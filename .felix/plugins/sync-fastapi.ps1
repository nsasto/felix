<#
.SYNOPSIS
FastAPI sync plugin for Felix run artifact synchronization

.DESCRIPTION
Implements the IRunReporter interface to sync run artifacts to a FastAPI backend.
Uses an outbox queue pattern with automatic retry on network failures for eventual consistency.
#>

# Source the sync interface for IRunReporter base class
# Handle different script sourcing scenarios (direct execution vs dot-sourcing)
$_syncFastapiScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$_syncInterfacePath = Join-Path (Split-Path $_syncFastapiScriptDir -Parent) "core\sync-interface.ps1"
if (-not (Test-Path $_syncInterfacePath)) {
    # Fallback: try relative to current location
    $_syncInterfacePath = Join-Path $PSScriptRoot "..\core\sync-interface.ps1"
}
. $_syncInterfacePath

#region Content Type Detection

function Get-ContentType {
    <#
    .SYNOPSIS
    Determine MIME content type from file extension
    
    .PARAMETER Path
    File path to check
    
    .OUTPUTS
    String content type
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    
    switch ($extension) {
        ".md" { return "text/markdown" }
        ".log" { return "text/plain; charset=utf-8" }
        ".txt" { return "text/plain; charset=utf-8" }
        ".patch" { return "text/x-patch" }
        ".json" { return "application/json" }
        ".ps1" { return "text/plain; charset=utf-8" }
        ".py" { return "text/x-python" }
        ".yaml" { return "text/yaml" }
        ".yml" { return "text/yaml" }
        ".xml" { return "application/xml" }
        ".html" { return "text/html" }
        ".css" { return "text/css" }
        ".js" { return "application/javascript" }
        ".ts" { return "application/typescript" }
        ".sh" { return "text/x-shellscript" }
        default { return "application/octet-stream" }
    }
}

#endregion

#region FastAPI Reporter Implementation

class FastApiReporter : IRunReporter {
    [string]$BaseUrl
    [string]$ApiKey
    [string]$OutboxPath
    [string]$FelixDir
    
    FastApiReporter([hashtable]$config, [string]$felixDir) {
        $this.BaseUrl = $config.base_url
        $this.ApiKey = $config.api_key
        $this.FelixDir = $felixDir
        $this.OutboxPath = Join-Path $felixDir "outbox"
        
        # Create outbox directory if it doesn't exist
        if (-not (Test-Path $this.OutboxPath)) {
            New-Item -ItemType Directory -Path $this.OutboxPath -Force | Out-Null
            Write-Verbose "Created outbox directory at $($this.OutboxPath)"
        }
        
        Write-Verbose "FastApiReporter initialized - BaseUrl: $($this.BaseUrl)"
    }
    
    [void] RegisterAgent([hashtable]$agentInfo) {
        $request = @{
            method   = "POST"
            endpoint = "/api/agents/register"
            body     = $agentInfo
        }
        
        $this.QueueRequest($request)
        $this.TrySendOutbox()
    }
    
    [string] StartRun([hashtable]$metadata) {
        # Generate client-side UUID for run_id
        $runId = [System.Guid]::NewGuid().ToString()
        
        # Add run_id to metadata
        $metadata["id"] = $runId
        
        $request = @{
            method   = "POST"
            endpoint = "/api/runs"
            body     = $metadata
        }
        
        $this.QueueRequest($request)
        $this.TrySendOutbox()
        
        return $runId
    }
    
    [void] AppendEvent([hashtable]$event) {
        # Extract run_id from event if present
        $runId = $event["run_id"]
        if (-not $runId) {
            Write-Warning "AppendEvent called without run_id in event"
            return
        }
        
        $this.AppendToRunOutbox($runId, $event)
    }
    
    [void] FinishRun([string]$runId, [hashtable]$result) {
        # First flush any pending events for this run
        $this.FlushRunEvents($runId)
        
        $request = @{
            method   = "POST"
            endpoint = "/api/runs/$runId/finish"
            body     = $result
        }
        
        $this.QueueRequest($request)
        $this.Flush()
    }
    
    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) {
        if (-not (Test-Path $localPath)) {
            Write-Warning "Artifact file not found: $localPath"
            return
        }
        
        # Calculate SHA256 hash
        $sha256 = $this.CalculateSHA256($localPath)
        $fileInfo = Get-Item $localPath
        
        $fileEntry = @{
            path         = $relativePath
            local_path   = $localPath
            sha256       = $sha256
            size_bytes   = $fileInfo.Length
            content_type = Get-ContentType -Path $localPath
        }
        
        # Queue as single file batch upload
        $this.QueueBatchUpload($runId, @($fileEntry))
    }
    
    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) {
        if (-not (Test-Path $runFolderPath)) {
            Write-Warning "Run folder not found: $runFolderPath"
            return
        }
        
        # Standard artifacts to look for
        $standardArtifacts = @(
            "plan-*.md",
            "report.md",
            "output.log",
            "output.txt",
            "prompt.md",
            "prompt.txt",
            "*.patch",
            "context.md",
            "context.txt"
        )
        
        $files = @()
        
        foreach ($pattern in $standardArtifacts) {
            $matches = Get-ChildItem -Path $runFolderPath -Filter $pattern -File -ErrorAction SilentlyContinue
            foreach ($match in $matches) {
                $relativePath = $match.Name
                $sha256 = $this.CalculateSHA256($match.FullName)
                
                $files += @{
                    path         = $relativePath
                    local_path   = $match.FullName
                    sha256       = $sha256
                    size_bytes   = $match.Length
                    content_type = Get-ContentType -Path $match.FullName
                }
            }
        }
        
        if ($files.Count -gt 0) {
            $this.QueueBatchUpload($runId, $files)
            Write-Verbose "Queued $($files.Count) artifacts from run folder"
        }
        else {
            Write-Verbose "No standard artifacts found in run folder"
        }
    }
    
    [void] Flush() {
        $this.TrySendOutbox()
    }
    
    #region Helper Methods
    
    hidden [string] CalculateSHA256([string]$filePath) {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $stream = [System.IO.File]::OpenRead($filePath)
            try {
                $hashBytes = $hasher.ComputeHash($stream)
                return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
            }
            finally {
                $stream.Close()
            }
        }
        finally {
            $hasher.Dispose()
        }
    }
    
    hidden [void] QueueRequest([hashtable]$request) {
        # Add timestamp for ordering
        $request["timestamp"] = [System.DateTime]::UtcNow.ToString("o")
        
        # Filename format: {timestamp}.jsonl
        $timestamp = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
        $filename = "$timestamp.jsonl"
        $filePath = Join-Path $this.OutboxPath $filename
        
        $json = $request | ConvertTo-Json -Depth 10 -Compress
        Add-Content -Path $filePath -Value $json -Encoding UTF8
        
        Write-Verbose "Queued request to $($request.endpoint)"
    }
    
    hidden [void] QueueBatchUpload([string]$runId, [array]$files) {
        # Batch upload filename format: {timestamp}-batch-upload.jsonl
        $timestamp = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
        $filename = "$timestamp-batch-upload.jsonl"
        $filePath = Join-Path $this.OutboxPath $filename
        
        $request = @{
            timestamp = [System.DateTime]::UtcNow.ToString("o")
            run_id    = $runId
            files     = $files
        }
        
        $json = $request | ConvertTo-Json -Depth 10 -Compress
        Add-Content -Path $filePath -Value $json -Encoding UTF8
        
        Write-Verbose "Queued batch upload for run $runId with $($files.Count) files"
    }
    
    hidden [void] AppendToRunOutbox([string]$runId, [hashtable]$event) {
        # Run-specific events use filename: run-{runId}.jsonl
        $filename = "run-$runId.jsonl"
        $filePath = Join-Path $this.OutboxPath $filename
        
        # Add timestamp if not present
        if (-not $event["timestamp"]) {
            $event["timestamp"] = [System.DateTime]::UtcNow.ToString("o")
        }
        
        $json = $event | ConvertTo-Json -Depth 10 -Compress
        Add-Content -Path $filePath -Value $json -Encoding UTF8
        
        Write-Verbose "Appended event to run outbox: $runId"
    }
    
    hidden [void] FlushRunEvents([string]$runId) {
        # Check for run-specific event file
        $filename = "run-$runId.jsonl"
        $filePath = Join-Path $this.OutboxPath $filename
        
        if (-not (Test-Path $filePath)) {
            return
        }
        
        # Read all events from the file
        $events = @()
        $lines = Get-Content -Path $filePath -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line.Trim()) {
                try {
                    $events += ($line | ConvertFrom-Json)
                }
                catch {
                    Write-Warning "Failed to parse event line: $line"
                }
            }
        }
        
        if ($events.Count -gt 0) {
            # Send events batch
            $success = $this.SendJsonRequest("POST", "/api/runs/$runId/events", @{ events = $events })
            
            if ($success) {
                # Delete the run events file
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
                Write-Verbose "Flushed $($events.Count) events for run $runId"
            }
        }
    }
    
    hidden [void] TrySendOutbox() {
        # List all .jsonl files in outbox sorted by name (oldest first)
        $outboxFiles = Get-ChildItem -Path $this.OutboxPath -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notlike "run-*.jsonl" } |  # Skip run event files (handled by FlushRunEvents)
            Sort-Object Name
        
        foreach ($file in $outboxFiles) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                $request = $content | ConvertFrom-Json
                
                # Detect batch upload requests by checking for files property
                if ($request.files) {
                    $success = $this.UploadBatch($request.run_id, $request.files)
                }
                else {
                    $success = $this.SendJsonRequest($request.method, $request.endpoint, $request.body)
                }
                
                if ($success) {
                    # Delete outbox file after successful send
                    Remove-Item -Path $file.FullName -Force
                    Write-Verbose "Successfully processed and removed: $($file.Name)"
                }
                else {
                    # Break loop on error, preserve remaining files for retry
                    Write-Warning "Failed to process $($file.Name) - will retry later"
                    break
                }
            }
            catch {
                Write-Warning "Error processing outbox file $($file.Name): $_"
                break
            }
        }
    }
    
    hidden [bool] SendJsonRequest([string]$method, [string]$endpoint, [object]$body) {
        $url = "$($this.BaseUrl)$endpoint"
        
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        if ($this.ApiKey) {
            $headers["Authorization"] = "Bearer $($this.ApiKey)"
        }
        
        try {
            $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
            
            $params = @{
                Method      = $method
                Uri         = $url
                Headers     = $headers
                Body        = $jsonBody
                TimeoutSec  = 10
                ContentType = "application/json"
            }
            
            $response = Invoke-RestMethod @params -ErrorAction Stop
            Write-Verbose "Request succeeded: $method $endpoint"
            return $true
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "Sync request failed: $method $endpoint - $errorMsg"
            return $false
        }
    }
    
    hidden [bool] UploadBatch([string]$runId, [array]$files) {
        $url = "$($this.BaseUrl)/api/runs/$runId/files"
        
        # Build manifest array
        $manifest = @()
        $validFiles = @()
        
        foreach ($file in $files) {
            $localPath = $file.local_path
            
            if (-not (Test-Path $localPath)) {
                Write-Warning "Skipping missing file: $localPath"
                continue
            }
            
            $manifest += @{
                path         = $file.path
                sha256       = $file.sha256
                size_bytes   = $file.size_bytes
                content_type = $file.content_type
            }
            
            $validFiles += $file
        }
        
        if ($manifest.Count -eq 0) {
            Write-Verbose "No valid files to upload in batch"
            return $true  # Consider success if nothing to upload
        }
        
        try {
            # Build multipart form data
            $boundary = [System.Guid]::NewGuid().ToString()
            $contentType = "multipart/form-data; boundary=$boundary"
            
            $bodyLines = @()
            
            # Add manifest as JSON
            $manifestJson = $manifest | ConvertTo-Json -Depth 10 -Compress
            $bodyLines += "--$boundary"
            $bodyLines += 'Content-Disposition: form-data; name="manifest"'
            $bodyLines += 'Content-Type: application/json'
            $bodyLines += ''
            $bodyLines += $manifestJson
            
            # Add each file
            foreach ($file in $validFiles) {
                $fileContent = [System.IO.File]::ReadAllBytes($file.local_path)
                $fileBase64 = [System.Convert]::ToBase64String($fileContent)
                
                $bodyLines += "--$boundary"
                $bodyLines += "Content-Disposition: form-data; name=`"$($file.path)`"; filename=`"$($file.path)`""
                $bodyLines += "Content-Type: $($file.content_type)"
                $bodyLines += "Content-Transfer-Encoding: base64"
                $bodyLines += ''
                $bodyLines += $fileBase64
            }
            
            $bodyLines += "--$boundary--"
            
            $body = $bodyLines -join "`r`n"
            
            $headers = @{}
            if ($this.ApiKey) {
                $headers["Authorization"] = "Bearer $($this.ApiKey)"
            }
            
            # Use WebRequest for multipart form data
            $params = @{
                Method      = "POST"
                Uri         = $url
                Headers     = $headers
                Body        = $body
                ContentType = $contentType
                TimeoutSec  = 120
            }
            
            $response = Invoke-RestMethod @params -ErrorAction Stop
            Write-Verbose "Batch upload succeeded for run $runId with $($validFiles.Count) files"
            return $true
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "Batch upload failed for run $runId - $errorMsg"
            return $false
        }
    }
    
    #endregion
}

#endregion

#region Plugin Factory

function New-PluginReporter {
    <#
    .SYNOPSIS
    Create a new FastApiReporter instance
    
    .PARAMETER Config
    Hashtable containing base_url and api_key configuration
    
    .PARAMETER FelixDir
    Path to the .felix directory
    
    .OUTPUTS
    FastApiReporter instance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$FelixDir
    )
    
    return [FastApiReporter]::new($Config, $FelixDir)
}

#endregion

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
# Go up two levels: sync-http/ -> plugins/ -> .felix/
$_felixDir = Split-Path (Split-Path $_syncFastapiScriptDir -Parent) -Parent
$_syncInterfacePath = Join-Path $_felixDir "core\sync-interface.ps1"
if (-not (Test-Path $_syncInterfacePath)) {
    # Fallback: try relative to current location
    $_syncInterfacePath = Join-Path $PSScriptRoot "..\..\core\sync-interface.ps1"
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

#region HTTP Sync Implementation

class HttpSync : IRunReporter {
    [string]$BaseUrl
    [string]$ApiKey
    [string]$OutboxPath
    [string]$FelixDir
    [string]$LogPath
    [int]$MaxLogSizeBytes = 5242880  # 5MB max log size
    [bool]$IsConfigValid = $false
    
    HttpSync([hashtable]$config, [string]$felixDir) {
        $this.FelixDir = $felixDir
        $this.OutboxPath = Join-Path $felixDir "outbox"
        $this.LogPath = Join-Path $felixDir "sync.log"
        
        # Validate configuration
        $configErrors = @()
        
        if (-not $config) {
            $configErrors += "Configuration is null or empty"
        }
        else {
            if (-not $config.base_url) {
                $configErrors += "Missing required 'base_url' in sync configuration"
            }
            elseif ($config.base_url -notmatch '^https?://') {
                $configErrors += "Invalid 'base_url': must start with http:// or https://"
            }
            else {
                $this.BaseUrl = $config.base_url
            }
            
            # API key is required - validated upstream in sync-interface.ps1
            if (-not $config.api_key) {
                $configErrors += "Missing required 'api_key' in sync configuration"
            }
            else {
                $this.ApiKey = $config.api_key
            }
        }
        
        if ($configErrors.Count -gt 0) {
            $errorMsg = "Sync plugin configuration error: $($configErrors -join '; ')"
            $this.WriteLog("ERROR", $errorMsg)
            $this.WriteLog("ERROR", "Sync requests will be queued locally but will fail to send until configuration is fixed.")
            $this.WriteLog("ERROR", "Required configuration: { `"base_url`": `"http://your-server:8080`", `"api_key`": `"fsk_...`" } in .felix/config.json under sync")
            $this.IsConfigValid = $false
            
            # Emit visible error to console
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "error" -Message "Sync configuration invalid: $($configErrors -join '; ')" -Component "sync" | Out-Null
            }
            else {
                Write-Warning "Sync configuration invalid: $($configErrors -join '; ')"
            }
        }
        else {
            $this.IsConfigValid = $true
        }
        
        # Create outbox directory if it doesn't exist
        try {
            if (-not (Test-Path $this.OutboxPath)) {
                New-Item -ItemType Directory -Path $this.OutboxPath -Force | Out-Null
            }
        }
        catch {
            $this.WriteLog("ERROR", "Failed to create outbox directory: $_")
        }
    }
    
    #region Logging with Rotation
    
    hidden [void] WriteLog([string]$level, [string]$message) {
        # Rotate log if needed
        $this.RotateLogIfNeeded()
        
        $timestamp = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $logEntry = "[$timestamp] [$level] $message"
        
        try {
            Add-Content -Path $this.LogPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail if unable to write log
        }
    }
    
    hidden [void] RotateLogIfNeeded() {
        if (-not (Test-Path $this.LogPath)) {
            return
        }
        
        try {
            $logFile = Get-Item $this.LogPath -ErrorAction SilentlyContinue
            if ($logFile -and $logFile.Length -ge $this.MaxLogSizeBytes) {
                # Rotate: rename current log to .old and start fresh
                $oldLogPath = "$($this.LogPath).old"
                if (Test-Path $oldLogPath) {
                    Remove-Item -Path $oldLogPath -Force -ErrorAction SilentlyContinue
                }
                Move-Item -Path $this.LogPath -Destination $oldLogPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Silently fail if rotation fails
        }
    }
    
    #endregion
    
    [void] RegisterAgent([hashtable]$agentInfo) {
        try {
            $request = @{
                method   = "POST"
                endpoint = "/api/agents/register-sync"
                body     = $agentInfo
            }
            
            $this.WriteLog("INFO", "Queueing agent registration request (API key auth)")
            $this.QueueRequest($request)
            $this.WriteLog("INFO", "Attempting to send agent registration")
            $this.TrySendOutbox()
        }
        catch {
            $this.WriteLog("WARNING", "Failed to queue agent registration: $_")
            # Don't rethrow - prevent agent crash
        }
    }
    
    [string] StartRun([hashtable]$metadata) {
        # Generate client-side UUID for run_id - always do this even if queueing fails
        $runId = [System.Guid]::NewGuid().ToString()
        
        try {
            # Add run_id to metadata
            $metadata["id"] = $runId
            
            $request = @{
                method   = "POST"
                endpoint = "/api/runs"
                body     = $metadata
            }
            
            $this.QueueRequest($request)
            $this.WriteLog("INFO", "Attempting to send run creation for $runId")
            $this.TrySendOutbox()
        }
        catch {
            $errorMsg = $_.Exception.Message
            $this.WriteLog("WARNING", "Failed to queue run start for $runId`: $errorMsg")
            
            # Emit visible warning to user
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "warn" -Message "Failed to sync run creation: $errorMsg" -Component "sync" | Out-Null
            }
            # Don't rethrow - return runId so agent can continue
        }
        
        return $runId
    }
    
    [void] AppendEvent([hashtable]$event) {
        try {
            # Extract run_id from event if present
            $runId = $event["run_id"]
            if (-not $runId) {
                $this.WriteLog("WARNING", "AppendEvent called without run_id in event")
                return
            }
            
            $this.AppendToRunOutbox($runId, $event)
        }
        catch {
            $errorMsg = $_.Exception.Message
            $this.WriteLog("WARNING", "Failed to queue event: $errorMsg")
            
            # Emit warning for event queueing failures (may indicate disk issues)
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "warn" -Message "Failed to queue sync event: $errorMsg" -Component "sync" | Out-Null
            }
            # Don't rethrow - prevent agent crash
        }
    }
    
    [void] FinishRun([string]$runId, [hashtable]$result) {
        try {
            # First flush any pending events for this run
            $this.FlushRunEvents($runId)
            
            $request = @{
                method   = "POST"
                endpoint = "/api/runs/$runId/finish"
                body     = $result
            }
            
            $this.QueueRequest($request)
            $this.WriteLog("INFO", "Queueing run completion for $runId (status: $($result.status))")
            $this.Flush()
        }
        catch {
            $errorMsg = $_.Exception.Message
            $this.WriteLog("WARNING", "Failed to queue run finish for $runId`: $errorMsg")
            
            # Emit visible warning to user for run completion failures
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "warn" -Message "Failed to sync run completion: $errorMsg" -Component "sync" | Out-Null
            }
            # Don't rethrow - prevent agent crash
        }
    }
    
    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) {
        try {
            if (-not (Test-Path $localPath)) {
                $this.WriteLog("WARNING", "Artifact file not found: $localPath")
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
        catch {
            $errorMsg = $_.Exception.Message
            $this.WriteLog("WARNING", "Failed to queue artifact upload for $relativePath`: $errorMsg")
            
            # Emit warning for artifact upload failures
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "warn" -Message "Failed to queue artifact upload: $errorMsg" -Component "sync" | Out-Null
            }
            # Don't rethrow - prevent agent crash
        }
    }
    
    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) {
        try {
            if (-not (Test-Path $runFolderPath)) {
                $this.WriteLog("WARNING", "Run folder not found: $runFolderPath")
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
            }
        }
        catch {
            $this.WriteLog("WARNING", "Failed to queue run folder upload for $runId`: $_")
            # Don't rethrow - prevent agent crash
        }
    }
    
    [void] Flush() {
        try {
            $this.TrySendOutbox()
        }
        catch {
            $this.WriteLog("WARNING", "Error during outbox flush: $_")
            # Don't rethrow - prevent agent crash
        }
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
        catch {
            $this.WriteLog("WARNING", "Failed to calculate SHA256 for $filePath`: $_")
            throw  # Re-throw - caller needs to handle missing hash
        }
        finally {
            $hasher.Dispose()
        }
    }
    
    hidden [void] QueueRequest([hashtable]$request) {
        try {
            # Add timestamp for ordering
            $request["timestamp"] = [System.DateTime]::UtcNow.ToString("o")
            
            # Filename format: {timestamp}.jsonl
            $timestamp = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
            $filename = "$timestamp.jsonl"
            $filePath = Join-Path $this.OutboxPath $filename
            
            $json = $request | ConvertTo-Json -Depth 10 -Compress
            Add-Content -Path $filePath -Value $json -Encoding UTF8
        }
        catch {
            $this.WriteLog("WARNING", "Failed to queue request to $($request.endpoint): $_")
            throw
        }
    }
    
    hidden [void] QueueBatchUpload([string]$runId, [array]$files) {
        try {
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
        }
        catch {
            $this.WriteLog("WARNING", "Failed to queue batch upload for run $runId`: $_")
            throw  # Re-throw to let caller handle it
        }
    }
    
    hidden [void] AppendToRunOutbox([string]$runId, [hashtable]$event) {
        try {
            # Run-specific events use filename: run-{runId}.jsonl
            $filename = "run-$runId.jsonl"
            $filePath = Join-Path $this.OutboxPath $filename
            
            # Add timestamp if not present
            if (-not $event["timestamp"]) {
                $event["timestamp"] = [System.DateTime]::UtcNow.ToString("o")
            }
            
            $json = $event | ConvertTo-Json -Depth 10 -Compress
            Add-Content -Path $filePath -Value $json -Encoding UTF8
        }
        catch {
            $this.WriteLog("WARNING", "Failed to append event to run outbox $runId`: $_")
            throw  # Re-throw to let caller handle it
        }
    }
    
    hidden [void] FlushRunEvents([string]$runId) {
        try {
            # Check for run-specific event file
            $filename = "run-$runId.jsonl"
            $filePath = Join-Path $this.OutboxPath $filename
            
            if (-not (Test-Path $filePath)) {
                return
            }
            
            # Read all events from the file
            $events = @()
            $skippedLines = 0
            $lines = Get-Content -Path $filePath -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line.Trim()) {
                    try {
                        $events += ($line | ConvertFrom-Json)
                    }
                    catch {
                        $skippedLines++
                        $this.WriteLog("WARNING", "Skipping corrupted event line in run-$runId.jsonl")
                    }
                }
            }
            
            if ($skippedLines -gt 0) {
                $this.WriteLog("WARNING", "Skipped $skippedLines corrupted event lines for run $runId")
            }
            
            if ($events.Count -gt 0) {
                # Send events batch
                $this.WriteLog("INFO", "Flushing $($events.Count) queued events for run $runId")
                $success = $this.SendJsonRequest("POST", "/api/runs/$runId/events", @{ events = $events })
                
                if ($success) {
                    $this.WriteLog("INFO", "Successfully flushed $($events.Count) events for run $runId")
                    # Delete the run events file
                    Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
                }
                else {
                    $this.WriteLog("WARNING", "Failed to flush events for run $runId - will retry later")
                }
            }
            elseif ($skippedLines -gt 0 -and $events.Count -eq 0) {
                # All lines were corrupted - remove the file to prevent repeated failures
                $this.WriteLog("WARNING", "All events in run-$runId.jsonl were corrupted - removing file")
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            $this.WriteLog("WARNING", "Error flushing events for run $runId`: $_")
            # Don't rethrow - continue with other operations
        }
    }
    
    hidden [int] GetMaxRetries() {
        # Check environment variable for max retry attempts
        $envMaxRetries = $env:FELIX_SYNC_MAX_RETRIES
        if ($envMaxRetries -and $envMaxRetries -match '^\d+$') {
            return [int]$envMaxRetries
        }
        return 5  # Default: 5 attempts (delays: 1s, 2s, 4s, 8s, 16s)
    }
    
    hidden [bool] IsTransientError([int]$statusCode, [string]$errorMessage) {
        # Transient errors are retryable: network issues, server overload, etc.
        # Status codes: 429 (rate limited), 500 (server error), 502, 503, 504 (gateway/unavailable)
        $transientStatusCodes = @(429, 500, 502, 503, 504)
        
        if ($statusCode -in $transientStatusCodes) {
            return $true
        }
        
        # Network-related errors are transient
        $transientPatterns = @(
            "Unable to connect",
            "Connection refused",
            "Connection timed out",
            "Network is unreachable",
            "No route to host",
            "DNS",
            "timeout",
            "temporarily unavailable"
        )
        
        foreach ($pattern in $transientPatterns) {
            if ($errorMessage -match $pattern) {
                return $true
            }
        }
        
        return $false
    }
    
    hidden [bool] IsPermanentError([int]$statusCode) {
        # Permanent errors should not be retried: bad request, unauthorized, not found, etc.
        # Status codes: 400 (bad request), 401 (unauthorized), 403 (forbidden), 404 (not found), 422 (unprocessable)
        $permanentStatusCodes = @(400, 401, 403, 404, 422)
        return $statusCode -in $permanentStatusCodes
    }
    
    hidden [void] TrySendOutbox() {
        # Check if config is valid before attempting to send
        if (-not $this.IsConfigValid) {
            # Emit visible warning on first failure
            if (-not $script:SyncConfigWarningShown) {
                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                    Emit-Log -Level "warn" -Message "Sync configuration invalid - requests queued locally but not sent" -Component "sync" | Out-Null
                }
                $script:SyncConfigWarningShown = $true
            }
            # Silently skip sending - requests remain queued for when config is fixed
            return
        }
        
        # List all .jsonl files in outbox sorted by name (oldest first)
        $outboxFiles = $null
        try {
            $outboxFiles = Get-ChildItem -Path $this.OutboxPath -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notlike "run-*.jsonl" } |  # Skip run event files (handled by FlushRunEvents)
            Sort-Object Name
        }
        catch {
            $this.WriteLog("WARNING", "Failed to list outbox files: $_")
            return
        }
        
        if (-not $outboxFiles -or $outboxFiles.Count -eq 0) {
            return
        }
        
        $maxRetries = $this.GetMaxRetries()
        
        foreach ($file in $outboxFiles) {
            $attempt = 0
            $success = $false
            $lastError = $null
            $lastStatusCode = 0
            $isPermanentFailure = $false
            
            while (-not $success -and $attempt -lt $maxRetries) {
                $attempt++
                
                # Exponential backoff delay (except first attempt)
                if ($attempt -gt 1) {
                    $delaySeconds = [Math]::Pow(2, $attempt - 1)  # 1s, 2s, 4s, 8s, 16s
                    $this.WriteLog("INFO", "Retry attempt $attempt/$maxRetries for $($file.Name) after ${delaySeconds}s delay")
                    Start-Sleep -Seconds $delaySeconds
                }
                
                try {
                    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                    if (-not $content -or $content.Trim() -eq "") {
                        $this.WriteLog("WARNING", "Skipping empty outbox file: $($file.Name)")
                        $success = $true  # Remove empty files
                        continue
                    }
                    
                    $request = $null
                    try {
                        $request = $content | ConvertFrom-Json
                    }
                    catch {
                        $this.WriteLog("ERROR", "Corrupt JSON in outbox file $($file.Name): $_")
                        # Mark as permanent failure - corrupted files won't become valid
                        $isPermanentFailure = $true
                        break
                    }
                    
                    # Detect batch upload requests by checking for files property
                    $result = $null
                    if ($request.files) {
                        $result = $this.UploadBatchWithStatus($request.run_id, $request.files)
                    }
                    else {
                        $result = $this.SendJsonRequestWithStatus($request.method, $request.endpoint, $request.body)
                    }
                    
                    if ($result.Success) {
                        $success = $true
                        $this.WriteLog("INFO", "Successfully sent $($file.Name)")
                    }
                    else {
                        $lastError = $result.Error
                        $lastStatusCode = $result.StatusCode
                        
                        # Check if this is a permanent error (don't retry)
                        if ($this.IsPermanentError($result.StatusCode)) {
                            $this.WriteLog("ERROR", "Permanent error for $($file.Name): HTTP $($result.StatusCode) - $lastError")
                            $isPermanentFailure = $true
                            break
                        }
                        
                        # Check if this is a transient error (retry with backoff)
                        if ($this.IsTransientError($result.StatusCode, $lastError)) {
                            $this.WriteLog("WARNING", "Transient error for $($file.Name): HTTP $($result.StatusCode) - $lastError (attempt $attempt/$maxRetries)")
                            
                            # Emit visible warning on first failure for critical operations
                            if ($attempt -eq 1 -and ($file.Name -match "^\d{17}" -or $file.Name -match "agent")) {
                                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                                    Emit-Log -Level "warn" -Message "Sync error (HTTP $($result.StatusCode)): $lastError - retrying..." -Component "sync" | Out-Null
                                }
                            }
                        }
                        else {
                            # Unknown error type - treat as transient but log it
                            $this.WriteLog("WARNING", "Unknown error for $($file.Name): HTTP $($result.StatusCode) - $lastError (attempt $attempt/$maxRetries)")
                            
                            # Emit visible warning on first failure for critical operations
                            if ($attempt -eq 1 -and ($file.Name -match "^\d{17}" -or $file.Name -match "agent")) {
                                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                                    Emit-Log -Level "warn" -Message "Sync error: $lastError - retrying..." -Component "sync" | Out-Null
                                }
                            }
                        }
                    }
                }
                catch {
                    $lastError = $_.Exception.Message
                    
                    # Check if this looks like a transient network error
                    if ($this.IsTransientError(0, $lastError)) {
                        $this.WriteLog("WARNING", "Network error for $($file.Name): $lastError (attempt $attempt/$maxRetries)")
                    }
                    else {
                        $this.WriteLog("ERROR", "Unexpected error processing $($file.Name): $lastError")
                    }
                }
            }
            
            if ($success) {
                # Delete outbox file after successful send
                try {
                    Remove-Item -Path $file.FullName -Force
                }
                catch {
                    $this.WriteLog("WARNING", "Failed to delete processed file $($file.Name): $_")
                }
            }
            elseif ($isPermanentFailure) {
                # Check if this was a corrupt JSON file - skip it and continue to next
                if ($lastError -match "Corrupt JSON") {
                    $this.WriteLog("WARNING", "Skipping corrupted outbox file $($file.Name) - file will be retained for investigation")
                    # Continue to next file - corrupted files won't magically fix themselves
                    continue
                }
                # Permanent API failure - keep file in outbox but continue to next file
                $this.WriteLog("WARNING", "Permanent API failure for $($file.Name) - file remains in outbox")
                
                # Notify user of permanent failure for critical operations (run files, agent registration, batch uploads)
                # Pattern matches: 20260218191241123.jsonl (timestamp), 20260218191241123-batch-upload.jsonl, or agent files
                if ($file.Name -match "^\d{17}" -or $file.Name -match "agent") {
                    if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                        Emit-Log -Level "error" -Message "Sync permanently failed (HTTP $lastStatusCode): $lastError" -Component "sync" | Out-Null
                    }
                }
                # Continue to next file - don't block other requests
            }
            else {
                # Transient failure after max retries - keep file in outbox
                $this.WriteLog("WARNING", "Max retries ($maxRetries) exceeded for $($file.Name) - file remains in outbox, will retry later")
                
                # Notify user that sync is having issues with critical operations
                # Pattern matches: 20260218191241123.jsonl (timestamp), batch uploads, or agent files
                if ($file.Name -match "^\d{17}" -or $file.Name -match "agent") {
                    if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                        Emit-Log -Level "warn" -Message "Sync operation failed after $maxRetries retries - will retry later" -Component "sync" | Out-Null
                    }
                }
                # Don't break - continue trying other files that might succeed
                # This is more resilient than blocking all syncs when one file fails
            }
        }
    }
    
    hidden [bool] SendJsonRequest([string]$method, [string]$endpoint, [object]$body) {
        $result = $this.SendJsonRequestWithStatus($method, $endpoint, $body)
        return $result.Success
    }
    
    hidden [hashtable] SendJsonRequestWithStatus([string]$method, [string]$endpoint, [object]$body) {
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
            return @{
                Success    = $true
                StatusCode = 200
                Error      = $null
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $statusCode = 0
            
            # Try to extract HTTP status code from WebException
            if ($_.Exception.Response) {
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                    
                    # Try to read response body for detailed error message
                    $responseStream = $_.Exception.Response.GetResponseStream()
                    if ($responseStream) {
                        $reader = New-Object System.IO.StreamReader($responseStream)
                        $responseBody = $reader.ReadToEnd()
                        $reader.Close()
                        
                        # Try to parse as JSON and extract detail field
                        try {
                            $errorJson = $responseBody | ConvertFrom-Json
                            if ($errorJson.detail) {
                                $errorMsg = $errorJson.detail
                            }
                        }
                        catch {
                            # Not JSON or no detail field - keep original error message
                        }
                    }
                }
                catch {
                    # Ignore response reading failures - keep original error message
                }
            }
            
            # Also check for status code in the error message (PowerShell 7+)
            if ($statusCode -eq 0 -and $errorMsg -match 'Response status code does not indicate success: (\d+)') {
                $statusCode = [int]$Matches[1]
            }
            
            # Check ErrorDetails.Message for response body (PowerShell Core)
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try {
                    $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
                    if ($errorJson.detail) { $errorMsg = $errorJson.detail }
                } catch { }
            }
            
            $this.WriteLog("ERROR", "Sync request failed: $method $endpoint - HTTP $statusCode - $errorMsg")
            
            # Emit visible error for critical operations like agent registration
            if ($endpoint -eq "/api/agents/register-sync") {
                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                    Emit-Log -Level "error" -Message "Agent registration HTTP request failed: $errorMsg" -Component "sync" | Out-Null
                }
            }
            
            return @{
                Success    = $false
                StatusCode = $statusCode
                Error      = $errorMsg
            }
        }
    }
    
    hidden [bool] UploadBatch([string]$runId, [array]$files) {
        $result = $this.UploadBatchWithStatus($runId, $files)
        return $result.Success
    }
    
    hidden [hashtable] UploadBatchWithStatus([string]$runId, [array]$files) {
        $url = "$($this.BaseUrl)/api/runs/$runId/files"
        
        # Build manifest array
        $manifest = @()
        $validFiles = @()
        
        foreach ($file in $files) {
            $localPath = $file.local_path
            
            if (-not (Test-Path $localPath)) {
                $this.WriteLog("WARN", "Skipping missing file: $localPath")
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
            return @{
                Success    = $true
                StatusCode = 200
                Error      = $null
            }  # Consider success if nothing to upload
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
            return @{
                Success    = $true
                StatusCode = 200
                Error      = $null
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $statusCode = 0
            
            # Try to extract HTTP status code from WebException
            if ($_.Exception.Response) {
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                catch {
                    # Ignore status code extraction failures
                }
            }
            
            # Also check for status code in the error message (PowerShell 7+)
            if ($statusCode -eq 0 -and $errorMsg -match 'Response status code does not indicate success: (\d+)') {
                $statusCode = [int]$Matches[1]
            }
            
            # Check ErrorDetails.Message for response body (PowerShell Core)
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try {
                    $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
                    if ($errorJson.detail) { $errorMsg = $errorJson.detail }
                } catch { }
            }
            
            $this.WriteLog("ERROR", "Batch upload failed for run $runId - HTTP $statusCode - $errorMsg")
            return @{
                Success    = $false
                StatusCode = $statusCode
                Error      = $errorMsg
            }
        }
    }
    
    #endregion
}

#endregion

#region Plugin Factory

function New-PluginReporter {
    <#
    .SYNOPSIS
    Create a new HttpSync instance
    
    .PARAMETER Config
    Hashtable containing base_url and api_key configuration
    
    .PARAMETER FelixDir
    Path to the .felix directory
    
    .OUTPUTS
    HttpSync instance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$FelixDir
    )
    
    return [HttpSync]::new($Config, $FelixDir)
}

#endregion

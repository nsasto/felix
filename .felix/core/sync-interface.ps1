<#
.SYNOPSIS
Sync interface definitions for Felix run artifact synchronization

.DESCRIPTION
Defines the IRunReporter interface and provides factory functions for creating
sync reporter instances. This enables optional pushing of run artifacts to
a server via an outbox queue pattern with automatic retry on network failures.
#>

# Abstract base class defining the sync reporter interface
class IRunReporter {
    <#
    .SYNOPSIS
    Register agent with sync server
    
    .PARAMETER agentInfo
    Hashtable containing agent_id, hostname, platform, version, felix_root
    #>
    [void] RegisterAgent([hashtable]$agentInfo) {
        throw [System.NotImplementedException]::new("RegisterAgent must be implemented by derived class")
    }
    
    <#
    .SYNOPSIS
    Start a new run and return the run ID
    
    .PARAMETER metadata
    Hashtable containing run metadata (requirement_id, agent_id, etc.)
    
    .OUTPUTS
    String run ID (client-generated UUID)
    #>
    [string] StartRun([hashtable]$metadata) {
        throw [System.NotImplementedException]::new("StartRun must be implemented by derived class")
    }
    
    <#
    .SYNOPSIS
    Append an event to the current run
    
    .PARAMETER event
    Hashtable containing event data
    #>
    [void] AppendEvent([hashtable]$event) {
        throw [System.NotImplementedException]::new("AppendEvent must be implemented by derived class")
    }
    
    <#
    .SYNOPSIS
    Finish a run with final result
    
    .PARAMETER runId
    The run ID to finish
    
    .PARAMETER result
    Hashtable containing final result data (status, exit_code, etc.)
    #>
    [void] FinishRun([string]$runId, [hashtable]$result) {
        throw [System.NotImplementedException]::new("FinishRun must be implemented by derived class")
    }
    
    <#
    .SYNOPSIS
    Upload a single artifact file
    
    .PARAMETER runId
    The run ID to associate the artifact with
    
    .PARAMETER relativePath
    Relative path for the artifact (e.g., "plan.md")
    
    .PARAMETER localPath
    Local file system path to the artifact
    #>
    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) {
        throw [System.NotImplementedException]::new("UploadArtifact must be implemented by derived class")
    }
    
    <#
    .SYNOPSIS
    Upload all artifacts from a run folder
    
    .PARAMETER runId
    The run ID to associate artifacts with
    
    .PARAMETER runFolderPath
    Path to the local run folder containing artifacts
    #>
    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) {
        throw [System.NotImplementedException]::new("UploadRunFolder must be implemented by derived class")
    }
    
    <#
    .SYNOPSIS
    Force delivery of all pending items in outbox
    #>
    [void] Flush() {
        throw [System.NotImplementedException]::new("Flush must be implemented by derived class")
    }
}

# No-op implementation when sync is disabled
class NoOpReporter : IRunReporter {
    NoOpReporter() {
        Write-Verbose "Sync disabled - using NoOpReporter"
    }
    
    [void] RegisterAgent([hashtable]$agentInfo) {
        # No-op
    }
    
    [string] StartRun([hashtable]$metadata) {
        # Return empty string - no sync happening
        return ""
    }
    
    [void] AppendEvent([hashtable]$event) {
        # No-op
    }
    
    [void] FinishRun([string]$runId, [hashtable]$result) {
        # No-op
    }
    
    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) {
        # No-op
    }
    
    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) {
        # No-op
    }
    
    [void] Flush() {
        # No-op
    }
}

function Get-RunReporter {
    <#
    .SYNOPSIS
    Factory function to create the appropriate run reporter instance
    
    .DESCRIPTION
    Returns a NoOpReporter when sync is disabled or config is missing.
    Returns a configured plugin reporter when sync is enabled.
    Checks both config file and FELIX_SYNC_ENABLED environment variable.
    
    .PARAMETER FelixDir
    Path to the .felix directory (optional, defaults to script root parent)
    
    .OUTPUTS
    IRunReporter instance (NoOpReporter or HttpSync)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FelixDir = $null
    )
    
    # Resolve Felix directory
    if (-not $FelixDir) {
        $FelixDir = Split-Path $PSScriptRoot -Parent
    }
    
    $configPath = Join-Path $FelixDir "config.json"
    
    # Check if config file exists
    if (-not (Test-Path $configPath)) {
        Write-Verbose "Config file not found at $configPath - sync disabled"
        return [NoOpReporter]::new()
    }
    
    # Load config
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Verbose "Failed to load config: $_ - sync disabled"
        return [NoOpReporter]::new()
    }
    
    # Check environment variable override first (takes precedence)
    $envEnabled = $env:FELIX_SYNC_ENABLED
    if ($envEnabled -eq "false" -or $envEnabled -eq "0") {
        Write-Verbose "FELIX_SYNC_ENABLED=$envEnabled - sync disabled by environment"
        return [NoOpReporter]::new()
    }
    
    # Check config for sync settings
    $syncEnabled = $false
    $syncConfig = $null
    
    if ($config.sync) {
        $syncConfig = $config.sync
        
        # Environment variable can enable sync even if config says disabled
        if ($envEnabled -eq "true" -or $envEnabled -eq "1") {
            $syncEnabled = $true
        }
        elseif ($syncConfig.enabled -eq $true) {
            $syncEnabled = $true
        }
    }
    elseif ($envEnabled -eq "true" -or $envEnabled -eq "1") {
        # Environment variable enabled but no config section - use defaults
        $syncEnabled = $true
        $syncConfig = @{
            provider = "fastapi"
            base_url = if ($env:FELIX_SYNC_URL) { $env:FELIX_SYNC_URL } else { "http://localhost:8080" }
            api_key  = $env:FELIX_SYNC_KEY
        }
    }
    
    if (-not $syncEnabled) {
        Write-Verbose "Sync not enabled in config or environment"
        return [NoOpReporter]::new()
    }
    
    # Build final sync config with environment variable overrides
    $finalConfig = @{
        base_url = if ($env:FELIX_SYNC_URL) { $env:FELIX_SYNC_URL } elseif ($syncConfig.base_url) { $syncConfig.base_url } else { "http://localhost:8080" }
        api_key  = if ($env:FELIX_SYNC_KEY) { $env:FELIX_SYNC_KEY } elseif ($syncConfig.api_key) { $syncConfig.api_key } else { $null }
    }
    
    # Validate API key is provided when sync is enabled
    if (-not $finalConfig.api_key) {
        Write-Error @"
Sync enabled but no API key configured.

To fix this issue, choose one of the following options:

1. Set environment variable:
   `$env:FELIX_SYNC_KEY = "fsk_your_key_here"

2. Add to .felix/config.json:
   {
     "sync": {
       "enabled": true,
       "provider": "fastapi",
       "base_url": "$($finalConfig.base_url)",
       "api_key": "fsk_your_key_here"
     }
   }

To generate an API key:
- Open Felix UI at http://localhost:3000
- Navigate to your project settings
- Go to "API Keys" tab
- Click "Generate New Key"

For development without sync, set sync.enabled=false in .felix/config.json
"@
        throw "API key required when sync is enabled. Set FELIX_SYNC_KEY environment variable or sync.api_key in config.json"
    }
    
    # Determine which plugin to load
    $provider = if ($syncConfig.provider) { $syncConfig.provider } else { "http" }
    
    # Load the plugin based on provider
    switch ($provider) {
        { $_ -in @("http", "fastapi") } {
            # Support both "http" (new) and "fastapi" (legacy) for backward compatibility
            $pluginPath = Join-Path $FelixDir "plugins\sync-http.ps1"
            if (-not (Test-Path $pluginPath)) {
                Write-Warning "Sync plugin not found at $pluginPath - falling back to NoOpReporter"
                return [NoOpReporter]::new()
            }
            
            try {
                . $pluginPath
                
                # Plugin should export New-PluginReporter function
                if (-not (Get-Command "New-PluginReporter" -ErrorAction SilentlyContinue)) {
                    Write-Warning "Sync plugin missing New-PluginReporter function - falling back to NoOpReporter"
                    return [NoOpReporter]::new()
                }
                
                $reporter = New-PluginReporter -Config $finalConfig -FelixDir $FelixDir
                Write-Verbose "Sync enabled using $provider provider"
                return $reporter
            }
            catch {
                Write-Warning "Failed to load sync plugin: $_ - falling back to NoOpReporter"
                return [NoOpReporter]::new()
            }
        }
        default {
            Write-Warning "Unknown sync provider '$provider' - falling back to NoOpReporter"
            return [NoOpReporter]::new()
        }
    }
}

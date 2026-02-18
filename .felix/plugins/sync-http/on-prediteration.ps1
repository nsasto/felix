<#
.SYNOPSIS
OnPreIteration hook: Initialize run tracking

.DESCRIPTION
Creates run record on first iteration and starts event flush timer
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$HookName,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    [hashtable]$Data,
    
    [Parameter(Mandatory = $false)]
    $Config = @{}
)

# Load shared state
. "$PSScriptRoot/sync-state.ps1"

# Only act on first iteration
if ($Data.Iteration -ne 1) {
    return @{ ShouldContinue = $true }
}

try {
    # Initialize client if not already done
    if (-not $Global:HttpSyncState.Client) {
        # Get Felix config from parent scope/context
        $felixConfig = $Data.Config
        $felixDir = $Data.Paths.FelixDir
        
        Initialize-HttpSyncClient -Config $felixConfig -FelixDir $felixDir
    }
    
    # Record start time
    $Global:HttpSyncState.RunStartTime = Get-Date
    
    # Extract git URL for project identity
    $gitUrl = $null
    try {
        $gitUrl = git config --get remote.origin.url 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $gitUrl) {
            Emit-Log -Level "warn" -Message "No git remote origin configured - project identity unavailable" -Component "sync" | Out-Null
        }
    }
    catch {
        Emit-Log -Level "warn" -Message "Failed to read git remote URL: $_" -Component "sync" | Out-Null
    }
    
    # Create run record
    $runData = @{
        requirement_id = $Data.Requirement.id
        agent_id = $Data.AgentConfig.id
    }
    
    # Add git_url for project authentication (preferred over project_id)
    if ($gitUrl) {
        $runData.git_url = $gitUrl.Trim()
    }
    
    $syncRunId = $Global:HttpSyncState.Client.StartRun($runData)
    $Global:HttpSyncState.RunId = $syncRunId
    
    # Start event flush timer
    $flushInterval = if ($Config.event_batch_interval) { $Config.event_batch_interval } else { 5 }
    Start-EventFlushTimer -IntervalSeconds $flushInterval
    
    Emit-Log -Level "info" -Message "Run started: $syncRunId (flush interval: ${flushInterval}s)" -Component "sync" | Out-Null
    
    return @{ ShouldContinue = $true; RunId = $syncRunId }
}
catch {
    Emit-Log -Level "warn" -Message "[sync-http] Failed to start run: $_" -Component "sync"
    return @{ ShouldContinue = $true }
}

<#
.SYNOPSIS
OnEvent hook: Queue events for batch sending

.DESCRIPTION
Adds events to queue, with immediate flush for critical events
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

if (-not $Global:HttpSyncState.Client -or -not $Global:HttpSyncState.RunId) {
    return @{ ShouldContinue = $true }
}

try {
    # Get event from hook data
    $event = $Data.Event
    
    # Critical events flush immediately (don't wait for timer)
    $criticalEvents = @("error", "requirement_complete", "validation_failed", "agent_blocked", "run_failed")
    $isCritical = $event.type -in $criticalEvents
    
    # Add to queue
    Add-EventToQueue -Event $event -Flush:$isCritical
    
    if ($isCritical) {
        Emit-Log -Level "debug" -Message "Critical event flushed immediately: $($event.type)" -Component "sync" | Out-Null
    }
    
    return @{ ShouldContinue = $true }
}
catch {
    Emit-Log -Level "warn" -Message "Event queuing failed: $_" -Component "sync"
    return @{ ShouldContinue = $true }
}

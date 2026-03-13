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

if (-not $Global:HttpSyncState -or -not $Global:HttpSyncState.Client -or -not $Global:HttpSyncState.RunId) {
    # RunId not established yet (OnPreIteration hasn't fired). Buffer the event so it
    # can be drained into the main queue once the backend run record exists.
    if (-not $Global:HttpSyncPreInitQueue) {
        $Global:HttpSyncPreInitQueue = [System.Collections.ArrayList]::new()
    }
    $Global:HttpSyncPreInitQueue.Add($event) | Out-Null
    return @{ ShouldContinue = $true }
}

try {
    # Get event from hook data
    $event = $Data.Event
    
    # Critical events flush immediately (don't wait for timer)
    # These must match the actual type strings emitted by emit-event.ps1
    $criticalEvents = @(
        "error_occurred",
        "run_completed",
        "run_started",
        "validation_completed",
        "task_completed",
        "agent_execution_started",
        "agent_execution_completed",
        "iteration_started"
    )
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

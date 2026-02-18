<#
.SYNOPSIS
OnBackpressureFailed hook: Handle validation failures

.DESCRIPTION
Queues error event and forces immediate status update when validation fails
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
    # Queue validation_failed event
    $errorEvent = @{
        type = "validation_failed"
        timestamp = Get-Date -Format "o"
        error = $Data.Error
        validation_type = $Data.ValidationType
        iteration = $Data.Iteration
    }
    
    Add-EventToQueue -Event $errorEvent -Flush
    
    # Force immediate status update (bypasses throttle)
    $status = @{
        status = "blocked"
        error = $Data.Error
        validation_type = $Data.ValidationType
        updated_at = Get-Date -Format "o"
    }
    
    Update-RunStatus -Status $status -Force
    
    Emit-Log -Level "info" -Message "Validation failure synced (forced)" -Component "sync" | Out-Null
    
    return @{ ShouldContinue = $true }
}
catch {
    Emit-Log -Level "warn" -Message "[sync-http] Backpressure failure sync failed: $_" -Component "sync"
    return @{ ShouldContinue = $true }
}

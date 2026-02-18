<#
.SYNOPSIS
OnPostModeSelection hook: Update run status after mode change

.DESCRIPTION
Throttled status update when agent switches between planning/building modes
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$HookName,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    [hashtable]$Data,
    
    [Parameter(Mandatory = $true)]
    $Config
)

# Load shared state
. "$PSScriptRoot/sync-state.ps1"

if (-not $Global:HttpSyncState.Client -or -not $Global:HttpSyncState.RunId) {
    return @{ ShouldContinue = $true }
}

try {
    # Update status with current mode
    $status = @{
        current_mode = $Data.AgentState.Mode
        current_iteration = $Data.Iteration
        updated_at = Get-Date -Format "o"
    }
    
    Update-RunStatus -Status $status
    
    return @{ ShouldContinue = $true }
}
catch {
    Write-Verbose "[sync-http] Mode selection status update failed: $_"
    return @{ ShouldContinue = $true }
}

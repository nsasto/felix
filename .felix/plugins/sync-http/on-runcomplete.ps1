<#
.SYNOPSIS
OnRunComplete hook: Finalize run and upload artifacts

.DESCRIPTION
Flushes remaining events, marks run finished, uploads artifacts, stops timer
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
    # 1. Flush any remaining events
    Invoke-EventFlush
    
    # 2. Calculate duration
    $duration = if ($Global:HttpSyncState.RunStartTime) {
        ((Get-Date) - $Global:HttpSyncState.RunStartTime).TotalSeconds
    } else {
        0
    }
    
    # 3. Mark run finished
    $finishData = @{
        status = $Data.Requirement.status
        completed_at = Get-Date -Format "o"
        iterations = $Data.Iteration
        duration_seconds = $duration
    }
    
    $Global:HttpSyncState.Client.FinishRun($Global:HttpSyncState.RunId, $finishData)
    
    # 4. Upload artifacts from runs/ directory
    if ($Data.Paths -and $Data.Paths.RunsDir) {
        $runsDir = $Data.Paths.RunsDir
        
        if (Test-Path $runsDir) {
            # Find most recent run folder
            $runFolders = Get-ChildItem $runsDir -Directory | Sort-Object LastWriteTime -Descending
            
            if ($runFolders -and $runFolders.Count -gt 0) {
                $latestRunFolder = $runFolders[0].FullName
                Write-Verbose "[sync-http] Uploading artifacts from: $latestRunFolder"
                
                $Global:HttpSyncState.Client.UploadArtifacts($Global:HttpSyncState.RunId, $latestRunFolder)
            }
        }
    }
    
    # 5. Stop flush timer
    Stop-EventFlushTimer
    
    Write-Verbose "[sync-http] Run completed: $($Global:HttpSyncState.RunId) ($duration seconds)"
    
    return @{ ShouldContinue = $true }
}
catch {
    Write-Warning "[sync-http] Run completion sync failed: $_"
    return @{ ShouldContinue = $true }
}
finally {
    # Clean up state
    $Global:HttpSyncState.RunId = $null
    $Global:HttpSyncState.EventQueue.Clear()
    $Global:HttpSyncState.RunStartTime = $null
}

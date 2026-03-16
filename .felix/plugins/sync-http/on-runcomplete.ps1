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
    
    [Parameter(Mandatory = $false)]
    $Config = @{}
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
    }
    else {
        0
    }
    
    # 3. Mark run finished
    # Reload requirement from file to get updated status
    $requirementsFile = if ($Data.Paths -and $Data.Paths.RequirementsFile) { 
        $Data.Paths.RequirementsFile 
    }
    else { 
        Join-Path $Data.Paths.FelixDir "requirements.json" 
    }
    
    $runStatus = "failed"  # Default to failed
    if (Test-Path $requirementsFile) {
        try {
            $requirements = Get-Content $requirementsFile -Raw | ConvertFrom-Json
            $currentRequirement = $requirements.requirements | Where-Object { $_.id -eq $Data.Requirement.id }
            if ($currentRequirement -and $currentRequirement.status -eq "complete") {
                $runStatus = "completed"
            }
        }
        catch {
            # If we can't read the file, use default status
        }
    }
    
    $finishData = @{
        status           = $runStatus
        completed_at     = Get-Date -Format "o"
        iterations       = $Data.Iteration
        duration_seconds = $duration
    }

    # Mark requirement complete independently from run finish sync.
    # This keeps server-side item state accurate even if /api/runs/{id}/finish
    # is temporarily failing and being retried from outbox.
    if ($runStatus -eq "completed" -and $Data.Requirement) {
        $reqCode = if ($Data.Requirement.code) { $Data.Requirement.code } else { $Data.Requirement.id }
        if ($reqCode) {
            try {
                $headers = @{ "Content-Type" = "application/json" }
                if ($Global:HttpSyncState.Client.ApiKey) {
                    $headers["Authorization"] = "Bearer $($Global:HttpSyncState.Client.ApiKey)"
                }
                $body = @{ code = $reqCode } | ConvertTo-Json
                Invoke-RestMethod -Uri "$($Global:HttpSyncState.Client.BaseUrl.TrimEnd('/'))/api/sync/work/complete" -Method POST -Headers $headers -Body $body -ErrorAction Stop | Out-Null
                Emit-Log -Level "info" -Message "Marked $reqCode complete on server (work/complete)" -Component "sync" | Out-Null
            }
            catch {
                Emit-Log -Level "warn" -Message "Failed to mark $reqCode complete via work/complete: $_" -Component "sync" | Out-Null
            }
        }
    }
    
    $Global:HttpSyncState.Client.FinishRun($Global:HttpSyncState.RunId, $finishData)

    # Mark agent back to idle
    if ($Data.AgentConfig -and $Data.AgentConfig.key) {
        $Global:HttpSyncState.Client.UpdateAgentStatus($Data.AgentConfig.key.ToString(), "idle")
    }

    # 4. Upload artifacts from runs/ directory
    if ($Data.Paths -and $Data.Paths.RunsDir) {
        $runsDir = $Data.Paths.RunsDir
        
        if (Test-Path $runsDir) {
            # Find most recent run folder
            $runFolders = Get-ChildItem $runsDir -Directory | Sort-Object LastWriteTime -Descending
            
            if ($runFolders -and $runFolders.Count -gt 0) {
                $latestRunFolder = $runFolders[0].FullName
                Emit-Log -Level "info" -Message "Uploading artifacts from: $latestRunFolder" -Component "sync" | Out-Null
                
                $Global:HttpSyncState.Client.UploadRunFolder($Global:HttpSyncState.RunId, $latestRunFolder)
                
                # Flush outbox to send queued batch upload immediately
                $Global:HttpSyncState.Client.Flush()
            }
        }
    }
    
    # 5. Stop flush timer
    Stop-EventFlushTimer
    
    Emit-Log -Level "info" -Message "Run completed: $($Global:HttpSyncState.RunId) ($duration seconds)" -Component "sync" | Out-Null
    
    return @{ ShouldContinue = $true }
}
catch {
    Emit-Log -Level "warn" -Message "[sync-http] Run completion sync failed: $_" -Component "sync"
    return @{ ShouldContinue = $true }
}
finally {
    # Clean up state
    $Global:HttpSyncState.RunId = $null
    $Global:HttpSyncState.EventQueue.Clear()
    $Global:HttpSyncState.RunStartTime = $null
}

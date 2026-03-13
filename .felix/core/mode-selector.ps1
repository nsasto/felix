<#
.SYNOPSIS
Execution mode selector for Felix agent

.DESCRIPTION
Determines whether to run in planning or building mode based on existing plan files.
#>

function Get-ExecutionMode {
    <#
    .SYNOPSIS
    Determines execution mode (planning vs building) and loads plan if needed
    #>
    param(
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        [string]$RunsDir,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $true)]
        $AgentState
    )
    
    # Look for most recent plan for current requirement
    $planPattern = "plan-$($CurrentRequirement.id).md"
    $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($existingPlans -and $existingPlans.Count -gt 0) {
        # Found plan - use building mode
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        $mode = "building"
        Emit-Log -Level "info" -Message "Found existing plan, using BUILDING mode" -Component "mode"
        
        # Transition state machine to Building
        # If currently Blocked, must pass through Planning first (Blocked -> Planning -> Building)
        if ($AgentState.Mode -eq 'Blocked') {
            $AgentState.TransitionTo('Planning')
            Emit-StateTransitioned -From 'Blocked' -To 'Planning'
            Emit-Log -Level "debug" -Message "Transitioned Blocked -> Planning (required intermediate)" -Component "state-machine"
        }
        if ($AgentState.Mode -ne 'Building') {
            $AgentState.TransitionTo('Building')
            Emit-StateTransitioned -From $AgentState.Mode -To 'Building'
            Emit-Log -Level "debug" -Message "Transitioned to Building mode" -Component "state-machine"
        }
        
        # Copy plan to current run directory for audit trail
        $planSnapshotPath = Join-Path $RunDir "plan-$($CurrentRequirement.id).md"
        Copy-Item $latestPlanPath $planSnapshotPath -Force
        $relPath = $planSnapshotPath.Replace((Split-Path $RunsDir -Parent) + "\", "")
        Emit-Artifact -Path $relPath -Type "plan" -SizeBytes (Get-Item $planSnapshotPath).Length
        Emit-Log -Level "debug" -Message "Plan snapshot saved to run directory" -Component "artifacts"
    }
    else {
        # No plan found - use planning mode (or default)
        $defaultMode = $Config.executor.default_mode
        $mode = if ($State.last_mode) { $State.last_mode } else { $defaultMode }
        if ($mode -eq "building" -and -not $existingPlans) {
            Emit-Log -Level "info" -Message "No plan found, falling back to PLANNING mode" -Component "mode"
            $mode = "planning"
        }
        Emit-Log -Level "debug" -Message "Remaining in Planning mode" -Component "state-machine"
        $latestPlanPath = $null
        $planContent = $null
    }
    
    # Workflow Stage: determine_mode
    Set-WorkflowStage -Stage "determine_mode" -ProjectPath (Split-Path $RunsDir -Parent)
    
    # Hook: OnPostModeSelection
    $hookResult = Invoke-PluginHook -HookName "OnPostModeSelection" -RunId $RunId -HookData @{
        Mode               = $mode
        CurrentRequirement = $CurrentRequirement
        PlanPath           = if ($latestPlanPath) { $latestPlanPath } else { "" }
    }
    
    if ($hookResult.OverrideMode) {
        Emit-Log -Level "info" -Message "Mode overridden: $($mode) -> $($hookResult.OverrideMode) ($($hookResult.Reason))" -Component "plugins"
        $mode = $hookResult.OverrideMode
    }
    
    return @{
        Mode        = $mode
        PlanPath    = $latestPlanPath
        PlanContent = $planContent
    }
}

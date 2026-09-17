<#
.SYNOPSIS
Execution mode selector for Felix agent

.DESCRIPTION
Determines whether to run in reviewing, planning, or building mode based on
pending_review state and existing plan files.
#>

function Copy-PlanSnapshotToRunDir {
    <#
    .SYNOPSIS
    Copies the latest plan into the current run dir unless it is already that file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LatestPlanPath,

        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $false)]
        [switch]$EmitArtifact,

        [Parameter(Mandatory = $false)]
        [string]$RunsDir = ""
    )

    $planSnapshotPath = Join-Path $RunDir "plan-$RequirementId.md"
    $sameFile = (Test-Path $planSnapshotPath) -and (
        (Get-Item -LiteralPath $LatestPlanPath).FullName -eq (Get-Item -LiteralPath $planSnapshotPath).FullName
    )
    if (-not $sameFile) {
        Copy-Item $LatestPlanPath $planSnapshotPath -Force
    }

    if ($EmitArtifact -and (Test-Path $planSnapshotPath)) {
        $root = if ($RunsDir) { Split-Path $RunsDir -Parent } else { Split-Path $RunDir -Parent }
        $relPath = $planSnapshotPath.Replace($root + "\", "")
        Emit-Artifact -Path $relPath -Type "plan" -SizeBytes (Get-Item $planSnapshotPath).Length
        Emit-Log -Level "debug" -Message "Plan snapshot saved to run directory" -Component "artifacts"
    }

    return $planSnapshotPath
}

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
    
    $latestPlanPath = $null
    $planContent = $null

    # Pending architecture review takes priority over plan/build selection
    $pendingReview = $false
    if ($State.ContainsKey("pending_review")) {
        $pendingReview = [bool]$State["pending_review"]
    }
    elseif ($State.pending_review) {
        $pendingReview = [bool]$State.pending_review
    }

    # Only pending_review schedules reviewing. Do not key off last_mode or AgentState.Mode alone
    # (that made reviewing sticky after REVIEW_CHANGES_REQUESTED / interrupted runs).
    if ($pendingReview) {
        $mode = "reviewing"
        Emit-Log -Level "info" -Message "Pending review requested, using REVIEWING mode" -Component "mode"

        # Ensure we have the latest plan available for the review prompt
        $planPattern = "plan-$($CurrentRequirement.id).md"
        $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($existingPlans -and $existingPlans.Count -gt 0) {
            $latestPlanPath = $existingPlans[0].FullName
            $planContent = Get-Content $latestPlanPath -Raw
            Copy-PlanSnapshotToRunDir -LatestPlanPath $latestPlanPath -RunDir $RunDir -RequirementId $CurrentRequirement.id | Out-Null
        }

        if ($AgentState.Mode -eq "Building" -and $AgentState.CanTransitionTo("Validating")) {
            $AgentState.TransitionTo("Validating")
            Emit-StateTransitioned -From "Building" -To "Validating"
        }
        if ($AgentState.Mode -eq "Validating" -and $AgentState.CanTransitionTo("Reviewing")) {
            $AgentState.TransitionTo("Reviewing")
            Emit-StateTransitioned -From "Validating" -To "Reviewing"
        }
        elseif ($AgentState.Mode -ne "Reviewing" -and $AgentState.CanTransitionTo("Reviewing")) {
            $AgentState.TransitionTo("Reviewing")
            Emit-StateTransitioned -From $AgentState.Mode -To "Reviewing"
        }
    }
    else {
        # Look for most recent plan for current requirement
        $planPattern = "plan-$($CurrentRequirement.id).md"
        $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

        if ($existingPlans -and $existingPlans.Count -gt 0) {
            # Found plan - use building mode
            $latestPlanPath = $existingPlans[0].FullName
            $planContent = Get-Content $latestPlanPath -Raw
            $mode = "building"
            Emit-Log -Level "info" -Message "Found existing plan, using BUILDING mode" -Component "mode"
            if ($State.last_mode -eq "reviewing") {
                # Stale reviewing last_mode without pending_review - clear so it cannot stick
                $State.last_mode = "building"
            }

            # Transition state machine to Building
            # If currently Blocked, must pass through Planning first (Blocked -> Planning -> Building)
            if ($AgentState.Mode -eq 'Blocked') {
                $AgentState.TransitionTo('Planning')
                Emit-StateTransitioned -From 'Blocked' -To 'Planning'
                Emit-Log -Level "debug" -Message "Transitioned Blocked -> Planning (required intermediate)" -Component "state-machine"
            }
            if ($AgentState.Mode -ne 'Building') {
                $fromMode = $AgentState.Mode
                $AgentState.TransitionTo('Building')
                Emit-StateTransitioned -From $fromMode -To 'Building'
                Emit-Log -Level "debug" -Message "Transitioned to Building mode" -Component "state-machine"
            }

            Copy-PlanSnapshotToRunDir `
                -LatestPlanPath $latestPlanPath `
                -RunDir $RunDir `
                -RequirementId $CurrentRequirement.id `
                -RunsDir $RunsDir `
                -EmitArtifact | Out-Null
        }
        else {
            # No plan found - use planning mode (or default)
            $defaultMode = $Config.executor.default_mode
            $mode = if ($State.last_mode) { $State.last_mode } else { $defaultMode }
            if ($mode -eq "building" -and -not $existingPlans) {
                Emit-Log -Level "info" -Message "No plan found, falling back to PLANNING mode" -Component "mode"
                $mode = "planning"
            }
            if ($mode -eq "reviewing") {
                # Stale last_mode without pending_review - fall back to planning
                Emit-Log -Level "info" -Message "Clearing stale reviewing last_mode; using PLANNING" -Component "mode"
                $mode = "planning"
                $State.last_mode = "planning"
            }
            Emit-Log -Level "debug" -Message "Remaining in Planning mode" -Component "state-machine"
        }
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

<#
.SYNOPSIS
Task completion processing for Felix agent

.DESCRIPTION
Handles task completion signals, backpressure validation, git commits, completion
signals, and iteration reports.
#>

function Invoke-TaskCompletion {
    <#
    .SYNOPSIS
    Processes task completion signals including backpressure validation
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        $AgentState,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$BeforeCommitHash,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCommit
    )
    
    # Workflow Stage: detect_task
    Set-WorkflowStage -Stage "detect_task" -ProjectPath $Paths.ProjectPath
    
    if ($Output -match '\*\*Task Completed:\*\*\s*(.+)') {
        $taskDesc = $matches[1].Trim()
        Emit-TaskCompleted -Signal "TASK_COMPLETE" -Mode $Mode
        Emit-Log -Level "info" -Message "Detected completed task: $taskDesc" -Component "task"
        
        # Hook: OnPreBackpressure
        $hookResult = Invoke-PluginHookSafely -HookName "OnPreBackpressure" -RunId $RunId -HookData @{
            CurrentRequirement = $CurrentRequirement
            Commands           = [System.Collections.ArrayList]@()
        }
        
        if ($hookResult.SkipBackpressure) {
            Emit-Log -Level "info" -Message "Backpressure skipped: $($hookResult.Reason)" -Component "plugins"
            $backpressureResult = @{ skipped = $true; success = $true }
        }
        else {
            # Workflow Stage: run_backpressure
            Set-WorkflowStage -Stage "run_backpressure" -ProjectPath $Paths.ProjectPath
            
            # Transition to Validating state
            if ($AgentState.Mode -eq "Building" -and $AgentState.CanTransitionTo('Validating')) {
                $AgentState.TransitionTo('Validating')
                Emit-StateTransitioned -From "Building" -To "Validating"
                Emit-Log -Level "debug" -Message "Transitioned to Validating mode (running backpressure)" -Component "state-machine"
            }
            
            # Run backpressure validation
            $backpressureResult = Invoke-BackpressureValidation `
                -WorkingDir $Paths.ProjectPath `
                -AgentsFilePath $Paths.AgentsFile `
                -Config $Config `
                -RunDir $RunDir
        }
        
        if (-not $backpressureResult.skipped -and -not $backpressureResult.success) {
            # Handle backpressure failure
            $blockResult = Invoke-BackpressureFailure `
                -TaskDesc $taskDesc `
                -BackpressureResult $backpressureResult `
                -State $State `
                -Config $Config `
                -CurrentRequirement $CurrentRequirement `
                -AgentState $AgentState `
                -Paths $Paths `
                -RunDir $RunDir
            
            if ($blockResult.ShouldExit) {
                return @{ ShouldExit = $true; ExitCode = $blockResult.ExitCode }
            }
            
            return @{ ShouldContinue = $false }
        }
        
        # Clear blocked status on success
        $State.blocked_task = $null
        
        if ($AgentState.Mode -eq "Validating") {
            $AgentState.TransitionTo('Building')
            Emit-StateTransitioned -From "Validating" -To "Building"
            Emit-Log -Level "debug" -Message "Transitioned back to Building mode (validation passed)" -Component "state-machine"
        }
        
        # Commit changes
        Save-TaskChanges `
            -ProjectPath $Paths.ProjectPath `
            -TaskDesc $taskDesc `
            -BeforeCommitHash $BeforeCommitHash `
            -Config $Config `
            -CurrentRequirement $CurrentRequirement `
            -RunDir $RunDir `
            -NoCommit:$NoCommit
        
        # Check if requirement is complete
        $freshRequirements = Get-Content $Paths.RequirementsFile -Raw | ConvertFrom-Json
        $freshReq = $freshRequirements.requirements | Where-Object { $_.id -eq $CurrentRequirement.id } | Select-Object -First 1
        
        if ($freshReq -and $freshReq.status -in @("complete", "done")) {
            Emit-Log -Level "info" -Message "Requirement $($CurrentRequirement.id) is now marked as $($freshReq.status)" -Component "complete"
            Emit-Log -Level "info" -Message "Exiting successfully" -Component "complete"
            Emit-Log -Level "debug" -Message "Invoke-TaskCompletion returning: ShouldExit=true, ExitCode=0 (requirement marked complete)" -Component "executor"
            return @{ ShouldExit = $true; ExitCode = 0 }
        }
    }
    
    return @{ ShouldContinue = $true }
}

function Invoke-BackpressureFailure {
    <#
    .SYNOPSIS
    Handles backpressure validation failure including blocking logic
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskDesc,
        
        [Parameter(Mandatory = $true)]
        $BackpressureResult,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        $AgentState,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir
    )
    
    Emit-Log -Level "error" -Message "Validation failed - changes will NOT be committed" -Component "backpressure"
    Emit-Log -Level "warn" -Message "Task marked as BLOCKED pending validation fixes" -Component "backpressure"
    
    # Determine retry count
    $maxRetries = if ($Config.backpressure.max_retries) { $Config.backpressure.max_retries } else { 3 }
    $failedCmdSummary = @()
    foreach ($failed in $BackpressureResult.failed_commands) {
        $failedCmdSummary += "[$($failed.type)] $($failed.command) (exit: $($failed.exit_code))"
    }
    
    $retryCount = 1
    if ($State.blocked_task -and $State.blocked_task.description -eq $TaskDesc) {
        $retryCount = $State.blocked_task.retry_count + 1
    }
    
    # Write blocked task details
    $failedCmdsText = ($failedCmdSummary | ForEach-Object { "- $_" }) -join "`n"
    $blockedTimestamp = Get-Date -Format "o"
    $blockedTaskReport = @"
# Blocked Task

**Task:** $TaskDesc
**Blocked At:** $blockedTimestamp
**Reason:** Validation failed (backpressure)
**Retry Attempt:** $retryCount of $maxRetries

## Failed Commands

$failedCmdsText
"@
    
    Set-Content (Join-Path $RunDir "blocked-task.md") $blockedTaskReport -Encoding UTF8
    $blockedTaskPath = Join-Path $RunDir "blocked-task.md"
    $relPath = $blockedTaskPath.Replace($Paths.ProjectPath + "\", "")
    Emit-Artifact -Path $relPath -Type "report" -SizeBytes (Get-Item $blockedTaskPath).Length
    
    if ($retryCount -gt $maxRetries) {
        # Max retries exceeded
        Emit-Error -ErrorType "MaxBackpressureRetriesExceeded" -Message "Maximum backpressure retries ($maxRetries) exceeded" -Severity "fatal"
        
        $maxRetriesReport = @"
#  Max Retries Exceeded 
**Task:** $TaskDesc
**Reason:** Backpressure validation failed $maxRetries consecutive times.
"@
        Set-Content (Join-Path $RunDir "max-retries-exceeded.md") $maxRetriesReport -Encoding UTF8
        Update-RequirementStatus -RequirementsFilePath $Paths.RequirementsFile -RequirementId $CurrentRequirement.id -NewStatus "blocked"
        
        # Transition state machine to Blocked
        if ($AgentState.CanTransitionTo('Blocked')) {
            $AgentState.TransitionTo('Blocked')
            Emit-StateTransitioned -From $AgentState.Mode -To "Blocked"
            Emit-Log -Level "debug" -Message "Transitioned to Blocked mode (max retries exceeded)" -Component "state-machine"
        }
        
        return @{ ShouldExit = $true; ExitCode = 2 }
    }
    
    # Update state to indicate blocked task
    $State.last_iteration_outcome = "blocked"
    $State.status = "blocked"
    $State.blocked_task = @{
        description     = $TaskDesc
        blocked_at      = Get-Date -Format "o"
        reason          = "validation_failed"
        failed_commands = $failedCmdSummary
        iteration       = $State.current_iteration
        retry_count     = $retryCount
        max_retries     = $maxRetries
    }
    $State.updated_at = Get-Date -Format "o"
    $State | ConvertTo-Json -Depth 10 | Set-Content $Paths.StateFile
    
    # Transition state machine to Blocked (temporary)
    if ($AgentState.CanTransitionTo('Blocked')) {
        $AgentState.TransitionTo('Blocked')
        Emit-StateTransitioned -From $AgentState.Mode -To "Blocked"
        Emit-Log -Level "debug" -Message "Transitioned to Blocked mode (will retry)" -Component "state-machine"
    }
    
    return @{ ShouldExit = $false }
}

function Save-TaskChanges {
    <#
    .SYNOPSIS
    Commits task changes to git
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TaskDesc,
        
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$BeforeCommitHash,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCommit
    )
    
    # Workflow Stage: commit_changes
    Set-WorkflowStage -Stage "commit_changes" -ProjectPath $ProjectPath

    if (-not (Test-GitRepository -WorkingDir $ProjectPath)) {
        Emit-Log -Level "debug" -Message "Skipping git diff/commit capture: project is not a git repository" -Component "commit"
        return
    }
    
    # Check if agent already committed changes
    Push-Location $ProjectPath
    try {
        $afterCommitHash = git rev-parse HEAD 2>$null
    }
    finally {
        Pop-Location
    }
    
    if ($BeforeCommitHash -ne $afterCommitHash) {
        # Agent created commit - capture diff
        Push-Location $ProjectPath
        try {
            $commitHash = git rev-parse --short HEAD 2>$null
            $commitMsg = git log -1 --pretty=%B 2>$null
            $diffOutput = git show HEAD --no-color 2>$null
        }
        finally {
            Pop-Location
        }
        Emit-Log -Level "info" -Message "Changes committed: $commitHash - $commitMsg" -Component "commit"
        
        $diffPath = Join-Path $RunDir "diff.patch"
        Set-Content $diffPath $diffOutput -Encoding UTF8
        $relDiffPath = $diffPath.Replace($ProjectPath + "\", "")
        Emit-Artifact -Path $relDiffPath -Type "diff" -SizeBytes (Get-Item $diffPath).Length
    }
    else {
        # PowerShell handles staging and commit
        Emit-Log -Level "debug" -Message "Capturing git diff to diff.patch" -Component "artifacts"
        $prevErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            Push-Location $ProjectPath
            try {
                git add -A 2>$null | Out-Null
                $diffOutput = git diff --cached 2>$null
            }
            finally {
                Pop-Location
            }
        }
        finally {
            $ErrorActionPreference = $prevErrorAction
        }
        if ($diffOutput) {
            $diffPath = Join-Path $RunDir "diff.patch"
            Set-Content $diffPath $diffOutput -Encoding UTF8
            $relPath = $diffPath.Replace($ProjectPath + "\", "")
            Emit-Artifact -Path $relPath -Type "diff" -SizeBytes (Get-Item $diffPath).Length
        }
        
        # Commit changes (if enabled)
        # Check requirement-level setting first, then fall back to global config
        $requirementCommitSetting = $CurrentRequirement.commit_on_complete
        if ($null -ne $requirementCommitSetting) {
            $shouldCommit = $requirementCommitSetting -and -not $NoCommit
        }
        else {
            $shouldCommit = $Config.executor.commit_on_complete -and -not $NoCommit
        }
        if ($shouldCommit) {
            # Format task description for git commit (strip markdown, convert escape sequences)
            $formattedTaskDesc = Format-PlainText -Text $TaskDesc
            $commitMsg = "Felix: $formattedTaskDesc"
            Push-Location $ProjectPath
            try {
                $success = Invoke-GitCommit -Message $commitMsg
                if ($success) {
                    $commitHash = git rev-parse --short HEAD 2>$null
                    Emit-Log -Level "info" -Message "Changes committed: $commitHash - $commitMsg" -Component "commit"
                }
                else {
                    # $false means no changes to commit (not a failure)
                    Emit-Log -Level "info" -Message "Nothing to commit" -Component "commit"
                }
            }
            catch {
                Emit-Error -ErrorType "GitCommitFailed" -Message "Failed to commit changes: $($_.Exception.Message)" -Severity "error"
            }
            finally {
                Pop-Location
            }
        }
    }
}

function Invoke-CompletionSignals {
    <#
    .SYNOPSIS
    Processes completion signals from agent output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentOutput,
        
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $AgentState,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFile
    )
    
    # Transition to BUILDING if planning completed
    if ($Mode -eq "planning" -and $AgentOutput -match '<promise>PLANNING_COMPLETE</promise>') {
        Emit-PhaseCompleted -Phase "planning" -Signal "PLAN_COMPLETE"
        Emit-Log -Level "info" -Message "Planning complete, transitioning to BUILDING mode" -Component "plan"
        $State.last_mode = "building"
        
        if ($AgentState.Mode -ne "Building") {
            $AgentState.TransitionTo('Building')
            Emit-StateTransitioned -From "Planning" -To "Building"
            Emit-Log -Level "debug" -Message "Transitioned to Building mode" -Component "state-machine"
        }
    }
    
    # Check ALL_COMPLETE first (more specific than TASK_COMPLETE)
    Emit-Log -Level "debug" -Message "Checking for ALL_COMPLETE signal..." -Component "executor"
    if ($AgentOutput -match '<promise>ALL_COMPLETE</promise>') {
        Emit-Log -Level "info" -Message "ALL_COMPLETE signal detected, marking requirement complete" -Component "executor"
        Write-Host "[EXECUTOR] ALL_COMPLETE detected, returning ExitCode=0" -ForegroundColor Green
        # Workflow Stage: update_status
        Set-WorkflowStage -Stage "update_status" -ProjectPath (Split-Path $RequirementsFile -Parent | Split-Path -Parent)
        
        # Transition state machine to Complete
        if ($AgentState.Mode -ne "Complete") {
            if ($AgentState.CanTransitionTo('Complete')) {
                $AgentState.TransitionTo('Complete')
                Emit-StateTransitioned -From $AgentState.Mode -To "Complete"
                Emit-Log -Level "debug" -Message "Transitioned to Complete mode" -Component "state-machine"
            }
            else {
                # Need to go through Validating first
                if ($AgentState.Mode -eq "Building") {
                    $AgentState.TransitionTo('Validating')
                    Emit-StateTransitioned -From "Building" -To "Validating"
                    Emit-Log -Level "debug" -Message "Transitioned to Validating mode" -Component "state-machine"
                }
                $AgentState.TransitionTo('Complete')
                Emit-StateTransitioned -From "Validating" -To "Complete"
                Emit-Log -Level "debug" -Message "Transitioned to Complete mode" -Component "state-machine"
            }
        }
        
        Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $CurrentRequirement.id -NewStatus "complete"
        Emit-Log -Level "debug" -Message "Invoke-CompletionSignals returning: ShouldExit=true, ExitCode=0 (ALL_COMPLETE detected)" -Component "executor"
        return @{ ShouldExit = $true; ExitCode = 0 }
    }
    
    # Task complete - continue to next iteration
    if ($AgentOutput -match '<promise>TASK_COMPLETE</promise>') {
        Emit-Log -Level "info" -Message "Task complete signal detected, continuing to next task" -Component "executor"
        return @{ ShouldExit = $false }
    }
    
    return @{ ShouldExit = $false }
}

function New-IterationReport {
    <#
    .SYNOPSIS
    Creates structured iteration report
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        
        [Parameter(Mandatory = $true)]
        [int]$Iteration,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        [string]$AgentOutput
    )
    
    $reportContent = @"
# Run Report

**Mode:** $Mode
**Iteration:** $Iteration
**Success:** $($State.last_iteration_outcome -eq 'success')
**Timestamp:** $(Get-Date -Format "o")

## Output

$AgentOutput
"@
    
    Set-Content (Join-Path $RunDir "report.md") $reportContent -Encoding UTF8
}

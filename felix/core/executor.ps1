<#
.SYNOPSIS
Main execution loop for Felix agent

.DESCRIPTION
Handles the main iteration loop including mode determination, agent invocation,
backpressure validation, git operations, and plugin hooks.
#>

function Invoke-FelixIteration {
    <#
    .SYNOPSIS
    Executes a single Felix agent iteration
    
    .PARAMETER Iteration
    Current iteration number
    
    .PARAMETER MaxIterations
    Maximum number of iterations allowed
    
    .PARAMETER CurrentRequirement
    The requirement being worked on
    
    .PARAMETER State
    Execution state hashtable
    
    .PARAMETER Config
    Felix configuration object
    
    .PARAMETER AgentConfig
    Agent configuration object
    
    .PARAMETER AgentState
    State machine object
    
    .PARAMETER Paths
    Project paths hashtable
    
    .PARAMETER NoCommit
    If true, skip git commits
    
    .OUTPUTS
    Hashtable with iteration result including continue status and exit code
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Iteration,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxIterations,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        $AgentConfig,
        
        [Parameter(Mandatory = $true)]
        $AgentState,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCommit
    )
    
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host " Felix Agent - Iteration $Iteration/$MaxIterations" -ForegroundColor Cyan
    
    # Workflow Stage: start_iteration
    Set-WorkflowStage -Stage "start_iteration" -ProjectPath $Paths.ProjectPath
    
    # Generate Run ID and Setup Dir
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runId = "$($CurrentRequirement.id)-$timestamp-it$Iteration"
    
    $runDir = Join-Path $Paths.RunsDir $runId
    if (-not (Test-Path $runDir)) {
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    }
    
    # Write requirement ID to run directory for tracking
    Set-Content (Join-Path $runDir "requirement_id.txt") $CurrentRequirement.id -Encoding UTF8
    
    # Update state with current run ID
    $State.last_run_id = $runId
    
    # Initialize the plugin system for this run
    Write-Host "[DEBUG] Initializing plugin system with runId: $runId" -ForegroundColor DarkGray
    Initialize-PluginSystem -Config $Config -RunId $runId
    
    # Determine mode
    $modeResult = Get-ExecutionMode `
        -CurrentRequirement $CurrentRequirement `
        -State $State `
        -Config $Config `
        -RunsDir $Paths.RunsDir `
        -RunId $runId `
        -RunDir $runDir `
        -AgentState $AgentState
    
    $mode = $modeResult.Mode
    $latestPlanPath = $modeResult.PlanPath
    $planContent = $modeResult.PlanContent
    
    # Update state
    $State.current_iteration = $Iteration
    $State.last_mode = $mode
    $State.status = "running"
    $State.updated_at = Get-Date -Format "o"
    $State | ConvertTo-Json | Set-Content $Paths.StateFile
    
    # Hook: OnPreIteration
    try {
        $hookResult = Invoke-PluginHook -HookName "OnPreIteration" -RunId $runId -HookData @{
            Iteration          = $Iteration
            MaxIterations      = $MaxIterations
            CurrentRequirement = $CurrentRequirement
            State              = $State
        }
    }
    catch {
        Write-Host "[PLUGINS] OnPreIteration hook failed: $_" -ForegroundColor Yellow
        $hookResult = @{ ContinueIteration = $true }
    }
    
    if ($hookResult.ContinueIteration -eq $false) {
        Write-Host "[PLUGINS] Iteration skipped: $($hookResult.Reason)"
        return @{ Continue = $false; ExitCode = 0 }
    }
    
    # Build prompt
    $fullPrompt = Build-IterationPrompt `
        -Mode $mode `
        -CurrentRequirement $CurrentRequirement `
        -State $State `
        -Paths $Paths `
        -RunId $runId `
        -RunDir $runDir `
        -PlanContent $planContent
    
    if (-not $fullPrompt) {
        return @{ Continue = $false; ExitCode = 1 }
    }
    
    # Capture state before execution for planning mode guardrails
    $beforeState = if ($mode -eq "planning") { Get-GitState -WorkingDir $Paths.ProjectPath } else { $null }
    
    # Capture commit hash before execution
    Push-Location $Paths.ProjectPath
    try {
        $beforeCommitHash = git rev-parse HEAD 2>$null
    }
    finally {
        Pop-Location
    }
    
    # Execute agent
    $executionResult = Invoke-AgentExecution `
        -AgentConfig $AgentConfig `
        -Prompt $fullPrompt `
        -ProjectPath $Paths.ProjectPath `
        -RunId $runId `
        -RunDir $runDir
    
    $output = $executionResult.Output
    $duration = $executionResult.Duration
    
    # Planning Mode Guardrails
    if ($mode -eq "planning") {
        $guardrailResult = Test-AndEnforcePlanningGuardrails `
            -ProjectPath $Paths.ProjectPath `
            -BeforeState $beforeState `
            -RunId $runId `
            -RunDir $runDir `
            -State $State `
            -StateFile $Paths.StateFile
        
        if (-not $guardrailResult.Passed) {
            return @{ Continue = $true; ExitCode = 0 }
        }
    }
    
    # Process task completion
    $taskResult = Process-TaskCompletion `
        -Output $output `
        -Mode $mode `
        -CurrentRequirement $CurrentRequirement `
        -State $State `
        -Config $Config `
        -AgentState $AgentState `
        -Paths $Paths `
        -RunId $runId `
        -RunDir $runDir `
        -BeforeCommitHash $beforeCommitHash `
        -NoCommit:$NoCommit
    
    if ($taskResult.ShouldExit) {
        return @{ Continue = $false; ExitCode = $taskResult.ExitCode }
    }
    
    if ($taskResult.ShouldContinue -eq $false) {
        return @{ Continue = $true; ExitCode = 0 }
    }
    
    # Check for completion signals
    $completionResult = Process-CompletionSignals `
        -Output $output `
        -Mode $mode `
        -CurrentRequirement $CurrentRequirement `
        -State $State `
        -AgentState $AgentState `
        -RequirementsFile $Paths.RequirementsFile
    
    if ($completionResult.ShouldExit) {
        return @{ Continue = $false; ExitCode = $completionResult.ExitCode }
    }
    
    # Update state and create report
    $State.last_iteration_outcome = "success"
    $State.updated_at = Get-Date -Format "o"
    $State | ConvertTo-Json | Set-Content $Paths.StateFile
    
    Create-IterationReport -RunDir $runDir -Mode $mode -Iteration $Iteration -State $State -Output $output
    
    # Hook: OnPostIteration
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostIteration" -RunId $runId -HookData @{
        Iteration = $Iteration
        Outcome   = $State.last_iteration_outcome
        State     = $State
    }
    
    if ($hookResult.ShouldContinue -eq $false) {
        Write-Host "[PLUGINS] Stopping iterations: $($hookResult.Reason)"
        return @{ Continue = $false; ExitCode = 0 }
    }
    
    # Workflow Stage: iteration_complete
    Set-WorkflowStage -Stage "iteration_complete" -ProjectPath $Paths.ProjectPath
    
    Write-Host ""
    Write-Host "Iteration $Iteration complete. Continuing..."
    Start-Sleep -Seconds 1
    
    return @{ Continue = $true; ExitCode = 0 }
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
    
    # Look for most recent plan for current requirement
    $planPattern = "plan-$($CurrentRequirement.id).md"
    $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($existingPlans -and $existingPlans.Count -gt 0) {
        # Found plan - use building mode
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        $mode = "building"
        Write-Host "[MODE] Found existing plan, using BUILDING mode" -ForegroundColor Yellow
        
        # Transition state machine to Building
        if ($AgentState.Mode -ne "Building") {
            $AgentState.TransitionTo('Building')
            Write-Host "[STATE-MACHINE] Transitioned to Building mode" -ForegroundColor DarkGray
        }
        
        # Copy plan to current run directory for audit trail
        $planSnapshotPath = Join-Path $RunDir "plan-$($CurrentRequirement.id).md"
        Copy-Item $latestPlanPath $planSnapshotPath -Force
        Write-Host "[ARTIFACTS] Plan snapshot saved to run directory" -ForegroundColor DarkGray
    }
    else {
        # No plan found - use planning mode (or default)
        $defaultMode = $Config.executor.default_mode
        $mode = if ($State.last_mode) { $State.last_mode } else { $defaultMode }
        if ($mode -eq "building" -and -not $existingPlans) {
            Write-Host "[MODE] No plan found, falling back to PLANNING mode" -ForegroundColor Yellow
            $mode = "planning"
        }
        Write-Host "[STATE-MACHINE] Remaining in Planning mode" -ForegroundColor DarkGray
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
        Write-Host "[PLUGINS] Mode overridden: $($mode) -> $($hookResult.OverrideMode) ($($hookResult.Reason))"
        $mode = $hookResult.OverrideMode
    }
    
    return @{
        Mode        = $mode
        PlanPath    = $latestPlanPath
        PlanContent = $planContent
    }
}

function Build-IterationPrompt {
    <#
    .SYNOPSIS
    Builds the full prompt for agent execution
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $false)]
        [string]$PlanContent = $null
    )
    
    # Load prompt template
    $promptFile = Join-Path $Paths.PromptsDir "$Mode.md"
    if (-not (Test-Path $promptFile)) {
        Write-Host "ERROR: " -NoNewline -ForegroundColor Red
        Write-Host "Prompt template not found: $promptFile" -ForegroundColor Red
        return $null
    }
    $promptTemplate = Get-Content $promptFile -Raw
    
    # Workflow Stage: gather_context
    Set-WorkflowStage -Stage "gather_context" -ProjectPath $Paths.ProjectPath
    
    # Gather context
    $contextParts = @()
    
    # Add AGENTS.md if exists
    if (Test-Path $Paths.AgentsFile) {
        $agentsContent = Get-Content $Paths.AgentsFile -Raw
        $contextParts += "# How to Run This Project`n`n$agentsContent"
    }
    
    # Add Requirements context
    $requirements = Get-Content $Paths.RequirementsFile -Raw | ConvertFrom-Json
    $reqContext = @{
        id           = $CurrentRequirement.id
        title        = $CurrentRequirement.title
        description  = $CurrentRequirement.description
        status       = $CurrentRequirement.status
        dependencies = @()
    }
    
    # Add dependency info if they exist
    if ($CurrentRequirement.depends_on -and $CurrentRequirement.depends_on.Count -gt 0) {
        $deps = @()
        foreach ($depId in $CurrentRequirement.depends_on) {
            $depReq = $requirements.requirements | Where-Object { $_.id -eq $depId } | Select-Object -First 1
            if ($depReq) {
                $deps += @{
                    id     = $depReq.id
                    title  = $depReq.title
                    status = $depReq.status
                }
            }
        }
        $reqContext.dependencies = $deps
    }
    
    $reqSummary = $reqContext | ConvertTo-Json -Depth 10
    $contextParts += "# Current Requirement Context`n`n``````json`n$reqSummary`n```````n`n*Note: Full requirements list available at ``felix/requirements.json`` if you need to check other requirements.*"
    
    # Add current requirement header
    $contextParts += "# Current Requirement`n`nYou are working on: **$($CurrentRequirement.id)** - $($CurrentRequirement.title)"
    
    # Add failure context from previous iteration if blocked
    if ($State.blocked_task) {
        $failedCommandsList = ($State.blocked_task.failed_commands | ForEach-Object { "- $_" }) -join "`n"
        $retryInfo = "# âš ï¸ Previous Iteration - Task Blocked âš ï¸`n`n"
        $retryInfo += "**IMPORTANT:** The following task failed validation in the previous iteration. You MUST fix these issues before proceeding.`n`n"
        $retryInfo += "**Blocked Task:** $($State.blocked_task.description)`n"
        $retryInfo += "**Retry Attempt:** $($State.blocked_task.retry_count) of $($State.blocked_task.max_retries)`n"
        $retryInfo += "**Blocked Since:** $($State.blocked_task.blocked_at)`n"
        $retryInfo += "**Reason:** $($State.blocked_task.reason)`n`n"
        $retryInfo += "## Failed Validation Commands`n`n"
        $retryInfo += "$failedCommandsList`n`n"
        $retryInfo += "## What You Must Do`n`n"
        $retryInfo += "1. **Review the failed validation commands above** - These commands must pass before the task can be committed`n"
        $retryInfo += "2. **Fix the underlying issues** causing the test/build/lint failures. DO NOT just retry without changes.`n"
        $retryInfo += "3. **Explain your fix** in the task completion message.`n"
        
        $contextParts += $retryInfo
    }
    
    # Add Mode Specific Context
    if ($Mode -eq "building") {
        if ($PlanContent) {
            $contextParts += "# Current Plan`n`n$PlanContent"
        }
    }
    
    # Target path for plan (relative to project root)
    $planRelPath = "runs/$RunId/plan-$($CurrentRequirement.id).md"
    $planOutputPath = Join-Path $Paths.ProjectPath $planRelPath
    
    if ($Mode -eq "planning") {
        $contextParts += "# Plan Output Path`n`nYou MUST generate a requirement-specific plan and save it to: **$planOutputPath**`n`nThis plan should contain ONLY tasks for requirement $($CurrentRequirement.id)."
    }
    else {
        $contextParts += "# Plan Update Path`n`nWhen marking tasks complete, update the plan at: **$planOutputPath**"
    }
    
    # Workflow Stage: build_prompt
    Set-WorkflowStage -Stage "build_prompt" -ProjectPath $Paths.ProjectPath
    
    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"
    
    # Hook: OnContextGathering
    $gitDiff = ""
    if (Test-Path (Join-Path $Paths.ProjectPath ".git")) {
        Push-Location $Paths.ProjectPath
        try {
            $gitDiff = git diff 2>$null
        }
        finally {
            Pop-Location
        }
    }
    $hookResult = Invoke-PluginHookSafely -HookName "OnContextGathering" -RunId $RunId -HookData @{
        Mode               = $Mode
        CurrentRequirement = $CurrentRequirement
        GitDiff            = $gitDiff
        PlanContent        = if ($Mode -eq "building" -and $PlanContent) { $PlanContent } else { "" }
        ContextFiles       = $contextParts
    }
    
    if ($hookResult.AdditionalContext) {
        Write-Verbose "[PLUGINS] Adding additional context from plugins"
        $fullPrompt += "`n`n---`n`n# Additional Context (Plugins)`n`n$($hookResult.AdditionalContext)"
    }
    
    return $fullPrompt
}

function Invoke-AgentExecution {
    <#
    .SYNOPSIS
    Executes the agent with the given prompt
    #>
    param(
        [Parameter(Mandatory = $true)]
        $AgentConfig,
        
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir
    )
    
    # Workflow Stage: execute_llm
    Set-WorkflowStage -Stage "execute_llm" -ProjectPath $ProjectPath
    
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Executing agent '$($AgentConfig.name)'..." -ForegroundColor White
    
    $executable = $AgentConfig.executable
    $agentArgs = $AgentConfig.args
    $agentWorkingDir = if ($AgentConfig.working_directory) { $AgentConfig.working_directory } else { "." }
    $startTime = Get-Date
    
    # Hook: OnPreExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPreExecution" -RunId $RunId -HookData @{
        Executable = $executable
        Args       = [System.Collections.ArrayList]@($agentArgs)
        Prompt     = $Prompt
    }
    
    if ($hookResult.ModifiedArgs) {
        $agentArgs = $hookResult.ModifiedArgs
        Write-Verbose "[PLUGINS] Using modified executable arguments"
    }
    
    # Execute the agent and capture output
    $agentCwd = if ([System.IO.Path]::IsPathRooted($agentWorkingDir)) {
        $agentWorkingDir
    }
    else {
        Join-Path $ProjectPath $agentWorkingDir
    }
    
    $envBackup = @{}
    try {
        # Apply agent environment variables (best-effort)
        if ($AgentConfig.environment) {
            foreach ($prop in $AgentConfig.environment.PSObject.Properties) {
                $key = $prop.Name
                $value = [string]$prop.Value
                $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
        
        Push-Location $agentCwd
        try {
            $output = $Prompt | & $executable @agentArgs 2>&1 | Out-String
        }
        finally {
            Pop-Location
        }
    }
    finally {
        foreach ($key in $envBackup.Keys) {
            [Environment]::SetEnvironmentVariable($key, $envBackup[$key], "Process")
        }
    }
    $duration = (Get-Date) - $startTime
    
    # Write raw output to run directory
    Set-Content (Join-Path $RunDir "output.log") $output -Encoding UTF8
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Execution complete (Duration: $($duration.TotalSeconds.ToString("F1"))s)" -ForegroundColor White
    
    # Hook: OnPostExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostExecution" -RunId $RunId -HookData @{
        Output   = $output
        Duration = $duration.TotalSeconds
    }
    
    return @{
        Output   = $output
        Duration = $duration
    }
}

function Test-AndEnforcePlanningGuardrails {
    <#
    .SYNOPSIS
    Tests and enforces planning mode guardrails
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        $BeforeState,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        [string]$StateFile
    )
    
    # Workflow Stage: check_guardrails
    Set-WorkflowStage -Stage "check_guardrails" -ProjectPath $ProjectPath
    
    $violations = Test-PlanningModeGuardrails -WorkingDir $ProjectPath -BeforeState $BeforeState -RunId $RunId
    if ($violations.HasViolations) {
        Undo-PlanningViolations -WorkingDir $ProjectPath -BeforeState $BeforeState -Violations $violations
        
        # Document guardrail violations
        $violationReport = @"
# Planning Mode Guardrail Violation

**Timestamp:** $(Get-Date -Format "o")

## Violations Detected

"@
        
        if ($violations.CommitMade) {
            $violationReport += "`n### Unauthorized Commit`n`nA commit was made during planning mode and has been reverted.`n"
        }
        
        if ($violations.UnauthorizedFiles.Count -gt 0) {
            $violationReport += "`n### Unauthorized File Modifications`n`nThe following files were modified outside allowed paths:`n`n"
            foreach ($file in $violations.UnauthorizedFiles) {
                $violationReport += "- $file`n"
            }
            $violationReport += "`nThese changes have been reverted.`n"
        }
        
        $violationReport += @"

## Allowed Modifications in Planning Mode

- runs/ directory (plan files)
- felix/state.json (execution state)
- felix/requirements.json (requirement status)
"@
        
        Set-Content (Join-Path $RunDir "guardrail-violation.md") $violationReport -Encoding UTF8
        Write-Host "[ARTIFACTS] Guardrail violation report saved" -ForegroundColor DarkGray
        
        # Update state
        $State.last_iteration_outcome = "guardrail_violation"
        $State.updated_at = Get-Date -Format "o"
        $State | ConvertTo-Json | Set-Content $StateFile
        
        Write-Host "[AGENT] " -NoNewline -ForegroundColor Red
        Write-Host "Planning mode aborted due to guardrail violations." -ForegroundColor Red
        
        return @{ Passed = $false }
    }
    
    return @{ Passed = $true }
}

function Process-TaskCompletion {
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
        [string]$BeforeCommitHash,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCommit
    )
    
    # Workflow Stage: detect_task
    Set-WorkflowStage -Stage "detect_task" -ProjectPath $Paths.ProjectPath
    
    if ($Output -match '\*\*Task Completed:\*\*\s*(.+)') {
        $taskDesc = $matches[1].Trim()
        Write-Host ""
        Write-Host "[TASK] " -NoNewline -ForegroundColor Green
        Write-Host "Detected completed task: $taskDesc" -ForegroundColor White
        
        # Hook: OnPreBackpressure
        $hookResult = Invoke-PluginHookSafely -HookName "OnPreBackpressure" -RunId $RunId -HookData @{
            CurrentRequirement = $CurrentRequirement
            Commands           = [System.Collections.ArrayList]@()
        }
        
        if ($hookResult.SkipBackpressure) {
            Write-Host "[PLUGINS] Backpressure skipped: $($hookResult.Reason)"
            $backpressureResult = @{ skipped = $true; success = $true }
        }
        else {
            # Workflow Stage: run_backpressure
            Set-WorkflowStage -Stage "run_backpressure" -ProjectPath $Paths.ProjectPath
            
            # Transition to Validating state
            if ($AgentState.Mode -eq "Building" -and $AgentState.CanTransitionTo('Validating')) {
                $AgentState.TransitionTo('Validating')
                Write-Host "[STATE-MACHINE] Transitioned to Validating mode (running backpressure)" -ForegroundColor DarkGray
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
            $blockResult = Handle-BackpressureFailure `
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
            Write-Host "[STATE-MACHINE] Transitioned back to Building mode (validation passed)" -ForegroundColor DarkGray
        }
        
        # Commit changes
        Commit-TaskChanges `
            -ProjectPath $Paths.ProjectPath `
            -TaskDesc $taskDesc `
            -BeforeCommitHash $BeforeCommitHash `
            -Config $Config `
            -RunDir $RunDir `
            -NoCommit:$NoCommit
        
        # Check if requirement is complete
        $freshRequirements = Get-Content $Paths.RequirementsFile -Raw | ConvertFrom-Json
        $freshReq = $freshRequirements.requirements | Where-Object { $_.id -eq $CurrentRequirement.id } | Select-Object -First 1
        
        if ($freshReq -and $freshReq.status -in @("complete", "done")) {
            Write-Host ""
            Write-Host "[COMPLETE] Requirement $($CurrentRequirement.id) is now marked as $($freshReq.status)" -ForegroundColor Green
            Write-Host "[COMPLETE] Exiting successfully" -ForegroundColor Green
            return @{ ShouldExit = $true; ExitCode = 0 }
        }
    }
    
    return @{ ShouldContinue = $true }
}

function Handle-BackpressureFailure {
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
    
    Write-Host ""
    Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
    Write-Host "âŒ Validation failed - changes will NOT be committed" -ForegroundColor Red
    Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
    Write-Host "Task marked as BLOCKED pending validation fixes" -ForegroundColor Yellow
    
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
    $blockedTaskReport = @"
# Blocked Task

**Task:** $TaskDesc
**Blocked At:** $(Get-Date -Format "o")
**Reason:** Validation failed (backpressure)
**Retry Attempt:** $retryCount of $maxRetries

## Failed Commands

$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)
"@
    
    Set-Content (Join-Path $RunDir "blocked-task.md") $blockedTaskReport -Encoding UTF8
    Write-Host "[ARTIFACTS] Blocked task report saved" -ForegroundColor DarkGray
    
    if ($retryCount -gt $maxRetries) {
        # Max retries exceeded
        Write-Host "[BLOCKED] Maximum backpressure retries ($maxRetries) exceeded" -ForegroundColor Red
        
        $maxRetriesReport = @"
# âŒ Max Retries Exceeded âŒ
**Task:** $TaskDesc
**Reason:** Backpressure validation failed $maxRetries consecutive times.
"@
        Set-Content (Join-Path $RunDir "max-retries-exceeded.md") $maxRetriesReport -Encoding UTF8
        Update-RequirementStatus -RequirementsFilePath $Paths.RequirementsFile -RequirementId $CurrentRequirement.id -NewStatus "blocked"
        
        # Transition state machine to Blocked
        if ($AgentState.CanTransitionTo('Blocked')) {
            $AgentState.TransitionTo('Blocked')
            Write-Host "[STATE-MACHINE] Transitioned to Blocked mode (max retries exceeded)" -ForegroundColor DarkGray
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
        Write-Host "[STATE-MACHINE] Transitioned to Blocked mode (will retry)" -ForegroundColor DarkGray
    }
    
    return @{ ShouldExit = $false }
}

function Commit-TaskChanges {
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
        [string]$BeforeCommitHash,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCommit
    )
    
    # Workflow Stage: commit_changes
    Set-WorkflowStage -Stage "commit_changes" -ProjectPath $ProjectPath
    
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
        Write-Host "[COMMIT] âœ… $commitHash - $commitMsg"
        
        $diffPath = Join-Path $RunDir "diff.patch"
        Set-Content $diffPath $diffOutput -Encoding UTF8
        Write-Host "[ARTIFACTS] Git diff saved to: diff.patch"
    }
    else {
        # PowerShell handles staging and commit
        Write-Host "[ARTIFACTS] Capturing git diff to diff.patch..."
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
            Write-Host "[ARTIFACTS] Git diff saved to: diff.patch"
        }
        
        # Commit changes (if enabled)
        # Check requirement-level setting first, then fall back to global config
        $requirementCommitSetting = $CurrentRequirement.commit_on_complete
        if ($null -ne $requirementCommitSetting) {
            $shouldCommit = $requirementCommitSetting -and -not $NoCommit
        } else {
            $shouldCommit = $Config.executor.commit_on_complete -and -not $NoCommit
        }
        if ($shouldCommit) {
            $commitMsg = "Felix: $TaskDesc"
            $prevErrorAction = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                Push-Location $ProjectPath
                try {
                    $commitOutput = git commit -m $commitMsg 2>&1
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                $ErrorActionPreference = $prevErrorAction
            }
            if ($LASTEXITCODE -eq 0) {
                Push-Location $ProjectPath
                try {
                    $commitHash = git rev-parse --short HEAD 2>$null
                }
                finally {
                    Pop-Location
                }
                Write-Host "[COMMIT] âœ… Changes committed: $commitHash - $commitMsg"
            }
            else {
                Write-Host "[COMMIT] âŒ Failed to commit changes:" -ForegroundColor Red
                Write-Host $commitOutput -ForegroundColor Red
            }
        }
    }
}

function Process-CompletionSignals {
    <#
    .SYNOPSIS
    Processes completion signals from agent output
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
        $AgentState,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFile
    )
    
    # Transition to BUILDING if planning completed
    if ($Mode -eq "planning" -and $Output -match '<promise>PLANNING_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[PLAN READY] Planning complete, transitioning to BUILDING mode"
        $State.last_mode = "building"
        
        if ($AgentState.Mode -ne "Building") {
            $AgentState.TransitionTo('Building')
            Write-Host "[STATE-MACHINE] Transitioned to Building mode" -ForegroundColor DarkGray
        }
    }
    
    # All requirements met?
    if ($Output -match '<promise>ALL_REQUIREMENTS_MET</promise>') {
        # Workflow Stage: update_status
        Set-WorkflowStage -Stage "update_status" -ProjectPath (Split-Path $RequirementsFile -Parent | Split-Path -Parent)
        
        # Transition state machine to Complete
        if ($AgentState.Mode -ne "Complete") {
            if ($AgentState.CanTransitionTo('Complete')) {
                $AgentState.TransitionTo('Complete')
                Write-Host "[STATE-MACHINE] Transitioned to Complete mode" -ForegroundColor DarkGray
            }
            else {
                # Need to go through Validating first
                if ($AgentState.Mode -eq "Building") {
                    $AgentState.TransitionTo('Validating')
                    Write-Host "[STATE-MACHINE] Transitioned to Validating mode" -ForegroundColor DarkGray
                }
                $AgentState.TransitionTo('Complete')
                Write-Host "[STATE-MACHINE] Transitioned to Complete mode" -ForegroundColor DarkGray
            }
        }
        
        Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $CurrentRequirement.id -NewStatus "complete"
        return @{ ShouldExit = $true; ExitCode = 0 }
    }
    
    return @{ ShouldExit = $false }
}

function Create-IterationReport {
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
        [string]$Output
    )
    
    $reportContent = @"
# Run Report

**Mode:** $Mode
**Iteration:** $Iteration
**Success:** $($State.last_iteration_outcome -eq 'success')
**Timestamp:** $(Get-Date -Format "o")

## Output

$Output
"@
    
    Set-Content (Join-Path $RunDir "report.md") $reportContent -Encoding UTF8
}


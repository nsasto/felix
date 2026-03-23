<#
.SYNOPSIS
Main execution loop for Felix agent

.DESCRIPTION
Handles the main iteration loop including mode determination, agent invocation,
backpressure validation, git operations, and plugin hooks.
#>

# Import agent adapters and extracted modules
. "$PSScriptRoot\agent-adapters.ps1"
. "$PSScriptRoot\mode-selector.ps1"
. "$PSScriptRoot\prompt-builder.ps1"
. "$PSScriptRoot\agent-runner.ps1"
. "$PSScriptRoot\artifact-validator.ps1"
. "$PSScriptRoot\task-handler.ps1"

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
        [switch]$NoCommit,

        [Parameter(Mandatory = $false)]
        [switch]$DebugMode,
        
        [Parameter(Mandatory = $false)]
        [switch]$VerboseMode
    )
    
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
    # Must happen before any Emit-* calls so $script:RunId / $script:PluginCache are set
    Emit-Log -Level "debug" -Message "Initializing plugin system with runId: $runId" -Component "executor"
    Initialize-PluginSystem -Config $Config -RunId $runId

    # Emit iteration started AFTER plugin init so the event can reach the OnEvent hook
    Emit-IterationStarted -Iteration $Iteration -MaxIterations $MaxIterations `
        -RequirementId $CurrentRequirement.id -Mode "determining"
    
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
            Config             = $Config
            Paths              = $Paths
            AgentConfig        = $AgentConfig
            Requirement        = $CurrentRequirement
        }
    }
    catch {
        Emit-Log -Level "warn" -Message "OnPreIteration hook failed: $_" -Component "plugins"
        $hookResult = @{ ContinueIteration = $true }
    }
    
    if ($hookResult.ContinueIteration -eq $false) {
        Emit-Log -Level "info" -Message "Iteration skipped: $($hookResult.Reason)" -Component "plugins" | Out-Null
        return @{ Continue = $false; ExitCode = 0 }
    }
    
    # Build prompt
    $fullPrompt = New-IterationPrompt `
        -Mode $mode `
        -CurrentRequirement $CurrentRequirement `
        -State $State `
        -Config $Config `
        -Paths $Paths `
        -RunId $runId `
        -RunDir $runDir `
        -PlanContent $planContent `
        -NoCommit:$NoCommit
    
    if (-not $fullPrompt) {
        return @{ Continue = $false; ExitCode = 1 }
    }

    $hasGitRepo = if (Get-Command Test-GitRepository -ErrorAction SilentlyContinue) {
        Test-GitRepository -WorkingDir $Paths.ProjectPath
    }
    else {
        Test-Path (Join-Path $Paths.ProjectPath ".git")
    }

    # Capture state before execution for planning mode guardrails
    $beforeState = if ($mode -eq "planning" -and $hasGitRepo) { Get-GitState -WorkingDir $Paths.ProjectPath } else { $null }
    
    # Capture commit hash before execution
    if ($hasGitRepo) {
        Push-Location $Paths.ProjectPath
        try {
            $beforeCommitHash = git rev-parse HEAD 2>$null
        }
        finally {
            Pop-Location
        }
    }
    else {
        $beforeCommitHash = ""
    }
    
    # Execute agent
    $executionResult = Invoke-AgentExecution `
        -AgentConfig $AgentConfig `
        -Prompt $fullPrompt `
        -ProjectPath $Paths.ProjectPath `
        -RunId $runId `
        -RunDir $runDir `
        -DebugMode:$DebugMode `
        -VerboseMode:$VerboseMode
    
    $output = $executionResult.Output
    # Use parsed output for signal/contract checking so the raw JSON envelope doesn't hide
    # <promise> tags that are embedded inside the agent's JSON result string.
    $parsedOutput = if ($executionResult.Parsed -and $executionResult.Parsed.Output) {
        $executionResult.Parsed.Output
    }
    elseif ($executionResult.NormalizedOutput) {
        $executionResult.NormalizedOutput
    }
    else {
        $executionResult.Output
    }

    if ($executionResult.Succeeded -eq $false) {
        $State.last_iteration_outcome = "failure"
        $State.status = "ready"
        $State.updated_at = Get-Date -Format "o"
        $State | ConvertTo-Json | Set-Content $Paths.StateFile

        New-IterationReport -RunDir $runDir -Mode $mode -Iteration $Iteration -State $State -AgentOutput $output
        Emit-IterationCompleted -Iteration $Iteration -Outcome "failure"
        return @{ Continue = $false; ExitCode = 1 }
    }
    
    # Planning Mode Guardrails
    if ($mode -eq "planning" -and $hasGitRepo) {
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

    $contractFlow = Invoke-ContractRepairFlow `
        -BasePrompt $fullPrompt `
        -Mode $mode `
        -RunDir $runDir `
        -RequirementId $CurrentRequirement.id `
        -InitialOutput $parsedOutput `
        -PreviousPlanContent $planContent `
        -RetryExecution {
        param($RepairPrompt, $AttemptNumber, $ViolationReason)
        $reasonSuffix = if ($ViolationReason) { " - $ViolationReason" } else { "" }
        Emit-Log -Level "warn" -Message "Contract violation detected, issuing corrective retry (attempt $AttemptNumber)$reasonSuffix" -Component "contract"
        Invoke-AgentExecution `
            -AgentConfig $AgentConfig `
            -Prompt $RepairPrompt `
            -ProjectPath $Paths.ProjectPath `
            -RunId $runId `
            -RunDir $runDir `
            -DebugMode:$DebugMode `
            -VerboseMode:$VerboseMode
    }

    $output = $contractFlow.Output

    if (-not $contractFlow.IsValid) {
        $reportPath = Write-ArtifactValidationFailure -RunDir $runDir -Message $contractFlow.Validation.Reason -RetryAttempts $contractFlow.RetryAttempts
        $relPath = $reportPath.Replace($Paths.ProjectPath + "\", "")
        Emit-Artifact -Path $relPath -Type "report" -SizeBytes (Get-Item $reportPath).Length
        Emit-Error -ErrorType "ArtifactValidationFailed" -Message $contractFlow.Validation.Reason -Severity "error" -Context @{
            mode           = $mode
            requirement_id = $CurrentRequirement.id
            plan_path      = $contractFlow.Validation.PlanPath
            signal         = $contractFlow.Validation.Signal
            retry_attempts = $contractFlow.RetryAttempts
        }

        $State.last_iteration_outcome = "failure"
        $State.status = "ready"
        $State.updated_at = Get-Date -Format "o"
        $State | ConvertTo-Json | Set-Content $Paths.StateFile

        New-IterationReport -RunDir $runDir -Mode $mode -Iteration $Iteration -State $State -AgentOutput $output
        Emit-IterationCompleted -Iteration $Iteration -Outcome "failure"
        return @{ Continue = $false; ExitCode = 1 }
    }
    
    # Process task completion
    $taskResult = Invoke-TaskCompletion `
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
        Emit-Log -Level "debug" -Message "Invoke-FelixIteration returning: Continue=false, ExitCode=$($taskResult.ExitCode) (from Invoke-TaskCompletion)" -Component "executor"
        return @{ Continue = $false; ExitCode = $taskResult.ExitCode }
    }
    
    if ($taskResult.ShouldContinue -eq $false) {
        return @{ Continue = $true; ExitCode = 0 }
    }
    
    # Check for completion signals
    $completionResult = Invoke-CompletionSignals `
        -AgentOutput $output `
        -Mode $mode `
        -CurrentRequirement $CurrentRequirement `
        -State $State `
        -AgentState $AgentState `
        -RequirementsFile $Paths.RequirementsFile
    
    if ($completionResult.ShouldExit) {
        Emit-Log -Level "debug" -Message "Invoke-FelixIteration returning: Continue=false, ExitCode=$($completionResult.ExitCode) (from Invoke-CompletionSignals)" -Component "executor"
        Write-Host "[EXECUTOR] Invoke-FelixIteration returning ExitCode=$($completionResult.ExitCode)" -ForegroundColor Green
        return @{ Continue = $false; ExitCode = $completionResult.ExitCode }
    }
    
    # Update state and create report
    $State.last_iteration_outcome = "success"
    $State.updated_at = Get-Date -Format "o"
    $State | ConvertTo-Json | Set-Content $Paths.StateFile
    
    New-IterationReport -RunDir $runDir -Mode $mode -Iteration $Iteration -State $State -AgentOutput $output
    
    # Hook: OnPostIteration
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostIteration" -RunId $runId -HookData @{
        Iteration = $Iteration
        Outcome   = $State.last_iteration_outcome
        State     = $State
    }
    
    if ($hookResult.ShouldContinue -eq $false) {
        Emit-Log -Level "info" -Message "Stopping iterations: $($hookResult.Reason)" -Component "plugins" | Out-Null
        return @{ Continue = $false; ExitCode = 0 }
    }
    
    # Workflow Stage: iteration_complete
    Set-WorkflowStage -Stage "iteration_complete" -ProjectPath $Paths.ProjectPath
    
    Emit-IterationCompleted -Iteration $Iteration -Outcome "success"
    Start-Sleep -Seconds 1
    
    return @{ Continue = $true; ExitCode = 0 }
}


. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/executor.ps1"

function New-ExecutorTestAgentState {
    param([string]$Mode)

    $state = [pscustomobject]@{ Mode = $Mode }
    $state | Add-Member -MemberType ScriptMethod -Name CanTransitionTo -Value {
        param([string]$NewMode)
        return $true
    }
    $state | Add-Member -MemberType ScriptMethod -Name TransitionTo -Value {
        param([string]$NewMode)
        $this.Mode = $NewMode
    }
    return $state
}

function New-ExecutorPlanContent {
    param([string[]]$Tasks)

    return @"
# Implementation Plan for S-0001

## Summary

Executor regression plan.

## Tasks

$($Tasks -join "`n")
"@
}

function Initialize-ExecutorGitRepo {
    param([string]$ProjectRoot)

    Push-Location $ProjectRoot
    try {
        git init | Out-Null
        git config user.email "felix-tests@example.com" | Out-Null
        git config user.name "Felix Tests" | Out-Null
        Set-Content (Join-Path $ProjectRoot "README.md") "# Executor Test" -Encoding UTF8
        git add -A | Out-Null
        git commit -m "init" | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe "Invoke-FelixIteration contract enforcement" {

    It "should retry once and continue with the repaired output" {
        $projectRoot = Join-Path $env:TEMP "executor-contract-$(Get-Random)"
        $runsDir = Join-Path $projectRoot "runs"
        $felixDir = Join-Path $projectRoot ".felix"
        New-Item -ItemType Directory -Path $projectRoot, $runsDir, $felixDir -Force | Out-Null
        Set-Content (Join-Path $felixDir "requirements.json") '{"requirements":[]}' -Encoding UTF8
        Set-Content (Join-Path $felixDir "state.json") '{}' -Encoding UTF8
        Initialize-ExecutorGitRepo -ProjectRoot $projectRoot

        $script:ExecutionCount = 0
        $script:TaskCompletionOutput = $null
        $script:CompletionSignalOutput = $null

        function Set-WorkflowStage { param([string]$Stage, [string]$ProjectPath) }
        function Emit-AgentExecutionStarted { param($AgentName, $AgentId) }
        function Initialize-PluginSystem { param($Config, [string]$RunId) }
        function Emit-IterationStarted { param($Iteration, $MaxIterations, $RequirementId, $Mode) }
        function Emit-IterationCompleted { param($Iteration, $Outcome) }
        function Emit-Artifact { param($Path, $Type, $SizeBytes) }
        function Emit-Error { param($ErrorType, $Message, $Severity, $Context) }
        function Emit-Log { param($Level, $Message, $Component) }
        function Invoke-PluginHook { param($HookName, $RunId, $HookData) return @{ ContinueIteration = $true } }
        function Invoke-PluginHookSafely { param($HookName, $RunId, $HookData) return @{} }
        function Get-ExecutionMode { param($CurrentRequirement, $State, $Config, $RunsDir, $RunId, $RunDir, $AgentState) return @{ Mode = 'planning'; PlanPath = $null; PlanContent = $null } }
        function New-IterationPrompt { param($Mode, $CurrentRequirement, $State, $Config, $Paths, $RunId, $RunDir, $PlanContent, $NoCommit) return 'base prompt' }
        function Get-GitState { param([string]$WorkingDir) return @{} }
        function Test-AndEnforcePlanningGuardrails { param($ProjectPath, $BeforeState, $RunId, $RunDir, $State, $StateFile) return @{ Passed = $true } }
        function Invoke-AgentExecution {
            param($AgentConfig, [string]$Prompt, [string]$ProjectPath, [string]$RunId, [string]$RunDir, [switch]$VerboseMode)
            $script:ExecutionCount++
            if ($script:ExecutionCount -eq 1) {
                return @{ Output = 'No completion marker'; Succeeded = $true }
            }

            Set-Content (Join-Path $RunDir 'plan-S-0001.md') (New-ExecutorPlanContent -Tasks @('- [ ] Repair task')) -Encoding UTF8
            return @{ Output = '<promise>PLAN_COMPLETE</promise>'; Succeeded = $true }
        }
        function Invoke-TaskCompletion {
            param($Output, $Mode, $CurrentRequirement, $State, $Config, $AgentState, $Paths, $RunId, $RunDir, $BeforeCommitHash, $NoCommit)
            $script:TaskCompletionOutput = $Output
            return @{ ShouldContinue = $true }
        }
        function Invoke-CompletionSignals {
            param($AgentOutput, $Mode, $CurrentRequirement, $State, $AgentState, $RequirementsFile)
            $script:CompletionSignalOutput = $AgentOutput
            return @{ ShouldExit = $false }
        }
        function New-IterationReport { param($RunDir, $Mode, $Iteration, $State, $AgentOutput) }

        try {
            $result = Invoke-FelixIteration `
                -Iteration 1 `
                -MaxIterations 5 `
                -CurrentRequirement ([pscustomobject]@{ id = 'S-0001'; title = 'Contract'; status = 'in_progress' }) `
                -State @{} `
                -Config ([pscustomobject]@{ executor = [pscustomobject]@{ default_mode = 'planning' } }) `
                -AgentConfig ([pscustomobject]@{ name = 'copilot'; key = 'ag1'; adapter = 'copilot'; executable = 'copilot' }) `
                -AgentState (New-ExecutorTestAgentState -Mode 'Planning') `
                -Paths @{
                ProjectPath      = $projectRoot
                RunsDir          = $runsDir
                StateFile        = (Join-Path $felixDir 'state.json')
                RequirementsFile = (Join-Path $felixDir 'requirements.json')
                AgentsFile       = (Join-Path $projectRoot 'AGENTS.md')
                PromptsDir       = (Join-Path $projectRoot 'prompts')
            } `
                -NoCommit

            Assert-True $result.Continue
            Assert-Equal 2 $script:ExecutionCount
            Assert-Equal '<promise>PLAN_COMPLETE</promise>' $script:TaskCompletionOutput
            Assert-Equal '<promise>PLAN_COMPLETE</promise>' $script:CompletionSignalOutput
        }
        finally {
            Remove-Item Function:\Set-WorkflowStage -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-AgentExecutionStarted -ErrorAction SilentlyContinue
            Remove-Item Function:\Initialize-PluginSystem -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-IterationStarted -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-IterationCompleted -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Artifact -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Error -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Log -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-PluginHook -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-PluginHookSafely -ErrorAction SilentlyContinue
            Remove-Item Function:\Get-ExecutionMode -ErrorAction SilentlyContinue
            Remove-Item Function:\New-IterationPrompt -ErrorAction SilentlyContinue
            Remove-Item Function:\Get-GitState -ErrorAction SilentlyContinue
            Remove-Item Function:\Test-AndEnforcePlanningGuardrails -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-AgentExecution -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-TaskCompletion -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-CompletionSignals -ErrorAction SilentlyContinue
            Remove-Item Function:\New-IterationReport -ErrorAction SilentlyContinue
            Remove-Item Variable:\script:ExecutionCount -ErrorAction SilentlyContinue
            Remove-Item Variable:\script:TaskCompletionOutput -ErrorAction SilentlyContinue
            Remove-Item Variable:\script:CompletionSignalOutput -ErrorAction SilentlyContinue
            Remove-Item $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should fail after one invalid retry and write a contract failure artifact" {
        $projectRoot = Join-Path $env:TEMP "executor-contract-$(Get-Random)"
        $runsDir = Join-Path $projectRoot "runs"
        $felixDir = Join-Path $projectRoot ".felix"
        New-Item -ItemType Directory -Path $projectRoot, $runsDir, $felixDir -Force | Out-Null
        Set-Content (Join-Path $felixDir "requirements.json") '{"requirements":[]}' -Encoding UTF8
        Set-Content (Join-Path $felixDir "state.json") '{}' -Encoding UTF8
        Initialize-ExecutorGitRepo -ProjectRoot $projectRoot

        $script:ExecutionCount = 0
        $script:TaskCompletionCalled = $false

        function Set-WorkflowStage { param([string]$Stage, [string]$ProjectPath) }
        function Emit-AgentExecutionStarted { param($AgentName, $AgentId) }
        function Initialize-PluginSystem { param($Config, [string]$RunId) }
        function Emit-IterationStarted { param($Iteration, $MaxIterations, $RequirementId, $Mode) }
        function Emit-IterationCompleted { param($Iteration, $Outcome) }
        function Emit-Artifact { param($Path, $Type, $SizeBytes) }
        function Emit-Error { param($ErrorType, $Message, $Severity, $Context) }
        function Emit-Log { param($Level, $Message, $Component) }
        function Invoke-PluginHook { param($HookName, $RunId, $HookData) return @{ ContinueIteration = $true } }
        function Invoke-PluginHookSafely { param($HookName, $RunId, $HookData) return @{} }
        function Get-ExecutionMode { param($CurrentRequirement, $State, $Config, $RunsDir, $RunId, $RunDir, $AgentState) return @{ Mode = 'planning'; PlanPath = $null; PlanContent = $null } }
        function New-IterationPrompt { param($Mode, $CurrentRequirement, $State, $Config, $Paths, $RunId, $RunDir, $PlanContent, $NoCommit) return 'base prompt' }
        function Get-GitState { param([string]$WorkingDir) return @{} }
        function Test-AndEnforcePlanningGuardrails { param($ProjectPath, $BeforeState, $RunId, $RunDir, $State, $StateFile) return @{ Passed = $true } }
        function Invoke-AgentExecution {
            param($AgentConfig, [string]$Prompt, [string]$ProjectPath, [string]$RunId, [string]$RunDir, [switch]$VerboseMode)
            $script:ExecutionCount++
            return @{ Output = 'Still invalid'; Succeeded = $true }
        }
        function Invoke-TaskCompletion {
            param($Output, $Mode, $CurrentRequirement, $State, $Config, $AgentState, $Paths, $RunId, $RunDir, $BeforeCommitHash, $NoCommit)
            $script:TaskCompletionCalled = $true
            return @{ ShouldContinue = $true }
        }
        function Invoke-CompletionSignals {
            param($AgentOutput, $Mode, $CurrentRequirement, $State, $AgentState, $RequirementsFile)
            return @{ ShouldExit = $false }
        }
        function New-IterationReport { param($RunDir, $Mode, $Iteration, $State, $AgentOutput) }

        try {
            $result = Invoke-FelixIteration `
                -Iteration 1 `
                -MaxIterations 5 `
                -CurrentRequirement ([pscustomobject]@{ id = 'S-0001'; title = 'Contract'; status = 'in_progress' }) `
                -State @{} `
                -Config ([pscustomobject]@{ executor = [pscustomobject]@{ default_mode = 'planning' } }) `
                -AgentConfig ([pscustomobject]@{ name = 'copilot'; key = 'ag1'; adapter = 'copilot'; executable = 'copilot' }) `
                -AgentState (New-ExecutorTestAgentState -Mode 'Planning') `
                -Paths @{
                ProjectPath      = $projectRoot
                RunsDir          = $runsDir
                StateFile        = (Join-Path $felixDir 'state.json')
                RequirementsFile = (Join-Path $felixDir 'requirements.json')
                AgentsFile       = (Join-Path $projectRoot 'AGENTS.md')
                PromptsDir       = (Join-Path $projectRoot 'prompts')
            } `
                -NoCommit

            $latestRun = Get-ChildItem $runsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $artifactPath = Join-Path $latestRun.FullName 'artifact-validation.md'

            Assert-False $result.Continue
            Assert-Equal 1 $result.ExitCode
            Assert-Equal 2 $script:ExecutionCount
            Assert-False $script:TaskCompletionCalled
            Assert-True (Test-Path $artifactPath) "Expected contract failure artifact to be written"
        }
        finally {
            Remove-Item Function:\Set-WorkflowStage -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-AgentExecutionStarted -ErrorAction SilentlyContinue
            Remove-Item Function:\Initialize-PluginSystem -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-IterationStarted -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-IterationCompleted -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Artifact -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Error -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Log -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-PluginHook -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-PluginHookSafely -ErrorAction SilentlyContinue
            Remove-Item Function:\Get-ExecutionMode -ErrorAction SilentlyContinue
            Remove-Item Function:\New-IterationPrompt -ErrorAction SilentlyContinue
            Remove-Item Function:\Get-GitState -ErrorAction SilentlyContinue
            Remove-Item Function:\Test-AndEnforcePlanningGuardrails -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-AgentExecution -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-TaskCompletion -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-CompletionSignals -ErrorAction SilentlyContinue
            Remove-Item Function:\New-IterationReport -ErrorAction SilentlyContinue
            Remove-Item Variable:\script:ExecutionCount -ErrorAction SilentlyContinue
            Remove-Item Variable:\script:TaskCompletionCalled -ErrorAction SilentlyContinue
            Remove-Item $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
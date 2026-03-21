<#
.SYNOPSIS
Tests for task-handler.ps1 - New-IterationReport
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/agent-adapters.ps1"
. "$PSScriptRoot/../core/task-handler.ps1"

function Set-WorkflowStage {
    param([string]$Stage, [string]$ProjectPath)
}

$script:UpdatedRequirementStatus = $null

function Update-RequirementStatus {
    param([string]$RequirementsFilePath, [string]$RequirementId, [string]$NewStatus)
    $script:UpdatedRequirementStatus = @{
        RequirementsFilePath = $RequirementsFilePath
        RequirementId        = $RequirementId
        NewStatus            = $NewStatus
    }
}

function New-TestAgentState {
    param([string]$Mode)

    $state = [pscustomobject]@{
        Mode              = $Mode
        TransitionHistory = @()
    }

    $state | Add-Member -MemberType ScriptMethod -Name CanTransitionTo -Value {
        param([string]$NewMode)
        return $true
    }

    $state | Add-Member -MemberType ScriptMethod -Name TransitionTo -Value {
        param([string]$NewMode)
        $this.TransitionHistory += @(@($this.Mode, $NewMode))
        $this.Mode = $NewMode
    }

    return $state
}

Describe "New-IterationReport" {

    It "should create report.md with correct mode and iteration" {
        $runDir = Join-Path $env:TEMP "test-report-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        try {
            $state = @{ last_iteration_outcome = "success" }
            New-IterationReport -RunDir $runDir -Mode "building" -Iteration 3 -State $state -AgentOutput "Agent did things"

            $reportPath = Join-Path $runDir "report.md"
            Assert-True (Test-Path $reportPath) "report.md should exist"

            $content = Get-Content $reportPath -Raw
            Assert-True ($content -match "building") "Should contain mode"
            Assert-True ($content -match "3") "Should contain iteration number"
            Assert-True ($content -match "True") "Should show success=True"
            Assert-True ($content -match "Agent did things") "Should contain agent output"
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should show failure state" {
        $runDir = Join-Path $env:TEMP "test-report-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        try {
            $state = @{ last_iteration_outcome = "failure" }
            New-IterationReport -RunDir $runDir -Mode "planning" -Iteration 1 -State $state -AgentOutput "Something failed"

            $content = Get-Content (Join-Path $runDir "report.md") -Raw
            Assert-True ($content -match "False") "Should show success=False for failure state"
            Assert-True ($content -match "planning") "Should contain mode"
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-CompletionSignals" {

    It "should transition planning mode on PLAN_COMPLETE" {
        $script:UpdatedRequirementStatus = $null
        $state = @{ last_mode = "planning" }
        $agentState = New-TestAgentState -Mode "Planning"
        $requirementsFile = Join-Path $env:TEMP "req-$(Get-Random).json"
        Set-Content $requirementsFile '{}' -Encoding UTF8

        try {
            $result = Invoke-CompletionSignals `
                -AgentOutput "<promise>PLAN_COMPLETE</promise>" `
                -Mode "planning" `
                -CurrentRequirement ([pscustomobject]@{ id = "S-0001" }) `
                -State $state `
                -AgentState $agentState `
                -RequirementsFile $requirementsFile

            Assert-False $result.ShouldExit
            Assert-Equal "building" $state.last_mode
            Assert-Equal "Building" $agentState.Mode
            Assert-Null $script:UpdatedRequirementStatus
        }
        finally {
            Remove-Item $requirementsFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should support PLANNING_COMPLETE compatibility alias" {
        $state = @{ last_mode = "planning" }
        $agentState = New-TestAgentState -Mode "Planning"
        $requirementsFile = Join-Path $env:TEMP "req-$(Get-Random).json"
        Set-Content $requirementsFile '{}' -Encoding UTF8

        try {
            $result = Invoke-CompletionSignals `
                -AgentOutput "<promise>PLANNING_COMPLETE</promise>" `
                -Mode "planning" `
                -CurrentRequirement ([pscustomobject]@{ id = "S-0001" }) `
                -State $state `
                -AgentState $agentState `
                -RequirementsFile $requirementsFile

            Assert-False $result.ShouldExit
            Assert-Equal "building" $state.last_mode
            Assert-Equal "Building" $agentState.Mode
        }
        finally {
            Remove-Item $requirementsFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should prefer ALL_COMPLETE over TASK_COMPLETE" {
        $script:UpdatedRequirementStatus = $null
        $state = @{ last_mode = "building" }
        $agentState = New-TestAgentState -Mode "Building"
        $requirementsFile = Join-Path $env:TEMP "req-$(Get-Random).json"
        Set-Content $requirementsFile '{}' -Encoding UTF8

        try {
            $result = Invoke-CompletionSignals `
                -AgentOutput ("<promise>TASK_COMPLETE</promise>`n<promise>ALL_COMPLETE</promise>") `
                -Mode "building" `
                -CurrentRequirement ([pscustomobject]@{ id = "S-0001" }) `
                -State $state `
                -AgentState $agentState `
                -RequirementsFile $requirementsFile

            Assert-True $result.ShouldExit
            Assert-Equal 0 $result.ExitCode
            Assert-Equal "complete" $script:UpdatedRequirementStatus.NewStatus
            Assert-Equal "Complete" $agentState.Mode
        }
        finally {
            Remove-Item $requirementsFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should reject inline completion tags" {
        $script:UpdatedRequirementStatus = $null
        $state = @{ last_mode = "building" }
        $agentState = New-TestAgentState -Mode "Building"
        $requirementsFile = Join-Path $env:TEMP "req-$(Get-Random).json"
        Set-Content $requirementsFile '{}' -Encoding UTF8

        try {
            $result = Invoke-CompletionSignals `
                -AgentOutput "status: <promise>TASK_COMPLETE</promise>" `
                -Mode "building" `
                -CurrentRequirement ([pscustomobject]@{ id = "S-0001" }) `
                -State $state `
                -AgentState $agentState `
                -RequirementsFile $requirementsFile

            Assert-False $result.ShouldExit
            Assert-Null $script:UpdatedRequirementStatus
            Assert-Equal "Building" $agentState.Mode
        }
        finally {
            Remove-Item $requirementsFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults

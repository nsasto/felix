<#
.SYNOPSIS
Tests for task-handler.ps1 - New-IterationReport
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/task-handler.ps1"

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

Get-TestResults

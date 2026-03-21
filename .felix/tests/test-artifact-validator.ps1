. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-adapters.ps1"
. "$PSScriptRoot/../core/artifact-validator.ps1"

function New-TestPlanContent {
    param(
        [string[]]$Tasks
    )

    $taskLines = $Tasks -join "`n"
    return @"
# Implementation Plan for S-0001

## Summary

Plan summary.

## Tasks

$taskLines
"@
}

Describe "Test-PlanningArtifact" {

    It "should fail when the planning plan file is missing" {
        $runDir = Join-Path $env:TEMP "artifact-plan-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        try {
            $result = Test-PlanningArtifact -RunDir $runDir -RequirementId "S-0001"
            Assert-False $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should fail when the planning plan file is malformed" {
        $runDir = Join-Path $env:TEMP "artifact-plan-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        Set-Content (Join-Path $runDir "plan-S-0001.md") "not a plan" -Encoding UTF8

        try {
            $result = Test-PlanningArtifact -RunDir $runDir -RequirementId "S-0001"
            Assert-False $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should pass when the planning plan file has required structure" {
        $runDir = Join-Path $env:TEMP "artifact-plan-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $content = New-TestPlanContent -Tasks @('- [ ] First task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $content -Encoding UTF8

        try {
            $result = Test-PlanningArtifact -RunDir $runDir -RequirementId "S-0001"
            Assert-True $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-BuildingArtifact" {

    It "should fail when no plan items were checked off" {
        $runDir = Join-Path $env:TEMP "artifact-build-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $previous = New-TestPlanContent -Tasks @('- [ ] First task', '- [ ] Second task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $previous -Encoding UTF8

        try {
            $result = Test-BuildingArtifact -RunDir $runDir -RequirementId "S-0001" -PreviousPlanContent $previous -Signal "TASK_COMPLETE"
            Assert-False $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should fail when ALL_COMPLETE leaves unchecked tasks" {
        $runDir = Join-Path $env:TEMP "artifact-build-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $previous = New-TestPlanContent -Tasks @('- [ ] First task', '- [ ] Second task')
        $updated = New-TestPlanContent -Tasks @('- [x] First task', '- [ ] Second task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $updated -Encoding UTF8

        try {
            $result = Test-BuildingArtifact -RunDir $runDir -RequirementId "S-0001" -PreviousPlanContent $previous -Signal "ALL_COMPLETE"
            Assert-False $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should pass when TASK_COMPLETE checks off a new plan item" {
        $runDir = Join-Path $env:TEMP "artifact-build-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $previous = New-TestPlanContent -Tasks @('- [ ] First task', '- [ ] Second task')
        $updated = New-TestPlanContent -Tasks @('- [x] First task', '- [ ] Second task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $updated -Encoding UTF8

        try {
            $result = Test-BuildingArtifact -RunDir $runDir -RequirementId "S-0001" -PreviousPlanContent $previous -Signal "TASK_COMPLETE"
            Assert-True $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should pass when ALL_COMPLETE checks off all remaining plan items" {
        $runDir = Join-Path $env:TEMP "artifact-build-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $previous = New-TestPlanContent -Tasks @('- [ ] First task', '- [ ] Second task')
        $updated = New-TestPlanContent -Tasks @('- [x] First task', '- [x] Second task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $updated -Encoding UTF8

        try {
            $result = Test-BuildingArtifact -RunDir $runDir -RequirementId "S-0001" -PreviousPlanContent $previous -Signal "ALL_COMPLETE"
            Assert-True $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-IterationArtifacts" {

    It "should require planning artifacts when PLAN_COMPLETE is emitted" {
        $runDir = Join-Path $env:TEMP "artifact-iter-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        try {
            $result = Test-IterationArtifacts -Mode "planning" -RunDir $runDir -RequirementId "S-0001" -AgentOutput "<promise>PLAN_COMPLETE</promise>"
            Assert-True $result.IsRequired
            Assert-False $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should require building artifacts when task completion is emitted" {
        $runDir = Join-Path $env:TEMP "artifact-iter-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $previous = New-TestPlanContent -Tasks @('- [ ] First task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $previous -Encoding UTF8

        try {
            $result = Test-IterationArtifacts -Mode "building" -RunDir $runDir -RequirementId "S-0001" -AgentOutput "**Task Completed:** Finished it" -PreviousPlanContent $previous
            Assert-True $result.IsRequired
            Assert-False $result.IsValid
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
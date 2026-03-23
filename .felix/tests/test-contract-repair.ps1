. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-adapters.ps1"
. "$PSScriptRoot/../core/artifact-validator.ps1"

function New-RepairPlanContent {
    param([string[]]$Tasks)

    return @"
# Implementation Plan for S-0001

## Summary

Repair plan.

## Tasks

$($Tasks -join "`n")
"@
}

Describe "Invoke-ContractRepairFlow" {

    It "should not retry when planning output has no signal but plan file is valid" {
        $runDir = Join-Path $env:TEMP "repair-flow-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        Set-Content (Join-Path $runDir "plan-S-0001.md") (New-RepairPlanContent -Tasks @('- [ ] Draft task')) -Encoding UTF8

        try {
            $result = Invoke-ContractRepairFlow `
                -BasePrompt "base prompt" `
                -Mode "planning" `
                -RunDir $runDir `
                -RequirementId "S-0001" `
                -InitialOutput "No completion marker" `
                -RetryExecution {
                    param($RepairPrompt, $AttemptNumber)
                    return @{
                        Succeeded = $true
                        Output    = '{"mode":"planning","completion":{"signal":"PLAN_COMPLETE"}}'
                    }
                }

            Assert-True $result.IsValid
            Assert-Equal 0 $result.RetryAttempts
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should retry once when planning output is missing the plan artifact" {
        $runDir = Join-Path $env:TEMP "repair-flow-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        try {
            $result = Invoke-ContractRepairFlow `
                -BasePrompt "base prompt" `
                -Mode "planning" `
                -RunDir $runDir `
                -RequirementId "S-0001" `
                -InitialOutput "<promise>PLAN_COMPLETE</promise>" `
                -RetryExecution {
                    param($RepairPrompt, $AttemptNumber)
                    Set-Content (Join-Path $runDir "plan-S-0001.md") (New-RepairPlanContent -Tasks @('- [ ] Draft task')) -Encoding UTF8
                    return @{
                        Succeeded = $true
                        Output    = "<promise>PLAN_COMPLETE</promise>"
                    }
                }

            Assert-True $result.IsValid
            Assert-Equal 1 $result.RetryAttempts
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should retry once when building output leaves plan unchanged" {
        $runDir = Join-Path $env:TEMP "repair-flow-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $previousPlan = New-RepairPlanContent -Tasks @('- [ ] First task', '- [ ] Second task')
        Set-Content (Join-Path $runDir "plan-S-0001.md") $previousPlan -Encoding UTF8

        try {
            $result = Invoke-ContractRepairFlow `
                -BasePrompt "base prompt" `
                -Mode "building" `
                -RunDir $runDir `
                -RequirementId "S-0001" `
                -InitialOutput '{"mode":"building","completion":{"signal":"TASK_COMPLETE"}}' `
                -PreviousPlanContent $previousPlan `
                -RetryExecution {
                    param($RepairPrompt, $AttemptNumber)
                    Set-Content (Join-Path $runDir "plan-S-0001.md") (New-RepairPlanContent -Tasks @('- [x] First task', '- [ ] Second task')) -Encoding UTF8
                    return @{
                        Succeeded = $true
                        Output    = '{"mode":"building","completion":{"signal":"TASK_COMPLETE"}}'
                    }
                }

            Assert-True $result.IsValid
            Assert-Equal 1 $result.RetryAttempts
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should fail cleanly after one invalid retry" {
        $runDir = Join-Path $env:TEMP "repair-flow-$(Get-Random)"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        Set-Content (Join-Path $runDir "plan-S-0001.md") (New-RepairPlanContent -Tasks @('- [ ] Draft task')) -Encoding UTF8

        try {
            $result = Invoke-ContractRepairFlow `
                -BasePrompt "base prompt" `
                -Mode "building" `
                -RunDir $runDir `
                -RequirementId "S-0001" `
                -InitialOutput '{"mode":"building","completion":{"signal":"TASK_COMPLETE"}}' `
                -PreviousPlanContent (New-RepairPlanContent -Tasks @('- [ ] Draft task')) `
                -RetryExecution {
                    param($RepairPrompt, $AttemptNumber)
                    return @{
                        Succeeded = $true
                        Output    = '{"mode":"building","completion":{"signal":"TASK_COMPLETE"}}'
                    }
                }

            Assert-False $result.IsValid
            Assert-Equal 1 $result.RetryAttempts
            Assert-True ($result.Validation.Reason -match 'without checking off any plan items') "Expected failure reason to explain the unchanged plan"
        }
        finally {
            Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
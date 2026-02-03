<#
.SYNOPSIS
Tests for requirements utilities
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/requirements-utils.ps1"

Describe "Update-RequirementStatus" {

    It "should update requirement status" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        
        $requirements = @{
            requirements = @(
                @{
                    id          = "R-001"
                    status      = "planned"
                    description = "Test requirement"
                }
            )
        }
        $requirements | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $result = Update-RequirementStatus -RequirementsFilePath $tempFile -RequirementId "R-001" -NewStatus "in_progress"
        
        Assert-True $result
        
        $updated = Get-Content $tempFile -Raw | ConvertFrom-Json
        Assert-Equal "in_progress" $updated.requirements[0].status
        
        Remove-Item $tempFile -Force
    }

    It "should return false for non-existent requirement" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        
        $requirements = @{
            requirements = @()
        }
        $requirements | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $result = Update-RequirementStatus -RequirementsFilePath $tempFile -RequirementId "R-999" -NewStatus "complete"
        
        Assert-False $result
        
        Remove-Item $tempFile -Force
    }

    It "should handle missing requirements array" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        
        "{}" | Set-Content $tempFile
        
        $result = Update-RequirementStatus -RequirementsFilePath $tempFile -RequirementId "R-001" -NewStatus "complete"
        
        Assert-False $result
        
        Remove-Item $tempFile -Force
    }
}

Describe "Update-RequirementRunId" {

    It "should update requirement run ID" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        
        $requirements = @{
            requirements = @(
                @{
                    id          = "R-001"
                    status      = "in_progress"
                    last_run_id = $null
                }
            )
        }
        $requirements | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $result = Update-RequirementRunId -RequirementsFilePath $tempFile -RequirementId "R-001" -RunId "run-123"
        
        Assert-True $result
        
        $updated = Get-Content $tempFile -Raw | ConvertFrom-Json
        Assert-Equal "run-123" $updated.requirements[0].last_run_id
        
        Remove-Item $tempFile -Force
    }

    It "should return false for non-existent requirement" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        
        $requirements = @{
            requirements = @()
        }
        $requirements | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $result = Update-RequirementRunId -RequirementsFilePath $tempFile -RequirementId "R-999" -RunId "run-123"
        
        Assert-False $result
        
        Remove-Item $tempFile -Force
    }
}

Describe "Invoke-RequirementValidation" {

    It "should return exit code 0 when validation script succeeds" {
        $tempScript = New-Item -ItemType File -Path "$env:TEMP/test-validate-$(Get-Random).ps1" -Force
        "exit 0" | Set-Content $tempScript
        
        $result = Invoke-RequirementValidation -ValidationScript $tempScript -RequirementId "R-001"
        
        Assert-Equal 0 $result.exitCode
        
        Remove-Item $tempScript -Force
    }

    It "should return exit code 1 when validation script fails" {
        $tempScript = New-Item -ItemType File -Path "$env:TEMP/test-validate-$(Get-Random).ps1" -Force
        "exit 1" | Set-Content $tempScript
        
        $result = Invoke-RequirementValidation -ValidationScript $tempScript -RequirementId "R-001"
        
        Assert-Equal 1 $result.exitCode
        
        Remove-Item $tempScript -Force
    }

    It "should return exit code 1 when validation script not found" {
        $result = Invoke-RequirementValidation -ValidationScript "nonexistent.ps1" -RequirementId "R-001"
        
        Assert-Equal 1 $result.exitCode
    }

    It "should return exit code 0 when validation script throws but exits 0" {
        $tempScript = New-Item -ItemType File -Path "$env:TEMP/test-validate-$(Get-Random).ps1" -Force
        @"
Write-Error "This is an error"
exit 0
"@ | Set-Content $tempScript
        
        $result = Invoke-RequirementValidation -ValidationScript $tempScript -RequirementId "R-001"
        
        Assert-Equal 0 $result.exitCode
        
        Remove-Item $tempScript -Force
    }
}


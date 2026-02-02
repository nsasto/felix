<#
.SYNOPSIS
Tests for requirements state management
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/test-helpers.ps1"
. "$PSScriptRoot/../core/state-manager.ps1"

Describe "Requirements State Loading" {

    It "should load valid requirements file" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Test 1"),
            (New-TestRequirement -Id "S-0002" -Title "Test 2")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        $state = Get-RequirementsState $requirementsFile

        Assert-Equal 2 $state.requirements.Count
        Assert-Equal "S-0001" $state.requirements[0].id

        Remove-TestRepository $repoPath
    }

    It "should throw when file not found" {
        Assert-Throws {
            Get-RequirementsState "nonexistent.json"
        }
    }

    It "should throw when JSON is invalid" {
        $tempFile = Join-Path $env:TEMP "invalid-$(Get-Random).json"
        "{ invalid json" | Out-File $tempFile

        Assert-Throws {
            Get-RequirementsState $tempFile
        }

        Remove-Item $tempFile
    }
}

Describe "Requirements State Saving" {

    It "should save state with proper formatting" {
        $repoPath = New-TestRepository
        $requirementsFile = Join-Path $repoPath "felix/requirements.json"

        $state = @{
            requirements = @(
                @{ id = "S-0001"; title = "Test"; status = "planned" }
            )
        }

        Save-RequirementsState $requirementsFile $state

        Assert-FileExists $requirementsFile

        # Verify it's valid JSON
        $loaded = Get-Content $requirementsFile -Raw | ConvertFrom-Json
        Assert-Equal "S-0001" $loaded.requirements[0].id

        Remove-TestRepository $repoPath
    }
}

Describe "Next Requirement Selection" {

    It "should select in_progress requirement first" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "First" -Status "planned"),
            (New-TestRequirement -Id "S-0002" -Title "Second" -Status "in_progress"),
            (New-TestRequirement -Id "S-0003" -Title "Third" -Status "planned")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        Assert-Equal "S-0002" $next.id

        Remove-TestRepository $repoPath
    }

    It "should select planned requirement when no in_progress" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "First" -Status "planned"),
            (New-TestRequirement -Id "S-0002" -Title "Second" -Status "complete")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        Assert-Equal "S-0001" $next.id

        Remove-TestRepository $repoPath
    }

    It "should respect dependencies" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Base" -Status "planned"),
            (New-TestRequirement -Id "S-0002" -Title "Dependent" -Status "planned" -DependsOn @("S-0001"))
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        # Should select S-0001 first because S-0002 depends on it
        Assert-Equal "S-0001" $next.id

        Remove-TestRepository $repoPath
    }

    It "should return null when no requirements available" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Done" -Status "complete")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        Assert-Null $next

        Remove-TestRepository $repoPath
    }
}

Describe "Requirement Status Update" {

    It "should update status successfully" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Test")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        Update-RequirementStatus $requirementsFile "S-0001" "in_progress"

        $state = Get-RequirementsState $requirementsFile
        Assert-Equal "in_progress" $state.requirements[0].status

        Remove-TestRepository $repoPath
    }

    It "should update branch when provided" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Test")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"
        Update-RequirementStatus $requirementsFile "S-0001" "in_progress" "feature/S-0001"

        $state = Get-RequirementsState $requirementsFile
        Assert-Equal "feature/S-0001" $state.requirements[0].branch

        Remove-TestRepository $repoPath
    }

    It "should throw when requirement not found" {
        $repoPath = New-TestRepository

        $requirementsFile = Join-Path $repoPath "felix/requirements.json"

        Assert-Throws {
            Update-RequirementStatus $requirementsFile "S-9999" "complete"
        }

        Remove-TestRepository $repoPath
    }
}

Get-TestResults

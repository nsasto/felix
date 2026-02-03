<#
.SYNOPSIS
Tests for initialization module
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/exit-handler.ps1"
. "$PSScriptRoot/../core/initialization.ps1"

Describe "Initialize-ExecutionState" {

    It "should create default state when file doesn't exist" {
        $state = Initialize-ExecutionState -StateFile "nonexistent.json"
        
        Assert-NotNull $state
        Assert-Null $state.current_requirement_id
        Assert-Equal 0 $state.current_iteration
        Assert-Equal "idle" $state.status
        Assert-Equal 0 $state.validation_retry_count
    }

    It "should load valid state file" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-state-$(Get-Random).json" -Force
        @{
            current_requirement_id = "R-001"
            current_iteration = 5
            last_mode = "building"
            status = "running"
            validation_retry_count = 1
        } | ConvertTo-Json | Set-Content $tempFile
        
        $state = Initialize-ExecutionState -StateFile $tempFile
        
        Assert-Equal "R-001" $state.current_requirement_id
        Assert-Equal 5 $state.current_iteration
        Assert-Equal "building" $state.last_mode
        
        Remove-Item $tempFile -Force
    }

    It "should handle empty state file" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-state-$(Get-Random).json" -Force
        "" | Set-Content $tempFile
        
        $state = Initialize-ExecutionState -StateFile $tempFile
        
        Assert-NotNull $state
        Assert-Equal "idle" $state.status
        
        Remove-Item $tempFile -Force
    }
}

Describe "Get-CurrentRequirement" {

    It "should find specific requirement by ID" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        @{
            requirements = @(
                @{
                    id = "R-001"
                    title = "Test 1"
                    status = "planned"
                }
                @{
                    id = "R-002"
                    title = "Test 2"
                    status = "planned"
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $req = Get-CurrentRequirement -RequirementsFile $tempFile -RequirementId "R-002"
        
        Assert-NotNull $req
        Assert-Equal "R-002" $req.id
        Assert-Equal "Test 2" $req.title
        
        Remove-Item $tempFile -Force
    }

    It "should find first planned requirement" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        @{
            requirements = @(
                @{
                    id = "R-001"
                    title = "Test 1"
                    status = "complete"
                }
                @{
                    id = "R-002"
                    title = "Test 2"
                    status = "planned"
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $req = Get-CurrentRequirement -RequirementsFile $tempFile
        
        Assert-NotNull $req
        Assert-Equal "R-002" $req.id
        
        Remove-Item $tempFile -Force
    }

    It "should return null for complete requirement" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-requirements-$(Get-Random).json" -Force
        @{
            requirements = @(
                @{
                    id = "R-001"
                    title = "Test 1"
                    status = "complete"
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $tempFile
        
        $req = Get-CurrentRequirement -RequirementsFile $tempFile -RequirementId "R-001"
        
        Assert-Null $req
        
        Remove-Item $tempFile -Force
    }
}

Describe "Initialize-StateForRequirement" {

    It "should initialize validation_retry_count if missing" {
        $state = @{
            current_requirement_id = $null
        }
        $req = [PSCustomObject]@{
            id = "R-001"
        }
        
        $updated = Initialize-StateForRequirement -State $state -Requirement $req
        
        Assert-Equal 0 $updated.validation_retry_count
    }

    It "should reset state for new requirement" {
        $state = @{
            current_requirement_id = "R-OLD"
            current_iteration = 5
            validation_retry_count = 2
            status = "blocked"
            blocked_task = "something"
        }
        $req = [PSCustomObject]@{
            id = "R-NEW"
        }
        
        $updated = Initialize-StateForRequirement -State $state -Requirement $req
        
        Assert-Equal "R-NEW" $updated.current_requirement_id
        Assert-Equal 0 $updated.current_iteration
        Assert-Equal 0 $updated.validation_retry_count
        Assert-Equal "ready" $updated.status
        Assert-Null $updated.blocked_task
    }

    It "should not reset state for same requirement" {
        $state = @{
            current_requirement_id = "R-001"
            current_iteration = 3
            validation_retry_count = 1
        }
        $req = [PSCustomObject]@{
            id = "R-001"
        }
        
        $updated = Initialize-StateForRequirement -State $state -Requirement $req
        
        Assert-Equal "R-001" $updated.current_requirement_id
        Assert-Equal 3 $updated.current_iteration
        Assert-Equal 1 $updated.validation_retry_count
    }
}

Describe "Initialize-PluginState" {

    It "should initialize plugin state variables" {
        # This function sets script-scoped variables
        # We can only verify it doesn't throw errors
        Initialize-PluginState
        
        # Function should complete without error
        Assert-True $true
    }
}

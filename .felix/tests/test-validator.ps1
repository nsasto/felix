<#
.SYNOPSIS
Tests for backpressure validation system
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/validator.ps1"

Describe "Get-BackpressureCommands" {

    It "should use config commands when provided" {
        $commands = Get-BackpressureCommands -AgentsFilePath "nonexistent.md" -ConfigCommands @("pytest", "npm test")
        
        Assert-Equal 2 $commands.Count
        Assert-Equal "pytest" $commands[0].command
        Assert-Equal "config" $commands[0].type
        Assert-Equal "npm test" $commands[1].command
    }

    It "should return empty array when AGENTS.md not found" {
        $commands = Get-BackpressureCommands -AgentsFilePath "nonexistent.md"
        
        Assert-Equal 0 $commands.Count
    }

    It "should parse commands from AGENTS.md" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-agents-$(Get-Random).md" -Force
        
        $content = @"
# AGENTS.md

## Run Tests

``````bash
pytest tests/
npm test
``````

## Build the Project

``````bash
npm run build
``````
"@
        Set-Content $tempFile $content
        
        $commands = Get-BackpressureCommands -AgentsFilePath $tempFile
        
        Assert-Equal 3 $commands.Count
        Assert-Equal "pytest tests/" $commands[0].command
        Assert-Equal "test" $commands[0].type
        Assert-Equal "npm test" $commands[1].command
        Assert-Equal "npm run build" $commands[2].command
        Assert-Equal "build" $commands[2].type
        
        Remove-Item $tempFile -Force
    }

    It "should skip comment lines and empty lines" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-agents-$(Get-Random).md" -Force
        
        $content = @"
# AGENTS.md

## Run Tests

``````bash
# Comment to skip
pytest tests/
``````
"@
        Set-Content $tempFile $content
        
        $commands = Get-BackpressureCommands -AgentsFilePath $tempFile
        
        # Should have the pytest command
        Assert-True ($commands.Count -ge 1)
        $pytestCmd = $commands | Where-Object { $_.command -eq "pytest tests/" }
        Assert-NotNull $pytestCmd
        
        Remove-Item $tempFile -Force
    }
}

Describe "Invoke-BackpressureValidation" {

    It "should skip when backpressure is disabled" {
        $config = [PSCustomObject]@{
            backpressure = @{
                enabled = $false
            }
        }
        
        $result = Invoke-BackpressureValidation -WorkingDir $PWD -AgentsFilePath "test.md" -Config $config -RunDir $null
        
        Assert-True $result.skipped
        Assert-True $result.success
    }

    It "should skip when no commands found" {
        $config = [PSCustomObject]@{
            backpressure = @{
                enabled  = $true
                commands = @()
            }
        }
        
        $result = Invoke-BackpressureValidation -WorkingDir $PWD -AgentsFilePath "nonexistent.md" -Config $config -RunDir $null
        
        Assert-True $result.skipped
        Assert-True $result.success
    }

    It "should execute commands and report success" {
        $config = [PSCustomObject]@{
            backpressure = @{
                enabled  = $true
                commands = @("cmd /c exit 0")
            }
        }
        
        $result = Invoke-BackpressureValidation -WorkingDir $PWD -AgentsFilePath "test.md" -Config $config -RunDir $null
        
        Assert-True $result.success
        Assert-Equal 0 $result.failed_commands.Count
    }

    It "should detect command failures" {
        $config = [PSCustomObject]@{
            backpressure = @{
                enabled  = $true
                commands = @("cmd /c exit 1")
            }
        }
        
        $result = Invoke-BackpressureValidation -WorkingDir $PWD -AgentsFilePath "test.md" -Config $config -RunDir $null
        
        Assert-False $result.success
        Assert-Equal 1 $result.failed_commands.Count
    }

    It "should write validation log when RunDir provided" {
        $runDir = New-Item -ItemType Directory -Path "$env:TEMP/test-run-$(Get-Random)" -Force
        
        $config = [PSCustomObject]@{
            backpressure = @{
                enabled  = $true
                commands = @("cmd /c exit 0")
            }
        }
        
        $result = Invoke-BackpressureValidation -WorkingDir $PWD -AgentsFilePath "test.md" -Config $config -RunDir $runDir
        
        $logPath = Join-Path $runDir "backpressure.log"
        Assert-FileExists $logPath
        
        Remove-Item $runDir -Recurse -Force
    }
}

Get-TestResults


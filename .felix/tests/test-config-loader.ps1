<#
.SYNOPSIS
Tests for configuration loading
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/config-loader.ps1"

Describe "Get-ProjectPaths" {

    It "should compute all project paths" {
        $paths = Get-ProjectPaths -ProjectPath "C:\Test\Project"
        
        Assert-Equal "C:\Test\Project" $paths.ProjectPath
        Assert-Equal "C:\Test\Project\specs" $paths.SpecsDir
        Assert-Equal "C:\Test\Project\.felix" $paths.FelixDir
        Assert-Equal "C:\Test\Project\runs" $paths.RunsDir
        Assert-Equal "C:\Test\Project\AGENTS.md" $paths.AgentsFile
        Assert-Equal "C:\Test\Project\.felix\agents.json" $paths.AgentsJsonFile
        Assert-Equal "C:\Test\Project\.felix\config.json" $paths.ConfigFile
        Assert-Equal "C:\Test\Project\.felix\state.json" $paths.StateFile
        Assert-Equal "C:\Test\Project\.felix\requirements.json" $paths.RequirementsFile
        # PromptsDir is relative to the core script location, not ProjectPath
        Assert-True (Test-Path $paths.PromptsDir -IsValid) "PromptsDir should be a valid path"
    }
}

Describe "Test-ProjectStructure" {

    It "should return true for valid project" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-project-$(Get-Random)" -Force
        $felixDir = New-Item -ItemType Directory -Path "$tempDir/.felix" -Force
        $specsDir = New-Item -ItemType Directory -Path "$tempDir/specs" -Force
        "{}" | Set-Content "$felixDir/config.json"
        "{}" | Set-Content "$felixDir/requirements.json"
        
        $paths = Get-ProjectPaths -ProjectPath $tempDir
        $result = Test-ProjectStructure -Paths $paths
        
        Assert-True $result
        
        Remove-Item $tempDir -Recurse -Force
    }

    It "should return false for invalid project" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-project-$(Get-Random)" -Force
        
        $paths = Get-ProjectPaths -ProjectPath $tempDir
        $result = Test-ProjectStructure -Paths $paths
        
        Assert-False $result
        
        Remove-Item $tempDir -Recurse -Force
    }
}

Describe "Get-FelixConfig" {

    It "should load valid config file" {
        $tempFile = New-Item -ItemType File -Path "$env:TEMP/test-config-$(Get-Random).json" -Force
        @{
            executor = @{
                max_iterations = 10
                default_mode   = "planning"
            }
        } | ConvertTo-Json | Set-Content $tempFile
        
        $config = Get-FelixConfig -ConfigFile $tempFile
        
        Assert-NotNull $config
        Assert-Equal 10 $config.executor.max_iterations
        
        Remove-Item $tempFile -Force
    }

    It "should return null for missing config file" {
        $config = Get-FelixConfig -ConfigFile "nonexistent.json"
        
        Assert-Null $config
    }
}

Describe "Get-AgentsConfiguration" {

    It "should load existing agents.json" {
        $tempHome = New-Item -ItemType Directory -Path "$env:TEMP/test-felix-home-$(Get-Random)" -Force
        $agentsFile = Join-Path $tempHome "agents.json"
        
        @{
            agents = @(
                @{
                    id                = 0
                    name              = "test-agent"
                    executable        = "test"
                    working_directory = "."
                    environment       = @{}
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $agentsFile
        
        $agentsData = Get-AgentsConfiguration -AgentsJsonFile $agentsFile
        
        Assert-NotNull $agentsData
        Assert-Equal 1 $agentsData.agents.Count
        Assert-Equal "test-agent" $agentsData.agents[0].name
        
        Remove-Item $tempHome -Recurse -Force
    }

    It "should create default agents.json if missing" {
        $tempHome = New-Item -ItemType Directory -Path "$env:TEMP/test-felix-home-$(Get-Random)" -Force
        
        $agentsFile = Join-Path $tempHome "agents.json"
        $agentsData = Get-AgentsConfiguration -AgentsJsonFile $agentsFile
        
        Assert-NotNull $agentsData
        Assert-True ($agentsData.agents.Count -ge 1)
        Assert-Equal "droid" $agentsData.agents[0].name
        
        Remove-Item $tempHome -Recurse -Force
    }
}

Describe "Get-AgentConfig" {

    It "should return correct agent by ID" {
        $agentsData = [PSCustomObject]@{
            agents = @(
                [PSCustomObject]@{
                    id         = 0
                    name       = "agent-0"
                    executable = "test0"
                }
                [PSCustomObject]@{
                    id         = 1
                    name       = "agent-1"
                    executable = "test1"
                }
            )
        }
        
        $agent = Get-AgentConfig -AgentsData $agentsData -AgentId 1
        
        Assert-NotNull $agent
        Assert-Equal "agent-1" $agent.name
    }

    It "should return correct agent by key" {
        $agentsData = [PSCustomObject]@{
            agents = @(
                [PSCustomObject]@{
                    key        = "ag_first123"
                    name       = "agent-a"
                    executable = "testa"
                }
                [PSCustomObject]@{
                    key        = "ag_second456"
                    name       = "agent-b"
                    executable = "testb"
                }
            )
        }

        $agent = Get-AgentConfig -AgentsData $agentsData -AgentId "ag_second456"

        Assert-NotNull $agent
        Assert-Equal "agent-b" $agent.name
        Assert-Equal "ag_second456" $agent.key
    }

    It "should normalize legacy id to key" {
        $agentsData = [PSCustomObject]@{
            agents = @(
                [PSCustomObject]@{
                    id         = "ag_legacy123"
                    name       = "legacy-agent"
                    executable = "legacy"
                }
            )
        }

        $agent = Get-AgentConfig -AgentsData $agentsData -AgentId "ag_legacy123"

        Assert-NotNull $agent
        Assert-Equal "ag_legacy123" $agent.key
    }

    It "should fallback to ID 0 for missing agent" {
        $agentsData = [PSCustomObject]@{
            agents = @(
                [PSCustomObject]@{
                    id         = 0
                    name       = "agent-0"
                    executable = "test0"
                }
            )
        }
        
        $agent = Get-AgentConfig -AgentsData $agentsData -AgentId 99
        
        Assert-NotNull $agent
        Assert-Equal "agent-0" $agent.name
    }
}


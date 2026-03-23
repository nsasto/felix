. "$PSScriptRoot/test-framework.ps1"

Describe "Invoke-Agent target normalization" {

    It "should preserve full agent name for agent use when target arrives as split characters" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $tempRoot = Join-Path $env:TEMP "felix-agent-targets-$(Get-Random)"
        $felixDir = Join-Path $tempRoot ".felix"

        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

        $agentsJson = @{
            agents = @(
                @{
                    key        = "ag_61a011bca"
                    name       = "copilot"
                    adapter    = "copilot"
                    executable = "copilot"
                    model      = "gpt-5.4"
                }
            )
        } | ConvertTo-Json -Depth 10
        Set-Content (Join-Path $felixDir "agents.json") $agentsJson -Encoding UTF8

        $configJson = @{
            agent = @{ agent_id = "ag_old00000" }
            sync  = @{ enabled = $false; provider = "http"; base_url = "https://api.runfelix.io"; api_key = $null }
        } | ConvertTo-Json -Depth 10
        Set-Content (Join-Path $felixDir "config.json") $configJson -Encoding UTF8

        Push-Location $repoRoot
        try {
            . ".\.felix\commands\agent.ps1"

            Invoke-Agent -ProjectRoot $tempRoot -AgentArgs @("use", "c", "o", "p", "i", "l", "o", "t")

            Assert-True $true "Expected split-character agent key to resolve without 'Agent not found'"
        }
        finally {
            Pop-Location
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should preserve full agent name for agent set-default when target arrives as split characters" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $tempRoot = Join-Path $env:TEMP "felix-agent-targets-$(Get-Random)"
        $felixDir = Join-Path $tempRoot ".felix"

        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

        $agentsJson = @{
            agents = @(
                @{
                    key        = "ag_61a011bca"
                    name       = "copilot"
                    adapter    = "copilot"
                    executable = "copilot"
                    model      = "gpt-5.4"
                }
            )
        } | ConvertTo-Json -Depth 10
        Set-Content (Join-Path $felixDir "agents.json") $agentsJson -Encoding UTF8

        $configJson = @{
            agent = @{ agent_id = "ag_old00000" }
            sync  = @{ enabled = $false; provider = "http"; base_url = "https://api.runfelix.io"; api_key = $null }
        } | ConvertTo-Json -Depth 10
        Set-Content (Join-Path $felixDir "config.json") $configJson -Encoding UTF8

        Push-Location $repoRoot
        try {
            . ".\.felix\commands\agent.ps1"

            Invoke-Agent -ProjectRoot $tempRoot -AgentArgs @("set-default", "c", "o", "p", "i", "l", "o", "t")

            Assert-True $true "Expected split-character default agent key to resolve without 'Agent not found'"
        }
        finally {
            Pop-Location
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

}

Get-TestResults
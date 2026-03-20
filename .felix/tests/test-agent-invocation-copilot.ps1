param()

$ErrorActionPreference = "Stop"

function New-TempDir {
    param([string]$Prefix)
    $base = Join-Path $env:TEMP $Prefix
    $suffix = [Guid]::NewGuid().ToString("N")
    $path = "$base-$suffix"
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$felixAgentScript = Join-Path $repoRoot ".felix\felix-agent.ps1"
$shimScript = Join-Path $repoRoot ".felix\tests\agent-shim-argv.cmd"

Assert-True (Test-Path $felixAgentScript) "Missing .felix/felix-agent.ps1 at $felixAgentScript"
Assert-True (Test-Path $shimScript) "Missing agent shim at $shimScript"

$projectRoot = New-TempDir -Prefix "felix-agent-invoke-copilot-project"

try {
    $specsDir = Join-Path $projectRoot "specs"
    $felixDir = Join-Path $projectRoot ".felix"
    $promptsDir = Join-Path $felixDir "prompts"
    $runsDir = Join-Path $projectRoot "runs"
    $agentWorkDirRel = "agent-workdir"
    $agentWorkDirAbs = Join-Path $projectRoot $agentWorkDirRel

    New-Item -ItemType Directory -Path $specsDir, $felixDir, $promptsDir, $runsDir, $agentWorkDirAbs -Force | Out-Null

    Set-Content (Join-Path $promptsDir "planning.md") "# planning" -Encoding UTF8
    Set-Content (Join-Path $promptsDir "building.md") "# building" -Encoding UTF8
    Set-Content (Join-Path $specsDir "S-0001-smoke.md") "# S-0001: Smoke`n" -Encoding UTF8

    $requirements = @{
        requirements = @(
            @{
                id         = "S-0001"
                title      = "Smoke"
                spec_path  = "specs/S-0001-smoke.md"
                status     = "planned"
                depends_on = @()
                updated_at = (Get-Date -Format "yyyy-MM-dd")
            }
        )
    } | ConvertTo-Json -Depth 10
    Set-Content (Join-Path $felixDir "requirements.json") $requirements -Encoding UTF8
    Set-Content (Join-Path $felixDir "state.json") (@{ status = "idle" } | ConvertTo-Json) -Encoding UTF8

    $seedRunDir = Join-Path $runsDir "seed"
    New-Item -ItemType Directory -Path $seedRunDir -Force | Out-Null
    Set-Content (Join-Path $seedRunDir "plan-S-0001.md") "# Plan`n`n## Tasks`n`n- [ ] Smoke task`n" -Encoding UTF8
    Set-Content (Join-Path $projectRoot "AGENTS.md") "# Agent Invocation Smoke Test`n" -Encoding UTF8

    Push-Location $projectRoot
    try {
        git init | Out-Null
        git config user.email "felix-smoke@example.com" | Out-Null
        git config user.name "Felix Smoke" | Out-Null
        git add -A | Out-Null
        git commit -m "init" | Out-Null
    }
    finally {
        Pop-Location
    }

    $agentKey = "ag_copilot_invoke"
    $agentsJson = @{
        agents = @(
            @{
                key                     = $agentKey
                name                    = "copilot-shim"
                provider                = "copilot"
                adapter                 = "copilot"
                executable              = $shimScript
                model                   = "gpt-5.4"
                working_directory       = $agentWorkDirRel
                allow_all               = $true
                no_ask_user             = $true
                max_autopilot_continues = 2
                environment             = @{
                    FELIX_AGENT_TEST = "1"
                }
            }
        )
    } | ConvertTo-Json -Depth 10
    Set-Content (Join-Path $felixDir "agents.json") $agentsJson -Encoding UTF8

    $config = @{
        version      = "0.1.0"
        executor     = @{
            mode               = "local"
            max_iterations     = 1
            default_mode       = "planning"
            commit_on_complete = $false
        }
        agent        = @{
            agent_id = $agentKey
        }
        paths        = @{
            specs  = "specs"
            agents = "AGENTS.md"
            runs   = "runs"
        }
        backpressure = @{
            enabled     = $false
            commands    = @()
            max_retries = 0
        }
        plugins      = @{
            enabled                      = $false
            discovery_path               = ".felix/plugins"
            api_version                  = "v1"
            disabled                     = @()
            state_retention_days         = 7
            circuit_breaker_max_failures = 3
            commands                     = @()
        }
        ui           = @{}
    } | ConvertTo-Json -Depth 10
    Set-Content (Join-Path $felixDir "config.json") $config -Encoding UTF8

    & $felixAgentScript $projectRoot -RequirementId "S-0001" -NoCommit | Out-Null
    $exitCode = $LASTEXITCODE
    Assert-True ($exitCode -eq 0) "felix-agent.ps1 exited with $exitCode"

    $latestRun = Get-ChildItem $runsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Assert-True ($null -ne $latestRun) "No run directory created under $runsDir"

    $outputLog = Join-Path $latestRun.FullName "output.log"
    Assert-True (Test-Path $outputLog) "Missing output.log at $outputLog"

    $output = Get-Content $outputLog -Raw
    Assert-True ($output -match "__AGENT_SHIM__=1") "Agent shim marker not found in output.log"
    Assert-True ($output -match [regex]::Escape("__AGENT_ENV__=1")) "Expected FELIX_AGENT_TEST env var not present in output.log"
    Assert-True ($output -match [regex]::Escape("__AGENT_CWD__=$agentWorkDirAbs")) "Agent did not run in expected working directory"
    Assert-True ($output -match "__AGENT_PROMPT_LEN__=0") "Copilot prompt should not be sent over stdin"
    Assert-True ($output -match "__AGENT_ARGS__=.*--autopilot") "Expected --autopilot argument not present in output.log"
    Assert-True ($output -match "__AGENT_ARGS__=.*--yolo") "Expected --yolo argument not present in output.log"
    Assert-True ($output -match "__AGENT_ARGS__=.*--no-ask-user") "Expected --no-ask-user argument not present in output.log"
    Assert-True ($output -match "__AGENT_ARGS__=.*--max-autopilot-continues 2") "Expected max-autopilot-continues argument not present in output.log"
    Assert-True ($output -match "__AGENT_ARGS__=.*--model gpt-5\.4") "Expected model argument not present in output.log"
    Assert-True ($output -match "__AGENT_ARGS__=.*-p") "Expected -p argument not present in output.log"

    Write-Host "PASS: Felix invoked copilot adapter with argument-mode prompt transport"
}
finally {
    Remove-Item -Recurse -Force $projectRoot -ErrorAction SilentlyContinue
}
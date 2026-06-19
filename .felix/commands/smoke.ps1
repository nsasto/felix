<#
.SYNOPSIS
First-run smoke checks for Felix.

.DESCRIPTION
Runs a disposable usage-tracking smoke project so users can verify that the
selected agent launches and writes runs/<run-id>/usage.json without touching
the current repository's requirements or source files.
#>

function Show-SmokeHelp {
    Write-Host ""
    Write-Host "felix smoke usage [options]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Run a live first-run usage smoke test in a disposable Felix project."
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  --dry-run    Show the resolved agent and smoke project path without running"
    Write-Host "  --json       Emit a machine-readable summary"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  felix smoke usage --dry-run"
    Write-Host "  felix smoke usage"
    Write-Host "  felix smoke usage --json"
    Write-Host ""
}

function Get-SmokeArgValue {
    param([string[]]$CommandArgs, [string]$Name)
    for ($i = 0; $i -lt $CommandArgs.Count - 1; $i++) {
        if ($CommandArgs[$i] -ieq $Name) { return $CommandArgs[$i + 1] }
    }
    return $null
}

function Write-SmokeJson {
    param($Object)
    $Object | ConvertTo-Json -Depth 8
}

function Get-SmokeActiveAgent {
    param([string]$ProjectRoot)

    $configPath = Join-Path $ProjectRoot ".felix\config.json"
    $agentsPath = Join-Path $ProjectRoot ".felix\agents.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "No .felix/config.json found. Run 'felix setup' first."
    }
    if (-not (Test-Path -LiteralPath $agentsPath)) {
        throw "No .felix/agents.json found. Run 'felix agent setup' first."
    }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agentsDoc = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agents = @($agentsDoc.agents)
    if ($agents.Count -eq 0) {
        throw "No agent profiles are configured. Run 'felix agent setup' first."
    }

    $agentId = if ($config.agent -and $config.agent.agent_id) { [string]$config.agent.agent_id } else { $null }
    $agent = $null
    if ($agentId) {
        $agent = $agents | Where-Object { $_.key -eq $agentId } | Select-Object -First 1
    }
    elseif ($agents.Count -eq 1) {
        $agent = $agents[0]
        $agentId = [string]$agent.key
    }

    if (-not $agent) {
        throw "No active agent selected. Run 'felix agent use <id|name>' first."
    }

    return [ordered]@{
        id         = $agentId
        name       = [string]$agent.name
        provider   = [string]$agent.provider
        adapter    = if ($agent.adapter) { [string]$agent.adapter } else { [string]$agent.provider }
        model      = if ($agent.model) { [string]$agent.model } else { "default" }
        executable = [string]$agent.executable
        agent      = $agent
        agentsPath = $agentsPath
    }
}

function New-UsageSmokeProject {
    param(
        [string]$SourceProjectRoot,
        [string]$SmokeProjectRoot,
        $ActiveAgent
    )

    $felixDir = Join-Path $SmokeProjectRoot ".felix"
    $specsDir = Join-Path $SmokeProjectRoot "specs"
    $runsDir = Join-Path $SmokeProjectRoot "runs"
    New-Item -ItemType Directory -Path $felixDir, $specsDir, $runsDir -Force | Out-Null

    Copy-Item -LiteralPath $ActiveAgent.agentsPath -Destination (Join-Path $felixDir "agents.json") -Force

    $config = [ordered]@{
        version      = "0.1.0"
        requirements = [ordered]@{ prefix = "S" }
        paths        = [ordered]@{
            specs   = "specs"
            agents  = "AGENTS.md"
            runs    = "runs"
            context = @("AGENTS.md")
        }
        agent        = [ordered]@{ agent_id = $ActiveAgent.id }
        executor     = [ordered]@{
            mode               = "local"
            max_iterations     = 1
            default_mode       = "planning"
            commit_on_complete = $false
        }
        backpressure = [ordered]@{
            enabled     = $false
            commands    = @()
            max_retries = 1
        }
        sync         = [ordered]@{
            enabled  = $false
            provider = "http"
            base_url = "https://api.runfelix.io"
            api_key  = $null
        }
        explore      = [ordered]@{
            enabled            = $false
            auto_enable_when   = [ordered]@{ min_tracked_files = 999999999 }
            skip_on_iteration_gt = 1
            agent_override     = $null
            max_tokens         = 8000
        }
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $felixDir "config.json") -Encoding UTF8
    "{}" | Set-Content -LiteralPath (Join-Path $felixDir "state.json") -Encoding UTF8

    $specRelPath = "specs/S-0000-usage-smoke.md"
    $requirements = [ordered]@{
        requirements = @(
            [ordered]@{
                id         = "S-0000"
                title      = "Usage tracking smoke test"
                spec_path  = $specRelPath
                status     = "planned"
                updated_at = (Get-Date -Format "yyyy-MM-dd")
            }
        )
    }
    $requirements | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $felixDir "requirements.json") -Encoding UTF8

    @"
# Agents - Smoke Test Project

This disposable Felix project verifies first-run model and token usage capture.

## Rules

- Do not edit the source project at: $SourceProjectRoot
- Do not make product changes in this smoke project
- Produce the normal Felix planning artifact and finish
"@ | Set-Content -LiteralPath (Join-Path $SmokeProjectRoot "AGENTS.md") -Encoding UTF8

    @"
---
id: S-0000
title: Usage tracking smoke test
status: planned
---

# Usage tracking smoke test

## Objective

Verify that Felix can launch the configured agent and write a usage artifact.

## Scope

This is a disposable smoke check. Do not make product changes. Write the normal
planning artifact for this requirement and then finish.

## Validation Criteria

- A run directory is created under runs
- The run directory contains usage.json
- Usage output includes an effective model and provider token data when the provider reports it
"@ | Set-Content -LiteralPath (Join-Path $SmokeProjectRoot $specRelPath) -Encoding UTF8

    return $SmokeProjectRoot
}

function Invoke-UsageSmoke {
    param(
        [string[]]$CommandArgs = @(),
        [string]$ProjectRoot,
        [string]$FelixEngineRoot
    )

    $dryRun = $CommandArgs -icontains "--dry-run"
    $json = $CommandArgs -icontains "--json"

    $unknown = @($CommandArgs | Where-Object { $_.StartsWith("-") -and $_ -notin @("--dry-run", "--json") })
    if ($unknown.Count -gt 0) {
        throw "Unknown option(s): $($unknown -join ', ')"
    }

    $active = Get-SmokeActiveAgent -ProjectRoot $ProjectRoot
    $runsRoot = Join-Path $ProjectRoot "runs"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $smokeProject = Join-Path $runsRoot "_usage-smoke-$stamp"

    $proxyWarnings = @()
    foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "GIT_HTTP_PROXY", "GIT_HTTPS_PROXY")) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        if ($value -and $value -match "127\.0\.0\.1:9") {
            $proxyWarnings += "$name=$value"
        }
    }

    if ($dryRun) {
        $summary = [ordered]@{
            _v            = 1
            kind          = "usage-smoke"
            dry_run       = $true
            project_path  = $smokeProject
            agent         = [ordered]@{
                id       = $active.id
                name     = $active.name
                provider = $active.provider
                adapter  = $active.adapter
                model    = $active.model
            }
            warnings      = $proxyWarnings
            next_command  = "felix smoke usage"
        }
        if ($json) { Write-SmokeJson $summary }
        $script:FelixSmokeExitCode = 0
        if ($json) { return }

        Write-Host ""
        Write-Host "Usage smoke dry run" -ForegroundColor Cyan
        Write-Host "  Agent: $($active.name) [$($active.id)] provider=$($active.provider) model=$($active.model)" -ForegroundColor Gray
        Write-Host "  Project: $smokeProject" -ForegroundColor Gray
        if ($proxyWarnings.Count -gt 0) {
            Write-Host "  Warning: proxy variables may block live agent network access:" -ForegroundColor Yellow
            foreach ($warning in $proxyWarnings) { Write-Host "    $warning" -ForegroundColor Yellow }
        }
        Write-Host "  Run: felix smoke usage" -ForegroundColor Green
        Write-Host ""
        return
    }

    New-UsageSmokeProject -SourceProjectRoot $ProjectRoot -SmokeProjectRoot $smokeProject -ActiveAgent $active | Out-Null

    if (-not $json) {
        Write-Host ""
        Write-Host "Usage smoke test" -ForegroundColor Cyan
        Write-Host "  Agent: $($active.name) [$($active.id)] provider=$($active.provider) model=$($active.model)" -ForegroundColor Gray
        Write-Host "  Project: $smokeProject" -ForegroundColor Gray
        if ($proxyWarnings.Count -gt 0) {
            Write-Host "  Warning: proxy variables may block live agent network access:" -ForegroundColor Yellow
            foreach ($warning in $proxyWarnings) { Write-Host "    $warning" -ForegroundColor Yellow }
        }
        Write-Host ""
    }

    $cliPath = Join-Path $FelixEngineRoot "felix-cli.ps1"
    if ($json) {
        $agentOutput = & $cliPath -ProjectPath $smokeProject -RequirementId "S-0000" -Format "plain" -NoCommit -NoExplore -NoStats *>&1 | Out-String
        $runExit = $LASTEXITCODE
    }
    else {
        & $cliPath -ProjectPath $smokeProject -RequirementId "S-0000" -Format "plain" -NoCommit -NoExplore -NoStats
        $runExit = $LASTEXITCODE
    }

    . (Join-Path $FelixEngineRoot "commands\query.ps1")
    $usageJson = Invoke-Query -CmdArgs @("usage", "--json") -ProjectPath $smokeProject | Out-String
    $usage = $null
    try { $usage = $usageJson | ConvertFrom-Json } catch { }

    $firstUsage = if ($usage -and $usage.usage -and @($usage.usage).Count -gt 0) { @($usage.usage)[0] } else { $null }
    $usageAvailable = $false
    $effectiveModel = $null
    $runId = $null
    if ($firstUsage) {
        $usageAvailable = ($firstUsage.usage_available -eq $true)
        $effectiveModel = if ($firstUsage.effective_model) { [string]$firstUsage.effective_model } else { $null }
        $runId = if ($firstUsage.run_id) { [string]$firstUsage.run_id } else { $null }
    }

    $passed = ($runExit -eq 0 -and $usage -and $usage.total -gt 0 -and $usageAvailable -and -not [string]::IsNullOrWhiteSpace($effectiveModel))
    $summary = [ordered]@{
        _v              = 1
        kind            = "usage-smoke"
        passed          = $passed
        exit_code       = $runExit
        project_path    = $smokeProject
        run_id          = $runId
        usage_available = $usageAvailable
        effective_model = $effectiveModel
        observed_tokens = if ($usage -and $usage.totals) { $usage.totals.observed_tokens } else { $null }
        total_tokens    = if ($usage -and $usage.totals) { $usage.totals.total_tokens } else { $null }
        query           = "cd `"$smokeProject`"; felix query usage --run-id $runId --json"
        warnings        = $proxyWarnings
        output_tail     = if ($json -and $agentOutput) { @(($agentOutput -split "`r?`n") | Where-Object { $_ } | Select-Object -Last 8) } else { @() }
    }

    if ($json) {
        Write-SmokeJson $summary
    }
    else {
        Write-Host ""
        if ($passed) {
            Write-Host "Usage smoke passed" -ForegroundColor Green
        }
        else {
            Write-Host "Usage smoke failed" -ForegroundColor Red
        }
        Write-Host "  Run ID: $runId" -ForegroundColor Gray
        Write-Host "  Usage available: $usageAvailable" -ForegroundColor Gray
        Write-Host "  Effective model: $effectiveModel" -ForegroundColor Gray
        Write-Host "  Observed tokens: $($summary.observed_tokens)" -ForegroundColor Gray
        Write-Host "  Inspect: cd `"$smokeProject`"; felix query usage --run-id $runId --json" -ForegroundColor Gray
        Write-Host "  Smoke project: $smokeProject" -ForegroundColor DarkGray
        Write-Host ""
    }

    if ($passed) {
        $script:FelixSmokeExitCode = 0
    }
    else {
        $script:FelixSmokeExitCode = 1
    }
    return
}

function Invoke-Smoke {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [Alias("Args")]
        [string[]]$CommandArgs = @(),
        [string[]]$CmdArgs = $null,
        [string]$RepoRoot = "",
        [string]$FelixRoot = ""
    )

    [string[]]$resolvedArgs = if ($null -ne $CmdArgs) { @($CmdArgs) } else { @($CommandArgs) }
    $projectRoot = if ($RepoRoot) { $RepoRoot } elseif ($env:FELIX_PROJECT_ROOT) { $env:FELIX_PROJECT_ROOT } else { (Get-Location).Path }
    $engineRoot = if ($FelixRoot) { $FelixRoot } elseif ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { Split-Path -Parent $PSScriptRoot }

    if ($resolvedArgs.Count -eq 0 -or $resolvedArgs[0] -in @("-h", "--help", "help")) {
        Show-SmokeHelp
        return
    }

    $subcommand = ([string]$resolvedArgs[0]).ToLowerInvariant()
    $rest = if ($resolvedArgs.Count -gt 1) { $resolvedArgs[1..($resolvedArgs.Count - 1)] } else { @() }

    try {
        switch ($subcommand) {
            "usage" {
                $script:FelixSmokeExitCode = 0
                Invoke-UsageSmoke -CommandArgs $rest -ProjectRoot $projectRoot -FelixEngineRoot $engineRoot
                exit $script:FelixSmokeExitCode
            }
            default {
                Write-Host "Unknown smoke command: $subcommand" -ForegroundColor Red
                Show-SmokeHelp
                exit 1
            }
        }
    }
    catch {
        $json = $resolvedArgs -icontains "--json"
        if ($json) {
            [ordered]@{ _v = 1; kind = "usage-smoke"; passed = $false; error = $_.Exception.Message } | ConvertTo-Json -Depth 4
        }
        else {
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        exit 1
    }
}

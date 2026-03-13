#!/usr/bin/env pwsh
<#
.SYNOPSIS
Felix CLI dispatcher - unified command interface

.DESCRIPTION
Routes commands to appropriate Felix scripts with consistent interface.

.PARAMETER Command
The command to execute: run, loop, status, list, validate, version, help

.PARAMETER Arguments
Command-specific arguments and global flags

.EXAMPLE
.felix\felix.ps1 run S-0001

.EXAMPLE
.felix\felix.ps1 loop --max-iterations 5

.EXAMPLE
.felix\felix.ps1 status S-0001 --format json

.EXAMPLE
.felix\felix.ps1 list --status planned

.EXAMPLE
.felix\felix.ps1 validate S-0001
#>

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Command = "help",

    [Parameter(Mandatory = $false, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"

# ── Root path resolution ─────────────────────────────────────────────
#
# When C# runner calls us it sets:
#   FELIX_INSTALL_DIR  → directory containing felix.ps1 (engine: core/, commands/, plugins/)
#   FELIX_PROJECT_ROOT → user's CWD (the project being worked on)
#
# When called directly (dev / user with .felix in PATH):
#   Neither env var is set, so both fall back to $PSScriptRoot-relative paths — unchanged.

# $FelixRoot → where engine scripts live (core/, commands/, plugins/)
$FelixRoot = if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { $PSScriptRoot }

function Resolve-RepoRoot {
    param([string]$StartDir)

    $resolved = $null
    try {
        $resolved = (Resolve-Path -LiteralPath $StartDir -ErrorAction Stop).Path
    }
    catch {
        $resolved = $StartDir
    }

    $dir = $resolved
    $gitRoot = $null
    while ($dir -and (Test-Path -LiteralPath $dir)) {
        if (Test-Path -LiteralPath (Join-Path $dir ".felix")) {
            return $dir
        }
        if (-not $gitRoot -and (Test-Path -LiteralPath (Join-Path $dir ".git"))) {
            $gitRoot = $dir
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) {
            break
        }
        $dir = $parent
    }

    if ($gitRoot) { return $gitRoot }
    return $resolved
}

# $RepoRoot → the project directory felix is operating on
$RepoRoot = if ($env:FELIX_PROJECT_ROOT) {
    $env:FELIX_PROJECT_ROOT
}
else {
    Resolve-RepoRoot -StartDir (Get-Location).Path
}

# ── .env loader ──────────────────────────────────────────────────────
# Reads KEY=VALUE pairs from $RepoRoot/.env (and project root .env).
# Variables already set in the environment are NOT overwritten.
function Load-DotEnv {
    param([string]$EnvFile)
    if (-not (Test-Path $EnvFile)) { return }
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -le 0) { return }
        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        # Strip surrounding quotes
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        # Only set if not already present
        if (-not [System.Environment]::GetEnvironmentVariable($key)) {
            [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
        }
    }
}

Load-DotEnv -EnvFile (Join-Path $RepoRoot ".env")
Load-DotEnv -EnvFile (Join-Path $RepoRoot ".felix\.env")

# Parse global flags
$Format = "rich"
$VerboseMode = $false
$global:FelixOutputFormat = "rich"  # updated after flag parsing below
$Quiet = $false
$NoStats = $false

$remainingArgs = @()
$i = 0
while ($i -lt $Arguments.Count) {
    switch ($Arguments[$i]) {
        "--format" {
            $i++
            $Format = $Arguments[$i]
        }
        "--verbose" {
            $VerboseMode = $true
        }
        "--quiet" {
            $Quiet = $true
        }
        "--no-stats" {
            $NoStats = $true
        }
        default {
            $remainingArgs += $Arguments[$i]
        }
    }
    $i++
}

$global:FelixOutputFormat = $Format

# -- Command routing -------------------------------------------------------
# Each command file is dot-sourced on demand into this script's scope.
# Functions defined there inherit $RepoRoot, $FelixRoot, $Format, $VerboseMode, $NoStats.

switch ($Command) {
    "run" {
        . "$FelixRoot\commands\run.ps1"
        Invoke-Run -Args $remainingArgs
    }
    "run-next" {
        . "$FelixRoot\commands\run-next.ps1"
        Invoke-RunNext -Args $remainingArgs
    }
    "loop" {
        . "$FelixRoot\commands\loop.ps1"
        Invoke-Loop -Args $remainingArgs
    }
    "status" {
        . "$FelixRoot\commands\status.ps1"
        Invoke-Status -Args $remainingArgs
    }
    "list" {
        . "$FelixRoot\commands\list.ps1"
        Invoke-List -Args $remainingArgs
    }
    "validate" {
        . "$FelixRoot\commands\validate.ps1"
        Invoke-Validate -Args $remainingArgs
    }
    "deps" {
        . "$FelixRoot\commands\deps.ps1"
        Invoke-Deps -Args $remainingArgs
    }
    "spec" {
        . "$FelixRoot\commands\spec.ps1"
        & { Invoke-SpecCreate @remainingArgs }
    }
    "context" {
        . "$FelixRoot\commands\context.ps1"
        Invoke-Context -Args $remainingArgs
    }
    "tui" {
        . "$FelixRoot\commands\tui.ps1"
        Invoke-Tui
    }
    "agent" {
        . "$FelixRoot\commands\agent.ps1"
        Invoke-Agent -AgentArgs $remainingArgs
    }
    "procs" {
        . "$FelixRoot\commands\procs.ps1"
        Invoke-ProcessList -Arguments $remainingArgs
    }
    "setup" {
        . "$FelixRoot\commands\setup.ps1"
        Invoke-Setup -Args $remainingArgs
    }
    "version" {
        . "$FelixRoot\commands\version.ps1"
        Show-Version
    }
    "help" {
        . "$FelixRoot\commands\help.ps1"
        $subCmd = if ($remainingArgs.Count -gt 0) { $remainingArgs[0] } else { $null }
        Show-Help -SubCommand $subCmd
    }
    default {
        # Generic passthrough: look for commands/<verb>.ps1 and invoke it
        $commandFile = "$FelixRoot\commands\$Command.ps1"
        if (Test-Path $commandFile) {
            . $commandFile
            # Convention: command file exposes Invoke-<PascalCase> (e.g. Invoke-MyCommand)
            $fnName = "Invoke-" + ((($Command -split '-') | ForEach-Object {
                        $_.Substring(0, 1).ToUpper() + $_.Substring(1)
                    }) -join '')
            if (Get-Command $fnName -ErrorAction SilentlyContinue) {
                & $fnName -Args $remainingArgs
            }
            else {
                Write-Host "Error: '$commandFile' does not expose '$fnName'." -ForegroundColor Red
                exit 1
            }
        }
        else {
            . "$FelixRoot\commands\help.ps1"
            Write-Host "Unknown command: $Command" -ForegroundColor Red
            Show-Help
            exit 1
        }
    }
}

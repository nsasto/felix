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
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("run", "loop", "status", "list", "validate", "version", "help")]
    [string]$Command,

    [Parameter(Mandatory = $false, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"

# Determine repository root (parent of .felix folder)
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Parse global flags
$Format = "rich"
$Verbose = $false
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
            $Verbose = $true
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

function Invoke-Run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix run <requirement-id> [--format <json|plain|rich>]"
        exit 1
    }

    $requirementId = $Args[0]

    # Build CLI args
    $cliArgs = @(
        $RepoRoot,
        "-RequirementId", $requirementId,
        "-Format", $Format
    )
    
    if ($NoStats) {
        $cliArgs += "-NoStats"
    }

    # Execute felix-cli.ps1 which spawns agent internally
    & "$PSScriptRoot\felix-cli.ps1" @cliArgs
    exit $LASTEXITCODE
}

function Invoke-Loop {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # Parse max-iterations flag
    $maxIterations = 0
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--max-iterations") {
            $maxIterations = [int]$Args[$i + 1]
            break
        }
    }

    Write-Host "Felix Loop Mode" -ForegroundColor Cyan
    Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
    if ($maxIterations -gt 0) {
        Write-Host "Max Iterations: $maxIterations" -ForegroundColor Gray
    }
    Write-Host ""

    # Start loop process
    $loopArgs = @($RepoRoot)
    if ($maxIterations -gt 0) {
        $loopArgs += @("-MaxIterations", $maxIterations)
    }

    & "$PSScriptRoot\felix-loop.ps1" @loopArgs
    exit $LASTEXITCODE
}

function Invoke-Status {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $requirementId = if ($Args -and $Args.Count -gt 0) { $Args[0] } else { $null }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath -Raw | ConvertFrom-Json

    if ($requirementId) {
        # Show specific requirement
        $req = $requirements.requirements | Where-Object { $_.id -eq $requirementId }
        if (-not $req) {
            Write-Error "Requirement not found: $requirementId"
            exit 1
        }

        if ($Format -eq "json") {
            $req | ConvertTo-Json -Depth 10
        } 
        else {
            Write-Host ""
            Write-Host "Requirement: $($req.id)" -ForegroundColor Cyan
            Write-Host "Title: $($req.title)"
            
            $statusColor = switch ($req.status) {
                "done" { "Green" }
                "complete" { "Green" }
                "in-progress" { "Yellow" }
                "planned" { "Cyan" }
                "blocked" { "Red" }
                default { "White" }
            }
            Write-Host "Status: $($req.status)" -ForegroundColor $statusColor
            Write-Host "Priority: $($req.priority)"
            
            if ($req.dependencies -and $req.dependencies.Count -gt 0) {
                Write-Host "Dependencies: $($req.dependencies -join ', ')"
            }
            if ($req.spec_file) {
                Write-Host "Spec: $($req.spec_file)"
            }
            if ($req.last_run_id) {
                Write-Host "Last Run: $($req.last_run_id)"
            }
            Write-Host ""
        }
    } 
    else {
        # Show summary
        if ($Format -eq "json") {
            $requirements.requirements | ConvertTo-Json -Depth 10
        } 
        else {
            Write-Host ""
            Write-Host "Felix Requirements Status" -ForegroundColor Cyan
            Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
            Write-Host ""
            
            $byStatus = $requirements.requirements | Group-Object status
            foreach ($group in $byStatus) {
                $color = switch ($group.Name) {
                    "done" { "Green" }
                    "complete" { "Green" }
                    "in-progress" { "Yellow" }
                    "in_progress" { "Yellow" }
                    "planned" { "Cyan" }
                    "blocked" { "Red" }
                    default { "White" }
                }
                Write-Host "$($group.Name): $($group.Count)" -ForegroundColor $color
            }
            Write-Host ""
        }
    }
}

function Invoke-List {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # Parse status filter
    $statusFilter = $null
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--status") {
            $statusFilter = $Args[$i + 1]
            break
        }
    }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath -Raw | ConvertFrom-Json

    # Filter by status
    $filtered = if ($statusFilter) {
        $requirements.requirements | Where-Object { $_.status -eq $statusFilter }
    } 
    else {
        $requirements.requirements
    }

    if ($Format -eq "json") {
        $filtered | ConvertTo-Json -Depth 10
    } 
    else {
        Write-Host ""
        Write-Host "Requirements:" -ForegroundColor Cyan
        if ($statusFilter) {
            Write-Host "Filter: status=$statusFilter" -ForegroundColor Gray
        }
        Write-Host ""
        
        foreach ($req in $filtered) {
            $color = switch ($req.status) {
                "done" { "Green" }
                "in-progress" { "Yellow" }
                "planned" { "Cyan" }
                "blocked" { "Red" }
                default { "White" }
            }
            Write-Host "  $($req.id): $($req.title)" -ForegroundColor $color -NoNewline
            Write-Host " [$($req.status)]" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

function Invoke-Validate {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix validate <requirement-id>"
        exit 1
    }

    $requirementId = $Args[0]

    Write-Host "Validating requirement: $requirementId" -ForegroundColor Cyan
    Write-Host ""

    # Call validation script
    $validatorScript = "$RepoRoot\scripts\validate-requirement.py"
    if (-not (Test-Path $validatorScript)) {
        Write-Error "Validator script not found: $validatorScript"
        exit 1
    }

    # Run Python validator
    $pythonCmd = "python"
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $pythonCmd = "py -3"
    }

    $result = & $pythonCmd $validatorScript $requirementId
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "✅ Validation PASSED" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Validation FAILED" -ForegroundColor Red
    }

    exit $exitCode
}

function Show-Version {
    Write-Host ""
    Write-Host "Felix CLI v0.3.0-alpha (Phase 1: PowerShell)" -ForegroundColor Cyan
    Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
    
    # Try to get git info
    try {
        $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $gitCommit = git rev-parse --short HEAD 2>$null
        if ($gitBranch) {
            Write-Host "Branch: $gitBranch" -ForegroundColor Gray
            Write-Host "Commit: $gitCommit" -ForegroundColor Gray
        }
    }
    catch {
        # Git not available or not a git repo
    }
    
    Write-Host ""
}

function Show-Help {
    param([string]$SubCommand)

    if ($SubCommand) {
        switch ($SubCommand) {
            "run" {
                Write-Host ""
                Write-Host "felix run <requirement-id> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Execute a single requirement to completion."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host "  --no-stats                   Suppress statistics summary"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix run S-0001"
                Write-Host "  felix run S-0001 --format json"
                Write-Host "  felix run S-0001 --format plain --no-stats"
                Write-Host ""
            }
            "loop" {
                Write-Host ""
                Write-Host "felix loop [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run agent in continuous loop mode (processes all planned requirements)."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --max-iterations <n>   Maximum iterations to run"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix loop"
                Write-Host "  felix loop --max-iterations 10"
                Write-Host ""
            }
            "status" {
                Write-Host ""
                Write-Host "felix status [requirement-id] [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Show current status of requirements."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix status"
                Write-Host "  felix status S-0001"
                Write-Host "  felix status --format json"
                Write-Host ""
            }
            "list" {
                Write-Host ""
                Write-Host "felix list [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "List requirements with optional filtering."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --status <status>            Filter by status (planned, in-progress, done, blocked)"
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix list"
                Write-Host "  felix list --status planned"
                Write-Host "  felix list --status done --format json"
                Write-Host ""
            }
            "validate" {
                Write-Host ""
                Write-Host "felix validate <requirement-id>" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run validation checks for a requirement."
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix validate S-0001"
                Write-Host ""
            }
            default {
                Write-Host "Unknown command: $SubCommand" -ForegroundColor Red
                Show-Help
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "Felix CLI - Development Workflow Automation" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  felix <command> [arguments] [options]"
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  run <req-id>        Execute a single requirement"
        Write-Host "  loop                Run agent in continuous loop mode"
        Write-Host "  status [req-id]     Show requirement status"
        Write-Host "  list                List all requirements"
        Write-Host "  validate <req-id>   Run validation checks"
        Write-Host "  version             Show version information"
        Write-Host "  help [command]      Show help for a command"
        Write-Host ""
        Write-Host "Global Options:" -ForegroundColor Yellow
        Write-Host "  --format <mode>     Output format: json, plain, rich (default: rich)"
        Write-Host "  --verbose           Enable verbose logging"
        Write-Host "  --quiet             Suppress non-essential output"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix run S-0001"
        Write-Host "  felix loop --max-iterations 5"
        Write-Host "  felix status S-0001 --format json"
        Write-Host "  felix list --status planned"
        Write-Host "  felix validate S-0001"
        Write-Host "  felix help run"
        Write-Host ""
    }
}

# Route to appropriate command handler
switch ($Command) {
    "run" {
        Invoke-Run @remainingArgs
    }
    "loop" {
        Invoke-Loop @remainingArgs
    }
    "status" {
        Invoke-Status @remainingArgs
    }
    "list" {
        Invoke-List @remainingArgs
    }
    "validate" {
        Invoke-Validate @remainingArgs
    }
    "version" {
        Show-Version
    }
    "help" {
        $subCmd = if ($remainingArgs.Count -gt 0) { $remainingArgs[0] } else { $null }
        Show-Help -SubCommand $subCmd
    }
    default {
        Write-Error "Unknown command: $Command"
        Show-Help
        exit 1
    }
}

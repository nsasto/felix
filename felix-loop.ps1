#!/usr/bin/env pwsh
# Felix Loop - Autonomous Multi-Requirement Executor
# Usage: .\felix-loop.ps1 <ProjectPath> [-MaxRequirements <N>]
#
# Continuously selects and processes planned/in_progress requirements
# until none remain or max requirements limit is reached.

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxRequirements = 999
)

$ErrorActionPreference = "Stop"

# Resolve paths
$ProjectPath = Resolve-Path $ProjectPath
$RequirementsFile = Join-Path $ProjectPath "felix\requirements.json"
$AgentScript = Join-Path $PSScriptRoot "felix-agent.ps1"

Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Felix Loop - Autonomous Multi-Requirement Executor" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "Project: " -NoNewline
Write-Host $ProjectPath -ForegroundColor Green
Write-Host "Max requirements: " -NoNewline
Write-Host $MaxRequirements -ForegroundColor Green
Write-Host ""

function Select-NextRequirement {
    param([string]$RequirementsFilePath)
    
    if (-not (Test-Path $RequirementsFilePath)) {
        Write-Host "Requirements file not found: $RequirementsFilePath" -ForegroundColor Red
        return $null
    }
    
    $requirements = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
    
    # Find first in_progress, then first planned
    $req = $requirements.requirements | Where-Object { $_.status -eq "in_progress" } | Select-Object -First 1
    if (-not $req) {
        $req = $requirements.requirements | Where-Object { $_.status -eq "planned" } | Select-Object -First 1
    }
    
    return $req
}

$requirementsProcessed = 0

while ($requirementsProcessed -lt $MaxRequirements) {
    # Select next requirement
    $nextReq = Select-NextRequirement -RequirementsFilePath $RequirementsFile
    
    if (-not $nextReq) {
        Write-Host ""
        Write-Host "=============================================================" -ForegroundColor Green
        Write-Host "  No more requirements to process - all done!" -ForegroundColor Green
        Write-Host "=============================================================" -ForegroundColor Green
        exit 0
    }
    
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "  Processing: $($nextReq.id) - $($nextReq.title)" -ForegroundColor Cyan
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Execute felix-agent for this specific requirement
    & $AgentScript $ProjectPath -RequirementId $nextReq.id
    $exitCode = $LASTEXITCODE
    
    Write-Host ""
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray
    
    switch ($exitCode) {
        0 {
            # Success - requirement completed
            Write-Host "✅ $($nextReq.id) completed successfully" -ForegroundColor Green
            $requirementsProcessed++
        }
        2 {
            # Blocked due to backpressure failures
            Write-Host "⚠️  $($nextReq.id) blocked (backpressure failures)" -ForegroundColor Yellow
            Write-Host "Moving to next requirement..." -ForegroundColor Yellow
            $requirementsProcessed++
        }
        3 {
            # Blocked due to validation failures
            Write-Host "⚠️  $($nextReq.id) blocked (validation failures)" -ForegroundColor Yellow
            Write-Host "Moving to next requirement..." -ForegroundColor Yellow
            $requirementsProcessed++
        }
        1 {
            # Error - stop loop
            Write-Host "❌ $($nextReq.id) encountered an error (exit code 1)" -ForegroundColor Red
            Write-Host "Stopping execution" -ForegroundColor Red
            exit 1
        }
        default {
            # Unknown exit code - stop loop
            Write-Host "❌ $($nextReq.id) returned unexpected exit code: $exitCode" -ForegroundColor Red
            Write-Host "Stopping execution" -ForegroundColor Red
            exit $exitCode
        }
    }
    
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Requirements processed: $requirementsProcessed / $MaxRequirements" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "  Max requirements limit reached ($MaxRequirements)" -ForegroundColor Yellow
Write-Host "=============================================================" -ForegroundColor Yellow
exit 0

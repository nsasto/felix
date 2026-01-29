#!/usr/bin/env pwsh
# Felix Loop - Autonomous Multi-Requirement Executor
# Usage: .\felix-loop.ps1 <ProjectPath> [-MaxRequirements <N>] [-NoCommit]
#
# Continuously selects and processes planned/in_progress requirements
# until none remain or max requirements limit is reached.
#
# Use -NoCommit flag for testing without git commits

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxRequirements = 999,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoCommit   # Use this flag for testing to prevent git commits
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
# Create process-specific lock file to track active loops
$lockDir = Join-Path $ProjectPath "felix\.locks"
if (-not (Test-Path $lockDir)) {
    New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
}

$lockFile = Join-Path $lockDir "loop-$PID.lock"
$lockData = @{
    pid     = $PID
    started = Get-Date -Format "o"
    project = $ProjectPath
} | ConvertTo-Json

Set-Content -Path $lockFile -Value $lockData
Write-Host "[LOCK] Created loop lock: $lockFile" -ForegroundColor Cyan

# Cleanup function
function Remove-LoopLock {
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        Write-Host "[LOCK] Removed loop lock" -ForegroundColor Cyan
    }
}

# Register cleanup on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Remove-LoopLock } | Out-Null
function Select-NextRequirement {
    param([string]$RequirementsFilePath)
    
    if (-not (Test-Path $RequirementsFilePath)) {
        Write-Host "Requirements file not found: $RequirementsFilePath" -ForegroundColor Red
        return $null
    }
    
    try {
        $requirements = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "ERROR: Failed to parse requirements.json: $_" -ForegroundColor Red
        Write-Host "File may be corrupted or contain invalid JSON" -ForegroundColor Red
        return $null
    }
    
    # Find first in_progress, then first planned (explicitly exclude complete, blocked, done)
    $req = $requirements.requirements | Where-Object { 
        $_.status -eq "in_progress" 
    } | Select-Object -First 1
    
    if (-not $req) {
        $req = $requirements.requirements | Where-Object { 
            $_.status -eq "planned" 
        } | Select-Object -First 1
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
    
    # Validate parameters before calling felix-agent
    if (-not $nextReq.id) {
        Write-Host "ERROR: nextReq.id is null or empty!" -ForegroundColor Red
        Write-Host "nextReq object: $($nextReq | ConvertTo-Json -Depth 2)" -ForegroundColor Yellow
        continue
    }
    
    # Double-check requirement status immediately before processing (catch external changes)
    try {
        $freshReqs = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        $freshReq = $freshReqs.requirements | Where-Object { $_.id -eq $nextReq.id } | Select-Object -First 1
        
        if (-not $freshReq) {
            Write-Host "â ï¸  Warning: Requirement $($nextReq.id) no longer exists in requirements.json" -ForegroundColor Yellow
            Write-Host "Skipping to next requirement..." -ForegroundColor Yellow
            continue
        }
        
        if ($freshReq.status -notin @("planned", "in_progress")) {
            Write-Host "â ï¸  Warning: Requirement $($nextReq.id) status changed to '$($freshReq.status)'" -ForegroundColor Yellow
            Write-Host "Skipping to next requirement..." -ForegroundColor Yellow
            continue
        }
    }
    catch {
        Write-Host "â ï¸  Warning: Failed to verify requirement status: $_" -ForegroundColor Yellow
        Write-Host "Skipping to next requirement..." -ForegroundColor Yellow
        continue
    }
    
    # Execute felix-agent for this specific requirement
    Write-Host "[DEBUG] Calling felix-agent with ProjectPath='$ProjectPath' RequirementId='$($nextReq.id)'" -ForegroundColor DarkGray
    
    if ($NoCommit) {
        & $AgentScript $ProjectPath -RequirementId $nextReq.id -NoCommit
    }
    else {
        & $AgentScript $ProjectPath -RequirementId $nextReq.id
    }
    $exitCode = $LASTEXITCODE
    
    Write-Host ""
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray
    
    switch ($exitCode) {
        0 {
            # Success - requirement completed
            Write-Host "? $($nextReq.id) completed successfully" -ForegroundColor Green
            
            # Brief pause to ensure requirements.json is updated
            Start-Sleep -Milliseconds 500
            
            # Verify the requirement was actually marked complete
            $updatedReqs = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
            $completedReq = $updatedReqs.requirements | Where-Object { $_.id -eq $nextReq.id }
            
            if ($completedReq -and ($completedReq.status -eq "complete" -or $completedReq.status -eq "done")) {
                Write-Host "âœ… Status verified: $($nextReq.id) marked as $($completedReq.status)" -ForegroundColor Green
            }
            elseif ($nextReq.status -in @("complete", "done")) {
                Write-Host "âœ… Requirement was already complete before processing" -ForegroundColor Cyan
            }
            else {
                Write-Host "â ï¸  Warning: $($nextReq.id) status is '$($completedReq.status)' (expected 'complete')" -ForegroundColor Yellow
            }
            
            $requirementsProcessed++
        }
        2 {
            # Blocked due to backpressure failures
            Write-Host "??  $($nextReq.id) blocked (backpressure failures)" -ForegroundColor Yellow
            Write-Host "Moving to next requirement..." -ForegroundColor Yellow
            $requirementsProcessed++
        }
        3 {
            # Blocked due to validation failures
            Write-Host "??  $($nextReq.id) blocked (validation failures)" -ForegroundColor Yellow
            Write-Host "Moving to next requirement..." -ForegroundColor Yellow
            $requirementsProcessed++
        }
        1 {
            # Error - stop loop
            Write-Host "? $($nextReq.id) encountered an error (exit code 1)" -ForegroundColor Red
            Write-Host "Stopping execution" -ForegroundColor Red
            exit 1
        }
        default {
            # Unknown exit code - stop loop
            Write-Host "? $($nextReq.id) returned unexpected exit code: $exitCode" -ForegroundColor Red
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

# Cleanup
Remove-LoopLock
exit 0

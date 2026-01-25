#!/usr/bin/env pwsh
# Felix Agent - Ralph Loop Executor (PowerShell)
# Usage: .\felix-agent.ps1 <ProjectPath>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

$ErrorActionPreference = "Stop"

# Resolve project path
$ProjectPath = Resolve-Path $ProjectPath
Write-Host "Felix Agent starting for: $ProjectPath"

# Key paths
$SpecsDir = Join-Path $ProjectPath "specs"
$FelixDir = Join-Path $ProjectPath "felix"
$RunsDir = Join-Path $ProjectPath "runs"
$PlanFile = Join-Path $ProjectPath "IMPLEMENTATION_PLAN.md"
$AgentsFile = Join-Path $ProjectPath "AGENTS.md"
$ConfigFile = Join-Path $FelixDir "config.json"
$StateFile = Join-Path $FelixDir "state.json"
$RequirementsFile = Join-Path $FelixDir "requirements.json"
$PromptsDir = Join-Path $FelixDir "prompts"

# Validate project structure
$requiredPaths = @($SpecsDir, $FelixDir, $ConfigFile, $RequirementsFile)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Write-Host "ERROR: Required path not found: $path"
        Write-Host "This doesn't appear to be a valid Felix project."
        exit 1
    }
}

# Load config
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$maxIterations = $config.executor.max_iterations
$autoTransition = $config.executor.auto_transition
$defaultMode = $config.executor.default_mode

Write-Host "Max iterations: $maxIterations"
Write-Host ""

# Load requirements
$requirements = Get-Content $RequirementsFile -Raw | ConvertFrom-Json

# Find current requirement (first in_progress or planned)
$currentReq = $requirements.requirements | Where-Object { 
    $_.status -eq "in_progress" 
} | Select-Object -First 1

if (-not $currentReq) {
    $currentReq = $requirements.requirements | Where-Object { 
        $_.status -eq "planned" 
    } | Select-Object -First 1
}

if (-not $currentReq) {
    Write-Host "No requirements to work on (all done or blocked)"
    exit 0
}

Write-Host "Working on: $($currentReq.id) - $($currentReq.title)"
Write-Host ""

# Initialize state if needed
if (-not (Test-Path $StateFile)) {
    $initialState = @{
        current_requirement_id = $currentReq.id
        last_run_id            = $null
        last_mode              = $null
        last_iteration_outcome = $null
        updated_at             = Get-Date -Format "o"
        current_iteration      = 0
        status                 = "ready"
    }
    $initialState | ConvertTo-Json | Set-Content $StateFile
}

# Load state
$state = Get-Content $StateFile -Raw | ConvertFrom-Json

# Main iteration loop
for ($iteration = 1; $iteration -le $maxIterations; $iteration++) {
    Write-Host ""
    Write-Host "═════════════════════════════════════════════════════════════"
    Write-Host "  Felix Agent - Iteration $iteration/$maxIterations"
    
    # Determine mode
    $mode = "building"  # Default
    
    # Check if plan exists and is not empty
    if ((Test-Path $PlanFile)) {
        $planContent = Get-Content $PlanFile -Raw
        if ($planContent.Trim().Length -lt 50) {
            $mode = "planning"
        }
    }
    else {
        $mode = "planning"
    }
    
    # Override with state if available
    if ($state.last_mode -and $iteration -eq 1) {
        # Continue in same mode as last run on first iteration
        $mode = $state.last_mode
    }
    
    Write-Host "  Mode: $($mode.ToUpper())"
    Write-Host "═════════════════════════════════════════════════════════════"
    Write-Host ""
    
    # Update state
    $state.current_iteration = $iteration
    $state.last_mode = $mode
    $state.status = "running"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    
    # Create run directory
    $runId = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
    $runDir = Join-Path $RunsDir $runId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    
    # Load prompt template
    $promptFile = Join-Path $PromptsDir "$mode.md"
    if (-not (Test-Path $promptFile)) {
        Write-Host "ERROR: Prompt template not found: $promptFile"
        exit 1
    }
    
    $promptTemplate = Get-Content $promptFile -Raw
    
    # Gather context
    $contextParts = @()
    
    # Add AGENTS.md if exists
    if (Test-Path $AgentsFile) {
        $agentsContent = Get-Content $AgentsFile -Raw
        $contextParts += "# How to Run This Project`n`n$agentsContent"
    }
    
    # Add all specs
    $specFiles = Get-ChildItem $SpecsDir -Filter "*.md"
    foreach ($specFile in $specFiles) {
        $specContent = Get-Content $specFile.FullName -Raw
        $contextParts += "# Spec: $($specFile.Name)`n`n$specContent"
    }
    
    # Add plan if in building mode
    if ($mode -eq "building" -and (Test-Path $PlanFile)) {
        $planContent = Get-Content $PlanFile -Raw
        $contextParts += "# Implementation Plan`n`n$planContent"
        
        # Snapshot plan
        Copy-Item $PlanFile (Join-Path $runDir "plan.snapshot.md")
    }
    
    # Add requirements status
    $reqSummary = $requirements | ConvertTo-Json -Depth 10
    $contextParts += "# Requirements Status`n`n``````json`n$reqSummary`n``````"
    
    # Add current requirement ID
    $contextParts += "# Current Requirement`n`nYou are working on: **$($currentReq.id)** - $($currentReq.title)"
    
    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"
    
    # Write requirement ID
    Set-Content (Join-Path $runDir "requirement_id.txt") $currentReq.id
    
    # Call droid exec (like ralph.ps1)
    Write-Host "Calling droid exec...`n"
    
    try {
        $output = $fullPrompt | droid exec --skip-permissions-unsafe 2>&1
        Write-Host $output
        
        # Write output log
        Set-Content (Join-Path $runDir "output.log") $output
        
        # Create report
        $success = $LASTEXITCODE -eq 0
        $report = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** $success
**Timestamp:** $(Get-Date -Format "o")

## Output

``````
$output
``````

"@
        Set-Content (Join-Path $runDir "report.md") $report
        
        # Check for completion signal
        if ($output -match '<promise>COMPLETE</promise>') {
            Write-Host ""
            Write-Host "[COMPLETE] Completion signal detected!"
            
            $state.status = "complete"
            $state.last_iteration_outcome = "complete"
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json | Set-Content $StateFile
            
            Write-Host ""
            Write-Host "Felix Agent complete - all tasks done!"
            exit 0
        }
        
        # Check for mode transition (if auto_transition enabled)
        if ($autoTransition) {
            if ($mode -eq "planning" -and (Test-Path $PlanFile)) {
                $planContent = Get-Content $PlanFile -Raw
                if ($planContent.Trim().Length -gt 100) {
                    Write-Host ""
                    Write-Host "-> Auto-transitioning to BUILDING mode"
                    $mode = "building"
                    $state.last_mode = "building"
                }
            }
        }
        
        # Update state
        $state.last_iteration_outcome = "success"
        $state.updated_at = Get-Date -Format "o"
        $state | ConvertTo-Json | Set-Content $StateFile
        
    }
    catch {
        Write-Host "ERROR during droid execution: $_"
        
        # Write error report
        $report = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** false
**Timestamp:** $(Get-Date -Format "o")

## Error

``````
$_
``````

"@
        Set-Content (Join-Path $runDir "report.md") $report
        
        $state.last_iteration_outcome = "error"
        $state.status = "error"
        $state.updated_at = Get-Date -Format "o"
        $state | ConvertTo-Json | Set-Content $StateFile
        
        exit 1
    }
    
    Write-Host ""
    Write-Host "Iteration $iteration complete. Continuing..."
    Write-Host ""
    
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "[WARNING] Reached max iterations ($maxIterations)"

$state.status = "incomplete"
$state.last_iteration_outcome = "max_iterations"
$state.updated_at = Get-Date -Format "o"
$state | ConvertTo-Json | Set-Content $StateFile

exit 1

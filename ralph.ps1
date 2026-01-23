#!/usr/bin/env pwsh
# Ralph Wiggum - Long-running AI agent loop
# Usage: .\ralph.ps1 [max_iterations] [-Feature <featureId>]

param(
    [int]$MaxIterations = 20,
    [string]$Feature = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PrdFile = Join-Path $ScriptDir "prd.json"
$ProgressFile = Join-Path $ScriptDir "progress.txt"
$ArchiveDir = Join-Path $ScriptDir "archive"
$LastBranchFile = Join-Path $ScriptDir ".last-branch"

# Archive previous run if branch changed
if ((Test-Path $PrdFile) -and (Test-Path $LastBranchFile)) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $CurrentBranch = $prdContent.branchName
        $LastBranch = Get-Content $LastBranchFile -Raw -ErrorAction SilentlyContinue
        
        if ($CurrentBranch -and $LastBranch -and ($CurrentBranch -ne $LastBranch.Trim())) {
            # Archive the previous run
            $Date = Get-Date -Format "yyyy-MM-dd"
            # Strip "ralph/" prefix from branch name for folder
            $FolderName = $LastBranch -replace '^ralph/', ''
            $ArchiveFolder = Join-Path $ArchiveDir "$Date-$FolderName"
            
            Write-Host "Archiving previous run: $LastBranch"
            New-Item -ItemType Directory -Path $ArchiveFolder -Force | Out-Null
            
            if (Test-Path $PrdFile) {
                Copy-Item $PrdFile $ArchiveFolder -Force
            }
            if (Test-Path $ProgressFile) {
                Copy-Item $ProgressFile $ArchiveFolder -Force
            }
            
            Write-Host "   Archived to: $ArchiveFolder"
            
            # Reset progress file for new run
            $progressContent = @(
                "# Ralph Progress Log",
                "Started: $(Get-Date)",
                "---"
            ) -join "`r`n"
            Set-Content -Path $ProgressFile -Value $progressContent
        }
    }
    catch {
        # Silently continue if JSON parsing fails
    }
}

# Track current branch
if (Test-Path $PrdFile) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $CurrentBranch = $prdContent.branchName
        if ($CurrentBranch) {
            Set-Content -Path $LastBranchFile -Value $CurrentBranch
        }
    }
    catch {
        # Silently continue if JSON parsing fails
    }
}

# Initialize progress file if it doesn't exist
if (-not (Test-Path $ProgressFile)) {
    $progressContent = @(
        "# Ralph Progress Log",
        "Started: $(Get-Date)",
        "---"
    ) -join "`r`n"
    Set-Content -Path $ProgressFile -Value $progressContent
}

# Initialize build folder as git repo if needed
if (Test-Path $PrdFile) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $BuildFolder = $prdContent.meta.folder
        
        if ($BuildFolder) {
            $BuildPath = Join-Path $ScriptDir $BuildFolder
            
            # Create folder if it doesn't exist
            if (-not (Test-Path $BuildPath)) {
                Write-Host "Creating build folder: $BuildFolder"
                New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
            }
            
            # Initialize git repo if not already initialized
            $GitPath = Join-Path $BuildPath ".git"
            if (-not (Test-Path $GitPath)) {
                Write-Host "Initializing git repository in: $BuildFolder"
                Push-Location $BuildPath
                git init | Out-Null
                git config user.name "Ralph" | Out-Null
                git config user.email "ralph@wiggum.ai" | Out-Null
                Pop-Location
            }
        }
    }
    catch {
        Write-Host "Warning: Could not initialize build folder: $_"
    }
}

# Validate feature if specified
if ($Feature) {
    if (-not (Test-Path $PrdFile)) {
        Write-Host "Error: PRD file not found at $PrdFile"
        exit 1
    }
    
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $foundFeature = $prdContent.features | Where-Object { $_.id -eq $Feature }
        
        if (-not $foundFeature) {
            Write-Host "Error: Feature '$Feature' not found in PRD"
            Write-Host ""
            Write-Host "Available features:"
            $prdContent.features | ForEach-Object {
                Write-Host "  $($_.id) - $($_.title)"
            }
            exit 1
        }
        
        Write-Host "Working on feature: $Feature - $($foundFeature.title)"
    }
    catch {
        Write-Host "Error reading PRD: $_"
        exit 1
    }
}

Write-Host "Starting Ralph - Max iterations: $MaxIterations"
if ($Feature) {
    Write-Host "Feature filter: $Feature"
}

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════"
    Write-Host "  Ralph Iteration $i of $MaxIterations"
    Write-Host "═══════════════════════════════════════════════════════"
    
    # Run droid with the ralph prompt
    try {
        $PromptPath = Join-Path $ScriptDir "prompt.md"
        $PromptContent = Get-Content $PromptPath -Raw
        
        # If feature is specified, add it to the prompt
        if ($Feature) {
            $FeatureInstruction = "`n`n## Feature Filter`n`nYou are working ONLY on feature: **$Feature**`n`nIgnore all other features. Only pick user stories from feature $Feature.`n"
            $PromptContent = $PromptContent + $FeatureInstruction
        }
        
        $Output = $PromptContent | droid exec --skip-permissions-unsafe 2>&1
        Write-Host $Output
        
        # Check for completion signal
        if ($Output -match '<promise>COMPLETE</promise>') {
            Write-Host ""
            Write-Host "Ralph completed all tasks!"
            Write-Host "Completed at iteration $i of $MaxIterations"
            exit 0
        }
    }
    catch {
        Write-Host "Error during iteration: $_"
    }
    
    Write-Host "Iteration $i complete. Continuing..."
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Ralph reached max iterations ($MaxIterations) without completing all tasks."
Write-Host "Check $ProgressFile for status."
exit 1

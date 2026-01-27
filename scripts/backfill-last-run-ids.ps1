# Backfill last_run_id fields in requirements.json
# This is a one-time migration script to populate last_run_id by scanning existing runs/

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Backfill Last Run IDs" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host ""

$runsDir = Join-Path $ProjectRoot "runs"
$requirementsFile = Join-Path $ProjectRoot "felix\requirements.json"

# Check if runs directory exists
if (-not (Test-Path $runsDir)) {
    Write-Host "ERROR: Runs directory not found: $runsDir" -ForegroundColor Red
    exit 1
}

# Check if requirements.json exists
if (-not (Test-Path $requirementsFile)) {
    Write-Host "ERROR: requirements.json not found: $requirementsFile" -ForegroundColor Red
    exit 1
}

Write-Host "Scanning runs directory: $runsDir" -ForegroundColor Yellow
Write-Host ""

# Scan all run directories and group by requirement_id
$runsByRequirement = @{}

Get-ChildItem -Path $runsDir -Directory | Sort-Object Name -Descending | ForEach-Object {
    $runDir = $_
    $runId = $runDir.Name
    $reqIdFile = Join-Path $runDir.FullName "requirement_id.txt"
    
    if (Test-Path $reqIdFile) {
        try {
            $requirementId = (Get-Content $reqIdFile -Raw).Trim()
            
            if ($requirementId) {
                # Store the first (most recent) run for each requirement
                if (-not $runsByRequirement.ContainsKey($requirementId)) {
                    $runsByRequirement[$requirementId] = $runId
                    Write-Host "  Found: $requirementId -> $runId" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Host "  Warning: Failed to read $reqIdFile" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Found $($runsByRequirement.Count) requirements with run history" -ForegroundColor Green
Write-Host ""

# Update requirements.json with last_run_id fields
Write-Host "Updating requirements.json..." -ForegroundColor Yellow

$content = Get-Content $requirementsFile -Raw
$updatedContent = $content

$updatedCount = 0

foreach ($reqId in $runsByRequirement.Keys) {
    $runId = $runsByRequirement[$reqId]
    
    # Check if requirement exists in requirements.json
    $reqPattern = '"id"\s*:\s*"' + [regex]::Escape($reqId) + '"'
    if ($updatedContent -notmatch $reqPattern) {
        Write-Host "  Warning: Requirement $reqId not found in requirements.json" -ForegroundColor Yellow
        continue
    }
    
    # Check if last_run_id field already exists for this requirement
    $runIdPattern = '("id"\s*:\s*"' + [regex]::Escape($reqId) + '"[\s\S]*?"last_run_id"\s*:\s*")([^"]*)(")'
    
    if ($updatedContent -match $runIdPattern) {
        # Update existing last_run_id
        $updatedContent = $updatedContent -replace $runIdPattern, "`${1}$runId`$3"
        Write-Host "  Updated: $reqId -> $runId" -ForegroundColor Green
    }
    else {
        # Add last_run_id field after updated_at
        $insertPattern = '("id"\s*:\s*"' + [regex]::Escape($reqId) + '"[\s\S]*?"updated_at"\s*:\s*"[^"]+")' 
        $updatedContent = $updatedContent -replace $insertPattern, "`$1,`n      ""last_run_id"": ""$runId"""
        Write-Host "  Added: $reqId -> $runId" -ForegroundColor Green
    }
    
    $updatedCount++
}

# Write back to file
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($requirementsFile, $updatedContent, $utf8NoBom)
    
    Write-Host ""
    Write-Host "✅ Successfully updated $updatedCount requirements" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "❌ ERROR: Failed to write requirements.json: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Backfill complete!" -ForegroundColor Cyan

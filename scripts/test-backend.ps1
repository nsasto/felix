# Test Backend - Run Python backend tests
# Automatically sets up virtual environment if needed

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$backendDir = Join-Path $ProjectRoot "app\backend"
$venvDir = Join-Path $backendDir ".venv"
$requirementsFile = Join-Path $backendDir "requirements.txt"

Write-Host "Backend Test Runner" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host ""

# Check if backend directory exists
if (-not (Test-Path $backendDir)) {
    Write-Host "ERROR: Backend directory not found: $backendDir" -ForegroundColor Red
    exit 1
}

Set-Location $backendDir

# Setup virtual environment if it doesn't exist
if (-not (Test-Path $venvDir)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv .venv
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create virtual environment" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Virtual environment created" -ForegroundColor Green
}

# Activate virtual environment
$activateScript = Join-Path $venvDir "Scripts\Activate.ps1"
if (-not (Test-Path $activateScript)) {
    Write-Host "ERROR: Activation script not found: $activateScript" -ForegroundColor Red
    exit 1
}

Write-Host "Activating virtual environment..." -ForegroundColor Cyan
& $activateScript

# Install/update dependencies
Write-Host "Checking dependencies..." -ForegroundColor Cyan
python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r requirements.txt
python -m pip install --quiet pytest pytest-cov

Write-Host "Dependencies ready" -ForegroundColor Green
Write-Host ""

# Create tests directory if it doesn't exist
$testsDir = Join-Path $backendDir "tests"
if (-not (Test-Path $testsDir)) {
    Write-Host "WARNING: tests/ directory not found, creating it..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $testsDir | Out-Null
    
    # Create __init__.py
    $initFile = Join-Path $testsDir "__init__.py"
    "" | Set-Content $initFile -Encoding UTF8
    
    Write-Host "Created tests/ directory" -ForegroundColor Green
    Write-Host "  Add test files to: $testsDir" -ForegroundColor Gray
    Write-Host ""
}

# Run pytest
Write-Host "Running tests..." -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
python -m pytest tests/ -v --tb=short

$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "All tests passed" -ForegroundColor Green
} elseif ($exitCode -eq 5) {
    Write-Host "No tests collected" -ForegroundColor Yellow
    Write-Host "  Add test files matching test_*.py or *_test.py to tests/" -ForegroundColor Gray
} else {
    Write-Host "Tests failed (exit code: $exitCode)" -ForegroundColor Red
}

exit $exitCode

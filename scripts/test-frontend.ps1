# Test Frontend - Run React frontend tests

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$frontendDir = Join-Path $ProjectRoot "app\frontend"

Write-Host "Frontend Test Runner" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
Write-Host ""

# Check if frontend directory exists
if (-not (Test-Path $frontendDir)) {
    Write-Host "ERROR: Frontend directory not found: $frontendDir" -ForegroundColor Red
    exit 1
}

Set-Location $frontendDir

# Check if node_modules exists
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    npm install
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Dependencies installed" -ForegroundColor Green
}

# Run tests
Write-Host "Running tests..." -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
npm test -- --run

$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "All tests passed" -ForegroundColor Green
} else {
    Write-Host "Tests failed (exit code: $exitCode)" -ForegroundColor Red
}

exit $exitCode

# Setup Development Environment - One-time setup for development

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Felix Development Environment Setup" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$backendDir = Join-Path $ProjectRoot "app\backend"
$frontendDir = Join-Path $ProjectRoot "app\frontend"

# Backend Setup
Write-Host "[1/3] Setting up Python backend..." -ForegroundColor Yellow
Write-Host ""

if (Test-Path $backendDir) {
    Set-Location $backendDir
    
    # Create virtual environment
    if (-not (Test-Path ".venv")) {
        Write-Host "  Creating Python virtual environment..." -ForegroundColor Cyan
        python -m venv .venv
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to create virtual environment" -ForegroundColor Red
            exit 1
        }
        Write-Host "   Virtual environment created" -ForegroundColor Green
    }
    else {
        Write-Host "   Virtual environment already exists" -ForegroundColor Green
    }
    
    # Activate and install dependencies
    Write-Host "  Installing dependencies..." -ForegroundColor Cyan
    & .venv\Scripts\Activate.ps1
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet -r requirements.txt
    python -m pip install --quiet pytest pytest-cov
    Write-Host "   Dependencies installed" -ForegroundColor Green
    
    # Create tests directory
    if (-not (Test-Path "tests")) {
        Write-Host "  Creating tests directory..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path "tests" | Out-Null
        "" | Set-Content "tests\__init__.py" -Encoding UTF8
        Write-Host "   Tests directory created" -ForegroundColor Green
    }
    else {
        Write-Host "   Tests directory exists" -ForegroundColor Green
    }
}
else {
    Write-Host "   Backend directory not found, skipping" -ForegroundColor Yellow
}

Write-Host ""

# Frontend Setup
Write-Host "[2/3] Setting up React frontend..." -ForegroundColor Yellow
Write-Host ""

if (Test-Path $frontendDir) {
    Set-Location $frontendDir
    
    Write-Host "  Installing npm dependencies..." -ForegroundColor Cyan
    npm install
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to install npm dependencies" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "   npm dependencies installed" -ForegroundColor Green
}
else {
    Write-Host "   Frontend directory not found, skipping" -ForegroundColor Yellow
}

Write-Host ""

# Verify Environment
Write-Host "[3/3] Verifying environment..." -ForegroundColor Yellow
Write-Host ""

Set-Location $ProjectRoot

# Check Python
Write-Host "  Checking Python..." -ForegroundColor Cyan
$pythonVersion = python --version 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   $pythonVersion" -ForegroundColor Green
}
else {
    Write-Host "   Python not found" -ForegroundColor Red
}

# Check Node
Write-Host "  Checking Node.js..." -ForegroundColor Cyan
$nodeVersion = node --version 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   Node.js $nodeVersion" -ForegroundColor Green
}
else {
    Write-Host "   Node.js not found" -ForegroundColor Red
}

# Check npm
Write-Host "  Checking npm..." -ForegroundColor Cyan
$npmVersion = npm --version 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   npm $npmVersion" -ForegroundColor Green
}
else {
    Write-Host "   npm not found" -ForegroundColor Red
}

# Check PostgreSQL
Write-Host "  Checking PostgreSQL..." -ForegroundColor Cyan
try {
    $psqlPath = Get-Command psql -ErrorAction Stop | Select-Object -ExpandProperty Source
    $psqlVersion = & $psqlPath --version 2>&1
    Write-Host "   $psqlVersion" -ForegroundColor Green
    
    # Check if server is running
    $testConnection = & $psqlPath -U postgres -c "SELECT 1;" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   PostgreSQL server is running" -ForegroundColor Green
        
        # Check if felix database exists
        $dbCheck = & $psqlPath -U postgres -lqt 2>&1 | Select-String -Pattern "^\s*felix\s"
        if ($dbCheck) {
            Write-Host "   Database 'felix' exists" -ForegroundColor Green
        }
        else {
            Write-Host "   Database 'felix' not found" -ForegroundColor Yellow
            Write-Host "   Run: .\scripts\setup-db.ps1" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   PostgreSQL server not running" -ForegroundColor Yellow
        $pgBin = Split-Path $psqlPath
        $pgData = Join-Path (Split-Path $pgBin) "data"
        Write-Host "   Start with: pg_ctl -D '$pgData' start" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "   PostgreSQL not found" -ForegroundColor Yellow
    Write-Host "   Install from: https://www.postgresql.org/download/windows/" -ForegroundColor Gray
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Quick start commands:" -ForegroundColor Cyan
Write-Host "  Backend tests:  .\scripts\test-backend.ps1" -ForegroundColor Gray
Write-Host "  Frontend tests: .\scripts\test-frontend.ps1" -ForegroundColor Gray
Write-Host "  Start backend:  python app\backend\main.py" -ForegroundColor Gray
Write-Host "  Start frontend: npm run dev --prefix app\frontend" -ForegroundColor Gray
Write-Host ""

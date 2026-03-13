# Setup Development Environment - One-time setup for development

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$ForceDb
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

    # Ensure .env exists
    if (-not (Test-Path ".env") -and (Test-Path ".env.example")) {
        Write-Host "  Creating .env from .env.example..." -ForegroundColor Cyan
        Copy-Item ".env.example" ".env"
        Write-Host "   .env created" -ForegroundColor Green
    }
    
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

    Write-Host "  Running typecheck..." -ForegroundColor Cyan
    npm run typecheck
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: typecheck failed" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   Frontend directory not found, skipping" -ForegroundColor Yellow
}

Write-Host ""

# Database + Felix CLI setup
Write-Host "[3/5] Setting up database..." -ForegroundColor Yellow
Write-Host ""
Set-Location $ProjectRoot

if ($ForceDb) {
    Write-Host "  Running database setup (Force + Seed)..." -ForegroundColor Cyan
    .\scripts\setup-db.ps1 -Force -Seed
}
else {
    Write-Host "  Running database setup (Seed)..." -ForegroundColor Cyan
    .\scripts\setup-db.ps1 -Seed
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Database setup failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/5] Initializing requirements..." -ForegroundColor Yellow
Write-Host ""

powershell -File .\.felix\felix.ps1 spec fix
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to generate requirements.json" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[5/5] Migrating data to database..." -ForegroundColor Yellow
Write-Host ""

# Ensure dev org/project rows exist before migration scripts (seed migration may be
# tracked in schema_migrations but data may be missing if DB was reset without -Seed)
Write-Host "  Ensuring dev project record exists..." -ForegroundColor Cyan
$gitUrl = git -C $ProjectRoot remote get-url origin 2>$null
if (-not $gitUrl) { $gitUrl = 'https://github.com/placeholder/felix' }
$POSTGRES_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'postgres' }
$DATABASE_NAME = if ($env:DATABASE_NAME) { $env:DATABASE_NAME } else { 'felix' }
$ensureSql = @"
INSERT INTO organizations (id, name, slug, owner_id, metadata)
VALUES ('00000000-0000-0000-0000-000000000001', 'dev_org', 'dev_org', 'dev_user', '{"email": "dev_user@dev_org.com"}')
ON CONFLICT (id) DO NOTHING;

INSERT INTO projects (id, org_id, name, slug, description, git_url, metadata)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Felix', 'felix', 'Felix AI agent orchestration system', '$gitUrl', '{}')
ON CONFLICT (id) DO NOTHING;

INSERT INTO organization_members (org_id, user_id, role)
VALUES ('00000000-0000-0000-0000-000000000001', 'dev_user', 'owner')
ON CONFLICT (org_id, user_id) DO NOTHING;
"@
$tmpSql = [System.IO.Path]::GetTempFileName() + '.sql'
$ensureSql | Set-Content $tmpSql -Encoding UTF8
$ErrorActionPreference = "Continue"
if ($env:DATABASE_URL) {
    psql -d $env:DATABASE_URL -f $tmpSql 2>&1 | Out-Null
}
else {
    psql -U $POSTGRES_USER -d $DATABASE_NAME -f $tmpSql 2>&1 | Out-Null
}
$ErrorActionPreference = "Stop"
Remove-Item $tmpSql -ErrorAction SilentlyContinue
Write-Host "   Dev project ready" -ForegroundColor Green

.\scripts\migrate-agent-profiles.ps1 -OrgId "00000000-0000-0000-0000-000000000001"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to migrate agent profiles" -ForegroundColor Red
    exit 1
}

.\scripts\migrate-agents.ps1 -ProjectId "00000000-0000-0000-0000-000000000001"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to migrate agents" -ForegroundColor Red
    exit 1
}

Write-Host "  Backfilling agent keys..." -ForegroundColor Cyan
if (-not $env:DATABASE_URL -and (Test-Path "$backendDir\.env")) {
    $dbUrlLine = Get-Content "$backendDir\.env" | Where-Object { $_ -match '^DATABASE_URL=' } | Select-Object -First 1
    if ($dbUrlLine) {
        $env:DATABASE_URL = $dbUrlLine -replace '^[^=]+=',''
    }
}
if ($env:DATABASE_URL) {
    & "$backendDir\.venv\Scripts\python.exe" "scripts\migrate_agent_keys.py" --db-url $env:DATABASE_URL --confirm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to backfill agent keys" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "  WARNING: DATABASE_URL not set; skipping agent key backfill" -ForegroundColor Yellow
}

.\scripts\migrate-requirements.ps1 -ProjectId "00000000-0000-0000-0000-000000000001"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to migrate requirements" -ForegroundColor Red
    exit 1
}

# Verify Environment
Write-Host "[Verify] Checking environment..." -ForegroundColor Yellow
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
            Write-Host "   Run: .\scripts\setup-db.ps1 -Force -Seed" -ForegroundColor Yellow
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

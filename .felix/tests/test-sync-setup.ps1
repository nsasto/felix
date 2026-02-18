<#
.SYNOPSIS
    Initialize test environment for run artifact sync end-to-end tests.

.DESCRIPTION
    This script sets up the test environment for S-0062 sync tests:
    - Verifies PostgreSQL is running
    - Creates/resets felix_test database schema
    - Configures STORAGE_TYPE=filesystem environment variable
    - Creates temp storage directory for test artifacts
    - Verifies backend server connectivity

.PARAMETER PgBin
    Path to PostgreSQL bin directory (optional - can also use PG_BIN env var)

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER StoragePath
    Path for test artifact storage (default: $env:TEMP\felix-sync-test\storage)

.EXAMPLE
    .\scripts\test-sync-setup.ps1
    # Initialize with defaults

.EXAMPLE
    .\scripts\test-sync-setup.ps1 -BackendUrl http://localhost:8081
    # Use custom backend URL

.NOTES
    Environment variables set by this script:
    - STORAGE_TYPE: Set to "filesystem"
    - STORAGE_BASE_PATH: Path to test storage directory
    - FELIX_SYNC_TEST_URL: Backend URL for tests
    - FELIX_SYNC_TEST_STORAGE: Storage directory path
    - DATABASE_URL: PostgreSQL connection string (if using felix_test)

    The script outputs a summary of the test environment configuration.
#>

param(
    [string]$PgBin,
    [string]$BackendUrl = "http://localhost:8080",
    [string]$StoragePath
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Test Environment Setup" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION DEFAULTS
# =============================================================================

# Allow overriding via environment variables
if (-not $PgBin) { $PgBin = $env:PG_BIN }
$POSTGRES_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'postgres' }
$DATABASE_NAME = 'felix_test'
$PRODUCTION_DATABASE = if ($env:DATABASE_NAME) { $env:DATABASE_NAME } else { 'felix' }

# Set default storage path
if (-not $StoragePath) {
    $StoragePath = Join-Path $env:TEMP "felix-sync-test\storage"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Resolve-PostgresTools {
    param($pgBin, [ref]$psqlExe)

    if ($pgBin) {
        $candidatePsql = Join-Path -Path $pgBin -ChildPath 'psql.exe'
        if (Test-Path $candidatePsql) { 
            $psqlExe.Value = $candidatePsql
            return
        }
    }

    try {
        $foundPsql = Get-Command psql -ErrorAction Stop
        $psqlExe.Value = $foundPsql.Source
    }
    catch { }
}

function Test-BackendConnectivity {
    param([string]$Url)
    
    try {
        $response = Invoke-WebRequest -Uri "$Url/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

# =============================================================================
# STEP 1: Verify PostgreSQL
# =============================================================================

Write-Host "Step 1: Verifying PostgreSQL..." -ForegroundColor Yellow

$psqlExe = ''
Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe)

if (-not $psqlExe) {
    Write-Host "  [WARN] psql command not found." -ForegroundColor Yellow
    Write-Host "  Tests requiring database will need PostgreSQL available." -ForegroundColor Yellow
    Write-Host "  Pass -PgBin to specify PostgreSQL bin directory." -ForegroundColor Yellow
    $dbAvailable = $false
}
else {
    Write-Host "  Found psql: $psqlExe" -ForegroundColor Gray
    
    # Check if PostgreSQL server is running
    try {
        $version = & $psqlExe -U $POSTGRES_USER -d postgres -c "SELECT 1;" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] PostgreSQL server is running" -ForegroundColor Green
            $dbAvailable = $true
        }
        else {
            Write-Host "  [WARN] Cannot connect to PostgreSQL server." -ForegroundColor Yellow
            $dbAvailable = $false
        }
    }
    catch {
        Write-Host "  [WARN] PostgreSQL connection failed." -ForegroundColor Yellow
        $dbAvailable = $false
    }
}

# =============================================================================
# STEP 2: Create/Reset Test Database Schema
# =============================================================================

Write-Host ""
Write-Host "Step 2: Setting up test database schema..." -ForegroundColor Yellow

if ($dbAvailable) {
    # Check if felix_test database exists
    $dbExists = & $psqlExe -U $POSTGRES_USER -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME';" 2>&1
    
    if ($dbExists -eq "1") {
        Write-Host "  Database '$DATABASE_NAME' already exists" -ForegroundColor Gray
        
        # Truncate test data tables (preserve schema)
        Write-Host "  Clearing test data..." -ForegroundColor Gray
        $truncateQuery = @"
            TRUNCATE TABLE run_files CASCADE;
            TRUNCATE TABLE run_events CASCADE;
            TRUNCATE TABLE runs CASCADE;
"@
        $ErrorActionPreference = "Continue"
        & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -c $truncateQuery 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
        Write-Host "  [OK] Test data cleared" -ForegroundColor Green
    }
    else {
        # Create test database by copying from production
        Write-Host "  Creating '$DATABASE_NAME' database..." -ForegroundColor Gray
        
        # First check if production database exists
        $prodExists = & $psqlExe -U $POSTGRES_USER -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$PRODUCTION_DATABASE';" 2>&1
        
        if ($prodExists -eq "1") {
            # Disconnect clients from production database
            & $psqlExe -U $POSTGRES_USER -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$PRODUCTION_DATABASE' AND pid <> pg_backend_pid();" 2>&1 | Out-Null
            
            # Create test database as template copy
            & $psqlExe -U $POSTGRES_USER -d postgres -c "CREATE DATABASE $DATABASE_NAME WITH TEMPLATE $PRODUCTION_DATABASE OWNER $POSTGRES_USER;" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Database '$DATABASE_NAME' created from '$PRODUCTION_DATABASE'" -ForegroundColor Green
                
                # Clear existing data in the new test database
                $truncateQuery = @"
                    TRUNCATE TABLE run_files CASCADE;
                    TRUNCATE TABLE run_events CASCADE;
                    TRUNCATE TABLE runs CASCADE;
"@
                & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -c $truncateQuery 2>&1 | Out-Null
            }
            else {
                Write-Host "  [ERROR] Failed to create test database" -ForegroundColor Red
                $dbAvailable = $false
            }
        }
        else {
            Write-Host "  [WARN] Production database '$PRODUCTION_DATABASE' not found" -ForegroundColor Yellow
            Write-Host "  Run scripts\setup-db.ps1 first to create the schema" -ForegroundColor Yellow
            $dbAvailable = $false
        }
    }
}
else {
    Write-Host "  [SKIP] Database setup skipped (PostgreSQL not available)" -ForegroundColor Yellow
}

# =============================================================================
# STEP 3: Configure Storage Environment
# =============================================================================

Write-Host ""
Write-Host "Step 3: Configuring storage environment..." -ForegroundColor Yellow

# Create storage directory
if (-not (Test-Path $StoragePath)) {
    New-Item -ItemType Directory -Path $StoragePath -Force | Out-Null
    Write-Host "  Created storage directory: $StoragePath" -ForegroundColor Gray
}
else {
    # Clear existing storage
    Get-ChildItem -Path $StoragePath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Cleared existing storage: $StoragePath" -ForegroundColor Gray
}

# Set environment variables
$env:STORAGE_TYPE = "filesystem"
$env:STORAGE_BASE_PATH = $StoragePath
$env:FELIX_SYNC_TEST_URL = $BackendUrl
$env:FELIX_SYNC_TEST_STORAGE = $StoragePath

if ($dbAvailable) {
    $env:DATABASE_URL = "postgresql://${POSTGRES_USER}@localhost:5432/${DATABASE_NAME}"
}

Write-Host "  [OK] Storage environment configured" -ForegroundColor Green
Write-Host "    STORAGE_TYPE = filesystem" -ForegroundColor Gray
Write-Host "    STORAGE_BASE_PATH = $StoragePath" -ForegroundColor Gray

# =============================================================================
# STEP 4: Verify Backend Connectivity
# =============================================================================

Write-Host ""
Write-Host "Step 4: Checking backend server..." -ForegroundColor Yellow

$backendReady = Test-BackendConnectivity -Url $BackendUrl

if ($backendReady) {
    Write-Host "  [OK] Backend server responding at $BackendUrl" -ForegroundColor Green
}
else {
    Write-Host "  [WARN] Backend server not responding at $BackendUrl" -ForegroundColor Yellow
    Write-Host "  Some tests require a running backend. Start with:" -ForegroundColor Yellow
    Write-Host "    cd app\backend && python main.py" -ForegroundColor Gray
}

# =============================================================================
# STEP 5: Create Test Outbox Directory
# =============================================================================

Write-Host ""
Write-Host "Step 5: Creating test outbox directory..." -ForegroundColor Yellow

$OutboxPath = Join-Path $env:TEMP "felix-sync-test\.felix\outbox"
if (-not (Test-Path $OutboxPath)) {
    New-Item -ItemType Directory -Path $OutboxPath -Force | Out-Null
}
else {
    # Clear existing outbox files
    Get-ChildItem -Path $OutboxPath -Filter "*.jsonl" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

$env:FELIX_SYNC_TEST_OUTBOX = $OutboxPath
Write-Host "  [OK] Outbox directory ready: $OutboxPath" -ForegroundColor Green

# =============================================================================
# SUMMARY
# =============================================================================

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Test Environment Setup Complete" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor White
Write-Host "  Backend URL:      $BackendUrl" -ForegroundColor Gray
Write-Host "  Storage Path:     $StoragePath" -ForegroundColor Gray
Write-Host "  Outbox Path:      $OutboxPath" -ForegroundColor Gray
if ($dbAvailable) {
    Write-Host "  Database:         $DATABASE_NAME" -ForegroundColor Gray
}
else {
    Write-Host "  Database:         (not available)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Status:" -ForegroundColor White
Write-Host "  PostgreSQL:       $(if ($dbAvailable) { 'Ready' } else { 'Not Available' })" -ForegroundColor $(if ($dbAvailable) { 'Green' } else { 'Yellow' })
Write-Host "  Backend Server:   $(if ($backendReady) { 'Ready' } else { 'Not Available' })" -ForegroundColor $(if ($backendReady) { 'Green' } else { 'Yellow' })
Write-Host "  Storage:          Ready" -ForegroundColor Green
Write-Host ""

# Export configuration for other test scripts
$configFile = Join-Path $env:TEMP "felix-sync-test\config.json"
@{
    backend_url = $BackendUrl
    storage_path = $StoragePath
    outbox_path = $OutboxPath
    database_name = $DATABASE_NAME
    database_available = $dbAvailable
    backend_available = $backendReady
} | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

Write-Host "Configuration saved to: $configFile" -ForegroundColor Gray
Write-Host ""

# Return success if minimum requirements met (storage ready)
exit 0

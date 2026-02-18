<#
.SYNOPSIS
    Clean up test environment after run artifact sync end-to-end tests.

.DESCRIPTION
    This script cleans up the test environment for S-0062 sync tests:
    - Removes test storage directory contents
    - Clears test database records (run_files, run_events, runs)
    - Removes test outbox files
    - Handles cleanup errors gracefully

.PARAMETER PgBin
    Path to PostgreSQL bin directory (optional - can also use PG_BIN env var)

.PARAMETER StoragePath
    Path for test artifact storage (default: $env:TEMP\felix-sync-test\storage)

.PARAMETER PreserveDatabase
    If specified, skips database cleanup (useful for debugging)

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\scripts\test-sync-cleanup.ps1
    # Clean up with defaults

.EXAMPLE
    .\scripts\test-sync-cleanup.ps1 -PreserveDatabase
    # Clean up but keep database records

.EXAMPLE
    .\scripts\test-sync-cleanup.ps1 -Force
    # Clean up without confirmation

.NOTES
    This script is safe to run multiple times.
    All errors are handled gracefully to ensure maximum cleanup.
#>

param(
    [string]$PgBin,
    [string]$StoragePath,
    [switch]$PreserveDatabase,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Test Environment Cleanup" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

# Allow overriding via environment variables
if (-not $PgBin) { $PgBin = $env:PG_BIN }
$POSTGRES_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'postgres' }
$DATABASE_NAME = 'felix_test'

# Set default paths
if (-not $StoragePath) {
    $StoragePath = Join-Path $env:TEMP "felix-sync-test\storage"
}
$OutboxPath = Join-Path $env:TEMP "felix-sync-test\.felix\outbox"
$TestRootPath = Join-Path $env:TEMP "felix-sync-test"

# =============================================================================
# CONFIRMATION
# =============================================================================

if (-not $Force) {
    Write-Host "This will clean up the following:" -ForegroundColor Yellow
    Write-Host "  - Storage directory: $StoragePath" -ForegroundColor Gray
    Write-Host "  - Outbox directory: $OutboxPath" -ForegroundColor Gray
    Write-Host "  - Test root: $TestRootPath" -ForegroundColor Gray
    if (-not $PreserveDatabase) {
        Write-Host "  - Database records in: $DATABASE_NAME (runs, run_events, run_files)" -ForegroundColor Gray
    }
    Write-Host ""
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
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

$cleanupErrors = @()

# =============================================================================
# STEP 1: Clean Storage Directory
# =============================================================================

Write-Host "Step 1: Cleaning storage directory..." -ForegroundColor Yellow

if (Test-Path $StoragePath) {
    try {
        $itemCount = (Get-ChildItem -Path $StoragePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Get-ChildItem -Path $StoragePath -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction Stop
        Write-Host "  [OK] Removed $itemCount files from storage" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Some storage files could not be removed: $_" -ForegroundColor Yellow
        $cleanupErrors += "Storage cleanup: $_"
    }
}
else {
    Write-Host "  [SKIP] Storage directory does not exist" -ForegroundColor Gray
}

# =============================================================================
# STEP 2: Clean Outbox Directory
# =============================================================================

Write-Host ""
Write-Host "Step 2: Cleaning outbox directory..." -ForegroundColor Yellow

if (Test-Path $OutboxPath) {
    try {
        $outboxFiles = Get-ChildItem -Path $OutboxPath -Filter "*.jsonl" -Force -ErrorAction SilentlyContinue
        $outboxCount = ($outboxFiles | Measure-Object).Count
        $outboxFiles | Remove-Item -Force -ErrorAction Stop
        Write-Host "  [OK] Removed $outboxCount outbox files" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Some outbox files could not be removed: $_" -ForegroundColor Yellow
        $cleanupErrors += "Outbox cleanup: $_"
    }
}
else {
    Write-Host "  [SKIP] Outbox directory does not exist" -ForegroundColor Gray
}

# =============================================================================
# STEP 3: Clean Database Records
# =============================================================================

Write-Host ""
Write-Host "Step 3: Cleaning database records..." -ForegroundColor Yellow

if ($PreserveDatabase) {
    Write-Host "  [SKIP] Database cleanup skipped (-PreserveDatabase)" -ForegroundColor Gray
}
else {
    $psqlExe = ''
    Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe)
    
    if (-not $psqlExe) {
        Write-Host "  [SKIP] psql not found - database cleanup skipped" -ForegroundColor Yellow
    }
    else {
        # Check if database exists
        $dbExists = & $psqlExe -U $POSTGRES_USER -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME';" 2>&1
        
        if ($dbExists -eq "1") {
            try {
                # Truncate test tables in order (respecting foreign key constraints)
                $truncateQuery = @"
                    -- Clear run files first (depends on runs)
                    TRUNCATE TABLE run_files CASCADE;
                    -- Clear run events (depends on runs)
                    TRUNCATE TABLE run_events CASCADE;
                    -- Clear runs
                    TRUNCATE TABLE runs CASCADE;
"@
                $result = & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -c $truncateQuery 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] Database records cleared (run_files, run_events, runs)" -ForegroundColor Green
                }
                else {
                    Write-Host "  [WARN] Database cleanup returned: $result" -ForegroundColor Yellow
                    $cleanupErrors += "Database cleanup: $result"
                }
            }
            catch {
                Write-Host "  [WARN] Database cleanup failed: $_" -ForegroundColor Yellow
                $cleanupErrors += "Database cleanup: $_"
            }
        }
        else {
            Write-Host "  [SKIP] Database '$DATABASE_NAME' does not exist" -ForegroundColor Gray
        }
    }
}

# =============================================================================
# STEP 4: Remove Test Config File
# =============================================================================

Write-Host ""
Write-Host "Step 4: Removing test config file..." -ForegroundColor Yellow

$configFile = Join-Path $TestRootPath "config.json"
if (Test-Path $configFile) {
    try {
        Remove-Item -Path $configFile -Force -ErrorAction Stop
        Write-Host "  [OK] Removed config file" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Could not remove config file: $_" -ForegroundColor Yellow
        $cleanupErrors += "Config cleanup: $_"
    }
}
else {
    Write-Host "  [SKIP] Config file does not exist" -ForegroundColor Gray
}

# =============================================================================
# STEP 5: Clean Empty Directories
# =============================================================================

Write-Host ""
Write-Host "Step 5: Removing empty directories..." -ForegroundColor Yellow

$dirsToCheck = @(
    $StoragePath,
    $OutboxPath,
    (Join-Path $TestRootPath ".felix"),
    $TestRootPath
)

foreach ($dir in $dirsToCheck) {
    if (Test-Path $dir) {
        $items = Get-ChildItem -Path $dir -Force -ErrorAction SilentlyContinue
        if (($items | Measure-Object).Count -eq 0) {
            try {
                Remove-Item -Path $dir -Force -ErrorAction Stop
                Write-Host "  Removed empty directory: $dir" -ForegroundColor Gray
            }
            catch {
                # Ignore errors removing empty directories
            }
        }
    }
}

Write-Host "  [OK] Empty directories cleaned" -ForegroundColor Green

# =============================================================================
# STEP 6: Clear Environment Variables
# =============================================================================

Write-Host ""
Write-Host "Step 6: Clearing environment variables..." -ForegroundColor Yellow

$envVars = @(
    "FELIX_SYNC_TEST_URL",
    "FELIX_SYNC_TEST_STORAGE",
    "FELIX_SYNC_TEST_OUTBOX"
)

foreach ($var in $envVars) {
    if ($env:$var) {
        Remove-Item "env:$var" -ErrorAction SilentlyContinue
        Write-Host "  Cleared: $var" -ForegroundColor Gray
    }
}

Write-Host "  [OK] Environment variables cleared" -ForegroundColor Green

# =============================================================================
# SUMMARY
# =============================================================================

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Cleanup Complete" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

if ($cleanupErrors.Count -gt 0) {
    Write-Host "Completed with warnings:" -ForegroundColor Yellow
    foreach ($err in $cleanupErrors) {
        Write-Host "  - $err" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 1
}
else {
    Write-Host "All cleanup operations completed successfully." -ForegroundColor Green
    Write-Host ""
    exit 0
}

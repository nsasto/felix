<#
.SYNOPSIS
    Sets up the Felix PostgreSQL database with all migrations.

.DESCRIPTION
    This script creates the felix database (if it doesn't exist) and runs all
    SQL migration files in order. It tracks which migrations have been applied
    using a schema_migrations table.

.PARAMETER Force
    Drop and recreate the database from scratch (destroys all data).

.EXAMPLE
    .\scripts\setup-db.ps1
    # Run all pending migrations

.EXAMPLE
    .\scripts\setup-db.ps1 -Force
    # Drop database and recreate from scratch
#>

param(
    [string]$PgBin,
    [string]$DataDir,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Allow overriding via environment variables
$PgBin = $PgBin -or $env:PG_BIN
$DataDir = $DataDir -or $env:PGDATA
$POSTGRES_USER = $env:POSTGRES_USER -or 'postgres'
$DATABASE_NAME = $env:DATABASE_NAME -or 'felix'
$MIGRATIONS_DIR = 'app/backend/migrations'

# Resolve psql/pg_ctl paths
function Resolve-PostgresTools {
    param($pgBin, [ref]$psqlExe, [ref]$pgCtlExe)

    if ($pgBin) {
        $candidatePsql = Join-Path -Path $pgBin -ChildPath 'psql.exe'
        $candidatePgCtl = Join-Path -Path $pgBin -ChildPath 'pg_ctl.exe'
        if (Test-Path $candidatePsql) { $psqlExe.Value = $candidatePsql }
        if (Test-Path $candidatePgCtl) { $pgCtlExe.Value = $candidatePgCtl }
        if ($psqlExe.Value -or $pgCtlExe.Value) {
            # Prepend to PATH for this session if not present
            if (-not ($env:Path -split ';' | Where-Object { $_ -eq $pgBin })) {
                $env:Path = "$pgBin;" + $env:Path
            }
            return
        }
    }

    try {
        $foundPsql = Get-Command psql -ErrorAction Stop
        $psqlExe.Value = $foundPsql.Source
    }
    catch { }

    try {
        $foundPgCtl = Get-Command pg_ctl -ErrorAction Stop
        $pgCtlExe.Value = $foundPgCtl.Source
    }
    catch { }
}

$psqlExe = New-Object System.Object
$psqlExe = [ref] ''
$pgCtlExe = New-Object System.Object
$pgCtlExe = [ref] ''
Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe) -pgCtlExe ([ref]$pgCtlExe)
$psqlExe = $psqlExe.Value
$pgCtlExe = $pgCtlExe.Value

Write-Host "==> Felix Database Setup" -ForegroundColor Cyan
Write-Host ""

# Ensure we resolved a psql executable earlier
if (-not $psqlExe) {
    Write-Host "ERROR: psql command not found." -ForegroundColor Red
    Write-Host "Please ensure PostgreSQL is installed and psql is in your PATH, or pass -PgBin 'C:\\Program Files\\PostgreSQL\\18\\bin' to this script." -ForegroundColor Yellow
    exit 1
}

# Check if PostgreSQL server is running
Write-Host "==> Checking PostgreSQL server..." -ForegroundColor Cyan
try {
    if ($env:DATABASE_URL) {
        $version = & $psqlExe -d $env:DATABASE_URL -c "SELECT version();" 2>&1
    }
    else {
        $version = & $psqlExe -U $POSTGRES_USER -c "SELECT version();" 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL connection failed"
    }
    Write-Host "[OK] PostgreSQL server is running" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Cannot connect to PostgreSQL server." -ForegroundColor Red
    Write-Host "Please ensure PostgreSQL is running on localhost:5432 or specify -DataDir/PGDATA to point to your data directory." -ForegroundColor Yellow
    if ($pgCtlExe) {
        $dd = $DataDir -or '<PGDATA path>'
        Write-Host "Start it with: $pgCtlExe -D $dd start" -ForegroundColor Yellow
    }
    else {
        Write-Host "Start it with your system service manager (e.g. 'net start postgresql' or via the Postgres installer shortcuts)." -ForegroundColor Yellow
    }
    exit 1
}

# Handle --Force flag: drop and recreate database
if ($Force) {
    Write-Host ""
    Write-Host "==> Force mode: Dropping database..." -ForegroundColor Yellow
    Write-Host "WARNING: This will destroy all data in the $DATABASE_NAME database!" -ForegroundColor Yellow
    $confirm = Read-Host "Type 'yes' to continue"
    
    if ($confirm -ne "yes") {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
    
    # Disconnect all clients
    & $psqlExe -U $POSTGRES_USER -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DATABASE_NAME';" 2>&1 | Out-Null
    
    # Drop database
    & $psqlExe -U $POSTGRES_USER -c "DROP DATABASE IF EXISTS $DATABASE_NAME;" 2>&1 | Out-Null
    Write-Host "[OK] Database dropped" -ForegroundColor Green
}

# Create database if it doesn't exist
Write-Host ""
Write-Host "==> Creating database (if not exists)..." -ForegroundColor Cyan
$dbExists = & $psqlExe -U $POSTGRES_USER -tAc "SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME';" 2>&1

if ($dbExists -eq "1") {
    Write-Host "[OK] Database '$DATABASE_NAME' already exists" -ForegroundColor Green
}
else {
    & $psqlExe -U $POSTGRES_USER -c "CREATE DATABASE $DATABASE_NAME;" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Database '$DATABASE_NAME' created" -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: Failed to create database" -ForegroundColor Red
        exit 1
    }
}

# Create schema_migrations table if it doesn't exist
Write-Host ""
Write-Host "==> Ensuring schema_migrations table exists..." -ForegroundColor Cyan
$createMigrationsTable = @"
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"@

& $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -c $createMigrationsTable 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] schema_migrations table ready" -ForegroundColor Green
}
else {
    Write-Host "ERROR: Failed to create schema_migrations table" -ForegroundColor Red
    exit 1
}

# Get list of applied migrations
$appliedMigrations = & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -tAc "SELECT version FROM schema_migrations ORDER BY version;" 2>&1
$appliedSet = @{}
if ($appliedMigrations) {
    $appliedMigrations -split "`n" | Where-Object { $_ } | ForEach-Object { $appliedSet[$_.Trim()] = $true }
}

Write-Host "[OK] Found $($appliedSet.Count) applied migration(s)" -ForegroundColor Green

# Get list of migration files
Write-Host ""
Write-Host "==> Scanning for migration files..." -ForegroundColor Cyan

if (-not (Test-Path $MIGRATIONS_DIR)) {
    Write-Host "ERROR: Migrations directory not found: $MIGRATIONS_DIR" -ForegroundColor Red
    exit 1
}

$migrationFiles = Get-ChildItem "$MIGRATIONS_DIR/*.sql" | Where-Object { $_.Name -match '^\d{3}_.*\.sql$' } | Sort-Object Name

if ($migrationFiles.Count -eq 0) {
    Write-Host "ERROR: No migration files found in $MIGRATIONS_DIR" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Found $($migrationFiles.Count) migration file(s)" -ForegroundColor Green

# Apply pending migrations
Write-Host ""
Write-Host "==> Applying migrations..." -ForegroundColor Cyan

$appliedCount = 0
foreach ($file in $migrationFiles) {
    $version = $file.Name
    
    if ($appliedSet.ContainsKey($version)) {
        Write-Host "  [-] $version (already applied)" -ForegroundColor Gray
        continue
    }
    
    Write-Host "  [+] Applying $version..." -ForegroundColor Cyan
    
    # Run the migration
    & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -f $file.FullName 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ERROR: Migration failed!" -ForegroundColor Red
        exit 1
    }
    
    # Record migration in schema_migrations table
    $insertSql = "INSERT INTO schema_migrations (version) VALUES ('$version');"
    & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -c $insertSql 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ERROR: Failed to record migration!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  [OK] $version applied" -ForegroundColor Green
    $appliedCount++
}

if ($appliedCount -eq 0) {
    Write-Host "[OK] All migrations up to date" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "[OK] Applied $appliedCount new migration(s)" -ForegroundColor Green
}

# Verify schema
Write-Host ""
Write-Host "==> Verifying database schema..." -ForegroundColor Cyan

$tables = & $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME -tAc "\dt" 2>&1 | Select-String -Pattern "^\s*public\s+\|\s+(\w+)" | ForEach-Object { $_.Matches.Groups[1].Value }

$expectedTables = @("organizations", "organization_members", "projects", "requirements", "agents", "agent_states", "runs", "run_artifacts")
$missingTables = $expectedTables | Where-Object { $_ -notin $tables }

if ($missingTables.Count -gt 0) {
    Write-Host "WARNING: Some expected tables are missing:" -ForegroundColor Yellow
    $missingTables | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
else {
    Write-Host "[OK] All expected tables exist" -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Database setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Connection string:" -ForegroundColor Cyan
Write-Host "  postgresql://$POSTGRES_USER@localhost:5432/$DATABASE_NAME" -ForegroundColor White
Write-Host ""
Write-Host "To verify manually:" -ForegroundColor Cyan
if ($psqlExe) {
    Write-Host "  $psqlExe -U $POSTGRES_USER -d $DATABASE_NAME" -ForegroundColor White
}
else {
    Write-Host "  psql -U $POSTGRES_USER -d $DATABASE_NAME" -ForegroundColor White
}
Write-Host ""

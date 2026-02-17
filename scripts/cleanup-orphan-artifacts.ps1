<#
.SYNOPSIS
    Clean up orphaned artifacts from storage that are not referenced in the database.

.DESCRIPTION
    This script identifies and removes artifact files in storage that don't have
    corresponding records in the run_files database table. This can happen when:
    - Runs are deleted from the database but storage cleanup fails
    - Storage uploads succeed but database insert fails
    - Manual database modifications
    
    The script operates in two modes:
    - DryRun (default): Lists orphaned files without deleting
    - Delete: Actually removes the orphaned files

.PARAMETER PgBin
    Path to PostgreSQL bin directory (optional - can also use PG_BIN env var)

.PARAMETER StoragePath
    Path to artifact storage directory (default: ./artifacts relative to backend)

.PARAMETER DryRun
    If specified, only lists orphaned files without deleting them (default behavior)

.PARAMETER Force
    Skip confirmation prompts when deleting

.PARAMETER DatabaseName
    Database name (default: felix)

.PARAMETER Verbose
    Show detailed progress information

.EXAMPLE
    .\scripts\cleanup-orphan-artifacts.ps1
    # Preview orphaned files (dry run)

.EXAMPLE
    .\scripts\cleanup-orphan-artifacts.ps1 -Force
    # Actually delete orphaned files without confirmation

.EXAMPLE
    .\scripts\cleanup-orphan-artifacts.ps1 -StoragePath "D:\felix-storage" -DryRun
    # Check specific storage path

.NOTES
    This script requires:
    - psql (PostgreSQL client) in PATH or specified via -PgBin
    - Access to the Felix database
    - Read/write access to the storage directory
#>

param(
    [string]$PgBin,
    [string]$StoragePath,
    [switch]$DryRun = $true,
    [switch]$Force,
    [string]$DatabaseName = "felix"
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Orphan Artifact Cleanup" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

# Allow overriding via environment variables
if (-not $PgBin) { $PgBin = $env:PG_BIN }
$POSTGRES_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'postgres' }

# Set default storage path (relative to backend directory)
if (-not $StoragePath) {
    $BackendPath = Join-Path $PSScriptRoot "..\app\backend"
    $StoragePath = Join-Path $BackendPath "artifacts"
}

# Resolve to absolute path
$StoragePath = [System.IO.Path]::GetFullPath($StoragePath)

# If -Force is specified without explicit -DryRun:$false, switch to delete mode
if ($Force -and $DryRun) {
    $DryRun = $false
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Storage Path: $StoragePath" -ForegroundColor Gray
Write-Host "  Database: $DatabaseName" -ForegroundColor Gray
Write-Host "  Mode: $(if ($DryRun) { 'Dry Run (preview only)' } else { 'Delete' })" -ForegroundColor Gray
Write-Host ""

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

function Get-StorageKeys {
    <#
    .SYNOPSIS
        Recursively get all storage keys from the storage directory.
    #>
    param([string]$BasePath)
    
    $keys = @()
    
    if (-not (Test-Path $BasePath)) {
        return $keys
    }
    
    # Get all files under runs/ directory
    $runsPath = Join-Path $BasePath "runs"
    if (Test-Path $runsPath) {
        $files = Get-ChildItem -Path $runsPath -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            # Convert absolute path to relative storage key
            $relativePath = $file.FullName.Substring($BasePath.Length).TrimStart('\', '/')
            $keys += $relativePath.Replace('\', '/')
        }
    }
    
    return $keys
}

function Get-DatabaseStorageKeys {
    <#
    .SYNOPSIS
        Get all storage keys from the run_files database table.
    #>
    param(
        [string]$PsqlExe,
        [string]$Database,
        [string]$User
    )
    
    $query = "SELECT storage_key FROM run_files WHERE storage_key IS NOT NULL;"
    $result = & $PsqlExe -U $User -d $Database -tAc $query 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query database: $result"
    }
    
    # Parse result - each line is a storage key
    $keys = @()
    foreach ($line in $result) {
        $trimmed = $line.Trim()
        if ($trimmed) {
            $keys += $trimmed
        }
    }
    
    return $keys
}

# =============================================================================
# VALIDATION
# =============================================================================

Write-Host "Step 1: Validating environment..." -ForegroundColor Yellow

# Check storage path exists
if (-not (Test-Path $StoragePath)) {
    Write-Host "  [ERROR] Storage path does not exist: $StoragePath" -ForegroundColor Red
    exit 1
}

$runsPath = Join-Path $StoragePath "runs"
if (-not (Test-Path $runsPath)) {
    Write-Host "  [INFO] No runs/ directory found in storage - nothing to clean up" -ForegroundColor Gray
    exit 0
}

# Find psql
$psqlExe = ''
Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe)

if (-not $psqlExe) {
    Write-Host "  [ERROR] psql not found. Install PostgreSQL client or specify -PgBin parameter." -ForegroundColor Red
    exit 1
}

Write-Host "  [OK] Using psql: $psqlExe" -ForegroundColor Green

# Check database exists
$dbExists = & $psqlExe -U $POSTGRES_USER -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DatabaseName';" 2>&1
if ($dbExists -ne "1") {
    Write-Host "  [ERROR] Database '$DatabaseName' does not exist" -ForegroundColor Red
    exit 1
}

Write-Host "  [OK] Database '$DatabaseName' found" -ForegroundColor Green

# =============================================================================
# STEP 2: COLLECT STORAGE KEYS
# =============================================================================

Write-Host ""
Write-Host "Step 2: Scanning storage directory..." -ForegroundColor Yellow

$storageKeys = Get-StorageKeys -BasePath $StoragePath
$storageKeyCount = $storageKeys.Count

Write-Host "  [OK] Found $storageKeyCount files in storage" -ForegroundColor Green

if ($storageKeyCount -eq 0) {
    Write-Host ""
    Write-Host "No artifact files found in storage. Nothing to clean up." -ForegroundColor Gray
    exit 0
}

# =============================================================================
# STEP 3: COLLECT DATABASE KEYS
# =============================================================================

Write-Host ""
Write-Host "Step 3: Querying database for valid storage keys..." -ForegroundColor Yellow

$dbKeys = Get-DatabaseStorageKeys -PsqlExe $psqlExe -Database $DatabaseName -User $POSTGRES_USER
$dbKeyCount = $dbKeys.Count

Write-Host "  [OK] Found $dbKeyCount storage keys in database" -ForegroundColor Green

# Create a hashset for fast lookup
$dbKeySet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $dbKeys) {
    [void]$dbKeySet.Add($key)
}

# =============================================================================
# STEP 4: IDENTIFY ORPHANS
# =============================================================================

Write-Host ""
Write-Host "Step 4: Identifying orphaned files..." -ForegroundColor Yellow

$orphanedKeys = @()
$orphanedSize = 0

foreach ($storageKey in $storageKeys) {
    if (-not $dbKeySet.Contains($storageKey)) {
        $orphanedKeys += $storageKey
        
        # Get file size
        $filePath = Join-Path $StoragePath $storageKey
        if (Test-Path $filePath) {
            $fileInfo = Get-Item $filePath
            $orphanedSize += $fileInfo.Length
        }
    }
}

$orphanCount = $orphanedKeys.Count
$orphanSizeMB = [math]::Round($orphanedSize / 1MB, 2)

if ($orphanCount -eq 0) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host "   No orphaned artifacts found!" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "All $storageKeyCount storage files have valid database references." -ForegroundColor Gray
    exit 0
}

Write-Host "  [FOUND] $orphanCount orphaned files ($orphanSizeMB MB)" -ForegroundColor Yellow

# =============================================================================
# STEP 5: DISPLAY ORPHANS
# =============================================================================

Write-Host ""
Write-Host "Orphaned files:" -ForegroundColor Yellow

$maxDisplay = 50
$displayed = 0

foreach ($key in $orphanedKeys) {
    if ($displayed -ge $maxDisplay) {
        $remaining = $orphanCount - $maxDisplay
        Write-Host "  ... and $remaining more files" -ForegroundColor Gray
        break
    }
    
    $filePath = Join-Path $StoragePath $key
    if (Test-Path $filePath) {
        $fileInfo = Get-Item $filePath
        $sizeKB = [math]::Round($fileInfo.Length / 1KB, 1)
        Write-Host "  - $key ($sizeKB KB)" -ForegroundColor Gray
    } else {
        Write-Host "  - $key (missing)" -ForegroundColor DarkGray
    }
    
    $displayed++
}

# =============================================================================
# STEP 6: DELETE OR DRY RUN
# =============================================================================

Write-Host ""

if ($DryRun) {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "   Dry Run Complete" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Found $orphanCount orphaned files ($orphanSizeMB MB) that would be deleted." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To actually delete these files, run:" -ForegroundColor Gray
    Write-Host "  .\scripts\cleanup-orphan-artifacts.ps1 -Force" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Confirmation prompt (unless -Force specified)
if (-not $Force) {
    Write-Host "WARNING: About to delete $orphanCount files ($orphanSizeMB MB)" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Type 'DELETE' to confirm"
    if ($confirm -ne "DELETE") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

Write-Host "Step 6: Deleting orphaned files..." -ForegroundColor Yellow

$deletedCount = 0
$failedCount = 0
$deletedSize = 0

foreach ($key in $orphanedKeys) {
    $filePath = Join-Path $StoragePath $key
    
    try {
        if (Test-Path $filePath) {
            $fileInfo = Get-Item $filePath
            $fileSize = $fileInfo.Length
            
            Remove-Item -Path $filePath -Force -ErrorAction Stop
            
            $deletedCount++
            $deletedSize += $fileSize
            
            if ($deletedCount % 100 -eq 0) {
                Write-Host "  Deleted $deletedCount files..." -ForegroundColor Gray
            }
        }
    }
    catch {
        $failedCount++
        Write-Host "  [WARN] Failed to delete: $key - $_" -ForegroundColor Yellow
    }
}

# Clean up empty directories
Write-Host ""
Write-Host "Step 7: Cleaning empty directories..." -ForegroundColor Yellow

$dirsRemoved = 0
$runsPath = Join-Path $StoragePath "runs"
if (Test-Path $runsPath) {
    # Get all directories, sorted by depth (deepest first)
    $dirs = Get-ChildItem -Path $runsPath -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending
    
    foreach ($dir in $dirs) {
        $items = Get-ChildItem -Path $dir.FullName -Force -ErrorAction SilentlyContinue
        if (($items | Measure-Object).Count -eq 0) {
            try {
                Remove-Item -Path $dir.FullName -Force -ErrorAction Stop
                $dirsRemoved++
            }
            catch {
                # Ignore errors removing directories
            }
        }
    }
}

Write-Host "  [OK] Removed $dirsRemoved empty directories" -ForegroundColor Green

# =============================================================================
# SUMMARY
# =============================================================================

$deletedSizeMB = [math]::Round($deletedSize / 1MB, 2)

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "   Cleanup Complete" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "  Files deleted: $deletedCount" -ForegroundColor Gray
Write-Host "  Space freed: $deletedSizeMB MB" -ForegroundColor Gray
Write-Host "  Directories removed: $dirsRemoved" -ForegroundColor Gray

if ($failedCount -gt 0) {
    Write-Host "  Failed deletions: $failedCount" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host ""
exit 0

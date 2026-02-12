<#
.SYNOPSIS
    Migrates requirements from .felix/requirements.json into the database.

.DESCRIPTION
    Reads requirements.json, strips "S-XXXX: " from titles, inserts:
    - requirements (code column set to S-XXXX)
    - requirement_versions (history)
    - requirement_content (current snapshot)
    - requirement_dependencies (join table)

.PARAMETER ProjectId
    Project UUID to associate requirements with.

.PARAMETER RequirementsPath
    Path to requirements.json (default: .felix/requirements.json).

.PARAMETER PgBin
    Optional PostgreSQL bin path (psql.exe location).

.PARAMETER DatabaseUrl
    Optional DATABASE_URL override (otherwise uses env:DATABASE_URL or localhost).

.PARAMETER Help
    Show help for this script and exit.
.PARAMETER DryRun
    Show a summary and the generated SQL without executing it.

.EXAMPLE
    .\scripts\migrate-requirements.ps1 -ProjectId "00000000-0000-0000-0000-000000000001"
#>

param(
    [string]$ProjectId,
    [string]$RequirementsPath = ".felix/requirements.json",
    [string]$PgBin,
    [string]$DatabaseUrl,
    [switch]$Help,
    [switch]$DryRun
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$ErrorActionPreference = "Stop"

if (-not $ProjectId) {
    $defaultProjectId = "00000000-0000-0000-0000-000000000001"
    $inputProjectId = Read-Host "Enter ProjectId (press Enter for $defaultProjectId)"
    $ProjectId = if ([string]::IsNullOrWhiteSpace($inputProjectId)) {
        $defaultProjectId
    } else {
        $inputProjectId
    }
}

function Resolve-PostgresTools {
    param($pgBin, [ref]$psqlExe)

    if ($pgBin) {
        $candidatePsql = Join-Path -Path $pgBin -ChildPath 'psql.exe'
        if (Test-Path $candidatePsql) {
            $psqlExe.Value = $candidatePsql
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
}

function SqlLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return "NULL" }
    $escaped = $Value -replace "'", "''"
    return "'$escaped'"
}

function SqlJsonLiteral {
    param($Value)
    $json = $Value | ConvertTo-Json -Compress
    return SqlLiteral $json
}

if (-not (Test-Path $RequirementsPath)) {
    throw "requirements.json not found at $RequirementsPath"
}

$requirementsData = Get-Content -Raw $RequirementsPath | ConvertFrom-Json
if (-not $requirementsData.requirements) {
    throw "Invalid requirements.json: missing requirements array."
}

$psqlExe = ''
Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe)
if (-not $psqlExe) {
    throw "psql command not found. Install PostgreSQL or pass -PgBin."
}

$dbUrl = if ($DatabaseUrl) { $DatabaseUrl } elseif ($env:DATABASE_URL) { $env:DATABASE_URL } else { $null }

$mapping = @{}
$insertStatements = New-Object System.Collections.Generic.List[string]

$insertStatements.Add("BEGIN;")

foreach ($req in $requirementsData.requirements) {
    $code = $req.id
    $title = $req.title
    $codePattern = [regex]::Escape($code)
    if ($title -match ("^" + $codePattern + ":\s*(.+)$")) {
        $title = $Matches[1]
    }

    $reqId = [guid]::NewGuid().ToString()
    $verId = [guid]::NewGuid().ToString()
    $mapping[$code] = @{ id = $reqId; version = $verId }

    $meta = @{
        tags = $req.tags
    }
    if ($null -ne $req.commit_on_complete) {
        $meta.commit_on_complete = $req.commit_on_complete
    }

    $updatedAt = if ($req.updated_at) { "$($req.updated_at)T00:00:00Z" } else { $null }

    $insertStatements.Add((
        "INSERT INTO requirements (id, project_id, code, title, spec_path, status, priority, metadata, created_at, updated_at) VALUES " +
        "({0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, NOW(), {8});" -f
        (SqlLiteral $reqId),
        (SqlLiteral $ProjectId),
        (SqlLiteral $code),
        (SqlLiteral $title),
        (SqlLiteral $req.spec_path),
        (SqlLiteral $req.status),
        (SqlLiteral $req.priority),
        (SqlJsonLiteral $meta),
        ($(if ($updatedAt) { SqlLiteral $updatedAt } else { "NOW()" }))
    ))

    $specPath = $req.spec_path
    $specContent = ""
    if ($specPath -and (Test-Path $specPath)) {
        $specContent = Get-Content -Raw $specPath
    }

    $insertStatements.Add((
        "INSERT INTO requirement_versions (id, requirement_id, content, created_at, author_id, source, diff_from_id) VALUES " +
        "({0}, {1}, {2}, {3}, NULL, 'migration', NULL);" -f
        (SqlLiteral $verId),
        (SqlLiteral $reqId),
        (SqlLiteral $specContent),
        ($(if ($updatedAt) { SqlLiteral $updatedAt } else { "NOW()" }))
    ))

    $insertStatements.Add((
        "INSERT INTO requirement_content (id, requirement_id, content, current_version_id, updated_at) VALUES " +
        "(gen_random_uuid(), {0}, {1}, {2}, {3});" -f
        (SqlLiteral $reqId),
        (SqlLiteral $specContent),
        (SqlLiteral $verId),
        ($(if ($updatedAt) { SqlLiteral $updatedAt } else { "NOW()" }))
    ))
}

foreach ($req in $requirementsData.requirements) {
    $code = $req.id
    $reqMap = $mapping[$code]
    if (-not $reqMap) { continue }

    foreach ($depCode in ($req.depends_on | ForEach-Object { $_ })) {
        $depMap = $mapping[$depCode]
        if (-not $depMap) {
            Write-Warning "Missing dependency code $depCode for requirement $code"
            continue
        }
        $insertStatements.Add((
            "INSERT INTO requirement_dependencies (requirement_id, depends_on_id, created_at) VALUES ({0}, {1}, NOW()) ON CONFLICT DO NOTHING;" -f
            (SqlLiteral $reqMap.id),
            (SqlLiteral $depMap.id)
        ))
    }
}

$insertStatements.Add("COMMIT;")

$tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
$insertStatements -join "`n" | Set-Content -Path $tempSql -Encoding UTF8

if ($DryRun) {
    Write-Host "[DRY RUN] Requirements parsed: $($requirementsData.requirements.Count)" -ForegroundColor Yellow
    Write-Host "[DRY RUN] Dependencies rows: $($insertStatements.Count - $requirementsData.requirements.Count * 3 - 2)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "---- SQL Preview (first 40 lines) ----" -ForegroundColor Yellow
    $preview = Get-Content -Path $tempSql | Select-Object -First 40
    $preview | ForEach-Object { Write-Host $_ }
    Write-Host "-------------------------------------" -ForegroundColor Yellow
    Remove-Item -Path $tempSql -Force -ErrorAction SilentlyContinue
    exit 0
}

try {
    if ($dbUrl) {
        & $psqlExe -d $dbUrl -f $tempSql | Out-Null
    }
    else {
        & $psqlExe -U postgres -d felix -f $tempSql | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Migration failed. See psql output for details."
    }
    Write-Host "[OK] Requirements migrated successfully." -ForegroundColor Green
}
finally {
    Remove-Item -Path $tempSql -Force -ErrorAction SilentlyContinue
}

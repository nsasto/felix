<#
.SYNOPSIS
    Seeds the agents table with a small set of default agents.

.DESCRIPTION
    Inserts three sci-fi named agents into the agents table for a project.
    Adds machine hostname to metadata as the source (current machine).
    Skips rows when an agent with the same project_id and name already exists.

.PARAMETER ProjectId
    Project UUID to associate agents with (default: 00000000-0000-0000-0000-000000000001).

.PARAMETER PgBin
    Optional PostgreSQL bin path (psql.exe location).

.PARAMETER DatabaseUrl
    Optional DATABASE_URL override (otherwise uses env:DATABASE_URL or localhost).

.PARAMETER Source
    Source label stored in agent metadata (default: migrate_agents.ps1).

.PARAMETER Help
    Show help for this script and exit.

.PARAMETER DryRun
    Show a summary and the generated SQL without executing it.

.EXAMPLE
    .\scripts\migrate-agents.ps1
#>

param(
    [string]$ProjectId = "00000000-0000-0000-0000-000000000001",
    [string]$OrgId = "00000000-0000-0000-0000-000000000001",
    [string]$PgBin,
    [string]$DatabaseUrl,
    [string]$Source = "migrate_agents.ps1",
    [switch]$Help,
    [switch]$DryRun
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$ErrorActionPreference = "Stop"

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
    if ($null -eq $Value) { return "NULL" }
    $json = $Value | ConvertTo-Json -Compress
    return SqlLiteral $json
}

$psqlExe = ''
Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe)
if (-not $psqlExe) {
    throw "psql command not found. Install PostgreSQL or pass -PgBin."
}

$dbUrl = if ($DatabaseUrl) { $DatabaseUrl } elseif ($env:DATABASE_URL) { $env:DATABASE_URL } else { $null }
$hostname = $env:COMPUTERNAME

$profileQuery = "SELECT id FROM agent_profiles WHERE org_id = $(SqlLiteral $OrgId) AND (adapter = 'droid' OR executable = 'droid') ORDER BY created_at DESC LIMIT 1;"
$profileId = if ($dbUrl) {
    & $psqlExe -d $dbUrl -t -A -c $profileQuery
} else {
    & $psqlExe -U postgres -d felix -t -A -c $profileQuery
}

if (-not $profileId) {
    throw "No droid agent profile found for org $OrgId. Create a droid profile before seeding agents."
}

$agents = @(
    @{ name = "Andromeda"; type = "ralph" },
    @{ name = "Serenity"; type = "ralph" },
    @{ name = "Galactica"; type = "ralph" }
)

$insertStatements = New-Object System.Collections.Generic.List[string]
$insertStatements.Add("BEGIN;")

foreach ($agent in $agents) {
    $metadata = @{
        source = $Source
        machine = @{
            hostname = $hostname
        }
        seeded = $true
    }

    $sqlTemplate = @"
INSERT INTO agents (id, project_id, name, type, status, heartbeat_at, metadata, profile_id, created_at, updated_at)
SELECT gen_random_uuid(), {0}, {1}, {2}, 'idle', NULL, {3}, {4}, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM agents WHERE project_id = {0} AND name = {1}
);
"@

    $insertStatements.Add(($sqlTemplate -f
        (SqlLiteral $ProjectId),
        (SqlLiteral $agent.name),
        (SqlLiteral $agent.type),
        (SqlJsonLiteral $metadata),
        (SqlLiteral $profileId.Trim())
    ))
}

$insertStatements.Add("COMMIT;")

$tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
$insertStatements -join "`n" | Set-Content -Path $tempSql -Encoding UTF8

if ($DryRun) {
    Write-Host "[DRY RUN] Agents to seed: $($agents.Count)" -ForegroundColor Yellow
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
    Write-Host "[OK] Agents seeded successfully." -ForegroundColor Green
}
finally {
    Remove-Item -Path $tempSql -Force -ErrorAction SilentlyContinue
}

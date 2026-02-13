<#
.SYNOPSIS
    Migrates agent profiles from .felix/agents.json into the database.

.DESCRIPTION
    Reads agents.json and inserts rows into agent_profiles for the given org.
    Skips rows when a profile with the same org_id, name, and adapter already exists.

.PARAMETER OrgId
    Organization UUID to associate profiles with.

.PARAMETER AgentsPath
    Path to agents.json (default: .felix/agents.json).

.PARAMETER PgBin
    Optional PostgreSQL bin path (psql.exe location).

.PARAMETER DatabaseUrl
    Optional DATABASE_URL override (otherwise uses env:DATABASE_URL or localhost).

.PARAMETER Source
    Source label stored in agent_profiles.source (default: repo).

.PARAMETER Help
    Show help for this script and exit.

.PARAMETER DryRun
    Show a summary and the generated SQL without executing it.

.EXAMPLE
    .\scripts\migrate-agent-profiles.ps1 -OrgId "00000000-0000-0000-0000-000000000001"
#>

param(
    [string]$OrgId,
    [string]$AgentsPath = ".felix/agents.json",
    [string]$PgBin,
    [string]$DatabaseUrl,
    [string]$Source = "repo",
    [switch]$Help,
    [switch]$DryRun
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$ErrorActionPreference = "Stop"

if (-not $OrgId) {
    $defaultOrgId = "00000000-0000-0000-0000-000000000001"
    $inputOrgId = Read-Host "Enter OrgId (press Enter for $defaultOrgId)"
    $OrgId = if ([string]::IsNullOrWhiteSpace($inputOrgId)) {
        $defaultOrgId
    } else {
        $inputOrgId
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
    if ($null -eq $Value) { return "NULL" }
    $json = $Value | ConvertTo-Json -Compress
    return SqlLiteral $json
}

if (-not (Test-Path $AgentsPath)) {
    throw "agents.json not found at $AgentsPath"
}

$agentsData = Get-Content -Raw $AgentsPath | ConvertFrom-Json
if (-not $agentsData.agents) {
    throw "Invalid agents.json: missing agents array."
}

$psqlExe = ''
Resolve-PostgresTools -pgBin $PgBin -psqlExe ([ref]$psqlExe)
if (-not $psqlExe) {
    throw "psql command not found. Install PostgreSQL or pass -PgBin."
}

$dbUrl = if ($DatabaseUrl) { $DatabaseUrl } elseif ($env:DATABASE_URL) { $env:DATABASE_URL } else { $null }

$insertStatements = New-Object System.Collections.Generic.List[string]
$insertStatements.Add("BEGIN;")

foreach ($agent in $agentsData.agents) {
    $name = $agent.name
    $adapter = if ($agent.adapter) { $agent.adapter } elseif ($agent.name) { $agent.name } else { "droid" }
    $executable = if ($agent.executable) { $agent.executable } else { $adapter }
    $args = if ($agent.PSObject.Properties.Name -contains "args") { $agent.args } else { $null }
    $model = if ($agent.model) { $agent.model } else { $null }
    $workingDir = if ($agent.working_directory) { $agent.working_directory } else { $null }
    $environment = if ($agent.environment) { $agent.environment } else { @{} }
    $description = if ($agent.description) { $agent.description } else { $null }

    $sqlTemplate = @"
INSERT INTO agent_profiles (id, org_id, name, adapter, executable, args, model, working_directory, environment, description, source, created_at, updated_at)
SELECT gen_random_uuid(), {0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8}, {9}, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM agent_profiles WHERE org_id = {0} AND name = {1} AND adapter = {2}
);
"@
    $insertStatements.Add(($sqlTemplate -f
        (SqlLiteral $OrgId),
        (SqlLiteral $name),
        (SqlLiteral $adapter),
        (SqlLiteral $executable),
        (SqlJsonLiteral $args),
        (SqlLiteral $model),
        (SqlLiteral $workingDir),
        (SqlJsonLiteral $environment),
        (SqlLiteral $description),
        (SqlLiteral $Source)
    ))
}

$insertStatements.Add("COMMIT;")

$tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
$insertStatements -join "`n" | Set-Content -Path $tempSql -Encoding UTF8

if ($DryRun) {
    Write-Host "[DRY RUN] Profiles parsed: $($agentsData.agents.Count)" -ForegroundColor Yellow
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
    Write-Host "[OK] Agent profiles migrated successfully." -ForegroundColor Green
}
finally {
    Remove-Item -Path $tempSql -Force -ErrorAction SilentlyContinue
}

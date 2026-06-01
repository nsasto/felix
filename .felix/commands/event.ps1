<#
.SYNOPSIS
felix event  -  query the Felix Event Bus (Phase AS2).

.DESCRIPTION
Subcommands: tail, query
Reads from .felix/events.jsonl (and rotated archives).
#>

function Invoke-Event {
    param(
        [string[]]$Args,
        [string]$RepoRoot = (Get-Location).Path,
        [string]$FelixRoot = $PSScriptRoot
    )

    $subCmd = if ($Args.Count -gt 0) { $Args[0] } else { "tail" }
    $subArgs = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }

    $eventsPath = Join-Path $RepoRoot ".felix\events.jsonl"

    switch ($subCmd) {
        "tail" {
            $kind  = $null
            $runId = $null
            $since = $null

            for ($i = 0; $i -lt $subArgs.Count; $i++) {
                switch ($subArgs[$i]) {
                    "--kind"   { $kind  = $subArgs[++$i] }
                    "--run-id" { $runId = $subArgs[++$i] }
                    "--since"  { $since = $subArgs[++$i] }
                }
            }

            Invoke-EventTail -EventsPath $eventsPath -Kind $kind -RunId $runId -Since $since
        }
        "query" {
            $expr = if ($subArgs.Count -gt 0) { $subArgs[0] } else { "" }
            Invoke-EventQuery -EventsPath $eventsPath -Expression $expr
        }
        default {
            Write-Host "Unknown event subcommand: $subCmd" -ForegroundColor Red
            Write-Host "Valid: tail, query" -ForegroundColor Gray
            exit 1
        }
    }
}

function Get-EventLines {
    param([string]$EventsPath)

    if (-not (Test-Path $EventsPath)) {
        return @()
    }
    return Get-Content $EventsPath -ErrorAction SilentlyContinue
}

function Parse-SinceArg {
    param([string]$Since)
    if (-not $Since) { return $null }
    $unit  = $Since[-1]
    $value = [int]($Since.Substring(0, $Since.Length - 1))
    $now   = [datetime]::UtcNow
    switch ($unit) {
        "m" { return $now.AddMinutes(-$value) }
        "h" { return $now.AddHours(-$value) }
        "d" { return $now.AddDays(-$value) }
        default { return $null }
    }
}

function Invoke-EventTail {
    param(
        [string]$EventsPath,
        [string]$Kind  = $null,
        [string]$RunId = $null,
        [string]$Since = $null
    )

    $lines  = Get-EventLines -EventsPath $EventsPath
    $cutoff = Parse-SinceArg -Since $Since

    $matched = 0
    foreach ($line in $lines) {
        if (-not $line.Trim()) { continue }
        try {
            $ev = $line | ConvertFrom-Json

            # Apply filters
            if ($Kind  -and $ev.type  -ne $Kind  -and $ev.data.kind -ne $Kind) { continue }
            if ($RunId -and $ev.run_id -ne $RunId) { continue }
            if ($cutoff) {
                $ts = [datetime]::Parse($(if ($ev.ts) { $ev.ts } else { $ev.timestamp }))
                if ($ts -lt $cutoff) { continue }
            }

            Write-Host $line
            $matched++
        } catch { continue }
    }

    if ($matched -eq 0) {
        Write-Host "(no matching events)" -ForegroundColor Gray
    }
}

function Invoke-EventQuery {
    param([string]$EventsPath, [string]$Expression)

    $lines = Get-EventLines -EventsPath $EventsPath

    foreach ($line in $lines) {
        if (-not $line.Trim()) { continue }
        try {
            $ev = $line | ConvertFrom-Json

            if ($Expression) {
                # Simple field=value filter: "type=log" or "run_id=S-0001"
                $parts = $Expression -split "="
                if ($parts.Count -eq 2) {
                    $field = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    $actual = $ev.$field
                    if (-not $actual -or $actual -notmatch $value) { continue }
                }
            }
            Write-Host $line
        } catch { continue }
    }
}

<#
.SYNOPSIS
felix gc  -  disk pressure cleanup (Phase F8).

.DESCRIPTION
Exposes Invoke-Gc for felix.ps1 dispatch.
Prunes:
  - runs/ older than gc.retention_days (default 30), keeping the last-success run per requirement
  - .felix/events-*.jsonl rotations beyond events.retention_days
  - .felix/worktrees/<run-id>/ orphaned (no entry in .felix/sessions.json)

Flags:
  --dry-run   Show what would be pruned without deleting
  --yes       Skip interactive confirmation for destructive paths
#>

function Invoke-Gc {
    param(
        [string[]]$CmdArgs = @(),
        [string]$ProjectPath = (Get-Location).Path
    )

    $felixDir = Join-Path $ProjectPath ".felix"
    $runsDir  = Join-Path $ProjectPath "runs"

    $dryRun = $CmdArgs -icontains "--dry-run"
    $yes    = $CmdArgs -icontains "--yes"

    # Load config for retention settings
    $configFile = Join-Path $felixDir "config.json"
    $runsRetention   = 30
    $eventsRetention = 30
    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($cfg.gc) {
                if ($cfg.gc.retention_days)        { $runsRetention   = [int]$cfg.gc.retention_days }
                if ($cfg.gc.events_retention_days) { $eventsRetention = [int]$cfg.gc.events_retention_days }
            }
        } catch {}
    }

    $cutoff       = (Get-Date).AddDays(-$runsRetention)
    $eventsCutoff = (Get-Date).AddDays(-$eventsRetention)

    $totalDeleted   = 0
    $totalFreed     = 0
    $reportLines    = [System.Collections.ArrayList]@()

    function Add-Report { param([string]$Line) [void]$reportLines.Add($Line) }

    Write-Host ""
    Write-Host "felix gc" -ForegroundColor Cyan
    if ($dryRun) { Write-Host "(dry-run mode - no files will be deleted)" -ForegroundColor Yellow }
    Write-Host ""

    # ?? 1. Prune runs/ ???????????????????????????????????????????????????????
    if (Test-Path $runsDir) {
        # Find the last-success run per requirement to protect it
        $lastSuccess = @{}
        Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                # Run dirs are named like S-0001-20260101-120000-it1
                if ($_.Name -match '^([A-Z]+-\d+)-') {
                    $reqId = $Matches[1]
                    $stateFile = Join-Path $_.FullName "state.json"
                    if (-not $lastSuccess.ContainsKey($reqId)) {
                        $outcome = ""
                        if (Test-Path $stateFile) {
                            try { $outcome = (Get-Content $stateFile -Raw | ConvertFrom-Json).outcome } catch {}
                        }
                        if ($outcome -ieq "success" -or $outcome -ieq "complete") {
                            $lastSuccess[$reqId] = $_.Name
                        }
                    }
                }
            }

        $staleRuns = Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                if ($_.LastWriteTime -ge $cutoff) { return $false }
                # Protect last-success run per requirement
                if ($_.Name -match '^([A-Z]+-\d+)-') {
                    $reqId = $Matches[1]
                    if ($lastSuccess[$reqId] -eq $_.Name) { return $false }
                }
                return $true
            }

        $staleCount = @($staleRuns).Count
        if ($staleCount -gt 0) {
            Write-Host "runs/ older than $runsRetention days: $staleCount run dir(s)" -ForegroundColor White
            $staleBytes = 0
            foreach ($d in $staleRuns) {
                $sz = (Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                $staleBytes += $sz
                Add-Report "  runs/$($d.Name)  ($([math]::Round($sz/1KB,1)) KB)"
                Write-Host "  - $($d.Name)" -ForegroundColor Gray
            }
            $totalFreed += $staleBytes
            Write-Host "  Would free: $([math]::Round($staleBytes/1KB,1)) KB" -ForegroundColor Gray

            if (-not $dryRun) {
                $doDelete = $yes
                if (-not $doDelete) {
                    $confirm = Read-Host "Delete $staleCount run dir(s)? [y/N]"
                    $doDelete = ($confirm -match '^[yY]')
                }
                if ($doDelete) {
                    foreach ($d in $staleRuns) {
                        try { Remove-Item $d.FullName -Recurse -Force -ErrorAction Stop; $totalDeleted++ }
                        catch { Write-Host "  Failed to remove $($d.Name): $_" -ForegroundColor Red }
                    }
                    Write-Host "  Deleted $totalDeleted run dir(s)." -ForegroundColor Green
                } else {
                    Write-Host "  Skipped." -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "runs/: nothing to prune (retention: $runsRetention days)" -ForegroundColor Green
        }
    } else {
        Write-Host "runs/: directory not found" -ForegroundColor Gray
    }

    Write-Host ""

    # ?? 2. Prune events-*.jsonl rotations ???????????????????????????????????
    $eventRotations = Get-ChildItem -Path $felixDir -Filter "events-*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $eventsCutoff }

    $rotCount = @($eventRotations).Count
    if ($rotCount -gt 0) {
        $rotBytes = ($eventRotations | Measure-Object -Property Length -Sum).Sum
        Write-Host "events rotations older than $eventsRetention days: $rotCount file(s)" -ForegroundColor White
        foreach ($f in $eventRotations) { Write-Host "  - $($f.Name)" -ForegroundColor Gray }
        Write-Host "  Would free: $([math]::Round($rotBytes/1KB,1)) KB" -ForegroundColor Gray
        $totalFreed += $rotBytes

        if (-not $dryRun) {
            $doDelete = $yes
            if (-not $doDelete) {
                $confirm = Read-Host "Delete $rotCount event rotation(s)? [y/N]"
                $doDelete = ($confirm -match '^[yY]')
            }
            if ($doDelete) {
                foreach ($f in $eventRotations) {
                    try { Remove-Item $f.FullName -Force -ErrorAction Stop; $totalDeleted++ }
                    catch { Write-Host "  Failed: $($f.Name): $_" -ForegroundColor Red }
                }
                Write-Host "  Deleted $rotCount event file(s)." -ForegroundColor Green
            } else {
                Write-Host "  Skipped." -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "events rotations: nothing to prune" -ForegroundColor Green
    }

    Write-Host ""

    # ?? 3. Prune orphaned worktrees ??????????????????????????????????????????
    $worktreesDir  = Join-Path $felixDir "worktrees"
    $sessionsFile  = Join-Path $felixDir "sessions.json"
    if (Test-Path $worktreesDir) {
        $activeSessions = @()
        if (Test-Path $sessionsFile) {
            try {
                $sess = Get-Content $sessionsFile -Raw | ConvertFrom-Json
                $activeSessions = @($sess.sessions | ForEach-Object { $_.run_id } | Where-Object { $_ })
            } catch {}
        }

        $orphans = Get-ChildItem -Path $worktreesDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $activeSessions -notcontains $_.Name }

        $orphCount = @($orphans).Count
        if ($orphCount -gt 0) {
            Write-Host "Orphaned worktrees: $orphCount" -ForegroundColor White
            foreach ($d in $orphans) { Write-Host "  - $($d.Name)" -ForegroundColor Gray }

            if (-not $dryRun) {
                $doDelete = $yes
                if (-not $doDelete) {
                    $confirm = Read-Host "Delete $orphCount orphaned worktree(s)? [y/N]"
                    $doDelete = ($confirm -match '^[yY]')
                }
                if ($doDelete) {
                    foreach ($d in $orphans) {
                        try { Remove-Item $d.FullName -Recurse -Force -ErrorAction Stop; $totalDeleted++ }
                        catch { Write-Host "  Failed: $($d.Name): $_" -ForegroundColor Red }
                    }
                    Write-Host "  Deleted $orphCount worktree(s)." -ForegroundColor Green
                } else {
                    Write-Host "  Skipped." -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "Worktrees: none orphaned" -ForegroundColor Green
        }
    }

    Write-Host ""

    # ?? Summary ??????????????????????????????????????????????????????????????
    if ($dryRun) {
        Write-Host "[dry-run] Would free approximately $([math]::Round($totalFreed/1KB,1)) KB" -ForegroundColor Cyan
    } else {
        Write-Host "gc complete. Deleted $totalDeleted item(s)." -ForegroundColor Cyan
    }
    Write-Host ""
}

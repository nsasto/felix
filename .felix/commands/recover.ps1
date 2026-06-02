<#
.SYNOPSIS
felix run recover / felix recover - recover from crashed worker iterations (Phase H5).

.DESCRIPTION
Inspects orphaned leases, abandoned worktrees, and incomplete runs.
Presents a structured plan before any mutations; --yes to apply non-interactively.

Usage:
  felix recover [--run <run-id>] [--all] [--yes] [--dry-run]
  felix run recover [--run <run-id>] [--all] [--yes] [--dry-run]
#>

function Invoke-Recover {
    param(
        [string[]]$CmdArgs = @(),
        [string]$RepoRoot  = (Get-Location).Path
    )

    $runId   = $null
    $all     = $false
    $yes     = $false
    $dryRun  = $false

    for ($i = 0; $i -lt $CmdArgs.Count; $i++) {
        switch ($CmdArgs[$i]) {
            "--run"      { if ($i+1 -lt $CmdArgs.Count) { $runId  = $CmdArgs[++$i] } }
            "--all"      { $all     = $true }
            "--yes"      { $yes     = $true }
            "--dry-run"  { $dryRun  = $true }
            default {
                # Positional: treat as run-id if not a flag
                if (-not $CmdArgs[$i].StartsWith("--") -and -not $runId) { $runId = $CmdArgs[$i] }
            }
        }
    }

    if (-not $runId -and -not $all) {
        Write-Host ""
        Write-Host "Usage: felix recover [--run <run-id>] [--all] [--yes] [--dry-run]" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  --run <id>   Recover a specific run (by run-id in lease file)"
        Write-Host "  --all        Enumerate all orphaned runs and prompt per-run"
        Write-Host "  --yes        Apply without interactive confirmation"
        Write-Host "  --dry-run    Show plan but make no changes"
        Write-Host ""
        exit 0
    }

    . "$PSScriptRoot\..\core\lease-manager.ps1"
    . "$PSScriptRoot\..\core\worktree-manager.ps1"
    . "$PSScriptRoot\..\core\requirements-utils.ps1"

    $FelixDir = Join-Path $RepoRoot ".felix"
    $reqFile  = Join-Path $FelixDir "requirements.json"

    # Collect orphaned items
    $orphans = Find-OrphanedRuns -RepoRoot $RepoRoot

    if ($runId -and -not $all) {
        $orphans = $orphans | Where-Object { $_.run_id -eq $runId -or $_.requirement_id -eq $runId }
        if ($orphans.Count -eq 0) {
            Write-Host ""
            Write-Host "No orphaned run found for: $runId" -ForegroundColor Yellow
            Write-Host "Run 'felix recover --all' to list all orphaned runs." -ForegroundColor Gray
            Write-Host ""
            exit 0
        }
    }

    if ($orphans.Count -eq 0) {
        Write-Host ""
        Write-Host "No orphaned runs found. Everything looks clean." -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    Write-Host ""
    Write-Host "Orphaned runs found:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($o in $orphans) {
        Write-Host "  Run:         $($o.run_id)" -ForegroundColor White
        Write-Host "  Requirement: $($o.requirement_id)" -ForegroundColor Gray
        Write-Host "  Worker:      $($o.worker_id)" -ForegroundColor Gray
        Write-Host "  Claimed at:  $($o.claimed_at)" -ForegroundColor Gray
        if ($o.has_worktree) {
            Write-Host "  Worktree:    $($o.worktree_path)" -ForegroundColor Gray
        }
        Write-Host "  Issues:      $($o.issues -join ', ')" -ForegroundColor DarkYellow
        Write-Host ""
    }

    if ($dryRun) {
        Write-Host "[dry-run] Would recover $($orphans.Count) orphaned run(s)." -ForegroundColor Cyan
        Write-Host "Run without --dry-run to apply." -ForegroundColor Gray
        Write-Host ""
        exit 0
    }

    foreach ($o in $orphans) {
        Write-Host "Recovering: $($o.run_id)" -ForegroundColor Cyan

        $action = "block"
        if (-not $yes) {
            Write-Host "  Actions: [r]esume  [a]bort (mark blocked)  [s]kip" -ForegroundColor Gray
            $choice = Read-Host "  Action for $($o.requirement_id)"
            switch ($choice.ToLower()) {
                "r"      { $action = "resume" }
                "a"      { $action = "block"  }
                "s"      { $action = "skip"   }
                default  { $action = "block"  }
            }
        }

        switch ($action) {
            "skip" {
                Write-Host "  Skipped." -ForegroundColor Gray
            }
            "resume" {
                Write-Host "  Resuming is not yet automated. Clean up worktree manually then re-run:" -ForegroundColor Yellow
                Write-Host "    felix run $($o.requirement_id)" -ForegroundColor Gray
                # Release stale lease so the requirement can be claimed again
                Remove-RequirementLease -ProjectPath $RepoRoot -RequirementId $o.requirement_id -Force | Out-Null
                Write-Host "  Lease released for $($o.requirement_id)" -ForegroundColor Green
            }
            "block" {
                # Release lease, mark requirement blocked, optionally clean worktree
                Remove-RequirementLease -ProjectPath $RepoRoot -RequirementId $o.requirement_id -Force | Out-Null
                if (Test-Path $reqFile) {
                    . "$PSScriptRoot\loop.ps1"
                    Set-RequirementBlocked -RequirementsFilePath $reqFile -RequirementId $o.requirement_id -BlockReason "recovered-from-crash"
                }
                if ($o.has_worktree) {
                    Write-Host "  Removing orphaned worktree: $($o.worktree_path)" -ForegroundColor Gray
                    if ($o.run_id) {
                        Remove-WorktreeForRun -RepoRoot $RepoRoot -RunId $o.run_id -Force | Out-Null
                    }
                }
                Write-Host "  $($o.requirement_id) marked blocked (block_reason: recovered-from-crash)" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host "Recovery complete." -ForegroundColor Green
    Write-Host ""
    exit 0
}

function Find-OrphanedRuns {
    <#
    .SYNOPSIS
    Scans leases and worktrees to find orphaned (crashed/stale) runs.
    Returns array of orphan descriptors.
    #>
    param([string]$RepoRoot)

    $result  = [System.Collections.ArrayList]@()
    $leases  = Get-AllLeases -ProjectPath $RepoRoot | Where-Object { -not $_.IsValid }
    $wts     = Get-ActiveWorktrees -RepoRoot $RepoRoot

    # Index worktrees by run_id
    $wtIndex = @{}
    foreach ($wt in $wts) { $wtIndex[$wt.run_id] = $wt }

    # Expired leases
    foreach ($lease in $leases) {
        $issues = @("lease-expired")
        $wtEntry = if ($lease.run_id -and $wtIndex.ContainsKey($lease.run_id)) { $wtIndex[$lease.run_id] } else { $null }
        if ($wtEntry) { $issues += "orphaned-worktree" }

        $orphan = [PSCustomObject]@{
            run_id          = $lease.run_id
            requirement_id  = $lease.requirement_id
            worker_id       = $lease.worker_id
            claimed_at      = $lease.claimed_at
            has_worktree    = ($null -ne $wtEntry)
            worktree_path   = if ($wtEntry) { $wtEntry.worktree } else { "" }
            issues          = $issues
        }
        [void]$result.Add($orphan)
    }

    # Worktrees without a lease (lease was released but worktree not cleaned up)
    foreach ($wt in $wts) {
        $hasLease = $leases | Where-Object { $_.run_id -eq $wt.run_id }
        if (-not $hasLease) {
            # Check if already accounted for above
            $already = $result | Where-Object { $_.run_id -eq $wt.run_id }
            if (-not $already) {
                $orphan = [PSCustomObject]@{
                    run_id         = $wt.run_id
                    requirement_id = ""
                    worker_id      = "unknown"
                    claimed_at     = $wt.created_at
                    has_worktree   = $true
                    worktree_path  = $wt.worktree
                    issues         = @("orphaned-worktree")
                }
                [void]$result.Add($orphan)
            }
        }
    }

    return $result.ToArray()
}

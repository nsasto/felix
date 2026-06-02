<#
.SYNOPSIS
Felix worktree manager (Phase H1).
Creates and tears down per-run git worktrees for parallel execution.

.DESCRIPTION
Worktrees are opt-in: set concurrency.worktrees=true in .felix/config.json
or pass --worktrees to felix loop.

Worktrees are created at:
  <repo>/.felix/worktrees/<run-id>/

On success (commit-on-complete): merge back to main branch then delete.
On failure: retain for diagnostics until retention window (concurrency.worktree_retention_days, default 3).
#>

function New-WorktreeForRun {
    <#
    .SYNOPSIS
    Creates a new git worktree for a run. Returns the worktree path or $null on failure.
    #>
    param(
        [string]$RepoRoot,
        [string]$RunId,
        [string]$BaseBranch = ""
    )

    $worktreesDir = Join-Path $RepoRoot ".felix\worktrees"
    if (-not (Test-Path $worktreesDir)) {
        New-Item -ItemType Directory -Path $worktreesDir -Force | Out-Null
    }

    $wtPath   = Join-Path $worktreesDir $RunId
    $branchName = "felix/run/$RunId"

    if (Test-Path $wtPath) {
        Write-Host "  [worktree] Already exists: $wtPath" -ForegroundColor Yellow
        return $wtPath
    }

    # Resolve base branch
    if (-not $BaseBranch) {
        try {
            $BaseBranch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
        } catch { $BaseBranch = "main" }
    }

    try {
        # Create a new branch + worktree in one step
        git -C $RepoRoot worktree add -b $branchName $wtPath $BaseBranch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [worktree] Failed to create worktree for $RunId" -ForegroundColor Red
            return $null
        }
        Write-Host "  [worktree] Created $wtPath (branch: $branchName)" -ForegroundColor Cyan
        # Record metadata
        $meta = @{
            run_id      = $RunId
            worktree    = $wtPath
            branch      = $branchName
            base_branch = $BaseBranch
            created_at  = (Get-Date -Format "o")
        }
        $meta | ConvertTo-Json | Set-Content (Join-Path $wtPath ".felix-worktree.json") -Encoding UTF8
        return $wtPath
    } catch {
        Write-Host "  [worktree] Error: $_" -ForegroundColor Red
        return $null
    }
}

function Remove-WorktreeForRun {
    <#
    .SYNOPSIS
    Removes a worktree and deletes its branch. Should be called after merge-back.
    #>
    param(
        [string]$RepoRoot,
        [string]$RunId,
        [switch]$Force
    )

    $worktreesDir = Join-Path $RepoRoot ".felix\worktrees"
    $wtPath = Join-Path $worktreesDir $RunId

    if (-not (Test-Path $wtPath)) {
        return $true
    }

    # Read metadata for branch name
    $metaPath = Join-Path $wtPath ".felix-worktree.json"
    $branchName = $null
    if (Test-Path $metaPath) {
        try {
            $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
            $branchName = $meta.branch
        } catch {}
    }

    try {
        if ($Force) {
            git -C $RepoRoot worktree remove --force $wtPath 2>&1 | Out-Null
        } else {
            git -C $RepoRoot worktree remove $wtPath 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -eq 0) {
            # Also delete the run branch
            if ($branchName) {
                git -C $RepoRoot branch -D $branchName 2>&1 | Out-Null
            }
            Write-Host "  [worktree] Removed $wtPath" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "  [worktree] Could not remove $wtPath (exit $LASTEXITCODE)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "  [worktree] Error removing worktree: $_" -ForegroundColor Red
        return $false
    }
}

function Merge-WorktreeToBase {
    <#
    .SYNOPSIS
    Merges a run worktree branch back into the base branch.
    Returns: "ok", "conflict", or "error".
    #>
    param(
        [string]$RepoRoot,
        [string]$RunId,
        [string]$MergeStrategy = "merge"  # "merge" or "squash"
    )

    $worktreesDir = Join-Path $RepoRoot ".felix\worktrees"
    $wtPath  = Join-Path $worktreesDir $RunId
    $metaPath = Join-Path $wtPath ".felix-worktree.json"

    if (-not (Test-Path $metaPath)) {
        Write-Host "  [worktree] No metadata found for $RunId" -ForegroundColor Red
        return "error"
    }

    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
    $branchName = $meta.branch
    $baseBranch = $meta.base_branch

    try {
        # Commit any uncommitted changes in the worktree
        $wtStatus = git -C $wtPath status --porcelain 2>$null
        if ($wtStatus) {
            git -C $wtPath add -A 2>&1 | Out-Null
            git -C $wtPath commit -m "chore(felix): worktree run $RunId auto-commit" 2>&1 | Out-Null
        }

        # Merge back to base branch
        if ($MergeStrategy -eq "squash") {
            git -C $RepoRoot merge --squash $branchName 2>&1 | Out-Null
        } else {
            git -C $RepoRoot merge --no-ff $branchName -m "feat(felix): merge run $RunId" 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -ne 0) {
            # Check if it's a conflict
            $conflictFiles = git -C $RepoRoot diff --name-only --diff-filter=U 2>$null
            if ($conflictFiles) {
                Write-Host "  [worktree] Merge conflict in: $($conflictFiles -join ', ')" -ForegroundColor Red
                git -C $RepoRoot merge --abort 2>&1 | Out-Null
                return "conflict"
            }
            return "error"
        }

        return "ok"
    } catch {
        Write-Host "  [worktree] Merge error: $_" -ForegroundColor Red
        return "error"
    }
}

function Get-ActiveWorktrees {
    <#
    .SYNOPSIS
    Returns list of active (existing) worktrees created by Felix.
    #>
    param([string]$RepoRoot)

    $worktreesDir = Join-Path $RepoRoot ".felix\worktrees"
    if (-not (Test-Path $worktreesDir)) { return @() }

    $result = [System.Collections.ArrayList]@()
    Get-ChildItem -Path $worktreesDir -Directory | ForEach-Object {
        $metaPath = Join-Path $_.FullName ".felix-worktree.json"
        if (Test-Path $metaPath) {
            try {
                $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
                [void]$result.Add($meta)
            } catch {}
        }
    }
    return $result.ToArray()
}

function Remove-StaleWorktrees {
    <#
    .SYNOPSIS
    Removes worktrees older than retention_days (default 3).
    #>
    param(
        [string]$RepoRoot,
        [int]$RetentionDays = 3,
        [switch]$DryRun
    )

    $worktrees = Get-ActiveWorktrees -RepoRoot $RepoRoot
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $removed = 0

    foreach ($wt in $worktrees) {
        $created = [DateTime]::Parse($wt.created_at)
        if ($created -lt $cutoff) {
            if ($DryRun) {
                Write-Host "  [dry-run] Would remove stale worktree: $($wt.run_id) (created $($wt.created_at))" -ForegroundColor Gray
            } else {
                Write-Host "  Removing stale worktree: $($wt.run_id)" -ForegroundColor Yellow
                Remove-WorktreeForRun -RepoRoot $RepoRoot -RunId $wt.run_id -Force
                $removed++
            }
        }
    }

    return $removed
}

function Get-WorktreeConfig {
    <#
    .SYNOPSIS
    Reads concurrency/worktree settings from .felix/config.json.
    Returns hashtable with enabled, retention_days, merge_strategy.
    #>
    param([string]$ProjectPath)

    $defaults = @{
        enabled         = $false
        retention_days  = 3
        merge_strategy  = "merge"
        parallel        = 1
    }

    $configPath = Join-Path $ProjectPath ".felix\config.json"
    if (-not (Test-Path $configPath)) { return $defaults }

    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($cfg.concurrency) {
            $c = $cfg.concurrency
            if ($null -ne $c.worktrees)       { $defaults.enabled        = [bool]$c.worktrees }
            if ($null -ne $c.retention_days)  { $defaults.retention_days = [int]$c.retention_days }
            if ($null -ne $c.merge_strategy)  { $defaults.merge_strategy = $c.merge_strategy }
            if ($null -ne $c.parallel)        { $defaults.parallel       = [int]$c.parallel }
        }
    } catch {}

    return $defaults
}

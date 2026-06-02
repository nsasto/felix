<#
.SYNOPSIS
Phase H tests - Concurrency & Worktrees: lease-manager, worktree-manager, recover, parallel loop.

Run with:
  powershell -File tests\Test-PhaseH.ps1
#>

$ErrorActionPreference = "Stop"

# ── Test helpers ──────────────────────────────────────────────────────────────

$script:Pass = 0
$script:Fail = 0

function Assert-True  { param($Cond, $Msg) if ($Cond) { $script:Pass++ } else { $script:Fail++; Write-Host "  FAIL: $Msg" -ForegroundColor Red } }
function Assert-False { param($Cond, $Msg) Assert-True (-not $Cond) $Msg }
function Assert-Equal {
    param($Expected, $Actual, $Msg)
    if ($Expected -eq $Actual) { $script:Pass++ }
    else { $script:Fail++; Write-Host "  FAIL: $Msg (expected='$Expected', actual='$Actual')" -ForegroundColor Red }
}
function Assert-NotNull { param($Val, $Msg) Assert-True ($null -ne $Val) $Msg }
function Assert-Null    { param($Val, $Msg) Assert-True ($null -eq $Val) $Msg }
function Assert-Contains { param($Val, $Col, $Msg) Assert-True ($Col -contains $Val) $Msg }

function Section { param($Name) Write-Host "`n## $Name" -ForegroundColor Cyan }

# ── Setup temp repo dir ───────────────────────────────────────────────────────

$TmpRepo  = Join-Path $env:TEMP ("felix-test-phaseH-" + [System.IO.Path]::GetRandomFileName())
$FelixDir = Join-Path $TmpRepo ".felix"
$LocksDir = Join-Path $FelixDir ".locks"
New-Item -ItemType Directory -Path $LocksDir -Force | Out-Null

# Dot-source modules under test
$FelixRoot = Join-Path (Join-Path $PSScriptRoot "..") ".felix"
. "$FelixRoot\core\lease-manager.ps1"
. "$FelixRoot\core\worktree-manager.ps1"
. "$FelixRoot\commands\recover.ps1"

$CurrentWorkerId = Get-WorkerId

# ── Section 1: Lease Manager - atomic claim ───────────────────────────────────
Section "1. Lease Manager - atomic claim"

$reqId = "H-TEST-001"

$lease1 = New-RequirementLease -ProjectPath $TmpRepo -RequirementId $reqId
Assert-NotNull $lease1 "First claim returns lease object"
Assert-Equal $reqId $lease1.requirement_id "Lease has correct requirement_id"
Assert-Equal $CurrentWorkerId $lease1.worker_id "Lease worker_id matches Get-WorkerId"
Assert-True  ($null -ne $lease1.claimed_at)  "Lease has claimed_at"
Assert-True  ($null -ne $lease1.lease_until) "Lease has lease_until"

$lease2 = New-RequirementLease -ProjectPath $TmpRepo -RequirementId $reqId
Assert-Null $lease2 "Second claim for same requirement returns null (atomic exclusion)"

# ── Section 2: Lease Manager - test validity ──────────────────────────────────
Section "2. Lease Manager - test validity"

$isValid = Test-RequirementLeased -ProjectPath $TmpRepo -RequirementId $reqId
Assert-True $isValid "Test-RequirementLeased returns true for fresh lease"

$isLeaseObjectValid = Test-LeaseValid -Lease $lease1
Assert-True $isLeaseObjectValid "Test-LeaseValid returns true for fresh lease object"

# ── Section 3: Lease Manager - ownership check ────────────────────────────────
Section "3. Lease Manager - ownership check"

$owned = Test-LeaseOwnedByMe -Lease $lease1
Assert-True $owned "This process owns the lease it created"

# Simulate lease from another process
$foreignLease = [PSCustomObject]@{ worker_id = "felix-99999@otherhost"; pid = 99999 }
$notOwned = Test-LeaseOwnedByMe -Lease $foreignLease
Assert-False $notOwned "Foreign process lease is not owned by me"

# ── Section 4: Lease Manager - update expiry ─────────────────────────────────
Section "4. Lease Manager - update expiry"

Start-Sleep -Milliseconds 50
$updated = Update-LeaseExpiry -ProjectPath $TmpRepo -RequirementId $reqId
Assert-True $updated "Update-LeaseExpiry returns true for owned lease"

# ── Section 5: Lease Manager - Get-AllLeases ─────────────────────────────────
Section "5. Lease Manager - Get-AllLeases"

$reqId2 = "H-TEST-002"
New-RequirementLease -ProjectPath $TmpRepo -RequirementId $reqId2 | Out-Null

$allLeases = Get-AllLeases -ProjectPath $TmpRepo
Assert-True ($allLeases.Count -ge 2) "Get-AllLeases returns at least 2 leases"
$ids = $allLeases | ForEach-Object { $_.requirement_id }
Assert-Contains $reqId  $ids "Get-AllLeases includes first lease"
Assert-Contains $reqId2 $ids "Get-AllLeases includes second lease"

$validLeases = $allLeases | Where-Object { $_.IsValid }
Assert-True (@($validLeases).Count -ge 2) "IsValid flag is set on fresh leases"

# ── Section 6: Lease Manager - Remove-RequirementLease ───────────────────────
Section "6. Lease Manager - Remove-RequirementLease"

$removed = Remove-RequirementLease -ProjectPath $TmpRepo -RequirementId $reqId
Assert-True $removed "Owner process can remove its lease"

$isLeased2 = Test-RequirementLeased -ProjectPath $TmpRepo -RequirementId $reqId
Assert-False $isLeased2 "Lease is gone after removal"

# Write a fake lease owned by another PID (cannot be removed without -Force)
$foreignLeasePath = Join-Path $LocksDir "H-TEST-FOREIGN.lock"
[PSCustomObject]@{
    requirement_id = "H-TEST-FOREIGN"
    worker_id      = "felix-99999@otherhost"
    run_id         = "run-foreign"
    claimed_at     = (Get-Date).ToString("o")
    lease_until    = (Get-Date).AddMinutes(30).ToString("o")
    pid            = 99999
} | ConvertTo-Json | Set-Content -Path $foreignLeasePath -Encoding UTF8

$removedForeign = Remove-RequirementLease -ProjectPath $TmpRepo -RequirementId "H-TEST-FOREIGN"
Assert-False $removedForeign "Cannot remove lease owned by different process"

# ── Section 7: Lease Manager - Force remove (recover scenario) ───────────────
Section "7. Lease Manager - Force remove (recover scenario)"

$forceRemoved = Remove-RequirementLease -ProjectPath $TmpRepo -RequirementId "H-TEST-FOREIGN" -Force
Assert-True $forceRemoved "Force remove works regardless of owner"
$goneAfterForce = Test-RequirementLeased -ProjectPath $TmpRepo -RequirementId "H-TEST-FOREIGN"
Assert-False $goneAfterForce "Lease gone after force remove"

# ── Section 8: Lease Manager - expired lease detection ───────────────────────
Section "8. Lease Manager - expired lease detection"

$expiredId = "H-TEST-EXPIRED"
$expiredLeasePath = Join-Path $LocksDir "$expiredId.lock"
[PSCustomObject]@{
    requirement_id = $expiredId
    worker_id      = "felix-dead@host"
    run_id         = "run-dead"
    claimed_at     = (Get-Date).ToUniversalTime().AddHours(-3).ToString("o")
    lease_until    = (Get-Date).ToUniversalTime().AddHours(-1).ToString("o")
    pid            = 99999
} | ConvertTo-Json | Set-Content -Path $expiredLeasePath -Encoding UTF8

$expiredLeases = Get-ExpiredLeases -ProjectPath $TmpRepo
Assert-True (@($expiredLeases).Count -ge 1) "Get-ExpiredLeases returns at least one expired lease"
$expiredIds = $expiredLeases | ForEach-Object { $_.requirement_id }
Assert-Contains $expiredId $expiredIds "Expired lease is in Get-ExpiredLeases result"

$isValidExpired = Test-RequirementLeased -ProjectPath $TmpRepo -RequirementId $expiredId
Assert-False $isValidExpired "Expired lease fails validity check"

# ── Section 9: Lease Manager - reclaim after expiry ──────────────────────────
Section "9. Lease Manager - reclaim after expiry"

$reclaimedLease = New-RequirementLease -ProjectPath $TmpRepo -RequirementId $expiredId
Assert-NotNull $reclaimedLease "Expired lease can be claimed by new worker"
Assert-Equal $CurrentWorkerId $reclaimedLease.worker_id "Reclaimed lease has current worker_id"

# ── Section 10: Worktree Manager - Get-WorktreeConfig defaults ────────────────
Section "10. Worktree Manager - Get-WorktreeConfig defaults"

$configPath = Join-Path $FelixDir "config.json"
'{}' | Set-Content -Path $configPath -Encoding UTF8

$cfg = Get-WorktreeConfig -ProjectPath $TmpRepo
Assert-NotNull $cfg "Get-WorktreeConfig returns object even without concurrency block"
Assert-Equal $false $cfg.enabled       "Default worktrees is false"
Assert-Equal 1      $cfg.parallel       "Default parallel is 1"
Assert-Equal 3      $cfg.retention_days "Default retention_days is 3"

# ── Section 11: Worktree Manager - Get-WorktreeConfig from config ─────────────
Section "11. Worktree Manager - Get-WorktreeConfig from config"

$configJson = '{"concurrency":{"worktrees":true,"parallel":4,"retention_days":7,"merge_strategy":"rebase"}}'
Set-Content -Path $configPath -Value $configJson -Encoding UTF8

$cfg2 = Get-WorktreeConfig -ProjectPath $TmpRepo
Assert-Equal $true    $cfg2.enabled       "worktrees=true from config"
Assert-Equal 4        $cfg2.parallel        "parallel=4 from config"
Assert-Equal 7        $cfg2.retention_days  "retention_days=7 from config"
Assert-Equal "rebase" $cfg2.merge_strategy  "merge_strategy=rebase from config"

# ── Section 12: Worktree Manager - Get-ActiveWorktrees (empty) ───────────────
Section "12. Worktree Manager - Get-ActiveWorktrees (no worktrees)"

$wt = Get-ActiveWorktrees -RepoRoot $TmpRepo
Assert-Equal 0 @($wt).Count "Get-ActiveWorktrees returns empty when no worktrees exist"

# ── Section 13: Worktree Manager - metadata file roundtrip ───────────────────
Section "13. Worktree Manager - metadata file roundtrip"

$wtDir = Join-Path (Join-Path (Join-Path $TmpRepo ".felix") "worktrees") "run-abc"
New-Item -ItemType Directory -Path $wtDir -Force | Out-Null
[PSCustomObject]@{
    run_id          = "run-abc"
    requirement_id  = "H-WT-001"
    worktree        = $wtDir
    branch          = "felix/run-abc"
    base_branch     = "v2"
    created_at      = (Get-Date).ToString("o")
    worker_id       = $CurrentWorkerId
} | ConvertTo-Json | Set-Content -Path (Join-Path $wtDir ".felix-worktree.json") -Encoding UTF8

$activeWts = Get-ActiveWorktrees -RepoRoot $TmpRepo
Assert-Equal 1        @($activeWts).Count          "Get-ActiveWorktrees finds 1 metadata file"
Assert-Equal "run-abc"  $activeWts[0].run_id      "run_id matches"
Assert-Equal "H-WT-001" $activeWts[0].requirement_id "requirement_id matches"

# ── Section 14: Recover - Invoke-Recover and Find-OrphanedRuns ───────────────
Section "14. recover.ps1 - functions are defined"

$fnInvoke = Get-Command Invoke-Recover -ErrorAction SilentlyContinue
Assert-NotNull $fnInvoke "Invoke-Recover function is defined after dot-sourcing recover.ps1"

$fnFind = Get-Command Find-OrphanedRuns -ErrorAction SilentlyContinue
Assert-NotNull $fnFind "Find-OrphanedRuns function is defined"

# ── Section 15: Find-OrphanedRuns - identifies expired leases ─────────────────
Section "15. Find-OrphanedRuns - expired leases become orphans"

$orphanId = "H-ORPHAN-001"
$orphanLeasePath = Join-Path $LocksDir "$orphanId.lock"
[PSCustomObject]@{
    requirement_id = $orphanId
    worker_id      = "felix-crash@host"
    run_id         = "run-crashed"
    claimed_at     = (Get-Date).ToUniversalTime().AddHours(-3).ToString("o")
    lease_until    = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
    pid            = 99999
} | ConvertTo-Json | Set-Content -Path $orphanLeasePath -Encoding UTF8

$orphans = Find-OrphanedRuns -RepoRoot $TmpRepo
Assert-True (@($orphans).Count -ge 1) "Find-OrphanedRuns detects at least 1 orphan"
$orphanReqIds = @($orphans) | ForEach-Object { $_.requirement_id }
Assert-Contains $orphanId $orphanReqIds "Expired lease is reported as orphan"

# ── Section 16: Find-OrphanedRuns - orphaned worktrees ────────────────────────
Section "16. Find-OrphanedRuns - orphaned worktrees (no matching lease)"

# The worktree from section 13 has no active lease -> orphan
$wtOrphans = Find-OrphanedRuns -RepoRoot $TmpRepo | Where-Object { $_.run_id -eq "run-abc" }
Assert-True (@($wtOrphans).Count -ge 1) "Worktree without lease detected as orphan"
Assert-True ($wtOrphans[0].has_worktree) "Orphan entry has has_worktree=true"
$wtIssues = $wtOrphans[0].issues
Assert-Contains "orphaned-worktree" $wtIssues "Orphan issues includes orphaned-worktree"

# ── Cleanup ───────────────────────────────────────────────────────────────────

Remove-Item -Recurse -Force $TmpRepo -ErrorAction SilentlyContinue

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor DarkGray
$total = $script:Pass + $script:Fail
if ($script:Fail -eq 0) {
    Write-Host "  Phase H Tests: ALL $total PASSED" -ForegroundColor Green
} else {
    Write-Host "  Phase H Tests: $($script:Pass)/$total passed, $($script:Fail) FAILED" -ForegroundColor Red
}
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host ""

if ($script:Fail -gt 0) { exit 1 } else { exit 0 }



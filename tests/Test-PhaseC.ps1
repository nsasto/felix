<#
.SYNOPSIS
Phase C unit tests - Explore subagent (Test-PhaseC.ps1)

Tests: Get-ExploreConfig, Test-ExploreEnabled, Assert-ContextMapSchema
#>

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

# ── Simple assert helpers ────────────────────────────────────────────────────
$script:TestsPassed = 0
$script:TestsFailed = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -ne $Actual) {
        Write-Host "  FAIL [$Label]: expected '$Expected', got '$Actual'" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-True {
    param($Condition, [string]$Label)
    if (-not $Condition) {
        Write-Host "  FAIL [$Label]: condition was false" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-False {
    param($Condition, [string]$Label)
    if ($Condition) {
        Write-Host "  FAIL [$Label]: condition was true (expected false)" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-NotNull {
    param($Value, [string]$Label)
    if ($null -eq $Value) {
        Write-Host "  FAIL [$Label]: value was null" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

# ── Load the module under test ────────────────────────────────────────────────
$repoRoot    = Split-Path $PSScriptRoot -Parent
$exploreScript = Join-Path $repoRoot ".felix\core\explore.ps1"
if (-not (Test-Path $exploreScript)) {
    Write-Host "ERROR: explore.ps1 not found at $exploreScript" -ForegroundColor Red
    exit 1
}
. $exploreScript

# ── Test helpers ──────────────────────────────────────────────────────────────
function Make-Config {
    param([bool]$Enabled = $false, [int]$MinFiles = 500, [int]$SkipGt = 1)
    return @{
        explore = @{
            enabled              = $Enabled
            auto_enable_when     = @{ min_tracked_files = $MinFiles }
            skip_on_iteration_gt = $SkipGt
            agent_override       = $null
            max_tokens           = 8000
        }
    }
}

# ── Get-ExploreConfig ─────────────────────────────────────────────────────────
Write-Host "`n== Get-ExploreConfig ==" -ForegroundColor Cyan

$cfg = Get-ExploreConfig -Config (Make-Config -Enabled $false)
Assert-Equal $false $cfg.enabled          "Get-ExploreConfig: enabled=false"
Assert-Equal 500    $cfg.auto_enable_when.min_tracked_files "Get-ExploreConfig: min_tracked_files=500"
Assert-Equal 1      $cfg.skip_on_iteration_gt "Get-ExploreConfig: skip_on_iteration_gt=1"
Assert-Equal 8000   $cfg.max_tokens        "Get-ExploreConfig: max_tokens=8000"

# Config without explore section — defaults returned
$cfg2 = Get-ExploreConfig -Config @{}
Assert-Equal $false $cfg2.enabled         "Get-ExploreConfig (no section): enabled defaults false"
Assert-NotNull $cfg2.auto_enable_when     "Get-ExploreConfig (no section): auto_enable_when not null"

# ── Test-ExploreEnabled ───────────────────────────────────────────────────────
Write-Host "`n== Test-ExploreEnabled ==" -ForegroundColor Cyan

$ec = Get-ExploreConfig -Config (Make-Config -Enabled $true)

# Explicit --explore always enables
$r = Test-ExploreEnabled -ExploreConfig $ec -ProjectPath $repoRoot -Iteration 1 -ExplicitExplore $true -ExplicitNoExplore $false
Assert-True $r "Test-ExploreEnabled: ExplicitExplore=true forces on"

# Explicit --no-explore always disables
$r = Test-ExploreEnabled -ExploreConfig $ec -ProjectPath $repoRoot -Iteration 1 -ExplicitExplore $false -ExplicitNoExplore $true
Assert-False $r "Test-ExploreEnabled: ExplicitNoExplore=true forces off"

# Enabled=true but iteration > skip_on_iteration_gt -> disabled
$ec2 = Get-ExploreConfig -Config (Make-Config -Enabled $true -SkipGt 1)
$r = Test-ExploreEnabled -ExploreConfig $ec2 -ProjectPath $repoRoot -Iteration 2 -ExplicitExplore $false -ExplicitNoExplore $false
Assert-False $r "Test-ExploreEnabled: iteration 2 > skip_on_iteration_gt 1 -> disabled"

# Enabled=true, iteration=1 -> enabled
$r = Test-ExploreEnabled -ExploreConfig $ec2 -ProjectPath $repoRoot -Iteration 1 -ExplicitExplore $false -ExplicitNoExplore $false
Assert-True $r "Test-ExploreEnabled: enabled=true iteration=1 <= skip=1 -> enabled"

# Enabled=false -> disabled unless explicit
$ec3 = Get-ExploreConfig -Config (Make-Config -Enabled $false)
$r = Test-ExploreEnabled -ExploreConfig $ec3 -ProjectPath $repoRoot -Iteration 1 -ExplicitExplore $false -ExplicitNoExplore $false
Assert-False $r "Test-ExploreEnabled: enabled=false, no flags -> disabled"

# ── Assert-ContextMapSchema ───────────────────────────────────────────────────
Write-Host "`n== Assert-ContextMapSchema ==" -ForegroundColor Cyan

# Full valid context-map with all required sections
$fullMap = @"
## Files likely to change
- src/main.ps1

## Files to read for context
- README.md

## Symbols of interest
None.

## Related tests
tests/Test-PhaseC.ps1

## Prior runs
None.
"@
$r = Assert-ContextMapSchema -Content $fullMap
Assert-True  ($r.Valid)                              "Assert-ContextMapSchema: full map -> Valid=true"
Assert-Equal 0 $r.Missing.Count                      "Assert-ContextMapSchema: full map -> 0 missing sections"

# Empty string -> missing all 5 sections
$r2 = Assert-ContextMapSchema -Content ""
Assert-False ($r2.Valid)                             "Assert-ContextMapSchema: empty -> Valid=false"
Assert-Equal 5 $r2.Missing.Count                     "Assert-ContextMapSchema: empty -> 5 missing sections"

# Partial map — missing some sections
$partial = "## Files likely to change`n- something`n`n## Files to read for context`n- README.md"
$r3 = Assert-ContextMapSchema -Content $partial
Assert-False ($r3.Valid)                             "Assert-ContextMapSchema: partial -> Valid=false"
Assert-True  ($r3.Missing -contains "## Symbols of interest") "Assert-ContextMapSchema: partial missing 'Symbols of interest'"
Assert-True  ($r3.Missing -contains "## Related tests")       "Assert-ContextMapSchema: partial missing 'Related tests'"
Assert-True  ($r3.Missing -contains "## Prior runs")          "Assert-ContextMapSchema: partial missing 'Prior runs'"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Phase C Tests: $script:TestsPassed passed, $script:TestsFailed failed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "=====================================" -ForegroundColor Cyan

if ($script:TestsFailed -gt 0) { exit 1 } else { exit 0 }

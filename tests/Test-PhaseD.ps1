<#
.SYNOPSIS
Phase D unit tests - Search (Test-PhaseD.ps1)

Tests: Get-SearchCacheKey, Get-SearchCache/Set-SearchCache, Get-RelatedFiles,
       Invoke-Search argument parsing basics
#>

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

# ── Simple assert helpers ─────────────────────────────────────────────────────
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

function Assert-Null {
    param($Value, [string]$Label)
    if ($null -ne $Value) {
        Write-Host "  FAIL [$Label]: expected null, got '$Value'" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

# ── Load modules under test ───────────────────────────────────────────────────
$repoRoot      = Split-Path $PSScriptRoot -Parent
$cacheScript   = Join-Path $repoRoot ".felix\core\search-cache.ps1"
$searchScript  = Join-Path $repoRoot ".felix\commands\search.ps1"

foreach ($s in @($cacheScript, $searchScript)) {
    if (-not (Test-Path $s)) {
        Write-Host "ERROR: $s not found" -ForegroundColor Red
        exit 1
    }
}

. $cacheScript
# Load search but suppress immediate execution
. $searchScript

# ── Get-SearchCacheKey ────────────────────────────────────────────────────────
Write-Host "`n== Get-SearchCacheKey ==" -ForegroundColor Cyan

$k1 = Get-SearchCacheKey -Query "CreateRunCommand" -Flags "file|code|50"
Assert-NotNull $k1                              "Get-SearchCacheKey: returns a value"
Assert-Equal 40 $k1.Length                      "Get-SearchCacheKey: SHA1 = 40 hex chars"
Assert-True  ($k1 -match "^[0-9a-f]{40}$")      "Get-SearchCacheKey: lowercase hex"

# Same input -> same key (deterministic)
$k2 = Get-SearchCacheKey -Query "CreateRunCommand" -Flags "file|code|50"
Assert-Equal $k1 $k2                            "Get-SearchCacheKey: deterministic"

# Different input -> different key
$k3 = Get-SearchCacheKey -Query "CreateRunCommand" -Flags "file|code|99"
Assert-True  ($k1 -ne $k3)                      "Get-SearchCacheKey: different flags -> different key"

$k4 = Get-SearchCacheKey -Query "OtherPattern" -Flags "file|code|50"
Assert-True  ($k1 -ne $k4)                      "Get-SearchCacheKey: different query -> different key"

# ── Get-SearchCache / Set-SearchCache / Clear-SearchCache ──────────────────────
Write-Host "`n== SearchCache read/write/clear ==" -ForegroundColor Cyan

$tmpDir = Join-Path $env:TEMP "felix-test-search-cache-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

try {
    $key = Get-SearchCacheKey -Query "felix" -Flags "file|code|50"

    # Miss before write
    $miss = Get-SearchCache -RunDir $tmpDir -Key $key
    Assert-Null $miss                           "SearchCache: miss before write -> null"

    # Write then hit
    $testResult = @{ matches = @(@{ path = "src/main.ps1"; line = 1; col = 1; text = "felix"; rank = 1.0; context = @() }); truncated = $false; total = 1; ignored_globs = @() }
    Set-SearchCache -RunDir $tmpDir -Key $key -Value $testResult
    $hit = Get-SearchCache -RunDir $tmpDir -Key $key
    Assert-NotNull $hit                         "SearchCache: hit after write -> not null"
    Assert-Equal 1 $hit.total                   "SearchCache: hit total = 1"

    # Second key doesn't collide
    $key2 = Get-SearchCacheKey -Query "other" -Flags "file|code|50"
    $miss2 = Get-SearchCache -RunDir $tmpDir -Key $key2
    Assert-Null $miss2                          "SearchCache: different key -> miss"

    # Write second key
    Set-SearchCache -RunDir $tmpDir -Key $key2 -Value @{ matches = @(); truncated = $false; total = 0; ignored_globs = @() }
    $hit2 = Get-SearchCache -RunDir $tmpDir -Key $key2
    Assert-NotNull $hit2                        "SearchCache: second key hit"
    Assert-Equal 0 $hit2.total                  "SearchCache: second key total = 0"

    # First key still intact (no collision)
    $hitAgain = Get-SearchCache -RunDir $tmpDir -Key $key
    Assert-Equal 1 $hitAgain.total              "SearchCache: first key unaffected by second write"

    # Clear
    Clear-SearchCache -RunDir $tmpDir
    $afterClear = Get-SearchCache -RunDir $tmpDir -Key $key
    Assert-Null $afterClear                     "SearchCache: after clear -> miss"

    # Clear on empty dir is a no-op (no error)
    Clear-SearchCache -RunDir $tmpDir
    Assert-True $true                           "SearchCache: clear on empty is a no-op"

} finally {
    Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Get-RelatedFiles ──────────────────────────────────────────────────────────
Write-Host "`n== Get-RelatedFiles ==" -ForegroundColor Cyan

$tmpProject = Join-Path $env:TEMP "felix-test-related-$(Get-Random)"
$runsDir    = Join-Path $tmpProject "runs"
New-Item -ItemType Directory -Path $runsDir -Force | Out-Null

try {
    # No runs dir match -> empty
    $files = Get-RelatedFiles -ProjectPath $tmpProject -RequirementId "S-9999"
    Assert-Equal 0 $files.Count                "Get-RelatedFiles: no matching runs -> 0"

    # Create a fake run with context-map.md
    $runDir1 = Join-Path $runsDir "S-0001-20260601-120000"
    New-Item -ItemType Directory -Path $runDir1 -Force | Out-Null
    $ctxMap = @"
# Context Map -- S-0001 it1

## Files likely to change
- src/Felix.Cli/Program.Commands.cs
- src/Felix.Cli/Program.Bootstrap.cs

## Files to read for context
- README.md
- .felix/config.json

## Symbols of interest
- CreateRunCommand

## Related tests
- tests/Felix.Cli.Tests/V2CommandsTests.cs

## Prior runs
None.
"@
    Set-Content -Path (Join-Path $runDir1 "context-map.md") -Value $ctxMap -Encoding UTF8

    $files = Get-RelatedFiles -ProjectPath $tmpProject -RequirementId "S-0001"
    Assert-True ($files.Count -ge 4)            "Get-RelatedFiles: extracts files from context-map -> >= 4"
    Assert-True ($files -contains "src/Felix.Cli/Program.Commands.cs") "Get-RelatedFiles: Program.Commands.cs present"
    Assert-True ($files -contains "README.md")  "Get-RelatedFiles: README.md present"
    Assert-True ($files -contains ".felix/config.json") "Get-RelatedFiles: config.json present"

    # Add iteration plan file
    $iterDir = Join-Path $runDir1 "iteration-1"
    New-Item -ItemType Directory -Path $iterDir -Force | Out-Null
    $planContent = @"
# Plan

## Steps
- src/Felix.Cli/NewFile.cs
- Not a file path (just text)
- tests/NewTest.cs
"@
    Set-Content -Path (Join-Path $iterDir "plan-S-0001.md") -Value $planContent -Encoding UTF8

    $files2 = Get-RelatedFiles -ProjectPath $tmpProject -RequirementId "S-0001"
    Assert-True ($files2 -contains "src/Felix.Cli/NewFile.cs") "Get-RelatedFiles: plan file paths included"
    Assert-True ($files2 -contains "tests/NewTest.cs")         "Get-RelatedFiles: plan test paths included"

    # Different req ID -> no match
    $files3 = Get-RelatedFiles -ProjectPath $tmpProject -RequirementId "S-0002"
    Assert-Equal 0 $files3.Count                "Get-RelatedFiles: non-matching req -> 0 files"

} finally {
    Remove-Item -Path $tmpProject -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Search JSON schema shape ──────────────────────────────────────────────────
Write-Host "`n== Search output schema (live search against repo) ==" -ForegroundColor Cyan

# Call Invoke-Search directly (already dot-sourced) and capture pipeline output
$savedLocation = Get-Location
Set-Location $repoRoot
try {
    $searchArgs = @("CreateRunCommand", "--json", "--in", "code", "--max", "5")
    $jsonLines = Invoke-Search @searchArgs 2>$null
    $jsonText  = if ($jsonLines -is [string]) { $jsonLines } else { $jsonLines -join "`n" }

    try {
        $parsed = $jsonText | ConvertFrom-Json
        Assert-NotNull $parsed                              "Search JSON: parse succeeds"
        Assert-NotNull $parsed.matches                      "Search JSON: has 'matches' key"
        Assert-NotNull ($parsed.PSObject.Properties["truncated"]) "Search JSON: has 'truncated' key"
        Assert-NotNull ($parsed.PSObject.Properties["total"])     "Search JSON: has 'total' key"
        Assert-NotNull $parsed.ignored_globs                "Search JSON: has 'ignored_globs' key"
        Assert-True  ($parsed.total -ge 1)                  "Search JSON: total >= 1 (CreateRunCommand exists)"
        if ($parsed.matches.Count -gt 0) {
            $m = $parsed.matches[0]
            Assert-NotNull $m.path                          "Search JSON: match has 'path'"
            Assert-NotNull ($m.PSObject.Properties["line"]) "Search JSON: match has 'line'"
            Assert-NotNull ($m.PSObject.Properties["col"])  "Search JSON: match has 'col'"
            Assert-NotNull $m.text                          "Search JSON: match has 'text'"
            Assert-NotNull ($m.PSObject.Properties["rank"]) "Search JSON: match has 'rank'"
        }
    } catch {
        Write-Host "  FAIL [Search JSON]: could not parse output: $_" -ForegroundColor Red
        Write-Host "  Raw output: $jsonText" -ForegroundColor Yellow
        $script:TestsFailed++
    }
} finally {
    Set-Location $savedLocation
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Phase D Tests: $script:TestsPassed passed, $script:TestsFailed failed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "=====================================" -ForegroundColor Cyan

if ($script:TestsFailed -gt 0) { exit 1 } else { exit 0 }

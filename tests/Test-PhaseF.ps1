#!/usr/bin/env pwsh
# tests/Test-PhaseF.ps1 -- Phase F: Targeted Execution + Security
# Run from repo root:  .\run-test-spec.ps1  OR  pwsh -File tests\Test-PhaseF.ps1

param([string]$ProjectPath = "")

if (-not $ProjectPath) { $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$ErrorActionPreference = "Stop"
$FelixRoot  = Join-Path $ProjectPath ".felix"
$CoreRoot   = Join-Path $FelixRoot  "core"
$CmdRoot    = Join-Path $FelixRoot  "commands"

# -- test harness -------------------------------------------------------------
$passed = 0
$failed = 0
function Assert-True {
    param([string]$Label, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result -eq $true -or $result) {
            Write-Host "  [PASS] $Label" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  [FAIL] $Label  (returned '$result')" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "  [FAIL] $Label  ($_)" -ForegroundColor Red
        $script:failed++
    }
}
function Assert-Equal {
    param([string]$Label, $Expected, $Actual)
    if ($Actual -eq $Expected) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Label  expected '$Expected' got '$Actual'" -ForegroundColor Red
        $script:failed++
    }
}
function Assert-Contains {
    param([string]$Label, [string]$Pattern, $Subject)
    $str = if ($Subject -is [string]) { $Subject } else { $Subject | ConvertTo-Json -Depth 5 -Compress }
    if ($str -match $Pattern) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Label  pattern '$Pattern' not found in '$str'" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "??? Phase F: Targeted Execution + Security ???" -ForegroundColor Cyan

# --- Section 1: path-matcher.ps1 ---------------------------------------------
Write-Host ""
Write-Host "1. path-matcher.ps1 (F1)" -ForegroundColor Yellow

. "$CoreRoot\path-matcher.ps1"
Assert-True  "Test-GlobMatch exact filename" {
    Test-GlobMatch "src/foo.cs" @("src/foo.cs")
}
Assert-True  "Test-GlobMatch single-star wildcard" {
    Test-GlobMatch "src/bar.cs" @("src/*.cs")
}
Assert-True  "Test-GlobMatch double-star (cross-dir)" {
    Test-GlobMatch "src/deep/nested/thing.ts" @("src/**/*.ts")
}
Assert-True  "Test-GlobMatch negation returns false for excluded" {
    -not (Test-GlobMatch "docs/readme.md" @("src/**"))
}
Assert-True  "Test-GlobMatch backslash-normalised path" {
    Test-GlobMatch "src\foo.cs" @("src/*.cs")
}
Assert-True  "Test-GlobMatch leaf-name fallback (no path)" {
    Test-GlobMatch "utils.py" @("*.py")
}
Assert-True  "Test-GlobMatch multiple patterns (first matches)" {
    Test-GlobMatch "src/app.ts" @("tests/**","src/**")
}
Assert-True  "Test-GlobMatch multiple patterns (second matches)" {
    Test-GlobMatch "tests/app.spec.ts" @("src/**","tests/**")
}
Assert-True  "Test-GlobMatch no match returns false" {
    -not (Test-GlobMatch "build/out.dll" @("src/**","tests/**"))
}

# --- Section 2: validator.ps1 Get-BackpressureCommands (F1) ------------------
Write-Host ""
Write-Host "2. validator.ps1 Get-BackpressureCommands (F1)" -ForegroundColor Yellow

# Stub Emit-Log for unit test context
if (-not (Get-Command Emit-Log -ErrorAction SilentlyContinue)) {
    function Emit-Log { param([string]$Level, [string]$Message) }
}

. "$CoreRoot\validator.ps1"

Assert-True "Get-BackpressureCommands returns empty for missing backpressure block" {
    $cmds = Get-BackpressureCommands -AgentsFilePath "C:\nonexistent\AGENTS.md" -ConfigCommands @()
    $cmds.Count -eq 0
}

Assert-True "Get-BackpressureCommands v1 string format" {
    $cmds = Get-BackpressureCommands -ConfigCommands @("dotnet test", "npm test")
    $cmds.Count -eq 2 -and $cmds[0].command -eq "dotnet test" -and $cmds[1].command -eq "npm test"
}

Assert-True "Get-BackpressureCommands v2 object format retains appliesTo" {
    # 2 items to avoid PS5.1 single-element array unrolling
    $obj1 = [PSCustomObject]@{ name = "dotnet.test"; cmd = "dotnet test"; appliesTo = @("src/**") }
    $obj2 = [PSCustomObject]@{ name = "npm.test";    cmd = "npm test";    appliesTo = $null }
    $cmds = Get-BackpressureCommands -ConfigCommands @($obj1, $obj2)
    $cmds.Count -eq 2 -and @($cmds[0].appliesTo).Count -eq 1 -and @($cmds[0].appliesTo)[0] -eq "src/**"
}
Assert-True "Get-BackpressureCommands v1 string - appliesTo is null (always run)" {
    $cmds = Get-BackpressureCommands -ConfigCommands @("npm test")
    $null -eq $cmds[0].appliesTo
}

# --- Section 3: validate-requirement.ps1 Get-SpecFrontmatter (F2) ------------
Write-Host ""
Write-Host "3. validate-requirement.ps1 Get-SpecFrontmatter (F2)" -ForegroundColor Yellow

. "$PSScriptRoot\..\scripts\validate-requirement.ps1" -DotSourceOnly

Assert-True "Get-SpecFrontmatter returns empty hash for spec with no frontmatter" {
    $fm = Get-SpecFrontmatter "## Overview`r`nSome spec"
    $fm -is [hashtable] -and $fm.Count -eq 0
}

Assert-True "Get-SpecFrontmatter parses scalar field" {
    $spec = "---`nid: S-0099`nstatus: planned`n---`n## Overview"
    $fm = Get-SpecFrontmatter $spec
    $fm.id -eq "S-0099" -and $fm.status -eq "planned"
}

Assert-True "Get-SpecFrontmatter parses inline array field" {
    $spec = "---`ngates: [dotnet.test, py.test]`n---`n## Overview"
    $fm = Get-SpecFrontmatter $spec
    $fm.gates -is [array] -and $fm.gates.Count -eq 2 -and $fm.gates[0] -eq "dotnet.test"
}

# --- Section 4: query.ps1 Invoke-Query (F3) ----------------------------------
Write-Host ""
Write-Host "4. query.ps1 Invoke-Query (F3)" -ForegroundColor Yellow

. "$CmdRoot\query.ps1"

# Test in a temp project directory
$tmpProj = Join-Path $env:TEMP "felix-test-query-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tmpProj -Force | Out-Null
New-Item -ItemType Directory -Path "$tmpProj\.felix" | Out-Null

@{ requirements = @() } | ConvertTo-Json | Set-Content "$tmpProj\.felix\requirements.json" -Encoding UTF8
@{
    _v = 1
    currency = "USD"
    prices = @(
        @{
            provider = "droid"
            model = "claude-sonnet-test"
            input_per_million = 1.0
            output_per_million = 2.0
            cache_read_per_million = 0.5
            cache_creation_per_million = 1.5
        }
    )
} | ConvertTo-Json -Depth 5 | Set-Content "$tmpProj\.felix\model-pricing.json" -Encoding UTF8

Assert-True "Invoke-Query requirements returns _v:1 JSON" {
    $out = Invoke-Query -CmdArgs @("requirements","--json") -ProjectPath $tmpProj 2>&1
    $json = $out | Where-Object { $_ -match '"_v"' } | Select-Object -First 1
    $json -match '"_v"\s*:\s*1'
}

Assert-True "Invoke-Query state returns _v:1 JSON" {
    $out = Invoke-Query -CmdArgs @("state","--json") -ProjectPath $tmpProj 2>&1
    $json = $out | Where-Object { $_ -match '"_v"' } | Select-Object -First 1
    $json -match '"_v"\s*:\s*1'
}

Assert-True "Invoke-Query usage returns token totals from usage.json" {
    $runDir = Join-Path $tmpProj "runs\S-0099-20260619-120000-it1"
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    [ordered]@{
        _v = 1
        run_id = "S-0099-20260619-120000-it1"
        timestamp_utc = "2026-06-19T12:00:00Z"
        duration_seconds = 12.5
        exit_code = 0
        succeeded = $true
        usage_available = $true
        usage_source = "droid.output"
        agent = [ordered]@{
            id = "ag_test"
            name = "droid"
            provider = "droid"
            adapter = "droid"
            executable = "droid"
        }
        model = [ordered]@{
            configured = "claude-sonnet-test"
            effective = "claude-sonnet-test"
            source = "configured"
        }
        usage = [ordered]@{
            input_tokens = 10
            output_tokens = 20
            total_tokens = 30
            cache_read_input_tokens = 40
            cache_creation_input_tokens = 50
            observed_tokens = 120
        }
    } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $runDir "usage.json") -Encoding UTF8

    $out = Invoke-Query -CmdArgs @("usage","--requirement","S-0099","--json") -ProjectPath $tmpProj 2>&1
    $parsed = ($out -join "`n") | ConvertFrom-Json
    $parsed._v -eq 1 -and
        $parsed.kind -eq "usage" -and
        $parsed.total -eq 1 -and
        $parsed.totals.input_tokens -eq 10 -and
        $parsed.totals.observed_tokens -eq 120 -and
        $parsed.pricing.costed_runs -eq 1 -and
        $parsed.estimated_cost -eq 0.000145 -and
        $parsed.usage[0].estimated_cost -eq 0.000145 -and
        $parsed.usage[0].effective_model -eq "claude-sonnet-test"
}

Assert-True "Invoke-Query invalid kind returns error message" {
    # Run in a child process to avoid 'exit 1' terminating the test script
    $out = powershell -NoProfile -Command "
        . '$CmdRoot\query.ps1'
        Invoke-Query -CmdArgs @('events') -ProjectPath '$tmpProj' 2>&1
    " 2>&1
    $str = $out -join " "
    $str -match "felix event" -or $str -match "not supported" -or $str -match "Unknown kind"
}

Remove-Item $tmpProj -Recurse -Force -ErrorAction SilentlyContinue

# --- Section 5: tool-allowlist.ps1 Test-AllowlistDecision (F5) ---------------
Write-Host ""
Write-Host "5. tool-allowlist.ps1 Test-AllowlistDecision (F5)" -ForegroundColor Yellow

. "$CoreRoot\tool-allowlist.ps1"

Assert-Equal "Test-AllowlistDecision default=allow, no lists -> allowed" $true `
    (Test-AllowlistDecision -ToolName "bash" -AllowList @() -DenyList @() -DefaultMode "allow")

Assert-Equal "Test-AllowlistDecision default=deny, not on allow -> denied" $false `
    (Test-AllowlistDecision -ToolName "bash" -AllowList @() -DenyList @() -DefaultMode "deny")

Assert-Equal "Test-AllowlistDecision explicit allow overrides deny-default" $true `
    (Test-AllowlistDecision -ToolName "bash" -AllowList @("bash","pwsh") -DenyList @() -DefaultMode "deny")

Assert-Equal "Test-AllowlistDecision explicit deny overrides allow-default" $false `
    (Test-AllowlistDecision -ToolName "curl" -AllowList @() -DenyList @("curl") -DefaultMode "allow")

Assert-Equal "Test-AllowlistDecision glob in allow list matches" $true `
    (Test-AllowlistDecision -ToolName "git-commit" -AllowList @("git-*") -DenyList @() -DefaultMode "deny")

Assert-Equal "Test-AllowlistDecision deny overrides allow when both match" $false `
    (Test-AllowlistDecision -ToolName "bash" -AllowList @("bash") -DenyList @("bash") -DefaultMode "allow")

# --- Section 6: tool.ps1 Invoke-Tool (F5) ------------------------------------
Write-Host ""
Write-Host "6. tool.ps1 Invoke-Tool (F5)" -ForegroundColor Yellow

. "$CmdRoot\tool.ps1"

$tmpProj2 = Join-Path $env:TEMP "felix-test-tool-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path "$tmpProj2\.felix" -Force | Out-Null
@{ tools = @{ allow = @(); deny = @(); default = "allow" } } | ConvertTo-Json | Set-Content "$tmpProj2\.felix\config.json" -Encoding UTF8

Assert-True "Invoke-Tool status outputs policy" {
    # Use *>&1 to also capture Write-Host (information stream 6) in PS5.1
    $out = powershell -NoProfile -Command "
        . '$CmdRoot\tool.ps1'
        Invoke-Tool -CmdArgs @('status') -ProjectPath '$tmpProj2' *>&1
    " 2>&1
    ($out -join " ") -match "allow|policy|default"
}

Assert-True "Invoke-Tool harden --dry-run does not write config" {
    $before = Get-Content "$tmpProj2\.felix\config.json" -Raw
    Invoke-Tool -CmdArgs @("harden","--dry-run","--yes") -ProjectPath $tmpProj2 2>&1 | Out-Null
    $after = Get-Content "$tmpProj2\.felix\config.json" -Raw
    $before -eq $after
}

Remove-Item $tmpProj2 -Recurse -Force -ErrorAction SilentlyContinue

# --- Section 7: gc.ps1 Invoke-Gc (F8) ----------------------------------------
Write-Host ""
Write-Host "7. gc.ps1 Invoke-Gc (F8)" -ForegroundColor Yellow

. "$CmdRoot\gc.ps1"

$tmpProj3 = Join-Path $env:TEMP "felix-test-gc-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path "$tmpProj3\.felix\events" -Force | Out-Null
# gc.ps1 uses $ProjectPath\runs (not .felix\runs)
New-Item -ItemType Directory -Path "$tmpProj3\runs" -Force | Out-Null
@{ gc = @{ retention_days = 30; events_retention_days = 30 } } | ConvertTo-Json | Set-Content "$tmpProj3\.felix\config.json" -Encoding UTF8

# Create a stale run dir (older than 30 days)
$staleRun = New-Item -ItemType Directory -Path "$tmpProj3\runs\S-0001-20240101T000000"
(Get-Item $staleRun.FullName).LastWriteTime = (Get-Date).AddDays(-60)

Assert-True "Invoke-Gc --dry-run reports stale run without deleting" {
    # Run in subprocess with *>&1 to capture Write-Host output
    $out = powershell -NoProfile -Command ". '$CmdRoot\gc.ps1'; Invoke-Gc -CmdArgs @('--dry-run') -ProjectPath '$tmpProj3' *>&1" 2>&1
    $str = $out -join " "
    (Test-Path $staleRun.FullName) -and ($str -match "S-0001|stale|run|would")
}
Assert-True "Invoke-Gc --yes deletes stale run" {
    Invoke-Gc -CmdArgs @("--yes") -ProjectPath $tmpProj3 2>&1 | Out-Null
    -not (Test-Path $staleRun.FullName)
}

Remove-Item $tmpProj3 -Recurse -Force -ErrorAction SilentlyContinue

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "??? Phase F Results ???" -ForegroundColor Cyan
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failed -gt 0) { exit 1 }

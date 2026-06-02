#!/usr/bin/env pwsh
# tests/Test-PhaseG.ps1 -- Phase G: Marketplace (curated index, remote update, skill install)
# Run from repo root:  .\run-test-spec.ps1  OR  pwsh -File tests\Test-PhaseG.ps1

param([string]$ProjectPath = "")

if (-not $ProjectPath) { $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$ErrorActionPreference = "Stop"
$FelixRoot = Join-Path $ProjectPath ".felix"
$CoreRoot  = Join-Path $FelixRoot  "core"
$CmdRoot   = Join-Path $FelixRoot  "commands"

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
function Assert-NotNull {
    param([string]$Label, $Value)
    if ($null -ne $Value) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Label  (got null)" -ForegroundColor Red
        $script:failed++
    }
}
function Assert-Null {
    param([string]$Label, $Value)
    if ($null -eq $Value) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Label  (expected null but got '$Value')" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "=== Phase G: Marketplace ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Helpers: temp directories
# ---------------------------------------------------------------------------
function New-TempDir {
    $d = Join-Path $env:TEMP "felix-test-g-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "1. index-client.ps1 exists" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$indexClientPath = Join-Path $CoreRoot "index-client.ps1"
Assert-True "index-client.ps1 exists" { Test-Path $indexClientPath }

# Dot-source for all subsequent tests
. $indexClientPath

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "2. Compare-SemVer" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
Assert-Equal "1.0.0 vs 1.0.0 = 0"  0  (Compare-SemVer "1.0.0" "1.0.0")
Assert-Equal "1.0.1 vs 1.0.0 = 1"  1  (Compare-SemVer "1.0.1" "1.0.0")
Assert-Equal "1.0.0 vs 1.0.1 = -1" -1 (Compare-SemVer "1.0.0" "1.0.1")
Assert-Equal "2.0.0 vs 1.9.9 = 1"  1  (Compare-SemVer "2.0.0" "1.9.9")
Assert-Equal "0.9.0 vs 1.0.0 = -1" -1 (Compare-SemVer "0.9.0" "1.0.0")
Assert-Equal "1.2.3 vs 1.2.3 = 0"  0  (Compare-SemVer "1.2.3" "1.2.3")
Assert-Equal "1.10.0 vs 1.9.0 = 1"  1  (Compare-SemVer "1.10.0" "1.9.0")

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "3. Get-CompatibleVersion" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$versions = @(
    [PSCustomObject]@{ v="1.0.0"; channel="stable"; felix_min="0.8.0"; url="http://example.com/1.0.0.zip"; sha256="abc" }
    [PSCustomObject]@{ v="1.1.0"; channel="stable"; felix_min="1.0.0"; url="http://example.com/1.1.0.zip"; sha256="def" }
    [PSCustomObject]@{ v="1.2.0"; channel="beta";   felix_min="1.0.0"; url="http://example.com/1.2.0.zip"; sha256="ghi" }
    [PSCustomObject]@{ v="2.0.0"; channel="stable"; felix_min="2.5.0"; url="http://example.com/2.0.0.zip"; sha256="jkl" }
)

$r = Get-CompatibleVersion -Versions $versions -InstalledFelixVersion "1.3.0" -Channel "stable"
Assert-Equal "stable channel + Felix 1.3.0 picks 1.1.0" "1.1.0" $r.v

$r2 = Get-CompatibleVersion -Versions $versions -InstalledFelixVersion "1.3.0" -Channel "beta"
Assert-Equal "beta channel + Felix 1.3.0 picks 1.2.0" "1.2.0" $r2.v

$r3 = Get-CompatibleVersion -Versions $versions -InstalledFelixVersion "0.7.0" -Channel "stable"
Assert-Null "Felix 0.7.0 has no compatible version" $r3

$r4 = Get-CompatibleVersion -Versions $versions -InstalledFelixVersion "2.5.0" -Channel "stable"
Assert-Equal "Felix 2.5.0 picks 2.0.0" "2.0.0" $r4.v

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "4. Get-DistributionConfig" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$tmp = New-TempDir
$felixDir = Join-Path $tmp ".felix"
New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

# No config.json -> defaults
$cfg = Get-DistributionConfig -ProjectPath $tmp
Assert-Equal "default index_url" "https://nsasto.github.io/felix/plugins.json" $cfg.index_url
Assert-True  "default channels contains stable" { $cfg.channels -contains "stable" }

# With custom config
@{
    distribution = @{
        index_url = "https://mycompany.com/felix-index.json"
        channels  = @("stable","internal")
    }
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $felixDir "config.json") -Encoding UTF8
$cfg2 = Get-DistributionConfig -ProjectPath $tmp
Assert-Equal "custom index_url from config" "https://mycompany.com/felix-index.json" $cfg2.index_url
Assert-True  "custom channels contains internal" { $cfg2.channels -contains "internal" }

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "5. Get-PluginIndex (local file)" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$docsIndex = Join-Path $ProjectPath "docs\plugins.json"
Assert-True "docs/plugins.json exists" { Test-Path $docsIndex }

$idx = Get-PluginIndex -Url $docsIndex
Assert-NotNull "Index is non-null" $idx
Assert-True    "Index has plugins array"  { $idx.plugins.Count -gt 0 }
Assert-True    "Index has skills array"   { $null -ne $idx.skills }
Assert-Contains "Index schema is index-v1" "index-v1" ($idx.schema)

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "6. Get-PluginIndex (missing file returns null)" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$nullIdx = Get-PluginIndex -Url "C:\does-not-exist\plugins.json"
Assert-Null "Missing file returns null" $nullIdx

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "7. Get-InstalledFelixVersion" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$ver = Get-InstalledFelixVersion -ProjectPath $ProjectPath
Assert-True "InstalledFelixVersion is non-empty" { $ver -match '\d+\.\d+\.\d+' }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "8. plugin.ps1 exists and loads" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$pluginPs1 = Join-Path $CmdRoot "plugin.ps1"
Assert-True "plugin.ps1 exists" { Test-Path $pluginPs1 }
. $pluginPs1
Assert-True "Invoke-Plugin function defined" { $null -ne (Get-Command Invoke-Plugin -ErrorAction SilentlyContinue) }
Assert-True "Invoke-PluginList function defined"   { $null -ne (Get-Command Invoke-PluginList   -ErrorAction SilentlyContinue) }
Assert-True "Invoke-PluginInstall function defined" { $null -ne (Get-Command Invoke-PluginInstall -ErrorAction SilentlyContinue) }
Assert-True "Invoke-PluginUpdate function defined" { $null -ne (Get-Command Invoke-PluginUpdate -ErrorAction SilentlyContinue) }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "9. skill.ps1 exists and loads" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$skillPs1 = Join-Path $CmdRoot "skill.ps1"
Assert-True "skill.ps1 exists" { Test-Path $skillPs1 }
# Load skill.ps1 (redefines Invoke-Skill — that's fine)
. $skillPs1
Assert-True "Invoke-Skill function defined"        { $null -ne (Get-Command Invoke-Skill         -ErrorAction SilentlyContinue) }
Assert-True "Invoke-SkillInstall function defined" { $null -ne (Get-Command Invoke-SkillInstall  -ErrorAction SilentlyContinue) }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "10. Invoke-PluginList local (no --remote)" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$tmp2 = New-TempDir
$felixDir2 = Join-Path $tmp2 ".felix"
New-Item -ItemType Directory -Path (Join-Path $felixDir2 "plugins") -Force | Out-Null

# Create a fake plugin
$fakePDir = Join-Path $felixDir2 "plugins\fake-plugin"
New-Item -ItemType Directory -Path $fakePDir -Force | Out-Null
@{ id = "fake-plugin"; name = "Fake Plugin"; version = "1.0.0" } | ConvertTo-Json | Set-Content (Join-Path $fakePDir "plugin.json") -Encoding UTF8

$output = Invoke-PluginList -SubArgs @() -RepoRoot $tmp2 | Out-String
# Invoke-PluginList writes to host so capture via redirection
$captured = & { Invoke-Plugin -CmdArgs @("list") -RepoRoot $tmp2 -FelixRoot $felixDir2 } *>&1 | Out-String
Assert-Contains "Plugins header present" "Plugins" $captured
Assert-Contains "fake-plugin listed" "fake-plugin" $captured

Remove-Item $tmp2 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "11. Invoke-PluginList --remote uses index (mock local file)" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$tmp3 = New-TempDir
$felixDir3 = Join-Path $tmp3 ".felix"
New-Item -ItemType Directory -Path $felixDir3 -Force | Out-Null
$mockIndexPath = Join-Path $tmp3 "mock-index.json"
@{
    schema  = "index-v1"
    updated = "2025-01-01"
    plugins = @(
        @{
            id         = "remote-plugin"
            name       = "Remote Plugin"
            categories = @("test")
            maintainer = "tester"
            versions   = @(@{ v="1.0.0"; channel="stable"; felix_min="0.1.0"; url="http://x"; sha256="aaa" })
        }
    )
    skills  = @()
} | ConvertTo-Json -Depth 10 | Set-Content $mockIndexPath -Encoding UTF8

# Inject distribution config pointing to local mock index
@{ distribution = @{ index_url = $mockIndexPath; channels = @("stable") } } |
    ConvertTo-Json | Set-Content (Join-Path $felixDir3 "config.json") -Encoding UTF8

$captured3 = & { Invoke-Plugin -CmdArgs @("list","--remote") -RepoRoot $tmp3 -FelixRoot $felixDir3 } *>&1 | Out-String
Assert-Contains "Remote header shown"   "Remote" $captured3
Assert-Contains "remote-plugin shown"   "remote-plugin" $captured3

Remove-Item $tmp3 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "12. Invoke-PluginUpdate --dry-run with mock index" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$tmp4 = New-TempDir
$fd4  = Join-Path $tmp4 ".felix"
New-Item -ItemType Directory -Path (Join-Path $fd4 "plugins\update-me") -Force | Out-Null
@{ id = "update-me"; name = "Update Me"; version = "0.9.0" } |
    ConvertTo-Json | Set-Content (Join-Path $fd4 "plugins\update-me\plugin.json") -Encoding UTF8

$mockIdx4 = Join-Path $tmp4 "mock4.json"
@{
    schema  = "index-v1"
    updated = "2025-01-01"
    plugins = @(
        @{
            id         = "update-me"
            name       = "Update Me"
            categories = @("test")
            maintainer = "test"
            versions   = @(@{ v="1.0.0"; channel="stable"; felix_min="0.0.0"; url="http://x"; sha256="000" })
        }
    )
    skills  = @()
} | ConvertTo-Json -Depth 10 | Set-Content $mockIdx4 -Encoding UTF8
@{ distribution = @{ index_url = $mockIdx4; channels = @("stable") } } |
    ConvertTo-Json | Set-Content (Join-Path $fd4 "config.json") -Encoding UTF8

$captured4 = & { Invoke-Plugin -CmdArgs @("update","--all","--dry-run") -RepoRoot $tmp4 -FelixRoot $fd4 } *>&1 | Out-String
Assert-Contains "Dry-run shows update-me" "update-me" $captured4
Assert-Contains "Dry-run mentions 1.0.0"  "1\.0\.0"     $captured4
Assert-Contains "Dry-run label shown"     "\[dry-run\]"  $captured4

# Plugin must NOT actually be updated (directory still at old version)
$manifestAfter = Get-Content (Join-Path $fd4 "plugins\update-me\plugin.json") -Raw | ConvertFrom-Json
Assert-Equal "Plugin not modified during dry-run" "0.9.0" $manifestAfter.version

Remove-Item $tmp4 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "13. skill.ps1 $Args -> $CmdArgs (no silent binding failure)" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
# Verify the file does NOT contain the old $Args param declaration
$skillContent = Get-Content $skillPs1 -Raw
Assert-True "skill.ps1 uses CmdArgs not Args param" { $skillContent -match '\[string\[\]\]\$CmdArgs' }
Assert-True "skill.ps1 does not use [string[]]`$Args" { $skillContent -notmatch '\[string\[\]\]\$Args' }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "14. Invoke-SkillInstall from local path" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$tmp5 = New-TempDir
$fd5  = Join-Path $tmp5 ".felix"
New-Item -ItemType Directory -Path (Join-Path $fd5 "skills") -Force | Out-Null

# Create fake skill source
$srcSkill = Join-Path $tmp5 "my-skill-src"
New-Item -ItemType Directory -Path $srcSkill -Force | Out-Null
@{ id = "my-local-skill"; name = "My Local Skill"; version = "1.0.0" } |
    ConvertTo-Json | Set-Content (Join-Path $srcSkill "skill.json") -Encoding UTF8

Invoke-SkillInstall -SubArgs @($srcSkill) -RepoRoot $tmp5

$destDir5 = Join-Path $fd5 "skills\my-local-skill"
Assert-True "Local skill installed to skills dir" { Test-Path $destDir5 }
Assert-True "skill.json present in installed dir" { Test-Path (Join-Path $destDir5 "skill.json") }

Remove-Item $tmp5 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "15. docs/plugins.json schema" -ForegroundColor Yellow
# ---------------------------------------------------------------------------
$docsIdx = Get-Content $docsIndex -Raw | ConvertFrom-Json
Assert-Equal "schema is index-v1" "index-v1" $docsIdx.schema
Assert-True  "plugins array exists" { $docsIdx.plugins.Count -gt 0 }
foreach ($p in $docsIdx.plugins) {
    Assert-True "Plugin $($p.id) has versions" { $p.versions.Count -gt 0 }
    foreach ($v in $p.versions) {
        Assert-True "Plugin $($p.id) v$($v.v) has url"    { -not [string]::IsNullOrEmpty($v.url) }
        Assert-True "Plugin $($p.id) v$($v.v) has sha256" { -not [string]::IsNullOrEmpty($v.sha256) }
        Assert-True "Plugin $($p.id) v$($v.v) has channel" { -not [string]::IsNullOrEmpty($v.channel) }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 50) -ForegroundColor DarkGray
$color = if ($failed -eq 0) { "Green" } else { "Red" }
Write-Host "Phase G: $passed passed, $failed failed" -ForegroundColor $color
Write-Host ""

if ($failed -gt 0) { exit 1 }
exit 0

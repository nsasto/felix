<#
.SYNOPSIS
Graphify integration unit tests.
#>

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

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
        Write-Host "  FAIL [$Label]: condition was true" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$testTempRoot = Join-Path $repoRoot ".tmp-graphify-tests"
Remove-Item $testTempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $testTempRoot -Force | Out-Null
. (Join-Path $repoRoot ".felix/core/graphify.ps1")
. (Join-Path $repoRoot ".felix/core/skill-loader.ps1")
. (Join-Path $repoRoot ".felix/core/config-loader.ps1")
. (Join-Path $repoRoot ".felix/commands/graphify.ps1")

Write-Host "`n== Graphify config defaults ==" -ForegroundColor Cyan
$defaults = Get-GraphifyConfig -Config ([pscustomobject]@{})
Assert-False $defaults.enabled "default enabled=false"
Assert-Equal "local" $defaults.mode "default mode=local"
Assert-Equal ".felix/graphify" $defaults.out_dir "default out_dir"
Assert-Equal "graphify-out" $defaults.team_out_dir "default team_out_dir"
Assert-Equal "ignore" $defaults.cache_policy "default cache_policy"

Write-Host "`n== Graphify setup helpers ==" -ForegroundColor Cyan
$tmpProject = Join-Path $testTempRoot "felix-graphify-test-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpProject -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpProject ".felix") -Force | Out-Null
try {
    @"
{
  "executor": { "commit_on_complete": true }
}
"@ | Set-Content -Path (Join-Path $tmpProject ".felix/config.json") -Encoding UTF8

    $cfg = Ensure-GraphifyConfigInFile -ConfigPath (Join-Path $tmpProject ".felix/config.json") -Mode "team" -AutoCommitRefresh:$true -CachePolicy "ignore" -PostCommitHook:$true
    $g = Get-GraphifyConfig -Config $cfg
    Assert-True $g.enabled "setup enables graphify"
    Assert-Equal "team" $g.mode "setup sets team mode"
    Assert-True $g.auto_commit_refresh "setup enables auto refresh"

    $skillDir = Ensure-GraphifySkill -RepoRoot $tmpProject
    Assert-True (Test-Path (Join-Path $skillDir "skill.json")) "skill manifest written"
    Assert-True (Test-Path (Join-Path $skillDir "prompt.md")) "skill prompt written"

    $ignore = Add-GraphifyGitIgnoreRules -RepoRoot $tmpProject -TeamOutDir "graphify-out" -CachePolicy "ignore"
    $gitignore = Get-Content (Join-Path $tmpProject ".gitignore") -Raw
    Assert-True ($gitignore -match "graphify-out/cost\.json") "gitignore includes cost.json"
    Assert-True ($gitignore -match "graphify-out/cache/") "gitignore includes cache when ignored"
} finally {
    Remove-Item $tmpProject -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n== Skill loader gating ==" -ForegroundColor Cyan
$tmpSkills = Join-Path $testTempRoot "felix-graphify-skill-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpSkills -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpSkills ".felix") -Force | Out-Null
try {
    Ensure-GraphifySkill -RepoRoot $tmpSkills | Out-Null
    $offBlob = Invoke-SkillLoader -RepoRoot $tmpSkills -Config ([pscustomobject]@{ graphify = [pscustomobject]@{ enabled = $false; skill_enabled = $true } })
    Assert-False ($offBlob -match "Graphify Investigator") "skill not loaded when graphify disabled"
    $onBlob = Invoke-SkillLoader -RepoRoot $tmpSkills -Config ([pscustomobject]@{ graphify = [pscustomobject]@{ enabled = $true; skill_enabled = $true } })
    Assert-True ($onBlob -match "Graphify Investigator") "skill loaded when graphify enabled"
} finally {
    Remove-Item $tmpSkills -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n== Hook and merge-driver status ==" -ForegroundColor Cyan
$tmpRepo = Join-Path $testTempRoot "felix-graphify-git-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpRepo -Force | Out-Null
$tmpGitBin = Join-Path $testTempRoot "felix-graphify-git-bin-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpGitBin -Force | Out-Null
try {
    $hookPath = Join-Path $tmpRepo "hooks/post-commit"
    New-Item -ItemType Directory -Path (Split-Path $hookPath -Parent) -Force | Out-Null
    "graphify hook" | Set-Content -Path $hookPath -Encoding ASCII
    "param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$GitArgs)`r`nif (`$GitArgs -contains 'rev-parse') { Write-Output '$hookPath'; exit 0 }`r`nWrite-Output 'merge.graphify.driver graphify merge %O %A %B'`r`nexit 0`r`n" | Set-Content -Path (Join-Path $tmpGitBin "git.ps1") -Encoding ASCII
    $oldPathForGit = $env:PATH
    $env:PATH = "$tmpGitBin;$oldPathForGit"

    Assert-True (Test-GraphifyHookInstalled -RepoRoot $tmpRepo) "post-commit hook detected"
    Assert-True (Test-GraphifyMergeDriverInstalled -RepoRoot $tmpRepo) "merge driver detected"
} finally {
    $env:PATH = $oldPathForGit
    Remove-Item $tmpRepo -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpGitBin -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n== Auto commit eligibility ==" -ForegroundColor Cyan
$tmpRepo2 = Join-Path $testTempRoot "felix-graphify-eligible-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpRepo2 -Force | Out-Null
$tmpStatusBin = Join-Path $testTempRoot "felix-graphify-status-bin-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpStatusBin -Force | Out-Null
try {
    New-Item -ItemType Directory -Path (Join-Path $tmpRepo2 "graphify-out") -Force | Out-Null
    "{}" | Set-Content (Join-Path $tmpRepo2 "graphify-out/graph.json") -Encoding UTF8
    $statusFile = Join-Path $tmpStatusBin "status.txt"
    "param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$GitArgs)`r`nif (`$GitArgs[0] -eq 'status') { Get-Content -LiteralPath '$statusFile' }`r`nexit 0`r`n" | Set-Content -Path (Join-Path $tmpStatusBin "git.ps1") -Encoding ASCII
    $oldPathForStatus = $env:PATH
    $env:PATH = "$tmpStatusBin;$oldPathForStatus"

    $enabledCfg = @{ enabled = $true; auto_commit_refresh = $true; mode = "team"; team_out_dir = "graphify-out"; out_dir = ".felix/graphify" }
    " M graphify-out/graph.json" | Set-Content -Path $statusFile -Encoding ASCII
    $eligible = Test-GraphifyAutoCommitEligible -RepoRoot $tmpRepo2 -GraphifyConfig $enabledCfg
    Assert-True $eligible.Eligible "graph-only changes are eligible"

    " M graphify-out/graph.json`r`n M code.txt" | Set-Content -Path $statusFile -Encoding ASCII
    $blocked = Test-GraphifyAutoCommitEligible -RepoRoot $tmpRepo2 -GraphifyConfig $enabledCfg
    Assert-False $blocked.Eligible "non-graph changes block auto commit"
    Assert-Equal "non-graphify-changes" $blocked.Reason "blocked reason"
} finally {
    $env:PATH = $oldPathForStatus
    Remove-Item $tmpRepo2 -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpStatusBin -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n== Native wrapper shim ==" -ForegroundColor Cyan
$tmpShimRoot = Join-Path $testTempRoot "felix-graphify-shim-$(Get-Random)"
$tmpShimProject = Join-Path $tmpShimRoot "project"
$tmpShimBin = Join-Path $tmpShimRoot "bin"
New-Item -ItemType Directory -Path $tmpShimProject,$tmpShimBin,(Join-Path $tmpShimProject ".felix"),(Join-Path $tmpShimProject "graphify-out") -Force | Out-Null
try {
    @"
{
  "graphify": { "enabled": true, "mode": "team", "team_out_dir": "graphify-out" }
}
"@ | Set-Content -Path (Join-Path $tmpShimProject ".felix/config.json") -Encoding UTF8
    "{}" | Set-Content -Path (Join-Path $tmpShimProject "graphify-out/graph.json") -Encoding UTF8
    $capture = Join-Path $tmpShimRoot "args.txt"
    "param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$GraphifyArgs)`r`n(`$GraphifyArgs -join ' ') | Set-Content -LiteralPath '$capture' -Encoding UTF8`r`n" | Set-Content -Path (Join-Path $tmpShimBin "graphify.ps1") -Encoding ASCII
    $oldPath = $env:PATH
    $env:PATH = "$tmpShimBin;$oldPath"
    Invoke-GraphifyQueryLike -Verb "query" -SubArgs @("show auth flow") -RepoRoot $tmpShimProject
    $captured = Get-Content $capture -Raw
    Assert-True ($captured -match 'query "?show auth flow"?') "query wrapper invokes graphify query"
    Assert-True ($captured -match '--graph') "query wrapper includes graph path"
} finally {
    $env:PATH = $oldPath
    Remove-Item $tmpShimRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Remove-Item $testTempRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Graphify Tests: $script:TestsPassed passed, $script:TestsFailed failed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "=====================================" -ForegroundColor Cyan

if ($script:TestsFailed -gt 0) { exit 1 } else { exit 0 }







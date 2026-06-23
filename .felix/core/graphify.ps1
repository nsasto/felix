<#
.SYNOPSIS
Graphify integration helpers for Felix.

.DESCRIPTION
Keeps Graphify optional. Felix owns setup, status, command wrappers, and the
post-requirement graph refresh commit policy; Graphify remains the source of
truth for graph extraction and query behavior.
#>

$script:GRAPHIFY_SKILL_ID = "graphify-investigator"

function Get-GraphifyConfig {
    param($Config)

    $defaults = @{
        enabled             = $false
        skill_enabled       = $true
        mode                = "local"
        out_dir             = ".felix/graphify"
        team_out_dir        = "graphify-out"
        native_install      = $false
        post_commit_hook    = $false
        auto_commit_refresh = $false
        cache_policy        = "ignore"
    }

    if (-not $Config -or -not $Config.graphify) {
        return $defaults
    }

    $cfg = $Config.graphify
    return @{
        enabled             = if ($null -ne $cfg.enabled) { [bool]$cfg.enabled } else { $defaults.enabled }
        skill_enabled       = if ($null -ne $cfg.skill_enabled) { [bool]$cfg.skill_enabled } else { $defaults.skill_enabled }
        mode                = if ($cfg.mode) { [string]$cfg.mode } else { $defaults.mode }
        out_dir             = if ($cfg.out_dir) { [string]$cfg.out_dir } else { $defaults.out_dir }
        team_out_dir        = if ($cfg.team_out_dir) { [string]$cfg.team_out_dir } else { $defaults.team_out_dir }
        native_install      = if ($null -ne $cfg.native_install) { [bool]$cfg.native_install } else { $defaults.native_install }
        post_commit_hook    = if ($null -ne $cfg.post_commit_hook) { [bool]$cfg.post_commit_hook } else { $defaults.post_commit_hook }
        auto_commit_refresh = if ($null -ne $cfg.auto_commit_refresh) { [bool]$cfg.auto_commit_refresh } else { $defaults.auto_commit_refresh }
        cache_policy        = if ($cfg.cache_policy) { [string]$cfg.cache_policy } else { $defaults.cache_policy }
    }
}

function Resolve-GraphifyOutDir {
    param(
        [string]$RepoRoot,
        $GraphifyConfig
    )

    $rel = if ($GraphifyConfig.mode -eq "team") { $GraphifyConfig.team_out_dir } else { $GraphifyConfig.out_dir }
    $rel = if ([string]::IsNullOrWhiteSpace($rel)) { "graphify-out" } else { $rel.Trim() }
    if ([System.IO.Path]::IsPathRooted($rel)) {
        return [System.IO.Path]::GetFullPath($rel)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)))
}

function Get-GraphifyRelativeOutDir {
    param($GraphifyConfig)

    $rel = if ($GraphifyConfig.mode -eq "team") { $GraphifyConfig.team_out_dir } else { $GraphifyConfig.out_dir }
    if ([string]::IsNullOrWhiteSpace($rel)) { return "graphify-out" }
    return ($rel -replace '\\', '/').TrimEnd('/')
}

function Test-GraphifyAvailable {
    $cmd = Get-Command graphify -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Get-GraphifyExecutablePath {
    $cmd = Get-Command graphify -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    return $cmd.Source
}

function Test-GraphifyHookInstalled {
    param([string]$RepoRoot)

    $hookPath = $null
    try {
        $hookPath = (& git -C $RepoRoot rev-parse --git-path hooks/post-commit 2>$null | Select-Object -First 1)
    }
    catch {
        $hookPath = $null
    }

    if ([string]::IsNullOrWhiteSpace($hookPath)) {
        $hookPath = Join-Path $RepoRoot ".git/hooks/post-commit"
    }
    elseif (-not [System.IO.Path]::IsPathRooted($hookPath)) {
        $hookPath = Join-Path $RepoRoot $hookPath
    }

    if (-not (Test-Path $hookPath)) { return $false }
    $content = Get-Content $hookPath -Raw -ErrorAction SilentlyContinue
    return ($content -match "graphify")
}

function Test-GraphifyMergeDriverInstalled {
    param([string]$RepoRoot)

    try {
        $drivers = & git -C $RepoRoot config --get-regexp "^merge\..*\.driver$" 2>$null
        return ($LASTEXITCODE -eq 0 -and (($drivers -join "`n") -match "graphify"))
    }
    catch {
        return $false
    }
}

function Get-GraphifyGitStatus {
    param(
        [string]$RepoRoot,
        [string]$RelativeOutDir
    )

    $prefix = ($RelativeOutDir -replace '\\', '/').TrimEnd('/') + "/"
    Push-Location $RepoRoot
    try {
        $lines = @(git status --porcelain 2>$null)
    }
    catch {
        return @{ All = @(); Graphify = @(); NonGraphify = @() }
    }
    finally {
        Pop-Location
    }

    $graph = [System.Collections.ArrayList]@()
    $other = [System.Collections.ArrayList]@()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
        $path = $line.Substring(3).Trim('"') -replace '\\', '/'
        if ($path -like "$prefix*") {
            [void]$graph.Add($path)
        }
        else {
            [void]$other.Add($path)
        }
    }

    return @{
        All         = @($lines)
        Graphify   = $graph.ToArray()
        NonGraphify = $other.ToArray()
    }
}

function Ensure-GraphifyConfigInFile {
    param(
        [string]$ConfigPath,
        [string]$Mode = "local",
        [bool]$AutoCommitRefresh = $false,
        [string]$CachePolicy = "ignore",
        [bool]$PostCommitHook = $false
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $cfg.graphify) {
        $cfg | Add-Member -MemberType NoteProperty -Name "graphify" -Value ([pscustomobject]@{}) -Force
    }

    $g = $cfg.graphify
    $defaults = Get-GraphifyConfig -Config $cfg
    $g | Add-Member -MemberType NoteProperty -Name "enabled" -Value $true -Force
    $g | Add-Member -MemberType NoteProperty -Name "skill_enabled" -Value $true -Force
    $g | Add-Member -MemberType NoteProperty -Name "mode" -Value $Mode -Force
    $g | Add-Member -MemberType NoteProperty -Name "out_dir" -Value $defaults.out_dir -Force
    $g | Add-Member -MemberType NoteProperty -Name "team_out_dir" -Value $defaults.team_out_dir -Force
    $g | Add-Member -MemberType NoteProperty -Name "native_install" -Value $defaults.native_install -Force
    $g | Add-Member -MemberType NoteProperty -Name "post_commit_hook" -Value $PostCommitHook -Force
    $g | Add-Member -MemberType NoteProperty -Name "auto_commit_refresh" -Value $AutoCommitRefresh -Force
    $g | Add-Member -MemberType NoteProperty -Name "cache_policy" -Value $CachePolicy -Force

    $cfg | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
    return $cfg
}

function Ensure-GraphifySkill {
    param([string]$RepoRoot)

    $skillDir = Join-Path $RepoRoot ".felix/skills/$script:GRAPHIFY_SKILL_ID"
    if (-not (Test-Path $skillDir)) {
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    }

    $manifest = @"
{
  "id": "graphify-investigator",
  "name": "Graphify Investigator",
  "description": "Use Graphify as an optional query-first codebase investigation tool.",
  "version": "1.0.0",
  "prompt": "prompt.md",
  "always": true,
  "triggers": {
    "commands": ["run", "run-next", "loop", "explore"],
    "applyTo": [],
    "tags": ["architecture", "graphify", "investigation"],
    "keywords": ["architecture", "call flow", "dependency", "dependencies", "trace", "symbol", "Graphify", "graphify"]
  }
}
"@

    $prompt = @"
## Graphify Investigator

Graphify is an optional repository knowledge graph. Use it when it will reduce broad searching or repeated file reads, especially for architecture, call-flow, dependency, symbol, and cross-file relationship questions.

Prefer these commands before large grep/read sweeps:

- `felix graphify query "<question>"`
- `felix graphify path "<from>" "<to>"`
- `felix graphify explain "<symbol>"`

If the Felix wrapper is unavailable, use the native equivalents: `graphify query`, `graphify path`, and `graphify explain`.

Do not paste or read `GRAPH_REPORT.md` wholesale into the prompt. Query the graph, inspect the small set of files it identifies, and fall back to normal Felix search when Graphify is missing, stale, or not useful.
"@

    Set-Content -Path (Join-Path $skillDir "skill.json") -Value $manifest -Encoding UTF8
    Set-Content -Path (Join-Path $skillDir "prompt.md") -Value $prompt -Encoding UTF8
    return $skillDir
}

function Add-GraphifyGitIgnoreRules {
    param(
        [string]$RepoRoot,
        [string]$TeamOutDir = "graphify-out",
        [string]$CachePolicy = "ignore"
    )

    $gitignore = Join-Path $RepoRoot ".gitignore"
    if (-not (Test-Path $gitignore)) {
        New-Item -ItemType File -Path $gitignore -Force | Out-Null
    }

    $rel = ($TeamOutDir -replace '\\', '/').TrimEnd('/')
    $rules = [System.Collections.ArrayList]@()
    [void]$rules.Add("$rel/cost.json")
    if ($CachePolicy -eq "ignore") {
        [void]$rules.Add("$rel/cache/")
    }

    $content = Get-Content $gitignore -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = "" }
    $changed = $false
    foreach ($rule in $rules) {
        if ($content -notmatch "(?m)^[ \t]*$([regex]::Escape($rule))[ \t]*$") {
            if (-not $content.EndsWith("`n")) { $content += "`n" }
            if ($content -notmatch "(?m)^# Graphify local artifacts$") {
                $content += "`n# Graphify local artifacts`n"
            }
            $content += "$rule`n"
            $changed = $true
        }
    }

    if ($changed) {
        Set-Content -Path $gitignore -Value $content -Encoding UTF8
    }

    return @{ Changed = $changed; Path = $gitignore; Rules = $rules.ToArray() }
}

function Test-GraphifyAutoCommitEligible {
    param(
        [string]$RepoRoot,
        $GraphifyConfig
    )

    if (-not $GraphifyConfig.enabled -or -not $GraphifyConfig.auto_commit_refresh) {
        return @{ Eligible = $false; Reason = "disabled"; GraphifyFiles = @(); NonGraphifyFiles = @() }
    }

    if ($GraphifyConfig.mode -ne "team") {
        return @{ Eligible = $false; Reason = "not-team-mode"; GraphifyFiles = @(); NonGraphifyFiles = @() }
    }

    $rel = Get-GraphifyRelativeOutDir -GraphifyConfig $GraphifyConfig
    $status = Get-GraphifyGitStatus -RepoRoot $RepoRoot -RelativeOutDir $rel
    if ($status.Graphify.Count -eq 0) {
        return @{ Eligible = $false; Reason = "no-graphify-changes"; GraphifyFiles = @(); NonGraphifyFiles = $status.NonGraphify }
    }

    if ($status.NonGraphify.Count -gt 0) {
        return @{ Eligible = $false; Reason = "non-graphify-changes"; GraphifyFiles = $status.Graphify; NonGraphifyFiles = $status.NonGraphify }
    }

    return @{ Eligible = $true; Reason = "graphify-only"; GraphifyFiles = $status.Graphify; NonGraphifyFiles = @() }
}

function Invoke-GraphifyAutoRefreshCommit {
    param(
        [string]$RepoRoot,
        $Config
    )

    $graphifyConfig = Get-GraphifyConfig -Config $Config
    $eligibility = Test-GraphifyAutoCommitEligible -RepoRoot $RepoRoot -GraphifyConfig $graphifyConfig
    if (-not $eligibility.Eligible) {
        if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
            Emit-Log -Level "debug" -Message "Graphify auto refresh commit skipped: $($eligibility.Reason)" -Component "graphify"
        }
        return @{ Committed = $false; Reason = $eligibility.Reason }
    }

    $rel = Get-GraphifyRelativeOutDir -GraphifyConfig $graphifyConfig
    Push-Location $RepoRoot
    $oldSkip = $env:GRAPHIFY_SKIP_HOOK
    try {
        $env:GRAPHIFY_SKIP_HOOK = "1"
        git add -- $rel 2>&1 | Out-Null
        git commit --no-verify -m "chore(graphify): refresh graph" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "git commit failed"
        }
        $sha = git rev-parse --short HEAD 2>$null
        if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
            Emit-Log -Level "info" -Message "Graphify refresh committed: $sha" -Component "graphify"
        }
        return @{ Committed = $true; Reason = "committed"; Sha = $sha }
    }
    catch {
        if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
            Emit-Log -Level "warn" -Message "Graphify auto refresh commit failed: $($_.Exception.Message)" -Component "graphify"
        }
        return @{ Committed = $false; Reason = "commit-failed"; Error = $_.Exception.Message }
    }
    finally {
        if ($null -eq $oldSkip) { Remove-Item Env:\GRAPHIFY_SKIP_HOOK -ErrorAction SilentlyContinue }
        else { $env:GRAPHIFY_SKIP_HOOK = $oldSkip }
        Pop-Location
    }
}



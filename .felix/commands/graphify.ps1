<#
.SYNOPSIS
felix graphify - optional Graphify setup and query wrappers.
#>

function Invoke-Graphify {
    param(
        [string[]]$CmdArgs = @(),
        [string]$RepoRoot = (Get-Location).Path,
        [string]$FelixRoot = (Join-Path $PSScriptRoot "..")
    )

    . "$PSScriptRoot\..\core\graphify.ps1"
    . "$PSScriptRoot\..\core\config-loader.ps1"

    $subCmd = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { "status" }
    $subArgs = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

    switch ($subCmd) {
        "status"  { Invoke-GraphifyStatus -SubArgs $subArgs -RepoRoot $RepoRoot }
        "setup"   { Invoke-GraphifySetup -SubArgs $subArgs -RepoRoot $RepoRoot }
        "build"   { Invoke-GraphifyBuild -SubArgs $subArgs -RepoRoot $RepoRoot }
        "update"  { Invoke-GraphifyUpdate -SubArgs $subArgs -RepoRoot $RepoRoot }
        "query"   { Invoke-GraphifyQueryLike -Verb "query" -SubArgs $subArgs -RepoRoot $RepoRoot }
        "path"    { Invoke-GraphifyQueryLike -Verb "path" -SubArgs $subArgs -RepoRoot $RepoRoot }
        "explain" { Invoke-GraphifyQueryLike -Verb "explain" -SubArgs $subArgs -RepoRoot $RepoRoot }
        default {
            Write-Host "Unknown graphify subcommand: $subCmd" -ForegroundColor Red
            Write-Host "Valid: status, setup, build, update, query, path, explain" -ForegroundColor Gray
            exit 1
        }
    }
}

function Get-GraphifyRuntime {
    param([string]$RepoRoot)

    $configPath = Join-Path $RepoRoot ".felix/config.json"
    $cfg = if (Test-Path $configPath) { Get-FelixConfig -ConfigFile $configPath } else { [pscustomobject]@{} }
    $graphCfg = Get-GraphifyConfig -Config $cfg
    $outDir = Resolve-GraphifyOutDir -RepoRoot $RepoRoot -GraphifyConfig $graphCfg
    return @{
        ConfigPath = $configPath
        Config     = $cfg
        Graphify   = $graphCfg
        OutDir     = $outDir
        GraphJson  = Join-Path $outDir "graph.json"
    }
}

function Invoke-GraphifyStatus {
    param([string[]]$SubArgs, [string]$RepoRoot)

    $json = $SubArgs -contains "--json"
    $rt = Get-GraphifyRuntime -RepoRoot $RepoRoot
    $rel = Get-GraphifyRelativeOutDir -GraphifyConfig $rt.Graphify
    $status = Get-GraphifyGitStatus -RepoRoot $RepoRoot -RelativeOutDir $rel
    $skillPath = Join-Path $RepoRoot ".felix/skills/$script:GRAPHIFY_SKILL_ID/skill.json"
    $result = [ordered]@{
        enabled = [bool]$rt.Graphify.enabled
        mode = [string]$rt.Graphify.mode
        graphify_available = (Test-GraphifyAvailable)
        graphify_executable = (Get-GraphifyExecutablePath)
        skill_installed = (Test-Path $skillPath)
        out_dir = $rt.OutDir
        graph_json = $rt.GraphJson
        graph_exists = (Test-Path $rt.GraphJson)
        post_commit_hook_installed = (Test-GraphifyHookInstalled -RepoRoot $RepoRoot)
        merge_driver_installed = (Test-GraphifyMergeDriverInstalled -RepoRoot $RepoRoot)
        graphify_changed_files = @($status.Graphify)
        non_graphify_changed_files = @($status.NonGraphify)
        cache_policy = [string]$rt.Graphify.cache_policy
        auto_commit_refresh = [bool]$rt.Graphify.auto_commit_refresh
    }

    if ($json) {
        $result | ConvertTo-Json -Depth 5
        return
    }

    Write-Host ""
    Write-Host "Graphify status" -ForegroundColor Cyan
    Write-Host "  Enabled             : $($result.enabled)"
    Write-Host "  Mode                : $($result.mode)"
    Write-Host "  Executable          : $(if ($result.graphify_available) { $result.graphify_executable } else { 'not found' })"
    Write-Host "  Felix skill         : $(if ($result.skill_installed) { 'installed' } else { 'missing' })"
    Write-Host "  Graph               : $(if ($result.graph_exists) { $result.graph_json } else { "missing ($($result.graph_json))" })"
    Write-Host "  Post-commit hook    : $($result.post_commit_hook_installed)"
    Write-Host "  Merge driver        : $($result.merge_driver_installed)"
    Write-Host "  Graph changes       : $($result.graphify_changed_files.Count)"
    Write-Host "  Other changes       : $($result.non_graphify_changed_files.Count)"
    Write-Host ""
}

function Invoke-GraphifySetup {
    param([string[]]$SubArgs, [string]$RepoRoot)

    $mode = "local"
    $native = $false
    $harness = $null
    $autoCommit = $false
    $cachePolicy = "ignore"

    for ($i = 0; $i -lt $SubArgs.Count; $i++) {
        switch ($SubArgs[$i]) {
            "--local" { $mode = "local" }
            "--team" { $mode = "team" }
            "--native" { $native = $true }
            "--auto-commit-refresh" { $autoCommit = $true }
            "--commit-cache" { $cachePolicy = "commit" }
            "--ignore-cache" { $cachePolicy = "ignore" }
            "--harness" {
                $i++
                if ($i -lt $SubArgs.Count) { $harness = $SubArgs[$i] }
            }
        }
    }

    $configPath = Join-Path $RepoRoot ".felix/config.json"
    $postCommit = ($mode -eq "team")
    $cfg = Ensure-GraphifyConfigInFile -ConfigPath $configPath -Mode $mode -AutoCommitRefresh:$autoCommit -CachePolicy $cachePolicy -PostCommitHook:$postCommit
    $graphCfg = Get-GraphifyConfig -Config $cfg
    $skillDir = Ensure-GraphifySkill -RepoRoot $RepoRoot

    Write-Host "  [ok] Installed Felix Graphify skill: $skillDir" -ForegroundColor Green
    Write-Host "  [ok] Updated graphify config ($mode mode)" -ForegroundColor Green

    if ($mode -eq "team") {
        $ignore = Add-GraphifyGitIgnoreRules -RepoRoot $RepoRoot -TeamOutDir $graphCfg.team_out_dir -CachePolicy $cachePolicy
        if ($ignore.Changed) {
            Write-Host "  [ok] Updated .gitignore for Graphify local artifacts" -ForegroundColor Green
        }
        else {
            Write-Host "  [ok] .gitignore already has Graphify local artifact rules" -ForegroundColor Green
        }

        if (Test-GraphifyAvailable) {
            Invoke-GraphifyNative -RepoRoot $RepoRoot -GraphifyConfig $graphCfg -Arguments @("hook", "install")
        }
        else {
            Write-Host "  [warn] graphify executable not found; skipped 'graphify hook install'" -ForegroundColor Yellow
            Write-Host "         Install with: uv tool install graphifyy" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Team graph workflow:" -ForegroundColor Cyan
        Write-Host "  graphify ."
        Write-Host "  git add $($graphCfg.team_out_dir) .gitignore"
        Write-Host "  git commit -m `"chore(graphify): add team graph`""
        Write-Host ""
    }

    if ($native) {
        Invoke-GraphifyNativeInstall -RepoRoot $RepoRoot -Harness $harness
    }
}

function Invoke-GraphifyBuild {
    param([string[]]$SubArgs, [string]$RepoRoot)

    $rt = Get-GraphifyRuntime -RepoRoot $RepoRoot
    $target = if ($SubArgs.Count -gt 0 -and -not $SubArgs[0].StartsWith("--")) { $SubArgs[0] } else { "." }
    $extra = if ($SubArgs.Count -gt 1 -and $SubArgs[0] -eq $target) { $SubArgs[1..($SubArgs.Count - 1)] } elseif ($SubArgs.Count -gt 0 -and $SubArgs[0] -eq $target) { @() } else { $SubArgs }
    Invoke-GraphifyNative -RepoRoot $RepoRoot -GraphifyConfig $rt.Graphify -Arguments (@($target) + @($extra))
}

function Invoke-GraphifyUpdate {
    param([string[]]$SubArgs, [string]$RepoRoot)

    $rt = Get-GraphifyRuntime -RepoRoot $RepoRoot
    $target = if ($SubArgs.Count -gt 0 -and -not $SubArgs[0].StartsWith("--")) { $SubArgs[0] } else { "." }
    $extra = if ($SubArgs.Count -gt 1 -and $SubArgs[0] -eq $target) { $SubArgs[1..($SubArgs.Count - 1)] } elseif ($SubArgs.Count -gt 0 -and $SubArgs[0] -eq $target) { @() } else { $SubArgs }
    Invoke-GraphifyNative -RepoRoot $RepoRoot -GraphifyConfig $rt.Graphify -Arguments (@($target, "--update") + @($extra))
}

function Invoke-GraphifyQueryLike {
    param(
        [string]$Verb,
        [string[]]$SubArgs,
        [string]$RepoRoot
    )

    if (-not $SubArgs -or $SubArgs.Count -eq 0) {
        Write-Host "Usage: felix graphify $Verb <args>" -ForegroundColor Red
        exit 1
    }

    $rt = Get-GraphifyRuntime -RepoRoot $RepoRoot
    $args = @($Verb) + @($SubArgs)
    if (Test-Path $rt.GraphJson) {
        $args += @("--graph", $rt.GraphJson)
    }
    Invoke-GraphifyNative -RepoRoot $RepoRoot -GraphifyConfig $rt.Graphify -Arguments $args
}

function Invoke-GraphifyNativeInstall {
    param([string]$RepoRoot, [string]$Harness)

    if (-not (Test-GraphifyAvailable)) {
        Write-Host "  [warn] graphify executable not found; skipped native install" -ForegroundColor Yellow
        return
    }

    $targets = if ([string]::IsNullOrWhiteSpace($Harness) -or $Harness -eq "all") {
        @("codex", "claude", "droid", "gemini", "copilot")
    }
    else {
        @($Harness)
    }

    foreach ($target in $targets) {
        Write-Host "  Installing native Graphify guidance for $target..." -ForegroundColor Cyan
        & graphify install --project --platform $target
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [warn] native install failed for $target" -ForegroundColor Yellow
        }
    }
}

function Invoke-GraphifyNative {
    param(
        [string]$RepoRoot,
        $GraphifyConfig,
        [string[]]$Arguments
    )

    if (-not (Test-GraphifyAvailable)) {
        Write-Host "Graphify is not installed or not on PATH." -ForegroundColor Red
        Write-Host "Install with: uv tool install graphifyy" -ForegroundColor Gray
        exit 1
    }

    $outDir = Resolve-GraphifyOutDir -RepoRoot $RepoRoot -GraphifyConfig $GraphifyConfig
    $oldOut = $env:GRAPHIFY_OUT
    $oldLog = $env:GRAPHIFY_QUERY_LOG_DISABLE
    Push-Location $RepoRoot
    try {
        $env:GRAPHIFY_OUT = $outDir
        if ([string]::IsNullOrWhiteSpace($oldLog)) { $env:GRAPHIFY_QUERY_LOG_DISABLE = "1" }
        & graphify @Arguments
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
    finally {
        if ($null -eq $oldOut) { Remove-Item Env:\GRAPHIFY_OUT -ErrorAction SilentlyContinue }
        else { $env:GRAPHIFY_OUT = $oldOut }

        if ($null -eq $oldLog) { Remove-Item Env:\GRAPHIFY_QUERY_LOG_DISABLE -ErrorAction SilentlyContinue }
        else { $env:GRAPHIFY_QUERY_LOG_DISABLE = $oldLog }
        Pop-Location
    }
}



<#
.SYNOPSIS
    Syncs functional CLI files and shared docs into ../felix-cloud
.DESCRIPTION
    Copies .felix code, scripts, commands, core modules, plugins, prompts,
    policies, tests, docs, and config templates into ../felix-cloud/.felix,
    plus selected repository-level documentation such as docs/CLI.md.
    Project-specific state (requirements.json, state.json, sessions.json,
    config.json, sync.log, outbox, .locks, __pycache__) is skipped.
.PARAMETER DryRun
    Show what would be copied without actually copying.
#>
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CloudRoot = Join-Path $PSScriptRoot '..\..\felix-cloud'

$Source = Join-Path $RepoRoot '.felix'
$Target = Join-Path $CloudRoot '.felix'

$Source = (Resolve-Path $Source).Path
if (-not (Test-Path $CloudRoot)) {
    Write-Error "Target not found: $CloudRoot"
    return
}
$CloudRoot = (Resolve-Path $CloudRoot).Path
$Target = (Resolve-Path $Target).Path

# --- Directories to sync (recursive) ---
$dirs = @(
    'bin'
    'cli'
    'commands'
    'core'
    'plugins'
    'policies'
    'prompts'
    'scripts'
    'tests'
)

# --- Individual files to sync ---
$files = @(
    'felix.ps1'
    'felix-cli.ps1'
    'felix-agent.ps1'
    'test-cli.ps1'
    'agent-models.json'
    'agent-templates.json'
    'agents.json'
    'config.json.example'
    'config.md'
    'version.txt'
    'README.md'
    'AI_CLI_CHEATSHEET.md'
    'FELIX-ARCHITECTURE.md'
)

# --- Repository-level file mappings to sync ---
$repoFileMappings = @(
    @{
        Source = Join-Path $RepoRoot 'docs\CLI.md'
        Target = Join-Path $CloudRoot 'docs\CLI.md'
    }
)

$copied = 0
$skipped = 0

function Copy-If-Newer {
    param([string]$Src, [string]$Dst)

    $srcItem = Get-Item $Src
    if (Test-Path $Dst) {
        $dstItem = Get-Item $Dst
        if ($srcItem.LastWriteTimeUtc -le $dstItem.LastWriteTimeUtc -and
            $srcItem.Length -eq $dstItem.Length) {
            $script:skipped++
            return
        }
    }

    $dstDir = Split-Path $Dst -Parent
    if (-not (Test-Path $dstDir)) {
        if ($DryRun) {
            Write-Host "  MKDIR  $dstDir" -ForegroundColor DarkGray
        }
        else {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
    }

    if ($DryRun) {
        Write-Host "  COPY   $Src -> $Dst" -ForegroundColor Cyan
    }
    else {
        Copy-Item -Path $Src -Destination $Dst -Force
    }
    $script:copied++
}

Write-Host "`nSyncing .felix functional files" -ForegroundColor Green
Write-Host "  From: $Source"
Write-Host "  To:   $Target`n"

if ($DryRun) { Write-Host "  [DRY RUN]`n" -ForegroundColor Yellow }

# Sync directories
foreach ($dir in $dirs) {
    $srcDir = Join-Path $Source $dir
    if (-not (Test-Path $srcDir)) { continue }

    $items = Get-ChildItem -Path $srcDir -Recurse -File
    foreach ($item in $items) {
        $rel = $item.FullName.Substring($Source.Length)
        $dst = Join-Path $Target $rel
        Copy-If-Newer $item.FullName $dst
    }
}

# Sync individual files
foreach ($f in $files) {
    $src = Join-Path $Source $f
    if (-not (Test-Path $src)) { continue }
    $dst = Join-Path $Target $f
    Copy-If-Newer $src $dst
}

# Sync repository-level files
foreach ($mapping in $repoFileMappings) {
    if (-not (Test-Path $mapping.Source)) { continue }
    Copy-If-Newer $mapping.Source $mapping.Target
}

Write-Host "Done: $copied copied, $skipped unchanged." -ForegroundColor Green
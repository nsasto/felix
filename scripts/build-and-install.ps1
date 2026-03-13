# Builds felix.exe (with embedded scripts) and runs 'felix install' to deploy
# to %LOCALAPPDATA%\Programs\Felix\ and add to User PATH.
#
# Usage:
#   .\scripts\build-and-install.ps1               # default: framework-dependent build
#   .\scripts\build-and-install.ps1 -SelfContained # bundle .NET runtime (~80MB, no prereqs)

param(
    [switch]$SelfContained,
    [switch]$Force,      # pass --force to 'felix install' to re-extract even if version matches
    [switch]$SkipCheck   # skip command-registry consistency check
)

$ErrorActionPreference = "Stop"

$repoRoot  = Split-Path -Parent $PSScriptRoot
$csprojDir = Join-Path $repoRoot "src\Felix.Cli"
$outDir    = Join-Path $repoRoot ".felix\bin"

Write-Host ""
Write-Host "Felix CLI Build + Install" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

# ── 0. Command registry consistency check ───────────────────────────────────
if (-not $SkipCheck) {
    Write-Host "[CHECK] Verifying command registry consistency..." -ForegroundColor Yellow
    & "$PSScriptRoot\check-command-registry.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Fix the issues above, then re-run. Use -SkipCheck to bypass." -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# ── 1. Build ────────────────────────────────────────────────────────────────
Write-Host "[BUILD] Compiling felix.exe..." -ForegroundColor Yellow

$publishArgs = @(
    "publish", $csprojDir,
    "-c", "Release",
    "-o", $outDir
)

if ($SelfContained) {
    $publishArgs += "-r", "win-x64", "--self-contained", "true", "-p:PublishSingleFile=true"
    Write-Host "  Mode: self-contained win-x64 (no .NET runtime required on target)" -ForegroundColor Gray
}
else {
    $publishArgs += "--self-contained", "false"
    Write-Host "  Mode: framework-dependent (requires .NET 10 on target)" -ForegroundColor Gray
}

Push-Location $csprojDir
try {
    dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit code $LASTEXITCODE)" }
}
finally {
    Pop-Location
}

$exePath = Join-Path $outDir "felix.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "[ERROR] Build completed but felix.exe not found at: $exePath" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Built: $exePath" -ForegroundColor Green
Write-Host ""

# ── 2. Install (extracted scripts + PATH) via the exe itself ──────────────
Write-Host "[INSTALL] Running: felix install" -ForegroundColor Yellow
$installArgs = @("install")
if ($Force) { $installArgs += "--force" }

& $exePath @installArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] 'felix install' failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

# ── 3. Clean up legacy profile entries (written by old install-cli.ps1) ──────
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    $before = Get-Content $profilePath -Raw
    $after  = ($before -split "`n" | Where-Object {
        $_ -notmatch '# Felix CLI' -and
        $_ -notmatch [regex]::Escape('\.felix') -and
        $_ -notmatch 'Set-Alias\s+felix'
    }) -join "`n"
    if ($after -ne $before) {
        Set-Content $profilePath $after -Encoding UTF8
        Write-Host "[CLEANUP] Removed legacy felix entries from PowerShell profile" -ForegroundColor Yellow
        Write-Host "          ($profilePath)" -ForegroundColor Gray
    }
}


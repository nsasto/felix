# Felix CLI - Windows Bootstrapper
#
# One-liner install (run in PowerShell):
#   irm https://www.felix.io/install.ps1 | iex
#
# With options:
#   $env:FELIX_VERSION = "0.9.0"; irm https://www.felix.io/install.ps1 | iex
#
# Or download and run locally:
#   .\scripts\install.ps1 [-Version 0.9.0] [-BaseUrl https://...] [-Force]

param(
    [string]$Version = "",
    [string]$BaseUrl = "https://www.felix.io/releases",   # <-- fill in your server URL
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Rid = "win-x64"

# Resolve version param (allow override via environment variable)
if (-not $Version) {
    $Version = if ($env:FELIX_VERSION) { $env:FELIX_VERSION } else { "latest" }
}

function Get-LatestVersion([string]$Base) {
    try {
        return (Invoke-RestMethod "$Base/latest.txt" -UseBasicParsing -ErrorAction Stop).Trim()
    } catch {
        throw "Could not fetch latest version from $Base/latest.txt`nUse -Version to specify a version explicitly."
    }
}

if ($Version -eq "latest") {
    Write-Host "Checking latest version ..." -ForegroundColor Gray
    $Version = Get-LatestVersion $BaseUrl
}

$ZipName = "felix-$Version-$Rid.zip"
$ZipUrl  = "$BaseUrl/$ZipName"
$CsuUrl  = "$BaseUrl/checksums-$Version.txt"
$Tmp     = Join-Path $env:TEMP "felix-install-$(([System.Guid]::NewGuid().ToString('N').Substring(0,8)))"

New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

try {
    Write-Host ""
    Write-Host "Felix CLI Installer" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "  Version : $Version" -ForegroundColor Gray
    Write-Host "  Platform: $Rid"     -ForegroundColor Gray
    Write-Host ""

    # ── Download ─────────────────────────────────────────────────────────────
    $ZipPath = Join-Path $Tmp $ZipName
    Write-Host "Downloading $ZipUrl ..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing

    # ── Checksum verification (best-effort) ───────────────────────────────────
    try {
        $CsuText = (Invoke-RestMethod $CsuUrl -UseBasicParsing -ErrorAction Stop).Trim()
        $Expected = ($CsuText -split "`n" |
                     Where-Object { $_ -like "*$ZipName*" } |
                     Select-Object -First 1) -replace "\s.*", ""
        if ($Expected) {
            $Actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
            if ($Actual -ne $Expected) {
                throw "SHA256 mismatch!`n  Expected : $Expected`n  Got      : $Actual"
            }
            Write-Host "  [OK] Checksum verified" -ForegroundColor Green
        }
    } catch [System.Net.WebException] {
        Write-Host "  [WARN] Could not fetch checksums - skipping verification" -ForegroundColor Yellow
    }

    # ── Extract ───────────────────────────────────────────────────────────────
    $ExtractDir = Join-Path $Tmp "x"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $ExePath = Join-Path $ExtractDir "felix.exe"
    if (-not (Test-Path $ExePath)) {
        throw "felix.exe not found in downloaded archive."
    }

    # ── Copy to install dir ───────────────────────────────────────────────────
    $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Felix"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $DestExe = Join-Path $InstallDir "felix.exe"
    Copy-Item $ExePath $DestExe -Force
    Write-Host "  [OK] felix.exe installed to $InstallDir" -ForegroundColor Green

    # ── Add install dir to User PATH (idempotent) ─────────────────────────────
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $UserPath) { $UserPath = "" }
    $Segments = $UserPath -split ";" | Where-Object { $_ -ne "" }
    if (-not ($Segments | Where-Object { $_.TrimEnd("\") -ieq $InstallDir.TrimEnd("\") })) {
        [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
        Write-Host "  [OK] Added $InstallDir to User PATH" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Already in PATH" -ForegroundColor Green
    }

} finally {
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "  Restart your terminal, then run:" -ForegroundColor Gray
Write-Host "    felix setup" -ForegroundColor Cyan
Write-Host "  in your project directory to initialise Felix."
Write-Host ""

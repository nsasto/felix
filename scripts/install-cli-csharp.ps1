# Quick installer for Felix.Cli.exe - Adds .felix\bin to User PATH

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$felixBin = Join-Path (Join-Path $repoRoot ".felix") "bin"
$exePath = Join-Path $felixBin "Felix.Cli.exe"

Write-Host ""
Write-Host "Felix CLI Installation" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""

# Check if exe exists
if (-not (Test-Path $exePath)) {
    Write-Host "[ERROR] Felix.Cli.exe not found at:" -ForegroundColor Red
    Write-Host "  $exePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Build it first:" -ForegroundColor Yellow
    Write-Host "  cd src/Felix.Cli" -ForegroundColor Yellow
    Write-Host "  dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o ../../.felix/bin" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Found Felix.Cli.exe" -ForegroundColor Green

# Check if already in PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$felixBin*") {
    Write-Host "[OK] Already in PATH" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage: Felix.Cli.exe --help" -ForegroundColor Cyan
    exit 0
}

# Add to PATH
Write-Host "[ADD] Adding to User PATH..." -ForegroundColor Yellow
Write-Host "  $felixBin" -ForegroundColor Gray

$newPath = "$userPath;$felixBin"
[Environment]::SetEnvironmentVariable("Path", $newPath, "User")

Write-Host "[OK] Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Action required:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal" -ForegroundColor Yellow
Write-Host "  2. Test: Felix.Cli.exe --help" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: felix.ps1 still works and is the canonical implementation" -ForegroundColor Gray
Write-Host ""

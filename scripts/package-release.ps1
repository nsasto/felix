# Builds self-contained release artifacts for win-x64, linux-x64, osx-arm64, osx-x64.
# Each artifact is a zip containing only the felix binary — engine scripts are embedded inside it.
# For win-x64, also builds a GUI installer (.exe) via Inno Setup if iscc.exe is in PATH.
#
# Usage:
#   .\scripts\package-release.ps1                  # all platforms
#   .\scripts\package-release.ps1 -Rid win-x64     # single platform
#   .\scripts\package-release.ps1 -SkipInstaller    # skip Inno Setup even if iscc is found
#
# Output:
#   .release\felix-{version}-{rid}.zip
#   .release\felix-{version}-setup.exe   (win-x64 only, requires Inno Setup)
#   .release\checksums-{version}.txt
#
# macOS .dmg:
#   Run scripts/package-dmg.sh on macOS after this script builds osx-* artifacts.

param(
    [string]$Rid = "",        # empty = build all platforms
    [switch]$SkipInstaller    # skip Inno Setup .exe even if iscc.exe is found
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$csprojDir = Join-Path $repoRoot "src\Felix.Cli"
$releaseDir = Join-Path $repoRoot ".release"
$version = (Get-Content (Join-Path $repoRoot ".felix\version.txt") -Raw -ErrorAction Stop).Trim()

$allRids = @("win-x64", "linux-x64", "osx-arm64", "osx-x64")
$rids = if ($Rid) { @($Rid) } else { $allRids }

Write-Host ""
Write-Host "Felix Release Packager  v$version" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Platforms : $($rids -join ', ')" -ForegroundColor Gray
Write-Host "  Output    : $releaseDir"          -ForegroundColor Gray
Write-Host ""

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

$checksums = [System.Collections.Generic.List[string]]::new()

foreach ($rid in $rids) {
    $outDir = Join-Path $releaseDir $rid
    $zipName = "felix-$version-$rid.zip"
    $zipPath = Join-Path $releaseDir $zipName

    Write-Host "[BUILD] dotnet publish  $rid ..." -ForegroundColor Yellow

    $publishArgs = @(
        "publish", $csprojDir,
        "-c", "Release",
        "-r", $rid,
        "--self-contained", "true",
        "-p:PublishSingleFile=true",
        "-p:PublishTrimmed=false",
        "-o", $outDir
    )

    dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $rid (exit $LASTEXITCODE)" }

    $exeName = if ($rid.StartsWith("win")) { "felix.exe" } else { "felix" }
    $exePath = Join-Path $outDir $exeName
    if (-not (Test-Path $exePath)) {
        throw "Expected binary not found after publish: $exePath"
    }

    Write-Host "[PACK]  $zipName ..." -ForegroundColor Yellow
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $exePath -DestinationPath $zipPath

    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    $checksums.Add("$hash  $zipName")

    Write-Host "  [OK]  $zipName  ($sizeMB MB)" -ForegroundColor Green
    Write-Host "        SHA256: $hash"           -ForegroundColor Gray
    Write-Host ""

    # ── Windows GUI installer (Inno Setup, win-x64 only) ──────────────────────
    if ($rid -eq "win-x64" -and -not $SkipInstaller) {
        # Locate iscc.exe: try PATH first, then default Inno Setup install locations.
        $isccCmd = Get-Command "iscc" -ErrorAction SilentlyContinue
        $isccExe = if ($isccCmd) { $isccCmd.Source } else { $null }

        if (-not $isccExe) {
            $pf86 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)
            $candidate = Join-Path $pf86 "Inno Setup 6\iscc.exe"
            if (Test-Path $candidate) { $isccExe = $candidate }
        }

        $issFile = Join-Path $repoRoot "scripts\felix-installer.iss"
        $setupName = "felix-$version-setup.exe"

        if ($isccExe -and (Test-Path $issFile)) {
            Write-Host "[INNO]  $setupName ..." -ForegroundColor Yellow

            $innoArgs = @(
                "/DVersion=$version",
                "/DSourceDir=$outDir",
                "/DOutputDir=$releaseDir",
                $issFile
            )
            & $isccExe @innoArgs
            if ($LASTEXITCODE -ne 0) { throw "Inno Setup build failed (exit $LASTEXITCODE)" }

            $setupPath = Join-Path $releaseDir $setupName
            $setupHash = (Get-FileHash $setupPath -Algorithm SHA256).Hash
            $setupSizeMB = [math]::Round((Get-Item $setupPath).Length / 1MB, 1)
            $checksums.Add("$setupHash  $setupName")

            Write-Host "  [OK]  $setupName  ($setupSizeMB MB)" -ForegroundColor Green
            Write-Host "        SHA256: $setupHash" -ForegroundColor Gray
            Write-Host ""
        }
        else {
            Write-Host "  [SKIP] Inno Setup not found - skipping GUI installer" -ForegroundColor Yellow
            Write-Host "         Install from https://jrsoftware.org/isinfo.php, then re-run." -ForegroundColor Gray
            Write-Host "         Or pass -SkipInstaller to suppress this warning." -ForegroundColor Gray
            Write-Host ""
        }
    }

    # Clean intermediate publish output
    Remove-Item $outDir -Recurse -Force
}

# Write checksums file
$checksumFile = Join-Path $releaseDir "checksums-$version.txt"
$checksums | Set-Content $checksumFile -Encoding UTF8

Write-Host "Checksums  -> $checksumFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Upload these files to your release server:" -ForegroundColor Green
foreach ($c in $checksums) {
    Write-Host "  $($c.Split('  ')[1])"
}
Write-Host "  checksums-$version.txt"
Write-Host ""
Write-Host "Then update latest.txt on the server to: $version" -ForegroundColor Yellow
Write-Host ""

# ── macOS .dmg reminder ───────────────────────────────────────────────────────
$builtMac = $rids | Where-Object { $_ -like "osx-*" }
if ($builtMac) {
    Write-Host "macOS users:" -ForegroundColor Cyan
    Write-Host "  Run  scripts/package-dmg.sh  on a macOS machine to build .dmg installers:" -ForegroundColor Gray
    foreach ($macRid in $builtMac) {
        Write-Host "    ./scripts/package-dmg.sh --version $version --rid $macRid" -ForegroundColor Gray
    }
    Write-Host ""
}

#!/usr/bin/env pwsh
<#
.SYNOPSIS
Install Felix CLI to PATH and create aliases

.DESCRIPTION
Adds the .felix folder to the user's PowerShell profile PATH and creates convenient aliases.
Supports both PowerShell 5.1 (Windows PowerShell) and PowerShell 7+ (cross-platform).

.PARAMETER Uninstall
Remove Felix CLI from PATH and delete aliases

.EXAMPLE
.\scripts\install-cli.ps1

.EXAMPLE
.\scripts\install-cli.ps1 -Uninstall
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Determine repository root
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FelixFolder = Join-Path $RepoRoot ".felix"

# Determine PowerShell profile path
$ProfilePath = $PROFILE.CurrentUserAllHosts
$ProfileDir = Split-Path -Parent $ProfilePath

function Add-ToProfile {
    param([string]$Content)
    
    if (-not (Test-Path $ProfilePath)) {
        Write-Host "Creating PowerShell profile: $ProfilePath" -ForegroundColor Cyan
        New-Item -Path $ProfilePath -ItemType File -Force | Out-Null
    }
    
    $existingContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
    
    if ($existingContent -and $existingContent.Contains($Content)) {
        Write-Host "[OK] Already in profile" -ForegroundColor Green
        return $false
    }
    
    Add-Content -Path $ProfilePath -Value "`n$Content"
    return $true
}

function Remove-FromProfile {
    param([string]$Pattern)
    
    if (-not (Test-Path $ProfilePath)) {
        Write-Host "Profile does not exist: $ProfilePath" -ForegroundColor Yellow
        return
    }
    
    $content = Get-Content $ProfilePath -Raw
    $newContent = $content -replace "(?m)^.*$Pattern.*`r?`n", ""
    
    if ($content -ne $newContent) {
        Set-Content -Path $ProfilePath -Value $newContent -NoNewline
        Write-Host "[OK] Removed from profile" -ForegroundColor Green
    }
    else {
        Write-Host "[!] Not found in profile" -ForegroundColor Yellow
    }
}

if ($Uninstall) {
    Write-Host ""
    Write-Host "Uninstalling Felix CLI..." -ForegroundColor Cyan
    Write-Host ""
    
    # Remove PATH addition
    Write-Host "Removing PATH entry..." -ForegroundColor Yellow
    Remove-FromProfile [regex]::Escape($FelixFolder)
    
    # Remove alias
    Write-Host "Removing felix alias..." -ForegroundColor Yellow
    Remove-FromProfile "Set-Alias felix"
    
    Write-Host ""
    Write-Host "[OK] Uninstall complete" -ForegroundColor Green
    Write-Host ""
    Write-Host "Restart your PowerShell session for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}
else {
    Write-Host ""
    Write-Host "Installing Felix CLI..." -ForegroundColor Cyan
    Write-Host ""
    
    # Verify felix.ps1 exists
    $felixScript = Join-Path $FelixFolder "felix.ps1"
    if (-not (Test-Path $felixScript)) {
        Write-Error "Felix script not found: $felixScript"
        exit 1
    }
    
    # Add .felix to PATH
    Write-Host "Adding .felix folder to PATH..." -ForegroundColor Yellow
    $pathEntry = "`n# Felix CLI - Add .felix folder to PATH`n`$env:PATH = `"$FelixFolder;`$env:PATH`""
    $addedPath = Add-ToProfile -Content $pathEntry
    
    if ($addedPath) {
        Write-Host "[OK] Added to profile" -ForegroundColor Green
    }
    
    # Create felix alias
    Write-Host "Creating 'felix' alias..." -ForegroundColor Yellow
    $aliasEntry = "`n# Felix CLI - Create felix alias`nSet-Alias felix '$felixScript'"
    $addedAlias = Add-ToProfile -Content $aliasEntry
    
    if ($addedAlias) {
        Write-Host "[OK] Added to profile" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Installation Details:" -ForegroundColor Cyan
    Write-Host "  Profile: $ProfilePath" -ForegroundColor Gray
    Write-Host "  Felix Folder: $FelixFolder" -ForegroundColor Gray
    Write-Host "  Felix Script: $felixScript" -ForegroundColor Gray
    Write-Host ""
    
    # Verify installation
    Write-Host "Verifying installation..." -ForegroundColor Yellow
    
    # Load profile in current session
    & $felixScript help | Out-Null
    
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
        Write-Host "[OK] Installation verified" -ForegroundColor Green
    }
    else {
        Write-Host "[!] Verification failed (this may be normal)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "[OK] Installation complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Restart your PowerShell session (or run: . `$PROFILE)"
    Write-Host "  2. Run 'felix help' to see available commands"
    Write-Host "  3. Try 'felix status' to view requirements"
    Write-Host "  4. Run 'felix run S-0001' to execute a requirement"
    Write-Host ""
    Write-Host "For immediate use (without restart):"
    Write-Host "  .felix\felix.ps1 help" -ForegroundColor Yellow
    Write-Host ""
}

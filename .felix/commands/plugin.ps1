<#
.SYNOPSIS
felix plugin  -  manage Felix plugins (Phase AS1).

.DESCRIPTION
Subcommands: install, list, remove, info
Plugins land in .felix/plugins/<id>/
#>

function Invoke-Plugin {
    param(
        [string[]]$Args,
        [string]$RepoRoot = (Get-Location).Path,
        [string]$FelixRoot = $PSScriptRoot
    )

    $subCmd = if ($Args.Count -gt 0) { $Args[0] } else { "list" }
    $subArgs = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }

    $pluginsDir = Join-Path $RepoRoot ".felix\plugins"
    $hashesPath = Join-Path $pluginsDir "manifest-hashes.json"

    switch ($subCmd) {
        "install" {
            if (-not $subArgs) {
                Write-Host "Usage: felix plugin install <source>" -ForegroundColor Red
                Write-Host "  source: ./local/path, https://url.zip, git+https://..., or <name>" -ForegroundColor Gray
                exit 1
            }
            $source = $subArgs[0]
            Invoke-PluginInstall -Source $source -PluginsDir $pluginsDir -HashesPath $hashesPath
        }
        "list" {
            $remote = $subArgs -contains "--remote"
            $json   = $subArgs -contains "--json"
            Invoke-PluginList -PluginsDir $pluginsDir -Remote:$remote -Json:$json
        }
        "remove" {
            if (-not $subArgs) {
                Write-Host "Usage: felix plugin remove <id>" -ForegroundColor Red; exit 1
            }
            Invoke-PluginRemove -Id $subArgs[0] -PluginsDir $pluginsDir -HashesPath $hashesPath
        }
        "info" {
            if (-not $subArgs) {
                Write-Host "Usage: felix plugin info <id>" -ForegroundColor Red; exit 1
            }
            Invoke-PluginInfo -Id $subArgs[0] -PluginsDir $pluginsDir
        }
        default {
            Write-Host "Unknown plugin subcommand: $subCmd" -ForegroundColor Red
            Write-Host "Valid: install, list, remove, info" -ForegroundColor Gray
            exit 1
        }
    }
}

function Invoke-PluginInstall {
    param([string]$Source, [string]$PluginsDir, [string]$HashesPath)

    # Determine install method
    if ($Source -like "git+https://*") {
        Write-Host "Git clone install not yet implemented. Clone manually to $PluginsDir/<id>/" -ForegroundColor Yellow
        exit 1
    }
    if ($Source -like "https://*") {
        Write-Host "URL install not yet implemented. Download and extract manually to $PluginsDir/<id>/" -ForegroundColor Yellow
        exit 1
    }

    # Filesystem copy
    $srcPath = [System.IO.Path]::GetFullPath($Source)
    if (-not (Test-Path $srcPath)) {
        Write-Host "Source path not found: $srcPath" -ForegroundColor Red; exit 1
    }

    # Read plugin.json manifest
    $manifestPath = Join-Path $srcPath "plugin.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Host "No plugin.json found in $srcPath" -ForegroundColor Red; exit 1
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $id = $manifest.id
    if (-not $id) {
        Write-Host "plugin.json missing 'id' field" -ForegroundColor Red; exit 1
    }

    $destDir = Join-Path $PluginsDir $id
    if (Test-Path $destDir) {
        Write-Host "Plugin '$id' already installed. Remove it first with: felix plugin remove $id" -ForegroundColor Yellow
        exit 1
    }

    # Copy plugin files
    Copy-Item -Path $srcPath -Destination $destDir -Recurse -Force
    Write-Host "  [ok] Installed plugin '$id' to $destDir" -ForegroundColor Green

    # Update manifest-hashes.json
    $bytes = [System.IO.File]::ReadAllBytes($manifestPath)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $hash  = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""

    $hashes = @{}
    if (Test-Path $HashesPath) {
        $hashes = Get-Content $HashesPath -Raw | ConvertFrom-Json -AsHashtable
    }
    $hashes[$id] = $hash
    $hashes | ConvertTo-Json | Set-Content $HashesPath -Encoding UTF8
    Write-Host "  [ok] Updated manifest-hashes.json" -ForegroundColor Green
}

function Invoke-PluginList {
    param([string]$PluginsDir, [switch]$Remote, [switch]$Json)

    if ($Remote) {
        Write-Host "Remote plugin index requires Phase G (Marketplace). Not yet available." -ForegroundColor Yellow
        exit 0
    }

    $plugins = [System.Collections.ArrayList]@()
    if (Test-Path $PluginsDir) {
        Get-ChildItem -Path $PluginsDir -Directory | ForEach-Object {
            $manifestPath = Join-Path $_.FullName "plugin.json"
            if (Test-Path $manifestPath) {
                $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                [void]$plugins.Add(@{
                    id      = $m.id
                    name    = if ($m.name) { $m.name } else { $m.id }
                    version = if ($m.version) { $m.version } else { "?" }
                    path    = $_.FullName
                })
            }
        }
    }

    if ($Json) {
        $plugins.ToArray() | ConvertTo-Json -Depth 3
        return
    }

    if ($plugins.Count -eq 0) {
        Write-Host "No plugins installed. Use 'felix plugin install <source>'." -ForegroundColor Gray
        return
    }

    Write-Host ""
    Write-Host "Installed plugins:" -ForegroundColor Cyan
    foreach ($p in $plugins) {
        Write-Host "  $($p.id) ($($p.version))  -  $($p.name)" -ForegroundColor White
    }
    Write-Host ""
}

function Invoke-PluginRemove {
    param([string]$Id, [string]$PluginsDir, [string]$HashesPath)

    $pluginDir = Join-Path $PluginsDir $Id
    if (-not (Test-Path $pluginDir)) {
        Write-Host "Plugin '$Id' not found." -ForegroundColor Red; exit 1
    }

    Remove-Item -Path $pluginDir -Recurse -Force
    Write-Host "  [ok] Removed plugin '$Id'" -ForegroundColor Green

    # Update manifest-hashes.json
    if (Test-Path $HashesPath) {
        $hashes = Get-Content $HashesPath -Raw | ConvertFrom-Json -AsHashtable
        $hashes.Remove($Id)
        $hashes | ConvertTo-Json | Set-Content $HashesPath -Encoding UTF8
    }
}

function Invoke-PluginInfo {
    param([string]$Id, [string]$PluginsDir)

    $manifestPath = Join-Path $PluginsDir "$Id\plugin.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Host "Plugin '$Id' not found." -ForegroundColor Red; exit 1
    }

    Get-Content $manifestPath | Write-Host
}

<#
.SYNOPSIS
felix plugin  -  manage Felix plugins (Phase AS1 + G3).

.DESCRIPTION
Subcommands: install, list, remove, info, update
Plugins land in .felix/plugins/<id>/
Phase G adds: list --remote, update [<id>|--all] [--dry-run] [--channel stable|beta]
#>

function Invoke-Plugin {
    param(
        [string[]]$CmdArgs = @(),
        [string]$RepoRoot = (Get-Location).Path,
        [string]$FelixRoot = $PSScriptRoot
    )

    $subCmd  = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { "list" }
    $subArgs = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

    $pluginsDir = Join-Path $RepoRoot ".felix\plugins"
    $hashesPath = Join-Path $pluginsDir "manifest-hashes.json"

    switch ($subCmd) {
        "install" {
            if (-not $subArgs) {
                Write-Host "Usage: felix plugin install <source>" -ForegroundColor Red
                Write-Host "  source: ./local/path, https://url.zip, git+https://..., or <name> (from index)" -ForegroundColor Gray
                exit 1
            }
            $source = $subArgs[0]
            $channel = "stable"
            for ($i = 1; $i -lt $subArgs.Count; $i++) {
                if ($subArgs[$i] -eq "--channel" -and $i+1 -lt $subArgs.Count) { $channel = $subArgs[$i+1] }
            }
            Invoke-PluginInstall -Source $source -PluginsDir $pluginsDir -HashesPath $hashesPath -Channel $channel -RepoRoot $RepoRoot
        }
        "list" {
            $remote  = $subArgs -icontains "--remote"
            $json    = $subArgs -icontains "--json"
            $channel = "stable"
            for ($i = 0; $i -lt $subArgs.Count; $i++) {
                if ($subArgs[$i] -eq "--channel" -and $i+1 -lt $subArgs.Count) { $channel = $subArgs[$i+1] }
            }
            Invoke-PluginList -PluginsDir $pluginsDir -Remote:$remote -Json:$json -Channel $channel -RepoRoot $RepoRoot
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
        "update" {
            $all    = $subArgs -icontains "--all"
            $dryRun = $subArgs -icontains "--dry-run"
            $channel = "stable"
            for ($i = 0; $i -lt $subArgs.Count; $i++) {
                if ($subArgs[$i] -eq "--channel" -and $i+1 -lt $subArgs.Count) { $channel = $subArgs[$i+1] }
            }
            $targetId = $subArgs | Where-Object { -not $_.StartsWith("--") } | Select-Object -First 1
            Invoke-PluginUpdate -PluginsDir $pluginsDir -HashesPath $hashesPath -TargetId $targetId -All:$all -DryRun:$dryRun -Channel $channel -RepoRoot $RepoRoot
        }
        default {
            Write-Host "Unknown plugin subcommand: $subCmd" -ForegroundColor Red
            Write-Host "Valid: install, list, remove, info, update" -ForegroundColor Gray
            exit 1
        }
    }
}

function Invoke-PluginInstall {
    param(
        [string]$Source,
        [string]$PluginsDir,
        [string]$HashesPath,
        [string]$Channel = "stable",
        [string]$RepoRoot = (Get-Location).Path
    )

    # Determine install method
    if ($Source -like "git+https://*") {
        Write-Host "Git clone install not yet implemented. Clone manually to $PluginsDir/<id>/" -ForegroundColor Yellow
        exit 1
    }
    if ($Source -like "https://*") {
        # Direct URL download + extract (no signature check on raw URL)
        Write-Host "  Downloading from $Source ..." -ForegroundColor Cyan
        $tmp = [System.IO.Path]::GetTempFileName() + ".zip"
        try {
            Invoke-WebRequest -Uri $Source -OutFile $tmp -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
            # Determine id from zip contents (look for plugin.json)
            $extractTmp = Join-Path $env:TEMP "felix-plugin-extract-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            Expand-Archive -Path $tmp -DestinationPath $extractTmp -Force
            $mFile = Get-ChildItem -Path $extractTmp -Recurse -Filter "plugin.json" | Select-Object -First 1
            if (-not $mFile) { Write-Host "No plugin.json found in archive." -ForegroundColor Red; exit 1 }
            $m  = Get-Content $mFile.FullName -Raw | ConvertFrom-Json
            $id = $m.id
            if (-not $id) { Write-Host "plugin.json missing 'id' field" -ForegroundColor Red; exit 1 }
            $destDir = Join-Path $PluginsDir $id
            if (Test-Path $destDir) {
                Write-Host "Plugin '$id' already installed. Remove it first with: felix plugin remove $id" -ForegroundColor Yellow
                exit 1
            }
            # Move extracted content to dest
            $srcDir = $mFile.Directory.FullName
            Copy-Item -Path $srcDir -Destination $destDir -Recurse -Force
            Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-Host "  [ok] Installed plugin '$id' to $destDir" -ForegroundColor Green
            return
        } catch {
            Write-Host "  Download failed: $_" -ForegroundColor Red
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }

    # Named install from index
    if ($Source -notlike "./*" -and $Source -notlike "*\*" -and $Source -notlike "*/*" -and -not (Test-Path $Source)) {
        . "$PSScriptRoot\..\core\index-client.ps1"
        $distCfg = Get-DistributionConfig -ProjectPath $RepoRoot
        Write-Host "  Looking up '$Source' in index ($($distCfg.index_url))..." -ForegroundColor Cyan
        $index = Get-PluginIndex -Url $distCfg.index_url
        if (-not $index) { exit 1 }
        $entry = $index.plugins | Where-Object { $_.id -eq $Source } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "  Plugin '$Source' not found in index." -ForegroundColor Red
            Write-Host "  Use 'felix plugin list --remote' to see available plugins." -ForegroundColor Gray
            exit 1
        }
        $felixVer = Get-InstalledFelixVersion -ProjectPath $RepoRoot
        $ver = Get-CompatibleVersion -Versions @($entry.versions) -InstalledFelixVersion $felixVer -Channel $Channel
        if (-not $ver) {
            Write-Host "  No compatible $Channel version of '$Source' for Felix $felixVer." -ForegroundColor Red
            exit 1
        }
        $destDir = Join-Path $PluginsDir $Source
        if (Test-Path $destDir) {
            Write-Host "Plugin '$Source' already installed. Remove it first with: felix plugin remove $Source" -ForegroundColor Yellow
            exit 1
        }
        $ok = Install-FromIndexEntry -Id $Source -VersionEntry $ver -DestDir $destDir
        if (-not $ok) { exit 1 }

        # Update manifest-hashes.json
        $manifestPath = Join-Path $destDir "plugin.json"
        if (Test-Path $manifestPath) {
            $bytes = [System.IO.File]::ReadAllBytes($manifestPath)
            $sha   = [System.Security.Cryptography.SHA256]::Create()
            $hash  = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
            $hashes = @{}
            if (Test-Path $HashesPath) { $hashes = Get-Content $HashesPath -Raw | ConvertFrom-Json -AsHashtable }
            $hashes[$Source] = $hash
            $hashes | ConvertTo-Json | Set-Content $HashesPath -Encoding UTF8
        }
        return
    }

    # Filesystem copy (local path)
    $srcPath = [System.IO.Path]::GetFullPath($Source)
    if (-not (Test-Path $srcPath)) {
        Write-Host "Source path not found: $srcPath" -ForegroundColor Red; exit 1
    }

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

    Copy-Item -Path $srcPath -Destination $destDir -Recurse -Force
    Write-Host "  [ok] Installed plugin '$id' to $destDir" -ForegroundColor Green

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
    param(
        [string]$PluginsDir,
        [switch]$Remote,
        [switch]$Json,
        [string]$Channel = "stable",
        [string]$RepoRoot = (Get-Location).Path
    )

    # Collect installed plugins
    $installed = [System.Collections.ArrayList]@()
    if (-not $PluginsDir) { $PluginsDir = Join-Path $RepoRoot ".felix\plugins" }
    if (Test-Path $PluginsDir) {
        Get-ChildItem -Path $PluginsDir -Directory | ForEach-Object {
            $manifestPath = Join-Path $_.FullName "plugin.json"
            if (Test-Path $manifestPath) {
                $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                [void]$installed.Add([PSCustomObject]@{
                    id      = $m.id
                    name    = if ($m.name)    { $m.name }    else { $m.id }
                    version = if ($m.version) { $m.version } else { "?" }
                    path    = $_.FullName
                    remote  = $null
                })
            }
        }
    }

    if ($Remote) {
        . "$PSScriptRoot\..\core\index-client.ps1"
        $distCfg = Get-DistributionConfig -ProjectPath $RepoRoot
        Write-Host "  Querying index: $($distCfg.index_url)" -ForegroundColor Cyan
        $index = Get-PluginIndex -Url $distCfg.index_url
        if (-not $index) {
            Write-Host "  Could not fetch remote index." -ForegroundColor Red
            # Fall through to show local only
        } else {
            $felixVer = Get-InstalledFelixVersion -ProjectPath $RepoRoot

            # Merge remote data into local list
            $installedIds = @($installed | ForEach-Object { $_.id })
            foreach ($entry in $index.plugins) {
                $ver = Get-CompatibleVersion -Versions @($entry.versions) -InstalledFelixVersion $felixVer -Channel $Channel
                $latestVer = if ($ver) { $ver.v } else { "n/a" }
                $existing = $installed | Where-Object { $_.id -eq $entry.id } | Select-Object -First 1
                if ($existing) {
                    $existing.remote = $latestVer
                } else {
                    [void]$installed.Add([PSCustomObject]@{
                        id      = $entry.id
                        name    = if ($entry.name) { $entry.name } else { $entry.id }
                        version = "(not installed)"
                        path    = $null
                        remote  = $latestVer
                    })
                }
            }
        }
    }

    if ($Json) {
        $installed.ToArray() | ConvertTo-Json -Depth 3
        return
    }

    if ($installed.Count -eq 0) {
        Write-Host "No plugins installed. Use 'felix plugin install <name-or-path>'." -ForegroundColor Gray
        return
    }

    Write-Host ""
    if ($Remote) {
        Write-Host "Plugins (installed + available from index):" -ForegroundColor Cyan
    } else {
        Write-Host "Installed plugins:" -ForegroundColor Cyan
    }
    foreach ($p in $installed) {
        $status = if ($p.path) { "installed" } else { "available" }
        $remoteInfo = if ($Remote -and $p.remote) { "  [latest: $($p.remote)]" } else { "" }
        $color = if ($p.path) { "White" } else { "Gray" }
        Write-Host "  $($p.id) v$($p.version)  ($status)$remoteInfo  -  $($p.name)" -ForegroundColor $color
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

function Invoke-PluginUpdate {
    <#
    .SYNOPSIS
    Checks installed plugins against the remote index and updates them.
    Protects against downgrade and felix_min incompatibility.
    #>
    param(
        [string]$PluginsDir,
        [string]$HashesPath,
        [string]$TargetId,
        [switch]$All,
        [switch]$DryRun,
        [string]$Channel = "stable",
        [string]$RepoRoot = (Get-Location).Path
    )

    if (-not $TargetId -and -not $All) {
        Write-Host "Usage: felix plugin update <id>     - update a specific plugin" -ForegroundColor Cyan
        Write-Host "       felix plugin update --all    - update all installed plugins" -ForegroundColor Cyan
        Write-Host "       felix plugin update --dry-run - preview only" -ForegroundColor Gray
        exit 0
    }

    . "$PSScriptRoot\..\core\index-client.ps1"
    $distCfg  = Get-DistributionConfig -ProjectPath $RepoRoot
    $index    = Get-PluginIndex -Url $distCfg.index_url
    if (-not $index) { exit 1 }

    $felixVer = Get-InstalledFelixVersion -ProjectPath $RepoRoot

    # Collect plugins to check
    $toCheck = [System.Collections.ArrayList]@()
    if (-not $PluginsDir) { $PluginsDir = Join-Path $RepoRoot ".felix\plugins" }
    if (-not (Test-Path $PluginsDir)) {
        Write-Host "No plugins installed." -ForegroundColor Gray; return
    }
    Get-ChildItem -Path $PluginsDir -Directory | ForEach-Object {
        $mPath = Join-Path $_.FullName "plugin.json"
        if (Test-Path $mPath) {
            $m = Get-Content $mPath -Raw | ConvertFrom-Json
            if (-not $TargetId -or $m.id -eq $TargetId) {
                [void]$toCheck.Add([PSCustomObject]@{
                    id        = $m.id
                    installed = if ($m.version) { $m.version } else { "0.0.0" }
                    path      = $_.FullName
                })
            }
        }
    }

    if ($TargetId -and $toCheck.Count -eq 0) {
        Write-Host "Plugin '$TargetId' is not installed." -ForegroundColor Red; exit 1
    }

    $updated = 0
    $skipped = 0

    Write-Host ""
    if ($DryRun) { Write-Host "felix plugin update (dry-run)" -ForegroundColor Cyan }
    else         { Write-Host "felix plugin update"           -ForegroundColor Cyan }
    Write-Host ""

    foreach ($p in $toCheck) {
        $entry = $index.plugins | Where-Object { $_.id -eq $p.id } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "  $($p.id): not in index (skipped)" -ForegroundColor Gray
            $skipped++
            continue
        }

        $latestVer = Get-CompatibleVersion -Versions @($entry.versions) -InstalledFelixVersion $felixVer -Channel $Channel
        if (-not $latestVer) {
            Write-Host "  $($p.id): no compatible $Channel version for Felix $felixVer (skipped)" -ForegroundColor Gray
            $skipped++
            continue
        }

        $cmp = Compare-SemVer $latestVer.v $p.installed
        if ($cmp -le 0) {
            Write-Host "  $($p.id) v$($p.installed): up to date" -ForegroundColor Green
            $skipped++
            continue
        }

        Write-Host "  $($p.id): $($p.installed) -> $($latestVer.v)" -ForegroundColor Yellow

        if ($DryRun) {
            $updated++
            continue
        }

        $ok = Install-FromIndexEntry -Id $p.id -VersionEntry $latestVer -DestDir $p.path
        if ($ok) {
            # Re-hash manifest
            $mPath = Join-Path $p.path "plugin.json"
            if (Test-Path $mPath) {
                $bytes = [System.IO.File]::ReadAllBytes($mPath)
                $sha   = [System.Security.Cryptography.SHA256]::Create()
                $hash  = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
                $hashes = @{}
                if (Test-Path $HashesPath) { $hashes = Get-Content $HashesPath -Raw | ConvertFrom-Json -AsHashtable }
                $hashes[$p.id] = $hash
                $hashes | ConvertTo-Json | Set-Content $HashesPath -Encoding UTF8
            }
            $updated++
        }
    }

    Write-Host ""
    if ($DryRun) {
        Write-Host "  [dry-run] Would update: $updated plugin(s). Skipped: $skipped." -ForegroundColor Cyan
    } else {
        Write-Host "  Updated: $updated plugin(s). Skipped: $skipped." -ForegroundColor Green
    }
    Write-Host ""
}
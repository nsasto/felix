<#
.SYNOPSIS
Felix marketplace index client (Phase G).
Fetches plugins.json index and provides SHA256 verification helpers.

.DESCRIPTION
Used by 'felix plugin list --remote', 'felix plugin update', and 'felix skill install'.
Index URL is read from .felix/config.json#distribution.index_url.
Default: https://nsasto.github.io/felix/plugins.json
#>

$DEFAULT_INDEX_URL = "https://nsasto.github.io/felix/plugins.json"

function Get-DistributionConfig {
    <#
    .SYNOPSIS
    Reads distribution config from .felix/config.json.
    Returns hashtable with index_url and channels.
    #>
    param([string]$ProjectPath = (Get-Location).Path)

    $configPath = Join-Path $ProjectPath ".felix\config.json"
    $defaults = @{
        index_url = $DEFAULT_INDEX_URL
        channels  = @("stable")
    }
    if (-not (Test-Path $configPath)) { return $defaults }

    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($cfg.distribution) {
            if ($cfg.distribution.index_url) { $defaults.index_url = $cfg.distribution.index_url }
            if ($cfg.distribution.channels)  { $defaults.channels  = @($cfg.distribution.channels) }
        }
    } catch {}

    return $defaults
}

function Get-PluginIndex {
    <#
    .SYNOPSIS
    Fetches and parses the Felix plugin index from a URL or local path.
    Returns parsed index object, or $null on failure.
    #>
    param([string]$Url)

    if (-not $Url) { $Url = $DEFAULT_INDEX_URL }

    try {
        if ($Url -like "http*") {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            return $resp.Content | ConvertFrom-Json
        } else {
            # Local file path
            if (-not (Test-Path $Url)) {
                Write-Host "  Index not found: $Url" -ForegroundColor Red
                return $null
            }
            return Get-Content $Url -Raw | ConvertFrom-Json
        }
    } catch {
        Write-Host "  Failed to fetch index from $Url : $_" -ForegroundColor Red
        return $null
    }
}

function Get-InstalledFelixVersion {
    <#
    .SYNOPSIS
    Returns the installed Felix version string (e.g. "1.3.5").
    #>
    param([string]$ProjectPath = (Get-Location).Path)

    $versionFile = Join-Path $ProjectPath ".felix\version.txt"
    if (Test-Path $versionFile) {
        return (Get-Content $versionFile -Raw).Trim()
    }
    # Fallback: check csproj
    $csproj = Join-Path $ProjectPath "src\Felix.Cli\Felix.Cli.csproj"
    if (Test-Path $csproj) {
        $content = Get-Content $csproj -Raw
        if ($content -match '<Version>([^<]+)</Version>') { return $Matches[1].Trim() }
    }
    return "0.0.0"
}

function Compare-SemVer {
    <#
    .SYNOPSIS
    Compares two semver strings. Returns -1, 0, or 1.
    #>
    param([string]$A, [string]$B)

    function Parse-Parts {
        param([string]$v)
        $parts = ($v -replace '[^0-9.]','') -split '\.' | ForEach-Object { [int]$_ }
        while ($parts.Count -lt 3) { $parts += 0 }
        return $parts
    }

    $pa = Parse-Parts $A
    $pb = Parse-Parts $B

    for ($i = 0; $i -lt 3; $i++) {
        if ($pa[$i] -lt $pb[$i]) { return -1 }
        if ($pa[$i] -gt $pb[$i]) { return  1 }
    }
    return 0
}

function Get-CompatibleVersion {
    <#
    .SYNOPSIS
    From an index entry's versions array, returns the latest version compatible
    with the installed Felix version and the requested channel.
    Returns $null if no compatible version found.
    #>
    param(
        [array]$Versions,
        [string]$InstalledFelixVersion,
        [string]$Channel = "stable"
    )

    $compatible = $Versions |
        Where-Object {
            $ch = if ($_.channel) { $_.channel } else { "stable" }
            $ch -eq $Channel
        } |
        Where-Object {
            $minVer = if ($_.felix_min) { $_.felix_min } else { "0.0.0" }
            (Compare-SemVer $InstalledFelixVersion $minVer) -ge 0
        } |
        Sort-Object { $_.v } -Descending |
        Select-Object -First 1

    return $compatible
}

function Test-IndexEntrySha256 {
    <#
    .SYNOPSIS
    Downloads a URL to a temp file and verifies its SHA256 hash.
    Returns the local temp path on success, or $null on failure.
    #>
    param([string]$Url, [string]$ExpectedSha256)

    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tmpFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop

        $sha  = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
        $actual = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""

        if ($actual -ieq $ExpectedSha256) {
            return $tmpFile
        } else {
            Write-Host "  SHA256 mismatch for $Url" -ForegroundColor Red
            Write-Host "    expected: $ExpectedSha256" -ForegroundColor Red
            Write-Host "    actual  : $actual"         -ForegroundColor Red
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            return $null
        }
    } catch {
        Write-Host "  Download failed: $_" -ForegroundColor Red
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Install-FromIndexEntry {
    <#
    .SYNOPSIS
    Downloads, verifies, and extracts a plugin/skill from an index version entry.
    Destination dir is passed by the caller.
    #>
    param(
        [string]$Id,
        [PSCustomObject]$VersionEntry,
        [string]$DestDir
    )

    Write-Host "  Downloading $Id v$($VersionEntry.v) from index..." -ForegroundColor Cyan
    $tmpFile = Test-IndexEntrySha256 -Url $VersionEntry.url -ExpectedSha256 $VersionEntry.sha256
    if (-not $tmpFile) { return $false }

    # Extract ZIP
    try {
        if (Test-Path $DestDir) { Remove-Item $DestDir -Recurse -Force }
        Expand-Archive -Path $tmpFile -DestinationPath $DestDir -Force
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        Write-Host "  [ok] Installed $Id v$($VersionEntry.v) to $DestDir" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  Failed to extract: $_" -ForegroundColor Red
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

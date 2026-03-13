# Creates felix-scripts.zip for embedding in felix.exe
# Called by MSBuild BeforeBuild target.
#
# Usage:
#   create-bundle.ps1 -OutputPath <zip-path> -FelixRoot <path-to-.felix>

param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$FelixRoot
)

$ErrorActionPreference = "Stop"

$FelixRoot = (Resolve-Path $FelixRoot).Path

# Files to exclude (project-data and runtime artefacts, not engine scripts)
$excludeDirs = @(
    [IO.Path]::Combine($FelixRoot, "bin"),
    [IO.Path]::Combine($FelixRoot, "outbox"),
    [IO.Path]::Combine($FelixRoot, ".locks"),
    [IO.Path]::Combine($FelixRoot, "__pycache__"),
    [IO.Path]::Combine($FelixRoot, "tests"),
    [IO.Path]::Combine($FelixRoot, "scripts")
)
$excludeFiles = @(
    "requirements.json",
    "config.json",
    "state.json",
    "agents.json",
    "sync.log",
    "config.md",
    "AI_CLI_CHEATSHEET.md"
)

# Collect files
$files = Get-ChildItem -Path $FelixRoot -Recurse -File | Where-Object {
    $path = $_.FullName
    # Skip excluded directories
    foreach ($dir in $excludeDirs) {
        if ($path.StartsWith($dir + [IO.Path]::DirectorySeparatorChar) -or $path -eq $dir) {
            return $false
        }
    }
    # Skip excluded root-level files by name
    if ($_.DirectoryName -eq $FelixRoot -and $excludeFiles -contains $_.Name) {
        return $false
    }
    # Skip lock files and other runtime-only artefacts anywhere in the tree
    if ($_.Extension -eq ".lock" -or $_.Name -eq "run.lock") {
        return $false
    }
    return $true
}

# Ensure output directory exists
$outDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Delete old zip
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

# Create zip
# Load both assemblies to support Windows PowerShell 5.1 and PowerShell 7+
Add-Type -Assembly "System.IO.Compression"
Add-Type -Assembly "System.IO.Compression.FileSystem"
$zip = [IO.Compression.ZipFile]::Open($OutputPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        # Store with forward-slash paths relative to FelixRoot
        $relativePath = $file.FullName.Substring($FelixRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, '/')
        $entryName = $relativePath -replace '\\', '/'
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

Write-Host "  Bundled $($files.Count) files → $OutputPath"

# Warn if any engine file is newer than version.txt (untracked bump)
$versionFile = Join-Path $FelixRoot "version.txt"
if (Test-Path $versionFile) {
    $versionTime = (Get-Item $versionFile).LastWriteTimeUtc
    $trackedExtensions = @('.ps1', '.json', '.md')
    $newerFile = Get-ChildItem -Path $FelixRoot -Recurse -File |
    Where-Object { $_.FullName -ne $versionFile -and ($trackedExtensions -contains $_.Extension) -and $_.LastWriteTimeUtc -gt $versionTime } |
    Select-Object -First 1
    if ($newerFile) {
        $rel = $newerFile.FullName.Substring($FelixRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
        Write-Host "  [WARN] version.txt may need a bump - '$rel' is newer than version.txt"
    }
}

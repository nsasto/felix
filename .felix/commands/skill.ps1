<#
.SYNOPSIS
felix skill - manage Felix skills (Phase B4 + G5).

.DESCRIPTION
Subcommands: list, show, enable, disable, install
Skills live in .felix/skills/<id>/ (repo scope) and %USERPROFILE%/.felix/skills/<id>/ (user scope).
Phase G adds: install <name|path|url|git> from index.
#>

function Invoke-Skill {
    param(
        [string[]]$CmdArgs = @(),
        [string]$RepoRoot = (Get-Location).Path
    )

    $subCmd  = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { "list" }
    $subArgs = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

    . "$PSScriptRoot\..\core\skill-loader.ps1"

    switch ($subCmd) {
        "list"    { Invoke-SkillList    -SubArgs $subArgs -RepoRoot $RepoRoot }
        "show"    { Invoke-SkillShow    -SubArgs $subArgs -RepoRoot $RepoRoot }
        "enable"  { Invoke-SkillEnable  -SubArgs $subArgs -RepoRoot $RepoRoot -Enable $true }
        "disable" { Invoke-SkillEnable  -SubArgs $subArgs -RepoRoot $RepoRoot -Enable $false }
        "install" { Invoke-SkillInstall -SubArgs $subArgs -RepoRoot $RepoRoot }
        default {
            Write-Host "Unknown skill subcommand: $subCmd" -ForegroundColor Red
            Write-Host "Valid: list, show, enable, disable, install" -ForegroundColor Gray
            exit 1
        }
    }
}

function Invoke-SkillInstall {
    param([string[]]$SubArgs, [string]$RepoRoot)

    if (-not $SubArgs) {
        Write-Host "Usage: felix skill install <source>" -ForegroundColor Red
        Write-Host "  source: ./local/path, https://url.zip, git+https://..., or <name> (from index)" -ForegroundColor Gray
        exit 1
    }

    $source  = $SubArgs[0]
    $channel = "stable"
    $scope   = "repo"  # default to repo scope
    for ($i = 1; $i -lt $SubArgs.Count; $i++) {
        if ($SubArgs[$i] -eq "--channel" -and $i+1 -lt $SubArgs.Count) { $channel = $SubArgs[$i+1] }
        if ($SubArgs[$i] -eq "--scope"   -and $i+1 -lt $SubArgs.Count) { $scope   = $SubArgs[$i+1] }
    }

    $skillsDir = if ($scope -eq "user") {
        Join-Path ([System.Environment]::GetFolderPath("UserProfile")) ".felix\skills"
    } else {
        Join-Path $RepoRoot ".felix\skills"
    }

    if (-not (Test-Path $skillsDir)) {
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    }

    if ($source -like "git+https://*") {
        Write-Host "Git clone install not yet implemented. Clone manually to $skillsDir/<id>/" -ForegroundColor Yellow
        exit 1
    }

    if ($source -like "https://*") {
        Write-Host "  Downloading from $source ..." -ForegroundColor Cyan
        $tmp = [System.IO.Path]::GetTempFileName() + ".zip"
        try {
            Invoke-WebRequest -Uri $source -OutFile $tmp -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
            $extractTmp = Join-Path $env:TEMP "felix-skill-extract-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            Expand-Archive -Path $tmp -DestinationPath $extractTmp -Force
            $mFile = Get-ChildItem -Path $extractTmp -Recurse -Filter "skill.json" | Select-Object -First 1
            if (-not $mFile) { Write-Host "No skill.json found in archive." -ForegroundColor Red; exit 1 }
            $m  = Get-Content $mFile.FullName -Raw | ConvertFrom-Json
            $id = $m.id
            if (-not $id) { Write-Host "skill.json missing 'id' field" -ForegroundColor Red; exit 1 }
            $destDir = Join-Path $skillsDir $id
            if (Test-Path $destDir) {
                Write-Host "Skill '$id' already installed in $scope scope." -ForegroundColor Yellow; exit 1
            }
            Copy-Item -Path $mFile.Directory.FullName -Destination $destDir -Recurse -Force
            Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-Host "  [ok] Installed skill '$id' to $destDir" -ForegroundColor Green
        } catch {
            Write-Host "  Download failed: $_" -ForegroundColor Red
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            exit 1
        }
        return
    }

    # Named install from index
    if ($source -notlike "./*" -and $source -notlike "*\*" -and $source -notlike "*/*" -and -not (Test-Path $source)) {
        . "$PSScriptRoot\..\core\index-client.ps1"
        $distCfg = Get-DistributionConfig -ProjectPath $RepoRoot
        Write-Host "  Looking up '$source' in index ($($distCfg.index_url))..." -ForegroundColor Cyan
        $index = Get-PluginIndex -Url $distCfg.index_url
        if (-not $index) { exit 1 }
        $entry = $index.skills | Where-Object { $_.id -eq $source } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "  Skill '$source' not found in index." -ForegroundColor Red
            Write-Host "  Use 'felix skill list --remote' to see available skills." -ForegroundColor Gray
            exit 1
        }
        $felixVer = Get-InstalledFelixVersion -ProjectPath $RepoRoot
        $ver = Get-CompatibleVersion -Versions @($entry.versions) -InstalledFelixVersion $felixVer -Channel $channel
        if (-not $ver) {
            Write-Host "  No compatible $channel version of '$source' for Felix $felixVer." -ForegroundColor Red
            exit 1
        }
        $destDir = Join-Path $skillsDir $source
        if (Test-Path $destDir) {
            Write-Host "Skill '$source' already installed. Remove it first." -ForegroundColor Yellow; exit 1
        }
        $ok = Install-FromIndexEntry -Id $source -VersionEntry $ver -DestDir $destDir
        if (-not $ok) { exit 1 }
        return
    }

    # Local path copy
    $srcPath = [System.IO.Path]::GetFullPath($source)
    if (-not (Test-Path $srcPath)) {
        Write-Host "Source path not found: $srcPath" -ForegroundColor Red; exit 1
    }
    $manifestPath = Join-Path $srcPath "skill.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Host "No skill.json found in $srcPath" -ForegroundColor Red; exit 1
    }
    $m  = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $id = $m.id
    if (-not $id) { Write-Host "skill.json missing 'id' field" -ForegroundColor Red; exit 1 }
    $destDir = Join-Path $skillsDir $id
    if (Test-Path $destDir) {
        Write-Host "Skill '$id' already installed in $scope scope." -ForegroundColor Yellow; exit 1
    }
    Copy-Item -Path $srcPath -Destination $destDir -Recurse -Force
    Write-Host "  [ok] Installed skill '$id' to $destDir" -ForegroundColor Green
}


function Get-AllSkillEntries {
    param([string]$RepoRoot)

    $repoSkillsDir = Join-Path $RepoRoot ".felix\skills"
    $userSkillsDir = Join-Path ([System.Environment]::GetFolderPath("UserProfile")) ".felix\skills"

    $configPath = Join-Path $RepoRoot ".felix\config.json"
    $disabled = @()
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($cfg.skills -and $cfg.skills.disabled) {
            $disabled = @($cfg.skills.disabled)
        }
    }

    $entries = [System.Collections.ArrayList]@()
    foreach ($pair in @(@{ Dir = $userSkillsDir; Scope = "user" }, @{ Dir = $repoSkillsDir; Scope = "repo" })) {
        if (-not (Test-Path $pair.Dir)) { continue }
        Get-ChildItem -Path $pair.Dir -Directory | ForEach-Object {
            $manifestPath = Join-Path $_.FullName "skill.json"
            if (Test-Path $manifestPath) {
                $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                [void]$entries.Add([PSCustomObject]@{
                    Id       = $m.id
                    Name     = if ($m.name) { $m.name } else { $m.id }
                    Version  = if ($m.version) { $m.version } else { "?" }
                    Scope    = $pair.Scope
                    Disabled = ($m.id -in $disabled)
                    Dir      = $_.FullName
                    Manifest = $m
                })
            }
        }
    }

    # Repo entries override user entries (keep last occurrence per id = repo wins)
    $byId = @{}
    foreach ($e in $entries) { $byId[$e.Id] = $e }
    return $byId.Values | Sort-Object Id
}

function Invoke-SkillList {
    param([string[]]$SubArgs, [string]$RepoRoot)

    $scope = "all"
    $json  = $false
    foreach ($a in $SubArgs) {
        if ($a -eq "--json") { $json = $true }
        if ($a -match "^--scope=?(.*)") { $scope = $Matches[1] }
    }

    $all = Get-AllSkillEntries -RepoRoot $RepoRoot
    $filtered = switch ($scope) {
        "repo" { $all | Where-Object { $_.Scope -eq "repo" } }
        "user" { $all | Where-Object { $_.Scope -eq "user" } }
        default { $all }
    }

    if ($json) {
        $filtered | Select-Object Id, Name, Version, Scope, Disabled | ConvertTo-Json -Depth 3
        return
    }

    Write-Host ""
    Write-Host "Skills ($scope scope):" -ForegroundColor Cyan
    foreach ($s in $filtered) {
        $status = if ($s.Disabled) { "[disabled]" } else { "" }
        $scopeTag = "[$($s.Scope)]"
        Write-Host ("  {0,-30} {1,-8} {2,-6} {3}" -f $s.Id, $s.Version, $scopeTag, $status) -ForegroundColor $(if ($s.Disabled) { "DarkGray" } else { "White" })
    }
    Write-Host ""
}

function Invoke-SkillShow {
    param([string[]]$SubArgs, [string]$RepoRoot)

    if (-not $SubArgs) {
        Write-Host "Usage: felix skill show <id>" -ForegroundColor Red; exit 1
    }
    $id = $SubArgs[0]
    $all = Get-AllSkillEntries -RepoRoot $RepoRoot
    $skill = $all | Where-Object { $_.Id -eq $id } | Select-Object -First 1

    if (-not $skill) {
        Write-Host "Skill '$id' not found." -ForegroundColor Red; exit 1
    }

    Write-Host ""
    Write-Host "Skill: $($skill.Name) ($id)" -ForegroundColor Cyan
    Write-Host "  Version : $($skill.Version)"
    Write-Host "  Scope   : $($skill.Scope)"
    Write-Host "  Enabled : $(if ($skill.Disabled) { 'no (disabled)' } else { 'yes' })"
    Write-Host "  Dir     : $($skill.Dir)"
    Write-Host ""

    $promptPath = Join-Path $skill.Dir $(if ($skill.Manifest.prompt) { $skill.Manifest.prompt } else { "prompt.md" })
    if (Test-Path $promptPath) {
        Write-Host "--- prompt.md ---" -ForegroundColor DarkGray
        Get-Content $promptPath | Write-Host
    }
}

function Invoke-SkillEnable {
    param([string[]]$SubArgs, [string]$RepoRoot, [bool]$Enable)

    if (-not $SubArgs) {
        $verb = if ($Enable) { "enable" } else { "disable" }
        Write-Host "Usage: felix skill $verb <id>" -ForegroundColor Red; exit 1
    }
    $id = $SubArgs[0]

    $configPath = Join-Path $RepoRoot ".felix\config.json"
    if (-not (Test-Path $configPath)) {
        Write-Host "No .felix/config.json found." -ForegroundColor Red; exit 1
    }

    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json

    # Ensure skills.disabled array exists
    if (-not $cfg.skills) {
        $cfg | Add-Member -MemberType NoteProperty -Name "skills" -Value ([PSCustomObject]@{ disabled = @() }) -Force
    }
    if (-not $cfg.skills.disabled) {
        $cfg.skills | Add-Member -MemberType NoteProperty -Name "disabled" -Value @() -Force
    }

    $disabledList = [System.Collections.ArrayList]@($cfg.skills.disabled)

    if ($Enable) {
        if ($disabledList.Contains($id)) {
            $disabledList.Remove($id)
            Write-Host "  Enabled skill '$id'" -ForegroundColor Green
        } else {
            Write-Host "  Skill '$id' is already enabled." -ForegroundColor Gray
        }
    } else {
        if (-not $disabledList.Contains($id)) {
            [void]$disabledList.Add($id)
            Write-Host "  Disabled skill '$id'" -ForegroundColor Yellow
        } else {
            Write-Host "  Skill '$id' is already disabled." -ForegroundColor Gray
        }
    }

    $cfg.skills.disabled = $disabledList.ToArray()
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

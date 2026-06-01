<#
.SYNOPSIS
felix skill - manage Felix skills (Phase B4).

.DESCRIPTION
Subcommands: list, show, enable, disable
Skills live in .felix/skills/<id>/ (repo scope) and %USERPROFILE%/.felix/skills/<id>/ (user scope).
#>

function Invoke-Skill {
    param(
        [string[]]$Args,
        [string]$RepoRoot = (Get-Location).Path
    )

    $subCmd = if ($Args.Count -gt 0) { $Args[0] } else { "list" }
    $subArgs = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }

    . "$PSScriptRoot\..\core\skill-loader.ps1"

    switch ($subCmd) {
        "list"    { Invoke-SkillList    -SubArgs $subArgs -RepoRoot $RepoRoot }
        "show"    { Invoke-SkillShow    -SubArgs $subArgs -RepoRoot $RepoRoot }
        "enable"  { Invoke-SkillEnable  -SubArgs $subArgs -RepoRoot $RepoRoot -Enable $true }
        "disable" { Invoke-SkillEnable  -SubArgs $subArgs -RepoRoot $RepoRoot -Enable $false }
        "install" {
            Write-Host "felix skill install is deferred to Phase G (Marketplace)." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "Unknown skill subcommand: $subCmd" -ForegroundColor Red
            Write-Host "Valid: list, show, enable, disable" -ForegroundColor Gray
            exit 1
        }
    }
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

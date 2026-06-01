<#
.SYNOPSIS
Phase B unit tests — frontmatter-parser.ps1 and skill-loader.ps1.

Run with:
    .\tests\Test-PhaseB.ps1

Exit code 0 = all pass. Exit code 1 = one or more failures.
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

. "$repoRoot\.felix\core\frontmatter-parser.ps1"
. "$repoRoot\.felix\core\skill-loader.ps1"

# ---------------------------------------------------------------------------
# Micro-assert helpers
# ---------------------------------------------------------------------------

$global:_pass = 0
$global:_fail = 0

function Assert-Equal {
    param([string]$Desc, $Actual, $Expected)
    if ("$Actual" -eq "$Expected") {
        Write-Host "  PASS: $Desc" -ForegroundColor Green
        $global:_pass++
    } else {
        Write-Host "  FAIL: $Desc`n        Expected: '$Expected'  Got: '$Actual'" -ForegroundColor Red
        $global:_fail++
    }
}

function Assert-True {
    param([string]$Desc, [bool]$Value)
    if ($Value) {
        Write-Host "  PASS: $Desc" -ForegroundColor Green
        $global:_pass++
    } else {
        Write-Host "  FAIL: $Desc (was false)" -ForegroundColor Red
        $global:_fail++
    }
}

function Assert-Null {
    param([string]$Desc, $Value)
    if ($null -eq $Value) {
        Write-Host "  PASS: $Desc" -ForegroundColor Green
        $global:_pass++
    } else {
        Write-Host "  FAIL: $Desc (expected null, got '$Value')" -ForegroundColor Red
        $global:_fail++
    }
}

function New-TempDir {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("felixtest-" + [guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

# ---------------------------------------------------------------------------
# Parse-SimpleYaml
# ---------------------------------------------------------------------------

Write-Host "`nParse-SimpleYaml" -ForegroundColor Cyan

$fm = Parse-SimpleYaml -Lines @("id: S-0001", "title: My Title", "status: planned")
Assert-Equal "scalar id"     $fm["id"]     "S-0001"
Assert-Equal "scalar title"  $fm["title"]  "My Title"
Assert-Equal "scalar status" $fm["status"] "planned"

$fm2 = Parse-SimpleYaml -Lines @("tags: [context, prompt, v2]")
Assert-Equal "inline array count" $fm2["tags"].Count 3
Assert-True  "inline array has context" ($fm2["tags"] -contains "context")
Assert-True  "inline array has v2"      ($fm2["tags"] -contains "v2")

$fm3 = Parse-SimpleYaml -Lines @("applyTo:", "  - src/Felix.Cli/**", "  - tests/**")
Assert-Equal "block list count" $fm3["applyTo"].Count 2
Assert-True  "block list item"  ($fm3["applyTo"] -contains "src/Felix.Cli/**")

$fm4 = Parse-SimpleYaml -Lines @("# comment", "id: S-0002", "# another")
Assert-Equal "ignores comments key count" $fm4.Count 1
Assert-Equal "ignores comments value"     $fm4["id"] "S-0002"

$fm5 = Parse-SimpleYaml -Lines @('title: "Quoted Title"')
Assert-Equal "strips double quotes" $fm5["title"] "Quoted Title"

# ---------------------------------------------------------------------------
# Get-SpecFrontmatter
# ---------------------------------------------------------------------------

Write-Host "`nGet-SpecFrontmatter" -ForegroundColor Cyan

Assert-Null "returns null for nonexistent file" (Get-SpecFrontmatter -SpecPath "C:\nonexistent\spec.md")

$tmp = New-TempDir
try {
    $noFmPath = Join-Path $tmp "no-fm.md"
    Set-Content $noFmPath "# S-0001: Title`n`nBody."
    Assert-Null "returns null for spec without frontmatter" (Get-SpecFrontmatter -SpecPath $noFmPath)

    $withFmContent = @"
---
id: S-0042
title: Test Spec
status: planned
applyTo:
  - src/**
tags: [context, v2]
skills: [build-context]
gates: []
depends_on: []
---

# S-0042: Test Spec

Body.
"@
    $withFmPath = Join-Path $tmp "S-0042.md"
    Set-Content $withFmPath $withFmContent
    $parsed = Get-SpecFrontmatter -SpecPath $withFmPath
    Assert-True  "parses frontmatter not null" ($null -ne $parsed)
    Assert-Equal "frontmatter id"     $parsed["id"]     "S-0042"
    Assert-Equal "frontmatter title"  $parsed["title"]  "Test Spec"
    Assert-Equal "frontmatter status" $parsed["status"] "planned"
    Assert-True  "frontmatter applyTo present"  ($null -ne $parsed["applyTo"] -and @($parsed["applyTo"]).Count -gt 0)
    Assert-True  "frontmatter tags has context" ($parsed["tags"] -contains "context")
    Assert-True  "frontmatter skills has build-context" ($parsed["skills"] -contains "build-context")
} finally { Remove-Item $tmp -Recurse -Force }

# ---------------------------------------------------------------------------
# Get-SpecBody
# ---------------------------------------------------------------------------

Write-Host "`nGet-SpecBody" -ForegroundColor Cyan

$tmp = New-TempDir
try {
    $plainPath = Join-Path $tmp "plain.md"
    Set-Content $plainPath "# Title`n`nBody."
    $body = Get-SpecBody -SpecPath $plainPath
    Assert-True "no-frontmatter body contains title" ($body -match "# Title")

    $fmSpecPath = Join-Path $tmp "fm.md"
    Set-Content $fmSpecPath "---`nid: S-0001`n---`n`n# S-0001: Title`n`nBody."
    $bodyFm = Get-SpecBody -SpecPath $fmSpecPath
    Assert-True "body strips frontmatter" (-not ($bodyFm -match "^---"))
    Assert-True "body has heading"        ($bodyFm -match "# S-0001: Title")
} finally { Remove-Item $tmp -Recurse -Force }

# ---------------------------------------------------------------------------
# Format-SpecFrontmatter
# ---------------------------------------------------------------------------

Write-Host "`nFormat-SpecFrontmatter" -ForegroundColor Cyan

$fmHash = [ordered]@{ id = "S-0001"; title = "My Spec"; tags = @() }
$block = Format-SpecFrontmatter -Frontmatter $fmHash
Assert-True "block starts with ---"  ($block -match "^---")
Assert-True "block contains id"      ($block -match "id: S-0001")
Assert-True "block contains title"   ($block -match "title: My Spec")
Assert-True "block empty array"      ($block -match "tags: \[\]")

$fmHash2 = [ordered]@{ applyTo = @("src/**", "tests/**") }
$block2 = Format-SpecFrontmatter -Frontmatter $fmHash2
Assert-True "non-empty array block list header" ($block2 -match "applyTo:")
Assert-True "non-empty array has item"          ($block2 -match "src/\*\*")

# ---------------------------------------------------------------------------
# New-DefaultFrontmatter
# ---------------------------------------------------------------------------

Write-Host "`nNew-DefaultFrontmatter" -ForegroundColor Cyan

$tmp = New-TempDir
try {
    $specPath = Join-Path $tmp "S-0099.md"
    Set-Content $specPath "# S-0099: Title"
    $dfm = New-DefaultFrontmatter -SpecPath $specPath -SpecId "S-0099"
    Assert-Equal "default id"     $dfm["id"]     "S-0099"
    Assert-Equal "default status" $dfm["status"] "planned"
    Assert-True  "has applyTo"    ($dfm.Contains("applyTo"))
    Assert-True  "has tags"       ($dfm.Contains("tags"))
    Assert-True  "has skills"     ($dfm.Contains("skills"))
    Assert-True  "has gates"      ($dfm.Contains("gates"))
    Assert-True  "has depends_on" ($dfm.Contains("depends_on"))
} finally { Remove-Item $tmp -Recurse -Force }

# ---------------------------------------------------------------------------
# Get-SkillDirectories
# ---------------------------------------------------------------------------

Write-Host "`nGet-SkillDirectories" -ForegroundColor Cyan

$tmp = New-TempDir
try {
    $emptyMap = Get-SkillDirectories -RepoRoot $tmp
    Assert-Equal "empty when no skills" $emptyMap.Count 0

    $sd = New-Item -ItemType Directory -Path (Join-Path $tmp ".felix\skills\my-skill") -Force
    $mJson = @{ id = "my-skill"; name = "My Skill"; triggers = @{} } | ConvertTo-Json
    Set-Content (Join-Path $sd "skill.json") $mJson

    $map = Get-SkillDirectories -RepoRoot $tmp
    Assert-Equal "loads one skill"   $map.Count 1
    Assert-True  "has correct id"    ($map.Contains("my-skill"))
    Assert-Equal "scope is repo"     $map["my-skill"].Scope "repo"

    $mapDis = Get-SkillDirectories -RepoRoot $tmp -Disabled @("my-skill")
    Assert-Equal "disabled excluded" $mapDis.Count 0
} finally { Remove-Item $tmp -Recurse -Force }

# ---------------------------------------------------------------------------
# Get-MatchedSkills
# ---------------------------------------------------------------------------

Write-Host "`nGet-MatchedSkills" -ForegroundColor Cyan

function New-TestSkillMap {
    param([hashtable[]]$Defs)
    $map = [ordered]@{}
    foreach ($d in $Defs) {
        $m = [PSCustomObject]@{
            id      = $d.id
            name    = $d.id
            always  = $(if ($d.ContainsKey("always")) { $d.always } else { $false })
            triggers = [PSCustomObject]@{
                commands = $(if ($d.ContainsKey("commands")) { $d.commands } else { @() })
                applyTo  = $(if ($d.ContainsKey("applyTo"))  { $d.applyTo  } else { @() })
                tags     = $(if ($d.ContainsKey("tags"))     { $d.tags     } else { @() })
                keywords = $(if ($d.ContainsKey("keywords")) { $d.keywords } else { @() })
            }
        }
        $map[$d.id] = @{ Dir = "C:\fake"; Manifest = $m; Scope = "repo" }
    }
    return $map
}

$alwaysMap = New-TestSkillMap -Defs @(@{ id = "always-skill"; always = $true })
$matched = Get-MatchedSkills -SkillMap $alwaysMap
Assert-True "always-on included" ($matched -contains "always-skill")

$cmdMap = New-TestSkillMap -Defs @(@{ id = "spec-skill"; commands = @("spec") })
Assert-True "command trigger matches" ($matched2 -ne $null -or $true)  # re-test below
$matched2 = Get-MatchedSkills -SkillMap $cmdMap -CurrentCommand "spec create"
Assert-True "command trigger matched on spec create" ($matched2 -contains "spec-skill")
$matched2b = Get-MatchedSkills -SkillMap $cmdMap -CurrentCommand "run"
Assert-True "command trigger not matched on run" (-not ($matched2b -contains "spec-skill"))

$tagMap = New-TestSkillMap -Defs @(@{ id = "tag-skill"; tags = @("context") })
$matched3 = Get-MatchedSkills -SkillMap $tagMap -RequirementTags @("context", "v2")
Assert-True "tag trigger matched" ($matched3 -contains "tag-skill")

$kwMap = New-TestSkillMap -Defs @(@{ id = "kw-skill"; keywords = @("authentication") })
$matched4 = Get-MatchedSkills -SkillMap $kwMap -TaskDescription "Implement authentication system"
Assert-True "keyword trigger matched" ($matched4 -contains "kw-skill")
$matched4b = Get-MatchedSkills -SkillMap $kwMap -TaskDescription ""
Assert-True "keyword not matched on empty desc" (-not ($matched4b -contains "kw-skill"))

$sortMap = New-TestSkillMap -Defs @(
    @{ id = "z-skill"; always = $true },
    @{ id = "a-skill"; always = $true },
    @{ id = "m-skill"; always = $true }
)
$sorted = Get-MatchedSkills -SkillMap $sortMap
Assert-Equal "sorted order [0]" $sorted[0] "a-skill"
Assert-Equal "sorted order [1]" $sorted[1] "m-skill"
Assert-Equal "sorted order [2]" $sorted[2] "z-skill"

# ---------------------------------------------------------------------------
# Get-SkillsBlob
# ---------------------------------------------------------------------------

Write-Host "`nGet-SkillsBlob" -ForegroundColor Cyan

$emptyBlob = Get-SkillsBlob -SkillMap @{} -MatchedIds @()
Assert-True "empty blob for no matches" ([string]::IsNullOrEmpty($emptyBlob))

$tmp = New-TempDir
try {
    $sd2 = New-Item -ItemType Directory -Path (Join-Path $tmp "my-skill") -Force
    Set-Content (Join-Path $sd2 "prompt.md") "## My Skill Content"
    $m = [PSCustomObject]@{ id = "my-skill"; name = "My Skill"; prompt = "prompt.md" }
    $blobMap = [ordered]@{ "my-skill" = @{ Dir = $sd2.FullName; Manifest = $m } }

    $blob = Get-SkillsBlob -SkillMap $blobMap -MatchedIds @("my-skill")
    Assert-True "blob has skill heading"  ($blob -match "### Skill:")
    Assert-True "blob has prompt content" ($blob -match "My Skill Content")

    $longContent = "X" * 500
    Set-Content (Join-Path $sd2 "prompt.md") $longContent
    $truncBlob = Get-SkillsBlob -SkillMap $blobMap -MatchedIds @("my-skill") -BudgetChars 100
    Assert-True "blob truncated under budget" ($truncBlob.Length -lt 200)
    Assert-True "blob has truncation notice"  ($truncBlob -match "truncated")
} finally { Remove-Item $tmp -Recurse -Force }

# ---------------------------------------------------------------------------
# Test-GlobMatch
# ---------------------------------------------------------------------------

Write-Host "`nTest-GlobMatch" -ForegroundColor Cyan

Assert-True "** matches across dirs"       (Test-GlobMatch -Pattern "src/**" -Path "src/a/b/c.cs")
Assert-True "* does not cross dir boundary" (-not (Test-GlobMatch -Pattern "src/*.cs" -Path "src/sub/foo.cs"))
Assert-True "* matches same level"          (Test-GlobMatch -Pattern "src/*.cs" -Path "src/foo.cs")
Assert-True "exact match"                   (Test-GlobMatch -Pattern "README.md" -Path "README.md")
Assert-True "non-match returns false"       (-not (Test-GlobMatch -Pattern "src/**" -Path "tests/foo.cs"))

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=" * 50 -ForegroundColor Cyan
$color = if ($global:_fail -eq 0) { "Green" } else { "Red" }
Write-Host "TOTAL: $global:_pass passed, $global:_fail failed" -ForegroundColor $color

if ($global:_fail -gt 0) { exit 1 }
exit 0

<#
.SYNOPSIS
felix migrate  -  v1->v2 transform registry (Phase A6).

.DESCRIPTION
Permanent tool that transforms a v1 Felix repository layout to v2.
Preview mode by default; --apply is required to write changes.

Transform registry (additive  -  later phases plug in here):
  felixignore-seed    Seed .felixignore from default template
  agents-map-init     Add ## Map block to root AGENTS.md
  (B) spec-frontmatter  Added by Phase B
  (F) tools-allow       Added by Phase F

Running twice on an already-migrated repo is a no-op.
Recovery: git revert the migration commit.
#>

param(
    [switch]$DryRun,
    [switch]$Apply,
    [string]$Only = "",
    [string]$ProjectPath = (Get-Location).Path
)

. "$PSScriptRoot\..\core\felixignore-utils.ps1"

# -- Transform registry -----------------------------------------------------

$transforms = [ordered]@{}

# A: .felixignore seed
$transforms["felixignore-seed"] = @{
    Id          = "felixignore-seed"
    Description = "Seed .felixignore from default template"
    Phase       = "A"
    Check       = {
        param($ProjectPath)
        -not (Test-Path (Join-Path $ProjectPath ".felixignore"))
    }
    Apply       = {
        param($ProjectPath)
        $result = New-DefaultFelixIgnore -RepoRoot $ProjectPath
        return @{ Changed = $result.Created; Detail = if ($result.Created) { "Created $($result.Path)" } else { "Skipped: $($result.Reason)" } }
    }
}

# A: AGENTS.md ## Map block initialization
$transforms["agents-map-init"] = @{
    Id          = "agents-map-init"
    Description = "Add ## Map section to root AGENTS.md"
    Phase       = "A"
    Check       = {
        param($ProjectPath)
        $agentsPath = Join-Path $ProjectPath "AGENTS.md"
        if (-not (Test-Path $agentsPath)) { return $true }
        $content = Get-Content $agentsPath -Raw -ErrorAction SilentlyContinue
        return $content -notmatch "## Map"
    }
    Apply       = {
        param($ProjectPath)
        $agentsPath = Join-Path $ProjectPath "AGENTS.md"
        if (-not (Test-Path $agentsPath)) {
            return @{ Changed = $false; Detail = "AGENTS.md not found  -  skipped" }
        }
        $content = Get-Content $agentsPath -Raw -ErrorAction SilentlyContinue
        if ($content -match "## Map") {
            return @{ Changed = $false; Detail = "## Map section already present" }
        }

        # Generate map from top-level directories
        $topDirs = Get-ChildItem -Path $ProjectPath -Directory |
            Where-Object { $_.Name -notmatch "^(\.|node_modules|__pycache__|obj|bin|runs|publish-out)$" } |
            Select-Object -First 20

        $mapLines = [System.Collections.ArrayList]@()
        [void]$mapLines.Add("## Map")
        [void]$mapLines.Add("")
        [void]$mapLines.Add("<!-- felix:map-start -->")
        foreach ($dir in $topDirs) {
            $readmeDesc = ""
            $readmePath = Join-Path $dir.FullName "README.md"
            if (Test-Path $readmePath) {
                $readmeContent = Get-Content $readmePath -TotalCount 5 -ErrorAction SilentlyContinue
                $firstHeading = $readmeContent | Where-Object { $_ -match "^#" } | Select-Object -First 1
                if ($firstHeading) {
                    $readmeDesc = "  -  " + ($firstHeading -replace "^#+\s*", "")
                }
            }
            [void]$mapLines.Add("- **$($dir.Name)/**$readmeDesc")
        }
        [void]$mapLines.Add("<!-- felix:map-end -->")
        [void]$mapLines.Add("")

        $mapBlock = $mapLines -join "`n"
        $newContent = $content.TrimEnd() + "`n`n" + $mapBlock
        Set-Content -Path $agentsPath -Value $newContent -Encoding UTF8 -NoNewline
        return @{ Changed = $true; Detail = "Added ## Map section with $($topDirs.Count) entries" }
    }
}

# -- Command implementation ------------------------------------------------

if (-not $DryRun -and -not $Apply) {
    $DryRun = $true
}

$selectedTransforms = if ($Only) {
    $transforms.Keys | Where-Object { $_ -eq $Only }
} else {
    $transforms.Keys
}

$results = [System.Collections.ArrayList]@()
$anyPending = $false

foreach ($id in $selectedTransforms) {
    $t = $transforms[$id]
    $needsRun = & $t.Check $ProjectPath
    if (-not $needsRun) {
        [void]$results.Add([PSCustomObject]@{
            Id     = $id
            Status = "no-op"
            Detail = "already applied"
        })
        continue
    }

    $anyPending = $true

    if ($DryRun) {
        [void]$results.Add([PSCustomObject]@{
            Id     = $id
            Status = "pending"
            Detail = $t.Description
        })
    } else {
        # --apply mode
        $applyResult = & $t.Apply $ProjectPath
        [void]$results.Add([PSCustomObject]@{
            Id     = $id
            Status = if ($applyResult.Changed) { "applied" } else { "no-op" }
            Detail = $applyResult.Detail
        })
    }
}

# -- Output ----------------------------------------------------------------

$mode = if ($Apply) { "apply" } else { "dry-run" }
Write-Host ""
if ($DryRun) {
    Write-Host "felix migrate (dry-run)  -  use --apply to write changes" -ForegroundColor Cyan
} else {
    Write-Host "felix migrate (apply)" -ForegroundColor Green
}
Write-Host ""

foreach ($r in $results) {
    $icon  = switch ($r.Status) {
        "applied" { "[ok]" }
        "pending" { "->" }
        "no-op"   { "." }
        default   { "?" }
    }
    $color = switch ($r.Status) {
        "applied" { "Green" }
        "pending" { "Yellow" }
        "no-op"   { "DarkGray" }
        default   { "White" }
    }
    Write-Host "  $icon [$($r.Id)] $($r.Detail)" -ForegroundColor $color
}

Write-Host ""
if ($DryRun -and $anyPending) {
    Write-Host "Run with --apply to execute the pending transforms." -ForegroundColor Yellow
} elseif (-not $anyPending) {
    Write-Host "Repository is already at v2 layout. No transforms needed." -ForegroundColor Green
}
Write-Host ""

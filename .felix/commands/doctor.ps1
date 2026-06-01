<#
.SYNOPSIS
felix doctor  -  diagnostic command for Felix installations (Phase AS4).

.DESCRIPTION
Single diagnostic command that surfaces common operational failures.
Checks are extensible  -  later phases register their own checks without
owning the verb.

v2.0 checks (A/A.5-owned):
  event-log          Detect corrupt events.jsonl (truncated last line, bad JSON)
  plugin-hashes      Detect plugin manifest hash mismatches
  repo-map-stale     New top-level folder without entry in AGENTS.md ## Map

Later phases add:
  spec-frontmatter   (Phase B) required fields, gate/skill/applyTo validation
  stale-review       (Phase E) last_review > 90 days in state.json
  stale-leases       (Phase H) .locks/*.lock past lease_until
  orphaned-worktrees (Phase H) .felix/worktrees/* not in active session

--fix flag: non-destructive repairs for currently registered checks.
--explain <path>: report which .felixignore pattern matched a given path.
#>

param(
    [switch]$Fix,
    [string]$Explain = "",
    [switch]$Json,
    [string]$ProjectPath = (Get-Location).Path
)

. "$PSScriptRoot\..\core\felixignore-utils.ps1"
. "$PSScriptRoot\..\core\frontmatter-parser.ps1"

$felixDir = Join-Path $ProjectPath ".felix"
$results  = [System.Collections.ArrayList]@()

# -- Explain mode (A3) ----------------------------------------------------

if ($Explain) {
    if (-not (Test-Path $Explain)) {
        Write-Host "Path not found: $Explain" -ForegroundColor Red
        exit 1
    }
    $exp = Get-FelixIgnoreExplanation -Path $Explain -RepoRoot $ProjectPath
    if ($exp.Ignored) {
        Write-Host "  IGNORED  $($exp.RelPath)"   -ForegroundColor Yellow
        Write-Host "  Pattern: $($exp.MatchedPattern) (layer: $($exp.Layer))" -ForegroundColor Gray
        Write-Host "  Source:  $($exp.Source)"    -ForegroundColor Gray
    } else {
        Write-Host "  NOT IGNORED  $($exp.RelPath)" -ForegroundColor Green
        Write-Host "  No matching .felixignore pattern." -ForegroundColor Gray
    }
    exit 0
}

# -- Check registry -------------------------------------------------------

function Add-CheckResult {
    param($Id, $Status, $Message, $FixDetail = "")
    [void]$results.Add([PSCustomObject]@{
        id        = $Id
        status    = $Status   # ok | warn | fail
        message   = $Message
        fix       = $FixDetail
    })
}

# Check 1: events.jsonl integrity (AS2)
$eventsPath = Join-Path $felixDir "events.jsonl"
if (Test-Path $eventsPath) {
    $lastLine = Get-Content $eventsPath -ErrorAction SilentlyContinue | Select-Object -Last 1
    $isCorrupt = $false
    if ($lastLine) {
        try { $null = $lastLine | ConvertFrom-Json } catch { $isCorrupt = $true }
    }
    if ($isCorrupt) {
        Add-CheckResult -Id "event-log" -Status "fail" -Message "events.jsonl last line is invalid JSON (corrupt/truncated)" -FixDetail "Truncate corrupt last line"
        if ($Fix) {
            $lines = Get-Content $eventsPath -ErrorAction SilentlyContinue
            if ($lines.Count -gt 1) {
                $lines[0..($lines.Count - 2)] | Set-Content $eventsPath -Encoding UTF8
                Write-Host "  [fix] Removed corrupt last line from events.jsonl" -ForegroundColor Yellow
            }
        }
    } else {
        Add-CheckResult -Id "event-log" -Status "ok" -Message "events.jsonl is valid"
    }
} else {
    Add-CheckResult -Id "event-log" -Status "ok" -Message "events.jsonl not yet created (normal for new installations)"
}

# Check 2: plugin manifest hash mismatches (AS1)
$hashesPath = Join-Path $felixDir "plugins\manifest-hashes.json"
if (Test-Path $hashesPath) {
    try {
        $hashes = Get-Content $hashesPath -Raw | ConvertFrom-Json
        $mismatches = [System.Collections.ArrayList]@()
        foreach ($prop in $hashes.PSObject.Properties) {
            $pluginManifest = Join-Path $felixDir "plugins\$($prop.Name)\plugin.json"
            if (Test-Path $pluginManifest) {
                $bytes = [System.IO.File]::ReadAllBytes($pluginManifest)
                $sha   = [System.Security.Cryptography.SHA256]::Create()
                $actualHash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
                if ($actualHash -ne $prop.Value) {
                    [void]$mismatches.Add($prop.Name)
                }
            }
        }
        if ($mismatches.Count -gt 0) {
            Add-CheckResult -Id "plugin-hashes" -Status "fail" -Message "Hash mismatches for plugins: $($mismatches -join ', ')" -FixDetail "Re-run 'felix plugin install' for affected plugins"
        } else {
            Add-CheckResult -Id "plugin-hashes" -Status "ok" -Message "All plugin hashes match"
        }
    } catch {
        Add-CheckResult -Id "plugin-hashes" -Status "warn" -Message "Could not parse manifest-hashes.json: $_"
    }
} else {
    Add-CheckResult -Id "plugin-hashes" -Status "ok" -Message "manifest-hashes.json not present"
}

# Check 3: repo-map staleness (A2)
$agentsPath = Join-Path $ProjectPath "AGENTS.md"
if (Test-Path $agentsPath) {
    $agentsContent = Get-Content $agentsPath -Raw -ErrorAction SilentlyContinue
    $hasMap = $agentsContent -match "## Map"

    if (-not $hasMap) {
        Add-CheckResult -Id "repo-map-stale" -Status "warn" -Message "Root AGENTS.md has no ## Map section. Run 'felix doctor --fix' or 'felix migrate --apply' to generate it." -FixDetail "Generate ## Map section"
        if ($Fix) {
            # Delegate to migrate transform
            $migrateScript = Join-Path $PSScriptRoot "migrate.ps1"
            if (Test-Path $migrateScript) {
                & $migrateScript -Apply -Only "agents-map-init" -ProjectPath $ProjectPath
            }
        }
    } else {
        # Check for untracked top-level dirs
        $mapMatch = [regex]::Match($agentsContent, "(?s)## Map.*?<!-- felix:map-start -->(.*?)<!-- felix:map-end -->")
        if ($mapMatch.Success) {
            $mapBlock = $mapMatch.Groups[1].Value
            $topDirs = Get-ChildItem -Path $ProjectPath -Directory |
                Where-Object { $_.Name -notmatch "^(\.|node_modules|__pycache__|obj|bin|runs|publish-out)$" }
            $stale = $topDirs | Where-Object { $mapBlock -notmatch [regex]::Escape($_.Name) }
            if ($stale) {
                Add-CheckResult -Id "repo-map-stale" -Status "warn" -Message "## Map missing entries for: $($stale.Name -join ', '). Run --fix to refresh." -FixDetail "Refresh ## Map section"
                if ($Fix) {
                    $migrateScript = Join-Path $PSScriptRoot "migrate.ps1"
                    if (Test-Path $migrateScript) {
                        & $migrateScript -Apply -Only "agents-map-init" -ProjectPath $ProjectPath
                    }
                }
            } else {
                Add-CheckResult -Id "repo-map-stale" -Status "ok" -Message "## Map is up to date"
            }
        } else {
            Add-CheckResult -Id "repo-map-stale" -Status "ok" -Message "## Map section present (unstructured  -  run 'felix migrate --apply' to add markers)"
        }
    }
} else {
    Add-CheckResult -Id "repo-map-stale" -Status "warn" -Message "Root AGENTS.md not found"
}

# Check 4: spec-frontmatter (B7)
$configPath = Join-Path $felixDir "config.json"
$specFrontmatterEnforcement = "warn"
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($cfg.doctor -and $cfg.doctor.gates -and $cfg.doctor.gates.spec_frontmatter) {
        $specFrontmatterEnforcement = $cfg.doctor.gates.spec_frontmatter
    }
}

$specsDir = Join-Path $ProjectPath "specs"
if (Test-Path $specsDir) {
    $missingFM = Get-ChildItem -Path $specsDir -Filter "*.md" -ErrorAction SilentlyContinue |
        Where-Object {
            $firstLine = Get-Content $_.FullName -TotalCount 1 -ErrorAction SilentlyContinue
            $firstLine -ne "---"
        }

    if ($missingFM -and @($missingFM).Count -gt 0) {
        $names = ($missingFM | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ", "
        $more  = if (@($missingFM).Count -gt 5) { " (and $(@($missingFM).Count - 5) more)" } else { "" }
        $status = if ($specFrontmatterEnforcement -eq "error") { "fail" } else { "warn" }
        Add-CheckResult -Id "spec-frontmatter" -Status $status `
            -Message "$(@($missingFM).Count) spec(s) missing frontmatter: $names$more. Run 'felix migrate --apply --only spec-frontmatter' to fix." `
            -FixDetail "Run felix migrate --apply --only spec-frontmatter"
        if ($Fix) {
            $migrateScript = Join-Path $PSScriptRoot "migrate.ps1"
            if (Test-Path $migrateScript) {
                & $migrateScript -Apply -Only "spec-frontmatter" -ProjectPath $ProjectPath
            }
        }
    } else {
        Add-CheckResult -Id "spec-frontmatter" -Status "ok" -Message "All specs have frontmatter"
    }
} else {
    Add-CheckResult -Id "spec-frontmatter" -Status "ok" -Message "specs/ directory not found (skipped)"
}

# -- Output ----------------------------------------------------------------

$failCount = ($results | Where-Object { $_.status -eq "fail" }).Count
$warnCount = ($results | Where-Object { $_.status -eq "warn" }).Count

if ($Json) {
    @{
        "_v"    = 1
        checks  = $results.ToArray()
        summary = @{ fail = $failCount; warn = $warnCount; ok = ($results.Count - $failCount - $warnCount) }
    } | ConvertTo-Json -Depth 5
    if ($failCount -gt 0) { exit 1 } else { exit 0 }
}

Write-Host ""
Write-Host "felix doctor" -ForegroundColor Cyan
Write-Host ""

foreach ($r in $results) {
    $icon = switch ($r.status) {
        "ok"   { "[ok]" }
        "warn" { "!" }
        "fail" { "[FAIL]" }
        default { "?" }
    }
    $color = switch ($r.status) {
        "ok"   { "Green" }
        "warn" { "Yellow" }
        "fail" { "Red" }
        default { "White" }
    }
    Write-Host "  $icon [$($r.id)] $($r.message)" -ForegroundColor $color
}

Write-Host ""
if ($failCount -gt 0) {
    Write-Host "$failCount issue(s) found." -ForegroundColor Red
    if (-not $Fix) { Write-Host "Run with --fix to attempt repairs." -ForegroundColor Gray }
} elseif ($warnCount -gt 0) {
    Write-Host "$warnCount warning(s). Run with --fix to address." -ForegroundColor Yellow
} else {
    Write-Host "All checks passed." -ForegroundColor Green
}
Write-Host ""

if ($failCount -gt 0) { exit 1 } else { exit 0 }

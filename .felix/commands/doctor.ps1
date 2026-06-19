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
  usage-artifacts    Token/model usage artifacts are present and readable
  usage-pricing      Local pricing config can estimate usage cost
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

$felixDir  = Join-Path $ProjectPath ".felix"
$stateFile = Join-Path $felixDir "state.json"
$results   = [System.Collections.ArrayList]@()

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

function Get-DoctorObjectPropertyValue {
    param($Object, [string]$Name)
    if (-not $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $null }
    return $prop.Value
}

function Get-DoctorPricingCatalog {
    param([string]$FelixDir)

    $pricingPath = Join-Path $FelixDir "model-pricing.json"
    if (-not (Test-Path $pricingPath)) {
        return [ordered]@{
            path    = $pricingPath
            exists   = $false
            entries = @()
        }
    }

    try {
        $raw = Get-Content $pricingPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entries = @()
        if ($raw.prices) { $entries = @($raw.prices) }
        elseif ($raw.models) { $entries = @($raw.models) }

        return [ordered]@{
            path    = $pricingPath
            exists   = $true
            entries = $entries
        }
    }
    catch {
        return [ordered]@{
            path    = $pricingPath
            exists   = $true
            entries = @()
            error   = $_.Exception.Message
        }
    }
}

function Test-DoctorPricingMatch {
    param(
        $Entry,
        [string]$Provider,
        [string]$Model
    )

    $entryProvider = Get-DoctorObjectPropertyValue -Object $Entry -Name "provider"
    $entryModel = Get-DoctorObjectPropertyValue -Object $Entry -Name "model"
    if ([string]::IsNullOrWhiteSpace([string]$entryProvider)) { $entryProvider = "*" }
    if ([string]::IsNullOrWhiteSpace([string]$entryModel)) { $entryModel = "*" }

    $providerMatches = $entryProvider -eq "*" -or [string]::Equals([string]$entryProvider, $Provider, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $providerMatches) { return $false }

    if ($entryModel -eq "*") { return $true }
    if ([string]::Equals([string]$entryModel, $Model, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

    return $Model -like $entryModel
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

# Check 5: stale-review (Phase E)
$stateForReview = $null
if (Test-Path $stateFile) {
    try { $stateForReview = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
if ($stateForReview -and $stateForReview.last_review) {
    try {
        $lastReview = [datetime]::Parse($stateForReview.last_review)
        $daysSince  = ((Get-Date) - $lastReview).TotalDays
        if ($daysSince -gt 90) {
            $daysInt = [int]$daysSince
            Add-CheckResult -Id "stale-review" -Status "warn" `
                -Message "Review overdue: last review was $daysInt days ago. Run 'felix review --acknowledge' to suppress." `
                -FixDetail "Run: felix review --acknowledge"
        } else {
            Add-CheckResult -Id "stale-review" -Status "ok" -Message "Review up to date (last: $($stateForReview.last_review))"
        }
    } catch {
        Add-CheckResult -Id "stale-review" -Status "warn" -Message "Could not parse last_review timestamp: $_"
    }
} else {
    Add-CheckResult -Id "stale-review" -Status "warn" `
        -Message "No review on record. Run 'felix review --learnings' periodically then 'felix review --acknowledge'." `
        -FixDetail "Run: felix review --acknowledge"
}

# Check 6: token/model usage artifacts
$runsDir = Join-Path $ProjectPath "runs"
$usageRecords = @()
if (-not (Test-Path $runsDir)) {
    Add-CheckResult -Id "usage-artifacts" -Status "ok" -Message "No runs yet; usage will be recorded after first agent execution"
}
else {
    $runDirs = @(Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue)
    $usageFiles = @(Get-ChildItem -Path $runsDir -Recurse -Filter "usage.json" -File -ErrorAction SilentlyContinue)

    if ($runDirs.Count -gt 0 -and $usageFiles.Count -eq 0) {
        Add-CheckResult -Id "usage-artifacts" -Status "warn" `
            -Message "No usage.json artifacts found for $($runDirs.Count) existing run(s). Run an agent with the current Felix runner to capture token and model usage." `
            -FixDetail "Run: felix run <requirement-id>"
    }
    elseif ($usageFiles.Count -eq 0) {
        Add-CheckResult -Id "usage-artifacts" -Status "ok" -Message "No run usage artifacts yet"
    }
    else {
        $invalidUsage = 0
        foreach ($usageFile in $usageFiles) {
            try {
                $record = Get-Content $usageFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $usageRecords += $record
            }
            catch {
                $invalidUsage++
            }
        }

        if ($invalidUsage -gt 0) {
            Add-CheckResult -Id "usage-artifacts" -Status "fail" `
                -Message "$invalidUsage usage.json artifact(s) are invalid JSON; 'felix query usage' may fail." `
                -FixDetail "Inspect or remove corrupt usage.json files under runs/"
        }
        else {
            $missingUsage = @($usageRecords | Where-Object { $_.usage_available -ne $true }).Count
            $missingModel = @($usageRecords | Where-Object { -not $_.model -or [string]::IsNullOrWhiteSpace([string]$_.model.effective) }).Count

            if ($missingUsage -gt 0 -or $missingModel -gt 0) {
                $parts = @()
                if ($missingUsage -gt 0) { $parts += "$missingUsage run(s) without provider token counts" }
                if ($missingModel -gt 0) { $parts += "$missingModel run(s) without an effective model" }
                Add-CheckResult -Id "usage-artifacts" -Status "warn" `
                    -Message "Usage artifacts present, but $($parts -join ' and '). Check the selected agent adapter/provider output." `
                    -FixDetail "Run: felix query usage --json"
            }
            else {
                $observedModels = @($usageRecords | ForEach-Object {
                    $provider = if ($_.agent -and $_.agent.provider) { [string]$_.agent.provider } else { "unknown" }
                    "$provider/$([string]$_.model.effective)"
                } | Sort-Object -Unique)
                Add-CheckResult -Id "usage-artifacts" -Status "ok" -Message "Usage artifacts readable for $($usageRecords.Count) run(s): $($observedModels -join ', ')"
            }
        }
    }
}

# Check 7: local usage pricing coverage
$validPricedUsage = @($usageRecords | Where-Object {
        $_.usage_available -eq $true -and $_.model -and -not [string]::IsNullOrWhiteSpace([string]$_.model.effective)
    })

if ($validPricedUsage.Count -eq 0) {
    Add-CheckResult -Id "usage-pricing" -Status "ok" -Message "No priced usage records yet"
}
else {
    $catalog = Get-DoctorPricingCatalog -FelixDir $felixDir
    if (-not $catalog.exists) {
        Add-CheckResult -Id "usage-pricing" -Status "warn" `
            -Message "Usage is captured, but .felix/model-pricing.json is missing so cost estimates are disabled." `
            -FixDetail "Copy .felix/model-pricing.json.example to .felix/model-pricing.json and add current provider prices"
    }
    elseif ($catalog.error) {
        Add-CheckResult -Id "usage-pricing" -Status "warn" `
            -Message "Could not parse .felix/model-pricing.json: $($catalog.error)" `
            -FixDetail "Fix JSON syntax in .felix/model-pricing.json"
    }
    elseif (@($catalog.entries).Count -eq 0) {
        Add-CheckResult -Id "usage-pricing" -Status "warn" `
            -Message ".felix/model-pricing.json has no pricing entries; cost estimates are disabled." `
            -FixDetail "Add prices[] entries for the models reported by 'felix query usage --json'"
    }
    else {
        $combos = @($validPricedUsage | ForEach-Object {
            $provider = if ($_.agent -and $_.agent.provider) { [string]$_.agent.provider } else { "" }
            [PSCustomObject]@{
                provider = $provider
                model    = [string]$_.model.effective
                key      = "$provider/$([string]$_.model.effective)"
            }
        } | Sort-Object key -Unique)

        $missingPricing = @($combos | Where-Object {
                $combo = $_
                -not @($catalog.entries | Where-Object { Test-DoctorPricingMatch -Entry $_ -Provider $combo.provider -Model $combo.model }).Count
            })

        if ($missingPricing.Count -gt 0) {
            Add-CheckResult -Id "usage-pricing" -Status "warn" `
                -Message "No pricing rule for: $((@($missingPricing | ForEach-Object { $_.key }) | Select-Object -First 5) -join ', ')." `
                -FixDetail "Add matching provider/model entries to .felix/model-pricing.json"
        }
        else {
            Add-CheckResult -Id "usage-pricing" -Status "ok" -Message "Pricing rules cover $($combos.Count) observed provider/model combination(s)"
        }
    }
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

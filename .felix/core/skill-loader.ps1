<#
.SYNOPSIS
skill-loader.ps1 - Phase B3 skill loader for Felix v2.

.DESCRIPTION
Discovers, filters, and assembles skill prompt fragments into the {{SKILLS}} placeholder.

Selection priority:
  1. always-on  (skill.json "always": true)
  2. command-triggered  (triggers.commands matches current command)
  3. path-triggered     (requirement applyTo globs intersect skill triggers.applyTo)
  4. tag-triggered      (requirement tags intersect skill triggers.tags)
  5. content-triggered  (task description contains triggers.keywords)

Repo scope (.felix/skills/) overrides user scope (%USERPROFILE%/.felix/skills/) on id collision.
Loaded skills are assembled in stable alphabetical-by-id order for deterministic replay.

Disabled skills (config.json#skills.disabled) are excluded regardless of trigger match.
#>

function Get-SkillDirectories {
    <#
    .SYNOPSIS
    Discovers all skill directories from repo scope and user scope.
    Repo scope wins on id collision.
    #>
    param(
        [string]$RepoRoot,
        [string[]]$Disabled = @()
    )

    $repoSkillsDir = Join-Path $RepoRoot ".felix\skills"
    $userSkillsDir = Join-Path ([System.Environment]::GetFolderPath("UserProfile")) ".felix\skills"

    $skillMap = [ordered]@{}

    # User scope first (lower priority)
    if (Test-Path $userSkillsDir) {
        Get-ChildItem -Path $userSkillsDir -Directory | ForEach-Object {
            $manifestPath = Join-Path $_.FullName "skill.json"
            if (Test-Path $manifestPath) {
                $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                $id = $m.id
                if ($id -and $id -notin $Disabled) {
                    $skillMap[$id] = @{ Dir = $_.FullName; Manifest = $m; Scope = "user" }
                }
            }
        }
    }

    # Repo scope (overrides user)
    if (Test-Path $repoSkillsDir) {
        Get-ChildItem -Path $repoSkillsDir -Directory | ForEach-Object {
            $manifestPath = Join-Path $_.FullName "skill.json"
            if (Test-Path $manifestPath) {
                $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                $id = $m.id
                if ($id -and $id -notin $Disabled) {
                    $skillMap[$id] = @{ Dir = $_.FullName; Manifest = $m; Scope = "repo" }
                }
            }
        }
    }

    return $skillMap
}

function Test-GlobMatch {
    <#
    .SYNOPSIS
    Tests whether a path matches a glob pattern (basic ** and * support).
    #>
    param([string]$Pattern, [string]$Path)
    # Convert to regex (reuse logic from felixignore-utils if available)
    $regex = "^" + [regex]::Escape($Pattern) `
        -replace "\\\*\\\*", ".*" `
        -replace "\\\*", "[^/\\]*" `
        -replace "\\\?", "[^/\\]" + "$"
    return $Path -match $regex
}

function Get-MatchedSkills {
    <#
    .SYNOPSIS
    Returns the set of skill ids that match given context.

    .PARAMETER SkillMap
    Ordered hashtable from Get-SkillDirectories.

    .PARAMETER CurrentCommand
    The Felix command being run (e.g. "spec create", "run").

    .PARAMETER RequirementApplyTo
    Array of path globs from spec frontmatter applyTo field.

    .PARAMETER RequirementTags
    Array of tags from spec frontmatter.

    .PARAMETER TaskDescription
    Text of the current task (for keyword matching).
    #>
    param(
        [hashtable]$SkillMap,
        [string]$CurrentCommand = "",
        [string[]]$RequirementApplyTo = @(),
        [string[]]$RequirementTags = @(),
        [string]$TaskDescription = ""
    )

    $matched = [System.Collections.ArrayList]@()

    foreach ($id in ($SkillMap.Keys | Sort-Object)) {
        $entry = $SkillMap[$id]
        $m = $entry.Manifest
        $triggers = $m.triggers

        # 1. Always-on
        if ($m.always -eq $true) {
            [void]$matched.Add($id)
            continue
        }

        # 2. Command-triggered
        if ($triggers.commands -and $CurrentCommand) {
            foreach ($cmd in $triggers.commands) {
                if ($CurrentCommand -like "$cmd*") {
                    [void]$matched.Add($id)
                    break
                }
            }
            if ($matched -contains $id) { continue }
        }

        # 3. Path-triggered (applyTo intersection)
        if ($triggers.applyTo -and $RequirementApplyTo) {
            $hit = $false
            foreach ($reqGlob in $RequirementApplyTo) {
                foreach ($skillGlob in $triggers.applyTo) {
                    # Check if the globs could possibly overlap (simple prefix match)
                    if ($reqGlob -like "$skillGlob*" -or $skillGlob -like "$reqGlob*") {
                        $hit = $true; break
                    }
                }
                if ($hit) { break }
            }
            if ($hit) { [void]$matched.Add($id); continue }
        }

        # 4. Tag-triggered
        if ($triggers.tags -and $RequirementTags) {
            foreach ($tag in $triggers.tags) {
                if ($RequirementTags -contains $tag) {
                    [void]$matched.Add($id)
                    break
                }
            }
            if ($matched -contains $id) { continue }
        }

        # 5. Content/keyword-triggered
        if ($triggers.keywords -and $TaskDescription) {
            foreach ($kw in $triggers.keywords) {
                if ($TaskDescription -match [regex]::Escape($kw)) {
                    [void]$matched.Add($id)
                    break
                }
            }
        }
    }

    return $matched.ToArray()
}

function Get-SkillsBlob {
    <#
    .SYNOPSIS
    Assembles the {{SKILLS}} prompt fragment from matched skills.

    .DESCRIPTION
    Returns a string containing all matched skill prompts separated by headers.
    Stable alphabetical-by-id ordering ensures deterministic replay.
    Returns empty string if no skills matched.
    #>
    param(
        [hashtable]$SkillMap,
        [string[]]$MatchedIds,
        [int]$BudgetChars = 0   # 0 = unlimited; truncates if needed
    )

    if (-not $MatchedIds -or $MatchedIds.Count -eq 0) { return "" }

    $parts = [System.Collections.ArrayList]@()

    foreach ($id in ($MatchedIds | Sort-Object)) {
        if (-not $SkillMap.ContainsKey($id)) { continue }
        $entry  = $SkillMap[$id]
        $m      = $entry.Manifest
        $prompt = Join-Path $entry.Dir $(if ($m.prompt) { $m.prompt } else { "prompt.md" })
        if (-not (Test-Path $prompt)) { continue }

        $content = Get-Content $prompt -Raw -ErrorAction SilentlyContinue
        if ($content) {
            [void]$parts.Add("### Skill: $(if ($m.name) { $m.name } else { $id })`n`n$content")
        }
    }

    if ($parts.Count -eq 0) { return "" }

    $blob = $parts -join "`n`n---`n`n"

    if ($BudgetChars -gt 0 -and $blob.Length -gt $BudgetChars) {
        $blob = $blob.Substring(0, $BudgetChars) + "`n`n[... skills truncated: budget exceeded ...]"
    }

    return $blob
}

function Invoke-SkillLoader {
    <#
    .SYNOPSIS
    Top-level entry point used by prompt-builder.ps1.

    .DESCRIPTION
    Reads config, discovers skills, matches against context, returns blob.
    #>
    param(
        [string]$RepoRoot,
        [hashtable]$Config = @{},
        [string]$CurrentCommand = "",
        [string[]]$RequirementApplyTo = @(),
        [string[]]$RequirementTags = @(),
        [string]$TaskDescription = "",
        [int]$BudgetChars = 0
    )

    $disabled = @()
    if ($Config.skills -and $Config.skills.disabled) {
        $disabled = @($Config.skills.disabled)
    }

    $skillMap = Get-SkillDirectories -RepoRoot $RepoRoot -Disabled $disabled
    if ($skillMap.Count -eq 0) { return "" }

    $matchedIds = Get-MatchedSkills `
        -SkillMap $skillMap `
        -CurrentCommand $CurrentCommand `
        -RequirementApplyTo $RequirementApplyTo `
        -RequirementTags $RequirementTags `
        -TaskDescription $TaskDescription

    return Get-SkillsBlob -SkillMap $skillMap -MatchedIds $matchedIds -BudgetChars $BudgetChars
}

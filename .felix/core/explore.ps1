<#
.SYNOPSIS
explore.ps1 - Phase C2 read-only exploration subagent for Felix v2.

.DESCRIPTION
Runs the configured agent in a read-only context (explore phase) before plan/build.
Produces runs/<run-id>/context-map.md with structured findings.

Context loaded: layered AGENTS.md + repo map + spec + skills.
Excluded: plan, prior diffs, building instructions.

Output contract (context-map.md schema):
  ## Files likely to change
  ## Files to read for context
  ## Symbols of interest
  ## Related tests
  ## Prior runs

If the agent adapter cannot guarantee read-only execution:
  - Without --explore explicit: skip phase and continue with plan/build
  - With --explore explicit: emit actionable error and abort

Config block (config.json):
  "explore": {
    "enabled": false,
    "auto_enable_when": { "min_tracked_files": 500 },
    "skip_on_iteration_gt": 1,
    "agent_override": null,
    "max_tokens": 8000
  }
#>

function Get-ExploreConfig {
    <#
    .SYNOPSIS
    Returns the explore config block with defaults applied.
    #>
    param($Config)

    $defaults = @{
        enabled              = $false
        auto_enable_when     = @{ min_tracked_files = 500 }
        skip_on_iteration_gt = 1
        agent_override       = $null
        max_tokens           = 8000
    }

    if (-not $Config -or -not $Config.explore) { return $defaults }

    $cfg = $Config.explore
    return @{
        enabled              = if ($null -ne $cfg.enabled)              { [bool]$cfg.enabled }              else { $defaults.enabled }
        auto_enable_when     = if ($cfg.auto_enable_when)               { $cfg.auto_enable_when }            else { $defaults.auto_enable_when }
        skip_on_iteration_gt = if ($null -ne $cfg.skip_on_iteration_gt) { [int]$cfg.skip_on_iteration_gt }  else { $defaults.skip_on_iteration_gt }
        agent_override       = if ($cfg.agent_override)                 { $cfg.agent_override }              else { $null }
        max_tokens           = if ($null -ne $cfg.max_tokens)           { [int]$cfg.max_tokens }             else { $defaults.max_tokens }
    }
}

function Test-ExploreAutoEnable {
    <#
    .SYNOPSIS
    Returns true if auto-enable signal is met (tracked file count >= threshold).
    #>
    param(
        [string]$ProjectPath,
        $AutoEnableWhen
    )

    if (-not $AutoEnableWhen -or -not $AutoEnableWhen.min_tracked_files) { return $false }

    $threshold = [int]$AutoEnableWhen.min_tracked_files
    try {
        Push-Location $ProjectPath
        $count = (git ls-files 2>$null | Measure-Object).Count
        return $count -ge $threshold
    } catch { return $false }
    finally { Pop-Location }
}

function Test-ExploreEnabled {
    <#
    .SYNOPSIS
    Returns whether the explore phase should run for this iteration.

    Priority: explicit --explore/--no-explore > config.enabled > auto_enable_when signal.
    Also respects skip_on_iteration_gt.
    #>
    param(
        $ExploreConfig,
        [string]$ProjectPath,
        [int]$Iteration,
        [bool]$ExplicitExplore = $false,
        [bool]$ExplicitNoExplore = $false
    )

    # Explicit --no-explore always wins
    if ($ExplicitNoExplore) { return $false }

    # skip_on_iteration_gt: skip if iteration exceeds threshold
    if ($ExploreConfig.skip_on_iteration_gt -gt 0 -and $Iteration -gt $ExploreConfig.skip_on_iteration_gt) {
        return $false
    }

    # Explicit --explore override
    if ($ExplicitExplore) { return $true }

    # Config-driven enable
    if ($ExploreConfig.enabled) { return $true }

    # Auto-enable signal
    return Test-ExploreAutoEnable -ProjectPath $ProjectPath -AutoEnableWhen $ExploreConfig.auto_enable_when
}

function Assert-ContextMapSchema {
    <#
    .SYNOPSIS
    Validates that a context-map.md has the required section headers.
    Returns @{ Valid = bool; Missing = string[] }
    #>
    param([string]$Content)

    $requiredSections = @(
        "## Files likely to change",
        "## Files to read for context",
        "## Symbols of interest",
        "## Related tests",
        "## Prior runs"
    )

    $missing = @()
    foreach ($section in $requiredSections) {
        if ($Content -notmatch [regex]::Escape($section)) {
            $missing += $section
        }
    }

    return @{ Valid = ($missing.Count -eq 0); Missing = $missing }
}

function New-ExplorePrompt {
    <#
    .SYNOPSIS
    Builds the read-only exploration prompt.
    Includes: layered AGENTS.md, repo map, spec, skills. Excludes: plan, diffs.
    #>
    param(
        [string]$ProjectPath,
        [string]$RepoRoot,
        [hashtable]$Paths,
        $CurrentRequirement,
        [string]$RunId,
        [int]$Iteration,
        [int]$MaxTokens,
        $Config
    )

    $parts = [System.Collections.ArrayList]@()

    [void]$parts.Add(@"
# Exploration Mode

You are a **read-only** exploration agent. Your job is to analyse the codebase for requirement **$($CurrentRequirement.id)** and produce a structured Context Map.

**You MUST NOT write any code or modify any files.**

Your output must be a single markdown document with exactly these sections in order:

## Files likely to change
List files you expect the implementing agent will need to edit (most relevant first).

## Files to read for context
List files the implementing agent should read for background (most relevant first).

## Symbols of interest
List key functions/classes/methods by name with location (e.g. ``RegisterCommands`` (Program.Commands.cs:42)).

## Related tests
List test files relevant to this requirement.

## Prior runs
Summarise any prior failed iterations for this requirement from the runs/ directory (if any).

---

Output ONLY the markdown context map. No preamble, no JSON, no code changes.
"@)

    # Requirement summary
    [void]$parts.Add("# Requirement`n`n**$($CurrentRequirement.id)**: $($CurrentRequirement.title)`n`n$($CurrentRequirement.description)")

    # Spec file
    $specPath = if ($CurrentRequirement.spec_path) { $CurrentRequirement.spec_path } else { "$($Paths.SpecsRelativePath)/$($CurrentRequirement.id).md" }
    $specFilePath = Join-Path $ProjectPath $specPath
    if (Test-Path $specFilePath) {
        $specContent = Get-Content $specFilePath -Raw -ErrorAction SilentlyContinue
        [void]$parts.Add("# Specification`n`n$specContent")
    }

    # Layered AGENTS.md
    $agentsLoaderPath = Join-Path $Paths.FelixDir "core\agents-loader.ps1"
    if (Test-Path $agentsLoaderPath) {
        . $agentsLoaderPath
        try {
            $layeredResult = Get-LayeredAgentsContext -StartPath $ProjectPath -RepoRoot $RepoRoot
            if ($layeredResult.Blob) { [void]$parts.Add("# Agents Guide`n`n$($layeredResult.Blob)") }
        } catch {}
    } elseif (Test-Path $Paths.AgentsFile) {
        $agentsContent = Get-Content $Paths.AgentsFile -Raw -ErrorAction SilentlyContinue
        if ($agentsContent) { [void]$parts.Add("# Agents Guide`n`n$agentsContent") }
    }

    # Repo map
    $rootAgentsPath = Join-Path $RepoRoot "AGENTS.md"
    if (Test-Path $rootAgentsPath) {
        $rootAgents = Get-Content $rootAgentsPath -Raw -ErrorAction SilentlyContinue
        if ($rootAgents -match "(?s)## Map\s*\n(.*?)(\n##|\z)") {
            [void]$parts.Add("# Repository Map`n`n$($Matches[1].Trim())")
        }
    }

    # Skills (read-only context)
    $skillLoaderPath = Join-Path $Paths.FelixDir "core\skill-loader.ps1"
    if (Test-Path $skillLoaderPath) {
        . $skillLoaderPath
        try {
            $skillsBlob = Invoke-SkillLoader -RepoRoot $RepoRoot -Config $Config -CurrentCommand "explore"
            if ($skillsBlob) { [void]$parts.Add("# Skills Context`n`n$skillsBlob") }
        } catch {}
    }

    $prompt = $parts -join "`n`n---`n`n"

    # Rough token cap: ~4 chars/token
    $charBudget = $MaxTokens * 4
    if ($prompt.Length -gt $charBudget) {
        $prompt = $prompt.Substring(0, $charBudget) + "`n`n[... explore prompt truncated: token budget exceeded ...]"
    }

    return $prompt
}

function Invoke-ExplorePhase {
    <#
    .SYNOPSIS
    Runs the read-only exploration subagent and writes context-map.md.

    Returns @{ Succeeded = bool; ContextMapPath = string; ContextMapContent = string }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,

        [Parameter(Mandatory = $true)]
        $CurrentRequirement,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [int]$Iteration,

        [Parameter(Mandatory = $true)]
        $Config,

        [Parameter(Mandatory = $true)]
        $AgentConfig,

        [Parameter(Mandatory = $false)]
        [bool]$ExplicitExplore = $false
    )

    $exploreConfig = Get-ExploreConfig -Config $Config
    $contextMapPath = Join-Path $RunDir "context-map.md"

    $repoRoot = if (Get-Command Resolve-RepoRoot -ErrorAction SilentlyContinue) {
        Resolve-RepoRoot -Path $ProjectPath
    } else { $ProjectPath }

    Emit-Log -Level "info" -Message "Explore phase: building prompt for $($CurrentRequirement.id) it$Iteration" -Component "explore"

    # Build exploration prompt
    $explorePrompt = New-ExplorePrompt `
        -ProjectPath    $ProjectPath `
        -RepoRoot       $repoRoot `
        -Paths          $Paths `
        -CurrentRequirement $CurrentRequirement `
        -RunId          $RunId `
        -Iteration      $Iteration `
        -MaxTokens      $exploreConfig.max_tokens `
        -Config         $Config

    # Determine agent to use (agent_override or default)
    $exploreAgentConfig = $AgentConfig
    if ($exploreConfig.agent_override) {
        $agentsData = Get-AgentsConfiguration -AgentsJsonFile $Paths.AgentsJsonFile -ErrorAction SilentlyContinue
        if ($agentsData) {
            $overrideAgent = Get-AgentConfig -AgentsData $agentsData -AgentId $exploreConfig.agent_override -ConfigFile $Paths.ConfigFile -ErrorAction SilentlyContinue
            if ($overrideAgent) { $exploreAgentConfig = $overrideAgent }
        }
    }

    # Read-only check: verify agent supports --read-only or wrapper
    $canReadOnly = Test-AgentReadOnly -AgentConfig $exploreAgentConfig
    if (-not $canReadOnly) {
        if ($ExplicitExplore) {
            Emit-Error -ErrorType "ExploreAdapterNotReadOnly" `
                -Message "Agent adapter '$($exploreAgentConfig.adapter)' cannot guarantee read-only execution. Use an adapter that supports --read-only, or remove --explore." `
                -Severity "error" `
                -Context @{ adapter = $exploreAgentConfig.adapter }
            return @{ Succeeded = $false; ContextMapPath = $null; ContextMapContent = "" }
        }
        Emit-Log -Level "warn" -Message "Explore phase skipped: adapter '$($exploreAgentConfig.adapter)' cannot guarantee read-only execution." -Component "explore"
        return @{ Succeeded = $false; ContextMapPath = $null; ContextMapContent = ""; Skipped = $true }
    }

    # Execute agent
    Emit-Log -Level "info" -Message "Running explore subagent for $($CurrentRequirement.id)" -Component "explore"
    Set-WorkflowStage -Stage "explore" -ProjectPath $ProjectPath

    $exploreRunDir = Join-Path $RunDir "explore"
    if (-not (Test-Path $exploreRunDir)) {
        New-Item -ItemType Directory -Path $exploreRunDir -Force | Out-Null
    }

    $execResult = Invoke-AgentExecution `
        -AgentConfig  $exploreAgentConfig `
        -Prompt       $explorePrompt `
        -ProjectPath  $ProjectPath `
        -RunId        "$RunId-explore" `
        -RunDir       $exploreRunDir `
        -ReadOnly:$true

    if ($execResult.Succeeded -eq $false) {
        Emit-Log -Level "warn" -Message "Explore subagent failed; continuing with plan/build without context map." -Component "explore"
        return @{ Succeeded = $false; ContextMapPath = $null; ContextMapContent = ""; Skipped = $true }
    }

    # Extract markdown content from agent output
    $rawOutput = if ($execResult.NormalizedOutput) { $execResult.NormalizedOutput } else { $execResult.Output }

    # Strip any JSON envelope (agent may wrap in {"output": "...md..."})
    $mapContent = $rawOutput
    try {
        $parsed = $rawOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($parsed -and $parsed.output) { $mapContent = [string]$parsed.output }
        elseif ($parsed -and $parsed.content) { $mapContent = [string]$parsed.content }
    } catch {}

    # Validate schema
    $schemaResult = Assert-ContextMapSchema -Content $mapContent
    if (-not $schemaResult.Valid) {
        $missing = $schemaResult.Missing -join ", "
        Emit-Log -Level "warn" -Message "context-map.md missing required sections: $missing. Injecting empty sections." -Component "explore"

        # Inject missing sections (empty) so downstream always has the full schema
        foreach ($section in $schemaResult.Missing) {
            $mapContent += "`n`n$section`n`n_(no data)_"
        }
    }

    # Prepend header if absent
    if ($mapContent -notmatch "^# Context Map") {
        $header = "# Context Map -- $($CurrentRequirement.id) it$Iteration`n`n"
        $mapContent = $header + $mapContent
    }

    # Write context-map.md
    Set-Content -Path $contextMapPath -Value $mapContent -Encoding UTF8
    Emit-Log -Level "info" -Message "context-map.md written: $contextMapPath" -Component "explore"

    return @{
        Succeeded        = $true
        ContextMapPath   = $contextMapPath
        ContextMapContent = $mapContent
        Skipped          = $false
    }
}

function Test-AgentReadOnly {
    <#
    .SYNOPSIS
    Returns true if the agent adapter is considered safe for read-only exploration.
    Currently: all adapters are considered safe (exploration prompt instructs read-only behavior).
    Future: check for native --read-only flag support in adapter config.
    #>
    param($AgentConfig)

    # Check if adapter has explicit read_only_supported flag
    if ($null -ne $AgentConfig.read_only_supported) {
        return [bool]$AgentConfig.read_only_supported
    }

    # Default: trust the prompt-based read-only instruction
    return $true
}

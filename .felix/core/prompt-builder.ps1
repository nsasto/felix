<#
.SYNOPSIS
Prompt builder for Felix agent iterations

.DESCRIPTION
Assembles the full prompt from templates, requirement context, and mode-specific content.
#>

function New-IterationPrompt {
    <#
    .SYNOPSIS
    Builds the full prompt for agent execution
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        
        [Parameter(Mandatory = $true)]
        $CurrentRequirement,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $false)]
        [string]$PlanContent = $null,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCommit,

        [Parameter(Mandatory = $false)]
        [string]$CurrentCommand = "",

        [Parameter(Mandatory = $false)]
        [string]$TaskDescription = ""
    )

    # Load v2 modules if present (graceful fallback for v1 environments)
    $agentsLoaderPath  = Join-Path $PSScriptRoot "agents-loader.ps1"
    $budgeterPath      = Join-Path $PSScriptRoot "context-budgeter.ps1"
    $memoryLoaderPath  = Join-Path $PSScriptRoot "memory-loader.ps1"
    if (Test-Path $agentsLoaderPath)  { . $agentsLoaderPath }
    if (Test-Path $budgeterPath)      { . $budgeterPath }
    if (Test-Path $memoryLoaderPath)  { . $memoryLoaderPath }

    # Load prompt template
    $promptFile = Join-Path $Paths.PromptsDir "$Mode.md"
    if (-not (Test-Path $promptFile)) {
        Emit-Error -ErrorType "PromptTemplateNotFound" -Message "Prompt template not found: $promptFile" -Severity "fatal"
        return $null
    }
    $promptTemplate = Get-Content $promptFile -Raw
    
    # Workflow Stage: gather_context
    Set-WorkflowStage -Stage "gather_context" -ProjectPath $Paths.ProjectPath
    
    # Gather context
    $contextParts = @()
    
    # Inject an explicit, ordered file-reading contract with exact paths.
    $requiredFileLines = [System.Collections.ArrayList]@()
    $missingRequiredFileLines = [System.Collections.ArrayList]@()

    if ($Paths.AgentsRelativePath) {
        $agentsExists = Test-Path $Paths.AgentsFile
        $agentsLabel = if ($agentsExists) { "required" } else { "required but currently missing" }
        [void]$requiredFileLines.Add("1. **$($Paths.AgentsRelativePath)** - configured agents guide ($agentsLabel)")
    }

    $nextIndex = $requiredFileLines.Count + 1
    $specPath = if ($CurrentRequirement.spec_path) { $CurrentRequirement.spec_path } else { "$($Paths.SpecsRelativePath)/$($CurrentRequirement.id).md" }
    [void]$requiredFileLines.Add("$nextIndex. **$specPath** - exact requirement spec file")

    foreach ($contextPath in @($Paths.ContextRelativePaths)) {
        $absolutePath = Join-Path $Paths.ProjectPath ($contextPath -replace '/', '\')
        if (Test-Path $absolutePath) {
            $nextIndex = $requiredFileLines.Count + 1
            [void]$requiredFileLines.Add("$nextIndex. **$contextPath** - configured project context and architecture")
        }
        else {
            [void]$missingRequiredFileLines.Add("- **$contextPath**")
        }
    }

    $readBlock = "# Read These Exact Files First`n`n"
    $readBlock += "Before planning or coding, open these exact filesystem paths in order:`n`n"
    $readBlock += ($requiredFileLines -join "`n")
    $readBlock += "`n`nDo not continue until you have opened the required files above."
    if ($missingRequiredFileLines.Count -gt 0) {
        $readBlock += "`n`n## Missing Required Context Files`n`n"
        $readBlock += ($missingRequiredFileLines -join "`n")
        $readBlock += "`n`nThese files are part of the configured project context but are not present. Continue with the required files that do exist, and treat the missing files as a context gap."
    }
    $contextParts += $readBlock
    
    # Add Requirements context
    $requirements = Get-Content $Paths.RequirementsFile -Raw | ConvertFrom-Json

    # Load .meta.json sidecar for rich metadata (priority, tags, depends_on).
    # Falls back to inline fields for backward compat with old requirements.json files.
    $reqMeta = $null
    if ($CurrentRequirement.spec_path) {
        $metaPath = Join-Path $Paths.ProjectPath ($CurrentRequirement.spec_path -replace '\.md$', '.meta.json')
        if (Test-Path $metaPath) {
            try { $reqMeta = Get-Content $metaPath -Raw | ConvertFrom-Json } catch {}
        }
    }
    $dependsOn = if ($reqMeta -and $reqMeta.depends_on) { $reqMeta.depends_on } else { $CurrentRequirement.depends_on }

    $reqContext = @{
        id           = $CurrentRequirement.id
        title        = $CurrentRequirement.title
        description  = $CurrentRequirement.description
        status       = $CurrentRequirement.status
        dependencies = @()
    }
    
    # Add dependency info if they exist
    if ($dependsOn -and $dependsOn.Count -gt 0) {
        $deps = @()
        foreach ($depId in $dependsOn) {
            $depReq = $requirements.requirements | Where-Object { $_.id -eq $depId } | Select-Object -First 1
            if ($depReq) {
                $deps += @{
                    id     = $depReq.id
                    title  = $depReq.title
                    status = $depReq.status
                }
            }
        }
        $reqContext.dependencies = $deps
    }
    
    $reqSummary = $reqContext | ConvertTo-Json -Depth 10
    $contextParts += "# Current Requirement Context`n`n``````json`n$reqSummary`n```````n`n*Note: Full requirements list available at ``.felix/requirements.json`` if you need to check other requirements.*"
    
    # Add reference to the requirement spec file
    $contextParts += "# Requirement Specification`n`nRead the full acceptance criteria and constraints in: **$specPath**`n`nYou MUST understand every line of the spec before planning or implementing."
    
    # Add current requirement header
    $contextParts += "# Current Requirement`n`nYou are working on: **$($CurrentRequirement.id)** - $($CurrentRequirement.title)"
    
    # Add failure context from previous iteration if blocked
    if ($State.blocked_task) {
        $failedCommandsList = ($State.blocked_task.failed_commands | ForEach-Object { "- $_" }) -join "`n"
        $retryInfo = "#  Previous Iteration - Task Blocked `n`n"
        $retryInfo += "**IMPORTANT:** The following task failed validation in the previous iteration. You MUST fix these issues before proceeding.`n`n"
        $retryInfo += "**Blocked Task:** $($State.blocked_task.description)`n"
        $retryInfo += "**Retry Attempt:** $($State.blocked_task.retry_count) of $($State.blocked_task.max_retries)`n"
        $retryInfo += "**Blocked Since:** $($State.blocked_task.blocked_at)`n"
        $retryInfo += "**Reason:** $($State.blocked_task.reason)`n`n"
        $retryInfo += "## Failed Validation Commands`n`n"
        $retryInfo += "$failedCommandsList`n`n"
        $retryInfo += "## What You Must Do`n`n"
        $retryInfo += "1. **Review the failed validation commands above** - These commands must pass before the task can be committed`n"
        $retryInfo += "2. **Fix the underlying issues** causing the test/build/lint failures. DO NOT just retry without changes.`n"
        $retryInfo += "3. **Explain your fix** in the task completion message.`n"
        
        $contextParts += $retryInfo
    }
    
    # Add Mode Specific Context
    if ($Mode -eq "building") {
        if ($PlanContent) {
            $contextParts += "# Current Plan`n`n$PlanContent"
        }
    }
    
    # Target path for plan (relative to project root)
    $planRelPath = "$($Paths.RunsRelativePath)/$RunId/plan-$($CurrentRequirement.id).md"
    $planOutputPath = Join-Path $Paths.ProjectPath $planRelPath
    
    if ($Mode -eq "planning") {
        $contextParts += "# Plan Output Path`n`nYou MUST generate a requirement-specific plan and save it to: **$planOutputPath**`n`nThis plan should contain ONLY tasks for requirement $($CurrentRequirement.id)."
    }
    else {
        $contextParts += "# Plan Update Path`n`nWhen marking tasks complete, update the plan at: **$planOutputPath**"
    }
    
    # Add git commit instructions based on settings
    $requirementCommitSetting = $CurrentRequirement.commit_on_complete
    if ($null -ne $requirementCommitSetting) {
        $shouldAgentCommit = $requirementCommitSetting -and -not $NoCommit
    }
    else {
        $shouldAgentCommit = $Config.executor.commit_on_complete -and -not $NoCommit
    }
    
    if ($shouldAgentCommit) {
        $contextParts += "# Git Commit Instructions`n`n**Do NOT run git commands.** Your changes will be automatically staged and committed after validation passes.`n`nThe system will:`n1. Stage all changes automatically`n2. Run backpressure validation (tests/build/lint)`n3. Commit with proper message formatting`n4. Apply git-commit-rules to strip unwanted content`n`nDo NOT push changes to remote."
    }
    else {
        $contextParts += "# Git Commit Instructions`n`n**Do NOT commit changes.** The commit_on_complete setting is disabled. Your changes will be captured but not committed to git history."
    }
    
    # Workflow Stage: build_prompt
    Set-WorkflowStage -Stage "build_prompt" -ProjectPath $Paths.ProjectPath
    
    # ── v2: Assemble placeholder sources and apply context budget ──────────
    $repoRoot = if (Get-Command Resolve-RepoRoot -ErrorAction SilentlyContinue) {
        Resolve-RepoRoot -Path $Paths.ProjectPath
    } else { $Paths.ProjectPath }

    # A1: Layered AGENTS.md context
    $layeredAgentsContent = ""
    if (Get-Command Get-LayeredAgentsContext -ErrorAction SilentlyContinue) {
        try {
            $layeredResult = Get-LayeredAgentsContext -StartPath $Paths.ProjectPath -RepoRoot $repoRoot
            $layeredAgentsContent = $layeredResult.Blob
        } catch { $layeredAgentsContent = "" }
    } else {
        # v1 fallback: single AGENTS.md
        if ($Paths.AgentsFile -and (Test-Path $Paths.AgentsFile)) {
            $layeredAgentsContent = Get-Content $Paths.AgentsFile -Raw -ErrorAction SilentlyContinue
        }
    }

    # Repo map: extract ## Map section from root AGENTS.md if present
    $repoMapContent = ""
    $rootAgentsPath = Join-Path $repoRoot "AGENTS.md"
    if (Test-Path $rootAgentsPath) {
        $rootAgents = Get-Content $rootAgentsPath -Raw -ErrorAction SilentlyContinue
        if ($rootAgents -match "(?s)## Map\s*\n(.*?)(\n##|\z)") {
            $repoMapContent = $Matches[1].Trim()
        }
    }

    # B3: Skills - load and match skills against current context
    $skillsContent = ""
    $skillLoaderPath = if ($Paths.FelixDir) { Join-Path $Paths.FelixDir "core\skill-loader.ps1" } else { $null }
    if ($skillLoaderPath -and (Test-Path $skillLoaderPath)) {
        . $skillLoaderPath
        try {
            # Parse spec frontmatter for applyTo, tags (B5)
            $specFrontmatter = @{}
            $frontmatterParserPath = Join-Path $Paths.FelixDir "core\frontmatter-parser.ps1"
            if (Test-Path $frontmatterParserPath) {
                . $frontmatterParserPath
                $specFilePath2 = Join-Path $Paths.ProjectPath $specPath
                if (Test-Path $specFilePath2) {
                    $fm = Get-SpecFrontmatter -SpecPath $specFilePath2
                    if ($fm) { $specFrontmatter = $fm }
                }
            }
            $skillsContent = Invoke-SkillLoader `
                -RepoRoot $repoRoot `
                -Config $(if ($Config) { $Config } else { @{} }) `
                -CurrentCommand $CurrentCommand `
                -RequirementApplyTo @($(if ($specFrontmatter -and $specFrontmatter.applyTo) { $specFrontmatter.applyTo } else { @() })) `
                -RequirementTags    @($(if ($specFrontmatter -and $specFrontmatter.tags) { $specFrontmatter.tags } else { @() })) `
                -TaskDescription    $(if ($TaskDescription) { $TaskDescription } else { "" })
        } catch { $skillsContent = "" }
    }

    # Spec content
    $specContent = ""
    $specFilePath = Join-Path $Paths.ProjectPath $specPath
    if (Test-Path $specFilePath) {
        $specContent = Get-Content $specFilePath -Raw -ErrorAction SilentlyContinue
    }

    # Plan content
    $planContentForBudget = if ($PlanContent) { $PlanContent } else { "" }

    # C3: Context Map - load from runs/<run-id>/context-map.md if present
    $contextMapContent = ""
    $contextMapPath = Join-Path $RunDir "context-map.md"
    if (Test-Path $contextMapPath) {
        $contextMapContent = Get-Content $contextMapPath -Raw -ErrorAction SilentlyContinue
        if ($contextMapContent) {
            Emit-Log -Level "debug" -Message "context-map.md loaded ($([int]($contextMapContent.Length/4)) tokens est.)" -Component "prompt-builder"
        }
    }

    # Build sources hashtable for budgeter
    $budgetSources = @{
        layered_agents = $layeredAgentsContent
        repo_map       = $repoMapContent
        spec           = $specContent
        plan           = $planContentForBudget
        context_map    = $contextMapContent
        skills         = $skillsContent
        memory         = ""   # filled below by Phase E
        extras         = ($contextParts -join "`n`n---`n`n")
    }

    # E4: Load memory context (.felix/memory/ tree)
    if (Get-Command Get-MemoryContext -ErrorAction SilentlyContinue) {
        try {
            $memContent = Get-MemoryContext `
                -FelixDir $Paths.FelixDir `
                -RequirementId $CurrentRequirement.id
            if ($memContent) {
                $budgetSources.memory = $memContent
                Emit-Log -Level "debug" -Message "Memory context loaded ($([int]($memContent.Length/4)) tokens est.)" -Component "prompt-builder"
            }
        } catch { $budgetSources.memory = "" }
    }

    # Apply budget (A5)
    $budgetTokens = if (Get-Command Get-BudgetTokens -ErrorAction SilentlyContinue) {
        Get-BudgetTokens -Config $Config
    } else { 32000 }

    $budgetResult = if (Get-Command Invoke-ContextBudget -ErrorAction SilentlyContinue) {
        Invoke-ContextBudget -Sources $budgetSources -BudgetTokens $budgetTokens
    } else {
        @{ Sources = $budgetSources; Summary = "tokens: ?/?"; Evicted = @() }
    }

    # Print budget summary per iteration
    if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
        Emit-Log -Level "info" -Message $budgetResult.Summary -Component "context-budgeter"
    }

    # Fill placeholders in template (unresolved placeholders → empty string)
    $fullPrompt = $promptTemplate `
        -replace '\{\{LAYERED_AGENTS\}\}', $budgetResult.Sources.layered_agents `
        -replace '\{\{REPO_MAP\}\}',       $budgetResult.Sources.repo_map `
        -replace '\{\{SPEC\}\}',           $budgetResult.Sources.spec `
        -replace '\{\{PLAN\}\}',           $budgetResult.Sources.plan `
        -replace '\{\{CONTEXT_MAP\}\}',    $budgetResult.Sources.context_map `
        -replace '\{\{SKILLS\}\}',         $budgetResult.Sources.skills `
        -replace '\{\{MEMORY\}\}',         $budgetResult.Sources.memory

    # Append legacy-style context block for templates that don't use placeholders
    $context = $budgetResult.Sources.extras
    $fullPrompt = "$fullPrompt`n`n---`n`n# Project Context`n`n$context"
    
    # Hook: OnContextGathering
    $gitDiff = ""
    if (Test-Path (Join-Path $Paths.ProjectPath ".git")) {
        Push-Location $Paths.ProjectPath
        $prevErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $gitDiff = git diff 2>$null
        }
        catch {
            $gitDiff = ""
        }
        finally {
            $ErrorActionPreference = $prevErrorAction
            Pop-Location
        }
    }
    $hookResult = Invoke-PluginHookSafely -HookName "OnContextGathering" -RunId $RunId -HookData @{
        Mode               = $Mode
        CurrentRequirement = $CurrentRequirement
        GitDiff            = $gitDiff
        PlanContent        = if ($Mode -eq "building" -and $PlanContent) { $PlanContent } else { "" }
        ContextFiles       = $contextParts
    }
    
    if ($hookResult.AdditionalContext) {
        Write-Verbose "[PLUGINS] Adding additional context from plugins"
        $fullPrompt += "`n`n---`n`n# Additional Context (Plugins)`n`n$($hookResult.AdditionalContext)"
    }
    
    return $fullPrompt
}

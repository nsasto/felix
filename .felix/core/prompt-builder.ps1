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
        [switch]$NoCommit
    )
    
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
    
    # Reference AGENTS.md and CONTEXT.md instead of embedding full content
    # This reduces token bloat and forces agents to actively read these files
    $contextParts += "# File References - Read These from Disk`n`nThe system provides these reference files in the project root (read them yourself):`n`n- **AGENTS.md** - contains 'How to Run This Project' with commands for testing, building, and running the application`n- **CONTEXT.md** - contains project structure, technology stack, conventions, and patterns`n`nRead these files from the project root before starting work. Both are essential to understanding how to complete this requirement."
    
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
    $specPath = if ($CurrentRequirement.spec_path) { $CurrentRequirement.spec_path } else { "specs/$($CurrentRequirement.id).md" }
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
    $planRelPath = "runs/$RunId/plan-$($CurrentRequirement.id).md"
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
    
    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"
    
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

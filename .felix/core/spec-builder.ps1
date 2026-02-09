# Spec Builder Core Module
# Handles interactive spec creation with LLM conversation

function Invoke-SpecBuilder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,
        
        [Parameter(Mandatory = $false)]
        [string]$InitialPrompt,
        
        [Parameter(Mandatory = $false)]
        [switch]$QuickMode,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AgentConfig,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Paths
    )
    
    Emit-Log -Level "info" -Message "Starting spec builder for $RequirementId" -Component "spec-builder"
    
    # Validate requirement ID format
    if ($RequirementId -notmatch '^S-\d{4}$') {
        Emit-Error -ErrorType "InvalidRequirementId" -Message "Requirement ID must be in format S-NNNN (e.g., S-0010)" -Severity "fatal"
        return @{ ExitCode = 1 }
    }
    
    # Check if spec already exists (with any slug)
    $existingSpec = Get-ChildItem -Path $Paths.SpecsDir -Filter "$RequirementId*.md" -ErrorAction SilentlyContinue
    if ($existingSpec) {
        Emit-Error -ErrorType "SpecAlreadyExists" -Message "Spec $RequirementId already exists at $($existingSpec.FullName)" -Severity "fatal"
        return @{ ExitCode = 1 }
    }
    
    # Load system prompt
    $systemPromptPath = Join-Path $Paths.PromptsDir "spec-builder.md"
    if (-not (Test-Path $systemPromptPath)) {
        Emit-Error -ErrorType "MissingPrompt" -Message "Spec builder prompt not found at $systemPromptPath" -Severity "fatal"
        return @{ ExitCode = 1 }
    }
    $systemPrompt = Get-Content $systemPromptPath -Raw
    
    # Add quick mode instructions if enabled
    if ($QuickMode) {
        $systemPrompt += "`n`n## QUICK MODE`n`n"
        $systemPrompt += "**You are in QUICK MODE.** This means:`n"
        $systemPrompt += "- Ask NO MORE THAN 2 clarifying questions`n"
        $systemPrompt += "- Make reasonable assumptions based on the existing Felix architecture`n"
        $systemPrompt += "- Focus only on critical ambiguities`n"
        $systemPrompt += "- After minimal clarification, generate the spec immediately`n"
    }
    
    # Gather context documents
    $context = Get-SpecBuilderContext -ProjectPath $Paths.ProjectPath -SpecsDir $Paths.SpecsDir
    
    # Initialize conversation
    $messages = @(
        @{
            role    = "system"
            content = $systemPrompt
        }
    )
    
    # Add context to first user message
    $contextMessage = @"
# Repository Context

$context

---

# Task

I need help creating a specification for requirement ID: $RequirementId
"@
    
    if ($InitialPrompt) {
        $contextMessage += "`n`nHere's what I want to build: $InitialPrompt"
        $contextMessage += "`n`nPlease ask me clarifying questions to understand what I need, then we'll create the spec together."
    }
    else {
        $contextMessage += "`n`nPlease ask me questions about what this requirement should do, and we'll build the specification together."
    }
    
    $messages += @{
        role    = "user"
        content = $contextMessage
    }
    
    # Start conversation loop
    Emit-SpecBuilderStarted -RequirementId $RequirementId
    
    # Display welcome banner
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host "  Spec Builder Started" -ForegroundColor Magenta
    Write-Host "  Requirement: $RequirementId" -ForegroundColor Magenta
    if ($QuickMode) {
        Write-Host "  Mode: Quick (minimal questions)" -ForegroundColor Magenta
    }
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host ""
    
    $maxTurns = 20
    $turnCount = 0
    $specComplete = $false
    $suggestedFilename = $null
    
    while ($turnCount -lt $maxTurns -and -not $specComplete) {
        $turnCount++
        Emit-Log -Level "debug" -Message "Spec builder turn $turnCount" -Component "spec-builder"
        
        # Call droid
        try {
            $response = Invoke-Droid -Messages $messages -Config $Config -AgentConfig $AgentConfig -Paths $Paths
        }
        catch {
            Emit-Error -ErrorType "DroidCallFailed" -Message "Failed to call droid: $_" -Severity "fatal"
            return @{ ExitCode = 1 }
        }
        
        $assistantMessage = $response
        $messages += @{
            role    = "assistant"
            content = $assistantMessage
        }
        
        # Parse response for events
        $events = Parse-SpecBuilderResponse -Response $assistantMessage
        
        foreach ($event in $events) {
            switch ($event.type) {
                "filename" {
                    # Store suggested filename for later use
                    $suggestedFilename = $event.content
                    Emit-Log -Level "debug" -Message "AI suggested filename: $suggestedFilename" -Component "spec-builder"
                }
                
                "question" {
                    Emit-SpecQuestion -Question $event.content
                    
                    # Check if running interactively (stdin is available and not redirected)
                    $isInteractive = [Console]::IsInputRedirected -eq $false -and [Environment]::UserInteractive
                    
                    if ($isInteractive) {
                        # Interactive mode: display formatted question and prompt for answer
                        Write-Host ""
                        Write-Host "============================================================" -ForegroundColor Cyan
                        Write-Host "  Question from AI" -ForegroundColor Cyan
                        Write-Host "============================================================" -ForegroundColor Cyan
                        Write-Host ""
                        
                        # Format markdown: **bold** and bullet points
                        $formatted = $event.content -replace '\\n', "`n"
                        $formatted = $formatted -replace '\*\*([^\*]+)\*\*', '$1'  # Remove ** markers (bold in markdown)
                        Write-Host $formatted
                        
                        Write-Host ""
                        $userInput = Read-Host "Your answer (or type cancel to abort)"
                        
                        if ($userInput -eq "cancel") {
                            Emit-SpecBuilderCancelled
                            return @{ ExitCode = 0 }
                        }
                    }
                    else {
                        # File-based mode: for UI/TUI integration
                        $promptId = "spec_q_$turnCount"
                        $promptFile = Join-Path $Paths.ProjectPath ".felix\prompts\$promptId.txt"
                        $responseFile = Join-Path $Paths.ProjectPath ".felix\prompts\$promptId.response.txt"
                        $cancelFile = Join-Path $Paths.ProjectPath ".felix\prompts\$promptId.cancel"
                        
                        # Clean up any previous response files
                        if (Test-Path $responseFile) { Remove-Item $responseFile -Force }
                        if (Test-Path $cancelFile) { Remove-Item $cancelFile -Force }
                        
                        # Write prompt
                        $event.content | Set-Content $promptFile -Encoding UTF8
                        
                        # Emit prompt requested event (using standard Emit-Event)
                        Emit-Event -EventType "prompt_requested" -Data @{
                            prompt_id     = $promptId
                            question      = $event.content
                            prompt_file   = $promptFile
                            response_file = $responseFile
                        }
                        
                        # Wait for response file or cancel file
                        $timeout = 300 # 5 minutes
                        $elapsed = 0
                        while ($elapsed -lt $timeout) {
                            if (Test-Path $cancelFile) {
                                Emit-SpecBuilderCancelled
                                return @{ ExitCode = 0 }
                            }
                            
                            if (Test-Path $responseFile) {
                                $userInput = Get-Content $responseFile -Raw
                                break
                            }
                            
                            Start-Sleep -Milliseconds 500
                            $elapsed += 0.5
                        }
                        
                        if (-not $userInput -or $elapsed -ge $timeout) {
                            Emit-Error -ErrorType "PromptTimeout" -Message "No response received within timeout period" -Severity "fatal"
                            return @{ ExitCode = 1 }
                        }
                        
                        # Clean up prompt files
                        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
                        Remove-Item $responseFile -Force -ErrorAction SilentlyContinue
                    }
                    
                    # Add user response to conversation
                    $messages += @{
                        role    = "user"
                        content = $userInput
                    }
                }
                
                "draft" {
                    Emit-SpecDraft -Content $event.content
                }
                
                "complete" {
                    # Use suggested filename or generate from title
                    $slug = $null
                    
                    if ($suggestedFilename) {
                        # Use AI-suggested filename
                        $slug = $suggestedFilename
                    }
                    else {
                        # Fallback: extract title and generate slug
                        $title = "untitled"
                        if ($event.content -match '#\s+S-\d{4}:\s+(.+)') {
                            $title = $Matches[1].Trim()
                        }
                        elseif ($event.content -match '#\s+(.+)') {
                            $title = $Matches[1].Trim()
                        }
                        
                        # Generate slug from title
                        $slug = $title.ToLower() `
                            -replace '[^\w\s-]', '' `
                            -replace '\s+', '-' `
                            -replace '-+', '-' `
                            -replace '^-|-$', ''
                    }
                    
                    # Build final spec path with slug
                    $finalSpecPath = Join-Path $Paths.SpecsDir "$RequirementId-$slug.md"
                    
                    # Write spec file
                    Set-Content -Path $finalSpecPath -Value $event.content -Encoding UTF8
                    Emit-Log -Level "info" -Message "Spec written to $finalSpecPath" -Component "spec-builder"
                    
                    # Update requirements.json
                    $result = Add-RequirementToJson -RequirementId $RequirementId -SpecPath $finalSpecPath -RequirementsFile $Paths.RequirementsFile
                    
                    if ($result) {
                        Emit-SpecBuilderComplete -RequirementId $RequirementId -SpecPath $finalSpecPath
                        $specComplete = $true
                        
                        # Display success message
                        $filename = Split-Path $finalSpecPath -Leaf
                        Write-Host ""
                        Write-Host "✅ Spec created successfully!" -ForegroundColor Green
                        Write-Host "   ID:       " -NoNewline -ForegroundColor Cyan
                        Write-Host $RequirementId
                        Write-Host "   File:     " -NoNewline -ForegroundColor Cyan
                        Write-Host $filename
                        Write-Host "   Location: " -NoNewline -ForegroundColor Cyan
                        Write-Host $finalSpecPath
                        Write-Host ""
                    }
                    else {
                        Emit-Error -ErrorType "FailedToUpdateRequirements" -Message "Failed to update requirements.json" -Severity "fatal"
                        return @{ ExitCode = 1 }
                    }
                }
            }
        }
    }
    
    if ($turnCount -ge $maxTurns) {
        Emit-Error -ErrorType "MaxTurnsReached" -Message "Spec builder exceeded maximum turns ($maxTurns)" -Severity "error"
        return @{ ExitCode = 1 }
    }
    
    return @{ ExitCode = 0 }
}

function Get-SpecBuilderContext {
    param(
        [string]$ProjectPath,
        [string]$SpecsDir
    )
    
    $contextParts = @()
    
    # README
    $readmePath = Join-Path $ProjectPath "README.md"
    if (Test-Path $readmePath) {
        $readme = Get-Content $readmePath -Raw
        $contextParts += "## README.md`n`n$readme`n"
    }
    
    # AGENTS.md
    $agentsPath = Join-Path $ProjectPath "AGENTS.md"
    if (Test-Path $agentsPath) {
        $agents = Get-Content $agentsPath -Raw
        $contextParts += "## AGENTS.md (How to Run Commands)`n`n$agents`n"
    }
    
    # spec_rules.md
    $rulesPath = Join-Path $ProjectPath ".felix\prompts\spec_rules.md"
    if (Test-Path $rulesPath) {
        $rules = Get-Content $rulesPath -Raw
        $contextParts += "## spec_rules.md (Specification Format Rules)`n`n$rules`n"
    }
    
    # One or two example specs for format reference only (if any exist)
    $specs = Get-ChildItem $SpecsDir -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -First 2
    if ($specs -and $specs.Count -gt 0) {
        $contextParts += "## Example Specification Format`n`n"
        foreach ($spec in $specs) {
            $content = Get-Content $spec.FullName -Raw
            $contextParts += "### $($spec.Name)`n`n````markdown`n$content`n`````n`n"
        }
    }
    else {
        $contextParts += "## Example Specification Format`n`n"
        $contextParts += "(No existing specs - this will be the first one. Follow spec_rules.md format.)`n`n"
    }
    
    return $contextParts -join "`n"
}

function Parse-SpecBuilderResponse {
    param([string]$Response)
    
    $events = @()
    
    # Look for XML-style tags (use (?s) flag to match across newlines)
    # Check for filename suggestion
    if ($Response -match '(?s)<filename>(.*?)</filename>') {
        $events += @{
            type    = "filename"
            content = $Matches[1].Trim()
        }
    }
    
    # Check for question
    if ($Response -match '(?s)<question>(.*?)</question>') {
        $events += @{
            type    = "question"
            content = $Matches[1].Trim()
        }
    }
    
    # Check for draft (legacy support)
    if ($Response -match '(?s)<draft>(.*?)</draft>') {
        $events += @{
            type    = "draft"
            content = $Matches[1].Trim()
        }
    }
    
    # Check for complete spec
    if ($Response -match '(?s)<spec>(.*?)</spec>') {
        $events += @{
            type    = "complete"
            content = $Matches[1].Trim()
        }
    }
    
    # If no special tags found, treat as question
    if ($events.Count -eq 0) {
        $events += @{
            type    = "question"
            content = $Response
        }
    }
    
    return $events
}

function Add-RequirementToJson {
    param(
        [string]$RequirementId,
        [string]$SpecPath,
        [string]$RequirementsFile
    )
    
    try {
        # Load requirements
        $requirementsData = @{ requirements = @() }
        if (Test-Path $RequirementsFile) {
            $requirementsData = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        }
        
        $requirements = @($requirementsData.requirements)
        
        # Check if already exists
        if ($requirements | Where-Object { $_.id -eq $RequirementId }) {
            Emit-Error -ErrorType "RequirementExists" -Message "Requirement $RequirementId already exists in requirements.json" -Severity "error"
            return $false
        }
        
        # Extract title from spec
        $specContent = Get-Content $SpecPath -Raw
        $title = "Untitled"
        if ($specContent -match '# (.+)') {
            $title = $Matches[1].Trim()
        }
        
        # Add new requirement
        $newRequirement = @{
            id         = $RequirementId
            title      = $title
            status     = "planned"
            spec_file  = (Resolve-Path $SpecPath -Relative)
            depends_on = @()
            created_at = Get-Date -Format "o"
            updated_at = Get-Date -Format "o"
        }
        
        $requirements += $newRequirement
        
        # Sort by ID
        $requirements = $requirements | Sort-Object id
        
        # Wrap in requirements object and save
        $requirementsData = @{ requirements = $requirements }
        $requirementsData | ConvertTo-Json -Depth 10 | Set-Content $RequirementsFile -Encoding UTF8
        
        Emit-Log -Level "info" -Message "Added $RequirementId to requirements.json" -Component "spec-builder"
        return $true
    }
    catch {
        Emit-Error -ErrorType "RequirementsUpdateFailed" -Message "Failed to update requirements.json: $_" -Severity "error"
        return $false
    }
}

# NDJSON event emitters for spec builder

function Emit-SpecBuilderStarted {
    param([string]$RequirementId)
    
    Emit-Event -EventType "spec_builder_started" -Data @{
        requirement_id = $RequirementId
    }
}

function Emit-SpecQuestion {
    param([string]$Question)
    
    Emit-Event -EventType "spec_question" -Data @{
        question = $Question
    }
}

function Emit-SpecDraft {
    param([string]$Content)
    
    Emit-Event -EventType "spec_draft" -Data @{
        content = $Content
    }
}

function Emit-SpecBuilderComplete {
    param(
        [string]$RequirementId,
        [string]$SpecPath
    )
    
    Emit-Event -EventType "spec_builder_complete" -Data @{
        requirement_id = $RequirementId
        spec_file      = $SpecPath
    }
}

function Emit-SpecBuilderCancelled {
    Emit-Event -EventType "spec_builder_cancelled" -Data @{}
}

function Invoke-Droid {
    param(
        [array]$Messages,
        [PSCustomObject]$Config,
        [PSCustomObject]$AgentConfig,
        [PSCustomObject]$Paths
    )
    
    # Format messages for droid - include system message first, then conversation
    $prompt = ""
    
    # Add system message if present
    $systemMsg = $Messages | Where-Object { $_.role -eq "system" } | Select-Object -First 1
    if ($systemMsg) {
        $prompt += $systemMsg.content + "`n`n---`n`n"
    }
    
    # Add conversation history (user and assistant messages)
    foreach ($msg in $Messages) {
        if ($msg.role -eq "user") {
            $prompt += "User: " + $msg.content + "`n`n"
        }
        elseif ($msg.role -eq "assistant") {
            $prompt += "Assistant: " + $msg.content + "`n`n"
        }
    }
    
    # Call droid CLI directly (like Invoke-AgentExecution does)
    $executable = $AgentConfig.executable
    $agentArgs = $AgentConfig.args
    $agentWorkingDir = if ($AgentConfig.working_directory) { $AgentConfig.working_directory } else { "." }
    
    $agentCwd = if ([System.IO.Path]::IsPathRooted($agentWorkingDir)) {
        $agentWorkingDir
    }
    else {
        Join-Path $Paths.ProjectPath $agentWorkingDir
    }
    
    $envBackup = @{}
    try {
        # Apply agent environment variables if any
        if ($AgentConfig.environment) {
            foreach ($prop in $AgentConfig.environment.PSObject.Properties) {
                $key = $prop.Name
                $value = [string]$prop.Value
                $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
        
        Push-Location $agentCwd
        try {
            # Pipe prompt to droid executable (same pattern as Invoke-AgentExecution)
            $output = $prompt | & $executable @agentArgs 2>&1 | Out-String
        }
        finally {
            Pop-Location
        }
    }
    finally {
        # Restore environment variables
        foreach ($key in $envBackup.Keys) {
            [Environment]::SetEnvironmentVariable($key, $envBackup[$key], "Process")
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Droid execution failed with exit code ${LASTEXITCODE}"
    }
    
    return $output.Trim()
}

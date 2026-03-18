# Context Builder Module
# Analyzes project structure and generates comprehensive CONTEXT.md

function Invoke-ContextBuilder {
    <#
    .SYNOPSIS
    Analyzes project and generates/updates CONTEXT.md
    
    .DESCRIPTION
    Performs autonomous analysis of project structure, tech stack, and architecture
    to generate comprehensive CONTEXT.md documentation. Includes existing CONTEXT.md
    to identify gaps. Creates timestamped backups before overwriting.
    
    .PARAMETER ProjectPath
    Path to the project root
    
    .PARAMETER IncludeHidden
    Include hidden files and folders in analysis (default: exclude)
    
    .PARAMETER Force
    Skip overwrite confirmation (default: inform but don't prompt)
    
    .PARAMETER Config
    Felix configuration object
    
    .PARAMETER AgentConfig
    Agent configuration object
    
    .PARAMETER Paths
    Paths configuration object
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeHidden,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AgentConfig,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Paths
    )
    
    Emit-Log -Level "info" -Message "Starting context builder" -Component "context-builder"
    
    # Check if CONTEXT.md exists
    $contextPath = Join-Path $ProjectPath "CONTEXT.md"
    $existingContext = $null
    
    if (Test-Path $contextPath) {
        $existingContext = Get-Content $contextPath -Raw -ErrorAction SilentlyContinue
        
        if ($existingContext) {
            Emit-Log -Level "warn" -Message "CONTEXT.md already exists, will update with gap analysis" -Component "context-builder"
            
            # Create timestamped backup
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = Join-Path $ProjectPath "CONTEXT.md.bak-$timestamp"
            
            try {
                Copy-Item $contextPath $backupPath -Force
                $backupFilename = Split-Path $backupPath -Leaf
                Emit-Log -Level "info" -Message "Backed up existing CONTEXT.md to $backupFilename" -Component "context-builder"
            }
            catch {
                Emit-Log -Level "warn" -Message "Failed to create backup: $_" -Component "context-builder"
            }
        }
    }
    
    # Gather project structure
    Emit-Log -Level "info" -Message "Scanning project structure..." -Component "context-builder"
    $projectStructure = Get-ProjectStructure -ProjectPath $ProjectPath -ExcludeHidden (-not $IncludeHidden)
    
    # Build context for LLM
    $contextParts = @()
    
    # Include existing CONTEXT.md if present
    if ($existingContext) {
        $contextParts += "# Existing CONTEXT.md`n`n$existingContext`n`n---`n"
        $contextParts += "**Your task**: Review the above CONTEXT.md and update it. Add missing sections, correct outdated info, expand on gaps.`n"
    }
    else {
        $contextParts += "**Your task**: Generate a comprehensive CONTEXT.md from scratch.`n"
    }
    
    # Add project structure summary
    $contextParts += "`n# Project Structure Summary`n`n$($projectStructure.Summary)`n"
    
    # Add key files content
    $contextParts += "`n# Key Files`n"
    
    # README.md
    $readmePath = Join-Path $ProjectPath "README.md"
    if (Test-Path $readmePath) {
        $readme = Get-Content $readmePath -Raw -ErrorAction SilentlyContinue
        if ($readme) {
            # Truncate if too long (keep first 3000 chars)
            if ($readme.Length -gt 3000) {
                $readme = $readme.Substring(0, 3000) + "`n`n[... truncated ...]"
            }
            $contextParts += "`n## README.md`n`n$readme`n"
        }
    }
    
    # AGENTS.md
    if (Test-Path $Paths.AgentsFile) {
        $agents = Get-Content $Paths.AgentsFile -Raw -ErrorAction SilentlyContinue
        if ($agents) {
            if ($agents.Length -gt 2000) {
                $agents = $agents.Substring(0, 2000) + "`n`n[... truncated ...]"
            }
            $contextParts += "`n## AGENTS.md`n`n$agents`n"
        }
    }
    
    # Learnings index (points agents to topic files in learnings/)
    $learningsIndexPath = Join-Path (Join-Path $ProjectPath "learnings") "README.md"
    if (Test-Path $learningsIndexPath) {
        $learningsIndex = Get-Content $learningsIndexPath -Raw -ErrorAction SilentlyContinue
        if ($learningsIndex) {
            $contextParts += "`n## Learnings Index`n`n$learningsIndex`n"
        }
    }
    
    # Package manifests for stack detection
    $manifestFiles = @("package.json", "requirements.txt", "pyproject.toml", "Pipfile", "poetry.lock", "Cargo.toml", "go.mod")
    foreach ($manifest in $manifestFiles) {
        $manifestPath = Join-Path $ProjectPath $manifest
        if (Test-Path $manifestPath) {
            $content = Get-Content $manifestPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Truncate if very long
                if ($content.Length -gt 1500) {
                    $content = $content.Substring(0, 1500) + "`n... truncated ..."
                }
                $contextParts += "`n## $manifest`n`n``````n$content`n```````n"
            }
        }
    }
    
    # Add sample source files for pattern detection
    $contextParts += "`n## Sample Source Files`n`n"
    $contextParts += "Based on file tree, key directories include:`n"
    foreach ($dir in $projectStructure.Tree.Directories | Select-Object -First 20) {
        $contextParts += "- $dir`n"
    }
    
    # Load build_context.md prompt
    $promptPath = Join-Path $Paths.PromptsDir "build_context.md"
    if (-not (Test-Path $promptPath)) {
        Emit-Error -ErrorType "PromptNotFound" -Message "build_context.md prompt not found at $promptPath" -Severity "fatal"
        return @{ ExitCode = 1 }
    }
    $systemPrompt = Get-Content $promptPath -Raw
    
    # Combine prompt and context
    $fullPrompt = "$systemPrompt`n`n---`n`n# Project Analysis Input`n`n$($contextParts -join "`n")"
    
    # Call agent to analyze and write CONTEXT.md
    Emit-Log -Level "info" -Message "Calling agent for analysis..." -Component "context-builder"
    
    try {
        $response = Invoke-AgentForContextBuild -Prompt $fullPrompt -Config $Config -AgentConfig $AgentConfig -Paths $Paths
        
        # Show agent's response message
        if ($response) {
            Write-Host ""
            Write-Host "Agent response:" -ForegroundColor Gray
            Write-Host $response
            Write-Host ""
        }
    }
    catch {
        Emit-Error -ErrorType "AgentCallFailed" -Message "Failed to call agent: $_" -Severity "fatal"
        return @{ ExitCode = 1 }
    }
    
    # Verify the file was created/updated
    if (-not (Test-Path $contextPath)) {
        Emit-Error -ErrorType "NoContextGenerated" -Message "Agent did not create CONTEXT.md" -Severity "fatal"
        return @{ ExitCode = 1 }
    }
    
    Emit-Log -Level "info" -Message "CONTEXT.md written to $contextPath" -Component "context-builder"
    
    # Success
    Write-Host ""
    Write-Host "✅ CONTEXT.md generated successfully!" -ForegroundColor Green
    Write-Host "   Location: $contextPath" -ForegroundColor Cyan
    if ($existingContext) {
        Write-Host "   Backup:   CONTEXT.md.bak-$timestamp" -ForegroundColor Gray
    }
    Write-Host ""
    
    return @{ ExitCode = 0 }
}

function Get-ProjectStructure {
    <#
    .SYNOPSIS
    Scans project directory and builds structure summary
    
    .PARAMETER ProjectPath
    Path to project root
    
    .PARAMETER ExcludeHidden
    Exclude hidden files and folders (default behavior)
    #>
    param(
        [string]$ProjectPath,
        [bool]$ExcludeHidden = $true
    )
    
    # Exclusion patterns
    $excludeDirs = @(
        'node_modules', '__pycache__', '.pytest_cache', 
        'dist', 'build', 'obj', 'bin', '.vs', 'target',
        '.venv', 'venv', 'env',
        'runs'  # Felix run outputs
    )
    
    # Add .git explicitly
    $excludeDirs += '.git'
    
    # If excluding hidden, add pattern
    if ($ExcludeHidden) {
        # Will exclude directories starting with .
        $excludeHiddenPattern = $true
    }
    else {
        $excludeHiddenPattern = $false
    }
    
    $fileTree = @{
        Directories = [System.Collections.ArrayList]@()
        Files       = [System.Collections.ArrayList]@()
        Extensions  = @{}
        TotalSize   = 0
    }
    
    # Recursive scan
    try {
        Get-ChildItem -Path $ProjectPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $relativePath = $_.FullName.Replace($ProjectPath, '').TrimStart('\', '/')
            
            # Check exclusions
            $shouldExclude = $false
            foreach ($exclude in $excludeDirs) {
                if ($relativePath -like "*$exclude*") {
                    $shouldExclude = $true
                    break
                }
            }
            
            # Check hidden pattern
            if ($excludeHiddenPattern -and -not $shouldExclude) {
                $pathParts = $relativePath -split '[/\\]'
                foreach ($part in $pathParts) {
                    if ($part -like '.*') {
                        $shouldExclude = $true
                        break
                    }
                }
            }
            
            if (-not $shouldExclude) {
                if ($_.PSIsContainer) {
                    [void]$fileTree.Directories.Add($relativePath)
                }
                else {
                    [void]$fileTree.Files.Add($relativePath)
                    $ext = $_.Extension.ToLower()
                    if ($ext) {
                        if (-not $fileTree.Extensions.ContainsKey($ext)) {
                            $fileTree.Extensions[$ext] = 0
                        }
                        $fileTree.Extensions[$ext]++
                    }
                    $fileTree.TotalSize += $_.Length
                }
            }
        }
    }
    catch {
        # Silently continue on access errors
    }
    
    # Generate summary
    $summary = "Total Files: $($fileTree.Files.Count)`n"
    $summary += "Total Directories: $($fileTree.Directories.Count)`n"
    $summary += "Total Size: $([math]::Round($fileTree.TotalSize / 1MB, 2)) MB`n`n"
    $summary += "File Types (top 15):`n"
    
    $topExtensions = $fileTree.Extensions.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15
    foreach ($ext in $topExtensions) {
        $summary += "  $($ext.Key): $($ext.Value) files`n"
    }
    
    return @{
        Tree    = $fileTree
        Summary = $summary
    }
}

function Invoke-AgentForContextBuild {
    <#
    .SYNOPSIS
    Calls agent with context analysis prompt
    
    .DESCRIPTION
    Reuses existing agent execution infrastructure following LEARNINGS.md patterns
    for reliable process invocation and error handling
    #>
    param(
        [string]$Prompt,
        $Config,
        $AgentConfig,
        $Paths
    )
    
    # Get agent profile
    $agentId = $Config.agent.agent_id
    if ($null -eq $agentId) {
        $agentId = 0
    }
    
    $agentsConfigPath = Join-Path $Paths.FelixDir "agents.json"
    if (-not (Test-Path $agentsConfigPath)) {
        throw "agents.json not found at $agentsConfigPath"
    }
    
    $agentsConfig = Get-Content $agentsConfigPath -Raw | ConvertFrom-Json
    $agentProfile = $agentsConfig.agents | Where-Object { $_.key -eq $agentId -or $_.id -eq $agentId }
    if ($agentProfile -and -not $agentProfile.key -and $agentProfile.id) {
        $agentProfile | Add-Member -NotePropertyName 'key' -NotePropertyValue $agentProfile.id -Force
    }
    
    if (-not $agentProfile) {
        throw "Agent profile not found for ID: $agentId"
    }
    
    # Build agent command
    $agentExe = $agentProfile.executable
    
    # CRITICAL: Verify CommandType == 'Application' (LEARNINGS.md Issue 3)
    $cmd = Get-Command $agentExe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Agent executable not found: $agentExe"
    }
    
    if ($cmd.CommandType -ne 'Application') {
        throw "Agent executable is not an Application: $agentExe (found: $($cmd.CommandType))"
    }
    
    # Build argument array (direct array passing, not splatting - LEARNINGS.md pattern)
    $agentArgs = @()
    if ($agentProfile.args) {
        $agentArgs += $agentProfile.args
    }
    
    # Write prompt to temp file
    $tempPrompt = Join-Path $env:TEMP "felix-context-prompt-$(Get-Random).txt"
    Set-Content -Path $tempPrompt -Value $Prompt -Encoding UTF8
    
    try {
        # Execute agent (following LEARNINGS.md patterns)
        $prevErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"  # Allow stderr without termination (LEARNINGS.md)
        
        try {
            # Pipe prompt to agent
            $response = Get-Content $tempPrompt -Raw | & $cmd $agentArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prevErrorAction
        }
        
        if ($exitCode -ne 0) {
            throw "Agent failed with exit code: $exitCode"
        }
        
        return $response
    }
    finally {
        # Cleanup
        Remove-Item $tempPrompt -Force -ErrorAction SilentlyContinue
    }
}


# Context Builder Module
# Analyzes project structure and generates comprehensive CONTEXT.md

. "$PSScriptRoot/emit-event.ps1"
. "$PSScriptRoot\output-normalizer.ps1"
. "$PSScriptRoot\copilot-bridge.ps1"

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

    .PARAMETER VerboseMode
    Enable verbose agent execution for adapter-built arguments
    
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

        [Parameter(Mandatory = $false)]
        [bool]$VerboseMode = $false,
        
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
        $response = Invoke-AgentForContextBuild -Prompt $fullPrompt -Config $Config -AgentConfig $AgentConfig -Paths $Paths -VerboseMode:$VerboseMode
        
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
    Write-Host "[OK] CONTEXT.md generated successfully." -ForegroundColor Green
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
        $Paths,
        [bool]$VerboseMode = $false
    )

    if (-not (Get-Command Get-AgentConfig -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\config-loader.ps1"
    }

    if (-not (Get-Command Resolve-FelixExecutablePath -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\compat-utils.ps1"
    }

    if (-not (Get-Command Get-AgentAdapter -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\agent-adapters.ps1"
    }

    $agentProfile = $AgentConfig
    if (-not $agentProfile -or $agentProfile.PSObject.Properties['agents'] -or [string]::IsNullOrWhiteSpace([string]$agentProfile.executable)) {
        $agentsData = $null
        if ($AgentConfig -and $AgentConfig.PSObject.Properties['agents']) {
            $agentsData = $AgentConfig
        }
        else {
            $agentsConfigPath = Join-Path $Paths.FelixDir "agents.json"
            if (-not (Test-Path $agentsConfigPath)) {
                throw "agents.json not found at $agentsConfigPath"
            }

            $agentsData = Get-Content $agentsConfigPath -Raw | ConvertFrom-Json
        }

        $agentId = if ($Config.agent -and $null -ne $Config.agent.agent_id -and -not [string]::IsNullOrWhiteSpace([string]$Config.agent.agent_id)) {
            [string]$Config.agent.agent_id
        }
        else {
            $firstAgent = $agentsData.agents | Select-Object -First 1
            if (-not $firstAgent) {
                throw "No agents found in agents.json"
            }

            if ($firstAgent.key) { [string]$firstAgent.key } else { [string]$firstAgent.id }
        }

        $configFile = Join-Path $Paths.FelixDir "config.json"
        $agentProfile = Get-AgentConfig -AgentsData $agentsData -AgentId $agentId -ConfigFile $configFile
    }

    if (-not $agentProfile) {
        throw "Agent profile could not be resolved for context build"
    }

    $adapterType = if ($agentProfile.adapter) { $agentProfile.adapter } elseif ($agentProfile.name) { $agentProfile.name } else { "droid" }
    $adapter = Get-AgentAdapter -AdapterType $adapterType -ErrorAction SilentlyContinue
    $formattedPrompt = $Prompt
    $agentArgs = @()
    $promptMode = "stdin"

    if ($adapter) {
        $invocation = Get-AgentInvocation -AdapterType $adapterType -Config $agentProfile -Prompt $Prompt -VerboseMode:$VerboseMode
        $formattedPrompt = $invocation.FormattedPrompt
        $agentArgs = @($invocation.Arguments)
        $promptMode = $invocation.PromptMode
    }
    elseif ($agentProfile.args) {
        $agentArgs += $agentProfile.args
    }

    $agentWorkingDir = if ($agentProfile.working_directory) { $agentProfile.working_directory } else { "." }
    $agentCwd = if ([System.IO.Path]::IsPathRooted($agentWorkingDir)) {
        $agentWorkingDir
    }
    else {
        Join-Path $Paths.ProjectPath $agentWorkingDir
    }

    # Build agent command only for direct execution. Copilot bridge resolves the child executable internally.
    $agentExe = $null
    if (-not ($adapterType -eq "copilot" -and (Test-UseCopilotCliBridge))) {
        $agentExe = Resolve-FelixExecutablePath $agentProfile.executable
        if (-not $agentExe) {
            $agentName = if ($agentProfile.name) { $agentProfile.name } else { "unknown" }
            throw "Agent executable is empty or not found for agent '$agentName'. Run 'felix setup' or 'felix agent use <name|key>' to configure a valid agent."
        }

        $cmd = Get-Command $agentExe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Agent executable not found: $agentExe"
        }

        if ($cmd.CommandType -notin @('Application', 'ExternalScript')) {
            throw "Agent executable is not an Application: $agentExe (found: $($cmd.CommandType))"
        }
    }

    $envBackup = @{}
    
    $tempPrompt = $null
    if ($promptMode -eq "stdin") {
        $tempPrompt = Join-Path $env:TEMP "felix-context-prompt-$(Get-Random).txt"
        Set-Content -Path $tempPrompt -Value $formattedPrompt -Encoding UTF8
    }
    
    try {
        if ($adapterType -eq "copilot" -and (Test-UseCopilotCliBridge)) {
            Emit-Log -Level "info" -Message "Using C# Copilot bridge for context build" -Component "context-builder"
            $bridgeResult = Invoke-CopilotCliBridge -AgentConfig $agentProfile -Prompt $Prompt -WorkingDirectory $agentCwd
            $response = $bridgeResult.Output
            $exitCode = $bridgeResult.ExitCode
        }
        else {
            if ($agentProfile.environment) {
                foreach ($prop in $agentProfile.environment.PSObject.Properties) {
                    $key = $prop.Name
                    $value = [string]$prop.Value
                    $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                    [Environment]::SetEnvironmentVariable($key, $value, "Process")
                }
            }

            # Execute agent (following LEARNINGS.md patterns)
            $prevErrorAction = $ErrorActionPreference
            $ErrorActionPreference = "Continue"  # Allow stderr without termination (LEARNINGS.md)
            
            try {
                Push-Location $agentCwd
                try {
                    if ($promptMode -eq "argument") {
                        $response = & $agentExe @agentArgs 2>&1 | Out-String
                    }
                    else {
                        $response = Get-Content $tempPrompt -Raw | & $agentExe @agentArgs 2>&1 | Out-String
                    }
                }
                finally {
                    Pop-Location
                }
                $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
            }
            finally {
                $ErrorActionPreference = $prevErrorAction
            }
        }
        
        if ($exitCode -ne 0) {
            throw "Agent failed with exit code: $exitCode"
        }

        if ($adapter) {
            $normalizedResponse = Normalize-AgentOutput -Output $response -AdapterType $agentProfile.adapter
            $parsed = $adapter.ParseResponse($normalizedResponse)
            if ($parsed -and $parsed.Error) {
                throw $parsed.Error
            }

            if ($parsed -and $parsed.Output) {
                return $parsed.Output
            }
        }

        return $response
    }
    finally {
        foreach ($key in $envBackup.Keys) {
            [Environment]::SetEnvironmentVariable($key, $envBackup[$key], "Process")
        }

        # Cleanup
        if ($tempPrompt) {
            Remove-Item $tempPrompt -Force -ErrorAction SilentlyContinue
        }
    }
}


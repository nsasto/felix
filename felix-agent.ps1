#!/usr/bin/env pwsh
# Felix Agent - Ralph Loop Executor (PowerShell)
# Usage: .\felix-agent.ps1 <ProjectPath> [-RequirementId <ID>]
#
# VALID REQUIREMENT STATUS VALUES:
#   - draft: Initial state, not ready for work
#   - planned: Ready to be worked on
#   - in_progress: Currently being worked on
#   - complete: Finished and validated
#   - blocked: Cannot proceed (dependencies or validation failures)

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [string]$RequirementId = $null,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoCommit   # Use this flag for testing to prevent git commits
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
# Must be done in this specific order for Windows PowerShell compatibility
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"

# Resolve project path
try {
    $ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Invalid project path: $ProjectPath" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Felix Agent starting for: " -NoNewline
Write-Host $ProjectPath -ForegroundColor Cyan

# ============================================================================
# Mode Guardrails Functions
# ============================================================================

function Get-GitState {
    <#
    .SYNOPSIS
    Captures the current git state for guardrail comparison
    #>
    param([string]$WorkingDir)
    
    Push-Location $WorkingDir
    try {
        $state = @{
            CommitHash     = $null
            ModifiedFiles  = @()
            UntrackedFiles = @()
        }
        
        # Get current commit hash
        $state.CommitHash = git rev-parse HEAD 2>$null
        
        # Get list of modified files (staged and unstaged)
        $state.ModifiedFiles = @(git diff --name-only HEAD 2>$null)
        $staged = @(git diff --name-only --cached 2>$null)
        if ($staged) {
            $state.ModifiedFiles = @($state.ModifiedFiles) + @($staged) | Select-Object -Unique
        }
        
        # Get untracked files
        $state.UntrackedFiles = @(git ls-files --others --exclude-standard 2>$null)
        
        return $state
    }
    finally {
        Pop-Location
    }
}

function Test-PlanningModeGuardrails {
    <#
    .SYNOPSIS
    Checks if planning mode guardrails were violated (code files modified or committed)
    Returns a hashtable with violation details
    #>
    param(
        [string]$WorkingDir,
        [hashtable]$BeforeState,
        [string]$RunId
    )
    
    Push-Location $WorkingDir
    try {
        $violations = @{
            CommitMade        = $false
            UnauthorizedFiles = @()
            HasViolations     = $false
        }
        
        # Allowed paths for planning mode (relative paths)
        $allowedPatterns = @(
            "^runs/",                          # Run directories
            "^felix/state\.json$",             # State file
            "^felix/requirements\.json$"       # Requirements file
        )
        
        # Get current git state
        $afterState = Get-GitState -WorkingDir $WorkingDir
        
        # Check if a new commit was made
        if ($afterState.CommitHash -ne $BeforeState.CommitHash) {
            $violations.CommitMade = $true
            $violations.HasViolations = $true
            Write-Host "[GUARDRAIL VIOLATION] " -NoNewline -ForegroundColor Red
            Write-Host "New commit detected during planning mode!" -ForegroundColor Yellow
        }
        
        # Check for unauthorized file modifications
        $allModifiedFiles = @($afterState.ModifiedFiles) + @($afterState.UntrackedFiles) | 
        Where-Object { $_ -and $_.Trim() -ne "" } |
        Select-Object -Unique
        
        foreach ($file in $allModifiedFiles) {
            # Skip if file was already modified before
            if ($BeforeState.ModifiedFiles -contains $file -or $BeforeState.UntrackedFiles -contains $file) {
                continue
            }
            
            # Check if file matches allowed patterns
            $isAllowed = $false
            $normalizedFile = $file -replace '\\', '/'
            foreach ($pattern in $allowedPatterns) {
                if ($normalizedFile -match $pattern) {
                    $isAllowed = $true
                    break
                }
            }
            
            if (-not $isAllowed) {
                $violations.UnauthorizedFiles += $file
                $violations.HasViolations = $true
            }
        }
        
        if ($violations.UnauthorizedFiles.Count -gt 0) {
            Write-Host "[GUARDRAIL VIOLATION] " -NoNewline -ForegroundColor Red
            Write-Host "Unauthorized files modified in planning mode:" -ForegroundColor Yellow
            foreach ($file in $violations.UnauthorizedFiles) {
                Write-Host "  - $file"
            }
        }
        
        return $violations
    }
    finally {
        Pop-Location
    }
}

function Undo-PlanningViolations {
    <#
    .SYNOPSIS
    Reverts unauthorized changes made during planning mode
    #>
    param(
        [string]$WorkingDir,
        [hashtable]$BeforeState,
        [hashtable]$Violations
    )
    
    Push-Location $WorkingDir
    try {
        # Revert commit if one was made
        if ($Violations.CommitMade) {
            Write-Host "[GUARDRAIL] " -NoNewline -ForegroundColor Yellow
            Write-Host "Reverting unauthorized commit..." -ForegroundColor Yellow
            git reset --soft $BeforeState.CommitHash 2>$null
        }
        
        # Revert unauthorized file changes
        foreach ($file in $Violations.UnauthorizedFiles) {
            if (Test-Path $file) {
                # Check if it was an existing file (modified) or new file
                $wasTracked = git ls-files $file 2>$null
                if ($wasTracked) {
                    Write-Host "[GUARDRAIL] Reverting changes to: $file"
                    git checkout HEAD -- $file 2>$null
                }
                else {
                    Write-Host "[GUARDRAIL] Removing unauthorized new file: $file"
                    Remove-Item $file -Force
                }
            }
        }
        
        Write-Host "[GUARDRAIL] " -NoNewline -ForegroundColor Green
        Write-Host "Violations reverted." -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

function Update-RequirementStatus {
    <#
    .SYNOPSIS
    Updates the status of a requirement in felix/requirements.json
    
    .DESCRIPTION
    Valid status values: draft, planned, in_progress, complete, blocked
    Uses regex replacement to preserve original JSON formatting.
    #>
    param(
        [string]$RequirementsFilePath,
        [string]$RequirementId,
        [ValidateSet('draft', 'planned', 'in_progress', 'complete', 'blocked')]
        [string]$NewStatus
    )
    
    try {
        $json = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $found = $false
        if ($json.requirements) {
            foreach ($req in $json.requirements) {
                if ($req.id -eq $RequirementId) {
                    $req.status = $NewStatus
                    $req.updated_at = (Get-Date -Format "yyyy-MM-dd")
                    $found = $true
                    break
                }
            }
        }
        if (-not $found) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Warning: Requirement $RequirementId not found in requirements.json" -ForegroundColor Yellow
            return $false
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $RequirementsFilePath
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Updated $RequirementId status to '$NewStatus'" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Error updating requirements.json: $_" -ForegroundColor Red
        return $false
    }
}

function Update-RequirementRunId {
    <#
    .SYNOPSIS
    Updates the last_run_id field for a specific requirement in requirements.json
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    try {
        if (-not (Test-Path $RequirementsFilePath)) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Requirements file not found: $RequirementsFilePath" -ForegroundColor Red
            return $false
        }
        $json = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $found = $false
        foreach ($req in $json.requirements) {
            if ($req.id -eq $RequirementId) {
                # Always use Add-Member with -Force to handle both new and existing properties
                $req | Add-Member -NotePropertyName "last_run_id" -NotePropertyValue $RunId -Force
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Could not find requirement $RequirementId in requirements.json" -ForegroundColor Yellow
            return $false
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $RequirementsFilePath
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Updated $RequirementId with last_run_id: $RunId" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Error updating last_run_id: $_" -ForegroundColor Red
        return $false
    }
}

function Resolve-PythonCommand {
    <#
    .SYNOPSIS
    Resolves a usable Python command (application only) with optional args
    #>
    param(
        [object]$Config
    )
    
    $pythonCmd = $null
    $pythonArgs = @()
    
    if ($Config -and $Config.python -and $Config.python.executable) {
        $candidate = $Config.python.executable
        if ($Config.python.args) {
            $pythonArgs = @($Config.python.args)
        }
        
        if (Test-Path $candidate) {
            $pythonCmd = (Resolve-Path $candidate).Path
        }
        else {
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.CommandType -eq "Application") {
                $pythonCmd = $cmd.Source
            }
        }
        
        if (-not $pythonCmd) {
            throw "Python executable not found or not an application: $candidate"
        }
        
        return @{ cmd = $pythonCmd; args = $pythonArgs }
    }
    
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @("-3") }
    }
    
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @() }
    }
    
    $cmd = Get-Command python3 -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @() }
    }
    
    throw "Python executable not found. Set felix/config.json -> python.executable (and optional python.args) or install Python."
}

function Invoke-RequirementValidation {
    <#
    .SYNOPSIS
    Runs scripts/validate-requirement.ps1 (PowerShell validation script)
    #>
    param(
        [string]$ValidationScript,
        [string]$RequirementId
    )
    
    Write-Host "[VALIDATION] Script: $ValidationScript"
    Write-Host "[VALIDATION] Requirement: $RequirementId"
    
    # Call PowerShell validation script directly
    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    
    try {
        # Execute the PowerShell validation script
        $output = & $ValidationScript $RequirementId 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
    }
    catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $prevErrorAction
    }
    
    return @{ output = $output; exitCode = $exitCode }
}

function Get-BackpressureCommands {
    <#
    .SYNOPSIS
    Parses test/build/lint commands from AGENTS.md
    
    .DESCRIPTION
    Looks for these sections in AGENTS.md:
    - "## Run Tests" - test commands
    - "## Build the Project" - build commands
    - "## Lint" - lint commands
    
    Commands are extracted from bash/sh code blocks within these sections.
    
    .PARAMETER AgentsFilePath
    Path to the AGENTS.md file
    
    .PARAMETER ConfigCommands
    Optional array of commands from config.json backpressure.commands
    If provided and non-empty, these take precedence over parsing AGENTS.md
    
    .OUTPUTS
    Array of hashtables with keys: command, type, description
    #>
    param(
        [string]$AgentsFilePath,
        [array]$ConfigCommands = @()
    )
    
    $commands = @()
    
    # If config commands are explicitly provided, use those
    if ($ConfigCommands -and $ConfigCommands.Count -gt 0) {
        Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
        Write-Host "Using commands from config.json"
        foreach ($cmd in $ConfigCommands) {
            $commands += @{
                command     = $cmd
                type        = "config"
                description = "Command from config.json"
            }
        }
        return $commands
    }
    
    # Parse commands from AGENTS.md
    if (-not (Test-Path $AgentsFilePath)) {
        Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
        Write-Host "Warning: AGENTS.md not found at $AgentsFilePath" -ForegroundColor Yellow
        return $commands
    }
    
    Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
    Write-Host "Parsing commands from AGENTS.md"
    $content = Get-Content $AgentsFilePath -Raw
    
    # Define sections to parse and their types
    $sectionPatterns = @(
        @{ pattern = '##\s*Run\s+Tests'; type = 'test'; name = 'Run Tests' }
        @{ pattern = '##\s*Build(\s+the\s+Project)?'; type = 'build'; name = 'Build' }
        @{ pattern = '##\s*Lint'; type = 'lint'; name = 'Lint' }
    )
    
    foreach ($section in $sectionPatterns) {
        # Find section start
        $sectionMatch = [regex]::Match($content, $section.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        if ($sectionMatch.Success) {
            # Get content from section start to next ## header or end of file
            $sectionStart = $sectionMatch.Index + $sectionMatch.Length
            $nextSectionMatch = [regex]::Match($content.Substring($sectionStart), '^##\s', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            
            if ($nextSectionMatch.Success) {
                $sectionContent = $content.Substring($sectionStart, $nextSectionMatch.Index)
            }
            else {
                $sectionContent = $content.Substring($sectionStart)
            }
            
            # Extract code blocks (```bash, ```sh, or ```)
            $codeBlockPattern = '```(?:bash|sh|powershell|pwsh)?\s*\r?\n([\s\S]*?)```'
            $codeBlocks = [regex]::Matches($sectionContent, $codeBlockPattern)
            
            foreach ($block in $codeBlocks) {
                $blockContent = $block.Groups[1].Value
                
                # Parse individual commands from the code block
                $lines = $blockContent -split '\r?\n'
                
                foreach ($line in $lines) {
                    $trimmedLine = $line.Trim()
                    
                    # Skip empty lines, comments, and placeholder lines
                    if (-not $trimmedLine -or 
                        $trimmedLine.StartsWith('#') -or 
                        $trimmedLine -match '^TODO:' -or
                        $trimmedLine -match '^\s*#') {
                        continue
                    }
                    
                    # Skip lines that are clearly not commands (e.g., "Runs on http://...")
                    if ($trimmedLine -match '^(Runs\s+on|API\s+docs|Example)') {
                        continue
                    }
                    
                    # Add the command
                    $commands += @{
                        command     = $trimmedLine
                        type        = $section.type
                        description = "$($section.name): $trimmedLine"
                    }
                }
            }
        }
    }
    
    Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
    Write-Host "Found $($commands.Count) commands from AGENTS.md"
    foreach ($cmd in $commands) {
        Write-Host "  [$($cmd.type)] $($cmd.command)"
    }
    
    return $commands
}

function Invoke-BackpressureValidation {
    <#
    .SYNOPSIS
    Executes backpressure validation commands (tests, build, lint) after code changes
    
    .DESCRIPTION
    Runs all backpressure commands parsed from AGENTS.md or config.json.
    Returns a result object indicating success/failure and details.
    
    .PARAMETER WorkingDir
    The project working directory
    
    .PARAMETER AgentsFilePath
    Path to the AGENTS.md file
    
    .PARAMETER Config
    The felix config object (for backpressure settings)
    
    .PARAMETER RunDir
    Directory to write validation logs to
    
    .OUTPUTS
    Hashtable with keys: success (bool), failed_commands (array), output (string)
    #>
    param(
        [string]$WorkingDir,
        [string]$AgentsFilePath,
        [object]$Config,
        [string]$RunDir
    )
    
    $result = @{
        success         = $true
        failed_commands = @()
        output          = ""
        skipped         = $false
    }
    
    # Check if backpressure is enabled
    if (-not $Config.backpressure.enabled) {
        Write-Host "[BACKPRESSURE] Backpressure validation is disabled in config"
        $result.skipped = $true
        return $result
    }
    
    # Get backpressure commands
    $configCommands = @()
    if ($Config.backpressure.commands) {
        $configCommands = @($Config.backpressure.commands)
    }
    
    $commands = Get-BackpressureCommands -AgentsFilePath $AgentsFilePath -ConfigCommands $configCommands
    
    if ($commands.Count -eq 0) {
        Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
        Write-Host "No validation commands found - skipping backpressure" -ForegroundColor Yellow
        $result.skipped = $true
        return $result
    }
    
    Write-Host ""
    Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
    Write-Host "Running validation commands..."
    Write-Host ""
    
    $allOutput = @()
    
    Push-Location $WorkingDir
    try {
        foreach ($cmd in $commands) {
            Write-Host "  [$($cmd.type)] Executing: $($cmd.command)"
            
            try {
                # Execute the command
                $prevErrorAction = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                $cmdOutput = Invoke-Expression $cmd.command 2>&1
                $exitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevErrorAction
                
                # Convert output to string
                $outputStr = ($cmdOutput | Out-String).Trim()
                $isNoisyTool = $cmd.command -match '\b(npm|vite|pnpm|yarn)\b'
                $hasRemoteException = $outputStr -match 'RemoteException'
                $allOutput += "=== $($cmd.type): $($cmd.command) ==="
                $allOutput += $outputStr
                $allOutput += "Exit code: $exitCode"
                if ($hasRemoteException -and $exitCode -eq 0) {
                    $allOutput += "Warning: stderr output detected (non-fatal)"
                }
                $allOutput += ""
                
                # Exit code 5 for backend tests means "no tests found" - treat as success
                $isBackendTest = $cmd.command -match 'test-backend'
                $isNoTestsFound = $exitCode -eq 5
                
                if ($exitCode -ne 0 -and -not ($isBackendTest -and $isNoTestsFound)) {
                    Write-Host "    ❌ FAILED (exit code: $exitCode)" -ForegroundColor Red
                    $result.success = $false
                    $result.failed_commands += @{
                        command   = $cmd.command
                        type      = $cmd.type
                        exit_code = $exitCode
                        output    = $outputStr
                    }
                }
                else {
                    if ($isBackendTest -and $isNoTestsFound) {
                        Write-Host "    ⚠️  PASSED (no tests found)" -ForegroundColor Yellow
                    }
                    elseif ($hasRemoteException -and $isNoisyTool) {
                        Write-Host "    ⚠️  PASSED (stderr output ignored)" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "    ✅ PASSED" -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host "    ❌ ERROR: $_" -ForegroundColor Red
                $result.success = $false
                $result.failed_commands += @{
                    command   = $cmd.command
                    type      = $cmd.type
                    exit_code = -1
                    output    = $_.ToString()
                }
                $allOutput += "=== $($cmd.type): $($cmd.command) ==="
                $allOutput += "ERROR: $_"
                $allOutput += ""
            }
        }
    }
    finally {
        Pop-Location
    }
    
    $result.output = $allOutput -join "`n"
    
    # Write validation log to run directory
    if ($RunDir -and (Test-Path $RunDir)) {
        $logPath = Join-Path $RunDir "backpressure.log"
        Set-Content $logPath $result.output -Encoding UTF8
        Write-Host ""
        Write-Host "[BACKPRESSURE] Validation log written to: $logPath"
    }
    
    # Summary
    Write-Host ""
    if ($result.success) {
        Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
        Write-Host "✅ All validation commands passed!" -ForegroundColor Green
    }
    else {
        Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
        Write-Host "❌ Validation FAILED - $($result.failed_commands.Count) command(s) failed" -ForegroundColor Red
        foreach ($failed in $result.failed_commands) {
            Write-Host "  - [$($failed.type)] $($failed.command)"
        }
    }
    
    return $result
}

# Key paths
$SpecsDir = Join-Path $ProjectPath "specs"
$FelixDir = Join-Path $ProjectPath "felix"
$RunsDir = Join-Path $ProjectPath "runs"
$AgentsFile = Join-Path $ProjectPath "AGENTS.md"
$ConfigFile = Join-Path $FelixDir "config.json"
$StateFile = Join-Path $FelixDir "state.json"
$RequirementsFile = Join-Path $FelixDir "requirements.json"
$PromptsDir = Join-Path $FelixDir "prompts"

Write-Host "[DEBUG] StateFile: $StateFile" -ForegroundColor DarkGray
Write-Host "[DEBUG] RequirementsFile: $RequirementsFile" -ForegroundColor DarkGray

# Validate project structure
$requiredPaths = @($SpecsDir, $FelixDir, $ConfigFile, $RequirementsFile)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Write-Host "ERROR: " -NoNewline -ForegroundColor Red
        Write-Host "Required path not found: $path" -ForegroundColor Red
        Write-Host "This doesn't appear to be a valid Felix project." -ForegroundColor Yellow
        exit 1
    }
}

# Load config
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$maxIterations = $config.executor.max_iterations
$defaultMode = $config.executor.default_mode

# Clear any cached plugin state from previous runs
$script:PluginCache = $null
$script:PluginCircuitBreaker = @{}
$script:PluginPermissions = $null

# Load agent configuration from global ~/.felix/agents.json via agent_id
$FelixHome = if ($env:FELIX_HOME) { $env:FELIX_HOME } else { Join-Path $env:USERPROFILE ".felix" }
$AgentsJsonFile = Join-Path $FelixHome "agents.json"

# Create default agents.json if it doesn't exist
if (-not (Test-Path $AgentsJsonFile)) {
    Write-Host "[CONFIG] " -NoNewline -ForegroundColor Cyan
    Write-Host "Creating default agents.json at: $AgentsJsonFile" -ForegroundColor Yellow
    
    $defaultAgentsConfig = @{
        agents = @(
            @{
                id                = 0
                name              = "felix-primary"
                executable        = "droid"
                args              = @("exec", "--skip-permissions-unsafe")
                working_directory = "."
                environment       = @{}
            }
        )
    }
    
    New-Item -Path (Split-Path $AgentsJsonFile -Parent) -ItemType Directory -Force | Out-Null
    $defaultAgentsConfig | ConvertTo-Json -Depth 10 | Set-Content $AgentsJsonFile
}

$agentsData = Get-Content $AgentsJsonFile -Raw | ConvertFrom-Json
$agentId = if ($config.agent -and $null -ne $config.agent.agent_id) { 
    $config.agent.agent_id 
}
else { 
    0  # Default to agent ID 0
}

# Find agent by ID
$agentConfig = $agentsData.agents | Where-Object { $_.id -eq $agentId }

if (-not $agentConfig) {
    Write-Host "WARNING: " -NoNewline -ForegroundColor Yellow
    Write-Host "Agent ID $agentId not found in agents.json. Falling back to system default (ID 0)." -ForegroundColor Yellow
    $agentConfig = $agentsData.agents | Where-Object { $_.id -eq 0 }
    
    if (-not $agentConfig) {
        Write-Host "ERROR: " -NoNewline -ForegroundColor Red
        Write-Host "System default agent (ID 0) not found in agents.json" -ForegroundColor Red
        exit 1
    }
    
    # Auto-correct config.json to reference agent ID 0
    $config.agent.agent_id = 0
    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
    Write-Host "[CONFIG] " -NoNewline -ForegroundColor Cyan
    Write-Host "Auto-corrected config.json to reference agent ID 0" -ForegroundColor Green
}

$agentName = $agentConfig.name
$script:agentName = $agentName
$script:agentId = $agentConfig.id
$script:agentConfig = $agentConfig

Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
Write-Host "Using agent: $agentName (ID: $($agentConfig.id))" -ForegroundColor White
Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
Write-Host "Executable: $($agentConfig.executable) $($agentConfig.args -join ' ')" -ForegroundColor Gray

# ============================================================================
# Agent Registration and Heartbeat Functions
# ============================================================================

$script:BackendBaseUrl = "http://localhost:8080"
$script:HeartbeatJob = $null

function Register-Agent {
    <#
    .SYNOPSIS
    Registers the agent with the backend API
    #>
    param(
        [int]$AgentId,
        [string]$AgentName,
        [int]$ProcessId,
        [string]$Hostname
    )
    
    $registration = @{
        agent_id   = $AgentId
        agent_name = $AgentName
        pid        = $ProcessId
        hostname   = $Hostname
        started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    
    try {
        $body = $registration | ConvertTo-Json
        $response = Invoke-RestMethod -Method POST `
            -Uri "$script:BackendBaseUrl/api/agents/register" `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
        Write-Host "Registered as agent ID $AgentId ('$AgentName', PID: $ProcessId)" -ForegroundColor Green
        return $true
    }
    catch {
        # Registration is best-effort - don't fail if backend is unreachable
        Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
        Write-Host "Registration failed (backend may be unavailable): $_" -ForegroundColor Yellow
        return $false
    }
}

function Send-AgentHeartbeat {
    <#
    .SYNOPSIS
    Sends a heartbeat to the backend API
    #>
    param(
        [int]$AgentId,
        [string]$CurrentRequirementId
    )
    
    $heartbeat = @{
        current_run_id = $CurrentRequirementId
    }
    
    try {
        $body = $heartbeat | ConvertTo-Json
        Invoke-RestMethod -Method POST `
            -Uri "$script:BackendBaseUrl/api/agents/$AgentId/heartbeat" `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        # Heartbeat failures are non-fatal
        return $false
    }
}

function Start-HeartbeatJob {
    <#
    .SYNOPSIS
    Starts a background job that sends heartbeats every 5 seconds
    #>
    param(
        [int]$AgentId,
        [string]$BaseUrl
    )
    
    # Stop any existing heartbeat job
    if ($script:HeartbeatJob) {
        Stop-HeartbeatJob
    }
    
    $script:HeartbeatJob = Start-Job -Name "FelixHeartbeat" -ScriptBlock {
        param($AgentId, $BaseUrl)
        
        while ($true) {
            Start-Sleep -Seconds 5
            
            try {
                # Read current requirement from state file if available
                $stateFile = "felix/state.json"
                $currentReqId = $null
                if (Test-Path $stateFile) {
                    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
                    $currentReqId = $state.current_requirement_id
                }
                
                $heartbeat = @{
                    current_run_id = $currentReqId
                } | ConvertTo-Json
                
                Invoke-RestMethod -Method POST `
                    -Uri "$BaseUrl/api/agents/$AgentId/heartbeat" `
                    -Body $heartbeat `
                    -ContentType "application/json" `
                    -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                # Silently continue on heartbeat failures
            }
        }
    } -ArgumentList $AgentId, $BaseUrl
    
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Started heartbeat job (every 5s)" -ForegroundColor Green
}

function Stop-HeartbeatJob {
    <#
    .SYNOPSIS
    Stops the background heartbeat job
    #>
    if ($script:HeartbeatJob) {
        Stop-Job -Job $script:HeartbeatJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:HeartbeatJob -Force -ErrorAction SilentlyContinue
        $script:HeartbeatJob = $null
    }
}

function Unregister-Agent {
    <#
    .SYNOPSIS
    Marks the agent as stopped in the registry
    #>
    param(
        [int]$AgentId
    )
    
    try {
        Invoke-RestMethod -Method POST `
            -Uri "$script:BackendBaseUrl/api/agents/$AgentId/stop" `
            -ContentType "application/json" `
            -ErrorAction Stop | Out-Null
        
        Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
        Write-Host "Agent ID $AgentId marked as stopped" -ForegroundColor Yellow
    }
    catch {
        # Best-effort - don't fail on unregister errors
    }
}

function Exit-FelixAgent {
    <#
    .SYNOPSIS
    Cleanly exit the agent with proper cleanup
    #>
    param(
        [int]$ExitCode = 0
    )
    
    # Stop heartbeat job
    Stop-HeartbeatJob
    
    # Unregister agent if we have an agent ID
    if ($script:agentId) {
        Unregister-Agent -AgentId $script:agentId
    }
    
    exit $ExitCode
}

# Store agent name and ID in script scope for cleanup function
$script:agentName = $null
$script:agentId = $null

# Resolve python upfront (hard stop if unavailable)
try {
    $null = Resolve-PythonCommand -Config $config
}
catch {
    Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
    Write-Host "❌ Python resolution failed: $_" -ForegroundColor Red
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════
# Plugin System Infrastructure
# ═══════════════════════════════════════════════════════════════════════════

# Global plugin state
$script:PluginCache = @{}
$script:PluginCircuitBreaker = @{}

# Permission constants
$script:PluginPermissions = @{
    "read:specs"       = @{ Description = "Read spec files from specs/" }
    "read:state"       = @{ Description = "Read felix/state.json and felix/requirements.json" }
    "read:runs"        = @{ Description = "Read run artifacts from runs/" }
    "write:runs"       = @{ Description = "Write to run artifacts in runs/" }
    "write:logs"       = @{ Description = "Write to log files" }
    "execute:commands" = @{ Description = "Execute external commands" }
    "network:http"     = @{ Description = "Make HTTP requests" }
    "git:read"         = @{ Description = "Read git state" }
    "git:write"        = @{ Description = "Execute git commands" }
}

function Initialize-PluginSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    # Check if plugins are enabled
    if (-not $Config.plugins -or -not $Config.plugins.enabled) {
        Write-Verbose "Plugin system disabled"
        $script:PluginCache = @{
            Enabled = $false
            Plugins = @()
        }
        return $script:PluginCache
    }
    
    $pluginDir = $Config.plugins.discovery_path
    if (-not $pluginDir) {
        $pluginDir = Join-Path $PSScriptRoot "felix/plugins"
    }
    
    if (-not (Test-Path $pluginDir)) {
        Write-Verbose "Plugin directory not found: $pluginDir"
        return @{
            Enabled = $true
            Plugins = @()
        }
    }
    
    # Discover plugins
    $disabledPlugins = if ($Config.plugins.disabled) { $Config.plugins.disabled } else { @() }
    
    Write-Host "[PLUGINS] Disabled plugins: $($disabledPlugins -join ', ')" -ForegroundColor DarkGray
    
    $plugins = Get-ChildItem $pluginDir -Directory | ForEach-Object {
        $pluginName = $_.Name
        $manifestPath = Join-Path $_.FullName "plugin.json"
        
        if (-not (Test-Path $manifestPath)) {
            Write-Verbose "Skipping plugin ${pluginName}: No manifest found"
            return $null
        }
        
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            # Check if plugin is disabled
            if ($disabledPlugins -contains $manifest.id -or $disabledPlugins -contains $pluginName) {
                Write-Verbose "Skipping plugin ${pluginName}: Disabled in config"
                return $null
            }
            
            # Basic validation
            if (-not $manifest.id -or -not $manifest.hooks) {
                Write-Warning "Invalid plugin manifest for $pluginName"
                return $null
            }
            
            $plugin = @{
                Id          = $manifest.id
                Name        = $manifest.name
                Path        = $_.FullName
                Hooks       = $manifest.hooks
                Permissions = if ($manifest.permissions) { $manifest.permissions } else { @() }
                Config      = if ($manifest.config) { $manifest.config } else { @{} }
            }
            
            Write-Verbose "Found plugin: $($plugin.Name) ($($plugin.Id))"
            return [PSCustomObject]$plugin
        }
        catch {
            Write-Warning "Failed to load plugin manifest for ${pluginName}: $_"
            return $null
        }
    } | Where-Object { $null -ne $_ }
    
    $script:PluginCache = @{
        Enabled = $true
        Plugins = $plugins
    }
    
    Write-Host "[PLUGINS] Initialized plugin system ($($plugins.Count) plugins active)" -ForegroundColor Green
    return $script:PluginCache
}

function Invoke-PluginHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HookName,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$HookData = @{}
    )
    
    if (-not $script:PluginCache -or -not $script:PluginCache.Enabled) {
        return @{ ShouldContinue = $true }
    }
    
    $combinedResult = @{
        ShouldContinue = $true
        Reason         = ""
    }
    
    foreach ($plugin in $script:PluginCache.Plugins) {
        # Check if plugin implements this hook
        $hook = $plugin.Hooks | Where-Object { $_.name -eq $HookName }
        if (-not $hook) { continue }
        
        # Check circuit breaker
        $pluginId = $plugin.Id
        if ($script:PluginCircuitBreaker[$pluginId] -ge 3) {
            Write-Verbose "Plugin $pluginId is disabled due to repeated failures"
            continue
        }
        
        try {
            # Implementation depends on hook type (script or binary)
            $result = $null
            if ($hook.type -eq "powershell") {
                $hookScript = Join-Path $plugin.Path $hook.script
                if (Test-Path $hookScript) {
                    $result = & $hookScript -HookName $HookName -RunId $RunId -Data $HookData -Config $plugin.Config
                }
            }
            
            # Process result
            if ($result) {
                if ($result.PSObject.Properties['ShouldContinue'] -and $result.ShouldContinue -eq $false) {
                    $combinedResult.ShouldContinue = $false
                    $combinedResult.Reason = $result.Reason
                }
                
                # Merge other properties into combined result
                foreach ($prop in $result.PSObject.Properties) {
                    if ($prop.Name -ne "ShouldContinue" -and $prop.Name -ne "Reason") {
                        $combinedResult[$prop.Name] = $prop.Value
                    }
                }
            }
            
            # Reset circuit breaker on success
            $script:PluginCircuitBreaker[$pluginId] = 0
        }
        catch {
            Write-Warning "Plugin $($plugin.Name) failed on hook ${HookName}: $_"
            $currentCount = if ($script:PluginCircuitBreaker[$pluginId]) { $script:PluginCircuitBreaker[$pluginId] } else { 0 }
            $script:PluginCircuitBreaker[$pluginId] = $currentCount + 1
        }
    }
    
    return [PSCustomObject]$combinedResult
}

function Invoke-PluginHookSafely {
    param(
        [string]$HookName,
        [string]$RunId,
        [hashtable]$HookData
    )
    
    try {
        return Invoke-PluginHook -HookName $HookName -RunId $RunId -HookData $HookData
    }
    catch {
        Write-Host "[PLUGINS] $HookName hook failed: $_" -ForegroundColor Yellow
        return @{ ShouldContinue = $true }
    }
}

# ============================================================================
# Main Execution Logic
# ============================================================================

# Load requirements
if (-not (Test-Path $RequirementsFile)) {
    Write-Host "ERROR: Requirements file not found: $RequirementsFile" -ForegroundColor Red
    exit 1
}

Write-Host "[DEBUG] Loading requirements from: $RequirementsFile" -ForegroundColor DarkGray
$requirements = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
Write-Host "[DEBUG] Total requirements loaded: $($requirements.requirements.Count)" -ForegroundColor DarkGray
$currentReq = $null

if ($RequirementId) {
    $currentReq = $requirements.requirements | Where-Object { $_.id -eq $RequirementId }
    if (-not $currentReq) {
        Write-Host "ERROR: Requirement $RequirementId not found." -ForegroundColor Red
        exit 1
    }
    
    # Debug: Show requirement details
    Write-Host "[DEBUG] Found requirement: $($currentReq.id) - $($currentReq.title)" -ForegroundColor DarkGray
    Write-Host "[DEBUG] Status: $($currentReq.status)" -ForegroundColor DarkGray
    
    # Check if requirement is already complete
    if ($currentReq.status -in @("complete", "done")) {
        Write-Host "Requirement $RequirementId is already $($currentReq.status) - nothing to do." -ForegroundColor Green
        
        # Clean up stale state if needed
        if (Test-Path $StateFile) {
            $state = Get-Content $StateFile -Raw | ConvertFrom-Json
            if ($state.current_requirement_id -eq $RequirementId) {
                Write-Host "[STATE] Clearing stale state for completed requirement $RequirementId" -ForegroundColor Cyan
                $state.current_requirement_id = $null
                $state.status = "ready"
                $state.last_iteration_outcome = "already_complete"
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json | Set-Content $StateFile
            }
        }
        exit 0
    }
}
else {
    # Find first planned or in_progress requirement
    $currentReq = $requirements.requirements | Where-Object { $_.status -eq "planned" -or $_.status -eq "in_progress" } | Select-Object -First 1
    if (-not $currentReq) {
        Write-Host "No planned or in-progress requirements found." -ForegroundColor Green
        exit 0
    }
}

$RequirementId = $currentReq.id

# Load or initialize state
$state = if (Test-Path $StateFile) {
    Get-Content $StateFile -Raw | ConvertFrom-Json
}
else {
    @{
        current_requirement_id = $null
        current_iteration      = 0
        last_mode              = $null
        status                 = "idle"
        validation_retry_count = 0
    }
}

# Initialize validation retry counter if it doesn't exist
if ($null -eq $state.validation_retry_count) {
    $state | Add-Member -MemberType NoteProperty -Name validation_retry_count -Value 0 -Force
}

# Reset validation retry counter if we're starting a new requirement
if ($state.current_requirement_id -ne $currentReq.id) {
    $state.validation_retry_count = 0
    $state.current_requirement_id = $currentReq.id
    $state.current_iteration = 0
    $state.status = "ready"
    $state.last_iteration_outcome = $null
    $state.blocked_task = $null
    Write-Host "[STATE] Starting new requirement, reset all state counters" -ForegroundColor Cyan
}

# ============================================================================
# Agent Registration at Startup
# ============================================================================

# Register with the backend (best-effort)
$registrationSucceeded = Register-Agent -AgentId $agentConfig.id -AgentName $agentName -ProcessId $PID -Hostname $env:COMPUTERNAME

# Start heartbeat background job if registration succeeded
if ($registrationSucceeded) {
    Start-HeartbeatJob -AgentId $agentConfig.id -BaseUrl $script:BackendBaseUrl
}

# Cleanup is handled by Exit-FelixAgent function which stops heartbeat and unregisters agent
# The agent will be marked inactive automatically after heartbeat timeout if abruptly terminated

# Main iteration loop
for ($iteration = 1; $iteration -le $maxIterations; $iteration++) {
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host " Felix Agent - Iteration $iteration/$maxIterations" -ForegroundColor Cyan
    
    # --- FIX START: Generate Run ID and Setup Dir immediately ---
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runId = "$($currentReq.id)-$timestamp-it$iteration"
    
    $runDir = Join-Path $RunsDir $runId
    if (-not (Test-Path $runDir)) {
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    }
    
    # Initialize the plugin system for this run
    Write-Host "[DEBUG] Initializing plugin system with runId: $runId" -ForegroundColor DarkGray
    Initialize-PluginSystem -Config $config -RunId $runId
    # --- FIX END ---

    # Determine mode
    $mode = "building" # Default 
    
    # Look for most recent plan for current requirement in runs/
    $planPattern = "plan-$($currentReq.id).md"
    $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($existingPlans -and $existingPlans.Count -gt 0) {
        # Found plan in runs/ - use building mode
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        $mode = "building"
        Write-Host "[MODE] Found existing plan, using BUILDING mode" -ForegroundColor Yellow
    }
    else {
        # No plan found - use planning mode (or default)
        $mode = if ($state.last_mode) { $state.last_mode } else { $defaultMode }
        if ($mode -eq "building" -and -not $existingPlans) {
            Write-Host "[MODE] No plan found, falling back to PLANNING mode" -ForegroundColor Yellow
            $mode = "planning"
        }
        $latestPlanPath = $null
        $planContent = $null
    }

    # Hook: OnPostModeSelection
    $hookResult = Invoke-PluginHook -HookName "OnPostModeSelection" -RunId $runId -HookData @{
        Mode               = $mode
        CurrentRequirement = $currentReq
        PlanPath           = if ($latestPlanPath) { $latestPlanPath } else { "" }
    }
    
    if ($hookResult.OverrideMode) {
        Write-Host "[PLUGINS] Mode overridden: $($mode) -> $($hookResult.OverrideMode) ($($hookResult.Reason))"
        $mode = $hookResult.OverrideMode
    }

    # Update state
    $state.current_iteration = $iteration
    $state.last_mode = $mode
    $state.status = "running"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile

    # Hook: OnPreIteration
    try {
        $hookResult = Invoke-PluginHook -HookName "OnPreIteration" -RunId $runId -HookData @{
            Iteration          = $iteration
            MaxIterations      = $maxIterations
            CurrentRequirement = $currentReq
            State              = $state
        }
    }
    catch {
        Write-Host "[PLUGINS] OnPreIteration hook failed: $_" -ForegroundColor Yellow
        $hookResult = @{ ContinueIteration = $true }
    }
    
    if ($hookResult.ContinueIteration -eq $false) {
        Write-Host "[PLUGINS] Iteration skipped: $($hookResult.Reason)"
        break
    }

    # Load prompt template
    $promptFile = Join-Path $PromptsDir "$mode.md"
    if (-not (Test-Path $promptFile)) {
        Write-Host "ERROR: " -NoNewline -ForegroundColor Red
        Write-Host "Prompt template not found: $promptFile" -ForegroundColor Red
        Exit-FelixAgent -ExitCode 1
    }
    $promptTemplate = Get-Content $promptFile -Raw

    # Gather context
    $contextParts = @()
    
    # Add AGENTS.md if exists
    if (Test-Path $AgentsFile) {
        $agentsContent = Get-Content $AgentsFile -Raw
        $contextParts += "# How to Run This Project`n`n$agentsContent"
    }

    # Add Requirements context
    $reqContext = @{
        id           = $currentReq.id
        title        = $currentReq.title
        description  = $currentReq.description
        status       = $currentReq.status
        dependencies = @()
    }
    
    # Add dependency info if they exist
    if ($currentReq.depends_on -and $currentReq.depends_on.Count -gt 0) {
        $deps = @()
        foreach ($depId in $currentReq.depends_on) {
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
    $contextParts += "# Current Requirement Context`n`n``````json`n$reqSummary`n```````n`n*Note: Full requirements list available at ``felix/requirements.json`` if you need to check other requirements.*"

    # Add current requirement header
    $contextParts += "# Current Requirement`n`nYou are working on: **$($currentReq.id)** - $($currentReq.title)"

    # Add failure context from previous iteration if blocked
    if ($state.blocked_task) {
        $failedCommandsList = ($state.blocked_task.failed_commands | ForEach-Object { "- $_" }) -join "`n"
        $retryInfo = "# ⚠️ Previous Iteration - Task Blocked ⚠️`n`n"
        $retryInfo += "**IMPORTANT:** The following task failed validation in the previous iteration. You MUST fix these issues before proceeding.`n`n"
        $retryInfo += "**Blocked Task:** $($state.blocked_task.description)`n"
        $retryInfo += "**Retry Attempt:** $($state.blocked_task.retry_count) of $($state.blocked_task.max_retries)`n"
        $retryInfo += "**Blocked Since:** $($state.blocked_task.blocked_at)`n"
        $retryInfo += "**Reason:** $($state.blocked_task.reason)`n`n"
        $retryInfo += "## Failed Validation Commands`n`n"
        $retryInfo += "$failedCommandsList`n`n"
        $retryInfo += "## What You Must Do`n`n"
        $retryInfo += "1. **Review the failed validation commands above** - These commands must pass before the task can be committed`n"
        $retryInfo += "2. **Fix the underlying issues** causing the test/build/lint failures. DO NOT just retry without changes.`n"
        $retryInfo += "3. **Explain your fix** in the task completion message.`n"
        
        $contextParts += $retryInfo
    }

    # Add Mode Specific Context
    if ($mode -eq "building") {
        if ($planContent) {
            $contextParts += "# Current Plan`n`n$planContent"
        }
    }

    # Target path for plan (relative to project root)
    $planRelPath = "runs/$runId/plan-$($currentReq.id).md"
    $planOutputPath = Join-Path $ProjectPath $planRelPath

    if ($mode -eq "planning") {
        $contextParts += "# Plan Output Path`n`nYou MUST generate a requirement-specific plan and save it to: **$planOutputPath**`n`nThis plan should contain ONLY tasks for requirement $($currentReq.id)."
    }
    else {
        $contextParts += "# Plan Update Path`n`nWhen marking tasks complete, update the plan at: **$planOutputPath**"
    }

    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"

    # Hook: OnContextGathering
    $gitDiff = if (Test-Path (Join-Path $ProjectPath ".git")) { git diff 2>$null } else { "" }
    $hookResult = Invoke-PluginHookSafely -HookName "OnContextGathering" -RunId $runId -HookData @{
        Mode               = $mode
        CurrentRequirement = $currentReq
        GitDiff            = $gitDiff
        PlanContent        = if ($mode -eq "building" -and $planContent) { $planContent } else { "" }
        ContextFiles       = $contextParts
    }
    
    if ($hookResult.AdditionalContext) {
        Write-Verbose "[PLUGINS] Adding additional context from plugins"
        $fullPrompt += "`n`n---`n`n# Additional Context (Plugins)`n`n$($hookResult.AdditionalContext)"
    }

    # Capture state before execution for planning mode guardrails
    $beforeState = if ($mode -eq "planning") { Get-GitState -WorkingDir $ProjectPath } else { $null }

    # Write prompt to run directory for debugging
    Set-Content (Join-Path $runDir "prompt.md") $fullPrompt -Encoding UTF8

    # Execute agent
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Executing droid in $mode mode..." -ForegroundColor White

    $executable = $agentConfig.executable
    $args = $agentConfig.args
    $startTime = Get-Date

    # Hook: OnPreExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPreExecution" -RunId $runId -HookData @{
        Executable = $executable
        Args       = [System.Collections.ArrayList]@($args)
        Prompt     = $fullPrompt
    }
    
    if ($hookResult.ModifiedArgs) {
        $args = $hookResult.ModifiedArgs
        Write-Verbose "[PLUGINS] Using modified executable arguments"
    }

    # Execute the agent and capture output
    $output = $fullPrompt | & $executable @args 2>&1 | Out-String
    $duration = (Get-Date) - $startTime

    # Write raw output to run directory
    Set-Content (Join-Path $runDir "output.txt") $output -Encoding UTF8
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Execution complete (Duration: $($duration.TotalSeconds.ToString("F1"))s)" -ForegroundColor White

    # Hook: OnPostExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostExecution" -RunId $runId -HookData @{
        Output   = $output
        Duration = $duration.TotalSeconds
    }

    # Planning Mode Guardrails
    if ($mode -eq "planning") {
        $violations = Test-PlanningModeGuardrails -WorkingDir $ProjectPath -BeforeState $beforeState -RunId $runId
        if ($violations.HasViolations) {
            Undo-PlanningViolations -WorkingDir $ProjectPath -BeforeState $beforeState -Violations $violations
            
            # Update state to reflect failure
            $state.last_iteration_outcome = "guardrail_violation"
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json | Set-Content $StateFile
            
            Write-Host "[AGENT] " -NoNewline -ForegroundColor Red
            Write-Host "Planning mode aborted due to guardrail violations." -ForegroundColor Red
            continue
        }
    }

    # Process task completion signal
    if ($output -match '\*\*Task Completed:\*\*\s*(.+)') {
        $taskDesc = $matches[1].Trim()
        Write-Host ""
        Write-Host "[TASK] " -NoNewline -ForegroundColor Green
        Write-Host "Detected completed task: $taskDesc" -ForegroundColor White
        
        # Hook: OnPreBackpressure
        $hookResult = Invoke-PluginHookSafely -HookName "OnPreBackpressure" -RunId $runId -HookData @{
            CurrentRequirement = $currentReq
            Commands           = [System.Collections.ArrayList]@()
        }
        
        if ($hookResult.SkipBackpressure) {
            Write-Host "[PLUGINS] Backpressure skipped: $($hookResult.Reason)"
            $backpressureResult = @{ skipped = $true; success = $true }
        }
        else {
            # Run backpressure validation BEFORE committing
            $backpressureResult = Invoke-BackpressureValidation `
                -WorkingDir $ProjectPath `
                -AgentsFilePath $AgentsFile `
                -Config $config `
                -RunDir $runDir
        }

        if (-not $backpressureResult.skipped -and -not $backpressureResult.success) {
            # Backpressure failed - do NOT commit, mark task as blocked
            Write-Host ""
            Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
            Write-Host "❌ Validation failed - changes will NOT be committed" -ForegroundColor Red
            Write-Host "[BACKPRESSURE] " -NoNewline -ForegroundColor Blue
            Write-Host "Task marked as BLOCKED pending validation fixes" -ForegroundColor Yellow

            # Determine retry count
            $maxRetries = if ($config.backpressure.max_retries) { $config.backpressure.max_retries } else { 3 }
            $blockedTaskDesc = $taskDesc
            $failedCmdSummary = @()
            foreach ($failed in $backpressureResult.failed_commands) {
                $failedCmdSummary += "[$($failed.type)] $($failed.command) (exit: $($failed.exit_code))"
            }

            $retryCount = 1
            if ($state.blocked_task -and $state.blocked_task.description -eq $blockedTaskDesc) {
                $retryCount = $state.blocked_task.retry_count + 1
            }

            if ($retryCount -gt $maxRetries) {
                # Max retries exceeded
                Write-Host "[BLOCKED] Maximum backpressure retries ($maxRetries) exceeded" -ForegroundColor Red
                
                $maxRetriesReport = @"
# ❌ Max Retries Exceeded ❌
**Task:** $blockedTaskDesc
**Reason:** Backpressure validation failed $maxRetries consecutive times.
## Failed Commands
$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)
## Next Steps
This task requires manual intervention.
"@
                Set-Content (Join-Path $runDir "max-retries-exceeded.md") $maxRetriesReport -Encoding UTF8
                Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "blocked"
                Exit-FelixAgent -ExitCode 2
            }

            # Update state to indicate blocked task
            $state.last_iteration_outcome = "blocked"
            $state.status = "blocked"
            $state.blocked_task = @{
                description     = $blockedTaskDesc
                blocked_at      = Get-Date -Format "o"
                reason          = "validation_failed"
                failed_commands = $failedCmdSummary
                iteration       = $iteration
                retry_count     = $retryCount
                max_retries     = $maxRetries
            }
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
            continue
        }

        # Clear blocked status on success
        $state.blocked_task = $null

        # Capture git diff after staging
        Write-Host "[ARTIFACTS] Capturing git diff to diff.patch..."
        try {
            $diffOutput = git diff --cached 2>&1
            if ($diffOutput) {
                $diffPath = Join-Path $runDir "diff.patch"
                Set-Content $diffPath $diffOutput -Encoding UTF8
                Write-Host "[ARTIFACTS] Git diff saved to: diff.patch"
            }
        }
        catch {
            Write-Host "[ARTIFACTS] Warning: Failed to capture git diff"
        }

        # Commit changes (if enabled)
        $shouldCommit = $config.executor.commit_on_complete -and -not $NoCommit
        if ($shouldCommit) {
            $commitMsg = "Felix ($($currentReq.id)): $taskDesc"
            $commitOutput = git commit -m $commitMsg 2>&1
            if ($LASTEXITCODE -eq 0) {
                $commitHash = git rev-parse --short HEAD 2>&1
                Write-Host "[COMMIT] ✅ Changes committed: $commitHash - $commitMsg"
            }
        }
        
        # After successful task completion with passing validation, check if requirement is done
        # Reload requirements to see if status was updated to complete
        $freshRequirements = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        $freshReq = $freshRequirements.requirements | Where-Object { $_.id -eq $currentReq.id } | Select-Object -First 1
        
        if ($freshReq -and $freshReq.status -in @("complete", "done")) {
            Write-Host ""
            Write-Host "[COMPLETE] Requirement $($currentReq.id) is now marked as $($freshReq.status)" -ForegroundColor Green
            Write-Host "[COMPLETE] Exiting successfully" -ForegroundColor Green
            Exit-FelixAgent -ExitCode 0
        }
    }

    # Transition to BUILDING if planning completed
    if ($mode -eq "planning" -and $output -match '<promise>PLANNING_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[PLAN READY] Planning complete, transitioning to BUILDING mode"
        $state.last_mode = "building"
    }

    # All requirements met?
    if ($output -match '<promise>ALL_REQUIREMENTS_MET</promise>') {
        # Check validation logic...
        Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "complete"
        Exit-FelixAgent -ExitCode 0
    }

    # Update state
    $state.last_iteration_outcome = "success"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile

    # Hook: OnPostIteration
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostIteration" -RunId $runId -HookData @{
        Iteration = $iteration
        Outcome   = $state.last_iteration_outcome
        State     = $state
    }

    if ($hookResult.ShouldContinue -eq $false) {
        Write-Host "[PLUGINS] Stopping iterations: $($hookResult.Reason)"
        break
    }

    Write-Host ""
    Write-Host "Iteration $iteration complete. Continuing..."
    Start-Sleep -Seconds 1
}

# If we reached here, max iterations were reached
Write-Host ""
Write-Host "[WARNING] Reached max iterations ($maxIterations)"
$state.status = "incomplete"
$state.updated_at = Get-Date -Format "o"
$state | ConvertTo-Json | Set-Content $StateFile
Exit-FelixAgent -ExitCode 0
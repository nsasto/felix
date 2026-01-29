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
    [string]$RequirementId = $null
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
# Must be done in this specific order for Windows PowerShell compatibility
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"

# Resolve project path
$ProjectPath = Resolve-Path $ProjectPath
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
    Write-Host "[BACKPRESSURE] Running validation commands..."
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
$autoTransition = $config.executor.auto_transition
$defaultMode = $config.executor.default_mode

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
$pythonInfo = $null
try {
    $pythonInfo = Resolve-PythonCommand -Config $config
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
        [hashtable]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    # Check if plugins are enabled
    if (-not $Config.plugins -or -not $Config.plugins.enabled) {
        Write-Verbose "Plugin system disabled"
        return @{
            Enabled = $false
            Plugins = @()
        }
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
    $plugins = @()
    $disabledPlugins = if ($Config.plugins.disabled) { $Config.plugins.disabled } else { @() }
    
    Get-ChildItem $pluginDir -Directory | ForEach-Object {
        $pluginName = $_.Name
        $manifestPath = Join-Path $_.FullName "plugin.json"
        
        if (-not (Test-Path $manifestPath)) {
            Write-Warning "Plugin $pluginName missing plugin.json manifest"
            return
        }
        
        # Skip disabled plugins
        if ($disabledPlugins -contains $pluginName) {
            Write-Verbose "Plugin $pluginName is disabled"
            return
        }
        
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            # Validate API version compatibility
            $apiVersion = if ($Config.plugins.api_version) { $Config.plugins.api_version } else { "v1" }
            if ($manifest.api_version -ne $apiVersion) {
                Write-Warning "Plugin $pluginName uses API version $($manifest.api_version), expected $apiVersion"
                return
            }
            
            # Validate Felix version compatibility
            if ($manifest.felix_version_min) {
                # Version comparison would go here - simplified for now
                Write-Verbose "Plugin $pluginName requires Felix >= $($manifest.felix_version_min)"
            }
            
            # Check for circular dependencies (simple check)
            if ($manifest.requires) {
                foreach ($dep in $manifest.requires) {
                    if ($dep -eq $pluginName) {
                        Write-Warning "Plugin $pluginName has circular dependency on itself"
                        return
                    }
                }
            }
            
            # Check circuit breaker state
            if ($script:PluginCircuitBreaker[$pluginName]) {
                $cbState = $script:PluginCircuitBreaker[$pluginName]
                if ($cbState.Disabled) {
                    Write-Warning "Plugin $pluginName disabled by circuit breaker (failures: $($cbState.FailureCount))"
                    return
                }
            }
            
            $plugins += @{
                Name        = $pluginName
                Manifest    = $manifest
                Path        = $_.FullName
                Priority    = if ($manifest.priority) { $manifest.priority } else { 100 }
                Permissions = if ($manifest.permissions) { $manifest.permissions } else { @() }
                Hooks       = if ($manifest.hooks) { $manifest.hooks } else { @() }
                Requires    = if ($manifest.requires) { $manifest.requires } else { @() }
            }
        }
        catch {
            Write-Warning "Failed to load plugin $pluginName: $_"
        }
    }
    
    # Topological sort for dependency resolution
    $sorted = @()
    $visited = @{}
    $visiting = @{}
    
    function Visit-Plugin {
        param([hashtable]$Plugin)
        
        if ($visited[$Plugin.Name]) { return }
        if ($visiting[$Plugin.Name]) {
            Write-Warning "Circular dependency detected: $($Plugin.Name)"
            return
        }
        
        $visiting[$Plugin.Name] = $true
        
        foreach ($depName in $Plugin.Requires) {
            $dep = $plugins | Where-Object { $_.Name -eq $depName } | Select-Object -First 1
            if ($dep) {
                Visit-Plugin -Plugin $dep
            }
            else {
                Write-Warning "Plugin $($Plugin.Name) requires missing plugin: $depName"
            }
        }
        
        $visiting[$Plugin.Name] = $false
        $visited[$Plugin.Name] = $true
        $script:sorted += $Plugin
    }
    
    foreach ($plugin in $plugins) {
        Visit-Plugin -Plugin $plugin
    }
    
    # Sort by priority within dependency order
    $sorted = $sorted | Sort-Object Priority
    
    # Cache plugins
    $script:PluginCache = @{
        Enabled    = $true
        Plugins    = $sorted
        RunId      = $RunId
        ApiVersion = if ($Config.plugins.api_version) { $Config.plugins.api_version } else { "v1" }
        Config     = $Config.plugins
    }
    
    Write-Host "[PLUGINS] Loaded $($sorted.Count) plugins"
    
    return $script:PluginCache
}

function Invoke-PluginHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HookName,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$HookData = @{},
        
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    if (-not $script:PluginCache.Enabled) {
        return $HookData
    }
    
    $apiVersion = $script:PluginCache.ApiVersion
    $applicablePlugins = $script:PluginCache.Plugins | Where-Object {
        $_.Hooks -contains $HookName
    }
    
    if ($applicablePlugins.Count -eq 0) {
        return $HookData
    }
    
    Write-Verbose "[PLUGINS] Executing hook: $HookName ($($applicablePlugins.Count) plugins)"
    
    $chainData = $HookData
    $executionLog = @()
    
    foreach ($plugin in $applicablePlugins) {
        try {
            # Check permissions
            $hasAllPermissions = $true
            foreach ($perm in $plugin.Permissions) {
                if (-not $script:PluginPermissions[$perm]) {
                    Write-Warning "Plugin $($plugin.Name) requests unknown permission: $perm"
                    $hasAllPermissions = $false
                }
            }
            
            if (-not $hasAllPermissions) {
                Write-Warning "Plugin $($plugin.Name) has invalid permissions, skipping"
                continue
            }
            
            # Determine hook script name based on API version
            $hookScript = if ($apiVersion -eq "v2") {
                Join-Path $plugin.Path "hooks/$HookName.ps1"
            }
            else {
                Join-Path $plugin.Path "on-$($HookName.ToLower()).ps1"
            }
            
            if (-not (Test-Path $hookScript)) {
                Write-Verbose "Plugin $($plugin.Name) hook script not found: $hookScript"
                continue
            }
            
            $startTime = Get-Date
            
            # Execute hook with chained data
            $result = & $hookScript -HookData $chainData -RunId $RunId -PluginConfig $plugin.Manifest
            
            $duration = (Get-Date) - $startTime
            
            # Update chain data with result (if hook returns data)
            if ($null -ne $result -and $result -is [hashtable]) {
                $chainData = $result
            }
            
            # Log successful execution
            $executionLog += @{
                Plugin   = $plugin.Name
                Hook     = $HookName
                Duration = $duration.TotalMilliseconds
                Success  = $true
            }
            
            # Reset circuit breaker on success
            if ($script:PluginCircuitBreaker[$plugin.Name]) {
                $script:PluginCircuitBreaker[$plugin.Name].FailureCount = 0
            }
        }
        catch {
            Write-Warning "Plugin $($plugin.Name) hook $HookName failed: $_"
            
            # Update circuit breaker
            if (-not $script:PluginCircuitBreaker[$plugin.Name]) {
                $script:PluginCircuitBreaker[$plugin.Name] = @{
                    FailureCount = 0
                    Disabled     = $false
                }
            }
            
            $cbState = $script:PluginCircuitBreaker[$plugin.Name]
            $cbState.FailureCount++
            
            $maxFailures = if ($script:PluginCache.Config.circuit_breaker_max_failures) {
                $script:PluginCache.Config.circuit_breaker_max_failures
            }
            else { 3 }
            
            if ($cbState.FailureCount -ge $maxFailures) {
                $cbState.Disabled = $true
                Write-Warning "Plugin $($plugin.Name) disabled by circuit breaker after $($cbState.FailureCount) failures"
            }
            
            $executionLog += @{
                Plugin  = $plugin.Name
                Hook    = $HookName
                Success = $false
                Error   = $_.ToString()
            }
        }
    }
    
    # Save execution log for debugging
    $logDir = Join-Path $RunsDir $RunId
    if (Test-Path $logDir) {
        $chainLogPath = Join-Path $logDir "plugin-chain-debug.json"
        $existingLog = if (Test-Path $chainLogPath) {
            Get-Content $chainLogPath -Raw | ConvertFrom-Json
        }
        else { @() }
        
        $existingLog += @{
            Hook      = $HookName
            Timestamp = Get-Date -Format "o"
            Plugins   = $executionLog
        }
        
        $existingLog | ConvertTo-Json -Depth 10 | Set-Content $chainLogPath
    }
    
    return $chainData
}

# ═══════════════════════════════════════════════════════════════════════════
# End Plugin System Infrastructure
# ═══════════════════════════════════════════════════════════════════════════

# Initialize plugin system after config loading
$pluginSystem = Initialize-PluginSystem -Config $config -RunId "init"
if ($pluginSystem.Enabled) {
    Write-Host "[PLUGINS] Plugin system initialized - $($pluginSystem.Plugins.Count) plugins loaded"
    foreach ($plugin in $pluginSystem.Plugins) {
        Write-Verbose "  - $($plugin.Name) v$($plugin.Manifest.version) (priority: $($plugin.Priority))"
    }
}

Write-Host "Max iterations: $maxIterations"
Write-Host ""

# Load requirements
$requirements = Get-Content $RequirementsFile -Raw | ConvertFrom-Json

# Select requirement (specific ID if provided, otherwise first available)
if ($RequirementId) {
    # Find specific requirement
    $currentReq = $requirements.requirements | Where-Object { $_.id -eq $RequirementId } | Select-Object -First 1
    
    if (-not $currentReq) {
        Write-Host "Requirement $RequirementId not found" -ForegroundColor Red
        exit 1
    }
    
    if ($currentReq.status -notin @("planned", "in_progress")) {
        Write-Host "Requirement $RequirementId has status '$($currentReq.status)' - cannot work on it" -ForegroundColor Yellow
        exit 1
    }
}
else {
    # Find first in_progress or planned
    $currentReq = $requirements.requirements | Where-Object { 
        $_.status -eq "in_progress" 
    } | Select-Object -First 1

    if (-not $currentReq) {
        $currentReq = $requirements.requirements | Where-Object { 
            $_.status -eq "planned" 
        } | Select-Object -First 1
    }

    if (-not $currentReq) {
        Write-Host "No requirements to work on " -NoNewline
        Write-Host "(all complete or blocked)" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "Working on: " -NoNewline
Write-Host "$($currentReq.id) - $($currentReq.title)" -ForegroundColor Green
Write-Host ""

# Initialize state if needed
if (-not (Test-Path $StateFile)) {
    $initialState = @{
        current_requirement_id = $currentReq.id
        last_run_id            = $null
        last_mode              = $null
        last_iteration_outcome = $null
        updated_at             = Get-Date -Format "o"
        current_iteration      = 0
        status                 = "ready"
        blocked_task           = $null
    }
    $initialState | ConvertTo-Json | Set-Content $StateFile
}

# Load state
$state = Get-Content $StateFile -Raw | ConvertFrom-Json

if ($null -eq $state.blocked_task) {
    $state | Add-Member -MemberType NoteProperty -Name blocked_task -Value $null -Force
}

# Initialize validation retry counter if it doesn't exist
if ($null -eq $state.validation_retry_count) {
    $state | Add-Member -MemberType NoteProperty -Name validation_retry_count -Value 0 -Force
}

# Reset validation retry counter if we're starting a new requirement
if ($state.current_requirement_id -ne $currentReq.id) {
    $state.validation_retry_count = 0
    $state.current_requirement_id = $currentReq.id
    Write-Host "[STATE] Starting new requirement, reset validation retry counter" -ForegroundColor Cyan
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

# Ensure cleanup on exit
$exitHandler = {
    Stop-HeartbeatJob
    Unregister-Agent -AgentId $agentConfig.id
}

# Register cleanup handler for graceful shutdown
# Note: PowerShell doesn't have direct cleanup hooks, but we'll call these at normal exit points
# The agent will be marked inactive automatically after heartbeat timeout if abruptly terminated

# Main iteration loop
for ($iteration = 1; $iteration -le $maxIterations; $iteration++) {
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "  Felix Agent - Iteration $iteration/$maxIterations" -ForegroundColor Cyan
    
    # Determine mode
    $mode = "building"  # Default
    
    # Look for most recent plan for current requirement in runs/
    $planPattern = "plan-$($currentReq.id).md"
    $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($existingPlans -and $existingPlans.Count -gt 0) {
        # Found plan in runs/ - use building mode
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        
        # Check if plan is substantive
        if ($planContent.Trim().Length -lt 50) {
            $mode = "planning"
        }
    }
    else {
        # No plan exists for current requirement - need to plan
        $mode = "planning"
    }
    
    # Override with state if available
    if ($state.last_mode -and $iteration -eq 1) {
        # Continue in same mode as last run on first iteration
        $mode = $state.last_mode
    }
    
    Write-Host "  Mode: " -NoNewline -ForegroundColor Cyan
    Write-Host $mode.ToUpper() -ForegroundColor $(if ($mode -eq "planning") { "Magenta" } else { "Blue" })
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host ""
    
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
    
    # Create run directory
    $runId = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
    $runDir = Join-Path $RunsDir $runId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    
    # Hook: OnPreIteration
    $hookResult = Invoke-PluginHook -HookName "OnPreIteration" -RunId $runId -HookData @{
        Iteration          = $iteration
        MaxIterations      = $maxIterations
        CurrentRequirement = $currentReq
        State              = $state
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
    
    # Add current requirement spec
    $currentSpecPath = Join-Path $ProjectPath $currentReq.spec_path
    if (Test-Path $currentSpecPath) {
        $specContent = Get-Content $currentSpecPath -Raw
        $contextParts += "# Current Requirement Spec: $($currentReq.id)`n`n$specContent"
    }
    
    # Add CONTEXT.md
    $contextFile = Join-Path $SpecsDir "CONTEXT.md"
    if (Test-Path $contextFile) {
        $contextContent = Get-Content $contextFile -Raw
        $contextParts += "# Project Context`n`n$contextContent"
    }
    
    # Add plan if in building mode
    if ($mode -eq "building" -and $existingPlans -and $existingPlans.Count -gt 0) {
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        $contextParts += "# Implementation Plan (from $($existingPlans[0].Directory.Name))`n`n$planContent"
        
        # Copy plan to current run for reference
        Copy-Item $latestPlanPath (Join-Path $runDir "plan-$($currentReq.id).md")
    }
    
    # Build minimal requirements context
    $reqContext = @{
        current = @{
            id        = $currentReq.id
            title     = $currentReq.title
            status    = $currentReq.status
            spec_path = $currentReq.spec_path
            priority  = $currentReq.priority
        }
    }
    
    # Add dependencies with their statuses if they exist
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
        $retryInfo += "2. **Fix the underlying issues** causing the test/build/lint failures`n"
        $retryInfo += "3. **DO NOT mark the task complete** until all validation passes`n"
        $retryInfo += "4. **Focus on fixing the errors** - Read error messages carefully and address root causes`n"
        
        # Load backpressure log from most recent run if available
        $lastRunId = $state.last_run_id
        if ($lastRunId) {
            $lastRunDir = Join-Path $RunsDir $lastRunId
            $backpressureLogPath = Join-Path $lastRunDir "backpressure.log"
            if (Test-Path $backpressureLogPath) {
                $backpressureLog = Get-Content $backpressureLogPath -Raw
                $retryInfo += "`n## Full Validation Output from Previous Iteration`n`n"
                $retryInfo += "The commands above produced the following output. **Read this carefully** to understand what needs to be fixed:`n`n"
                $retryInfo += $backpressureLog
                $retryInfo += "`n"
            }
        }
        
        $contextParts += $retryInfo
        
        Write-Host "[CONTEXT] " -NoNewline -ForegroundColor Yellow
        Write-Host "Injected blocked task failure context (retry $($state.blocked_task.retry_count)/$($state.blocked_task.max_retries))" -ForegroundColor Yellow
    }
    
    # Add plan output path instruction
    $planOutputPath = "runs/$runId/plan-$($currentReq.id).md"
    if ($mode -eq "planning") {
        $contextParts += "# Plan Output Path`n`nGenerate your implementation plan and save it to: **$planOutputPath**`n`nThis plan should contain ONLY tasks for requirement $($currentReq.id)."
    }
    else {
        $contextParts += "# Plan Update Path`n`nWhen marking tasks complete, update the plan at: **$planOutputPath**"
    }
    
    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"
    
    # Hook: OnContextGathering
    $gitDiff = if (Test-Path (Join-Path $ProjectPath ".git")) { git diff 2>$null } else { "" }
    $hookResult = Invoke-PluginHook -HookName "OnContextGathering" -RunId $runId -HookData @{
        Mode               = $mode
        CurrentRequirement = $currentReq
        GitDiff            = $gitDiff
        PlanContent        = if ($mode -eq "building" -and $planContent) { $planContent } else { "" }
        ContextFiles       = [System.Collections.ArrayList]@($contextParts)
    }
    
    if ($hookResult.AdditionalContext) {
        Write-Verbose "[PLUGINS] Adding additional context from plugins"
        $fullPrompt += "`n`n---`n`n# Plugin Context`n`n$($hookResult.AdditionalContext)"
    }
    
    # Write requirement ID
    Set-Content (Join-Path $runDir "requirement_id.txt") $currentReq.id
    
    # Update last_run_id in requirements.json
    $null = Update-RequirementRunId -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -RunId $runId
    
    # Capture git state before execution (for planning mode guardrails)
    $gitStateBefore = $null
    if ($mode -eq "planning") {
        Write-Host "[GUARDRAIL] " -NoNewline -ForegroundColor Yellow
        Write-Host "Capturing git state before planning iteration..." -ForegroundColor Yellow
        $gitStateBefore = Get-GitState -WorkingDir $ProjectPath
    }
    
    # Call agent executable (using config from agents.json)
    $executable = $agentConfig.executable
    $args = $agentConfig.args
    Write-Host "Calling $executable $($args -join ' ')...`n"
    
    # Hook: OnPreLLM
    $hookResult = Invoke-PluginHook -HookName "OnPreLLM" -RunId $runId -HookData @{
        Mode               = $mode
        CurrentRequirement = $currentReq
        PromptFile         = $promptFile
        FullPrompt         = $fullPrompt
    }
    
    if ($hookResult.SkipLLM) {
        Write-Host "[PLUGINS] LLM execution skipped: $($hookResult.Reason)"
        continue
    }
    
    if ($hookResult.ModifiedPrompt) {
        Write-Verbose "[PLUGINS] Using modified prompt from plugin"
        $fullPrompt = $hookResult.ModifiedPrompt
    }
    
    $droidSuccess = $false
    $droidError = $null
    try {
        # Ensure UTF-8 encoding is preserved in output capture
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        
        # Build command with arguments from agents.json
        $cmdArgs = @($args) + @()  # Convert to array and add any additional args
        $output = $fullPrompt | & $executable @cmdArgs 2>&1 | Out-String
        $output = $output.Trim()
        $droidSuccess = $true
    }
    catch {
        $droidError = $_
        Write-Host "ERROR during $executable execution: $_"
        
        # Write error report
        $report = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** false
**Timestamp:** $(Get-Date -Format "o")

## Error

```
$_
```

"@
        Set-Content (Join-Path $runDir "report.md") $report -Encoding UTF8
        
        $state.last_iteration_outcome = "error"
        $state.status = "error"
        $state.updated_at = Get-Date -Format "o"
        $state | ConvertTo-Json | Set-Content $StateFile
        
        Exit-FelixAgent -ExitCode 1
    }
    
    # === Post-droid processing (outside try/catch) ===
    Write-Host $output
    
    # Write output log
    Set-Content (Join-Path $runDir "output.log") $output -Encoding UTF8
    
    # Hook: OnPostLLM
    $hookResult = Invoke-PluginHook -HookName "OnPostLLM" -RunId $runId -HookData @{
        Mode               = $mode
        CurrentRequirement = $currentReq
        ExitCode           = if ($droidSuccess) { 0 } else { 1 }
        OutputPath         = Join-Path $runDir "output.log"
    }
    
    if (-not $hookResult.Success) {
        Write-Warning "[PLUGINS] Post-LLM hook reported failure: $($hookResult.ErrorMessage)"
    }
    
    # ====================================================================
    # Planning Mode Guardrail Enforcement
    # ====================================================================
    $guardrailViolations = $null
    if ($mode -eq "planning" -and $gitStateBefore) {
        Write-Host ""
        Write-Host "[GUARDRAIL] " -NoNewline -ForegroundColor Yellow
        Write-Host "Checking planning mode guardrails..." -ForegroundColor Yellow
        $guardrailViolations = Test-PlanningModeGuardrails -WorkingDir $ProjectPath -BeforeState $gitStateBefore -RunId $runId
        
        if ($guardrailViolations.HasViolations) {
            Write-Host ""
            Write-Host "[GUARDRAIL] " -NoNewline -ForegroundColor Red
            Write-Host "VIOLATIONS DETECTED - Reverting unauthorized changes..." -ForegroundColor Red
            Undo-PlanningViolations -WorkingDir $ProjectPath -BeforeState $gitStateBefore -Violations $guardrailViolations
            
            # Log the violation in the run directory
            $violationLog = @"
# Guardrail Violation Report

**Mode:** planning
**Run ID:** $runId
**Timestamp:** $(Get-Date -Format "o")

## Violations

**Commit Made:** $($guardrailViolations.CommitMade)

**Unauthorized Files:**
$(($guardrailViolations.UnauthorizedFiles | ForEach-Object { "- $_" }) -join "`n")

## Action Taken

All unauthorized changes have been reverted.
"@
            Set-Content (Join-Path $runDir "guardrail-violation.md") $violationLog -Encoding UTF8
            
            # Update state with guardrail violation
            $state.last_iteration_outcome = "guardrail_violation"
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json | Set-Content $StateFile
            
            Write-Host "[GUARDRAIL] " -NoNewline -ForegroundColor Yellow
            Write-Host "Continuing to next iteration after violation cleanup..." -ForegroundColor Yellow
            Write-Host ""
            continue  # Skip the rest of this iteration and continue to next
        }
        else {
            Write-Host "[GUARDRAIL] No violations detected - planning mode guardrails passed."
        }
    }
    
    # Create report
    $success = $LASTEXITCODE -eq 0
    # Join output array with newlines to preserve formatting
    $outputText = if ($output -is [array]) { $output -join "`n" } else { $output }
    $report = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** $success
**Timestamp:** $(Get-Date -Format "o")

## Output

$outputText

"@
    Set-Content (Join-Path $runDir "report.md") $report -Encoding UTF8
    
    # Check for task completion signal (building mode)
    if ($mode -eq "building" -and $output -match '<promise>TASK_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[TASK DONE] Task completed"
        
        # Hook: OnPreBackpressure
        $hookResult = Invoke-PluginHook -HookName "OnPreBackpressure" -RunId $runId -HookData @{
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
            
            # Extract task description from output for tracking
            $taskMatch = $output -match '\*\*Task Completed:\*\*\s*(.+?)(?:\r?\n|\*\*)'
            $blockedTaskDesc = if ($matches) { $matches[1].Trim() } else { "Unknown task" }
            
            # Build failed commands summary
            $failedCmdSummary = @()
            foreach ($failed in $backpressureResult.failed_commands) {
                $failedCmdSummary += "[$($failed.type)] $($failed.command) (exit: $($failed.exit_code))"
            }
            
            # Determine retry count - check if this is the same blocked task being retried
            $retryCount = 1
            if ($state.blocked_task -and $state.blocked_task.description -eq $blockedTaskDesc) {
                $retryCount = $state.blocked_task.retry_count + 1
            }
            
            # Hook: OnBackpressureFailed
            $hookResult = Invoke-PluginHook -HookName "OnBackpressureFailed" -RunId $runId -HookData @{
                CurrentRequirement = $currentReq
                ValidationResult   = $backpressureResult
                RetryCount         = $retryCount
            }
            
            if ($hookResult.ShouldRetry -and $hookResult.SuggestedFix) {
                Write-Host "[PLUGINS] Retry suggested: $($hookResult.Reason)"
            }
            
            # Get max retries from config (default to 3)
            $maxRetries = if ($config.backpressure.max_retries) { $config.backpressure.max_retries } else { 3 }
            
            # Check if max retries exceeded
            if ($retryCount -gt $maxRetries) {
                Write-Host ""
                Write-Host "[MAX RETRIES] Task has failed validation $retryCount times (max: $maxRetries)"
                Write-Host "[MAX RETRIES] Marking task as PERMANENTLY BLOCKED - requires manual intervention"
                
                $state.last_iteration_outcome = "max_retries_exceeded"
                $state.status = "max_retries_exceeded"
                $state.blocked_task = @{
                    description     = $blockedTaskDesc
                    blocked_at      = Get-Date -Format "o"
                    reason          = "max_retries_exceeded"
                    failed_commands = $failedCmdSummary
                    iteration       = $iteration
                    retry_count     = $retryCount
                    max_retries     = $maxRetries
                }
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
                
                # Write max retries report
                $maxRetriesReport = @"
# Max Retries Exceeded Report

**Task:** $blockedTaskDesc
**Blocked At:** $(Get-Date -Format "o")
**Retry Count:** $retryCount
**Max Retries:** $maxRetries
**Reason:** Validation has failed repeatedly

## Failed Commands

$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)

## Next Steps

This task requires manual intervention. The agent will not retry automatically.
Review the validation failures and fix the underlying issues before restarting.
"@
                Set-Content (Join-Path $runDir "max-retries-exceeded.md") $maxRetriesReport -Encoding UTF8
                
                # Mark requirement as blocked in requirements.json
                Write-Host "[BLOCKED] Marking requirement $($currentReq.id) as blocked due to backpressure failures" -ForegroundColor Red
                Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "blocked"
                Write-Host "[BLOCKED] To unblock: Fix validation issues, then manually change status to 'planned' in requirements.json" -ForegroundColor Yellow
                
                Write-Host "Exiting due to max retries exceeded (exit code 2)..."
                Exit-FelixAgent -ExitCode 2
            }
            
            Write-Host "[RETRY] Retry attempt $retryCount of $maxRetries"
            
            # Update state to indicate blocked task with details
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
            
            # Write blocked task report to run directory
            $blockedReport = @"
# Blocked Task Report

**Task:** $blockedTaskDesc
**Blocked At:** $(Get-Date -Format "o")
**Reason:** Validation failed
**Retry:** $retryCount of $maxRetries

## Failed Commands

$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)

## Backpressure Output

``````
$($backpressureResult.output)
``````

## Next Steps

The agent will retry this task in the next iteration ($($maxRetries - $retryCount) attempts remaining).
Fix the validation issues to unblock progress.
"@
            Set-Content (Join-Path $runDir "blocked-task.md") $blockedReport -Encoding UTF8
            Write-Host "[BLOCKED] Details written to: $(Join-Path $runDir 'blocked-task.md')"
            
            # Continue to next iteration - LLM should fix the issues
            Write-Host "Continuing to next iteration to fix validation issues..."
            continue
        }
        
        # Backpressure passed (or was skipped) - clear blocked state and proceed with commit
        if ($state.blocked_task) {
            Write-Host "[UNBLOCKED] Previous blocked task is now passing validation"
            $state.blocked_task = $null
            $state.status = "running"
        }
        
        $gitStatus = git status --porcelain 2>&1
        if ($gitStatus -and $LASTEXITCODE -eq 0) {
            Write-Host "[COMMIT] Uncommitted changes detected, committing..."
            
            # Extract task description from output for commit message
            $taskMatch = $output -match '\*\*Task Completed:\*\*\s*(.+?)(?:\r?\n|\*\*)'
            $taskDesc = if ($matches) { $matches[1].Trim() } else { "Task completion" }
            
            # Stage all changes
            git add -A 2>&1 | Out-Null
            
            # Capture git diff after staging (shows exactly what will be committed)
            Write-Host "[ARTIFACTS] Capturing git diff to diff.patch..."
            try {
                $diffOutput = git diff --cached 2>&1
                if ($diffOutput) {
                    $diffPath = Join-Path $runDir "diff.patch"
                    Set-Content $diffPath $diffOutput -Encoding UTF8
                    Write-Host "[ARTIFACTS] Git diff saved to: diff.patch"
                }
                else {
                    Write-Host "[ARTIFACTS] No changes to capture in diff"
                }
            }
            catch {
                Write-Host "[ARTIFACTS] Warning: Failed to capture git diff: $_"
            }
            
            # Commit changes
            $commitMsg = "Felix ($($currentReq.id)): $taskDesc"
            
            # Hook: OnPreCommit
            $stagedFiles = git diff --cached --name-only 2>&1
            $hookResult = Invoke-PluginHook -HookName "OnPreCommit" -RunId $runId -HookData @{
                CurrentRequirement = $currentReq
                CommitMessage      = $commitMsg
                StagedFiles        = [System.Collections.ArrayList]@($stagedFiles -split "`n" | Where-Object { $_ })
            }
            
            if ($hookResult.SkipCommit) {
                Write-Host "[PLUGINS] Commit skipped: $($hookResult.Reason)"
                continue
            }
            
            if ($hookResult.ModifiedCommitMessage) {
                $commitMsg = $hookResult.ModifiedCommitMessage
                Write-Verbose "[PLUGINS] Using modified commit message"
            }
            
            $commitOutput = git commit -m $commitMsg 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $commitHash = git rev-parse --short HEAD 2>&1
                Write-Host "[COMMIT] ✅ Changes committed: $commitHash - $commitMsg"
            }
            else {
                Write-Host "[COMMIT] ⚠️ Git commit failed: $commitOutput"
            }
        }
        else {
            Write-Host "[COMMIT] No changes to commit (task may have been read-only)"
        }
        
        Write-Host "Continuing to next iteration..."
        # Continue loop to next iteration
    }
    
    # Check for all tasks completion signal (building mode)
    if ($mode -eq "building" -and $output -match '<promise>ALL_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[ALL COMPLETE] LLM signaled all tasks complete. Verifying with task checker..."
        
        # Load verification prompt
        $verificationPromptPath = Join-Path $ProjectPath "felix\prompts\check-tasks-complete.md"
        
        if (-not (Test-Path $verificationPromptPath)) {
            Write-Host "[WARNING] Task verification prompt not found at $verificationPromptPath"
            Write-Host "Falling back to trusting LLM signal..."
            $tasksVerified = $true
        }
        else {
            # Get latest plan
            $planPattern = "plan-$($currentReq.id).md"
            $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            
            if ($existingPlans -and $existingPlans.Count -gt 0) {
                $latestPlanPath = $existingPlans[0].FullName
                $planContent = Get-Content $latestPlanPath -Raw
                
                # Load verification prompt and inject plan
                $verificationPrompt = Get-Content $verificationPromptPath -Raw
                $fullPrompt = $verificationPrompt -replace '\{PLAN_CONTENT\}', $planContent
                
                # Create temporary prompt file for verification
                $tempPromptPath = Join-Path $RunDir "verify-tasks-prompt.txt"
                $fullPrompt | Out-File -FilePath $tempPromptPath -Encoding UTF8
                
                Write-Host "[VERIFY] Asking LLM to verify task completion..."
                
                # Call agent with verification prompt (use config from agents.json)
                $cmdArgs = @($args) + @()
                $verificationOutput = $fullPrompt | & $executable @cmdArgs 2>&1 | Out-String
                
                Write-Host $verificationOutput
                
                if ($verificationOutput -match '<verification>TASKS_COMPLETE</verification>') {
                    Write-Host "[VERIFY] ✅ LLM confirmed all tasks complete"
                    $tasksVerified = $true
                }
                else {
                    Write-Host "[WARNING] LLM verification found incomplete tasks"
                    Write-Host "Ignoring ALL_COMPLETE signal and continuing iterations..."
                    $tasksVerified = $false
                }
                
                # Clean up temp prompt file
                if (Test-Path $tempPromptPath) {
                    Remove-Item $tempPromptPath -Force
                }
            }
            else {
                Write-Host "[WARNING] Could not find plan file to verify"
                Write-Host "Trusting LLM signal..."
                $tasksVerified = $true
            }
        }
        
        if ($tasksVerified) {
            # All tasks verified complete - run validation before marking complete
            Write-Host ""
            Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
            Write-Host "All plan tasks complete. Running validation..." -ForegroundColor Magenta
                
            # Run validation script
            $validationScript = Join-Path $ProjectPath "scripts\validate-requirement.ps1"
            $validationPassed = $false
                
            if (-not (Test-Path $validationScript)) {
                Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
                Write-Host "❌ Validation script not found at $validationScript" -ForegroundColor Red
                Exit-FelixAgent -ExitCode 1
            }
                
            try {
                $validationResult = Invoke-RequirementValidation -ValidationScript $validationScript -RequirementId $currentReq.id
                $validationOutput = $validationResult.output
                $validationExitCode = $validationResult.exitCode
                    
                Write-Host $validationOutput
                    
                if ($validationExitCode -eq 0) {
                    Write-Host ""
                    Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
                    Write-Host "✅ Validation PASSED!" -ForegroundColor Green
                    $validationPassed = $true
                }
                else {
                    Write-Host ""
                    Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
                    Write-Host "❌ Validation FAILED (exit code: $validationExitCode)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
                Write-Host "❌ Error running validation: $_" -ForegroundColor Red
                Exit-FelixAgent -ExitCode 1
            }
                
            if ($validationPassed) {
                # Validation passed - mark requirement complete
                $state.status = "complete"
                $state.last_iteration_outcome = "complete"
                $state.validation_retry_count = 0
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json | Set-Content $StateFile
                    
                # Update requirements.json to mark requirement as complete
                Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "complete"
                    
                Write-Host ""
                Write-Host "Felix Agent complete - all tasks done and validated!"
                Exit-FelixAgent -ExitCode 0
            }
            else {
                # Validation failed - emit STUCK signal
                Write-Host ""
                Write-Host "[STUCK] Tasks complete but validation failed!"
                Write-Host "<promise>STUCK</promise>"
                    
                # Track validation retry count
                if (-not $state.validation_retry_count) {
                    $state.validation_retry_count = 0
                }
                $state.validation_retry_count++
                    
                # Get validation config (with defaults)
                $validationConfig = $config.validation
                $markBlockedOnFailure = if ($null -ne $validationConfig.mark_blocked_on_failure) { $validationConfig.mark_blocked_on_failure } else { $true }
                $exitOnBlocked = if ($null -ne $validationConfig.exit_on_blocked) { $validationConfig.exit_on_blocked } else { $true }
                $maxValidationRetries = if ($null -ne $validationConfig.max_validation_retries) { $validationConfig.max_validation_retries } else { 1 }
                    
                # Log retry attempt
                $totalAttempts = $maxValidationRetries + 1
                Write-Host "[VALIDATION RETRY] Attempt $($state.validation_retry_count) of $totalAttempts" -ForegroundColor Yellow
                    
                # Check if max retries exceeded
                if ($state.validation_retry_count -gt $maxValidationRetries) {
                    Write-Host ""
                    Write-Host "[BLOCKED] Maximum validation retries ($totalAttempts attempts) exceeded" -ForegroundColor Red
                        
                    # Mark requirement as blocked if configured
                    if ($markBlockedOnFailure) {
                        Write-Host "[BLOCKED] Marking requirement $($currentReq.id) as blocked in requirements.json" -ForegroundColor Red
                        Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "blocked"
                        Write-Host "[BLOCKED] Requirement blocked due to repeated validation failures." -ForegroundColor Red
                        Write-Host "[BLOCKED] To unblock: Fix validation issues, then manually change status to 'planned' in requirements.json" -ForegroundColor Yellow
                    }
                        
                    $state.last_iteration_outcome = "validation_blocked"
                    $state.status = "blocked"
                    $state.updated_at = Get-Date -Format "o"
                    $state | ConvertTo-Json | Set-Content $StateFile
                        
                    # Exit if configured
                    if ($exitOnBlocked) {
                        Write-Host "[EXIT] Exiting to allow other requirements to proceed (exit code 3)" -ForegroundColor Yellow
                        Exit-FelixAgent -ExitCode 3
                    }
                }
                    
                $state.last_iteration_outcome = "validation_failed"
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json | Set-Content $StateFile
                    
                # Continue to next iteration to allow LLM to fix issues
            }
        }
    }
    
    # Check for planning mode signals
    if ($mode -eq "planning" -and $output -match '<promise>PLAN_DRAFT</promise>') {
        Write-Host ""
        Write-Host "[PLAN DRAFT] Initial plan created, will review next iteration"
        # Continue loop for review iteration
    }
    
    if ($mode -eq "planning" -and $output -match '<promise>PLAN_REFINING</promise>') {
        Write-Host ""
        Write-Host "[REFINING] Plan needs refinement, continuing iterations..."
        # Continue loop
    }
    
    if ($mode -eq "planning" -and $output -match '<promise>PLAN_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[PLAN READY] Planning complete, transitioning to BUILDING mode"
        $state.last_mode = "building"
    }
    
    # Update state
    $state.last_iteration_outcome = "success"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    
    # Hook: OnPostIteration
    $hookResult = Invoke-PluginHook -HookName "OnPostIteration" -RunId $runId -HookData @{
        Iteration          = $iteration
        MaxIterations      = $maxIterations
        CurrentRequirement = $currentReq
        Outcome            = $state.last_iteration_outcome
        State              = $state
    }
    
    if (-not $hookResult.ShouldContinue) {
        Write-Host "[PLUGINS] Stopping iterations: $($hookResult.Reason)"
        break
    }
    
    Write-Host ""
    Write-Host "Iteration $iteration complete. Continuing..."
    Write-Host ""
    
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "[WARNING] Reached max iterations ($maxIterations)"

$state.status = "incomplete"
$state.last_iteration_outcome = "max_iterations"
$state.updated_at = Get-Date -Format "o"
$state | ConvertTo-Json | Set-Content $StateFile

Exit-FelixAgent -ExitCode 1

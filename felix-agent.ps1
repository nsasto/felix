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

# Load compatibility utilities, state machine, git operations, state management, plugins, validator, workflow, and agent registration
. "$PSScriptRoot/felix/core/compat-utils.ps1"
. "$PSScriptRoot/felix/core/agent-state.ps1"
. "$PSScriptRoot/felix/core/git-manager.ps1"
. "$PSScriptRoot/felix/core/state-manager.ps1"
. "$PSScriptRoot/felix/core/plugin-manager.ps1"
. "$PSScriptRoot/felix/core/validator.ps1"
. "$PSScriptRoot/felix/core/workflow.ps1"
. "$PSScriptRoot/felix/core/agent-registration.ps1"

# Configure UTF-8 encoding for console output
# Must be done in this specific order for Windows PowerShell compatibility
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"

# Resolve project path
try {
    $ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
    # Store in script scope for Exit-FelixAgent cleanup
    $script:ProjectPath = $ProjectPath
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
# Note: Get-GitState is now in felix/core/git-manager.ps1

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
        if ($afterState.commitHash -ne $BeforeState.commitHash) {
            $violations.CommitMade = $true
            $violations.HasViolations = $true
            Write-Host "[GUARDRAIL VIOLATION] " -NoNewline -ForegroundColor Red
            Write-Host "New commit detected during planning mode!" -ForegroundColor Yellow
        }
        
        # Check for unauthorized file modifications
        $allModifiedFiles = @($afterState.modifiedFiles) + @($afterState.untrackedFiles) | 
        Where-Object { $_ -and $_.Trim() -ne "" } |
        Select-Object -Unique
        
        foreach ($file in $allModifiedFiles) {
            # Skip if file was already modified before
            if ($BeforeState.modifiedFiles -contains $file -or $BeforeState.untrackedFiles -contains $file) {
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
            git reset --soft $BeforeState.commitHash 2>$null
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

# Note: Core state management is now in felix/core/state-manager.ps1
# This wrapper maintains backward compatibility with the legacy parameter names
function Update-RequirementStatus {
    param(
        [string]$RequirementsFilePath,
        [string]$RequirementId,
        [ValidateSet('draft', 'planned', 'in_progress', 'complete', 'blocked')]
        [string]$NewStatus
    )
    
    try {
        # Call the state-manager function with correct parameter name mapping
        & (Get-Module -ListAvailable | Where-Object { $_.ExportedFunctions.Keys -contains 'Update-RequirementStatus' }).ExportedFunctions['Update-RequirementStatus'] `
            -RequirementsFile $RequirementsFilePath -RequirementId $RequirementId -Status $NewStatus
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Updated $RequirementId status to '$NewStatus'" -ForegroundColor Green
        return $true
    }
    catch {
        # Fallback to inline implementation if module function not available
        $json = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $found = $false
        if ($json.requirements) {
            foreach ($req in $json.requirements) {
                if ($req.id -eq $RequirementId) {
                    $req.status = $NewStatus
                    $found = $true
                    break
                }
            }
        }
        if (-not $found) {
            Write-Host "[REQUIREMENTS] Warning: Requirement $RequirementId not found" -ForegroundColor Yellow
            return $false
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $RequirementsFilePath
        Write-Host "[REQUIREMENTS] Updated $RequirementId status to '$NewStatus'" -ForegroundColor Green
        return $true
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

# Set-WorkflowStage: Now in felix/core/workflow.ps1

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

# Get-BackpressureCommands: Now in felix/core/validator.ps1

# Invoke-BackpressureValidation: Now in felix/core/validator.ps1

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
            @{
                id                = 1
                name              = "codex-cli"
                executable        = "codex"
                args              = @("-C", ".", "-s", "workspace-write", "-a", "never", "exec", "--color", "never", "-")
                working_directory = "."
                environment       = @{}
            }
            @{
                id                = 2
                name              = "claude-code"
                executable        = "claude"
                args              = @("-p", "--output-format", "text")
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

# Agent registration functions: Now in felix/core/agent-registration.ps1
# Create script-scoped aliases to avoid naming conflicts with wrappers
New-Alias -Name 'Register-AgentInternal' -Value 'Register-Agent' -Scope Script -Force
New-Alias -Name 'Send-AgentHeartbeatInternal' -Value 'Send-AgentHeartbeat' -Scope Script -Force
New-Alias -Name 'Start-HeartbeatJobInternal' -Value 'Start-HeartbeatJob' -Scope Script -Force
New-Alias -Name 'Stop-HeartbeatJobInternal' -Value 'Stop-HeartbeatJob' -Scope Script -Force
New-Alias -Name 'Unregister-AgentInternal' -Value 'Unregister-Agent' -Scope Script -Force

# Wrappers provide backward compatibility with script-scoped $BackendBaseUrl
function Register-Agent {
    param([int]$AgentId, [string]$AgentName, [int]$ProcessId, [string]$Hostname)
    return Register-AgentInternal -AgentId $AgentId -AgentName $AgentName -ProcessId $ProcessId -Hostname $Hostname -BackendBaseUrl $script:BackendBaseUrl
}

function Send-AgentHeartbeat {
    param([int]$AgentId, [string]$CurrentRequirementId)
    return Send-AgentHeartbeatInternal -AgentId $AgentId -CurrentRequirementId $CurrentRequirementId -BackendBaseUrl $script:BackendBaseUrl
}

function Start-HeartbeatJob {
    param([int]$AgentId, [string]$BaseUrl)
    if ($script:HeartbeatJob) {
        Stop-HeartbeatJobInternal -Job $script:HeartbeatJob
    }
    $script:HeartbeatJob = Start-HeartbeatJobInternal -AgentId $AgentId -BackendBaseUrl $BaseUrl
}

function Stop-HeartbeatJob {
    if ($script:HeartbeatJob) {
        Stop-HeartbeatJobInternal -Job $script:HeartbeatJob
        $script:HeartbeatJob = $null
    }
}

function Unregister-Agent {
    param([int]$AgentId)
    Unregister-AgentInternal -AgentId $AgentId -BackendBaseUrl $script:BackendBaseUrl
}

function Exit-FelixAgent {
    <#
    .SYNOPSIS
    Cleanly exit the agent with proper cleanup
    #>
    param(
        [int]$ExitCode = 0
    )
    
    # Clear workflow stage on exit
    if ($script:ProjectPath) {
        Set-WorkflowStage -Clear -ProjectPath $script:ProjectPath
    }
    
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

# Initialize-PluginSystem: Now in felix/core/plugin-manager.ps1

# Invoke-PluginHook: Now in felix/core/plugin-manager.ps1

# Invoke-PluginHookSafely: Now in felix/core/plugin-manager.ps1

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

# Helper function to convert PSCustomObject to hashtable recursively
function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)]$InputObject)
    
    process {
        if ($null -eq $InputObject) { return $null }
        
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) { ConvertTo-Hashtable $object }
            )
            return , $collection
        }
        elseif ($InputObject -is [PSCustomObject]) {
            $hashtable = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hashtable[$property.Name] = ConvertTo-Hashtable $property.Value
            }
            return $hashtable
        }
        else {
            return $InputObject
        }
    }
}

# Load or initialize state
$state = if (Test-Path $StateFile) {
    try {
        $rawContent = Get-Content $StateFile -Raw
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            Write-Host "[WARNING] State file is empty, initializing new state" -ForegroundColor Yellow
            @{
                current_requirement_id = $null
                current_iteration      = 0
                last_mode              = $null
                status                 = "idle"
                validation_retry_count = 0
            }
        }
        else {
            $loadedState = $rawContent | ConvertFrom-Json
            if ($null -eq $loadedState) {
                Write-Host "[WARNING] State file loaded but resulted in null, initializing new state" -ForegroundColor Yellow
                @{
                    current_requirement_id = $null
                    current_iteration      = 0
                    last_mode              = $null
                    status                 = "idle"
                    validation_retry_count = 0
                }
            }
            else {
                # Convert PSCustomObject to hashtable for mutability (including nested objects)
                $converted = ConvertTo-Hashtable $loadedState
                if ($null -eq $converted) {
                    Write-Host "[WARNING] Conversion to hashtable failed, initializing new state" -ForegroundColor Yellow
                    @{
                        current_requirement_id = $null
                        current_iteration      = 0
                        last_mode              = $null
                        status                 = "idle"
                        validation_retry_count = 0
                    }
                }
                else {
                    $converted
                }
            }
        }
    }
    catch {
        Write-Host "[WARNING] Failed to load state file: $_" -ForegroundColor Yellow
        Write-Host "[WARNING] Initializing new state" -ForegroundColor Yellow
        @{
            current_requirement_id = $null
            current_iteration      = 0
            last_mode              = $null
            status                 = "idle"
            validation_retry_count = 0
        }
    }
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
if ($null -ne $state -and -not $state.ContainsKey('validation_retry_count')) {
    $state.validation_retry_count = 0
}

# Initialize state machine for this execution
$agentState = New-AgentState -InitialMode "Planning"
$agentState.RequirementId = $RequirementId
Write-Host "[STATE-MACHINE] Initialized in Planning mode for requirement $RequirementId" -ForegroundColor DarkGray

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
    
    # Workflow Stage: start_iteration
    Set-WorkflowStage -Stage "start_iteration" -ProjectPath $ProjectPath
    
    # --- FIX START: Generate Run ID and Setup Dir immediately ---
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runId = "$($currentReq.id)-$timestamp-it$iteration"
    
    $runDir = Join-Path $RunsDir $runId
    if (-not (Test-Path $runDir)) {
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    }
    
    # Write requirement ID to run directory for tracking
    Set-Content (Join-Path $runDir "requirement_id.txt") $currentReq.id -Encoding UTF8
    
    # Update state with current run ID
    $state.last_run_id = $runId
    
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
        
        # Transition state machine to Building
        if ($agentState.Mode -ne "Building") {
            $agentState.TransitionTo('Building')
            Write-Host "[STATE-MACHINE] Transitioned to Building mode" -ForegroundColor DarkGray
        }
        
        # Copy plan to current run directory for audit trail
        $planSnapshotPath = Join-Path $runDir "plan-$($currentReq.id).md"
        Copy-Item $latestPlanPath $planSnapshotPath -Force
        Write-Host "[ARTIFACTS] Plan snapshot saved to run directory" -ForegroundColor DarkGray
    }
    else {
        # No plan found - use planning mode (or default)
        $mode = if ($state.last_mode) { $state.last_mode } else { $defaultMode }
        if ($mode -eq "building" -and -not $existingPlans) {
            Write-Host "[MODE] No plan found, falling back to PLANNING mode" -ForegroundColor Yellow
            $mode = "planning"
        }
        # State machine stays in Planning mode (default)
        Write-Host "[STATE-MACHINE] Remaining in Planning mode" -ForegroundColor DarkGray
        $latestPlanPath = $null
        $planContent = $null
    }

    # Workflow Stage: determine_mode
    Set-WorkflowStage -Stage "determine_mode" -ProjectPath $ProjectPath

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

    # Workflow Stage: gather_context
    Set-WorkflowStage -Stage "gather_context" -ProjectPath $ProjectPath

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

    # Workflow Stage: build_prompt
    Set-WorkflowStage -Stage "build_prompt" -ProjectPath $ProjectPath

    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"

    # Hook: OnContextGathering
    $gitDiff = ""
    if (Test-Path (Join-Path $ProjectPath ".git")) {
        Push-Location $ProjectPath
        try {
            $gitDiff = git diff 2>$null
        }
        finally {
            Pop-Location
        }
    }
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

    # Capture commit hash before execution to detect agent-created commits
    Push-Location $ProjectPath
    try {
        $beforeCommitHash = git rev-parse HEAD 2>$null
    }
    finally {
        Pop-Location
    }

    # Workflow Stage: execute_llm
    Set-WorkflowStage -Stage "execute_llm" -ProjectPath $ProjectPath

    # Execute agent
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Executing agent '$($script:agentName)' in $mode mode..." -ForegroundColor White

    $executable = $agentConfig.executable
    $agentArgs = $agentConfig.args
    $agentWorkingDir = if ($agentConfig.working_directory) { $agentConfig.working_directory } else { "." }
    $startTime = Get-Date

    # Hook: OnPreExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPreExecution" -RunId $runId -HookData @{
        Executable = $executable
        Args       = [System.Collections.ArrayList]@($agentArgs)
        Prompt     = $fullPrompt
    }
    
    if ($hookResult.ModifiedArgs) {
        $agentArgs = $hookResult.ModifiedArgs
        Write-Verbose "[PLUGINS] Using modified executable arguments"
    }

    # Execute the agent and capture output
    $agentCwd = if ([System.IO.Path]::IsPathRooted($agentWorkingDir)) {
        $agentWorkingDir
    }
    else {
        Join-Path $ProjectPath $agentWorkingDir
    }

    $envBackup = @{}
    try {
        # Apply agent environment variables (best-effort)
        if ($agentConfig.environment) {
            foreach ($prop in $agentConfig.environment.PSObject.Properties) {
                $key = $prop.Name
                $value = [string]$prop.Value
                $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }

        Push-Location $agentCwd
        try {
            $output = $fullPrompt | & $executable @agentArgs 2>&1 | Out-String
        }
        finally {
            Pop-Location
        }
    }
    finally {
        foreach ($key in $envBackup.Keys) {
            [Environment]::SetEnvironmentVariable($key, $envBackup[$key], "Process")
        }
    }
    $duration = (Get-Date) - $startTime

    # Write raw output to run directory
    Set-Content (Join-Path $runDir "output.log") $output -Encoding UTF8
    Write-Host "[AGENT] " -NoNewline -ForegroundColor Cyan
    Write-Host "Execution complete (Duration: $($duration.TotalSeconds.ToString("F1"))s)" -ForegroundColor White

    # Hook: OnPostExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostExecution" -RunId $runId -HookData @{
        Output   = $output
        Duration = $duration.TotalSeconds
    }

    # Workflow Stage: process_output
    Set-WorkflowStage -Stage "process_output" -ProjectPath $ProjectPath

    # Planning Mode Guardrails
    if ($mode -eq "planning") {
        # Workflow Stage: check_guardrails (conditional - planning mode only)
        Set-WorkflowStage -Stage "check_guardrails" -ProjectPath $ProjectPath
        
        $violations = Test-PlanningModeGuardrails -WorkingDir $ProjectPath -BeforeState $beforeState -RunId $runId
        if ($violations.HasViolations) {
            Undo-PlanningViolations -WorkingDir $ProjectPath -BeforeState $beforeState -Violations $violations
            
            # Document guardrail violations
            $violationReport = @"
# Planning Mode Guardrail Violation

**Timestamp:** $(Get-Date -Format "o")
**Iteration:** $iteration

## Violations Detected

"@
            
            if ($violations.CommitMade) {
                $violationReport += "`n### Unauthorized Commit`n`nA commit was made during planning mode and has been reverted.`n"
            }
            
            if ($violations.UnauthorizedFiles.Count -gt 0) {
                $violationReport += "`n### Unauthorized File Modifications`n`nThe following files were modified outside allowed paths:`n`n"
                foreach ($file in $violations.UnauthorizedFiles) {
                    $violationReport += "- $file`n"
                }
                $violationReport += "`nThese changes have been reverted.`n"
            }
            
            $violationReport += @"

## Allowed Modifications in Planning Mode

- runs/ directory (plan files)
- felix/state.json (execution state)
- felix/requirements.json (requirement status)

## What This Means

The LLM attempted to modify code files during planning mode, which is not allowed.
Planning mode is for creating/refining plans only.
"@
            
            Set-Content (Join-Path $runDir "guardrail-violation.md") $violationReport -Encoding UTF8
            Write-Host "[ARTIFACTS] Guardrail violation report saved" -ForegroundColor DarkGray
            
            # Update state to reflect failure
            $state.last_iteration_outcome = "guardrail_violation"
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json | Set-Content $StateFile
            
            Write-Host "[AGENT] " -NoNewline -ForegroundColor Red
            Write-Host "Planning mode aborted due to guardrail violations." -ForegroundColor Red
            continue
        }
    }

    # Workflow Stage: detect_task
    Set-WorkflowStage -Stage "detect_task" -ProjectPath $ProjectPath

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
            # Workflow Stage: run_backpressure
            Set-WorkflowStage -Stage "run_backpressure" -ProjectPath $ProjectPath
            
            # Transition to Validating state before running backpressure
            if ($agentState.Mode -eq "Building" -and $agentState.CanTransitionTo('Validating')) {
                $agentState.TransitionTo('Validating')
                Write-Host "[STATE-MACHINE] Transitioned to Validating mode (running backpressure)" -ForegroundColor DarkGray
            }
            
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
            
            # Write blocked task details
            $blockedTaskReport = @"
# Blocked Task

**Task:** $blockedTaskDesc
**Blocked At:** $(Get-Date -Format "o")
**Reason:** Validation failed (backpressure)
**Retry Attempt:** $retryCount of $maxRetries

## Failed Commands

$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)

## Next Steps

Review the backpressure.log for detailed error output.
Fix the failing tests/builds before the agent can proceed.
"@

            Set-Content (Join-Path $runDir "blocked-task.md") $blockedTaskReport -Encoding UTF8
            Write-Host "[ARTIFACTS] Blocked task report saved" -ForegroundColor DarkGray

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
                
                # Transition state machine to Blocked
                if ($agentState.CanTransitionTo('Blocked')) {
                    $agentState.TransitionTo('Blocked')
                    Write-Host "[STATE-MACHINE] Transitioned to Blocked mode (max retries exceeded)" -ForegroundColor DarkGray
                }
                
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
            
            # Transition state machine to Blocked (temporary, will retry)
            if ($agentState.CanTransitionTo('Blocked')) {
                $agentState.TransitionTo('Blocked')
                Write-Host "[STATE-MACHINE] Transitioned to Blocked mode (will retry)" -ForegroundColor DarkGray
            }
            
            continue
        }

        # Clear blocked status on success and transition back to Building
        $state.blocked_task = $null
        
        if ($agentState.Mode -eq "Validating") {
            # Validation passed, back to Building for next iteration
            $agentState.TransitionTo('Building')
            Write-Host "[STATE-MACHINE] Transitioned back to Building mode (validation passed)" -ForegroundColor DarkGray
        }

        # Workflow Stage: commit_changes
        Set-WorkflowStage -Stage "commit_changes" -ProjectPath $ProjectPath

        # Check if agent already committed changes
        Push-Location $ProjectPath
        try {
            $afterCommitHash = git rev-parse HEAD 2>$null
        }
        finally {
            Pop-Location
        }
        if ($beforeCommitHash -ne $afterCommitHash) {
            # Agent created commit - capture diff from the commit
            Push-Location $ProjectPath
            try {
                $commitHash = git rev-parse --short HEAD 2>$null
                $commitMsg = git log -1 --pretty=%B 2>$null
            }
            finally {
                Pop-Location
            }
            Write-Host "[COMMIT] ✅ $commitHash - $commitMsg"
            
            Write-Host "[ARTIFACTS] Capturing git diff from commit..."
            Push-Location $ProjectPath
            try {
                $diffOutput = git show HEAD --no-color 2>$null
            }
            finally {
                Pop-Location
            }
            $diffPath = Join-Path $runDir "diff.patch"
            Set-Content $diffPath $diffOutput -Encoding UTF8
            Write-Host "[ARTIFACTS] Git diff saved to: diff.patch"
        }
        else {
            # PowerShell handles staging and commit
            Write-Host "[ARTIFACTS] Capturing git diff to diff.patch..."
            $prevErrorAction = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                Push-Location $ProjectPath
                try {
                    git add -A 2>$null | Out-Null
                    $diffOutput = git diff --cached 2>$null
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                $ErrorActionPreference = $prevErrorAction
            }
            if ($diffOutput) {
                $diffPath = Join-Path $runDir "diff.patch"
                Set-Content $diffPath $diffOutput -Encoding UTF8
                Write-Host "[ARTIFACTS] Git diff saved to: diff.patch"
            }
            
            # Commit changes (if enabled)
            $shouldCommit = $config.executor.commit_on_complete -and -not $NoCommit
            if ($shouldCommit) {
                $commitMsg = "Felix ($($currentReq.id)): $taskDesc"
                $prevErrorAction = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                try {
                    Push-Location $ProjectPath
                    try {
                        $commitOutput = git commit -m $commitMsg 2>&1
                    }
                    finally {
                        Pop-Location
                    }
                }
                finally {
                    $ErrorActionPreference = $prevErrorAction
                }
                if ($LASTEXITCODE -eq 0) {
                    Push-Location $ProjectPath
                    try {
                        $commitHash = git rev-parse --short HEAD 2>$null
                    }
                    finally {
                        Pop-Location
                    }
                    Write-Host "[COMMIT] ✅ Changes committed: $commitHash - $commitMsg"
                }
                else {
                    Write-Host "[COMMIT] ❌ Failed to commit changes:" -ForegroundColor Red
                    Write-Host $commitOutput -ForegroundColor Red
                }
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
        
        # Transition state machine to Building
        if ($agentState.Mode -ne "Building") {
            $agentState.TransitionTo('Building')
            Write-Host "[STATE-MACHINE] Transitioned to Building mode" -ForegroundColor DarkGray
        }
    }

    # All requirements met?
    if ($output -match '<promise>ALL_REQUIREMENTS_MET</promise>') {
        # Workflow Stage: update_status
        Set-WorkflowStage -Stage "update_status" -ProjectPath $ProjectPath
        
        # Transition state machine to Complete
        if ($agentState.Mode -ne "Complete") {
            if ($agentState.CanTransitionTo('Complete')) {
                $agentState.TransitionTo('Complete')
                Write-Host "[STATE-MACHINE] Transitioned to Complete mode" -ForegroundColor DarkGray
            }
            else {
                # Need to go through Validating first
                if ($agentState.Mode -eq "Building") {
                    $agentState.TransitionTo('Validating')
                    Write-Host "[STATE-MACHINE] Transitioned to Validating mode" -ForegroundColor DarkGray
                }
                $agentState.TransitionTo('Complete')
                Write-Host "[STATE-MACHINE] Transitioned to Complete mode" -ForegroundColor DarkGray
            }
        }
        
        # Check validation logic...
        Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "complete"
        Exit-FelixAgent -ExitCode 0
    }

    # Workflow Stage: update_status
    Set-WorkflowStage -Stage "update_status" -ProjectPath $ProjectPath

    # Update state
    $state.last_iteration_outcome = "success"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    
    # Create structured iteration report
    $reportContent = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** $($state.last_iteration_outcome -eq 'success')
**Timestamp:** $(Get-Date -Format "o")

## Output

$output
"@

    Set-Content (Join-Path $runDir "report.md") $reportContent -Encoding UTF8

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

    # Workflow Stage: iteration_complete
    Set-WorkflowStage -Stage "iteration_complete" -ProjectPath $ProjectPath

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

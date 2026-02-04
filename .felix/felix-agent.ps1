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

# Load core modules
. "$PSScriptRoot/core/emit-event.ps1"
. "$PSScriptRoot/core/compat-utils.ps1"
. "$PSScriptRoot/core/agent-state.ps1"
. "$PSScriptRoot/core/git-manager.ps1"
. "$PSScriptRoot/core/state-manager.ps1"
. "$PSScriptRoot/core/plugin-manager.ps1"
. "$PSScriptRoot/core/validator.ps1"
. "$PSScriptRoot/core/workflow.ps1"
. "$PSScriptRoot/core/agent-registration.ps1"
. "$PSScriptRoot/core/guardrails.ps1"
. "$PSScriptRoot/core/python-utils.ps1"
. "$PSScriptRoot/core/requirements-utils.ps1"
. "$PSScriptRoot/core/exit-handler.ps1"
. "$PSScriptRoot/core/config-loader.ps1"
. "$PSScriptRoot/core/initialization.ps1"
. "$PSScriptRoot/core/executor.ps1"

# Configure UTF-8 encoding for console output
# Must be done in this specific order for Windows PowerShell compatibility
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"

# Resolve project path
try {
    $ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
    $script:ProjectPath = $ProjectPath
}
catch {
    Emit-Error -ErrorType "InvalidProjectPath" -Message "Invalid project path: $ProjectPath" -Severity "fatal" -Context @{ error = $_.ToString() }
    exit 1
}

Emit-RunStarted -RunId "init" -RequirementId "" -ProjectPath $ProjectPath
Emit-Log -Level "info" -Message "Felix Agent starting for: $ProjectPath" -Component "agent"

# Get project paths and validate structure
$paths = Get-ProjectPaths -ProjectPath $ProjectPath
if (-not (Test-ProjectStructure -Paths $paths)) {
    exit 1
}

# Extract paths for convenience
$SpecsDir = $paths.SpecsDir
$FelixDir = $paths.FelixDir
$RunsDir = $paths.RunsDir
$AgentsFile = $paths.AgentsFile
$ConfigFile = $paths.ConfigFile
$StateFile = $paths.StateFile
$RequirementsFile = $paths.RequirementsFile
$PromptsDir = $paths.PromptsDir

Emit-Log -Level "debug" -Message "StateFile: $StateFile" -Component "init"
Emit-Log -Level "debug" -Message "RequirementsFile: $RequirementsFile" -Component "init"

# Load configuration
$config = Get-FelixConfig -ConfigFile $ConfigFile
if (-not $config) {
    exit 1
}

$maxIterations = $config.executor.max_iterations
$defaultMode = $config.executor.default_mode

# Load agent configuration
$agentId = if ($config.agent -and $null -ne $config.agent.agent_id) { 
    $config.agent.agent_id 
}
else { 
    0  # Default to agent ID 0
}

$agentsData = Get-AgentsConfiguration
if (-not $agentsData) {
    exit 1
}

$agentConfig = Get-AgentConfig -AgentsData $agentsData -AgentId $agentId -ConfigFile $ConfigFile
if (-not $agentConfig) {
    exit 1
}

$agentName = $agentConfig.name
$script:agentName = $agentName
$script:agentId = $agentConfig.id
$script:agentConfig = $agentConfig

# ============================================================================
# Agent Registration and Heartbeat Functions
# ============================================================================

$script:BackendBaseUrl = "http://localhost:8080"
$script:HeartbeatJob = $null

# No wrappers needed - call module functions directly with all parameters

# Resolve python upfront (hard stop if unavailable)
try {
    $null = Resolve-PythonCommand -Config $config
}
catch {
    Emit-Error -ErrorType "PythonResolutionFailed" -Message "Python resolution failed: $_" -Severity "fatal"
    exit 1
}

# Initialize plugin state
Initialize-PluginState

# Load requirements and select current requirement
$currentReq = Get-CurrentRequirement -RequirementsFile $RequirementsFile -RequirementId $RequirementId -StateFile $StateFile
if (-not $currentReq) {
    exit 0
}

$RequirementId = $currentReq.id

# Load or initialize execution state
$state = Initialize-ExecutionState -StateFile $StateFile

# Initialize state machine for this execution
$agentState = New-AgentState -InitialMode "Planning"
$agentState.RequirementId = $RequirementId
Emit-Log -Level "debug" -Message "Initialized in Planning mode for requirement $RequirementId" -Component "state-machine"

# Reset validation retry counter if we're starting a new requirement
$state = Initialize-StateForRequirement -State $state -Requirement $currentReq

# Register agent with backend
$registrationSucceeded = Register-Agent -AgentId $agentConfig.id -AgentName $agentName -ProcessId $PID -Hostname $env:COMPUTERNAME -BackendBaseUrl $script:BackendBaseUrl
if ($registrationSucceeded) {
    $script:HeartbeatJob = Start-HeartbeatJob -AgentId $agentConfig.id -BackendBaseUrl $script:BackendBaseUrl
}

# Main iteration loop
for ($iteration = 1; $iteration -le $maxIterations; $iteration++) {
    $result = Invoke-FelixIteration `
        -Iteration $iteration `
        -MaxIterations $maxIterations `
        -CurrentRequirement $currentReq `
        -State $state `
        -Config $config `
        -AgentConfig $agentConfig `
        -AgentState $agentState `
        -Paths $paths `
        -NoCommit:$NoCommit
    
    if (-not $result.Continue) {
        Exit-FelixAgent -ExitCode $result.ExitCode -ProjectPath $ProjectPath -AgentId $agentConfig.id -HeartbeatJob $script:HeartbeatJob
    }
}

# Max iterations reached
Emit-Log -Level "warn" -Message "Reached max iterations ($maxIterations)" -Component "agent"
$state.status = "incomplete"
$state.updated_at = Get-Date -Format "o"
$state | ConvertTo-Json | Set-Content $StateFile
Exit-FelixAgent -ExitCode 0 -ProjectPath $ProjectPath -AgentId $agentConfig.id -HeartbeatJob $script:HeartbeatJob

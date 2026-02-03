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
. "$PSScriptRoot/felix/core/compat-utils.ps1"
. "$PSScriptRoot/felix/core/agent-state.ps1"
. "$PSScriptRoot/felix/core/git-manager.ps1"
. "$PSScriptRoot/felix/core/state-manager.ps1"
. "$PSScriptRoot/felix/core/plugin-manager.ps1"
. "$PSScriptRoot/felix/core/validator.ps1"
. "$PSScriptRoot/felix/core/workflow.ps1"
. "$PSScriptRoot/felix/core/agent-registration.ps1"
. "$PSScriptRoot/felix/core/guardrails.ps1"
. "$PSScriptRoot/felix/core/python-utils.ps1"
. "$PSScriptRoot/felix/core/requirements-utils.ps1"
. "$PSScriptRoot/felix/core/exit-handler.ps1"
. "$PSScriptRoot/felix/core/config-loader.ps1"
. "$PSScriptRoot/felix/core/initialization.ps1"
. "$PSScriptRoot/felix/core/executor.ps1"

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
    Write-Host "ERROR: Invalid project path: $ProjectPath" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Felix Agent starting for: " -NoNewline
Write-Host $ProjectPath -ForegroundColor Cyan

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

Write-Host "[DEBUG] StateFile: $StateFile" -ForegroundColor DarkGray
Write-Host "[DEBUG] RequirementsFile: $RequirementsFile" -ForegroundColor DarkGray

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

# Exit-FelixAgent: Now in felix/core/exit-handler.ps1
# Wrapper provides backward compatibility with script-scoped variables
function Exit-FelixAgent {
    param([int]$ExitCode = 0)
    Exit-FelixAgent -ExitCode $ExitCode -ProjectPath $script:ProjectPath -AgentId $script:agentId -HeartbeatJob $script:HeartbeatJob
}

# Resolve python upfront (hard stop if unavailable)
try {
    $null = Resolve-PythonCommand -Config $config
}
catch {
    Write-Host "[VALIDATION] " -NoNewline -ForegroundColor Magenta
    Write-Host "❌ Python resolution failed: $_" -ForegroundColor Red
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
Write-Host "[STATE-MACHINE] Initialized in Planning mode for requirement $RequirementId" -ForegroundColor DarkGray

# Reset validation retry counter if we're starting a new requirement
$state = Initialize-StateForRequirement -State $state -Requirement $currentReq

# Register agent with backend
$registrationSucceeded = Register-Agent -AgentId $agentConfig.id -AgentName $agentName -ProcessId $PID -Hostname $env:COMPUTERNAME
if ($registrationSucceeded) {
    Start-HeartbeatJob -AgentId $agentConfig.id -BaseUrl $script:BackendBaseUrl
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
        Exit-FelixAgent -ExitCode $result.ExitCode
    }
}

# Max iterations reached
Write-Host ""
Write-Host "[WARNING] Reached max iterations ($maxIterations)"
$state.status = "incomplete"
$state.updated_at = Get-Date -Format "o"
$state | ConvertTo-Json | Set-Content $StateFile
Exit-FelixAgent -ExitCode 0

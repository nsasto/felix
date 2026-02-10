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
    [string]$InitialPrompt = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$SpecBuildMode,
    
    [Parameter(Mandatory = $false)]
    [switch]$QuickMode,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoCommit,   # Use this flag for testing to prevent git commits
    
    [Parameter(Mandatory = $false)]
    [switch]$VerboseMode
)

$ErrorActionPreference = "Stop"

# Load core modules
try {
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
}
catch {
    Write-Host "FATAL: Failed to load module: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

# Suppress NDJSON events for interactive spec-builder mode
# Must happen before any Emit-* calls to prevent JSON clutter in console
if ($SpecBuildMode) {
    $isInteractive = [Console]::IsInputRedirected -eq $false -and [Environment]::UserInteractive
    if ($isInteractive) {
        $script:SuppressEventEmission = $true
    }
}

# Configure UTF-8 encoding for console output
# Must be done in this specific order for Windows PowerShell compatibility
# Skip console operations when running in non-interactive/redirected mode
try {
    chcp 65001 | Out-Null
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    # Ignore errors when no console available
}
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

$initReqId = if ($RequirementId) { $RequirementId } else { "" }
Emit-RunStarted -RunId "init" -RequirementId $initReqId -ProjectPath $ProjectPath
Emit-Log -Level "info" -Message "Felix Agent starting for: $ProjectPath" -Component "agent"

# Get project paths and validate structure
$paths = Get-ProjectPaths -ProjectPath $ProjectPath
if (-not (Test-ProjectStructure -Paths $paths)) {
    exit 1
}

function Acquire-FelixRunLock {
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $false)][string]$RequirementId,
        [Parameter(Mandatory = $false)][switch]$Interactive
    )

    # Back-compat safety: if other felix-agent processes are already running for this repo,
    # refuse to start even if no lock file exists (older processes won't have created one).
    try {
        $projectPathStr = [string]$ProjectPath
        $escaped = [regex]::Escape($projectPathStr)
        $candidates = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'felix-agent\.ps1' -and $_.CommandLine -match $escaped } |
        Select-Object -ExpandProperty ProcessId

        # Verify each candidate is actually still running (not zombie/exiting)
        $others = @()
        foreach ($pid in $candidates) {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                $others += $pid
            }
        }

        if ($others.Count -gt 0) {
            $pidsStr = $others -join ', '
            
            if ($Interactive) {
                Write-Host "`n⚠️  Another Felix agent is already running!" -ForegroundColor Yellow
                Write-Host "   Process ID(s): $pidsStr" -ForegroundColor Cyan
                Write-Host ""
                $response = Read-Host "Kill the existing process and continue? (y/n)"
                
                if ($response -eq 'y' -or $response -eq 'Y') {
                    foreach ($pid in $others) {
                        try {
                            Write-Host "Killing process $pid..." -ForegroundColor Yellow
                            Stop-Process -Id $pid -Force -ErrorAction Stop
                            Start-Sleep -Milliseconds 500
                        }
                        catch {
                            Write-Host "Failed to kill process $pid`: $_" -ForegroundColor Red
                        }
                    }
                    
                    # Try to remove stale lock file
                    try {
                        if (Test-Path -LiteralPath $LockPath) {
                            Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 200
                        }
                    }
                    catch { }
                    
                    # Don't return null, let it retry the lock acquisition below
                }
                else {
                    Write-Host "Cancelled by user." -ForegroundColor Gray
                    return $null
                }
            }
            else {
                Emit-Error -ErrorType "FelixRunAlreadyInProgress" -Message "Another Felix run is already active for this repo (PIDs: $pidsStr). Stop it before starting a new run." -Severity "fatal" -Context @{
                    lock_path = $LockPath
                    pids      = @($others)
                }
                return $null
            }
        }
    }
    catch { }

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            $handle = [System.IO.FileStream]::new(
                $LockPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::ReadWrite  # Allow others to read lock info while we hold it
            )

            $lockInfo = @{
                pid            = $PID
                project_path   = [string]$ProjectPath
                requirement_id = if ($RequirementId) { [string]$RequirementId } else { "" }
                started_at     = (Get-Date).ToUniversalTime().ToString("o")
            }

            $json = $lockInfo | ConvertTo-Json -Compress -Depth 5
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            $bytes = $utf8NoBom.GetBytes($json)
            $handle.Write($bytes, 0, $bytes.Length)
            $handle.Flush()

            return $handle
        }
        catch {
            if (-not (Test-Path -LiteralPath $LockPath)) {
                throw
            }

            # Existing lock: check whether it's stale
            $existing = $null
            try {
                # Open with FileShare.ReadWrite to read while lock holder keeps file open
                $fileStream = [System.IO.FileStream]::new(
                    $LockPath,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite
                )
                $reader = [System.IO.StreamReader]::new($fileStream)
                $raw = $reader.ReadToEnd()
                $reader.Close()
                $fileStream.Close()
                
                if ($raw) { $existing = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue }
            }
            catch { }

            $existingPid = $null
            try {
                if ($existing -and $existing.pid) { $existingPid = [int]$existing.pid }
            }
            catch { }

            $isRunning = $false
            if ($existingPid) {
                $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
                if ($proc) { $isRunning = $true }
            }

            Emit-Log -Level "debug" -Message "Lock check: existingPid=$existingPid isRunning=$isRunning Interactive=$Interactive" -Component "lock"

            if ($isRunning) {
                if ($Interactive) {
                    Write-Host "`n⚠️  Another Felix agent is already running!" -ForegroundColor Yellow
                    Write-Host "   Process ID: $existingPid" -ForegroundColor Cyan
                    if ($existing.requirement_id) {
                        Write-Host "   Working on: $($existing.requirement_id)" -ForegroundColor Cyan
                    }
                    Write-Host ""
                    $response = Read-Host "Kill the existing process and continue? (y/n)"
                    
                    if ($response -eq 'y' -or $response -eq 'Y') {
                        try {
                            Write-Host "Killing process $existingPid..." -ForegroundColor Yellow
                            Stop-Process -Id $existingPid -Force -ErrorAction Stop
                            Start-Sleep -Milliseconds 500
                            
                            # Remove the stale lock file
                            try {
                                Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
                                Start-Sleep -Milliseconds 200
                            }
                            catch { }
                            
                            # Retry - don't return null, let it fall through to the retry logic
                        }
                        catch {
                            Write-Host "Failed to kill process $existingPid`: $_" -ForegroundColor Red
                            return $null
                        }
                    }
                    else {
                        Write-Host "Cancelled by user." -ForegroundColor Gray
                        return $null
                    }
                }
                else {
                    # Try to find the session ID for this PID
                    $sessionId = $null
                    $felixDir = Join-Path $ProjectPath ".felix"
                    $sessionsFile = Join-Path $felixDir "sessions.json"
                    if (Test-Path $sessionsFile) {
                        try {
                            $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
                            $matchingSession = $sessions | Where-Object { $_.pid -eq $existingPid } | Select-Object -First 1
                            if ($matchingSession) {
                                $sessionId = $matchingSession.session_id
                            }
                        }
                        catch { }
                    }
                    
                    $reqInfo = if ($existing -and $existing.requirement_id) { " (working on: $($existing.requirement_id))" } else { "" }
                    $killMsg = "To kill the blocking process, run:`n  Stop-Process -Id $existingPid -Force`n  Remove-Item '$LockPath' -Force"
                    if ($sessionId) {
                        $killMsg += "`n`nOr use Felix's session manager:`n  felix procs kill $sessionId"
                    }
                    
                    Emit-Error -ErrorType "FelixRunAlreadyInProgress" -Message "Another Felix run is already active for this repo$reqInfo`n`n$killMsg" -Severity "fatal" -Context @{
                        lock_path      = $LockPath
                        existing_pid   = $existingPid
                        existing_reqid = if ($existing -and $existing.requirement_id) { [string]$existing.requirement_id } else { "" }
                        session_id     = if ($sessionId) { $sessionId } else { "" }
                    }
                    # Give time for event to flush before exit
                    Start-Sleep -Milliseconds 100
                    return $null
                }
            }

            # Stale lock: remove and retry once
            try {
                Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }
    }

    return $null
}

function Release-FelixRunLock {
    param(
        [Parameter(Mandatory = $false)]$LockHandle,
        [Parameter(Mandatory = $true)][string]$LockPath
    )

    try {
        if ($LockHandle) { $LockHandle.Dispose() }
    }
    catch { }

    try {
        if (Test-Path -LiteralPath $LockPath) {
            Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

$lockPath = Join-Path $paths.FelixDir "run.lock"

# Enable interactive lock resolution ONLY for SpecBuildMode
# (felix-cli spawns with redirected stdout/stderr but NOT stdin, so IsInputRedirected returns false)
$enableInteractiveLock = $SpecBuildMode

$script:FelixRunLockHandle = Acquire-FelixRunLock -LockPath $lockPath -ProjectPath $ProjectPath -RequirementId $RequirementId -Interactive:$enableInteractiveLock
if (-not $script:FelixRunLockHandle) {
    exit 1
}

try {
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
    Emit-Log -Level "debug" -Message "Loading Felix config from $ConfigFile" -Component "init"
    $config = Get-FelixConfig -ConfigFile $ConfigFile
    if (-not $config) {
        Emit-Error -ErrorType "ConfigLoadFailed" -Message "Failed to load config" -Severity "fatal"
        exit 1
    }
    Emit-Log -Level "debug" -Message "Config loaded successfully" -Component "init"

    $maxIterations = $config.executor.max_iterations
    $defaultMode = $config.executor.default_mode

    # Load agent configuration
    $agentId = if ($config.agent -and $null -ne $config.agent.agent_id) { 
        $config.agent.agent_id 
    }
    else { 
        0  # Default to agent ID 0
    }
    Emit-Log -Level "debug" -Message "Using agent ID: $agentId" -Component "init"

    Emit-Log -Level "debug" -Message "Loading agents configuration" -Component "init"
    $agentsData = Get-AgentsConfiguration -AgentsJsonFile $paths.AgentsJsonFile
    if (-not $agentsData) {
        Emit-Error -ErrorType "AgentsDataLoadFailed" -Message "Failed to load agents.json" -Severity "fatal"
        exit 1
    }
    Emit-Log -Level "debug" -Message "Agents data loaded successfully" -Component "init"

    Emit-Log -Level "debug" -Message "Getting agent config for ID $agentId" -Component "init"
    $agentConfig = Get-AgentConfig -AgentsData $agentsData -AgentId $agentId -ConfigFile $ConfigFile
    if (-not $agentConfig) {
        Emit-Error -ErrorType "AgentConfigLoadFailed" -Message "Failed to load agent config for ID $agentId" -Severity "fatal"
        exit 1
    }
    Emit-Log -Level "debug" -Message "Agent config loaded: $($agentConfig.name)" -Component "init"

    $agentName = $agentConfig.name
    $script:agentName = $agentName
    $script:agentId = $agentConfig.id
    $script:agentConfig = $agentConfig

    # Show agent info for spec-builder mode (bypasses event suppression)
    if ($SpecBuildMode -and $script:SuppressEventEmission) {
        $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
        Write-Host "INFO" -NoNewline -ForegroundColor Cyan
        Write-Host " [agent] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Using agent: $($agentConfig.name) (ID: $($agentConfig.id))"
        
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
        Write-Host "INFO" -NoNewline -ForegroundColor Cyan
        Write-Host " [agent] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Executable: $($agentConfig.executable) $($agentConfig.args -join ' ')"
        Write-Host ""
    }

    # ============================================================================
    # Mode Selection: Spec Builder vs Normal Execution
    # ============================================================================

    if ($SpecBuildMode) {
        Emit-Log -Level "debug" -Message "Entering spec builder mode" -Component "init"
        # Spec builder flow - different path entirely
        . "$PSScriptRoot/core/spec-builder.ps1"
    
        Emit-Log -Level "debug" -Message "Calling Invoke-SpecBuilder with RequirementId=$RequirementId, QuickMode=$($QuickMode.IsPresent), VerboseMode=$($VerboseMode.IsPresent)" -Component "init"
        $result = Invoke-SpecBuilder `
            -RequirementId $RequirementId `
            -InitialPrompt $InitialPrompt `
            -QuickMode:$QuickMode `
            -VerboseMode:$VerboseMode `
            -Config $config `
            -AgentConfig $agentConfig `
            -Paths $paths
    
        Emit-Log -Level "debug" -Message "Invoke-SpecBuilder returned with exit code $($result.ExitCode)" -Component "init"
        Exit-FelixAgent -ExitCode $result.ExitCode -ProjectPath $ProjectPath -AgentId $agentConfig.id -HeartbeatJob $null
    }

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
    if (-not $currentReq -or -not $currentReq.id) {
        # Error already emitted by Get-CurrentRequirement (either RequirementNotFound or already complete)
        Emit-Error -ErrorType "NoRequirementAvailable" -Message "Cannot proceed: requirement '$RequirementId' is not available for execution" -Severity "fatal"
        [Console]::Out.Flush()  # Ensure error event is flushed before exit
        Start-Sleep -Milliseconds 100  # Brief delay to ensure output is captured
        exit 1
    }

    $RequirementId = $currentReq.id

    # Load or initialize execution state
    $state = Initialize-ExecutionState -StateFile $StateFile

    # Initialize state machine for this execution
    $agentState = New-AgentState -InitialMode "Planning"
    $agentState.RequirementId = $RequirementId
    Emit-Log -Level "debug" -Message "Initialized in Planning mode for requirement $RequirementId" -Component "state-machine"

    # Reset validation retry counter if we're starting a new requirement
    Emit-Log -Level "debug" -Message "About to call Initialize-StateForRequirement" -Component "init"
    $state = Initialize-StateForRequirement -State $state -Requirement $currentReq
    Emit-Log -Level "debug" -Message "Completed Initialize-StateForRequirement" -Component "init"

    # Register agent with backend
    Emit-Log -Level "debug" -Message "About to call Register-Agent" -Component "init"
    $registrationSucceeded = Register-Agent -AgentId $agentConfig.id -AgentName $agentName -ProcessId $PID -Hostname $env:COMPUTERNAME -BackendBaseUrl $script:BackendBaseUrl
    Emit-Log -Level "debug" -Message "Completed Register-Agent, success=$registrationSucceeded" -Component "init"
    if ($registrationSucceeded) {
        Emit-Log -Level "debug" -Message "Starting heartbeat job" -Component "init"
        $script:HeartbeatJob = Start-HeartbeatJob -AgentId $agentConfig.id -BackendBaseUrl $script:BackendBaseUrl
        Emit-Log -Level "debug" -Message "Heartbeat job started" -Component "init"
    }

    Emit-Log -Level "debug" -Message "About to enter main iteration loop (max: $maxIterations)" -Component "init"
    # Main iteration loop
    for ($iteration = 1; $iteration -le $maxIterations; $iteration++) {
        Emit-Log -Level "debug" -Message "Starting iteration $iteration of $maxIterations" -Component "executor"
        $result = Invoke-FelixIteration `
            -Iteration $iteration `
            -MaxIterations $maxIterations `
            -CurrentRequirement $currentReq `
            -State $state `
            -Config $config `
            -AgentConfig $agentConfig `
            -AgentState $agentState `
            -Paths $paths `
            -NoCommit:$NoCommit `
            -VerboseMode:$VerboseMode
    
        if (-not $result.Continue) {
            Exit-FelixAgent -ExitCode $result.ExitCode -ProjectPath $ProjectPath -AgentId $agentConfig.id -BackendBaseUrl $script:BackendBaseUrl -HeartbeatJob $script:HeartbeatJob
        }
    }

    # Max iterations reached
    Emit-Log -Level "warn" -Message "Reached max iterations ($maxIterations)" -Component "agent"
    $state.status = "incomplete"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    Exit-FelixAgent -ExitCode 0 -ProjectPath $ProjectPath -AgentId $agentConfig.id -BackendBaseUrl $script:BackendBaseUrl -HeartbeatJob $script:HeartbeatJob
}
finally {
    Release-FelixRunLock -LockHandle $script:FelixRunLockHandle -LockPath $lockPath
}

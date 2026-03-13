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

# $FelixEngineRoot: where core/, plugins/, commands/ live.
# When invoked via the C# runner after global install, FELIX_INSTALL_DIR points to the
# extracted engine dir. When called directly (dev / PS-only), fall back to $PSScriptRoot.
$FelixEngineRoot = if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { $PSScriptRoot }

# Load .env files so environment-based config (FELIX_SYNC_KEY, etc.) is always available
# regardless of how this script was invoked. Only sets vars not already in the environment.
foreach ($envFile in @("$ProjectPath\.env", "$ProjectPath\.felix\.env")) {
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -eq '' -or $line.StartsWith('#')) { return }
            $idx = $line.IndexOf('=')
            if ($idx -le 0) { return }
            $key = $line.Substring(0, $idx).Trim()
            $val = $line.Substring($idx + 1).Trim()
            if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
                ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
            }
        }
    }
}


try {
    . "$FelixEngineRoot/core/emit-event.ps1"
    . "$FelixEngineRoot/core/compat-utils.ps1"
    . "$FelixEngineRoot/core/text-utils.ps1"
    . "$FelixEngineRoot/core/agent-state.ps1"
    . "$FelixEngineRoot/core/git-manager.ps1"
    . "$FelixEngineRoot/core/state-manager.ps1"
    . "$FelixEngineRoot/core/plugin-manager.ps1"
    . "$FelixEngineRoot/core/validator.ps1"
    . "$FelixEngineRoot/core/workflow.ps1"
    . "$FelixEngineRoot/core/agent-registration.ps1"
    . "$FelixEngineRoot/core/guardrails.ps1"
    . "$FelixEngineRoot/core/python-utils.ps1"
    . "$FelixEngineRoot/core/requirements-utils.ps1"
    . "$FelixEngineRoot/core/exit-handler.ps1"
    . "$FelixEngineRoot/core/setup-utils.ps1"
    . "$FelixEngineRoot/core/config-loader.ps1"
    . "$FelixEngineRoot/core/initialization.ps1"
    . "$FelixEngineRoot/core/executor.ps1"
    . "$FelixEngineRoot/core/sync-interface.ps1"
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

function Lock-FelixRun {
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
        foreach ($processId in $candidates) {
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($proc) {
                $others += $processId
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
                    foreach ($processId in $others) {
                        try {
                            Write-Host "Killing process $processId..." -ForegroundColor Yellow
                            Stop-Process -Id $processId -Force -ErrorAction Stop
                            Start-Sleep -Milliseconds 500
                        }
                        catch {
                            Write-Host "Failed to kill process $processId`: $_" -ForegroundColor Red
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

function Unlock-FelixRun {
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

$script:FelixRunLockHandle = Lock-FelixRun -LockPath $lockPath -ProjectPath $ProjectPath -RequirementId $RequirementId -Interactive:$enableInteractiveLock
if (-not $script:FelixRunLockHandle) {
    exit 1
}

try {
    # Extract paths for convenience
    $FelixDir = $paths.FelixDir
    $ConfigFile = $paths.ConfigFile
    $StateFile = $paths.StateFile
    $RequirementsFile = $paths.RequirementsFile

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

    # Load agent configuration
    $agentId = if ($config.agent -and $null -ne $config.agent.agent_id) { 
        $config.agent.agent_id 
    }
    else { 
        "39535ce5-e344-5a8c-9f3f-44776b998939"  # Default to droid agent UUID
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
    $script:agentConfig = $agentConfig

    $provider = if ($agentConfig.adapter) { $agentConfig.adapter } else { $agentConfig.name }
    $model = if ($agentConfig.model) { $agentConfig.model } else { "" }
    # Runtime settings (executable/working_directory/environment filled in by Get-AgentDefaults)
    $agentSettings = @{}
    if ($agentConfig.executable) { $agentSettings["executable"] = $agentConfig.executable }
    if ($agentConfig.working_directory) { $agentSettings["working_directory"] = $agentConfig.working_directory }
    if ($agentConfig.environment) { $agentSettings["environment"] = $agentConfig.environment }

    # Derive the canonical agent key and full registration payload in one call.
    # Key + payload reuse the same object — no second compute needed.
    $agentPayload = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $ProjectPath -Source "felix-agent"
    $script:agentKey = $agentPayload.key
    $script:agentId = $script:agentKey
    $agentConfig | Add-Member -NotePropertyName key -NotePropertyValue $script:agentKey -Force

    # Initialize sync reporter
    Emit-Log -Level "debug" -Message "Initializing sync reporter" -Component "init"
    $script:SyncReporter = Get-RunReporter -FelixDir $FelixDir
    Emit-Log -Level "debug" -Message "Sync reporter type: $($script:SyncReporter.GetType().Name)" -Component "init"

    # Show sync status to user
    $isSyncEnabled = $script:SyncReporter.GetType().Name -ne "NoOpReporter"
    if ($isSyncEnabled) {
        $syncUrl = $script:SyncReporter.BaseUrl
        Emit-Log -Level "info" -Message "Sync enabled -> $syncUrl" -Component "sync"
    }

    # Register agent with sync service (non-blocking, best-effort)
    if ($isSyncEnabled) {
        $syncAgentInfo = $agentPayload

        if ($env:FELIX_SKIP_REGISTER -eq "true") {
            # Loop pre-registered this agent — skip redundant registration, just start heartbeat
            Emit-Log -Level "debug" -Message "Agent registration skipped (pre-registered by loop)" -Component "sync"
        }
        else {
            try {
                Emit-Log -Level "debug" -Message "Starting agent registration..." -Component "sync"

                if (-not $syncAgentInfo.ContainsKey("git_url")) {
                    Emit-Log -Level "warn" -Message "No git URL available - agent registration may fail with API key auth" -Component "sync"
                }

                $registered = $script:SyncReporter.RegisterAgent($syncAgentInfo)
                if (-not $registered.Success) {
                    $errDetail = if ($registered.Error) { " ($($registered.Error))" } else { "" }
                    Emit-Log -Level "error" -Message "Backend unreachable - cannot start sync run$errDetail. Check backend URL and connectivity, or disable sync in .felix/config.json." -Component "sync"
                    exit 1
                }
                Emit-Log -Level "debug" -Message "Agent registered with backend" -Component "sync"
            }
            catch {
                # Handle registration failures gracefully - show error but continue execution
                $errorMsg = $_.Exception.Message
                Emit-Log -Level "error" -Message "Agent registration failed: $errorMsg" -Component "sync"

                # Show prominent warning to user
                Write-Host ""
                Write-Host "WARNING: Agent registration failed" -ForegroundColor Yellow
                Write-Host "  Error: $errorMsg" -ForegroundColor Yellow
                Write-Host "  Continuing without sync - runs will be local only" -ForegroundColor Yellow
                Write-Host ""
            }
        }

        # Start heartbeat job — always when sync is active, whether we registered or skipped.
        # Heartbeat is per-run liveness; the loop orchestrator runs in a separate process.
        $script:HeartbeatApiKey = $script:SyncReporter.ApiKey
        $script:HeartbeatBaseUrl = $script:SyncReporter.BaseUrl
        $gitUrlForHeartbeat = if ($syncAgentInfo.ContainsKey("git_url")) { $syncAgentInfo["git_url"] } else { "" }
        $script:HeartbeatJob = Start-HeartbeatJob `
            -AgentId $script:agentKey `
            -BackendBaseUrl $script:HeartbeatBaseUrl `
            -ApiKey $script:HeartbeatApiKey `
            -GitUrl $gitUrlForHeartbeat
    }

    # Show agent info for spec-builder mode (bypasses event suppression)
    if ($SpecBuildMode -and $script:SuppressEventEmission) {
        $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
        Write-Host "INFO" -NoNewline -ForegroundColor Cyan
        Write-Host " [agent] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Using agent: $($agentConfig.name) (Key: $($agentConfig.key))"
        
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
        Write-Host "INFO" -NoNewline -ForegroundColor Cyan
        Write-Host " [agent] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Executable: $($agentConfig.executable)"
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
        Exit-FelixAgent -ExitCode $result.ExitCode -ProjectPath $ProjectPath -AgentId $script:agentKey -HeartbeatJob $null
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
    $currentReq = Get-CurrentRequirement -RequirementsFile $RequirementsFile -RequirementId $RequirementId -StateFile $StateFile -TrustServerStatus:$isSyncEnabled
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

    # Agent registration handled by sync reporter above
    # Heartbeat job started after successful registration (every 15s to /api/agents/{id}/heartbeat)

    # Notify server that agent is actively starting work (reserved -> in_progress)
    if ($isSyncEnabled -and $RequirementId) {
        try {
            $syncBaseUrl = if ($env:FELIX_SYNC_URL) { $env:FELIX_SYNC_URL } else { $config.sync.base_url }
            $syncApiKey = if ($env:FELIX_SYNC_KEY) { $env:FELIX_SYNC_KEY } else { $config.sync.api_key }
            $startHeaders = @{ "Content-Type" = "application/json" }
            if ($syncApiKey) { $startHeaders["Authorization"] = "Bearer $syncApiKey" }
            $startBody = @{ code = $RequirementId } | ConvertTo-Json
            Invoke-RestMethod -Uri "$($syncBaseUrl.TrimEnd('/'))/api/sync/work/start" -Method POST -Headers $startHeaders -Body $startBody -ErrorAction Stop | Out-Null
            Emit-Log -Level "info" -Message "$RequirementId transitioned to in_progress on server" -Component "sync"
        }
        catch {
            # Non-fatal: agent proceeds even if server is unavailable or item is already in_progress
            Emit-Log -Level "warn" -Message "Could not mark $RequirementId in_progress on server: $_" -Component "sync"
        }
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
            # Build run context for OnRunComplete hook
            $runContext = @{
                Requirement = $currentReq
                Iteration   = $iteration
                Paths       = $paths
                Config      = $config
                AgentConfig = $agentConfig
            }
            Emit-Log -Level "debug" -Message "Exiting agent loop: ExitCode=$($result.ExitCode), Continue=$($result.Continue)" -Component "agent"
            Exit-FelixAgent -ExitCode $result.ExitCode -ProjectPath $ProjectPath -AgentId $script:agentKey -HeartbeatJob $script:HeartbeatJob -RunContext $runContext
        }
    }

    # Max iterations reached
    Emit-Log -Level "warn" -Message "Reached max iterations ($maxIterations)" -Component "agent"
    Write-Host "[AGENT-LOOP] Max iterations reached, exiting with code 0" -ForegroundColor Yellow
    $state.status = "incomplete"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    
    # Build run context for OnRunComplete hook
    $currentReq.status = "incomplete"
    $runContext = @{
        Requirement = $currentReq
        Iteration   = $maxIterations
        Paths       = $paths
        Config      = $config
        AgentConfig = $agentConfig
    }
    Exit-FelixAgent -ExitCode 0 -ProjectPath $ProjectPath -AgentId $script:agentKey -HeartbeatJob $script:HeartbeatJob -RunContext $runContext
}
finally {
    Unlock-FelixRun -LockHandle $script:FelixRunLockHandle -LockPath $lockPath
}

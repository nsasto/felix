<#
.SYNOPSIS
Initialization logic for Felix agent execution

.DESCRIPTION
Handles state loading, requirement selection, agent registration,
and setup of the execution environment.
#>

function Initialize-ExecutionState {
    <#
    .SYNOPSIS
    Loads or initializes the execution state from state.json
    
    .PARAMETER StateFile
    Path to state.json
    
    .OUTPUTS
    Hashtable containing execution state
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StateFile
    )
    
    if (-not (Test-Path $StateFile)) {
        return @{
            current_requirement_id = $null
            current_iteration      = 0
            last_mode              = $null
            status                 = "idle"
            validation_retry_count = 0
        }
    }
    
    try {
        $rawContent = Get-Content $StateFile -Raw
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            Write-Host "[WARNING] State file is empty, initializing new state" -ForegroundColor Yellow
            return @{
                current_requirement_id = $null
                current_iteration      = 0
                last_mode              = $null
                status                 = "idle"
                validation_retry_count = 0
            }
        }
        
        $loadedState = $rawContent | ConvertFrom-Json
        if ($null -eq $loadedState) {
            Write-Host "[WARNING] State file loaded but resulted in null, initializing new state" -ForegroundColor Yellow
            return @{
                current_requirement_id = $null
                current_iteration      = 0
                last_mode              = $null
                status                 = "idle"
                validation_retry_count = 0
            }
        }
        
        # Convert PSCustomObject to hashtable for mutability
        # Requires ConvertTo-Hashtable from exit-handler.ps1
        $converted = ConvertTo-Hashtable $loadedState
        if ($null -eq $converted) {
            Write-Host "[WARNING] Conversion to hashtable failed, initializing new state" -ForegroundColor Yellow
            return @{
                current_requirement_id = $null
                current_iteration      = 0
                last_mode              = $null
                status                 = "idle"
                validation_retry_count = 0
            }
        }
        
        return $converted
    }
    catch {
        Write-Host "[WARNING] Failed to load state file: $_" -ForegroundColor Yellow
        Write-Host "[WARNING] Initializing new state" -ForegroundColor Yellow
        return @{
            current_requirement_id = $null
            current_iteration      = 0
            last_mode              = $null
            status                 = "idle"
            validation_retry_count = 0
        }
    }
}

function Get-CurrentRequirement {
    <#
    .SYNOPSIS
    Finds the requirement to work on
    
    .PARAMETER RequirementsFile
    Path to requirements.json
    
    .PARAMETER RequirementId
    Specific requirement ID (optional)
    
    .PARAMETER StateFile
    Path to state.json for cleanup if requirement already complete
    
    .OUTPUTS
    PSCustomObject of the requirement to work on, or $null
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFile,
        
        [Parameter(Mandatory = $false)]
        [string]$RequirementId = $null,
        
        [Parameter(Mandatory = $false)]
        [string]$StateFile = $null
    )
    
    if (-not (Test-Path $RequirementsFile)) {
        Write-Host "ERROR: Requirements file not found: $RequirementsFile" -ForegroundColor Red
        return $null
    }
    
    try {
        Write-Host "[DEBUG] Loading requirements from: $RequirementsFile" -ForegroundColor DarkGray
        $requirements = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        Write-Host "[DEBUG] Total requirements loaded: $($requirements.requirements.Count)" -ForegroundColor DarkGray
        
        $currentReq = $null
        
        if ($RequirementId) {
            $currentReq = $requirements.requirements | Where-Object { $_.id -eq $RequirementId }
            if (-not $currentReq) {
                Write-Host "ERROR: Requirement $RequirementId not found." -ForegroundColor Red
                return $null
            }
            
            Write-Host "[DEBUG] Found requirement: $($currentReq.id) - $($currentReq.title)" -ForegroundColor DarkGray
            Write-Host "[DEBUG] Status: $($currentReq.status)" -ForegroundColor DarkGray
            
            # Check if requirement is already complete
            if ($currentReq.status -in @("complete", "done")) {
                Write-Host "Requirement $RequirementId is already $($currentReq.status) - nothing to do." -ForegroundColor Green
                
                # Clean up stale state if needed
                if ($StateFile -and (Test-Path $StateFile)) {
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
                return $null
            }
        }
        else {
            # Find first planned or in_progress requirement
            $currentReq = $requirements.requirements | Where-Object { $_.status -eq "planned" -or $_.status -eq "in_progress" } | Select-Object -First 1
            if (-not $currentReq) {
                Write-Host "No planned or in-progress requirements found." -ForegroundColor Green
                return $null
            }
        }
        
        return $currentReq
    }
    catch {
        Write-Host "ERROR: Failed to load requirements: $_" -ForegroundColor Red
        return $null
    }
}

function Initialize-StateForRequirement {
    <#
    .SYNOPSIS
    Resets state counters when starting a new requirement
    
    .PARAMETER State
    Current execution state hashtable
    
    .PARAMETER Requirement
    Requirement being worked on
    
    .OUTPUTS
    Updated state hashtable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        $Requirement
    )
    
    # Initialize validation retry counter if it doesn't exist
    if (-not $State.ContainsKey('validation_retry_count')) {
        $State.validation_retry_count = 0
    }
    
    # Reset validation retry counter if we're starting a new requirement
    if ($State.current_requirement_id -ne $Requirement.id) {
        $State.validation_retry_count = 0
        $State.current_requirement_id = $Requirement.id
        $State.current_iteration = 0
        $State.status = "ready"
        $State.last_iteration_outcome = $null
        $State.blocked_task = $null
        Write-Host "[STATE] Starting new requirement, reset all state counters" -ForegroundColor Cyan
    }
    
    return $State
}

function Initialize-PluginState {
    <#
    .SYNOPSIS
    Initializes script-scoped plugin state variables
    
    .OUTPUTS
    None (sets script-scoped variables)
    #>
    
    # Clear any cached plugin state from previous runs
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
}

function Register-FelixAgent {
    <#
    .SYNOPSIS
    Registers agent with backend and starts heartbeat
    
    .PARAMETER AgentConfig
    Agent configuration object
    
    .PARAMETER BackendBaseUrl
    Base URL for backend API
    
    .PARAMETER HeartbeatJobVar
    Script-scoped variable name for storing heartbeat job (e.g., 'HeartbeatJob')
    
    .OUTPUTS
    Boolean indicating registration success
    #>
    param(
        [Parameter(Mandatory = $true)]
        $AgentConfig,
        
        [Parameter(Mandatory = $true)]
        [string]$BackendBaseUrl,
        
        [Parameter(Mandatory = $false)]
        [string]$HeartbeatJobVar = 'HeartbeatJob'
    )
    
    # Register with the backend (best-effort)
    # Note: Requires Register-Agent from agent-registration.ps1
    $registrationSucceeded = Register-Agent -AgentId $AgentConfig.id -AgentName $AgentConfig.name -ProcessId $PID -Hostname $env:COMPUTERNAME -BackendBaseUrl $BackendBaseUrl
    
    # Start heartbeat background job if registration succeeded
    if ($registrationSucceeded) {
        # Note: Requires Start-HeartbeatJob from agent-registration.ps1
        $heartbeatJob = Start-HeartbeatJob -AgentId $AgentConfig.id -BackendBaseUrl $BackendBaseUrl
        Set-Variable -Name $HeartbeatJobVar -Value $heartbeatJob -Scope Script
    }
    
    return $registrationSucceeded
}

Export-ModuleMember -Function Initialize-ExecutionState, Get-CurrentRequirement, Initialize-StateForRequirement, Initialize-PluginState, Register-FelixAgent

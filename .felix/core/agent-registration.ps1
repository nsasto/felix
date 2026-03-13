<#
.SYNOPSIS
Agent registration and heartbeat management for Felix backend communication

.DESCRIPTION
Provides functions to register agents with the backend API, send heartbeats,
and manage background heartbeat jobs. All operations are best-effort and
fail gracefully if backend is unavailable.
#>

function Register-Agent {
    <#
    .SYNOPSIS
    Registers the agent with the backend API
    
    .PARAMETER AgentId
    Unique agent identifier
    
    .PARAMETER AgentName
    Human-readable agent name
    
    .PARAMETER ProcessId
    Process ID of the agent
    
    .PARAMETER Hostname
    Hostname where the agent is running
    
    .PARAMETER BackendBaseUrl
    Base URL of the backend API
    
    .OUTPUTS
    Boolean indicating success or failure
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentId,
        
        [Parameter(Mandatory = $true)]
        [string]$AgentName,
        
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $true)]
        [string]$Hostname,
        
        [Parameter(Mandatory = $true)]
        [string]$BackendBaseUrl
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
        $null = Invoke-RestMethod -Method POST `
            -Uri "$BackendBaseUrl/api/agents/register" `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        Emit-Log -Level "info" -Message "Registered as agent ID $AgentId ('$AgentName', PID: $ProcessId)" -Component "agent"
        return $true
    }
    catch {
        # Registration is best-effort - don't fail if backend is unreachable
        Emit-Log -Level "warn" -Message "Registration failed (backend may be unavailable): $_" -Component "agent"
        return $false
    }
}

function Send-AgentHeartbeat {
    <#
    .SYNOPSIS
    Sends a heartbeat to the backend API
    
    .PARAMETER AgentId
    Unique agent identifier
    
    .PARAMETER CurrentRequirementId
    ID of the requirement currently being worked on
    
    .PARAMETER BackendBaseUrl
    Base URL of the backend API
    
    .OUTPUTS
    Boolean indicating success or failure
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentId,
        
        [Parameter(Mandatory = $false)]
        [string]$CurrentRequirementId,
        
        [Parameter(Mandatory = $true)]
        [string]$BackendBaseUrl
    )
    
    $heartbeat = @{
        current_run_id = $CurrentRequirementId
    }
    
    try {
        $body = $heartbeat | ConvertTo-Json
        Invoke-RestMethod -Method POST `
            -Uri "$BackendBaseUrl/api/agents/$AgentId/heartbeat" `
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
    Starts a background job that sends heartbeats every 15 seconds
    
    .PARAMETER AgentId
    Unique agent identifier
    
    .PARAMETER BackendBaseUrl
    Base URL of the backend API
    
    .PARAMETER ApiKey
    API key for authentication (Bearer token)
    
    .PARAMETER GitUrl
    Git remote URL for project validation
    
    .OUTPUTS
    Returns the PowerShell job object
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentId,
        
        [Parameter(Mandatory = $true)]
        [string]$BackendBaseUrl,

        [Parameter(Mandatory = $false)]
        [string]$ApiKey = "",

        [Parameter(Mandatory = $false)]
        [string]$GitUrl = ""
    )
    
    $job = Start-Job -Name "FelixHeartbeat" -ScriptBlock {
        param($AgentId, $BaseUrl, $ApiKey, $GitUrl)
        
        while ($true) {
            Start-Sleep -Seconds 15
            
            try {
                $headers = @{ "Content-Type" = "application/json" }
                if ($ApiKey) { $headers["Authorization"] = "Bearer $ApiKey" }

                $body = @{}
                if ($GitUrl) { $body["git_url"] = $GitUrl }

                Invoke-RestMethod -Method POST `
                    -Uri "$BaseUrl/api/agents/$AgentId/heartbeat" `
                    -Headers $headers `
                    -Body ($body | ConvertTo-Json) `
                    -ContentType "application/json" `
                    -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                # Silently continue on heartbeat failures
            }
        }
    } -ArgumentList $AgentId, $BackendBaseUrl, $ApiKey, $GitUrl
    
    Emit-Log -Level "debug" -Message "Started heartbeat job (every 15s)" -Component "agent" | Out-Null
    
    return $job
}

function Stop-HeartbeatJob {
    <#
    .SYNOPSIS
    Stops a background heartbeat job
    
    .PARAMETER Job
    The PowerShell job object to stop
    #>
    param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Job]$Job
    )
    
    if ($Job) {
        Stop-Job -Job $Job -ErrorAction SilentlyContinue
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    }
}

function Unregister-Agent {
    <#
    .SYNOPSIS
    Marks the agent as stopped in the registry
    
    .PARAMETER AgentId
    Unique agent identifier
    
    .PARAMETER BackendBaseUrl
    Base URL of the backend API
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentId,
        
        [Parameter(Mandatory = $true)]
        [string]$BackendBaseUrl
    )
    
    try {
        Invoke-RestMethod -Method POST `
            -Uri "$BackendBaseUrl/api/agents/$AgentId/stop" `
            -ContentType "application/json" `
            -ErrorAction Stop | Out-Null
        
        Emit-Log -Level "info" -Message "Agent ID $AgentId marked as stopped" -Component "agent"
    }
    catch {
        # Best-effort - don't fail on unregister errors
    }
}


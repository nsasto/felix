<#
.SYNOPSIS
Configuration loading and agent setup for Felix agent

.DESCRIPTION
Handles loading of configuration from config.json and agents.json, 
resolving agent configuration, and validating project structure.
#>

function Get-ProjectPaths {
    <#
    .SYNOPSIS
    Computes all standard Felix project paths
    
    .PARAMETER ProjectPath
    Absolute path to the project root
    
    .OUTPUTS
    Hashtable containing all project paths
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )
    
    return @{
        ProjectPath      = $ProjectPath
        SpecsDir         = Join-Path $ProjectPath "specs"
        FelixDir         = Join-Path $ProjectPath ".felix"
        RunsDir          = Join-Path $ProjectPath "runs"
        AgentsFile       = Join-Path $ProjectPath "AGENTS.md"
        AgentsJsonFile   = Join-Path (Join-Path $ProjectPath ".felix") "agents.json"
        ConfigFile       = Join-Path (Join-Path $ProjectPath ".felix") "config.json"
        StateFile        = Join-Path (Join-Path $ProjectPath ".felix") "state.json"
        RequirementsFile = Join-Path (Join-Path $ProjectPath ".felix") "requirements.json"
        PromptsDir       = Join-Path $PSScriptRoot "..\prompts"
    }
}

if (-not (Get-Command Emit-Error -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\emit-event.ps1"
}

if (-not (Get-Command Get-AgentDefaults -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\agent-adapters.ps1"
}

function Test-ProjectStructure {
    <#
    .SYNOPSIS
    Validates that required Felix project paths exist
    
    .PARAMETER Paths
    Hashtable of paths from Get-ProjectPaths
    
    .OUTPUTS
    Boolean indicating whether project structure is valid
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths
    )
    
    $requiredPaths = @(
        $Paths.SpecsDir,
        $Paths.FelixDir,
        $Paths.ConfigFile,
        $Paths.RequirementsFile
    )
    
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path $path)) {
            Emit-Error -ErrorType "InvalidProjectStructure" -Message "Required path not found: $path" -Severity "fatal"
            Emit-Log -Level "warn" -Message "This doesn't appear to be a valid Felix project" -Component "config"
            return $false
        }
    }
    
    return $true
}

function Get-FelixConfig {
    <#
    .SYNOPSIS
    Loads Felix configuration from config.json
    
    .PARAMETER ConfigFile
    Path to config.json
    
    .OUTPUTS
    PSCustomObject containing configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )
    
    if (-not (Test-Path $ConfigFile)) {
        Emit-Error -ErrorType "ConfigNotFound" -Message "Configuration file not found: $ConfigFile" -Severity "fatal"
        return $null
    }
    
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        Emit-Error -ErrorType "ConfigLoadFailed" -Message "Failed to load configuration: $_" -Severity "fatal"
        return $null
    }
}

function Get-AgentsConfiguration {
    <#
    .SYNOPSIS
    Loads agents configuration from a project agents.json
    
    .PARAMETER AgentsJsonFile
    Path to agents.json (e.g., <project>/.felix/agents.json).
    
    .OUTPUTS
    PSCustomObject containing agents configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentsJsonFile
    )
    
    # Create default agents.json if it doesn't exist
    if (-not (Test-Path $AgentsJsonFile)) {
        Emit-Log -Level "warn" -Message "Creating default agents.json at: $AgentsJsonFile" -Component "config"
        
        $defaultAgentsConfig = @{
            agents = @(
                @{
                    id                = 0
                    name              = "droid"
                    adapter           = "droid"
                    executable        = "droid"
                    working_directory = "."
                    environment       = @{}
                }
                @{
                    id                = 1
                    name              = "claude"
                    adapter           = "claude"
                    executable        = "claude"
                    working_directory = "."
                    environment       = @{}
                }
                @{
                    id                = 2
                    name              = "codex"
                    adapter           = "codex"
                    executable        = "codex"
                    working_directory = "."
                    environment       = @{}
                }
                @{
                    id                = 3
                    name              = "gemini"
                    adapter           = "gemini"
                    executable        = "gemini"
                    working_directory = "."
                    environment       = @{}
                }
            )
        }
        
        New-Item -Path (Split-Path $AgentsJsonFile -Parent) -ItemType Directory -Force | Out-Null
        $defaultAgentsConfig | ConvertTo-Json -Depth 10 | Set-Content $AgentsJsonFile
    }
    
    try {
        $agentsData = Get-Content $AgentsJsonFile -Raw | ConvertFrom-Json
        return $agentsData
    }
    catch {
        Emit-Error -ErrorType "AgentsConfigLoadFailed" -Message "Failed to load agents configuration: $_" -Severity "fatal"
        return $null
    }
}

function Get-AgentConfig {
    <#
    .SYNOPSIS
    Resolves specific agent configuration by ID
    
    .PARAMETER AgentsData
    Agents configuration data from Get-AgentsConfiguration
    
    .PARAMETER AgentId
    ID of the agent to retrieve
    
    .PARAMETER ConfigFile
    Path to config.json for auto-correction if needed
    
    .OUTPUTS
    Hashtable containing agent configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        $AgentsData,
        
        [Parameter(Mandatory = $true)]
        [string]$AgentId,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigFile = $null
    )
    
    # Find agent by ID — accept both 'key' (current) and 'id' (legacy) property names
    $agentConfig = $AgentsData.agents | Where-Object { $_.key -eq $AgentId -or $_.id -eq $AgentId }
    
    # Normalize: if agent was found via legacy 'id' field, alias it to 'key' so downstream code works
    if ($agentConfig -and -not $agentConfig.key -and $agentConfig.id) {
        $agentConfig | Add-Member -NotePropertyName 'key' -NotePropertyValue $agentConfig.id -Force
    }
    
    if (-not $agentConfig) {
        Emit-Log -Level "warn" -Message "Agent ID $AgentId not found in agents.json. Falling back to first configured agent. Run 'felix setup' or 'felix agent use <name|key>' to pick a valid active agent." -Component "config"
        $agentConfig = $AgentsData.agents | Select-Object -First 1
        
        if (-not $agentConfig) {
            Emit-Error -ErrorType "DefaultAgentNotFound" -Message "No agents found in agents.json" -Severity "fatal"
            return $null
        }
        
        # Normalize legacy 'id' -> 'key' on fallback agent too
        if (-not $agentConfig.key -and $agentConfig.id) {
            $agentConfig | Add-Member -NotePropertyName 'key' -NotePropertyValue $agentConfig.id -Force
        }
        
        # Auto-correct config.json to reference first agent if path provided
        if ($ConfigFile) {
            try {
                $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
                $config.agent.agent_id = $agentConfig.key
                $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
                Emit-Log -Level "info" -Message "Auto-corrected config.json to reference agent key $($agentConfig.key)" -Component "config"
            }
            catch {
                Emit-Log -Level "warn" -Message "Could not auto-correct config.json: $_" -Component "config"
            }
        }
    }

    $adapterType = if ($agentConfig.adapter) { $agentConfig.adapter } else { $agentConfig.name }
    $defaults = Get-AgentDefaults -AdapterType $adapterType
    foreach ($key in $defaults.Keys) {
        $hasProperty = $agentConfig.PSObject.Properties[$key]
        $value = if ($hasProperty) { $agentConfig.$key } else { $null }
        $needsDefault = $false

        if (-not $hasProperty) {
            $needsDefault = $true
        }
        elseif ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
            $needsDefault = $true
        }
        elseif ($null -eq $value) {
            $needsDefault = $true
        }

        if ($needsDefault) {
            $agentConfig | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
        }
    }
    
    Emit-Log -Level "info" -Message "Using agent: $($agentConfig.name) (Key: $($agentConfig.key))" -Component "agent"
    Emit-Log -Level "info" -Message "Executable: $($agentConfig.executable)" -Component "agent"
    
    return $agentConfig
}

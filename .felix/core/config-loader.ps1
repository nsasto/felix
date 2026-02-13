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
        PromptsDir       = Join-Path (Join-Path $ProjectPath ".felix") "prompts"
    }
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
                    args              = @("exec", "--skip-permissions-unsafe", "--output-format", "json")
                    working_directory = "."
                    environment       = @{}
                    description       = "Factory.ai Droid - Fast, reliable, JSON event stream"
                }
                @{
                    id                = 1
                    name              = "claude"
                    adapter           = "claude"
                    executable        = "claude"
                    args              = @("-p", "--model", "sonnet", "--output-format", "text")
                    working_directory = "."
                    environment       = @{}
                    description       = "Anthropic Claude Code - Excellent reasoning, OAuth auth"
                }
                @{
                    id                = 2
                    name              = "codex"
                    adapter           = "codex"
                    executable        = "codex"
                    args              = @("-C", ".", "-s", "workspace-write", "-a", "never")
                    working_directory = "."
                    environment       = @{}
                    description       = "OpenAI Codex CLI - Diff-based workflow, OAuth auth"
                }
                @{
                    id                = 3
                    name              = "gemini"
                    adapter           = "gemini"
                    executable        = "gemini"
                    args              = @("-m", "auto", "--approval-mode=auto_edit", "--output-format", "json")
                    working_directory = "."
                    environment       = @{}
                    description       = "Google Gemini CLI - JSON streaming, OAuth auth"
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
        [int]$AgentId,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigFile = $null
    )
    
    # Find agent by ID
    $agentConfig = $AgentsData.agents | Where-Object { $_.id -eq $AgentId }
    
    if (-not $agentConfig) {
        Emit-Log -Level "warn" -Message "Agent ID $AgentId not found in agents.json. Falling back to system default (ID 0)" -Component "config"
        $agentConfig = $AgentsData.agents | Where-Object { $_.id -eq 0 }
        
        if (-not $agentConfig) {
            Emit-Error -ErrorType "DefaultAgentNotFound" -Message "System default agent (ID 0) not found in agents.json" -Severity "fatal"
            return $null
        }
        
        # Auto-correct config.json to reference agent ID 0 if path provided
        if ($ConfigFile) {
            try {
                $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
                $config.agent.agent_id = 0
                $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
                Emit-Log -Level "info" -Message "Auto-corrected config.json to reference agent ID 0" -Component "config"
            }
            catch {
                Emit-Log -Level "warn" -Message "Could not auto-correct config.json: $_" -Component "config"
            }
        }
    }
    
    Emit-Log -Level "info" -Message "Using agent: $($agentConfig.name) (ID: $($agentConfig.id))" -Component "agent"
    Emit-Log -Level "info" -Message "Executable: $($agentConfig.executable) $($agentConfig.args -join ' ')" -Component "agent"
    
    return $agentConfig
}

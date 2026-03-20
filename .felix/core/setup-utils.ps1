<#
.SYNOPSIS
Shared utilities for setup operations

.DESCRIPTION
Common functions used by setup.ps1, agent-setup.ps1, and other setup-related modules.
#>

function Copy-EngineFile {
    <#
    .SYNOPSIS
    Copy a file from the Felix engine directory to the project's .felix directory
    
    .PARAMETER FelixRoot
    Root directory of the Felix engine
    
    .PARAMETER FelixDir
    Project's .felix directory
    
    .PARAMETER RelPath
    Relative path within .felix (e.g., "policies\allowlist.json")
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [string]$FelixRoot,
        [string]$FelixDir,
        [string]$RelPath
    )
    
    $src = Join-Path $FelixRoot $RelPath
    $dest = Join-Path $FelixDir  $RelPath
    if ((Test-Path $src) -and -not (Test-Path $dest)) {
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $src $dest -Force
        return $true
    }
    return $false
}

function Show-ApiKeyExpiration {
    <#
    .SYNOPSIS
    Display API key expiration in human-readable format
    #>
    param([string]$ExpiresAt)
    
    if (-not $ExpiresAt) {
        Write-Host "   Expires: Never" -ForegroundColor Gray
        return
    }
    
    $expiresDate = [DateTime]::Parse($ExpiresAt)
    $daysLeft = ($expiresDate - [DateTime]::Now).Days
    $dateString = $expiresDate.ToString("yyyy-MM-dd")
    
    if ($daysLeft -gt 0) {
        Write-Host "   Expires: $dateString ($daysLeft days left)" -ForegroundColor Gray
    }
    else {
        Write-Host "   Expires: $dateString (EXPIRED)" -ForegroundColor Yellow
    }
}

function Test-ExecutableInstalled {
    <#
    .SYNOPSIS
    Test if an executable is available on PATH
    
    .PARAMETER ExecutableName
    Name of the executable to test (e.g., "droid", "codex", "claude")
    
    .OUTPUTS
    Boolean
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutableName
    )
    
    try {
        $resolved = Get-Command $ExecutableName -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $true
        }

        if ($ExecutableName.ToLower() -eq "copilot") {
            foreach ($candidate in (Get-CopilotExecutableCandidates)) {
                if (Test-Path $candidate) {
                    return $true
                }
            }
        }

        return $false
    }
    catch {
        return $false
    }
}

function Get-CopilotExecutableCandidates {
    <#
    .SYNOPSIS
    Returns likely Windows Copilot CLI shim paths.

    .DESCRIPTION
    GitHub Copilot CLI on Windows is often installed under VS Code globalStorage
    rather than a directory present on PATH. This helper surfaces the common shim
    locations so setup-time detection can reflect the real installed state.
    #>
    param()

    $candidates = @()
    $candidateDirs = @()

    if ($env:FELIX_COPILOT_CLI_ROOTS) {
        $candidateDirs += ($env:FELIX_COPILOT_CLI_ROOTS -split [System.IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($env:APPDATA) {
        $globalStorage = Join-Path $env:APPDATA "Code\User\globalStorage"
        if (Test-Path $globalStorage) {
            $copilotStorageDirs = Get-ChildItem -Path $globalStorage -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "github.copilot*" } |
            ForEach-Object { Join-Path $_.FullName "copilotCli" }
            $candidateDirs += $copilotStorageDirs
        }

        $candidateDirs += @(
            (Join-Path $env:APPDATA ".vscode-copilot"),
            (Join-Path $env:APPDATA ".vscode-copilot\bin")
        )
    }

    foreach ($dir in ($candidateDirs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $candidates += @(
            (Join-Path $dir "copilot.bat"),
            (Join-Path $dir "copilot.cmd"),
            (Join-Path $dir "copilot.exe"),
            (Join-Path $dir "copilot.ps1")
        )
    }

    return @($candidates | Select-Object -Unique)
}

function New-AgentKey {
    <#
    .SYNOPSIS
    Generate a deterministic agent key based on provider, model, settings, and project
    
    .DESCRIPTION
    Creates an immutable content-addressed key for an agent configuration.
    Same provider+model+settings+machine+project always produces the same key.
    This prevents UUID management issues and ensures idempotent syncing.
    
    .PARAMETER Provider
    Agent provider name (codex, claude, droid, gemini)
    
    .PARAMETER Model
    Model name (e.g., gpt-4, claude-opus)
    
    .PARAMETER AgentSettings
    Provider-specific settings object (e.g., sandbox mode for Codex)
    
    .PARAMETER ProjectRoot
    Root directory of the project (used to derive git remote URL or path)
    
    .OUTPUTS
    String like 'ag_a3f7b9e2c1'
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Provider,
        
        [Parameter(Mandatory = $true)]
        [string]$Model,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AgentSettings = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot = $null
    )

    function ConvertTo-OrderedValue {
        param([object]$Value)

        if ($null -eq $Value) { return $null }

        if ($Value -is [System.Collections.IDictionary]) {
            $ordered = [ordered]@{}
            foreach ($key in ($Value.Keys | Sort-Object)) {
                $ordered[$key] = ConvertTo-OrderedValue -Value $Value[$key]
            }
            return $ordered
        }

        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            $list = @()
            foreach ($item in $Value) {
                $list += ConvertTo-OrderedValue -Value $item
            }
            return $list
        }

        return $Value
    }
    
    # Use system hostname as machine identifier
    $machineId = $env:COMPUTERNAME.ToLower()
    
    # Derive project identifier from git remote URL or filesystem path
    $projectId = $ProjectRoot
    if (-not [string]::IsNullOrEmpty($ProjectRoot)) {
        try {
            $currentDir = Get-Location
            Set-Location $ProjectRoot | Out-Null
            $gitUrl = git config --get remote.origin.url 2>$null
            Set-Location $currentDir | Out-Null
            
            if (-not [string]::IsNullOrEmpty($gitUrl)) {
                # Normalize git URL: remove .git, convert SSH to HTTPS, lowercase
                $projectId = $gitUrl.ToLower() -replace '\.git$', '' -replace '^git@(.+?):', 'https://$1/'
            }
            else {
                $projectId = $ProjectRoot.ToLower().TrimEnd('\', '/')
            }
        }
        catch {
            $projectId = $ProjectRoot.ToLower().TrimEnd('\', '/')
        }
    }
    else {
        $projectId = (Get-Location).Path.ToLower().TrimEnd('\', '/')
    }
    
    # Create deterministic string representation of settings
    $settingsStr = ""
    if ($AgentSettings -and $AgentSettings.Count -gt 0) {
        # Compact JSON to ensure consistent formatting
        $orderedSettings = ConvertTo-OrderedValue -Value $AgentSettings
        $settingsStr = ($orderedSettings | ConvertTo-Json -Compress -Depth 10) -replace '\s+', ''
    }
    
    # Build hash input: provider::model::settings::machine::project
    $hashInput = @(
        $Provider.ToLower(),
        $Model.ToLower(),
        $settingsStr,
        $machineId,
        $projectId
    ) -join "::"
    
    # Compute SHA256 hash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hashStr = [BitConverter]::ToString($hash).Replace("-", "").ToLower()
    
    # Return ag_ prefix + first 9 chars of hash (12 chars total)
    return "ag_$($hashStr.Substring(0, 9))"
}

function Build-AgentRegistrationPayload {
    <#
    .SYNOPSIS
    Builds the canonical agent registration payload for the backend.

    .DESCRIPTION
    Single source of truth for what gets sent to /api/agents/register-sync.
    Uses only the base identity fields from agents.json — name, provider/adapter,
    model, and machine hostname — so that 'felix agent register' and the workflow
    always produce the same key and the same payload shape.

    .PARAMETER AgentConfig
    Agent entry from agents.json (must have: name, adapter|name, model).

    .PARAMETER ProjectRoot
    Root directory of the project (used to look up git remote URL and to
    derive the project identity component of the agent key).

    .PARAMETER Source
    Value for metadata.source. Defaults to "cli".

    .OUTPUTS
    Hashtable ready to pass to $reporter.RegisterAgent(). Contains:
      key, provider, model, agent_settings, machine_id, name, type, git_url, metadata.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $AgentConfig,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $false)]
        [string]$Source = "cli"
    )

    $provider = if ($AgentConfig.adapter) { $AgentConfig.adapter } else { $AgentConfig.name }
    $model = if ($AgentConfig.model) { [string]$AgentConfig.model } else { "" }

    # Key is always generated from empty settings — infrastructure defaults
    # (executable, working_directory, environment) are NOT part of agent identity.
    $agentKey = New-AgentKey -Provider $provider -Model $model -AgentSettings @{} -ProjectRoot $ProjectRoot

    # Machine identifier
    $hostname = $env:COMPUTERNAME
    if (-not $hostname) { $hostname = $env:HOSTNAME }
    if (-not $hostname) {
        try { $hostname = [System.Net.Dns]::GetHostName() } catch { $hostname = "unknown" }
    }

    # Git URL for project authentication
    $gitUrl = $null
    try {
        $raw = & git -C $ProjectRoot config --get remote.origin.url 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) { $gitUrl = $raw.Trim() }
    }
    catch { }

    # Metadata — only base identity fields, no runtime defaults
    $metadata = @{
        hostname = $hostname
        adapter  = $provider
        source   = $Source
    }
    if ($model -ne "") { $metadata["model"] = $model }

    $payload = @{
        key            = $agentKey
        provider       = $provider
        model          = $model
        agent_settings = @{}
        machine_id     = $hostname
        name           = $AgentConfig.name
        type           = "cli"
        metadata       = $metadata
    }
    if ($gitUrl) { $payload["git_url"] = $gitUrl }

    return $payload
}

function ConvertTo-ConfiguredAgentList {
    <#
    .SYNOPSIS
    Normalizes raw agents.json content into a consistent configured-agent list.

    .PARAMETER AgentsData
    Object parsed from .felix/agents.json.

    .OUTPUTS
    Array of PSCustomObject entries: Name, Provider, Model, Key.
    #>
    param(
        [Parameter(Mandatory = $false)]
        $AgentsData
    )

    $configuredAgents = @()
    if (-not $AgentsData -or -not $AgentsData.agents) {
        return , $configuredAgents
    }

    foreach ($agent in $AgentsData.agents) {
        $agentKey = $null
        if ($agent.PSObject.Properties['key'] -and $agent.key) {
            $agentKey = [string]$agent.key
        }
        elseif ($agent.PSObject.Properties['id'] -and $null -ne $agent.id) {
            $agentKey = [string]$agent.id
        }

        if (-not $agentKey) {
            continue
        }

        $provider = if ($agent.PSObject.Properties['provider'] -and $agent.provider) {
            [string]$agent.provider
        }
        elseif ($agent.PSObject.Properties['adapter'] -and $agent.adapter) {
            [string]$agent.adapter
        }
        else {
            ""
        }

        $configuredAgents += [pscustomobject]@{
            Name     = [string]$agent.name
            Provider = $provider
            Model    = if ($agent.PSObject.Properties['model']) { [string]$agent.model } else { "" }
            Key      = $agentKey
        }
    }

    return , $configuredAgents
}

function Get-ActiveAgentSelectionPlan {
    <#
    .SYNOPSIS
    Determines setup behavior for active-agent selection.

    .PARAMETER ConfiguredAgents
    Normalized configured agents list.

    .PARAMETER CurrentAgentId
    Current value of config.agent.agent_id (optional).

    .OUTPUTS
    PSCustomObject with Mode (none|auto|choose), CurrentAgent, AutoAgent, and IsCurrentMissing.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$ConfiguredAgents = @(),

        [Parameter(Mandatory = $false)]
        [string]$CurrentAgentId = $null
    )

    if (-not $ConfiguredAgents) {
        $ConfiguredAgents = @()
    }

    $currentAgent = $null
    if ($CurrentAgentId) {
        $currentAgent = $ConfiguredAgents | Where-Object { $_.Key -eq $CurrentAgentId } | Select-Object -First 1
    }

    if ($ConfiguredAgents.Count -eq 0) {
        return [pscustomobject]@{
            Mode             = "none"
            CurrentAgent     = $currentAgent
            AutoAgent        = $null
            IsCurrentMissing = $false
        }
    }

    if ($ConfiguredAgents.Count -eq 1) {
        return [pscustomobject]@{
            Mode             = "auto"
            CurrentAgent     = $currentAgent
            AutoAgent        = $ConfiguredAgents[0]
            IsCurrentMissing = $false
        }
    }

    return [pscustomobject]@{
        Mode             = "choose"
        CurrentAgent     = $currentAgent
        AutoAgent        = $null
        IsCurrentMissing = [bool]($CurrentAgentId -and -not $currentAgent)
    }
}

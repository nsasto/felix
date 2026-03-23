<#
.SYNOPSIS
Interactive agent configuration setup

.DESCRIPTION
Guides users through selecting LLM agent providers and models, then configures
their project's agents.json with new UUIDs for each selected agent.
#>

# Load shared utilities
. (Join-Path $PSScriptRoot "setup-utils.ps1")
if (-not (Get-Command Get-AgentDefaults -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "agent-adapters.ps1")
}

function Get-AgentInstallGuidance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName
    )

    switch ($AgentName.ToLower()) {
        "droid" {
            return @(
                "Install with: npm install -g @factory-ai/droid-cli",
                "Then verify with: droid --version"
            )
        }
        "claude" {
            return @(
                "Install with: npm install -g @anthropic-ai/claude-code",
                "Then run: claude auth login"
            )
        }
        "codex" {
            return @(
                "Install with: npm install -g @openai/codex-cli",
                "Then run: codex auth"
            )
        }
        "gemini" {
            return @(
                "Install with: pip install google-gemini-cli",
                "Then run: gemini auth login"
            )
        }
        "copilot" {
            return @(
                "Install the GitHub Copilot Chat extension in VS Code and allow it to install the Copilot CLI when prompted.",
                "Or run `copilot` once in a terminal to trigger the CLI install flow.",
                "Then run: copilot login"
            )
        }
        default {
            return @("Install via your package manager and ensure the executable is on PATH.")
        }
    }
}

function Get-AvailableAgents {
    <#
    .SYNOPSIS
    Load agent templates from engine directory
    
    .PARAMETER FelixRoot
    Path to Felix engine directory
    
    .OUTPUTS
    Array of agent template objects
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FelixRoot
    )
    
    $candidates = @(
        (Join-Path $FelixRoot "agent-templates.json"),
        (Join-Path $FelixRoot ".felix\agent-templates.json"),
        (Join-Path $FelixRoot "agents.json"),
        (Join-Path $FelixRoot ".felix\agents.json")
    )
    $engineAgentsPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $engineAgentsPath) {
        Write-Warning "Engine agent templates not found at: $($candidates -join ', ')"
        return @()
    }
    
    try {
        $agentsData = Get-Content $engineAgentsPath -Raw | ConvertFrom-Json
        return $agentsData.agents
    }
    catch {
        Write-Warning "Failed to parse engine agents.json: $_"
        return @()
    }
}

function Get-ModelCatalog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FelixRoot
    )

    $candidates = @(
        (Join-Path $FelixRoot "agent-models.json"),
        (Join-Path $FelixRoot ".felix\agent-models.json")
    )
    $catalogPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $catalogPath) {
        return @{}
    }

    try {
        return (Get-Content $catalogPath -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Warning "Failed to parse agent model catalog: $_"
        return @{}
    }
}

function Get-ModelsForProvider {
    <#
    .SYNOPSIS
    Return available models for a given provider
    
    .PARAMETER Provider
    Agent provider name (droid, claude, codex, gemini, copilot)
    
    .OUTPUTS
    Array of available model names
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Provider,

        [Parameter(Mandatory = $false)]
        [string]$FelixRoot = $null
    )

    $models = @{}
    if ($FelixRoot) {
        $catalog = Get-ModelCatalog -FelixRoot $FelixRoot
        if ($catalog -and $catalog.providers) {
            $models = $catalog.providers
        }
    }

    if (-not $models -or $models.Count -eq 0) {
        $models = @{
            droid   = @(
                "claude-opus-4-6",
                "claude-opus-4-6-fast",
                "claude-opus-4-5-20251101",
                "claude-sonnet-4-6",
                "claude-sonnet-4-5-20250929",
                "claude-haiku-4-5-20251001",
                "gpt-5.4",
                "gpt-5.3-codex",
                "gpt-5.2-codex",
                "gpt-5.2",
                "gemini-3.1-pro-preview",
                "gemini-3-flash-preview",
                "glm-4.7",
                "glm-5",
                "kimi-k2.5",
                "minimax-m2.5"
            )
            claude  = @("sonnet", "opus")
            codex   = @("gpt-5.2-codex", "gpt-5.4-codex")
            gemini  = @("auto")
            copilot = @("gpt-5.4", "gpt-5.3-codex", "claude-opus-4.6", "claude-sonnet-4.6", "claude-haiku-4.5", "claude-opus-4.5", "claude-opus-4.6-fast", "claude-sonnet-4", "claude-sonnet-4.5", "gemini-2.5-pro", "gemini-3-flash", "gemini-3-pro", "gemini-3.1-pro")
        }
    }

    if ($models -is [System.Collections.IDictionary]) {
        if ($models.ContainsKey($Provider)) {
            return @($models[$Provider])
        }
        return @()
    }

    $property = $models.PSObject.Properties[$Provider]
    if ($property) {
        return @($property.Value)
    }

    return @()
}

function Invoke-AgentSelection {
    <#
    .SYNOPSIS
    Interactive wizard to select agents and models
    
    .PARAMETER AvailableAgents
    Array of agent template objects from engine
    
    .OUTPUTS
    Array of hashtables with selected agent configurations (including new UUIDs)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$AvailableAgents,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot = $null,

        [Parameter(Mandatory = $false)]
        [string]$FelixRoot = $null
    )
    
    Write-Host "`nAgent Configuration" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Select which agents to configure for this project.`n" -ForegroundColor Gray
    
    $selectedAgents = @()
    $agentMap = @{}
    
    # Build map for easy lookup
    foreach ($agent in $AvailableAgents) {
        $agentMap[$agent.name] = $agent
    }
    
    # Show available agents with validation
    $validAgents = @()
    $listedAgents = @()
    $index = 1
    foreach ($agent in $AvailableAgents) {
        $adapterType = if ($agent.adapter) { $agent.adapter } elseif ($agent.provider) { $agent.provider } else { $agent.name }
        $defaults = Get-AgentDefaults -AdapterType $adapterType
        $exeName = if ($agent.executable) { $agent.executable } else { $defaults.executable }
        $installed = Test-ExecutableInstalled -ExecutableName $exeName
        $status = if ($installed) { "[OK] installed" } else { "[--] not installed" }
        $providerLabel = if ($agent.PSObject.Properties["provider"]) { $agent.provider } elseif ($agent.PSObject.Properties["adapter"]) { $agent.adapter } else { $null }
        $label = if ($providerLabel) { "$($agent.name) ($providerLabel)" } else { $agent.name }
        Write-Host "  [$index] $label $status" -ForegroundColor $(if ($installed) { "Green" } else { "DarkGray" })
        
        if ($installed) {
            $validAgents += $agent.name
        }
        $listedAgents += [pscustomobject]@{
            Name      = $agent.name
            Installed = $installed
        }
        $index++
    }
    
    if ($validAgents.Count -eq 0) {
        Write-Host "`n[WARN] No agent executables found on PATH. Please install at least one:" -ForegroundColor Yellow
        foreach ($agent in $AvailableAgents) {
            Write-Host "  - $($agent.name)" -ForegroundColor Gray
            foreach ($line in (Get-AgentInstallGuidance -AgentName $agent.name)) {
                Write-Host "      $line" -ForegroundColor DarkGray
            }
        }
        return @()
    }
    
    Write-Host "`nAvailable agents (with executables installed): $($validAgents -join ', ')" -ForegroundColor Gray
    Write-Host ""
    
    # Multiple selection loop
    $continue = $true
    while ($continue) {
        $choice = Read-Host "Select an agent to configure (number or name)"
        
        if ($choice -eq "done" -or $choice -eq "") {
            $continue = $false
            if ($selectedAgents.Count -eq 0) {
                Write-Host "[WARN] No agents selected" -ForegroundColor Yellow
            }
            break
        }
        
        $choice = $choice.Trim()
        $agentName = $null
        if ($choice -match '^\d+$') {
            $choiceIndex = [int]$choice
            if ($choiceIndex -lt 1 -or $choiceIndex -gt $listedAgents.Count) {
                Write-Host "  [ERR] Invalid agent number: $choice" -ForegroundColor Red
                continue
            }
            $agentName = $listedAgents[$choiceIndex - 1].Name
        }
        else {
            $agentName = $choice.ToLower()
            if (-not $agentMap.ContainsKey($agentName)) {
                Write-Host "  [ERR] Unknown agent: $choice" -ForegroundColor Red
                continue
            }
        }
        
        if ($validAgents -notcontains $agentName) {
            Write-Host "  [ERR] Agent not installed: $agentName" -ForegroundColor Red
            foreach ($line in (Get-AgentInstallGuidance -AgentName $agentName)) {
                Write-Host "      $line" -ForegroundColor DarkGray
            }
            continue
        }
        
        # Check if already selected
        if ($selectedAgents | Where-Object { $_.name -eq $agentName }) {
            Write-Host "  [WARN] $agentName already selected" -ForegroundColor Yellow
            continue
        }
        
        $baseAgent = $agentMap[$agentName]
        $selectedConfig = $baseAgent | ConvertTo-Json | ConvertFrom-Json
        if (-not $selectedConfig.provider) {
            if ($selectedConfig.adapter) {
                $selectedConfig.provider = $selectedConfig.adapter
            }
            else {
                $selectedConfig.provider = $selectedConfig.name
            }
        }
        $adapterType = if ($selectedConfig.adapter) { $selectedConfig.adapter } else { $selectedConfig.provider }
        $defaults = Get-AgentDefaults -AdapterType $adapterType
        
        # Allow model selection if provider supports multiple models
        $availableModels = Get-ModelsForProvider -Provider $selectedConfig.provider -FelixRoot $FelixRoot
        if ($availableModels -and -not ($availableModels -is [System.Array])) {
            $availableModels = @($availableModels)
        }
        if (-not $availableModels -or $availableModels.Count -eq 0) {
            $availableModels = if ($defaults.model) { @($defaults.model) } else { @() }
        }
        $defaultModel = if ($selectedConfig.model) { $selectedConfig.model } elseif ($availableModels.Count -gt 0) { $availableModels[0] } else { $defaults.model }
        if ($availableModels.Count -gt 1) {
            Write-Host "  Available models for $agentName`:" -ForegroundColor Gray
            for ($i = 0; $i -lt $availableModels.Count; $i++) {
                Write-Host ("    [{0}] {1}" -f ($i + 1), $availableModels[$i]) -ForegroundColor Gray
            }
            $modelInput = Read-Host "  Select model (number or name) [default: $defaultModel]"
            if ($modelInput -and $modelInput.Trim()) {
                $modelInput = $modelInput.Trim()
                if ($modelInput -match '^\d+$') {
                    $modelIndex = [int]$modelInput
                    if ($modelIndex -ge 1 -and $modelIndex -le $availableModels.Count) {
                        $selectedConfig | Add-Member -NotePropertyName model -NotePropertyValue $availableModels[$modelIndex - 1] -Force
                    }
                    else {
                        Write-Host "    [WARN] Invalid model number, using default: $($baseAgent.model)" -ForegroundColor Yellow
                    }
                }
                elseif ($availableModels -contains $modelInput) {
                    $selectedConfig | Add-Member -NotePropertyName model -NotePropertyValue $modelInput -Force
                }
                else {
                    Write-Host "    [WARN] Unknown model, using default: $($baseAgent.model)" -ForegroundColor Yellow
                }
            }
        }
        
        # Generate deterministic content-addressed key for this agent
        $modelForKey = if ($selectedConfig.model) { $selectedConfig.model } else { $defaultModel }
        $agentSettings = @{}
        $exeForKey = if ($selectedConfig.executable) { $selectedConfig.executable } else { $defaults.executable }
        if ($exeForKey) { $agentSettings["executable"] = $exeForKey }
        $workingDirForKey = if ($selectedConfig.working_directory) { $selectedConfig.working_directory } else { $defaults.working_directory }
        if ($workingDirForKey) { $agentSettings["working_directory"] = $workingDirForKey }
        $envForKey = if ($selectedConfig.environment) { $selectedConfig.environment } else { $defaults.environment }
        if ($envForKey) { $agentSettings["environment"] = $envForKey }
        foreach ($defaultKey in $defaults.Keys) {
            if ($defaultKey -in @("adapter", "executable", "model", "working_directory", "environment")) {
                continue
            }

            $valueForKey = $null
            if ($selectedConfig.PSObject.Properties[$defaultKey]) {
                $valueForKey = $selectedConfig.$defaultKey
            }
            else {
                $valueForKey = $defaults[$defaultKey]
            }

            if ($null -ne $valueForKey -and -not ($valueForKey -is [string] -and [string]::IsNullOrWhiteSpace($valueForKey))) {
                $agentSettings[$defaultKey] = $valueForKey
            }
        }
        $agentKey = New-AgentKey -Provider $selectedConfig.provider -Model $modelForKey -AgentSettings $agentSettings -ProjectRoot $ProjectRoot
        $selectedConfig | Add-Member -NotePropertyName id -NotePropertyValue $agentKey -Force
        $selectedAgents += $selectedConfig
        
        $displayModel = if ($selectedConfig.model) { $selectedConfig.model } else { $defaultModel }
        Write-Host "  [+] Added: $($selectedConfig.name) (model: $displayModel, id: $($selectedConfig.id))" -ForegroundColor Green
        Write-Host ""

        $another = Read-Host "  Add another agent? (Y/n)"
        if ($another -eq 'n' -or $another -eq 'N') {
            $continue = $false
            break
        }
    }
    
    return $selectedAgents
}

function Add-AgentsToProjectConfig {
    <#
    .SYNOPSIS
    Write selected agents to project's agents.json
    
    .PARAMETER ProjectRoot
    Root directory of the project
    
    .PARAMETER SelectedAgents
    Array of selected agent configurations
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory = $true)]
        [array]$SelectedAgents
    )
    
    if ($SelectedAgents.Count -eq 0) {
        Write-Host "[SKIP] No agents to configure" -ForegroundColor Gray
        return $false
    }
    
    $felixDir = Join-Path $ProjectRoot ".felix"
    if (-not (Test-Path $felixDir)) {
        Write-Host "[ERR] Project .felix directory not found: $felixDir" -ForegroundColor Red
        return $false
    }
    
    $agentsPath = Join-Path $felixDir "agents.json"
    
    # Load or create agents.json
    $agentsConfig = @{ agents = @() }
    if (Test-Path $agentsPath) {
        try {
            $agentsConfig = Get-Content $agentsPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Could not parse existing agents.json, creating new: $_"
        }
    }
    
    # Ensure agents array exists
    if (-not $agentsConfig.PSObject.Properties['agents']) {
        $agentsConfig | Add-Member -NotePropertyName agents -NotePropertyValue @()
    }
    
    # Add selected agents (avoid duplicates with same name)
    foreach ($agent in $SelectedAgents) {
        $existing = $agentsConfig.agents | Where-Object { $_.name -eq $agent.name }
        if ($existing) {
            # Update existing agent
            $existingIdx = $agentsConfig.agents.IndexOf($existing)
            $agentsConfig.agents[$existingIdx] = $agent
            Write-Host "  Updated: $($agent.name)" -ForegroundColor Cyan
        }
        else {
            # Add new agent
            $agentsConfig.agents += $agent
            Write-Host "  Added: $($agent.name)" -ForegroundColor Green
        }
    }
    
    # Write back to file
    $agentsConfig | ConvertTo-Json -Depth 10 | Set-Content $agentsPath -Encoding UTF8
    Write-Host "  [OK] Saved to .felix/agents.json" -ForegroundColor Green
    return $true
}

function Invoke-AgentSetup {
    <#
    .SYNOPSIS
    Main entry point for agent configuration setup
    
    .PARAMETER ProjectRoot
    Root directory of the project
    
    .PARAMETER FelixRoot
    Path to Felix engine directory (defaults from env or parent path)
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory = $false)]
        [string]$FelixRoot = (if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) })
    )
    
    $availableAgents = Get-AvailableAgents -FelixRoot $FelixRoot
    if ($availableAgents.Count -eq 0) {
        Write-Host "[ERR] No agent templates found in engine directory" -ForegroundColor Red
        return $false
    }
    
    $selectedAgents = Invoke-AgentSelection -AvailableAgents $availableAgents -ProjectRoot $ProjectRoot -FelixRoot $FelixRoot
    if ($selectedAgents.Count -eq 0) {
        Write-Host "[SKIP] No agents configured" -ForegroundColor Gray
        return $false
    }
    
    Write-Host "`nConfiguring selected agents..." -ForegroundColor Cyan
    return Add-AgentsToProjectConfig -ProjectRoot $ProjectRoot -SelectedAgents $selectedAgents
}

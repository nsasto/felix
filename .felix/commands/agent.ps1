
# Resolve-FelixExecutablePath is used only by Invoke-Agent — kept co-located here.
function Resolve-FelixExecutablePath {
    param([Parameter(Mandatory = $true)][string]$Executable)

    if ([string]::IsNullOrWhiteSpace($Executable)) {
        return $null
    }

    # Direct path (relative or absolute)
    try {
        if (Test-Path $Executable) {
            return (Resolve-Path $Executable).Path
        }
    }
    catch { }

    # PATH / registered command
    try {
        $source = (Get-Command $Executable -ErrorAction Stop).Source
        if ($source -and $source.EndsWith(".ps1")) {
            $cmdShim = [System.IO.Path]::ChangeExtension($source, "cmd")
            if (Test-Path $cmdShim) {
                return (Resolve-Path $cmdShim).Path
            }
            $exeShim = [System.IO.Path]::ChangeExtension($source, "exe")
            if (Test-Path $exeShim) {
                return (Resolve-Path $exeShim).Path
            }
        }
        return $source
    }
    catch { }

    $ext = [System.IO.Path]::GetExtension($Executable)
    $names = if ($ext) {
        @($Executable)
    }
    else {
        # Prefer Windows npm shims first to avoid PowerShell execution-policy issues.
        @("$Executable.cmd", "$Executable.exe", "$Executable.ps1", $Executable)
    }

    $candidateRoots = @()

    # Windows npm global shim directory is usually %APPDATA%\npm
    if ($env:APPDATA) {
        $candidateRoots += (Join-Path $env:APPDATA "npm")
    }

    # Try npm global prefix if npm is installed
    try {
        $null = Get-Command npm -ErrorAction Stop
        $npmPrefix = (& npm prefix -g 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($npmPrefix)) {
            $candidateRoots += $npmPrefix
            $candidateRoots += (Join-Path $npmPrefix "bin")
        }
    }
    catch { }

    foreach ($root in ($candidateRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        foreach ($name in $names) {
            try {
                $candidate = Join-Path $root $name
                if (Test-Path $candidate) {
                    return (Resolve-Path $candidate).Path
                }
            }
            catch { }
        }
    }

    return $null
}

function Invoke-Agent {
    param([string[]]$AgentArgs)

    if ($AgentArgs -is [string]) {
        $AgentArgs = @($AgentArgs -split '\s+' | Where-Object { $_ -ne '' })
    }
    elseif ($AgentArgs.Count -gt 0 -and $AgentArgs[0] -is [char]) {
        $AgentArgs = @(((-join $AgentArgs) -split '\s+') | Where-Object { $_ -ne '' })
    }
    else {
        $AgentArgs = @($AgentArgs)
    }

    if (-not $AgentArgs -or $AgentArgs.Count -eq 0) {
        $helpPath = Join-Path $PSScriptRoot "help.ps1"
        if (Test-Path $helpPath) {
            . $helpPath
            Show-Help -SubCommand "agent"
            return
        }
        Write-Host "Usage: felix agent <list|current|use|test|setup|install-help|register> [args]"
        return
    }
    
    $subCmd = $AgentArgs[0]
    $subArgs = if ($AgentArgs.Count -gt 1) { @($AgentArgs[1..($AgentArgs.Count - 1)]) } else { @() }

    function Resolve-AgentTargetInput {
        param([object[]]$Values)

        if (-not $Values -or $Values.Count -eq 0) {
            return $null
        }

        return ((@($Values) | ForEach-Object { [string]$_ }) -join '').Trim()
    }

    if ($subCmd -in @("setup", "install-help")) {
        . "$PSScriptRoot\..\core\agent-setup.ps1"
        $felixRoot = if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { Split-Path -Parent $PSScriptRoot }
        if ($subCmd -eq "setup") {
            Invoke-AgentSetup -ProjectRoot $RepoRoot -FelixRoot $felixRoot | Out-Null
            return
        }

        $availableAgents = @(Get-AvailableAgents -FelixRoot $felixRoot)
        if ($availableAgents.Count -eq 0) {
            $availableAgents = @(
                [pscustomobject]@{ name = "droid" },
                [pscustomobject]@{ name = "claude" },
                [pscustomobject]@{ name = "codex" },
                [pscustomobject]@{ name = "gemini" },
                [pscustomobject]@{ name = "copilot" }
            )
        }

        $targetAgent = if ($subArgs.Count -gt 0) {
            (Resolve-AgentTargetInput -Values $subArgs).ToLower()
        }
        else { $null }
        $agentsToShow = @()

        if ($targetAgent) {
            $match = $availableAgents | Where-Object { $_.name -eq $targetAgent } | Select-Object -First 1
            if (-not $match) {
                Write-Error "Unknown agent: $targetAgent"
                exit 1
            }
            $agentsToShow = @($match)
        }
        else {
            $agentsToShow = $availableAgents
        }

        Write-Host ""
        Write-Host "Agent Install Help" -ForegroundColor Cyan
        Write-Host ""
        foreach ($agent in $agentsToShow) {
            $defaults = Get-AgentDefaults -AdapterType $agent.name
            $exeName = if ($agent.PSObject.Properties["executable"] -and $agent.executable) { $agent.executable } else { $defaults.executable }
            $installed = Test-ExecutableInstalled -ExecutableName $exeName
            $status = if ($installed) { "[OK] installed" } else { "[--] not installed" }

            Write-Host "$($agent.name) $status" -ForegroundColor $(if ($installed) { "Green" } else { "Yellow" })
            foreach ($line in (Get-AgentInstallGuidance -AgentName $agent.name)) {
                Write-Host "  $line" -ForegroundColor Gray
            }
            Write-Host ""
        }
        return
    }

    # Load config and agents
    . "$PSScriptRoot\..\core\config-loader.ps1"
    if (-not (Get-Command Get-AgentDefaults -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\..\core\agent-adapters.ps1"
    }
    $configPath = Join-Path $RepoRoot ".felix\config.json"
    $config = Get-FelixConfig -ConfigFile $configPath
    $agentsFile = Join-Path $RepoRoot ".felix\agents.json"
    
    if (-not (Test-Path $agentsFile)) {
        Write-Error "agents.json not found at: $agentsFile"
        exit 1
    }
    
    $agents = @((Get-Content $agentsFile -Raw | ConvertFrom-Json).agents)
    
    # Normalize legacy 'id' property to 'key' for backward compatibility
    foreach ($a in $agents) {
        if (-not $a.key -and $a.id) {
            $a | Add-Member -NotePropertyName 'key' -NotePropertyValue $a.id -Force
        }
    }
    
    switch ($subCmd) {
        "list" {
            Write-Host ""
            Write-Host "Available Agents:" -ForegroundColor Cyan
            Write-Host ""
            
            foreach ($agent in $agents) {
                $isCurrent = ($agent.key -eq $config.agent.agent_id)
                $marker = if ($isCurrent) { "*" } else { " " }
                $color = if ($isCurrent) { "Green" } else { "White" }
                $provider = if ($agent.PSObject.Properties["provider"]) { $agent.provider } elseif ($agent.PSObject.Properties["adapter"]) { $agent.adapter } else { $null }
                
                Write-Host "$marker Key: $($agent.key) - $($agent.name)" -ForegroundColor $color
                if ($provider) {
                    Write-Host "  Provider: $provider" -ForegroundColor Gray
                }
                Write-Host "  Executable: $($agent.executable)" -ForegroundColor Gray
                Write-Host "  Adapter: $($agent.adapter)" -ForegroundColor Gray
                Write-Host ""
            }
        }
        "current" {
            $currentId = $config.agent.agent_id
            $current = $agents | Where-Object { $_.key -eq $currentId } | Select-Object -First 1
            
            if ($current) {
                $provider = if ($current.PSObject.Properties["provider"]) { $current.provider } elseif ($current.PSObject.Properties["adapter"]) { $current.adapter } else { $null }
                Write-Host ""
                Write-Host "Current Agent:" -ForegroundColor Cyan
                Write-Host "  Key: $($current.key)"
                Write-Host "  Name: $($current.name)"
                if ($provider) {
                    Write-Host "  Provider: $provider"
                }
                Write-Host "  Executable: $($current.executable)"
                Write-Host "  Adapter: $($current.adapter)"
                Write-Host ""
            }
            else {
                Write-Host "No current agent configured (ID: $currentId not found)" -ForegroundColor Red
                exit 1
            }
        }
        "use" {
            $targetValues = @($subArgs)
            $requestedModel = $null
            $modelFlagIndex = [Array]::IndexOf($targetValues, "--model")
            if ($modelFlagIndex -ge 0) {
                $requestedModelValues = if ($modelFlagIndex -lt ($targetValues.Count - 1)) { @($targetValues[($modelFlagIndex + 1)..($targetValues.Count - 1)]) } else { @() }
                $targetValues = if ($modelFlagIndex -gt 0) { @($targetValues[0..($modelFlagIndex - 1)]) } else { @() }
                $requestedModel = Resolve-AgentTargetInput -Values $requestedModelValues
            }

            $target = if ($targetValues.Count -gt 0) { Resolve-AgentTargetInput -Values $targetValues } else { $null }
            $agent = $null

            if (-not $target) {
                $installedAgents = @()
                foreach ($candidate in $agents) {
                    if ($candidate.key -and $candidate.key -match '^ag_[0-9a-f]{9}$') {
                        $installedAgents += $candidate
                    }
                }

                $listAgents = if ($installedAgents.Count -gt 0) { $installedAgents } else { $agents }
                if ($installedAgents.Count -eq 0) {
                    Write-Host "[WARN] No valid agent keys detected in agents.json; showing all." -ForegroundColor Yellow
                }

                Write-Host ""
                Write-Host "Select an agent to use:" -ForegroundColor Cyan
                for ($i = 0; $i -lt $listAgents.Count; $i++) {
                    $label = $listAgents[$i].name
                    if ($listAgents[$i].model) {
                        $label += " (model: $($listAgents[$i].model))"
                    }
                    Write-Host ("  [{0}] {1}" -f ($i + 1), $label)
                }
                $target = Read-Host "Agent number or name"
                if (-not $target) {
                    return
                }

                if ($target -match '^\d+$') {
                    $index = [int]$target
                    if ($index -ge 1 -and $index -le $listAgents.Count) {
                        $agent = $listAgents[$index - 1]
                    }
                }
                else {
                    $agent = $agents | Where-Object { $_.name -eq $target } | Select-Object -First 1
                }
            }
            else {
                # Try as ID first
                if ($target -match '^ag_') {
                    $agent = $agents | Where-Object { $_.key -eq $target } | Select-Object -First 1
                }
                else {
                    # Try as name
                    $agent = $agents | Where-Object { $_.name -eq $target } | Select-Object -First 1
                }
            }
            
            if (-not $agent) {
                Write-Error "Agent not found: $target"
                exit 1
            }

            if ($requestedModel -and -not [string]::Equals([string]$agent.model, $requestedModel, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not (Get-Command New-AgentKey -ErrorAction SilentlyContinue)) {
                    . "$PSScriptRoot\..\core\setup-utils.ps1"
                }

                $adapterType = if ($agent.PSObject.Properties["adapter"] -and $agent.adapter) { $agent.adapter } elseif ($agent.PSObject.Properties["provider"] -and $agent.provider) { $agent.provider } else { $agent.name }
                $provider = if ($agent.PSObject.Properties["provider"] -and $agent.provider) { $agent.provider } else { $adapterType }
                $defaults = Get-AgentDefaults -AdapterType $adapterType

                $agentSettings = @{}
                $exeForKey = if ($agent.executable) { $agent.executable } else { $defaults.executable }
                if ($exeForKey) { $agentSettings["executable"] = $exeForKey }
                $workingDirForKey = if ($agent.working_directory) { $agent.working_directory } else { $defaults.working_directory }
                if ($workingDirForKey) { $agentSettings["working_directory"] = $workingDirForKey }
                $envForKey = if ($agent.environment) { $agent.environment } else { $defaults.environment }
                if ($envForKey) { $agentSettings["environment"] = $envForKey }
                foreach ($defaultKey in $defaults.Keys) {
                    if ($defaultKey -in @("adapter", "executable", "model", "working_directory", "environment")) {
                        continue
                    }

                    $valueForKey = if ($agent.PSObject.Properties[$defaultKey]) { $agent.$defaultKey } else { $defaults[$defaultKey] }
                    if ($null -ne $valueForKey -and -not ($valueForKey -is [string] -and [string]::IsNullOrWhiteSpace($valueForKey))) {
                        $agentSettings[$defaultKey] = $valueForKey
                    }
                }

                $newKey = New-AgentKey -Provider $provider -Model $requestedModel -AgentSettings $agentSettings -ProjectRoot $RepoRoot
                $existingAgent = $agents | Where-Object { $_.key -eq $newKey } | Select-Object -First 1
                if ($existingAgent) {
                    $agent = $existingAgent
                }
                else {
                    $originalAgentKey = $agent.key
                    $agent.model = $requestedModel
                    $agent.key = $newKey
                    if ($agent.PSObject.Properties['id']) {
                        $agent.id = $newKey
                    }

                    for ($i = 0; $i -lt $agents.Count; $i++) {
                        if ($agents[$i].key -eq $originalAgentKey) {
                            $agents[$i] = $agent
                            break
                        }
                    }

                    $agentsConfig = @{ agents = @($agents) }
                    $agentsConfig | ConvertTo-Json -Depth 10 | Set-Content $agentsFile -Encoding UTF8
                }
            }
            
            # Update config.json
            $config.agent.agent_id = $agent.key
            $configPath = Join-Path $RepoRoot ".felix\config.json"
            $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
            
            Write-Host ""
            Write-Host "Switched to agent: $($agent.name) (Key: $($agent.key))" -ForegroundColor Green
            Write-Host ""
        }
        "test" {
            if ($subArgs.Count -eq 0) {
                Write-Error "Usage: felix agent test <id|name>"
                exit 1
            }
            
            $target = Resolve-AgentTargetInput -Values $subArgs
            $agent = $null
            
            # Try as key first
            if ($target -match '^ag_') {
                $agent = $agents | Where-Object { $_.key -eq $target } | Select-Object -First 1
            }
            else {
                # Try as name
                $agent = $agents | Where-Object { $_.name -eq $target } | Select-Object -First 1
            }
            
            if (-not $agent) {
                Write-Error "Agent not found: $target"
                exit 1
            }
            
            Write-Host ""
            Write-Host "Testing agent: $($agent.name)" -ForegroundColor Cyan
            Write-Host ""
            
            # Test 1: Executable exists
            Write-Host "[1/2] Checking executable..." -NoNewline
            try {
                $exePath = Resolve-FelixExecutablePath $agent.executable
                if (-not $exePath) {
                    throw "not found"
                }
                Write-Host " OK" -ForegroundColor Green
                Write-Host "      Path: $exePath" -ForegroundColor Gray
            }
            catch {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Host "      Executable '$($agent.executable)' not found in PATH" -ForegroundColor Red
                exit 1
            }
            
            # Test 2: Simple version check
            Write-Host "[2/2] Checking version..." -NoNewline
            try {
                $versionArgs = @("--version")
                $versionOutput = & $exePath @versionArgs 2>&1 | Out-String
                Write-Host " OK" -ForegroundColor Green
                Write-Host "      $($versionOutput.Trim())" -ForegroundColor Gray
            }
            catch {
                Write-Host " SKIPPED" -ForegroundColor Yellow
                Write-Host "      (version check not supported)" -ForegroundColor Gray
            }
            
            Write-Host ""
            Write-Host "Agent test passed!" -ForegroundColor Green
            Write-Host ""
        }
        "register" {
            # Load sync and setup utilities
            $felixEngineRoot = if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { Split-Path -Parent $PSScriptRoot }
            . "$felixEngineRoot\core\sync-interface.ps1"
            . "$felixEngineRoot\core\setup-utils.ps1"

            $felixDir = Join-Path $RepoRoot ".felix"
            $reporter = Get-RunReporter -FelixDir $felixDir
            $syncActive = $reporter.GetType().Name -ne "NoOpReporter"

            # ── Resolve URL and API key ──────────────────────────────────────
            $targetUrl = if ($syncActive) {
                $reporter.BaseUrl
            }
            elseif ($env:FELIX_SYNC_URL) {
                $env:FELIX_SYNC_URL
            }
            elseif ($config.sync -and $config.sync.base_url) {
                $config.sync.base_url
            }
            else {
                "http://localhost:8080"
            }

            $apiKey = if ($syncActive) {
                $reporter.ApiKey
            }
            elseif ($env:FELIX_SYNC_KEY) {
                $env:FELIX_SYNC_KEY
            }
            elseif ($config.sync -and $config.sync.api_key) {
                $config.sync.api_key
            }
            else {
                $null
            }

            # ── Prompt when sync is disabled ─────────────────────────────────
            if (-not $syncActive) {
                $keyDisplay = if ($apiKey) { ($apiKey.Substring(0, [Math]::Min(12, $apiKey.Length))) + "..." } else { "(none)" }
                Write-Host ""
                Write-Host "Sync is not enabled in this project." -ForegroundColor Yellow
                Write-Host "  Target URL : $targetUrl" -ForegroundColor Gray
                Write-Host "  API key    : $keyDisplay" -ForegroundColor Gray
                Write-Host ""
                $answer = Read-Host "Attempt registration anyway? (y/N)"
                if ($answer -notmatch '^[Yy]$') {
                    Write-Host "Cancelled." -ForegroundColor Gray
                    Write-Host ""
                    exit 0
                }
            }

            # ── Allow key override before attempting ─────────────────────────
            $keyDisplay = if ($apiKey) { ($apiKey.Substring(0, [Math]::Min(12, $apiKey.Length))) + "..." } else { "(none - will attempt without key)" }
            Write-Host ""
            Write-Host "  URL : $targetUrl" -ForegroundColor Gray
            Write-Host "  Key : $keyDisplay" -ForegroundColor Gray
            Write-Host ""
            $override = Read-Host "Press Enter to use the above key, or paste a new API key"
            if (-not [string]::IsNullOrWhiteSpace($override)) {
                $apiKey = $override.Trim()
                Write-Host "  Using provided key." -ForegroundColor Gray
            }

            # ── Build one-shot reporter if sync is disabled ──────────────────
            if (-not $syncActive) {
                $pluginPath = Join-Path $felixDir "plugins\sync-http\http-client.ps1"
                if (-not (Test-Path $pluginPath)) {
                    Write-Host "Sync plugin not found at: $pluginPath" -ForegroundColor Red
                    exit 1
                }
                . $pluginPath
                $reporter = New-PluginReporter -Config @{ base_url = $targetUrl; api_key = $apiKey } -FelixDir $felixDir
            }
            elseif (-not [string]::IsNullOrWhiteSpace($override)) {
                # Sync is active but user supplied a different key — rebuild reporter
                $pluginPath = Join-Path $felixDir "plugins\sync-http\http-client.ps1"
                . $pluginPath
                $reporter = New-PluginReporter -Config @{ base_url = $targetUrl; api_key = $apiKey } -FelixDir $felixDir
            }

            $currentId = $config.agent.agent_id
            $agentConfig = $agents | Where-Object { $_.key -eq $currentId } | Select-Object -First 1
            if (-not $agentConfig) {
                Write-Error "Current agent (ID: $currentId) not found in agents.json"
                exit 1
            }

            Write-Host "Registering agent '$($agentConfig.name)'..." -ForegroundColor Cyan

            $syncAgentInfo = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $RepoRoot -Source "felix agent register"

            if (-not $syncAgentInfo.ContainsKey("git_url")) {
                Write-Host "[WARN] No git remote 'origin' found - registration may fail with API key auth" -ForegroundColor Yellow
            }

            $result = $reporter.RegisterAgent($syncAgentInfo)
            if ($result.Success) {
                Write-Host "[+] Agent registered successfully (key: $agentKey)" -ForegroundColor Green
                Write-Host ""
            }
            else {
                Write-Host "[-] Registration failed." -ForegroundColor Red
                if ($result.Error) {
                    Write-Host "    $($result.Error)" -ForegroundColor Red
                }
                Write-Host "    Run 'felix agent register' again to supply a different key." -ForegroundColor Gray
                Write-Host ""
                exit 1
            }
        }
        default {
            Write-Error "Unknown agent subcommand: $subCmd. Use: list, current, use, test, setup, register"
            exit 1
        }
    }
}

# Load shared setup utilities
. (Join-Path (Split-Path $PSScriptRoot -Parent) "core\setup-utils.ps1")

function Invoke-Setup {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    Write-Host "`n====================================" -ForegroundColor Cyan
    Write-Host " Felix CLI Setup Wizard" -ForegroundColor Cyan
    Write-Host "====================================`n" -ForegroundColor Cyan

    # ── Step 1: Confirm project folder ────────────────────────────────────────
    Write-Host "Project Folder" -ForegroundColor White
    Write-Host "  Current: $RepoRoot" -ForegroundColor Gray
    $folderInput = Read-Host "  Press Enter to use this folder, or enter a different path"
    if ($folderInput -and $folderInput.Trim()) {
        $resolved = Resolve-Path $folderInput.Trim() -ErrorAction SilentlyContinue
        if ($resolved -and (Test-Path $resolved.Path)) {
            $RepoRoot = $resolved.Path
            Write-Host "  Using: $RepoRoot" -ForegroundColor Green
        } else {
            Write-Host "  Path not found - using current folder" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Using: $RepoRoot" -ForegroundColor Green
    }
    Write-Host ""

    # ── Scaffold .felix/ project files (idempotent — safe to re-run) ──────────
    #
    # For files with engine-provided defaults (policies, prompts) we copy from
    # $FelixRoot (the installed or local engine dir) rather than hardcoding
    # content here. Data files (requirements.json, state.json, config.json) are
    # project-specific and created with minimal stubs.
    # Never overwrites files that already exist.
    #
    $felixDir = Join-Path $RepoRoot ".felix"
    $isNewProject = -not (Test-Path $felixDir)
    $scaffolded = @()    # files created
    $skipped   = @()    # files already present

    if ($isNewProject) {
        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null
    }

    # Helper: copy a file from the engine dir if it exists there and not in dest
    # (defined at module scope above — called with explicit FelixRoot/FelixDir)

    # requirements.json — empty object with requirements array (project-specific, no engine default)
    $reqPath = Join-Path $felixDir "requirements.json"
    if (-not (Test-Path $reqPath)) {
        '{ "requirements": [] }' | Set-Content $reqPath -Encoding UTF8
        $scaffolded += "requirements.json"
    } else { $skipped += "requirements.json" }

    # state.json — empty object (project-specific, no engine default)
    $statePath = Join-Path $felixDir "state.json"
    if (-not (Test-Path $statePath)) {
        "{}" | Set-Content $statePath -Encoding UTF8
        $scaffolded += "state.json"
    } else { $skipped += "state.json" }

    # config.json — copy from config.json.example template from engine dir
    $configStubPath = Join-Path $felixDir "config.json"
    $configExampleSourcePath = Join-Path $FelixRoot "config.json.example"
    if (-not (Test-Path $configStubPath)) {
        if (Test-Path $configExampleSourcePath) {
            # Use example from engine dir as template
            $exampleContent = Get-Content $configExampleSourcePath -Raw
            $exampleContent | Set-Content $configStubPath -Encoding UTF8
            $scaffolded += "config.json (from engine template)"
        } else {
            # Fallback to minimal hardcoded structure if no example exists in engine
            [ordered]@{
                agent = [ordered]@{ agent_id = $null }
                sync  = [ordered]@{
                    enabled  = $false
                    provider = "http"
                    base_url = "http://localhost:8080"
                    api_key  = $null
                }
            } | ConvertTo-Json -Depth 10 | Set-Content $configStubPath -Encoding UTF8
            $scaffolded += "config.json"
        }
    } else { $skipped += "config.json" }

    # config.json.example — copy from engine dir; serves as template for config
    if (Copy-EngineFile -FelixRoot $FelixRoot -FelixDir $felixDir -RelPath "config.json.example") {
        $scaffolded += "config.json.example (template)"
    } else { $skipped += "config.json.example (template)" }

    # policies/ — copy from engine dir; contains allowlist.json and denylist.json
    foreach ($policyFile in @("policies\allowlist.json", "policies\denylist.json")) {
        if (Copy-EngineFile -FelixRoot $FelixRoot -FelixDir $felixDir -RelPath $policyFile) {
            $scaffolded += $policyFile.Replace('\', '/')
        } else { $skipped += $policyFile.Replace('\', '/') }
    }

    # specs/ — where requirement spec files live
    $specsDir = Join-Path $RepoRoot "specs"
    if (-not (Test-Path $specsDir)) {
        New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
        $scaffolded += "specs/"
    } else { $skipped += "specs/" }

    # runs/ — where run artifacts are stored
    $runsDir = Join-Path $RepoRoot "runs"
    if (-not (Test-Path $runsDir)) {
        New-Item -ItemType Directory -Path $runsDir -Force | Out-Null
        $scaffolded += "runs/"
    } else { $skipped += "runs/" }

    # .gitignore — add Felix entries if not already present
    $gitignorePath = Join-Path $RepoRoot ".gitignore"
    $felixIgnoreLines = @(
        "",
        "# Felix local files (machine-specific, may contain API keys)",
        ".felix/config.json",
        ".felix/state.json",
        ".felix/outbox/",
        ".felix/sync.log",
        ".felix/spec-manifest.json",
        "# Felix .meta.json sidecars (server-generated cache, gitignored)",
        "specs/*.meta.json"
    )
    $felixIgnoreBlock = $felixIgnoreLines -join "`n"
    if (Test-Path $gitignorePath) {
        $existing = Get-Content $gitignorePath -Raw
        if ($existing -notmatch '\.felix/config\.json') {
            Add-Content $gitignorePath $felixIgnoreBlock -Encoding UTF8
            $scaffolded += ".gitignore (updated)"
        } else { $skipped += ".gitignore" }
    } else {
        ($felixIgnoreLines | Select-Object -Skip 1) -join "`n" | Set-Content $gitignorePath -Encoding UTF8
        $scaffolded += ".gitignore (created)"
    }

    $label = if ($isNewProject) { "Initialized new Felix project" } else { "Project files" }
    Write-Host "${label}:" -ForegroundColor Cyan
    foreach ($item in $scaffolded) {
        Write-Host "  + $item" -ForegroundColor Green
    }
    foreach ($item in $skipped) {
        Write-Host "  - $item (already exists)" -ForegroundColor DarkGray
    }
    Write-Host "  Engine: $FelixRoot" -ForegroundColor Gray
    Write-Host ""


    # Load existing config
    $configPath = Join-Path $RepoRoot ".felix\config.json"
    $config = $null
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Could not parse existing config: $($_.Exception.Message)"
        }
    }

    # Initialize config if not exists or failed to load
    if (-not $config) {
        $config = @{
            agent = @{ agent_id = $null }
            sync  = @{
                enabled  = $false
                provider = "fastapi"
                base_url = "http://localhost:8080"
                api_key  = $null
            }
        }
    }

    # Ensure sync section exists
    if (-not $config.sync) {
        $config | Add-Member -NotePropertyName sync -NotePropertyValue @{
            enabled  = $false
            provider = "fastapi"
            base_url = "http://localhost:8080"
            api_key  = $null
        }
    }

    # Ensure required sync properties exist with defaults
    if (-not $config.sync.base_url) {
        $config.sync | Add-Member -NotePropertyName base_url -NotePropertyValue "http://localhost:8080" -Force
    }
    if (-not $config.sync.provider) {
        $config.sync | Add-Member -NotePropertyName provider -NotePropertyValue "http" -Force
    }
    if (-not ($config.sync.PSObject.Properties.Name -contains "enabled")) {
        $config.sync | Add-Member -NotePropertyName enabled -NotePropertyValue $false -Force
    }
    if (-not ($config.sync.PSObject.Properties.Name -contains "api_key")) {
        $config.sync | Add-Member -NotePropertyName api_key -NotePropertyValue $null -Force
    }

    # Ensure backpressure section exists
    if (-not $config.PSObject.Properties['backpressure']) {
        $config | Add-Member -NotePropertyName backpressure -NotePropertyValue ([pscustomobject]@{
            enabled     = $false
            commands    = @()
            max_retries = 3
        }) -Force
    }

    # Ensure executor section exists
    if (-not $config.PSObject.Properties['executor']) {
        $config | Add-Member -NotePropertyName executor -NotePropertyValue ([pscustomobject]@{
            max_iterations = 20
            default_mode   = "planning"
            commit_on_complete = $true
        }) -Force
    }

    # ── Project section ────────────────────────────────────────────────────────
    Write-Host "Project Directory" -ForegroundColor White
    Write-Host "  $RepoRoot" -ForegroundColor Gray
    Write-Host ""

    # Check AGENTS.md
    $agentsMdPath = Join-Path $RepoRoot "AGENTS.md"
    if (-not (Test-Path $agentsMdPath)) {
        Write-Host "  [WARN] AGENTS.md not found - agents won't have project context" -ForegroundColor Yellow
        $createAgents = Read-Host "  Create a stub AGENTS.md? (Y/n)"
        if ($createAgents -ne 'n' -and $createAgents -ne 'N') {
            $agentsStub = "# Agents - How to Operate This Repository`n`n## Install Dependencies`n`n<!-- Describe how to install project dependencies -->`n`n## Run Tests`n`n<!-- Describe how to run the test suite -->`n`n## Build the Project`n`n<!-- Describe how to build the project -->`n`n## Start the Application`n`n<!-- Describe how to start the application -->`n"
            $agentsStub | Set-Content $agentsMdPath -Encoding UTF8
            Write-Host "  Created AGENTS.md - fill it in so agents understand your project" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  AGENTS.md found" -ForegroundColor Green
    }
    Write-Host ""

    # ── Agent configuration ────────────────────────────────────────────────────
    # Load agent-setup module and offer to configure agents
    . (Join-Path (Split-Path $PSScriptRoot -Parent) "core\agent-setup.ps1")
    
    $configureAgents = Read-Host "Configure LLM agents for this project? (Y/n)"
    if ($configureAgents -ne 'n' -and $configureAgents -ne 'N') {
        Invoke-AgentSetup -ProjectRoot $RepoRoot -FelixRoot $FelixRoot | Out-Null
    }
    Write-Host ""

    # Check for common project dependency files
    $depChecks = @(
        @{ File = "requirements.txt";  Label = "Python (requirements.txt)" }
        @{ File = "pyproject.toml";    Label = "Python (pyproject.toml)" }
        @{ File = "package.json";      Label = "Node.js (package.json)" }
        @{ File = "go.mod";            Label = "Go (go.mod)" }
        @{ File = "Cargo.toml";        Label = "Rust (Cargo.toml)" }
        @{ File = "Gemfile";           Label = "Ruby (Gemfile)" }
        @{ File = "pom.xml";           Label = "Java/Maven (pom.xml)" }
        @{ File = "build.gradle";      Label = "Java/Gradle (build.gradle)" }
    )
    $foundDeps = @()
    foreach ($dep in $depChecks) {
        if (Test-Path (Join-Path $RepoRoot $dep.File)) {
            $foundDeps += $dep.Label
        }
    }
    if ($foundDeps.Count -gt 0) {
        Write-Host "  Detected: $($foundDeps -join ', ')" -ForegroundColor Gray
    }
    else {
        Write-Host "  [WARN] No recognised dependency file found in project root" -ForegroundColor Yellow
    }

    Write-Host ""

    # ── Agent selection ────────────────────────────────────────────────────────
    Write-Host "Agent" -ForegroundColor White

    $knownAgents = @(
        @{ Id = 0; Name = "droid";   Exe = "droid";  Desc = "Factory.ai Droid" }
        @{ Id = 1; Name = "claude";  Exe = "claude"; Desc = "Anthropic Claude Code" }
        @{ Id = 2; Name = "codex";   Exe = "codex";  Desc = "OpenAI Codex CLI" }
        @{ Id = 3; Name = "gemini";  Exe = "gemini"; Desc = "Google Gemini CLI" }
    )

    $currentAgentId = if ($config.agent.agent_id) { $config.agent.agent_id } else { $null }

    foreach ($a in $knownAgents) {
        $available = $null -ne (Get-Command $a.Exe -ErrorAction SilentlyContinue)
        $marker    = if ($available) { "[installed]" } else { "[not found]" }
        $color     = if ($available) { "Gray" } else { "DarkGray" }
        $current   = if ($currentAgentId -eq $a.Id -or $currentAgentId -eq $a.Name) { " <-- current" } else { "" }
        Write-Host ("  {0,2}  {1,-8} {2,-12} {3}{4}" -f $a.Id, $a.Name, $marker, $a.Desc, $current) -ForegroundColor $color
    }

    $agentInput = Read-Host "  Enter agent number (0-3) or press Enter to keep current"
    if ($agentInput -and $agentInput.Trim() -match '^\d$') {
        $chosen = $knownAgents | Where-Object { $_.Id -eq [int]$agentInput.Trim() }
        if ($chosen) {
            $config.agent.agent_id = $chosen.Id
            Write-Host "  Agent set to: $($chosen.Name)" -ForegroundColor Green
        }
    }
    Write-Host ""

    # ── Test / backpressure command ────────────────────────────────────────────
    Write-Host "Test Command (backpressure)" -ForegroundColor White
    $currentCmd = ""
    if ($config.backpressure.commands -and $config.backpressure.commands.Count -gt 0) {
        $currentCmd = $config.backpressure.commands[0]
    }
    if ($currentCmd) {
        Write-Host "  Current: $currentCmd" -ForegroundColor Gray
    }
    else {
        Write-Host "  Not set - agents won't run tests to validate their work" -ForegroundColor Yellow
    }
    $newCmd = Read-Host "  Enter test command (e.g. 'pytest' or 'npm test') or press Enter to keep current"
    if ($newCmd -and $newCmd.Trim()) {
        $config.backpressure.enabled  = $true
        $config.backpressure.commands = @($newCmd.Trim())
        Write-Host "  Test command saved" -ForegroundColor Green
    }
    Write-Host ""

    # ── Mode: local vs remote ─────────────────────────────────────────────────
    Write-Host "Mode" -ForegroundColor White
    $currentMode = if ($config.sync.enabled) { "remote" } else { "local" }
    Write-Host "  Current: $currentMode" -ForegroundColor Gray
    Write-Host "  [1] local  - runs saved locally only (default)" -ForegroundColor Gray
    Write-Host "  [2] remote - sync runs and specs to Felix backend" -ForegroundColor Gray
    Write-Host ""
    $modeInput = Read-Host "  Enter choice [1/2] or press Enter to keep current ($currentMode)"
    $remoteMode = $false
    switch ($modeInput.Trim()) {
        "1" { $remoteMode = $false }
        "2" { $remoteMode = $true }
        default { $remoteMode = ($currentMode -eq "remote") }
    }
    Write-Host ""

    # ── Sync / backend (remote mode only) ────────────────────────────────────
    if ($remoteMode) {
        # Prompt for backend URL
        Write-Host "Backend URL" -ForegroundColor White
        Write-Host "  Current: $($config.sync.base_url)" -ForegroundColor Gray
        $newUrl = Read-Host "  Enter backend URL (press Enter to keep current)"
        if ($newUrl -and $newUrl.Trim()) {
            $config.sync.base_url = $newUrl.Trim().TrimEnd("/")
        }

        # Prompt for API key
        Write-Host "`nAPI Key" -ForegroundColor White
        Write-Host "  Generate a key at: $($config.sync.base_url)/settings" -ForegroundColor Gray
        if ($config.sync.api_key) {
            Write-Host "  Current key: $($config.sync.api_key.Substring(0, [Math]::Min(12, $config.sync.api_key.Length)))..." -ForegroundColor Gray
        }
        $newKey = Read-Host "  Paste your API key starting with fsk_ or press Enter to keep current"

        if (-not $newKey -or -not $newKey.Trim()) {
            if ($config.sync.api_key) {
                Write-Host "`n  Keeping existing API key" -ForegroundColor Gray
                $newKey = $config.sync.api_key
            }
            else {
                Write-Host "`nNo API key provided - sync will be disabled" -ForegroundColor Yellow
                $config.sync.enabled = $false
                $config.sync.api_key = $null
                $newKey = $null
            }
        }
        else {
            $newKey = $newKey.Trim()
        }

        if ($newKey) {
            if (-not $newKey.StartsWith("fsk_")) {
                Write-Host "`nInvalid API key format - expected key starting with fsk_" -ForegroundColor Yellow
                Write-Host "   Clearing API key and disabling sync" -ForegroundColor Gray
                $config.sync.api_key = $null
                $config.sync.enabled = $false
                $newKey = $null
            }

            if ($newKey) {
                Write-Host "`nValidating API key..." -ForegroundColor Cyan
                try {
                    $validateUrl = "$($config.sync.base_url)/api/keys/validate"
                    $headers = @{ "Authorization" = "Bearer $newKey" }
                    $response = Invoke-RestMethod -Uri $validateUrl -Method Get -Headers $headers -ErrorAction Stop

                    Write-Host "Valid API key!" -ForegroundColor Green
                    Write-Host "   Project: $($response.project_name) [$($response.project_id)]" -ForegroundColor Gray
                    Write-Host "   Organization: $($response.org_id)" -ForegroundColor Gray
                    Show-ApiKeyExpiration -ExpiresAt $response.expires_at

                    $config.sync.api_key = $newKey
                    $config.sync.enabled = $true
                }
                catch {
                    Write-Host "API key validation failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "   Check backend URL and key, then try again" -ForegroundColor Gray
                    Write-Host "   Clearing API key and disabling sync" -ForegroundColor Gray
                    $config.sync.api_key = $null
                    $config.sync.enabled = $false
                }
            }
        }
    }
    else {
        # Local mode — disable sync, preserve any existing URL/key in config
        $config.sync.enabled = $false
        Write-Host "Running in local mode - runs will only be saved locally." -ForegroundColor Gray
        Write-Host "  To enable sync later, run 'felix setup' again and choose remote," -ForegroundColor DarkGray
        Write-Host "  or pass --sync to a single run: 'felix run S-0001 --sync'" -ForegroundColor DarkGray
        Write-Host ""
    }

    # Save config
    Write-Host "`nSaving configuration..." -ForegroundColor Cyan

    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
        Write-Host "Configuration saved to .felix\config.json" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to save configuration: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    # ── Pull requirements from server (remote + sync enabled only) ────────────
    if ($remoteMode -and $config.sync.enabled) {
        Write-Host ""
        Write-Host "Pull Requirements" -ForegroundColor White
        Write-Host "  Download specs and register them in requirements.json?" -ForegroundColor Gray
        $pullInput = Read-Host "  [y/N]"
        if ($pullInput.Trim() -match '^[Yy]') {
            Write-Host ""
            felix spec pull
            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                felix spec fix
            }
        }
        Write-Host ""
    }

    Write-Host "`n====================================" -ForegroundColor Cyan
    Write-Host " Setup Complete!" -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Cyan

    if ($config.sync.enabled) {
        Write-Host "`nSync enabled - runs will mirror to backend" -ForegroundColor Green
        Write-Host "   Run: felix run <requirement-id>" -ForegroundColor Gray
    }
    else {
        Write-Host "`nSync disabled - runs will only save locally" -ForegroundColor Yellow
        Write-Host "   Run felix setup again to enable sync" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Output "Setup complete."
}

#!/usr/bin/env pwsh
<#
.SYNOPSIS
Felix CLI dispatcher - unified command interface

.DESCRIPTION
Routes commands to appropriate Felix scripts with consistent interface.

.PARAMETER Command
The command to execute: run, loop, status, list, validate, version, help

.PARAMETER Arguments
Command-specific arguments and global flags

.EXAMPLE
.felix\felix.ps1 run S-0001

.EXAMPLE
.felix\felix.ps1 loop --max-iterations 5

.EXAMPLE
.felix\felix.ps1 status S-0001 --format json

.EXAMPLE
.felix\felix.ps1 list --status planned

.EXAMPLE
.felix\felix.ps1 validate S-0001
#>

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet("run", "loop", "status", "list", "validate", "deps", "spec", "context", "agent", "procs", "tui", "version", "help")]
    [string]$Command = "help",

    [Parameter(Mandatory = $false, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"

# Determine repository root (parent of .felix folder)
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Parse global flags
$Format = "rich"
$VerboseMode = $false
$Quiet = $false
$NoStats = $false

$remainingArgs = @()
$i = 0
while ($i -lt $Arguments.Count) {
    switch ($Arguments[$i]) {
        "--format" {
            $i++
            $Format = $Arguments[$i]
        }
        "--verbose" {
            $VerboseMode = $true
        }
        "--quiet" {
            $Quiet = $true
        }
        "--no-stats" {
            $NoStats = $true
        }
        default {
            $remainingArgs += $Arguments[$i]
        }
    }
    $i++
}

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
        return (Get-Command $Executable -ErrorAction Stop).Source
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

    # Windows npm global shim directory is usually %APPDATA%\npm (and equals `npm prefix -g` on Windows).
    if ($env:APPDATA) {
        $candidateRoots += (Join-Path $env:APPDATA "npm")
    }

    # Try npm global prefix if npm is installed, even if its shim dir is not in PATH.
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

    # Load config and agents
    . "$PSScriptRoot\core\config-loader.ps1"
    $configPath = Join-Path $RepoRoot ".felix\config.json"
    $config = Get-FelixConfig -ConfigFile $configPath
    $agentsFile = Join-Path $RepoRoot ".felix\agents.json"
    
    if (-not (Test-Path $agentsFile)) {
        Write-Error "agents.json not found at: $agentsFile"
        exit 1
    }
    
    $agents = (Get-Content $agentsFile -Raw | ConvertFrom-Json).agents
    
    if (-not $AgentArgs -or $AgentArgs.Count -eq 0) {
        Write-Error "Usage: felix agent <list|current|use|test> [args]"
        exit 1
    }
    
    $subCmd = $AgentArgs[0]
    $subArgs = $AgentArgs[1..($AgentArgs.Count - 1)]
    
    switch ($subCmd) {
        "list" {
            Write-Host ""
            Write-Host "Available Agents:" -ForegroundColor Cyan
            Write-Host ""
            
            foreach ($agent in $agents) {
                $isCurrent = ($agent.id -eq $config.agent.agent_id)
                $marker = if ($isCurrent) { "*" } else { " " }
                $color = if ($isCurrent) { "Green" } else { "White" }
                
                Write-Host "$marker ID: $($agent.id) - $($agent.name)" -ForegroundColor $color
                Write-Host "  Executable: $($agent.executable)" -ForegroundColor Gray
                Write-Host "  Adapter: $($agent.adapter)" -ForegroundColor Gray
                Write-Host "  Description: $($agent.description)" -ForegroundColor Gray
                Write-Host ""
            }
        }
        "current" {
            $currentId = $config.agent.agent_id
            $current = $agents | Where-Object { $_.id -eq $currentId } | Select-Object -First 1
            
            if ($current) {
                Write-Host ""
                Write-Host "Current Agent:" -ForegroundColor Cyan
                Write-Host "  ID: $($current.id)"
                Write-Host "  Name: $($current.name)"
                Write-Host "  Executable: $($current.executable)"
                Write-Host "  Adapter: $($current.adapter)"
                Write-Host "  Description: $($current.description)"
                Write-Host ""
            }
            else {
                Write-Host "No current agent configured (ID: $currentId not found)" -ForegroundColor Red
                exit 1
            }
        }
        "use" {
            if ($subArgs.Count -eq 0) {
                Write-Error "Usage: felix agent use <id|name>"
                exit 1
            }
            
            $target = $subArgs[0]
            $agent = $null
            
            # Try as ID first
            if ($target -match '^\d+$') {
                $agent = $agents | Where-Object { $_.id -eq [int]$target } | Select-Object -First 1
            }
            else {
                # Try as name
                $agent = $agents | Where-Object { $_.name -eq $target } | Select-Object -First 1
            }
            
            if (-not $agent) {
                Write-Error "Agent not found: $target"
                exit 1
            }
            
            # Verify executable exists
            try {
                $resolvedPath = Resolve-FelixExecutablePath $agent.executable
                if (-not $resolvedPath) {
                    throw "not found"
                }
            }
            catch {
                Write-Warning "Executable '$($agent.executable)' not found in PATH"
                Write-Warning "Install the agent CLI before using it:"
                switch ($agent.name) {
                    "claude" { Write-Host "  npm install -g @anthropic-ai/claude-code" -ForegroundColor Gray }
                    "codex" { Write-Host "  npm install -g @openai/codex-cli" -ForegroundColor Gray }
                    "gemini" { Write-Host "  pip install google-gemini-cli" -ForegroundColor Gray }
                    "droid" { Write-Host "  npm install -g @factory-ai/droid-cli" -ForegroundColor Gray }
                }
                
                $response = Read-Host "Continue anyway? (y/N)"
                if ($response -ne "y") {
                    exit 1
                }
            }
            
            # Update config.json
            $config.agent.agent_id = $agent.id
            $configPath = Join-Path $RepoRoot ".felix\config.json"
            $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
            
            Write-Host ""
            Write-Host "Switched to agent: $($agent.name) (ID: $($agent.id))" -ForegroundColor Green
            Write-Host ""
        }
        "test" {
            if ($subArgs.Count -eq 0) {
                Write-Error "Usage: felix agent test <id|name>"
                exit 1
            }
            
            $target = $subArgs[0]
            $agent = $null
            
            # Try as ID first
            if ($target -match '^\d+$') {
                $agent = $agents | Where-Object { $_.id -eq [int]$target } | Select-Object -First 1
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
        default {
            Write-Error "Unknown agent subcommand: $subCmd. Use: list, current, use, test"
            exit 1
        }
    }
}

function Invoke-Context {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    
    # Load context-builder module
    . "$PSScriptRoot\core\context-builder.ps1"
    
    # Load dependencies
    . "$PSScriptRoot\core\config-loader.ps1"
    . "$PSScriptRoot\core\emit-event.ps1"
    
    if (-not $Args -or $Args.Count -eq 0) {
        Write-Host ""
        Write-Host "Usage: felix context <build|show> [options]" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Subcommands:" -ForegroundColor Yellow
        Write-Host "  build [options]       Analyze project and generate CONTEXT.md"
        Write-Host "  show                  Display current CONTEXT.md content"
        Write-Host ""
        Write-Host "Options for 'build':" -ForegroundColor Yellow
        Write-Host "  --include-hidden      Include hidden files/folders in analysis"
        Write-Host "  --force               Skip overwrite confirmation"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix context build"
        Write-Host "  felix context build --include-hidden"
        Write-Host "  felix context build --force"
        Write-Host "  felix context show"
        Write-Host ""
        exit 0
    }
    
    $subCmd = $Args[0]
    
    switch ($subCmd) {
        "build" {
            # Parse flags
            $includeHidden = $false
            $force = $false
            
            for ($i = 1; $i -lt $Args.Count; $i++) {
                switch ($Args[$i]) {
                    "--include-hidden" { $includeHidden = $true }
                    "--force" { $force = $true }
                }
            }
            
            Write-Host ""
            Write-Host "=== Felix Context Builder ===" -ForegroundColor Cyan
            Write-Host "Project: $RepoRoot" -ForegroundColor Gray
            Write-Host ""
            
            # Load configuration
            $configPath = Join-Path $RepoRoot ".felix\config.json"
            $agentsFile = Join-Path $RepoRoot ".felix\agents.json"
            $config = Get-FelixConfig -ConfigFile $configPath
            $agentConfig = Get-AgentsConfiguration -AgentsJsonFile $agentsFile
            $paths = @{
                ProjectPath = $RepoRoot
                FelixDir    = Join-Path $RepoRoot ".felix"
                SpecsDir    = Join-Path $RepoRoot "specs"
                PromptsDir  = Join-Path $RepoRoot ".felix\prompts"
                AgentsFile  = Join-Path $RepoRoot "AGENTS.md"
            }
            
            # Execute builder
            $result = Invoke-ContextBuilder `
                -ProjectPath $RepoRoot `
                -IncludeHidden:$includeHidden `
                -Force:$force `
                -Config $config `
                -AgentConfig $agentConfig `
                -Paths $paths
            
            exit $result.ExitCode
        }
        
        "show" {
            $contextPath = Join-Path $RepoRoot "CONTEXT.md"
            if (-not (Test-Path $contextPath)) {
                Write-Host ""
                Write-Host "CONTEXT.md not found" -ForegroundColor Yellow
                Write-Host "Run 'felix context build' to generate it" -ForegroundColor Gray
                Write-Host ""
                exit 1
            }
            
            $content = Get-Content $contextPath -Raw
            Write-Host $content
        }
        
        default {
            Write-Error "Unknown context subcommand: $subCmd"
            Write-Host "Usage: felix context <build|show> [options]"
            Write-Host ""
            Write-Host "Options for 'build':"
            Write-Host "  --include-hidden    Include hidden files/folders in analysis"
            Write-Host "  --force             Skip overwrite confirmation"
            exit 1
        }
    }
}

function Invoke-ProcessList {
    param([string[]]$Arguments)
    
    # Load session manager
    . "$PSScriptRoot\core\session-manager.ps1"
    
    $subCmd = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments[0] } else { "list" }
    
    # Handle array extraction carefully - PowerShell unwraps single-element @() arrays
    # Use ArrayList.ToArray() to force proper array creation for single element
    $subArgs = if ($Arguments.Count -eq 2) {
        # Single argument after command - use ArrayList to force proper array
        $temp = [System.Collections.ArrayList]@()
        $null = $temp.Add($Arguments[1])
        , $temp.ToArray()
    }
    elseif ($Arguments.Count -gt 2) {
        # Multiple arguments - range operator works fine
        $Arguments[1..($Arguments.Count - 1)]
    }
    else {
        @()
    }
    
    switch ($subCmd) {
        "list" {
            $sessions = Get-ActiveSessions -ProjectPath $RepoRoot
            
            if ($sessions.Count -eq 0) {
                Write-Host ""
                Write-Host "No active sessions" -ForegroundColor Gray
                Write-Host ""
                exit 0
            }
            
            Write-Host ""
            Write-Host "Active Sessions:" -ForegroundColor Cyan
            Write-Host ""
            
            # Show sessions in table format
            $sessions | ForEach-Object {
                $duration = (Get-Date).ToUniversalTime() - [DateTime]::Parse($_.start_time)
                $durationStr = if ($duration.TotalHours -ge 1) {
                    "{0:hh\:mm\:ss}" -f $duration
                }
                else {
                    "{0:mm\:ss}" -f $duration
                }
                
                Write-Host "  Session: $($_.session_id)" -ForegroundColor Yellow
                Write-Host "  Requirement: $($_.requirement_id)" -ForegroundColor White
                Write-Host "  Agent: $($_.agent)" -ForegroundColor Gray
                Write-Host "  PID: $($_.pid)" -ForegroundColor Gray
                Write-Host "  Duration: $durationStr" -ForegroundColor Gray
                Write-Host "  Status: $($_.status)" -ForegroundColor $(if ($_.status -eq "running") { "Green" } else { "Yellow" })
                Write-Host ""
            }
            
            Write-Host "Commands:" -ForegroundColor Cyan
            Write-Host "  felix procs kill <session-id>    Terminate a session"
            Write-Host ""
        }
        "kill" {
            if ($subArgs.Count -eq 0) {
                Write-Error "Usage: felix procs kill <session-id>"
                Write-Host ""
                Write-Host "Tip: Use 'felix procs list' to see active sessions"
                Write-Host ""
                exit 1
            }
            
            $sessionId = $subArgs[0]
            
            Write-Host ""
            Write-Host "Terminating session: $sessionId" -ForegroundColor Yellow
            Write-Host ""
            
            $success = Stop-Session -SessionId $sessionId -ProjectPath $RepoRoot
            
            if ($success) {
                Write-Host "Session terminated successfully" -ForegroundColor Green
                Write-Host ""
            }
            else {
                Write-Host "Failed to terminate session" -ForegroundColor Red
                Write-Host ""
                exit 1
            }
        }
        default {
            Write-Error "Unknown procs subcommand: $subCmd"
            Write-Host "Usage: felix procs <list|kill> [args]"
            exit 1
        }
    }
}

function Invoke-Run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix run <requirement-id> [--format <json|plain|rich>]"
        exit 1
    }

    $requirementId = $Args[0]
    $formatValue = $Format  # Use script-level default
    $syncEnabled = $false
    
    # Parse optional flags
    for ($i = 1; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--format" -and ($i + 1) -lt $Args.Count) {
            $formatValue = $Args[$i + 1]
            $i++  # Skip the format value
        }
        elseif ($Args[$i] -eq "--sync") {
            $syncEnabled = $true
        }
    }

    # Execute felix-cli.ps1 which spawns agent internally
    if ($NoStats) {
        & "$PSScriptRoot\felix-cli.ps1" -ProjectPath $RepoRoot -RequirementId $requirementId -Format $formatValue -NoStats -VerboseMode:$VerboseMode -Sync:$syncEnabled
    }
    else {
        & "$PSScriptRoot\felix-cli.ps1" -ProjectPath $RepoRoot -RequirementId $requirementId -Format $formatValue -VerboseMode:$VerboseMode -Sync:$syncEnabled
    }

    exit $LASTEXITCODE
}

function Invoke-Loop {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # Parse flags
    $maxIterations = 0
    $formatValue = $Format  # Use script-level default
    $syncEnabled = $false
    
    $i = 0
    while ($i -lt $Args.Count) {
        if ($Args[$i] -eq "--max-iterations" -and ($i + 1) -lt $Args.Count) {
            $maxIterations = [int]$Args[$i + 1]
            $i += 2
        }
        elseif ($Args[$i] -eq "--format" -and ($i + 1) -lt $Args.Count) {
            $formatValue = $Args[$i + 1]
            $i += 2
        }
        elseif ($Args[$i] -eq "--sync") {
            $syncEnabled = $true
            $i++
        }
        else {
            $i++
        }
    }

    Write-Host "Felix Loop Mode" -ForegroundColor Cyan
    Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
    if ($maxIterations -gt 0) {
        Write-Host "Max Iterations: $maxIterations" -ForegroundColor Gray
    }
    Write-Host ""

    # Start loop process - use explicit named parameters
    if ($maxIterations -gt 0) {
        & "$PSScriptRoot\felix-loop.ps1" -ProjectPath $RepoRoot -MaxRequirements $maxIterations -Format $formatValue -Sync:$syncEnabled
    }
    else {
        & "$PSScriptRoot\felix-loop.ps1" -ProjectPath $RepoRoot -Format $formatValue -Sync:$syncEnabled
    }
    exit $LASTEXITCODE
}

function Invoke-Tui {
    # Launch interactive Terminal UI dashboard
    $felixCliPath = Join-Path $RepoRoot "src\Felix.Cli"
    
    # Check if dotnet is available
    $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnetCmd) {
        Write-Host "[ERROR] dotnet CLI not found" -ForegroundColor Red
        Write-Host "" 
        Write-Host "The TUI requires .NET SDK to be installed." -ForegroundColor Yellow
        Write-Host "Download from: https://dotnet.microsoft.com/download" -ForegroundColor Cyan
        exit 1
    }
    
    # Check if Felix.Cli project exists
    if (-not (Test-Path $felixCliPath)) {
        Write-Host "[ERROR] Felix.Cli project not found at: $felixCliPath" -ForegroundColor Red
        exit 1
    }
    
    # Launch TUI dashboard
    & dotnet run --project $felixCliPath -- dashboard
    exit $LASTEXITCODE
}

function Invoke-Status {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $requirementId = if ($Args -and $Args.Count -gt 0) { $Args[0] } else { $null }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath -Raw | ConvertFrom-Json

    if ($requirementId) {
        # Show specific requirement
        $req = $requirements.requirements | Where-Object { $_.id -eq $requirementId }
        if (-not $req) {
            Write-Error "Requirement not found: $requirementId"
            exit 1
        }

        if ($Format -eq "json") {
            $req | ConvertTo-Json -Depth 10
        } 
        else {
            Write-Host ""
            Write-Host "Requirement: $($req.id)" -ForegroundColor Cyan
            Write-Host "Title: $($req.title)"
            
            $statusColor = switch ($req.status) {
                "done" { "Green" }
                "complete" { "Green" }
                "in-progress" { "Yellow" }
                "planned" { "Cyan" }
                "blocked" { "Red" }
                default { "White" }
            }
            Write-Host "Status: $($req.status)" -ForegroundColor $statusColor
            Write-Host "Priority: $($req.priority)"
            
            # Check dependencies
            if ($req.depends_on -and $req.depends_on.Count -gt 0) {
                Write-Host "Dependencies: $($req.depends_on -join ', ')" -ForegroundColor Gray
                
                # Build lookup for dependency checking
                $requirementsById = @{}
                foreach ($r in $requirements.requirements) {
                    $requirementsById[$r.id] = $r
                }
                
                # Check for incomplete dependencies
                $incompleteDeps = @()
                $missingDeps = @()
                foreach ($depId in $req.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if (-not $depReq) {
                        $missingDeps += $depId
                    }
                    elseif ($depReq.status -notin @("done", "complete")) {
                        $incompleteDeps += "$depId ($($depReq.status))"
                    }
                }
                
                if ($incompleteDeps.Count -gt 0) {
                    Write-Host ""
                    Write-Host "[WARN] Incomplete dependencies:" -ForegroundColor Yellow
                    foreach ($dep in $incompleteDeps) {
                        Write-Host "  - $dep" -ForegroundColor Yellow
                    }
                }
                
                if ($missingDeps.Count -gt 0) {
                    Write-Host ""
                    Write-Host "[ERROR] Missing dependencies:" -ForegroundColor Red
                    foreach ($dep in $missingDeps) {
                        Write-Host "  - $dep" -ForegroundColor Red
                    }
                }
            }
            
            if ($req.spec_path) {
                Write-Host "Spec: $($req.spec_path)" -ForegroundColor Gray
            }
            if ($req.last_run_id) {
                Write-Host "Last Run: $($req.last_run_id)" -ForegroundColor Gray
            }
            Write-Host ""
        }
    } 
    else {
        # Show summary
        if ($Format -eq "json") {
            $requirements.requirements | ConvertTo-Json -Depth 10
        } 
        else {
            Write-Host ""
            Write-Host "Felix Requirements Status" -ForegroundColor Cyan
            Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
            Write-Host ""
            
            $byStatus = $requirements.requirements | Group-Object status
            foreach ($group in $byStatus) {
                $color = switch ($group.Name) {
                    "done" { "Green" }
                    "complete" { "Green" }
                    "in-progress" { "Yellow" }
                    "in_progress" { "Yellow" }
                    "planned" { "Cyan" }
                    "blocked" { "Red" }
                    default { "White" }
                }
                Write-Host "$($group.Name): $($group.Count)" -ForegroundColor $color
            }
            Write-Host ""
        }
    }
}

function Invoke-List {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # Parse filters and flags
    $statusFilter = $null
    $priorityFilter = $null
    $blockedByIncompleteDeps = $false
    $withDeps = $false
    $tagFilter = $null
    
    for ($i = 0; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--status" { $statusFilter = $Args[$i + 1]; $i++ }
            "--priority" { $priorityFilter = $Args[$i + 1]; $i++ }
            "--tags" { $tagFilter = $Args[$i + 1]; $i++ }
            "--blocked-by" { 
                if ($Args[$i + 1] -eq "incomplete-deps") {
                    $blockedByIncompleteDeps = $true
                }
                $i++
            }
            "--with-deps" { $withDeps = $true }
        }
    }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath -Raw | ConvertFrom-Json
    
    # Build lookup for dependency checking
    $requirementsById = @{}
    foreach ($req in $requirements.requirements) {
        $requirementsById[$req.id] = $req
    }

    # Apply filters
    $filtered = $requirements.requirements
    
    if ($statusFilter) {
        $filtered = $filtered | Where-Object { $_.status -eq $statusFilter }
    }
    
    if ($priorityFilter) {
        $filtered = $filtered | Where-Object { $_.priority -eq $priorityFilter }
    }
    
    if ($tagFilter) {
        $tags = $tagFilter -split ','
        $filtered = $filtered | Where-Object { 
            $reqTags = $_.tags
            ($tags | Where-Object { $reqTags -contains $_ }).Count -gt 0
        }
    }
    
    if ($blockedByIncompleteDeps) {
        $filtered = $filtered | Where-Object {
            if ($_.depends_on -and $_.depends_on.Count -gt 0) {
                $hasIncomplete = $false
                foreach ($depId in $_.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if (-not $depReq -or $depReq.status -notin @("done", "complete")) {
                        $hasIncomplete = $true
                        break
                    }
                }
                $hasIncomplete
            }
            else {
                $false
            }
        }
    }

    # Sort by ID for consistent ordering
    $filtered = $filtered | Sort-Object { $_.id }

    if ($Format -eq "json") {
        $filtered | ConvertTo-Json -Depth 10
    } 
    else {
        Write-Host ""
        Write-Host "Requirements:" -ForegroundColor Cyan
        
        # Show active filters
        $filters = @()
        if ($statusFilter) { $filters += "status=$statusFilter" }
        if ($priorityFilter) { $filters += "priority=$priorityFilter" }
        if ($tagFilter) { $filters += "tags=$tagFilter" }
        if ($blockedByIncompleteDeps) { $filters += "blocked-by=incomplete-deps" }
        
        if ($filters.Count -gt 0) {
            Write-Host "Filters: $($filters -join ', ')" -ForegroundColor Gray
        }
        Write-Host ""
        
        foreach ($req in $filtered) {
            $color = switch ($req.status) {
                "done" { "Green" }
                "complete" { "Green" }
                "in-progress" { "Yellow" }
                "planned" { "Cyan" }
                "blocked" { "Red" }
                default { "White" }
            }
            
            Write-Host "  $($req.id): $($req.title)" -ForegroundColor $color -NoNewline
            Write-Host " [$($req.status)]" -ForegroundColor Gray
            
            # Show dependencies if requested
            if ($withDeps -and $req.depends_on -and $req.depends_on.Count -gt 0) {
                Write-Host "    Depends on: " -NoNewline -ForegroundColor DarkGray
                $depStatuses = @()
                foreach ($depId in $req.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if ($depReq) {
                        $depColor = if ($depReq.status -in @("done", "complete")) { "Green" } else { "Yellow" }
                        $depStatuses += "$depId ($($depReq.status))"
                    }
                    else {
                        $depStatuses += "$depId (missing)"
                    }
                }
                Write-Host ($depStatuses -join ', ') -ForegroundColor DarkGray
            }
        }
        
        Write-Host ""
        Write-Host "Total: $($filtered.Count)" -ForegroundColor Gray
        Write-Host ""
    }
}

function Invoke-Validate {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix validate <requirement-id>"
        exit 1
    }

    $requirementId = $Args[0]

    Write-Host "Validating requirement: $requirementId" -ForegroundColor Cyan
    Write-Host ""

    # Call validation script
    $validatorScript = "$RepoRoot\scripts\validate-requirement.py"
    if (-not (Test-Path $validatorScript)) {
        Write-Error "Validator script not found: $validatorScript"
        exit 1
    }

    # Run Python validator
    $pythonCmd = "python"
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $pythonCmd = "py -3"
    }

    $result = & $pythonCmd $validatorScript $requirementId
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host " Validation PASSED" -ForegroundColor Green
    }
    else {
        Write-Host " Validation FAILED" -ForegroundColor Red
    }

    exit $exitCode
}

function Invoke-Deps {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix deps <requirement-id> [--check|--tree|--incomplete]"
        Write-Host "Examples:"
        Write-Host "  felix deps S-0018              Show dependencies of S-0018"
        Write-Host "  felix deps S-0018 --check      Check if dependencies are complete"
        Write-Host "  felix deps S-0018 --tree       Show full dependency tree"
        Write-Host "  felix deps --incomplete        List all requirements with incomplete dependencies"
        exit 1
    }

    $requirementId = $Args[0]
    $showTree = $false
    $checkOnly = $false
    $showIncomplete = $false

    # Parse flags
    for ($i = 1; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--tree" { $showTree = $true }
            "--check" { $checkOnly = $true }
            "--incomplete" { $showIncomplete = $true }
        }
    }

    # Handle --incomplete flag (show all requirements with incomplete deps)
    if ($requirementId -eq "--incomplete") {
        $showIncomplete = $true
        $requirementId = $null
    }

    # Load requirements.json
    $requirementsFile = Join-Path $RepoRoot ".felix/requirements.json"
    if (-not (Test-Path $requirementsFile)) {
        Write-Error "requirements.json not found at $requirementsFile"
        exit 1
    }

    try {
        $requirementsData = Get-Content $requirementsFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse requirements.json: $_"
        exit 1
    }

    # Build lookup by ID
    $requirementsById = @{}
    foreach ($req in $requirementsData.requirements) {
        $requirementsById[$req.id] = $req
    }

    # Show all incomplete if requested
    if ($showIncomplete) {
        Write-Host ""
        Write-Host "=== Requirements with Incomplete Dependencies ===" -ForegroundColor Cyan
        Write-Host ""

        $foundAny = $false
        foreach ($req in $requirementsData.requirements) {
            if ($req.depends_on -and $req.depends_on.Count -gt 0) {
                $incomplete = @()
                foreach ($depId in $req.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if ($depReq -and $depReq.status -notin @("done", "complete")) {
                        $incomplete += "$depId ($($depReq.status))"
                    }
                    elseif (-not $depReq) {
                        $incomplete += "$depId (missing)"
                    }
                }

                if ($incomplete.Count -gt 0) {
                    $foundAny = $true
                    Write-Host "  $($req.id) - $($req.title)" -ForegroundColor Yellow
                    Write-Host "    Status: $($req.status)" -ForegroundColor Gray
                    Write-Host "    Incomplete dependencies: $($incomplete -join ', ')" -ForegroundColor Red
                    Write-Host ""
                }
            }
        }

        if (-not $foundAny) {
            Write-Host "  [OK] All requirements have complete dependencies" -ForegroundColor Green
        }
        Write-Host ""
        exit 0
    }

    # Validate requirement ID
    if ($requirementId -notmatch '^S-\d{4}$') {
        Write-Error "Invalid requirement ID format. Expected S-NNNN (e.g., S-0001)"
        exit 1
    }

    # Find requirement
    $requirement = $requirementsById[$requirementId]
    if (-not $requirement) {
        Write-Error "Requirement $requirementId not found in requirements.json"
        exit 1
    }

    Write-Host ""
    Write-Host "=== Dependency Analysis: $requirementId ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Requirement: $($requirement.title)" -ForegroundColor White
    Write-Host "Status: $($requirement.status)" -ForegroundColor $(if ($requirement.status -in @("done", "complete")) { "Green" } else { "Yellow" })
    Write-Host ""

    # Check if requirement has dependencies
    if (-not $requirement.depends_on -or $requirement.depends_on.Count -eq 0) {
        Write-Host "[OK] No dependencies" -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    # Analyze dependencies
    Write-Host "Dependencies ($($requirement.depends_on.Count)):" -ForegroundColor Yellow
    Write-Host ""

    $allComplete = $true
    $incompleteDeps = @()
    $missingDeps = @()

    foreach ($depId in $requirement.depends_on) {
        $depReq = $requirementsById[$depId]
        
        if (-not $depReq) {
            Write-Host "  [ERROR] $depId - MISSING from requirements.json" -ForegroundColor Red
            $missingDeps += $depId
            $allComplete = $false
            continue
        }

        $isComplete = $depReq.status -in @("done", "complete")
        $statusColor = if ($isComplete) { "Green" } else { "Yellow" }
        $statusIcon = if ($isComplete) { "[OK]" } else { "[WARN]" }

        Write-Host "  $statusIcon $depId - $($depReq.title)" -ForegroundColor $statusColor
        Write-Host "        Status: $($depReq.status)" -ForegroundColor Gray
        Write-Host "        Priority: $($depReq.priority)" -ForegroundColor Gray

        if (-not $isComplete) {
            $allComplete = $false
            $incompleteDeps += $depId
        }

        # Show dependency tree if requested
        if ($showTree -and $depReq.depends_on -and $depReq.depends_on.Count -gt 0) {
            Write-Host "        Depends on: $($depReq.depends_on -join ', ')" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    # Summary
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    if ($allComplete) {
        Write-Host "[OK] All dependencies are complete" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "[WARN] Incomplete dependencies detected" -ForegroundColor Yellow
        if ($incompleteDeps.Count -gt 0) {
            Write-Host "  Incomplete: $($incompleteDeps -join ', ')" -ForegroundColor Yellow
        }
        if ($missingDeps.Count -gt 0) {
            Write-Host "  Missing: $($missingDeps -join ', ')" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Consider completing dependencies before starting $requirementId" -ForegroundColor Gray
        exit 1
    }
}

function Invoke-SpecCreate {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )


    if ($Args.Count -eq 0) {
        Write-Host ""
        Write-Host "Available subcommands:"
        Write-Host "  create [--quick] <description>   Create a new specification with auto-generated ID"
        Write-Host "  fix [--fix-duplicates]            Scan specs folder and fix requirements.json alignment"
        Write-Host "  delete <requirement-id>           Delete a specification and remove from requirements.json"
        Write-Host "  status <requirement-id> <status>  Update a requirement status in requirements.json"
        Write-Host ""
        Write-Host "Flags:"
        Write-Host "  --quick, -q           Quick mode: minimal questions, makes reasonable assumptions"
        Write-Host "  --fix-duplicates, -f  Automatically rename duplicate spec files to next available ID"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix spec create `"Add user authentication`""
        Write-Host "  felix spec fix"
        Write-Host "  felix spec fix --fix-duplicates"
        Write-Host "  felix spec delete S-0042"
        Write-Host "  felix spec status S-0042 planned"
        exit 0
    }

    $subcommand = $Args[0]
    
    switch ($subcommand) {
        "create" {
            # Check for --quick flag
            $quickMode = $false
            $argsWithoutFlags = @()
            for ($i = 1; $i -lt $Args.Count; $i++) {
                if ($Args[$i] -eq "--quick" -or $Args[$i] -eq "-q") {
                    $quickMode = $true
                }
                else {
                    $argsWithoutFlags += $Args[$i]
                }
            }
            
            # Get description interactively or from command line
            $description = if ($argsWithoutFlags.Count -gt 0) { 
                $argsWithoutFlags -join " " 
            }
            else { 
                Read-Host "What feature do you want to build?"
            }

            if (-not $description -or $description.Trim() -eq "") {
                Write-Error "Description cannot be empty"
                exit 1
            }
            
            $description = $description.Trim()

            # Spec create is inherently interactive - JSON mode not supported
            if ($Format -eq "json") {
                Write-Host "⚠️  Warning: --format json is not supported for 'spec create'" -ForegroundColor Yellow
                Write-Host "   Spec builder requires interactive input (questions/answers)" -ForegroundColor Gray
                Write-Host "   Continuing with standard interactive mode..." -ForegroundColor Gray
                Write-Host ""
            }

            # Auto-generate next available requirement ID
            $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
            $nextId = "S-0001"
            
            if (Test-Path $requirementsFile) {
                try {
                    $reqData = Get-Content $requirementsFile -Raw | ConvertFrom-Json
                    $existingIds = $reqData.requirements | ForEach-Object { $_.id }
                    
                    # Find highest number
                    $maxNum = 0
                    foreach ($id in $existingIds) {
                        if ($id -match '^S-(\d{4})$') {
                            $num = [int]$matches[1]
                            if ($num -gt $maxNum) {
                                $maxNum = $num
                            }
                        }
                    }
                    
                    $nextNum = $maxNum + 1
                    $nextId = "S-{0:D4}" -f $nextNum
                }
                catch {
                    # If there's an error reading, default to S-0001
                    Write-Warning "Could not read requirements.json, using S-0001"
                }
            }

            # Spec-builder needs interactive stdin, so call felix-agent directly
            # (felix-cli subprocess redirection breaks Read-Host)
            if ($quickMode) {
                & "$PSScriptRoot\felix-agent.ps1" `
                    -ProjectPath $RepoRoot `
                    -SpecBuildMode:$true `
                    -QuickMode:$true `
                    -RequirementId $nextId `
                    -InitialPrompt $description `
                    -VerboseMode:$VerboseMode
            }
            else {
                & "$PSScriptRoot\felix-agent.ps1" `
                    -ProjectPath $RepoRoot `
                    -SpecBuildMode:$true `
                    -RequirementId $nextId `
                    -InitialPrompt $description `
                    -VerboseMode:$VerboseMode
            }
            
            exit $LASTEXITCODE
        }
        
        "fix" {
            # Check for --fix-duplicates flag
            $fixDuplicates = $false
            for ($i = 1; $i -lt $Args.Count; $i++) {
                if ($Args[$i] -eq "--fix-duplicates" -or $Args[$i] -eq "-f") {
                    $fixDuplicates = $true
                }
            }
            Invoke-SpecFix -FixDuplicates:$fixDuplicates
            exit $LASTEXITCODE
        }
        
        "delete" {
            if ($Args.Count -lt 2) {
                Write-Error "Usage: felix spec delete <requirement-id>"
                Write-Host "Example: felix spec delete S-0042"
                exit 1
            }
            
            $requirementId = $Args[1]
            Invoke-SpecDelete -RequirementId $requirementId
            exit $LASTEXITCODE
        }
        
        "status" {
            if ($Args.Count -lt 3) {
                Write-Error "Usage: felix spec status <requirement-id> <status>"
                Write-Host "Example: felix spec status S-0042 planned"
                exit 1
            }
            
            $requirementId = $Args[1]
            $statusValue = $Args[2]
            Invoke-SpecStatus -RequirementId $requirementId -Status $statusValue
            exit $LASTEXITCODE
        }
        
        default {
            Write-Error "Unknown spec subcommand: $subcommand"
            Write-Host ""
            Write-Host "Available subcommands:"
            Write-Host "  create [--quick] <description>   Create a new specification with auto-generated ID"
            Write-Host "  fix [--fix-duplicates]            Scan specs folder and fix requirements.json alignment"
            Write-Host "  delete <requirement-id>           Delete a specification and remove from requirements.json"
            Write-Host "  status <requirement-id> <status>  Update a requirement status in requirements.json"
            Write-Host ""
            Write-Host "Flags:"
            Write-Host "  --quick, -q           Quick mode: minimal questions, makes reasonable assumptions"
            Write-Host "  --fix-duplicates, -f  Automatically rename duplicate spec files to next available ID"
            Write-Host ""
            Write-Host "Examples:"
            Write-Host "  felix spec create `"Add user authentication`""
            Write-Host "  felix spec fix"
            Write-Host "  felix spec fix --fix-duplicates"
            Write-Host "  felix spec delete S-0042"
            Write-Host "  felix spec status S-0042 planned"
            exit 1
        }
    }
}

function Invoke-SpecStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    if ($RequirementId -notmatch '^S-\d{4}$') {
        Write-Error 'Invalid requirement ID format. Expected S-NNNN (e.g., S-0001)'
        exit 1
    }

    $normalizedStatus = $Status.ToLower()
    if ($normalizedStatus -eq "in-progress") {
        $normalizedStatus = "in_progress"
    }

    $allowedStatuses = @("draft", "planned", "in_progress", "blocked", "complete", "done")
    if ($allowedStatuses -notcontains $normalizedStatus) {
        Write-Error "Invalid status '$Status'. Allowed: $($allowedStatuses -join ', ')"
        exit 1
    }

    . "$PSScriptRoot\core\state-manager.ps1"

    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
    if (-not (Test-Path $requirementsFile)) {
        Write-Error "requirements.json not found at $requirementsFile"
        exit 1
    }

    try {
        $state = Get-RequirementsState -RequirementsFile $requirementsFile
        $requirement = $state.requirements | Where-Object { $_.id -eq $RequirementId }
        if (-not $requirement) {
            Write-Error "Requirement $RequirementId not found in requirements.json"
            exit 1
        }

        $requirement.status = $normalizedStatus
        $requirement.updated_at = Get-Date -Format "yyyy-MM-dd"
        Save-RequirementsState -RequirementsFile $requirementsFile -State $state

        Write-Host ""
        Write-Host "[OK] Updated $RequirementId status to '$normalizedStatus'" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Error "Failed to update requirement status: $_"
        exit 1
    }
}

function Invoke-SpecFix {
    param(
        [switch]$FixDuplicates
    )
    
    Write-Host ""
    Write-Host "=== Spec Fix Utility ===" -ForegroundColor Cyan
    Write-Host "Scanning specs folder and validating requirements.json..." -ForegroundColor Gray
    Write-Host ""
    
    # Helper function to ensure array type
    function Ensure-Array {
        param($value)
        if ($null -eq $value) { return @() }
        if ($value -is [array]) { return @($value) }
        return @($value)
    }
    
    # Helper function to find next available spec ID
    function Get-NextAvailableSpecId {
        param([int]$StartFrom)
        $nextId = $StartFrom + 1
        while (Test-Path (Join-Path $specsDir "S-$($nextId.ToString('0000'))*")) {
            $nextId++
        }
        return $nextId
    }
    
    $specsDir = Join-Path $RepoRoot "specs"
    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
    
    if (-not (Test-Path $specsDir)) {
        Write-Error "Specs directory not found: $specsDir"
        exit 1
    }
    
    # Load or create requirements.json
    $requirementsData = @{ requirements = @() }
    if (Test-Path $requirementsFile) {
        try {
            $requirementsData = Get-Content $requirementsFile -Raw | ConvertFrom-Json
            Write-Host "[OK] Loaded requirements.json" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to parse requirements.json - will recreate"
            $requirementsData = @{ requirements = @() }
        }
    }
    else {
        Write-Warning "requirements.json not found - will create new"
    }
    
    # Get all spec files
    $specFiles = Get-ChildItem -Path $specsDir -Filter "S-*.md" | Sort-Object Name
    Write-Host "Found $($specFiles.Count) spec files" -ForegroundColor Cyan
    Write-Host ""
    
    # Track changes
    $added = @()
    $updated = @()
    $orphaned = @()
    $errors = @()
    $duplicates = @()
    $fixed = @()
    $processedIds = @{}
    
    # Find max spec ID for duplicate renaming
    $allSpecIds = @()
    $tempFiles = Get-ChildItem -Path $specsDir -Filter "S-*.md"
    foreach ($f in $tempFiles) {
        if ($f.Name -match '^S-(\d{4})') {
            $allSpecIds += [int]$Matches[1]
        }
    }
    $maxSpecId = if ($allSpecIds.Count -gt 0) { ($allSpecIds | Measure-Object -Maximum).Maximum } else { 0 }
    
    # Build lookup of existing requirements (convert to hashtables for mutability)
    $existingReqs = @{}
    foreach ($req in $requirementsData.requirements) {
        # Convert PSCustomObject to hashtable and preserve all existing properties
        $reqHash = [ordered]@{
            id                 = $req.id
            title              = $req.title
            spec_path          = $req.spec_path
            status             = $req.status
            priority           = $req.priority
            tags               = Ensure-Array $req.tags
            depends_on         = Ensure-Array $req.depends_on
            updated_at         = $req.updated_at
            commit_on_complete = if ($null -ne $req.commit_on_complete) { $req.commit_on_complete } else { $false }
        }
        # Preserve created_at if it exists
        if ($req.created_at) {
            $reqHash.created_at = $req.created_at
        }
        $existingReqs[$req.id] = $reqHash
    }
    
    # Process each spec file
    foreach ($specFile in $specFiles) {
        $fileName = $specFile.Name
        
        # Extract requirement ID from filename
        if ($fileName -match '^(S-\d{4})') {
            $reqId = $Matches[1]
            
            # Check for duplicate IDs
            if ($processedIds.ContainsKey($reqId)) {
                if ($FixDuplicates) {
                    # Find next available ID
                    $nextId = Get-NextAvailableSpecId -StartFrom $maxSpecId
                    $maxSpecId = $nextId
                    $newReqId = "S-$($nextId.ToString('0000'))"
                    $newFileName = $fileName -replace '^S-\d{4}', $newReqId
                    
                    # Rename with git if file is tracked, else use Rename-Item
                    $oldPath = Join-Path $specsDir $fileName
                    $newPath = Join-Path $specsDir $newFileName
                    
                    try {
                        $useGit = $false
                        if (Test-Path (Join-Path $RepoRoot ".git")) {
                            # Try git mv silently, but if it fails (untracked file), fall back to Rename-Item
                            $ErrorActionPreference = 'SilentlyContinue'
                            $gitResult = git mv $oldPath $newPath 2>$null
                            $ErrorActionPreference = 'Continue'
                            if ($LASTEXITCODE -eq 0) {
                                $useGit = $true
                            }
                        }
                        
                        if (-not $useGit) {
                            # File not tracked or no git repo - use PowerShell rename
                            Rename-Item -Path $oldPath -NewName $newFileName -ErrorAction Stop
                        }
                        
                        Write-Host "  [FIX] Renamed duplicate $reqId -> $newReqId ($newFileName)" -ForegroundColor Cyan
                        $fixed += "$fileName -> $newFileName"
                        
                        # Update for continued processing
                        $reqId = $newReqId
                        $fileName = $newFileName
                        $specFile = Get-Item -Path $newPath
                    }
                    catch {
                        $errors += "Failed to rename $fileName : $_"
                        Write-Host "  [ERROR] Failed to rename $fileName - $_" -ForegroundColor Red
                        continue
                    }
                }
                else {
                    $duplicates += $fileName
                    Write-Host "  [WARN] Duplicate ID $reqId in $fileName (already processed $($processedIds[$reqId]))" -ForegroundColor Magenta
                    continue
                }
            }
            $processedIds[$reqId] = $fileName
            
            # Read spec title
            try {
                $content = Get-Content $specFile.FullName -Raw
                $title = "Untitled"
                if ($content -match '#\s+S-\d{4}:\s+(.+)') {
                    $titleText = $Matches[1].Trim()
                    $title = "${reqId}: $titleText"
                }
                elseif ($content -match '#\s+(.+)') {
                    $title = $Matches[1].Trim()
                }
                
                # Check if requirement exists
                if ($existingReqs.ContainsKey($reqId)) {
                    $existing = $existingReqs[$reqId]
                    
                    # Check if spec_path needs updating (using forward slashes for consistency)
                    $relativePath = "specs/$fileName"
                    $needsUpdate = $false
                    
                    if ($existing.spec_path -ne $relativePath) {
                        $existing.spec_path = $relativePath
                        $needsUpdate = $true
                    }
                    
                    if ($existing.title -ne $title) {
                        $existing.title = $title
                        $needsUpdate = $true
                    }
                    
                    if ($needsUpdate) {
                        $existing.updated_at = Get-Date -Format "yyyy-MM-dd"
                        $updated += $reqId
                        Write-Host "  [UPDATE] $reqId - $fileName" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "  [OK] $reqId - $fileName" -ForegroundColor Green
                    }
                }
                else {
                    # Add new requirement with minimal properties
                    $newReq = [ordered]@{
                        id                 = $reqId
                        title              = $title
                        spec_path          = "specs/$fileName"
                        status             = "planned"
                        priority           = "medium"
                        tags               = @()
                        depends_on         = @()
                        updated_at         = Get-Date -Format "yyyy-MM-dd"
                        commit_on_complete = $false
                    }
                    # Don't add to requirementsData.requirements yet - we'll rebuild it later
                    $existingReqs[$reqId] = $newReq
                    $added += $reqId
                    Write-Host "  [ADD] $reqId - $fileName" -ForegroundColor Green
                }
                
                # Remove from tracking (so we can find orphans)
                $existingReqs.Remove($reqId)
            }
            catch {
                $errors += "Failed to process $fileName : $_"
                Write-Host "  [ERROR] $fileName - $_" -ForegroundColor Red
            }
        }
        else {
            $errors += "Invalid filename format: $fileName"
            Write-Host "  [WARN] Invalid $fileName - not in S-NNNN format" -ForegroundColor Magenta
        }
    }
    
    # Check for orphaned entries (in requirements.json but no matching file found)
    # Any remaining items in existingReqs means we didn't find their spec file
    if ($existingReqs.Count -gt 0) {
        foreach ($orphanedReq in $existingReqs.Values) {
            $orphaned += $orphanedReq.id
            Write-Host "  [ORPHAN] $($orphanedReq.id) - file not found: $($orphanedReq.spec_path)" -ForegroundColor Yellow
        }
    }
    
    # Rebuild requirements array from all entries (existing + newly added)
    # Note: We need to get all requirements from the original data that weren't removed,
    # plus any new ones we added. Since we remove processed items from $existingReqs,
    # we need to rebuild from the original requirementsData and merge with updates.
    
    $allRequirements = @()
    
    # Get all requirement IDs we've processed (both existing and new)
    $processedIds = @{}
    foreach ($specFile in $specFiles) {
        if ($specFile.Name -match '^(S-\d{4})') {
            $reqId = $Matches[1]
            $processedIds[$reqId] = $true
        }
    }
    
    # Add all processed requirements from our lookup
    foreach ($reqId in $processedIds.Keys | Sort-Object) {
        # Build lookup of requirements by ID for quick access
        $reqLookup = @{}
        foreach ($req in $requirementsData.requirements) {
            $reqLookup[$req.id] = $req
        }
        
        # If this was an existing requirement that we updated, use our hashtable version
        # Otherwise use the original from requirementsData
        if ($reqLookup.ContainsKey($reqId)) {
            # Find the updated version in our original data
            $origReq = $requirementsData.requirements | Where-Object { $_.id -eq $reqId }
            if ($origReq) {
                # Build hashtable with all properties preserved
                $reqHash = [ordered]@{
                    id         = $origReq.id
                    title      = $origReq.title
                    spec_path  = $origReq.spec_path
                    status     = $origReq.status
                    priority   = $origReq.priority
                    tags       = if ($origReq.tags) { @($origReq.tags) } else { @() }
                    depends_on = if ($origReq.depends_on) { @($origReq.depends_on) } else { @() }
                    updated_at = $origReq.updated_at
                }
                # Preserve created_at and commit_on_complete if they exist
                if ($origReq.created_at) {
                    $reqHash.created_at = $origReq.created_at
                }
                if ($null -ne $origReq.commit_on_complete) {
                    $reqHash.commit_on_complete = $origReq.commit_on_complete
                }
                $allRequirements += $reqHash
            }
        }
    }
    
    # Actually, let me simplify this - just iterate through all spec files and build from scratch
    $allRequirements = @()
    foreach ($specFile in $specFiles) {
        if ($specFile.Name -match '^(S-\d{4})') {
            $reqId = $Matches[1]
            
            # Find in original requirements
            $origReq = $requirementsData.requirements | Where-Object { $_.id -eq $reqId }
            
            if ($origReq) {
                # Preserve existing requirement with updated spec_path and title
                $content = Get-Content $specFile.FullName -Raw -ErrorAction SilentlyContinue
                $title = $origReq.title
                if ($content -match '#\s+S-\d{4}:\s+(.+)') {
                    $titleText = $Matches[1].Trim()
                    $title = "${reqId}: $titleText"
                }
                elseif ($content -match '#\s+(.+)') {
                    $title = $Matches[1].Trim()
                }
                
                $reqHash = [ordered]@{
                    id         = $origReq.id
                    title      = $title
                    spec_path  = "specs/$($specFile.Name)"
                    status     = $origReq.status
                    priority   = $origReq.priority
                    tags       = Ensure-Array $origReq.tags
                    depends_on = Ensure-Array $origReq.depends_on
                    updated_at = if ($origReq.title -ne $title -or $origReq.spec_path -ne "specs/$($specFile.Name)") { Get-Date -Format "yyyy-MM-dd" } else { $origReq.updated_at }
                }
                if ($origReq.created_at) {
                    $reqHash.created_at = $origReq.created_at
                }
                if ($null -ne $origReq.commit_on_complete) {
                    $reqHash.commit_on_complete = $origReq.commit_on_complete
                }
                $allRequirements += $reqHash
            }
            else {
                # New requirement
                $content = Get-Content $specFile.FullName -Raw -ErrorAction SilentlyContinue
                $title = "Untitled"
                if ($content -match '#\s+S-\d{4}:\s+(.+)') {
                    $titleText = $Matches[1].Trim()
                    $title = "${reqId}: $titleText"
                }
                elseif ($content -match '#\s+(.+)') {
                    $title = $Matches[1].Trim()
                }
                
                $allRequirements += [ordered]@{
                    id                 = $reqId
                    title              = $title
                    spec_path          = "specs/$($specFile.Name)"
                    status             = "planned"
                    priority           = "medium"
                    tags               = @()
                    depends_on         = @()
                    updated_at         = Get-Date -Format "yyyy-MM-dd"
                    commit_on_complete = $false
                }
            }
        }
    }
    
    # Sort requirements by ID
    $requirementsData.requirements = $allRequirements | Sort-Object id
    
    # Save requirements.json with proper array serialization
    try {
        # Convert to JSON
        $json = $requirementsData | ConvertTo-Json -Depth 10 -Compress:$false
        
        # Fix PowerShell JSON serialization quirks:
        # 1. Empty arrays converted to {} - replace with []
        $json = $json -replace ':\s*\{\s*\}', ': []'
        
        # 2. Single-item arrays collapsed to strings - we need to fix specific fields
        #    Match patterns like "depends_on": "S-0005" and wrap in array
        $json = $json -creplace '("(?:depends_on|tags)":\s*)"([^"]+)"', '$1["$2"]'
        
        Set-Content -Path $requirementsFile -Value $json -Encoding UTF8
        Write-Host ""
        Write-Host "[OK] Saved requirements.json" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to save requirements.json: $_"
        exit 1
    }
    
    # Report summary
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Total specs:      $($specFiles.Count)" -ForegroundColor White
    Write-Host "Added:            $($added.Count)" -ForegroundColor Green
    Write-Host "Updated:          $($updated.Count)" -ForegroundColor Yellow
    if ($fixed.Count -gt 0) {
        Write-Host "Fixed:            $($fixed.Count)" -ForegroundColor Cyan
    }
    Write-Host "Duplicates:       $($duplicates.Count)" -ForegroundColor Magenta
    Write-Host "Orphaned:         $($orphaned.Count)" -ForegroundColor Yellow
    Write-Host "Errors:           $($errors.Count)" -ForegroundColor Red
    
    if ($fixed.Count -gt 0) {
        Write-Host ""
        Write-Host "[OK] Fixed duplicate specs:" -ForegroundColor Cyan
        foreach ($fix in $fixed) {
            Write-Host "  - $fix" -ForegroundColor Gray
        }
    }
    
    if ($duplicates.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARN] Duplicate spec IDs found (skipped):" -ForegroundColor Magenta
        foreach ($file in $duplicates) {
            Write-Host "  - $file" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "To automatically rename duplicates, run:" -ForegroundColor Yellow
        Write-Host "  felix spec fix --fix-duplicates" -ForegroundColor Gray
    }
    
    if ($orphaned.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARN] Orphaned entries (in requirements.json but file missing):" -ForegroundColor Yellow
        foreach ($id in $orphaned) {
            Write-Host "  - $id" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "To remove orphaned entries, delete them manually or run:" -ForegroundColor Gray
        foreach ($id in $orphaned) {
            Write-Host "  felix spec delete $id" -ForegroundColor Gray
        }
    }
    
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors encountered:" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  - $err" -ForegroundColor Gray
        }
    }
        
    Write-Host ""
}

function Invoke-SpecDelete {
    param([string]$RequirementId)
    
    if ($RequirementId -notmatch '^S-\d{4}$') {
        Write-Error 'Invalid requirement ID format. Expected S-NNNN (e.g., S-0001)'
        exit 1
    }
    
    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
    $specsDir = Join-Path $RepoRoot "specs"
    
    # Load requirements.json
    if (-not (Test-Path $requirementsFile)) {
        Write-Error "requirements.json not found at $requirementsFile"
        exit 1
    }
    
    try {
        $requirementsData = Get-Content $requirementsFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse requirements.json: $_"
        exit 1
    }
    
    # Find requirement
    $requirement = $requirementsData.requirements | Where-Object { $_.id -eq $RequirementId }
    if (-not $requirement) {
        Write-Error "Requirement $RequirementId not found in requirements.json"
        exit 1
    }
    
    # Find spec file
    $specFile = Get-ChildItem -Path $specsDir -Filter "$RequirementId*.md" -ErrorAction SilentlyContinue
    
    # Show what will be deleted
    Write-Host ""
    Write-Host "=== Delete Specification ===" -ForegroundColor Yellow
    Write-Host "ID:    $RequirementId" -ForegroundColor Cyan
    Write-Host "Title: $($requirement.title)" -ForegroundColor Cyan
    if ($specFile) {
        Write-Host "File:  $($specFile.Name)" -ForegroundColor Cyan
    }
    else {
        Write-Host "File:  (not found)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Confirm deletion
    $confirmation = Read-Host "Are you sure you want to delete this spec? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Deletion cancelled" -ForegroundColor Gray
        exit 0
    }
    
    # Delete spec file
    if ($specFile) {
        try {
            Remove-Item $specFile.FullName -Force
            Write-Host "[OK] Deleted file: $($specFile.Name)" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to delete file: $_"
            exit 1
        }
    }
    
    # Remove from requirements.json
    $requirementsData.requirements = $requirementsData.requirements | Where-Object { $_.id -ne $RequirementId }
    
    try {
        $json = $requirementsData | ConvertTo-Json -Depth 10
        Set-Content -Path $requirementsFile -Value $json -Encoding UTF8
        Write-Host "[OK] Removed from requirements.json" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to update requirements.json: $_"
        exit 1
    }
    
    Write-Host ""
    Write-Host "[OK] Specification $RequirementId deleted successfully" -ForegroundColor Green
    Write-Host ""
}

function Show-Version {
    Write-Host ""
    Write-Host "Felix CLI v0.3.0-alpha (Phase 1: PowerShell)" -ForegroundColor Cyan
    Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
    
    # Try to get git info
    try {
        $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $gitCommit = git rev-parse --short HEAD 2>$null
        if ($gitBranch) {
            Write-Host "Branch: $gitBranch" -ForegroundColor Gray
            Write-Host "Commit: $gitCommit" -ForegroundColor Gray
        }
    }
    catch {
        # Git not available or not a git repo
    }
    
    Write-Host ""
}

function Show-Help {
    param([string]$SubCommand)

    if ($SubCommand) {
        switch ($SubCommand) {
            "run" {
                Write-Host ""
                Write-Host "felix run <requirement-id> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Execute a single requirement to completion."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host "  --no-stats                   Suppress statistics summary"
                Write-Host "  --sync                       Temporarily enable sync (overrides config)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix run S-0001"
                Write-Host "  felix run S-0001 --format json"
                Write-Host "  felix run S-0001 --sync"
                Write-Host "  felix run S-0001 --format plain --no-stats"
                Write-Host ""
            }
            "loop" {
                Write-Host ""
                Write-Host "felix loop [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run agent in continuous loop mode (processes all planned requirements)."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --max-iterations <n>   Maximum iterations to run"
                Write-Host "  --sync                 Temporarily enable sync (overrides config)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix loop"
                Write-Host "  felix loop --max-iterations 10"
                Write-Host "  felix loop --sync"
                Write-Host ""
            }
            "status" {
                Write-Host ""
                Write-Host "felix status [requirement-id] [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Show current status of requirements."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix status"
                Write-Host "  felix status S-0001"
                Write-Host "  felix status --format json"
                Write-Host ""
            }
            "list" {
                Write-Host ""
                Write-Host "felix list [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "List requirements with optional filtering."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --status <status>            Filter by status (planned, in-progress, done, blocked)"
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix list"
                Write-Host "  felix list --status planned"
                Write-Host "  felix list --status done --format json"
                Write-Host ""
            }
            "validate" {
                Write-Host ""
                Write-Host "felix validate <requirement-id>" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run validation checks for a requirement."
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix validate S-0001"
                Write-Host ""
            }
            "deps" {
                Write-Host ""
                Write-Host "felix deps [requirement-id] [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Show dependency information and validation status."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --check              Check if dependencies are satisfied"
                Write-Host "  --tree               Show dependency tree"
                Write-Host "  --incomplete         Show incomplete dependencies only"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix deps S-0001"
                Write-Host "  felix deps S-0001 --check"
                Write-Host "  felix deps --incomplete"
                Write-Host "  felix deps --tree"
                Write-Host ""
            }
            "spec" {
                Write-Host ""
                Write-Host "felix spec <subcommand> [arguments]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage requirement specifications."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  create <description>   Create a new requirement spec"
                Write-Host "  fix <req-id>           Fix an existing spec"
                Write-Host "  delete <req-id>        Delete a requirement spec"
                Write-Host "  status <req-id> <status>  Update a requirement status"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix spec create ""Add user authentication"""
                Write-Host "  felix spec fix S-0001"
                Write-Host "  felix spec delete S-0001"
                Write-Host "  felix spec status S-0001 planned"
                Write-Host ""
            }
            "context" {
                Write-Host ""
                Write-Host "felix context <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Generate or view comprehensive project context documentation."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  build [options]       Analyze project and generate CONTEXT.md"
                Write-Host "  show                  Display current CONTEXT.md content"
                Write-Host ""
                Write-Host "Options for 'build':" -ForegroundColor Yellow
                Write-Host "  --include-hidden      Include hidden files/folders in analysis"
                Write-Host "  --force               Skip overwrite confirmation"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix context build"
                Write-Host "  felix context build --include-hidden"
                Write-Host "  felix context build --force"
                Write-Host "  felix context show"
                Write-Host ""
                Write-Host "Note:" -ForegroundColor Yellow
                Write-Host "  The build command uses the configured agent to autonomously analyze"
                Write-Host "  the project structure, tech stack, and architecture to generate"
                Write-Host "  comprehensive documentation. Existing CONTEXT.md is backed up with"
                Write-Host "  a timestamp before being updated."
                Write-Host ""
            }
            "tui" {
                Write-Host ""
                Write-Host "felix tui" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Launch interactive Terminal UI dashboard with:"
                Write-Host "  - Visual requirement status and progress tracking"
                Write-Host "  - Interactive command menu"
                Write-Host "  - Real-time status visualization"
                Write-Host ""
                Write-Host "Requirements:" -ForegroundColor Yellow
                Write-Host "  - .NET SDK (dotnet CLI)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix tui"
                Write-Host ""
                Write-Host "Navigation:" -ForegroundColor Yellow
                Write-Host "  1-5     Quick actions"
                Write-Host "  /       Show all commands"
                Write-Host "  ?       Help screen"
                Write-Host "  q       Quit dashboard"
                Write-Host ""
            }
            "procs" {
                Write-Host ""
                Write-Host "felix procs [subcommand]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage active agent execution sessions."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  list                   List all active sessions (default)"
                Write-Host "  kill <session-id>      Terminate a running session"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix procs"
                Write-Host "  felix procs list"
                Write-Host "  felix procs kill S-0001-20260208-133511-it1"
                Write-Host ""
                Write-Host "Session Info:" -ForegroundColor Yellow
                Write-Host "  - Session ID (run ID)"
                Write-Host "  - Requirement being executed"
                Write-Host "  - Agent name"
                Write-Host "  - Process ID (PID)"
                Write-Host "  - Running duration"
                Write-Host ""
            }
            default {
                Write-Host "Unknown command: $SubCommand" -ForegroundColor Red
                Show-Help
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "Felix CLI - Development Workflow Automation" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  felix <command> [arguments] [options]"
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  run <req-id>          Execute a single requirement"
        Write-Host "  loop                  Run agent in continuous loop mode"
        Write-Host "  status [req-id]       Show requirement status"
        Write-Host "  list                  List all requirements with filters"
        Write-Host "  validate <req-id>     Run validation checks"
        Write-Host "  deps [req-id]         Show dependencies and validate status"
        Write-Host "  spec <subcommand>     Manage requirement specifications"
        Write-Host "  context <subcommand>  Generate/view project context documentation"
        Write-Host "  agent <subcommand>    Manage and switch agents"
        Write-Host "  procs [subcommand]    Manage active execution sessions"
        Write-Host "  tui                   Launch interactive terminal UI"
        Write-Host "  version               Show version information"
        Write-Host "  help [command]        Show help for a command"
        Write-Host ""
        Write-Host "Global Options:" -ForegroundColor Yellow
        Write-Host "  --format <mode>       Output format: json, plain, rich (default: rich)"
        Write-Host "  --verbose             Enable verbose logging"
        Write-Host "  --quiet               Suppress non-essential output"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix run S-0001"
        Write-Host "  felix loop --max-iterations 5"
        Write-Host "  felix status S-0001 --format json"
        Write-Host "  felix list --status planned"
        Write-Host "  felix validate S-0001"
        Write-Host "  felix deps S-0001 --check"
        Write-Host "  felix spec create ""Add user authentication"""
        Write-Host "  felix context build"
        Write-Host "  felix help run"
        Write-Host ""
    }
}

# Route to appropriate command handler
switch ($Command) {
    "run" {
        Invoke-Run -Args $remainingArgs
    }
    "loop" {
        Invoke-Loop -Args $remainingArgs
    }
    "status" {
        Invoke-Status -Args $remainingArgs
    }
    "list" {
        Invoke-List -Args $remainingArgs
    }
    "validate" {
        Invoke-Validate -Args $remainingArgs
    }
    "deps" {
        Invoke-Deps -Args $remainingArgs
    }
    "spec" {
        & { Invoke-SpecCreate @remainingArgs }
    }
    "context" {
        Invoke-Context -Args $remainingArgs
    }
    "tui" {
        Invoke-Tui
    }
    "agent" {
        Invoke-Agent -AgentArgs $remainingArgs
    }
    "procs" {
        Invoke-ProcessList -Arguments $remainingArgs
    }
    "version" {
        Show-Version
    }
    "help" {
        $subCmd = if ($remainingArgs.Count -gt 0) { $remainingArgs[0] } else { $null }
        Show-Help -SubCommand $subCmd
    }
    default {
        Write-Error "Unknown command: $Command"
        Show-Help
        exit 1
    }
}

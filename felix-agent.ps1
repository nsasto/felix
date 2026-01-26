#!/usr/bin/env pwsh
# Felix Agent - Ralph Loop Executor (PowerShell)
# Usage: .\felix-agent.ps1 <ProjectPath>
#
# VALID REQUIREMENT STATUS VALUES:
#   - draft: Initial state, not ready for work
#   - planned: Ready to be worked on
#   - in_progress: Currently being worked on
#   - complete: Finished and validated
#   - blocked: Cannot proceed (dependencies or validation failures)

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

$ErrorActionPreference = "Stop"

# Resolve project path
$ProjectPath = Resolve-Path $ProjectPath
Write-Host "Felix Agent starting for: $ProjectPath"

# ============================================================================
# Mode Guardrails Functions
# ============================================================================

function Get-GitState {
    <#
    .SYNOPSIS
    Captures the current git state for guardrail comparison
    #>
    param([string]$WorkingDir)
    
    Push-Location $WorkingDir
    try {
        $state = @{
            CommitHash     = $null
            ModifiedFiles  = @()
            UntrackedFiles = @()
        }
        
        # Get current commit hash
        $state.CommitHash = git rev-parse HEAD 2>$null
        
        # Get list of modified files (staged and unstaged)
        $state.ModifiedFiles = @(git diff --name-only HEAD 2>$null)
        $staged = @(git diff --name-only --cached 2>$null)
        if ($staged) {
            $state.ModifiedFiles = @($state.ModifiedFiles) + @($staged) | Select-Object -Unique
        }
        
        # Get untracked files
        $state.UntrackedFiles = @(git ls-files --others --exclude-standard 2>$null)
        
        return $state
    }
    finally {
        Pop-Location
    }
}

function Test-PlanningModeGuardrails {
    <#
    .SYNOPSIS
    Checks if planning mode guardrails were violated (code files modified or committed)
    Returns a hashtable with violation details
    #>
    param(
        [string]$WorkingDir,
        [hashtable]$BeforeState,
        [string]$RunId
    )
    
    Push-Location $WorkingDir
    try {
        $violations = @{
            CommitMade        = $false
            UnauthorizedFiles = @()
            HasViolations     = $false
        }
        
        # Allowed paths for planning mode (relative paths)
        $allowedPatterns = @(
            "^runs/",                          # Run directories
            "^felix/state\.json$",             # State file
            "^felix/requirements\.json$"       # Requirements file
        )
        
        # Get current git state
        $afterState = Get-GitState -WorkingDir $WorkingDir
        
        # Check if a new commit was made
        if ($afterState.CommitHash -ne $BeforeState.CommitHash) {
            $violations.CommitMade = $true
            $violations.HasViolations = $true
            Write-Host "[GUARDRAIL VIOLATION] New commit detected during planning mode!"
        }
        
        # Check for unauthorized file modifications
        $allModifiedFiles = @($afterState.ModifiedFiles) + @($afterState.UntrackedFiles) | 
        Where-Object { $_ -and $_.Trim() -ne "" } |
        Select-Object -Unique
        
        foreach ($file in $allModifiedFiles) {
            # Skip if file was already modified before
            if ($BeforeState.ModifiedFiles -contains $file -or $BeforeState.UntrackedFiles -contains $file) {
                continue
            }
            
            # Check if file matches allowed patterns
            $isAllowed = $false
            $normalizedFile = $file -replace '\\', '/'
            foreach ($pattern in $allowedPatterns) {
                if ($normalizedFile -match $pattern) {
                    $isAllowed = $true
                    break
                }
            }
            
            if (-not $isAllowed) {
                $violations.UnauthorizedFiles += $file
                $violations.HasViolations = $true
            }
        }
        
        if ($violations.UnauthorizedFiles.Count -gt 0) {
            Write-Host "[GUARDRAIL VIOLATION] Unauthorized files modified in planning mode:"
            foreach ($file in $violations.UnauthorizedFiles) {
                Write-Host "  - $file"
            }
        }
        
        return $violations
    }
    finally {
        Pop-Location
    }
}

function Undo-PlanningViolations {
    <#
    .SYNOPSIS
    Reverts unauthorized changes made during planning mode
    #>
    param(
        [string]$WorkingDir,
        [hashtable]$BeforeState,
        [hashtable]$Violations
    )
    
    Push-Location $WorkingDir
    try {
        # Revert commit if one was made
        if ($Violations.CommitMade) {
            Write-Host "[GUARDRAIL] Reverting unauthorized commit..."
            git reset --soft $BeforeState.CommitHash 2>$null
        }
        
        # Revert unauthorized file changes
        foreach ($file in $Violations.UnauthorizedFiles) {
            if (Test-Path $file) {
                # Check if it was an existing file (modified) or new file
                $wasTracked = git ls-files $file 2>$null
                if ($wasTracked) {
                    Write-Host "[GUARDRAIL] Reverting changes to: $file"
                    git checkout HEAD -- $file 2>$null
                }
                else {
                    Write-Host "[GUARDRAIL] Removing unauthorized new file: $file"
                    Remove-Item $file -Force
                }
            }
        }
        
        Write-Host "[GUARDRAIL] Violations reverted."
    }
    finally {
        Pop-Location
    }
}

function Update-RequirementStatus {
    <#
    .SYNOPSIS
    Updates the status of a requirement in felix/requirements.json
    
    .DESCRIPTION
    Valid status values: draft, planned, in_progress, complete, blocked
    #>
    param(
        [string]$RequirementsFilePath,
        [string]$RequirementId,
        [ValidateSet('draft', 'planned', 'in_progress', 'complete', 'blocked')]
        [string]$NewStatus
    )
    
    try {
        # Read current requirements
        $reqData = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        
        # Find and update the requirement
        $found = $false
        foreach ($req in $reqData.requirements) {
            if ($req.id -eq $RequirementId) {
                $req.status = $NewStatus
                $req.updated_at = Get-Date -Format "yyyy-MM-dd"
                $found = $true
                break
            }
        }
        
        if ($found) {
            # Write back to file with proper formatting
            $reqData | ConvertTo-Json -Depth 10 | Set-Content $RequirementsFilePath -Encoding UTF8
            Write-Host "[REQUIREMENTS] Updated $RequirementId status to '$NewStatus'"
            return $true
        }
        else {
            Write-Host "[REQUIREMENTS] Warning: Requirement $RequirementId not found in requirements.json"
            return $false
        }
    }
    catch {
        Write-Host "[REQUIREMENTS] Error updating requirements.json: $_"
        return $false
    }
}

function Resolve-PythonCommand {
    <#
    .SYNOPSIS
    Resolves a usable Python command (application only) with optional args
    #>
    param(
        [object]$Config
    )
    
    $pythonCmd = $null
    $pythonArgs = @()
    
    if ($Config -and $Config.python -and $Config.python.executable) {
        $candidate = $Config.python.executable
        if ($Config.python.args) {
            $pythonArgs = @($Config.python.args)
        }
        
        if (Test-Path $candidate) {
            $pythonCmd = (Resolve-Path $candidate).Path
        }
        else {
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.CommandType -eq "Application") {
                $pythonCmd = $cmd.Source
            }
        }
        
        if (-not $pythonCmd) {
            throw "Python executable not found or not an application: $candidate"
        }
        
        return @{ cmd = $pythonCmd; args = $pythonArgs }
    }
    
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @("-3") }
    }
    
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @() }
    }
    
    $cmd = Get-Command python3 -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @() }
    }
    
    throw "Python executable not found. Set felix/config.json -> python.executable (and optional python.args) or install Python."
}

function Invoke-RequirementValidation {
    <#
    .SYNOPSIS
    Runs scripts/validate-requirement.py with a resolved Python command
    #>
    param(
        [hashtable]$PythonInfo,
        [string]$ValidationScript,
        [string]$RequirementId
    )
    
    $pythonExe = $PythonInfo.cmd
    [array]$pythonArgs = $PythonInfo.args
    
    Write-Host "[VALIDATION] Python: $pythonExe"
    Write-Host "[VALIDATION] Script: $ValidationScript"
    
    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue" # Ensure stderr doesn't crash the loop
    
    try {
        # Fix: Flatten into a single array for clean parameter binding
        [array]$allArguments = @()
        if ($pythonArgs) { $allArguments += $pythonArgs }
        $allArguments += $ValidationScript
        $allArguments += $RequirementId
        
        # Use '@' to splat the array as individual arguments
        $output = & $pythonExe @allArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $prevErrorAction
    }
    
    return @{ output = $output; exitCode = $exitCode }
}

function Get-BackpressureCommands {
    <#
    .SYNOPSIS
    Parses test/build/lint commands from AGENTS.md
    
    .DESCRIPTION
    Looks for these sections in AGENTS.md:
    - "## Run Tests" - test commands
    - "## Build the Project" - build commands
    - "## Lint" - lint commands
    
    Commands are extracted from bash/sh code blocks within these sections.
    
    .PARAMETER AgentsFilePath
    Path to the AGENTS.md file
    
    .PARAMETER ConfigCommands
    Optional array of commands from config.json backpressure.commands
    If provided and non-empty, these take precedence over parsing AGENTS.md
    
    .OUTPUTS
    Array of hashtables with keys: command, type, description
    #>
    param(
        [string]$AgentsFilePath,
        [array]$ConfigCommands = @()
    )
    
    $commands = @()
    
    # If config commands are explicitly provided, use those
    if ($ConfigCommands -and $ConfigCommands.Count -gt 0) {
        Write-Host "[BACKPRESSURE] Using commands from config.json"
        foreach ($cmd in $ConfigCommands) {
            $commands += @{
                command     = $cmd
                type        = "config"
                description = "Command from config.json"
            }
        }
        return $commands
    }
    
    # Parse commands from AGENTS.md
    if (-not (Test-Path $AgentsFilePath)) {
        Write-Host "[BACKPRESSURE] Warning: AGENTS.md not found at $AgentsFilePath"
        return $commands
    }
    
    Write-Host "[BACKPRESSURE] Parsing commands from AGENTS.md"
    $content = Get-Content $AgentsFilePath -Raw
    
    # Define sections to parse and their types
    $sectionPatterns = @(
        @{ pattern = '##\s*Run\s+Tests'; type = 'test'; name = 'Run Tests' }
        @{ pattern = '##\s*Build(\s+the\s+Project)?'; type = 'build'; name = 'Build' }
        @{ pattern = '##\s*Lint'; type = 'lint'; name = 'Lint' }
    )
    
    foreach ($section in $sectionPatterns) {
        # Find section start
        $sectionMatch = [regex]::Match($content, $section.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        if ($sectionMatch.Success) {
            # Get content from section start to next ## header or end of file
            $sectionStart = $sectionMatch.Index + $sectionMatch.Length
            $nextSectionMatch = [regex]::Match($content.Substring($sectionStart), '^##\s', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            
            if ($nextSectionMatch.Success) {
                $sectionContent = $content.Substring($sectionStart, $nextSectionMatch.Index)
            }
            else {
                $sectionContent = $content.Substring($sectionStart)
            }
            
            # Extract code blocks (```bash, ```sh, or ```)
            $codeBlockPattern = '```(?:bash|sh|powershell|pwsh)?\s*\r?\n([\s\S]*?)```'
            $codeBlocks = [regex]::Matches($sectionContent, $codeBlockPattern)
            
            foreach ($block in $codeBlocks) {
                $blockContent = $block.Groups[1].Value
                
                # Parse individual commands from the code block
                $lines = $blockContent -split '\r?\n'
                
                foreach ($line in $lines) {
                    $trimmedLine = $line.Trim()
                    
                    # Skip empty lines, comments, and placeholder lines
                    if (-not $trimmedLine -or 
                        $trimmedLine.StartsWith('#') -or 
                        $trimmedLine -match '^TODO:' -or
                        $trimmedLine -match '^\s*#') {
                        continue
                    }
                    
                    # Skip lines that are clearly not commands (e.g., "Runs on http://...")
                    if ($trimmedLine -match '^(Runs\s+on|API\s+docs|Example)') {
                        continue
                    }
                    
                    # Add the command
                    $commands += @{
                        command     = $trimmedLine
                        type        = $section.type
                        description = "$($section.name): $trimmedLine"
                    }
                }
            }
        }
    }
    
    Write-Host "[BACKPRESSURE] Found $($commands.Count) commands from AGENTS.md"
    foreach ($cmd in $commands) {
        Write-Host "  [$($cmd.type)] $($cmd.command)"
    }
    
    return $commands
}

function Invoke-BackpressureValidation {
    <#
    .SYNOPSIS
    Executes backpressure validation commands (tests, build, lint) after code changes
    
    .DESCRIPTION
    Runs all backpressure commands parsed from AGENTS.md or config.json.
    Returns a result object indicating success/failure and details.
    
    .PARAMETER WorkingDir
    The project working directory
    
    .PARAMETER AgentsFilePath
    Path to the AGENTS.md file
    
    .PARAMETER Config
    The felix config object (for backpressure settings)
    
    .PARAMETER RunDir
    Directory to write validation logs to
    
    .OUTPUTS
    Hashtable with keys: success (bool), failed_commands (array), output (string)
    #>
    param(
        [string]$WorkingDir,
        [string]$AgentsFilePath,
        [object]$Config,
        [string]$RunDir
    )
    
    $result = @{
        success         = $true
        failed_commands = @()
        output          = ""
        skipped         = $false
    }
    
    # Check if backpressure is enabled
    if (-not $Config.backpressure.enabled) {
        Write-Host "[BACKPRESSURE] Backpressure validation is disabled in config"
        $result.skipped = $true
        return $result
    }
    
    # Get backpressure commands
    $configCommands = @()
    if ($Config.backpressure.commands) {
        $configCommands = @($Config.backpressure.commands)
    }
    
    $commands = Get-BackpressureCommands -AgentsFilePath $AgentsFilePath -ConfigCommands $configCommands
    
    if ($commands.Count -eq 0) {
        Write-Host "[BACKPRESSURE] No validation commands found - skipping backpressure"
        $result.skipped = $true
        return $result
    }
    
    Write-Host ""
    Write-Host "[BACKPRESSURE] Running validation commands..."
    Write-Host ""
    
    $allOutput = @()
    
    Push-Location $WorkingDir
    try {
        foreach ($cmd in $commands) {
            Write-Host "  [$($cmd.type)] Executing: $($cmd.command)"
            
            try {
                # Execute the command
                $prevErrorAction = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                $cmdOutput = Invoke-Expression $cmd.command 2>&1
                $exitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevErrorAction
                
                # Convert output to string
                $outputStr = ($cmdOutput | Out-String).Trim()
                $isNoisyTool = $cmd.command -match '\b(npm|vite|pnpm|yarn)\b'
                $hasRemoteException = $outputStr -match 'RemoteException'
                $allOutput += "=== $($cmd.type): $($cmd.command) ==="
                $allOutput += $outputStr
                $allOutput += "Exit code: $exitCode"
                if ($hasRemoteException -and $exitCode -eq 0) {
                    $allOutput += "Warning: stderr output detected (non-fatal)"
                }
                $allOutput += ""
                
                if ($exitCode -ne 0) {
                    Write-Host "    ❌ FAILED (exit code: $exitCode)"
                    $result.success = $false
                    $result.failed_commands += @{
                        command   = $cmd.command
                        type      = $cmd.type
                        exit_code = $exitCode
                        output    = $outputStr
                    }
                }
                else {
                    if ($hasRemoteException -and $isNoisyTool) {
                        Write-Host "    ⚠️  PASSED (stderr output ignored)"
                    }
                    else {
                        Write-Host "    ✅ PASSED"
                    }
                }
            }
            catch {
                Write-Host "    ❌ ERROR: $_"
                $result.success = $false
                $result.failed_commands += @{
                    command   = $cmd.command
                    type      = $cmd.type
                    exit_code = -1
                    output    = $_.ToString()
                }
                $allOutput += "=== $($cmd.type): $($cmd.command) ==="
                $allOutput += "ERROR: $_"
                $allOutput += ""
            }
        }
    }
    finally {
        Pop-Location
    }
    
    $result.output = $allOutput -join "`n"
    
    # Write validation log to run directory
    if ($RunDir -and (Test-Path $RunDir)) {
        $logPath = Join-Path $RunDir "backpressure.log"
        Set-Content $logPath $result.output -Encoding UTF8
        Write-Host ""
        Write-Host "[BACKPRESSURE] Validation log written to: $logPath"
    }
    
    # Summary
    Write-Host ""
    if ($result.success) {
        Write-Host "[BACKPRESSURE] ✅ All validation commands passed!"
    }
    else {
        Write-Host "[BACKPRESSURE] ❌ Validation FAILED - $($result.failed_commands.Count) command(s) failed"
        foreach ($failed in $result.failed_commands) {
            Write-Host "  - [$($failed.type)] $($failed.command)"
        }
    }
    
    return $result
}

# Key paths
$SpecsDir = Join-Path $ProjectPath "specs"
$FelixDir = Join-Path $ProjectPath "felix"
$RunsDir = Join-Path $ProjectPath "runs"
$AgentsFile = Join-Path $ProjectPath "AGENTS.md"
$ConfigFile = Join-Path $FelixDir "config.json"
$StateFile = Join-Path $FelixDir "state.json"
$RequirementsFile = Join-Path $FelixDir "requirements.json"
$PromptsDir = Join-Path $FelixDir "prompts"

# Validate project structure
$requiredPaths = @($SpecsDir, $FelixDir, $ConfigFile, $RequirementsFile)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Write-Host "ERROR: Required path not found: $path"
        Write-Host "This doesn't appear to be a valid Felix project."
        exit 1
    }
}

# Load config
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$maxIterations = $config.executor.max_iterations
$autoTransition = $config.executor.auto_transition
$defaultMode = $config.executor.default_mode

# Resolve python upfront (hard stop if unavailable)
$pythonInfo = $null
try {
    $pythonInfo = Resolve-PythonCommand -Config $config
}
catch {
    Write-Host "[VALIDATION] ❌ Python resolution failed: $_"
    exit 1
}

Write-Host "Max iterations: $maxIterations"
Write-Host ""

# Load requirements
$requirements = Get-Content $RequirementsFile -Raw | ConvertFrom-Json

# Find current requirement (first in_progress or planned)
$currentReq = $requirements.requirements | Where-Object { 
    $_.status -eq "in_progress" 
} | Select-Object -First 1

if (-not $currentReq) {
    $currentReq = $requirements.requirements | Where-Object { 
        $_.status -eq "planned" 
    } | Select-Object -First 1
}

if (-not $currentReq) {
    Write-Host "No requirements to work on (all complete or blocked)"
    exit 0
}

Write-Host "Working on: $($currentReq.id) - $($currentReq.title)"
Write-Host ""

# Initialize state if needed
if (-not (Test-Path $StateFile)) {
    $initialState = @{
        current_requirement_id = $currentReq.id
        last_run_id            = $null
        last_mode              = $null
        last_iteration_outcome = $null
        updated_at             = Get-Date -Format "o"
        current_iteration      = 0
        status                 = "ready"
        blocked_task           = $null
    }
    $initialState | ConvertTo-Json | Set-Content $StateFile
}

# Load state
$state = Get-Content $StateFile -Raw | ConvertFrom-Json

if ($null -eq $state.blocked_task) {
    $state | Add-Member -MemberType NoteProperty -Name blocked_task -Value $null -Force
}

# Main iteration loop
for ($iteration = 1; $iteration -le $maxIterations; $iteration++) {
    Write-Host ""
    Write-Host "═════════════════════════════════════════════════════════════"
    Write-Host "  Felix Agent - Iteration $iteration/$maxIterations"
    
    # Determine mode
    $mode = "building"  # Default
    
    # Look for most recent plan for current requirement in runs/
    $planPattern = "plan-$($currentReq.id).md"
    $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($existingPlans -and $existingPlans.Count -gt 0) {
        # Found plan in runs/ - use building mode
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        
        # Check if plan is substantive
        if ($planContent.Trim().Length -lt 50) {
            $mode = "planning"
        }
    }
    else {
        # No plan exists for current requirement - need to plan
        $mode = "planning"
    }
    
    # Override with state if available
    if ($state.last_mode -and $iteration -eq 1) {
        # Continue in same mode as last run on first iteration
        $mode = $state.last_mode
    }
    
    Write-Host "  Mode: $($mode.ToUpper())"
    Write-Host "═════════════════════════════════════════════════════════════"
    Write-Host ""
    
    # Update state
    $state.current_iteration = $iteration
    $state.last_mode = $mode
    $state.status = "running"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    
    # Create run directory
    $runId = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
    $runDir = Join-Path $RunsDir $runId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    
    # Load prompt template
    $promptFile = Join-Path $PromptsDir "$mode.md"
    if (-not (Test-Path $promptFile)) {
        Write-Host "ERROR: Prompt template not found: $promptFile"
        exit 1
    }
    
    $promptTemplate = Get-Content $promptFile -Raw
    
    # Gather context
    $contextParts = @()
    
    # Add AGENTS.md if exists
    if (Test-Path $AgentsFile) {
        $agentsContent = Get-Content $AgentsFile -Raw
        $contextParts += "# How to Run This Project`n`n$agentsContent"
    }
    
    # Add current requirement spec
    $currentSpecPath = Join-Path $ProjectPath $currentReq.spec_path
    if (Test-Path $currentSpecPath) {
        $specContent = Get-Content $currentSpecPath -Raw
        $contextParts += "# Current Requirement Spec: $($currentReq.id)`n`n$specContent"
    }
    
    # Add CONTEXT.md
    $contextFile = Join-Path $SpecsDir "CONTEXT.md"
    if (Test-Path $contextFile) {
        $contextContent = Get-Content $contextFile -Raw
        $contextParts += "# Project Context`n`n$contextContent"
    }
    
    # Add plan if in building mode
    if ($mode -eq "building" -and $existingPlans -and $existingPlans.Count -gt 0) {
        $latestPlanPath = $existingPlans[0].FullName
        $planContent = Get-Content $latestPlanPath -Raw
        $contextParts += "# Implementation Plan (from $($existingPlans[0].Directory.Name))`n`n$planContent"
        
        # Copy plan to current run for reference
        Copy-Item $latestPlanPath (Join-Path $runDir "plan-$($currentReq.id).md")
    }
    
    # Add requirements status
    $reqSummary = $requirements | ConvertTo-Json -Depth 10
    $contextParts += "# Requirements Status`n`n``````json`n$reqSummary`n``````"
    
    # Add current requirement ID
    $contextParts += "# Current Requirement`n`nYou are working on: **$($currentReq.id)** - $($currentReq.title)"
    
    # Add plan output path instruction
    $planOutputPath = "runs/$runId/plan-$($currentReq.id).md"
    if ($mode -eq "planning") {
        $contextParts += "# Plan Output Path`n`nGenerate your implementation plan and save it to: **$planOutputPath**`n`nThis plan should contain ONLY tasks for requirement $($currentReq.id)."
    }
    else {
        $contextParts += "# Plan Update Path`n`nWhen marking tasks complete, update the plan at: **$planOutputPath**"
    }
    
    # Construct full prompt
    $context = $contextParts -join "`n`n---`n`n"
    $fullPrompt = "$promptTemplate`n`n---`n`n# Project Context`n`n$context"
    
    # Write requirement ID
    Set-Content (Join-Path $runDir "requirement_id.txt") $currentReq.id
    
    # Capture git state before execution (for planning mode guardrails)
    $gitStateBefore = $null
    if ($mode -eq "planning") {
        Write-Host "[GUARDRAIL] Capturing git state before planning iteration..."
        $gitStateBefore = Get-GitState -WorkingDir $ProjectPath
    }
    
    # Call droid exec (like ralph.ps1)
    Write-Host "Calling droid exec...`n"
    
    $droidSuccess = $false
    $droidError = $null
    try {
        $output = $fullPrompt | droid exec --skip-permissions-unsafe 2>&1
        $droidSuccess = $true
    }
    catch {
        $droidError = $_
        Write-Host "ERROR during droid execution: $_"
        
        # Write error report
        $report = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** false
**Timestamp:** $(Get-Date -Format "o")

## Error

``````
$_
``````

"@
        Set-Content (Join-Path $runDir "report.md") $report -Encoding UTF8
        
        $state.last_iteration_outcome = "error"
        $state.status = "error"
        $state.updated_at = Get-Date -Format "o"
        $state | ConvertTo-Json | Set-Content $StateFile
        
        exit 1
    }
    
    # === Post-droid processing (outside try/catch) ===
    Write-Host $output
    
    # Write output log
    Set-Content (Join-Path $runDir "output.log") $output -Encoding UTF8
    
    # ====================================================================
    # Planning Mode Guardrail Enforcement
    # ====================================================================
    $guardrailViolations = $null
    if ($mode -eq "planning" -and $gitStateBefore) {
        Write-Host ""
        Write-Host "[GUARDRAIL] Checking planning mode guardrails..."
        $guardrailViolations = Test-PlanningModeGuardrails -WorkingDir $ProjectPath -BeforeState $gitStateBefore -RunId $runId
        
        if ($guardrailViolations.HasViolations) {
            Write-Host ""
            Write-Host "[GUARDRAIL] VIOLATIONS DETECTED - Reverting unauthorized changes..."
            Undo-PlanningViolations -WorkingDir $ProjectPath -BeforeState $gitStateBefore -Violations $guardrailViolations
            
            # Log the violation in the run directory
            $violationLog = @"
# Guardrail Violation Report

**Mode:** planning
**Run ID:** $runId
**Timestamp:** $(Get-Date -Format "o")

## Violations

**Commit Made:** $($guardrailViolations.CommitMade)

**Unauthorized Files:**
$(($guardrailViolations.UnauthorizedFiles | ForEach-Object { "- $_" }) -join "`n")

## Action Taken

All unauthorized changes have been reverted.
"@
            Set-Content (Join-Path $runDir "guardrail-violation.md") $violationLog -Encoding UTF8
            
            # Update state with guardrail violation
            $state.last_iteration_outcome = "guardrail_violation"
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json | Set-Content $StateFile
            
            Write-Host "[GUARDRAIL] Continuing to next iteration after violation cleanup..."
            Write-Host ""
            continue  # Skip the rest of this iteration and continue to next
        }
        else {
            Write-Host "[GUARDRAIL] No violations detected - planning mode guardrails passed."
        }
    }
    
    # Create report
    $success = $LASTEXITCODE -eq 0
    $report = @"
# Run Report

**Mode:** $mode
**Iteration:** $iteration
**Success:** $success
**Timestamp:** $(Get-Date -Format "o")

## Output

``````
$output
``````

"@
    Set-Content (Join-Path $runDir "report.md") $report -Encoding UTF8
    
    # Check for task completion signal (building mode)
    if ($mode -eq "building" -and $output -match '<promise>TASK_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[TASK DONE] Task completed"
        
        # Run backpressure validation BEFORE committing
        $backpressureResult = Invoke-BackpressureValidation `
            -WorkingDir $ProjectPath `
            -AgentsFilePath $AgentsFile `
            -Config $config `
            -RunDir $runDir
        
        if (-not $backpressureResult.skipped -and -not $backpressureResult.success) {
            # Backpressure failed - do NOT commit, mark task as blocked
            Write-Host ""
            Write-Host "[BACKPRESSURE] ❌ Validation failed - changes will NOT be committed"
            Write-Host "[BACKPRESSURE] Task marked as BLOCKED pending validation fixes"
            
            # Extract task description from output for tracking
            $taskMatch = $output -match '\*\*Task Completed:\*\*\s*(.+?)(?:\r?\n|\*\*)'
            $blockedTaskDesc = if ($matches) { $matches[1].Trim() } else { "Unknown task" }
            
            # Build failed commands summary
            $failedCmdSummary = @()
            foreach ($failed in $backpressureResult.failed_commands) {
                $failedCmdSummary += "[$($failed.type)] $($failed.command) (exit: $($failed.exit_code))"
            }
            
            # Determine retry count - check if this is the same blocked task being retried
            $retryCount = 1
            if ($state.blocked_task -and $state.blocked_task.description -eq $blockedTaskDesc) {
                $retryCount = $state.blocked_task.retry_count + 1
            }
            
            # Get max retries from config (default to 3)
            $maxRetries = if ($config.backpressure.max_retries) { $config.backpressure.max_retries } else { 3 }
            
            # Check if max retries exceeded
            if ($retryCount -gt $maxRetries) {
                Write-Host ""
                Write-Host "[MAX RETRIES] Task has failed validation $retryCount times (max: $maxRetries)"
                Write-Host "[MAX RETRIES] Marking task as PERMANENTLY BLOCKED - requires manual intervention"
                
                $state.last_iteration_outcome = "max_retries_exceeded"
                $state.status = "max_retries_exceeded"
                $state.blocked_task = @{
                    description     = $blockedTaskDesc
                    blocked_at      = Get-Date -Format "o"
                    reason          = "max_retries_exceeded"
                    failed_commands = $failedCmdSummary
                    iteration       = $iteration
                    retry_count     = $retryCount
                    max_retries     = $maxRetries
                }
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
                
                # Write max retries report
                $maxRetriesReport = @"
# Max Retries Exceeded Report

**Task:** $blockedTaskDesc
**Blocked At:** $(Get-Date -Format "o")
**Retry Count:** $retryCount
**Max Retries:** $maxRetries
**Reason:** Validation has failed repeatedly

## Failed Commands

$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)

## Next Steps

This task requires manual intervention. The agent will not retry automatically.
Review the validation failures and fix the underlying issues before restarting.
"@
                Set-Content (Join-Path $runDir "max-retries-exceeded.md") $maxRetriesReport -Encoding UTF8
                
                Write-Host "Exiting due to max retries exceeded..."
                exit 2
            }
            
            Write-Host "[RETRY] Retry attempt $retryCount of $maxRetries"
            
            # Update state to indicate blocked task with details
            $state.last_iteration_outcome = "blocked"
            $state.status = "blocked"
            $state.blocked_task = @{
                description     = $blockedTaskDesc
                blocked_at      = Get-Date -Format "o"
                reason          = "validation_failed"
                failed_commands = $failedCmdSummary
                iteration       = $iteration
                retry_count     = $retryCount
                max_retries     = $maxRetries
            }
            $state.updated_at = Get-Date -Format "o"
            $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
            
            # Write blocked task report to run directory
            $blockedReport = @"
# Blocked Task Report

**Task:** $blockedTaskDesc
**Blocked At:** $(Get-Date -Format "o")
**Reason:** Validation failed
**Retry:** $retryCount of $maxRetries

## Failed Commands

$($failedCmdSummary | ForEach-Object { "- $_" } | Out-String)

## Backpressure Output

``````
$($backpressureResult.output)
``````

## Next Steps

The agent will retry this task in the next iteration ($($maxRetries - $retryCount) attempts remaining).
Fix the validation issues to unblock progress.
"@
            Set-Content (Join-Path $runDir "blocked-task.md") $blockedReport -Encoding UTF8
            Write-Host "[BLOCKED] Details written to: $(Join-Path $runDir 'blocked-task.md')"
            
            # Continue to next iteration - LLM should fix the issues
            Write-Host "Continuing to next iteration to fix validation issues..."
            continue
        }
        
        # Backpressure passed (or was skipped) - clear blocked state and proceed with commit
        if ($state.blocked_task) {
            Write-Host "[UNBLOCKED] Previous blocked task is now passing validation"
            $state.blocked_task = $null
            $state.status = "running"
        }
        
        $gitStatus = git status --porcelain 2>&1
        if ($gitStatus -and $LASTEXITCODE -eq 0) {
            Write-Host "[COMMIT] Uncommitted changes detected, committing..."
            
            # Capture git diff before committing for observability
            Write-Host "[DIFF] Capturing git diff to diff.patch..."
            Push-Location $ProjectPath
            try {
                # Capture both staged and unstaged changes
                $diffOutput = git diff HEAD 2>&1
                if ($diffOutput) {
                    $diffPath = Join-Path $runDir "diff.patch"
                    Set-Content $diffPath $diffOutput -Encoding UTF8
                    Write-Host "[DIFF] Git diff captured: $diffPath"
                }
                else {
                    Write-Host "[DIFF] No diff content to capture"
                }
            }
            catch {
                Write-Host "[DIFF] Warning: Failed to capture git diff: $_"
            }
            finally {
                Pop-Location
            }
            
            # Extract task description from output for commit message
            $taskMatch = $output -match '\*\*Task Completed:\*\*\s*(.+?)(?:\r?\n|\*\*)'
            $taskDesc = if ($matches) { $matches[1].Trim() } else { "Task completion" }
            
            git add -A 2>&1 | Out-Null
            $commitMsg = "Felix ($($currentReq.id)): $taskDesc"
            $commitOutput = git commit -m $commitMsg 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $commitHash = git rev-parse --short HEAD 2>&1
                Write-Host "[COMMIT] ✅ Changes committed: $commitHash - $commitMsg"
            }
            else {
                Write-Host "[COMMIT] ⚠️ Git commit failed: $commitOutput"
            }
        }
        else {
            Write-Host "[COMMIT] No changes to commit (task may have been read-only)"
        }
        
        Write-Host "Continuing to next iteration..."
        # Continue loop to next iteration
    }
    
    # Check for all tasks completion signal (building mode)
    if ($mode -eq "building" -and $output -match '<promise>ALL_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[ALL COMPLETE] All tasks done for requirement!"
        
        # Verify plan actually has no remaining tasks
        $planPattern = "plan-$($currentReq.id).md"
        $existingPlans = Get-ChildItem $RunsDir -Recurse -Filter $planPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        
        if ($existingPlans -and $existingPlans.Count -gt 0) {
            $latestPlanPath = $existingPlans[0].FullName
            $planContent = Get-Content $latestPlanPath -Raw
            
            # Check for unchecked tasks (- [ ])
            $uncheckedTasks = ($planContent | Select-String '- \[ \]' -AllMatches).Matches.Count
            
            if ($uncheckedTasks -gt 0) {
                Write-Host "[WARNING] LLM signaled ALL_COMPLETE but $uncheckedTasks unchecked tasks remain in plan"
                Write-Host "Ignoring signal and continuing to next iteration..."
            }
            else {
                # All tasks truly complete - run validation before marking complete
                Write-Host ""
                Write-Host "[VALIDATION] All plan tasks complete. Running validation..."
                
                # Run validation script
                $validationScript = Join-Path $ProjectPath "scripts" "validate-requirement.py"
                $validationPassed = $false
                
                if (-not (Test-Path $validationScript)) {
                    Write-Host "[VALIDATION] ❌ Validation script not found at $validationScript"
                    exit 1
                }
                
                try {
                    $validationResult = Invoke-RequirementValidation -PythonInfo $pythonInfo -ValidationScript $validationScript -RequirementId $currentReq.id
                    $validationOutput = $validationResult.output
                    $validationExitCode = $validationResult.exitCode
                    
                    Write-Host $validationOutput
                    
                    if ($validationExitCode -eq 0) {
                        Write-Host ""
                        Write-Host "[VALIDATION] ✅ Validation PASSED!"
                        $validationPassed = $true
                    }
                    else {
                        Write-Host ""
                        Write-Host "[VALIDATION] ❌ Validation FAILED (exit code: $validationExitCode)"
                    }
                }
                catch {
                    Write-Host "[VALIDATION] ❌ Error running validation: $_"
                    exit 1
                }
                
                if ($validationPassed) {
                    # Validation passed - mark requirement complete
                    $state.status = "complete"
                    $state.last_iteration_outcome = "complete"
                    $state.updated_at = Get-Date -Format "o"
                    $state | ConvertTo-Json | Set-Content $StateFile
                    
                    # Update requirements.json to mark requirement as complete
                    Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "complete"
                    
                    Write-Host ""
                    Write-Host "Felix Agent complete - all tasks done and validated!"
                    exit 0
                }
                else {
                    # Validation failed - emit STUCK signal
                    Write-Host ""
                    Write-Host "[STUCK] Tasks complete but validation failed!"
                    Write-Host "<promise>STUCK</promise>"
                    
                    $state.last_iteration_outcome = "validation_failed"
                    $state.updated_at = Get-Date -Format "o"
                    $state | ConvertTo-Json | Set-Content $StateFile
                    
                    # Continue to next iteration to allow LLM to fix issues
                }
            }
        }
        else {
            # No plan found - run validation anyway
            Write-Host ""
            Write-Host "[VALIDATION] No plan found. Running validation..."
            
            $validationScript = Join-Path $ProjectPath "scripts" "validate-requirement.py"
            $validationPassed = $false
            
            if (-not (Test-Path $validationScript)) {
                Write-Host "[VALIDATION] ❌ Validation script not found at $validationScript"
                exit 1
            }
            
            try {
                $validationResult = Invoke-RequirementValidation -PythonInfo $pythonInfo -ValidationScript $validationScript -RequirementId $currentReq.id
                $validationOutput = $validationResult.output
                $validationExitCode = $validationResult.exitCode
                
                Write-Host $validationOutput
                
                if ($validationExitCode -eq 0) {
                    Write-Host ""
                    Write-Host "[VALIDATION] ✅ Validation PASSED!"
                    $validationPassed = $true
                }
                else {
                    Write-Host ""
                    Write-Host "[VALIDATION] ❌ Validation FAILED (exit code: $validationExitCode)"
                }
            }
            catch {
                Write-Host "[VALIDATION] ❌ Error running validation: $_"
                exit 1
            }
            
            if ($validationPassed) {
                $state.status = "complete"
                $state.last_iteration_outcome = "complete"
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json | Set-Content $StateFile
                
                # Update requirements.json to mark requirement as complete
                Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $currentReq.id -NewStatus "complete"
                
                Write-Host ""
                Write-Host "Felix Agent complete - all tasks done and validated!"
                exit 0
            }
            else {
                Write-Host ""
                Write-Host "[STUCK] Validation failed!"
                Write-Host "<promise>STUCK</promise>"
                
                $state.last_iteration_outcome = "validation_failed"
                $state.updated_at = Get-Date -Format "o"
                $state | ConvertTo-Json | Set-Content $StateFile
            }
        }
    }
    
    # Check for planning mode signals
    if ($mode -eq "planning" -and $output -match '<promise>PLAN_DRAFT</promise>') {
        Write-Host ""
        Write-Host "[PLAN DRAFT] Initial plan created, will review next iteration"
        # Continue loop for review iteration
    }
    
    if ($mode -eq "planning" -and $output -match '<promise>PLAN_REFINING</promise>') {
        Write-Host ""
        Write-Host "[REFINING] Plan needs refinement, continuing iterations..."
        # Continue loop
    }
    
    if ($mode -eq "planning" -and $output -match '<promise>PLAN_COMPLETE</promise>') {
        Write-Host ""
        Write-Host "[PLAN READY] Planning complete, transitioning to BUILDING mode"
        $state.last_mode = "building"
    }
    
    # Update state
    $state.last_iteration_outcome = "success"
    $state.updated_at = Get-Date -Format "o"
    $state | ConvertTo-Json | Set-Content $StateFile
    
    Write-Host ""
    Write-Host "Iteration $iteration complete. Continuing..."
    Write-Host ""
    
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "[WARNING] Reached max iterations ($maxIterations)"

$state.status = "incomplete"
$state.last_iteration_outcome = "max_iterations"
$state.updated_at = Get-Date -Format "o"
$state | ConvertTo-Json | Set-Content $StateFile

exit 1

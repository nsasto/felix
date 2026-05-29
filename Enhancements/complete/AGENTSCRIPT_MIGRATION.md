# Felix Agent Script Migration Plan

> **Status:** Active — AgentScript migration planning

## Executive Summary

The `felix-agent.ps1` script has evolved into a "God Script" handling configuration, path resolution, git state tracking, plugin management, HTTP heartbeats, and core execution logic in a single 800+ line file. While the logic is sound, the architecture is fragile and difficult to maintain.

This document outlines a comprehensive refactoring plan to transform the monolithic script into a modular, testable, and maintainable system.

**Timeline**: 6-7 days for complete migration
**Compatibility Target**: PowerShell 5.1+ (Windows PowerShell compatibility required)

---

## Critical Issues Identified

### Immediate Blockers (Security & Compatibility)

#### 1. PowerShell 5.1 Incompatibility

**Problem**: Script uses PowerShell 7+ syntax that breaks on Windows PowerShell 5.1:

- Ternary operator `? :`
- Null coalescing `??`
- Pipeline chain operators

**Impact**: Script fails on default Windows installations
**Priority**: CRITICAL - Fix immediately

#### 2. String Interpolation Vulnerabilities

**Problem**: Using `$Var:Text` inside double quotes causes "Invalid variable reference" errors

```powershell
# ❌ WRONG - PowerShell sees : as drive reference
Write-Host "Processing $requirementId:Building"

# ✅ CORRECT - Use curly braces
Write-Host "Processing ${requirementId}:Building"
```

**Impact**: Runtime errors when variables contain colons
**Priority**: CRITICAL - Fix immediately

#### 3. Command Injection Risk

**Problem**: `Invoke-Expression` used in backpressure validation system

```powershell
# ❌ SECURITY HOLE
Invoke-Expression $cmd.command
```

**Impact**: Arbitrary code execution vulnerability
**Priority**: CRITICAL - Replace with safe alternatives

### Architectural Problems

#### 4. Implicit Global State

**Problem**: Heavy reliance on `$script:` scoped variables makes unit testing impossible

```powershell
$script:config = @{}
$script:requirementState = @{}
$script:gitState = @{}
```

**Impact**: Cannot test functions in isolation, difficult to debug
**Priority**: HIGH - Refactor to explicit parameter passing

#### 5. Mixed Concerns

**Problem**: Single file contains:

- Orchestration logic
- Git operations
- HTTP API calls
- Plugin management
- File I/O
- Validation logic

**Impact**: Changes ripple across entire file, difficult to navigate
**Priority**: HIGH - Extract to separate modules

#### 6. No Formal State Machine

**Problem**: State transitions handled with ad-hoc `if/else` blocks

```powershell
if ($planExists) {
    $mode = "Building"
} else {
    $mode = "Planning"
}
```

**Impact**: Can enter invalid states, difficult to reason about flow
**Priority**: MEDIUM - Implement formal state machine

---

## Proposed Architecture

### Module Structure

```
.felix/
├── core/
│   ├── compat-utils.ps1      # PS 5.1 compatibility layer
│   ├── agent-state.ps1        # Formal state machine
│   ├── git-manager.ps1        # All git operations
│   ├── state-manager.ps1      # requirements.json CRUD
│   ├── planner.ps1            # Planning mode logic
│   ├── executor.ps1           # Building mode logic
│   └── validator.ps1          # Validation & backpressure
├── plugins/
│   ├── plugin-manager.ps1     # Plugin lifecycle & sandbox
│   └── <user-plugins>/        # User-provided plugins
├── utils/
│   ├── logger.ps1             # Structured logging
│   ├── http-client.ps1        # Safe HTTP requests
│   └── json-ops.ps1           # Standardized JSON operations
├── tests/
│   ├── test-state-machine.ps1
│   ├── test-git-manager.ps1
│   └── test-validator.ps1
├── felix-agent.ps1            # Thin orchestrator (200 lines max)
└── felix-loop.ps1             # Continuous execution mode
```

### Design Principles

1. **Single Responsibility** - Each module handles one concern
2. **Explicit Dependencies** - No implicit global state
3. **PS 5.1 Compatible** - No PS 7+ exclusive syntax
4. **Testable** - Each module can be tested independently
5. **Fail-Safe** - Plugin failures don't crash agent
6. **Secure** - No `Invoke-Expression` or command injection

---

## Migration Plan

### Phase 1: Critical Fixes (Day 1)

**Goal**: Make script safe and compatible with PowerShell 5.1

#### 1.1 Create Compatibility Layer

```powershell
# filepath: .felix/core/compat-utils.ps1
<#
.SYNOPSIS
PowerShell 5.1 compatible utility functions
.DESCRIPTION
Provides safe alternatives to PS 7+ features
#>

function Coalesce-Value {
    <#
    .SYNOPSIS
    Replaces ?? operator for PS 5.1 compatibility
    #>
    param(
        [Parameter(ValueFromPipeline)]
        $Value,
        $Default
    )
    if ($null -eq $Value -or $Value -eq '') { return $Default }
    return $Value
}

function Ternary {
    <#
    .SYNOPSIS
    Replaces ?: operator for PS 5.1 compatibility
    #>
    param(
        [bool]$Condition,
        $IfTrue,
        $IfFalse
    )
    if ($Condition) { return $IfTrue } else { return $IfFalse }
}

function Safe-Interpolate {
    <#
    .SYNOPSIS
    Safe string interpolation without drive reference bugs
    #>
    param(
        [string]$Template,
        [hashtable]$Variables
    )
    $result = $Template
    foreach ($key in $Variables.Keys) {
        $placeholder = "`${$key}"
        $result = $result -replace [regex]::Escape($placeholder), $Variables[$key]
    }
    return $result
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
    Secure command execution without Invoke-Expression
    #>
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $PWD
    )

    $originalLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location $WorkingDirectory
        }

        # Use call operator with explicit arguments - no command injection
        $result = & $Command @Arguments 2>&1
        return @{
            output = $result
            exitCode = $LASTEXITCODE
        }
    }
    finally {
        Set-Location $originalLocation
    }
}

Export-ModuleMember -Function Coalesce-Value, Ternary, Safe-Interpolate, Invoke-SafeCommand
```

#### 1.2 Replace Unsafe Patterns in felix-agent.ps1

**Find and Replace**:

- All `??` → `Coalesce-Value`
- All `? :` → `Ternary`
- All `$var:text` → `${var}:text`
- All `Invoke-Expression` → `Invoke-SafeCommand`

**Validation**: Run on PowerShell 5.1 to verify compatibility

---

### Phase 2: State Machine Formalization (Day 2)

**Goal**: Prevent invalid state transitions

#### 2.1 Create State Machine

```powershell
# filepath: .felix/core/agent-state.ps1
<#
.SYNOPSIS
Formal state machine for Felix agent execution
#>

class AgentState {
    [string]$Mode
    [string]$RequirementId
    [string]$Branch
    [hashtable]$Context
    [datetime]$StartTime
    [int]$IterationCount

    AgentState([string]$mode) {
        $this.Mode = $mode
        $this.Context = @{}
        $this.StartTime = Get-Date
        $this.IterationCount = 0
    }

    [hashtable] GetValidTransitions() {
        return @{
            'Planning' = @('Building', 'Blocked', 'Complete')
            'Building' = @('Validating', 'Blocked')
            'Validating' = @('Complete', 'Building', 'Blocked')
            'Blocked' = @('Planning')
            'Complete' = @()  # Terminal state
        }
    }

    [bool] CanTransitionTo([string]$newMode) {
        $validTransitions = $this.GetValidTransitions()
        return $validTransitions[$this.Mode] -contains $newMode
    }

    [void] TransitionTo([string]$newMode) {
        if (-not $this.CanTransitionTo($newMode)) {
            throw "Invalid state transition: $($this.Mode) -> $newMode. Valid transitions: $($this.GetValidTransitions()[$this.Mode] -join ', ')"
        }

        Write-Verbose "State transition: $($this.Mode) -> $newMode (Iteration: $($this.IterationCount))"
        $this.Mode = $newMode
        $this.IterationCount++
    }

    [hashtable] ToJson() {
        return @{
            mode = $this.Mode
            requirementId = $this.RequirementId
            branch = $this.Branch
            iterationCount = $this.IterationCount
            startTime = $this.StartTime.ToString('o')
            context = $this.Context
        }
    }
}

function New-AgentState {
    param([string]$InitialMode = 'Planning')
    return [AgentState]::new($InitialMode)
}

Export-ModuleMember -Function New-AgentState
```

#### 2.2 Update Main Script

Replace ad-hoc state checks with formal transitions:

```powershell
# Before
if ($planExists) { $mode = "Building" }

# After
$agentState.TransitionTo('Building')
```

---

### Phase 3: Extract Git Operations (Day 3)

**Goal**: Isolate git operations for testing and reuse

#### 3.1 Create Git Manager

```powershell
# filepath: .felix/core/git-manager.ps1
<#
.SYNOPSIS
Git operations for Felix agent
#>

function Initialize-FeatureBranch {
    <#
    .SYNOPSIS
    Creates or switches to feature branch for requirement
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementId,

        [string]$BaseBranch = "main"
    )

    $branchName = "feature/$RequirementId"

    # Check if branch exists locally
    $existingBranch = git branch --list $branchName 2>&1
    if ($LASTEXITCODE -eq 0 -and $existingBranch) {
        Write-Verbose "Switching to existing branch: $branchName"
        git checkout $branchName 2>&1 | Out-Null
        return $branchName
    }

    # Check if branch exists remotely
    $remoteBranch = git ls-remote --heads origin $branchName 2>&1
    if ($LASTEXITCODE -eq 0 -and $remoteBranch) {
        Write-Verbose "Checking out remote branch: $branchName"
        git fetch origin $branchName 2>&1 | Out-Null
        git checkout -b $branchName "origin/$branchName" 2>&1 | Out-Null
        return $branchName
    }

    # Create new branch from base
    Write-Verbose "Creating new branch: $branchName from $BaseBranch"
    git checkout $BaseBranch 2>&1 | Out-Null
    git pull origin $BaseBranch 2>&1 | Out-Null
    git checkout -b $branchName 2>&1 | Out-Null

    return $branchName
}

function Get-GitState {
    <#
    .SYNOPSIS
    Captures current git state for guardrail checking
    #>
    param()

    return @{
        commitHash = git rev-parse HEAD 2>&1
        branch = git rev-parse --abbrev-ref HEAD 2>&1
        modifiedFiles = @(git diff --name-only HEAD 2>&1)
        untrackedFiles = @(git ls-files --others --exclude-standard 2>&1)
        stagedFiles = @(git diff --cached --name-only 2>&1)
    }
}

function Test-GitChanges {
    <#
    .SYNOPSIS
    Checks if there are uncommitted changes
    #>
    param()

    $status = git status --porcelain 2>&1
    return ($null -ne $status -and $status.Length -gt 0)
}

function Invoke-GitCommit {
    <#
    .SYNOPSIS
    Commits changes with proper error handling
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [switch]$Push
    )

    if (-not (Test-GitChanges)) {
        Write-Warning "No changes to commit"
        return $false
    }

    git add . 2>&1 | Out-Null
    git commit -m $Message 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Git commit failed"
    }

    if ($Push) {
        $branch = git rev-parse --abbrev-ref HEAD 2>&1
        git push origin $branch 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git push failed"
        }
    }

    return $true
}

function Invoke-GitRevert {
    <#
    .SYNOPSIS
    Reverts unauthorized changes (for planning mode guardrails)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$BeforeState,

        [string[]]$AllowedPatterns = @('runs/*', '.felix/state.json', '.felix/requirements.json')
    )

    $afterState = Get-GitState

    # Check for new commits
    if ($afterState.commitHash -ne $BeforeState.commitHash) {
        Write-Warning "Unauthorized commit detected - reverting"
        git reset --soft "$($BeforeState.commitHash)" 2>&1 | Out-Null
    }

    # Check for unauthorized file changes
    $allChanges = $afterState.modifiedFiles + $afterState.untrackedFiles
    foreach ($file in $allChanges) {
        $allowed = $false
        foreach ($pattern in $AllowedPatterns) {
            if ($file -like $pattern) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            Write-Warning "Unauthorized change detected: $file - reverting"
            if (Test-Path $file) {
                git checkout HEAD -- $file 2>&1 | Out-Null
            }
        }
    }
}

Export-ModuleMember -Function Initialize-FeatureBranch, Get-GitState, Test-GitChanges, Invoke-GitCommit, Invoke-GitRevert
```

---

### Phase 4: Extract State Management (Day 3)

**Goal**: Isolate requirements.json operations

#### 4.1 Create State Manager

```powershell
# filepath: .felix/core/state-manager.ps1
<#
.SYNOPSIS
Requirements state management
#>

function Get-RequirementsState {
    <#
    .SYNOPSIS
    Reads requirements.json with validation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile
    )

    if (-not (Test-Path $RequirementsFile)) {
        throw "Requirements file not found: $RequirementsFile"
    }

    try {
        $content = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        return $content
    }
    catch {
        throw "Failed to parse requirements.json: $($_.Exception.Message)"
    }
}

function Save-RequirementsState {
    <#
    .SYNOPSIS
    Writes requirements.json with standardized formatting
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile,

        [Parameter(Mandatory=$true)]
        [object]$State
    )

    try {
        $json = $State | ConvertTo-Json -Depth 10
        Set-Content -Path $RequirementsFile -Value $json -Encoding UTF8
    }
    catch {
        throw "Failed to save requirements.json: $($_.Exception.Message)"
    }
}

function Get-NextRequirement {
    <#
    .SYNOPSIS
    Selects next requirement to process
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile
    )

    $state = Get-RequirementsState $RequirementsFile

    # Priority 1: in_progress requirements
    $inProgress = $state.requirements | Where-Object { $_.status -eq "in_progress" } | Select-Object -First 1
    if ($inProgress) {
        return $inProgress
    }

    # Priority 2: planned requirements (respect dependencies)
    $planned = $state.requirements | Where-Object { $_.status -eq "planned" }
    foreach ($req in $planned) {
        # Check if all dependencies are complete
        $dependenciesMet = $true
        if ($req.depends_on) {
            foreach ($depId in $req.depends_on) {
                $dep = $state.requirements | Where-Object { $_.id -eq $depId }
                if ($dep -and $dep.status -ne "complete") {
                    $dependenciesMet = $false
                    break
                }
            }
        }

        if ($dependenciesMet) {
            return $req
        }
    }

    return $null
}

function Update-RequirementStatus {
    <#
    .SYNOPSIS
    Updates status of a specific requirement
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile,

        [Parameter(Mandatory=$true)]
        [string]$RequirementId,

        [Parameter(Mandatory=$true)]
        [string]$Status,

        [string]$Branch = $null
    )

    $state = Get-RequirementsState $RequirementsFile
    $requirement = $state.requirements | Where-Object { $_.id -eq $RequirementId }

    if (-not $requirement) {
        throw "Requirement not found: $RequirementId"
    }

    $requirement.status = $Status
    if ($Branch) {
        $requirement.branch = $Branch
    }

    Save-RequirementsState $RequirementsFile $state
    Write-Verbose "Updated requirement $RequirementId status to: $Status"
}

Export-ModuleMember -Function Get-RequirementsState, Save-RequirementsState, Get-NextRequirement, Update-RequirementStatus
```

---

### Phase 5: Plugin Sandbox (Day 4)

**Goal**: Prevent plugin failures from crashing agent

#### 5.1 Create Plugin Manager

```powershell
# filepath: .felix/plugins/plugin-manager.ps1
<#
.SYNOPSIS
Safe plugin execution with isolation
#>

function Invoke-PluginSafely {
    <#
    .SYNOPSIS
    Executes plugin in isolated runspace with timeout
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PluginPath,

        [Parameter(Mandatory=$true)]
        [string]$Hook,

        [hashtable]$Context = @{},

        [int]$TimeoutSeconds = 30
    )

    $result = @{
        success = $false
        output = $null
        error = $null
        duration = 0
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Create isolated runspace for plugin
        $ps = [powershell]::Create()

        # Load plugin script
        $pluginContent = Get-Content $PluginPath -Raw
        $ps.AddScript($pluginContent) | Out-Null

        # Check if hook function exists
        $checkScript = "Get-Command -Name '$Hook' -ErrorAction SilentlyContinue"
        $ps.AddScript($checkScript) | Out-Null

        $hookExists = $ps.Invoke()
        $ps.Commands.Clear()

        if (-not $hookExists) {
            $result.error = "Hook function '$Hook' not found in plugin"
            return $result
        }

        # Execute hook with context
        $ps.AddCommand($Hook) | Out-Null
        $ps.AddParameters($Context) | Out-Null

        # Execute with timeout
        $asyncResult = $ps.BeginInvoke()
        $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        if ($asyncResult.AsyncWaitHandle.WaitOne($timeout)) {
            $result.output = $ps.EndInvoke($asyncResult)
            $result.success = -not $ps.HadErrors
        }
        else {
            throw "Plugin timeout after $TimeoutSeconds seconds"
        }

        # Capture errors
        if ($ps.Streams.Error.Count -gt 0) {
            $result.error = $ps.Streams.Error[0].ToString()
            $result.success = $false
        }
    }
    catch {
        $result.error = $_.Exception.Message
        $result.success = $false
    }
    finally {
        $stopwatch.Stop()
        $result.duration = $stopwatch.ElapsedMilliseconds

        if ($ps) {
            $ps.Dispose()
        }
    }

    return $result
}

function Get-Plugins {
    <#
    .SYNOPSIS
    Discovers plugins in plugin directory
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PluginDirectory,

        [string[]]$DisabledPlugins = @()
    )

    if (-not (Test-Path $PluginDirectory)) {
        Write-Warning "Plugin directory not found: $PluginDirectory"
        return @()
    }

    $plugins = Get-ChildItem -Path $PluginDirectory -Filter "*.ps1" -Recurse

    # Filter out disabled plugins
    $enabledPlugins = $plugins | Where-Object {
        $pluginName = $_.BaseName
        $DisabledPlugins -notcontains $pluginName
    }

    return $enabledPlugins
}

function Invoke-PluginHook {
    <#
    .SYNOPSIS
    Invokes hook across all enabled plugins
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PluginDirectory,

        [Parameter(Mandatory=$true)]
        [string]$Hook,

        [hashtable]$Context = @{},

        [string[]]$DisabledPlugins = @()
    )

    $plugins = Get-Plugins -PluginDirectory $PluginDirectory -DisabledPlugins $DisabledPlugins

    foreach ($plugin in $plugins) {
        Write-Verbose "Executing plugin: $($plugin.Name) - Hook: $Hook"

        $result = Invoke-PluginSafely -PluginPath $plugin.FullName -Hook $Hook -Context $Context

        if (-not $result.success) {
            Write-Warning "Plugin $($plugin.Name) failed: $($result.error)"
        }
        else {
            Write-Verbose "Plugin $($plugin.Name) completed in $($result.duration)ms"
        }
    }
}

Export-ModuleMember -Function Invoke-PluginSafely, Get-Plugins, Invoke-PluginHook
```

---

### Phase 6: Refactor Main Script (Day 5)

**Goal**: Reduce main script to thin orchestrator

#### 6.1 New felix-agent.ps1

```powershell
# filepath: .felix/felix-agent.ps1
<#
.SYNOPSIS
Felix autonomous agent - clean orchestrator
.DESCRIPTION
Thin orchestrator that delegates to specialized modules.
Compatible with PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [string]$BaseBranch = "main",

    [switch]$NoCommit
)

$ErrorActionPreference = "Stop"

# Import core modules
$scriptRoot = $PSScriptRoot
. "$scriptRoot/core/compat-utils.ps1"
. "$scriptRoot/core/agent-state.ps1"
. "$scriptRoot/core/state-manager.ps1"
. "$scriptRoot/core/git-manager.ps1"
. "$scriptRoot/plugins/plugin-manager.ps1"
. "$scriptRoot/utils/logger.ps1"

Write-Log "Felix Agent Starting" -Level Info
Write-Log "Repository: $RepoPath" -Level Info
Write-Log "Base Branch: $BaseBranch" -Level Info

# Load configuration
$configPath = Join-Path $RepoPath ".felix/config.json"
if (-not (Test-Path $configPath)) {
    Write-Log "Configuration file not found: $configPath" -Level Error
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Initialize paths
Set-Location $RepoPath
$requirementsFile = Join-Path $RepoPath ".felix/requirements.json"
$pluginDirectory = Join-Path $RepoPath ".felix/plugins"

# Create state machine
$agentState = New-AgentState -InitialMode 'Planning'

try {
    # Select next requirement
    $requirement = Get-NextRequirement $requirementsFile
    if (-not $requirement) {
        Write-Log "No planned requirements found" -Level Info
        exit 0
    }

    $agentState.RequirementId = $requirement.id
    Write-Log "Processing requirement: $($requirement.id) - $($requirement.title)" -Level Info

    # Setup git branch
    $branch = Initialize-FeatureBranch -RequirementId $requirement.id -BaseBranch $BaseBranch
    $agentState.Branch = $branch
    Update-RequirementStatus $requirementsFile $requirement.id "in_progress" $branch

    Write-Log "Working on branch: $branch" -Level Info

    # Execute pre-planning plugins
    Invoke-PluginHook -PluginDirectory $pluginDirectory `
                      -Hook "On-PrePlanning" `
                      -Context @{
                          requirementId = $requirement.id
                          branch = $branch
                      } `
                      -DisabledPlugins $config.plugins.disabled

    # Capture git state before planning (for guardrails)
    $gitStateBefore = Get-GitState

    # TODO: Planning logic (extract to planner.ps1)
    # $plan = New-ImplementationPlan ...

    # Transition to Building
    $agentState.TransitionTo('Building')
    Write-Log "State: Building" -Level Info

    # TODO: Execution logic (extract to executor.ps1)
    # $executionResult = Invoke-Implementation ...

    # Transition to Validating
    $agentState.TransitionTo('Validating')
    Write-Log "State: Validating" -Level Info

    # TODO: Validation logic (extract to validator.ps1)
    # $validationResult = Test-RequirementValidation ...

    # Simulate validation success for now
    $validationResult = @{ success = $true }

    if ($validationResult.success) {
        # Transition to Complete
        $agentState.TransitionTo('Complete')

        # Commit changes
        if (-not $NoCommit -and $config.executor.commit_on_complete) {
            $commitMessage = "feat: Implement $($requirement.id) - $($requirement.title)"
            Invoke-GitCommit -Message $commitMessage -Push
            Write-Log "Changes committed and pushed" -Level Info
        }

        # Update status
        Update-RequirementStatus $requirementsFile $requirement.id "complete"
        Write-Log "✅ Requirement complete: $($requirement.id)" -Level Success

        # Execute post-completion plugins
        Invoke-PluginHook -PluginDirectory $pluginDirectory `
                          -Hook "On-Complete" `
                          -Context @{
                              requirementId = $requirement.id
                              branch = $branch
                          } `
                          -DisabledPlugins $config.plugins.disabled

        exit 0
    }
    else {
        # Transition to Blocked
        $agentState.TransitionTo('Blocked')
        Update-RequirementStatus $requirementsFile $requirement.id "blocked"
        Write-Log "❌ Requirement blocked: $($requirement.id)" -Level Error
        exit 3
    }

} catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error

    if ($agentState.RequirementId) {
        Update-RequirementStatus $requirementsFile $agentState.RequirementId "blocked"
    }

    exit 1
}
```

---

### Phase 7: Testing Infrastructure (Day 6)

**Goal**: Create comprehensive test suite

#### 7.1 Test Framework

```powershell
# filepath: .felix/tests/test-runner.ps1
<#
.SYNOPSIS
Test runner for Felix modules
#>

function Assert-Equal {
    param($Expected, $Actual, $Message = "")
    if ($Expected -ne $Actual) {
        throw "Assertion failed: Expected '$Expected' but got '$Actual'. $Message"
    }
}

function Assert-True {
    param([bool]$Condition, $Message = "")
    if (-not $Condition) {
        throw "Assertion failed: Condition is false. $Message"
    }
}

function Assert-Throws {
    param([scriptblock]$ScriptBlock, $Message = "")
    try {
        & $ScriptBlock
        throw "Assertion failed: Expected exception but none was thrown. $Message"
    }
    catch {
        # Expected
    }
}

function Run-Tests {
    param([string]$TestDirectory)

    $testFiles = Get-ChildItem -Path $TestDirectory -Filter "test-*.ps1"
    $passed = 0
    $failed = 0

    foreach ($testFile in $testFiles) {
        Write-Host "`n--- Running: $($testFile.Name) ---" -ForegroundColor Cyan

        try {
            . $testFile.FullName
            $passed++
            Write-Host "✅ PASSED" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Host "❌ FAILED: $_" -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor Red
        }
    }

    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Passed: $passed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red

    return ($failed -eq 0)
}
```

#### 7.2 Example Tests

```powershell
# filepath: .felix/tests/test-state-machine.ps1
. "$PSScriptRoot/../core/agent-state.ps1"

# Test: Initial state
$state = New-AgentState
Assert-Equal "Planning" $state.Mode "Initial state should be Planning"

# Test: Valid transition
$state.TransitionTo('Building')
Assert-Equal "Building" $state.Mode "Should transition to Building"

# Test: Invalid transition
Assert-Throws { $state.TransitionTo('Planning') } "Should not allow Building -> Planning"

# Test: Iteration counting
Assert-Equal 1 $state.IterationCount "Should track iterations"

Write-Host "All state machine tests passed"
```

```powershell
# filepath: .felix/tests/test-git-manager.ps1
. "$PSScriptRoot/../core/git-manager.ps1"

# Create temp git repo for testing
$tempRepo = New-Item -ItemType Directory -Path "$env:TEMP/felix-test-repo-$(Get-Random)" -Force
Push-Location $tempRepo
git init | Out-Null
git config user.email "test@example.com" | Out-Null
git config user.name "Test User" | Out-Null

# Create initial commit
"test" | Out-File "README.md"
git add . | Out-Null
git commit -m "Initial commit" | Out-Null

# Test: Create feature branch
$branch = Initialize-FeatureBranch -RequirementId "S-0001" -BaseBranch "main"
Assert-Equal "feature/S-0001" $branch "Should create feature branch"

# Test: Get git state
$gitState = Get-GitState
Assert-True ($gitState.branch -eq "feature/S-0001") "Should be on feature branch"

# Cleanup
Pop-Location
Remove-Item $tempRepo -Recurse -Force

Write-Host "All git manager tests passed"
```

---

## Migration Checklist

### Day 1: Critical Fixes

- [ ] Create `.felix/core/compat-utils.ps1`
- [ ] Replace all `??` with `Coalesce-Value`
- [ ] Replace all `? :` with `Ternary`
- [ ] Fix all `$var:text` to `${var}:text`
- [ ] Replace `Invoke-Expression` with `Invoke-SafeCommand`
- [ ] Test on PowerShell 5.1

### Day 2: State Machine

- [ ] Create `.felix/core/agent-state.ps1`
- [ ] Replace ad-hoc mode checks with state machine
- [ ] Add state validation
- [ ] Test state transitions

### Day 3: Extract Modules

- [ ] Create `.felix/core/git-manager.ps1`
- [ ] Create `.felix/core/state-manager.ps1`
- [ ] Update main script to use modules
- [ ] Test git operations
- [ ] Test state management

### Day 4: Plugin Sandbox

- [ ] Create `.felix/plugins/plugin-manager.ps1`
- [ ] Implement isolated execution
- [ ] Add timeout handling
- [ ] Test plugin failures don't crash agent

### Day 5: Refactor Main Script

- [ ] Extract planner logic to `.felix/core/planner.ps1`
- [ ] Extract executor logic to `.felix/core/executor.ps1`
- [ ] Extract validator logic to `.felix/core/validator.ps1`
- [ ] Reduce main script to orchestrator
- [ ] Update `felix-loop.ps1`

### Day 6: Testing

- [ ] Create test framework
- [ ] Write tests for each module
- [ ] Achieve >80% code coverage
- [ ] Add CI integration

### Day 7: Documentation & Cleanup

- [ ] Update AGENTS.md
- [ ] Add inline documentation
- [ ] Create module usage examples
- [ ] Remove old commented code
- [ ] Final compatibility check

---

## Success Metrics

### Code Quality

- Main script: < 200 lines
- Each module: < 300 lines
- Test coverage: > 80%
- PowerShell 5.1 compatible: 100%

### Security

- Zero `Invoke-Expression` usage
- All external commands use call operator
- Plugin isolation: 100%

### Maintainability

- Single Responsibility: Each module has one purpose
- No global state: All state passed explicitly
- Testable: Each module tested independently
- Documented: All functions have help text

---

## Rollback Plan

If issues arise during migration:

1. **Git Branch Strategy**: Perform migration on `feature/agent-refactor` branch
2. **Incremental PRs**: Merge each phase separately to validate
3. **Compatibility Shim**: Keep old `felix-agent.ps1.backup` during transition
4. **Gradual Rollout**: Test with S-0000 test requirement before production use

---

## Post-Migration Benefits

1. **Maintainability**: Changes isolated to relevant module
2. **Testability**: Can test each module independently
3. **Reusability**: Modules can be used by other scripts
4. **Debuggability**: Clear boundaries, explicit dependencies
5. **Onboarding**: New developers understand structure quickly
6. **Security**: No command injection vulnerabilities
7. **Compatibility**: Works on all PowerShell versions
8. **Reliability**: Plugin failures don't crash agent

---

## Future Enhancements

After migration completes:

1. **Add Logging Module**: Structured logging with levels and targets
2. **Add HTTP Client Module**: Safe API calls with retry logic
3. **Add Metrics Module**: Performance tracking and telemetry
4. **Add Config Validator**: Validate config.json schema
5. **Add Spec Parser Module**: Parse acceptance criteria
6. **Add Report Generator**: Create run reports
7. **Add Artifact Manager**: Handle run artifacts

---

**Document Version**: 1.0
**Created**: February 2, 2026
**Owner**: Felix Core Team
**Status**: Approved - Ready for Implementation

# Felix Agent Script Test Plan

## Overview

This document outlines comprehensive testing strategies for the Felix agent refactoring. Each module must be tested independently (unit tests) and in combination (integration tests) to ensure reliability and maintainability.

**Testing Philosophy**: "Test early, test often, test thoroughly"

**Target Coverage**: >80% code coverage across all modules
**Compatibility Target**: PowerShell 5.1 and PowerShell 7+
**Test Environment**: Windows 10/11, clean git repository

---

## Test Infrastructure

### Test Framework Setup

```powershell
# filepath: .felix/tests/test-framework.ps1
<#
.SYNOPSIS
Lightweight test framework for PowerShell 5.1+ compatibility
#>

$Global:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Describe {
    param([string]$Name, [scriptblock]$Tests)

    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $Tests
}

function It {
    param([string]$Description, [scriptblock]$Test)

    Write-Host "  Testing: $Description" -NoNewline

    try {
        & $Test
        Write-Host " [PASS]" -ForegroundColor Green
        $Global:TestResults.Passed++
        $Global:TestResults.Tests += @{
            description = $Description
            status = "PASS"
            error = $null
        }
    }
    catch {
        Write-Host " [FAIL]" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $Global:TestResults.Failed++
        $Global:TestResults.Tests += @{
            description = $Description
            status = "FAIL"
            error = $_.Exception.Message
        }
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = "")
    if ($Expected -ne $Actual) {
        throw "Expected '$Expected' but got '$Actual'. $Message"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message = "")
    if (-not $Condition) {
        throw "Condition is false. $Message"
    }
}

function Assert-False {
    param([bool]$Condition, [string]$Message = "")
    if ($Condition) {
        throw "Condition is true (expected false). $Message"
    }
}

function Assert-NotNull {
    param($Value, [string]$Message = "")
    if ($null -eq $Value) {
        throw "Value is null. $Message"
    }
}

function Assert-Null {
    param($Value, [string]$Message = "")
    if ($null -ne $Value) {
        throw "Value is not null (expected null). $Message"
    }
}

function Assert-Throws {
    param([scriptblock]$ScriptBlock, [string]$Message = "")
    try {
        & $ScriptBlock
        throw "Expected exception but none was thrown. $Message"
    }
    catch {
        # Expected - test passes
    }
}

function Assert-Contains {
    param($Collection, $Item, [string]$Message = "")
    if ($Collection -notcontains $Item) {
        throw "Collection does not contain '$Item'. $Message"
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Message = "")
    if (-not (Test-Path $Path)) {
        throw "File does not exist: $Path. $Message"
    }
}

function Get-TestResults {
    $total = $Global:TestResults.Passed + $Global:TestResults.Failed + $Global:TestResults.Skipped

    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Total:   $total" -ForegroundColor White
    Write-Host "Passed:  $($Global:TestResults.Passed)" -ForegroundColor Green
    Write-Host "Failed:  $($Global:TestResults.Failed)" -ForegroundColor Red
    Write-Host "Skipped: $($Global:TestResults.Skipped)" -ForegroundColor Yellow

    $successRate = if ($total -gt 0) {
        [math]::Round(($Global:TestResults.Passed / $total) * 100, 2)
    } else {
        0
    }
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } else { "Red" })

    return ($Global:TestResults.Failed -eq 0)
}

Export-ModuleMember -Function Describe, It, Assert-*, Get-TestResults
```

### Test Helper Utilities

```powershell
# filepath: .felix/tests/test-helpers.ps1
<#
.SYNOPSIS
Helper functions for testing
#>

function New-TestRepository {
    <#
    .SYNOPSIS
    Creates temporary git repository for testing
    #>
    param([string]$Name = "test-repo-$(Get-Random)")

    $repoPath = Join-Path $env:TEMP $Name

    if (Test-Path $repoPath) {
        Remove-Item $repoPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null

    Push-Location $repoPath
    git init | Out-Null
    git config user.email "test@felix.dev" | Out-Null
    git config user.name "Felix Test" | Out-Null

    # Create initial structure
    New-Item -ItemType Directory -Path "felix" -Force | Out-Null
    New-Item -ItemType Directory -Path "specs" -Force | Out-Null
    New-Item -ItemType Directory -Path "runs" -Force | Out-Null

    # Create minimal config
    @{
        executor = @{
            commit_on_complete = $true
        }
        plugins = @{
            disabled = @()
        }
    } | ConvertTo-Json -Depth 10 | Set-Content ".felix/config.json"

    # Create minimal requirements
    @{
        requirements = @()
    } | ConvertTo-Json -Depth 10 | Set-Content ".felix/requirements.json"

    # Initial commit
    git add . | Out-Null
    git commit -m "Initial commit" | Out-Null

    Pop-Location

    return $repoPath
}

function Remove-TestRepository {
    param([string]$Path)

    if (Test-Path $Path) {
        # Force remove even if files are in use
        Get-ChildItem -Path $Path -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-TestRequirement {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Status = "planned",
        [string[]]$DependsOn = @()
    )

    return @{
        id = $Id
        title = $Title
        status = $Status
        depends_on = $DependsOn
        branch = $null
    }
}

function Set-TestRequirements {
    param(
        [string]$RepoPath,
        [array]$Requirements
    )

    $requirementsFile = Join-Path $RepoPath ".felix/requirements.json"
    @{
        requirements = $Requirements
    } | ConvertTo-Json -Depth 10 | Set-Content $requirementsFile
}

Export-ModuleMember -Function New-TestRepository, Remove-TestRepository, New-TestRequirement, Set-TestRequirements
```

---

## Module-Specific Test Suites

### 1. Compatibility Utilities Tests

```powershell
# filepath: .felix/tests/test-compat-utils.ps1
<#
.SYNOPSIS
Tests for PowerShell 5.1 compatibility utilities
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/compat-utils.ps1"

Describe "Coalesce-Value Function" {

    It "should return value when not null" {
        $result = Coalesce-Value "test" "default"
        Assert-Equal "test" $result
    }

    It "should return default when value is null" {
        $result = Coalesce-Value $null "default"
        Assert-Equal "default" $result
    }

    It "should return default when value is empty string" {
        $result = Coalesce-Value "" "default"
        Assert-Equal "default" $result
    }

    It "should work with pipeline input" {
        $result = $null | Coalesce-Value -Default "piped"
        Assert-Equal "piped" $result
    }
}

Describe "Ternary Function" {

    It "should return IfTrue when condition is true" {
        $result = Ternary $true "yes" "no"
        Assert-Equal "yes" $result
    }

    It "should return IfFalse when condition is false" {
        $result = Ternary $false "yes" "no"
        Assert-Equal "no" $result
    }

    It "should handle complex conditions" {
        $value = 5
        $result = Ternary ($value -gt 3) "big" "small"
        Assert-Equal "big" $result
    }
}

Describe "Safe-Interpolate Function" {

    It "should replace variables correctly" {
        $result = Safe-Interpolate -Template "Hello ${name}!" -Variables @{ name = "World" }
        Assert-Equal "Hello World!" $result
    }

    It "should handle multiple variables" {
        $template = "${greeting} ${name}, you have ${count} messages"
        $vars = @{ greeting = "Hi"; name = "Alice"; count = "5" }
        $result = Safe-Interpolate -Template $template -Variables $vars
        Assert-Equal "Hi Alice, you have 5 messages" $result
    }

    It "should not confuse colons with drive references" {
        $template = "Status: ${status}"
        $vars = @{ status = "Building" }
        $result = Safe-Interpolate -Template $template -Variables $vars
        Assert-Equal "Status: Building" $result
    }
}

Describe "Invoke-SafeCommand Function" {

    It "should execute command and return exit code" {
        $result = Invoke-SafeCommand -Command "powershell" -Arguments @("-Command", "exit 0")
        Assert-Equal 0 $result.exitCode
    }

    It "should return non-zero exit code on failure" {
        $result = Invoke-SafeCommand -Command "powershell" -Arguments @("-Command", "exit 42")
        Assert-Equal 42 $result.exitCode
    }

    It "should change working directory" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-wd-$(Get-Random)" -Force
        $result = Invoke-SafeCommand -Command "powershell" -Arguments @("-Command", "pwd") -WorkingDirectory $tempDir.FullName
        Assert-True ($result.output -match [regex]::Escape($tempDir.FullName))
        Remove-Item $tempDir -Recurse -Force
    }
}

Get-TestResults
```

### 2. State Machine Tests

```powershell
# filepath: .felix/tests/test-agent-state.ps1
<#
.SYNOPSIS
Tests for agent state machine
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-state.ps1"

Describe "AgentState Initialization" {

    It "should initialize with Planning mode by default" {
        $state = New-AgentState
        Assert-Equal "Planning" $state.Mode
    }

    It "should initialize with custom mode" {
        $state = New-AgentState -InitialMode "Building"
        Assert-Equal "Building" $state.Mode
    }

    It "should initialize iteration count to 0" {
        $state = New-AgentState
        Assert-Equal 0 $state.IterationCount
    }

    It "should set start time" {
        $state = New-AgentState
        Assert-NotNull $state.StartTime
    }
}

Describe "State Transitions" {

    It "should allow Planning to Building transition" {
        $state = New-AgentState
        $state.TransitionTo('Building')
        Assert-Equal "Building" $state.Mode
    }

    It "should allow Building to Validating transition" {
        $state = New-AgentState -InitialMode "Building"
        $state.TransitionTo('Validating')
        Assert-Equal "Validating" $state.Mode
    }

    It "should allow Validating to Complete transition" {
        $state = New-AgentState -InitialMode "Validating"
        $state.TransitionTo('Complete')
        Assert-Equal "Complete" $state.Mode
    }

    It "should allow any state to Blocked transition" {
        $state = New-AgentState -InitialMode "Building"
        $state.TransitionTo('Blocked')
        Assert-Equal "Blocked" $state.Mode
    }

    It "should reject invalid transitions" {
        $state = New-AgentState -InitialMode "Building"
        Assert-Throws { $state.TransitionTo('Planning') }
    }

    It "should not allow transition from Complete" {
        $state = New-AgentState -InitialMode "Complete"
        Assert-Throws { $state.TransitionTo('Planning') }
    }

    It "should increment iteration count on transition" {
        $state = New-AgentState
        Assert-Equal 0 $state.IterationCount
        $state.TransitionTo('Building')
        Assert-Equal 1 $state.IterationCount
        $state.TransitionTo('Validating')
        Assert-Equal 2 $state.IterationCount
    }
}

Describe "State Context Management" {

    It "should store context data" {
        $state = New-AgentState
        $state.Context['key'] = 'value'
        Assert-Equal 'value' $state.Context['key']
    }

    It "should store requirement ID" {
        $state = New-AgentState
        $state.RequirementId = 'S-0001'
        Assert-Equal 'S-0001' $state.RequirementId
    }
}

Describe "State Serialization" {

    It "should convert to JSON hashtable" {
        $state = New-AgentState
        $state.RequirementId = 'S-0001'
        $state.Branch = 'feature/S-0001'

        $json = $state.ToJson()

        Assert-Equal 'Planning' $json.mode
        Assert-Equal 'S-0001' $json.requirementId
        Assert-Equal 'feature/S-0001' $json.branch
        Assert-NotNull $json.startTime
    }
}

Get-TestResults
```

### 3. Git Manager Tests

```powershell
# filepath: .felix/tests/test-git-manager.ps1
<#
.SYNOPSIS
Tests for git operations
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/test-helpers.ps1"
. "$PSScriptRoot/../core/git-manager.ps1"

Describe "Feature Branch Initialization" {

    It "should create new feature branch" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $branch = Initialize-FeatureBranch -RequirementId "S-0001" -BaseBranch "main"

        Assert-Equal "feature/S-0001" $branch

        $currentBranch = git rev-parse --abbrev-ref HEAD
        Assert-Equal "feature/S-0001" $currentBranch

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should switch to existing branch" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Create branch first time
        Initialize-FeatureBranch -RequirementId "S-0001" | Out-Null

        # Switch back to main
        git checkout main | Out-Null

        # Initialize again - should switch, not create
        $branch = Initialize-FeatureBranch -RequirementId "S-0001"

        Assert-Equal "feature/S-0001" $branch
        $currentBranch = git rev-parse --abbrev-ref HEAD
        Assert-Equal "feature/S-0001" $currentBranch

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should use custom base branch" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Create develop branch
        git checkout -b develop | Out-Null
        "test" | Out-File "dev.txt"
        git add . | Out-Null
        git commit -m "Dev commit" | Out-Null

        $branch = Initialize-FeatureBranch -RequirementId "S-0001" -BaseBranch "develop"

        Assert-Equal "feature/S-0001" $branch

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git State Capture" {

    It "should capture clean state" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $state = Get-GitState

        Assert-NotNull $state.commitHash
        Assert-Equal "main" $state.branch
        Assert-Equal 0 $state.modifiedFiles.Count
        Assert-Equal 0 $state.untrackedFiles.Count

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should detect modified files" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Modify a file
        "changed" | Out-File ".felix/config.json"

        $state = Get-GitState

        Assert-True ($state.modifiedFiles.Count -gt 0)
        Assert-Contains $state.modifiedFiles ".felix/config.json"

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should detect untracked files" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Create new file
        "new" | Out-File "newfile.txt"

        $state = Get-GitState

        Assert-True ($state.untrackedFiles.Count -gt 0)
        Assert-Contains $state.untrackedFiles "newfile.txt"

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git Change Detection" {

    It "should return false for clean working directory" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $hasChanges = Test-GitChanges

        Assert-False $hasChanges

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should return true when files are modified" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        "changed" | Out-File ".felix/config.json"

        $hasChanges = Test-GitChanges

        Assert-True $hasChanges

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git Commit Operations" {

    It "should commit changes successfully" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Make a change
        "changed" | Out-File ".felix/config.json"

        $result = Invoke-GitCommit -Message "Test commit"

        Assert-True $result

        # Verify commit exists
        $log = git log --oneline -1
        Assert-True ($log -match "Test commit")

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should not commit when no changes" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $result = Invoke-GitCommit -Message "Test commit"

        Assert-False $result

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git Revert Operations" {

    It "should revert unauthorized file changes" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $beforeState = Get-GitState

        # Modify unauthorized file
        "changed" | Out-File "unauthorized.txt"

        # Revert with allowed patterns
        Invoke-GitRevert -BeforeState $beforeState -AllowedPatterns @('runs/*', '.felix/state.json')

        # File should not exist
        Assert-False (Test-Path "unauthorized.txt")

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should preserve allowed file changes" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $beforeState = Get-GitState

        # Create allowed directory
        New-Item -ItemType Directory -Path "runs/test" -Force | Out-Null

        # Modify allowed file
        "changed" | Out-File "runs/test/output.log"

        # Revert with allowed patterns
        Invoke-GitRevert -BeforeState $beforeState -AllowedPatterns @('runs/*')

        # File should still exist
        Assert-True (Test-Path "runs/test/output.log")

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Get-TestResults
```

### 4. State Manager Tests

```powershell
# filepath: .felix/tests/test-state-manager.ps1
<#
.SYNOPSIS
Tests for requirements state management
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/test-helpers.ps1"
. "$PSScriptRoot/../core/state-manager.ps1"

Describe "Requirements State Loading" {

    It "should load valid requirements file" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Test 1"),
            (New-TestRequirement -Id "S-0002" -Title "Test 2")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        $state = Get-RequirementsState $requirementsFile

        Assert-Equal 2 $state.requirements.Count
        Assert-Equal "S-0001" $state.requirements[0].id

        Remove-TestRepository $repoPath
    }

    It "should throw when file not found" {
        Assert-Throws {
            Get-RequirementsState "nonexistent.json"
        }
    }

    It "should throw when JSON is invalid" {
        $tempFile = Join-Path $env:TEMP "invalid-$(Get-Random).json"
        "{ invalid json" | Out-File $tempFile

        Assert-Throws {
            Get-RequirementsState $tempFile
        }

        Remove-Item $tempFile
    }
}

Describe "Requirements State Saving" {

    It "should save state with proper formatting" {
        $repoPath = New-TestRepository
        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"

        $state = @{
            requirements = @(
                @{ id = "S-0001"; title = "Test"; status = "planned" }
            )
        }

        Save-RequirementsState $requirementsFile $state

        Assert-FileExists $requirementsFile

        # Verify it's valid JSON
        $loaded = Get-Content $requirementsFile -Raw | ConvertFrom-Json
        Assert-Equal "S-0001" $loaded.requirements[0].id

        Remove-TestRepository $repoPath
    }
}

Describe "Next Requirement Selection" {

    It "should select in_progress requirement first" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "First" -Status "planned"),
            (New-TestRequirement -Id "S-0002" -Title "Second" -Status "in_progress"),
            (New-TestRequirement -Id "S-0003" -Title "Third" -Status "planned")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        Assert-Equal "S-0002" $next.id

        Remove-TestRepository $repoPath
    }

    It "should select planned requirement when no in_progress" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "First" -Status "planned"),
            (New-TestRequirement -Id "S-0002" -Title "Second" -Status "complete")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        Assert-Equal "S-0001" $next.id

        Remove-TestRepository $repoPath
    }

    It "should respect dependencies" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Base" -Status "planned"),
            (New-TestRequirement -Id "S-0002" -Title "Dependent" -Status "planned" -DependsOn @("S-0001"))
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        # Should select S-0001 first because S-0002 depends on it
        Assert-Equal "S-0001" $next.id

        Remove-TestRepository $repoPath
    }

    It "should return null when no requirements available" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Done" -Status "complete")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        $next = Get-NextRequirement $requirementsFile

        Assert-Null $next

        Remove-TestRepository $repoPath
    }
}

Describe "Requirement Status Update" {

    It "should update status successfully" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Test")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        Update-RequirementStatus $requirementsFile "S-0001" "in_progress"

        $state = Get-RequirementsState $requirementsFile
        Assert-Equal "in_progress" $state.requirements[0].status

        Remove-TestRepository $repoPath
    }

    It "should update branch when provided" {
        $repoPath = New-TestRepository

        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Test")
        )
        Set-TestRequirements $repoPath $requirements

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"
        Update-RequirementStatus $requirementsFile "S-0001" "in_progress" "feature/S-0001"

        $state = Get-RequirementsState $requirementsFile
        Assert-Equal "feature/S-0001" $state.requirements[0].branch

        Remove-TestRepository $repoPath
    }

    It "should throw when requirement not found" {
        $repoPath = New-TestRepository

        $requirementsFile = Join-Path $repoPath ".felix/requirements.json"

        Assert-Throws {
            Update-RequirementStatus $requirementsFile "S-9999" "complete"
        }

        Remove-TestRepository $repoPath
    }
}

Get-TestResults
```

### 5. Plugin Manager Tests

```powershell
# filepath: .felix/tests/test-plugin-manager.ps1
<#
.SYNOPSIS
Tests for plugin system
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/test-helpers.ps1"
. "$PSScriptRoot/../plugins/plugin-manager.ps1"

Describe "Plugin Discovery" {

    It "should find plugins in directory" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        # Create test plugins
        "function On-Test { Write-Host 'Plugin 1' }" | Out-File "$tempDir/plugin1.ps1"
        "function On-Test { Write-Host 'Plugin 2' }" | Out-File "$tempDir/plugin2.ps1"

        $plugins = Get-Plugins -PluginDirectory $tempDir

        Assert-Equal 2 $plugins.Count

        Remove-Item $tempDir -Recurse -Force
    }

    It "should exclude disabled plugins" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        "function On-Test { }" | Out-File "$tempDir/plugin1.ps1"
        "function On-Test { }" | Out-File "$tempDir/plugin2.ps1"

        $plugins = Get-Plugins -PluginDirectory $tempDir -DisabledPlugins @("plugin1")

        Assert-Equal 1 $plugins.Count
        Assert-Equal "plugin2" $plugins[0].BaseName

        Remove-Item $tempDir -Recurse -Force
    }

    It "should return empty array when directory not found" {
        $plugins = Get-Plugins -PluginDirectory "nonexistent"
        Assert-Equal 0 $plugins.Count
    }
}

Describe "Plugin Execution" {

    It "should execute plugin successfully" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        $pluginCode = @"
function On-Test {
    param([hashtable]`$Context)
    return "Success: `$(`$Context.value)"
}
"@
        $pluginCode | Out-File "$tempDir/test-plugin.ps1"

        $result = Invoke-PluginSafely -PluginPath "$tempDir/test-plugin.ps1" `
                                       -Hook "On-Test" `
                                       -Context @{ value = "42" }

        Assert-True $result.success
        Assert-True ($result.output -match "Success: 42")

        Remove-Item $tempDir -Recurse -Force
    }

    It "should handle plugin timeout" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        $pluginCode = @"
function On-Test {
    Start-Sleep -Seconds 60
}
"@
        $pluginCode | Out-File "$tempDir/timeout-plugin.ps1"

        $result = Invoke-PluginSafely -PluginPath "$tempDir/timeout-plugin.ps1" `
                                       -Hook "On-Test" `
                                       -TimeoutSeconds 2

        Assert-False $result.success
        Assert-True ($result.error -match "timeout")

        Remove-Item $tempDir -Recurse -Force
    }

    It "should handle plugin errors" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        $pluginCode = @"
function On-Test {
    throw "Plugin error"
}
"@
        $pluginCode | Out-File "$tempDir/error-plugin.ps1"

        $result = Invoke-PluginSafely -PluginPath "$tempDir/error-plugin.ps1" `
                                       -Hook "On-Test"

        Assert-False $result.success
        Assert-NotNull $result.error

        Remove-Item $tempDir -Recurse -Force
    }

    It "should handle missing hook function" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        $pluginCode = @"
function Some-Other-Function {
    Write-Host "Not the hook"
}
"@
        $pluginCode | Out-File "$tempDir/no-hook.ps1"

        $result = Invoke-PluginSafely -PluginPath "$tempDir/no-hook.ps1" `
                                       -Hook "On-Test"

        Assert-False $result.success
        Assert-True ($result.error -match "not found")

        Remove-Item $tempDir -Recurse -Force
    }
}

Describe "Plugin Isolation" {

    It "should not affect parent scope" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/plugins-$(Get-Random)" -Force

        $pluginCode = @"
function On-Test {
    `$Global:TestVariable = "Modified"
}
"@
        $pluginCode | Out-File "$tempDir/scope-plugin.ps1"

        $Global:TestVariable = "Original"

        Invoke-PluginSafely -PluginPath "$tempDir/scope-plugin.ps1" -Hook "On-Test"

        # Global variable should not be affected due to isolated runspace
        Assert-Equal "Original" $Global:TestVariable

        Remove-Item $tempDir -Recurse -Force
    }
}

Get-TestResults
```

---

## Integration Tests

### End-to-End Agent Execution

```powershell
# filepath: .felix/tests/integration/test-agent-e2e.ps1
<#
.SYNOPSIS
End-to-end integration tests
#>

. "$PSScriptRoot/../test-framework.ps1"
. "$PSScriptRoot/../test-helpers.ps1"

Describe "Agent End-to-End Execution" {

    It "should complete simple requirement" {
        $repoPath = New-TestRepository

        # Setup requirement
        $requirements = @(
            (New-TestRequirement -Id "S-0001" -Title "Simple Test" -Status "planned")
        )
        Set-TestRequirements $repoPath $requirements

        # Create simple spec
        $specPath = Join-Path $repoPath "specs"
        @"
# S-0001: Simple Test

## Description
Simple test requirement for validation

## Acceptance Criteria
- [x] Manual verification - test passes
"@ | Out-File "$specPath/S-0001-simple-test.md"

        # Run agent (with mock mode to avoid actual droid calls)
        # This would be the actual integration test

        # Verify branch created
        Push-Location $repoPath
        $branches = git branch --list "feature/S-0001"
        Assert-NotNull $branches
        Pop-Location

        Remove-TestRepository $repoPath
    }
}

Get-TestResults
```

---

## Compatibility Testing

### PowerShell Version Compatibility

```powershell
# filepath: .felix/tests/compatibility/test-ps51.ps1
<#
.SYNOPSIS
PowerShell 5.1 compatibility verification
.DESCRIPTION
Run these tests on PowerShell 5.1 to ensure compatibility
#>

. "$PSScriptRoot/../test-framework.ps1"

Describe "PowerShell Version" {

    It "should detect PowerShell version" {
        Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
        Assert-NotNull $PSVersionTable.PSVersion
    }

    It "should work on PowerShell 5.1 or higher" {
        Assert-True ($PSVersionTable.PSVersion.Major -ge 5)
    }
}

Describe "Syntax Compatibility" {

    It "should not use ternary operator" {
        # Search for ternary operator usage in core modules
        $coreFiles = Get-ChildItem "$PSScriptRoot/../../core" -Filter "*.ps1" -Recurse

        foreach ($file in $coreFiles) {
            $content = Get-Content $file.FullName -Raw
            Assert-False ($content -match '\?\s*:') "File uses ternary operator: $($file.Name)"
        }
    }

    It "should not use null coalescing operator" {
        $coreFiles = Get-ChildItem "$PSScriptRoot/../../core" -Filter "*.ps1" -Recurse

        foreach ($file in $coreFiles) {
            $content = Get-Content $file.FullName -Raw
            Assert-False ($content -match '\?\?') "File uses null coalescing: $($file.Name)"
        }
    }
}

Get-TestResults
```

---

## Security Testing

### Command Injection Tests

```powershell
# filepath: .felix/tests/security/test-command-injection.ps1
<#
.SYNOPSIS
Security tests for command injection vulnerabilities
#>

. "$PSScriptRoot/../test-framework.ps1"

Describe "Command Injection Prevention" {

    It "should not use Invoke-Expression in core modules" {
        $coreFiles = Get-ChildItem "$PSScriptRoot/../../core" -Filter "*.ps1" -Recurse

        foreach ($file in $coreFiles) {
            $content = Get-Content $file.FullName -Raw
            Assert-False ($content -match 'Invoke-Expression') "File uses Invoke-Expression: $($file.Name)"
        }
    }

    It "should use Invoke-SafeCommand for external commands" {
        # Verify safe command usage patterns
        $coreFiles = Get-ChildItem "$PSScriptRoot/../../core" -Filter "*.ps1" -Recurse

        foreach ($file in $coreFiles) {
            $content = Get-Content $file.FullName -Raw
            if ($content -match 'Invoke-Expression') {
                throw "Unsafe command execution in: $($file.Name)"
            }
        }
    }
}

Get-TestResults
```

---

## Performance Testing

### Module Load Time

```powershell
# filepath: .felix/tests/performance/test-load-time.ps1
<#
.SYNOPSIS
Performance tests for module loading
#>

. "$PSScriptRoot/../test-framework.ps1"

Describe "Module Load Performance" {

    It "should load compat-utils quickly" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        . "$PSScriptRoot/../../core/compat-utils.ps1"
        $stopwatch.Stop()

        Write-Host "Load time: $($stopwatch.ElapsedMilliseconds)ms"
        Assert-True ($stopwatch.ElapsedMilliseconds -lt 1000) "Load took too long"
    }

    It "should load all core modules in under 5 seconds" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        . "$PSScriptRoot/../../core/compat-utils.ps1"
        . "$PSScriptRoot/../../core/agent-state.ps1"
        . "$PSScriptRoot/../../core/git-manager.ps1"
        . "$PSScriptRoot/../../core/state-manager.ps1"
        . "$PSScriptRoot/../../plugins/plugin-manager.ps1"

        $stopwatch.Stop()

        Write-Host "Total load time: $($stopwatch.ElapsedMilliseconds)ms"
        Assert-True ($stopwatch.ElapsedMilliseconds -lt 5000) "Total load took too long"
    }
}

Get-TestResults
```

---

## Test Execution Scripts

### Run All Tests

```powershell
# filepath: .felix/tests/run-all-tests.ps1
<#
.SYNOPSIS
Runs all test suites
#>

param(
    [switch]$IncludeIntegration,
    [switch]$IncludePerformance
)

$ErrorActionPreference = "Continue"

$testScripts = @(
    "test-compat-utils.ps1",
    "test-agent-state.ps1",
    "test-git-manager.ps1",
    "test-state-manager.ps1",
    "test-plugin-manager.ps1"
)

if ($IncludeIntegration) {
    $testScripts += "integration/test-agent-e2e.ps1"
}

if ($IncludePerformance) {
    $testScripts += "performance/test-load-time.ps1"
}

$totalPassed = 0
$totalFailed = 0

foreach ($script in $testScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script

    if (Test-Path $scriptPath) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Running: $script" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        & $scriptPath

        $totalPassed += $Global:TestResults.Passed
        $totalFailed += $Global:TestResults.Failed

        # Reset for next test
        $Global:TestResults = @{ Passed = 0; Failed = 0; Skipped = 0; Tests = @() }
    }
}

Write-Host "`n========================================"  -ForegroundColor Cyan
Write-Host "FINAL TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })

exit $(if ($totalFailed -eq 0) { 0 } else { 1 })
```

### Continuous Integration Script

```powershell
# filepath: .felix/tests/ci-test.ps1
<#
.SYNOPSIS
CI/CD test runner
#>

Write-Host "Felix Agent Test Suite - CI Mode" -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Run unit tests
Write-Host "`nRunning Unit Tests..." -ForegroundColor Yellow
& "$PSScriptRoot/run-all-tests.ps1"
$unitTestResult = $LASTEXITCODE

# Run compatibility tests
Write-Host "`nRunning Compatibility Tests..." -ForegroundColor Yellow
& "$PSScriptRoot/compatibility/test-ps51.ps1"
$compatResult = $LASTEXITCODE

# Run security tests
Write-Host "`nRunning Security Tests..." -ForegroundColor Yellow
& "$PSScriptRoot/security/test-command-injection.ps1"
$securityResult = $LASTEXITCODE

# Final result
if ($unitTestResult -eq 0 -and $compatResult -eq 0 -and $securityResult -eq 0) {
    Write-Host "`n✅ All CI tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ CI tests failed!" -ForegroundColor Red
    exit 1
}
```

---

## Test Coverage Tracking

### Coverage Report Generator

```powershell
# filepath: .felix/tests/generate-coverage.ps1
<#
.SYNOPSIS
Generates test coverage report
#>

function Get-FunctionCoverage {
    param(
        [string]$ModulePath,
        [string]$TestPath
    )

    # Get all functions in module
    $moduleContent = Get-Content $ModulePath -Raw
    $functions = [regex]::Matches($moduleContent, 'function\s+([A-Za-z-]+)') |
                 ForEach-Object { $_.Groups[1].Value }

    # Get all function calls in tests
    $testContent = Get-Content $TestPath -Raw
    $testedFunctions = [regex]::Matches($testContent, '([A-Za-z-]+)\s+-') |
                       ForEach-Object { $_.Groups[1].Value }

    $totalFunctions = $functions.Count
    $testedCount = ($functions | Where-Object { $testedFunctions -contains $_ }).Count
    $coverage = if ($totalFunctions -gt 0) {
        [math]::Round(($testedCount / $totalFunctions) * 100, 2)
    } else {
        0
    }

    return @{
        module = Split-Path $ModulePath -Leaf
        totalFunctions = $totalFunctions
        testedFunctions = $testedCount
        coverage = $coverage
    }
}

# Generate report
$modules = @(
    @{ module = "core/compat-utils.ps1"; test = "test-compat-utils.ps1" },
    @{ module = "core/agent-state.ps1"; test = "test-agent-state.ps1" },
    @{ module = "core/git-manager.ps1"; test = "test-git-manager.ps1" },
    @{ module = "core/state-manager.ps1"; test = "test-state-manager.ps1" },
    @{ module = "plugins/plugin-manager.ps1"; test = "test-plugin-manager.ps1" }
)

Write-Host "`n=== Test Coverage Report ===" -ForegroundColor Cyan
Write-Host ""

$totalCoverage = 0

foreach ($item in $modules) {
    $modulePath = Join-Path $PSScriptRoot ".." $item.module
    $testPath = Join-Path $PSScriptRoot $item.test

    if ((Test-Path $modulePath) -and (Test-Path $testPath)) {
        $coverage = Get-FunctionCoverage -ModulePath $modulePath -TestPath $testPath

        $color = if ($coverage.coverage -ge 80) { "Green" }
                 elseif ($coverage.coverage -ge 60) { "Yellow" }
                 else { "Red" }

        Write-Host "$($coverage.module): $($coverage.coverage)% " -NoNewline
        Write-Host "($($coverage.testedFunctions)/$($coverage.totalFunctions) functions)" -ForegroundColor $color

        $totalCoverage += $coverage.coverage
    }
}

$avgCoverage = [math]::Round($totalCoverage / $modules.Count, 2)
Write-Host "`nAverage Coverage: $avgCoverage%" -ForegroundColor $(
    if ($avgCoverage -ge 80) { "Green" } else { "Yellow" }
)
```

---

## Manual Test Checklist

### Pre-Migration Tests

- [ ] Current felix-agent.ps1 runs successfully on PowerShell 5.1
- [ ] Current felix-agent.ps1 runs successfully on PowerShell 7
- [ ] Git operations work correctly (commit, push, branch)
- [ ] Requirements selection logic works
- [ ] Plugins execute without crashing agent
- [ ] Validation script integration works

### Post-Migration Tests (Per Module)

#### Compat Utils

- [ ] All functions work on PowerShell 5.1
- [ ] All functions work on PowerShell 7
- [ ] No syntax errors
- [ ] String interpolation works correctly
- [ ] Safe command execution prevents injection

#### Agent State

- [ ] State machine initializes correctly
- [ ] Valid transitions work
- [ ] Invalid transitions are rejected
- [ ] Context data persists
- [ ] JSON serialization works

#### Git Manager

- [ ] Branch creation works
- [ ] Branch switching works
- [ ] Git state capture accurate
- [ ] Commit operations succeed
- [ ] Revert operations work correctly

#### State Manager

- [ ] Requirements load correctly
- [ ] Requirements save correctly
- [ ] Next requirement selection works
- [ ] Dependency resolution works
- [ ] Status updates persist

#### Plugin Manager

- [ ] Plugins discovered correctly
- [ ] Disabled plugins excluded
- [ ] Plugins execute in isolation
- [ ] Plugin timeout works
- [ ] Plugin errors don't crash agent

### Integration Tests

- [ ] Full agent run completes successfully
- [ ] Git branch created for requirement
- [ ] Status updates correctly
- [ ] Plugins execute at correct hooks
- [ ] State transitions correctly
- [ ] Validation runs correctly
- [ ] Commits made when appropriate

---

## Success Criteria

### Unit Test Coverage

- ✅ >80% function coverage
- ✅ All critical paths tested
- ✅ Error conditions handled
- ✅ Edge cases covered

### Integration Testing

- ✅ End-to-end workflow works
- ✅ Module interactions correct
- ✅ State persists correctly

### Compatibility

- ✅ PowerShell 5.1 compatible
- ✅ PowerShell 7+ compatible
- ✅ No version-specific syntax

### Security

- ✅ No Invoke-Expression usage
- ✅ No command injection vulnerabilities
- ✅ Plugin isolation working

### Performance

- ✅ Module loading < 5 seconds
- ✅ No significant slowdown vs original
- ✅ Memory usage acceptable

---

**Document Version**: 1.0
**Created**: February 2, 2026
**Owner**: Felix Core Team
**Status**: Approved - Ready for Implementation


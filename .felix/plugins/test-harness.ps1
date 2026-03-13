# 
# Felix Plugin Test Harness
# 
# This harness provides utilities for testing Felix plugins in isolation.

param(
    [Parameter(Mandatory = $false)]
    [string]$PluginPath,
    
    [Parameter(Mandatory = $false)]
    [string]$HookName,
    
    [Parameter(Mandatory = $false)]
    [switch]$RunAll
)

# Import hook contracts
. (Join-Path $PSScriptRoot "hook-contracts.ps1")

function Test-PluginHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginPath,
        
        [Parameter(Mandatory = $true)]
        [string]$HookName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$MockHookData,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ExpectedResult = @{}
    )
    
    Write-Host "Testing plugin hook: $HookName" -ForegroundColor Cyan
    Write-Host "Plugin: $PluginPath"
    Write-Host ""
    
    # Load plugin manifest
    $manifestPath = Join-Path $PluginPath "plugin.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Host " FAILED: Plugin manifest not found" -ForegroundColor Red
        return $false
    }
    
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    
    # Check if plugin implements this hook
    if ($manifest.hooks -notcontains $HookName) {
        Write-Host "  SKIPPED: Plugin does not implement $HookName" -ForegroundColor Yellow
        return $true
    }
    
    # Find hook script
    $apiVersion = if ($manifest.api_version) { $manifest.api_version } else { "v1" }
    $hookScript = if ($apiVersion -eq "v2") {
        Join-Path $PluginPath "hooks/$HookName.ps1"
    }
    else {
        Join-Path $PluginPath "on-$($HookName.ToLower()).ps1"
    }
    
    if (-not (Test-Path $hookScript)) {
        Write-Host " FAILED: Hook script not found: $hookScript" -ForegroundColor Red
        return $false
    }
    
    # Execute hook in isolated environment
    try {
        $mockRunId = "test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        Write-Host "Executing hook with mock data..." -ForegroundColor Gray
        $result = & $hookScript -HookData $MockHookData -RunId $mockRunId -PluginConfig $manifest
        
        # Validate result type
        if (-not (Test-HookContract -HookName $HookName -Result $result)) {
            Write-Host " FAILED: Hook returned invalid result type" -ForegroundColor Red
            return $false
        }
        
        # Check expected results
        $passed = $true
        foreach ($key in $ExpectedResult.Keys) {
            if ($result.$key -ne $ExpectedResult[$key]) {
                Write-Host " FAILED: Expected $key = $($ExpectedResult[$key]), got $($result.$key)" -ForegroundColor Red
                $passed = $false
            }
        }
        
        if ($passed) {
            Write-Host " PASSED" -ForegroundColor Green
        }
        
        Write-Host ""
        return $passed
    }
    catch {
        Write-Host " FAILED: Exception during hook execution" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host ""
        return $false
    }
}

function New-MockHookData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HookName
    )
    
    # Generate realistic mock data for each hook
    switch ($HookName) {
        "OnPreIteration" {
            return @{
                Iteration = 1
                MaxIterations = 10
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                    status = "in_progress"
                }
                State = @{
                    status = "running"
                }
            }
        }
        "OnPostModeSelection" {
            return @{
                Mode = "building"
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                PlanPath = "runs/test-run-001/plan-S-0001.md"
            }
        }
        "OnContextGathering" {
            return @{
                Mode = "building"
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                GitDiff = "diff --git a/test.txt b/test.txt"
                PlanContent = "# Implementation Plan"
                ContextFiles = [System.Collections.ArrayList]@("AGENTS.md", "CONTEXT.md")
            }
        }
        "OnPreLLM" {
            return @{
                Mode = "building"
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                PromptFile = "felix/prompts/building.md"
                FullPrompt = "You are Felix, an AI agent..."
            }
        }
        "OnPostLLM" {
            return @{
                Mode = "building"
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                ExitCode = 0
                OutputPath = "runs/test-run-001/output.log"
            }
        }
        "OnGuardrailCheck" {
            return @{
                Mode = "planning"
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                GuardrailsPassed = $false
                FailedChecks = [System.Collections.ArrayList]@("src/unauthorized.js")
            }
        }
        "OnPreBackpressure" {
            return @{
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                Commands = [System.Collections.ArrayList]@()
            }
        }
        "OnBackpressureFailed" {
            return @{
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                ValidationResult = @{
                    success = $false
                    failed_commands = @(
                        @{ type = "test"; command = "npm test"; exit_code = 1 }
                    )
                }
                RetryCount = 1
            }
        }
        "OnPreCommit" {
            return @{
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                CommitMessage = "Felix (S-0001): Implement feature"
                StagedFiles = [System.Collections.ArrayList]@("src/app.js", "package.json")
            }
        }
        "OnPostValidation" {
            return @{
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                ValidationPassed = $true
                ValidationOutput = "All tests passed"
            }
        }
        "OnPostIteration" {
            return @{
                Iteration = 1
                MaxIterations = 10
                RunId = "test-run-001"
                CurrentRequirement = @{
                    id = "S-0001"
                    title = "Test Requirement"
                }
                Outcome = "success"
                State = @{
                    status = "running"
                }
            }
        }
        default {
            return @{}
        }
    }
}

# Main test execution
if ($PluginPath) {
    if ($HookName) {
        # Test single hook
        $mockData = New-MockHookData -HookName $HookName
        $result = Test-PluginHook -PluginPath $PluginPath -HookName $HookName -MockHookData $mockData
        exit $(if ($result) { 0 } else { 1 })
    }
    elseif ($RunAll) {
        # Test all hooks implemented by plugin
        $manifestPath = Join-Path $PluginPath "plugin.json"
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        
        $allPassed = $true
        foreach ($hook in $manifest.hooks) {
            $mockData = New-MockHookData -HookName $hook
            $result = Test-PluginHook -PluginPath $PluginPath -HookName $hook -MockHookData $mockData
            if (-not $result) {
                $allPassed = $false
            }
        }
        
        Write-Host ""
        if ($allPassed) {
            Write-Host "All tests passed! " -ForegroundColor Green
            exit 0
        }
        else {
            Write-Host "Some tests failed " -ForegroundColor Red
            exit 1
        }
    }
}
else {
    Write-Host "Felix Plugin Test Harness"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\test-harness.ps1 -PluginPath <path> -HookName <hook>  # Test single hook"
    Write-Host "  .\test-harness.ps1 -PluginPath <path> -RunAll           # Test all hooks"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\test-harness.ps1 -PluginPath .\slack-notifier -HookName OnPostLLM"
    Write-Host "  .\test-harness.ps1 -PluginPath .\metrics-collector -RunAll"
}

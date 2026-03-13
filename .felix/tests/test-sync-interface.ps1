#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests for sync-interface.ps1

.DESCRIPTION
Validates the IRunReporter interface, NoOpReporter class, and Get-RunReporter factory function.
#>

$ErrorActionPreference = 'Stop'

# Get the Felix directory (parent of tests folder)
$FelixDir = Split-Path $PSScriptRoot -Parent

# Load the sync interface module
. "$FelixDir\core\sync-interface.ps1"

$testsPassed = 0
$testsFailed = 0

function Test-Assert {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if ($Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host "`n=== Testing sync-interface.ps1 ===" -ForegroundColor Cyan

# Test 1: NoOpReporter can be instantiated
Write-Host "`nTest 1: NoOpReporter instantiation" -ForegroundColor Yellow
try {
    $reporter = [NoOpReporter]::new()
    Test-Assert ($null -ne $reporter) "NoOpReporter created successfully"
    Test-Assert ($reporter.GetType().Name -eq "NoOpReporter") "Type is NoOpReporter"
} catch {
    Write-Host "  FAIL: Exception creating NoOpReporter: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 2: NoOpReporter implements all interface methods without throwing
Write-Host "`nTest 2: NoOpReporter methods work (no-op)" -ForegroundColor Yellow
try {
    $reporter = [NoOpReporter]::new()
    
    # Test RegisterAgent
    $reporter.RegisterAgent(@{ agent_id = 1; hostname = "test" })
    Test-Assert $true "RegisterAgent completes without error"
    
    # Test StartRun
    $runId = $reporter.StartRun(@{ requirement_id = "TEST-001" })
    Test-Assert ($runId -eq "") "StartRun returns empty string"
    
    # Test AppendEvent
    $reporter.AppendEvent(@{ type = "test_event" })
    Test-Assert $true "AppendEvent completes without error"
    
    # Test FinishRun
    $reporter.FinishRun("test-run-id", @{ status = "success" })
    Test-Assert $true "FinishRun completes without error"
    
    # Test UploadArtifact
    $reporter.UploadArtifact("test-run-id", "test.txt", "C:\test.txt")
    Test-Assert $true "UploadArtifact completes without error"
    
    # Test UploadRunFolder
    $reporter.UploadRunFolder("test-run-id", "C:\test-folder")
    Test-Assert $true "UploadRunFolder completes without error"
    
    # Test Flush
    $reporter.Flush()
    Test-Assert $true "Flush completes without error"
} catch {
    Write-Host "  FAIL: Exception testing NoOpReporter methods: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Get-RunReporter returns NoOpReporter when sync is disabled
Write-Host "`nTest 3: Get-RunReporter returns NoOpReporter when sync disabled" -ForegroundColor Yellow
try {
    # Clear any env variables that might enable sync
    $env:FELIX_SYNC_ENABLED = $null
    
    $reporter = Get-RunReporter -FelixDir $FelixDir
    Test-Assert ($null -ne $reporter) "Get-RunReporter returns a reporter"
    Test-Assert ($reporter.GetType().Name -eq "NoOpReporter") "Returns NoOpReporter when sync disabled"
} catch {
    Write-Host "  FAIL: Exception in Get-RunReporter: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 4: Get-RunReporter respects FELIX_SYNC_ENABLED=false
Write-Host "`nTest 4: Get-RunReporter respects FELIX_SYNC_ENABLED=false" -ForegroundColor Yellow
try {
    $env:FELIX_SYNC_ENABLED = "false"
    
    $reporter = Get-RunReporter -FelixDir $FelixDir
    Test-Assert ($reporter.GetType().Name -eq "NoOpReporter") "Returns NoOpReporter when FELIX_SYNC_ENABLED=false"
    
    $env:FELIX_SYNC_ENABLED = $null
} catch {
    Write-Host "  FAIL: Exception testing FELIX_SYNC_ENABLED: $_" -ForegroundColor Red
    $testsFailed++
} finally {
    $env:FELIX_SYNC_ENABLED = $null
}

# Test 5: IRunReporter base class throws NotImplementedException
Write-Host "`nTest 5: IRunReporter base class throws NotImplementedException" -ForegroundColor Yellow
try {
    $baseReporter = [IRunReporter]::new()
    
    try {
        $baseReporter.RegisterAgent(@{})
        Test-Assert $false "Should have thrown NotImplementedException"
    } catch [System.NotImplementedException] {
        Test-Assert $true "RegisterAgent throws NotImplementedException"
    }
    
    try {
        $baseReporter.StartRun(@{})
        Test-Assert $false "Should have thrown NotImplementedException"
    } catch [System.NotImplementedException] {
        Test-Assert $true "StartRun throws NotImplementedException"
    }
    
    try {
        $baseReporter.Flush()
        Test-Assert $false "Should have thrown NotImplementedException"
    } catch [System.NotImplementedException] {
        Test-Assert $true "Flush throws NotImplementedException"
    }
} catch {
    Write-Host "  FAIL: Unexpected exception testing base class: $_" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })

if ($testsFailed -gt 0) {
    exit 1
}
exit 0

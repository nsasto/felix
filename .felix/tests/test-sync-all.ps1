<#
.SYNOPSIS
    Master script to run all run artifact sync end-to-end tests.

.DESCRIPTION
    This script orchestrates all S-0062 sync tests in the proper order:
    1. Runs test-sync-setup.ps1 to initialize the test environment
    2. Executes all individual test scripts
    3. Runs test-sync-cleanup.ps1 to clean up test data
    4. Collects and reports pass/fail status for each test
    5. Returns overall exit code (0 = all passed, 1 = any failed)

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER SkipSetup
    Skip the setup phase (use existing environment)

.PARAMETER SkipCleanup
    Skip the cleanup phase (preserve test data for debugging)

.PARAMETER TestFilter
    Only run tests matching this pattern (e.g., "happy", "network")

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-all.ps1
    # Run all sync tests with defaults

.EXAMPLE
    .\scripts\test-sync-all.ps1 -SkipSetup -SkipCleanup
    # Run tests without setup/cleanup (for debugging)

.EXAMPLE
    .\scripts\test-sync-all.ps1 -TestFilter "happy"
    # Only run tests matching "happy"

.NOTES
    Prerequisites:
    - Backend server running at specified URL
    - PostgreSQL database available
    - All test scripts must exist in the scripts/ directory

    Exit codes:
    - 0: All tests passed
    - 1: One or more tests failed
    - 2: Setup failed or prerequisites not met
#>

param(
    [string]$BackendUrl = "http://localhost:8080",
    [switch]$SkipSetup,
    [switch]$SkipCleanup,
    [string]$TestFilter = "",
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartTime = Get-Date

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Test Suite - All Tests" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Started:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Backend:    $BackendUrl" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# TEST DEFINITIONS
# =============================================================================

# Define all test scripts in execution order
$TestScripts = @(
    @{
        Name        = "Happy Path"
        Script      = "test-sync-happy-path.ps1"
        Description = "Complete sync flow from CLI agent to backend storage"
        Required    = $true
    },
    @{
        Name        = "Idempotency"
        Script      = "test-sync-idempotency.ps1"
        Description = "Verify unchanged files are skipped on re-upload"
        Required    = $true
    },
    @{
        Name        = "Network Failure"
        Script      = "test-sync-network-failure.ps1"
        Description = "Verify outbox queue and retry behavior"
        Required    = $false  # May require stopping backend
    },
    @{
        Name        = "Large File"
        Script      = "test-sync-large-file.ps1"
        Description = "Upload and download 5MB+ files"
        Required    = $true
    },
    @{
        Name        = "Concurrent Upload"
        Script      = "test-sync-concurrent.ps1"
        Description = "Parallel agent uploads without conflicts"
        Required    = $true
    },
    @{
        Name        = "Performance Benchmark"
        Script      = "test-sync-benchmark.ps1"
        Description = "Measure sync overhead across multiple runs"
        Required    = $false  # Can be slow
    },
    @{
        Name        = "Batch Comparison"
        Script      = "test-sync-batch-comparison.ps1"
        Description = "Compare batch vs individual upload performance"
        Required    = $false  # Performance test
    },
    @{
        Name        = "Error Recovery"
        Script      = "test-sync-error-recovery.ps1"
        Description = "Handle corrupt JSON and invalid file paths"
        Required    = $true
    },
    @{
        Name        = "Data Integrity"
        Script      = "test-sync-data-integrity.ps1"
        Description = "Verify SHA256 hashes and database constraints"
        Required    = $true
    }
)

# Filter tests if pattern provided
if ($TestFilter) {
    $TestScripts = $TestScripts | Where-Object { $_.Name -like "*$TestFilter*" -or $_.Script -like "*$TestFilter*" }
    Write-Host "Filtered to $($TestScripts.Count) test(s) matching '$TestFilter'" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# RESULTS TRACKING
# =============================================================================

$Results = @{
    Setup   = $null
    Tests   = @()
    Cleanup = $null
}

$TotalPassed = 0
$TotalFailed = 0
$TotalSkipped = 0

function Write-TestHeader {
    param([string]$Name, [int]$Index, [int]$Total)
    
    Write-Host ""
    Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Test $Index/$Total`: $Name" -ForegroundColor White
    Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
}

function Write-TestFooter {
    param([string]$Name, [string]$Status, [string]$Duration)
    
    $color = switch ($Status) {
        "PASSED" { "Green" }
        "FAILED" { "Red" }
        "SKIPPED" { "Yellow" }
        default { "Gray" }
    }
    
    Write-Host ""
    Write-Host "  Result: $Status ($Duration)" -ForegroundColor $color
}

# =============================================================================
# PHASE 1: SETUP
# =============================================================================

if (-not $SkipSetup) {
    Write-Host "Phase 1: Environment Setup" -ForegroundColor Cyan
    Write-Host "==========================" -ForegroundColor Cyan
    
    $setupScript = Join-Path $ScriptDir "test-sync-setup.ps1"
    
    if (-not (Test-Path $setupScript)) {
        Write-Host "  [ERROR] Setup script not found: $setupScript" -ForegroundColor Red
        exit 2
    }
    
    $setupStart = Get-Date
    try {
        $setupOutput = & $setupScript -BackendUrl $BackendUrl 2>&1
        $setupExitCode = $LASTEXITCODE
        
        if ($VerboseOutput) {
            $setupOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
        
        $setupDuration = ((Get-Date) - $setupStart).ToString("mm\:ss")
        
        if ($setupExitCode -eq 0) {
            Write-Host "  [OK] Setup completed ($setupDuration)" -ForegroundColor Green
            $Results.Setup = @{
                Status   = "PASSED"
                ExitCode = $setupExitCode
                Duration = $setupDuration
            }
        }
        else {
            Write-Host "  [WARN] Setup completed with warnings ($setupDuration)" -ForegroundColor Yellow
            $Results.Setup = @{
                Status   = "WARNING"
                ExitCode = $setupExitCode
                Duration = $setupDuration
            }
        }
    }
    catch {
        Write-Host "  [ERROR] Setup failed: $($_.Exception.Message)" -ForegroundColor Red
        $Results.Setup = @{
            Status   = "FAILED"
            ExitCode = 1
            Error    = $_.Exception.Message
        }
        exit 2
    }
}
else {
    Write-Host "Phase 1: Environment Setup (SKIPPED)" -ForegroundColor Yellow
    $Results.Setup = @{
        Status = "SKIPPED"
    }
}

Write-Host ""

# =============================================================================
# PHASE 2: RUN TESTS
# =============================================================================

Write-Host "Phase 2: Running Tests" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan

$testIndex = 0
$totalTests = $TestScripts.Count

foreach ($test in $TestScripts) {
    $testIndex++
    $testScript = Join-Path $ScriptDir $test.Script
    
    Write-TestHeader -Name $test.Name -Index $testIndex -Total $totalTests
    Write-Host "  $($test.Description)" -ForegroundColor Gray
    
    # Check if script exists
    if (-not (Test-Path $testScript)) {
        Write-Host "  [SKIP] Script not found: $($test.Script)" -ForegroundColor Yellow
        $Results.Tests += @{
            Name     = $test.Name
            Script   = $test.Script
            Status   = "SKIPPED"
            Reason   = "Script not found"
            ExitCode = -1
        }
        $TotalSkipped++
        Write-TestFooter -Name $test.Name -Status "SKIPPED" -Duration "0:00"
        continue
    }
    
    # Run the test
    $testStart = Get-Date
    try {
        Write-Host "  Running..." -ForegroundColor Gray
        
        $testOutput = & $testScript -BackendUrl $BackendUrl 2>&1
        $testExitCode = $LASTEXITCODE
        
        $testDuration = ((Get-Date) - $testStart).ToString("mm\:ss")
        
        if ($VerboseOutput) {
            Write-Host ""
            $testOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
        
        if ($testExitCode -eq 0) {
            $Results.Tests += @{
                Name     = $test.Name
                Script   = $test.Script
                Status   = "PASSED"
                ExitCode = $testExitCode
                Duration = $testDuration
            }
            $TotalPassed++
            Write-TestFooter -Name $test.Name -Status "PASSED" -Duration $testDuration
        }
        elseif ($testExitCode -eq 2) {
            # Prerequisites not met - skip
            $Results.Tests += @{
                Name     = $test.Name
                Script   = $test.Script
                Status   = "SKIPPED"
                Reason   = "Prerequisites not met"
                ExitCode = $testExitCode
                Duration = $testDuration
            }
            $TotalSkipped++
            Write-TestFooter -Name $test.Name -Status "SKIPPED" -Duration $testDuration
        }
        else {
            $Results.Tests += @{
                Name     = $test.Name
                Script   = $test.Script
                Status   = "FAILED"
                ExitCode = $testExitCode
                Duration = $testDuration
            }
            $TotalFailed++
            Write-TestFooter -Name $test.Name -Status "FAILED" -Duration $testDuration
            
            # Show last few lines of output on failure
            if (-not $VerboseOutput) {
                Write-Host ""
                Write-Host "  Last output:" -ForegroundColor Yellow
                $testOutput | Select-Object -Last 5 | ForEach-Object { 
                    Write-Host "    $_" -ForegroundColor Yellow 
                }
            }
        }
    }
    catch {
        $testDuration = ((Get-Date) - $testStart).ToString("mm\:ss")
        $Results.Tests += @{
            Name     = $test.Name
            Script   = $test.Script
            Status   = "FAILED"
            Error    = $_.Exception.Message
            Duration = $testDuration
        }
        $TotalFailed++
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-TestFooter -Name $test.Name -Status "FAILED" -Duration $testDuration
    }
}

Write-Host ""

# =============================================================================
# PHASE 3: CLEANUP
# =============================================================================

if (-not $SkipCleanup) {
    Write-Host "Phase 3: Cleanup" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    
    $cleanupScript = Join-Path $ScriptDir "test-sync-cleanup.ps1"
    
    if (-not (Test-Path $cleanupScript)) {
        Write-Host "  [WARN] Cleanup script not found: $cleanupScript" -ForegroundColor Yellow
        $Results.Cleanup = @{
            Status = "SKIPPED"
            Reason = "Script not found"
        }
    }
    else {
        $cleanupStart = Get-Date
        try {
            $cleanupOutput = & $cleanupScript -Force 2>&1
            $cleanupExitCode = $LASTEXITCODE
            
            if ($VerboseOutput) {
                $cleanupOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            }
            
            $cleanupDuration = ((Get-Date) - $cleanupStart).ToString("mm\:ss")
            
            if ($cleanupExitCode -eq 0) {
                Write-Host "  [OK] Cleanup completed ($cleanupDuration)" -ForegroundColor Green
                $Results.Cleanup = @{
                    Status   = "PASSED"
                    ExitCode = $cleanupExitCode
                    Duration = $cleanupDuration
                }
            }
            else {
                Write-Host "  [WARN] Cleanup completed with warnings ($cleanupDuration)" -ForegroundColor Yellow
                $Results.Cleanup = @{
                    Status   = "WARNING"
                    ExitCode = $cleanupExitCode
                    Duration = $cleanupDuration
                }
            }
        }
        catch {
            Write-Host "  [WARN] Cleanup failed: $($_.Exception.Message)" -ForegroundColor Yellow
            $Results.Cleanup = @{
                Status = "FAILED"
                Error  = $_.Exception.Message
            }
        }
    }
}
else {
    Write-Host "Phase 3: Cleanup (SKIPPED)" -ForegroundColor Yellow
    $Results.Cleanup = @{
        Status = "SKIPPED"
    }
}

Write-Host ""

# =============================================================================
# SUMMARY
# =============================================================================

$TotalDuration = ((Get-Date) - $StartTime).ToString("mm\:ss")

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Test Suite Summary" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Duration:    $TotalDuration" -ForegroundColor White
Write-Host "  Total Tests: $($TotalPassed + $TotalFailed + $TotalSkipped)" -ForegroundColor White
Write-Host "  Passed:      $TotalPassed" -ForegroundColor Green
Write-Host "  Failed:      $TotalFailed" -ForegroundColor $(if ($TotalFailed -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped:     $TotalSkipped" -ForegroundColor $(if ($TotalSkipped -gt 0) { "Yellow" } else { "Gray" })
Write-Host ""

# Show detailed results
Write-Host "Test Results:" -ForegroundColor White
Write-Host "-------------" -ForegroundColor DarkGray

foreach ($result in $Results.Tests) {
    $statusIcon = switch ($result.Status) {
        "PASSED"  { "[PASS]" }
        "FAILED"  { "[FAIL]" }
        "SKIPPED" { "[SKIP]" }
        default   { "[????]" }
    }
    $statusColor = switch ($result.Status) {
        "PASSED"  { "Green" }
        "FAILED"  { "Red" }
        "SKIPPED" { "Yellow" }
        default   { "Gray" }
    }
    
    $duration = if ($result.Duration) { " ($($result.Duration))" } else { "" }
    Write-Host "  $statusIcon $($result.Name)$duration" -ForegroundColor $statusColor
    
    if ($result.Error) {
        Write-Host "         Error: $($result.Error)" -ForegroundColor DarkYellow
    }
    if ($result.Reason) {
        Write-Host "         Reason: $($result.Reason)" -ForegroundColor DarkYellow
    }
}

Write-Host ""

# Show failed tests summary if any
if ($TotalFailed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    foreach ($result in $Results.Tests | Where-Object { $_.Status -eq "FAILED" }) {
        Write-Host "  - $($result.Name): Exit code $($result.ExitCode)" -ForegroundColor Red
    }
    Write-Host ""
}

# Final status
if ($TotalFailed -eq 0) {
    Write-Host "All tests PASSED!" -ForegroundColor Green
    Write-Host ""
    exit 0
}
else {
    Write-Host "$TotalFailed test(s) FAILED." -ForegroundColor Red
    Write-Host ""
    exit 1
}

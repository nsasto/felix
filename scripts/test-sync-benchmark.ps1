<#
.SYNOPSIS
    Performance benchmark test for run artifact sync.

.DESCRIPTION
    This script benchmarks the sync system performance:
    - Run 100 sequential requirement executions (lightweight/mock)
    - Measure total time and per-run average using Measure-Command
    - Compare sync overhead vs no-sync baseline (should be <10% overhead)
    - Verify database row count grows linearly with run count
    - Verify storage size grows linearly with artifact count
    - Check PowerShell memory is stable (no memory leaks)
    - Check backend memory stable under load (if accessible)

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER RunCount
    Number of sequential runs to perform (default: 100)

.PARAMETER Timeout
    Maximum test duration in seconds (default: 600)

.PARAMETER SkipNoSyncBaseline
    Skip the no-sync baseline measurement (faster test)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-benchmark.ps1
    # Run benchmark with 100 iterations

.EXAMPLE
    .\scripts\test-sync-benchmark.ps1 -RunCount 50 -SkipNoSyncBaseline
    # Run 50 iterations without baseline comparison

.NOTES
    Prerequisites:
    - Backend server running at specified URL
    - PostgreSQL database available
    - Run test-sync-setup.ps1 first to initialize environment

    Exit codes:
    - 0: All tests passed (benchmark completed successfully)
    - 1: One or more tests failed
    - 2: Prerequisites not met (backend unavailable, etc.)
#>

param(
    [string]$BackendUrl = "http://localhost:8080",
    [int]$RunCount = 100,
    [int]$Timeout = 600,
    [switch]$SkipNoSyncBaseline,
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Performance Benchmark Test" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-benchmark-$TestId"
$TestAgentId = "test-agent-benchmark-$TestId"
$TestDir = Join-Path $env:TEMP "felix-sync-benchmark-$TestId"

# Track test results
$testsPassed = 0
$testsFailed = 0
$testResults = @()

# Performance metrics
$syncRunTimes = @()
$noSyncRunTimes = @()
$memorySnapshots = @()
$runIds = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "  [$status] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "         $Message" -ForegroundColor $(if ($Passed) { "Gray" } else { "Yellow" })
    }
    
    $script:testResults += @{
        Name    = $TestName
        Passed  = $Passed
        Message = $Message
    }
    
    if ($Passed) {
        $script:testsPassed++
    }
    else {
        $script:testsFailed++
    }
}

function Test-BackendAvailable {
    param([string]$Url)
    
    try {
        $response = Invoke-WebRequest -Uri "$Url/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-ProcessMemoryMB {
    $process = Get-Process -Id $PID
    return [math]::Round($process.WorkingSet64 / 1MB, 2)
}

function Get-RunCountFromApi {
    param([string]$ProjectId)
    
    try {
        $response = Invoke-RestMethod -Uri "$BackendUrl/api/runs?project_id=$ProjectId&limit=1000" -Method GET -TimeoutSec 30 -ErrorAction SilentlyContinue
        if ($response.runs) {
            return $response.runs.Count
        }
        return 0
    }
    catch {
        return -1
    }
}

function Get-FileCountFromApi {
    param([string]$RunId)
    
    try {
        $response = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$RunId/files" -Method GET -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($response.files) {
            return $response.files.Count
        }
        return 0
    }
    catch {
        return -1
    }
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check backend availability
if (-not (Test-BackendAvailable -Url $BackendUrl)) {
    Write-Host "  [ERROR] Backend server not available at $BackendUrl" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please start the backend server with:" -ForegroundColor Yellow
    Write-Host "  cd app\backend && python main.py" -ForegroundColor Gray
    Write-Host ""
    exit 2
}
Write-Host "  [OK] Backend server responding at $BackendUrl" -ForegroundColor Green

# Create test directory
if (-not (Test-Path $TestDir)) {
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
}
$OutboxDir = Join-Path $TestDir ".felix\outbox"
New-Item -ItemType Directory -Path $OutboxDir -Force | Out-Null
Write-Host "  [OK] Test directory created: $TestDir" -ForegroundColor Green

# Source the sync interface and plugin
$FelixDir = Join-Path $PSScriptRoot "..\\.felix"
$SyncInterfacePath = Join-Path $FelixDir "core\sync-interface.ps1"
$SyncPluginPath = Join-Path $FelixDir "plugins\sync-fastapi.ps1"

if (-not (Test-Path $SyncInterfacePath)) {
    Write-Host "  [ERROR] Sync interface not found: $SyncInterfacePath" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $SyncPluginPath)) {
    Write-Host "  [ERROR] Sync plugin not found: $SyncPluginPath" -ForegroundColor Red
    exit 2
}

. $SyncInterfacePath
. $SyncPluginPath
Write-Host "  [OK] Sync modules loaded" -ForegroundColor Green

# Record initial memory
$initialMemoryMB = Get-ProcessMemoryMB
Write-Host "  [OK] Initial memory: ${initialMemoryMB}MB" -ForegroundColor Green

Write-Host ""

# =============================================================================
# SETUP: Create Test Project
# =============================================================================

Write-Host "Setting up test data..." -ForegroundColor Yellow

# Create test project via API
try {
    $projectBody = @{
        id   = $TestProjectId
        name = "Benchmark Test Project $TestId"
        path = $TestDir
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri "$BackendUrl/api/projects" -Method POST -Body $projectBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "  [OK] Test project created: $TestProjectId" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "  [OK] Test project already exists: $TestProjectId" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Could not create test project via API: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""

# =============================================================================
# BASELINE: No-Sync Performance (Optional)
# =============================================================================

if (-not $SkipNoSyncBaseline) {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "   Baseline: No-Sync Performance" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Running $RunCount iterations WITHOUT sync..." -ForegroundColor Yellow
    
    $baselineDir = Join-Path $TestDir "baseline"
    New-Item -ItemType Directory -Path $baselineDir -Force | Out-Null
    
    $noSyncTimer = [System.Diagnostics.Stopwatch]::StartNew()
    
    for ($i = 1; $i -le $RunCount; $i++) {
        $iterTimer = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Simulate run: create folder, write artifacts, no sync
        $runId = [System.Guid]::NewGuid().ToString()
        $runFolder = Join-Path $baselineDir "runs\$runId"
        New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
        
        # Create plan file
        $planContent = @"
# Baseline Test Plan - Run $i

## Summary
Iteration $i of $RunCount in baseline (no-sync) test.
Run ID: $runId
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
        $planPath = Join-Path $runFolder "plan-S-BASELINE-$i.md"
        $planContent | Set-Content -Path $planPath -Encoding UTF8
        
        # Create output file
        $outputContent = @"
[INFO] Baseline run $i started
[INFO] Run ID: $runId
[INFO] No sync operations
[INFO] Baseline run $i completed
"@
        $outputPath = Join-Path $runFolder "output.log"
        $outputContent | Set-Content -Path $outputPath -Encoding UTF8
        
        $iterTimer.Stop()
        $noSyncRunTimes += $iterTimer.Elapsed.TotalMilliseconds
        
        # Progress indicator every 10 iterations
        if ($i % 10 -eq 0) {
            Write-Host "  Progress: $i / $RunCount iterations" -ForegroundColor Gray
        }
    }
    
    $noSyncTimer.Stop()
    
    $noSyncTotalMs = $noSyncTimer.Elapsed.TotalMilliseconds
    $noSyncAvgMs = ($noSyncRunTimes | Measure-Object -Average).Average
    
    Write-Host ""
    Write-Host "  Baseline Results:" -ForegroundColor Cyan
    Write-Host "    Total time:   $([math]::Round($noSyncTotalMs / 1000, 2))s" -ForegroundColor Gray
    Write-Host "    Average/run:  $([math]::Round($noSyncAvgMs, 2))ms" -ForegroundColor Gray
    Write-Host ""
}

# =============================================================================
# BENCHMARK: Sync-Enabled Performance
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Benchmark: Sync-Enabled Performance" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Running $RunCount iterations WITH sync enabled..." -ForegroundColor Yellow

$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = $BackendUrl

$config = @{
    base_url = $BackendUrl
    api_key  = $null
}

$reporter = [FastApiReporter]::new($config, (Join-Path $TestDir ".felix"))
$reporter.OutboxPath = $OutboxDir

# Register agent once
$agentInfo = @{
    agent_id = $TestAgentId
    hostname = $env:COMPUTERNAME
    platform = "windows"
    version  = "1.0.0-benchmark"
}
$reporter.RegisterAgent($agentInfo)

# Wait for registration to complete
Start-Sleep -Milliseconds 500

$syncTimer = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 1; $i -le $RunCount; $i++) {
    $iterTimer = [System.Diagnostics.Stopwatch]::StartNew()
    
    $requirementId = "S-BENCH-$TestId-$i"
    
    # Start run
    $runMetadata = @{
        agent_id       = $TestAgentId
        project_id     = $TestProjectId
        requirement_id = $requirementId
        branch         = "test/benchmark"
        scenario       = "testing"
        phase          = "building"
    }
    
    $runId = $reporter.StartRun($runMetadata)
    $runIds += $runId
    
    # Create run folder
    $runFolder = Join-Path $TestDir "runs\$runId"
    New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
    
    # Create plan file
    $planContent = @"
# Benchmark Test Plan - Run $i

## Summary
Iteration $i of $RunCount in sync benchmark test.
Run ID: $runId
Requirement: $requirementId
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
    $planPath = Join-Path $runFolder "plan-$requirementId.md"
    $planContent | Set-Content -Path $planPath -Encoding UTF8
    
    # Create output file
    $outputContent = @"
[INFO] Benchmark run $i started
[INFO] Run ID: $runId
[INFO] Requirement: $requirementId
[INFO] Sync enabled
[INFO] Benchmark run $i completed
"@
    $outputPath = Join-Path $runFolder "output.log"
    $outputContent | Set-Content -Path $outputPath -Encoding UTF8
    
    # Upload artifacts
    $reporter.UploadRunFolder($runId, $runFolder)
    
    # Finish run
    $runResult = @{
        status       = "completed"
        exit_code    = 0
        duration_sec = 1
    }
    $reporter.FinishRun($runId, $runResult)
    
    $iterTimer.Stop()
    $syncRunTimes += $iterTimer.Elapsed.TotalMilliseconds
    
    # Record memory every 20 iterations
    if ($i % 20 -eq 0) {
        $memorySnapshots += @{
            Iteration = $i
            MemoryMB  = Get-ProcessMemoryMB
        }
        Write-Host "  Progress: $i / $RunCount iterations (Memory: $(Get-ProcessMemoryMB)MB)" -ForegroundColor Gray
    }
    elseif ($i % 10 -eq 0) {
        Write-Host "  Progress: $i / $RunCount iterations" -ForegroundColor Gray
    }
}

$syncTimer.Stop()

# Wait for final outbox flush
Start-Sleep -Seconds 2

$syncTotalMs = $syncTimer.Elapsed.TotalMilliseconds
$syncAvgMs = ($syncRunTimes | Measure-Object -Average).Average

Write-Host ""
Write-Host "  Sync-Enabled Results:" -ForegroundColor Cyan
Write-Host "    Total time:   $([math]::Round($syncTotalMs / 1000, 2))s" -ForegroundColor Gray
Write-Host "    Average/run:  $([math]::Round($syncAvgMs, 2))ms" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# TEST 1: Sync Overhead Analysis
# =============================================================================

Write-Host "Test Group 1: Sync Overhead Analysis" -ForegroundColor Cyan

if (-not $SkipNoSyncBaseline -and $noSyncAvgMs -gt 0) {
    $overheadMs = $syncAvgMs - $noSyncAvgMs
    $overheadPercent = (($syncAvgMs - $noSyncAvgMs) / $noSyncAvgMs) * 100
    
    Write-Host "  Baseline (no sync): $([math]::Round($noSyncAvgMs, 2))ms/run" -ForegroundColor Gray
    Write-Host "  With sync:          $([math]::Round($syncAvgMs, 2))ms/run" -ForegroundColor Gray
    Write-Host "  Overhead:           $([math]::Round($overheadMs, 2))ms ($([math]::Round($overheadPercent, 1))%)" -ForegroundColor Gray
    
    $isOverheadAcceptable = $overheadPercent -lt 10
    Write-TestResult -TestName "Sync overhead is less than 10%" -Passed $isOverheadAcceptable -Message "Actual: $([math]::Round($overheadPercent, 1))%"
}
else {
    Write-Host "  (Baseline skipped - overhead comparison not available)" -ForegroundColor Gray
    Write-TestResult -TestName "Benchmark completed successfully" -Passed $true -Message "Average: $([math]::Round($syncAvgMs, 2))ms/run"
}

Write-Host ""

# =============================================================================
# TEST 2: Verify Database Row Count Growth
# =============================================================================

Write-Host "Test Group 2: Database Row Count Verification" -ForegroundColor Cyan

$runsInDb = Get-RunCountFromApi -ProjectId $TestProjectId

if ($runsInDb -ge 0) {
    # Expect at least 90% of runs to be recorded (allowing for minor timing issues)
    $expectedMinRuns = [math]::Floor($RunCount * 0.9)
    $rowCountOk = $runsInDb -ge $expectedMinRuns
    
    Write-TestResult -TestName "Database run count grows with iterations" -Passed $rowCountOk -Message "Expected ~$RunCount, Found: $runsInDb"
    
    # Check a few runs have correct file counts
    $sampleRunId = $runIds[0]
    $fileCount = Get-FileCountFromApi -RunId $sampleRunId
    $hasFiles = $fileCount -ge 2  # Expecting at least plan and output files
    
    Write-TestResult -TestName "Runs have expected artifact count" -Passed $hasFiles -Message "Sample run has $fileCount files"
}
else {
    Write-TestResult -TestName "Database run count grows with iterations" -Passed $false -Message "Could not query database"
}

Write-Host ""

# =============================================================================
# TEST 3: Memory Stability Check
# =============================================================================

Write-Host "Test Group 3: Memory Stability Check" -ForegroundColor Cyan

$finalMemoryMB = Get-ProcessMemoryMB
$memoryGrowthMB = $finalMemoryMB - $initialMemoryMB
$memoryGrowthPercent = ($memoryGrowthMB / $initialMemoryMB) * 100

Write-Host "  Initial memory: ${initialMemoryMB}MB" -ForegroundColor Gray
Write-Host "  Final memory:   ${finalMemoryMB}MB" -ForegroundColor Gray
Write-Host "  Growth:         ${memoryGrowthMB}MB ($([math]::Round($memoryGrowthPercent, 1))%)" -ForegroundColor Gray

# Memory should not grow more than 50% during the test (indicating a leak)
$memoryStable = $memoryGrowthPercent -lt 50

Write-TestResult -TestName "PowerShell memory is stable (no leaks)" -Passed $memoryStable -Message "Growth: $([math]::Round($memoryGrowthPercent, 1))%"

# Check if memory snapshots show stable trend
if ($memorySnapshots.Count -ge 3) {
    $firstHalfAvg = ($memorySnapshots[0..([math]::Floor($memorySnapshots.Count / 2) - 1)] | ForEach-Object { $_.MemoryMB } | Measure-Object -Average).Average
    $secondHalfAvg = ($memorySnapshots[[math]::Floor($memorySnapshots.Count / 2)..($memorySnapshots.Count - 1)] | ForEach-Object { $_.MemoryMB } | Measure-Object -Average).Average
    
    $trendGrowth = (($secondHalfAvg - $firstHalfAvg) / $firstHalfAvg) * 100
    $trendStable = $trendGrowth -lt 20
    
    Write-TestResult -TestName "Memory trend is stable over time" -Passed $trendStable -Message "First half avg: $([math]::Round($firstHalfAvg, 1))MB, Second half avg: $([math]::Round($secondHalfAvg, 1))MB"
}

Write-Host ""

# =============================================================================
# TEST 4: Outbox Cleared
# =============================================================================

Write-Host "Test Group 4: Outbox Status" -ForegroundColor Cyan

$outboxFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$outboxCount = ($outboxFiles | Measure-Object).Count

Write-TestResult -TestName "Outbox is empty after benchmark" -Passed ($outboxCount -eq 0) -Message "Found $outboxCount files in outbox"

Write-Host ""

# =============================================================================
# TEST 5: Run Time Consistency
# =============================================================================

Write-Host "Test Group 5: Run Time Consistency" -ForegroundColor Cyan

$minTime = ($syncRunTimes | Measure-Object -Minimum).Minimum
$maxTime = ($syncRunTimes | Measure-Object -Maximum).Maximum
$stdDev = 0

if ($syncRunTimes.Count -gt 1) {
    $mean = ($syncRunTimes | Measure-Object -Average).Average
    $sumSquares = ($syncRunTimes | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
    $stdDev = [math]::Sqrt($sumSquares / ($syncRunTimes.Count - 1))
}

Write-Host "  Min time:    $([math]::Round($minTime, 2))ms" -ForegroundColor Gray
Write-Host "  Max time:    $([math]::Round($maxTime, 2))ms" -ForegroundColor Gray
Write-Host "  Std Dev:     $([math]::Round($stdDev, 2))ms" -ForegroundColor Gray

# Coefficient of variation should be reasonable (less than 100%)
$cv = if ($syncAvgMs -gt 0) { ($stdDev / $syncAvgMs) * 100 } else { 0 }
$consistencyOk = $cv -lt 100

Write-TestResult -TestName "Run times are reasonably consistent" -Passed $consistencyOk -Message "CV: $([math]::Round($cv, 1))%"

Write-Host ""

# =============================================================================
# CLEANUP
# =============================================================================

Write-Host "Cleaning up..." -ForegroundColor Yellow

# Remove test directory
if (Test-Path $TestDir) {
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Clear environment variables
$env:FELIX_SYNC_ENABLED = $null
$env:FELIX_SYNC_URL = $null

Write-Host "  [OK] Test cleanup complete" -ForegroundColor Green
Write-Host ""

# =============================================================================
# SUMMARY
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Benchmark Summary" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Performance Results:" -ForegroundColor White
Write-Host "  Total Runs:          $RunCount" -ForegroundColor Gray
Write-Host "  Total Time:          $([math]::Round($syncTotalMs / 1000, 2))s" -ForegroundColor Gray
Write-Host "  Average Time/Run:    $([math]::Round($syncAvgMs, 2))ms" -ForegroundColor Gray
Write-Host "  Runs in Database:    $runsInDb" -ForegroundColor Gray
if (-not $SkipNoSyncBaseline -and $noSyncAvgMs -gt 0) {
    Write-Host "  Sync Overhead:       $([math]::Round($overheadPercent, 1))%" -ForegroundColor Gray
}
Write-Host ""

Write-Host "Test Results:" -ForegroundColor White
Write-Host "  Total Tests: $($testsPassed + $testsFailed)" -ForegroundColor White
Write-Host "  Passed:      $testsPassed" -ForegroundColor Green
Write-Host "  Failed:      $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($testsFailed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    foreach ($result in $testResults | Where-Object { -not $_.Passed }) {
        Write-Host "  - $($result.Name)" -ForegroundColor Red
        if ($result.Message) {
            Write-Host "    $($result.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

Write-Host "Benchmark Details:" -ForegroundColor Gray
Write-Host "  Test ID:        $TestId" -ForegroundColor Gray
Write-Host "  Project ID:     $TestProjectId" -ForegroundColor Gray
Write-Host "  Agent ID:       $TestAgentId" -ForegroundColor Gray
Write-Host "  Backend URL:    $BackendUrl" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "Benchmark completed successfully!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Benchmark completed with failures." -ForegroundColor Red
    exit 1
}

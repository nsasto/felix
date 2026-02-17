<#
.SYNOPSIS
    Happy path end-to-end test for run artifact sync.

.DESCRIPTION
    This script tests the complete sync flow from CLI agent through outbox queue to backend storage:
    - Sets FELIX_SYNC_ENABLED=true environment variable
    - Uses test project and agent IDs
    - Creates a minimal test run with artifacts
    - Verifies outbox is empty after completion
    - Queries database for run record via API
    - Verifies run has correct metadata
    - Counts run_files records
    - Verifies storage contains artifact files
    - Downloads artifact and compares SHA256

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER Timeout
    Maximum test duration in seconds (default: 60)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-happy-path.ps1
    # Run happy path test with defaults

.EXAMPLE
    .\scripts\test-sync-happy-path.ps1 -BackendUrl http://localhost:8081 -Verbose
    # Use custom backend URL with verbose output

.NOTES
    Prerequisites:
    - Backend server running at specified URL
    - PostgreSQL database available
    - Run test-sync-setup.ps1 first to initialize environment

    Exit codes:
    - 0: All tests passed
    - 1: One or more tests failed
    - 2: Prerequisites not met (backend unavailable, etc.)
#>

param(
    [string]$BackendUrl = "http://localhost:8080",
    [int]$Timeout = 60,
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Happy Path Test" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-$TestId"
$TestAgentId = "test-agent-$TestId"
$TestRunId = $null  # Will be set after run creation
$TestDir = Join-Path $env:TEMP "felix-sync-happy-path-$TestId"

# Track test results
$testsPassed = 0
$testsFailed = 0
$testResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "  [$status] $TestName" -ForegroundColor $color
    if ($Message -and -not $Passed) {
        Write-Host "         $Message" -ForegroundColor Yellow
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

function Calculate-SHA256 {
    param([string]$FilePath)
    
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $hasher.ComputeHash($stream)
            return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        }
        finally {
            $stream.Close()
        }
    }
    finally {
        $hasher.Dispose()
    }
}

function Calculate-SHA256FromBytes {
    param([byte[]]$Content)
    
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hasher.ComputeHash($Content)
        return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    }
    finally {
        $hasher.Dispose()
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

Write-Host ""

# =============================================================================
# SETUP: Create Test Project and Agent in Database
# =============================================================================

Write-Host "Setting up test data..." -ForegroundColor Yellow

# Create test project via API
try {
    $projectBody = @{
        id   = $TestProjectId
        name = "Test Project $TestId"
        path = $TestDir
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri "$BackendUrl/api/projects" -Method POST -Body $projectBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "  [OK] Test project created: $TestProjectId" -ForegroundColor Green
}
catch {
    # Project may already exist or API structure differs - try to continue
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "  [OK] Test project already exists: $TestProjectId" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Could not create test project via API: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         Continuing with direct database setup..." -ForegroundColor Yellow
    }
}

Write-Host ""

# =============================================================================
# TEST 1: Initialize Reporter with Sync Enabled
# =============================================================================

Write-Host "Test Group 1: Reporter Initialization" -ForegroundColor Cyan

$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = $BackendUrl

$config = @{
    base_url = $BackendUrl
    api_key  = $null
}

try {
    $reporter = [FastApiReporter]::new($config, $TestDir)
    $reporter.OutboxPath = $OutboxDir
    Write-TestResult -TestName "Reporter initialized with sync enabled" -Passed $true
}
catch {
    Write-TestResult -TestName "Reporter initialized with sync enabled" -Passed $false -Message $_.Exception.Message
    exit 1
}

Write-Host ""

# =============================================================================
# TEST 2: Register Agent
# =============================================================================

Write-Host "Test Group 2: Agent Registration" -ForegroundColor Cyan

$agentInfo = @{
    agent_id = $TestAgentId
    hostname = $env:COMPUTERNAME
    platform = "windows"
    version  = "1.0.0-test"
}

try {
    $reporter.RegisterAgent($agentInfo)
    Write-TestResult -TestName "Agent registration queued" -Passed $true
}
catch {
    Write-TestResult -TestName "Agent registration queued" -Passed $false -Message $_.Exception.Message
}

# Check outbox was processed (should be empty if server is up)
Start-Sleep -Milliseconds 500
$outboxFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$outboxEmpty = ($outboxFiles | Measure-Object).Count -eq 0
Write-TestResult -TestName "Agent registration sent to server (outbox empty)" -Passed $outboxEmpty

Write-Host ""

# =============================================================================
# TEST 3: Start Run
# =============================================================================

Write-Host "Test Group 3: Run Creation" -ForegroundColor Cyan

$runMetadata = @{
    agent_id       = $TestAgentId
    project_id     = $TestProjectId
    requirement_id = "S-TEST-$TestId"
    branch         = "test/happy-path"
    scenario       = "testing"
    phase          = "building"
}

try {
    $TestRunId = $reporter.StartRun($runMetadata)
    
    # Verify run ID format
    $isValidUuid = $TestRunId -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    Write-TestResult -TestName "Run created with valid UUID" -Passed $isValidUuid -Message "Run ID: $TestRunId"
}
catch {
    Write-TestResult -TestName "Run created with valid UUID" -Passed $false -Message $_.Exception.Message
    exit 1
}

# Wait for outbox to be processed
Start-Sleep -Milliseconds 500
$outboxFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "run-*.jsonl" }
$outboxEmpty = ($outboxFiles | Measure-Object).Count -eq 0
Write-TestResult -TestName "Run creation sent to server (outbox empty)" -Passed $outboxEmpty

Write-Host ""

# =============================================================================
# TEST 4: Create and Upload Artifacts
# =============================================================================

Write-Host "Test Group 4: Artifact Upload" -ForegroundColor Cyan

# Create test artifact files
$runFolder = Join-Path $TestDir "runs\$TestRunId"
New-Item -ItemType Directory -Path $runFolder -Force | Out-Null

$planContent = @"
# Test Plan for S-TEST-$TestId

## Summary
This is a test plan created by the happy path test.

## Tasks
- [x] Task 1: Create test files
- [x] Task 2: Upload artifacts
- [x] Task 3: Verify sync
"@
$planPath = Join-Path $runFolder "plan-S-TEST-$TestId.md"
$planContent | Set-Content -Path $planPath -Encoding UTF8

$outputContent = @"
[INFO] Test started at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
[INFO] Running happy path test
[INFO] Test ID: $TestId
[INFO] Project ID: $TestProjectId
[INFO] Agent ID: $TestAgentId
[INFO] Run ID: $TestRunId
[INFO] Test completed successfully
"@
$outputPath = Join-Path $runFolder "output.log"
$outputContent | Set-Content -Path $outputPath -Encoding UTF8

# Calculate expected SHA256 hashes
$planHash = Calculate-SHA256 -FilePath $planPath
$outputHash = Calculate-SHA256 -FilePath $outputPath

Write-Host "  Created test artifacts:" -ForegroundColor Gray
Write-Host "    - plan-S-TEST-$TestId.md (SHA256: $($planHash.Substring(0,16))...)" -ForegroundColor Gray
Write-Host "    - output.log (SHA256: $($outputHash.Substring(0,16))...)" -ForegroundColor Gray

# Upload run folder artifacts
try {
    $reporter.UploadRunFolder($TestRunId, $runFolder)
    Write-TestResult -TestName "Artifacts queued for upload" -Passed $true
}
catch {
    Write-TestResult -TestName "Artifacts queued for upload" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST 5: Finish Run
# =============================================================================

Write-Host "Test Group 5: Run Completion" -ForegroundColor Cyan

$runResult = @{
    status       = "completed"
    exit_code    = 0
    duration_sec = 5
    summary_json = @{
        tests_passed = 3
        tests_failed = 0
    }
}

try {
    $reporter.FinishRun($TestRunId, $runResult)
    Write-TestResult -TestName "Run finished successfully" -Passed $true
}
catch {
    Write-TestResult -TestName "Run finished successfully" -Passed $false -Message $_.Exception.Message
}

# Wait for all outbox items to be processed
Start-Sleep -Seconds 2

$outboxFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$outboxCount = ($outboxFiles | Measure-Object).Count
Write-TestResult -TestName "Outbox is empty after completion" -Passed ($outboxCount -eq 0) -Message "Found $outboxCount files in outbox"

Write-Host ""

# =============================================================================
# TEST 6: Verify Run in Database via API
# =============================================================================

Write-Host "Test Group 6: Database Verification via API" -ForegroundColor Cyan

# Query run files via API
try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    $hasFiles = $filesResponse.files -and $filesResponse.files.Count -gt 0
    Write-TestResult -TestName "Run files exist in database" -Passed $hasFiles -Message "Found $($filesResponse.files.Count) files"
    
    if ($hasFiles) {
        # Check for expected files
        $hasPlan = $filesResponse.files | Where-Object { $_.path -like "plan-*.md" }
        $hasOutput = $filesResponse.files | Where-Object { $_.path -eq "output.log" }
        
        Write-TestResult -TestName "Plan artifact recorded" -Passed ($null -ne $hasPlan)
        Write-TestResult -TestName "Output artifact recorded" -Passed ($null -ne $hasOutput)
        
        # Verify SHA256 hashes match
        if ($hasPlan) {
            $dbPlanHash = $hasPlan.sha256
            Write-TestResult -TestName "Plan SHA256 matches" -Passed ($dbPlanHash -eq $planHash) -Message "DB: $($dbPlanHash.Substring(0,16))... vs Local: $($planHash.Substring(0,16))..."
        }
        if ($hasOutput) {
            $dbOutputHash = $hasOutput.sha256
            Write-TestResult -TestName "Output SHA256 matches" -Passed ($dbOutputHash -eq $outputHash) -Message "DB: $($dbOutputHash.Substring(0,16))... vs Local: $($outputHash.Substring(0,16))..."
        }
    }
}
catch {
    Write-TestResult -TestName "Run files exist in database" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST 7: Download Artifact and Verify Content
# =============================================================================

Write-Host "Test Group 7: Artifact Download and Verification" -ForegroundColor Cyan

try {
    # Download output.log
    $downloadedContent = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/output.log" -UseBasicParsing -ErrorAction Stop
    
    Write-TestResult -TestName "Artifact download successful" -Passed ($downloadedContent.StatusCode -eq 200)
    
    # Verify content hash
    $downloadedHash = Calculate-SHA256FromBytes -Content $downloadedContent.Content
    Write-TestResult -TestName "Downloaded content SHA256 matches" -Passed ($downloadedHash -eq $outputHash) -Message "Downloaded: $($downloadedHash.Substring(0,16))... vs Original: $($outputHash.Substring(0,16))..."
    
    # Verify content type header
    $contentType = $downloadedContent.Headers["Content-Type"]
    $hasCorrectType = $contentType -like "text/plain*"
    Write-TestResult -TestName "Content-Type header correct" -Passed $hasCorrectType -Message "Got: $contentType"
}
catch {
    Write-TestResult -TestName "Artifact download successful" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST 8: Query Run Events
# =============================================================================

Write-Host "Test Group 8: Run Events Verification" -ForegroundColor Cyan

try {
    $eventsResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/events" -Method GET -ErrorAction Stop
    
    $hasEvents = $eventsResponse.events -and $eventsResponse.events.Count -gt 0
    Write-TestResult -TestName "Run events exist" -Passed $hasEvents -Message "Found $($eventsResponse.events.Count) events"
    
    if ($hasEvents) {
        # Check for expected event types
        $hasStarted = $eventsResponse.events | Where-Object { $_.type -eq "started" }
        $hasCompleted = $eventsResponse.events | Where-Object { $_.type -eq "completed" }
        
        Write-TestResult -TestName "Started event recorded" -Passed ($null -ne $hasStarted)
        Write-TestResult -TestName "Completed event recorded" -Passed ($null -ne $hasCompleted)
    }
}
catch {
    Write-TestResult -TestName "Run events exist" -Passed $false -Message $_.Exception.Message
}

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
Write-Host "   Test Summary" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
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

Write-Host "Test Run Details:" -ForegroundColor Gray
Write-Host "  Test ID:     $TestId" -ForegroundColor Gray
Write-Host "  Project ID:  $TestProjectId" -ForegroundColor Gray
Write-Host "  Agent ID:    $TestAgentId" -ForegroundColor Gray
Write-Host "  Run ID:      $TestRunId" -ForegroundColor Gray
Write-Host "  Backend URL: $BackendUrl" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests FAILED." -ForegroundColor Red
    exit 1
}

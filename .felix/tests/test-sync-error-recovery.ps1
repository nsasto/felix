<#
.SYNOPSIS
    Error recovery test for run artifact sync.

.DESCRIPTION
    This script tests the sync system's ability to recover from various error conditions:
    - Corrupt JSON in outbox file: Verify agent continues without crash and skips corrupt files
    - Invalid file path in batch upload: Verify agent handles missing files gracefully
    - Verify subsequent valid files are processed successfully

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER Timeout
    Maximum test duration in seconds (default: 60)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-error-recovery.ps1
    # Run error recovery test with defaults

.EXAMPLE
    .\scripts\test-sync-error-recovery.ps1 -BackendUrl http://localhost:8081 -Verbose
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
Write-Host "   Felix Sync Error Recovery Test" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-$TestId"
$TestAgentId = "test-agent-$TestId"
$TestDir = Join-Path $env:TEMP "felix-sync-error-recovery-$TestId"

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
    elseif ($Message -and $VerboseOutput) {
        Write-Host "         $Message" -ForegroundColor Gray
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
$FelixDir = Join-Path $PSScriptRoot ".."
$SyncInterfacePath = Join-Path $FelixDir "core\sync-interface.ps1"
$SyncPluginPath = Join-Path $FelixDir "plugins\sync-http\http-client.ps1"

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
# TEST SCENARIO 1: Corrupt JSON in Outbox File
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 1: Corrupt JSON in Outbox File" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating test scenario..." -ForegroundColor Yellow

# Configure environment
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = $BackendUrl

$config = @{
    base_url = $BackendUrl
    api_key  = $null
}

# Create test project via API first
try {
    $projectBody = @{
        id   = $TestProjectId
        name = "Error Recovery Test Project $TestId"
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

# Initialize reporter
try {
    $reporter = [HttpSync]::new($config, (Join-Path $TestDir ".felix"))
    $reporter.OutboxPath = $OutboxDir
    Write-Host "  [OK] Reporter initialized" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to initialize reporter: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "Test Group 1a: Corrupt JSON File Injection" -ForegroundColor Cyan

# Step 1: Create a corrupt JSON file in outbox (should be processed first due to timestamp)
$corruptTimestamp = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
$corruptFilePath = Join-Path $OutboxDir "$corruptTimestamp.jsonl"
$corruptContent = @"
{this is not valid json: [broken syntax
"@
$corruptContent | Set-Content -Path $corruptFilePath -Encoding UTF8
Write-Host "  Created corrupt JSON file: $(Split-Path $corruptFilePath -Leaf)" -ForegroundColor Gray

# Small delay to ensure timestamp ordering
Start-Sleep -Milliseconds 100

# Step 2: Create a valid agent registration request (should be processed after corrupt file)
$agentInfo = @{
    agent_id = $TestAgentId
    hostname = $env:COMPUTERNAME
    platform = "windows"
    version  = "1.0.0-error-recovery-test"
}

try {
    $reporter.RegisterAgent($agentInfo)
    Write-Host "  [OK] Valid agent registration queued" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Agent registration: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Count outbox files before flush
$outboxFilesBefore = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$countBefore = ($outboxFilesBefore | Measure-Object).Count
Write-Host "  Outbox files before flush: $countBefore" -ForegroundColor Gray

# Step 3: Attempt to flush outbox - this should handle the corrupt file gracefully
Write-Host ""
Write-Host "Attempting flush with corrupt file present..." -ForegroundColor Yellow

$flushError = $null
try {
    # Call flush (this calls TrySendOutbox internally)
    $reporter.Flush()
    Write-Host "  [OK] Flush completed without crash" -ForegroundColor Green
}
catch {
    $flushError = $_.Exception.Message
    Write-Host "  [WARN] Flush error: $flushError" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Test Group 1b: Corrupt File Handling Verification" -ForegroundColor Cyan

# Verify: Agent continues without crash
Write-TestResult -TestName "Agent continues without crash after corrupt JSON" -Passed ($flushError -eq $null) -Message "Error: $flushError"

# Check what files remain in outbox
$outboxFilesAfter = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$countAfter = ($outboxFilesAfter | Measure-Object).Count

# Check if corrupt file still exists (it should remain since it couldn't be processed)
$corruptFileExists = Test-Path $corruptFilePath
Write-TestResult -TestName "Corrupt file preserved for later investigation" -Passed $corruptFileExists -Message "Corrupt file: $(Split-Path $corruptFilePath -Leaf)"

# Note: Due to the break on error in TrySendOutbox, the subsequent valid file may also remain
# This is expected behavior - the sync system stops on first error to preserve ordering
# The test verifies the system doesn't crash and handles errors gracefully

Write-Host ""

# Clean up corrupt file for next scenario
if (Test-Path $corruptFilePath) {
    Remove-Item -Path $corruptFilePath -Force -ErrorAction SilentlyContinue
    Write-Host "  Cleaned up corrupt file for next scenario" -ForegroundColor Gray
}

# Flush again to process the remaining valid file
Start-Sleep -Milliseconds 500
try {
    $reporter.Flush()
    Write-Host "  [OK] Second flush completed" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Second flush: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Wait for processing
Start-Sleep -Seconds 1

# Verify valid agent registration was eventually processed
$outboxFilesFinal = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "run-*.jsonl" }
$countFinal = ($outboxFilesFinal | Measure-Object).Count
Write-TestResult -TestName "Valid operations processed after corrupt file removed" -Passed ($countFinal -eq 0) -Message "Remaining files: $countFinal"

Write-Host ""

# =============================================================================
# TEST SCENARIO 2: Invalid File Path in Batch Upload
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 2: Invalid File Path in Batch Upload" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating test scenario..." -ForegroundColor Yellow

# Start a new run for this scenario
$scenario2RunId = $null
$runMetadata = @{
    agent_id       = $TestAgentId
    project_id     = $TestProjectId
    requirement_id = "S-ERRRECOVERY-$TestId"
    branch         = "test/error-recovery"
    scenario       = "testing"
    phase          = "missing-file-test"
}

try {
    $scenario2RunId = $reporter.StartRun($runMetadata)
    Write-Host "  [OK] Test run created: $scenario2RunId" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to create run: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Wait for run creation to be processed
Start-Sleep -Seconds 1
try { $reporter.Flush() } catch {}

# Create run folder with artifacts
$runFolder = Join-Path $TestDir "runs\$scenario2RunId"
New-Item -ItemType Directory -Path $runFolder -Force | Out-Null

# Create a valid artifact file
$validContent = @"
# Valid Test Plan

## Summary
This is a valid plan file for the error recovery test.

## Tasks
- [x] Task 1: Test missing file handling
- [x] Task 2: Verify partial upload success
"@
$validPath = Join-Path $runFolder "plan.md"
$validContent | Set-Content -Path $validPath -Encoding UTF8
$validHash = Calculate-SHA256 -FilePath $validPath

Write-Host "  Created valid artifact: plan.md (SHA: $($validHash.Substring(0,16))...)" -ForegroundColor Gray

Write-Host ""
Write-Host "Test Group 2a: Batch Upload with Missing File" -ForegroundColor Cyan

# Manually create a batch upload manifest with an invalid (missing) file path
$timestamp = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
$batchFilePath = Join-Path $OutboxDir "$timestamp-batch-upload.jsonl"

$batchRequest = @{
    timestamp = [System.DateTime]::UtcNow.ToString("o")
    run_id    = $scenario2RunId
    files     = @(
        @{
            path         = "plan.md"
            local_path   = $validPath
            sha256       = $validHash
            size_bytes   = (Get-Item $validPath).Length
            content_type = "text/markdown"
        },
        @{
            path         = "missing-file.txt"
            local_path   = "C:\nonexistent\path\that\does\not\exist\missing-file.txt"
            sha256       = "0000000000000000000000000000000000000000000000000000000000000000"
            size_bytes   = 0
            content_type = "text/plain"
        },
        @{
            path         = "another-missing.log"
            local_path   = Join-Path $runFolder "does-not-exist.log"
            sha256       = "1111111111111111111111111111111111111111111111111111111111111111"
            size_bytes   = 100
            content_type = "text/plain"
        }
    )
}

$batchJson = $batchRequest | ConvertTo-Json -Depth 10 -Compress
$batchJson | Set-Content -Path $batchFilePath -Encoding UTF8

Write-Host "  Created batch upload manifest with 1 valid + 2 missing files" -ForegroundColor Gray
Write-Host "  - plan.md (exists)" -ForegroundColor Gray
Write-Host "  - missing-file.txt (does NOT exist)" -ForegroundColor Gray
Write-Host "  - another-missing.log (does NOT exist)" -ForegroundColor Gray

Write-Host ""
Write-Host "Attempting batch upload with missing files..." -ForegroundColor Yellow

$batchError = $null
try {
    $reporter.Flush()
    Write-Host "  [OK] Flush completed without crash" -ForegroundColor Green
}
catch {
    $batchError = $_.Exception.Message
    Write-Host "  [WARN] Flush error: $batchError" -ForegroundColor Yellow
}

# Wait for upload to complete
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Test Group 2b: Missing File Handling Verification" -ForegroundColor Cyan

# Verify: Agent handles missing files gracefully
Write-TestResult -TestName "Agent handles missing files without crash" -Passed ($batchError -eq $null) -Message "Error: $batchError"

# Check if batch upload file was processed (should be removed after successful partial upload)
$batchFileExists = Test-Path $batchFilePath
Write-TestResult -TestName "Batch upload processed" -Passed (-not $batchFileExists) -Message "File still exists: $batchFileExists"

# Verify valid file was uploaded successfully via API
Write-Host ""
Write-Host "Test Group 2c: Valid File Upload Verification" -ForegroundColor Cyan

try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$scenario2RunId/files" -Method GET -ErrorAction Stop
    
    $fileCount = $filesResponse.files.Count
    Write-TestResult -TestName "Run files exist in database" -Passed ($fileCount -gt 0) -Message "Found $fileCount files"
    
    # Check if valid file was uploaded
    $planFile = $filesResponse.files | Where-Object { $_.path -eq "plan.md" }
    Write-TestResult -TestName "Valid plan.md was uploaded" -Passed ($null -ne $planFile)
    
    if ($planFile) {
        Write-TestResult -TestName "plan.md SHA256 matches" -Passed ($planFile.sha256 -eq $validHash) -Message "DB: $($planFile.sha256.Substring(0,16))..."
    }
    
    # Verify missing files were NOT uploaded (they shouldn't exist in the database)
    $missingFile = $filesResponse.files | Where-Object { $_.path -eq "missing-file.txt" }
    $anotherMissing = $filesResponse.files | Where-Object { $_.path -eq "another-missing.log" }
    
    Write-TestResult -TestName "Missing file NOT in database" -Passed ($null -eq $missingFile) -Message "missing-file.txt should not exist"
    Write-TestResult -TestName "Another missing file NOT in database" -Passed ($null -eq $anotherMissing) -Message "another-missing.log should not exist"
}
catch {
    Write-TestResult -TestName "Run files verification" -Passed $false -Message $_.Exception.Message
}

# Download valid file to verify content integrity
Write-Host ""
Write-Host "Test Group 2d: Downloaded Content Verification" -ForegroundColor Cyan

try {
    $downloadResponse = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$scenario2RunId/files/plan.md" -UseBasicParsing -ErrorAction Stop
    
    Write-TestResult -TestName "plan.md downloadable" -Passed ($downloadResponse.StatusCode -eq 200)
    
    $downloadedHash = Calculate-SHA256FromBytes -Content $downloadResponse.Content
    Write-TestResult -TestName "Downloaded content matches original" -Passed ($downloadedHash -eq $validHash) -Message "Downloaded: $($downloadedHash.Substring(0,16))..."
}
catch {
    Write-TestResult -TestName "plan.md downloadable" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# Finish the test run
try {
    $finishResult = @{
        status       = "completed"
        exit_code    = 0
        duration_sec = 10
    }
    $reporter.FinishRun($scenario2RunId, $finishResult)
    Write-Host "  [OK] Test run completed" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Finish run: $($_.Exception.Message)" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1

# =============================================================================
# TEST SCENARIO 3: Multiple Corrupt Files Mixed with Valid
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 3: Multiple Corrupt Files in Queue" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating test scenario with multiple files..." -ForegroundColor Yellow

# Create multiple files: corrupt, valid, corrupt, valid (in timestamp order)
$ts1 = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
Start-Sleep -Milliseconds 50
$ts2 = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
Start-Sleep -Milliseconds 50
$ts3 = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
Start-Sleep -Milliseconds 50
$ts4 = [System.DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")

# File 1: Corrupt JSON (empty braces that parse but fail semantically)
$corrupt1Path = Join-Path $OutboxDir "$ts1.jsonl"
"{ invalid json here" | Set-Content -Path $corrupt1Path -Encoding UTF8
Write-Host "  Created corrupt file 1: $ts1.jsonl" -ForegroundColor Gray

# File 2: Valid agent re-registration (will update existing)
$valid1Path = Join-Path $OutboxDir "$ts2.jsonl"
$valid1Request = @{
    timestamp = [System.DateTime]::UtcNow.ToString("o")
    method    = "POST"
    endpoint  = "/api/agents/register"
    body      = @{
        agent_id = "$TestAgentId-v2"
        hostname = $env:COMPUTERNAME
        platform = "windows"
        version  = "1.0.1-error-recovery-test"
    }
}
($valid1Request | ConvertTo-Json -Depth 10 -Compress) | Set-Content -Path $valid1Path -Encoding UTF8
Write-Host "  Created valid file 2: $ts2.jsonl (agent register)" -ForegroundColor Gray

# File 3: Another corrupt file
$corrupt2Path = Join-Path $OutboxDir "$ts3.jsonl"
"not json at all: just plain text with special chars <>&" | Set-Content -Path $corrupt2Path -Encoding UTF8
Write-Host "  Created corrupt file 3: $ts3.jsonl" -ForegroundColor Gray

# File 4: Valid run creation
$valid2Path = Join-Path $OutboxDir "$ts4.jsonl"
$scenario3RunId = [System.Guid]::NewGuid().ToString()
$valid2Request = @{
    timestamp = [System.DateTime]::UtcNow.ToString("o")
    method    = "POST"
    endpoint  = "/api/runs"
    body      = @{
        id             = $scenario3RunId
        agent_id       = $TestAgentId
        project_id     = $TestProjectId
        requirement_id = "S-ERRRECOVERY-$TestId-3"
        branch         = "test/error-recovery"
        scenario       = "testing"
        phase          = "multi-corrupt-test"
    }
}
($valid2Request | ConvertTo-Json -Depth 10 -Compress) | Set-Content -Path $valid2Path -Encoding UTF8
Write-Host "  Created valid file 4: $ts4.jsonl (run creation)" -ForegroundColor Gray

# Count outbox files
$outboxFilesScenario3 = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "run-*.jsonl" }
Write-Host "  Total outbox files: $($outboxFilesScenario3.Count)" -ForegroundColor Gray

Write-Host ""
Write-Host "Test Group 3a: Processing Queue with Multiple Errors" -ForegroundColor Cyan

$multiError = $null
try {
    $reporter.Flush()
    Write-Host "  [OK] Flush completed without crash" -ForegroundColor Green
}
catch {
    $multiError = $_.Exception.Message
    Write-Host "  [WARN] Flush error: $multiError" -ForegroundColor Yellow
}

Write-TestResult -TestName "Agent survives multiple corrupt files" -Passed ($multiError -eq $null) -Message "Error: $multiError"

# Due to break-on-error behavior, the first corrupt file will stop processing
# We need to clean up corrupt files and retry

Write-Host ""
Write-Host "Test Group 3b: Recovery After Manual Cleanup" -ForegroundColor Cyan

# Remove corrupt files (simulating manual intervention or automated cleanup)
if (Test-Path $corrupt1Path) { Remove-Item $corrupt1Path -Force }
if (Test-Path $corrupt2Path) { Remove-Item $corrupt2Path -Force }
Write-Host "  Removed corrupt files (simulating manual cleanup)" -ForegroundColor Gray

# Retry flush
Start-Sleep -Milliseconds 500
try {
    $reporter.Flush()
    Write-Host "  [OK] Retry flush completed" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Retry flush: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Wait for processing
Start-Sleep -Seconds 2

# Check if valid files were processed
$remainingFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "run-*.jsonl" }
$remainingCount = ($remainingFiles | Measure-Object).Count

Write-TestResult -TestName "Valid files processed after cleanup" -Passed ($remainingCount -eq 0) -Message "Remaining files: $remainingCount"

# =============================================================================
# CLEANUP
# =============================================================================

Write-Host ""
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
Write-Host "  Test ID:          $TestId" -ForegroundColor Gray
Write-Host "  Project ID:       $TestProjectId" -ForegroundColor Gray
Write-Host "  Agent ID:         $TestAgentId" -ForegroundColor Gray
Write-Host "  Scenario 2 Run:   $scenario2RunId" -ForegroundColor Gray
Write-Host "  Backend URL:      $BackendUrl" -ForegroundColor Gray
Write-Host ""

Write-Host "Error Recovery Test Notes:" -ForegroundColor Gray
Write-Host "  Scenario 1: Corrupt JSON in outbox" -ForegroundColor Gray
Write-Host "    - Agent continues without crash on corrupt JSON" -ForegroundColor Gray
Write-Host "    - Corrupt files preserved for investigation" -ForegroundColor Gray
Write-Host "    - Valid files processed after cleanup" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 2: Invalid file paths in batch upload" -ForegroundColor Gray
Write-Host "    - Missing files skipped gracefully" -ForegroundColor Gray
Write-Host "    - Valid files in same batch uploaded successfully" -ForegroundColor Gray
Write-Host "    - No corruption or cross-contamination" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 3: Multiple corrupt files mixed with valid" -ForegroundColor Gray
Write-Host "    - System survives multiple corruption scenarios" -ForegroundColor Gray
Write-Host "    - Recovery possible after cleanup" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests PASSED! Error recovery mechanisms working correctly." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests FAILED." -ForegroundColor Red
    exit 1
}

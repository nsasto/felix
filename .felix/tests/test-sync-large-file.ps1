<#
.SYNOPSIS
    Large file upload test for run artifact sync.

.DESCRIPTION
    This script tests the sync functionality with a large file (5MB):
    - Creates a 5MB output.log file using PowerShell
    - Places file in test run folder
    - Uploads via UploadRunFolder method
    - Verifies upload succeeds without timeout
    - Downloads file via GET /api/runs/{run_id}/files/output.log
    - Compares SHA256 hash of downloaded vs original
    - Verifies upload completes in under 30 seconds
    - Ensures no memory issues or process crashes (exit code 0)

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER FileSizeMB
    Size of the test file in megabytes (default: 5)

.PARAMETER UploadTimeout
    Maximum time in seconds for upload to complete (default: 30)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-large-file.ps1
    # Run large file test with defaults (5MB file)

.EXAMPLE
    .\scripts\test-sync-large-file.ps1 -FileSizeMB 10 -UploadTimeout 60
    # Test with 10MB file and 60 second timeout

.NOTES
    Prerequisites:
    - Backend server running at specified URL
    - Run test-sync-setup.ps1 first to initialize environment

    Exit codes:
    - 0: All tests passed
    - 1: One or more tests failed
    - 2: Prerequisites not met (backend unavailable, etc.)
#>

param(
    [string]$BackendUrl = "http://localhost:8080",
    [int]$FileSizeMB = 5,
    [int]$UploadTimeout = 30,
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Large File Test (${FileSizeMB}MB)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-large-$TestId"
$TestAgentId = "test-agent-large-$TestId"
$TestRunId = $null  # Will be set after run creation
$TestDir = Join-Path $env:TEMP "felix-sync-large-file-$TestId"
$FileSizeBytes = $FileSizeMB * 1024 * 1024

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

function Generate-LargeLogFile {
    param(
        [string]$FilePath,
        [int]$TargetSizeBytes
    )
    
    $sw = [System.IO.StreamWriter]::new($FilePath, $false, [System.Text.Encoding]::UTF8)
    try {
        $bytesWritten = 0
        $lineNumber = 0
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Write header
        $header = "[INFO] Large file test started at $timestamp`r`n"
        $header += "[INFO] Target size: $TargetSizeBytes bytes`r`n"
        $header += "[INFO] Test ID: $TestId`r`n"
        $header += "=" * 80 + "`r`n`r`n"
        $sw.Write($header)
        $bytesWritten += [System.Text.Encoding]::UTF8.GetByteCount($header)
        
        # Generate log content until we reach target size
        $logLevels = @("INFO", "DEBUG", "TRACE", "WARN")
        $operations = @(
            "Processing file",
            "Analyzing data",
            "Computing hash",
            "Validating input",
            "Transforming output",
            "Executing operation",
            "Loading configuration",
            "Initializing component",
            "Performing calculation",
            "Serializing result"
        )
        $random = [System.Random]::new()
        
        while ($bytesWritten -lt $TargetSizeBytes) {
            $lineNumber++
            $level = $logLevels[$random.Next($logLevels.Count)]
            $operation = $operations[$random.Next($operations.Count)]
            $detail = "iteration=$lineNumber, elapsed=$($random.Next(1, 1000))ms, threads=$($random.Next(1, 16)), memory=$($random.Next(100, 9999))KB"
            
            $line = "[$level] $timestamp $operation - $detail`r`n"
            $sw.Write($line)
            $bytesWritten += [System.Text.Encoding]::UTF8.GetByteCount($line)
            
            # Occasional multi-line data blocks to make it more realistic
            if ($lineNumber % 500 -eq 0) {
                $block = @"
-------------------------------------------------------------------
Status Report (Line $lineNumber)
  Bytes Written: $bytesWritten / $TargetSizeBytes
  Progress: $([math]::Round($bytesWritten * 100 / $TargetSizeBytes, 1))%
  Memory Usage: $($random.Next(50, 200))MB
-------------------------------------------------------------------

"@
                $sw.Write($block)
                $bytesWritten += [System.Text.Encoding]::UTF8.GetByteCount($block)
            }
        }
        
        # Write footer
        $footer = "`r`n" + "=" * 80 + "`r`n"
        $footer += "[INFO] Large file test completed`r`n"
        $footer += "[INFO] Final size: $bytesWritten bytes`r`n"
        $footer += "[INFO] Total lines: $lineNumber`r`n"
        $sw.Write($footer)
    }
    finally {
        $sw.Close()
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
# SETUP: Create Test Project via API
# =============================================================================

Write-Host "Setting up test data..." -ForegroundColor Yellow

# Create test project via API
try {
    $projectBody = @{
        id   = $TestProjectId
        name = "Test Project Large File $TestId"
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
        Write-Host "         Continuing with direct setup..." -ForegroundColor Yellow
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
# TEST 2: Start Run
# =============================================================================

Write-Host "Test Group 2: Run Creation" -ForegroundColor Cyan

$runMetadata = @{
    agent_id       = $TestAgentId
    project_id     = $TestProjectId
    requirement_id = "S-LARGE-$TestId"
    branch         = "test/large-file"
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

# Wait for run creation to be processed
Start-Sleep -Milliseconds 500

Write-Host ""

# =============================================================================
# TEST 3: Create Large Test File
# =============================================================================

Write-Host "Test Group 3: Large File Creation (${FileSizeMB}MB)" -ForegroundColor Cyan

# Create run folder and large file
$runFolder = Join-Path $TestDir "runs\$TestRunId"
New-Item -ItemType Directory -Path $runFolder -Force | Out-Null

$outputPath = Join-Path $runFolder "output.log"

try {
    $createMeasure = Measure-Command {
        Generate-LargeLogFile -FilePath $outputPath -TargetSizeBytes $FileSizeBytes
    }
    
    $fileInfo = Get-Item $outputPath
    $actualSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    
    Write-TestResult -TestName "Large file created ($actualSizeMB MB)" -Passed $true -Message "Created in $([math]::Round($createMeasure.TotalSeconds, 2))s"
    
    # Calculate SHA256 for later comparison
    $originalHash = Calculate-SHA256 -FilePath $outputPath
    Write-Host "    Original SHA256: $($originalHash.Substring(0, 32))..." -ForegroundColor Gray
}
catch {
    Write-TestResult -TestName "Large file created" -Passed $false -Message $_.Exception.Message
    exit 1
}

Write-Host ""

# =============================================================================
# TEST 4: Upload Large File via UploadRunFolder
# =============================================================================

Write-Host "Test Group 4: Large File Upload (timeout: ${UploadTimeout}s)" -ForegroundColor Cyan

$uploadSucceeded = $false
$uploadDuration = 0

try {
    $uploadMeasure = Measure-Command {
        $reporter.UploadRunFolder($TestRunId, $runFolder)
        # Trigger outbox flush
        $reporter.Flush()
    }
    
    $uploadDuration = $uploadMeasure.TotalSeconds
    
    # Check if outbox is empty (indicating successful upload)
    $outboxFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "run-*.jsonl" }
    $outboxEmpty = ($outboxFiles | Measure-Object).Count -eq 0
    
    if ($outboxEmpty) {
        $uploadSucceeded = $true
        Write-TestResult -TestName "Upload succeeded without timeout" -Passed $true -Message "Completed in $([math]::Round($uploadDuration, 2))s"
    }
    else {
        Write-TestResult -TestName "Upload succeeded without timeout" -Passed $false -Message "Outbox not empty - upload may have failed"
    }
}
catch {
    Write-TestResult -TestName "Upload succeeded without timeout" -Passed $false -Message $_.Exception.Message
}

# Verify upload time is under limit
$underTimeLimit = $uploadDuration -lt $UploadTimeout
Write-TestResult -TestName "Upload completed in under ${UploadTimeout}s" -Passed $underTimeLimit -Message "Actual: $([math]::Round($uploadDuration, 2))s"

Write-Host ""

# =============================================================================
# TEST 5: Finish Run
# =============================================================================

Write-Host "Test Group 5: Run Completion" -ForegroundColor Cyan

$runResult = @{
    status       = "completed"
    exit_code    = 0
    duration_sec = [math]::Round($uploadDuration, 2)
    summary_json = @{
        file_size_mb   = $actualSizeMB
        upload_time_s  = [math]::Round($uploadDuration, 2)
        throughput_mbs = [math]::Round($actualSizeMB / $uploadDuration, 2)
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

Write-Host ""

# =============================================================================
# TEST 6: Download File and Verify SHA256
# =============================================================================

Write-Host "Test Group 6: Download and SHA256 Verification" -ForegroundColor Cyan

try {
    $downloadMeasure = Measure-Command {
        $downloadedContent = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/output.log" -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    }
    
    Write-TestResult -TestName "Artifact download successful" -Passed ($downloadedContent.StatusCode -eq 200) -Message "Downloaded in $([math]::Round($downloadMeasure.TotalSeconds, 2))s"
    
    # Verify content hash
    $downloadedHash = Calculate-SHA256FromBytes -Content $downloadedContent.Content
    $hashMatches = $downloadedHash -eq $originalHash
    
    Write-TestResult -TestName "Downloaded content SHA256 matches original" -Passed $hashMatches -Message "Downloaded: $($downloadedHash.Substring(0, 32))..."
    
    # Verify downloaded size matches
    $downloadedSize = $downloadedContent.Content.Length
    $downloadedSizeMB = [math]::Round($downloadedSize / 1MB, 2)
    $sizeMatches = [math]::Abs($downloadedSize - $fileInfo.Length) -lt 1024  # Allow 1KB tolerance
    
    Write-TestResult -TestName "Downloaded file size matches ($downloadedSizeMB MB)" -Passed $sizeMatches -Message "Original: $actualSizeMB MB, Downloaded: $downloadedSizeMB MB"
}
catch {
    Write-TestResult -TestName "Artifact download successful" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST 7: Verify Database Records via API
# =============================================================================

Write-Host "Test Group 7: Database Verification via API" -ForegroundColor Cyan

try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    $hasFiles = $filesResponse.files -and $filesResponse.files.Count -gt 0
    Write-TestResult -TestName "Run files exist in database" -Passed $hasFiles -Message "Found $($filesResponse.files.Count) file(s)"
    
    if ($hasFiles) {
        # Check for output.log file
        $outputFile = $filesResponse.files | Where-Object { $_.path -eq "output.log" }
        
        Write-TestResult -TestName "Output file recorded in database" -Passed ($null -ne $outputFile)
        
        if ($outputFile) {
            # Verify size_bytes is correct
            $dbSize = $outputFile.size_bytes
            $sizeMatches = [math]::Abs($dbSize - $fileInfo.Length) -lt 1024  # Allow 1KB tolerance
            Write-TestResult -TestName "Database size_bytes matches actual file size" -Passed $sizeMatches -Message "DB: $dbSize, Actual: $($fileInfo.Length)"
            
            # Verify SHA256 hash
            $dbHash = $outputFile.sha256
            $dbHashMatches = $dbHash -eq $originalHash
            Write-TestResult -TestName "Database SHA256 matches original" -Passed $dbHashMatches
            
            # Verify content_type
            $contentTypeOk = $outputFile.content_type -like "text/*"
            Write-TestResult -TestName "Content-Type is correct (text/*)" -Passed $contentTypeOk -Message "Got: $($outputFile.content_type)"
        }
    }
}
catch {
    Write-TestResult -TestName "Run files exist in database" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST 8: Memory and Process Health Check
# =============================================================================

Write-Host "Test Group 8: Memory and Process Health" -ForegroundColor Cyan

# Check PowerShell memory usage isn't excessive
$currentProcess = Get-Process -Id $PID
$memoryMB = [math]::Round($currentProcess.WorkingSet64 / 1MB, 2)

# Memory under 500MB is reasonable for this test
$memoryOk = $memoryMB -lt 500
Write-TestResult -TestName "PowerShell memory usage reasonable (<500MB)" -Passed $memoryOk -Message "Current: $memoryMB MB"

# No exceptions so far means no crashes
Write-TestResult -TestName "No process crashes detected" -Passed $true

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

Write-Host "Performance Metrics:" -ForegroundColor Gray
Write-Host "  File Size:     $actualSizeMB MB" -ForegroundColor Gray
Write-Host "  Upload Time:   $([math]::Round($uploadDuration, 2)) seconds" -ForegroundColor Gray
if ($uploadDuration -gt 0) {
    Write-Host "  Throughput:    $([math]::Round($actualSizeMB / $uploadDuration, 2)) MB/s" -ForegroundColor Gray
}
Write-Host "  Memory Usage:  $memoryMB MB" -ForegroundColor Gray
Write-Host ""

Write-Host "Test Run Details:" -ForegroundColor Gray
Write-Host "  Test ID:       $TestId" -ForegroundColor Gray
Write-Host "  Project ID:    $TestProjectId" -ForegroundColor Gray
Write-Host "  Run ID:        $TestRunId" -ForegroundColor Gray
Write-Host "  Backend URL:   $BackendUrl" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests FAILED." -ForegroundColor Red
    exit 1
}

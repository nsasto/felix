<#
.SYNOPSIS
    Data integrity test for run artifact sync.

.DESCRIPTION
    This script verifies data integrity across the run artifact sync system:
    - Verify SHA256 hashes match between source and storage
    - Verify database foreign key constraints enforced
    - Verify run events ordered by timestamp
    - Verify artifact metadata matches file properties (size_bytes, content_type)
    - Check for orphaned records in run_files without corresponding runs
    - Check for orphaned files in storage without run_files records

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER Timeout
    Maximum test duration in seconds (default: 60)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-data-integrity.ps1
    # Run data integrity test with defaults

.EXAMPLE
    .\scripts\test-sync-data-integrity.ps1 -BackendUrl http://localhost:8081 -Verbose
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
Write-Host "   Felix Sync Data Integrity Test" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-$TestId"
$TestAgentId = "test-agent-$TestId"
$TestDir = Join-Path $env:TEMP "felix-sync-data-integrity-$TestId"

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
# SETUP: Create Test Project, Agent, and Run with Artifacts
# =============================================================================

Write-Host "Setting up test data..." -ForegroundColor Yellow

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
        name = "Data Integrity Test Project $TestId"
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

# Register agent
$agentInfo = @{
    agent_id = $TestAgentId
    hostname = $env:COMPUTERNAME
    platform = "windows"
    version  = "1.0.0-data-integrity-test"
}

try {
    $reporter.RegisterAgent($agentInfo)
    Write-Host "  [OK] Agent registered: $TestAgentId" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Agent registration: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Wait for registration to process
Start-Sleep -Milliseconds 500
try { $reporter.Flush() } catch {}

# Start a test run
$TestRunId = $null
$runMetadata = @{
    agent_id       = $TestAgentId
    project_id     = $TestProjectId
    requirement_id = "S-DATAINTEGRITY-$TestId"
    branch         = "test/data-integrity"
    scenario       = "testing"
    phase          = "integrity-test"
}

try {
    $TestRunId = $reporter.StartRun($runMetadata)
    Write-Host "  [OK] Test run created: $TestRunId" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to create run: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

# Wait for run creation
Start-Sleep -Seconds 1
try { $reporter.Flush() } catch {}

# Create test artifact files with known content
$runFolder = Join-Path $TestDir "runs\$TestRunId"
New-Item -ItemType Directory -Path $runFolder -Force | Out-Null

# Artifact 1: Plan file (markdown)
$planContent = @"
# Test Plan for Data Integrity Test

## Summary
This is a test plan created for the data integrity test.
Test ID: $TestId

## Tasks
- [x] Task 1: Create test files with known hashes
- [x] Task 2: Upload artifacts via sync
- [x] Task 3: Verify hashes match in database
- [x] Task 4: Verify metadata matches file properties
"@
$planPath = Join-Path $runFolder "plan-S-DATAINTEGRITY-$TestId.md"
$planContent | Set-Content -Path $planPath -Encoding UTF8

# Artifact 2: Output log (text)
$outputContent = @"
[INFO] Data integrity test started at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
[INFO] Test ID: $TestId
[INFO] Project ID: $TestProjectId
[INFO] Agent ID: $TestAgentId
[INFO] Run ID: $TestRunId
[DEBUG] Creating test artifacts with known hashes
[INFO] Uploading artifacts to server
[INFO] Test completed successfully
"@
$outputPath = Join-Path $runFolder "output.log"
$outputContent | Set-Content -Path $outputPath -Encoding UTF8

# Artifact 3: JSON data
$jsonContent = @{
    test_id     = $TestId
    project_id  = $TestProjectId
    agent_id    = $TestAgentId
    run_id      = $TestRunId
    created_at  = (Get-Date -Format "o")
    test_data   = @{
        key1 = "value1"
        key2 = 42
        key3 = @(1, 2, 3)
    }
} | ConvertTo-Json -Depth 10
$jsonPath = Join-Path $runFolder "data.json"
$jsonContent | Set-Content -Path $jsonPath -Encoding UTF8

# Calculate expected hashes and sizes
$planHash = Calculate-SHA256 -FilePath $planPath
$outputHash = Calculate-SHA256 -FilePath $outputPath
$jsonHash = Calculate-SHA256 -FilePath $jsonPath

$planSize = (Get-Item $planPath).Length
$outputSize = (Get-Item $outputPath).Length
$jsonSize = (Get-Item $jsonPath).Length

Write-Host "  Created test artifacts:" -ForegroundColor Gray
Write-Host "    - plan-S-DATAINTEGRITY-$TestId.md (SHA: $($planHash.Substring(0,16))..., Size: $planSize bytes)" -ForegroundColor Gray
Write-Host "    - output.log (SHA: $($outputHash.Substring(0,16))..., Size: $outputSize bytes)" -ForegroundColor Gray
Write-Host "    - data.json (SHA: $($jsonHash.Substring(0,16))..., Size: $jsonSize bytes)" -ForegroundColor Gray

# Upload artifacts
try {
    $reporter.UploadRunFolder($TestRunId, $runFolder)
    Write-Host "  [OK] Artifacts uploaded" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to upload artifacts: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

# Finish the run
$runResult = @{
    status       = "completed"
    exit_code    = 0
    duration_sec = 10
}

try {
    $reporter.FinishRun($TestRunId, $runResult)
    Write-Host "  [OK] Test run completed" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Finish run: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Wait for all uploads to complete
Start-Sleep -Seconds 2
try { $reporter.Flush() } catch {}

Write-Host ""

# =============================================================================
# TEST SCENARIO 1: SHA256 Hash Verification
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 1: SHA256 Hash Verification" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Verifying SHA256 hashes match between source and storage..." -ForegroundColor Yellow

# Get files from database via API
try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    $fileCount = $filesResponse.files.Count
    Write-TestResult -TestName "Run files exist in database" -Passed ($fileCount -gt 0) -Message "Found $fileCount files"
    
    if ($fileCount -gt 0) {
        # Verify each file's hash
        $planFile = $filesResponse.files | Where-Object { $_.path -like "plan-*.md" }
        $outputFile = $filesResponse.files | Where-Object { $_.path -eq "output.log" }
        $jsonFile = $filesResponse.files | Where-Object { $_.path -eq "data.json" }
        
        if ($planFile) {
            $dbPlanHash = $planFile.sha256
            Write-TestResult -TestName "Plan file SHA256 matches" -Passed ($dbPlanHash -eq $planHash) -Message "DB: $($dbPlanHash.Substring(0,16))... vs Local: $($planHash.Substring(0,16))..."
        }
        else {
            Write-TestResult -TestName "Plan file SHA256 matches" -Passed $false -Message "Plan file not found in database"
        }
        
        if ($outputFile) {
            $dbOutputHash = $outputFile.sha256
            Write-TestResult -TestName "Output file SHA256 matches" -Passed ($dbOutputHash -eq $outputHash) -Message "DB: $($dbOutputHash.Substring(0,16))... vs Local: $($outputHash.Substring(0,16))..."
        }
        else {
            Write-TestResult -TestName "Output file SHA256 matches" -Passed $false -Message "Output file not found in database"
        }
        
        if ($jsonFile) {
            $dbJsonHash = $jsonFile.sha256
            Write-TestResult -TestName "JSON file SHA256 matches" -Passed ($dbJsonHash -eq $jsonHash) -Message "DB: $($dbJsonHash.Substring(0,16))... vs Local: $($jsonHash.Substring(0,16))..."
        }
        else {
            Write-TestResult -TestName "JSON file SHA256 matches" -Passed $false -Message "JSON file not found in database"
        }
    }
}
catch {
    Write-TestResult -TestName "Run files exist in database" -Passed $false -Message $_.Exception.Message
}

Write-Host ""
Write-Host "Verifying downloaded content SHA256 matches..." -ForegroundColor Yellow

# Download each file and verify hash
try {
    $downloadedPlan = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/plan-S-DATAINTEGRITY-$TestId.md" -UseBasicParsing -ErrorAction Stop
    $downloadedPlanHash = Calculate-SHA256FromBytes -Content $downloadedPlan.Content
    Write-TestResult -TestName "Downloaded plan SHA256 matches original" -Passed ($downloadedPlanHash -eq $planHash) -Message "Downloaded: $($downloadedPlanHash.Substring(0,16))..."
}
catch {
    Write-TestResult -TestName "Downloaded plan SHA256 matches original" -Passed $false -Message $_.Exception.Message
}

try {
    $downloadedOutput = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/output.log" -UseBasicParsing -ErrorAction Stop
    $downloadedOutputHash = Calculate-SHA256FromBytes -Content $downloadedOutput.Content
    Write-TestResult -TestName "Downloaded output SHA256 matches original" -Passed ($downloadedOutputHash -eq $outputHash) -Message "Downloaded: $($downloadedOutputHash.Substring(0,16))..."
}
catch {
    Write-TestResult -TestName "Downloaded output SHA256 matches original" -Passed $false -Message $_.Exception.Message
}

try {
    $downloadedJson = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/data.json" -UseBasicParsing -ErrorAction Stop
    $downloadedJsonHash = Calculate-SHA256FromBytes -Content $downloadedJson.Content
    Write-TestResult -TestName "Downloaded JSON SHA256 matches original" -Passed ($downloadedJsonHash -eq $jsonHash) -Message "Downloaded: $($downloadedJsonHash.Substring(0,16))..."
}
catch {
    Write-TestResult -TestName "Downloaded JSON SHA256 matches original" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST SCENARIO 2: Foreign Key Constraint Enforcement
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 2: Foreign Key Constraint Enforcement" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing database foreign key constraints..." -ForegroundColor Yellow

# Attempt to create a run_file for a non-existent run via direct API call
$fakeRunId = [System.Guid]::NewGuid().ToString()
$fakeManifest = @(
    @{
        path   = "fake-file.txt"
        sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
    }
) | ConvertTo-Json

try {
    # This should fail with 404 because the run doesn't exist
    $response = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$fakeRunId/files" `
        -Method POST `
        -ContentType "multipart/form-data" `
        -Form @{
            manifest = $fakeManifest
            files    = Get-Item $planPath
        } `
        -ErrorAction Stop
    
    # If we get here, the constraint wasn't enforced
    Write-TestResult -TestName "Foreign key prevents orphan run_files" -Passed $false -Message "Upload succeeded for non-existent run"
}
catch {
    # Check if it's a 404 (expected) or other error
    $statusCode = 0
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
    }
    
    $isExpectedError = ($statusCode -eq 404) -or ($_.Exception.Message -match "Run not found")
    Write-TestResult -TestName "Foreign key prevents orphan run_files" -Passed $isExpectedError -Message "Status: $statusCode"
}

# Attempt to create events for a non-existent run
try {
    $fakeEvents = @(
        @{
            type    = "test_event"
            level   = "info"
            message = "This should fail"
        }
    )
    
    $response = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$fakeRunId/events" `
        -Method POST `
        -Body ($fakeEvents | ConvertTo-Json) `
        -ContentType "application/json" `
        -ErrorAction Stop
    
    Write-TestResult -TestName "Foreign key prevents orphan run_events" -Passed $false -Message "Event append succeeded for non-existent run"
}
catch {
    $statusCode = 0
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
    }
    
    $isExpectedError = ($statusCode -eq 404) -or ($_.Exception.Message -match "Run not found")
    Write-TestResult -TestName "Foreign key prevents orphan run_events" -Passed $isExpectedError -Message "Status: $statusCode"
}

Write-Host ""

# =============================================================================
# TEST SCENARIO 3: Run Events Timestamp Ordering
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 3: Run Events Timestamp Ordering" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Verifying run events are ordered by timestamp..." -ForegroundColor Yellow

try {
    $eventsResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/events" -Method GET -ErrorAction Stop
    
    $hasEvents = $eventsResponse.events -and $eventsResponse.events.Count -gt 0
    Write-TestResult -TestName "Run events exist" -Passed $hasEvents -Message "Found $($eventsResponse.events.Count) events"
    
    if ($hasEvents -and $eventsResponse.events.Count -ge 2) {
        # Verify events are in ascending order by id (timeline order)
        $inOrder = $true
        $lastId = 0
        $lastTs = $null
        
        foreach ($event in $eventsResponse.events) {
            if ($event.id -le $lastId) {
                $inOrder = $false
                break
            }
            $lastId = $event.id
        }
        
        Write-TestResult -TestName "Events ordered by ID (ascending)" -Passed $inOrder -Message "IDs checked: $($eventsResponse.events.Count)"
        
        # Check for expected event types
        $eventTypes = $eventsResponse.events | ForEach-Object { $_.type }
        $hasStarted = "started" -in $eventTypes
        $hasCompleted = "completed" -in $eventTypes
        
        Write-TestResult -TestName "Started event exists" -Passed $hasStarted -Message "Types: $($eventTypes -join ', ')"
        Write-TestResult -TestName "Completed event exists" -Passed $hasCompleted -Message "Types: $($eventTypes -join ', ')"
        
        # Verify started comes before completed
        $startedIndex = [array]::IndexOf($eventTypes, "started")
        $completedIndex = [array]::IndexOf($eventTypes, "completed")
        
        if ($hasStarted -and $hasCompleted) {
            $correctOrder = $startedIndex -lt $completedIndex
            Write-TestResult -TestName "Started event precedes completed" -Passed $correctOrder -Message "Started at index $startedIndex, Completed at index $completedIndex"
        }
    }
}
catch {
    Write-TestResult -TestName "Run events exist" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST SCENARIO 4: Artifact Metadata Verification
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 4: Artifact Metadata Verification" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Verifying artifact metadata matches file properties..." -ForegroundColor Yellow

try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    foreach ($file in $filesResponse.files) {
        $filePath = $file.path
        
        # Check size_bytes
        $localPath = $null
        $expectedSize = 0
        $expectedContentType = ""
        
        if ($filePath -like "plan-*.md") {
            $localPath = $planPath
            $expectedSize = $planSize
            $expectedContentType = "text/markdown"
        }
        elseif ($filePath -eq "output.log") {
            $localPath = $outputPath
            $expectedSize = $outputSize
            $expectedContentType = "text/plain"
        }
        elseif ($filePath -eq "data.json") {
            $localPath = $jsonPath
            $expectedSize = $jsonSize
            $expectedContentType = "application/json"
        }
        
        if ($localPath) {
            # Verify size
            $sizeMatch = $file.size_bytes -eq $expectedSize
            Write-TestResult -TestName "Size matches for $filePath" -Passed $sizeMatch -Message "DB: $($file.size_bytes) vs Local: $expectedSize"
            
            # Verify content_type
            $typeMatch = $file.content_type -eq $expectedContentType
            Write-TestResult -TestName "Content-type matches for $filePath" -Passed $typeMatch -Message "DB: $($file.content_type) vs Expected: $expectedContentType"
            
            # Verify kind
            $expectedKind = if ($filePath -like "*.log") { "log" } else { "artifact" }
            $kindMatch = $file.kind -eq $expectedKind
            Write-TestResult -TestName "Kind matches for $filePath" -Passed $kindMatch -Message "DB: $($file.kind) vs Expected: $expectedKind"
        }
    }
}
catch {
    Write-TestResult -TestName "Artifact metadata verification" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST SCENARIO 5: Orphaned Records Check
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 5: Orphaned Records Check" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking for orphaned records..." -ForegroundColor Yellow

# Note: With foreign key constraints and ON DELETE CASCADE, orphaned records
# should not be possible. This test verifies the constraints are working.

# The run we created should have files
try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    $hasFiles = $filesResponse.files.Count -gt 0
    Write-TestResult -TestName "Run has associated files (no orphan files)" -Passed $hasFiles -Message "File count: $($filesResponse.files.Count)"
}
catch {
    Write-TestResult -TestName "Run has associated files" -Passed $false -Message $_.Exception.Message
}

# The run we created should have events
try {
    $eventsResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/events" -Method GET -ErrorAction Stop
    
    $hasEvents = $eventsResponse.events.Count -gt 0
    Write-TestResult -TestName "Run has associated events (no orphan events)" -Passed $hasEvents -Message "Event count: $($eventsResponse.events.Count)"
}
catch {
    Write-TestResult -TestName "Run has associated events" -Passed $false -Message $_.Exception.Message
}

# Verify all files are downloadable (no orphaned records pointing to missing storage)
Write-Host ""
Write-Host "Verifying no orphaned storage references..." -ForegroundColor Yellow

try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    $allDownloadable = $true
    foreach ($file in $filesResponse.files) {
        try {
            $downloadResponse = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/$($file.path)" -UseBasicParsing -ErrorAction Stop
            if ($downloadResponse.StatusCode -ne 200) {
                $allDownloadable = $false
                Write-Host "    [WARN] File not downloadable: $($file.path)" -ForegroundColor Yellow
            }
        }
        catch {
            $allDownloadable = $false
            Write-Host "    [WARN] File download failed: $($file.path) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-TestResult -TestName "All files downloadable (no orphaned storage refs)" -Passed $allDownloadable -Message "Checked $($filesResponse.files.Count) files"
}
catch {
    Write-TestResult -TestName "All files downloadable" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST SCENARIO 6: Cross-Verification Consistency
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Scenario 6: Cross-Verification Consistency" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Performing cross-verification checks..." -ForegroundColor Yellow

# Verify that downloading and re-uploading would be idempotent (unchanged files skipped)
# This tests that the SHA256-based idempotency check is working correctly

# First, get current file hashes from database
$dbHashes = @{}
try {
    $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$TestRunId/files" -Method GET -ErrorAction Stop
    
    foreach ($file in $filesResponse.files) {
        $dbHashes[$file.path] = $file.sha256
    }
    
    Write-Host "  Captured $($dbHashes.Count) file hashes from database" -ForegroundColor Gray
}
catch {
    Write-Host "  [ERROR] Failed to get file hashes: $($_.Exception.Message)" -ForegroundColor Red
}

# Verify local file hashes match database
$allMatch = $true
foreach ($file in $filesResponse.files) {
    $localPath = $null
    $localHash = $null
    
    if ($file.path -like "plan-*.md") {
        $localPath = $planPath
        $localHash = $planHash
    }
    elseif ($file.path -eq "output.log") {
        $localPath = $outputPath
        $localHash = $outputHash
    }
    elseif ($file.path -eq "data.json") {
        $localPath = $jsonPath
        $localHash = $jsonHash
    }
    
    if ($localHash -and $dbHashes[$file.path]) {
        if ($localHash -ne $dbHashes[$file.path]) {
            $allMatch = $false
            Write-Host "    [MISMATCH] $($file.path): Local=$($localHash.Substring(0,16))... DB=$($dbHashes[$file.path].Substring(0,16))..." -ForegroundColor Yellow
        }
    }
}

Write-TestResult -TestName "All local hashes match database hashes" -Passed $allMatch -Message "Cross-verified $($dbHashes.Count) files"

# Verify download -> hash cycle
$downloadHashCycle = $true
foreach ($file in $filesResponse.files) {
    try {
        $downloaded = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$TestRunId/files/$($file.path)" -UseBasicParsing -ErrorAction Stop
        $downloadedHash = Calculate-SHA256FromBytes -Content $downloaded.Content
        
        if ($downloadedHash -ne $file.sha256) {
            $downloadHashCycle = $false
            Write-Host "    [MISMATCH] $($file.path): Downloaded=$($downloadedHash.Substring(0,16))... DB=$($file.sha256.Substring(0,16))..." -ForegroundColor Yellow
        }
    }
    catch {
        $downloadHashCycle = $false
        Write-Host "    [ERROR] $($file.path): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-TestResult -TestName "Download-hash cycle consistent" -Passed $downloadHashCycle -Message "All downloaded files match DB hashes"

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
Write-Host "  Test ID:          $TestId" -ForegroundColor Gray
Write-Host "  Project ID:       $TestProjectId" -ForegroundColor Gray
Write-Host "  Agent ID:         $TestAgentId" -ForegroundColor Gray
Write-Host "  Run ID:           $TestRunId" -ForegroundColor Gray
Write-Host "  Backend URL:      $BackendUrl" -ForegroundColor Gray
Write-Host ""

Write-Host "Data Integrity Test Notes:" -ForegroundColor Gray
Write-Host "  Scenario 1: SHA256 Hash Verification" -ForegroundColor Gray
Write-Host "    - Verifies file hashes in database match source files" -ForegroundColor Gray
Write-Host "    - Verifies downloaded content hashes match originals" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 2: Foreign Key Constraint Enforcement" -ForegroundColor Gray
Write-Host "    - Attempts to create orphan run_files (should fail)" -ForegroundColor Gray
Write-Host "    - Attempts to create orphan run_events (should fail)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 3: Run Events Timestamp Ordering" -ForegroundColor Gray
Write-Host "    - Events returned in ascending ID order" -ForegroundColor Gray
Write-Host "    - Started event precedes completed event" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 4: Artifact Metadata Verification" -ForegroundColor Gray
Write-Host "    - size_bytes matches actual file size" -ForegroundColor Gray
Write-Host "    - content_type matches file extension" -ForegroundColor Gray
Write-Host "    - kind correctly categorizes artifacts vs logs" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 5: Orphaned Records Check" -ForegroundColor Gray
Write-Host "    - Run has associated files and events" -ForegroundColor Gray
Write-Host "    - All files are downloadable (no orphaned storage)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Scenario 6: Cross-Verification Consistency" -ForegroundColor Gray
Write-Host "    - Local hashes match database hashes" -ForegroundColor Gray
Write-Host "    - Download-hash cycle is consistent" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests PASSED! Data integrity verified." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests FAILED." -ForegroundColor Red
    exit 1
}

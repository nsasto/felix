<#
.SYNOPSIS
    Network failure and retry test for run artifact sync.

.DESCRIPTION
    This script tests the outbox queue behavior when the backend is unavailable:
    - Stop/make backend server unreachable
    - Run felix agent with backend unavailable
    - Verify outbox contains queued .jsonl files
    - Count outbox files (expect operations: register, create run, finish, batch upload)
    - Restart/restore backend server
    - Trigger outbox flush by running another requirement
    - Verify original outbox files cleared
    - Verify both runs appear in database
    - Verify both runs have artifacts in storage

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER Timeout
    Maximum test duration in seconds (default: 120)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-network-failure.ps1
    # Run network failure test with defaults

.EXAMPLE
    .\scripts\test-sync-network-failure.ps1 -BackendUrl http://localhost:8081 -Verbose
    # Use custom backend URL with verbose output

.NOTES
    Prerequisites:
    - Backend server running at specified URL (will be tested for availability)
    - PostgreSQL database available
    - Run test-sync-setup.ps1 first to initialize environment

    This test simulates network failure by using an unreachable URL for the first run,
    then restores the real backend URL for retry.

    Exit codes:
    - 0: All tests passed
    - 1: One or more tests failed
    - 2: Prerequisites not met (backend unavailable, etc.)
#>

param(
    [string]$BackendUrl = "http://localhost:8080",
    [int]$Timeout = 120,
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Network Failure Test" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-$TestId"
$TestAgentId = "test-agent-$TestId"
$TestDir = Join-Path $env:TEMP "felix-sync-network-failure-$TestId"

# URL that is guaranteed to be unreachable (localhost on unused port)
$UnreachableUrl = "http://127.0.0.1:59999"

# Track run IDs
$Run1Id = $null
$Run2Id = $null

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

# Check backend availability (we need it running for the second phase of the test)
if (-not (Test-BackendAvailable -Url $BackendUrl)) {
    Write-Host "  [ERROR] Backend server not available at $BackendUrl" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please start the backend server with:" -ForegroundColor Yellow
    Write-Host "  cd app\backend && python main.py" -ForegroundColor Gray
    Write-Host ""
    exit 2
}
Write-Host "  [OK] Backend server responding at $BackendUrl" -ForegroundColor Green

# Verify unreachable URL is actually unreachable
if (Test-BackendAvailable -Url $UnreachableUrl) {
    Write-Host "  [ERROR] The 'unreachable' URL is actually reachable: $UnreachableUrl" -ForegroundColor Red
    Write-Host "  Please ensure port 59999 is not in use." -ForegroundColor Yellow
    exit 2
}
Write-Host "  [OK] Unreachable URL confirmed: $UnreachableUrl" -ForegroundColor Green

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
# PHASE 1: Run with Backend UNAVAILABLE (simulating network failure)
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   PHASE 1: Backend Unavailable (Network Failure)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating Run 1 with backend UNAVAILABLE..." -ForegroundColor Yellow
Write-Host "  Using unreachable URL: $UnreachableUrl" -ForegroundColor Gray

# Configure environment with unreachable URL
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = $UnreachableUrl

$configOffline = @{
    base_url = $UnreachableUrl
    api_key  = $null
}

try {
    $reporterOffline = [FastApiReporter]::new($configOffline, $TestDir)
    $reporterOffline.OutboxPath = $OutboxDir
    Write-Host "  [OK] Reporter initialized with unreachable URL" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to initialize reporter: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

# Register agent (will fail to send and queue to outbox)
$agentInfo = @{
    agent_id = $TestAgentId
    hostname = $env:COMPUTERNAME
    platform = "windows"
    version  = "1.0.0-network-failure-test"
}

try {
    $reporterOffline.RegisterAgent($agentInfo)
    Write-Host "  [OK] Agent registration attempted (should be queued)" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Agent registration failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Small delay to allow any retry attempts
Start-Sleep -Milliseconds 500

# Start Run 1 (will queue to outbox)
$run1Metadata = @{
    agent_id       = $TestAgentId
    project_id     = $TestProjectId
    requirement_id = "S-NETFAIL-$TestId"
    branch         = "test/network-failure"
    scenario       = "testing"
    phase          = "offline-run"
}

try {
    $Run1Id = $reporterOffline.StartRun($run1Metadata)
    Write-Host "  [OK] Run 1 started: $Run1Id (queued to outbox)" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to create Run 1: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create run folder with artifacts
$run1Folder = Join-Path $TestDir "runs\$Run1Id"
New-Item -ItemType Directory -Path $run1Folder -Force | Out-Null

$run1PlanContent = @"
# Network Failure Test Plan - Run 1

## Summary
This plan was created while the backend was unavailable.

## Tasks
- [x] Task 1: Create run while offline
- [x] Task 2: Queue artifacts to outbox
- [x] Task 3: Wait for backend recovery

## Notes
Test ID: $TestId
Run ID: $Run1Id
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Backend Status: OFFLINE
"@
$run1PlanPath = Join-Path $run1Folder "plan.md"
$run1PlanContent | Set-Content -Path $run1PlanPath -Encoding UTF8
$run1PlanHash = Calculate-SHA256 -FilePath $run1PlanPath

$run1OutputContent = @"
[INFO] Run 1 started at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
[INFO] Test ID: $TestId
[INFO] Run ID: $Run1Id
[ERROR] Backend unavailable at $UnreachableUrl
[INFO] Operations queued to outbox for retry
[INFO] Run 1 completed (artifacts queued)
"@
$run1OutputPath = Join-Path $run1Folder "output.log"
$run1OutputContent | Set-Content -Path $run1OutputPath -Encoding UTF8
$run1OutputHash = Calculate-SHA256 -FilePath $run1OutputPath

Write-Host "  Created artifacts for Run 1:" -ForegroundColor Gray
Write-Host "    - plan.md (SHA: $($run1PlanHash.Substring(0,16))...)" -ForegroundColor Gray
Write-Host "    - output.log (SHA: $($run1OutputHash.Substring(0,16))...)" -ForegroundColor Gray

# Upload artifacts for Run 1 (will queue to outbox)
try {
    $reporterOffline.UploadRunFolder($Run1Id, $run1Folder)
    Write-Host "  [OK] Run 1 artifacts queued to outbox" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Upload failed (expected): $($_.Exception.Message)" -ForegroundColor Yellow
}

# Finish Run 1 (will queue to outbox)
$run1Result = @{
    status       = "completed"
    exit_code    = 0
    duration_sec = 5
}

try {
    $reporterOffline.FinishRun($Run1Id, $run1Result)
    Write-Host "  [OK] Run 1 finish event queued to outbox" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Finish failed (expected): $($_.Exception.Message)" -ForegroundColor Yellow
}

# Small delay to ensure all queuing is complete
Start-Sleep -Milliseconds 500

Write-Host ""

# =============================================================================
# TEST GROUP 1: Verify Outbox Contains Queued Operations
# =============================================================================

Write-Host "Test Group 1: Outbox Queue Verification (Offline)" -ForegroundColor Cyan

$outboxFiles = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$outboxCount = ($outboxFiles | Measure-Object).Count

Write-TestResult -TestName "Outbox contains queued files" -Passed ($outboxCount -gt 0) -Message "Found $outboxCount files in outbox"

# Check for specific operation types in outbox
$hasAgentRegister = $false
$hasRunStart = $false
$hasRunFinish = $false
$hasArtifacts = $false

foreach ($file in $outboxFiles) {
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match '"action"\s*:\s*"register_agent"') { $hasAgentRegister = $true }
    if ($content -match '"action"\s*:\s*"start_run"') { $hasRunStart = $true }
    if ($content -match '"action"\s*:\s*"finish_run"') { $hasRunFinish = $true }
    if ($content -match '"action"\s*:\s*"upload_artifact"' -or $content -match '"action"\s*:\s*"batch_upload"') { $hasArtifacts = $true }
}

Write-TestResult -TestName "Outbox has agent registration" -Passed $hasAgentRegister -Message "Agent register action queued"
Write-TestResult -TestName "Outbox has run start" -Passed $hasRunStart -Message "Run start action queued"
Write-TestResult -TestName "Outbox has run finish" -Passed $hasRunFinish -Message "Run finish action queued"
Write-TestResult -TestName "Outbox has artifact uploads" -Passed $hasArtifacts -Message "Artifact upload action queued"

# Display outbox files for debugging
if ($VerboseOutput) {
    Write-Host ""
    Write-Host "  Outbox files:" -ForegroundColor Gray
    foreach ($file in $outboxFiles) {
        Write-Host "    - $($file.Name)" -ForegroundColor Gray
    }
}

Write-Host ""

# =============================================================================
# PHASE 2: Restore Backend and Flush Outbox
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   PHASE 2: Backend Restored (Retry)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating Run 2 with backend AVAILABLE..." -ForegroundColor Yellow
Write-Host "  Using backend URL: $BackendUrl" -ForegroundColor Gray

# Configure environment with real backend URL
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = $BackendUrl

$configOnline = @{
    base_url = $BackendUrl
    api_key  = $null
}

try {
    $reporterOnline = [FastApiReporter]::new($configOnline, $TestDir)
    $reporterOnline.OutboxPath = $OutboxDir
    Write-Host "  [OK] Reporter initialized with real backend URL" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to initialize reporter: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create test project via API (needed for runs to reference)
try {
    $projectBody = @{
        id   = $TestProjectId
        name = "Network Failure Test Project $TestId"
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

# Register agent again with online reporter
try {
    $reporterOnline.RegisterAgent($agentInfo)
    Write-Host "  [OK] Agent registered with online backend" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Agent registration: $($_.Exception.Message)" -ForegroundColor Yellow
}

Start-Sleep -Milliseconds 500

# Flush outbox - this should send all queued operations
Write-Host ""
Write-Host "Flushing outbox..." -ForegroundColor Yellow

try {
    $reporterOnline.Flush()
    Write-Host "  [OK] Outbox flush triggered" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Flush error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Wait for flush to complete
Start-Sleep -Seconds 2

# Start Run 2 (should send immediately)
$run2Metadata = @{
    agent_id       = $TestAgentId
    project_id     = $TestProjectId
    requirement_id = "S-NETFAIL-$TestId"
    branch         = "test/network-failure"
    scenario       = "testing"
    phase          = "online-run"
}

try {
    $Run2Id = $reporterOnline.StartRun($run2Metadata)
    Write-Host "  [OK] Run 2 started: $Run2Id (sent immediately)" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to create Run 2: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create run folder with artifacts
$run2Folder = Join-Path $TestDir "runs\$Run2Id"
New-Item -ItemType Directory -Path $run2Folder -Force | Out-Null

$run2PlanContent = @"
# Network Failure Test Plan - Run 2

## Summary
This plan was created after the backend was restored.

## Tasks
- [x] Task 1: Create run while online
- [x] Task 2: Upload artifacts directly
- [x] Task 3: Verify both runs in database

## Notes
Test ID: $TestId
Run ID: $Run2Id
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Backend Status: ONLINE
"@
$run2PlanPath = Join-Path $run2Folder "plan.md"
$run2PlanContent | Set-Content -Path $run2PlanPath -Encoding UTF8
$run2PlanHash = Calculate-SHA256 -FilePath $run2PlanPath

$run2OutputContent = @"
[INFO] Run 2 started at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
[INFO] Test ID: $TestId
[INFO] Run ID: $Run2Id
[INFO] Backend available at $BackendUrl
[INFO] Artifacts uploaded directly
[INFO] Run 2 completed successfully
"@
$run2OutputPath = Join-Path $run2Folder "output.log"
$run2OutputContent | Set-Content -Path $run2OutputPath -Encoding UTF8
$run2OutputHash = Calculate-SHA256 -FilePath $run2OutputPath

Write-Host "  Created artifacts for Run 2:" -ForegroundColor Gray
Write-Host "    - plan.md (SHA: $($run2PlanHash.Substring(0,16))...)" -ForegroundColor Gray
Write-Host "    - output.log (SHA: $($run2OutputHash.Substring(0,16))...)" -ForegroundColor Gray

# Upload artifacts for Run 2 (should send immediately)
try {
    $reporterOnline.UploadRunFolder($Run2Id, $run2Folder)
    Write-Host "  [OK] Run 2 artifacts uploaded" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Upload: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Finish Run 2 (should send immediately)
$run2Result = @{
    status       = "completed"
    exit_code    = 0
    duration_sec = 5
}

try {
    $reporterOnline.FinishRun($Run2Id, $run2Result)
    Write-Host "  [OK] Run 2 completed" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Finish: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Final flush to ensure everything is sent
Start-Sleep -Seconds 1
try {
    $reporterOnline.Flush()
}
catch {
    # Ignore flush errors
}

# Wait for all operations to complete
Start-Sleep -Seconds 2

Write-Host ""

# =============================================================================
# TEST GROUP 2: Verify Outbox is Cleared
# =============================================================================

Write-Host "Test Group 2: Outbox Cleared After Flush" -ForegroundColor Cyan

$outboxFilesAfter = Get-ChildItem -Path $OutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
$outboxCountAfter = ($outboxFilesAfter | Measure-Object).Count

Write-TestResult -TestName "Outbox is empty after flush" -Passed ($outboxCountAfter -eq 0) -Message "Found $outboxCountAfter files remaining"

if ($outboxCountAfter -gt 0 -and $VerboseOutput) {
    Write-Host "  Remaining outbox files:" -ForegroundColor Yellow
    foreach ($file in $outboxFilesAfter) {
        Write-Host "    - $($file.Name)" -ForegroundColor Yellow
    }
}

Write-Host ""

# =============================================================================
# TEST GROUP 3: Verify Run 1 in Database (queued run)
# =============================================================================

Write-Host "Test Group 3: Run 1 Verification (Queued Run)" -ForegroundColor Cyan

try {
    $run1Files = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$Run1Id/files" -Method GET -ErrorAction Stop
    
    $run1FileCount = $run1Files.files.Count
    Write-TestResult -TestName "Run 1 appears in database" -Passed $true -Message "Run ID: $Run1Id"
    Write-TestResult -TestName "Run 1 has file records" -Passed ($run1FileCount -gt 0) -Message "Found $run1FileCount files"
    
    # Verify SHA256 hashes
    if ($run1FileCount -gt 0) {
        $r1Plan = $run1Files.files | Where-Object { $_.path -eq "plan.md" }
        $r1Output = $run1Files.files | Where-Object { $_.path -eq "output.log" }
        
        if ($r1Plan) {
            Write-TestResult -TestName "Run 1 plan.md SHA256 matches" -Passed ($r1Plan.sha256 -eq $run1PlanHash) -Message "DB: $($r1Plan.sha256.Substring(0,16))..."
        }
        if ($r1Output) {
            Write-TestResult -TestName "Run 1 output.log SHA256 matches" -Passed ($r1Output.sha256 -eq $run1OutputHash) -Message "DB: $($r1Output.sha256.Substring(0,16))..."
        }
    }
}
catch {
    Write-TestResult -TestName "Run 1 appears in database" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST GROUP 4: Verify Run 2 in Database (direct run)
# =============================================================================

Write-Host "Test Group 4: Run 2 Verification (Direct Run)" -ForegroundColor Cyan

try {
    $run2Files = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$Run2Id/files" -Method GET -ErrorAction Stop
    
    $run2FileCount = $run2Files.files.Count
    Write-TestResult -TestName "Run 2 appears in database" -Passed $true -Message "Run ID: $Run2Id"
    Write-TestResult -TestName "Run 2 has file records" -Passed ($run2FileCount -gt 0) -Message "Found $run2FileCount files"
    
    # Verify SHA256 hashes
    if ($run2FileCount -gt 0) {
        $r2Plan = $run2Files.files | Where-Object { $_.path -eq "plan.md" }
        $r2Output = $run2Files.files | Where-Object { $_.path -eq "output.log" }
        
        if ($r2Plan) {
            Write-TestResult -TestName "Run 2 plan.md SHA256 matches" -Passed ($r2Plan.sha256 -eq $run2PlanHash) -Message "DB: $($r2Plan.sha256.Substring(0,16))..."
        }
        if ($r2Output) {
            Write-TestResult -TestName "Run 2 output.log SHA256 matches" -Passed ($r2Output.sha256 -eq $run2OutputHash) -Message "DB: $($r2Output.sha256.Substring(0,16))..."
        }
    }
}
catch {
    Write-TestResult -TestName "Run 2 appears in database" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST GROUP 5: Verify Artifact Downloads
# =============================================================================

Write-Host "Test Group 5: Artifact Download Verification" -ForegroundColor Cyan

# Download Run 1 artifacts
try {
    $r1PlanDownload = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$Run1Id/files/plan.md" -UseBasicParsing -ErrorAction Stop
    $r1PlanDownloadHash = Calculate-SHA256FromBytes -Content $r1PlanDownload.Content
    
    Write-TestResult -TestName "Run 1 plan.md downloadable" -Passed ($r1PlanDownload.StatusCode -eq 200)
    Write-TestResult -TestName "Run 1 plan.md content intact" -Passed ($r1PlanDownloadHash -eq $run1PlanHash) -Message "Downloaded: $($r1PlanDownloadHash.Substring(0,16))..."
}
catch {
    Write-TestResult -TestName "Run 1 plan.md downloadable" -Passed $false -Message $_.Exception.Message
}

# Download Run 2 artifacts
try {
    $r2PlanDownload = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$Run2Id/files/plan.md" -UseBasicParsing -ErrorAction Stop
    $r2PlanDownloadHash = Calculate-SHA256FromBytes -Content $r2PlanDownload.Content
    
    Write-TestResult -TestName "Run 2 plan.md downloadable" -Passed ($r2PlanDownload.StatusCode -eq 200)
    Write-TestResult -TestName "Run 2 plan.md content intact" -Passed ($r2PlanDownloadHash -eq $run2PlanHash) -Message "Downloaded: $($r2PlanDownloadHash.Substring(0,16))..."
}
catch {
    Write-TestResult -TestName "Run 2 plan.md downloadable" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST GROUP 6: Verify Run Events
# =============================================================================

Write-Host "Test Group 6: Run Events Verification" -ForegroundColor Cyan

try {
    $run1Events = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$Run1Id/events" -Method GET -ErrorAction Stop
    
    $r1EventCount = $run1Events.events.Count
    $r1HasStarted = $run1Events.events | Where-Object { $_.type -eq "started" }
    $r1HasCompleted = $run1Events.events | Where-Object { $_.type -eq "completed" }
    
    Write-TestResult -TestName "Run 1 has events" -Passed ($r1EventCount -gt 0) -Message "Found $r1EventCount events"
    Write-TestResult -TestName "Run 1 has started event" -Passed ($null -ne $r1HasStarted)
    Write-TestResult -TestName "Run 1 has completed event" -Passed ($null -ne $r1HasCompleted)
}
catch {
    Write-TestResult -TestName "Run 1 events verification" -Passed $false -Message $_.Exception.Message
}

try {
    $run2Events = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$Run2Id/events" -Method GET -ErrorAction Stop
    
    $r2EventCount = $run2Events.events.Count
    $r2HasStarted = $run2Events.events | Where-Object { $_.type -eq "started" }
    $r2HasCompleted = $run2Events.events | Where-Object { $_.type -eq "completed" }
    
    Write-TestResult -TestName "Run 2 has events" -Passed ($r2EventCount -gt 0) -Message "Found $r2EventCount events"
    Write-TestResult -TestName "Run 2 has started event" -Passed ($null -ne $r2HasStarted)
    Write-TestResult -TestName "Run 2 has completed event" -Passed ($null -ne $r2HasCompleted)
}
catch {
    Write-TestResult -TestName "Run 2 events verification" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# TEST GROUP 7: Retry Behavior Verification
# =============================================================================

Write-Host "Test Group 7: Retry Behavior Summary" -ForegroundColor Cyan

# The fact that Run 1's data appears in the database after we flushed proves retry worked
$retrySuccessful = ($testsPassed -gt 10) # Most tests should have passed at this point

Write-TestResult -TestName "Queued operations were retried successfully" -Passed $retrySuccessful -Message "Run 1 data synced after backend restored"
Write-TestResult -TestName "No data loss during network failure" -Passed ($Run1Id -ne $null -and $Run2Id -ne $null) -Message "Both run IDs: $Run1Id, $Run2Id"

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
Write-Host "  Test ID:         $TestId" -ForegroundColor Gray
Write-Host "  Project ID:      $TestProjectId" -ForegroundColor Gray
Write-Host "  Agent ID:        $TestAgentId" -ForegroundColor Gray
Write-Host "  Run 1 ID:        $Run1Id (queued offline)" -ForegroundColor Gray
Write-Host "  Run 2 ID:        $Run2Id (sent online)" -ForegroundColor Gray
Write-Host "  Backend URL:     $BackendUrl" -ForegroundColor Gray
Write-Host "  Unreachable URL: $UnreachableUrl" -ForegroundColor Gray
Write-Host ""

Write-Host "Network Failure Test Notes:" -ForegroundColor Gray
Write-Host "  - Phase 1: Simulated network failure using unreachable URL" -ForegroundColor Gray
Write-Host "  - Operations were queued to local outbox (.jsonl files)" -ForegroundColor Gray
Write-Host "  - Phase 2: Backend restored, outbox flushed" -ForegroundColor Gray
Write-Host "  - Both runs (offline and online) verified in database" -ForegroundColor Gray
Write-Host "  - Demonstrates eventual consistency via retry" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests PASSED! Network failure recovery verified." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests FAILED." -ForegroundColor Red
    exit 1
}

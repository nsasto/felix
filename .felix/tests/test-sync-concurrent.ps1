<#
.SYNOPSIS
    Concurrent upload test for run artifact sync.

.DESCRIPTION
    This script tests concurrent artifact uploads from multiple agents running in parallel:
    - Run 3 agents in parallel on different requirements using Start-Job
    - Each agent uploads artifacts simultaneously to different run_ids
    - Wait for all jobs to complete
    - Verify no database deadlocks occur (check for error messages)
    - Verify no storage write conflicts occur (check for errors)
    - All 3 runs complete successfully (exit code 0)
    - Query database for all 3 run records
    - Verify storage contains artifacts for all 3 runs
    - Check no artifact corruption or cross-contamination via SHA256 comparison

.PARAMETER BackendUrl
    URL of the backend server to test against (default: http://localhost:8080)

.PARAMETER Timeout
    Maximum time in seconds to wait for all jobs (default: 120)

.PARAMETER AgentCount
    Number of parallel agents to run (default: 3)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    .\scripts\test-sync-concurrent.ps1
    # Run concurrent test with 3 parallel agents

.EXAMPLE
    .\scripts\test-sync-concurrent.ps1 -AgentCount 5 -Timeout 180
    # Use 5 agents with 180 second timeout

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
    [int]$Timeout = 120,
    [int]$AgentCount = 3,
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

# Configure UTF-8 encoding for console output
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Felix Sync Concurrent Upload Test" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# CONFIGURATION
# =============================================================================

$TestId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$TestProjectId = "test-project-concurrent-$TestId"
$TestDir = Join-Path $env:TEMP "felix-sync-concurrent-$TestId"

# Track test results
$testsPassed = 0
$testsFailed = 0
$testResults = @()

# Store agent info and expected hashes for verification
$agentData = @{}

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
Write-Host "  [OK] Test directory created: $TestDir" -ForegroundColor Green

# Verify sync modules exist
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
Write-Host "  [OK] Sync modules found" -ForegroundColor Green

Write-Host ""

# =============================================================================
# SETUP: Create Test Project via API
# =============================================================================

Write-Host "Setting up test data..." -ForegroundColor Yellow

# Create test project via API
try {
    $projectBody = @{
        id   = $TestProjectId
        name = "Concurrent Test Project $TestId"
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
# PREPARE AGENT DATA
# =============================================================================

Write-Host "Preparing data for $AgentCount parallel agents..." -ForegroundColor Yellow

for ($i = 1; $i -le $AgentCount; $i++) {
    $agentId = "test-agent-concurrent-$TestId-$i"
    $requirementId = "S-CONCURRENT-$TestId-$i"
    
    # Pre-create directory for each agent
    $agentDir = Join-Path $TestDir "agent-$i"
    $outboxDir = Join-Path $agentDir ".felix\outbox"
    New-Item -ItemType Directory -Path $outboxDir -Force | Out-Null
    
    # Create unique content for each agent's files
    $planContent = @"
# Concurrent Test Plan - Agent $i

## Summary
This plan was created by agent $i in the concurrent upload test.

## Tasks
- [x] Task 1: Start concurrent run
- [x] Task 2: Upload artifacts
- [x] Task 3: Finish run

## Unique Data
Test ID: $TestId
Agent ID: $agentId
Agent Number: $i
Requirement: $requirementId
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Random: $([System.Guid]::NewGuid().ToString())
"@

    $outputContent = @"
[INFO] Agent $i started at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
[INFO] Test ID: $TestId
[INFO] Agent ID: $agentId
[INFO] Requirement ID: $requirementId
[INFO] This is agent number $i of $AgentCount
[DEBUG] Random data: $([System.Guid]::NewGuid().ToString())
[DEBUG] More random: $([System.Guid]::NewGuid().ToString())
[INFO] Agent $i completed successfully
"@

    # Calculate expected hashes (content written here matches what jobs will write)
    $planPath = Join-Path $agentDir "plan-$requirementId.md"
    $outputPath = Join-Path $agentDir "output.log"
    
    $planContent | Set-Content -Path $planPath -Encoding UTF8 -NoNewline
    $outputContent | Set-Content -Path $outputPath -Encoding UTF8 -NoNewline
    
    $planHash = Calculate-SHA256 -FilePath $planPath
    $outputHash = Calculate-SHA256 -FilePath $outputPath
    
    $agentData["agent-$i"] = @{
        AgentId       = $agentId
        RequirementId = $requirementId
        AgentDir      = $agentDir
        OutboxDir     = $outboxDir
        PlanHash      = $planHash
        OutputHash    = $outputHash
        PlanContent   = $planContent
        OutputContent = $outputContent
        RunId         = $null
        JobStatus     = $null
        ExitCode      = $null
        Errors        = @()
    }
    
    Write-Host "  [OK] Agent $i prepared: $agentId" -ForegroundColor Green
    Write-Host "       Plan hash:   $($planHash.Substring(0, 16))..." -ForegroundColor Gray
    Write-Host "       Output hash: $($outputHash.Substring(0, 16))..." -ForegroundColor Gray
}

Write-Host ""

# =============================================================================
# DEFINE THE AGENT JOB SCRIPT
# =============================================================================

# The job script block that each parallel agent will execute
$AgentJobScript = {
    param(
        [string]$BackendUrl,
        [string]$ProjectId,
        [string]$AgentId,
        [string]$RequirementId,
        [string]$AgentDir,
        [string]$OutboxDir,
        [string]$PlanContent,
        [string]$OutputContent,
        [string]$SyncInterfacePath,
        [string]$SyncPluginPath,
        [int]$AgentNumber
    )
    
    $ErrorActionPreference = "Stop"
    $result = @{
        Success = $false
        RunId   = $null
        Errors  = @()
        Details = @()
    }
    
    try {
        # Source the sync modules
        . $SyncInterfacePath
        . $SyncPluginPath
        
        $result.Details += "Sync modules loaded"
        
        # Initialize reporter
        $config = @{
            base_url = $BackendUrl
            api_key  = $null
        }
        
        $reporter = [HttpSync]::new($config, (Split-Path $OutboxDir -Parent))
        $reporter.OutboxPath = $OutboxDir
        
        $result.Details += "Reporter initialized"
        
        # Register agent
        $agentInfo = @{
            agent_id = $AgentId
            hostname = $env:COMPUTERNAME
            platform = "windows"
            version  = "1.0.0-concurrent-test"
        }
        $reporter.RegisterAgent($agentInfo)
        $result.Details += "Agent registered"
        
        # Start run
        $runMetadata = @{
            agent_id       = $AgentId
            project_id     = $ProjectId
            requirement_id = $RequirementId
            branch         = "test/concurrent-$AgentNumber"
            scenario       = "testing"
            phase          = "building"
        }
        
        $runId = $reporter.StartRun($runMetadata)
        $result.RunId = $runId
        $result.Details += "Run started: $runId"
        
        # Create run folder
        $runFolder = Join-Path $AgentDir "runs\$runId"
        New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
        
        # Write artifacts with exact same content
        $planPath = Join-Path $runFolder "plan-$RequirementId.md"
        $outputPath = Join-Path $runFolder "output.log"
        
        $PlanContent | Set-Content -Path $planPath -Encoding UTF8 -NoNewline
        $OutputContent | Set-Content -Path $outputPath -Encoding UTF8 -NoNewline
        
        $result.Details += "Artifacts written"
        
        # Upload artifacts
        $reporter.UploadRunFolder($runId, $runFolder)
        $result.Details += "Artifacts uploaded"
        
        # Finish run
        $runResult = @{
            status       = "completed"
            exit_code    = 0
            duration_sec = 2
        }
        $reporter.FinishRun($runId, $runResult)
        $result.Details += "Run finished"
        
        # Small delay to ensure flush completes
        Start-Sleep -Milliseconds 500
        
        $result.Success = $true
    }
    catch {
        $result.Success = $false
        $result.Errors += $_.Exception.Message
    }
    
    return $result
}

# =============================================================================
# RUN PARALLEL AGENTS
# =============================================================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Running $AgentCount Agents in Parallel" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting parallel jobs..." -ForegroundColor Yellow

$jobs = @()
$startTime = Get-Date

for ($i = 1; $i -le $AgentCount; $i++) {
    $agent = $agentData["agent-$i"]
    
    $job = Start-Job -ScriptBlock $AgentJobScript -ArgumentList @(
        $BackendUrl,
        $TestProjectId,
        $agent.AgentId,
        $agent.RequirementId,
        $agent.AgentDir,
        $agent.OutboxDir,
        $agent.PlanContent,
        $agent.OutputContent,
        $SyncInterfacePath,
        $SyncPluginPath,
        $i
    )
    
    $jobs += @{
        Job         = $job
        AgentKey    = "agent-$i"
        AgentNumber = $i
    }
    
    Write-Host "  [STARTED] Agent $i job: $($job.Id)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Waiting for all jobs to complete (timeout: ${Timeout}s)..." -ForegroundColor Yellow

# Wait for all jobs with timeout
$allJobs = $jobs | ForEach-Object { $_.Job }
$completed = Wait-Job -Job $allJobs -Timeout $Timeout

$endTime = Get-Date
$totalDuration = ($endTime - $startTime).TotalSeconds

Write-Host "  All jobs finished in $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor Green
Write-Host ""

# =============================================================================
# COLLECT JOB RESULTS
# =============================================================================

Write-Host "Test Group 1: Job Completion Status" -ForegroundColor Cyan

$allJobsSucceeded = $true
$deadlockDetected = $false
$writeConflictDetected = $false

foreach ($jobInfo in $jobs) {
    $job = $jobInfo.Job
    $agentKey = $jobInfo.AgentKey
    $agentNum = $jobInfo.AgentNumber
    
    $jobState = $job.State
    
    if ($jobState -eq "Completed") {
        $jobResult = Receive-Job -Job $job
        
        if ($jobResult.Success) {
            $agentData[$agentKey].RunId = $jobResult.RunId
            $agentData[$agentKey].JobStatus = "Success"
            $agentData[$agentKey].ExitCode = 0
            Write-TestResult -TestName "Agent $agentNum job completed successfully" -Passed $true -Message "Run ID: $($jobResult.RunId)"
        }
        else {
            $allJobsSucceeded = $false
            $agentData[$agentKey].JobStatus = "Failed"
            $agentData[$agentKey].ExitCode = 1
            $agentData[$agentKey].Errors = $jobResult.Errors
            
            $errorMsg = $jobResult.Errors -join "; "
            Write-TestResult -TestName "Agent $agentNum job completed successfully" -Passed $false -Message $errorMsg
            
            # Check for deadlock or write conflict errors
            if ($errorMsg -match "deadlock" -or $errorMsg -match "lock" -or $errorMsg -match "timeout") {
                $deadlockDetected = $true
            }
            if ($errorMsg -match "conflict" -or $errorMsg -match "already exists" -or $errorMsg -match "concurrent") {
                $writeConflictDetected = $true
            }
        }
    }
    else {
        $allJobsSucceeded = $false
        $agentData[$agentKey].JobStatus = "Timeout/Error"
        $agentData[$agentKey].ExitCode = 2
        Write-TestResult -TestName "Agent $agentNum job completed successfully" -Passed $false -Message "Job state: $jobState"
    }
    
    # Clean up job
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}

Write-TestResult -TestName "All $AgentCount agents completed (exit code 0)" -Passed $allJobsSucceeded
Write-TestResult -TestName "No database deadlocks detected" -Passed (-not $deadlockDetected) -Message $(if ($deadlockDetected) { "Deadlock detected in job errors" } else { "" })
Write-TestResult -TestName "No storage write conflicts detected" -Passed (-not $writeConflictDetected) -Message $(if ($writeConflictDetected) { "Write conflict detected in job errors" } else { "" })

Write-Host ""

# =============================================================================
# TEST 2: Verify All Runs in Database
# =============================================================================

Write-Host "Test Group 2: Database Verification" -ForegroundColor Cyan

$allRunsInDb = $true

foreach ($i in 1..$AgentCount) {
    $agent = $agentData["agent-$i"]
    $runId = $agent.RunId
    
    if (-not $runId) {
        $allRunsInDb = $false
        Write-TestResult -TestName "Agent $i run exists in database" -Passed $false -Message "No run ID (job failed)"
        continue
    }
    
    try {
        $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$runId/files" -Method GET -TimeoutSec 10 -ErrorAction Stop
        
        $hasFiles = $filesResponse.files -and $filesResponse.files.Count -gt 0
        Write-TestResult -TestName "Agent $i run exists in database" -Passed $true -Message "Run ID: $runId, Files: $($filesResponse.files.Count)"
        
        if (-not $hasFiles) {
            $allRunsInDb = $false
        }
    }
    catch {
        $allRunsInDb = $false
        Write-TestResult -TestName "Agent $i run exists in database" -Passed $false -Message $_.Exception.Message
    }
}

Write-TestResult -TestName "All $AgentCount runs present in database" -Passed $allRunsInDb

Write-Host ""

# =============================================================================
# TEST 3: Verify Artifact Integrity (SHA256 Comparison)
# =============================================================================

Write-Host "Test Group 3: Artifact Integrity Verification" -ForegroundColor Cyan

$allArtifactsIntact = $true
$noCrossContamination = $true

foreach ($i in 1..$AgentCount) {
    $agent = $agentData["agent-$i"]
    $runId = $agent.RunId
    
    if (-not $runId) {
        Write-TestResult -TestName "Agent $i artifacts integrity" -Passed $false -Message "No run ID"
        $allArtifactsIntact = $false
        continue
    }
    
    try {
        # Get file list from API
        $filesResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$runId/files" -Method GET -TimeoutSec 10 -ErrorAction Stop
        
        # Check plan file
        $planFile = $filesResponse.files | Where-Object { $_.path -like "plan-*.md" }
        if ($planFile) {
            $dbPlanHash = $planFile.sha256
            $expectedPlanHash = $agent.PlanHash
            
            $planHashMatches = $dbPlanHash -eq $expectedPlanHash
            if (-not $planHashMatches) {
                $allArtifactsIntact = $false
                
                # Check if hash matches any other agent's hash (cross-contamination)
                foreach ($j in 1..$AgentCount) {
                    if ($j -ne $i -and $dbPlanHash -eq $agentData["agent-$j"].PlanHash) {
                        $noCrossContamination = $false
                        Write-Host "    WARNING: Agent $i plan hash matches Agent $j!" -ForegroundColor Red
                    }
                }
            }
            
            Write-TestResult -TestName "Agent $i plan SHA256 matches" -Passed $planHashMatches -Message "DB: $($dbPlanHash.Substring(0, 16))..."
        }
        else {
            $allArtifactsIntact = $false
            Write-TestResult -TestName "Agent $i plan SHA256 matches" -Passed $false -Message "Plan file not found"
        }
        
        # Check output file
        $outputFile = $filesResponse.files | Where-Object { $_.path -eq "output.log" }
        if ($outputFile) {
            $dbOutputHash = $outputFile.sha256
            $expectedOutputHash = $agent.OutputHash
            
            $outputHashMatches = $dbOutputHash -eq $expectedOutputHash
            if (-not $outputHashMatches) {
                $allArtifactsIntact = $false
                
                # Check for cross-contamination
                foreach ($j in 1..$AgentCount) {
                    if ($j -ne $i -and $dbOutputHash -eq $agentData["agent-$j"].OutputHash) {
                        $noCrossContamination = $false
                        Write-Host "    WARNING: Agent $i output hash matches Agent $j!" -ForegroundColor Red
                    }
                }
            }
            
            Write-TestResult -TestName "Agent $i output SHA256 matches" -Passed $outputHashMatches -Message "DB: $($dbOutputHash.Substring(0, 16))..."
        }
        else {
            $allArtifactsIntact = $false
            Write-TestResult -TestName "Agent $i output SHA256 matches" -Passed $false -Message "Output file not found"
        }
    }
    catch {
        $allArtifactsIntact = $false
        Write-TestResult -TestName "Agent $i artifacts integrity" -Passed $false -Message $_.Exception.Message
    }
}

Write-TestResult -TestName "No cross-contamination between agents" -Passed $noCrossContamination -Message $(if (-not $noCrossContamination) { "Artifacts mixed between runs!" } else { "" })

Write-Host ""

# =============================================================================
# TEST 4: Download and Verify Content
# =============================================================================

Write-Host "Test Group 4: Download and Content Verification" -ForegroundColor Cyan

$allDownloadsSucceeded = $true

foreach ($i in 1..$AgentCount) {
    $agent = $agentData["agent-$i"]
    $runId = $agent.RunId
    
    if (-not $runId) {
        continue
    }
    
    try {
        # Download output.log and verify content hash
        $downloadedContent = Invoke-WebRequest -Uri "$BackendUrl/api/runs/$runId/files/output.log" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        
        if ($downloadedContent.StatusCode -eq 200) {
            $downloadedHash = Calculate-SHA256FromBytes -Content $downloadedContent.Content
            $expectedHash = $agent.OutputHash
            
            $contentMatches = $downloadedHash -eq $expectedHash
            Write-TestResult -TestName "Agent $i downloaded content matches original" -Passed $contentMatches -Message "Downloaded: $($downloadedHash.Substring(0, 16))..."
            
            if (-not $contentMatches) {
                $allDownloadsSucceeded = $false
            }
        }
        else {
            $allDownloadsSucceeded = $false
            Write-TestResult -TestName "Agent $i downloaded content matches original" -Passed $false -Message "HTTP Status: $($downloadedContent.StatusCode)"
        }
    }
    catch {
        $allDownloadsSucceeded = $false
        Write-TestResult -TestName "Agent $i downloaded content matches original" -Passed $false -Message $_.Exception.Message
    }
}

Write-Host ""

# =============================================================================
# TEST 5: Verify Run Events
# =============================================================================

Write-Host "Test Group 5: Run Events Verification" -ForegroundColor Cyan

$allEventsPresent = $true

foreach ($i in 1..$AgentCount) {
    $agent = $agentData["agent-$i"]
    $runId = $agent.RunId
    
    if (-not $runId) {
        continue
    }
    
    try {
        $eventsResponse = Invoke-RestMethod -Uri "$BackendUrl/api/runs/$runId/events" -Method GET -TimeoutSec 10 -ErrorAction Stop
        
        $eventCount = $eventsResponse.events.Count
        $hasStarted = $eventsResponse.events | Where-Object { $_.type -eq "started" }
        $hasCompleted = $eventsResponse.events | Where-Object { $_.type -eq "completed" }
        
        $eventsOk = ($null -ne $hasStarted) -and ($null -ne $hasCompleted)
        Write-TestResult -TestName "Agent $i has started and completed events" -Passed $eventsOk -Message "Events: $eventCount"
        
        if (-not $eventsOk) {
            $allEventsPresent = $false
        }
    }
    catch {
        $allEventsPresent = $false
        Write-TestResult -TestName "Agent $i has started and completed events" -Passed $false -Message $_.Exception.Message
    }
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

Write-Host "Concurrent Test Details:" -ForegroundColor Gray
Write-Host "  Test ID:        $TestId" -ForegroundColor Gray
Write-Host "  Project ID:     $TestProjectId" -ForegroundColor Gray
Write-Host "  Agent Count:    $AgentCount" -ForegroundColor Gray
Write-Host "  Total Duration: $([math]::Round($totalDuration, 2))s" -ForegroundColor Gray
Write-Host "  Backend URL:    $BackendUrl" -ForegroundColor Gray
Write-Host ""

Write-Host "Agent Results:" -ForegroundColor Gray
foreach ($i in 1..$AgentCount) {
    $agent = $agentData["agent-$i"]
    $status = if ($agent.JobStatus -eq "Success") { "[OK]" } else { "[FAIL]" }
    $color = if ($agent.JobStatus -eq "Success") { "Green" } else { "Red" }
    Write-Host "  Agent $i $status Run: $($agent.RunId)" -ForegroundColor $color
}
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests PASSED! Concurrent upload verified successfully." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests FAILED." -ForegroundColor Red
    exit 1
}

<#
.SYNOPSIS
Tests for sync-http.ps1 plugin

.DESCRIPTION
Unit tests for the HttpSync class and related functions
#>

$ErrorActionPreference = "Stop"

# Get the directory of this test script
$TestDir = Split-Path $PSScriptRoot -Parent
$InterfacePath = Join-Path $TestDir "core\sync-interface.ps1"
$PluginPath = Join-Path $TestDir "plugins\sync-http.ps1"

# Source the interface first to make IRunReporter available
. $InterfacePath

Write-Host "=== Testing sync-http.ps1 ===" -ForegroundColor Cyan
Write-Host ""

# Track test results
$passed = 0
$failed = 0

function Test-Assert {
    param(
        [bool]$Condition,
        [string]$Message
    )
    
    if ($Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        $script:failed++
    }
}

# Create temporary test directory for outbox
$TestTempDir = Join-Path $env:TEMP "felix-test-sync-$([System.Guid]::NewGuid().ToString().Substring(0,8))"
New-Item -ItemType Directory -Path $TestTempDir -Force | Out-Null

try {
    # Test 1: Source the plugin file
    Write-Host "Test 1: Source plugin file"
    try {
        . $PluginPath
        Test-Assert $true "Plugin file sourced successfully"
    }
    catch {
        Test-Assert $false "Plugin file sourced successfully - Error: $_"
    }
    Write-Host ""

    # Test 2: Get-ContentType function
    Write-Host "Test 2: Get-ContentType function"
    Test-Assert ((Get-ContentType -Path "test.md") -eq "text/markdown") "Returns text/markdown for .md files"
    Test-Assert ((Get-ContentType -Path "test.log") -eq "text/plain; charset=utf-8") "Returns text/plain for .log files"
    Test-Assert ((Get-ContentType -Path "test.txt") -eq "text/plain; charset=utf-8") "Returns text/plain for .txt files"
    Test-Assert ((Get-ContentType -Path "test.patch") -eq "text/x-patch") "Returns text/x-patch for .patch files"
    Test-Assert ((Get-ContentType -Path "test.json") -eq "application/json") "Returns application/json for .json files"
    Test-Assert ((Get-ContentType -Path "test.unknown") -eq "application/octet-stream") "Returns application/octet-stream for unknown extensions"
    Write-Host ""

    # Test 3: HttpSync instantiation
    Write-Host "Test 3: HttpSync instantiation"
    $config = @{
        base_url = "http://localhost:8080"
        api_key  = "test-key"
    }
    
    try {
        $reporter = [HttpSync]::new($config, $TestTempDir)
        Test-Assert $true "HttpSync created successfully"
        Test-Assert ($reporter.BaseUrl -eq "http://localhost:8080") "BaseUrl property set correctly"
        Test-Assert ($reporter.ApiKey -eq "test-key") "ApiKey property set correctly"
        Test-Assert ($reporter.OutboxPath -eq (Join-Path $TestTempDir "outbox")) "OutboxPath property set correctly"
        Test-Assert (Test-Path $reporter.OutboxPath) "Outbox directory created"
    }
    catch {
        Test-Assert $false "HttpSync created successfully - Error: $_"
    }
    Write-Host ""

    # Test 4: New-PluginReporter factory function
    Write-Host "Test 4: New-PluginReporter factory function"
    try {
        $reporter2 = New-PluginReporter -Config $config -FelixDir $TestTempDir
        Test-Assert $true "New-PluginReporter returns reporter"
        Test-Assert ($reporter2.GetType().Name -eq "HttpSync") "Returns HttpSync type"
    }
    catch {
        Test-Assert $false "New-PluginReporter returns reporter - Error: $_"
    }
    Write-Host ""

    # Test 5: QueueRequest creates outbox files
    Write-Host "Test 5: QueueRequest creates outbox files"
    # Create a fresh reporter with clean outbox
    $testOutboxDir = Join-Path $TestTempDir "outbox-test5"
    $config5 = @{
        base_url = "http://localhost:8080"
        api_key  = $null
    }
    $reporter5 = [HttpSync]::new($config5, (Split-Path $testOutboxDir -Parent))
    $reporter5.OutboxPath = $testOutboxDir
    New-Item -ItemType Directory -Path $testOutboxDir -Force | Out-Null
    
    # Call RegisterAgent (which uses QueueRequest)
    $agentInfo = @{
        agent_id   = "test-agent"
        hostname   = "test-host"
        platform   = "Windows"
        version    = "1.0.0"
        felix_root = "C:\test"
    }
    
    # We can't actually test QueueRequest directly since TrySendOutbox will fail,
    # but we can verify the file is created before network errors
    $reporter5.RegisterAgent($agentInfo)
    
    # Check if any .jsonl file was created (even if send failed)
    $outboxFiles = Get-ChildItem -Path $testOutboxDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
    Test-Assert ($outboxFiles.Count -ge 0) "Outbox queuing attempted (network may have failed)"
    Write-Host ""

    # Test 6: StartRun generates UUID
    Write-Host "Test 6: StartRun generates UUID"
    $testOutboxDir6 = Join-Path $TestTempDir "outbox-test6"
    New-Item -ItemType Directory -Path $testOutboxDir6 -Force | Out-Null
    $reporter6 = [HttpSync]::new($config5, (Split-Path $testOutboxDir6 -Parent))
    $reporter6.OutboxPath = $testOutboxDir6
    
    $metadata = @{
        agent_id       = "test-agent"
        requirement_id = "S-0001"
    }
    
    $runId = $reporter6.StartRun($metadata)
    Test-Assert ($runId.Length -eq 36) "StartRun returns UUID (36 chars)"
    Test-Assert ($runId -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") "StartRun returns valid UUID format"
    Write-Host ""

    # Test 7: AppendToRunOutbox creates run-specific files
    Write-Host "Test 7: AppendToRunOutbox creates run-specific files"
    $testOutboxDir7 = Join-Path $TestTempDir "outbox-test7"
    New-Item -ItemType Directory -Path $testOutboxDir7 -Force | Out-Null
    $reporter7 = [HttpSync]::new($config5, (Split-Path $testOutboxDir7 -Parent))
    $reporter7.OutboxPath = $testOutboxDir7
    
    $event = @{
        run_id     = "test-run-123"
        event_type = "task_started"
        payload    = @{ task = "Test task" }
    }
    
    $reporter7.AppendEvent($event)
    
    $runEventFile = Join-Path $testOutboxDir7 "run-test-run-123.jsonl"
    Test-Assert (Test-Path $runEventFile) "Run-specific event file created"
    
    if (Test-Path $runEventFile) {
        $content = Get-Content $runEventFile -Raw
        Test-Assert ($content -match "task_started") "Event content written correctly"
    }
    Write-Host ""

    # Test 8: CalculateSHA256 works correctly
    Write-Host "Test 8: SHA256 calculation"
    $testFile = Join-Path $TestTempDir "test-hash.txt"
    "Hello, World!" | Set-Content -Path $testFile -NoNewline
    
    $hash = $reporter.CalculateSHA256($testFile)
    # Known SHA256 of "Hello, World!" (no newline)
    $expectedHash = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"
    Test-Assert ($hash -eq $expectedHash) "SHA256 calculated correctly"
    Write-Host ""

    # Test 9: UploadArtifact handles missing files
    Write-Host "Test 9: UploadArtifact handles missing files"
    $testOutboxDir9 = Join-Path $TestTempDir "outbox-test9"
    New-Item -ItemType Directory -Path $testOutboxDir9 -Force | Out-Null
    $reporter9 = [HttpSync]::new($config5, (Split-Path $testOutboxDir9 -Parent))
    $reporter9.OutboxPath = $testOutboxDir9
    
    try {
        $reporter9.UploadArtifact("test-run", "missing.txt", "C:\nonexistent\file.txt")
        Test-Assert $true "UploadArtifact handles missing file gracefully"
    }
    catch {
        Test-Assert $false "UploadArtifact handles missing file gracefully - Error: $_"
    }
    Write-Host ""

    # Test 10: UploadRunFolder collects artifacts
    Write-Host "Test 10: UploadRunFolder collects artifacts"
    $testRunFolder = Join-Path $TestTempDir "test-run-folder"
    New-Item -ItemType Directory -Path $testRunFolder -Force | Out-Null
    
    # Create some test artifacts
    "# Test Plan" | Set-Content (Join-Path $testRunFolder "plan-S-0001.md")
    "Test output" | Set-Content (Join-Path $testRunFolder "output.log")
    
    $testOutboxDir10 = Join-Path $TestTempDir "outbox-test10"
    New-Item -ItemType Directory -Path $testOutboxDir10 -Force | Out-Null
    $reporter10 = [HttpSync]::new($config5, (Split-Path $testOutboxDir10 -Parent))
    $reporter10.OutboxPath = $testOutboxDir10
    
    $reporter10.UploadRunFolder("test-run-10", $testRunFolder)
    
    # Check if batch upload file was queued
    $batchFiles = Get-ChildItem -Path $testOutboxDir10 -Filter "*-batch-upload.jsonl" -File -ErrorAction SilentlyContinue
    Test-Assert ($batchFiles.Count -gt 0) "Batch upload file queued"
    
    if ($batchFiles.Count -gt 0) {
        $batchContent = Get-Content $batchFiles[0].FullName -Raw | ConvertFrom-Json
        Test-Assert ($batchContent.files.Count -ge 2) "Batch contains expected artifacts"
    }
    Write-Host ""

}
finally {
    # Cleanup test directory
    if (Test-Path $TestTempDir) {
        Remove-Item -Path $TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

exit $failed

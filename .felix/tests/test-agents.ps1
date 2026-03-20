# Test All Agent Providers
# Runs tests for all configured agent CLIs (Droid, Claude, Codex, Gemini, Copilot)

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "Felix Agent Provider Test Suite" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Testing all agent providers for CLI availability and basic execution" -ForegroundColor Gray
Write-Host ""

$scriptDir = $PSScriptRoot
$results = @()

# Test each agent provider
$agents = @(
    @{ Name = "Droid";  Script = "test-agent-droid.ps1" }
    @{ Name = "Claude"; Script = "test-agent-claude.ps1" }
    @{ Name = "Codex";  Script = "test-agent-codex.ps1" }
    @{ Name = "Gemini"; Script = "test-agent-gemini.ps1" }
    @{ Name = "Copilot"; Script = "test-agent-copilot.ps1" }
)

foreach ($agent in $agents) {
    $scriptPath = Join-Path $scriptDir $agent.Script
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "ERROR: Test script not found: $($agent.Script)" -ForegroundColor Red
        $results += @{
            Name = $agent.Name
            Status = "ERROR"
            ExitCode = -1
            Duration = 0
        }
        continue
    }
    
    Write-Host "[$($agent.Name)]" -ForegroundColor Cyan
    Write-Host ("=" * ($agent.Name.Length + 2)) -ForegroundColor Cyan
    
    $startTime = Get-Date
    
    $verboseFlag = if ($Verbose) { "-Verbose" } else { "" }
    & $scriptPath $verboseFlag
    $exitCode = $LASTEXITCODE
    
    $duration = ((Get-Date) - $startTime).TotalSeconds
    
    $status = switch ($exitCode) {
        0 { "PASS" }
        1 { "FAIL" }
        2 { "SKIP" }
        default { "ERROR" }
    }
    
    $results += @{
        Name = $agent.Name
        Status = $status
        ExitCode = $exitCode
        Duration = $duration
    }
    
    Write-Host ""
}

# Summary table
Write-Host ""
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "============" -ForegroundColor Cyan
Write-Host ""

$maxNameLength = ($results | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
$headerFormat = "{0,-$($maxNameLength + 2)} {1,-8} {2,-10} {3}"
$rowFormat = "{0,-$($maxNameLength + 2)} {1,-8} {2,-10} {3}"

Write-Host ($headerFormat -f "Provider", "Status", "Duration", "Exit Code")
Write-Host ($headerFormat -f ("-" * ($maxNameLength + 2)), "--------", "----------", "---------")

$passCount = 0
$failCount = 0
$skipCount = 0
$errorCount = 0

foreach ($result in $results) {
    $statusColor = switch ($result.Status) {
        "PASS"  { "Green"; $passCount++ }
        "FAIL"  { "Red"; $failCount++ }
        "SKIP"  { "Yellow"; $skipCount++ }
        "ERROR" { "Red"; $errorCount++ }
    }
    
    $durationStr = "$([math]::Round($result.Duration, 2))s"
    
    Write-Host ($rowFormat -f $result.Name, $result.Status, $durationStr, $result.ExitCode) -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "Results: " -NoNewline
Write-Host "$passCount passed" -ForegroundColor Green -NoNewline
Write-Host ", " -NoNewline
Write-Host "$failCount failed" -ForegroundColor Red -NoNewline
Write-Host ", " -NoNewline
Write-Host "$skipCount skipped" -ForegroundColor Yellow
Write-Host ""

# Exit code logic
if ($errorCount -gt 0) {
    Write-Host "Status: ERROR - Some tests could not run" -ForegroundColor Red
    exit 1
}
elseif ($failCount -gt 0) {
    Write-Host "Status: FAIL - Some agents are not working correctly" -ForegroundColor Red
    exit 1
}
elseif ($passCount -eq 0) {
    Write-Host "Status: SKIP - No agents available for testing" -ForegroundColor Yellow
    exit 2
}
else {
    Write-Host "Status: PASS - All available agents working correctly" -ForegroundColor Green
    exit 0
}

# Test Droid Agent CLI
# Verifies that Droid CLI is installed and can execute basic prompts

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

$agentName = "Droid"
$executable = "droid"
$logFile = "test-agent-droid.log"
$testPrompt = "Output exactly: TEST_OK"
$timeoutSeconds = 30

Write-Host ""
Write-Host "Testing $agentName Agent CLI" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

# Check if executable exists
Write-Host "[1/4] Checking for $executable CLI..." -ForegroundColor Gray
$cmd = Get-Command $executable -ErrorAction SilentlyContinue

if (-not $cmd) {
    Write-Host "SKIP: $agentName CLI not found in PATH" -ForegroundColor Yellow
    Write-Host "  Install from: https://factory.ai" -ForegroundColor Gray
    Write-Host ""
    exit 2
}

Write-Host "  Found: $($cmd.Source)" -ForegroundColor Green
Write-Host ""

# Read agent config
Write-Host "[2/4] Reading agent configuration..." -ForegroundColor Gray
$agentsFile = Join-Path (Split-Path -Parent $PSScriptRoot) ".felix\agents.json"

if (Test-Path $agentsFile) {
    try {
        $agentsConfig = Get-Content $agentsFile -Raw | ConvertFrom-Json
        $droidAgent = $agentsConfig.agents | Where-Object { $_.adapter -eq "droid" } | Select-Object -First 1
        
        if ($droidAgent) {
            $args = $droidAgent.args
            Write-Host "  Using config args: $($args -join ' ')" -ForegroundColor Green
        }
        else {
            Write-Host "  No Droid config found, using defaults" -ForegroundColor Yellow
            $args = @("exec", "--skip-permissions-unsafe", "--output-format", "json")
        }
    }
    catch {
        Write-Host "  Failed to parse agents.json, using defaults" -ForegroundColor Yellow
        $args = @("exec", "--skip-permissions-unsafe", "--output-format", "json")
    }
}
else {
    Write-Host "  agents.json not found, using defaults" -ForegroundColor Yellow
    $args = @("exec", "--skip-permissions-unsafe", "--output-format", "json")
}
Write-Host ""

# Execute test
Write-Host "[3/4] Executing test prompt..." -ForegroundColor Gray
Write-Host "  Prompt: $testPrompt" -ForegroundColor Gray
Write-Host "  Timeout: $timeoutSeconds seconds" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date

$job = Start-Job -ScriptBlock {
    param($executable, $args, $testPrompt)
    
    try {
        $output = $testPrompt | & $executable $args 2>&1
        return @{
            Success  = $true
            Output   = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    catch {
        return @{
            Success  = $false
            Output   = $_.Exception.Message
            ExitCode = -1
        }
    }
} -ArgumentList $executable, $args, $testPrompt

$completed = Wait-Job $job -Timeout $timeoutSeconds

if (-not $completed) {
    Stop-Job $job
    Remove-Job $job
    
    Write-Host "FAIL: Timeout after $timeoutSeconds seconds" -ForegroundColor Red
    Write-Host "  Agent may be waiting for OAuth authentication" -ForegroundColor Yellow
    Write-Host "  Or agent is processing request slowly" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$result = Receive-Job $job
Remove-Job $job

$duration = ((Get-Date) - $startTime).TotalSeconds

# Save output to log
$result.Output | Set-Content $logFile -Encoding UTF8
Write-Host "  Output saved to: $logFile" -ForegroundColor Gray
Write-Host "  Duration: $([math]::Round($duration, 2))s" -ForegroundColor Gray
Write-Host ""

if ($Verbose) {
    Write-Host "Raw Output:" -ForegroundColor Gray
    Write-Host $result.Output -ForegroundColor DarkGray
    Write-Host ""
}

# Parse output
Write-Host "[4/4] Verifying output..." -ForegroundColor Gray

if (-not $result.Success) {
    Write-Host "FAIL: Execution error" -ForegroundColor Red
    Write-Host "  Error: $($result.Output)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($result.Output -match 'TEST_OK') {
    Write-Host "PASS: $agentName agent working correctly" -ForegroundColor Green
    Write-Host "  ✓ Found TEST_OK in output" -ForegroundColor Green
    Write-Host "  ✓ Exit code: $($result.ExitCode)" -ForegroundColor Green
    Write-Host ""
    exit 0
}
else {
    Write-Host "FAIL: TEST_OK not found in output" -ForegroundColor Red
    Write-Host "  Agent may have authentication issues" -ForegroundColor Yellow
    Write-Host "  Or agent may not be following instructions" -ForegroundColor Yellow
    Write-Host "  Check log file: $logFile" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Test Copilot Agent CLI
# Verifies that GitHub Copilot CLI is installed and can execute basic prompts programmatically

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

. "$PSScriptRoot/../core/agent-adapters.ps1"

$agentName = "Copilot"
$executable = "copilot"
$logFile = "test-agent-copilot.log"
$testPrompt = "Output exactly: TEST_OK"
$timeoutSeconds = 60

Write-Host ""
Write-Host "Testing $agentName Agent CLI" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/4] Checking for $executable CLI..." -ForegroundColor Gray
$cmd = Get-Command $executable -ErrorAction SilentlyContinue

if (-not $cmd) {
    Write-Host "SKIP: $agentName CLI not found in PATH" -ForegroundColor Yellow
    Write-Host "  Install from: https://docs.github.com/en/copilot/how-tos/copilot-cli" -ForegroundColor Gray
    Write-Host ""
    exit 2
}

Write-Host "  Found: $($cmd.Source)" -ForegroundColor Green
Write-Host ""

Write-Host "[2/4] Building copilot invocation..." -ForegroundColor Gray
$copilotAgent = [pscustomobject]@{
    adapter = "copilot"
    executable = "copilot"
    model = "gpt-5.3-codex"
    allow_all = $true
    no_ask_user = $true
    max_autopilot_continues = 3
}
$invocation = Get-AgentInvocation -AdapterType "copilot" -Config $copilotAgent -Prompt $testPrompt -VerboseMode:$false
Write-Host "  Using programmatic autopilot mode" -ForegroundColor Green
Write-Host ""

Write-Host "[3/4] Executing test prompt..." -ForegroundColor Gray
Write-Host "  Prompt: $testPrompt" -ForegroundColor Gray
Write-Host "  Timeout: $timeoutSeconds seconds" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date
$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()

try {
    $processFilePath = $cmd.Source
    $processArgs = @($invocation.Arguments)
    if ($processFilePath.EndsWith(".ps1")) {
        $processFilePath = "powershell.exe"
        $processArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cmd.Source) + $processArgs
    }

    $argString = (@($processArgs) | ForEach-Object {
            $a = [string]$_
            if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
        }) -join ' '

    $process = Start-Process `
        -FilePath $processFilePath `
        -ArgumentList $argString `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $completed = $process.WaitForExit($timeoutSeconds * 1000)

    if (-not $completed) {
        try { $process.Kill() } catch { }
        Write-Host "FAIL: Timeout after $timeoutSeconds seconds" -ForegroundColor Red
        Write-Host "  Agent may be waiting for folder trust or authentication" -ForegroundColor Yellow
        Write-Host "  Try running: copilot login" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
    $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    $combined = $stdout
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        if (-not [string]::IsNullOrWhiteSpace($combined)) { $combined += "`n" }
        $combined += $stderr
    }

    $result = @{
        Success = ($process.ExitCode -eq 0)
        Output = $combined
        ExitCode = $process.ExitCode
    }
}
finally {
    foreach ($path in @($stdoutPath, $stderrPath)) {
        if ($path -and (Test-Path $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

$duration = ((Get-Date) - $startTime).TotalSeconds

$result.Output | Set-Content $logFile -Encoding UTF8
Write-Host "  Output saved to: $logFile" -ForegroundColor Gray
Write-Host "  Duration: $([math]::Round($duration, 2))s" -ForegroundColor Gray
Write-Host ""

if ($Verbose) {
    Write-Host "Raw Output:" -ForegroundColor Gray
    Write-Host $result.Output -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "[4/4] Verifying output..." -ForegroundColor Gray

if (-not $result.Success) {
    Write-Host "FAIL: Execution error" -ForegroundColor Red
    Write-Host "  Error: $($result.Output)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($result.Output -match 'TEST_OK') {
    Write-Host "PASS: $agentName agent working correctly" -ForegroundColor Green
    Write-Host "  [OK] Found TEST_OK in output" -ForegroundColor Green
    Write-Host "  [OK] Exit code: $($result.ExitCode)" -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "FAIL: Expected output not found" -ForegroundColor Red
Write-Host "  Expected: TEST_OK" -ForegroundColor Red
Write-Host "  Actual: $($result.Output.Trim())" -ForegroundColor Red
Write-Host ""
exit 1
$env:GIT_TERMINAL_PROMPT = "0"

# Get all test files
$testDir = Join-Path $PSScriptRoot ".felix\tests"
$testFiles = Get-ChildItem $testDir -Filter "test-*.ps1" | Where-Object {
    # Exclude sync tests (need external services)
    # Exclude agent-specific tests (test-agent-claude, etc.) that need CLI tools
    # Exclude interactive tests that use Read-Host
    # Exclude helpers/framework (not test suites)
    $_.Name -notmatch "test-sync-" -and
    $_.Name -notmatch "test-orchestrat" -and
    $_.Name -notmatch "test-droid-flags" -and
    $_.Name -notmatch "test-droid-verbose" -and
    $_.Name -notmatch "test-agent-claude" -and
    $_.Name -notmatch "test-agent-copilot" -and
    $_.Name -notmatch "test-agent-codex" -and
    $_.Name -notmatch "test-agent-droid" -and
    $_.Name -notmatch "test-agent-gemini" -and
    $_.Name -notmatch "test-agent-invocation" -and
    $_.Name -notmatch "test-agents\.ps1" -and
    $_.Name -ne "test-framework.ps1" -and
    $_.Name -ne "test-helpers.ps1"
} | Sort-Object Name

$totalPass = 0
$totalFail = 0
$failedTests = @()

foreach ($tf in $testFiles) {
    Write-Host ">>> $($tf.BaseName)" -ForegroundColor Yellow
    $output = & powershell.exe -NoProfile -Command "& { . '$($tf.FullName)' } 2>&1" | Out-String
    $lines = $output -split "`n"
    foreach ($line in $lines) {
        if ($line -match '\[PASS\]') {
            $totalPass++
            Write-Host $line.Trim()
        }
        elseif ($line -match '\[FAIL\]') {
            $totalFail++
            $failedTests += "$($tf.BaseName): $($line.Trim())"
            Write-Host $line.Trim() -ForegroundColor Red
        }
        elseif ($line -match 'Error:' -and $line -notmatch 'Export-ModuleMember') {
            Write-Host $line.Trim() -ForegroundColor Red
        }
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FULL SUITE RESULTS" -ForegroundColor Cyan
Write-Host "Passed: $totalPass" -ForegroundColor Green
Write-Host "Failed: $totalFail" -ForegroundColor $(if ($totalFail -gt 0) { "Red" } else { "Green" })
if ($failedTests.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($ft in $failedTests) { Write-Host "  $ft" -ForegroundColor Red }
}
Write-Host "========================================" -ForegroundColor Cyan

if ($totalFail -gt 0) { exit 1 }

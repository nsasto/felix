# Test Droid CLI flags to see output differences
# Run this to determine which flags give us the best visibility

$ErrorActionPreference = "Continue"

$testPrompt = "do nothing. this is a test"

Write-Host ""
Write-Host "Testing Droid CLI Flags" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test Prompt: $testPrompt" -ForegroundColor Gray
Write-Host ""

# First, get help to see available flags
Write-Host "[Info] Getting available flags from droid exec --help" -ForegroundColor Cyan
droid exec --help 2>&1 | Tee-Object -FilePath "test-droid-help.log"
Write-Host ""
Write-Host "Help saved to: test-droid-help.log" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to continue with tests..."

# Test 1: Basic exec
Write-Host "[Test 1/6] Basic exec (no flags)" -ForegroundColor Yellow
Write-Host "Command: droid exec" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe 2>&1 | Tee-Object -FilePath "test-droid-basic.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 2: JSON output
Write-Host "[Test 2/6] JSON output format" -ForegroundColor Yellow
Write-Host "Command: droid exec --output-format json" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe --output-format json 2>&1 | Tee-Object -FilePath "test-droid-json.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 3: Verbose flag
Write-Host "[Test 3/6] Verbose flag (-v or --verbose)" -ForegroundColor Yellow
Write-Host "Command: droid exec -v" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe -v 2>&1 | Tee-Object -FilePath "test-droid-verbose.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 4: Log level
Write-Host "[Test 4/6] Log level debug" -ForegroundColor Yellow
Write-Host "Command: droid exec --log-level debug" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe --log-level debug 2>&1 | Tee-Object -FilePath "test-droid-loglevel.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 5: Stream output
Write-Host "[Test 5/6] Stream output" -ForegroundColor Yellow
Write-Host "Command: droid exec --stream" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe --stream 2>&1 | Tee-Object -FilePath "test-droid-stream.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 6: Reasoning effort high
Write-Host "[Test 6/8] Reasoning effort high" -ForegroundColor Yellow
Write-Host "Command: droid exec --reasoning-effort high" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe --reasoning-effort high 2>&1 | Tee-Object -FilePath "test-droid-reasoning-high.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 7: JSON + Reasoning high
Write-Host "[Test 7/8] JSON + Reasoning high" -ForegroundColor Yellow
Write-Host "Command: droid exec --output-format json --reasoning-effort high" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe --output-format json --reasoning-effort high 2>&1 | Tee-Object -FilePath "test-droid-json-reasoning.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to continue..."

# Test 8: JSON + Verbose combo
Write-Host "[Test 8/8] JSON + Verbose" -ForegroundColor Yellow
Write-Host "Command: droid exec --output-format json -v" -ForegroundColor Gray
Write-Host ""
try {
    $testPrompt | droid exec --skip-permissions-unsafe --output-format json -v 2>&1 | Tee-Object -FilePath "test-droid-json-verbose.log"
    Write-Host "✓ Success" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host ""
Write-Host "Test Complete!" -ForegroundColor Green
Write-Host "=============" -ForegroundColor Green
Write-Host ""
Write-Host "Log files created:" -ForegroundColor Cyan
Get-ChildItem test-droid-*.log -ErrorAction SilentlyContinue | ForEach-Object {
    $lineCount = (Get-Content $_.FullName -ErrorAction SilentlyContinue).Count
    $size = $_.Length
    Write-Host "  $($_.Name): $lineCount lines, $size bytes" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Review the files to see which gives you:" -ForegroundColor Yellow
Write-Host "  - Model thinking/reasoning" -ForegroundColor Yellow
Write-Host "  - Step-by-step actions" -ForegroundColor Yellow
Write-Host "  - Structured JSON events" -ForegroundColor Yellow
Write-Host ""

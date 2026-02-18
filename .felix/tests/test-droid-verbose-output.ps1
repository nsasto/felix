#!/usr/bin/env pwsh
# Test Droid Output Formats
# Demonstrates the difference between text and JSON output formats

param(
    [Parameter(Mandatory = $false)]
    [string]$Prompt = "List 3 key files in the current directory and explain their purpose."
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Droid Output Format Test" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Prompt: $Prompt" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: Droid doesn't have a '-v' verbose flag." -ForegroundColor Yellow
Write-Host "      Text format (default) shows full reasoning." -ForegroundColor Yellow
Write-Host "      JSON format structures output for parsing." -ForegroundColor Yellow
Write-Host ""

# Test 1: Text output (default - shows thinking/reasoning)
Write-Host "[Test 1/3] Text Output (default)" -ForegroundColor Yellow
Write-Host "Command: echo `"..`" | droid exec --skip-permissions-unsafe --output-format text" -ForegroundColor Gray
Write-Host "Shows: Full response with reasoning and analysis" -ForegroundColor Cyan
Write-Host ""
Write-Host "--- OUTPUT START ---" -ForegroundColor DarkGray
$Prompt | droid exec --skip-permissions-unsafe --output-format text 2>&1
Write-Host "--- OUTPUT END ---" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Press Enter to continue..." -ForegroundColor Gray
Read-Host

# Test 2: JSON output (structured, parsed by Felix)
Write-Host "[Test 2/3] JSON Output (structured)" -ForegroundColor Yellow
Write-Host "Command: echo `"..`" | droid exec --skip-permissions-unsafe --output-format json" -ForegroundColor Gray
Write-Host "Shows: Structured JSON for programmatic parsing" -ForegroundColor Cyan
Write-Host ""
Write-Host "--- OUTPUT START ---" -ForegroundColor DarkGray
$Prompt | droid exec --skip-permissions-unsafe --output-format json 2>&1
Write-Host "--- OUTPUT END ---" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Press Enter to continue..." -ForegroundColor Gray
Read-Host

# Test 3: Text with high reasoning effort
Write-Host "[Test 3/3] JSON with High Reasoning Effort" -ForegroundColor Yellow  
Write-Host "Command: echo `"..`" | droid exec --skip-permissions-unsafe --output-format json --reasoning-effort high" -ForegroundColor Gray
Write-Host "Shows: Same JSON structure, but model thinks more deeply" -ForegroundColor Cyan
Write-Host "Note: Reasoning effort affects quality, NOT format" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "--- OUTPUT START ---" -ForegroundColor DarkGray
$Prompt | droid exec --skip-permissions-unsafe --output-format json --reasoning-effort high 2>&1
Write-Host "--- OUTPUT END ---" -ForegroundColor DarkGray
Write-Host ""

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  1. Text format: Human-readable reasoning" -ForegroundColor White
Write-Host "  2. JSON format: Structured for parsing" -ForegroundColor White  
Write-Host "  3. Reasoning effort: Affects quality, not format" -ForegroundColor White
Write-Host ""
Write-Host "Current Felix Config (.felix/agents.json):" -ForegroundColor Yellow
Write-Host "  - Output format: json (for structured parsing)" -ForegroundColor Gray
Write-Host "  - Thinking is hidden in JSON structure" -ForegroundColor Gray
Write-Host ""
Write-Host "To see thinking in Felix runs:" -ForegroundColor Yellow
Write-Host "  Option 1: Change output-format to 'text'" -ForegroundColor Gray
Write-Host "            (Requires adapter changes to parse text)" -ForegroundColor DarkGray
Write-Host "  Option 2: Use felix --format plain" -ForegroundColor Gray
Write-Host "            (Shows raw JSON output with all fields)" -ForegroundColor DarkGray
Write-Host "  Option 3: Check output.log in runs/ folder" -ForegroundColor Gray
Write-Host "            (Contains full JSON response)" -ForegroundColor DarkGray
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

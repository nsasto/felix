#!/usr/bin/env pwsh
<#
.SYNOPSIS
Felix CLI consumer for NDJSON event stream

.DESCRIPTION
Spawns felix-agent subprocess and consumes NDJSON events from stdout.
Supports multiple output formats: json (passthrough), plain (colored text), rich (enhanced visuals).

.PARAMETER ProjectPath
Path to the Felix repository

.PARAMETER RequirementId
Optional requirement ID to run a specific requirement

.PARAMETER Format
Output format: json, plain, or rich (default: rich)

.PARAMETER EventTypes
Filter events by type (e.g., log, error_occurred, validation_passed)

.PARAMETER MinLevel
Minimum log level to display: debug, info, warn, error (default: info)

.PARAMETER NoStats
Suppress statistics summary at the end

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -RequirementId S-0001

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -Format json

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -MinLevel warn -NoStats
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [string]$RequirementId = $null,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("json", "plain", "rich")]
    [string]$Format = "rich",
    
    [Parameter(Mandatory = $false)]
    [string[]]$EventTypes = @(),
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("debug", "info", "warn", "error")]
    [string]$MinLevel = "info",
    
    [Parameter(Mandatory = $false)]
    [switch]$NoStats
)

$ErrorActionPreference = "Continue"

# ANSI color codes for terminal output
$colors = @{
    Reset         = "`e[0m"
    Bold          = "`e[1m"
    Dim           = "`e[2m"
    
    # Foreground colors
    Black         = "`e[30m"
    Red           = "`e[31m"
    Green         = "`e[32m"
    Yellow        = "`e[33m"
    Blue          = "`e[34m"
    Magenta       = "`e[35m"
    Cyan          = "`e[36m"
    White         = "`e[37m"
    
    # Bright foreground
    BrightRed     = "`e[91m"
    BrightGreen   = "`e[92m"
    BrightYellow  = "`e[93m"
    BrightBlue    = "`e[94m"
    BrightMagenta = "`e[95m"
    BrightCyan    = "`e[96m"
}

# Statistics tracking
$stats = @{
    events             = 0
    errors             = 0
    warnings           = 0
    tasks_completed    = 0
    tasks_failed       = 0
    validations_passed = 0
    validations_failed = 0
    events_by_type     = @{}
}

function Update-Stats {
    param([PSCustomObject]$Event)
    
    $stats.events++
    
    $eventType = $Event.type
    if ($stats.events_by_type.ContainsKey($eventType)) {
        $stats.events_by_type[$eventType]++
    }
    else {
        $stats.events_by_type[$eventType] = 1
    }
    
    switch ($Event.type) {
        "error_occurred" { 
            $stats.errors++ 
        }
        "log" {
            if ($Event.data.level -eq "warn") { $stats.warnings++ }
            if ($Event.data.level -eq "error") { $stats.errors++ }
        }
        "task_completed" {
            if ($Event.data.signal -match "success|complete") { 
                $stats.tasks_completed++ 
            }
            else { 
                $stats.tasks_failed++ 
            }
        }
        "validation_completed" {
            if ($Event.data.passed) { 
                $stats.validations_passed++ 
            }
            else { 
                $stats.validations_failed++ 
            }
        }
    }
}

function Show-Stats {
    if ($NoStats) { return }
    
    Write-Host ""
    Write-Host "$($colors.Bold)$($colors.Cyan)========================================$($colors.Reset)"
    Write-Host "$($colors.Bold)$($colors.Cyan)Execution Summary$($colors.Reset)"
    Write-Host "$($colors.Bold)$($colors.Cyan)========================================$($colors.Reset)"
    Write-Host "Events Processed: $($stats.events)"
    
    $errorColor = if ($stats.errors -gt 0) { $colors.Red } else { $colors.Green }
    Write-Host "${errorColor}Errors: $($stats.errors)$($colors.Reset)"
    
    $warnColor = if ($stats.warnings -gt 0) { $colors.Yellow } else { $colors.Green }
    Write-Host "${warnColor}Warnings: $($stats.warnings)$($colors.Reset)"
    
    if ($stats.tasks_completed -gt 0 -or $stats.tasks_failed -gt 0) {
        Write-Host "$($colors.Green)Tasks Completed: $($stats.tasks_completed)$($colors.Reset)"
        
        $taskFailColor = if ($stats.tasks_failed -gt 0) { $colors.Red } else { $colors.Green }
        Write-Host "${taskFailColor}Tasks Failed: $($stats.tasks_failed)$($colors.Reset)"
    }
    
    if ($stats.validations_passed -gt 0 -or $stats.validations_failed -gt 0) {
        Write-Host "$($colors.Green)Validations Passed: $($stats.validations_passed)$($colors.Reset)"
        
        $valFailColor = if ($stats.validations_failed -gt 0) { $colors.Red } else { $colors.Green }
        Write-Host "${valFailColor}Validations Failed: $($stats.validations_failed)$($colors.Reset)"
    }
    
    Write-Host ""
    Write-Host "$($colors.Dim)Events by type:$($colors.Reset)"
    foreach ($eventType in ($stats.events_by_type.Keys | Sort-Object)) {
        $count = $stats.events_by_type[$eventType]
        Write-Host "$($colors.Dim)  ${eventType}: $count$($colors.Reset)"
    }
    
    Write-Host "$($colors.Bold)$($colors.Cyan)========================================$($colors.Reset)"
    Write-Host ""
}

function Should-Display-Event {
    param([PSCustomObject]$Event)
    
    # Filter by event type if specified
    if ($EventTypes.Count -gt 0 -and $Event.type -notin $EventTypes) {
        return $false
    }
    
    # Filter by log level for log events
    if ($Event.type -eq "log" -and $Event.data.level) {
        $levelOrder = @{ debug = 0; info = 1; warn = 2; error = 3 }
        $eventLevel = $levelOrder[$Event.data.level]
        $minLevelValue = $levelOrder[$MinLevel]
        
        if ($null -ne $eventLevel -and $eventLevel -lt $minLevelValue) {
            return $false
        }
    }
    
    return $true
}

function Format-Timestamp {
    param([string]$IsoTimestamp)
    
    try {
        $dt = [DateTime]::Parse($IsoTimestamp)
        return $dt.ToLocalTime().ToString("HH:mm:ss.fff")
    }
    catch {
        return $IsoTimestamp
    }
}

#
# Format: JSON (passthrough)
#
function Render-Json {
    param([string]$Line)
    Write-Output $Line
}

#
# Format: Plain (colored text)
#
function Render-Plain {
    param([PSCustomObject]$Event)
    
    $timestamp = Format-Timestamp $Event.timestamp
    $type = $Event.type
    $data = $Event.data
    
    switch ($type) {
        "run_started" {
            Write-Host "[$timestamp] RUN STARTED - $($data.requirement_id) (run: $($data.run_id))" -ForegroundColor Cyan
        }
        "iteration_started" {
            Write-Host "[$timestamp] ITERATION $($data.iteration)/$($data.max_iterations) - Mode: $($data.mode)" -ForegroundColor Cyan
        }
        "iteration_completed" {
            $color = if ($data.outcome -eq "success") { "Green" } else { "Red" }
            Write-Host "[$timestamp] ITERATION COMPLETED - $($data.outcome)" -ForegroundColor $color
        }
        "log" {
            $levelColor = switch ($data.level) {
                "debug" { "Gray" }
                "info" { "White" }
                "warn" { "Yellow" }
                "error" { "Red" }
                default { "White" }
            }
            
            $component = if ($data.component) { "[$($data.component)]" } else { "" }
            Write-Host "[$timestamp] $($data.level.ToUpper()) $component $($data.message)" -ForegroundColor $levelColor
        }
        "agent_execution_started" {
            Write-Host "[$timestamp] AGENT EXECUTION STARTED - $($data.agent_name)" -ForegroundColor Cyan
        }
        "agent_execution_completed" {
            Write-Host "[$timestamp] AGENT EXECUTION COMPLETED - Duration: $($data.duration_seconds)s" -ForegroundColor Green
        }
        "validation_started" {
            Write-Host "[$timestamp] VALIDATION STARTED - Type: $($data.validation_type), Commands: $($data.command_count)" -ForegroundColor Blue
        }
        "validation_command_started" {
            Write-Host "[$timestamp]   Running: [$($data.type)] $($data.command)" -ForegroundColor Blue
        }
        "validation_command_completed" {
            $status = if ($data.passed) { "PASSED" } else { "FAILED (exit: $($data.exit_code))" }
            $color = if ($data.passed) { "Green" } else { "Red" }
            Write-Host "[$timestamp]   $status" -ForegroundColor $color
        }
        "validation_completed" {
            $color = if ($data.passed) { "Green" } else { "Red" }
            $status = if ($data.passed) { "PASSED" } else { "FAILED" }
            Write-Host "[$timestamp] VALIDATION $status - $($data.passed_count)/$($data.total_count)" -ForegroundColor $color
        }
        "task_completed" {
            Write-Host "[$timestamp] TASK COMPLETED - Signal: $($data.signal)" -ForegroundColor Green
        }
        "state_transitioned" {
            Write-Host "[$timestamp] STATE: $($data.from)  $($data.to)" -ForegroundColor Magenta
        }
        "artifact_created" {
            $sizeKb = if ($data.size_bytes) { ($data.size_bytes / 1KB).ToString("F1") + " KB" } else { "unknown" }
            Write-Host "[$timestamp] ARTIFACT: $($data.path) ($($data.type), $sizeKb)" -ForegroundColor Cyan
        }
        "error_occurred" {
            Write-Host "[$timestamp] ERROR: $($data.error_type) - $($data.message)" -ForegroundColor Red
            if ($data.context) {
                Write-Host "  Context: $($data.context | ConvertTo-Json -Compress)" -ForegroundColor Gray
            }
        }
        "run_completed" {
            $color = if ($data.exit_code -eq 0) { "Green" } else { "Red" }
            Write-Host "[$timestamp] RUN COMPLETED - $($data.status) (exit: $($data.exit_code), duration: $($data.duration_seconds)s)" -ForegroundColor $color
        }
        default {
            $dataJson = $data | ConvertTo-Json -Compress
            Write-Host "[$timestamp] $type - $dataJson" -ForegroundColor Gray
        }
    }
}

#
# Format: Rich (enhanced visuals)
#
function Render-Rich {
    param([PSCustomObject]$Event)
    
    $timestamp = Format-Timestamp $Event.timestamp
    $type = $Event.type
    $data = $Event.data
    
    switch ($type) {
        "run_started" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Cyan) Felix Run Started$($colors.Reset)"
            Write-Host "$($colors.Cyan) Run ID: $($data.run_id)$($colors.Reset)"
            Write-Host "$($colors.Cyan) Requirement: $($data.requirement_id)$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host ""
        }
        
        "iteration_started" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Cyan) Iteration $($data.iteration)/$($data.max_iterations) - Mode: $($data.mode.ToUpper())$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host ""
        }
        
        "iteration_completed" {
            $outcomeColor = if ($data.outcome -eq "success") { $colors.Green } else { $colors.Red }
            Write-Host ""
            Write-Host "$($colors.Dim)[$timestamp] Iteration $($data.iteration) completed: $outcomeColor$($data.outcome)$($colors.Reset)"
        }
        
        "log" {
            $levelColor = switch ($data.level) {
                "debug" { $colors.Dim }
                "info" { $colors.White }
                "warn" { $colors.Yellow }
                "error" { $colors.Red }
                default { $colors.White }
            }
            
            $component = if ($data.component) { "[$($data.component)]" } else { "" }
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset) $levelColor$($data.level.ToUpper())$($colors.Reset) $component $($data.message)"
        }
        
        "agent_execution_started" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Cyan)[$timestamp] AGENT EXECUTION STARTED$($colors.Reset)"
            Write-Host "$($colors.Cyan)  Agent: $($data.agent_name)$($colors.Reset)"
        }
        
        "agent_execution_completed" {
            Write-Host "$($colors.Bold)$($colors.Green)[$timestamp] AGENT EXECUTION COMPLETED$($colors.Reset)"
            Write-Host "$($colors.Green)  Duration: $($data.duration_seconds.ToString("F1"))s$($colors.Reset)"
            Write-Host ""
        }
        
        "validation_started" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Blue)[$timestamp] VALIDATION STARTED$($colors.Reset)"
            Write-Host "$($colors.Blue)  Type: $($data.validation_type)$($colors.Reset)"
            Write-Host "$($colors.Blue)  Commands: $($data.command_count)$($colors.Reset)"
            Write-Host ""
        }
        
        "validation_command_started" {
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset) $($colors.Blue)Running:$($colors.Reset) [$($data.type)] $($data.command)"
        }
        
        "validation_command_completed" {
            $status = if ($data.passed) {
                "$($colors.Green) PASSED$($colors.Reset)"
            }
            else {
                "$($colors.Red) FAILED (exit code: $($data.exit_code))$($colors.Reset)"
            }
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset)   $status"
        }
        
        "validation_completed" {
            Write-Host ""
            if ($data.passed) {
                Write-Host "$($colors.Bold)$($colors.Green)[$timestamp]  VALIDATION PASSED$($colors.Reset)"
            }
            else {
                Write-Host "$($colors.Bold)$($colors.Red)[$timestamp]  VALIDATION FAILED$($colors.Reset)"
            }
            Write-Host "$($colors.Dim)  Passed: $($data.passed_count)/$($data.total_count)$($colors.Reset)"
            Write-Host ""
        }
        
        "task_completed" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Green)[$timestamp]  TASK COMPLETED$($colors.Reset)"
            Write-Host "$($colors.Green)  Signal: $($data.signal)$($colors.Reset)"
            Write-Host ""
        }
        
        "state_transitioned" {
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset) $($colors.Magenta)State:$($colors.Reset) $($data.from)  $($data.to)"
        }
        
        "artifact_created" {
            $sizeKb = if ($data.size_bytes) { ($data.size_bytes / 1KB).ToString("F1") + " KB" } else { "unknown" }
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset) $($colors.Cyan)Artifact:$($colors.Reset) $($data.path) ($($data.type), $sizeKb)"
        }
        
        "error_occurred" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Red)[$timestamp] ERROR: $($data.error_type)$($colors.Reset)"
            Write-Host "$($colors.Red)  Severity: $($data.severity)$($colors.Reset)"
            Write-Host "$($colors.Red)  Message: $($data.message)$($colors.Reset)"
            if ($data.context) {
                Write-Host "$($colors.Dim)  Context: $($data.context | ConvertTo-Json -Compress)$($colors.Reset)"
            }
            Write-Host ""
        }
        
        "run_completed" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            $statusColor = if ($data.exit_code -eq 0) { $colors.Green } else { $colors.Red }
            Write-Host "$($colors.Bold)$statusColor Run Completed: $($data.status) (exit code: $($data.exit_code))$($colors.Reset)"
            if ($data.duration_seconds) {
                Write-Host "$($colors.Cyan) Duration: $($data.duration_seconds.ToString("F1"))s$($colors.Reset)"
            }
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host ""
        }
        
        default {
            # Unknown event type - show raw JSON
            $dataJson = $data | ConvertTo-Json -Compress
            Write-Host "$($colors.Dim)[$timestamp] $($type): $dataJson$($colors.Reset)"
        }
    }
}

# Select renderer based on format
$renderer = switch ($Format) {
    "json" { { param($e, $l) Render-Json -Line $l } }
    "plain" { { param($e, $l) Render-Plain -Event $e } }
    "rich" { { param($e, $l) Render-Rich -Event $e } }
}

# Build felix-agent command
$agentScript = Join-Path $PSScriptRoot "felix-agent.ps1"
$agentArgs = @($ProjectPath)
if ($RequirementId) {
    $agentArgs += @("-RequirementId", $RequirementId)
}

if ($Format -ne "json") {
    Write-Host "$($colors.Bold)$($colors.Cyan)Felix CLI Consumer$($colors.Reset)"
    Write-Host "$($colors.Dim)Format: $Format | Min Level: $MinLevel$($colors.Reset)"
    if ($EventTypes.Count -gt 0) {
        Write-Host "$($colors.Dim)Filtering events: $($EventTypes -join ', ')$($colors.Reset)"
    }
    Write-Host ""
}

# Start felix-agent as subprocess
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = "powershell.exe"
$processInfo.Arguments = "-NoProfile -File `"$agentScript`" $($agentArgs -join ' ')"
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $false

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo

try {
    $process.Start() | Out-Null
    
    # Read stdout line by line
    while (-not $process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine()
        
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        
        # Try to parse as JSON
        try {
            $event = $line | ConvertFrom-Json
            
            # Validate it's an event (has type and data)
            if ($event.type -and $event.data) {
                # Update statistics
                Update-Stats -Event $event
                
                # Check if event should be displayed
                if (Should-Display-Event -Event $event) {
                    & $renderer $event $line
                }
            }
            else {
                # Valid JSON but not an event
                if ($Format -eq "json") {
                    Write-Output $line
                }
                elseif ($Format -ne "json") {
                    Write-Host "$($colors.Dim)Non-event JSON: $line$($colors.Reset)"
                }
            }
        }
        catch {
            # Not JSON - treat as legacy console output
            if ($Format -eq "json") {
                Write-Output $line
            }
            else {
                Write-Host "$($colors.Yellow)[LEGACY OUTPUT]$($colors.Reset) $line"
            }
        }
    }
    
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    
    # Show stats for non-json formats
    if ($Format -ne "json") {
        Show-Stats
        Write-Host "$($colors.Dim)Felix agent exited with code: $exitCode$($colors.Reset)"
    }
    
    exit $exitCode
}
catch {
    if ($Format -ne "json") {
        Write-Host "$($colors.Red)Error running felix-agent: $_$($colors.Reset)"
    }
    exit 1
}
finally {
    if ($process -and -not $process.HasExited) {
        $process.Kill()
    }
}

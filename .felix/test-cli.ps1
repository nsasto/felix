#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test CLI consumer for Felix NDJSON event stream

.DESCRIPTION
Spawns felix-agent subprocess and consumes NDJSON events from stdout.
Renders formatted output to demonstrate event stream parsing.

.EXAMPLE
.\test-cli.ps1 C:\dev\Felix -RequirementId S-0000
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [string]$RequirementId = $null
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

function Render-Event {
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
                "$($colors.Green)✅ PASSED$($colors.Reset)"
            }
            else {
                "$($colors.Red)❌ FAILED (exit code: $($data.exit_code))$($colors.Reset)"
            }
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset)   $status"
        }
        
        "validation_completed" {
            Write-Host ""
            if ($data.passed) {
                Write-Host "$($colors.Bold)$($colors.Green)[$timestamp] ✅ VALIDATION PASSED$($colors.Reset)"
            }
            else {
                Write-Host "$($colors.Bold)$($colors.Red)[$timestamp] ❌ VALIDATION FAILED$($colors.Reset)"
            }
            Write-Host "$($colors.Dim)  Passed: $($data.passed_count)/$($data.total_count)$($colors.Reset)"
            Write-Host ""
        }
        
        "task_completed" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Green)[$timestamp] ✅ TASK COMPLETED$($colors.Reset)"
            Write-Host "$($colors.Green)  Signal: $($data.signal)$($colors.Reset)"
            Write-Host ""
        }
        
        "state_transitioned" {
            Write-Host "$($colors.Dim)[$timestamp]$($colors.Reset) $($colors.Magenta)State:$($colors.Reset) $($data.from) → $($data.to)"
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

# Build felix-agent command
$agentScript = Join-Path $PSScriptRoot "felix-agent.ps1"
$agentArgs = @($ProjectPath)
if ($RequirementId) {
    $agentArgs += @("-RequirementId", $RequirementId)
}

Write-Host "$($colors.Bold)$($colors.Cyan)Felix Test CLI Consumer$($colors.Reset)"
Write-Host "$($colors.Dim)Starting felix-agent: $agentScript $($agentArgs -join ' ')$($colors.Reset)"
Write-Host ""

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

# Event counter for stats
$eventCount = 0
$eventsByType = @{}

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
                $eventCount++
                if ($eventsByType.ContainsKey($event.type)) {
                    $eventsByType[$event.type] = $eventsByType[$event.type] + 1
                }
                else {
                    $eventsByType[$event.type] = 1
                }
                Render-Event -Event $event
            }
            else {
                # Valid JSON but not an event - show as-is
                Write-Host "$($colors.Dim)Non-event JSON: $line$($colors.Reset)"
            }
        }
        catch {
            # Not JSON - treat as legacy console output
            Write-Host "$($colors.Yellow)[LEGACY OUTPUT]$($colors.Reset) $line"
        }
    }
    
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    
    # Show stats
    Write-Host ""
    Write-Host "$($colors.Bold)$($colors.Cyan)Event Stream Statistics$($colors.Reset)"
    Write-Host "$($colors.Dim)Total events: $eventCount$($colors.Reset)"
    Write-Host "$($colors.Dim)Events by type:$($colors.Reset)"
    foreach ($eventType in ($eventsByType.Keys | Sort-Object)) {
        $count = $eventsByType[$eventType]
        Write-Host "$($colors.Dim)  $eventType`: $count$($colors.Reset)"
    }
    Write-Host ""
    Write-Host "$($colors.Dim)Felix agent exited with code: $exitCode$($colors.Reset)"
    
    exit $exitCode
}
catch {
    Write-Host "$($colors.Red)Error running felix-agent: $_$($colors.Reset)" -ForegroundColor Red
    exit 1
}
finally {
    if ($process -and -not $process.HasExited) {
        $process.Kill()
    }
}

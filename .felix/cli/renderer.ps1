<#
.SYNOPSIS
ANSI renderer and stats for Felix CLI output

.DESCRIPTION
ANSI color definitions, statistics tracking, and all event renderers.
Dot-sourced into felix-cli.ps1.
#>

# ANSI color codes for terminal output
# ANSI color codes - use compatible escape sequence for PowerShell 5.1
$esc = if ($PSVersionTable.PSVersion.Major -ge 7) { "`e" } else { [char]0x1b }

$colors = @{
    Reset         = "$esc[0m"
    Bold          = "$esc[1m"
    Dim           = "$esc[2m"
    
    # Foreground colors
    Black         = "$esc[30m"
    Red           = "$esc[31m"
    Green         = "$esc[32m"
    Yellow        = "$esc[33m"
    Blue          = "$esc[34m"
    Magenta       = "$esc[35m"
    Cyan          = "$esc[36m"
    White         = "$esc[37m"
    
    # Bright foreground
    BrightRed     = "$esc[91m"
    BrightGreen   = "$esc[92m"
    BrightYellow  = "$esc[93m"
    BrightBlue    = "$esc[94m"
    BrightMagenta = "$esc[95m"
    BrightCyan    = "$esc[96m"
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

$script:CategoryColumnWidth = 10

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

function Write-CategoryLine {
    param(
        [string]$Timestamp,
        [string]$Category,
        [string]$Message,
        [string]$CategoryColor = $colors.White,
        [string]$MessageColor = $colors.White
    )

    $paddedCategory = $Category.PadRight($script:CategoryColumnWidth)
    Write-Host "$($colors.Dim)[$Timestamp]$($colors.Reset) ${CategoryColor}${paddedCategory}$($colors.Reset) ${MessageColor}${Message}$($colors.Reset)"
}

# Format-MarkdownText is now provided by text-utils.ps1

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
            $formattedMessage = Format-MarkdownText -Text $data.message
            Write-Host "[$timestamp] $($data.level.ToUpper()) $component $formattedMessage" -ForegroundColor $levelColor
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
            Write-CategoryLine -Timestamp $timestamp -Category "Iteration" -Message $data.outcome -CategoryColor $outcomeColor -MessageColor $outcomeColor
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
            $formattedMessage = Format-MarkdownText -Text $data.message
            $message = if ($component) { "$component $formattedMessage" } else { $formattedMessage }
            Write-CategoryLine -Timestamp $timestamp -Category $data.level.ToUpper() -Message $message -CategoryColor $levelColor
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
            Write-CategoryLine -Timestamp $timestamp -Category "Running" -Message "[$($data.type)] $($data.command)" -CategoryColor $colors.Blue
        }
        
        "validation_command_completed" {
            $status = if ($data.passed) {
                "PASSED"
            }
            else {
                "FAILED (exit code: $($data.exit_code))"
            }
            $statusColor = if ($data.passed) { $colors.Green } else { $colors.Red }
            Write-CategoryLine -Timestamp $timestamp -Category "Validation" -Message $status -CategoryColor $statusColor -MessageColor $statusColor
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
            Write-CategoryLine -Timestamp $timestamp -Category "State" -Message "$($data.from) -> $($data.to)" -CategoryColor $colors.Magenta
        }
        
        "artifact_created" {
            $sizeKb = if ($data.size_bytes) { ($data.size_bytes / 1KB).ToString("F1") + " KB" } else { "unknown" }
            Write-CategoryLine -Timestamp $timestamp -Category "Artifact" -Message "$($data.path) ($($data.type), $sizeKb)" -CategoryColor $colors.Cyan
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
        
        "spec_builder_started" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Magenta)============================================================$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Magenta) Spec Builder Started$($colors.Reset)"
            Write-Host "$($colors.Magenta) Requirement: $($data.requirement_id)$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Magenta)============================================================$($colors.Reset)"
            Write-Host ""
        }
        
        "spec_question" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Cyan)  Question from AI$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Cyan)============================================================$($colors.Reset)"
            Write-Host ""
            
            # Format and display the question with markdown rendering
            $formattedQuestion = Format-MarkdownText -Text $data.question
            Write-Host $formattedQuestion
            
            Write-Host ""
            Write-Host "$($colors.Yellow)Your answer (or type cancel to abort):$($colors.Reset) " -NoNewline
        }
        
        "spec_draft" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Green)[$timestamp] SPEC DRAFT GENERATED$($colors.Reset)"
            Write-Host "$($colors.Dim)  Content length: $($data.content.Length) characters$($colors.Reset)"
            Write-Host ""
        }
        
        "spec_builder_complete" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Green)============================================================$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Green)  Spec Builder Complete!$($colors.Reset)"
            Write-Host "$($colors.Green)  Requirement: $($data.requirement_id)$($colors.Reset)"
            Write-Host "$($colors.Green)  Spec File: $($data.spec_file)$($colors.Reset)"
            Write-Host "$($colors.Bold)$($colors.Green)============================================================$($colors.Reset)"
            Write-Host ""
        }
        
        "spec_builder_cancelled" {
            Write-Host ""
            Write-Host "$($colors.Bold)$($colors.Yellow)[$timestamp]  SPEC BUILDER CANCELLED$($colors.Reset)"
            Write-Host ""
        }
        
        "prompt_requested" {
            # File-based prompt for UI/TUI integration - show minimal info
            Write-CategoryLine -Timestamp $timestamp -Category "Prompt" -Message "Waiting for response (prompt_id: $($data.prompt_id))" -CategoryColor $colors.Cyan
        }
        
        default {
            # Unknown event type - show raw JSON
            $dataJson = $data | ConvertTo-Json -Compress
            Write-CategoryLine -Timestamp $timestamp -Category "Event" -Message "${type}: $dataJson" -CategoryColor $colors.Dim -MessageColor $colors.Dim
        }
    }
}

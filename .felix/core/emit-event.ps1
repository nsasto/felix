<#
.SYNOPSIS
Event emission system for Felix NDJSON output

.DESCRIPTION
Provides functions to emit structured NDJSON events to stdout. All console output
from the Felix engine flows through these functions, making the engine UI-agnostic
and enabling multiple consumers (CLI, TUI, Tray).

Events are emitted as newline-delimited JSON (NDJSON) - one complete JSON object per line.
Consumers read stdout line-by-line and parse each event.

.NOTES
- Use Write-Output (not Write-Host) to emit to stdout
- All events include timestamp and type
- Errors are structured events, not stderr (except PowerShell crashes)
#>

function Emit-Event {
    <#
    .SYNOPSIS
    Emits a structured event to stdout as NDJSON
    
    .DESCRIPTION
    Core event emission function. All events flow through here.
    Outputs newline-delimited JSON to stdout for consumption by host/UI.
    
    .PARAMETER EventType
    Type of event (e.g., 'log', 'progress', 'run_started')
    
    .PARAMETER Data
    Hashtable containing event-specific data
    
    .EXAMPLE
    Emit-Event -EventType "run_started" -Data @{
        run_id = "2026-02-04T10-30-00"
        requirement_id = "S-0001"
    }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    # Skip event emission if suppressed (e.g., interactive spec-builder mode)
    # But show errors directly with Write-Host for interactive debugging
    if ($script:SuppressEventEmission -eq $true) {
        # Still show errors/fatals in interactive mode via console
        if ($Severity -in @('error', 'fatal')) {
            $color = if ($Severity -eq 'fatal') { 'Red' } else { 'Yellow' }
            Write-Host "[$Severity] $ErrorType`: $Message" -ForegroundColor $color
            if ($Context) {
                Write-Host "  Context: $($Context | ConvertTo-Json -Compress)" -ForegroundColor Gray
            }
        }
        return
    }
    
    # Build event object
    $event = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")  # ISO 8601 format
        type      = $EventType
        data      = $Data
    }
    
    # Convert to JSON and write to stdout
    $json = $event | ConvertTo-Json -Compress -Depth 10
    
    # Use [Console]::WriteLine for speed + subprocess compatibility
    [Console]::WriteLine($json)
    
    # Trigger OnEvent plugin hook (sync, logging, etc.)
    if ($script:PluginCache -and $script:RunId) {
        try {
            Invoke-PluginHookSafely -HookName "OnEvent" -RunId $script:RunId -HookData @{
                Event = $event
            } | Out-Null
        }
        catch {
            # Silent failure - plugins shouldn't break event emission
        }
    }
}

function Emit-Log {
    <#
    .SYNOPSIS
    Emits a structured log event
    
    .DESCRIPTION
    Helper function for log messages with severity levels.
    Replaces most Write-Host calls in the codebase.
    
    .PARAMETER Level
    Log level: debug, info, warn, error
    
    .PARAMETER Message
    Log message text
    
    .PARAMETER Component
    Optional component name (e.g., "config-loader", "executor")
    
    .EXAMPLE
    Emit-Log -Level "info" -Message "Loading configuration" -Component "config-loader"
    Emit-Log -Level "error" -Message "Config file not found"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("debug", "info", "warn", "error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = ""
    )
    
    $data = @{
        level   = $Level
        message = $Message
    }
    
    if ($Component) {
        $data.component = $Component
    }
    
    Emit-Event -EventType "log" -Data $data
}

function Emit-Progress {
    <#
    .SYNOPSIS
    Emits a progress update event
    
    .DESCRIPTION
    Used for reporting progress through multi-step operations.
    UI can display as progress bar or percentage indicator.
    
    .PARAMETER Percent
    Progress percentage (0-100)
    
    .PARAMETER Step
    Current step identifier
    
    .PARAMETER Message
    Optional human-readable progress message
    
    .EXAMPLE
    Emit-Progress -Percent 50 -Step "validation" -Message "Running tests"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$Percent,
        
        [Parameter(Mandatory = $true)]
        [string]$Step,
        
        [Parameter(Mandatory = $false)]
        [string]$Message = ""
    )
    
    $data = @{
        percent = $Percent
        step    = $Step
    }
    
    if ($Message) {
        $data.message = $Message
    }
    
    Emit-Event -EventType "progress" -Data $data
}

function Emit-Artifact {
    <#
    .SYNOPSIS
    Emits an artifact creation event
    
    .DESCRIPTION
    Emitted whenever the engine writes a file (logs, reports, diffs, etc).
    Allows UI to display artifact list and enable viewing/downloading.
    
    .PARAMETER Path
    Relative path to artifact from project root
    
    .PARAMETER Type
    Artifact type: log, report, diff, metadata, etc
    
    .PARAMETER SizeBytes
    Optional file size in bytes
    
    .EXAMPLE
    Emit-Artifact -Path "runs/2026-02-04T10-30-00/output.log" -Type "log" -SizeBytes 45123
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$Type,
        
        [Parameter(Mandatory = $false)]
        [long]$SizeBytes = 0
    )
    
    $data = @{
        path = $Path
        type = $Type
    }
    
    if ($SizeBytes -gt 0) {
        $data.size_bytes = $SizeBytes
    }
    
    Emit-Event -EventType "artifact_created" -Data $data
}

function Emit-Error {
    <#
    .SYNOPSIS
    Emits a structured error event
    
    .DESCRIPTION
    Used for all errors in the system. Replaces Write-Host with -ForegroundColor Red.
    Includes error context (requirement, run, iteration) for debugging.
    
    .PARAMETER ErrorType
    Type of error (e.g., ConfigNotFound, ValidationFailed, AgentCrash)
    
    .PARAMETER Message
    Human-readable error message
    
    .PARAMETER Severity
    Error severity: warning, error, fatal
    
    .PARAMETER Context
    Optional hashtable with additional context (requirement_id, run_id, etc)
    
    .EXAMPLE
    Emit-Error -ErrorType "ConfigNotFound" -Message "Config file not found: .felix/config.json" -Severity "fatal" -Context @{
        file = "config-loader.ps1"
        line = 91
    }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorType,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("warning", "error", "fatal")]
        [string]$Severity = "error",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    
    # If events are suppressed (interactive mode), show errors directly on console
    if ($script:SuppressEventEmission -eq $true) {
        $color = if ($Severity -eq 'fatal') { 'Red' } elseif ($Severity -eq 'error') { 'Red' } else { 'Yellow' }
        Write-Host "[$Severity] $ErrorType`: $Message" -ForegroundColor $color
        if ($Context.Count -gt 0) {
            Write-Host "  Context: $($Context | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
    }
    
    $data = @{
        error_type = $ErrorType
        message    = $Message
        severity   = $Severity
    }
    
    if ($Context.Count -gt 0) {
        $data.context = $Context
    }
    
    Emit-Event -EventType "error_occurred" -Data $data
}

function Emit-RunStarted {
    <#
    .SYNOPSIS
    Emits run_started event
    
    .PARAMETER RunId
    Run identifier (timestamp-based)
    
    .PARAMETER RequirementId
    Requirement being worked on
    
    .PARAMETER ProjectPath
    Project path
    #>
    param(
        [string]$RunId,
        [string]$RequirementId,
        [string]$ProjectPath
    )
    
    Emit-Event -EventType "run_started" -Data @{
        run_id         = $RunId
        requirement_id = $RequirementId
        project_path   = $ProjectPath
    }
}

function Emit-RunCompleted {
    <#
    .SYNOPSIS
    Emits run_completed event
    
    .PARAMETER Status
    Run status: success, failure, cancelled, blocked
    
    .PARAMETER ExitCode
    Process exit code
    
    .PARAMETER DurationSeconds
    Optional run duration in seconds
    #>
    param(
        [string]$Status,
        [int]$ExitCode,
        [double]$DurationSeconds = 0
    )
    
    $data = @{
        status    = $Status
        exit_code = $ExitCode
    }
    
    if ($DurationSeconds -gt 0) {
        $data.duration_seconds = $DurationSeconds
    }
    
    Emit-Event -EventType "run_completed" -Data $data
}

function Emit-IterationStarted {
    <#
    .SYNOPSIS
    Emits iteration_started event
    
    .PARAMETER Iteration
    Current iteration number
    
    .PARAMETER MaxIterations
    Maximum iterations allowed
    
    .PARAMETER RequirementId
    Requirement being worked on
    
    .PARAMETER Mode
    Execution mode: planning or building
    #>
    param(
        [int]$Iteration,
        [int]$MaxIterations,
        [string]$RequirementId,
        [string]$Mode
    )
    
    Emit-Event -EventType "iteration_started" -Data @{
        iteration      = $Iteration
        max_iterations = $MaxIterations
        requirement_id = $RequirementId
        mode           = $Mode
    }
}

function Emit-IterationCompleted {
    <#
    .SYNOPSIS
    Emits iteration_completed event
    
    .PARAMETER Iteration
    Completed iteration number
    
    .PARAMETER Outcome
    Iteration outcome: success, failure, blocked
    #>
    param(
        [int]$Iteration,
        [string]$Outcome
    )
    
    Emit-Event -EventType "iteration_completed" -Data @{
        iteration = $Iteration
        outcome   = $Outcome
    }
}

function Emit-PhaseStarted {
    <#
    .SYNOPSIS
    Emits phase_started event
    
    .PARAMETER Phase
    Phase name: planning, building, validating
    #>
    param(
        [string]$Phase
    )
    
    Emit-Event -EventType "phase_started" -Data @{
        phase = $Phase
    }
}

function Emit-PhaseCompleted {
    <#
    .SYNOPSIS
    Emits phase_completed event
    
    .PARAMETER Phase
    Completed phase name
    
    .PARAMETER Signal
    Optional completion signal (e.g., PLAN_COMPLETE, ALL_COMPLETE)
    #>
    param(
        [string]$Phase,
        [string]$Signal = ""
    )
    
    $data = @{
        phase = $Phase
    }
    
    if ($Signal) {
        $data.signal = $Signal
    }
    
    Emit-Event -EventType "phase_completed" -Data $data
}

function Emit-ValidationStarted {
    <#
    .SYNOPSIS
    Emits validation_started event
    
    .PARAMETER CommandCount
    Number of validation commands to run
    
    .PARAMETER ValidationType
    Type of validation: backpressure, requirement, etc
    #>
    param(
        [int]$CommandCount,
        [string]$ValidationType = "backpressure"
    )
    
    Emit-Event -EventType "validation_started" -Data @{
        command_count   = $CommandCount
        validation_type = $ValidationType
    }
}

function Emit-ValidationCommandStarted {
    <#
    .SYNOPSIS
    Emits validation_command_started event
    
    .PARAMETER Command
    Command being executed
    
    .PARAMETER Type
    Command type: test, build, lint
    #>
    param(
        [string]$Command,
        [string]$Type
    )
    
    Emit-Event -EventType "validation_command_started" -Data @{
        command = $Command
        type    = $Type
    }
}

function Emit-ValidationCommandCompleted {
    <#
    .SYNOPSIS
    Emits validation_command_completed event
    
    .PARAMETER Command
    Command that was executed
    
    .PARAMETER Passed
    Whether command passed (exit code 0)
    
    .PARAMETER ExitCode
    Command exit code
    #>
    param(
        [string]$Command,
        [bool]$Passed,
        [int]$ExitCode
    )
    
    Emit-Event -EventType "validation_command_completed" -Data @{
        command   = $Command
        passed    = $Passed
        exit_code = $ExitCode
    }
}

function Emit-ValidationCompleted {
    <#
    .SYNOPSIS
    Emits validation_completed event
    
    .PARAMETER Passed
    Whether validation passed overall
    
    .PARAMETER PassedCount
    Number of commands that passed
    
    .PARAMETER FailedCount
    Number of commands that failed
    
    .PARAMETER TotalCount
    Total commands executed
    #>
    param(
        [bool]$Passed,
        [int]$PassedCount,
        [int]$FailedCount,
        [int]$TotalCount
    )
    
    Emit-Event -EventType "validation_completed" -Data @{
        passed       = $Passed
        passed_count = $PassedCount
        failed_count = $FailedCount
        total_count  = $TotalCount
    }
}

function Emit-StateTransitioned {
    <#
    .SYNOPSIS
    Emits state_transitioned event
    
    .PARAMETER From
    Previous state
    
    .PARAMETER To
    New state
    #>
    param(
        [string]$From,
        [string]$To
    )
    
    Emit-Event -EventType "state_transitioned" -Data @{
        from = $From
        to   = $To
    }
}

function Emit-TaskCompleted {
    <#
    .SYNOPSIS
    Emits task_completed event
    
    .PARAMETER Signal
    Completion signal detected (TASK_COMPLETE, ALL_COMPLETE)
    
    .PARAMETER Mode
    Current mode
    #>
    param(
        [string]$Signal,
        [string]$Mode
    )
    
    Emit-Event -EventType "task_completed" -Data @{
        signal = $Signal
        mode   = $Mode
    }
}

function Emit-AgentExecutionStarted {
    <#
    .SYNOPSIS
    Emits agent_execution_started event
    
    .PARAMETER AgentName
    Name of agent being executed
    
    .PARAMETER AgentId
    Agent ID
    #>
    param(
        [string]$AgentName,
        [string]$AgentId
    )
    
    Emit-Event -EventType "agent_execution_started" -Data @{
        agent_name = $AgentName
        agent_id   = $AgentId
    }
}

function Emit-AgentExecutionCompleted {
    <#
    .SYNOPSIS
    Emits agent_execution_completed event
    
    .PARAMETER DurationSeconds
    Execution duration in seconds
    #>
    param(
        [double]$DurationSeconds
    )
    
    Emit-Event -EventType "agent_execution_completed" -Data @{
        duration_seconds = $DurationSeconds
    }
}

# Functions are available when dot-sourced (no Export-ModuleMember needed)

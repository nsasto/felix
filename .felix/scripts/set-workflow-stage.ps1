#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates the current workflow stage in .felix/state.json
    
.DESCRIPTION
    This helper script updates the workflow stage tracking fields in state.json:
    - current_workflow_stage: The ID of the current stage
    - workflow_stage_timestamp: When the stage was entered
    - workflow_stage_history: Rolling array of last 10 stage transitions
    
    Valid stages are defined in .felix/workflow.json:
    - select_requirement
    - start_iteration
    - determine_mode
    - gather_context
    - build_prompt
    - execute_llm
    - process_output
    - check_guardrails (conditional: planning mode only)
    - detect_task
    - run_backpressure
    - commit_changes
    - validate_requirement
    - update_status
    - iteration_complete
    
.PARAMETER Stage
    The workflow stage ID to set (e.g., "execute_llm", "run_backpressure")
    
.PARAMETER ProjectPath
    Optional. Path to the Felix project directory. Defaults to current directory.
    
.PARAMETER Clear
    Optional switch. If set, clears the current workflow stage (sets to null).
    
.EXAMPLE
    .\set-workflow-stage.ps1 -Stage "execute_llm"
    
.EXAMPLE
    .\set-workflow-stage.ps1 -Stage "run_backpressure" -ProjectPath "C:\dev\Felix"
    
.EXAMPLE
    .\set-workflow-stage.ps1 -Clear
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Stage,
    
    [Parameter(Mandatory = $false)]
    [string]$ProjectPath = ".",
    
    [Parameter(Mandatory = $false)]
    [switch]$Clear
)

# Resolve project path
try {
    $ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
}
catch {
    Write-Error "Invalid project path: $ProjectPath"
    exit 1
}

$StateFile = Join-Path $ProjectPath "felix\state.json"

# Validate state file exists
if (-not (Test-Path $StateFile)) {
    Write-Error "State file not found: $StateFile"
    exit 1
}

# Validate parameters
if (-not $Clear -and -not $Stage) {
    Write-Error "Either -Stage or -Clear must be specified"
    exit 1
}

# Load current state
try {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse state.json: $_"
    exit 1
}

$timestamp = Get-Date -Format "o"

if ($Clear) {
    # Clear the workflow stage
    $state | Add-Member -MemberType NoteProperty -Name current_workflow_stage -Value $null -Force
    $state | Add-Member -MemberType NoteProperty -Name workflow_stage_timestamp -Value $null -Force
    # Workflow stage cleared (silent)
}
else {
    # Set the new stage
    $previousStage = $state.current_workflow_stage
    
    $state | Add-Member -MemberType NoteProperty -Name current_workflow_stage -Value $Stage -Force
    $state | Add-Member -MemberType NoteProperty -Name workflow_stage_timestamp -Value $timestamp -Force
    
    # Maintain workflow_stage_history (last 10 entries)
    $historyEntry = @{
        stage     = $Stage
        timestamp = $timestamp
    }
    
    # Get existing history or initialize empty array
    $history = @()
    if ($state.PSObject.Properties['workflow_stage_history'] -and $state.workflow_stage_history) {
        # Convert to regular array if needed
        $history = @($state.workflow_stage_history)
    }
    
    # Add new entry
    $history += [PSCustomObject]$historyEntry
    
    # Keep only last 10 entries
    if ($history.Count -gt 10) {
        $history = $history | Select-Object -Last 10
    }
    
    $state | Add-Member -MemberType NoteProperty -Name workflow_stage_history -Value $history -Force
    # Workflow stage changes are tracked in state.json
}

# Update the updated_at timestamp
$state.updated_at = $timestamp

# Save state
try {
    $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile -Encoding UTF8
}
catch {
    Write-Error "Failed to save state.json: $_"
    exit 1
}

exit 0


<#
.SYNOPSIS
Workflow stage management for Felix agent visualization

.DESCRIPTION
Provides functions to update and clear workflow stages in state.json
for live visualization in the UI. Updates are non-critical and fail silently.
#>

function Set-WorkflowStage {
    <#
    .SYNOPSIS
    Updates the current workflow stage in state.json for live visualization
    
    .DESCRIPTION
    Calls the set-workflow-stage.ps1 helper script to update:
    - current_workflow_stage
    - workflow_stage_timestamp
    - workflow_stage_history (last 10 entries)
    
    This is a wrapper that handles errors silently to not disrupt agent execution.
    
    .PARAMETER Stage
    The workflow stage ID (e.g., "execute_llm", "run_backpressure")
    
    .PARAMETER ProjectPath
    The Felix project path
    
    .PARAMETER Clear
    Optional switch to clear the current stage
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Stage,
        
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$Clear
    )
    
    $helperScript = Join-Path $ProjectPath "felix\scripts\set-workflow-stage.ps1"
    
    # If helper script doesn't exist, silently skip (backwards compatibility)
    if (-not (Test-Path $helperScript)) {
        return
    }
    
    try {
        if ($Clear) {
            & $helperScript -Clear -ProjectPath $ProjectPath 2>$null | Out-Null
        }
        elseif ($Stage) {
            & $helperScript -Stage $Stage -ProjectPath $ProjectPath 2>$null | Out-Null
        }
    }
    catch {
        # Silently ignore workflow stage update errors - visualization is non-critical
        Write-Verbose "[WORKFLOW] Failed to update stage: $_"
    }
}


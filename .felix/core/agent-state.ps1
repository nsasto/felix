<#
.SYNOPSIS
Formal state machine for Felix agent execution
#>

class AgentState {
    [string]$Mode
    [string]$RequirementId
    [string]$Branch
    [hashtable]$Context
    [datetime]$StartTime
    [int]$IterationCount

    AgentState([string]$mode) {
        $this.Mode = $mode
        $this.Context = @{}
        $this.StartTime = Get-Date
        $this.IterationCount = 0
    }

    [hashtable] GetValidTransitions() {
        return @{
            'Planning'   = @('Building', 'Blocked', 'Complete')
            'Building'   = @('Validating', 'Blocked')
            'Validating' = @('Complete', 'Building', 'Blocked')
            'Blocked'    = @('Planning')
            'Complete'   = @()  # Terminal state
        }
    }

    [bool] CanTransitionTo([string]$newMode) {
        $validTransitions = $this.GetValidTransitions()
        return $validTransitions[$this.Mode] -contains $newMode
    }

    [void] TransitionTo([string]$newMode) {
        if (-not $this.CanTransitionTo($newMode)) {
            throw "Invalid state transition: $($this.Mode) -> $newMode. Valid transitions: $($this.GetValidTransitions()[$this.Mode] -join ', ')"
        }

        Write-Verbose "State transition: $($this.Mode) -> $newMode (Iteration: $($this.IterationCount))"
        $this.Mode = $newMode
        $this.IterationCount++
    }

    [hashtable] ToJson() {
        return @{
            mode           = $this.Mode
            requirementId  = $this.RequirementId
            branch         = $this.Branch
            iterationCount = $this.IterationCount
            startTime      = $this.StartTime.ToString('o')
            context        = $this.Context
        }
    }
}

function New-AgentState {
    param([string]$InitialMode = 'Planning')
    return [AgentState]::new($InitialMode)
}


<#
.SYNOPSIS
Tests for agent state machine
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-state.ps1"

Describe "AgentState Initialization" {

    It "should initialize with Planning mode by default" {
        $state = New-AgentState
        Assert-Equal "Planning" $state.Mode
    }

    It "should initialize with custom mode" {
        $state = New-AgentState -InitialMode "Building"
        Assert-Equal "Building" $state.Mode
    }

    It "should initialize iteration count to 0" {
        $state = New-AgentState
        Assert-Equal 0 $state.IterationCount
    }

    It "should set start time" {
        $state = New-AgentState
        Assert-NotNull $state.StartTime
    }
}

Describe "State Transitions" {

    It "should allow Planning to Building transition" {
        $state = New-AgentState
        $state.TransitionTo('Building')
        Assert-Equal "Building" $state.Mode
    }

    It "should allow Building to Validating transition" {
        $state = New-AgentState -InitialMode "Building"
        $state.TransitionTo('Validating')
        Assert-Equal "Validating" $state.Mode
    }

    It "should allow Validating to Complete transition" {
        $state = New-AgentState -InitialMode "Validating"
        $state.TransitionTo('Complete')
        Assert-Equal "Complete" $state.Mode
    }

    It "should allow any state to Blocked transition" {
        $state = New-AgentState -InitialMode "Building"
        $state.TransitionTo('Blocked')
        Assert-Equal "Blocked" $state.Mode
    }

    It "should reject invalid transitions" {
        $state = New-AgentState -InitialMode "Building"
        Assert-Throws { $state.TransitionTo('Planning') }
    }

    It "should not allow transition from Complete" {
        $state = New-AgentState -InitialMode "Complete"
        Assert-Throws { $state.TransitionTo('Planning') }
    }

    It "should increment iteration count on transition" {
        $state = New-AgentState
        Assert-Equal 0 $state.IterationCount
        $state.TransitionTo('Building')
        Assert-Equal 1 $state.IterationCount
        $state.TransitionTo('Validating')
        Assert-Equal 2 $state.IterationCount
    }
}

Describe "State Context Management" {

    It "should store context data" {
        $state = New-AgentState
        $state.Context['key'] = 'value'
        Assert-Equal 'value' $state.Context['key']
    }

    It "should store requirement ID" {
        $state = New-AgentState
        $state.RequirementId = 'S-0001'
        Assert-Equal 'S-0001' $state.RequirementId
    }
}

Describe "State Serialization" {

    It "should convert to JSON hashtable" {
        $state = New-AgentState
        $state.RequirementId = 'S-0001'
        $state.Branch = 'feature/S-0001'

        $json = $state.ToJson()

        Assert-Equal 'Planning' $json.mode
        Assert-Equal 'S-0001' $json.requirementId
        Assert-Equal 'feature/S-0001' $json.branch
        Assert-NotNull $json.startTime
    }
}

Get-TestResults

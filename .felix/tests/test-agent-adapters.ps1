<#
.SYNOPSIS
Tests for agent-adapters.ps1 adapter pattern
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/agent-adapters.ps1"

Describe "Get-AgentAdapter" {

    It "should return DroidAdapter for droid" {
        $adapter = Get-AgentAdapter -AdapterType "droid"
        Assert-NotNull $adapter
        Assert-Equal "DroidAdapter" $adapter.GetType().Name
    }

    It "should return ClaudeAdapter for claude" {
        $adapter = Get-AgentAdapter -AdapterType "claude"
        Assert-NotNull $adapter
        Assert-Equal "ClaudeAdapter" $adapter.GetType().Name
    }

    It "should return CodexAdapter for codex" {
        $adapter = Get-AgentAdapter -AdapterType "codex"
        Assert-NotNull $adapter
        Assert-Equal "CodexAdapter" $adapter.GetType().Name
    }

    It "should return GeminiAdapter for gemini" {
        $adapter = Get-AgentAdapter -AdapterType "gemini"
        Assert-NotNull $adapter
        Assert-Equal "GeminiAdapter" $adapter.GetType().Name
    }

    It "should return CopilotAdapter for copilot" {
        $adapter = Get-AgentAdapter -AdapterType "copilot"
        Assert-NotNull $adapter
        Assert-Equal "CopilotAdapter" $adapter.GetType().Name
    }

    It "should be case insensitive" {
        $adapter = Get-AgentAdapter -AdapterType "DROID"
        Assert-NotNull $adapter
        Assert-Equal "DroidAdapter" $adapter.GetType().Name
    }
}

Describe "Get-AgentDefaults" {

    It "should return droid defaults" {
        $defaults = Get-AgentDefaults -AdapterType "droid"
        Assert-Equal "droid" $defaults.adapter
        Assert-Equal "droid" $defaults.executable
        Assert-NotNull $defaults.model
    }

    It "should return claude defaults" {
        $defaults = Get-AgentDefaults -AdapterType "claude"
        Assert-Equal "claude" $defaults.adapter
        Assert-Equal "claude" $defaults.executable
    }

    It "should return codex defaults" {
        $defaults = Get-AgentDefaults -AdapterType "codex"
        Assert-Equal "codex" $defaults.adapter
    }

    It "should return gemini defaults" {
        $defaults = Get-AgentDefaults -AdapterType "gemini"
        Assert-Equal "gemini" $defaults.adapter
    }

    It "should return copilot defaults" {
        $defaults = Get-AgentDefaults -AdapterType "copilot"
        Assert-Equal "copilot" $defaults.adapter
        Assert-Equal "copilot" $defaults.executable
        Assert-Equal "auto" $defaults.model
        Assert-True $defaults.allow_all
        Assert-True $defaults.no_ask_user
    }

    It "should handle unknown adapter type" {
        $defaults = Get-AgentDefaults -AdapterType "custom"
        Assert-Equal "custom" $defaults.adapter
        Assert-Equal "custom" $defaults.executable
    }
}

Describe "DroidAdapter.FormatPrompt" {

    It "should return prompt unchanged" {
        $adapter = [DroidAdapter]::new()
        $result = $adapter.FormatPrompt("test prompt")
        Assert-Equal "test prompt" $result
    }
}

Describe "DroidAdapter.DetectCompletion" {

    It "should detect PLANNING_COMPLETE signal" {
        $adapter = [DroidAdapter]::new()
        $output = "<promise> PLANNING_COMPLETE </promise>"
        Assert-True ($adapter.DetectCompletion($output))
    }

    It "should detect TASK_COMPLETE signal" {
        $adapter = [DroidAdapter]::new()
        $output = "<promise> TASK_COMPLETE </promise>"
        Assert-True ($adapter.DetectCompletion($output))
    }

    It "should detect ALL_COMPLETE signal" {
        $adapter = [DroidAdapter]::new()
        $output = "<promise> ALL_COMPLETE </promise>"
        Assert-True ($adapter.DetectCompletion($output))
    }

    It "should return false for no signal" {
        $adapter = [DroidAdapter]::new()
        $output = "Just some regular output"
        Assert-False ($adapter.DetectCompletion($output))
    }
}

Describe "DroidAdapter.ParseResponse" {

    It "should detect PLANNING_COMPLETE in XML" {
        $adapter = [DroidAdapter]::new()
        $result = $adapter.ParseResponse("Some output`n<promise> PLANNING_COMPLETE </promise>")
        Assert-True $result.IsComplete
        Assert-Equal "building" $result.NextMode
    }

    It "should detect TASK_COMPLETE in XML" {
        $adapter = [DroidAdapter]::new()
        $result = $adapter.ParseResponse("Output`n<promise> TASK_COMPLETE </promise>")
        Assert-True $result.IsComplete
        Assert-Equal "continue" $result.NextMode
    }

    It "should detect ALL_COMPLETE in XML" {
        $adapter = [DroidAdapter]::new()
        $result = $adapter.ParseResponse("Output`n<promise> ALL_COMPLETE </promise>")
        Assert-True $result.IsComplete
        Assert-Equal "complete" $result.NextMode
    }

    It "should return not complete for plain output" {
        $adapter = [DroidAdapter]::new()
        $result = $adapter.ParseResponse("Just regular output")
        Assert-False $result.IsComplete
        Assert-Null $result.NextMode
    }

    It "should extract plain text from droid success JSON" {
        $adapter = [DroidAdapter]::new()
        $result = $adapter.ParseResponse('{"type":"result","subtype":"success","is_error":false,"result":"Updated CONTEXT.md successfully"}')
        Assert-Equal "Updated CONTEXT.md successfully" $result.Output
        Assert-Null $result.Error
    }
}

Describe "ClaudeAdapter.FormatPrompt" {

    It "should return prompt unchanged" {
        $adapter = [ClaudeAdapter]::new()
        $result = $adapter.FormatPrompt("test prompt")
        Assert-Equal "test prompt" $result
    }
}

Describe "ClaudeAdapter.DetectCompletion" {

    It "should detect planning complete signal" {
        $adapter = [ClaudeAdapter]::new()
        $output = "planning complete"
        Assert-True ($adapter.DetectCompletion($output))
    }

    It "should return false for no signal" {
        $adapter = [ClaudeAdapter]::new()
        Assert-False ($adapter.DetectCompletion("no signal here"))
    }
}

Describe "Get-AgentInvocation" {

    It "should use stdin prompt transport for droid" {
        $config = [pscustomobject]@{ adapter = "droid"; model = "claude-opus-4-5-20251101" }
        $invocation = Get-AgentInvocation -AdapterType "droid" -Config $config -Prompt "test prompt" -VerboseMode $false
        Assert-Equal "stdin" $invocation.PromptMode
        Assert-Equal "test prompt" $invocation.FormattedPrompt
        Assert-Contains $invocation.Arguments "exec"
    }

    It "should use argument prompt transport for copilot" {
        $config = [pscustomobject]@{
            adapter                 = "copilot"
            model                   = "gpt-5.4"
            allow_all               = $true
            no_ask_user             = $true
            max_autopilot_continues = 5
            custom_agent            = "general-purpose"
        }
        $invocation = Get-AgentInvocation -AdapterType "copilot" -Config $config -Prompt "test prompt" -VerboseMode $false
        Assert-Equal "argument" $invocation.PromptMode
        Assert-Equal "test prompt" $invocation.FormattedPrompt
        Assert-Contains $invocation.Arguments "--autopilot"
        Assert-Contains $invocation.Arguments "--yolo"
        Assert-Contains $invocation.Arguments "--no-ask-user"
        Assert-Contains $invocation.Arguments "--agent"
        Assert-Contains $invocation.Arguments "general-purpose"
        Assert-Contains $invocation.Arguments "-p"
        Assert-Contains $invocation.Arguments "test prompt"
    }
}

Describe "CopilotAdapter.ParseResponse" {

    It "should detect ALL_COMPLETE in XML" {
        $adapter = [CopilotAdapter]::new()
        $result = $adapter.ParseResponse("Output`n<promise> ALL_COMPLETE </promise>")
        Assert-True $result.IsComplete
        Assert-Equal "complete" $result.NextMode
    }
}

Get-TestResults

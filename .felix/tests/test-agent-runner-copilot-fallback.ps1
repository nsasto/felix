. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-runner.ps1"

Describe "Copilot runner fallback helpers" {

    It "should remove a model flag and its value" {
        $inputValues = @("--autopilot", "--model", "gpt-5.4", "-p", "hello")
        $filtered = Remove-ArgumentPair -Arguments $inputValues -Flag "--model"

        Assert-Equal 3 $filtered.Count
        Assert-Contains $filtered "--autopilot"
        Assert-Contains $filtered "-p"
        Assert-Contains $filtered "hello"
        Assert-False ($filtered -contains "--model")
        Assert-False ($filtered -contains "gpt-5.4")
    }

    It "should detect Copilot unavailable-model output" {
        Assert-True (Test-CopilotModelUnavailableOutput -Output 'Error: Model "gpt-5.4" from --model flag is not available.')
        Assert-False (Test-CopilotModelUnavailableOutput -Output 'Some other Copilot failure')
    }

    It "should successfully invoke the retry command without the explicit model" {
        $shimScript = Join-Path $PSScriptRoot "agent-shim-copilot-retry.cmd"
        Assert-True (Test-Path $shimScript) "Missing shim script at $shimScript"

        $initialCommand = @(
            "--autopilot",
            "-s",
            "--no-color",
            "--yolo",
            "--no-ask-user",
            "--max-autopilot-continues", "2",
            "--model", "gpt-5.4",
            "-p", "test prompt"
        )

        $retryCommand = Remove-ArgumentPair -Arguments $initialCommand -Flag "--model"
        $retryResult = Invoke-AgentSubprocess `
            -ProcessFilePath $shimScript `
            -ProcessArgs $retryCommand `
            -WorkingDirectory $PSScriptRoot `
            -PromptMode "argument" `
            -Prompt "unused" `
            -StartTime (Get-Date)

        Assert-True $retryResult.Succeeded "Retry invocation should succeed after removing --model"
        Assert-True ($retryResult.Output -match "__COPILOT_MODEL_FALLBACK__=1") "Retry output should include the fallback success marker"
        Assert-False ($retryResult.Output -match "--model") "Retry output should not include the explicit --model argument"
        Assert-False ($retryResult.Output -match "gpt-5.4") "Retry output should not include the removed model value"
    }
}

Get-TestResults
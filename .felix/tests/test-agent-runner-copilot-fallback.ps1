. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-runner.ps1"

function Emit-Artifact { param([string]$Path, [string]$Type, [long]$SizeBytes = 0) }
function Emit-Event { param([string]$EventType, [hashtable]$Data) }
function Emit-Log { param([string]$Level, [string]$Message, [string]$Component = "") }

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

    It "should extract normalized usage from provider JSON output" {
        $output = @(
            '{"type":"system","model":"claude-sonnet-test","session_id":"sess-123"}',
            '{"type":"completion","durationMs":1234,"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40}}'
        ) -join "`n"

        $usage = Get-AgentUsageFromOutput -Output $output -AdapterType "droid"

        Assert-Equal "claude-sonnet-test" $usage.effective_model
        Assert-Equal "sess-123" $usage.session_id
        Assert-Equal 10 $usage.usage.input_tokens
        Assert-Equal 20 $usage.usage.output_tokens
        Assert-Equal 30 $usage.usage.total_tokens
        Assert-Equal 100 $usage.usage.observed_tokens
    }

    It "should write usage.json with model and token details" {
        $tmpDir = Join-Path $env:TEMP "felix-usage-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

        try {
            $agentConfig = [pscustomobject]@{
                key = "ag_test"
                name = "droid"
                provider = "droid"
                adapter = "droid"
                executable = "droid"
                model = "configured-model"
            }
            $output = '{"type":"completion","usage":{"input_tokens":7,"output_tokens":11}}'

            $record = Write-AgentUsageArtifact `
                -AgentConfig $agentConfig `
                -AdapterType "droid" `
                -RunId "S-0001-test" `
                -RunDir $tmpDir `
                -ProjectPath $tmpDir `
                -Output $output `
                -DurationSeconds 1.25 `
                -ExitCode 0 `
                -Succeeded $true

            $usagePath = Join-Path $tmpDir "usage.json"
            Assert-True (Test-Path $usagePath) "usage.json should be written"
            $saved = Get-Content $usagePath -Raw | ConvertFrom-Json
            Assert-Equal "configured-model" $saved.model.effective
            Assert-Equal 7 $saved.usage.input_tokens
            Assert-Equal 11 $saved.usage.output_tokens
            Assert-Equal 18 $saved.usage.total_tokens
            Assert-Equal 18 $record.usage.total_tokens
        }
        finally {
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
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

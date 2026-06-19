. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/compat-utils.ps1"
. "$PSScriptRoot/../core/workflow.ps1"
. "$PSScriptRoot/../core/agent-adapters.ps1"
. "$PSScriptRoot/../core/agent-runner.ps1"

function Emit-Event {
    param([string]$EventType, [hashtable]$Data)
}

function Invoke-PluginHookSafely {
    param([string]$HookName, [string]$RunId, [hashtable]$HookData)
    return @{}
}

Describe "Invoke-AgentSubprocess cmd shim execution" {

    It "should execute a cmd shim through cmd.exe without quoting the path as a literal command" {
        $tempDir = Join-Path $env:TEMP "test-agent-runner-cmd-$(Get-Random)"
        $cmdPath = Join-Path $tempDir "fake-agent.cmd"

        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Set-Content -Path $cmdPath -Value "@echo off`necho CMD_OK" -Encoding ASCII

        try {
            $result = Invoke-AgentSubprocess `
                -ProcessFilePath $cmdPath `
                -ProcessArgs @("--flag") `
                -WorkingDirectory $tempDir `
                -PromptMode "argument" `
                -Prompt "unused" `
                -StartTime (Get-Date)

            Assert-True $result.Succeeded "Expected cmd shim execution to succeed"
            Assert-True ([bool]($result.Output -match "CMD_OK")) "Expected output from cmd shim"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should parse empty output and record usage artifact as unavailable" {
        $tempDir = Join-Path $env:TEMP "test-agent-runner-empty-$(Get-Random)"
        $runDir = Join-Path $tempDir "runs\S-0000-empty-it1"

        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        try {
            $adapter = Get-AgentAdapter -AdapterType "droid"
            $parseInput = Get-AgentParseInput -Output ""
            Assert-Equal "`n" $parseInput "Empty output should be padded for PowerShell class parser binding"
            $parsed = $adapter.ParseResponse($parseInput)
            Assert-Equal "`n" $parsed.Output "Adapter should receive padded parser input"
            Assert-False $parsed.IsComplete "Empty adapter output should not signal completion"

            $agentConfig = [pscustomobject]@{
                key               = "ag_empty"
                name              = "empty"
                adapter           = "droid"
                executable        = "empty-agent"
                model             = "empty-model"
                working_directory = "."
                environment       = @{}
            }

            $record = Write-AgentUsageArtifact `
                -AgentConfig $agentConfig `
                -AdapterType "droid" `
                -RunId "S-0000-empty-it1" `
                -RunDir $runDir `
                -ProjectPath $tempDir `
                -Output "" `
                -DurationSeconds 0.1 `
                -ExitCode 1 `
                -Succeeded $false

            $usagePath = Join-Path $runDir "usage.json"
            Assert-True (Test-Path $usagePath) "usage.json should still be written"

            $usage = Get-Content $usagePath -Raw | ConvertFrom-Json
            Assert-Equal $false $usage.usage_available "Token usage should be unavailable"
            Assert-Equal "empty-model" $usage.model.effective "Configured model should still be recorded"
            Assert-Equal 1 $usage.exit_code "Exit code should be preserved"
            Assert-Equal $false $record.usage_available "Returned record should match saved usage availability"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should spill long argument-mode prompts to a temporary file" {
        $tempDir = Join-Path $env:TEMP "test-agent-runner-long-arg-$(Get-Random)"
        $cmdPath = Join-Path $tempDir "echo-args.cmd"
        $longPrompt = "UNIQUE_LONG_PROMPT_TOKEN " + ("x" * 7000)

        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Set-Content -Path $cmdPath -Value "@echo off`necho ARGS=%*" -Encoding ASCII

        try {
            $result = Invoke-AgentSubprocess `
                -ProcessFilePath $cmdPath `
                -ProcessArgs @("-p", $longPrompt) `
                -WorkingDirectory $tempDir `
                -PromptMode "argument" `
                -Prompt $longPrompt `
                -StartTime (Get-Date)

            Assert-True $result.Succeeded "Expected long argument prompt shim to succeed"
            Assert-True ($result.Output -match "Read the Felix prompt from this file") "Expected short file instruction in argv"
            Assert-False ($result.Output -match "UNIQUE_LONG_PROMPT_TOKEN") "Long prompt content should not be passed directly in argv"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults

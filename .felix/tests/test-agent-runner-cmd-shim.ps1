. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/agent-runner.ps1"

function Emit-Event {
    param([string]$EventType, [hashtable]$Data)
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
}

Get-TestResults

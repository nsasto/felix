. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/agent-runner.ps1"

$script:ObservedStreamChunks = @()

function Emit-Event {
    param([string]$EventType, [hashtable]$Data)
}

function Emit-AgentStreamChunk {
    param([string]$Stream, [string]$Content)
    $script:ObservedStreamChunks += @([pscustomobject]@{
            Stream  = $Stream
            Content = $Content
        })
}

Describe "Invoke-AgentSubprocess verbose streaming" {

    It "should emit stdout chunks while verbose mode is enabled" {
        $script:ObservedStreamChunks = @()

        $result = Invoke-AgentSubprocess `
            -ProcessFilePath "powershell.exe" `
            -ProcessArgs @(
                "-NoProfile",
                "-Command",
                "Write-Output 'first'; Start-Sleep -Milliseconds 700; Write-Output 'second'"
            ) `
            -WorkingDirectory $PWD `
            -PromptMode "argument" `
            -Prompt "unused" `
            -StartTime (Get-Date) `
            -VerboseMode:$true

        Assert-True $result.Succeeded "Expected subprocess to succeed"
        Assert-True (($script:ObservedStreamChunks | Where-Object { $_.Stream -eq "stdout" }).Count -ge 2) "Expected multiple stdout stream chunks"
        Assert-True (($script:ObservedStreamChunks.Content -contains "first")) "Expected first stdout line to be streamed"
        Assert-True (($script:ObservedStreamChunks.Content -contains "second")) "Expected second stdout line to be streamed"
    }
}

Get-TestResults

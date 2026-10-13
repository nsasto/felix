Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Invoke-Felix3Process.ps1')

function ConvertFrom-CodexEventStream {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output)
    $events = @()
    foreach ($line in ($Output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try { $events += ($line | ConvertFrom-Json -ErrorAction Stop) } catch { }
    }
    $messages = @()
    $threadId = $null
    $usage = $null
    $failure = $null
    $completed = $false
    foreach ($event in $events) {
        $type = Get-Felix3ProcessProperty $event 'type'
        $eventThreadId = Get-Felix3ProcessProperty $event 'thread_id'
        $item = Get-Felix3ProcessProperty $event 'item'
        if ($eventThreadId) { $threadId = [string]$eventThreadId }
        if ($type -eq 'item.completed' -and (Get-Felix3ProcessProperty $item 'type') -eq 'agent_message' -and (Get-Felix3ProcessProperty $item 'text')) {
            $messages += [string](Get-Felix3ProcessProperty $item 'text')
        }
        if ($type -eq 'turn.completed') { $completed = $true; if (Get-Felix3ProcessProperty $event 'usage') { $usage = Get-Felix3ProcessProperty $event 'usage' } }
        if ($type -eq 'turn.failed') {
            $eventError = Get-Felix3ProcessProperty $event 'error'
            $failure = if (Get-Felix3ProcessProperty $eventError 'message') { [string](Get-Felix3ProcessProperty $eventError 'message') } else { 'Codex reported a failed turn.' }
        }
        if ($type -eq 'error' -and (Get-Felix3ProcessProperty $event 'message')) { $failure = [string](Get-Felix3ProcessProperty $event 'message') }
    }
    return @{
        IsValid = ($events.Count -gt 0)
        Completed = $completed
        Text = $messages -join "`n"
        ThreadId = $threadId
        Usage = $usage
        Error = $failure
        Events = $events.Count
    }
}

function Invoke-CodexHarness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('planning', 'building', 'reviewing')][string]$Phase,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [string]$Executable = 'codex',
        [string]$Model,
        [string]$Sandbox = 'read-only',
        [string]$ApprovalPolicy = 'on-request',
        [string]$SessionId,
        $Journal,
        [scriptblock]$EventSink,
        [string]$CancelTokenPath
    )
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw "Working directory does not exist: $WorkingDirectory" }
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt must not be empty.' }
    if (-not [System.IO.Path]::IsPathRooted($RunDirectory)) { $RunDirectory = Join-Path $WorkingDirectory $RunDirectory }
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) { New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null }
    $RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
    $resolvedExe = Resolve-Felix3Executable -Executable $Executable
    $lastMessagePath = Join-Path $RunDirectory 'codex-last-message.txt'
    if ($SessionId) {
        $arguments = @('exec', 'resume', '--json', '-c', "approval_policy=`"$ApprovalPolicy`"", '-c', "sandbox_mode=`"$Sandbox`"", '-o', $lastMessagePath, $SessionId, '-')
        if ($Model) { $arguments += @('-m', $Model) }
    }
    else {
        $arguments = @('exec', '--json', '-C', (Resolve-Path -LiteralPath $WorkingDirectory).Path, '-s', $Sandbox, '-c', "approval_policy=`"$ApprovalPolicy`"", '-o', $lastMessagePath, '-')
        if ($Model) { $arguments += @('-m', $Model) }
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $argumentString = ConvertTo-Felix3ArgumentString -Arguments $arguments
    if ($resolvedExe -match '\.(cmd|bat)$') {
        $startInfo.FileName = $env:ComSpec
        $startInfo.Arguments = '/d /s /c ""' + $resolvedExe + '" ' + $argumentString + '"'
    }
    else { $startInfo.FileName = $resolvedExe; $startInfo.Arguments = $argumentString }
    $startInfo.WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($name in @('StandardInputEncoding', 'StandardOutputEncoding', 'StandardErrorEncoding')) {
        $property = $startInfo.GetType().GetProperty($name)
        if ($property -and $property.CanWrite) { $property.SetValue($startInfo, $utf8, $null) }
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $startedAt = [DateTime]::UtcNow
    $rawPath = Join-Path $RunDirectory 'codex-events.jsonl'
    $stderrPath = Join-Path $RunDirectory 'codex-stderr.log'
    try {
        if ($EventSink) { & $EventSink 'phase.started' @{ phase = $Phase } "Harness phase started ($Phase)." }
        $onLine = {
            param($line)
            if (-not $EventSink) { return }
            try {
                $e = $line | ConvertFrom-Json -ErrorAction Stop
                $type = [string]$e.type
                $kind = switch ($type) {
                    'thread.started' { 'session.started' }
                    'turn.started' { 'turn.started' }
                    'item.started' { if ($e.item.type -eq 'command_execution' -or $e.item.type -eq 'mcp_tool_call') { 'tool.started' } else { 'assistant.message' } }
                    'item.completed' { if ($e.item.type -eq 'agent_message') { 'output.delta' } elseif ($e.item.type -eq 'command_execution' -or $e.item.type -eq 'mcp_tool_call') { 'tool.completed' } else { 'harness.event' } }
                    'turn.completed' { 'turn.completed' }
                    'turn.failed' { 'phase.failed' }
                    'error' { 'phase.failed' }
                    default { 'harness.event' }
                }
                $summary = if ($type -eq 'item.completed' -and $e.item.type -eq 'agent_message') { [string]$e.item.text } elseif ($type -eq 'item.started') { "Codex item started: $($e.item.type)" } elseif ($type -eq 'turn.completed') { 'Codex turn completed.' } else { "Codex event: $type" }
                $payload = @{ provider_event = $type; session_id = [string]$e.thread_id; item_type = [string]$e.item.type }
                if ($type -eq 'turn.completed') { $payload.usage = $e.usage }
                return (& $EventSink $kind $payload $summary)
            } catch { }
        }.GetNewClosure()
        $onErrorLine = { param($line) if ($EventSink) { & $EventSink 'harness.stderr' @{} $line } }.GetNewClosure()
        $onStart = { param($pid) if ($EventSink) { & $EventSink 'harness.process.started' @{ process_id = $pid; session_id = $null } "Codex process started (pid $pid)." } }.GetNewClosure()
        $onExit = { param($pid,$cancelled) if ($EventSink) { & $EventSink 'harness.process.exited' @{ process_id = $pid; cancelled = $cancelled } 'Codex process exited.' } }.GetNewClosure()
        $processOutput = Invoke-Felix3Process -Process $process -Prompt $Prompt -RawOutputPath $rawPath -StderrPath $stderrPath -OnOutputLine $onLine -OnErrorLine $onErrorLine -CancelTokenPath $CancelTokenPath -OnProcessStart $onStart -OnProcessExit $onExit
        $stdout = $processOutput.Stdout
        $stderr = $processOutput.Stderr
        $parsed = ConvertFrom-CodexEventStream -Output $stdout
        $exitCode = $processOutput.ExitCode
        $succeeded = ($exitCode -eq 0 -and $parsed.IsValid -and $parsed.Completed -and -not $parsed.Error)
        $finishedAt = [DateTime]::UtcNow
        $resultPath = Join-Path $RunDirectory 'harness-result.json'
        $resultText = if (Test-Path -LiteralPath $lastMessagePath -PathType Leaf) { Get-Content -LiteralPath $lastMessagePath -Raw -Encoding UTF8 } else { $parsed.Text }
        if ($resultText) { Set-Content -LiteralPath $lastMessagePath -Value $resultText -Encoding UTF8 }
        $errorText = if ($processOutput.QuestionRequested) { $null } elseif ($parsed.Error) { $parsed.Error } elseif (-not $parsed.IsValid) { 'Codex did not return recognized JSONL events.' } elseif (-not $parsed.Completed) { 'Codex exited without a completed turn event.' } elseif ($exitCode -ne 0) { "Codex exited with code $exitCode." } else { $null }
        [ordered]@{
            schema = 'felix3-harness-result-v1'; harness = 'codex'; phase = $Phase
            status = if ($processOutput.QuestionRequested) { 'needs-input' } elseif ($succeeded) { 'succeeded' } else { 'failed' }
            started_at = $startedAt.ToString('o'); finished_at = $finishedAt.ToString('o')
            duration_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 2)
            exit_code = $exitCode; session_id = $parsed.ThreadId; model = $Model; sandbox = $Sandbox; approval_policy = $ApprovalPolicy
            text = $resultText; error = $errorText; usage = $parsed.Usage; cost_usd = $null; event_count = $parsed.Events
            artifacts = @('codex-events.jsonl', 'codex-stderr.log', 'codex-last-message.txt')
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        if ($Journal) {
            $usageRecord = ConvertTo-Felix3UsageRecord -Harness 'codex' -Phase $Phase -PhaseInstance (Split-Path $RunDirectory -Leaf) -Model $Model -Usage $parsed.Usage -CostUsd $null -DurationSeconds (($finishedAt - $startedAt).TotalSeconds) -SessionId $parsed.ThreadId
            Update-Felix3UsageSummary -RunDirectory $Journal.RunDirectory -UsageRecord $usageRecord | Out-Null
        }
        if ($EventSink -and -not $processOutput.QuestionRequested) { & $EventSink $(if ($succeeded) { 'phase.completed' } else { 'phase.failed' }) @{ exit_code = $exitCode; event_count = $parsed.Events; session_id = $parsed.ThreadId; usage = $parsed.Usage; model = $Model } $(if ($succeeded) { "Harness phase completed ($Phase)." } else { "Harness phase failed ($Phase): $errorText" }) }
        if ($parsed.ThreadId) {
            [ordered]@{ schema = 'felix3-codex-session-v1'; harness = 'codex'; session_id = $parsed.ThreadId; phase = $Phase; working_directory = $startInfo.WorkingDirectory; model = $Model; updated_at = $finishedAt.ToString('o') } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $RunDirectory 'codex-session.json') -Encoding UTF8
        }
        return [pscustomobject]@{
            Harness = 'codex'; Succeeded = $succeeded; Interrupted = $processOutput.Cancelled; NeedsInput = $processOutput.QuestionRequested; ExitCode = $exitCode; Phase = $Phase; SessionId = $parsed.ThreadId
            ResultText = $resultText; Error = $errorText; Usage = $parsed.Usage; CostUsd = $null
            Turns = $null; ResultPath = $resultPath; RawOutputPath = $rawPath; StderrPath = $stderrPath
            SessionPath = if ($parsed.ThreadId) { Join-Path $RunDirectory 'codex-session.json' } else { $null }
        }
    }
    finally { $process.Dispose() }
}

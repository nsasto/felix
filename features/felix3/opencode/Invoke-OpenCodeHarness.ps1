Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Invoke-Felix3Process.ps1')

function ConvertFrom-OpenCodeEventStream {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output)
    $events = @()
    foreach ($line in ($Output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try { $events += ($line | ConvertFrom-Json -ErrorAction Stop) }
        catch { }
    }
    $textParts = @()
    $sessionId = $null
    $finished = $null
    $eventError = $null
    $stepCount = 0
    foreach ($event in $events) {
        if (-not $sessionId -and $event.PSObject.Properties['sessionID']) { $sessionId = [string]$event.sessionID }
        if ($event.PSObject.Properties['type'] -and $event.type -eq 'text' -and $event.PSObject.Properties['part'] -and $event.part.PSObject.Properties['text']) {
            $textParts += [string]$event.part.text
        }
        if ($event.PSObject.Properties['type'] -and $event.type -eq 'step_finish') { $finished = $event; $stepCount++ }
        if ($event.PSObject.Properties['type'] -and $event.type -eq 'error') { $eventError = $event }
    }
    $text = $textParts -join "`n"
    return @{
        IsValid = ($events.Count -gt 0)
        Completed = ($stepCount -gt 0)
        Error = if ($eventError -and $eventError.PSObject.Properties['message']) { [string]$eventError.message } else { $null }
        Text = $text
        SessionId = $sessionId
        Usage = if ($finished -and $finished.PSObject.Properties['part'] -and $finished.part.PSObject.Properties['tokens']) { $finished.part.tokens } else { $null }
        CostUsd = if ($finished -and $finished.PSObject.Properties['part'] -and $finished.part.PSObject.Properties['cost']) { [double]$finished.part.cost } else { $null }
        Turns = $stepCount
        Events = $events.Count
    }
}

function Invoke-OpenCodeHarness {
    <# Runs one Felix phase through OpenCode's native non-interactive run loop. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('planning', 'building', 'reviewing')][string]$Phase,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [string]$Executable = 'opencode',
        [string]$Model,
        [string]$Agent,
        [string]$SessionId,
        [switch]$AutoApprove,
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
    $arguments = @('run', '--format', 'json', '--dir', (Resolve-Path -LiteralPath $WorkingDirectory).Path)
    if ($Model) { $arguments += @('--model', $Model) }
    if ($Agent) { $arguments += @('--agent', $Agent) }
    if ($SessionId) { $arguments += @('--session', $SessionId) }
    if ($AutoApprove) { $arguments += '--auto' }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $argumentString = ConvertTo-Felix3ArgumentString -Arguments $arguments
    if ($resolvedExe -match '\.(cmd|bat)$') {
        $startInfo.FileName = $env:ComSpec
        $startInfo.Arguments = '/d /s /c ""' + $resolvedExe + '" ' + $argumentString + '"'
    }
    else {
        $startInfo.FileName = $resolvedExe
        $startInfo.Arguments = $argumentString
    }
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
    $rawPath = Join-Path $RunDirectory 'opencode-events.jsonl'
    $stderrPath = Join-Path $RunDirectory 'opencode-stderr.log'
    try {
        if ($EventSink) { & $EventSink 'phase.started' @{ phase = $Phase } "Harness phase started ($Phase)." }
        $onLine = {
            param($line)
            if (-not $EventSink) { return }
            try {
                $e = $line | ConvertFrom-Json -ErrorAction Stop
                $type = [string]$e.type
                $kind = switch ($type) {
                    'text' { 'output.delta' }
                    'tool_use' { if ($e.part.tool -eq 'question' -and $e.part.state.status -ne 'completed') { 'question.requested' } elseif ($e.part.state.status -eq 'completed') { 'tool.completed' } else { 'tool.started' } }
                    'step_finish' { 'turn.completed' }
                    'error' { 'phase.failed' }
                    default { 'harness.event' }
                }
                $summary = if ($type -eq 'tool_use') { "Tool: $($e.part.tool)" } elseif ($type -eq 'text') { [string]$e.part.text } elseif ($type -eq 'error') { [string]$e.message } else { "OpenCode event: $type" }
                $payload = @{ provider_event = $type; session_id = [string]$e.sessionID }
                if ($e.part.tool) { $payload.tool = [string]$e.part.tool }
                if ($type -eq 'tool_use' -and $e.part.tool -eq 'question' -and $kind -eq 'question.requested') { $payload.question = $e.part.state.input.questions }
                if ($type -eq 'step_finish') { $payload.usage = $e.part.tokens; $payload.cost_usd = $e.part.cost }
                return (& $EventSink $kind $payload $summary)
            } catch { }
        }.GetNewClosure()
        $onErrorLine = { param($line) if ($EventSink) { & $EventSink 'harness.stderr' @{} $line } }.GetNewClosure()
        $onStart = { param($pid) if ($EventSink) { & $EventSink 'harness.process.started' @{ process_id = $pid; session_id = $null } "OpenCode process started (pid $pid)." } }.GetNewClosure()
        $onExit = { param($pid,$cancelled) if ($EventSink) { & $EventSink 'harness.process.exited' @{ process_id = $pid; cancelled = $cancelled } 'OpenCode process exited.' } }.GetNewClosure()
        $processOutput = Invoke-Felix3Process -Process $process -Prompt $Prompt -RawOutputPath $rawPath -StderrPath $stderrPath -OnOutputLine $onLine -OnErrorLine $onErrorLine -CancelTokenPath $CancelTokenPath -OnProcessStart $onStart -OnProcessExit $onExit
        $stdout = $processOutput.Stdout
        $stderr = $processOutput.Stderr
        $parsed = ConvertFrom-OpenCodeEventStream -Output $stdout
        $exitCode = $processOutput.ExitCode
        $succeeded = ($exitCode -eq 0 -and $parsed.IsValid -and $parsed.Completed -and -not $parsed.Error)
        $finishedAt = [DateTime]::UtcNow
        $resultPath = Join-Path $RunDirectory 'harness-result.json'
        $sessionPath = Join-Path $RunDirectory 'opencode-session.json'
        $errorText = if ($processOutput.QuestionRequested) { $null } elseif ($parsed.Error) { $parsed.Error } elseif (-not $parsed.IsValid) { 'OpenCode did not return any recognized JSON events.' } elseif (-not $parsed.Completed) { 'OpenCode exited without a completed step event.' } elseif ($exitCode -ne 0) { "OpenCode exited with code $exitCode." } else { $null }
        [ordered]@{
            schema = 'felix3-harness-result-v1'; harness = 'opencode'; phase = $Phase
            status = if ($processOutput.QuestionRequested) { 'needs-input' } elseif ($succeeded) { 'succeeded' } else { 'failed' }
            started_at = $startedAt.ToString('o'); finished_at = $finishedAt.ToString('o')
            duration_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 2)
            exit_code = $exitCode; session_id = $parsed.SessionId; model = $Model; agent = $Agent
            text = $parsed.Text; error = $errorText; usage = $parsed.Usage; cost_usd = $parsed.CostUsd
            turns = $parsed.Turns; event_count = $parsed.Events
            artifacts = @('opencode-events.jsonl', 'opencode-stderr.log')
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        if ($Journal) {
            $usageRecord = ConvertTo-Felix3UsageRecord -Harness 'opencode' -Phase $Phase -PhaseInstance (Split-Path $RunDirectory -Leaf) -Model $Model -Usage $parsed.Usage -CostUsd $parsed.CostUsd -DurationSeconds (($finishedAt - $startedAt).TotalSeconds) -SessionId $parsed.SessionId
            Update-Felix3UsageSummary -RunDirectory $Journal.RunDirectory -UsageRecord $usageRecord | Out-Null
        }
        if ($EventSink -and -not $processOutput.QuestionRequested) { & $EventSink $(if ($succeeded) { 'phase.completed' } else { 'phase.failed' }) @{ exit_code = $exitCode; event_count = $parsed.Events; session_id = $parsed.SessionId; usage = $parsed.Usage; cost_usd = $parsed.CostUsd; model = $Model } $(if ($succeeded) { "Harness phase completed ($Phase)." } else { "Harness phase failed ($Phase): $errorText" }) }
        if ($parsed.SessionId) {
            [ordered]@{ schema = 'felix3-opencode-session-v1'; harness = 'opencode'; session_id = $parsed.SessionId; phase = $Phase; working_directory = $startInfo.WorkingDirectory; model = $Model; agent = $Agent; updated_at = $finishedAt.ToString('o') } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sessionPath -Encoding UTF8
        }
        return [pscustomobject]@{
            Harness = 'opencode'; Succeeded = $succeeded; Interrupted = $processOutput.Cancelled; NeedsInput = $processOutput.QuestionRequested; ExitCode = $exitCode; Phase = $Phase; SessionId = $parsed.SessionId
            ResultText = $parsed.Text; Error = $errorText; Usage = $parsed.Usage; CostUsd = $parsed.CostUsd
            Turns = $parsed.Turns; ResultPath = $resultPath; RawOutputPath = $rawPath; StderrPath = $stderrPath
            SessionPath = if ($parsed.SessionId) { $sessionPath } else { $null }
        }
    }
    finally { $process.Dispose() }
}

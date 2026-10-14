Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Invoke-Felix3Process.ps1')

function ConvertFrom-ClaudeHarnessResponse {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output)

    $resultEvent = $null
    try {
        $parsed = $Output | ConvertFrom-Json -ErrorAction Stop
        if ($parsed.type -eq 'result') { $resultEvent = $parsed }
    }
    catch {
        # Verbose Claude Code output is newline-delimited JSON; inspect the final
        # result event while retaining the complete raw stream as an artifact.
        foreach ($line in ($Output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
                if ($event.type -eq 'result') { $resultEvent = $event }
            }
            catch { }
        }
    }

    if (-not $resultEvent) {
        return @{
            IsValid = $false
            Error = 'Claude Code did not return a recognized result event.'
            Text = $Output
            SessionId = $null
            Usage = $null
            CostUsd = $null
            Turns = $null
        }
    }

    $errorText = $null
    if ((Get-Felix3ProcessProperty $resultEvent 'is_error') -or (Get-Felix3ProcessProperty $resultEvent 'subtype') -eq 'error') {
        $errorText = if (Get-Felix3ProcessProperty $resultEvent 'result') { [string](Get-Felix3ProcessProperty $resultEvent 'result') } else { 'Claude Code reported an error.' }
    }

    return @{
        IsValid = ($null -eq $errorText)
        Error = $errorText
        Text = [string](Get-Felix3ProcessProperty $resultEvent 'result')
        SessionId = [string](Get-Felix3ProcessProperty $resultEvent 'session_id')
        Usage = Get-Felix3ProcessProperty $resultEvent 'usage'
        CostUsd = Get-Felix3ProcessProperty $resultEvent 'total_cost_usd'
        Turns = Get-Felix3ProcessProperty $resultEvent 'num_turns'
    }
}

function Invoke-ClaudeHarness {
    <#
    .SYNOPSIS
    Runs one Felix phase through Claude Code's native headless harness.

    .DESCRIPTION
    The caller owns phase prompts and Felix workflow state. Claude Code owns its
    internal agent/tool loop. This function records the raw response, normalized
    result, and resumable Claude session metadata in the supplied run directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('planning', 'building', 'reviewing')][string]$Phase,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [string]$Executable = 'claude',
        [string]$Model,
        [string]$PermissionMode = 'default',
        [string[]]$AllowedTools = @(),
        [string]$SessionId,
        [ValidateRange(1, 500)][int]$MaxTurns = 100,
        $Journal,
        [scriptblock]$EventSink,
        [string]$CancelTokenPath
    )

    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        throw "Working directory does not exist: $WorkingDirectory"
    }
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw 'Prompt must not be empty.'
    }
    if (-not [System.IO.Path]::IsPathRooted($RunDirectory)) {
        $RunDirectory = Join-Path $WorkingDirectory $RunDirectory
    }
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null
    }
    $RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path

    $resolvedExe = Resolve-Felix3Executable -Executable $Executable
    $arguments = @('-p', '--output-format', 'stream-json', '--include-partial-messages', '--verbose', '--max-turns', [string]$MaxTurns)
    if ($Model) { $arguments += @('--model', $Model) }
    if ($PermissionMode) { $arguments += @('--permission-mode', $PermissionMode) }
    $allowedToolList = @($AllowedTools | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($allowedToolList.Count -gt 0) { $arguments += @('--allowedTools') + $allowedToolList }
    if ($SessionId) { $arguments += @('--resume', $SessionId) }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $argumentString = ConvertTo-Felix3ArgumentString -Arguments $arguments
    if ($resolvedExe -match '\.(cmd|bat)$') {
        # npm installs Claude Code as a .cmd shim on Windows. Launch it through
        # cmd.exe because ProcessStartInfo cannot execute command scripts directly.
        $startInfo.FileName = $env:ComSpec
        $commandLine = '"' + '"' + $resolvedExe + '" ' + $argumentString + '"'
        $startInfo.Arguments = "/d /s /c $commandLine"
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
    # These properties are available on newer runtimes; keep the feature usable
    # on the Windows PowerShell runtime Felix currently supports as well.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($name in @('StandardInputEncoding', 'StandardOutputEncoding', 'StandardErrorEncoding')) {
        $property = $startInfo.GetType().GetProperty($name)
        if ($property -and $property.CanWrite) { $property.SetValue($startInfo, $utf8, $null) }
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $startedAt = [DateTime]::UtcNow
    $rawPath = Join-Path $RunDirectory 'claude-response.jsonl'
    $stderrPath = Join-Path $RunDirectory 'claude-stderr.log'

    try {
        if ($EventSink) { & $EventSink 'phase.started' @{ phase = $Phase } "Harness phase started ($Phase)." }
        $onLine = {
            param($line)
            if (-not $EventSink) { return }
            try {
                $e = $line | ConvertFrom-Json -ErrorAction Stop
                $type = [string]$e.type
                $questionTool = if ($type -eq 'assistant') { @($e.message.content | Where-Object { $_.type -eq 'tool_use' -and $_.name -match 'AskUserQuestion|question' } | Select-Object -First 1)[0] } else { $null }
                $kind = if ($questionTool) { 'question.requested' } else { switch ($type) { 'stream_event' { 'output.delta' } 'assistant' { if (@($e.message.content | Where-Object { $_.type -eq 'tool_use' }).Count) { 'tool.started' } else { 'assistant.message' } } 'user' { 'tool.completed' } 'result' { 'turn.completed' } 'error' { 'phase.failed' } default { 'harness.event' } } }
                $summary = if ($questionTool) { 'Claude requested human input.' } elseif ($type -eq 'stream_event') { [string]$e.event.delta.text } elseif ($type -eq 'result') { 'Claude phase result received.' } else { "Claude event: $type" }
                $payload = @{ provider_event = $type; session_id = [string]$e.session_id }
                if ($questionTool) { $payload.tool = [string]$questionTool.name; $payload.question = $questionTool.input.questions }
                elseif ($type -eq 'assistant') { $tool = @($e.message.content | Where-Object { $_.type -eq 'tool_use' } | Select-Object -First 1)[0]; if ($tool) { $payload.tool = [string]$tool.name } }
                if ($e.message.usage) { $payload.usage = $e.message.usage }
                if ($type -eq 'result') { $payload.usage = $e.usage; $payload.cost_usd = $e.total_cost_usd }
                return (& $EventSink $kind $payload $summary)
            } catch { }
        }.GetNewClosure()
        $onErrorLine = { param($line) if ($EventSink) { & $EventSink 'harness.stderr' @{} $line } }.GetNewClosure()
        $onStart = { param($pid) if ($EventSink) { & $EventSink 'harness.process.started' @{ process_id = $pid; session_id = $null } "Claude process started (pid $pid)." } }.GetNewClosure()
        $onExit = { param($pid,$cancelled) if ($EventSink) { & $EventSink 'harness.process.exited' @{ process_id = $pid; cancelled = $cancelled } 'Claude process exited.' } }.GetNewClosure()
        $processOutput = Invoke-Felix3Process -Process $process -Prompt $Prompt -RawOutputPath $rawPath -StderrPath $stderrPath -OnOutputLine $onLine -OnErrorLine $onErrorLine -CancelTokenPath $CancelTokenPath -OnProcessStart $onStart -OnProcessExit $onExit
        $stdout = $processOutput.Stdout
        $stderr = $processOutput.Stderr
        $parsed = ConvertFrom-ClaudeHarnessResponse -Output $stdout
        $exitCode = $processOutput.ExitCode
        $succeeded = ($exitCode -eq 0 -and $parsed.IsValid)
        $finishedAt = [DateTime]::UtcNow

        $resultPath = Join-Path $RunDirectory 'harness-result.json'
        $sessionPath = Join-Path $RunDirectory 'claude-session.json'

        $normalized = [ordered]@{
            schema = 'felix3-harness-result-v1'
            harness = 'claude-code'
            phase = $Phase
            status = if ($processOutput.QuestionRequested) { 'needs-input' } elseif ($succeeded) { 'succeeded' } else { 'failed' }
            started_at = $startedAt.ToString('o')
            finished_at = $finishedAt.ToString('o')
            duration_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 2)
            exit_code = $exitCode
            session_id = $parsed.SessionId
            model = $Model
            text = $parsed.Text
            error = if ($processOutput.QuestionRequested) { $null } elseif ($parsed.Error) { $parsed.Error } elseif ($exitCode -ne 0) { "Claude Code exited with code $exitCode." } else { $null }
            usage = $parsed.Usage
            cost_usd = $parsed.CostUsd
            turns = $parsed.Turns
            artifacts = @('claude-response.jsonl', 'claude-stderr.log')
        }
        $normalized | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        if ($Journal) {
            $usageRecord = ConvertTo-Felix3UsageRecord -Harness 'claude-code' -Phase $Phase -PhaseInstance (Split-Path $RunDirectory -Leaf) -Model $Model -Usage $parsed.Usage -CostUsd $parsed.CostUsd -DurationSeconds (($finishedAt - $startedAt).TotalSeconds) -SessionId $parsed.SessionId
            Update-Felix3UsageSummary -RunDirectory $Journal.RunDirectory -UsageRecord $usageRecord | Out-Null
        }
        if ($EventSink -and -not $processOutput.QuestionRequested) { & $EventSink $(if ($succeeded) { 'phase.completed' } else { 'phase.failed' }) @{ exit_code = $exitCode; session_id = $parsed.SessionId; usage = $parsed.Usage; cost_usd = $parsed.CostUsd; model = $Model } $(if ($succeeded) { "Harness phase completed ($Phase)." } else { "Harness phase failed ($Phase): $($normalized.error)" }) }

        if ($parsed.SessionId) {
            [ordered]@{
                schema = 'felix3-claude-session-v1'
                harness = 'claude-code'
                session_id = $parsed.SessionId
                phase = $Phase
                working_directory = $startInfo.WorkingDirectory
                model = $Model
                updated_at = $finishedAt.ToString('o')
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sessionPath -Encoding UTF8
        }

        return [pscustomobject]@{
            Harness = 'claude-code'
            Succeeded = $succeeded
            Interrupted = $processOutput.Cancelled
            NeedsInput = $processOutput.QuestionRequested
            ExitCode = $exitCode
            Phase = $Phase
            SessionId = $parsed.SessionId
            ResultText = $parsed.Text
            Error = $normalized.error
            Usage = $parsed.Usage
            CostUsd = $parsed.CostUsd
            Turns = $parsed.Turns
            ResultPath = $resultPath
            RawOutputPath = $rawPath
            StderrPath = $stderrPath
            SessionPath = if ($parsed.SessionId) { $sessionPath } else { $null }
        }
    }
    finally {
        $process.Dispose()
    }
}

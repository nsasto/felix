Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Invoke-Felix3Process.ps1')

function global:ConvertFrom-GrokBuildEventEnvelope {
    param([Parameter(Mandatory)]$Event)
    $method = Get-Felix3ProcessProperty $Event 'method'
    $parameters = Get-Felix3ProcessProperty $Event 'params'
    $update = Get-Felix3ProcessProperty $parameters 'update'
    if (-not $update -and (Get-Felix3ProcessProperty $Event 'sessionUpdate')) { $update = $Event }
    if (($method -eq 'session/update' -or $update) -and $update) {
        $sessionId = [string](Get-Felix3ProcessProperty $parameters 'sessionId')
        if (-not $sessionId) { $sessionId = [string](Get-Felix3ProcessProperty $Event 'sessionId') }
        switch ([string](Get-Felix3ProcessProperty $update 'sessionUpdate')) {
            'agent_message_chunk' {
                $content = Get-Felix3ProcessProperty $update 'content'
                return [pscustomobject]@{ type='text'; data=[string](Get-Felix3ProcessProperty $content 'text'); sessionId=$sessionId }
            }
            'agent_thought_chunk' {
                return [pscustomobject]@{ type='thought'; data=''; sessionId=$sessionId }
            }
            'tool_call' {
                return [pscustomobject]@{ type='tool_call'; toolCallId=[string](Get-Felix3ProcessProperty $update 'toolCallId'); toolName=[string](Get-Felix3ProcessProperty $update 'title'); sessionId=$sessionId }
            }
            'tool_call_update' {
                return [pscustomobject]@{ type='tool_call_update'; toolCallId=[string](Get-Felix3ProcessProperty $update 'toolCallId'); status=[string](Get-Felix3ProcessProperty $update 'status'); sessionId=$sessionId }
            }
            'usage_update' {
                return [pscustomobject]@{ type='usage'; usage=(Get-Felix3ProcessProperty $update 'usage'); sessionId=$sessionId }
            }
            default { return [pscustomobject]@{ type='ignored'; sessionId=$sessionId } }
        }
    }
    $result = Get-Felix3ProcessProperty $Event 'result'
    if ($result -and (Get-Felix3ProcessProperty $result 'stopReason')) {
        return [pscustomobject]@{
            type='end'; sessionId=[string](Get-Felix3ProcessProperty $result 'sessionId'); stopReason=[string](Get-Felix3ProcessProperty $result 'stopReason')
            usage=(Get-Felix3ProcessProperty $result 'usage'); total_cost_usd=(Get-Felix3ProcessProperty $result 'total_cost_usd'); num_turns=(Get-Felix3ProcessProperty $result 'num_turns')
        }
    }
    # Keep support for existing fixtures and CLI builds that use flat event records.
    return $Event
}

function ConvertFrom-GrokBuildStream {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Output)
    $text = New-Object System.Text.StringBuilder
    $session = $null; $usage = $null; $costUsd = $null; $turns = $null; $errorText = $null; $sawEnd = $false
    $failedToolName = $null; $failedToolStatus = $null; $toolNames = @{}
    $eventCount = 0
    foreach ($line in ($Output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $event = ConvertFrom-GrokBuildEventEnvelope -Event $event
        $eventCount++
        $eventSessionId = Get-Felix3ProcessProperty $event 'sessionId'
        if ($eventSessionId) { $session = [string]$eventSessionId }
        switch ([string](Get-Felix3ProcessProperty $event 'type')) {
            'text' {
                $eventText = Get-Felix3ProcessProperty $event 'data'
                if ($eventText) { [void]$text.Append([string]$eventText) }
            }
            'tool_call' {
                $toolCallId = [string](Get-Felix3ProcessProperty $event 'toolCallId')
                $toolName = [string](Get-Felix3ProcessProperty $event 'toolName')
                if ($toolCallId -and $toolName) { $toolNames[$toolCallId] = $toolName }
            }
            'tool_call_update' {
                $toolStatus = [string](Get-Felix3ProcessProperty $event 'status')
                if ($toolStatus -eq 'failed') {
                    $toolCallId = [string](Get-Felix3ProcessProperty $event 'toolCallId')
                    $failedToolName = if ($toolCallId -and $toolNames.ContainsKey($toolCallId)) { $toolNames[$toolCallId] } else { 'unknown' }
                    $failedToolStatus = $toolStatus
                    # Keep diagnostics useful without persisting tool arguments or output in the normalized result.
                    $errorText = "Grok Build tool '$failedToolName' failed with status '$failedToolStatus'."
                }
            }
            'usage' {
                $eventUsage = Get-Felix3ProcessProperty $event 'usage'
                if ($eventUsage) { $usage = $eventUsage }
            }
            'end' {
                $sawEnd = $true
                if ($eventSessionId) { $session = [string]$eventSessionId }
                $eventUsage = Get-Felix3ProcessProperty $event 'usage'
                if ($eventUsage) { $usage = $eventUsage }
                $eventCost = Get-Felix3ProcessProperty $event 'total_cost_usd'
                if ($null -ne $eventCost -and $eventCost -is [ValueType]) { $costUsd = [double]$eventCost }
                $eventTurns = Get-Felix3ProcessProperty $event 'num_turns'
                if ($null -ne $eventTurns -and $eventTurns -is [ValueType]) { $turns = [int]$eventTurns }
                $stopReason = Get-Felix3ProcessProperty $event 'stopReason'
                if ($stopReason -and [string]$stopReason -notin @('end_turn','stop')) {
                    $stopError = "Grok Build stopped with reason '$stopReason' and may not have completed the requested phase."
                    $errorText = if ($errorText) { "$errorText $stopError" } else { $stopError }
                }
            }
            'error' { $errorText = [string](Get-Felix3ProcessProperty $event 'message') }
        }
    }
    return [pscustomobject]@{ Text=$text.ToString(); SessionId=$session; Usage=$usage; CostUsd=$costUsd; Turns=$turns; Error=$errorText; FailedToolName=$failedToolName; FailedToolStatus=$failedToolStatus; SawEnd=$sawEnd; EventCount=$eventCount }
}

function Invoke-GrokBuildHarness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('planning','building','reviewing')][string]$Phase,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory)][string]$RunDirectory,
        [string]$Executable = 'grok',
        [string]$Model,
        [int]$MaxTurns = 100,
        [string]$PermissionMode,
        [string]$SandboxProfile,
        [string[]]$Tools = @(),
        [string[]]$DisallowedTools = @(),
        [string[]]$AllowRules = @(),
        [string[]]$DenyRules = @(),
        [bool]$AlwaysApprove = $false,
        [string]$SessionId,
        $Journal,
        [scriptblock]$EventSink,
        [string]$CancelTokenPath
    )

    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        throw "Working directory does not exist: $WorkingDirectory"
    }
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt must not be empty.' }
    if ($MaxTurns -lt 1 -or $MaxTurns -gt 500) { throw 'Grok Build max_turns must be between 1 and 500.' }
    if (-not [System.IO.Path]::IsPathRooted($RunDirectory)) { $RunDirectory = Join-Path $WorkingDirectory $RunDirectory }
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null
    }
    $WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    $RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path

    try { $resolvedExe = Resolve-Felix3Executable -Executable $Executable }
    catch {
        throw "Grok Build CLI '$Executable' was not found. Install it with 'irm https://x.ai/cli/install.ps1 | iex', then run 'grok login' and reopen the terminal."
    }

    # Grok headless mode reads prompts from a file, not stdin. Keep that file
    # beside the local phase artifacts; it is never included in live events or
    # Cloud's artifact allowlist by default.
    $promptPath = Join-Path $RunDirectory 'grok-prompt.txt'
    [System.IO.File]::WriteAllText($promptPath, $Prompt, [System.Text.UTF8Encoding]::new($false))
    $arguments = @('--no-auto-update','--prompt-file',$promptPath,'--output-format','streaming-json','--max-turns',[string]$MaxTurns,'--cwd',$WorkingDirectory)
    if ($Model) { $arguments += @('--model',$Model) }
    if ($PermissionMode) { $arguments += @('--permission-mode',$PermissionMode) }
    if ($SandboxProfile) { $arguments += @('--sandbox',$SandboxProfile) }
    $toolList = @($Tools | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($toolList.Count -gt 0) { $arguments += @('--tools',($toolList -join ',')) }
    $disallowedList = @($DisallowedTools | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($disallowedList.Count -gt 0) { $arguments += @('--disallowed-tools',($disallowedList -join ',')) }
    foreach ($rule in @($AllowRules | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) { $arguments += @('--allow',[string]$rule) }
    foreach ($rule in @($DenyRules | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) { $arguments += @('--deny',[string]$rule) }
    if ($AlwaysApprove) { $arguments += '--always-approve' }
    if ($SessionId) { $arguments += @('--resume',$SessionId) }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedExe
    $startInfo.Arguments = ConvertTo-Felix3ArgumentString -Arguments $arguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($name in @('StandardInputEncoding','StandardOutputEncoding','StandardErrorEncoding')) {
        $property = $startInfo.GetType().GetProperty($name)
        if ($property -and $property.CanWrite) { $property.SetValue($startInfo, $utf8, $null) }
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $startedAt = [DateTime]::UtcNow
    $rawPath = Join-Path $RunDirectory 'grok-events.jsonl'
    $stderrPath = Join-Path $RunDirectory 'grok-stderr.log'
    $toolNames = @{}
    $questionState = [pscustomobject]@{ Buffer = ''; Inside = $false }
    $questionStart = '<felix3-question>'
    $questionEnd = '</felix3-question>'

    try {
        if ($EventSink) { [void](& $EventSink 'phase.started' @{ phase = $Phase } "Harness phase started ($Phase).") }
        $onLine = {
            param($line)
            try {
                $e = ConvertFrom-GrokBuildEventEnvelope -Event ($line | ConvertFrom-Json -ErrorAction Stop)
                $type = [string](Get-Felix3ProcessProperty $e 'type')
                switch ($type) {
                    'text' {
                        $text = [string](Get-Felix3ProcessProperty $e 'data')
                        if ($text) {
                            $questionState.Buffer += $text
                            if (-not $questionState.Inside) {
                                $startIndex = $questionState.Buffer.IndexOf($questionStart, [StringComparison]::Ordinal)
                                if ($startIndex -ge 0) {
                                    $safeText = $questionState.Buffer.Substring(0, $startIndex)
                                    if ($safeText -and $EventSink) { [void](& $EventSink 'output.delta' @{ provider_event = 'text' } $safeText) }
                                    $questionState.Buffer = $questionState.Buffer.Substring($startIndex + $questionStart.Length)
                                    $questionState.Inside = $true
                                }
                                else {
                                    $retain = [Math]::Min($questionState.Buffer.Length, $questionStart.Length - 1)
                                    $emitLength = $questionState.Buffer.Length - $retain
                                    if ($emitLength -gt 0 -and $EventSink) { [void](& $EventSink 'output.delta' @{ provider_event = 'text' } $questionState.Buffer.Substring(0, $emitLength)) }
                                    if ($retain -gt 0) { $questionState.Buffer = $questionState.Buffer.Substring($emitLength) } else { $questionState.Buffer = '' }
                                    return
                                }
                            }
                            if ($questionState.Inside) {
                                $endIndex = $questionState.Buffer.IndexOf($questionEnd, [StringComparison]::Ordinal)
                                if ($endIndex -ge 0) {
                                    $questionState.Buffer = ''
                                    $questionState.Inside = $false
                                    return 'question.requested'
                                }
                                $retain = [Math]::Min($questionState.Buffer.Length, $questionEnd.Length - 1)
                                if ($retain -gt 0) { $questionState.Buffer = $questionState.Buffer.Substring($questionState.Buffer.Length - $retain) } else { $questionState.Buffer = '' }
                            }
                        }
                    }
                    'thought' { }
                    'tool_call' {
                        $callId = [string](Get-Felix3ProcessProperty $e 'toolCallId')
                        $name = [string](Get-Felix3ProcessProperty $e 'toolName')
                        if ($callId) { $toolNames[$callId] = $name }
                        [void](& $EventSink 'tool.started' @{ tool = $name; status = 'started' } 'Grok started a tool.')
                    }
                    'tool_call_update' {
                        $callId = [string](Get-Felix3ProcessProperty $e 'toolCallId')
                        $name = if ($callId -and $toolNames.ContainsKey($callId)) { [string]$toolNames[$callId] } else { 'tool' }
                        $status = [string](Get-Felix3ProcessProperty $e 'status')
                        if ($status -eq 'failed') { [void](& $EventSink 'tool.failed' @{ tool = $name; status = 'failed' } 'Grok tool failed.') }
                        elseif ($status -eq 'completed') { [void](& $EventSink 'tool.completed' @{ tool = $name; status = 'completed' } 'Grok completed a tool.') }
                    }
                    'usage' { }
                    'end' { }
                    'error' { }
                    default { }
                }
            } catch { }
        }.GetNewClosure()
        $onErrorLine = { param($line) if ($EventSink) { [void](& $EventSink 'harness.stderr' @{} $line) } }.GetNewClosure()
        $onStart = { param($pid) if ($EventSink) { [void](& $EventSink 'harness.process.started' @{ process_id = $pid } 'Grok Build process started.') } }.GetNewClosure()
        $onExit = { param($pid,$cancelled) if ($EventSink) { [void](& $EventSink 'harness.process.exited' @{ process_id = $pid; cancelled = $cancelled } 'Grok Build process exited.') } }.GetNewClosure()
        $processOutput = Invoke-Felix3Process -Process $process -Prompt '' -RawOutputPath $rawPath -StderrPath $stderrPath -OnOutputLine $onLine -OnErrorLine $onErrorLine -CancelTokenPath $CancelTokenPath -OnProcessStart $onStart -OnProcessExit $onExit
        if (-not $processOutput.QuestionRequested -and -not $questionState.Inside -and $questionState.Buffer -and $EventSink) {
            [void](& $EventSink 'output.delta' @{ provider_event = 'text' } $questionState.Buffer)
        }
        $finishedAt = [DateTime]::UtcNow
        $parsed = ConvertFrom-GrokBuildStream -Output ([string]$processOutput.Stdout)
        $errorText = $parsed.Error
        if (-not $processOutput.Cancelled -and $processOutput.ExitCode -ne 0 -and -not $errorText) { $errorText = "Grok Build exited with code $($processOutput.ExitCode)." }
        elseif (-not $processOutput.Cancelled -and -not $parsed.SawEnd -and -not $errorText) { $errorText = 'Grok Build exited without its final end event.' }
        $succeeded = ($processOutput.ExitCode -eq 0 -and $parsed.SawEnd -and -not $errorText -and -not $processOutput.QuestionRequested)
        $textResult = $parsed.Text
        $resultPath = Join-Path $RunDirectory 'harness-result.json'
        $sessionPath = Join-Path $RunDirectory 'grok-session.json'
        [ordered]@{
            schema = 'felix3-harness-result-v1'; harness = 'grok-build'; phase = $Phase
            status = if ($processOutput.Cancelled) { 'interrupted' } elseif ($processOutput.QuestionRequested) { 'needs-input' } elseif ($succeeded) { 'succeeded' } else { 'failed' }
            started_at = $startedAt.ToString('o'); finished_at = $finishedAt.ToString('o')
            duration_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds,2)
            exit_code = $processOutput.ExitCode; session_id = $parsed.SessionId; model = $Model
            text = $textResult; error = $errorText; failed_tool_name = $parsed.FailedToolName; failed_tool_status = $parsed.FailedToolStatus
            usage = $parsed.Usage; cost_usd = $parsed.CostUsd; turns = $parsed.Turns
            artifacts = @('grok-prompt.txt','grok-events.jsonl','grok-stderr.log')
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        if ($parsed.SessionId) {
            [ordered]@{ schema='felix3-grok-build-session-v1'; harness='grok-build'; session_id=$parsed.SessionId; phase=$Phase; working_directory=$WorkingDirectory; model=$Model; updated_at=$finishedAt.ToString('o') } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sessionPath -Encoding UTF8
        }
        if ($Journal) {
            $usageRecord = ConvertTo-Felix3UsageRecord -Harness 'grok-build' -Phase $Phase -PhaseInstance (Split-Path $RunDirectory -Leaf) -Model $Model -Usage $parsed.Usage -CostUsd $parsed.CostUsd -DurationSeconds (($finishedAt - $startedAt).TotalSeconds) -SessionId $parsed.SessionId
            Update-Felix3UsageSummary -RunDirectory $Journal.RunDirectory -UsageRecord $usageRecord | Out-Null
        }
        if ($EventSink -and $processOutput.QuestionRequested) {
            [void](& $EventSink 'question.requested' @{} 'Grok requested human input.')
        }
        elseif ($EventSink -and -not $processOutput.Cancelled) {
            [void](& $EventSink $(if ($succeeded) { 'phase.completed' } else { 'phase.failed' }) @{ exit_code=$processOutput.ExitCode; session_id=$parsed.SessionId; turns=$parsed.Turns } $(if ($succeeded) { "Harness phase completed ($Phase)." } else { "Grok Build phase failed ($Phase)." }))
        }
        return [pscustomobject]@{
            Harness='grok-build'; Succeeded=[bool]$succeeded; Interrupted=[bool]$processOutput.Cancelled; NeedsInput=[bool]$processOutput.QuestionRequested
            ExitCode=[int]$processOutput.ExitCode; Phase=$Phase; SessionId=$parsed.SessionId; ResultText=$textResult; Error=$errorText
            Usage=$parsed.Usage; CostUsd=$parsed.CostUsd; Turns=$parsed.Turns; ResultPath=$resultPath; RawOutputPath=$rawPath; StderrPath=$stderrPath
            SessionPath=if ($parsed.SessionId) { $sessionPath } else { $null }
        }
    }
    finally {
        try { $process.Dispose() } catch { }
    }
}

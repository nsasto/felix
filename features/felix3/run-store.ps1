Set-StrictMode -Version Latest

function global:Initialize-Felix3RunJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunDirectory, [Parameter(Mandatory)][string]$RunId)
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) { New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null }
    $path = Join-Path $RunDirectory 'events.jsonl'
    $sequence = 0L
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            try { $item = $line | ConvertFrom-Json; if ($item.seq -gt $sequence) { $sequence = [long]$item.seq } } catch { }
        }
    }
    return [pscustomobject]@{ RunId = $RunId; RunDirectory = $RunDirectory; EventPath = $path; Sequence = $sequence; StartedAt = [DateTime]::UtcNow }
}

function global:Protect-Felix3Text {
    param([AllowEmptyString()][string]$Text, [int]$MaxLength = 2000)
    if ($null -eq $Text) { return $null }
    $safe = $Text -replace '(?i)(api[_-]?key|token|password|secret)(\s*[=:]\s*)([^\s,;"'']+)', '$1$2[REDACTED]'
    $safe = $safe -replace '(?i)Bearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [REDACTED]'
    $safe = $safe -replace '(?i)\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|fsk_[A-Za-z0-9_-]{16,})\b', '[REDACTED]'
    $safe = $safe -replace '(?i)\bAKIA[0-9A-Z]{16}\b', '[REDACTED]'
    $safe = $safe -replace '\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b', '[REDACTED]'
    if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) + '…[truncated]' }
    return $safe
}

function global:Get-Felix3PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function global:Write-Felix3RunEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Journal,
        [Parameter(Mandatory)][string]$Kind,
        [string]$Phase,
        [string]$Harness,
        $Payload,
        [string]$Summary
    )
    $Journal.Sequence = [long]$Journal.Sequence + 1
    $event = [ordered]@{
        schema = 'felix3-event-v1'
        event_id = '{0}:{1}' -f $Journal.RunId, $Journal.Sequence
        run_id = $Journal.RunId
        seq = $Journal.Sequence
        timestamp = [DateTime]::UtcNow.ToString('o')
        kind = $Kind
        phase = $Phase
        harness = $Harness
        summary = Protect-Felix3Text -Text $Summary
        payload = $Payload
    }
    $line = $event | ConvertTo-Json -Depth 30 -Compress
    [System.IO.File]::AppendAllText($Journal.EventPath, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    return [pscustomobject]$event
}

function global:New-Felix3EventSink {
    param($Journal, [string]$Phase, [string]$Harness, [scriptblock]$CloudSink)
    return {
        param($Kind, $Payload, $Summary)
        $event = Write-Felix3RunEvent -Journal $Journal -Kind ([string]$Kind) -Phase $Phase -Harness $Harness -Payload $Payload -Summary ([string]$Summary)
        $statePath = Join-Path $Journal.RunDirectory 'state.json'
        if ($Kind -in @('harness.process.started','harness.process.exited') -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $state.PSObject.Properties['process']) { Add-Member -InputObject $state -NotePropertyName process -NotePropertyValue $null }
                if ($Kind -eq 'harness.process.started') { $state.process = @{ id = [int]$Payload.process_id; phase = $Phase; started_at = [DateTime]::UtcNow.ToString('o') } }
                else { $state.process = $null }
                Write-Felix3AtomicJson -Path $statePath -Value $state
            } catch { }
        }
        if ($CloudSink) { & $CloudSink $event }
        if ($Kind -eq 'output.delta' -and $Summary) { [Console]::Write((Protect-Felix3Text -Text ([string]$Summary) -MaxLength 500)) }
        elseif ($Kind -in @('phase.started','phase.completed','phase.failed','question.requested','tool.started','turn.completed')) {
            Write-Host ("[felix3:{0}] {1}" -f $Phase, (Protect-Felix3Text -Text $Summary -MaxLength 180))
        }
        if ($Kind -eq 'question.requested') { return 'question.requested' }
    }.GetNewClosure()
}

function global:ConvertTo-Felix3UsageRecord {
    param([string]$Harness, [string]$Phase, [string]$PhaseInstance, [string]$Model, $Usage, $CostUsd, [double]$DurationSeconds, [string]$SessionId)
    $inputTokens = $null; $outputTokens = $null; $totalTokens = $null; $cachedTokens = $null; $reasoningTokens = $null
    if ($Usage) {
        foreach ($name in @('input_tokens','prompt_tokens','inputTokens','input')) { $value = Get-Felix3PropertyValue $Usage $name; if ($null -eq $inputTokens -and $null -ne $value) { $inputTokens = [long]$value } }
        foreach ($name in @('output_tokens','completion_tokens','outputTokens','output')) { $value = Get-Felix3PropertyValue $Usage $name; if ($null -eq $outputTokens -and $null -ne $value) { $outputTokens = [long]$value } }
        foreach ($name in @('total_tokens','totalTokens','total')) { $value = Get-Felix3PropertyValue $Usage $name; if ($null -eq $totalTokens -and $null -ne $value) { $totalTokens = [long]$value } }
        foreach ($name in @('cached_input_tokens','cache_read_input_tokens','cached_tokens')) { $value = Get-Felix3PropertyValue $Usage $name; if ($null -eq $cachedTokens -and $null -ne $value) { $cachedTokens = [long]$value } }
        if ($null -eq $cachedTokens) { $cache = Get-Felix3PropertyValue $Usage 'cache'; if ($cache) { $cachedTokens = Get-Felix3PropertyValue $cache 'read' } }
        foreach ($name in @('reasoning_tokens','reasoningTokens','reasoning')) { $value = Get-Felix3PropertyValue $Usage $name; if ($null -eq $reasoningTokens -and $null -ne $value) { $reasoningTokens = [long]$value } }
    }
    return [pscustomobject]@{
        schema = 'felix3-usage-v1'; harness = $Harness; phase = $Phase; phase_instance = $PhaseInstance; model = $Model; session_id = $SessionId
        input_tokens = $inputTokens; output_tokens = $outputTokens; total_tokens = $totalTokens; cached_input_tokens = $cachedTokens
        reasoning_tokens = $reasoningTokens; cost_usd = if ($null -ne $CostUsd) { [double]$CostUsd } else { $null }
        duration_seconds = $DurationSeconds; reported = ($null -ne $inputTokens -or $null -ne $outputTokens -or $null -ne $totalTokens -or $null -ne $cachedTokens -or $null -ne $reasoningTokens); captured_at = [DateTime]::UtcNow.ToString('o')
        provider_usage = $Usage
    }
}

function global:Update-Felix3UsageSummary {
    param([Parameter(Mandatory)][string]$RunDirectory, [Parameter(Mandatory)]$UsageRecord)
    $path = Join-Path $RunDirectory 'usage.json'
    $records = @()
    if (Test-Path -LiteralPath $path) {
        try { $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json; $records = @($existing.phases) } catch { }
    }
    $records = @($records | Where-Object { -not ($_.phase_instance -eq $UsageRecord.phase_instance) }) + @($UsageRecord)
    $sum = { param($property) $items = @($records | Where-Object { $null -ne $_.$property }); if ($items.Count) { [long](($items | Measure-Object -Property $property -Sum).Sum) } else { $null } }
    $costItems = @($records | Where-Object { $null -ne $_.cost_usd })
    $summary = [ordered]@{
        schema = 'felix3-usage-summary-v1'; phases = $records
        totals = [ordered]@{
            input_tokens = & $sum 'input_tokens'; output_tokens = & $sum 'output_tokens'
            total_tokens = & $sum 'total_tokens'
            cached_input_tokens = & $sum 'cached_input_tokens'; reasoning_tokens = & $sum 'reasoning_tokens'
            cost_usd = if ($costItems.Count) { [math]::Round((($costItems | Measure-Object -Property cost_usd -Sum).Sum), 8) } else { $null }
            duration_seconds = [math]::Round((($records | Measure-Object -Property duration_seconds -Sum).Sum), 2)
            complete = (@($records | Where-Object { -not $_.reported }).Count -eq 0)
        }
    }
    $summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function global:Write-Felix3AtomicJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function global:Get-Felix3QuestionFromText {
    param([AllowEmptyString()][string]$Text)
    if ($Text -notmatch '(?s)<felix3-question>\s*(\{.*?\})\s*</felix3-question>') { return $null }
    try {
        $question = $Matches[1] | ConvertFrom-Json -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$question.question)) { return $null }
        $choices = @()
        if ($question.PSObject.Properties['choices']) { $choices = @($question.choices | ForEach-Object { Protect-Felix3Text -Text ([string]$_) -MaxLength 300 }) }
        return [pscustomobject]@{
            question = Protect-Felix3Text -Text ([string]$question.question)
            choices = $choices
            context = if ($question.PSObject.Properties['context']) { Protect-Felix3Text -Text ([string]$question.context) -MaxLength 1000 } else { $null }
            asked_at = [DateTime]::UtcNow.ToString('o')
        }
    } catch { return $null }
}

function global:ConvertFrom-Felix3QuestionData {
    param($Data)
    if ($null -eq $Data) { return $null }
    if ($Data -is [string]) { return [pscustomobject]@{ question = Protect-Felix3Text -Text $Data; choices = @(); context = $null; asked_at = [DateTime]::UtcNow.ToString('o') } }
    $items = @($Data)
    $questions = @(); $choices = @()
    foreach ($item in $items) {
        $text = Get-Felix3PropertyValue $item 'question'
        if (-not $text) { $text = Get-Felix3PropertyValue $item 'prompt' }
        if ($text) { $header = Get-Felix3PropertyValue $item 'header'; $questions += if ($header) { "${header}: $text" } else { [string]$text } }
        foreach ($choice in @(Get-Felix3PropertyValue $item 'options')) {
            $label = Get-Felix3PropertyValue $choice 'label'
            if ($label) { $choices += [string]$label }
        }
        foreach ($choice in @(Get-Felix3PropertyValue $item 'choices')) { if ($choice) { $choices += [string]$choice } }
    }
    if (-not $questions.Count) {
        $direct = Get-Felix3PropertyValue $Data 'question'
        if ($direct -is [string] -and $direct) { $questions += $direct }
    }
    if (-not $questions.Count) { return $null }
    $safeChoices = @($choices | Select-Object -Unique | ForEach-Object { Protect-Felix3Text -Text ([string]$_) -MaxLength 300 })
    return [pscustomobject]@{ question = Protect-Felix3Text -Text ($questions -join "`n"); choices = $safeChoices; context = 'The harness requested interactive input.'; asked_at = [DateTime]::UtcNow.ToString('o') }
}

function global:Get-Felix3LastSessionId {
    param([Parameter(Mandatory)][string]$EventPath, [Parameter(Mandatory)][string]$Phase)
    if (-not (Test-Path -LiteralPath $EventPath -PathType Leaf)) { return $null }
    $sessionId = $null
    foreach ($line in [System.IO.File]::ReadLines($EventPath)) {
        try { $event = $line | ConvertFrom-Json; if ($event.phase -eq $Phase -and $event.payload.session_id) { $sessionId = [string]$event.payload.session_id } } catch { }
    }
    return $sessionId
}

function global:Add-Felix3QuestionProtocol {
    param([Parameter(Mandatory)][string]$Prompt)
    return $Prompt + @'

## Human input protocol
Do not invoke an interactive question tool or wait for terminal input. If a decision is required and cannot be resolved safely from the specification and repository, stop and make your final response exactly this marker (with valid JSON):
<felix3-question>{"question":"the concise question","choices":["choice A","choice B"],"context":"why the decision matters"}</felix3-question>
Do not make consequential assumptions silently. For routine details, use the least surprising safe default and record it in your final response.
'@
}

function global:Remove-ExpiredFelix3Runs {
    param([Parameter(Mandatory)][string]$RunsRoot, [int]$RetentionDays = 30)
    if ($RetentionDays -lt 1 -or -not (Test-Path -LiteralPath $RunsRoot -PathType Container)) { return @() }
    $cutoff = [DateTime]::UtcNow.AddDays(-$RetentionDays)
    $removed = @()
    foreach ($directory in Get-ChildItem -LiteralPath $RunsRoot -Directory -ErrorAction SilentlyContinue) {
        $statePath = Join-Path $directory.FullName 'state.json'
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { continue }
        try {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.status -notin @('completed','failed') -or -not $state.finished_at) { continue }
            if ([DateTime]::Parse([string]$state.finished_at).ToUniversalTime() -lt $cutoff) {
                Remove-Item -LiteralPath $directory.FullName -Recurse -Force
                $removed += $directory.Name
            }
        } catch { }
    }
    return $removed
}

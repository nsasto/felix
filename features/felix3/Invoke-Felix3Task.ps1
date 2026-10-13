Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Load-Felix3Config.ps1')
. (Join-Path $PSScriptRoot 'contracts.ps1')
. (Join-Path $PSScriptRoot 'run-store.ps1')
. (Join-Path $PSScriptRoot 'cloud-sync.ps1')
. (Join-Path $PSScriptRoot 'claude\Invoke-ClaudeHarness.ps1')
. (Join-Path $PSScriptRoot 'opencode\Invoke-OpenCodeHarness.ps1')
. (Join-Path $PSScriptRoot 'codex\Invoke-CodexHarness.ps1')

function Read-Felix3Template {
    param([string]$Path, [hashtable]$Values)
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($key in $Values.Keys) { $content = $content.Replace("{{$key}}", [string]$Values[$key]) }
    return $content
}

function Write-Felix3Json {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-Felix3RunDirectory {
    param([Parameter(Mandatory)][string]$RunsRoot, [Parameter(Mandatory)][string]$RunId)
    if ([string]::IsNullOrWhiteSpace($RunId) -or [System.IO.Path]::IsPathRooted($RunId) -or $RunId -in @('.', '..') -or [System.IO.Path]::GetFileName($RunId) -ne $RunId) {
        throw "Invalid Felix 3 run ID '$RunId'. Run IDs must be a single directory name."
    }
    $root = [System.IO.Path]::GetFullPath($RunsRoot)
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $path = [System.IO.Path]::GetFullPath((Join-Path $root $RunId))
    if (-not $path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Run ID '$RunId' resolves outside the configured runs directory." }
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Felix 3 run directory cannot be a symlink or junction: $path" }
    }
    return $path
}

function ConvertTo-Felix3ReviewJsonText {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ($Text -match '(?s)```(?:json)?\s*(\{.*?\})\s*```') { return $Matches[1] }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -ge 0 -and $end -gt $start) { return $Text.Substring($start, $end - $start + 1) }
    return $Text
}

function Invoke-Felix3Validation {
    param($Config, [string]$ProjectPath, [string]$RunDirectory, $Journal, [string]$CancelTokenPath)
    $commands = @($Config.workflow.validation.commands)
    if ($Config.workflow.validation.require_at_least_one_command -and $commands.Count -eq 0) {
        throw 'Validation is configured to require at least one command, but workflow.validation.commands is empty.'
    }
    $results = @()
    foreach ($command in $commands) {
        if (-not $command.executable) { throw 'Every validation command needs an executable.' }
        $started = [DateTime]::UtcNow
        $executable = Resolve-Felix3Executable -Executable ([string]$command.executable)
        $commandArguments = if ($command.PSObject.Properties['args']) { @([string[]]$command.args) } else { @() }
        $arguments = ConvertTo-Felix3ArgumentString -Arguments $commandArguments
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        if ($executable -match '\.(cmd|bat)$') { $startInfo.FileName = $env:ComSpec; $startInfo.Arguments = '/d /s /c ""' + $executable + '" ' + $arguments + '"' }
        else { $startInfo.FileName = $executable; $startInfo.Arguments = $arguments }
        $startInfo.WorkingDirectory = $ProjectPath
        $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true; $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
        $name = if ($command.PSObject.Properties['name'] -and $command.name) { [string]$command.name } else { [string]$command.executable }
        $onLine = {
            param($line)
            if ($Journal) { Write-Felix3RunEvent -Journal $Journal -Kind 'validation.output' -Phase 'validation' -Harness 'felix3' -Payload @{ command = $name } -Summary $line | Out-Null }
            Write-Host ("[felix3:validation:{0}] {1}" -f $name, (Protect-Felix3Text -Text $line -MaxLength 180))
        }.GetNewClosure()
        $outPath = Join-Path $RunDirectory ("validation-{0}.stdout.log" -f ($name -replace '[^A-Za-z0-9._-]','_'))
        $errPath = Join-Path $RunDirectory ("validation-{0}.stderr.log" -f ($name -replace '[^A-Za-z0-9._-]','_'))
        try { $processResult = Invoke-Felix3Process -Process $process -Prompt '' -RawOutputPath $outPath -StderrPath $errPath -OnOutputLine $onLine -CancelTokenPath $CancelTokenPath }
        finally { $process.Dispose() }
        $output = @($processResult.Stdout, $processResult.Stderr) -join "`n"
        $exitCode = $processResult.ExitCode
        $results += [pscustomobject]@{
            name = $name
            executable = [string]$command.executable
            args = $commandArguments
            exit_code = $exitCode
            passed = ($exitCode -eq 0)
            output = $output
            duration_seconds = [math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 2)
            interrupted = [bool]$processResult.Cancelled
        }
    }
    $path = Join-Path $RunDirectory 'validation.json'
    Write-Felix3Json -Path $path -Value @{ schema = 'felix3-validation-v1'; passed = (@($results | Where-Object { -not $_.passed }).Count -eq 0); commands = $results }
    return [pscustomobject]@{ Passed = (@($results | Where-Object { -not $_.passed }).Count -eq 0); Interrupted = (@($results | Where-Object { $_.interrupted }).Count -gt 0); Harness = 'validation'; SessionId = $null; Results = $results; Path = $path }
}

function Suspend-Felix3ForQuestion {
    param($Result, [string]$Phase, $State, [string]$StatePath, [string]$RunDirectory, $Journal, [int]$Attempt = 1, [int]$Cycle = 1, $Cloud)
    $question = Get-Felix3QuestionFromText -Text ([string]$Result.ResultText)
    $fromStream = $false
    if (-not $question -and $Result.NeedsInput) {
        $questionEvent = $null
        foreach ($line in [System.IO.File]::ReadLines($Journal.EventPath)) {
            try { $event = $line | ConvertFrom-Json; if ($event.phase -eq $Phase -and $event.kind -eq 'question.requested') { $questionEvent = $event } } catch { }
        }
        if ($questionEvent) { $question = ConvertFrom-Felix3QuestionData -Data $questionEvent.payload.question; $fromStream = $true }
        if (-not $question) { $question = ConvertFrom-Felix3QuestionData -Data @{ question = 'The harness requested input but did not provide a readable question.' }; $fromStream = $true }
    }
    if (-not $question) { return $false }
    $questionPath = Join-Path $RunDirectory 'question.json'
    $question | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $questionPath -Encoding UTF8
    Set-Felix3RunStatus -State $State -Status 'awaiting-input'
    $State.active_phase = $Phase
    $State.pending_question = @{ phase = $Phase; session_id = $Result.SessionId; attempt = $Attempt; cycle = $Cycle; asked_at = $question.asked_at }
    $State.outcome = 'Agent paused for human input.'
    Write-Felix3AtomicJson -Path $StatePath -Value $State
    if (-not $fromStream) {
        $event = Write-Felix3RunEvent -Journal $Journal -Kind 'question.requested' -Phase $Phase -Harness $Result.Harness -Payload @{ question = $question.question; choices = $question.choices; context = $question.context; session_id = $Result.SessionId } -Summary $question.question
        Add-Felix3CloudEvent -Cloud $Cloud -Event $event
    }
    return $true
}

function Suspend-Felix3ForStop {
    param($Result, [string]$Phase, $State, [string]$StatePath, [string]$RunDirectory, $Journal, $Cloud)
    if (-not $Result.Interrupted) { return $false }
    Set-Felix3RunStatus -State $State -Status 'interrupted'; $State.active_phase = $Phase; $State.outcome = 'Run stopped by user. Resume with Resume-Felix3Task.'; $State.process = $null
    Write-Felix3AtomicJson -Path $StatePath -Value $State
    $event = Write-Felix3RunEvent -Journal $Journal -Kind 'run.interrupted' -Phase $Phase -Harness $Result.Harness -Payload @{ session_id = $Result.SessionId } -Summary 'Run stopped by user.'
    Add-Felix3CloudEvent -Cloud $Cloud -Event $event
    if ($Cloud) {
        Send-Felix3CloudEvents -Cloud $Cloud
        try { Invoke-Felix3BestEffortSyncCall { $Cloud.Client.Flush() } | Out-Null } catch { }
    }
    return $true
}

function Invoke-Felix3Task {
    <# Drives one manually supplied spec through planning, building, independent validation, and review. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$RequirementId,
        [Parameter(Mandatory = $true)][string]$SpecPath,
        [string]$ConfigPath = '.felix3/config.json',
        [string]$Title,
        [string]$ResumeRunId,
        [string]$Answer
    )

    $project = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $configFile = Resolve-Felix3Path -Path $ConfigPath -BasePath $project
    $config = Import-Felix3Config -Path $configFile
    $specFile = Resolve-Felix3Path -Path $SpecPath -BasePath $project
    if (-not (Test-Path -LiteralPath $specFile -PathType Leaf)) { throw "Specification not found: $specFile" }
    $specText = Get-Content -LiteralPath $specFile -Raw -Encoding UTF8
    if (-not $Title) { $Title = $RequirementId }
    $runsRoot = Resolve-Felix3Path -Path ([string]$config.artifacts.runs_dir) -BasePath $project
    $retentionDays = if ($config.artifacts.PSObject.Properties['local_retention_days'] -and $config.artifacts.local_retention_days) { [int]$config.artifacts.local_retention_days } else { 30 }
    if ($retentionDays -gt 0) { Remove-ExpiredFelix3Runs -RunsRoot $runsRoot -RetentionDays $retentionDays | Out-Null }
    $resuming = -not [string]::IsNullOrWhiteSpace($ResumeRunId)
    $safeRequirementId = [regex]::Replace($RequirementId, '[^A-Za-z0-9._-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeRequirementId)) { $safeRequirementId = 'requirement' }
    $runId = if ($resuming) { $ResumeRunId } else { '{0}-{1}-{2}' -f $safeRequirementId, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)) }
    $runDirectory = Resolve-Felix3RunDirectory -RunsRoot $runsRoot -RunId $runId
    if ($resuming -and -not (Test-Path -LiteralPath $runDirectory -PathType Container)) { throw "Felix 3 run not found: $runId" }
    $planPath = Join-Path $runDirectory 'plan.md'
    $reviewPath = Join-Path $runDirectory 'review.json'
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

    $workItemPath = Join-Path $runDirectory 'work-item.json'
    $statePath = Join-Path $runDirectory 'state.json'
    $resumeState = $null
    $answeringQuestion = $false
    $resumePhase = $null; $resumeSession = $null; $resumeAttempt = 1; $resumeCycle = 1
    $rejectingPlan = $false
    $planWasApproved = $false
    if ($resuming) {
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Felix 3 run state not found: $statePath" }
        $resumeState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $answeringQuestion = ($resumeState.status -eq 'awaiting-input')
        if ($resumeState.status -in @('completed','blocked')) { throw "Run $runId is terminal ($($resumeState.status)); start a new run to retry it." }
        if ($resumeState.status -eq 'awaiting-input' -and [string]::IsNullOrWhiteSpace($Answer)) { throw "Run $runId requires an answer. Use Resume-Felix3Task -RunId '$runId' -Answer '...'" }
        if ($resumeState.status -eq 'awaiting-plan-approval' -and $Answer -notmatch '^(?i:approve|reject)$') { throw "Run $runId is awaiting plan approval. Resume with -Answer approve (or reject)." }
        $planWasApproved = ($resumeState.status -eq 'awaiting-plan-approval' -and $Answer -match '^(?i:approve)$')
        $rejectingPlan = ($resumeState.status -eq 'awaiting-plan-approval' -and $Answer -match '^(?i:reject)$')
        $workItem = Get-Content -LiteralPath $workItemPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $RequirementId = [string]$workItem.id
        $Title = [string]$workItem.title
        $specFile = Join-Path $runDirectory 'spec.md'
        $specText = Get-Content -LiteralPath $specFile -Raw -Encoding UTF8
        Assert-Felix3WorkItemContract -WorkItem $workItem -SpecText $specText | Out-Null
        $pendingQuestion = Get-Felix3PropertyValue $resumeState 'pending_question'
        $pendingPhase = Get-Felix3PropertyValue $pendingQuestion 'phase'
        $resumePhase = if ($pendingPhase) { [string]$pendingPhase } elseif ($resumeState.status -eq 'awaiting-plan-approval') { 'building' } else { [string]$resumeState.active_phase }
        if (-not $resumePhase) { $resumePhase = 'planning' }
        $pendingSession = Get-Felix3PropertyValue $pendingQuestion 'session_id'
        if ($pendingSession) { $resumeSession = [string]$pendingSession } else { $resumeSession = Get-Felix3LastSessionId -EventPath (Join-Path $runDirectory 'events.jsonl') -Phase $resumePhase }
        $pendingAttempt = Get-Felix3PropertyValue $pendingQuestion 'attempt'
        $pendingCycle = Get-Felix3PropertyValue $pendingQuestion 'cycle'
        if ($pendingAttempt) { $resumeAttempt = [int]$pendingAttempt }
        if ($pendingCycle) { $resumeCycle = [int]$pendingCycle }
        if ($resumeState.status -eq 'awaiting-input') {
            Set-Content -LiteralPath (Join-Path $runDirectory 'answer.md') -Value $Answer -Encoding UTF8
            Remove-Item -LiteralPath (Join-Path $runDirectory 'question.json') -Force -ErrorAction SilentlyContinue
        }
        if ($planWasApproved) { $Answer = '' }
        $state = $resumeState
        if (-not $rejectingPlan) {
            $state.pending_question = $null
            Set-Felix3RunStatus -State $state -Status $resumePhase
            $state.active_phase = $resumePhase
        }
        if (-not $state.PSObject.Properties['process']) { Add-Member -InputObject $state -NotePropertyName process -NotePropertyValue $null }
        if (-not $state.PSObject.Properties['finished_at']) { Add-Member -InputObject $state -NotePropertyName finished_at -NotePropertyValue $null }
    }
    else {
        $workItem = New-Felix3WorkItem -ProjectPath $project -Id $RequirementId -Title $Title -SpecPath $specFile
        Assert-Felix3WorkItemContract -WorkItem $workItem -SpecText $specText | Out-Null
        Write-Felix3Json -Path $workItemPath -Value $workItem
        [System.IO.File]::WriteAllText((Join-Path $runDirectory 'spec.md'), $specText, [System.Text.UTF8Encoding]::new($false))
        $state = [ordered]@{ schema = 'felix3-task-state-v2'; id = $RequirementId; run_id = $runId; status = 'new'; active_phase = 'planning'; started_at = [DateTime]::UtcNow.ToString('o'); phases = @(); validation = $null; outcome = $null; pending_question = $null; process = $null }
        Set-Felix3RunStatus -State $state -Status 'planning'
    }
    $journal = Initialize-Felix3RunJournal -RunDirectory $runDirectory -RunId $runId
    Remove-Item -LiteralPath (Join-Path $runDirectory 'cancel.requested') -Force -ErrorAction SilentlyContinue
    Write-Felix3AtomicJson -Path $statePath -Value $state
    $cloud = $null
    try { $cloud = Initialize-Felix3CloudSync -Config $config -ProjectPath $project -RunId $runId -RequirementId $RequirementId -Resume:$resuming }
    catch { Write-Warning 'Felix 3 cloud sync could not initialize; continuing with local execution only.'; $cloud = $null }
    $cloudSink = if ($cloud) { { param($event) Add-Felix3CloudEvent -Cloud $cloud -Event $event }.GetNewClosure() } else { $null }
    $runStartedEvent = Write-Felix3RunEvent -Journal $journal -Kind $(if ($resuming) { 'run.resumed' } else { 'run.started' }) -Payload @{ requirement_id = $RequirementId; resume_phase = $resumePhase } -Summary $(if ($resuming) { "Run resumed in $resumePhase." } else { "Run started for $RequirementId." })
    if ($cloud) { Add-Felix3CloudEvent -Cloud $cloud -Event $runStartedEvent }
    if ($rejectingPlan) {
        Set-Felix3RunStatus -State $state -Status 'blocked'; $state.active_phase = $null; $state.finished_at = [DateTime]::UtcNow.ToString('o'); $state.outcome = 'Plan rejected by human.'
        $rejectedEvent = Write-Felix3RunEvent -Journal $journal -Kind 'plan.rejected' -Phase 'planning' -Payload @{ requirement_id = $RequirementId } -Summary 'Plan rejected by human.'
        if ($cloud) { Add-Felix3CloudEvent -Cloud $cloud -Event $rejectedEvent }
        $blockedEvent = Write-Felix3RunEvent -Journal $journal -Kind 'run.blocked' -Payload @{ status = 'blocked' } -Summary $state.outcome
        if ($cloud) { Add-Felix3CloudEvent -Cloud $cloud -Event $blockedEvent; try { Complete-Felix3CloudSync -Cloud $cloud -Status 'blocked' -RunDirectory $runDirectory } catch { Write-Warning 'Felix 3 cloud sync could not finish cleanly; queued artifacts remain local.' } }
        Write-Felix3AtomicJson -Path $statePath -Value $state
        return [pscustomobject]@{ Status = 'blocked'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome }
    }
    if ($planWasApproved) {
        $approvedEvent = Write-Felix3RunEvent -Journal $journal -Kind 'plan.approved' -Phase 'planning' -Payload @{ requirement_id = $RequirementId } -Summary 'Plan approved by human.'
        if ($cloud) { Add-Felix3CloudEvent -Cloud $cloud -Event $approvedEvent }
    }
    if ($answeringQuestion) {
        $digestBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Answer))
        $digest = [System.BitConverter]::ToString($digestBytes).Replace('-', '').ToLowerInvariant()
        $answered = Write-Felix3RunEvent -Journal $journal -Kind 'question.answered' -Phase $resumePhase -Payload @{ answer_sha256 = $digest; answer_length = $Answer.Length } -Summary 'Human input recorded.'
        if ($cloud) { Add-Felix3CloudEvent -Cloud $cloud -Event $answered }
    }

    $invokePhase = {
        param([string]$Phase, [string]$Prompt, [string]$PhaseDirectory, [string]$ResumeSession)
        New-Item -ItemType Directory -Path $PhaseDirectory -Force | Out-Null
        $phaseConfig = Get-Felix3PhaseConfig -Config $config -Phase $Phase
        $session = if ($ResumeSession) { $ResumeSession } else { $null }
        $Prompt = Add-Felix3QuestionProtocol -Prompt $Prompt
        if ($resuming -and $Phase -eq $resumePhase -and $Answer) { $Prompt += "`n`n## Human answer to your pending question`n$Answer`nContinue the same phase and complete its requested output." }
        $eventSink = New-Felix3EventSink -Journal $journal -Phase $Phase -Harness $phaseConfig.provider -CloudSink $cloudSink
        if ($phaseConfig.provider -eq 'claude-code') {
            $harnessResult = Invoke-ClaudeHarness -Phase $Phase -WorkingDirectory $project -Prompt $Prompt -RunDirectory $PhaseDirectory -Executable $phaseConfig.executable -Model $phaseConfig.model -PermissionMode $phaseConfig.permission_mode -MaxTurns $phaseConfig.max_turns -SessionId $session -Journal $journal -EventSink $eventSink -CancelTokenPath (Join-Path $runDirectory 'cancel.requested')
        }
        elseif ($phaseConfig.provider -eq 'codex') {
            $harnessResult = Invoke-CodexHarness -Phase $Phase -WorkingDirectory $project -Prompt $Prompt -RunDirectory $PhaseDirectory -Executable $phaseConfig.executable -Model $phaseConfig.model -Sandbox $phaseConfig.sandbox -ApprovalPolicy $phaseConfig.approval_policy -SessionId $session -Journal $journal -EventSink $eventSink -CancelTokenPath (Join-Path $runDirectory 'cancel.requested')
        }
        else {
            $harnessResult = Invoke-OpenCodeHarness -Phase $Phase -WorkingDirectory $project -Prompt $Prompt -RunDirectory $PhaseDirectory -Executable $phaseConfig.executable -Model $phaseConfig.model -Agent $phaseConfig.agent -AutoApprove:$phaseConfig.auto_approve -SessionId $session -Journal $journal -EventSink $eventSink -CancelTokenPath (Join-Path $runDirectory 'cancel.requested')
        }
        return Assert-Felix3HarnessResultContract -Result $harnessResult -ExpectedHarness $phaseConfig.provider -ExpectedPhase $Phase
    }
    $templates = Join-Path $PSScriptRoot 'prompts'
    $sharedValues = @{
        WORK_ITEM_JSON = ($workItem | ConvertTo-Json -Compress)
        WORK_ITEM_ID = $RequirementId
        WORK_ITEM_TITLE = $Title
        SPEC_TEXT = $specText
        PROJECT_PATH = $project
        PLAN_PATH = $planPath
        REVIEW_PATH = $reviewPath
        VALIDATION_PATH = (Join-Path $runDirectory 'validation.json')
        VALIDATION_EVIDENCE = (Join-Path $runDirectory 'validation.json')
        VALIDATION_FAILURES = 'None. This is the first build attempt.'
        REVIEW_FINDINGS = 'None.'
        HUMAN_ANSWERS = if ($resuming -and $Answer) { $Answer } elseif (Test-Path -LiteralPath (Join-Path $runDirectory 'answer.md')) { Get-Content -LiteralPath (Join-Path $runDirectory 'answer.md') -Raw -Encoding UTF8 } else { 'No human decisions recorded.' }
    }

    try {
        if ($resuming -and $resumePhase -ne 'planning') {
            if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Cannot resume at $resumePhase because the saved plan is missing." }
            $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8
        }
        else {
        $planningPrompt = Read-Felix3Template -Path (Join-Path $templates 'planning.md') -Values $sharedValues
        if ($config.harness.provider -in @('opencode', 'codex')) {
            $planningPrompt = $planningPrompt.Replace('Write the plan to the exact required path. Include:', 'Return the complete plan as Markdown in your final response. Felix 3 will persist that response to the required plan path. Include:')
            $planningPrompt += "`n`nDo not attempt to modify files. Your final answer must contain the complete plan and nothing outside it."
        }
        Set-Felix3RunStatus -State $state -Status 'planning'; $state.active_phase = 'planning'
        Write-Felix3AtomicJson -Path $statePath -Value $state
        $planResult = & $invokePhase 'planning' $planningPrompt (Join-Path $runDirectory $(if ($resuming -and $resumeSession) { 'planning-resume' } else { 'planning' })) $(if ($resumePhase -eq 'planning') { $resumeSession } else { $null })
        if (Suspend-Felix3ForStop -Result $planResult -Phase planning -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'interrupted'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome } }
        if (Suspend-Felix3ForQuestion -Result $planResult -Phase planning -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'awaiting-input'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; PlanPath = $planPath; Outcome = 'Agent needs human input.' } }
        $state.phases += [pscustomobject]@{ name = 'planning'; status = if ($planResult.Succeeded) { 'succeeded' } else { 'failed' }; result = $planResult.ResultPath }
        if (-not $planResult.Succeeded) { throw "Planning harness failed: $($planResult.Error)" }
        if ($config.harness.provider -in @('opencode', 'codex') -and -not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
            Set-Content -LiteralPath $planPath -Value $planResult.ResultText -Encoding UTF8
        }
        if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Planning phase did not create the required plan: $planPath" }
        $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8
        foreach ($section in @('## Acceptance Coverage', '## Tasks', '## Validation')) {
            if ($planText -notmatch [regex]::Escape($section)) { throw "Plan is missing required section '$section'." }
        }
        if ($planText -notmatch '(?m)^\s*\|.+\|.+\|') { throw 'Plan acceptance coverage must contain a Markdown table with mapped criteria.' }
        if ($planText -notmatch '(?m)^\s*- \[ \] .+') { throw 'Plan must contain at least one unchecked implementation task.' }
        if ($config.workflow.require_plan_approval -and -not ($resuming -and $resumePhase -eq 'building')) {
            Set-Felix3RunStatus -State $state -Status 'awaiting-plan-approval'
            $state.active_phase = 'building'
            $state.outcome = 'Plan created; human approval is required before building.'
            $state.finished_at = $null
            Write-Felix3AtomicJson -Path $statePath -Value $state
            $approvalEvent = Write-Felix3RunEvent -Journal $journal -Kind 'plan.approval_requested' -Phase 'planning' -Payload @{ requirement_id = $RequirementId; plan_path = $planPath } -Summary 'Plan is waiting for human approval.'
            if ($cloud) { Add-Felix3CloudEvent -Cloud $cloud -Event $approvalEvent }
            return [pscustomobject]@{ Status = $state.status; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; PlanPath = $planPath; Outcome = $state.outcome }
        }
        }

        Set-Felix3RunStatus -State $state -Status 'building'; $state.active_phase = 'building'
        Write-Felix3AtomicJson -Path $statePath -Value $state
        $buildSessionPolicy = (Get-Felix3PhaseConfig -Config $config -Phase building).session_policy
        $reviewSessionPolicy = (Get-Felix3PhaseConfig -Config $config -Phase reviewing).session_policy
        $buildPromptBase = Read-Felix3Template -Path (Join-Path $templates 'building.md') -Values $sharedValues
        $latestBuild = $null
        $validation = $null
        $firstBuildAttempt = if ($resuming -and $resumePhase -eq 'building') { $resumeAttempt } else { 1 }
        if ($resuming -and $resumePhase -eq 'reviewing' -and $state.validation -and (Test-Path -LiteralPath $state.validation -PathType Leaf)) {
            $savedValidation = Get-Content -LiteralPath $state.validation -Raw -Encoding UTF8 | ConvertFrom-Json
            $validation = [pscustomobject]@{ Passed = [bool]$savedValidation.passed; Results = @($savedValidation.commands); Path = [string]$state.validation }
        }
        if (-not ($resuming -and $resumePhase -eq 'reviewing')) { for ($attempt = $firstBuildAttempt; $attempt -le [int]$config.workflow.max_build_attempts; $attempt++) {
            $buildPrompt = $buildPromptBase + "`n`n## Attempt`nThis is build attempt $attempt of $($config.workflow.max_build_attempts). Complete every unfinished task in the plan."
            if ($latestBuild -and -not $latestBuild.Succeeded) { $buildPrompt += "`nPrevious harness error: $($latestBuild.Error)" }
            $buildSession = if ($resuming -and $resumePhase -eq 'building' -and $attempt -eq $firstBuildAttempt) { $resumeSession } elseif ($buildSessionPolicy -eq 'resume' -and $attempt -gt 1 -and $latestBuild) { $latestBuild.SessionId } else { $null }
            $phaseFolder = if ($resuming -and $resumePhase -eq 'building' -and $attempt -eq $firstBuildAttempt) { "building-$attempt-resume" } else { "building-$attempt" }
            $latestBuild = & $invokePhase 'building' $buildPrompt (Join-Path $runDirectory $phaseFolder) $buildSession
            if (Suspend-Felix3ForStop -Result $latestBuild -Phase building -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'interrupted'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome } }
            if (Suspend-Felix3ForQuestion -Result $latestBuild -Phase building -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Attempt $attempt -Cloud $cloud) { return [pscustomobject]@{ Status = 'awaiting-input'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = 'Agent needs human input.' } }
            $state.phases += [pscustomobject]@{ name = "building-$attempt"; status = if ($latestBuild.Succeeded) { 'succeeded' } else { 'failed' }; result = $latestBuild.ResultPath }
            if (-not $latestBuild.Succeeded) { continue }
            $validation = Invoke-Felix3Validation -Config $config -ProjectPath $project -RunDirectory $runDirectory -Journal $journal -CancelTokenPath (Join-Path $runDirectory 'cancel.requested')
            if (Suspend-Felix3ForStop -Result $validation -Phase building -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'interrupted'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome } }
            $validationEvent = Write-Felix3RunEvent -Journal $journal -Kind 'validation.completed' -Phase 'validation' -Harness 'felix3' -Payload @{ passed = $validation.Passed; commands = $validation.Results.Count } -Summary $(if ($validation.Passed) { 'Independent validation passed.' } else { 'Independent validation failed.' })
            Add-Felix3CloudEvent -Cloud $cloud -Event $validationEvent
            $state.validation = $validation.Path
            if ($validation.Passed) { break }
            $failureSummary = ($validation.Results | Where-Object { -not $_.passed } | ForEach-Object { "- $($_.name) exited $($_.exit_code):`n$($_.output)" }) -join "`n"
            $buildPromptBase += "`n`n## Validation failures to fix`n$failureSummary"
            $sharedValues['VALIDATION_FAILURES'] = $failureSummary
        } }
        if (-not $validation -or -not $validation.Passed) { throw 'Independent validation did not pass within the configured build attempts.' }

        Set-Felix3RunStatus -State $state -Status 'reviewing'; $state.active_phase = 'reviewing'
        Write-Felix3AtomicJson -Path $statePath -Value $state
        $approved = $false
        $latestReview = $null
        $firstReviewCycle = if ($resuming -and $resumePhase -eq 'reviewing') { $resumeCycle } else { 1 }
        for ($cycle = $firstReviewCycle; $cycle -le [int]$config.workflow.max_review_cycles; $cycle++) {
            $reviewValues = @{} + $sharedValues
            $reviewValues['VALIDATION_EVIDENCE'] = $validation.Path
            $reviewPrompt = Read-Felix3Template -Path (Join-Path $templates 'reviewing.md') -Values $reviewValues
            if ($config.harness.provider -in @('opencode', 'codex')) {
                $reviewPrompt = $reviewPrompt.Replace('Write one JSON object to the exact review output path:', 'Return one JSON object as your complete final response. Felix 3 will persist it to the required review output path:')
                $reviewPrompt += "`n`nDo not modify any files. Return only the JSON object without Markdown fences or surrounding commentary."
            }
            Remove-Item -LiteralPath $reviewPath -Force -ErrorAction SilentlyContinue
            $reviewSession = if ($resuming -and $resumePhase -eq 'reviewing' -and $cycle -eq $firstReviewCycle) { $resumeSession } elseif ($reviewSessionPolicy -eq 'resume' -and $cycle -gt 1 -and $latestReview) { $latestReview.SessionId } else { $null }
            $reviewFolder = if ($reviewSession) { "reviewing-$cycle-resume" } else { "reviewing-$cycle" }
            $reviewResult = & $invokePhase 'reviewing' $reviewPrompt (Join-Path $runDirectory $reviewFolder) $reviewSession
            if (Suspend-Felix3ForStop -Result $reviewResult -Phase reviewing -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'interrupted'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome } }
            if (Suspend-Felix3ForQuestion -Result $reviewResult -Phase reviewing -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cycle $cycle -Cloud $cloud) { return [pscustomobject]@{ Status = 'awaiting-input'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; PlanPath = $planPath; Outcome = 'Agent needs human input.' } }
            $latestReview = $reviewResult
            $state.phases += [pscustomobject]@{ name = "reviewing-$cycle"; status = if ($reviewResult.Succeeded) { 'succeeded' } else { 'failed' }; result = $reviewResult.ResultPath }
            if (-not $reviewResult.Succeeded) { throw "Review harness failed: $($reviewResult.Error)" }
            if ($config.harness.provider -in @('opencode', 'codex') -and $reviewResult.ResultText) {
                $reviewJsonText = ConvertTo-Felix3ReviewJsonText -Text $reviewResult.ResultText
                Set-Content -LiteralPath $reviewPath -Value $reviewJsonText -Encoding UTF8
            }
            if (-not (Test-Path -LiteralPath $reviewPath -PathType Leaf)) { throw "Review phase did not create required JSON: $reviewPath" }
            try { $review = Get-Content -LiteralPath $reviewPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
            catch { throw "Review JSON is invalid: $($_.Exception.Message)" }
            if ($review.decision -eq 'approved') { $approved = $true; break }
            if ($review.decision -ne 'changes_requested') { throw "Unknown review decision '$($review.decision)'." }
            if ($cycle -lt [int]$config.workflow.max_review_cycles) {
                Set-Felix3RunStatus -State $state -Status 'building'
                Write-Felix3AtomicJson -Path $statePath -Value $state
                $fixPrompt = $buildPromptBase + "`n`n## Review findings to resolve`n" + (Get-Content -LiteralPath $reviewPath -Raw -Encoding UTF8)
                $fixResumeSession = if ($buildSessionPolicy -eq 'resume' -and $latestBuild -and $latestBuild.SessionId) { $latestBuild.SessionId } elseif ($buildSessionPolicy -eq 'resume') { Get-Felix3LastSessionId -EventPath (Join-Path $runDirectory 'events.jsonl') -Phase building } else { $null }
                $fixResult = & $invokePhase 'building' $fixPrompt (Join-Path $runDirectory ("review-fixes-$cycle")) $fixResumeSession
                if (Suspend-Felix3ForStop -Result $fixResult -Phase building -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'interrupted'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome } }
                if (Suspend-Felix3ForQuestion -Result $fixResult -Phase building -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cycle $cycle -Cloud $cloud) { return [pscustomobject]@{ Status = 'awaiting-input'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = 'Agent needs human input.' } }
                $state.phases += [pscustomobject]@{ name = "review-fixes-$cycle"; status = if ($fixResult.Succeeded) { 'succeeded' } else { 'failed' }; result = $fixResult.ResultPath }
                if (-not $fixResult.Succeeded) { throw "Review fix harness failed: $($fixResult.Error)" }
                $latestBuild = $fixResult
                $validation = Invoke-Felix3Validation -Config $config -ProjectPath $project -RunDirectory $runDirectory -Journal $journal -CancelTokenPath (Join-Path $runDirectory 'cancel.requested')
                if (Suspend-Felix3ForStop -Result $validation -Phase building -State $state -StatePath $statePath -RunDirectory $runDirectory -Journal $journal -Cloud $cloud) { return [pscustomobject]@{ Status = 'interrupted'; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; Outcome = $state.outcome } }
                $validationEvent = Write-Felix3RunEvent -Journal $journal -Kind 'validation.completed' -Phase 'validation' -Harness 'felix3' -Payload @{ passed = $validation.Passed; commands = $validation.Results.Count } -Summary $(if ($validation.Passed) { 'Independent validation passed.' } else { 'Independent validation failed.' })
                Add-Felix3CloudEvent -Cloud $cloud -Event $validationEvent
                if (-not $validation.Passed) { throw 'Validation failed after review fixes.' }
            }
        }
        if (-not $approved) { throw 'Review did not approve the implementation within the configured review cycles.' }
        Set-Felix3RunStatus -State $state -Status 'completed'
        $state.outcome = 'Plan completed, independent validation passed, and review approved.'
    }
    catch {
        Set-Felix3RunStatus -State $state -Status 'blocked'
        $state.outcome = $_.Exception.Message
    }

    $state.finished_at = [DateTime]::UtcNow.ToString('o')
    if ($state.status -eq 'completed') { $state.active_phase = $null }
    $usageSummary = $null
    if (Test-Path -LiteralPath (Join-Path $runDirectory 'usage.json') -PathType Leaf) { try { $usageSummary = (Get-Content -LiteralPath (Join-Path $runDirectory 'usage.json') -Raw -Encoding UTF8 | ConvertFrom-Json).totals } catch { } }
    Write-Felix3RunEvent -Journal $journal -Kind $(if ($state.status -eq 'completed') { 'run.completed' } else { 'run.blocked' }) -Payload @{ status = $state.status; usage = $usageSummary } -Summary ([string]$state.outcome) | Out-Null
    if ($cloud) {
        try { Complete-Felix3CloudSync -Cloud $cloud -Status $(if ($state.status -eq 'completed') { 'completed' } else { 'failed' }) -RunDirectory $runDirectory }
        catch { Write-Warning 'Felix 3 cloud sync could not finish cleanly; queued artifacts remain local.' }
    }
    Write-Felix3AtomicJson -Path $statePath -Value $state
    return [pscustomobject]@{ Status = $state.status; RunId = $runId; RunDirectory = $runDirectory; StatePath = $statePath; PlanPath = if (Test-Path $planPath) { $planPath } else { $null }; ReviewPath = if (Test-Path $reviewPath) { $reviewPath } else { $null }; ValidationPath = $state.validation; Outcome = $state.outcome }
}

function Resume-Felix3Task {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RunId,
        [string]$Answer,
        [string]$ConfigPath = '.felix3/config.json'
    )
    $project = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $config = Import-Felix3Config -Path (Resolve-Felix3Path -Path $ConfigPath -BasePath $project)
    $runsRoot = Resolve-Felix3Path -Path ([string]$config.artifacts.runs_dir) -BasePath $project
    $runDirectory = Resolve-Felix3RunDirectory -RunsRoot $runsRoot -RunId $RunId
    if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) { throw "Felix 3 run not found: $RunId" }
    $workItem = Get-Content -LiteralPath (Join-Path $runDirectory 'work-item.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    return Invoke-Felix3Task -ProjectPath $project -RequirementId ([string]$workItem.id) -Title ([string]$workItem.title) -SpecPath (Join-Path $runDirectory 'spec.md') -ConfigPath $ConfigPath -ResumeRunId $RunId -Answer $Answer
}

function Stop-Felix3Task {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string]$RunId, [string]$ConfigPath = '.felix3/config.json')
    $project = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $config = Import-Felix3Config -Path (Resolve-Felix3Path -Path $ConfigPath -BasePath $project)
    $runsRoot = Resolve-Felix3Path -Path ([string]$config.artifacts.runs_dir) -BasePath $project
    $runDirectory = Resolve-Felix3RunDirectory -RunsRoot $runsRoot -RunId $RunId
    if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) { throw "Felix 3 run not found: $RunId" }
    $statePath = Join-Path $runDirectory 'state.json'
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.status -in @('completed','failed','blocked','awaiting-input','awaiting-plan-approval')) { throw "Run '$RunId' is not active (status: $($state.status))." }
    Set-Content -LiteralPath (Join-Path $runDirectory 'cancel.requested') -Value ([DateTime]::UtcNow.ToString('o')) -Encoding UTF8
    Set-Felix3RunStatus -State $state -Status 'stop-requested'
    Write-Felix3AtomicJson -Path $statePath -Value $state
    return [pscustomobject]@{ RunId = $RunId; Status = 'stop-requested'; Message = 'Cancellation token written; the active harness process will stop at its next poll.' }
}

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Invoke-Felix3Task.ps1')

class Fel3TestCloudClient {
    [object[]]$Events = @()
    [int]$FinishCount = 0
    [int]$FlushCount = 0
    [void] AppendEvents([string]$RunId, [array]$Events) { $this.Events = @($Events) }
    [void] Flush() { $this.FlushCount++ }
    [void] FinishRun([string]$RunId, [hashtable]$Result) { $this.FinishCount++ }
    [void] UploadArtifact([string]$RunId, [string]$RelativePath, [string]$LocalPath) { }
}

function Assert-Felix3 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Felix 3 test failed: $Message" }
}

function New-FakeCli {
    param([string]$Root, [string]$Name, [string]$Source)
    $python = (Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $scriptPath = Join-Path $Root "$Name.py"
    $shimPath = Join-Path $Root "$Name.cmd"
    Set-Content -LiteralPath $scriptPath -Value $Source -Encoding ASCII
    Set-Content -LiteralPath $shimPath -Value "@echo off`r`n`"$python`" `"$scriptPath`" %*" -Encoding ASCII
    return $shimPath
}

$tempRoot = Join-Path $PSScriptRoot (".test-run-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    # Stable V3 work-item, harness-result, event, and state-transition contracts.
    $contractProject = Join-Path $tempRoot 'contract-project'
    $contractSpecs = Join-Path $contractProject 'specs'
    New-Item -ItemType Directory -Path $contractSpecs -Force | Out-Null
    $localSpecA = Join-Path $contractSpecs 'S-READY.md'
    $localSpecB = Join-Path $contractSpecs 'S-BLOCKED.md'
    [IO.File]::WriteAllText($localSpecA, "---`nid: S-READY`ntitle: Ready example`nstatus: ready-for-agent`n---`n# Ready spec`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($localSpecB, "---`nid: S-BLOCKED`ntitle: Blocked example`nstatus: ready-for-agent`ndepends_on: [S-DEP]`n---`n# Blocked spec`n", [Text.UTF8Encoding]::new($false))
    $localSourceConfig = [pscustomobject]@{ work_source = [pscustomobject]@{ specs_dir = 'specs'; ready_status = 'ready-for-agent' } }
    $selectedLocalSpec = Get-Felix3ReadyLocalSpec -ProjectPath $contractProject -Config $localSourceConfig
    Assert-Felix3 ($selectedLocalSpec.Id -eq 'S-READY' -and $selectedLocalSpec.Title -eq 'Ready example') 'local work source selects a ready spec and skips unmet dependencies'
    Set-Felix3LocalSpecStatus -Path $localSpecA -Status 'in-progress'
    Assert-Felix3 ((Get-Felix3SpecMetadata -Path $localSpecA)['status'] -eq 'in-progress') 'local work source persists spec status changes'
    $contractSpec = Join-Path $contractSpecs 'S-1.md'
    $contractSpecText = "# Contract spec`n`nAcceptance: preserve the supplied requirement snapshot.`n"
    [System.IO.File]::WriteAllText($contractSpec, $contractSpecText, [System.Text.UTF8Encoding]::new($false))
    $workItem = New-Felix3WorkItem -ProjectPath $contractProject -Id ' S-1 ' -Title ' Contract example ' -SpecPath 'specs/S-1.md' -DependsOn @('S-0','S-0','')
    Assert-Felix3 ($workItem.schema -eq 'felix3-work-item-v1' -and $workItem.id -eq 'S-1' -and $workItem.source.provider -eq 'manual-spec') 'work item normalizes IDs and records its source'
    Assert-Felix3 ($workItem.spec_path -eq 'specs/S-1.md' -and $workItem.depends_on.Count -eq 1) 'work item paths and dependencies are normalized'
    Assert-Felix3 ($workItem.spec_sha256 -eq (Get-Felix3Sha256Hex -Text $contractSpecText)) 'work item digest binds the exact specification snapshot'
    Assert-Felix3 ((Assert-Felix3WorkItemContract -WorkItem $workItem -SpecText $contractSpecText).id -eq 'S-1') 'valid work item satisfies the shared source contract'
    foreach ($badSpecPath in @('../outside.md', [System.IO.Path]::GetFullPath((Join-Path $tempRoot 'outside.md')))) {
        $rejected = $false
        try { New-Felix3WorkItem -ProjectPath $contractProject -Id 'S-X' -SpecPath $badSpecPath | Out-Null } catch { $rejected = $true }
        Assert-Felix3 $rejected 'work item specs cannot escape the project directory'
    }
    $tamperedWorkItem = $workItem | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $tamperedWorkItem.spec_sha256 = '0' * 64
    $rejectedDigest = $false
    try { Assert-Felix3WorkItemContract -WorkItem $tamperedWorkItem -SpecText $contractSpecText | Out-Null } catch { $rejectedDigest = $true }
    Assert-Felix3 $rejectedDigest 'work item contract rejects spec snapshot mismatch'
    Assert-Felix3 (Assert-Felix3RunStateTransition -From 'planning' -To 'building') 'planning can advance to building'
    Assert-Felix3 (Assert-Felix3RunStateTransition -From 'reviewing' -To 'building') 'review findings can route work back to building'
    foreach ($transition in @(@('completed','building'), @('awaiting-plan-approval','reviewing'), @('blocked','building'))) {
        $rejected = $false
        try { Assert-Felix3RunStateTransition -From $transition[0] -To $transition[1] | Out-Null } catch { $rejected = $true }
        Assert-Felix3 $rejected "invalid run state transition is rejected: $($transition[0]) -> $($transition[1])"
    }

    $runBoundaryRoot = Join-Path $tempRoot 'runs-boundary'
    New-Item -ItemType Directory -Path $runBoundaryRoot -Force | Out-Null
    $safeRunDirectory = Resolve-Felix3RunDirectory -RunsRoot $runBoundaryRoot -RunId 'S-0001-20261013-123456-abcd1234'
    Assert-Felix3 ($safeRunDirectory.StartsWith([System.IO.Path]::GetFullPath($runBoundaryRoot), [System.StringComparison]::OrdinalIgnoreCase)) 'valid run IDs stay under the runs directory'
    foreach ($unsafeRunId in @('..', '../outside', 'nested/run', [System.IO.Path]::GetFullPath((Join-Path $tempRoot 'outside')))) {
        $rejected = $false
        try { Resolve-Felix3RunDirectory -RunsRoot $runBoundaryRoot -RunId $unsafeRunId | Out-Null } catch { $rejected = $true }
        Assert-Felix3 $rejected "unsafe run ID is rejected: $unsafeRunId"
    }
    foreach ($configPath in @(
        (Join-Path $PSScriptRoot '..\felix3.config.example.json'),
        (Join-Path $PSScriptRoot '..\opencode\felix3-opencode.config.example.json'),
        (Join-Path $PSScriptRoot '..\codex\felix3-codex.config.example.json')
    )) {
        $loadedConfig = Import-Felix3Config -Path (Resolve-Path -LiteralPath $configPath).Path
        Assert-Felix3 ($loadedConfig.harness.provider -in @('claude-code','opencode','codex')) "example config validates: $(Split-Path $configPath -Leaf)"
    }
    $savedSyncUrl = $env:FELIX_SYNC_URL
    try {
        Remove-Item Env:FELIX_SYNC_URL -ErrorAction SilentlyContinue
        Assert-Felix3 ((Resolve-Felix3CloudBaseUrl -Settings ([pscustomobject]@{})) -eq 'https://runfelix.io') 'cloud sync defaults to the documented Felix endpoint'
        Assert-Felix3 ((Resolve-Felix3CloudBaseUrl -Settings ([pscustomobject]@{ base_url = 'https://custom.example' })) -eq 'https://custom.example') 'cloud sync honors its configured endpoint'
        $env:FELIX_SYNC_URL = 'https://env.example'
        Assert-Felix3 ((Resolve-Felix3CloudBaseUrl -Settings ([pscustomobject]@{ base_url = 'https://custom.example' })) -eq 'https://env.example') 'cloud sync environment URL overrides configuration'
    }
    finally { if ($null -eq $savedSyncUrl) { Remove-Item Env:FELIX_SYNC_URL -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_URL = $savedSyncUrl } }

    $cloudRequestLog = [System.Collections.ArrayList]::new()
    $cloudApiRequest = {
        param($Method, $Uri, $Headers, $Body)
        [void]$cloudRequestLog.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Headers = $Headers; Body = $Body })
        if ($Uri -match '/api/sync/work/next\?') { return @{ code='C-42'; title='Cloud requirement'; spec_path='specs/C-42.md'; priority='high'; depends_on=@('C-10') } }
        if ($Uri -match '/api/sync/specs/file\?') { return "# Cloud spec`n`nAcceptance criteria: retain the source snapshot.`n" }
        return @{ status='ok' }
    }.GetNewClosure()
    $cloudAgentId = '74c9552d-664e-4cf3-a9fb-0b0c0e1ce9e2'
    $cloudSource = New-Felix3CloudWorkSource -BaseUrl 'https://cloud.example/' -ApiKey 'fsk-test-secret' -AgentId $cloudAgentId -ProjectPath $tempRoot -Request $cloudApiRequest
    $cloudClaim = ClaimNext-Felix3CloudWorkItem -Source $cloudSource
    Assert-Felix3 ($cloudClaim.WorkItem.id -eq 'C-42' -and $cloudClaim.WorkItem.source.provider -eq 'felix-cloud') 'Cloud claim normalizes its identity and source'
    Assert-Felix3 ($cloudClaim.WorkItem.priority -eq 'high' -and $cloudClaim.WorkItem.depends_on[0] -eq 'C-10') 'Cloud claim preserves priority and dependencies'
    Assert-Felix3 ((Test-Path -LiteralPath $cloudClaim.SpecPath) -and $cloudClaim.WorkItem.spec_sha256 -eq (Get-Felix3Sha256Hex -Text $cloudClaim.SpecText)) 'Cloud claim materializes and hashes its local spec snapshot'
    Assert-Felix3 ($cloudRequestLog[0].Uri -match [regex]::Escape($cloudAgentId) -and $cloudRequestLog[0].Headers.Authorization -eq 'Bearer fsk-test-secret') 'Cloud claim scopes the request to configured agent and API key'
    Start-Felix3CloudWorkItem -Source $cloudSource -RequirementId 'C-42' | Out-Null
    Complete-Felix3CloudWorkItem -Source $cloudSource -RequirementId 'C-42' | Out-Null
    Release-Felix3CloudWorkItem -Source $cloudSource -RequirementId 'C-42' | Out-Null
    Assert-Felix3 (($cloudRequestLog | Where-Object { $_.Uri -match '/work/start$' }).Count -eq 1 -and ($cloudRequestLog | Where-Object { $_.Uri -match '/work/complete$' }).Count -eq 1 -and ($cloudRequestLog | Where-Object { $_.Uri -match '/work/release$' }).Count -eq 1) 'Cloud work lifecycle maps start, complete, and release endpoints'
    $conflictException = [System.Exception]::new('already started')
    Add-Member -InputObject $conflictException -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 409 })
    $conflictRequest = { param($Method,$Uri,$Headers,$Body) throw $conflictException }.GetNewClosure()
    $conflictSource = New-Felix3CloudWorkSource -BaseUrl 'https://cloud.example' -ApiKey 'secret' -AgentId $cloudAgentId -ProjectPath $tempRoot -Request $conflictRequest
    Assert-Felix3 ((Start-Felix3CloudWorkItem -Source $conflictSource -RequirementId 'C-42').status -eq 'already-started') 'Cloud start conflict after a same-agent claim is treated as a resumed start'
    $unsafeCloudRequest = { param($Method, $Uri, $Headers, $Body) return @{ code='C-X'; title='unsafe'; spec_path='../outside.md'; depends_on=@() } }.GetNewClosure()
    $unsafeCloudSource = New-Felix3CloudWorkSource -BaseUrl 'https://cloud.example' -ApiKey 'secret' -AgentId $cloudAgentId -ProjectPath $tempRoot -Request $unsafeCloudRequest
    $unsafeCloudRejected = $false
    try { ClaimNext-Felix3CloudWorkItem -Source $unsafeCloudSource | Out-Null } catch { $unsafeCloudRejected = $true }
    Assert-Felix3 $unsafeCloudRejected 'Cloud claim rejects spec paths that escape the Cloud specs directory'
    $invalidCloudIdentityRejected = $false
    try { New-Felix3CloudWorkSource -BaseUrl 'https://cloud.example' -ApiKey 'secret' -AgentId 'felix-v2-profile' -ProjectPath $tempRoot | Out-Null } catch { $invalidCloudIdentityRejected = $true }
    Assert-Felix3 $invalidCloudIdentityRejected 'Cloud work source requires an explicit Cloud UUID rather than a Felix 2 profile key'

    $cloudProject = Join-Path $tempRoot 'cloud-cycle-project'
    $cloudConfigPath = Join-Path (Join-Path $cloudProject '.felix3') 'config.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cloudConfigPath) -Force | Out-Null
    $cloudCycleConfig = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\opencode\felix3-opencode.config.example.json') -Raw | ConvertFrom-Json
    $cloudCycleConfig.work_source.provider = 'felix-cloud'
    $cloudCycleConfig.work_source.cloud.agent_id = $cloudAgentId
    $cloudCycleConfig.cloud_sync.api_key = 'fsk-test-secret'
    $cloudCycleConfig | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $cloudConfigPath -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $cloudProject 'specs') -Force | Out-Null
    $savedCycleApiKey = $env:FELIX_SYNC_KEY
    $savedTaskFunction = (Get-Command Invoke-Felix3Task -CommandType Function).ScriptBlock
    $savedResumeFunction = (Get-Command Resume-Felix3Task -CommandType Function).ScriptBlock
    $cloudCycleApiLog = [System.Collections.ArrayList]::new()
    $cloudCycleRequest = {
        param($Method, $Uri, $Headers, $Body)
        [void]$cloudCycleApiLog.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
        if ($Uri -match '/api/sync/work/next\?') { return @{ code=$global:felix3TestCloudCode; title='Cloud cycle test'; spec_path="specs/$global:felix3TestCloudCode.md"; priority='medium'; depends_on=@() } }
        if ($Uri -match '/api/sync/specs/file\?') { return "# $global:felix3TestCloudCode`n`nAcceptance: exercise the Cloud cycle.`n" }
        return @{ status='ok' }
    }.GetNewClosure()
    try {
        $env:FELIX_SYNC_KEY = 'fsk-test-secret'
        Set-Item -Path Function:\Invoke-Felix3Task -Value { param($ProjectPath,$RequirementId,$Title,$SpecPath,$ConfigPath,$WorkItem,$NewRunId,$ResumeRunId,$Answer) return [pscustomobject]@{ Status = $global:felix3TestCloudTaskStatus; RunId = $NewRunId } }
        Set-Item -Path Function:\Resume-Felix3Task -Value { param($ProjectPath,$RunId,$Answer,$ConfigPath) return [pscustomobject]@{ Status = $global:felix3TestCloudTaskStatus; RunId = $RunId } }
        $global:felix3TestCloudCode = 'C-100'; $global:felix3TestCloudTaskStatus = 'completed'
        $completedCloudCycle = Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest
        Assert-Felix3 ($completedCloudCycle.Status -eq 'completed' -and ($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/complete$' }).Count -eq 1) 'Cloud cycle completes the source item only after task completion'
        $global:felix3TestCloudCode = 'C-101'; $global:felix3TestCloudTaskStatus = 'awaiting-input'
        $waitingCloudCycle = Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest
        $nextCountBeforeResume = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/next\?' }).Count
        $claimExistsWhileWaiting = Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $cloudProject '.felix3') 'work-source') 'cloud-claim.json')
        Assert-Felix3 ($waitingCloudCycle.Status -eq 'awaiting-input' -and $claimExistsWhileWaiting) 'Cloud cycle retains claims while awaiting human input'
        $global:felix3TestCloudTaskStatus = 'completed'
        $resumedCloudCycle = Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Answer 'Proceed' -Request $cloudCycleRequest
        $nextCountAfterResume = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/next\?' }).Count
        Assert-Felix3 ($resumedCloudCycle.Status -eq 'completed' -and $nextCountAfterResume -eq $nextCountBeforeResume) 'Cloud cycle resumes its saved claim before polling for more work'
        $global:felix3TestCloudCode = 'C-102'; $global:felix3TestCloudTaskStatus = 'blocked'
        $blockedCloudCycle = Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest
        Assert-Felix3 ($blockedCloudCycle.Status -eq 'blocked' -and ($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/release$' }).Count -eq 1) 'Cloud cycle releases a blocked source item'
        $cycleLockPath = Join-Path (Join-Path (Join-Path $cloudProject '.felix3') 'work-source') 'cloud-cycle.lock'
        $heldCycleLock = [System.IO.File]::Open($cycleLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $concurrentCycleRejected = $false
            try { Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest | Out-Null } catch { $concurrentCycleRejected = $true }
            Assert-Felix3 $concurrentCycleRejected 'Cloud cycle lock prevents two workers using the same checkout'
        }
        finally { $heldCycleLock.Dispose() }
    }
    finally {
        Set-Item -Path Function:\Invoke-Felix3Task -Value $savedTaskFunction
        Set-Item -Path Function:\Resume-Felix3Task -Value $savedResumeFunction
        Remove-Variable -Name felix3TestCloudCode,felix3TestCloudTaskStatus -Scope Global -ErrorAction SilentlyContinue
        if ($null -eq $savedCycleApiKey) { Remove-Item Env:FELIX_SYNC_KEY -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_KEY = $savedCycleApiKey }
    }

    $savedSyncEnabled = $env:FELIX_SYNC_ENABLED; $savedSyncKey = $env:FELIX_SYNC_KEY; $savedAgentKey = $env:FELIX_SYNC_AGENT_KEY
    try {
        $env:FELIX_SYNC_ENABLED = 'true'; Remove-Item Env:FELIX_SYNC_KEY,Env:FELIX_SYNC_AGENT_KEY -ErrorAction SilentlyContinue
        $cloudConfig = [pscustomobject]@{ harness = [pscustomobject]@{ provider = 'codex' }; cloud_sync = [pscustomobject]@{ enabled = $true; artifacts = @() } }
        $cloudDisabled = Initialize-Felix3CloudSync -Config $cloudConfig -ProjectPath $tempRoot -RunId 'no-cloud-creds' -RequirementId 'S-1'
        Assert-Felix3 ($null -eq $cloudDisabled) 'missing optional cloud credentials do not block local runs'
    }
    finally {
        if ($null -eq $savedSyncEnabled) { Remove-Item Env:FELIX_SYNC_ENABLED -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_ENABLED = $savedSyncEnabled }
        if ($null -eq $savedSyncKey) { Remove-Item Env:FELIX_SYNC_KEY -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_KEY = $savedSyncKey }
        if ($null -eq $savedAgentKey) { Remove-Item Env:FELIX_SYNC_AGENT_KEY -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_AGENT_KEY = $savedAgentKey }
    }

    # Normalized durable journal, redaction, question parsing, and usage totals.
    $journal = Initialize-Felix3RunJournal -RunDirectory $tempRoot -RunId 'journal-test'
    Write-Felix3RunEvent -Journal $journal -Kind 'run.started' -Summary 'started' | Out-Null
    Write-Felix3RunEvent -Journal $journal -Kind 'phase.started' -Phase 'building' -Summary 'api_key=secret-value' | Out-Null
    $journalLines = @(Get-Content -LiteralPath $journal.EventPath)
    Assert-Felix3 ($journalLines.Count -eq 2) 'event journal appends one complete JSON record per event'
    $eventTwo = $journalLines[1] | ConvertFrom-Json
    Assert-Felix3 ($eventTwo.seq -eq 2 -and $eventTwo.summary -match '\[REDACTED\]') 'events have stable sequence and redacted summaries'
    Assert-Felix3 ((Assert-Felix3RunEventContract -Event $eventTwo).event_id -eq 'journal-test:2') 'run events satisfy the durable event contract'
    $invalidEvent = [pscustomobject]@{ schema='felix3-event-v1'; event_id='wrong'; run_id='journal-test'; seq=3; timestamp=[DateTime]::UtcNow.ToString('o'); kind='phase.started'; phase='building'; harness='codex'; summary=''; payload=$null }
    $rejectedEvent = $false
    try { Assert-Felix3RunEventContract -Event $invalidEvent | Out-Null } catch { $rejectedEvent = $true }
    Assert-Felix3 $rejectedEvent 'run event contract rejects inconsistent event identity'
    $knownTokenLeak = Protect-Felix3Text -Text 'Provider returned key sk-or-v1-0123456789abcdefghijklmnop and github_pat_abcdefghijklmnopqrstuvwxyz123456'
    Assert-Felix3 ($knownTokenLeak -notmatch 'sk-or-v1-|github_pat_') 'common provider and source-control tokens are redacted from summaries'
    $question = Get-Felix3QuestionFromText '<felix3-question>{"question":"Choose?","choices":["A","B"],"context":"Public API choice"}</felix3-question>'
    Assert-Felix3 ($question.question -eq 'Choose?' -and $question.choices.Count -eq 2) 'Felix question marker parses into a structured question'
    $nativeQuestionSafe = ConvertFrom-Felix3QuestionData -Data @(@{ question = 'Choose a model?'; options = @(@{ label = 'DeepSeek' }, @{ label = 'key=sk-or-v1-0123456789abcdefghijklmnop' }) })
    Assert-Felix3 ($nativeQuestionSafe.choices[1] -match '\[REDACTED\]' -and $nativeQuestionSafe.choices[1] -notmatch 'sk-or-v1-') 'native question choices redact credential-like strings before persistence'
    $usageA = ConvertTo-Felix3UsageRecord -Harness 'codex' -Phase 'building' -PhaseInstance 'building-1' -Model 'm' -Usage @{ input_tokens = 10; output_tokens = 4; total_tokens = 14 } -CostUsd $null -DurationSeconds 1 -SessionId 's'
    Update-Felix3UsageSummary -RunDirectory $tempRoot -UsageRecord $usageA | Out-Null
    $usageB = ConvertTo-Felix3UsageRecord -Harness 'opencode' -Phase 'building' -PhaseInstance 'building-2' -Model 'm' -Usage @{ input = 5; output = 2; total = 7; cache = @{ read = 3 }; reasoning = 1 } -CostUsd 0.001 -DurationSeconds 2 -SessionId 's'
    $usagePath = Update-Felix3UsageSummary -RunDirectory $tempRoot -UsageRecord $usageB
    $usageUnknown = ConvertTo-Felix3UsageRecord -Harness 'codex' -Phase 'reviewing' -PhaseInstance 'review-1' -Model 'm' -Usage $null -CostUsd $null -DurationSeconds 1 -SessionId 's'
    Update-Felix3UsageSummary -RunDirectory $tempRoot -UsageRecord $usageUnknown | Out-Null
    $usage = Get-Content -LiteralPath $usagePath -Raw | ConvertFrom-Json
    Assert-Felix3 ($usage.totals.input_tokens -eq 15 -and $usage.totals.output_tokens -eq 6 -and $usage.totals.cached_input_tokens -eq 3) 'provider usage fields normalize and aggregate'
    Assert-Felix3 (-not $usage.totals.complete) 'missing provider usage remains explicitly incomplete'
    $emptyUsage = ConvertTo-Felix3UsageRecord -Harness 'codex' -Phase 'planning' -PhaseInstance 'planning-empty-usage' -Model 'm' -Usage @{} -CostUsd $null -DurationSeconds 1 -SessionId 's'
    Assert-Felix3 (-not $emptyUsage.reported) 'empty usage objects do not masquerade as token accounting'

    # Each native CLI adapter streams its JSONL events and normalizes final usage.
    $fixtureSources = @{
        claude = @'
import json
print(json.dumps({'type':'result','session_id':'claude-session','result':'claude done','usage':{'input_tokens':12,'output_tokens':3},'total_cost_usd':0.001}),flush=True)
'@
        opencode = @'
import json
for e in [{'type':'text','sessionID':'opencode-session','part':{'text':'open streamed'}},{'type':'step_finish','sessionID':'opencode-session','part':{'tokens':{'input':10,'output':4,'total':14,'reasoning':1,'cache':{'read':6}},'cost':0.002}}]: print(json.dumps(e),flush=True)
'@
        codex = @'
import sys,json,os
events=[{'type':'thread.started','thread_id':'codex-session'},{'type':'item.completed','thread_id':'codex-session','item':{'type':'agent_message','text':'codex done'}},{'type':'turn.completed','thread_id':'codex-session','usage':{'input_tokens':8,'output_tokens':2,'total_tokens':10}}]
for e in events: print(json.dumps(e),flush=True)
a=sys.argv[1:]
if '-o' in a: open(a[a.index('-o')+1],'w',encoding='utf-8').write('codex done')
if os.environ.get('FELIX3_CAPTURE_ARGS'): open(os.environ['FELIX3_CAPTURE_ARGS'],'w',encoding='utf-8').write(json.dumps(a))
'@
    }
    foreach ($name in @('claude','opencode','codex')) {
        $phaseDirectory = Join-Path $tempRoot "adapter-$name"
        New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
        $executable = New-FakeCli -Root $tempRoot -Name "fake-$name" -Source $fixtureSources[$name]
        $sink = New-Felix3EventSink -Journal $journal -Phase "adapter-$name" -Harness $name
        if ($name -eq 'claude') { $result = Invoke-ClaudeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -Journal $journal -EventSink $sink }
        elseif ($name -eq 'opencode') { $result = Invoke-OpenCodeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -Journal $journal -EventSink $sink }
        else {
            $captureArgsPath = Join-Path $tempRoot 'codex-args.json'; $env:FELIX3_CAPTURE_ARGS = $captureArgsPath
            try { $result = Invoke-CodexHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -Journal $journal -EventSink $sink }
            finally { Remove-Item Env:FELIX3_CAPTURE_ARGS -ErrorAction SilentlyContinue }
            $codexArgs = @(Get-Content -LiteralPath $captureArgsPath -Raw | ConvertFrom-Json)
            Assert-Felix3 ($codexArgs -notcontains '-a' -and $codexArgs -contains '-c' -and ($codexArgs -join ' ') -match 'approval_policy="on-request"') 'Codex adapter uses supported approval config overrides'
        }
        $expectedHarness = @{ claude='claude-code'; opencode='opencode'; codex='codex' }[$name]
        Assert-Felix3 ((Assert-Felix3HarnessResultContract -Result $result -ExpectedHarness $expectedHarness -ExpectedPhase 'building').Harness -eq $expectedHarness) "$name adapter satisfies the common result contract"
        $invalidResult = $result | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $invalidResult.Succeeded = $true
        $invalidResult.Interrupted = $true
        $rejectedResult = $false
        try { Assert-Felix3HarnessResultContract -Result $invalidResult -ExpectedHarness $expectedHarness -ExpectedPhase 'building' | Out-Null } catch { $rejectedResult = $true }
        Assert-Felix3 $rejectedResult "$name result contract rejects contradictory outcome flags"
        Assert-Felix3 $result.Succeeded "$name adapter succeeds on its JSONL protocol"
        Assert-Felix3 (Test-Path -LiteralPath $result.RawOutputPath) "$name raw output is written while streaming"
        Assert-Felix3 ([string]$result.SessionId -eq "$name-session") "$name session ID is normalized"
    }
    $adapterUsage = Get-Content -LiteralPath (Join-Path $tempRoot 'usage.json') -Raw | ConvertFrom-Json
    Assert-Felix3 ($adapterUsage.totals.input_tokens -ge 30 -and $adapterUsage.totals.output_tokens -ge 9) 'all adapters contribute normalized usage'

    $incompleteOpenCodeDir = Join-Path $tempRoot 'incomplete-opencode'; New-Item -ItemType Directory -Path $incompleteOpenCodeDir -Force | Out-Null
    $incompleteOpenCodeExe = New-FakeCli -Root $tempRoot -Name 'fake-incomplete-opencode' -Source "import json`nprint(json.dumps({'type':'text','sessionID':'unfinished','part':{'text':'partial only'}}),flush=True)"
    $incompleteOpenCode = Invoke-OpenCodeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $incompleteOpenCodeDir -Executable $incompleteOpenCodeExe
    Assert-Felix3 (-not $incompleteOpenCode.Succeeded -and $incompleteOpenCode.Error -match 'without a completed step') 'OpenCode process exit without a completion event is not success'
    $incompleteCodexDir = Join-Path $tempRoot 'incomplete-codex'; New-Item -ItemType Directory -Path $incompleteCodexDir -Force | Out-Null
    $incompleteCodexExe = New-FakeCli -Root $tempRoot -Name 'fake-incomplete-codex' -Source "import json`nprint(json.dumps({'type':'thread.started','thread_id':'unfinished'}),flush=True)"
    $incompleteCodex = Invoke-CodexHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $incompleteCodexDir -Executable $incompleteCodexExe
    Assert-Felix3 (-not $incompleteCodex.Succeeded -and $incompleteCodex.Error -match 'without a completed turn') 'Codex process exit without a completion event is not success'

    # Claude's native AskUserQuestion tool request is paused and normalized too.
    $claudeQuestionPhase = Join-Path $tempRoot 'claude-native-question'
    New-Item -ItemType Directory -Path $claudeQuestionPhase -Force | Out-Null
    $claudeQuestionSource = @'
import json,time
event={'type':'assistant','session_id':'claude-question-session','message':{'content':[{'type':'tool_use','name':'AskUserQuestion','input':{'questions':[{'header':'Naming','question':'Choose a public name?','options':[{'label':'alpha'},{'label':'beta'}]}]}}]}}
print(json.dumps(event),flush=True)
time.sleep(15)
'@
    $claudeQuestionExe = New-FakeCli -Root $tempRoot -Name 'fake-claude-question' -Source $claudeQuestionSource
    $claudeQuestionSink = New-Felix3EventSink -Journal $journal -Phase 'claude-native-question' -Harness 'claude-code'
    $claudeQuestionResult = Invoke-ClaudeHarness -Phase planning -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $claudeQuestionPhase -Executable $claudeQuestionExe -Journal $journal -EventSink $claudeQuestionSink
    Assert-Felix3 $claudeQuestionResult.NeedsInput 'Claude native AskUserQuestion stops the headless harness'
    $claudeQuestionEvent = @([System.IO.File]::ReadLines($journal.EventPath) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.phase -eq 'claude-native-question' -and $_.kind -eq 'question.requested' })[0]
    $claudeQuestion = ConvertFrom-Felix3QuestionData -Data $claudeQuestionEvent.payload.question
    Assert-Felix3 ($claudeQuestion.question -match 'Choose a public name' -and $claudeQuestion.choices.Count -eq 2) 'Claude native question fields normalize to Felix question data'

    # Native OpenCode question tool requests become durable Felix questions and stop the model loop.
    $questionPhase = Join-Path $tempRoot 'native-question'
    New-Item -ItemType Directory -Path $questionPhase -Force | Out-Null
    $nativeQuestionSource = @'
import json,time
event={'type':'tool_use','sessionID':'open-question-session','part':{'type':'tool','tool':'question','state':{'status':'running','input':{'questions':[{'header':'Naming','question':'Choose a public name?','options':[{'label':'alpha'},{'label':'beta'}]}]}}}}
print(json.dumps(event),flush=True)
time.sleep(15)
'@
    $nativeQuestionExe = New-FakeCli -Root $tempRoot -Name 'fake-native-question' -Source $nativeQuestionSource
    $questionSink = New-Felix3EventSink -Journal $journal -Phase 'native-question' -Harness 'opencode'
    $nativeQuestionResult = Invoke-OpenCodeHarness -Phase planning -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $questionPhase -Executable $nativeQuestionExe -Journal $journal -EventSink $questionSink
    Assert-Felix3 $nativeQuestionResult.NeedsInput 'provider-native question tool stops the headless harness'
    $nativeQuestionEvent = @([System.IO.File]::ReadLines($journal.EventPath) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.kind -eq 'question.requested' -and $_.phase -eq 'native-question' })[0]
    $nativeQuestion = ConvertFrom-Felix3QuestionData -Data $nativeQuestionEvent.payload.question
    Assert-Felix3 ($nativeQuestion.question -match 'Choose a public name' -and $nativeQuestion.choices.Count -eq 2) 'provider-native question fields normalize to Felix question data'
    $nativeQuestionRun = Join-Path $tempRoot 'native-question-run'
    New-Item -ItemType Directory -Path $nativeQuestionRun -Force | Out-Null
    $nativeState = [ordered]@{ schema = 'felix3-task-state-v2'; id = 'native'; run_id = 'native'; status = 'planning'; active_phase = 'planning'; phases = @(); validation = $null; outcome = $null; pending_question = $null; process = $null }
    $nativeStatePath = Join-Path $nativeQuestionRun 'state.json'
    Write-Felix3AtomicJson -Path $nativeStatePath -Value $nativeState
    Assert-Felix3 (Suspend-Felix3ForQuestion -Result $nativeQuestionResult -Phase planning -State $nativeState -StatePath $nativeStatePath -RunDirectory $nativeQuestionRun -Journal $journal) 'native question requests suspend the coordinator'
    $nativeStateSaved = Get-Content -LiteralPath $nativeStatePath -Raw | ConvertFrom-Json
    Assert-Felix3 ($nativeStateSaved.status -eq 'awaiting-input' -and (Test-Path (Join-Path $nativeQuestionRun 'question.json'))) 'native questions persist the question and resumable state'

    # Cooperative cancellation stops a running process without treating it as a normal error.
    $stopPhase = Join-Path $tempRoot 'stop-check'
    New-Item -ItemType Directory -Path $stopPhase -Force | Out-Null
    $slowSource = "import json,time`nprint(json.dumps({'type':'text','sessionID':'stop-session','part':{'text':'working'}}),flush=True)`ntime.sleep(15)"
    $slowExe = New-FakeCli -Root $tempRoot -Name 'fake-slow' -Source $slowSource
    $cancelPath = Join-Path $tempRoot 'cancel.requested'
    $cancelJob = Start-Job -ArgumentList $cancelPath -ScriptBlock { param($path) Start-Sleep -Milliseconds 500; Set-Content -LiteralPath $path -Value 'stop' }
    $stopResult = Invoke-OpenCodeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $stopPhase -Executable $slowExe -CancelTokenPath $cancelPath
    Wait-Job $cancelJob | Out-Null; Remove-Job $cancelJob
    Assert-Felix3 $stopResult.Interrupted 'cancel token terminates the active harness process'

    # Cloud event payloads omit streamed content and redact question text unless explicitly opted in.
    $cloudStatePath = Join-Path $tempRoot 'cloud-state.json'
    @{ last_event_seq = 0 } | ConvertTo-Json | Set-Content -LiteralPath $cloudStatePath -Encoding UTF8
    $fakeCloudClient = [Fel3TestCloudClient]::new()
    $cloud = [pscustomobject]@{ Client = $fakeCloudClient; CloudRunId = 'cloud-id'; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = [pscustomobject]@{ include_phase_summaries = $true; include_question_text = $false; artifacts = @() } }
    Add-Felix3CloudEvent -Cloud $cloud -Event ([pscustomobject]@{ kind = 'output.delta'; event_id = 'e1'; run_id = 'local'; seq = 1; phase = 'building'; harness = 'codex'; summary = 'private source text'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{} })
    Assert-Felix3 ($fakeCloudClient.Events.Count -eq 0 -and $cloud.Buffer.Count -eq 0) 'cloud never receives streamed assistant text'
    Add-Felix3CloudEvent -Cloud $cloud -Event ([pscustomobject]@{ kind = 'question.requested'; event_id = 'e2'; run_id = 'local'; seq = 2; phase = 'planning'; harness = 'codex'; summary = 'Sensitive project question?'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{ question = 'Sensitive project question?' } })
    $sentQuestion = $fakeCloudClient.Events[0]
    Assert-Felix3 ($sentQuestion.message -eq 'Human input requested.' -and ($sentQuestion | ConvertTo-Json -Depth 20 -Compress) -notmatch 'Sensitive project question') 'cloud question summaries contain no question text by default'
    $optInCloudClient = [Fel3TestCloudClient]::new()
    $optInCloud = [pscustomobject]@{ Client = $optInCloudClient; CloudRunId = 'cloud-id'; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = [pscustomobject]@{ include_phase_summaries = $true; include_question_text = $true; artifacts = @() } }
    Add-Felix3CloudEvent -Cloud $optInCloud -Event ([pscustomobject]@{ kind = 'question.requested'; event_id = 'e3'; run_id = 'local'; seq = 3; phase = 'planning'; harness = 'codex'; summary = 'Sensitive project question?'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{ question = 'Sensitive project question?' } })
    $optInQuestion = $optInCloudClient.Events[0]
    Assert-Felix3 ($optInQuestion.data.question -eq 'Sensitive project question?' -and $optInQuestion.message -eq 'Human input requested.') 'cloud includes question wording only when explicitly enabled'
    $interruptRun = Join-Path $tempRoot 'interrupted-cloud-run'; New-Item -ItemType Directory -Path $interruptRun -Force | Out-Null
    $interruptJournal = Initialize-Felix3RunJournal -RunDirectory $interruptRun -RunId 'interrupt-cloud'
    $interruptStatePath = Join-Path $interruptRun 'state.json'
    $interruptState = [ordered]@{ schema = 'felix3-task-state-v2'; id = 'interrupt-cloud'; run_id = 'interrupt-cloud'; status = 'building'; active_phase = 'building'; phases = @(); validation = $null; outcome = $null; pending_question = $null; process = $null }
    Write-Felix3AtomicJson -Path $interruptStatePath -Value $interruptState
    $interruptCloud = [pscustomobject]@{ Client = $fakeCloudClient; CloudRunId = 'cloud-id'; RunId = 'interrupt-cloud'; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = $cloud.Settings }
    $interruptResult = [pscustomobject]@{ Interrupted = $true; Harness = 'codex'; SessionId = 'session' }
    Assert-Felix3 (Suspend-Felix3ForStop -Result $interruptResult -Phase building -State $interruptState -StatePath $interruptStatePath -RunDirectory $interruptRun -Journal $interruptJournal -Cloud $interruptCloud) 'coordinator records an interrupted run'
    Assert-Felix3 ($fakeCloudClient.FinishCount -eq 0 -and $fakeCloudClient.FlushCount -gt 0) 'resumable interruption flushes cloud events without finishing the cloud run'

    # The coordinator pauses on a human question, resumes the same session, and finishes its gates.
    $project = Join-Path $tempRoot 'resume-project'
    New-Item -ItemType Directory -Path (Join-Path $project 'specs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $project '.felix3') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project 'specs\S-1.md') -Value 'HUMAN_CHOICE_REQUIRED: ask for the feature name.' -Encoding UTF8
    $python = (Get-Command python -CommandType Application | Select-Object -First 1).Source
    $coordinatorSource = @'
import sys,json,os
a=sys.argv[1:]
p=sys.stdin.read()
resuming='resume' in a
question='<felix3-question>{"question":"What name should the feature use?","choices":["alpha","beta"],"context":"Naming affects the API."}</felix3-question>'
plan='''# Plan\n\n## Acceptance Coverage\n| Criterion | Task | Check |\n|---|---|---|\n| Feature name | Task 1 | Validate |\n\n## Tasks\n- [ ] Implement the feature.\n\n## Validation\n- Run configured validation.'''
if 'HUMAN_CHOICE_REQUIRED' in p and 'No human decisions recorded.' in p: text=question
elif 'planning phase' in p.lower(): text=plan
elif 'independent review agent' in p.lower(): text='{"schema":"felix3-review-v1","decision":"approved","summary":"Approved","findings":[]}'
else: text='Implementation complete.'
events=[{'type':'thread.started','thread_id':'coordinator-session'},{'type':'item.completed','thread_id':'coordinator-session','item':{'type':'agent_message','text':text}},{'type':'turn.completed','thread_id':'coordinator-session','usage':{'input_tokens':9,'output_tokens':2,'total_tokens':11}}]
for e in events: print(json.dumps(e),flush=True)
if '-o' in a: open(a[a.index('-o')+1],'w',encoding='utf-8').write(text)
if os.environ.get('FELIX3_CAPTURE_ARGS'): open(os.environ['FELIX3_CAPTURE_ARGS'],'a',encoding='utf-8').write(json.dumps({'args':a,'prompt':p})+'\n')
'@
    $codexExe = New-FakeCli -Root $tempRoot -Name 'fake-coordinator' -Source $coordinatorSource
    $config = @{
        schema_version = 1
        work_source = @{ provider = 'manual-spec'; specs_dir = 'specs'; ready_status = 'ready' }
        artifacts = @{ runs_dir = '.felix3/runs'; local_retention_days = 30 }
        cloud_sync = @{ enabled = $false; agent_key = ''; include_phase_summaries = $true; include_question_text = $false; artifacts = @() }
        harness = @{ provider = 'codex'; codex = @{ executable = $codexExe; sandbox = 'read-only'; approval_policy = 'never'; session_policy = 'fresh'; phases = @{
            planning = @{ sandbox = 'read-only'; approval_policy = 'never' }
            building = @{ sandbox = 'workspace-write'; approval_policy = 'never'; session_policy = 'resume' }
            reviewing = @{ sandbox = 'read-only'; approval_policy = 'never' }
        } } }
        workflow = @{ require_plan_approval = $false; max_build_attempts = 2; max_review_cycles = 1; validation = @{ require_at_least_one_command = $true; commands = @(@{ name = 'python'; executable = $python; args = @('-c', "import pathlib,sys; p=pathlib.Path(r'$tempRoot\validate-once'); existed=p.exists(); p.write_text('seen'); sys.exit(0 if existed else 1)") }) } }
    }
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8
    $savedCaptureArgs = $env:FELIX3_CAPTURE_ARGS; $captureArgsPath = Join-Path $tempRoot 'coordinator-args.jsonl'; $env:FELIX3_CAPTURE_ARGS = $captureArgsPath
    try {
        $first = Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-1' -SpecPath 'specs/S-1.md'
        Assert-Felix3 ($first.Status -eq 'awaiting-input') 'coordinator persists an agent question and pauses the run'
        Assert-Felix3 (Test-Path -LiteralPath (Join-Path $first.RunDirectory 'question.json')) 'question is durable and inspectable'
        $resumed = Resume-Felix3Task -ProjectPath $project -RunId $first.RunId -Answer 'Use beta.'
    }
    finally { if ($null -eq $savedCaptureArgs) { Remove-Item Env:FELIX3_CAPTURE_ARGS -ErrorAction SilentlyContinue } else { $env:FELIX3_CAPTURE_ARGS = $savedCaptureArgs } }
    Assert-Felix3 ($resumed.Status -eq 'completed') 'answer resumes the same run through validation and review'
    $coordinatorCalls = @(Get-Content -LiteralPath $captureArgsPath | ForEach-Object { $_ | ConvertFrom-Json })
    $buildResumeCall = @($coordinatorCalls | Where-Object { $_.prompt -match 'building phase' -and $_.args -contains 'resume' })
    Assert-Felix3 ($buildResumeCall.Count -ge 1) 'building session_policy=resume continues the same session on validation retry'
    $state = Get-Content -LiteralPath $resumed.StatePath -Raw | ConvertFrom-Json
    Assert-Felix3 ($state.run_id -eq $first.RunId -and $state.status -eq 'completed') 'resumption preserves run identity and terminal state'
    Assert-Felix3 (Test-Path -LiteralPath (Join-Path $resumed.RunDirectory 'usage.json')) 'resumed run retains aggregated usage'

    Set-Content -LiteralPath (Join-Path $project 'specs\S-2.md') -Value 'Approval workflow smoke spec.' -Encoding UTF8
    $config.workflow.require_plan_approval = $true
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8
    $approvalRun = Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-2' -SpecPath 'specs/S-2.md'
    Assert-Felix3 ($approvalRun.Status -eq 'awaiting-plan-approval') 'approval gate durably pauses after producing the plan'
    $approvedRun = Resume-Felix3Task -ProjectPath $project -RunId $approvalRun.RunId -Answer approve
    Assert-Felix3 ($approvedRun.Status -eq 'completed') 'plan approval resumes the same run through remaining gates'
    $approvalEvents = @(Get-Content -LiteralPath (Join-Path $approvalRun.RunDirectory 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json } | ForEach-Object { $_.kind })
    Assert-Felix3 ($approvalEvents -contains 'plan.approval_requested' -and $approvalEvents -contains 'plan.approved') 'plan approval and decision are recorded as lifecycle events'

    Set-Content -LiteralPath (Join-Path $project 'specs\S-3.md') -Value 'Reject plan workflow smoke spec.' -Encoding UTF8
    $rejectedPlan = Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-3' -SpecPath 'specs/S-3.md'
    $rejectedRun = Resume-Felix3Task -ProjectPath $project -RunId $rejectedPlan.RunId -Answer reject
    Assert-Felix3 ($rejectedRun.Status -eq 'blocked') 'human plan rejection terminates the run as blocked'
    $rejectionEvents = @(Get-Content -LiteralPath (Join-Path $rejectedPlan.RunDirectory 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json } | ForEach-Object { $_.kind })
    Assert-Felix3 ($rejectionEvents -contains 'plan.rejected' -and $rejectionEvents -contains 'run.blocked') 'plan rejection writes terminal lifecycle events'

    $claudeCoordinatorSource = @'
import json,pathlib,sys
counter=pathlib.Path('fake-claude-phase-count')
phase=int(counter.read_text())+1 if counter.exists() else 1
counter.write_text(str(phase))
if phase == 1:
 text='''# Plan\n\n## Acceptance Coverage\n| Criterion | Task | Check |\n|---|---|---|\n| Smoke output | Task 1 | Validate |\n\n## Tasks\n- [ ] Create the smoke output.\n\n## Validation\n- Run configured validation.'''
elif phase == 3:
 text='{"schema":"felix3-review-v1","decision":"approved","summary":"Approved","findings":[]}'
else:
 pathlib.Path('harness-smoke.txt').write_text('Felix 3 harness smoke\n',encoding='utf-8')
 text='Implementation complete.'
print(json.dumps({'type':'result','session_id':'claude-coordinator-session','result':text,'usage':{'input_tokens':10,'output_tokens':5},'total_cost_usd':0.001}),flush=True)
'@
    $claudeCoordinatorExe = New-FakeCli -Root $tempRoot -Name 'fake-claude-coordinator' -Source $claudeCoordinatorSource
    $claudeSpec = Join-Path $project 'specs\S-CLAUDE.md'
    Set-Content -LiteralPath $claudeSpec -Value 'Claude coordinator smoke spec.' -Encoding UTF8
    $config.workflow.require_plan_approval = $false
    $config.harness.provider = 'claude-code'
    $config.harness['claude-code'] = @{
        executable = $claudeCoordinatorExe; model = 'test'; permission_mode = 'default'; max_turns = 10; session_policy = 'fresh'
        phases = @{
            planning = @{ permission_mode = 'plan'; max_turns = 10; session_policy = 'fresh' }
            building = @{ permission_mode = 'acceptEdits'; max_turns = 10; session_policy = 'resume' }
            reviewing = @{ permission_mode = 'plan'; max_turns = 10; session_policy = 'fresh' }
        }
    }
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8
    $claudeCoordinatorRun = Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-CLAUDE' -SpecPath 'specs/S-CLAUDE.md'
    Assert-Felix3 (Test-Path -LiteralPath (Join-Path $claudeCoordinatorRun.RunDirectory 'plan.md')) 'Claude final plan response is persisted by Felix before build'
    Assert-Felix3 ($claudeCoordinatorRun.Status -eq 'completed') "Claude coordinator completes planning, build, validation, and review (status=$($claudeCoordinatorRun.Status), outcome=$($claudeCoordinatorRun.Outcome))"
    Assert-Felix3 ((Get-Content (Join-Path $project 'harness-smoke.txt') -Raw).Trim() -eq 'Felix 3 harness smoke') 'Claude coordinator completes build, validation, and review'
    $config.harness.provider = 'codex'
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8

    $localReadySpec = Join-Path $project 'specs\S-LOCAL.md'
    [IO.File]::WriteAllText($localReadySpec, "---`nid: S-LOCAL`ntitle: Local queue smoke`nstatus: ready`n---`nLocal ready work source smoke spec.", [Text.UTF8Encoding]::new($false))
    $config.workflow.require_plan_approval = $false
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8
    $localCycle = Invoke-Felix3LocalWorkCycle -ProjectPath $project
    Assert-Felix3 ($localCycle.Status -eq 'completed' -and $localCycle.WorkItem.id -eq 'S-LOCAL') 'local ready-spec cycle runs the selected work item through validation and review'
    Assert-Felix3 ((Get-Felix3SpecMetadata -Path $localReadySpec)['status'] -eq 'completed') 'successful local work marks its spec completed'
    Assert-Felix3 (-not (Test-Path -LiteralPath (Join-Path $project '.felix3\work-source\local-active.json'))) 'successful local work clears the resumable active claim'

    Write-Output 'Felix 3 tests passed: three harness adapters, local and Cloud work-source lifecycles, streamed events/usage, native questions, plan approval/rejection, cancellation, cloud privacy, and resumable workflows.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

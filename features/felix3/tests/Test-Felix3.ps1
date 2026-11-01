$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Invoke-Felix3Task.ps1')

class Fel3TestCloudClient {
    [object[]]$Events = @()
    [object[]]$Activity = @()
    [int]$FinishCount = 0
    [int]$FlushCount = 0
    [bool]$FailAppend = $false
    [void] AppendEvents([string]$RunId, [array]$Events) { if ($this.FailAppend) { throw 'simulated offline upload' }; $this.Events = @($Events) }
    [bool] PublishRunActivity([string]$RunId, [hashtable]$Activity) { $this.Activity += [pscustomobject]$Activity; return $true }
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
    $planningTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\planning.md') -Raw -Encoding UTF8
    Assert-Felix3 ($planningTemplate -match 'Discover repository instruction files first' -and $planningTemplate -match 'directory listings to identify the exact files present' -and $planningTemplate -match 'Never use a file-read call to check whether a guessed path exists' -and $planningTemplate -notmatch 'CLAUDE\.md') 'planning prompt requires listing before reading and avoids suggesting absent candidate filenames'

    # Claude Code plan mode writes the plan to its native plans folder and returns a pointer.
    # Felix must capture that file only from the configured Claude plan root.
    $claudePlansRoot = Join-Path $tempRoot 'plans'
    New-Item -ItemType Directory -Path $claudePlansRoot -Force | Out-Null
    $claudeNativePlanPath = Join-Path $claudePlansRoot 'native-plan.md'
    $claudeNativePlanText = @'
# Plan: S-PLAN - Native plan capture

## Acceptance Coverage
| Criterion | Planned task(s) | Verification |
|---|---|---|
| Smoke | Task 1 | Run check |
'@
    [System.IO.File]::WriteAllText($claudeNativePlanPath, $claudeNativePlanText, [Text.UTF8Encoding]::new($false))
    $claudePointerResponse = @{ type = 'result'; result = "Plan written to ``$claudeNativePlanPath``."; session_id = 'claude-plan-session' } | ConvertTo-Json -Compress
    $claudeCapturedPlan = ConvertFrom-ClaudeHarnessResponse -Output $claudePointerResponse -PlanRoots @($claudePlansRoot) -CaptureNativePlan
    Assert-Felix3 ($claudeCapturedPlan.IsValid -and $claudeCapturedPlan.Text -eq $claudeNativePlanText -and $claudeCapturedPlan.NativePlanPath -eq $claudeNativePlanPath) 'Claude native plan pointer is captured into Felix as plan content'
    $outsidePlanPath = Join-Path $tempRoot 'outside-plan.md'
    [System.IO.File]::WriteAllText($outsidePlanPath, $claudeNativePlanText, [Text.UTF8Encoding]::new($false))
    $outsidePlan = ConvertFrom-ClaudeHarnessResponse -Output (@{ type = 'result'; result = "Plan written to ``$outsidePlanPath``." } | ConvertTo-Json -Compress) -PlanRoots @($claudePlansRoot) -CaptureNativePlan
    Assert-Felix3 (-not $outsidePlan.IsValid -and $outsidePlan.Error -match 'outside the allowed Claude plans directory') 'Claude native plan capture rejects paths outside the user plans directory'
    $nativeHarnessDirectory = Join-Path $tempRoot 'claude-native-harness'
    New-Item -ItemType Directory -Path $nativeHarnessDirectory -Force | Out-Null
    $capturedArtifact = Save-ClaudeNativePlanArtifact -Text $claudeCapturedPlan.Text -RunDirectory $nativeHarnessDirectory -NativePlanPath $claudeCapturedPlan.NativePlanPath
    Assert-Felix3 ($capturedArtifact -and (Test-Path -LiteralPath $capturedArtifact) -and (Get-Content -LiteralPath $capturedArtifact -Raw -Encoding UTF8) -eq $claudeNativePlanText) 'Claude native plan is copied into the local Felix run artifact'

    # Stable V3 work-item, harness-result, event, and state-transition contracts.
    $contractProject = Join-Path $tempRoot 'contract-project'
    $contractSpecs = Join-Path $contractProject 'specs'
    New-Item -ItemType Directory -Path $contractSpecs -Force | Out-Null
    $localSpecA = Join-Path $contractSpecs 'S-READY.md'
    $localSpecB = Join-Path $contractSpecs 'S-BLOCKED.md'
    $relativeSpecPath = Get-Felix3RelativePath -BasePath $contractProject -TargetPath $localSpecA
    Assert-Felix3 ($relativeSpecPath -eq 'specs\S-READY.md') 'relative path helper works without .NET Core Path.GetRelativePath'
    $sameDirectoryPath = Get-Felix3RelativePath -BasePath $contractProject -TargetPath $contractProject
    Assert-Felix3 ($sameDirectoryPath -eq '.') 'relative path helper returns dot for identical directory paths'
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
        (Join-Path $PSScriptRoot '..\codex\felix3-codex.config.example.json'),
        (Join-Path $PSScriptRoot '..\grok\felix3-grok.config.example.json')
    )) {
        $loadedConfig = Import-Felix3Config -Path (Resolve-Path -LiteralPath $configPath).Path
        Assert-Felix3 ($loadedConfig.harness.provider -in @('claude-code','opencode','codex','grok-build')) "example config validates: $(Split-Path $configPath -Leaf)"
    }
    $grokSetupProject = Join-Path $tempRoot 'grok-setup-project'
    New-Item -ItemType Directory -Path $grokSetupProject -Force | Out-Null
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\felix3-cli.ps1') -Action setup -ProjectPath $grokSetupProject -Harness grok-build | Out-Null
    $grokSetupConfig = Get-Content -LiteralPath (Join-Path $grokSetupProject '.felix3\config.json') -Raw | ConvertFrom-Json
    Assert-Felix3 ($LASTEXITCODE -eq 0 -and $grokSetupConfig.harness.provider -eq 'grok-build' -and (Test-Path -LiteralPath (Join-Path $grokSetupProject '.grok\skills\felix\SKILL.md'))) 'Grok setup creates its config and installs the Felix skill in the Grok project skill directory'
    $allowedToolsConfig = Import-Felix3Config -Path (Join-Path $PSScriptRoot '..\felix3.config.example.json')
    $claudeConfigBlock = $allowedToolsConfig.harness.'claude-code'
    $claudeConfigBlock | Add-Member -NotePropertyName allowed_tools -NotePropertyValue @('Read')
    $claudeConfigBlock.phases.building | Add-Member -NotePropertyName allowed_tools -NotePropertyValue @('Bash(python -m unittest:*)')
    $allowedToolsPhase = Get-Felix3PhaseConfig -Config $allowedToolsConfig -Phase building
    $allowedBuildTools = @($allowedToolsPhase.allowed_tools)
    Assert-Felix3 ($allowedBuildTools.Count -eq 1 -and $allowedBuildTools[0] -eq 'Bash(python -m unittest:*)') 'Claude phase config can narrow inherited allowed tools to a build-phase list'
    $allowedToolsPlan = Get-Felix3PhaseConfig -Config $allowedToolsConfig -Phase planning
    $allowedPlanningTools = @($allowedToolsPlan.allowed_tools)
    Assert-Felix3 ($allowedPlanningTools.Count -eq 1 -and $allowedPlanningTools[0] -eq 'Read') 'Claude phase config inherits base allowed tools when no phase override exists'
    $grokConfig = Import-Felix3Config -Path (Join-Path $PSScriptRoot '..\grok\felix3-grok.config.example.json')
    $grokPlanningPhase = Get-Felix3PhaseConfig -Config $grokConfig -Phase planning
    Assert-Felix3 (@($grokPlanningPhase.deny_rules) -contains 'Bash') 'Grok planning phase denies native shell while Felix owns validation'
    $grokBuildPhase = Get-Felix3PhaseConfig -Config $grokConfig -Phase building
    Assert-Felix3 ($grokBuildPhase.permission_mode -eq 'dontAsk' -and @($grokBuildPhase.allow_rules) -contains 'Bash(dotnet *)' -and @($grokBuildPhase.allow_rules) -contains 'Bash(powershell -NoProfile -File *)' -and @($grokBuildPhase.allow_rules) -contains 'Edit' -and @($grokBuildPhase.allow_rules) -notcontains 'Bash(*)' -and @($grokBuildPhase.deny_rules) -contains 'Bash(git push *)' -and @($grokBuildPhase.deny_rules) -contains 'Bash(rm -rf *)') 'Grok build phase allows common project build commands while denying broad shell and destructive operations'
    $grokReviewPhase = Get-Felix3PhaseConfig -Config $grokConfig -Phase reviewing
    $grokReviewRules = @($grokReviewPhase.allow_rules)
    Assert-Felix3 (@($grokReviewRules) -contains 'Read' -and @($grokReviewRules) -contains 'Grep' -and @($grokReviewRules) -contains 'Glob' -and @($grokReviewRules) -notcontains 'Bash' -and @($grokReviewPhase.deny_rules) -contains 'Bash') 'Grok review phase allows native read/search tools and denies shell commands'
    $savedSyncUrl = $env:FELIX_SYNC_URL
    try {
        Remove-Item Env:FELIX_SYNC_URL -ErrorAction SilentlyContinue
        Assert-Felix3 ((Resolve-Felix3CloudBaseUrl -Settings ([pscustomobject]@{})) -eq 'https://api.runfelix.io') 'cloud sync defaults to the Felix Cloud API endpoint'
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
    $cloudStartRequest = $cloudRequestLog | Where-Object { $_.Uri -match '/work/start$' } | Select-Object -First 1
    Assert-Felix3 ($cloudStartRequest.Body.agent_id -eq $cloudAgentId) 'Cloud lifecycle requests carry the owning agent UUID'
    Complete-Felix3CloudWorkItem -Source $cloudSource -RequirementId 'C-42' | Out-Null
    Release-Felix3CloudWorkItem -Source $cloudSource -RequirementId 'C-42' | Out-Null
    $cloudStartRequests = @($cloudRequestLog | Where-Object { $_.Uri -match '/work/start$' })
    $cloudCompleteRequests = @($cloudRequestLog | Where-Object { $_.Uri -match '/work/complete$' })
    $cloudReleaseRequests = @($cloudRequestLog | Where-Object { $_.Uri -match '/work/release$' })
    Assert-Felix3 ($cloudStartRequests.Count -eq 1 -and $cloudCompleteRequests.Count -eq 1 -and $cloudReleaseRequests.Count -eq 1) 'Cloud work lifecycle maps start, complete, and release endpoints'
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
    $savedCloudStartFunction = (Get-Command Start-Felix3CloudWorkItem -CommandType Function).ScriptBlock
    $global:felix3CloudTaskCalls = 0
    $global:felix3TestCloudClaimStatus = 'reserved'
    $cloudCycleApiLog = [System.Collections.ArrayList]::new()
    $cloudCycleRequest = {
        param($Method, $Uri, $Headers, $Body)
        [void]$cloudCycleApiLog.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
        if ($Uri -match '/api/sync/work/next\?') { return @{ code=$global:felix3TestCloudCode; title='Cloud cycle test'; spec_path="specs/$global:felix3TestCloudCode.md"; priority='medium'; depends_on=@(); status=$global:felix3TestCloudClaimStatus } }
        if ($Uri -match '/api/sync/specs/file\?') { return "# $global:felix3TestCloudCode`n`nAcceptance: exercise the Cloud cycle.`n" }
        return @{ status='ok' }
    }.GetNewClosure()
    try {
        $env:FELIX_SYNC_KEY = 'fsk-test-secret'
        Set-Item -Path Function:\Invoke-Felix3Task -Value { param($ProjectPath,$RequirementId,$Title,$SpecPath,$ConfigPath,$WorkItem,$NewRunId,$ResumeRunId,$Answer) $global:felix3CloudTaskCalls++; return [pscustomobject]@{ Status = $global:felix3TestCloudTaskStatus; RunId = $NewRunId } }
        Set-Item -Path Function:\Resume-Felix3Task -Value { param($ProjectPath,$RunId,$Answer,$ConfigPath) return [pscustomobject]@{ Status = $global:felix3TestCloudTaskStatus; RunId = $RunId } }
        $global:felix3TestCloudCode = 'C-100'; $global:felix3TestCloudTaskStatus = 'completed'
        $completedCloudCycle = Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest
        Assert-Felix3 ($completedCloudCycle.Status -eq 'completed' -and @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/complete$' }).Count -eq 1) 'Cloud cycle completes the source item only after task completion'
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
        Assert-Felix3 ($blockedCloudCycle.Status -eq 'blocked' -and @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/release$' }).Count -eq 1) 'Cloud cycle releases a blocked source item'
        Set-Item -Path Function:\Start-Felix3CloudWorkItem -Value { param($Source,$RequirementId) return @{ status='already-started'; code=$RequirementId } }
        $global:felix3TestCloudCode = 'C-103'; $global:felix3TestCloudTaskStatus = 'completed'
        $callsBeforeRecoveryGuard = $global:felix3CloudTaskCalls
        $recoveryGuardTriggered = $false
        try { Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest | Out-Null } catch { $recoveryGuardTriggered = $_.Exception.Message -match 'Recover the original checkout' }
        $guardClaimPath = Join-Path (Join-Path (Join-Path $cloudProject '.felix3') 'work-source') 'cloud-claim.json'
        $guardClaim = Get-Content -LiteralPath $guardClaimPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Felix3 ($recoveryGuardTriggered -and $global:felix3CloudTaskCalls -eq $callsBeforeRecoveryGuard -and $guardClaim.recovery_required -eq $true) 'Cloud start conflict without a saved run preserves the claim and blocks duplicate execution'
        $retryRecoveryGuardTriggered = $false
        try { Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest | Out-Null } catch { $retryRecoveryGuardTriggered = $_.Exception.Message -match 'Preserve the claim record' }
        Assert-Felix3 $retryRecoveryGuardTriggered 'Cloud recovery-required claim cannot be retried as a fresh run'
        Remove-Item -LiteralPath $guardClaimPath -Force
        Set-Item -Path Function:\Start-Felix3CloudWorkItem -Value $savedCloudStartFunction
        $global:felix3TestCloudCode = 'C-104'; $global:felix3TestCloudClaimStatus = 'in_progress'
        $startsBeforeStickyRecovery = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/start$' }).Count
        $stickyRecoveryTriggered = $false
        try { Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest | Out-Null } catch { $stickyRecoveryTriggered = $_.Exception.Message -match 'Recover the original checkout' }
        $stickyClaim = Get-Content -LiteralPath $guardClaimPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $startsAfterStickyRecovery = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/start$' }).Count
        Assert-Felix3 ($stickyRecoveryTriggered -and $startsAfterStickyRecovery -eq $startsBeforeStickyRecovery -and $stickyClaim.recovery_required) 'Cloud in-progress sticky claim blocks execution without calling start'
        Remove-Item -LiteralPath $guardClaimPath -Force
        $global:felix3TestCloudCode = 'C-105'; $global:felix3TestCloudClaimStatus = $null
        $startsBeforeUnknownStatus = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/start$' }).Count
        $releasesBeforeUnknownStatus = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/release$' }).Count
        $tasksBeforeUnknownStatus = $global:felix3CloudTaskCalls
        $unknownStatusRejected = $false
        try { Invoke-Felix3CloudWorkCycle -ProjectPath $cloudProject -ConfigPath $cloudConfigPath -Request $cloudCycleRequest | Out-Null } catch { $unknownStatusRejected = $_.Exception.Message -match 'recognized claim status' }
        $unknownStatusClaim = Get-Content -LiteralPath $guardClaimPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $startsAfterUnknownStatus = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/start$' }).Count
        $releasesAfterUnknownStatus = @($cloudCycleApiLog | Where-Object { $_.Uri -match '/work/release$' }).Count
        Assert-Felix3 ($unknownStatusRejected -and $startsAfterUnknownStatus -eq $startsBeforeUnknownStatus -and $releasesAfterUnknownStatus -eq $releasesBeforeUnknownStatus -and $global:felix3CloudTaskCalls -eq $tasksBeforeUnknownStatus -and $unknownStatusClaim.recovery_required -eq $true) 'Cloud response with missing claim status preserves recovery state and blocks start, release, and harness execution'
        Remove-Item -LiteralPath $guardClaimPath -Force
        $global:felix3TestCloudClaimStatus = 'reserved'
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
        Set-Item -Path Function:\Start-Felix3CloudWorkItem -Value $savedCloudStartFunction
        Remove-Variable -Name felix3TestCloudCode,felix3TestCloudTaskStatus,felix3CloudTaskCalls,felix3TestCloudClaimStatus -Scope Global -ErrorAction SilentlyContinue
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
import json,sys,os
events=[
 {'type':'stream_event','session_id':'claude-session','event':{'type':'content_block_delta','delta':{'type':'thinking_delta','thinking':'PRIVATE_CLAUDE_THOUGHT_SENTINEL'}}},
 {'type':'stream_event','session_id':'claude-session','event':{'type':'content_block_delta','delta':{'type':'text_delta','text':'Claude surfaced delta'}}},
 {'type':'assistant','session_id':'claude-session','message':{'content':[{'type':'tool_use','name':'Read','input':{'file_path':'PRIVATE_CLAUDE_TOOL_INPUT_SENTINEL'}}]}},
 {'type':'result','session_id':'claude-session','result':'claude done','usage':{'input_tokens':12,'output_tokens':3},'total_cost_usd':0.001}
]
for event in events: print(json.dumps(event),flush=True)
if os.environ.get('FELIX3_CAPTURE_CLAUDE_ARGS'): open(os.environ['FELIX3_CAPTURE_CLAUDE_ARGS'],'w',encoding='utf-8').write(json.dumps(sys.argv[1:]))
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
        grok = @'
import json,sys,os
events=[
 {'type':'available_commands','tools':[],'commands':[]},
 {'method':'session/update','params':{'sessionId':'grok-session','update':{'sessionUpdate':'agent_thought_chunk','content':{'type':'text','text':'PRIVATE_GROK_THOUGHT_SENTINEL'}}}},
 {'method':'session/update','params':{'sessionId':'grok-session','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'Grok surfaced response'}}}},
 {'method':'session/update','params':{'sessionId':'grok-session','update':{'sessionUpdate':'tool_call','toolCallId':'t1','title':'shell'}}},
 {'method':'session/update','params':{'sessionId':'grok-session','update':{'sessionUpdate':'tool_call_update','toolCallId':'t1','status':'completed','content':'PRIVATE_TOOL_OUTPUT_SENTINEL'}}},
 {'method':'session/update','params':{'sessionId':'grok-session','update':{'sessionUpdate':'usage_update','usage':{'input_tokens':11,'output_tokens':7}}}},
 {'jsonrpc':'2.0','id':2,'result':{'sessionId':'grok-session','usage':{'input_tokens':11,'output_tokens':7},'total_cost_usd':0.004,'num_turns':2,'stopReason':'end_turn'}}]
for e in events: print(json.dumps(e),flush=True)
if os.environ.get('FELIX3_CAPTURE_GROK_ARGS'): open(os.environ['FELIX3_CAPTURE_GROK_ARGS'],'w',encoding='utf-8').write(json.dumps(sys.argv[1:]))
'@
    }
    foreach ($name in @('claude','opencode','codex','grok')) {
        $phaseDirectory = Join-Path $tempRoot "adapter-$name"
        New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
        $executable = New-FakeCli -Root $tempRoot -Name "fake-$name" -Source $fixtureSources[$name]
        $sink = New-Felix3EventSink -Journal $journal -Phase "adapter-$name" -Harness $name
        if ($name -eq 'claude') {
            $captureClaudeArgsPath = Join-Path $tempRoot 'claude-args.json'; $env:FELIX3_CAPTURE_CLAUDE_ARGS = $captureClaudeArgsPath
            try { $result = Invoke-ClaudeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -AllowedTools @('Bash(python -m unittest:*)','Read') -Journal $journal -EventSink $sink }
            finally { Remove-Item Env:FELIX3_CAPTURE_CLAUDE_ARGS -ErrorAction SilentlyContinue }
            $claudeArgs = Get-Content -LiteralPath $captureClaudeArgsPath -Raw | ConvertFrom-Json
            $allowedToolsIndex = [Array]::IndexOf($claudeArgs, '--allowedTools')
            Assert-Felix3 ($allowedToolsIndex -ge 0 -and $claudeArgs[$allowedToolsIndex + 1] -eq 'Bash(python -m unittest:*)' -and $claudeArgs[$allowedToolsIndex + 2] -eq 'Read') "Claude adapter forwards scoped allowed tools without widening the default policy (captured args: $($claudeArgs -join ' | '))"
        }
        elseif ($name -eq 'opencode') { $result = Invoke-OpenCodeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -Journal $journal -EventSink $sink }
        elseif ($name -eq 'grok') {
            $grokArgsPath = Join-Path $tempRoot 'grok-args.json'; $env:FELIX3_CAPTURE_GROK_ARGS = $grokArgsPath
            try { $result = Invoke-GrokBuildHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -PermissionMode 'dontAsk' -AllowRules @('Read','Edit','Bash(git status *)') -DenyRules @('Bash(git push *)') -Journal $journal -EventSink $sink }
            finally { Remove-Item Env:FELIX3_CAPTURE_GROK_ARGS -ErrorAction SilentlyContinue }
            $grokArgs = Get-Content -LiteralPath $grokArgsPath -Raw | ConvertFrom-Json
            Assert-Felix3 (($grokArgs -join ' ') -match '--permission-mode dontAsk' -and $grokArgs -contains '--allow' -and @($grokArgs | Where-Object { $_ -eq 'Bash(git status *)' }).Count -eq 1 -and $grokArgs -contains '--deny' -and @($grokArgs | Where-Object { $_ -eq 'Bash(git push *)' }).Count -eq 1) 'Grok adapter forwards scoped shell matcher and deny rules'
        }
        else {
            $captureArgsPath = Join-Path $tempRoot 'codex-args.json'; $env:FELIX3_CAPTURE_ARGS = $captureArgsPath
            try { $result = Invoke-CodexHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $phaseDirectory -Executable $executable -WindowsSandbox 'unelevated' -Journal $journal -EventSink $sink }
            finally { Remove-Item Env:FELIX3_CAPTURE_ARGS -ErrorAction SilentlyContinue }
            $codexArgs = Get-Content -LiteralPath $captureArgsPath -Raw | ConvertFrom-Json
            Assert-Felix3 ($codexArgs -notcontains '-a' -and $codexArgs -contains '-c' -and ($codexArgs -join ' ') -match 'approval_policy="on-request"') 'Codex adapter uses supported approval config overrides'
            Assert-Felix3 (($codexArgs -join ' ') -match 'windows\.sandbox="unelevated"') 'Codex adapter forwards the optional Windows sandbox backend override'
        }
        $expectedHarness = @{ claude='claude-code'; opencode='opencode'; codex='codex'; grok='grok-build' }[$name]
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
        if ($name -eq 'claude') {
            $claudeEvents = @(Get-Content -LiteralPath $journal.EventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.phase -eq 'adapter-claude' })
            $claudeDeltas = @($claudeEvents | Where-Object kind -eq 'output.delta')
            $claudeProjection = @($claudeEvents | ForEach-Object { ConvertTo-Felix3LiveProjection -Event $_ } | Where-Object { $_ })
            Assert-Felix3 ($claudeDeltas.Count -eq 1 -and $claudeDeltas[0].summary -eq 'Claude surfaced delta') 'Claude stream-json text deltas enter the normalized event stream'
            Assert-Felix3 (@($claudeProjection | Where-Object { $_.kind -eq 'assistant.delta' -and $_.text -eq 'Claude surfaced delta' }).Count -eq 1) 'Claude surfaced text maps to the shared live assistant-delta contract'
            Assert-Felix3 ((($claudeEvents + $claudeProjection) | ConvertTo-Json -Depth 10) -notmatch 'PRIVATE_CLAUDE_THOUGHT_SENTINEL|PRIVATE_CLAUDE_TOOL_INPUT_SENTINEL') 'Claude reasoning and tool input never enter normalized or live events'
            Assert-Felix3 (@($claudeProjection | Where-Object { $_.kind -eq 'tool.started' -and $_.tool -eq 'Read' }).Count -eq 1) 'Claude tool start projects only its allowlisted tool name'
        }
        elseif ($name -eq 'grok') {
            Assert-Felix3 ($result.ResultText -eq 'Grok surfaced response' -and $result.CostUsd -eq 0.004 -and $result.Turns -eq 2) 'Grok normalizes surfaced text and provider usage metadata'
            $grokEvents = @(Get-Content -LiteralPath $journal.EventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.phase -eq 'adapter-grok' })
            Assert-Felix3 (($grokEvents | ConvertTo-Json -Depth 10) -notmatch 'PRIVATE_GROK_THOUGHT_SENTINEL|PRIVATE_TOOL_OUTPUT_SENTINEL') 'Grok thought and tool output content never enter normalized events'
            $questionExe = New-FakeCli -Root $tempRoot -Name 'fake-grok-question' -Source @'
import json
for text in ['visible before <felix3-ques','tion>{"question":"PRIVATE_GROK_QUESTION_SENTINEL"}','</felix3-question>']:
 e={'method':'session/update','params':{'sessionId':'grok-question-session','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':text}}}}
 print(json.dumps(e),flush=True)
'@
            $questionDir = Join-Path $tempRoot 'adapter-grok-question'; New-Item -ItemType Directory -Path $questionDir -Force | Out-Null
            $questionLiveEvents = [System.Collections.ArrayList]::new()
            $questionLiveSink = { param($event) [void]$questionLiveEvents.Add($event) }.GetNewClosure()
            $questionSink = New-Felix3EventSink -Journal $journal -Phase 'adapter-grok-question' -Harness 'grok-build' -CloudSink $questionLiveSink
            $questionResult = Invoke-GrokBuildHarness -Phase planning -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $questionDir -Executable $questionExe -EventSink $questionSink
            Assert-Felix3 ($questionResult.NeedsInput -and -not $questionResult.Succeeded) 'Grok question marker interrupts the phase and enters the shared human-input workflow'
            $questionLiveJson = $questionLiveEvents | ConvertTo-Json -Depth 10
            $questionLiveKinds = (@($questionLiveEvents | ForEach-Object { $_.kind }) -join ',')
            $questionBodyLeaked = $questionLiveJson.Contains('PRIVATE_GROK_QUESTION_SENTINEL')
            Assert-Felix3 (-not $questionBodyLeaked -and $questionLiveKinds -match 'question.requested') "Grok live sink event kinds: $questionLiveKinds; private question included: $questionBodyLeaked"
        }
    }

    $previousCloudKey = $env:FELIX_SYNC_KEY
    $previousAgentKey = $env:FELIX_SYNC_AGENT_KEY
    $previousLivePipe = $env:FELIX3_LIVE_PIPE
    $env:FELIX_SYNC_KEY = 'private-cloud-key-sentinel'
    $env:FELIX_SYNC_AGENT_KEY = 'private-agent-key-sentinel'
    $env:FELIX3_LIVE_PIPE = 'private-pipe-name-sentinel'
    $envCapturePath = Join-Path $tempRoot 'harness-environment.txt'
    $env:FELIX3_CAPTURE_ENV = $envCapturePath
    try {
        $environmentExe = New-FakeCli -Root $tempRoot -Name 'fake-environment' -Source @'
import json,os
open(os.environ['FELIX3_CAPTURE_ENV'],'w',encoding='utf-8').write('|'.join(os.getenv(k,'') for k in ['FELIX_SYNC_KEY','FELIX_SYNC_AGENT_KEY','FELIX3_LIVE_PIPE']))
for e in [{'type':'text','sessionID':'environment-session','part':{'text':'safe'}},{'type':'step_finish','sessionID':'environment-session','part':{}}]: print(json.dumps(e),flush=True)
'@
        $environmentPhase = Join-Path $tempRoot 'adapter-environment'
        New-Item -ItemType Directory -Path $environmentPhase -Force | Out-Null
        $environmentResult = Invoke-OpenCodeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $environmentPhase -Executable $environmentExe
        Assert-Felix3 $environmentResult.Succeeded 'environment isolation fixture harness completed'
        Assert-Felix3 ([string](Get-Content -LiteralPath $envCapturePath -Raw) -eq '||') 'native harness processes do not inherit Cloud credentials or Felix live pipe address'
    }
    finally {
        if ($null -eq $previousCloudKey) { Remove-Item Env:FELIX_SYNC_KEY -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_KEY = $previousCloudKey }
        if ($null -eq $previousAgentKey) { Remove-Item Env:FELIX_SYNC_AGENT_KEY -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_AGENT_KEY = $previousAgentKey }
        if ($null -eq $previousLivePipe) { Remove-Item Env:FELIX3_LIVE_PIPE -ErrorAction SilentlyContinue } else { $env:FELIX3_LIVE_PIPE = $previousLivePipe }
        Remove-Item Env:FELIX3_CAPTURE_ENV -ErrorAction SilentlyContinue
    }

    # The coordinator uses PowerShell as the pipe client and the CLI as server.
    # Exercise the real PowerShell writer against a local pipe with no Cloud dependency.
    if (-not ('Felix3PipeContractTest.LocalPipeReader' -as [type])) {
        Add-Type -TypeDefinition @'
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading.Tasks;
namespace Felix3PipeContractTest {
    public static class LocalPipeReader {
        public static Task<string> ReadLine(string name) {
            return Task.Run(() => {
                using (var server = new NamedPipeServerStream(name, PipeDirection.In, 1, PipeTransmissionMode.Byte)) {
                    server.WaitForConnection();
                    using (var reader = new StreamReader(server, new UTF8Encoding(false))) {
                        return reader.ReadLine();
                    }
                }
            });
        }
    }
}
'@
    }
    $previousPipeAddress = $env:FELIX3_LIVE_PIPE
    $pipeName = 'felix3-live-ps-test-{0}' -f [guid]::NewGuid().ToString('N')
    $pipeReadTask = [Felix3PipeContractTest.LocalPipeReader]::ReadLine($pipeName)
    try {
        $env:FELIX3_LIVE_PIPE = $pipeName
        $pipeEvent = @{ type='event'; event=@{ kind='phase.started'; phase='planning'; harness='opencode'; run_id='pipe-test'; seq=1 } }
        Assert-Felix3 (Send-Felix3LivePipeMessage -Message $pipeEvent) 'PowerShell coordinator connects to the live named pipe'
        Assert-Felix3 ($pipeReadTask.Wait([TimeSpan]::FromSeconds(5))) 'named-pipe server receives the PowerShell event'
        $pipeLine = $pipeReadTask.Result
        $pipeEnvelope = $pipeLine | ConvertFrom-Json
        Assert-Felix3 ($pipeEnvelope.type -eq 'event' -and $pipeEnvelope.event.kind -eq 'phase.started' -and $pipeEnvelope.event.phase -eq 'planning') 'PowerShell named-pipe writer delivers a normalized event envelope'
    }
    finally {
        try { if ($global:Felix3LivePipeWriter) { $global:Felix3LivePipeWriter.Dispose() } } catch { }
        $global:Felix3LivePipeWriter = $null
        if ($null -eq $previousPipeAddress) { Remove-Item Env:FELIX3_LIVE_PIPE -ErrorAction SilentlyContinue } else { $env:FELIX3_LIVE_PIPE = $previousPipeAddress }
    }

    $previousPipeAddress = $env:FELIX3_LIVE_PIPE
    $pipeName = 'felix3-live-ps-stall-{0}' -f [guid]::NewGuid().ToString('N')
    $stalledServer = [System.IO.Pipes.NamedPipeServerStream]::new($pipeName, [System.IO.Pipes.PipeDirection]::In, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
    $stalledConnect = $stalledServer.WaitForConnectionAsync()
    try {
        $env:FELIX3_LIVE_PIPE = $pipeName
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $dropped = 0
        for ($i = 0; $i -lt 256; $i++) {
            $message = @{ type = 'event'; event = @{ kind = 'assistant.delta'; text = ('x' * 8192); seq = $i } }
            if (-not (Send-Felix3LivePipeMessage -Message $message)) { $dropped++ }
        }
        $watch.Stop()
        Assert-Felix3 ($stalledConnect.Wait([TimeSpan]::FromSeconds(5))) 'slow-consumer test accepts the Felix producer pipe'
        Assert-Felix3 ($watch.Elapsed.TotalSeconds -lt 5) 'a stalled live-pipe reader cannot block event production'
        Assert-Felix3 ($dropped -gt 0) 'slow live-pipe consumers cause bounded transient drops'
    }
    finally {
        $stalledServer.Dispose()
        try { if ($global:Felix3LivePipeWriter) { $global:Felix3LivePipeWriter.Dispose() } } catch { }
        $global:Felix3LivePipeWriter = $null
        $global:Felix3LivePipeWriteTask = $null
        if ($null -eq $previousPipeAddress) { Remove-Item Env:FELIX3_LIVE_PIPE -ErrorAction SilentlyContinue } else { $env:FELIX3_LIVE_PIPE = $previousPipeAddress }
    }

    $claudeLiveSource = @'
import json
events=[
 {'type':'stream_event','event':{'type':'content_block_delta','delta':{'type':'thinking_delta','thinking':'PRIVATE_THINKING_SENTINEL'}}},
 {'type':'stream_event','event':{'type':'content_block_delta','delta':{'type':'text_delta','text':'surfaced assistant text'}}},
 {'type':'stream_event','event':{'type':'content_block_delta','delta':{'type':'input_json_delta','partial_json':'PRIVATE_TOOL_INPUT_SENTINEL'}}},
 {'type':'assistant','session_id':'claude-live-session','message':{'content':[{'type':'tool_use','name':'Bash','input':{'command':'PRIVATE_COMMAND_SENTINEL'}}]}},
 {'type':'assistant','session_id':'claude-live-session','message':{'content':[{'type':'tool_use','name':'AskUserQuestion','input':{'questions':[{'question':'PRIVATE_QUESTION_SENTINEL'}]}}]}},
 {'type':'result','session_id':'claude-live-session','result':'complete'}]
for e in events: print(json.dumps(e),flush=True)
'@
    $claudeLiveExe = New-FakeCli -Root $tempRoot -Name 'fake-claude-live-filter' -Source $claudeLiveSource
    $claudeLivePhase = Join-Path $tempRoot 'claude-live-filter'; New-Item -ItemType Directory -Path $claudeLivePhase -Force | Out-Null
    $claudeLiveSink = New-Felix3EventSink -Journal $journal -Phase 'claude-live-filter' -Harness 'claude-code'
    $claudeLiveResult = Invoke-ClaudeHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $claudeLivePhase -Executable $claudeLiveExe -Journal $journal -EventSink $claudeLiveSink
    Assert-Felix3 $claudeLiveResult.Succeeded 'Claude privacy fixture completes normally'
    $claudeLiveEvents = @([IO.File]::ReadLines($journal.EventPath) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.phase -eq 'claude-live-filter' })
    $claudeProjection = @($claudeLiveEvents | ForEach-Object { ConvertTo-Felix3LiveProjection -Event $_ } | Where-Object { $_ })
    $claudeOutput = @($claudeProjection | Where-Object { $_.kind -eq 'assistant.delta' })
    $claudeProjectionJson = $claudeProjection | ConvertTo-Json -Depth 10 -Compress
    Assert-Felix3 ($claudeOutput.Count -eq 1 -and $claudeOutput[0].text -eq 'surfaced assistant text') 'Claude live projection emits only surfaced text deltas'
    Assert-Felix3 (@($claudeProjection | Where-Object { $_.kind -eq 'tool.started' -and $_.tool -eq 'Bash' }).Count -eq 1) 'Claude live projection retains safe tool identity only'
    Assert-Felix3 (@($claudeProjection | Where-Object { $_.kind -eq 'question.requested' }).Count -eq 1) 'Claude question projection is a generic prompt indicator'
    Assert-Felix3 ($claudeProjectionJson -notmatch 'PRIVATE_THINKING|PRIVATE_TOOL_INPUT|PRIVATE_COMMAND|PRIVATE_QUESTION') 'Claude reasoning, tool input, command arguments, and question wording stay out of live projection'

    $codexLiveSource = @'
import json
events=[
 {'type':'thread.started','thread_id':'codex-live-session'},
 {'type':'item.started','thread_id':'codex-live-session','item':{'type':'command_execution','command':'PRIVATE_CODEX_COMMAND_SENTINEL'}},
 {'type':'item.completed','thread_id':'codex-live-session','item':{'type':'agent_message','text':'Codex surfaced assistant text'}},
 {'type':'item.completed','thread_id':'codex-live-session','item':{'type':'command_execution','output':'PRIVATE_CODEX_OUTPUT_SENTINEL'}},
 {'type':'turn.completed','thread_id':'codex-live-session','usage':{'input_tokens':8,'output_tokens':3,'total_tokens':11}}]
for e in events: print(json.dumps(e),flush=True)
'@
    $codexLiveExe = New-FakeCli -Root $tempRoot -Name 'fake-codex-live-filter' -Source $codexLiveSource
    $codexLivePhase = Join-Path $tempRoot 'codex-live-filter'; New-Item -ItemType Directory -Path $codexLivePhase -Force | Out-Null
    $codexLiveSink = New-Felix3EventSink -Journal $journal -Phase 'codex-live-filter' -Harness 'codex'
    $codexLiveResult = Invoke-CodexHarness -Phase building -WorkingDirectory $tempRoot -Prompt 'prompt' -RunDirectory $codexLivePhase -Executable $codexLiveExe -Journal $journal -EventSink $codexLiveSink
    Assert-Felix3 $codexLiveResult.Succeeded 'Codex privacy fixture completes normally'
    $codexLiveEvents = @([IO.File]::ReadLines($journal.EventPath) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.phase -eq 'codex-live-filter' })
    $codexProjection = @($codexLiveEvents | ForEach-Object { ConvertTo-Felix3LiveProjection -Event $_ } | Where-Object { $_ })
    $codexOutput = @($codexProjection | Where-Object { $_.kind -eq 'assistant.delta' })
    $codexProjectionJson = $codexProjection | ConvertTo-Json -Depth 10 -Compress
    Assert-Felix3 ($codexOutput.Count -eq 1 -and $codexOutput[0].text -eq 'Codex surfaced assistant text') 'Codex completed assistant messages become live output chunks'
    Assert-Felix3 (@($codexProjection | Where-Object { $_.kind -eq 'tool.started' -and $_.tool -eq 'command_execution' }).Count -eq 1) 'Codex live projection retains safe command tool identity only'
    Assert-Felix3 ($codexProjectionJson -notmatch 'PRIVATE_CODEX_COMMAND|PRIVATE_CODEX_OUTPUT') 'Codex command arguments and tool output stay out of live projection'

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

    # Durable Cloud event payloads contain lifecycle metadata only; question text always stays local.
    $cloudStatePath = Join-Path $tempRoot 'cloud-state.json'
    @{ last_event_seq = 0; updated_at = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $cloudStatePath -Encoding UTF8
    $fakeCloudClient = [Fel3TestCloudClient]::new()
    $cloud = [pscustomobject]@{ Client = $fakeCloudClient; CloudRunId = 'cloud-id'; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = [pscustomobject]@{ include_phase_summaries = $true; live_activity = $false; artifacts = @() } }
    Add-Felix3CloudEvent -Cloud $cloud -Event ([pscustomobject]@{ kind = 'output.delta'; event_id = 'e1'; run_id = 'local'; seq = 1; phase = 'building'; harness = 'codex'; summary = 'private source text'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{} })
    Assert-Felix3 ($fakeCloudClient.Events.Count -eq 0 -and $cloud.Buffer.Count -eq 0) 'cloud never receives streamed assistant text'
    $outputProjection = ConvertTo-Felix3LiveProjection -Event ([pscustomobject]@{ kind = 'output.delta'; run_id = 'local'; seq = 1; timestamp = [DateTime]::UtcNow.ToString('o'); phase = 'building'; harness = 'opencode'; summary = 'surfaced text'; payload = @{ provider_event = 'text'; private = 'must not pass' } })
    Assert-Felix3 ($outputProjection.kind -eq 'assistant.delta' -and $outputProjection.text -eq 'surfaced text' -and -not ($outputProjection | ConvertTo-Json -Compress | Select-String 'private|provider_event')) 'live projection copies only surfaced assistant text into a versioned allowlist'
    $grokLiveToolAliases = @(
        @{ Native = 'run_terminal_command'; Expected = 'command_execution' },
        @{ Native = 'read_file'; Expected = 'read' },
        @{ Native = 'search_replace'; Expected = 'edit' },
        @{ Native = 'list_dir'; Expected = 'list' },
        @{ Native = 'grep'; Expected = 'grep' },
        @{ Native = 'write'; Expected = 'write' }
    )
    foreach ($toolAlias in $grokLiveToolAliases) {
        $grokToolProjection = ConvertTo-Felix3LiveProjection -Event ([pscustomobject]@{ kind = 'tool.started'; run_id = 'local'; seq = 3; timestamp = [DateTime]::UtcNow.ToString('o'); phase = 'building'; harness = 'grok-build'; summary = 'Grok started a tool.'; payload = @{ tool = $toolAlias.Native; status = 'started' } })
        Assert-Felix3 ($grokToolProjection.tool -eq $toolAlias.Expected) "Grok live tool '$($toolAlias.Native)' maps to '$($toolAlias.Expected)'"
    }
    $pathAndSecretProjection = ConvertTo-Felix3LiveProjection -Event ([pscustomobject]@{ kind = 'output.delta'; run_id = 'local'; seq = 2; timestamp = [DateTime]::UtcNow.ToString('o'); phase = 'building'; harness = 'opencode'; summary = 'Open C:\Users\Alice Smith\project\src\main.cs and /home/alice/project/src/main.py; token=sk-or-v1-0123456789abcdefghijklmnop; xai-0123456789abcdefghijklmnopqrstuv; https://example.com/docs'; payload = @{} })
    Assert-Felix3 ($pathAndSecretProjection.text -notmatch 'C:\\Users|/home/alice|sk-or-v1-|xai-0123456789' -and $pathAndSecretProjection.text -match '\[local path\]' -and $pathAndSecretProjection.text -match 'https://example.com/docs') 'live assistant text redacts absolute machine paths and provider credentials while preserving URLs'
    $questionProjection = ConvertTo-Felix3LiveProjection -Event ([pscustomobject]@{ kind = 'question.requested'; run_id = 'local'; seq = 2; timestamp = [DateTime]::UtcNow.ToString('o'); phase = 'planning'; harness = 'claude-code'; summary = 'Sensitive question wording'; payload = @{ question = 'Sensitive question wording'; tool = 'AskUserQuestion' } })
    Assert-Felix3 (($questionProjection | ConvertTo-Json -Compress) -notmatch 'Sensitive question|AskUserQuestion') 'live question projection contains no question text or question tool payload'
    Add-Felix3CloudEvent -Cloud $cloud -Event ([pscustomobject]@{ kind = 'question.requested'; event_id = 'e2'; run_id = 'local'; seq = 2; phase = 'planning'; harness = 'codex'; summary = 'Sensitive project question?'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{ question = 'Sensitive project question?' } })
    $sentQuestion = $fakeCloudClient.Events[0]
    Assert-Felix3 ($sentQuestion.message -eq 'Human input requested.' -and ($sentQuestion | ConvertTo-Json -Depth 20 -Compress) -notmatch 'Sensitive project question') 'durable cloud question summaries never contain question text'
    $liveCloudClient = [Fel3TestCloudClient]::new()
    $liveCloud = [pscustomobject]@{ Client = $liveCloudClient; CloudRunId = 'cloud-id'; LiveEnabled = $true; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = [pscustomobject]@{ include_phase_summaries = $true; live_activity = $true; artifacts = @() } }
    Add-Felix3CloudEvent -Cloud $liveCloud -Event ([pscustomobject]@{ kind = 'tool.started'; event_id = 'e-live'; run_id = 'local'; seq = 4; phase = 'building'; harness = 'opencode'; summary = 'Sensitive command and model reasoning'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{ tool = 'shell'; status = 'started'; provider_event = 'private provider payload'; usage = @{ output_tokens = 99 } } })
    Assert-Felix3 ($liveCloudClient.Activity.Count -eq 0 -and $liveCloud.Buffer.Count -eq 1 -and $liveCloud.Buffer[0].message -eq 'Tool started.') 'opt-in live activity avoids synchronous HTTP and durable metadata remains a fixed summary'
    Assert-Felix3 (($liveCloud.Buffer[0] | ConvertTo-Json -Depth 10 -Compress) -notmatch 'Sensitive command|private provider|output_tokens|harness') 'durable Cloud action metadata excludes provider output, reasoning, usage, and harness internals'
    $retryCloudClient = [Fel3TestCloudClient]::new()
    $retryCloudClient.FailAppend = $true
    $retryCloud = [pscustomobject]@{ Client = $retryCloudClient; CloudRunId = 'cloud-id'; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = $cloud.Settings }
    Add-Felix3CloudEvent -Cloud $retryCloud -Event ([pscustomobject]@{ kind = 'phase.completed'; event_id = 'e-retry'; run_id = 'local'; seq = 3; phase = 'planning'; harness = 'codex'; summary = 'Planning done'; timestamp = [DateTime]::UtcNow.ToString('o'); payload = @{} })
    Assert-Felix3 ($retryCloud.Buffer.Count -eq 1) 'failed Cloud event upload retains the batch for retry'
    $retryCloudClient.FailAppend = $false
    Send-Felix3CloudEvents -Cloud $retryCloud
    $retriedSequence = (Get-Content -LiteralPath $cloudStatePath -Raw | ConvertFrom-Json).last_event_seq
    Assert-Felix3 ($retryCloud.Buffer.Count -eq 0 -and $retryCloudClient.Events.Count -eq 1 -and $retriedSequence -eq 2) 'Cloud event retry clears the buffer and advances the durable sequence only after success'
    . (Join-Path $PSScriptRoot '..\..\..\.felix\core\sync-interface.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\.felix\plugins\sync-http\http-client.ps1')
    $savedRestFunction = Get-Item Function:\global:Invoke-RestMethod -ErrorAction SilentlyContinue
    $global:felix3OutboxOffline = $true
    $global:felix3OutboxRequests = [System.Collections.ArrayList]::new()
    Set-Item Function:\global:Invoke-RestMethod -Value {
        [CmdletBinding()]
        param([string]$Method, [string]$Uri, [hashtable]$Headers, [object]$Body, [int]$TimeoutSec, [string]$ContentType)
        if ($global:felix3OutboxOffline) { throw 'Unable to connect (simulated offline).' }
        [void]$global:felix3OutboxRequests.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
        return @{ ok = $true }
    }
    $syncOutboxDirectory = Join-Path $tempRoot 'sync-http-outbox'
    New-Item -ItemType Directory -Path $syncOutboxDirectory -Force | Out-Null
    try {
        $syncClient = [HttpSync]::new(@{ base_url = 'http://localhost:12345'; api_key = 'fsk-test' }, $syncOutboxDirectory)
        $syncClient.AppendEvents('felix3-outbox-smoke', @(@{ type = 'felix3.phase.completed'; level = 'info'; message = 'phase done'; run_id = 'cloud-run'; data = @{ sequence = 1 } }))
        $runOutboxPath = Join-Path (Join-Path $syncOutboxDirectory 'outbox') 'run-felix3-outbox-smoke.jsonl'
        Assert-Felix3 (Test-Path -LiteralPath $runOutboxPath) 'offline sync-http event upload is persisted in its JSONL disk outbox'
        Assert-Felix3 (@(Get-Content -LiteralPath $runOutboxPath).Count -eq 1) 'disk outbox contains one event record'
        $global:felix3OutboxOffline = $false
        $syncClient.FinishRun('felix3-outbox-smoke', @{ status = 'completed' })
        Assert-Felix3 ((-not (Test-Path -LiteralPath $runOutboxPath)) -and $global:felix3OutboxRequests.Count -ge 1) 'sync-http reconnect retries queued events and removes the run-event outbox file'
        Assert-Felix3 (@($global:felix3OutboxRequests | Where-Object { $_.Uri -match '/api/runs/felix3-outbox-smoke/events$' }).Count -eq 1) 'disk outbox retry sends the queued event batch to the run events endpoint'
        $startedCloudRun = $syncClient.StartRun(@{ agent_key = 'ag-test'; project_id = 'project-test'; metadata = @{ felix3_run_id = 'local-run'; live_stream_enabled = $true } })
        Assert-Felix3 ([bool]$startedCloudRun -and @($global:felix3OutboxRequests | Where-Object { $_.Uri -match '/api/runs$' }).Count -eq 1) 'a single queued run-start request flushes through the outbox'
        $runStartBody = @($global:felix3OutboxRequests | Where-Object { $_.Uri -match '/api/runs$' })[0].Body | ConvertFrom-Json
        Assert-Felix3 ($runStartBody.metadata.live_stream_enabled -eq $true -and $runStartBody.metadata.felix3_run_id -eq 'local-run') 'run-start sync sends the live-stream opt-in as nested non-content metadata'
    }
    finally {
        if ($savedRestFunction) { Set-Item Function:\global:Invoke-RestMethod -Value $savedRestFunction.ScriptBlock }
        else { Remove-Item Function:\global:Invoke-RestMethod -ErrorAction SilentlyContinue }
        Remove-Variable felix3OutboxOffline, felix3OutboxRequests -Scope Global -ErrorAction SilentlyContinue
    }
    $interruptRun = Join-Path $tempRoot 'interrupted-cloud-run'; New-Item -ItemType Directory -Path $interruptRun -Force | Out-Null
    $interruptJournal = Initialize-Felix3RunJournal -RunDirectory $interruptRun -RunId 'interrupt-cloud'
    $interruptStatePath = Join-Path $interruptRun 'state.json'
    $interruptState = [ordered]@{ schema = 'felix3-task-state-v2'; id = 'interrupt-cloud'; run_id = 'interrupt-cloud'; status = 'building'; active_phase = 'building'; phases = @(); validation = $null; outcome = $null; pending_question = $null; process = $null }
    Write-Felix3AtomicJson -Path $interruptStatePath -Value $interruptState
    $interruptCloud = [pscustomobject]@{ Client = $fakeCloudClient; CloudRunId = 'cloud-id'; RunId = 'interrupt-cloud'; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow; StatePath = $cloudStatePath; Settings = $cloud.Settings }
    $interruptResult = [pscustomobject]@{ Interrupted = $true; Harness = 'codex'; SessionId = 'session' }
    Assert-Felix3 (Suspend-Felix3ForStop -Result $interruptResult -Phase building -State $interruptState -StatePath $interruptStatePath -RunDirectory $interruptRun -Journal $interruptJournal -Cloud $interruptCloud) 'coordinator records an interrupted run'
    Assert-Felix3 ($fakeCloudClient.FinishCount -eq 0 -and $fakeCloudClient.FlushCount -gt 0) 'resumable interruption flushes cloud events without finishing the cloud run'

    $stopProject = Join-Path $tempRoot 'stop-request-project'
    $stopRun = Join-Path $stopProject '.felix3\runs\stop-request'
    New-Item -ItemType Directory -Path $stopRun -Force | Out-Null
    $stopConfig = Import-Felix3Config -Path (Join-Path $PSScriptRoot '..\felix3.config.example.json')
    Write-Felix3Json -Path (Join-Path $stopProject '.felix3\config.json') -Value $stopConfig
    $stopState = [ordered]@{ schema = 'felix3-task-state-v2'; id = 'stop-request'; run_id = 'stop-request'; status = 'building'; active_phase = 'building'; phases = @(); validation = $null; outcome = $null; pending_question = $null; process = $null }
    Write-Felix3AtomicJson -Path (Join-Path $stopRun 'state.json') -Value $stopState
    $stopResult = Stop-Felix3Task -ProjectPath $stopProject -RunId 'stop-request'
    $savedStopState = Get-Content (Join-Path $stopRun 'state.json') -Raw | ConvertFrom-Json
    Assert-Felix3 ($stopResult.Status -eq 'stop-requested' -and $savedStopState.status -eq 'stop-requested') 'Stop-Felix3Task accepts and records a stop request from an active build'
    Assert-Felix3 (Test-Path (Join-Path $stopRun 'cancel.requested')) 'Stop-Felix3Task writes the cooperative cancellation token'

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
if os.environ.get('FELIX3_CAPTURE_ARGS'): open(os.environ['FELIX3_CAPTURE_ARGS'],'a',encoding='utf-8').write(json.dumps({'args':a,'prompt':p,'working_directory':os.getcwd()})+'\n')
'@
    $codexExe = New-FakeCli -Root $tempRoot -Name 'fake-coordinator' -Source $coordinatorSource
    $config = @{
        schema_version = 1
        execution = @{ worktree = @{ enabled = $false } }
        work_source = @{ provider = 'manual-spec'; specs_dir = 'specs'; ready_status = 'ready' }
        artifacts = @{ runs_dir = '.felix3/runs'; local_retention_days = 30 }
        cloud_sync = @{ enabled = $false; agent_key = ''; include_phase_summaries = $true; include_question_text = $false; artifacts = @() }
        harness = @{ provider = 'codex'; codex = @{ executable = $codexExe; sandbox = 'read-only'; windows_sandbox = 'unelevated'; approval_policy = 'never'; session_policy = 'fresh'; phases = @{
            planning = @{ sandbox = 'read-only'; approval_policy = 'never' }
            building = @{ sandbox = 'workspace-write'; approval_policy = 'never'; session_policy = 'resume' }
            reviewing = @{ sandbox = 'read-only'; approval_policy = 'never' }
        } } }
        workflow = @{ require_plan_approval = $false; max_build_attempts = 2; max_review_cycles = 1; validation = @{ require_at_least_one_command = $true; commands = @(@{ name = 'python'; executable = $python; args = @('-c', "import pathlib,sys; p=pathlib.Path(r'$tempRoot\validate-once'); existed=p.exists(); p.write_text('seen'); sys.exit(0 if existed else 1)") }) } }
    }
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8
    $savedCaptureArgs = $env:FELIX3_CAPTURE_ARGS; $captureArgsPath = Join-Path $tempRoot 'coordinator-args.jsonl'; $env:FELIX3_CAPTURE_ARGS = $captureArgsPath
    try {
        $invalidConfig = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $invalidConfig.workflow.validation.commands = @()
        $invalidConfigPath = Join-Path $project '.felix3\invalid-config.json'
        $invalidConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $invalidConfigPath -Encoding UTF8
        $preflightRejected = $false
        $preflightError = ''
        try { Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-PREFLIGHT' -SpecPath 'specs/S-1.md' -ConfigPath '.felix3/invalid-config.json' -NewRunId 'preflight-rejected' | Out-Null }
        catch { $preflightError = $_.Exception.Message; $preflightRejected = $preflightError -match 'no harness phases were run' }
        $preflightRunPath = Join-Path $project '.felix3/runs/preflight-rejected'
        Assert-Felix3 ($preflightRejected -and -not (Test-Path -LiteralPath $preflightRunPath) -and -not (Test-Path -LiteralPath $captureArgsPath)) "missing required validation commands fail before run creation and provider calls (error='$preflightError', run_exists=$(Test-Path -LiteralPath $preflightRunPath), provider_called=$(Test-Path -LiteralPath $captureArgsPath))"
        $invalidConfig.workflow.validation.commands = @(@{ name = 'bad-args'; executable = 'python'; args = '-c' })
        $invalidConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $invalidConfigPath -Encoding UTF8
        $invalidArgsRejected = $false
        try { Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-PREFLIGHT-ARGS' -SpecPath 'specs/S-1.md' -ConfigPath '.felix3/invalid-config.json' -NewRunId 'preflight-args-rejected' | Out-Null }
        catch { $invalidArgsRejected = $_.Exception.Message -match 'args must be an array of strings' }
        $invalidArgsRunPath = Join-Path $project '.felix3/runs/preflight-args-rejected'
        Assert-Felix3 ($invalidArgsRejected -and -not (Test-Path -LiteralPath $invalidArgsRunPath) -and -not (Test-Path -LiteralPath $captureArgsPath)) 'scalar validation args fail before run creation and provider calls'
        $first = Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-1' -SpecPath 'specs/S-1.md'
        Assert-Felix3 ($first.Status -eq 'awaiting-input') 'coordinator persists an agent question and pauses the run'
        Assert-Felix3 (Test-Path -LiteralPath (Join-Path $first.RunDirectory 'question.json')) 'question is durable and inspectable'
        $resumed = Resume-Felix3Task -ProjectPath $project -RunId $first.RunId -Answer 'Use beta.'
    }
    finally { if ($null -eq $savedCaptureArgs) { Remove-Item Env:FELIX3_CAPTURE_ARGS -ErrorAction SilentlyContinue } else { $env:FELIX3_CAPTURE_ARGS = $savedCaptureArgs } }
    Assert-Felix3 ($resumed.Status -eq 'completed') 'answer resumes the same run through validation and review'
    $coordinatorCalls = @(Get-Content -LiteralPath $captureArgsPath | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Felix3 (@($coordinatorCalls | Where-Object { ($_.args -join ' ') -notmatch 'windows\.sandbox="unelevated"' }).Count -eq 0) 'coordinator forwards the configured Windows sandbox override to every Codex phase'
    $buildResumeCall = @($coordinatorCalls | Where-Object { $_.prompt -match 'building phase' -and $_.args -contains 'resume' })
    Assert-Felix3 ($buildResumeCall.Count -ge 1) 'building session_policy=resume continues the same session on validation retry'
    $state = Get-Content -LiteralPath $resumed.StatePath -Raw | ConvertFrom-Json
    Assert-Felix3 ($state.run_id -eq $first.RunId -and $state.status -eq 'completed') 'resumption preserves run identity and terminal state'
    Assert-Felix3 (Test-Path -LiteralPath (Join-Path $resumed.RunDirectory 'usage.json')) 'resumed run retains aggregated usage'

    # A failed Grok shell action must be reported as a harness failure, not as a validation failure.
    $failedGrokProject = Join-Path $tempRoot 'failed-grok-project'
    New-Item -ItemType Directory -Path (Join-Path $failedGrokProject 'specs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $failedGrokProject '.felix3') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $failedGrokProject 'specs/S-GROK-FAIL.md') -Value @'
---
id: S-GROK-FAIL
title: Grok failure diagnostic
---
# Verify greeting
'@ -Encoding UTF8
    $failedGrokSource = @'
import os,sys,json
a=sys.argv[1:]
prompt=open(a[a.index('--prompt-file')+1],encoding='utf-8').read()
if '# Felix 3 Planning Phase' in prompt:
    print(json.dumps({'type':'text','data':'# Plan\n\n## Acceptance Coverage\n| Criterion | Task | Check |\n|---|---|---|\n| The check passes | Task 1 | Run the hello validator |\n\n## Tasks\n- [ ] Run the check.\n\n## Validation\nRun the configured command.'}),flush=True)
    print(json.dumps({'type':'end','stopReason':'end_turn','sessionId':'failed-grok-session'}),flush=True)
else:
    prompt_path=a[a.index('--prompt-file')+1]
    open(os.path.join(os.path.dirname(prompt_path),'captured-build-prompt.txt'),'w',encoding='utf-8').write(prompt)
    print(json.dumps({'type':'tool_call','toolCallId':'call-1','toolName':'run_terminal_command'}),flush=True)
    print(json.dumps({'type':'tool_call_update','toolCallId':'call-1','status':'failed','content':{'type':'text','text':'User cancelled the execution for tool run_terminal_command'}}),flush=True)
    print(json.dumps({'type':'end','stopReason':'cancelled','sessionId':'failed-grok-session'}),flush=True)
'@
    $failedGrokExe = New-FakeCli -Root $tempRoot -Name 'fake-grok-cancel' -Source $failedGrokSource
    $failedGrokConfig = Import-Felix3Config -Path (Join-Path $PSScriptRoot '..\grok\felix3-grok.config.example.json')
    $failedGrokConfig.execution.worktree.enabled = $false
    $failedGrokConfig.artifacts.runs_dir = '.felix3/runs'
    $failedGrokConfig.cloud_sync.enabled = $false
    $failedGrokConfig.harness.'grok-build'.executable = $failedGrokExe
    $failedGrokConfig.workflow.max_build_attempts = 1
    $failedGrokConfig.workflow.validation.commands = @(@{ name = 'should-not-run'; executable = 'python'; args = @('-c','raise SystemExit(0)') })
    Write-Felix3Json -Path (Join-Path $failedGrokProject '.felix3\config.json') -Value $failedGrokConfig
    $failedGrokRun = Invoke-Felix3Task -ProjectPath $failedGrokProject -RequirementId 'S-GROK-FAIL' -SpecPath 'specs/S-GROK-FAIL.md'
    Assert-Felix3 ($failedGrokRun.Status -eq 'blocked' -and $failedGrokRun.Outcome -match "Grok Build tool 'run_terminal_command' failed with status 'failed'" -and $failedGrokRun.Outcome -match "Grok Build stopped with reason 'cancelled'") 'failed build diagnostics preserve the tool name/status and provider cancellation reason'
    Assert-Felix3 (-not $failedGrokRun.ValidationPath) 'validation is not reported as failed when no validation command ran'
    $failedGrokBuildPrompt = Get-Content -LiteralPath (Join-Path $failedGrokRun.RunDirectory 'building-1\captured-build-prompt.txt') -Raw -Encoding UTF8
    $grokBuildGuidanceHasSingleCommand = $failedGrokBuildPrompt -match '(?i)one terminal command per tool call'
    $grokBuildGuidanceDelegatesValidation = $failedGrokBuildPrompt -match '(?i)Felix runs configured validation commands'
    Assert-Felix3 ($grokBuildGuidanceHasSingleCommand -and $grokBuildGuidanceDelegatesValidation) "Grok build prompt avoids compound terminal calls and delegates acceptance validation to Felix (single=$grokBuildGuidanceHasSingleCommand, validation=$grokBuildGuidanceDelegatesValidation)"
    foreach ($grokPhase in @('planning','building','reviewing')) {
        $phasePrompt = Add-Felix3GrokTerminalGuidance -Prompt "Prompt for $grokPhase" -Phase $grokPhase
        Assert-Felix3 ($phasePrompt -match '(?i)one terminal command per tool call in every phase' -and $phasePrompt -match "Do not chain commands with PowerShell ';'") "Grok $grokPhase prompt forbids compound terminal commands"
        if ($grokPhase -eq 'reviewing') {
            Assert-Felix3 ($phasePrompt -match '(?i)During review, do not call terminal tools' -and $phasePrompt -match '(?i)supplied validation evidence') 'Grok review prompt avoids terminal approval requests and relies on provided validation evidence'
        }
    }
    $failedGrokResult = Get-Content -LiteralPath (Join-Path $failedGrokRun.RunDirectory 'building-1\harness-result.json') -Raw | ConvertFrom-Json
    Assert-Felix3 ($failedGrokResult.failed_tool_name -eq 'run_terminal_command' -and $failedGrokResult.failed_tool_status -eq 'failed' -and $failedGrokResult.error -notmatch 'User cancelled the execution') 'Grok local result records only safe failure metadata and excludes the raw tool result'

    # New configs default to a per-run worktree, and resume returns to that exact checkout.
    $worktreeRepo = Join-Path $tempRoot 'worktree-repo'
    $worktreeProject = Join-Path $worktreeRepo 'project'
    New-Item -ItemType Directory -Path (Join-Path $worktreeProject 'specs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $worktreeProject '.felix3') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $worktreeProject 'specs/S-WORKTREE.md') -Value 'HUMAN_CHOICE_REQUIRED' -Encoding UTF8
    $worktreeConfig = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $worktreeConfig.PSObject.Properties.Remove('execution')
    $worktreeConfig.workflow.require_plan_approval = $false
    $worktreeConfig.workflow.validation.require_at_least_one_command = $false
    $worktreeConfig.workflow.validation.commands = @()
    $worktreeConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $worktreeProject '.felix3/config.json') -Encoding UTF8
    & git -C $worktreeRepo init -b main | Out-Null
    & git -C $worktreeRepo -c user.name='Felix Test' -c user.email='felix-test@example.invalid' add .
    & git -C $worktreeRepo -c user.name='Felix Test' -c user.email='felix-test@example.invalid' commit -m 'test fixture' | Out-Null
    $projectAgentProfile = Join-Path $worktreeProject '.opencode/agents/felix3-review.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $projectAgentProfile) -Force | Out-Null
    Set-Content -LiteralPath $projectAgentProfile -Value 'description: disposable review profile' -Encoding UTF8
    $projectSkillFile = Join-Path $worktreeProject '.opencode/skills/project-guide/SKILL.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $projectSkillFile) -Force | Out-Null
    Set-Content -LiteralPath $projectSkillFile -Value 'Project-specific harness skill.' -Encoding UTF8
    $worktreeCapturePath = Join-Path $tempRoot 'worktree-calls.jsonl'
    $savedCaptureArgs = $env:FELIX3_CAPTURE_ARGS; $env:FELIX3_CAPTURE_ARGS = $worktreeCapturePath
    try {
        $worktreeFirst = Invoke-Felix3Task -ProjectPath $worktreeProject -RequirementId 'S-WORKTREE' -SpecPath 'specs/S-WORKTREE.md'
        Assert-Felix3 ($worktreeFirst.Status -eq 'awaiting-input') 'worktree-enabled default starts the task in an isolated checkout'
        $worktreeMetadata = Get-Content -LiteralPath (Join-Path $worktreeFirst.RunDirectory 'worktree.json') -Raw | ConvertFrom-Json
        Assert-Felix3 ((Test-Path -LiteralPath $worktreeMetadata.path -PathType Container) -and $worktreeMetadata.path -ne $worktreeProject) 'default run records a distinct existing worktree path'
        Assert-Felix3 (Test-Path -LiteralPath (Join-Path $worktreeMetadata.path '.opencode/agents/felix3-review.md')) 'worktree includes ignored project OpenCode agent profiles'
        Assert-Felix3 (Test-Path -LiteralPath (Join-Path $worktreeMetadata.path '.opencode/skills/project-guide/SKILL.md')) 'worktree includes ignored project OpenCode skills'
        $worktreeResumed = Resume-Felix3Task -ProjectPath $worktreeProject -RunId $worktreeFirst.RunId -Answer 'Use beta.'
    }
    finally { if ($null -eq $savedCaptureArgs) { Remove-Item Env:FELIX3_CAPTURE_ARGS -ErrorAction SilentlyContinue } else { $env:FELIX3_CAPTURE_ARGS = $savedCaptureArgs } }
    Assert-Felix3 ($worktreeResumed.Status -eq 'completed') 'resumed run continues successfully in its saved worktree'
    Assert-Felix3 ((Get-Content -LiteralPath (Join-Path $worktreeFirst.RunDirectory 'worktree.json') -Raw | ConvertFrom-Json).path -eq $worktreeMetadata.path) 'resume preserves the original worktree assignment'
    Assert-Felix3 ((Get-Content -LiteralPath $worktreeResumed.StatePath -Raw | ConvertFrom-Json).working_directory -eq $worktreeMetadata.path) 'run state records the active worktree directory'
    $worktreeCalls = @(Get-Content -LiteralPath $worktreeCapturePath | ForEach-Object { $_ | ConvertFrom-Json })
    $wrongWorktreeCalls = @($worktreeCalls | Where-Object { $_.working_directory -ne $worktreeMetadata.path })
    $wrongWorktreeDirectories = @($wrongWorktreeCalls | ForEach-Object { $_.working_directory }) -join '; '
    Assert-Felix3 (($worktreeCalls.Count -gt 0) -and $wrongWorktreeCalls.Count -eq 0) "harness phases, including resume, run inside the recorded worktree (expected '$($worktreeMetadata.path)', received '$wrongWorktreeDirectories')"
    $worktreeBuildPrompt = @($worktreeCalls | Where-Object { $_.prompt -match '# Felix 3 Building Phase' }) | Select-Object -Last 1
    $expectedHarnessPlanPath = Join-Path $worktreeMetadata.path ('.felix3/run-context/' + $worktreeFirst.RunId + '/plan.md')
    $approvedPlanLine = @($worktreeBuildPrompt.prompt -split "`r?`n" | Where-Object { $_ -match 'Approved plan' }) -join '; '
    Assert-Felix3 ($worktreeBuildPrompt.prompt -match [regex]::Escape($expectedHarnessPlanPath)) "build prompt points to the plan copy inside the worktree (expected '$expectedHarnessPlanPath', prompt '$approvedPlanLine')"
    Assert-Felix3 ($worktreeBuildPrompt.prompt -notmatch [regex]::Escape($worktreeFirst.RunDirectory)) 'build prompt does not expose the parent checkout run directory'
    $worktreeReviewPrompt = @($worktreeCalls | Where-Object { $_.prompt -match '# Felix 3 Review Phase' }) | Select-Object -Last 1
    Assert-Felix3 ($worktreeReviewPrompt.prompt -match '## Acceptance Coverage' -and $worktreeReviewPrompt.prompt -match '"passed"\s*:\s*true') 'review prompt embeds the plan and validation evidence'
    Assert-Felix3 ($worktreeReviewPrompt.prompt -notmatch [regex]::Escape($worktreeFirst.RunDirectory)) 'review prompt does not require access outside the worktree'
    $worktreeSecond = Invoke-Felix3Task -ProjectPath $worktreeProject -RequirementId 'S-WORKTREE-2' -SpecPath 'specs/S-WORKTREE.md'
    Assert-Felix3 ((Get-Content -LiteralPath (Join-Path $worktreeSecond.RunDirectory 'worktree.json') -Raw | ConvertFrom-Json).path -ne $worktreeMetadata.path) 'separate task runs receive separate worktrees'

    $config.harness.codex.Remove('windows_sandbox') | Out-Null
    $config.workflow.require_plan_approval = $false
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project '.felix3\config.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $project 'specs\S-DEFAULT-SANDBOX.md') -Value 'Default Codex sandbox setting smoke.' -Encoding UTF8
    $defaultSandboxRun = Invoke-Felix3Task -ProjectPath $project -RequirementId 'S-DEFAULT-SANDBOX' -SpecPath 'specs/S-DEFAULT-SANDBOX.md'
    Assert-Felix3 ($defaultSandboxRun.Status -eq 'completed') 'Codex coordinator runs with the optional Windows sandbox override omitted'

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
    Assert-Felix3 (Test-Path -LiteralPath (Join-Path $claudeCoordinatorRun.RunDirectory 'plan.md')) "Claude final plan response is persisted by Felix before build (status=$($claudeCoordinatorRun.Status), outcome=$($claudeCoordinatorRun.Outcome))"
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

    # Explicit local-spec linking creates a safe, opt-in upload request.
    . (Join-Path $PSScriptRoot '..\..\..\.felix\core\sync-interface.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\.felix\plugins\sync-http\http-client.ps1')
    $uploadBody = New-FelixSyncSpecUploadRequest -RelativePath 'specs\S-0001-cloud-link.md' -Content '# Cloud link smoke — café'
    $uploadedSpec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($uploadBody.files[0].content))
    Assert-Felix3 ($uploadBody.create_missing -and $uploadBody.files[0].path -eq 'specs/S-0001-cloud-link.md' -and $uploadedSpec -eq '# Cloud link smoke — café') 'local spec upload opts into requirement mapping and preserves UTF-8 content'
    $uploadAccepted = Resolve-FelixSyncSpecUploadResponse -Response ([pscustomobject]@{ results = @([pscustomobject]@{ path = 'specs/S-0001-cloud-link.md'; uploaded = $true; error = $null }) }) -RelativePath 'specs\S-0001-cloud-link.md'
    $uploadRejected = Resolve-FelixSyncSpecUploadResponse -Response ([pscustomobject]@{ results = @([pscustomobject]@{ path = 'specs/S-0001-cloud-link.md'; uploaded = $false; error = 'No mapping' }) }) -RelativePath 'specs\S-0001-cloud-link.md'
    Assert-Felix3 ($uploadAccepted.Success -and -not $uploadRejected.Success -and $uploadRejected.Error -eq 'No mapping') 'local spec linking requires Cloud to confirm the matching upload'
    Assert-Felix3 (Test-Felix3LocalSpecCodeMatch -RequirementId 'S-0001' -RelativeSpecPath $uploadBody.files[0].path) 'local spec linking accepts a matching requirement code'
    Assert-Felix3 (-not (Test-Felix3LocalSpecCodeMatch -RequirementId 'S-0002' -RelativeSpecPath $uploadBody.files[0].path)) 'local spec linking rejects a mismatched requirement code'
    $invalidUploadRejected = $false
    try { New-FelixSyncSpecUploadRequest -RelativePath '../outside.md' -Content 'unsafe' | Out-Null } catch { $invalidUploadRejected = $true }
    Assert-Felix3 $invalidUploadRejected 'local spec upload rejects paths outside specs/'

    Write-Output 'Felix 3 tests passed: four harness adapters, local and Cloud work-source lifecycles, streamed events/usage, native questions, plan approval/rejection, cancellation, Cloud privacy, in-memory retry, disk outbox persistence/retry, and resumable workflows.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

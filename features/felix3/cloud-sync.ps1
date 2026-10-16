Set-StrictMode -Version Latest

function global:Invoke-Felix3BestEffortSyncCall {
    param([scriptblock]$Call)
    $previous = $env:FELIX_SYNC_MAX_RETRIES
    try { $env:FELIX_SYNC_MAX_RETRIES = '1'; & $Call }
    finally { if ($null -eq $previous) { Remove-Item Env:FELIX_SYNC_MAX_RETRIES -ErrorAction SilentlyContinue } else { $env:FELIX_SYNC_MAX_RETRIES = $previous } }
}

function global:Resolve-Felix3CloudBaseUrl {
    param($Settings)
    if ($env:FELIX_SYNC_URL) { return [string]$env:FELIX_SYNC_URL }
    $configuredBaseUrl = Get-Felix3PropertyValue $Settings 'base_url'
    if ($configuredBaseUrl) { return [string]$configuredBaseUrl }
    return 'https://api.runfelix.io'
}

function global:Test-Felix3LocalSpecCodeMatch {
    param([string]$RequirementId, [string]$RelativeSpecPath)
    $requirementCode = [regex]::Match($RequirementId, '^S-\d{4}$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $pathCode = [regex]::Match([IO.Path]::GetFileNameWithoutExtension($RelativeSpecPath), '^S-\d{4}\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $requirementCode.Success -and $pathCode.Success -and $requirementCode.Value -ieq $pathCode.Value
}

function global:Initialize-Felix3CloudSync {
    param($Config, [string]$ProjectPath, [string]$RunId, [string]$RequirementId, [string]$SpecPath, [switch]$Resume)
    $settings = Get-Felix3PropertyValue $Config 'cloud_sync'
    if (-not $settings) { $settings = [pscustomobject]@{ enabled = $false; live_activity = $false; live_output = $false; artifacts = @(); include_phase_summaries = $true } }
    $configuredEnabled = Get-Felix3PropertyValue $settings 'enabled'
    $enabled = if ($env:FELIX_SYNC_ENABLED -eq 'false' -or $env:FELIX_SYNC_ENABLED -eq '0') { $false } elseif ($env:FELIX_SYNC_ENABLED -eq 'true' -or $env:FELIX_SYNC_ENABLED -eq '1') { $true } else { [bool]$configuredEnabled }
    if (-not $enabled) { return $null }
    $configuredApiKey = Get-Felix3PropertyValue $settings 'api_key'
    $configuredAgentKey = Get-Felix3PropertyValue $settings 'agent_key'
    $baseUrl = Resolve-Felix3CloudBaseUrl -Settings $settings
    $apiKey = if ($env:FELIX_SYNC_KEY) { $env:FELIX_SYNC_KEY } elseif ($configuredApiKey) { [string]$configuredApiKey } else { $null }
    $agentKey = if ($env:FELIX_SYNC_AGENT_KEY) { $env:FELIX_SYNC_AGENT_KEY } elseif ($configuredAgentKey) { [string]$configuredAgentKey } else { $null }
    if (-not $agentKey) {
        $agentsPath = Join-Path $ProjectPath '.felix\agents.json'
        if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
            try {
                $agentsDoc = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $expected = switch ([string]$Config.harness.provider) { 'claude-code' { @('claude','claude-code') } 'opencode' { @('opencode') } 'codex' { @('codex') } 'grok-build' { @('grok','grok-build') } }
                $agent = @($agentsDoc.agents | Where-Object { $_.provider -in $expected -or $_.adapter -in $expected } | Select-Object -First 1)[0]
                if ($agent.key) { $agentKey = [string]$agent.key }
            } catch { }
        }
    }
    if (-not $apiKey) { Write-Warning 'Felix 3 cloud sync is enabled but no API key is configured; continuing with local execution only.'; return $null }
    if (-not $agentKey) { Write-Warning 'Felix 3 cloud sync is enabled but no agent key is configured; continuing with local execution only.'; return $null }
    $sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $pluginCandidates = @(
        (Join-Path $PSScriptRoot '..\plugins\sync-http\http-client.ps1'),
        (Join-Path $sourceRoot '.felix\plugins\sync-http\http-client.ps1')
    )
    if ($env:FELIX_INSTALL_DIR) {
        $pluginCandidates += Join-Path $env:FELIX_INSTALL_DIR 'plugins\sync-http\http-client.ps1'
        $pluginCandidates += Join-Path (Split-Path -Parent $env:FELIX_INSTALL_DIR) 'plugins\sync-http\http-client.ps1'
    }
    $pluginPath = $pluginCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $pluginPath) { Write-Warning "Felix HTTP sync transport is unavailable; checked $($pluginCandidates -join ', '); continuing with local execution only."; return $null }
    $interfaceCandidates = @(
        (Join-Path $PSScriptRoot '..\core\sync-interface.ps1'),
        (Join-Path $sourceRoot '.felix\core\sync-interface.ps1')
    )
    if ($env:FELIX_INSTALL_DIR) {
        $interfaceCandidates += Join-Path $env:FELIX_INSTALL_DIR 'core\sync-interface.ps1'
        $interfaceCandidates += Join-Path (Split-Path -Parent $env:FELIX_INSTALL_DIR) 'core\sync-interface.ps1'
    }
    $interfacePath = $interfaceCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $interfacePath) { Write-Warning "Felix HTTP sync interface is unavailable; checked $($interfaceCandidates -join ', '); continuing with local execution only."; return $null }
    $loadedFlag = Get-Variable -Name Felix3HttpSyncLoaded -Scope Global -ErrorAction SilentlyContinue
    if (-not $loadedFlag -or -not $loadedFlag.Value) {
        . $interfacePath
        . $pluginPath
        $global:Felix3HttpSyncLoaded = $true
    }
    $felix3Dir = Join-Path $ProjectPath '.felix3'
    New-Item -ItemType Directory -Path $felix3Dir -Force | Out-Null
    $client = [HttpSync]::new(@{ base_url = $baseUrl; api_key = $apiKey }, $felix3Dir)
    $workSourceProvider = [string](Get-Felix3PropertyValue (Get-Felix3PropertyValue $Config 'work_source') 'provider')
    if (-not $Resume -and $workSourceProvider -ne 'felix-cloud' -and (Get-Felix3PropertyValue $settings 'upload_local_spec') -eq $true) {
        try {
            $relativeSpecPath = (Get-Felix3RelativePath -BasePath $ProjectPath -TargetPath $SpecPath).Replace('\','/')
            if ($relativeSpecPath -notmatch '^specs/(?!.*\.\.)[^:]+\.md$') {
                Write-Warning 'Felix 3 local spec upload is enabled, but the selected spec is not a Markdown file under the project specs/ directory; continuing with local execution only.'
                return $null
            }
            if (-not (Test-Felix3LocalSpecCodeMatch -RequirementId $RequirementId -RelativeSpecPath $relativeSpecPath)) {
                Write-Warning 'Felix 3 local spec upload requires the spec filename and requirement ID to share the same S-0001-style code; continuing with local execution only.'
                return $null
            }
            $specContent = Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8
            $upload = $client.UploadSpec($relativeSpecPath, $specContent)
            if (-not $upload.Success) {
                Write-Warning "Felix 3 could not link the local spec to Cloud: $($upload.Error). Continuing with local execution only."
                return $null
            }
        }
        catch {
            Write-Warning "Felix 3 could not upload the local spec to Cloud: $($_.Exception.Message). Continuing with local execution only."
            return $null
        }
    }
    $gitUrl = $null
    try { $remote = git -C $ProjectPath config --get remote.origin.url 2>$null; if ($LASTEXITCODE -eq 0 -and $remote) { $gitUrl = ([string]$remote).Trim() } } catch { }
    $liveOutput = (Get-Felix3PropertyValue $settings 'live_output') -eq $true
    $liveActivity = (Get-Felix3PropertyValue $settings 'live_activity') -eq $true
    $liveEnabled = $liveActivity -or $liveOutput
    $metadata = @{
        requirement_id = $RequirementId
        agent_key = $agentKey
        metadata = @{ felix3_run_id = $RunId; live_stream_enabled = $liveEnabled }
    }
    # This durable boolean lets Cloud avoid opening a viewer-only SSE channel
    # for runs whose owner did not opt into live activity. No stream content is
    # stored in run metadata.
    if ($gitUrl) { $metadata.git_url = $gitUrl }
    $statePath = Join-Path $felix3Dir ("cloud-$RunId.json")
    if ($Resume -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        $cloudState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $cloudRunId = [string]$cloudState.cloud_run_id
    }
    else {
        try { $cloudRunId = Invoke-Felix3BestEffortSyncCall { $client.StartRun($metadata) } }
        catch { Write-Warning "Felix 3 cloud sync could not start; continuing with local execution only. $($_.Exception.Message)"; return $null }
        if (-not $cloudRunId) { Write-Warning 'Felix 3 cloud sync did not return a run ID; continuing with local execution only.'; return $null }
    }
    $state = [ordered]@{ schema = 'felix3-cloud-sync-v1'; enabled = $true; local_run_id = $RunId; cloud_run_id = $cloudRunId; status = 'active'; last_event_seq = 0; updated_at = [DateTime]::UtcNow.ToString('o') }
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
    try { Invoke-Felix3BestEffortSyncCall { $client.Flush() } | Out-Null } catch { }
    if ($liveEnabled) {
        $configured = Send-Felix3LivePipeMessage @{
            type = 'configure'; enabled = $true; include_text = $liveOutput; base_url = $baseUrl
            cloud_run_id = [string]$cloudRunId
        }
        if (-not $configured) { Write-Warning 'Felix live Cloud activity is unavailable in this invocation; continuing with local execution and metadata sync.' }
    }
    return [pscustomobject]@{ Client = $client; CloudRunId = $cloudRunId; RunId = $RunId; RequirementId = $RequirementId; ProjectPath = $ProjectPath; StatePath = $statePath; Settings = $settings; LiveEnabled = $liveEnabled; LiveOutput = $liveOutput; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow }
}

function global:Add-Felix3CloudEvent {
    param($Cloud, $Event)
    if (-not $Cloud) { return }
    $liveEnabled = (Get-Felix3PropertyValue $Cloud 'LiveEnabled') -eq $true
    if ($liveEnabled) {
        $liveProjection = ConvertTo-Felix3LiveProjection -Event $Event
        if ($liveProjection) { Send-Felix3LivePipeMessage @{ type = 'event'; event = $liveProjection } | Out-Null }
    }
    if ($Event.kind -in @('output.delta','assistant.message','harness.event','harness.stderr','harness.process.started','harness.process.exited','validation.output')) { return }
    $eventPayload = if ($Event.payload) { $Event.payload } else { @{} }
    # Cloud events are durable. Keep them to a small, non-content-bearing
    # activity record; full provider output and run artifacts remain on disk.
    # Live, transient activity belongs on a separate non-persisting transport.
    $summary = switch ([string]$Event.kind) {
        'run.started' { 'Run started.' }
        'run.resumed' { 'Run resumed.' }
        'phase.started' { 'Phase started.' }
        'phase.completed' { 'Phase completed.' }
        'phase.failed' { 'Phase failed.' }
        'validation.completed' { 'Validation completed.' }
        'turn.completed' { 'Agent turn completed.' }
        'tool.started' { 'Tool started.' }
        'tool.completed' { 'Tool completed.' }
        'question.requested' { 'Human input requested.' }
        'question.answered' { 'Human input recorded.' }
        'plan.approval_requested' { 'Plan is waiting for human approval.' }
        'plan.approved' { 'Plan approved by human.' }
        'plan.rejected' { 'Plan rejected by human.' }
        'run.completed' { 'Run completed.' }
        'run.blocked' { 'Run is blocked.' }
        'run.interrupted' { 'Run was interrupted.' }
        default { 'Run activity.' }
    }
    $payload = @{
        event_id = $Event.event_id; local_run_id = $Event.run_id; sequence = $Event.seq
        phase = $Event.phase; summary = $summary
    }
    if ($Event.phase -in @('exploring','planning','building','validating','reviewing')) { $payload.phase = [string]$Event.phase }
    $toolName = Get-Felix3PropertyValue $eventPayload 'tool'
    if ($toolName -and [string]$toolName -match '^[A-Za-z0-9_.-]{1,80}$') { $payload.tool = [string]$toolName }
    $status = Get-Felix3PropertyValue $eventPayload 'status'
    if ($status -in @('started','completed','failed','blocked','interrupted','approved','rejected','waiting')) { $payload.status = [string]$status }
    $level = if ($Event.kind -match 'failed|error|blocked|interrupted') { 'error' } else { 'info' }
    $Cloud.Buffer.Add(@{ type = "felix3.$($Event.kind)"; timestamp = $Event.timestamp; level = $level; message = $summary; run_id = $Cloud.CloudRunId; data = $payload }) | Out-Null
    if ($Cloud.Buffer.Count -ge 15 -or $Event.kind -in @('phase.started','phase.completed','phase.failed','question.requested','plan.approval_requested','plan.approved','plan.rejected','run.completed','run.blocked')) {
        Send-Felix3CloudEvents -Cloud $Cloud
    }
}

function global:Send-Felix3CloudEvents {
    param($Cloud)
    if (-not $Cloud -or $Cloud.Buffer.Count -eq 0) { return }
    $batch = @($Cloud.Buffer.ToArray())
    $Cloud.Buffer.Clear()
    try {
        Invoke-Felix3BestEffortSyncCall { $Cloud.Client.AppendEvents($Cloud.CloudRunId, $batch) }
        $Cloud.LastFlush = [DateTime]::UtcNow
        $meta = Get-Content -LiteralPath $Cloud.StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $meta.last_event_seq += $batch.Count
        $meta.updated_at = [DateTime]::UtcNow.ToString('o')
        $meta | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Cloud.StatePath -Encoding UTF8
    }
    catch {
        foreach ($event in $batch) { $Cloud.Buffer.Add($event) | Out-Null }
    }
}

function global:Complete-Felix3CloudSync {
    param($Cloud, [string]$Status, [string]$RunDirectory)
    if (-not $Cloud) { return }
    Send-Felix3CloudEvents -Cloud $Cloud
    Invoke-Felix3BestEffortSyncCall { $Cloud.Client.FinishRun($Cloud.CloudRunId, @{ status = $Status; completed_at = [DateTime]::UtcNow.ToString('o'); local_run_id = $Cloud.RunId }) }
    $artifactList = if ($Cloud.Settings.PSObject.Properties['artifacts']) { @($Cloud.Settings.artifacts) } else { @() }
    foreach ($relativePath in $artifactList) {
        if (-not $relativePath) { continue }
        if ([System.IO.Path]::IsPathRooted([string]$relativePath) -or ([string]$relativePath -split '[\\/]') -contains '..') { continue }
        $path = Join-Path $RunDirectory ([string]$relativePath)
        if (Test-Path -LiteralPath $path -PathType Leaf) { $Cloud.Client.UploadArtifact($Cloud.CloudRunId, ([string]$relativePath).Replace('\','/'), $path) }
    }
    try { Invoke-Felix3BestEffortSyncCall { $Cloud.Client.Flush() } | Out-Null } catch { }
    $meta = Get-Content -LiteralPath $Cloud.StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $meta.status = $Status; $meta.updated_at = [DateTime]::UtcNow.ToString('o')
    $meta | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Cloud.StatePath -Encoding UTF8
    if ((Get-Felix3PropertyValue $Cloud 'LiveEnabled') -eq $true) { Send-Felix3LivePipeMessage @{ type = 'close' } | Out-Null }
}

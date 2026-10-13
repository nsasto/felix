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
    return 'https://runfelix.io'
}

function global:Initialize-Felix3CloudSync {
    param($Config, [string]$ProjectPath, [string]$RunId, [string]$RequirementId, [switch]$Resume)
    $settings = Get-Felix3PropertyValue $Config 'cloud_sync'
    if (-not $settings) { $settings = [pscustomobject]@{ enabled = $false; artifacts = @(); include_phase_summaries = $true } }
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
                $expected = switch ([string]$Config.harness.provider) { 'claude-code' { @('claude','claude-code') } 'opencode' { @('opencode') } 'codex' { @('codex') } }
                $agent = @($agentsDoc.agents | Where-Object { $_.provider -in $expected -or $_.adapter -in $expected } | Select-Object -First 1)[0]
                if ($agent.key) { $agentKey = [string]$agent.key }
            } catch { }
        }
    }
    if (-not $apiKey) { Write-Warning 'Felix 3 cloud sync is enabled but no API key is configured; continuing with local execution only.'; return $null }
    if (-not $agentKey) { Write-Warning 'Felix 3 cloud sync is enabled but no agent key is configured; continuing with local execution only.'; return $null }
    $sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $pluginPath = Join-Path $sourceRoot '.felix\plugins\sync-http\http-client.ps1'
    if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) { Write-Warning "Felix HTTP sync transport is unavailable at $pluginPath; continuing with local execution only."; return $null }
    $loadedFlag = Get-Variable -Name Felix3HttpSyncLoaded -Scope Global -ErrorAction SilentlyContinue
    if (-not $loadedFlag -or -not $loadedFlag.Value) { . $pluginPath; $global:Felix3HttpSyncLoaded = $true }
    $felix3Dir = Join-Path $ProjectPath '.felix3'
    New-Item -ItemType Directory -Path $felix3Dir -Force | Out-Null
    $client = [HttpSync]::new(@{ base_url = $baseUrl; api_key = $apiKey }, $felix3Dir)
    $gitUrl = $null
    try { $remote = git -C $ProjectPath config --get remote.origin.url 2>$null; if ($LASTEXITCODE -eq 0 -and $remote) { $gitUrl = ([string]$remote).Trim() } } catch { }
    $metadata = @{ requirement_id = $RequirementId; agent_key = $agentKey; felix3_run_id = $RunId }
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
    return [pscustomobject]@{ Client = $client; CloudRunId = $cloudRunId; RunId = $RunId; RequirementId = $RequirementId; ProjectPath = $ProjectPath; StatePath = $statePath; Settings = $settings; Buffer = [System.Collections.ArrayList]::new(); LastFlush = [DateTime]::UtcNow }
}

function global:Add-Felix3CloudEvent {
    param($Cloud, $Event)
    if (-not $Cloud) { return }
    if ($Event.kind -in @('output.delta','assistant.message','harness.event','harness.stderr','harness.process.started','harness.process.exited','validation.output')) { return }
    $eventPayload = if ($Event.payload) { $Event.payload } else { @{} }
    $allowedSummary = @('run.started','run.resumed','phase.started','phase.completed','phase.failed','validation.completed','turn.completed','tool.started','tool.completed','question.requested','question.answered','plan.approval_requested','plan.approved','plan.rejected','run.completed','run.blocked','run.interrupted')
    $summary = if ($Event.kind -eq 'question.requested') { 'Human input requested.' } elseif ($Event.kind -eq 'question.answered') { 'Human input recorded.' } elseif ($Event.kind -eq 'plan.approval_requested') { 'Plan is waiting for human approval.' } elseif ($Event.kind -eq 'plan.approved') { 'Plan approved by human.' } elseif ($Event.kind -eq 'plan.rejected') { 'Plan rejected by human.' } elseif ($Event.kind -eq 'phase.failed') { 'Harness phase failed.' } elseif ($Event.kind -eq 'run.blocked') { 'Run is blocked.' } elseif ($Event.kind -eq 'run.interrupted') { 'Run was interrupted.' } elseif ($Event.kind -in $allowedSummary -and $Cloud.Settings.include_phase_summaries -ne $false) { Protect-Felix3Text -Text $Event.summary -MaxLength 300 } else { $Event.kind }
    $payload = @{
        event_id = $Event.event_id; local_run_id = $Event.run_id; sequence = $Event.seq
        phase = $Event.phase; harness = $Event.harness; summary = $summary
        provider_event = Get-Felix3PropertyValue $eventPayload 'provider_event'
    }
    if (Get-Felix3PropertyValue $eventPayload 'session_id') { $payload.session_id = Get-Felix3PropertyValue $eventPayload 'session_id' }
    if (Get-Felix3PropertyValue $eventPayload 'tool') { $payload.tool = Get-Felix3PropertyValue $eventPayload 'tool' }
    if (Get-Felix3PropertyValue $eventPayload 'usage') { $payload.usage = Get-Felix3PropertyValue $eventPayload 'usage' }
    if ($null -ne (Get-Felix3PropertyValue $eventPayload 'cost_usd')) { $payload.cost_usd = Get-Felix3PropertyValue $eventPayload 'cost_usd' }
    if (Get-Felix3PropertyValue $eventPayload 'model') { $payload.model = Get-Felix3PropertyValue $eventPayload 'model' }
    if (Get-Felix3PropertyValue $eventPayload 'status') { $payload.status = Get-Felix3PropertyValue $eventPayload 'status' }
    if ($Event.kind -eq 'question.requested' -and $Cloud.Settings.include_question_text -eq $true) {
        $question = ConvertFrom-Felix3QuestionData -Data (Get-Felix3PropertyValue $eventPayload 'question')
        if ($question) { $payload.question = Protect-Felix3Text -Text $question.question -MaxLength 1000 }
    }
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
}

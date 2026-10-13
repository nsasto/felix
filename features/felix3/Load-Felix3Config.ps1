Set-StrictMode -Version Latest

function Import-Felix3Config {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Felix 3 config not found: $Path. Copy felix3.config.example.json and edit it for this project."
    }

    try {
        $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Felix 3 config is not valid JSON: $($_.Exception.Message)"
    }

    if ($config.schema_version -ne 1) {
        throw "Unsupported Felix 3 config schema_version '$($config.schema_version)'; expected 1."
    }
    $workSourceProvider = if ($config.PSObject.Properties['work_source'] -and $config.work_source -and $config.work_source.PSObject.Properties['provider']) { [string]$config.work_source.provider } else { 'manual-spec' }
    if ($workSourceProvider -notin @('manual-spec', 'felix-cloud')) {
        throw "Unsupported Felix 3 work source '$workSourceProvider'; supported work sources are 'manual-spec' and 'felix-cloud'."
    }
    if ($workSourceProvider -eq 'felix-cloud') {
        $cloudWorkSource = if ($config.work_source.PSObject.Properties['cloud']) { $config.work_source.cloud } else { $null }
        if (-not $cloudWorkSource -or [string]::IsNullOrWhiteSpace([string]$cloudWorkSource.agent_id)) {
            throw 'work_source.cloud.agent_id is required for the Felix Cloud work source.'
        }
        $agentUuid = [guid]::Empty
        if (-not [guid]::TryParse([string]$cloudWorkSource.agent_id, [ref]$agentUuid)) { throw 'work_source.cloud.agent_id must be a Cloud agent UUID.' }
    }
    $provider = [string]$config.harness.provider
    if ($provider -notin @('claude-code', 'opencode', 'codex')) {
        throw "Unsupported Felix 3 harness '$provider'; supported harnesses are 'claude-code', 'opencode', and 'codex'."
    }
    $harnessConfig = $config.harness.$provider
    if (-not $harnessConfig) {
        throw "harness.$provider configuration is required when harness.provider is '$provider'."
    }
    if (-not $harnessConfig.executable) {
        throw "harness.$provider.executable must be set."
    }
    if (-not $config.artifacts.runs_dir) {
        throw 'artifacts.runs_dir must be set.'
    }
    if ($config.artifacts.PSObject.Properties['local_retention_days'] -and [int]$config.artifacts.local_retention_days -lt 0) {
        throw 'artifacts.local_retention_days must be zero (disabled) or a positive number.'
    }

    foreach ($key in @('planning', 'building', 'reviewing')) {
        $phase = $harnessConfig.phases.$key
        if ($provider -eq 'claude-code' -and $phase.max_turns -and ([int]$phase.max_turns -lt 1 -or [int]$phase.max_turns -gt 500)) {
            throw "harness.claude-code.phases.$key.max_turns must be between 1 and 500."
        }
        $configuredSessionPolicy = if ($phase.PSObject.Properties['session_policy']) { [string]$phase.session_policy } else { $null }
        if ($configuredSessionPolicy -and $configuredSessionPolicy -notin @('fresh', 'resume')) {
            throw "harness.$provider.phases.$key.session_policy must be 'fresh' or 'resume'."
        }
        if ($provider -eq 'codex') {
            $sandbox = if ($phase.PSObject.Properties['sandbox']) { $phase.sandbox } else { $harnessConfig.sandbox }
            if ($sandbox -and $sandbox -notin @('read-only', 'workspace-write', 'danger-full-access')) {
                throw "harness.codex.phases.$key.sandbox must be read-only, workspace-write, or danger-full-access."
            }
            $baseWindowsSandbox = if ($harnessConfig.PSObject.Properties['windows_sandbox']) { $harnessConfig.windows_sandbox } else { $null }
            $windowsSandbox = if ($phase.PSObject.Properties['windows_sandbox']) { $phase.windows_sandbox } else { $baseWindowsSandbox }
            if ($windowsSandbox -and $windowsSandbox -notin @('elevated', 'unelevated')) {
                throw "harness.codex.phases.$key.windows_sandbox must be elevated or unelevated."
            }
            $approval = if ($phase.PSObject.Properties['approval_policy']) { $phase.approval_policy } else { $harnessConfig.approval_policy }
            if ($approval -and $approval -notin @('on-request', 'never')) {
                throw "harness.codex.phases.$key.approval_policy must be on-request or never."
            }
        }
    }

    if ($config.workflow.max_build_attempts -lt 1) { throw 'workflow.max_build_attempts must be at least 1.' }
    if ($config.workflow.max_review_cycles -lt 1) { throw 'workflow.max_review_cycles must be at least 1.' }
    return $config
}

function Get-Felix3PhaseConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][ValidateSet('planning', 'building', 'reviewing')][string]$Phase
    )

    $provider = [string]$Config.harness.provider
    $base = $Config.harness.$provider
    $phaseConfig = $base.phases.$Phase
    $phaseModel = if ($phaseConfig.PSObject.Properties['model']) { $phaseConfig.model } else { $null }
    $baseModel = if ($base.PSObject.Properties['model']) { $base.model } else { $null }
    $phasePermissionMode = if ($phaseConfig.PSObject.Properties['permission_mode']) { $phaseConfig.permission_mode } else { $null }
    $basePermissionMode = if ($base.PSObject.Properties['permission_mode']) { $base.permission_mode } else { $null }
    $phaseMaxTurns = if ($phaseConfig.PSObject.Properties['max_turns']) { $phaseConfig.max_turns } else { $null }
    $baseMaxTurns = if ($base.PSObject.Properties['max_turns']) { $base.max_turns } else { $null }
    $phaseAgent = if ($phaseConfig.PSObject.Properties['agent']) { $phaseConfig.agent } else { $null }
    $baseAgent = if ($base.PSObject.Properties['agent']) { $base.agent } else { $null }
    $phaseAutoApprove = if ($phaseConfig.PSObject.Properties['auto_approve']) { $phaseConfig.auto_approve } else { $null }
    $baseAutoApprove = if ($base.PSObject.Properties['auto_approve']) { $base.auto_approve } else { $null }
    $phaseSessionPolicy = if ($phaseConfig.PSObject.Properties['session_policy']) { $phaseConfig.session_policy } else { $null }
    $baseSessionPolicy = if ($base.PSObject.Properties['session_policy']) { $base.session_policy } else { $null }
    return [pscustomobject]@{
        provider = $provider
        executable = [string]$base.executable
        model = if ($phaseModel) { [string]$phaseModel } else { [string]$baseModel }
        permission_mode = if ($phasePermissionMode) { [string]$phasePermissionMode } elseif ($basePermissionMode) { [string]$basePermissionMode } else { $null }
        max_turns = if ($phaseMaxTurns) { [int]$phaseMaxTurns } elseif ($baseMaxTurns) { [int]$baseMaxTurns } else { $null }
        agent = if ($phaseAgent) { [string]$phaseAgent } elseif ($baseAgent) { [string]$baseAgent } else { $null }
        auto_approve = if ($null -ne $phaseAutoApprove) { [bool]$phaseAutoApprove } elseif ($null -ne $baseAutoApprove) { [bool]$baseAutoApprove } else { $false }
        session_policy = if ($phaseSessionPolicy) { [string]$phaseSessionPolicy } elseif ($baseSessionPolicy) { [string]$baseSessionPolicy } else { 'fresh' }
        sandbox = if ($phaseConfig.PSObject.Properties['sandbox'] -and $phaseConfig.sandbox) { [string]$phaseConfig.sandbox } elseif ($base.PSObject.Properties['sandbox'] -and $base.sandbox) { [string]$base.sandbox } else { 'read-only' }
        approval_policy = if ($phaseConfig.PSObject.Properties['approval_policy'] -and $phaseConfig.approval_policy) { [string]$phaseConfig.approval_policy } elseif ($base.PSObject.Properties['approval_policy'] -and $base.approval_policy) { [string]$base.approval_policy } else { 'on-request' }
        windows_sandbox = if ($phaseConfig.PSObject.Properties['windows_sandbox'] -and $phaseConfig.windows_sandbox) { [string]$phaseConfig.windows_sandbox } elseif ($base.PSObject.Properties['windows_sandbox'] -and $base.windows_sandbox) { [string]$base.windows_sandbox } else { $null }
    }
}

function Resolve-Felix3Path {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

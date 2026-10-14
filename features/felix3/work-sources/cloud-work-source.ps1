Set-StrictMode -Version Latest

function Write-Felix3CloudClaimRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Record)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $backup = "$Path.$([guid]::NewGuid().ToString('N')).bak"
    try {
        $json = ConvertTo-Json -InputObject $Record -Depth 30
        [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
        if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($temporary, $Path, $backup); Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
        else { [System.IO.File]::Move($temporary, $Path) }
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    }
}

function New-Felix3CloudWorkSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][string]$ProjectPath,
        [scriptblock]$Request
    )
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'Felix Cloud work source requires an API key (FELIX_SYNC_KEY or cloud_sync.api_key).' }
    if ([string]::IsNullOrWhiteSpace($AgentId)) { throw 'Felix Cloud work source requires an explicit Cloud agent UUID in work_source.cloud.agent_id.' }
    $parsedAgentId = [guid]::Empty
    if (-not [guid]::TryParse($AgentId, [ref]$parsedAgentId)) { throw 'work_source.cloud.agent_id must be the UUID assigned to this Felix agent in Cloud.' }
    return [pscustomobject]@{
        BaseUrl = $BaseUrl.TrimEnd('/')
        ApiKey = $ApiKey
        AgentId = $parsedAgentId.ToString()
        ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
        Request = $Request
    }
}

function Invoke-Felix3CloudWorkRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method, [Parameter(Mandatory)][string]$Path, $Body)
    $uri = $Source.BaseUrl + $Path
    $headers = @{ Authorization = "Bearer $($Source.ApiKey)"; Accept = 'application/json' }
    if ($Source.Request) { return & $Source.Request $Method $uri $headers $Body }
    if ($Method -eq 'GET') {
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
    }
    $json = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $json -ErrorAction Stop
}

function Get-Felix3CloudSpecContent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$SpecPath)
    if (-not $SpecPath.StartsWith('specs/', [System.StringComparison]::OrdinalIgnoreCase) -or ($SpecPath -split '[\\/]') -contains '..' -or [System.IO.Path]::IsPathRooted($SpecPath)) {
        throw "Cloud returned an unsafe spec path '$SpecPath'; expected a project spec path under specs/."
    }
    $encodedPath = [System.Uri]::EscapeDataString($SpecPath)
    $content = Invoke-Felix3CloudWorkRequest -Source $Source -Method GET -Path "/api/sync/specs/file?path=$encodedPath"
    if ($content -is [System.Net.HttpWebResponse]) { throw 'Cloud spec response did not contain text content.' }
    if ($null -eq $content -or [string]::IsNullOrWhiteSpace([string]$content)) { throw "Cloud spec '$SpecPath' was empty or unavailable." }
    return [string]$content
}

function ClaimNext-Felix3CloudWorkItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Source)
    $agent = [System.Uri]::EscapeDataString([string]$Source.AgentId)
    $claim = Invoke-Felix3CloudWorkRequest -Source $Source -Method GET -Path "/api/sync/work/next?agent_id=$agent"
    if ($null -eq $claim) { return $null }
    $id = [string](Get-Felix3PropertyValue $claim 'code')
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'Felix Cloud work/next response is missing code.' }
    try {
    $title = [string](Get-Felix3PropertyValue $claim 'title')
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $id }
    $remoteSpecPath = [string](Get-Felix3PropertyValue $claim 'spec_path')
    if ([string]::IsNullOrWhiteSpace($remoteSpecPath)) { $remoteSpecPath = "specs/$id.md" }
    $specText = Get-Felix3CloudSpecContent -Source $Source -SpecPath $remoteSpecPath
    $digest = Get-Felix3Sha256Hex -Text $specText
    $itemDirectoryName = Get-Felix3Sha256Hex -Text $id
    $itemDirectory = Join-Path (Join-Path (Join-Path $Source.ProjectPath '.felix3') 'work-items') $itemDirectoryName
    New-Item -ItemType Directory -Path $itemDirectory -Force | Out-Null
    $localSpecPath = Join-Path $itemDirectory 'spec.md'
    [System.IO.File]::WriteAllText($localSpecPath, $specText, [System.Text.UTF8Encoding]::new($false))
    $projectPrefix = $Source.ProjectPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $relativeSpecPath = $localSpecPath.Substring($projectPrefix.Length).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    $dependencies = @(Get-Felix3PropertyValue $claim 'depends_on')
    $item = [pscustomobject][ordered]@{
        schema = 'felix3-work-item-v1'
        id = $id.Trim()
        title = $title.Trim()
        source = [pscustomobject][ordered]@{ provider = 'felix-cloud'; id = $id.Trim() }
        priority = Get-Felix3PropertyValue $claim 'priority'
        depends_on = @($dependencies | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        spec_path = $relativeSpecPath
        spec_sha256 = $digest
    }
    Assert-Felix3WorkItemContract -WorkItem $item -SpecText $specText | Out-Null
    return [pscustomobject]@{ WorkItem = $item; SpecPath = $localSpecPath; SpecText = $specText; RemoteSpecPath = $remoteSpecPath }
    }
    catch {
        $claimError = $_
        try { Release-Felix3CloudWorkItem -Source $Source -RequirementId $id | Out-Null }
        catch { Write-Warning "Felix could not release Cloud claim '$id' after spec materialization failed." }
        throw $claimError
    }
}

function Start-Felix3CloudWorkItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$RequirementId)
    try { return Invoke-Felix3CloudWorkRequest -Source $Source -Method POST -Path '/api/sync/work/start' -Body @{ code = $RequirementId } }
    catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        if ($statusCode -eq 409) { return @{ status = 'already-started'; code = $RequirementId } }
        throw
    }
}

function Complete-Felix3CloudWorkItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$RequirementId)
    return Invoke-Felix3CloudWorkRequest -Source $Source -Method POST -Path '/api/sync/work/complete' -Body @{ code = $RequirementId }
}

function Release-Felix3CloudWorkItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$RequirementId)
    return Invoke-Felix3CloudWorkRequest -Source $Source -Method POST -Path '/api/sync/work/release' -Body @{ code = $RequirementId }
}

function Invoke-Felix3CloudWorkCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$ConfigPath = '.felix3/config.json',
        [string]$Answer,
        [scriptblock]$Request
    )
    $project = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $config = Import-Felix3Config -Path (Resolve-Felix3Path -Path $ConfigPath -BasePath $project)
    if ([string]$config.work_source.provider -ne 'felix-cloud') { throw "work_source.provider must be 'felix-cloud' to claim Cloud work." }
    $settings = Get-Felix3PropertyValue $config 'cloud_sync'
    $cloudWork = Get-Felix3PropertyValue $config.work_source 'cloud'
    $apiKey = if ($env:FELIX_SYNC_KEY) { $env:FELIX_SYNC_KEY } else { [string](Get-Felix3PropertyValue $settings 'api_key') }
    $agentId = if ($env:FELIX_SYNC_AGENT_ID) { $env:FELIX_SYNC_AGENT_ID } else { [string](Get-Felix3PropertyValue $cloudWork 'agent_id') }
    $source = New-Felix3CloudWorkSource -BaseUrl (Resolve-Felix3CloudBaseUrl -Settings $settings) -ApiKey $apiKey -AgentId $agentId -ProjectPath $project -Request $Request
    $claimPath = Join-Path (Join-Path (Join-Path $project '.felix3') 'work-source') 'cloud-claim.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $claimPath) -Force | Out-Null
    $cycleLockPath = Join-Path (Split-Path -Parent $claimPath) 'cloud-cycle.lock'
    try { $cycleLock = [System.IO.File]::Open($cycleLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
    catch { throw 'A Felix Cloud work cycle is already active for this project checkout.' }
    try {
    if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
        $savedClaim = Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($savedClaim.schema -ne 'felix3-cloud-claim-v1' -or -not $savedClaim.work_item -or [string]::IsNullOrWhiteSpace([string]$savedClaim.work_item.id)) {
            throw 'The saved Felix Cloud claim is malformed; preserve it for diagnosis instead of claiming new work.'
        }
        if ([string]$savedClaim.agent_id -ne [string]$source.AgentId) { throw 'The saved Cloud claim belongs to a different Cloud agent UUID.' }
        if ([string]::IsNullOrWhiteSpace([string]$savedClaim.run_id)) { throw 'The saved Cloud claim does not contain a run ID.' }
        if ((Get-Felix3PropertyValue $savedClaim 'recovery_required') -eq $true) { throw "Cloud work '$($savedClaim.work_item.id)' is already in progress, but this checkout has no confirmed resumable run. Preserve the claim record and recover the original checkout before retrying." }
        if ($savedClaim.pending_action -and $savedClaim.pending_action -notin @('complete','release')) { throw "Unknown pending Cloud claim action '$($savedClaim.pending_action)' in the local claim record." }
        if ($savedClaim.pending_action -eq 'complete') {
            Complete-Felix3CloudWorkItem -Source $source -RequirementId ([string]$savedClaim.work_item.id) | Out-Null
            Remove-Item -LiteralPath $claimPath -Force
        }
        elseif ($savedClaim.pending_action -eq 'release') {
            Release-Felix3CloudWorkItem -Source $source -RequirementId ([string]$savedClaim.work_item.id) | Out-Null
            Remove-Item -LiteralPath $claimPath -Force
        }
        elseif ($savedClaim.work_item) {
            if (-not $savedClaim.started) {
                Start-Felix3CloudWorkItem -Source $source -RequirementId ([string]$savedClaim.work_item.id) | Out-Null
                $savedClaim.started = $true
                Write-Felix3CloudClaimRecord -Path $claimPath -Record $savedClaim
            }
            if ([System.IO.Path]::IsPathRooted([string]$savedClaim.work_item.spec_path) -or ([string]$savedClaim.work_item.spec_path -split '[\\/]') -contains '..') { throw 'The saved Cloud work item contains an unsafe local spec path.' }
            $savedSpec = Join-Path $project ([string]$savedClaim.work_item.spec_path)
            $statePath = $null
            if ($savedClaim.run_id) {
                $runsRoot = Resolve-Felix3Path -Path ([string]$config.artifacts.runs_dir) -BasePath $project
                $savedRunDirectory = Resolve-Felix3RunDirectory -RunsRoot $runsRoot -RunId ([string]$savedClaim.run_id)
                $statePath = Join-Path $savedRunDirectory 'state.json'
            }
            if ($statePath -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
                $run = Resume-Felix3Task -ProjectPath $project -RunId ([string]$savedClaim.run_id) -Answer $Answer -ConfigPath $ConfigPath
            }
            else {
                $run = Invoke-Felix3Task -ProjectPath $project -RequirementId $savedClaim.work_item.id -Title $savedClaim.work_item.title -SpecPath $savedSpec -ConfigPath $ConfigPath -WorkItem $savedClaim.work_item -NewRunId $savedClaim.run_id
                $savedClaim.started = $true
            }
            if ($run.Status -eq 'completed') {
                $savedClaim.pending_action = 'complete'
                Write-Felix3CloudClaimRecord -Path $claimPath -Record $savedClaim
                Complete-Felix3CloudWorkItem -Source $source -RequirementId ([string]$savedClaim.work_item.id) | Out-Null
                Remove-Item -LiteralPath $claimPath -Force
            }
            elseif ($run.Status -eq 'blocked') {
                $savedClaim.pending_action = 'release'
                Write-Felix3CloudClaimRecord -Path $claimPath -Record $savedClaim
                Release-Felix3CloudWorkItem -Source $source -RequirementId ([string]$savedClaim.work_item.id) | Out-Null
                Remove-Item -LiteralPath $claimPath -Force
            }
            return [pscustomobject]@{ Status = $run.Status; WorkItem = $savedClaim.work_item; Run = $run }
        }
    }

    $claimed = ClaimNext-Felix3CloudWorkItem -Source $source
    if (-not $claimed) { return [pscustomobject]@{ Status = 'no-work'; WorkItem = $null; Run = $null } }
    $safeId = [regex]::Replace([string]$claimed.WorkItem.id, '[^A-Za-z0-9._-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = 'requirement' }
    $runId = '{0}-{1}-{2}' -f $safeId, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $record = [ordered]@{ schema = 'felix3-cloud-claim-v1'; agent_id = $source.AgentId; work_item = $claimed.WorkItem; remote_spec_path = $claimed.RemoteSpecPath; run_id = $runId; started = $false; pending_action = $null }
    try {
        Write-Felix3CloudClaimRecord -Path $claimPath -Record $record
        $startResult = Start-Felix3CloudWorkItem -Source $source -RequirementId $claimed.WorkItem.id
        if ([string]$startResult.status -eq 'already-started') {
            # A fresh local claim record means this checkout cannot prove it owns
            # the existing Cloud run. Do not start a duplicate run or release the
            # sticky claim, which may still be active on another machine.
            $record.recovery_required = $true
            Write-Felix3CloudClaimRecord -Path $claimPath -Record $record
            throw "Cloud work '$($claimed.WorkItem.id)' is already in progress for this agent, but no resumable local run was found. Recover the original checkout before retrying."
        }
        $record.started = $true
        Write-Felix3CloudClaimRecord -Path $claimPath -Record $record
        $run = Invoke-Felix3Task -ProjectPath $project -RequirementId $claimed.WorkItem.id -Title $claimed.WorkItem.title -SpecPath $claimed.SpecPath -ConfigPath $ConfigPath -WorkItem $claimed.WorkItem -NewRunId $runId
        if ($run.Status -eq 'completed') {
            $record.pending_action = 'complete'
            Write-Felix3CloudClaimRecord -Path $claimPath -Record $record
            Complete-Felix3CloudWorkItem -Source $source -RequirementId $claimed.WorkItem.id | Out-Null
            Remove-Item -LiteralPath $claimPath -Force
        }
        elseif ($run.Status -eq 'blocked') {
            $record.pending_action = 'release'
            Write-Felix3CloudClaimRecord -Path $claimPath -Record $record
            Release-Felix3CloudWorkItem -Source $source -RequirementId $claimed.WorkItem.id | Out-Null
            Remove-Item -LiteralPath $claimPath -Force
        }
        return [pscustomobject]@{ Status = $run.Status; WorkItem = $claimed.WorkItem; Run = $run }
    }
    catch {
        if (-not $record.started -and -not $record.recovery_required) {
            try { Release-Felix3CloudWorkItem -Source $source -RequirementId $claimed.WorkItem.id | Out-Null; Remove-Item -LiteralPath $claimPath -Force } catch { }
        }
        throw
    }
    }
    finally { $cycleLock.Dispose() }
}

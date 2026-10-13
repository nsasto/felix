Set-StrictMode -Version Latest

function Get-Felix3SpecMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -notmatch '(?s)^---\s*\r?\n(.*?)\r?\n---(?:\r?\n|$)') { return $null }
    $metadata = @{}
    foreach ($line in ($Matches[1] -split '\r?\n')) {
        if ($line -match '^([A-Za-z][A-Za-z0-9_-]*):\s*(.*?)\s*$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim().Trim('"', "'")
            if ($value -match '^\[(.*)\]$') { $value = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }) }
            $metadata[$key] = $value
        }
    }
    return $metadata
}

function Get-Felix3ReadyLocalSpec {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)]$Config)
    $workSource = $Config.work_source
    $specsDir = if ($workSource.PSObject.Properties['specs_dir'] -and $workSource.specs_dir) { [string]$workSource.specs_dir } else { 'specs' }
    $readyStatus = if ($workSource.PSObject.Properties['ready_status'] -and $workSource.ready_status) { [string]$workSource.ready_status } else { 'ready-for-agent' }
    $root = Resolve-Felix3Path -Path $specsDir -BasePath $ProjectPath
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    foreach ($file in (Get-ChildItem -LiteralPath $root -Filter '*.md' -File -Recurse | Sort-Object FullName)) {
        $meta = Get-Felix3SpecMetadata -Path $file.FullName
        if (-not $meta -or -not $meta.ContainsKey('status') -or [string]$meta['status'] -ine $readyStatus) { continue }
        $id = if ($meta.ContainsKey('id') -and $meta['id']) { [string]$meta['id'] } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
        $title = if ($meta.ContainsKey('title') -and $meta['title']) { [string]$meta['title'] } else { $id }
        $dependencies = if ($meta.ContainsKey('depends_on') -and $meta['depends_on']) { @($meta['depends_on']) } else { @() }
        $dependenciesReady = $true
        foreach ($dependency in $dependencies) {
            $dependencyFile = Get-ChildItem -LiteralPath $root -Filter '*.md' -File -Recurse | Where-Object {
                $dependencyMeta = Get-Felix3SpecMetadata -Path $_.FullName
                $dependencyMeta -and (($dependencyMeta.ContainsKey('id') -and [string]$dependencyMeta['id'] -eq [string]$dependency) -or ([IO.Path]::GetFileNameWithoutExtension($_.Name) -eq [string]$dependency))
            } | Select-Object -First 1
            $dependencyMetadata = if ($dependencyFile) { Get-Felix3SpecMetadata -Path $dependencyFile.FullName } else { $null }
            if (-not $dependencyMetadata -or -not $dependencyMetadata.ContainsKey('status') -or [string]$dependencyMetadata['status'] -notin @('completed','done')) { $dependenciesReady = $false; break }
        }
        if (-not $dependenciesReady) { continue }
        $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($ProjectPath), $file.FullName).Replace('\','/')
        return [pscustomobject]@{ Id = $id; Title = $title; SpecPath = $relative; FilePath = $file.FullName; Metadata = $meta }
    }
    return $null
}

function Set-Felix3LocalSpecStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Status)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -notmatch '(?s)^---\s*\r?\n(.*?)\r?\n---(?:\r?\n|$)') { throw "Ready spec must have YAML frontmatter to track status: $Path" }
    $frontmatter = [regex]::Replace($Matches[1], '(?m)^status:\s*.*$', "status: $Status")
    if ($frontmatter -notmatch '(?m)^status:') { $frontmatter += "`nstatus: $Status" }
    $updated = $text -replace '(?s)^---\s*\r?\n(.*?)\r?\n---(?:\r?\n|$)', "---`n$frontmatter`n---`n"
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, $updated, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Invoke-Felix3LocalWorkCycle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath, [string]$Answer, [string]$ConfigPath = '.felix3/config.json')
    $project = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $config = Import-Felix3Config -Path (Resolve-Felix3Path -Path $ConfigPath -BasePath $project)
    $stateDirectory = Join-Path (Join-Path $project '.felix3') 'work-source'
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $lockPath = Join-Path $stateDirectory 'local-cycle.lock'
    try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'A Felix 3 local work cycle is already active for this project checkout.' }
    $statePath = Join-Path $stateDirectory 'local-active.json'
    try {
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.schema -ne 'felix3-local-active-v1' -or [string]::IsNullOrWhiteSpace([string]$state.run_id)) { throw "Saved local work state is malformed: $statePath" }
            $run = Resume-Felix3Task -ProjectPath $project -RunId ([string]$state.run_id) -Answer $Answer -ConfigPath $ConfigPath
            $specPath = Join-Path $project ([string]$state.spec_path)
            if ($run.Status -eq 'completed') {
                Set-Felix3LocalSpecStatus -Path $specPath -Status 'completed'
                Remove-Item -LiteralPath $statePath -Force
            }
            elseif ($run.Status -eq 'blocked') {
                $readyStatus = if ($config.work_source.ready_status) { [string]$config.work_source.ready_status } else { 'ready-for-agent' }
                Set-Felix3LocalSpecStatus -Path $specPath -Status $readyStatus
                Remove-Item -LiteralPath $statePath -Force
            }
            return [pscustomobject]@{ Status = $run.Status; WorkItem = $state.work_item; Run = $run }
        }
        $item = Get-Felix3ReadyLocalSpec -ProjectPath $project -Config $config
        if (-not $item) { return [pscustomobject]@{ Status = 'no-work'; WorkItem = $null; Run = $null } }
        $safeId = [regex]::Replace($item.Id, '[^A-Za-z0-9._-]', '_')
        if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = 'requirement' }
        $runId = '{0}-{1}-{2}' -f $safeId, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
        Set-Felix3LocalSpecStatus -Path $item.FilePath -Status 'in-progress'
        $workItem = New-Felix3WorkItem -ProjectPath $project -Id $item.Id -Title $item.Title -SpecPath $item.SpecPath -DependsOn @($item.Metadata['depends_on']) -Priority ([string]$item.Metadata['priority'])
        [ordered]@{ schema='felix3-local-active-v1'; run_id=$runId; spec_path=$item.SpecPath; work_item=$workItem } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8
        $run = Invoke-Felix3Task -ProjectPath $project -RequirementId $item.Id -Title $item.Title -SpecPath $item.SpecPath -ConfigPath $ConfigPath -WorkItem $workItem -NewRunId $runId
        if ($run.Status -eq 'completed') {
            Set-Felix3LocalSpecStatus -Path $item.FilePath -Status 'completed'
            Remove-Item -LiteralPath $statePath -Force
        }
        elseif ($run.Status -eq 'blocked') {
            $readyStatus = if ($config.work_source.ready_status) { [string]$config.work_source.ready_status } else { 'ready-for-agent' }
            Set-Felix3LocalSpecStatus -Path $item.FilePath -Status $readyStatus
            Remove-Item -LiteralPath $statePath -Force
        }
        return [pscustomobject]@{ Status = $run.Status; WorkItem = $workItem; Run = $run }
    }
    finally { $lock.Dispose() }
}

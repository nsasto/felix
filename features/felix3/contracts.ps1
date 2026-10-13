Set-StrictMode -Version Latest

function Get-Felix3Sha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-Felix3HarnessResultContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][ValidateSet('claude-code','opencode','codex')][string]$ExpectedHarness,
        [Parameter(Mandatory)][ValidateSet('planning','building','reviewing')][string]$ExpectedPhase
    )

    $required = @('Harness','Succeeded','Interrupted','NeedsInput','ExitCode','Phase','SessionId','ResultText','Error','Usage','CostUsd','Turns','ResultPath','RawOutputPath','StderrPath','SessionPath')
    foreach ($name in $required) {
        if (-not $Result.PSObject.Properties[$name]) { throw "Felix 3 harness result is missing required field '$name'." }
    }
    if ([string]$Result.Harness -ne $ExpectedHarness) { throw "Felix 3 harness result identifies '$($Result.Harness)' but '$ExpectedHarness' was selected." }
    if ([string]$Result.Phase -ne $ExpectedPhase) { throw "Felix 3 harness result identifies phase '$($Result.Phase)' but '$ExpectedPhase' was requested." }
    if ($Result.Succeeded -isnot [bool] -or $Result.Interrupted -isnot [bool] -or $Result.NeedsInput -isnot [bool]) {
        throw 'Felix 3 harness result Succeeded, Interrupted, and NeedsInput fields must be booleans.'
    }
    if ($Result.Interrupted -and $Result.NeedsInput) { throw 'Felix 3 harness result cannot be interrupted and awaiting input at the same time.' }
    if ($Result.Succeeded -and ($Result.Interrupted -or $Result.NeedsInput)) { throw 'Felix 3 harness result cannot succeed while interrupted or awaiting input.' }
    if ($Result.Succeeded -and $null -ne $Result.ExitCode -and [int]$Result.ExitCode -ne 0) { throw 'Felix 3 successful harness result must have exit code 0 or null.' }
    if ($null -ne $Result.ExitCode -and $Result.ExitCode -isnot [int]) { throw 'Felix 3 harness result ExitCode must be an integer or null.' }
    return $Result
}

function Assert-Felix3WorkItemContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$WorkItem, [Parameter(Mandatory)][AllowEmptyString()][string]$SpecText)

    foreach ($name in @('schema','id','title','source','priority','depends_on','spec_path','spec_sha256')) {
        if (-not $WorkItem.PSObject.Properties[$name]) { throw "Felix 3 work item is missing required field '$name'." }
    }
    if ($WorkItem.schema -ne 'felix3-work-item-v1') { throw "Unsupported Felix 3 work item schema '$($WorkItem.schema)'." }
    if ([string]::IsNullOrWhiteSpace([string]$WorkItem.id)) { throw 'Felix 3 work item id must not be empty.' }
    if ([string]::IsNullOrWhiteSpace([string]$WorkItem.title)) { throw 'Felix 3 work item title must not be empty.' }
    if (-not $WorkItem.source -or [string]::IsNullOrWhiteSpace([string]$WorkItem.source.provider) -or [string]::IsNullOrWhiteSpace([string]$WorkItem.source.id)) { throw 'Felix 3 work item source must include provider and id.' }
    if ([string]::IsNullOrWhiteSpace([string]$WorkItem.spec_path) -or [System.IO.Path]::IsPathRooted([string]$WorkItem.spec_path) -or ([string]$WorkItem.spec_path -split '[\\/]') -contains '..') { throw 'Felix 3 work item spec_path must be a project-relative path without traversal segments.' }
    if ([string]$WorkItem.spec_sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Felix 3 work item spec_sha256 must be a lowercase SHA-256 digest.' }
    if ($WorkItem.depends_on -isnot [System.Array]) { throw 'Felix 3 work item depends_on must be an array.' }
    $actualHash = Get-Felix3Sha256Hex -Text $SpecText
    if ($actualHash -ne [string]$WorkItem.spec_sha256) { throw 'Felix 3 work item spec_sha256 does not match the supplied specification text.' }
    return $WorkItem
}

function Assert-Felix3RunEventContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Event)

    foreach ($name in @('schema','event_id','run_id','seq','timestamp','kind','phase','harness','summary','payload')) {
        if (-not $Event.PSObject.Properties[$name]) { throw "Felix 3 run event is missing required field '$name'." }
    }
    if ($Event.schema -ne 'felix3-event-v1') { throw "Unsupported Felix 3 run event schema '$($Event.schema)'." }
    if ([string]::IsNullOrWhiteSpace([string]$Event.run_id) -or [string]::IsNullOrWhiteSpace([string]$Event.kind)) { throw 'Felix 3 run event run_id and kind must not be empty.' }
    if ([long]$Event.seq -lt 1 -or [string]$Event.event_id -ne ("{0}:{1}" -f $Event.run_id, $Event.seq)) { throw 'Felix 3 run event id and sequence do not agree.' }
    $parsedTimestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Event.timestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedTimestamp)) { throw 'Felix 3 run event timestamp must be ISO-8601.' }
    return $Event
}

function New-Felix3WorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$Id,
        [string]$Title,
        [Parameter(Mandatory)][string]$SpecPath,
        [string]$SourceProvider = 'manual-spec',
        [string]$SourceId,
        [string]$Priority,
        [string[]]$DependsOn = @()
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { throw 'Felix 3 work item id must not be empty.' }
    if ([string]::IsNullOrWhiteSpace($SourceProvider)) { throw 'Felix 3 work item source provider must not be empty.' }
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $Id }
    if ([string]::IsNullOrWhiteSpace($SourceId)) { $SourceId = $Id }

    $project = [System.IO.Path]::GetFullPath($ProjectPath)
    $spec = if ([System.IO.Path]::IsPathRooted($SpecPath)) { [System.IO.Path]::GetFullPath($SpecPath) } else { [System.IO.Path]::GetFullPath((Join-Path $project $SpecPath)) }
    if (-not (Test-Path -LiteralPath $spec -PathType Leaf)) { throw "Felix 3 work item specification not found: $spec" }
    $projectPrefix = $project.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $spec.StartsWith($projectPrefix, $pathComparison)) {
        throw 'Felix 3 work item specification must be inside the project directory.'
    }
    $relativeSpec = $spec.Substring($projectPrefix.Length)
    $specText = [System.IO.File]::ReadAllText($spec, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($specText)) { throw 'Felix 3 work item specification must not be empty.' }
    $hash = Get-Felix3Sha256Hex -Text $specText
    $normalizedDependencies = @($DependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)

    $item = [pscustomobject][ordered]@{
        schema = 'felix3-work-item-v1'
        id = $Id.Trim()
        title = $Title.Trim()
        source = [pscustomobject][ordered]@{ provider = $SourceProvider.Trim(); id = $SourceId.Trim() }
        priority = if ([string]::IsNullOrWhiteSpace($Priority)) { $null } else { $Priority.Trim() }
        depends_on = $normalizedDependencies
        spec_path = $relativeSpec.Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        spec_sha256 = $hash
    }
    return Assert-Felix3WorkItemContract -WorkItem $item -SpecText $specText
}

function Assert-Felix3RunStateTransition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To)

    $allowed = @{
        'new' = @('planning')
        'planning' = @('building','awaiting-input','awaiting-plan-approval','interrupted','blocked')
        'building' = @('building','reviewing','awaiting-input','interrupted','blocked')
        'reviewing' = @('building','completed','awaiting-input','interrupted','blocked')
        'awaiting-input' = @('planning','building','reviewing','blocked')
        'awaiting-plan-approval' = @('building','blocked')
        'interrupted' = @('planning','building','reviewing','blocked')
        'stop-requested' = @('planning','building','reviewing','interrupted','blocked')
        'blocked' = @()
        'completed' = @()
    }
    if (-not $allowed.ContainsKey($From)) { throw "Unknown Felix 3 run state '$From'." }
    if ($From -ne $To -and $To -notin $allowed[$From]) { throw "Invalid Felix 3 run state transition '$From' -> '$To'." }
    return $true
}

function Set-Felix3RunStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Status)
    Assert-Felix3RunStateTransition -From ([string]$State.status) -To $Status | Out-Null
    $State.status = $Status
}

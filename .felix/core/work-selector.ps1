<#
.SYNOPSIS
Work selection for Felix loop - local or remote mode.

.DESCRIPTION
Provides Get-NextRequirement which dispatches to:
  - Local mode  (sync disabled): scan requirements.json for planned/in_progress
  - Remote mode (sync enabled):  call GET /api/sync/work/next for server-assigned work
#>

function Get-NextRequirement {
    <#
    .SYNOPSIS
    Returns the next requirement to process, or $null if none available.

    .PARAMETER RequirementsFilePath
    Path to local .felix/requirements.json

    .PARAMETER Config
    Felix config hashtable (from Get-FelixConfig). Used to detect remote mode.

    .PARAMETER AgentId
    Agent identifier to send in remote mode requests.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFilePath,

        [Parameter(Mandatory = $false)]
        $Config = $null,

        [Parameter(Mandatory = $false)]
        [string]$AgentId = ""
    )

    $syncEnabled = $false
    $baseUrl = ""
    $apiKey = ""

    # Resolve sync config - handle both hashtable and PSCustomObject
    if ($Config) {
        $syncSection = if ($Config -is [hashtable]) { $Config["sync"] } else { $Config.sync }
        if ($syncSection) {
            $enabledVal = if ($syncSection -is [hashtable]) { $syncSection["enabled"] } else { $syncSection.enabled }
            $syncEnabled = ($enabledVal -eq $true) -or ($enabledVal -eq "true")
            if ($syncEnabled) {
                $baseUrl = if ($syncSection -is [hashtable]) { $syncSection["base_url"] } else { $syncSection.base_url }
                $apiKey = if ($syncSection -is [hashtable]) { $syncSection["api_key"] } else { $syncSection.api_key }
            }
        }
    }

    # Also honour environment variable override
    if ($env:FELIX_SYNC_ENABLED -eq "true") {
        $syncEnabled = $true
        if ($env:FELIX_SYNC_URL) { $baseUrl = $env:FELIX_SYNC_URL }
        if ($env:FELIX_SYNC_KEY) { $apiKey = $env:FELIX_SYNC_KEY }
    }

    # Always pick up the key from env if sync is enabled but key not in config
    if ($syncEnabled -and -not $apiKey -and $env:FELIX_SYNC_KEY) {
        $apiKey = $env:FELIX_SYNC_KEY
    }
    if ($syncEnabled -and -not $baseUrl -and $env:FELIX_SYNC_URL) {
        $baseUrl = $env:FELIX_SYNC_URL
    }

    if ($syncEnabled -and $baseUrl) {
        return Get-NextRequirementRemote -BaseUrl $baseUrl -ApiKey $apiKey -AgentId $AgentId
    }
    else {
        return Get-NextRequirementLocal -RequirementsFilePath $RequirementsFilePath
    }
}

function Get-NextRequirementLocal {
    <#
    .SYNOPSIS
    Scans local requirements.json for the next in_progress then planned item.
    Preserves existing felix-loop behaviour exactly.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFilePath
    )

    if (-not (Test-Path $RequirementsFilePath)) {
        Emit-Error -ErrorType "RequirementsFileNotFound" -Message "Requirements file not found: $RequirementsFilePath" -Severity "error"
        return $null
    }

    try {
        $parsed = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        # Normalize bare array format (legacy) to { requirements: [] } object
        if ($parsed -is [array]) { $requirements = [PSCustomObject]@{ requirements = $parsed } } else { $requirements = $parsed }
    }
    catch {
        Emit-Error -ErrorType "RequirementsParseError" -Message "Failed to parse requirements.json: $_" -Severity "error"
        return $null
    }

    # in_progress first (resume interrupted work), then planned - both sorted by ID
    $req = $requirements.requirements |
    Where-Object { $_.status -eq "in_progress" } |
    Sort-Object { $_.id } |
    Select-Object -First 1

    if (-not $req) {
        $req = $requirements.requirements |
        Where-Object { $_.status -eq "planned" } |
        Sort-Object { $_.id } |
        Select-Object -First 1
    }

    return $req
}

function Get-NextRequirementRemote {
    <#
    .SYNOPSIS
    Calls GET /api/sync/work/next to receive a server-assigned requirement.
    Server marks it in_progress + assigned_to=AgentId atomically.
    Returns $null when no work is available.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [string]$ApiKey = "",

        [Parameter(Mandatory = $false)]
        [string]$AgentId = ""
    )

    try {
        $headers = @{ "Content-Type" = "application/json" }
        if ($ApiKey) { $headers["Authorization"] = "Bearer $ApiKey" }

        $url = "$($BaseUrl.TrimEnd('/'))/api/sync/work/next"
        if ($AgentId) { $url += "?agent_id=$([Uri]::EscapeDataString($AgentId))" }

        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers -ErrorAction Stop

        if (-not $response -or -not $response.code) {
            Emit-Log -Level "info" -Message "No work available from server" -Component "work-selector"
            return $null
        }

        # Return object compatible with the local requirement shape the loop expects
        return [PSCustomObject]@{
            id                 = $response.code
            title              = $response.title
            spec_path          = $response.spec_path
            status             = "in_progress"   # server already set this
            commit_on_complete = if ($null -ne $response.commit_on_complete) { $response.commit_on_complete } else { $true }
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 204 -or $statusCode -eq 404) {
            Emit-Log -Level "info" -Message "No work available from server ($statusCode)" -Component "work-selector"
            return $null
        }
        Emit-Log -Level "warn" -Message "Remote work fetch failed: $_ - falling back to local" -Component "work-selector"
        return $null
    }
}

function Send-WorkRelease {
    <#
    .SYNOPSIS
    Releases a previously claimed requirement back to the server queue.
    Called on backpressure failure or error so other agents can pick it up.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementCode,

        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [string]$ApiKey = ""
    )

    try {
        $headers = @{ "Content-Type" = "application/json" }
        if ($ApiKey) { $headers["Authorization"] = "Bearer $ApiKey" }

        $body = @{ code = $RequirementCode } | ConvertTo-Json
        Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/api/sync/work/release" -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Emit-Log -Level "info" -Message "Released $RequirementCode back to server queue" -Component "work-selector"
    }
    catch {
        Emit-Log -Level "warn" -Message "Failed to release ${RequirementCode}: $_" -Component "work-selector"
    }
}

function Send-WorkStart {
    <#
    .SYNOPSIS
    Transitions a reserved requirement to in_progress on the server.
    Called by the agent immediately before its first iteration begins.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementCode,

        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [string]$ApiKey = ""
    )

    try {
        $headers = @{ "Content-Type" = "application/json" }
        if ($ApiKey) { $headers["Authorization"] = "Bearer $ApiKey" }

        $body = @{ code = $RequirementCode } | ConvertTo-Json
        Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/api/sync/work/start" -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Emit-Log -Level "info" -Message "${RequirementCode} transitioned to in_progress on server" -Component "work-selector"
    }
    catch {
        # Non-fatal: agent proceeds even if this fails (e.g. server unavailable or already in_progress)
        Emit-Log -Level "warn" -Message "Failed to mark ${RequirementCode} in_progress on server: $_" -Component "work-selector"
    }
}

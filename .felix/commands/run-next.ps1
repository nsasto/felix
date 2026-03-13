<#
.SYNOPSIS
Runs the next available requirement — local or server-assigned.

.DESCRIPTION
Equivalent to one iteration of felix loop:
  - Remote mode (sync enabled): claims next planned requirement from server
    via GET /api/sync/work/next (atomic, skip-locked)
  - Local mode: picks next in_progress then planned from requirements.json

Exits 0 on success, non-zero on failure, 5 if no work is available.
#>

function Invoke-RunNext {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $formatValue = if ($Format) { $Format } else { "rich" }
    $syncEnabled = $false

    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--format" -and ($i + 1) -lt $Args.Count) {
            $formatValue = $Args[$i + 1]
            $i++
        }
        elseif ($Args[$i] -eq "--sync") {
            $syncEnabled = $true
        }
    }

    # Load engine dependencies
    . "$PSScriptRoot\..\core\emit-event.ps1"
    . "$PSScriptRoot\..\core\work-selector.ps1"

    # Load config for sync mode detection
    $config = $null
    $configFile = Join-Path $RepoRoot ".felix\config.json"
    try {
        if (Test-Path $configFile) {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
        }
    }
    catch { <# non-fatal, falls back to local mode #> }

    # Override sync from flag
    if ($syncEnabled -and $config) {
        if ($config -is [hashtable]) {
            if (-not $config["sync"]) { $config["sync"] = @{} }
            $config["sync"]["enabled"] = $true
        }
        else {
            if (-not $config.sync) { $config | Add-Member -NotePropertyName "sync" -NotePropertyValue ([PSCustomObject]@{}) -Force }
            $config.sync | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force
        }
    }
    elseif ($syncEnabled) {
        $config = [PSCustomObject]@{ sync = [PSCustomObject]@{ enabled = $true } }
    }

    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"

    # Determine agent id from agents.json if available
    $agentId = ""
    try {
        $agentsFile = Join-Path $RepoRoot ".felix\agents.json"
        if (Test-Path $agentsFile) {
            $agentsData = Get-Content $agentsFile -Raw | ConvertFrom-Json
            # Handle both array format and { "agents": [...] } wrapper format
            $agentsArray = if ($agentsData -is [array]) { $agentsData }
            elseif ($agentsData.agents) { $agentsData.agents }
            else { @($agentsData) }
            $first = $agentsArray | Select-Object -First 1
            if ($first.key) { $agentId = $first.key }
        }
    }
    catch { }

    # Claim / pick next requirement
    $nextReq = Get-NextRequirement -RequirementsFilePath $requirementsFile -Config $config -AgentId $agentId

    if (-not $nextReq) {
        if ($formatValue -eq "json") {
            Emit-Log -Level "info" -Message "No requirements available to run" -Component "run-next"
        }
        else {
            Write-Host "No requirements available to run." -ForegroundColor Yellow
        }
        exit 5
    }

    if ($formatValue -ne "json") {
        Write-Host ""
        Write-Host "Running: $($nextReq.id)" -ForegroundColor Cyan
    }
    else {
        Emit-Log -Level "info" -Message "Running requirement: $($nextReq.id)" -Component "run-next"
    }

    # When sync is enabled the requirement came from the server with an authoritative
    # status (reserved/in_progress). Update the local requirements.json so that
    # Get-CurrentRequirement in felix-agent.ps1 sees the server status instead of
    # a potentially stale local status (e.g. "complete").
    if ($syncEnabled -and (Test-Path $requirementsFile)) {
        try {
            $parsed = Get-Content $requirementsFile -Raw | ConvertFrom-Json
            if ($parsed -is [array]) { $localReqs = [PSCustomObject]@{ requirements = $parsed } } else { $localReqs = $parsed }
            $localEntry = $localReqs.requirements | Where-Object { $_.id -eq $nextReq.id }
            if ($localEntry) {
                $serverStatus = if ($nextReq.status) { $nextReq.status } else { "in_progress" }
                $localEntry.status = $serverStatus
                $localReqs | ConvertTo-Json -Depth 10 | Set-Content $requirementsFile -Encoding UTF8
            }
        }
        catch {
            # Non-fatal - agent will still get the ID; worst case it re-hits the status check
        }
    }

    # Delegate to felix-cli.ps1 (same as 'felix run <id>')
    $felixCli = "$PSScriptRoot\..\felix-cli.ps1"

    if ($NoStats) {
        & $felixCli -ProjectPath $RepoRoot -RequirementId $nextReq.id -Format $formatValue -NoStats -VerboseMode:$VerboseMode -Sync:$syncEnabled
    }
    else {
        & $felixCli -ProjectPath $RepoRoot -RequirementId $nextReq.id -Format $formatValue -VerboseMode:$VerboseMode -Sync:$syncEnabled
    }
    exit $LASTEXITCODE
}

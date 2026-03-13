
function Invoke-Loop {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # --- Parse flags ---
    # $Format / $VerboseMode / $RepoRoot / $FelixRoot inherited from felix.ps1 scope
    $maxRequirements = 999
    $noCommit = $false
    $syncEnabled = $false

    $i = 0
    while ($i -lt $Args.Count) {
        switch ($Args[$i]) {
            "--max-iterations" { $maxRequirements = [int]$Args[++$i] }
            "--no-commit" { $noCommit = $true }
            "--sync" { $syncEnabled = $true }
        }
        $i++
    }

    # --- Dot-source required modules ---
    . "$FelixRoot\core\emit-event.ps1"
    . "$FelixRoot\core\config-loader.ps1"
    . "$FelixRoot\core\setup-utils.ps1"
    . "$FelixRoot\core\sync-interface.ps1"
    . "$FelixRoot\core\work-selector.ps1"
    . "$FelixRoot\core\requirements-utils.ps1"

    # --- Resolve paths ---
    $FelixDir = Join-Path $RepoRoot ".felix"
    $requirementsFile = Join-Path $FelixDir "requirements.json"
    $agentsJsonFile = Join-Path $FelixDir "agents.json"
    $felixCli = Join-Path $FelixRoot "felix-cli.ps1"
    $activeFormat = if ($Format) { $Format } else { $global:FelixOutputFormat }
    if (-not $activeFormat) { $activeFormat = "rich" }

    # --- Load config, patch sync.enabled if --sync (mirrors run-next pattern) ---
    $config = $null
    try {
        $configFile = Join-Path $FelixDir "config.json"
        if (Test-Path $configFile) { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    }
    catch { }

    if ($syncEnabled -and $config) {
        if (-not $config.sync) {
            $config | Add-Member -NotePropertyName "sync" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $config.sync | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force
    }
    elseif ($syncEnabled) {
        $config = [PSCustomObject]@{ sync = [PSCustomObject]@{ enabled = $true } }
    }

    # --- Load agent payload (key + registration info in one call) ---
    $agentsData = Get-AgentsConfiguration -AgentsJsonFile $agentsJsonFile
    $agentConfig = $agentsData.agents | Select-Object -First 1
    $agentPayload = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $RepoRoot -Source "felix loop"
    $agentKey = $agentPayload.key

    # --- Pre-flight: register agent once before first iteration ---
    $reporter = Get-RunReporter -FelixDir $FelixDir
    $isSyncActive = $reporter.GetType().Name -ne "NoOpReporter"

    if ($isSyncActive) {
        Emit-Log -Level "info" -Message "Sync enabled -> $($reporter.BaseUrl)" -Component "sync"
        $regResult = $reporter.RegisterAgent($agentPayload)
        if (-not $regResult.Success) {
            $detail = if ($regResult.Error) { ": $($regResult.Error)" } else { "" }
            Emit-Log -Level "error" -Message "Agent registration failed$detail - aborting loop" -Component "sync"
            exit 1
        }
        Emit-Log -Level "info" -Message "Agent registered (key: $agentKey)" -Component "sync"
    }

    # --- Loop lock ---
    $lockDir = Join-Path $FelixDir ".locks"
    New-Item -Path $lockDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $lockFile = Join-Path $lockDir "loop-$PID.lock"
    @{ pid = $PID; started = (Get-Date -Format "o"); project = $RepoRoot } | ConvertTo-Json | Set-Content $lockFile

    $processed = 0

    try {
        while ($processed -lt $maxRequirements) {
            # Claim next requirement â€” identical to run-next: local file or server-assigned
            $nextReq = Get-NextRequirement -RequirementsFilePath $requirementsFile -Config $config -AgentId $agentKey

            if (-not $nextReq) {
                Emit-Log -Level "info" -Message "No more requirements to process - all done!" -Component "loop"
                break
            }

            Emit-Log -Level "info" -Message "Processing: $($nextReq.id)" -Component "loop"

            # Mirror run-next: write server-assigned status back to local requirements.json
            # so felix-agent sees the correct status (e.g. "in_progress") not a stale one.
            if ($syncEnabled -and (Test-Path $requirementsFile)) {
                try {
                    $parsed = Get-Content $requirementsFile -Raw | ConvertFrom-Json
                    if ($parsed -is [array]) { $localReqs = [PSCustomObject]@{ requirements = $parsed } } else { $localReqs = $parsed }
                    $localEntry = $localReqs.requirements | Where-Object { $_.id -eq $nextReq.id }
                    if ($localEntry) {
                        $localEntry.status = if ($nextReq.status) { $nextReq.status } else { "in_progress" }
                        $localReqs | ConvertTo-Json -Depth 10 | Set-Content $requirementsFile -Encoding UTF8
                    }
                }
                catch { }
            }

            # Tell subprocess to skip re-registration â€” loop already registered above
            $env:FELIX_SKIP_REGISTER = "true"
            try {
                $cliParams = @{
                    ProjectPath   = [string]$RepoRoot
                    RequirementId = [string]$nextReq.id
                    Format        = $activeFormat
                    Sync          = [bool]$syncEnabled
                    NoCommit      = [bool]$noCommit
                }
                & $felixCli @cliParams
                $exitCode = $LASTEXITCODE
            }
            finally {
                Remove-Item Env:\FELIX_SKIP_REGISTER -ErrorAction SilentlyContinue
            }

            switch ($exitCode) {
                0 {
                    Emit-Log -Level "info" -Message "$($nextReq.id) completed" -Component "loop"
                    # Keep local requirements.json in sync â€” mark complete regardless of sync mode
                    Update-RequirementStatus -RequirementsFilePath $requirementsFile -RequirementId $nextReq.id -NewStatus "complete" | Out-Null
                    $processed++
                }
                1 {
                    Emit-Log -Level "error" -Message "$($nextReq.id) failed (exit 1) - stopping loop" -Component "loop"
                    exit 1
                }
                2 {
                    Emit-Log -Level "warn" -Message "$($nextReq.id) blocked (backpressure) - moving on" -Component "loop"
                    if ($isSyncActive) {
                        Send-WorkRelease -RequirementCode $nextReq.id -BaseUrl $reporter.BaseUrl -ApiKey $reporter.ApiKey
                    }
                    $processed++
                }
                3 {
                    Emit-Log -Level "warn" -Message "$($nextReq.id) blocked (validation) - moving on" -Component "loop"
                    if ($isSyncActive) {
                        Send-WorkRelease -RequirementCode $nextReq.id -BaseUrl $reporter.BaseUrl -ApiKey $reporter.ApiKey
                    }
                    $processed++
                }
                default {
                    Emit-Log -Level "error" -Message "$($nextReq.id) unexpected exit $exitCode - stopping" -Component "loop"
                    exit $exitCode
                }
            }
        }

        if ($processed -ge $maxRequirements) {
            Emit-Log -Level "info" -Message "Max requirements reached ($maxRequirements)" -Component "loop"
        }
    }
    finally {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }

    exit 0
}

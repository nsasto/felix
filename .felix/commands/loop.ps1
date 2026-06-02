
function Invoke-Loop {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # --- Parse flags ---
    $maxRequirements = 999
    $noCommit        = $false
    $syncEnabled     = $false
    $parallelWorkers = 1
    $useWorktrees    = $false

    $i = 0
    while ($i -lt $Args.Count) {
        switch ($Args[$i]) {
            "--max-iterations" { $maxRequirements = [int]$Args[++$i] }
            "--no-commit"      { $noCommit        = $true }
            "--sync"           { $syncEnabled      = $true }
            "--parallel"       { $parallelWorkers  = [int]$Args[++$i] }
            "--worktrees"      { $useWorktrees     = $true }
        }
        $i++
    }

    . "$FelixRoot\core\emit-event.ps1"
    . "$FelixRoot\core\config-loader.ps1"
    . "$FelixRoot\core\setup-utils.ps1"
    . "$FelixRoot\core\sync-interface.ps1"
    . "$FelixRoot\core\work-selector.ps1"
    . "$FelixRoot\core\requirements-utils.ps1"
    . "$FelixRoot\core\lease-manager.ps1"
    . "$FelixRoot\core\worktree-manager.ps1"

    $FelixDir         = Join-Path $RepoRoot ".felix"
    $requirementsFile = Join-Path $FelixDir "requirements.json"
    $agentsJsonFile   = Join-Path $FelixDir "agents.json"
    $felixCli         = Join-Path $FelixRoot "felix-cli.ps1"
    $activeFormat     = if ($Format) { $Format } else { $global:FelixOutputFormat }
    if (-not $activeFormat) { $activeFormat = "rich" }

    $config = $null
    try {
        $configFile = Join-Path $FelixDir "config.json"
        if (Test-Path $configFile) { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    } catch {}

    $wtCfg = Get-WorktreeConfig -ProjectPath $RepoRoot
    if ($wtCfg.enabled -and -not $useWorktrees)               { $useWorktrees    = $true }
    if ($wtCfg.parallel -gt 1 -and $parallelWorkers -eq 1)    { $parallelWorkers = $wtCfg.parallel }

    if ($syncEnabled -and $config) {
        if (-not $config.sync) { $config | Add-Member -NotePropertyName "sync" -NotePropertyValue ([PSCustomObject]@{}) -Force }
        $config.sync | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force
    } elseif ($syncEnabled) {
        $config = [PSCustomObject]@{ sync = [PSCustomObject]@{ enabled = $true } }
    }

    $agentsData   = Get-AgentsConfiguration -AgentsJsonFile $agentsJsonFile
    $agentConfig  = $agentsData.agents | Select-Object -First 1
    $agentPayload = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $RepoRoot -Source "felix loop"
    $agentKey     = $agentPayload.key

    $reporter     = Get-RunReporter -FelixDir $FelixDir
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

    $lockDir  = Join-Path $FelixDir ".locks"
    New-Item -Path $lockDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $lockFile = Join-Path $lockDir "loop-$PID.lock"
    @{ pid = $PID; started = (Get-Date -Format "o"); project = $RepoRoot; parallel = $parallelWorkers } | ConvertTo-Json | Set-Content $lockFile

    if ($parallelWorkers -gt 1) {
        Invoke-LoopParallel -ParallelWorkers $parallelWorkers -MaxRequirements $maxRequirements `
            -RepoRoot $RepoRoot -FelixRoot $FelixRoot -FelixCli $felixCli `
            -RequirementsFile $requirementsFile -Config $config -AgentKey $agentKey `
            -ActiveFormat $activeFormat -SyncEnabled $syncEnabled -NoCommit $noCommit `
            -UseWorktrees $useWorktrees -Reporter $reporter -IsSyncActive $isSyncActive `
            -LockFile $lockFile
        return
    }

    $processed = 0
    try {
        while ($processed -lt $maxRequirements) {
            $nextReq = Get-NextUnleasedRequirement -RequirementsFilePath $requirementsFile -Config $config -AgentId $agentKey -ProjectPath $RepoRoot
            if (-not $nextReq) {
                Emit-Log -Level "info" -Message "No more requirements to process - all done!" -Component "loop"
                break
            }

            $runId = "$($nextReq.id)-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $lease = New-RequirementLease -ProjectPath $RepoRoot -RequirementId $nextReq.id -RunId $runId
            if (-not $lease) {
                Emit-Log -Level "info" -Message "$($nextReq.id) claimed by another worker - skipping" -Component "loop"
                continue
            }

            Emit-Log -Level "info" -Message "Processing: $($nextReq.id) (lease: $runId)" -Component "loop"

            $wtPath = $null
            if ($useWorktrees) {
                $wtPath = New-WorktreeForRun -RepoRoot $RepoRoot -RunId $runId
                if (-not $wtPath) { Write-Host "  [loop] Worktree creation failed - running in main tree" -ForegroundColor Yellow }
            }

            if ($syncEnabled -and (Test-Path $requirementsFile)) {
                try {
                    $parsed = Get-Content $requirementsFile -Raw | ConvertFrom-Json
                    if ($parsed -is [array]) { $localReqs = [PSCustomObject]@{ requirements = $parsed } } else { $localReqs = $parsed }
                    $localEntry = $localReqs.requirements | Where-Object { $_.id -eq $nextReq.id }
                    if ($localEntry) {
                        $localEntry.status = if ($nextReq.status) { $nextReq.status } else { "in_progress" }
                        $localReqs | ConvertTo-Json -Depth 10 | Set-Content $requirementsFile -Encoding UTF8
                    }
                } catch {}
            }

            $env:FELIX_SKIP_REGISTER = "true"
            $exitCode = 0
            try {
                $cliParams = @{
                    ProjectPath   = [string](if ($wtPath) { $wtPath } else { $RepoRoot })
                    RequirementId = [string]$nextReq.id
                    Format        = $activeFormat
                    Sync          = [bool]$syncEnabled
                    NoCommit      = [bool]$noCommit
                    DebugMode     = [bool]$DebugMode
                }
                & $felixCli @cliParams
                $exitCode = $LASTEXITCODE
            } finally {
                Remove-Item Env:\FELIX_SKIP_REGISTER -ErrorAction SilentlyContinue
                Remove-RequirementLease -ProjectPath $RepoRoot -RequirementId $nextReq.id | Out-Null
            }

            if ($wtPath -and $exitCode -eq 0 -and -not $noCommit) {
                $mergeResult = Merge-WorktreeToBase -RepoRoot $RepoRoot -RunId $runId
                if ($mergeResult -eq "conflict") {
                    Emit-Log -Level "warn" -Message "$($nextReq.id) merge conflict - marking blocked" -Component "loop"
                    Set-RequirementBlocked -RequirementsFilePath $requirementsFile -RequirementId $nextReq.id -BlockReason "merge-conflict"
                    $exitCode = 2
                } elseif ($mergeResult -eq "ok") {
                    Remove-WorktreeForRun -RepoRoot $RepoRoot -RunId $runId | Out-Null
                }
            }

            switch ($exitCode) {
                0 {
                    Emit-Log -Level "info" -Message "$($nextReq.id) completed" -Component "loop"
                    Update-RequirementStatus -RequirementsFilePath $requirementsFile -RequirementId $nextReq.id -NewStatus "complete" | Out-Null
                    $processed++
                }
                1 {
                    Emit-Log -Level "error" -Message "$($nextReq.id) failed (exit 1) - stopping loop" -Component "loop"
                    exit 1
                }
                2 {
                    Emit-Log -Level "warn" -Message "$($nextReq.id) blocked (backpressure) - moving on" -Component "loop"
                    if ($isSyncActive) { Send-WorkRelease -RequirementCode $nextReq.id -BaseUrl $reporter.BaseUrl -ApiKey $reporter.ApiKey }
                    $processed++
                }
                3 {
                    Emit-Log -Level "warn" -Message "$($nextReq.id) blocked (validation) - moving on" -Component "loop"
                    if ($isSyncActive) { Send-WorkRelease -RequirementCode $nextReq.id -BaseUrl $reporter.BaseUrl -ApiKey $reporter.ApiKey }
                    $processed++
                }
                default {
                    Emit-Log -Level "error" -Message "$($nextReq.id) unexpected exit $exitCode - stopping" -Component "loop"
                    exit $exitCode
                }
            }
        }
        if ($processed -ge $maxRequirements) { Emit-Log -Level "info" -Message "Max requirements reached ($maxRequirements)" -Component "loop" }
    } finally {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

function Get-NextUnleasedRequirement {
    param([string]$RequirementsFilePath, $Config = $null, [string]$AgentId = "", [string]$ProjectPath = "")
    if (-not (Test-Path $RequirementsFilePath)) { return $null }
    try {
        $parsed = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $reqs   = if ($parsed -is [array]) { $parsed } else { @($parsed.requirements) }
        $next   = $reqs | Where-Object {
            $_.status -eq "planned" -and
            -not (Test-RequirementLeased -ProjectPath $ProjectPath -RequirementId $_.id)
        } | Select-Object -First 1
        if ($next) { return $next }
    } catch {}
    return Get-NextRequirement -RequirementsFilePath $RequirementsFilePath -Config $Config -AgentId $AgentId
}

function Set-RequirementBlocked {
    param([string]$RequirementsFilePath, [string]$RequirementId, [string]$BlockReason = "")
    if (-not (Test-Path $RequirementsFilePath)) { return }
    try {
        $parsed  = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $isArray = $parsed -is [array]
        $reqs    = if ($isArray) { $parsed } else { @($parsed.requirements) }
        $req     = $reqs | Where-Object { $_.id -eq $RequirementId } | Select-Object -First 1
        if ($req) {
            $req.status = "blocked"
            if ($BlockReason) { $req | Add-Member -NotePropertyName "block_reason" -NotePropertyValue $BlockReason -Force }
            if ($isArray) { $reqs | ConvertTo-Json -Depth 10 | Set-Content $RequirementsFilePath -Encoding UTF8 }
            else          { $parsed | ConvertTo-Json -Depth 10 | Set-Content $RequirementsFilePath -Encoding UTF8 }
        }
    } catch { Write-Host "  [loop] Could not mark $RequirementId blocked: $_" -ForegroundColor Yellow }
}

function Invoke-LoopParallel {
    param(
        [int]$ParallelWorkers, [int]$MaxRequirements,
        [string]$RepoRoot, [string]$FelixRoot, [string]$FelixCli,
        [string]$RequirementsFile, $Config, [string]$AgentKey,
        [string]$ActiveFormat, [bool]$SyncEnabled, [bool]$NoCommit,
        [bool]$UseWorktrees, $Reporter, [bool]$IsSyncActive, [string]$LockFile
    )

    Write-Host ""
    Write-Host "felix loop --parallel $ParallelWorkers$(if ($UseWorktrees) { ' --worktrees' })" -ForegroundColor Cyan
    Write-Host "Starting $ParallelWorkers worker(s)..." -ForegroundColor Gray
    Write-Host ""

    $workerScript = {
        param($WorkerIndex, $RepoRoot, $FelixRoot, $FelixCli, $RequirementsFile, $SyncEnabled, $NoCommit, $ActiveFormat, $UseWorktrees)
        $ErrorActionPreference = "Stop"
        . "$FelixRoot\core\lease-manager.ps1"
        . "$FelixRoot\core\worktree-manager.ps1"
        . "$FelixRoot\core\requirements-utils.ps1"
        . "$FelixRoot\core\emit-event.ps1"
        . "$FelixRoot\commands\loop.ps1"

        $workerId  = "worker-$WorkerIndex"
        $processed = 0

        while ($processed -lt 999) {
            if (-not (Test-Path $RequirementsFile)) { break }
            $parsed  = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
            $reqs    = if ($parsed -is [array]) { $parsed } else { @($parsed.requirements) }
            $nextReq = $reqs | Where-Object {
                $_.status -eq "planned" -and -not (Test-RequirementLeased -ProjectPath $RepoRoot -RequirementId $_.id)
            } | Select-Object -First 1

            if (-not $nextReq) { Write-Host "  [$workerId] No more requirements - done" -ForegroundColor Gray; break }

            $runId = "$($nextReq.id)-w$WorkerIndex-$(Get-Date -Format 'HHmmss')"
            $lease = New-RequirementLease -ProjectPath $RepoRoot -RequirementId $nextReq.id -RunId $runId
            if (-not $lease) { Start-Sleep -Milliseconds 200; continue }

            Write-Host "  [$workerId] Claimed: $($nextReq.id)" -ForegroundColor Yellow

            $wtPath = $null
            if ($UseWorktrees) { $wtPath = New-WorktreeForRun -RepoRoot $RepoRoot -RunId $runId }

            $exitCode = 0
            try {
                $env:FELIX_SKIP_REGISTER = "true"
                $cliParams = @{
                    ProjectPath   = [string](if ($wtPath) { $wtPath } else { $RepoRoot })
                    RequirementId = [string]$nextReq.id
                    Format        = $ActiveFormat
                    Sync          = [bool]$SyncEnabled
                    NoCommit      = [bool]$NoCommit
                }
                & $FelixCli @cliParams
                $exitCode = $LASTEXITCODE
            } finally {
                Remove-Item Env:\FELIX_SKIP_REGISTER -ErrorAction SilentlyContinue
                Remove-RequirementLease -ProjectPath $RepoRoot -RequirementId $nextReq.id | Out-Null
            }

            if ($wtPath -and $exitCode -eq 0 -and -not $NoCommit) {
                $mergeResult = Merge-WorktreeToBase -RepoRoot $RepoRoot -RunId $runId
                if ($mergeResult -eq "conflict") {
                    Write-Host "  [$workerId] Merge conflict for $($nextReq.id) - blocking" -ForegroundColor Red
                    Set-RequirementBlocked -RequirementsFilePath $RequirementsFile -RequirementId $nextReq.id -BlockReason "merge-conflict"
                    $exitCode = 2
                } elseif ($mergeResult -eq "ok") {
                    Remove-WorktreeForRun -RepoRoot $RepoRoot -RunId $runId | Out-Null
                }
            }

            if ($exitCode -eq 0) {
                Update-RequirementStatus -RequirementsFilePath $RequirementsFile -RequirementId $nextReq.id -NewStatus "complete" | Out-Null
                Write-Host "  [$workerId] Completed: $($nextReq.id)" -ForegroundColor Green
            } elseif ($exitCode -eq 1) {
                Write-Host "  [$workerId] Failed: $($nextReq.id) - stopping worker" -ForegroundColor Red; break
            }
            $processed++
        }
        Write-Host "  [$workerId] Exiting (processed $processed)" -ForegroundColor Gray
    }

    $jobs = @()
    for ($w = 1; $w -le $ParallelWorkers; $w++) {
        $job = Start-Job -ScriptBlock $workerScript -ArgumentList @(
            $w, $RepoRoot, $FelixRoot, $FelixCli, $RequirementsFile,
            $SyncEnabled, $NoCommit, $ActiveFormat, $UseWorktrees
        )
        $jobs += $job
        Write-Host "  Started worker $w (job $($job.Id))" -ForegroundColor Gray
    }

    $finished = @{}
    while ($finished.Count -lt $jobs.Count) {
        foreach ($job in $jobs) {
            if ($job.Id -notin $finished.Keys -and $job.State -in @("Completed","Failed","Stopped")) {
                Receive-Job -Job $job 2>&1 | ForEach-Object { Write-Host $_ }
                $finished[$job.Id] = $job.State
                Write-Host "  Worker job-$($job.Id) finished ($($job.State))" -ForegroundColor Gray
            }
        }
        if ($finished.Count -lt $jobs.Count) { Start-Sleep -Seconds 2 }
    }

    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    if ($finished.Values -contains "Failed") { exit 1 }
    exit 0
}

# Loop Enhancements — Inline loop into felix command framework

> **Status:** Planned — Loop architecture improvements

## Problem

`felix loop` currently delegates to a standalone `felix-loop.ps1` script that lives outside the `felix.ps1` command framework. This causes several issues:

1. **Agent registration happens per-run, not per-loop** — `RegisterAgent` is called inside `felix-agent.ps1` (the subprocess), so a bad key/URL is not caught until the first iteration starts. A 10-iteration loop could have been failing on iteration 1 every time.

2. **Work selection still uses the stale env-var pattern** — `felix-loop.ps1` reads `FELIX_SYNC_ENABLED` to decide whether to call `Get-NextRequirementRemote`, but doesn't benefit from the fixed fallback logic in `work-selector.ps1` (env key applied when sync is enabled from _any_ source).

3. **`.env` loading doesn't apply** — `felix.ps1` calls `Load-DotEnv` before routing, but `felix-loop.ps1` is invoked as a separate process that bypasses this entirely. `FELIX_SYNC_KEY` loaded from `.env` is only in the parent process; the loop subprocess doesn't inherit it.

4. **Format logic is duplicated** — `felix-loop.ps1` has its own `Emit-Loop-Log` shim to switch between NDJSON and plain text. `Emit-Log` is now format-aware via `$global:FelixOutputFormat`. The shim is dead weight.

5. **Cross-cutting concerns don't apply automatically** — any new global behaviour added to `felix.ps1` (new flags, new `.env` paths, telemetry) needs to be manually duplicated in `felix-loop.ps1`.

---

## Goal

- `felix loop` is a first-class command that lives entirely in `commands/loop.ps1`
- Pre-flight: register agent + validate sync _before_ the first iteration
- Each per-iteration `felix-cli.ps1` subprocess skips re-registration via `FELIX_SKIP_REGISTER=true`
- `felix-loop.ps1` is **deleted** (no shim — clean break)
- All output uses `Emit-Log` (inherits `$global:FelixOutputFormat` from `felix.ps1`)

---

## Architecture After

```
felix loop [--sync] [--max-iterations N] [--no-commit]
  └── commands/loop.ps1 : Invoke-Loop
        1. Parse flags
        2. Load .felix/config.json, patch sync.enabled if --sync
        3. Load agents.json → first agent → compute agentKey (New-AgentKey)
        4. Get-RunReporter → $reporter (HttpSync or NoOpReporter)
        5. PRE-FLIGHT: $reporter.RegisterAgent($syncAgentInfo)
           → fail fast if registration fails before any iteration
        6. Create .felix/.locks/loop-$PID.lock
        7. while ($processed -lt $maxIterations):
             a. Get-NextRequirement (work-selector, local or remote)
             b. Validate req still planned/in_progress in local file
             c. $env:FELIX_SKIP_REGISTER = "true"
                & felix-cli.ps1 -RequirementId $req.id -Sync:$syncEnabled
             d. Handle exit codes 0/1/2/3
             e. For exit 2/3: Send-WorkRelease if sync enabled
        8. Cleanup lock in finally block

felix-agent.ps1 (unchanged interface)
  - New guard: if ($env:FELIX_SKIP_REGISTER -eq "true") { skip RegisterAgent block }
  - Everything else unchanged — still self-registers when called via `felix run`

felix-loop.ps1
  → DELETED
```

---

## Files Changed

| File                       | Change                                                     |
| -------------------------- | ---------------------------------------------------------- |
| `.felix/commands/loop.ps1` | Full rewrite — absorbs all logic from `felix-loop.ps1`     |
| `.felix/felix-agent.ps1`   | Add `FELIX_SKIP_REGISTER` guard around RegisterAgent block |
| `.felix/felix-loop.ps1`    | **Deleted**                                                |
| `.felix/commands/help.ps1` | Update loop help if needed                                 |

---

## Implementation Steps

### Step 1 — Add `FELIX_SKIP_REGISTER` guard in `felix-agent.ps1`

Around the `if ($isSyncEnabled)` registration block (~line 431), wrap with:

```powershell
if ($isSyncEnabled -and $env:FELIX_SKIP_REGISTER -ne "true") {
    # ... existing RegisterAgent block ...
}
elseif ($isSyncEnabled) {
    Emit-Log -Level "debug" -Message "Agent registration skipped (pre-registered by loop)" -Component "sync"
    # Still start heartbeat — the agent needs to ping even if loop registered it
    $script:HeartbeatApiKey = $script:SyncReporter.ApiKey
    $script:HeartbeatBaseUrl = $script:SyncReporter.BaseUrl
    $script:HeartbeatJob = Start-HeartbeatJob `
        -AgentId $script:agentKey `
        -BackendBaseUrl $script:HeartbeatBaseUrl `
        -ApiKey $script:HeartbeatApiKey `
        -GitUrl $gitUrl
}
```

Note: heartbeat still starts even in skip mode — each run subprocess should still maintain liveness.

### Step 2 — Rewrite `commands/loop.ps1`

```powershell
function Invoke-Loop {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)

    # --- Parse flags ---
    $maxRequirements = 999
    $noCommit        = $false
    $syncEnabled     = $false
    # $Format / $VerboseMode inherited from felix.ps1 scope

    $i = 0
    while ($i -lt $Args.Count) {
        switch ($Args[$i]) {
            "--max-iterations" { $maxRequirements = [int]$Args[++$i] }
            "--no-commit"      { $noCommit = $true }
            "--sync"           { $syncEnabled = $true }
        }
        $i++
    }

    # --- Dot-source required modules ---
    . "$FelixRoot\core\emit-event.ps1"
    . "$FelixRoot\core\config-loader.ps1"
    . "$FelixRoot\core\setup-utils.ps1"
    . "$FelixRoot\core\sync-interface.ps1"
    . "$FelixRoot\core\work-selector.ps1"

    # --- Load config, patch sync if --sync flag ---
    $configFile = Join-Path $RepoRoot ".felix\config.json"
    $config = $null
    try {
        if (Test-Path $configFile) { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    } catch { }

    if ($syncEnabled) {
        if (-not $config) { $config = [PSCustomObject]@{ sync = [PSCustomObject]@{ enabled = $true } } }
        elseif (-not $config.sync) { $config | Add-Member -NotePropertyName sync -NotePropertyValue ([PSCustomObject]@{ enabled = $true }) -Force }
        else { $config.sync | Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force }
    }

    # --- Resolve paths ---
    $FelixDir          = Join-Path $RepoRoot ".felix"
    $requirementsFile  = Join-Path $FelixDir "requirements.json"
    $agentsJsonFile    = Join-Path $FelixDir "agents.json"

    # --- Load agent info for registration ---
    $agentsData = Get-AgentsConfiguration -AgentsJsonFile $agentsJsonFile
    $agentConfig = $agentsData.agents | Select-Object -First 1
    $provider    = if ($agentConfig.adapter) { $agentConfig.adapter } else { $agentConfig.name }
    $model       = if ($agentConfig.model)   { $agentConfig.model   } else { "" }
    $agentKey    = New-AgentKey -Provider $provider -Model $model -AgentSettings @{} -ProjectRoot $RepoRoot

    # --- Init sync reporter ---
    $reporter     = Get-RunReporter -FelixDir $FelixDir
    $isSyncActive = $reporter.GetType().Name -ne "NoOpReporter"

    # --- Pre-flight: register agent before first iteration ---
    if ($isSyncActive) {
        Emit-Log -Level "info" -Message "Sync enabled -> $($reporter.BaseUrl)" -Component "sync"

        $hostname = $env:COMPUTERNAME
        if (-not $hostname) { try { $hostname = [System.Net.Dns]::GetHostName() } catch { $hostname = "unknown" } }
        $gitUrl = (git config --get remote.origin.url 2>$null)?.Trim()

        $syncAgentInfo = @{
            key            = $agentKey
            provider       = $provider
            model          = $model
            agent_settings = @{}
            machine_id     = $hostname
            name           = $agentConfig.name
            type           = "cli"
            metadata       = @{ hostname = $hostname; platform = "windows" }
        }
        if ($gitUrl) { $syncAgentInfo["git_url"] = $gitUrl }

        $regResult = $reporter.RegisterAgent($syncAgentInfo)
        if (-not $regResult.Success) {
            $detail = if ($regResult.Error) { ": $($regResult.Error)" } else { "" }
            Emit-Log -Level "error" -Message "Agent registration failed$detail — aborting loop" -Component "sync"
            exit 1
        }
        Emit-Log -Level "info" -Message "Agent registered (key: $agentKey)" -Component "sync"
    }

    # --- Loop lock ---
    $lockDir  = Join-Path $FelixDir ".locks"
    New-Item -Path $lockDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $lockFile = Join-Path $lockDir "loop-$PID.lock"
    @{ pid = $PID; started = (Get-Date -Format "o"); project = $RepoRoot } | ConvertTo-Json | Set-Content $lockFile

    $felixCli = Join-Path $FelixRoot "felix-cli.ps1"
    $processed = 0

    try {
        while ($processed -lt $maxRequirements) {
            $nextReq = Get-NextRequirement -RequirementsFilePath $requirementsFile -Config $config -AgentId $agentKey
            if (-not $nextReq) {
                Emit-Log -Level "info" -Message "No more requirements to process - all done!" -Component "loop"
                break
            }

            # Verify status hasn't changed externally
            try {
                $fresh = (Get-Content $requirementsFile -Raw | ConvertFrom-Json).requirements |
                    Where-Object { $_.id -eq $nextReq.id } | Select-Object -First 1
                if (-not $fresh -or $fresh.status -notin @("planned","in_progress")) {
                    Emit-Log -Level "warn" -Message "Requirement $($nextReq.id) skipped (status: $($fresh.status))" -Component "loop"
                    continue
                }
            } catch {
                Emit-Log -Level "warn" -Message "Could not verify $($nextReq.id) status - skipping" -Component "loop"
                continue
            }

            Emit-Log -Level "info" -Message "Processing: $($nextReq.id)" -Component "loop"

            # Tell subprocess to skip re-registration
            $env:FELIX_SKIP_REGISTER = "true"
            try {
                $cliArgs = @("-ProjectPath", $RepoRoot, "-RequirementId", $nextReq.id, "-Format", $Format, "-Sync:$syncEnabled")
                if ($noCommit) { $cliArgs += "-NoCommit" }
                & $felixCli @cliArgs
                $exitCode = $LASTEXITCODE
            } finally {
                $env:FELIX_SKIP_REGISTER = $null
                Remove-Item Env:\FELIX_SKIP_REGISTER -ErrorAction SilentlyContinue
            }

            switch ($exitCode) {
                0 { Emit-Log -Level "info" -Message "$($nextReq.id) completed" -Component "loop"; $processed++ }
                1 { Emit-Log -Level "error" -Message "$($nextReq.id) failed (exit 1) - stopping loop" -Component "loop"; exit 1 }
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
                default { Emit-Log -Level "error" -Message "$($nextReq.id) unexpected exit $exitCode - stopping" -Component "loop"; exit $exitCode }
            }
        }

        if ($processed -ge $maxRequirements) {
            Emit-Log -Level "info" -Message "Max requirements reached ($maxRequirements)" -Component "loop"
        }
    } finally {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }

    exit 0
}
```

### Step 3 — Delete `felix-loop.ps1`

```powershell
Remove-Item .felix/felix-loop.ps1
```

Update any remaining references (search for `felix-loop.ps1` across the repo).

### Step 4 — Build, install, test

```powershell
.\scripts\build-and-install.ps1

# Test: sync enabled, valid key
felix loop --sync --max-iterations 1

# Test: sync enabled, bad key — should fail before first iteration
felix loop --sync --max-iterations 3  # with wrong FELIX_SYNC_KEY

# Test: local mode — unchanged behaviour
felix loop --max-iterations 2

# Test: single run still self-registers
felix run S-0001 --sync
```

---

## What Stays the Same

- `felix run S-0001 --sync` — calls `felix-cli.ps1` → subprocess `felix-agent.ps1`, which self-registers as before (no `FELIX_SKIP_REGISTER` set)
- `felix run-next --sync` — picks next requirement then delegates to `felix-cli.ps1`, same as before
- `felix agent register` — manual one-shot registration, unaffected
- `felix-cli.ps1` — unchanged; it's the per-run subprocess boundary
- Exit codes 0/1/2/3 semantics — unchanged

---

## Notes

- Heartbeat: even with `FELIX_SKIP_REGISTER`, each subprocess still starts its own heartbeat job. This is intentional — the heartbeat is per-run liveness, not per-loop. The loop orchestrator doesn't live in the same process as the heartbeat.
- `felix-loop.ps1` was invocable directly by `.\felix\felix-loop.ps1 C:\dev\Felix`. After deletion, this path breaks. Acceptable per user requirement (no backward compat).
- `felix-loop.ps1` is referenced in Enhancements/AGENTSCRIPT_MIGRATION.md and possibly CI scripts — audit before deleting.

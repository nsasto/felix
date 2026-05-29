# Felix CLI Hardening: Agent Execution Timeout Handling

> **Status:** Reference — Timeout handling notes

## Document Purpose

This document captures the design and implementation plan for adding timeout handling to Felix agent execution. Currently, the agent executor blocks indefinitely if an agent process hangs due to network failures, broken connections, or other issues.

**Date Created:** 2026-02-17  
**Status:** Planned  
**Priority:** High (blocks production readiness)  
**Related Docs:** [AGENTS.md](../AGENTS.md), [CLI_EXEC_IMPLEMENTATION.md](CLI_EXEC_IMPLEMENTATION.md)

---

## Problem Statement

### Current Behavior

The agent execution system uses `Start-Process -Wait` which blocks indefinitely:

```powershell
# .felix/core/executor.ps1 (line 679)
$p = Start-Process `
    -FilePath $resolvedExecutable `
    -ArgumentList $argString `
    -WorkingDirectory $agentCwd `
    -NoNewWindow `
    -PassThru `
    -Wait `                           # ← BLOCKS FOREVER
    -RedirectStandardInput $inputPath `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

$exitCode = [int]$p.ExitCode
```

### Failure Scenarios

1. **Network Connection Loss:** Agent (Droid/Claude) loses connection mid-execution
2. **Streaming Parse Failure:** Agent emits `<promise>TASK_COMPLETE</promise>` but PowerShell can't read it
3. **Process Hang:** Agent process deadlocks or enters infinite loop
4. **Resource Exhaustion:** Agent runs out of memory but doesn't exit

In all cases, the PowerShell script hangs forever with no recovery mechanism. Manual kill is required.

### User Impact

- **Production blocker:** Cannot deploy unattended automation
- **Wasted time:** Engineers must babysit long-running requirements
- **No diagnostics:** No artifacts captured from hung processes
- **Manual cleanup:** Orphaned processes require manual kill

---

## Technical Analysis

### Current Architecture

**File:** [.felix/core/executor.ps1](../.felix/core/executor.ps1) (lines 650-760)

**Flow:**

1. Create temp files for stdin/stdout/stderr
2. Write formatted prompt to input temp file
3. Start agent process with stream redirection
4. **BLOCK** until process exits (no timeout)
5. Read output from temp files
6. Parse response, emit events
7. Clean up temp files

**Output Capture Pattern:**

```powershell
$inputPath = [System.IO.Path]::GetTempFileName()
$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()

# Write prompt
[System.IO.File]::WriteAllText($inputPath, $formattedPrompt, $utf8NoBom)

# Execute and WAIT FOREVER
$p = Start-Process ... -Wait

# Read results
$stdout = Get-Content -Raw -LiteralPath $stdoutPath
$stderr = Get-Content -Raw -LiteralPath $stderrPath
```

### Exit Code Conventions

**Current exit codes** (from [.felix/core/exit-handler.ps1](../.felix/core/exit-handler.ps1)):

- **0** = Success
- **1** = General error (agent execution failures)
- **2** = Blocked (backpressure failures exceeded max retries)
- **3** = Blocked (validation failures exceeded max retries)
- **127** = Executable not found

**New exit code:**

- **4** = Timeout (agent process exceeded time limit)

### Timeout Pattern Research

**Best practice found** in [scripts/validate-requirement.py](../scripts/validate-requirement.py) (PowerShell job timeout):

```powershell
$job = Start-Job -ScriptBlock { ... }
$completed = Wait-Job -Job $job -Timeout $TimeoutSeconds

if ($completed) {
    $result = Receive-Job -Job $job
    Remove-Job -Job $job -Force
} else {
    # Timeout occurred
    Stop-Job -Job $job
    Remove-Job -Job $job -Force
}
```

**Preferred pattern** (direct process control):

```powershell
$p = Start-Process ... -PassThru  # No -Wait
$timeoutMs = $timeoutSeconds * 1000

if ($p.WaitForExit($timeoutMs)) {
    # Completed normally
    $exitCode = [int]$p.ExitCode
    # Read temp files as normal
} else {
    # Timeout occurred
    try {
        $p.Kill($true)  # Kill process tree
        $p.WaitForExit(5000)  # Wait for cleanup
    } catch {
        # Process already exited
    }

    $succeeded = $false
    $exitCode = 4  # Timeout exit code

    Emit-Error -ErrorType "AgentTimeout" -Message "..." -Severity "error"

    # Still read partial output for debugging
    $output = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
}
```

---

## Implementation Plan

### 1. Configuration Schema

**File:** [.felix/config.json](../.felix/config.json)

**Add to executor section:**

```json
{
  "executor": {
    "mode": "local",
    "max_iterations": 100,
    "default_mode": "planning",
    "commit_on_complete": true,
    "agent_timeout_seconds": 1800,
    "_timeout_note": "0 = no timeout (dangerous but available for debugging)"
  }
}
```

**Default:** 1800 seconds (30 minutes)
**Zero handling:** 0 = infinite timeout (preserves current behavior for debugging)

**Future enhancement:** Per-agent timeout override in agents.json

### 2. Exit Code Handling

**File:** [.felix/core/exit-handler.ps1](../.felix/core/exit-handler.ps1)

**Modify around line 70:**

```powershell
# Current:
$status = if ($ExitCode -eq 0) { "success" }
    elseif ($ExitCode -eq 2) { "blocked_backpressure" }
    elseif ($ExitCode -eq 3) { "blocked_validation" }
    else { "error" }

# Add:
$status = if ($ExitCode -eq 0) { "success" }
    elseif ($ExitCode -eq 2) { "blocked_backpressure" }
    elseif ($ExitCode -eq 3) { "blocked_validation" }
    elseif ($ExitCode -eq 4) { "timeout" }
    else { "error" }
```

**Update documentation comments:**

```powershell
# Exit Codes:
#   0 = Success
#   1 = General error
#   2 = Blocked (backpressure failures)
#   3 = Blocked (validation failures)
#   4 = Timeout (agent exceeded time limit)
#   127 = Executable not found
```

### 3. Executor Timeout Logic

**File:** [.felix/core/executor.ps1](../.felix/core/executor.ps1)

**Location:** Lines 679-710 (Start-Process section)

**Changes:**

```powershell
# Read timeout configuration
$timeoutSeconds = 1800  # Default: 30 minutes
if ($Config.executor.PSObject.Properties['agent_timeout_seconds']) {
    $timeoutSeconds = [int]$Config.executor.agent_timeout_seconds
}

# Convert to milliseconds (0 = infinite)
$timeoutMs = if ($timeoutSeconds -eq 0) { [int]::MaxValue } else { $timeoutSeconds * 1000 }

Emit-Log -Level "debug" -Message "Agent timeout: $timeoutSeconds seconds" -Component "agent"

# Start process WITHOUT -Wait
$p = Start-Process `
    -FilePath $resolvedExecutable `
    -ArgumentList $argString `
    -WorkingDirectory $agentCwd `
    -NoNewWindow `
    -PassThru `
    -RedirectStandardInput $inputPath `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

# Wait with timeout
$startTime = Get-Date
if ($p.WaitForExit($timeoutMs)) {
    # Normal completion
    $exitCode = [int]$p.ExitCode

    # Existing success/failure logic...
    $stdout = ""
    $stderr = ""
    if (Test-Path $stdoutPath) { $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue }
    if (Test-Path $stderrPath) { $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue }

    $output = $stdout
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        if (-not [string]::IsNullOrWhiteSpace($output)) { $output += "`n" }
        $output += $stderr
    }

    if ($exitCode -ne 0) {
        $succeeded = $false
        Emit-Error -ErrorType "AgentExecutionFailed" -Message "Agent process exited non-zero (exit code: $exitCode)" -Severity "error" -Context @{
            agent_name = $AgentConfig.name
            exit_code  = $exitCode
        }
    }
}
else {
    # Timeout occurred
    $elapsed = ((Get-Date) - $startTime).TotalSeconds
    $succeeded = $false
    $exitCode = 4

    Emit-Error -ErrorType "AgentTimeout" -Message "Agent process exceeded timeout ($timeoutSeconds seconds, elapsed: $([Math]::Round($elapsed, 1))s)" -Severity "error" -Context @{
        agent_name = $AgentConfig.name
        agent_id = $AgentConfig.id
        timeout_seconds = $timeoutSeconds
        elapsed_seconds = [Math]::Round($elapsed, 1)
        process_id = $p.Id
    }

    # Kill process tree
    try {
        Emit-Log -Level "warn" -Message "Terminating hung agent process (PID: $($p.Id))" -Component "agent"
        $p.Kill($true)  # $true = kill entire process tree
        [void]$p.WaitForExit(5000)  # Wait up to 5 seconds for cleanup
    }
    catch {
        Emit-Log -Level "debug" -Message "Process kill failed (may have already exited): $_" -Component "agent"
    }

    # Still capture partial output for debugging
    $stdout = ""
    $stderr = ""
    if (Test-Path $stdoutPath) { $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue }
    if (Test-Path $stderrPath) { $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue }

    $output = "=== TIMEOUT AFTER $timeoutSeconds SECONDS ===`n`n"
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        $output += "=== PARTIAL STDOUT ===`n$stdout`n"
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        $output += "=== PARTIAL STDERR ===`n$stderr`n"
    }
    if ([string]::IsNullOrWhiteSpace($stdout) -and [string]::IsNullOrWhiteSpace($stderr)) {
        $output += "(No output captured before timeout)"
    }
}
```

### 4. Event Emission

**New error type:** `AgentTimeout`

**Emission pattern:**

```powershell
Emit-Error -ErrorType "AgentTimeout" -Message "Agent process exceeded timeout ($timeoutSeconds seconds, elapsed: $([Math]::Round($elapsed, 1))s)" -Severity "error" -Context @{
    agent_name = $AgentConfig.name
    agent_id = $AgentConfig.id
    timeout_seconds = $timeoutSeconds
    elapsed_seconds = [Math]::Round($elapsed, 1)
    process_id = $p.Id
}
```

**Context fields:**

- `agent_name`: Which agent timed out (droid/claude/codex)
- `agent_id`: Agent ID from configuration
- `timeout_seconds`: Configured timeout value
- `elapsed_seconds`: Actual elapsed time (should be ≈ timeout)
- `process_id`: OS process ID (for manual investigation)

### 5. Documentation Updates

**File:** [AGENTS.md](../AGENTS.md)

**Add to "Agent Profiles" section:**

```markdown
### Agent Timeout

Agents have a configurable execution timeout to prevent infinite hangs:

- **Default:** 1800 seconds (30 minutes)
- **Configuration:** `.felix/config.json` → `executor.agent_timeout_seconds`
- **Behavior:** Process killed after timeout, requirement marked for manual investigation
- **Debugging:** Set to `0` for infinite timeout (not recommended for production)
```

**Update "Exit Codes" section:**

```markdown
### Exit Codes

**Felix Agent (felix-agent.ps1):**

- `0` - Success: requirement complete and validated
- `1` - Error: general execution failure (droid errors, file I/O issues)
- `2` - Blocked: backpressure failures exceeded max retries (default: 3 attempts)
- `3` - Blocked: validation failures exceeded max retries (default: 2 attempts)
- `4` - Timeout: agent process exceeded time limit (requires manual investigation)
```

---

## Edge Cases & Risks

### 1. Race Conditions

**Issue:** Process exits just before timeout check

**Mitigation:** `WaitForExit($timeout)` returns true if process exits at any point during wait. No race condition.

### 2. Process Tree Cleanup

**Issue:** Agent spawns child processes (e.g., npm, git)

**Mitigation:** `$p.Kill($true)` kills entire process tree. Second parameter = kill children.

### 3. File Handle Locks

**Issue:** Killed process may not release file handles on temp files

**Mitigation:**

- Use `-ErrorAction SilentlyContinue` when reading temp files
- Cleanup in `finally` block handles locked files gracefully
- Partial output still valuable for debugging

### 4. Exit Code Validity

**Issue:** `$p.ExitCode` only valid after `WaitForExit()` returns true

**Mitigation:** Only access `$p.ExitCode` in success branch. Timeout branch explicitly sets `$exitCode = 4`.

### 5. PowerShell Job Pool Exhaustion

**Issue:** Using `Start-Job` can exhaust job slots in PowerShell

**Mitigation:** Use direct `Start-Process` + `WaitForExit()` pattern (not jobs). More efficient, no job pool limits.

### 6. Zero Timeout Edge Case

**Issue:** Timeout=0 should mean "infinite" but `WaitForExit(0)` returns immediately

**Mitigation:** Convert 0 to `[int]::MaxValue` (effectively infinite):

```powershell
$timeoutMs = if ($timeoutSeconds -eq 0) { [int]::MaxValue } else { $timeoutSeconds * 1000 }
```

### 7. Partial Output Value

**Issue:** Output from hung process may be incomplete/corrupted

**Value:**

- For streaming agents (Droid), partial NDJSON events are still valuable
- Shows progress before hang (helps identify blocking point)
- Better than no output at all

**Format:** Prefix partial output with `=== TIMEOUT AFTER N SECONDS ===` header

---

## Testing Strategy

### Manual Testing

**Setup:**

```json
// .felix/config.json
{
  "executor": {
    "agent_timeout_seconds": 30
  }
}
```

**Test Cases:**

1. **Normal Completion (< Timeout)**
   - Run standard requirement
   - Should complete normally
   - Exit code = 0
   - No timeout events

2. **Hard Timeout**
   - Create test agent that sleeps 60 seconds
   - Should terminate after 30 seconds
   - Exit code = 4
   - `AgentTimeout` error event emitted
   - Partial output captured in `runs/*/output.log`

3. **Zero Timeout (Infinite)**
   - Set `agent_timeout_seconds: 0`
   - Run long-running requirement
   - Should complete without timeout
   - Preserves current behavior

4. **Process Exit at Timeout Boundary**
   - Create agent that exits at exactly 30 seconds
   - Should capture normal exit code
   - No false-positive timeout

5. **Streaming Agent Partial Output**
   - Use Droid with slow task
   - Trigger timeout mid-execution
   - Verify partial NDJSON events captured
   - Verify events are parseable

### Automated Testing

**Not applicable** - timeout testing requires real time delays, not suitable for CI/CD.

**Alternative:** Document manual test procedure for regression testing.

### Validation Checklist

- [ ] Default 30-minute timeout configured in config.json
- [ ] Exit code 4 added to exit-handler.ps1
- [ ] Executor uses WaitForExit pattern (no -Wait)
- [ ] Timeout kills process tree with $p.Kill($true)
- [ ] Partial output captured and prefixed with timeout header
- [ ] AgentTimeout error event emitted with full context
- [ ] AGENTS.md updated with timeout documentation
- [ ] Zero timeout = infinite (debugging use case)
- [ ] Manual test passed with 30-second timeout

---

## Implementation Checklist

### Phase 1: Core Timeout Logic

- [ ] Add `agent_timeout_seconds: 1800` to `.felix/config.json`
- [ ] Update exit code mapping in `.felix/core/exit-handler.ps1` (add case 4)
- [ ] Refactor executor.ps1 Start-Process section (remove -Wait, add WaitForExit)
- [ ] Implement timeout branch with Kill() and partial output capture
- [ ] Add AgentTimeout error emission with context

### Phase 2: Documentation

- [ ] Update AGENTS.md with timeout section
- [ ] Update AGENTS.md exit codes section
- [ ] Add inline code comments explaining timeout logic
- [ ] Document zero-timeout edge case behavior

### Phase 3: Testing

- [ ] Manual test: 30-second timeout on long-running task
- [ ] Manual test: Zero timeout (infinite) preserves current behavior
- [ ] Manual test: Normal completion under timeout threshold
- [ ] Manual test: Partial output captured on streaming agent timeout
- [ ] Verify exit code 4 propagates correctly

### Phase 4: Validation

- [ ] Code review: Edge case handling
- [ ] Code review: Process cleanup in all paths
- [ ] Code review: File handle cleanup in finally block
- [ ] Integration test: Run full requirement loop with timeout enabled
- [ ] Verify no regression in normal execution flow

---

## Future Enhancements

### Per-Agent Timeout Configuration

Allow different timeouts per agent type:

```json
// .felix/agents.json
{
  "agents": [
    {
      "id": 0,
      "name": "droid",
      "timeout_seconds": 3600 // 1 hour for complex tasks
    },
    {
      "id": 1,
      "name": "claude",
      "timeout_seconds": 1800 // 30 minutes
    }
  ]
}
```

**Fallback:** Agent-specific timeout > executor default timeout > 1800

### Timeout Warning Events

Emit warning before timeout:

```powershell
if ($elapsed -gt ($timeoutSeconds * 0.9)) {
    Emit-Warning -Message "Agent approaching timeout (${elapsed}s / ${timeoutSeconds}s)"
}
```

**Challenge:** Requires polling loop instead of blocking wait.

### Adaptive Timeout

Learn from historical execution times:

- Track average duration per requirement
- Set timeout = avg \* 2 or avg + 10 minutes (whichever is larger)
- Prevents false timeouts on legitimately slow requirements

**Storage:** Add to `.felix/metrics.json` or database

### Timeout Retry Policy

Currently: Timeout = fatal, no retry

**Enhancement:** Allow configurable retry with backoff:

```json
{
  "executor": {
    "timeout_retry_max": 1,
    "timeout_retry_backoff_seconds": 300
  }
}
```

**Use case:** Transient network issues might resolve on retry.

**Risk:** Doubles execution time on persistent hangs.

---

## Related Issues

### Network Resilience

Timeout handling addresses symptom, not root cause. Network failures should be handled by agents:

- **Droid:** Retry HTTP requests with exponential backoff
- **Claude:** Handle OAuth token refresh gracefully
- **All agents:** Emit heartbeat events during long operations

**Recommendation:** Add network resilience to agent specifications.

### Orphaned Processes

If PowerShell script is killed (Ctrl+C), agent process may become orphaned.

**Current:** No cleanup

**Enhancement:** Register trap handler for SIGINT/SIGTERM:

```powershell
trap {
    if ($p -and -not $p.HasExited) {
        $p.Kill($true)
    }
    exit 1
}
```

**Location:** [.felix/felix-agent.ps1](../.felix/felix-agent.ps1) (main entry point)

### Progress Reporting

Timeout is less critical if users see progress. Enhance event stream:

```json
{ "event": "progress", "percent": 45, "message": "Analyzing codebase..." }
```

**Agents:** Emit progress events during long operations
**CLI:** Render progress bar in rich format mode

---

## References

- [.felix/core/executor.ps1](../.felix/core/executor.ps1) - Agent execution logic
- [.felix/core/exit-handler.ps1](../.felix/core/exit-handler.ps1) - Exit code mapping
- [.felix/config.json](../.felix/config.json) - Runtime configuration
- [AGENTS.md](../AGENTS.md) - Operational documentation
- [CLI_EXEC_IMPLEMENTATION.md](CLI_EXEC_IMPLEMENTATION.md) - CLI architecture

---

**Status:** Ready for implementation
**Estimated effort:** 4-6 hours (including testing)
**Risk level:** Medium (changes core execution path)
**Rollback:** Git revert if issues detected

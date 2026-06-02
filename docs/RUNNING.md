# Running Requirements

> **Quick links:** [felix run](#felix-run) · [felix loop](#felix-loop) · [felix run-next](#felix-run-next) · [felix run replay](#felix-run-replay) · [felix procs](#felix-procs) · [Exit Codes](#exit-codes)

---

## `felix run <requirement-id>`

**What it does:** Tells the agent "work on this specific requirement until it's done or you hit a wall."

```bash
felix run S-0001
```

**When to use it:**

- You have a specific requirement ready to implement
- You want focused, controlled execution
- You're testing a new spec before letting the agent loose

**Options:**

| Flag | Description |
|---|---|
| `--format json\|plain\|rich` | Output format. Default: `rich` for interactive terminals, `json` for pipelines. |
| `--sync` | Enable artifact mirroring to the backend server for this run only. |
| `--no-commit` | Make all code changes but skip `git commit` at the end. |
| `--verbose` | Show debug-level output — prompts, state transitions, file I/O. |
| `--quiet` | Suppress info messages and progress. Only errors, warnings, and final status. |
| `--no-stats` | Skip the run statistics summary at the end. |

**Examples:**

```bash
# Execute requirement with rich terminal output (default)
felix run S-0042

# Get JSON events for parsing in scripts
felix run S-0042 --format json

# Push artifacts to backend server
felix run S-0042 --sync

# Test a spec without committing changes
felix run S-0042 --no-commit
```

**Behind the scenes:** Felix spawns `felix-agent.ps1` as a subprocess, streams NDJSON events from stdout, and renders them in your chosen format. The agent runs in a loop (up to 100 iterations by default) trying to complete the requirement: building context, calling the LLM, processing responses, running tests, committing changes, and validating success.

When sync is disabled, Felix treats non-git working directories as valid local projects. It skips git-state probing and commit capture instead of failing with repository checks.

---

## `felix loop`

**What it does:** Autonomously processes all planned/in-progress requirements until the backlog is empty or you stop it.

```bash
felix loop
```

**When to use it:**

- Friday afternoon before the weekend (let it work while you're gone)
- You have 20 small requirements and don't want to babysit each one
- You trust your specs and backpressure tests

**When NOT to use it:**

- Your specs are half-baked or vague
- You haven't validated your test suite catches regressions
- It's Monday morning and your boss wants a demo at 10 AM

**Options:**

| Flag | Description |
|---|---|
| `--max-iterations N` | Stop after processing N requirements. |
| `--sync` | Continuously sync artifacts to the backend server. |
| `--no-commit` | Skip git commits on completion (useful for reviewing before committing). |
| `--format json\|plain\|rich` | Output format. |

**Examples:**

```bash
# Limit to 5 requirements then stop
felix loop --max-iterations 5

# Continuously sync artifacts to backend
felix loop --sync

# Skip git commits (useful for reviewing before committing)
felix loop --no-commit
```

**Pro tip:** Loop mode creates lock files in `.felix/.locks/loop-<PID>.lock` to prevent multiple loops from colliding. If Felix crashes and leaves a stale lock, you'll need to manually clean it up.

**War story:** We once let `felix loop` run overnight on a fresh project with 30 requirements. Came back to find 28 complete, 1 blocked (flaky test), and 1 in a hilarious infinite loop arguing with itself about whether a function should be async or not. Lesson learned: always write clear acceptance criteria.

> For **parallel workers**, see [CONCURRENCY.md](CONCURRENCY.md) — `felix loop --parallel N [--worktrees]`.

---

## `felix run-next`

**What it does:** Finds the next available requirement and runs it immediately — server-assigned in team mode, locally-picked in solo mode.

```bash
felix run-next
felix run-next --sync    # enable sync for this run
felix run-next --format json
```

**Remote mode** (sync enabled): calls `GET /api/sync/work/next` — atomic, `FOR UPDATE SKIP LOCKED` so multiple agents on the same project never claim the same item. Marks it `reserved`, then transitions to `in_progress` when the agent starts.

**Local mode**: picks the next `in_progress` then `planned` requirement from `requirements.json`, sorted by ID.

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | Requirement completed successfully |
| `2`/`3` | Blocked — claim auto-released back to `planned` |
| `5` | No work available — nothing planned or already all claimed |

The `5` exit code is designed for CI poll loops:

```powershell
while ($true) {
    felix run-next --sync
    if ($LASTEXITCODE -eq 5) { Start-Sleep 60 }  # nothing to do, wait
    elseif ($LASTEXITCODE -ne 0) { break }        # error or block needs attention
}
```

---

## `felix run replay <run-id>`

Re-open the exact prompt artifact that was sent to the model for a past run. Read-only — does not re-execute the agent.

```powershell
felix run replay <run-id>
felix run replay <run-id> --iteration <N>
```

| Argument/Flag | Description |
|---|---|
| `<run-id>` | Run directory name (e.g., `S-0001-20260601-143022-it1`). |
| `--iteration N` | Open the prompt for iteration N. Defaults to the last iteration. |

**What it opens:** `runs/<run-id>/iteration-<N>/prompt.txt` in `$EDITOR` (falls back to `notepad`).

**Why:** When an agent produces unexpected output, `replay` lets you read the exact context it received — diagnose truncated specs, wrong skill loading, or missing memory entries.

> See [CONTEXT.md](CONTEXT.md) for the full replay reference, run artifact layout, and how to debug with run history.

---

## `felix procs`

**What it does:** Shows all currently running Felix agent processes tracked in `.felix/sessions.json`.

```bash
felix procs
felix procs list
```

**Shows:**

- Session ID (run identifier)
- Requirement being executed
- Agent name
- Process ID (PID)
- Running duration
- Status (running/paused)

**Example output:**

```
Active Sessions:

  Session: S-0042-20260217-143022-it1
  Requirement: S-0042
  Agent: droid
  PID: 18432
  Duration: 12:34
  Status: running
```

**Why this matters:** Sometimes you spawn `felix loop` in a background terminal and forget about it. `felix procs` shows you it's still churning away.

---

## `felix procs kill <session-id>`

**What it does:** Force-terminates tracked agent processes and removes their entries from `.felix/sessions.json`.

```bash
felix procs kill S-0042-20260217-143022-it1

# Kill all running sessions at once
felix procs kill all
```

- `felix procs kill <session-id>` stops one tracked session
- `felix procs kill all` stops every tracked session in the repo
- Stale session records are cleaned up automatically when Felix reads `.felix/sessions.json`

**When you need this:**

- Agent is stuck in an infinite loop
- You realized the spec is wrong mid-execution
- You need to free up CPU/memory for something else

**Safety:** This is a force stop of the tracked process tree, not a graceful "finish the current iteration" shutdown. Use it when you want the session gone now.

---

## Exit Codes

Felix uses exit codes to communicate status in scripts and CI:

| Code | Meaning | What to Do |
|---|---|---|
| `0` | Success | Requirement complete, tests pass, validated |
| `1` | Error | Agent crashed, unexpected failure, infrastructure issue |
| `2` | Blocked (Backpressure) | Tests failed 3 times, agent gave up |
| `3` | Blocked (Validation) | Acceptance criteria failed 2 times |
| `5` | No Work Available | Nothing planned — used by `felix run-next`; safe in CI |

**Why this matters for automation:**

```powershell
felix run S-0042
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    # Success - deploy to staging
    deploy-to-staging
}
elseif ($exitCode -eq 2 -or $exitCode -eq 3) {
    # Blocked - manual intervention needed
    send-slack-notification "S-0042 blocked, needs attention"
}
else {
    # Error - retry later
    schedule-retry
}
```

**Unblocking requirements:**

When Felix exits with code 2 or 3, it marks the requirement as "blocked" in `.felix/requirements.json`. To unblock:

1. Fix the underlying issue (broken tests, wrong acceptance criteria)
2. Edit `.felix/requirements.json` and change status from `"blocked"` to `"planned"`
3. Run Felix again — it will pick up the unblocked requirement

**Common causes:**

- Exit 2: Flaky tests, missing test data, environment issues
- Exit 3: Vague acceptance criteria, feature genuinely incomplete

---

*See also: [SPECS.md](SPECS.md) for requirement management and validation · [CONTEXT.md](CONTEXT.md) for run artifacts and replay · [CONCURRENCY.md](CONCURRENCY.md) for parallel workers · [CLI.md](CLI.md) for global options and the full command index*

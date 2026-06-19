# The Felix CLI

> **Quick links:** [Command Index](#command-index) Â· [Global Options](#global-options) Â· [felix tui](#felix-tui) Â· [Operating Modes](#operating-modes) Â· [Best Practices](#best-practices)

---

## Mental Model

Felix runs an **autonomous loop**, not a chat.

- Loads a small set of files each iteration
- Runs in either planning or building mode
- Produces one concrete outcome
- Updates state on disk
- Continues to next task

**Felix runs to completion by default.** You start it, it finishes the work, then stops.

All memory lives in files, not conversation state:

- You can stop and resume anytime
- Progress is visible in git commits
- No chat history to maintain
- State is inspectable and recoverable

---

## Repository Layout

A Felix-enabled repository typically looks like this:

```
.
â”œâ”€â”€ specs/                         # Requirements (markdown)
â”‚   â”œâ”€â”€ CONTEXT.md
â”‚   â””â”€â”€ auth-email-signin.md
â”œâ”€â”€ AGENTS.md                      # How to run the system
â”œâ”€â”€ .felix/
â”‚   â”œâ”€â”€ requirements.json          # Central registry and status
â”‚   â”œâ”€â”€ state.json                 # Agent control state
â”‚   â”œâ”€â”€ config.json                # Sync, agent, executor settings
â”‚   â”œâ”€â”€ agents.json                # LLM agent profiles
â”‚   â”œâ”€â”€ sessions.json              # Active process tracking
â”‚   â”œâ”€â”€ outbox/                    # Sync queue (when enabled)
â”‚   â”œâ”€â”€ prompts/
â”‚   â”‚   â”œâ”€â”€ planning.md
â”‚   â”‚   â””â”€â”€ building.md
â”‚   â””â”€â”€ plugins/
â”‚       â””â”€â”€ sync-http/             # HTTP sync plugin
â”œâ”€â”€ runs/
â”‚   â””â”€â”€ <run-id>/
â”‚       â”œâ”€â”€ plan-<req-id>.md       # Working plan
â”‚       â”œâ”€â”€ commands.log.jsonl     # Execution log
â”‚       â”œâ”€â”€ diff.patch             # Git diff
â”‚       â””â”€â”€ report.md             # Run summary
â””â”€â”€ app/                           # Your application code
```

---

## Core Concepts

Felix separates **content**, **structure**, and **action**:

- **Markdown** holds meaning (specs, plans, context)
- **JSON** holds structure and status (requirements.json, state.json)
- **Plans** hold next actions (per-requirement, disposable)
- **Sync** (optional) mirrors artifacts to server for team visibility

### Specs (`specs/`)

One topic per file. Narrow scope. No implementation detail. Stable over time.

**Good filenames:** `auth-email-signin.md`, `billing-invoice-download.md`
**Bad:** a single giant PRD, files mixing requirements and task lists.

### Requirements Registry (`.felix/requirements.json`)

Slim index â€” only what Felix needs to schedule and track work. **Status values:** `draft` â†’ `planned` â†’ `in_progress` â†’ `complete` / `blocked`. Rich metadata (`priority`, `tags`, `depends_on`) lives in `specs/*.meta.json` sidecars.

See [SPECS.md](SPECS.md) for the full registry format, `felix spec` commands, and validation criteria rules.

---

## Command Index

| Command | What it does | Reference |
|---|---|---|
| `felix run` | Execute one requirement | [RUNNING.md](RUNNING.md) |
| `felix loop` | Continuous execution loop | [RUNNING.md](RUNNING.md) |
| `felix run-next` | Claim and run next queued requirement | [RUNNING.md](RUNNING.md) |
| `felix run replay` | Re-run a saved iteration | [RUNNING.md](RUNNING.md) |
| `felix procs` | View running agent processes | [RUNNING.md](RUNNING.md) |
| `felix spec` | Create, manage, sync specs | [SPECS.md](SPECS.md) |
| `felix validate` | Run acceptance criteria | [SPECS.md](SPECS.md) |
| `felix list` | List requirements and status | [SPECS.md](SPECS.md) |
| `felix status` | Show requirement status | [SPECS.md](SPECS.md) |
| `felix setup` | Interactive project wizard | [SETUP.md](SETUP.md) |
| `felix agent` | Manage agent profiles | [SETUP.md](SETUP.md) |
| `felix tool` | Tool allowlist management | [SETUP.md](SETUP.md) |
| `felix migrate` | Schema migration | [SETUP.md](SETUP.md) |
| `felix doctor` | Health check | [SETUP.md](SETUP.md) |
| `felix gc` | Garbage collection | [SETUP.md](SETUP.md) |
| `felix update` | Update the CLI | [SETUP.md](SETUP.md) |
| `felix context` | Context inspection, build, push/pull | [CONTEXT.md](CONTEXT.md) |
| `felix event` | Event stream | [CONTEXT.md](CONTEXT.md) |
| `felix search` | Full-text search | [SEARCH.md](SEARCH.md) |
| `felix deps` | Dependency graph | [SEARCH.md](SEARCH.md) |
| `felix query` | Structured state query | [SEARCH.md](SEARCH.md) |
| `felix memory` | Agent memory management | [MEMORY.md](MEMORY.md) |
| `felix skill` | Skill management | [SKILLS.md](SKILLS.md) |
| `felix plugin` | Plugin management | [PLUGINS.md](PLUGINS.md) |
| `felix loop --parallel` | Parallel workers | [CONCURRENCY.md](CONCURRENCY.md) |
| `felix recover` | Crash recovery | [CONCURRENCY.md](CONCURRENCY.md) |
| `felix tui` | Interactive terminal shell | *(below)* |
| `felix version` | Show version | [SETUP.md](SETUP.md) |
| `felix help` | Command reference | [SETUP.md](SETUP.md) |

---

## Global Options

These flags work with every command.

### `--format <json|plain|rich>`

| Value | Description |
|---|---|
| `rich` (default) | Progress indicators, colored output, formatted tables |
| `plain` | Simple colored text â€” good for log files and basic CI |
| `json` | One JSON object per line â€” perfect for scripting and pipelines |

### `--verbose`

Debug-level output: state transitions, LLM prompt construction, file I/O, git commands. **Warning:** very chatty.

### `--quiet`

Suppresses info messages, progress indicators, and statistics. Only errors, warnings, and final status are shown. Use for background jobs and cron tasks.

### `--no-stats`

Suppresses the run statistics summary (`Events`, `Errors`, `Duration`, etc.) at the end of a run. Useful with `--format json` to avoid breaking parsers.

### `--sync`

Enables artifact mirroring to a remote backend for this run only, overriding `sync.enabled` in `.felix/config.json`.

**What gets synced:** agent registration, run creation, full NDJSON event stream, output files (logs, diffs, reports), run completion.

**Configuration hierarchy:** `--sync` flag (highest) â†’ `$env:FELIX_SYNC_ENABLED` â†’ `.felix/config.json`

```powershell
# Override for one run
felix run S-0001 --sync

# Production automation
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.company.com"
$env:FELIX_SYNC_KEY = "fsk_prod_key_here"
felix loop
```

See [SYNC_OPERATIONS.md](SYNC_OPERATIONS.md) for full sync configuration and troubleshooting.

### `--no-commit`

Agent makes all code changes but skips `git commit` at the end. Useful for testing specs and reviewing output before committing:

```bash
felix run S-0001 --no-commit --format plain | tee test-output.log
# Review, then either:
git add -A && git commit -m "Implement S-0001 (manually verified)"
# or:
git reset --hard
```

### `--quick`

Used with `felix spec create` â€” skips interactive prompts, defaults everything to `planned` with minimal frontmatter. Useful for batch-creating 20+ requirements quickly.

---

## `felix tui`

```bash
felix tui
felix dashboard   # alias
```

Launches an interactive terminal UI (built with .NET/Spectre.Console) providing:

- A bordered welcome and status card on initial load
- Header visibility for captured token/model usage, model count, cache-read tokens, and pricing configuration status
- A Copilot-style slash-command composer at the bottom while typing
- Scrollback-first command output so prior content remains visible in the terminal
- Slash suggestions for commands and common requirement arguments

**Navigation:**

| Key | Action |
|---|---|
| `/` | Start a slash command and open command suggestions |
| `Up`/`Down` | Move through the visible suggestion window |
| `Enter` | Accept the highlighted suggestion or run the current input |
| `Esc` | Cancel the current prompt or suggestion list |
| `Backspace` | Delete input, or cancel when the prompt is empty |

**Common commands:** `/help` Â· `/status` Â· `/list` Â· `/run <id>` Â· `/run-next` Â· `/validate <id>` Â· `/deps <id>` Â· `/query usage` Â· `/setup` Â· `/quit`

**Notes:**
- Output is appended below each command (terminal scrollback is preserved)
- Some commands take over the terminal directly, then return when they finish (`/run`, `/run-next`, `/loop`, `/setup`, `/procs kill`)
- .NET SDK (`dotnet` CLI) must be installed â€” TUI is the C# `src/Felix.Cli` project

---

## Operating Modes

Felix runs in one of two modes depending on `sync.enabled` in `.felix/config.json`.

### Local Mode (default)

No server required. Everything runs from local files.

- Work selection reads `requirements.json` directly
- `in_progress` requirements resume first, then `planned`, sorted by ID
- Dependencies (`depends_on`) read from `specs/*.meta.json` sidecars or inline in `requirements.json`
- No network calls during the agent loop

```json
{ "sync": { "enabled": false } }
```

### Remote / Team Mode

Requires a running Felix backend. Enables server-side work allocation so multiple agents can collaborate on the same project without stepping on each other.

```json
{
  "sync": {
    "enabled": true,
    "base_url": "http://localhost:8080",
    "api_key": "fsk_..."
  }
}
```

**How work allocation works:**

1. `felix loop` calls `GET /api/sync/work/next` instead of scanning `requirements.json`
2. Server uses `FOR UPDATE SKIP LOCKED` to atomically assign a requirement to one agent
3. Returns 204 when nothing is available â€” loop idles and retries
4. If the agent is blocked (exit code 2 or 3), it calls `POST /api/sync/work/release` to return the requirement to the queue for another agent

**Typical remote mode workflow:**

```bash
felix spec pull           # Get latest specs and metadata from server
felix loop                # Start the autonomous loop (uses server work allocation)
# Terminal 2 â€” second agent works in parallel on different requirements
felix loop
```

**Environment variable overrides** (useful for CI/CD):

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL     = "https://felix.company.com"
$env:FELIX_SYNC_KEY     = "fsk_prod_key_here"
felix loop
```

---

## Lessons Learned: Bugs, Pitfalls, and War Stories

### The Case of the Stale Lock File

**Symptom:** Felix refuses to start with "Another process is running."

**Cause:** Agent crashed mid-run and left a `.felix/run.lock` file.

**Solution:** Check for stale processes first:

```powershell
felix procs list
```

If nothing running:

```powershell
Remove-Item .felix/run.lock
```

**Prevention:** Felix now detects stale locks (PID no longer exists) and cleans them automatically. But if you `kill -9` the process, you might still hit this.

### The ProcessStartInfo Inheritance Bug

**The Bug:** Added `--sync` flag, but environment variable wasn't reaching the subprocess.

**Root cause:**

```csharp
var startInfo = new ProcessStartInfo("pwsh", args);
// Looks like environment is inherited, right?
startInfo.Environment["FELIX_SYNC_ENABLED"] = "true";
// WRONG: Default environment is EMPTY, not inherited!
```

**The fix:**

```csharp
// Must COPY parent environment first
foreach (DictionaryEntry env in Environment.GetEnvironmentVariables()) {
    startInfo.Environment[env.Key.ToString()] = env.Value.ToString();
}
// NOW we can add our variable
startInfo.Environment["FELIX_SYNC_ENABLED"] = "true";
```

**Lesson:** Always check subprocess default behavior. "Inherited" doesn't mean what you think.

### The Arrow Character Encoding Disaster

**The Bug:** Console output showed `Ã¢â‚¬"` instead of `â†’` on some systems.

**Root cause:** UTF-8 string written to console configured for ASCII or Windows-1252.

**The fix:**

```powershell
# Must be in this exact order for Windows PowerShell 5.1
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

**Pragmatic solution:** Changed `â†’` to `->` in output messages. Not pretty, but works everywhere.

**Lesson:** Unicode support in terminal apps is a minefield. ASCII-safe characters or emojis (which Windows handles better for some reason) are safer than fancy arrows.

### The Path Shadowing Mystery

**The Bug:** CLI agents registered successfully, but database showed NULL for metadata fields.

**Debugged for hours:** API returned 200 OK, database schema was correct, payload looked valid.

**Smoking gun:** Both `routers/agents.py` and `routers/sync.py` defined `/api/agents/register`.

**FastAPI behavior:** Registers routes in order. First definition wins. Later definitions silently ignored.

**What happened:**

1. `sync.router` registered first with `/api/agents/register` (simple upsert)
2. `agents.router` registered second with same path (full auth, metadata handling)
3. CLI called `/api/agents/register` â†’ routed to sync endpoint (no metadata support)
4. No error because the endpoint exists, just wrong implementation

**The fix:** Removed redundant endpoint, unified on single authenticated route.

**Lesson:** Name your endpoints uniquely or review route registration carefully. FastAPI won't warn about shadowing.

### The UUID Type Mismatch Saga

**The Bug:** Agent registration worked, then crashed on exit: "Cannot convert int to UUID."

**Original design:** Agent IDs were integers (0, 1, 2, 3).

**Database migration:** Changed agents.id column to UUID for scalability.

**Migration script:** Updated `.felix/agents.json` to use UUIDs.

**What we forgot:** 20+ PowerShell functions had `[int]$AgentId` parameters.

**The cascade:**

1. Load config: agent_id is now string "39535ce5-..."
2. PowerShell sees `[int]$AgentId` â†’ tries to cast string to int â†’ fails silently, uses $null
3. Agent runs successfully (default fallback mechanisms)
4. Exit handler tries to unregister: `Unregister-Agent -AgentId $null`
5. Backend: "uuid field cannot be null" â†’ 500 error â†’ crash

**The fix:** Changed every `[int]$AgentId` to `[string]$AgentId` across 5 files.

**Lesson:** When changing a core data type, grep the entire codebase for type hints. PowerShell's lenient casting can hide bugs until production.

### The Infinite Spec-Build Loop

**The Bug:** User runs `felix spec create`, agent generates criteria, saves file, detects changes, asks "want to commit?", user says yes, agent commits, then asks again, loops forever.

**Root cause:** Agent was detecting its own git commit as "new changes" and re-entering the commit flow.

**The fix:** Track last known git state, only prompt if working tree is dirty AND different from last check.

**Lesson:** State machines need memory. "Are there changes?" depends on "compared to when?"

### The 422 Validation Error Mystery

**The Bug:** Sync registration returned 422 Unprocessable Entity with cryptic message.

**Payload looked fine:** All required fields present, types correct.

**FastAPI validation error detail:**

```json
{
  "detail": [
    {
      "loc": ["body", "name"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

**What?** We were sending `agent_id` and `hostname`, not checking `name`.

**The fix:** Backend model expected optional `name` field, but validation middleware required it. Made it truly optional with default.

**Lesson:** FastAPI validation errors are your friend. Read them carefully. `"loc"` tells you exactly which field failed.

---

## Best Practices: How Good Engineers Use Felix

### 1. Write Testable Acceptance Criteria

**Bad:**

```markdown
- [ ] User authentication works
```

**Good:**

```markdown
- [ ] Login endpoint responds: `curl -X POST http://localhost:3000/api/auth/login -d '{"username":"test","password":"test"}' -H "Content-Type: application/json"` (status 200)
- [ ] Invalid credentials rejected: `curl -X POST http://localhost:3000/api/auth/login -d '{"username":"test","password":"wrong"}' -H "Content-Type: application/json"` (status 401)
- [ ] Auth tests pass: `pytest tests/test_auth.py` (exit code 0)
```

### 2. Start Small, Iterate

**Don't:**

```bash
# Write 50 requirements
# Run felix loop
# Go on vacation
# Come back to 47 failures
```

**Do:**

```bash
# Write 3 requirements
# Run felix run S-0001
# Verify it works
# Adjust your spec style based on what worked
# Write 5 more requirements
# Run felix loop --max-iterations 5
# Verify those work
# Now scale up
```

### 3. Use Quick Mode for Batch Creation

When you have a mental model of 20 small requirements:

```powershell
# Create them all with --quick
felix spec create "Add user login" --quick
felix spec create "Add password reset" --quick
felix spec create "Add email verification" --quick
# ... 17 more ...

# Go back and flesh out details for complex ones
code specs/S-0042-*.md
code specs/S-0051-*.md
```

### 4. Monitor Long-Running Loops

Don't just fire and forget:

```powershell
# Terminal 1: Run the loop
felix loop --sync

# Terminal 2: Watch progress
watch -n 30 'felix status'

# Terminal 3: Check for blockages
felix deps --incomplete
```

### 5. Use Sync Strategically

**Local dev:** No sync (fast, no network dependency)

```bash
felix run S-0001
```

**Integration environment:** Sync for troubleshooting

```bash
felix run S-0001 --sync
```

**Production automation:** Always sync

```powershell
$env:FELIX_SYNC_ENABLED = "true"
felix loop
```

### 6. Version Your Agents.json

Track agent configuration changes in git:

```bash
git add .felix/agents.json
git commit -m "Switch default agent to claude for better reasoning"
```

Why? When a requirement fails, you want to know which agent ran it and with what configuration.

### 7. Archive Old Runs

Run artifacts accumulate fast. Periodically prune with `felix gc`:

```powershell
felix gc --dry-run   # See what would be pruned
felix gc --yes       # Prune without confirmation
```

Or archive manually:

```powershell
$cutoff = (Get-Date).AddDays(-30)
Get-ChildItem runs/* | Where-Object { $_.CreationTime -lt $cutoff } | Move-Item -Destination archive/runs/
```

### 8. Test Acceptance Criteria Manually First

Before letting the agent work on a requirement:

```bash
# Run the validation commands yourself
python main.py  # Does it start?
curl http://localhost:3000/health  # Does the endpoint work?
pytest tests/  # Do the tests pass?

# If any fail, your criteria are wrong
felix validate S-0042  # Confirm with the validator
```

---

## Common Workflows

### The "Sprint Planning" Workflow

**Monday morning:**

```bash
# Review what's ready
felix spec list --status planned

# Check dependencies
felix deps --tree

# Start the first batch
felix run S-0042
felix run S-0043
felix run S-0044
```

### The "Continuous Integration" Workflow

**CI/CD pipeline:**

```yaml
# .github/workflows/felix.yml
- name: Run Felix requirements
  run: |
    felix loop --max-iterations 10 --format json --sync
  env:
    FELIX_SYNC_ENABLED: "true"
    FELIX_SYNC_URL: ${{ secrets.FELIX_BACKEND_URL }}
    FELIX_SYNC_KEY: ${{ secrets.FELIX_API_KEY }}
```

### The "Overnight Batch" Workflow

**Before leaving Friday:**

```bash
# Start loop in background
nohup felix loop --sync > felix-loop.log 2>&1 &

# Check progress Monday morning
felix status
grep -i error felix-loop.log
felix spec list --status blocked
```

### The "Emergency Fix" Workflow

**Production is down, need quick fix:**

```bash
# Create requirement
felix spec create "Fix authentication timeout issue" --quick

# Edit spec with exact criteria
code specs/S-0078.md

# Run focused execution, no distractions
felix run S-0078 --format plain --no-stats

# Verify fix
felix validate S-0078

# Deploy
git push
```

---

## Debugging Guide: When Things Go Wrong

### Felix Won't Start

**Error:** "Another process is running"

**Check:**

```bash
felix procs list
```

**Fix if stale:**

```bash
Remove-Item .felix/run.lock
```

### Agent Loops Forever

**Check:**

```bash
# See what it's doing
felix status S-0042 --format json | jq .current_iteration

# If iteration count keeps growing...
felix procs kill <session-id>
```

**Common causes:**

- Vague acceptance criteria that are never satisfied
- Flaky tests that sometimes pass/fail
- Agent making changes that break tests in a cycle

### Sync Not Working

**Symptoms:** No artifacts appear in backend

**Check local queue:**

```powershell
Get-ChildItem .felix\outbox\*.jsonl | Measure-Object
```

**If empty:** Sync disabled or failing silently

**If hundreds:** Network issue or backend down

**Test backend connectivity:**

```powershell
curl http://localhost:8080/health
```

**Enable debug logging:**

```powershell
felix run S-0001 --sync --verbose 2>&1 | Select-String -Pattern "sync"
```

### Validation Fails But Looks Correct

**Problem:** Acceptance criteria look right, but validation fails

**Debug:**

```bash
# Run validation with verbose output
felix validate S-0042 --verbose

# Manually run the failing command
python main.py  # Does it actually work?

# Check for environmental issues
echo $PATH
which python
python --version
```

**Common gotchas:**

- Wrong Python version
- Missing environment variables
- Database not running
- Port already in use

---

## Going Deeper

The `tuts/` directory contains architecture deep dives written alongside the codebase:

| File | Description |
|---|---|
| [tuts/FELIX_EXPLAINED.md](../tuts/FELIX_EXPLAINED.md) | Accessible intro â€” the "tiny brain, big clipboard" mental model, full architecture tour |
| [tuts/EXECUTION_FLOW.md](../tuts/EXECUTION_FLOW.md) | Detailed execution flow with Mermaid diagram â€” planning mode guardrails, backpressure, git snapshot |
| [tuts/MULTI_AGENT_SUPPORT.md](../tuts/MULTI_AGENT_SUPPORT.md) | Full adapter pattern docs for all 4 LLM profiles |
| [tuts/SWITCHING_AGENTS.md](../tuts/SWITCHING_AGENTS.md) | Step-by-step agent switching guide |
| [tuts/sync/README.md](../tuts/sync/README.md) | 9-chapter sync system deep dive â€” outbox pattern, plugin internals, production ops |

---

## Conclusion: The Felix Philosophy

Felix is different from traditional tools because it's designed for **iterative autonomous execution** rather than one-shot commands. The switches and options reflect this:

- **`--sync`** exists because long-running agents need observability
- **`--quick`** exists because batch creation matters at scale
- **`--no-commit`** exists because testing agents is different from trusting them
- **Exit codes** communicate more than pass/fail; they tell you WHY it failed

The best way to learn Felix is to use it on a real project. Start with one simple requirement, watch what the agent does, adjust your specs based on what works, then scale up.

Remember: Felix is a junior developer. Give it clear instructions, testable criteria, and guard rails (backpressure tests), and it will happily churn through work while you focus on architecture and design.

Happy automating! ðŸš€

---

*See also: [RUNNING.md](RUNNING.md) Â· [SPECS.md](SPECS.md) Â· [SETUP.md](SETUP.md) Â· [CONTEXT.md](CONTEXT.md) Â· [SEARCH.md](SEARCH.md) Â· [MEMORY.md](MEMORY.md) Â· [SKILLS.md](SKILLS.md) Â· [PLUGINS.md](PLUGINS.md) Â· [CONCURRENCY.md](CONCURRENCY.md) Â· [SYNC_OPERATIONS.md](SYNC_OPERATIONS.md) Â· [CONFIGURATION.md](CONFIGURATION.md)*

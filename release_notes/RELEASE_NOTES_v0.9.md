# Release Notes - v0.9.0

## Highlights

- **🤖 Content-addressed agent keys** - Agents are identified by a deterministic key derived from their config, eliminating manual UUID wrangling
- **📝 `felix agent register`** - Register the local agent with the sync server in one command
- **🔄 `felix run-next`** - Claim and run the next queued requirement automatically
- **⚙️ Improved `felix setup`** - Interactive LLM agent configuration, local/remote mode choice, and config template scaffolding
- **📦 Spec split** - `spec-pull` and `spec-fix` are now separate commands with `--force` support
- **📋 Server work allocation** - Reserved/in-progress claim split, sticky re-assignment, and automatic release on block
- **🖥️ TUI overhaul** - Searchable menus, bordered input panel, direct JSON reads (faster), full command list in menu
- **🌍 Global installer** - Scripts embedded in `felix.exe`; cross-platform `install.ps1` / `install.sh`
- **🎨 Frontend polish** - Kanban table view with bulk remap, compact run cards, spec slide-out, run detail tooltips

---

## New Features

### Content-Addressed Agent Keys

Agent identity is now derived from config rather than assigned manually.

**Key formula:** `ag_` + first 9 chars of `sha256("{provider}::{model}::{}::{machine}::{git_url}")`

- Keys are stable across machines for the same config
- `agents.json` no longer requires manual UUIDs — only `provider`, `model`, and `name`
- `felix setup` writes a correctly-shaped `agents.json` automatically
- Backend validates submitted key against recomputed value to prevent spoofing

```json
// .felix/agents.json
[
  { "name": "droid", "provider": "openai", "model": "o3-mini" }
]
```

---

### `felix agent register`

Registers the current agent profile with the sync server.

```powershell
felix agent register
```

- Shows the target URL and API key prefix before attempting
- Prompts to proceed when sync is disabled in config
- Allows key override before each attempt
- Surfaces backend error detail on failure (key mismatch, git URL mismatch, etc.)
- Safe to re-run — uses `ON CONFLICT (key) DO UPDATE` so repeated calls just refresh metadata

---

### `felix run-next`

Claims the next queued requirement from the server (or local `requirements.json`) and immediately runs it.

```powershell
felix run-next
felix run-next --local   # skip server, use local queue only
```

- Fetches next `planned` requirement via `GET /work/next`
- Marks it `reserved` then `in_progress` before starting the agent
- Releases the claim back to the queue if the agent exits blocked or with an error

---

### Improved `felix setup`

Setup is now a guided wizard:

1. Confirms target project folder
2. Asks for local or remote (server-backed) mode
3. In remote mode: prompts for server URL, git URL, and API key
4. Runs `spec pull` + `spec fix` to bootstrap requirements from server
5. **Interactive LLM agent configuration** — prompts for provider and model, writes `agents.json`
6. Scaffolds `policies/`, `specs/`, and supporting files from `config.json.example` template
7. Prompts for test command and mode

---

### Spec Commands Split

`spec.ps1` has been split into two focused commands:

| Command | What it does |
|---|---|
| `felix spec pull` | Downloads specs from server to local `specs/` directory |
| `felix spec fix` | Validates and repairs `requirements.json` from local spec files |

**New in spec pull:**
- `--force` flag overwrites local untracked files
- Hints to run `spec fix` when new files are downloaded
- Reads `status` from `.meta.json` sidecars if present

**Slim `requirements.json` schema** — only `id`, `spec_path`, and `status` fields. Optional fields (`priority`, `tags`, `depends_on`) moved to `.meta.json` sidecars.

---

### Server Work Allocation

Work claiming is now a two-phase protocol:

1. **`reserved`** — `GET /work/next` claims the slot (prevents double-assignment)
2. **`in_progress`** — `POST /work/start` transitions when agent begins active work

Additional changes:
- **Sticky re-assignment** — `work/next` returns the same requirement if the agent already has one reserved or in-progress
- **Auto-release on block** — if the agent exits due to backpressure or validation failure, the claim is released back to `planned`
- `requirements.assigned_to` is now a plain `TEXT` field (no FK constraint), so agents don't need to be pre-registered to claim work

---

### Global Installer

`felix.exe` now embeds all engine scripts in a zip resource at build time.

```powershell
# Install globally (once)
irm https://felixai.dev/install.ps1 | iex   # Windows
curl -sSL https://felixai.dev/install.sh | bash   # macOS/Linux

# Then in any project
felix setup
```

- `felix install` extracts scripts to `~/.local/share/felix` (or equivalent)
- `felix setup` scaffolds `.felix/` from the installed engine — no per-project copies of engine files
- Prompts resolve from install dir via `$PSScriptRoot`, not per-project copy

---

## Improvements

### CLI Reliability

- **Generic command passthrough** — unknown verbs are forwarded to the PowerShell dispatcher rather than rejected by `[ValidateSet]`, so new commands don't require a C# rebuild
- **Unified help routing** — `felix help <cmd>` routes to `<cmd> --help`; unknown help topics show top-level help
- **Version bump warning** — `build-and-install.ps1` warns if any `.ps1`/`.json`/`.md` files are newer than `version.txt`
- **Command registry check** — build script validates that all command files, C# registrations, and help entries are consistent

### TUI (Terminal Dashboard)

- **Bordered input panel** with `>` prompt indicator
- **Searchable + back-able selection menus** for requirement and command choice
- **Full command list** — `loop`, `spec pull`, `spec fix`, `context`, `setup` now appear in TUI menu
- **Performance** — requirements read directly from `requirements.json` (eliminates PS subprocess spawns)
- Fixed `KeyNotFoundException` when spec title was missing (falls back to `spec_path`)
- Fixed layout corruption caused by `AnsiConsole.Status()` spinner running alongside table renders

### Session Management

- `felix procs kill all` terminates all active Felix sessions in one step
- Improved error handling and user feedback in session stop flow

### Frontend / UI

- **Kanban table view** — switch between card and table layout; bulk status remap with `FilterPopover` and confirm dialog
- **Compact run cards** — natural language title, three-line layout, JSON log rendering
- **Spec slide-out** — click a requirement in the queue to view its spec inline
- **Run detail** — fixed-height event rows with truncation and hover tooltip; run details tooltip on run cards
- **Live Fleet health** — agent blocks show Bot icon and tooltip
- **Domain folders** — components reorganised into `requirements/`, `runs/`, `agents/`, `settings/`, `shared/`
- Display `Code` column instead of `ID` in specifications table

### Sync / Backend

- `RegisterAgent` now returns full `{Success, Error}` detail — backend error messages (key mismatch, git URL mismatch, DB errors) surface directly in the CLI output
- `create_agent` auto-generates UUID when none supplied — removes the dual INSERT query branches that caused `"text() construct doesn't define a bound parameter named 'id'"` errors
- Fixed `asyncpg.Record` accessed via `.get()` during run creation (use bracket syntax)
- Event pipeline: buffered pre-init events, expanded critical event list, fixed timer `PSScriptRoot` in action block
- Heartbeat: 15 s interval, project validation, proper auth wiring
- Dropped `run_events.type` CHECK constraint so all agent event types reach the DB

---

## Bug Fixes

| Area | Fix |
|---|---|
| CLI encoding | Replace em-dashes and non-ASCII characters throughout PS scripts (Windows-1252 misparse) |
| CLI passthrough | `[ValidateSet]` removed from `felix.ps1`; unknown commands no longer hard-fail |
| `run-next` | Fix named param invocation; default `formatValue` to `rich`; `Join-Path` chain for PS 5.1 |
| `spec fix` | Exits 0 on success, 1 on errors; emits slim schema only |
| TUI | `ReadRequirementsJson` unwraps `{requirements:[]}` wrapper format |
| TUI | Guard `EnumerateArray` and `JsonDocument.Parse` against empty/non-array roots |
| TUI | Restore cursor below panel after keypress |
| Setup | Copy engine files instead of hardcoding content; smart-quote parse errors fixed |
| Setup | Scaffold is idempotent — always fills missing files, adds `policies/` and `specs/` |
| Installer | Clean up legacy PS profile entries from old `install-cli.ps1` |
| Agent config | Streamline `agents.json` — remove unused fields, simplify executable verification |
| Backend | `requirements.assigned_to` changed from UUID FK to TEXT (no prior agent registration needed) |
| Backend | Fix FK error on setup: ensure dev project exists before migration scripts |
| Backend | Fix seed migration: add missing `git_url` to projects insert |
| Backend | Fix auth/rate-limit on read endpoints; dynamic artifact categories |
| Codex adapter | Use `danger-full-access` flag for write access (required since Codex v0.98.0) |

---

## Upgrade Notes

No breaking changes from v0.8. If upgrading:

1. **Rebuild and reinstall the CLI:**
   ```powershell
   .\scripts\build-and-install.ps1
   ```

2. **Register your agent** (new — one time per machine/project):
   ```powershell
   felix agent register
   ```

3. **`agents.json` format** — if you have existing entries with a manual `id` field, it is now ignored; the key is computed from `provider`/`model`/`machine`/`git_url`. Remove the `id` field to keep things tidy.

4. **`requirements.json`** — slim schema drop-in compatible. Extra fields (`priority`, `tags`, etc.) are silently ignored if present.

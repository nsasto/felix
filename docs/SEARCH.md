# Search & Navigation

> **Quick links:** [felix search](#felix-search) · [felix deps](#felix-deps) · [felix query](#felix-query) · [Search Cache](#search-cache) · [Examples](#examples)

---

## `felix search`

Full-text search across your codebase, specs, and run artifacts. Felix-aware — it honours `.felixignore` patterns and scopes results to the nearest relevant subdirectory.

```powershell
felix search <pattern> [options]
```

### Options

| Flag | Default | Description |
|---|---|---|
| `--scope file\|symbol` | `file` | Match at file level or symbol level (symbol requires LSP; falls back to file). |
| `--in code\|specs\|runs\|all` | `code` | Scope the search target. `code` excludes `specs/` and `runs/`. |
| `--max N` | `50` | Maximum number of matches to return. |
| `--json` | — | Emit structured JSON output (see contract below). |
| `--related-to <req-id>` | — | Return files referenced in that requirement's plans, diffs, and context maps — no pattern needed. |

### JSON output contract

```json
{
  "matches": [
    {
      "path":    "src/Felix.Cli/Program.cs",
      "line":    42,
      "col":     18,
      "text":    "var result = RunAgent(req);",
      "rank":    0.74,
      "context": ["// previous line", "// following line"]
    }
  ],
  "truncated":     false,
  "total":         12,
  "ignored_globs": ["runs/", "publish-out/", "node_modules/"]
}
```

### Search targets

| `--in` value | What is searched |
|---|---|
| `code` (default) | Entire repo, excluding `specs/` and `runs/` |
| `specs` | `specs/` directory |
| `runs` | The 10 most-recent run directories |
| `all` | Entire repo root (no exclusions beyond `.felixignore`) |

### `.felixignore` integration

Patterns in `.felixignore` (and `%USERPROFILE%/.felix/ignore`) are automatically applied as exclusions. To see which pattern excluded a file:

```powershell
felix doctor --explain publish-out/MyApp.exe
```

---

## `felix deps`

Analyze requirement dependencies. Reads from `.felix/requirements.json`.

```powershell
felix deps <requirement-id> [--check] [--tree]
felix deps --incomplete
```

### Subcommands and flags

| Usage | Description |
|---|---|
| `felix deps S-0001` | Show direct dependencies of `S-0001` with their statuses. |
| `felix deps S-0001 --check` | Exit 0 if all dependencies are complete, exit 1 if any are pending. Useful in CI. |
| `felix deps S-0001 --tree` | Show full transitive dependency tree (each dep also lists its own deps). |
| `felix deps --incomplete` | List **all** requirements that have at least one incomplete dependency. |

### Example output

```
=== Dependency Analysis: S-0005 ===

Requirement: Add user authentication
Status: planned

Dependencies (2):
  [OK]   S-0001 - Database schema
         Status: complete
         Priority: high

  [WARN] S-0003 - Auth middleware
         Status: in-progress
         Priority: high

=== Summary ===
[WARN] Incomplete dependencies detected
  Incomplete: S-0003
```

---

## `felix query`

Structured, versioned JSON interface for agent-readable state. Decouples agents from raw schema files (`requirements.json`, `state.json`). Schema is versioned with a `_v` field.

```powershell
felix query <kind> [filters] [--json]
```

### Kinds

| Kind | Description |
|---|---|
| `requirements` | Read and filter requirements. |
| `runs` | Read run history metadata. |
| `usage` | Summarize model and token usage from run artifacts. |
| `state` | Read `.felix/state.json` (loop control state). |

For events, plugins, skills, and memory use their dedicated verbs instead (`felix event query`, `felix plugin list`, `felix skill list`, `felix memory view`).

### `requirements` filters

```powershell
felix query requirements --status planned --json
felix query requirements --status in-progress
```

| Flag | Description |
|---|---|
| `--status <value>` | Filter by requirement status (e.g., `planned`, `in-progress`, `complete`, `blocked`). |
| `--json` | Emit JSON with `_v` version field. |

Example JSON output:

```json
{
  "_v": 1,
  "requirements": [
    {
      "id": "S-0001",
      "title": "Add login endpoint",
      "status": "planned",
      "priority": "high",
      "depends_on": []
    }
  ]
}
```

### `runs` filters

```powershell
felix query runs --since 24h --json
felix query runs --since 24h --requirement S-0001
```

| Flag | Description |
|---|---|
| `--since <duration>` | Filter runs by age (e.g., `24h`, `7d`). |
| `--requirement <id>` | Filter to runs for a specific requirement. |
| `--json` | Emit structured JSON. |

### `state`

```powershell
felix query state --json
```

Returns the current contents of `.felix/state.json` in a stable, versioned format.

### `usage` filters

```powershell
felix query usage --since 7d
felix query usage --requirement S-0001 --json
felix query usage --run-id S-0001-20260619T120000-it1
```

Usage reads `runs/<run-id>/usage.json`, written by the agent runner after each execution.

For Copilot CLI runs, `felix query usage` reads model, session, and token details from Copilot's JSONL stream. Copilot may report output tokens without input tokens, so `input_tokens` can be `null` for a successful run.

| Flag | Description |
|---|---|
| `--since <duration>` | Filter usage records by age or date (for example `24h`, `7d`, `2026-06-01`). |
| `--requirement <id>` | Filter usage to runs for a specific requirement. |
| `--run-id <id>` | Filter usage to one exact run ID. |
| `--json` | Emit structured JSON including token totals and per-run model details. |

Cost estimates are optional and local. Copy `.felix/model-pricing.json.example` to `.felix/model-pricing.json` and add current provider prices; `felix query usage` then reports estimated cost where model pricing matches.

---

## Search Cache

To avoid paying twice for the same grep within a single iteration, Felix memoizes search results in a per-run cache file:

```
runs/<run-id>/search-cache.json
```

**Cache key:** hash of the query pattern + flags (`scope|in|max`).  
**TTL:** lifetime of the current iteration only — no cross-iteration stale reads.  
**Invalidation:** deleted automatically when the run directory is pruned by `felix gc`.

A cache hit is recorded as a `search.cache_hit` event on the event bus. You can observe hits with:

```powershell
felix event tail --kind search.cache_hit
```

The cache is only active when `FELIX_RUN_DIR` is set (which `felix loop` and `felix run` set automatically). Ad-hoc `felix search` invocations skip the cache.

---

## Examples

```powershell
# Search source code for "RegisterCommands"
felix search "RegisterCommands"

# Search only specs
felix search "authentication" --in specs

# Search last 10 runs for an error message
felix search "NullReferenceException" --in runs --max 20

# Find all files related to S-0042 (killer query — no upstream agent can do this)
felix search --related-to S-0042 --json

# Check if S-0005 is ready to work on
felix deps S-0005 --check

# List all blocked requirements
felix query requirements --status blocked --json

# Find all planned requirements and pipe to a script
felix query requirements --status planned --json | ConvertFrom-Json | ...
```

---

*See also: [CONTEXT.md](CONTEXT.md) for run artifacts · [CLI.md](CLI.md) for the full command reference · [CONFIGURATION.md](CONFIGURATION.md) for `.felixignore` setup*

## Graphify Queries

`felix search` remains the fastest text search path. Use `felix graphify query`, `felix graphify path`, or `felix graphify explain` when the question is about architecture, call flow, dependencies, symbols, or relationships across files.

Graphify is optional and external. Felix passes through to the native Graphify executable and does not inject graph reports into every prompt. See [GRAPHIFY.md](GRAPHIFY.md) for setup and team workflow details.

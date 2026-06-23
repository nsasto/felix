# Configuration Reference

> **Quick links:** [Overview](#overview) · [executor](#executor-block) · [sync](#sync-block) · [tools](#tools-block-v2-phase-f) · [gc](#gc-block-v2-phase-f) · [distribution](#distribution-block-v2-phase-g) · [concurrency](#concurrency-block-v2-phase-h) · [context](#context-block-v2-phase-a) · [backpressure](#backpressure-block) · [plugins](#plugins-block) · [graphify](#graphify-block) · [Environment Variables](#environment-variable-overrides) · [Examples](#examples)

---

## Overview

Felix reads its configuration from `.felix/config.json` in your repository root. A minimal file is created by `felix setup`; you add blocks as needed.

**File location:** `<repo-root>/.felix/config.json`

The schema is forward-compatible: unknown keys are silently ignored, and every key has a sensible default so a sparse file works without error. All blocks are optional unless noted.

---

## `executor` Block

Controls how the agent loop runs requirements.

```json
"executor": {
  "mode": "local",
  "max_iterations": 100,
  "default_mode": "planning",
  "commit_on_complete": true
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `mode` | `string` | `"local"` | Execution mode. Only `"local"` is supported in v2. |
| `max_iterations` | `integer` | `100` | Maximum iterations per requirement run before the agent aborts. |
| `default_mode` | `string` | `"planning"` | Starting mode for a fresh requirement: `"planning"` or `"building"`. |
| `commit_on_complete` | `boolean` | `true` | Auto-commit changes after a requirement completes. Use `-NoCommit` flag to override per-run. |

---

## `agent` Block

Identifies the active agent profile used for this repository.

```json
"agent": {
  "agent_id": "ag_61a011bca"
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `agent_id` | `string` | `null` | Key of the agent profile to load from `.felix/agents.json`. Falls back to the first entry when absent. |

---

## `requirements` Block

Controls requirement ID format.

```json
"requirements": {
  "prefix": "S"
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `prefix` | `string` | `"S"` | Prefix for auto-generated requirement IDs (e.g., `"S"` → `S-0001`). |

---

## `paths` Block

Overrides default file/directory locations.

```json
"paths": {
  "specs": "specs",
  "runs": "runs",
  "agents": "AGENTS.md",
  "context": ["CONTEXT.md"]
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `specs` | `string` | `"specs"` | Directory containing spec markdown files. |
| `runs` | `string` | `"runs"` | Directory where run artifacts are written. |
| `agents` | `string` | `"AGENTS.md"` | Path to the root agents/context file. |
| `context` | `string[]` | `["CONTEXT.md"]` | List of context files uploaded/downloaded by `felix context push/pull`. |

---

## `context` Block (v2 Phase A)

Token budget for prompt assembly. Added by Phase A5 — the context budgeter.

```json
"context": {
  "budget_tokens": 32000
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `budget_tokens` | `integer` | `32000` | Maximum tokens for the assembled prompt. When exceeded, sources are evicted in this order: extras → memory → context\_map → skills → layered\_agents → repo\_map → plan → spec. |

Inspect current token usage:

```powershell
felix context inspect
```

---

## Model Usage and Pricing

Felix records model and token usage for each agent run in:

```text
runs/<run-id>/usage.json
```

Inspect usage across runs:

```powershell
felix query usage --since 7d
felix query usage --requirement S-0001 --json
```

Cost estimates are local and opt-in. Copy `.felix/model-pricing.json.example` to `.felix/model-pricing.json`, then add current provider prices:

```json
{
  "_v": 1,
  "currency": "USD",
  "prices": [
    {
      "provider": "codex",
      "model": "gpt-example",
      "input_per_million": 0.0,
      "output_per_million": 0.0,
      "cache_read_per_million": 0.0,
      "cache_creation_per_million": 0.0
    }
  ]
}
```

Use `felix doctor` to check whether usage artifacts exist and whether observed models have matching pricing rules.

Provider notes:

- Copilot CLI reports output tokens in its JSONL stream, plus session and premium request metadata. It may not report input tokens, so `input_tokens` can be `null` while `output_tokens`, `total_tokens`, and `observed_tokens` are populated.
- Copilot usage capture requires `--output-format json`, which Felix enables for direct Copilot runs.
- On Windows, Felix writes long Copilot prompts to a temporary file before launch to avoid command-line length failures.
- If a live Copilot run produces blank output, verify `copilot login` and clear blocked proxy settings before treating it as a Felix usage parser issue.

---

## `backpressure` Block

Gates that must pass before the agent considers a task complete.

```json
"backpressure": {
  "enabled": true,
  "commands": [
    {
      "name": "dotnet.test",
      "cmd": "dotnet test tests/Felix.Cli.Tests",
      "appliesTo": ["src/Felix.Cli/**", "tests/Felix.Cli.Tests/**"]
    },
    {
      "name": "pwsh.unit",
      "cmd": "pwsh -File ./run-test-spec.ps1",
      "appliesTo": ["felix/**", "scripts/**"]
    }
  ],
  "max_retries": 3,
  "always_run": ["pwsh.lint"]
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | `boolean` | `true` | Whether backpressure gates are enforced. |
| `commands` | `object[]` | `[]` | List of gate definitions (see below). |
| `max_retries` | `integer` | `3` | Number of times the agent retries a requirement before marking it blocked. |
| `always_run` | `string[]` | `[]` | Gate names that run regardless of which files changed (v2 Phase F). |

**Gate definition** (`commands[]` entries):

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | `string` | ✓ | Unique gate name (used in `always_run` and spec `gates` frontmatter). |
| `cmd` | `string` | ✓ | Shell command to execute. Exit code 0 = pass. |
| `appliesTo` | `string[]` | — | Glob patterns matched against the iteration diff. Gate is skipped if no file in the diff matches. Omit to always run (v1 behaviour). |

---

## `plugins` Block

Controls the plugin subsystem.

```json
"plugins": {
  "enabled": true,
  "discovery_path": ".felix/plugins",
  "api_version": "v1",
  "disabled": ["prompt-enhancer"],
  "state_retention_days": 7,
  "circuit_breaker_max_failures": 3,
  "commands": []
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | `boolean` | `true` | Master switch for the plugin subsystem. |
| `discovery_path` | `string` | `".felix/plugins"` | Directory Felix scans for plugin manifests. |
| `api_version` | `string` | `"v1"` | Plugin API version to enforce. |
| `disabled` | `string[]` | `[]` | Plugin IDs that are loaded but not executed. |
| `state_retention_days` | `integer` | `7` | Days to keep plugin transient state before pruning. |
| `circuit_breaker_max_failures` | `integer` | `3` | Consecutive failures before a plugin is auto-disabled for the session. |
| `commands` | `object[]` | `[]` | Additional plugin-contributed commands. |

---

## `sync` Block

Mirrors run artifacts to a remote server (e.g., runfelix.io).

```json
"sync": {
  "enabled": false,
  "provider": "http",
  "base_url": "https://api.runfelix.io",
  "api_key": null
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | `boolean` | `false` | Enable artifact mirroring. Also toggled by `--sync` flag and `FELIX_SYNC_ENABLED` env var. |
| `provider` | `string` | `"http"` | Sync provider. Currently only `"http"`. |
| `base_url` | `string` | `"https://api.runfelix.io"` | Base URL for the sync server. |
| `api_key` | `string` | `null` | API key. Prefer setting via `FELIX_SYNC_KEY` env var or `.env` file rather than in `config.json`. |

---

## `explore` Block (v2 Phase C)

Controls the exploration subagent that reads the repository before plan/build phases.

```json
"explore": {
  "enabled": false,
  "auto_enable_when": {
    "min_tracked_files": 500
  },
  "skip_on_iteration_gt": 1,
  "agent_override": null,
  "max_tokens": 8000
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | `boolean` | `false` | Enable the exploration subagent. `felix migrate` auto-enables when tracked files ≥ 500. |
| `auto_enable_when.min_tracked_files` | `integer` | `500` | Threshold for `felix migrate` to auto-enable exploration. |
| `skip_on_iteration_gt` | `integer` | `1` | Skip exploration on iteration > N (avoids redundant scans on retry iterations). |
| `agent_override` | `string` | `null` | Use a different agent profile for exploration. `null` = same as main agent. |
| `max_tokens` | `integer` | `8000` | Token budget for the exploration subagent's context output. |

---

## `tools` Block (v2 Phase F)

Agent tool allowlist. Controls which tools the agent is permitted to call.

```json
"tools": {
  "allow": [],
  "deny": [],
  "default": "allow"
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `allow` | `string[]` | `[]` | Glob patterns of permitted tool names (e.g., `"search.*"`, `"navigate.definition"`). |
| `deny` | `string[]` | `[]` | Glob patterns of explicitly denied tool names. `deny` takes precedence over `allow`. |
| `default` | `string` | `"allow"` | Fallback when a tool matches neither list: `"allow"` or `"deny"`. |

**Default-allow is the safe upgrade path.** v1→v2 migration sets `default: "allow"` and records all calls in the audit log. Run `felix tool harden` when you are ready to flip to `default: "deny"` with an inferred allowlist.

```powershell
# Inspect current allowlist status and audit stats
felix tool status

# Flip to deny with inferred allowlist from audit log
felix tool harden
felix tool harden --dry-run   # Preview without writing
```

---

## `gc` Block (v2 Phase F)

Disk-pressure cleanup settings.

```json
"gc": {
  "retention_days": 30,
  "events_retention_days": 30
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `retention_days` | `integer` | `30` | Days to keep run directories under `runs/`. The most-recent successful run per requirement is always retained. |
| `events_retention_days` | `integer` | `30` | Days to keep rotated `.felix/events-*.jsonl` archives. The live `.felix/events.jsonl` is never deleted by gc. |

Trigger a garbage-collection pass:

```powershell
felix gc --dry-run   # Preview what would be pruned
felix gc --yes       # Prune without interactive confirmation
```

---

## `distribution` Block (v2 Phase G)

Marketplace index settings for plugin and skill discovery.

```json
"distribution": {
  "index_url": "https://nsasto.github.io/felix/plugins.json",
  "channels": ["stable"]
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `index_url` | `string` | `"https://nsasto.github.io/felix/plugins.json"` | URL of the marketplace index JSON. Override to use a private registry. |
| `channels` | `string[]` | `["stable"]` | Channels to include when resolving compatible versions. Options: `"stable"`, `"beta"`. |

---

## `concurrency` Block (v2 Phase H)

Parallel worker and git worktree settings.

```json
"concurrency": {
  "worktrees": false,
  "parallel": 1,
  "merge_strategy": "merge",
  "retention_days": 3
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `worktrees` | `boolean` | `false` | Enable per-run git worktrees. Can also be activated with `felix loop --worktrees`. |
| `parallel` | `integer` | `1` | Number of worker processes to spawn in `felix loop`. Overridden by `--parallel N`. |
| `merge_strategy` | `string` | `"merge"` | How completed worktrees are merged back: `"merge"` or `"ff"` (fast-forward). |
| `retention_days` | `integer` | `3` | Days to keep abandoned/failed worktrees before `felix gc` removes them. |

---

## `graphify` Block

Controls optional Graphify integration. Graphify remains an external dependency; Felix uses this block for skill loading, wrapper commands, and optional team graph refresh commits.

```json
"graphify": {
  "enabled": false,
  "skill_enabled": true,
  "mode": "local",
  "out_dir": ".felix/graphify",
  "team_out_dir": "graphify-out",
  "native_install": false,
  "post_commit_hook": false,
  "auto_commit_refresh": false,
  "cache_policy": "ignore"
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | `boolean` | `false` | Enables Felix Graphify skill guidance and wrapper behavior. |
| `skill_enabled` | `boolean` | `true` | Loads the small `graphify-investigator` skill when Graphify is enabled. |
| `mode` | `string` | `local` | `local` uses ignored graph output; `team` uses committed `graphify-out/`. |
| `out_dir` | `string` | `.felix/graphify` | Local-mode output directory passed to Graphify. |
| `team_out_dir` | `string` | `graphify-out` | Team-mode graph directory intended to be committed. |
| `native_install` | `boolean` | `false` | Records whether native assistant setup was requested. |
| `post_commit_hook` | `boolean` | `false` | Records whether team setup should use Graphify's post-commit hook. |
| `auto_commit_refresh` | `boolean` | `false` | Lets Felix create a separate `chore(graphify): refresh graph` commit when only graph files changed after a requirement commit. |
| `cache_policy` | `string` | `ignore` | `ignore` excludes `graphify-out/cache/`; `commit` allows committing it. |

See [GRAPHIFY.md](GRAPHIFY.md) for setup and team workflow details.

---

## `skills` Block

Controls the skill subsystem (populated by `felix skill enable/disable`).

```json
"skills": {
  "disabled": ["prompt-enhancer"]
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `disabled` | `string[]` | `[]` | Skill IDs that are installed but not loaded at runtime. |

---

## Environment Variable Overrides

These environment variables override the corresponding `config.json` keys at runtime. Useful in CI/CD pipelines or for temporary overrides without editing files.

| Variable | Overrides | Example |
|---|---|---|
| `FELIX_SYNC_ENABLED` | `sync.enabled` | `"true"` / `"false"` |
| `FELIX_SYNC_URL` | `sync.base_url` | `"https://api.runfelix.io"` |
| `FELIX_SYNC_KEY` | `sync.api_key` | `"fsk_prod_key_here"` |

---

## Examples

### Minimal config

A new repo set up with `felix setup` generates a file similar to this:

```json
{
  "version": "0.1.0",
  "executor": {
    "mode": "local",
    "max_iterations": 100,
    "default_mode": "planning",
    "commit_on_complete": true
  },
  "agent": {
    "agent_id": "your-agent-id"
  },
  "backpressure": {
    "enabled": true,
    "commands": [],
    "max_retries": 3
  },
  "sync": {
    "enabled": false,
    "provider": "http",
    "base_url": "https://api.runfelix.io",
    "api_key": null
  }
}
```

### Full v2 config

```json
{
  "version": "0.1.0",
  "executor": {
    "mode": "local",
    "max_iterations": 100,
    "default_mode": "planning",
    "commit_on_complete": true
  },
  "agent": { "agent_id": "ag_61a011bca" },
  "requirements": { "prefix": "S" },
  "paths": {
    "specs": "specs",
    "runs": "runs",
    "agents": "AGENTS.md",
    "context": ["CONTEXT.md"]
  },
  "context": { "budget_tokens": 32000 },
  "backpressure": {
    "enabled": true,
    "commands": [
      {
        "name": "dotnet.test",
        "cmd": "dotnet test",
        "appliesTo": ["src/**", "tests/**"]
      },
      {
        "name": "pwsh.unit",
        "cmd": "pwsh -File ./run-test-spec.ps1",
        "appliesTo": ["felix/**", ".felix/plugins/**/*.ps1"]
      }
    ],
    "max_retries": 3,
    "always_run": ["pwsh.lint"]
  },
  "plugins": {
    "enabled": true,
    "discovery_path": ".felix/plugins",
    "api_version": "v1",
    "disabled": [],
    "state_retention_days": 7,
    "circuit_breaker_max_failures": 3
  },
  "sync": {
    "enabled": false,
    "provider": "http",
    "base_url": "https://api.runfelix.io",
    "api_key": null
  },
  "explore": {
    "enabled": false,
    "auto_enable_when": { "min_tracked_files": 500 },
    "skip_on_iteration_gt": 1,
    "agent_override": null,
    "max_tokens": 8000
  },
  "tools": {
    "allow": ["search.*", "navigate.*", "query.requirements", "query.runs"],
    "deny": [],
    "default": "allow"
  },
  "gc": {
    "retention_days": 30,
    "events_retention_days": 30
  },
  "distribution": {
    "index_url": "https://nsasto.github.io/felix/plugins.json",
    "channels": ["stable"]
  },
  "concurrency": {
    "worktrees": false,
    "parallel": 1,
    "merge_strategy": "merge",
    "retention_days": 3
  }
}
```

---

*See also: [CLI.md](CLI.md) · [PLUGINS.md](PLUGINS.md) · [CONCURRENCY.md](CONCURRENCY.md) · [MARKETPLACE.md](MARKETPLACE.md)*

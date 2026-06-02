# Learning & Memory

> **Quick links:** [What Is Memory](#what-is-memory) · [Memory Files](#memory-files) · [felix memory view](#felix-memory-view) · [felix memory add](#felix-memory-add) · [felix memory edit](#felix-memory-edit) · [felix memory prune](#felix-memory-prune) · [How the Agent Uses Memory](#how-the-agent-uses-memory) · [Memory Budget](#memory-budget) · [Learning Proposals](#learning-proposals)

---

## What Is Memory

Memory gives Felix **persistent knowledge that survives across runs**. Without memory, the agent starts each iteration with no recollection of past mistakes or conventions it has learned. With memory, it carries durable insights forward — e.g., "always run `dotnet build` before `dotnet test`", or "the `Program.Commands.cs` file registers commands via reflection."

Memory entries live in `.felix/memory/` as plain markdown files with YAML frontmatter. They are never modified by the agent loop automatically — only by CLI commands you run or via `felix review --learnings`.

---

## Memory Files

```
.felix/memory/
├── repo/
│   └── 2026-06-01-commands-registration.md     # repo-scoped entries
└── requirement/
    └── S-0001/
        └── 2026-06-10-auth-token-format.md      # per-requirement entries

%USERPROFILE%\.felix\memory\
└── global/
    └── 2026-05-15-testing-conventions.md        # cross-repo global entries
```

Three scopes:

| Scope | Location | Committed? | Use for |
|---|---|---|---|
| `global` | `%USERPROFILE%\.felix\memory\global\` | No (user profile) | Cross-repo conventions, personal preferences |
| `repo` | `.felix\memory\repo\` | Yes | Repo-specific architecture notes, team conventions |
| `requirement` | `.felix\memory\requirement\<id>\` | Yes | Per-requirement context, decisions, known traps |

**Memory files are never auto-deleted.** Only `runs/*/agents-md-suggestions.md` proposal files are pruned — see [Learning Proposals](#learning-proposals).

### Entry frontmatter

Each memory file uses YAML frontmatter:

```markdown
---
title: Commands are registered via reflection
scope: repo
created: 2026-06-01
tags: [architecture, commands]
---

`Program.Commands.cs` registers all CLI commands using reflection.
Add new commands there, not in `Program.cs`.
```

| Field | Required | Description |
|---|---|---|
| `title` | ✓ | One-line summary shown in `felix memory view`. |
| `scope` | ✓ | `global`, `repo`, or `requirement`. |
| `created` | ✓ | ISO date of creation. |
| `tags` | — | Array of keyword tags for filtering. |

---

## `felix memory view`

Inspect memory entries without opening individual files.

```powershell
felix memory view                              # All scopes
felix memory view --scope global               # Global entries only
felix memory view --scope repo                 # Repo entries only
felix memory view --scope requirement          # All per-requirement entries
felix memory view --scope requirement --req S-0001  # Entries for S-0001 only
```

Example output:

```
Felix Memory (4 entries)

  [global]       Testing conventions
    .felix\memory\global\2026-05-15-testing-conventions.md

  [repo]         Commands are registered via reflection
    .felix\memory\repo\2026-06-01-commands-registration.md

  [requirement/S-0001]  Auth token format decision
    .felix\memory\requirement\S-0001\2026-06-10-auth-token-format.md
```

---

## `felix memory add`

Create a new memory entry from the command line.

```powershell
felix memory add --scope repo --title "Run dotnet build before test" --body "Always run 'dotnet build' before 'dotnet test' to surface compile errors first"

felix memory add --scope global --title "Prefer Assert.Equal order" --body "Use Assert.Equal(expected, actual) — expected value goes first"

felix memory add --scope requirement --req S-0042 --title "JWT secret in env var" --body "The JWT secret is loaded from FELIX_JWT_SECRET; do not hardcode it"
```

| Flag | Required | Description |
|---|---|---|
| `--scope <scope>` | ✓ | `global`, `repo`, or `requirement`. |
| `--title <text>` | ✓ | One-line summary (used as the filename slug). |
| `--body <text>` | — | Full entry body. Can be multi-line. |
| `--req <id>` | Required when `--scope requirement` | Requirement ID to scope the entry to. |

The file is written to the appropriate scope directory with a datestamped filename: `YYYY-MM-DD-<title-slug>.md`.

---

## `felix memory edit`

Open an existing memory file in your editor (`$EDITOR`, defaulting to `notepad`).

```powershell
felix memory edit .felix\memory\repo\2026-06-01-commands-registration.md

# Or a relative path from the repo root
felix memory edit .felix/memory/repo/2026-06-01-commands-registration.md
```

---

## `felix memory prune`

Remove stale learning-proposal files from `runs/*/agents-md-suggestions.md`. Does **not** touch any committed memory entries in `.felix/memory/`.

```powershell
felix memory prune                     # Prune proposals older than 30 days
felix memory prune --older-than 14     # Prune proposals older than 14 days
felix memory prune --dry-run           # Preview without deleting
```

| Flag | Description |
|---|---|
| `--older-than <days>` | Age threshold in days. Default: 30. |
| `--dry-run` | Show which files would be deleted; make no changes. |

---

## How the Agent Uses Memory

Memory files are loaded additively into the `{{MEMORY}}` placeholder in the prompt template before each iteration:

1. **Global** entries are loaded first.
2. **Repo** entries are loaded next.
3. **Requirement-scoped** entries for the current requirement are loaded last.

Entries are concatenated in file-name order within each scope. The assembled block is passed to the token budgeter, which may evict memory to fit the context window (see [Memory Budget](#memory-budget)).

---

## Memory Budget

Memory is subject to the token budget set in `config.json`:

```json
"context": {
  "budget_tokens": 32000
}
```

Eviction order when the budget is exceeded:

```
extras → memory → context_map → skills → layered_agents → repo_map → plan → spec
```

Memory is evicted **after** extras but **before** skills, context maps, and the spec/plan core. This means excessive memory growth will reduce context available to the agent rather than crowding out the requirement spec.

Inspect the current budget and whether memory would be evicted:

```powershell
felix context inspect
```

---

## Learning Proposals

The `learning-capture` plugin (enabled by default after `felix setup`) runs after each iteration and writes proposals to:

```
runs/<run-id>/agents-md-suggestions.md
```

These proposals contain suggested `AGENTS.md` additions, new memory entries, and prompt edits — but they are **never auto-applied**. You review and accept them manually:

```powershell
felix review --learnings        # Walk proposals from recent runs; accept/reject/defer
felix review --prompts          # Review prompt health (stale workarounds, etc.)
felix review --all              # Both, in sequence
felix review --acknowledge      # Mark the last review date (silences the 90-day reminder)
```

Accepted memory entries land as committed files in `.felix/memory/repo/` (or `requirement/`). Rejected proposals remain as-is until `felix memory prune` removes them.

---

*See also: [CONTEXT.md](CONTEXT.md) for token budget details · [CONFIGURATION.md](CONFIGURATION.md) for the `context.budget_tokens` key · [CLI.md](CLI.md) for the full `felix memory` command reference*

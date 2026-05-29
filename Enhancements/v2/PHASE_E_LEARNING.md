# Phase E — Self-Improving Loop + Memory (v2.4)

> **Status:** Planned
> **Version:** v2.4 (parallel with C/D)
> **Depends-On:** A.5
> **Unblocks:** —
> **Last-Touched:** 2026-05-29

The article calls "stop hooks that reflect on the session and propose CLAUDE.md updates" the most valuable hook pattern. Felix has the hook infrastructure but nothing wired up. Every run starts blank — there's no equivalent of `/memories/`. Insights die in `runs/.../report.md` and no future iteration ever sees them.

## Goals

1. Capture per-iteration learnings into reviewable proposals (not auto-applied).
2. Give Felix a durable memory tree the planning/building prompts load additively.
3. Flag prompts that compensate for old model limitations so they can be retired.

## Deliverables

### E1 — `learning-capture` reference plugin

- Hooks: `OnPostIteration`
- Reads from Event Bus (AS2), not log scraping (E8)
- Drafts proposals to `runs/<run-id>/agents-md-suggestions.md`:

  ```markdown
  # Suggestions from S-0042 it3

  ## Proposed AGENTS.md additions

  - Run `dotnet build` before `dotnet test` to surface compile errors first

  ## Proposed memory entries

  - [repo] `Program.Commands.cs` registers via reflection — add new commands there, not in `Program.cs`

  ## Proposed prompt edits

  - building.md: "do NOT write code" rule fires unnecessarily when model already in planning mode
  ```

- Never auto-applies; always reviewed by human

### E2 — `felix review` (unified surface)

- Single command with sub-modes; replaces what was previously three separate verbs (`felix learnings review`, `felix prompts review`, plus the quarterly reminder hook):
  - `felix review --learnings` — walks `agents-md-suggestions.md` proposals across recent runs; accept/reject/defer
  - `felix review --prompts` — diffs current prompts/skills against a baseline snapshot, flags model-workaround heuristics (`<promise>` tags, `do NOT ...` rules, JSON-only output contracts, per-task-size constraints), suggests retirements
  - `felix review --all` — both, in sequence
  - `felix review --acknowledge` — stamps `.felix/state.json#last_review` to silence the reminder
- Accepted edits land via `git apply`-style patch with `[felix-learning]` or `[felix-prompt]` commit markers
- Recommended cadence: every 3 months or after a major model release

### E3 — Periodic review reminder hook (formerly E4)

- `OnLoopStart` plugin checks `.felix/state.json#last_review`
- > 90 days → emits Event Bus warning + console banner pointing at `felix review --all`
- Suppressible via `felix review --acknowledge`

### E4 — `.felix/memory/` tree (formerly E5)

- Three scopes (mirrors `/memories/` pattern):
  - `.felix/memory/global/*.md` — user-level (cross-repo); lives at `%USERPROFILE%/.felix/memory/global/` actually; repo can override per-file
  - `.felix/memory/repo/*.md` — repo-scoped (committed)
  - `.felix/memory/requirement/S-NNNN/*.md` — per-requirement (committed alongside spec)
- Loaded additively into `{{MEMORY}}` placeholder (A4) by the loop
- Budgeter (A5) evicts memory **after** layered AGENTS.md but **before** spec/plan

### E5 — `felix memory` CLI (formerly E6)

- `felix memory view [--scope global|repo|requirement S-NNNN]`
- `felix memory add --scope <scope> --title "<...>" --body "<...>"`
- `felix memory edit <file>` — opens in editor
- `felix memory prune [--older-than 30d] [--dry-run]` — operates on `runs/.../agents-md-suggestions.md` proposals only by default (see E6)

### E6 — Auto-proposed memory entries (formerly E7)

- `learning-capture` (E1) also drafts memory proposals (short, dated bullets) into `runs/<run-id>/agents-md-suggestions.md`
- **Auto-prune is scoped to proposal files in `runs/` only.** Memory entries already promoted into `.felix/memory/repo/` (committed) are **never** modified by the loop — only by `felix memory` commands a human runs. Avoids surprising diffs against committed files.
- Promotion happens via `felix review --learnings`; promoted entries get `promoted: true` in frontmatter and live in `.felix/memory/`
- Prevents the memory tree from becoming a graveyard _and_ prevents the loop from rewriting committed history

### E7 — Event Bus consumer (formerly E8)

- `learning-capture` reads events via `felix events query`, not by scraping `runs/.../output.log`
- Failure events (`backpressure.fail`, `validation.fail`, `iteration.error`) are the primary input
- Win events (`requirement.complete`) trigger "what worked" memory proposals

## Non-goals

- Automatic application of learnings (always human-reviewed)
- Cross-repo memory sync (deferred to v3 cloud bidirectional sync)
- Prompt A/B framework (deferred; bench harness covers 80%)

## Phase Contracts frozen here

- `.felix/memory/` tree layout (scopes, file naming, frontmatter required fields)
- `agents-md-suggestions.md` schema
- `felix memory view|add|edit|prune` CLI
- `felix review --learnings|--prompts|--all|--acknowledge` CLI + report schema
- Auto-prune scope: `runs/.../agents-md-suggestions.md` only; `.felix/memory/` never auto-modified

## Verification

- Deliberate iteration failure → `agents-md-suggestions.md` exists and includes at least one proposal
- `felix review --learnings` accepts a proposal → AGENTS.md updated; commit shows `[felix-learning]` marker
- Memory entry written in run N surfaces in iteration prompt of run N+1
- `felix review --prompts` flags `<promise>` usage in `building.md` and "do NOT" rules in `planning.md`
- Poisoned memory entry (nonsense added by model) → `felix doctor` flags via heuristic (length, low signal, no frontmatter)
- Proposal in `runs/.../agents-md-suggestions.md` not promoted within 30 days → auto-pruned; **committed entry in `.felix/memory/repo/` is never touched by the loop**

## Dogfood specs

- `specs/S-2E01-learning-capture-plugin.md`
- `specs/S-2E02-review-cli.md` (unified `felix review`)
- `specs/S-2E03-review-reminder-hook.md`
- `specs/S-2E04-memory-tree.md`
- `specs/S-2E05-memory-cli.md`
- `specs/S-2E06-auto-memory-proposals.md`
- `specs/S-2E07-event-bus-consumer.md`

## Anchor files

- New: `.felix/plugins/learning-capture/`, `.felix/memory/`
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `review`, `memory`
- [.felix/state.json](../../.felix/state.json) — `last_review` field
- [.felix/config.json](../../.felix/config.json) — `memory.retention_days`, `learnings.auto_propose`

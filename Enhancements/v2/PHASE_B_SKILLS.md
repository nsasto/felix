# Phase B — Skills & Spec Frontmatter (v2.1)

> **Status:** Planned
> **Version:** v2.1
> **Depends-On:** A
> **Unblocks:** C
> **Last-Touched:** 2026-05-29

Today every prompt in [.felix/prompts/](../../.felix/prompts/) is always-on. As the prompt set grows, every iteration carries more dead weight. Skills bring **progressive disclosure**: load expertise only when the current task triggers it.

## Goals

1. Move non-mode prompts into a skill format with explicit triggers.
2. Give specs structured frontmatter that the loop, the linter, and per-path backpressure (F) can consume.
3. Add a spec critique loop so requirements get reviewed before they go `planned`.

## Deliverables

### B1 — Skill manifest schema

- `.felix/skills/<id>/skill.json`:
  ```json
  {
    "id": "spec-builder",
    "name": "Spec Builder",
    "description": "Generates new requirement specs from a one-line description",
    "triggers": {
      "commands": ["spec create"],
      "applyTo": [],
      "tags": []
    },
    "prompt": "prompt.md",
    "version": "1.0.0"
  }
  ```
- `prompt.md` next to manifest; treated as a fragment injected via the `{{SKILLS}}` placeholder
- Repo scope: `.felix/skills/<id>/`; user scope: `%USERPROFILE%/.felix/skills/<id>/`
- **Repo overrides user** on id collision

### B2 — Migrate existing prompts

Move from `[.felix/prompts/](../../.felix/prompts/)` to skills:

- `spec-builder` → `skills/spec-builder/`
- `documenter`, `explainer.md`, `learning.md` → `skills/<id>/`
- `build_context.md`, `build_agents.md` → `skills/<id>/`
- `check-tasks-complete.md` → `skills/check-tasks-complete/`
- `spec_rules.md`, `spec_q_1.txt` → embedded in `spec-builder` skill assets
- **Keep at root**: `planning.md`, `building.md` (mode prompts, always loaded)

### B3 — Skill loader

- Selection algorithm:
  1. Always-on skills (manifest with empty triggers and explicit `"always": true`) — discouraged
  2. Command-triggered: matched by `triggers.commands`
  3. Path-triggered: requirement's `applyTo` globs intersect skill's `triggers.applyTo`
  4. Tag-triggered: requirement's `tags` intersect skill's `triggers.tags`
  5. Content-triggered: task descriptions contain any `triggers.keywords` (cheap)
- Loaded skills assembled into `{{SKILLS}}` placeholder with stable ordering (deterministic for replay)
- Budgeter (A5) evicts skills first under pressure

### B4 — `felix skill` CLI

- `felix skill list [--scope repo|user|all]`
- `felix skill show <id>` — full manifest + prompt
- `felix skill enable|disable <id>` — writes to `.felix/config.json#skills.disabled`
- `felix skill install <name|path|url|git>` — deferred to G (G5)

### B5 — Spec frontmatter

- YAML frontmatter block at top of each `specs/S-NNNN-*.md`:
  ```yaml
  ---
  id: S-0042
  title: Add hierarchical AGENTS.md loader
  status: planned
  applyTo:
    - "felix/felix-agent.ps1"
    - ".felix/prompts/**"
  tags: [context, prompt]
  skills: [build_context]
  gates: ["pwsh.unit", "pwsh.lint"]
  depends_on: [S-0040]
  ---
  ```
- Parsed by loop; mirrored into `.felix/requirements.json` (single source of truth still the spec file)

### B6 — `felix spec fix`

- Detects v1 specs (no frontmatter) and migrates by inferring fields from the body
- `--dry-run` prints proposed frontmatter blocks
- `--apply` writes them

### B7 — `felix spec lint`

- Checks: required fields present; `gates` references existing backpressure entries; `skills` references existing skills; `applyTo` not empty for non-trivial requirements
- CI gate — **opt-in via `spec.lint.enforce: true`** until the repo is clean. `felix spec fix --apply` flips the flag automatically once zero unfront-mattered specs remain. Prevents B7 from being a footgun on v1→v2 upgrade.

### B8 — `felix spec review`

- Runs a `spec-critic` skill against `S-NNNN`
- Outputs `specs/_reviews/S-NNNN-review-<utc>.md` with: missing acceptance criteria, ambiguous scope, suggested `applyTo`/`gates`
- **No lifecycle change.** A spec stays `draft` until a human edits it after the review exists (mtime check) or explicitly runs `felix spec approve`, at which point it moves to `planned`. We do **not** introduce `reviewed` or `approved` as separate states — they're transient steps in a single-user workflow.
- `felix spec approve S-NNNN` is a one-shot convenience for the "I've read the review, ship it" path

## Non-goals

- Remote skill marketplace (G5/G6)
- Skill A/B testing (deferred)

## Phase Contracts frozen here

- `skill.json` v1 schema
- Spec frontmatter v1 schema (required + optional fields)
- `felix skill list|show|enable|disable` CLI surface
- `felix spec lint|fix|review|approve` CLI surface
- Spec lifecycle states: `draft | planned | in-progress | complete | blocked` (no `reviewed`/`approved` — those are transient steps, not states)

## Verification

- A requirement with `applyTo: ["src/Felix.Cli/**"]` loads the C#-relevant skill but not the Python one
- Removing a skill mid-run leaves the iteration prompt intact (skill registry resolved at iteration start)
- `felix spec lint` catches a spec missing a `gates` entry while touching `src/**` once `spec.lint.enforce` is on
- `felix spec review S-0001` produces a critique file; spec stays `draft` until human edits it or runs `spec approve`
- Repo skill with same id as user skill is the one loaded
- `felix migrate` (A6) runs `spec fix --apply` end-to-end on a v1 fixture and the repo lands with `spec.lint.enforce: true` automatically

## Dogfood specs

- `specs/S-2B01-skill-manifest.md`
- `specs/S-2B02-prompt-to-skill-migration.md`
- `specs/S-2B03-skill-loader.md`
- `specs/S-2B04-skill-cli.md`
- `specs/S-2B05-spec-frontmatter.md`
- `specs/S-2B06-spec-fix.md`
- `specs/S-2B07-spec-lint.md`
- `specs/S-2B08-spec-review.md`

## Anchor files

- [.felix/prompts/](../../.felix/prompts/) — most files migrate out
- New: `.felix/skills/`
- [src/Felix.Cli/SpecCommands.cs](../../src/Felix.Cli/SpecCommands.cs) — `spec lint|fix|review|approve`
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `skill list|show|enable|disable`
- [.felix/requirements.json](../../.felix/requirements.json) — mirror frontmatter

# Phase B — Skills & Spec Frontmatter (v2.1)

> **Status:** Planned
> **Version:** v2.1
> **Depends-On:** A
> **Unblocks:** C
> **Last-Touched:** 2026-05-29

Today every prompt in [.felix/prompts/](../../.felix/prompts/) is always-on. As the prompt set grows, every iteration carries more dead weight. Skills bring **progressive disclosure**: load expertise only when the current task triggers it.

## Goals

1. Move non-mode prompts into a skill format with explicit triggers.
2. Give specs structured frontmatter that the loop, the doctor checks, and per-path backpressure (F) can consume.
3. Ensure new specs are created with frontmatter so the migration loop closes.

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
- **Skill ids are kebab-case and must match the directory name** (e.g. `spec-builder`, `build-context`)

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
  skills: [build-context]
  gates: ["pwsh.unit", "pwsh.lint"]
  depends_on: [S-0040]
  ---
  ```
- Parsed by loop; mirrored into `.felix/requirements.json` (single source of truth still the spec file)

### B6 — `felix spec fix`

- Detects v1 specs (no frontmatter) and migrates by inferring fields from the body
- `--dry-run` prints proposed frontmatter blocks
- `--apply` writes them

### B7 — Spec frontmatter validation _(folded into `felix doctor`)_

- **No separate `felix spec lint` verb.** Validation checks live as a registered `doctor` check (A.5 AS4):
  - Required fields present
  - `gates` references existing backpressure entries
  - `skills` references existing skills
  - `applyTo` not empty for non-trivial requirements
- Enforcement is controlled by `doctor.gates.spec_frontmatter` (default `warn`). `felix migrate` flips to `error` automatically once zero unfront-mattered specs remain. Prevents the check from being a footgun on v1→v2 upgrade.

### B8 — `felix spec create` (frontmatter-emitting) _(replaces `spec review`/`spec approve`)_

- `felix spec create` always emits a populated frontmatter block. Closes the migration loop: after `felix migrate`, every hand-edited or freshly-created spec is well-formed.
- **`felix spec review` + `spec-critic` skill + `felix spec approve` cut.** Promotion from `draft` → `planned` happens by a human edit (mtime check on the spec itself). If a user wants a critique, they can run any skill against any file manually — no dedicated subsystem needed.

## Non-goals

- Remote skill marketplace (G5/G6)
- Skill A/B testing (deferred)

## Phase Contracts frozen here

- `skill.json` v1 schema
- Spec frontmatter v1 schema (required + optional fields)
- `felix skill list|show|enable|disable` CLI surface
- `felix spec fix|create` CLI surface (lint folded into `doctor`; `review`/`approve` cut)
- Spec lifecycle states: `draft | planned | in-progress | complete | blocked`

## Verification

- A requirement with `applyTo: ["src/Felix.Cli/**"]` loads the C#-relevant skill but not the Python one
- Removing a skill mid-run leaves the iteration prompt intact (skill registry resolved at iteration start)
- `felix doctor` flags a spec missing a `gates` entry while touching `src/**` once `doctor.gates.spec_frontmatter` is on
- `felix spec create S-NNNN` produces a spec with valid frontmatter on first invocation
- Repo skill with same id as user skill is the one loaded
- `felix migrate` runs `spec fix --apply` end-to-end on a v1 fixture and the repo lands with `doctor.gates.spec_frontmatter: error` automatically

## Dogfood specs

- `specs/S-2B01-skill-manifest.md`
- `specs/S-2B02-prompt-to-skill-migration.md`
- `specs/S-2B03-skill-loader.md`
- `specs/S-2B04-skill-cli.md`
- `specs/S-2B05-spec-frontmatter.md`
- `specs/S-2B06-spec-fix.md`
- `specs/S-2B07-doctor-spec-frontmatter-check.md`
- `specs/S-2B08-spec-create.md`

## Anchor files

- [.felix/prompts/](../../.felix/prompts/) — most files migrate out and the originals are deleted by `felix migrate` (git history preserved)
- New: `.felix/skills/`
- [src/Felix.Cli/SpecCommands.cs](../../src/Felix.Cli/SpecCommands.cs) — `spec fix|create` (no `lint`/`review`/`approve`)
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `skill list|show|enable|disable`
- [.felix/requirements.json](../../.felix/requirements.json) — mirror frontmatter

# S-0004: Artifact Templates and Scaffolding

## Narrative

As a developer starting a new Felix-enabled project, I need templates and scaffolding commands to quickly create the Felix artifact structure (specs/, ..felix/, AGENTS.md) with sensible defaults, so I don't have to manually create each file.

## Acceptance Criteria

### CLI Scaffolding Command

- [ ] `felix init` command to initialize Felix in existing project
- [ ] Creates directory structure: specs/, ..felix/, ..felix/prompts/, ..felix/policies/, runs/
- [ ] Generates initial files from templates
- [ ] Validates not already Felix-enabled before creating
- [ ] Option: `felix init --minimal` for bare-bones setup

### Template Files

**..felix/config.json template:**

- [ ] Sensible defaults: max_iterations=100, auto_transition=true, default_mode="building"
- [ ] Commented template explaining each setting

**..felix/requirements.json template:**

- [ ] Empty array with schema comment
- [ ] Example commented-out entry showing structure

**..felix/prompts/planning.md template:**

- [ ] Planning mode instructions from Ralph Playbook
- [ ] Guardrails: no code changes, gap analysis rules
- [ ] Context structure: what to load and how to analyze

**..felix/prompts/building.md template:**

- [ ] Building mode instructions from Ralph Playbook
- [ ] Workflow: investigate → implement → validate cycle
- [ ] Backpressure rules

**..felix/policies/allowlist.json template:**

- [ ] Allowed commands: git, npm, pip, python, node, cargo, make
- [ ] Allowed file patterns: src/, tests/, app/, specs/, ..felix/, AGENTS.md, runs/
- [ ] Comments explaining allowlist semantics

**..felix/policies/denylist.json template:**

- [ ] Prohibited operations: rm -rf, system commands, network access
- [ ] Prohibited paths: /, /home, /etc, node_modules/, .git/objects/
- [ ] Comments explaining denylist semantics

**AGENTS.md template:**

- [ ] Sections: Install Dependencies, Run Tests, Build, Start Application
- [ ] Placeholder commands with TODOs
- [ ] Explanation comment at top about keeping it operational

**specs/CONTEXT.md template:**

- [ ] Sections: Tech Stack, Design Standards, UX Rules, Architectural Invariants
- [ ] Placeholder content with examples

### New Spec Generation

- [ ] `felix spec create <name>` command
- [ ] Prompts for title, generates ID (incremental: S-0001, S-0002, etc.)
- [ ] Creates specs/S-NNNN-<name>.md with template structure (e.g., S-0005-user-authentication.md)
- [ ] Adds entry to ..felix/requirements.json with status="draft"

### Validation Command

- [ ] `felix validate` command to check Felix project health
- [ ] Verifies all required files exist
- [ ] Checks specs/ for valid format (ID in first line)
- [ ] Validates ..felix/requirements.json schema
- [ ] Checks ..felix/config.json for required fields
- [ ] Reports missing or malformed files

## Technical Notes

**CLI tool location:** Could be:

- Option A: Standalone CLI tool (`felix` command installed globally)
- Option B: Python script in agent repository (`python -m felix init`)
- Option C: Backend API endpoints (POST /api/init) called by frontend

Prefer Option B for now (simplicity, no separate CLI package).

**Template philosophy:** Templates should be:

- Heavily commented with explanations
- Show examples of correct usage
- Be immediately runnable (even if no-ops)
- Not require editing to get started

**Spec ID generation:** Parse existing specs/ to find highest S-NNNN ID, increment. Handle gaps gracefully.

## Validation Criteria

- [ ] Felix CLI module exists: `python -c "import felix.cli"` (exit code 0)
- [ ] Init command available: `python -m felix init --help` (exit code 0)
- [ ] Spec create command available: `python -m felix spec create --help` (exit code 0)
- [ ] Validate command available: `python -m felix validate --help` (exit code 0)

## Dependencies

None - scaffolding is orthogonal to execution.



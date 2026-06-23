# Skills

> **Quick links:** [What Are Skills](#what-are-skills) · [Directory Layout](#directory-layout) · [Manifest Schema](#skillsjson-manifest-schema) · [Installing Skills](#installing-skills) · [Managing Skills](#managing-skills) · [Writing a Skill](#writing-a-skill) · [Loading Order](#skill-loading-order)

---

## What Are Skills

Skills are **reusable agent capabilities** packaged as a prompt fragment plus a `skill.json` manifest. Instead of loading every prompt on every iteration, Felix loads only the skills that are relevant to the current task — keeping the context window lean and the agent focused.

A skill is matched by:

- **Command trigger** — a specific CLI command invokes it (e.g., `spec create`)
- **Path trigger** — the requirement's `applyTo` globs overlap with the skill's `triggers.applyTo`
- **Tag trigger** — the requirement's `tags` include one of the skill's `triggers.tags`
- **Always-on** — manifest has `"always": true` (discouraged; use sparingly)

Matched skills are assembled into the `{{SKILLS}}` prompt placeholder before each iteration. The token budgeter (see [CONFIGURATION.md](CONFIGURATION.md)) evicts skills first when the budget is tight.

---

## Directory Layout

```
.felix/
└── skills/
    └── <id>/
        ├── skill.json      # Manifest (required)
        └── prompt.md       # Prompt fragment (required by default)
```

Two scopes exist:

| Scope | Location | Priority |
|---|---|---|
| **user** | `%USERPROFILE%\.felix\skills\<id>\` | Lower — repo wins on ID collision |
| **repo** | `<repo-root>\.felix\skills\<id>\` | Higher — overrides user scope |

**Skill IDs are kebab-case and must match the directory name.** For example, the skill `spec-builder` lives in `.felix/skills/spec-builder/`.

---

## `skill.json` Manifest Schema

```json
{
  "id": "spec-builder",
  "name": "Spec Builder",
  "description": "Generates new requirement specs from a one-line description",
  "version": "1.0.0",
  "prompt": "prompt.md",
  "always": false,
  "triggers": {
    "commands": ["spec create"],
    "applyTo":  [],
    "tags":     [],
    "keywords": []
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` | ✓ | Unique kebab-case identifier. Must match the directory name. |
| `name` | `string` | ✓ | Human-readable display name. |
| `description` | `string` | — | One-line description shown in `felix skill list`. |
| `version` | `string` | — | SemVer string (e.g., `"1.0.0"`). |
| `prompt` | `string` | — | Filename of the prompt fragment, relative to the skill directory. Defaults to `"prompt.md"`. |
| `always` | `boolean` | — | Load on every iteration regardless of triggers. Discouraged — prefer explicit triggers. |
| `triggers.commands` | `string[]` | — | CLI command names that activate this skill (e.g., `"spec create"`). |
| `triggers.applyTo` | `string[]` | — | Glob patterns matched against the requirement's `applyTo` field. |
| `triggers.tags` | `string[]` | — | Tags matched against the requirement's `tags` field. |
| `triggers.keywords` | `string[]` | — | Keywords matched (cheaply) against the requirement's title/description. |

---

## Installing Skills

### From the marketplace (by name)

```powershell
felix skill install security-review
felix skill install security-review --channel beta
felix skill install security-review --scope user    # install to user scope
```

Felix looks up the skill in the configured index (`distribution.index_url`), checks compatibility, verifies the SHA256 checksum, and extracts the archive into `.felix/skills/<id>/`.

### From a local path

```powershell
felix skill install ./my-skills/code-reviewer
```

The directory must contain a `skill.json` with a valid `id` field. Felix copies the entire directory to `.felix/skills/<id>/`.

### From a URL (zip archive)

```powershell
felix skill install https://example.com/skills/my-skill-1.0.0.zip
```

Felix downloads, extracts, locates `skill.json`, and installs to the skill's declared `id`.

### Flags

| Flag | Description |
|---|---|
| `--scope repo\|user` | Install to repo scope (default) or user scope. |
| `--channel stable\|beta` | Prefer versions from this channel when resolving from the index. |

---

## Managing Skills

### List installed skills

```powershell
felix skill list                   # all scopes
felix skill list --scope repo      # repo scope only
felix skill list --scope user      # user scope only
felix skill list --json            # machine-readable output
```

Example output:

```
Skills (all scope):
  build-context                  1.0.0  [repo]
  documenter                     1.0.0  [repo]
  spec-builder                   1.0.0  [repo]
  security-review                1.0.0  [user]   [disabled]
```

### Inspect a skill

```powershell
felix skill show spec-builder
```

Prints the manifest fields, installation path, enabled status, and the full content of `prompt.md`.

### Enable / disable a skill

```powershell
felix skill enable  security-review
felix skill disable security-review
```

Disable writes the skill ID to `skills.disabled` in `.felix/config.json`. The skill remains installed and is listed in `felix skill list` (marked `[disabled]`), but it is not loaded at runtime.

---

## Writing a Skill

Here is a minimal worked example — a `test-advisor` skill that fires when requirements touch test files.

**`skill.json`**

```json
{
  "id": "test-advisor",
  "name": "Test Advisor",
  "description": "Reminds the agent of testing conventions when test files are in scope",
  "version": "1.0.0",
  "triggers": {
    "applyTo": ["tests/**", "**/*.test.*", "**/*.spec.*"],
    "tags":    ["testing"]
  }
}
```

**`prompt.md`**

```markdown
## Test Advisor

When writing or modifying tests:

- Mirror the file structure: `src/Foo.cs` → `tests/FooTests.cs`
- Use Arrange/Act/Assert layout; one logical assertion per test
- Prefer `Assert.Equal(expected, actual)` order
- Avoid `Thread.Sleep`; use retry helpers or polling instead
- Run `dotnet test` before marking any task done
```

**Install and verify:**

```powershell
felix skill install ./my-skills/test-advisor
felix skill show test-advisor
```

The next time the agent processes a requirement with `applyTo: ["tests/**"]` or `tags: ["testing"]`, `test-advisor/prompt.md` will be injected into the `{{SKILLS}}` placeholder.

---

## Skill Loading Order

Skills are assembled into the prompt in a deterministic order on each iteration:

1. **User scope** skills are scanned first.
2. **Repo scope** skills are scanned second. When a repo skill shares an `id` with a user skill, the repo version replaces the user version.
3. Among matched skills, ordering is alphabetical by `id`.
4. Disabled skill IDs (from `skills.disabled` in `config.json`) are excluded.
5. The assembled block is passed to the token budgeter. If the budget is exceeded, skills are evicted (highest-`id` first, then lower-priority placeholders).

This means **repo skills take precedence over user skills** — team-level conventions override personal preferences.

---

*See also: [MARKETPLACE.md](MARKETPLACE.md) for remote skill install · [CONFIGURATION.md](CONFIGURATION.md) for `skills.disabled` config key · [CLI.md](CLI.md) for the full `felix skill` command reference*

## Graphify Investigator

`felix graphify setup --local` and `felix graphify setup --team` install `.felix/skills/graphify-investigator/`. The skill is loaded only when `graphify.enabled` is true and `graphify.skill_enabled` is not false.

The skill tells agents to query Graphify for architecture, call-flow, dependency, symbol, and cross-file investigation using `felix graphify query`, `felix graphify path`, and `felix graphify explain`. It also tells agents not to read or inject `GRAPH_REPORT.md` wholesale.

See [GRAPHIFY.md](GRAPHIFY.md) for setup and team workflow details.

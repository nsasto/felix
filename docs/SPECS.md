# Spec & Requirement Management

> **Quick links:** [felix spec](#felix-spec) · [felix validate](#felix-validate) · [felix list](#felix-list) · [felix status](#felix-status) · [Requirements Registry](#requirements-registry) · [Validation Criteria](#validation-criteria)

---

## Requirements Registry

`.felix/requirements.json` is the slim index Felix uses to schedule and track work:

```json
{
  "requirements": [
    {
      "id": "S-0001",
      "title": "Auth email sign-in",
      "spec_path": "specs/auth-email-signin.md",
      "status": "planned",
      "commit_on_complete": false
    }
  ]
}
```

Rich metadata (`priority`, `tags`, `depends_on`) lives in `specs/*.meta.json` sidecars. Keep `requirements.json` boring and stable.

**Status values:** `draft` → `planned` → `in_progress` → `complete` / `blocked`

---

## Validation Criteria

Leave checkboxes **unchecked** — Felix re-evaluates them every iteration:

```markdown
## Validation Criteria

- [ ] Tests pass: `pytest` (exit code 0)
- [ ] Lint clean: `npm run lint` (exit code 0)
- [ ] Login endpoint responds: `curl -X POST http://localhost:3000/api/auth/login -d '{"username":"test","password":"test"}' -H "Content-Type: application/json"` (status 200)
```

**Critical rule:** Only use backticks for **actual executable commands**. Use **bold** for file paths, plain text for URLs and placeholders. We learned this the hard way when someone wrote:

```markdown
- [ ] File exists: `src/config.py`
```

The validator tried to execute `src/config.py` as a command and exploded. Correct version:

```markdown
- [ ] File exists: **src/config.py** (file exists)
```

The script looks for `## Validation Criteria` first, then falls back to `## Acceptance Criteria`.

---

## `felix spec`

Manage requirement specs. All subcommands operate on `specs/` and `.felix/requirements.json`.

### `felix spec create <description>`

**Interactive mode (asks questions):**

```bash
felix spec create "Add user authentication"
```

**Quick mode (makes reasonable assumptions):**

```bash
felix spec create "Add user authentication" --quick
```

**What `--quick` does:**

- Skips asking for detailed description (uses the title)
- Defaults to planned status
- No dependencies
- Generates minimal acceptance criteria

**Interactive mode asks:**

1. Do you want to provide a detailed description? (y/N)
2. What status should this be? (planned/draft/in-progress)
3. Does this depend on other requirements? (comma-separated IDs)
4. Do you want to generate acceptance criteria with the agent? (y/N)

**Behind the scenes:** Felix auto-generates the next requirement ID (finds highest S-NNNN in `specs/` and increments), creates the spec file with frontmatter, and optionally launches the agent in spec-builder mode to write detailed acceptance criteria.

**Pro tip:** Use `--quick` for small, obvious requirements. Use interactive mode for complex features that need detailed planning.

---

### `felix spec list`

`felix spec list` is the canonical command. The top-level `felix list` alias still works for compatibility.

```bash
felix spec list

# Filter by status
felix spec list --status planned
felix spec list --status complete
felix spec list --status blocked

# Filter by priority
felix spec list --priority high
felix spec list --priority low

# Filter by tags (comma-separated)
felix spec list --tags backend
felix spec list --tags backend,auth

# Show requirements blocked by incomplete dependencies
felix spec list --blocked-by incomplete-deps

# Include dependency details in output
felix spec list --with-deps

# JSON for scripting
felix spec list --format json | jq '.[] | select(.status == "blocked")'
```

**Useful patterns:**

```bash
# Morning standup: what got done overnight?
felix spec list --status complete

# Planning: what's ready to work on?
felix spec list --status planned

# What's stuck on unfinished dependencies?
felix spec list --blocked-by incomplete-deps

# Troubleshooting: what's stuck?
felix spec list --status blocked
```

---

### `felix spec fix`

Scan specs folder and fix alignment between `specs/` directory and `requirements.json`.

```bash
felix spec fix

# Auto-rename duplicate spec IDs
felix spec fix --fix-duplicates
```

**What this does:** Scans all `S-*.md` files in `specs/` and reconciles them against `.felix/requirements.json`:

- Adds entries for spec files that are missing from `requirements.json`
- Rebuilds the `requirements.json` view of the current `specs/` directory
- With `--fix-duplicates`: detects duplicate `S-NNNN` IDs and renames files to the next available ID

**When to use:**

- After manually creating or deleting spec files without using `felix spec create`/`delete`
- After cloning a repo where `requirements.json` is out of sync with `specs/`
- When you see "requirement not found" errors that don't match your spec files

---

### `felix spec delete <requirement-id>`

```bash
# Delete with confirmation
felix spec delete S-0001

# Delete without prompting
felix spec delete S-0001 --yes
```

**What gets deleted:**

- The spec file (`specs/S-NNNN.md`)
- The requirement entry in `.felix/requirements.json`

**What stays:**

- Historical run artifacts in `runs/` (for audit trail)
- Git history (no force deletion)

---

### `felix spec status <requirement-id> <status>`

Update the status of a requirement without hand-editing JSON.

```bash
felix spec status S-0042 planned
felix spec status S-0042 in_progress
felix spec status S-0042 complete
felix spec status S-0042 blocked
```

**Common use cases:**

- Unblocking a blocked requirement: `felix spec status S-0042 planned`
- Manually marking something complete: `felix spec status S-0042 complete`
- Forcing a requirement back into the queue: `felix spec status S-0042 in_progress`

---

### `felix spec pull`

Sync specs from the remote server.

```bash
# Pull all specs that are out of date
felix spec pull

# Preview without writing any files
felix spec pull --dry-run

# Force overwrite of local files even if they exist
felix spec pull --force

# Also delete local specs that no longer exist on the server
felix spec pull --delete
```

**What it does:**

1. Calls `POST /api/sync/specs/check` with a manifest of local file hashes
2. Server responds with which files are missing, outdated, or current
3. Downloads only the files that differ (`.md` specs and `.meta.json` sidecars)
4. Writes them into the repo, updates `.felix/spec-manifest.json`, and optionally removes files the server no longer tracks

If a newly downloaded markdown spec does not yet have a `.meta.json` sidecar, Felix creates a fallback sidecar locally so metadata resolution stays consistent until the next full sync.

**What are `.meta.json` sidecars?**

Each spec has an accompanying `specs/S-NNNN-name.meta.json` file containing rich metadata stored in the server DB:

```json
{
  "priority": "high",
  "tags": ["backend", "auth"],
  "depends_on": ["S-0001", "S-0002"],
  "updated_at": "2026-02-23"
}
```

- Generated automatically on `spec create` and `spec fix`
- Gitignored (`specs/*.meta.json`) so they don't pollute version control
- Used by the agent loop to resolve `depends_on` for the current requirement
- Downloaded fresh each time via `felix spec pull`

**When to use it:**

- Before starting work in remote/team mode to get the latest server state
- When another team member has updated spec priorities or dependencies
- After `felix setup` on a new clone — pull specs before running the loop

**Authentication:** Requires `sync.api_key` in `.felix/config.json` or `FELIX_SYNC_KEY` env var.

**Safety rules:**

- Existing local files that are not tracked in `.felix/spec-manifest.json` are skipped unless you pass `--force`
- Server-deleted files are only removed locally when you pass `--delete`
- `--dry-run` shows planned download, update, and delete actions without touching files

```bash
# Typical workflow before running the agent loop in team mode
felix spec pull
felix loop
```

---

### `felix spec push`

Upload local specs to the remote server.

```bash
# Upload all specs
felix spec push

# Preview without uploading
felix spec push --dry-run

# Re-upload all even if unchanged
felix spec push --force
```

**What it does:** Reads all `*.md` files from `specs/`, encodes them as base64, and uploads them to `POST /api/sync/specs/upload` in chunks. Felix retries failed chunks before giving up and reports per-file upload or skip results after the server responds.

When `--force` is set, Felix asks the server to create missing requirement mappings if the backend supports that behavior.

**Authentication:** Requires `sync.api_key` in `.felix/config.json` or `FELIX_SYNC_KEY` env var.

**When to use:**

- After creating or editing specs locally that you want remote agents to pick up
- Before starting a distributed team session — push local changes so others get them via `felix spec pull`
- After bulk-creating specs with `felix spec create --quick`

**Typical team workflow:**

```bash
# Developer A: create and push specs
felix spec create "Add rate limiting" --quick
felix spec push

# Agent on another machine: pull and work
felix spec pull
felix loop
```

---

## `felix validate <requirement-id>`

**What it does:** Runs requirement-level acceptance verification from the spec file without running the full agent loop.

**What this answers:** "Has this requirement been achieved according to its own acceptance criteria?"

**What it does not do:** It does not replace loop backpressure checks. Backpressure is the per-iteration safety gate (tests/build/lint before commit), while `felix validate` is a requirement-level done check.

```bash
felix validate S-0001

# Machine-readable result for CI/UI
felix validate S-0001 --json
```

**Why you need this:**

1. **Testing your acceptance criteria** before letting the agent loose
2. **Debugging failures** — run validation in isolation to see what's actually broken
3. **Post-deployment checks** — validate requirements still work after merging
4. **Progress confidence** — measure completion against explicit, executable criteria

**Exit codes:** `0` all acceptance criteria passed · `1` one or more failed · `2` invalid arguments or requirement not found

---

## `felix list`

Top-level alias for `felix spec list`. Kept for compatibility.

```bash
felix list
felix list --status planned
felix list --format json
```

See [`felix spec list`](#felix-spec-list) for the full option reference.

---

## `felix status [requirement-id]`

**Check on everything:**

```bash
felix status
```

**Check one requirement:**

```bash
felix status S-0001
```

**Get machine-readable output:**

```bash
felix status --format json
```

**What you'll see:**

- Current requirement status (planned, in_progress, complete, blocked)
- Agent name and last execution time
- Validation results
- Git commit associated with completion

**Why this matters:** When your agent has been churning for 30 minutes and you're wondering if it's actually working or stuck in a loop, `felix status` is your reality check.

---

*See also: [RUNNING.md](RUNNING.md) for executing requirements · [SEARCH.md](SEARCH.md) for `felix deps` dependency graph · [CONTEXT.md](CONTEXT.md) for run artifacts · [CLI.md](CLI.md) for global options and the full command index*

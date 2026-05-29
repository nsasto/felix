# Repo Split: Open-Source CLI + Closed SaaS App

> **Status:** Planned
> **Priority:** High (prerequisite for public launch)

## Overview

Split the monorepo into two repositories:

- **Open-source** (`github.com/nsasto/felix`) — CLI agent engine, the core product developers adopt
- **Private** (new repo, e.g. `github.com/nsasto/felix-app`) — SaaS backend, dashboard, landing site, and premium tray manager

This follows the proven pattern used by Terraform, Pulumi, Grafana k6, etc: open CLI, closed cloud platform.

## Rationale

- Community value is in the CLI — agent engine, backpressure, spec-driven workflow, plugin system
- App is the SaaS moat — dashboard, team orchestration, run visualization, auth
- Tray manager is a premium desktop perk for SaaS users
- Sync plugin bridges open CLI → closed SaaS via documented API contracts
- Architecture is already decoupled — zero shared source code, independent builds, no config overlap

---

## Open-Source Repo (felix)

### Keeps

- `.felix/` — PowerShell agent engine (core, commands, plugins)
- `src/Felix.Cli/` — C# CLI wrapper
- `felix/` — agent launcher scripts
- `scripts/` — build, release, test scripts (CLI-relevant ones)
- `specs/` — spec templates and examples
- `docs/` — CLI documentation (FELIX_CLI.md, SYNC_OPERATIONS.md)
- `AGENTS.md`, `README.md`, `CONTEXT.md`, `HOW_TO_USE.md`, `FEATURES.md`
- `runs/` — example run structure (or .gitignore it)
- `learnings/` — developer notes

### Removes

- `app/` — entire directory (backend, frontend, landing, tray-manager)
- `schema.sql` — backend DB schema
- `wrangler.toml` — Cloudflare Pages config
- `build.sh` — frontend/landing build script
- `felix.sln` — VS solution (only contains tray-manager)
- Top-level `package.json` — frontend/landing build orchestration
- `Enhancements/` — internal planning docs (optional: keep relevant ones)

### Needs

- [ ] LICENSE file (MIT)
- [ ] Updated README.md — remove app references, add "Felix Cloud" callout with link to runfelix.io
- [ ] Updated AGENTS.md — remove frontend/backend test/build instructions
- [ ] .gitignore cleanup — remove app-specific entries
- [ ] Contributing guide (CONTRIBUTING.md)
- [ ] Issue templates for CLI bugs, feature requests, plugin submissions

---

## Private Repo (felix-app)

### Keeps

- `app/backend/` — FastAPI API server
- `app/frontend/` — React dashboard
- `app/landing/` — Marketing site
- `app/tray-manager/` — Desktop tray app (premium)
- `schema.sql` — DB schema
- `wrangler.toml` — Cloudflare config
- `build.sh` — Frontend build script
- `package.json` — Build orchestration
- `felix.sln` — VS solution for tray-manager

### Needs

- [ ] Own README with setup instructions
- [ ] Own CI/CD pipeline
- [ ] Own AGENTS.md for backend/frontend dev workflow
- [ ] Copy relevant Enhancement docs

---

## Execution Steps

### Phase 1: Prepare (before split)

- [x] Choose license for CLI repo (MIT) — LICENSE file added
- [x] Audit all files — found 4 critical issues (see Audit Findings below)
- [x] Confirm `.felix/plugins/sync-http/` only uses documented API endpoints — clean (found unauth backend bug, see below)
- [x] Clean up `runs/` — already gitignored and untracked, no secrets found
- [x] Remove or redact internal planning docs from Enhancements/ — 13 SaaS-internal docs untracked + gitignored
- [x] Check git history for any previously-committed secrets (already audited — clean)

### Phase 2: Create private repo

- [ ] Create `felix-app` private repo on GitHub
- [ ] Copy `app/`, `schema.sql`, `wrangler.toml`, `build.sh`, `package.json`, `felix.sln` into it
- [ ] Set up its own README, .gitignore, CI/CD
- [ ] Verify backend, frontend, landing, and tray-manager all build independently
- [ ] Push to private repo

### Phase 3: Clean public repo

- [ ] Remove `app/` directory from felix repo
- [ ] Remove `schema.sql`, `wrangler.toml`, `build.sh`, `felix.sln`, top-level `package.json`
- [ ] Update README.md — CLI-focused, link to runfelix.io for cloud features
- [ ] Update AGENTS.md — remove app build/test instructions
- [ ] Add LICENSE file
- [ ] Add CONTRIBUTING.md
- [ ] Prune Enhancements/ — keep CLI-relevant, remove cloud/app internals
- [ ] Verify CLI builds and tests pass with `scripts/test-backend.ps1` removed or updated
- [ ] Commit and push

### Phase 4: Post-split

- [ ] Create GitHub release v1.0.0 on cleaned public repo
- [ ] Update runfelix.io download links if needed
- [ ] Set up CI for public repo (GitHub Actions: build CLI, run tests)
- [ ] Archive or make current monorepo private if keeping as backup

---

## Decisions

- **Git history**: Fresh private repo for app (no need to preserve app git history separately). Public repo keeps full history (already cleaned of co-author lines and secrets).
- **Sync plugin ships open**: `.felix/plugins/sync-http/` reveals API contract (endpoint paths, payload shapes). This is intentional — it's documentation, not a leak. Community can build alternative sync targets.
- **Tray manager = premium**: Ships in SaaS installer, not in open-source CLI builds.
- **Enhancements/**: Most are internal planning — move to private repo or archive. Keep only CLI-relevant ones public.

## Open Questions

- [x] Should `runs/` directory ship in open repo as examples, or be fully gitignored? → **Gitignored** (already done, no sensitive data but no value as examples)
- [ ] Do we want a `felix-app` monorepo or split further (backend, frontend, landing)?
- [ ] CI for public repo — GitHub Actions? What matrix (Windows, Linux, macOS)?

---

## Phase 1 Audit Findings

Issues discovered during Phase 1 audit that must be resolved in Phase 3 (clean public repo):

### Critical: Scripts importing from app/backend

| Script                                   | Issue                                                  | Resolution                                      |
| ---------------------------------------- | ------------------------------------------------------ | ----------------------------------------------- |
| `scripts/generate-sync-key.py` (L46-51)  | Adds `app/backend` to sys.path, imports `utils.keygen` | Move to private repo or inline the keygen logic |
| `scripts/migrate_agent_keys.py` (L15-18) | Imports `keygen` and `normalize_git_url` from backend  | Move to private repo (admin-only script)        |
| `scripts/setup-db.ps1` (L55)             | Hardcoded path `app/backend/migrations`                | Move to private repo (DB setup is SaaS-only)    |

### Critical: Config referencing app paths

| File                          | Issue                                                                      | Resolution                                                  |
| ----------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `.felix/config.json` (L21-22) | Backpressure commands run `app/backend` pytest and `app/frontend` npm test | Remove app test commands; keep only CLI-relevant validation |

### Security: Unauthenticated backend endpoint

| File                                   | Issue                                            | Resolution                                           |
| -------------------------------------- | ------------------------------------------------ | ---------------------------------------------------- |
| `app/backend/routers/agents.py` (L492) | `POST /api/agents/{agent_id}/status` has no auth | Add `Depends(verify_api_key)` — fix before deploying |

### Enhancements removed from public tracking

**Kept public (CLI-relevant):** AGENTSCRIPT_MIGRATION, AGENTSCRIPT_TESTPLAN, CLI, CLI_HARDENING_NOTES, GIT_COMMIT_RULES, LOOP_ENHANCEMENTS, SPEC_BUILDER

**Removed from public (SaaS-internal):** ARCHITECTURE, CLOUD_MIGRATION_PLAN, CLOUD_ORCHESTRATION, LANDING_PAGE, PRODUCTION_PH1, PRODUCTION_PH1_MIGRATION, PRODUCTION_PH2, PRODUCTION_ROADMAP, RUNS_IMPLEMENTATION, RUNS_PHASE2, UI_GUIDELINES, UI_TODO, REPO_SPLIT

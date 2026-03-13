# Release Notes - v1.0.0

**Release Date:** March 1, 2026

## Highlights

- **☁️ Cloud-ready** — Full production deployment stack: Render (backend), Cloudflare Pages (frontend), Supabase (auth + DB)
- **🔐 Supabase Auth** — OAuth login, JWT validation (HS256/RS256/ES256), per-org RLS policies, onboarding gate
- **🌐 Landing page** — Public-facing site at runfelix.io with waitlist, CLI docs, and lifecycle visual
- **📤 `felix spec push`** — Upload local spec files to server DB (completes the spec sync round-trip)
- **📋 `felix context push/pull`** — Sync README, CONTEXT.md, and AGENTS.md to/from server
- **🤖 Agent hostname on Kanban** — See which machine is running each reserved requirement
- **🐛 State machine fix** — `Blocked → Planning → Building` transition now works correctly
- **🔧 `pytest` PATH fallback** — Automatically falls back to `python -m pytest` when `pytest` isn't in PATH
- **📄 `requirements.json` normalization** — Bare-array format from old `setup` gracefully handled everywhere

---

## New Features

### Cloud Deployment

Felix is now production-deployable with a first-class cloud stack:

| Layer       | Platform                                                                                      |
| ----------- | --------------------------------------------------------------------------------------------- |
| Backend API | [Render](https://render.com) — `render.yaml` included                                         |
| Frontend UI | [Cloudflare Pages](https://pages.cloudflare.com) — `_redirects` SPA fallback, `wrangler.toml` |
| Database    | Supabase Postgres (via `asyncpg` + PgBouncer-safe `statement_cache_size=0`)                   |
| Auth        | Supabase Auth (OAuth + JWT)                                                                   |
| Landing     | Cloudflare Pages — `app/landing/` subtree                                                     |

The backend validates all API calls against a JWT signed by Supabase. The frontend redirects to `/app/` with token included so React can process auth.

---

### Supabase Auth Integration

Full authentication pipeline from browser login to API call:

- **OAuth login** — Supabase OAuth with redirect to `/app/` (not root) so the React app processes the auth token
- **JWT validation** — supports HS256 (secret), RS256 (JWKS), and ES256 (new Supabase signing keys)
- **Manifest endpoints** — accept both Felix API keys and Supabase JWTs for CLI/UI interop
- **`get_user_context`** — all routers that need `org_id` now resolve it from DB via this helper (not hardcoded dev constants)
- **Dev bypass** — `AuthGate` skips authentication in local development mode

**Org onboarding gate:**

Users without an org are redirected to an org-creation screen on first login. No access to the rest of the app until an org exists (Phase 2b enforcement).

**RLS policies** — Row Level Security enabled on all tables. Org-scoped access via `auth.uid()` checks in migration `028_enable_rls.sql`.

---

### Landing Page (`app/landing/`)

Complete public-facing site deployed to Cloudflare Pages:

- **Hero** — clear action-oriented heading
- **CLI lifecycle visual** — replaces the old command reference table; shows the agent workflow end-to-end
- **"Wake up to completed features"** — CTA section replacing the CLI Quick Start
- **Waitlist** — form wired to Supabase REST API (`waitlist` table, migration included)
- **Works-with logos** — Factory.ai, GitHub, and others
- **Mobile-responsive** — full layout tested at mobile breakpoints
- **Cloudflare Pages build** — Vite + Tailwind v4 plugin, root `package.json` for auto-detect, `_redirects` SPA fallback

---

### `felix spec push`

Completes the bidirectional spec sync. Uploads local spec files to the server DB.

```powershell
felix spec push
felix spec push --dry-run    # show what would be uploaded without sending
felix spec push --force      # re-upload even unchanged files
```

Works in tandem with `felix spec pull` to keep local specs and the server in sync.

---

### `felix context push` / `felix context pull`

Sync project documentation files to/from the server:

```powershell
# Upload README.md, CONTEXT.md, AGENTS.md
felix context push
felix context push --dry-run

# Download from server
felix context pull
felix context pull --force
```

Files are content-addressed (SHA256) — unchanged files are skipped automatically. Base64-encoded for safe transport through the manifest API.

---

### Agent Hostname on Kanban

The `RESERVED` pill on Kanban cards now shows the hostname of the machine running the requirement:

```
[RESERVED by dev-laptop]
```

Extracted from agent registration metadata (`hostname`, `adapter`, `model`). Makes it easy to see which agent is working on what, especially in multi-machine setups.

---

### Org Context Switcher (Frontend)

Users can belong to multiple organisations. The org context switcher lets you toggle between them without re-logging in. Project routing resolves org/project from DB rather than `DEV_` environment constants.

---

## Bug Fixes

### State Machine: `Blocked → Building` Crash

When a requirement was `Blocked` and the agent re-started on the next iteration, it tried to transition directly to `Building` — which is illegal (`Blocked` can only go to `Planning`). The agent would crash with:

```
Invalid state transition: Blocked -> Building. Valid transitions: Planning
```

**Fix:** `mode-selector.ps1` now inserts the required `Planning` intermediate state when resuming from `Blocked`:

```
Blocked → Planning → Building
```

---

### `pytest` Not Found in Validation

When `pytest` isn't installed globally (only inside a venv), validation commands would fail with `'pytest' is not recognized`. Felix now automatically falls back to `python -m pytest` before failing:

```
[info] pytest not in PATH, falling back to: python -m pytest tests/
```

---

### `requirements.json` Bare Array Format

`felix setup` was writing `requirements.json` as a bare JSON array `[]` instead of the expected wrapper `{ "requirements": [] }`. This caused `PropertyAssignmentException` on the `.requirements` property across multiple commands.

**Fixed in:**

- `commands/setup.ps1` — now writes the correct structure on init
- `core/state-manager.ps1` — normalizes on read
- `core/work-selector.ps1` — normalizes on read (main scheduling path)
- `core/spec-builder.ps1` — normalizes on read (prevents data loss on save)
- `core/requirements-utils.ps1` — normalizes in both `Update-RequirementStatus` and `Update-RequirementRunId`
- `commands/spec-fix.ps1` — normalizes on load
- `commands/spec.ps1` — normalizes in `create` and `delete` handlers
- `commands/run-next.ps1` / `commands/loop.ps1` — normalizes in sync status-update path

---

### `agents.json` Legacy `id` Field

After the `id` → `key` rename in the agent schema, projects that still had `"id"` in `agents.json` would fall through to the first-agent fallback and log a spurious warning on every run:

```
WARN Agent ID ag_xxx not found in agents.json. Falling back to first agent (droid)
```

**Fix:** `config-loader.ps1`, `context-builder.ps1`, and `agent.ps1` now all accept either `id` or `key` and normalize to `key` transparently. No project-side migration needed.

---

### Other Fixes

| Area               | Fix                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| Health check       | URL construction strips `/api` suffix before appending `/health`                                                         |
| CORS               | `runfelix.io` added to default allowed origins                                                                           |
| JWT                | ES256 support added for new Supabase signing keys; fail-fast with 500 on HS256 without secret                            |
| Supabase manifests | `verify_api_key` used on manifest endpoints; JWTs correctly bypassed in key check                                        |
| Context push/pull  | Fixed double-encoding in push/pull cycle; base64-encode body for PS 5.1 UTF-8                                            |
| Context push       | `ReadAllText` instead of `Get-Content` to avoid encoding issues                                                          |
| OAuth redirect     | `redirectTo` points to `/app/` so auth token is processed by React                                                       |
| SPA routing        | Catch-all `_redirects` and `/app/` base path correct in Cloudflare build                                                 |
| Frontend routes    | Vite `BASE_PATH` prepended to client-side routes in production                                                           |
| Agent registration | `populate registered_by_user_id` from API key on register-sync                                                           |
| Agent registration | Upserts machine and resolves `profile_id` from metadata                                                                  |
| Sync key           | `FELIX_SYNC_KEY`/`URL` env vars applied correctly when sync enabled via config (not only env)                            |
| Sync status        | Skip stale local `complete` check when `TrustServerStatus` is set                                                        |
| Local req sync     | `run-next` syncs local `requirements.json` with server status before executing agent                                     |
| Log rotation       | Windows-safe rotating log handler avoids `PermissionError` on rollover                                                   |
| Pydantic           | `model_config` used instead of deprecated `Config` class for Pydantic v2                                                 |
| DB migrations      | PgBouncer compatibility: `statement_cache_size=0`; skip `_supabase_` migrations in local setup                           |
| Tests              | Fixed 7 pre-existing test failures (`agent[key]` KeyError, `run[requirement_id]` KeyError, profile DB crash on register) |
| Command registry   | `spec-push`, `context-pull`, `context-push` added to subcommand exclusion list in registry check                         |

---

## Improvements

### Settings / Config moved to DB

Agent settings and project configuration are now stored in the database rather than flat files. The project manifest is fetched from the API rather than read from disk on the backend.

### User Display

- OAuth display name and avatar shown in user menu (not UUID)
- App favicon and web manifest added

### Spec Sync: Fully DB-Driven

`felix spec pull` now queries the server DB for spec content rather than reading from disk. Combined with `felix spec push`, the full round-trip is:

```
Local specs/ → push → Server DB → pull → Local specs/
```

### CLI Reliability

- `felix spec create` prompts for description if not passed on the command line
- `--quick` / `-q` flag on `spec create` skips interactive Q&A
- `.env` auto-loaded in `felix-agent.ps1` so `FELIX_SYNC_KEY` always reaches the sync plugin
- `emit-log` pretty-printed in rich mode; lock files excluded from bundle

---

## Upgrade Notes

### From v0.9.x

1. **Rebuild and reinstall the CLI:**

   ```powershell
   cd C:\dev\felix
   .\scripts\build-and-install.ps1
   ```

2. **Fix `requirements.json`** if your project has the bare-array format — run:

   ```powershell
   felix spec fix
   ```

   This will rewrite it in the correct wrapper format.

3. **`agents.json`** — if you have `"id"` fields, they are now accepted transparently. You can optionally rename to `"key"` for consistency with current schema.

4. **Cloud deployment** — if deploying to Render + Cloudflare Pages, see `docs/SYNC_OPERATIONS.md` and `Enhancements/PRODUCTION_PH2.md` for the full deployment checklist, environment variables, and migration steps.

5. **Supabase** — set `SUPABASE_URL`, `SUPABASE_JWT_SECRET` (for HS256) or leave unset (for RS256/ES256 via JWKS) in your Render environment.

---

## What's Next

- Real-time Kanban updates via Supabase Realtime (replacing SSE polling)
- Org-scoped project management and multi-agent orchestration dashboard
- CLI installer at `runfelix.io/install.ps1`

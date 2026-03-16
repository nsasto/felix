# Release Notes - v1.0.1

**Release Date:** March 16, 2026

## Highlights

- **📦 Chunked spec upload** — `felix spec push` now uploads in configurable chunks with retry logic, preventing timeouts on large projects
- **📋 `felix validate --json`** — Machine-readable JSON output for CI pipelines and dashboards
- **🧪 Comprehensive test suite** — 8 new test modules covering agent adapters, context builder, event emission, session management, setup utilities, spec builder, task handler, text utilities, and work selection
- **⚙️ GitHub Actions CI** — Automated test runs on push/PR to `main` with dedicated Windows runner
- **📦 Automated release pipeline** — New `package-release` workflow builds, packages (Inno Setup), and publishes GitHub Releases on version bump
- **🔄 Server-side requirement completion** — `on-runcomplete` plugin now marks requirements complete via `/api/sync/work/complete` independently from run finish sync
- **📖 Plugin authoring guide** — Full developer reference for writing Felix plugins

---

## New Features

### Chunked Spec Upload with Retry

`felix spec push` now splits large uploads into chunks to avoid HTTP timeouts. Configurable via environment variables:

| Variable                      | Default | Description                     |
| ----------------------------- | ------- | ------------------------------- |
| `FELIX_SPEC_PUSH_CHUNK_SIZE`  | 10      | Files per upload batch          |
| `FELIX_SPEC_PUSH_TIMEOUT_SEC` | 120     | HTTP timeout per chunk          |
| `FELIX_SPEC_PUSH_RETRIES`     | 2       | Retry attempts per failed chunk |

Progress reporting adapts automatically — plain text in CI/redirected output, `Write-Progress` bars in interactive terminals.

### `felix validate --json`

The validation command now accepts a `--json` flag for machine-readable output, suitable for CI gates and dashboards:

```powershell
felix validate S-0002 --json
```

Returns a JSON object with `success`, `requirementId`, `exitCode`, `reason`, and `output` fields. Error cases (missing requirement, missing validator script) also produce structured JSON when the flag is set.

### GitHub Actions CI

New workflow (`.github/workflows/tests.yml`) runs the full PowerShell test suite on every push and PR to `main`. Configures Git identity for tests that require commits and runs on `windows-latest`.

### Automated Release Pipeline

New workflow (`.github/workflows/package-release.yml`) triggers on version bumps or release notes changes. Builds the .NET CLI, packages with Inno Setup, and creates GitHub Releases with stable asset aliases (`felix-setup.exe`).

### Server-Side Requirement Completion

The `sync-http` plugin's `on-runcomplete` hook now calls `/api/sync/work/complete` to mark requirements as completed on the server, independently from the `/api/runs/{id}/finish` call. This ensures server-side item state stays accurate even if the run finish endpoint is temporarily failing and being retried from the outbox.

### Plugin Authoring Guide

New `docs/PLUGINS.md` — a complete reference for writing Felix plugins, including:

- Quick start and manifest schema
- All 11 lifecycle hooks documented
- State management, configuration, and circuit breaker patterns
- Two worked examples (commit-prefix, slack-notify)

---

## Test Coverage

8 new test modules added, bringing comprehensive coverage to previously untested subsystems:

| Test Module            | Coverage                                  |
| ---------------------- | ----------------------------------------- |
| `test-agent-adapters`  | Agent adapter registration and invocation |
| `test-context-builder` | LLM context assembly                      |
| `test-emit-event`      | Plugin event emission pipeline            |
| `test-session-manager` | Session lifecycle and persistence         |
| `test-setup-utils`     | Project setup and scaffolding             |
| `test-spec-builder`    | Spec file generation                      |
| `test-task-handler`    | Task dispatch and execution               |
| `test-text-utils`      | String utilities                          |
| `test-work-selector`   | Requirement selection logic               |

Existing tests updated to prevent git credential prompts in CI environments.

---

## Bug Fixes & Improvements

- **`spec push --force`** — New flag to re-upload all specs, including those with missing requirement mappings on the server
- **Windows installer** — Updated to use `setup.exe` with stable download URLs
- **`.gitignore`** — Temp scripts excluded from version control
- **Help docs** — Updated CLI help and feature documentation to reflect new flags and commands

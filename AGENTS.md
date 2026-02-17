# Agents - How to Operate This Repository

This file tells Felix **how to run the system**.

## Install Dependencies

Dependencies are managed automatically by the test scripts. If you need to set up manually, see HOW_TO_USE.md. The user should set this up prior to engaging you.

## Run Tests

### Backend Tests

```powershell
powershell -File .\scripts\test-backend.ps1
```

Auto-creates venv, installs dependencies, creates tests/ directory if needed.
Exit code 5 means "no tests found" (not a failure).

### Frontend Tests

```powershell
powershell -File .\scripts\test-frontend.ps1
```

Auto-installs npm dependencies if needed.

### Test File Locations

- Backend tests: `app/backend/tests/test_*.py`
- Frontend tests: `app/frontend/src/__tests__/*.test.tsx`

## Build the Project

```powershell
# Backend builds are not needed (Python)
# Frontend build:
cd app/frontend; npm run build; cd ../..
```

## Start the Application

### Development Mode

**Backend (FastAPI):**

```bash
cd app/backend
python main.py
# Runs on http://localhost:8080
# API docs at http://localhost:8080/docs
```

**Frontend (React):**

```bash
cd app/frontend
npm run dev
# Runs on http://localhost:3000
```

### Running Felix agent (PowerShell)

Run the agent locally with PowerShell (examples):

```powershell
# Start the agent for the repository at C:\dev\Felix
.\felix\felix-agent.ps1 C:\dev\Felix

# Alternative: run the looped runner
.\felix\felix-loop.ps1 C:\dev\Felix

# Sync plugin loads automatically if enabled in config
# Check: .felix/outbox/ will contain *.jsonl if queued
```

### Sync Configuration (Optional)

Enable artifact mirroring to server for team collaboration:

**Environment Variables:**

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"  # Optional
```

**Temporary Sync Override (CLI Flag):**

Use the `--Sync` flag to enable sync for a single run without modifying config.json:

```powershell
# Enable sync just for this run (overrides config.json)
felix run S-0001 --sync

# Combine with other flags
felix run S-0001 --sync --quick --no-commit
```

The flag sets `FELIX_SYNC_ENABLED` environment variable for the agent subprocess only. It doesn't persist across runs.

**Config File (.felix/config.json):**

```json
{
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "http://localhost:8080",
    "api_key": null
  }
}
```

**How It Works:**

- Agent writes artifacts locally first (always)
- Sync plugin queues uploads in `.felix/outbox/*.jsonl`
- Automatic retry on network failure (eventual consistency)
- Idempotent: unchanged files skip upload (SHA256 check)
- Batch upload: all run artifacts in single HTTP request

**Console Output:**

When sync is enabled, agent startup shows:

```
[18:51:16.212] INFO [sync] Sync enabled → http://localhost:8080
[18:51:16.431] INFO [sync] Agent registered successfully
```

**Check Sync Status:**

- Pending uploads: `ls .felix\outbox\*.jsonl`
- Recent synced runs: Check backend at http://localhost:8080/docs → GET /api/runs

See **Enhancements/runs_migration.md** for architecture details.

### Agent Profiles (Local vs Remote)

- Local CLI runs use **.felix/agents.json** in the repo as the source of agent profiles.
- User profile **%USERPROFILE%\.felix\agents.json** is no longer used.
- Remote agents use DB-managed profiles and runtime registrations; local file profiles are only for local execution.
- Agent registration happens via the app/backend and persists in the database.

### Production Mode

```bash
# To be added when production setup is ready
```

## Validate Requirement

Run validation checks for a specific requirement. The validation script reads acceptance criteria from the spec file and executes any commands specified.

```bash
# Validate a specific requirement
py -3 scripts/validate-requirement.py S-0002

# If `py -3` is not available, use `python` or set the full Python executable path in `.felix/config.json` under `python.executable`.

# Example output:
# Validating Requirement: S-0002
# ✅ Backend starts: `python app/backend/main.py` (exit code 0)
# ✅ Health endpoint responds: `curl http://localhost:8080/health` (status 200)
# VALIDATION PASSED for S-0002
```

### Exit Codes

**Validation Script (validate-requirement.py):**

- `0` - All acceptance criteria passed
- `1` - One or more acceptance criteria failed
- `2` - Invalid arguments or requirement not found

**Felix Agent (felix-agent.ps1):**

- `0` - Success: requirement complete and validated
- `1` - Error: general execution failure (droid errors, file I/O issues)
- `2` - Blocked: backpressure failures exceeded max retries (default: 3 attempts)
- `3` - Blocked: validation failures exceeded max retries (default: 2 attempts)

When the agent exits with code 2 or 3, the requirement is automatically marked as "blocked" in `.felix/requirements.json`. To unblock:

1. Fix the underlying issues (tests, validation criteria, or code)
2. Manually edit `.felix/requirements.json` and change status from `"blocked"` to `"planned"`
3. Restart the agent - it will pick up the unblocked requirement

### Validation Criteria Format

Specs should include testable validation criteria with commands and expected outcomes. The script looks for "## Validation Criteria" first, then falls back to "## Acceptance Criteria":

```markdown
## Validation Criteria

- [ ] Backend starts: `python app/backend/main.py` (exit code 0)
- [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Tests pass: `cd app/backend && pytest` (exit code 0)
```

**Important:** Only use backticks for actual executable commands. Do NOT use backticks for:

- File paths (use **bold** instead: **app/backend/main.py**)
- URLs (use plain text: http://localhost:8080)
- Placeholders (use plain text: {ComputerName})
- Configuration values (use plain text or **bold**)

The validation script executes anything in backticks as a shell command. If it's not meant to be executed, don't use backticks.

## Sync Troubleshooting

This section covers common issues with artifact sync and how to resolve them.

### Check Outbox Queue Status

```powershell
# View pending uploads
ls .felix\outbox\*.jsonl

# Count pending files
(Get-ChildItem .felix\outbox\*.jsonl).Count
```

If you see many files, the agent is queuing uploads but cannot reach the backend.

### Common Errors and Solutions

| Error                           | Cause                             | Solution                                                                             |
| ------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------ |
| 401 Unauthorized                | Invalid or expired API key        | Generate new key with `python scripts/generate-sync-key.py`, update FELIX_SYNC_KEY   |
| 429 Too Many Requests           | Rate limit exceeded (100 req/min) | Wait for rate limit reset (shown in X-RateLimit-Reset header), reduce sync frequency |
| 503 Service Unavailable         | Backend or storage unavailable    | Check backend health at /health endpoint, verify database/storage connectivity       |
| Connection refused              | Backend not running               | Start backend with `python app/backend/main.py`                                      |
| Timeout errors                  | Network issues or large uploads   | Check network, retry will happen automatically with exponential backoff              |
| "Invalid configuration" warning | Missing FELIX_SYNC_URL            | Set FELIX_SYNC_URL environment variable or configure in **.felix/config.json**       |

### Managing Large Outbox Queue

When the outbox grows large (many unsynced files):

1. **Manual flush** - restart the agent to trigger sync retry
2. **Clear stale files** - if files are corrupted or no longer needed:

   ```powershell
   # View file contents first
   Get-Content .felix\outbox\<filename>.jsonl | ConvertFrom-Json

   # Remove specific stale file (use with caution)
   Remove-Item .felix\outbox\<filename>.jsonl
   ```

3. **Check logs** - review **.felix/sync.log** for error details

### Environment Variable Reference

| Variable               | Description                            | Default                    |
| ---------------------- | -------------------------------------- | -------------------------- |
| FELIX_SYNC_ENABLED     | Enable/disable sync (true/false)       | false                      |
| FELIX_SYNC_URL         | Backend URL for sync API               | none (required if enabled) |
| FELIX_SYNC_KEY         | API key for authentication (fsk\_...)  | none (optional)            |
| FELIX_SYNC_MAX_RETRIES | Max retry attempts for failed requests | 5                          |

### Configuration Examples

**Development (local backend):**

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"
# No API key needed for local dev
```

Or in **.felix/config.json**:

```json
{
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "http://localhost:8080"
  }
}
```

**Staging:**

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://staging-felix.example.com"
$env:FELIX_SYNC_KEY = "fsk_staging_key_here"
```

**Production:**

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.example.com"
$env:FELIX_SYNC_KEY = "fsk_production_key_here"
$env:FELIX_SYNC_MAX_RETRIES = "10"  # More retries for reliability
```

### Viewing Sync Logs

The CLI writes detailed sync logs to **.felix/sync.log** (auto-rotates at 5MB):

```powershell
# View recent log entries
Get-Content .felix\sync.log -Tail 50

# Search for errors
Select-String -Path .felix\sync.log -Pattern "ERROR|WARN"
```

### Disabling Sync in Emergency

**CLI-Side Disable (per-agent)**

To disable sync on a specific CLI agent:

```powershell
$env:FELIX_SYNC_ENABLED = "false"
```

Or edit **.felix/config.json** and set `"enabled": false`.

Existing queued files in **.felix/outbox/** will remain but won't be sent until sync is re-enabled.

**Server-Side Disable (global)**

To disable sync globally on the backend (affects all agents):

```bash
# Linux/macOS
export FELIX_SYNC_FEATURE_ENABLED=false

# Windows PowerShell
$env:FELIX_SYNC_FEATURE_ENABLED = "false"
```

When disabled at the server level:

- All sync endpoints return 503 Service Unavailable
- Agents will queue uploads locally and retry when sync is re-enabled
- Non-sync endpoints (health check, metrics) remain operational

**Cleanup Orphaned Artifacts**

If you need to clean up storage files that no longer have database references:

```powershell
# Preview orphaned files (dry run)
.\scripts\cleanup-orphan-artifacts.ps1

# Actually delete orphaned files
.\scripts\cleanup-orphan-artifacts.ps1 -Force
```

See **docs/SYNC_OPERATIONS.md** for full rollback procedures.

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here

## CLI Scope

Felix CLI configuration and execution are always local to the machine running it.

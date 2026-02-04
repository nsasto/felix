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
```

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

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here


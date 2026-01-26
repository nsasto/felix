# Agents - How to Operate This Repository

This file tells Felix **how to run the system**.

## Install Dependencies

### Backend

```bash
cd app/backend
python -m pip install -r requirements.txt
```

### Frontend

```bash
cd app/frontend
npm install
```

## Run Tests

### Backend

```bash
cd app/backend
python -m pytest tests/ -v
```

### Frontend

```bash
cd app/frontend
npm test
```

### Test Structure

- Backend tests: `app/backend/tests/` (pytest)
- Frontend tests: `app/frontend/src/__tests__/` (Jest/Vitest)
- Run individual test files: `python -m pytest tests/test_filename.py`

## Build the Project

```bash
# Backend builds are not needed (Python)
# Frontend build:
cd app/frontend
npm run build
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

### Production Mode

```bash
# To be added when production setup is ready
```

## Validate Requirement

Run validation checks for a specific requirement. The validation script reads acceptance criteria from the spec file and executes any commands specified.

```bash
# Validate a specific requirement
py -3 scripts/validate-requirement.py S-0002

# If py is not available, set python.executable in felix/config.json or use python directly

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

When the agent exits with code 2 or 3, the requirement is automatically marked as "blocked" in `felix/requirements.json`. To unblock:

1. Fix the underlying issues (tests, validation criteria, or code)
2. Manually edit `felix/requirements.json` and change status from `"blocked"` to `"planned"`
3. Restart the agent - it will pick up the unblocked requirement

### Validation Criteria Format

Specs should include testable validation criteria with commands and expected outcomes. The script looks for "## Validation Criteria" first, then falls back to "## Acceptance Criteria":

```markdown
## Validation Criteria

- [ ] Backend starts: `python app/backend/main.py` (exit code 0)
- [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Tests pass: `cd app/backend && pytest` (exit code 0)
```

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here

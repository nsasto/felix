# Implementation Plan

This is the **current plan**, not the historical record.

## Architecture Decisions (Complete)

✅ **Tech Stack Finalized:**

- Agent: Python 3.11+ (standalone script)
- Backend: FastAPI + Uvicorn + WebSocket
- Frontend: React 19 + TypeScript + Vite (existing)
- Communication: Filesystem only (no IPC)
- LLM: Direct API calls (Anthropic Claude)

✅ **Repository structure established**
✅ **Documentation complete** (README, HOW_TO_USE, RALPH_EXPLAINED, AGENTS)
✅ **Frontend scaffolding exists** (needs refactoring)

---

## Phase 1: Backend Foundation

### 1.1 Python Backend Setup

- [x] Create `app/backend/` Python project structure
- [x] Add `pyproject.toml` or `requirements.txt` with dependencies (fastapi, uvicorn, websockets, anthropic, aiofiles, watchfiles, pydantic)
- [x] Create basic FastAPI app with health check endpoint
- [x] Add CORS for frontend (port 3000)
- [x] Update AGENTS.md with backend run commands

### 1.2 Project Management API

- [x] `POST /api/projects/register` - Register project directory
- [x] `GET /api/projects` - List registered projects
- [x] `GET /api/projects/:id` - Get project details
- [x] `DELETE /api/projects/:id` - Unregister project
- [x] Store projects in `~/.felix/projects.json`

### 1.3 File Operations API

- [ ] `GET /api/projects/:id/specs` - List spec files
- [ ] `GET /api/projects/:id/specs/:filename` - Read spec
- [ ] `PUT /api/projects/:id/specs/:filename` - Update spec
- [ ] `GET /api/projects/:id/plan` - Read IMPLEMENTATION_PLAN.md
- [ ] `PUT /api/projects/:id/plan` - Update plan
- [ ] `GET /api/projects/:id/requirements` - Read requirements.json
- [ ] Add path validation against allowlist/denylist

---

## Phase 2: Agent Core

### 2.1 Agent Script

- [ ] Create `app/backend/agent.py` - Main agent entry point
- [ ] Implement `RalphExecutor` class with basic loop
- [ ] Add CLI argument parsing (project path)
- [ ] Load artifacts (specs, plan, AGENTS.md, requirements.json)
- [ ] Write minimal state updates to felix/state.json

### 2.2 Mode Logic

- [ ] Implement mode determination (planning vs building)
- [ ] Read auto_transition from felix/config.json
- [ ] Implement mode switching logic

### 2.3 LLM Integration

- [ ] Add Anthropic API client initialization
- [ ] Load prompt templates from felix/prompts/
- [ ] Implement context gathering (specs + plan + AGENTS)
- [ ] Make test LLM call to verify connectivity

### 2.4 Planning Mode Implementation

- [ ] Read all specs from specs/
- [ ] Generate IMPLEMENTATION_PLAN.md via LLM
- [ ] Update felix/requirements.json status
- [ ] No code changes (enforce rule)

### 2.5 Building Mode Implementation

- [ ] Parse IMPLEMENTATION_PLAN.md for next task
- [ ] Investigate existing code (search codebase)
- [ ] Execute code changes via LLM
- [ ] Mark task complete in plan

---

## Phase 3: Backpressure & Validation

### 3.1 Test Execution

- [ ] Parse test commands from AGENTS.md
- [ ] Run tests as subprocess
- [ ] Capture stdout/stderr
- [ ] Retry on failure (max N attempts)
- [ ] Mark task blocked if tests fail

### 3.2 Run Artifacts

- [ ] Create runs/<run-id>/ directory
- [ ] Write requirement_id.txt, plan.snapshot.md
- [ ] Log commands to commands.log.jsonl
- [ ] Generate diff.patch and report.md

### 3.3 Git Integration

- [ ] Implement git commit after successful task
- [ ] Generate meaningful commit messages

---

## Phase 4: Backend Orchestration

### 4.1 Agent Spawning

- [ ] `POST /api/projects/:id/runs/start` - Spawn agent process
- [ ] Store agent PID, track status
- [ ] `POST /api/projects/:id/runs/stop` - Kill agent process

### 4.2 File Watching

- [ ] Watch felix/state.json, requirements.json, runs/
- [ ] Broadcast changes via WebSocket to clients

### 4.3 WebSocket Server

- [ ] Create WebSocket endpoint `/ws`
- [ ] Stream run logs in real-time
- [ ] Send agent status updates

---

## Phase 5: Frontend Refactoring

### 5.1 Project Management UI

- [ ] Create project selector/switcher component
- [ ] Add "Register Project" flow
- [ ] Display project list with status

### 5.2 Specs Editor

- [ ] Rewire existing markdown editor to specs/\*.md
- [ ] Add file tree navigation
- [ ] Keep split/edit/preview modes

### 5.3 Kanban for IMPLEMENTATION_PLAN.md

- [ ] Parse plan into task objects
- [ ] Display in existing Kanban
- [ ] Sync status with requirements.json

### 5.4 AI Quality Checker

- [ ] Repurpose Gemini chat for spec linting
- [ ] Check "one sentence without and" rule
- [ ] Validate AGENTS.md stays operational-only

### 5.5 Run Monitoring

- [ ] Create runs history viewer
- [ ] Show active run with real-time output

### 5.6 Executor Controls

- [ ] Add "Start Run" / "Stop Run" buttons
- [ ] Show current mode from state.json

---

## Next Immediate Steps

**Priority 1: Backend Setup**

1. Create Python backend structure
2. Add dependencies
3. Implement basic FastAPI app with health check
4. Test backend starts successfully

**Priority 2: Agent Skeleton**

1. Create agent.py with basic loop
2. Test it loads artifacts from a project directory
3. Make test LLM API call
4. Verify it writes to felix/state.json

**Priority 3: Prove the Core**

1. Implement minimal planning mode (generate plan via LLM)
2. Implement minimal building mode (execute one task)
3. Test on simple example project
4. Verify backpressure works (run tests)

---

_Note: This plan is snapshotted into each run at `runs/<run-id>/plan.snapshot.md` for audit trail._

# S-0002: Felix Backend API Server

## Narrative

As a developer, I need a FastAPI backend that spawns and monitors Felix agents, provides HTTP/WebSocket APIs for project management and file operations, and enables the frontend UI to observe agent execution via filesystem watching.

## Acceptance Criteria

### Server Foundation

- [ ] FastAPI app in `app/backend/main.py` with CORS for frontend (port 3000)
- [ ] Runs on port 8080 via uvicorn
- [ ] Health check endpoint: `GET /health`
- [ ] Lifespan events for startup/shutdown
- [ ] Dependencies installed from requirements.txt (fastapi, uvicorn, websockets, aiofiles, watchfiles, pydantic)

### Project Management API

- [ ] `POST /api/projects/register` - Register project directory, validate Felix structure
- [ ] `GET /api/projects` - List registered projects with metadata
- [ ] `GET /api/projects/:id` - Get project details (specs count, current state, last run)
- [ ] `DELETE /api/projects/:id` - Unregister project
- [ ] Store projects in `~/.felix/projects.json` (user-level registry)

### File Operations API

- [ ] `GET /api/projects/:id/specs` - List spec files with IDs and titles
- [ ] `GET /api/projects/:id/specs/:filename` - Read spec content
- [ ] `PUT /api/projects/:id/specs/:filename` - Update spec content
- [ ] `POST /api/projects/:id/specs` - Create new spec
- [ ] `GET /api/projects/:id/requirements` - Read felix/requirements.json
- [ ] `PUT /api/projects/:id/requirements` - Update requirements
- [ ] `GET /api/projects/:id/agents-md` - Read AGENTS.md
- [ ] `GET /api/projects/:id/runs/:runId/plan` - Read per-requirement plan from runs/<run-id>/plan-<req-id>.md
- [ ] Path validation against felix/policies/allowlist.json and denylist.json

### Agent Spawning & Monitoring

- [x] `POST /api/projects/:id/runs/start` - Spawn PowerShell agent process (felix-agent.ps1) for project
- [x] `POST /api/projects/:id/runs/stop` - Terminate running agent
- [ ] `GET /api/projects/:id/runs` - List run history
- [ ] `GET /api/projects/:id/runs/:runId` - Get run details and artifacts
- [x] Track agent PIDs, start times, exit codes
- [x] Store run metadata in backend memory (ephemeral, not persisted)

### Real-time State Updates

- [ ] WebSocket endpoint: `/ws/projects/:id` for real-time updates
- [ ] Watch felix/state.json with watchfiles library
- [ ] Watch runs/ directory for new run artifacts
- [ ] Broadcast state changes to connected WebSocket clients
- [ ] Send events: iteration_start, iteration_complete, mode_change, status_update, run_complete

### Error Handling

- [ ] 404 for unregistered projects
- [ ] 400 for invalid file paths or policy violations
- [ ] 409 for conflicting operations (agent already running)
- [ ] 500 for subprocess spawn failures
- [ ] Structured error responses with error codes

## Technical Notes

**Architecture:** Backend is optional orchestration layer. Agents can run standalone via CLI. Backend's job is spawning processes, watching filesystem, and exposing state to UI.

**Communication model:** Backend never communicates directly with agent processes. All coordination via filesystem:

- Backend writes felix/config.json
- Agent writes felix/state.json and runs/
- Backend watches those files with file watchers
- Backend broadcasts to frontend via WebSocket

**Process management:** Use Python subprocess.Popen() to spawn agents. Track PIDs. Clean up on server shutdown. Agents run detached—backend doesn't block waiting for completion.

**Security:** Validate all file paths against policies. Never allow arbitrary filesystem access. Allowlist overrides denylist.

## Validation Criteria

- [ ] Backend starts: `cd app/backend && python main.py` (exit code 0 within 5 seconds, then Ctrl+C)
- [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Dependencies installed: `cd app/backend && python -c "import fastapi, uvicorn, websockets, aiofiles, watchfiles, pydantic"` (exit code 0)
- [ ] CORS configured for frontend: `curl -I -X OPTIONS http://localhost:8080/health -H "Origin: http://localhost:3000"` (includes Access-Control-Allow-Origin)

## Dependencies

- S-0001 (agent must exist to spawn)

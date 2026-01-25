# Context

This file documents product and system context for Felix.

## Tech Stack

### Agent

- **Language:** PowerShell
- **Runtime:** Windows PowerShell / PowerShell Core (pwsh)
- **LLM Integration:** droid exec (Factory tool)
- **Authentication:** FACTORY_API_KEY environment variable
- **Location:** `felix-agent.ps1` at project root

### Backend

- **Language:** Python 3.11+
- **Framework:** FastAPI + Uvicorn (ASGI)
- **Port:** 8080
- **Dependencies:** fastapi, uvicorn, websockets, aiofiles, watchfiles, pydantic
- **Location:** `app/backend/`
- **Process Management:** subprocess.Popen for spawning detached agents

### Frontend

- **Language:** TypeScript
- **Framework:** React 19 + Vite
- **Port:** 3000 (development)
- **Location:** `app/frontend/`
- **State Management:** REST API + WebSocket for real-time updates

### Communication Architecture

- **Agent ↔ Filesystem:** Direct read/write of project files
- **Backend ↔ Agent:** Filesystem watching only (no IPC, sockets, or shared memory)
- **Backend ↔ Frontend:** REST API + WebSocket for real-time updates
- **LLM Integration:** Agent shells out to droid exec which calls Factory API

## Design Standards

- Keep the outer mechanism dumb
- File-based memory and state
- Deterministic, reproducible iterations

## UX Rules

- Minimal UI - operator console, not the brain
- State visible through file system
- Clear separation between planning and building

## Architectural Invariants

- Planning mode cannot commit code
- Building mode requires a plan
- One iteration equals one task outcome
- Backpressure is non-negotiable

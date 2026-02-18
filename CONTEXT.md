# Context

Felix is a plan-driven executor for autonomous software delivery. It transforms the Ralph concept from "a loop you run" into an operable system with durable state, explicit modes (planning/building), and enforced separation between planning and execution. The system orchestrates AI agents through filesystem-based artifacts while providing a web UI for monitoring and control.

## Tech Stack

### Agent (CLI)

- **Language:** PowerShell
- **Runtime:** Windows PowerShell 5.1+ / PowerShell Core 7+ (pwsh)
- **LLM Integration:** `droid exec` (Factory CLI tool)
- **Authentication:** `FACTORY_API_KEY` environment variable
- **Entry Point:** `.felix/felix.ps1` (dispatcher)
- **Core Scripts:** `.felix/felix-agent.ps1`, `.felix/felix-loop.ps1`, `.felix/felix-cli.ps1`
- **Location:** `.felix/` directory

### Backend (API Server)

- **Language:** Python 3.11+
- **Framework:** FastAPI 0.115.0 + Uvicorn 0.32.0 (ASGI)
- **Port:** 8080
- **Database:** PostgreSQL (asyncpg 0.29+, SQLAlchemy 2.0+, databases 0.8+)
- **Key Dependencies:**
  - `fastapi`, `uvicorn[standard]` - Web framework and server
  - `websockets` - Real-time communication
  - `aiofiles`, `watchfiles` - Async file operations
  - `pydantic`, `pydantic-settings` - Data validation
  - `anthropic`, `openai` - LLM client libraries (Copilot)
  - `httpx` - Async HTTP client
  - `python-dotenv` - Environment management
  - `supabase` - Cloud storage client (optional)
- **Location:** `app/backend/`
- **API Docs:** http://localhost:8080/docs (Swagger UI)

### Frontend (Web UI)

- **Language:** TypeScript 5.8+
- **Framework:** React 19.2 + Vite 6.2
- **Port:** 3000 (development)
- **Testing:** Vitest 4.0 + @testing-library/react 16.3 + happy-dom
- **Key Dependencies:**
  - `react`, `react-dom` - UI framework
  - `marked` - Markdown rendering
  - `ansi-to-react` - ANSI terminal output display
  - `react-resizable-panels` - Resizable panel layouts
  - `@google/genai` - Gemini API client
- **Build Tool:** Vite with React plugin
- **Location:** `app/frontend/`

### Tray Manager (Windows System Tray)

- **Language:** C# 8+
- **Framework:** .NET 8.0 + WPF (Windows Presentation Foundation)
- **UI Toolkit:** WPF-UI 3.0.5 (Fluent Design)
- **Key Dependencies:**
  - `CommunityToolkit.Mvvm` - MVVM framework
  - `MdXaml` - Markdown rendering in WPF
  - `System.Drawing.Common` - Graphics utilities
- **Location:** `app/tray-manager/`

### CLI Tool (Future/Optional)

- **Language:** C# 12
- **Framework:** .NET 10.0
- **Key Dependencies:**
  - `Spectre.Console` - Rich console output
  - `System.CommandLine` - Command-line parsing
- **Location:** `src/Felix.Cli/`

### Communication Architecture

- **Agent ↔ Filesystem:** Direct read/write of project files (specs, plans, state JSON)
- **Agent → Backend:** Optional outbox-based sync (JSONL queue)
- **Backend ↔ Agent:** No direct communication; backend watches filesystem for changes
- **Backend ↔ Database:** Async PostgreSQL via `databases` + `asyncpg`
- **Backend ↔ Storage:** Artifact upload via abstraction layer (filesystem or Supabase)
- **Backend ↔ Frontend:** REST API + SSE for real-time updates
- **Frontend ↔ LLM (Copilot):** Via backend proxy endpoints or direct client (Gemini)
- **Agent ↔ LLM:** Agent shells out to `droid exec` which calls Factory API

## Design Standards

- **Keep the outer mechanism dumb:** Agent orchestration is simple; complexity lives in prompts
- **File-based memory and state:** All state persisted as JSON/Markdown files in `.felix/` and `runs/`
- **Deterministic, reproducible iterations:** Each agent run is self-contained with traceable artifacts
- **Separation of concerns:** Agent (PowerShell) → Backend (Python) → Frontend (React) are independent
- **Atomic task outcomes:** One iteration = one task outcome (success, failure, or blocked)
- **Error handling:** Use structured try/catch in PowerShell; Python exceptions with FastAPI error handlers
- **Naming conventions:**
  - PowerShell: kebab-case files (`felix-agent.ps1`), PascalCase functions
  - Python: snake_case files and functions, PascalCase classes
  - TypeScript: PascalCase components, camelCase functions/variables
  - Specs: `S-NNNN-descriptive-name.md` format

## UX Rules

- **Minimal UI:** Operator console, not the brain; the agent does the thinking
- **State visible through filesystem:** Users can inspect `.felix/state.json`, `runs/`, and spec files
- **Clear separation:** Planning mode (generates plans) vs Building mode (writes code)
- **Real-time feedback:** WebSocket streaming for agent console output
- **Accessible defaults:** Light/dark themes, keyboard navigation

## Architectural Invariants

- **Planning mode cannot commit code:** Enforced by agent guardrails
- **Building mode requires a plan:** Agent fails without a plan file present
- **One iteration equals one task outcome:** Atomic units of work
- **Backpressure is non-negotiable:** Tests must pass before marking complete (configurable in `.felix/config.json`)
- **Spec files are test suites (persistent):** `specs/*.md` define what to build and how to validate
- **Plan files are to-do lists (ephemeral):** `runs/*/plan-*.md` are checked off and archived
- **Agent registry is authoritative:** `.felix/agents.json` defines available agents; `config.json` references by ID

## Testing Standards

- **Backend:**
  - Framework: pytest 8.3+ with pytest-asyncio
  - Location: `app/backend/tests/test_*.py`
  - Run: `powershell -File .\scripts\test-backend.ps1`
  - Coverage: pytest-cov enabled
  - Configuration: `app/backend/pytest.ini`
  - **Mocking Infrastructure:**
    - Unit tests must NEVER require real database connections
    - Mock database lifecycle: `patch("main.db_startup")` and `patch("main.db_shutdown")`
    - Example: See **app/backend/tests/test_sync_endpoints.py** (FakeDatabase pattern)
    - Pattern: Use `unittest.mock.patch` in test fixtures for all external dependencies
- **Frontend:**
  - Framework: Vitest 4.0 with @testing-library/react
  - Location: `app/frontend/src/__tests__/*.test.tsx`
  - Run: `powershell -File .\scripts\test-frontend.ps1`
  - Setup: `app/frontend/src/__tests__/setup.ts`
  - Environment: happy-dom
  - Pool: threads (required for Windows, prevents fork timeout issues)
  - Configuration: `app/frontend/vite.config.ts`
- **Agent (PowerShell):**
  - Location: `.felix/tests/`
  - Harness: `.felix/plugins/test-harness.ps1`
- **Requirements:**
  - All new features require tests
  - Minimum coverage: Happy path + one error case
  - Tests must pass before marking requirements complete
  - Validation: `py -3 scripts/validate-requirement.py S-NNNN`

## File Organization

- `.felix/` - Felix agent runtime configuration and scripts
  - `felix.ps1` - CLI dispatcher (entry point)
  - `felix-agent.ps1` - Core agent executor
  - `felix-loop.ps1` - Continuous execution loop
  - `config.json` - Runtime configuration (includes sync settings)
  - `agents.json` - Agent registry (ID, executable, adapter)
  - `requirements.json` - Requirements status tracking
  - `state.json` - Current execution state
  - `outbox/` - Sync queue for server uploads (\*.jsonl)
  - `core/` - Core PowerShell modules & interfaces
    - `sync-interface.ps1` - Abstract sync reporter interface
  - `plugins/` - Plugin system (metrics, slack, sync, prompt-enhancer)
    - `sync-http.ps1` - HTTP sync implementation
  - `policies/` - Allowlist/denylist for agent operations
  - `prompts/` - LLM prompt templates (planning.md, building.md, etc.)
  - `tests/` - Agent test files
- `app/backend/` - FastAPI backend server
  - `main.py` - Application entry point
  - `routers/` - API route handlers (agents, runs, settings, copilot, etc.)
  - `database/` - Database connection and writers
  - `migrations/` - SQL schema migrations
  - `services/` - Business logic services
  - `websocket/` - WebSocket handlers
  - `tests/` - pytest test files
- `app/frontend/` - React web UI
  - `App.tsx` - Main application component
  - `index.tsx` - React entry point
  - `components/` - React components (AgentDashboard, SettingsScreen, etc.)
  - `hooks/` - Custom React hooks
  - `services/` - API client services
  - `src/api/` - API integration
  - `src/__tests__/` - Vitest test files
- `app/tray-manager/` - Windows system tray application
  - `App.xaml` / `App.xaml.cs` - WPF application
  - `Views/` - XAML views
  - `ViewModels/` - MVVM view models
  - `Services/` - Application services
- `specs/` - Requirement specifications (S-NNNN-\*.md)
- `runs/` - Execution run artifacts (timestamped directories)
- `scripts/` - Development and utility scripts
  - `test-backend.ps1`, `test-frontend.ps1` - Test runners
  - `validate-requirement.ps1/py` - Requirement validation
  - `setup-db.ps1` - Database setup
  - `install-cli.ps1` - CLI installation
- `tuts/` - Tutorial and explanation documents
- `learnings/` - Historical learnings and anti-patterns
- `src/` - Additional source code (Felix.Cli)

## Database Schema

PostgreSQL database with 11 core tables:

- `schema_migrations` - Migration version tracking
- `organizations` - Multi-tenant organization records
- `organization_members` - User membership with roles (owner/admin/member)
- `projects` - Projects within organizations
- `requirements` - Requirement tracking (planned/in-progress/completed/blocked)
- `agents` - Agent registration and status
- `agent_states` - Key-value state storage for agents
- `runs` - Execution run records (pending/running/completed/failed/cancelled)
- `run_artifacts` - Artifacts produced by runs (deprecated)
- `run_files` - Run artifact storage tracking with SHA256
- `run_events` - Event timeline for runs (real-time streaming)

Setup: `.\scripts\setup-db.ps1`

## Key Dependencies

### External Services

- **Factory API:** LLM execution via `droid exec` command
- **PostgreSQL:** Primary data store for backend (local or remote)
- **Node.js/npm:** Frontend build and development
- **Python 3.11+:** Backend runtime

## Sync Configuration (Optional)

Agent-to-server artifact mirroring via outbox pattern:

- **Outbox Queue:** `.felix/outbox/*.jsonl` with automatic retry
- **Plugin System:** Pluggable sync providers (http, custom)
- **Idempotent:** SHA256 manifest ensures unchanged files skip upload
- **Batch Upload:** All run artifacts in single HTTP request (~90% fewer requests)
- **Automatic Compression:** gzip via HTTP Accept-Encoding header
- **Storage Abstraction:** FilesystemStorage (local) or SupabaseStorage (cloud)

Environment Variables:

- `FELIX_SYNC_ENABLED` - Enable sync (true/false)
- `FELIX_SYNC_URL` - Backend base URL (e.g., http://localhost:8080)
- `FELIX_SYNC_KEY` - Optional API key for authentication

See: **Enhancements/runs_migration.md** for implementation details.

### Environment Variables

- `FACTORY_API_KEY` - Authentication for Factory/droid CLI
- `DATABASE_URL` - PostgreSQL connection string (backend)
- `FELIX_COPILOT_API_KEY` - Optional: API key for Copilot features
- `GEMINI_API_KEY` - Optional: Google Gemini API for frontend Copilot

### Configuration Files

- `.felix/config.json` - Agent runtime configuration
- `.felix/agents.json` - Agent definitions registry
- `app/backend/.env` - Backend environment variables
- `app/frontend/.env` - Frontend environment variables (Vite)

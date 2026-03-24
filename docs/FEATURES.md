# Felix Features

**Transform Your Development Workflow with Intelligent Autonomous Agent Swarms**

Felix is a production-ready system for autonomous software delivery at scale, turning AI-powered development from concept into operable reality. Built on plan-driven execution with enforced validation and distributed orchestration capabilities, Felix provides the scaffolding, validation, and tooling needed to deploy autonomous agent swarms reliably across your entire team's infrastructure.

---

## 🎯 Core Capabilities

### Plan-Driven Execution

- **Explicit Phases**: Separate planning and building modes with enforced boundaries
- **Self-Reviewing Plans**: Agents generate and critique their own plans before execution
- **Task Atomicity**: One task per iteration with clear completion signals
- **State Persistence**: All progress saved to disk for reproducible iterations
- **Autonomous Loops**: Runs to completion without human intervention

### Backpressure Validation

- **Test-Gated Progress**: No advancement without passing tests
- **Build Validation**: Ensures code compiles before marking tasks complete
- **Lint Enforcement**: Code quality checks integrated into workflow
- **Configurable Gates**: Customize validation requirements per project
- **Non-Negotiable Quality**: Failures halt progress until resolved

### Artifact-Based Architecture

- **Durable State**: Specs, plans, and status persist as files, not chat history
- **Version Controlled**: All artifacts are git-trackable
- **Human Readable**: Markdown-based specs and plans
- **Audit Trail**: Complete history of decisions and changes
- **Framework Agnostic**: Works with any project structure

### Distributed Orchestration

- **Multi-Machine Swarms**: Deploy agents across team workstations, VMs, or cloud instances
- **Team Coordination**: Central dashboard controls agents on any registered machine
- **Cloud/Local Modes**: Full cloud orchestration or completely local operation
- **Tray-Mediated Security**: All remote control flows through authenticated tray applications
- **Scale on Demand**: Utilize spare capacity across your infrastructure

### Plugin System

- **Lifecycle Hooks**: 11 hooks covering the full iteration cycle (pre-iteration through post-validation)
- **PowerShell Scripts**: Plugins are simple `.ps1` scripts — no compilation needed
- **Manifest-Driven**: JSON manifests declare hooks, permissions, and config
- **State Management**: Persistent and transient state helpers built in
- **Circuit Breaker**: Auto-disables failing plugins after configurable threshold
- **Priority Ordering**: Control execution order across plugins (0–999)
- **Permission Model**: Declare required access (`read:specs`, `network:http`, `git:write`, etc.)
- **Reference Implementation**: Built-in sync-http plugin demonstrates production patterns

See **[Writing Plugins](PLUGINS.md)** for the full authoring guide.

---

## 💻 Command Line Interface (CLI)

### Execution Commands

**`felix run <req-id>`**

- Execute a single requirement to completion
- Automatic mode selection (planning or building)
- Real-time console output with ANSI formatting
- JSON/rich/plain output formats
- Statistics summary on completion

**`felix loop`**

- Continuous execution mode - processes all planned requirements
- Configurable max iterations (`--max-iterations`)
- Automatic requirement selection based on status and dependencies
- Stops on validation failures or max iterations reached
- Perfect for overnight autonomous development

**`felix procs`**

- List all active agent execution sessions
- View session details: requirement, agent, PID, duration
- Kill running sessions by session ID
- Process monitoring and management
- Prevents duplicate executions

### Installation and Update Commands

**`felix install`**

- Bootstraps Felix onto a machine from the published installer or install scripts
- Sets up the global command entrypoint and install directory
- Intended for first-time machine setup

**`felix update`**

- Checks GitHub Releases for the latest Felix version
- Selects the correct package for Windows, Linux, or macOS
- Verifies checksums before staging replacement files
- Prompts interactively by default, with `--yes` for unattended upgrades
- Supports update checks without install via `--check`

### Requirements Management

**`felix status [req-id]`**

- View requirement status (draft/planned/in-progress/complete/blocked/done)
- Show dependencies and their completion status
- Display priority and timestamps
- JSON, rich, or plain text output
- Filter by specific requirement or view all

**`felix list`**

- List all requirements with advanced filtering
- Filter by: status, priority, tags, incomplete dependencies
- Show dependency tree (`--tree`)
- Rich formatting with color-coded status
- Export as JSON for programmatic access

**`felix deps [req-id]`**

- Analyze requirement dependencies
- Check if dependencies are satisfied (`--check`)
- View dependency tree visualization
- Find all requirements with incomplete dependencies (`--incomplete`)
- Validate execution readiness

**`felix validate <req-id>`**

- Run requirement-level acceptance verification against spec criteria
- Execute tests specified in requirement spec
- Check command exit codes
- Verify expected outcomes
- Detailed pass/fail reporting
- Optional machine-readable output with `--json`

### Specification Management

**`felix spec create "<description>"`**

- Interactive spec creation with LLM assistance
- Auto-generated requirement IDs (S-NNNN)
- Guided questions for context gathering
- Quick mode (`--quick`) for minimal questions
- Automatic addition to requirements.json

**`felix spec fix`**

- Scan specs folder and sync with requirements.json
- Detect orphaned entries
- Find missing specs
- Rename duplicate IDs (`--fix-duplicates`)
- Fix title mismatches and broken references

**`felix spec delete <req-id>`**

- Remove spec file and requirements.json entry
- Confirmation prompts for safety
- Cascade dependency checks
- Maintains referential integrity

### Context Documentation

**`felix context build`**

- Autonomous project analysis and documentation
- Generates comprehensive CONTEXT.md
- Tech stack detection from manifests
- Architecture discovery
- Design standards extraction
- File organization mapping
- Timestamped backups before updates
- Hidden file exclusion (`--include-hidden` to override)

**`felix context show`**

- Display current CONTEXT.md content
- Quick reference in terminal
- No modification - read-only view

### Agent Management

**`felix agent list`**

- View all configured agents
- Show current agent with marker
- Display adapter types and executables
- Agent metadata and models

**`felix agent current`**

- Display currently active agent
- Configuration details
- Adapter and execution settings

**`felix agent setup`**

- Interactive agent and model selection
- Writes selected agents to `.felix/agents.json`

**`felix agent use [id|name]`**

- Switch between configured agents
- Support multiple LLM providers (Droid, Claude, Codex, Gemini, Copilot)
- Update config.json atomically
- Recompute deterministic agent keys when `--model` changes the active profile identity
- Immediate effect on next execution

**`felix agent register`**

- Register the current configured agent with the sync backend
- Show sync target details before attempting registration
- Safe to re-run and safe in non-interactive shells

**`felix procs kill <session-id|all>`**

- Stop tracked Felix agent sessions from the CLI
- Clean stale `.felix/sessions.json` entries automatically
- Remove session records after termination

**`felix spec pull` / `felix spec push`**

- Sync local specs with the backend server
- Support dry-run, force, and delete semantics for pull
- Chunk uploads and retry failed push batches

### Terminal UI

**`felix tui`**

- Interactive slash-command shell with startup project/status card
- Scrollback-preserving command output in the terminal
- Bottom composer with command and argument suggestions
- Longer-running commands can temporarily take over the terminal and return to the shell after completion
- Built with .NET Spectre.Console
- Rich formatting and colors

---

## 🌐 Web Application

### Multi-Project Management

**Project Selector**

- View all registered projects across organization
- Tenant-based project isolation
- Project path display for quick identification
- Automatic project discovery
- Remember last selected project
- Switch between projects seamlessly
- Project metadata and status

### Agent Dashboard

**Agent Registry**

- View all registered agents across all machines
- Agent status monitoring (active/stale/inactive/stopped)
- Heartbeat tracking with timeout detection
- Machine metadata (hostname, platform, IP)
- Agent configuration per entry
- Quick start/stop/restart controls from dashboard
- Filter and search agents across infrastructure

**Run Management**

- View run history with status badges
- Active vs completed run separation
- Run artifacts viewer (plans, logs, commits)
- Stop running agents with confirmation
- Run duration tracking
- Requirement linkage
- Cross-machine run orchestration

**Workflow Visualization**

- Visual state machine diagram
- Mode transitions (planning/building/validating)
- Current state highlighting
- Progress indicators
- Interactive tooltips

### Requirements Kanban Board

**Drag-and-Drop Management**

- Six-column board: Draft → Planned → In Progress → Complete → Blocked → Done
- Drag requirements between stages
- Visual status transitions
- Real-time updates across all connected users

**Advanced Filtering**

- Filter by status, priority, tags
- Show/hide requirements with incomplete dependencies
- Search by ID or title
- Collapsible columns for focus
- Filter badge indicators

**Dependency Visualization**

- Dependency warnings in cards
- Incomplete dependency tooltips
- Blocked status for unmet dependencies
- Dependency chain visualization

**Requirement Details**

- Slide-out panel for detailed view
- Full spec content with markdown rendering
- Edit specs inline
- Priority and label management
- Dependency editor
- Status transitions

### Live Console Output

**Real-Time Streaming**

- WebSocket-powered console output from any agent
- ANSI color code rendering
- Auto-scroll with user override
- Multiple console tabs for concurrent agents
- Command history
- Clear console functionality
- View output from agents on any machine

### Specs Editor

**Markdown Editing**

- Full-featured markdown editor
- Syntax highlighting
- Live preview with marked.js
- Auto-save on changes
- File browser for multi-spec editing
- Concurrent edit warnings

**Spec Operations**

- Create new specs from editor
- Edit existing specs
- Delete with confirmation
- Spec format validation
- Requirement ID generation

### Copilot AI Assistant

**Chat Interface**

- Context-aware AI conversations
- Project-specific chat history (localStorage)
- Multiple AI provider support (Backend proxy or direct Gemini)
- Streaming responses with word-by-word animation
- Avatar state changes (idle/thinking/speaking)

**Smart Features**

- Automatic spec generation from conversation
- "Insert Spec" button for LLM-generated content
- Spec format detection
- Requirements Q&A
- Architecture guidance
- Code suggestions

**Chat Management**

- Persistent per-project history (50 message limit)
- Clear chat history
- Chat panel toggle
- Bubble-style message display
- Timestamp tracking

### Configuration Panel

**Agent Settings**

- Select and configure active agent
- Set max iterations
- Agent adapter selection
- Working directory configuration
- Environment variables

**Project Settings**

- Project path configuration
- Requirement file location
- Backpressure settings (enable/disable tests)
- Custom validation rules
- Polling intervals
- Multi-tenant organization settings

### Settings Screen

**API Configuration**

- Backend URL configuration with validation
- API key management for Copilot features
- Secure key storage (localStorage)
- Connection testing
- Cloud authentication setup

**UI Preferences**

- Theme selection (light/dark) with system default
- Realtime persistence
- Immediate theme switching

**Refresh Controls**

- Force refresh agents
- Force refresh requirements
- Clear cached data
- Reconnect WebSocket

---

## 🖥️ Windows Tray Manager

### System Integration

**System Tray Application**

- Persistent Windows system tray icon on each machine
- Context menu for quick actions
- Notification support
- Auto-start capability
- Minimize to tray
- Per-machine agent hosting

**Modern UI**

- .NET 8 WPF with Fluent Design
- Mica/Acrylic backdrop effects
- Rounded corners and custom chrome
- Dark theme by default
- High-DPI aware rendering

### Agent Registration & Modes

**Cloud Mode**

- Authenticate tray to tenant (Supabase/custom)
- Register agent to central dashboard
- Agent appears in web UI immediately
- Receive remote control commands via WebSocket
- Heartbeat monitoring every ~10 seconds
- Machine metadata automatically captured

**Local Mode**

- Connect to localhost backend only
- No cloud authentication required
- Same tray UX, fully local operation
- Perfect for development and testing
- No external dependencies

**Registration Flow**

- Agent only exists when tray registers it
- No "default" or hidden agents
- Registration persists server-side per tenant
- Metadata: agent ID, machine name, last connected, availability status
- Agent remains visible even when offline (historical record)

### Remote Control

**WebSocket Command Channel**

- Persistent WebSocket connection per tray instance
- Server → agent START/STOP commands
- Instant execution on remote machine
- Run parameters passed through WebSocket payload
- Optional real-time log streaming back to dashboard

**Availability Tracking**

- Heartbeats originate from tray (push, not poll)
- Automatic offline detection on heartbeat timeout
- Last-seen timestamps displayed in dashboard
- Reconnection handling with state recovery

### Agent Management

**Visual Dashboard**

- DataGrid view of all agents on this machine
- Columns: Name, Status, Last Run, Last Feature, Operations
- Status indicators with icons (Idle/Busy/Error)
- Real-time status updates
- Search and filter capabilities

**Agent Operations**

- Add new agents with wizard
- Configure agent settings per entry
- Toggle agent active/inactive status
- Delete agents with confirmation
- Quick start/stop per agent
- View agent logs

### Navigation & Views

**Multi-Panel Interface**

- Left navigation: Agents, Logs, Settings
- Agents panel: Management dashboard
- Logs panel: Real-time log viewer
- Settings panel: Configuration options

**Settings Management**

- Backend connection configuration
- Project path settings
- Cloud/Local mode toggle
- Tray behavior options
- Startup preferences
- Notification settings
- Authentication credentials

---

## 🌍 Distributed Orchestration

Felix's distributed orchestration capabilities transform autonomous development from a single-machine experiment into an enterprise-scale infrastructure. Deploy agent swarms across your team's workstations, VMs, or cloud instances, all controlled from a single dashboard.

### Multi-Machine Agent Swarms

**Team Workstation Utilization**

- Install tray on each developer's machine
- Register agents to your organization's tenant
- Central dashboard shows all agents across all machines
- Utilize spare CPU/memory during off-hours or idle time
- Each machine contributes to the agent pool

**VM and Cloud Instance Support**

- Deploy agents on virtual machines (VMware, Hyper-V, VirtualBox)
- Cloud VM support (Azure VMs, AWS EC2, GCP Compute Engine)
- VDI environments fully supported
- Architecture-agnostic: Windows, Linux, macOS (tray on Windows, CLI on all)
- Spin up VMs on demand, register agents, distribute work

**Dynamic Agent Pools**

- Agents join/leave pool automatically based on availability
- Dashboard shows real-time availability across all machines
- Automatic failover if agent disconnects
- Scale horizontally by adding more machines
- No central bottleneck - agents execute locally

### Cloud Mode Architecture

**Tray as Trust Boundary**

- All remote control flows through authenticated tray application
- No direct backend-to-filesystem communication
- Tray mediates all commands and ensures security
- Each tray instance represents one agent on one machine
- Authentication required before agent appears in dashboard

**WebSocket Control Channel**

- One WebSocket connection per tray instance
- Connection handshake includes agent_id, tenant, session metadata
- Server sends START/STOP commands through WebSocket
- Tray spawns local executor (PowerShell/CLI) when START received
- Executor emits events back through tray to API
- Real-time log streaming from executor to dashboard

**Multi-Tenant Security**

- Organizations with multiple projects
- Agent scoping per organization
- Role-based access control (future)
- Tenant isolation at database level
- Each agent bound to one organization

**Heartbeat Monitoring**

- Tray sends heartbeat every ~10 seconds (configurable)
- Backend updates last_seen_at and availability status
- No polling from server - push-based model
- Immediate offline detection when heartbeats stop
- Dashboard shows last-seen timestamps for offline agents
- Historical records preserved even after disconnect

### Local Mode (Development)

**Zero Cloud Dependencies**

- Run entire stack locally: backend, frontend, tray
- Tray connects to http://localhost:8080 instead of cloud
- No authentication required
- Same UX as cloud mode
- Perfect for development, testing, and isolated environments
- Can switch between cloud/local without code changes

**Local-First Ergonomics**

- Scripts can run directly without tray (agentless execution)
- Optional agent_id parameter for log attribution
- No cloud ceremony required for development
- Deploy to cloud when ready for collaboration

### Filesystem-Based Communication

**Simple Agent Architecture**

- Agents communicate with backend only via filesystem
- No IPC, sockets, or shared memory between agent and backend
- Agents remain simple PowerShell/Python scripts
- All state persists as files (specs/, .felix/, runs/)
- Backend watches filesystem for changes
- File watcher triggers UI updates via WebSocket
- This design enables remote execution (agent writes files, backend reads them)

**Event Emission**

- Agents emit NDJSON events to runs/[run-id]/events.ndjson
- Tray or backend reads events and forwards to API
- Events include: status changes, progress updates, log lines
- Dashboard receives events for real-time updates
- No direct coupling between agent and dashboard

### Orchestration Use Cases

**Overnight Team-Wide Builds**

- Queue 20 requirements at 6pm
- Automatically distribute across 10 team machines
- Each agent picks up work independently
- Wake up to 20 completed features (or clear failure reasons)
- Review all work from dashboard

**CI/CD Agent Farms**

- Dedicated VMs for agent execution
- Pipeline triggers agent runs via API
- Agents execute on isolated VMs
- Results streamed back to pipeline
- Scale by adding more VMs

**Hot-Desk Agent Hosting**

- Install tray on shared workstations
- Agent becomes available when machine powers on
- Automatically contributes to team pool
- No dedicated infrastructure required

**Geographic Distribution**

- Agents on machines in different time zones
- 24/7 continuous execution as machines come online
- Handoff between regions as teams start/end day
- Global agent pool for follow-the-sun development

---

## 🔌 Backend API Server

### RESTful Endpoints

**Projects API**

- `GET /api/projects` - List all projects in organization
- `GET /api/projects/{id}` - Get project details
- `POST /api/projects` - Create new project
- `PUT /api/projects/{id}` - Update project
- `DELETE /api/projects/{id}` - Delete project
- Project status aggregation

**Requirements API**

- `GET /api/requirements` - List requirements with filtering
- `GET /api/requirements/{id}` - Get requirement details
- `POST /api/requirements` - Create requirement
- `PUT /api/requirements/{id}` - Update requirement
- `DELETE /api/requirements/{id}` - Delete requirement
- `GET /api/requirements/{id}/dependencies` - Dependency graph
- Bulk operations and validation execution

**Agents API**

- `POST /api/agents/register` - Register agent (tray → API)
- `POST /api/agents/{id}/heartbeat` - Update heartbeat
- `POST /api/agents/{id}/status` - Update agent status
- `GET /api/agents` - List all agents with availability
- `GET /api/agents/{id}` - Get agent details
- Run history and configuration updates

**Runs API**

- `POST /api/agents/runs` - Create run and send START command
- `POST /api/agents/runs/{id}/stop` - Send STOP command
- `GET /api/agents/runs` - List runs with filtering
- `GET /api/agents/runs/{id}` - Get run details and artifacts
- `GET /api/agents/runs/{id}/logs` - Stream logs
- Run artifacts storage (plans, logs, commits)

**Copilot API**

- `POST /api/copilot/chat` - Streaming chat endpoint
- Context loading from project files
- Multiple LLM adapter support
- Spec generation assistance

### WebSocket Support

**Control Channel** (`/ws/agents/{agent_id}/control`)

- Bidirectional agent control
- Server → Agent: START, STOP commands
- Agent → Server: ACK, STATUS updates
- One connection per tray instance
- Automatic reconnection handling

**Console Streaming** (`/ws/console/{run_id}`)

- Real-time console output from agents
- ANSI escape code support
- Multiple clients can subscribe
- Auto-closes on run completion

**Live Updates** (`/ws/updates`)

- Agent status changes
- Requirement updates
- Run progress notifications
- Multi-client broadcast

### Database Integration

**PostgreSQL Backend**

- Organizations and multi-tenancy (organization-scoped data)
- Projects and requirements tracking
- Agent registry with heartbeat timestamps
- Agent states (availability, last_seen_at)
- Run artifacts storage (plans, logs, exit codes)
- Organization members (future RBAC)
- 9 tables total: organizations, projects, agents, agent_states, runs, run_artifacts, requirements, organization_members, migrations

**Async Operations**

- asyncpg for high performance
- SQLAlchemy 2.0 ORM
- Connection pooling
- Transaction management
- Migrations with version tracking

### File System Watching

**Project Monitoring**

- Watch specs/, .felix/, runs/ directories
- Detect file changes (specs, plans, requirements.json)
- Trigger UI updates via WebSocket
- No polling required for file changes
- Cross-platform with watchfiles library
- Enables remote execution (agent writes, backend reads)

---

## 🎨 Key Differentiators

### 1. **Distributed Swarm Execution**

Unlike single-machine AI dev tools, Felix orchestrates agent swarms across your entire team's infrastructure. Utilize team workstations, VMs, or cloud instances as a coordinated agent pool. Most AI coding assistants run on your local machine only; Felix scales horizontally.

### 2. **Enforced Boundaries**

Felix enforces the planning/building separation at the runtime level. Agents cannot commit code during planning, and cannot advance in building without tests passing. This isn't prompt engineering—it's architectural enforcement.

### 3. **Durable State Management**

Chat transcripts are ephemeral; Felix artifacts are permanent. Every spec, plan, and status persists as a version-controlled file, providing complete audit trails and reproducibility. Agent swarms coordinate through shared filesystem state.

### 4. **Backpressure as a Feature**

Felix treats test failures and build errors as essential feedback, not obstacles to route around. This ensures quality is baked in, not bolted on. Distributed agents all respect the same validation gates.

### 5. **Multi-Agent Support**

Switch seamlessly between different LLM providers (Droid, Claude, Codex, Gemini, Copilot) without changing your workflow. Compare agent performance on identical tasks. Mix and match agents across your swarm.

### 6. **Production Ready**

Felix isn't a prototype or proof-of-concept. It's a full-stack system with:

- Web UI for monitoring and control
- Windows tray integration for always-on agent hosting
- RESTful API for programmatic access
- PostgreSQL backend for enterprise scale and multi-tenancy
- Comprehensive CLI for CI/CD integration
- Distributed orchestration for team-scale execution

### 7. **Framework Agnostic**

Felix works with any tech stack. The agent understands your project by analyzing its structure, not by hardcoded templates. Works with Python, TypeScript, Go, Rust, .NET, and more. Deploy agents anywhere.

### 8. **Incremental Adoption**

Start with a single requirement on one machine. No need to migrate your entire project or provision infrastructure. Felix specs coexist with your existing issue trackers. Add more agents as you validate the approach.

---

## 📊 Use Cases

### Overnight Team-Wide Development

- Queue up 50 requirements with `felix loop` at end of day
- 10 team members leave tray running overnight
- Agents automatically distribute work across all machines
- Wake up to 50 completed features with passing tests (or clear failure reasons)
- Review agent's work via git commits in dashboard

### VM Farm Orchestration

- Spin up 20 Azure VMs or AWS EC2 instances
- Install tray on each VM, register to tenant
- Dashboard shows 20 agents ready
- Start 20 runs simultaneously from web UI
- Each VM executes one requirement independently
- Scale on demand: destroy VMs when done, recreate when needed

### Hot-Desk Agent Hosting

- Install tray on all shared workstations in office
- Machines become agents when powered on
- Automatic contribution to team agent pool
- No dedicated infrastructure required
- Agents become unavailable when machines shut down (graceful)

### Automated Refactoring at Scale

- Write specs describing desired refactoring across 100 services
- Distribute specs across agent swarm
- Agents execute with test validation at each step
- All changes validated before merge
- Rollback on any failure
- Complete refactoring in hours instead of weeks

### Test-Driven Implementation

- Spec includes acceptance criteria tests
- Agent must pass all tests to complete
- Validation enforced across all agents in swarm
- Ensures requirements are met, not just code written
- Living documentation through specs

### Multi-Team Coordination

- Shared requirements.json across teams
- Dependency tracking prevents conflicts
- Each team can use different agents (or different LLMs)
- Centralized status dashboard shows all teams' progress
- Agent swarms per team, all visible in one org

### CI/CD Integration

- Run `felix validate <req-id>` in pipelines
- Block deployments on incomplete requirements
- Automated requirement status updates
- JSON output for pipeline parsing
- Dedicated CI agents (VMs) separate from dev agents

### Brownfield Migration

- Document existing code with `felix context build`
- Create specs for undocumented features
- Gradually add Felix to legacy projects
- Use one agent initially, expand to swarm as confidence grows
- No big-bang migration required

---

## 🚀 Getting Started

### Prerequisites

- **PowerShell 5.1+** or **PowerShell Core 7+**
- **Python 3.11+** (for validation scripts)
- **LLM API Access**: Factory (Droid), Anthropic (Claude), OpenAI (Codex), or Google (Gemini)

### Quick Start

```powershell
# Install Felix CLI
git clone https://github.com/nsasto/felix.git
cd felix
.\scripts\install.ps1

# Set up a project
cd C:\your\project
felix setup

# Run a requirement
felix run S-0001

# Or continuous loop mode
felix loop

# Interactive TUI
felix tui
```

### Cloud Sync (Optional)

Mirror run artifacts to [runfelix.io](https://runfelix.io) for team visibility:

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://runfelix.io"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"
felix run S-0001 --sync
```

See **docs/SYNC_OPERATIONS.md** for full configuration.

---

## 📖 Documentation

- **[README.md](../README.md)** - Overview and quick start
- **[CLI Reference](CLI.md)** - Complete CLI guide and setup
- **[AGENTS.md](../AGENTS.md)** - Operational procedures
- **[CONTEXT.md](../CONTEXT.md)** - Project architecture

### Tutorials

- **[EXECUTION_FLOW.md](../tuts/EXECUTION_FLOW.md)** - How Felix executes requirements
- **[MULTI_AGENT_SUPPORT.md](../tuts/MULTI_AGENT_SUPPORT.md)** - Using multiple agents
- **[SWITCHING_AGENTS.md](../tuts/SWITCHING_AGENTS.md)** - Agent switching guide

---

## 🌟 What Makes Felix Different?

Most AI development tools are either:

- **Copilots**: Great for single-file edits but can't execute multi-step plans
- **Autonomous**: Can execute plans but lack validation and state management

Felix solves both: Autonomous execution with production-grade scaffolding — structured specs, backpressure validation, git-managed state, and optional cloud sync for team visibility.

**The Felix Promise:**

_When you wake up tomorrow, the features you specified today will be implemented, tested, and committed — or you'll know exactly why they weren't._

No surprises. No magic. Just reliable, validated, autonomous software delivery.

---

## 🤝 Enterprise Ready

Felix is designed for teams and organizations:

- **Multi-tenant architecture** - Isolate organizations, projects, and agents
- **Role-based access control** - Control who can start/stop agents (roadmap)
- **Audit trails** - Complete history of all agent actions
- **High availability** - Agents failover automatically, no single point of failure
- **Horizontal scaling** - Add machines to add capacity, linear scaling
- **Security** - Authenticated agent registration, WebSocket TLS, tenant isolation
- **Observability** - Dashboard shows all agents, runs, and logs in real-time

Felix scales from a single developer's laptop to an enterprise with hundreds of agents across global infrastructure.

---

**Ready to transform your development workflow?**

Start with one requirement. Add one agent. Scale to a swarm.

See [CLI.md](CLI.md) for complete setup instructions.

# Felix CLI Architecture

## Overview

Felix is evolving from a PowerShell-based automation framework to a unified CLI executable that provides a professional command-line interface for managing development workflows. This document outlines the architectural vision, component interactions, and migration path from the current PowerShell scripts to `felix.exe`.

## Vision

**Current State (v0.2):**

- PowerShell scripts (felix-agent.ps1, felix-loop.ps1, test-cli.ps1)
- NDJSON event streaming from agent to consumers
- Manual script execution with full paths
- Windows-focused (PowerShell 5.1/7)
- Write-Host rendering in test-cli.ps1

**Future State (v0.3+):**

- Single `felix.exe` executable
- Cross-platform (Windows, macOS, Linux)
- Professional command-line interface with subcommands
- Multiple output modes (TUI, JSON, Plain)
- Installed in PATH for easy access
- Rich terminal UI with real-time dashboards
- Seamless integration with Tray app, Backend, and CI/CD

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         felix.exe                           │
│                     (C# .NET 8 Console)                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Command    │  │   Process    │  │   Renderer   │     │
│  │   Parser     │  │   Manager    │  │   Layer      │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         │                  │                  │            │
│         └──────────┬───────┴──────────────────┘            │
│                    │                                        │
│         ┌──────────▼──────────┐                            │
│         │   Output Selector   │                            │
│         │  (TUI/JSON/Plain)   │                            │
│         └──────────┬──────────┘                            │
└────────────────────┼───────────────────────────────────────┘
                     │
         ┌───────────▼───────────┐
         │   PowerShell Agent    │
         │  felix-agent.ps1      │
         │  (NDJSON → stdout)    │
         └───────────┬───────────┘
                     │
              NDJSON Events
         (run_started, log, error,
          validation_*, task_*)
```

### Component Interactions

#### 1. Felix CLI → PowerShell Agent

The CLI spawns the PowerShell agent as a child process:

```
felix.exe run S-0001
    ↓
Start-Process powershell.exe
    -ArgumentList "-File", "felix-agent.ps1", "C:\dev\Felix", "-RequirementId", "S-0001"
    -RedirectStandardOutput (pipe)
    ↓
Read NDJSON events from stdout
    ↓
Parse and route to renderer
```

**Key Points:**

- CLI never executes agent logic directly
- PowerShell agent remains unchanged (emits NDJSON)
- CLI is a consumer and orchestrator
- Process isolation for reliability

#### 2. Tray App → Felix CLI

The tray application uses felix.exe in JSON mode:

```
Tray App (C#)
    ↓
Process.Start("felix.exe", "run S-0001 --format json")
    ↓
Read NDJSON from stdout
    ↓
Parse events
    ↓
Update system tray UI
    ↓
Show notifications
```

**Benefits:**

- No PowerShell dependency in tray app
- Single executable to bundle
- Consistent event format
- Real-time progress updates

#### 3. Backend API → Felix CLI

The backend spawns felix.exe and streams events to WebSocket clients:

```
Backend (Python FastAPI)
    ↓
subprocess.Popen(["felix", "run", "S-0001", "--format", "json"])
    ↓
Read NDJSON from stdout
    ↓
Parse events
    ↓
WebSocket.send(event) → Web UI clients
```

**Benefits:**

- Backend doesn't need PowerShell knowledge
- Cross-platform backend support
- Real-time updates to web clients
- Simple process management

#### 4. CI/CD Pipeline → Felix CLI

GitHub Actions and other CI systems use felix.exe:

```yaml
# .github/workflows/requirements.yml
- name: Run requirement
  run: felix run S-0001 --format json

- name: Parse results
  run: |
    # Parse NDJSON output
    # Extract metrics
    # Fail if errors detected
```

**Benefits:**

- JSON output for programmatic parsing
- Standard exit codes (0 = success, 1+ = failure)
- No special setup needed
- Cross-platform CI support

### TUI Placement and Role

**The TUI is NOT a separate executable** — it's a rendering mode inside felix.exe.

```
felix.exe
├── Commands (run, loop, status, list, validate)
├── Process Manager (spawns PowerShell agent)
├── Output Selector
│   ├── TUI Mode (rich dashboard) ← Spectre.Console
│   ├── JSON Mode (NDJSON passthrough)
│   └── Plain Mode (colored text)
└── Event Parser (reads NDJSON from agent)
```

**TUI Characteristics:**

- Default mode when running interactively
- Rich, real-time dashboard with:
  - Current requirement status
  - Active tasks with progress bars
  - Recent log entries (scrolling)
  - Validation results with checkmarks
  - Error highlighting
  - Time elapsed
- Detects non-interactive terminals (CI, pipe) → falls back to Plain
- Disabled via `--format` flag when not desired

**Example TUI Layout:**

```
┌─────────────────────────────────────────────────────────┐
│ Felix Agent - Running S-0001                            │
├─────────────────────────────────────────────────────────┤
│ Status: In Progress | Time: 00:02:34 | Iteration: 1/5  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Current Task:                                           │
│ ▰▰▰▰▰▰▰▰▰▰▰▰░░░░░░░░ 60% Running backend tests         │
│                                                         │
│ Recent Logs:                                            │
│ [12:34:56] 🔍 Analyzing requirement specification       │
│ [12:35:12] ✅ Backend tests passed (23/23)              │
│ [12:35:18] 🔧 Updating configuration file               │
│ [12:35:22] ⚙️  Running validation checks                │
│                                                         │
│ Validation Results:                                     │
│ ✅ Backend starts successfully                          │
│ ✅ Health endpoint responds                             │
│ ⏳ Integration tests running...                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Command Structure

### Primary Commands

#### `felix run <requirement-id>`

Execute a single requirement to completion.

```bash
# Run with TUI (default for interactive terminals)
felix run S-0001

# Run with JSON output (machines, tray app, backend)
felix run S-0001 --format json

# Run with plain output (simple terminals, logs)
felix run S-0001 --format plain

# Run with dry-run mode (plan only, no execution)
felix run S-0001 --dry-run
```

**Output:** NDJSON events (format-dependent rendering) + exit code

#### `felix loop`

Run agent in continuous loop mode (processes all planned requirements).

```bash
# Loop with TUI
felix loop

# Loop with JSON output
felix loop --format json

# Loop with max iterations
felix loop --max-iterations 10
```

**Output:** NDJSON events for all requirements processed

#### `felix status [requirement-id]`

Show current status of requirements.

```bash
# Show all requirements
felix status

# Show specific requirement
felix status S-0001

# Output as JSON
felix status --format json
```

**Output:** Status summary or detailed requirement state

#### `felix list [--status <status>]`

List requirements with optional filtering.

```bash
# List all requirements
felix list

# List by status
felix list --status planned
felix list --status in-progress
felix list --status done

# Output as JSON
felix list --format json
```

**Output:** Formatted list of requirements

#### `felix validate <requirement-id>`

Run validation checks for a requirement.

```bash
# Validate requirement
felix validate S-0001

# Validate with verbose output
felix validate S-0001 --verbose
```

**Output:** Validation results + exit code (0 = pass, 1 = fail)

#### `felix version`

Show version information.

```bash
felix version
```

**Output:** Version, commit hash, build date

#### `felix help [command]`

Show help information.

```bash
# General help
felix help

# Command-specific help
felix help run
felix help loop
```

### Global Flags

- `--format <mode>`: Output format (tui, json, plain)
- `--verbose`: Enable verbose logging
- `--quiet`: Suppress non-essential output
- `--no-color`: Disable color output
- `--repo <path>`: Repository path (default: current directory)

## Output Modes

### TUI Mode (Default Interactive)

**When Used:**

- Interactive terminal sessions
- Developer running commands manually
- Default when no `--format` specified and terminal supports it

**Features:**

- Real-time dashboard with live updates
- Progress bars and spinners
- Color-coded status indicators
- Scrolling log viewer
- Task breakdown with completion states
- Validation results with visual indicators

**Technology:** Spectre.Console library (C#)

### JSON Mode (Machine-Readable)

**When Used:**

- Tray application consuming events
- Backend streaming to web clients
- CI/CD pipelines parsing results
- Explicit `--format json` flag

**Output:** Pure NDJSON events from agent (passthrough)

```json
{"event": "run_started", "requirement_id": "S-0001", "timestamp": "2026-02-05T10:00:00Z"}
{"event": "log", "level": "info", "message": "Starting requirement analysis", "component": "planner"}
{"event": "task_completed", "task": "analyze_spec", "status": "success"}
```

**Benefits:**

- Structured data for programmatic parsing
- Same format as PowerShell agent emits
- No rendering overhead
- Streamable (line-by-line processing)

### Plain Mode (Simple Text)

**When Used:**

- Non-interactive terminals (pipes, redirects)
- Log files
- Terminals without rich rendering support
- Explicit `--format plain` flag

**Output:** Colored text with timestamps and log levels

```
[2026-02-05 10:00:00] INFO  Starting requirement S-0001
[2026-02-05 10:00:05] INFO  Running backend tests...
[2026-02-05 10:00:12] SUCCESS Backend tests passed (23/23)
[2026-02-05 10:00:15] ERROR Validation failed: Health endpoint timeout
```

**Benefits:**

- Human-readable without special terminal
- Works in all environments
- Easy to grep and search
- Good for log archival

### Mode Selection Logic

```
Is --format specified?
├── Yes → Use specified format
└── No → Detect environment
    ├── Interactive terminal + TTY + Rich support → TUI
    ├── Piped/redirected stdout → Plain
    └── Fallback → Plain
```

## Integration Patterns

### Tray Application Integration

**Current (v0.2):**

```csharp
// C# Tray App
var psi = new ProcessStartInfo {
    FileName = "powershell.exe",
    Arguments = "-File felix-loop.ps1 C:\\dev\\Felix",
    RedirectStandardOutput = true
};
// Parse NDJSON from stdout...
```

**Future (v0.3+):**

```csharp
// C# Tray App
var psi = new ProcessStartInfo {
    FileName = "felix",
    Arguments = "loop --format json",
    RedirectStandardOutput = true
};
// Parse NDJSON from stdout (same format!)
```

**Benefits:**

- No PowerShell dependency
- Single executable to bundle
- Cross-platform (macOS tray app possible)
- Cleaner process management

### Backend API Integration

**Current (v0.2):**

```python
# Python Backend
proc = subprocess.Popen(
    ["powershell", "-File", "felix-agent.ps1", repo_path, "-RequirementId", req_id],
    stdout=subprocess.PIPE
)
# Parse NDJSON and stream to WebSocket...
```

**Future (v0.3+):**

```python
# Python Backend
proc = subprocess.Popen(
    ["felix", "run", req_id, "--format", "json"],
    stdout=subprocess.PIPE
)
# Parse NDJSON and stream to WebSocket (same format!)
```

**Benefits:**

- Cross-platform backend (Linux servers)
- No PowerShell installation required
- Simpler deployment
- Better container support

### CI/CD Integration

**Current (v0.2):**

```yaml
# .github/workflows/requirements.yml
- name: Run requirement
  shell: powershell
  run: |
    .\felix-agent.ps1 ${{ github.workspace }} -RequirementId S-0001
```

**Future (v0.3+):**

```yaml
# .github/workflows/requirements.yml
- name: Run requirement
  run: felix run S-0001 --format json

- name: Validate requirement
  run: felix validate S-0001
```

**Benefits:**

- Standard shell (no 'shell: powershell' needed)
- Works on Linux/macOS runners
- Clean exit codes for pass/fail
- Structured JSON output for parsing

## Benefits Summary

### For Users

1. **Simple Installation:** Single executable, add to PATH, done
2. **Intuitive Commands:** `felix run`, `felix status`, `felix validate`
3. **Rich Feedback:** TUI provides real-time visual progress
4. **Cross-Platform:** Same commands on Windows, macOS, Linux
5. **Professional UX:** Modern CLI experience (like kubectl, docker, gh)

### For Developers

1. **Language Choice:** C# for CLI, PowerShell agent unchanged
2. **Clean Separation:** CLI = consumer, Agent = business logic
3. **Extensibility:** Easy to add new commands and renderers
4. **Testability:** CLI logic testable independently from agent
5. **Maintainability:** Clear component boundaries

### For Integrators

1. **Consistent Interface:** All consumers use same felix.exe
2. **Standard Formats:** JSON mode for machines, TUI for humans
3. **Process Isolation:** Spawn process, read stdout, done
4. **No Special Dependencies:** Just the executable
5. **Cross-Platform:** Deploy anywhere

### For System Architecture

1. **Decoupled Components:** CLI doesn't know agent internals
2. **Event-Driven:** NDJSON events flow through system
3. **Composable:** Mix and match components (CLI + Web UI + Tray)
4. **Scalable:** Backend can spawn multiple agents
5. **Future-Proof:** Can replace agent implementation without breaking CLI

## Design Decisions

### Why C# for CLI?

1. **Cross-Platform:** .NET 8 runs on Windows, macOS, Linux
2. **Rich Ecosystem:** Spectre.Console, System.CommandLine
3. **Performance:** Fast startup, low memory footprint
4. **Existing Skills:** Team knows C# (tray app already in C#)
5. **Tooling:** Excellent IDE support, debugger, profiler
6. **Self-Contained:** Can bundle .NET runtime in executable

### Why Keep PowerShell Agent?

1. **Working Well:** Agent logic is solid, NDJSON migration complete
2. **Expertise:** Team has PowerShell experience
3. **Windows Integration:** Native PowerShell features (COM, WMI, etc.)
4. **Incremental:** Can migrate agent to C# later if needed
5. **Decoupling:** CLI doesn't care about agent implementation

### Why Spectre.Console?

1. **Rich TUI:** Built-in support for tables, progress, trees, panels
2. **Mature:** Battle-tested in many popular CLI tools
3. **Documentation:** Comprehensive docs and examples
4. **Cross-Platform:** Works on all .NET platforms
5. **Active:** Regular updates and community support

### Why NDJSON Events?

1. **Streaming:** Process line-by-line, low memory
2. **Structured:** Easy to parse and validate
3. **Extensible:** Add new event types without breaking consumers
4. **Standard:** Well-known format (JSON Lines)
5. **Debuggable:** Human-readable for troubleshooting

## Phase 1 Limitations

**Project-Specific Installation:**
- `install-cli.ps1` adds THIS repo's `.felix` folder to PATH
- Only works when this Felix repository is present on the system
- Not suitable for end-user projects or distribution (yet)
- Requires Felix development repository to be cloned

**Current Workarounds:**
- Use direct paths: `.\..felix\felix.ps1 run S-0001`
- Scripts work without installation (recommended for now)
- Each project would need its own copy of scripts (not recommended)

**Phase 2 Solution:**
- System-wide `felix.exe` installed to standard location (e.g., `C:\Program Files\Felix` or `~/.local/bin`)
- Works in ANY project directory without Felix repo present
- No dependency on Felix development repository
- Standard installers (MSI for Windows, homebrew for macOS, apt/snap for Linux)
- Single universal installation serves all projects

---

## Roadmap

### Phase 0: Foundation (Complete ✅)

- NDJSON event system in agent
- PowerShell test-cli.ps1 consumer
- Event type definitions
- Migration documentation

### Phase 1: PowerShell CLI Polish (Next)

- Enhance test-cli.ps1 → felix-cli.ps1
  - Add format modes (json, plain, tui-like)
  - Add filtering and stats
  - Improve rendering
- Create felix.ps1 dispatcher
  - Route commands (run, loop, status, list)
  - Handle global flags
  - Provide help text
- Create install script
  - Add felix.ps1 to PATH
  - Create aliases
  - Verify installation

### Phase 2: C# CLI Development (v0.3)

- Create felix.exe project structure
- Implement command parsing (Spectre.Console.Cli)
- Implement process manager (spawn agent, read NDJSON)
- Implement JSON renderer (passthrough)
- Implement Plain renderer (colored text)
- Implement TUI renderer (Spectre.Console)
- Add all commands (run, loop, status, list, validate)
- Testing and polish
- Self-contained build (bundle .NET runtime)
- Installation package (installer, PATH setup)

### Phase 3: Integration Updates (v0.3)

- Update tray app to use felix.exe
- Update backend to use felix.exe
- Update CI/CD workflows
- Update documentation
- Migration guide for users

### Phase 4: Advanced Features (v0.4+)

- Config file support (~/.felixrc)
- Plugin system
- Remote agent execution
- Web dashboard integration
- Performance monitoring
- Advanced filtering and querying

## Migration Impact

### For End Users

**Minimal disruption:**

- PowerShell scripts continue to work during transition
- felix.exe provides same functionality with better UX
- Opt-in migration (can use both simultaneously)
- Upgrade to felix.exe when ready

### For Tray App

**One-time code change:**

- Replace PowerShell process spawn with felix.exe spawn
- Same NDJSON parsing (format unchanged)
- Benefits from simpler process management

### For Backend

**One-time code change:**

- Replace PowerShell process spawn with felix.exe spawn
- Same NDJSON parsing (format unchanged)
- Benefits from cross-platform support

### For CI/CD

**Update workflow files:**

- Replace PowerShell script calls with felix.exe commands
- Simpler syntax (no shell: powershell needed)
- Better cross-platform support

## Conclusion

The felix.exe CLI represents a significant evolution in the Felix system:

- **Unified Interface:** One executable for all operations
- **Professional UX:** Modern CLI with rich TUI
- **Cross-Platform:** Windows, macOS, Linux support
- **Clean Architecture:** CLI consumer, PowerShell agent producer
- **Seamless Integration:** Works with Tray, Backend, CI/CD
- **Future-Proof:** Extensible design for new features

The migration is incremental, low-risk, and provides immediate benefits while maintaining backward compatibility with existing workflows.

---

**Next Steps:**

1. Review and approve this architectural vision
2. Begin Phase 1 (PowerShell CLI polish)
3. Plan Phase 2 (C# CLI development)
4. Coordinate integration updates

**Related Documents:**

- [CLI_MIGRATION.md](./CLI_MIGRATION.md) - Implementation details and migration strategy
- [RELEASE_NOTES_v0.2.md](../RELEASE_NOTES_v0.2.md) - NDJSON event system details
- [NDJSON_MIGRATION_COMPLETE.md](./NDJSON_MIGRATION_COMPLETE.md) - Event format specifications

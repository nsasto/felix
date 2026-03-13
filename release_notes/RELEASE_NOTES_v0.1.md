# Felix Agent v0.1.0 Release Notes

**Release Date:** February 3, 2026  
**Type:** Initial Public Release  
**Platform:** PowerShell 5.1+ / PowerShell 7.x  
**License:** [TBD]

## Overview

Felix Agent v0.1.0 is an autonomous software development agent system that executes requirements using AI-powered agents (droid, codex) with continuous validation and quality gates. Built entirely in PowerShell, it provides a robust framework for automated software development with safety guardrails, state management, and extensibility.

## Core Features

### 1. Autonomous Agent Execution

- **Single Requirement Mode**: Execute a specific requirement by ID
- **Autonomous Loop Mode**: Automatically process multiple requirements in sequence
- **Iteration Control**: Configurable max iterations per requirement (default: 100)
- **Clean Exit Handling**: Graceful shutdown with proper cleanup and backend unregistration

### 2. Three-Mode State Machine

Felix operates in three distinct modes with explicit transitions:

**Planning Mode**

- Creates execution plan without modifying codebase
- Strict guardrails: only `runs/`, `.felix/state.json`, `.felix/requirements.json` can be modified
- Generates detailed plan artifacts in run directories
- Auto-transitions to Building when plan is complete

**Building Mode**

- Implements changes based on plan
- Most file changes allowed (respects denylist policies)
- Agent can write code, update specs, modify files
- Transitions to Validating when agent signals task completion

**Validating Mode**

- Runs backpressure validation commands (tests, builds)
- If validation passes → Requirement marked complete
- If validation fails → Returns to Building with failure context
- Configurable max retries (default: 3)

### 3. Backpressure Validation System

Continuous quality enforcement through automated testing:

- **Command Parsing**: Extracts validation commands from AGENTS.md
- **Command Types**:
  - `[test]` - Test suite execution (pytest, npm test)
  - `[build]` - Build verification (npm build, docker build)
  - `[validate]` - Custom validation scripts
- **Failure Tracking**: Counts consecutive failures per requirement
- **Auto-Blocking**: Requirements blocked after exceeding max retries
- **Detailed Logging**: Full validation output saved to run directories

**Example AGENTS.md validation commands:**

```markdown
## Validation Commands

- [test] `powershell -File .\scripts\test-backend.ps1`
- [test] `powershell -File .\scripts\test-frontend.ps1`
- [build] `cd app/frontend; npm run build; cd ../..`
```

### 4. Guardrails & Safety

Prevents accidental damage through strict file change enforcement:

- **Mode-Based Rules**: Different permissions for Planning vs Building modes
- **Allowlist/Denylist**: Configurable patterns in `.felix/policies/`
- **Automatic Reversion**: Unauthorized changes automatically reverted via git
- **Violation Reports**: Detailed reports saved to run directories
- **Git State Tracking**: Captures before/after state for all iterations

**Planning Mode Restrictions:**

- ✅ Allowed: `runs/*`, `.felix/state.json`, `.felix/requirements.json`
- ❌ Denied: All code files, specs, configuration

**Building Mode Restrictions:**

- ✅ Allowed: Most files (respects denylist)
- ❌ Denied: `.git/`, `node_modules/`, binary files (configurable)

### 5. Git Integration

Native git operations for full change tracking:

- **Auto-Commit**: Commits changes after successful iterations (configurable)
- **Per-Requirement Commits**: Organized git history by requirement ID
- **Commit Control**:
  - Global: `config.json` → `executor.commit_on_complete`
  - Per-Requirement: `requirements.json` → `requirement.commit_on_complete`
  - CLI Override: `-NoCommit` flag for testing
- **Diff Tracking**: Saves `diff.patch` to run directories
- **Safe Revert**: Guardrail violations trigger automatic rollback

### 6. Requirement Management

Comprehensive requirement tracking and lifecycle management:

**Requirement Properties:**

- `id` - Unique identifier (e.g., S-0001)
- `title` - Human-readable name
- `spec_path` - Path to specification markdown
- `status` - Current state (draft, planned, in_progress, complete, blocked, done)
- `priority` - Urgency level
- `tags` - Categorization tags
- `depends_on` - Dependency array (IDs of prerequisite requirements)
- `updated_at` - Last modification timestamp
- `commit_on_complete` - Optional per-requirement commit override

**Status Workflow:**

```
draft → planned → in_progress → complete → done
                     ↓
                  blocked (on validation failure)
```

### 7. Modular Architecture

15 independent PowerShell core modules with clear responsibilities:

| Module                     | Purpose                 | Key Functions                                          |
| -------------------------- | ----------------------- | ------------------------------------------------------ |
| **config-loader.ps1**      | Configuration loading   | Get-FelixConfig, Get-AgentConfiguration                |
| **initialization.ps1**     | State bootstrapping     | Get-CurrentRequirement, Initialize-StateForRequirement |
| **executor.ps1**           | Main iteration loop     | Invoke-FelixIteration, Build-IterationPrompt           |
| **agent-state.ps1**        | State machine           | Get-CurrentAgentMode, mode transitions                 |
| **validator.ps1**          | Backpressure validation | Invoke-BackpressureValidation                          |
| **guardrails.ps1**         | File change enforcement | Test-FileChangeCompliance                              |
| **git-manager.ps1**        | Git operations          | Invoke-GitCommit, Invoke-GitRevert                     |
| **requirements-utils.ps1** | Requirement tracking    | Get-Requirements, Update-RequirementStatus             |
| **state-manager.ps1**      | State persistence       | Get-FelixState, Save-FelixState                        |
| **plugin-manager.ps1**     | Plugin orchestration    | Invoke-PluginHook                                      |
| **workflow.ps1**           | Workflow tracking       | Set-WorkflowStage                                      |
| **agent-registration.ps1** | Backend integration     | Register-Agent, Send-AgentHeartbeat                    |
| **exit-handler.ps1**       | Clean shutdown          | Exit-FelixAgent                                        |
| **python-utils.ps1**       | Python resolution       | Get-PythonCommand                                      |
| **compat-utils.ps1**       | PS 5.1/7.x compat       | Cross-version utilities                                |

### 8. Plugin System

Extensible architecture for adding functionality without modifying core:

**Plugin Hooks:**

- `on_prediteration` - Before iteration starts
- `on_postiteration` - After iteration completes
- `on_contextgathering` - During context collection phase
- `on_prellm` - Before LLM agent execution
- `on_postllm` - After LLM agent execution
- `on_postvalidation` - After backpressure validation
- `on_backpressurefailed` - When validation fails

**Built-in Plugins (Disabled by Default):**

**metrics-collector**

- Tracks iteration duration, token usage, success rates
- Generates JSON metrics files per iteration
- Aggregates statistics across requirements

**prompt-enhancer**

- Augments prompts with additional context
- Injects relevant code snippets
- Adds dependency information

**slack-notifier**

- Sends notifications to Slack channels
- Alerts on validation failures
- Reports requirement completion

**Plugin Features:**

- JSON manifest with metadata and permissions
- Permission enforcement (read:specs, write:runs, execute:commands, etc.)
- Circuit breaker: auto-disables failing plugins after N failures
- State retention with configurable cleanup

### 9. Multi-Agent Support

Flexible agent configuration system:

**Agent Presets (in ~/.felix/agents.json):**

- **felix-primary** (ID: 0) - droid exec
- **codex-cli** (ID: 1) - codex CLI with workspace-write

**Agent Properties:**

- `id` - Numeric identifier
- `name` - Display name
- `executable` - Command to run (droid, codex, custom)
- `args` - Command-line arguments array
- `working_directory` - Execution directory
- `environment` - Environment variables

**Configuration:**

```json
{
  "agent": {
    "agent_id": 0 // Select agent by ID
  }
}
```

### 10. Comprehensive State Management

**state.json Tracking:**

- Current iteration count
- Last iteration outcome
- Backpressure failure counter
- Validation failure counter
- Current workflow stage
- Last run ID
- Blocked task information (if applicable)
- State machine mode

**State Persistence:**

- Saved after every iteration
- Crash recovery support
- Historical state tracking in run directories

### 11. Run Directory Artifacts

Every iteration creates a timestamped directory with full observability:

**Directory Structure:**

```
runs/S-0001-20260203-143052-it1/
├── requirement_id.txt      # Requirement being worked on
├── prompt.txt              # Full prompt sent to agent
├── response.txt            # Agent's complete response
├── plan.md                 # Generated plan (Planning mode)
├── diff.patch              # Git diff of changes
├── backpressure.log        # Validation command output
├── guardrail-violation.md  # Violation report (if any)
└── metrics.json            # Plugin metrics (if enabled)
```

### 12. Configuration System

**config.json Features:**

- **Executor Settings**: mode, max_iterations, default_mode, auto_transition, commit_on_complete
- **Agent Selection**: agent_id to choose from presets
- **Paths**: Customizable paths for specs, agents, runs
- **Backpressure**: Enable/disable, custom commands, max_retries
- **Plugins**: Enable/disable, discovery path, disabled list, circuit breaker settings
- **UI Integration**: Theme preferences
- **Copilot Integration**: Provider, model, context sources, features

### 13. Prompt Engineering

Mode-specific prompts with context injection:

**Prompt Templates (.felix/prompts/):**

- `planning.md` - Planning mode instructions
- `building.md` - Building mode instructions
- `learning.md` - Learning mode (future feature)
- `check-tasks-complete.md` - Task completion detection
- `spec_rules.md` - Specification authoring guidelines

**Context Sources:**

- Current requirement specification
- AGENTS.md operational guide
- Requirement dependencies
- Previous iteration outcomes (if failed)
- Project structure information

### 14. Backend API Integration (Optional)

Agent registration and heartbeat system:

- **Registration**: Agents register with backend on startup
- **Heartbeat**: Background job sends status updates every 5 seconds
- **Unregistration**: Clean unregister on shutdown
- **Graceful Degradation**: Works offline if backend unavailable
- **Process Tracking**: Backend tracks active agent processes

### 15. Testing Framework

Built-in PowerShell test harness:

**Test Coverage:**

- Core module functionality (126+ tests)
- State machine transitions
- Git operations
- Guardrail enforcement
- Configuration loading
- Plugin system
- Requirement lifecycle

**Test Execution:**

```powershell
# Single test file
.\.felix\tests\test-framework.ps1 .\.felix\tests\test-config-loader.ps1

# All tests
Get-ChildItem .felix/tests/test-*.ps1 | ForEach-Object {
    .\.felix\tests\test-framework.ps1 $_
}
```

## Installation & Setup

### Prerequisites

- PowerShell 5.1 or PowerShell 7.x
- Git installed and in PATH
- AI agent executable (droid or codex)

### Quick Start

1. **Initialize Project Structure:**

   ```powershell
   # Ensure .felix/ directory exists with required files:
   .felix/
   ├── config.json
   ├── requirements.json
   ├── state.json
   ├── agents.json (in ~/.felix/)
   ```

2. **Configure Agent:**
   Edit `~/.felix/agents.json` to add your agent presets

3. **Add Requirements:**
   Edit `.felix/requirements.json` to define requirements

4. **Run Agent:**

   ```powershell
   # Single requirement
   .\.felix\felix-agent.ps1 . -RequirementId S-0001

   # Autonomous loop
   .\.felix\felix-loop.ps1 C:\path\to\project
   ```

## Command-Line Interface

### felix-agent.ps1

Execute a single requirement:

```powershell
.\.felix\felix-agent.ps1 <ProjectPath> [-RequirementId <ID>] [-NoCommit]
```

**Parameters:**

- `ProjectPath` (Required) - Path to project root
- `RequirementId` (Optional) - Specific requirement to execute (otherwise picks first planned)
- `NoCommit` (Optional) - Skip git commits (useful for testing)

**Exit Codes:**

- `0` - Success (requirement complete)
- `1` - Error (general failure)
- `2` - Blocked (backpressure failures exceeded retries)
- `3` - Blocked (validation failures exceeded retries)

### felix-loop.ps1

Autonomous multi-requirement execution:

```powershell
.\.felix\felix-loop.ps1 <ProjectPath> [-MaxRequirements <N>] [-NoCommit]
```

**Parameters:**

- `ProjectPath` (Required) - Path to project root
- `MaxRequirements` (Optional) - Limit number of requirements to process (default: 999)
- `NoCommit` (Optional) - Skip git commits

**Behavior:**

- Processes requirements sequentially in order
- Automatically blocks and skips failed requirements
- Creates loop lock file to prevent concurrent execution
- Exits when no more planned/in_progress requirements found

## Configuration Reference

### Executor Settings

```json
{
  "executor": {
    "mode": "local", // Execution mode
    "max_iterations": 100, // Safety limit per requirement
    "default_mode": "planning", // Start in planning or building
    "auto_transition": true, // Auto-transition planning → building
    "commit_on_complete": true // Create git commit after completion
  }
}
```

### Backpressure Settings

```json
{
  "backpressure": {
    "enabled": true, // Enable validation
    "commands": [], // Custom commands (empty = parse AGENTS.md)
    "max_retries": 3 // Max consecutive failures before blocking
  }
}
```

### Plugin Settings

```json
{
  "plugins": {
    "enabled": false, // Enable plugin system
    "discovery_path": ".felix/plugins",
    "api_version": "v1",
    "disabled": ["plugin-name"], // Plugins to skip
    "state_retention_days": 7, // Plugin state cleanup
    "circuit_breaker_max_failures": 3 // Auto-disable after N failures
  }
}
```

## Architecture Highlights

### Design Principles

1. **Modularity**: 15 independent core modules with single responsibilities
2. **Extensibility**: Plugin system allows customization without core changes
3. **Safety**: Guardrails prevent accidental damage to codebase
4. **Observability**: Full artifact tracking in run directories
5. **Git-Native**: All changes tracked in version control
6. **State Machine**: Explicit mode transitions with clear rules
7. **Validation-First**: Continuous testing ensures quality
8. **PowerShell-First**: Runs on Windows, Linux, macOS with PowerShell

### Key Innovations

**Guardrail System**
Unlike traditional CI/CD that validates after-the-fact, Felix's guardrails prevent invalid changes before they're committed. Planning mode's strict file restrictions ensure agents can't accidentally damage the codebase while strategizing.

**Backpressure Validation**
Continuous validation after every building iteration provides immediate feedback. Failed validations return agents to building mode with detailed failure context, enabling rapid iteration and correction.

**State Machine with Context**
The three-mode state machine (Planning → Building → Validating) provides clear phase separation. Each mode has distinct permissions, prompts, and success criteria, reducing ambiguity and improving agent performance.

**Plugin Hook System**
Eight strategic plugin hooks allow customization at critical execution points without modifying core logic. Plugins can augment prompts, track metrics, send notifications, or inject custom validation logic.

## Known Limitations & Future Work

### Current Limitations

1. **Single Agent at a Time**: No concurrent requirement execution (by design for safety)
2. **PowerShell Only**: Core system requires PowerShell environment
3. **Git Required**: All features assume git repository
4. **No Rollback**: Cannot undo completed requirements (manual git revert needed)
5. **Limited Error Recovery**: Some failure modes require manual intervention

### Planned Features (Future Releases)

- **Learning Mode**: Agent learns from past successes/failures
- **Requirement Validation**: Automated spec quality checking
- **Parallel Execution**: Multiple agents on independent requirements
- **Cost Tracking**: LLM token usage and cost estimation
- **Web Dashboard**: Real-time monitoring and control
- **Docker Support**: Containerized agent execution
- **Cloud Integration**: Azure/AWS agent hosting

## Migration Guide

### From Previous Versions

This is the initial release - no migration needed.

### Breaking Changes

N/A - Initial release

## Support & Documentation

### Documentation

- **README.md**: Project overview and quick start
- **.felix/README.md**: Detailed architecture and flow diagrams
- **.felix/config.md**: Configuration reference
- **HOW_TO_USE.md**: User guide and best practices
- **AGENTS.md**: Operational guide for agents

### Community

- GitHub Issues: [Link TBD]
- Discussions: [Link TBD]
- Discord: [Link TBD]

## Contributors

[TBD]

## License

[TBD]

---

**Release Commit:** 6c0c6c5  
**Previous Version:** N/A (Initial Release)  
**Next Version:** 0.2.0 (Planned)

# Felix Agent System

**Version:** 0.1.0  
**Core:** PowerShell-based autonomous agent executor

## Directory Structure

```
.felix/
├── felix-agent.ps1          # Main entry point - orchestrates single requirement
├── felix-loop.ps1           # Multi-requirement autonomous loop
├── config.json              # Global configuration
├── agents.json              # Agent presets (droid, codex, etc.)
├── requirements.json        # Requirement tracking and status
├── state.json               # Runtime execution state
├── config.md                # Configuration documentation
│
├── core/                    # Core PowerShell modules
│   ├── config-loader.ps1    # Load config, validate structure
│   ├── initialization.ps1   # Initialize state for requirements
│   ├── executor.ps1         # Main iteration loop logic
│   ├── agent-registration.ps1  # Backend registration/heartbeat
│   ├── agent-state.ps1      # State machine (Planning/Building/Validating)
│   ├── workflow.ps1         # Workflow stage tracking
│   ├── validator.ps1        # Backpressure validation (tests/builds)
│   ├── guardrails.ps1       # File change validation by mode
│   ├── git-manager.ps1      # Git operations (diff, commit, revert)
│   ├── requirements-utils.ps1  # Load/update requirements.json
│   ├── state-manager.ps1    # Load/save state.json
│   ├── plugin-manager.ps1   # Plugin system orchestration
│   ├── python-utils.ps1     # Python executable resolution
│   ├── exit-handler.ps1     # Clean shutdown and unregistration
│   └── compat-utils.ps1     # PowerShell 5.1/7.x compatibility
│
├── prompts/                 # Mode-specific prompts
│   ├── planning.md          # Planning mode prompt template
│   ├── building.md          # Building mode prompt template
│   ├── learning.md          # Learning mode prompt (future)
│   ├── check-tasks-complete.md  # Task completion detection
│   └── spec_rules.md        # Specification authoring rules
│
├── policies/                # Permission control
│   ├── allowlist.json       # Allowed file patterns by mode
│   └── denylist.json        # Forbidden file patterns
│
├── plugins/                 # Plugin system (optional)
│   ├── metrics-collector/   # Iteration metrics tracking
│   ├── prompt-enhancer/     # Prompt augmentation
│   ├── slack-notifier/      # Slack notifications
│   └── hook-contracts.ps1   # Plugin hook definitions
│
├── scripts/                 # Utilities
│   └── set-workflow-stage.ps1  # Update workflow stage in state
│
└── tests/                   # PowerShell test suite
    ├── test-framework.ps1   # Test harness
    └── test-*.ps1          # Individual test files
```

## Execution Flow

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        felix-agent.ps1                          │
│                     (Main Entry Point)                          │
└────────────┬────────────────────────────────────────────────────┘
             │
             ├─► Load 15 Core Modules (dot-sourcing)
             │
             ├─► config-loader.ps1
             │   └─► Validate project structure (.felix/, specs/)
             │   └─► Load config.json, agents.json
             │
             ├─► initialization.ps1
             │   └─► Get current requirement (requirements.json)
             │   └─► Initialize state.json for requirement
             │   └─► Setup plugin permissions
             │
             ├─► agent-registration.ps1
             │   └─► Register with backend API (optional)
             │   └─► Start heartbeat background job
             │
             └─► executor.ps1: Invoke-FelixIteration (loop)
                 │
                 ├─► ITERATION START
                 │   ├─► workflow.ps1: Set stage "start_iteration"
                 │   ├─► Create run directory (runs/S-XXXX-timestamp-itN/)
                 │   └─► plugin-manager.ps1: Initialize plugins
                 │
                 ├─► DETERMINE MODE
                 │   ├─► workflow.ps1: Set stage "determine_mode"
                 │   ├─► agent-state.ps1: Check current mode
                 │   │   └─► Planning → Building → Validating
                 │   └─► Load mode-specific prompt (prompts/*.md)
                 │
                 ├─► GATHER CONTEXT
                 │   ├─► workflow.ps1: Set stage "gather_context"
                 │   ├─► Read current requirement spec
                 │   ├─► Read AGENTS.md
                 │   ├─► Check requirement dependencies
                 │   └─► plugin-manager.ps1: on_contextgathering hook
                 │
                 ├─► BUILD PROMPT
                 │   ├─► workflow.ps1: Set stage "build_prompt"
                 │   ├─► Combine: mode prompt + context + history
                 │   └─► plugin-manager.ps1: on_prellm hook
                 │
                 ├─► EXECUTE LLM
                 │   ├─► workflow.ps1: Set stage "execute_llm"
                 │   ├─► Run agent executable (droid, codex, etc.)
                 │   └─► plugin-manager.ps1: on_postllm hook
                 │
                 ├─► DETECT TASK COMPLETION
                 │   ├─► workflow.ps1: Set stage "detect_task"
                 │   ├─► Parse agent response for completion signals
                 │   └─► If complete → transition to Validating mode
                 │
                 ├─► RUN BACKPRESSURE VALIDATION
                 │   ├─► workflow.ps1: Set stage "run_backpressure"
                 │   ├─► validator.ps1: Parse AGENTS.md for commands
                 │   │   └─► Run [test] commands (pytest, npm test)
                 │   │   └─► Run [build] commands (npm build)
                 │   ├─► plugin-manager.ps1: on_postvalidation hook
                 │   └─► If failed → increment failure counter
                 │       └─► If max retries → BLOCK requirement
                 │
                 ├─► VALIDATE GUARDRAILS
                 │   ├─► guardrails.ps1: Check file changes
                 │   ├─► Planning mode: Only runs/, .felix/state.json allowed
                 │   ├─► Building mode: Most changes allowed
                 │   └─► If violation → git-manager.ps1: Revert changes
                 │
                 ├─► COMMIT CHANGES
                 │   ├─► workflow.ps1: Set stage "commit_changes"
                 │   ├─► git-manager.ps1: Create commit (if enabled)
                 │   │   └─► Check commit_on_complete setting
                 │   │   └─► Check requirement.commit_on_complete override
                 │   └─► Capture git diff to diff.patch
                 │
                 ├─► UPDATE STATE
                 │   ├─► state-manager.ps1: Save iteration outcome
                 │   ├─► requirements-utils.ps1: Update status if complete
                 │   └─► Clear workflow stage
                 │
                 └─► ITERATION END
                     ├─► If requirement complete → EXIT
                     ├─► If max iterations → EXIT
                     └─► Continue to next iteration
```

### File Call Sequence

```
felix-agent.ps1
│
├─[LOAD]─► compat-utils.ps1
├─[LOAD]─► agent-state.ps1
├─[LOAD]─► git-manager.ps1
├─[LOAD]─► state-manager.ps1
├─[LOAD]─► plugin-manager.ps1
├─[LOAD]─► validator.ps1
├─[LOAD]─► workflow.ps1
├─[LOAD]─► agent-registration.ps1
├─[LOAD]─► guardrails.ps1
├─[LOAD]─► python-utils.ps1
├─[LOAD]─► requirements-utils.ps1
├─[LOAD]─► exit-handler.ps1
├─[LOAD]─► config-loader.ps1
├─[LOAD]─► initialization.ps1
├─[LOAD]─► executor.ps1
│
├─[CALL]─► config-loader.ps1::Get-ProjectPaths()
├─[CALL]─► config-loader.ps1::Test-ProjectStructure()
├─[CALL]─► config-loader.ps1::Get-FelixConfig()
├─[CALL]─► config-loader.ps1::Get-AgentConfiguration()
│
├─[CALL]─► requirements-utils.ps1::Get-Requirements()
├─[CALL]─► initialization.ps1::Get-CurrentRequirement()
├─[CALL]─► initialization.ps1::Initialize-StateForRequirement()
│
├─[CALL]─► agent-registration.ps1::Register-Agent()
├─[CALL]─► agent-registration.ps1::Start-HeartbeatJob()
│
└─[CALL]─► executor.ps1::Invoke-FelixIteration() [LOOP]
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("start_iteration")
    ├─[CALL]─► plugin-manager.ps1::Initialize-PluginSystem()
    │
    ├─[CALL]─► executor.ps1::Get-ExecutionMode()
    │   └─[CALL]─► agent-state.ps1::Get-CurrentAgentMode()
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("determine_mode")
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("gather_context")
    │   └─[CALL]─► plugin-manager.ps1::Invoke-PluginHook("on_contextgathering")
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("build_prompt")
    │   ├─[CALL]─► executor.ps1::Build-IterationPrompt()
    │   └─[CALL]─► plugin-manager.ps1::Invoke-PluginHook("on_prellm")
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("execute_llm")
    │   ├─[CALL]─► executor.ps1::Invoke-AgentExecution()
    │   └─[CALL]─► plugin-manager.ps1::Invoke-PluginHook("on_postllm")
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("detect_task")
    │   └─[CALL]─► executor.ps1::Process-TaskCompletion()
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("run_backpressure")
    │   ├─[CALL]─► validator.ps1::Invoke-BackpressureValidation()
    │   └─[CALL]─► plugin-manager.ps1::Invoke-PluginHook("on_postvalidation")
    │
    ├─[CALL]─► guardrails.ps1::Test-FileChangeCompliance()
    │   └─[IF FAIL]─► git-manager.ps1::Invoke-GitRevert()
    │
    ├─[CALL]─► workflow.ps1::Set-WorkflowStage("commit_changes")
    │   └─[CALL]─► git-manager.ps1::Invoke-GitCommit()
    │
    ├─[CALL]─► state-manager.ps1::Save-FelixState()
    ├─[CALL]─► requirements-utils.ps1::Update-RequirementStatus()
    │
    └─[CALL]─► workflow.ps1::Set-WorkflowStage($null) [clear]

[ON EXIT]
└─[CALL]─► exit-handler.ps1::Exit-FelixAgent()
    ├─[CALL]─► agent-registration.ps1::Stop-HeartbeatJob()
    ├─[CALL]─► agent-registration.ps1::Unregister-Agent()
    └─[EXIT]─► PowerShell exit code
```

## State Machine

The agent operates in three primary modes:

```
┌──────────┐
│ Planning │  ← Start here for new requirements
└────┬─────┘
     │ Plan complete?
     ↓
┌──────────┐
│ Building │  ← Implements changes based on plan
└────┬─────┘
     │ Task detected as complete?
     ↓
┌────────────┐
│ Validating │  ← Runs backpressure validation
└────┬───────┘
     │
     ├─ Pass → Mark requirement complete, EXIT
     └─ Fail → Back to Building (retry)
```

### Mode Rules

**Planning Mode:**

- Only allowed to modify: `runs/`, `.felix/state.json`, `.felix/requirements.json`
- Purpose: Create execution plan without touching codebase
- Guardrails strictly enforced

**Building Mode:**

- Most file changes allowed (respects policies/denylist.json)
- Purpose: Implement changes, write code, update specs
- Transitions to Validating when agent signals completion

**Validating Mode:**

- Runs backpressure commands (tests, builds)
- If pass → Requirement marked complete
- If fail → Returns to Building with failure context
- Max retries configurable (default: 3)

## Core Modules Reference

### config-loader.ps1

**Purpose:** Configuration loading and project validation  
**Key Functions:**

- `Get-ProjectPaths()` - Computes all standard paths
- `Test-ProjectStructure()` - Validates required directories exist
- `Get-FelixConfig()` - Loads config.json
- `Get-AgentConfiguration()` - Resolves agent executable/args

### initialization.ps1

**Purpose:** State initialization and requirement selection  
**Key Functions:**

- `Get-CurrentRequirement()` - Finds next requirement to work on
- `Initialize-StateForRequirement()` - Creates/resets state.json
- `Initialize-ExecutionState()` - Full state bootstrap

### executor.ps1

**Purpose:** Main iteration loop orchestration  
**Key Functions:**

- `Invoke-FelixIteration()` - Single iteration execution
- `Get-ExecutionMode()` - Determines current mode
- `Build-IterationPrompt()` - Constructs prompt from context
- `Invoke-AgentExecution()` - Runs droid/codex agent
- `Process-TaskCompletion()` - Detects task completion

### agent-state.ps1

**Purpose:** State machine management  
**Key Functions:**

- `Get-CurrentAgentMode()` - Returns Planning/Building/Validating
- Mode transition logic
- State validation

### validator.ps1

**Purpose:** Backpressure validation (tests/builds)  
**Key Functions:**

- `Invoke-BackpressureValidation()` - Runs all validation commands
- `Get-BackpressureCommands()` - Parses AGENTS.md for commands
- Supports `[test]`, `[build]`, `[validate]` tags

### guardrails.ps1

**Purpose:** File change enforcement by mode  
**Key Functions:**

- `Test-FileChangeCompliance()` - Validates changes against mode rules
- Checks allowlist.json and denylist.json
- Generates violation reports

### git-manager.ps1

**Purpose:** Git operations  
**Key Functions:**

- `Get-GitState()` - Captures current git status
- `Invoke-GitCommit()` - Creates requirement commit
- `Invoke-GitRevert()` - Reverts unauthorized changes
- `Test-AllowedChanges()` - Validates change patterns

### requirements-utils.ps1

**Purpose:** Requirement tracking  
**Key Functions:**

- `Get-Requirements()` - Loads requirements.json
- `Update-RequirementStatus()` - Changes requirement status
- `Get-RequirementById()` - Finds specific requirement

### state-manager.ps1

**Purpose:** State persistence  
**Key Functions:**

- `Get-FelixState()` - Loads state.json
- `Save-FelixState()` - Persists state.json
- State schema validation

### plugin-manager.ps1

**Purpose:** Plugin system orchestration  
**Key Functions:**

- `Initialize-PluginSystem()` - Loads enabled plugins
- `Invoke-PluginHook()` - Executes plugin hooks
- Circuit breaker for failing plugins
- Plugin permission enforcement

### workflow.ps1

**Purpose:** Workflow stage tracking  
**Key Functions:**

- `Set-WorkflowStage()` - Updates current workflow stage
- Stages: start_iteration, determine_mode, gather_context, build_prompt, execute_llm, detect_task, run_backpressure, commit_changes

### agent-registration.ps1

**Purpose:** Backend API integration  
**Key Functions:**

- `Register-Agent()` - Registers with backend API
- `Send-AgentHeartbeat()` - Sends heartbeat
- `Start-HeartbeatJob()` - Background heartbeat job
- `Unregister-Agent()` - Clean unregistration

### exit-handler.ps1

**Purpose:** Clean shutdown  
**Key Functions:**

- `Exit-FelixAgent()` - Graceful exit with cleanup
- Stops heartbeat job
- Unregisters from backend
- Returns proper exit codes

## Configuration Files

### config.json

Global configuration for agent behavior, plugins, backpressure, and paths.

### agents.json

Agent preset definitions (stored in `~/.felix/agents.json`):

- **felix-primary** - droid exec
- **codex-cli** - codex CLI with workspace-write

### requirements.json

Requirement tracking with status, dependencies, priority, labels.

**Status values:**

- `draft` - Not ready
- `planned` - Ready to work on
- `in_progress` - Currently being worked
- `complete` - Finished and validated
- `blocked` - Cannot proceed
- `done` - Archived/historical

### state.json

Runtime execution state:

- Current iteration count
- Last outcome
- Backpressure failure counter
- Blocked task info
- Workflow stage
- Run ID

## Plugin System

Plugins extend agent behavior at specific hooks:

**Hooks:**

- `on_prediteration` - Before iteration starts
- `on_postiteration` - After iteration completes
- `on_contextgathering` - During context collection
- `on_prellm` - Before LLM execution
- `on_postllm` - After LLM execution
- `on_postvalidation` - After backpressure validation
- `on_backpressurefailed` - When validation fails

**Built-in Plugins:**

- **metrics-collector** - Tracks iteration metrics
- **prompt-enhancer** - Augments prompts with additional context
- **slack-notifier** - Sends Slack notifications

Plugins are PowerShell scripts with JSON manifests defining permissions.

## Testing

Run tests with:

```powershell
# Individual test file
.\.felix\tests\test-framework.ps1 .\.felix\tests\test-config-loader.ps1

# All tests
Get-ChildItem .felix/tests/test-*.ps1 | ForEach-Object { .\.felix\tests\test-framework.ps1 $_ }
```

Tests cover:

- Core module functionality
- State machine transitions
- Git operations
- Guardrail enforcement
- Configuration loading
- Plugin system

## Usage

### Single Requirement

```powershell
.\.felix\felix-agent.ps1 . -RequirementId S-0001
```

### Autonomous Loop

```powershell
.\.felix\felix-loop.ps1 C:\path\to\project
```

### Testing Mode (no commits)

```powershell
.\.felix\felix-agent.ps1 . -RequirementId S-0001 -NoCommit
```

## Exit Codes

- `0` - Success (requirement complete)
- `1` - Error (general failure)
- `2` - Blocked (backpressure failures exceeded max retries)
- `3` - Blocked (validation failures exceeded max retries)

## Architecture Principles

1. **Modular Design**: 15 independent core modules with clear responsibilities
2. **Dot-Sourcing**: Modules loaded via dot-sourcing (not Import-Module)
3. **State Machine**: Explicit mode transitions (Planning → Building → Validating)
4. **Guardrails**: File change enforcement prevents accidental damage
5. **Backpressure**: Continuous validation ensures quality
6. **Plugin System**: Extensible without modifying core
7. **Git-Native**: All changes tracked in git history
8. **PowerShell-First**: Runs on PowerShell 5.1+ and PowerShell 7.x

## Version History

- **0.1.0** - Initial release (February 2026)
  - Core agent execution loop
  - State machine with 3 modes
  - Backpressure validation
  - Guardrail enforcement
  - Plugin system foundation
  - Git integration
  - Multi-requirement autonomous loop

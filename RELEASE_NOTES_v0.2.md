# Felix Agent v0.2.0 Release Notes

**Release Date:** February 5, 2026  
**Type:** Major Feature Release - NDJSON Event Streaming  
**Platform:** PowerShell 5.1+ / PowerShell 7.x  
**Status:** UI-Agnostic Architecture Complete

## Overview

Felix Agent v0.2.0 introduces a complete architectural shift to **NDJSON (Newline-Delimited JSON) event streaming**, making the agent fully UI-agnostic. All console output has been replaced with structured events emitted to stdout, enabling integration with web UIs, logging systems, monitoring dashboards, and any NDJSON consumer.

This release eliminates the previous console-only output model and establishes Felix as a true backend service that can power rich frontends without code changes.

## 🎯 Breaking Changes

**None** - The migration is fully backward compatible. The agent continues to function identically when run directly in a terminal, with the added benefit of structured event output.

## ✨ New Features

### 1. NDJSON Event Streaming Architecture

The agent now emits **15 structured event types** as newline-delimited JSON to stdout:

#### Event Types

**Lifecycle Events**

- `run_started` - Agent execution begins (includes run_id, project_path, requirement_id)
- `run_completed` - Agent execution ends (includes status, exit_code, duration)
- `iteration_started` - Iteration begins (includes iteration number, max iterations, mode)
- `iteration_completed` - Iteration ends (includes outcome)

**Agent Execution Events**

- `agent_execution_started` - LLM agent (droid/codex) invocation starts
- `agent_execution_completed` - LLM agent completes (includes duration)

**Validation Events**

- `validation_started` - Backpressure validation begins (includes command count)
- `validation_command_started` - Individual command starts (includes command text, type)
- `validation_command_completed` - Individual command completes (includes exit code, success status)
- `validation_completed` - All validation commands complete (includes pass/fail counts)

**Task & State Events**

- `task_completed` - Agent signals task completion (includes signal type, mode)
- `state_transitioned` - State machine transitions (Planning → Building → Validating → Complete)
- `phase_started` / `phase_completed` - Major phase transitions (planning_complete, etc.)

**General Events**

- `log` - Structured log messages (includes level: debug/info/warn/error, component, message)
- `error_occurred` - Structured errors (includes error_type, severity, message, optional context)
- `progress` - Progress updates (includes percentage, current, total, description)
- `artifact_created` - File artifacts generated (includes path, type, size_bytes)

#### Event Structure

All events follow a consistent schema:

```json
{
  "timestamp": "2026-02-05T08:18:12.4142800Z",
  "type": "log",
  "data": {
    "level": "info",
    "component": "executor",
    "message": "Starting iteration 1 of 100"
  }
}
```

### 2. PowerShell Test CLI Consumer

A reference implementation demonstrating NDJSON consumption:

**Location:** `.felix/test-cli.ps1`

**Features:**

- Real-time event parsing from agent stdout
- ANSI colored terminal rendering
- Event type-specific formatting
- Event statistics tracking
- Legacy output fallback (gracefully handles non-NDJSON output)
- PowerShell 5.1 and 7.x compatible

**Usage:**

```powershell
# Run agent with colored event rendering
.\.felix\test-cli.ps1 C:\dev\Felix S-0002
```

**Output Example:**

```
============================================================
 Felix Run Started
 Run ID: init
 Requirement: S-0002
============================================================

[2026-02-05T08:18:12Z] INFO [executor] Starting iteration 1 of 100

============================================================
 Iteration 1/100 - Mode: PLANNING
============================================================

[2026-02-05T08:18:15Z] AGENT EXECUTION STARTED
  Agent: droid

[2026-02-05T08:20:45Z] AGENT EXECUTION COMPLETED
  Duration: 150.2s

[2026-02-05T08:20:46Z] State: Planning → Building
```

### 3. Loop Mode Event Support

`felix-loop.ps1` (multi-requirement executor) now emits structured events:

- Requirement selection events
- Processing status per requirement
- Completion verification
- Error tracking across requirements
- Progress counters (N/M requirements processed)

### 4. Component-Based Logging

Log events include a `component` field for filtering and debugging:

- `agent` - Main agent lifecycle
- `init` - Initialization and configuration
- `executor` - Iteration loop and task processing
- `validator` - Backpressure validation
- `state-machine` - State transitions
- `loop` - Multi-requirement processing
- `plugins` - Plugin system events
- `artifacts` - File generation tracking

### 5. Silent Workflow Tracking

Workflow stage transitions (previously console output) are now tracked silently in `state.json`:

```json
{
  "current_workflow_stage": "execute_llm",
  "workflow_stage_timestamp": "2026-02-05T08:18:12.000Z",
  "workflow_stage_history": [
    { "stage": "start_iteration", "timestamp": "2026-02-05T08:18:10.000Z" },
    { "stage": "determine_mode", "timestamp": "2026-02-05T08:18:11.000Z" },
    { "stage": "execute_llm", "timestamp": "2026-02-05T08:18:12.000Z" }
  ]
}
```

## 🔧 Technical Improvements

### Event Emission System

**Location:** `.felix/core/emit-event.ps1`

**Functions:**

- `Emit-Event` - Core event emission (uses `Write-Output` for stdout)
- `Emit-Log` - Structured logging with levels and components
- `Emit-Error` - Structured error emission
- `Emit-Progress` - Progress tracking
- `Emit-Artifact` - File artifact tracking
- `Emit-RunStarted` / `Emit-RunCompleted` - Lifecycle events
- `Emit-IterationStarted` / `Emit-IterationCompleted` - Iteration events
- `Emit-AgentExecutionStarted` / `Emit-AgentExecutionCompleted` - Agent invocation events
- `Emit-ValidationStarted` / `Emit-ValidationCompleted` - Validation lifecycle
- `Emit-ValidationCommandStarted` / `Emit-ValidationCommandCompleted` - Per-command events
- `Emit-StateTransitioned` - State machine transitions
- `Emit-TaskCompleted` - Task completion signals
- `Emit-PhaseStarted` / `Emit-PhaseCompleted` - Phase transitions

### Eliminated Write-Host Blocking

**Problem Solved:** Previous versions used `Write-Host` extensively, which writes to the console host (not stdout) and blocks when output is redirected or when no console is attached.

**Solution:** All critical execution path calls converted to `Write-Output`-based event emission, enabling:

- Output redirection without hanging
- Headless execution (no console required)
- Clean stdout stream for parsing
- Stderr remains available for PowerShell errors

### Files Converted (100% Coverage)

**Core Execution Path:**

- ✅ `felix-agent.ps1` - Main entry point
- ✅ `felix-loop.ps1` - Multi-requirement executor
- ✅ `executor.ps1` - Iteration loop and task processing
- ✅ `validator.ps1` - Backpressure validation
- ✅ `initialization.ps1` - Requirement loading and state setup
- ✅ `agent-registration.ps1` - Backend registration
- ✅ `requirements-utils.ps1` - Requirement management
- ✅ `plugin-manager.ps1` - Plugin system
- ✅ `guardrails.ps1` - Planning mode guardrails
- ✅ `set-workflow-stage.ps1` - Workflow tracking (silenced)

**Non-Critical Files (Intentionally Preserved):**

- `test-cli.ps1` - UI consumer (uses `Write-Host` for colored output)
- `plugins/test-harness.ps1` - Testing utility
- `tests/**` - Test scripts

## 📊 Benefits

### For Web UI Development

```javascript
// Example: Consuming Felix events in Node.js
const { spawn } = require("child_process");
const readline = require("readline");

const felix = spawn("powershell", [
  "-NoProfile",
  "-File",
  ".felix/felix-agent.ps1",
  "C:\\dev\\MyProject",
  "-RequirementId",
  "REQ-001",
]);

const rl = readline.createInterface({ input: felix.stdout });

rl.on("line", (line) => {
  try {
    const event = JSON.parse(line);

    switch (event.type) {
      case "log":
        console.log(`[${event.data.level}] ${event.data.message}`);
        break;
      case "agent_execution_started":
        console.log("🤖 Agent started...");
        break;
      case "task_completed":
        console.log("✅ Task complete!");
        break;
      case "error_occurred":
        console.error(`❌ Error: ${event.data.message}`);
        break;
    }
  } catch (e) {
    console.warn("Non-JSON output:", line);
  }
});
```

### For Monitoring & Observability

- **Real-time Progress**: Track iteration counts, validation results, and task completion
- **Performance Metrics**: Measure agent execution duration, validation times
- **Error Tracking**: Structured errors with types and severity levels
- **Artifact Discovery**: Know exactly what files were created/modified
- **State Visibility**: Monitor state machine transitions in real-time

### For Testing & CI/CD

- **Programmatic Control**: Parse exit codes and events to make decisions
- **Automated Verification**: Validate agent behavior by inspecting event stream
- **Log Aggregation**: Send events to Elasticsearch, Splunk, or CloudWatch
- **Headless Execution**: Run without a console, perfect for containerized environments

## 🔄 Migration Guide

### For Direct CLI Users

**No changes required.** Continue running Felix as before:

```powershell
# Still works exactly the same
.\.felix\felix-agent.ps1 C:\dev\MyProject -RequirementId S-0001
```

**Optional:** Use test-cli for colored output:

```powershell
# Enhanced colored rendering
.\.felix\test-cli.ps1 C:\dev\MyProject S-0001
```

### For Script Integrators

**Before v0.2 (Not Recommended):**

```powershell
# Had to parse unstructured console output
$output = & .\.felix\felix-agent.ps1 C:\dev\MyProject -RequirementId S-0001 2>&1
if ($output -match "✅.*completed") { Write-Host "Success" }
```

**After v0.2 (Recommended):**

```powershell
# Parse structured NDJSON events
$events = & .\.felix\felix-agent.ps1 C:\dev\MyProject -RequirementId S-0001 |
  Where-Object { $_ -match '^\{' } |
  ForEach-Object { $_ | ConvertFrom-Json }

$completed = $events | Where-Object { $_.type -eq 'task_completed' }
if ($completed) { Write-Host "Task completed successfully" }
```

### For Web UI Developers

1. **Spawn Felix Process**: Use language-specific process spawning (`subprocess.Popen`, `child_process.spawn`, etc.)
2. **Read Stdout Line-by-Line**: Each line is a complete NDJSON event
3. **Parse JSON**: Each line is valid JSON - parse and handle by `event.type`
4. **Display to User**: Render events in your UI (progress bars, logs, status indicators)
5. **Monitor Exit Code**: Check process exit code for final status (0=success, 1=error, 2/3=blocked)

## 📝 Configuration

### Disable Commits During Testing

```powershell
# Use -NoCommit flag to test without git commits
.\.felix\felix-agent.ps1 C:\dev\MyProject -RequirementId S-0001 -NoCommit
```

### Event Filtering

Filter events by type or component in consuming code:

```powershell
# Get only error events
$errors = $events | Where-Object { $_.type -eq 'error_occurred' }

# Get only validation events
$validation = $events | Where-Object { $_.type -match 'validation' }

# Get only logs from executor component
$executorLogs = $events |
  Where-Object { $_.type -eq 'log' -and $_.data.component -eq 'executor' }
```

## 🐛 Bug Fixes

- **Fixed:** Agent hanging when output redirected (Write-Host blocking on null console)
- **Fixed:** Console encoding issues causing hang on startup (chcp 65001)
- **Fixed:** Registration failure preventing iteration loop entry
- **Fixed:** Empty requirement_id in run_started event
- **Fixed:** Unicode character corruption in emoji-heavy output

## 🔍 Verification

The v0.2 release has been verified with:

- ✅ Agent starts and emits NDJSON events correctly
- ✅ No hanging on Write-Host blocking
- ✅ All events flow to stdout for UI consumption
- ✅ State machine transitions emit events
- ✅ Backpressure validation emits structured events
- ✅ Task completion detection working
- ✅ Requirement status detection working (skips 'done' requirements)
- ✅ Exit codes correct (0=success, 1=error, 2=backpressure blocked, 3=validation blocked)
- ✅ test-cli.ps1 consumer parses and renders events correctly
- ✅ PowerShell 5.1 and 7.x compatibility maintained

## 📚 Documentation

- **NDJSON_MIGRATION_COMPLETE.md** - Complete migration details and event catalog
- **AGENTS.md** - Updated with NDJSON event system usage
- **README.md** - Updated with v0.2 features and examples

## 🚀 What's Next (v0.3 Roadmap)

- Web UI reference implementation consuming NDJSON events
- Real-time WebSocket event streaming
- Event replay and debugging tools
- Grafana/Prometheus metrics exporters
- Docker containerization with headless execution
- REST API for agent control and monitoring

## 📦 Installation

```powershell
# Clone repository
git clone https://github.com/your-org/Felix.git
cd Felix

# Checkout v0.2.0
git checkout v0.2.0

# Run agent (same as v0.1)
.\.felix\felix-agent.ps1 C:\dev\YourProject -RequirementId YOUR-REQ-ID

# Or use test CLI consumer
.\.felix\test-cli.ps1 C:\dev\YourProject YOUR-REQ-ID
```

## 🙏 Acknowledgments

This release represents a fundamental architectural improvement that positions Felix as a true backend service. The NDJSON event streaming system enables rich UI integrations while maintaining full backward compatibility.

---

**Full Changelog:** v0.1.0...v0.2.0  
**Commit:** e9224df1737c80c1bd85ab92c07cde28dc396ba5

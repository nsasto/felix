# Felix Agent v0.5.0 Release Notes

**Release Date:** February 8, 2026  
**Type:** Major Feature Release - Interactive UI & Session Management  
**Platform:** PowerShell 5.1+ / PowerShell 7.x  
**Status:** Production-Ready CLI with Process Control

## Overview

Felix Agent v0.5.0 introduces a **fully interactive Terminal UI (TUI)** and **comprehensive session management** for tracking and controlling concurrent agent executions. This release transforms Felix from a command-line tool into an interactive development experience while maintaining full backward compatibility with scripting and automation.

Key additions include a keyboard-driven dashboard, real-time session monitoring, improved Ctrl+C handling with process tree termination, and enhanced agent configuration management.

## 🎯 Breaking Changes

**None** - All existing commands and scripts continue to work unchanged. New features are additive.

## ✨ New Features

### 1. Interactive TUI Dashboard

A fully interactive terminal UI for managing Felix operations without memorizing commands.

**Launch:** `felix tui` or `Felix.Cli.exe tui`

**Features:**

- **Real-time status overview** - Live requirement status with GitHub-style progress bar
- **Keyboard-driven navigation** - No mouse required, fast workflow
- **Context-aware menus** - Smart command suggestions based on current state
- **Integrated session monitoring** - View running agents from dashboard
- **Help system** - Built-in documentation with `?` key

**Keyboard Shortcuts:**

```
1 - Run agent           Execute a requirement
2 - Status              Show all requirement status
3 - List                List requirements with filters
4 - Validate            Run validation checks
5 - Dependencies        Show dependency tree
6 - Active Sessions     View running agents (NEW)
/ - Commands menu       Browse all available commands
? - Help                Show keyboard shortcuts
q - Quit                Exit TUI
```

**Dashboard Display:**

- ASCII art Felix banner
- Stacked progress bar showing requirement distribution
- Total requirement count
- Quick access to all major operations

**Use Cases:**

- **Quick interactions**: Launch Felix without remembering command syntax
- **Status monitoring**: Real-time view of project state
- **Learning**: Discover commands through interactive menus
- **Session management**: Monitor and control running agents

### 2. Session Management & Process Tracking

Track and control concurrent agent executions with full visibility into running processes.

**Command:** `felix procs [subcommand]`

**Subcommands:**

```powershell
felix procs              # List active sessions (default)
felix procs list         # Explicit list command
felix procs kill <id>    # Terminate a running session
```

**Session Information Displayed:**

- **Session ID** - Unique run identifier (format: `{req-id}-{timestamp}-{iteration}`)
- **Requirement** - Which requirement is being executed
- **Agent** - Which agent profile is running (claude-sonnet, codex, etc.)
- **PID** - Process ID for system-level monitoring
- **Status** - Current execution state (running, validating, etc.)
- **Duration** - How long the agent has been running

**Session Lifecycle:**

1. **Registration** - Automatic when agent starts (`.felix/sessions.json`)
2. **Tracking** - Process monitoring with PID validation
3. **Cleanup** - Automatic unregistration on normal exit or Ctrl+C
4. **Stale Detection** - Dead PIDs pruned automatically

**Session Storage:**

- File: `.felix/sessions.json`
- Format: JSON array with session objects
- Persistent across Felix CLI invocations
- Cleaned automatically (no manual maintenance)

**Session Object Schema:**

```json
{
  "session_id": "S-0001-20260208-133511-it1",
  "requirement_id": "S-0001",
  "pid": 12345,
  "agent": "claude-sonnet",
  "start_time": "2026-02-08T13:35:11Z",
  "status": "running"
}
```

**Integration:**

- **TUI Dashboard** - Press `6` to view active sessions
- **CLI** - Use `felix procs` for scripting/automation
- **Monitoring** - PIDs available for system tools (Task Manager, htop, etc.)

**Use Cases:**

- **Concurrent execution** - Run multiple agents on different requirements
- **Process control** - Kill hung or stuck processes
- **Resource monitoring** - Track CPU/memory usage by PID
- **Development** - Manage multiple test runs simultaneously

### 3. Enhanced Ctrl+C Handling

Improved signal handling with process tree termination to prevent orphaned processes.

**Improvements:**

- **Immediate response** - Ctrl+C caught immediately via Console.CancelKeyPress
- **Process tree termination** - Kills entire subprocess tree, not just parent
- **Session cleanup** - Unregisters session properly before exit
- **Handler cleanup** - Removes event handler to prevent memory leaks

**How It Works:**

```powershell
# Before (v0.4): Only killed parent process, subprocesses survived
# After (v0.5): Kills entire tree using Process.Kill($true)
```

**Technical Details:**

- Uses `$script:` scope for handler access to agent process variable
- Calls `Process.Kill($true)` for tree termination (PowerShell 7 feature)
- Fallback graceful handling for PowerShell 5.1
- Unregisters handler in finally block to prevent reentry

**Benefits:**

- No more orphaned Python/Node.js subprocesses
- Clean terminal state after cancellation
- Proper session tracking updates
- Reliable process cleanup

### 4. Agent Configuration Refactoring

Improved agent management with clearer configuration and runtime handling.

**Changes:**

- **Simplified adapter pattern** - Agent-specific logic isolated in adapters
- **Runtime validation** - Verify agent availability before execution
- **Better error messages** - Clear feedback when agents unavailable
- **OAuth setup docs** - Complete guide for Claude/Codex/Gemini (see [HOW_TO_USE.md](HOW_TO_USE.md))

**Agent Adapters:**

- `DroidAdapter` - Claude Desktop integration (MCP protocol)
- `CodexAdapter` - GitHub Copilot CLI integration
- `GeminiAdapter` - Google AI Studio integration

**Configuration:**

- Agents defined in `.felix/agents.json`
- Runtime detection of available agents
- Automatic fallback handling
- Clear error reporting

### 5. CLI Improvements

Multiple enhancements to command-line interface and user experience.

**Output Streaming:**

- Fixed real-time event streaming (no more buffering delays)
- Synchronous StreamReader for immediate output
- Proper NDJSON parsing with error recovery
- Clean format mixing between quiet/verbose modes

**Command Enhancements:**

- `Resolve-FelixExecutablePath` - Smart executable resolution (PATH, relative, absolute)
- Format options (`--format json|plain|rich`) consistently supported
- Better error handling with actionable messages
- Help command improvements with subcommand details

**Performance:**

- Improved stream reading performance
- Reduced CLI startup time
- Better memory management in long-running loops

**Compatibility:**

- PowerShell 5.1 `Join-Path` fixes (nested calls for 3+ arguments)
- Cross-platform path handling
- Consistent behavior across Windows/Linux/macOS

### 6. Documentation Updates

Comprehensive documentation for all new features.

**Updated Files:**

- **README.md** - Quick Start includes TUI and procs commands
- **HOW_TO_USE.md** - Complete TUI and session management sections
  - Interactive keyboard shortcuts documented
  - Session management workflows explained
  - Ctrl+C improvements described
  - Use cases and examples provided

**New Sections:**

- Session Management - Features, commands, lifecycle, use cases
- TUI Dashboard - Keyboard shortcuts, features, navigation
- Process Control - Ctrl+C handling, tree termination, cleanup

## 🔧 Bug Fixes

**Output Streaming:**

- Fixed buffering causing delayed output in `felix-cli.ps1`
- Resolved format mixing between quiet/verbose modes
- Restored synchronous reading after merge conflicts

**Command Execution:**

- Fixed `felix run` error handling and exit codes
- Resolved binary differences in `felix-cli.ps1`
- Fixed loop output format consistency

**PowerShell 5.1 Compatibility:**

- Fixed `Join-Path` calls for 3+ arguments (nested calls required)
- Resolved `??` null-coalescing operator usage (PS 5.1 doesn't support)
- Fixed parameter binding issues with `Export-ModuleMember`

**Process Management:**

- Resolved "ps" alias conflict (renamed command to "procs")
- Fixed parameter binding error referencing "sessions.json"
- Proper cleanup of stale session entries

## 📚 Documentation

**Quick Reference:**

```powershell
# New Commands
felix tui                           # Launch interactive TUI
felix procs                         # List active sessions
felix procs kill <session-id>       # Kill a session

# TUI Shortcuts (inside felix tui)
1-6     Quick actions
/       Commands menu
?       Help
q       Quit

# Session Management
felix procs list                    # Show all running agents
felix procs kill S-0001-...-it1     # Stop specific agent
```

**Complete Documentation:**

- [README.md](README.md) - Overview and quick start
- [HOW_TO_USE.md](HOW_TO_USE.md) - Complete usage guide with examples
- [AGENTS.md](AGENTS.md) - Operational guide for running Felix

## 🚀 Migration Guide

**From v0.2 to v0.5:**

No migration required - all existing workflows continue working unchanged.

**Optional Enhancements:**

1. **Try the TUI:**

   ```powershell
   felix tui
   # Press ? for help, explore with keyboard shortcuts
   ```

2. **Monitor sessions:**

   ```powershell
   # Start an agent in background
   Start-Job { felix run S-0001 }

   # Monitor from another terminal
   felix procs
   ```

3. **Update scripts:**

   ```powershell
   # Old: Manual process tracking
   $proc = Start-Process -PassThru ...

   # New: Automatic session tracking
   felix run S-0001  # Session auto-registered
   felix procs       # View all sessions
   ```

## 🎯 Use Cases

**Interactive Development:**

```powershell
# Launch TUI for quick interactions
felix tui

# Press 1 to run, 2 for status, 6 to monitor sessions
# No need to remember command syntax
```

**Concurrent Execution:**

```powershell
# Terminal 1: Backend work
felix run S-0010

# Terminal 2: Frontend work
felix run S-0020

# Terminal 3: Monitor both
felix procs
```

**Process Control:**

```powershell
# List running agents
felix procs

# Output:
# S-0001-20260208-133511-it1  S-0001  claude-sonnet  12345  running  5m 23s

# Kill stuck agent
felix procs kill S-0001-20260208-133511-it1
```

**Automation with Monitoring:**

```powershell
# Start multiple agents
foreach ($req in "S-0001", "S-0002", "S-0003") {
    Start-Job { felix run $using:req }
}

# Monitor progress
while ((felix procs list) -match "running") {
    felix procs
    Start-Sleep 30
}
```

## 🔮 What's Next

**v0.6 - Cloud Integration (Planned):**

- Cloud-hosted agent execution
- Shared session tracking across machines
- Web-based TUI dashboard
- Multi-user collaboration

**v0.7 - Advanced Session Control (Planned):**

- Session pause/resume
- Session logs and replay
- Resource limits per session
- Session scheduling

## 📦 Installation

**PowerShell CLI:**

```powershell
# Clone repository
git clone https://github.com/yourusername/felix.git
cd felix

# Install to PATH
.\scripts\install-cli.ps1

# Restart PowerShell
felix tui
```

**C# CLI (Recommended):**

```powershell
# Build and install
.\scripts\install-cli-csharp.ps1

# Use directly
felix tui
felix procs
```

## 🐛 Known Issues

None reported in this release.

## 👥 Contributors

- Session management implementation
- TUI dashboard development
- Ctrl+C improvements
- Documentation updates
- Bug fixes and testing

## 📄 License

[Your license here]

---

**Full Changelog:** https://github.com/yourusername/felix/compare/v0.2...v0.5

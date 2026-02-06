# Felix CLI Executable Implementation Guide

## Document Purpose

This guide captures the current CLI architecture, maintainability considerations, and implementation notes for transitioning from PowerShell CLI to a native C# executable (`felix.exe`).

**Date Created:** 2026-02-06  
**Phase Status:** PowerShell CLI Complete ✅ | C# CLI Ready to Start  
**Related Docs:** [CLI_MIGRATION.md](CLI_MIGRATION.md), [AGENTS.md](../AGENTS.md)

---

## Current Architecture (Phase 1 Complete)

### CLI Layer Structure

```
felix.ps1 (1046 lines) - Main dispatcher
├─ Command routing (run/loop/status/list/validate/spec/version/help)
├─ Global flag parsing (--format, --verbose, --quiet, --no-stats)
├─ Subcommand handling (spec create/fix/delete)
└─ Delegates to actual scripts:
    ├─ felix-cli.ps1 (NDJSON renderer with format modes)
    ├─ felix-agent.ps1 (agent executor)
    ├─ felix-loop.ps1 (loop runner)
    ├─ core/spec-builder.ps1 (interactive spec creation)
    ├─ scripts/validate-requirement.py (validation engine)
    └─ scripts/* (other utilities)
```

### Commands Implemented

| Command                    | Purpose                            | Delegates To                     | Status |
| -------------------------- | ---------------------------------- | -------------------------------- | ------ |
| `felix run S-NNNN`         | Execute single requirement         | felix-cli.ps1 → felix-agent.ps1  | ✅     |
| `felix loop`               | Run all planned requirements       | felix-loop.ps1                   | ✅     |
| `felix status S-NNNN`      | Show requirement status            | Inline logic                     | ✅     |
| `felix list`               | List requirements by status        | Inline logic                     | ✅     |
| `felix validate S-NNNN`    | Run validation criteria            | validate-requirement.py          | ✅     |
| `felix spec create`        | Interactive spec builder           | spec-builder.ps1                 | ✅     |
| `felix spec fix`           | Align specs with requirements.json | Inline logic (Invoke-SpecFix)    | ✅     |
| `felix spec delete S-NNNN` | Remove spec and JSON entry         | Inline logic (Invoke-SpecDelete) | ✅     |
| `felix version`            | Show version info                  | Inline logic                     | ✅     |
| `felix help`               | Show usage help                    | Inline logic                     | ✅     |

### Global Flags

```powershell
--format <json|plain|rich>   # Output format (default: rich)
--verbose                     # Enable verbose logging
--quiet                       # Suppress non-essential output
--no-stats                    # Disable statistics summary
```

### Key Files

```
.felix/
├── felix.ps1                 # Main CLI dispatcher (1046 lines)
├── felix-cli.ps1             # NDJSON event renderer
├── felix-agent.ps1           # Core agent executor
├── felix-loop.ps1            # Loop runner
├── core/
│   ├── spec-builder.ps1      # Spec creation engine
│   └── *.ps1                 # Other utilities
├── prompts/
│   ├── spec-builder.md       # Spec builder LLM prompt
│   └── droid-system.md       # Agent system prompt
└── requirements.json         # Requirement registry

scripts/
├── validate-requirement.py   # Python validation engine
└── validate-requirement.ps1  # PowerShell wrapper
```

---

## Maintainability Analysis

### What Doesn't Touch CLI (90% of work)

#### 1. Prompt Updates

**No CLI changes needed**

```markdown
.felix/prompts/spec-builder.md
.felix/prompts/droid-system.md
```

- Edit markdown files directly
- Agent loads at runtime
- Zero CLI involvement

**Example workflow:**

```powershell
# Just edit the file
notepad .felix/prompts/spec-builder.md
# No CLI rebuild/restart needed
```

#### 2. Core Script Modifications

**Direct modification, CLI passes through**

```powershell
.felix/felix-agent.ps1        # Main agent logic
.felix/core/spec-builder.ps1  # Spec builder
.felix/core/*.ps1             # Other utilities
```

- CLI just routes to scripts with parameters
- Modify scripts directly as before
- CLI is transparent pass-through

**Example workflow:**

```powershell
# Fix a bug in agent
notepad .felix/felix-agent.ps1
# Test immediately
felix run S-0001
```

#### 3. Output Format Changes

**Isolated in felix-cli.ps1**

```powershell
# .felix/felix-cli.ps1
function Render-Rich { ... }
function Render-Plain { ... }
function Render-Json { ... }
```

- Change colors/styles without touching core logic
- Add new format modes easily
- Single responsibility: event rendering

**Example workflow:**

```powershell
# Change rich mode colors
notepad .felix/felix-cli.ps1
# Test immediately
felix run S-0001 --format rich
```

### What Requires CLI Changes (10% of work)

#### 1. New Commands

**Minimal registration needed**

```powershell
# 1. Add to ValidateSet (line 40)
[ValidateSet("run", "loop", "status", "NEW_COMMAND", ...)]

# 2. Add switch case (line 180)
"NEW_COMMAND" {
    & "$PSScriptRoot\scripts\new-command.ps1" @remainingArgs
    exit $LASTEXITCODE
}
```

**Effort:** 2-3 lines per command (5 minutes)  
**Benefit:** Consistent interface, automatic help docs, global flag support

#### 2. Global Flags

**Moderate effort if needed across all commands**

```powershell
# Flag parsing section (lines 50-80)
switch ($Arguments[$i]) {
    "--new-flag" {
        $NewFlag = $true
    }
}
```

**Effort:** 10-15 lines (15 minutes)  
**Benefit:** Consistent UX, unified behavior

#### 3. Subcommand Groups

**Example: `felix spec <create|fix|delete>`**

```powershell
# Subcommand routing (lines 318-430)
"spec" {
    $subcommand = $remainingArgs[0]
    switch ($subcommand) {
        "create" { Invoke-SpecCreate }
        "fix"    { Invoke-SpecFix }
        "delete" { Invoke-SpecDelete }
    }
}
```

**Effort:** 20-30 lines per command group (30 minutes)  
**Benefit:** Organized namespace, cleaner help docs

---

## Developer Workflow Impact

### Common Tasks

| Task                 | CLI Impact | Effort | Workflow                                     |
| -------------------- | ---------- | ------ | -------------------------------------------- |
| Update prompt        | None       | 0 min  | Edit `.felix/prompts/*.md` directly          |
| Fix agent bug        | None       | 0 min  | Edit `.felix/felix-agent.ps1` directly       |
| Modify spec builder  | None       | 0 min  | Edit `.felix/core/spec-builder.ps1` directly |
| Change output colors | None       | 5 min  | Edit `felix-cli.ps1` render functions        |
| Add utility script   | Low        | 5 min  | 1. Create script 2. Add switch case          |
| Add new command      | Low        | 10 min | Add ValidateSet + switch case + help text    |
| Add global flag      | Medium     | 15 min | Add parser + pass-through logic              |
| Add subcommand group | Medium     | 30 min | Create routing + help + validation           |

### Before/After Comparison

**Without CLI (direct invocation):**

```powershell
# Scattered, inconsistent patterns
powershell -File .felix\felix-agent.ps1 C:\dev\Felix -RequirementId S-0001
powershell -File .felix\felix-loop.ps1 C:\dev\Felix --max-iterations 5
py -3 scripts\validate-requirement.py S-0001
powershell -File .felix\core\spec-builder.ps1 -RepositoryPath C:\dev\Felix
```

**With CLI (unified interface):**

```powershell
# Consistent, discoverable patterns
felix run S-0001
felix loop --max-iterations 5
felix validate S-0001
felix spec create
```

### Real Example: Adding a New Command

**Scenario:** Add `felix export` command to generate HTML report

**Step 1: Create the script (95% of effort)**

```powershell
# .felix/scripts/export-report.ps1
param(
    [string]$RepoRoot,
    [string]$Format = "html",
    [string]$Output = "report.html"
)

# Your actual export logic here
# ... read requirements.json ...
# ... generate report ...
# ... save to file ...

Write-Host "Report exported to $Output" -ForegroundColor Green
```

**Step 2: Register in CLI (5% of effort)**

```powershell
# felix.ps1 line 40 - Add to ValidateSet
[ValidateSet("run", "loop", "status", "list", "validate", "spec", "export", "version", "help")]

# felix.ps1 line 180 - Add switch case
"export" {
    & "$PSScriptRoot\scripts\export-report.ps1" -RepoRoot $RepoRoot @remainingArgs
    exit $LASTEXITCODE
}

# felix.ps1 line 850 - Add to help text
Write-Host "  export [--format <html|json>] [--output <file>]  Export project report" -ForegroundColor Gray
```

**Result:**

```powershell
felix export --format html --output status.html
```

**Total effort:** 5 minutes for CLI integration, rest is your actual feature code.

---

## Critical Dependencies

### validate-requirement.py

**Status:** ✅ **Actively Used & Essential**

**Purpose:**

- Reads validation criteria from spec files
- Executes commands specified in backticks
- Verifies exit codes and expected outcomes
- Returns exit code 0 (pass) or 1 (fail)

**Usage via CLI:**

```powershell
felix validate S-0001
# ↓ Delegates to:
py -3 scripts\validate-requirement.py S-0001
```

**Implementation in felix.ps1 (lines 270-302):**

```powershell
function Invoke-Validate {
    param([string[]]$Args)

    $requirementId = $Args[0]
    $validatorScript = "$RepoRoot\scripts\validate-requirement.py"

    # Detect Python command
    $pythonCmd = "python"
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $pythonCmd = "py -3"
    }

    # Execute validator
    & $pythonCmd $validatorScript $requirementId
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "✓ Validation PASSED" -ForegroundColor Green
    } else {
        Write-Host "✗ Validation FAILED" -ForegroundColor Red
    }

    exit $exitCode
}
```

**Example validation criteria (from spec):**

```markdown
## Validation Criteria

- [ ] Backend starts: `python app/backend/main.py` (exit code 0)
- [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Tests pass: `cd app/backend && pytest` (exit code 0)
```

**Integration points:**

1. CLI command: `felix validate S-NNNN`
2. Agent workflow: Felix agent calls it after completing requirements
3. Manual testing: Developers verify specs
4. Validation-driven completion: Core to S-0005 spec

**Do NOT remove or replace without equivalent functionality.**

### requirements.json Schema

**Current schema (validated and preserved by spec utilities):**

```json
{
  "requirements": [
    {
      "id": "S-NNNN",
      "title": "S-NNNN: Requirement Title",
      "spec_path": "specs/S-NNNN-slug.md",
      "status": "planned|in_progress|done|complete|blocked",
      "priority": "low|medium|high|critical",
      "labels": ["tag1", "tag2"],
      "depends_on": ["S-NNNN"],
      "updated_at": "YYYY-MM-DD",
      "created_at": "YYYY-MM-DD",
      "commit_on_complete": true|false
    }
  ]
}
```

**Properties:**

- `spec_path`: Forward slashes, relative path from repo root
- `labels`, `depends_on`: Always arrays (even if empty or single item)
- `updated_at`: ISO date format (YYYY-MM-DD)
- `created_at`: Optional, preserved if exists
- `commit_on_complete`: Optional, defaults to false

**Spec utilities maintain:**

- ✅ Schema consistency (spec_path format)
- ✅ Property preservation (all fields retained)
- ✅ Array serialization (proper JSON arrays, not strings)
- ✅ Duplicate detection (warns on duplicate IDs)

---

## Implementation Achievements (Phase 1)

### ✅ Completed Features

1. **Command Routing**
   - 10 commands fully functional
   - Subcommand support (spec create/fix/delete)
   - Consistent error handling
   - Exit code propagation

2. **Global Flags**
   - `--format` with json/plain/rich modes
   - `--verbose` for detailed output
   - `--quiet` for silent mode
   - `--no-stats` to suppress summaries

3. **Spec Management Utilities**
   - `felix spec create`: Interactive LLM-driven spec builder
   - `felix spec fix`: Scan/validate/align specs with requirements.json
   - `felix spec delete`: Confirm and remove specs
   - Duplicate detection and warnings
   - Schema validation and preservation

4. **NDJSON Event Streaming**
   - Real-time event rendering
   - Multiple format modes
   - Color-coded output
   - Statistics tracking

5. **Validation Integration**
   - Python validator integration
   - Exit code handling
   - Pass/fail reporting

### 🎯 Quality Standards Achieved

- **Schema correctness:** spec_path, not spec_file
- **Property preservation:** All optional fields retained
- **Array handling:** Proper JSON serialization
- **Duplicate detection:** Warns on conflicting IDs
- **ASCII output:** [OK], [ERROR], [WARN] markers for consistency
- **Exit codes:** Proper propagation for scripting

---

## Lessons Learned

### PowerShell Gotchas

1. **Array Serialization**
   - `ConvertTo-Json` collapses single-item arrays to strings
   - Empty arrays become `{}` instead of `[]`
   - **Solution:** Regex post-processing in JSON output

2. **Parameter Passing**
   - Switch parameters can't be passed as strings in arrays
   - **Solution:** Use bare switches or splatting

3. **Console Detection**
   - `[Console]::IsInputRedirected` and `[Environment]::UserInteractive`
   - Critical for dual-mode operation (terminal vs programmatic)

4. **Hashtable vs PSCustomObject**
   - JSON deserialization creates immutable PSCustomObjects
   - Must convert to hashtables for modification
   - **Solution:** `Ensure-Array` helper function

5. **Regex Multiline Matching**
   - `.` doesn't match newlines by default
   - **Solution:** Use `(?s)` flag for single-line mode

**Full details:** [learnings/WORKING_WITH_PS.md](../learnings/WORKING_WITH_PS.md)

---

## Phase 2 Readiness: C# CLI

### Prerequisites Completed ✅

1. **Command interface defined** - 10 commands with clear responsibilities
2. **Flag parsing patterns** - Global flags and command-specific args
3. **NDJSON protocol** - Event format documented and implemented
4. **Validation integration** - Python validator interface stable
5. **Schema validation** - requirements.json structure locked
6. **Exit codes** - Conventions established (0=success, 1=error, 2=blocked, 3=validation_fail)

### Migration Advantages

**PowerShell CLI serves as:**

1. **Working prototype** - Test UX before committing to compiled code
2. **Specification** - Behavior fully defined and tested
3. **Compatibility layer** - Can coexist during transition
4. **Fallback** - If C# CLI fails, PowerShell version still works

**C# benefits:**

1. **Performance** - No PowerShell startup overhead (~2s saved per invocation)
2. **Distribution** - Single executable, no PowerShell/Python dependencies
3. **Cross-platform** - .NET 8 runs on Windows/Linux/macOS
4. **Type safety** - Compile-time validation
5. **Package management** - NuGet for dependencies

### Architecture Preservation

**Keep script-based core:**

```
felix.exe                     # C# CLI (new)
├─ Command routing           # Port from felix.ps1
├─ Flag parsing              # Port from felix.ps1
├─ NDJSON rendering          # Port from felix-cli.ps1
└─ Delegates to scripts:     # KEEP UNCHANGED
    ├─ felix-agent.ps1       # Core agent executor
    ├─ core/spec-builder.ps1 # Spec builder
    ├─ scripts/validate-requirement.py
    └─ prompts/*.md          # LLM prompts
```

**Why keep scripts:**

- Prompts need frequent iteration (no recompile)
- Agent logic is complex and changes often
- Python validator is cross-platform and tested
- Script modifications are faster than C# rebuilds

**C# responsibilities:**

- CLI parsing and routing
- NDJSON event consumption and rendering
- Process spawning and management
- Exit code handling
- Help/version/status commands (inline logic)

---

## Pre-Implementation Checklist

### Before Starting C# CLI:

- [ ] Review current command interface for any missing features
- [ ] Document NDJSON event schema completely
- [ ] Verify all exit codes are consistent
- [ ] Test PowerShell CLI edge cases
- [ ] Ensure Python validator is stable
- [ ] Lock requirements.json schema (no more changes)
- [ ] Create CLI integration tests
- [ ] Document script invocation patterns
- [ ] Plan backward compatibility strategy
- [ ] Set up .NET 8 project structure

### Design Decisions Needed:

1. **Distribution strategy**
   - Single-file executable vs. framework-dependent?
   - Windows-only or cross-platform first?
   - Auto-update mechanism?

2. **Configuration**
   - Keep .felix/config.json?
   - Environment variables support?
   - CLI flag precedence?

3. **Error handling**
   - Structured error output?
   - Debug mode with stack traces?
   - Log file generation?

4. **Testing**
   - Unit tests for CLI parsing?
   - Integration tests with scripts?
   - Smoke tests for all commands?

5. **Installation**
   - Global PATH installation?
   - Per-project .felix/bin?
   - Installer script?

---

## Recommendation

### Keep PowerShell CLI Active

**The CLI layer adds minimal complexity (5-10% overhead) for significant benefits:**

✅ **Unified user experience** - Consistent interface across all commands  
✅ **Discoverable** - `felix help` shows everything  
✅ **Scriptable** - Exit codes and formats for automation  
✅ **Testable** - Single entry point for integration tests  
✅ **Future-proof** - Easy migration to C# when ready

**Complexity breakdown:**

- 90% of changes don't touch CLI (prompts, scripts, logic)
- 10% requires minimal registration (2-3 lines per command)
- Net benefit >> maintenance cost

### When to Migrate to C#

**Migrate when:**

- PowerShell startup time becomes bottleneck (>2s per invocation)
- Cross-platform distribution is needed (Linux/macOS users)
- Type safety and IDE support desired for CLI code
- Single-file distribution required (no dependencies)
- Team is comfortable with C# development

**Don't migrate if:**

- Only you use Felix locally
- Quick iteration on CLI features is priority
- PowerShell performance is acceptable
- Team prefers scripting languages

**Current verdict:** PowerShell CLI is production-ready. Phase 2 (C# CLI) is optional optimization, not requirement.

---

## Next Steps & Migration Options

### Phase 1 Status: ✅ COMPLETE

**What we've built:**

- 10 CLI commands with consistent interface
- 3 spec subcommands (create/fix/delete)
- Global flags and format modes
- Schema-aligned utilities with property preservation
- Duplicate detection and validation
- Comprehensive documentation

**What's working:**

```bash
felix run S-0001              # Execute requirement
felix loop                    # Run all planned
felix status S-0001           # Check status
felix list --status planned   # Filter by status
felix validate S-0001         # Run validation
felix spec create             # Interactive builder
felix spec fix                # Align specs
felix spec delete S-0001      # Remove spec
```

**Ready to move forward!**

---

## Strategic Options Analysis

### Option A: Repository Hygiene 🧹

**Quick cleanup before moving forward**

**Tasks:**

- Fix 3 duplicate spec files (S-0021, S-0022, S-0023)
- Run `felix spec fix` to clean requirements.json
- Commit clean state to feature/cli branch
- Archive or clean old runs/ folders
- Update any stale documentation

**Effort:** 1-2 hours  
**Value:** Clean foundation for next phase  
**Risk:** Low  
**Recommendation:** Do this first regardless of next choice

**Commands to run:**

```bash
# Rename or remove duplicate specs
git mv specs/S-0021-windows-tray-manager.md specs/S-0056-windows-tray-manager.md
git mv specs/S-0022-windows-tray-remote-enhancements.md specs/S-0057-tray-remote-enhancements.md
git mv specs/S-0023-tray-manager-ui-modernization.md specs/S-0058-tray-ui-modernization.md

# Realign requirements.json
felix spec fix

# Commit clean state
git add .
git commit -m "Clean up duplicate specs and realign requirements.json"
```

---

### Option B: Phase 2 - C# CLI (felix.exe) 🚀

**Build native executable as thin wrapper over felix.ps1**

**Architecture:**

```
felix.exe (C#)
    ↓ System.CommandLine parsing & validation
    ↓ calls: pwsh -File felix.ps1 <command> <args>
    ↓ streams output
    ↓ exits with same code
    ↓
felix.ps1 (PowerShell) ← UNCHANGED
    ↓ existing routing logic
    ↓ delegates to felix-agent.ps1, spec-builder.ps1, etc.
```

**Goals:**

- Create .NET 8 console application (~200 lines)
- Use System.CommandLine for argument parsing
- Call felix.ps1 for all actual work (no logic duplication)
- Single-file executable distribution
- Better tab completion and help text

**Benefits:**

- ⚡ ~2s faster per invocation (no PowerShell startup for parsing)
- 📦 Single-file distribution (.exe feels more professional)
- 🔍 Better discoverability (native help, tab completion)
- 🔒 Argument validation before calling PowerShell
- 🌍 Cross-platform potential (.NET 8 runs on Windows/Linux/macOS)

**Critical Design Decision:**

✅ **felix.exe calls felix.ps1** (thin wrapper approach)
❌ NOT calling felix-agent.ps1 directly (avoids logic duplication)

This keeps felix.ps1 as single source of truth for all command routing and business logic.

**Prerequisites (all ✅):**

- [x] Command interface defined and tested (felix.ps1 working)
- [x] Flag parsing patterns established
- [x] Exit code conventions established
- [x] All 11 commands documented

**Implementation phases:**

1. **Project setup** (Day 1: 2-3 hours)
   - Create .NET 8 console app in src/Felix.Cli
   - Add System.CommandLine package
   - Set up build configuration

2. **Command definitions** (Day 2-3: 1-2 days)
   - Define all 11 commands with System.CommandLine
   - Add arguments and options with validation
   - Implement ExecutePowerShell helper
   - Test each command delegates correctly

3. **Build and package** (Day 4: 4-6 hours)
   - Configure single-file publish
   - Output to .felix/bin/Felix.Cli.exe
   - Test with real requirements
   - Verify exit codes match felix.ps1

4. **Installation script** (Day 5: 2-3 hours)
   - Create install-cli-csharp.ps1
   - Add to PATH configuration
   - Generate tab completion scripts
   - Update documentation

5. **Testing** (Day 6-7: 1-2 days)
   - Behavior validation (output matches felix.ps1)
   - Exit code validation
   - All commands and flags
   - Error handling

6. **Documentation** (Day 8: 4-6 hours)
   - Update HOW_TO_USE.md
   - Create CLI_EXEC_PLAN.md
   - Document coexistence strategy
   - Migration guide

**Effort:** 1 week (5-7 days)  
**Value:** High (performance, distribution, professional UX)  
**Risk:** Low (felix.ps1 remains functional fallback)  
**Recommendation:** Do this for better performance and distribution

**Detailed implementation guide:** See [CLI_EXEC_PLAN.md](CLI_EXEC_PLAN.md)

---

### Option C: TUI/GUI Integration 🎨

**Build interactive visual layer for Felix**

**Goals:**

- Real-time agent monitoring dashboard
- Interactive spec builder with forms
- Live status updates and progress
- Visual requirement dependency graph

**Options:**

1. **Terminal UI (TUI)** - Spectre.Console, Terminal.Gui
2. **Web UI** - Existing React frontend (already built!)
3. **Desktop GUI** - Avalonia, WPF

**Benefits:**

- 👁️ Visual feedback during agent runs
- 📊 Real-time progress and statistics
- 🎯 Easier spec creation with guided forms
- 📈 Dependency visualization

**Prerequisites:**

- ✅ CLI working (can spawn processes)
- ✅ NDJSON events defined
- ✅ File-based prompt system (for TUI spec builder)
- ⚠️ Need to define TUI event protocol

**Implementation phases:**

1. **Choose framework** (1 day)
   - Evaluate Spectre.Console vs Terminal.Gui
   - Or leverage existing React frontend
   - Prototype basic layout

2. **Core dashboard** (3-5 days)
   - Live event streaming from agent
   - Status indicators
   - Progress bars
   - Log viewer

3. **Interactive spec builder** (2-3 days)
   - Form-based input
   - Real-time validation
   - Preview generation
   - Save/cancel workflows

4. **Integration** (2-3 days)
   - Connect to felix run/loop
   - File-based prompt handling
   - Error display and handling

**Effort:** 1-2 weeks  
**Value:** High (UX improvement, discoverability)  
**Risk:** Medium (new UI paradigm, event integration)  
**Recommendation:** Good if you want better UX, but existing React frontend might already cover this

**Note:** The React frontend (S-0003) might already provide most of this. Consider improving that instead of building new TUI.

---

### Option D: CLI Polish 💎

**Quick wins to improve developer experience**

**Tasks:**

1. **Tab completion** (1-2 days)
   - PowerShell completion script
   - Bash completion script
   - Install into profile
   - Test with all commands

2. **Better error messages** (1 day)
   - Contextual hints ("Did you mean...?")
   - Common mistakes guide
   - Suggest fixes for errors
   - Color-coded severity

3. **Progress indicators** (1 day)
   - Spinners for long operations
   - Progress bars for loops
   - ETA calculations
   - Cancellation support

4. **More formats** (1-2 days)
   - Markdown output mode
   - HTML report generation
   - CSV export for status/list
   - JSON Lines for streaming

5. **Documentation** (2-3 days)
   - Man pages (felix.1)
   - Command reference docs
   - Usage examples
   - Troubleshooting guide

**Effort:** 5-7 days total (can do incrementally)  
**Value:** Medium (quality of life)  
**Risk:** Low (additive changes)  
**Recommendation:** Good filler work between major features

**Priority order:**

1. Tab completion (highest ROI)
2. Better error messages
3. Progress indicators
4. Documentation
5. More formats

---

### Option E: Core Features 🔧

**Stop working on CLI, build actual Felix features**

**Available specs to implement:**

- S-0054+: New requirement specifications
- Agent capability improvements
- Plugin/extension system
- Better validation framework
- Enhanced artifact generation

**Rationale:**

- CLI is fully functional now
- Phase 1 complete and tested
- Time to deliver business value
- Build features users actually need

**Effort:** Varies by feature  
**Value:** High (new capabilities)  
**Risk:** Low (working on product features)  
**Recommendation:** Do this if CLI meets current needs

**Approach:**

```bash
# Create new spec
felix spec create

# Implement requirement
felix run S-NNNN

# Validate
felix validate S-NNNN
```

---

### Option F: Merge to features/cloud 🎯

**Ship Phase 1 and close the CLI enhancement cycle**

**Tasks:**

1. Final testing of all commands
2. Update documentation
3. Merge feature/cli into features/cloud (active dev branch)
4. Write release notes
5. Tag release (v0.4.0-cli?)

**What gets shipped:**

- 10 CLI commands fully functional
- Spec management utilities
- Schema alignment tools
- NDJSON event streaming
- Comprehensive documentation

**Effort:** 1-2 days  
**Value:** High (milestone completion)  
**Risk:** Low (already tested)  
**Recommendation:** Do this to mark Phase 1 complete

**Steps:**

```bash
# Final cleanup on feature/cli
felix spec fix
git add .
git commit -m "Final Phase 1 cleanup"
git push origin feature/cli

# Merge to features/cloud (active dev branch)
git checkout features/cloud
git merge feature/cli
git tag v0.4.0-cli -m "Phase 1: PowerShell CLI Complete"
git push origin features/cloud --tags
```

---

## Recommended Path Forward

### 🎯 Immediate Next Steps (This Week)

**Day 1-2: Option A - Repository Hygiene**

- Fix duplicate specs
- Run `felix spec fix`
- Commit clean state
- **Goal:** Clean foundation

**Day 3-5: Option F - Merge to features/cloud**

- Final testing
- Update docs
- Merge to features/cloud
- Tag v0.4.0-cli
- **Goal:** Ship Phase 1

### 🚀 Short-term Options (Next 2 Weeks)

**Choose ONE based on priority:**

1. **If performance/distribution matters:** Option B (C# CLI)
   - Best for multi-user deployment
   - Faster invocation times
   - Professional distribution

2. **If UX matters most:** Option C (TUI/GUI)
   - Better visibility during runs
   - Easier spec creation
   - Visual feedback

3. **If quick wins desired:** Option D (CLI Polish)
   - Tab completion
   - Better errors
   - Nice-to-haves

4. **If features are priority:** Option E (Core Features)
   - Build actual product capabilities
   - Implement pending specs
   - Deliver user value

### 📊 Decision Matrix

| Option       | Effort | Value  | Risk   | User Impact | Dev Impact |
| ------------ | ------ | ------ | ------ | ----------- | ---------- |
| A - Cleanup  | Low    | Medium | Low    | None        | High       |
| B - C# CLI   | High   | High   | Medium | Medium      | High       |
| C - TUI/GUI  | High   | High   | Medium | High        | Medium     |
| D - Polish   | Medium | Medium | Low    | Medium      | High       |
| E - Features | Varies | High   | Low    | High        | Medium     |
| F - Merge    | Low    | High   | Low    | High        | Medium     |

### 💡 My Recommendation

**Do this sequence:**

1. **A + F first** (3-4 days)
   - Clean up repository
   - Ship Phase 1 to features/cloud (active dev branch)
   - Close the CLI enhancement cycle
   - Celebrate milestone! 🎉

2. **Then choose ONE:**
   - **E (Core Features)** if CLI already meets needs
   - **B (C# CLI)** if distributing to others
   - **D (Polish)** if staying in CLI space but want quick wins

**Reasoning:**

- Phase 1 is functionally complete
- Diminishing returns on more CLI work
- Time to deliver user-facing features
- Can always come back to C# CLI later

**Your call!** What feels most valuable right now?

---

## Branch Strategy Note

**Current workflow:**

- `feature/cli` - CLI development branch (where we are now)
- `features/cloud` - Active dev branch (merge target)
- `main` - Production branch (eventual target)

**Recommended flow:**

```bash
feature/cli → features/cloud → main
```

This allows CLI enhancements to integrate with cloud features before production release.

---

## References

- [CLI_MIGRATION.md](CLI_MIGRATION.md) - Full migration plan and implementation details
- [AGENTS.md](../AGENTS.md) - How to operate the system, validation docs
- [learnings/WORKING_WITH_PS.md](../learnings/WORKING_WITH_PS.md) - PowerShell gotchas and solutions
- [.felix/felix.ps1](../.felix/felix.ps1) - Current CLI implementation
- [scripts/validate-requirement.py](../scripts/validate-requirement.py) - Validation engine

---

**Document Status:** Complete and ready for Phase 2 planning  
**Last Updated:** 2026-02-06  
**Maintainer:** Development team

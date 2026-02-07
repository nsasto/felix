# Multi-Agent Support - Comprehensive Guide

## Overview

Felix supports multiple LLM coding agents through an **adapter pattern** that normalizes differences in CLI interfaces, output formats, and completion signals. This allows seamless switching between Droid, Claude Code, Codex CLI, and Gemini CLI while maintaining Felix's Planning → Building → Validating workflow.

## Architecture

### Core Components

1. **Agent Profiles** (`.felix/agents.json`)
   - Registry of available agents with metadata
   - Each profile specifies: ID, name, executable, adapter type, CLI args
   - Current configuration: 4 agents (Droid, Claude, Codex, Gemini)

2. **Agent Adapters** (`.felix/core/agent-adapters.ps1`)
   - PowerShell classes that handle agent-specific behavior
   - Each adapter implements: `FormatPrompt()`, `ParseResponse()`, `DetectCompletion()`, `BuildArgs()`
   - Loaded dynamically based on profile's `adapter` field

3. **Executor Integration** (`.felix/core/executor.ps1`)
   - `Invoke-AgentExecution` loads correct adapter
   - Formats prompts before piping to agent
   - Parses responses to detect completion signals
   - Returns structured data for workflow decisions

4. **Configuration** (`.felix/config.json`)
   - `agent.agent_id` field selects active agent (0-3)
   - Modified by `felix agent use <id>` command
   - Persistent across Felix runs

### Data Flow

```
User Command (felix run S-0001)
    ↓
felix.ps1 → felix-cli.ps1 → agent-state.ps1
    ↓
executor.ps1: Invoke-AgentExecution
    ↓
1. Load agent profile from agents.json
2. Get-AgentAdapter (loads correct adapter class)
3. adapter.FormatPrompt(prompt) → formatted prompt
4. adapter.BuildArgs(config) → CLI arguments
5. Execute: formattedPrompt | <executable> <args>
6. adapter.ParseResponse(output) → structured result
7. Return { Output, Duration, Parsed }
    ↓
agent-state.ps1: Check Parsed.IsComplete, Parsed.NextMode
    ↓
Transition: planning → building OR building → complete
```

## Agent Profiles

### Droid (Factory.ai) - ID 0

**Profile:**

```json
{
  "id": 0,
  "name": "droid",
  "adapter": "droid",
  "executable": "droid",
  "args": ["exec", "--skip-permissions-unsafe"],
  "description": "Factory.ai Droid - Fast, reliable, uses XML completion signals"
}
```

**Characteristics:**

- **Authentication:** API key via `FACTORY_API_KEY` environment variable
- **Output Format:** Plain text with XML tags
- **Completion Signals:** `<promise>PLANNING_COMPLETE</promise>`, `<promise>ALL_REQUIREMENTS_MET</promise>`
- **Strengths:** Fast, low latency, stable XML parsing
- **Weaknesses:** Requires API key management

**Adapter Behavior:**

- `FormatPrompt()`: Pass through (no formatting needed)
- `ParseResponse()`: Regex match `(?s)<promise>\s*(PLANNING_COMPLETE|ALL_REQUIREMENTS_MET)\s*</promise>`
- `DetectCompletion()`: Boolean check for promise tags
- `BuildArgs()`: Return args from profile directly

### Claude (Anthropic) - ID 1

**Profile:**

```json
{
  "id": 1,
  "name": "claude",
  "adapter": "claude",
  "executable": "claude",
  "args": ["-p", "--model", "sonnet", "--output-format", "text"],
  "description": "Anthropic Claude Code - Excellent reasoning, OAuth auth"
}
```

**Characteristics:**

- **Authentication:** OAuth via `claude auth login` (one-time setup)
- **Output Format:** JSON or text (configurable)
- **Completion Signals:** JSON `{"status": "complete"}` or text markers "planning complete"
- **Strengths:** Excellent reasoning, strong code quality, OAuth (no API keys)
- **Weaknesses:** May be slower than Droid

**Adapter Behavior:**

- `FormatPrompt()`: Pass through (accepts plain text in `-p` mode)
- `ParseResponse()`: Try JSON parsing first, fallback to regex `(?i)(planning\s+complete|all\s+tasks?\s+complete)`
- `DetectCompletion()`: Check JSON `status: complete` or text patterns
- `BuildArgs()`: Ensure `--output-format text` is present

**Setup:**

```bash
# One-time OAuth setup
claude auth login

# Test
claude --version
```

### Codex (OpenAI) - ID 2

**Profile:**

```json
{
  "id": 2,
  "name": "codex",
  "adapter": "codex",
  "executable": "codex",
  "args": ["-C", ".", "-s", "workspace-write", "-a", "never"],
  "description": "OpenAI Codex CLI - Diff-based workflow, OAuth auth"
}
```

**Characteristics:**

- **Authentication:** OpenAI OAuth via `codex auth` (one-time setup)
- **Output Format:** Diff-based, plain text
- **Completion Signals:** "Applied N changes", "No changes needed", "committed"
- **Strengths:** Diff-based workflow, strong at code transformations, OAuth
- **Weaknesses:** Less structured output, harder to parse completion

**Adapter Behavior:**

- `FormatPrompt()`: Pass through (stdin mode)
- `ParseResponse()`: Regex `(?i)(applied\s+\d+\s+change|no\s+changes?\s+needed|complete)`
- `DetectCompletion()`: Match "applied", "committed", "no changes needed"
- `BuildArgs()`: Return args from profile (includes `-C .` for workspace context)

**Setup:**

```bash
# One-time OAuth setup
codex auth

# Test
codex --version
```

### Gemini (Google) - ID 3

**Profile:**

```json
{
  "id": 3,
  "name": "gemini",
  "adapter": "gemini",
  "executable": "gemini",
  "args": [
    "-m",
    "auto",
    "--approval-mode=auto_edit",
    "--output-format",
    "json"
  ],
  "description": "Google Gemini CLI - JSON streaming, OAuth auth"
}
```

**Characteristics:**

- **Authentication:** Google OAuth via `gemini auth login` (one-time setup)
- **Output Format:** JSON streaming (newline-delimited)
- **Completion Signals:** JSON `{"phase_complete": true}`, `{"status": "done"}`
- **Strengths:** JSON streaming, structured output, OAuth
- **Weaknesses:** May require careful stream parsing

**Adapter Behavior:**

- `FormatPrompt()`: Pass through (accepts plain text)
- `ParseResponse()`: Try JSON parsing `phase_complete: true`, fallback to regex `(?i)(phase\s+complete|all\s+done)`
- `DetectCompletion()`: Check JSON fields or text patterns
- `BuildArgs()`: Ensure `--output-format json` is present

**Setup:**

```bash
# One-time OAuth setup
gemini auth login

# Test
gemini --version
```

## Usage

### Listing Agents

```bash
felix agent list
```

**Output:**

```
Available Agents:

* ID: 0 - droid
  Executable: droid
  Adapter: droid
  Description: Factory.ai Droid - Fast, reliable, uses XML completion signals

  ID: 1 - claude
  Executable: claude
  Adapter: claude
  Description: Anthropic Claude Code - Excellent reasoning, OAuth auth

  ID: 2 - codex
  Executable: codex
  Adapter: codex
  Description: OpenAI Codex CLI - Diff-based workflow, OAuth auth

  ID: 3 - gemini
  Executable: gemini
  Adapter: gemini
  Description: Google Gemini CLI - JSON streaming, OAuth auth
```

**Legend:**

- `*` indicates currently active agent
- ID: Numeric identifier (used in `agent use` command)
- Name: Human-readable name (also usable in `agent use`)

### Checking Current Agent

```bash
felix agent current
```

**Output:**

```
Current Agent:
  ID: 0
  Name: droid
  Executable: droid
  Adapter: droid
  Description: Factory.ai Droid - Fast, reliable, uses XML completion signals
```

### Switching Agents

```bash
# Switch by ID
felix agent use 1

# Switch by name
felix agent use claude
```

**Process:**

1. Validates agent exists in agents.json
2. Checks if executable is in PATH
3. Warns if not found, prompts to continue
4. Updates `.felix/config.json` with new `agent.agent_id`
5. Confirms switch

**Output:**

```
Switched to agent: claude (ID: 1)
```

**If executable not found:**

```
Executable 'claude' not found in PATH
Install the agent CLI before using it:
  npm install -g @anthropic-ai/claude-code
Continue anyway? (y/N):
```

### Testing Agents

```bash
# Test by ID
felix agent test 1

# Test by name
felix agent test claude
```

**Checks:**

1. **Executable exists** - Verifies CLI is in PATH
2. **Version check** - Runs `--version` (if supported)

**Output:**

```
Testing agent: claude

[1/2] Checking executable... OK
      Path: C:\Users\...\AppData\Roaming\npm\claude.cmd
[2/2] Checking version... OK
      claude-code v1.2.3

Agent test passed!
```

## Decision Tree: Which Agent to Use?

### Use **Droid** when:

- ✅ You need **maximum speed** (lowest latency)
- ✅ You have **FACTORY_API_KEY** set up
- ✅ You want **reliable XML-based completion detection**
- ✅ You're working on **well-scoped requirements** (planning → building works well)

### Use **Claude** when:

- ✅ You need **superior reasoning** and code quality
- ✅ You prefer **OAuth** (no API key management)
- ✅ You're tackling **complex requirements** that need deeper analysis
- ✅ You value **strong documentation** generation

### Use **Codex** when:

- ✅ You need **diff-based workflow** (explicit change tracking)
- ✅ You prefer **OpenAI models** (GPT-4 based)
- ✅ You're doing **iterative refactoring** (diffs show exactly what changed)
- ✅ You want **OAuth** authentication

### Use **Gemini** when:

- ✅ You need **structured JSON output** for parsing
- ✅ You prefer **Google Cloud** ecosystem
- ✅ You're building **integrations** that consume JSON streams
- ✅ You want **OAuth** authentication

## Troubleshooting

### Agent executable not found

**Symptom:**

```
Executable 'claude' not found in PATH
```

**Solution:**
Install the agent CLI:

```bash
# Claude
npm install -g @anthropic-ai/claude-code

# Codex
npm install -g @openai/codex-cli

# Gemini
pip install google-gemini-cli

# Droid
npm install -g @factory-ai/droid-cli
```

### OAuth authentication failures

**Symptom:**

```
Error: Not authenticated. Run 'claude auth login'
```

**Solution:**
Run one-time OAuth setup:

```bash
# Claude
claude auth login

# Codex
codex auth

# Gemini
gemini auth login
```

### Completion signals not detected

**Symptom:**
Felix loops indefinitely, doesn't transition planning → building

**Cause:**
Adapter's `ParseResponse()` isn't matching agent's actual output format

**Solution:**

1. Check `runs/<run-id>/output.log` for actual agent output
2. Verify adapter regex patterns in `.felix/core/agent-adapters.ps1`
3. Update adapter to match actual output format
4. Consider adding debug logging to adapter

**Example Fix:**

```powershell
# In agent-adapters.ps1, ClaudeAdapter.ParseResponse()
Write-Host "[ADAPTER DEBUG] Output: $($output.Substring(0, [Math]::Min(200, $output.Length)))"

if ($output -match '(?i)(planning\s+complete|ready\s+to\s+build)') {
    Write-Host "[ADAPTER DEBUG] Matched planning complete"
    $result.IsComplete = $true
    $result.NextMode = "building"
}
```

### Wrong agent profile arguments

**Symptom:**
Agent fails with "Unknown option" or similar CLI errors

**Cause:**
`args` array in agents.json doesn't match agent's actual CLI interface

**Solution:**

1. Check agent's help: `<executable> --help`
2. Update `.felix/agents.json` with correct arguments
3. Restart Felix (no recompile needed, JSON is loaded dynamically)

**Example:**

```json
{
  "id": 1,
  "name": "claude",
  "args": ["-p", "--model", "sonnet", "--output-format", "text"]
  // Changed from ["--interactive"] to match actual CLI
}
```

### Adapter not loading

**Symptom:**

```
Failed to load adapter: claude
```

**Cause:**

1. `adapter` field in agents.json doesn't match adapter class name
2. Typo in adapter type
3. Agent-adapters.ps1 not imported correctly

**Solution:**

1. Verify `.felix/agents.json` has correct `"adapter": "claude"` field
2. Check adapter type in `Get-AgentAdapter` switch statement matches
3. Ensure `.felix/core/executor.ps1` imports agent-adapters.ps1:
   ```powershell
   . "$PSScriptRoot\agent-adapters.ps1"
   ```

## Adding New Agents

### Step 1: Add Profile to agents.json

```json
{
  "id": 4,
  "name": "my-agent",
  "adapter": "myagent",
  "executable": "my-agent-cli",
  "args": ["--workspace", ".", "--mode", "auto"],
  "working_directory": ".",
  "environment": {},
  "description": "My custom agent"
}
```

### Step 2: Create Adapter Class

In `.felix/core/agent-adapters.ps1`:

```powershell
class MyAgentAdapter {
    [string] FormatPrompt([string]$prompt) {
        # Transform prompt if needed
        return $prompt
    }

    [hashtable] ParseResponse([string]$output) {
        $result = @{
            Output = $output
            IsComplete = $false
            NextMode = $null
            Error = $null
        }

        # Parse completion signals
        if ($output -match 'DONE') {
            $result.IsComplete = $true
            $result.NextMode = "complete"
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        return $output -match 'DONE'
    }

    [string[]] BuildArgs([hashtable]$config) {
        return $config.args
    }
}
```

### Step 3: Register in Factory

In `.felix/core/agent-adapters.ps1`, add case to `Get-AgentAdapter`:

```powershell
function Get-AgentAdapter {
    param([Parameter(Mandatory = $true)][string]$AdapterType)

    switch ($AdapterType.ToLower()) {
        "droid" { return [DroidAdapter]::new() }
        "claude" { return [ClaudeAdapter]::new() }
        "codex" { return [CodexAdapter]::new() }
        "gemini" { return [GeminiAdapter]::new() }
        "myagent" { return [MyAgentAdapter]::new() }  # NEW
        default {
            Write-Error "Unknown adapter type: $AdapterType"
            return $null
        }
    }
}
```

### Step 4: Test

```bash
felix agent list       # Should show new agent
felix agent test 4     # Verify executable works
felix agent use 4      # Switch to new agent
felix run S-0001       # Test with real requirement
```

## Configuration Reference

### agents.json Schema

```json
{
  "agents": [
    {
      "id": 0, // Unique numeric ID
      "name": "agent-name", // Human-readable name
      "adapter": "adapter-type", // Adapter class to load
      "executable": "cli-command", // Executable name/path
      "args": ["--flag", "value"], // CLI arguments array
      "working_directory": ".", // Execution directory
      "environment": {}, // Environment variables
      "description": "Description" // Help text
    }
  ]
}
```

### config.json Agent Section

```json
{
  "agent": {
    "agent_id": 0, // Active agent ID (0-3 currently)
    "max_iterations": 20 // Loop safety limit
  }
}
```

**Modified by:** `felix agent use <id>`

## Best Practices

### 1. Test Before Switching

Always run `felix agent test <name>` before using a new agent:

```bash
felix agent test claude
felix agent use claude
```

### 2. One-Time OAuth Setup

Run authentication once per machine:

```bash
# Do this once
claude auth login
codex auth
gemini auth login

# Then use freely
felix agent use claude
felix run S-0001
```

### 3. Keep API Keys Secure

For Droid (API key based):

```bash
# Set in environment (not committed to repo)
$env:FACTORY_API_KEY = "your-key-here"

# Or add to Windows environment variables permanently
```

### 4. Monitor Completion Detection

Watch for agents getting stuck in planning/building loops:

```bash
# Check actual output
Get-Content runs\<run-id>\output.log

# Verify completion signals are present
```

### 5. Adapter Debugging

Add temporary debug logging to adapters during development:

```powershell
[hashtable] ParseResponse([string]$output) {
    Write-Host "[DEBUG] Output length: $($output.Length)" -ForegroundColor Cyan
    Write-Host "[DEBUG] First 100 chars: $($output.Substring(0, [Math]::Min(100, $output.Length)))" -ForegroundColor Gray

    # ... parsing logic ...
}
```

### 6. Fallback Strategy

If an agent fails, switch to known-good agent:

```bash
# Claude not working? Fall back to Droid
felix agent use droid
felix run S-0001
```

## Performance Characteristics

| Agent  | Latency     | Token Speed | Auth Overhead        | Reliability |
| ------ | ----------- | ----------- | -------------------- | ----------- |
| Droid  | ⚡⚡⚡ Low  | Fast        | None (after key set) | High        |
| Claude | ⚡⚡ Medium | Medium      | OAuth (one-time)     | High        |
| Codex  | ⚡⚡ Medium | Fast        | OAuth (one-time)     | Medium      |
| Gemini | ⚡⚡ Medium | Medium      | OAuth (one-time)     | Medium      |

**Notes:**

- **Latency:** Time to first token
- **Token Speed:** Generation throughput
- **Auth Overhead:** Per-request authentication cost
- **Reliability:** Completion signal detection accuracy

## Examples

### Example 1: Switch from Droid to Claude

```bash
# Current agent
C:\dev\Felix> felix agent current
Current Agent:
  ID: 0
  Name: droid

# Test Claude first
C:\dev\Felix> felix agent test claude
Testing agent: claude
[1/2] Checking executable... OK
[2/2] Checking version... OK
Agent test passed!

# Switch
C:\dev\Felix> felix agent use claude
Switched to agent: claude (ID: 1)

# Run requirement
C:\dev\Felix> felix run S-0001
```

### Example 2: List and Switch by Name

```bash
C:\dev\Felix> felix agent list

Available Agents:
* ID: 0 - droid
  ID: 1 - claude
  ID: 2 - codex
  ID: 3 - gemini

C:\dev\Felix> felix agent use gemini
Switched to agent: gemini (ID: 3)
```

### Example 3: Test All Agents

```bash
C:\dev\Felix> felix agent test droid; felix agent test claude; felix agent test codex; felix agent test gemini

# Review results, install any missing CLIs
```

## Related Documentation

- [SWITCHING_AGENTS.md](SWITCHING_AGENTS.md) - Quick start guide for switching agents
- [HOW_TO_USE.md](../HOW_TO_USE.md) - General Felix usage
- [AGENT_CONFIG_EXPLAINED.md](AGENT_CONFIG_EXPLAINED.md) - Agent configuration deep dive
- [WORKING_WITH_PS.md](../learnings/WORKING_WITH_PS.md) - PowerShell patterns and gotchas

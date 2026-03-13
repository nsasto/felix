# Switching Agents - Quick Start Guide

This guide shows you how to set up and switch between different LLM agents in Felix.

## Available Agents

Felix supports 4 agents:

1. **Droid** (Factory.ai) - Fast, API key auth
2. **Claude** (Anthropic) - Best reasoning, OAuth
3. **Codex** (OpenAI) - Diff-based, OAuth
4. **Gemini** (Google) - JSON streaming, OAuth

## One-Time Setup

### Install Agent CLIs

Install the agent CLIs you want to use:

```bash
# Droid (npm)
npm install -g @factory-ai/droid-cli

# Claude (npm)
npm install -g @anthropic-ai/claude-code

# Codex (npm)
npm install -g @openai/codex-cli

# Gemini (pip)
pip install google-gemini-cli
```

### Authentication

#### Droid (API Key)

Set environment variable:

```powershell
# PowerShell (temporary)
$env:FACTORY_API_KEY = "your-api-key-here"

# PowerShell (permanent)
[Environment]::SetEnvironmentVariable("FACTORY_API_KEY", "your-key", "User")
```

#### Claude (OAuth)

```bash
claude auth login
# Opens browser, complete OAuth flow
```

#### Codex (OAuth)

```bash
codex auth
# Opens browser, complete OAuth flow
```

#### Gemini (OAuth)

```bash
gemini auth login
# Opens browser, complete OAuth flow
```

## Switching Agents

### Step 1: List Available Agents

```bash
felix agent list
```

Output:

```
Available Agents:

* ID: ag_ee77df894 - claude
  Provider: claude
  Executable: claude
  Adapter: claude

  ID: ag_16fffb5a4 - codex
  Provider: codex
  Executable: codex
  Adapter: codex

  ID: ag_39535ce5e - droid
  Executable: droid
  Adapter: droid

  ID: ag_7a5702bda - gemini
  Executable: gemini
  Adapter: gemini
```

The `*` shows which agent is currently active.

### Step 2: Test Agent

Before switching, verify the agent works:

```bash
# Test by name
felix agent test claude

# Test by ID
felix agent test ag_ee77df894
```

Output:

```
Testing agent: claude

[1/2] Checking executable... OK
      Path: C:\Users\...\AppData\Roaming\npm\claude.cmd
[2/2] Checking version... OK
      claude-code v1.2.3

Agent test passed!
```

### Step 3: Switch

```bash
# Switch by name
felix agent use claude

# Switch by ID
felix agent use ag_ee77df894

# Or select interactively
felix agent use
```

Output:

```
Switched to agent: claude (ID: ag_ee77df894)
```

### Step 4: Verify

```bash
felix agent current
```

Output:

```
Current Agent:
  ID: ag_ee77df894
  Name: claude
  Executable: claude
  Adapter: claude
  Provider: claude
```

### Step 5: Run

Now use Felix normally:

```bash
felix run S-0001
felix loop --max-iterations 5
felix status S-0001
```

Felix will use your selected agent for all operations.

## Quick Reference

```bash
# List agents
felix agent list

# Check current agent
felix agent current

# Test agent
felix agent test <id|name>

# Switch agent
felix agent use [id|name]
felix agent use
```

## Examples

### Example 1: Switch to Claude

```bash
felix agent test claude
felix agent use claude
felix run S-0001
```

### Example 2: Switch Back to Droid

```bash
felix agent use droid
felix agent current
```

### Example 3: Try All Agents

```bash
# Test each
felix agent test droid
felix agent test claude
felix agent test codex
felix agent test gemini

# Pick one
felix agent use claude
```

## Troubleshooting

### "Executable not found"

Install the CLI:

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

### "Not authenticated"

Run OAuth setup:

```bash
# Claude
claude auth login

# Codex
codex auth

# Gemini
gemini auth login
```

For Droid, set API key:

```powershell
$env:FACTORY_API_KEY = "your-key"
```

### Agent Stuck in Loop

Switch to a different agent:

```bash
felix agent use droid
felix run S-0001
```

## When to Use Each Agent

**Use Droid when:**

- You need maximum speed
- You have an API key set up

**Use Claude when:**

- You need best code quality
- You're tackling complex requirements

**Use Codex when:**

- You want explicit diffs of changes
- You prefer OpenAI models

**Use Gemini when:**

- You want structured JSON output
- You prefer Google Cloud

## Next Steps

- See [MULTI_AGENT_SUPPORT.md](MULTI_AGENT_SUPPORT.md) for architecture details
- See [HOW_TO_USE.md](../HOW_TO_USE.md) for Felix basics
- See [AGENT_CONFIG_EXPLAINED.md](AGENT_CONFIG_EXPLAINED.md) for configuration reference

# Understanding Felix Agents: Local vs Remote

**Quick version:** Felix has two separate agent models that solve different problems. Understanding when to use each will save you hours of confusion.

## The Two Worlds

Felix agents exist in two completely different contexts:

### 1. Local CLI Agents (What You Run)

These are the executables on your machine:
- `droid` (Factory.ai CLI)
- `claude` (Anthropic CLI)
- `codex` (OpenAI CLI)
- `gemini` (Google CLI)

**Configuration:** `.felix/agents.json` in your repository  
**Purpose:** Tell Felix *how to launch* these CLIs  
**Scope:** Local machine only  

### 2. Remote Agents (What The Backend Tracks)

These are runtime registrations in the database:
- Which agents are currently running
- On which machines
- For which organizations
- With what configuration

**Configuration:** PostgreSQL database (tables: `agents`, `agent_profiles`, `machines`)  
**Purpose:** Track activity, enable collaboration, provide visibility  
**Scope:** Team-wide, server-managed  

**Here's the key insight:** These two systems are *intentionally separate*. Your local `.felix/agents.json` doesn't sync to the backend. The backend doesn't tell your CLI which agents to use.

## Why Two Systems?

### The Local Problem: "How Do I Run This Agent?"

You type `felix run S-0001`. Felix needs to know:
- Which executable to run (`droid`, `claude`, etc.)
- What arguments to pass
- What environment variables to set
- What model to use

**Solution:** Read `.felix/agents.json` and look up agent by ID.

### The Remote Problem: "What Agents Are Running Right Now?"

Your manager asks: "Which agents are working on what?"

The backend needs to know:
- Agent `0` is running on John's laptop
- Agent `1` is running on the CI server
- Agent `2` just finished on Jane's machine

**Solution:** Agents register with backend when they start, update `last_seen_at` timestamp.

## Local Configuration: `.felix/agents.json`

This file lives in your repository and defines agent presets:

```json
{
  "agents": [
    {
      "id": 0,
      "name": "droid",
      "adapter": "droid",
      "executable": "droid",
      "model": "claude-opus-4-5-20251101",
      "working_directory": ".",
      "environment": {},
      "description": "Factory.ai Droid - Fast, reliable, JSON event stream"
    },
    {
      "id": 1,
      "name": "claude",
      "adapter": "claude",
      "executable": "claude",
      "model": "sonnet",
      "working_directory": ".",
      "environment": {},
      "description": "Anthropic Claude Code - Excellent reasoning, OAuth auth"
    }
  ]
}
```

### Field Reference

| Field | Purpose | Example |
|-------|---------|---------|
| `id` | Stable identifier (never change) | `0`, `1`, `2` |
| `name` | Human-readable name | `"droid"`, `"claude"` |
| `adapter` | LLM adapter type (for backend tracking) | `"droid"`, `"claude"` |
| `executable` | Command to run | `"droid"`, `"claude"` |
| `model` | Model identifier (passed to CLI) | `"claude-opus-4-5-20251101"` |
| `working_directory` | Where to run the command | `"."` (repo root) |
| `environment` | Environment variables | `{"API_KEY": "..."}` |
| `description` | Display text | `"Factory.ai Droid - Fast..."` |

### Selecting Which Agent To Use

Edit `.felix/config.json`:

```json
{
  "agent": {
    "agent_id": 0
  }
}
```

**What happens:**
1. Felix reads `agent_id: 0` from config
2. Looks up agent `0` in `agents.json`
3. Finds `"executable": "droid"`
4. Runs: `droid <args>` with the specified model and environment

### Adding a New Local Agent

Let's say you want to add a custom agent:

```json
{
  "id": 4,
  "name": "my-custom-agent",
  "adapter": "custom",
  "executable": "python",
  "model": "gpt-4",
  "working_directory": ".",
  "environment": {
    "OPENAI_API_KEY": "sk-..."
  },
  "description": "Custom Python wrapper around GPT-4"
}
```

Then set `agent_id: 4` in `.felix/config.json`.

**Important:** IDs should be unique within your repository. Don't reuse IDs.

## Remote Agents: Backend Database

When you run Felix with sync enabled, the agent registers itself:

```
[18:51:16.212] INFO [sync] Sync enabled → http://localhost:8080
[18:51:16.431] INFO [sync] Agent registered successfully
```

**What just happened:**

```sql
-- Backend executed this
INSERT INTO agents (id, name, hostname, platform, version, 
                    adapter, executable, model, last_seen_at)
VALUES ('0', '0', 'UK2060899W2', 'windows', '0.7',
        'droid', 'droid', 'claude-opus-4-5-20251101', NOW())
ON CONFLICT (id) DO UPDATE SET
    hostname = EXCLUDED.hostname,
    platform = EXCLUDED.platform,
    last_seen_at = EXCLUDED.last_seen_at;
```

### Backend Agent Tables

**`agents` Table** - Runtime instances

```sql
CREATE TABLE agents (
    id TEXT PRIMARY KEY,              -- Agent ID (e.g., "0")
    name TEXT,                        -- Display name
    hostname TEXT,                    -- Machine hostname
    platform TEXT,                    -- "windows", "linux", "macos"
    version TEXT,                     -- Felix version
    adapter TEXT,                     -- "droid", "claude", etc.
    executable TEXT,                  -- CLI command
    model TEXT,                       -- Model identifier
    last_seen_at TIMESTAMPTZ,         -- Last heartbeat
    type TEXT DEFAULT 'cli',          -- 'cli' or 'web'
    status TEXT DEFAULT 'idle',       -- 'idle', 'working', 'offline'
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
```

**`agent_profiles` Table** - Organization templates (future)

```sql
CREATE TABLE agent_profiles (
    id UUID PRIMARY KEY,
    org_id UUID REFERENCES organizations(id),
    name TEXT,                        -- "Default Droid Setup"
    adapter TEXT,                     -- "droid"
    executable TEXT,                  -- "droid"
    model TEXT,                       -- "claude-opus-4"
    args JSONB,                       -- CLI arguments
    environment JSONB,                -- Env vars
    description TEXT,
    created_at TIMESTAMPTZ
);
```

**`machines` Table** - Physical/virtual machines

```sql
CREATE TABLE machines (
    id UUID PRIMARY KEY,
    org_id UUID REFERENCES organizations(id),
    hostname TEXT,                    -- "UK2060899W2"
    fingerprint TEXT,                 -- Hardware fingerprint
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
);
```

### Why Track Agents Remotely?

**1. Visibility**

Web UI shows:
- Which agents are active
- What they're working on
- When they last checked in

**2. Audit Trail**

Database records:
- Every run's agent_id
- Which machine it ran on
- What model was used

**3. Capacity Planning**

Queries like:
```sql
-- How many agents ran today?
SELECT COUNT(DISTINCT id) FROM agents 
WHERE last_seen_at > NOW() - INTERVAL '1 day';

-- Which models are most used?
SELECT adapter, model, COUNT(*) 
FROM agents 
GROUP BY adapter, model;
```

**4. Future: Distributed Work**

Backend can eventually:
- Assign work to idle agents
- Balance load across machines
- Manage API quotas per agent

## The Confusion Point (And How To Avoid It)

**Common mistake:** Editing backend database and expecting CLI to change.

```sql
-- This does NOT affect your local CLI
UPDATE agents SET model = 'gpt-4' WHERE id = '0';
```

Your local `.felix/agents.json` still says `claude-opus-4`. The CLI uses the local file.

**Common mistake #2:** Editing `.felix/agents.json` and expecting web UI to change.

```json
// This does NOT update the backend
{"id": 0, "model": "new-model"}
```

Backend shows old model until next run (when registration updates it).

### The Mental Model

Think of it like Git:

- **Local agents.json** = Your local repository
- **Backend database** = Remote repository
- **Agent registration** = Push (one-way, best-effort)

There's no "pull" from backend to CLI. There's no automatic sync. The local file is always the source of truth for *how to run* agents.

## Practical Scenarios

### Scenario 1: Switching Between Agents Locally

**Goal:** Try different LLMs without affecting the team.

```bash
# Edit .felix/config.json
{
  "agent": { "agent_id": 1 }  # Switch to Claude
}

# Run
felix run S-0001

# Check what ran
grep "Using agent" runs/*/output.log
# Output: Using agent: claude (ID: 1)
```

**Backend sees:** Agent `1` registered, created a run, went idle.

**Team sees:** Your run in the web UI, linked to agent `1`.

### Scenario 2: Adding Custom Agent (Local Only)

**Goal:** Use a local Python script as an agent.

```json
// .felix/agents.json
{
  "id": 5,
  "name": "my-script",
  "adapter": "custom",
  "executable": "python",
  "model": "scripts/my_agent.py",
  "working_directory": ".",
  "environment": {"PYTHONPATH": "scripts"}
}
```

```json
// .felix/config.json
{"agent": {"agent_id": 5}}
```

**Backend sees:** Agent `5` with adapter `custom`. Shows in web UI.

**Team sees:** Your custom runs. They can't replicate them (don't have `my_agent.py`), but they see what you accomplished.

### Scenario 3: Organization-Wide Agent Profile (Future)

**Goal:** IT team defines approved agent configurations.

```sql
-- Admin creates profile in backend
INSERT INTO agent_profiles (org_id, name, adapter, executable, model)
VALUES ('org-abc', 'Standard Droid', 'droid', 'droid', 'claude-opus-4');
```

**Future CLI:** Downloads profile, generates `.felix/agents.json` automatically.

**Not implemented yet**, but the database schema supports it.

### Scenario 4: Debugging "Wrong Agent Running"

**Symptom:** CLI runs `claude` but you selected `droid`.

**Debug steps:**

1. **Check config:**
   ```bash
   cat .felix/config.json | grep agent_id
   # Output: "agent_id": 0
   ```

2. **Check agents.json:**
   ```bash
   cat .felix/agents.json | jq '.agents[] | select(.id == 0)'
   # Output: {"id": 0, "name": "droid", "executable": "droid", ...}
   ```

3. **Check logs:**
   ```bash
   grep "Using agent" runs/*/output.log
   # Output: Using agent: claude (ID: 1)
   ```

**Problem found:** Config says `0`, logs show `1`. Something is overriding the config.

**Common causes:**
- Old `.felix/state.json` cached the agent
- Environment variable `FELIX_AGENT_ID` set
- Wrong working directory (reading different `.felix/config.json`)

## Best Practices

### ✅ Do This

**1. Keep agents.json in version control**

Team members share the same agent definitions:
```bash
git add .felix/agents.json
git commit -m "Add droid agent configuration"
```

**2. Use stable IDs**

Never change agent IDs. Add new ones:
```json
// Good
{"id": 0, "name": "droid-old"}
{"id": 4, "name": "droid-new"}

// Bad
{"id": 0, "name": "droid-new"}  // Changed!
```

**3. Document custom agents**

```json
{
  "id": 5,
  "name": "experimental-gpt4",
  "description": "Testing GPT-4 integration - requires OPENAI_API_KEY env var"
}
```

**4. Enable sync for visibility**

```json
// .felix/config.json
{
  "sync": {
    "enabled": true,
    "base_url": "https://felix.yourcompany.com"
  }
}
```

Team sees your runs in the web UI.

### ❌ Avoid This

**1. Editing backend database directly**

```sql
-- This won't affect CLI behavior
UPDATE agents SET executable = 'new-executable';
```

Edit `.felix/agents.json` instead.

**2. Sharing agent IDs across repositories**

```
repo-a/.felix/agents.json: {"id": 0, "name": "droid"}
repo-b/.felix/agents.json: {"id": 0, "name": "claude"}
```

When sync is enabled, both report as agent `0`. Backend can't distinguish them. Use different IDs or different database instances.

**3. Hardcoding API keys in agents.json**

```json
// Bad
{"environment": {"OPENAI_API_KEY": "sk-abc123..."}}

// Good
{"environment": {}}  // Use system environment or key vault
```

API keys in version control = security incident.

**4. Assuming sync is bidirectional**

Sync goes one way: CLI → Backend. Backend doesn't push configs back to CLI (yet).

## The Future: Unified Agent Management

Eventually, Felix will support:

**1. Backend-managed agent profiles**
- IT team defines approved configurations
- CLI downloads and applies them
- No local `.felix/agents.json` needed

**2. Agent assignment**
- Backend assigns work to idle agents
- Agents poll: "What should I work on?"
- Distributed processing

**3. Live agent status**
- Real-time heartbeat (not just registration)
- Web UI shows: "Agent 0 is on iteration 3/10"
- Kill switch from web UI

**4. API quota management**
- Backend tracks API usage per agent
- Throttle agents approaching quota
- Distribute quota across team

## Summary

**Local agents.json:**
- How to run CLIs
- Per-repository
- Source of truth for execution
- Versioned with code

**Backend database:**
- What agents ran
- Team visibility
- Audit trail
- Future: orchestration

**They're separate** by design. This keeps the CLI functional offline while enabling team collaboration when online.

**The rule:** If you're changing *how* agents work, edit `.felix/agents.json`. If you're tracking *what* agents did, check the database.

---

**Pro tip:** When in doubt, check what the logs say. Felix logs exactly which agent it's using:

```
[18:51:16.212] INFO [agent] Using agent: droid (ID: 0)
[18:51:16.261] INFO [agent] Executable: droid
```

**If the logs don't match your config, your config isn't being read.**

---

**See also:**
- [Sync Tutorial](sync/README.md) - How agent registration works
- [HOW_TO_USE.md](../HOW_TO_USE.md) - CLI usage guide
- [AGENTS.md](../AGENTS.md) - Operational guide

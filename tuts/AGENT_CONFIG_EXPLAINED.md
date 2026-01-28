# Felix Agents: The Tale of Two Files

_Or: How we learned to stop worrying and love stable identifiers_

## The Big Picture: Why Two Files?

When you first look at Felix's agent system, you might wonder: "Why do we have **two** separate `agents.json` files?" It seems redundant, right? Here's the story.

Imagine you're running a taxi dispatch system. You need two things:

1. A **directory** of all available taxis (make, model, license plate, driver info)
2. A **real-time tracker** showing which taxis are on the road RIGHT NOW (location, passenger, status)

Would you put both in the same file? Absolutely not! The directory changes rarely (when you buy/sell taxis), but the tracker updates every few seconds. They have different lifecycles, different purposes, and mixing them would be chaos.

That's exactly why Felix has:

### 1. Global Agent Configurations (`~/.felix/agents.json`)

**The Directory** - Your stable catalog of agent types

- **Location**: `~/.felix/agents.json` (your home directory)
- **Purpose**: "What agents **CAN** I run?"
- **Contains**: Executable paths, command arguments, environment setup
- **Updates**: Rarely - when you add/remove/configure agent types
- **Shared**: Across all your Felix projects
- **Version control**: Usually gitignored (contains API keys, local paths)

```json
{
  "agents": [
    {
      "id": 0,
      "name": "felix-primary",
      "executable": "droid",
      "args": ["exec", "--skip-permissions-unsafe"],
      "working_directory": ".",
      "environment": {}
    }
  ]
}
```

### 2. Project Runtime Registry (`<project>/felix/agents.json`)

**The Real-Time Tracker** - Active process monitoring

- **Location**: `<your-project>/felix/agents.json` (per-project)
- **Purpose**: "What agents **ARE** running in THIS project?"
- **Contains**: Process IDs, hostnames, heartbeats, current task
- **Updates**: Every 5 seconds (via heartbeat)
- **Isolated**: Each project has its own tracker
- **Version control**: Usually gitignored (ephemeral runtime state)

```json
{
  "agents": {
    "0": {
      "agent_id": 0,
      "agent_name": "felix-primary",
      "pid": 12345,
      "hostname": "LAPTOP-XYZ",
      "status": "active",
      "current_run_id": "S-0022",
      "started_at": "2026-01-28T10:00:00Z",
      "last_heartbeat": "2026-01-28T10:05:22Z",
      "stopped_at": null
    }
  }
}
```

## The Architecture: How It All Connects

```
┌─────────────────────────────────────────────────────────────┐
│  ~/.felix/agents.json (GLOBAL CONFIG)                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Agent ID 0: felix-primary (droid exec)              │    │
│  │ Agent ID 1: felix-worker-1 (droid exec)             │    │
│  │ Agent ID 2: claude-sonnet (claude --model sonnet)   │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │ Read on startup
                       ↓
          ┌────────────────────────────┐
          │  felix-agent.ps1           │
          │  1. Loads config.json      │
          │  2. Finds agent by ID      │
          │  3. Registers with backend │
          │  4. Sends heartbeats       │
          └────────────┬───────────────┘
                       │
                       ↓ HTTP API
          ┌────────────────────────────────────┐
          │  FastAPI Backend (Python)          │
          │  - POST /api/agents/register       │
          │  - POST /api/agents/{id}/heartbeat │
          │  - GET /api/agents                 │
          └────────────┬───────────────────────┘
                       │ Writes
                       ↓
┌─────────────────────────────────────────────────────────────┐
│  <project>/felix/agents.json (RUNTIME REGISTRY)             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ "0": {agent_id: 0, pid: 12345, status: "active"}    │    │
│  │ "1": {agent_id: 1, pid: 12346, status: "active"}    │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │ Read on demand
                       ↓
          ┌────────────────────────────┐
          │  React Frontend            │
          │  - Agent Dashboard         │
          │  - Live console            │
          │  - Status monitoring       │
          └────────────────────────────┘
```

## The Great Refactoring: From Names to IDs

### The Problem We Had

Initially, the system used **agent names** as the primary identifier. Seemed reasonable:

```json
{
  "agents": {
    "felix-primary": { "pid": 12345, ... },
    "claude-worker": { "pid": 67890, ... }
  }
}
```

But then disaster struck. Picture this:

**User**: "I want to rename 'felix-primary' to 'felix-main' to match our naming convention."  
**System**: _Renames the agent in config_  
**Runtime registry**: "Who the hell is 'felix-main'? I only know 'felix-primary'!"  
**Result**: Orphaned runtime state. Agent looks "stopped" in UI even though it's running.

### The Lesson: **Mutable vs. Immutable Identifiers**

Names are for humans. Names change. Names are **mutable**.  
IDs are for systems. IDs never change. IDs are **immutable**.

This is a fundamental principle in database design, but it applies everywhere:

- Social Security Numbers don't change even if you change your name
- GitHub repo IDs stay constant even if you rename the repo
- Database primary keys never change even if all other fields do

### The Solution: ID-Based Architecture

We refactored to use **agent ID** as the stable identifier:

```json
// Config: ID 0 can be renamed freely
{"id": 0, "name": "felix-primary"}  →  {"id": 0, "name": "felix-main"}

// Runtime: Always tracked by ID
"0": {"agent_id": 0, "agent_name": "felix-main", ...}  // ✅ Connection preserved!
```

Now renaming is safe. The ID links config to runtime state, and the name is just a display field.

### The Bugs We Hit (And How We Fixed Them)

**Bug #1: Structure Mismatch - The 500 Error**

```
Error: Failed to fetch agents: TypeError: Failed to fetch
Status: 500 Internal Server Error
```

**What happened**: Someone put **config data** (array structure) into the **runtime file** (dict structure):

```json
// WRONG - config data in runtime location
{ "agents": [{ "id": 0, "name": "felix-primary", "executable": "droid" }] }
```

**Why it broke**: Backend expected a dictionary keyed by ID to iterate over:

```python
for agent_id, agent in agents_dict.items():  # ❌ Can't iterate array as dict!
```

**The fix**:

1. Cleared the runtime file: `{"agents": {}}`
2. Added validation to prevent config/runtime confusion
3. Documented which file is which (hence this document!)

**Lesson**: When you have similar-looking data structures serving different purposes, make the distinction CRYSTAL CLEAR. We now have explicit comments and file locations.

---

**Bug #2: Loading from Wrong File**

```
ERROR: Agent ID 0 not found in agents.json
```

**What happened**: The PowerShell script was loading from **project** `felix/agents.json` (runtime) instead of **global** `~/.felix/agents.json` (config).

**Why it broke**: We cleared the runtime file to fix Bug #1, so there was no agent data there. Script looked in the wrong place.

**The fix**:

```powershell
# BEFORE (wrong)
$AgentsJsonFile = Join-Path $FelixDir "agents.json"  # Project runtime

# AFTER (correct)
$FelixHome = Join-Path $env:USERPROFILE ".felix"
$AgentsJsonFile = Join-Path $FelixHome "agents.json"  # Global config
```

**Lesson**: When you have **two files with the same name in different locations**, always be explicit about which one you mean. Use absolute paths, not ambiguous relative ones.

---

**Bug #3: Missing agent_id in Registration**

**What happened**: After refactoring endpoints from `/agents/{name}` to `/agents/{id}`, we forgot to update the registration request body.

**Why it broke**: Backend expected `agent_id` in the POST body, but PowerShell was still sending just `agent_name`.

**The fix**: Updated all places that call the API:

```powershell
# BEFORE
$registration = @{ agent_name = $AgentName; pid = $PID; ... }

# AFTER
$registration = @{ agent_id = $AgentId; agent_name = $AgentName; pid = $PID; ... }
```

**Lesson**: When refactoring APIs, grep for ALL call sites. It's not just the endpoint definition - it's every client that calls it. We found 7 places that needed updating across PowerShell, TypeScript, and Python.

## Technical Decisions: Why We Built It This Way

### Decision #1: FastAPI + Python for Backend

**Why**:

- Type safety with Pydantic models
- Automatic API documentation (Swagger/OpenAPI)
- WebSocket support for live console streaming
- Easy JSON serialization

**Alternative considered**: Node.js + Express  
**Why we didn't**: Python fits the ecosystem better (droid is Python-based, easier integration)

### Decision #2: Dict Keys as Strings in JSON

**The problem**: JSON doesn't support integer keys. When you write `{"0": {...}}`, it's a string.

**Our approach**:

```python
# Store as string in JSON
agents_dict = {str(agent_id): entry.model_dump() for agent_id, entry in agents.items()}

# Load as int in Python
for id_str, entry_data in agents_dict.items():
    agent_id = int(id_str)  # Convert back to int
    result[agent_id] = AgentEntry(**entry_data)
```

**Why**: We want `agent_id` to be an **integer type** in our code (type safety, validation), but JSON forces us to use strings. So we convert at the boundary.

**Lesson**: When your programming language's types don't match your storage format, convert at the I/O boundary and keep types consistent internally.

### Decision #3: One Agent Instance Per ID

**The constraint**: You cannot run two instances of agent ID 0 simultaneously.

**Why this is good**:

- **Prevents runaway processes**: Can't accidentally spawn 1000 agents
- **Explicit capacity planning**: "I have 3 worker slots"
- **Clear ownership**: "Agent 2 is working on S-0015"
- **Simple reasoning**: No need to track instance IDs, just agent IDs

**How to run multiple workers**: Create multiple agent configs with different IDs:

```json
{
  "agents": [
    {"id": 0, "name": "felix-primary", ...},
    {"id": 1, "name": "felix-worker-1", ...},
    {"id": 2, "name": "felix-worker-2", ...}
  ]
}
```

**Analogy**: Think of it like parking spaces. You have numbered spots (0, 1, 2). Each spot can hold one car. If you want more cars, you need more spots. You can't magically fit two cars in spot #0.

**Lesson**: Sometimes constraints make systems **easier** to reason about, not harder. Limiting to one-agent-per-ID prevents a whole class of bugs (race conditions, resource conflicts, orphaned processes).

### Decision #4: Heartbeat Every 5 Seconds

**Why 5 seconds**:

- Fast enough to detect crashes quickly (10-second timeout = worst case 15 seconds to detect)
- Slow enough to not spam the backend (12 requests/minute is trivial)
- Standard in distributed systems (Kubernetes uses 10s, we're more aggressive)

**How it works**:

```powershell
Start-Job -ScriptBlock {
    while ($true) {
        Start-Sleep -Seconds 5
        Invoke-RestMethod -Method POST -Uri "$BaseUrl/api/agents/$AgentId/heartbeat" -Body $json
    }
} -ArgumentList $AgentId, $BaseUrl
```

**What happens if an agent crashes**:

1. Heartbeats stop
2. After 10 seconds, backend marks status as "inactive"
3. UI shows: "⚪ felix-primary (inactive - last seen 2 min ago)"

**Lesson**: For distributed systems, you need a "dead man's switch." If you don't hear from a process, assume it's dead. The timeout (10s) should be 2x the heartbeat interval (5s) to allow for one missed heartbeat.

## How Good Engineers Think: Lessons from This System

### 1. **Separate Configuration from State**

Bad engineer: "Let's put the agent list and their runtime status in one file!"  
Good engineer: "Config changes rarely, state changes constantly. Different lifecycle = different storage."

This principle applies everywhere:

- Docker Compose: `docker-compose.yml` (config) vs. `docker ps` (state)
- Kubernetes: ConfigMaps (config) vs. Pod status (state)
- Web browsers: Settings (config) vs. Session storage (state)

### 2. **Use Immutable Identifiers for Relationships**

Bad engineer: "Let's use names as IDs - they're human-readable!"  
Good engineer: "Names are for display. IDs are for relationships. Never confuse the two."

When to use names:

- Showing information to users
- Logging and debugging
- CLI arguments (convert to ID immediately)

When to use IDs:

- Foreign keys / references
- API path parameters (now that we fixed it!)
- Anything that needs to survive a rename

### 3. **Make Invalid States Unrepresentable**

Bad engineer: "We'll validate agent_id at runtime"  
Good engineer: "We'll use TypeScript/Pydantic to make invalid IDs impossible"

```typescript
// TypeScript ensures agent_id is always a number
interface AgentEntry {
  agent_id: number;  // Can't be string, null, or undefined
  agent_name: string;
  ...
}
```

```python
# Pydantic validates on construction
class AgentEntry(BaseModel):
    agent_id: int  # Raises error if not an int
    agent_name: str
    ...
```

If your type system prevents bugs, you don't need runtime checks.

### 4. **Fail Fast, Fail Loud**

When we hit errors, we don't silently continue:

```powershell
if (-not $agentConfig) {
    Write-Host "ERROR: Agent ID $agentId not found" -ForegroundColor Red
    exit 1  # ❌ STOP immediately, don't continue with broken state
}
```

**Why**: It's better to crash early than to run for hours with corrupted data.

### 5. **Best-Effort Registration**

But... sometimes failing is worse than degrading:

```powershell
try {
    Register-Agent -AgentId $id -AgentName $name ...
    Write-Host "Registered successfully" -ForegroundColor Green
}
catch {
    Write-Host "Registration failed (backend may be unavailable)" -ForegroundColor Yellow
    # ⚠️ Continue anyway - agent can still work without registration
}
```

**Why**: Registration is for monitoring/UI. If the backend is down, we still want the agent to execute requirements. Don't let a nice-to-have feature block critical functionality.

**Lesson**: Know the difference between **critical** failures (wrong agent ID) and **degraded** failures (can't register). Fail fast on critical, degrade gracefully on nice-to-have.

### 6. **Explicit is Better Than Implicit**

We could have auto-generated agent IDs. We didn't. Why?

```json
// ❌ Auto-generated (implicit)
{"agents": [
  {"name": "felix-primary", ...},  // ID = 0? 1? Generated hash?
]}

// ✅ Explicit
{"agents": [
  {"id": 0, "name": "felix-primary", ...},  // Crystal clear
]}
```

**Why explicit is better**:

- No surprises ("Wait, why did my agent become ID 47?")
- Easy to reference ("Start agent 0")
- Portable ("Agent 0 is agent 0 everywhere")
- Debuggable ("Show me agent 0's logs")

**Lesson**: If a user needs to refer to something, make the identifier explicit and stable. Don't hide it behind auto-generation.

## Technologies Used

### Backend Stack

- **FastAPI**: Modern Python web framework with automatic API docs
- **Pydantic**: Data validation using Python type annotations
- **uvicorn**: ASGI server for async Python web apps
- **WebSockets**: For real-time console streaming to frontend

### Frontend Stack

- **React**: Component-based UI library
- **TypeScript**: Type-safe JavaScript with interfaces
- **Vite**: Fast build tool and dev server
- **Tailwind CSS**: Utility-first CSS framework

### Agent Stack

- **PowerShell**: Cross-platform scripting for agent orchestration
- **Background Jobs**: For async heartbeat loop
- **REST API**: HTTP calls to backend for registration/heartbeat

### Data Format

- **JSON**: Universal data interchange format
- **ISO 8601 timestamps**: Standard date/time format for global compat
- **UTF-8 encoding**: Universal text encoding

## Common Pitfalls and How to Avoid Them

### Pitfall #1: Confusing the Two Files

**Symptom**: "I added an agent to `felix/agents.json` but it doesn't show in the dropdown!"

**Why**: You edited the **runtime registry** (project folder), not the **config** (global folder).

**Fix**: Edit `~/.felix/agents.json` instead.

**Prevention**: Name them differently? `agents-config.json` vs. `agents-runtime.json`? (We kept the names for consistency with existing docs, but worth considering)

### Pitfall #2: Starting Agent Before Backend

**Symptom**: "Agent starts but doesn't show in dashboard"

**Why**: Registration failed because backend wasn't running.

**Fix**:

```powershell
# 1. Start backend first
cd app/backend
python main.py

# 2. Then start agent
.\felix-agent.ps1 C:\dev\Felix
```

**Prevention**: The agent continues working even without registration (best-effort), but you won't see it in the UI. Always start backend first for full visibility.

### Pitfall #3: Hardcoding Agent Names

**Bad code**:

```typescript
const agent = agents.find((a) => a.name === "felix-primary"); // ❌ Fragile!
```

**Why bad**: If user renames the agent, code breaks.

**Good code**:

```typescript
const agent = agents.find((a) => a.id === 0); // ✅ Stable ID
console.log(`Agent: ${agent.name}`); // Use name for display only
```

**Lesson**: Use IDs for logic, names for display.

### Pitfall #4: Not Cleaning Up Heartbeat Jobs

**Symptom**: "I have 50 PowerShell background jobs running!"

**Why**: Each agent start creates a heartbeat job. If you don't clean up, they accumulate.

**Fix**:

```powershell
# On script exit
finally {
    Stop-HeartbeatJob  # Kills background job
    Unregister-Agent -AgentId $id
}
```

**Prevention**: Always pair resource creation with cleanup. Use `try/finally` blocks.

### Pitfall #5: Forgetting to Convert String Keys

**Symptom**: "Frontend can't find agent - it's looking for string '0' not number 0"

**Why**: JSON stores keys as strings. TypeScript treats them as strings unless you convert.

**Fix**:

```typescript
// Backend sends: {"agents": {"0": {...}}}
const runtimeAgents = response.agents;
const runtime = runtimeAgents[config.id]; // ✅ Works if config.id is number

// If config.id is string, convert:
const runtime = runtimeAgents[String(config.id)];
```

**Prevention**: Be consistent about types. If agent_id is a number in your type system, keep it as a number. Convert only at I/O boundaries (JSON serialization).

## The Multi-Agent Future

With this architecture, running multiple agents is straightforward:

### Step 1: Configure Worker Slots

```json
// ~/.felix/agents.json
{
  "agents": [
    {"id": 0, "name": "felix-primary", "executable": "droid", ...},
    {"id": 1, "name": "felix-worker-1", "executable": "droid", ...},
    {"id": 2, "name": "felix-worker-2", "executable": "droid", ...}
  ]
}
```

### Step 2: Start Multiple Processes

```powershell
# Terminal 1
$env:AGENT_ID = 0
.\felix-agent.ps1 C:\dev\Felix

# Terminal 2
$env:AGENT_ID = 1
.\felix-agent.ps1 C:\dev\Felix

# Terminal 3
$env:AGENT_ID = 2
.\felix-agent.ps1 C:\dev\Felix
```

### Step 3: Watch Them Work

```json
// felix/agents.json (runtime)
{
  "agents": {
    "0": { "agent_id": 0, "status": "active", "current_run_id": "S-0022" },
    "1": { "agent_id": 1, "status": "active", "current_run_id": "S-0023" },
    "2": { "agent_id": 2, "status": "active", "current_run_id": "S-0024" }
  }
}
```

Dashboard shows all three, working in parallel, each with their own console output!

## Summary: The Key Insights

1. **Two files, two purposes**: Config (what CAN run) vs. Registry (what IS running)
2. **IDs are stable, names are mutable**: Use IDs for relationships, names for display
3. **Constraints enable simplicity**: One agent per ID prevents a whole class of bugs
4. **Fail fast on critical, degrade on nice-to-have**: Know the difference
5. **Type safety at boundaries**: Convert once at I/O, keep types consistent internally
6. **Heartbeats detect failures**: 5-second pulse, 10-second timeout
7. **Explicit beats implicit**: Users can reason about what they can see

This system isn't just about running agents - it's a case study in how to design distributed systems that are both powerful and predictable. Every decision (from ID-based keys to separate config files) came from real bugs, real confusion, and real learning.

Now go forth and build reliable systems! And remember: if it changes rarely, it's config. If it changes constantly, it's state. Never mix the two.

---

_"The best code is not clever - it's obvious."_ - Someone smarter than us

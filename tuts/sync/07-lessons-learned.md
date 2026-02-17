# Chapter 7: Battle Scars - Bugs We Hit and How We Fixed Them

This is the chapter you came for. The bugs, the facepalms, the 3 AM debugging sessions, and the lessons that stick.

## Bug #1: The Integer That Wanted To Be a String

**Date:** February 17, 2026  
**Severity:** Breaking  
**Time to Fix:** 15 minutes  
**Time to Find:** 2 hours

### The Error

```
[18:51:16.872] WARN [agent] Registration failed:
{"detail":[{"type":"string_type","loc":["body","agent_id"],
"msg":"Input should be a valid string","input":0}]}
```

**Translation:** Backend expects `agent_id` as a string, got integer `0`.

### The Code

```powershell
# In agents.json
{
  "id": 0,        # ← Stored as integer
  "name": "droid",
  "adapter": "droid"
}

# In felix-agent.ps1 (the bug)
$syncAgentInfo = @{
    agent_id = $agentConfig.id  # ← Sends integer 0
    hostname = $env:COMPUTERNAME
}

# Backend expects (Pydantic model)
class AgentRegistration(BaseModel):
    agent_id: str  # ← Strict type checking
```

### Why This Happened

PowerShell hashtables don't care about types. This works fine:

```powershell
$myHash = @{ id = 0 }       # Integer
$myHash = @{ id = "0" }     # String
```

But when PowerShell sends this to FastAPI via JSON:

```json
{ "agent_id": 0 }     // JSON integer
{ "agent_id": "0" }   // JSON string
```

**Pydantic validates strictly.** It sees `"agent_id": 0` and says: "I expected a string. This is an integer. REJECTED."

### The Fix

```powershell
# Before
agent_id = $agentConfig.id

# After
agent_id = $agentConfig.id.ToString()  # ← Explicit conversion
```

One call to `.ToString()`. Problem solved.

### The Lesson

**Type systems don't translate automatically.** Even when languages try to be helpful (PowerShell auto-converts types), serialization doesn't. JSON has numbers and strings as different types. This becomes YOUR problem at API boundaries.

**Best Practice:**

- Always explicitly convert types at API boundaries
- Never trust implicit type coercion when crossing language boundaries
- Use strict validation libraries (Pydantic) to catch this early

**Pro tip:** This bug would have been caught by TypeScript. If you're building APIs, consider using TypeScript on both sides, or at least generate TypeScript types from your Python models.

## Bug #2: The Duplicate Registration Call

**Date:** Same day (minutes after Bug #1)  
**Severity:** Confusing  
**Time to Fix:** 5 minutes  
**Time to Find:** 30 minutes

### The Symptom

Even after fixing Bug #1, we saw strange fields in the error:

```json
{
  "agent_name": "droid", // ← Wrong field name
  "pid": 41364, // ← We don't send this anymore
  "started_at": "..." // ← Or this
}
```

"Wait, we fixed the code. Why is it still sending old fields?"

### The Discovery

There were **TWO** registration calls:

```powershell
# Call #1 (lines 413-440) - NEW CODE - Sync reporter pattern
$syncAgentInfo = @{
    agent_id = $agentConfig.id.ToString()
    hostname = $env:COMPUTERNAME
    platform = $platform
    version = "0.7"
}
$script:SyncReporter.RegisterAgent($syncAgentInfo)

# Call #2 (lines 532-539) - LEGACY CODE - Direct registration
$registrationSucceeded = Register-Agent `
    -AgentId $agentConfig.id `      # ← Old function signature
    -AgentName $agentName `         # ← Sends wrong fields
    -ProcessId $PID `
    -Hostname $env:COMPUTERNAME `
    -BackendBaseUrl $script:BackendBaseUrl
```

**The old call was still there.** We added new sync code but forgot to remove the old heartbeat system.

### Why This Happened

We evolved the design:

1. **Original design:** Direct REST calls with heartbeat
2. **New design:** Sync reporter pattern with outbox queue

But we never removed the old code. Both ran. One failed (old), one worked (new).

### The Fix

Delete the old registration:

```powershell
# Removed:
# - Register-Agent call (lines 532-539)
# - Heartbeat job start
# - agent-registration.ps1 module (deprecated)

# Kept:
# - Sync reporter registration (lines 413-440)
```

### The Lesson

**Refactoring isn't done until the old code is deleted.** It's not enough to write new code that works. You must:

1. Write new code
2. Verify new code works
3. Delete old code
4. Verify old code is actually unused

**How to avoid this:**

- Grep for old function names before merging
- Use deprecation warnings (`Write-Warning "This function is deprecated"`)
- Add TODOs at point of use (`# TODO: Remove this after migration`)
- Code review specifically for "dead code"

## Bug #3: Missing Field Names in Backend Model

**Date:** Same debugging session  
**Severity:** High (blocking)  
**Time to Fix:** 10 minutes

### The Problem

We added new fields to the registration request:

```powershell
$syncAgentInfo = @{
    felix_root = $ProjectPath  # ← New field
    adapter    = $agentConfig.adapter  # ← New field
    executable = $agentConfig.executable  # ← New field
    model      = $agentConfig.model  # ← New field
}
```

But the backend model was old:

```python
class AgentRegistration(BaseModel):
    agent_id: str
    hostname: str
    platform: str
    version: str
    # ← Missing: felix_root, adapter, executable, model
```

**Result:** Pydantic silently ignored the extra fields. No error, no storage, no data.

### The Fix

Update the model:

```python
class AgentRegistration(BaseModel):
    agent_id: str
    hostname: str
    platform: str
    version: str
    felix_root: Optional[str] = Field(None, description="Felix repository root path")
    adapter: Optional[str] = Field(None, description="LLM adapter name")
    executable: Optional[str] = Field(None, description="Agent executable")
    model: Optional[str] = Field(None, description="LLM model identifier")
```

Then update the database insert:

```python
query = """
    INSERT INTO agents (id, name, hostname, platform, version,
                        adapter, executable, model, ...)
    VALUES (:id, :name, :hostname, :platform, :version,
            :adapter, :executable, :model, ...)
    ON CONFLICT (id) DO UPDATE SET
        adapter = EXCLUDED.adapter,
        executable = EXCLUDED.executable,
        model = EXCLUDED.model,
        ...
"""
```

### The Lesson

**Schema evolution requires three-step coordination:**

1. **Database migration** - Add columns (with defaults for old rows)
2. **Backend code** - Update models and queries
3. **CLI code** - Send new fields

Miss any step → data loss.

**Best practice:**

- Write database migration first (creates columns)
- Update backend to accept new fields (makes them optional)
- Deploy backend before updating CLI (backward compatible)
- Update CLI to send new fields (forward compatible)
- Later, make fields required (after verifying all CLIs updated)

This is called **expand-contract migration pattern**.

## Bug #4: The "Name" vs "agent_name" Confusion

**Severity:** Medium  
**Pattern:** API Design Mistake

### The Inconsistency

Different parts of the codebase used different names:

```python
# Backend expects
class AgentRegistration(BaseModel):
    name: str  # ← Used in backend

# CLI sends
$syncAgentInfo = @{
    agent_name = "droid"  # ← Was sent from CLI (old code)
}

# Database stores
CREATE TABLE agents (
    name TEXT  # ← But actually wants "name"
)
```

**Result:** 400 Bad Request - "Field required: name"

### The Fix

**Be consistent.** Pick one name and use it everywhere:

```python
# Backend model
agent_id: str  # Unique identifier
name: str      # Will receive agent_id as name for CLI agents

# CLI sends
agent_id = $agentConfig.id.ToString()
# Backend automatically uses agent_id as name
```

### The Lesson

**Name things consistently across boundaries.** When you have:

- CLI (PowerShell)
- Backend (Python)
- Database (SQL)
- Frontend (TypeScript)

Use the same field names everywhere. Don't translate. Don't be clever.

**Anti-pattern:**

```python
# Frontend calls this "username"
# Backend calls this "user_name"
# Database calls this "uname"
# CLI calls this "login"
```

**Good pattern:**

```python
# Everyone calls this "user_id"
```

## Bug #5: Platform Hardcoded to "Windows"

**Severity:** Low (data quality issue)  
**Discovered:** During code review

### The Problem

```powershell
$syncAgentInfo = @{
    platform = "windows"  # ← Hardcoded!
}
```

Agents running on Linux or macOS reported platform as "windows". Metrics were wrong.

### The Fix

Dynamic detection:

```powershell
$platform = if ($IsWindows -or $env:OS -match "Windows") {
    "windows"
}
elseif ($IsLinux) {
    "linux"
}
elseif ($IsMacOS) {
    "macos"
}
else {
    "unknown"
}
```

### The Lesson

**Never hardcode dynamic data.** Especially when the language gives you standard variables:

- `$IsWindows` (PowerShell 6+)
- `$IsLinux` (PowerShell 6+)
- `$IsMacOS` (PowerShell 6+)

**Corollary:** Don't assume your development environment is the only environment.

## Bug #6: Register-Agent Was Actually Not Needed

**Date:** During architecture review  
**Severity:** None (design question)  
**Time to Resolve:** 30-minute discussion

### The Question

"Why do we call `RegisterAgent()` and then `StartRun()`? Can't we just do `StartRun()` and create the agent record automatically via foreign key?"

### The Debate

**Option 1: Merge registration into StartRun**

```python
# In StartRun endpoint
agent_id = body.agent_id
# Create agent if not exists (automatic)
cursor.execute("INSERT INTO agents (id) VALUES (?) ON CONFLICT DO NOTHING", agent_id)
```

**Pros:**

- One fewer API call
- Simpler client code
- Automatic agent creation

**Cons:**

- No agent metadata (platform, version, adapter)
- No registration timestamp
- No way to distinguish "agent exists" from "agent registered"

**Option 2: Keep separate registration**

```python
# RegisterAgent: Store metadata
# StartRun: Just foreign key reference
```

**Pros:**

- Rich agent metadata (platform, version, model, hostname)
- Registration acts as heartbeat
- Can query "active agents" separately
- Clear lifecycle: register → run → unregister

**Cons:**

- Extra API call
- More complex client code

### The Decision

**Keep registration separate.** Here's why:

1. **Metadata matters** - Knowing which agents use which models helps with billing, debugging, and capacity planning
2. **Registration is a heartbeat** - Updates `last_seen_at`, lets backend know agent is alive
3. **Separation of concerns** - Agent identity vs agent work are different concepts
4. **Future-proofing** - Can add agent-level features (disable agent, agent quotas, etc.)

### The Lesson

**Don't over-DRY.** Yes, you could merge two calls into one. But sometimes the separation carries information:

- Registration = "I exist"
- StartRun = "I'm working"

These are conceptually different, so keeping them separate makes the design clearer.

**Also: Premature optimization is the root of all evil.** We obsessed over "one fewer API call" when:

- Registration happens once per agent run (not hot path)
- Network latency dominates (100ms vs 200ms is noise)
- Code clarity matters more than saving 100ms

## Bug #7: SHA256 Wasn't Checked Fast Enough

**Scenario:** Backend received duplicate uploads  
**Root cause:** Frontend called upload APIs twice

Early implementation:

```python
# Backend: Check if file exists
result = await db.fetch_one(
    "SELECT 1 FROM run_files WHERE run_id = :run_id AND path = :path"
)
if result:
    return  # Skip upload

# Upload the file
await storage.save_file(...)
```

**Problem:** Check was only by path, not by SHA256. If file content changed, old version remained.

### The Fix

```python
# Check by SHA256 hash
result = await db.fetch_one(
    """
    SELECT sha256 FROM run_files
    WHERE run_id = :run_id AND path = :path
    """
)

if result and result["sha256"] == request_sha256:
    return  # Same file, skip upload

# Different content or new file - upload it
await storage.save_file(...)
await db.execute(
    """
    INSERT INTO run_files (run_id, path, sha256, ...)
    VALUES (...)
    ON CONFLICT (run_id, path) DO UPDATE SET
        sha256 = EXCLUDED.sha256,
        ...
    """
)
```

### The Lesson

**Idempotency requires content addressing.** Path alone isn't enough:

- File gets updated with new content
- Upload fails midway, retries
- User manually edits file then re-syncs

Use SHA256 (or any cryptographic hash) to make idempotency actually work.

## Patterns We Got Right

Not everything was a bug! Some things worked well from the start:

### ✅ Outbox Queue Pattern

Never had to refactor this. It worked offline, handled retries, made debugging easy.

### ✅ JSONL Format

Plain text = easy debugging. One line per request = atomic operations.

### ✅ Fail Gracefully

Sync failures never crashed the agent. This design decision saved us countless times.

### ✅ SHA256 Deduplication

Saved 60% of bandwidth immediately. Uploads of unchanged files are instant.

### ✅ Separate Agent Registration

Despite the debate, this turned out great. Having rich agent metadata helped debug issues.

## Testing Lessons

We learned what makes tests valuable:

### Good Tests

**E2E scripts that simulate real scenarios:**

```powershell
# test-sync-happy-path.ps1
# 1. Start backend
# 2. Enable sync
# 3. Run agent
# 4. Verify uploads
# 5. Check database
```

These caught actual bugs.

### Bad Tests

**Unit tests for retry logic:**

```powershell
It "retries 3 times with exponential backoff" {
    # This test is a lie - we don't actually retry 3 times
}
```

We wrote tests for behavior we didn't implement. Tests passed. Code was wrong.

**Lesson:** Test what you actually do, not what you think you do.

## Debug Techniques That Saved Us

### 1. Verbose Logging

```powershell
Emit-Log -Level "debug" -Message "About to call RegisterAgent" -Component "init"
$result = RegisterAgent(...)
Emit-Log -Level "debug" -Message "RegisterAgent returned: $result" -Component "init"
```

Verbose, but saved hours. We saw exactly where execution went wrong.

### 2. Inspect Outbox Files

```powershell
Get-Content .felix\outbox\*.jsonl | ConvertFrom-Json | Format-List
```

If sync was queued but not sent, outbox files had the evidence.

### 3. Backend Request Logging

```python
log_sync_info(
    f"Agent registered on {body.hostname}",
    agent_id=body.agent_id,
    platform=body.platform,
    adapter=body.adapter,
)
```

Compare CLI logs with backend logs to find where requests got lost.

### 4. Database Queries

```sql
-- What agents are registered?
SELECT id, name, platform, adapter, last_seen_at FROM agents;

-- What runs exist?
SELECT id, requirement_id, agent_id, started_at FROM runs ORDER BY started_at DESC LIMIT 10;

-- What files were uploaded?
SELECT run_id, path, sha256, size_bytes FROM run_files WHERE run_id = 'abc123';
```

When everything else failed, SQL showed ground truth.

## The Meta-Lesson

**Good architecture forgives mistakes.** Because we used:

- Outbox pattern (queued requests weren't lost during debugging)
- Idempotent uploads (safe to retry while fixing bugs)
- Local-first design (agent kept working despite sync bugs)

...we could debug and fix issues **without user impact**. Users saw warnings, but their work continued.

**Bad architecture punishes mistakes.** If we'd built:

- Synchronous uploads (bugs would crash agent)
- Non-idempotent requests (bugs would corrupt data)
- Cloud-first design (bugs would block work)

...every bug would have been a crisis.

## Next: Testing Strategy

Now that you've seen the bugs, let's see how we test to catch them.

[Continue to Chapter 8: Testing Strategy →](08-testing.md)

---

**Remember:** Every bug taught us something. The bugs that hurt the worst taught us the most. And the best architecture isn't bug-free – it's bug-resilient.

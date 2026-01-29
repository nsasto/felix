# Future State Agent Tracking

## Current Model: Agent Pushes Heartbeats

**Pros:**

- Simple: Agent just sends HTTP POST every 5 seconds
- No backend polling overhead
- Agent controls frequency
- Works across networks (agent can be remote)

**Cons:**

- Network traffic every 5 seconds per agent
- If agent crashes mid-iteration, backend doesn't know until heartbeat timeout (10s)
- Background job in PowerShell adds complexity

## Proposed Model: Server Polls Process

**How it would work:**

1. Agent registers once: `POST /api/agents/register` with PID + hostname
2. Backend periodically checks if PID still exists
3. Backend updates status based on process existence

**Pros:**

- No continuous network traffic
- Cleaner agent code (no background heartbeat job)
- More accurate detection of crashes

**Cons:**

- **Only works locally**: Backend can only check PIDs on same machine
- **Doesn't work for remote agents**: Can't check PID on different hostname
- Backend needs polling loop/scheduler
- Cross-platform PID checking complexity (Windows vs Linux)

## Hybrid Approach?

**Option 1: Local agents = poll, Remote agents = heartbeat**

- Backend detects if `hostname == current_hostname`
- If local: poll PID
- If remote: require heartbeats

**Option 2: Remove heartbeats entirely, trust registration**

- Agent registers on start
- Agent unregisters on clean shutdown
- Backend marks stale if no activity for X time
- Simpler but less accurate

## Recommendation

**Keep the current heartbeat model** because:

1. **Future-proof**: Supports distributed agents (multiple machines, cloud agents)
2. **Current work tracking**: Heartbeat includes `current_run_id`, showing what requirement the agent is working on
3. **Standard pattern**: Most distributed systems use heartbeats (Kubernetes, Consul, etc.)
4. **5 seconds is reasonable**: Not excessive overhead

## TODO: Add Agent ID to Run Output Folders

**Current behavior:**

- Run output folders are named by requirement only (e.g., `felix/runs/S-0001/`)
- When multiple agents run the same requirement, outputs overwrite each other

**Proposed behavior:**

- Include agent ID in folder structure: `felix/runs/S-0001/{agent-id}/`
- Each agent's run outputs are isolated
- Easy to trace which agent produced which artifacts

**Benefits:**

- Supports multiple agents working on different requirements simultaneously
- Prevents race conditions on shared output directories
- Audit trail: know exactly which agent produced each log/artifact
- Aligns with agent heartbeat tracking (agent ID already tracked in backend)

**Implementation notes:**

- Agent ID format: `{ComputerName}-{PID}` (matches heartbeat system)
- Update `felix-agent.ps1` to create agent-specific output folders
- Update validation/reporting to read from agent-specific paths

## TODO: Add Version Composite Key for Change Detection

**Current behavior:**

- Agent doesn't track if its script or prompts have changed between runs
- No way to know if output folder was generated with current or old version
- Comparing outputs across versions can lead to false positives/negatives

**Proposed behavior:**

- Create composite version key: `{script-version}-{prompts-version}`
- Script version: semver from `felix-agent.ps1` header or git commit hash
- Prompts version: hash of prompt files or explicit version number
- Include version in output folder structure: `felix/runs/S-0001/{agent-id}/{version}/`

**Benefits:**

- Agent can detect if it's running with different code/prompts than last run
- Output comparison only happens between same-version runs
- Clear audit trail of which version produced which results
- Prevents confusion when debugging output differences

**Implementation notes:**

- Add version metadata to output folder (e.g., `version.json`)
- Agent checks version before reusing/comparing previous outputs
- If version mismatch, treat as fresh run (don't compare outputs)
- Version format example: `1.2.0-a3f9d8` (script version + prompt hash)
- Update validation scripts to be version-aware

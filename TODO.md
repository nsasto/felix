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

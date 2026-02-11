# S-0039: Control WebSocket Infrastructure

**Phase:** 1 (Core Orchestration)  
**Effort:** 6-8 hours  
**Priority:** High  
**Dependencies:** S-0038

---

## Narrative

This specification covers implementing a bidirectional WebSocket for agent control commands (START, STOP, PAUSE, RESUME). This allows the backend to send control commands to connected agents and receive status updates. This is distinct from the console streaming WebSocket (which only streams logs).

---

## Acceptance Criteria

### WebSocket Module

- [ ] Create **app/backend/websocket/**init**.py** (empty)
- [ ] Create **app/backend/websocket/control.py** with `ControlConnectionManager` class

### ControlConnectionManager Class

- [ ] Maintain dict of active connections: `{agent_id: WebSocket}`
- [ ] Method: `async connect(agent_id, websocket)` - Register new connection
- [ ] Method: `async disconnect(agent_id)` - Remove connection
- [ ] Method: `async send_command(agent_id, command)` - Send command to specific agent
- [ ] Method: `async broadcast_status(agent_id, status)` - Broadcast status to listeners

### WebSocket Endpoint

- [ ] Add endpoint: `@router.websocket("/api/agents/{agent_id}/control")`
- [ ] Accept agent connection
- [ ] Receive and handle messages from agent (status updates, heartbeats)
- [ ] Send commands from backend to agent (START, STOP, PAUSE)
- [ ] Handle connection errors and cleanup

### Message Protocol

- [ ] Define JSON message format:
  - Commands (backend → agent): `{"type": "command", "command": "START", "run_id": "...", "requirement_id": "..."}`
  - Status (agent → backend): `{"type": "status", "status": "running", "run_id": "..."}`
  - Heartbeat (agent → backend): `{"type": "heartbeat"}`

---

## Technical Notes

### ControlConnectionManager (websocket/control.py)

```python
from fastapi import WebSocket
from typing import Dict
import json
import logging

logger = logging.getLogger(__name__)

class ControlConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, agent_id: str, websocket: WebSocket):
        """Register a new agent control connection"""
        await websocket.accept()
        self.active_connections[agent_id] = websocket
        logger.info(f"Agent {agent_id} connected to control WebSocket")

    async def disconnect(self, agent_id: str):
        """Remove agent control connection"""
        if agent_id in self.active_connections:
            del self.active_connections[agent_id]
            logger.info(f"Agent {agent_id} disconnected from control WebSocket")

    async def send_command(self, agent_id: str, command: dict):
        """Send command to specific agent"""
        if agent_id not in self.active_connections:
            raise ValueError(f"Agent {agent_id} not connected")

        websocket = self.active_connections[agent_id]
        await websocket.send_json(command)
        logger.info(f"Sent command to agent {agent_id}: {command}")

    async def broadcast_status(self, agent_id: str, status: dict):
        """Broadcast agent status to all listening connections"""
        # For now, just log status updates
        # Phase 3 will broadcast via Supabase Realtime
        logger.info(f"Agent {agent_id} status: {status}")

    def is_connected(self, agent_id: str) -> bool:
        """Check if agent is connected"""
        return agent_id in self.active_connections

# Global instance
control_manager = ControlConnectionManager()
```

### WebSocket Endpoint (routers/agents.py)

```python
from websocket.control import control_manager
from fastapi import WebSocket, WebSocketDisconnect

@router.websocket("/{agent_id}/control")
async def agent_control_websocket(
    websocket: WebSocket,
    agent_id: str,
    db = Depends(get_db)
):
    """
    Bidirectional WebSocket for agent control.

    Messages from backend to agent (commands):
    - {"type": "command", "command": "START", "run_id": "...", "requirement_id": "..."}
    - {"type": "command", "command": "STOP", "run_id": "..."}

    Messages from agent to backend (status):
    - {"type": "status", "status": "running", "run_id": "..."}
    - {"type": "heartbeat"}
    """
    await control_manager.connect(agent_id, websocket)
    writer = AgentWriter(db)

    try:
        while True:
            # Receive messages from agent
            data = await websocket.receive_json()
            message_type = data.get("type")

            if message_type == "status":
                # Agent reporting status change
                status = data.get("status")
                run_id = data.get("run_id")
                await writer.update_status(agent_id, status)
                await control_manager.broadcast_status(agent_id, data)

            elif message_type == "heartbeat":
                # Agent sending heartbeat
                await writer.update_heartbeat(agent_id)

            else:
                logger.warning(f"Unknown message type from agent {agent_id}: {message_type}")

    except WebSocketDisconnect:
        await control_manager.disconnect(agent_id)
        await writer.update_status(agent_id, "disconnected")
    except Exception as e:
        logger.error(f"Error in control WebSocket for agent {agent_id}: {e}")
        await control_manager.disconnect(agent_id)
```

### Message Protocol Examples

**START Command (backend → agent):**

```json
{
  "type": "command",
  "command": "START",
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "requirement_id": "660e8400-e29b-41d4-a716-446655440000",
  "metadata": {
    "max_iterations": 10
  }
}
```

**Status Update (agent → backend):**

```json
{
  "type": "status",
  "status": "running",
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "progress": 0.5
}
```

**Heartbeat (agent → backend):**

```json
{
  "type": "heartbeat"
}
```

---

## Dependencies

**Depends On:**

- S-0038: Agent Registration and Heartbeat API

**Blocks:**

- S-0040: Run Control API Endpoints

---

## Validation Criteria

### File Creation

- [ ] File exists: **app/backend/websocket/**init**.py**
- [ ] File exists: **app/backend/websocket/control.py**
- [ ] Module imports: `cd app/backend && python -c "from websocket.control import control_manager"`

### Backend Verification

- [ ] Backend starts: `cd app/backend && python main.py`
- [ ] API docs show control WebSocket: Open `http://localhost:8080/docs`, verify `/api/agents/{agent_id}/control`

### WebSocket Connection Test

**Test with wscat (install: `npm install -g wscat`):**

```bash
# Connect as agent
wscat -c ws://localhost:8080/api/agents/test-agent-1/control

# Send heartbeat from agent
> {"type": "heartbeat"}

# Send status update from agent
> {"type": "status", "status": "running", "run_id": "test-run-1"}

# Verify no errors in backend logs
```

### Database Verification

- [ ] Heartbeat updates agent: `psql -U postgres -d felix -c "SELECT id, heartbeat_at FROM agents WHERE id = 'test-agent-1';"`
- [ ] Status updates agent: `psql -U postgres -d felix -c "SELECT id, status FROM agents WHERE id = 'test-agent-1';"`

### Connection Manager Test

**Python test script:**

```python
import asyncio
from websocket.control import control_manager

async def test():
    print("Connected agents:", control_manager.active_connections.keys())
    assert control_manager.is_connected("test-agent-1")

asyncio.run(test())
```

---

## Rollback Strategy

If issues arise:

1. Remove websocket/ directory
2. Remove control WebSocket endpoint from routers/agents.py
3. Revert to Phase 0 state (REST API only)

---

## Notes

- Control WebSocket is bidirectional (agent ↔ backend)
- Console WebSocket is unidirectional (backend → frontend) and separate
- Control WebSocket handles commands and status updates
- Console WebSocket handles log streaming only
- Agents should connect to control WebSocket on startup
- Backend can send commands only to connected agents
- Connection manager tracks all active agent connections
- Phase 3 will integrate Supabase Realtime for status broadcasting
- For now, status updates are logged but not broadcast to frontend (Phase 1 uses polling)


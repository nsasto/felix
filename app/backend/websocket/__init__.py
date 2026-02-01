# WebSocket infrastructure for Felix agent control
"""
WebSocket module for Felix agent control infrastructure.

This module provides bidirectional WebSocket communication between the backend
and connected agents for control commands and status updates.

Exports:
    - control_manager: Global ControlConnectionManager instance
    - ControlConnectionManager: Class for managing WebSocket connections
    - CommandType: Enum of valid command types (START, STOP, PAUSE, RESUME)
    - AgentStatus: Enum of valid agent statuses (running, idle, stopped, error)
    - ControlCommand: Pydantic model for command messages (backend → agent)
    - StatusMessage: Pydantic model for status messages (agent → backend)
    - HeartbeatMessage: Pydantic model for heartbeat messages (agent → backend)
"""

from .control import (
    control_manager,
    ControlConnectionManager,
    CommandType,
    AgentStatus,
    ControlCommand,
    StatusMessage,
    HeartbeatMessage,
)

__all__ = [
    "control_manager",
    "ControlConnectionManager",
    "CommandType",
    "AgentStatus",
    "ControlCommand",
    "StatusMessage",
    "HeartbeatMessage",
]

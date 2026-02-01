"""
Control WebSocket Connection Manager for Felix Agent Control.

This module provides bidirectional WebSocket infrastructure for agent control commands
(START, STOP, PAUSE, RESUME). It allows the backend to send control commands to connected
agents and receive status updates in real-time.

This is distinct from the console streaming WebSocket which only streams logs unidirectionally.

Part of S-0039: Control WebSocket Infrastructure
"""

import logging
from typing import Dict

from fastapi import WebSocket


# Configure module logger
logger = logging.getLogger(__name__)


class ControlConnectionManager:
    """
    Manages bidirectional WebSocket connections for agent control.

    Maintains a dictionary of active connections mapping agent_id to WebSocket.
    Provides methods to connect, disconnect, send commands, and check connection status.

    Usage:
        - Agents connect to `/api/agents/{agent_id}/control` WebSocket endpoint
        - Backend can send commands via `send_command(agent_id, command)`
        - Agents send status updates and heartbeats which are received in the endpoint

    Attributes:
        active_connections: Dict mapping agent_id (str) to WebSocket instance
    """

    def __init__(self) -> None:
        """Initialize the connection manager with an empty connections dict."""
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, agent_id: str, websocket: WebSocket) -> None:
        """
        Register a new agent control connection.

        Accepts the WebSocket connection and stores it in the active_connections dict.
        If an agent reconnects, the new connection replaces the old one.

        Args:
            agent_id: The unique identifier for the agent (string UUID or ID)
            websocket: The FastAPI WebSocket instance for this connection
        """
        await websocket.accept()
        self.active_connections[agent_id] = websocket
        logger.info(f"Agent {agent_id} connected to control WebSocket")

    async def disconnect(self, agent_id: str) -> None:
        """
        Remove an agent control connection.

        Removes the agent from the active_connections dict if present.
        Safe to call even if agent is not connected.

        Args:
            agent_id: The unique identifier for the agent
        """
        if agent_id in self.active_connections:
            del self.active_connections[agent_id]
            logger.info(f"Agent {agent_id} disconnected from control WebSocket")

    async def send_command(self, agent_id: str, command: dict) -> None:
        """
        Send a command to a specific connected agent.

        Commands are JSON objects with at minimum a 'type' and 'command' field.
        Example: {"type": "command", "command": "START", "run_id": "...", "requirement_id": "..."}

        Args:
            agent_id: The unique identifier for the agent
            command: Dict containing the command to send (will be JSON serialized)

        Raises:
            ValueError: If the agent is not connected
        """
        if agent_id not in self.active_connections:
            raise ValueError(f"Agent {agent_id} not connected")

        websocket = self.active_connections[agent_id]
        await websocket.send_json(command)
        logger.info(f"Sent command to agent {agent_id}: {command}")

    def is_connected(self, agent_id: str) -> bool:
        """
        Check if an agent is currently connected.

        Args:
            agent_id: The unique identifier for the agent

        Returns:
            True if the agent has an active WebSocket connection, False otherwise
        """
        return agent_id in self.active_connections

    async def broadcast_status(self, agent_id: str, status: dict) -> None:
        """
        Broadcast agent status to all listening connections.

        Currently logs the status update. Phase 3 will integrate Supabase Realtime
        for pushing status updates to frontend clients.

        Args:
            agent_id: The unique identifier for the agent
            status: Dict containing the status information
        """
        # For now, just log status updates
        # Phase 3 will broadcast via Supabase Realtime
        logger.info(f"Agent {agent_id} status: {status}")


# Global instance for use across the application
control_manager = ControlConnectionManager()

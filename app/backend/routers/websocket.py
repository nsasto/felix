"""
Felix Backend - WebSocket API for Real-time Updates
Watches felix/state.json, requirements.json, and runs/ for changes
and broadcasts updates to connected clients.
"""

import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import Dict, Set, Optional, Any
from contextlib import asynccontextmanager

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from watchfiles import awatch, Change

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage


router = APIRouter(tags=["websocket"])


class ConnectionManager:
    """Manages WebSocket connections per project"""
    
    def __init__(self):
        # project_id -> set of WebSocket connections
        self._connections: Dict[str, Set[WebSocket]] = {}
        # project_id -> asyncio task watching files
        self._watchers: Dict[str, asyncio.Task] = {}
        # Lock for thread-safe operations
        self._lock = asyncio.Lock()
    
    async def connect(self, project_id: str, websocket: WebSocket):
        """Accept a new WebSocket connection for a project"""
        await websocket.accept()
        
        async with self._lock:
            if project_id not in self._connections:
                self._connections[project_id] = set()
            self._connections[project_id].add(websocket)
            
            # Start watcher if this is the first connection for this project
            if project_id not in self._watchers or self._watchers[project_id].done():
                self._watchers[project_id] = asyncio.create_task(
                    self._watch_project(project_id)
                )
    
    async def disconnect(self, project_id: str, websocket: WebSocket):
        """Remove a WebSocket connection"""
        async with self._lock:
            if project_id in self._connections:
                self._connections[project_id].discard(websocket)
                
                # If no more connections, cancel the watcher
                if not self._connections[project_id]:
                    del self._connections[project_id]
                    if project_id in self._watchers:
                        self._watchers[project_id].cancel()
                        try:
                            await self._watchers[project_id]
                        except asyncio.CancelledError:
                            pass
                        del self._watchers[project_id]
    
    async def broadcast(self, project_id: str, message: dict):
        """Broadcast a message to all connections for a project"""
        if project_id not in self._connections:
            return
        
        # Create a copy to avoid modification during iteration
        connections = list(self._connections.get(project_id, set()))
        dead_connections = []
        
        for websocket in connections:
            try:
                await websocket.send_json(message)
            except Exception:
                # Connection is dead, mark for removal
                dead_connections.append(websocket)
        
        # Clean up dead connections
        async with self._lock:
            for ws in dead_connections:
                if project_id in self._connections:
                    self._connections[project_id].discard(ws)
    
    def _get_watch_paths(self, project_path: Path) -> list:
        """Get the list of paths to watch for a project"""
        paths = []
        
        # Watch felix/state.json
        state_file = project_path / "felix" / "state.json"
        if state_file.exists():
            paths.append(state_file)
        else:
            # Watch felix/ directory in case state.json is created later
            felix_dir = project_path / "felix"
            if felix_dir.exists():
                paths.append(felix_dir)
        
        # Watch felix/requirements.json
        req_file = project_path / "felix" / "requirements.json"
        if req_file.exists():
            paths.append(req_file)
        
        # Watch runs/ directory
        runs_dir = project_path / "runs"
        if runs_dir.exists():
            paths.append(runs_dir)
        
        return paths
    
    async def _watch_project(self, project_id: str):
        """Watch a project's files for changes and broadcast updates"""
        project = storage.get_project_by_id(project_id)
        if not project:
            return
        
        project_path = Path(project.path)
        
        # Determine paths to watch
        # Watch the felix/ and runs/ directories
        felix_dir = project_path / "felix"
        runs_dir = project_path / "runs"
        
        watch_paths = []
        if felix_dir.exists():
            watch_paths.append(felix_dir)
        if runs_dir.exists():
            watch_paths.append(runs_dir)
        
        if not watch_paths:
            # Nothing to watch, wait and check again periodically
            while True:
                await asyncio.sleep(5)
                if felix_dir.exists():
                    watch_paths.append(felix_dir)
                    break
        
        try:
            async for changes in awatch(*watch_paths):
                await self._handle_changes(project_id, project_path, changes)
        except asyncio.CancelledError:
            # Watcher was cancelled, exit gracefully
            raise
        except Exception as e:
            # Log error but don't crash
            print(f"Error in file watcher for project {project_id}: {e}")
    
    async def _handle_changes(self, project_id: str, project_path: Path, 
                              changes: Set[tuple]):
        """Handle file changes and broadcast appropriate events"""
        for change_type, path_str in changes:
            path = Path(path_str)
            relative_path = path.relative_to(project_path) if path.is_relative_to(project_path) else path
            
            # Determine event type based on what changed
            event = await self._create_event(change_type, path, relative_path, project_path)
            if event:
                await self.broadcast(project_id, event)
    
    async def _create_event(self, change_type: Change, path: Path, 
                           relative_path: Path, project_path: Path) -> Optional[dict]:
        """Create an event message based on the file change"""
        path_parts = relative_path.parts
        timestamp = datetime.now().isoformat()
        
        # state.json changes
        if path_parts == ("felix", "state.json"):
            return await self._create_state_event(path, timestamp)
        
        # requirements.json changes
        if path_parts == ("felix", "requirements.json"):
            return await self._create_requirements_event(path, timestamp)
        
        # runs/ directory changes
        if len(path_parts) >= 1 and path_parts[0] == "runs":
            return await self._create_run_event(change_type, path, relative_path, timestamp)
        
        return None
    
    async def _create_state_event(self, path: Path, timestamp: str) -> Optional[dict]:
        """Create event for state.json changes"""
        try:
            if path.exists():
                content = json.loads(path.read_text())
                return {
                    "type": "state_update",
                    "timestamp": timestamp,
                    "data": content
                }
        except (json.JSONDecodeError, IOError):
            pass
        return None
    
    async def _create_requirements_event(self, path: Path, timestamp: str) -> Optional[dict]:
        """Create event for requirements.json changes"""
        try:
            if path.exists():
                content = json.loads(path.read_text())
                return {
                    "type": "requirements_update",
                    "timestamp": timestamp,
                    "data": content
                }
        except (json.JSONDecodeError, IOError):
            pass
        return None
    
    async def _create_run_event(self, change_type: Change, path: Path, 
                                relative_path: Path, timestamp: str) -> Optional[dict]:
        """Create event for runs/ directory changes"""
        path_parts = relative_path.parts
        
        # New run directory created
        if len(path_parts) == 2 and path.is_dir():
            run_id = path_parts[1]
            return {
                "type": "run_started" if change_type == Change.added else "run_updated",
                "timestamp": timestamp,
                "data": {
                    "run_id": run_id
                }
            }
        
        # Run artifact file created or modified
        if len(path_parts) >= 3:
            run_id = path_parts[1]
            artifact_name = "/".join(path_parts[2:])
            
            event_type = "run_artifact_created" if change_type == Change.added else "run_artifact_updated"
            
            data = {
                "run_id": run_id,
                "artifact": artifact_name
            }
            
            # For report.md, include content preview
            if artifact_name == "report.md" and path.exists():
                try:
                    content = path.read_text()
                    # Include first 500 chars as preview
                    data["preview"] = content[:500]
                except IOError:
                    pass
            
            return {
                "type": event_type,
                "timestamp": timestamp,
                "data": data
            }
        
        return None
    
    async def shutdown(self):
        """Shutdown all watchers and close connections"""
        async with self._lock:
            # Cancel all watchers
            for project_id, task in self._watchers.items():
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            
            # Close all connections
            for project_id, connections in self._connections.items():
                for ws in connections:
                    try:
                        await ws.close()
                    except Exception:
                        pass
            
            self._watchers.clear()
            self._connections.clear()


# Global connection manager instance
manager = ConnectionManager()


@router.websocket("/ws/projects/{project_id}")
async def websocket_endpoint(websocket: WebSocket, project_id: str):
    """
    WebSocket endpoint for real-time project updates.
    
    Clients connect to receive updates when:
    - felix/state.json changes (iteration_start, iteration_complete, mode_change, status_update)
    - felix/requirements.json changes (requirement status updates)
    - runs/ directory changes (new runs, run artifacts)
    
    Events are JSON objects with format:
    {
        "type": "state_update" | "requirements_update" | "run_started" | "run_artifact_created" | "run_artifact_updated",
        "timestamp": "ISO datetime",
        "data": { ... event-specific data ... }
    }
    """
    # Verify project exists
    project = storage.get_project_by_id(project_id)
    if not project:
        await websocket.close(code=4004, reason=f"Project not found: {project_id}")
        return
    
    await manager.connect(project_id, websocket)
    
    # Send initial state on connect
    await _send_initial_state(websocket, project_id)
    
    try:
        # Keep connection alive and handle any incoming messages
        while True:
            # Wait for messages (ping/pong or commands from client)
            try:
                data = await websocket.receive_text()
                # For now, we don't process incoming messages, just keep-alive
                # Could add commands like "refresh" or "subscribe_to_logs" later
            except WebSocketDisconnect:
                break
    except Exception:
        pass
    finally:
        await manager.disconnect(project_id, websocket)


async def _send_initial_state(websocket: WebSocket, project_id: str):
    """Send the current state when a client first connects"""
    project = storage.get_project_by_id(project_id)
    if not project:
        return
    
    project_path = Path(project.path)
    
    # Send current state.json if it exists
    state_file = project_path / "felix" / "state.json"
    if state_file.exists():
        try:
            content = json.loads(state_file.read_text())
            await websocket.send_json({
                "type": "initial_state",
                "timestamp": datetime.now().isoformat(),
                "data": content
            })
        except (json.JSONDecodeError, IOError):
            pass
    
    # Send current requirements.json if it exists
    req_file = project_path / "felix" / "requirements.json"
    if req_file.exists():
        try:
            content = json.loads(req_file.read_text())
            await websocket.send_json({
                "type": "initial_requirements",
                "timestamp": datetime.now().isoformat(),
                "data": content
            })
        except (json.JSONDecodeError, IOError):
            pass
    
    # Send list of existing runs
    runs_dir = project_path / "runs"
    if runs_dir.exists():
        runs = []
        for run_dir in sorted(runs_dir.iterdir(), reverse=True):
            if run_dir.is_dir():
                artifacts = [f.name for f in run_dir.iterdir() if f.is_file()]
                runs.append({
                    "run_id": run_dir.name,
                    "artifacts": artifacts
                })
        
        if runs:
            await websocket.send_json({
                "type": "initial_runs",
                "timestamp": datetime.now().isoformat(),
                "data": {"runs": runs[:10]}  # Send last 10 runs
            })


def get_connection_manager() -> ConnectionManager:
    """Get the global connection manager (for shutdown cleanup)"""
    return manager

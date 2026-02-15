"""
Tests for Console Streaming WebSocket (S-0041: Console Streaming WebSocket)

Tests for:
- WebSocket endpoint for streaming agent console output
- Query parameter handling (run_id, from_start)
- Error handling (missing run_id, file not found, file I/O errors)
- File tailing functionality (_tail_file)
"""
import pytest
from unittest.mock import patch, AsyncMock, MagicMock, PropertyMock
from pathlib import Path
import asyncio

from fastapi.testclient import TestClient

# Import the FastAPI app
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from routers.agents import _tail_file, _get_project_path_for_agent


class TestTailFile:
    """Tests for _tail_file helper function"""

    @pytest.mark.asyncio
    async def test_tail_file_nonexistent_returns_empty(self, tmp_path):
        """_tail_file returns empty string for non-existent file"""
        non_existent = tmp_path / "nonexistent.log"
        
        content, position, error = await _tail_file(non_existent, 0)
        
        assert content == ""
        assert position == 0
        assert error is None

    @pytest.mark.asyncio
    async def test_tail_file_reads_from_beginning(self, tmp_path):
        """_tail_file reads entire file when starting from position 0"""
        log_file = tmp_path / "test.log"
        test_content = "Line 1\nLine 2\nLine 3\n"
        log_file.write_text(test_content)
        
        content, position, error = await _tail_file(log_file, 0)
        
        # Content should match what we wrote
        assert content == test_content
        # Position should equal file size (may differ from len() due to line endings on Windows)
        assert position == log_file.stat().st_size
        assert error is None

    @pytest.mark.asyncio
    async def test_tail_file_reads_new_content_only(self, tmp_path):
        """_tail_file reads only new content from last position"""
        log_file = tmp_path / "test.log"
        log_file.write_text("Line 1\nLine 2\n")
        
        # First read
        content1, position1, error1 = await _tail_file(log_file, 0)
        assert error1 is None
        
        # Append more content
        with open(log_file, "a") as f:
            f.write("Line 3\n")
        
        # Second read from previous position
        content2, position2, error2 = await _tail_file(log_file, position1)
        
        assert content2 == "Line 3\n"
        assert position2 > position1
        assert error2 is None

    @pytest.mark.asyncio
    async def test_tail_file_handles_file_rotation(self, tmp_path):
        """_tail_file resets position when file is truncated/rotated"""
        log_file = tmp_path / "test.log"
        log_file.write_text("Original long content that will be replaced\n")
        
        # Get initial size
        initial_size = log_file.stat().st_size
        
        # Truncate the file (simulate rotation)
        log_file.write_text("New short content\n")
        
        # Read with old position (larger than new file size)
        content, position, error = await _tail_file(log_file, initial_size)
        
        # Should reset and read from beginning
        assert content == "New short content\n"
        assert error is None

    @pytest.mark.asyncio
    async def test_tail_file_returns_empty_when_no_new_content(self, tmp_path):
        """_tail_file returns empty string when at end of file"""
        log_file = tmp_path / "test.log"
        log_file.write_text("Line 1\n")
        
        # Read to end
        content1, position1, error1 = await _tail_file(log_file, 0)
        assert error1 is None
        
        # Read again from same position
        content2, position2, error2 = await _tail_file(log_file, position1)
        
        assert content2 == ""
        assert position2 == position1
        assert error2 is None


class TestConsoleWebSocketEndpoint:
    """Tests for the console WebSocket endpoint"""

    @pytest.fixture
    def client(self):
        """Create a test client"""
        return TestClient(app)

    @pytest.fixture
    def mock_project_path(self, tmp_path):
        """Mock _get_project_path_for_agent to return temp path"""
        with patch(
            "routers.agents._get_project_path_for_agent",
            new=AsyncMock(return_value=tmp_path),
        ):
            yield tmp_path

    def test_websocket_endpoint_exists_in_router(self):
        """WebSocket endpoint is registered in the agents router"""
        from routers.agents import router
        
        # Check that the /console websocket route exists
        routes = [route for route in router.routes if hasattr(route, 'path')]
        console_routes = [r for r in routes if '/console' in r.path]
        
        assert len(console_routes) > 0, "Console WebSocket route should be registered"

    def test_websocket_rejects_missing_run_id(self, client, mock_project_path):
        """WebSocket returns error when run_id is not provided"""
        with client.websocket_connect("/api/agents/1/console") as websocket:
            data = websocket.receive_json()
            assert "error" in data
            assert data["error"] == "run_id query parameter is required"

    def test_websocket_rejects_empty_run_id(self, client, mock_project_path):
        """WebSocket returns error when run_id is empty string"""
        with client.websocket_connect("/api/agents/1/console?run_id=") as websocket:
            data = websocket.receive_json()
            assert "error" in data
            assert data["error"] == "run_id query parameter is required"

    def test_websocket_rejects_nonexistent_log_file(self, client, mock_project_path):
        """WebSocket returns error when log file doesn't exist"""
        run_id = "nonexistent-run"
        
        with client.websocket_connect(f"/api/agents/1/console?run_id={run_id}") as websocket:
            data = websocket.receive_json()
            assert "error" in data
            assert f"Log file not found: runs/{run_id}/output.log" in data["error"]

    def test_websocket_connects_successfully_with_valid_run_id(self, client, mock_project_path):
        """WebSocket connects successfully with valid run_id and existing log file"""
        run_id = "test-run-001"
        
        # Create log file
        run_dir = mock_project_path / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        log_file = run_dir / "output.log"
        log_file.write_text("Initial log content\n")
        
        with client.websocket_connect(f"/api/agents/1/console?run_id={run_id}") as websocket:
            # Should receive connected message
            data = websocket.receive_json()
            assert data["type"] == "connected"
            assert data["run_id"] == run_id
            assert "Connected to console stream" in data["message"]

    def test_websocket_streams_from_end_by_default(self, client, mock_project_path):
        """WebSocket streams from end of file when from_start=false (default)"""
        run_id = "test-run-002"
        
        # Create log file with initial content
        run_dir = mock_project_path / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        log_file = run_dir / "output.log"
        log_file.write_text("Existing content that should not be sent\n")
        
        with client.websocket_connect(f"/api/agents/1/console?run_id={run_id}") as websocket:
            # Should receive connected message
            data = websocket.receive_json()
            assert data["type"] == "connected"
            
            # Append new content to log file
            with open(log_file, "a") as f:
                f.write("New content after connection\n")
            
            # Wait a bit for the poll
            import time
            time.sleep(0.2)
            
            # Should receive only the new content
            data = websocket.receive_json()
            assert data["type"] == "output"
            assert data["content"] == "New content after connection\n"
            assert "Existing content" not in data["content"]

    def test_websocket_streams_from_beginning_when_requested(self, client, mock_project_path):
        """WebSocket streams from beginning of file when from_start=true"""
        run_id = "test-run-003"
        
        # Create log file with initial content
        run_dir = mock_project_path / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        log_file = run_dir / "output.log"
        log_file.write_text("Existing content from beginning\n")
        
        with client.websocket_connect(f"/api/agents/1/console?run_id={run_id}&from_start=true") as websocket:
            # Should receive connected message
            data = websocket.receive_json()
            assert data["type"] == "connected"
            
            # Should receive existing content
            data = websocket.receive_json()
            assert data["type"] == "output"
            assert "Existing content from beginning" in data["content"]


class TestConsoleWebSocketNoProjectRegistered:
    """Tests for console WebSocket when no project is registered"""

    @pytest.fixture
    def client(self):
        """Create a test client"""
        return TestClient(app)

    def test_websocket_rejects_when_no_project_registered(self, client):
        """WebSocket returns error when no project is registered"""
        with patch(
            "routers.agents._get_project_path_for_agent",
            new=AsyncMock(return_value=None),
        ):
            with client.websocket_connect("/api/agents/1/console?run_id=test-run") as websocket:
                data = websocket.receive_json()
                assert "error" in data
                assert "No project registered" in data["error"]


class TestConsoleWebSocketMessageFormat:
    """Tests for WebSocket message format validation"""

    @pytest.fixture
    def client(self):
        """Create a test client"""
        return TestClient(app)

    @pytest.fixture
    def mock_project_path(self, tmp_path):
        """Mock _get_project_path_for_agent to return temp path"""
        with patch(
            "routers.agents._get_project_path_for_agent",
            new=AsyncMock(return_value=tmp_path),
        ):
            yield tmp_path

    def test_connected_message_format(self, client, mock_project_path):
        """Connected message has correct format"""
        run_id = "test-run-format"
        
        # Create log file
        run_dir = mock_project_path / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        log_file = run_dir / "output.log"
        log_file.write_text("")
        
        with client.websocket_connect(f"/api/agents/1/console?run_id={run_id}") as websocket:
            data = websocket.receive_json()
            
            # Verify message format
            assert "type" in data
            assert data["type"] == "connected"
            assert "agent_id" in data
            assert "message" in data
            assert "run_id" in data
            assert data["run_id"] == run_id

    def test_output_message_format(self, client, mock_project_path):
        """Output message has correct format"""
        run_id = "test-run-output"
        
        # Create log file with content
        run_dir = mock_project_path / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        log_file = run_dir / "output.log"
        log_file.write_text("Test output content\n")
        
        with client.websocket_connect(f"/api/agents/1/console?run_id={run_id}&from_start=true") as websocket:
            # Skip connected message
            websocket.receive_json()
            
            # Get output message
            data = websocket.receive_json()
            
            # Verify message format
            assert "type" in data
            assert data["type"] == "output"
            assert "content" in data
            assert "run_id" in data
            assert data["run_id"] == run_id

    def test_error_message_format(self, client, mock_project_path):
        """Error message has correct format"""
        with client.websocket_connect("/api/agents/1/console") as websocket:
            data = websocket.receive_json()
            
            # Verify error format (just "error" field, not "type": "error")
            assert "error" in data
            assert isinstance(data["error"], str)

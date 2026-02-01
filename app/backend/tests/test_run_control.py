"""
Tests for the Run Control API Endpoints (S-0040: Run Control API Endpoints)

Tests for:
- RunCreateRequest, RunResponse, RunListResponse model validation
- POST /api/agents/runs - create new run and send START command
- POST /api/agents/runs/{run_id}/stop - stop a running run
- GET /api/agents/runs - list runs with count
- GET /api/agents/runs/{run_id} - get run details
"""
import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from pathlib import Path
from fastapi.testclient import TestClient

# Import the FastAPI app and models
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from models import RunCreateRequest, RunResponse, RunListResponse


@pytest.fixture
def client():
    """Create a test client"""
    return TestClient(app)


# ============================================================================
# Pydantic Model Tests
# ============================================================================


class TestRunCreateRequestModel:
    """Tests for RunCreateRequest Pydantic model"""

    def test_run_create_request_with_required_fields(self):
        """RunCreateRequest model validates with required fields only"""
        request = RunCreateRequest(agent_id="550e8400-e29b-41d4-a716-446655440000")
        
        assert request.agent_id == "550e8400-e29b-41d4-a716-446655440000"
        assert request.requirement_id is None
        assert request.metadata == {}

    def test_run_create_request_with_all_fields(self):
        """RunCreateRequest model accepts all optional fields"""
        request = RunCreateRequest(
            agent_id="550e8400-e29b-41d4-a716-446655440000",
            requirement_id="S-0040",
            metadata={"iteration": 1, "mode": "building"}
        )
        
        assert request.agent_id == "550e8400-e29b-41d4-a716-446655440000"
        assert request.requirement_id == "S-0040"
        assert request.metadata == {"iteration": 1, "mode": "building"}

    def test_run_create_request_missing_agent_id_raises_error(self):
        """RunCreateRequest raises error when agent_id is missing"""
        with pytest.raises(ValueError):
            RunCreateRequest()


class TestRunResponseModel:
    """Tests for RunResponse Pydantic model"""

    def test_run_response_with_required_fields(self):
        """RunResponse model validates with required fields"""
        response = RunResponse(
            id="run-001",
            project_id="proj-001",
            agent_id="agent-001",
            status="running",
            metadata={}
        )
        
        assert response.id == "run-001"
        assert response.project_id == "proj-001"
        assert response.agent_id == "agent-001"
        assert response.status == "running"
        assert response.requirement_id is None
        assert response.started_at is None
        assert response.completed_at is None
        assert response.error is None
        assert response.agent_name is None

    def test_run_response_with_all_fields(self):
        """RunResponse model accepts all optional fields"""
        from datetime import datetime
        
        now = datetime.now()
        response = RunResponse(
            id="run-001",
            project_id="proj-001",
            agent_id="agent-001",
            requirement_id="S-0040",
            status="completed",
            started_at=now,
            completed_at=now,
            error=None,
            metadata={"result": "success"},
            agent_name="Test Agent"
        )
        
        assert response.requirement_id == "S-0040"
        assert response.started_at == now
        assert response.completed_at == now
        assert response.metadata == {"result": "success"}
        assert response.agent_name == "Test Agent"


class TestRunListResponseModel:
    """Tests for RunListResponse Pydantic model"""

    def test_run_list_response_with_empty_list(self):
        """RunListResponse model validates with empty list"""
        response = RunListResponse(runs=[], count=0)
        
        assert response.runs == []
        assert response.count == 0

    def test_run_list_response_with_runs(self):
        """RunListResponse model accepts list of RunResponse objects"""
        run1 = RunResponse(
            id="run-001",
            project_id="proj-001",
            agent_id="agent-001",
            status="running",
            metadata={}
        )
        run2 = RunResponse(
            id="run-002",
            project_id="proj-001",
            agent_id="agent-002",
            status="completed",
            metadata={}
        )
        
        response = RunListResponse(runs=[run1, run2], count=2)
        
        assert len(response.runs) == 2
        assert response.count == 2
        assert response.runs[0].id == "run-001"
        assert response.runs[1].id == "run-002"


# ============================================================================
# Create Run Endpoint Tests
# ============================================================================


class TestCreateRunEndpoint:
    """Tests for POST /api/agents/runs endpoint"""

    @pytest.fixture
    def mock_agent_record(self):
        """Create a mock agent record"""
        return {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "project_id": "dev-project-id",
            "name": "Test Agent",
            "type": "ralph",
            "status": "idle",
            "heartbeat_at": "2026-01-01T00:00:00Z",
            "metadata": {},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        }

    @pytest.fixture
    def mock_run_record(self):
        """Create a mock run record"""
        return {
            "id": "660e8400-e29b-41d4-a716-446655440000",
            "project_id": "dev-project-id",
            "agent_id": "550e8400-e29b-41d4-a716-446655440000",
            "requirement_id": "S-0040",
            "status": "running",
            "started_at": "2026-01-01T00:00:00Z",
            "completed_at": None,
            "error": None,
            "metadata": {"iteration": 1},
        }

    @pytest.fixture
    def mock_db(self):
        """Mock database dependency"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    @pytest.fixture
    def mock_auth(self):
        """Mock authentication dependency"""
        with patch('routers.agents.get_current_user', return_value={"user_id": "dev-user"}):
            yield

    def test_create_run_success(self, client, mock_db, mock_auth, mock_agent_record, mock_run_record):
        """POST /api/agents/runs creates run and returns 201"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter, \
             patch('routers.agents.RunWriter') as MockRunWriter, \
             patch('routers.agents.control_manager') as mock_control:
            
            # Setup agent writer mock
            mock_agent_writer = MagicMock()
            MockAgentWriter.return_value = mock_agent_writer
            mock_agent_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            
            # Setup run writer mock
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.create_run = AsyncMock(return_value=mock_run_record)
            mock_run_writer.update_run_status = AsyncMock(return_value=None)
            mock_run_writer.get_run = AsyncMock(return_value=mock_run_record)
            
            # Setup control manager mock
            mock_control.is_connected.return_value = True
            mock_control.send_command = AsyncMock(return_value=None)
            
            response = client.post(
                "/api/agents/runs",
                json={
                    "agent_id": "550e8400-e29b-41d4-a716-446655440000",
                    "requirement_id": "S-0040",
                    "metadata": {"iteration": 1}
                }
            )
            
            assert response.status_code == 201
            data = response.json()
            assert data["id"] == "660e8400-e29b-41d4-a716-446655440000"
            assert data["agent_id"] == "550e8400-e29b-41d4-a716-446655440000"
            assert data["status"] == "running"
            assert data["agent_name"] == "Test Agent"

    def test_create_run_agent_not_found(self, client, mock_db, mock_auth):
        """POST /api/agents/runs returns 404 when agent not found"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_agent_writer = MagicMock()
            MockAgentWriter.return_value = mock_agent_writer
            mock_agent_writer.get_agent = AsyncMock(return_value=None)
            
            response = client.post(
                "/api/agents/runs",
                json={
                    "agent_id": "nonexistent-agent-id"
                }
            )
            
            assert response.status_code == 404
            assert "Agent not found" in response.json()["detail"]

    def test_create_run_agent_not_connected(self, client, mock_db, mock_auth, mock_agent_record):
        """POST /api/agents/runs returns 503 when agent not connected"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter, \
             patch('routers.agents.control_manager') as mock_control:
            
            # Setup agent writer mock
            mock_agent_writer = MagicMock()
            MockAgentWriter.return_value = mock_agent_writer
            mock_agent_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            
            # Agent not connected
            mock_control.is_connected.return_value = False
            
            response = client.post(
                "/api/agents/runs",
                json={
                    "agent_id": "550e8400-e29b-41d4-a716-446655440000"
                }
            )
            
            assert response.status_code == 503
            assert "Agent not connected" in response.json()["detail"]

    def test_create_run_missing_agent_id(self, client, mock_db, mock_auth):
        """POST /api/agents/runs returns 422 when agent_id is missing"""
        response = client.post(
            "/api/agents/runs",
            json={}
        )
        
        assert response.status_code == 422

    def test_create_run_database_error(self, client, mock_db, mock_auth, mock_agent_record):
        """POST /api/agents/runs returns 500 on database error"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter, \
             patch('routers.agents.RunWriter') as MockRunWriter, \
             patch('routers.agents.control_manager') as mock_control:
            
            # Setup agent writer mock
            mock_agent_writer = MagicMock()
            MockAgentWriter.return_value = mock_agent_writer
            mock_agent_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            
            # Setup run writer mock to fail
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.create_run = AsyncMock(side_effect=Exception("Database connection failed"))
            
            # Agent is connected
            mock_control.is_connected.return_value = True
            
            response = client.post(
                "/api/agents/runs",
                json={
                    "agent_id": "550e8400-e29b-41d4-a716-446655440000"
                }
            )
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


# ============================================================================
# Stop Run Endpoint Tests
# ============================================================================


class TestStopRunEndpoint:
    """Tests for POST /api/agents/runs/{run_id}/stop endpoint"""

    @pytest.fixture
    def mock_run_record(self):
        """Create a mock run record"""
        return {
            "id": "660e8400-e29b-41d4-a716-446655440000",
            "project_id": "dev-project-id",
            "agent_id": "550e8400-e29b-41d4-a716-446655440000",
            "requirement_id": "S-0040",
            "status": "running",
            "started_at": "2026-01-01T00:00:00Z",
            "completed_at": None,
            "error": None,
            "metadata": {},
        }

    @pytest.fixture
    def mock_db(self):
        """Mock database dependency"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_stop_run_success(self, client, mock_db, mock_run_record):
        """POST /api/agents/runs/{run_id}/stop returns 200 on success"""
        with patch('routers.agents.RunWriter') as MockRunWriter, \
             patch('routers.agents.control_manager') as mock_control:
            
            # Setup run writer mock
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(return_value=mock_run_record)
            
            # Setup control manager mock
            mock_control.is_connected.return_value = True
            mock_control.send_command = AsyncMock(return_value=None)
            
            response = client.post("/api/agents/runs/660e8400-e29b-41d4-a716-446655440000/stop")
            
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "ok"
            assert data["run_id"] == "660e8400-e29b-41d4-a716-446655440000"
            assert data["message"] == "STOP command sent"

    def test_stop_run_not_found(self, client, mock_db):
        """POST /api/agents/runs/{run_id}/stop returns 404 when run not found"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(return_value=None)
            
            response = client.post("/api/agents/runs/nonexistent-run-id/stop")
            
            assert response.status_code == 404
            assert "Run not found" in response.json()["detail"]

    def test_stop_run_agent_not_connected(self, client, mock_db, mock_run_record):
        """POST /api/agents/runs/{run_id}/stop returns 503 when agent not connected"""
        with patch('routers.agents.RunWriter') as MockRunWriter, \
             patch('routers.agents.control_manager') as mock_control:
            
            # Setup run writer mock
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(return_value=mock_run_record)
            
            # Agent not connected
            mock_control.is_connected.return_value = False
            
            response = client.post("/api/agents/runs/660e8400-e29b-41d4-a716-446655440000/stop")
            
            assert response.status_code == 503
            assert "Agent not connected" in response.json()["detail"]

    def test_stop_run_database_error(self, client, mock_db):
        """POST /api/agents/runs/{run_id}/stop returns 500 on database error"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.post("/api/agents/runs/660e8400-e29b-41d4-a716-446655440000/stop")
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


# ============================================================================
# List Runs Endpoint Tests
# ============================================================================


class TestListRunsEndpoint:
    """Tests for GET /api/agents/runs endpoint"""

    @pytest.fixture
    def mock_runs_list(self):
        """Create a mock list of runs"""
        return [
            {
                "id": "run-001",
                "project_id": "dev-project-id",
                "agent_id": "agent-001",
                "requirement_id": "S-0040",
                "status": "running",
                "started_at": "2026-01-01T12:00:00Z",
                "completed_at": None,
                "error": None,
                "metadata": {},
                "agent_name": "Agent 1",
            },
            {
                "id": "run-002",
                "project_id": "dev-project-id",
                "agent_id": "agent-002",
                "requirement_id": "S-0039",
                "status": "completed",
                "started_at": "2026-01-01T11:00:00Z",
                "completed_at": "2026-01-01T11:30:00Z",
                "error": None,
                "metadata": {"result": "success"},
                "agent_name": "Agent 2",
            },
        ]

    @pytest.fixture
    def mock_run_writer_list(self, mock_runs_list):
        """Create a mock RunWriter for list operations"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_writer = MagicMock()
            MockRunWriter.return_value = mock_writer
            mock_writer.list_runs = AsyncMock(return_value=mock_runs_list)
            yield mock_writer

    @pytest.fixture
    def mock_run_writer_list_empty(self):
        """Create a mock RunWriter that returns empty list"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_writer = MagicMock()
            MockRunWriter.return_value = mock_writer
            mock_writer.list_runs = AsyncMock(return_value=[])
            yield mock_writer

    @pytest.fixture
    def mock_db_list(self):
        """Mock database dependency for list tests"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_list_runs_success(self, client, mock_run_writer_list, mock_db_list):
        """GET /api/agents/runs returns list with count"""
        response = client.get("/api/agents/runs")
        
        assert response.status_code == 200
        data = response.json()
        assert "runs" in data
        assert "count" in data
        assert data["count"] == 2
        assert len(data["runs"]) == 2
        
        # Verify first run
        run_1 = data["runs"][0]
        assert run_1["id"] == "run-001"
        assert run_1["status"] == "running"
        assert run_1["agent_name"] == "Agent 1"

    def test_list_runs_empty(self, client, mock_run_writer_list_empty, mock_db_list):
        """GET /api/agents/runs returns empty list when no runs"""
        response = client.get("/api/agents/runs")
        
        assert response.status_code == 200
        data = response.json()
        assert data["runs"] == []
        assert data["count"] == 0

    def test_list_runs_with_limit_parameter(self, client, mock_runs_list, mock_db_list):
        """GET /api/agents/runs respects limit query parameter"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_writer = MagicMock()
            MockRunWriter.return_value = mock_writer
            mock_writer.list_runs = AsyncMock(return_value=[mock_runs_list[0]])
            
            response = client.get("/api/agents/runs?limit=1")
            
            assert response.status_code == 200
            data = response.json()
            assert data["count"] == 1
            
            # Verify list_runs was called with limit parameter
            mock_writer.list_runs.assert_called_once()
            call_args = mock_writer.list_runs.call_args
            assert call_args.kwargs.get("limit") == 1

    def test_list_runs_database_error(self, client, mock_db_list):
        """GET /api/agents/runs returns 500 on database error"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_writer = MagicMock()
            MockRunWriter.return_value = mock_writer
            mock_writer.list_runs = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.get("/api/agents/runs")
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


# ============================================================================
# Get Run Endpoint Tests
# ============================================================================


class TestGetRunEndpoint:
    """Tests for GET /api/agents/runs/{run_id} endpoint"""

    @pytest.fixture
    def mock_run_record(self):
        """Create a mock run record"""
        return {
            "id": "660e8400-e29b-41d4-a716-446655440000",
            "project_id": "dev-project-id",
            "agent_id": "550e8400-e29b-41d4-a716-446655440000",
            "requirement_id": "S-0040",
            "status": "running",
            "started_at": "2026-01-01T00:00:00Z",
            "completed_at": None,
            "error": None,
            "metadata": {"iteration": 1},
        }

    @pytest.fixture
    def mock_agent_record(self):
        """Create a mock agent record"""
        return {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "project_id": "dev-project-id",
            "name": "Test Agent",
            "type": "ralph",
            "status": "running",
            "heartbeat_at": "2026-01-01T00:00:00Z",
            "metadata": {},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        }

    @pytest.fixture
    def mock_db(self):
        """Mock database dependency"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_get_run_success(self, client, mock_db, mock_run_record, mock_agent_record):
        """GET /api/agents/runs/{run_id} returns run details"""
        with patch('routers.agents.RunWriter') as MockRunWriter, \
             patch('routers.agents.AgentWriter') as MockAgentWriter:
            
            # Setup run writer mock
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(return_value=mock_run_record)
            
            # Setup agent writer mock
            mock_agent_writer = MagicMock()
            MockAgentWriter.return_value = mock_agent_writer
            mock_agent_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            
            response = client.get("/api/agents/runs/660e8400-e29b-41d4-a716-446655440000")
            
            assert response.status_code == 200
            data = response.json()
            assert data["id"] == "660e8400-e29b-41d4-a716-446655440000"
            assert data["agent_id"] == "550e8400-e29b-41d4-a716-446655440000"
            assert data["requirement_id"] == "S-0040"
            assert data["status"] == "running"
            assert data["agent_name"] == "Test Agent"
            assert data["metadata"] == {"iteration": 1}

    def test_get_run_not_found(self, client, mock_db):
        """GET /api/agents/runs/{run_id} returns 404 when run not found"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(return_value=None)
            
            response = client.get("/api/agents/runs/nonexistent-run-id")
            
            assert response.status_code == 404
            assert "Run not found" in response.json()["detail"]

    def test_get_run_database_error(self, client, mock_db):
        """GET /api/agents/runs/{run_id} returns 500 on database error"""
        with patch('routers.agents.RunWriter') as MockRunWriter:
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.get("/api/agents/runs/660e8400-e29b-41d4-a716-446655440000")
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]

    def test_get_run_with_missing_agent(self, client, mock_db, mock_run_record):
        """GET /api/agents/runs/{run_id} works when agent is deleted"""
        with patch('routers.agents.RunWriter') as MockRunWriter, \
             patch('routers.agents.AgentWriter') as MockAgentWriter:
            
            # Setup run writer mock
            mock_run_writer = MagicMock()
            MockRunWriter.return_value = mock_run_writer
            mock_run_writer.get_run = AsyncMock(return_value=mock_run_record)
            
            # Setup agent writer mock - agent not found
            mock_agent_writer = MagicMock()
            MockAgentWriter.return_value = mock_agent_writer
            mock_agent_writer.get_agent = AsyncMock(return_value=None)
            
            response = client.get("/api/agents/runs/660e8400-e29b-41d4-a716-446655440000")
            
            assert response.status_code == 200
            data = response.json()
            assert data["id"] == "660e8400-e29b-41d4-a716-446655440000"
            assert data["agent_name"] is None  # Agent not found, so name is None

"""
Tests for the Agent Registry API (S-0013: Agent Settings Registry)

NOTE: S-0032 - File-based agent registry has been removed.
Database-backed endpoints implemented in S-0038:
- POST /api/agents/register -> Database-backed agent registration
- POST /api/agents/{id}/heartbeat -> Database-backed heartbeat update
- POST /api/agents/{id}/stop -> 501 Not Implemented (stubbed)
- POST /api/agents/{id}/start -> 501 Not Implemented (stubbed)
- GET /api/agents -> Returns {"agents": {}}

The following functionality is preserved:
- GET /api/agents/config -> Returns agent configurations from global ~/.felix/agents.json
- GET /api/agents/workflow-config -> Returns workflow configuration
- WebSocket /api/agents/{id}/console -> Console streaming from runs/ directory
"""
import json
import pytest
from pathlib import Path
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient

# Import the FastAPI app and router
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from routers.agents import AgentEntry


@pytest.fixture
def client():
    """Create a test client"""
    return TestClient(app)


class TestRegisterAgentEndpoint:
    """Tests for POST /api/agents/register endpoint (S-0038)"""

    @pytest.fixture
    def mock_agent_writer(self):
        """Create a mock AgentWriter that returns a valid agent record"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            # Create mock instance
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            
            # Mock upsert_agent to return a valid agent record
            mock_agent_record = {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "project_id": "dev-project-id",
                "name": "Test Agent",
                "type": "ralph",
                "status": "idle",
                "heartbeat_at": None,
                "metadata": {"version": "1.0"},
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:00Z",
            }
            mock_writer.upsert_agent = AsyncMock(return_value=mock_agent_record)
            
            yield mock_writer

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

    def test_register_agent_success(self, client, mock_agent_writer, mock_db, mock_auth):
        """POST /api/agents/register creates agent and returns 201"""
        response = client.post(
            "/api/agents/register",
            json={
                "agent_id": "550e8400-e29b-41d4-a716-446655440000",
                "name": "Test Agent",
                "type": "ralph",
                "metadata": {"version": "1.0"}
            }
        )
        
        assert response.status_code == 201
        data = response.json()
        assert data["id"] == "550e8400-e29b-41d4-a716-446655440000"
        assert data["name"] == "Test Agent"
        assert data["type"] == "ralph"
        assert data["status"] == "idle"

    def test_register_agent_with_default_type(self, client, mock_agent_writer, mock_db, mock_auth):
        """POST /api/agents/register uses default type when not specified"""
        response = client.post(
            "/api/agents/register",
            json={
                "agent_id": "550e8400-e29b-41d4-a716-446655440000",
                "name": "Test Agent",
            }
        )
        
        assert response.status_code == 201

    def test_register_agent_missing_required_fields(self, client, mock_db, mock_auth):
        """POST /api/agents/register returns 422 when required fields are missing"""
        response = client.post(
            "/api/agents/register",
            json={
                "name": "Test Agent",
                # Missing agent_id
            }
        )
        
        assert response.status_code == 422

    def test_register_agent_database_error(self, client, mock_db, mock_auth):
        """POST /api/agents/register returns 500 on database error"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.upsert_agent = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.post(
                "/api/agents/register",
                json={
                    "agent_id": "550e8400-e29b-41d4-a716-446655440000",
                    "name": "Test Agent",
                }
            )
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


class TestHeartbeatEndpoint:
    """Tests for POST /api/agents/{agent_id}/heartbeat endpoint (S-0038)"""

    @pytest.fixture
    def mock_agent_writer_heartbeat(self):
        """Create a mock AgentWriter for heartbeat operations"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            
            # Mock get_agent to return a valid agent (agent exists)
            mock_agent_record = {
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
            mock_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            mock_writer.update_heartbeat = AsyncMock(return_value=None)
            
            yield mock_writer

    @pytest.fixture
    def mock_db_heartbeat(self):
        """Mock database dependency for heartbeat tests"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_heartbeat_success(self, client, mock_agent_writer_heartbeat, mock_db_heartbeat):
        """POST /api/agents/{agent_id}/heartbeat updates heartbeat and returns 200"""
        response = client.post(
            "/api/agents/550e8400-e29b-41d4-a716-446655440000/heartbeat"
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["agent_id"] == "550e8400-e29b-41d4-a716-446655440000"

    def test_heartbeat_agent_not_found(self, client, mock_db_heartbeat):
        """POST /api/agents/{agent_id}/heartbeat returns 404 for nonexistent agent"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.get_agent = AsyncMock(return_value=None)
            
            response = client.post(
                "/api/agents/nonexistent-agent-id/heartbeat"
            )
            
            assert response.status_code == 404
            assert "Agent not found" in response.json()["detail"]

    def test_heartbeat_database_error(self, client, mock_db_heartbeat):
        """POST /api/agents/{agent_id}/heartbeat returns 500 on database error"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.get_agent = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.post(
                "/api/agents/550e8400-e29b-41d4-a716-446655440000/heartbeat"
            )
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


class TestStatusUpdateEndpoint:
    """Tests for POST /api/agents/{agent_id}/status endpoint (S-0038)"""

    @pytest.fixture
    def mock_agent_writer_status(self):
        """Create a mock AgentWriter for status update operations"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            
            # Mock get_agent to return a valid agent (agent exists)
            mock_agent_record = {
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
            mock_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            mock_writer.update_status = AsyncMock(return_value=None)
            
            yield mock_writer

    @pytest.fixture
    def mock_db_status(self):
        """Mock database dependency for status tests"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_status_update_success(self, client, mock_agent_writer_status, mock_db_status):
        """POST /api/agents/{agent_id}/status updates status and returns 200"""
        response = client.post(
            "/api/agents/550e8400-e29b-41d4-a716-446655440000/status",
            json={"status": "running"}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["agent_id"] == "550e8400-e29b-41d4-a716-446655440000"
        assert data["new_status"] == "running"

    def test_status_update_agent_not_found(self, client, mock_db_status):
        """POST /api/agents/{agent_id}/status returns 404 for nonexistent agent"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.get_agent = AsyncMock(return_value=None)
            
            response = client.post(
                "/api/agents/nonexistent-agent-id/status",
                json={"status": "running"}
            )
            
            assert response.status_code == 404
            assert "Agent not found" in response.json()["detail"]

    def test_status_update_invalid_status(self, client, mock_agent_writer_status, mock_db_status):
        """POST /api/agents/{agent_id}/status returns 400 for invalid status"""
        response = client.post(
            "/api/agents/550e8400-e29b-41d4-a716-446655440000/status",
            json={"status": "invalid_status"}
        )
        
        assert response.status_code == 400
        assert "Invalid status" in response.json()["detail"]

    def test_status_update_database_error(self, client, mock_db_status):
        """POST /api/agents/{agent_id}/status returns 500 on database error"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.get_agent = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.post(
                "/api/agents/550e8400-e29b-41d4-a716-446655440000/status",
                json={"status": "running"}
            )
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


class TestListAgentsEndpoint:
    """Tests for GET /api/agents endpoint (S-0038)"""

    @pytest.fixture
    def mock_agent_writer_list(self):
        """Create a mock AgentWriter for list operations"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            
            # Mock list_agents to return a list of agents
            mock_agents_list = [
                {
                    "id": "550e8400-e29b-41d4-a716-446655440000",
                    "project_id": "dev-project-id",
                    "name": "Test Agent 1",
                    "type": "ralph",
                    "status": "idle",
                    "heartbeat_at": "2026-01-01T00:00:00Z",
                    "metadata": {"version": "1.0"},
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z",
                },
                {
                    "id": "550e8400-e29b-41d4-a716-446655440001",
                    "project_id": "dev-project-id",
                    "name": "Test Agent 2",
                    "type": "droid",
                    "status": "running",
                    "heartbeat_at": "2026-01-01T00:00:00Z",
                    "metadata": {},
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z",
                },
            ]
            mock_writer.list_agents = AsyncMock(return_value=mock_agents_list)
            
            yield mock_writer

    @pytest.fixture
    def mock_agent_writer_list_empty(self):
        """Create a mock AgentWriter that returns empty list"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.list_agents = AsyncMock(return_value=[])
            
            yield mock_writer

    @pytest.fixture
    def mock_db_list(self):
        """Mock database dependency for list tests"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_list_agents_success(self, client, mock_agent_writer_list, mock_db_list):
        """GET /api/agents returns list of agents with count"""
        response = client.get("/api/agents")
        
        assert response.status_code == 200
        data = response.json()
        assert "agents" in data
        assert "count" in data
        assert data["count"] == 2
        assert len(data["agents"]) == 2
        
        # Verify first agent
        agent_1 = data["agents"][0]
        assert agent_1["id"] == "550e8400-e29b-41d4-a716-446655440000"
        assert agent_1["name"] == "Test Agent 1"
        assert agent_1["type"] == "ralph"
        assert agent_1["status"] == "idle"

    def test_list_agents_empty(self, client, mock_agent_writer_list_empty, mock_db_list):
        """GET /api/agents returns empty list when no agents"""
        response = client.get("/api/agents")
        
        assert response.status_code == 200
        data = response.json()
        assert data["agents"] == []
        assert data["count"] == 0

    def test_list_agents_database_error(self, client, mock_db_list):
        """GET /api/agents returns 500 on database error"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.list_agents = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.get("/api/agents")
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


class TestGetAgentEndpoint:
    """Tests for GET /api/agents/{agent_id} endpoint (S-0038)"""

    @pytest.fixture
    def mock_agent_writer_get(self):
        """Create a mock AgentWriter for get agent operations"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            
            # Mock get_agent to return a valid agent
            mock_agent_record = {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "project_id": "dev-project-id",
                "name": "Test Agent",
                "type": "ralph",
                "status": "idle",
                "heartbeat_at": "2026-01-01T00:00:00Z",
                "metadata": {"version": "1.0"},
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:00Z",
            }
            mock_writer.get_agent = AsyncMock(return_value=mock_agent_record)
            
            yield mock_writer

    @pytest.fixture
    def mock_db_get(self):
        """Mock database dependency for get agent tests"""
        mock_database = MagicMock()
        with patch('routers.agents.get_db', return_value=mock_database):
            yield mock_database

    def test_get_agent_success(self, client, mock_agent_writer_get, mock_db_get):
        """GET /api/agents/{agent_id} returns agent data"""
        response = client.get("/api/agents/550e8400-e29b-41d4-a716-446655440000")
        
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == "550e8400-e29b-41d4-a716-446655440000"
        assert data["name"] == "Test Agent"
        assert data["type"] == "ralph"
        assert data["status"] == "idle"
        assert data["project_id"] == "dev-project-id"
        assert data["metadata"] == {"version": "1.0"}

    def test_get_agent_not_found(self, client, mock_db_get):
        """GET /api/agents/{agent_id} returns 404 for nonexistent agent"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.get_agent = AsyncMock(return_value=None)
            
            response = client.get("/api/agents/nonexistent-agent-id")
            
            assert response.status_code == 404
            assert "Agent not found" in response.json()["detail"]

    def test_get_agent_database_error(self, client, mock_db_get):
        """GET /api/agents/{agent_id} returns 500 on database error"""
        with patch('routers.agents.AgentWriter') as MockAgentWriter:
            mock_writer = MagicMock()
            MockAgentWriter.return_value = mock_writer
            mock_writer.get_agent = AsyncMock(side_effect=Exception("Database connection failed"))
            
            response = client.get("/api/agents/550e8400-e29b-41d4-a716-446655440000")
            
            assert response.status_code == 500
            assert "Database error" in response.json()["detail"]


class TestStubbedEndpoints:
    """Tests for remaining stubbed agent registry endpoints (S-0032)"""

    def test_stop_agent_returns_501(self, client):
        """POST /api/agents/{id}/stop returns 501 Not Implemented"""
        response = client.post("/api/agents/0/stop")
        
        assert response.status_code == 501
        assert "temporarily disabled" in response.json()["detail"]

    def test_start_agent_returns_501(self, client):
        """POST /api/agents/{id}/start returns 501 Not Implemented"""
        response = client.post(
            "/api/agents/0/start",
            json={"requirement_id": "S-0001"}
        )
        
        assert response.status_code == 501
        assert "temporarily disabled" in response.json()["detail"]


class TestAgentEntryModel:
    """Tests for AgentEntry model - still used for type definitions"""

    def test_agent_entry_model_fields(self):
        """AgentEntry model has all required fields"""
        agent = AgentEntry(
            agent_id=0,
            agent_name="test-agent",
            pid=12345,
            hostname="test-host",
            status="active"
        )
        
        assert agent.agent_id == 0
        assert agent.agent_name == "test-agent"
        assert agent.pid == 12345
        assert agent.hostname == "test-host"
        assert agent.status == "active"

    def test_agent_entry_model_optional_fields(self):
        """AgentEntry model handles optional fields"""
        agent = AgentEntry(
            agent_id=1,
            agent_name="test-agent-2",
            pid=99999,
            hostname="host2",
            status="active",
            current_run_id="S-0030",
            started_at="2026-01-29T12:00:00Z",
            last_heartbeat="2026-01-29T12:05:00Z",
            current_workflow_stage="execute_llm",
            workflow_stage_timestamp="2026-01-29T12:00:00Z"
        )
        
        assert agent.current_run_id == "S-0030"
        assert agent.started_at == "2026-01-29T12:00:00Z"
        assert agent.last_heartbeat == "2026-01-29T12:05:00Z"
        assert agent.current_workflow_stage == "execute_llm"
        assert agent.workflow_stage_timestamp == "2026-01-29T12:00:00Z"


class TestGetAgentsConfig:
    """Tests for GET /api/agents/config endpoint (S-0021: Agent Orchestration Enhancement)"""

    @pytest.fixture
    def mock_felix_home_with_agents(self, tmp_path):
        """Create a temporary felix home directory with agents.json"""
        felix_home = tmp_path / ".felix"
        felix_home.mkdir(parents=True, exist_ok=True)
        
        agents_file = felix_home / "agents.json"
        agents_data = {
            "agents": [
                {
                    "id": 0,
                    "name": "felix-primary",
                    "executable": "droid",
                    "args": ["exec", "--skip-permissions-unsafe"],
                    "working_directory": ".",
                    "environment": {}
                },
                {
                    "id": 1,
                    "name": "test-agent",
                    "executable": "claude",
                    "args": ["--model", "opus"],
                    "working_directory": "/custom/path",
                    "environment": {"API_KEY": "test123"}
                }
            ]
        }
        agents_file.write_text(json.dumps(agents_data, indent=2), encoding='utf-8')
        
        return felix_home

    @pytest.fixture
    def mock_storage_felix_home(self, mock_felix_home_with_agents):
        """Patch storage.get_felix_home to use temporary directory"""
        with patch('storage.get_felix_home', return_value=mock_felix_home_with_agents):
            with patch('routers.agents.storage.get_felix_home', return_value=mock_felix_home_with_agents):
                yield mock_felix_home_with_agents

    def test_get_agents_config_returns_all_configured_agents(self, client, mock_storage_felix_home):
        """Get agents config returns all configured agents from agents.json"""
        response = client.get("/api/agents/config")
        assert response.status_code == 200
        
        data = response.json()
        assert "agents" in data
        assert len(data["agents"]) == 2
        
        # Verify first agent (system default)
        agent_0 = next(a for a in data["agents"] if a["id"] == 0)
        assert agent_0["name"] == "felix-primary"
        assert agent_0["executable"] == "droid"
        assert "exec" in agent_0["args"]
        
        # Verify second agent
        agent_1 = next(a for a in data["agents"] if a["id"] == 1)
        assert agent_1["name"] == "test-agent"
        assert agent_1["executable"] == "claude"
        assert agent_1["args"] == ["--model", "opus"]
        assert agent_1["working_directory"] == "/custom/path"
        assert agent_1["environment"]["API_KEY"] == "test123"

    def test_get_agents_config_returns_default_when_file_missing(self, client, tmp_path):
        """Returns default agent when agents.json doesn't exist"""
        # Create empty felix home without agents.json
        felix_home = tmp_path / ".felix_empty"
        felix_home.mkdir(parents=True, exist_ok=True)
        
        with patch('storage.get_felix_home', return_value=felix_home):
            with patch('routers.agents.storage.get_felix_home', return_value=felix_home):
                response = client.get("/api/agents/config")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should return default agent
        assert len(data["agents"]) == 1
        assert data["agents"][0]["id"] == 0
        assert data["agents"][0]["name"] == "felix-primary"
        assert data["agents"][0]["executable"] == "droid"

    def test_get_agents_config_handles_malformed_json(self, client, tmp_path):
        """Returns default agent when agents.json is malformed"""
        felix_home = tmp_path / ".felix_malformed"
        felix_home.mkdir(parents=True, exist_ok=True)
        
        agents_file = felix_home / "agents.json"
        agents_file.write_text("not valid json {{{", encoding='utf-8')
        
        with patch('storage.get_felix_home', return_value=felix_home):
            with patch('routers.agents.storage.get_felix_home', return_value=felix_home):
                response = client.get("/api/agents/config")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should return default agent on parse error
        assert len(data["agents"]) == 1
        assert data["agents"][0]["id"] == 0
        assert data["agents"][0]["name"] == "felix-primary"

    def test_get_agents_config_response_schema(self, client, mock_storage_felix_home):
        """Verify response matches expected schema for frontend merge"""
        response = client.get("/api/agents/config")
        assert response.status_code == 200
        
        data = response.json()
        
        # Verify schema for each agent matches MergedAgent requirements
        for agent in data["agents"]:
            assert "id" in agent
            assert "name" in agent
            assert "executable" in agent
            assert "args" in agent
            assert "working_directory" in agent
            assert "environment" in agent
            assert isinstance(agent["id"], int)
            assert isinstance(agent["name"], str)
            assert isinstance(agent["executable"], str)
            assert isinstance(agent["args"], list)
            assert isinstance(agent["working_directory"], str)
            assert isinstance(agent["environment"], dict)


class TestGetWorkflowConfig:
    """Tests for GET /api/agents/workflow-config endpoint (S-0030: Agent Workflow Visualization)"""

    @pytest.fixture
    def mock_project_with_workflow(self, tmp_path):
        """Create a temporary project with workflow.json"""
        project_path = tmp_path / "test-project"
        project_path.mkdir(parents=True, exist_ok=True)
        
        # Create required Felix structure
        (project_path / "felix").mkdir(exist_ok=True)
        (project_path / "specs").mkdir(exist_ok=True)
        
        # Create workflow.json
        workflow_data = {
            "version": "2.0",
            "layout": "vertical",
            "stages": [
                {
                    "id": "custom_stage_1",
                    "name": "Custom 1",
                    "icon": "star",
                    "description": "Custom stage one",
                    "order": 1
                },
                {
                    "id": "custom_stage_2",
                    "name": "Custom 2",
                    "icon": "circle",
                    "description": "Custom stage two",
                    "order": 2,
                    "conditional": "some_mode"
                }
            ]
        }
        workflow_file = project_path / "felix" / "workflow.json"
        workflow_file.write_text(json.dumps(workflow_data, indent=2), encoding='utf-8')
        
        return project_path

    @pytest.fixture
    def mock_project_registration(self, mock_project_with_workflow):
        """Mock storage functions to return our test project"""
        from models import Project
        test_project = Project(
            id="test-project-id",
            path=str(mock_project_with_workflow),
            name="Test Project"
        )
        
        with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
            with patch('routers.agents.storage.get_project_by_id', return_value=test_project):
                yield test_project

    def test_get_workflow_config_returns_custom_config(self, client, mock_project_registration):
        """Returns workflow configuration from workflow.json"""
        response = client.get("/api/agents/workflow-config")
        assert response.status_code == 200
        
        data = response.json()
        assert data["version"] == "2.0"
        assert data["layout"] == "vertical"
        assert len(data["stages"]) == 2
        
        # Verify first custom stage
        stage_1 = data["stages"][0]
        assert stage_1["id"] == "custom_stage_1"
        assert stage_1["name"] == "Custom 1"
        assert stage_1["icon"] == "star"
        assert stage_1["description"] == "Custom stage one"
        assert stage_1["order"] == 1
        
        # Verify second custom stage with conditional
        stage_2 = data["stages"][1]
        assert stage_2["id"] == "custom_stage_2"
        assert stage_2["conditional"] == "some_mode"

    def test_get_workflow_config_with_project_id(self, client, mock_project_registration):
        """Returns workflow configuration for specified project_id"""
        response = client.get("/api/agents/workflow-config?project_id=test-project-id")
        assert response.status_code == 200
        
        data = response.json()
        assert data["version"] == "2.0"
        assert len(data["stages"]) == 2

    def test_get_workflow_config_returns_default_when_no_projects(self, client):
        """Returns default workflow config when no projects registered"""
        with patch('routers.agents.storage.get_all_projects', return_value=[]):
            response = client.get("/api/agents/workflow-config")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should return default config
        assert data["version"] == "1.0"
        assert data["layout"] == "horizontal"
        assert len(data["stages"]) == 14  # Default has 14 stages
        
        # Verify some default stages exist
        stage_ids = [s["id"] for s in data["stages"]]
        assert "select_requirement" in stage_ids
        assert "execute_llm" in stage_ids
        assert "commit_changes" in stage_ids
        assert "iteration_complete" in stage_ids

    def test_get_workflow_config_returns_default_when_file_missing(self, client, tmp_path):
        """Returns default workflow config when workflow.json doesn't exist"""
        # Create project without workflow.json
        project_path = tmp_path / "no-workflow-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        from models import Project
        test_project = Project(
            id="no-workflow-id",
            path=str(project_path),
            name="No Workflow Project"
        )
        
        with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
            response = client.get("/api/agents/workflow-config")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should return default config
        assert data["version"] == "1.0"
        assert data["layout"] == "horizontal"
        assert len(data["stages"]) == 14

    def test_get_workflow_config_handles_malformed_json(self, client, tmp_path):
        """Returns default workflow config when workflow.json is malformed"""
        project_path = tmp_path / "malformed-workflow-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        # Create malformed workflow.json
        workflow_file = project_path / "felix" / "workflow.json"
        workflow_file.write_text("not valid json {{{", encoding='utf-8')
        
        from models import Project
        test_project = Project(
            id="malformed-id",
            path=str(project_path),
            name="Malformed Project"
        )
        
        with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
            response = client.get("/api/agents/workflow-config")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should return default config on parse error
        assert data["version"] == "1.0"
        assert len(data["stages"]) == 14

    def test_get_workflow_config_handles_empty_stages(self, client, tmp_path):
        """Returns default workflow config when workflow.json has empty stages"""
        project_path = tmp_path / "empty-stages-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        # Create workflow.json with empty stages
        workflow_file = project_path / "felix" / "workflow.json"
        workflow_file.write_text(json.dumps({"version": "1.0", "stages": []}), encoding='utf-8')
        
        from models import Project
        test_project = Project(
            id="empty-stages-id",
            path=str(project_path),
            name="Empty Stages Project"
        )
        
        with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
            response = client.get("/api/agents/workflow-config")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should return default config when stages array is empty
        assert len(data["stages"]) == 14

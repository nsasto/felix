"""
Tests for the Agent Registry API (S-0013: Agent Settings Registry)

These tests validate:
1. Agent registers on startup via API
2. Heartbeat updates agents.json
3. Stale agents marked inactive
"""
import json
import pytest
from pathlib import Path
from datetime import datetime, timezone, timedelta
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

# Import the FastAPI app and router
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from routers.agents import (
    AgentEntry,
    check_agent_liveness,
    get_agents_file_path,
)


@pytest.fixture
def client():
    """Create a test client"""
    return TestClient(app)


@pytest.fixture
def mock_agents_file(tmp_path):
    """Create a temporary agents.json file"""
    agents_file = tmp_path / "felix" / "agents.json"
    agents_file.parent.mkdir(parents=True, exist_ok=True)
    agents_file.write_text(json.dumps({"agents": {}}), encoding='utf-8')
    return agents_file


@pytest.fixture
def mock_agents_registry(mock_agents_file):
    """Patch the agents file path to use the temporary file"""
    with patch('routers.agents.get_agents_file_path', return_value=mock_agents_file):
        yield mock_agents_file


class TestAgentRegistration:
    """Tests for agent registration (Validation criterion 1)"""

    def test_register_new_agent(self, client, mock_agents_registry):
        """Agent registers on startup via API"""
        response = client.post(
            "/api/agents/register",
            json={
                "agent_id": 0,
                "agent_name": "test-agent",
                "pid": 12345,
                "hostname": "test-host",
                "started_at": datetime.now(timezone.utc).isoformat()
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["agent_id"] == 0
        assert data["agent_name"] == "test-agent"
        assert data["status"] == "active"
        assert data["pid"] == 12345
        assert data["hostname"] == "test-host"

    def test_register_agent_persists_to_file(self, client, mock_agents_registry):
        """Registration persists agent to agents.json"""
        client.post(
            "/api/agents/register",
            json={
                "agent_id": 1,
                "agent_name": "persist-agent",
                "pid": 99999,
                "hostname": "persist-host"
            }
        )
        
        # Read the file directly - keys are now agent_id as strings
        content = json.loads(mock_agents_registry.read_text(encoding='utf-8'))
        assert "1" in content["agents"]
        assert content["agents"]["1"]["pid"] == 99999
        assert content["agents"]["1"]["hostname"] == "persist-host"
        assert content["agents"]["1"]["status"] == "active"

    def test_register_duplicate_active_agent_fails(self, client, mock_agents_registry):
        """Cannot register agent with same ID if already active"""
        # First registration
        response1 = client.post(
            "/api/agents/register",
            json={
                "agent_id": 2,
                "agent_name": "duplicate-agent",
                "pid": 11111,
                "hostname": "host1"
            }
        )
        assert response1.status_code == 200
        
        # Second registration with same ID should fail
        response2 = client.post(
            "/api/agents/register",
            json={
                "agent_id": 2,
                "agent_name": "duplicate-agent",
                "pid": 22222,
                "hostname": "host2"
            }
        )
        assert response2.status_code == 409
        assert "already active" in response2.json()["detail"]

    def test_register_reuses_stopped_agent_id(self, client, mock_agents_registry):
        """Can re-register agent ID after it was stopped"""
        # Register agent
        client.post(
            "/api/agents/register",
            json={
                "agent_id": 3,
                "agent_name": "reuse-agent",
                "pid": 11111,
                "hostname": "host1"
            }
        )
        
        # Stop the agent using agent_id
        client.post("/api/agents/3/stop")
        
        # Re-register with same ID - should succeed
        response = client.post(
            "/api/agents/register",
            json={
                "agent_id": 3,
                "agent_name": "reuse-agent",
                "pid": 22222,
                "hostname": "host2"
            }
        )
        assert response.status_code == 200
        assert response.json()["pid"] == 22222

    def test_register_agent_name_validation(self, client, mock_agents_registry):
        """Agent name must be alphanumeric with hyphens/underscores"""
        # Valid names
        valid_names = ["test-agent", "test_agent", "TestAgent123", "AGENT_1"]
        for idx, name in enumerate(valid_names):
            response = client.post(
                "/api/agents/register",
                json={"agent_id": 100 + idx, "agent_name": name, "pid": 12345, "hostname": "host"}
            )
            assert response.status_code == 200, f"Expected {name} to be valid"
            # Stop it so we can test next one cleanly
            client.post(f"/api/agents/{100 + idx}/stop")
        
        # Invalid names
        invalid_names = ["test agent", "test@agent", "test.agent", ""]
        for idx, name in enumerate(invalid_names):
            response = client.post(
                "/api/agents/register",
                json={"agent_id": 200 + idx, "agent_name": name, "pid": 12345, "hostname": "host"}
            )
            assert response.status_code == 400, f"Expected {name} to be invalid"


class TestAgentHeartbeat:
    """Tests for agent heartbeat (Validation criterion 2)"""

    def test_heartbeat_updates_timestamp(self, client, mock_agents_registry):
        """Heartbeat updates agents.json with new timestamp"""
        # Register agent with agent_id
        client.post(
            "/api/agents/register",
            json={"agent_id": 10, "agent_name": "heartbeat-agent", "pid": 12345, "hostname": "host"}
        )
        
        # Wait a tiny bit then heartbeat using agent_id
        response = client.post(
            "/api/agents/10/heartbeat",
            json={"current_run_id": "S-0001"}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "active"
        assert data["current_run_id"] == "S-0001"
        assert data["last_heartbeat"] is not None

    def test_heartbeat_updates_current_run_id(self, client, mock_agents_registry):
        """Heartbeat can update the current run ID"""
        # Register agent with agent_id
        client.post(
            "/api/agents/register",
            json={"agent_id": 11, "agent_name": "run-agent", "pid": 12345, "hostname": "host"}
        )
        
        # Heartbeat with run ID using agent_id
        client.post(
            "/api/agents/11/heartbeat",
            json={"current_run_id": "S-0002"}
        )
        
        # Verify in file - keys are now agent_id as strings
        content = json.loads(mock_agents_registry.read_text(encoding='utf-8'))
        assert content["agents"]["11"]["current_run_id"] == "S-0002"

    def test_heartbeat_nonexistent_agent_fails(self, client, mock_agents_registry):
        """Heartbeat for non-existent agent returns 404"""
        response = client.post(
            "/api/agents/99999/heartbeat",
            json={"current_run_id": None}
        )
        assert response.status_code == 404


class TestAgentLiveness:
    """Tests for stale agent detection (Validation criterion 5)"""

    def test_active_agent_with_recent_heartbeat(self):
        """Agent with recent heartbeat is marked active"""
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agent = AgentEntry(
            agent_id=20,
            agent_name="test-agent",
            pid=12345,
            hostname="host",
            status="active",
            last_heartbeat=now
        )
        
        status = check_agent_liveness(agent)
        assert status == "active"

    def test_inactive_agent_with_stale_heartbeat(self):
        """Agent with heartbeat > 10s old is marked inactive"""
        stale_time = (datetime.now(timezone.utc) - timedelta(seconds=15)).isoformat().replace('+00:00', 'Z')
        agent = AgentEntry(
            agent_id=21,
            agent_name="test-agent",
            pid=12345,
            hostname="host",
            status="active",
            last_heartbeat=stale_time
        )
        
        status = check_agent_liveness(agent)
        assert status == "inactive"

    def test_stopped_agent_stays_stopped(self):
        """Stopped agent remains stopped regardless of heartbeat"""
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agent = AgentEntry(
            agent_id=22,
            agent_name="test-agent",
            pid=12345,
            hostname="host",
            status="stopped",
            last_heartbeat=now,
            stopped_at=now
        )
        
        status = check_agent_liveness(agent)
        assert status == "stopped"

    def test_get_agents_updates_stale_status(self, client, mock_agents_registry):
        """GET /api/agents marks stale agents as inactive"""
        # Create agent with stale heartbeat directly in file - keys are now agent_id as strings
        stale_time = (datetime.now(timezone.utc) - timedelta(seconds=15)).isoformat().replace('+00:00', 'Z')
        content = {
            "agents": {
                "23": {
                    "agent_id": 23,
                    "agent_name": "stale-agent",
                    "pid": 12345,
                    "hostname": "host",
                    "status": "active",
                    "current_run_id": None,
                    "started_at": stale_time,
                    "last_heartbeat": stale_time,
                    "stopped_at": None
                }
            }
        }
        mock_agents_registry.write_text(json.dumps(content), encoding='utf-8')
        
        # Get agents - should update status
        response = client.get("/api/agents")
        assert response.status_code == 200
        
        data = response.json()
        assert data["agents"]["23"]["status"] == "inactive"


class TestAgentStop:
    """Tests for agent stop endpoint"""

    def test_stop_agent(self, client, mock_agents_registry):
        """Stop endpoint marks agent as stopped"""
        # Register agent with agent_id
        client.post(
            "/api/agents/register",
            json={"agent_id": 30, "agent_name": "stop-agent", "pid": 12345, "hostname": "host"}
        )
        
        # Stop agent using agent_id
        response = client.post("/api/agents/30/stop")
        assert response.status_code == 200
        assert response.json()["status"] == "stopped"
        
        # Verify in file - keys are now agent_id as strings
        content = json.loads(mock_agents_registry.read_text(encoding='utf-8'))
        assert content["agents"]["30"]["status"] == "stopped"
        assert content["agents"]["30"]["stopped_at"] is not None

    def test_stop_nonexistent_agent_fails(self, client, mock_agents_registry):
        """Stop for non-existent agent returns 404"""
        response = client.post("/api/agents/99999/stop")
        assert response.status_code == 404


class TestGetAgents:
    """Tests for GET /api/agents endpoint"""

    def test_get_agents_empty_registry(self, client, mock_agents_registry):
        """Get agents returns empty dict for empty registry"""
        response = client.get("/api/agents")
        assert response.status_code == 200
        assert response.json()["agents"] == {}

    def test_get_agents_returns_all_agents(self, client, mock_agents_registry):
        """Get agents returns all registered agents"""
        # Register multiple agents with agent_id
        for i in range(3):
            client.post(
                "/api/agents/register",
                json={"agent_id": 40 + i, "agent_name": f"agent-{i}", "pid": 10000 + i, "hostname": f"host-{i}"}
            )
        
        response = client.get("/api/agents")
        assert response.status_code == 200
        
        agents = response.json()["agents"]
        assert len(agents) == 3
        # Keys are now agent_id as strings
        assert "40" in agents
        assert "41" in agents
        assert "42" in agents


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


class TestWorkflowStageFields:
    """Tests for workflow stage field parsing from state.json (S-0030: Agent Workflow Visualization)"""

    @pytest.fixture
    def mock_project_with_state(self, tmp_path):
        """Create a temporary project with state.json containing workflow stage"""
        project_path = tmp_path / "state-test-project"
        project_path.mkdir(parents=True, exist_ok=True)
        
        # Create required Felix structure
        (project_path / "felix").mkdir(exist_ok=True)
        (project_path / "specs").mkdir(exist_ok=True)
        
        # Create state.json with workflow stage
        state_data = {
            "current_requirement_id": "S-0030",
            "last_run_id": "S-0030-20260129-120000-it1",
            "last_mode": "building",
            "status": "running",
            "current_workflow_stage": "execute_llm",
            "workflow_stage_timestamp": "2026-01-29T12:00:00Z"
        }
        state_file = project_path / "felix" / "state.json"
        state_file.write_text(json.dumps(state_data, indent=2), encoding='utf-8')
        
        return project_path

    def test_get_agents_includes_workflow_stage_fields(self, client, mock_agents_file, tmp_path):
        """GET /api/agents includes workflow stage fields from state.json"""
        # Create project with state.json
        project_path = tmp_path / "workflow-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        state_data = {
            "current_requirement_id": "S-0030",
            "current_workflow_stage": "execute_llm",
            "workflow_stage_timestamp": "2026-01-29T12:00:00Z"
        }
        (project_path / "felix" / "state.json").write_text(json.dumps(state_data), encoding='utf-8')
        
        from models import Project
        test_project = Project(id="test-id", path=str(project_path), name="Test")
        
        # Create agent registry with active agent working on S-0030
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agents_data = {
            "agents": {
                "50": {
                    "agent_id": 50,
                    "agent_name": "workflow-agent",
                    "pid": 12345,
                    "hostname": "host",
                    "status": "active",
                    "current_run_id": "S-0030",
                    "started_at": now,
                    "last_heartbeat": now,
                    "stopped_at": None
                }
            }
        }
        mock_agents_file.write_text(json.dumps(agents_data), encoding='utf-8')
        
        with patch('routers.agents.get_agents_file_path', return_value=mock_agents_file):
            with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
                response = client.get("/api/agents")
        
        assert response.status_code == 200
        data = response.json()
        
        agent = data["agents"]["50"]
        assert agent["current_workflow_stage"] == "execute_llm"
        assert agent["workflow_stage_timestamp"] == "2026-01-29T12:00:00Z"

    def test_workflow_stage_fields_null_when_no_state(self, client, mock_agents_file, tmp_path):
        """Workflow stage fields are null when state.json doesn't exist"""
        # Create project without state.json
        project_path = tmp_path / "no-state-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        from models import Project
        test_project = Project(id="no-state-id", path=str(project_path), name="No State")
        
        # Create agent registry
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agents_data = {
            "agents": {
                "51": {
                    "agent_id": 51,
                    "agent_name": "no-state-agent",
                    "pid": 12345,
                    "hostname": "host",
                    "status": "active",
                    "current_run_id": "S-0999",
                    "started_at": now,
                    "last_heartbeat": now,
                    "stopped_at": None
                }
            }
        }
        mock_agents_file.write_text(json.dumps(agents_data), encoding='utf-8')
        
        with patch('routers.agents.get_agents_file_path', return_value=mock_agents_file):
            with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
                response = client.get("/api/agents")
        
        assert response.status_code == 200
        data = response.json()
        
        agent = data["agents"]["51"]
        assert agent["current_workflow_stage"] is None
        assert agent["workflow_stage_timestamp"] is None

    def test_workflow_stage_fields_null_for_inactive_agent(self, client, mock_agents_file, tmp_path):
        """Workflow stage fields are null for inactive agents"""
        # Create project with state.json
        project_path = tmp_path / "inactive-agent-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        state_data = {
            "current_requirement_id": "S-0030",
            "current_workflow_stage": "execute_llm",
            "workflow_stage_timestamp": "2026-01-29T12:00:00Z"
        }
        (project_path / "felix" / "state.json").write_text(json.dumps(state_data), encoding='utf-8')
        
        from models import Project
        test_project = Project(id="inactive-id", path=str(project_path), name="Inactive")
        
        # Create agent with stale heartbeat (will become inactive)
        stale_time = (datetime.now(timezone.utc) - timedelta(seconds=15)).isoformat().replace('+00:00', 'Z')
        agents_data = {
            "agents": {
                "52": {
                    "agent_id": 52,
                    "agent_name": "inactive-agent",
                    "pid": 12345,
                    "hostname": "host",
                    "status": "active",
                    "current_run_id": "S-0030",
                    "started_at": stale_time,
                    "last_heartbeat": stale_time,
                    "stopped_at": None
                }
            }
        }
        mock_agents_file.write_text(json.dumps(agents_data), encoding='utf-8')
        
        with patch('routers.agents.get_agents_file_path', return_value=mock_agents_file):
            with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
                response = client.get("/api/agents")
        
        assert response.status_code == 200
        data = response.json()
        
        agent = data["agents"]["52"]
        # Agent becomes inactive due to stale heartbeat
        assert agent["status"] == "inactive"
        # Workflow stage fields should be null for inactive agents
        assert agent["current_workflow_stage"] is None
        assert agent["workflow_stage_timestamp"] is None

    def test_workflow_stage_fields_null_when_no_matching_run(self, client, mock_agents_file, tmp_path):
        """Workflow stage fields are null when agent's run doesn't match state"""
        # Create project with state.json
        project_path = tmp_path / "no-match-project"
        (project_path / "felix").mkdir(parents=True)
        (project_path / "specs").mkdir()
        
        state_data = {
            "current_requirement_id": "S-0030",
            "current_workflow_stage": "execute_llm",
            "workflow_stage_timestamp": "2026-01-29T12:00:00Z"
        }
        (project_path / "felix" / "state.json").write_text(json.dumps(state_data), encoding='utf-8')
        
        from models import Project
        test_project = Project(id="no-match-id", path=str(project_path), name="No Match")
        
        # Create agent working on different requirement
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agents_data = {
            "agents": {
                "53": {
                    "agent_id": 53,
                    "agent_name": "no-match-agent",
                    "pid": 12345,
                    "hostname": "host",
                    "status": "active",
                    "current_run_id": "S-0999",  # Different requirement
                    "started_at": now,
                    "last_heartbeat": now,
                    "stopped_at": None
                }
            }
        }
        mock_agents_file.write_text(json.dumps(agents_data), encoding='utf-8')
        
        with patch('routers.agents.get_agents_file_path', return_value=mock_agents_file):
            with patch('routers.agents.storage.get_all_projects', return_value=[test_project]):
                response = client.get("/api/agents")
        
        assert response.status_code == 200
        data = response.json()
        
        agent = data["agents"]["53"]
        # Agent is working on different requirement, so no workflow stage
        assert agent["current_workflow_stage"] is None
        assert agent["workflow_stage_timestamp"] is None

    def test_agent_entry_model_has_workflow_fields(self):
        """AgentEntry model includes workflow stage fields"""
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agent = AgentEntry(
            agent_id=54,
            agent_name="model-test-agent",
            pid=12345,
            hostname="host",
            status="active",
            current_run_id="S-0030",
            started_at=now,
            last_heartbeat=now,
            current_workflow_stage="build_prompt",
            workflow_stage_timestamp="2026-01-29T12:00:00Z"
        )
        
        assert agent.current_workflow_stage == "build_prompt"
        assert agent.workflow_stage_timestamp == "2026-01-29T12:00:00Z"
        
        # Test model_dump includes these fields
        dumped = agent.model_dump()
        assert "current_workflow_stage" in dumped
        assert "workflow_stage_timestamp" in dumped

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
                "agent_name": "test-agent",
                "pid": 12345,
                "hostname": "test-host",
                "started_at": datetime.now(timezone.utc).isoformat()
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["agent_name"] == "test-agent"
        assert data["status"] == "active"
        assert data["pid"] == 12345
        assert data["hostname"] == "test-host"

    def test_register_agent_persists_to_file(self, client, mock_agents_registry):
        """Registration persists agent to agents.json"""
        client.post(
            "/api/agents/register",
            json={
                "agent_name": "persist-agent",
                "pid": 99999,
                "hostname": "persist-host"
            }
        )
        
        # Read the file directly
        content = json.loads(mock_agents_registry.read_text(encoding='utf-8'))
        assert "persist-agent" in content["agents"]
        assert content["agents"]["persist-agent"]["pid"] == 99999
        assert content["agents"]["persist-agent"]["hostname"] == "persist-host"
        assert content["agents"]["persist-agent"]["status"] == "active"

    def test_register_duplicate_active_agent_fails(self, client, mock_agents_registry):
        """Cannot register agent with same name if already active"""
        # First registration
        response1 = client.post(
            "/api/agents/register",
            json={
                "agent_name": "duplicate-agent",
                "pid": 11111,
                "hostname": "host1"
            }
        )
        assert response1.status_code == 200
        
        # Second registration with same name should fail
        response2 = client.post(
            "/api/agents/register",
            json={
                "agent_name": "duplicate-agent",
                "pid": 22222,
                "hostname": "host2"
            }
        )
        assert response2.status_code == 409
        assert "already active" in response2.json()["detail"]

    def test_register_reuses_stopped_agent_name(self, client, mock_agents_registry):
        """Can re-register agent name after it was stopped"""
        # Register agent
        client.post(
            "/api/agents/register",
            json={
                "agent_name": "reuse-agent",
                "pid": 11111,
                "hostname": "host1"
            }
        )
        
        # Stop the agent
        client.post("/api/agents/reuse-agent/stop")
        
        # Re-register with same name - should succeed
        response = client.post(
            "/api/agents/register",
            json={
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
        for name in valid_names:
            response = client.post(
                "/api/agents/register",
                json={"agent_name": name, "pid": 12345, "hostname": "host"}
            )
            assert response.status_code == 200, f"Expected {name} to be valid"
            # Stop it so we can register next one
            client.post(f"/api/agents/{name}/stop")
        
        # Invalid names
        invalid_names = ["test agent", "test@agent", "test.agent", ""]
        for name in invalid_names:
            response = client.post(
                "/api/agents/register",
                json={"agent_name": name, "pid": 12345, "hostname": "host"}
            )
            assert response.status_code == 400, f"Expected {name} to be invalid"


class TestAgentHeartbeat:
    """Tests for agent heartbeat (Validation criterion 2)"""

    def test_heartbeat_updates_timestamp(self, client, mock_agents_registry):
        """Heartbeat updates agents.json with new timestamp"""
        # Register agent
        client.post(
            "/api/agents/register",
            json={"agent_name": "heartbeat-agent", "pid": 12345, "hostname": "host"}
        )
        
        # Wait a tiny bit then heartbeat
        response = client.post(
            "/api/agents/heartbeat-agent/heartbeat",
            json={"current_run_id": "S-0001"}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "active"
        assert data["current_run_id"] == "S-0001"
        assert data["last_heartbeat"] is not None

    def test_heartbeat_updates_current_run_id(self, client, mock_agents_registry):
        """Heartbeat can update the current run ID"""
        # Register agent
        client.post(
            "/api/agents/register",
            json={"agent_name": "run-agent", "pid": 12345, "hostname": "host"}
        )
        
        # Heartbeat with run ID
        client.post(
            "/api/agents/run-agent/heartbeat",
            json={"current_run_id": "S-0002"}
        )
        
        # Verify in file
        content = json.loads(mock_agents_registry.read_text(encoding='utf-8'))
        assert content["agents"]["run-agent"]["current_run_id"] == "S-0002"

    def test_heartbeat_nonexistent_agent_fails(self, client, mock_agents_registry):
        """Heartbeat for non-existent agent returns 404"""
        response = client.post(
            "/api/agents/ghost-agent/heartbeat",
            json={"current_run_id": None}
        )
        assert response.status_code == 404


class TestAgentLiveness:
    """Tests for stale agent detection (Validation criterion 5)"""

    def test_active_agent_with_recent_heartbeat(self):
        """Agent with recent heartbeat is marked active"""
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        agent = AgentEntry(
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
        # Create agent with stale heartbeat directly in file
        stale_time = (datetime.now(timezone.utc) - timedelta(seconds=15)).isoformat().replace('+00:00', 'Z')
        content = {
            "agents": {
                "stale-agent": {
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
        assert data["agents"]["stale-agent"]["status"] == "inactive"


class TestAgentStop:
    """Tests for agent stop endpoint"""

    def test_stop_agent(self, client, mock_agents_registry):
        """Stop endpoint marks agent as stopped"""
        # Register agent
        client.post(
            "/api/agents/register",
            json={"agent_name": "stop-agent", "pid": 12345, "hostname": "host"}
        )
        
        # Stop agent
        response = client.post("/api/agents/stop-agent/stop")
        assert response.status_code == 200
        assert response.json()["status"] == "stopped"
        
        # Verify in file
        content = json.loads(mock_agents_registry.read_text(encoding='utf-8'))
        assert content["agents"]["stop-agent"]["status"] == "stopped"
        assert content["agents"]["stop-agent"]["stopped_at"] is not None

    def test_stop_nonexistent_agent_fails(self, client, mock_agents_registry):
        """Stop for non-existent agent returns 404"""
        response = client.post("/api/agents/no-such-agent/stop")
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
        # Register multiple agents
        for i in range(3):
            client.post(
                "/api/agents/register",
                json={"agent_name": f"agent-{i}", "pid": 10000 + i, "hostname": f"host-{i}"}
            )
        
        response = client.get("/api/agents")
        assert response.status_code == 200
        
        agents = response.json()["agents"]
        assert len(agents) == 3
        assert "agent-0" in agents
        assert "agent-1" in agents
        assert "agent-2" in agents


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

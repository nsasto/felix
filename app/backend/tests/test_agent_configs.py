"""
Tests for the Agent Configuration API (S-0020: Consolidate Agent Settings Management)

These tests validate:
1. CRUD operations for agent configurations
2. ID 0 deletion rejection (403 Forbidden)
3. Fallback logic when agent_id is invalid
4. Active agent setting and retrieval
"""
import json
import pytest
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient

# Import the FastAPI app
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app


@pytest.fixture
def client():
    """Create a test client"""
    return TestClient(app)


@pytest.fixture
def temp_felix_home(tmp_path):
    """Create a temporary felix home directory with agents.json and config.json"""
    felix_home = tmp_path / ".felix"
    felix_home.mkdir(parents=True, exist_ok=True)
    
    # Create default agents.json
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
            }
        ]
    }
    agents_file.write_text(json.dumps(agents_data, indent=2), encoding='utf-8')
    
    # Create default config.json
    config_file = felix_home / "config.json"
    config_data = {
        "version": "0.1.0",
        "agent": {
            "agent_id": 0
        }
    }
    config_file.write_text(json.dumps(config_data, indent=2), encoding='utf-8')
    
    return felix_home


@pytest.fixture
def mock_felix_home(temp_felix_home):
    """Patch storage.get_felix_home to use temporary directory"""
    with patch('storage.get_felix_home', return_value=temp_felix_home):
        with patch('routers.agent_configs.storage.get_felix_home', return_value=temp_felix_home):
            yield temp_felix_home


class TestGetAgentConfigs:
    """Tests for GET /api/agent-configs endpoint"""

    def test_get_agents_returns_all_agents(self, client, mock_felix_home):
        """Get agents returns all configured agents"""
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        
        data = response.json()
        assert "agents" in data
        assert "active_agent_id" in data
        assert len(data["agents"]) == 1
        assert data["agents"][0]["id"] == 0
        assert data["agents"][0]["name"] == "felix-primary"
        assert data["active_agent_id"] == 0

    def test_get_agents_with_multiple_agents(self, client, mock_felix_home):
        """Get agents returns multiple configured agents"""
        # Add another agent directly to the file
        agents_file = mock_felix_home / "agents.json"
        agents_data = json.loads(agents_file.read_text(encoding='utf-8'))
        agents_data["agents"].append({
            "id": 1,
            "name": "test-agent",
            "executable": "claude",
            "args": ["--model", "sonnet"],
            "working_directory": ".",
            "environment": {}
        })
        agents_file.write_text(json.dumps(agents_data, indent=2), encoding='utf-8')
        
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        
        data = response.json()
        assert len(data["agents"]) == 2
        agent_ids = [a["id"] for a in data["agents"]]
        assert 0 in agent_ids
        assert 1 in agent_ids

    def test_get_agents_fallback_on_invalid_active_id(self, client, mock_felix_home):
        """Falls back to ID 0 when active_id references non-existent agent"""
        # Set invalid active_id in config
        config_file = mock_felix_home / "config.json"
        config_data = {"agent": {"agent_id": 999}}
        config_file.write_text(json.dumps(config_data, indent=2), encoding='utf-8')
        
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        
        data = response.json()
        assert data["active_agent_id"] == 0


class TestGetSingleAgentConfig:
    """Tests for GET /api/agent-configs/{agent_id} endpoint"""

    def test_get_existing_agent(self, client, mock_felix_home):
        """Get a specific agent by ID"""
        response = client.get("/api/agent-configs/0")
        assert response.status_code == 200
        
        data = response.json()
        assert data["agent"]["id"] == 0
        assert data["agent"]["name"] == "felix-primary"

    def test_get_nonexistent_agent_returns_404(self, client, mock_felix_home):
        """Get non-existent agent returns 404"""
        response = client.get("/api/agent-configs/999")
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()


class TestCreateAgentConfig:
    """Tests for POST /api/agent-configs endpoint"""

    def test_create_agent_config(self, client, mock_felix_home):
        """Create a new agent configuration"""
        response = client.post(
            "/api/agent-configs",
            json={
                "name": "new-agent",
                "executable": "claude",
                "args": ["--model", "opus"],
                "working_directory": "/custom/path",
                "environment": {"API_KEY": "test123"}
            }
        )
        
        assert response.status_code == 201
        data = response.json()
        assert data["agent"]["id"] == 1  # Next ID after 0
        assert data["agent"]["name"] == "new-agent"
        assert data["agent"]["executable"] == "claude"
        assert data["agent"]["args"] == ["--model", "opus"]
        assert data["agent"]["working_directory"] == "/custom/path"
        assert data["agent"]["environment"] == {"API_KEY": "test123"}

    def test_create_agent_persists_to_file(self, client, mock_felix_home):
        """Created agent is persisted to agents.json"""
        client.post(
            "/api/agent-configs",
            json={
                "name": "persisted-agent",
                "executable": "droid"
            }
        )
        
        # Read file directly
        agents_file = mock_felix_home / "agents.json"
        agents_data = json.loads(agents_file.read_text(encoding='utf-8'))
        
        agent_names = [a["name"] for a in agents_data["agents"]]
        assert "persisted-agent" in agent_names

    def test_create_agent_with_defaults(self, client, mock_felix_home):
        """Create agent with minimal fields uses defaults"""
        response = client.post(
            "/api/agent-configs",
            json={"name": "minimal-agent"}
        )
        
        assert response.status_code == 201
        data = response.json()
        assert data["agent"]["executable"] == "droid"
        assert data["agent"]["args"] == []
        assert data["agent"]["working_directory"] == "."
        assert data["agent"]["environment"] == {}

    def test_create_agent_empty_name_fails(self, client, mock_felix_home):
        """Create agent with empty name returns 400"""
        response = client.post(
            "/api/agent-configs",
            json={"name": ""}
        )
        assert response.status_code == 400
        assert "empty" in response.json()["detail"].lower()

    def test_create_agent_whitespace_name_fails(self, client, mock_felix_home):
        """Create agent with whitespace-only name returns 400"""
        response = client.post(
            "/api/agent-configs",
            json={"name": "   "}
        )
        assert response.status_code == 400

    def test_create_multiple_agents_increments_id(self, client, mock_felix_home):
        """Creating multiple agents assigns sequential IDs"""
        # Create first agent
        response1 = client.post(
            "/api/agent-configs",
            json={"name": "agent-1"}
        )
        assert response1.json()["agent"]["id"] == 1
        
        # Create second agent
        response2 = client.post(
            "/api/agent-configs",
            json={"name": "agent-2"}
        )
        assert response2.json()["agent"]["id"] == 2
        
        # Create third agent
        response3 = client.post(
            "/api/agent-configs",
            json={"name": "agent-3"}
        )
        assert response3.json()["agent"]["id"] == 3


class TestUpdateAgentConfig:
    """Tests for PUT /api/agent-configs/{agent_id} endpoint"""

    def test_update_agent_name(self, client, mock_felix_home):
        """Update agent name"""
        response = client.put(
            "/api/agent-configs/0",
            json={"name": "updated-name"}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["agent"]["name"] == "updated-name"
        assert data["agent"]["id"] == 0  # ID unchanged

    def test_update_agent_executable(self, client, mock_felix_home):
        """Update agent executable"""
        response = client.put(
            "/api/agent-configs/0",
            json={"executable": "claude"}
        )
        
        assert response.status_code == 200
        assert response.json()["agent"]["executable"] == "claude"

    def test_update_agent_args(self, client, mock_felix_home):
        """Update agent args"""
        response = client.put(
            "/api/agent-configs/0",
            json={"args": ["--verbose", "--debug"]}
        )
        
        assert response.status_code == 200
        assert response.json()["agent"]["args"] == ["--verbose", "--debug"]

    def test_update_agent_environment(self, client, mock_felix_home):
        """Update agent environment variables"""
        response = client.put(
            "/api/agent-configs/0",
            json={"environment": {"API_KEY": "new-key", "DEBUG": "true"}}
        )
        
        assert response.status_code == 200
        env = response.json()["agent"]["environment"]
        assert env["API_KEY"] == "new-key"
        assert env["DEBUG"] == "true"

    def test_update_nonexistent_agent_returns_404(self, client, mock_felix_home):
        """Update non-existent agent returns 404"""
        response = client.put(
            "/api/agent-configs/999",
            json={"name": "ghost-agent"}
        )
        assert response.status_code == 404

    def test_update_agent_persists_changes(self, client, mock_felix_home):
        """Updated agent is persisted to agents.json"""
        client.put(
            "/api/agent-configs/0",
            json={"name": "persisted-update"}
        )
        
        # Read file directly
        agents_file = mock_felix_home / "agents.json"
        agents_data = json.loads(agents_file.read_text(encoding='utf-8'))
        
        agent_0 = next(a for a in agents_data["agents"] if a["id"] == 0)
        assert agent_0["name"] == "persisted-update"

    def test_update_agent_empty_name_fails(self, client, mock_felix_home):
        """Update agent with empty name returns 400"""
        response = client.put(
            "/api/agent-configs/0",
            json={"name": ""}
        )
        assert response.status_code == 400

    def test_update_multiple_fields(self, client, mock_felix_home):
        """Update multiple fields at once"""
        response = client.put(
            "/api/agent-configs/0",
            json={
                "name": "multi-update",
                "executable": "new-exec",
                "args": ["arg1", "arg2"],
                "working_directory": "/new/path"
            }
        )
        
        assert response.status_code == 200
        agent = response.json()["agent"]
        assert agent["name"] == "multi-update"
        assert agent["executable"] == "new-exec"
        assert agent["args"] == ["arg1", "arg2"]
        assert agent["working_directory"] == "/new/path"


class TestDeleteAgentConfig:
    """Tests for DELETE /api/agent-configs/{agent_id} endpoint"""

    def test_delete_system_default_returns_403(self, client, mock_felix_home):
        """Cannot delete system default agent (ID 0) - returns 403"""
        response = client.delete("/api/agent-configs/0")
        
        assert response.status_code == 403
        assert "system default" in response.json()["detail"].lower()

    def test_delete_non_system_agent(self, client, mock_felix_home):
        """Can delete non-system-default agents"""
        # First create an agent to delete
        client.post("/api/agent-configs", json={"name": "to-delete"})
        
        # Delete it
        response = client.delete("/api/agent-configs/1")
        
        assert response.status_code == 200
        assert response.json()["status"] == "deleted"
        assert response.json()["agent_id"] == 1

    def test_delete_nonexistent_agent_returns_404(self, client, mock_felix_home):
        """Delete non-existent agent returns 404"""
        response = client.delete("/api/agent-configs/999")
        assert response.status_code == 404

    def test_delete_removes_from_file(self, client, mock_felix_home):
        """Deleted agent is removed from agents.json"""
        # Create an agent
        client.post("/api/agent-configs", json={"name": "delete-me"})
        
        # Verify it exists
        agents_file = mock_felix_home / "agents.json"
        agents_data = json.loads(agents_file.read_text(encoding='utf-8'))
        assert len(agents_data["agents"]) == 2
        
        # Delete it
        client.delete("/api/agent-configs/1")
        
        # Verify removal
        agents_data = json.loads(agents_file.read_text(encoding='utf-8'))
        assert len(agents_data["agents"]) == 1
        agent_ids = [a["id"] for a in agents_data["agents"]]
        assert 1 not in agent_ids

    def test_delete_active_agent_switches_to_default(self, client, mock_felix_home):
        """Deleting active agent switches to system default"""
        # Create a new agent and set it as active
        client.post("/api/agent-configs", json={"name": "active-to-delete"})
        client.post("/api/agent-configs/active", json={"agent_id": 1})
        
        # Verify agent 1 is active
        config_file = mock_felix_home / "config.json"
        config_data = json.loads(config_file.read_text(encoding='utf-8'))
        assert config_data["agent"]["agent_id"] == 1
        
        # Delete the active agent
        response = client.delete("/api/agent-configs/1")
        
        assert response.status_code == 200
        assert "switched to system default" in response.json()["message"].lower()
        
        # Verify config switched to 0
        config_data = json.loads(config_file.read_text(encoding='utf-8'))
        assert config_data["agent"]["agent_id"] == 0


class TestSetActiveAgent:
    """Tests for POST /api/agent-configs/active endpoint"""

    def test_set_active_agent(self, client, mock_felix_home):
        """Set active agent by ID"""
        # Create a new agent
        client.post("/api/agent-configs", json={"name": "new-active"})
        
        # Set it as active
        response = client.post(
            "/api/agent-configs/active",
            json={"agent_id": 1}
        )
        
        assert response.status_code == 200
        assert response.json()["agent_id"] == 1

    def test_set_active_updates_config_file(self, client, mock_felix_home):
        """Setting active agent updates config.json"""
        # Create a new agent
        client.post("/api/agent-configs", json={"name": "new-active"})
        
        # Set it as active
        client.post("/api/agent-configs/active", json={"agent_id": 1})
        
        # Verify in config file
        config_file = mock_felix_home / "config.json"
        config_data = json.loads(config_file.read_text(encoding='utf-8'))
        assert config_data["agent"]["agent_id"] == 1

    def test_set_active_nonexistent_agent_returns_404(self, client, mock_felix_home):
        """Cannot set non-existent agent as active"""
        response = client.post(
            "/api/agent-configs/active",
            json={"agent_id": 999}
        )
        assert response.status_code == 404


class TestGetActiveAgent:
    """Tests for GET /api/agent-configs/active/current endpoint"""

    def test_get_active_agent(self, client, mock_felix_home):
        """Get current active agent configuration"""
        response = client.get("/api/agent-configs/active/current")
        
        assert response.status_code == 200
        data = response.json()
        assert data["agent"]["id"] == 0
        assert data["agent"]["name"] == "felix-primary"

    def test_get_active_agent_fallback_on_invalid(self, client, mock_felix_home):
        """Falls back to ID 0 when active agent doesn't exist"""
        # Set invalid active_id
        config_file = mock_felix_home / "config.json"
        config_data = {"agent": {"agent_id": 999}}
        config_file.write_text(json.dumps(config_data, indent=2), encoding='utf-8')
        
        response = client.get("/api/agent-configs/active/current")
        
        assert response.status_code == 200
        data = response.json()
        assert data["agent"]["id"] == 0
        assert "not found" in data["message"].lower()

    def test_get_active_agent_autocorrects_config(self, client, mock_felix_home):
        """Auto-corrects config.json when active agent doesn't exist"""
        # Set invalid active_id
        config_file = mock_felix_home / "config.json"
        config_data = {"agent": {"agent_id": 999}}
        config_file.write_text(json.dumps(config_data, indent=2), encoding='utf-8')
        
        # Call the endpoint
        client.get("/api/agent-configs/active/current")
        
        # Verify config was corrected
        config_data = json.loads(config_file.read_text(encoding='utf-8'))
        assert config_data["agent"]["agent_id"] == 0


class TestIdNeverReused:
    """Tests verifying IDs are never reused after deletion"""

    def test_id_not_reused_after_deletion(self, client, mock_felix_home):
        """Deleted agent IDs are not reused for new agents"""
        # Create agents with IDs 1, 2, 3
        client.post("/api/agent-configs", json={"name": "agent-1"})
        client.post("/api/agent-configs", json={"name": "agent-2"})
        client.post("/api/agent-configs", json={"name": "agent-3"})
        
        # Delete agent with ID 2
        client.delete("/api/agent-configs/2")
        
        # Create a new agent - should get ID 4, not 2
        response = client.post("/api/agent-configs", json={"name": "agent-4"})
        assert response.json()["agent"]["id"] == 4

    def test_id_increments_from_max(self, client, mock_felix_home):
        """New IDs increment from max existing ID"""
        # Create agent with ID 1
        client.post("/api/agent-configs", json={"name": "agent-1"})
        
        # Manually set an agent with high ID
        agents_file = mock_felix_home / "agents.json"
        agents_data = json.loads(agents_file.read_text(encoding='utf-8'))
        agents_data["agents"].append({
            "id": 100,
            "name": "high-id-agent",
            "executable": "droid",
            "args": [],
            "working_directory": ".",
            "environment": {}
        })
        agents_file.write_text(json.dumps(agents_data, indent=2), encoding='utf-8')
        
        # Create a new agent - should get ID 101
        response = client.post("/api/agent-configs", json={"name": "next-agent"})
        assert response.json()["agent"]["id"] == 101


class TestEdgeCases:
    """Tests for edge cases and error handling"""

    def test_empty_agents_file_creates_default(self, client, mock_felix_home):
        """Empty/missing agents.json creates default agent"""
        # Delete agents.json
        agents_file = mock_felix_home / "agents.json"
        agents_file.unlink()
        
        # Request should succeed and create default
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        
        data = response.json()
        assert len(data["agents"]) == 1
        assert data["agents"][0]["id"] == 0

    def test_missing_config_file_uses_default_active(self, client, mock_felix_home):
        """Missing config.json defaults to agent ID 0"""
        # Delete config.json
        config_file = mock_felix_home / "config.json"
        config_file.unlink()
        
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        assert response.json()["active_agent_id"] == 0

    def test_malformed_config_uses_default_active(self, client, mock_felix_home):
        """Malformed config.json defaults to agent ID 0"""
        config_file = mock_felix_home / "config.json"
        config_file.write_text("not valid json {{{", encoding='utf-8')
        
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        assert response.json()["active_agent_id"] == 0

    def test_config_without_agent_section_uses_default(self, client, mock_felix_home):
        """Config without agent section defaults to ID 0"""
        config_file = mock_felix_home / "config.json"
        config_data = {"version": "0.1.0"}  # No agent section
        config_file.write_text(json.dumps(config_data), encoding='utf-8')
        
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        assert response.json()["active_agent_id"] == 0

    def test_legacy_inline_agent_defaults_to_id_0(self, client, mock_felix_home):
        """Legacy inline agent config (without agent_id) defaults to ID 0"""
        config_file = mock_felix_home / "config.json"
        config_data = {
            "agent": {
                "name": "legacy-agent",
                "executable": "droid"
            }
        }
        config_file.write_text(json.dumps(config_data), encoding='utf-8')
        
        response = client.get("/api/agent-configs")
        assert response.status_code == 200
        assert response.json()["active_agent_id"] == 0

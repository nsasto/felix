"""
Tests for the Copilot API (S-0016: Felix Copilot Settings)

These tests validate:
1. Copilot test endpoint works correctly
2. Copilot status endpoint returns configuration status
3. API key validation from environment
4. Provider-specific testing logic
"""
import json
import pytest
from pathlib import Path
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient
import os

# Import the FastAPI app and router
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from routers.copilot import (
    CopilotTestResult,
    verify_openai_connection,
    verify_anthropic_connection,
)
from routers.settings import (
    CopilotConfig,
    CopilotContextSourcesConfig,
    CopilotFeaturesConfig,
    FelixConfig,
)


@pytest.fixture
def client():
    """Create a test client"""
    return TestClient(app)


@pytest.fixture
def mock_copilot_config():
    """Create a mock copilot configuration"""
    return CopilotConfig(
        enabled=True,
        provider="openai",
        model="gpt-4o",
        context_sources=CopilotContextSourcesConfig(),
        features=CopilotFeaturesConfig()
    )


@pytest.fixture
def mock_felix_config(mock_copilot_config):
    """Create a mock Felix configuration with copilot"""
    return FelixConfig(copilot=mock_copilot_config)


class TestCopilotTestEndpoint:
    """Tests for POST /api/copilot/test endpoint"""

    def test_test_connection_no_api_key(self, client):
        """Test returns error when FELIX_COPILOT_API_KEY is not set"""
        with patch.dict(os.environ, {}, clear=True):
            # Ensure FELIX_COPILOT_API_KEY is not set
            if 'FELIX_COPILOT_API_KEY' in os.environ:
                del os.environ['FELIX_COPILOT_API_KEY']
            
            with patch('routers.copilot.os.getenv', return_value=None):
                response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "not found" in data["error"].lower()

    def test_test_connection_empty_api_key(self, client):
        """Test returns error when FELIX_COPILOT_API_KEY is empty"""
        with patch('routers.copilot.os.getenv', return_value="   "):
            response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "empty" in data["error"].lower()

    def test_test_connection_openai_success(self, client, mock_felix_config):
        """Test returns success for valid OpenAI API key"""
        with patch('routers.copilot.os.getenv', return_value="sk-test-key"):
            with patch('routers.copilot.load_global_config', return_value=mock_felix_config):
                with patch('routers.copilot.verify_openai_connection', new_callable=AsyncMock) as mock_test:
                    mock_test.return_value = (True, None)
                    response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["error"] is None
        assert data["provider"] == "openai"
        assert data["model"] == "gpt-4o"

    def test_test_connection_openai_failure(self, client, mock_felix_config):
        """Test returns error for invalid OpenAI API key"""
        with patch('routers.copilot.os.getenv', return_value="sk-invalid-key"):
            with patch('routers.copilot.load_global_config', return_value=mock_felix_config):
                with patch('routers.copilot.verify_openai_connection', new_callable=AsyncMock) as mock_test:
                    mock_test.return_value = (False, "Invalid API key")
                    response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert data["error"] == "Invalid API key"

    def test_test_connection_anthropic_success(self, client):
        """Test returns success for valid Anthropic API key"""
        anthropic_config = FelixConfig(
            copilot=CopilotConfig(
                enabled=True,
                provider="anthropic",
                model="claude-3-5-sonnet-20241022",
                context_sources=CopilotContextSourcesConfig(),
                features=CopilotFeaturesConfig()
            )
        )
        
        with patch('routers.copilot.os.getenv', return_value="sk-ant-test-key"):
            with patch('routers.copilot.load_global_config', return_value=anthropic_config):
                with patch('routers.copilot.verify_anthropic_connection', new_callable=AsyncMock) as mock_test:
                    mock_test.return_value = (True, None)
                    response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["provider"] == "anthropic"
        assert data["model"] == "claude-3-5-sonnet-20241022"

    def test_test_connection_custom_provider(self, client):
        """Test returns success for custom provider (no validation needed)"""
        custom_config = FelixConfig(
            copilot=CopilotConfig(
                enabled=True,
                provider="custom",
                model="my-custom-model",
                context_sources=CopilotContextSourcesConfig(),
                features=CopilotFeaturesConfig()
            )
        )
        
        with patch('routers.copilot.os.getenv', return_value="custom-api-key"):
            with patch('routers.copilot.load_global_config', return_value=custom_config):
                response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["provider"] == "custom"
        assert data["model"] == "my-custom-model"

    def test_test_connection_no_copilot_config(self, client):
        """Test uses defaults when copilot config doesn't exist"""
        config_without_copilot = FelixConfig(copilot=None)
        
        with patch('routers.copilot.os.getenv', return_value="sk-test-key"):
            with patch('routers.copilot.load_global_config', return_value=config_without_copilot):
                with patch('routers.copilot.verify_openai_connection', new_callable=AsyncMock) as mock_test:
                    mock_test.return_value = (True, None)
                    response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        # Should use defaults
        assert data["provider"] == "openai"
        assert data["model"] == "gpt-4o"

    def test_test_connection_unsupported_provider(self, client):
        """Test returns error for unsupported provider"""
        unsupported_config = FelixConfig(
            copilot=CopilotConfig(
                enabled=True,
                provider="unsupported",
                model="some-model",
                context_sources=CopilotContextSourcesConfig(),
                features=CopilotFeaturesConfig()
            )
        )
        
        with patch('routers.copilot.os.getenv', return_value="some-api-key"):
            with patch('routers.copilot.load_global_config', return_value=unsupported_config):
                response = client.post("/api/copilot/test")
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "unsupported" in data["error"].lower()


class TestCopilotStatusEndpoint:
    """Tests for GET /api/copilot/status endpoint"""

    def test_status_no_copilot_config(self, client):
        """Test status returns unconfigured when no copilot config exists"""
        config_without_copilot = FelixConfig(copilot=None)
        
        with patch('routers.copilot.load_global_config', return_value=config_without_copilot):
            with patch('routers.copilot.os.getenv', return_value=""):
                response = client.get("/api/copilot/status")
        
        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is False
        assert data["configured"] is False
        assert data["api_key_present"] is False

    def test_status_with_copilot_config_enabled(self, client, mock_felix_config):
        """Test status returns enabled when copilot is configured and enabled"""
        with patch('routers.copilot.load_global_config', return_value=mock_felix_config):
            with patch('routers.copilot.os.getenv', return_value="sk-test-key"):
                response = client.get("/api/copilot/status")
        
        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is True
        assert data["configured"] is True
        assert data["api_key_present"] is True
        assert data["provider"] == "openai"
        assert data["model"] == "gpt-4o"

    def test_status_with_copilot_disabled(self, client):
        """Test status returns disabled when copilot is configured but disabled"""
        disabled_config = FelixConfig(
            copilot=CopilotConfig(
                enabled=False,
                provider="openai",
                model="gpt-4o",
                context_sources=CopilotContextSourcesConfig(),
                features=CopilotFeaturesConfig()
            )
        )
        
        with patch('routers.copilot.load_global_config', return_value=disabled_config):
            with patch('routers.copilot.os.getenv', return_value="sk-test-key"):
                response = client.get("/api/copilot/status")
        
        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is False
        assert data["configured"] is True
        assert data["api_key_present"] is True

    def test_status_no_api_key_in_env(self, client, mock_felix_config):
        """Test status shows api_key_present=False when no key in environment"""
        with patch('routers.copilot.load_global_config', return_value=mock_felix_config):
            with patch('routers.copilot.os.getenv', return_value=""):
                response = client.get("/api/copilot/status")
        
        assert response.status_code == 200
        data = response.json()
        assert data["api_key_present"] is False


class TestOpenAIConnection:
    """Tests for OpenAI connection testing"""

    @pytest.mark.asyncio
    async def test_openai_success_response(self):
        """Test OpenAI returns success on 200 response"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_openai_connection("sk-test", "gpt-4o")
            
            assert success is True
            assert error is None

    @pytest.mark.asyncio
    async def test_openai_invalid_api_key(self):
        """Test OpenAI returns error on 401 response"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 401
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_openai_connection("sk-invalid", "gpt-4o")
            
            assert success is False
            assert "Invalid API key" in error

    @pytest.mark.asyncio
    async def test_openai_model_not_found(self):
        """Test OpenAI returns error on 404 response"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 404
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_openai_connection("sk-test", "nonexistent-model")
            
            assert success is False
            assert "not found" in error.lower()

    @pytest.mark.asyncio
    async def test_openai_rate_limit_success(self):
        """Test OpenAI returns success on 429 (rate limit means key is valid)"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 429
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_openai_connection("sk-test", "gpt-4o")
            
            assert success is True
            assert error is None


class TestAnthropicConnection:
    """Tests for Anthropic connection testing"""

    @pytest.mark.asyncio
    async def test_anthropic_success_response(self):
        """Test Anthropic returns success on 200 response"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_anthropic_connection("sk-ant-test", "claude-3-5-sonnet-20241022")
            
            assert success is True
            assert error is None

    @pytest.mark.asyncio
    async def test_anthropic_invalid_api_key(self):
        """Test Anthropic returns error on 401 response"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 401
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_anthropic_connection("sk-ant-invalid", "claude-3-5-sonnet-20241022")
            
            assert success is False
            assert "Invalid API key" in error

    @pytest.mark.asyncio
    async def test_anthropic_rate_limit_success(self):
        """Test Anthropic returns success on 429 (rate limit means key is valid)"""
        with patch('routers.copilot.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_response = MagicMock()
            mock_response.status_code = 429
            mock_client.post.return_value = mock_response
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            success, error = await verify_anthropic_connection("sk-ant-test", "claude-3-5-sonnet-20241022")
            
            assert success is True
            assert error is None


class TestCopilotConfigSaveLoad:
    """Tests for copilot config persistence in global settings"""

    def test_global_settings_returns_copilot_config(self, client, mock_felix_config):
        """Test that global settings endpoint includes copilot config"""
        with patch('routers.settings.load_global_config', return_value=mock_felix_config):
            response = client.get("/api/settings")
        
        assert response.status_code == 200
        data = response.json()
        assert "copilot" in data["config"]
        assert data["config"]["copilot"]["enabled"] is True
        assert data["config"]["copilot"]["provider"] == "openai"
        assert data["config"]["copilot"]["model"] == "gpt-4o"

    def test_global_settings_saves_copilot_config(self, client, tmp_path):
        """Test that updating global settings saves copilot config"""
        config_file = tmp_path / "config.json"
        config_file.write_text("{}", encoding='utf-8')
        
        config_data = {
            "version": "0.1.0",
            "executor": {"mode": "local", "max_iterations": 10, "default_mode": "building", "auto_transition": True},
            "agent": {"name": "felix-primary", "executable": "droid", "args": [], "working_directory": ".", "environment": {}},
            "paths": {"specs": "specs", "agents": "AGENTS.md", "runs": "runs"},
            "backpressure": {"enabled": True, "commands": [], "max_retries": 3},
            "ui": {"theme": "dark"},
            "copilot": {
                "enabled": True,
                "provider": "anthropic",
                "model": "claude-3-5-sonnet-20241022",
                "context_sources": {
                    "agents_md": True,
                    "learnings_md": False,
                    "prompt_md": True,
                    "requirements": True,
                    "other_specs": False
                },
                "features": {
                    "streaming": True,
                    "auto_suggest": False,
                    "context_aware": True
                }
            }
        }
        
        with patch('routers.settings.get_global_config_path', return_value=config_file):
            response = client.put("/api/settings", json={"config": config_data})
        
        assert response.status_code == 200
        
        # Read the saved file and verify
        saved_data = json.loads(config_file.read_text(encoding='utf-8'))
        assert saved_data["copilot"]["enabled"] is True
        assert saved_data["copilot"]["provider"] == "anthropic"
        assert saved_data["copilot"]["model"] == "claude-3-5-sonnet-20241022"
        assert saved_data["copilot"]["context_sources"]["learnings_md"] is False
        assert saved_data["copilot"]["features"]["auto_suggest"] is False

    def test_global_settings_default_copilot_none(self, client, tmp_path):
        """Test that global settings returns None for copilot when not configured"""
        config_file = tmp_path / "config.json"
        # Write config without copilot section
        config_data = {
            "version": "0.1.0",
            "executor": {"mode": "local", "max_iterations": 10, "default_mode": "building", "auto_transition": True},
            "agent": {"name": "felix-primary", "executable": "droid", "args": [], "working_directory": ".", "environment": {}},
            "paths": {"specs": "specs", "agents": "AGENTS.md", "runs": "runs"},
            "backpressure": {"enabled": True, "commands": [], "max_retries": 3},
            "ui": {"theme": "dark"}
        }
        config_file.write_text(json.dumps(config_data), encoding='utf-8')
        
        with patch('routers.settings.get_global_config_path', return_value=config_file):
            response = client.get("/api/settings")
        
        assert response.status_code == 200
        data = response.json()
        # copilot should be None when not configured
        assert data["config"]["copilot"] is None

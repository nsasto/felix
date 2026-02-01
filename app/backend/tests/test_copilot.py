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
        features=CopilotFeaturesConfig(),
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
            if "FELIX_COPILOT_API_KEY" in os.environ:
                del os.environ["FELIX_COPILOT_API_KEY"]

            with patch("routers.copilot.os.getenv", return_value=None):
                response = client.post("/api/copilot/test")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "not configured" in data["error"].lower()

    def test_test_connection_empty_api_key(self, client):
        """Test returns error when FELIX_COPILOT_API_KEY is empty"""
        with patch("routers.copilot.os.getenv", return_value="   "):
            response = client.post("/api/copilot/test")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "not configured" in data["error"].lower()

    def test_test_connection_openai_success(self, client, mock_felix_config):
        """Test returns success for valid OpenAI API key"""
        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.verify_openai_connection", new_callable=AsyncMock
                ) as mock_test:
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
        with patch("routers.copilot.os.getenv", return_value="sk-invalid-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.verify_openai_connection", new_callable=AsyncMock
                ) as mock_test:
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
                features=CopilotFeaturesConfig(),
            )
        )

        with patch("routers.copilot.os.getenv", return_value="sk-ant-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(anthropic_config, None),
            ):
                with patch(
                    "routers.copilot.verify_anthropic_connection",
                    new_callable=AsyncMock,
                ) as mock_test:
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
                features=CopilotFeaturesConfig(),
            )
        )

        with patch("routers.copilot.os.getenv", return_value="custom-api-key"):
            with patch(
                "routers.copilot.load_global_config", return_value=(custom_config, None)
            ):
                response = client.post("/api/copilot/test")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["provider"] == "custom"
        assert data["model"] == "my-custom-model"

    def test_test_connection_no_copilot_config(self, client):
        """Test uses defaults when copilot config doesn't exist"""
        config_without_copilot = FelixConfig(copilot=None)

        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(config_without_copilot, None),
            ):
                with patch(
                    "routers.copilot.verify_openai_connection", new_callable=AsyncMock
                ) as mock_test:
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
                features=CopilotFeaturesConfig(),
            )
        )

        with patch("routers.copilot.os.getenv", return_value="some-api-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(unsupported_config, None),
            ):
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

        with patch(
            "routers.copilot.load_global_config",
            return_value=(config_without_copilot, None),
        ):
            with patch("routers.copilot.os.getenv", return_value=""):
                response = client.get("/api/copilot/status")

        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is False
        assert data["configured"] is False
        assert data["api_key_present"] is False

    def test_status_with_copilot_config_enabled(self, client, mock_felix_config):
        """Test status returns enabled when copilot is configured and enabled"""
        with patch(
            "routers.copilot.load_global_config", return_value=(mock_felix_config, None)
        ):
            with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
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
                features=CopilotFeaturesConfig(),
            )
        )

        with patch(
            "routers.copilot.load_global_config", return_value=(disabled_config, None)
        ):
            with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
                response = client.get("/api/copilot/status")

        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is False
        assert data["configured"] is True
        assert data["api_key_present"] is True

    def test_status_no_api_key_in_env(self, client, mock_felix_config):
        """Test status shows api_key_present=False when no key in environment"""
        with patch(
            "routers.copilot.load_global_config", return_value=(mock_felix_config, None)
        ):
            with patch("routers.copilot.os.getenv", return_value=""):
                response = client.get("/api/copilot/status")

        assert response.status_code == 200
        data = response.json()
        assert data["api_key_present"] is False


class TestOpenAIConnection:
    """Tests for OpenAI connection testing"""

    @pytest.mark.asyncio
    async def test_openai_success_response(self):
        """Test OpenAI returns success on 200 response"""
        with patch("openai.AsyncOpenAI") as mock_openai_class:
            mock_client = MagicMock()
            mock_client.chat = MagicMock()
            mock_client.chat.completions = MagicMock()
            mock_client.chat.completions.create = AsyncMock(return_value=MagicMock())
            mock_openai_class.return_value = mock_client

            success, error = await verify_openai_connection("sk-test", "gpt-4o")

            assert success is True
            assert error is None

    @pytest.mark.asyncio
    async def test_openai_invalid_api_key(self):
        """Test OpenAI returns error on 401 response"""
        from openai import AuthenticationError
        from unittest.mock import MagicMock as MM

        with patch("openai.AsyncOpenAI") as mock_openai_class:
            mock_client = MagicMock()
            mock_client.chat = MagicMock()
            mock_client.chat.completions = MagicMock()
            # Create a mock request object for the AuthenticationError
            mock_request = MM()
            mock_request.url = "https://api.openai.com/v1/chat/completions"
            mock_client.chat.completions.create = AsyncMock(
                side_effect=AuthenticationError(
                    message="Invalid API key", response=MM(status_code=401), body={}
                )
            )
            mock_openai_class.return_value = mock_client

            success, error = await verify_openai_connection("sk-invalid", "gpt-4o")

            assert success is False
            assert "Invalid API key" in error

    @pytest.mark.asyncio
    async def test_openai_model_not_found(self):
        """Test OpenAI returns error on 404 response"""
        with patch("openai.AsyncOpenAI") as mock_openai_class:
            mock_client = MagicMock()
            mock_client.chat = MagicMock()
            mock_client.chat.completions = MagicMock()
            mock_client.chat.completions.create = AsyncMock(
                side_effect=Exception("Model 'nonexistent-model' not found")
            )
            mock_openai_class.return_value = mock_client

            success, error = await verify_openai_connection(
                "sk-test", "nonexistent-model"
            )

            assert success is False
            assert "not found" in error.lower()

    @pytest.mark.asyncio
    async def test_openai_rate_limit_success(self):
        """Test OpenAI returns success on 429 (rate limit means key is valid)"""
        from openai import RateLimitError
        from unittest.mock import MagicMock as MM

        with patch("openai.AsyncOpenAI") as mock_openai_class:
            mock_client = MagicMock()
            mock_client.chat = MagicMock()
            mock_client.chat.completions = MagicMock()
            mock_client.chat.completions.create = AsyncMock(
                side_effect=RateLimitError(
                    message="Rate limit exceeded", response=MM(status_code=429), body={}
                )
            )
            mock_openai_class.return_value = mock_client

            success, error = await verify_openai_connection("sk-test", "gpt-4o")

            assert success is True
            assert error is None


class TestAnthropicConnection:
    """Tests for Anthropic connection testing"""

    @pytest.mark.asyncio
    async def test_anthropic_success_response(self):
        """Test Anthropic returns success on 200 response"""
        with patch("anthropic.AsyncAnthropic") as mock_anthropic_class:
            mock_client = MagicMock()
            mock_client.messages = MagicMock()
            mock_client.messages.create = AsyncMock(return_value=MagicMock())
            mock_anthropic_class.return_value = mock_client

            success, error = await verify_anthropic_connection(
                "sk-ant-test", "claude-3-5-sonnet-20241022"
            )

            assert success is True
            assert error is None

    @pytest.mark.asyncio
    async def test_anthropic_invalid_api_key(self):
        """Test Anthropic returns error on 401 response"""
        from anthropic import AuthenticationError
        from unittest.mock import MagicMock as MM

        with patch("anthropic.AsyncAnthropic") as mock_anthropic_class:
            mock_client = MagicMock()
            mock_client.messages = MagicMock()
            mock_response = MM()
            mock_response.status_code = 401
            mock_client.messages.create = AsyncMock(
                side_effect=AuthenticationError(
                    message="Invalid API key", response=mock_response, body={}
                )
            )
            mock_anthropic_class.return_value = mock_client

            success, error = await verify_anthropic_connection(
                "sk-ant-invalid", "claude-3-5-sonnet-20241022"
            )

            assert success is False
            assert "Invalid API key" in error

    @pytest.mark.asyncio
    async def test_anthropic_rate_limit_success(self):
        """Test Anthropic returns success on 429 (rate limit means key is valid)"""
        from anthropic import RateLimitError
        from unittest.mock import MagicMock as MM

        with patch("anthropic.AsyncAnthropic") as mock_anthropic_class:
            mock_client = MagicMock()
            mock_client.messages = MagicMock()
            mock_response = MM()
            mock_response.status_code = 429
            mock_client.messages.create = AsyncMock(
                side_effect=RateLimitError(
                    message="Rate limit exceeded", response=mock_response, body={}
                )
            )
            mock_anthropic_class.return_value = mock_client

            success, error = await verify_anthropic_connection(
                "sk-ant-test", "claude-3-5-sonnet-20241022"
            )

            assert success is True
            assert error is None


class TestCopilotStreamEndpoint:
    """Tests for POST /api/copilot/chat/stream endpoint (S-0017)"""

    def test_stream_endpoint_returns_sse_media_type(self, client, mock_felix_config):
        """Streaming endpoint returns correct SSE media type"""
        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    # Mock service
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = [
                        {"role": "user", "content": "test"}
                    ]

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "thinking"}\n\n'
                        yield 'data: {"avatar_state": "speaking"}\n\n'
                        yield 'data: {"token": "Hello"}\n\n'
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test message", "history": []},
                    )

        assert response.status_code == 200
        assert "text/event-stream" in response.headers.get("content-type", "")

    def test_stream_endpoint_sends_avatar_state_events(self, client, mock_felix_config):
        """Streaming includes avatar state transitions"""
        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = [
                        {"role": "user", "content": "test"}
                    ]

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "thinking"}\n\n'
                        yield 'data: {"avatar_state": "speaking"}\n\n'
                        yield 'data: {"token": "Hello"}\n\n'
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test message", "history": []},
                    )

        content = response.text
        assert "thinking" in content
        assert "speaking" in content
        assert "idle" in content

    def test_stream_endpoint_with_conversation_history(self, client, mock_felix_config):
        """Streaming endpoint accepts and processes conversation history"""
        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = []

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "thinking"}\n\n'
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={
                            "message": "follow up question",
                            "history": [
                                {"role": "user", "content": "first message"},
                                {"role": "assistant", "content": "first response"},
                            ],
                        },
                    )

        assert response.status_code == 200
        # Verify history was passed to build_messages
        mock_service.build_messages.assert_called_once()

    def test_stream_endpoint_with_project_path(
        self, client, mock_felix_config, tmp_path
    ):
        """Streaming endpoint loads context when project_path provided"""
        # Create mock project files
        project_dir = tmp_path / "test_project"
        project_dir.mkdir()
        (project_dir / "AGENTS.md").write_text("# Test Agents", encoding="utf-8")

        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {
                        "agents_md": "# Test Agents"
                    }
                    mock_service.trim_context_for_token_budget.return_value = {
                        "agents_md": "# Test Agents"
                    }
                    mock_service.build_system_prompt.return_value = (
                        "test prompt with context"
                    )
                    mock_service.build_messages.return_value = []

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={
                            "message": "test",
                            "history": [],
                            "project_path": str(project_dir),
                        },
                    )

        assert response.status_code == 200
        mock_service.load_context.assert_called_once()

    def test_stream_endpoint_error_handling(self, client, mock_felix_config):
        """Streaming endpoint handles errors gracefully via error events"""
        with patch("routers.copilot.os.getenv", return_value="sk-test-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = []

                    # Simulate error in stream
                    async def mock_stream_error(*args, **kwargs):
                        yield 'data: {"avatar_state": "thinking"}\n\n'
                        yield 'data: {"error": "API connection failed", "avatar_state": "error"}\n\n'

                    mock_service.stream_response = mock_stream_error
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test", "history": []},
                    )

        assert response.status_code == 200  # SSE streams return 200 even with errors
        content = response.text
        assert "error" in content
        assert "API connection failed" in content
        assert "avatar_state" in content


class TestCopilotService:
    """Tests for CopilotService class (S-0017)"""

    def test_service_default_configuration(self):
        """Service uses default configuration when not provided"""
        from services.copilot import CopilotService, CopilotConfig

        service = CopilotService()
        assert service.config.provider == "openai"
        assert service.config.model == "gpt-4o"
        assert service.config.enabled is True

    def test_service_custom_configuration(self):
        """Service accepts custom configuration"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(
            provider="anthropic", model="claude-3-5-sonnet-20241022", enabled=True
        )
        service = CopilotService(config)

        assert service.config.provider == "anthropic"
        assert service.config.model == "claude-3-5-sonnet-20241022"

    def test_service_validate_configuration_disabled(self):
        """Validation fails when copilot is disabled"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=False)
        service = CopilotService(config)

        is_valid, error = service.validate_configuration()
        assert is_valid is False
        assert "disabled" in error.lower()

    def test_service_validate_configuration_no_api_key(self):
        """Validation fails when API key is not set"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True)
        service = CopilotService(config)

        with patch.dict(os.environ, {}, clear=True):
            with patch("services.copilot.os.getenv", return_value=""):
                # Force re-evaluation by clearing cached env key
                service._env_api_key = None
                is_valid, error = service.validate_configuration()

        assert is_valid is False
        assert "not configured" in error.lower()

    def test_service_validate_configuration_unsupported_provider(self):
        """Validation fails for unsupported provider"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True, provider="unknown")
        # Provide API key via constructor (correct way)
        service = CopilotService(config, api_key="test-key")

        is_valid, error = service.validate_configuration()
        assert is_valid is False
        assert "unsupported" in error.lower()

    def test_service_load_context(self, tmp_path):
        """Service loads project context files (excluding requirements - S-0032)"""
        from services.copilot import CopilotService

        # Create test project files
        (tmp_path / "AGENTS.md").write_text("# Agent Guidelines", encoding="utf-8")
        (tmp_path / "LEARNINGS.md").write_text("# Project Learnings", encoding="utf-8")
        (tmp_path / "prompt.md").write_text("# Spec Template", encoding="utf-8")
        # Note: requirements.json file no longer loaded per S-0032
        (tmp_path / "specs").mkdir()
        (tmp_path / "specs" / "S-0001.md").write_text("# Spec 1", encoding="utf-8")

        service = CopilotService()
        context = service.load_context(tmp_path)

        assert "agents_md" in context
        assert "Agent Guidelines" in context["agents_md"]
        assert "learnings_md" in context
        assert "prompt_md" in context
        # S-0032: requirements context removed - will be database-driven in Phase 0
        assert "requirements" not in context
        assert "other_specs" in context
        assert "S-0001" in context["other_specs"]

    def test_service_load_context_respects_disabled_sources(self, tmp_path):
        """Service respects disabled context sources"""
        from services.copilot import CopilotService, CopilotConfig

        # Create test project files
        (tmp_path / "AGENTS.md").write_text("# Agent Guidelines", encoding="utf-8")
        (tmp_path / "LEARNINGS.md").write_text("# Project Learnings", encoding="utf-8")

        config = CopilotConfig(
            context_sources={
                "agents_md": True,
                "learnings_md": False,  # Disabled
                "prompt_md": True,
                "requirements": True,
                "other_specs": True,
            }
        )
        service = CopilotService(config)
        context = service.load_context(tmp_path)

        assert "agents_md" in context
        assert "learnings_md" not in context  # Should not be loaded

    def test_service_build_system_prompt_empty_context(self):
        """Service builds base prompt with no context"""
        from services.copilot import CopilotService

        service = CopilotService()
        prompt = service.build_system_prompt({})

        assert "Felix Copilot" in prompt
        assert "technical specifications" in prompt.lower()
        assert "Project Context" not in prompt

    def test_service_build_system_prompt_with_context(self):
        """Service builds prompt with context sections (excluding requirements - S-0032)"""
        from services.copilot import CopilotService

        service = CopilotService()
        # S-0032: requirements context removed - will be database-driven in Phase 0
        context = {
            "agents_md": "# Agent Guidelines\nBuild fast.",
            "learnings_md": "# Project Learnings\nImportant lesson.",
        }
        prompt = service.build_system_prompt(context)

        assert "Felix Copilot" in prompt
        assert "Project Context" in prompt
        assert "Agent Guidelines" in prompt
        assert "Project Learnings" in prompt
        # Requirements no longer included in system prompt per S-0032
        assert "requirements.json" not in prompt

    def test_service_build_messages_with_history(self):
        """Service builds messages including history"""
        from services.copilot import CopilotService, ChatMessage

        service = CopilotService()
        history = [
            ChatMessage(role="user", content="Hello"),
            ChatMessage(role="assistant", content="Hi there!"),
        ]

        messages = service.build_messages("System prompt", history, "New question")

        assert len(messages) == 4  # system + 2 history + user
        assert messages[0]["role"] == "system"
        assert messages[1]["role"] == "user"
        assert messages[1]["content"] == "Hello"
        assert messages[2]["role"] == "assistant"
        assert messages[3]["role"] == "user"
        assert messages[3]["content"] == "New question"

    def test_service_build_messages_limits_history(self):
        """Service limits history to MAX_CONTEXT_MESSAGES"""
        from services.copilot import CopilotService, ChatMessage

        service = CopilotService()
        # Create 15 history messages
        history = [
            ChatMessage(
                role="user" if i % 2 == 0 else "assistant", content=f"Message {i}"
            )
            for i in range(15)
        ]

        messages = service.build_messages("System prompt", history, "New question")

        # Should be: system + 10 history (MAX_CONTEXT_MESSAGES) + user = 12
        assert len(messages) == 12
        # First history message should be Message 5 (last 10 of 0-14)
        assert messages[1]["content"] == "Message 5"

    def test_service_trim_context_for_token_budget(self):
        """Service trims context when exceeding token budget"""
        from services.copilot import CopilotService

        service = CopilotService()
        # Create large context (each char ~0.25 tokens, so 40k chars = ~10k tokens)
        large_content = "x" * 40000
        context = {"agents_md": large_content}

        trimmed = service.trim_context_for_token_budget(context)

        # Should be trimmed
        assert len(trimmed["agents_md"]) < len(large_content)
        assert "[...truncated...]" in trimmed["agents_md"]

    def test_service_trim_context_preserves_small_context(self):
        """Service preserves context under token budget"""
        from services.copilot import CopilotService

        service = CopilotService()
        context = {"agents_md": "Small content"}

        trimmed = service.trim_context_for_token_budget(context)

        assert trimmed["agents_md"] == "Small content"


class TestCopilotConfigSaveLoad:
    """Tests for copilot config persistence in global settings"""

    def test_global_settings_returns_copilot_config(self, client, mock_felix_config):
        """Test that global settings endpoint includes copilot config"""
        with patch(
            "routers.settings.load_global_config",
            return_value=(mock_felix_config, None),
        ):
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
        config_file.write_text("{}", encoding="utf-8")

        config_data = {
            "version": "0.1.0",
            "executor": {
                "mode": "local",
                "max_iterations": 10,
                "default_mode": "building",
                "auto_transition": True,
            },
            "agent": {"agent_id": 0},  # Use agent_id format (ID 0 = system default)
            "paths": {"specs": "specs", "agents": "AGENTS.md", "runs": "runs"},
            "backpressure": {"enabled": True, "commands": [], "max_retries": 3},
            "ui": {},
            "copilot": {
                "enabled": True,
                "provider": "anthropic",
                "model": "claude-3-5-sonnet-20241022",
                "context_sources": {
                    "agents_md": True,
                    "learnings_md": False,
                    "prompt_md": True,
                    "requirements": True,
                    "other_specs": False,
                },
                "features": {
                    "streaming": True,
                    "auto_suggest": False,
                    "context_aware": True,
                },
            },
        }

        # Mock validate_agent_id_exists to return True for ID 0
        with patch("routers.settings.get_global_config_path", return_value=config_file):
            with patch("routers.settings.validate_agent_id_exists", return_value=True):
                response = client.put("/api/settings", json={"config": config_data})

        assert response.status_code == 200

        # Read the saved file and verify
        saved_data = json.loads(config_file.read_text(encoding="utf-8"))
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
            "executor": {
                "mode": "local",
                "max_iterations": 10,
                "default_mode": "building",
                "auto_transition": True,
            },
            "agent": {
                "name": "felix-primary",
                "executable": "droid",
                "args": [],
                "working_directory": ".",
                "environment": {},
            },
            "paths": {"specs": "specs", "agents": "AGENTS.md", "runs": "runs"},
            "backpressure": {"enabled": True, "commands": [], "max_retries": 3},
            "ui": {},
        }
        config_file.write_text(json.dumps(config_data), encoding="utf-8")

        with patch("routers.settings.get_global_config_path", return_value=config_file):
            response = client.get("/api/settings")

        assert response.status_code == 200
        data = response.json()
        # copilot should be None when not configured
        assert data["config"]["copilot"] is None


class TestApiKeyHeaderSupport:
    """Tests for API key header support (S-0022: Move Copilot API Key to Browser Storage)"""

    def test_test_endpoint_uses_header_api_key(self, client, mock_felix_config):
        """Test endpoint uses X-Copilot-API-Key header when provided"""
        with patch("routers.copilot.os.getenv", return_value=None):  # No env var
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.verify_openai_connection", new_callable=AsyncMock
                ) as mock_verify:
                    mock_verify.return_value = (True, None)
                    response = client.post(
                        "/api/copilot/test",
                        headers={"X-Copilot-API-Key": "test-header-key-12345"},
                    )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        # Verify the header key was passed to verify_openai_connection
        mock_verify.assert_called_once()
        call_args = mock_verify.call_args[0]
        assert call_args[0] == "test-header-key-12345"

    def test_test_endpoint_header_takes_priority_over_env(
        self, client, mock_felix_config
    ):
        """Test that header API key takes priority over environment variable"""
        with patch(
            "routers.copilot.os.getenv", return_value="test-env-key"
        ):  # Env var set
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.verify_openai_connection", new_callable=AsyncMock
                ) as mock_verify:
                    mock_verify.return_value = (True, None)
                    response = client.post(
                        "/api/copilot/test",
                        headers={"X-Copilot-API-Key": "test-header-priority"},
                    )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        # Verify header key was used instead of env key
        mock_verify.assert_called_once()
        call_args = mock_verify.call_args[0]
        assert call_args[0] == "test-header-priority"

    def test_test_endpoint_falls_back_to_env_when_no_header(
        self, client, mock_felix_config
    ):
        """Test that env var is used when no header provided"""
        with patch("routers.copilot.os.getenv", return_value="test-env-fallback"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.verify_openai_connection", new_callable=AsyncMock
                ) as mock_verify:
                    mock_verify.return_value = (True, None)
                    response = client.post("/api/copilot/test")  # No header

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        # Verify env key was used as fallback
        mock_verify.assert_called_once()
        call_args = mock_verify.call_args[0]
        assert call_args[0] == "test-env-fallback"

    def test_test_endpoint_returns_error_when_no_key_available(self, client):
        """Test returns error when neither header nor env var provides API key"""
        with patch("routers.copilot.os.getenv", return_value=None):
            response = client.post("/api/copilot/test")  # No header

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "api key" in data["error"].lower()
        assert "not configured" in data["error"].lower()

    def test_stream_endpoint_uses_header_api_key(self, client, mock_felix_config):
        """Stream endpoint uses X-Copilot-API-Key header when provided"""
        with patch("routers.copilot.os.getenv", return_value=None):  # No env var
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = []

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "thinking"}\n\n'
                        yield 'data: {"token": "Hello"}\n\n'
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test message", "history": []},
                        headers={"X-Copilot-API-Key": "test-header-stream-key"},
                    )

        assert response.status_code == 200
        # Verify service was created with header API key
        mock_service_factory.assert_called_once()
        call_kwargs = mock_service_factory.call_args[1]
        assert call_kwargs["api_key"] == "test-header-stream-key"

    def test_stream_endpoint_header_priority_over_env(self, client, mock_felix_config):
        """Stream endpoint: header API key takes priority over env var"""
        with patch("routers.copilot.os.getenv", return_value="test-env-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = []

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test", "history": []},
                        headers={"X-Copilot-API-Key": "test-header-priority"},
                    )

        assert response.status_code == 200
        # Verify header key was used instead of env
        call_kwargs = mock_service_factory.call_args[1]
        assert call_kwargs["api_key"] == "test-header-priority"

    def test_stream_endpoint_fallback_to_env_when_no_header(
        self, client, mock_felix_config
    ):
        """Stream endpoint: falls back to env var when no header provided"""
        with patch("routers.copilot.os.getenv", return_value="test-env-key"):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = []

                    async def mock_stream(*args, **kwargs):
                        yield 'data: {"avatar_state": "idle", "done": true}\n\n'

                    mock_service.stream_response = mock_stream
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test", "history": []},
                        # No header provided
                    )

        assert response.status_code == 200
        # When no header provided, api_key should be None (service uses env internally)
        call_kwargs = mock_service_factory.call_args[1]
        assert call_kwargs["api_key"] is None

    def test_stream_endpoint_error_when_no_key_available(
        self, client, mock_felix_config
    ):
        """Stream endpoint returns error event when no API key available"""
        # Create a config that's enabled but don't provide any API key
        with patch("routers.copilot.os.getenv", return_value=None):
            with patch(
                "routers.copilot.load_global_config",
                return_value=(mock_felix_config, None),
            ):
                with patch(
                    "routers.copilot.create_copilot_service_from_config"
                ) as mock_service_factory:
                    # Create a service that will fail validation
                    mock_service = MagicMock()
                    mock_service.load_context.return_value = {}
                    mock_service.trim_context_for_token_budget.return_value = {}
                    mock_service.build_system_prompt.return_value = "test prompt"
                    mock_service.build_messages.return_value = []

                    # Return error from stream_response when no API key
                    async def mock_stream_error(*args, **kwargs):
                        yield 'data: {"error": "API key not configured. Please add your API key in Settings.", "avatar_state": "error"}\n\n'

                    mock_service.stream_response = mock_stream_error
                    mock_service_factory.return_value = mock_service

                    response = client.post(
                        "/api/copilot/chat/stream",
                        json={"message": "test", "history": []},
                        # No header provided, no env var
                    )

        assert response.status_code == 200  # SSE returns 200 even on errors
        content = response.text
        assert "error" in content
        assert "api key" in content.lower() or "API key" in content


class TestCopilotServiceApiKey:
    """Tests for CopilotService API key handling"""

    def test_service_uses_provided_api_key(self):
        """Service uses explicitly provided API key"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True)
        service = CopilotService(config, api_key="test-provided-key")

        assert service.api_key == "test-provided-key"

    def test_service_provided_key_takes_priority(self):
        """Provided API key takes priority over environment variable"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True)

        with patch.dict(os.environ, {"FELIX_COPILOT_API_KEY": "test-env-key"}):
            service = CopilotService(config, api_key="test-provided-priority")
            # Force env key caching to trigger
            assert service.api_key == "test-provided-priority"

    def test_service_falls_back_to_env_when_no_provided_key(self):
        """Service falls back to env var when no key provided"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True)

        with patch("services.copilot.os.getenv", return_value="test-env-fallback"):
            service = CopilotService(config)
            # Reset env cache to allow fallback
            service._env_api_key = None
            assert service.api_key == "test-env-fallback"

    def test_service_returns_none_when_no_key_available(self):
        """Service returns None when no key available"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True)

        with patch("services.copilot.os.getenv", return_value=""):
            service = CopilotService(config)
            service._env_api_key = None
            assert service.api_key is None

    def test_service_set_api_key(self):
        """Service can dynamically set API key"""
        from services.copilot import CopilotService, CopilotConfig

        config = CopilotConfig(enabled=True)
        service = CopilotService(config)

        with patch("services.copilot.os.getenv", return_value=""):
            service._env_api_key = None
            assert service.api_key is None

            service.set_api_key("test-new-key")
            assert service.api_key == "test-new-key"

    def test_create_copilot_service_from_config_with_api_key(self):
        """Factory function passes API key to service"""
        from services.copilot import create_copilot_service_from_config, CopilotConfig

        copilot_config = MagicMock()
        copilot_config.provider = "openai"
        copilot_config.model = "gpt-4o"
        copilot_config.enabled = True
        copilot_config.context_sources.agents_md = True
        copilot_config.context_sources.learnings_md = True
        copilot_config.context_sources.prompt_md = True
        copilot_config.context_sources.requirements = True
        copilot_config.context_sources.other_specs = True

        service = create_copilot_service_from_config(
            copilot_config, api_key="test-factory-key"
        )

        assert service._provided_api_key == "test-factory-key"
        assert service.api_key == "test-factory-key"

    def test_create_copilot_service_from_config_no_api_key(self):
        """Factory function creates service without API key (uses env)"""
        from services.copilot import create_copilot_service_from_config

        copilot_config = MagicMock()
        copilot_config.provider = "openai"
        copilot_config.model = "gpt-4o"
        copilot_config.enabled = True
        copilot_config.context_sources.agents_md = True
        copilot_config.context_sources.learnings_md = True
        copilot_config.context_sources.prompt_md = True
        copilot_config.context_sources.requirements = True
        copilot_config.context_sources.other_specs = True

        service = create_copilot_service_from_config(copilot_config)

        assert service._provided_api_key is None

"""
Felix Backend - CopilotService
Handles LLM integration, context loading, and conversation management for copilot chat.
"""

from typing import Optional, List, AsyncGenerator, Dict, Any
from pathlib import Path
from dataclasses import dataclass, field
import json
import os

from openai import (
    AsyncOpenAI,
    APIError,
    APIConnectionError,
    RateLimitError,
    APITimeoutError,
)
from anthropic import AsyncAnthropic, APIError as AnthropicAPIError


@dataclass
class CopilotConfig:
    """Configuration for the copilot service"""

    provider: str = "openai"
    model: str = "gpt-4o"
    enabled: bool = True
    context_sources: Dict[str, bool] = field(
        default_factory=lambda: {
            "agents_md": True,
            "learnings_md": True,
            "prompt_md": True,
            "requirements": True,
            "other_specs": True,
        }
    )


@dataclass
class ChatMessage:
    """A chat message in conversation history"""

    role: str  # 'user' or 'assistant'
    content: str


class CopilotService:
    """
    Service for copilot chat functionality.

    Handles:
    - LLM API streaming (OpenAI, Anthropic)
    - Project context loading
    - System prompt building
    - Conversation memory management
    """

    # Maximum messages to keep in context window
    MAX_CONTEXT_MESSAGES = 10

    # Maximum tokens for context trimming
    MAX_CONTEXT_TOKENS = 8000

    def __init__(
        self, config: Optional[CopilotConfig] = None, api_key: Optional[str] = None
    ):
        """
        Initialize the copilot service.

        Args:
            config: Copilot configuration. Uses defaults if not provided.
            api_key: Optional API key. If not provided, falls back to environment variable.
        """
        self.config = config or CopilotConfig()
        self._provided_api_key = api_key
        self._env_api_key: Optional[str] = None

    @property
    def api_key(self) -> Optional[str]:
        """
        Get API key with priority: provided key → environment variable.

        Returns:
            API key string or None if not configured
        """
        # First check if API key was explicitly provided
        if self._provided_api_key:
            return (
                self._provided_api_key.strip()
                if self._provided_api_key.strip()
                else None
            )

        # Fall back to environment variable (lazy loading)
        if self._env_api_key is None:
            self._env_api_key = os.getenv("FELIX_COPILOT_API_KEY", "").strip()
        return self._env_api_key if self._env_api_key else None

    def set_api_key(self, api_key: Optional[str]) -> None:
        """
        Set the API key to use for requests.

        Args:
            api_key: The API key to use, or None to fall back to env var
        """
        self._provided_api_key = api_key

    def validate_configuration(self) -> tuple[bool, Optional[str]]:
        """
        Validate copilot configuration.

        Returns:
            Tuple of (is_valid, error_message)
        """
        if not self.config.enabled:
            return False, "Copilot is disabled in settings"

        if not self.api_key:
            return False, "API key not configured. Please add your API key in Settings."

        if self.config.provider not in ["openai", "anthropic", "custom"]:
            return False, f"Unsupported provider: {self.config.provider}"

        return True, None

    def load_context(self, project_path: Path) -> Dict[str, str]:
        """
        Load project context files.

        Args:
            project_path: Path to the project root

        Returns:
            Dictionary of context source names to content
        """
        context = {}
        sources = self.config.context_sources

        # Load AGENTS.md
        if sources.get("agents_md", True):
            agents_path = project_path / "AGENTS.md"
            if agents_path.exists():
                try:
                    content = agents_path.read_text(encoding="utf-8-sig")
                    context["agents_md"] = self._trim_content(content, 4000)
                except Exception:
                    pass

        # Load LEARNINGS.md
        if sources.get("learnings_md", True):
            learnings_path = project_path / "LEARNINGS.md"
            if learnings_path.exists():
                try:
                    content = learnings_path.read_text(encoding="utf-8-sig")
                    context["learnings_md"] = self._trim_content(content, 2000)
                except Exception:
                    pass

        # Load prompt.md
        if sources.get("prompt_md", True):
            prompt_path = project_path / "prompt.md"
            if prompt_path.exists():
                try:
                    content = prompt_path.read_text(encoding="utf-8-sig")
                    context["prompt_md"] = self._trim_content(content, 3000)
                except Exception:
                    pass

        # S-0032: requirements.json reading removed - will be database-driven in Phase 0
        # Requirements context will be provided via database query in future implementation

        # Load other specs (summary only)
        if sources.get("other_specs", True):
            specs_dir = project_path / "specs"
            if specs_dir.exists():
                try:
                    spec_files = list(specs_dir.glob("*.md"))
                    if spec_files:
                        spec_list = [f.stem for f in spec_files[:20]]  # Max 20 specs
                        context["other_specs"] = (
                            f"Available specs: {', '.join(spec_list)}"
                        )
                except Exception:
                    pass

        return context

    def _trim_content(self, content: str, max_chars: int) -> str:
        """Trim content to maximum character length"""
        if len(content) <= max_chars:
            return content
        return content[:max_chars] + "\n[...truncated...]"

    def build_system_prompt(self, context: Dict[str, str]) -> str:
        """
        Build system prompt with project context.

        Args:
            context: Dictionary of loaded context content

        Returns:
            Complete system prompt string
        """
        base_prompt = """You are Felix Copilot, an AI assistant specialized in helping users write technical specifications.

You have access to the project's context files to help you understand conventions and provide accurate suggestions.

When drafting specs:
- Follow the project's existing spec format
- Use markdown formatting
- Include clear acceptance criteria
- Add validation criteria where appropriate
- Reference dependencies when relevant

Be concise, helpful, and maintain a professional yet friendly tone."""

        context_parts = []

        if "agents_md" in context:
            context_parts.append(
                f"## AGENTS.md (Project Guidelines)\n{context['agents_md']}"
            )

        if "learnings_md" in context:
            context_parts.append(
                f"## LEARNINGS.md (Project Learnings)\n{context['learnings_md']}"
            )

        if "prompt_md" in context:
            context_parts.append(
                f"## prompt.md (Spec Template)\n{context['prompt_md']}"
            )

        # S-0032: requirements context removed - will be database-driven in Phase 0

        if "other_specs" in context:
            context_parts.append(f"## Other Specs\n{context['other_specs']}")

        if context_parts:
            return (
                base_prompt + "\n\n# Project Context\n\n" + "\n\n".join(context_parts)
            )

        return base_prompt

    def build_messages(
        self, system_prompt: str, history: List[ChatMessage], user_message: str
    ) -> List[Dict[str, str]]:
        """
        Build message list for LLM API.

        Manages conversation memory by keeping only last N messages.

        Args:
            system_prompt: The system prompt
            history: Previous conversation messages
            user_message: Current user message

        Returns:
            List of messages formatted for LLM API
        """
        messages = [{"role": "system", "content": system_prompt}]

        # Add history (last N messages for context window management)
        for msg in history[-self.MAX_CONTEXT_MESSAGES :]:
            messages.append({"role": msg.role, "content": msg.content})

        # Add current user message
        messages.append({"role": "user", "content": user_message})

        return messages

    def trim_context_for_token_budget(self, context: Dict[str, str]) -> Dict[str, str]:
        """
        Trim context sources if total size exceeds token budget.

        Estimates ~4 characters per token and trims largest sources first.

        Args:
            context: Dictionary of context content

        Returns:
            Trimmed context dictionary
        """
        total_size = sum(len(v) for v in context.values())
        estimated_tokens = total_size // 4

        if estimated_tokens <= self.MAX_CONTEXT_TOKENS:
            return context

        # Trim sources in order of size (largest first)
        trimmed = dict(context)
        sources_by_size = sorted(
            trimmed.keys(), key=lambda k: len(trimmed.get(k, "")), reverse=True
        )

        for source in sources_by_size:
            if source in trimmed:
                current_len = len(trimmed[source])
                new_len = min(current_len, 2000)  # Trim to 2000 chars
                if new_len < current_len:
                    trimmed[source] = self._trim_content(trimmed[source], new_len)

            # Recalculate and check
            total_size = sum(len(v) for v in trimmed.values())
            if total_size // 4 <= self.MAX_CONTEXT_TOKENS:
                break

        return trimmed

    async def stream_response(
        self, messages: List[Dict[str, str]]
    ) -> AsyncGenerator[str, None]:
        """
        Stream LLM response based on configured provider.

        Yields SSE-formatted events:
        - {"avatar_state": "thinking", "stream_id": "..."} - Initial state
        - {"avatar_state": "speaking", "stream_id": "..."} - When streaming starts
        - {"token": "text", "token_id": "...", "stream_id": "..."} - Each token
        - {"avatar_state": "idle", "done": true, "stream_id": "..."} - Complete
        - {"error": "message", "avatar_state": "error", "stream_id": "..."} - On error

        Args:
            messages: List of messages for the LLM

        Yields:
            SSE event strings
        """
        import uuid

        # Generate unique stream ID for this response
        stream_id = str(uuid.uuid4())

        # Validate configuration
        is_valid, error = self.validate_configuration()
        if not is_valid:
            yield f"data: {json.dumps({'error': error, 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
            return

        # Signal thinking state with stream ID
        yield f"data: {json.dumps({'avatar_state': 'thinking', 'stream_id': stream_id})}\n\n"

        try:
            if self.config.provider == "openai":
                async for event in self._stream_openai(messages, stream_id):
                    yield event
            elif self.config.provider == "anthropic":
                async for event in self._stream_anthropic(messages, stream_id):
                    yield event
            else:
                yield f"data: {json.dumps({'error': f'Unsupported provider: {self.config.provider}', 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
                return

            # Signal completion with stream ID
            yield f"data: {json.dumps({'avatar_state': 'idle', 'done': True, 'stream_id': stream_id})}\n\n"

        except Exception as e:
            # Catch any unexpected errors not handled by provider-specific methods
            yield f"data: {json.dumps({'error': str(e), 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"

    async def _stream_openai(
        self, messages: List[Dict[str, str]], stream_id: str
    ) -> AsyncGenerator[str, None]:
        """Stream response from OpenAI API using official SDK with token deduplication"""
        try:
            client = AsyncOpenAI(api_key=self.api_key, timeout=60.0)

            # Signal speaking state
            yield f"data: {json.dumps({'avatar_state': 'speaking', 'stream_id': stream_id})}\n\n"

            token_counter = 0
            stream = await client.chat.completions.create(
                model=self.config.model, messages=messages, stream=True, max_tokens=4000
            )

            async for chunk in stream:
                if chunk.choices:
                    delta = chunk.choices[0].delta
                    if delta.content:
                        token_counter += 1
                        # Include token counter for frontend deduplication
                        event_data = {
                            "token": delta.content,
                            "token_id": f"{stream_id}_{token_counter}",
                            "stream_id": stream_id,
                        }
                        yield f"data: {json.dumps(event_data)}\n\n"

        except RateLimitError:
            yield f"data: {json.dumps({'error': 'Rate limit exceeded. Please try again later.', 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
        except APIConnectionError:
            yield f"data: {json.dumps({'error': 'Connection failed. Check your network.', 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
        except APITimeoutError:
            yield f"data: {json.dumps({'error': 'Request timed out. Please try again.', 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
        except APIError as e:
            error_msg = str(e)
            if "invalid" in error_msg.lower() and "api" in error_msg.lower():
                error_msg = "Invalid API key"
            yield f"data: {json.dumps({'error': error_msg, 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e), 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"

    async def _stream_anthropic(
        self, messages: List[Dict[str, str]], stream_id: str
    ) -> AsyncGenerator[str, None]:
        """Stream response from Anthropic API using official SDK with token deduplication"""
        try:
            # Extract system prompt (Anthropic uses separate system parameter)
            system_content = ""
            api_messages = []
            for msg in messages:
                if msg["role"] == "system":
                    system_content = msg["content"]
                else:
                    api_messages.append(msg)

            client = AsyncAnthropic(api_key=self.api_key, timeout=60.0)

            # Signal speaking state
            yield f"data: {json.dumps({'avatar_state': 'speaking', 'stream_id': stream_id})}\n\n"

            token_counter = 0
            async with client.messages.stream(
                model=self.config.model,
                max_tokens=4000,
                system=system_content,
                messages=api_messages,
            ) as stream:
                async for text in stream.text_stream:
                    if text:
                        token_counter += 1
                        event_data = {
                            "token": text,
                            "token_id": f"{stream_id}_{token_counter}",
                            "stream_id": stream_id,
                        }
                        yield f"data: {json.dumps(event_data)}\n\n"

        except AnthropicAPIError as e:
            error_msg = str(e)
            if "invalid" in error_msg.lower() and "api" in error_msg.lower():
                error_msg = "Invalid API key"
            elif "rate limit" in error_msg.lower():
                error_msg = "Rate limit exceeded. Please try again later."
            yield f"data: {json.dumps({'error': error_msg, 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"
        except Exception as e:
            error_msg = str(e)
            if "timeout" in error_msg.lower():
                error_msg = "Request timed out. Please try again."
            elif "connection" in error_msg.lower():
                error_msg = "Connection failed. Check your network."
            yield f"data: {json.dumps({'error': error_msg, 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"


def create_copilot_service_from_config(
    copilot_config: Any, api_key: Optional[str] = None
) -> CopilotService:
    """
    Create a CopilotService from a copilot configuration object.

    Args:
        copilot_config: Config object from settings (may be None)
        api_key: Optional API key. If not provided, falls back to environment variable.

    Returns:
        Configured CopilotService instance
    """
    if copilot_config is None:
        return CopilotService(api_key=api_key)

    config = CopilotConfig(
        provider=copilot_config.provider,
        model=copilot_config.model,
        enabled=copilot_config.enabled,
        context_sources={
            "agents_md": copilot_config.context_sources.agents_md,
            "learnings_md": copilot_config.context_sources.learnings_md,
            "prompt_md": copilot_config.context_sources.prompt_md,
            "requirements": copilot_config.context_sources.requirements,
            "other_specs": copilot_config.context_sources.other_specs,
        },
    )

    return CopilotService(config, api_key=api_key)

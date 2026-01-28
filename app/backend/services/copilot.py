"""
Felix Backend - CopilotService
Handles LLM integration, context loading, and conversation management for copilot chat.
"""
from typing import Optional, List, AsyncGenerator, Dict, Any
from pathlib import Path
from dataclasses import dataclass, field
import json
import httpx
import os


@dataclass
class CopilotConfig:
    """Configuration for the copilot service"""
    provider: str = "openai"
    model: str = "gpt-4o"
    enabled: bool = True
    context_sources: Dict[str, bool] = field(default_factory=lambda: {
        "agents_md": True,
        "learnings_md": True,
        "prompt_md": True,
        "requirements": True,
        "other_specs": True
    })


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
    
    def __init__(self, config: Optional[CopilotConfig] = None):
        """
        Initialize the copilot service.
        
        Args:
            config: Copilot configuration. Uses defaults if not provided.
        """
        self.config = config or CopilotConfig()
        self._api_key: Optional[str] = None
    
    @property
    def api_key(self) -> Optional[str]:
        """Get API key from environment (lazy loading)"""
        if self._api_key is None:
            self._api_key = os.getenv("FELIX_COPILOT_API_KEY", "").strip()
        return self._api_key if self._api_key else None
    
    def validate_configuration(self) -> tuple[bool, Optional[str]]:
        """
        Validate copilot configuration.
        
        Returns:
            Tuple of (is_valid, error_message)
        """
        if not self.config.enabled:
            return False, "Copilot is disabled in settings"
        
        if not self.api_key:
            return False, "FELIX_COPILOT_API_KEY not configured"
        
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
                    content = agents_path.read_text(encoding='utf-8-sig')
                    context["agents_md"] = self._trim_content(content, 4000)
                except Exception:
                    pass
        
        # Load LEARNINGS.md
        if sources.get("learnings_md", True):
            learnings_path = project_path / "LEARNINGS.md"
            if learnings_path.exists():
                try:
                    content = learnings_path.read_text(encoding='utf-8-sig')
                    context["learnings_md"] = self._trim_content(content, 2000)
                except Exception:
                    pass
        
        # Load prompt.md
        if sources.get("prompt_md", True):
            prompt_path = project_path / "prompt.md"
            if prompt_path.exists():
                try:
                    content = prompt_path.read_text(encoding='utf-8-sig')
                    context["prompt_md"] = self._trim_content(content, 3000)
                except Exception:
                    pass
        
        # Load requirements.json
        if sources.get("requirements", True):
            req_path = project_path / "felix" / "requirements.json"
            if req_path.exists():
                try:
                    content = req_path.read_text(encoding='utf-8-sig')
                    context["requirements"] = self._trim_content(content, 3000)
                except Exception:
                    pass
        
        # Load other specs (summary only)
        if sources.get("other_specs", True):
            specs_dir = project_path / "specs"
            if specs_dir.exists():
                try:
                    spec_files = list(specs_dir.glob("*.md"))
                    if spec_files:
                        spec_list = [f.stem for f in spec_files[:20]]  # Max 20 specs
                        context["other_specs"] = f"Available specs: {', '.join(spec_list)}"
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
            context_parts.append(f"## AGENTS.md (Project Guidelines)\n{context['agents_md']}")
        
        if "learnings_md" in context:
            context_parts.append(f"## LEARNINGS.md (Project Learnings)\n{context['learnings_md']}")
        
        if "prompt_md" in context:
            context_parts.append(f"## prompt.md (Spec Template)\n{context['prompt_md']}")
        
        if "requirements" in context:
            context_parts.append(f"## requirements.json (Current Requirements)\n```json\n{context['requirements']}\n```")
        
        if "other_specs" in context:
            context_parts.append(f"## Other Specs\n{context['other_specs']}")
        
        if context_parts:
            return base_prompt + "\n\n# Project Context\n\n" + "\n\n".join(context_parts)
        
        return base_prompt
    
    def build_messages(
        self,
        system_prompt: str,
        history: List[ChatMessage],
        user_message: str
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
        for msg in history[-self.MAX_CONTEXT_MESSAGES:]:
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
            trimmed.keys(),
            key=lambda k: len(trimmed.get(k, "")),
            reverse=True
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
        self,
        messages: List[Dict[str, str]]
    ) -> AsyncGenerator[str, None]:
        """
        Stream LLM response based on configured provider.
        
        Yields SSE-formatted events:
        - {"avatar_state": "thinking"} - Initial state
        - {"avatar_state": "speaking"} - When streaming starts
        - {"token": "text"} - Each token
        - {"avatar_state": "idle", "done": true} - Complete
        - {"error": "message", "avatar_state": "error"} - On error
        
        Args:
            messages: List of messages for the LLM
            
        Yields:
            SSE event strings
        """
        # Validate configuration
        is_valid, error = self.validate_configuration()
        if not is_valid:
            yield f"data: {json.dumps({'error': error, 'avatar_state': 'error'})}\n\n"
            return
        
        # Signal thinking state
        yield f"data: {json.dumps({'avatar_state': 'thinking'})}\n\n"
        
        try:
            if self.config.provider == "openai":
                async for event in self._stream_openai(messages):
                    yield event
            elif self.config.provider == "anthropic":
                async for event in self._stream_anthropic(messages):
                    yield event
            else:
                yield f"data: {json.dumps({'error': f'Unsupported provider: {self.config.provider}', 'avatar_state': 'error'})}\n\n"
                return
            
            # Signal completion
            yield f"data: {json.dumps({'avatar_state': 'idle', 'done': True})}\n\n"
            
        except httpx.TimeoutException:
            yield f"data: {json.dumps({'error': 'Request timed out', 'avatar_state': 'error'})}\n\n"
        except httpx.ConnectError:
            yield f"data: {json.dumps({'error': 'Connection failed', 'avatar_state': 'error'})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e), 'avatar_state': 'error'})}\n\n"
    
    async def _stream_openai(
        self,
        messages: List[Dict[str, str]]
    ) -> AsyncGenerator[str, None]:
        """Stream response from OpenAI API"""
        async with httpx.AsyncClient(timeout=60.0) as client:
            async with client.stream(
                "POST",
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": self.config.model,
                    "messages": messages,
                    "stream": True,
                    "max_tokens": 4000
                }
            ) as response:
                if response.status_code != 200:
                    error_body = await response.aread()
                    try:
                        error_data = json.loads(error_body)
                        error_msg = error_data.get("error", {}).get("message", f"HTTP {response.status_code}")
                    except Exception:
                        error_msg = f"HTTP {response.status_code}"
                    yield f"data: {json.dumps({'error': error_msg, 'avatar_state': 'error'})}\n\n"
                    return
                
                # Signal speaking state
                yield f"data: {json.dumps({'avatar_state': 'speaking'})}\n\n"
                
                async for line in response.aiter_lines():
                    if line.startswith("data: "):
                        data_str = line[6:]
                        if data_str.strip() == "[DONE]":
                            break
                        try:
                            data = json.loads(data_str)
                            delta = data.get("choices", [{}])[0].get("delta", {})
                            content = delta.get("content", "")
                            if content:
                                yield f"data: {json.dumps({'token': content})}\n\n"
                        except json.JSONDecodeError:
                            continue
    
    async def _stream_anthropic(
        self,
        messages: List[Dict[str, str]]
    ) -> AsyncGenerator[str, None]:
        """Stream response from Anthropic API"""
        # Extract system prompt (Anthropic uses separate system parameter)
        system_content = ""
        api_messages = []
        for msg in messages:
            if msg["role"] == "system":
                system_content = msg["content"]
            else:
                api_messages.append(msg)
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            async with client.stream(
                "POST",
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": self.api_key,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": self.config.model,
                    "max_tokens": 4000,
                    "system": system_content,
                    "messages": api_messages,
                    "stream": True
                }
            ) as response:
                if response.status_code != 200:
                    error_body = await response.aread()
                    try:
                        error_data = json.loads(error_body)
                        error_msg = error_data.get("error", {}).get("message", f"HTTP {response.status_code}")
                    except Exception:
                        error_msg = f"HTTP {response.status_code}"
                    yield f"data: {json.dumps({'error': error_msg, 'avatar_state': 'error'})}\n\n"
                    return
                
                # Signal speaking state
                yield f"data: {json.dumps({'avatar_state': 'speaking'})}\n\n"
                
                async for line in response.aiter_lines():
                    if line.startswith("data: "):
                        data_str = line[6:]
                        try:
                            data = json.loads(data_str)
                            event_type = data.get("type", "")
                            
                            if event_type == "content_block_delta":
                                delta = data.get("delta", {})
                                text = delta.get("text", "")
                                if text:
                                    yield f"data: {json.dumps({'token': text})}\n\n"
                            elif event_type == "message_stop":
                                break
                        except json.JSONDecodeError:
                            continue


def create_copilot_service_from_config(copilot_config: Any) -> CopilotService:
    """
    Create a CopilotService from a copilot configuration object.
    
    Args:
        copilot_config: Config object from settings (may be None)
        
    Returns:
        Configured CopilotService instance
    """
    if copilot_config is None:
        return CopilotService()
    
    config = CopilotConfig(
        provider=copilot_config.provider,
        model=copilot_config.model,
        enabled=copilot_config.enabled,
        context_sources={
            "agents_md": copilot_config.context_sources.agents_md,
            "learnings_md": copilot_config.context_sources.learnings_md,
            "prompt_md": copilot_config.context_sources.prompt_md,
            "requirements": copilot_config.context_sources.requirements,
            "other_specs": copilot_config.context_sources.other_specs
        }
    )
    
    return CopilotService(config)

"""
Felix Backend - Copilot API
Handles API key testing, copilot configuration validation, and chat streaming.
"""
from fastapi import APIRouter, HTTPException, Header
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, List, AsyncGenerator
import os
import httpx
import json
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from routers.settings import load_global_config
from services.copilot import (
    CopilotService,
    CopilotConfig,
    ChatMessage as ServiceChatMessage,
    create_copilot_service_from_config
)

router = APIRouter(prefix="/api/copilot", tags=["copilot"])


# --- Response Models ---

class CopilotTestResult(BaseModel):
    """Result of copilot API key test"""
    success: bool = Field(..., description="Whether the test was successful")
    error: Optional[str] = Field(None, description="Error message if test failed")
    provider: Optional[str] = Field(None, description="Provider tested")
    model: Optional[str] = Field(None, description="Model tested")


class ChatMessage(BaseModel):
    """A single chat message"""
    role: str = Field(..., description="Message role: 'user' or 'assistant'")
    content: str = Field(..., description="Message content")


class CopilotChatRequest(BaseModel):
    """Request body for copilot chat"""
    message: str = Field(..., description="User's message")
    history: List[ChatMessage] = Field(default_factory=list, description="Previous conversation history")
    project_path: Optional[str] = Field(None, description="Project path for context loading")


# --- Helper Functions ---

async def verify_openai_connection(api_key: str, model: str) -> tuple[bool, Optional[str]]:
    """Verify OpenAI API connection"""
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": "ping"}],
                    "max_tokens": 5
                }
            )
            
            if response.status_code == 200:
                return True, None
            elif response.status_code == 401:
                return False, "Invalid API key"
            elif response.status_code == 404:
                return False, f"Model '{model}' not found or not accessible"
            elif response.status_code == 429:
                # Rate limit but key is valid
                return True, None
            else:
                error_data = response.json() if response.headers.get("content-type", "").startswith("application/json") else {}
                error_msg = error_data.get("error", {}).get("message", f"HTTP {response.status_code}")
                return False, error_msg
    except httpx.TimeoutException:
        return False, "Connection timeout - check your network"
    except httpx.ConnectError:
        return False, "Connection failed - check your network"
    except Exception as e:
        return False, f"Connection error: {str(e)}"


async def verify_anthropic_connection(api_key: str, model: str) -> tuple[bool, Optional[str]]:
    """Verify Anthropic API connection"""
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": model,
                    "max_tokens": 5,
                    "messages": [{"role": "user", "content": "ping"}]
                }
            )
            
            if response.status_code == 200:
                return True, None
            elif response.status_code == 401:
                return False, "Invalid API key"
            elif response.status_code == 404:
                return False, f"Model '{model}' not found or not accessible"
            elif response.status_code == 429:
                # Rate limit but key is valid
                return True, None
            else:
                error_data = response.json() if response.headers.get("content-type", "").startswith("application/json") else {}
                error_msg = error_data.get("error", {}).get("message", f"HTTP {response.status_code}")
                return False, error_msg
    except httpx.TimeoutException:
        return False, "Connection timeout - check your network"
    except httpx.ConnectError:
        return False, "Connection failed - check your network"
    except Exception as e:
        return False, f"Connection error: {str(e)}"


# --- Endpoints ---

@router.post("/test", response_model=CopilotTestResult)
async def test_copilot_connection(
    x_copilot_api_key: Optional[str] = Header(None, alias="X-Copilot-API-Key")
):
    """
    Test the copilot API key connection.
    
    Priority for API key:
    1. X-Copilot-API-Key header (for browser-provided keys)
    2. FELIX_COPILOT_API_KEY environment variable (for local dev)
    
    Returns success/failure status without exposing the API key.
    """
    # Get API key with priority: header → env var
    api_key = None
    if x_copilot_api_key and x_copilot_api_key.strip():
        api_key = x_copilot_api_key.strip()
    else:
        env_key = os.getenv("FELIX_COPILOT_API_KEY")
        if env_key and env_key.strip():
            api_key = env_key.strip()
    
    if not api_key:
        return CopilotTestResult(
            success=False,
            error="API key not configured. Please add your API key in Settings."
        )
    
    # Load copilot configuration
    config, _ = load_global_config()
    copilot_config = config.copilot
    
    if copilot_config is None:
        # Use defaults if no copilot config exists
        provider = "openai"
        model = "gpt-4o"
    else:
        provider = copilot_config.provider
        model = copilot_config.model
    
    # Test connection based on provider
    if provider == "openai":
        success, error = await verify_openai_connection(api_key, model)
    elif provider == "anthropic":
        success, error = await verify_anthropic_connection(api_key, model)
    elif provider == "custom":
        # For custom providers, we can't test without knowing the endpoint
        # Just verify the API key is present
        return CopilotTestResult(
            success=True,
            error=None,
            provider=provider,
            model=model
        )
    else:
        return CopilotTestResult(
            success=False,
            error=f"Unsupported provider: {provider}"
        )
    
    return CopilotTestResult(
        success=success,
        error=error,
        provider=provider,
        model=model
    )


@router.get("/status")
async def get_copilot_status():
    """
    Get copilot configuration status.
    
    Returns whether copilot is enabled and configured,
    without exposing sensitive information.
    """
    config, _ = load_global_config()
    copilot_config = config.copilot
    
    api_key_present = bool(os.getenv("FELIX_COPILOT_API_KEY", "").strip())
    
    if copilot_config is None:
        return {
            "enabled": False,
            "configured": False,
            "api_key_present": api_key_present,
            "provider": None,
            "model": None
        }
    
    return {
        "enabled": copilot_config.enabled,
        "configured": True,
        "api_key_present": api_key_present,
        "provider": copilot_config.provider,
        "model": copilot_config.model
    }


# --- Streaming Chat Helper Functions ---

def build_system_prompt(project_path: Optional[str], context_sources: dict) -> str:
    """Build system prompt with project context"""
    system_prompt = """You are Felix Copilot, an AI assistant specialized in helping users write technical specifications.

You have access to the project's context files to help you understand conventions and provide accurate suggestions.

When drafting specs:
- Follow the project's existing spec format
- Use markdown formatting
- Include clear acceptance criteria
- Add validation criteria where appropriate
- Reference dependencies when relevant

Be concise, helpful, and maintain a professional yet friendly tone."""

    # Load context files if project path is provided
    if project_path:
        project = Path(project_path)
        context_parts = []
        
        # Load enabled context sources
        if context_sources.get('agents_md', True):
            agents_path = project / "AGENTS.md"
            if agents_path.exists():
                try:
                    content = agents_path.read_text(encoding='utf-8-sig')[:4000]
                    context_parts.append(f"## AGENTS.md (Project Guidelines)\n{content}")
                except Exception:
                    pass
        
        if context_sources.get('learnings_md', True):
            learnings_path = project / "LEARNINGS.md"
            if learnings_path.exists():
                try:
                    content = learnings_path.read_text(encoding='utf-8-sig')[:2000]
                    context_parts.append(f"## LEARNINGS.md (Project Learnings)\n{content}")
                except Exception:
                    pass
        
        if context_sources.get('prompt_md', True):
            prompt_path = project / "prompt.md"
            if prompt_path.exists():
                try:
                    content = prompt_path.read_text(encoding='utf-8-sig')[:3000]
                    context_parts.append(f"## prompt.md (Spec Template)\n{content}")
                except Exception:
                    pass
        
        if context_sources.get('requirements', True):
            req_path = project / "felix" / "requirements.json"
            if req_path.exists():
                try:
                    content = req_path.read_text(encoding='utf-8-sig')[:3000]
                    context_parts.append(f"## requirements.json (Current Requirements)\n```json\n{content}\n```")
                except Exception:
                    pass
        
        if context_parts:
            system_prompt += "\n\n# Project Context\n\n" + "\n\n".join(context_parts)
    
    return system_prompt


def build_messages(system_prompt: str, history: List[ChatMessage], user_message: str) -> list:
    """Build message list for LLM API"""
    messages = [{"role": "system", "content": system_prompt}]
    
    # Add history (last 10 messages for context window management)
    for msg in history[-10:]:
        messages.append({"role": msg.role, "content": msg.content})
    
    # Add current user message
    messages.append({"role": "user", "content": user_message})
    
    return messages


async def stream_openai_response(
    api_key: str,
    model: str,
    messages: list
) -> AsyncGenerator[str, None]:
    """Stream response from OpenAI API"""
    async with httpx.AsyncClient(timeout=60.0) as client:
        async with client.stream(
            "POST",
            "https://api.openai.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            },
            json={
                "model": model,
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
            
            # Signal that we're now speaking
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


async def stream_anthropic_response(
    api_key: str,
    model: str,
    messages: list
) -> AsyncGenerator[str, None]:
    """Stream response from Anthropic API"""
    # Anthropic uses a different message format - extract system prompt
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
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json"
            },
            json={
                "model": model,
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
            
            # Signal that we're now speaking
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


@router.post("/chat/stream")
async def stream_copilot_chat(
    request: CopilotChatRequest,
    x_copilot_api_key: Optional[str] = Header(None, alias="X-Copilot-API-Key")
):
    """
    Stream copilot chat response via Server-Sent Events (SSE).
    
    Priority for API key:
    1. X-Copilot-API-Key header (for browser-provided keys)
    2. FELIX_COPILOT_API_KEY environment variable (for local dev)
    
    Sends events in the format:
    - {"avatar_state": "thinking"} - Initial state
    - {"avatar_state": "speaking"} - When first token arrives  
    - {"token": "text"} - Each token as it arrives
    - {"avatar_state": "idle", "done": true} - Stream complete
    - {"error": "message", "avatar_state": "error"} - On error
    
    Uses CopilotService for LLM integration and context management.
    """
    # Determine API key with priority: header → env var
    api_key = None
    if x_copilot_api_key and x_copilot_api_key.strip():
        api_key = x_copilot_api_key.strip()
    # If no header, the service will fall back to env var internally
    
    async def event_generator() -> AsyncGenerator[str, None]:
        try:
            # Load copilot configuration and create service with API key
            config, _ = load_global_config()
            service = create_copilot_service_from_config(config.copilot, api_key=api_key)
            
            # Load project context if project path provided
            context = {}
            if request.project_path:
                project_path = Path(request.project_path)
                context = service.load_context(project_path)
                # Apply token budget trimming
                context = service.trim_context_for_token_budget(context)
            
            # Build system prompt with context
            system_prompt = service.build_system_prompt(context)
            
            # Convert Pydantic ChatMessage to service ChatMessage
            history = [
                ServiceChatMessage(role=msg.role, content=msg.content)
                for msg in request.history
            ]
            
            # Build message list
            messages = service.build_messages(system_prompt, history, request.message)
            
            # Stream response using service
            async for event in service.stream_response(messages):
                yield event
            
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e), 'avatar_state': 'error'})}\n\n"
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )

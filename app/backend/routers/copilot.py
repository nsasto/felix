"""
Felix Backend - Copilot API
Handles API key testing and copilot configuration validation.
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import Optional
import os
import httpx
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from routers.settings import load_global_config

router = APIRouter(prefix="/api/copilot", tags=["copilot"])


# --- Response Models ---

class CopilotTestResult(BaseModel):
    """Result of copilot API key test"""
    success: bool = Field(..., description="Whether the test was successful")
    error: Optional[str] = Field(None, description="Error message if test failed")
    provider: Optional[str] = Field(None, description="Provider tested")
    model: Optional[str] = Field(None, description="Model tested")


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
async def test_copilot_connection():
    """
    Test the copilot API key connection.
    
    Reads FELIX_COPILOT_API_KEY from environment and tests
    connectivity to the configured LLM provider.
    
    Returns success/failure status without exposing the API key.
    """
    # Get API key from environment
    api_key = os.getenv("FELIX_COPILOT_API_KEY")
    
    if not api_key:
        return CopilotTestResult(
            success=False,
            error="FELIX_COPILOT_API_KEY not found in environment"
        )
    
    if not api_key.strip():
        return CopilotTestResult(
            success=False,
            error="FELIX_COPILOT_API_KEY is empty"
        )
    
    # Load copilot configuration
    config = load_global_config()
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
    config = load_global_config()
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

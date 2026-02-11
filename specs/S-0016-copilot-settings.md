# S-0016: Felix Copilot Settings

## Narrative

As a Felix user who wants AI-powered assistance for spec writing and project management, I need a settings page to configure my own LLM provider and API credentials, so that I can enable the Felix Copilot using my existing OpenAI, Anthropic, or other LLM subscriptions without vendor lock-in.

Currently, there is no AI assistance in Felix. Users write specs manually and must reference project context (AGENTS.md, LEARNINGS.md, requirements) themselves. This requirement introduces the configuration layer for Felix Copilot - a pluggable AI assistant that works with any LLM provider the user chooses.

The key principle is **BYOK (Bring Your Own Key)**: Felix never stores, transmits, or manages API billing. Users provide their own credentials stored in `.env` file, and Felix uses LangChain to abstract provider differences.

## Acceptance Criteria

### Settings Category

- [ ] New "Felix Copilot" category appears in settings left sidebar
- [ ] Category positioned between "Appearance" and "Advanced"
- [ ] Category icon uses sparkle emoji: ✨
- [ ] Category description: "AI-powered spec writing assistant"
- [ ] Selecting category shows copilot configuration panel

### Enable/Disable Toggle

- [ ] "Enable Copilot" toggle switch at top of settings panel
- [ ] Toggle defaults to OFF (disabled) for new installations
- [ ] Toggle saves immediately to ..felix/config.json on change
- [ ] When disabled, all copilot features are hidden from UI (no chat button in specs editor)
- [ ] When enabled, copilot chat button appears in specs editor
- [ ] Toggle shows visual feedback (loading state) during save

### Provider Selection

- [ ] "Provider" dropdown field with options: OpenAI, Anthropic, Custom
- [ ] Default selection: OpenAI
- [ ] Dropdown disabled when copilot is disabled
- [ ] Changing provider auto-updates model list
- [ ] Provider selection saves to ..felix/config.json
- [ ] Help text: "Choose your LLM provider. Felix uses your API key from .env file."

### API Key Configuration

- [ ] "API Key" section shows instruction text: "Add FELIX_COPILOT_API_KEY to your .env file"
- [ ] Code snippet shows: `FELIX_COPILOT_API_KEY=sk-your-key-here`
- [ ] "Test Connection" button validates API key from environment
- [ ] Test success shows green checkmark: "✓ Connected successfully"
- [ ] Test failure shows red X and error: "✗ API key not found or invalid"
- [ ] Help text: "Your API key is stored in .env (not version controlled)"
- [ ] Link to provider API key page (OpenAI dashboard, Anthropic console)

### Model Selection

- [ ] "Model" dropdown field with provider-specific models
- [ ] OpenAI options: gpt-4o, gpt-4-turbo, gpt-3.5-turbo
- [ ] Anthropic options: claude-3-5-sonnet-20241022, claude-3-opus-20240229, claude-3-haiku-20240307
- [ ] Custom provider: Free text input for model name
- [ ] Default: gpt-4o (OpenAI), claude-3-5-sonnet-20241022 (Anthropic)
- [ ] Dropdown disabled when copilot is disabled
- [ ] Model selection saves to ..felix/config.json
- [ ] Help text: "Model used for spec generation and conversations"

### Context Configuration

- [ ] "Context Sources" section with toggles for each source
- [ ] Toggle: AGENTS.md - "Operational instructions and validation"
- [ ] Toggle: LEARNINGS.md - "Technical knowledge and common pitfalls"
- [ ] Toggle: prompt.md - "Spec writing conventions"
- [ ] Toggle: requirements.json - "Project dependencies and status"
- [ ] Toggle: Other specs - "Pattern consistency from existing specs"
- [ ] All sources enabled by default
- [ ] Disabling a source excludes it from copilot system prompt
- [ ] Context settings save to ..felix/config.json

### Feature Toggles

- [ ] "Streaming Responses" toggle (default: ON) - Enables token-by-token streaming
- [ ] "Auto-suggest Spec Titles" toggle (default: ON) - Suggests titles from user input
- [ ] "Context-aware Completions" toggle (default: ON) - Uses project context in responses
- [ ] Each toggle has descriptive help text
- [ ] Feature settings save to ..felix/config.json
- [ ] Disabled features don't appear in copilot behavior

### Visual Feedback

- [ ] Loading spinner during API key validation test
- [ ] Success/error toast notifications for settings saves
- [ ] Disabled state styling for inputs when copilot is off
- [ ] Form validation: Shows warning if copilot enabled but no API key in .env
- [ ] Unsaved changes indicator (if needed - currently auto-saves)
- [ ] "Reset to Defaults" button clears all copilot settings

## Technical Notes

### Architecture

**LangChain Integration:**

Felix uses LangChain to abstract LLM provider differences, supporting OpenAI, Anthropic, and future providers without custom interfaces.

```python
# Backend: app/backend/services/copilot.py
import os
from langchain.chat_models import ChatOpenAI, ChatAnthropic
from langchain.chains import ConversationChain
from langchain.memory import ConversationBufferMemory
from langchain.schema import HumanMessage, SystemMessage, AIMessage

class CopilotService:
    def __init__(self, config: dict):
        self.config = config
        self.api_key = os.getenv('FELIX_COPILOT_API_KEY')
        self.model = self._init_model()
        self.memory = ConversationBufferMemory(return_messages=True)
        self.chain = ConversationChain(
            llm=self.model,
            memory=self.memory,
            verbose=True
        )

    def _init_model(self):
        if not self.api_key:
            raise ValueError("FELIX_COPILOT_API_KEY not found in environment")

        provider = self.config.get('provider', 'openai')
        model_name = self.config.get('model', 'gpt-4o')

        if provider == "openai":
            return ChatOpenAI(
                api_key=self.api_key,
                model_name=model_name,
                streaming=self.config.get('features', {}).get('streaming', True)
            )
        elif provider == "anthropic":
            return ChatAnthropic(
                api_key=self.api_key,
                model_name=model_name,
                streaming=self.config.get('features', {}).get('streaming', True)
            )
        else:
            raise ValueError(f"Unsupported provider: {provider}")

    def load_context(self, project_path: str) -> dict:
        """Load enabled context sources from project files"""
        context = {}
        sources = self.config.get('context_sources', {})

        if sources.get('agents_md', True):
            agents_path = project_path / 'AGENTS.md'
            if agents_path.exists():
                context['agents_md'] = agents_path.read_text(encoding='utf-8')

        if sources.get('learnings_md', True):
            learnings_path = project_path / 'LEARNINGS.md'
            if learnings_path.exists():
                context['learnings_md'] = learnings_path.read_text(encoding='utf-8')

        if sources.get('prompt_md', True):
            prompt_path = project_path / 'prompt.md'
            if prompt_path.exists():
                context['prompt_md'] = prompt_path.read_text(encoding='utf-8')

        if sources.get('requirements', True):
            req_path = project_path / 'felix' / 'requirements.json'
            if req_path.exists():
                context['requirements'] = req_path.read_text(encoding='utf-8')

        return context

    def build_system_prompt(self, context: dict) -> str:
        """Build system prompt from enabled context sources"""
        parts = [
            "You are Felix Copilot, an AI assistant for writing technical specifications.",
            "Your role is to help users draft clear, comprehensive specs following project conventions.",
            ""
        ]

        if 'agents_md' in context:
            parts.append("=== OPERATIONAL INSTRUCTIONS ===")
            parts.append(context['agents_md'])
            parts.append("")

        if 'learnings_md' in context:
            parts.append("=== TECHNICAL KNOWLEDGE & PITFALLS ===")
            parts.append(context['learnings_md'])
            parts.append("")

        if 'prompt_md' in context:
            parts.append("=== SPEC WRITING CONVENTIONS ===")
            parts.append(context['prompt_md'])
            parts.append("")

        if 'requirements' in context:
            parts.append("=== EXISTING REQUIREMENTS ===")
            parts.append(context['requirements'])
            parts.append("")

        parts.append("Always follow the spec format from prompt.md. Be concise but thorough.")

        return "\n".join(parts)
```

**Frontend Configuration Interface:**

```typescript
// app/frontend/services/felixApi.ts additions

export interface CopilotConfig {
  enabled: boolean;
  provider: 'openai' | 'anthropic' | 'custom';
  model: string;
  context_sources: {
    agents_md: boolean;
    learnings_md: boolean;
    prompt_md: boolean;
    requirements: boolean;
    other_specs: boolean;
  };
  features: {
    streaming: boolean;
    auto_suggest: boolean;
    context_aware: boolean;
  };
}

export interface FelixConfig {
  version: string;
  executor: any;
  agent: any;
  paths: any;
  backpressure: any;
  ui: { theme: string };
  copilot?: CopilotConfig;
}

// New API endpoints
async testCopilotConnection(projectId: string): Promise<{ success: boolean; error?: string }> {
  const response = await fetch(`${this.baseUrl}/projects/${projectId}/copilot/test`, {
    method: 'POST'
  });
  return response.json();
}
```

**Backend API Endpoints:**

```python
# app/backend/routers/copilot.py
from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
import os

router = APIRouter(prefix="/api/projects/{project_id}/copilot", tags=["copilot"])

@router.post("/test")
async def test_copilot_connection(project_id: str):
    """Test API key and connection to LLM provider"""
    try:
        api_key = os.getenv('FELIX_COPILOT_API_KEY')

        if not api_key:
            return JSONResponse(
                content={"success": False, "error": "FELIX_COPILOT_API_KEY not found in environment"},
                status_code=200
            )

        # Load copilot config
        from app.backend.services.config import load_config
        config = load_config(project_id)
        copilot_config = config.get('copilot', {})

        # Test connection with LangChain
        from app.backend.services.copilot import CopilotService
        service = CopilotService(copilot_config)

        # Simple test message
        from langchain.schema import HumanMessage
        response = service.model([HumanMessage(content="ping")])

        return JSONResponse(
            content={"success": True},
            status_code=200
        )

    except Exception as e:
        return JSONResponse(
            content={"success": False, "error": str(e)},
            status_code=200
        )
```

**Config File Schema:**

```json
{
  "version": "0.1.0",
  "executor": {...},
  "agent": {...},
  "paths": {...},
  "backpressure": {...},
  "ui": { "theme": "dark" },
  "copilot": {
    "enabled": false,
    "provider": "openai",
    "model": "gpt-4o",
    "context_sources": {
      "agents_md": true,
      "learnings_md": true,
      "prompt_md": true,
      "requirements": true,
      "other_specs": true
    },
    "features": {
      "streaming": true,
      "auto_suggest": true,
      "context_aware": true
    }
  }
}
```

**.env file (root directory):**

```bash
# Felix Copilot API Key
# Get your key from: https://platform.openai.com/api-keys or https://console.anthropic.com/
FELIX_COPILOT_API_KEY=
```

### Security Considerations

**API Key Storage:**

- API key stored in `.env` file (already gitignored by default in most projects)
- Backend reads from environment using `os.getenv()`
- Never logged or persisted by backend
- User responsible for protecting .env file

**Environment Variable Access:**

- Backend has read-only access to environment variables
- Frontend never receives API key (only success/failure status)
- No API endpoint exposes raw API key

## Dependencies

- S-0007 (Settings Screen) - requires existing settings infrastructure
- S-0002 (Backend API) - requires config endpoints
- **New:** LangChain Python library (`pip install langchain`)
- **New:** OpenAI Python SDK (`pip install openai`) - optional, via LangChain
- **New:** Anthropic Python SDK (`pip install anthropic`) - optional, via LangChain
- **New:** python-dotenv (`pip install python-dotenv`) - for .env file handling

## Non-Goals

- Felix-hosted API keys or billing (user BYOK always)
- Custom LLM provider integrations beyond LangChain support
- API key encryption at rest (plaintext in .env, future enhancement)
- Multi-user API key management (single-user app)
- Usage tracking, cost estimation, or billing analytics
- Fine-tuning or custom model training
- Prompt engineering UI (use code-based defaults)
- API key rotation automation (manual update in .env)

## Validation Criteria

- [ ] Settings shows copilot category: Open settings, verify "Felix Copilot" appears in sidebar
- [ ] Toggle enables copilot: Turn on toggle, save, verify chat button appears in specs editor
- [ ] Provider dropdown works: Change from OpenAI to Anthropic, verify model list updates
- [ ] API key test fails without key: Click Test Connection without .env key, verify error message
- [ ] API key test succeeds: Add valid key to .env, click Test, verify success message
- [ ] Model selection saves: Change model to gpt-3.5-turbo, save, reload settings, verify persisted
- [ ] Context sources save: Disable LEARNINGS.md, save, verify config.json updated
- [ ] Feature toggles save: Disable streaming, save, verify config.json updated
- [ ] Disabled state works: Disable copilot, verify all inputs are disabled and grayed out
- [ ] Config persistence: Configure copilot, restart app, verify all settings retained
- [ ] .env security: Verify .env file in .gitignore, attempt git add, confirm not staged




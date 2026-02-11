# S-0022: Move Copilot API Key to Browser Storage

## Overview

Currently the copilot feature uses an API key stored in a `.env` file in the backend. This approach doesn't work for cloud-hosted deployments where multiple users share the same backend. We need to move the API key storage to the browser (localStorage) so each user can provide their own OpenAI API key.

## Narrative

As a Felix user, I need to provide my own OpenAI API key through the Settings UI so that I can use the copilot feature in both local and cloud-hosted deployments.

## Acceptance Criteria

### Core Functionality

- [ ] Settings UI has an input field for OpenAI API key in the Copilot section
- [ ] API key is stored in browser localStorage (key: felix_copilot_api_key)
- [ ] API key is sent to backend via `X-Copilot-API-Key` HTTP header on copilot requests
- [ ] Backend validates the API key header and uses it for OpenAI API calls
- [ ] Backend returns 401 Unauthorized if no API key is provided
- [ ] If no API key in header, backend falls back to `FELIX_COPILOT_API_KEY` env var (for local dev)

### Edge Cases

- [ ] Input field shows masked characters (password-style) for security
- [ ] Save confirmation is shown when API key is saved
- [ ] Clear error message is shown when API key is missing or invalid
- [ ] Existing `.env` file continues to work as fallback for local development
- [ ] API keys are never logged or exposed in console/network logs

## Technical Notes

### Architecture

**Frontend (React + localStorage):**

- Add API key input to Settings → Copilot section
- Store in localStorage: localStorage.setItem('felix_copilot_api_key', key)
- Inject header when making copilot requests
- Show "API key required" message if missing

**Backend (FastAPI):**

- Modify `/api/copilot/chat/stream` to accept `X-Copilot-API-Key` header
- Priority: header → env var → error
- Return 401 if neither is available

### Files to Modify

**app/frontend/components/SettingsScreen.tsx:**

- Add input field in Copilot settings section
- Add save/load logic for API key
- Add masked input component

**app/frontend/services/felixApi.ts:**

- Add `setCopilotApiKey(key: string): void`
- Add `getCopilotApiKey(): string | null`
- Modify `streamCopilotChat()` to include `X-Copilot-API-Key` header

**app/backend/routes/copilot.py:**

- Read `X-Copilot-API-Key` from request headers
- Fallback to `os.getenv("FELIX_COPILOT_API_KEY")`
- Return 401 with clear error if neither exists

**app/backend/main.py:**

- Remove `load_dotenv()` call (optional - can keep for local dev)

**app/backend/requirements.txt:**

- Remove `python-dotenv` dependency (optional - can keep for local dev)

### API Changes

New HTTP header:

- `X-Copilot-API-Key: sk-proj-...` - User's OpenAI API key

New error response:

- `401 Unauthorized` - Missing or invalid API key

### Data Model

**localStorage:**

```typescript
{
  "felix_copilot_api_key": "sk-proj-..." // OpenAI API key
}
```

**Request Headers:**

```
X-Copilot-API-Key: sk-proj-...
```

### Security Considerations

1. `.env` file must be in `.gitignore` to prevent accidental commits
2. API keys stored in localStorage are origin-isolated (secure as cookies)
3. Use HTTPS in production to prevent header interception
4. Never log API keys in console or server logs
5. Consider adding key validation endpoint that doesn't expose the key

## Dependencies

- Browser localStorage API (native, no dependencies)
- Backend must support custom HTTP headers
- Frontend must support header injection in SSE/EventSource

**Note:** EventSource (used for SSE) doesn't support custom headers in standard implementation. May need to:

- Use query parameter as fallback: `?api_key=xxx` (less secure)
- Use custom fetch-based SSE client that supports headers
- Use POST request upgrade to SSE stream

## Validation Criteria

- [ ] User can enter API key in Settings UI
- [ ] API key persists in localStorage across sessions
- [ ] Copilot chat works with user-provided API key
- [ ] Backend returns 401 when no key provided
- [ ] Backend falls back to env var when header is missing (local dev)
- [ ] .env file is in .gitignore
- [ ] Tests verify header validation logic


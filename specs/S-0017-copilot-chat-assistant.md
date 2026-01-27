# S-0017: Felix Copilot Chat Assistant

## Narrative

As a Felix user writing technical specifications, I need an AI-powered chat assistant with animated avatar and persistent conversation history, so that I can quickly draft specs, ask questions about the project, and get context-aware suggestions without leaving the specs editor.

Currently, users must write specs manually by referencing multiple files (AGENTS.md, LEARNINGS.md, prompt.md, requirements.json, other specs). This is time-consuming and error-prone. The Felix Copilot Chat provides an interactive assistant that knows the project context and can draft specs following project conventions.

The copilot appears as a **bottom-right floating chat button** in the specs editor only. When clicked, it expands into a chat panel with an animated agent avatar that changes expression based on activity (idle, listening, thinking, speaking, error). Conversations use **streaming responses** (token-by-token) via LangChain with **multi-turn context awareness**. Chat history is **persisted to localStorage** per project.

## Acceptance Criteria

### Floating Chat Button

- [ ] Chat button appears in bottom-right corner of specs editor only
- [ ] Button positioned `fixed bottom-4 right-4 z-50`
- [ ] Button shows sparkle icon (✨) with subtle pulse animation
- [ ] Button only visible when copilot is enabled in settings (S-0016)
- [ ] Button shows badge with unread message count (if copilot sent message while panel closed)
- [ ] Button size: 56×56px, circular, gradient background (felix-500 to felix-600)
- [ ] Hover effect: Slight scale-up (1.05×) and shadow increase
- [ ] Click button toggles chat panel open/closed

### Chat Panel Layout

- [ ] Panel expands upward from chat button when clicked
- [ ] Panel dimensions: 380px wide × 520px tall
- [ ] Panel positioned above chat button with 8px gap
- [ ] Panel uses rounded corners (16px), gradient border, elevated shadow
- [ ] Panel has three sections: Header (80px), Messages (flex-1), Input (80px)
- [ ] Panel slides up with smooth animation (300ms ease-out) on open
- [ ] Panel slides down and fades out on close
- [ ] Click outside panel or ESC key closes panel

### Chat Header

- [ ] Header shows "Felix Copilot" title (left side, font-semibold)
- [ ] Animated agent avatar (48×48px) in header (left side, before title)
- [ ] Minimize button (right side) collapses panel back to button
- [ ] Clear history button (right side, before minimize) resets conversation
- [ ] Context badge shows active context sources: "📚 4 sources" (small, below title)
- [ ] Header background: subtle gradient with theme colors

### Animated Agent Avatar

- [ ] Avatar renders as SVG animation (48×48px)
- [ ] Five animation states:
  - **Idle**: Gentle breathing, occasional blink (default state)
  - **Listening**: Attentive expression, subtle nod when user typing
  - **Thinking**: Processing indicator, gears turning animation
  - **Speaking**: Animated as tokens stream in (mouth moving)
  - **Error**: Worried expression, brief shake animation
- [ ] Avatar transitions smoothly between states (300ms CSS transitions)
- [ ] Avatar state changes based on copilot activity:
  - User focuses input → Listening
  - User sends message → Thinking
  - First token arrives → Speaking
  - Stream completes → Idle
  - Error occurs → Error (2s), then Idle
- [ ] Avatar is non-intrusive, small, positioned left of title

### Message History

- [ ] Messages displayed in scrollable area (flex-1, overflow-y-auto)
- [ ] User messages aligned right, assistant messages aligned left
- [ ] User messages: felix-500 background, white text, rounded bubble
- [ ] Assistant messages: theme-bg-elevated background, theme-text-primary, rounded bubble
- [ ] Each message shows timestamp (text-[10px], theme-text-muted)
- [ ] Code blocks in messages use syntax highlighting (monaco or highlight.js)
- [ ] Markdown rendering for assistant messages (bold, italic, lists, links)
- [ ] Auto-scroll to bottom when new message arrives
- [ ] Loading indicator (three dots animation) while assistant thinking
- [ ] Empty state: "Hi! I'm Felix Copilot. Ask me to draft a spec or answer questions about your project."

### Message Input

- [ ] Text input box at bottom of panel (80px height)
- [ ] Input placeholder: "Ask me anything or type /draft to create a spec..."
- [ ] Send button (right side of input, disabled if empty)
- [ ] Send on Enter key, Shift+Enter for new line
- [ ] Input auto-focuses when panel opens
- [ ] Character limit: 2000 chars (show count when >1800)
- [ ] Cancel button appears during streaming (stops generation mid-stream)

### Quick Actions

- [ ] "/draft" command: Quick button above input to start spec generation
- [ ] "/draft" button: "✨ Draft Spec" with prominent styling
- [ ] Clicking "/draft" prompts: "What spec would you like me to draft?"
- [ ] "/help" command: Shows list of available commands and features
- [ ] Future: "/analyze" command for spec review/improvement suggestions

### Streaming Responses

- [ ] Assistant responses stream token-by-token as they arrive (typewriter effect)
- [ ] Streaming uses Server-Sent Events (SSE) from backend
- [ ] Frontend EventSource listens to `/api/projects/:id/copilot/stream` endpoint
- [ ] Each SSE message contains: `{"token": "word", "avatar_state": "speaking"}`
- [ ] Tokens append to current message bubble in real-time
- [ ] Avatar animates in "Speaking" state during stream
- [ ] Auto-scroll follows stream (keeps bottom visible)
- [ ] Cancel button stops stream and closes SSE connection
- [ ] Partial message shows "⚠️ Stream interrupted" footer if connection breaks
- [ ] Retry button allows resuming from last message

### Conversation Persistence

- [ ] Chat history saved to `localStorage` per project
- [ ] Storage key: `felix_copilot_chat_${projectId}`
- [ ] History includes: messages (user + assistant), timestamps, avatar states
- [ ] Maximum 50 messages stored (FIFO when exceeded)
- [ ] History survives page refresh, browser restart, navigation
- [ ] "Clear History" button in header wipes localStorage and resets conversation
- [ ] Confirmation dialog before clearing: "Clear all conversation history?"
- [ ] Switching projects loads correct history for each project
- [ ] Export history feature (future): Download JSON of conversation

### Multi-Turn Context

- [ ] LangChain `ConversationBufferMemory` maintains conversation context
- [ ] Previous messages included in system prompt for each request
- [ ] Context window: Last 10 messages + system prompt (project context)
- [ ] Token budget management: Summarize messages older than 10 turns if total >8k tokens
- [ ] Follow-up questions work: "What about dependencies?" after discussing spec
- [ ] User can reference previous messages: "Change the title you suggested earlier"
- [ ] Context reset when clearing history (fresh conversation)

### Spec Generation Workflow

- [ ] User types: "Draft a spec for user authentication" or clicks "/draft" button
- [ ] Copilot loads project context (AGENTS.md, LEARNINGS.md, prompt.md, requirements, specs)
- [ ] Copilot asks clarifying questions if needed: "Should this use OAuth or JWT?"
- [ ] Copilot generates spec following prompt.md conventions
- [ ] Generated spec shows in message as markdown (preview)
- [ ] "Insert Spec" button appears below generated spec message
- [ ] Clicking "Insert Spec" populates editor content area with generated markdown
- [ ] User can edit spec in editor after insertion
- [ ] Copilot tracks if spec was edited (for future fine-tuning)

### Error Handling

- [ ] Connection errors show: "❌ Connection lost. Retrying..."
- [ ] API errors show: "❌ Error: [error message]"
- [ ] Invalid API key shows: "❌ API key invalid. Check Settings > Felix Copilot"
- [ ] Rate limit errors: "❌ Rate limit exceeded. Please wait [time] before trying again"
- [ ] Avatar shows "Error" state for 2 seconds, then returns to Idle
- [ ] Retry button allows resending last message after error
- [ ] Error messages don't break conversation flow (appended to history)

## Technical Notes

### Architecture

**Backend Streaming with LangChain:**

```python
# app/backend/routers/copilot.py
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from langchain.callbacks.streaming_stdout import StreamingStdOutCallbackHandler
from langchain.schema import HumanMessage
import json

router = APIRouter(prefix="/api/projects/{project_id}/copilot", tags=["copilot"])

class SSECallbackHandler(StreamingStdOutCallbackHandler):
    """Custom callback for SSE streaming"""
    def __init__(self):
        self.tokens = []

    def on_llm_new_token(self, token: str, **kwargs):
        """Called when new token arrives from LLM"""
        self.tokens.append(token)

@router.post("/stream")
async def stream_copilot_response(
    project_id: str,
    request: dict
):
    """Stream copilot response via SSE"""
    async def event_generator():
        try:
            # Load config and initialize service
            from app.backend.services.copilot import CopilotService
            from app.backend.services.config import load_config

            config = load_config(project_id)
            copilot_config = config.get('copilot', {})

            service = CopilotService(copilot_config)

            # Load project context
            project_path = Path(f"projects/{project_id}")
            context = service.load_context(project_path)

            # Build system prompt with context
            system_prompt = service.build_system_prompt(context)

            # Add user message to conversation
            user_message = request.get('message', '')

            # Set avatar state to thinking
            yield f"data: {json.dumps({'avatar_state': 'thinking'})}\n\n"

            # Stream response with callback
            callback = SSECallbackHandler()

            # Use ConversationChain for multi-turn context
            response = service.chain.predict(
                input=user_message,
                callbacks=[callback]
            )

            # Stream tokens as they arrive
            yield f"data: {json.dumps({'avatar_state': 'speaking'})}\n\n"

            for token in callback.tokens:
                yield f"data: {json.dumps({'token': token})}\n\n"

            # Mark stream complete
            yield f"data: {json.dumps({'avatar_state': 'idle', 'done': True})}\n\n"

        except Exception as e:
            yield f"data: {json.dumps({'error': str(e), 'avatar_state': 'error'})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream"
    )
```

**Frontend Chat Component:**

```typescript
// app/frontend/components/CopilotChat.tsx
import React, { useState, useEffect, useRef } from 'react';
import { felixApi } from '../services/felixApi';

interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
}

interface CopilotChatProps {
  projectId: string;
  onInsertSpec: (content: string) => void;
}

const CopilotChat: React.FC<CopilotChatProps> = ({ projectId, onInsertSpec }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [avatarState, setAvatarState] = useState<'idle' | 'listening' | 'thinking' | 'speaking' | 'error'>('idle');
  const [streaming, setStreaming] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Load chat history from localStorage
  useEffect(() => {
    const storageKey = `felix_copilot_chat_${projectId}`;
    const saved = localStorage.getItem(storageKey);
    if (saved) {
      try {
        const history = JSON.parse(saved);
        setMessages(history.map((m: any) => ({
          ...m,
          timestamp: new Date(m.timestamp)
        })));
      } catch (err) {
        console.error('Failed to load chat history:', err);
      }
    }
  }, [projectId]);

  // Save chat history to localStorage
  useEffect(() => {
    if (messages.length > 0) {
      const storageKey = `felix_copilot_chat_${projectId}`;
      const toSave = messages.slice(-50); // Keep last 50 messages
      localStorage.setItem(storageKey, JSON.stringify(toSave));
    }
  }, [messages, projectId]);

  // Auto-scroll to bottom
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSendMessage = async () => {
    if (!input.trim() || streaming) return;

    // Add user message
    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: input,
      timestamp: new Date()
    };
    setMessages(prev => [...prev, userMessage]);
    setInput('');
    setAvatarState('thinking');
    setStreaming(true);

    // Create assistant message placeholder
    const assistantMessage: Message = {
      id: (Date.now() + 1).toString(),
      role: 'assistant',
      content: '',
      timestamp: new Date()
    };
    setMessages(prev => [...prev, assistantMessage]);

    // Start SSE stream
    try {
      const response = await fetch(`${felixApi.baseUrl}/projects/${projectId}/copilot/stream`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: input })
      });

      const reader = response.body?.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader!.read();
        if (done) break;

        const chunk = decoder.decode(value);
        const lines = chunk.split('\n');

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = JSON.parse(line.slice(6));

            if (data.token) {
              setMessages(prev => {
                const updated = [...prev];
                const lastMsg = updated[updated.length - 1];
                if (lastMsg.role === 'assistant') {
                  lastMsg.content += data.token;
                }
                return updated;
              });
            }

            if (data.avatar_state) {
              setAvatarState(data.avatar_state);
            }

            if (data.done) {
              setStreaming(false);
            }

            if (data.error) {
              setAvatarState('error');
              setTimeout(() => setAvatarState('idle'), 2000);
              setStreaming(false);
            }
          }
        }
      }
    } catch (err) {
      console.error('Streaming error:', err);
      setAvatarState('error');
      setTimeout(() => setAvatarState('idle'), 2000);
      setStreaming(false);
    }
  };

  return (
    <>
      {/* Floating Chat Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="fixed bottom-4 right-4 z-50 w-14 h-14 rounded-full bg-gradient-to-br from-felix-500 to-felix-600 text-white shadow-lg hover:scale-105 transition-transform flex items-center justify-center"
      >
        <span className="text-2xl animate-pulse">✨</span>
      </button>

      {/* Chat Panel */}
      {isOpen && (
        <div className="fixed bottom-20 right-4 z-50 w-[380px] h-[520px] rounded-2xl theme-bg-surface border-2 border-felix-500/30 shadow-2xl flex flex-col">
          {/* Header with Avatar */}
          <div className="h-20 px-4 py-3 border-b theme-border flex items-center gap-3">
            <AvatarAnimation state={avatarState} />
            <div className="flex-1">
              <h3 className="text-sm font-semibold theme-text-primary">Felix Copilot</h3>
              <span className="text-[10px] theme-text-muted">📚 4 sources</span>
            </div>
            <button onClick={() => setMessages([])} className="text-xs">🗑️</button>
            <button onClick={() => setIsOpen(false)} className="text-xs">➖</button>
          </div>

          {/* Messages */}
          <div className="flex-1 overflow-y-auto p-4 space-y-3">
            {messages.map(msg => (
              <div key={msg.id} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                <div className={`max-w-[85%] rounded-2xl px-4 py-2 ${
                  msg.role === 'user' ? 'bg-felix-500 text-white' : 'theme-bg-elevated theme-text-primary'
                }`}>
                  <div className="text-sm">{msg.content}</div>
                  <div className="text-[10px] mt-1 opacity-70">
                    {msg.timestamp.toLocaleTimeString()}
                  </div>
                </div>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>

          {/* Input */}
          <div className="h-20 p-3 border-t theme-border">
            <div className="flex gap-2">
              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onFocus={() => setAvatarState('listening')}
                onBlur={() => avatarState === 'listening' && setAvatarState('idle')}
                onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && handleSendMessage()}
                placeholder="Ask me anything..."
                className="flex-1 px-3 py-2 text-sm rounded-lg theme-bg-elevated theme-border"
              />
              <button
                onClick={handleSendMessage}
                disabled={!input.trim() || streaming}
                className="px-4 py-2 rounded-lg bg-felix-500 text-white disabled:opacity-50"
              >
                ➤
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
};
```

**Avatar Animation States (CSS):**

```css
/* app/frontend/styles/copilot-avatar.css */

@keyframes breathe {
  0%,
  100% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.02);
  }
}

.avatar-idle {
  animation: breathe 3s ease-in-out infinite;
}

@keyframes nod {
  0%,
  100% {
    transform: translateY(0);
  }
  50% {
    transform: translateY(-2px);
  }
}

.avatar-listening {
  animation: nod 1.5s ease-in-out infinite;
}

@keyframes think {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

.avatar-thinking {
  animation: think 2s linear infinite;
}

@keyframes speak {
  0%,
  100% {
    transform: translateY(0);
  }
  50% {
    transform: translateY(-1px);
  }
}

.avatar-speaking {
  animation: speak 0.5s ease-in-out infinite;
}

@keyframes shake {
  0%,
  100% {
    transform: translateX(0);
  }
  25% {
    transform: translateX(-4px);
  }
  75% {
    transform: translateX(4px);
  }
}

.avatar-error {
  animation: shake 0.4s ease-in-out 3;
}
```

**Token Budget Management:**

```python
# app/backend/services/copilot.py
from langchain.memory import ConversationSummaryMemory

class CopilotService:
    def __init__(self, config: dict):
        self.config = config
        self.model = self._init_model()

        # Use summary memory for token budget management
        if config.get('features', {}).get('context_aware', True):
            self.memory = ConversationSummaryMemory(
                llm=self.model,
                max_token_limit=8000  # Summarize if conversation exceeds 8k tokens
            )
        else:
            self.memory = ConversationBufferMemory(return_messages=True)

    def trim_context(self, context: dict) -> dict:
        """Trim context sources if total tokens exceed budget"""
        total_size = sum(len(v) for v in context.values())
        estimated_tokens = total_size // 4

        if estimated_tokens > 10000:
            # Trim LEARNINGS.md (largest file)
            if 'learnings_md' in context:
                context['learnings_md'] = context['learnings_md'][:2000] + "\n[...truncated...]"

        return context
```

## Dependencies

- S-0016 (Copilot Settings) - required for configuration and API key
- S-0003 (Frontend Observer UI) - copilot appears in specs editor
- S-0002 (Backend API) - requires SSE streaming endpoint
- **New:** LangChain with streaming callbacks
- **New:** Server-Sent Events (SSE) support in FastAPI
- **New:** localStorage for conversation persistence
- **New:** Markdown renderer (marked.js)
- **New:** Syntax highlighter (highlight.js)

## Non-Goals

- Copilot in other screens (projects, kanban, settings) - specs editor only for now
- Voice input/output for chat (text-only)
- Multi-user collaboration in chat (single-user conversations)
- Chat export to PDF or sharing (future enhancement)
- Copilot proactive suggestions (user must initiate conversation)
- Real-time typing indicators
- Chat search or message filtering
- Custom avatar designs (single default agent)
- Offline mode (requires API connection)

## Validation Criteria

- [ ] Chat button appears: Open specs editor with copilot enabled, verify ✨ button bottom-right
- [ ] Panel toggles: Click button, verify panel expands upward with animation
- [ ] Avatar animates: Send message, verify avatar changes idle → thinking → speaking → idle
- [ ] Streaming works: Send message, verify tokens appear character-by-character
- [ ] Multi-turn context: Ask "draft a spec", then "add validation section", verify copilot understands
- [ ] History persists: Send messages, refresh page, verify conversation retained
- [ ] Clear history works: Click clear button, confirm dialog, verify localStorage cleared
- [ ] Insert spec works: Generate spec, click Insert, verify editor content populated
- [ ] Error handling: Disconnect network, send message, verify error state and retry button
- [ ] Avatar transitions: Type in input (listening), send (thinking), receive (speaking), complete (idle)
- [ ] Token limit: Send 15 messages, verify old messages summarized
- [ ] Context sources: Disable LEARNINGS.md in settings, verify not included in system prompt

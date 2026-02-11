# S-0027: Fix Repeating Streaming Copilot Output

## Narrative

As a Felix user using the copilot chat feature, I need the streaming response to display tokens correctly without repetition, so that I can read the assistant's responses clearly without duplicate words appearing multiple times in the output.

Currently, the copilot streaming implementation has a bug where tokens from the LLM API are being repeated in the displayed output. Users see responses like "Hello Hello world world this this is is a a test test" instead of "Hello world this is a test". This occurs because the streaming token accumulation logic has race conditions and improper state management that causes tokens to be processed and displayed multiple times.

The bug manifests in several scenarios:

- **Token Buffering Issues**: Multiple SSE events arrive rapidly and tokens get buffered/processed multiple times
- **State Race Conditions**: React state updates are not atomic, causing duplicate token appends
- **SSE Parser Problems**: Incomplete SSE lines are parsed multiple times as the buffer accumulates
- **Stream Reconnection**: Network hiccups cause partial streams to replay tokens already processed

This fix implements proper token deduplication, atomic state updates, robust SSE parsing, and stream recovery mechanisms to ensure each token is displayed exactly once.

## Acceptance Criteria

### Token Deduplication

- [ ] Each token from the LLM API is processed and displayed exactly once
- [ ] No duplicate words appear in streamed responses (e.g., "Hello Hello world world")
- [ ] Token accumulation uses atomic state updates to prevent race conditions
- [ ] Multiple rapid SSE events don't cause token repetition
- [ ] Stream interruption and resumption don't replay already-displayed tokens

### SSE Buffer Management

- [ ] SSE response parsing handles incomplete lines correctly without reprocessing
- [ ] Buffer management prevents partial JSON objects from being parsed multiple times
- [ ] Line splitting logic accounts for different line ending formats (`\n`, `\r\n`)
- [ ] Empty data lines and malformed SSE events are ignored safely
- [ ] Buffer overflow protection prevents memory issues during long responses

### State Management

- [ ] Message content updates use functional state updates to prevent stale closures
- [ ] Token appending is atomic and doesn't rely on current state that might be outdated
- [ ] React state batching doesn't cause tokens to be lost or duplicated
- [ ] Avatar state changes don't interfere with message content streaming
- [ ] Component unmounting during streaming cancels operations cleanly

### Stream Recovery

- [ ] Network interruptions don't cause token repetition when stream resumes
- [ ] Cancelled streams don't leave partial tokens that affect next stream
- [ ] Stream controller cleanup prevents event handlers from firing after cancellation
- [ ] AbortController properly terminates fetch requests and event listeners
- [ ] Memory leaks from abandoned event listeners are prevented

### Error Handling

- [ ] JSON parsing errors in SSE data don't break the entire stream
- [ ] Network timeouts are handled gracefully without token duplication
- [ ] API errors display once and don't retry automatically causing repeated error messages
- [ ] Malformed SSE events are logged but don't stop processing valid events
- [ ] Stream-level errors reset state cleanly for the next conversation turn

### Performance

- [ ] Token processing is efficient and doesn't cause UI lag during fast streams
- [ ] Large responses (>4000 tokens) stream smoothly without performance degradation
- [ ] Memory usage remains stable during extended chat sessions
- [ ] Rapid token arrival doesn't overwhelm React's state update queue
- [ ] Auto-scroll performance remains smooth during token streaming

## Technical Implementation

### Root Cause Analysis

The repeating output bug has several contributing factors identified in the codebase. The proposed suggestions are just that, you should still do a full analysis as part of your planning:

1. **SSE Buffer Race Condition** (felixApi.ts lines 1190-1220):

   ```typescript
   // PROBLEMATIC: buffer concatenation without proper line boundary handling
   buffer += decoder.decode(value, { stream: true });
   const lines = buffer.split("\n");
   buffer = lines.pop() || ""; // Last line might be incomplete
   ```

   Issue: When multiple chunks arrive rapidly, the buffer splitting logic can reprocess the same data.

2. **Non-Atomic State Updates** (CopilotChat.tsx lines 280-290):

   ```typescript
   // PROBLEMATIC: State update relies on previous state
   setMessages((prev) => {
     const updated = [...prev];
     const lastMsg = updated[updated.length - 1];
     if (lastMsg && lastMsg.id === assistantMessageId) {
       lastMsg.content += event.token; // This mutation can cause issues
     }
     return updated;
   });
   ```

   Issue: Direct mutation of state objects can cause React to miss updates or process them multiple times.

3. **Event Handler Cleanup** (felixApi.ts lines 1165-1185):
   ```typescript
   // PROBLEMATIC: Event handlers not properly cleaned up on cancellation
   cancel: () => {
     abortController?.abort();
     abortController = null;
     // Missing: Clear event callbacks to prevent stale handler execution
   };
   ```

### Fixed Implementation

**1. Robust SSE Parsing with Deduplication**

```typescript
// app/frontend/services/felixApi.ts - Enhanced stream parsing
streamCopilotChat(request: CopilotChatRequest): CopilotStreamController {
  let abortController: AbortController | null = new AbortController();
  let eventCallback: ((event: CopilotStreamEvent) => void) | null = null;
  let errorCallback: ((error: Error) => void) | null = null;
  let completeCallback: (() => void) | null = null;
  let processedEventIds = new Set<string>(); // Prevent duplicate events

  const startStream = async () => {
    try {
      // ... fetch setup ...

      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error("Response body is not readable");
      }

      const decoder = new TextDecoder();
      let buffer = "";
      let lineNumber = 0; // Track line numbers for deduplication

      while (true) {
        if (abortController?.signal.aborted) {
          break;
        }

        const { done, value } = await reader.read();

        if (done) {
          completeCallback?.();
          break;
        }

        // Robust buffer management
        const chunk = decoder.decode(value, { stream: true });
        buffer += chunk;

        // Handle different line endings consistently
        const lines = buffer.split(/\r?\n/);

        // Keep incomplete line in buffer
        buffer = lines.pop() || "";

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim();
          lineNumber++;

          if (!line || !line.startsWith("data: ")) {
            continue;
          }

          try {
            const dataStr = line.slice(6).trim();
            if (!dataStr || dataStr === "[DONE]") {
              if (dataStr === "[DONE]") {
                completeCallback?.();
                return;
              }
              continue;
            }

            // Create unique event ID for deduplication
            const eventId = `${lineNumber}_${dataStr.slice(0, 50)}`;
            if (processedEventIds.has(eventId)) {
              console.warn('Duplicate SSE event detected, skipping:', eventId);
              continue;
            }
            processedEventIds.add(eventId);

            // Clean up old event IDs to prevent memory leak
            if (processedEventIds.size > 1000) {
              const oldestEvents = Array.from(processedEventIds).slice(0, 500);
              oldestEvents.forEach(id => processedEventIds.delete(id));
            }

            const data = JSON.parse(dataStr) as CopilotStreamEvent;

            // Only emit if stream hasn't been cancelled
            if (!abortController?.signal.aborted && eventCallback) {
              eventCallback(data);
            }

            // Handle completion
            if (data.done) {
              completeCallback?.();
              return;
            }

            // Handle errors
            if (data.error) {
              errorCallback?.(new Error(data.error));
              return;
            }
          } catch (parseError) {
            console.warn("Failed to parse SSE data:", line, parseError);
            // Continue processing other lines
          }
        }
      }
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        return; // Stream was cancelled
      }
      errorCallback?.(error instanceof Error ? error : new Error(String(error)));
    }
  };

  startStream();

  return {
    onEvent: (callback) => {
      eventCallback = callback;
    },
    onError: (callback) => {
      errorCallback = callback;
    },
    onComplete: (callback) => {
      completeCallback = callback;
    },
    cancel: () => {
      abortController?.abort();
      abortController = null;
      // Clear callbacks to prevent stale handler execution
      eventCallback = null;
      errorCallback = null;
      completeCallback = null;
      processedEventIds.clear();
    },
  };
}
```

**2. Atomic Message State Updates**

```typescript
// app/frontend/components/CopilotChat.tsx - Enhanced message handling
const CopilotChat: React.FC<CopilotChatProps> = ({ ... }) => {
  // ... existing state ...

  // Track current streaming message to prevent race conditions
  const streamingMessageRef = useRef<{
    id: string;
    content: string;
    tokenCount: number;
  } | null>(null);

  const handleSendMessage = useCallback(async () => {
    // ... user message creation ...

    // Create placeholder assistant message
    const assistantMessageId = generateMessageId();
    const assistantMessage: ChatMessage = {
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: new Date(),
    };
    setMessages(prev => [...prev, assistantMessage]);

    // Initialize streaming tracker
    streamingMessageRef.current = {
      id: assistantMessageId,
      content: '',
      tokenCount: 0,
    };

    try {
      const streamController = felixApi.streamCopilotChat({...});
      streamControllerRef.current = streamController;

      // Handle stream events with atomic updates
      streamController.onEvent((event: CopilotStreamEvent) => {
        // Update avatar state if provided
        if (event.avatar_state) {
          setAvatarState(event.avatar_state);
        }

        // Handle tokens with deduplication
        if (event.token && streamingMessageRef.current) {
          const streamingMsg = streamingMessageRef.current;

          // Verify this is still the current streaming message
          if (streamingMsg.id === assistantMessageId) {
            // Append token to tracked content
            streamingMsg.content += event.token;
            streamingMsg.tokenCount++;

            // Atomic state update using the tracked content
            setMessages(prev => {
              const updated = [...prev];
              const targetMsg = updated.find(msg => msg.id === assistantMessageId);
              if (targetMsg) {
                // Create new message object to ensure React detects the change
                const newMsg: ChatMessage = {
                  ...targetMsg,
                  content: streamingMsg.content, // Use tracked content, not concatenation
                };
                const index = updated.findIndex(msg => msg.id === assistantMessageId);
                updated[index] = newMsg;
              }
              return updated;
            });
          }
        }

        // Handle completion
        if (event.done) {
          setIsStreaming(false);
          setAvatarState('idle');
          streamControllerRef.current = null;
          streamingMessageRef.current = null;

          if (!isOpen) {
            setUnreadCount(prev => prev + 1);
          }
        }

        // Handle errors
        if (event.error) {
          console.error('Stream error:', event.error);
          setLastError(event.error);
          setLastFailedMessage(trimmedInput);

          // Clean error handling
          if (streamingMessageRef.current && streamingMessageRef.current.content === '') {
            // No content received yet - show error message
            setMessages(prev => {
              const updated = [...prev];
              const targetMsg = updated.find(msg => msg.id === assistantMessageId);
              if (targetMsg) {
                const errorMsg = { ...targetMsg, content: `❌ Error: ${event.error}` };
                const index = updated.findIndex(msg => msg.id === assistantMessageId);
                updated[index] = errorMsg;
              }
              return updated;
            });
          } else if (streamingMessageRef.current) {
            // Partial content received - add interruption notice
            const finalContent = streamingMessageRef.current.content + '\n\n⚠️ Stream interrupted';
            setMessages(prev => {
              const updated = [...prev];
              const targetMsg = updated.find(msg => msg.id === assistantMessageId);
              if (targetMsg) {
                const finalMsg = { ...targetMsg, content: finalContent };
                const index = updated.findIndex(msg => msg.id === assistantMessageId);
                updated[index] = finalMsg;
              }
              return updated;
            });
          }

          setTimeout(() => setAvatarState('idle'), 2000);
          setIsStreaming(false);
          streamControllerRef.current = null;
          streamingMessageRef.current = null;
        }
      });

      // ... error handling ...
    } catch (err) {
      // ... error handling ...
      streamingMessageRef.current = null;
    }
  }, [inputValue, isStreaming, messages, projectPath, generateMessageId, isOpen]);

  // Clean up streaming ref on cancel
  const handleCancelStream = useCallback(() => {
    if (streamControllerRef.current) {
      streamControllerRef.current.cancel();
      streamControllerRef.current = null;

      // Finalize the streaming message
      if (streamingMessageRef.current) {
        const finalContent = streamingMessageRef.current.content +
          (streamingMessageRef.current.content ? '\n\n⚠️ Stream cancelled' : '⚠️ Response cancelled');

        setMessages(prev => {
          const updated = [...prev];
          const targetMsg = updated.find(msg => msg.id === streamingMessageRef.current!.id);
          if (targetMsg) {
            const finalMsg = { ...targetMsg, content: finalContent };
            const index = updated.findIndex(msg => msg.id === streamingMessageRef.current!.id);
            updated[index] = finalMsg;
          }
          return updated;
        });

        streamingMessageRef.current = null;
      }
    }

    setIsStreaming(false);
    setAvatarState('idle');
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (streamControllerRef.current) {
        streamControllerRef.current.cancel();
      }
      streamingMessageRef.current = null;
    };
  }, []);

  // ... rest of component
};
```

**3. Backend Stream Reliability**

```python
# app/backend/services/copilot.py - Enhanced streaming with deduplication
import uuid
import time

class CopilotService:
    async def stream_response(
        self, messages: List[Dict[str, str]]
    ) -> AsyncGenerator[str, None]:
        """Enhanced streaming with token deduplication and reliable event emission"""

        # Generate unique stream ID for this response
        stream_id = str(uuid.uuid4())
        token_counter = 0

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
            yield f"data: {json.dumps({'error': str(e), 'avatar_state': 'error', 'stream_id': stream_id})}\n\n"

    async def _stream_openai(
        self, messages: List[Dict[str, str]], stream_id: str
    ) -> AsyncGenerator[str, None]:
        """Enhanced OpenAI streaming with token deduplication"""
        try:
            client = AsyncOpenAI(api_key=self.api_key, timeout=60.0)

            # Signal speaking state
            yield f"data: {json.dumps({'avatar_state': 'speaking', 'stream_id': stream_id})}\n\n"

            token_counter = 0
            stream = await client.chat.completions.create(
                model=self.config.model,
                messages=messages,
                stream=True,
                max_tokens=4000
            )

            async for chunk in stream:
                if chunk.choices:
                    delta = chunk.choices[0].delta
                    if delta.content:
                        token_counter += 1
                        # Include token counter for frontend deduplication
                        event_data = {
                            'token': delta.content,
                            'token_id': f"{stream_id}_{token_counter}",
                            'stream_id': stream_id
                        }
                        yield f"data: {json.dumps(event_data)}\n\n"

                        # Small delay to prevent overwhelming the client
                        if token_counter % 10 == 0:
                            await asyncio.sleep(0.001)

        except Exception as e:
            # Enhanced error handling with stream context
            error_data = {
                'error': str(e),
                'avatar_state': 'error',
                'stream_id': stream_id,
                'error_type': type(e).__name__
            }
            yield f"data: {json.dumps(error_data)}\n\n"

    async def _stream_anthropic(
        self, messages: List[Dict[str, str]], stream_id: str
    ) -> AsyncGenerator[str, None]:
        """Enhanced Anthropic streaming with token deduplication"""
        try:
            # Extract system prompt
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
                            'token': text,
                            'token_id': f"{stream_id}_{token_counter}",
                            'stream_id': stream_id
                        }
                        yield f"data: {json.dumps(event_data)}\n\n"

                        # Small delay to prevent overwhelming
                        if token_counter % 10 == 0:
                            await asyncio.sleep(0.001)

        except Exception as e:
            error_data = {
                'error': str(e),
                'avatar_state': 'error',
                'stream_id': stream_id,
                'error_type': type(e).__name__
            }
            yield f"data: {json.dumps(error_data)}\n\n"
```

## Dependencies

- S-0017 (Copilot Chat Assistant) - requires streaming infrastructure to be functioning
- S-0002 (Backend API) - requires SSE streaming endpoints
- **Enhanced:** Server-Side Events (SSE) error handling
- **Enhanced:** React state management for concurrent updates
- **New:** Token deduplication algorithms
- **New:** Stream recovery mechanisms

## Non-Goals

- Changing the overall streaming architecture (keep SSE)
- Supporting other streaming protocols (WebSockets, HTTP/2 Server Push)
- Implementing message persistence during stream failures
- Adding stream compression or optimization
- Supporting multiple concurrent streams per session
- Implementing custom retry logic for individual tokens
- Adding real-time collaboration features to streaming
- Supporting offline mode or stream caching

## Validation Criteria

- [ ] Start copilot chat: Open specs editor, send message, verify no repeated words in response
- [ ] Fast streaming test: Send message requesting long response, verify tokens appear once each during rapid streaming
- [ ] Network interruption test: Disconnect network during streaming, verify no token repetition when reconnected
- [ ] Cancellation test: Start stream, click cancel mid-response, verify partial response shows correctly without duplication
- [ ] Multiple messages test: Send several messages in succession, verify each response is clean without token repetition
- [ ] Large response test: Request 4000-token response, verify no performance issues or repeated tokens
- [ ] Error recovery test: Trigger API error during streaming, verify error message appears once
- [ ] Browser refresh test: Refresh page during streaming, verify no memory leaks or zombie event handlers
- [ ] Concurrent tab test: Open multiple tabs, verify streaming in one tab doesn't affect others
- [ ] Mobile browser test: Test on mobile Safari/Chrome, verify touch interactions don't cause duplicate tokens
- [ ] Long session test: Conduct 20+ message conversation, verify token processing remains reliable throughout


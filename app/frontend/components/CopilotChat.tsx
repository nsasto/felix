import React, { useState, useCallback, useRef, useEffect } from 'react';
import CopilotChatButton from './CopilotChatButton';
import CopilotChatPanel from './CopilotChatPanel';
import { AvatarState } from './CopilotAvatar';
import { 
  felixApi, 
  ChatMessage, 
  CopilotStreamController,
  CopilotStreamEvent 
} from '../services/felixApi';

/** Maximum number of messages to store in localStorage */
const MAX_STORED_MESSAGES = 50;

/** localStorage key prefix for chat history */
const STORAGE_KEY_PREFIX = 'felix_copilot_chat_';

interface CopilotChatProps {
  /** Project ID for API calls and localStorage key */
  projectId: string;
  /** Project path for context loading */
  projectPath?: string;
  /** Callback when user wants to insert generated spec content */
  onInsertSpec?: (content: string) => void;
}

/**
 * Get localStorage key for a project's chat history.
 * @param projectId - The project ID
 * @returns localStorage key in format: felix_copilot_chat_{projectId}
 */
const getStorageKey = (projectId: string): string => {
  return `${STORAGE_KEY_PREFIX}${projectId}`;
};

/**
 * Load chat history from localStorage for a given project.
 * @param projectId - The project ID
 * @returns Array of ChatMessages, or empty array if none found
 */
const loadChatHistory = (projectId: string): ChatMessage[] => {
  try {
    const storageKey = getStorageKey(projectId);
    const saved = localStorage.getItem(storageKey);
    if (!saved) return [];
    
    const parsed = JSON.parse(saved);
    if (!Array.isArray(parsed)) return [];
    
    // Convert stored timestamps back to Date objects
    return parsed.map((msg: any) => ({
      ...msg,
      timestamp: new Date(msg.timestamp),
    }));
  } catch (err) {
    console.error('Failed to load chat history from localStorage:', err);
    return [];
  }
};

/**
 * Save chat history to localStorage for a given project.
 * Maintains a maximum of MAX_STORED_MESSAGES messages (FIFO).
 * @param projectId - The project ID
 * @param messages - Array of ChatMessages to save
 */
const saveChatHistory = (projectId: string, messages: ChatMessage[]): void => {
  try {
    const storageKey = getStorageKey(projectId);
    
    // Keep only the last MAX_STORED_MESSAGES messages (FIFO)
    const toSave = messages.slice(-MAX_STORED_MESSAGES);
    
    // Convert Date objects to ISO strings for storage
    const serialized = toSave.map(msg => ({
      ...msg,
      timestamp: msg.timestamp instanceof Date 
        ? msg.timestamp.toISOString() 
        : msg.timestamp,
    }));
    
    localStorage.setItem(storageKey, JSON.stringify(serialized));
  } catch (err) {
    console.error('Failed to save chat history to localStorage:', err);
  }
};

/**
 * Clear chat history from localStorage for a given project.
 * @param projectId - The project ID
 */
const clearChatHistory = (projectId: string): void => {
  try {
    const storageKey = getStorageKey(projectId);
    localStorage.removeItem(storageKey);
  } catch (err) {
    console.error('Failed to clear chat history from localStorage:', err);
  }
};

/**
 * CopilotChat - Main chat component integrating button, panel, and streaming logic.
 * 
 * Features:
 * - Streaming responses via SSE (Server-Sent Events)
 * - Token-by-token message building
 * - Avatar state updates from stream
 * - Cancel button during streaming
 * - Error handling and retry
 * 
 * This component manages all chat state and coordinates between:
 * - CopilotChatButton (floating FAB)
 * - CopilotChatPanel (chat UI with messages and input)
 * - Backend streaming API (/api/copilot/chat/stream)
 */
const CopilotChat: React.FC<CopilotChatProps> = ({
  projectId,
  projectPath,
  onInsertSpec,
}) => {
  // Panel open/close state
  const [isOpen, setIsOpen] = useState(false);
  
  // Chat messages
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  
  // Input state
  const [inputValue, setInputValue] = useState('');
  
  // Avatar state
  const [avatarState, setAvatarState] = useState<AvatarState>('idle');
  
  // Streaming state
  const [isStreaming, setIsStreaming] = useState(false);
  
  // Unread count (for badge when panel is closed)
  const [unreadCount, setUnreadCount] = useState(0);
  
  // Reference to the stream controller for cancellation
  const streamControllerRef = useRef<CopilotStreamController | null>(null);
  
  // Context source count (for display in header)
  const [contextSourceCount, setContextSourceCount] = useState(0);
  
  // Error state for retry functionality
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastFailedMessage, setLastFailedMessage] = useState<string | null>(null);

  // Track whether we've loaded history (to prevent saving on initial load)
  const historyLoadedRef = useRef(false);

  // Load chat history from localStorage when component mounts or projectId changes
  useEffect(() => {
    historyLoadedRef.current = false;
    const history = loadChatHistory(projectId);
    setMessages(history);
    // Mark as loaded after setting messages
    // Use a microtask to ensure the state update is processed first
    Promise.resolve().then(() => {
      historyLoadedRef.current = true;
    });
  }, [projectId]);

  // Save chat history to localStorage when messages change
  useEffect(() => {
    // Don't save if we haven't loaded yet (prevents overwriting on initial render)
    // Also don't save if messages array is empty (could be initial state or cleared)
    if (!historyLoadedRef.current) {
      return;
    }
    
    // Save messages (even if empty, which clears the storage)
    saveChatHistory(projectId, messages);
  }, [projectId, messages]);

  // Load context source count from config
  useEffect(() => {
    const loadContextSourceCount = async () => {
      try {
        const config = await felixApi.getGlobalConfig();
        const copilotConfig = config.config.copilot;
        if (copilotConfig?.context_sources) {
          const sources = copilotConfig.context_sources;
          const count = [
            sources.agents_md,
            sources.learnings_md,
            sources.prompt_md,
            sources.requirements,
            sources.other_specs,
          ].filter(Boolean).length;
          setContextSourceCount(count);
        }
      } catch (err) {
        console.error('Failed to load context source count:', err);
        // Default to 4 if we can't load config
        setContextSourceCount(4);
      }
    };
    
    loadContextSourceCount();
  }, []);

  // Clear unread count when panel opens
  useEffect(() => {
    if (isOpen) {
      setUnreadCount(0);
    }
  }, [isOpen]);

  // Generate unique message ID
  const generateMessageId = useCallback(() => {
    return `msg_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }, []);

  /**
   * Handle sending a message and streaming the response.
   * 
   * Flow:
   * 1. Add user message to messages
   * 2. Set avatar to 'thinking'
   * 3. Create placeholder assistant message
   * 4. Start SSE stream
   * 5. Update avatar to 'speaking' when first token arrives
   * 6. Append tokens to assistant message
   * 7. Set avatar to 'idle' when done
   * 8. Handle errors with 'error' avatar state
   */
  const handleSendMessage = useCallback(async () => {
    const trimmedInput = inputValue.trim();
    if (!trimmedInput || isStreaming) return;

    // Clear any previous error state
    setLastError(null);
    setLastFailedMessage(null);

    // Create user message
    const userMessage: ChatMessage = {
      id: generateMessageId(),
      role: 'user',
      content: trimmedInput,
      timestamp: new Date(),
    };

    // Add user message to state
    setMessages(prev => [...prev, userMessage]);
    setInputValue('');
    setAvatarState('thinking');
    setIsStreaming(true);

    // Create placeholder assistant message
    const assistantMessageId = generateMessageId();
    const assistantMessage: ChatMessage = {
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: new Date(),
    };
    setMessages(prev => [...prev, assistantMessage]);

    try {
      // Build conversation history for context (last 10 messages, excluding the new ones)
      const historyForApi = messages.slice(-10).map(msg => ({
        role: msg.role,
        content: msg.content,
      }));

      // Start streaming
      const streamController = felixApi.streamCopilotChat({
        message: trimmedInput,
        history: historyForApi,
        project_path: projectPath,
      });

      // Store controller for cancellation
      streamControllerRef.current = streamController;

      // Handle stream events
      streamController.onEvent((event: CopilotStreamEvent) => {
        // Update avatar state if provided
        if (event.avatar_state) {
          setAvatarState(event.avatar_state);
        }

        // Append token to assistant message
        if (event.token) {
          setMessages(prev => {
            const updated = [...prev];
            const lastMsg = updated[updated.length - 1];
            if (lastMsg && lastMsg.id === assistantMessageId) {
              lastMsg.content += event.token;
            }
            return updated;
          });
        }

        // Handle completion
        if (event.done) {
          setIsStreaming(false);
          setAvatarState('idle');
          streamControllerRef.current = null;
          
          // Increment unread count if panel is closed
          if (!isOpen) {
            setUnreadCount(prev => prev + 1);
          }
        }

        // Handle errors from stream
        if (event.error) {
          console.error('Stream error:', event.error);
          setLastError(event.error);
          setLastFailedMessage(trimmedInput);
          
          // Update assistant message with error indicator
          setMessages(prev => {
            const updated = [...prev];
            const lastMsg = updated[updated.length - 1];
            if (lastMsg && lastMsg.id === assistantMessageId && !lastMsg.content) {
              lastMsg.content = `❌ Error: ${event.error}`;
            } else if (lastMsg && lastMsg.id === assistantMessageId) {
              // Partial message - add interruption indicator
              lastMsg.content += '\n\n⚠️ Stream interrupted';
            }
            return updated;
          });
          
          // Avatar will be set to error by the event, then we reset to idle
          setTimeout(() => setAvatarState('idle'), 2000);
          setIsStreaming(false);
          streamControllerRef.current = null;
        }
      });

      // Handle stream-level errors
      streamController.onError((error: Error) => {
        console.error('Stream connection error:', error);
        setLastError(error.message);
        setLastFailedMessage(trimmedInput);
        
        // Update assistant message with error
        setMessages(prev => {
          const updated = [...prev];
          const lastMsg = updated[updated.length - 1];
          if (lastMsg && lastMsg.id === assistantMessageId && !lastMsg.content) {
            lastMsg.content = `❌ Connection lost. ${error.message}`;
          } else if (lastMsg && lastMsg.id === assistantMessageId) {
            lastMsg.content += '\n\n⚠️ Stream interrupted';
          }
          return updated;
        });
        
        setAvatarState('error');
        setTimeout(() => setAvatarState('idle'), 2000);
        setIsStreaming(false);
        streamControllerRef.current = null;
      });

      // Handle stream completion
      streamController.onComplete(() => {
        setIsStreaming(false);
        setAvatarState('idle');
        streamControllerRef.current = null;
      });

    } catch (err) {
      console.error('Failed to start stream:', err);
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      setLastError(errorMessage);
      setLastFailedMessage(trimmedInput);
      
      // Update assistant message with error
      setMessages(prev => {
        const updated = [...prev];
        const lastMsg = updated[updated.length - 1];
        if (lastMsg && lastMsg.id === assistantMessageId) {
          lastMsg.content = `❌ Failed to connect: ${errorMessage}`;
        }
        return updated;
      });
      
      setAvatarState('error');
      setTimeout(() => setAvatarState('idle'), 2000);
      setIsStreaming(false);
    }
  }, [inputValue, isStreaming, messages, projectPath, generateMessageId, isOpen]);

  /**
   * Handle canceling the current stream.
   */
  const handleCancelStream = useCallback(() => {
    if (streamControllerRef.current) {
      streamControllerRef.current.cancel();
      streamControllerRef.current = null;
      
      // Mark the last message as interrupted
      setMessages(prev => {
        const updated = [...prev];
        const lastMsg = updated[updated.length - 1];
        if (lastMsg && lastMsg.role === 'assistant') {
          if (lastMsg.content) {
            lastMsg.content += '\n\n⚠️ Stream cancelled';
          } else {
            lastMsg.content = '⚠️ Response cancelled';
          }
        }
        return updated;
      });
    }
    
    setIsStreaming(false);
    setAvatarState('idle');
  }, []);

  /**
   * Handle clearing chat history.
   * Clears both in-memory state and localStorage.
   */
  const handleClearHistory = useCallback(() => {
    // Cancel any ongoing stream
    if (streamControllerRef.current) {
      streamControllerRef.current.cancel();
      streamControllerRef.current = null;
    }
    
    // Clear localStorage for this project
    clearChatHistory(projectId);
    
    // Clear in-memory state
    setMessages([]);
    setIsStreaming(false);
    setAvatarState('idle');
    setLastError(null);
    setLastFailedMessage(null);
    setUnreadCount(0);
  }, [projectId]);

  /**
   * Handle input focus - set avatar to listening.
   */
  const handleInputFocus = useCallback(() => {
    if (!isStreaming) {
      setAvatarState('listening');
    }
  }, [isStreaming]);

  /**
   * Handle input blur - reset avatar to idle if not streaming.
   */
  const handleInputBlur = useCallback(() => {
    if (!isStreaming && avatarState === 'listening') {
      setAvatarState('idle');
    }
  }, [isStreaming, avatarState]);

  /**
   * Handle input change with listening state.
   */
  const handleInputChange = useCallback((value: string) => {
    setInputValue(value);
    // Set to listening when typing
    if (!isStreaming && value.trim()) {
      setAvatarState('listening');
    }
  }, [isStreaming]);

  /**
   * Toggle panel open/close.
   */
  const handleTogglePanel = useCallback(() => {
    setIsOpen(prev => !prev);
  }, []);

  /**
   * Close panel.
   */
  const handleClosePanel = useCallback(() => {
    setIsOpen(false);
  }, []);

  /**
   * Handle quick draft action - prompts user to describe what spec to draft.
   */
  const handleQuickDraft = useCallback(() => {
    setInputValue('Draft a spec for: ');
    // Focus will be handled by the panel's auto-focus
  }, []);

  /**
   * Handle help command - shows available commands and features.
   */
  const handleHelpCommand = useCallback(() => {
    const helpMessage: ChatMessage = {
      id: generateMessageId(),
      role: 'assistant',
      content: `## Available Commands

**Quick Actions:**
- **✨ Draft Spec** - Click to start drafting a new specification
- **❓ Help** - Show this help message

**Text Commands:**
- Type \`/draft <description>\` to quickly draft a spec
- Type \`/help\` to show this help message

**Features:**
- **Spec Generation** - Ask me to draft specifications following your project conventions
- **Context Awareness** - I know your project structure from AGENTS.md, LEARNINGS.md, and other specs
- **Insert to Editor** - Click "Insert Spec" on generated specs to add them to the editor
- **Multi-turn Chat** - I remember our conversation context for follow-up questions

**Tips:**
- Be specific about what you need (e.g., "Draft a spec for user authentication with OAuth")
- Ask me to add sections like validation criteria or technical notes
- I can help review and improve existing specs`,
      timestamp: new Date(),
    };
    setMessages(prev => [...prev, helpMessage]);
  }, [generateMessageId]);

  /**
   * Handle inserting spec content into the editor.
   */
  const handleInsertSpec = useCallback((content: string) => {
    if (onInsertSpec) {
      onInsertSpec(content);
    }
  }, [onInsertSpec]);

  return (
    <>
      {/* Floating Chat Button */}
      <CopilotChatButton
        isOpen={isOpen}
        onClick={handleTogglePanel}
        unreadCount={unreadCount}
      />

      {/* Chat Panel */}
      <CopilotChatPanel
        isOpen={isOpen}
        onClose={handleClosePanel}
        avatarState={avatarState}
        messages={messages}
        inputValue={inputValue}
        onInputChange={handleInputChange}
        onSendMessage={handleSendMessage}
        isStreaming={isStreaming}
        onCancelStream={handleCancelStream}
        onClearHistory={handleClearHistory}
        contextSourceCount={contextSourceCount}
        onInsertSpec={handleInsertSpec}
        onQuickDraft={handleQuickDraft}
        onHelpCommand={handleHelpCommand}
      />
    </>
  );
};

export default CopilotChat;

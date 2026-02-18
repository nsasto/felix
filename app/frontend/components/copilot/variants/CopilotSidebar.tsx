import React, { useState, useCallback, useRef, useEffect } from "react";
import { AvatarState } from "../CopilotAvatar";
import {
  felixApi,
  ChatMessage,
  CopilotStreamController,
  CopilotStreamEvent,
} from "../../../services/felixApi";
import { CopilotHeader } from "../building-blocks/CopilotHeader";
import { CopilotMessageBubble } from "../building-blocks/CopilotMessageBubble";
import { CopilotInput } from "../building-blocks/CopilotInput";
import { CopilotLoading } from "../building-blocks/CopilotLoading";
import { CopilotEmptyState } from "../building-blocks/CopilotEmptyState";
import { Button } from "../../ui/button";
import { Sparkles } from "lucide-react";

/** Maximum number of messages to store in localStorage */
const MAX_STORED_MESSAGES = 50;

/** localStorage key prefix for chat history */
const STORAGE_KEY_PREFIX = "felix_copilot_chat_";

interface CopilotSidebarProps {
  /** Project ID for API calls and localStorage key */
  projectId: string;
  /** Callback when user wants to insert generated spec content */
  onInsertSpec?: (content: string) => void;
}

/**
 * Get localStorage key for a project's chat history
 */
const getStorageKey = (projectId: string): string => {
  return `${STORAGE_KEY_PREFIX}${projectId}`;
};

/**
 * Load chat history from localStorage
 */
const loadChatHistory = (projectId: string): ChatMessage[] => {
  try {
    const storageKey = getStorageKey(projectId);
    const saved = localStorage.getItem(storageKey);
    if (!saved) return [];

    const parsed = JSON.parse(saved);
    if (!Array.isArray(parsed)) return [];

    return parsed.map((msg: any) => ({
      ...msg,
      timestamp: new Date(msg.timestamp),
    }));
  } catch (err) {
    console.error("Failed to load chat history:", err);
    return [];
  }
};

/**
 * Save chat history to localStorage
 */
const saveChatHistory = (projectId: string, messages: ChatMessage[]): void => {
  try {
    const storageKey = getStorageKey(projectId);
    const toSave = messages.slice(-MAX_STORED_MESSAGES);

    const serialized = toSave.map((msg) => ({
      ...msg,
      timestamp:
        msg.timestamp instanceof Date
          ? msg.timestamp.toISOString()
          : msg.timestamp,
    }));

    localStorage.setItem(storageKey, JSON.stringify(serialized));
  } catch (err) {
    console.error("Failed to save chat history:", err);
  }
};

/**
 * Clear chat history from localStorage
 */
const clearChatHistory = (projectId: string): void => {
  try {
    const storageKey = getStorageKey(projectId);
    localStorage.removeItem(storageKey);
  } catch (err) {
    console.error("Failed to clear chat history:", err);
  }
};

/**
 * CopilotSidebar - Full-height sidebar chat implementation
 *
 * Features:
 * - Reusable chat state management
 * - Streaming responses with token-by-token updates
 * - Message history persistence to localStorage
 * - Avatar state transitions
 * - Error handling and retry
 * - Spec insertion support
 *
 * This variant is designed for inline/sidebar placement, not floating.
 */
export const CopilotSidebar: React.FC<CopilotSidebarProps> = ({
  projectId,
  onInsertSpec,
}) => {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputValue, setInputValue] = useState("");
  const [avatarState, setAvatarState] = useState<AvatarState>("idle");
  const [isStreaming, setIsStreaming] = useState(false);
  const [contextSourceCount, setContextSourceCount] = useState(0);

  const streamControllerRef = useRef<CopilotStreamController | null>(null);
  const streamingMessageRef = useRef<{
    id: string;
    content: string;
    tokenCount: number;
  } | null>(null);
  const historyLoadedRef = useRef(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Load chat history from localStorage when projectId changes
  useEffect(() => {
    historyLoadedRef.current = false;
    const history = loadChatHistory(projectId);
    setMessages(history);
    Promise.resolve().then(() => {
      historyLoadedRef.current = true;
    });
  }, [projectId]);

  // Save chat history to localStorage when messages change
  useEffect(() => {
    if (!historyLoadedRef.current) return;
    saveChatHistory(projectId, messages);
  }, [projectId, messages]);

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // Load context source count from config
  useEffect(() => {
    const loadContextSourceCount = async () => {
      try {
        const configResult = await felixApi.getUserConfig();
        const copilotConfig = configResult.config.copilot;
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
          return;
        }

        setContextSourceCount(4);
      } catch (err) {
        console.error("Failed to load context source count:", err);
        setContextSourceCount(4);
      }
    };

    loadContextSourceCount();
  }, []);

  // Generate unique message ID
  const generateMessageId = useCallback(() => {
    return `msg_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }, []);

  // Handle sending message and streaming response
  const handleSendMessage = useCallback(async () => {
    const trimmedInput = inputValue.trim();
    if (!trimmedInput || isStreaming) return;

    // Create user message
    const userMessage: ChatMessage = {
      id: generateMessageId(),
      role: "user",
      content: trimmedInput,
      timestamp: new Date(),
    };

    setMessages((prev) => [...prev, userMessage]);
    setInputValue("");
    setAvatarState("thinking");
    setIsStreaming(true);

    // Create placeholder assistant message
    const assistantMessageId = generateMessageId();
    const assistantMessage: ChatMessage = {
      id: assistantMessageId,
      role: "assistant",
      content: "",
      timestamp: new Date(),
    };
    setMessages((prev) => [...prev, assistantMessage]);

    streamingMessageRef.current = {
      id: assistantMessageId,
      content: "",
      tokenCount: 0,
    };

    try {
      const historyForApi = messages.slice(-10).map((msg) => ({
        role: msg.role,
        content: msg.content,
      }));

      const streamController = felixApi.streamCopilotChat({
        message: trimmedInput,
        history: historyForApi,
      });

      streamControllerRef.current = streamController;

      streamController.onEvent((event: CopilotStreamEvent) => {
        if (event.avatar_state) {
          setAvatarState(event.avatar_state);
        }

        if (event.token && streamingMessageRef.current) {
          const streamingMsg = streamingMessageRef.current;

          if (streamingMsg.id === assistantMessageId) {
            streamingMsg.content += event.token;
            streamingMsg.tokenCount++;

            setMessages((prev) => {
              const updated = [...prev];
              const targetMsg = updated.find(
                (msg) => msg.id === assistantMessageId,
              );
              if (targetMsg) {
                const newMsg: ChatMessage = {
                  ...targetMsg,
                  content: streamingMsg.content,
                };
                const index = updated.findIndex(
                  (msg) => msg.id === assistantMessageId,
                );
                updated[index] = newMsg;
              }
              return updated;
            });
          }
        }

        if (event.done) {
          setIsStreaming(false);
          setAvatarState("idle");
          streamControllerRef.current = null;
          streamingMessageRef.current = null;
        }

        if (event.error) {
          console.error("Stream error:", event.error);

          if (
            streamingMessageRef.current &&
            streamingMessageRef.current.content === ""
          ) {
            setMessages((prev) => {
              const updated = [...prev];
              const targetMsg = updated.find(
                (msg) => msg.id === assistantMessageId,
              );
              if (targetMsg) {
                const errorMsg = {
                  ...targetMsg,
                  content: `❌ Error: ${event.error}`,
                };
                const index = updated.findIndex(
                  (msg) => msg.id === assistantMessageId,
                );
                updated[index] = errorMsg;
              }
              return updated;
            });
          }

          setTimeout(() => setAvatarState("idle"), 2000);
          setIsStreaming(false);
          streamControllerRef.current = null;
          streamingMessageRef.current = null;
        }
      });

      streamController.onError((error: Error) => {
        console.error("Stream connection error:", error);
        setAvatarState("error");
        setTimeout(() => setAvatarState("idle"), 2000);
        setIsStreaming(false);
        streamControllerRef.current = null;
        streamingMessageRef.current = null;
      });

      streamController.onComplete(() => {
        setIsStreaming(false);
        setAvatarState("idle");
        streamControllerRef.current = null;
        streamingMessageRef.current = null;
      });
    } catch (err) {
      console.error("Failed to start stream:", err);
      setAvatarState("error");
      setTimeout(() => setAvatarState("idle"), 2000);
      setIsStreaming(false);
    }
  }, [inputValue, isStreaming, messages, generateMessageId]);

  // Handle canceling stream
  const handleCancelStream = useCallback(() => {
    if (streamControllerRef.current) {
      streamControllerRef.current.cancel();
      streamControllerRef.current = null;

      if (streamingMessageRef.current) {
        const finalContent =
          streamingMessageRef.current.content +
          (streamingMessageRef.current.content
            ? "\n\n⚠️ Stream cancelled"
            : "⚠️ Response cancelled");

        setMessages((prev) => {
          const updated = [...prev];
          const targetMsg = updated.find(
            (msg) => msg.id === streamingMessageRef.current!.id,
          );
          if (targetMsg) {
            const finalMsg = { ...targetMsg, content: finalContent };
            const index = updated.findIndex(
              (msg) => msg.id === streamingMessageRef.current!.id,
            );
            updated[index] = finalMsg;
          }
          return updated;
        });

        streamingMessageRef.current = null;
      }
    }

    setIsStreaming(false);
    setAvatarState("idle");
  }, []);

  // Handle clearing history
  const handleClearHistory = useCallback(() => {
    if (streamControllerRef.current) {
      streamControllerRef.current.cancel();
      streamControllerRef.current = null;
    }

    clearChatHistory(projectId);
    setMessages([]);
    setIsStreaming(false);
    setAvatarState("idle");
  }, [projectId]);

  // Handle quick draft action
  const handleQuickDraft = useCallback(() => {
    setInputValue("Draft a spec for: ");
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

  return (
    <div className="flex flex-col h-full bg-[var(--bg-surface-100)] border-l border-[var(--border)]">
      {/* Header */}
      <CopilotHeader
        avatarState={avatarState}
        contextSourceCount={contextSourceCount}
        onClearHistory={handleClearHistory}
      />

      {/* Messages Area */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3 custom-scrollbar">
        {messages.length === 0 ? (
          <CopilotEmptyState />
        ) : (
          <>
            {messages.map((msg) => (
              <CopilotMessageBubble
                key={msg.id}
                message={msg}
                isStreaming={isStreaming}
                onInsertSpec={onInsertSpec}
              />
            ))}

            {/* Loading indicator */}
            {isStreaming &&
              messages.length > 0 &&
              messages[messages.length - 1].role === "user" && (
                <CopilotLoading />
              )}

            {/* Scroll anchor */}
            <div ref={messagesEndRef} />
          </>
        )}
      </div>

      {/* Quick Actions */}
      {!isStreaming && (
        <div className="px-4 py-2 border-t border-[var(--border)] flex gap-2">
          <Button
            onClick={handleQuickDraft}
            variant="default"
            size="sm"
            className="gap-1.5"
          >
            <Sparkles className="w-3.5 h-3.5" />
            Draft Spec
          </Button>
        </div>
      )}

      {/* Input Area */}
      <div className="p-4 border-t border-[var(--border)]">
        <CopilotInput
          value={inputValue}
          onChange={setInputValue}
          onSend={handleSendMessage}
          isStreaming={isStreaming}
          onCancel={handleCancelStream}
          autoFocus={false}
        />
      </div>
    </div>
  );
};

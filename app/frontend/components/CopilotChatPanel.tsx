import React, { useEffect, useRef, useCallback } from 'react';
import CopilotAvatar, { AvatarState } from './CopilotAvatar';
import { ChatMessage } from '../services/felixApi';

interface CopilotChatPanelProps {
  /** Whether the panel is open */
  isOpen: boolean;
  /** Callback when panel should close */
  onClose: () => void;
  /** Current avatar animation state */
  avatarState: AvatarState;
  /** Array of chat messages */
  messages: ChatMessage[];
  /** Current input value */
  inputValue: string;
  /** Callback when input changes */
  onInputChange: (value: string) => void;
  /** Callback when message is sent */
  onSendMessage: () => void;
  /** Whether currently streaming a response */
  isStreaming: boolean;
  /** Callback to cancel streaming */
  onCancelStream: () => void;
  /** Callback to clear chat history */
  onClearHistory: () => void;
  /** Number of context sources loaded */
  contextSourceCount?: number;
}

/**
 * Chat panel component for the Felix Copilot chat assistant.
 * Features:
 * - Fixed position above the chat button
 * - Header with avatar, title, and action buttons
 * - Scrollable message area
 * - Input area with send button
 * - Slide-up/down animations
 * - ESC key and outside click to close
 */
const CopilotChatPanel: React.FC<CopilotChatPanelProps> = ({
  isOpen,
  onClose,
  avatarState,
  messages,
  inputValue,
  onInputChange,
  onSendMessage,
  isStreaming,
  onCancelStream,
  onClearHistory,
  contextSourceCount = 0,
}) => {
  const panelRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    if (isOpen) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, isOpen]);

  // Auto-focus input when panel opens
  useEffect(() => {
    if (isOpen) {
      // Small delay to allow animation to start
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  // Handle ESC key to close panel
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (!isOpen) return;
      
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
      }
    },
    [isOpen, onClose]
  );

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  // Handle outside click to close panel
  const handleOutsideClick = useCallback(
    (event: MouseEvent) => {
      if (!isOpen) return;
      
      const panel = panelRef.current;
      if (panel && !panel.contains(event.target as Node)) {
        // Check if click was on the chat button (don't close if clicking the button)
        const chatButton = document.querySelector('[aria-label*="Felix Copilot chat"]');
        if (chatButton && chatButton.contains(event.target as Node)) {
          return;
        }
        onClose();
      }
    },
    [isOpen, onClose]
  );

  useEffect(() => {
    // Add listener with a small delay to prevent immediate closing on open
    if (isOpen) {
      const timer = setTimeout(() => {
        document.addEventListener('mousedown', handleOutsideClick);
      }, 100);
      return () => {
        clearTimeout(timer);
        document.removeEventListener('mousedown', handleOutsideClick);
      };
    }
    return () => {
      document.removeEventListener('mousedown', handleOutsideClick);
    };
  }, [isOpen, handleOutsideClick]);

  // Handle input key events
  const handleInputKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      if (inputValue.trim() && !isStreaming) {
        onSendMessage();
      }
    }
  };

  // Handle clear history with confirmation
  const handleClearHistory = () => {
    if (window.confirm('Clear all conversation history?')) {
      onClearHistory();
    }
  };

  // Format timestamp for display
  const formatTimestamp = (date: Date) => {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  // Character count display
  const charCount = inputValue.length;
  const showCharCount = charCount > 1800;
  const isOverLimit = charCount > 2000;

  return (
    <div
      ref={panelRef}
      className={`
        fixed z-50
        w-[380px] h-[520px]
        rounded-2xl
        theme-bg-surface
        shadow-2xl
        flex flex-col
        overflow-hidden
        transition-all duration-300 ease-out
        ${isOpen 
          ? 'opacity-100 translate-y-0 pointer-events-auto' 
          : 'opacity-0 translate-y-4 pointer-events-none'
        }
      `}
      style={{
        // Position above the chat button (button is 56px, plus 8px gap, plus margin)
        bottom: 'calc(56px + 16px + 8px)',
        right: '16px',
        // Gradient border effect using box-shadow
        boxShadow: isOpen 
          ? '0 25px 50px -12px rgba(0, 0, 0, 0.5), 0 0 0 2px rgba(115, 142, 241, 0.3)'
          : 'none',
      }}
      role="dialog"
      aria-modal="true"
      aria-label="Felix Copilot Chat"
    >
      {/* Header Section - 80px */}
      <div 
        className="h-20 px-4 py-3 border-b theme-border flex items-center gap-3 flex-shrink-0"
        style={{
          background: 'linear-gradient(180deg, rgba(115, 142, 241, 0.1) 0%, transparent 100%)',
        }}
      >
        {/* Avatar */}
        <CopilotAvatar state={avatarState} size={48} />
        
        {/* Title and context badge */}
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-semibold theme-text-primary">Felix Copilot</h3>
          {contextSourceCount > 0 && (
            <span className="text-[10px] theme-text-muted">
              📚 {contextSourceCount} sources
            </span>
          )}
        </div>
        
        {/* Action buttons */}
        <div className="flex items-center gap-1">
          {/* Clear history button */}
          <button
            onClick={handleClearHistory}
            className="p-2 rounded-lg theme-text-muted hover:theme-text-primary hover:bg-slate-800/50 transition-colors"
            aria-label="Clear conversation history"
            title="Clear history"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" 
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" 
              />
            </svg>
          </button>
          
          {/* Minimize button */}
          <button
            onClick={onClose}
            className="p-2 rounded-lg theme-text-muted hover:theme-text-primary hover:bg-slate-800/50 transition-colors"
            aria-label="Minimize chat panel"
            title="Minimize"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 9l-7 7-7-7" />
            </svg>
          </button>
        </div>
      </div>

      {/* Messages Section - flex-1 */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3 custom-scrollbar">
        {/* Empty state */}
        {messages.length === 0 && (
          <div className="h-full flex flex-col items-center justify-center text-center px-6">
            <div className="w-16 h-16 bg-felix-500/10 rounded-full flex items-center justify-center mb-4">
              <span className="text-3xl">✨</span>
            </div>
            <p className="text-sm theme-text-primary font-medium mb-2">
              Hi! I'm Felix Copilot.
            </p>
            <p className="text-xs theme-text-muted">
              Ask me to draft a spec or answer questions about your project.
            </p>
          </div>
        )}

        {/* Message bubbles */}
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            <div
              className={`
                max-w-[85%] rounded-2xl px-4 py-2
                ${msg.role === 'user'
                  ? 'bg-felix-500 text-white'
                  : 'theme-bg-elevated theme-text-primary'
                }
              `}
            >
              {/* Message content */}
              <div className="text-sm whitespace-pre-wrap break-words">
                {msg.content}
              </div>
              
              {/* Timestamp */}
              <div 
                className={`text-[10px] mt-1 ${
                  msg.role === 'user' ? 'text-white/70' : 'theme-text-muted'
                }`}
              >
                {formatTimestamp(msg.timestamp)}
              </div>
            </div>
          </div>
        ))}

        {/* Loading indicator when thinking/streaming */}
        {isStreaming && messages.length > 0 && messages[messages.length - 1].role === 'user' && (
          <div className="flex justify-start">
            <div className="theme-bg-elevated rounded-2xl px-4 py-3">
              <div className="flex items-center gap-1">
                <div className="w-2 h-2 bg-felix-500 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                <div className="w-2 h-2 bg-felix-500 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                <div className="w-2 h-2 bg-felix-500 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
              </div>
            </div>
          </div>
        )}

        {/* Scroll anchor */}
        <div ref={messagesEndRef} />
      </div>

      {/* Input Section - 80px */}
      <div className="h-20 p-3 border-t theme-border flex-shrink-0">
        <div className="flex gap-2 h-full">
          {/* Text input */}
          <div className="flex-1 relative">
            <textarea
              ref={inputRef}
              value={inputValue}
              onChange={(e) => onInputChange(e.target.value)}
              onKeyDown={handleInputKeyDown}
              placeholder="Ask me anything or type /draft to create a spec..."
              maxLength={2000}
              className={`
                w-full h-full px-3 py-2 text-sm
                rounded-lg theme-bg-elevated theme-border
                theme-text-primary placeholder:theme-text-muted
                resize-none
                focus:outline-none focus:ring-2 focus:ring-felix-500/50
                ${isOverLimit ? 'border-red-500' : ''}
              `}
              disabled={isStreaming}
            />
            
            {/* Character count */}
            {showCharCount && (
              <span 
                className={`absolute bottom-1 right-2 text-[10px] ${
                  isOverLimit ? 'text-red-500' : 'theme-text-muted'
                }`}
              >
                {charCount}/2000
              </span>
            )}
          </div>
          
          {/* Send/Cancel button */}
          {isStreaming ? (
            <button
              onClick={onCancelStream}
              className="px-4 rounded-lg bg-red-500 hover:bg-red-600 text-white transition-colors flex items-center justify-center"
              aria-label="Cancel streaming"
              title="Cancel"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          ) : (
            <button
              onClick={onSendMessage}
              disabled={!inputValue.trim() || isOverLimit}
              className={`
                px-4 rounded-lg transition-colors flex items-center justify-center
                ${inputValue.trim() && !isOverLimit
                  ? 'bg-felix-500 hover:bg-felix-600 text-white'
                  : 'bg-slate-700 text-slate-500 cursor-not-allowed'
                }
              `}
              aria-label="Send message"
              title="Send"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" 
                  d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" 
                />
              </svg>
            </button>
          )}
        </div>
      </div>

      {/* Inline CSS for felix colors */}
      <style>{`
        .bg-felix-500 {
          background-color: #738ef1;
        }
        .bg-felix-500\\/10 {
          background-color: rgba(115, 142, 241, 0.1);
        }
        .hover\\:bg-felix-600:hover {
          background-color: #5268e8;
        }
        .ring-felix-500\\/50 {
          --tw-ring-color: rgba(115, 142, 241, 0.5);
        }
      `}</style>
    </div>
  );
};

export default CopilotChatPanel;

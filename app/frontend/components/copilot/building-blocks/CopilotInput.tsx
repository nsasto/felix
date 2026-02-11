import React, { useRef, useEffect } from "react";
import { Button } from "../../ui/button";
import { Textarea } from "../../ui/textarea";
import { Send, X } from "lucide-react";

interface CopilotInputProps {
  value: string;
  onChange: (value: string) => void;
  onSend: () => void;
  isStreaming?: boolean;
  onCancel?: () => void;
  placeholder?: string;
  maxLength?: number;
  autoFocus?: boolean;
}

/**
 * CopilotInput - Input area with send/cancel button
 *
 * Features:
 * - Textarea with character limit
 * - Character count display (when > 1800 chars)
 * - Send button (Enter key, disabled when empty)
 * - Cancel button (during streaming)
 * - Shift+Enter for new line
 * - Auto-focus support
 */
export const CopilotInput: React.FC<CopilotInputProps> = ({
  value,
  onChange,
  onSend,
  isStreaming = false,
  onCancel,
  placeholder = "Ask me anything or type /draft to create a spec...",
  maxLength = 2000,
  autoFocus = false,
}) => {
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Auto-focus when requested
  useEffect(() => {
    if (autoFocus && inputRef.current) {
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [autoFocus]);

  // Handle key events
  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      if (value.trim() && !isStreaming) {
        onSend();
      }
    }
  };

  const charCount = value.length;
  const showCharCount = charCount > 1800;
  const isOverLimit = charCount > maxLength;

  return (
    <div className="flex gap-2">
      {/* Text input */}
      <div className="flex-1 relative">
        <Textarea
          ref={inputRef}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          maxLength={maxLength}
          className={`
            resize-none h-full min-h-[60px]
            ${isOverLimit ? "border-[var(--destructive-500)]" : ""}
          `}
          disabled={isStreaming}
        />

        {/* Character count */}
        {showCharCount && (
          <span
            className={`
              absolute bottom-2 right-2 text-[10px]
              ${isOverLimit ? "text-[var(--destructive-500)]" : "text-[var(--text-muted)]"}
            `}
          >
            {charCount}/{maxLength}
          </span>
        )}
      </div>

      {/* Send/Cancel button */}
      {isStreaming && onCancel ? (
        <Button
          onClick={onCancel}
          variant="destructive"
          size="icon"
          className="self-end"
        >
          <X className="w-5 h-5" />
        </Button>
      ) : (
        <Button
          onClick={onSend}
          disabled={!value.trim() || isOverLimit}
          size="icon"
          className="self-end"
        >
          <Send className="w-5 h-5" />
        </Button>
      )}
    </div>
  );
};

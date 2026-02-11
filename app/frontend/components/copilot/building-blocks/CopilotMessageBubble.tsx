import React, { useCallback } from "react";
import { ChatMessage } from "../../../services/felixApi";
import { marked } from "marked";
import { Button } from "../../ui/button";
import { FileText } from "lucide-react";

interface CopilotMessageBubbleProps {
  message: ChatMessage;
  isStreaming?: boolean;
  onInsertSpec?: (content: string) => void;
}

/**
 * Check if a message content looks like a generated spec.
 * A spec typically has markdown headings (# or ##) and structured content.
 */
const looksLikeSpec = (content: string): boolean => {
  const hasHeading = /^#+ .+/m.test(content);
  const isSubstantial = content.length > 200;
  const hasMultipleSections =
    (content.match(/^#+ .+/gm) || []).length >= 2 ||
    (content.match(/^- \[/gm) || []).length >= 2;

  return hasHeading && isSubstantial && hasMultipleSections;
};

/**
 * Format timestamp for display
 */
const formatTimestamp = (date: Date) => {
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
};

/**
 * Render markdown content for assistant messages.
 * User messages are displayed as plain text.
 */
const renderMessageContent = (msg: ChatMessage) => {
  if (msg.role === "user") {
    return (
      <div className="text-sm whitespace-pre-wrap break-words">
        {msg.content}
      </div>
    );
  }

  try {
    const html = marked.parse(msg.content, { async: false }) as string;
    return (
      <div
        className="text-sm copilot-markdown prose prose-sm prose-invert max-w-none [&>*]:text-[var(--text)]"
        dangerouslySetInnerHTML={{ __html: html }}
      />
    );
  } catch (err) {
    console.error("Markdown parsing error:", err);
    return (
      <div className="text-sm whitespace-pre-wrap break-words">
        {msg.content}
      </div>
    );
  }
};

/**
 * CopilotMessageBubble - Renders a single chat message with optional spec insertion
 *
 * Features:
 * - User messages: right-aligned, brand background
 * - Assistant messages: left-aligned, surface background, markdown rendering
 * - Timestamp display
 * - "Insert Spec" button for spec-like assistant messages
 */
export const CopilotMessageBubble: React.FC<CopilotMessageBubbleProps> = ({
  message,
  isStreaming = false,
  onInsertSpec,
}) => {
  return (
    <div
      className={`flex flex-col ${message.role === "user" ? "items-end" : "items-start"}`}
    >
      <div
        className={`
          max-w-[85%] rounded-2xl px-4 py-2
          ${
            message.role === "user"
              ? "bg-[var(--brand-500)] text-white"
              : "bg-[var(--bg-surface-200)] text-[var(--text)] border border-[var(--border)]"
          }
        `}
      >
        {/* Message content */}
        {renderMessageContent(message)}

        {/* Timestamp */}
        <div
          className={`text-[10px] mt-1 ${
            message.role === "user"
              ? "text-white/70"
              : "text-[var(--text-muted)]"
          }`}
        >
          {formatTimestamp(message.timestamp)}
        </div>
      </div>

      {/* Insert Spec button for spec-like assistant messages */}
      {message.role === "assistant" &&
        !isStreaming &&
        looksLikeSpec(message.content) &&
        onInsertSpec && (
          <Button
            onClick={() => onInsertSpec(message.content)}
            variant="default"
            size="sm"
            className="mt-2 gap-1.5"
          >
            <FileText className="w-3.5 h-3.5" />
            Insert Spec
          </Button>
        )}
    </div>
  );
};

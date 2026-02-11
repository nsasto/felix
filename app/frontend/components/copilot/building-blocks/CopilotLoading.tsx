import React from "react";

/**
 * CopilotLoading - Animated thinking/typing indicator
 *
 * Displays three bouncing dots to indicate the assistant is thinking or generating a response
 */
export const CopilotLoading: React.FC = () => {
  return (
    <div className="flex justify-start">
      <div className="bg-[var(--bg-surface-200)] border border-[var(--border)] rounded-2xl px-4 py-3">
        <div className="flex items-center gap-1">
          <div
            className="w-2 h-2 bg-[var(--brand-500)] rounded-full animate-bounce"
            style={{ animationDelay: "0ms" }}
          />
          <div
            className="w-2 h-2 bg-[var(--brand-500)] rounded-full animate-bounce"
            style={{ animationDelay: "150ms" }}
          />
          <div
            className="w-2 h-2 bg-[var(--brand-500)] rounded-full animate-bounce"
            style={{ animationDelay: "300ms" }}
          />
        </div>
      </div>
    </div>
  );
};

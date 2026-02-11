import React from "react";

interface CopilotEmptyStateProps {
  title?: string;
  message?: string;
}

/**
 * CopilotEmptyState - Empty conversation state
 *
 * Displays a welcoming message when there are no messages yet
 */
export const CopilotEmptyState: React.FC<CopilotEmptyStateProps> = ({
  title = "Hi! I'm Felix Copilot.",
  message = "Ask me to draft a spec or answer questions about your project.",
}) => {
  return (
    <div className="h-full flex flex-col items-center justify-center text-center px-6">
      <div className="w-16 h-16 bg-[var(--brand-500)]/10 rounded-full flex items-center justify-center mb-4">
        <span className="text-3xl">✨</span>
      </div>
      <p className="text-sm text-[var(--text)] font-medium mb-2">{title}</p>
      <p className="text-xs text-[var(--text-muted)]">{message}</p>
    </div>
  );
};

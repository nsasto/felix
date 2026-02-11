import React from "react";
import { AvatarState } from "../CopilotAvatar";
import { Button } from "../../ui/button";
import { Trash2, Minimize2 } from "lucide-react";

interface CopilotHeaderProps {
  avatarState: AvatarState;
  contextSourceCount?: number;
  onClearHistory: () => void;
  onMinimize?: () => void;
  title?: string;
}

/**
 * CopilotHeader - Header with title and action buttons
 *
 * Features:
 * - Title and context badge
 * - Clear history button (with confirmation)
 * - Optional minimize button
 * - Avatar state tracking (for future animated character)
 */
export const CopilotHeader: React.FC<CopilotHeaderProps> = ({
  avatarState,
  contextSourceCount = 0,
  onClearHistory,
  onMinimize,
  title = "Felix Copilot",
}) => {
  const handleClearHistory = () => {
    if (window.confirm("Clear all conversation history?")) {
      onClearHistory();
    }
  };

  return (
    <div className="flex items-center gap-3 p-4 border-b border-[var(--border)]">
      {/* Title and context badge */}
      <div className="flex-1 min-w-0">
        <h3 className="text-sm font-semibold text-[var(--text)]">{title}</h3>
        {contextSourceCount > 0 && (
          <span className="text-[10px] text-[var(--text-muted)]">
            📚 {contextSourceCount} sources
          </span>
        )}
      </div>

      {/* Action buttons */}
      <div className="flex items-center gap-1">
        {/* Clear history button */}
        <Button
          onClick={handleClearHistory}
          variant="ghost"
          size="icon"
          title="Clear history"
        >
          <Trash2 className="w-4 h-4" />
        </Button>

        {/* Minimize button (optional) */}
        {onMinimize && (
          <Button
            onClick={onMinimize}
            variant="ghost"
            size="icon"
            title="Minimize"
          >
            <Minimize2 className="w-4 h-4" />
          </Button>
        )}
      </div>
    </div>
  );
};

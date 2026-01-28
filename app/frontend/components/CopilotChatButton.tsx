import React, { useEffect, useState } from "react";
import { felixApi, CopilotConfig } from "../services/felixApi";

interface CopilotChatButtonProps {
  /** Whether the chat panel is currently open */
  isOpen: boolean;
  /** Callback when button is clicked to toggle panel */
  onClick: () => void;
  /** Number of unread messages (badge count) */
  unreadCount?: number;
}

/**
 * Floating chat button for the Felix Copilot chat assistant.
 * - Fixed position bottom-right with z-50
 * - Sparkle emoji with pulse animation
 * - Badge for unread message count
 * - Only renders when copilot is enabled in settings
 */
const CopilotChatButton: React.FC<CopilotChatButtonProps> = ({
  isOpen,
  onClick,
  unreadCount = 0,
}) => {
  const [isEnabled, setIsEnabled] = useState<boolean | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Check if copilot is enabled in settings
  useEffect(() => {
    const checkCopilotEnabled = async () => {
      try {
        const result = await felixApi.getGlobalConfig();
        const copilotConfig = result.config.copilot as
          | CopilotConfig
          | undefined;
        const enabled = copilotConfig?.enabled ?? false;
        console.log(
          "[CopilotChatButton] Copilot enabled:",
          enabled,
          "Config:",
          copilotConfig,
        );
        setIsEnabled(enabled);
      } catch (error) {
        console.error("Failed to check copilot status:", error);
        setIsEnabled(false);
      } finally {
        setIsLoading(false);
      }
    };

    checkCopilotEnabled();
  }, []);

  console.log(
    "[CopilotChatButton] Render state - isLoading:",
    isLoading,
    "isEnabled:",
    isEnabled,
  );

  // Don't render if copilot is not enabled or still loading
  if (isLoading || !isEnabled) {
    return null;
  }

  return (
    <button
      onClick={onClick}
      className={`
        fixed bottom-12 right-4 z-50
        w-14 h-14 rounded-full
        bg-gradient-to-br from-felix-500 to-felix-600
        text-white shadow-lg
        hover:scale-105 transition-all duration-200
        flex items-center justify-center
        focus:outline-none focus:ring-2 focus:ring-felix-500/50 focus:ring-offset-2 focus:ring-offset-transparent
        ${isOpen ? "scale-95 shadow-md" : "hover:shadow-xl"}
      `}
      aria-label={
        isOpen ? "Close Felix Copilot chat" : "Open Felix Copilot chat"
      }
      title={isOpen ? "Close chat" : "Chat with Felix Copilot"}
    >
      {/* Sparkle emoji with pulse animation */}
      <span
        className={`text-2xl ${!isOpen ? "animate-pulse" : ""}`}
        role="img"
        aria-hidden="true"
      >
        ✨
      </span>

      {/* Unread message count badge */}
      {unreadCount > 0 && !isOpen && (
        <span
          className="
            absolute -top-1 -right-1
            min-w-5 h-5 px-1.5
            bg-red-500 text-white
            text-xs font-bold
            rounded-full
            flex items-center justify-center
            shadow-md
            animate-bounce
          "
          aria-label={`${unreadCount} unread messages`}
        >
          {unreadCount > 99 ? "99+" : unreadCount}
        </span>
      )}

      {/* Inline CSS for felix colors (in case they're not in tailwind config) */}
      <style>{`
        .from-felix-500 {
          --tw-gradient-from: #738ef1;
          --tw-gradient-stops: var(--tw-gradient-from), var(--tw-gradient-to, rgba(115, 142, 241, 0));
        }
        .to-felix-600 {
          --tw-gradient-to: #5268e8;
        }
        .bg-felix-500 {
          background-color: #738ef1;
        }
        .ring-felix-500\\/50 {
          --tw-ring-color: rgba(115, 142, 241, 0.5);
        }
      `}</style>
    </button>
  );
};

export default CopilotChatButton;

import React from "react";
import { Button } from "../../ui/button";
import { AlertCircle, RefreshCw } from "lucide-react";

interface CopilotErrorProps {
  error: string;
  onRetry?: () => void;
}

/**
 * CopilotError - Error display with retry option
 *
 * Shows error message with an optional retry button
 */
export const CopilotError: React.FC<CopilotErrorProps> = ({
  error,
  onRetry,
}) => {
  return (
    <div className="flex justify-start">
      <div className="max-w-[85%] rounded-2xl px-4 py-3 bg-[var(--destructive-500)]/10 border border-[var(--destructive-500)]/20">
        <div className="flex items-start gap-2">
          <AlertCircle className="w-4 h-4 text-[var(--destructive-500)] flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm text-[var(--destructive-500)] font-medium">
              Error
            </p>
            <p className="text-xs text-[var(--text-muted)] mt-1">{error}</p>
            {onRetry && (
              <Button
                onClick={onRetry}
                variant="ghost"
                size="sm"
                className="mt-2 h-7 text-xs gap-1"
              >
                <RefreshCw className="w-3 h-3" />
                Retry
              </Button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

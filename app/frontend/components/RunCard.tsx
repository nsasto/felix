import React from "react";
import { RunHistoryEntry } from "../services/felixApi";
import { cn } from "../lib/utils";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";

interface RunCardProps {
  run: RunHistoryEntry;
  isSelected?: boolean;
  onClick: (runId: string) => void;
}

const RunCard: React.FC<RunCardProps> = ({
  run,
  isSelected = false,
  onClick,
}) => {
  const formatRelativeTime = (isoString: string): string => {
    try {
      const date = new Date(isoString);
      const now = new Date();
      const diff = Math.floor((now.getTime() - date.getTime()) / 1000);
      if (diff < 60) return `${diff}s ago`;
      if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
      if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
      return `${Math.floor(diff / 86400)}d ago`;
    } catch {
      return isoString;
    }
  };

  const getStatusVariant = (status: string) => {
    switch (status) {
      case "completed":
        return "success";
      case "running":
        return "warning";
      case "failed":
        return "destructive";
      default:
        return "default";
    }
  };

  return (
    <Button
      type="button"
      variant="ghost"
      onClick={() => onClick(run.run_id)}
      className={cn(
        "w-full h-auto text-left px-3 py-2 rounded-lg border transition-all duration-200 justify-start",
        isSelected
          ? "bg-[var(--bg-surface-200)] border-[var(--brand-500)]/50 ring-1 ring-[var(--brand-500)]/30"
          : "bg-[var(--bg-surface-100)]/50 border-[var(--border-muted)] hover:border-[var(--border-strong)] hover:bg-[var(--bg-surface-100)]",
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="text-[10px] font-mono text-[var(--text-muted)] truncate mb-0.5">
            {run.run_id}
          </div>
          <div className="flex items-center gap-2 text-[10px] text-[var(--text-lighter)]">
            {run.requirement_id && (
              <span className="px-1.5 py-0.5 rounded bg-[var(--brand-500)]/10 text-[var(--brand-500)] border border-[var(--brand-500)]/20 font-mono">
                {run.requirement_id}
              </span>
            )}
            <span>{formatRelativeTime(run.started_at)}</span>
          </div>
        </div>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {run.exit_code !== null && run.exit_code !== undefined && (
            <span
              className={cn(
                "text-[10px] font-mono",
                run.exit_code === 0
                  ? "text-[var(--brand-500)]"
                  : "text-[var(--destructive-500)]",
              )}
            >
              exit: {run.exit_code}
            </span>
          )}
          <Badge variant={getStatusVariant(run.status)}>{run.status}</Badge>
        </div>
      </div>
    </Button>
  );
};

export default RunCard;

import React from "react";
import { RunHistoryEntry } from "../services/felixApi";

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

  const statusColor =
    run.status === "completed"
      ? "text-emerald-400"
      : run.status === "running"
        ? "text-amber-400"
        : run.status === "failed"
          ? "text-red-400"
          : "text-slate-400";

  const statusBg =
    run.status === "completed"
      ? "bg-emerald-500/10 border-emerald-500/20"
      : run.status === "running"
        ? "bg-amber-500/10 border-amber-500/20"
        : run.status === "failed"
          ? "bg-red-500/10 border-red-500/20"
          : "bg-slate-500/10 border-slate-500/20";

  return (
    <button
      key={run.run_id}
      onClick={() => onClick(run.run_id)}
      className={`
        w-full text-left px-3 py-2 rounded-lg border transition-all
        ${
          isSelected
            ? "theme-bg-elevated border-brand-500/50 ring-1 ring-brand-500/30"
            : "theme-bg-elevated/50 theme-border hover:border-slate-600"
        }
      `}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="text-[10px] font-mono text-slate-400 truncate mb-0.5">
            {run.run_id}
          </div>
          <div className="flex items-center gap-2 text-[10px] text-slate-500">
            {run.requirement_id && (
              <span className="px-1.5 py-0.5 rounded bg-blue-500/10 text-blue-400 border border-blue-500/20 font-mono">
                {run.requirement_id}
              </span>
            )}
            <span>{formatRelativeTime(run.started_at)}</span>
          </div>
        </div>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {run.exit_code !== null && run.exit_code !== undefined && (
            <span
              className={`text-[10px] font-mono ${
                run.exit_code === 0 ? "text-emerald-400" : "text-red-400"
              }`}
            >
              exit: {run.exit_code}
            </span>
          )}
          <span
            className={`text-[10px] font-bold px-1.5 py-0.5 rounded border ${statusBg} ${statusColor} uppercase`}
          >
            {run.status}
          </span>
        </div>
      </div>
    </button>
  );
};

export default RunCard;

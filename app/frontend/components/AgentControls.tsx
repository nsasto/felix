import React, { useState, useEffect, useCallback } from "react";
import { felixApi, AgentStatus, RunHistoryEntry } from "../services/felixApi";
import { IconFelix, IconCpu } from "./Icons";
import RunCard from "./RunCard";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { cn } from "../lib/utils";

interface AgentControlsProps {
  projectId: string;
  /** Called when agent status changes */
  onStatusChange?: (status: AgentStatus) => void;
  /** Compact mode for embedding in smaller spaces */
  compact?: boolean;
  /** Called when a run is selected from history */
  onSelectRun?: (runId: string) => void;
}

const AgentControls: React.FC<AgentControlsProps> = ({
  projectId,
  onStatusChange,
  compact = false,
  onSelectRun,
}) => {
  const [status, setStatus] = useState<AgentStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionInProgress, setActionInProgress] = useState<
    "start" | "stop" | null
  >(null);
  const [runs, setRuns] = useState<RunHistoryEntry[]>([]);
  const [runsLoading, setRunsLoading] = useState(false);
  const [showHistory, setShowHistory] = useState(false);

  // Fetch run history
  const fetchRunHistory = useCallback(async () => {
    if (!projectId) return;

    setRunsLoading(true);
    try {
      const response = await felixApi.listRuns(projectId);
      setRuns(response.runs);
    } catch (err) {
      console.error("Failed to fetch run history:", err);
    } finally {
      setRunsLoading(false);
    }
  }, [projectId]);

  // Fetch status on mount and set up polling
  const fetchStatus = useCallback(async () => {
    if (!projectId) return;

    try {
      const agentStatus = await felixApi.getAgentStatus(projectId);
      setStatus(agentStatus);
      setError(null);
      onStatusChange?.(agentStatus);
    } catch (err) {
      console.error("Failed to fetch agent status:", err);
      // Only set error if this is the initial load
      if (loading) {
        setError(
          err instanceof Error ? err.message : "Failed to fetch agent status",
        );
      }
    } finally {
      setLoading(false);
    }
  }, [projectId, loading, onStatusChange]);

  useEffect(() => {
    // Initial fetch on mount - no polling (removed for Phase -1 cleanup)
    // Real-time updates will be added via Supabase Realtime in Phase 3
    fetchStatus();
    fetchRunHistory();
  }, [projectId]); // Only depend on projectId for initial fetch

  const handleStartAgent = async () => {
    setActionInProgress("start");
    setError(null);

    try {
      const result = await felixApi.startRun(projectId);
      console.log("Agent started:", result);

      // Fetch updated status and run history
      await fetchStatus();
      await fetchRunHistory();
    } catch (err) {
      console.error("Failed to start agent:", err);
      setError(err instanceof Error ? err.message : "Failed to start agent");
    } finally {
      setActionInProgress(null);
    }
  };

  const handleStopAgent = async () => {
    setActionInProgress("stop");
    setError(null);

    try {
      await felixApi.stopRun(projectId);
      console.log("Agent stopped");

      // Fetch updated status and run history
      await fetchStatus();
      await fetchRunHistory();
    } catch (err) {
      console.error("Failed to stop agent:", err);
      setError(err instanceof Error ? err.message : "Failed to stop agent");
    } finally {
      setActionInProgress(null);
    }
  };

  // Format timestamp for display
  const formatTimestamp = (isoString: string | null | undefined): string => {
    if (!isoString) return "";
    try {
      const date = new Date(isoString);
      return date.toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch {
      return "";
    }
  };

  // Format datetime for run history display
  const formatRunDateTime = (isoString: string): string => {
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

  // Get status badge styles - using theme-aware colors where possible
  const getStatusStyles = (
    status: string,
  ): { bg: string; text: string; dot: string } => {
    switch (status) {
      case "running":
        return {
          bg: "bg-brand-500/10 border-brand-500/20",
          text: "text-brand-400",
          dot: "bg-brand-500 animate-pulse",
        };
      case "completed":
        return {
          bg: "bg-emerald-500/10 border-emerald-500/20",
          text: "text-emerald-400",
          dot: "bg-emerald-500",
        };
      case "failed":
        return {
          bg: "bg-red-500/10 border-red-500/20",
          text: "text-red-400",
          dot: "bg-red-500",
        };
      case "stopped":
        return {
          bg: "bg-amber-500/10 border-amber-500/20",
          text: "text-amber-400",
          dot: "bg-amber-500",
        };
      default:
        return {
          bg: "bg-[var(--bg-surface-200)] border-[var(--border-default)] border",
          text: "text-[var(--text-muted)]",
          dot: "bg-gray-500",
        };
    }
  };

  if (loading) {
    return (
      <div
        className={cn(
          "flex items-center gap-3",
          compact
            ? ""
            : "p-4 bg-[var(--bg-surface-100)] border border-[var(--border-default)] rounded-2xl",
        )}
      >
        <div className="w-4 h-4 border-2 border-[var(--border-muted)] border-t-[var(--text-muted)] rounded-full animate-spin" />
        <span className="text-[10px] font-mono text-[var(--text-muted)] uppercase">
          Checking agent...
        </span>
      </div>
    );
  }

  if (error && !status) {
    return (
      <div
        className={cn(
          compact
            ? ""
            : "p-4 bg-[var(--bg-surface-100)] border border-[var(--border-default)] rounded-2xl",
        )}
      >
        <div className="flex items-center gap-2 text-red-400">
          <svg
            className="w-4 h-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span className="text-xs">{error}</span>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={fetchStatus}
          className="mt-2 text-[10px] font-bold text-[var(--text-muted)] hover:text-[var(--text-light)] h-auto p-0"
        >
          Retry
        </Button>
      </div>
    );
  }

  const isRunning = status?.running ?? false;

  // Compact mode - just a small status badge with action button
  if (compact) {
    return (
      <div className="flex items-center gap-3">
        {/* Status indicator */}
        <div className="flex items-center gap-2">
          <div
            className={cn(
              "w-2 h-2 rounded-full",
              isRunning
                ? "bg-brand-500 animate-pulse"
                : "bg-[var(--text-lighter)]",
            )}
          />
          <span
            className={cn(
              "text-[10px] font-bold uppercase",
              isRunning ? "text-brand-400" : "text-[var(--text-muted)]",
            )}
          >
            {isRunning ? "Running" : "Idle"}
          </span>
        </div>

        {/* Action button */}
        {isRunning ? (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleStopAgent}
            disabled={actionInProgress === "stop"}
            className="h-7 px-3 text-[10px] font-bold text-red-400 border border-red-500/20 hover:bg-red-500/10"
          >
            {actionInProgress === "stop" ? "Stopping..." : "Stop"}
          </Button>
        ) : (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleStartAgent}
            disabled={actionInProgress === "start"}
            className="h-7 px-3 text-[10px] font-bold text-brand-400 border border-brand-500/20 hover:bg-brand-500/10"
          >
            {actionInProgress === "start" ? "Starting..." : "Start"}
          </Button>
        )}
      </div>
    );
  }

  // Full mode - detailed card with status and controls
  return (
    <div className="bg-[var(--bg-surface-100)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 border-b border-[var(--border-default)] flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div
            className={cn(
              "w-10 h-10 rounded-xl flex items-center justify-center",
              isRunning ? "bg-brand-500/20" : "bg-[var(--bg-surface-200)]",
            )}
          >
            <IconFelix
              className={cn(
                "w-5 h-5",
                isRunning
                  ? "text-brand-400 animate-pulse"
                  : "text-[var(--text-muted)]",
              )}
            />
          </div>
          <div>
            <h3 className="text-sm font-bold text-[var(--text-light)]">
              Felix Agent
            </h3>
            <p className="text-[10px] font-mono theme-text-faint uppercase">
              {isRunning ? "Agent Active" : "Agent Idle"}
            </p>
          </div>
        </div>

        {/* Status badge */}
        <div
          className={`flex items-center gap-2 px-3 py-1.5 rounded-lg border ${
            isRunning
              ? "bg-brand-500/10 border-brand-500/20"
              : "theme-bg-surface"
          }`}
          style={{ borderColor: isRunning ? undefined : "var(--border-muted)" }}
        >
          <div
            className={`w-2 h-2 rounded-full ${
              isRunning
                ? "bg-brand-500 animate-pulse shadow-lg shadow-brand-500/50"
                : ""
            }`}
            style={{
              backgroundColor: isRunning ? undefined : "var(--text-faint)",
            }}
          />
          <span
            className={`text-[10px] font-bold uppercase ${
              isRunning ? "text-brand-400" : "theme-text-muted"
            }`}
          >
            {isRunning ? "Running" : "Stopped"}
          </span>
        </div>
      </div>

      {/* Body - Status details when running */}
      {isRunning && status && (
        <div className="px-6 py-4 border-b bg-[var(--bg-base)] border-[var(--border-default)]">
          <div className="grid grid-cols-2 gap-4">
            {status.pid && (
              <div>
                <span className="text-[9px] font-mono text-[var(--text-lighter)] uppercase">
                  Process ID
                </span>
                <p className="text-sm font-mono text-[var(--text-light)]">
                  {status.pid}
                </p>
              </div>
            )}
            {status.started_at && (
              <div>
                <span className="text-[9px] font-mono text-[var(--text-lighter)] uppercase">
                  Started
                </span>
                <p className="text-sm font-mono text-[var(--text-light)]">
                  {formatTimestamp(status.started_at)}
                </p>
              </div>
            )}
            {status.current_run_id && (
              <div className="col-span-2">
                <span className="text-[9px] font-mono text-[var(--text-lighter)] uppercase">
                  Run ID
                </span>
                <p className="text-xs font-mono text-[var(--text-lighter)] truncate">
                  {status.current_run_id}
                </p>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Error display */}
      {error && (
        <div className="px-6 py-3 bg-red-500/10 border-b border-red-500/20">
          <div className="flex items-center gap-2 text-red-400">
            <svg
              className="w-4 h-4 flex-shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span className="text-xs">{error}</span>
          </div>
        </div>
      )}

      {/* Footer - Actions */}
      <div className="px-6 py-4 flex items-center justify-between border-b border-[var(--border-default)]">
        <div className="flex flex-col gap-1 items-start">
          <Button
            variant="ghost"
            size="sm"
            onClick={fetchStatus}
            className="text-[10px] font-bold text-[var(--text-muted)] hover:text-[var(--text-light)] flex items-center gap-1.5 h-auto py-1 px-2 -ml-2"
          >
            <IconCpu className="w-3 h-3" />
            Refresh Status
          </Button>
          <span className="text-[8px] font-mono text-[var(--text-lighter)]">
            Status may be outdated
          </span>
        </div>

        {isRunning ? (
          <Button
            onClick={handleStopAgent}
            disabled={actionInProgress === "stop"}
            variant="outline"
            className="text-xs font-bold text-red-400 border-red-500/20 hover:bg-red-500/10 hover:text-red-400 flex items-center gap-2"
          >
            {actionInProgress === "stop" ? (
              <>
                <div className="w-3 h-3 border-2 border-red-400/30 border-t-red-400 rounded-full animate-spin" />
                Stopping...
              </>
            ) : (
              <>
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z"
                  />
                </svg>
                Stop Agent
              </>
            )}
          </Button>
        ) : (
          <Button
            onClick={handleStartAgent}
            disabled={actionInProgress === "start"}
            className="text-xs font-bold text-white bg-brand-600 hover:bg-brand-500 flex items-center gap-2 shadow-lg shadow-brand-900/30"
          >
            {actionInProgress === "start" ? (
              <>
                <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                Starting...
              </>
            ) : (
              <>
                <IconFelix className="w-4 h-4" />
                Start Agent
              </>
            )}
          </Button>
        )}
      </div>

      {/* Run History Section */}
      <div className="px-6 py-4">
        <button
          onClick={() => {
            setShowHistory(!showHistory);
            if (!showHistory && runs.length === 0) {
              fetchRunHistory();
            }
          }}
          className="w-full flex items-center justify-between text-left group"
        >
          <div className="flex items-center gap-2">
            <svg
              className={cn(
                "w-4 h-4 text-[var(--text-muted)] transition-transform duration-200",
                showHistory ? "rotate-90" : "",
              )}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M9 5l7 7-7 7"
              />
            </svg>
            <span className="text-xs font-bold text-[var(--text-lighter)] uppercase tracking-wider group-hover:text-[var(--text-light)] transition-colors">
              Run History
            </span>
            {runs.length > 0 && (
              <span className="text-[9px] font-mono text-[var(--text-lighter)] bg-[var(--bg-surface-200)] px-1.5 py-0.5 rounded">
                {runs.length}
              </span>
            )}
          </div>
          {runsLoading && (
            <div className="w-3 h-3 border-2 border-[var(--border-muted)] border-t-[var(--text-muted)] rounded-full animate-spin" />
          )}
        </button>

        {/* Expandable run history list */}
        {showHistory && (
          <div className="mt-4 space-y-2 max-h-64 overflow-y-auto custom-scrollbar">
            {runs.length === 0 ? (
              <div className="text-center py-6 text-[var(--text-lighter)]">
                <svg
                  className="w-8 h-8 mx-auto mb-2 opacity-50"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <p className="text-[10px] font-mono uppercase">No runs yet</p>
              </div>
            ) : (
              runs.map((run) => (
                <RunCard
                  key={run.run_id}
                  run={run}
                  onClick={(runId) => onSelectRun?.(runId)}
                />
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
};

export default AgentControls;

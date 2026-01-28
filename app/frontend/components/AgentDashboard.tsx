import React, { useState, useEffect, useCallback, useRef } from "react";
import {
  felixApi,
  AgentEntry,
  AgentRegistryResponse,
  RunHistoryEntry,
  Requirement,
  MergedAgent,
  AgentConfigEntry,
} from "../services/felixApi";
import { IconFelix, IconCpu, IconTerminal } from "./Icons";
import { marked } from "marked";
import Ansi from "ansi-to-react";
import RunArtifactViewer from "./RunArtifactViewer";
import RunCard from "./RunCard";

// --- Types ---

interface AgentDashboardProps {
  projectId: string;
}

interface SelectedAgent {
  name: string;
  agent: MergedAgent;
}

// --- Status Icon Component ---

const StatusIcon: React.FC<{ status: string }> = ({ status }) => {
  switch (status) {
    case "active":
      return <span title="Active">🟢</span>;
    case "stale":
      return <span title="Stale">🟡</span>;
    case "inactive":
      return <span title="Inactive">⚪</span>;
    case "stopped":
      return <span title="Stopped">🔴</span>;
    case "not-started":
      return <span title="Not Started">⚫</span>;
    default:
      return <span title="Unknown">⚪</span>;
  }
};

// --- Run Status Badge Component ---

const RunStatusBadge: React.FC<{ status: string }> = ({ status }) => {
  const styles = {
    running: {
      bg: "bg-felix-500/10",
      text: "text-felix-400",
      border: "border-felix-500/20",
      icon: "🔄",
    },
    completed: {
      bg: "bg-emerald-500/10",
      text: "text-emerald-400",
      border: "border-emerald-500/20",
      icon: "✅",
    },
    failed: {
      bg: "bg-red-500/10",
      text: "text-red-400",
      border: "border-red-500/20",
      icon: "❌",
    },
    blocked: {
      bg: "bg-amber-500/10",
      text: "text-amber-400",
      border: "border-amber-500/20",
      icon: "⚠️",
    },
    stopped: {
      bg: "bg-slate-500/10",
      text: "text-slate-400",
      border: "border-slate-500/20",
      icon: "⏹️",
    },
  };

  const style = styles[status as keyof typeof styles] || styles.stopped;

  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-lg border ${style.bg} ${style.border}`}
    >
      <span className="text-xs">{style.icon}</span>
      <span className={`text-[9px] font-bold uppercase ${style.text}`}>
        {status}
      </span>
    </span>
  );
};

// --- Toolbar Component ---

interface ToolbarProps {
  selectedAgent: SelectedAgent | null;
  requirements: Requirement[];
  onStart: (requirementId: string) => void;
  onStop: (mode: "graceful" | "force") => void;
  onRefresh: () => void;
  onSettings: () => void;
  actionInProgress: string | null;
}

const DashboardToolbar: React.FC<ToolbarProps> = ({
  selectedAgent,
  requirements,
  onStart,
  onStop,
  onRefresh,
  onSettings,
  actionInProgress,
}) => {
  const [showStartDropdown, setShowStartDropdown] = useState(false);
  const [showStopDropdown, setShowStopDropdown] = useState(false);
  const startDropdownRef = useRef<HTMLDivElement>(null);
  const stopDropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdowns on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        startDropdownRef.current &&
        !startDropdownRef.current.contains(e.target as Node)
      ) {
        setShowStartDropdown(false);
      }
      if (
        stopDropdownRef.current &&
        !stopDropdownRef.current.contains(e.target as Node)
      ) {
        setShowStopDropdown(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Calculate uptime
  const getUptime = () => {
    if (!selectedAgent?.agent.started_at) return null;
    try {
      const started = new Date(selectedAgent.agent.started_at);
      const now = new Date();
      const diff = now.getTime() - started.getTime();
      const hours = Math.floor(diff / (1000 * 60 * 60));
      const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
      if (hours > 0) return `${hours}h ${minutes}m`;
      return `${minutes}m`;
    } catch {
      return null;
    }
  };

  const availableRequirements = requirements.filter(
    (r) => r.status === "planned" || r.status === "blocked",
  );

  const isAgentActive = selectedAgent?.agent.status === "active";
  
  // Start button should be enabled for not-started and stopped agents (can be restarted)
  const canStartAgent = selectedAgent && (selectedAgent.agent.status === "not-started" || selectedAgent.agent.status === "stopped");
  const canStopAgent = selectedAgent && isAgentActive;

  return (
    <div
      className="h-14 border-b flex items-center justify-between px-6"
      style={{
        backgroundColor: "var(--bg-base)",
        borderColor: "var(--border-default)",
      }}
    >
      {/* Left section - Agent info */}
      <div className="flex items-center gap-6">
        {selectedAgent ? (
          <>
            <div className="flex items-center gap-3">
              <div
                className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                  isAgentActive ? "bg-felix-500/20" : ""
                }`}
                style={{
                  backgroundColor: isAgentActive
                    ? undefined
                    : "var(--bg-surface)",
                }}
              >
                <IconFelix
                  className={`w-5 h-5 ${isAgentActive ? "text-felix-400 animate-pulse" : ""}`}
                  style={{
                    color: isAgentActive ? undefined : "var(--text-muted)",
                  }}
                />
              </div>
              <div>
                <h3
                  className="text-sm font-bold"
                  style={{ color: "var(--text-secondary)" }}
                >
                  {selectedAgent.name}
                </h3>
                <p
                  className="text-[10px] font-mono"
                  style={{ color: "var(--text-muted)" }}
                >
                  {selectedAgent.agent.hostname || selectedAgent.agent.executable}
                </p>
              </div>
            </div>
            <div
              className="flex items-center gap-4 text-[10px] font-mono"
              style={{ color: "var(--text-faint)" }}
            >
              {selectedAgent.agent.pid && <span>PID: {selectedAgent.agent.pid}</span>}
              {getUptime() && <span>Uptime: {getUptime()}</span>}
              {selectedAgent.agent.current_run_id && (
                <span className="px-2 py-0.5 rounded bg-felix-500/10 text-felix-400 border border-felix-500/20">
                  {selectedAgent.agent.current_run_id}
                </span>
              )}
            </div>
          </>
        ) : (
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-xl flex items-center justify-center"
              style={{ backgroundColor: "var(--bg-surface)" }}
            >
              <IconFelix
                className="w-5 h-5"
                style={{ color: "var(--text-muted)" }}
              />
            </div>
            <div>
              <h3
                className="text-sm font-bold"
                style={{ color: "var(--text-tertiary)" }}
              >
                No Agent Selected
              </h3>
              <p
                className="text-[10px] font-mono"
                style={{ color: "var(--text-muted)" }}
              >
                Select an agent from the list
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Right section - Controls */}
      <div className="flex items-center gap-3">
        {/* Live indicator */}
        {selectedAgent?.agent.status === "active" && (
          <div className="flex items-center gap-2 mr-2">
            <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse shadow-lg shadow-emerald-500/50" />
            <span className="text-[10px] font-mono text-emerald-400 uppercase">
              Live
            </span>
          </div>
        )}

        {/* Start button with dropdown */}
        <div className="relative" ref={startDropdownRef}>
          <button
            onClick={() => setShowStartDropdown(!showStartDropdown)}
            disabled={
              !canStartAgent || actionInProgress !== null
            }
            className="px-4 py-2 text-xs font-bold text-white bg-felix-600 hover:bg-felix-500 rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            {actionInProgress === "start" ? (
              <>
                <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                Starting...
              </>
            ) : (
              <>
                <span>▶️</span>
                Start
              </>
            )}
          </button>
          {showStartDropdown && availableRequirements.length > 0 && (
            <div
              className="absolute right-0 top-full mt-2 w-64 rounded-xl border shadow-xl z-50 overflow-hidden"
              style={{
                backgroundColor: "var(--bg-elevated)",
                borderColor: "var(--border-default)",
              }}
            >
              <div
                className="px-3 py-2 border-b"
                style={{ borderColor: "var(--border-default)" }}
              >
                <span
                  className="text-[10px] font-bold uppercase"
                  style={{ color: "var(--text-muted)" }}
                >
                  Select Requirement
                </span>
              </div>
              <div className="max-h-48 overflow-y-auto custom-scrollbar">
                {availableRequirements.map((req) => (
                  <button
                    key={req.id}
                    onClick={() => {
                      onStart(req.id);
                      setShowStartDropdown(false);
                    }}
                    className="w-full px-3 py-2 text-left hover:bg-felix-500/10 transition-colors flex items-center justify-between"
                  >
                    <div>
                      <span className="text-xs font-mono text-felix-400">
                        {req.id}
                      </span>
                      <p
                        className="text-[10px] truncate"
                        style={{ color: "var(--text-muted)" }}
                      >
                        {req.title}
                      </p>
                    </div>
                    <span
                      className={`text-[8px] font-bold uppercase px-1.5 py-0.5 rounded ${
                        req.status === "blocked"
                          ? "bg-red-500/10 text-red-400"
                          : "bg-blue-500/10 text-blue-400"
                      }`}
                    >
                      {req.status}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Stop button with dropdown */}
        <div className="relative" ref={stopDropdownRef}>
          <button
            onClick={() => setShowStopDropdown(!showStopDropdown)}
            disabled={
              !canStopAgent || actionInProgress !== null
            }
            className="px-4 py-2 text-xs font-bold text-red-400 border border-red-500/20 rounded-xl hover:bg-red-500/10 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            {actionInProgress === "stop" ? (
              <>
                <div className="w-3 h-3 border-2 border-red-400/30 border-t-red-400 rounded-full animate-spin" />
                Stopping...
              </>
            ) : (
              <>
                <span>⏹️</span>
                Stop
              </>
            )}
          </button>
          {showStopDropdown && (
            <div
              className="absolute right-0 top-full mt-2 w-48 rounded-xl border shadow-xl z-50 overflow-hidden"
              style={{
                backgroundColor: "var(--bg-elevated)",
                borderColor: "var(--border-default)",
              }}
            >
              <button
                onClick={() => {
                  onStop("graceful");
                  setShowStopDropdown(false);
                }}
                className="w-full px-4 py-3 text-left text-xs hover:bg-amber-500/10 transition-colors flex items-center gap-2"
              >
                <span>🛑</span>
                <div>
                  <span className="font-bold text-amber-400">
                    Graceful Stop
                  </span>
                  <p
                    className="text-[9px]"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Wait for current task
                  </p>
                </div>
              </button>
              <button
                onClick={() => {
                  onStop("force");
                  setShowStopDropdown(false);
                }}
                className="w-full px-4 py-3 text-left text-xs hover:bg-red-500/10 transition-colors flex items-center gap-2 border-t"
                style={{ borderColor: "var(--border-default)" }}
              >
                <span>⚡</span>
                <div>
                  <span className="font-bold text-red-400">Force Kill</span>
                  <p
                    className="text-[9px]"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Terminate immediately
                  </p>
                </div>
              </button>
            </div>
          )}
        </div>

        {/* Settings button */}
        <button
          onClick={onSettings}
          className="p-2 rounded-xl border transition-all hover:border-felix-500/30"
          style={{
            borderColor: "var(--border-default)",
            color: "var(--text-muted)",
          }}
          title="Settings"
        >
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
              d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
            />
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
            />
          </svg>
        </button>

        {/* Refresh button */}
        <button
          onClick={onRefresh}
          className="p-2 rounded-xl border transition-all hover:border-felix-500/30"
          style={{
            borderColor: "var(--border-default)",
            color: "var(--text-muted)",
          }}
          title="Refresh"
        >
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
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
        </button>
      </div>
    </div>
  );
};

// --- Agent List Panel ---

interface AgentListPanelProps {
  agents: MergedAgent[];
  selectedAgent: SelectedAgent | null;
  onSelectAgent: (agent: SelectedAgent) => void;
  loading: boolean;
}

const AgentListPanel: React.FC<AgentListPanelProps> = ({
  agents,
  selectedAgent,
  onSelectAgent,
  loading,
}) => {
  // Group agents by status per S-0021 spec
  const availableAgents = agents.filter((a) => a.status === "not-started");
  const activeAgents = agents.filter((a) => a.status === "active" || a.status === "stale");
  const inactiveAgents = agents.filter((a) => a.status === "inactive" || a.status === "stopped");

  // Format relative time
  const formatRelativeTime = (isoString: string | null | undefined) => {
    if (!isoString) return null;
    try {
      const date = new Date(isoString);
      const now = new Date();
      const diff = Math.floor((now.getTime() - date.getTime()) / 1000);
      if (diff < 60) return `${diff}s ago`;
      if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
      return `${Math.floor(diff / 3600)}h ago`;
    } catch {
      return null;
    }
  };

  const renderAgentCard = (agent: MergedAgent) => {
    const isSelected = selectedAgent?.name === agent.name;
    const relativeTime = formatRelativeTime(agent.last_heartbeat);

    return (
      <button
        key={agent.name}
        onClick={() => onSelectAgent({ name: agent.name, agent })}
        className={`w-full p-3 rounded-xl text-left transition-all border ${
          isSelected
            ? "border-felix-500/50 bg-felix-500/10"
            : "hover:border-felix-500/20"
        }`}
        style={{
          backgroundColor: isSelected ? undefined : "var(--bg-base)",
          borderColor: isSelected ? undefined : "var(--border-default)",
        }}
      >
        <div className="flex items-start gap-3">
          <StatusIcon status={agent.status} />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span
                className="font-bold text-sm truncate"
                style={{ color: "var(--text-secondary)" }}
              >
                {agent.name}
              </span>
              {agent.current_run_id && (
                <span className="px-1.5 py-0.5 text-[9px] font-mono rounded bg-felix-500/10 text-felix-400 border border-felix-500/20">
                  {agent.current_run_id}
                </span>
              )}
            </div>
            <div
              className="flex items-center gap-2 text-[10px]"
              style={{ color: "var(--text-muted)" }}
            >
              {agent.status === "not-started" ? (
                // For not-started agents, show executable + args preview
                <span className="truncate font-mono">
                  {agent.executable} {agent.args.slice(0, 2).join(" ")}...
                </span>
              ) : (
                // For running/stopped agents, show hostname
                <span className="truncate">{agent.hostname || agent.executable}</span>
              )}
              {(agent.status === "active" || agent.status === "stale") && relativeTime && (
                <>
                  <span>•</span>
                  <span>{relativeTime}</span>
                </>
              )}
            </div>
            {/* Status text for not-started agents */}
            {agent.status === "not-started" && (
              <p className="text-[9px] mt-1" style={{ color: "var(--text-faint)" }}>
                Ready to start
              </p>
            )}
            {/* Last active timestamp for stopped agents */}
            {agent.status === "stopped" && agent.stopped_at && (
              <p className="text-[9px] mt-1" style={{ color: "var(--text-faint)" }}>
                Stopped {formatRelativeTime(agent.stopped_at)}
              </p>
            )}
          </div>
        </div>
      </button>
    );
  };

  if (loading) {
    return (
      <div
        className="h-full flex flex-col"
        style={{ backgroundColor: "var(--bg-deep)" }}
      >
        <div
          className="p-4 border-b"
          style={{ borderColor: "var(--border-default)" }}
        >
          <h2
            className="text-xs font-bold uppercase tracking-wider"
            style={{ color: "var(--text-tertiary)" }}
          >
            Agents
          </h2>
        </div>
        <div className="flex-1 flex items-center justify-center">
          <div
            className="w-6 h-6 border-2 rounded-full animate-spin"
            style={{
              borderColor: "var(--border-muted)",
              borderTopColor: "var(--text-muted)",
            }}
          />
        </div>
      </div>
    );
  }

  if (agents.length === 0) {
    return (
      <div
        className="h-full flex flex-col"
        style={{ backgroundColor: "var(--bg-deep)" }}
      >
        <div
          className="p-4 border-b"
          style={{ borderColor: "var(--border-default)" }}
        >
          <h2
            className="text-xs font-bold uppercase tracking-wider"
            style={{ color: "var(--text-tertiary)" }}
          >
            Agents
          </h2>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center p-4 text-center">
          <div
            className="w-12 h-12 rounded-xl flex items-center justify-center mb-3"
            style={{ backgroundColor: "var(--bg-surface)" }}
          >
            <IconCpu
              className="w-6 h-6"
              style={{ color: "var(--text-faint)" }}
            />
          </div>
          <p
            className="text-xs font-bold mb-1"
            style={{ color: "var(--text-tertiary)" }}
          >
            No agents configured
          </p>
          <p className="text-[10px]" style={{ color: "var(--text-muted)" }}>
            Configure agents in Settings
          </p>
        </div>
      </div>
    );
  }

  return (
    <div
      className="h-full flex flex-col"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      <div
        className="px-6 py-4 border-b"
        style={{ borderColor: "var(--border-default)" }}
      >
        <h2
          className="text-xs font-bold uppercase tracking-wider"
          style={{ color: "var(--text-tertiary)" }}
        >
          Agents
        </h2>
      </div>
      <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4 space-y-3">
        {/* Available Agents (not-started) */}
        {availableAgents.length > 0 && (
          <div>
            <div className="flex items-center gap-2 mb-2 px-1">
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: "#6b7280" }}
              />
              <span
                className="text-[10px] font-bold uppercase"
                style={{ color: "var(--text-muted)" }}
              >
                Available ({availableAgents.length})
              </span>
            </div>
            <div className="space-y-2">{availableAgents.map(renderAgentCard)}</div>
          </div>
        )}

        {/* Active Agents */}
        {activeAgents.length > 0 && (
          <div>
            <div className="flex items-center gap-2 mb-2 px-1">
              <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
              <span
                className="text-[10px] font-bold uppercase"
                style={{ color: "var(--text-muted)" }}
              >
                Active ({activeAgents.length})
              </span>
            </div>
            <div className="space-y-2">{activeAgents.map(renderAgentCard)}</div>
          </div>
        )}

        {/* Inactive Agents */}
        {inactiveAgents.length > 0 && (
          <div>
            <div className="flex items-center gap-2 mb-2 px-1">
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: "var(--text-faint)" }}
              />
              <span
                className="text-[10px] font-bold uppercase"
                style={{ color: "var(--text-muted)" }}
              >
                Inactive ({inactiveAgents.length})
              </span>
            </div>
            <div className="space-y-2">
              {inactiveAgents.map(renderAgentCard)}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

// --- Live Console Panel ---

interface LiveConsolePanelProps {
  selectedAgent: SelectedAgent | null;
  projectId: string;
}

const LiveConsolePanel: React.FC<LiveConsolePanelProps> = ({
  selectedAgent,
  projectId,
}) => {
  const [consoleOutput, setConsoleOutput] = useState<string>("");
  const [scrollLocked, setScrollLocked] = useState(false);
  const [loading, setLoading] = useState(false);
  const consoleRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new content arrives
  useEffect(() => {
    if (!scrollLocked && consoleRef.current) {
      consoleRef.current.scrollTop = consoleRef.current.scrollHeight;
    }
  }, [consoleOutput, scrollLocked]);

  // Poll for console output when agent is active
  useEffect(() => {
    if (!selectedAgent || selectedAgent.agent.status !== "active") {
      return;
    }

    let isMounted = true;

    const fetchConsoleOutput = async () => {
      // For now, we'll show a placeholder. Full implementation would require:
      // 1. Backend WebSocket endpoint for console streaming
      // 2. Or polling the current run's output.log

      // Get the current run's output if available
      if (selectedAgent.agent.current_run_id) {
        try {
          // Try to fetch the output.log for the current run
          // This is a placeholder - the actual implementation would tail the file
          const runId = selectedAgent.agent.current_run_id;
          // Note: This would require a new API endpoint to get run output in real-time
        } catch (err) {
          console.error("Failed to fetch console output:", err);
        }
      }
    };

    const interval = setInterval(fetchConsoleOutput, 1000);
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, [selectedAgent, projectId]);

  const handleClear = () => {
    setConsoleOutput("");
  };

  // Empty state - no agent selected
  if (!selectedAgent) {
    return (
      <div
        className="h-full flex flex-col"
        style={{ backgroundColor: "var(--bg-base)" }}
      >
        <div
          className="px-6 py-4 border-b flex items-center justify-between"
          style={{
            borderColor: "var(--border-default)",
          }}
        >
          <div className="flex items-center gap-2">
            <IconTerminal
              className="w-4 h-4"
              style={{ color: "var(--text-muted)" }}
            />
            <span
              className="text-xs font-bold"
              style={{ color: "var(--text-tertiary)" }}
            >
              Live Console
            </span>
          </div>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center p-4 text-center">
          <IconTerminal
            className="w-12 h-12 mb-3"
            style={{ color: "var(--text-faint)" }}
          />
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>
            Select an agent to view console output
          </p>
        </div>
      </div>
    );
  }

  // Empty state - agent idle (not-started, stopped, inactive, or stale)
  if (selectedAgent.agent.status !== "active") {
    // Determine appropriate message based on status
    const getStatusMessage = () => {
      switch (selectedAgent.agent.status) {
        case "not-started":
          return { primary: "Agent not running", secondary: "Start the agent to see output" };
        case "stopped":
          return { primary: "Agent stopped", secondary: "Restart the agent to see output" };
        default:
          return { primary: "Agent idle - waiting for work", secondary: "Start a run to see live output" };
      }
    };
    const message = getStatusMessage();
    
    return (
      <div
        className="h-full flex flex-col"
        style={{ backgroundColor: "var(--bg-base)" }}
      >
        <div
          className="px-6 py-4 border-b flex items-center justify-between"
          style={{
            borderColor: "var(--border-default)",
          }}
        >
          <div className="flex items-center gap-3">
            <IconTerminal
              className="w-4 h-4"
              style={{ color: "var(--text-muted)" }}
            />
            <span
              className="text-xs font-bold"
              style={{ color: "var(--text-secondary)" }}
            >
              {selectedAgent.name}
            </span>
            <span
              className="text-[10px] px-2 py-0.5 rounded"
              style={{
                backgroundColor: "var(--bg-surface)",
                color: "var(--text-muted)",
              }}
            >
              {selectedAgent.agent.status}
            </span>
          </div>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center p-4 text-center">
          <div
            className="w-12 h-12 rounded-xl flex items-center justify-center mb-3"
            style={{ backgroundColor: "var(--bg-surface)" }}
          >
            <IconFelix
              className="w-6 h-6"
              style={{ color: "var(--text-faint)" }}
            />
          </div>
          <p className="text-xs mb-1" style={{ color: "var(--text-muted)" }}>
            {message.primary}
          </p>
          <p className="text-[10px]" style={{ color: "var(--text-faint)" }}>
            {message.secondary}
          </p>
        </div>
      </div>
    );
  }

  // Active console view
  return (
    <div
      className="h-full flex flex-col"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      {/* Header */}
      <div
        className="px-6 py-4 border-b flex items-center justify-between"
        style={{
          borderColor: "var(--border-default)",
        }}
      >
        <div className="flex items-center gap-3">
          <IconTerminal className="w-4 h-4 text-felix-400" />
          <span
            className="text-xs font-bold"
            style={{ color: "var(--text-secondary)" }}
          >
            {selectedAgent.name}
          </span>
          {selectedAgent.agent.current_run_id && (
            <span className="text-[10px] px-2 py-0.5 rounded bg-felix-500/10 text-felix-400 border border-felix-500/20">
              {selectedAgent.agent.current_run_id}
            </span>
          )}
          <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setScrollLocked(!scrollLocked)}
            className={`p-1.5 rounded transition-colors ${scrollLocked ? "bg-felix-500/10 text-felix-400" : ""}`}
            style={{ color: scrollLocked ? undefined : "var(--text-muted)" }}
            title={scrollLocked ? "Unlock scroll" : "Lock scroll"}
          >
            <span>📌</span>
          </button>
          <button
            onClick={handleClear}
            className="p-1.5 rounded transition-colors"
            style={{ color: "var(--text-muted)" }}
            title="Clear console"
          >
            <span>🗑️</span>
          </button>
        </div>
      </div>

      {/* Console output */}
      <div
        ref={consoleRef}
        className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4 font-mono text-xs leading-relaxed ansi-console"
        style={{
          backgroundColor: "var(--bg-base)",
          color: "var(--text-secondary)",
        }}
      >
        {consoleOutput ? (
          <pre className="whitespace-pre-wrap">
            <Ansi useClasses>{consoleOutput}</Ansi>
          </pre>
        ) : (
          <div
            className="flex items-center gap-2"
            style={{ color: "var(--text-muted)" }}
          >
            <div className="w-2 h-2 rounded-full bg-felix-500 animate-pulse" />
            <span>Waiting for output...</span>
          </div>
        )}
      </div>
    </div>
  );
};

// --- Run History Panel ---

interface RunHistoryPanelProps {
  projectId: string;
  onSelectRun: (runId: string) => void;
}

const RunHistoryPanel: React.FC<RunHistoryPanelProps> = ({
  projectId,
  onSelectRun,
}) => {
  const [runs, setRuns] = useState<RunHistoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string[]>([]);
  const [showFilters, setShowFilters] = useState(false);

  // Fetch runs
  const fetchRuns = useCallback(async () => {
    try {
      const response = await felixApi.listRuns(projectId);
      setRuns(response.runs);
    } catch (err) {
      console.error("Failed to fetch runs:", err);
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => {
    fetchRuns();
    const interval = setInterval(fetchRuns, 5000);
    return () => clearInterval(interval);
  }, [fetchRuns]);

  // Filter runs
  const filteredRuns = runs.filter((run) => {
    if (
      searchQuery &&
      !run.run_id.toLowerCase().includes(searchQuery.toLowerCase())
    ) {
      return false;
    }
    if (statusFilter.length > 0 && !statusFilter.includes(run.status)) {
      return false;
    }
    return true;
  });

  // Format timestamp
  const formatRelativeTime = (isoString: string) => {
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

  return (
    <div
      className="h-full flex flex-col"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      {/* Header */}
      <div
        className="px-6 py-4 border-b"
        style={{ borderColor: "var(--border-default)" }}
      >
        <div className="flex items-center justify-between mb-3">
          <h2
            className="text-xs font-bold uppercase tracking-wider"
            style={{ color: "var(--text-tertiary)" }}
          >
            Run History
          </h2>
          <button
            onClick={() => setShowFilters(!showFilters)}
            className={`p-1 rounded transition-colors ${showFilters ? "bg-felix-500/10 text-felix-400" : ""}`}
            style={{ color: showFilters ? undefined : "var(--text-muted)" }}
          >
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
                d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"
              />
            </svg>
          </button>
        </div>

        {/* Search */}
        <div className="relative">
          <input
            type="text"
            placeholder="Search runs..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full px-3 py-2 pl-8 rounded-lg text-xs border outline-none focus:border-felix-500/50"
            style={{
              backgroundColor: "var(--bg-base)",
              borderColor: "var(--border-default)",
              color: "var(--text-secondary)",
            }}
          />
          <svg
            className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5"
            style={{ color: "var(--text-muted)" }}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>

        {/* Filters */}
        {showFilters && (
          <div
            className="mt-3 p-3 rounded-lg border"
            style={{
              backgroundColor: "var(--bg-base)",
              borderColor: "var(--border-default)",
            }}
          >
            <span
              className="text-[10px] font-bold uppercase"
              style={{ color: "var(--text-muted)" }}
            >
              Status
            </span>
            <div className="flex flex-wrap gap-2 mt-2">
              {["running", "completed", "failed", "blocked", "stopped"].map(
                (status) => (
                  <button
                    key={status}
                    onClick={() => {
                      setStatusFilter((prev) =>
                        prev.includes(status)
                          ? prev.filter((s) => s !== status)
                          : [...prev, status],
                      );
                    }}
                    className={`px-2 py-1 text-[10px] rounded-lg border transition-colors ${
                      statusFilter.includes(status)
                        ? "bg-felix-500/10 border-felix-500/30 text-felix-400"
                        : ""
                    }`}
                    style={{
                      borderColor: statusFilter.includes(status)
                        ? undefined
                        : "var(--border-default)",
                      color: statusFilter.includes(status)
                        ? undefined
                        : "var(--text-muted)",
                    }}
                  >
                    {status}
                  </button>
                ),
              )}
            </div>
          </div>
        )}
      </div>

      {/* Run list */}
      <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4 space-y-2">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <div
              className="w-6 h-6 border-2 rounded-full animate-spin"
              style={{
                borderColor: "var(--border-muted)",
                borderTopColor: "var(--text-muted)",
              }}
            />
          </div>
        ) : filteredRuns.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <svg
              className="w-8 h-8 mb-2"
              style={{ color: "var(--text-faint)" }}
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
            <p
              className="text-[10px] font-mono uppercase"
              style={{ color: "var(--text-muted)" }}
            >
              {searchQuery || statusFilter.length > 0
                ? "No matching runs"
                : "No runs yet"}
            </p>
          </div>
        ) : (
          filteredRuns.map((run) => (
            <RunCard key={run.run_id} run={run} onClick={onSelectRun} />
          ))
        )}
      </div>
    </div>
  );
};

// --- Run Detail Slide-Out ---

interface RunDetailSlideOutProps {
  projectId: string;
  runId: string | null;
  onClose: () => void;
}

const RunDetailSlideOut: React.FC<RunDetailSlideOutProps> = ({
  projectId,
  runId,
  onClose,
}) => {
  // Handle ESC key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  const isOpen = !!runId;

  return (
    <>
      {/* Backdrop */}
      <div
        className={`fixed inset-0 bg-black/50 z-40 transition-opacity duration-300 ${
          runId ? "opacity-100" : "opacity-0 pointer-events-none"
        }`}
        onClick={onClose}
      />

      {/* Slide-out panel */}
      <div
        className={`fixed right-0 top-0 bottom-8 w-[60vw] min-w-[500px] max-w-[800px] z-50 flex flex-col border-l shadow-2xl transition-transform duration-300 ease-out ${
          runId ? "translate-x-0" : "translate-x-full"
        }`}
        style={{
          backgroundColor: "var(--bg-base)",
          borderColor: "var(--border-default)",
        }}
      >
        {runId && (
          <RunArtifactViewer
            projectId={projectId}
            runId={runId}
            onClose={onClose}
          />
        )}
      </div>
    </>
  );
};

// --- Main Dashboard Component ---

const AgentDashboard: React.FC<AgentDashboardProps> = ({ projectId }) => {
  const [agents, setAgents] = useState<MergedAgent[]>([]);
  const [selectedAgent, setSelectedAgent] = useState<SelectedAgent | null>(
    null,
  );
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Fetch agents - merges configured agents with runtime status
  const fetchAgents = useCallback(async () => {
    try {
      // Load both configured agents and runtime agents in parallel
      const [configResponse, runtimeResponse] = await Promise.all([
        felixApi.getAgentsConfig().catch(() => ({ agents: [] })), // Graceful fallback
        felixApi.getAgents(),
      ]);

      const configuredAgents = configResponse.agents || [];
      const runtimeAgents = runtimeResponse.agents || {};

      // Merge: configured agents are source of truth, overlay with runtime status
      const mergedAgents: MergedAgent[] = configuredAgents.map((config) => {
        const runtime = runtimeAgents[config.name];

        if (!runtime) {
          // No runtime entry - agent has never been started
          return {
            ...config,
            status: "not-started" as const,
          };
        }

        // Has runtime entry - merge config with runtime data
        return {
          ...config,
          status: runtime.status,
          pid: runtime.pid,
          hostname: runtime.hostname,
          current_run_id: runtime.current_run_id,
          last_heartbeat: runtime.last_heartbeat,
          started_at: runtime.started_at,
          stopped_at: runtime.stopped_at,
        };
      });

      setAgents(mergedAgents);
      setError(null);

      // Auto-select first active agent if none selected
      if (!selectedAgent) {
        const activeAgents = mergedAgents.filter(
          (a) => a.status === "active",
        );
        if (activeAgents.length > 0) {
          setSelectedAgent({
            name: activeAgents[0].name,
            agent: activeAgents[0],
          });
        }
      } else {
        // Update selected agent data
        const updatedAgent = mergedAgents.find(
          (a) => a.name === selectedAgent.name,
        );
        if (updatedAgent) {
          setSelectedAgent({
            name: updatedAgent.name,
            agent: updatedAgent,
          });
        }
      }
    } catch (err) {
      console.error("Failed to fetch agents:", err);
      setError(err instanceof Error ? err.message : "Failed to fetch agents");
    } finally {
      setLoading(false);
    }
  }, [selectedAgent]);

  // Fetch requirements
  const fetchRequirements = useCallback(async () => {
    try {
      const response = await felixApi.getRequirements(projectId);
      setRequirements(response.requirements);
    } catch (err) {
      console.error("Failed to fetch requirements:", err);
    }
  }, [projectId]);

  // Initial fetch and polling
  useEffect(() => {
    fetchAgents();
    fetchRequirements();

    const agentInterval = setInterval(fetchAgents, 2000);
    const reqInterval = setInterval(fetchRequirements, 10000);

    return () => {
      clearInterval(agentInterval);
      clearInterval(reqInterval);
    };
  }, [fetchAgents, fetchRequirements]);

  // Handle start agent
  const handleStart = async (requirementId: string) => {
    if (!selectedAgent) return;
    setActionInProgress("start");
    try {
      // Start the agent with the specified requirement
      await felixApi.startAgentWithRequirement(
        selectedAgent.name,
        requirementId,
      );
      await fetchAgents();
    } catch (err) {
      console.error("Failed to start agent:", err);
      setError(err instanceof Error ? err.message : "Failed to start agent");
    } finally {
      setActionInProgress(null);
    }
  };

  // Handle stop agent
  const handleStop = async (mode: "graceful" | "force") => {
    if (!selectedAgent) return;
    setActionInProgress("stop");
    try {
      // Stop the agent with the specified mode
      await felixApi.stopAgent(selectedAgent.name, mode);
      await fetchAgents();
    } catch (err) {
      console.error("Failed to stop agent:", err);
      setError(err instanceof Error ? err.message : "Failed to stop agent");
    } finally {
      setActionInProgress(null);
    }
  };

  // Handle refresh
  const handleRefresh = () => {
    fetchAgents();
    fetchRequirements();
  };

  // Handle settings (placeholder)
  const handleSettings = () => {
    // This would navigate to settings or open a settings modal
    console.log("Open settings");
  };

  return (
    <div
      className="h-full flex flex-col"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      {/* Error banner */}
      {error && (
        <div className="px-6 py-2 bg-red-500/10 border-b border-red-500/20 flex items-center justify-between">
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
          <button
            onClick={fetchAgents}
            className="text-[10px] font-bold text-red-400 hover:text-red-300"
          >
            Retry
          </button>
        </div>
      )}

      {/* Toolbar */}
      <DashboardToolbar
        selectedAgent={selectedAgent}
        requirements={requirements}
        onStart={handleStart}
        onStop={handleStop}
        onRefresh={handleRefresh}
        onSettings={handleSettings}
        actionInProgress={actionInProgress}
      />

      {/* Three-Column Layout */}
      <div className="flex-1 flex">
        {/* Agent List Panel - Left Sidebar */}
        <div
          className="w-80 flex-shrink-0 border-r"
          style={{ borderColor: "var(--border-default)" }}
        >
          <AgentListPanel
            agents={agents}
            selectedAgent={selectedAgent}
            onSelectAgent={setSelectedAgent}
            loading={loading}
          />
        </div>

        {/* Middle and Right Panels - Split View */}
        <div className="flex-1 flex">
          {/* Live Console Panel - Takes more space */}
          <div
            className="flex-1 border-r"
            style={{ borderColor: "var(--border-default)" }}
          >
            <LiveConsolePanel
              selectedAgent={selectedAgent}
              projectId={projectId}
            />
          </div>

          {/* Run History Panel - Right Side */}
          <div className="w-96 flex-shrink-0">
            <RunHistoryPanel
              projectId={projectId}
              onSelectRun={setSelectedRunId}
            />
          </div>
        </div>
      </div>

      {/* Run Detail Slide-Out */}
      <RunDetailSlideOut
        projectId={projectId}
        runId={selectedRunId}
        onClose={() => setSelectedRunId(null)}
      />
    </div>
  );
};

export default AgentDashboard;

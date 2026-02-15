import React, { useState, useEffect, useCallback, useRef } from "react";
import { felixApi, Requirement, MergedAgent } from "../services/felixApi";
import { listRuns as apiListRuns } from "../src/api/client";
import type { Run } from "../src/api/types";
import { PageLoading } from "./ui/page-loading";
import {
  Bot as IconFelix,
  AlertCircle,
  Cpu as IconCpu,
  Terminal as IconTerminal,
  Play as IconPlay,
  Square as IconStop,
  Lock as IconLock,
  Trash2 as IconTrash,
  Filter,
  Search,
  Clock,
  Workflow as IconWorkflow,
  Loader2 as IconLoader,
  CheckCircle as IconCheckCircle,
  XCircle as IconXCircle,
  AlertTriangle as IconAlertTriangle,
  StopCircle as IconStopCircle,
} from "lucide-react";
import Ansi from "ansi-to-react";
import RunArtifactViewer from "./RunArtifactViewer";
import { cn } from "../lib/utils";
import {
  getRequirementStatusBadgeClass,
  getRunStatusVariant,
} from "../lib/status";
import WorkflowVisualization from "./WorkflowVisualization";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Badge } from "./ui/badge";
import { Card } from "./ui/card";
import { EmptyState } from "./ui/empty-state";
import DataTable from "./DataTable";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "./ui/dialog";

// --- Constants ---
const POLLING_INTERVAL_MS = 3000; // 3-second polling interval

// --- Types ---

interface AgentDashboardProps {
  projectId: string;
}

interface SelectedAgent {
  id: string;
  agent: MergedAgent;
}

type AgentStatus = MergedAgent["status"];

// --- Status Icon Component Removed (Integrated into Badge/Dot) ---

// --- Run Status Badge Component ---

const RunStatusBadge: React.FC<{ status: string }> = ({ status }) => {
  const styles: Record<
    string,
    {
      variant: "success" | "destructive" | "warning" | "default";
      Icon: React.ComponentType<{ className?: string }>;
    }
  > = {
    running: { variant: "success" as const, Icon: IconLoader },
    completed: { variant: "success" as const, Icon: IconCheckCircle },
    failed: { variant: "destructive" as const, Icon: IconXCircle },
    blocked: { variant: "warning" as const, Icon: IconAlertTriangle },
    stopped: { variant: "default" as const, Icon: IconStopCircle },
  };

  const style = styles[status] || styles.stopped;
  const Icon = style.Icon;

  return (
    <Badge variant={style.variant} className="gap-1 px-2 py-0.5">
      <Icon className={cn("w-3 h-3", status === "running" && "animate-spin")} />
      <span className="text-[9px] font-bold uppercase">{status}</span>
    </Badge>
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
  const activeAgents = agents.filter(
    (a) => a.status === "active" || a.status === "stale",
  );
  const inactiveAgents = agents.filter(
    (a) => a.status === "inactive" || a.status === "stopped",
  );

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
    const isSelected = selectedAgent?.id === agent.id;
    const relativeTime = formatRelativeTime(agent.last_heartbeat);

    const statusColor =
      {
        active: "bg-[var(--brand-500)] shadow-[0_0_8px_-2px_var(--brand-500)]",
        stale: "bg-[var(--warning-500)]",
        stopped: "bg-[var(--destructive-500)]",
        "not-started": "bg-[var(--border-muted)]",
        inactive: "bg-[var(--text-muted)]",
      }[agent.status] || "bg-[var(--text-muted)]";

    return (
      <Card
        key={agent.id}
        onClick={() => onSelectAgent({ id: agent.id, agent })}
        className={cn(
          "w-full p-3 rounded-xl text-left transition-all cursor-pointer border",
          isSelected
            ? "border-[var(--brand-500)]/50 bg-[var(--brand-500)]/5"
            : "bg-[var(--bg-base)] border-[var(--border-default)] hover:border-[var(--brand-500)]/20 hover:bg-[var(--bg-surface)]",
        )}
      >
        <div className="flex items-start gap-3">
          <div
            className={cn(
              "w-2.5 h-2.5 rounded-full mt-1.5 flex-shrink-0 transition-colors",
              statusColor,
            )}
            title={agent.status}
          />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span className="font-bold text-sm truncate theme-text-secondary">
                {agent.name}
              </span>
              {agent.current_run_id && (
                <span className="px-1.5 py-0.5 text-[9px] font-mono rounded bg-[var(--brand-500)]/10 text-[var(--brand-400)] border border-[var(--brand-500)]/20">
                  {agent.current_run_id}
                </span>
              )}
            </div>
            <div className="flex items-center gap-2 text-[10px] theme-text-muted">
              {agent.status === "not-started" ? (
                // For not-started agents, show executable + args preview
                <span className="truncate font-mono">
                  {agent.executable} {agent.args.slice(0, 2).join(" ")}...
                </span>
              ) : (
                // For running/stopped agents, show hostname
                <span className="truncate">
                  {agent.hostname || agent.executable}
                </span>
              )}
              {(agent.status === "active" || agent.status === "stale") &&
                relativeTime && (
                  <>
                    <span>•</span>
                    <span>{relativeTime}</span>
                  </>
                )}
            </div>
            {/* Status text for not-started agents */}
            {agent.status === "not-started" && (
              <p className="text-[9px] mt-1 theme-text-faint">Ready to start</p>
            )}
            {/* Last active timestamp for stopped agents */}
            {agent.status === "stopped" && agent.stopped_at && (
              <p className="text-[9px] mt-1 theme-text-faint">
                Stopped {formatRelativeTime(agent.stopped_at)}
              </p>
            )}
          </div>
        </div>
      </Card>
    );
  };

  if (loading) {
    return (
      <div className="h-full flex flex-col bg-[var(--bg-200)]">
        <div className="p-4 border-b border-[var(--border-default)]">
          <h2 className="text-xs font-bold uppercase tracking-wider theme-text-tertiary">
            Agents
          </h2>
        </div>
        <div className="flex-1">
          <PageLoading size="md" showText={false} />
        </div>
      </div>
    );
  }

  if (agents.length === 0) {
    return (
      <div className="h-full flex flex-col bg-[var(--bg-200)]">
        <div className="p-4 border-b border-[var(--border)]">
          <h2 className="text-xs font-bold uppercase tracking-wider text-[var(--text-lighter)]">
            Agents
          </h2>
        </div>
        <EmptyState
          title="No agents configured"
          description="Configure agents in Settings"
          icon={<IconCpu className="w-6 h-6 text-[var(--text-faint)]" />}
        />
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col bg-[var(--bg-base)]">
      <div className="px-6 py-4 border-b border-[var(--border)]">
        <h2 className="text-xs font-bold uppercase tracking-wider text-[var(--text-lighter)]">
          Agents
        </h2>
      </div>
      <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4 space-y-3">
        {/* Available Agents (not-started) */}
        {availableAgents.length > 0 && (
          <div>
            <div className="flex items-center gap-2 mb-2 px-1">
              <div className="w-2 h-2 rounded-full bg-slate-500" />
              <span className="text-[10px] font-bold uppercase text-[var(--text-muted)]">
                Available ({availableAgents.length})
              </span>
            </div>
            <div className="space-y-2">
              {availableAgents.map(renderAgentCard)}
            </div>
          </div>
        )}

        {/* Active Agents */}
        {activeAgents.length > 0 && (
          <div>
            <div className="flex items-center gap-2 mb-2 px-1">
              <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
              <span className="text-[10px] font-bold uppercase text-[var(--text-muted)]">
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
              <div className="w-2 h-2 rounded-full bg-[var(--text-lighter)]" />
              <span className="text-[10px] font-bold uppercase text-[var(--text-muted)]">
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

// WebSocket message types
interface ConsoleWebSocketMessage {
  type: "connected" | "output" | "run_changed" | "idle" | "error";
  content?: string;
  run_id?: string;
  message?: string;
  status?: string;
  agent_name?: string;
}

const LiveConsolePanel: React.FC<LiveConsolePanelProps> = ({
  selectedAgent,
  projectId,
}) => {
  const [consoleOutput, setConsoleOutput] = useState<string>("");
  const [scrollLocked, setScrollLocked] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState<
    "disconnected" | "connecting" | "connected"
  >("disconnected");
  const [currentRunId, setCurrentRunId] = useState<string | null>(null);
  const consoleRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttempts = useRef(0);

  // Clear console output when agent changes
  useEffect(() => {
    setConsoleOutput("");
    setScrollLocked(false);
    setCurrentRunId(null);
  }, [selectedAgent?.id]);

  // Auto-scroll to bottom when new content arrives
  useEffect(() => {
    if (!scrollLocked && consoleRef.current) {
      consoleRef.current.scrollTop = consoleRef.current.scrollHeight;
    }
  }, [consoleOutput, scrollLocked]);

  // WebSocket connection for console streaming
  useEffect(() => {
    if (!selectedAgent || selectedAgent.agent.status !== "active") {
      // Clean up WebSocket when agent is not active
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      setConnectionStatus("disconnected");
      return;
    }

    const agentId = selectedAgent.id;

    const connectWebSocket = () => {
      // Close existing connection
      if (wsRef.current) {
        wsRef.current.close();
      }

      setConnectionStatus("connecting");

      // Create WebSocket connection
      const wsUrl = `ws://localhost:8080/api/agents/${agentId}/console`;
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        setConnectionStatus("connected");
        reconnectAttempts.current = 0;
        console.log(`WebSocket connected for agent ID ${agentId}`);
      };

      ws.onmessage = (event) => {
        try {
          const message: ConsoleWebSocketMessage = JSON.parse(event.data);

          switch (message.type) {
            case "connected":
              // Connection confirmation
              console.log("WebSocket connected:", message.message);
              break;

            case "output":
              // Append new output content
              if (message.content) {
                setConsoleOutput((prev) => prev + message.content);
              }
              if (message.run_id) {
                setCurrentRunId(message.run_id);
              }
              break;

            case "run_changed":
              // New run started, clear output and show notification
              setConsoleOutput(`--- Run changed to: ${message.run_id} ---\n`);
              setCurrentRunId(message.run_id || null);
              console.log("Run changed:", message.run_id);
              break;

            case "idle":
              // Agent is idle
              console.log("Agent idle:", message.message);
              break;

            case "error":
              // Error message
              console.error("WebSocket error:", message.message);
              setConsoleOutput(
                (prev) => prev + `\n[Error: ${message.message}]\n`,
              );
              break;

            default:
              console.log("Unknown WebSocket message:", message);
          }
        } catch (err) {
          console.error("Failed to parse WebSocket message:", err);
        }
      };

      ws.onerror = (error) => {
        console.error("WebSocket error:", error);
        setConnectionStatus("disconnected");
      };

      ws.onclose = (event) => {
        console.log(
          `WebSocket closed: code=${event.code}, reason=${event.reason}`,
        );
        setConnectionStatus("disconnected");
        wsRef.current = null;

        // Auto-reconnect with exponential backoff (max 30 seconds)
        if (selectedAgent?.agent.status === "active") {
          const delay = Math.min(
            1000 * Math.pow(2, reconnectAttempts.current),
            30000,
          );
          reconnectAttempts.current++;

          reconnectTimeoutRef.current = setTimeout(() => {
            console.log(
              `Attempting to reconnect (attempt ${reconnectAttempts.current})...`,
            );
            connectWebSocket();
          }, delay);
        }
      };
    };

    connectWebSocket();

    // Cleanup on unmount or agent change
    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [selectedAgent?.id, selectedAgent?.agent.status]);

  const handleClear = () => {
    setConsoleOutput("");
  };

  const isAgentActive = selectedAgent?.agent?.status === "active";

  // Determine status message for non-active agents
  const getStatusMessage = () => {
    if (!selectedAgent) return null;
    if (isAgentActive) return null;

    switch (selectedAgent.agent.status) {
      case "not-started":
        return {
          primary: "Agent not running",
          secondary: "Start the agent to see output",
        };
      case "stopped":
        return {
          primary: "Agent stopped",
          secondary: "Restart the agent to see output",
        };
      default:
        return {
          primary: "Agent idle - waiting for work",
          secondary: "Start a run to see live output",
        };
    }
  };
  const idleMessage = getStatusMessage();

  // Main layout - always render structure with conditional content
  return (
    <div className="h-full flex flex-col overflow-hidden bg-[var(--bg-base)]">
      {/* Console Header - Fixed */}
      <div className="px-6 py-4 border-b flex items-center justify-between flex-shrink-0 border-[var(--border)]">
        <div className="flex items-center gap-3">
          <IconTerminal className="w-4 h-4 text-brand-400" />
          <span className="text-xs font-bold text-[var(--text-light)]">
            {selectedAgent?.name || "Live Console"}
          </span>
          {selectedAgent?.agent?.current_run_id && (
            <span className="text-[10px] px-2 py-0.5 rounded bg-brand-500/10 text-brand-400 border border-brand-500/20">
              {selectedAgent.agent.current_run_id}
            </span>
          )}
          {isAgentActive && (
            <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
          )}
          {selectedAgent && !isAgentActive && (
            <span className="text-[10px] px-2 py-0.5 rounded bg-[var(--bg-surface-100)] text-[var(--text-muted)]">
              {selectedAgent.agent.status}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => setScrollLocked(!scrollLocked)}
            className={cn(
              "h-7 w-7 rounded transition-colors",
              scrollLocked
                ? "bg-brand-500/10 text-brand-400"
                : "text-[var(--text-muted)]",
            )}
            title={scrollLocked ? "Unlock scroll" : "Lock scroll"}
          >
            <IconLock className="w-3.5 h-3.5" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={handleClear}
            className="h-7 w-7 rounded transition-colors text-[var(--text-muted)]"
            title="Clear console"
          >
            <IconTrash className="w-3.5 h-3.5" />
          </Button>
        </div>
      </div>

      {/* Console output */}
      <div
        ref={consoleRef}
        className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4 font-mono text-xs leading-relaxed ansi-console min-h-0 bg-[var(--bg-base)] text-[var(--text-light)]"
      >
        {/* No agent selected state */}
        {!selectedAgent && (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <IconTerminal className="w-12 h-12 mb-3 text-[var(--text-lighter)]" />
            <p className="text-xs text-[var(--text-muted)]">
              Select an agent to view console output
            </p>
          </div>
        )}

        {/* Agent idle/stopped state */}
        {selectedAgent && idleMessage && (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <div className="w-12 h-12 rounded-xl flex items-center justify-center mb-3 bg-[var(--bg-surface-100)]">
              <IconFelix className="w-6 h-6 text-[var(--text-lighter)]" />
            </div>
            <p className="text-xs mb-1 text-[var(--text-muted)]">
              {idleMessage.primary}
            </p>
            <p className="text-[10px] text-[var(--text-lighter)]">
              {idleMessage.secondary}
            </p>
          </div>
        )}

        {/* Active agent - console output */}
        {selectedAgent && !idleMessage && consoleOutput && (
          <pre className="whitespace-pre-wrap">
            {(() => {
              try {
                return <Ansi useClasses>{consoleOutput}</Ansi>;
              } catch (error) {
                console.error("Ansi parsing failed:", error);
                return consoleOutput;
              }
            })()}
          </pre>
        )}

        {/* Active agent - waiting for output */}
        {selectedAgent && !idleMessage && !consoleOutput && (
          <div className="flex items-center gap-2 text-[var(--text-muted)]">
            <div className="w-2 h-2 rounded-full bg-brand-500 animate-pulse" />
            <span>Waiting for output...</span>
          </div>
        )}
      </div>

      {/* Workflow Footer - Fixed at bottom */}
      <div className="flex-shrink-0 border-t-2 border-[var(--border)] bg-[var(--bg-base)]">
        {/* Workflow Header */}
        <div className="px-4 py-1.5 border-b flex items-center gap-2 flex-shrink-0 border-[var(--border)]">
          <IconWorkflow className="w-4 h-4 text-[var(--text-muted)]" />
          <span className="text-xs font-bold uppercase tracking-wider text-[var(--text-lighter)]">
            Agent Workflow
          </span>
        </div>

        {/* Workflow Visualization */}
        <div className="overflow-x-auto overflow-y-hidden custom-scrollbar h-[120px]">
          {/* No agent selected */}
          {!selectedAgent && (
            <div className="h-full flex flex-col items-center justify-center opacity-20">
              <IconCpu className="w-8 h-8 mb-2 text-[var(--text-lighter)]" />
              <p className="text-[10px] uppercase tracking-widest text-[var(--text-lighter)]">
                Select an agent
              </p>
            </div>
          )}

          {/* Agent selected - always show workflow visualization */}
          {selectedAgent && (
            <WorkflowVisualization
              projectId={projectId}
              currentStage={selectedAgent?.agent?.current_workflow_stage}
              isAgentActive={isAgentActive}
            />
          )}
        </div>
      </div>
    </div>
  );
};

// --- Run History Panel ---

interface RunHistoryPanelProps {
  projectId: string;
  selectedAgentId: string | null;
  onSelectRun: (runId: string) => void;
  dbRuns: Run[]; // Database-backed runs from new API (S-0042)
  loading?: boolean;
}

const RunHistoryPanel: React.FC<RunHistoryPanelProps> = ({
  projectId,
  selectedAgentId,
  onSelectRun,
  dbRuns,
  loading: propsLoading,
}) => {
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string[]>([]);
  const [showFilters, setShowFilters] = useState(false);

  // Use the loading prop if provided, default to false (data comes from parent polling)
  const loading = propsLoading ?? false;

  // Filter runs (using database-backed runs from S-0042)
  const filteredRuns = dbRuns.filter((run) => {
    if (
      searchQuery &&
      !run.id.toLowerCase().includes(searchQuery.toLowerCase())
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
    <div className="h-full flex flex-col bg-[var(--bg-base)]">
      {/* Header */}
      <div className="px-6 py-4 border-b border-[var(--border)]">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-xs font-bold uppercase tracking-wider text-[var(--text-lighter)]">
            Run History
          </h2>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => setShowFilters(!showFilters)}
            className={cn(
              "h-7 w-7 rounded transition-colors",
              showFilters
                ? "bg-brand-500/10 text-brand-400"
                : "text-[var(--text-muted)]",
            )}
          >
            <Filter className="w-4 h-4" />
          </Button>
        </div>

        {/* Search */}
        <div className="relative">
          <Input
            type="text"
            placeholder="Search runs..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full px-3 py-2 pl-8 rounded-lg text-xs border outline-none focus:border-brand-500/50 bg-[var(--bg-base)] border-[var(--border)] text-[var(--text-light)]"
          />
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-[var(--text-muted)]" />
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="mt-3 p-3 rounded-lg border bg-[var(--bg-base)] border-[var(--border)]">
            <span className="text-[10px] font-bold uppercase text-[var(--text-muted)]">
              Status
            </span>
            <div className="flex flex-wrap gap-2 mt-2">
              {["running", "completed", "failed", "blocked", "stopped"].map(
                (status) => (
                  <Button
                    key={status}
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      setStatusFilter((prev) =>
                        prev.includes(status)
                          ? prev.filter((s) => s !== status)
                          : [...prev, status],
                      );
                    }}
                    className={cn(
                      "h-7 px-2 text-[10px] rounded-lg border transition-colors",
                      statusFilter.includes(status)
                        ? "bg-brand-500/10 border-brand-500/30 text-brand-400 hover:bg-brand-500/20"
                        : "border-[var(--border)] text-[var(--text-muted)]",
                    )}
                  >
                    {status}
                  </Button>
                ),
              )}
            </div>
          </div>
        )}
      </div>

      {/* Run list */}
      <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4 space-y-2">
        {!selectedAgentId ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <Clock className="w-8 h-8 mb-2 text-[var(--text-lighter)]" />
            <p className="text-[10px] font-mono uppercase tracking-widest text-[var(--text-muted)]">
              Select an agent
            </p>
          </div>
        ) : loading ? (
          <div className="flex items-center justify-center py-8">
            <PageLoading size="md" showText={false} fullPage={false} />
          </div>
        ) : filteredRuns.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <Clock className="w-8 h-8 mb-2 text-[var(--text-lighter)]" />
            <p className="text-[10px] font-mono uppercase text-[var(--text-muted)]">
              {searchQuery || statusFilter.length > 0
                ? "No matching runs"
                : "No runs yet"}
            </p>
          </div>
        ) : (
          filteredRuns.map((run) => (
            <DbRunCard key={run.id} run={run} onClick={onSelectRun} />
          ))
        )}
      </div>
    </div>
  );
};

// --- Database Run Card Component (S-0042) ---

interface DbRunCardProps {
  run: Run;
  onClick: (runId: string) => void;
}

const DbRunCard: React.FC<DbRunCardProps> = ({ run, onClick }) => {
  // Format relative time
  const formatRelativeTime = (isoString: string | null) => {
    if (!isoString) return null;
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
    <Button
      type="button"
      variant="ghost"
      onClick={() => onClick(run.id)}
      className="w-full h-auto p-3 rounded-xl text-left transition-all border border-[var(--border-muted)] hover:border-[var(--brand-500)]/30 bg-[var(--bg-surface-100)] hover:bg-[var(--bg-surface-200)] group flex flex-col items-start"
    >
      <div className="flex items-center justify-between mb-2 w-full">
        <span className="text-xs font-mono text-[var(--brand-400)] truncate group-hover:text-[var(--brand-300)] transition-colors max-w-[60%]">
          {run.id.substring(0, 8)}...
        </span>
        <Badge
          variant={getRunStatusVariant(run.status)}
          className="px-2 py-0.5 text-[10px] uppercase"
        >
          {run.status}
        </Badge>
      </div>
      <div className="flex items-center justify-between text-[10px] text-[var(--text-muted)] group-hover:text-[var(--text-light)]">
        <span>{run.agent_name || "Unknown Agent"}</span>
        {run.started_at && <span>{formatRelativeTime(run.started_at)}</span>}
      </div>
      {run.requirement_id && (
        <div className="mt-1 text-[10px] text-[var(--text-lighter)]">
          Req: {run.requirement_id}
        </div>
      )}
    </Button>
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
        className={`fixed right-0 top-0 bottom-8 w-[60vw] min-w-[500px] max-w-[800px] z-50 flex flex-col border-l shadow-2xl transition-transform duration-300 ease-out bg-[var(--bg-base)] border-[var(--border)] ${
          runId ? "translate-x-0" : "translate-x-full"
        }`}
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
  const [dbRuns, setDbRuns] = useState<Run[]>([]); // Database-backed runs from new API
  const [selectedAgent, setSelectedAgent] = useState<SelectedAgent | null>(
    null,
  );
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [agentSearch, setAgentSearch] = useState("");
  const [showStartDialog, setShowStartDialog] = useState(false);

  // Refs to track current selectedAgent for polling without recreating fetchAgents
  const selectedAgentRef = useRef(selectedAgent);
  useEffect(() => {
    selectedAgentRef.current = selectedAgent;
  }, [selectedAgent]);

  // Fetch runs from database-backed API (S-0042)
  const fetchDbRuns = useCallback(async () => {
    try {
      const response = await apiListRuns(20);
      setDbRuns(response.runs);
    } catch (err) {
      console.error("Failed to fetch database runs:", err);
      // Don't set error - runs panel will show empty state
    }
  }, []);

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
        const runtime = runtimeAgents[config.id];

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
          // Workflow stage fields (S-0030)
          current_workflow_stage: runtime.current_workflow_stage,
          workflow_stage_timestamp: runtime.workflow_stage_timestamp,
        };
      });

      setAgents(mergedAgents);
      setError(null);

      // Auto-select first active agent if none selected (using ref for current value)
      const currentSelected = selectedAgentRef.current;
      if (!currentSelected) {
        const activeAgents = mergedAgents.filter((a) => a.status === "active");
        if (activeAgents.length > 0) {
          setSelectedAgent({
            id: activeAgents[0].id,
            agent: activeAgents[0],
          });
        }
      } else {
        // Update selected agent data
        const updatedAgent = mergedAgents.find(
          (a) => a.id === currentSelected.id,
        );
        if (updatedAgent) {
          setSelectedAgent({
            id: updatedAgent.id,
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
  }, []); // Empty deps - uses ref for selectedAgent to avoid recreating

  // Fetch requirements
  const fetchRequirements = useCallback(async () => {
    try {
      const response = await felixApi.getRequirements(projectId);
      setRequirements(response.requirements);
    } catch (err) {
      console.error("Failed to fetch requirements:", err);
    }
  }, [projectId]);

  // Initial fetch on mount
  useEffect(() => {
    fetchAgents();
    fetchRequirements();
    fetchDbRuns();
  }, []); // Empty deps - run once on mount

  // 3-second polling for agents and runs (S-0042: restored live polling)
  useEffect(() => {
    const agentPollInterval = setInterval(() => {
      fetchAgents();
    }, POLLING_INTERVAL_MS);

    const runsPollInterval = setInterval(() => {
      fetchDbRuns();
    }, POLLING_INTERVAL_MS);

    // Cleanup intervals on unmount
    return () => {
      clearInterval(agentPollInterval);
      clearInterval(runsPollInterval);
    };
  }, [fetchAgents, fetchDbRuns]);

  // Handle start run using new API client (S-0042)
  const handleStart = async (requirementId: string) => {
    if (!selectedAgent) return;
    setActionInProgress("start");
    try {
      // Try to use the new database-backed API first
      // The agent_id for the new API is a string UUID; legacy endpoints still power start/stop.
      // For now, use the legacy API which starts the configured agent process
      await felixApi.startAgentWithRequirement(selectedAgent.id, requirementId);
      await fetchAgents();
      await fetchDbRuns();
    } catch (err) {
      console.error("Failed to start agent:", err);
      setError(err instanceof Error ? err.message : "Failed to start agent");
    } finally {
      setActionInProgress(null);
    }
  };

  // Handle stop run using new API client (S-0042)
  const handleStop = async (mode: "graceful" | "force") => {
    if (!selectedAgent) return;
    setActionInProgress("stop");
    try {
      // Use the legacy API for stopping (which signals the running process)
      await felixApi.stopAgent(selectedAgent.id, mode);
      await fetchAgents();
      await fetchDbRuns();
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
    fetchDbRuns();
  };

  const statusTone: Record<AgentStatus, string> = {
    active: "bg-emerald-500/15 text-emerald-400 border-emerald-500/30",
    stale: "bg-amber-500/15 text-amber-400 border-amber-500/30",
    inactive: "bg-slate-500/15 text-slate-300 border-slate-500/30",
    stopped: "bg-rose-500/15 text-rose-400 border-rose-500/30",
    "not-started": "bg-slate-500/10 text-slate-300 border-slate-500/20",
  };

  const statusDot: Record<AgentStatus, string> = {
    active: "bg-emerald-500",
    stale: "bg-amber-400",
    inactive: "bg-slate-400",
    stopped: "bg-rose-500",
    "not-started": "bg-slate-500",
  };

  const filteredAgents = agents.filter((agent) => {
    const query = agentSearch.trim().toLowerCase();
    if (!query) return true;
    return (
      agent.name.toLowerCase().includes(query) ||
      agent.executable.toLowerCase().includes(query) ||
      (agent.hostname || "").toLowerCase().includes(query)
    );
  });

  const activeCount = agents.filter(
    (agent) => agent.status === "active" || agent.status === "stale",
  ).length;
  const idleCount = agents.filter(
    (agent) => agent.status === "inactive" || agent.status === "not-started",
  ).length;
  const stoppedCount = agents.filter((agent) => agent.status === "stopped")
    .length;
  const runningRuns = dbRuns.filter((run) => run.status === "running").length;
  const failedRuns = dbRuns.filter((run) => run.status === "failed").length;
  const availableRequirements = requirements.filter(
    (req) => req.status === "planned" || req.status === "blocked",
  );
  const isAgentActive = selectedAgent?.agent.status === "active";
  const canStartAgent =
    selectedAgent &&
    (selectedAgent.agent.status === "not-started" ||
      selectedAgent.agent.status === "stopped");
  const canStopAgent = selectedAgent && isAgentActive;

  const workflowStages = [
    "draft",
    "planned",
    "in_progress",
    "blocked",
    "completed",
  ] as const;
  const workflowCounts = workflowStages.map((status) => ({
    status,
    count: requirements.filter((req) => req.status === status).length,
  }));

  const velocityBuckets = (() => {
    const now = new Date();
    const buckets = Array.from({ length: 6 }, (_, idx) => {
      const hour = (now.getHours() - (5 - idx) + 24) % 24;
      return {
        label: `${hour.toString().padStart(2, "0")}:00`,
        value: 0,
      };
    });
    dbRuns.forEach((run) => {
      if (!run.started_at) return;
      const started = new Date(run.started_at);
      const diffHours = Math.floor(
        (now.getTime() - started.getTime()) / (1000 * 60 * 60),
      );
      if (diffHours < 0 || diffHours > 5) return;
      const index = 5 - diffHours;
      if (buckets[index]) buckets[index].value += 1;
    });
    return buckets;
  })();
  const maxVelocity = Math.max(
    1,
    ...velocityBuckets.map((bucket) => bucket.value),
  );

  const matrixSlots = Math.max(24, agents.length);
  const matrixAgents = Array.from({ length: matrixSlots }, (_, idx) =>
    agents[idx] ? agents[idx] : null,
  );

  const formatRelativeTime = (isoString: string | null | undefined) => {
    if (!isoString) return "--";
    try {
      const date = new Date(isoString);
      const now = new Date();
      const diff = Math.floor((now.getTime() - date.getTime()) / 1000);
      if (diff < 60) return `${diff}s ago`;
      if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
      if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
      return `${Math.floor(diff / 86400)}d ago`;
    } catch {
      return "--";
    }
  };

  const recentRunsForSelected = selectedAgent
    ? dbRuns
        .filter((run) => run.agent_name === selectedAgent.agent.name)
        .slice(0, 5)
    : [];

  return (
    <div className="h-full flex flex-col bg-[var(--bg-base)]">
      {/* Error banner */}
      {error && (
        <div className="px-6 py-2 bg-red-500/10 border-b border-red-500/20 flex items-center justify-between">
          <div className="flex items-center gap-2 text-red-400">
            <AlertCircle className="w-4 h-4" />
            <span className="text-xs">{error}</span>
          </div>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={fetchAgents}
            className="h-auto px-2 py-1 text-[10px] font-bold text-red-400 hover:text-red-300"
          >
            Retry
          </Button>
        </div>
      )}

      <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-6 space-y-6">
        {/* Metric tiles */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card className="p-5 border border-[var(--border-default)] bg-[var(--bg-surface)]">
            <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
              Active Agents
            </p>
            <div className="mt-3 flex items-end justify-between">
              <span className="text-3xl font-semibold theme-text-secondary">
                {activeCount}
              </span>
              <span className="text-[11px] theme-text-muted">
                {agents.length} total
              </span>
            </div>
          </Card>
          <Card className="p-5 border border-[var(--border-default)] bg-[var(--bg-surface)]">
            <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
              Idle / Ready
            </p>
            <div className="mt-3 flex items-end justify-between">
              <span className="text-3xl font-semibold theme-text-secondary">
                {idleCount}
              </span>
              <span className="text-[11px] theme-text-muted">
                {stoppedCount} stopped
              </span>
            </div>
          </Card>
          <Card className="p-5 border border-[var(--border-default)] bg-[var(--bg-surface)]">
            <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
              Runs In Flight
            </p>
            <div className="mt-3 flex items-end justify-between">
              <span className="text-3xl font-semibold theme-text-secondary">
                {runningRuns}
              </span>
              <span className="text-[11px] theme-text-muted">
                {failedRuns} failed
              </span>
            </div>
          </Card>
        </div>

        {/* Widgets row */}
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          <Card className="xl:col-span-2 p-6 border border-[var(--border-default)] bg-[var(--bg-surface)]">
            <div className="flex items-center justify-between mb-5">
              <div>
                <p className="text-[11px] font-semibold uppercase tracking-[0.2em] theme-text-muted">
                  Live Fleet Health
                </p>
                <p className="text-xs theme-text-muted mt-1">
                  Status snapshot of registered agents.
                </p>
              </div>
              <div className="flex items-center gap-3 text-[10px] theme-text-muted">
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-emerald-500" />
                  Active
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-amber-400" />
                  Stale
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-slate-400" />
                  Idle
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-rose-500" />
                  Stopped
                </span>
              </div>
            </div>
            <div className="grid grid-cols-12 gap-2">
              {matrixAgents.map((agent, idx) => (
                <div
                  key={agent?.id || `slot-${idx}`}
                  className={`h-6 rounded-md ${
                    agent ? statusDot[agent.status] : "bg-[var(--bg-surface-200)]"
                  }`}
                  title={agent ? `${agent.name} (${agent.status})` : "Empty"}
                />
              ))}
            </div>
            <div className="mt-6 border-t border-[var(--border-muted)] pt-4">
              <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
                Workflow Congestion
              </p>
              <div className="mt-3 grid grid-cols-5 gap-3">
                {workflowCounts.map((stage) => (
                  <div key={stage.status} className="text-center">
                    <div className="h-16 rounded-lg bg-[var(--bg-surface-200)] flex items-end justify-center overflow-hidden">
                      <div
                        className="w-full bg-[var(--accent-primary)]/60"
                        style={{
                          height: `${Math.min(100, stage.count * 10)}%`,
                        }}
                      />
                    </div>
                    <p className="mt-2 text-[10px] uppercase tracking-[0.18em] theme-text-muted">
                      {stage.status.replace("_", " ")}
                    </p>
                    <p className="text-xs font-semibold theme-text-secondary">
                      {stage.count}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          </Card>

          <Card className="p-6 border border-[var(--border-default)] bg-[var(--bg-surface)]">
            <div className="flex items-center justify-between mb-5">
              <div>
                <p className="text-[11px] font-semibold uppercase tracking-[0.2em] theme-text-muted">
                  Performance Velocity
                </p>
                <p className="text-xs theme-text-muted mt-1">
                  Runs started per hour.
                </p>
              </div>
              <span className="text-[10px] theme-text-muted">Last 6 hours</span>
            </div>
            <div className="flex items-end gap-3 h-40">
              {velocityBuckets.map((bucket) => (
                <div key={bucket.label} className="flex-1 flex flex-col items-center gap-2">
                  <div className="w-full bg-[var(--bg-surface-200)] rounded-md flex items-end overflow-hidden h-28">
                    <div
                      className="w-full bg-[var(--accent-primary)]/70"
                      style={{
                        height: `${(bucket.value / maxVelocity) * 100}%`,
                      }}
                    />
                  </div>
                  <span className="text-[9px] theme-text-muted">
                    {bucket.label}
                  </span>
                </div>
              ))}
            </div>
          </Card>
        </div>

        {/* Agents table */}
        <Card className="p-6 border border-[var(--border-default)] bg-[var(--bg-surface)]">
          <div className="flex items-center justify-between gap-4 mb-4">
            <div>
              <h2 className="text-sm font-semibold theme-text-secondary">
                Agent Fleet
              </h2>
              <p className="text-xs theme-text-muted">
                Select an agent to drill into details.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Input
                value={agentSearch}
                onChange={(event) => setAgentSearch(event.target.value)}
                placeholder="Search agents..."
                className="h-9 w-64 text-xs"
              />
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={handleRefresh}
                className="text-[10px] font-bold"
              >
                Refresh
              </Button>
            </div>
          </div>
          {loading ? (
            <PageLoading message="Loading agents..." size="sm" fullPage={false} />
          ) : filteredAgents.length === 0 ? (
            <EmptyState
              title="No agents found"
              description="Try adjusting your search."
              icon={<IconCpu className="w-6 h-6 text-[var(--text-faint)]" />}
            />
          ) : (
            <div className="border border-[var(--border-default)] rounded-xl overflow-hidden">
              <DataTable
                data={filteredAgents}
                rowKey={(row) => row.id}
                onRowClick={(row) => setSelectedAgent({ id: row.id, agent: row })}
                rowClassName={(row) =>
                  selectedAgent?.id === row.id
                    ? "bg-[var(--brand-500)]/5"
                    : ""
                }
                columns={[
                  {
                    key: "agent",
                    header: "Agent",
                    cell: (row) => (
                      <div>
                        <p className="text-sm font-semibold theme-text-secondary">
                          {row.name}
                        </p>
                        <p className="text-[10px] theme-text-muted">
                          {row.hostname || row.executable}
                        </p>
                      </div>
                    ),
                  },
                  {
                    key: "status",
                    header: "Status",
                    cell: (row) => (
                      <span
                        className={`inline-flex items-center gap-2 px-2 py-1 rounded-full text-[10px] font-semibold border ${statusTone[row.status]}`}
                      >
                        <span className={`w-2 h-2 rounded-full ${statusDot[row.status]}`} />
                        {row.status.replace("-", " ")}
                      </span>
                    ),
                  },
                  {
                    key: "heartbeat",
                    header: "Last heartbeat",
                    cell: (row) => (
                      <span className="text-xs theme-text-muted">
                        {formatRelativeTime(row.last_heartbeat)}
                      </span>
                    ),
                  },
                  {
                    key: "run",
                    header: "Current run",
                    cell: (row) => (
                      <span className="text-xs font-mono theme-text-secondary">
                        {row.current_run_id || "--"}
                      </span>
                    ),
                  },
                  {
                    key: "workflow",
                    header: "Workflow",
                    cell: (row) => (
                      <span className="text-xs theme-text-muted">
                        {row.current_workflow_stage || "--"}
                      </span>
                    ),
                  },
                ]}
                actions={(row) => (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="text-[10px]"
                    onClick={(event) => {
                      event.stopPropagation();
                      setSelectedAgent({ id: row.id, agent: row });
                    }}
                  >
                    View
                  </Button>
                )}
              />
            </div>
          )}
        </Card>

        {selectedAgent && (
          <Card className="p-6 border border-[var(--border-default)] bg-[var(--bg-surface)]">
            <div className="flex items-start justify-between gap-4 mb-4">
              <div>
                <p className="text-xs uppercase tracking-[0.2em] theme-text-muted">
                  Agent Detail
                </p>
                <h3 className="text-lg font-semibold theme-text-secondary mt-2">
                  {selectedAgent.agent.name}
                </h3>
                <p className="text-xs theme-text-muted">
                  {selectedAgent.agent.hostname || selectedAgent.agent.executable}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Button
                  onClick={() => setShowStartDialog(true)}
                  disabled={!canStartAgent || actionInProgress !== null}
                  size="sm"
                  className="text-[10px] font-bold gap-2"
                >
                  {actionInProgress === "start" ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Starting
                    </>
                  ) : (
                    <>
                      <IconPlay className="w-3 h-3" />
                      Start
                    </>
                  )}
                </Button>
                <Button
                  onClick={() => handleStop("graceful")}
                  disabled={!canStopAgent || actionInProgress !== null}
                  variant="ghost"
                  size="sm"
                  className="text-[10px] font-bold text-[var(--destructive-500)] gap-2"
                >
                  {actionInProgress === "stop" ? (
                    <>
                      <div className="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                      Stopping
                    </>
                  ) : (
                    <>
                      <IconStop className="w-3 h-3" />
                      Stop
                    </>
                  )}
                </Button>
                <Button
                  onClick={() => setSelectedAgent(null)}
                  variant="ghost"
                  size="sm"
                  className="text-[10px] font-bold"
                >
                  Clear
                </Button>
              </div>
            </div>
            <Dialog open={showStartDialog} onOpenChange={setShowStartDialog}>
              <DialogContent className="max-w-sm">
                <DialogHeader>
                  <DialogTitle>Select Requirement</DialogTitle>
                  <DialogDescription>
                    Choose a requirement to start the agent with.
                  </DialogDescription>
                </DialogHeader>
                <div className="max-h-64 overflow-y-auto custom-scrollbar space-y-2 py-2">
                  {availableRequirements.length === 0 ? (
                    <div className="text-center py-4 text-xs theme-text-muted">
                      No available requirements.
                    </div>
                  ) : (
                    availableRequirements.map((req) => (
                      <Button
                        key={req.id}
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          handleStart(req.id);
                          setShowStartDialog(false);
                        }}
                        className="w-full h-auto px-3 py-2 text-left justify-between rounded-md border border-transparent hover:border-[var(--brand-500)]/20 hover:bg-[var(--brand-500)]/10"
                      >
                        <div>
                          <span className="text-xs font-mono text-[var(--brand-400)]">
                            {req.id}
                          </span>
                          <p className="text-[10px] truncate theme-text-muted">
                            {req.title}
                          </p>
                        </div>
                        <Badge
                          variant={
                            req.status === "blocked" ? "destructive" : "default"
                          }
                          className={cn(
                            "text-[9px] px-1.5 py-0.5",
                            getRequirementStatusBadgeClass(req.status),
                          )}
                        >
                          {req.status}
                        </Badge>
                      </Button>
                    ))
                  )}
                </div>
                <DialogFooter>
                  <Button
                    variant="ghost"
                    onClick={() => setShowStartDialog(false)}
                  >
                    Cancel
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-4">
                <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
                  Status
                </p>
                <span
                  className={`mt-2 inline-flex items-center gap-2 px-3 py-1 rounded-full text-[10px] font-semibold border ${statusTone[selectedAgent.agent.status]}`}
                >
                  <span
                    className={`w-2 h-2 rounded-full ${statusDot[selectedAgent.agent.status]}`}
                  />
                  {selectedAgent.agent.status.replace("-", " ")}
                </span>
              </div>
              <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-4">
                <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
                  Last heartbeat
                </p>
                <p className="mt-2 text-sm font-semibold theme-text-secondary">
                  {formatRelativeTime(selectedAgent.agent.last_heartbeat)}
                </p>
              </div>
              <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-4">
                <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
                  Current run
                </p>
                <p className="mt-2 text-sm font-mono theme-text-secondary">
                  {selectedAgent.agent.current_run_id || "--"}
                </p>
              </div>
            </div>
            <div className="mt-6">
              <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted mb-3">
                Recent runs
              </p>
              {recentRunsForSelected.length === 0 ? (
                <p className="text-xs theme-text-muted">
                  No recent runs for this agent yet.
                </p>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {recentRunsForSelected.map((run) => (
                    <Button
                      key={run.id}
                      type="button"
                      variant="ghost"
                      onClick={() => setSelectedRunId(run.id)}
                      className="w-full h-auto p-3 rounded-xl text-left border border-[var(--border-muted)] hover:border-[var(--accent-primary)]/40"
                    >
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-xs font-mono theme-text-secondary">
                          {run.id.slice(0, 8)}...
                        </span>
                        <Badge
                          variant={getRunStatusVariant(run.status)}
                          className="text-[9px] uppercase"
                        >
                          {run.status}
                        </Badge>
                      </div>
                      <p className="text-[10px] theme-text-muted">
                        {run.requirement_id || "No requirement"}
                      </p>
                    </Button>
                  ))}
                </div>
              )}
            </div>
          </Card>
        )}
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

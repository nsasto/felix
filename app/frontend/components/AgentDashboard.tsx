import React, { useState, useEffect, useCallback, useRef } from "react";
import { felixApi, Requirement } from "../services/felixApi";
import {
  listAgents as apiListAgents,
  listRuns as apiListRuns,
} from "../src/api/client";
import type { Agent, Run } from "../src/api/types";
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
  ChevronLeft as IconChevronLeft,
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
  agent: Agent;
}

type AgentStatus = "running" | "idle" | "stopped" | "error" | "unknown";
type DashboardView = "dashboard" | "detail";

const getAgentMetadataValue = (
  metadata: Record<string, unknown>,
  key: string,
) => {
  const value = metadata[key];
  return typeof value === "string" ? value : null;
};

const getAgentHostLabel = (agent: Agent) => {
  const metadata = agent.metadata || {};
  const machine = metadata.machine;
  if (machine && typeof machine === "object") {
    const machineHost = getAgentMetadataValue(
      machine as Record<string, unknown>,
      "hostname",
    );
    if (machineHost) return machineHost;
  }
  return getAgentMetadataValue(metadata, "hostname");
};

const getAgentWorkflowStage = (agent: Agent) => {
  const metadata = agent.metadata || {};
  return (
    getAgentMetadataValue(metadata, "current_workflow_stage") ||
    getAgentMetadataValue(metadata, "workflow_stage")
  );
};

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

// --- Live Console Panel ---

interface LiveConsolePanelProps {
  selectedAgent: SelectedAgent | null;
  projectId: string;
  runId: string | null;
  showWorkflow?: boolean;
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
  runId,
  showWorkflow = true,
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
    if (!selectedAgent || selectedAgent.agent.status !== "running" || !runId) {
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
      const wsUrl = `ws://localhost:8080/api/agents/${agentId}/console?run_id=${encodeURIComponent(runId)}`;
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
        if (selectedAgent?.agent.status === "running" && runId) {
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
  }, [selectedAgent?.id, selectedAgent?.agent.status, runId]);

  const handleClear = () => {
    setConsoleOutput("");
  };

  const isAgentActive = selectedAgent?.agent?.status === "running";

  // Determine status message for non-active agents
  const getStatusMessage = () => {
    if (!selectedAgent) return null;
    if (isAgentActive) return null;

    switch (selectedAgent.agent.status) {
      case "idle":
        return {
          primary: "Agent idle",
          secondary: "Start a run to see output",
        };
      case "stopped":
        return {
          primary: "Agent stopped",
          secondary: "Restart the agent to see output",
        };
      case "error":
        return {
          primary: "Agent error",
          secondary: "Resolve the error to resume output",
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
            {selectedAgent?.agent?.name || "Live Console"}
          </span>
          {currentRunId && (
            <span className="text-[10px] px-2 py-0.5 rounded bg-brand-500/10 text-brand-400 border border-brand-500/20">
              {currentRunId}
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

      {showWorkflow && (
        <div className="flex-shrink-0 border-t-2 border-[var(--border)] bg-[var(--bg-base)]">
          <div className="px-4 py-1.5 border-b flex items-center gap-2 flex-shrink-0 border-[var(--border)]">
            <IconWorkflow className="w-4 h-4 text-[var(--text-muted)]" />
            <span className="text-xs font-bold uppercase tracking-wider text-[var(--text-lighter)]">
              Agent Workflow
            </span>
          </div>
          <div className="overflow-x-auto overflow-y-hidden custom-scrollbar h-[120px]">
            {!selectedAgent && (
              <div className="h-full flex flex-col items-center justify-center opacity-20">
                <IconCpu className="w-8 h-8 mb-2 text-[var(--text-lighter)]" />
                <p className="text-[10px] uppercase tracking-widest text-[var(--text-lighter)]">
                  Select an agent
                </p>
              </div>
            )}
            {selectedAgent && (
              <WorkflowVisualization
                projectId={projectId}
                currentStage={getAgentWorkflowStage(selectedAgent.agent)}
                isAgentActive={isAgentActive}
              />
            )}
          </div>
        </div>
      )}
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
  const [agents, setAgents] = useState<Agent[]>([]);
  const [dbRuns, setDbRuns] = useState<Run[]>([]); // Database-backed runs from new API
  const [selectedAgent, setSelectedAgent] = useState<SelectedAgent | null>(
    null,
  );
  const [viewMode, setViewMode] = useState<DashboardView>("dashboard");
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

  // Fetch agents from database-backed API
  const fetchAgents = useCallback(async () => {
    try {
      const response = await apiListAgents({
        scope: "project",
        projectId: projectId || undefined,
      });
      setAgents(response.agents);
      setError(null);

      // Auto-select first running agent if none selected (using ref for current value)
      const currentSelected = selectedAgentRef.current;
      if (!currentSelected) {
        const runningAgents = response.agents.filter(
          (agent) => normalizeStatus(agent.status) === "running",
        );
        if (runningAgents.length > 0) {
          setSelectedAgent({
            id: runningAgents[0].id,
            agent: runningAgents[0],
          });
        }
      } else {
        // Update selected agent data
        const updatedAgent = response.agents.find(
          (agent) => agent.id === currentSelected.id,
        );
        if (updatedAgent) {
          setSelectedAgent({
            id: updatedAgent.id,
            agent: updatedAgent,
          });
        } else if (viewMode === "detail") {
          setViewMode("dashboard");
          setSelectedAgent(null);
        }
      }
    } catch (err) {
      console.error("Failed to fetch agents:", err);
      setError(err instanceof Error ? err.message : "Failed to fetch agents");
    } finally {
      setLoading(false);
    }
  }, [projectId, viewMode]); // Uses ref for selectedAgent to avoid recreating

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
  }, [fetchAgents, fetchRequirements, fetchDbRuns]);

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

  const normalizeStatus = (status: string | null | undefined): AgentStatus => {
    if (!status) return "unknown";
    if (status === "running") return "running";
    if (status === "idle") return "idle";
    if (status === "stopped") return "stopped";
    if (status === "error") return "error";
    return "unknown";
  };

  const statusTone: Record<AgentStatus, string> = {
    running: "bg-emerald-500/15 text-emerald-400 border-emerald-500/30",
    idle: "bg-slate-500/15 text-slate-300 border-slate-500/30",
    stopped: "bg-rose-500/15 text-rose-400 border-rose-500/30",
    error: "bg-amber-500/15 text-amber-400 border-amber-500/30",
    unknown: "bg-slate-500/10 text-slate-300 border-slate-500/20",
  };

  const statusDot: Record<AgentStatus, string> = {
    running: "bg-emerald-500",
    idle: "bg-slate-400",
    stopped: "bg-rose-500",
    error: "bg-amber-400",
    unknown: "bg-slate-500",
  };

  const filteredAgents = agents.filter((agent) => {
    const query = agentSearch.trim().toLowerCase();
    if (!query) return true;
    return (
      agent.name.toLowerCase().includes(query) ||
      agent.type.toLowerCase().includes(query) ||
      agent.project_id.toLowerCase().includes(query) ||
      (getAgentHostLabel(agent) || "").toLowerCase().includes(query)
    );
  });

  const runningCount = agents.filter(
    (agent) => normalizeStatus(agent.status) === "running",
  ).length;
  const idleCount = agents.filter(
    (agent) => normalizeStatus(agent.status) === "idle",
  ).length;
  const stoppedCount = agents.filter(
    (agent) => normalizeStatus(agent.status) === "stopped",
  ).length;
  const runningRuns = dbRuns.filter((run) => run.status === "running").length;
  const failedRuns = dbRuns.filter((run) => run.status === "failed").length;
  const availableRequirements = requirements.filter(
    (req) => req.status === "planned" || req.status === "blocked",
  );
  const isAgentActive = selectedAgent?.agent.status === "running";
  const canStartAgent =
    selectedAgent &&
    (selectedAgent.agent.status === "idle" ||
      selectedAgent.agent.status === "stopped");
  const canStopAgent = selectedAgent && isAgentActive;

  const enterDetailView = (agent: Agent) => {
    setSelectedAgent({ id: agent.id, agent });
    setViewMode("detail");
  };

  const exitDetailView = () => {
    setViewMode("dashboard");
  };

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

  const selectedAgentRuns = selectedAgent
    ? dbRuns.filter((run) => run.agent_id === selectedAgent.id)
    : [];
  const activeRunId =
    selectedAgentRuns.find((run) => run.status === "running")?.id || null;

  const renderDashboard = () => (
    <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-6 space-y-6">
      {/* Metric tiles */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="p-5 border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
          <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
            Running Agents
          </p>
          <div className="mt-3 flex items-end justify-between">
            <span className="text-3xl font-semibold theme-text-secondary">
              {runningCount}
            </span>
            <span className="text-[11px] theme-text-muted">
              {agents.length} total
            </span>
          </div>
        </Card>
        <Card className="p-5 border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
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
        <Card className="p-5 border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
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
        <Card className="p-6 border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
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
                Running
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 rounded-full bg-slate-400" />
                Idle
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 rounded-full bg-rose-500" />
                Stopped
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 rounded-full bg-amber-400" />
                Error
              </span>
            </div>
          </div>
          <div className="grid grid-cols-12 gap-2">
            {matrixAgents.map((agent, idx) => (
              <div
                key={agent?.id || `slot-${idx}`}
                className={`h-6 rounded-md ${
                  agent
                    ? statusDot[normalizeStatus(agent.status)]
                    : "bg-[var(--bg-surface-200)]"
                }`}
                title={agent ? `${agent.name} (${agent.status})` : "Empty"}
              />
            ))}
          </div>
        </Card>

        <Card className="p-6 border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
          <div className="mb-5">
            <p className="text-[11px] font-semibold uppercase tracking-[0.2em] theme-text-muted">
              Workflow Congestion
            </p>
            <p className="text-xs theme-text-muted mt-1">
              Requirement stages across agents.
            </p>
          </div>
          <div className="grid grid-cols-5 gap-3">
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
        </Card>

        <Card className="p-6 border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
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
              <div
                key={bucket.label}
                className="flex-1 flex flex-col items-center gap-2"
              >
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
      <div>
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
        <Card className="border border-[var(--border-default)] bg-[var(--bg-surface-100)]">
          {loading ? (
            <PageLoading
              message="Loading agents..."
              size="sm"
              fullPage={false}
            />
          ) : filteredAgents.length === 0 ? (
            <EmptyState
              title="No agents found"
              description="Try adjusting your search."
              icon={<IconCpu className="w-6 h-6 text-[var(--text-faint)]" />}
            />
          ) : (
            <div className="overflow-hidden">
              <DataTable
                data={filteredAgents}
                rowKey={(row) => row.id}
                onRowClick={(row) => enterDetailView(row)}
                rowClassName={(row) =>
                  selectedAgent?.id === row.id ? "bg-[var(--brand-500)]/5" : ""
                }
                columns={[
                  {
                    key: "agent",
                    header: "Agent",
                    cell: (row) => {
                      const hostLabel = getAgentHostLabel(row);
                      return (
                        <div>
                          <p className="text-sm font-semibold theme-text-secondary">
                            {row.name}
                          </p>
                          <p className="text-[10px] theme-text-muted">
                            {row.type}
                            {hostLabel ? ` | ${hostLabel}` : ""}
                          </p>
                        </div>
                      );
                    },
                  },
                  {
                    key: "status",
                    header: "Status",
                    cell: (row) => (
                      <span
                        className={`inline-flex items-center gap-2 px-2 py-1 rounded-full text-[10px] font-semibold border ${statusTone[normalizeStatus(row.status)]}`}
                      >
                        <span
                          className={`w-2 h-2 rounded-full ${statusDot[normalizeStatus(row.status)]}`}
                        />
                        {row.status.replace("-", " ")}
                      </span>
                    ),
                  },
                  {
                    key: "project",
                    header: "Project",
                    cell: (row) => (
                      <span className="text-xs font-mono theme-text-muted">
                        {row.project_id}
                      </span>
                    ),
                  },
                  {
                    key: "heartbeat",
                    header: "Last heartbeat",
                    cell: (row) => (
                      <span className="text-xs theme-text-muted">
                        {formatRelativeTime(row.heartbeat_at)}
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
                      enterDetailView(row);
                    }}
                  >
                    View
                  </Button>
                )}
              />
            </div>
          )}
        </Card>
      </div>
    </div>
  );

  const renderDetail = () => {
    if (!selectedAgent) {
      return null;
    }

    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <div className="border-b border-[var(--border-default)] bg-[var(--bg-base)] px-6 py-4">
          <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
            <div className="flex items-center gap-3">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={exitDetailView}
                className="h-9 w-9 text-[var(--text-muted)]"
                aria-label="Back to dashboard"
              >
                <IconChevronLeft className="w-4 h-4" />
              </Button>
              <div>
                <div className="flex items-center gap-3">
                  <h2 className="text-lg font-semibold theme-text-secondary">
                    {selectedAgent.agent.name}
                  </h2>
                  <span
                    className={`inline-flex items-center gap-2 px-2 py-1 rounded-full text-[10px] font-semibold border ${statusTone[normalizeStatus(selectedAgent.agent.status)]}`}
                  >
                    <span
                      className={`w-2 h-2 rounded-full ${statusDot[normalizeStatus(selectedAgent.agent.status)]}`}
                    />
                    {selectedAgent.agent.status.replace("-", " ")}
                  </span>
                </div>
                <div className="text-[10px] theme-text-muted mt-1">
                  <span className="font-mono">
                    {getAgentHostLabel(selectedAgent.agent) ||
                      selectedAgent.agent.type}
                  </span>
                  <span className="mx-2 text-[var(--text-faint)]">|</span>
                  <span className="font-mono">
                    Heartbeat{" "}
                    {formatRelativeTime(selectedAgent.agent.heartbeat_at)}
                  </span>
                </div>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2">
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
        </div>

        <div className="flex-1 grid grid-cols-1 xl:grid-cols-[minmax(0,2fr)_minmax(320px,1fr)] gap-6 p-6 overflow-hidden">
          <div className="border border-[var(--border-default)] rounded-2xl bg-[var(--bg-surface-100)] overflow-hidden">
            <LiveConsolePanel
              selectedAgent={selectedAgent}
              projectId={projectId}
              runId={activeRunId}
              showWorkflow={false}
            />
          </div>
          <div className="border border-[var(--border-default)] rounded-2xl bg-[var(--bg-surface-100)] overflow-hidden">
            <RunHistoryPanel
              projectId={projectId}
              selectedAgentId={selectedAgent.id}
              onSelectRun={setSelectedRunId}
              dbRuns={selectedAgentRuns}
              loading={loading}
            />
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
              <Button variant="ghost" onClick={() => setShowStartDialog(false)}>
                Cancel
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    );
  };

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

      {viewMode === "detail" ? renderDetail() : renderDashboard()}

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

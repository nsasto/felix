import React, { useEffect, useState, useMemo } from "react";
import {
  felixApi,
  WorkflowStage,
  WorkflowConfigResponse,
} from "../services/felixApi";
import {
  IconTarget,
  IconPlay,
  IconGitBranch,
  IconFolder,
  IconFileText,
  IconCpu,
  IconFileCode,
  IconShield,
  IconCheckSquare,
  IconFlask,
  IconGitCommit,
  IconCheckCircle,
  IconBarChart,
  IconFlag,
} from "./Icons";

// --- Types ---

interface WorkflowVisualizationProps {
  projectId: string;
  currentStage: string | null | undefined;
  /** Optional: list of completed stage IDs */
  completedStages?: string[];
  /** Optional: list of failed stage IDs */
  failedStages?: string[];
  /** Optional: whether the agent is active */
  isAgentActive?: boolean;
}

type StageStatus = "active" | "completed" | "failed" | "pending" | "unknown";

// --- Icon Mapping ---

/**
 * Maps workflow.json icon names to React icon components.
 * Add new icons here as they're added to Icons.tsx.
 */
const ICON_MAP: Record<
  string,
  React.FC<{ className?: string; style?: React.CSSProperties }>
> = {
  target: IconTarget,
  play: IconPlay,
  "git-branch": IconGitBranch,
  folder: IconFolder,
  "file-text": IconFileText,
  cpu: IconCpu,
  "file-code": IconFileCode,
  shield: IconShield,
  "check-square": IconCheckSquare,
  flask: IconFlask,
  "git-commit": IconGitCommit,
  "check-circle": IconCheckCircle,
  "bar-chart": IconBarChart,
  flag: IconFlag,
};

/**
 * Default icon when the specified icon is not found in the map
 */
const DefaultIcon: React.FC<{
  className?: string;
  style?: React.CSSProperties;
}> = ({ className, style }) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <circle cx="12" cy="12" r="10" />
    <path d="M12 16v-4" />
    <path d="M12 8h.01" />
  </svg>
);

// --- Styled Components ---

const StageNode: React.FC<{
  stage: WorkflowStage;
  status: StageStatus;
  isLast: boolean;
}> = ({ stage, status, isLast }) => {
  const IconComponent = ICON_MAP[stage.icon] || DefaultIcon;

  // Determine styles based on status
  const getNodeStyles = () => {
    switch (status) {
      case "active":
        return {
          border: "border-felix-500",
          bg: "bg-felix-500/20",
          iconColor: "text-felix-400",
          nameColor: "text-felix-400",
          animation: "animate-workflow-pulse",
          glow: "shadow-lg shadow-felix-500/30",
        };
      case "completed":
        return {
          border: "border-emerald-500/50",
          bg: "bg-emerald-500/10",
          iconColor: "text-emerald-400",
          nameColor: "text-emerald-400",
          animation: "",
          glow: "",
        };
      case "failed":
        return {
          border: "border-red-500/50",
          bg: "bg-red-500/10",
          iconColor: "text-red-400",
          nameColor: "text-red-400",
          animation: "",
          glow: "",
        };
      case "unknown":
        return {
          border: "border-amber-500/50",
          bg: "bg-amber-500/10",
          iconColor: "text-amber-400",
          nameColor: "text-amber-400",
          animation: "",
          glow: "",
        };
      default: // pending
        return {
          border: "",
          bg: "",
          iconColor: "",
          nameColor: "",
          animation: "",
          glow: "",
        };
    }
  };

  const styles = getNodeStyles();
  const isPending = status === "pending";

  return (
    <div className="flex items-center">
      {/* Stage Node */}
      <div className="relative group">
        {/* Tooltip */}
        <div
          className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-2 py-1 rounded text-[10px] whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity z-10 pointer-events-none"
          style={{
            backgroundColor: "var(--bg-elevated)",
            color: "var(--text-secondary)",
            border: "1px solid var(--border-default)",
          }}
        >
          {stage.description}
          {stage.conditional && (
            <span className="ml-1 text-amber-400 text-[9px]">
              ({stage.conditional})
            </span>
          )}
        </div>

        {/* Node Container */}
        <div
          className={`flex flex-col items-center gap-1 p-2 rounded-lg transition-all duration-300 ${styles.animation} ${styles.glow} ${
            isPending ? "" : `border ${styles.border} ${styles.bg}`
          }`}
          style={{
            backgroundColor: isPending ? "var(--bg-surface)" : undefined,
            borderColor: isPending ? "var(--border-muted)" : undefined,
            minWidth: "52px",
          }}
        >
          {/* Icon with optional overlay */}
          <div className="relative">
            <IconComponent
              className={`w-4 h-4 transition-colors ${styles.iconColor}`}
              style={{
                color: isPending ? "var(--text-faint)" : undefined,
              }}
            />
            {/* Status overlay */}
            {status === "completed" && (
              <div className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-emerald-500 flex items-center justify-center">
                <svg
                  className="w-1.5 h-1.5 text-white"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="4"
                >
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              </div>
            )}
            {status === "failed" && (
              <div className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-red-500 flex items-center justify-center">
                <svg
                  className="w-1.5 h-1.5 text-white"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="4"
                >
                  <path d="M18 6L6 18M6 6l12 12" />
                </svg>
              </div>
            )}
          </div>

          {/* Stage Name */}
          <span
            className={`text-[9px] font-medium text-center leading-tight ${styles.nameColor}`}
            style={{
              color: isPending ? "var(--text-muted)" : undefined,
            }}
          >
            {stage.name}
          </span>
        </div>
      </div>

      {/* Connector Arrow */}
      {!isLast && (
        <div className="flex items-center px-0.5">
          <div
            className="w-3 h-px transition-colors"
            style={{
              backgroundColor:
                status === "completed" || status === "active"
                  ? "var(--text-muted)"
                  : "var(--border-muted)",
            }}
          />
          <svg
            className="w-2 h-2 -ml-0.5"
            viewBox="0 0 8 8"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            style={{
              color:
                status === "completed" || status === "active"
                  ? "var(--text-muted)"
                  : "var(--border-muted)",
            }}
          >
            <path d="M2 1l3 3-3 3" />
          </svg>
        </div>
      )}
    </div>
  );
};

// --- Main Component ---

const WorkflowVisualization: React.FC<WorkflowVisualizationProps> = ({
  projectId,
  currentStage,
  completedStages = [],
  failedStages = [],
  isAgentActive = false,
}) => {
  const [workflowConfig, setWorkflowConfig] =
    useState<WorkflowConfigResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Fetch workflow configuration
  useEffect(() => {
    const fetchConfig = async () => {
      try {
        setLoading(true);
        const config = await felixApi.getWorkflowConfig(projectId);
        setWorkflowConfig(config);
        setError(null);
      } catch (err) {
        console.error("Failed to load workflow config:", err);
        setError(
          err instanceof Error
            ? err.message
            : "Failed to load workflow configuration",
        );
      } finally {
        setLoading(false);
      }
    };

    fetchConfig();
  }, [projectId]);

  // Sort stages by order
  const sortedStages = useMemo(() => {
    if (!workflowConfig) return [];
    return [...workflowConfig.stages].sort((a, b) => a.order - b.order);
  }, [workflowConfig]);

  // Determine status for each stage
  const getStageStatus = (stage: WorkflowStage): StageStatus => {
    // If agent is not active, all stages are pending
    if (!isAgentActive) {
      return "pending";
    }

    // Check if this is the current active stage
    if (currentStage === stage.id) {
      return "active";
    }

    // Check if stage is in failed list
    if (failedStages.includes(stage.id)) {
      return "failed";
    }

    // Check if stage is in completed list
    if (completedStages.includes(stage.id)) {
      return "completed";
    }

    // Check if current stage exists in our config
    if (currentStage) {
      const currentStageIndex = sortedStages.findIndex(
        (s) => s.id === currentStage,
      );
      const thisStageIndex = sortedStages.findIndex((s) => s.id === stage.id);

      // If we couldn't find current stage, it's unknown
      if (currentStageIndex === -1) {
        // Current stage is not in config - show warning
        return "pending";
      }

      // Stages before current are completed
      if (thisStageIndex < currentStageIndex) {
        return "completed";
      }
    }

    return "pending";
  };

  // Check if current stage is unknown (not in config)
  const isCurrentStageUnknown = useMemo(() => {
    if (!currentStage || !isAgentActive) return false;
    return !sortedStages.some((s) => s.id === currentStage);
  }, [currentStage, sortedStages, isAgentActive]);

  // Loading state
  if (loading) {
    return (
      <div
        className="flex items-center justify-center p-4"
        style={{ backgroundColor: "var(--bg-surface)" }}
      >
        <div
          className="w-4 h-4 border-2 rounded-full animate-spin"
          style={{
            borderColor: "var(--border-muted)",
            borderTopColor: "var(--text-muted)",
          }}
        />
        <span className="ml-2 text-xs" style={{ color: "var(--text-muted)" }}>
          Loading workflow...
        </span>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div
        className="flex items-center justify-center p-4"
        style={{ backgroundColor: "var(--bg-surface)" }}
      >
        <span className="text-xs text-red-400">{error}</span>
      </div>
    );
  }

  // No config state
  if (!workflowConfig || sortedStages.length === 0) {
    return (
      <div
        className="flex items-center justify-center p-4"
        style={{ backgroundColor: "var(--bg-surface)" }}
      >
        <span className="text-xs" style={{ color: "var(--text-muted)" }}>
          No workflow data
        </span>
      </div>
    );
  }

  // Render workflow visualization
  return (
    <div className="px-4 py-1" style={{ backgroundColor: "var(--bg-base)" }}>
      {/* Unknown stage warning */}
      {isCurrentStageUnknown && currentStage && (
        <div className="mb-2 px-2 py-1 rounded bg-amber-500/10 border border-amber-500/20">
          <span className="text-[10px] text-amber-400">
            Unknown Stage: {currentStage}
          </span>
        </div>
      )}

      {/* Agent idle message */}
      {!isAgentActive && (
        <div
          className="mb-2 px-2 py-1 rounded"
          style={{ backgroundColor: "var(--bg-base)" }}
        >
          <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
            Agent idle - workflow inactive
          </span>
        </div>
      )}

      {/* Workflow stages - horizontal scrollable */}
      <div className="overflow-x-auto overflow-y-hidden custom-scrollbar">
        <div className="flex items-center min-w-max pb-1">
          {sortedStages.map((stage, index) => (
            <StageNode
              key={stage.id}
              stage={stage}
              status={getStageStatus(stage)}
              isLast={index === sortedStages.length - 1}
            />
          ))}
        </div>
      </div>
    </div>
  );
};

export default WorkflowVisualization;

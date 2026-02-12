import React, { useEffect, useState, useMemo } from "react";
import {
  felixApi,
  WorkflowStage,
  WorkflowConfigResponse,
} from "../services/felixApi";
import {
  Check,
  ChevronRight,
  HelpCircle,
  X,
  Target as IconTarget,
  Play as IconPlay,
  GitBranch as IconGitBranch,
  Folder as IconFolder,
  FileText as IconFileText,
  Cpu as IconCpu,
  FileCode as IconFileCode,
  Shield as IconShield,
  CheckSquare as IconCheckSquare,
  FlaskConical as IconFlask,
  GitCommit as IconGitCommit,
  CheckCircle as IconCheckCircle,
  BarChart as IconBarChart,
  Flag as IconFlag,
} from "lucide-react";

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
  <HelpCircle className={className} style={style} />
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
          border: "border-brand-500",
          bg: "bg-brand-500/20",
          iconColor: "text-brand-400",
          nameColor: "text-brand-400",
          animation: "animate-workflow-pulse",
          glow: "shadow-lg shadow-brand-500/30",
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
        <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-2 py-1 rounded text-[10px] whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity z-10 pointer-events-none bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-default)]">
          {stage.description}
          {stage.conditional && (
            <span className="ml-1 text-amber-400 text-[9px]">
              ({stage.conditional})
            </span>
          )}
        </div>

        {/* Node Container */}
        <div
          className={`flex flex-col items-center gap-1 p-2 rounded-lg transition-all duration-300 min-w-[52px] ${styles.animation} ${styles.glow} ${
            isPending
              ? "bg-[var(--bg-surface)] border border-[var(--border-muted)]"
              : `border ${styles.border} ${styles.bg}`
          }`}
        >
          {/* Icon with optional overlay */}
          <div className="relative">
            <IconComponent
              className={`w-4 h-4 transition-colors ${styles.iconColor} ${isPending ? "text-[var(--text-faint)]" : ""}`}
            />
            {/* Status overlay */}
            {status === "completed" && (
              <div className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-emerald-500 flex items-center justify-center">
                <Check className="w-1.5 h-1.5 text-white" strokeWidth={4} />
              </div>
            )}
            {status === "failed" && (
              <div className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-red-500 flex items-center justify-center">
                <X className="w-1.5 h-1.5 text-white" strokeWidth={4} />
              </div>
            )}
          </div>

          {/* Stage Name */}
          <span
            className={`text-[9px] font-medium text-center leading-tight ${styles.nameColor} ${
              isPending ? "text-[var(--text-muted)]" : ""
            }`}
          >
            {stage.name}
          </span>
        </div>
      </div>

      {/* Connector Arrow */}
      {!isLast && (
        <div className="flex items-center px-0.5">
          <div
            className={`w-3 h-px transition-colors ${
              status === "completed" || status === "active"
                ? "bg-[var(--text-muted)]"
                : "bg-[var(--border-muted)]"
            }`}
          />
          <ChevronRight
            className={`w-2 h-2 -ml-0.5 ${
              status === "completed" || status === "active"
                ? "text-[var(--text-muted)]"
                : "text-[var(--border-muted)]"
            }`}
            strokeWidth={1.5}
          />
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
      <div className="flex items-center justify-center p-4 bg-[var(--bg-surface)]">
        <div className="w-4 h-4 border-2 border-[var(--border-muted)] border-t-[var(--text-muted)] rounded-full animate-spin" />
        <span className="ml-2 text-xs text-[var(--text-muted)]">
          Loading workflow...
        </span>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="flex items-center justify-center p-4 bg-[var(--bg-surface)]">
        <span className="text-xs text-red-400">{error}</span>
      </div>
    );
  }

  // No config state
  if (!workflowConfig || sortedStages.length === 0) {
    return (
      <div className="flex items-center justify-center p-4 bg-[var(--bg-surface)]">
        <span className="text-xs text-[var(--text-muted)]">
          No workflow data
        </span>
      </div>
    );
  }

  // Render workflow visualization
  return (
    <div className="px-4 py-1 bg-[var(--bg-base)]">
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
        <div className="mb-2 px-2 py-1 rounded bg-[var(--bg-base)]">
          <span className="text-[10px] text-[var(--text-muted)]">
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

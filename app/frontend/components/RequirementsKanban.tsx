import React, { useState, useEffect, useMemo, useRef } from "react";
import {
  felixApi,
  Requirement,
  RequirementsData,
  RequirementStatusResponse,
} from "../services/felixApi";
import { IconPlus, IconFileText } from "./Icons";
import RequirementDetailSlideOut from "./RequirementDetailSlideOut";
import {
  hasIncompleteDependencies,
  getIncompleteDependencies,
  formatIncompleteDependenciesTooltip,
} from "../utils/dependencies";

// Requirement status columns matching the felix/requirements.json schema
type RequirementStatus =
  | "draft"
  | "planned"
  | "in_progress"
  | "complete"
  | "blocked"
  | "done";

interface Column {
  status: RequirementStatus;
  label: string;
  color: string;
  bgColor: string;
  borderColor: string;
}

const COLUMNS: Column[] = [
  {
    status: "draft",
    label: "Draft",
    color: "bg-slate-500",
    bgColor: "bg-slate-500/10",
    borderColor: "border-slate-500/20",
  },
  {
    status: "planned",
    label: "Planned",
    color: "bg-blue-500",
    bgColor: "bg-blue-500/10",
    borderColor: "border-blue-500/20",
  },
  {
    status: "in_progress",
    label: "In Progress",
    color: "bg-amber-500",
    bgColor: "bg-amber-500/10",
    borderColor: "border-amber-500/20",
  },
  {
    status: "complete",
    label: "Complete",
    color: "bg-emerald-500",
    bgColor: "bg-emerald-500/10",
    borderColor: "border-emerald-500/20",
  },
  {
    status: "blocked",
    label: "Blocked",
    color: "bg-red-500",
    bgColor: "bg-red-500/10",
    borderColor: "border-red-500/20",
  },
  {
    status: "done",
    label: "Done",
    color: "bg-purple-500",
    bgColor: "bg-purple-500/10",
    borderColor: "border-purple-500/20",
  },
];

const PRIORITY_STYLES: Record<
  string,
  { bg: string; text: string; border: string }
> = {
  critical: {
    bg: "bg-red-500/10",
    text: "text-red-400",
    border: "border-red-500/20",
  },
  high: {
    bg: "bg-amber-500/10",
    text: "text-amber-400",
    border: "border-amber-500/20",
  },
  medium: {
    bg: "bg-blue-500/10",
    text: "text-blue-400",
    border: "border-blue-500/20",
  },
  low: {
    bg: "bg-slate-500/10",
    text: "text-slate-400",
    border: "border-slate-500/20",
  },
};

// Sticky Drop Zones Component
interface StickyDropZonesProps {
  visibleColumns: Column[];
  draggedItem: Requirement | null;
  dragOverColumn: RequirementStatus | null;
  scrollOffset: number;
  onDragOver: (e: React.DragEvent, status: RequirementStatus) => void;
  onDragLeave: () => void;
  onDrop: (e: React.DragEvent, status: RequirementStatus) => void;
}

const StickyDropZones: React.FC<StickyDropZonesProps> = ({
  visibleColumns,
  draggedItem,
  dragOverColumn,
  scrollOffset,
  onDragOver,
  onDragLeave,
  onDrop,
}) => {
  if (!draggedItem) return null;

  return (
    <div
      className="fixed top-0 left-0 right-0 z-50 theme-bg-base/95 backdrop-blur-sm border-b theme-border transition-all duration-300 ease-out"
      style={{
        transform: draggedItem ? "translateY(0)" : "translateY(-100%)",
        opacity: draggedItem ? 1 : 0,
      }}
    >
      <div className="flex gap-6 px-6 py-3 overflow-x-auto">
        {/* Adjust for scroll offset */}
        <div
          style={{ transform: `translateX(-${scrollOffset}px)` }}
          className="flex gap-6"
        >
          {visibleColumns.map((column) => {
            const isDropTarget = dragOverColumn === column.status;
            const isCurrentColumn = draggedItem.status === column.status;

            return (
              <div
                key={`sticky-${column.status}`}
                className={`
                  flex-shrink-0 w-80 h-16 rounded-xl border-2 
                  flex items-center justify-center
                  transition-all duration-200 ease-in-out
                  ${column.bgColor} ${column.borderColor}
                  ${isDropTarget ? "border-felix-500/70 bg-felix-500/10 scale-105 shadow-lg" : ""}
                  ${isCurrentColumn ? "opacity-50 cursor-not-allowed" : "cursor-pointer hover:border-felix-500/50"}
                  touch-manipulation min-h-[44px]
                `}
                style={{
                  boxShadow: isDropTarget
                    ? "0 8px 32px rgba(var(--felix-500), 0.3)"
                    : "var(--shadow-md)",
                }}
                onDragOver={(e) =>
                  !isCurrentColumn && onDragOver(e, column.status)
                }
                onDragLeave={onDragLeave}
                onDrop={(e) => !isCurrentColumn && onDrop(e, column.status)}
              >
                <div className="flex items-center gap-3">
                  <div
                    className={`w-3 h-3 rounded-full ${column.color} ${column.status === "in_progress" ? "animate-pulse" : ""}`}
                  />
                  <div className="text-center">
                    <h3 className="text-sm font-bold uppercase tracking-widest theme-text-secondary">
                      {column.label}
                    </h3>
                    <p className="text-xs theme-text-tertiary">
                      {isDropTarget
                        ? "Drop here"
                        : isCurrentColumn
                          ? "Current"
                          : "Drop to move"}
                    </p>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

interface RequirementsKanbanProps {
  projectId: string;
  onSelectRequirement?: (requirement: Requirement) => void;
}

const RequirementsKanban: React.FC<RequirementsKanbanProps> = ({
  projectId,
  onSelectRequirement,
}) => {
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draggedItem, setDraggedItem] = useState<Requirement | null>(null);
  const [dragOverColumn, setDragOverColumn] =
    useState<RequirementStatus | null>(null);
  const [scrollOffset, setScrollOffset] = useState(0);

  // Filter state
  const [priorityFilter, setPriorityFilter] = useState<string | null>(null);
  const [labelFilter, setLabelFilter] = useState<string | null>(null);
  const [showDone, setShowDone] = useState(false);

  // Requirement status info for each requirement (maps requirement id -> status info)
  // This includes plan info and spec modification timestamps for drift detection
  const [requirementStatusMap, setRequirementStatusMap] = useState<
    Record<string, RequirementStatusResponse>
  >({});

  // Selected requirement for slide-out detail view
  const [selectedRequirement, setSelectedRequirement] =
    useState<Requirement | null>(null);

  // Ref for the kanban container to track scroll position
  const kanbanContainerRef = useRef<HTMLDivElement>(null);

  // Track horizontal scroll position for sticky zones alignment
  useEffect(() => {
    const container = kanbanContainerRef.current;
    if (!container) return;

    const handleScroll = () => {
      setScrollOffset(container.scrollLeft);
    };

    container.addEventListener("scroll", handleScroll);
    return () => container.removeEventListener("scroll", handleScroll);
  }, []);

  // Fetch requirement status for all requirements that might have plans
  // This includes both plan info and spec modification times for drift detection
  useEffect(() => {
    const fetchRequirementStatus = async () => {
      if (!projectId || requirements.length === 0) return;

      // Only fetch for requirements that might have plans
      const relevantReqs = requirements.filter(
        (req) =>
          req.status === "planned" ||
          req.status === "in_progress" ||
          req.status === "complete",
      );

      const statusMap: Record<string, RequirementStatusResponse> = {};

      // Fetch status info for each relevant requirement
      await Promise.all(
        relevantReqs.map(async (req) => {
          try {
            const statusInfo = await felixApi.getRequirementStatus(
              projectId,
              req.id,
            );
            if (statusInfo.has_plan) {
              statusMap[req.id] = statusInfo;
            }
          } catch (err) {
            console.warn(
              `Failed to fetch requirement status for ${req.id}:`,
              err,
            );
          }
        }),
      );

      setRequirementStatusMap(statusMap);
    };

    fetchRequirementStatus();
  }, [projectId, requirements]);

  // Fetch requirements on mount and when projectId changes
  useEffect(() => {
    const fetchRequirements = async () => {
      if (!projectId) return;

      setLoading(true);
      setError(null);

      try {
        const data = await felixApi.getRequirements(projectId);
        setRequirements(data.requirements || []);
      } catch (err) {
        console.error("Failed to fetch requirements:", err);
        setError(
          err instanceof Error ? err.message : "Failed to fetch requirements",
        );
      } finally {
        setLoading(false);
      }
    };

    fetchRequirements();
  }, [projectId]);

  // Get all unique labels for filter dropdown
  const allLabels = React.useMemo(() => {
    const labels = new Set<string>();
    requirements.forEach((req) =>
      req.labels?.forEach((label) => labels.add(label)),
    );
    return Array.from(labels).sort();
  }, [requirements]);

  // Get all unique priorities for filter dropdown
  const allPriorities = React.useMemo(() => {
    const priorities = new Set<string>();
    requirements.forEach((req) => priorities.add(req.priority));
    return Array.from(priorities).sort((a, b) => {
      const order = ["critical", "high", "medium", "low"];
      return order.indexOf(a) - order.indexOf(b);
    });
  }, [requirements]);

  // Filter requirements
  const filteredRequirements = React.useMemo(() => {
    return requirements.filter((req) => {
      if (priorityFilter && req.priority !== priorityFilter) return false;
      if (labelFilter && !req.labels?.includes(labelFilter)) return false;
      return true;
    });
  }, [requirements, priorityFilter, labelFilter]);

  // Visible columns based on showDone filter
  const visibleColumns = React.useMemo(() => {
    return COLUMNS.filter((col) => showDone || col.status !== "done");
  }, [showDone]);

  // Get requirements for a specific column
  const getColumnRequirements = (status: RequirementStatus) => {
    return filteredRequirements.filter((req) => req.status === status);
  };

  // Drag handlers
  const handleDragStart = (e: React.DragEvent, requirement: Requirement) => {
    setDraggedItem(requirement);
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", requirement.id);
  };

  const handleDragOver = (e: React.DragEvent, status: RequirementStatus) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    setDragOverColumn(status);
  };

  const handleDragLeave = () => {
    setDragOverColumn(null);
  };

  const handleDrop = async (
    e: React.DragEvent,
    newStatus: RequirementStatus,
  ) => {
    e.preventDefault();
    setDragOverColumn(null);

    if (!draggedItem || draggedItem.status === newStatus) {
      setDraggedItem(null);
      return;
    }

    // Optimistically update the UI
    const updatedRequirements = requirements.map((req) =>
      req.id === draggedItem.id
        ? {
            ...req,
            status: newStatus,
            updated_at: new Date().toISOString().split("T")[0],
          }
        : req,
    );
    setRequirements(updatedRequirements);
    setDraggedItem(null);

    // Persist the change to the backend
    try {
      await felixApi.updateRequirements(projectId, updatedRequirements);
    } catch (err) {
      console.error("Failed to update requirements:", err);
      // Revert on error - refetch from server
      try {
        const data = await felixApi.getRequirements(projectId);
        setRequirements(data.requirements || []);
      } catch {
        // If refetch fails, show error
        setError("Failed to save changes. Please refresh the page.");
      }
    }
  };

  const handleDragEnd = () => {
    setDraggedItem(null);
    setDragOverColumn(null);
  };

  // Check if a requirement is blocked due to incomplete dependencies
  // Uses the dependency utility that correctly recognizes both 'done' and 'complete' as valid states
  const checkBlockedByDependency = (requirement: Requirement): boolean => {
    return hasIncompleteDependencies(requirement, requirements);
  };

  // Get incomplete dependencies for a requirement (memoized per requirement)
  const getIncompleteDepsList = (requirement: Requirement): Requirement[] => {
    return getIncompleteDependencies(requirement, requirements);
  };

  // Format a Unix timestamp (seconds since epoch) to a readable date string
  const formatTimestamp = (timestamp: string | null): string | null => {
    if (!timestamp) return null;
    try {
      // The backend returns file modification time as a float string (Unix timestamp)
      const unixTime = parseFloat(timestamp);
      if (isNaN(unixTime)) return null;
      const date = new Date(unixTime * 1000);
      return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch {
      return null;
    }
  };

  // Get plan info for a requirement and check if spec was modified after plan
  const getPlanTimestampInfo = (
    requirementId: string,
  ): {
    planTime: string | null;
    specModifiedAfterPlan: boolean;
    hasPlan: boolean;
  } => {
    const statusInfo = requirementStatusMap[requirementId];
    if (!statusInfo || !statusInfo.has_plan) {
      return { planTime: null, specModifiedAfterPlan: false, hasPlan: false };
    }

    const planTime = formatTimestamp(statusInfo.plan_modified_at);

    // Check if spec was modified after plan was generated
    let specModifiedAfterPlan = false;
    if (statusInfo.plan_modified_at && statusInfo.spec_modified_at) {
      const planModTime = parseFloat(statusInfo.plan_modified_at);
      const specModTime = parseFloat(statusInfo.spec_modified_at);
      // If spec was modified after plan, there's drift
      specModifiedAfterPlan =
        !isNaN(planModTime) && !isNaN(specModTime) && specModTime > planModTime;
    }

    return {
      planTime,
      specModifiedAfterPlan,
      hasPlan: true,
    };
  };

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center theme-bg-deepest">
        <div className="flex flex-col items-center gap-4">
          <div className="w-8 h-8 border-2 border-felix-500/30 border-t-felix-500 rounded-full animate-spin" />
          <span className="text-xs font-mono theme-text-muted uppercase tracking-widest">
            Loading requirements...
          </span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex-1 flex items-center justify-center theme-bg-deepest">
        <div className="bg-red-500/10 border border-red-500/20 rounded-xl px-6 py-4 text-center max-w-md">
          <span className="text-xs font-bold text-red-400 uppercase">
            Error Loading Requirements
          </span>
          <p className="text-sm text-red-300 mt-2">{error}</p>
          <button
            onClick={() => window.location.reload()}
            className="mt-4 px-4 py-2 text-xs font-bold text-red-400 border border-red-500/20 rounded-lg hover:bg-red-500/10 transition-colors"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col theme-bg-deepest overflow-hidden">
      {/* Sticky Drop Zones */}
      <StickyDropZones
        visibleColumns={visibleColumns}
        draggedItem={draggedItem}
        dragOverColumn={dragOverColumn}
        scrollOffset={scrollOffset}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      />

      {/* Filter bar */}
      <div
        className="h-12 border-b theme-border flex items-center px-6 gap-4 theme-bg-base/50 flex-shrink-0"
        style={{
          backgroundColor:
            "color-mix(in srgb, var(--bg-base) 50%, transparent)",
        }}
      >
        <span className="text-[10px] font-bold theme-text-muted uppercase tracking-widest">
          Filters:
        </span>

        {/* Priority filter */}
        <select
          value={priorityFilter || ""}
          onChange={(e) => setPriorityFilter(e.target.value || null)}
          className="theme-bg-elevated border theme-border rounded-lg px-3 py-1.5 text-xs theme-text-secondary outline-none focus:border-felix-500/50 cursor-pointer"
        >
          <option value="">All Priorities</option>
          {allPriorities.map((priority) => (
            <option key={priority} value={priority}>
              {priority.charAt(0).toUpperCase() + priority.slice(1)}
            </option>
          ))}
        </select>

        {/* Label filter */}
        <select
          value={labelFilter || ""}
          onChange={(e) => setLabelFilter(e.target.value || null)}
          className="theme-bg-elevated border theme-border rounded-lg px-3 py-1.5 text-xs theme-text-secondary outline-none focus:border-felix-500/50 cursor-pointer"
        >
          <option value="">All Labels</option>
          {allLabels.map((label) => (
            <option key={label} value={label}>
              {label}
            </option>
          ))}
        </select>

        {/* Clear filters button */}
        {(priorityFilter || labelFilter) && (
          <button
            onClick={() => {
              setPriorityFilter(null);
              setLabelFilter(null);
            }}
            className="text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors"
          >
            Clear
          </button>
        )}

        {/* Show Done toggle */}
        <label className="flex items-center gap-2 cursor-pointer ml-4">
          <input
            type="checkbox"
            checked={showDone}
            onChange={(e) => setShowDone(e.target.checked)}
            className="w-3.5 h-3.5 rounded border theme-border bg-transparent checked:bg-purple-500 checked:border-purple-500 cursor-pointer accent-purple-500"
          />
          <span
            className="text-[10px] font-bold theme-text-muted uppercase tracking-widest"
            title="Done = reviewed and accepted, ready for production"
          >
            Show Done
          </span>
        </label>

        <div className="flex-1" />

        {/* Requirements count */}
        <span className="text-[10px] font-mono theme-text-tertiary">
          {filteredRequirements.length} / {requirements.length} requirements
        </span>
      </div>

      {/* Kanban columns */}
      <div
        ref={kanbanContainerRef}
        className="flex-1 flex gap-6 p-6 overflow-x-auto custom-scrollbar"
      >
        {visibleColumns.map((column) => {
          const columnRequirements = getColumnRequirements(column.status);
          const isDropTarget = dragOverColumn === column.status;

          return (
            <div
              key={column.status}
              className="flex-shrink-0 w-80 flex flex-col gap-4"
              onDragOver={(e) => handleDragOver(e, column.status)}
              onDragLeave={handleDragLeave}
              onDrop={(e) => handleDrop(e, column.status)}
            >
              {/* Column header */}
              <div className="flex items-center justify-between px-2">
                <div className="flex items-center gap-2">
                  <div
                    className={`w-2 h-2 rounded-full ${column.color} ${column.status === "in_progress" ? "animate-pulse" : ""}`}
                  />
                  <h3 className="text-xs font-bold uppercase tracking-widest theme-text-tertiary">
                    {column.label}
                  </h3>
                </div>
                <span className="text-[10px] font-mono theme-text-tertiary theme-bg-elevated px-1.5 py-0.5 rounded">
                  {columnRequirements.length}
                </span>
              </div>

              {/* Cards container */}
              <div
                className={`flex-1 space-y-3 min-h-[200px] rounded-xl transition-colors ${
                  isDropTarget
                    ? "theme-bg-surface border-2 border-dashed border-felix-500/30"
                    : ""
                }`}
                style={
                  isDropTarget
                    ? {
                        backgroundColor:
                          "color-mix(in srgb, var(--bg-surface) 30%, transparent)",
                      }
                    : undefined
                }
              >
                {columnRequirements.map((requirement) => {
                  const priorityStyle =
                    PRIORITY_STYLES[requirement.priority] ||
                    PRIORITY_STYLES.medium;
                  const incompleteDeps = getIncompleteDepsList(requirement);
                  const hasBlockedDeps = incompleteDeps.length > 0;
                  const isDragging = draggedItem?.id === requirement.id;
                  const planTimestampInfo = getPlanTimestampInfo(
                    requirement.id,
                  );
                  const depsTooltip = hasBlockedDeps
                    ? `Incomplete dependencies:\n${formatIncompleteDependenciesTooltip(incompleteDeps)}`
                    : "";

                  return (
                    <div
                      key={requirement.id}
                      draggable
                      onDragStart={(e) => handleDragStart(e, requirement)}
                      onDragEnd={handleDragEnd}
                      onClick={() => {
                        setSelectedRequirement(requirement);
                        onSelectRequirement?.(requirement);
                      }}
                      className={`
                        theme-bg-base border theme-border p-4 rounded-xl 
                        hover:border-felix-600/40 transition-all cursor-grab group 
                        ${isDragging ? "opacity-50 scale-95" : ""}
                        ${hasBlockedDeps && requirement.status !== "blocked" ? "border-l-2 border-l-amber-500/50" : ""}
                      `}
                      style={{ boxShadow: "var(--shadow-lg)" }}
                    >
                      {/* Header row: ID + Priority + In-Progress Indicator */}
                      <div className="flex justify-between items-start mb-2">
                        <div className="flex items-center gap-2">
                          <span className="text-[10px] font-mono font-bold text-felix-400 bg-felix-500/10 px-2 py-0.5 rounded border border-felix-500/20">
                            {requirement.id}
                          </span>
                          {/* In-progress indicator for actively worked on requirements */}
                          {requirement.status === "in_progress" && (
                            <div className="flex items-center gap-1.5 px-1.5 py-0.5 rounded bg-amber-500/10 border border-amber-500/20">
                              <div className="w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse shadow-lg shadow-amber-500/50" />
                              <span className="text-[8px] font-bold text-amber-400 uppercase tracking-wide">
                                Active
                              </span>
                            </div>
                          )}
                        </div>
                        <span
                          className={`text-[9px] font-bold px-1.5 py-0.5 rounded uppercase ${priorityStyle.bg} ${priorityStyle.text} border ${priorityStyle.border}`}
                        >
                          {requirement.priority}
                        </span>
                      </div>

                      {/* Title */}
                      <h4 className="text-sm font-semibold theme-text-primary mb-2 group-hover:text-felix-400 transition-colors line-clamp-2">
                        {requirement.title}
                      </h4>

                      {/* Dependencies warning with hover tooltip showing incomplete deps */}
                      {hasBlockedDeps && requirement.status !== "blocked" && (
                        <div
                          className="flex items-center gap-1.5 mb-2 text-[9px] text-amber-400 cursor-help"
                          title={depsTooltip}
                        >
                          <svg
                            className="w-3 h-3"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth="2"
                              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                            />
                          </svg>
                          <span>
                            ⚠️ {incompleteDeps.length} incomplete{" "}
                            {incompleteDeps.length === 1
                              ? "dependency"
                              : "dependencies"}
                          </span>
                        </div>
                      )}

                      {/* Labels */}
                      {requirement.labels && requirement.labels.length > 0 && (
                        <div className="flex flex-wrap gap-1.5 mb-2">
                          {requirement.labels.map((label) => (
                            <span
                              key={label}
                              className="text-[9px] font-mono theme-text-tertiary border theme-border-muted px-1.5 py-0.5 rounded hover:theme-text-secondary transition-colors"
                            >
                              #{label}
                            </span>
                          ))}
                        </div>
                      )}

                      {/* Plan timestamp indicator with drift detection */}
                      {planTimestampInfo.hasPlan && (
                        <div className="flex items-center gap-2 mb-2 text-[9px]">
                          {/* Drift warning indicator - spec modified after plan */}
                          {planTimestampInfo.specModifiedAfterPlan ? (
                            <div className="flex items-center gap-1.5 px-1.5 py-0.5 rounded bg-orange-500/10 border border-orange-500/30">
                              <svg
                                className="w-3 h-3 text-orange-400"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                  strokeWidth="2"
                                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                                />
                              </svg>
                              <span className="text-orange-400 font-mono">
                                Spec changed • Plan stale
                              </span>
                            </div>
                          ) : (
                            <div className="flex items-center gap-1.5 px-1.5 py-0.5 rounded bg-blue-500/10 border border-blue-500/20">
                              <svg
                                className="w-3 h-3 text-blue-400"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                  strokeWidth="2"
                                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                                />
                              </svg>
                              <span className="text-blue-400 font-mono">
                                Plan:{" "}
                                {planTimestampInfo.planTime || "Available"}
                              </span>
                            </div>
                          )}
                        </div>
                      )}

                      {/* Footer: Updated date + view spec link */}
                      <div className="flex justify-between items-center pt-2 border-t theme-border-muted">
                        <span className="text-[9px] font-mono theme-text-tertiary">
                          Updated: {requirement.updated_at}
                        </span>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedRequirement(requirement);
                            onSelectRequirement?.(requirement);
                          }}
                          className="text-[9px] font-bold theme-text-muted hover:text-felix-400 transition-colors flex items-center gap-1"
                        >
                          <IconFileText className="w-3 h-3" />
                          View Spec
                        </button>
                      </div>
                    </div>
                  );
                })}

                {/* Empty state for column */}
                {columnRequirements.length === 0 && (
                  <div
                    className={`
                    flex flex-col items-center justify-center py-8 text-center
                    border border-dashed rounded-xl
                    ${isDropTarget ? "border-felix-500/50 bg-felix-500/5" : "theme-border-muted"}
                  `}
                  >
                    <span className="text-[10px] font-mono theme-text-tertiary uppercase">
                      {isDropTarget ? "Drop here" : "No requirements"}
                    </span>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Requirement Detail Slide-Out */}
      <RequirementDetailSlideOut
        projectId={projectId}
        requirement={selectedRequirement}
        onClose={() => setSelectedRequirement(null)}
      />
    </div>
  );
};

export default RequirementsKanban;

import React, { useState, useEffect, useMemo, useRef } from "react";
import {
  felixApi,
  Requirement,
  RequirementsData,
  RequirementStatusResponse,
} from "../services/felixApi";
import { Plus as IconPlus, FileText as IconFileText } from "lucide-react";
import RequirementDetailSlideOut from "./RequirementDetailSlideOut";
import {
  hasIncompleteDependencies,
  getIncompleteDependencies,
  formatIncompleteDependenciesTooltip,
} from "../utils/dependencies";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { Card } from "./ui/card";
import { Switch } from "./ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { cn } from "../lib/utils";

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
  variant:
    | "default"
    | "secondary"
    | "destructive"
    | "outline"
    | "success"
    | "warning";
}

const COLUMNS: Column[] = [
  {
    status: "draft",
    label: "Draft",
    variant: "secondary",
  },
  {
    status: "planned",
    label: "Planned",
    variant: "default", // Using default/brand for Planned
  },
  {
    status: "in_progress",
    label: "In Progress",
    variant: "warning",
  },
  {
    status: "complete",
    label: "Complete",
    variant: "success",
  },
  {
    status: "blocked",
    label: "Blocked",
    variant: "destructive",
  },
  {
    status: "done",
    label: "Done",
    variant: "outline", // Distinct from Complete
  },
];

const getPriorityVariant = (priority: string) => {
  switch (priority) {
    case "critical":
      return "destructive";
    case "high":
      return "warning";
    case "medium":
      return "default"; // Brand/Blue equivalent
    case "low":
      return "secondary";
    default:
      return "outline";
  }
};

const getStatusColor = (status: RequirementStatus): string => {
  switch (status) {
    case "draft":
      return "var(--status-draft)";
    case "planned":
      return "var(--status-planned)";
    case "in_progress":
      return "var(--status-in-progress)";
    case "complete":
      return "var(--status-complete)";
    case "done":
      return "var(--status-done)";
    case "blocked":
      return "var(--status-blocked)";
    default:
      return "var(--text-muted)";
  }
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

  const getDropZoneStyles = (variant: string, isDropTarget: boolean) => {
    // Base styles
    let styles = "border-2 ";

    if (isDropTarget) {
      // Active drop target styles
      switch (variant) {
        case "default":
          return (
            styles +
            "border-[var(--brand-500)]/70 bg-[var(--brand-500)]/10 text-[var(--brand-500)]"
          );
        case "secondary":
          return (
            styles +
            "border-[var(--border-strong)] bg-[var(--bg-surface-200)] text-[var(--text)]"
          );
        case "destructive":
          return (
            styles +
            "border-[var(--destructive-500)]/70 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]"
          );
        case "warning":
          return (
            styles +
            "border-[var(--warning-500)]/70 bg-[var(--warning-500)]/10 text-[var(--warning-500)]"
          );
        case "success":
          return (
            styles +
            "border-[var(--brand-500)]/70 bg-[var(--brand-500)]/10 text-[var(--brand-500)]"
          );
        default:
          return (
            styles +
            "border-[var(--brand-500)]/70 bg-[var(--brand-500)]/10 text-[var(--brand-500)]"
          );
      }
    } else {
      // Inactive styles
      switch (variant) {
        case "default":
          return (
            styles + "border-[var(--brand-500)]/20 bg-[var(--brand-500)]/5"
          );
        case "secondary":
          return (
            styles + "border-[var(--border-muted)] bg-[var(--bg-surface-100)]"
          );
        case "destructive":
          return (
            styles +
            "border-[var(--destructive-500)]/20 bg-[var(--destructive-500)]/5"
          );
        case "warning":
          return (
            styles + "border-[var(--warning-500)]/20 bg-[var(--warning-500)]/5"
          );
        case "success":
          return (
            styles + "border-[var(--brand-500)]/20 bg-[var(--brand-500)]/5"
          );
        default:
          return (
            styles + "border-[var(--border-muted)] bg-[var(--bg-surface-100)]"
          );
      }
    }
  };

  return (
    <div
      className="fixed top-0 left-0 right-0 z-50 bg-[var(--bg-base)]/95 backdrop-blur-sm border-b border-[var(--border-muted)] transition-all duration-300 ease-out"
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
                className={cn(
                  "flex-shrink-0 w-80 h-16 rounded-xl flex items-center justify-center transition-all duration-200 ease-in-out touch-manipulation min-h-[44px]",
                  getDropZoneStyles(column.variant, isDropTarget),
                  isDropTarget ? "scale-105 shadow-lg" : "",
                  isCurrentColumn
                    ? "opacity-50 cursor-not-allowed"
                    : "cursor-pointer hover:border-opacity-50",
                )}
                style={{
                  boxShadow: isDropTarget
                    ? "0 8px 32px rgba(0, 0, 0, 0.2)"
                    : "none",
                }}
                onDragOver={(e) =>
                  !isCurrentColumn && onDragOver(e, column.status)
                }
                onDragLeave={onDragLeave}
                onDrop={(e) => !isCurrentColumn && onDrop(e, column.status)}
              >
                <div className="flex items-center gap-3">
                  <Badge
                    variant={column.variant}
                    className="pointer-events-none"
                  >
                    {column.label}
                  </Badge>
                  <div className="text-center">
                    <p className="text-xs text-[var(--text-muted)]">
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

  // Compact view state - persisted to localStorage
  const [isCompactView, setIsCompactView] = useState<boolean>(() => {
    // Initialize from localStorage on first render
    if (typeof window !== "undefined") {
      const stored = localStorage.getItem("felix-kanban-compact-view");
      return stored === "true";
    }
    return false;
  });

  // Persist compact view preference to localStorage
  useEffect(() => {
    localStorage.setItem("felix-kanban-compact-view", String(isCompactView));
  }, [isCompactView]);

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
  // PERFORMANCE: Disabled until backend implements requirement status endpoint (S-0032)
  // This used to make N individual API calls per requirement, but the endpoint returns 501.
  // The status map is used for plan drift detection. Re-enable after database migration.
  // useEffect(() => {
  //   const fetchRequirementStatus = async () => {
  //     if (!projectId || requirements.length === 0) return;

  //     // Only fetch for requirements that might have plans
  //     const relevantReqs = requirements.filter(
  //       (req) =>
  //         req.status === "planned" ||
  //         req.status === "in_progress" ||
  //         req.status === "complete",
  //     );

  //     const statusMap: Record<string, RequirementStatusResponse> = {};

  //     // Fetch status info for each relevant requirement
  //     await Promise.all(
  //       relevantReqs.map(async (req) => {
  //         try {
  //           const statusInfo = await felixApi.getRequirementStatus(
  //             projectId,
  //             req.id,
  //           );
  //           if (statusInfo.has_plan) {
  //             statusMap[req.id] = statusInfo;
  //           }
  //         } catch (err) {
  //           console.warn(
  //             `Failed to fetch requirement status for ${req.id}:`,
  //             err,
  //           );
  //         }
  //       }),
  //     );

  //     setRequirementStatusMap(statusMap);
  //   };

  //   fetchRequirementStatus();
  // }, [projectId, requirements]);

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
    requirement: Requirement,
  ): {
    planTime: string | null;
    specModifiedAfterPlan: boolean;
    hasPlan: boolean;
  } => {
    if (!requirement.has_plan || !requirement.plan_modified_at) {
      return { planTime: null, specModifiedAfterPlan: false, hasPlan: false };
    }

    const planTime = formatTimestamp(requirement.plan_modified_at);

    // Check if spec was modified after plan was generated
    let specModifiedAfterPlan = false;
    if (requirement.plan_modified_at && requirement.spec_modified_at) {
      const planModTime = parseFloat(requirement.plan_modified_at);
      const specModTime = parseFloat(requirement.spec_modified_at);
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
      <div className="flex-1 flex items-center justify-center bg-[var(--bg-base)]">
        <div className="flex flex-col items-center gap-4">
          <div className="w-8 h-8 border-2 border-[var(--brand-500)]/30 border-t-[var(--brand-500)] rounded-full animate-spin" />
          <span className="text-xs font-mono text-[var(--text-muted)] uppercase tracking-widest">
            Loading requirements...
          </span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex-1 flex items-center justify-center bg-[var(--bg-base)]">
        <div className="bg-[var(--destructive-500)]/10 border border-[var(--destructive-500)]/20 rounded-xl px-6 py-4 text-center max-w-md">
          <span className="text-xs font-bold text-[var(--destructive-400)] uppercase">
            Error Loading Requirements
          </span>
          <p className="text-sm text-[var(--destructive-300)] mt-2">{error}</p>
          <Button
            variant="ghost"
            onClick={() => window.location.reload()}
            className="mt-4 text-xs font-bold text-[var(--destructive-400)] hover:text-[var(--destructive-300)] hover:bg-[var(--destructive-500)]/10"
          >
            Retry
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden bg-[var(--bg-base)]">
      {/* Sticky Drop Zones - Always show all columns including Done */}
      <StickyDropZones
        visibleColumns={COLUMNS}
        draggedItem={draggedItem}
        dragOverColumn={dragOverColumn}
        scrollOffset={scrollOffset}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      />

      {/* Filter bar */}
      <div className="h-12 border-b border-[var(--border-muted)] flex items-center px-6 gap-4 bg-[var(--bg-surface-100)]/50 flex-shrink-0 backdrop-blur-sm">
        <span className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-widest">
          Filters:
        </span>

        {/* Priority filter */}
        <Select
          value={priorityFilter || "all"}
          onValueChange={(val) => setPriorityFilter(val === "all" ? null : val)}
        >
          <SelectTrigger className="w-[130px] h-7 text-xs bg-[var(--bg-surface-100)] border-[var(--border-muted)]">
            <SelectValue placeholder="All Priorities" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Priorities</SelectItem>
            {allPriorities.map((priority) => (
              <SelectItem key={priority} value={priority}>
                {priority.charAt(0).toUpperCase() + priority.slice(1)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {/* Label filter */}
        <Select
          value={labelFilter || "all"}
          onValueChange={(val) => setLabelFilter(val === "all" ? null : val)}
        >
          <SelectTrigger className="w-[130px] h-7 text-xs bg-[var(--bg-surface-100)] border-[var(--border-muted)]">
            <SelectValue placeholder="All Labels" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Labels</SelectItem>
            {allLabels.map((label) => (
              <SelectItem key={label} value={label}>
                {label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {/* Clear filters button */}
        {(priorityFilter || labelFilter) && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              setPriorityFilter(null);
              setLabelFilter(null);
            }}
            className="h-7 px-2 text-[10px] font-bold text-[var(--text-muted)] hover:text-[var(--text)]"
          >
            Clear
          </Button>
        )}

        {/* Show Done toggle */}
        <div className="flex items-center gap-2 ml-4">
          <Switch
            checked={showDone}
            onCheckedChange={setShowDone}
            className="data-[state=checked]:bg-[var(--brand-500)]"
          />
          <span
            className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-widest cursor-pointer"
            onClick={() => setShowDone(!showDone)}
            title="Done = reviewed and accepted, ready for production"
          >
            Show Done
          </span>
        </div>

        {/* Compact View toggle */}
        <div className="flex items-center gap-2 ml-2">
          <Switch
            checked={isCompactView}
            onCheckedChange={setIsCompactView}
            className="data-[state=checked]:bg-[var(--brand-500)]"
          />
          <span
            className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-widest cursor-pointer"
            onClick={() => setIsCompactView(!isCompactView)}
            title="Compact view shows smaller cards with less information"
          >
            Compact View
          </span>
        </div>

        <div className="flex-1" />

        {/* Requirements count */}
        <Badge
          variant="outline"
          className="font-mono text-[var(--text-lighter)]"
        >
          {filteredRequirements.length} / {requirements.length} requirements
        </Badge>
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
              <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between px-2">
                  <span className="text-sm font-semibold text-[var(--text-primary)] uppercase tracking-wide">
                    {column.label}
                  </span>
                  <Badge
                    variant="outline"
                    className="text-[10px] font-mono text-[var(--text-muted)] bg-[var(--bg-surface-200)] border-[var(--border-muted)] px-1.5 py-0.5 rounded"
                  >
                    {columnRequirements.length}
                  </Badge>
                </div>
                {/* Solid color line */}
                <div
                  className="w-full rounded-full"
                  style={{
                    backgroundColor: getStatusColor(column.status),
                    height: "0.15rem",
                  }}
                />
              </div>

              {/* Cards container */}
              <div
                className={cn(
                  "flex-1 space-y-3 min-h-[200px] rounded-xl transition-colors",
                  isDropTarget
                    ? "bg-[var(--bg-surface-200)] border-2 border-dashed border-[var(--brand-500)]/30"
                    : "",
                )}
              >
                {columnRequirements.map((requirement) => {
                  const incompleteDeps = getIncompleteDepsList(requirement);
                  const hasBlockedDeps = incompleteDeps.length > 0;
                  const isDragging = draggedItem?.id === requirement.id;
                  const planTimestampInfo = getPlanTimestampInfo(requirement);
                  const depsTooltip = hasBlockedDeps
                    ? `Incomplete dependencies:\n${formatIncompleteDependenciesTooltip(incompleteDeps)}`
                    : "";

                  return (
                    <Card
                      key={requirement.id}
                      draggable
                      onDragStart={(e) => handleDragStart(e, requirement)}
                      onDragEnd={handleDragEnd}
                      onClick={() => {
                        setSelectedRequirement(requirement);
                        onSelectRequirement?.(requirement);
                      }}
                      className={cn(
                        "rounded-xl border cursor-grab group transition-all duration-200 bg-[var(--bg-surface-100)] border-[var(--border-muted)]",
                        "hover:border-[var(--brand-600)]/40 hover:shadow-md",
                        isCompactView ? "p-3" : "p-4",
                        isDragging ? "opacity-50 scale-95" : "shadow-sm",
                        hasBlockedDeps && requirement.status !== "blocked"
                          ? "border-l-2 border-l-[var(--warning-500)]/50"
                          : "",
                      )}
                    >
                      {/* Header row: ID + Priority + In-Progress Indicator */}
                      <div
                        className={`flex justify-between items-start ${isCompactView ? "mb-1" : "mb-2"}`}
                      >
                        <div className="flex items-center gap-2">
                          <span className="text-[10px] font-mono font-bold text-[var(--brand-400)] bg-[var(--brand-500)]/10 px-2 py-0.5 rounded border border-[var(--brand-500)]/20">
                            {requirement.id}
                          </span>
                          {/* In-progress indicator for actively worked on requirements */}
                          {requirement.status === "in_progress" && (
                            <div
                              className={`flex items-center gap-1.5 px-1.5 py-0.5 rounded bg-[var(--warning-500)]/10 border border-[var(--warning-500)]/20 ${isCompactView ? "scale-90" : ""}`}
                            >
                              <div className="w-1.5 h-1.5 rounded-full bg-[var(--warning-500)] animate-pulse shadow-lg shadow-[var(--warning-500)]/50" />
                              <span className="text-[8px] font-bold text-[var(--warning-400)] uppercase tracking-wide">
                                Active
                              </span>
                            </div>
                          )}
                        </div>
                        <Badge
                          variant={getPriorityVariant(requirement.priority)}
                          className={cn(
                            "font-bold uppercase",
                            isCompactView
                              ? "text-[8px] px-1.5 py-0 scale-90 origin-right"
                              : "text-[9px] px-1.5 py-0.5",
                          )}
                        >
                          {requirement.priority}
                        </Badge>
                      </div>

                      {/* Title */}
                      <h4
                        className={`font-semibold text-[var(--text-primary)] group-hover:text-[var(--brand-400)] transition-colors ${isCompactView ? "text-[13px] mb-1 line-clamp-1" : "text-sm mb-2 line-clamp-2"}`}
                      >
                        {requirement.title}
                      </h4>

                      {/* Dependencies warning with hover tooltip showing incomplete deps */}
                      {/* In compact mode: icon + count only; in normal mode: full text */}
                      {hasBlockedDeps && requirement.status !== "blocked" && (
                        <div
                          className={`flex items-center gap-1.5 text-[var(--warning-400)] cursor-help ${isCompactView ? "mb-0 text-[8px]" : "mb-2 text-[9px]"}`}
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
                          {isCompactView ? (
                            <span>⚠️ {incompleteDeps.length}</span>
                          ) : (
                            <span>
                              ⚠️ {incompleteDeps.length} incomplete{" "}
                              {incompleteDeps.length === 1
                                ? "dependency"
                                : "dependencies"}
                            </span>
                          )}
                        </div>
                      )}

                      {/* Labels - Animated hide/show with compact mode transition */}
                      {requirement.labels && requirement.labels.length > 0 && (
                        <div
                          className={`kanban-card-section kanban-card-section-hideable flex flex-wrap gap-1.5 ${isCompactView ? "" : "mb-2"}`}
                        >
                          {requirement.labels.map((label) => (
                            <span
                              key={label}
                              className="text-[9px] font-mono text-[var(--text-muted)] border border-[var(--border-muted)] px-1.5 py-0.5 rounded hover:text-[var(--text-primary)] transition-colors"
                            >
                              #{label}
                            </span>
                          ))}
                        </div>
                      )}

                      {/* Plan timestamp indicator with drift detection - Animated hide/show */}
                      {planTimestampInfo.hasPlan && (
                        <div
                          className={`kanban-card-section kanban-card-section-hideable flex items-center gap-2 text-[9px] ${isCompactView ? "" : "mb-2"}`}
                        >
                          {/* Drift warning indicator - spec modified after plan */}
                          {planTimestampInfo.specModifiedAfterPlan ? (
                            <div className="flex items-center gap-1.5 px-1.5 py-0.5 rounded bg-[var(--warning-500)]/10 border border-[var(--warning-500)]/30">
                              <svg
                                className="w-3 h-3 text-[var(--warning-400)]"
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
                              <span className="text-[var(--warning-400)] font-mono">
                                Spec changed • Plan stale
                              </span>
                            </div>
                          ) : (
                            <div className="flex items-center gap-1.5 px-1.5 py-0.5 rounded bg-[var(--brand-500)]/5 border border-[var(--brand-500)]/10">
                              <svg
                                className="w-3 h-3 text-[var(--brand-400)]"
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
                              <span className="text-[var(--brand-400)] font-mono">
                                Plan:{" "}
                                {planTimestampInfo.planTime || "Available"}
                              </span>
                            </div>
                          )}
                        </div>
                      )}

                      {/* Footer: Updated date + view spec link - Animated hide/show */}
                      <div
                        className={`kanban-card-section kanban-card-section-hideable flex justify-between items-center pt-2 border-t border-[var(--border-muted)] ${isCompactView ? "" : ""}`}
                      >
                        <span className="text-[9px] font-mono text-[var(--text-muted)]">
                          Updated: {requirement.updated_at}
                        </span>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedRequirement(requirement);
                            onSelectRequirement?.(requirement);
                          }}
                          className="h-auto p-0 text-[var(--text-muted)] hover:text-[var(--brand-400)] hover:bg-transparent font-bold text-[9px] flex items-center gap-1"
                        >
                          <IconFileText size={12} />
                          View Spec
                        </Button>
                      </div>
                    </Card>
                  );
                })}

                {/* Empty state for column */}
                {columnRequirements.length === 0 && (
                  <div
                    className={cn(
                      "flex flex-col items-center justify-center py-8 text-center border border-dashed rounded-xl transition-colors",
                      isDropTarget
                        ? "border-[var(--brand-500)]/50 bg-[var(--brand-500)]/5"
                        : "border-[var(--border-muted)]",
                    )}
                  >
                    <span className="text-[10px] font-mono text-[var(--text-muted)] uppercase">
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

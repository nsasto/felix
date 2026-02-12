export type RequirementStatus =
  | "draft"
  | "planned"
  | "in_progress"
  | "complete"
  | "blocked"
  | "done";

const normalizeRequirementStatus = (
  status: string | null | undefined,
): RequirementStatus | null => {
  if (!status) return null;
  const normalized =
    status === "running"
      ? "in_progress"
      : status === "completed"
        ? "complete"
        : status;
  return normalized as RequirementStatus;
};

const requirementStatusColors: Record<RequirementStatus, string> = {
  draft: "var(--status-draft)",
  planned: "var(--status-planned)",
  in_progress: "var(--status-in-progress)",
  complete: "var(--status-complete)",
  done: "var(--status-done)",
  blocked: "var(--status-blocked)",
};

export const getRequirementStatusColor = (status: string | null | undefined) => {
  const key = normalizeRequirementStatus(status);
  if (!key) return "var(--text-muted)";
  return requirementStatusColors[key] ?? "var(--text-muted)";
};

const requirementStatusBadgeClasses: Record<RequirementStatus, string> = {
  draft: "bg-[var(--status-draft)] border-[var(--status-draft)] text-white",
  planned: "bg-[var(--status-planned)] border-[var(--status-planned)] text-white",
  in_progress:
    "bg-[var(--status-in-progress)] border-[var(--status-in-progress)] text-white",
  complete: "bg-[var(--status-complete)] border-[var(--status-complete)] text-white",
  done: "bg-[var(--status-done)] border-[var(--status-done)] text-white",
  blocked: "bg-[var(--status-blocked)] border-[var(--status-blocked)] text-white",
};

const requirementStatusSoftBadgeClasses: Record<RequirementStatus, string> = {
  draft:
    "bg-[var(--status-draft)]/20 text-[var(--status-draft)] border-[var(--status-draft)]",
  planned:
    "bg-[var(--status-planned)]/20 text-[var(--status-planned)] border-[var(--status-planned)]",
  in_progress:
    "bg-[var(--status-in-progress)]/20 text-[var(--status-in-progress)] border-[var(--status-in-progress)]",
  complete:
    "bg-[var(--status-complete)]/20 text-[var(--status-complete)] border-[var(--status-complete)]",
  done:
    "bg-[var(--status-done)]/20 text-[var(--status-done)] border-[var(--status-done)]",
  blocked:
    "bg-[var(--status-blocked)]/20 text-[var(--status-blocked)] border-[var(--status-blocked)]",
};

const requirementStatusColorClasses: Record<RequirementStatus, string> = {
  draft: "bg-[var(--status-draft)]",
  planned: "bg-[var(--status-planned)]",
  in_progress: "bg-[var(--status-in-progress)]",
  complete: "bg-[var(--status-complete)]",
  done: "bg-[var(--status-done)]",
  blocked: "bg-[var(--status-blocked)]",
};

export const getRequirementStatusBadgeClass = (
  status: string | null | undefined,
) => {
  const key = normalizeRequirementStatus(status);
  if (!key) return "bg-[var(--text-muted)] border-[var(--text-muted)] text-white";
  return requirementStatusBadgeClasses[key];
};

export const getRequirementStatusSoftBadgeClass = (
  status: string | null | undefined,
) => {
  const key = normalizeRequirementStatus(status);
  if (!key)
    return "bg-[var(--text-muted)]/20 text-[var(--text-muted)] border-[var(--text-muted)]";
  return requirementStatusSoftBadgeClasses[key];
};

export const getRequirementStatusColorClass = (
  status: string | null | undefined,
) => {
  const key = normalizeRequirementStatus(status);
  if (!key) return "bg-[var(--text-muted)]";
  return requirementStatusColorClasses[key];
};

export const getRequirementPriorityVariant = (
  priority: string,
): "default" | "success" | "warning" | "destructive" => {
  switch (priority) {
    case "critical":
      return "destructive";
    case "high":
      return "warning";
    case "medium":
      return "default";
    case "low":
      return "default";
    default:
      return "default";
  }
};

export const getProjectStatusDotClass = (status: string | null): string => {
  switch (status?.toLowerCase()) {
    case "running":
      return "bg-[var(--brand-500)] animate-pulse";
    case "complete":
    case "done":
      return "bg-[var(--brand-500)]";
    case "blocked":
    case "error":
      return "bg-[var(--destructive-500)]";
    case "planned":
      return "bg-[var(--warning-500)]";
    default:
      return "bg-[var(--text-muted)]";
  }
};

export const getRunStatusVariant = (
  status: string,
): "success" | "warning" | "destructive" | "default" => {
  switch (status) {
    case "completed":
      return "success";
    case "running":
      return "warning";
    case "failed":
      return "destructive";
    case "cancelled":
      return "default";
    default:
      return "default";
  }
};

export const getRequirementStatusVariant = (status: string) => {
  switch (status.toLowerCase()) {
    case "completed":
    case "complete":
    case "done":
      return "success";
    case "running":
    case "in_progress":
      return "warning";
    case "blocked":
    case "failed":
      return "destructive";
    case "planned":
      return "default";
    default:
      return "secondary";
  }
};

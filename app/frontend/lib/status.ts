export type RequirementStatus =
  | "draft"
  | "planned"
  | "in_progress"
  | "complete"
  | "blocked"
  | "done";

const requirementStatusColors: Record<RequirementStatus, string> = {
  draft: "var(--status-draft)",
  planned: "var(--status-planned)",
  in_progress: "var(--status-in-progress)",
  complete: "var(--status-complete)",
  done: "var(--status-done)",
  blocked: "var(--status-blocked)",
};

export const getRequirementStatusColor = (status: string | null | undefined) => {
  if (!status) return "var(--text-muted)";
  const normalized =
    status === "running"
      ? "in_progress"
      : status === "completed"
        ? "complete"
        : status;
  const key = normalized as RequirementStatus;
  return requirementStatusColors[key] ?? "var(--text-muted)";
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

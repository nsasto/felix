import React from "react";
import RequirementsKanban from "../RequirementsKanban";
import ProjectRequiredState from "../ProjectRequiredState";

interface KanbanViewProps {
  projectId: string | null;
  onGoToProjects: () => void;
  onSelectRequirement: (req: { last_run_id?: string | null }) => void;
}

export default function KanbanView({
  projectId,
  onGoToProjects,
  onSelectRequirement,
}: KanbanViewProps) {
  if (!projectId) {
    return (
      <ProjectRequiredState
        message="Select a project to view requirements"
        onGoToProjects={onGoToProjects}
      />
    );
  }

  return (
    <RequirementsKanban
      projectId={projectId}
      onSelectRequirement={onSelectRequirement}
    />
  );
}

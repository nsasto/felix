import React from "react";
import PlanViewer from "../PlanViewer";
import ProjectRequiredState from "../ProjectRequiredState";

interface PlanViewProps {
  projectId: string | null;
  onGoToProjects: () => void;
}

export default function PlanView({ projectId, onGoToProjects }: PlanViewProps) {
  if (!projectId) {
    return (
      <ProjectRequiredState
        message="Select a project to view README"
        onGoToProjects={onGoToProjects}
      />
    );
  }

  return <PlanViewer projectId={projectId} onBack={onGoToProjects} />;
}

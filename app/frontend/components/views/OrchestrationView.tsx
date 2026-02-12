import React from "react";
import AgentDashboard from "../AgentDashboard";
import ProjectRequiredState from "../ProjectRequiredState";

interface OrchestrationViewProps {
  projectId: string | null;
  onGoToProjects: () => void;
}

export default function OrchestrationView({
  projectId,
  onGoToProjects,
}: OrchestrationViewProps) {
  if (!projectId) {
    return (
      <ProjectRequiredState
        message="Select a project to view agent dashboard"
        onGoToProjects={onGoToProjects}
      />
    );
  }

  return <AgentDashboard projectId={projectId} />;
}

import React from "react";
import ConfigPanel from "../ConfigPanel";
import ProjectRequiredState from "../ProjectRequiredState";

interface ConfigViewProps {
  projectId: string | null;
  onGoToProjects: () => void;
}

export default function ConfigView({
  projectId,
  onGoToProjects,
}: ConfigViewProps) {
  if (!projectId) {
    return (
      <ProjectRequiredState
        message="Select a project to view configuration"
        onGoToProjects={onGoToProjects}
      />
    );
  }

  return <ConfigPanel projectId={projectId} onClose={onGoToProjects} />;
}

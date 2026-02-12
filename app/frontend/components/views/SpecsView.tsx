import React from "react";
import SpecsEditor from "../SpecsEditor";
import ProjectRequiredState from "../ProjectRequiredState";

interface SpecsViewProps {
  projectId: string | null;
  onGoToProjects: () => void;
  onSelectSpec: (filename: string) => void;
}

export default function SpecsView({
  projectId,
  onGoToProjects,
  onSelectSpec,
}: SpecsViewProps) {
  if (!projectId) {
    return (
      <ProjectRequiredState
        message="Select a project to view specs"
        onGoToProjects={onGoToProjects}
      />
    );
  }

  return <SpecsEditor projectId={projectId} onSelectSpec={onSelectSpec} />;
}

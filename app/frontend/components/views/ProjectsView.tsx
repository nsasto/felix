import React from "react";
import { ProjectDetails } from "../../services/felixApi";
import ProjectSelector from "../ProjectSelector";
import ProjectDashboard from "../ProjectDashboard";

interface ProjectsViewProps {
  selectedProjectId: string | null;
  selectedProject: ProjectDetails | null;
  orgId: string | null;
  onSelectProject: (projectId: string, details: ProjectDetails) => void;
  onNavigate: (view: string) => void;
}

export default function ProjectsView({
  selectedProjectId,
  selectedProject,
  orgId,
  onSelectProject,
  onNavigate,
}: ProjectsViewProps) {
  if (selectedProjectId && selectedProject) {
    return (
      <ProjectDashboard
        projectId={selectedProjectId}
        project={selectedProject}
        onNavigate={onNavigate}
      />
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden bg-[var(--bg-base)] items-center">
      <div className="w-full max-w-6xl h-full px-6">
        <ProjectSelector
          selectedProjectId={selectedProjectId}
          orgId={orgId}
          onSelectProject={onSelectProject}
        />
      </div>
    </div>
  );
}

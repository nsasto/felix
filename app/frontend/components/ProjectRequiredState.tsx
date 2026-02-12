import React from "react";
import { Button } from "./ui/button";

interface ProjectRequiredStateProps {
  message: string;
  onGoToProjects: () => void;
}

export default function ProjectRequiredState({
  message,
  onGoToProjects,
}: ProjectRequiredStateProps) {
  return (
    <div
      className="flex-1 flex flex-col items-center justify-center text-center"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      <span className="text-sm" style={{ color: "var(--text-muted)" }}>
        {message}
      </span>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        onClick={onGoToProjects}
        className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors h-auto"
      >
        Go to Projects
      </Button>
    </div>
  );
}

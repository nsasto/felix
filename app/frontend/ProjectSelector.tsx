import React, { useEffect, useMemo, useState } from "react";
import { felixApi, Project, ProjectDetails } from "../services/felixApi";
import {
  IconPlus,
  IconFelix,
  IconSearch,
  IconGridView,
  IconListView,
  IconFilter,
} from "./Icons";

interface ProjectSelectorProps {
  selectedProjectId: string | null;
  onSelectProject: (projectId: string, details: ProjectDetails) => void;
}

const getProjectName = (project: Project): string => {
  if (project.name) {
    return project.name;
  }
  const segments = project.path.replace(/\\/g, "/").split("/");
  return segments[segments.length - 1] || project.path;
};

const formatDateTime = (value?: string): string => {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
};

const getRegionLabel = (path: string): string => {
  const normalized = path.replace(/\\/g, "/");
  const segments = normalized.split("/").filter(Boolean);
  if (segments.length >= 2) {
    return `${segments[segments.length - 2]} | ${segments[segments.length - 1]}`;
  }
  return path;
};

const getStatusStyle = (status?: string) => {
  if (!status) {
    return {
      backgroundColor: "var(--bg-surface)",
      color: "var(--text-tertiary)",
      borderColor: "var(--border-default)",
    };
  }
  switch (status.toLowerCase()) {
    case "running":
      return {
        backgroundColor: "rgba(79, 190, 116, 0.1)",
        color: "var(--brand-400)",
        borderColor: "rgba(56, 189, 248, 0.5)",
      };
    case "complete":
      return {
        backgroundColor: "rgba(52, 211, 153, 0.12)",
        color: "var(--emerald-400, #10b981)",
        borderColor: "rgba(16, 185, 129, 0.3)",
      };
    case "paused":
    case "blocked":
      return {
        backgroundColor: "rgba(244, 63, 94, 0.1)",
        color: "var(--text-error, #f43f5e)",
        borderColor: "rgba(244, 63, 94, 0.3)",
      };
    default:
      return {
        backgroundColor: "var(--bg-surface)",
        color: "var(--text-tertiary)",
        borderColor: "var(--border-default)",
      };
  }
};

const ProjectSelector: React.FC<ProjectSelectorProps> = ({
  selectedProjectId,
  onSelectProject,
}) => {
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectDetails, setProjectDetails] = useState<
    Map<string, ProjectDetails>
  >(new Map());
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<"grid" | "table">("grid");
  const [searchTerm, setSearchTerm] = useState("");
  const [isRegisterOpen, setIsRegisterOpen] = useState(false);
  const [registerPath, setRegisterPath] = useState("");
  const [registerName, setRegisterName] = useState("");
  const [isRegistering, setIsRegistering] = useState(false);
  const [confirmUnregister, setConfirmUnregister] = useState<string | null>(
    null,
  );

  const loadProjects = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const projectList = await felixApi.listProjects();
      const detailsMap = new Map<string, ProjectDetails>();
      await Promise.all(
        projectList.map(async (project) => {
          try {
            const details = await felixApi.getProject(project.id);
            detailsMap.set(project.id, details);
          } catch (inner) {
            console.warn(`Failed to load details for ${project.id}:`, inner);
          }
        }),
      );
      setProjects(projectList);
      setProjectDetails(detailsMap);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load projects");
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadProjects();
  }, []);

  const handleProjectClick = async (project: Project) => {
    const existing = projectDetails.get(project.id);
    if (existing) {
      onSelectProject(project.id, existing);
      return;
    }
    try {
      const fetched = await felixApi.getProject(project.id);
      setProjectDetails((prev) => new Map(prev).set(project.id, fetched));
      onSelectProject(project.id, fetched);
    } catch (err) {
      console.warn(`Failed to load project ${project.id}:`, err);
    }
  };

  const handleRegister = async () => {
    if (!registerPath.trim()) {
      return;
    }
    setIsRegistering(true);
    setError(null);
    try {
      const project = await felixApi.registerProject({
        path: registerPath.trim(),
        name: registerName.trim() || undefined,
      });
      const details = await felixApi.getProject(project.id);
      setProjects((prev) => [...prev, project]);
      setProjectDetails((prev) => new Map(prev).set(project.id, details));
      setIsRegisterOpen(false);
      setRegisterPath("");
      setRegisterName("");
      onSelectProject(project.id, details);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to register project");
    } finally {
      setIsRegistering(false);
    }
  };

  const handleUnregister = async (projectId: string) => {
    try {
      await felixApi.unregisterProject(projectId);
      setProjects((prev) => prev.filter((project) => project.id !== projectId));
      setProjectDetails((prev) => {
        const map = new Map(prev);
        map.delete(projectId);
        return map;
      });
      setConfirmUnregister(null);
      if (selectedProjectId === projectId) {
        const remaining = projects.filter((project) => project.id !== projectId);
        if (remaining.length > 0) {
          const primary = remaining[0];
          const fallbackDetails = projectDetails.get(primary.id);
          if (fallbackDetails) {
            onSelectProject(primary.id, fallbackDetails);
          }
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to unregister project");
    }
  };

  const filteredProjects = useMemo(() => {
    const query = searchTerm.trim().toLowerCase();
    if (!query) return projects;
    return projects.filter((project) => {
      const name = getProjectName(project).toLowerCase();
      const path = project.path.toLowerCase();
      const details = projectDetails.get(project.id);
      const status = details?.status?.toLowerCase() ?? "";
      return (
        name.includes(query) ||
        path.includes(query) ||
        status.includes(query)
      );
    });
  }, [projects, projectDetails, searchTerm]);

  return (
    <div
      className="projects-shell flex-1 flex flex-col overflow-hidden"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      <div
        className="projects-toolbar px-8 py-6 border-b"
        style={{
          borderColor: "var(--border-default)",
          backgroundColor: "var(--bg-surface)",
        }}
      >
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <p className="text-2xl font-semibold" style={{ color: "var(--text-secondary)" }}>
              Projects
            </p>
            <p className="text-xs uppercase tracking-[0.4em] text-[var(--text-muted)]">
              {projects.length} workspace{projects.length === 1 ? "" : "s"}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              className={`inline-flex items-center justify-center w-10 h-10 rounded-2xl border ${
                viewMode === "grid"
                  ? "border-brand-500 text-brand-500"
                  : "border-transparent text-[var(--text-muted)]"
              }`}
              onClick={() => setViewMode("grid")}
            >
              <IconGridView className="w-5 h-5" />
            </button>
            <button
              type="button"
              className={`inline-flex items-center justify-center w-10 h-10 rounded-2xl border ${
                viewMode === "table"
                  ? "border-brand-500 text-brand-500"
                  : "border-transparent text-[var(--text-muted)]"
              }`}
              onClick={() => setViewMode("table")}
            >
              <IconListView className="w-5 h-5" />
            </button>
            <button
              type="button"
              className="flex items-center gap-2 px-3 py-2 rounded-2xl border border-brand-500 bg-brand-500/10 text-brand-500"
              onClick={() => setIsRegisterOpen(true)}
            >
              <IconPlus className="w-4 h-4" />
              New project
            </button>
          </div>
        </div>
        <div className="flex items-center gap-3 pt-4">
          <div
            className="flex items-center gap-2 flex-1 px-3 py-2 rounded-full border"
            style={{
              borderColor: "var(--border-muted)",
              backgroundColor: "var(--bg-deep)",
            }}
          >
            <IconSearch className="w-4 h-4" style={{ color: "var(--text-muted)" }} />
            <input
              type="text"
              className="flex-1 bg-transparent outline-none text-sm"
              placeholder="Search projects"
              style={{ color: "var(--text-secondary)" }}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
            <span className="text-[10px] uppercase tracking-[0.3em]" style={{ color: "var(--text-muted)" }}>
              Cmd+K
            </span>
          </div>
          <button
            type="button"
            className="flex items-center gap-2 px-4 py-2 rounded-2xl border border-transparent bg-[var(--bg-surface)] text-[var(--text-muted)]"
          >
            <IconFilter className="w-4 h-4" />
            Filter
          </button>
          <button
            type="button"
            className="px-4 py-2 rounded-2xl border text-[var(--text-muted)]"
            style={{ borderColor: "var(--border-muted)" }}
            onClick={loadProjects}
          >
            Refresh
          </button>
        </div>
      </div>

      {error && (
        <div
          className="projects-error mx-8 mt-4 rounded-xl border px-5 py-3 text-sm"
          style={{
            borderColor: "rgba(248, 113, 113, 0.3)",
            backgroundColor: "rgba(248, 113, 113, 0.08)",
            color: "var(--text-error, #fca5a5)",
          }}
        >
          {error}
        </div>
      )}

      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="projects-empty flex flex-col items-center justify-center gap-3 px-8 py-12 text-center">
            <IconFelix className="w-12 h-12 text-[var(--text-muted)]" />
            <p className="text-sm font-semibold" style={{ color: "var(--text-secondary)" }}>
              Loading projects...
            </p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              Please wait while we gather your workspace data.
            </p>
          </div>
        ) : filteredProjects.length === 0 ? (
          <div className="projects-empty flex flex-col items-center justify-center gap-3 px-8 py-12 text-center">
            <IconFelix className="w-12 h-12 text-[var(--text-muted)]" />
            <p className="text-sm font-semibold" style={{ color: "var(--text-secondary)" }}>
              No projects yet
            </p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              Register a project to get started.
            </p>
          </div>
        ) : viewMode === "grid" ? (
          <div className="projects-grid grid grid-cols-1 gap-4 px-8 pb-8 pt-6 md:grid-cols-2 xl:grid-cols-3">
            {filteredProjects.map((project) => {
              const details = projectDetails.get(project.id);
              const isActive = selectedProjectId === project.id;
              return (
                <button
                  key={project.id}
                  onClick={() => handleProjectClick(project)}
                  className="project-card flex flex-col rounded-2xl border p-5 text-left transition hover:border-brand-400/70"
                  style={{
                    borderColor: isActive ? "var(--brand-500)" : "var(--border-default)",
                    backgroundColor: isActive ? "var(--bg-elevated)" : "var(--bg-surface)",
                  }}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-lg font-semibold" style={{ color: "var(--text-secondary)" }}>
                      {getProjectName(project)}
                    </span>
                    <span
                      className="text-[10px] font-semibold uppercase tracking-[0.3em] rounded-full border px-2 py-0.5"
                      style={getStatusStyle(details?.status)}
                    >
                      {details?.status?.toUpperCase() ?? "IDLE"}
                    </span>
                  </div>
                  <p
                    className="text-xs text-[var(--text-muted)] mt-1 line-clamp-2"
                    style={{ color: "var(--text-muted)" }}
                  >
                    {project.path}
                  </p>
                  <div className="mt-4 flex items-center justify-between text-[11px] uppercase tracking-[0.3em] text-[var(--text-muted)]">
                    <span>{details?.spec_count ?? 0} specs</span>
                    <span>Compute —</span>
                  </div>
                  <div className="mt-3 text-[10px] text-[var(--text-muted)]">
                    {details?.status === "paused" && "Project is paused"}
                  </div>
                </button>
              );
            })}
          </div>
        ) : (
          <div className="projects-table px-8 pb-8 pt-6">
            <div className="overflow-x-auto border border-var(--border-default) rounded-2xl">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-[10px] uppercase tracking-[0.4em] text-[var(--text-muted)]">
                    <th className="px-4 py-3 text-left">Project</th>
                    <th className="px-4 py-3 text-left">Status</th>
                    <th className="px-4 py-3 text-left">Compute</th>
                    <th className="px-4 py-3 text-left">Region</th>
                    <th className="px-4 py-3 text-left">Created</th>
                    <th className="px-4 py-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredProjects.map((project) => {
                    const details = projectDetails.get(project.id);
                    const isActive = selectedProjectId === project.id;
                    return (
                      <tr
                        key={project.id}
                        className={`project-table-row border-t border-transparent ${
                          isActive ? "bg-[var(--bg-deep)]" : ""
                        }`}
                      >
                        <td className="px-4 py-4">
                          <div className="font-semibold text-[var(--text-secondary)]">
                            {getProjectName(project)}
                          </div>
                          <div className="text-[10px] text-[var(--text-muted)] break-all">
                            {project.id}
                          </div>
                        </td>
                        <td className="px-4 py-4">
                          <span
                            className="text-[10px] font-semibold uppercase tracking-[0.4em] rounded-full border px-2 py-0.5"
                            style={getStatusStyle(details?.status)}
                          >
                            {details?.status?.toUpperCase() ?? "IDLE"}
                          </span>
                        </td>
                        <td className="px-4 py-4 text-[var(--text-muted)]">
                          {details?.has_specs ? "Specs" : "—"}
                        </td>
                        <td className="px-4 py-4 text-[var(--text-muted)]">
                          {getRegionLabel(project.path)}
                        </td>
                        <td className="px-4 py-4 text-[var(--text-muted)]">
                          {formatDateTime(project.registered_at)}
                        </td>
                        <td className="px-4 py-4 text-right">
                          <button
                            type="button"
                            className="text-[10px] uppercase tracking-[0.3em] text-[var(--text-muted)]"
                            onClick={(e) => {
                              e.stopPropagation();
                              setConfirmUnregister(project.id);
                            }}
                          >
                            →
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>

      {isRegisterOpen && (
        <div className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50">
          <div
            className="rounded-2xl shadow-2xl w-[420px] overflow-hidden"
            style={{ backgroundColor: "var(--bg-base)", border: "1px solid var(--border-default)" }}
          >
            <div
              className="h-12 border-b flex items-center justify-between px-4"
              style={{ borderColor: "var(--border-default)" }}
            >
              <div className="flex items-center gap-2">
                <IconPlus className="w-4 h-4" />
                <span className="text-xs font-bold" style={{ color: "var(--text-secondary)" }}>
                  Register Project
                </span>
              </div>
              <button
                type="button"
                className="rounded-lg p-1.5"
                onClick={() => setIsRegisterOpen(false)}
                style={{ color: "var(--text-muted)" }}
              >
                ✕
              </button>
            </div>
            <div className="p-4 space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider mb-2" style={{ color: "var(--text-muted)" }}>
                  Project Path *
                </label>
                <input
                  type="text"
                  value={registerPath}
                  onChange={(e) => setRegisterPath(e.target.value)}
                  placeholder="C:\\path\\to\\project"
                  className="w-full rounded-2xl px-4 py-2.5 text-sm focus:ring-1 focus:ring-brand-500 transition-all outline-none"
                  style={{
                    backgroundColor: "var(--bg-elevated)",
                    border: "1px solid var(--border-muted)",
                    color: "var(--text-secondary)",
                  }}
                />
              </div>
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider mb-2" style={{ color: "var(--text-muted)" }}>
                  Display Name (optional)
                </label>
                <input
                  type="text"
                  value={registerName}
                  onChange={(e) => setRegisterName(e.target.value)}
                  placeholder="My Project"
                  className="w-full rounded-2xl px-4 py-2.5 text-sm focus:ring-1 focus:ring-brand-500 transition-all outline-none"
                  style={{
                    backgroundColor: "var(--bg-elevated)",
                    border: "1px solid var(--border-muted)",
                    color: "var(--text-secondary)",
                  }}
                />
              </div>
              {error && (
                <div className="p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs" style={{ color: "var(--status-error)" }}>
                  {error}
                </div>
              )}
            </div>
            <div className="h-14 border-t flex items-center justify-end gap-3 px-4" style={{ borderColor: "var(--border-default)" }}>
              <button
                type="button"
                className="px-4 py-2 text-xs font-medium"
                style={{ color: "var(--text-muted)" }}
                onClick={() => setIsRegisterOpen(false)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="px-4 py-2 bg-brand-600 text-white text-xs font-bold rounded-xl hover:bg-brand-500 transition-all disabled:opacity-50"
                onClick={handleRegister}
                disabled={!registerPath.trim() || isRegistering}
              >
                {isRegistering ? "Registering..." : "Register"}
              </button>
            </div>
          </div>
        </div>
      )}

      {confirmUnregister && (
        <div className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50">
          <div
            className="rounded-2xl shadow-2xl w-[360px] overflow-hidden"
            style={{ backgroundColor: "var(--bg-base)", border: "1px solid var(--border-default)" }}
          >
            <div className="p-6 text-center">
              <div className="w-12 h-12 bg-red-500/10 rounded-full flex items-center justify-center mx-auto mb-4">
                <span className="text-2xl" style={{ color: "var(--status-error)" }}>
                  !
                </span>
              </div>
              <h3 className="text-sm font-bold mb-2" style={{ color: "var(--text-secondary)" }}>
                Unregister Project?
              </h3>
              <p className="text-xs mb-6" style={{ color: "var(--text-muted)" }}>
                This removes the project from Felix but does not delete your files.
              </p>
              <div className="flex gap-3 justify-center">
                <button
                  type="button"
                  className="px-4 py-2 text-xs font-medium"
                  style={{ color: "var(--text-muted)" }}
                  onClick={() => setConfirmUnregister(null)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="px-4 py-2 bg-red-600 text-white text-xs font-bold rounded-xl hover:bg-red-500 transition-all"
                  onClick={() => {
                    handleUnregister(confirmUnregister);
                  }}
                >
                  Unregister
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ProjectSelector;

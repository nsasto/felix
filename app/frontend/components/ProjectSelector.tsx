/**
 * ProjectSelector Component
 * Displays a list of registered projects with status indicators.
 * Allows project switching and provides register/unregister actions.
 */
import React, { useState, useEffect } from "react";
import { felixApi, Project, ProjectDetails } from "../services/felixApi";
import { IconPlus, IconFelix } from "./Icons";

type ViewMode = "cards" | "table";

// Project status color mapping
const getStatusColor = (status: string | null): string => {
  switch (status?.toLowerCase()) {
    case "running":
      return "bg-brand-500 animate-pulse";
    case "complete":
    case "done":
      return "bg-emerald-500";
    case "blocked":
    case "error":
      return "bg-red-500";
    case "planned":
      return "bg-amber-500";
    default:
      return "bg-slate-600";
  }
};

// Icon props interface
interface IconProps {
  className?: string;
  style?: React.CSSProperties;
}

// Folder icon component
const IconFolder = ({ className = "w-5 h-5", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
  </svg>
);

// Trash icon for unregister
const IconTrash = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <polyline points="3 6 5 6 21 6" />
    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
    <line x1="10" y1="11" x2="10" y2="17" />
    <line x1="14" y1="11" x2="14" y2="17" />
  </svg>
);

// Close icon
const IconX = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
  </svg>
);

// Grid icon for cards view
const IconGrid = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <rect x="3" y="3" width="7" height="7" />
    <rect x="14" y="3" width="7" height="7" />
    <rect x="14" y="14" width="7" height="7" />
    <rect x="3" y="14" width="7" height="7" />
  </svg>
);

// List icon for table view
const IconList = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <line x1="8" y1="6" x2="21" y2="6" />
    <line x1="8" y1="12" x2="21" y2="12" />
    <line x1="8" y1="18" x2="21" y2="18" />
    <line x1="3" y1="6" x2="3.01" y2="6" />
    <line x1="3" y1="12" x2="3.01" y2="12" />
    <line x1="3" y1="18" x2="3.01" y2="18" />
  </svg>
);

// Search icon
const IconSearch = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <circle cx="11" cy="11" r="8" />
    <path d="m21 21-4.35-4.35" />
  </svg>
);

// Filter icon
const IconFilter = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
  </svg>
);

// More icon (three dots)
const IconMore = ({ className = "w-4 h-4", style }: IconProps) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
  >
    <circle cx="12" cy="12" r="1" />
    <circle cx="12" cy="5" r="1" />
    <circle cx="12" cy="19" r="1" />
  </svg>
);

interface ProjectSelectorProps {
  selectedProjectId: string | null;
  onSelectProject: (projectId: string, details: ProjectDetails) => void;
  onProjectsChange?: () => void;
}

export const ProjectSelector: React.FC<ProjectSelectorProps> = ({
  selectedProjectId,
  onSelectProject,
  onProjectsChange,
}) => {
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectDetails, setProjectDetails] = useState<
    Map<string, ProjectDetails>
  >(new Map());
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isRegisterOpen, setIsRegisterOpen] = useState(false);
  const [registerPath, setRegisterPath] = useState("");
  const [registerName, setRegisterName] = useState("");
  const [isRegistering, setIsRegistering] = useState(false);
  const [confirmUnregister, setConfirmUnregister] = useState<string | null>(
    null,
  );
  const [viewMode, setViewMode] = useState<ViewMode>("cards");
  const [searchQuery, setSearchQuery] = useState("");

  // Load projects on mount
  useEffect(() => {
    loadProjects();
  }, []);

  const loadProjects = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const projectList = await felixApi.listProjects();
      setProjects(projectList);

      // Load details for each project
      const detailsMap = new Map<string, ProjectDetails>();
      await Promise.all(
        projectList.map(async (project) => {
          try {
            const details = await felixApi.getProject(project.id);
            detailsMap.set(project.id, details);
          } catch (e) {
            // If we can't get details, use basic project info
            console.warn(
              `Failed to load details for project ${project.id}:`,
              e,
            );
          }
        }),
      );
      setProjectDetails(detailsMap);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load projects");
    } finally {
      setIsLoading(false);
    }
  };

  const handleRegister = async () => {
    if (!registerPath.trim()) return;

    setIsRegistering(true);
    setError(null);
    try {
      const newProject = await felixApi.registerProject({
        path: registerPath.trim(),
        name: registerName.trim() || undefined,
      });

      // Get details for the new project
      const details = await felixApi.getProject(newProject.id);

      setProjects((prev) => [...prev, newProject]);
      setProjectDetails((prev) => new Map(prev).set(newProject.id, details));

      setIsRegisterOpen(false);
      setRegisterPath("");
      setRegisterName("");

      // Auto-select the new project
      onSelectProject(newProject.id, details);
      onProjectsChange?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to register project");
    } finally {
      setIsRegistering(false);
    }
  };

  const handleUnregister = async (projectId: string) => {
    try {
      await felixApi.unregisterProject(projectId);
      setProjects((prev) => prev.filter((p) => p.id !== projectId));
      setProjectDetails((prev) => {
        const newMap = new Map(prev);
        newMap.delete(projectId);
        return newMap;
      });
      setConfirmUnregister(null);

      // If the unregistered project was selected, clear selection
      if (selectedProjectId === projectId) {
        const remaining = projects.filter((p) => p.id !== projectId);
        if (remaining.length > 0) {
          const firstProject = remaining[0];
          const details = projectDetails.get(firstProject.id);
          if (details) {
            onSelectProject(firstProject.id, details);
          }
        }
      }
      onProjectsChange?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to unregister project");
    }
  };

  const handleProjectClick = (project: Project) => {
    const details = projectDetails.get(project.id);
    if (details) {
      onSelectProject(project.id, details);
    }
  };

  const getProjectName = (project: Project): string => {
    if (project.name) return project.name;
    // Extract folder name from path
    const parts = project.path.replace(/\\/g, "/").split("/");
    return parts[parts.length - 1] || project.path;
  };

  // Filter projects based on search query
  const filteredProjects = projects.filter((project) => {
    const name = getProjectName(project).toLowerCase();
    const path = project.path.toLowerCase();
    const query = searchQuery.toLowerCase();
    return name.includes(query) || path.includes(query);
  });

  return (
    <div
      className="flex flex-col h-full"
      style={{ backgroundColor: "var(--bg-base)" }}
    >
      {/* Header */}
      <div
        className="border-b"
        style={{ borderColor: "var(--border-default)" }}
      >
        <div className="h-14 flex items-center px-6 justify-between">
          <h1
            className="text-lg font-semibold"
            style={{ color: "var(--text-primary)" }}
          >
            Projects
          </h1>
          <button
            onClick={() => setIsRegisterOpen(true)}
            className="px-3 py-1.5 bg-brand-600 text-white text-sm font-medium rounded-lg hover:bg-brand-500 transition-all flex items-center gap-2"
          >
            <IconPlus className="w-4 h-4" />
            New project
          </button>
        </div>

        {/* Search and view controls */}
        <div className="px-6 py-3 flex items-center gap-3">
          {/* Search */}
          <div className="flex-1 relative">
            <IconSearch
              className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2"
              style={{ color: "var(--text-muted)" }}
            />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search for a project"
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg outline-none transition-all"
              style={{
                backgroundColor: "var(--bg-base)",
                border: "1px solid var(--border-muted)",
                color: "var(--text-secondary)",
              }}
            />
          </div>

          {/* Filter button (placeholder) */}
          <button
            className="p-2 rounded-lg transition-all border"
            style={{
              borderColor: "var(--border-muted)",
              color: "var(--text-muted)",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = "var(--hover-bg)";
              e.currentTarget.style.color = "var(--text-secondary)";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = "transparent";
              e.currentTarget.style.color = "var(--text-muted)";
            }}
            title="Filter"
          >
            <IconFilter className="w-4 h-4" />
          </button>

          {/* View mode toggles */}
          <div
            className="flex items-center border rounded-lg"
            style={{ borderColor: "var(--border-muted)" }}
          >
            <button
              onClick={() => setViewMode("cards")}
              className="p-2 transition-all"
              style={{
                backgroundColor:
                  viewMode === "cards" ? "var(--bg-elevated)" : "transparent",
                color:
                  viewMode === "cards"
                    ? "var(--text-primary)"
                    : "var(--text-muted)",
              }}
              title="Card view"
            >
              <IconGrid className="w-4 h-4" />
            </button>
            <button
              onClick={() => setViewMode("table")}
              className="p-2 transition-all"
              style={{
                backgroundColor:
                  viewMode === "table" ? "var(--bg-elevated)" : "transparent",
                color:
                  viewMode === "table"
                    ? "var(--text-primary)"
                    : "var(--text-muted)",
              }}
              title="Table view"
            >
              <IconList className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Error display */}
      {error && (
        <div
          className="mx-6 mt-3 p-3 bg-red-500/10 border border-red-500/20 rounded-lg text-sm flex items-center justify-between"
          style={{ color: "var(--status-error)" }}
        >
          <span>{error}</span>
          <button
            onClick={() => setError(null)}
            className="ml-2 opacity-80 hover:opacity-100 p-1"
            style={{ color: "var(--status-error)" }}
          >
            <IconX className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* Project list */}
      <div className="flex-1 overflow-y-auto custom-scrollbar">
        {isLoading ? (
          <div
            className="flex items-center justify-center py-16 text-sm"
            style={{ color: "var(--text-muted)" }}
          >
            <IconFelix className="w-5 h-5 animate-spin mr-2" />
            Loading projects...
          </div>
        ) : filteredProjects.length === 0 ? (
          <div
            className="flex flex-col items-center justify-center py-16 text-center px-6"
            style={{ color: "var(--text-muted)" }}
          >
            {searchQuery ? (
              <>
                <IconSearch className="w-12 h-12 mb-4 opacity-50" />
                <p className="text-sm mb-1">No projects found</p>
                <p className="text-xs opacity-60">Try adjusting your search</p>
              </>
            ) : (
              <>
                <IconFolder className="w-12 h-12 mb-4 opacity-50" />
                <p className="text-sm mb-1">No projects registered</p>
                <p className="text-xs opacity-60">
                  Click "New project" to register a project
                </p>
              </>
            )}
          </div>
        ) : viewMode === "cards" ? (
          /* Card View */
          <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-3 p-6">
            {filteredProjects.map((project) => {
              const details = projectDetails.get(project.id);
              const isSelected = selectedProjectId === project.id;

              return (
                <div
                  key={project.id}
                  className="relative group cursor-pointer rounded-xl border transition-all hover:shadow-md"
                  style={{
                    backgroundColor: "var(--bg-elevated)",
                    borderColor: isSelected
                      ? "var(--accent-primary)"
                      : "var(--border-default)",
                    borderWidth: isSelected ? "2px" : "1px",
                  }}
                  onClick={() => handleProjectClick(project)}
                >
                  <div className="p-4">
                    {/* Card header */}
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-2 flex-1 min-w-0">
                        <IconFolder
                          className="w-5 h-5 flex-shrink-0"
                          style={{ color: "var(--text-muted)" }}
                        />
                        <h3
                          className="font-semibold text-sm truncate"
                          style={{ color: "var(--text-primary)" }}
                        >
                          {getProjectName(project)}
                        </h3>
                      </div>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setConfirmUnregister(project.id);
                        }}
                        className="opacity-0 group-hover:opacity-100 p-1.5 hover:bg-red-500/10 rounded-lg transition-all flex-shrink-0"
                        style={{ color: "var(--text-muted)" }}
                        onMouseEnter={(e) => {
                          e.currentTarget.style.color = "var(--status-error)";
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.color = "var(--text-muted)";
                        }}
                        title="Unregister project"
                      >
                        <IconMore className="w-4 h-4" />
                      </button>
                    </div>

                    {/* Project path */}
                    <p
                      className="text-xs mb-3 truncate font-mono"
                      style={{ color: "var(--text-muted)" }}
                    >
                      {project.path.split("\\").pop() ||
                        project.path.split("/").pop()}
                    </p>

                    {/* Status badge */}
                    {details?.status && (
                      <div
                        className="inline-flex items-center gap-1.5 px-2 py-1 rounded text-xs font-medium mb-3"
                        style={{
                          backgroundColor: "var(--bg-base)",
                          color: "var(--text-muted)",
                        }}
                      >
                        <div
                          className={`w-2 h-2 rounded-full ${getStatusColor(details.status)}`}
                        />
                        <span className="uppercase text-[10px] tracking-wider">
                          {details.status}
                        </span>
                      </div>
                    )}

                    {/* Status message */}
                    {details?.status === "paused" && (
                      <div
                        className="flex items-center gap-2 p-2 rounded-lg mb-3"
                        style={{ backgroundColor: "var(--bg-base)" }}
                      >
                        <svg
                          className="w-4 h-4 flex-shrink-0"
                          style={{ color: "var(--text-muted)" }}
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                        >
                          <circle cx="12" cy="12" r="10" />
                          <line x1="12" y1="8" x2="12" y2="12" />
                          <line x1="12" y1="16" x2="12.01" y2="16" />
                        </svg>
                        <span
                          className="text-xs"
                          style={{ color: "var(--text-muted)" }}
                        >
                          Project is paused
                        </span>
                        <button
                          className="ml-auto text-xs"
                          style={{ color: "var(--text-muted)" }}
                        >
                          <svg
                            className="w-4 h-4"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            strokeWidth="2"
                          >
                            <circle cx="12" cy="12" r="10" />
                            <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
                            <line x1="12" y1="17" x2="12.01" y2="17" />
                          </svg>
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          /* Table View */
          <div className="px-6 py-4">
            <table className="w-full">
              <thead>
                <tr
                  className="border-b"
                  style={{ borderColor: "var(--border-default)" }}
                >
                  <th
                    className="text-left py-3 px-3 text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Project
                  </th>
                  <th
                    className="text-left py-3 px-3 text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Status
                  </th>
                  <th
                    className="text-left py-3 px-3 text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Compute
                  </th>
                  <th
                    className="text-left py-3 px-3 text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Region
                  </th>
                  <th
                    className="text-left py-3 px-3 text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "var(--text-muted)" }}
                  >
                    Created
                  </th>
                  <th className="w-10"></th>
                </tr>
              </thead>
              <tbody>
                {filteredProjects.map((project) => {
                  const details = projectDetails.get(project.id);
                  const isSelected = selectedProjectId === project.id;

                  return (
                    <tr
                      key={project.id}
                      className="border-b group cursor-pointer transition-colors"
                      style={{
                        borderColor: "var(--border-default)",
                        backgroundColor: isSelected
                          ? "var(--selected-bg)"
                          : "transparent",
                      }}
                      onClick={() => handleProjectClick(project)}
                      onMouseEnter={(e) => {
                        if (!isSelected) {
                          e.currentTarget.style.backgroundColor =
                            "var(--hover-bg)";
                        }
                      }}
                      onMouseLeave={(e) => {
                        if (!isSelected) {
                          e.currentTarget.style.backgroundColor = "transparent";
                        }
                      }}
                    >
                      <td className="py-3 px-3">
                        <div className="flex flex-col">
                          <span
                            className="font-medium text-sm"
                            style={{ color: "var(--text-primary)" }}
                          >
                            {getProjectName(project)}
                          </span>
                          <span
                            className="text-xs font-mono"
                            style={{ color: "var(--text-muted)" }}
                          >
                            {project.path.length > 40
                              ? "..." + project.path.slice(-37)
                              : project.path}
                          </span>
                        </div>
                      </td>
                      <td className="py-3 px-3">
                        {details?.status && (
                          <span
                            className="inline-flex items-center gap-1.5 px-2 py-1 rounded text-xs font-medium"
                            style={{
                              backgroundColor: "var(--bg-base)",
                              color: "var(--text-muted)",
                            }}
                          >
                            <div
                              className={`w-2 h-2 rounded-full ${getStatusColor(details.status)}`}
                            />
                            <span className="uppercase text-[10px] tracking-wider">
                              {details.status}
                            </span>
                          </span>
                        )}
                      </td>
                      <td
                        className="py-3 px-3 text-sm"
                        style={{ color: "var(--text-muted)" }}
                      >
                        —
                      </td>
                      <td
                        className="py-3 px-3 text-sm"
                        style={{ color: "var(--text-secondary)" }}
                      >
                        aws | us-east-2
                      </td>
                      <td
                        className="py-3 px-3 text-sm"
                        style={{ color: "var(--text-secondary)" }}
                      >
                        {details
                          ? new Date().toLocaleDateString("en-US", {
                              month: "short",
                              day: "numeric",
                              year: "2-digit",
                              hour: "2-digit",
                              minute: "2-digit",
                            })
                          : "—"}
                      </td>
                      <td className="py-3 px-3">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setConfirmUnregister(project.id);
                          }}
                          className="opacity-0 group-hover:opacity-100 p-1.5 hover:bg-red-500/10 rounded-lg transition-all"
                          style={{ color: "var(--text-muted)" }}
                          onMouseEnter={(e) => {
                            e.currentTarget.style.color = "var(--status-error)";
                          }}
                          onMouseLeave={(e) => {
                            e.currentTarget.style.color = "var(--text-muted)";
                          }}
                          title="Unregister project"
                        >
                          <IconMore className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Register Project Dialog */}
      {isRegisterOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div
            className="rounded-2xl shadow-2xl w-[420px] overflow-hidden"
            style={{
              backgroundColor: "var(--bg-base)",
              border: "1px solid var(--border-default)",
            }}
          >
            {/* Dialog header */}
            <div
              className="h-12 border-b flex items-center justify-between px-4"
              style={{ borderColor: "var(--border-default)" }}
            >
              <div className="flex items-center gap-2">
                <IconFolder
                  className="w-4 h-4"
                  style={{ color: "var(--accent-primary)" }}
                />
                <span
                  className="text-xs font-bold"
                  style={{ color: "var(--text-secondary)" }}
                >
                  Register Project
                </span>
              </div>
              <button
                onClick={() => setIsRegisterOpen(false)}
                className="p-1.5 rounded-lg transition-all"
                style={{ color: "var(--text-muted)" }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.backgroundColor = "var(--hover-bg)";
                  e.currentTarget.style.color = "var(--text-secondary)";
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = "transparent";
                  e.currentTarget.style.color = "var(--text-muted)";
                }}
              >
                <IconX className="w-4 h-4" />
              </button>
            </div>

            {/* Dialog body */}
            <div className="p-4 space-y-4">
              <div>
                <label
                  className="block text-[10px] font-bold uppercase tracking-wider mb-2"
                  style={{ color: "var(--text-muted)" }}
                >
                  Project Path *
                </label>
                <input
                  type="text"
                  value={registerPath}
                  onChange={(e) => setRegisterPath(e.target.value)}
                  placeholder="C:\path\to\your\project"
                  className="w-full rounded-xl px-4 py-2.5 text-sm focus:ring-1 focus:ring-brand-500 transition-all outline-none"
                  style={{
                    backgroundColor: "var(--bg-elevated)",
                    border: "1px solid var(--border-muted)",
                    color: "var(--text-secondary)",
                  }}
                />
                <p
                  className="mt-1.5 text-[9px]"
                  style={{ color: "var(--text-muted)" }}
                >
                  Enter the absolute path to your Felix project directory
                  <br />
                  Tip: Shift+Right-click folder in Explorer → "Copy as path"
                </p>
              </div>

              <div>
                <label
                  className="block text-[10px] font-bold uppercase tracking-wider mb-2"
                  style={{ color: "var(--text-muted)" }}
                >
                  Display Name (optional)
                </label>
                <input
                  type="text"
                  value={registerName}
                  onChange={(e) => setRegisterName(e.target.value)}
                  placeholder="My Project"
                  className="w-full rounded-xl px-4 py-2.5 text-sm focus:ring-1 focus:ring-brand-500 transition-all outline-none"
                  style={{
                    backgroundColor: "var(--bg-elevated)",
                    border: "1px solid var(--border-muted)",
                    color: "var(--text-secondary)",
                  }}
                />
              </div>

              {error && (
                <div
                  className="p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs"
                  style={{ color: "var(--status-error)" }}
                >
                  {error}
                </div>
              )}
            </div>

            {/* Dialog footer */}
            <div
              className="h-14 border-t flex items-center justify-end gap-3 px-4"
              style={{ borderColor: "var(--border-default)" }}
            >
              <button
                onClick={() => setIsRegisterOpen(false)}
                className="px-4 py-2 text-xs font-medium transition-colors"
                style={{ color: "var(--text-muted)" }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.color = "var(--text-secondary)";
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.color = "var(--text-muted)";
                }}
              >
                Cancel
              </button>
              <button
                onClick={handleRegister}
                disabled={!registerPath.trim() || isRegistering}
                className="px-4 py-2 bg-brand-600 text-white text-xs font-bold rounded-xl hover:bg-brand-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isRegistering ? "Registering..." : "Register"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirm Unregister Dialog */}
      {confirmUnregister && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div
            className="rounded-2xl shadow-2xl w-[380px] overflow-hidden"
            style={{
              backgroundColor: "var(--bg-base)",
              border: "1px solid var(--border-default)",
            }}
          >
            <div className="p-6 text-center">
              <div className="w-12 h-12 bg-red-500/10 rounded-full flex items-center justify-center mx-auto mb-4">
                <IconTrash
                  className="w-6 h-6"
                  style={{ color: "var(--status-error)" }}
                />
              </div>
              <h3
                className="text-sm font-bold mb-2"
                style={{ color: "var(--text-primary)" }}
              >
                Unregister Project?
              </h3>
              <p
                className="text-xs mb-6"
                style={{ color: "var(--text-muted)" }}
              >
                This will remove the project from Felix. Your files will not be
                deleted.
              </p>
              <div className="flex gap-3 justify-center">
                <button
                  onClick={() => setConfirmUnregister(null)}
                  className="px-4 py-2 text-xs font-medium transition-colors"
                  style={{ color: "var(--text-muted)" }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.color = "var(--text-secondary)";
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.color = "var(--text-muted)";
                  }}
                >
                  Cancel
                </button>
                <button
                  onClick={() => handleUnregister(confirmUnregister)}
                  className="px-4 py-2 bg-red-600 text-white text-xs font-bold rounded-xl hover:bg-red-500 transition-all"
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

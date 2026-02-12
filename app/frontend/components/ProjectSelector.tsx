/**
 * ProjectSelector Component
 * Displays a list of registered projects with status indicators.
 * Allows project switching and provides register/unregister actions.
 */
import React, { useState, useEffect } from "react";
import { felixApi, Project, ProjectDetails } from "../services/felixApi";
import { Plus as IconPlus, Bot as IconFelix } from "lucide-react";
import { cn } from "../lib/utils";
import { Alert, AlertDescription } from "./ui/alert";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Card, CardContent } from "./ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { Input } from "./ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "./ui/table";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import DataSurface from "./DataSurface";
import FilterPopover from "./FilterPopover";

type ViewMode = "cards" | "table";

// Project status color mapping
const getStatusColor = (status: string | null): string => {
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
  const [filters, setFilters] = useState<Record<string, Set<string>>>({
    status: new Set(),
  });

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
    const matchesSearch = name.includes(query) || path.includes(query);
    if (!matchesSearch) {
      return false;
    }

    if (filters.status.size > 0) {
      const status = projectDetails.get(project.id)?.status?.toLowerCase();
      return status ? filters.status.has(status) : false;
    }

    return true;
  });

  return (
    <div className="flex flex-col h-full bg-[var(--bg-base)]">
      <DataSurface
        title="Projects"
        className="bg-[var(--bg-base)]"
        surfaceVariant={viewMode === "table" ? "card" : "plain"}
        contentClassName={viewMode === "table" ? undefined : "rounded-lg"}
        search={
          <div className="relative w-full max-w-sm">
            <IconSearch className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 theme-text-muted" />
            <Input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search for a project"
              className="pl-9 h-9 text-sm"
            />
          </div>
        }
        filters={
          <FilterPopover
            groups={[
              {
                key: "status",
                label: "Status",
                options: [
                  { label: "Running", value: "running" },
                  { label: "Paused", value: "paused" },
                  { label: "Planned", value: "planned" },
                  { label: "Blocked", value: "blocked" },
                  { label: "Error", value: "error" },
                  { label: "Done", value: "done" },
                  { label: "Complete", value: "complete" },
                ],
              },
            ]}
            value={filters}
            onChange={setFilters}
            label="Filter projects"
          />
        }
        actions={
          <Button
            onClick={() => setIsRegisterOpen(true)}
            size="sm"
            className="h-9"
          >
            <IconPlus className="w-4 h-4" />
            New project
          </Button>
        }
        viewToggle={
          <ToggleGroup
            type="single"
            value={viewMode}
            onValueChange={(value) => {
              if (value) setViewMode(value as ViewMode);
            }}
            className="border border-[var(--border)] rounded-md"
          >
            <ToggleGroupItem value="cards" title="Card view" className="h-9 w-9">
              <IconGrid className="w-4 h-4" />
            </ToggleGroupItem>
            <ToggleGroupItem value="table" title="Table view" className="h-9 w-9">
              <IconList className="w-4 h-4" />
            </ToggleGroupItem>
          </ToggleGroup>
        }
      >
        {error && (
          <div className="px-6 pt-2">
            <Alert className="flex items-center justify-between border-[var(--destructive-500)]/20 bg-[var(--destructive-500)]/10">
              <AlertDescription className="text-[var(--destructive-500)]">
                {error}
              </AlertDescription>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setError(null)}
              >
                <IconX className="w-4 h-4" />
              </Button>
            </Alert>
          </div>
        )}
        {isLoading ? (
          <div className="flex items-center justify-center py-16 text-sm theme-text-muted">
            <IconFelix className="w-5 h-5 animate-spin mr-2" />
            Loading projects...
          </div>
        ) : filteredProjects.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center px-6 theme-text-muted">
            {searchQuery || filters.status.size > 0 ? (
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
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 py-2">
            {filteredProjects.map((project) => {
              const details = projectDetails.get(project.id);
              const isSelected = selectedProjectId === project.id;

              return (
                <Card
                  key={project.id}
                  selectable
                  className={cn(
                    "relative group",
                    isSelected
                      ? "border-2 border-[var(--brand-500)]"
                      : "border-[var(--border-default)]",
                  )}
                  onClick={() => handleProjectClick(project)}
                >
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-2 flex-1 min-w-0">
                        <IconFolder className="w-5 h-5 flex-shrink-0 theme-text-muted" />
                        <h3 className="font-semibold text-sm truncate theme-text-primary">
                          {getProjectName(project)}
                        </h3>
                      </div>
                      <Button
                        onClick={(e) => {
                          e.stopPropagation();
                          setConfirmUnregister(project.id);
                        }}
                        variant="ghost"
                        size="icon"
                        className="opacity-0 group-hover:opacity-100 text-[var(--text-muted)] hover:text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/10"
                        title="Unregister project"
                      >
                        <IconMore className="w-4 h-4" />
                      </Button>
                    </div>

                    <p className="text-xs mb-3 truncate font-mono theme-text-muted">
                      {project.path.split("\\").pop() ||
                        project.path.split("/").pop()}
                    </p>

                    {details?.status && (
                      <Badge className="gap-1.5 mb-3">
                        <div
                          className={`w-2 h-2 rounded-full ${getStatusColor(details.status)}`}
                        />
                        <span className="uppercase text-[10px] tracking-wider">
                          {details.status}
                        </span>
                      </Badge>
                    )}

                    {details?.status === "paused" && (
                      <div className="flex items-center gap-2 p-2 rounded-lg mb-3 bg-[var(--bg-base)]">
                        <svg
                          className="w-4 h-4 flex-shrink-0 theme-text-muted"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                        >
                          <circle cx="12" cy="12" r="10" />
                          <line x1="12" y1="8" x2="12" y2="12" />
                          <line x1="12" y1="16" x2="12.01" y2="16" />
                        </svg>
                        <span className="text-xs theme-text-muted">
                          Project is paused
                        </span>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="ml-auto text-[var(--text-muted)]"
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
                        </Button>
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        ) : (
          <div className="px-2 py-2">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Project</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Compute</TableHead>
                  <TableHead>Region</TableHead>
                  <TableHead>Created</TableHead>
                  <TableHead className="w-10"></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredProjects.map((project) => {
                  const details = projectDetails.get(project.id);
                  const isSelected = selectedProjectId === project.id;

                  return (
                    <TableRow
                      key={project.id}
                      className={cn(
                        "group cursor-pointer",
                        isSelected && "bg-[var(--bg-surface-200)]",
                      )}
                      onClick={() => handleProjectClick(project)}
                    >
                      <TableCell>
                        <div className="flex flex-col">
                          <span className="font-medium text-sm theme-text-primary">
                            {getProjectName(project)}
                          </span>
                          <span className="text-xs font-mono theme-text-muted">
                            {project.path.length > 40
                              ? "..." + project.path.slice(-37)
                              : project.path}
                          </span>
                        </div>
                      </TableCell>
                      <TableCell>
                        {details?.status && (
                          <Badge className="gap-1.5">
                            <div
                              className={`w-2 h-2 rounded-full ${getStatusColor(details.status)}`}
                            />
                            <span className="uppercase text-[10px] tracking-wider">
                              {details.status}
                            </span>
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="theme-text-muted">-</TableCell>
                      <TableCell className="theme-text-secondary">-</TableCell>
                      <TableCell className="theme-text-secondary">-</TableCell>
                      <TableCell>
                        <Button
                          onClick={(e) => {
                            e.stopPropagation();
                            setConfirmUnregister(project.id);
                          }}
                          variant="ghost"
                          size="icon"
                          className="opacity-0 group-hover:opacity-100 text-[var(--text-muted)] hover:text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/10"
                          title="Unregister project"
                        >
                          <IconMore className="w-4 h-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </DataSurface>

      {/* Register Project Dialog */}

      <Dialog open={isRegisterOpen} onOpenChange={setIsRegisterOpen}>
        <DialogContent className="max-w-md p-0">
          <DialogHeader>
            <div className="flex items-center gap-2">
              <IconFolder className="w-4 h-4 text-[var(--brand-500)]" />
              <DialogTitle>Register Project</DialogTitle>
            </div>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setIsRegisterOpen(false)}
            >
              <IconX className="w-4 h-4" />
            </Button>
          </DialogHeader>

          <div className="p-4 space-y-4">
            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider mb-2 theme-text-muted">
                Project Path *
              </label>
              <Input
                value={registerPath}
                onChange={(e) => setRegisterPath(e.target.value)}
                placeholder="C:\path\to\your\project"
                className="h-10"
              />
              <p className="mt-1.5 text-[9px] theme-text-muted">
                Enter the absolute path to your Felix project directory
                <br />
                Tip: Shift+Right-click folder in Explorer to "Copy as path"
              </p>
            </div>

            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider mb-2 theme-text-muted">
                Display Name (optional)
              </label>
              <Input
                value={registerName}
                onChange={(e) => setRegisterName(e.target.value)}
                placeholder="My Project"
                className="h-10"
              />
            </div>

            {error && (
              <Alert className="border-[var(--destructive-500)]/20 bg-[var(--destructive-500)]/10">
                <AlertDescription className="text-[var(--destructive-500)]">
                  {error}
                </AlertDescription>
              </Alert>
            )}
          </div>

          <DialogFooter>
            <Button variant="ghost" onClick={() => setIsRegisterOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleRegister}
              disabled={!registerPath.trim() || isRegistering}
            >
              {isRegistering ? "Registering..." : "Register"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Confirm Unregister Dialog */}
      <AlertDialog
        open={Boolean(confirmUnregister)}
        onOpenChange={(open) => {
          if (!open) setConfirmUnregister(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader className="text-center">
            <div className="w-12 h-12 bg-[var(--destructive-500)]/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <IconTrash className="w-6 h-6 text-[var(--destructive-500)]" />
            </div>
            <AlertDialogTitle>Unregister Project?</AlertDialogTitle>
            <AlertDialogDescription className="mt-2">
              This will remove the project from Felix. Your files will not be
              deleted.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter className="flex items-center justify-center gap-3">
            <AlertDialogCancel asChild>
              <Button variant="ghost">Cancel</Button>
            </AlertDialogCancel>
            <AlertDialogAction asChild>
              <Button
                variant="destructive"
                onClick={() => handleUnregister(confirmUnregister || "")}
              >
                Unregister
              </Button>
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default ProjectSelector;

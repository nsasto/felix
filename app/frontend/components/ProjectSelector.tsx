/**
 * ProjectSelector Component
 * Displays a list of registered projects with status indicators.
 * Allows project switching and provides register/unregister actions.
 */
import React, { useState, useEffect } from "react";
import { felixApi, Project, ProjectDetails } from "../services/felixApi";
import {
  Bot as IconFelix,
  Folder,
  HelpCircle,
  Info,
  LayoutGrid,
  List,
  Plus as IconPlus,
  Search,
  Trash2,
  X,
} from "lucide-react";
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
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import DataSurface from "./DataSurface";
import FilterPopover from "./FilterPopover";
import DataTable from "./DataTable";
import RowActionsMenu from "./RowActionsMenu";
import { getProjectStatusDotClass } from "../lib/status";

type ViewMode = "cards" | "table";

interface ProjectSelectorProps {
  selectedProjectId: string | null;
  orgId: string | null;
  onSelectProject: (projectId: string, details: ProjectDetails) => void;
  onProjectsChange?: () => void;
}

export const ProjectSelector: React.FC<ProjectSelectorProps> = ({
  selectedProjectId,
  orgId,
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
  const [registerGitUrl, setRegisterGitUrl] = useState("");
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
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);

  // Load projects on mount and when org changes
  useEffect(() => {
    loadProjects();
  }, [orgId]);

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
    if (!registerGitUrl.trim()) return;

    setIsRegistering(true);
    setError(null);
    try {
      const newProject = await felixApi.registerProject({
        git_url: registerGitUrl.trim(),
        name: registerName.trim() || undefined,
      });

      // Get details for the new project
      const details = await felixApi.getProject(newProject.id);

      setProjects((prev) => [...prev, newProject]);
      setProjectDetails((prev) => new Map(prev).set(newProject.id, details));

      setIsRegisterOpen(false);
      setRegisterGitUrl("");
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
    // Extract repo name from git URL
    const match = project.git_url.match(/\/([^\/]+?)(?:\.git)?$/);
    return match ? match[1] : project.git_url;
  };

  // Filter projects based on search query
  const filteredProjects = projects.filter((project) => {
    const name = getProjectName(project).toLowerCase();
    const gitUrl = project.git_url.toLowerCase();
    const query = searchQuery.toLowerCase();
    const matchesSearch = name.includes(query) || gitUrl.includes(query);
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
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 theme-text-muted" />
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
            <ToggleGroupItem
              value="cards"
              title="Card view"
              className="h-9 w-9"
            >
              <LayoutGrid className="w-4 h-4" />
            </ToggleGroupItem>
            <ToggleGroupItem
              value="table"
              title="Table view"
              className="h-9 w-9"
            >
              <List className="w-4 h-4" />
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
                <X className="w-4 h-4" />
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
                <Search className="w-12 h-12 mb-4 opacity-50" />
                <p className="text-sm mb-1">No projects found</p>
                <p className="text-xs opacity-60">Try adjusting your search</p>
              </>
            ) : (
              <>
                <Folder className="w-12 h-12 mb-4 opacity-50" />
                <p className="text-sm mb-1">No projects registered</p>
                <p className="text-xs opacity-60">
                  Click "New project" to register a project
                </p>
              </>
            )}
          </div>
        ) : viewMode === "cards" ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {filteredProjects.map((project) => {
              const details = projectDetails.get(project.id);
              const isSelected =
                selectedProjectId === project.id || openMenuId === project.id;

              return (
                <Card
                  key={project.id}
                  selectable
                  className={cn(
                    "relative group",
                    isSelected
                      ? "border-2 border-[var(--brand-500)] bg-[var(--bg-surface-200)]"
                      : "border-[var(--border-default)]",
                  )}
                  onClick={() => handleProjectClick(project)}
                >
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-2 flex-1 min-w-0">
                        <Folder className="w-5 h-5 flex-shrink-0 theme-text-muted" />
                        <h3 className="font-semibold text-sm truncate theme-text-primary">
                          {getProjectName(project)}
                        </h3>
                      </div>
                      <RowActionsMenu
                        items={[
                          {
                            label: "Unregister project",
                            icon: "trash",
                            onSelect: () => setConfirmUnregister(project.id),
                          },
                        ]}
                        onOpenChange={(open) =>
                          setOpenMenuId(open ? project.id : null)
                        }
                      />
                    </div>

                    <p className="text-xs mb-3 truncate font-mono theme-text-muted">
                      {project.git_url}
                    </p>

                    {details?.status && (
                      <Badge className="gap-1.5 mb-3">
                        <div
                          className={`w-2 h-2 rounded-full ${getProjectStatusDotClass(details.status)}`}
                        />
                        <span className="uppercase text-[10px] tracking-wider">
                          {details.status}
                        </span>
                      </Badge>
                    )}

                    {details?.status === "paused" && (
                      <div className="flex items-center gap-2 p-2 rounded-lg mb-3 bg-[var(--bg-base)]">
                        <Info className="w-4 h-4 flex-shrink-0 theme-text-muted" />
                        <span className="text-xs theme-text-muted">
                          Project is paused
                        </span>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="ml-auto text-[var(--text-muted)]"
                        >
                          <HelpCircle className="w-4 h-4" />
                        </Button>
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        ) : (
          <div>
            <DataTable
              data={filteredProjects}
              rowKey={(project) => project.id}
              onRowClick={handleProjectClick}
              rowClassName={(project) =>
                cn(
                  "group",
                  (selectedProjectId === project.id ||
                    openMenuId === project.id) &&
                    "bg-[var(--bg-surface-200)]",
                )
              }
              actionsHeader="Actions"
              actionsClassName="text-right"
              actions={(project) => (
                <RowActionsMenu
                  items={[
                    {
                      label: "Unregister project",
                      icon: "trash",
                      onSelect: () => setConfirmUnregister(project.id),
                    },
                  ]}
                  onOpenChange={(open) =>
                    setOpenMenuId(open ? project.id : null)
                  }
                />
              )}
              columns={[
                {
                  key: "project",
                  header: "Project",
                  cell: (project) => (
                    <div className="flex flex-col">
                      <span className="font-medium text-sm">
                        {getProjectName(project)}
                      </span>
                      <span className="table-secondary text-xs font-mono">
                        {project.git_url.length > 50
                          ? "..." + project.git_url.slice(-47)
                          : project.git_url}
                      </span>
                    </div>
                  ),
                },
                {
                  key: "status",
                  header: "Status",
                  cell: (project) => {
                    const details = projectDetails.get(project.id);
                    if (!details?.status) {
                      return null;
                    }
                    return (
                      <Badge className="gap-1.5">
                        <div
                          className={`w-2 h-2 rounded-full ${getProjectStatusDotClass(details.status)}`}
                        />
                        <span className="uppercase text-[10px] tracking-wider">
                          {details.status}
                        </span>
                      </Badge>
                    );
                  },
                },
                {
                  key: "compute",
                  header: "Compute",
                  cell: () => <span className="table-secondary">-</span>,
                },
                {
                  key: "region",
                  header: "Region",
                  cell: () => <span className="table-secondary">-</span>,
                },
                {
                  key: "created",
                  header: "Created",
                  cell: () => <span className="table-secondary">-</span>,
                },
              ]}
            />
          </div>
        )}
      </DataSurface>

      {/* Register Project Dialog */}

      <Dialog open={isRegisterOpen} onOpenChange={setIsRegisterOpen}>
        <DialogContent className="max-w-md p-0">
          <DialogHeader>
            <div className="flex items-center gap-2">
              <Folder className="w-4 h-4 text-[var(--brand-500)]" />
              <DialogTitle>Register Project</DialogTitle>
            </div>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setIsRegisterOpen(false)}
            >
              <X className="w-4 h-4" />
            </Button>
          </DialogHeader>

          <div className="p-4 space-y-4">
            <div>
              <label className="block text-[10px] font-bold uppercase tracking-wider mb-2 theme-text-muted">
                Git Repository URL *
              </label>
              <Input
                value={registerGitUrl}
                onChange={(e) => setRegisterGitUrl(e.target.value)}
                placeholder="https://github.com/username/repo.git"
                className="h-10"
              />
              <p className="mt-1.5 text-[9px] theme-text-muted">
                Enter the git repository URL for your project
                <br />
                Example: https://github.com/username/projectname.git
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
              disabled={!registerGitUrl.trim() || isRegistering}
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
              <Trash2 className="w-6 h-6 text-[var(--destructive-500)]" />
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

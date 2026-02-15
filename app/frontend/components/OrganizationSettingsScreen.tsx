import React, { useCallback, useEffect, useMemo, useState } from "react";
import { felixApi, Project } from "../services/felixApi";
import {
  AlertTriangle,
  Folder,
  LayoutGrid,
  List,
  Plus,
  Search,
} from "lucide-react";
import { Alert, AlertDescription } from "./ui/alert";
import { Button } from "./ui/button";
import { Card, CardContent } from "./ui/card";
import DataTable from "./DataTable";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { Input } from "./ui/input";
import { PageLoading } from "./ui/page-loading";
import { Tabs, TabsList, TabsTrigger } from "./ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import { cn } from "../lib/utils";

type OrgTab =
  | "members"
  | "projects"
  | "adapters"
  | "agent-templates"
  | "policies"
  | "billing";

const ORG_TABS: Array<{ id: OrgTab; label: string }> = [
  { id: "members", label: "Members and Roles" },
  { id: "projects", label: "Projects" },
  { id: "adapters", label: "Adapters" },
  { id: "agent-templates", label: "Agent Templates" },
  { id: "policies", label: "Policies" },
  { id: "billing", label: "Billing" },
];

interface OrganizationSettingsScreenProps {
  organizationName?: string | null;
  orgSlug?: string | null;
  roleLabel?: string | null;
  onBack: () => void;
}

const OrganizationSettingsScreen: React.FC<OrganizationSettingsScreenProps> = ({
  organizationName,
  orgSlug,
  roleLabel,
  onBack,
}) => {
  const [activeTab, setActiveTab] = useState<OrgTab>("projects");
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectsLoading, setProjectsLoading] = useState(false);
  const [projectsError, setProjectsError] = useState<string | null>(null);
  const [activeProjectId, setActiveProjectId] = useState<string | null>(null);
  const [activeProjectMeta, setActiveProjectMeta] = useState<{
    has_specs: boolean;
    has_plan: boolean;
    has_requirements: boolean;
    spec_count: number;
    status: string | null;
  } | null>(null);
  const [projectDetailsLoading, setProjectDetailsLoading] = useState(false);
  const [projectDetailsError, setProjectDetailsError] = useState<string | null>(
    null,
  );
  const [viewMode, setViewMode] = useState<"cards" | "table">("cards");
  const [searchQuery, setSearchQuery] = useState("");
  const [isRegisterOpen, setIsRegisterOpen] = useState(false);
  const [registerPath, setRegisterPath] = useState("");
  const [registerName, setRegisterName] = useState("");
  const [isRegistering, setIsRegistering] = useState(false);
  const [registerError, setRegisterError] = useState<string | null>(null);

  const fetchProjects = useCallback(async () => {
    setProjectsLoading(true);
    setProjectsError(null);
    try {
      const list = await felixApi.listProjects();
      setProjects(list);
      if (!activeProjectId && list.length > 0) {
        setActiveProjectId(list[0].id);
      }
    } catch (err) {
      setProjectsError(
        err instanceof Error ? err.message : "Failed to load projects",
      );
    } finally {
      setProjectsLoading(false);
    }
  }, [activeProjectId]);

  useEffect(() => {
    if (activeTab === "projects") {
      fetchProjects();
    }
  }, [activeTab, fetchProjects]);

  const fetchProjectDetails = useCallback(async (projectId: string) => {
    setProjectDetailsLoading(true);
    setProjectDetailsError(null);
    try {
      const details = await felixApi.getProject(projectId);
      setActiveProjectMeta({
        has_specs: details.has_specs,
        has_plan: details.has_plan,
        has_requirements: details.has_requirements,
        spec_count: details.spec_count,
        status: details.status,
      });
    } catch (err) {
      setActiveProjectMeta(null);
      setProjectDetailsError(
        err instanceof Error ? err.message : "Failed to load project details",
      );
    } finally {
      setProjectDetailsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeProjectId) {
      fetchProjectDetails(activeProjectId);
    } else {
      setActiveProjectMeta(null);
    }
  }, [activeProjectId, fetchProjectDetails]);


  const activeProject = useMemo(
    () => projects.find((project) => project.id === activeProjectId) || null,
    [projects, activeProjectId],
  );

  const renderProjectsTab = () => {
    if (projectsLoading) {
      return (
        <div className="flex justify-center py-8">
          <PageLoading message="Loading projects..." size="md" fullPage={false} />
        </div>
      );
    }

    if (projectsError) {
      return (
        <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
          <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
            <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
            <div>
              <p className="text-xs">{projectsError}</p>
              <Button
                onClick={fetchProjects}
                variant="ghost"
                size="sm"
                className="mt-2 text-[10px] text-[var(--destructive-500)]"
              >
                Try again
              </Button>
            </div>
          </AlertDescription>
        </Alert>
      );
    }

    const filteredProjects = projects.filter((project) => {
      if (!searchQuery.trim()) return true;
      const query = searchQuery.toLowerCase();
      const name = (project.name || project.id).toLowerCase();
      const path = project.path.toLowerCase();
      return name.includes(query) || path.includes(query);
    });

    const handleOpenProjectSettings = (project: Project) => {
      if (!orgSlug) return;
      const path = `/org/${orgSlug}/projects/${project.id}/settings`;
      window.history.pushState({}, "", path);
      window.dispatchEvent(new PopStateEvent("popstate"));
    };

    const handleRegister = async () => {
      if (!registerPath.trim()) return;
      setIsRegistering(true);
      setRegisterError(null);
      try {
        const created = await felixApi.registerProject({
          path: registerPath.trim(),
          name: registerName.trim() || undefined,
        });
        setRegisterPath("");
        setRegisterName("");
        setIsRegisterOpen(false);
        setActiveProjectId(created.id);
        fetchProjects();
      } catch (err) {
        setRegisterError(
          err instanceof Error ? err.message : "Failed to register project",
        );
      } finally {
        setIsRegistering(false);
      }
    };

    return (
      <div className="space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <h3 className="text-lg font-semibold">Projects</h3>
            <p className="text-xs theme-text-muted mt-1">
              Manage organization projects and open project settings.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64 max-w-full">
              <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 theme-text-muted" />
              <Input
                value={searchQuery}
                onChange={(event) => setSearchQuery(event.target.value)}
                placeholder="Search projects"
                className="h-9 pl-9 text-sm"
              />
            </div>
            <ToggleGroup
              type="single"
              value={viewMode}
              onValueChange={(value) => value && setViewMode(value as "cards" | "table")}
              className="border border-[var(--border)] rounded-md"
            >
              <ToggleGroupItem value="cards" title="Card view" className="h-9 w-9">
                <LayoutGrid className="w-4 h-4" />
              </ToggleGroupItem>
              <ToggleGroupItem value="table" title="Table view" className="h-9 w-9">
                <List className="w-4 h-4" />
              </ToggleGroupItem>
            </ToggleGroup>
            <Button
              onClick={() => setIsRegisterOpen(true)}
              size="sm"
              className="h-9"
            >
              <Plus className="w-4 h-4" />
              New project
            </Button>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)] gap-6">
          <div className="space-y-4">
            {projectsLoading && (
              <div className="flex justify-center py-8">
                <PageLoading message="Loading projects..." size="md" fullPage={false} />
              </div>
            )}

            {projectsError && !projectsLoading && (
              <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
                  <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-xs">{projectsError}</p>
                    <Button
                      onClick={fetchProjects}
                      variant="ghost"
                      size="sm"
                      className="mt-2 text-[10px] text-[var(--destructive-500)]"
                    >
                      Try again
                    </Button>
                  </div>
                </AlertDescription>
              </Alert>
            )}

            {!projectsLoading && !projectsError && filteredProjects.length === 0 && (
              <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-8 text-center">
                <div className="w-12 h-12 theme-bg-surface rounded-xl flex items-center justify-center mx-auto mb-4">
                  <Folder className="w-6 h-6 theme-text-muted" />
                </div>
                <h4 className="text-sm font-bold theme-text-tertiary mb-2">
                  No projects found
                </h4>
                <p className="text-xs theme-text-muted max-w-sm mx-auto">
                  Register a Felix project to get started.
                </p>
              </div>
            )}

            {!projectsLoading && !projectsError && filteredProjects.length > 0 && (
              <>
                {viewMode === "cards" ? (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {filteredProjects.map((project) => {
                      const isSelected = project.id === activeProjectId;
                      return (
                        <Card
                          key={project.id}
                          selectable
                          className={cn(
                            "relative group cursor-pointer",
                            isSelected
                              ? "border-2 border-[var(--brand-500)] bg-[var(--bg-surface-200)]"
                              : "border-[var(--border-default)]",
                          )}
                          onClick={() => setActiveProjectId(project.id)}
                        >
                          <CardContent className="p-4">
                            <div className="flex items-start justify-between mb-3">
                              <div className="flex items-center gap-2 flex-1 min-w-0">
                                <Folder className="w-5 h-5 flex-shrink-0 theme-text-muted" />
                                <h3 className="font-semibold text-sm truncate theme-text-primary">
                                  {project.name || project.id}
                                </h3>
                              </div>
                            </div>
                            <p className="text-xs mb-3 truncate font-mono theme-text-muted">
                              {project.path}
                            </p>
                            <p className="text-[10px] theme-text-muted">
                              Registered {new Date(project.registered_at).toLocaleDateString()}
                            </p>
                          </CardContent>
                        </Card>
                      );
                    })}
                  </div>
                ) : (
                  <DataTable
                    data={filteredProjects}
                    rowKey={(project) => project.id}
                    onRowClick={(project) => setActiveProjectId(project.id)}
                    rowClassName={(project) =>
                      cn(
                        "group cursor-pointer",
                        project.id === activeProjectId &&
                          "bg-[var(--bg-surface-200)]",
                      )
                    }
                    columns={[
                      {
                        key: "project",
                        header: "Project",
                        cell: (project) => (
                          <div className="flex flex-col">
                            <span className="font-medium text-sm">
                              {project.name || project.id}
                            </span>
                            <span className="table-secondary text-xs font-mono">
                              {project.path.length > 40
                                ? "..." + project.path.slice(-37)
                                : project.path}
                            </span>
                          </div>
                        ),
                      },
                      {
                        key: "registered",
                        header: "Registered",
                        cell: (project) => (
                          <span className="table-secondary text-xs">
                            {new Date(project.registered_at).toLocaleDateString()}
                          </span>
                        ),
                      },
                    ]}
                  />
                )}
              </>
            )}
          </div>

          <div className="space-y-4">
            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
              {activeProject ? (
                <>
                  <h4 className="text-sm font-bold theme-text-secondary mb-2">
                    {activeProject.name || activeProject.id}
                  </h4>
                  <p className="text-xs theme-text-muted mb-4">
                    {activeProject.path}
                  </p>
                  <div className="text-[10px] theme-text-muted mb-4">
                    Registered{" "}
                    {new Date(activeProject.registered_at).toLocaleDateString()}
                  </div>
                  {projectDetailsLoading && (
                    <div className="text-xs theme-text-muted mb-4">
                      Loading details...
                    </div>
                  )}
                  {projectDetailsError && (
                    <div className="text-xs text-[var(--destructive-500)] mb-4">
                      {projectDetailsError}
                    </div>
                  )}
                  {!projectDetailsLoading && activeProjectMeta && (
                    <div className="grid grid-cols-2 gap-3 text-[11px] theme-text-muted mb-4">
                      <div>
                        <span className="block text-[10px] uppercase tracking-wide">
                          Specs
                        </span>
                        <span className="text-sm font-semibold theme-text-secondary">
                          {activeProjectMeta.spec_count}
                        </span>
                      </div>
                      <div>
                        <span className="block text-[10px] uppercase tracking-wide">
                          Requirements
                        </span>
                        <span className="text-sm font-semibold theme-text-secondary">
                          {activeProjectMeta.has_requirements ? "Yes" : "No"}
                        </span>
                      </div>
                      <div>
                        <span className="block text-[10px] uppercase tracking-wide">
                          Plan
                        </span>
                        <span className="text-sm font-semibold theme-text-secondary">
                          {activeProjectMeta.has_plan ? "Yes" : "No"}
                        </span>
                      </div>
                      <div>
                        <span className="block text-[10px] uppercase tracking-wide">
                          Status
                        </span>
                        <span className="text-sm font-semibold theme-text-secondary">
                          {activeProjectMeta.status || "Unknown"}
                        </span>
                      </div>
                    </div>
                  )}
                  <div className="flex flex-col gap-2">
                    <Button
                      onClick={() => handleOpenProjectSettings(activeProject)}
                      size="sm"
                      className="uppercase"
                    >
                      Open Project Settings
                    </Button>
                  </div>
                </>
              ) : (
                <div className="text-xs theme-text-muted">
                  Select a project to see details.
                </div>
              )}
            </div>
            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
              <h4 className="text-sm font-bold theme-text-secondary mb-2">
                Register a Project
              </h4>
              <p className="text-xs theme-text-muted mb-4">
                Add a new Felix project to this organization.
              </p>
              <Button
                onClick={() => setIsRegisterOpen(true)}
                size="sm"
                className="uppercase"
              >
                New Project
              </Button>
            </div>
          </div>
        </div>

        <Dialog open={isRegisterOpen} onOpenChange={setIsRegisterOpen}>
          <DialogContent className="max-w-md p-0">
            <DialogHeader>
              <div className="flex items-center gap-2">
                <Folder className="w-4 h-4 text-[var(--brand-500)]" />
                <DialogTitle>Register Project</DialogTitle>
              </div>
            </DialogHeader>
            <div className="p-4 space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider mb-2 theme-text-muted">
                  Project Path *
                </label>
                <Input
                  value={registerPath}
                  onChange={(e) => setRegisterPath(e.target.value)}
                  placeholder="C:\\path\\to\\your\\project"
                  className="h-10"
                />
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
              {registerError && (
                <Alert className="border-[var(--destructive-500)]/20 bg-[var(--destructive-500)]/10">
                  <AlertDescription className="text-[var(--destructive-500)]">
                    {registerError}
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
      </div>
    );
  };

  const renderPlaceholder = (title: string) => (
    <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-xs theme-text-muted">
        This section is ready for organization-level configuration.
      </p>
    </div>
  );

  const renderActiveTab = () => {
    if (activeTab === "projects") {
      return renderProjectsTab();
    }
    const tab = ORG_TABS.find((entry) => entry.id === activeTab);
    return renderPlaceholder(tab?.label || "Settings");
  };

  return (
    <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
      <div className="bg-[var(--bg-base)] px-6 pt-8 pb-2">
        <div className="max-w-5xl mx-auto">
          <div className="flex items-start justify-between gap-6">
            <div>
              <h1 className="text-2xl font-semibold theme-text-primary">
                Organization Settings
              </h1>
              <p className="mt-2 text-xs theme-text-muted">
                {organizationName || "Organization"}
              </p>
              {roleLabel && (
                <span className="inline-flex mt-2 text-[10px] font-bold px-2 py-1 rounded-full border border-[var(--border-muted)] text-[var(--text-muted)]">
                  {roleLabel}
                </span>
              )}
            </div>
            <Button onClick={onBack} variant="ghost" size="sm">
              Back to Projects
            </Button>
          </div>
          <div className="mt-6 border-b border-[var(--border-default)]">
            <Tabs
              value={activeTab}
              onValueChange={(value) => setActiveTab(value as OrgTab)}
            >
              <TabsList
                variant="line"
                className="w-full justify-start gap-6 overflow-x-auto overflow-y-hidden whitespace-nowrap"
              >
                {ORG_TABS.map((tab) => (
                  <TabsTrigger
                    key={tab.id}
                    value={tab.id}
                    variant="line"
                    className="text-sm font-medium whitespace-nowrap"
                  >
                    {tab.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar p-8 theme-bg-base">
        <div className="max-w-5xl mx-auto">{renderActiveTab()}</div>
      </div>
    </div>
  );
};

export default OrganizationSettingsScreen;

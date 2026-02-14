import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  felixApi,
  FelixConfig,
  Project,
} from "../services/felixApi";
import { AlertTriangle } from "lucide-react";
import { Alert, AlertDescription } from "./ui/alert";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { PageLoading } from "./ui/page-loading";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { Switch } from "./ui/switch";
import { Tabs, TabsList, TabsTrigger } from "./ui/tabs";

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
  roleLabel?: string | null;
  onBack: () => void;
}

const OrganizationSettingsScreen: React.FC<OrganizationSettingsScreenProps> = ({
  organizationName,
  roleLabel,
  onBack,
}) => {
  const [activeTab, setActiveTab] = useState<OrgTab>("projects");
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectsLoading, setProjectsLoading] = useState(false);
  const [projectsError, setProjectsError] = useState<string | null>(null);
  const [activeProjectId, setActiveProjectId] = useState<string | null>(null);
  const [projectConfig, setProjectConfig] = useState<FelixConfig | null>(null);
  const [originalConfig, setOriginalConfig] = useState<FelixConfig | null>(null);
  const [configLoading, setConfigLoading] = useState(false);
  const [configSaving, setConfigSaving] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<
    Record<string, string>
  >({});

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

  const fetchProjectConfig = useCallback(async (projectId: string) => {
    setConfigLoading(true);
    setConfigError(null);
    try {
      const result = await felixApi.getConfig(projectId);
      setProjectConfig(result.config);
      setOriginalConfig(result.config);
    } catch (err) {
      setConfigError(
        err instanceof Error ? err.message : "Failed to load project settings",
      );
    } finally {
      setConfigLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeTab === "projects") {
      fetchProjects();
    }
  }, [activeTab, fetchProjects]);

  useEffect(() => {
    if (activeProjectId) {
      fetchProjectConfig(activeProjectId);
    }
  }, [activeProjectId, fetchProjectConfig]);

  const validateConfig = useCallback((cfg: FelixConfig) => {
    const errors: Record<string, string> = {};
    if (!Number.isInteger(cfg.executor.max_iterations) || cfg.executor.max_iterations <= 0) {
      errors.max_iterations = "Must be a positive integer";
    }
    if (!["planning", "building"].includes(cfg.executor.default_mode)) {
      errors.default_mode = 'Must be "planning" or "building"';
    }
    if (cfg.backpressure.max_retries !== undefined) {
      if (!Number.isInteger(cfg.backpressure.max_retries) || cfg.backpressure.max_retries < 0) {
        errors.max_retries = "Must be a non-negative integer";
      }
    }
    return errors;
  }, []);

  const handleExecutorChange = (
    field: keyof FelixConfig["executor"],
    value: any,
  ) => {
    if (!projectConfig) return;
    const next = {
      ...projectConfig,
      executor: { ...projectConfig.executor, [field]: value },
    };
    setProjectConfig(next);
    setValidationErrors(validateConfig(next));
  };

  const handleBackpressureChange = (
    field: keyof FelixConfig["backpressure"],
    value: any,
  ) => {
    if (!projectConfig) return;
    const next = {
      ...projectConfig,
      backpressure: { ...projectConfig.backpressure, [field]: value },
    };
    setProjectConfig(next);
    setValidationErrors(validateConfig(next));
  };

  const handleSave = async () => {
    if (!projectConfig || !activeProjectId) return;
    const errors = validateConfig(projectConfig);
    if (Object.keys(errors).length > 0) {
      setValidationErrors(errors);
      return;
    }

    setConfigSaving(true);
    setConfigError(null);
    try {
      const result = await felixApi.updateConfig(activeProjectId, projectConfig);
      setProjectConfig(result.config);
      setOriginalConfig(result.config);
    } catch (err) {
      setConfigError(
        err instanceof Error ? err.message : "Failed to save project settings",
      );
    } finally {
      setConfigSaving(false);
    }
  };

  const hasChanges =
    projectConfig &&
    originalConfig &&
    JSON.stringify(projectConfig) !== JSON.stringify(originalConfig);

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

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-lg font-semibold">Project Settings</h3>
            <p className="text-xs theme-text-muted mt-1">
              Changes here affect all project members.
            </p>
          </div>
          <div className="flex items-center gap-3">
            {activeProject && (
              <Select
                value={activeProjectId || ""}
                onValueChange={setActiveProjectId}
              >
                <SelectTrigger className="w-56">
                  <SelectValue placeholder="Select project" />
                </SelectTrigger>
                <SelectContent>
                  {projects.map((project) => (
                    <SelectItem key={project.id} value={project.id}>
                      {project.name || project.id}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
            <Button
              onClick={handleSave}
              disabled={!hasChanges || configSaving || Object.keys(validationErrors).length > 0}
              size="sm"
              className="text-[10px] font-bold uppercase"
            >
              {configSaving ? "Saving..." : "Save Project Changes"}
            </Button>
          </div>
        </div>

        {configError && (
          <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
            <AlertDescription className="text-xs text-[var(--destructive-500)]">
              {configError}
            </AlertDescription>
          </Alert>
        )}

        {configLoading && (
          <div className="flex justify-center py-8">
            <PageLoading message="Loading settings..." size="md" fullPage={false} />
          </div>
        )}

        {!configLoading && projectConfig && (
          <div className="space-y-6">
            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
              <h4 className="text-sm font-bold theme-text-secondary mb-4">
                General
              </h4>
              <div className="space-y-4">
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Max Iterations
                  </label>
                  <Input
                    type="number"
                    min="1"
                    value={projectConfig.executor.max_iterations}
                    onChange={(e) =>
                      handleExecutorChange(
                        "max_iterations",
                        parseInt(e.target.value) || 0,
                      )
                    }
                    className={
                      validationErrors.max_iterations
                        ? "border-[var(--destructive-500)]/50 focus-visible:ring-[var(--destructive-500)]"
                        : ""
                    }
                  />
                  {validationErrors.max_iterations && (
                    <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                      {validationErrors.max_iterations}
                    </p>
                  )}
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Default Mode
                  </label>
                  <Select
                    value={projectConfig.executor.default_mode}
                    onValueChange={(value) =>
                      handleExecutorChange("default_mode", value)
                    }
                  >
                    <SelectTrigger
                      aria-label="Default Mode"
                      className={
                        validationErrors.default_mode
                          ? "border-[var(--destructive-500)]/50 focus-visible:ring-[var(--destructive-500)]"
                          : ""
                      }
                    >
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="planning">Planning</SelectItem>
                      <SelectItem value="building">Building</SelectItem>
                    </SelectContent>
                  </Select>
                  {validationErrors.default_mode && (
                    <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                      {validationErrors.default_mode}
                    </p>
                  )}
                </div>
                <div className="flex items-center justify-between">
                  <div>
                    <label className="block text-xs font-bold theme-text-tertiary">
                      Auto Transition
                    </label>
                    <p className="text-[10px] theme-text-muted mt-1">
                      Automatically switch from planning to building
                    </p>
                  </div>
                  <Switch
                    checked={projectConfig.executor.auto_transition}
                    onCheckedChange={(checked) =>
                      handleExecutorChange("auto_transition", checked)
                    }
                  />
                </div>
              </div>
            </div>

            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
              <h4 className="text-sm font-bold theme-text-secondary mb-4">
                Backpressure
              </h4>
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <label className="block text-xs font-bold theme-text-tertiary">
                      Enable Backpressure
                    </label>
                    <p className="text-[10px] theme-text-muted mt-1">
                      Run validation between iterations
                    </p>
                  </div>
                  <Switch
                    checked={projectConfig.backpressure.enabled}
                    onCheckedChange={(checked) =>
                      handleBackpressureChange("enabled", checked)
                    }
                  />
                </div>
                {projectConfig.backpressure.enabled && (
                  <div>
                    <label className="block text-xs font-bold theme-text-tertiary mb-2">
                      Max Retries
                    </label>
                    <Input
                      type="number"
                      min="0"
                      value={(projectConfig.backpressure as any).max_retries || 3}
                      onChange={(e) =>
                        handleBackpressureChange(
                          "max_retries",
                          parseInt(e.target.value) || 0,
                        )
                      }
                      className={
                        validationErrors.max_retries
                          ? "border-[var(--destructive-500)]/50 focus-visible:ring-[var(--destructive-500)]"
                          : ""
                      }
                    />
                    {validationErrors.max_retries && (
                      <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                        {validationErrors.max_retries}
                      </p>
                    )}
                  </div>
                )}
                {projectConfig.backpressure.commands.length > 0 && (
                  <div className="theme-bg-base border border-[var(--border-muted)] rounded-lg p-4 space-y-2">
                    {projectConfig.backpressure.commands.map((cmd, index) => (
                      <code key={index} className="text-xs font-mono theme-text-tertiary block">
                        {index + 1}. {cmd}
                      </code>
                    ))}
                  </div>
                )}
              </div>
            </div>

            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
              <h4 className="text-sm font-bold theme-text-secondary mb-4">
                Paths
              </h4>
              <div className="space-y-2 text-xs theme-text-muted">
                <div className="flex items-center justify-between">
                  <span>Specs</span>
                  <code className="font-mono">{projectConfig.paths.specs}</code>
                </div>
                <div className="flex items-center justify-between">
                  <span>AGENTS.md</span>
                  <code className="font-mono">{projectConfig.paths.agents}</code>
                </div>
                <div className="flex items-center justify-between">
                  <span>Runs</span>
                  <code className="font-mono">{projectConfig.paths.runs}</code>
                </div>
              </div>
            </div>
          </div>
        )}
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
        <div className="max-w-3xl mx-auto">
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
                className="w-full justify-start flex-wrap gap-6"
              >
                {ORG_TABS.map((tab) => (
                  <TabsTrigger
                    key={tab.id}
                    value={tab.id}
                    variant="line"
                    className="text-sm font-medium"
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
        <div className="max-w-3xl mx-auto">{renderActiveTab()}</div>
      </div>
    </div>
  );
};

export default OrganizationSettingsScreen;

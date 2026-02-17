import React, { useState, useEffect, useCallback } from "react";
import { toast } from "sonner";
import {
  felixApi,
  FelixConfig,
  ProjectDetails,
  AgentConfiguration,
  ApiKeyInfo,
  ApiKeyCreated,
  ApiKeyListResponse,
} from "../services/felixApi";
import { listAgents, registerAgent } from "../src/api/client";
import type { Agent } from "../src/api/types";
import {
  AlertTriangle,
  Check,
  Info,
  Plus,
  RefreshCw,
  X,
  Settings as IconSettings,
  Folder as IconFolder,
  Code as IconCode,
  FileText as IconFileText,
  Briefcase as IconBriefcase,
  Cpu as IconCpu,
  Key as IconKey,
} from "lucide-react";
import { Alert, AlertDescription } from "./ui/alert";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { PageLoading } from "./ui/page-loading";
import { Tabs, TabsList, TabsTrigger } from "./ui/tabs";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { Switch } from "./ui/switch";
import MarkdownEditor from "./MarkdownEditor";

interface SettingsScreenProps {
  projectId?: string; // Optional - when undefined, uses global settings API
  onBack: () => void;
}

type SettingsCategory =
  | "general"
  | "paths"
  | "advanced"
  | "projects"
  | "agents"
  | "api-keys"
  | "docs";

type DocFileName = "README.md" | "CONTEXT.md" | "AGENTS.md";

interface CategoryInfo {
  id: SettingsCategory;
  label: string;
  description: string;
  icon: React.ReactNode;
}

const CATEGORIES: CategoryInfo[] = [
  {
    id: "general",
    label: "General",
    description: "Basic Felix configuration",
    icon: <IconSettings className="w-4 h-4" />,
  },
  {
    id: "paths",
    label: "Paths",
    description: "File and directory locations",
    icon: <IconFolder className="w-4 h-4" />,
  },
  {
    id: "advanced",
    label: "Advanced",
    description: "Developer and debug options",
    icon: <IconCode className="w-4 h-4" />,
  },
  {
    id: "projects",
    label: "Projects",
    description: "Edit the current project",
    icon: <IconBriefcase className="w-4 h-4" />,
  },
  {
    id: "agents",
    label: "Agents",
    description: "Agent registry and status",
    icon: <IconCpu className="w-4 h-4" />,
  },
  {
    id: "api-keys",
    label: "API Keys",
    description: "Manage project API keys for CLI sync",
    icon: <IconKey className="w-4 h-4" />,
  },
  {
    id: "docs",
    label: "Docs",
    description: "Project documentation files",
    icon: <IconFileText className="w-4 h-4" />,
  },
];

const SettingsScreen: React.FC<SettingsScreenProps> = ({
  projectId,
  onBack,
}) => {
  const [activeCategory, setActiveCategory] =
    useState<SettingsCategory>("general");
  const [config, setConfig] = useState<FelixConfig | null>(null);
  const [originalConfig, setOriginalConfig] = useState<FelixConfig | null>(
    null,
  );
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saveMessage, setSaveMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);
  const [validationErrors, setValidationErrors] = useState<
    Record<string, string>
  >({});

  // Current project state
  const [currentProject, setCurrentProject] = useState<ProjectDetails | null>(
    null,
  );
  const [currentProjectLoading, setCurrentProjectLoading] = useState(false);
  const [currentProjectError, setCurrentProjectError] = useState<string | null>(
    null,
  );
  const [configProjectName, setConfigProjectName] = useState("");
  const [configProjectPath, setConfigProjectPath] = useState("");
  const [configProjectGitRepo, setConfigProjectGitRepo] = useState("");

  // Agents state (project agents)
  const [projectAgents, setProjectAgents] = useState<Agent[]>([]);
  const [projectAgentsLoading, setProjectAgentsLoading] = useState(false);
  const [projectAgentsError, setProjectAgentsError] = useState<string | null>(
    null,
  );
  const [agentFormType, setAgentFormType] = useState<string>("ralph");
  const [agentFormProfileId, setAgentFormProfileId] = useState<string>("");
  const [agentProfiles, setAgentProfiles] = useState<AgentConfiguration[]>([]);
  const [agentProfilesLoading, setAgentProfilesLoading] = useState(false);
  const [agentProfilesError, setAgentProfilesError] = useState<string | null>(
    null,
  );

  // API Keys state (project-scoped)
  const [apiKeys, setApiKeys] = useState<ApiKeyInfo[]>([]);
  const [apiKeysLoading, setApiKeysLoading] = useState(false);
  const [apiKeysError, setApiKeysError] = useState<string | null>(null);
  const [showApiKeyForm, setShowApiKeyForm] = useState(false);
  const [apiKeyFormName, setApiKeyFormName] = useState("");
  const [apiKeyFormExpiresDays, setApiKeyFormExpiresDays] = useState<
    number | undefined
  >(undefined);
  const [apiKeyFormSaving, setApiKeyFormSaving] = useState(false);
  const [createdApiKey, setCreatedApiKey] = useState<ApiKeyCreated | null>(
    null,
  );

  // Agent configurations state (legacy)

  // Agent form state (for add/edit)
  const [showAgentForm, setShowAgentForm] = useState(false);
  const [editingAgentId, setEditingAgentId] = useState<string | null>(null);
  const [agentFormName, setAgentFormName] = useState("");
  const [agentFormSaving, setAgentFormSaving] = useState(false);
  const [agentFormError, setAgentFormError] = useState<string | null>(null);
  const [agentNameValidationError, setAgentNameValidationError] = useState<
    string | null
  >(null);

  const [activeDoc, setActiveDoc] = useState<DocFileName>("README.md");
  const [docContents, setDocContents] = useState<Record<DocFileName, string>>({
    "README.md": "",
    "CONTEXT.md": "",
    "AGENTS.md": "",
  });
  const [docOriginals, setDocOriginals] = useState<Record<DocFileName, string>>(
    {
      "README.md": "",
      "CONTEXT.md": "",
      "AGENTS.md": "",
    },
  );
  const [docsLoaded, setDocsLoaded] = useState<Record<DocFileName, boolean>>({
    "README.md": false,
    "CONTEXT.md": false,
    "AGENTS.md": false,
  });
  const [docsLoading, setDocsLoading] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);
  const [docsSaving, setDocsSaving] = useState(false);
  const [docsSaveMessage, setDocsSaveMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);

  // Fetch config on mount and sync theme
  // Uses global settings API when no projectId is provided
  useEffect(() => {
    const fetchConfig = async () => {
      setLoading(true);
      setError(null);
      setSaveMessage(null);

      try {
        // Use global settings API when no projectId, otherwise use project-specific API
        const result = projectId
          ? await felixApi.getConfig(projectId)
          : await felixApi.getGlobalConfig();
        setConfig(result.config);
        setOriginalConfig(result.config);
      } catch (err) {
        console.error("Failed to fetch config:", err);
        setError(
          err instanceof Error ? err.message : "Failed to load configuration",
        );
      } finally {
        setLoading(false);
      }
    };

    fetchConfig();
  }, [projectId]);

  // Fetch current project when Projects category is selected
  const fetchCurrentProject = useCallback(async () => {
    if (!projectId) {
      setCurrentProject(null);
      return;
    }
    setCurrentProjectLoading(true);
    setCurrentProjectError(null);
    try {
      const project = await felixApi.getProject(projectId);
      setCurrentProject(project);
      setConfigProjectName(project.name || "");
      setConfigProjectPath(project.path);
      setConfigProjectGitRepo(project.git_repo || "");
    } catch (err) {
      console.error("Failed to fetch project:", err);
      setCurrentProjectError(
        err instanceof Error ? err.message : "Failed to load project",
      );
    } finally {
      setCurrentProjectLoading(false);
    }
  }, [projectId]);

  useEffect(() => {
    if (activeCategory === "projects") {
      fetchCurrentProject();
    }
  }, [activeCategory, fetchCurrentProject]);

  // Fetch agents when Agents category is selected
  const fetchProjectAgents = useCallback(async () => {
    if (!projectId) {
      setProjectAgents([]);
      return;
    }
    setProjectAgentsLoading(true);
    setProjectAgentsError(null);
    try {
      const response = await listAgents({
        scope: "project",
        projectId,
      });
      setProjectAgents(response.agents);
    } catch (err) {
      console.error("Failed to fetch project agents:", err);
      setProjectAgentsError(
        err instanceof Error ? err.message : "Failed to load agents",
      );
    } finally {
      setProjectAgentsLoading(false);
    }
  }, [projectId]);

  const fetchAgentProfiles = useCallback(async () => {
    setAgentProfilesLoading(true);
    setAgentProfilesError(null);
    try {
      const response = await felixApi.getAgentConfigurations();
      console.log("[SettingsScreen] Agent profiles response:", response);
      console.log(
        "[SettingsScreen] Individual profiles:",
        response.agents.map((p) => ({ id: p.id, name: p.name })),
      );

      // Filter out any profiles without valid IDs to prevent React key errors
      const validProfiles = response.agents.filter(
        (profile) => profile.id != null && profile.id !== "",
      );

      if (validProfiles.length !== response.agents.length) {
        console.warn(
          `[SettingsScreen] Filtered out ${response.agents.length - validProfiles.length} profiles without valid IDs`,
          response.agents.filter((p) => !p.id || p.id === ""),
        );
      }

      setAgentProfiles(validProfiles);
    } catch (err) {
      console.error("Failed to fetch agent profiles:", err);
      setAgentProfilesError(
        err instanceof Error ? err.message : "Failed to load agent profiles",
      );
    } finally {
      setAgentProfilesLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeCategory === "agents") {
      fetchProjectAgents();
      fetchAgentProfiles();
    }
  }, [activeCategory, fetchProjectAgents, fetchAgentProfiles]);

  useEffect(() => {
    if (!projectId) {
      return;
    }
    setActiveDoc("README.md");
    setDocContents({
      "README.md": "",
      "CONTEXT.md": "",
      "AGENTS.md": "",
    });
    setDocOriginals({
      "README.md": "",
      "CONTEXT.md": "",
      "AGENTS.md": "",
    });
    setDocsLoaded({
      "README.md": false,
      "CONTEXT.md": false,
      "AGENTS.md": false,
    });
    setDocsError(null);
    setDocsSaveMessage(null);
  }, [projectId]);

  const fetchDoc = useCallback(
    async (docName: DocFileName) => {
      if (!projectId) return;
      setDocsLoading(true);
      setDocsError(null);

      try {
        const response = await felixApi.getProjectFile(projectId, docName);
        const content = response.content || "";
        setDocContents((prev) => ({ ...prev, [docName]: content }));
        setDocOriginals((prev) => ({ ...prev, [docName]: content }));
        setDocsLoaded((prev) => ({ ...prev, [docName]: true }));
      } catch (err) {
        console.error("Failed to fetch project file:", err);
        setDocsError(
          err instanceof Error ? err.message : "Failed to load project file",
        );
        setDocContents((prev) => ({ ...prev, [docName]: "" }));
        setDocOriginals((prev) => ({ ...prev, [docName]: "" }));
        setDocsLoaded((prev) => ({ ...prev, [docName]: true }));
      } finally {
        setDocsLoading(false);
      }
    },
    [projectId],
  );

  useEffect(() => {
    if (activeCategory !== "docs" || !projectId) return;
    if (!docsLoaded[activeDoc]) {
      fetchDoc(activeDoc);
    }
  }, [activeCategory, activeDoc, docsLoaded, fetchDoc, projectId]);

  useEffect(() => {
    if (docsSaveMessage) {
      const timeout = setTimeout(() => setDocsSaveMessage(null), 3000);
      return () => clearTimeout(timeout);
    }
  }, [docsSaveMessage]);

  // Validate config
  const validateConfig = useCallback(
    (cfg: FelixConfig): Record<string, string> => {
      const errors: Record<string, string> = {};

      // Validate max_iterations
      if (
        !Number.isInteger(cfg.executor.max_iterations) ||
        cfg.executor.max_iterations <= 0
      ) {
        errors.max_iterations = "Must be a positive integer";
      }

      // Validate default_mode
      if (!["planning", "building"].includes(cfg.executor.default_mode)) {
        errors.default_mode = 'Must be "planning" or "building"';
      }

      // Validate backpressure max_retries if present
      if (cfg.backpressure.max_retries !== undefined) {
        if (
          !Number.isInteger(cfg.backpressure.max_retries) ||
          cfg.backpressure.max_retries < 0
        ) {
          errors.max_retries = "Must be a non-negative integer";
        }
      }

      return errors;
    },
    [],
  );

  // Validate agent name
  const validateAgentName = useCallback((name: string): string | null => {
    if (!name || !name.trim()) {
      return "Agent name cannot be empty";
    }
    // Agent name must be alphanumeric with hyphens and underscores only
    if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
      return "Agent name must be alphanumeric with hyphens and underscores only";
    }
    return null;
  }, []);

  // Handle agent name input change
  const handleAgentNameInputChange = (value: string) => {
    setAgentFormName(value);
    setAgentNameValidationError(validateAgentName(value));
  };

  // Get relative time string
  const getRelativeTime = useCallback(
    (timestamp: string | null | undefined): string => {
      if (!timestamp) return "Never";

      try {
        const date = new Date(timestamp);
        const now = new Date();
        const diffMs = now.getTime() - date.getTime();
        const diffSec = Math.floor(diffMs / 1000);

        if (diffSec < 5) return "Just now";
        if (diffSec < 60) return `${diffSec}s ago`;

        const diffMin = Math.floor(diffSec / 60);
        if (diffMin < 60) return `${diffMin}m ago`;

        const diffHour = Math.floor(diffMin / 60);
        if (diffHour < 24) return `${diffHour}h ago`;

        const diffDay = Math.floor(diffHour / 24);
        return `${diffDay}d ago`;
      } catch {
        return "Unknown";
      }
    },
    [],
  );

  // Handle config field changes
  const handleExecutorChange = (
    field: keyof FelixConfig["executor"],
    value: any,
  ) => {
    if (!config) return;

    const newConfig = {
      ...config,
      executor: {
        ...config.executor,
        [field]: value,
      },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  const handleBackpressureChange = (
    field: keyof FelixConfig["backpressure"],
    value: any,
  ) => {
    if (!config) return;

    const newConfig = {
      ...config,
      backpressure: {
        ...config.backpressure,
        [field]: value,
      },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  const handleUIChange = (field: keyof FelixConfig["ui"], value: any) => {
    if (!config) return;

    const newConfig = {
      ...config,
      ui: {
        ...config.ui,
        [field]: value,
      },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  // Handle save
  // Uses global settings API when no projectId, otherwise uses project-specific API
  const hasConfigChanges =
    config &&
    originalConfig &&
    JSON.stringify(config) !== JSON.stringify(originalConfig);

  const hasProjectChanges =
    !!currentProject &&
    (configProjectName.trim() !== (currentProject.name || "") ||
      configProjectPath.trim() !== currentProject.path ||
      configProjectGitRepo.trim() !== (currentProject.git_repo || ""));

  const hasChanges = !!(hasConfigChanges || hasProjectChanges);

  const handleSave = async () => {
    if (!config) return;

    const errors = validateConfig(config);
    if (hasConfigChanges && Object.keys(errors).length > 0) {
      setValidationErrors(errors);
      return;
    }

    setSaving(true);
    setError(null);
    setSaveMessage(null);

    try {
      if (hasConfigChanges) {
        const result = projectId
          ? await felixApi.updateConfig(projectId, config)
          : await felixApi.updateGlobalConfig(config);
        setConfig(result.config);
        setOriginalConfig(result.config);
      }

      if (hasProjectChanges && currentProject) {
        setCurrentProjectError(null);
        const pathChanged = configProjectPath.trim() !== currentProject.path;
        const gitRepoChanged =
          configProjectGitRepo.trim() !== (currentProject.git_repo || "");
        const updated = await felixApi.updateProject(currentProject.id, {
          name: configProjectName.trim() || undefined,
          path: pathChanged ? configProjectPath.trim() : undefined,
          git_repo: gitRepoChanged
            ? configProjectGitRepo.trim() || null
            : undefined,
        });
        setCurrentProject({
          ...currentProject,
          name: updated.name,
          path: updated.path,
          git_repo: updated.git_repo,
        });
      }

      if (hasConfigChanges && hasProjectChanges) {
        toast.success("Settings saved successfully");
        setSaveMessage({
          type: "success",
          text: "Settings saved successfully",
        });
      } else if (hasProjectChanges) {
        toast.success("Project updated successfully");
        setSaveMessage({
          type: "success",
          text: "Project updated successfully",
        });
      } else if (hasConfigChanges) {
        toast.success("Configuration saved successfully");
        setSaveMessage({
          type: "success",
          text: "Configuration saved successfully",
        });
      }
    } catch (err) {
      console.error("Failed to save settings:", err);
      const message =
        err instanceof Error ? err.message : "Failed to save settings";
      setError(message);
      setSaveMessage({
        type: "error",
        text: message,
      });
      if (hasProjectChanges) {
        setCurrentProjectError(message);
      }
    } finally {
      setSaving(false);
    }
  };

  useEffect(() => {
    if (!saveMessage) return undefined;
    const timeout = setTimeout(() => setSaveMessage(null), 3000);
    return () => clearTimeout(timeout);
  }, [saveMessage]);

  // Reset to original config
  const handleReset = () => {
    if (originalConfig) {
      setConfig(originalConfig);
      setValidationErrors({});
    }
    if (currentProject) {
      setConfigProjectName(currentProject.name || "");
      setConfigProjectPath(currentProject.path);
      setConfigProjectGitRepo(currentProject.git_repo || "");
      setCurrentProjectError(null);
    }
  };

  // Reset category to defaults
  const handleResetCategory = () => {
    if (!config || !originalConfig) return;

    // Reset only the current category's settings
    const newConfig = { ...config };
    switch (activeCategory) {
      case "general":
        newConfig.executor = { ...originalConfig.executor };
        break;
      case "agent":
        newConfig.agent = { ...originalConfig.agent };
        break;
      case "advanced":
        newConfig.backpressure = { ...originalConfig.backpressure };
        break;
      // paths is read-only, no reset needed
    }

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  // Render General settings
  const renderGeneralSettings = () => {
    if (!config) return null;

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold">General Settings</h3>
            <p className="text-xs theme-text-muted mt-1">
              Basic Felix configuration options
            </p>
          </div>
          <Button
            onClick={handleResetCategory}
            variant="ghost"
            size="sm"
            className="text-[10px] font-bold"
          >
            Reset to Defaults
          </Button>
        </div>

        {/* Max Iterations */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Max Iterations
          </label>
          <Input
            type="number"
            min="1"
            value={config.executor.max_iterations}
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
          <p className="mt-2 text-[11px] theme-text-muted">
            Maximum number of iterations the agent will run before stopping
          </p>
        </div>

        {/* Default Mode */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Default Mode
          </label>
          <Select
            value={config.executor.default_mode}
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
          <p className="mt-2 text-[11px] theme-text-muted">
            Mode the agent starts in when a run begins
          </p>
        </div>

        {/* Auto Transition */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <div className="flex items-center justify-between">
            <div>
              <label className="block text-sm font-bold theme-text-secondary">
                Auto Transition
              </label>
              <p className="text-[11px] theme-text-muted mt-1">
                Automatically switch from planning to building mode when plan is
                complete
              </p>
            </div>
            <Switch
              checked={config.executor.auto_transition}
              onCheckedChange={(checked) =>
                handleExecutorChange("auto_transition", checked)
              }
            />
          </div>
        </div>
      </div>
    );
  };

  // Render Paths settings (read-only)
  const renderPathsSettings = () => {
    if (!config) return null;

    return (
      <div className="space-y-6">
        <div className="mb-6">
          <h3 className="text-lg font-semibold">Paths</h3>
          <p className="text-xs theme-text-muted mt-1">
            File and directory locations (read-only)
          </p>
        </div>

        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl overflow-hidden">
          <div className="divide-y divide-[var(--border-default)]">
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm theme-text-secondary">
                  Specs Directory
                </span>
                <p className="text-[10px] theme-text-muted mt-0.5">
                  Location of specification files
                </p>
              </div>
              <code className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg">
                {config.paths.specs}
              </code>
            </div>
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm theme-text-secondary">AGENTS.md</span>
                <p className="text-[10px] theme-text-muted mt-0.5">
                  Agent instructions file
                </p>
              </div>
              <code className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg">
                {config.paths.agents}
              </code>
            </div>
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm theme-text-secondary">
                  Runs Directory
                </span>
                <p className="text-[10px] theme-text-muted mt-0.5">
                  Location of run artifacts
                </p>
              </div>
              <code className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg">
                {config.paths.runs}
              </code>
            </div>
          </div>
        </div>

        <Alert className="border-[var(--warning-500)]/30 bg-[var(--warning-500)]/10 text-[var(--warning-500)]">
          <AlertDescription className="flex items-start gap-3 text-[var(--warning-500)]/80">
            <Info className="w-4 h-4 mt-0.5 flex-shrink-0" />
            <p className="text-xs">
              Path settings are read-only. Edit{" "}
              <code className="bg-[var(--warning-500)]/10 px-1 rounded">
                felix/config.json
              </code>{" "}
              directly to modify these values.
            </p>
          </AlertDescription>
        </Alert>
      </div>
    );
  };

  // Render Advanced settings
  const renderAdvancedSettings = () => {
    if (!config) return null;

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold">Advanced Settings</h3>
            <p className="text-xs theme-text-muted mt-1">
              Developer options and debug settings
            </p>
          </div>
          <Button
            onClick={handleResetCategory}
            variant="ghost"
            size="sm"
            className="text-[10px] font-bold"
          >
            Reset to Defaults
          </Button>
        </div>

        {/* Backpressure Section */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <div className="flex items-center justify-between mb-4">
            <div>
              <label className="block text-sm font-bold theme-text-secondary">
                Enable Backpressure
              </label>
              <p className="text-[11px] theme-text-muted mt-1">
                Run lint/test/build commands between agent iterations
              </p>
            </div>
            <Switch
              checked={config.backpressure.enabled}
              onCheckedChange={(checked) =>
                handleBackpressureChange("enabled", checked)
              }
            />
          </div>

          {config.backpressure.enabled && (
            <div className="space-y-4 pt-4 border-t border-[var(--border-default)]">
              {/* Max Retries */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Max Retries
                </label>
                <Input
                  type="number"
                  min="0"
                  value={(config.backpressure as any).max_retries || 3}
                  onChange={(e) =>
                    handleBackpressureChange(
                      "max_retries" as any,
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
                  <p className="mt-1 text-[10px] text-[var(--destructive-500)]">
                    {validationErrors.max_retries}
                  </p>
                )}
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Number of retry attempts for failed backpressure commands
                </p>
              </div>

              {/* Commands (read-only display) */}
              {config.backpressure.commands.length > 0 && (
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Validation Commands
                  </label>
                  <div className="theme-bg-base border border-[var(--border-muted)] rounded-lg p-4 space-y-2">
                    {config.backpressure.commands.map((cmd, index) => (
                      <div key={index} className="flex items-center gap-2">
                        <span className="text-[9px] font-mono theme-text-muted w-4">
                          {index + 1}.
                        </span>
                        <code className="text-xs font-mono theme-text-tertiary">
                          {cmd}
                        </code>
                      </div>
                    ))}
                  </div>
                  <p className="mt-1.5 text-[10px] theme-text-muted">
                    Edit felix/config.json directly to modify commands
                  </p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Executor Mode (read-only info) */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <div className="flex justify-between items-center">
            <div>
              <label className="block text-sm font-bold theme-text-secondary">
                Executor Mode
              </label>
              <p className="text-[11px] theme-text-muted mt-1">
                How the agent executor runs (local or remote)
              </p>
            </div>
            <span className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg uppercase">
              {config.executor.mode}
            </span>
          </div>
        </div>

        {/* Config Version */}
        <div className="text-center text-[10px] font-mono theme-text-muted pt-4">
          Config Version: {config.version}
        </div>
      </div>
    );
  };

  // Render Projects settings
  const renderProjectsSettings = () => {
    if (!projectId) {
      return (
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <h3 className="text-lg font-semibold">Project</h3>
          <p className="text-xs theme-text-muted mt-2">
            Select a project to edit its settings.
          </p>
        </div>
      );
    }

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-lg font-semibold">Current Project</h3>
            <p className="text-xs theme-text-muted mt-1">
              Edit settings for the active project only.
            </p>
          </div>
          <Button
            onClick={fetchCurrentProject}
            variant="ghost"
            size="sm"
            className="text-[10px] font-bold"
          >
            Refresh
          </Button>
        </div>

        {currentProjectLoading && (
          <div className="flex flex-col items-center justify-center py-12">
            <PageLoading message="Loading project..." fullPage={false} />
          </div>
        )}

        {currentProjectError && !currentProjectLoading && (
          <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
            <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
              <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
              <div>
                <p className="text-xs">{currentProjectError}</p>
                <Button
                  onClick={fetchCurrentProject}
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

        {!currentProjectLoading && currentProject && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 space-y-5">
            <div>
              <p className="text-[10px] uppercase tracking-[0.2em] theme-text-muted">
                Project ID
              </p>
              <p className="text-xs font-mono theme-text-secondary mt-1">
                {currentProject.id}
              </p>
              <p className="text-[10px] theme-text-muted mt-1">
                Registered{" "}
                {new Date(currentProject.registered_at).toLocaleDateString()}
              </p>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Project Name
                </label>
                <Input
                  type="text"
                  value={configProjectName}
                  onChange={(e) => setConfigProjectName(e.target.value)}
                  placeholder={
                    currentProject.path.split(/[/\\]/).pop() || "Project name"
                  }
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Display name for this project (leave empty to use directory
                  name)
                </p>
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Project Folder
                </label>
                <Input
                  type="text"
                  value={configProjectPath}
                  onChange={(e) => setConfigProjectPath(e.target.value)}
                  placeholder="C:\\path\\to\\your\\project"
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Full path to the project directory (must contain specs/ and
                  felix/ directories)
                </p>
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Git Repository
                </label>
                <Input
                  type="text"
                  value={configProjectGitRepo}
                  onChange={(e) => setConfigProjectGitRepo(e.target.value)}
                  placeholder="https://github.com/username/repo.git"
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Git repository URL (optional). Validated on save.
                </p>
              </div>
              <p className="text-[10px] theme-text-muted">
                Use the Save Changes button above to apply project updates.
              </p>
            </div>
          </div>
        )}
      </div>
    );
  };

  // Render Agents settings
  const renderAgentsSettings = () => {
    if (!projectId) {
      return (
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <h3 className="text-lg font-semibold">Project Agents</h3>
          <p className="text-xs theme-text-muted mt-2">
            Select a project to manage its agents.
          </p>
        </div>
      );
    }

    const resetAgentForm = () => {
      setShowAgentForm(false);
      setEditingAgentId(null);
      setAgentFormName("");
      setAgentFormType("");
      setAgentFormProfileId("");
      setAgentFormError(null);
    };

    const openAddAgentForm = () => {
      resetAgentForm();
      setShowAgentForm(true);
    };

    const openEditAgentForm = (agent: Agent) => {
      setEditingAgentId(agent.id);
      setAgentFormName(agent.name);
      setAgentFormType(agent.type || "");
      setAgentFormProfileId(agent.profile_id || "");
      setAgentFormError(null);
      setShowAgentForm(true);
    };

    const handleAgentFormSave = async () => {
      if (!agentFormName.trim()) {
        setAgentFormError("Agent name is required");
        return;
      }
      if (!agentFormProfileId) {
        setAgentFormError("Agent profile is required");
        return;
      }

      setAgentFormSaving(true);
      setAgentFormError(null);

      try {
        const agentId = editingAgentId ?? crypto.randomUUID();
        await registerAgent(
          agentId,
          agentFormName.trim(),
          agentFormType.trim() || undefined,
          { source: "ui" },
          agentFormProfileId,
        );
        toast.success(
          editingAgentId
            ? "Agent updated successfully"
            : "Agent created successfully",
        );
        resetAgentForm();
        fetchProjectAgents();
      } catch (err) {
        console.error("Failed to save agent:", err);
        setAgentFormError(
          err instanceof Error ? err.message : "Failed to save agent",
        );
      } finally {
        setAgentFormSaving(false);
      }
    };

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold">Project Agents</h3>
            <p className="text-xs theme-text-muted mt-1">
              Manage agents for the active project.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              onClick={fetchProjectAgents}
              disabled={projectAgentsLoading}
              variant="secondary"
              size="sm"
              className="text-xs font-bold"
            >
              <RefreshCw
                className={`w-4 h-4 ${projectAgentsLoading ? "animate-spin" : ""}`}
              />
              {projectAgentsLoading ? "Refreshing..." : "Refresh"}
            </Button>
            <Button onClick={openAddAgentForm} size="sm" className="uppercase">
              <Plus className="w-4 h-4" />
              Add Agent
            </Button>
          </div>
        </div>

        {showAgentForm && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-bold theme-text-secondary">
                {editingAgentId ? "Edit Agent" : "Add Agent"}
              </h4>
              <Button
                onClick={resetAgentForm}
                variant="ghost"
                size="icon"
                className="h-8 w-8"
              >
                <X className="w-4 h-4" />
              </Button>
            </div>

            {agentFormError && (
              <Alert className="mb-4 border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                <AlertDescription className="text-[var(--destructive-500)]">
                  {agentFormError}
                </AlertDescription>
              </Alert>
            )}

            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Agent Name *
                </label>
                <Input
                  type="text"
                  placeholder="my-agent"
                  value={agentFormName}
                  onChange={(e) => setAgentFormName(e.target.value)}
                />
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Agent Profile *
                </label>
                <Select
                  value={agentFormProfileId}
                  onValueChange={(value) => setAgentFormProfileId(value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select an agent profile" />
                  </SelectTrigger>
                  <SelectContent>
                    {agentProfiles.map((profile, idx) => (
                      <SelectItem
                        key={profile.id || `profile-${idx}`}
                        value={profile.id}
                      >
                        {profile.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {agentProfilesError && (
                  <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                    {agentProfilesError}
                  </p>
                )}
                {agentProfilesLoading && (
                  <p className="mt-1.5 text-[10px] theme-text-muted">
                    Loading profiles...
                  </p>
                )}
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Agent Type (optional)
                </label>
                <Input
                  type="text"
                  placeholder="ralph"
                  value={agentFormType}
                  onChange={(e) => setAgentFormType(e.target.value)}
                />
              </div>
              <div className="flex justify-end gap-3 pt-2">
                <Button
                  onClick={resetAgentForm}
                  variant="ghost"
                  size="sm"
                  className="uppercase"
                >
                  Cancel
                </Button>
                <Button
                  onClick={handleAgentFormSave}
                  disabled={
                    agentFormSaving ||
                    !agentFormName.trim() ||
                    !agentFormProfileId
                  }
                  size="sm"
                  className="uppercase"
                >
                  {agentFormSaving ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Saving...
                    </>
                  ) : editingAgentId ? (
                    "Update Agent"
                  ) : (
                    "Create Agent"
                  )}
                </Button>
              </div>
            </div>
          </div>
        )}

        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <h4 className="text-sm font-bold theme-text-secondary mb-4">
            Agents
          </h4>

          {projectAgentsError && (
            <Alert className="mb-4 border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
                <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
                <div>
                  <p className="text-xs">{projectAgentsError}</p>
                  <Button
                    onClick={fetchProjectAgents}
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

          {projectAgentsLoading && projectAgents.length === 0 && (
            <div className="flex flex-col items-center justify-center py-8">
              <PageLoading
                message="Loading agents..."
                size="md"
                fullPage={false}
              />
            </div>
          )}

          {!projectAgentsLoading &&
            !projectAgentsError &&
            projectAgents.length === 0 && (
              <div className="text-center py-6">
                <p className="text-xs theme-text-muted">
                  No agents registered for this project yet.
                </p>
              </div>
            )}

          {projectAgents.length > 0 && (
            <div className="space-y-3">
              {projectAgents.map((agent) => (
                <div
                  key={agent.id}
                  className="theme-bg-base border border-[var(--border-muted)] rounded-lg p-4"
                >
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <h5 className="text-sm font-bold theme-text-secondary">
                        {agent.name}
                      </h5>
                      <div className="text-[11px] theme-text-muted mt-1">
                        <span className="font-mono">
                          {agent.profile_name || "No profile"}
                        </span>
                        {agent.heartbeat_at && (
                          <span className="ml-2">
                            Last seen {getRelativeTime(agent.heartbeat_at)}
                          </span>
                        )}
                      </div>
                    </div>
                    <Button
                      onClick={() => openEditAgentForm(agent)}
                      variant="secondary"
                      size="sm"
                      className="text-[10px] font-bold"
                    >
                      Edit
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <h4 className="text-sm font-bold theme-text-secondary mb-4">
            Running Agents
          </h4>

          {projectAgentsLoading && projectAgents.length === 0 && (
            <div className="flex flex-col items-center justify-center py-8">
              <PageLoading
                message="Loading running agents..."
                size="md"
                fullPage={false}
              />
            </div>
          )}

          {!projectAgentsLoading &&
            projectAgents.filter((agent) => agent.status === "running")
              .length === 0 && (
              <div className="text-center py-6">
                <p className="text-xs theme-text-muted">
                  No agents are currently running. Start an agent to see it
                  here.
                </p>
              </div>
            )}

          {projectAgents.filter((agent) => agent.status === "running").length >
            0 && (
            <div className="space-y-3">
              {projectAgents
                .filter((agent) => agent.status === "running")
                .map((agent) => (
                  <div
                    key={agent.id}
                    className="theme-bg-base border border-[var(--border-muted)] rounded-lg p-4"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <h5 className="text-sm font-bold theme-text-secondary">
                          {agent.name}
                        </h5>
                        <div className="text-[11px] theme-text-muted mt-1">
                          <span className="font-mono">
                            {agent.profile_name || "No profile"}
                          </span>
                          {agent.heartbeat_at && (
                            <span className="ml-2">
                              Last seen {getRelativeTime(agent.heartbeat_at)}
                            </span>
                          )}
                        </div>
                      </div>
                      <span className="text-[10px] font-bold uppercase text-[var(--accent-primary)]">
                        Running
                      </span>
                    </div>
                  </div>
                ))}
            </div>
          )}
        </div>

        <div className="bg-[var(--status-info)]/5 border border-[var(--status-info)]/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <Info className="w-4 h-4 text-[var(--status-info)] mt-0.5 flex-shrink-0" />
            <div className="text-xs text-[var(--status-info)]/80">
              <p>
                <strong>Project Agents</strong> are registered instances tied to
                the current project.
              </p>
              <p className="mt-1">
                <strong>Agent Profiles</strong> define defaults and are required
                when creating agents.
              </p>
              <p className="mt-1">
                <strong>Running Agents</strong> are pulled from the project
                agent list.
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  };

  // Model options by provider// Model options by provider
  const modelOptions: Record<string, { value: string; label: string }[]> = {
    openai: [
      { value: "gpt-4o", label: "GPT-4o" },
      { value: "gpt-4-turbo", label: "GPT-4 Turbo" },
      { value: "gpt-3.5-turbo", label: "GPT-3.5 Turbo" },
    ],
    anthropic: [
      { value: "claude-3-5-sonnet-20241022", label: "Claude 3.5 Sonnet" },
      { value: "claude-3-opus-20240229", label: "Claude 3 Opus" },
      { value: "claude-3-haiku-20240307", label: "Claude 3 Haiku" },
    ],
  };

  // Render the active category's settings
  const renderActiveSettings = () => {
    switch (activeCategory) {
      case "general":
        return renderGeneralSettings();
      case "paths":
        return renderPathsSettings();
      case "advanced":
        return renderAdvancedSettings();
      case "projects":
        return renderProjectsSettings();
      case "agents":
        return renderAgentsSettings();
      case "api-keys":
        return renderApiKeysSettings();
      case "docs":
        return renderDocsSettings();
      default:
        return null;
    }
  };

  const availableCategories = projectId
    ? CATEGORIES
    : CATEGORIES.filter(
        (category) => category.id !== "docs" && category.id !== "api-keys",
      );

  useEffect(() => {
    if (
      !availableCategories.some((category) => category.id === activeCategory)
    ) {
      setActiveCategory("general");
    }
  }, [activeCategory, availableCategories]);

  const DOC_OPTIONS: Array<{
    id: DocFileName;
    label: string;
    description: string;
  }> = [
    {
      id: "README.md",
      label: "README.md",
      description: "Project overview and onboarding details.",
    },
    {
      id: "CONTEXT.md",
      label: "CONTEXT.md",
      description: "Core background and context for Felix.",
    },
    {
      id: "AGENTS.md",
      label: "AGENTS.md",
      description: "Agent instructions and execution guidance.",
    },
  ];

  // Load API keys when projectId changes
  useEffect(() => {
    if (!projectId || activeCategory !== "api-keys") {
      return;
    }

    const loadApiKeys = async () => {
      setApiKeysLoading(true);
      setApiKeysError(null);
      try {
        const response = await felixApi.listApiKeys(projectId);
        setApiKeys(response.keys);
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : "Failed to load API keys";
        setApiKeysError(errorMessage);
        toast.error(errorMessage);
      } finally {
        setApiKeysLoading(false);
      }
    };

    loadApiKeys();
  }, [projectId, activeCategory]);

  const handleCreateApiKey = async () => {
    if (!projectId) return;

    setApiKeyFormSaving(true);
    try {
      const newKey = await felixApi.createApiKey(projectId, {
        name: apiKeyFormName || undefined,
        expires_days: apiKeyFormExpiresDays,
      });
      setCreatedApiKey(newKey);
      setApiKeys([...apiKeys, newKey]);
      setShowApiKeyForm(false);
      setApiKeyFormName("");
      setApiKeyFormExpiresDays(undefined);
      toast.success("API key created successfully");
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : "Failed to create API key";
      toast.error(errorMessage);
    } finally {
      setApiKeyFormSaving(false);
    }
  };

  const handleRevokeApiKey = async (keyId: string) => {
    if (!projectId) return;
    if (
      !confirm(
        "Are you sure you want to revoke this API key? This action cannot be undone.",
      )
    ) {
      return;
    }

    try {
      await felixApi.revokeApiKey(projectId, keyId);
      setApiKeys(apiKeys.filter((key) => key.id !== keyId));
      toast.success("API key revoked successfully");
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : "Failed to revoke API key";
      toast.error(errorMessage);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    toast.success("Copied to clipboard");
  };

  const formatDate = (dateString: string | null) => {
    if (!dateString) return "Never";
    return new Date(dateString).toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  const renderApiKeysSettings = () => {
    if (!projectId) {
      return (
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <h3 className="text-lg font-semibold">API Keys</h3>
          <p className="text-xs theme-text-muted mt-2">
            Select a project to manage API keys for CLI sync.
          </p>
        </div>
      );
    }

    return (
      <div className="space-y-6">
        {/* Header */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <div className="flex items-start justify-between mb-4">
            <div>
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <IconKey className="w-5 h-5" />
                API Keys
              </h3>
              <p className="text-xs theme-text-muted mt-1">
                Generate project-scoped API keys for CLI agent sync. Each key is
                scoped to this project only.
              </p>
            </div>
            <Button
              onClick={() => setShowApiKeyForm(true)}
              size="sm"
              disabled={showApiKeyForm}
            >
              <Plus className="w-4 h-4 mr-1" />
              New Key
            </Button>
          </div>

          {/* New Key Form */}
          {showApiKeyForm && (
            <div className="mt-4 p-4 border border-[var(--border-default)] rounded-lg space-y-4">
              <div>
                <label className="block text-sm font-medium mb-2">
                  Key Name (Optional)
                </label>
                <Input
                  value={apiKeyFormName}
                  onChange={(e) => setApiKeyFormName(e.target.value)}
                  placeholder="e.g., Dev Laptop, CI/CD Pipeline"
                  className="w-full"
                />
                <p className="text-xs theme-text-muted mt-1">
                  A descriptive name to help you identify this key
                </p>
              </div>

              <div>
                <label className="block text-sm font-medium mb-2">
                  Expires In (Optional)
                </label>
                <Select
                  value={apiKeyFormExpiresDays?.toString() || "never"}
                  onValueChange={(value) =>
                    setApiKeyFormExpiresDays(
                      value === "never" ? undefined : parseInt(value),
                    )
                  }
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Never expires" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="never">Never expires</SelectItem>
                    <SelectItem value="7">7 days</SelectItem>
                    <SelectItem value="30">30 days</SelectItem>
                    <SelectItem value="90">90 days</SelectItem>
                    <SelectItem value="365">1 year</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="flex gap-2">
                <Button
                  onClick={handleCreateApiKey}
                  disabled={apiKeyFormSaving}
                  size="sm"
                >
                  {apiKeyFormSaving ? "Generating..." : "Generate Key"}
                </Button>
                <Button
                  onClick={() => {
                    setShowApiKeyForm(false);
                    setApiKeyFormName("");
                    setApiKeyFormExpiresDays(undefined);
                  }}
                  variant="ghost"
                  size="sm"
                  disabled={apiKeyFormSaving}
                >
                  Cancel
                </Button>
              </div>
            </div>
          )}

          {/* Created Key Display (one-time) */}
          {createdApiKey && (
            <Alert className="mt-4 border-green-500/50 bg-green-500/10">
              <Check className="w-4 h-4 text-green-500" />
              <AlertDescription>
                <p className="text-sm font-semibold mb-2">
                  API Key Generated Successfully
                </p>
                <p className="text-xs theme-text-muted mb-3">
                  Copy this key now - it will not be shown again!
                </p>
                <div className="flex items-center gap-2 p-2 bg-black/20 rounded font-mono text-sm break-all">
                  <code className="flex-1">{createdApiKey.key}</code>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => copyToClipboard(createdApiKey.key)}
                    className="shrink-0"
                  >
                    Copy
                  </Button>
                </div>
                <p className="text-xs theme-text-muted mt-3">
                  Set this in your environment or config:
                  <br />
                  <code className="text-xs">
                    $env:FELIX_SYNC_KEY = "{createdApiKey.key}"
                  </code>
                </p>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => setCreatedApiKey(null)}
                  className="mt-3"
                >
                  Dismiss
                </Button>
              </AlertDescription>
            </Alert>
          )}
        </div>

        {/* Keys List */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <h4 className="text-md font-semibold mb-4">Active Keys</h4>

          {apiKeysLoading && (
            <div className="flex items-center justify-center py-8">
              <div className="w-6 h-6 border-2 border-[var(--border-default)] border-t-[var(--fg-default)] rounded-full animate-spin" />
            </div>
          )}

          {apiKeysError && (
            <Alert className="border-red-500/50 bg-red-500/10">
              <AlertTriangle className="w-4 h-4 text-red-500" />
              <AlertDescription>{apiKeysError}</AlertDescription>
            </Alert>
          )}

          {!apiKeysLoading && !apiKeysError && apiKeys.length === 0 && (
            <p className="text-sm theme-text-muted text-center py-8">
              No API keys yet. Generate one to enable CLI sync for this project.
            </p>
          )}

          {!apiKeysLoading && !apiKeysError && apiKeys.length > 0 && (
            <div className="space-y-3">
              {apiKeys.map((key) => (
                <div
                  key={key.id}
                  className="p-4 border border-[var(--border-default)] rounded-lg"
                >
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <p className="font-medium">
                          {key.name || "Unnamed Key"}
                        </p>
                        {key.expires_at &&
                          new Date(key.expires_at) < new Date() && (
                            <span className="text-xs px-2 py-0.5 bg-red-500/20 text-red-500 rounded">
                              Expired
                            </span>
                          )}
                      </div>
                      <div className="text-xs theme-text-muted mt-1 space-y-1">
                        <p>Created: {formatDate(key.created_at)}</p>
                        {key.last_used_at && (
                          <p>Last used: {formatDate(key.last_used_at)}</p>
                        )}
                        {key.expires_at && (
                          <p>Expires: {formatDate(key.expires_at)}</p>
                        )}
                      </div>
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => handleRevokeApiKey(key.id)}
                      className="text-red-500 hover:text-red-600 hover:bg-red-500/10"
                    >
                      <X className="w-4 h-4 mr-1" />
                      Revoke
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Help Section */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <h4 className="text-md font-semibold mb-3 flex items-center gap-2">
            <Info className="w-4 h-4" />
            Using API Keys
          </h4>
          <div className="space-y-3 text-sm theme-text-muted">
            <p>
              API keys allow your CLI agent to sync run artifacts to this
              server. Each key is scoped to this project only.
            </p>
            <div>
              <p className="font-medium theme-text-default mb-1">
                Setup Instructions:
              </p>
              <ol className="list-decimal list-inside space-y-1 ml-2">
                <li>Generate a new API key above</li>
                <li>Copy the key (shown only once)</li>
                <li>
                  Set in environment:{" "}
                  <code className="text-xs px-1 py-0.5 bg-black/20 rounded">
                    $env:FELIX_SYNC_KEY = "fsk_..."
                  </code>
                </li>
                <li>
                  Or add to{" "}
                  <code className="text-xs px-1 py-0.5 bg-black/20 rounded">
                    .felix/config.json
                  </code>{" "}
                  under{" "}
                  <code className="text-xs px-1 py-0.5 bg-black/20 rounded">
                    sync.api_key
                  </code>
                </li>
                <li>Enable sync in config or use --sync flag</li>
              </ol>
            </div>
            <p className="text-xs">
              Sync is optional. CLI agents work perfectly without it for
              local-only development.
            </p>
          </div>
        </div>
      </div>
    );
  };

  const renderDocsSettings = () => {
    if (!projectId) {
      return (
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
          <h3 className="text-lg font-semibold">Docs</h3>
          <p className="text-xs theme-text-muted mt-2">
            Select a project to edit README.md, CONTEXT.md, or AGENTS.md.
          </p>
        </div>
      );
    }

    const hasDocChanges = docContents[activeDoc] !== docOriginals[activeDoc];

    const handleDocSave = async () => {
      if (!hasDocChanges) return;
      setDocsSaving(true);
      setDocsError(null);
      setDocsSaveMessage(null);
      try {
        await felixApi.updateProjectFile(
          projectId,
          activeDoc,
          docContents[activeDoc],
        );
        setDocOriginals((prev) => ({
          ...prev,
          [activeDoc]: docContents[activeDoc],
        }));
        setDocsSaveMessage({
          type: "success",
          text: `${activeDoc} saved`,
        });
      } catch (err) {
        console.error("Failed to save project file:", err);
        setDocsSaveMessage({
          type: "error",
          text: err instanceof Error ? err.message : "Failed to save file",
        });
      } finally {
        setDocsSaving(false);
      }
    };

    const handleDocDiscard = () => {
      setDocContents((prev) => ({
        ...prev,
        [activeDoc]: docOriginals[activeDoc],
      }));
    };

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between gap-4">
          <div>
            <h3 className="text-lg font-semibold">Documentation Files</h3>
            <p className="text-xs theme-text-muted mt-1">
              Edit project-level README, CONTEXT, and AGENTS files.
            </p>
          </div>
          <Button
            onClick={() => fetchDoc(activeDoc)}
            variant="ghost"
            size="sm"
            className="text-[10px] font-bold"
          >
            Refresh
          </Button>
        </div>

        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <Tabs
            value={activeDoc}
            onValueChange={(value) => setActiveDoc(value as DocFileName)}
          >
            <TabsList className="flex flex-wrap justify-start gap-2">
              {DOC_OPTIONS.map((doc) => (
                <TabsTrigger key={doc.id} value={doc.id}>
                  {doc.label}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <p className="mt-3 text-[11px] theme-text-muted">
            {DOC_OPTIONS.find((doc) => doc.id === activeDoc)?.description}
          </p>
        </div>

        {docsError && (
          <Alert className="border-[var(--status-warning)]/30 bg-[var(--status-warning)]/10 text-[var(--status-warning)]">
            <AlertDescription className="flex items-start gap-3 text-[var(--status-warning)]">
              <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
              <div>
                <p className="text-xs">{docsError}</p>
                <p className="text-[10px] mt-1 opacity-80">
                  You can still save to create the file.
                </p>
              </div>
            </AlertDescription>
          </Alert>
        )}

        {docsLoading ? (
          <PageLoading
            message={`Loading ${activeDoc}...`}
            size="sm"
            fullPage={false}
          />
        ) : (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl overflow-hidden h-[620px]">
            <MarkdownEditor
              content={docContents[activeDoc]}
              onContentChange={(content) =>
                setDocContents((prev) => ({ ...prev, [activeDoc]: content }))
              }
              viewModes={["edit", "split", "preview"]}
              initialViewMode="preview"
              onSave={handleDocSave}
              onDiscard={handleDocDiscard}
              hasChanges={hasDocChanges}
              saving={docsSaving}
              saveMessage={docsSaveMessage}
              fileName={activeDoc}
              showFormatting={true}
              showCopy={true}
              showSave={true}
              placeholder={`# ${activeDoc}\n`}
              className="h-full"
            />
          </div>
        )}
      </div>
    );
  };

  // Loading state
  if (loading) {
    return (
      <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
        <div className="flex-1">
          <PageLoading message="Loading settings..." />
        </div>
      </div>
    );
  }

  // Error state (no config)
  if (error && !config) {
    return (
      <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <div className="w-16 h-16 theme-bg-surface rounded-2xl flex items-center justify-center mb-4">
            <AlertTriangle className="w-8 h-8 text-[var(--status-error)]" />
          </div>
          <h3 className="text-sm font-bold theme-text-tertiary mb-2">
            Failed to Load Settings
          </h3>
          <p className="text-xs theme-text-muted max-w-md mb-4">{error}</p>
          <Button
            onClick={onBack}
            variant="secondary"
            size="sm"
            className="text-[var(--accent-primary)] border-[var(--accent-primary)]/20 hover:bg-[var(--accent-primary)]/10"
          >
            Back to Projects
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
      {/* Header and Tabs */}
      <div className="bg-[var(--bg-base)] px-6 pt-8 pb-2">
        <div className="max-w-3xl mx-auto">
          <div className="flex items-start justify-between gap-6">
            <div>
              <h1 className="text-2xl font-semibold theme-text-primary">
                {projectId ? "Project Settings" : "Organization Settings"}
              </h1>
              {hasChanges && (
                <div className="mt-2 flex items-center gap-2 text-[11px] text-[var(--status-warning)]">
                  <div className="w-1.5 h-1.5 rounded-full bg-[var(--status-warning)] animate-pulse" />
                  <span className="font-mono uppercase">Unsaved changes</span>
                </div>
              )}
              {saveMessage && (
                <div className="mt-3">
                  <Alert
                    className={
                      saveMessage.type === "error"
                        ? "border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]"
                        : "border-[var(--status-success)]/30 bg-[var(--status-success)]/10 text-[var(--status-success)]"
                    }
                  >
                    <AlertDescription className="text-xs">
                      {saveMessage.text}
                    </AlertDescription>
                  </Alert>
                </div>
              )}
            </div>
            <div className="flex items-center gap-3">
              {hasChanges && (
                <Button
                  onClick={handleReset}
                  variant="ghost"
                  size="sm"
                  className="text-[10px] font-bold"
                >
                  Discard
                </Button>
              )}
              <Button
                onClick={handleSave}
                disabled={
                  saving ||
                  !hasChanges ||
                  (hasConfigChanges && Object.keys(validationErrors).length > 0)
                }
                size="sm"
                className="text-[10px] font-bold uppercase"
              >
                {saving ? (
                  <>
                    <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Saving...
                  </>
                ) : (
                  "Save Changes"
                )}
              </Button>
            </div>
          </div>
          <div className="mt-6 border-b border-[var(--border-default)]">
            <Tabs
              value={activeCategory}
              onValueChange={(value) =>
                setActiveCategory(value as SettingsCategory)
              }
            >
              <TabsList
                variant="line"
                className="w-full justify-start flex-wrap gap-6"
              >
                {availableCategories.map((category) => (
                  <TabsTrigger
                    key={category.id}
                    value={category.id}
                    variant="line"
                    className="text-sm font-medium"
                  >
                    {category.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </div>
        </div>
      </div>

      {/* Settings Content */}
      <div className="flex-1 overflow-y-auto custom-scrollbar p-8 theme-bg-base">
        <div className="max-w-3xl mx-auto">{renderActiveSettings()}</div>
      </div>
    </div>
  );
};

export default SettingsScreen;

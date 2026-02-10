import React, { useState, useEffect, useCallback } from "react";
import {
  felixApi,
  FelixConfig,
  Project,
  AgentEntry,
  AgentRegistryResponse,
  AgentConfiguration,
  AgentConfigurationsResponse,
  getCopilotApiKey,
  setCopilotApiKey,
  clearCopilotApiKey,
} from "../services/felixApi";
import { IconFelix } from "./Icons";
import { Alert, AlertDescription } from "./ui/alert";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { Switch } from "./ui/switch";
import { useTheme, ThemeValue } from "../hooks/ThemeProvider";

interface SettingsScreenProps {
  projectId?: string; // Optional - when undefined, uses global settings API
  onBack: () => void;
}

type SettingsCategory =
  | "general"
  | "paths"
  | "copilot"
  | "advanced"
  | "projects"
  | "agents";

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
    icon: (
      <svg
        className="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
        />
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
        />
      </svg>
    ),
  },
  {
    id: "paths",
    label: "Paths",
    description: "File and directory locations",
    icon: (
      <svg
        className="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"
        />
      </svg>
    ),
  },
  {
    id: "copilot",
    label: "Felix Copilot",
    description: "AI-powered spec writing assistant",
    icon: <span className="text-lg">✨</span>,
  },
  {
    id: "advanced",
    label: "Advanced",
    description: "Developer and debug options",
    icon: (
      <svg
        className="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
        />
      </svg>
    ),
  },
  {
    id: "projects",
    label: "Projects",
    description: "Manage registered projects",
    icon: (
      <svg
        className="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
        />
      </svg>
    ),
  },
  {
    id: "agents",
    label: "Agents",
    description: "Agent registry and status",
    icon: (
      <svg
        className="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
        />
      </svg>
    ),
  },
];

const SettingsScreen: React.FC<SettingsScreenProps> = ({
  projectId,
  onBack,
}) => {
  const { theme, setTheme } = useTheme();
  const [activeCategory, setActiveCategory] =
    useState<SettingsCategory>("general");
  const [config, setConfig] = useState<FelixConfig | null>(null);
  const [originalConfig, setOriginalConfig] = useState<FelixConfig | null>(
    null,
  );
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<
    Record<string, string>
  >({});

  // Projects state
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectsLoading, setProjectsLoading] = useState(false);
  const [projectsError, setProjectsError] = useState<string | null>(null);
  const [projectSearchQuery, setProjectSearchQuery] = useState("");
  const [registerPath, setRegisterPath] = useState("");
  const [registerName, setRegisterName] = useState("");
  const [isRegistering, setIsRegistering] = useState(false);
  const [showRegisterForm, setShowRegisterForm] = useState(false);
  const [unregisteringId, setUnregisteringId] = useState<string | null>(null);
  const [showUnregisterConfirm, setShowUnregisterConfirm] = useState<
    string | null
  >(null);
  const [configuringProjectId, setConfiguringProjectId] = useState<
    string | null
  >(null);
  const [configProjectName, setConfigProjectName] = useState("");
  const [configProjectPath, setConfigProjectPath] = useState("");
  const [isSavingConfig, setIsSavingConfig] = useState(false);

  // Agents state (orchestration - running agents)
  const [registeredAgents, setRegisteredAgents] = useState<
    Record<string, AgentEntry>
  >({});
  const [agentsLoading, setAgentsLoading] = useState(false);
  const [agentsError, setAgentsError] = useState<string | null>(null);
  const [agentNameInput, setAgentNameInput] = useState<string>("");
  const [agentNameValidationError, setAgentNameValidationError] = useState<
    string | null
  >(null);

  // Agent configurations state (from agents.json)
  const [agentConfigurations, setAgentConfigurations] = useState<
    AgentConfiguration[]
  >([]);
  const [activeAgentId, setActiveAgentId] = useState<number>(0);
  const [agentConfigsLoading, setAgentConfigsLoading] = useState(false);
  const [agentConfigsError, setAgentConfigsError] = useState<string | null>(
    null,
  );
  const [settingActiveAgent, setSettingActiveAgent] = useState<number | null>(
    null,
  );
  const [deletingAgentId, setDeletingAgentId] = useState<number | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState<number | null>(
    null,
  );

  // Agent form state (for add/edit)
  const [showAgentForm, setShowAgentForm] = useState(false);
  const [editingAgentId, setEditingAgentId] = useState<number | null>(null);
  const [agentFormName, setAgentFormName] = useState("");
  const [agentFormExecutable, setAgentFormExecutable] = useState("");
  const [agentFormArgs, setAgentFormArgs] = useState("");
  const [agentFormWorkingDir, setAgentFormWorkingDir] = useState(".");
  const [agentFormSaving, setAgentFormSaving] = useState(false);
  const [agentFormError, setAgentFormError] = useState<string | null>(null);

  // Fetch config on mount and sync theme
  // Uses global settings API when no projectId is provided
  useEffect(() => {
    const fetchConfig = async () => {
      setLoading(true);
      setError(null);

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
  }, [projectId, setTheme]);

  // Fetch projects when Projects category is selected
  const fetchProjects = useCallback(async () => {
    setProjectsLoading(true);
    setProjectsError(null);
    try {
      const projectsList = await felixApi.listProjects();
      setProjects(projectsList);
    } catch (err) {
      console.error("Failed to fetch projects:", err);
      setProjectsError(
        err instanceof Error ? err.message : "Failed to load projects",
      );
    } finally {
      setProjectsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeCategory === "projects") {
      fetchProjects();
    }
  }, [activeCategory, fetchProjects]);

  // Fetch agents when Agents category is selected
  const fetchAgents = useCallback(async () => {
    setAgentsLoading(true);
    setAgentsError(null);
    try {
      const response = await felixApi.getAgents();
      setRegisteredAgents(response.agents);
    } catch (err) {
      console.error("Failed to fetch agents:", err);
      setAgentsError(
        err instanceof Error ? err.message : "Failed to load agents",
      );
    } finally {
      setAgentsLoading(false);
    }
  }, []);

  // Fetch agent configurations from agents.json
  const fetchAgentConfigurations = useCallback(async () => {
    setAgentConfigsLoading(true);
    setAgentConfigsError(null);
    try {
      const response = await felixApi.getAgentConfigurations();
      setAgentConfigurations(response.agents);
      setActiveAgentId(response.active_agent_id);
    } catch (err) {
      console.error("Failed to fetch agent configurations:", err);
      setAgentConfigsError(
        err instanceof Error
          ? err.message
          : "Failed to load agent configurations",
      );
    } finally {
      setAgentConfigsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeCategory === "agents") {
      fetchAgents();
      fetchAgentConfigurations();
      // Also initialize agent name input from config
      if (config?.agent?.name) {
        setAgentNameInput(config.agent.name);
      }
    }
  }, [
    activeCategory,
    fetchAgents,
    fetchAgentConfigurations,
    config?.agent?.name,
  ]);

  // Clear success message after 3 seconds
  useEffect(() => {
    if (successMessage) {
      const timeout = setTimeout(() => setSuccessMessage(null), 3000);
      return () => clearTimeout(timeout);
    }
  }, [successMessage]);

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
    setAgentNameInput(value);
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
  const handleSave = async () => {
    if (!config) return;

    const errors = validateConfig(config);
    if (Object.keys(errors).length > 0) {
      setValidationErrors(errors);
      return;
    }

    setSaving(true);
    setError(null);
    setSuccessMessage(null);

    try {
      // Use global settings API when no projectId, otherwise use project-specific API
      const result = projectId
        ? await felixApi.updateConfig(projectId, config)
        : await felixApi.updateGlobalConfig(config);
      setConfig(result.config);
      setOriginalConfig(result.config);
      setSuccessMessage("Configuration saved successfully");
    } catch (err) {
      console.error("Failed to save config:", err);
      setError(
        err instanceof Error ? err.message : "Failed to save configuration",
      );
    } finally {
      setSaving(false);
    }
  };

  // Check if config has changes
  const hasChanges =
    config &&
    originalConfig &&
    JSON.stringify(config) !== JSON.stringify(originalConfig);

  // Reset to original config
  const handleReset = () => {
    if (originalConfig) {
      setConfig(originalConfig);
      setValidationErrors({});
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

        {/* Appearance Section - Theme (Local Only, not saved to backend config) */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 mb-6">
          <div className="flex items-center gap-2 mb-3">
            <span className="text-lg">🎨</span>
            <div>
              <label className="block text-sm font-bold theme-text-secondary">
                Appearance
              </label>
              <p className="text-[10px] theme-text-muted">
                This setting is saved locally and not synced across devices
              </p>
            </div>
          </div>
          <Select
            value={theme}
            onValueChange={(value) => setTheme(value as ThemeValue)}
          >
            <SelectTrigger className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="dark">Dark</SelectItem>
              <SelectItem value="light">Light</SelectItem>
              <SelectItem value="system">System (Auto)</SelectItem>
            </SelectContent>
          </Select>
          <p className="mt-2 text-[11px] theme-text-muted">
            Choose your preferred color theme. "System" automatically follows
            your operating system preference.
          </p>
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
            <svg
              className="w-4 h-4 mt-0.5 flex-shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
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
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold">Projects</h3>
            <p className="text-xs theme-text-muted mt-1">
              Manage registered Felix projects
            </p>
          </div>
          <Button
            onClick={() => setShowRegisterForm(true)}
            size="sm"
            className="uppercase"
          >
            <svg
              className="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M12 4v16m8-8H4"
              />
            </svg>
            Register New Project
          </Button>
        </div>

        {/* Search/Filter */}
        <div className="relative">
          <Input
            type="text"
            placeholder="Search projects by name or path..."
            value={projectSearchQuery}
            onChange={(e) => setProjectSearchQuery(e.target.value)}
            className="h-11 pl-10"
          />
          <svg
            className="w-4 h-4 theme-text-muted absolute left-4 top-1/2 -translate-y-1/2"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>

        {/* Register Form Modal */}
        {showRegisterForm && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-bold theme-text-secondary">
                Register New Project
              </h4>
              <Button
                onClick={() => {
                  setShowRegisterForm(false);
                  setRegisterPath("");
                  setRegisterName("");
                }}
                variant="ghost"
                size="icon"
                className="h-8 w-8"
              >
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </Button>
            </div>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Project Path *
                </label>
                <Input
                  type="text"
                  placeholder="C:\path\to\your\project"
                  value={registerPath}
                  onChange={(e) => setRegisterPath(e.target.value)}
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Full path to the project directory (must contain specs/ and
                  felix/ directories)
                  <br />
                  Tip: Shift+Right-click folder in Explorer → "Copy as path"
                </p>
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Project Name (optional)
                </label>
                <Input
                  type="text"
                  placeholder="My Project"
                  value={registerName}
                  onChange={(e) => setRegisterName(e.target.value)}
                />
              </div>
              <div className="flex justify-end gap-3 pt-2">
                <Button
                  onClick={() => {
                    setShowRegisterForm(false);
                    setRegisterPath("");
                    setRegisterName("");
                  }}
                  variant="ghost"
                  size="sm"
                  className="uppercase"
                >
                  Cancel
                </Button>
                <Button
                  onClick={async () => {
                    if (!registerPath.trim()) return;
                    setIsRegistering(true);
                    try {
                      await felixApi.registerProject({
                        path: registerPath.trim(),
                        name: registerName.trim() || undefined,
                      });
                      setShowRegisterForm(false);
                      setRegisterPath("");
                      setRegisterName("");
                      setSuccessMessage("Project registered successfully");
                      fetchProjects();
                    } catch (err) {
                      setProjectsError(
                        err instanceof Error
                          ? err.message
                          : "Failed to register project",
                      );
                    } finally {
                      setIsRegistering(false);
                    }
                  }}
                  disabled={!registerPath.trim() || isRegistering}
                  size="sm"
                  className="uppercase"
                >
                  {isRegistering ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Registering...
                    </>
                  ) : (
                    "Register Project"
                  )}
                </Button>
              </div>
            </div>
          </div>
        )}

        {/* Loading State */}
        {projectsLoading && (
          <div className="flex flex-col items-center justify-center py-12">
            <div className="w-8 h-8 border-2 border-[var(--border-default)] border-t-[var(--accent-primary)] rounded-full animate-spin mb-4" />
            <span className="text-xs font-mono theme-text-muted uppercase">
              Loading projects...
            </span>
          </div>
        )}

        {/* Error State */}
        {projectsError && !projectsLoading && (
          <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
            <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
              <svg
                className="w-4 h-4 mt-0.5 flex-shrink-0"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
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

        {/* Empty State */}
        {!projectsLoading && !projectsError && projects.length === 0 && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-8 text-center">
            <div className="w-12 h-12 theme-bg-surface rounded-xl flex items-center justify-center mx-auto mb-4">
              <svg
                className="w-6 h-6 theme-text-muted"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                />
              </svg>
            </div>
            <h4 className="text-sm font-bold theme-text-tertiary mb-2">
              No Projects Registered
            </h4>
            <p className="text-xs theme-text-muted max-w-sm mx-auto">
              Register a Felix project to get started. Projects must have specs/
              and felix/ directories.
            </p>
          </div>
        )}

        {/* Projects List */}
        {!projectsLoading && !projectsError && projects.length > 0 && (
          <div className="space-y-3">
            {projects
              .filter((project) => {
                if (!projectSearchQuery.trim()) return true;
                const query = projectSearchQuery.toLowerCase();
                return (
                  project.name?.toLowerCase().includes(query) ||
                  false ||
                  project.path.toLowerCase().includes(query) ||
                  project.id.toLowerCase().includes(query)
                );
              })
              .sort(
                (a, b) =>
                  new Date(b.registered_at).getTime() -
                  new Date(a.registered_at).getTime(),
              )
              .map((project) => (
                <div
                  key={project.id}
                  className={`theme-bg-elevated border rounded-xl p-5 transition-all ${
                    project.id === projectId
                      ? "border-[var(--accent-primary)]/40 bg-[var(--selected-bg)]"
                      : "border-[var(--border-default)] hover:border-[var(--border-muted)]"
                  }`}
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <h4 className="text-sm font-bold theme-text-secondary truncate">
                          {project.name || project.id}
                        </h4>
                        {project.id === projectId && (
                          <span className="px-2 py-0.5 text-[9px] font-bold bg-[var(--accent-primary)]/20 text-[var(--accent-primary)] rounded-full uppercase">
                            Active
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2">
                        <code className="text-[11px] font-mono theme-text-muted truncate block">
                          {project.path}
                        </code>
                        <Button
                          onClick={() =>
                            navigator.clipboard.writeText(project.path)
                          }
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7"
                          title="Copy path"
                        >
                          <svg
                            className="w-3.5 h-3.5"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth="2"
                              d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                            />
                          </svg>
                        </Button>
                      </div>
                      <p className="text-[10px] theme-text-muted mt-2">
                        Registered{" "}
                        {new Date(project.registered_at).toLocaleDateString()}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <Button
                        onClick={() => {
                          // TODO: Open project action - requires callback from parent
                        }}
                        variant="secondary"
                        size="sm"
                        className="text-[10px] font-bold"
                      >
                        Open
                      </Button>
                      <Button
                        onClick={() => {
                          setConfiguringProjectId(project.id);
                          setConfigProjectName(project.name || "");
                          setConfigProjectPath(project.path);
                        }}
                        variant="secondary"
                        size="sm"
                        className="text-[10px] font-bold"
                      >
                        Configure
                      </Button>
                      {project.id !== projectId && (
                        <Button
                          onClick={() => setShowUnregisterConfirm(project.id)}
                          variant="destructive"
                          size="sm"
                          className="text-[10px] font-bold bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                        >
                          Unregister
                        </Button>
                      )}
                    </div>
                  </div>

                  {/* Configuration Panel */}
                  {configuringProjectId === project.id && (
                    <div className="mt-4 pt-4 border-t border-[var(--border-default)]">
                      <div className="space-y-4">
                        <div>
                          <label className="block text-xs font-bold theme-text-tertiary mb-2">
                            Project Name
                          </label>
                          <Input
                            type="text"
                            value={configProjectName}
                            onChange={(e) =>
                              setConfigProjectName(e.target.value)
                            }
                            placeholder={
                              project.path.split(/[/\\]/).pop() ||
                              "Project name"
                            }
                          />
                          <p className="mt-1.5 text-[10px] theme-text-muted">
                            Display name for this project (leave empty to use
                            directory name)
                          </p>
                        </div>
                        <div>
                          <label className="block text-xs font-bold theme-text-tertiary mb-2">
                            Project Folder
                          </label>
                          <Input
                            type="text"
                            value={configProjectPath}
                            onChange={(e) =>
                              setConfigProjectPath(e.target.value)
                            }
                            placeholder="C:\path\to\your\project"
                            className="font-mono"
                          />
                          <p className="mt-1.5 text-[10px] theme-text-muted">
                            Full path to the project directory (must contain
                            specs/ and felix/ directories)
                          </p>
                        </div>
                        <div className="flex justify-end gap-3">
                          <Button
                            onClick={() => {
                              setConfiguringProjectId(null);
                              setConfigProjectName("");
                              setConfigProjectPath("");
                            }}
                            variant="ghost"
                            size="sm"
                            className="uppercase"
                          >
                            Cancel
                          </Button>
                          <Button
                            onClick={async () => {
                              setIsSavingConfig(true);
                              try {
                                // Only send path if it changed
                                const pathChanged =
                                  configProjectPath.trim() !== project.path;
                                await felixApi.updateProject(project.id, {
                                  name: configProjectName.trim() || undefined,
                                  path: pathChanged
                                    ? configProjectPath.trim()
                                    : undefined,
                                });
                                setSuccessMessage(
                                  "Project configuration saved",
                                );
                                setConfiguringProjectId(null);
                                setConfigProjectName("");
                                setConfigProjectPath("");
                                fetchProjects();
                              } catch (err) {
                                setProjectsError(
                                  err instanceof Error
                                    ? err.message
                                    : "Failed to save project configuration",
                                );
                              } finally {
                                setIsSavingConfig(false);
                              }
                            }}
                            disabled={isSavingConfig}
                            size="sm"
                            className="uppercase"
                          >
                            {isSavingConfig ? (
                              <>
                                <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                Saving...
                              </>
                            ) : (
                              "Save"
                            )}
                          </Button>
                        </div>
                      </div>
                    </div>
                  )}

                  {/* Unregister Confirmation */}
                  {showUnregisterConfirm === project.id && (
                    <div className="mt-4 pt-4 border-t border-[var(--border-default)]">
                      <div className="flex items-center justify-between">
                        <p className="text-xs text-[var(--status-warning)]">
                          Remove this project from Felix? Files will remain on
                          disk.
                        </p>
                        <div className="flex items-center gap-2">
                          <Button
                            onClick={() => setShowUnregisterConfirm(null)}
                            variant="ghost"
                            size="sm"
                            className="text-[10px] font-bold"
                          >
                            Cancel
                          </Button>
                          <Button
                            onClick={async () => {
                              setUnregisteringId(project.id);
                              try {
                                await felixApi.unregisterProject(project.id);
                                setSuccessMessage(
                                  "Project unregistered successfully",
                                );
                                setShowUnregisterConfirm(null);
                                fetchProjects();
                              } catch (err) {
                                setProjectsError(
                                  err instanceof Error
                                    ? err.message
                                    : "Failed to unregister project",
                                );
                              } finally {
                                setUnregisteringId(null);
                              }
                            }}
                            disabled={unregisteringId === project.id}
                            variant="destructive"
                            size="sm"
                            className="text-[10px] font-bold bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                          >
                            {unregisteringId === project.id ? (
                              <>
                                <div className="w-3 h-3 border-2 border-[var(--status-error)]/30 border-t-[var(--status-error)] rounded-full animate-spin" />
                                Removing...
                              </>
                            ) : (
                              "Confirm Unregister"
                            )}
                          </Button>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              ))}
          </div>
        )}
      </div>
    );
  };

  // Render Agents settings
  const renderAgentsSettings = () => {
    if (!config) return null;

    // Handle setting active agent
    const handleSetActiveAgent = async (agentId: number) => {
      setSettingActiveAgent(agentId);
      try {
        await felixApi.setActiveAgent(agentId);
        setActiveAgentId(agentId);
        setSuccessMessage(`Agent set as active successfully`);
      } catch (err) {
        console.error("Failed to set active agent:", err);
        setAgentConfigsError(
          err instanceof Error ? err.message : "Failed to set active agent",
        );
      } finally {
        setSettingActiveAgent(null);
      }
    };

    // Handle deleting agent
    const handleDeleteAgent = async (agentId: number) => {
      setDeletingAgentId(agentId);
      try {
        await felixApi.deleteAgentConfiguration(agentId);
        setSuccessMessage("Agent deleted successfully");
        setShowDeleteConfirm(null);
        fetchAgentConfigurations();
      } catch (err) {
        console.error("Failed to delete agent:", err);
        setAgentConfigsError(
          err instanceof Error ? err.message : "Failed to delete agent",
        );
      } finally {
        setDeletingAgentId(null);
      }
    };

    // Reset agent form
    const resetAgentForm = () => {
      setShowAgentForm(false);
      setEditingAgentId(null);
      setAgentFormName("");
      setAgentFormExecutable("");
      setAgentFormArgs("");
      setAgentFormWorkingDir(".");
      setAgentFormError(null);
    };

    // Open add agent form
    const openAddAgentForm = () => {
      resetAgentForm();
      setShowAgentForm(true);
    };

    // Open edit agent form
    const openEditAgentForm = (agent: AgentConfiguration) => {
      setEditingAgentId(agent.id);
      setAgentFormName(agent.name);
      setAgentFormExecutable(agent.executable);
      setAgentFormArgs(agent.args.join(" "));
      setAgentFormWorkingDir(agent.working_directory);
      setAgentFormError(null);
      setShowAgentForm(true);
    };

    // Handle agent form save
    const handleAgentFormSave = async () => {
      // Validate required fields
      if (!agentFormName.trim()) {
        setAgentFormError("Agent name is required");
        return;
      }
      if (!agentFormExecutable.trim()) {
        setAgentFormError("Executable path is required");
        return;
      }

      setAgentFormSaving(true);
      setAgentFormError(null);

      try {
        const agentData = {
          name: agentFormName.trim(),
          executable: agentFormExecutable.trim(),
          args: agentFormArgs.trim() ? agentFormArgs.trim().split(/\s+/) : [],
          working_directory: agentFormWorkingDir.trim() || ".",
        };

        if (editingAgentId !== null) {
          // Update existing agent
          await felixApi.updateAgentConfiguration(editingAgentId, agentData);
          setSuccessMessage("Agent updated successfully");
        } else {
          // Create new agent
          await felixApi.createAgentConfiguration(agentData);
          setSuccessMessage("Agent created successfully");
        }

        resetAgentForm();
        fetchAgentConfigurations();
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
            <h3 className="text-lg font-semibold">Agent Configurations</h3>
            <p className="text-xs theme-text-muted mt-1">
              Manage saved agent presets from agents.json
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              onClick={() => {
                fetchAgentConfigurations();
                fetchAgents();
              }}
              disabled={agentConfigsLoading || agentsLoading}
              variant="secondary"
              size="sm"
              className="text-xs font-bold"
            >
              <svg
                className={`w-4 h-4 ${agentConfigsLoading || agentsLoading ? "animate-spin" : ""}`}
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
              {agentConfigsLoading || agentsLoading
                ? "Refreshing..."
                : "Refresh"}
            </Button>
            <Button onClick={openAddAgentForm} size="sm" className="uppercase">
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M12 4v16m8-8H4"
                />
              </svg>
              Add Agent
            </Button>
          </div>
        </div>

        {/* Agent Form (Add/Edit) */}
        {showAgentForm && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-bold theme-text-secondary">
                {editingAgentId !== null ? "Edit Agent" : "Add New Agent"}
              </h4>
              <Button
                onClick={resetAgentForm}
                variant="ghost"
                size="icon"
                className="h-8 w-8"
              >
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </Button>
            </div>

            {/* Form Error */}
            {agentFormError && (
              <Alert className="mb-4 border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                <AlertDescription className="text-[var(--destructive-500)]">
                  {agentFormError}
                </AlertDescription>
              </Alert>
            )}

            <div className="space-y-4">
              {/* Name */}
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
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  A unique name for this agent configuration
                </p>
              </div>

              {/* Executable */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Executable Path *
                </label>
                <Input
                  type="text"
                  placeholder="droid"
                  value={agentFormExecutable}
                  onChange={(e) => setAgentFormExecutable(e.target.value)}
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Path to the agent executable (e.g., droid, python, npx)
                </p>
              </div>

              {/* Arguments */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Arguments
                </label>
                <Input
                  type="text"
                  placeholder="exec --no-interactive"
                  value={agentFormArgs}
                  onChange={(e) => setAgentFormArgs(e.target.value)}
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Command-line arguments passed to the executable
                  (space-separated)
                </p>
              </div>

              {/* Working Directory */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Working Directory
                </label>
                <Input
                  type="text"
                  placeholder="."
                  value={agentFormWorkingDir}
                  onChange={(e) => setAgentFormWorkingDir(e.target.value)}
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Working directory for agent execution (use "." for project
                  root)
                </p>
              </div>

              {/* Form Actions */}
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
                    !agentFormExecutable.trim()
                  }
                  size="sm"
                  className="uppercase"
                >
                  {agentFormSaving ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Saving...
                    </>
                  ) : editingAgentId !== null ? (
                    "Update Agent"
                  ) : (
                    "Create Agent"
                  )}
                </Button>
              </div>
            </div>
          </div>
        )}

        {/* Agent Configurations List */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <h4 className="text-sm font-bold theme-text-secondary mb-4">
            Saved Agents
          </h4>

          {/* Error State */}
          {agentConfigsError && (
            <Alert className="mb-4 border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
                <svg
                  className="w-4 h-4 mt-0.5 flex-shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                  />
                </svg>
                <div>
                  <p className="text-xs">{agentConfigsError}</p>
                  <Button
                    onClick={fetchAgentConfigurations}
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

          {/* Loading State */}
          {agentConfigsLoading && agentConfigurations.length === 0 && (
            <div className="flex flex-col items-center justify-center py-8">
              <div className="w-6 h-6 border-2 border-[var(--border-default)] border-t-[var(--accent-primary)] rounded-full animate-spin mb-3" />
              <span className="text-[10px] font-mono theme-text-muted uppercase">
                Loading agent configurations...
              </span>
            </div>
          )}

          {/* Empty State */}
          {!agentConfigsLoading &&
            !agentConfigsError &&
            agentConfigurations.length === 0 && (
              <div className="text-center py-8">
                <div className="w-12 h-12 theme-bg-surface rounded-xl flex items-center justify-center mx-auto mb-4">
                  <svg
                    className="w-6 h-6 theme-text-muted"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
                    />
                  </svg>
                </div>
                <h4 className="text-sm font-bold theme-text-tertiary mb-2">
                  No Agent Configurations
                </h4>
                <p className="text-xs theme-text-muted max-w-sm mx-auto">
                  No saved agent configurations found. Add an agent to get
                  started.
                </p>
              </div>
            )}

          {/* Agent Configurations List */}
          {agentConfigurations.length > 0 && (
            <div className="space-y-3">
              {agentConfigurations
                .sort((a, b) => a.id - b.id)
                .map((agent) => {
                  const isSystemDefault = agent.id === 0;
                  const isActive = agent.id === activeAgentId;

                  return (
                    <div
                      key={agent.id}
                      className={`theme-bg-base border rounded-lg p-4 transition-all ${
                        isActive
                          ? "border-[var(--accent-primary)]/40 bg-[var(--selected-bg)]"
                          : "border-[var(--border-muted)]"
                      }`}
                    >
                      <div className="flex items-start justify-between gap-4">
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2 mb-2 flex-wrap">
                            <h5 className="text-sm font-bold theme-text-secondary truncate">
                              {agent.name}
                            </h5>
                            <span className="text-[9px] font-mono theme-text-muted">
                              ID: {agent.id}
                            </span>
                            {isSystemDefault && (
                              <span className="px-2 py-0.5 text-[9px] font-bold bg-[var(--status-warning)]/20 text-[var(--status-warning)] rounded-full flex items-center gap-1">
                                🔒 System Default
                              </span>
                            )}
                            {isActive && (
                              <span className="px-2 py-0.5 text-[9px] font-bold bg-[var(--accent-primary)]/20 text-[var(--accent-primary)] rounded-full flex items-center gap-1">
                                ✓ Active
                              </span>
                            )}
                          </div>
                          <div className="space-y-1 text-[11px]">
                            <div className="flex items-center gap-2">
                              <span className="theme-text-muted">
                                Executable:
                              </span>
                              <code className="theme-text-tertiary font-mono bg-[var(--hover-bg)] px-1.5 py-0.5 rounded">
                                {agent.executable}
                              </code>
                            </div>
                            {agent.args.length > 0 && (
                              <div className="flex items-start gap-2">
                                <span className="theme-text-muted">Args:</span>
                                <code className="theme-text-tertiary font-mono bg-[var(--hover-bg)] px-1.5 py-0.5 rounded break-all">
                                  {agent.args.join(" ")}
                                </code>
                              </div>
                            )}
                            <div className="flex items-center gap-2">
                              <span className="theme-text-muted">
                                Working Dir:
                              </span>
                              <code className="theme-text-tertiary font-mono bg-[var(--hover-bg)] px-1.5 py-0.5 rounded">
                                {agent.working_directory}
                              </code>
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2 flex-shrink-0">
                          {!isActive && (
                            <Button
                              onClick={() => handleSetActiveAgent(agent.id)}
                              disabled={settingActiveAgent === agent.id}
                              size="sm"
                              className="text-[10px] font-bold uppercase"
                            >
                              {settingActiveAgent === agent.id ? (
                                <>
                                  <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                  Setting...
                                </>
                              ) : (
                                "Set Active"
                              )}
                            </Button>
                          )}
                          <Button
                            onClick={() => openEditAgentForm(agent)}
                            variant="secondary"
                            size="sm"
                            className="text-[10px] font-bold"
                          >
                            Edit
                          </Button>
                          {isSystemDefault ? (
                            <Button
                              disabled
                              variant="secondary"
                              size="sm"
                              className="text-[10px] font-bold"
                              title="System default cannot be deleted"
                            >
                              Delete
                            </Button>
                          ) : (
                            <Button
                              onClick={() => setShowDeleteConfirm(agent.id)}
                              variant="destructive"
                              size="sm"
                              className="text-[10px] font-bold bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                            >
                              Delete
                            </Button>
                          )}
                        </div>
                      </div>

                      {/* Delete Confirmation */}
                      {showDeleteConfirm === agent.id && (
                        <div className="mt-4 pt-4 border-t border-[var(--border-default)]">
                          <div className="flex items-center justify-between">
                            <p className="text-xs text-[var(--status-warning)]">
                              Delete this agent configuration? This cannot be
                              undone.
                            </p>
                            <div className="flex items-center gap-2">
                              <Button
                                onClick={() => setShowDeleteConfirm(null)}
                                variant="ghost"
                                size="sm"
                                className="text-[10px] font-bold"
                              >
                                Cancel
                              </Button>
                              <Button
                                onClick={() => handleDeleteAgent(agent.id)}
                                disabled={deletingAgentId === agent.id}
                                variant="destructive"
                                size="sm"
                                className="text-[10px] font-bold bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                              >
                                {deletingAgentId === agent.id ? (
                                  <>
                                    <div className="w-3 h-3 border-2 border-[var(--status-error)]/30 border-t-[var(--status-error)] rounded-full animate-spin" />
                                    Deleting...
                                  </>
                                ) : (
                                  "Confirm Delete"
                                )}
                              </Button>
                            </div>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
            </div>
          )}
        </div>

        {/* Running Agents (Orchestration) */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <h4 className="text-sm font-bold theme-text-secondary mb-4">
            Running Agents
          </h4>

          {/* Error State */}
          {agentsError && (
            <Alert className="mb-4 border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
                <svg
                  className="w-4 h-4 mt-0.5 flex-shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                  />
                </svg>
                <div>
                  <p className="text-xs">{agentsError}</p>
                  <Button
                    onClick={fetchAgents}
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

          {/* Loading State */}
          {agentsLoading && Object.keys(registeredAgents).length === 0 && (
            <div className="flex flex-col items-center justify-center py-8">
              <div className="w-6 h-6 border-2 border-[var(--border-default)] border-t-[var(--accent-primary)] rounded-full animate-spin mb-3" />
              <span className="text-[10px] font-mono theme-text-muted uppercase">
                Loading running agents...
              </span>
            </div>
          )}

          {/* Empty State */}
          {!agentsLoading &&
            !agentsError &&
            Object.keys(registeredAgents).length === 0 && (
              <div className="text-center py-6">
                <p className="text-xs theme-text-muted">
                  No agents are currently running. Start an agent to see it
                  here.
                </p>
              </div>
            )}

          {/* Agents List */}
          {Object.keys(registeredAgents).length > 0 && (
            <div className="space-y-3">
              {Object.entries(registeredAgents)
                .sort(([, a], [, b]) => {
                  const statusOrder = { active: 0, inactive: 1, stopped: 2 };
                  const aOrder =
                    statusOrder[a.status as keyof typeof statusOrder] ?? 3;
                  const bOrder =
                    statusOrder[b.status as keyof typeof statusOrder] ?? 3;
                  if (aOrder !== bOrder) return aOrder - bOrder;
                  const aTime = a.last_heartbeat
                    ? new Date(a.last_heartbeat).getTime()
                    : 0;
                  const bTime = b.last_heartbeat
                    ? new Date(b.last_heartbeat).getTime()
                    : 0;
                  return bTime - aTime;
                })
                .map(([agentName, agent]) => (
                  <div
                    key={agentName}
                    className="theme-bg-base border border-[var(--border-muted)] rounded-lg p-4"
                  >
                    <div className="flex items-center gap-2 mb-2">
                      <span
                        className="flex-shrink-0"
                        title={`Status: ${agent.status}`}
                      >
                        {agent.status === "active" && (
                          <span className="text-base">🟢</span>
                        )}
                        {agent.status === "inactive" && (
                          <span className="text-base">⚪</span>
                        )}
                        {agent.status === "stopped" && (
                          <span className="text-base">🔴</span>
                        )}
                      </span>
                      <h5 className="text-sm font-bold theme-text-secondary truncate">
                        {agentName}
                      </h5>
                    </div>
                    <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-[11px]">
                      <div className="flex items-center gap-2">
                        <span className="theme-text-muted">Hostname:</span>
                        <span className="theme-text-tertiary font-mono">
                          {agent.hostname}
                        </span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="theme-text-muted">PID:</span>
                        <span className="theme-text-tertiary font-mono">
                          {agent.pid}
                        </span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="theme-text-muted">
                          Last heartbeat:
                        </span>
                        <span className="theme-text-tertiary">
                          {getRelativeTime(agent.last_heartbeat)}
                        </span>
                      </div>
                      {agent.current_run_id && (
                        <div className="flex items-center gap-2">
                          <span className="theme-text-muted">Working on:</span>
                          <span className="theme-text-secondary font-mono">
                            {agent.current_run_id}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
            </div>
          )}
        </div>

        {/* Info Note */}
        <div className="bg-[var(--status-info)]/5 border border-[var(--status-info)]/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <svg
              className="w-4 h-4 text-[var(--status-info)] mt-0.5 flex-shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <div className="text-xs text-[var(--status-info)]/80">
              <p>
                <strong>Agent Configurations</strong> are saved presets (from
                agents.json). The <strong>active</strong> agent is used when
                starting new runs.
              </p>
              <p className="mt-1">
                <strong>Running Agents</strong> show currently registered agent
                instances with heartbeats.
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  };

  // Copilot settings state
  const [copilotTestLoading, setCopilotTestLoading] = useState(false);
  const [copilotTestResult, setCopilotTestResult] = useState<{
    success: boolean;
    error?: string;
  } | null>(null);

  // Copilot API key state (stored in localStorage)
  const [copilotApiKeyInput, setCopilotApiKeyInput] = useState<string>("");
  const [copilotApiKeyHasValue, setCopilotApiKeyHasValue] =
    useState<boolean>(false);
  const [copilotApiKeySaving, setCopilotApiKeySaving] = useState(false);
  const [copilotApiKeySaved, setCopilotApiKeySaved] = useState(false);

  // Load Copilot API key status from localStorage on mount
  useEffect(() => {
    const savedKey = getCopilotApiKey();
    setCopilotApiKeyHasValue(!!savedKey);
    // Don't populate the input with the actual key for security
    // Just show that a key exists
  }, []);

  // Clear API key saved message after 3 seconds
  useEffect(() => {
    if (copilotApiKeySaved) {
      const timeout = setTimeout(() => setCopilotApiKeySaved(false), 3000);
      return () => clearTimeout(timeout);
    }
  }, [copilotApiKeySaved]);

  // Save Copilot API key to localStorage
  const handleSaveCopilotApiKey = () => {
    if (!copilotApiKeyInput.trim()) return;
    setCopilotApiKeySaving(true);
    try {
      setCopilotApiKey(copilotApiKeyInput.trim());
      setCopilotApiKeyHasValue(true);
      setCopilotApiKeyInput("");
      setCopilotApiKeySaved(true);
      // Also reset test result since key changed
      setCopilotTestResult(null);
    } finally {
      setCopilotApiKeySaving(false);
    }
  };

  // Clear Copilot API key from localStorage
  const handleClearCopilotApiKey = () => {
    clearCopilotApiKey();
    setCopilotApiKeyHasValue(false);
    setCopilotApiKeyInput("");
    setCopilotTestResult(null);
  };

  // Model options by provider
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

  // Default copilot config
  const defaultCopilotConfig = {
    enabled: false,
    provider: "openai" as const,
    model: "gpt-4o",
    context_sources: {
      agents_md: true,
      learnings_md: true,
      prompt_md: true,
      requirements: true,
      other_specs: true,
    },
    features: {
      streaming: true,
      auto_suggest: true,
      context_aware: true,
    },
  };

  // Handle copilot config changes
  const handleCopilotChange = (field: string, value: any) => {
    if (!config) return;

    const currentCopilot = config.copilot || defaultCopilotConfig;

    const newConfig = {
      ...config,
      copilot: {
        ...currentCopilot,
        [field]: value,
      },
    };

    // Reset model when provider changes
    if (field === "provider") {
      const defaultModel =
        value === "openai"
          ? "gpt-4o"
          : value === "anthropic"
            ? "claude-3-5-sonnet-20241022"
            : "";
      newConfig.copilot = {
        ...newConfig.copilot,
        model: defaultModel,
      };
    }

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  const handleCopilotContextChange = (field: string, value: boolean) => {
    if (!config) return;

    const currentCopilot = config.copilot || defaultCopilotConfig;

    const newConfig = {
      ...config,
      copilot: {
        ...currentCopilot,
        context_sources: {
          ...currentCopilot.context_sources,
          [field]: value,
        },
      },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  const handleCopilotFeatureChange = (field: string, value: boolean) => {
    if (!config) return;

    const currentCopilot = config.copilot || defaultCopilotConfig;

    const newConfig = {
      ...config,
      copilot: {
        ...currentCopilot,
        features: {
          ...currentCopilot.features,
          [field]: value,
        },
      },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  // Test copilot connection
  const handleTestCopilotConnection = async () => {
    setCopilotTestLoading(true);
    setCopilotTestResult(null);

    try {
      const result = await felixApi.testCopilotConnection();
      setCopilotTestResult({
        success: result.success,
        error: result.error,
      });
    } catch (err) {
      setCopilotTestResult({
        success: false,
        error: err instanceof Error ? err.message : "Failed to test connection",
      });
    } finally {
      setCopilotTestLoading(false);
    }
  };

  // Reset copilot to defaults
  const handleResetCopilot = () => {
    if (!config) return;

    const newConfig = {
      ...config,
      copilot: { ...defaultCopilotConfig },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
    setCopilotTestResult(null);
  };

  // Render Copilot settings
  const renderCopilotSettings = () => {
    if (!config) return null;

    const copilotConfig = config.copilot || defaultCopilotConfig;
    const isEnabled = copilotConfig.enabled;
    const provider = copilotConfig.provider || "openai";

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold">Felix Copilot</h3>
            <p className="text-xs theme-text-muted mt-1">
              AI-powered spec writing assistant
            </p>
          </div>
          <Button
            onClick={handleResetCopilot}
            variant="ghost"
            size="sm"
            className="text-[10px] font-bold"
          >
            Reset to Defaults
          </Button>
        </div>

        {/* Enable/Disable Toggle */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <div className="flex items-center justify-between">
            <div>
              <label className="block text-sm font-bold theme-text-secondary">
                Enable Copilot
              </label>
              <p className="text-[11px] theme-text-muted mt-1">
                Turn on AI-powered assistance for spec writing
              </p>
            </div>
            <Switch
              checked={isEnabled}
              onCheckedChange={(checked) =>
                handleCopilotChange("enabled", checked)
              }
            />
          </div>
        </div>

        {/* Provider Selection */}
        <div
          className={`theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 transition-opacity ${!isEnabled ? "opacity-50" : ""}`}
        >
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Provider
          </label>
          <Select
            value={provider}
            onValueChange={(value) => handleCopilotChange("provider", value)}
            disabled={!isEnabled}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="openai">OpenAI</SelectItem>
              <SelectItem value="anthropic">Anthropic</SelectItem>
              <SelectItem value="custom">Custom</SelectItem>
            </SelectContent>
          </Select>
          <p className="mt-2 text-[11px] theme-text-muted">
            Choose your LLM provider. Felix uses your API key from .env file.
          </p>
        </div>

        {/* Info about BYOK */}
        <div className="bg-[var(--status-info)]/5 border border-[var(--status-info)]/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <svg
              className="w-4 h-4 text-[var(--status-info)] mt-0.5 flex-shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <p className="text-xs text-[var(--status-info)]/80">
              <strong>Bring Your Own Key (BYOK):</strong> Felix{" "}
              <strong>never</strong> stores your API remotely, or manages your
              API billing. Your API key stays in your local storage and is used
              only for direct API calls.{" "}
              <span className="text-[11px] theme-text-muted">
                {provider === "openai" && (
                  <a
                    href="https://platform.openai.com/api-keys"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[var(--accent-primary)] hover:underline"
                  >
                    Get your OpenAI API key here →
                  </a>
                )}
                {provider === "anthropic" && (
                  <a
                    href="https://console.anthropic.com/"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[var(--accent-primary)] hover:underline"
                  >
                    Get your Anthropic API key here →
                  </a>
                )}
              </span>
            </p>
          </div>
        </div>

        {/* API Key Configuration */}
        <div
          className={`theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 transition-opacity ${!isEnabled ? "opacity-50" : ""}`}
        >
          <label className="block text-sm font-bold theme-text-secondary mb-3">
            API Key
          </label>

          {/* API Key Status */}
          {copilotApiKeyHasValue && (
            <Alert className="mb-4 border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]">
              <AlertDescription className="flex items-center gap-2 text-[var(--brand-500)]">
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span className="text-xs">API key configured</span>
                <Button
                  onClick={handleClearCopilotApiKey}
                  disabled={!isEnabled}
                  variant="ghost"
                  size="sm"
                  className="ml-auto text-[10px] text-[var(--destructive-500)]"
                >
                  Clear
                </Button>
              </AlertDescription>
            </Alert>
          )}

          {/* API Key Input */}
          <div className="space-y-3 mb-4">
            <div>
              <label className="block text-xs font-bold theme-text-tertiary mb-2">
                {copilotApiKeyHasValue ? "Update API Key" : "Enter API Key"}
              </label>
              <div className="flex gap-2">
                <Input
                  type="password"
                  value={copilotApiKeyInput}
                  onChange={(e) => setCopilotApiKeyInput(e.target.value)}
                  disabled={!isEnabled}
                  placeholder={
                    copilotApiKeyHasValue ? "••••••••••••••••" : "sk-proj-..."
                  }
                  className="flex-1 font-mono"
                />
                <Button
                  onClick={handleSaveCopilotApiKey}
                  disabled={
                    !isEnabled ||
                    !copilotApiKeyInput.trim() ||
                    copilotApiKeySaving
                  }
                  size="sm"
                  className="uppercase"
                >
                  {copilotApiKeySaving ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Saving...
                    </>
                  ) : (
                    "Save"
                  )}
                </Button>
              </div>
              <p className="mt-1.5 text-[10px] theme-text-muted">
                Your API key is stored in your browser's localStorage (not sent
                to any server)
              </p>
            </div>

            {/* Save Confirmation */}
            {copilotApiKeySaved && (
              <div className="flex items-center gap-2 text-xs text-[var(--brand-500)]">
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span>API key saved successfully</span>
              </div>
            )}
          </div>

          {/* Test Connection Button */}
          <div className="flex items-center gap-3 mb-4">
            <Button
              onClick={handleTestCopilotConnection}
              disabled={
                !isEnabled || copilotTestLoading || !copilotApiKeyHasValue
              }
              size="sm"
              className="uppercase"
            >
              {copilotTestLoading ? (
                <>
                  <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Testing...
                </>
              ) : (
                "Test Connection"
              )}
            </Button>

            {copilotTestResult && (
              <div
                className={`flex items-center gap-2 text-xs ${copilotTestResult.success ? "text-[var(--status-success)]" : "text-[var(--status-error)]"}`}
              >
                {copilotTestResult.success ? (
                  <>
                    <span>✓</span>
                    <span>Connected successfully</span>
                  </>
                ) : (
                  <>
                    <span>✗</span>
                    <span>
                      {copilotTestResult.error || "Connection failed"}
                    </span>
                  </>
                )}
              </div>
            )}
          </div>

          {/* Fallback info for local development If no browser API key is set, the backend will check for .env*/}
        </div>

        {/* Model Selection */}
        <div
          className={`theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 transition-opacity ${!isEnabled ? "opacity-50" : ""}`}
        >
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Model
          </label>
          {provider === "custom" ? (
            <Input
              type="text"
              value={copilotConfig.model}
              onChange={(e) => handleCopilotChange("model", e.target.value)}
              disabled={!isEnabled}
              placeholder="Enter model name"
              className="font-mono"
            />
          ) : (
            <Select
              value={copilotConfig.model}
              onValueChange={(value) => handleCopilotChange("model", value)}
              disabled={!isEnabled}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {modelOptions[provider]?.map((option) => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          <p className="mt-2 text-[11px] theme-text-muted">
            Model used for spec generation and conversations
          </p>
        </div>

        {/* Context Sources */}
        <div
          className={`theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 transition-opacity ${!isEnabled ? "opacity-50" : ""}`}
        >
          <label className="block text-sm font-bold theme-text-secondary mb-4">
            Context Sources
          </label>
          <div className="space-y-3">
            {[
              {
                key: "agents_md",
                label: "AGENTS.md",
                description: "Operational instructions and validation",
              },
              {
                key: "learnings_md",
                label: "LEARNINGS.md",
                description: "Technical knowledge and common pitfalls",
              },
              {
                key: "prompt_md",
                label: "prompt.md",
                description: "Spec writing conventions",
              },
              {
                key: "requirements",
                label: "requirements.json",
                description: "Project dependencies and status",
              },
              {
                key: "other_specs",
                label: "Other specs",
                description: "Pattern consistency from existing specs",
              },
            ].map((source) => (
              <div
                key={source.key}
                className="flex items-center justify-between py-2"
              >
                <div>
                  <span className="text-sm theme-text-secondary">
                    {source.label}
                  </span>
                  <p className="text-[10px] theme-text-muted">
                    {source.description}
                  </p>
                </div>
                <Switch
                  checked={(copilotConfig.context_sources as any)[source.key]}
                  onCheckedChange={(checked) =>
                    handleCopilotContextChange(source.key, checked)
                  }
                  disabled={!isEnabled}
                />
              </div>
            ))}
          </div>
        </div>

        {/* Feature Toggles */}
        <div
          className={`theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 transition-opacity ${!isEnabled ? "opacity-50" : ""}`}
        >
          <label className="block text-sm font-bold theme-text-secondary mb-4">
            Features
          </label>
          <div className="space-y-3">
            {[
              {
                key: "streaming",
                label: "Streaming Responses",
                description:
                  "Enables token-by-token streaming for faster feedback",
              },
              {
                key: "auto_suggest",
                label: "Auto-suggest Spec Titles",
                description: "Suggests titles based on your input",
              },
              {
                key: "context_aware",
                label: "Context-aware Completions",
                description: "Uses project context in responses",
              },
            ].map((feature) => (
              <div
                key={feature.key}
                className="flex items-center justify-between py-2"
              >
                <div>
                  <span className="text-sm theme-text-secondary">
                    {feature.label}
                  </span>
                  <p className="text-[10px] theme-text-muted">
                    {feature.description}
                  </p>
                </div>
                <Switch
                  checked={(copilotConfig.features as any)[feature.key]}
                  onCheckedChange={(checked) =>
                    handleCopilotFeatureChange(feature.key, checked)
                  }
                  disabled={!isEnabled}
                />
              </div>
            ))}
          </div>
        </div>

        {/* Warning when enabled but no API key in localStorage */}
        {isEnabled && !copilotApiKeyHasValue && (
          <Alert className="border-[var(--warning-500)]/30 bg-[var(--warning-500)]/10 text-[var(--warning-500)]">
            <AlertDescription className="flex items-start gap-3 text-[var(--warning-500)]/80">
              <svg
                className="w-4 h-4 mt-0.5 flex-shrink-0"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
              <p className="text-xs">
                Copilot is enabled but no API key is configured. Enter your{" "}
                {provider === "openai"
                  ? "OpenAI"
                  : provider === "anthropic"
                    ? "Anthropic"
                    : ""}{" "}
                API key above to use copilot features.
              </p>
            </AlertDescription>
          </Alert>
        )}
      </div>
    );
  };

  // Render the active category's settings
  const renderActiveSettings = () => {
    switch (activeCategory) {
      case "general":
        return renderGeneralSettings();
      case "paths":
        return renderPathsSettings();
      case "copilot":
        return renderCopilotSettings();
      case "advanced":
        return renderAdvancedSettings();
      case "projects":
        return renderProjectsSettings();
      case "agents":
        return renderAgentsSettings();
      default:
        return null;
    }
  };

  // Loading state
  if (loading) {
    return (
      <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
        <div className="flex-1 flex flex-col items-center justify-center">
          <div className="w-8 h-8 border-2 border-[var(--border-default)] border-t-brand-500 rounded-full animate-spin mb-4" />
          <span className="text-xs font-mono theme-text-muted uppercase">
            Loading settings...
          </span>
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
            <svg
              className="w-8 h-8 text-[var(--status-error)]"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
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
            ← Back to Projects
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex theme-bg-base overflow-hidden">
      {/* Left Sidebar - Categories Navigation */}
      <div className="w-64 border-r border-[var(--border-default)] flex flex-col theme-bg-deep flex-shrink-0 bg-[var(--bg-deep)]">
        {/* Sidebar Header */}
        <div className="h-14 border-b border-[var(--border-default)] flex items-center px-5">
          <Button
            onClick={onBack}
            variant="ghost"
            size="icon"
            className="mr-3 h-8 w-8"
            title="Back to Projects"
          >
            <svg
              className="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M15 19l-7-7 7-7"
              />
            </svg>
          </Button>
          <span className="text-xs font-bold theme-text-tertiary uppercase tracking-widest">
            Settings
          </span>
        </div>

        {/* Categories List */}
        <div className="flex-1 p-3 space-y-1 overflow-y-auto custom-scrollbar">
          {CATEGORIES.map((category) => (
            <Button
              key={category.id}
              onClick={() => setActiveCategory(category.id)}
              variant="ghost"
              size="sm"
              className={`w-full justify-start gap-3 px-4 py-3 rounded-xl text-left ${
                activeCategory === category.id
                  ? "bg-[var(--selected-bg)] text-[var(--accent-primary)] border border-[var(--accent-primary)]/20"
                  : "theme-text-tertiary hover:theme-text-secondary hover:bg-[var(--hover-bg)] border border-transparent"
              }`}
            >
              <div
                className={`flex-shrink-0 ${activeCategory === category.id ? "text-[var(--accent-primary)]" : "theme-text-muted"}`}
              >
                {category.icon}
              </div>
              <div className="min-w-0">
                <span className="sidebar-label">{category.label}</span>
                <span className="block text-[10px] theme-text-muted truncate">
                  {category.description}
                </span>
              </div>
            </Button>
          ))}
        </div>

        {/* Sidebar Footer */}
        <div className="p-4 border-t border-[var(--border-default)]">
          <div className="flex items-center gap-2 text-[10px] theme-text-muted">
            <IconFelix className="w-4 h-4 text-[var(--accent-primary)]/50" />
            <span className="font-mono">felix/config.json</span>
          </div>
        </div>
      </div>

      {/* Right Panel - Settings Content */}
      <div className="flex-1 flex flex-col min-w-0 theme-bg-base">
        {/* Top Bar with Save Controls */}
        <div className="h-14 border-b border-[var(--border-default)] flex items-center px-6 justify-between backdrop-blur flex-shrink-0 bg-[var(--bg-base)]/95">
          <div className="flex items-center gap-3">
            {hasChanges && (
              <div className="flex items-center gap-2 text-[10px] text-[var(--status-warning)]">
                <div className="w-1.5 h-1.5 rounded-full bg-[var(--status-warning)] animate-pulse" />
                <span className="font-mono uppercase">Unsaved changes</span>
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
                Object.keys(validationErrors).length > 0
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

        {/* Success/Error Messages */}
        {(successMessage || error) && (
          <div
            className={`px-6 py-3 text-xs flex items-center gap-2 ${
              successMessage
                ? "bg-[var(--status-success)]/10 text-[var(--status-success)]"
                : "bg-[var(--status-error)]/10 text-[var(--status-error)]"
            }`}
          >
            {successMessage ? (
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M5 13l4 4L19 7"
                />
              </svg>
            ) : (
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            )}
            {successMessage || error}
          </div>
        )}

        {/* Settings Content */}
        <div className="flex-1 overflow-y-auto custom-scrollbar p-8 theme-bg-base">
          <div className="max-w-2xl">{renderActiveSettings()}</div>
        </div>
      </div>
    </div>
  );
};

export default SettingsScreen;

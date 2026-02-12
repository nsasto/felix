import React, { useState, useEffect, useCallback } from "react";
import { felixApi, FelixConfig, ConfigContent } from "../services/felixApi";
import {
  AlertTriangle,
  Bot as IconFelix,
  ChevronLeft,
  FileText as IconFileText,
  Folder,
} from "lucide-react";
import { PageLoading } from "./ui/page-loading";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Switch } from "./ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";

interface ConfigPanelProps {
  projectId: string;
  onClose: () => void;
}

const ConfigPanel: React.FC<ConfigPanelProps> = ({ projectId, onClose }) => {
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

  // Fetch config on mount
  useEffect(() => {
    const fetchConfig = async () => {
      setLoading(true);
      setError(null);

      try {
        const result = await felixApi.getConfig(projectId);
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

      return errors;
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

    setConfig({
      ...config,
      backpressure: {
        ...config.backpressure,
        [field]: value,
      },
    });
  };

  // Handle save
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
      const result = await felixApi.updateConfig(projectId, config);
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

  if (loading) {
    return (
      <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
        <div className="h-14 border-b theme-border flex items-center px-6 justify-between theme-bg-base/95 backdrop-blur">
          <div className="flex items-center gap-4">
            <Button
              type="button"
              onClick={onClose}
              variant="ghost"
              size="icon"
              className="h-8 w-8 rounded-lg transition-all theme-text-muted hover:theme-text-secondary hover:bg-[var(--hover-bg)]"
            >
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <h2 className="text-sm font-bold theme-text-primary">
              Configuration
            </h2>
          </div>
        </div>
        <div className="flex-1">
          <PageLoading message="Loading configuration..." />
        </div>
      </div>
    );
  }

  if (error && !config) {
    return (
      <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
        <div className="h-14 border-b theme-border flex items-center px-6 justify-between theme-bg-base/95 backdrop-blur">
          <div className="flex items-center gap-4">
            <Button
              type="button"
              onClick={onClose}
              variant="ghost"
              size="icon"
              className="h-8 w-8 rounded-lg transition-all theme-text-muted hover:theme-text-secondary hover:bg-[var(--hover-bg)]"
            >
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <h2 className="text-sm font-bold theme-text-primary">
              Configuration
            </h2>
          </div>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <div className="w-16 h-16 theme-bg-surface rounded-2xl flex items-center justify-center mb-4">
            <IconFileText className="w-8 h-8 theme-text-muted" />
          </div>
          <h3 className="text-sm font-bold theme-text-tertiary mb-2">
            Failed to Load Configuration
          </h3>
          <p className="text-xs theme-text-muted max-w-md">{error}</p>
        </div>
      </div>
    );
  }

  if (!config) return null;

  return (
    <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
      {/* Header */}
      <div className="h-14 border-b theme-border flex items-center px-6 justify-between theme-bg-base/95 backdrop-blur">
        <div className="flex items-center gap-4">
          <Button
            type="button"
            onClick={onClose}
            variant="ghost"
            size="icon"
            className="h-8 w-8 rounded-lg transition-all theme-text-muted hover:theme-text-secondary hover:bg-[var(--hover-bg)]"
          >
            <ChevronLeft className="w-4 h-4" />
          </Button>
          <div>
            <h2 className="text-sm font-bold theme-text-primary">
              Configuration
            </h2>
            <p className="text-[10px] font-mono theme-text-muted">
              felix/config.json
            </p>
          </div>
        </div>

        {/* Save controls */}
        <div className="flex items-center gap-3">
          {hasChanges && (
            <Button
              type="button"
              onClick={handleReset}
              variant="ghost"
              size="sm"
              className="h-auto px-3 py-1.5 text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors"
            >
              Reset
            </Button>
          )}
          <Button
            type="button"
            onClick={handleSave}
            disabled={
              saving || !hasChanges || Object.keys(validationErrors).length > 0
            }
            className={`h-auto px-4 py-1.5 text-[10px] font-bold rounded-lg transition-all flex items-center gap-2 ${
              hasChanges && Object.keys(validationErrors).length === 0
                ? "bg-brand-600 text-white hover:bg-brand-500"
                : "theme-bg-surface theme-text-muted cursor-not-allowed"
            }`}
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

      {/* Success/Error messages */}
      {(successMessage || error) && (
        <div
          className={`px-6 py-3 text-xs ${
            successMessage
              ? "bg-emerald-500/10 text-emerald-400"
              : "bg-red-500/10 text-red-400"
          }`}
        >
          {successMessage || error}
        </div>
      )}

      {/* Content */}
      <div className="flex-1 overflow-y-auto custom-scrollbar p-8">
        <div className="max-w-2xl mx-auto space-y-8">
          {/* Executor Settings */}
          <section className="theme-bg-elevated border theme-border rounded-2xl p-6">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-brand-500/10 rounded-xl flex items-center justify-center">
                <IconFelix className="w-5 h-5 text-brand-400" />
              </div>
              <div>
                <h3 className="text-sm font-bold theme-text-primary">
                  Executor Settings
                </h3>
                <p className="text-[10px] theme-text-muted">
                  Agent execution configuration
                </p>
              </div>
            </div>

            <div className="space-y-5">
              {/* Max Iterations */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
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
                  className={`w-full h-auto theme-bg-base border rounded-xl px-4 py-3 text-sm theme-text-secondary outline-none transition-all ${
                    validationErrors.max_iterations
                      ? "border-red-500/50 focus:border-red-500"
                      : "theme-border-muted focus:border-brand-500/50 focus:ring-1 focus:ring-brand-500/20"
                  }`}
                />
                {validationErrors.max_iterations && (
                  <p className="mt-1 text-[10px] text-red-400">
                    {validationErrors.max_iterations}
                  </p>
                )}
                <p className="mt-1 text-[10px] theme-text-muted">
                  Maximum number of iterations the agent will run
                </p>
              </div>

              {/* Default Mode */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Default Mode
                </label>
                <Select
                  value={config.executor.default_mode}
                  onValueChange={(value) =>
                    handleExecutorChange("default_mode", value)
                  }
                >
                  <SelectTrigger
                    className={`w-full h-auto theme-bg-base border rounded-xl px-4 py-3 text-sm theme-text-secondary outline-none transition-all ${
                      validationErrors.default_mode
                        ? "border-red-500/50"
                        : "theme-border-muted focus:border-brand-500/50 focus:ring-1 focus:ring-brand-500/20"
                    }`}
                  >
                    <SelectValue placeholder="Select mode" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="planning">Planning</SelectItem>
                    <SelectItem value="building">Building</SelectItem>
                  </SelectContent>
                </Select>
                {validationErrors.default_mode && (
                  <p className="mt-1 text-[10px] text-red-400">
                    {validationErrors.default_mode}
                  </p>
                )}
                <p className="mt-1 text-[10px] theme-text-muted">
                  Mode the agent starts in when a run begins
                </p>
              </div>

              {/* Auto Transition */}
              <div className="flex items-center justify-between">
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary">
                    Auto Transition
                  </label>
                  <p className="text-[10px] theme-text-muted">
                    Automatically switch from planning to building mode
                  </p>
                </div>
                <Switch
                  checked={config.executor.auto_transition}
                  onCheckedChange={(checked) =>
                    handleExecutorChange("auto_transition", checked)
                  }
                  aria-label="Auto transition"
                />
              </div>
            </div>
          </section>

          {/* Backpressure Settings */}
          <section className="theme-bg-elevated border theme-border rounded-2xl p-6">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-amber-500/10 rounded-xl flex items-center justify-center">
                <AlertTriangle className="w-5 h-5 text-amber-400" />
              </div>
              <div>
                <h3 className="text-sm font-bold theme-text-primary">
                  Backpressure
                </h3>
                <p className="text-[10px] theme-text-muted">
                  Build validation between iterations
                </p>
              </div>
            </div>

            <div className="space-y-5">
              {/* Backpressure Enabled */}
              <div className="flex items-center justify-between">
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary">
                    Enable Backpressure
                  </label>
                  <p className="text-[10px] theme-text-muted">
                    Run lint/test/build commands between agent iterations
                  </p>
                </div>
                <Switch
                  checked={config.backpressure.enabled}
                  onCheckedChange={(checked) =>
                    handleBackpressureChange("enabled", checked)
                  }
                  aria-label="Enable backpressure"
                />
              </div>

              {/* Backpressure Commands (read-only display) */}
              {config.backpressure.enabled &&
                config.backpressure.commands.length > 0 && (
                  <div>
                    <label className="block text-xs font-bold theme-text-tertiary mb-2">
                      Validation Commands
                    </label>
                    <div className="theme-bg-base border theme-border-muted rounded-xl p-4 space-y-2">
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
                    <p className="mt-1 text-[10px] theme-text-muted">
                      Edit felix/config.json directly to modify commands
                    </p>
                  </div>
                )}
            </div>
          </section>

          {/* Paths Settings (read-only) */}
          <section className="theme-bg-elevated border theme-border rounded-2xl p-6">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-emerald-500/10 rounded-xl flex items-center justify-center">
                <Folder className="w-5 h-5 text-emerald-400" />
              </div>
              <div>
                <h3 className="text-sm font-bold theme-text-primary">
                  Project Paths
                </h3>
                <p className="text-[10px] theme-text-muted">
                  File and directory locations (read-only)
                </p>
              </div>
            </div>

            <div className="space-y-3">
              <div className="flex justify-between items-center py-2 border-b theme-border-subtle">
                <span className="text-xs theme-text-muted">
                  Specs Directory
                </span>
                <code className="text-xs font-mono theme-text-tertiary">
                  {config.paths.specs}
                </code>
              </div>
              <div className="flex justify-between items-center py-2 border-b theme-border-subtle">
                <span className="text-xs theme-text-muted">Plan File</span>
                <code className="text-xs font-mono theme-text-tertiary">
                  {config.paths.plan}
                </code>
              </div>
              <div className="flex justify-between items-center py-2 border-b theme-border-subtle">
                <span className="text-xs theme-text-muted">AGENTS.md</span>
                <code className="text-xs font-mono theme-text-tertiary">
                  {config.paths.agents}
                </code>
              </div>
              <div className="flex justify-between items-center py-2">
                <span className="text-xs theme-text-muted">Runs Directory</span>
                <code className="text-xs font-mono theme-text-tertiary">
                  {config.paths.runs}
                </code>
              </div>
            </div>
          </section>

          {/* Config Version */}
          <div className="text-center text-[10px] font-mono theme-text-faint">
            Config Version: {config.version}
          </div>
        </div>
      </div>
    </div>
  );
};

export default ConfigPanel;

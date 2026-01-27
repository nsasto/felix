import React, { useState, useEffect, useCallback } from 'react';
import { felixApi, FelixConfig, Project } from '../services/felixApi';
import { IconFelix } from './Icons';
import { useTheme, ThemeValue } from '../hooks/ThemeProvider';

interface SettingsScreenProps {
  projectId: string;
  onBack: () => void;
}

type SettingsCategory = 'general' | 'agent' | 'paths' | 'advanced' | 'projects';

interface CategoryInfo {
  id: SettingsCategory;
  label: string;
  description: string;
  icon: React.ReactNode;
}

const CATEGORIES: CategoryInfo[] = [
  {
    id: 'general',
    label: 'General',
    description: 'Basic Felix configuration',
    icon: (
      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
      </svg>
    ),
  },
  {
    id: 'agent',
    label: 'Agent',
    description: 'Agent execution preferences',
    icon: (
      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
      </svg>
    ),
  },
  {
    id: 'paths',
    label: 'Paths',
    description: 'File and directory locations',
    icon: (
      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
      </svg>
    ),
  },
  {
    id: 'advanced',
    label: 'Advanced',
    description: 'Developer and debug options',
    icon: (
      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
      </svg>
    ),
  },
  {
    id: 'projects',
    label: 'Projects',
    description: 'Manage registered projects',
    icon: (
      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
      </svg>
    ),
  },
];

const SettingsScreen: React.FC<SettingsScreenProps> = ({ projectId, onBack }) => {
  const { theme, setTheme } = useTheme();
  const [activeCategory, setActiveCategory] = useState<SettingsCategory>('general');
  const [config, setConfig] = useState<FelixConfig | null>(null);
  const [originalConfig, setOriginalConfig] = useState<FelixConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<Record<string, string>>({});

  // Projects state
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectsLoading, setProjectsLoading] = useState(false);
  const [projectsError, setProjectsError] = useState<string | null>(null);
  const [projectSearchQuery, setProjectSearchQuery] = useState('');
  const [registerPath, setRegisterPath] = useState('');
  const [registerName, setRegisterName] = useState('');
  const [isRegistering, setIsRegistering] = useState(false);
  const [showRegisterForm, setShowRegisterForm] = useState(false);
  const [unregisteringId, setUnregisteringId] = useState<string | null>(null);
  const [showUnregisterConfirm, setShowUnregisterConfirm] = useState<string | null>(null);
  const [configuringProjectId, setConfiguringProjectId] = useState<string | null>(null);
  const [configProjectName, setConfigProjectName] = useState('');
  const [configProjectPath, setConfigProjectPath] = useState('');
  const [isSavingConfig, setIsSavingConfig] = useState(false);

  // Fetch config on mount and sync theme
  useEffect(() => {
    const fetchConfig = async () => {
      setLoading(true);
      setError(null);

      try {
        const result = await felixApi.getConfig(projectId);
        setConfig(result.config);
        setOriginalConfig(result.config);
        
        // Sync theme from backend config to context and localStorage
        // This ensures the backend config is the source of truth for theme
        if (result.config.ui?.theme) {
          setTheme(result.config.ui.theme as ThemeValue);
        }
      } catch (err) {
        console.error('Failed to fetch config:', err);
        setError(err instanceof Error ? err.message : 'Failed to load configuration');
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
      console.error('Failed to fetch projects:', err);
      setProjectsError(err instanceof Error ? err.message : 'Failed to load projects');
    } finally {
      setProjectsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeCategory === 'projects') {
      fetchProjects();
    }
  }, [activeCategory, fetchProjects]);

  // Clear success message after 3 seconds
  useEffect(() => {
    if (successMessage) {
      const timeout = setTimeout(() => setSuccessMessage(null), 3000);
      return () => clearTimeout(timeout);
    }
  }, [successMessage]);

  // Validate config
  const validateConfig = useCallback((cfg: FelixConfig): Record<string, string> => {
    const errors: Record<string, string> = {};

    // Validate max_iterations
    if (!Number.isInteger(cfg.executor.max_iterations) || cfg.executor.max_iterations <= 0) {
      errors.max_iterations = 'Must be a positive integer';
    }

    // Validate default_mode
    if (!['planning', 'building'].includes(cfg.executor.default_mode)) {
      errors.default_mode = 'Must be "planning" or "building"';
    }

    // Validate backpressure max_retries if present
    if (cfg.backpressure.max_retries !== undefined) {
      if (!Number.isInteger(cfg.backpressure.max_retries) || cfg.backpressure.max_retries < 0) {
        errors.max_retries = 'Must be a non-negative integer';
      }
    }

    return errors;
  }, []);

  // Handle config field changes
  const handleExecutorChange = (field: keyof FelixConfig['executor'], value: any) => {
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

  const handleAgentChange = (field: keyof FelixConfig['agent'], value: any) => {
    if (!config) return;

    const newConfig = {
      ...config,
      agent: {
        ...config.agent,
        [field]: value,
      },
    };

    setConfig(newConfig);
    setValidationErrors(validateConfig(newConfig));
  };

  const handleBackpressureChange = (field: keyof FelixConfig['backpressure'], value: any) => {
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

  const handleUIChange = (field: keyof FelixConfig['ui'], value: any) => {
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

    // Apply theme change immediately for instant feedback
    if (field === 'theme') {
      setTheme(value as ThemeValue);
    }
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
      setSuccessMessage('Configuration saved successfully');
    } catch (err) {
      console.error('Failed to save config:', err);
      setError(err instanceof Error ? err.message : 'Failed to save configuration');
    } finally {
      setSaving(false);
    }
  };

  // Check if config has changes
  const hasChanges = config && originalConfig && 
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
      case 'general':
        newConfig.executor = { ...originalConfig.executor };
        break;
      case 'agent':
        newConfig.agent = { ...originalConfig.agent };
        break;
      case 'advanced':
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
            <h3 className="text-lg font-bold theme-text-secondary">General Settings</h3>
            <p className="text-xs theme-text-muted mt-1">Basic Felix configuration options</p>
          </div>
          <button
            onClick={handleResetCategory}
            className="text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors px-3 py-1.5 rounded-lg hover:bg-[var(--hover-bg)]"
          >
            Reset to Defaults
          </button>
        </div>

        {/* Theme Selection */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Theme
          </label>
          <select
            value={config.ui?.theme || 'dark'}
            onChange={(e) => handleUIChange('theme', e.target.value as ThemeValue)}
            className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary outline-none transition-all cursor-pointer focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20"
          >
            <option value="dark">Dark</option>
            <option value="light">Light</option>
            <option value="system">System</option>
          </select>
          <p className="mt-2 text-[11px] theme-text-muted">
            Choose your preferred color theme. "System" follows your operating system preference.
          </p>
        </div>

        {/* Max Iterations */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Max Iterations
          </label>
          <input
            type="number"
            min="1"
            value={config.executor.max_iterations}
            onChange={(e) => handleExecutorChange('max_iterations', parseInt(e.target.value) || 0)}
            className={`w-full theme-bg-base border rounded-lg px-4 py-2.5 text-sm theme-text-secondary outline-none transition-all ${
              validationErrors.max_iterations 
                ? 'border-[var(--status-error)]/50 focus:border-[var(--status-error)]'
                : 'border-[var(--border-muted)] focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20'
            }`}
          />
          {validationErrors.max_iterations && (
            <p className="mt-1.5 text-[10px] text-[var(--status-error)]">{validationErrors.max_iterations}</p>
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
          <select
            value={config.executor.default_mode}
            onChange={(e) => handleExecutorChange('default_mode', e.target.value)}
            className={`w-full theme-bg-base border rounded-lg px-4 py-2.5 text-sm theme-text-secondary outline-none transition-all cursor-pointer ${
              validationErrors.default_mode
                ? 'border-[var(--status-error)]/50'
                : 'border-[var(--border-muted)] focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20'
            }`}
          >
            <option value="planning">Planning</option>
            <option value="building">Building</option>
          </select>
          {validationErrors.default_mode && (
            <p className="mt-1.5 text-[10px] text-[var(--status-error)]">{validationErrors.default_mode}</p>
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
                Automatically switch from planning to building mode when plan is complete
              </p>
            </div>
            <button
              onClick={() => handleExecutorChange('auto_transition', !config.executor.auto_transition)}
              className={`w-12 h-6 rounded-full transition-all relative flex-shrink-0 ${
                config.executor.auto_transition 
                  ? 'bg-[var(--accent-secondary)]' 
                  : 'theme-bg-surface'
              }`}
            >
              <div
                className={`absolute top-1 w-4 h-4 bg-white rounded-full transition-all shadow-sm ${
                  config.executor.auto_transition ? 'left-7' : 'left-1'
                }`}
              />
            </button>
          </div>
        </div>
      </div>
    );
  };

  // Render Agent settings
  const renderAgentSettings = () => {
    if (!config) return null;

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-bold theme-text-secondary">Agent Settings</h3>
            <p className="text-xs theme-text-muted mt-1">Agent execution preferences and policies</p>
          </div>
          <button
            onClick={handleResetCategory}
            className="text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors px-3 py-1.5 rounded-lg hover:bg-[var(--hover-bg)]"
          >
            Reset to Defaults
          </button>
        </div>

        {/* Executable */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Executable Path
          </label>
          <input
            type="text"
            value={config.agent.executable}
            onChange={(e) => handleAgentChange('executable', e.target.value)}
            className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary font-mono outline-none transition-all focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20"
          />
          <p className="mt-2 text-[11px] theme-text-muted">
            Path to the agent executable (e.g., droid, python)
          </p>
        </div>

        {/* Arguments */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Arguments
          </label>
          <input
            type="text"
            value={config.agent.args.join(' ')}
            onChange={(e) => handleAgentChange('args', e.target.value.split(' ').filter(Boolean))}
            className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary font-mono outline-none transition-all focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20"
          />
          <p className="mt-2 text-[11px] theme-text-muted">
            Command-line arguments passed to the agent executable (space-separated)
          </p>
        </div>

        {/* Working Directory */}
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
          <label className="block text-sm font-bold theme-text-secondary mb-2">
            Working Directory
          </label>
          <input
            type="text"
            value={config.agent.working_directory}
            onChange={(e) => handleAgentChange('working_directory', e.target.value)}
            className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary font-mono outline-none transition-all focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20"
          />
          <p className="mt-2 text-[11px] theme-text-muted">
            Working directory for agent execution (use "." for project root)
          </p>
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
          <h3 className="text-lg font-bold theme-text-secondary">Paths</h3>
          <p className="text-xs theme-text-muted mt-1">File and directory locations (read-only)</p>
        </div>

        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl overflow-hidden">
          <div className="divide-y divide-[var(--border-default)]">
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm theme-text-secondary">Specs Directory</span>
                <p className="text-[10px] theme-text-muted mt-0.5">Location of specification files</p>
              </div>
              <code className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg">{config.paths.specs}</code>
            </div>
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm theme-text-secondary">AGENTS.md</span>
                <p className="text-[10px] theme-text-muted mt-0.5">Agent instructions file</p>
              </div>
              <code className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg">{config.paths.agents}</code>
            </div>
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm theme-text-secondary">Runs Directory</span>
                <p className="text-[10px] theme-text-muted mt-0.5">Location of run artifacts</p>
              </div>
              <code className="text-xs font-mono theme-text-tertiary theme-bg-surface px-3 py-1.5 rounded-lg">{config.paths.runs}</code>
            </div>
          </div>
        </div>

        <div className="bg-[var(--status-warning)]/5 border border-[var(--status-warning)]/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <svg className="w-4 h-4 text-[var(--status-warning)] mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <p className="text-xs text-[var(--status-warning)]/80">
              Path settings are read-only. Edit <code className="bg-[var(--status-warning)]/10 px-1 rounded">felix/config.json</code> directly to modify these values.
            </p>
          </div>
        </div>
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
            <h3 className="text-lg font-bold theme-text-secondary">Advanced Settings</h3>
            <p className="text-xs theme-text-muted mt-1">Developer options and debug settings</p>
          </div>
          <button
            onClick={handleResetCategory}
            className="text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors px-3 py-1.5 rounded-lg hover:bg-[var(--hover-bg)]"
          >
            Reset to Defaults
          </button>
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
            <button
              onClick={() => handleBackpressureChange('enabled', !config.backpressure.enabled)}
              className={`w-12 h-6 rounded-full transition-all relative flex-shrink-0 ${
                config.backpressure.enabled 
                  ? 'bg-[var(--accent-secondary)]' 
                  : 'theme-bg-surface'
              }`}
            >
              <div
                className={`absolute top-1 w-4 h-4 bg-white rounded-full transition-all shadow-sm ${
                  config.backpressure.enabled ? 'left-7' : 'left-1'
                }`}
              />
            </button>
          </div>

          {config.backpressure.enabled && (
            <div className="space-y-4 pt-4 border-t border-[var(--border-default)]">
              {/* Max Retries */}
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Max Retries
                </label>
                <input
                  type="number"
                  min="0"
                  value={(config.backpressure as any).max_retries || 3}
                  onChange={(e) => handleBackpressureChange('max_retries' as any, parseInt(e.target.value) || 0)}
                  className={`w-full theme-bg-base border rounded-lg px-4 py-2.5 text-sm theme-text-secondary outline-none transition-all ${
                    validationErrors.max_retries
                      ? 'border-[var(--status-error)]/50 focus:border-[var(--status-error)]'
                      : 'border-[var(--border-muted)] focus:border-[var(--accent-primary)]/50'
                  }`}
                />
                {validationErrors.max_retries && (
                  <p className="mt-1 text-[10px] text-[var(--status-error)]">{validationErrors.max_retries}</p>
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
                        <span className="text-[9px] font-mono theme-text-muted w-4">{index + 1}.</span>
                        <code className="text-xs font-mono theme-text-tertiary">{cmd}</code>
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
            <h3 className="text-lg font-bold theme-text-secondary">Projects</h3>
            <p className="text-xs theme-text-muted mt-1">Manage registered Felix projects</p>
          </div>
          <button
            onClick={() => setShowRegisterForm(true)}
            className="px-4 py-2 text-xs font-bold bg-[var(--accent-secondary)] text-white rounded-lg hover:bg-[var(--accent-primary)] transition-colors flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v16m8-8H4" />
            </svg>
            Register New Project
          </button>
        </div>

        {/* Search/Filter */}
        <div className="relative">
          <input
            type="text"
            placeholder="Search projects by name or path..."
            value={projectSearchQuery}
            onChange={(e) => setProjectSearchQuery(e.target.value)}
            className="w-full theme-bg-elevated border border-[var(--border-default)] rounded-xl px-4 py-3 pl-10 text-sm theme-text-secondary outline-none focus:border-[var(--accent-primary)]/50 focus:ring-1 focus:ring-[var(--accent-primary)]/20 transition-all"
          />
          <svg className="w-4 h-4 theme-text-muted absolute left-4 top-1/2 -translate-y-1/2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>

        {/* Register Form Modal */}
        {showRegisterForm && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-bold theme-text-secondary">Register New Project</h4>
              <button
                onClick={() => {
                  setShowRegisterForm(false);
                  setRegisterPath('');
                  setRegisterName('');
                }}
                className="theme-text-muted hover:theme-text-secondary transition-colors"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">Project Path *</label>
                <input
                  type="text"
                  placeholder="C:\path\to\your\project"
                  value={registerPath}
                  onChange={(e) => setRegisterPath(e.target.value)}
                  className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary font-mono outline-none focus:border-[var(--accent-primary)]/50 transition-all"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Full path to the project directory (must contain specs/ and felix/ directories)
                </p>
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">Project Name (optional)</label>
                <input
                  type="text"
                  placeholder="My Project"
                  value={registerName}
                  onChange={(e) => setRegisterName(e.target.value)}
                  className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary outline-none focus:border-[var(--accent-primary)]/50 transition-all"
                />
              </div>
              <div className="flex justify-end gap-3 pt-2">
                <button
                  onClick={() => {
                    setShowRegisterForm(false);
                    setRegisterPath('');
                    setRegisterName('');
                  }}
                  className="px-4 py-2 text-xs font-bold theme-text-muted hover:theme-text-secondary transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={async () => {
                    if (!registerPath.trim()) return;
                    setIsRegistering(true);
                    try {
                      await felixApi.registerProject({
                        path: registerPath.trim(),
                        name: registerName.trim() || undefined,
                      });
                      setShowRegisterForm(false);
                      setRegisterPath('');
                      setRegisterName('');
                      setSuccessMessage('Project registered successfully');
                      fetchProjects();
                    } catch (err) {
                      setProjectsError(err instanceof Error ? err.message : 'Failed to register project');
                    } finally {
                      setIsRegistering(false);
                    }
                  }}
                  disabled={!registerPath.trim() || isRegistering}
                  className={`px-4 py-2 text-xs font-bold rounded-lg transition-all flex items-center gap-2 ${
                    registerPath.trim() && !isRegistering
                      ? 'bg-[var(--accent-secondary)] text-white hover:bg-[var(--accent-primary)]'
                      : 'theme-bg-surface theme-text-muted cursor-not-allowed'
                  }`}
                >
                  {isRegistering ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Registering...
                    </>
                  ) : (
                    'Register Project'
                  )}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Loading State */}
        {projectsLoading && (
          <div className="flex flex-col items-center justify-center py-12">
            <div className="w-8 h-8 border-2 border-[var(--border-default)] border-t-[var(--accent-primary)] rounded-full animate-spin mb-4" />
            <span className="text-xs font-mono theme-text-muted uppercase">Loading projects...</span>
          </div>
        )}

        {/* Error State */}
        {projectsError && !projectsLoading && (
          <div className="bg-[var(--status-error)]/10 border border-[var(--status-error)]/20 rounded-xl p-4">
            <div className="flex items-start gap-3">
              <svg className="w-4 h-4 text-[var(--status-error)] mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <div>
                <p className="text-xs text-[var(--status-error)]">{projectsError}</p>
                <button
                  onClick={fetchProjects}
                  className="text-[10px] text-[var(--status-error)]/70 hover:text-[var(--status-error)] mt-2 underline"
                >
                  Try again
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Empty State */}
        {!projectsLoading && !projectsError && projects.length === 0 && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-8 text-center">
            <div className="w-12 h-12 theme-bg-surface rounded-xl flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 theme-text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
            </div>
            <h4 className="text-sm font-bold theme-text-tertiary mb-2">No Projects Registered</h4>
            <p className="text-xs theme-text-muted max-w-sm mx-auto">
              Register a Felix project to get started. Projects must have specs/ and felix/ directories.
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
                  (project.name?.toLowerCase().includes(query) || false) ||
                  project.path.toLowerCase().includes(query) ||
                  project.id.toLowerCase().includes(query)
                );
              })
              .sort((a, b) => new Date(b.registered_at).getTime() - new Date(a.registered_at).getTime())
              .map((project) => (
                <div
                  key={project.id}
                  className={`theme-bg-elevated border rounded-xl p-5 transition-all ${
                    project.id === projectId
                      ? 'border-[var(--accent-primary)]/40 bg-[var(--selected-bg)]'
                      : 'border-[var(--border-default)] hover:border-[var(--border-muted)]'
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
                        <button
                          onClick={() => navigator.clipboard.writeText(project.path)}
                          className="flex-shrink-0 theme-text-muted hover:theme-text-tertiary transition-colors"
                          title="Copy path"
                        >
                          <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                          </svg>
                        </button>
                      </div>
                      <p className="text-[10px] theme-text-muted mt-2">
                        Registered {new Date(project.registered_at).toLocaleDateString()}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <button
                        onClick={() => {
                          // TODO: Open project action - requires callback from parent
                        }}
                        className="px-3 py-1.5 text-[10px] font-bold theme-text-tertiary hover:theme-text-secondary border border-[var(--border-muted)] rounded-lg hover:bg-[var(--hover-bg)] transition-all"
                      >
                        Open
                      </button>
                      <button
                        onClick={() => {
                          setConfiguringProjectId(project.id);
                          setConfigProjectName(project.name || '');
                          setConfigProjectPath(project.path);
                        }}
                        className="px-3 py-1.5 text-[10px] font-bold theme-text-tertiary hover:theme-text-secondary border border-[var(--border-muted)] rounded-lg hover:bg-[var(--hover-bg)] transition-all"
                      >
                        Configure
                      </button>
                      {project.id !== projectId && (
                        <button
                          onClick={() => setShowUnregisterConfirm(project.id)}
                          className="px-3 py-1.5 text-[10px] font-bold text-[var(--status-error)]/70 hover:text-[var(--status-error)] border border-[var(--status-error)]/20 rounded-lg hover:bg-[var(--status-error)]/10 transition-all"
                        >
                          Unregister
                        </button>
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
                          <input
                            type="text"
                            value={configProjectName}
                            onChange={(e) => setConfigProjectName(e.target.value)}
                            placeholder={project.path.split(/[/\\]/).pop() || 'Project name'}
                            className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary outline-none focus:border-[var(--accent-primary)]/50 transition-all"
                          />
                          <p className="mt-1.5 text-[10px] theme-text-muted">
                            Display name for this project (leave empty to use directory name)
                          </p>
                        </div>
                        <div>
                          <label className="block text-xs font-bold theme-text-tertiary mb-2">
                            Project Folder
                          </label>
                          <input
                            type="text"
                            value={configProjectPath}
                            onChange={(e) => setConfigProjectPath(e.target.value)}
                            placeholder="C:\path\to\your\project"
                            className="w-full theme-bg-base border border-[var(--border-muted)] rounded-lg px-4 py-2.5 text-sm theme-text-secondary font-mono outline-none focus:border-[var(--accent-primary)]/50 transition-all"
                          />
                          <p className="mt-1.5 text-[10px] theme-text-muted">
                            Full path to the project directory (must contain specs/ and felix/ directories)
                          </p>
                        </div>
                        <div className="flex justify-end gap-3">
                          <button
                            onClick={() => {
                              setConfiguringProjectId(null);
                              setConfigProjectName('');
                              setConfigProjectPath('');
                            }}
                            className="px-4 py-2 text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors"
                          >
                            Cancel
                          </button>
                          <button
                            onClick={async () => {
                              setIsSavingConfig(true);
                              try {
                                // Only send path if it changed
                                const pathChanged = configProjectPath.trim() !== project.path;
                                await felixApi.updateProject(project.id, {
                                  name: configProjectName.trim() || undefined,
                                  path: pathChanged ? configProjectPath.trim() : undefined,
                                });
                                setSuccessMessage('Project configuration saved');
                                setConfiguringProjectId(null);
                                setConfigProjectName('');
                                setConfigProjectPath('');
                                fetchProjects();
                              } catch (err) {
                                setProjectsError(err instanceof Error ? err.message : 'Failed to save project configuration');
                              } finally {
                                setIsSavingConfig(false);
                              }
                            }}
                            disabled={isSavingConfig}
                            className={`px-4 py-2 text-[10px] font-bold rounded-lg transition-all flex items-center gap-2 ${
                              !isSavingConfig
                                ? 'bg-[var(--accent-secondary)] text-white hover:bg-[var(--accent-primary)]'
                                : 'theme-bg-surface theme-text-muted cursor-not-allowed'
                            }`}
                          >
                            {isSavingConfig ? (
                              <>
                                <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                Saving...
                              </>
                            ) : (
                              'Save'
                            )}
                          </button>
                        </div>
                      </div>
                    </div>
                  )}

                  {/* Unregister Confirmation */}
                  {showUnregisterConfirm === project.id && (
                    <div className="mt-4 pt-4 border-t border-[var(--border-default)]">
                      <div className="flex items-center justify-between">
                        <p className="text-xs text-[var(--status-warning)]">
                          Remove this project from Felix? Files will remain on disk.
                        </p>
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => setShowUnregisterConfirm(null)}
                            className="px-3 py-1.5 text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors"
                          >
                            Cancel
                          </button>
                          <button
                            onClick={async () => {
                              setUnregisteringId(project.id);
                              try {
                                await felixApi.unregisterProject(project.id);
                                setSuccessMessage('Project unregistered successfully');
                                setShowUnregisterConfirm(null);
                                fetchProjects();
                              } catch (err) {
                                setProjectsError(err instanceof Error ? err.message : 'Failed to unregister project');
                              } finally {
                                setUnregisteringId(null);
                              }
                            }}
                            disabled={unregisteringId === project.id}
                            className="px-3 py-1.5 text-[10px] font-bold bg-[var(--status-error)]/20 text-[var(--status-error)] rounded-lg hover:bg-[var(--status-error)]/30 transition-all flex items-center gap-2"
                          >
                            {unregisteringId === project.id ? (
                              <>
                                <div className="w-3 h-3 border-2 border-[var(--status-error)]/30 border-t-[var(--status-error)] rounded-full animate-spin" />
                                Removing...
                              </>
                            ) : (
                              'Confirm Unregister'
                            )}
                          </button>
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

  // Render the active category's settings
  const renderActiveSettings = () => {
    switch (activeCategory) {
      case 'general':
        return renderGeneralSettings();
      case 'agent':
        return renderAgentSettings();
      case 'paths':
        return renderPathsSettings();
      case 'advanced':
        return renderAdvancedSettings();
      case 'projects':
        return renderProjectsSettings();
      default:
        return null;
    }
  };

  // Loading state
  if (loading) {
    return (
      <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
        <div className="flex-1 flex flex-col items-center justify-center">
          <div className="w-8 h-8 border-2 border-[var(--border-default)] border-t-felix-500 rounded-full animate-spin mb-4" />
          <span className="text-xs font-mono theme-text-muted uppercase">Loading settings...</span>
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
            <svg className="w-8 h-8 text-[var(--status-error)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          </div>
          <h3 className="text-sm font-bold theme-text-tertiary mb-2">Failed to Load Settings</h3>
          <p className="text-xs theme-text-muted max-w-md mb-4">{error}</p>
          <button 
            onClick={onBack}
            className="px-4 py-2 text-xs font-bold text-[var(--accent-primary)] border border-[var(--accent-primary)]/20 rounded-lg hover:bg-[var(--accent-primary)]/10 transition-colors"
          >
            ← Back to Projects
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex theme-bg-base overflow-hidden">
      {/* Left Sidebar - Categories Navigation */}
      <div className="w-64 border-r border-[var(--border-default)] flex flex-col theme-bg-deep flex-shrink-0" style={{ backgroundColor: 'var(--bg-deep)' }}>
        {/* Sidebar Header */}
        <div className="h-14 border-b border-[var(--border-default)] flex items-center px-5">
          <button
            onClick={onBack}
            className="p-1.5 hover:bg-[var(--hover-bg)] rounded-lg transition-all theme-text-muted hover:theme-text-secondary mr-3"
            title="Back to Projects"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <span className="text-xs font-bold theme-text-tertiary uppercase tracking-widest">Settings</span>
        </div>

        {/* Categories List */}
        <div className="flex-1 p-3 space-y-1 overflow-y-auto custom-scrollbar">
          {CATEGORIES.map((category) => (
            <button
              key={category.id}
              onClick={() => setActiveCategory(category.id)}
              className={`w-full flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-all ${
                activeCategory === category.id
                  ? 'bg-[var(--selected-bg)] text-[var(--accent-primary)] border border-[var(--accent-primary)]/20'
                  : 'theme-text-tertiary hover:theme-text-secondary hover:bg-[var(--hover-bg)] border border-transparent'
              }`}
            >
              <div className={`flex-shrink-0 ${activeCategory === category.id ? 'text-[var(--accent-primary)]' : 'theme-text-muted'}`}>
                {category.icon}
              </div>
              <div className="min-w-0">
                <span className="block text-sm font-medium">{category.label}</span>
                <span className="block text-[10px] theme-text-muted truncate">{category.description}</span>
              </div>
            </button>
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
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top Bar with Save Controls */}
        <div className="h-14 border-b border-[var(--border-default)] flex items-center px-6 justify-between backdrop-blur flex-shrink-0" style={{ backgroundColor: 'var(--bg-base)', opacity: 0.95 }}>
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
              <button
                onClick={handleReset}
                className="px-3 py-1.5 text-[10px] font-bold theme-text-muted hover:theme-text-secondary transition-colors"
              >
                Discard
              </button>
            )}
            <button
              onClick={handleSave}
              disabled={saving || !hasChanges || Object.keys(validationErrors).length > 0}
              className={`px-4 py-1.5 text-[10px] font-bold rounded-lg transition-all flex items-center gap-2 ${
                hasChanges && Object.keys(validationErrors).length === 0
                  ? 'bg-[var(--accent-secondary)] text-white hover:bg-[var(--accent-primary)]'
                  : 'theme-bg-surface theme-text-muted cursor-not-allowed'
              }`}
            >
              {saving ? (
                <>
                  <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Saving...
                </>
              ) : (
                'Save Changes'
              )}
            </button>
          </div>
        </div>

        {/* Success/Error Messages */}
        {(successMessage || error) && (
          <div className={`px-6 py-3 text-xs flex items-center gap-2 ${
            successMessage ? 'bg-[var(--status-success)]/10 text-[var(--status-success)]' : 'bg-[var(--status-error)]/10 text-[var(--status-error)]'
          }`}>
            {successMessage ? (
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" />
              </svg>
            ) : (
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            )}
            {successMessage || error}
          </div>
        )}

        {/* Settings Content */}
        <div className="flex-1 overflow-y-auto custom-scrollbar p-8">
          <div className="max-w-2xl">
            {renderActiveSettings()}
          </div>
        </div>
      </div>
    </div>
  );
};

export default SettingsScreen;

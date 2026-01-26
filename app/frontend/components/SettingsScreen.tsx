import React, { useState, useEffect, useCallback } from 'react';
import { felixApi, FelixConfig } from '../services/felixApi';
import { IconFelix } from './Icons';

interface SettingsScreenProps {
  projectId: string;
  onBack: () => void;
}

type SettingsCategory = 'general' | 'agent' | 'paths' | 'advanced';

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
];

const SettingsScreen: React.FC<SettingsScreenProps> = ({ projectId, onBack }) => {
  const [activeCategory, setActiveCategory] = useState<SettingsCategory>('general');
  const [config, setConfig] = useState<FelixConfig | null>(null);
  const [originalConfig, setOriginalConfig] = useState<FelixConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<Record<string, string>>({});

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
        console.error('Failed to fetch config:', err);
        setError(err instanceof Error ? err.message : 'Failed to load configuration');
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
            <h3 className="text-lg font-bold text-slate-200">General Settings</h3>
            <p className="text-xs text-slate-500 mt-1">Basic Felix configuration options</p>
          </div>
          <button
            onClick={handleResetCategory}
            className="text-[10px] font-bold text-slate-500 hover:text-slate-300 transition-colors px-3 py-1.5 rounded-lg hover:bg-slate-800/50"
          >
            Reset to Defaults
          </button>
        </div>

        {/* Max Iterations */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <label className="block text-sm font-bold text-slate-300 mb-2">
            Max Iterations
          </label>
          <input
            type="number"
            min="1"
            value={config.executor.max_iterations}
            onChange={(e) => handleExecutorChange('max_iterations', parseInt(e.target.value) || 0)}
            className={`w-full bg-[#0d1117] border rounded-lg px-4 py-2.5 text-sm text-slate-300 outline-none transition-all ${
              validationErrors.max_iterations 
                ? 'border-red-500/50 focus:border-red-500'
                : 'border-slate-700/50 focus:border-felix-500/50 focus:ring-1 focus:ring-felix-500/20'
            }`}
          />
          {validationErrors.max_iterations && (
            <p className="mt-1.5 text-[10px] text-red-400">{validationErrors.max_iterations}</p>
          )}
          <p className="mt-2 text-[11px] text-slate-500">
            Maximum number of iterations the agent will run before stopping
          </p>
        </div>

        {/* Default Mode */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <label className="block text-sm font-bold text-slate-300 mb-2">
            Default Mode
          </label>
          <select
            value={config.executor.default_mode}
            onChange={(e) => handleExecutorChange('default_mode', e.target.value)}
            className={`w-full bg-[#0d1117] border rounded-lg px-4 py-2.5 text-sm text-slate-300 outline-none transition-all cursor-pointer ${
              validationErrors.default_mode
                ? 'border-red-500/50'
                : 'border-slate-700/50 focus:border-felix-500/50 focus:ring-1 focus:ring-felix-500/20'
            }`}
          >
            <option value="planning">Planning</option>
            <option value="building">Building</option>
          </select>
          {validationErrors.default_mode && (
            <p className="mt-1.5 text-[10px] text-red-400">{validationErrors.default_mode}</p>
          )}
          <p className="mt-2 text-[11px] text-slate-500">
            Mode the agent starts in when a run begins
          </p>
        </div>

        {/* Auto Transition */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <div className="flex items-center justify-between">
            <div>
              <label className="block text-sm font-bold text-slate-300">
                Auto Transition
              </label>
              <p className="text-[11px] text-slate-500 mt-1">
                Automatically switch from planning to building mode when plan is complete
              </p>
            </div>
            <button
              onClick={() => handleExecutorChange('auto_transition', !config.executor.auto_transition)}
              className={`w-12 h-6 rounded-full transition-all relative flex-shrink-0 ${
                config.executor.auto_transition 
                  ? 'bg-felix-600' 
                  : 'bg-slate-700'
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
            <h3 className="text-lg font-bold text-slate-200">Agent Settings</h3>
            <p className="text-xs text-slate-500 mt-1">Agent execution preferences and policies</p>
          </div>
          <button
            onClick={handleResetCategory}
            className="text-[10px] font-bold text-slate-500 hover:text-slate-300 transition-colors px-3 py-1.5 rounded-lg hover:bg-slate-800/50"
          >
            Reset to Defaults
          </button>
        </div>

        {/* Executable */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <label className="block text-sm font-bold text-slate-300 mb-2">
            Executable Path
          </label>
          <input
            type="text"
            value={config.agent.executable}
            onChange={(e) => handleAgentChange('executable', e.target.value)}
            className="w-full bg-[#0d1117] border border-slate-700/50 rounded-lg px-4 py-2.5 text-sm text-slate-300 font-mono outline-none transition-all focus:border-felix-500/50 focus:ring-1 focus:ring-felix-500/20"
          />
          <p className="mt-2 text-[11px] text-slate-500">
            Path to the agent executable (e.g., droid, python)
          </p>
        </div>

        {/* Arguments */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <label className="block text-sm font-bold text-slate-300 mb-2">
            Arguments
          </label>
          <input
            type="text"
            value={config.agent.args.join(' ')}
            onChange={(e) => handleAgentChange('args', e.target.value.split(' ').filter(Boolean))}
            className="w-full bg-[#0d1117] border border-slate-700/50 rounded-lg px-4 py-2.5 text-sm text-slate-300 font-mono outline-none transition-all focus:border-felix-500/50 focus:ring-1 focus:ring-felix-500/20"
          />
          <p className="mt-2 text-[11px] text-slate-500">
            Command-line arguments passed to the agent executable (space-separated)
          </p>
        </div>

        {/* Working Directory */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <label className="block text-sm font-bold text-slate-300 mb-2">
            Working Directory
          </label>
          <input
            type="text"
            value={config.agent.working_directory}
            onChange={(e) => handleAgentChange('working_directory', e.target.value)}
            className="w-full bg-[#0d1117] border border-slate-700/50 rounded-lg px-4 py-2.5 text-sm text-slate-300 font-mono outline-none transition-all focus:border-felix-500/50 focus:ring-1 focus:ring-felix-500/20"
          />
          <p className="mt-2 text-[11px] text-slate-500">
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
          <h3 className="text-lg font-bold text-slate-200">Paths</h3>
          <p className="text-xs text-slate-500 mt-1">File and directory locations (read-only)</p>
        </div>

        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl overflow-hidden">
          <div className="divide-y divide-slate-800/60">
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm text-slate-300">Specs Directory</span>
                <p className="text-[10px] text-slate-600 mt-0.5">Location of specification files</p>
              </div>
              <code className="text-xs font-mono text-slate-400 bg-slate-800/50 px-3 py-1.5 rounded-lg">{config.paths.specs}</code>
            </div>
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm text-slate-300">AGENTS.md</span>
                <p className="text-[10px] text-slate-600 mt-0.5">Agent instructions file</p>
              </div>
              <code className="text-xs font-mono text-slate-400 bg-slate-800/50 px-3 py-1.5 rounded-lg">{config.paths.agents}</code>
            </div>
            <div className="flex justify-between items-center px-5 py-4">
              <div>
                <span className="text-sm text-slate-300">Runs Directory</span>
                <p className="text-[10px] text-slate-600 mt-0.5">Location of run artifacts</p>
              </div>
              <code className="text-xs font-mono text-slate-400 bg-slate-800/50 px-3 py-1.5 rounded-lg">{config.paths.runs}</code>
            </div>
          </div>
        </div>

        <div className="bg-amber-500/5 border border-amber-500/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <svg className="w-4 h-4 text-amber-400 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <p className="text-xs text-amber-400/80">
              Path settings are read-only. Edit <code className="bg-amber-500/10 px-1 rounded">felix/config.json</code> directly to modify these values.
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
            <h3 className="text-lg font-bold text-slate-200">Advanced Settings</h3>
            <p className="text-xs text-slate-500 mt-1">Developer options and debug settings</p>
          </div>
          <button
            onClick={handleResetCategory}
            className="text-[10px] font-bold text-slate-500 hover:text-slate-300 transition-colors px-3 py-1.5 rounded-lg hover:bg-slate-800/50"
          >
            Reset to Defaults
          </button>
        </div>

        {/* Backpressure Section */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <div className="flex items-center justify-between mb-4">
            <div>
              <label className="block text-sm font-bold text-slate-300">
                Enable Backpressure
              </label>
              <p className="text-[11px] text-slate-500 mt-1">
                Run lint/test/build commands between agent iterations
              </p>
            </div>
            <button
              onClick={() => handleBackpressureChange('enabled', !config.backpressure.enabled)}
              className={`w-12 h-6 rounded-full transition-all relative flex-shrink-0 ${
                config.backpressure.enabled 
                  ? 'bg-felix-600' 
                  : 'bg-slate-700'
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
            <div className="space-y-4 pt-4 border-t border-slate-800/60">
              {/* Max Retries */}
              <div>
                <label className="block text-xs font-bold text-slate-400 mb-2">
                  Max Retries
                </label>
                <input
                  type="number"
                  min="0"
                  value={(config.backpressure as any).max_retries || 3}
                  onChange={(e) => handleBackpressureChange('max_retries' as any, parseInt(e.target.value) || 0)}
                  className={`w-full bg-[#0d1117] border rounded-lg px-4 py-2.5 text-sm text-slate-300 outline-none transition-all ${
                    validationErrors.max_retries
                      ? 'border-red-500/50 focus:border-red-500'
                      : 'border-slate-700/50 focus:border-felix-500/50'
                  }`}
                />
                {validationErrors.max_retries && (
                  <p className="mt-1 text-[10px] text-red-400">{validationErrors.max_retries}</p>
                )}
                <p className="mt-1.5 text-[10px] text-slate-600">
                  Number of retry attempts for failed backpressure commands
                </p>
              </div>

              {/* Commands (read-only display) */}
              {config.backpressure.commands.length > 0 && (
                <div>
                  <label className="block text-xs font-bold text-slate-400 mb-2">
                    Validation Commands
                  </label>
                  <div className="bg-[#0d1117] border border-slate-700/50 rounded-lg p-4 space-y-2">
                    {config.backpressure.commands.map((cmd, index) => (
                      <div key={index} className="flex items-center gap-2">
                        <span className="text-[9px] font-mono text-slate-600 w-4">{index + 1}.</span>
                        <code className="text-xs font-mono text-slate-400">{cmd}</code>
                      </div>
                    ))}
                  </div>
                  <p className="mt-1.5 text-[10px] text-slate-600">
                    Edit felix/config.json directly to modify commands
                  </p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Executor Mode (read-only info) */}
        <div className="bg-[#161b22] border border-slate-800/60 rounded-xl p-5">
          <div className="flex justify-between items-center">
            <div>
              <label className="block text-sm font-bold text-slate-300">
                Executor Mode
              </label>
              <p className="text-[11px] text-slate-500 mt-1">
                How the agent executor runs (local or remote)
              </p>
            </div>
            <span className="text-xs font-mono text-slate-400 bg-slate-800/50 px-3 py-1.5 rounded-lg uppercase">
              {config.executor.mode}
            </span>
          </div>
        </div>

        {/* Config Version */}
        <div className="text-center text-[10px] font-mono text-slate-600 pt-4">
          Config Version: {config.version}
        </div>
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
      default:
        return null;
    }
  };

  // Loading state
  if (loading) {
    return (
      <div className="flex-1 flex flex-col bg-[#0d1117] overflow-hidden">
        <div className="flex-1 flex flex-col items-center justify-center">
          <div className="w-8 h-8 border-2 border-slate-600/30 border-t-felix-500 rounded-full animate-spin mb-4" />
          <span className="text-xs font-mono text-slate-600 uppercase">Loading settings...</span>
        </div>
      </div>
    );
  }

  // Error state (no config)
  if (error && !config) {
    return (
      <div className="flex-1 flex flex-col bg-[#0d1117] overflow-hidden">
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
            <svg className="w-8 h-8 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          </div>
          <h3 className="text-sm font-bold text-slate-400 mb-2">Failed to Load Settings</h3>
          <p className="text-xs text-slate-600 max-w-md mb-4">{error}</p>
          <button 
            onClick={onBack}
            className="px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
          >
            ← Back to Projects
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex bg-[#0d1117] overflow-hidden">
      {/* Left Sidebar - Categories Navigation */}
      <div className="w-64 border-r border-slate-800/60 flex flex-col bg-[#0a0c10]/40 flex-shrink-0">
        {/* Sidebar Header */}
        <div className="h-14 border-b border-slate-800/60 flex items-center px-5">
          <button
            onClick={onBack}
            className="p-1.5 hover:bg-slate-800 rounded-lg transition-all text-slate-500 hover:text-slate-300 mr-3"
            title="Back to Projects"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <span className="text-xs font-bold text-slate-400 uppercase tracking-widest">Settings</span>
        </div>

        {/* Categories List */}
        <div className="flex-1 p-3 space-y-1 overflow-y-auto custom-scrollbar">
          {CATEGORIES.map((category) => (
            <button
              key={category.id}
              onClick={() => setActiveCategory(category.id)}
              className={`w-full flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-all ${
                activeCategory === category.id
                  ? 'bg-felix-600/10 text-felix-400 border border-felix-500/20'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50 border border-transparent'
              }`}
            >
              <div className={`flex-shrink-0 ${activeCategory === category.id ? 'text-felix-400' : 'text-slate-500'}`}>
                {category.icon}
              </div>
              <div className="min-w-0">
                <span className="block text-sm font-medium">{category.label}</span>
                <span className="block text-[10px] text-slate-600 truncate">{category.description}</span>
              </div>
            </button>
          ))}
        </div>

        {/* Sidebar Footer */}
        <div className="p-4 border-t border-slate-800/60">
          <div className="flex items-center gap-2 text-[10px] text-slate-600">
            <IconFelix className="w-4 h-4 text-felix-500/50" />
            <span className="font-mono">felix/config.json</span>
          </div>
        </div>
      </div>

      {/* Right Panel - Settings Content */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top Bar with Save Controls */}
        <div className="h-14 border-b border-slate-800/60 flex items-center px-6 justify-between bg-[#0d1117]/95 backdrop-blur flex-shrink-0">
          <div className="flex items-center gap-3">
            {hasChanges && (
              <div className="flex items-center gap-2 text-[10px] text-amber-400">
                <div className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
                <span className="font-mono uppercase">Unsaved changes</span>
              </div>
            )}
          </div>

          <div className="flex items-center gap-3">
            {hasChanges && (
              <button
                onClick={handleReset}
                className="px-3 py-1.5 text-[10px] font-bold text-slate-500 hover:text-slate-300 transition-colors"
              >
                Discard
              </button>
            )}
            <button
              onClick={handleSave}
              disabled={saving || !hasChanges || Object.keys(validationErrors).length > 0}
              className={`px-4 py-1.5 text-[10px] font-bold rounded-lg transition-all flex items-center gap-2 ${
                hasChanges && Object.keys(validationErrors).length === 0
                  ? 'bg-felix-600 text-white hover:bg-felix-500'
                  : 'bg-slate-800 text-slate-500 cursor-not-allowed'
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
            successMessage ? 'bg-emerald-500/10 text-emerald-400' : 'bg-red-500/10 text-red-400'
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

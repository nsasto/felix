/**
 * ProjectSelector Component
 * Displays a list of registered projects with status indicators.
 * Allows project switching and provides register/unregister actions.
 */
import React, { useState, useEffect } from 'react';
import { felixApi, Project, ProjectDetails } from '../services/felixApi';
import { IconPlus, IconFelix } from './Icons';

// Project status color mapping
const getStatusColor = (status: string | null): string => {
  switch (status?.toLowerCase()) {
    case 'running':
      return 'bg-felix-500 animate-pulse';
    case 'complete':
    case 'done':
      return 'bg-emerald-500';
    case 'blocked':
    case 'error':
      return 'bg-red-500';
    case 'planned':
      return 'bg-amber-500';
    default:
      return 'bg-slate-600';
  }
};

// Folder icon component
const IconFolder = ({ className = "w-5 h-5" }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
  </svg>
);

// Trash icon for unregister
const IconTrash = ({ className = "w-4 h-4" }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <polyline points="3 6 5 6 21 6" />
    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
    <line x1="10" y1="11" x2="10" y2="17" />
    <line x1="14" y1="11" x2="14" y2="17" />
  </svg>
);

// Close icon
const IconX = ({ className = "w-4 h-4" }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
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
  const [projectDetails, setProjectDetails] = useState<Map<string, ProjectDetails>>(new Map());
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isRegisterOpen, setIsRegisterOpen] = useState(false);
  const [registerPath, setRegisterPath] = useState('');
  const [registerName, setRegisterName] = useState('');
  const [isRegistering, setIsRegistering] = useState(false);
  const [confirmUnregister, setConfirmUnregister] = useState<string | null>(null);

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
            console.warn(`Failed to load details for project ${project.id}:`, e);
          }
        })
      );
      setProjectDetails(detailsMap);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load projects');
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
      setRegisterPath('');
      setRegisterName('');
      
      // Auto-select the new project
      onSelectProject(newProject.id, details);
      onProjectsChange?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to register project');
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
      setError(e instanceof Error ? e.message : 'Failed to unregister project');
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
    const parts = project.path.replace(/\\/g, '/').split('/');
    return parts[parts.length - 1] || project.path;
  };

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="h-12 border-b flex items-center px-4 justify-between" style={{ borderColor: 'var(--border-default)' }}>
        <div className="flex items-center gap-2">
          <IconFelix className="w-4 h-4" style={{ color: 'var(--accent-primary)' }} />
          <span className="text-[10px] font-bold uppercase tracking-widest" style={{ color: 'var(--text-muted)' }}>
            Projects
          </span>
        </div>
        <button
          onClick={() => setIsRegisterOpen(true)}
          className="p-1.5 rounded-lg transition-all"
          style={{ color: 'var(--text-muted)' }}
          onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = 'var(--hover-bg)'; e.currentTarget.style.color = 'var(--accent-primary)'; }}
          onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = 'transparent'; e.currentTarget.style.color = 'var(--text-muted)'; }}
          title="Register Project"
        >
          <IconPlus className="w-4 h-4" />
        </button>
      </div>

      {/* Error display */}
      {error && (
        <div className="mx-3 mt-3 p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs" style={{ color: 'var(--status-error)' }}>
          {error}
          <button
            onClick={() => setError(null)}
            className="ml-2 opacity-80 hover:opacity-100"
            style={{ color: 'var(--status-error)' }}
          >
            ×
          </button>
        </div>
      )}

      {/* Project list */}
      <div className="flex-1 overflow-y-auto custom-scrollbar p-3 space-y-1">
        {isLoading ? (
          <div className="flex items-center justify-center py-8 text-xs" style={{ color: 'var(--text-muted)' }}>
            <IconFelix className="w-5 h-5 animate-spin mr-2" />
            Loading projects...
          </div>
        ) : projects.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center" style={{ color: 'var(--text-muted)' }}>
            <IconFolder className="w-8 h-8 mb-3 opacity-50" />
            <p className="text-xs mb-1">No projects registered</p>
            <p className="text-[10px] opacity-60">
              Click + to register a project
            </p>
          </div>
        ) : (
          projects.map((project) => {
            const details = projectDetails.get(project.id);
            const isSelected = selectedProjectId === project.id;
            
            return (
              <div key={project.id} className="relative group">
                <button
                  onClick={() => handleProjectClick(project)}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs transition-all border"
                  style={{
                    backgroundColor: isSelected ? 'var(--selected-bg)' : 'transparent',
                    color: isSelected ? 'var(--accent-primary)' : 'var(--text-muted)',
                    borderColor: isSelected ? 'var(--accent-primary)' : 'transparent',
                    borderOpacity: isSelected ? 0.2 : 0,
                    boxShadow: isSelected ? 'var(--shadow-md)' : 'none',
                  }}
                  onMouseEnter={(e) => {
                    if (!isSelected) {
                      e.currentTarget.style.backgroundColor = 'var(--hover-bg)';
                      e.currentTarget.style.color = 'var(--text-secondary)';
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (!isSelected) {
                      e.currentTarget.style.backgroundColor = 'transparent';
                      e.currentTarget.style.color = 'var(--text-muted)';
                    }
                  }}
                >
                  <div className="relative">
                    <IconFolder className="w-4 h-4" />
                    {details && (
                      <div
                        className={`absolute -bottom-0.5 -right-0.5 w-2 h-2 rounded-full ${getStatusColor(
                          details.status
                        )}`}
                      />
                    )}
                  </div>
                  <div className="flex-1 flex flex-col items-start min-w-0">
                    <span className="truncate font-medium w-full text-left">
                      {getProjectName(project)}
                    </span>
                    {details && (
                      <span className="text-[9px] opacity-40 font-mono">
                        {details.spec_count} specs
                        {details.has_plan && ' • plan'}
                        {details.status && ` • ${details.status}`}
                      </span>
                    )}
                  </div>
                </button>
                
                {/* Unregister button */}
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setConfirmUnregister(project.id);
                  }}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 opacity-0 group-hover:opacity-100 hover:bg-red-500/10 rounded-lg transition-all"
                  style={{ color: 'var(--text-muted)' }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = 'var(--status-error)'; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; }}
                  title="Unregister project"
                >
                  <IconTrash className="w-3.5 h-3.5" />
                </button>
              </div>
            );
          })
        )}
      </div>

      {/* Refresh button */}
      <div className="p-3 border-t" style={{ borderColor: 'var(--border-default)' }}>
        <button
          onClick={loadProjects}
          disabled={isLoading}
          className="w-full py-2 text-[10px] font-mono transition-colors uppercase tracking-wider disabled:opacity-50"
          style={{ color: 'var(--text-muted)' }}
          onMouseEnter={(e) => { e.currentTarget.style.color = 'var(--text-tertiary)'; }}
          onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; }}
        >
          {isLoading ? 'Loading...' : 'Refresh Projects'}
        </button>
      </div>

      {/* Register Project Dialog */}
      {isRegisterOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="rounded-2xl shadow-2xl w-[420px] overflow-hidden" style={{ backgroundColor: 'var(--bg-base)', border: '1px solid var(--border-default)' }}>
            {/* Dialog header */}
            <div className="h-12 border-b flex items-center justify-between px-4" style={{ borderColor: 'var(--border-default)' }}>
              <div className="flex items-center gap-2">
                <IconFolder className="w-4 h-4" style={{ color: 'var(--accent-primary)' }} />
                <span className="text-xs font-bold" style={{ color: 'var(--text-secondary)' }}>
                  Register Project
                </span>
              </div>
              <button
                onClick={() => setIsRegisterOpen(false)}
                className="p-1.5 rounded-lg transition-all"
                style={{ color: 'var(--text-muted)' }}
                onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = 'var(--hover-bg)'; e.currentTarget.style.color = 'var(--text-secondary)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = 'transparent'; e.currentTarget.style.color = 'var(--text-muted)'; }}
              >
                <IconX className="w-4 h-4" />
              </button>
            </div>

            {/* Dialog body */}
            <div className="p-4 space-y-4">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider mb-2" style={{ color: 'var(--text-muted)' }}>
                  Project Path *
                </label>
                <input
                  type="text"
                  value={registerPath}
                  onChange={(e) => setRegisterPath(e.target.value)}
                  placeholder="C:\path\to\your\project"
                  className="w-full rounded-xl px-4 py-2.5 text-sm focus:ring-1 focus:ring-felix-500 transition-all outline-none"
                  style={{ 
                    backgroundColor: 'var(--bg-elevated)', 
                    border: '1px solid var(--border-muted)',
                    color: 'var(--text-secondary)'
                  }}
                />
                <p className="mt-1.5 text-[9px]" style={{ color: 'var(--text-muted)' }}>
                  Enter the absolute path to your Felix project directory
                </p>
              </div>

              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider mb-2" style={{ color: 'var(--text-muted)' }}>
                  Display Name (optional)
                </label>
                <input
                  type="text"
                  value={registerName}
                  onChange={(e) => setRegisterName(e.target.value)}
                  placeholder="My Project"
                  className="w-full rounded-xl px-4 py-2.5 text-sm focus:ring-1 focus:ring-felix-500 transition-all outline-none"
                  style={{ 
                    backgroundColor: 'var(--bg-elevated)', 
                    border: '1px solid var(--border-muted)',
                    color: 'var(--text-secondary)'
                  }}
                />
              </div>

              {error && (
                <div className="p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs" style={{ color: 'var(--status-error)' }}>
                  {error}
                </div>
              )}
            </div>

            {/* Dialog footer */}
            <div className="h-14 border-t flex items-center justify-end gap-3 px-4" style={{ borderColor: 'var(--border-default)' }}>
              <button
                onClick={() => setIsRegisterOpen(false)}
                className="px-4 py-2 text-xs font-medium transition-colors"
                style={{ color: 'var(--text-muted)' }}
                onMouseEnter={(e) => { e.currentTarget.style.color = 'var(--text-secondary)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; }}
              >
                Cancel
              </button>
              <button
                onClick={handleRegister}
                disabled={!registerPath.trim() || isRegistering}
                className="px-4 py-2 bg-felix-600 text-white text-xs font-bold rounded-xl hover:bg-felix-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isRegistering ? 'Registering...' : 'Register'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirm Unregister Dialog */}
      {confirmUnregister && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="rounded-2xl shadow-2xl w-[380px] overflow-hidden" style={{ backgroundColor: 'var(--bg-base)', border: '1px solid var(--border-default)' }}>
            <div className="p-6 text-center">
              <div className="w-12 h-12 bg-red-500/10 rounded-full flex items-center justify-center mx-auto mb-4">
                <IconTrash className="w-6 h-6" style={{ color: 'var(--status-error)' }} />
              </div>
              <h3 className="text-sm font-bold mb-2" style={{ color: 'var(--text-primary)' }}>
                Unregister Project?
              </h3>
              <p className="text-xs mb-6" style={{ color: 'var(--text-muted)' }}>
                This will remove the project from Felix. Your files will not be
                deleted.
              </p>
              <div className="flex gap-3 justify-center">
                <button
                  onClick={() => setConfirmUnregister(null)}
                  className="px-4 py-2 text-xs font-medium transition-colors"
                  style={{ color: 'var(--text-muted)' }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = 'var(--text-secondary)'; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; }}
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

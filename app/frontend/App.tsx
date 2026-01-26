
import React, { useState, useEffect, useRef, useMemo } from 'react';
import { 
  Task,
  UIState,
  MarkdownAsset
} from './types';
import { felixApi, ProjectDetails } from './services/felixApi';
import { 
  IconFelix, 
  IconSearch, 
  IconTerminal,
  IconFileCode,
  IconFileText,
  IconCpu,
  IconKanban,
  IconPlus 
} from './components/Icons';
import ProjectSelector from './components/ProjectSelector';
import RequirementsKanban from './components/RequirementsKanban';
import AgentControls from './components/AgentControls';
import RunArtifactViewer from './components/RunArtifactViewer';
import SpecsEditor from './components/SpecsEditor';
import RunMonitor from './components/RunMonitor';
import ConfigPanel from './components/ConfigPanel';
import PlanViewer from './components/PlanViewer';
import SettingsScreen from './components/SettingsScreen';
import { marked } from 'marked';

const INITIAL_TASKS: Task[] = [
  { id: 't1', title: 'Implement Auth Layer', description: 'Create JWT based authentication service.', status: 'todo', priority: 'high', tags: ['security', 'backend'] },
  { id: 't2', title: 'Felix UI Redesign', description: 'Switch to Kanban-first workflow.', status: 'in-progress', priority: 'medium', tags: ['frontend', 'ux'] },
  { id: 't3', title: 'Setup Gemini 2.5 API', description: 'Integrate native audio and multi-modal support.', status: 'completed', priority: 'high', tags: ['ai', 'infra'] },
  { id: 't4', title: 'Database Migration', description: 'Migrate legacy SQL to optimized schema.', status: 'backlog', priority: 'low', tags: ['data'] },
];

const INITIAL_ASSETS: MarkdownAsset[] = [
  { id: 'a1', name: 'README.md', content: '# Project Felix\n\nFelix is a high-performance workspace orchestrator designed to bridge the gap between high-level project management and code execution.\n\n## Features\n- **AI Orchestration**: Built with Gemini 3 for deep reasoning.\n- **Kanban Board**: Real-time status tracking.\n- **Asset Management**: Integrated Markdown orchestration.\n\n```javascript\nconst felix = new Orchestrator();\nfelix.sync();\n```', lastEdited: Date.now() },
  { id: 'a2', name: 'ROADMAP.md', content: '# Product Roadmap\n\n### Current Milestone: Alpha\n- [x] Base architecture definition\n- [x] Initial UI styling system\n- [ ] Multi-document orchestration\n- [ ] Native audio feedback engine\n\n### Upcoming: Beta\n- [ ] Real-time collaborative sessions\n- [ ] Third-party plugin SDK', lastEdited: Date.now() },
  { id: 'a3', name: 'ARCH.md', content: '# Architecture Overview\n\n| Component | Responsibility | Tech |\n| :--- | :--- | :--- |\n| UI Layer | React / Tailwind | Frontend |\n| Reasoning | Gemini 3 Pro | Intelligence |\n| Storage | Cloud Sync | Data |\n\n> "Felix is not just a tool, it is a collaborator in the engineering process."', lastEdited: Date.now() },
];

// Extended UI state to include projects, config, plan, and settings views
type ExtendedUIState = UIState | 'projects' | 'config' | 'plan' | 'settings';

const App: React.FC = () => {
  const [tasks, setTasks] = useState<Task[]>(INITIAL_TASKS);
  const [assets, setAssets] = useState<MarkdownAsset[]>(INITIAL_ASSETS);
  const [uiState, setUiState] = useState<ExtendedUIState>('projects'); // Start with projects view
  const [selectedAssetId, setSelectedAssetId] = useState<string>(INITIAL_ASSETS[0].id);
  const [assetViewMode, setAssetViewMode] = useState<'edit' | 'preview' | 'split'>('split');
  const [parsedHtml, setParsedHtml] = useState<string>('');
  
  // Project management state
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);
  const [selectedProject, setSelectedProject] = useState<ProjectDetails | null>(null);
  const [backendStatus, setBackendStatus] = useState<'unknown' | 'connected' | 'disconnected'>('unknown');
  
  // Run artifact viewer state
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);

  // Check backend status on mount
  useEffect(() => {
    const checkBackend = async () => {
      try {
        await felixApi.healthCheck();
        setBackendStatus('connected');
      } catch (e) {
        setBackendStatus('disconnected');
        console.warn('Backend not available:', e);
      }
    };
    checkBackend();
    
    // Periodically check backend status
    const interval = setInterval(checkBackend, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleSelectProject = (projectId: string, details: ProjectDetails) => {
    setSelectedProjectId(projectId);
    setSelectedProject(details);
    // Switch to kanban view after selecting a project
    if (uiState === 'projects') {
      setUiState('kanban');
    }
  };

  const editorRef = useRef<HTMLTextAreaElement>(null);
  const activeAsset = useMemo(() => assets.find(a => a.id === selectedAssetId) || assets[0], [assets, selectedAssetId]);

  // Reliable Markdown parsing effect
  useEffect(() => {
    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        // marked.parse can be sync or async depending on options; await handles both
        const result = await marked.parse(activeAsset.content || '');
        if (isMounted) setParsedHtml(result);
      } catch (err) {
        console.error("Markdown rendering error:", err);
        if (isMounted) setParsedHtml(`<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`);
      }
    };

    const timeout = setTimeout(parseMarkdown, 50); // Small debounce for smoother typing
    return () => { 
      isMounted = false; 
      clearTimeout(timeout); 
    };
  }, [activeAsset.content]);

  const updateAssetContent = (id: string, newContent: string) => {
    setAssets(prev => prev.map(a => a.id === id ? { ...a, content: newContent, lastEdited: Date.now() } : a));
  };

  const insertFormatting = (prefix: string, suffix: string = '') => {
    if (!editorRef.current) return;
    const textarea = editorRef.current;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const text = textarea.value;
    const selectedText = text.substring(start, end);
    const newContent = text.substring(0, start) + prefix + selectedText + suffix + text.substring(end);
    
    updateAssetContent(activeAsset.id, newContent);
    
    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + prefix.length, end + prefix.length);
    }, 0);
  };

  const copyToClipboard = () => {
    navigator.clipboard.writeText(activeAsset.content);
    // Simple visual feedback could go here
  };

  const renderKanban = () => {
    const columns: { status: Task['status'], label: string }[] = [
      { status: 'backlog', label: 'Backlog' },
      { status: 'todo', label: 'Todo' },
      { status: 'in-progress', label: 'In Progress' },
      { status: 'completed', label: 'Completed' },
    ];

    return (
      <div className="flex-1 flex gap-6 p-8 overflow-x-auto custom-scrollbar bg-[#050608]">
        {columns.map(col => (
          <div key={col.status} className="flex-shrink-0 w-80 flex flex-col gap-4">
            <div className="flex items-center justify-between px-2">
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${
                  col.status === 'todo' ? 'bg-amber-500' : 
                  col.status === 'in-progress' ? 'bg-felix-500 animate-pulse' : 
                  col.status === 'completed' ? 'bg-emerald-500' : 'bg-slate-600'
                }`} />
                <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400">{col.label}</h3>
              </div>
              <span className="text-[10px] font-mono text-slate-600 bg-slate-900 px-1.5 py-0.5 rounded">
                {tasks.filter(t => t.status === col.status).length}
              </span>
            </div>
            
            <div className="flex-1 space-y-3">
              {tasks.filter(t => t.status === col.status).map(task => (
                <div 
                  key={task.id} 
                  className="bg-[#0d1117] border border-slate-800/60 p-4 rounded-xl hover:border-felix-600/40 transition-all cursor-pointer group shadow-lg shadow-black/20"
                >
                  <div className="flex justify-between items-start mb-2">
                    <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded uppercase ${
                      task.priority === 'high' ? 'bg-red-500/10 text-red-400 border border-red-500/20' : 
                      task.priority === 'medium' ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20' : 
                      'bg-slate-800 text-slate-400'
                    }`}>
                      {task.priority}
                    </span>
                    <button className="opacity-0 group-hover:opacity-100 p-1 hover:bg-slate-800 rounded transition-opacity">
                      <IconPlus className="w-3 h-3 text-slate-500" />
                    </button>
                  </div>
                  <h4 className="text-sm font-semibold text-slate-200 mb-1 group-hover:text-felix-400 transition-colors">{task.title}</h4>
                  <p className="text-[11px] text-slate-500 leading-relaxed mb-3 line-clamp-2">{task.description}</p>
                  <div className="flex flex-wrap gap-1.5">
                    {task.tags.map(tag => (
                      <span key={tag} className="text-[9px] font-mono text-slate-600 border border-slate-800 px-1 rounded hover:text-slate-400 transition-colors">#{tag}</span>
                    ))}
                  </div>
                </div>
              ))}
              <button className="w-full py-2 border border-dashed border-slate-800 rounded-xl text-[10px] text-slate-600 hover:border-slate-600 hover:text-slate-400 transition-all flex items-center justify-center gap-2 group">
                <IconPlus className="w-3 h-3 group-hover:scale-125 transition-transform" />
                Add Task
              </button>
            </div>
          </div>
        ))}
      </div>
    );
  };

  const renderCanvas = () => {
    return (
      <div className="flex-1 flex bg-[#0d1117] overflow-hidden">
        <div className="flex-1 flex flex-col border-r border-slate-800/60">
          <div className="h-12 border-b border-slate-800/60 flex items-center px-6 justify-between bg-[#0d1117]/80 backdrop-blur">
             <div className="flex items-center gap-3">
               <IconFileCode className="w-4 h-4 text-felix-400" />
               <span className="text-xs font-mono font-bold text-slate-400">workspace/felix-core/orchestrator.ts</span>
             </div>
             <div className="flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-emerald-500"></div>
                <span className="text-[10px] font-bold text-emerald-500 uppercase">Live Context Active</span>
             </div>
          </div>
          <div className="flex-1 p-8 font-mono text-sm leading-relaxed overflow-y-auto custom-scrollbar selection:bg-felix-500/30">
             <pre className="!bg-transparent !border-none !p-0">
{`// Felix Orchestrator Logic
import { Gemini } from '@google/genai';

export const analyzeWorkspace = async () => {
  const context = await loadFiles();
  const feedback = await Gemini.generate({
    prompt: 'Review architecture for bottlenecks',
    context
  });
  
  return feedback;
};

// @todo: Implement task-to-code mapping
export const executeTask = (taskId: string) => {
  console.log(\`Executing $\{taskId\}...\`);
};`}
             </pre>
          </div>
        </div>
      </div>
    );
  };

  const renderAssets = () => {
    return (
      <div className="flex-1 flex bg-[#0d1117] overflow-hidden">
        {/* Sub-nav Panel */}
        <div className="w-64 border-r border-slate-800/60 flex flex-col bg-[#0a0c10]/40 flex-shrink-0">
           <div className="h-12 border-b border-slate-800/60 flex items-center px-4">
              <span className="text-[10px] font-bold uppercase tracking-widest text-slate-500">Project Workspace</span>
           </div>
           <div className="p-3 space-y-1 overflow-y-auto custom-scrollbar">
              {assets.map(asset => (
                <button 
                  key={asset.id} 
                  onClick={() => { setSelectedAssetId(asset.id); }}
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs transition-all border ${selectedAssetId === asset.id ? 'bg-felix-600/10 text-felix-400 border-felix-500/20 shadow-lg shadow-felix-900/10' : 'text-slate-500 border-transparent hover:text-slate-300 hover:bg-slate-800/50'}`}
                >
                  <IconFileText className="w-4 h-4" />
                  <div className="flex flex-col items-start min-w-0">
                    <span className="truncate font-medium">{asset.name}</span>
                    <span className="text-[9px] opacity-40 font-mono">markdown</span>
                  </div>
                </button>
              ))}
              <button className="w-full flex items-center gap-2 px-3 py-2 rounded-xl text-xs text-slate-600 hover:text-slate-400 border border-dashed border-slate-800/60 mt-4 transition-all">
                <IconPlus className="w-3.5 h-3.5" />
                <span>New Resource</span>
              </button>
           </div>
        </div>

        {/* Integrated Orchestration Canvas */}
        <div className="flex-1 flex flex-col min-w-0 bg-[#0a0c10]/20">
           <div className="h-12 border-b border-slate-800/60 flex items-center px-4 justify-between bg-[#0d1117]/95 backdrop-blur z-20 flex-shrink-0">
              <div className="flex items-center gap-4">
                <div className="flex bg-slate-900 border border-slate-800 rounded-lg p-0.5 shadow-inner">
                  <button 
                    onClick={() => setAssetViewMode('edit')}
                    className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${assetViewMode === 'edit' ? 'bg-slate-800 text-felix-400 shadow-sm' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    SOURCE
                  </button>
                  <button 
                    onClick={() => setAssetViewMode('split')}
                    className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${assetViewMode === 'split' ? 'bg-slate-800 text-felix-400 shadow-sm' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    ORCHESTRATE
                  </button>
                  <button 
                    onClick={() => setAssetViewMode('preview')}
                    className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${assetViewMode === 'preview' ? 'bg-slate-800 text-felix-400 shadow-sm' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    PREVIEW
                  </button>
                </div>

                {(assetViewMode === 'edit' || assetViewMode === 'split') && (
                  <div className="flex items-center gap-0.5 border-l border-slate-800 pl-4">
                    <button onClick={() => insertFormatting('# ')} className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all" title="H1">
                      <span className="font-bold text-xs">H1</span>
                    </button>
                    <button onClick={() => insertFormatting('## ')} className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all" title="H2">
                      <span className="font-bold text-xs">H2</span>
                    </button>
                    <button onClick={() => insertFormatting('**', '**')} className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all" title="Bold">
                      <span className="font-bold text-xs uppercase">B</span>
                    </button>
                    <button onClick={() => insertFormatting('*', '*')} className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all" title="Italic">
                      <span className="italic text-xs font-serif font-bold uppercase">I</span>
                    </button>
                    <button onClick={() => insertFormatting('- ')} className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all" title="List">
                      <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
                    </button>
                    <button onClick={() => insertFormatting('`', '`')} className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all" title="Code">
                      <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M16 18l6-6-6-6M8 6l-6 6 6 6" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
                    </button>
                  </div>
                )}
              </div>
              
              <div className="flex items-center gap-4">
                <button 
                  onClick={copyToClipboard}
                  className="text-[10px] font-bold text-slate-500 hover:text-felix-400 transition-colors uppercase tracking-widest flex items-center gap-2"
                >
                  <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
                  Copy Raw
                </button>
                <div className="h-4 w-px bg-slate-800"></div>
                <div className="flex items-center gap-2">
                   <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></div>
                   <span className="text-[10px] font-mono text-slate-500 uppercase">{activeAsset.name}</span>
                </div>
              </div>
           </div>

           {/* Flexible Content Panels */}
           <div className={`flex-1 flex overflow-hidden ${assetViewMode === 'split' ? 'divide-x divide-slate-800/40' : ''}`}>
              {(assetViewMode === 'edit' || assetViewMode === 'split') && (
                <div className="flex-1 flex flex-col min-w-0 relative h-full">
                  <textarea 
                    ref={editorRef}
                    value={activeAsset.content}
                    onChange={(e) => updateAssetContent(activeAsset.id, e.target.value)}
                    className="w-full h-full p-12 bg-[#050608]/20 text-slate-300 font-mono text-sm leading-relaxed outline-none resize-none custom-scrollbar selection:bg-felix-500/30 placeholder:text-slate-800"
                    placeholder="# Orchestrate your document content here..."
                  />
                  {assetViewMode === 'edit' && (
                    <div className="absolute top-4 right-4 text-[9px] font-mono text-slate-700 uppercase tracking-[0.2em] bg-slate-900/30 px-3 py-1 rounded-full border border-slate-800/50 backdrop-blur">Resource Source Editor</div>
                  )}
                </div>
              )}

              {(assetViewMode === 'preview' || assetViewMode === 'split') && (
                <div className="flex-1 flex flex-col min-w-0 h-full bg-[#0d1117]/10 relative">
                   <div className="flex-1 p-12 overflow-y-auto custom-scrollbar markdown-preview font-sans max-w-4xl mx-auto w-full">
                      <div dangerouslySetInnerHTML={{ __html: parsedHtml }} />
                      {!parsedHtml && (
                        <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                           <IconFelix className="w-12 h-12 opacity-10" />
                           <span className="text-xs font-mono uppercase tracking-widest opacity-20">Awaiting content for rendering...</span>
                        </div>
                      )}
                   </div>
                   {assetViewMode === 'preview' && (
                    <div className="absolute top-4 right-4 text-[9px] font-mono text-slate-700 uppercase tracking-[0.2em] bg-slate-900/30 px-3 py-1 rounded-full border border-slate-800/50 backdrop-blur">Live Visualization</div>
                   )}
                </div>
              )}
           </div>
        </div>
      </div>
    );
  };

  // Render the projects view
  const renderProjects = () => {
    return (
      <div className="flex-1 flex bg-[#0d1117] overflow-hidden">
        {/* Project Selector Panel */}
        <div className="w-80 border-r border-slate-800/60 flex flex-col bg-[#0a0c10]/40 flex-shrink-0">
          <ProjectSelector
            selectedProjectId={selectedProjectId}
            onSelectProject={handleSelectProject}
          />
        </div>

        {/* Project Details Panel */}
        <div className="flex-1 flex flex-col min-w-0 bg-[#0a0c10]/20">
          {/* Show Run Artifact Viewer when a run is selected */}
          {selectedRunId && selectedProjectId ? (
            <RunArtifactViewer
              projectId={selectedProjectId}
              runId={selectedRunId}
              onClose={() => setSelectedRunId(null)}
            />
          ) : selectedProject ? (
            <>
              {/* Project header */}
              <div className="h-16 border-b border-slate-800/60 flex items-center px-8 bg-[#0d1117]/95 backdrop-blur">
                <div className="flex-1">
                  <h2 className="text-lg font-bold text-slate-200">
                    {selectedProject.name || selectedProject.path.split(/[\\/]/).pop()}
                  </h2>
                  <p className="text-[10px] font-mono text-slate-600 truncate max-w-lg">
                    {selectedProject.path}
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  {selectedProject.status && (
                    <span className={`text-[10px] font-bold px-2 py-1 rounded-lg uppercase ${
                      selectedProject.status === 'running' ? 'bg-felix-500/20 text-felix-400' :
                      selectedProject.status === 'complete' ? 'bg-emerald-500/20 text-emerald-400' :
                      selectedProject.status === 'blocked' ? 'bg-red-500/20 text-red-400' :
                      'bg-slate-800 text-slate-400'
                    }`}>
                      {selectedProject.status}
                    </span>
                  )}
                </div>
              </div>

              {/* Project overview */}
              <div className="flex-1 p-8 overflow-y-auto custom-scrollbar">
                <div className="grid grid-cols-3 gap-6 mb-8">
                  {/* Specs card */}
                  <div className="bg-[#161b22] border border-slate-800/60 rounded-2xl p-6 hover:border-felix-600/40 transition-all">
                    <div className="flex items-center gap-3 mb-4">
                      <div className="w-10 h-10 bg-felix-500/10 rounded-xl flex items-center justify-center">
                        <IconFileText className="w-5 h-5 text-felix-400" />
                      </div>
                      <div>
                        <h3 className="text-2xl font-bold text-slate-200">
                          {selectedProject.spec_count}
                        </h3>
                        <p className="text-[10px] font-mono text-slate-600 uppercase">
                          Specifications
                        </p>
                      </div>
                    </div>
                    <button 
                      onClick={() => setUiState('assets')}
                      className="w-full py-2 text-xs text-felix-400 hover:text-felix-300 transition-colors"
                    >
                      View Specs →
                    </button>
                  </div>

                  {/* Plan card */}
                  <div className="bg-[#161b22] border border-slate-800/60 rounded-2xl p-6 hover:border-felix-600/40 transition-all">
                    <div className="flex items-center gap-3 mb-4">
                      <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                        selectedProject.has_plan ? 'bg-emerald-500/10' : 'bg-slate-800'
                      }`}>
                        <IconKanban className={`w-5 h-5 ${
                          selectedProject.has_plan ? 'text-emerald-400' : 'text-slate-600'
                        }`} />
                      </div>
                      <div>
                        <h3 className="text-sm font-bold text-slate-200">
                          Project README
                        </h3>
                        <p className="text-[10px] font-mono text-slate-600 uppercase">
                          Documentation
                        </p>
                      </div>
                    </div>
                    <button 
                      onClick={() => setUiState('plan')}
                      className="w-full py-2 text-xs text-felix-400 hover:text-felix-300 transition-colors"
                    >
                      View README →
                    </button>
                  </div>

                  {/* Requirements card */}
                  <div className="bg-[#161b22] border border-slate-800/60 rounded-2xl p-6 hover:border-felix-600/40 transition-all">
                    <div className="flex items-center gap-3 mb-4">
                      <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                        selectedProject.has_requirements ? 'bg-amber-500/10' : 'bg-slate-800'
                      }`}>
                        <IconCpu className={`w-5 h-5 ${
                          selectedProject.has_requirements ? 'text-amber-400' : 'text-slate-600'
                        }`} />
                      </div>
                      <div>
                        <h3 className="text-sm font-bold text-slate-200">
                          {selectedProject.has_requirements ? 'Configured' : 'None'}
                        </h3>
                        <p className="text-[10px] font-mono text-slate-600 uppercase">
                          Requirements
                        </p>
                      </div>
                    </div>
                    <button 
                      onClick={() => setUiState('kanban')}
                      className="w-full py-2 text-xs text-felix-400 hover:text-felix-300 transition-colors"
                    >
                      View Board →
                    </button>
                  </div>
                </div>

                {/* Quick actions */}
                <div className="bg-[#161b22] border border-slate-800/60 rounded-2xl p-6 mb-6">
                  <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-4">
                    Quick Actions
                  </h3>
                  <div className="grid grid-cols-2 gap-3 mb-3">
                    <button
                      onClick={() => setUiState('assets')}
                      className="py-3 px-4 bg-slate-800/50 hover:bg-slate-800 rounded-xl text-sm text-slate-300 hover:text-slate-100 transition-all flex items-center justify-center gap-2"
                    >
                      <IconFileText className="w-4 h-4" />
                      Edit Specs
                    </button>
                    <button
                      onClick={() => setUiState('kanban')}
                      className="py-3 px-4 bg-slate-800/50 hover:bg-slate-800 rounded-xl text-sm text-slate-300 hover:text-slate-100 transition-all flex items-center justify-center gap-2"
                    >
                      <IconKanban className="w-4 h-4" />
                      View Board
                    </button>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      onClick={() => setUiState('plan')}
                      className="py-3 px-4 bg-slate-800/50 hover:bg-slate-800 rounded-xl text-sm text-slate-300 hover:text-slate-100 transition-all flex items-center justify-center gap-2"
                    >
                      <IconFileCode className="w-4 h-4" />
                      View README
                    </button>
                    <button
                      onClick={() => setUiState('config')}
                      className="py-3 px-4 bg-slate-800/50 hover:bg-slate-800 rounded-xl text-sm text-slate-300 hover:text-slate-100 transition-all flex items-center justify-center gap-2"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                      Config
                    </button>
                  </div>
                </div>

                {/* Run Monitor - Real-time Status */}
                <div className="mb-6">
                  <RunMonitor
                    projectId={selectedProjectId!}
                    onRunComplete={(data) => {
                      // Refresh project details when a run completes
                      console.log('Run completed:', data);
                    }}
                  />
                </div>

                {/* Agent Controls */}
                <AgentControls
                  projectId={selectedProjectId!}
                  onSelectRun={(runId) => setSelectedRunId(runId)}
                />
              </div>
            </>
          ) : (
            // No project selected
            <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
              <div className="w-20 h-20 bg-slate-800/50 rounded-3xl flex items-center justify-center mb-6">
                <IconFelix className="w-10 h-10 text-slate-700" />
              </div>
              <h2 className="text-lg font-bold text-slate-400 mb-2">
                No Project Selected
              </h2>
              <p className="text-sm text-slate-600 max-w-md mb-6">
                Select a project from the list to view its details, or register a new project to get started.
              </p>
              {backendStatus === 'disconnected' && (
                <div className="bg-amber-500/10 border border-amber-500/20 rounded-xl px-4 py-3 text-xs text-amber-400">
                  <span className="font-bold">Backend Offline:</span> Start the Felix backend server to manage projects.
                  <code className="block mt-2 bg-black/30 px-2 py-1 rounded text-amber-300">
                    cd app/backend && python main.py
                  </code>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-[#050608] text-slate-300 font-sans selection:bg-felix-500/30">
      {/* Primary Orchestration Sidebar */}
      <aside className="w-16 border-r border-slate-800/60 bg-[#0d1117] flex flex-col items-center py-6 gap-6 z-30 shadow-2xl flex-shrink-0">
        <div 
          onClick={() => setUiState('projects')}
          className="p-2 bg-felix-600 rounded-2xl shadow-xl shadow-felix-900/50 transform hover:scale-110 transition-transform cursor-pointer group"
          title="Projects"
        >
           <IconFelix className="w-6 h-6 text-white group-hover:rotate-45 transition-transform duration-500" />
        </div>
        <div className="flex-1 flex flex-col items-center gap-4 w-full px-2">
          {/* Projects button */}
          <button 
            onClick={() => setUiState('projects')}
            className={`p-3 rounded-2xl transition-all w-full flex items-center justify-center group relative ${uiState === 'projects' ? 'bg-slate-800 text-felix-400 shadow-md border border-slate-700/50' : 'text-slate-600 hover:text-slate-300 hover:bg-slate-800/30'}`}
            title="Projects"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5">
              <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
            </svg>
            {uiState === 'projects' && <div className="absolute -left-2 w-1 h-6 bg-felix-500 rounded-full"></div>}
          </button>
          <button 
            onClick={() => setUiState('kanban')}
            className={`p-3 rounded-2xl transition-all w-full flex items-center justify-center group relative ${uiState === 'kanban' ? 'bg-slate-800 text-felix-400 shadow-md border border-slate-700/50' : 'text-slate-600 hover:text-slate-300 hover:bg-slate-800/30'}`}
            title="Project Board"
          >
            <IconKanban className="w-5 h-5" />
            {uiState === 'kanban' && <div className="absolute -left-2 w-1 h-6 bg-felix-500 rounded-full"></div>}
          </button>
          <button 
            onClick={() => setUiState('canvas')}
            className={`p-3 rounded-2xl transition-all w-full flex items-center justify-center group relative ${uiState === 'canvas' ? 'bg-slate-800 text-felix-400 shadow-md border border-slate-700/50' : 'text-slate-600 hover:text-slate-300 hover:bg-slate-800/30'}`}
            title="Code Canvas"
          >
            <IconFileCode className="w-5 h-5" />
            {uiState === 'canvas' && <div className="absolute -left-2 w-1 h-6 bg-felix-500 rounded-full"></div>}
          </button>
          <button 
            onClick={() => setUiState('assets')}
            className={`p-3 rounded-2xl transition-all w-full flex items-center justify-center group relative ${uiState === 'assets' ? 'bg-slate-800 text-felix-400 shadow-md border border-slate-700/50' : 'text-slate-600 hover:text-slate-300 hover:bg-slate-800/30'}`}
            title="Resource Documents"
          >
            <IconFileText className="w-5 h-5" />
            {uiState === 'assets' && <div className="absolute -left-2 w-1 h-6 bg-felix-500 rounded-full"></div>}
          </button>
          <div className="h-px w-8 bg-slate-800/50 my-2"></div>
          <button className="p-3 text-slate-700 hover:text-slate-300 transition-all w-full flex items-center justify-center hover:bg-slate-800/30 rounded-2xl group">
            <IconSearch className="w-5 h-5 group-hover:scale-110 transition-transform" />
          </button>
        </div>
        <div className="mt-auto flex flex-col items-center gap-4">
          {/* Settings button */}
          <button 
            onClick={() => setUiState('settings')}
            className={`p-3 rounded-2xl transition-all w-full flex items-center justify-center group relative ${uiState === 'settings' ? 'bg-slate-800 text-felix-400 shadow-md border border-slate-700/50' : 'text-slate-600 hover:text-slate-300 hover:bg-slate-800/30'}`}
            title="Settings"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            {uiState === 'settings' && <div className="absolute -left-2 w-1 h-6 bg-felix-500 rounded-full"></div>}
          </button>
          {/* Backend status indicator */}
          <div 
            className={`w-2 h-2 rounded-full ${
              backendStatus === 'connected' ? 'bg-emerald-500' : 
              backendStatus === 'disconnected' ? 'bg-red-500' : 
              'bg-slate-600'
            }`}
            title={`Backend: ${backendStatus}`}
          />
          <div className="w-9 h-9 rounded-2xl bg-[#161b22] flex items-center justify-center text-[10px] font-bold border border-slate-800 text-slate-500 shadow-inner hover:border-felix-600/50 transition-colors cursor-pointer">NS</div>
        </div>
      </aside>

      {/* Main View Container */}
      <div className="flex-1 flex flex-col relative min-w-0">
        <header className="h-14 border-b border-slate-800/60 flex items-center px-8 justify-between bg-[#0a0c10]/70 backdrop-blur-2xl flex-shrink-0 z-10">
           <div className="flex items-center gap-4">
              <h2 className="text-sm font-bold tracking-[0.15em] text-white uppercase flex items-center gap-3">
                {uiState === 'projects' && <div className="w-2 h-2 rounded-full bg-felix-500 shadow-lg shadow-felix-500/20"></div>}
                {uiState === 'kanban' && <div className="w-2 h-2 rounded-full bg-amber-500 shadow-lg shadow-amber-500/20"></div>}
                {uiState === 'canvas' && <div className="w-2 h-2 rounded-full bg-felix-400 shadow-lg shadow-felix-400/20"></div>}
                {uiState === 'assets' && <div className="w-2 h-2 rounded-full bg-emerald-400 shadow-lg shadow-emerald-400/20"></div>}
                {uiState === 'config' && <div className="w-2 h-2 rounded-full bg-slate-400 shadow-lg shadow-slate-400/20"></div>}
                {uiState === 'plan' && <div className="w-2 h-2 rounded-full bg-cyan-400 shadow-lg shadow-cyan-400/20"></div>}
                {uiState === 'settings' && <div className="w-2 h-2 rounded-full bg-purple-400 shadow-lg shadow-purple-400/20"></div>}
                {uiState === 'projects' ? 'Projects' : uiState === 'kanban' ? 'System Board' : uiState === 'canvas' ? 'Orchestration Canvas' : uiState === 'assets' ? 'Specifications' : uiState === 'config' ? 'Configuration' : uiState === 'plan' ? 'Project README' : uiState === 'settings' ? 'Settings' : 'Workspace Assets'}
              </h2>
              <div className="h-4 w-[1px] bg-slate-800 mx-2"></div>
              <span className="text-[10px] font-mono text-slate-500 truncate max-w-[300px] hover:text-slate-300 transition-colors cursor-default">
                {selectedProject ? selectedProject.name || selectedProject.path.split(/[\\/]/).pop() : 'No project selected'}
                {uiState !== 'projects' && activeAsset && ` / ${activeAsset.name}`}
              </span>
           </div>
           <div className="flex items-center gap-6">
              <div className="flex items-center gap-2">
                <div className={`w-1.5 h-1.5 rounded-full ${backendStatus === 'connected' ? 'bg-emerald-500 animate-pulse' : 'bg-red-500'} shadow-lg`}></div>
                <span className="text-[10px] font-mono font-bold text-slate-500 uppercase tracking-tighter">
                  {backendStatus === 'connected' ? 'Backend Online' : 'Backend Offline'}
                </span>
              </div>
           </div>
        </header>

        {uiState === 'projects' ? renderProjects() : uiState === 'kanban' ? (
          selectedProjectId ? (
            <RequirementsKanban 
              projectId={selectedProjectId} 
              onSelectRequirement={(req) => {
                // Navigate to spec view when requirement is clicked
                console.log('Selected requirement:', req.id);
              }}
            />
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-center bg-[#050608]">
              <span className="text-sm text-slate-500">Select a project to view requirements</span>
              <button 
                onClick={() => setUiState('projects')}
                className="mt-4 px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
              >
                Go to Projects
              </button>
            </div>
          )
        ) : uiState === 'canvas' ? renderCanvas() : uiState === 'assets' ? (
          selectedProjectId ? (
            <SpecsEditor 
              projectId={selectedProjectId}
              onSelectSpec={(filename) => {
                console.log('Selected spec:', filename);
              }}
            />
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-center bg-[#050608]">
              <span className="text-sm text-slate-500">Select a project to view specs</span>
              <button 
                onClick={() => setUiState('projects')}
                className="mt-4 px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
              >
                Go to Projects
              </button>
            </div>
          )
        ) : uiState === 'config' ? (
          selectedProjectId ? (
            <ConfigPanel 
              projectId={selectedProjectId}
              onClose={() => setUiState('projects')}
            />
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-center bg-[#050608]">
              <span className="text-sm text-slate-500">Select a project to view configuration</span>
              <button 
                onClick={() => setUiState('projects')}
                className="mt-4 px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
              >
                Go to Projects
              </button>
            </div>
          )
        ) : uiState === 'plan' ? (
          selectedProjectId ? (
            <PlanViewer 
              projectId={selectedProjectId}
              onBack={() => setUiState('projects')}
            />
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-center bg-[#050608]">
              <span className="text-sm text-slate-500">Select a project to view README</span>
              <button 
                onClick={() => setUiState('projects')}
                className="mt-4 px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
              >
                Go to Projects
              </button>
            </div>
          )
        ) : uiState === 'settings' ? (
          selectedProjectId ? (
            <SettingsScreen 
              projectId={selectedProjectId}
              onBack={() => setUiState('projects')}
            />
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-center bg-[#050608]">
              <span className="text-sm text-slate-500">Select a project to view settings</span>
              <button 
                onClick={() => setUiState('projects')}
                className="mt-4 px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
              >
                Go to Projects
              </button>
            </div>
          )
        ) : renderAssets()}

      </div>

      {/* Persistent OS Status Bar */}
      <footer className="h-8 border-t border-slate-800/60 bg-[#0d1117] flex items-center px-6 justify-between text-[10px] font-mono text-slate-500 z-40 fixed bottom-0 left-0 right-0 select-none flex-shrink-0 backdrop-blur-xl">
         <div className="flex items-center gap-6">
            <div className="flex items-center gap-2 text-felix-400 group cursor-default">
               <IconTerminal className="w-3.5 h-3.5 group-hover:animate-pulse" />
               <span className="font-bold uppercase tracking-[0.2em] text-[9px]">Felix Kernel: 3.1-STABLE</span>
            </div>
            <div className="h-4 w-[1px] bg-slate-800 opacity-50"></div>
            <span className="opacity-60 uppercase tracking-tighter text-slate-600">ID: FLX-ORCH-8821</span>
            <span className="opacity-60 text-slate-600 uppercase">Load: 0.42 / 1.00</span>
         </div>
         <div className="flex items-center gap-6">
            <div className="flex items-center gap-2 hover:text-slate-300 transition-colors cursor-pointer">
              <span className="uppercase text-[9px]">Latency</span>
              <span className="text-emerald-500 font-bold">18ms</span>
            </div>
            <div className="h-4 w-[1px] bg-slate-800 opacity-50"></div>
            <div className="flex items-center gap-2 group cursor-pointer">
               <div className="w-2 h-2 rounded-full bg-emerald-500 shadow-sm shadow-emerald-500/20 group-hover:scale-125 transition-transform"></div>
               <span className="uppercase tracking-[0.1em] group-hover:text-slate-300 transition-colors">Workspace Encrypted</span>
            </div>
            <div className="h-4 w-[1px] bg-slate-800 opacity-50"></div>
            <span className="hover:text-slate-300 cursor-pointer transition-colors uppercase tracking-widest font-bold">UTF-8</span>
         </div>
      </footer>
    </div>
  );
};

export default App;

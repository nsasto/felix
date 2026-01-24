
import React, { useState, useEffect, useRef, useMemo } from 'react';
import { 
  Message, 
  MessageRole, 
  Conversation, 
  ModelType, 
  Attachment,
  ContextFile,
  Task,
  UIState,
  MarkdownAsset
} from './types';
import { geminiService } from './services/geminiService';
import { 
  IconFelix, 
  IconSearch, 
  IconTerminal, 
  IconFileCode,
  IconFileText,
  IconCpu,
  IconKanban,
  IconMaximize,
  IconChevronRight,
  IconPlus 
} from './components/Icons';
import ChatBubble from './components/ChatBubble';
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

const App: React.FC = () => {
  const [tasks, setTasks] = useState<Task[]>(INITIAL_TASKS);
  const [assets, setAssets] = useState<MarkdownAsset[]>(INITIAL_ASSETS);
  const [uiState, setUiState] = useState<UIState>('kanban');
  const [selectedAssetId, setSelectedAssetId] = useState<string>(INITIAL_ASSETS[0].id);
  const [assetViewMode, setAssetViewMode] = useState<'edit' | 'preview' | 'split'>('split');
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [inputText, setInputText] = useState('');
  const [selectedModel, setSelectedModel] = useState<ModelType>(ModelType.FLASH);
  const [isLoading, setIsLoading] = useState(false);
  const [parsedHtml, setParsedHtml] = useState<string>('');
  const [messages, setMessages] = useState<Message[]>([
    { id: 'm1', role: MessageRole.MODEL, text: "Felix active. I'm monitoring your workspace. How can I help orchestrate your workflow?", timestamp: Date.now() }
  ]);

  const chatScrollRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<HTMLTextAreaElement>(null);
  const activeAsset = useMemo(() => assets.find(a => a.id === selectedAssetId) || assets[0], [assets, selectedAssetId]);

  useEffect(() => {
    if (chatScrollRef.current) chatScrollRef.current.scrollTop = chatScrollRef.current.scrollHeight;
  }, [messages, isLoading]);

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

  const handleSendMessage = async () => {
    if (!inputText.trim()) return;
    const userMsg: Message = { id: Date.now().toString(), role: MessageRole.USER, text: inputText, timestamp: Date.now() };
    setMessages(prev => [...prev, userMsg]);
    setInputText('');
    setIsLoading(true);

    const context: ContextFile[] = uiState === 'assets' ? [
      { id: activeAsset.id, name: activeAsset.name, path: activeAsset.name, content: activeAsset.content, language: 'markdown' }
    ] : [];

    try {
      const response = await geminiService.generateResponse(selectedModel, messages, inputText, [], context, false);
      const modelMsg: Message = { id: (Date.now() + 1).toString(), role: MessageRole.MODEL, text: response.text, sources: response.sources, timestamp: Date.now() };
      setMessages(prev => [...prev, modelMsg]);
    } catch (err) {
      console.error(err);
    } finally {
      setIsLoading(false);
    }
  };

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
        {renderFelixPane()}
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

        {renderFelixPane()}
      </div>
    );
  };

  const renderFelixPane = () => (
    <div className="w-[450px] flex flex-col bg-[#050608] z-10 border-l border-slate-800/60 shadow-2xl flex-shrink-0 relative overflow-hidden">
      {/* Decorative pulse background */}
      <div className="absolute top-0 right-0 w-64 h-64 bg-felix-900/10 blur-[100px] pointer-events-none rounded-full -translate-y-1/2 translate-x-1/2"></div>
      
      <div className="h-12 border-b border-slate-800/60 flex items-center px-4 justify-between bg-[#0d1117]/50 backdrop-blur shrink-0">
        <div className="flex items-center gap-2">
          <IconFelix className="w-4 h-4 text-felix-400" />
          <span className="text-[10px] font-bold uppercase tracking-widest text-slate-500">Felix Context Intelligence</span>
        </div>
        <button onClick={() => setUiState('kanban')} className="p-1.5 hover:bg-slate-800 rounded-lg transition-all text-slate-500 hover:text-slate-300">
           <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12" strokeWidth="2" strokeLinecap="round"/></svg>
        </button>
      </div>
      <div ref={chatScrollRef} className="flex-1 overflow-y-auto custom-scrollbar p-6 space-y-6 relative z-10">
        {messages.map(msg => <ChatBubble key={msg.id} message={msg} />)}
        {isLoading && (
           <div className="flex items-center gap-3 text-slate-600 text-[10px] font-mono animate-pulse pl-2 border-l-2 border-felix-600/30">
             <IconCpu className="w-3 h-3 animate-spin" />
             Felix is synthesizing project state...
           </div>
        )}
      </div>
      <div className="p-4 border-t border-slate-800/60 bg-[#0d1117]/90 backdrop-blur shrink-0">
         <div className="relative group">
            <textarea 
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && (e.preventDefault(), handleSendMessage())}
              className="w-full bg-[#161b22] border border-slate-700/50 rounded-2xl p-4 pr-14 text-sm focus:ring-1 focus:ring-felix-500 focus:border-felix-500 transition-all resize-none min-h-[50px] max-h-[200px] shadow-2xl placeholder:text-slate-600 selection:bg-felix-500/40"
              placeholder={uiState === 'assets' ? `Ask Felix to refine ${activeAsset.name}...` : "Initiate reasoning sequence..."}
              rows={1}
            />
            <button 
              onClick={handleSendMessage}
              className="absolute right-3 bottom-3 p-2 bg-felix-600 text-white rounded-xl hover:bg-felix-500 transition-all transform active:scale-95 shadow-lg shadow-felix-900/40 disabled:opacity-50"
              disabled={isLoading || !inputText.trim()}
            >
               <IconChevronRight className="w-4 h-4" />
            </button>
         </div>
         <div className="mt-3 flex justify-center">
            <span className="text-[8px] font-mono text-slate-700 uppercase tracking-[0.3em]">Neural Link Stable // 256-bit AES</span>
         </div>
      </div>
    </div>
  );

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-[#050608] text-slate-300 font-sans selection:bg-felix-500/30">
      {/* Primary Orchestration Sidebar */}
      <aside className="w-16 border-r border-slate-800/60 bg-[#0d1117] flex flex-col items-center py-6 gap-6 z-30 shadow-2xl flex-shrink-0">
        <div className="p-2 bg-felix-600 rounded-2xl shadow-xl shadow-felix-900/50 transform hover:scale-110 transition-transform cursor-pointer group">
           <IconFelix className="w-6 h-6 text-white group-hover:rotate-45 transition-transform duration-500" />
        </div>
        <div className="flex-1 flex flex-col items-center gap-4 w-full px-2">
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
           <div className="w-9 h-9 rounded-2xl bg-[#161b22] flex items-center justify-center text-[10px] font-bold border border-slate-800 text-slate-500 shadow-inner hover:border-felix-600/50 transition-colors cursor-pointer">NS</div>
        </div>
      </aside>

      {/* Main View Container */}
      <div className="flex-1 flex flex-col relative min-w-0">
        <header className="h-14 border-b border-slate-800/60 flex items-center px-8 justify-between bg-[#0a0c10]/70 backdrop-blur-2xl flex-shrink-0 z-10">
           <div className="flex items-center gap-4">
              <h2 className="text-sm font-bold tracking-[0.15em] text-white uppercase flex items-center gap-3">
                {uiState === 'kanban' && <div className="w-2 h-2 rounded-full bg-amber-500 shadow-lg shadow-amber-500/20"></div>}
                {uiState === 'canvas' && <div className="w-2 h-2 rounded-full bg-felix-400 shadow-lg shadow-felix-400/20"></div>}
                {uiState === 'assets' && <div className="w-2 h-2 rounded-full bg-emerald-400 shadow-lg shadow-emerald-400/20"></div>}
                {uiState === 'kanban' ? 'System Board' : uiState === 'canvas' ? 'Orchestration Canvas' : 'Workspace Assets'}
              </h2>
              <div className="h-4 w-[1px] bg-slate-800 mx-2"></div>
              <span className="text-[10px] font-mono text-slate-500 truncate max-w-[300px] hover:text-slate-300 transition-colors cursor-default">FELIX_OS_CORE / {activeAsset.name}</span>
           </div>
           <div className="flex items-center gap-6">
              <div className="flex items-center gap-3 bg-slate-900/40 px-4 py-2 rounded-2xl border border-slate-800/50 group hover:border-felix-600/30 transition-all">
                <IconCpu className="w-3.5 h-3.5 text-slate-600 group-hover:text-felix-400 transition-colors" />
                <span className="text-[9px] font-mono font-bold text-slate-500 uppercase tracking-widest">
                  {selectedModel === ModelType.FLASH ? 'Gemini 3 Flash' : 'Gemini 3 Pro'}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 shadow-lg shadow-emerald-500/40 animate-pulse"></div>
                <span className="text-[10px] font-mono font-bold text-slate-500 uppercase tracking-tighter">Live Sync</span>
              </div>
           </div>
        </header>

        {uiState === 'kanban' ? renderKanban() : uiState === 'canvas' ? renderCanvas() : renderAssets()}

        {/* Floating AI Interface Component */}
        {uiState === 'kanban' && (
          <div className="absolute bottom-12 right-12 z-50 flex flex-col items-end gap-5">
            {isChatOpen && (
              <div className="w-[420px] h-[600px] bg-[#0d1117] border border-slate-800/80 shadow-[0_32px_64px_-16px_rgba(0,0,0,0.8)] rounded-3xl flex flex-col overflow-hidden animate-in backdrop-blur-xl">
                <div className="h-14 border-b border-slate-800/60 bg-[#161b22]/80 px-5 flex items-center justify-between">
                   <div className="flex items-center gap-3">
                      <div className="p-1.5 bg-felix-600 rounded-lg">
                        <IconFelix className="w-4 h-4 text-white" />
                      </div>
                      <div className="flex flex-col">
                        <span className="text-xs font-bold text-slate-200">Felix Assistant</span>
                        <span className="text-[9px] font-mono text-emerald-500 uppercase leading-none">Context Active</span>
                      </div>
                   </div>
                   <div className="flex items-center gap-2">
                     <button 
                       onClick={() => { setUiState('canvas'); setIsChatOpen(false); }}
                       className="p-2 hover:bg-slate-800 rounded-xl text-slate-500 transition-all hover:text-felix-400" title="Expand Analysis"
                     >
                        <IconMaximize className="w-4 h-4" />
                     </button>
                     <button onClick={() => setIsChatOpen(false)} className="p-2 hover:bg-slate-800 rounded-xl text-slate-500 hover:text-red-400 transition-all">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12" strokeWidth="2.5" strokeLinecap="round"/></svg>
                     </button>
                   </div>
                </div>
                <div ref={chatScrollRef} className="flex-1 overflow-y-auto custom-scrollbar p-6 space-y-6 bg-black/30">
                   {messages.map(msg => <ChatBubble key={msg.id} message={msg} />)}
                   {isLoading && (
                      <div className="flex items-center gap-3 text-slate-600 text-[10px] font-mono animate-pulse bg-slate-900/50 p-4 rounded-2xl border border-slate-800/50">
                        <IconCpu className="w-4 h-4 animate-spin text-felix-500" />
                        Synchronizing neural context...
                      </div>
                   )}
                </div>
                <div className="p-5 border-t border-slate-800/60 bg-[#161b22]/90">
                   <div className="relative">
                      <input 
                        value={inputText}
                        onChange={(e) => setInputText(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleSendMessage()}
                        className="w-full bg-[#0d1117] border border-slate-700/40 rounded-2xl py-3 pl-5 pr-12 text-xs focus:ring-1 focus:ring-felix-500 focus:border-felix-500 transition-all outline-none placeholder:text-slate-700 shadow-inner"
                        placeholder="Talk to Felix Assistant..."
                      />
                      <button 
                        onClick={handleSendMessage}
                        className="absolute right-2.5 top-2 p-1.5 text-felix-400 hover:text-white transition-colors hover:scale-110 active:scale-90"
                      >
                         <IconChevronRight className="w-5 h-5" />
                      </button>
                   </div>
                </div>
              </div>
            )}
            
            {!isChatOpen && (
              <button 
                onClick={() => setIsChatOpen(true)}
                className="w-16 h-16 bg-felix-600 rounded-3xl shadow-2xl shadow-felix-900/60 hover:bg-felix-500 hover:scale-105 transition-all flex items-center justify-center group border border-felix-400/20 active:scale-95"
              >
                <IconFelix className="w-8 h-8 text-white group-hover:rotate-12 transition-transform duration-300" />
                <div className="absolute -top-1 -right-1 w-5 h-5 bg-emerald-500 rounded-full border-[3px] border-[#050608] animate-bounce"></div>
              </button>
            )}
          </div>
        )}
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

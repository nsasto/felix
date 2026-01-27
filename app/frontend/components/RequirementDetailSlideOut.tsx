import React, { useState, useEffect, useCallback, useRef } from 'react';
import { felixApi, Requirement, RunHistoryResponse, RunHistoryEntry } from '../services/felixApi';
import { marked } from 'marked';

// Status badge styles matching RequirementsKanban
const STATUS_STYLES: Record<string, { bg: string; text: string; border: string }> = {
  draft: { bg: 'bg-slate-500/10', text: 'text-slate-400', border: 'border-slate-500/20' },
  planned: { bg: 'bg-blue-500/10', text: 'text-blue-400', border: 'border-blue-500/20' },
  in_progress: { bg: 'bg-amber-500/10', text: 'text-amber-400', border: 'border-amber-500/20' },
  complete: { bg: 'bg-emerald-500/10', text: 'text-emerald-400', border: 'border-emerald-500/20' },
  blocked: { bg: 'bg-red-500/10', text: 'text-red-400', border: 'border-red-500/20' },
};

const PRIORITY_STYLES: Record<string, { bg: string; text: string; border: string }> = {
  critical: { bg: 'bg-red-500/10', text: 'text-red-400', border: 'border-red-500/20' },
  high: { bg: 'bg-amber-500/10', text: 'text-amber-400', border: 'border-amber-500/20' },
  medium: { bg: 'bg-blue-500/10', text: 'text-blue-400', border: 'border-blue-500/20' },
  low: { bg: 'bg-slate-500/10', text: 'text-slate-400', border: 'border-slate-500/20' },
};

type TabId = 'requirements' | 'history';

interface TabInfo {
  id: TabId;
  label: string;
}

const TABS: TabInfo[] = [
  { id: 'requirements', label: 'Requirements' },
  { id: 'history', label: 'History' },
];

interface RequirementDetailSlideOutProps {
  projectId: string;
  requirement: Requirement | null;
  onClose: () => void;
  onEditSpec?: (filename: string) => void;
  onViewPlan?: (planPath: string) => void;
}

const RequirementDetailSlideOut: React.FC<RequirementDetailSlideOutProps> = ({
  projectId,
  requirement,
  onClose,
  onEditSpec,
  onViewPlan,
}) => {
  const [activeTab, setActiveTab] = useState<TabId>('requirements');
  const [specContent, setSpecContent] = useState<string>('');
  const [specLoading, setSpecLoading] = useState(false);
  const [specError, setSpecError] = useState<string | null>(null);
  const [parsedHtml, setParsedHtml] = useState<string>('');
  
  // History state
  const [runHistory, setRunHistory] = useState<RunHistoryEntry[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [expandedRuns, setExpandedRuns] = useState<Set<string>>(new Set());

  const slideOutRef = useRef<HTMLDivElement>(null);
  const isOpen = requirement !== null;

  // Fetch spec content when requirement changes
  useEffect(() => {
    if (!requirement || !requirement.spec_path) {
      setSpecContent('');
      setParsedHtml('');
      return;
    }

    const fetchSpec = async () => {
      setSpecLoading(true);
      setSpecError(null);

      try {
        // Extract filename from spec_path (e.g., "specs/S-0010-kanban.md" -> "S-0010-kanban.md")
        const filename = requirement.spec_path.split('/').pop() || requirement.spec_path;
        const result = await felixApi.getSpec(projectId, filename);
        setSpecContent(result.content);
      } catch (err) {
        console.error('Failed to fetch spec:', err);
        setSpecError(err instanceof Error ? err.message : 'Failed to load spec');
      } finally {
        setSpecLoading(false);
      }
    };

    fetchSpec();
  }, [projectId, requirement]);

  // Parse markdown when spec content changes
  useEffect(() => {
    if (!specContent) {
      setParsedHtml('');
      return;
    }

    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        const result = await marked.parse(specContent);
        if (isMounted) {
          // Make checkboxes read-only
          const readOnlyHtml = result.replace(
            /(<input type="checkbox"[^>]*)/g, 
            '$1 disabled onclick="return false;"'
          );
          setParsedHtml(readOnlyHtml);
        }
      } catch (err) {
        console.error('Markdown parsing error:', err);
        if (isMounted) {
          setParsedHtml(`<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`);
        }
      }
    };

    parseMarkdown();
    return () => { isMounted = false; };
  }, [specContent]);

  // Fetch run history when requirement changes or history tab is selected
  useEffect(() => {
    if (!requirement || activeTab !== 'history') {
      return;
    }

    const fetchHistory = async () => {
      setHistoryLoading(true);
      setHistoryError(null);

      try {
        const result = await felixApi.listRuns(projectId);
        // Filter runs that might be related to this requirement
        // In-memory run history doesn't have requirement_id, so we show all runs
        // A more sophisticated filter could parse run artifacts for requirement references
        setRunHistory(result.runs || []);
      } catch (err) {
        console.error('Failed to fetch run history:', err);
        setHistoryError(err instanceof Error ? err.message : 'Failed to load history');
      } finally {
        setHistoryLoading(false);
      }
    };

    fetchHistory();
  }, [projectId, requirement, activeTab]);

  // Keyboard handlers
  const handleKeyDown = useCallback((event: KeyboardEvent) => {
    if (!isOpen) return;

    switch (event.key) {
      case 'Escape':
        event.preventDefault();
        onClose();
        break;
      case 'ArrowLeft':
        if (event.target === document.body || event.target === slideOutRef.current) {
          event.preventDefault();
          const currentIndex = TABS.findIndex(t => t.id === activeTab);
          if (currentIndex > 0) {
            setActiveTab(TABS[currentIndex - 1].id);
          }
        }
        break;
      case 'ArrowRight':
        if (event.target === document.body || event.target === slideOutRef.current) {
          event.preventDefault();
          const currentIndex = TABS.findIndex(t => t.id === activeTab);
          if (currentIndex < TABS.length - 1) {
            setActiveTab(TABS[currentIndex + 1].id);
          }
        }
        break;
    }
  }, [isOpen, activeTab, onClose]);

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  // Focus trap: trap focus within slide-out when open
  useEffect(() => {
    if (!isOpen) return;

    const slideOut = slideOutRef.current;
    if (!slideOut) return;

    // Focus the slide-out container
    slideOut.focus();
  }, [isOpen]);

  const toggleRunExpanded = (runId: string) => {
    setExpandedRuns(prev => {
      const next = new Set(prev);
      if (next.has(runId)) {
        next.delete(runId);
      } else {
        next.add(runId);
      }
      return next;
    });
  };

  const formatDate = (dateString: string) => {
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
    } catch {
      return dateString;
    }
  };

  const getStatusLabel = (status: string) => {
    return status.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  };

  // Don't render anything if no requirement selected
  if (!requirement) return null;

  const statusStyle = STATUS_STYLES[requirement.status] || STATUS_STYLES.draft;
  const priorityStyle = PRIORITY_STYLES[requirement.priority] || PRIORITY_STYLES.medium;

  return (
    <>
      {/* Backdrop */}
      <div 
        className={`fixed inset-0 bg-black/50 z-40 transition-opacity duration-300 ${
          isOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Slide-out Panel */}
      <div
        ref={slideOutRef}
        tabIndex={-1}
        className={`
          fixed top-0 right-0 h-full z-50
          theme-bg-base border-l theme-border
          flex flex-col
          transition-transform duration-300 ease-out
          outline-none
          w-[60vw] max-w-[800px] min-w-[500px]
          ${isOpen ? 'translate-x-0' : 'translate-x-full'}
          
          /* Responsive: Full-screen on small devices */
          max-[768px]:w-full max-[768px]:max-w-none max-[768px]:min-w-0
        `}
        role="dialog"
        aria-modal="true"
        aria-labelledby="slide-out-title"
      >
        {/* Header */}
        <div className="h-16 border-b theme-border flex items-center px-6 justify-between flex-shrink-0 theme-bg-base">
          <div className="flex items-center gap-3 min-w-0">
            <span className="text-sm font-mono font-bold text-felix-400 bg-felix-500/10 px-2.5 py-1 rounded-lg border border-felix-500/20">
              {requirement.id}
            </span>
            <h2 
              id="slide-out-title" 
              className="text-base font-bold text-slate-200 truncate"
              title={requirement.title}
            >
              {requirement.title}
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-slate-500 hover:text-slate-300 hover:bg-slate-800 transition-colors"
            aria-label="Close"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="h-12 border-b theme-border flex items-center px-6 gap-4 flex-shrink-0 theme-bg-deep">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`
                px-4 py-2 text-sm font-bold transition-all rounded-lg
                ${activeTab === tab.id 
                  ? 'text-felix-400 bg-felix-500/10 border border-felix-500/30' 
                  : 'text-slate-500 hover:text-slate-300 border border-transparent hover:border-slate-700'}
              `}
              aria-selected={activeTab === tab.id}
              role="tab"
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto custom-scrollbar">
          {activeTab === 'requirements' ? (
            <div className="p-6">
              {/* Metadata Section */}
              <div className="mb-6 space-y-4">
                {/* Status and Priority Row */}
                <div className="flex items-center gap-3 flex-wrap">
                  <span className={`text-xs font-bold px-2.5 py-1 rounded-lg uppercase ${statusStyle.bg} ${statusStyle.text} border ${statusStyle.border}`}>
                    {getStatusLabel(requirement.status)}
                  </span>
                  <span className={`text-xs font-bold px-2.5 py-1 rounded-lg uppercase ${priorityStyle.bg} ${priorityStyle.text} border ${priorityStyle.border}`}>
                    {requirement.priority}
                  </span>
                  <span className="text-xs font-mono text-slate-600">
                    Updated: {requirement.updated_at}
                  </span>
                </div>

                {/* Labels */}
                {requirement.labels && requirement.labels.length > 0 && (
                  <div className="flex flex-wrap gap-2">
                    {requirement.labels.map(label => (
                      <span 
                        key={label} 
                        className="text-xs font-mono text-slate-500 bg-slate-800/50 border border-slate-700/50 px-2 py-1 rounded-lg"
                      >
                        #{label}
                      </span>
                    ))}
                  </div>
                )}

                {/* Dependencies */}
                {requirement.depends_on && requirement.depends_on.length > 0 && (
                  <div className="flex items-center gap-2 text-xs">
                    <span className="text-slate-500">Dependencies:</span>
                    <div className="flex flex-wrap gap-1.5">
                      {requirement.depends_on.map(depId => (
                        <span 
                          key={depId}
                          className="text-xs font-mono text-cyan-400 bg-cyan-500/10 border border-cyan-500/20 px-2 py-0.5 rounded"
                        >
                          {depId}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {/* Action Buttons */}
                <div className="flex items-center gap-3 pt-2">
                  {onEditSpec && (
                    <button
                      onClick={() => {
                        const filename = requirement.spec_path.split('/').pop() || requirement.spec_path;
                        onEditSpec(filename);
                      }}
                      className="px-4 py-2 text-xs font-bold text-felix-400 bg-felix-500/10 border border-felix-500/30 rounded-lg hover:bg-felix-500/20 transition-colors flex items-center gap-2"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                      Edit Spec
                    </button>
                  )}
                  {onViewPlan && (
                    <button
                      onClick={() => onViewPlan(requirement.spec_path)}
                      className="px-4 py-2 text-xs font-bold text-slate-400 border border-slate-700 rounded-lg hover:bg-slate-800 hover:text-slate-300 transition-colors flex items-center gap-2"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                      </svg>
                      View Plan
                    </button>
                  )}
                </div>
              </div>

              {/* Spec Content */}
              <div className="border-t border-slate-800/60 pt-6">
                <h3 className="text-sm font-bold text-slate-400 uppercase tracking-wider mb-4">
                  Specification
                </h3>
                
                {specLoading ? (
                  <div className="flex items-center justify-center py-12">
                    <div className="w-6 h-6 border-2 border-felix-500/30 border-t-felix-500 rounded-full animate-spin" />
                  </div>
                ) : specError ? (
                  <div className="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 text-sm text-red-400">
                    {specError}
                  </div>
                ) : (
                  <div 
                    className="markdown-preview prose prose-invert prose-sm max-w-none
                      prose-headings:text-slate-200 prose-headings:font-bold
                      prose-p:text-slate-400 prose-p:leading-relaxed
                      prose-a:text-felix-400 prose-a:no-underline hover:prose-a:underline
                      prose-code:text-amber-400 prose-code:bg-slate-800/50 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded
                      prose-pre:theme-bg-elevated prose-pre:border prose-pre:theme-border
                      prose-li:text-slate-400
                      prose-strong:text-slate-200
                      prose-blockquote:border-l-felix-500 prose-blockquote:text-slate-400
                    "
                    dangerouslySetInnerHTML={{ __html: parsedHtml }}
                  />
                )}
              </div>
            </div>
          ) : (
            /* History Tab */
            <div className="p-6">
              <h3 className="text-sm font-bold text-slate-400 uppercase tracking-wider mb-4">
                Work History
              </h3>

              {historyLoading ? (
                <div className="flex items-center justify-center py-12">
                  <div className="w-6 h-6 border-2 border-felix-500/30 border-t-felix-500 rounded-full animate-spin" />
                </div>
              ) : historyError ? (
                <div className="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 text-sm text-red-400">
                  {historyError}
                </div>
              ) : runHistory.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-center">
                  <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                    <svg className="w-8 h-8 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                  <p className="text-sm text-slate-500">No work history yet</p>
                  <p className="text-xs text-slate-600 mt-1">
                    Run the Felix agent to see work history here.
                  </p>
                </div>
              ) : (
                <div className="space-y-3">
                  {runHistory.map(run => {
                    const isExpanded = expandedRuns.has(run.run_id);
                    const statusColor = run.status === 'completed' ? 'text-emerald-400' :
                                       run.status === 'running' ? 'text-amber-400' :
                                       run.status === 'failed' ? 'text-red-400' :
                                       'text-slate-400';
                    const statusBg = run.status === 'completed' ? 'bg-emerald-500/10 border-emerald-500/20' :
                                     run.status === 'running' ? 'bg-amber-500/10 border-amber-500/20' :
                                     run.status === 'failed' ? 'bg-red-500/10 border-red-500/20' :
                                     'bg-slate-500/10 border-slate-500/20';
                    
                    return (
                      <div 
                        key={run.run_id}
                        className="theme-bg-elevated border theme-border rounded-xl overflow-hidden"
                      >
                        {/* Run Header */}
                        <button
                          onClick={() => toggleRunExpanded(run.run_id)}
                          className="w-full px-4 py-3 flex items-center justify-between hover:bg-slate-800/30 transition-colors"
                        >
                          <div className="flex items-center gap-3">
                            <span className={`text-xs font-bold px-2 py-0.5 rounded border ${statusBg} ${statusColor} uppercase`}>
                              {run.status}
                            </span>
                            <span className="text-sm text-slate-300 font-mono">
                              {formatDate(run.started_at)}
                            </span>
                          </div>
                          <div className="flex items-center gap-3">
                            <span className="text-xs text-slate-500 font-mono">
                              PID: {run.pid}
                            </span>
                            <svg 
                              className={`w-4 h-4 text-slate-500 transition-transform ${isExpanded ? 'rotate-180' : ''}`} 
                              fill="none" 
                              stroke="currentColor" 
                              viewBox="0 0 24 24"
                            >
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 9l-7 7-7-7" />
                            </svg>
                          </div>
                        </button>

                        {/* Expanded Details */}
                        {isExpanded && (
                          <div className="px-4 py-3 border-t theme-border theme-bg-base">
                            <div className="space-y-2 text-xs">
                              <div className="flex justify-between">
                                <span className="text-slate-500">Run ID:</span>
                                <span className="text-slate-300 font-mono">{run.run_id}</span>
                              </div>
                              <div className="flex justify-between">
                                <span className="text-slate-500">Started:</span>
                                <span className="text-slate-300">{formatDate(run.started_at)}</span>
                              </div>
                              {run.ended_at && (
                                <div className="flex justify-between">
                                  <span className="text-slate-500">Ended:</span>
                                  <span className="text-slate-300">{formatDate(run.ended_at)}</span>
                                </div>
                              )}
                              {run.exit_code !== null && run.exit_code !== undefined && (
                                <div className="flex justify-between">
                                  <span className="text-slate-500">Exit Code:</span>
                                  <span className={run.exit_code === 0 ? 'text-emerald-400' : 'text-red-400'}>
                                    {run.exit_code}
                                  </span>
                                </div>
                              )}
                              {run.error_message && (
                                <div className="mt-2 p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-red-400">
                                  {run.error_message}
                                </div>
                              )}
                            </div>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer with keyboard hint */}
        <div className="h-10 border-t theme-border flex items-center px-6 justify-between flex-shrink-0 theme-bg-deep">
          <span className="text-[10px] text-slate-600">
            Press <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono">ESC</kbd> to close
          </span>
          <span className="text-[10px] text-slate-600">
            <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono">←</kbd>
            <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono ml-1">→</kbd>
            to switch tabs
          </span>
        </div>
      </div>
    </>
  );
};

export default RequirementDetailSlideOut;

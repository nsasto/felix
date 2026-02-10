import React, { useState, useEffect, useCallback, useRef } from "react";
import { felixApi, Requirement, RunHistoryEntry } from "../services/felixApi";
import { marked } from "marked";
import RunArtifactViewer from "./RunArtifactViewer";
import RunCard from "./RunCard";
import { 
  getAllDependenciesWithStatus, 
  isDependencyComplete,
  DependencyInfo 
} from "../utils/dependencies";

// Status badge styles matching RequirementsKanban
const STATUS_STYLES: Record<
  string,
  { bg: string; text: string; border: string }
> = {
  draft: {
    bg: "bg-slate-500/10",
    text: "text-slate-400",
    border: "border-slate-500/20",
  },
  planned: {
    bg: "bg-blue-500/10",
    text: "text-blue-400",
    border: "border-blue-500/20",
  },
  in_progress: {
    bg: "bg-amber-500/10",
    text: "text-amber-400",
    border: "border-amber-500/20",
  },
  complete: {
    bg: "bg-emerald-500/10",
    text: "text-emerald-400",
    border: "border-emerald-500/20",
  },
  blocked: {
    bg: "bg-red-500/10",
    text: "text-red-400",
    border: "border-red-500/20",
  },
  done: {
    bg: "bg-purple-500/10",
    text: "text-purple-400",
    border: "border-purple-500/20",
  },
};

const PRIORITY_STYLES: Record<
  string,
  { bg: string; text: string; border: string }
> = {
  critical: {
    bg: "bg-red-500/10",
    text: "text-red-400",
    border: "border-red-500/20",
  },
  high: {
    bg: "bg-amber-500/10",
    text: "text-amber-400",
    border: "border-amber-500/20",
  },
  medium: {
    bg: "bg-blue-500/10",
    text: "text-blue-400",
    border: "border-blue-500/20",
  },
  low: {
    bg: "bg-slate-500/10",
    text: "text-slate-400",
    border: "border-slate-500/20",
  },
};

type TopLevelTabId = "overview" | "history";

interface TopLevelTabInfo {
  id: TopLevelTabId;
  label: string;
  icon: string;
}

const TOP_LEVEL_TABS: TopLevelTabInfo[] = [
  { id: "overview", label: "Overview", icon: "📋" },
  { id: "history", label: "Run History", icon: "🕐" },
];

interface RequirementDetailSlideOutProps {
  projectId: string;
  requirement: Requirement | null;
  onClose: () => void;
}

const RequirementDetailSlideOut: React.FC<RequirementDetailSlideOutProps> = ({
  projectId,
  requirement,
  onClose,
}) => {
  // Top level tabs: Overview (default) or Run History
  const [activeTab, setActiveTab] = useState<TopLevelTabId>("overview");

  // Currently selected run in Run History tab
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);

  // Spec content for Overview tab
  const [specContent, setSpecContent] = useState<string>("");
  const [specLoading, setSpecLoading] = useState(false);
  const [specError, setSpecError] = useState<string | null>(null);
  const [specHtml, setSpecHtml] = useState<string>("");

  // History state
  const [runHistory, setRunHistory] = useState<RunHistoryEntry[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);

  // All requirements for dependency lookup
  const [allRequirements, setAllRequirements] = useState<Requirement[]>([]);

  const slideOutRef = useRef<HTMLDivElement>(null);
  const isOpen = requirement !== null;

  // Fetch all requirements for dependency lookup
  useEffect(() => {
    if (!projectId || !requirement) return;

    const fetchAllRequirements = async () => {
      try {
        const data = await felixApi.getRequirements(projectId);
        setAllRequirements(data.requirements || []);
      } catch (err) {
        console.warn("Failed to fetch requirements for dependency lookup:", err);
      }
    };

    fetchAllRequirements();
  }, [projectId, requirement?.id]);

  // Reset state when requirement changes
  useEffect(() => {
    if (requirement) {
      // Default tab is always Overview (consistent entry point)
      setActiveTab("overview");
      setSelectedRunId(null);
      setSpecContent("");
      setSpecHtml("");
      setRunHistory([]);
    }
  }, [requirement?.id]);

  // Fetch spec content when requirement changes
  useEffect(() => {
    if (!requirement || !requirement.spec_path) {
      setSpecContent("");
      return;
    }

    const fetchSpec = async () => {
      setSpecLoading(true);
      setSpecError(null);

      try {
        const filename =
          requirement.spec_path.split("/").pop() || requirement.spec_path;
        const result = await felixApi.getSpec(projectId, filename);
        setSpecContent(result.content);
      } catch (err) {
        console.error("Failed to fetch spec:", err);
        setSpecError(
          err instanceof Error ? err.message : "Failed to load spec",
        );
      } finally {
        setSpecLoading(false);
      }
    };

    fetchSpec();
  }, [projectId, requirement?.id, requirement?.spec_path]);

  // Parse spec markdown
  useEffect(() => {
    if (!specContent) {
      setSpecHtml("");
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
            '$1 disabled onclick="return false;"',
          );
          console.log(
            "Spec markdown parsed, HTML length:",
            readOnlyHtml.length,
          );
          setSpecHtml(readOnlyHtml);
        }
      } catch (err) {
        console.error("Markdown parsing error:", err);
        if (isMounted) {
          setSpecHtml(
            `<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`,
          );
        }
      }
    };

    parseMarkdown();
    return () => {
      isMounted = false;
    };
  }, [specContent]);

  // Fetch run history when Run History tab is selected
  useEffect(() => {
    if (!requirement || activeTab !== "history") {
      return;
    }

    const fetchHistory = async () => {
      setHistoryLoading(true);
      setHistoryError(null);

      try {
        // Filter runs by requirement ID
        const result = await felixApi.listRuns(projectId, requirement.id);
        setRunHistory(result.runs || []);
      } catch (err) {
        console.error("Failed to fetch run history:", err);
        setHistoryError(
          err instanceof Error ? err.message : "Failed to load history",
        );
      } finally {
        setHistoryLoading(false);
      }
    };

    fetchHistory();
  }, [projectId, requirement?.id, activeTab]);

  // Keyboard handlers
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (!isOpen) return;

      switch (event.key) {
        case "Escape":
          event.preventDefault();
          onClose();
          break;
        case "ArrowLeft":
          if (
            event.target === document.body ||
            event.target === slideOutRef.current
          ) {
            event.preventDefault();
            const currentIndex = TOP_LEVEL_TABS.findIndex(
              (t) => t.id === activeTab,
            );
            if (currentIndex > 0) {
              setActiveTab(TOP_LEVEL_TABS[currentIndex - 1].id);
            }
          }
          break;
        case "ArrowRight":
          if (
            event.target === document.body ||
            event.target === slideOutRef.current
          ) {
            event.preventDefault();
            const currentIndex = TOP_LEVEL_TABS.findIndex(
              (t) => t.id === activeTab,
            );
            if (currentIndex < TOP_LEVEL_TABS.length - 1) {
              setActiveTab(TOP_LEVEL_TABS[currentIndex + 1].id);
            }
          }
          break;
      }
    },
    [isOpen, activeTab, onClose],
  );

  useEffect(() => {
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);

  // Focus the slide-out when open
  useEffect(() => {
    if (!isOpen) return;

    const slideOut = slideOutRef.current;
    if (!slideOut) return;

    slideOut.focus();
  }, [isOpen]);

  const formatDate = (dateString: string) => {
    try {
      const date = new Date(dateString);
      const now = new Date();
      const diff = Math.floor((now.getTime() - date.getTime()) / 1000);
      if (diff < 60) return `${diff}s ago`;
      if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
      if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
      return `${Math.floor(diff / 86400)}d ago`;
    } catch {
      return dateString;
    }
  };

  const getStatusLabel = (status: string) => {
    return status.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  };

  const handleSelectRun = (runId: string) => {
    setSelectedRunId(runId);
  };

  // Don't render anything if no requirement selected
  if (!requirement) return null;

  const statusStyle = STATUS_STYLES[requirement.status] || STATUS_STYLES.draft;
  const priorityStyle =
    PRIORITY_STYLES[requirement.priority] || PRIORITY_STYLES.medium;

  // Render Overview tab content
  const renderOverviewTab = () => {
    console.log(
      "Rendering Overview tab, specHtml length:",
      specHtml?.length,
      "specLoading:",
      specLoading,
      "specError:",
      specError,
    );
    return (
      <div className="h-full overflow-y-auto custom-scrollbar">
        {/* Metadata Section */}
        <div className="p-6 border-b theme-border">
          <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-4">
            Metadata
          </h3>

          <div className="space-y-4">
            {/* Status and Priority Row */}
            <div className="flex items-center gap-3 flex-wrap">
              <span
                className={`text-xs font-bold px-2.5 py-1 rounded-lg uppercase ${statusStyle.bg} ${statusStyle.text} border ${statusStyle.border}`}
              >
                {getStatusLabel(requirement.status)}
              </span>
              <span
                className={`text-xs font-bold px-2.5 py-1 rounded-lg uppercase ${priorityStyle.bg} ${priorityStyle.text} border ${priorityStyle.border}`}
              >
                {requirement.priority}
              </span>
              <span className="text-xs font-mono text-slate-600">
                Updated: {requirement.updated_at}
              </span>
            </div>

            {/* Labels */}
            {requirement.labels && requirement.labels.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {requirement.labels.map((label) => (
                  <span
                    key={label}
                    className="text-xs font-mono text-slate-500 bg-slate-800/50 border border-slate-700/50 px-2 py-1 rounded-lg"
                  >
                    #{label}
                  </span>
                ))}
              </div>
            )}

            {/* Dependencies - Color-coded with status badges */}
            {requirement.depends_on && requirement.depends_on.length > 0 && (
              <div className="space-y-2">
                <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">Dependencies</span>
                <div className="space-y-1.5">
                  {getAllDependenciesWithStatus(requirement, allRequirements).map(({ requirement: dep, isComplete }) => (
                    <div
                      key={dep.id}
                      className="flex items-center gap-2 p-2 rounded-lg theme-bg-elevated hover:bg-slate-800/60 cursor-pointer transition-colors"
                      onClick={(e) => {
                        e.stopPropagation();
                        // Could navigate to the dependency - for now just log
                        console.log(`Navigate to dependency: ${dep.id}`);
                      }}
                      title={`${dep.id}: ${dep.title}`}
                    >
                      {/* Status icon */}
                      <span className="text-sm">
                        {isComplete ? '✓' : '⚠️'}
                      </span>
                      
                      {/* Requirement info */}
                      <div className="flex-1 min-w-0">
                        <div className="text-xs font-mono theme-text-primary">{dep.id}</div>
                        <div className="text-[10px] theme-text-muted truncate">{dep.title}</div>
                      </div>
                      
                      {/* Status badge */}
                      <span
                        className={`text-[9px] font-bold px-2 py-1 rounded uppercase whitespace-nowrap ${
                          isComplete
                            ? 'bg-green-500/20 text-green-400 border border-green-500/30'
                            : 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                        }`}
                      >
                        {dep.status}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Last Run Info */}
            {requirement.last_run_id && (
              <div className="mt-4 p-3 theme-bg-elevated border theme-border rounded-lg">
                <div className="text-xs text-slate-500 mb-1">Last Run</div>
                <div className="text-sm font-mono text-slate-300">
                  {requirement.last_run_id}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Specification Section */}
        <div className="p-6">
          <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-4">
            Specification
          </h3>

          {specLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-2 border-brand-500/30 border-t-brand-500 rounded-full animate-spin" />
            </div>
          ) : specError ? (
            <div className="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 text-sm text-red-400">
              {specError}
            </div>
          ) : specHtml ? (
            <div
              className="prose prose-invert prose-sm max-w-none
                prose-headings:text-slate-200 prose-headings:font-bold
                prose-p:text-slate-400 prose-p:leading-relaxed
                prose-a:text-brand-400 prose-a:no-underline hover:prose-a:underline
                prose-code:text-amber-400 prose-code:bg-slate-800/50 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded
                prose-pre:theme-bg-elevated prose-pre:border prose-pre:theme-border
                prose-li:text-slate-400
                prose-strong:text-slate-200
                prose-blockquote:border-l-brand-500 prose-blockquote:text-slate-400"
              dangerouslySetInnerHTML={{ __html: specHtml }}
            />
          ) : (
            <div className="text-center py-12 text-slate-600">
              <span className="text-2xl">📄</span>
              <p className="mt-2 text-xs">No specification available</p>
            </div>
          )}
        </div>
      </div>
    );
  };

  // Render Run History tab content with master-detail layout
  const renderHistoryTab = () => {
    return (
      <div className="h-full flex">
        {/* Master List (left side, ~40% width) */}
        <div className="w-[40%] border-r theme-border flex flex-col">
          <div className="p-3 border-b theme-border">
            <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider">
              Runs
            </h3>
          </div>

          <div className="flex-1 overflow-y-auto custom-scrollbar">
            {historyLoading ? (
              <div className="flex items-center justify-center py-12">
                <div className="w-6 h-6 border-2 border-brand-500/30 border-t-brand-500 rounded-full animate-spin" />
              </div>
            ) : historyError ? (
              <div className="p-4">
                <div className="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 text-sm text-red-400">
                  {historyError}
                </div>
              </div>
            ) : runHistory.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-center p-6">
                <span className="text-2xl mb-2">🕐</span>
                <h4 className="text-sm font-bold text-slate-400 mb-1">
                  No Runs
                </h4>
                <p className="text-xs text-slate-600">
                  No runs found for this requirement.
                </p>
              </div>
            ) : (
              <div className="p-2 space-y-1">
                {runHistory.map((run) => (
                  <RunCard
                    key={run.run_id}
                    run={run}
                    isSelected={run.run_id === selectedRunId}
                    onClick={handleSelectRun}
                  />
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Detail Panel (right side, ~60% width) */}
        <div className="w-[60%] flex flex-col">
          {!selectedRunId ? (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📭</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">
                Select a Run
              </h3>
              <p className="text-xs text-slate-600 max-w-md">
                Click on a run from the list to view its artifacts.
              </p>
            </div>
          ) : (
            <RunArtifactViewer projectId={projectId} runId={selectedRunId} />
          )}
        </div>
      </div>
    );
  };

  // Render tab content based on active tab
  const renderTabContent = () => {
    switch (activeTab) {
      case "overview":
        return renderOverviewTab();
      case "history":
        return renderHistoryTab();
      default:
        return null;
    }
  };

  return (
    <>
      {/* Backdrop */}
      <div
        className={`fixed inset-0 bg-black/50 z-40 transition-opacity duration-300 ${
          isOpen ? "opacity-100" : "opacity-0 pointer-events-none"
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
          ${isOpen ? "translate-x-0" : "translate-x-full"}
          
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
            <span className="text-sm font-mono font-bold text-brand-400 bg-brand-500/10 px-2.5 py-1 rounded-lg border border-brand-500/20">
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
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="h-12 border-b theme-border flex items-center px-4 gap-1 flex-shrink-0 theme-bg-deep overflow-x-auto">
          {TOP_LEVEL_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`
                px-4 py-1.5 text-xs font-bold rounded-md transition-all flex items-center gap-2 whitespace-nowrap
                ${
                  activeTab === tab.id
                    ? "bg-slate-800 text-brand-400 shadow-sm"
                    : "text-slate-500 hover:text-slate-400"
                }
              `}
              aria-selected={activeTab === tab.id}
              role="tab"
            >
              <span>{tab.icon}</span>
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-hidden">{renderTabContent()}</div>

        {/* Footer with keyboard hint */}
        <div className="h-10 border-t theme-border flex items-center px-6 justify-between flex-shrink-0 theme-bg-deep">
          <span className="text-[10px] text-slate-600">
            Press{" "}
            <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono">
              ESC
            </kbd>{" "}
            to close
          </span>
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-slate-600">
              <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono">
                ←
              </kbd>
              <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono ml-1">
                →
              </kbd>{" "}
              to switch tabs
            </span>
          </div>
        </div>
      </div>
    </>
  );
};

export default RequirementDetailSlideOut;

import React, { useState, useEffect, useCallback, useRef } from "react";
import { felixApi, Requirement, RunHistoryEntry } from "../services/felixApi";
import { marked } from "marked";
import RunArtifactViewer from "./RunArtifactViewer";
import RunCard from "./RunCard";
import { Badge } from "./ui/badge";
import { cn } from "../lib/utils";
import {
  getAllDependenciesWithStatus,
  isDependencyComplete,
  DependencyInfo,
} from "../utils/dependencies";

const getStatusVariant = (status: string) => {
  switch (status.toLowerCase()) {
    case "completed":
    case "complete":
    case "done":
      return "success";
    case "running":
    case "in_progress":
      return "warning";
    case "blocked":
    case "failed":
      return "destructive";
    case "planned":
      return "default";
    default:
      return "secondary";
  }
};

const getPriorityVariant = (priority: string) => {
  switch (priority.toLowerCase()) {
    case "critical":
      return "destructive";
    case "high":
      return "warning";
    case "medium":
      return "default";
    case "low":
    default:
      return "secondary";
  }
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
        console.warn(
          "Failed to fetch requirements for dependency lookup:",
          err,
        );
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
        <div className="p-6 border-b border-[var(--border-muted)]">
          <h3 className="text-xs font-bold text-[var(--text-muted)] uppercase tracking-wider mb-4">
            Metadata
          </h3>

          <div className="space-y-4">
            {/* Status and Priority Row */}
            <div className="flex items-center gap-3 flex-wrap">
              <Badge variant={getStatusVariant(requirement.status)}>
                {getStatusLabel(requirement.status)}
              </Badge>
              <Badge variant={getPriorityVariant(requirement.priority)}>
                {requirement.priority}
              </Badge>
              <span className="text-xs font-mono text-[var(--text-muted)]">
                Updated: {requirement.updated_at}
              </span>
            </div>

            {/* Labels */}
            {requirement.labels && requirement.labels.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {requirement.labels.map((label) => (
                  <Badge
                    key={label}
                    variant="outline"
                    className="text-[var(--text-muted)] border-[var(--border-muted)] bg-[var(--bg-surface-100)]"
                  >
                    #{label}
                  </Badge>
                ))}
              </div>
            )}

            {/* Dependencies - Color-coded with status badges */}
            {requirement.depends_on && requirement.depends_on.length > 0 && (
              <div className="space-y-2">
                <span className="text-xs font-bold text-[var(--text-muted)] uppercase tracking-wider">
                  Dependencies
                </span>
                <div className="space-y-1.5">
                  {getAllDependenciesWithStatus(
                    requirement,
                    allRequirements,
                  ).map(({ requirement: dep, isComplete }) => (
                    <div
                      key={dep.id}
                      className="flex items-center gap-2 p-2 rounded-lg bg-[var(--bg-surface-100)] hover:bg-[var(--bg-surface-200)] cursor-pointer transition-colors"
                      onClick={(e) => {
                        e.stopPropagation();
                        // Could navigate to the dependency - for now just log
                        console.log(`Navigate to dependency: ${dep.id}`);
                      }}
                      title={`${dep.id}: ${dep.title}`}
                    >
                      {/* Status icon */}
                      <span className="text-sm">{isComplete ? "✓" : "⚠️"}</span>

                      {/* Requirement info */}
                      <div className="flex-1 min-w-0">
                        <div className="text-xs font-mono text-[var(--text)]">
                          {dep.id}
                        </div>
                        <div className="text-[10px] text-[var(--text-muted)] truncate">
                          {dep.title}
                        </div>
                      </div>

                      {/* Status badge */}
                      <Badge
                        variant={isComplete ? "success" : "warning"}
                        className="py-0.5"
                      >
                        {dep.status}
                      </Badge>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Last Run Info */}
            {requirement.last_run_id && (
              <div className="mt-4 p-3 bg-[var(--bg-surface-100)] border border-[var(--border-muted)] rounded-lg">
                <div className="text-xs text-[var(--text-muted)] mb-1">
                  Last Run
                </div>
                <div className="text-sm font-mono text-[var(--text-light)]">
                  {requirement.last_run_id}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Specification Section */}
        <div className="p-6">
          <h3 className="text-xs font-bold text-[var(--text-muted)] uppercase tracking-wider mb-4">
            Specification
          </h3>

          {specLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-2 border-[var(--brand-500)]/30 border-t-[var(--brand-500)] rounded-full animate-spin" />
            </div>
          ) : specError ? (
            <div className="bg-[var(--destructive-500)]/10 border border-[var(--destructive-500)]/20 rounded-xl px-4 py-3 text-sm text-[var(--destructive-400)]">
              {specError}
            </div>
          ) : specHtml ? (
            <div
              className="prose prose-invert prose-sm max-w-none
                prose-headings:text-[var(--text)] prose-headings:font-bold
                prose-p:text-[var(--text-muted)] prose-p:leading-relaxed
                prose-a:text-[var(--brand-400)] prose-a:no-underline hover:prose-a:underline
                prose-code:text-[var(--warning-400)] prose-code:bg-[var(--bg-surface-200)] prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded
                prose-pre:bg-[var(--bg-surface-100)] prose-pre:border prose-pre:border-[var(--border-muted)]
                prose-li:text-[var(--text-muted)]
                prose-strong:text-[var(--text)]
                prose-blockquote:border-l-[var(--brand-500)] prose-blockquote:text-[var(--text-muted)]"
              dangerouslySetInnerHTML={{ __html: specHtml }}
            />
          ) : (
            <div className="text-center py-12 text-[var(--text-muted)]">
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
        <div className="w-[40%] border-r border-[var(--border-muted)] flex flex-col">
          <div className="p-3 border-b border-[var(--border-muted)]">
            <h3 className="text-xs font-bold text-[var(--text-muted)] uppercase tracking-wider">
              Runs
            </h3>
          </div>

          <div className="flex-1 overflow-y-auto custom-scrollbar">
            {historyLoading ? (
              <div className="flex items-center justify-center py-12">
                <div className="w-6 h-6 border-2 border-[var(--brand-500)]/30 border-t-[var(--brand-500)] rounded-full animate-spin" />
              </div>
            ) : historyError ? (
              <div className="p-4">
                <div className="bg-[var(--destructive-500)]/10 border border-[var(--destructive-500)]/20 rounded-xl px-4 py-3 text-sm text-[var(--destructive-400)]">
                  {historyError}
                </div>
              </div>
            ) : runHistory.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-center p-6">
                <span className="text-2xl mb-2">🕐</span>
                <h4 className="text-sm font-bold text-[var(--text-muted)] mb-1">
                  No Runs
                </h4>
                <p className="text-xs text-[var(--text-muted)]">
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
              <div className="w-16 h-16 bg-[var(--bg-surface-200)] rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📭</span>
              </div>
              <h3 className="text-sm font-bold text-[var(--text-muted)] mb-2">
                Select a Run
              </h3>
              <p className="text-xs text-[var(--text-muted)] max-w-md">
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
        className={cn(
          "fixed inset-0 bg-[var(--bg-overlay)] z-40 transition-opacity duration-300",
          isOpen ? "opacity-100" : "opacity-0 pointer-events-none",
        )}
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Slide-out Panel */}
      <div
        ref={slideOutRef}
        tabIndex={-1}
        className={cn(
          "fixed top-0 right-0 h-full z-50",
          "bg-[var(--bg-base)] border-l border-[var(--border-muted)]",
          "flex flex-col",
          "transition-transform duration-300 ease-out",
          "outline-none",
          "w-[60vw] max-w-[800px] min-w-[500px]",
          isOpen ? "translate-x-0" : "translate-x-full",
          /* Responsive: Full-screen on small devices */
          "max-[768px]:w-full max-[768px]:max-w-none max-[768px]:min-w-0",
        )}
        role="dialog"
        aria-modal="true"
        aria-labelledby="slide-out-title"
      >
        {/* Header */}
        <div className="h-16 border-b border-[var(--border-muted)] flex items-center px-6 justify-between flex-shrink-0 bg-[var(--bg-base)]">
          <div className="flex items-center gap-3 min-w-0">
            <span className="text-sm font-mono font-bold text-[var(--brand-400)] bg-[var(--brand-500)]/10 px-2.5 py-1 rounded-lg border border-[var(--brand-500)]/20">
              {requirement.id}
            </span>
            <h2
              id="slide-out-title"
              className="text-base font-bold text-[var(--text)] truncate"
              title={requirement.title}
            >
              {requirement.title}
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-light)] hover:bg-[var(--bg-surface-200)] transition-colors"
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
        <div className="h-12 border-b border-[var(--border-muted)] flex items-center px-4 gap-1 flex-shrink-0 bg-[var(--bg-surface-100)] overflow-x-auto">
          {TOP_LEVEL_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={cn(
                "px-4 py-1.5 text-xs font-bold rounded-md transition-all flex items-center gap-2 whitespace-nowrap",
                activeTab === tab.id
                  ? "bg-[var(--bg-surface-200)] text-[var(--brand-400)] shadow-sm"
                  : "text-[var(--text-muted)] hover:text-[var(--text-light)]",
              )}
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
        <div className="h-10 border-t border-[var(--border-muted)] flex items-center px-6 justify-between flex-shrink-0 bg-[var(--bg-surface-100)]">
          <span className="text-[10px] text-[var(--text-muted)]">
            Press{" "}
            <kbd className="px-1.5 py-0.5 bg-[var(--bg-surface-200)] rounded text-[var(--text-light)] font-mono">
              ESC
            </kbd>{" "}
            to close
          </span>
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-[var(--text-muted)]">
              <kbd className="px-1.5 py-0.5 bg-[var(--bg-surface-200)] rounded text-[var(--text-light)] font-mono">
                ←
              </kbd>
              <kbd className="px-1.5 py-0.5 bg-[var(--bg-surface-200)] rounded text-[var(--text-light)] font-mono ml-1">
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

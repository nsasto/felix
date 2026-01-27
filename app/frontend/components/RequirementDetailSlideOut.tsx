import React, { useState, useEffect, useCallback, useRef } from "react";
import {
  felixApi,
  Requirement,
  RunHistoryEntry,
} from "../services/felixApi";
import { marked } from "marked";

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

type TabId = "metadata" | "report" | "log" | "plan" | "spec" | "history";

interface TabInfo {
  id: TabId;
  label: string;
  icon: string;
}

const TABS: TabInfo[] = [
  { id: "metadata", label: "Metadata", icon: "📋" },
  { id: "report", label: "Report", icon: "📊" },
  { id: "log", label: "Output Log", icon: "📜" },
  { id: "plan", label: "Plan Snapshot", icon: "📝" },
  { id: "spec", label: "Specification", icon: "📄" },
  { id: "history", label: "History", icon: "🕐" },
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
  // Default tab: Metadata if no last_run_id, Report if last_run_id exists
  const getDefaultTab = (): TabId => {
    return requirement?.last_run_id ? "report" : "metadata";
  };

  const [activeTab, setActiveTab] = useState<TabId>(getDefaultTab());
  
  // Currently selected run for artifact viewing
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  
  // Spec content for Specification tab
  const [specContent, setSpecContent] = useState<string>("");
  const [specLoading, setSpecLoading] = useState(false);
  const [specError, setSpecError] = useState<string | null>(null);
  
  // Artifact content for Report, Log, Plan tabs
  const [artifactContent, setArtifactContent] = useState<string>("");
  const [artifactLoading, setArtifactLoading] = useState(false);
  const [artifactError, setArtifactError] = useState<string | null>(null);
  const [parsedHtml, setParsedHtml] = useState<string>("");

  // History state
  const [runHistory, setRunHistory] = useState<RunHistoryEntry[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);

  const slideOutRef = useRef<HTMLDivElement>(null);
  const isOpen = requirement !== null;

  // Reset state when requirement changes
  useEffect(() => {
    if (requirement) {
      const defaultTab = requirement.last_run_id ? "report" : "metadata";
      setActiveTab(defaultTab);
      setSelectedRunId(requirement.last_run_id || null);
      setSpecContent("");
      setArtifactContent("");
      setParsedHtml("");
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

  // Fetch artifact content when tab or selected run changes
  useEffect(() => {
    if (!requirement || !selectedRunId) {
      setArtifactContent("");
      setParsedHtml("");
      return;
    }

    // Only fetch for artifact tabs
    if (activeTab !== "report" && activeTab !== "log" && activeTab !== "plan") {
      return;
    }

    const fetchArtifact = async () => {
      setArtifactLoading(true);
      setArtifactError(null);
      setArtifactContent("");

      try {
        let filename: string;
        switch (activeTab) {
          case "report":
            filename = "report.md";
            break;
          case "log":
            filename = "output.log";
            break;
          case "plan":
            filename = `plan-${requirement.id}.md`;
            break;
          default:
            return;
        }

        const result = await felixApi.getRunArtifact(
          projectId,
          selectedRunId,
          filename,
        );
        setArtifactContent(result.content);
      } catch (err) {
        console.error("Failed to fetch artifact:", err);
        setArtifactError(
          err instanceof Error ? err.message : "Failed to load artifact",
        );
      } finally {
        setArtifactLoading(false);
      }
    };

    fetchArtifact();
  }, [projectId, requirement?.id, selectedRunId, activeTab]);

  // Parse markdown for Report, Plan, and Spec tabs
  useEffect(() => {
    const isMarkdownTab = activeTab === "report" || activeTab === "plan" || activeTab === "spec";
    if (!isMarkdownTab) {
      setParsedHtml("");
      return;
    }

    const content = activeTab === "spec" ? specContent : artifactContent;
    if (!content) {
      setParsedHtml("");
      return;
    }

    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        const result = await marked.parse(content);
        if (isMounted) {
          // Make checkboxes read-only
          const readOnlyHtml = result.replace(
            /(<input type="checkbox"[^>]*)/g,
            '$1 disabled onclick="return false;"',
          );
          setParsedHtml(readOnlyHtml);
        }
      } catch (err) {
        console.error("Markdown parsing error:", err);
        if (isMounted) {
          setParsedHtml(
            `<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`,
          );
        }
      }
    };

    parseMarkdown();
    return () => {
      isMounted = false;
    };
  }, [activeTab, specContent, artifactContent]);

  // Fetch run history when history tab is selected
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
            const currentIndex = TABS.findIndex((t) => t.id === activeTab);
            if (currentIndex > 0) {
              setActiveTab(TABS[currentIndex - 1].id);
            }
          }
          break;
        case "ArrowRight":
          if (
            event.target === document.body ||
            event.target === slideOutRef.current
          ) {
            event.preventDefault();
            const currentIndex = TABS.findIndex((t) => t.id === activeTab);
            if (currentIndex < TABS.length - 1) {
              setActiveTab(TABS[currentIndex + 1].id);
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
      return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch {
      return dateString;
    }
  };

  const getStatusLabel = (status: string) => {
    return status.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  };

  const handleSelectRun = (runId: string) => {
    setSelectedRunId(runId);
    // Switch to report tab to show the selected run's artifacts
    setActiveTab("report");
  };

  // Don't render anything if no requirement selected
  if (!requirement) return null;

  const statusStyle = STATUS_STYLES[requirement.status] || STATUS_STYLES.draft;
  const priorityStyle =
    PRIORITY_STYLES[requirement.priority] || PRIORITY_STYLES.medium;

  // Render tab content
  const renderTabContent = () => {
    switch (activeTab) {
      case "metadata":
        return (
          <div className="p-6">
            {/* Metadata Section */}
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

              {/* Dependencies */}
              {requirement.depends_on && requirement.depends_on.length > 0 && (
                <div className="flex items-center gap-2 text-xs">
                  <span className="text-slate-500">Dependencies:</span>
                  <div className="flex flex-wrap gap-1.5">
                    {requirement.depends_on.map((depId) => (
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
        );

      case "report":
      case "plan":
        // Markdown content tabs
        if (!selectedRunId) {
          return (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📭</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">No Run Selected</h3>
              <p className="text-xs text-slate-600 max-w-md">
                Run the Felix agent or select a run from the History tab to view artifacts.
              </p>
            </div>
          );
        }

        if (artifactLoading) {
          return (
            <div className="flex-1 flex flex-col items-center justify-center h-full">
              <div className="w-8 h-8 border-2 border-slate-600/30 border-t-felix-500 rounded-full animate-spin mb-4" />
              <span className="text-xs font-mono text-slate-600 uppercase">Loading artifact...</span>
            </div>
          );
        }

        if (artifactError) {
          return (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📄</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">Artifact Not Found</h3>
              <p className="text-xs text-slate-600 max-w-md">{artifactError}</p>
            </div>
          );
        }

        return (
          <div className="h-full overflow-y-auto custom-scrollbar p-8 markdown-preview">
            {parsedHtml ? (
              <div
                className="max-w-4xl mx-auto prose prose-invert prose-sm
                  prose-headings:text-slate-200 prose-headings:font-bold
                  prose-p:text-slate-400 prose-p:leading-relaxed
                  prose-a:text-felix-400 prose-a:no-underline hover:prose-a:underline
                  prose-code:text-amber-400 prose-code:bg-slate-800/50 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded
                  prose-pre:theme-bg-elevated prose-pre:border prose-pre:theme-border
                  prose-li:text-slate-400
                  prose-strong:text-slate-200
                  prose-blockquote:border-l-felix-500 prose-blockquote:text-slate-400"
                dangerouslySetInnerHTML={{ __html: parsedHtml }}
              />
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                <span className="text-4xl opacity-30">📋</span>
                <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                  No content available
                </span>
              </div>
            )}
          </div>
        );

      case "log":
        // Output log tab
        if (!selectedRunId) {
          return (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📭</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">No Run Selected</h3>
              <p className="text-xs text-slate-600 max-w-md">
                Run the Felix agent or select a run from the History tab to view output logs.
              </p>
            </div>
          );
        }

        if (artifactLoading) {
          return (
            <div className="flex-1 flex flex-col items-center justify-center h-full">
              <div className="w-8 h-8 border-2 border-slate-600/30 border-t-felix-500 rounded-full animate-spin mb-4" />
              <span className="text-xs font-mono text-slate-600 uppercase">Loading log...</span>
            </div>
          );
        }

        if (artifactError) {
          return (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📜</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">Log Not Found</h3>
              <p className="text-xs text-slate-600 max-w-md">{artifactError}</p>
            </div>
          );
        }

        return (
          <div className="h-full overflow-y-auto custom-scrollbar p-6 theme-bg-deepest">
            <pre className="font-mono text-xs theme-text-tertiary whitespace-pre-wrap leading-relaxed">
              {artifactContent || "No log content available."}
            </pre>
          </div>
        );

      case "spec":
        // Specification tab
        if (specLoading) {
          return (
            <div className="flex-1 flex flex-col items-center justify-center h-full">
              <div className="w-8 h-8 border-2 border-slate-600/30 border-t-felix-500 rounded-full animate-spin mb-4" />
              <span className="text-xs font-mono text-slate-600 uppercase">Loading specification...</span>
            </div>
          );
        }

        if (specError) {
          return (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">📄</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">Specification Not Found</h3>
              <p className="text-xs text-slate-600 max-w-md">{specError}</p>
            </div>
          );
        }

        return (
          <div className="h-full overflow-y-auto custom-scrollbar p-8 markdown-preview">
            {parsedHtml ? (
              <div
                className="max-w-4xl mx-auto prose prose-invert prose-sm
                  prose-headings:text-slate-200 prose-headings:font-bold
                  prose-p:text-slate-400 prose-p:leading-relaxed
                  prose-a:text-felix-400 prose-a:no-underline hover:prose-a:underline
                  prose-code:text-amber-400 prose-code:bg-slate-800/50 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded
                  prose-pre:theme-bg-elevated prose-pre:border prose-pre:theme-border
                  prose-li:text-slate-400
                  prose-strong:text-slate-200
                  prose-blockquote:border-l-felix-500 prose-blockquote:text-slate-400"
                dangerouslySetInnerHTML={{ __html: parsedHtml }}
              />
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                <span className="text-4xl opacity-30">📄</span>
                <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                  No specification available
                </span>
              </div>
            )}
          </div>
        );

      case "history":
        // History tab
        if (historyLoading) {
          return (
            <div className="flex items-center justify-center h-full">
              <div className="w-6 h-6 border-2 border-felix-500/30 border-t-felix-500 rounded-full animate-spin" />
            </div>
          );
        }

        if (historyError) {
          return (
            <div className="p-6">
              <div className="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 text-sm text-red-400">
                {historyError}
              </div>
            </div>
          );
        }

        if (runHistory.length === 0) {
          return (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
                <span className="text-2xl">🕐</span>
              </div>
              <h3 className="text-sm font-bold text-slate-400 mb-2">No Work History</h3>
              <p className="text-xs text-slate-600 max-w-md">
                No runs found for this requirement. Run the Felix agent to see work history here.
              </p>
            </div>
          );
        }

        return (
          <div className="p-6">
            <div className="space-y-3">
              {runHistory.map((run) => {
                const isSelected = run.run_id === selectedRunId;
                const statusColor =
                  run.status === "completed"
                    ? "text-emerald-400"
                    : run.status === "running"
                      ? "text-amber-400"
                      : run.status === "failed"
                        ? "text-red-400"
                        : "text-slate-400";
                const statusBg =
                  run.status === "completed"
                    ? "bg-emerald-500/10 border-emerald-500/20"
                    : run.status === "running"
                      ? "bg-amber-500/10 border-amber-500/20"
                      : run.status === "failed"
                        ? "bg-red-500/10 border-red-500/20"
                        : "bg-slate-500/10 border-slate-500/20";

                return (
                  <button
                    key={run.run_id}
                    onClick={() => handleSelectRun(run.run_id)}
                    className={`
                      w-full text-left px-4 py-3 rounded-xl border transition-all
                      ${isSelected
                        ? "theme-bg-elevated border-felix-500/50 ring-1 ring-felix-500/30"
                        : "theme-bg-elevated theme-border hover:border-slate-600"
                      }
                    `}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span
                          className={`text-xs font-bold px-2 py-0.5 rounded border ${statusBg} ${statusColor} uppercase`}
                        >
                          {run.status}
                        </span>
                        {isSelected && (
                          <span className="text-xs font-bold text-felix-400 bg-felix-500/10 px-2 py-0.5 rounded">
                            SELECTED
                          </span>
                        )}
                      </div>
                      <span className="text-xs text-slate-500 font-mono">
                        PID: {run.pid}
                      </span>
                    </div>

                    <div className="space-y-1 text-xs">
                      <div className="flex justify-between">
                        <span className="text-slate-500">Run ID:</span>
                        <span className="text-slate-300 font-mono truncate ml-2 max-w-[200px]">
                          {run.run_id}
                        </span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-slate-500">Started:</span>
                        <span className="text-slate-300">
                          {formatDate(run.started_at)}
                        </span>
                      </div>
                      {run.ended_at && (
                        <div className="flex justify-between">
                          <span className="text-slate-500">Ended:</span>
                          <span className="text-slate-300">
                            {formatDate(run.ended_at)}
                          </span>
                        </div>
                      )}
                      {run.exit_code !== null && run.exit_code !== undefined && (
                        <div className="flex justify-between">
                          <span className="text-slate-500">Exit Code:</span>
                          <span
                            className={
                              run.exit_code === 0
                                ? "text-emerald-400"
                                : "text-red-400"
                            }
                          >
                            {run.exit_code}
                          </span>
                        </div>
                      )}
                    </div>

                    {run.error_message && (
                      <div className="mt-2 p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-red-400 text-xs">
                        {run.error_message}
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        );

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
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`
                px-3 py-1.5 text-[10px] font-bold rounded-md transition-all flex items-center gap-1.5 whitespace-nowrap
                ${
                  activeTab === tab.id
                    ? "bg-slate-800 text-felix-400 shadow-sm"
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
        <div className="flex-1 overflow-hidden">
          {renderTabContent()}
        </div>

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
            {selectedRunId && (
              <span className="text-[10px] text-slate-600 font-mono truncate max-w-[150px]">
                Run: {selectedRunId}
              </span>
            )}
            <span className="text-[10px] text-slate-600">
              <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono">
                ←
              </kbd>
              <kbd className="px-1.5 py-0.5 bg-slate-800 rounded text-slate-400 font-mono ml-1">
                →
              </kbd>
              to switch tabs
            </span>
          </div>
        </div>
      </div>
    </>
  );
};

export default RequirementDetailSlideOut;

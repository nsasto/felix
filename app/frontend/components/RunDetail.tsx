import React, { useState, useEffect, useRef, useCallback } from "react";
import { marked } from "marked";
import { PageLoading } from "./ui/page-loading";
import { Button } from "./ui/button";
import { getRunFiles, getRunFile, getRunEvents } from "../src/api/client";
import type { RunFile, RunFilesResponse, RunEvent } from "../src/api/types";
import {
  Bot as IconFelix,
  FileText as IconFileText,
  ChevronLeft,
  ChevronDown,
  ChevronRight,
  File as IconFile,
  ScrollText as IconScrollText,
  Clock as IconClock,
  AlertCircle as IconAlertCircle,
  AlertTriangle as IconAlertTriangle,
  Info as IconInfo,
  Bug as IconBug,
  ChevronUp,
} from "lucide-react";
import { cn } from "../lib/utils";

// ============================================================================
// RunDetail Component (S-0063 - Artifact Sync Viewer)
// ============================================================================
// Uses the new database-backed sync endpoints from S-0060:
//   GET /api/runs/{run_id}/files - List files
//   GET /api/runs/{run_id}/files/{path} - Get file content
// ============================================================================

interface RunDetailProps {
  /** The run ID to display (UUID string) */
  runId: string;
  /** Optional callback when close button is clicked */
  onClose?: () => void;
}

/**
 * RunDetail displays run artifacts using the sync API endpoints.
 * Features a split layout with file list sidebar (left) and content viewer (right).
 */
const RunDetail: React.FC<RunDetailProps> = ({ runId, onClose }) => {
  // State for file list
  const [files, setFiles] = useState<RunFile[]>([]);
  const [filesLoading, setFilesLoading] = useState(true);
  const [filesError, setFilesError] = useState<string | null>(null);

  // State for selected file content
  const [selectedFile, setSelectedFile] = useState<RunFile | null>(null);
  const [fileContent, setFileContent] = useState<string>("");
  const [contentLoading, setContentLoading] = useState(false);
  const [contentError, setContentError] = useState<string | null>(null);
  const [parsedHtml, setParsedHtml] = useState<string>("");

  // State for event timeline
  const [events, setEvents] = useState<RunEvent[]>([]);
  const [eventsLoading, setEventsLoading] = useState(false);
  const [eventsError, setEventsError] = useState<string | null>(null);
  const [eventsExpanded, setEventsExpanded] = useState(false);
  const eventTimelineRef = useRef<HTMLDivElement>(null);

  // State for sidebar collapse on mobile
  const [sidebarExpanded, setSidebarExpanded] = useState(true);

  // Ref for sidebar file list container (for keyboard navigation focus)
  const sidebarRef = useRef<HTMLDivElement>(null);

  // Fetch file list on mount
  useEffect(() => {
    const fetchFiles = async () => {
      setFilesLoading(true);
      setFilesError(null);

      try {
        const response = await getRunFiles(runId);
        setFiles(response.files);

        // Auto-select first file (prioritize report.md, then plan.md)
        if (response.files.length > 0) {
          const reportFile = response.files.find((f) => f.path === "report.md");
          const planFile = response.files.find(
            (f) => f.path.includes("plan") && f.path.endsWith(".md"),
          );
          const defaultFile = reportFile || planFile || response.files[0];
          setSelectedFile(defaultFile);
        }
      } catch (err) {
        console.error("Failed to fetch run files:", err);
        setFilesError(
          err instanceof Error ? err.message : "Failed to load run files",
        );
      } finally {
        setFilesLoading(false);
      }
    };

    fetchFiles();
  }, [runId]);

  // Fetch content when selected file changes
  useEffect(() => {
    if (!selectedFile) {
      setFileContent("");
      setParsedHtml("");
      return;
    }

    const fetchContent = async () => {
      setContentLoading(true);
      setContentError(null);

      try {
        const content = await getRunFile(runId, selectedFile.path);
        setFileContent(content);
      } catch (err) {
        console.error("Failed to fetch file content:", err);
        setContentError(
          err instanceof Error ? err.message : "Failed to load file content",
        );
        setFileContent("");
      } finally {
        setContentLoading(false);
      }
    };

    fetchContent();
  }, [runId, selectedFile]);

  // Fetch events when expanded
  useEffect(() => {
    if (!eventsExpanded) return;

    const fetchEvents = async () => {
      setEventsLoading(true);
      setEventsError(null);

      try {
        const response = await getRunEvents(runId, undefined, 100);
        setEvents(response.events);
      } catch (err) {
        console.error("Failed to fetch run events:", err);
        setEventsError(
          err instanceof Error ? err.message : "Failed to load events",
        );
      } finally {
        setEventsLoading(false);
      }
    };

    fetchEvents();
  }, [runId, eventsExpanded]);

  // Auto-scroll to bottom when events change
  useEffect(() => {
    if (eventsExpanded && eventTimelineRef.current && events.length > 0) {
      eventTimelineRef.current.scrollTop =
        eventTimelineRef.current.scrollHeight;
    }
  }, [events, eventsExpanded]);

  // Parse markdown content when file content changes
  useEffect(() => {
    if (!selectedFile || !fileContent) {
      setParsedHtml("");
      return;
    }

    // Only parse markdown files
    if (!selectedFile.path.endsWith(".md")) {
      setParsedHtml("");
      return;
    }

    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        const result = await marked.parse(fileContent);
        if (isMounted) setParsedHtml(result);
      } catch (err) {
        console.error("Markdown rendering error:", err);
        if (isMounted) {
          setParsedHtml(
            `<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`,
          );
        }
      }
    };

    const timeout = setTimeout(parseMarkdown, 50);
    return () => {
      isMounted = false;
      clearTimeout(timeout);
    };
  }, [fileContent, selectedFile]);

  // Group files by kind (artifacts first, then logs)
  const groupedFiles = React.useMemo(() => {
    const artifacts = files.filter((f) => f.kind === "artifact");
    const logs = files.filter((f) => f.kind === "log");
    const other = files.filter(
      (f) => f.kind !== "artifact" && f.kind !== "log",
    );
    return { artifacts, logs, other };
  }, [files]);

  // Flat list of files for keyboard navigation (in display order)
  const flatFileList = React.useMemo(() => {
    return [
      ...groupedFiles.artifacts,
      ...groupedFiles.logs,
      ...groupedFiles.other,
    ];
  }, [groupedFiles]);

  // Keyboard navigation handler for file list
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (!flatFileList.length) return;

      const currentIndex = selectedFile
        ? flatFileList.findIndex((f) => f.path === selectedFile.path)
        : -1;

      switch (e.key) {
        case "ArrowDown":
        case "j": // vim-style navigation
          e.preventDefault();
          if (currentIndex < flatFileList.length - 1) {
            setSelectedFile(flatFileList[currentIndex + 1]);
          } else if (currentIndex === -1 && flatFileList.length > 0) {
            setSelectedFile(flatFileList[0]);
          }
          break;
        case "ArrowUp":
        case "k": // vim-style navigation
          e.preventDefault();
          if (currentIndex > 0) {
            setSelectedFile(flatFileList[currentIndex - 1]);
          }
          break;
        case "Home":
          e.preventDefault();
          if (flatFileList.length > 0) {
            setSelectedFile(flatFileList[0]);
          }
          break;
        case "End":
          e.preventDefault();
          if (flatFileList.length > 0) {
            setSelectedFile(flatFileList[flatFileList.length - 1]);
          }
          break;
      }
    },
    [flatFileList, selectedFile],
  );

  // Format file size
  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  // Format event timestamp
  const formatEventTime = (ts: string): string => {
    try {
      const date = new Date(ts);
      return date.toLocaleTimeString("en-US", {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: false,
      });
    } catch {
      return ts;
    }
  };

  // Get event level styles
  const getEventLevelStyles = (level: string) => {
    switch (level.toLowerCase()) {
      case "error":
        return {
          icon: IconAlertCircle,
          textColor: "text-red-400",
          bgColor: "bg-red-500/10",
          borderColor: "border-red-500/30",
        };
      case "warn":
      case "warning":
        return {
          icon: IconAlertTriangle,
          textColor: "text-amber-400",
          bgColor: "bg-amber-500/10",
          borderColor: "border-amber-500/30",
        };
      case "debug":
        return {
          icon: IconBug,
          textColor: "text-gray-400",
          bgColor: "bg-gray-500/10",
          borderColor: "border-gray-500/30",
        };
      case "info":
      default:
        return {
          icon: IconInfo,
          textColor: "text-blue-400",
          bgColor: "bg-blue-500/10",
          borderColor: "border-blue-500/30",
        };
    }
  };

  // Get file icon based on extension
  const getFileIcon = (path: string) => {
    if (path.endsWith(".md")) return IconFileText;
    if (path.endsWith(".log")) return IconScrollText;
    return IconFile;
  };

  // Render file list section
  const renderFileList = (title: string, fileList: RunFile[]) => {
    if (fileList.length === 0) return null;

    return (
      <div className="mb-4">
        <h3 className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2 px-3">
          {title}
        </h3>
        <div className="space-y-1">
          {fileList.map((file) => {
            const FileIcon = getFileIcon(file.path);
            const isSelected = selectedFile?.path === file.path;

            return (
              <button
                key={file.path}
                onClick={() => setSelectedFile(file)}
                className={cn(
                  "w-full px-3 py-2 text-left rounded-lg transition-all flex items-center gap-2",
                  isSelected
                    ? "bg-[var(--brand-500)]/10 border border-[var(--brand-500)]/30"
                    : "hover:bg-[var(--bg-surface-200)] border border-transparent",
                )}
              >
                <FileIcon
                  className={cn(
                    "w-4 h-4 flex-shrink-0",
                    isSelected
                      ? "text-[var(--brand-400)]"
                      : "text-[var(--text-muted)]",
                  )}
                />
                <div className="flex-1 min-w-0">
                  <p
                    className={cn(
                      "text-xs font-medium truncate",
                      isSelected
                        ? "text-[var(--brand-400)]"
                        : "text-[var(--text-light)]",
                    )}
                  >
                    {file.path}
                  </p>
                  <p className="text-[10px] text-[var(--text-muted)]">
                    {formatFileSize(file.size_bytes)}
                  </p>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    );
  };

  // Render event timeline panel
  const renderEventTimeline = () => {
    return (
      <div className="border-t border-[var(--border)] mt-2">
        {/* Collapsible header */}
        <button
          onClick={() => setEventsExpanded(!eventsExpanded)}
          className="w-full px-3 py-2 flex items-center gap-2 hover:bg-[var(--bg-surface-200)] transition-colors"
        >
          {eventsExpanded ? (
            <ChevronDown className="w-3 h-3 text-[var(--text-muted)]" />
          ) : (
            <ChevronRight className="w-3 h-3 text-[var(--text-muted)]" />
          )}
          <IconClock className="w-3 h-3 text-[var(--text-muted)]" />
          <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
            Events
          </span>
          {events.length > 0 && (
            <span className="ml-auto text-[9px] text-[var(--text-muted)] bg-[var(--bg-surface-200)] px-1.5 py-0.5 rounded">
              {events.length}
            </span>
          )}
        </button>

        {/* Expanded event list */}
        {eventsExpanded && (
          <div
            ref={eventTimelineRef}
            className="max-h-64 overflow-y-auto custom-scrollbar px-2 pb-2"
          >
            {eventsLoading ? (
              <div className="py-4 text-center">
                <div className="w-4 h-4 border-2 border-[var(--brand-500)] border-t-transparent rounded-full animate-spin mx-auto mb-2" />
                <p className="text-[10px] text-[var(--text-muted)]">
                  Loading events...
                </p>
              </div>
            ) : eventsError ? (
              <div className="py-4 text-center">
                <IconAlertCircle className="w-4 h-4 text-red-400 mx-auto mb-1" />
                <p className="text-[10px] text-red-400">{eventsError}</p>
              </div>
            ) : events.length === 0 ? (
              <div className="py-4 text-center">
                <p className="text-[10px] text-[var(--text-muted)]">
                  No events recorded
                </p>
              </div>
            ) : (
              <div className="space-y-1.5 pt-1">
                {events.map((event) => {
                  const levelStyles = getEventLevelStyles(event.level);
                  const LevelIcon = levelStyles.icon;

                  return (
                    <div
                      key={event.id}
                      className={cn(
                        "px-2 py-1.5 rounded border text-[10px]",
                        levelStyles.bgColor,
                        levelStyles.borderColor,
                      )}
                    >
                      <div className="flex items-start gap-1.5">
                        <LevelIcon
                          className={cn(
                            "w-3 h-3 flex-shrink-0 mt-0.5",
                            levelStyles.textColor,
                          )}
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-0.5">
                            <span
                              className={cn(
                                "font-medium",
                                levelStyles.textColor,
                              )}
                            >
                              {event.type}
                            </span>
                            <span className="text-[var(--text-muted)] ml-auto">
                              {formatEventTime(event.ts)}
                            </span>
                          </div>
                          {event.message && (
                            <p className="text-[var(--text-light)] break-words">
                              {event.message}
                            </p>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>
    );
  };

  // Render content viewer
  const renderContentViewer = () => {
    if (contentLoading) {
      return (
        <div className="flex-1 flex items-center justify-center">
          <PageLoading message="Loading file..." size="md" fullPage={false} />
        </div>
      );
    }

    if (contentError) {
      return (
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <IconFileText className="w-12 h-12 text-[var(--text-muted)] opacity-20 mb-4" />
          <h3 className="text-sm font-bold text-[var(--text-light)] mb-2">
            Failed to Load File
          </h3>
          <p className="text-xs text-[var(--text-muted)] max-w-md">
            {contentError}
          </p>
        </div>
      );
    }

    if (!selectedFile) {
      return (
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <IconFelix className="w-12 h-12 text-[var(--text-muted)] opacity-20 mb-4" />
          <p className="text-xs text-[var(--text-muted)]">
            Select a file to view its content
          </p>
        </div>
      );
    }

    // Markdown files
    if (selectedFile.path.endsWith(".md") && parsedHtml) {
      return (
        <div
          className="max-w-4xl mx-auto markdown-preview"
          dangerouslySetInnerHTML={{ __html: parsedHtml }}
        />
      );
    }

    // Log files and other text files
    if (selectedFile.path.endsWith(".log")) {
      return (
        <pre className="font-mono text-xs text-[var(--text-tertiary)] whitespace-pre-wrap leading-relaxed">
          {fileContent || "No content available."}
        </pre>
      );
    }

    // Default: pre-formatted code
    return (
      <pre className="font-mono text-xs text-[var(--text-light)] whitespace-pre-wrap leading-relaxed bg-[var(--bg-surface-100)] p-4 rounded-lg border border-[var(--border)]">
        {fileContent || "No content available."}
      </pre>
    );
  };

  // Loading state - files list loading
  if (filesLoading) {
    return (
      <div className="flex-1 flex flex-col bg-[var(--bg-base)]">
        {/* Header */}
        {onClose && (
          <div className="h-14 border-b border-[var(--border)] flex items-center px-6 justify-between bg-[var(--bg-base)]/95 backdrop-blur">
            <div className="flex items-center gap-4">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={onClose}
                className="p-2 h-9 w-9 hover:bg-[var(--bg-surface-200)] rounded-lg transition-all text-[var(--text-muted)] hover:text-[var(--text-light)]"
              >
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <div>
                <h2 className="text-sm font-bold text-[var(--text-light)]">
                  Run Artifacts
                </h2>
                <p className="text-[10px] font-mono text-[var(--text-muted)] truncate max-w-md">
                  {runId}
                </p>
              </div>
            </div>
          </div>
        )}
        <PageLoading message="Loading run files..." />
      </div>
    );
  }

  // Error state - files list failed to load
  if (filesError) {
    return (
      <div className="flex-1 flex flex-col bg-[var(--bg-base)]">
        {/* Header */}
        {onClose && (
          <div className="h-14 border-b border-[var(--border)] flex items-center px-6 justify-between bg-[var(--bg-base)]/95 backdrop-blur">
            <div className="flex items-center gap-4">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={onClose}
                className="p-2 h-9 w-9 hover:bg-[var(--bg-surface-200)] rounded-lg transition-all text-[var(--text-muted)] hover:text-[var(--text-light)]"
              >
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <div>
                <h2 className="text-sm font-bold text-[var(--text-light)]">
                  Run Artifacts
                </h2>
                <p className="text-[10px] font-mono text-[var(--text-muted)] truncate max-w-md">
                  {runId}
                </p>
              </div>
            </div>
          </div>
        )}
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <IconFileText className="w-12 h-12 text-[var(--text-muted)] opacity-20 mb-4" />
          <h3 className="text-sm font-bold text-[var(--text-light)] mb-2">
            Run Not Found
          </h3>
          <p className="text-xs text-[var(--text-muted)] max-w-md">
            {filesError}
          </p>
        </div>
      </div>
    );
  }

  // Empty state - no files found
  if (files.length === 0) {
    return (
      <div className="flex-1 flex flex-col bg-[var(--bg-base)]">
        {/* Header */}
        {onClose && (
          <div className="h-14 border-b border-[var(--border)] flex items-center px-6 justify-between bg-[var(--bg-base)]/95 backdrop-blur">
            <div className="flex items-center gap-4">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={onClose}
                className="p-2 h-9 w-9 hover:bg-[var(--bg-surface-200)] rounded-lg transition-all text-[var(--text-muted)] hover:text-[var(--text-light)]"
              >
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <div>
                <h2 className="text-sm font-bold text-[var(--text-light)]">
                  Run Artifacts
                </h2>
                <p className="text-[10px] font-mono text-[var(--text-muted)] truncate max-w-md">
                  {runId}
                </p>
              </div>
            </div>
          </div>
        )}
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
          <IconFelix className="w-12 h-12 text-[var(--text-muted)] opacity-20 mb-4" />
          <h3 className="text-sm font-bold text-[var(--text-light)] mb-2">
            No Files Found
          </h3>
          <p className="text-xs text-[var(--text-muted)]">
            This run has no artifacts yet.
          </p>
        </div>
      </div>
    );
  }

  // Main layout: sidebar + content viewer
  return (
    <div className="flex-1 flex flex-col bg-[var(--bg-base)] overflow-hidden">
      {/* Header - only show if onClose is provided */}
      {onClose && (
        <div className="h-14 border-b border-[var(--border)] flex items-center px-4 md:px-6 justify-between bg-[var(--bg-base)]/95 backdrop-blur flex-shrink-0">
          <div className="flex items-center gap-3 md:gap-4">
            <Button
              type="button"
              variant="ghost"
              size="icon"
              onClick={onClose}
              className="p-2 h-9 w-9 hover:bg-[var(--bg-surface-200)] rounded-lg transition-all text-[var(--text-muted)] hover:text-[var(--text-light)]"
            >
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <div>
              <h2 className="text-sm font-bold text-[var(--text-light)]">
                Run Artifacts
              </h2>
              <p className="text-[10px] font-mono text-[var(--text-muted)] truncate max-w-[200px] md:max-w-md">
                {runId}
              </p>
            </div>
          </div>
          {/* Mobile sidebar toggle */}
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => setSidebarExpanded(!sidebarExpanded)}
            className="p-2 h-9 w-9 hover:bg-[var(--bg-surface-200)] rounded-lg transition-all text-[var(--text-muted)] hover:text-[var(--text-light)] md:hidden"
            aria-label={sidebarExpanded ? "Hide file list" : "Show file list"}
          >
            {sidebarExpanded ? (
              <ChevronUp className="w-4 h-4" />
            ) : (
              <ChevronDown className="w-4 h-4" />
            )}
          </Button>
        </div>
      )}

      {/* Split layout: sidebar + content - responsive: stack on mobile, side-by-side on desktop */}
      <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
        {/* Sidebar - file list + event timeline */}
        {/* On mobile: collapsible above content. On desktop: fixed width sidebar */}
        <div
          ref={sidebarRef}
          tabIndex={0}
          onKeyDown={handleKeyDown}
          className={cn(
            "flex-shrink-0 border-b md:border-b-0 md:border-r border-[var(--border)] flex flex-col bg-[var(--bg-base)] transition-all duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--brand-500)]",
            // Mobile: collapsible with max-height
            sidebarExpanded
              ? "max-h-[50vh] md:max-h-none"
              : "max-h-0 md:max-h-none overflow-hidden md:overflow-visible",
            // Desktop: fixed width
            "md:w-64",
          )}
          aria-label="File list navigation. Use arrow keys to navigate files."
        >
          {/* File list area - scrollable */}
          <div className="flex-1 overflow-y-auto custom-scrollbar py-4">
            {renderFileList("Artifacts", groupedFiles.artifacts)}
            {renderFileList("Logs", groupedFiles.logs)}
            {renderFileList("Other", groupedFiles.other)}
          </div>
          {/* Event timeline - at bottom of sidebar */}
          {renderEventTimeline()}
        </div>

        {/* Content viewer */}
        <div className="flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {/* File path header */}
          {selectedFile && (
            <div className="mb-4 pb-3 border-b border-[var(--border)]">
              <h3 className="text-sm font-semibold text-[var(--text-light)] break-all">
                {selectedFile.path}
              </h3>
              <p className="text-[10px] text-[var(--text-muted)]">
                {formatFileSize(selectedFile.size_bytes)} •{" "}
                {selectedFile.content_type || "text/plain"}
              </p>
            </div>
          )}
          {renderContentViewer()}
        </div>
      </div>
    </div>
  );
};

export default RunDetail;

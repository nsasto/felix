import React, { useState, useEffect } from "react";
import { marked } from "marked";
import { PageLoading } from "./ui/page-loading";
import { Button } from "./ui/button";
import {
  getRunFiles,
  getRunFile,
} from "../src/api/client";
import type { RunFile, RunFilesResponse } from "../src/api/types";
import {
  Bot as IconFelix,
  FileText as IconFileText,
  ChevronLeft,
  File as IconFile,
  ScrollText as IconScrollText,
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
          const planFile = response.files.find((f) =>
            f.path.includes("plan") && f.path.endsWith(".md")
          );
          const defaultFile = reportFile || planFile || response.files[0];
          setSelectedFile(defaultFile);
        }
      } catch (err) {
        console.error("Failed to fetch run files:", err);
        setFilesError(
          err instanceof Error ? err.message : "Failed to load run files"
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
          err instanceof Error ? err.message : "Failed to load file content"
        );
        setFileContent("");
      } finally {
        setContentLoading(false);
      }
    };

    fetchContent();
  }, [runId, selectedFile]);

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
            `<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`
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
    const other = files.filter((f) => f.kind !== "artifact" && f.kind !== "log");
    return { artifacts, logs, other };
  }, [files]);

  // Format file size
  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
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
                    : "hover:bg-[var(--bg-surface-200)] border border-transparent"
                )}
              >
                <FileIcon
                  className={cn(
                    "w-4 h-4 flex-shrink-0",
                    isSelected
                      ? "text-[var(--brand-400)]"
                      : "text-[var(--text-muted)]"
                  )}
                />
                <div className="flex-1 min-w-0">
                  <p
                    className={cn(
                      "text-xs font-medium truncate",
                      isSelected
                        ? "text-[var(--brand-400)]"
                        : "text-[var(--text-light)]"
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
          <div className="w-16 h-16 bg-[var(--bg-surface-200)] rounded-2xl flex items-center justify-center mb-4">
            <IconFileText className="w-8 h-8 text-[var(--text-muted)]" />
          </div>
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
          <div className="w-16 h-16 bg-[var(--bg-surface-200)] rounded-2xl flex items-center justify-center mb-4">
            <IconFileText className="w-8 h-8 text-[var(--text-muted)]" />
          </div>
          <h3 className="text-sm font-bold text-[var(--text-light)] mb-2">
            Run Not Found
          </h3>
          <p className="text-xs text-[var(--text-muted)] max-w-md">{filesError}</p>
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
        <div className="h-14 border-b border-[var(--border)] flex items-center px-6 justify-between bg-[var(--bg-base)]/95 backdrop-blur flex-shrink-0">
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

      {/* Split layout: sidebar + content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Sidebar - file list */}
        <div className="w-64 flex-shrink-0 border-r border-[var(--border)] overflow-y-auto custom-scrollbar py-4 bg-[var(--bg-base)]">
          {renderFileList("Artifacts", groupedFiles.artifacts)}
          {renderFileList("Logs", groupedFiles.logs)}
          {renderFileList("Other", groupedFiles.other)}
        </div>

        {/* Content viewer */}
        <div className="flex-1 overflow-y-auto custom-scrollbar p-6">
          {/* File path header */}
          {selectedFile && (
            <div className="mb-4 pb-3 border-b border-[var(--border)]">
              <h3 className="text-sm font-semibold text-[var(--text-light)]">
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

import React, { useState, useEffect, useCallback } from "react";
import { felixApi } from "../services/felixApi";
import { getRunFile } from "../src/api/client";
import { marked } from "marked";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "./ui/tabs";
import { PageLoading } from "./ui/page-loading";
import { Button } from "./ui/button";
import ErrorBoundary from "./ErrorBoundary";
import {
  Bot as IconFelix,
  FileText as IconFileText,
  ClipboardList as IconClipboardList,
  Scroll as IconScroll,
  Edit as IconEdit,
  ChevronLeft,
  RefreshCw,
  Download,
  FileWarning,
} from "lucide-react";

/** Error types for better error handling */
type ErrorType =
  | "not_found"
  | "load_failed"
  | "large_file"
  | "network"
  | "unknown";

interface RunArtifactViewerProps {
  projectId: string;
  runId: string;
  onClose?: () => void; // Optional - if not provided, header with back button is hidden
}

type ArtifactTab = "report" | "log" | "plan" | "spec";

const SYNC_BASE_URL = "http://localhost:8080/api";

/** Parse error message to determine error type */
function getErrorType(error: Error | string): ErrorType {
  const message = typeof error === "string" ? error : error.message;
  const lowerMessage = message.toLowerCase();

  if (lowerMessage.includes("404") || lowerMessage.includes("not found")) {
    return "not_found";
  }
  if (
    lowerMessage.includes("too large") ||
    lowerMessage.includes("size limit") ||
    lowerMessage.includes("413")
  ) {
    return "large_file";
  }
  if (
    lowerMessage.includes("network") ||
    lowerMessage.includes("fetch") ||
    lowerMessage.includes("failed to fetch")
  ) {
    return "network";
  }
  if (lowerMessage.includes("failed to load")) {
    return "load_failed";
  }
  return "unknown";
}

/** Get user-friendly error message based on error type */
function getErrorMessage(
  errorType: ErrorType,
  filename: string,
): { title: string; description: string } {
  switch (errorType) {
    case "not_found":
      return {
        title: "Artifact Not Found",
        description: `The file "${filename}" does not exist for this run. It may not have been generated yet or the run may have been incomplete.`,
      };
    case "large_file":
      return {
        title: "File Too Large",
        description: `The file "${filename}" is too large to display in the browser. Use the download button to save it locally.`,
      };
    case "network":
      return {
        title: "Unable to Load Artifacts",
        description:
          "A network error occurred while loading the artifact. Please check your connection and try again.",
      };
    case "load_failed":
      return {
        title: "Unable to Load Artifacts",
        description:
          "Failed to load the artifact content. The server may be temporarily unavailable.",
      };
    default:
      return {
        title: "Something Went Wrong",
        description: "An unexpected error occurred while loading the artifact.",
      };
  }
}

const RunArtifactViewerInner: React.FC<RunArtifactViewerProps> = ({
  projectId,
  runId,
  onClose,
}) => {
  const [activeTab, setActiveTab] = useState<ArtifactTab>("report");
  const [content, setContent] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [errorType, setErrorType] = useState<ErrorType>("unknown");
  const [parsedHtml, setParsedHtml] = useState<string>("");
  const [requirementId, setRequirementId] = useState<string | null>(null);
  const [specPath, setSpecPath] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);

  // Fetch requirement ID and spec path from requirement_id.txt
  useEffect(() => {
    const fetchRequirementInfo = async () => {
      try {
        const content = await getRunFile(runId, "requirement_id.txt");
        const reqId = content.trim();
        setRequirementId(reqId);

        // Fetch requirements to get spec_path for this requirement
        if (reqId) {
          try {
            const requirements = await felixApi.getRequirements(projectId);
            const req = requirements.requirements.find((r) => r.id === reqId);
            if (req) {
              setSpecPath(req.spec_path);
            }
          } catch (err) {
            console.error("Failed to fetch requirements:", err);
          }
        }
      } catch (err) {
        console.error("Failed to fetch requirement ID:", err);
        // Not critical - plan and spec tabs just won't work
      }
    };

    fetchRequirementInfo();
  }, [projectId, runId]);

  // Map tab to filename
  const getFilename = (tab: ArtifactTab): string => {
    switch (tab) {
      case "report":
        return "report.md";
      case "log":
        return "output.log";
      case "plan":
        return requirementId ? `plan-${requirementId}.md` : "plan.snapshot.md";
      case "spec":
        return "spec.md"; // Placeholder, will fetch separately
    }
  };

  // Fetch artifact content when tab changes
  const fetchArtifact = useCallback(async () => {
    setLoading(true);
    setError(null);
    setErrorType("unknown");
    setContent("");

    try {
      if (activeTab === "spec" && specPath) {
        // Fetch spec directly from specs directory
        const filename = specPath.split("/").pop() || specPath;
        const result = await felixApi.getSpec(projectId, filename);
        setContent(result.content);
      } else {
        // Fetch from run artifacts
        const filename = getFilename(activeTab);
        const result = await getRunFile(runId, filename);
        setContent(result);
      }
    } catch (err) {
      console.error("Failed to fetch artifact:", err);
      const errorMessage =
        err instanceof Error ? err.message : "Failed to load artifact";
      setError(errorMessage);
      setErrorType(getErrorType(err instanceof Error ? err : errorMessage));
    } finally {
      setLoading(false);
    }
  }, [projectId, runId, activeTab, requirementId, specPath]);

  useEffect(() => {
    fetchArtifact();
  }, [fetchArtifact, retryCount]);

  // Retry handler
  const handleRetry = useCallback(() => {
    setRetryCount((prev) => prev + 1);
  }, []);

  // Get download URL for current artifact
  const getDownloadUrl = useCallback((): string | null => {
    if (activeTab === "spec") {
      return null; // Specs aren't run artifacts, no direct download
    }
    const filename = getFilename(activeTab);
    return `${SYNC_BASE_URL}/runs/${encodeURIComponent(runId)}/files/${encodeURIComponent(filename)}`;
  }, [activeTab, runId, requirementId]);

  // Parse markdown content for report, plan, and spec tabs
  useEffect(() => {
    if (activeTab === "log") {
      setParsedHtml("");
      return;
    }

    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        const result = await marked.parse(content || "");
        if (isMounted) setParsedHtml(result);
      } catch (err) {
        console.error("Markdown rendering error:", err);
        if (isMounted)
          setParsedHtml(
            `<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`,
          );
      }
    };

    const timeout = setTimeout(parseMarkdown, 50);
    return () => {
      isMounted = false;
      clearTimeout(timeout);
    };
  }, [content, activeTab]);

  const tabs: {
    id: ArtifactTab;
    label: string;
    icon: React.ComponentType<{ className?: string }>;
  }[] = [
    { id: "report", label: "Report", icon: IconClipboardList },
    { id: "log", label: "Output Log", icon: IconScroll },
    { id: "plan", label: "Plan Snapshot", icon: IconEdit },
    { id: "spec", label: "Specification", icon: IconFileText },
  ];

  return (
    <Tabs
      value={activeTab}
      onValueChange={(value) => setActiveTab(value as ArtifactTab)}
      className="flex-1 flex flex-col theme-bg-base overflow-hidden"
    >
      {/* Header - only show if onClose is provided */}
      {onClose && (
        <div className="h-14 border-b theme-border flex items-center px-6 justify-between theme-bg-base/95 backdrop-blur">
          <div className="flex items-center gap-4">
            <Button
              type="button"
              variant="ghost"
              size="icon"
              onClick={onClose}
              className="p-2 h-9 w-9 hover:bg-slate-800 rounded-lg transition-all text-slate-500 hover:text-slate-300"
            >
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <div>
              <h2 className="text-sm font-bold text-slate-200">
                Run Artifacts
              </h2>
              <p className="text-[10px] font-mono text-slate-600 truncate max-w-md">
                {runId}
              </p>
            </div>
          </div>

          {/* Tab selector */}
          <TabsList variant="line">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <TabsTrigger
                  key={tab.id}
                  value={tab.id}
                  variant="line"
                  className="px-4 py-1.5 text-[10px] font-bold"
                >
                  <Icon className="w-3 h-3 mr-2" />
                  {tab.label}
                </TabsTrigger>
              );
            })}
          </TabsList>
        </div>
      )}

      {/* Embedded tab bar - only show if onClose is NOT provided */}
      {!onClose && (
        <div className="flex items-center px-6 pt-4 flex-shrink-0 theme-bg-base">
          <TabsList variant="line">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <TabsTrigger
                  key={tab.id}
                  value={tab.id}
                  variant="line"
                  className="px-3 py-1.5 text-xs font-medium"
                >
                  <Icon className="w-3.5 h-3.5 mr-1.5" />
                  {tab.label}
                </TabsTrigger>
              );
            })}
          </TabsList>
        </div>
      )}

      {/* Tab Content Panels */}
      {loading ? (
        <div className="flex-1">
          <PageLoading message="Loading artifact..." />
        </div>
      ) : error ? (
        <div className="flex-1 flex flex-col items-center justify-center h-full text-center p-8">
          {errorType === "not_found" ? (
            <FileWarning className="w-12 h-12 text-slate-600 opacity-20 mb-4" />
          ) : (
            <IconFileText className="w-12 h-12 text-amber-500 opacity-20 mb-4" />
          )}
          <h3 className="text-sm font-bold text-slate-300 mb-2">
            {getErrorMessage(errorType, getFilename(activeTab)).title}
          </h3>
          <p className="text-xs text-slate-500 max-w-md mb-4">
            {getErrorMessage(errorType, getFilename(activeTab)).description}
          </p>

          {/* Action buttons */}
          <div className="flex items-center gap-3">
            {/* Show retry button for recoverable errors */}
            {(errorType === "network" ||
              errorType === "load_failed" ||
              errorType === "unknown") && (
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={handleRetry}
                className="flex items-center gap-2"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                Retry
              </Button>
            )}

            {/* Show download link for large files or as fallback */}
            {(errorType === "large_file" || errorType === "load_failed") &&
              getDownloadUrl() && (
                <a
                  href={getDownloadUrl()!}
                  download={getFilename(activeTab)}
                  className="inline-flex items-center gap-2 h-8 px-3 text-xs font-semibold rounded-md border border-[var(--border-default)] bg-[var(--bg-surface-100)] text-[var(--text-secondary)] hover:bg-[var(--hover-bg)] transition-colors"
                >
                  <Download className="w-3.5 h-3.5" />
                  Download File
                </a>
              )}
          </div>
        </div>
      ) : (
        <>
          <TabsContent
            value="report"
            className="flex-1 overflow-y-auto custom-scrollbar m-0 p-6 markdown-preview"
            forceMount
            hidden={activeTab !== "report"}
          >
            {parsedHtml ? (
              <div
                className="max-w-4xl mx-auto"
                dangerouslySetInnerHTML={{ __html: parsedHtml }}
              />
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                <IconFelix className="w-12 h-12 opacity-10" />
                <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                  No content available
                </span>
              </div>
            )}
          </TabsContent>

          <TabsContent
            value="log"
            className="flex-1 overflow-y-auto custom-scrollbar m-0 p-6"
            forceMount
            hidden={activeTab !== "log"}
          >
            <pre className="font-mono text-xs theme-text-tertiary whitespace-pre-wrap leading-relaxed">
              {content || "No log content available."}
            </pre>
          </TabsContent>

          <TabsContent
            value="plan"
            className="flex-1 overflow-y-auto custom-scrollbar m-0 p-6 markdown-preview"
            forceMount
            hidden={activeTab !== "plan"}
          >
            {parsedHtml ? (
              <div
                className="max-w-4xl mx-auto"
                dangerouslySetInnerHTML={{ __html: parsedHtml }}
              />
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                <IconFelix className="w-12 h-12 opacity-10" />
                <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                  No content available
                </span>
              </div>
            )}
          </TabsContent>

          <TabsContent
            value="spec"
            className="flex-1 overflow-y-auto custom-scrollbar m-0 p-6 markdown-preview"
            forceMount
            hidden={activeTab !== "spec"}
          >
            {parsedHtml ? (
              <div
                className="max-w-4xl mx-auto"
                dangerouslySetInnerHTML={{ __html: parsedHtml }}
              />
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                <IconFelix className="w-12 h-12 opacity-10" />
                <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                  No content available
                </span>
              </div>
            )}
          </TabsContent>
        </>
      )}
    </Tabs>
  );
};

/**
 * RunArtifactViewer wrapped in ErrorBoundary for resilience against render errors.
 * This catches any JavaScript errors that occur during rendering and displays
 * a fallback UI instead of crashing the whole application.
 */
const RunArtifactViewer: React.FC<RunArtifactViewerProps> = (props) => {
  const [errorBoundaryKey, setErrorBoundaryKey] = useState(0);

  const handleErrorBoundaryRetry = useCallback(() => {
    // Reset the ErrorBoundary by changing its key
    setErrorBoundaryKey((prev) => prev + 1);
  }, []);

  return (
    <ErrorBoundary
      key={errorBoundaryKey}
      title="Unable to load artifacts"
      onRetry={handleErrorBoundaryRetry}
      onError={(error, errorInfo) => {
        console.error("RunArtifactViewer ErrorBoundary caught error:", error);
        console.error("Component stack:", errorInfo.componentStack);
      }}
    >
      <RunArtifactViewerInner {...props} />
    </ErrorBoundary>
  );
};

export default RunArtifactViewer;

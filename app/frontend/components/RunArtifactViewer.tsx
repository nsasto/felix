import React, { useState, useEffect } from "react";
import { felixApi, RunArtifactContent } from "../services/felixApi";
import { marked } from "marked";
import { IconFelix, IconFileText } from "./Icons";

interface RunArtifactViewerProps {
  projectId: string;
  runId: string;
  onClose?: () => void; // Optional - if not provided, header with back button is hidden
}

type ArtifactTab = "report" | "log" | "plan" | "spec";

const RunArtifactViewer: React.FC<RunArtifactViewerProps> = ({
  projectId,
  runId,
  onClose,
}) => {
  const [activeTab, setActiveTab] = useState<ArtifactTab>("report");
  const [content, setContent] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [parsedHtml, setParsedHtml] = useState<string>("");
  const [requirementId, setRequirementId] = useState<string | null>(null);
  const [specPath, setSpecPath] = useState<string | null>(null);

  // Fetch requirement ID and spec path from requirement_id.txt
  useEffect(() => {
    const fetchRequirementInfo = async () => {
      try {
        const result = await felixApi.getRunArtifact(
          projectId,
          runId,
          "requirement_id.txt",
        );
        const reqId = result.content.trim();
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
  useEffect(() => {
    const fetchArtifact = async () => {
      setLoading(true);
      setError(null);
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
          const result = await felixApi.getRunArtifact(
            projectId,
            runId,
            filename,
          );
          setContent(result.content);
        }
      } catch (err) {
        console.error("Failed to fetch artifact:", err);
        setError(
          err instanceof Error ? err.message : "Failed to load artifact",
        );
      } finally {
        setLoading(false);
      }
    };

    fetchArtifact();
  }, [projectId, runId, activeTab, requirementId, specPath]);

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

  const tabs: { id: ArtifactTab; label: string; icon: string }[] = [
    { id: "report", label: "Report", icon: "📋" },
    { id: "log", label: "Output Log", icon: "📜" },
    { id: "plan", label: "Plan Snapshot", icon: "📝" },
    { id: "spec", label: "Specification", icon: "📄" },
  ];

  return (
    <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
      {/* Header - only show if onClose is provided */}
      {onClose && (
        <div className="h-14 border-b theme-border flex items-center px-6 justify-between theme-bg-base/95 backdrop-blur">
          <div className="flex items-center gap-4">
            <button
              onClick={onClose}
              className="p-2 hover:bg-slate-800 rounded-lg transition-all text-slate-500 hover:text-slate-300"
            >
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M15 19l-7-7 7-7"
                />
              </svg>
            </button>
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
          <div className="flex bg-slate-900 border border-slate-800 rounded-lg p-0.5">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-1.5 text-[10px] font-bold rounded-md transition-all flex items-center gap-2 ${
                  activeTab === tab.id
                    ? "bg-slate-800 text-brand-400 shadow-sm"
                    : "text-slate-500 hover:text-slate-400"
                }`}
              >
                <span>{tab.icon}</span>
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Embedded tab bar - only show if onClose is NOT provided */}
      {!onClose && (
        <div className="h-10 border-b theme-border flex items-center px-3 gap-1 flex-shrink-0 theme-bg-deep">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`
                px-3 py-1 text-[10px] font-bold rounded-md transition-all flex items-center gap-1.5
                ${
                  activeTab === tab.id
                    ? "bg-slate-800 text-brand-400 shadow-sm"
                    : "text-slate-500 hover:text-slate-400"
                }
              `}
            >
              <span>{tab.icon}</span>
              {tab.label}
            </button>
          ))}
        </div>
      )}

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {loading ? (
          <div className="flex-1 flex flex-col items-center justify-center h-full">
            <div className="w-8 h-8 border-2 border-slate-600/30 border-t-brand-500 rounded-full animate-spin mb-4" />
            <span className="text-xs font-mono text-slate-600 uppercase">
              Loading artifact...
            </span>
          </div>
        ) : error ? (
          <div className="flex-1 flex flex-col items-center justify-center h-full text-center p-8">
            <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4">
              <IconFileText className="w-8 h-8 text-slate-600" />
            </div>
            <h3 className="text-sm font-bold text-slate-400 mb-2">
              Artifact Not Found
            </h3>
            <p className="text-xs text-slate-600 max-w-md">{error}</p>
          </div>
        ) : activeTab === "log" ? (
          // Log view - monospace text
          <div className="h-full overflow-y-auto custom-scrollbar p-6 theme-bg-deepest">
            <pre className="font-mono text-xs theme-text-tertiary whitespace-pre-wrap leading-relaxed">
              {content || "No log content available."}
            </pre>
          </div>
        ) : (
          // Markdown view - rendered HTML
          <div className="h-full overflow-y-auto custom-scrollbar p-8 markdown-preview">
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
          </div>
        )}
      </div>
    </div>
  );
};

export default RunArtifactViewer;

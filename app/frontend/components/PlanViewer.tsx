import React, { useState, useEffect, useRef } from "react";
import { felixApi } from "../services/felixApi";
import { marked } from "marked";
import { IconFileText } from "./Icons";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Textarea } from "./ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";

interface PlanViewerProps {
  projectId: string;
  onPlanUpdate?: () => void;
  onBack?: () => void;
}

type ViewMode = "view" | "edit";

const PlanViewer: React.FC<PlanViewerProps> = ({
  projectId,
  onPlanUpdate,
  onBack,
}) => {
  // Plan content state
  const [planContent, setPlanContent] = useState<string>("");
  const [originalContent, setOriginalContent] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);

  // View mode and parsed markdown
  const [viewMode, setViewMode] = useState<ViewMode>("view");
  const [parsedHtml, setParsedHtml] = useState<string>("");

  const editorRef = useRef<HTMLTextAreaElement>(null);

  // Check if content has been modified
  const hasChanges = planContent !== originalContent;

  // Fetch README content on mount or when projectId changes
  useEffect(() => {
    const fetchReadme = async () => {
      setLoading(true);
      setError(null);
      try {
        // Try to fetch README.md from the project root
        const response = await fetch(
          `http://localhost:8080/api/projects/${projectId}/files/README.md`,
        );
        if (!response.ok) {
          throw new Error("README.md not found");
        }
        const data = await response.json();
        setPlanContent(data.content || "");
        setOriginalContent(data.content || "");
      } catch (err) {
        console.error("Failed to fetch README:", err);
        setError(
          err instanceof Error ? err.message : "Failed to load README.md",
        );
        setPlanContent("");
        setOriginalContent("");
      } finally {
        setLoading(false);
      }
    };

    fetchReadme();
  }, [projectId]);

  // Parse markdown for preview
  useEffect(() => {
    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        const result = await marked.parse(planContent || "");
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
  }, [planContent]);

  // Handle save
  const handleSave = async () => {
    if (!hasChanges) return;

    setSaving(true);
    setSaveMessage(null);
    try {
      await felixApi.updatePlan(projectId, planContent);
      setOriginalContent(planContent);
      setSaveMessage({ type: "success", text: "Plan saved successfully" });
      onPlanUpdate?.();

      // Clear success message after 3 seconds
      setTimeout(() => setSaveMessage(null), 3000);
    } catch (err) {
      console.error("Failed to save plan:", err);
      setSaveMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Failed to save",
      });
    } finally {
      setSaving(false);
    }
  };

  // Handle discard changes
  const handleDiscard = () => {
    if (hasChanges) {
      const confirm = window.confirm("Discard all changes?");
      if (!confirm) return;
    }
    setPlanContent(originalContent);
    setViewMode("view");
  };

  // Insert formatting at cursor position (for edit mode)
  const insertFormatting = (prefix: string, suffix: string = "") => {
    if (!editorRef.current) return;
    const textarea = editorRef.current;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const text = textarea.value;
    const selectedText = text.substring(start, end);
    const newContent =
      text.substring(0, start) +
      prefix +
      selectedText +
      suffix +
      text.substring(end);

    setPlanContent(newContent);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + prefix.length, end + prefix.length);
    }, 0);
  };

  // Copy raw content to clipboard
  const copyToClipboard = () => {
    navigator.clipboard.writeText(planContent);
    setSaveMessage({ type: "success", text: "Copied to clipboard" });
    setTimeout(() => setSaveMessage(null), 2000);
  };

  // Render loading state
  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center bg-[var(--bg-base)]">
        <div className="flex items-center gap-3 text-[var(--text-muted)]">
          <div className="w-5 h-5 border-2 border-[var(--border-muted)] border-t-[var(--brand-500)] rounded-full animate-spin" />
          <span className="text-xs font-mono">
            Loading implementation plan...
          </span>
        </div>
      </div>
    );
  }

  // Render error state
  if (error) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center p-8 bg-[var(--bg-base)]">
        <div className="bg-[var(--bg-surface)] border border-[var(--border-muted)] rounded-xl px-6 py-4 max-w-md text-center">
          <div className="w-12 h-12 bg-[var(--bg-surface-200)] rounded-xl flex items-center justify-center mx-auto mb-4">
            <IconFileText className="w-6 h-6 text-[var(--text-muted)]" />
          </div>
          <h3 className="text-sm font-bold text-[var(--text-secondary)] mb-2">
            No Readme
          </h3>
          <p className="text-xs text-[var(--text-muted)] mb-4">{error}</p>
          <p className="text-[10px] text-[var(--text-muted)]">
            README.md file not found in the project root.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col bg-[var(--bg-base)] overflow-hidden">
      {/* Toolbar */}
      <div className="h-12 border-b border-[var(--border-muted)] flex items-center px-4 justify-between bg-[var(--bg-base)]/95 backdrop-blur z-20 flex-shrink-0">
        <div className="flex items-center gap-4">
          {/* Back button */}
          {onBack && (
            <Button variant="ghost" size="icon" onClick={onBack}>
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
            </Button>
          )}

          {/* View mode toggle */}
          <ToggleGroup
            type="single"
            value={viewMode}
            onValueChange={(value) => {
              if (value) setViewMode(value as ViewMode);
            }}
          >
            <ToggleGroupItem value="view">VIEW</ToggleGroupItem>
            <ToggleGroupItem value="edit">EDIT</ToggleGroupItem>
          </ToggleGroup>

          {/* Formatting buttons (only in edit mode) */}
          {viewMode === "edit" && (
            <div
              className="flex items-center gap-0.5 border-l pl-4"
              style={{ borderColor: "var(--border-default)" }}
            >
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("# ")}
                title="H1"
              >
                <span className="font-bold text-xs">H1</span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("## ")}
                title="H2"
              >
                <span className="font-bold text-xs">H2</span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("### ")}
                title="H3"
              >
                <span className="font-bold text-xs">H3</span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("- [ ] ")}
                title="Task Checkbox"
              >
                <svg
                  className="w-3.5 h-3.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M9 12l2 2 4-4"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                  <rect
                    x="3"
                    y="3"
                    width="18"
                    height="18"
                    rx="2"
                    strokeWidth="2"
                  />
                </svg>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("- [x] ")}
                title="Completed Task"
              >
                <svg
                  className="w-3.5 h-3.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <rect
                    x="3"
                    y="3"
                    width="18"
                    height="18"
                    rx="2"
                    fill="currentColor"
                    fillOpacity="0.2"
                    strokeWidth="2"
                  />
                  <path
                    d="M9 12l2 2 4-4"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("- ")}
                title="List"
              >
                <svg
                  className="w-3.5 h-3.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("**", "**")}
                title="Bold"
              >
                <span className="font-bold text-xs uppercase">B</span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("`", "`")}
                title="Code"
              >
                <svg
                  className="w-3.5 h-3.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M16 18l6-6-6-6M8 6l-6 6 6 6"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </Button>
            </div>
          )}
        </div>

        <div className="flex items-center gap-4">
          {/* Save/Discard buttons (only in edit mode with changes) */}
          {viewMode === "edit" && (
            <>
              {hasChanges && (
                <Button variant="ghost" size="sm" onClick={handleDiscard}>
                  Discard
                </Button>
              )}
              <Button
                onClick={handleSave}
                disabled={!hasChanges || saving}
                size="sm"
                className="uppercase"
              >
                {saving ? (
                  <>
                    <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Saving...
                  </>
                ) : (
                  <>
                    <svg
                      className="w-3 h-3"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        d="M5 13l4 4L19 7"
                        strokeWidth="3"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                    Save
                  </>
                )}
              </Button>
            </>
          )}

          {/* Save message */}
          {saveMessage && (
            <Badge
              variant={
                saveMessage.type === "success" ? "success" : "destructive"
              }
            >
              {saveMessage.text}
            </Badge>
          )}

          {/* Copy button */}
          <Button variant="ghost" size="sm" onClick={copyToClipboard}>
            <svg
              className="w-3 h-3"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            Copy
          </Button>

          <div className="h-4 w-px bg-[var(--border-muted)]"></div>

          {/* File indicator */}
          <div className="flex items-center gap-2">
            {hasChanges && (
              <div
                className="w-1.5 h-1.5 rounded-full bg-amber-500"
                title="Unsaved changes"
              />
            )}
            <span className="text-[10px] font-mono text-[var(--text-muted)] uppercase">
              README.md
            </span>
          </div>
        </div>
      </div>

      {/* Content Area */}
      <div className="flex-1 overflow-hidden relative">
        {viewMode === "edit" ? (
          // Edit mode - textarea
          <div className="h-full flex flex-col">
            <Textarea
              ref={editorRef}
              value={planContent}
              onChange={(e) => setPlanContent(e.target.value)}
              className="w-full h-full p-12 font-mono text-sm leading-relaxed resize-none custom-scrollbar selection:bg-brand-500/30 border-0 rounded-none bg-[var(--bg-elevated)] text-[var(--text-secondary)] focus-visible:ring-0 focus-visible:ring-offset-0"
              placeholder="# Implementation Plan..."
            />
            <div className="absolute top-4 right-4 text-[9px] font-mono text-[var(--text-muted)] uppercase tracking-[0.2em] bg-[var(--bg-surface-200)]/30 px-3 py-1 rounded-full border border-[var(--border-muted)] backdrop-blur opacity-50">
              Source Editor
            </div>
          </div>
        ) : (
          // View mode - rendered markdown
          <div className="h-full overflow-y-auto custom-scrollbar">
            <div className="p-12 max-w-4xl mx-auto markdown-preview font-sans">
              <div dangerouslySetInnerHTML={{ __html: parsedHtml }} />
              {!parsedHtml && (
                <div className="flex flex-col items-center justify-center h-full text-[var(--text-muted)] gap-4 opacity-50">
                  <IconFileText className="w-12 h-12 opacity-20" />
                  <span className="text-xs font-mono uppercase tracking-widest opacity-40">
                    No plan content
                  </span>
                </div>
              )}
            </div>
            <div className="absolute top-4 right-4 text-[9px] font-mono text-[var(--text-muted)] uppercase tracking-[0.2em] bg-[var(--bg-surface-200)]/30 px-3 py-1 rounded-full border border-[var(--border-muted)] backdrop-blur opacity-50">
              Live Preview
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default PlanViewer;

import React, { useState, useEffect, useRef } from "react";
import { marked } from "marked";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Textarea } from "./ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";

interface MarkdownEditorProps {
  // Content management
  content: string;
  onContentChange: (content: string) => void;
  placeholder?: string;

  // View mode configuration
  viewModes: readonly string[]; // e.g., ["view", "edit"] or ["edit", "split", "preview"]
  initialViewMode?: string; // Initial active mode, defaults to first in viewModes

  // Save functionality
  onSave?: () => void | Promise<void>;
  onDiscard?: () => void;
  hasChanges?: boolean;
  saving?: boolean;
  saveMessage?: { type: "success" | "error"; text: string } | null;

  // Optional features
  showFormatting?: boolean; // Show formatting toolbar (default: true)
  showCopy?: boolean; // Show copy button (default: true)
  showSave?: boolean; // Show save/discard buttons (default: true)

  // File context
  fileName?: string; // Display filename in toolbar

  // Additional actions (render prop for parent-specific buttons)
  additionalActions?: React.ReactNode;

  // Styling
  className?: string;
  editorClassName?: string;
  previewClassName?: string;

  // Refs
  editorRef?: React.RefObject<HTMLTextAreaElement>;
}

const MarkdownEditor: React.FC<MarkdownEditorProps> = ({
  content,
  onContentChange,
  placeholder = "Start typing...",
  viewModes,
  initialViewMode,
  onSave,
  onDiscard,
  hasChanges = false,
  saving = false,
  saveMessage = null,
  showFormatting = true,
  showCopy = true,
  showSave = true,
  fileName,
  additionalActions,
  className = "",
  editorClassName = "",
  previewClassName = "",
  editorRef: externalEditorRef,
}) => {
  // Internal view mode state with localStorage persistence
  const [viewMode, setViewMode] = useState<string>(() => {
    const savedMode = localStorage.getItem("markdownEditorViewMode");
    if (savedMode && viewModes.includes(savedMode)) {
      return savedMode;
    }
    return initialViewMode || viewModes[0] || "edit";
  });

  // Persist view mode changes to localStorage
  useEffect(() => {
    localStorage.setItem("markdownEditorViewMode", viewMode);
  }, [viewMode]);

  // Parsed markdown state
  const [parsedHtml, setParsedHtml] = useState<string>("");

  // Internal editor ref if not provided
  const internalEditorRef = useRef<HTMLTextAreaElement>(null);
  const editorRef = externalEditorRef || internalEditorRef;

  // Parse markdown for preview
  useEffect(() => {
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
  }, [content]);

  // Insert formatting at cursor position
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

    onContentChange(newContent);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + prefix.length, end + prefix.length);
    }, 0);
  };

  // Copy raw content to clipboard
  const copyToClipboard = () => {
    navigator.clipboard.writeText(content);
  };

  // Handle save
  const handleSave = async () => {
    if (onSave) {
      await onSave();
    }
  };

  // Handle discard
  const handleDiscard = () => {
    if (onDiscard) {
      if (hasChanges) {
        const confirm = window.confirm("Discard all changes?");
        if (!confirm) return;
      }
      onDiscard();
    }
  };

  // Determine if editor should be shown
  const showEditor = viewMode === "edit" || viewMode === "split";
  // Determine if preview should be shown
  const showPreview =
    viewMode === "view" || viewMode === "preview" || viewMode === "split";

  return (
    <div
      className={`flex-1 flex flex-col bg-[var(--bg-base)] overflow-hidden ${className}`}
    >
      {/* Toolbar */}
      <div className="h-12 border-b border-[var(--border-muted)] flex items-center px-4 justify-between bg-[var(--bg-base)]/95 backdrop-blur z-20 flex-shrink-0">
        <div className="flex items-center gap-4">
          {/* Additional actions from parent (e.g., back button) */}
          {additionalActions}

          {/* View mode toggle */}
          <ToggleGroup
            type="single"
            value={viewMode}
            onValueChange={(value) => {
              if (value) setViewMode(value);
            }}
          >
            {viewModes.map((mode) => (
              <ToggleGroupItem key={mode} value={mode}>
                {mode.toUpperCase()}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>

          {/* Formatting buttons (only show if enabled and in edit/split mode) */}
          {showFormatting && showEditor && (
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
              <div className="w-px h-5 bg-[var(--border-muted)] mx-1" />
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("**", "**")}
                title="Bold"
              >
                <span className="font-bold text-xs">B</span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("_", "_")}
                title="Italic"
              >
                <span className="font-italic text-xs">I</span>
              </Button>
              <div className="w-px h-5 bg-[var(--border-muted)] mx-1" />
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("- ")}
                title="List"
              >
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <line x1="8" y1="6" x2="21" y2="6" strokeWidth="2" />
                  <line x1="8" y1="12" x2="21" y2="12" strokeWidth="2" />
                  <line x1="8" y1="18" x2="21" y2="18" strokeWidth="2" />
                  <line x1="3" y1="6" x2="3.01" y2="6" strokeWidth="2" />
                  <line x1="3" y1="12" x2="3.01" y2="12" strokeWidth="2" />
                  <line x1="3" y1="18" x2="3.01" y2="18" strokeWidth="2" />
                </svg>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("```\n", "\n```")}
                title="Code Block"
              >
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <polyline points="16 18 22 12 16 6" strokeWidth="2" />
                  <polyline points="8 6 2 12 8 18" strokeWidth="2" />
                </svg>
              </Button>
              <div className="w-px h-5 bg-[var(--border-muted)] mx-1" />
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("- [ ] ")}
                title="Empty Checkbox"
              >
                <svg
                  className="w-4 h-4"
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
                    ry="2"
                    strokeWidth="2"
                  />
                </svg>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => insertFormatting("- [x] ")}
                title="Checked Checkbox"
              >
                <svg
                  className="w-4 h-4"
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
                    ry="2"
                    strokeWidth="2"
                  />
                  <polyline
                    points="9 11 12 14 22 4"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </Button>
            </div>
          )}
        </div>

        <div className="flex items-center gap-2">
          {/* Save button */}
          {showSave && onSave && (
            <Button
              variant="default"
              size="sm"
              onClick={handleSave}
              disabled={!hasChanges || saving}
              className="h-7"
            >
              {saving ? "Saving..." : "Save"}
            </Button>
          )}

          {/* Discard button */}
          {showSave && onDiscard && hasChanges && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleDiscard}
              disabled={saving}
              className="h-7"
            >
              Discard
            </Button>
          )}

          {/* Save message */}
          {saveMessage && (
            <Badge
              variant={
                saveMessage.type === "success" ? "success" : "destructive"
              }
              className="text-[10px] px-2 py-1"
            >
              {saveMessage.text}
            </Badge>
          )}

          {/* Copy button */}
          {showCopy && (
            <Button
              variant="ghost"
              size="icon"
              onClick={copyToClipboard}
              title="Copy to clipboard"
              className="h-7 w-7"
            >
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <rect
                  x="9"
                  y="9"
                  width="13"
                  height="13"
                  rx="2"
                  ry="2"
                  strokeWidth="2"
                />
                <path
                  d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"
                  strokeWidth="2"
                />
              </svg>
            </Button>
          )}

          {/* File name and unsaved indicator */}
          {fileName && (
            <div className="flex items-center gap-2 px-2 border-l border-[var(--border-muted)]">
              <span className="text-xs font-mono text-[var(--text-muted)]">
                {fileName}
              </span>
              {hasChanges && (
                <div
                  className="w-1.5 h-1.5 rounded-full bg-[var(--warning-500)]"
                  title="Unsaved changes"
                />
              )}
            </div>
          )}
        </div>
      </div>

      {/* Editor/Preview Layout */}
      <div className="flex-1 flex overflow-hidden">
        {/* Editor Pane */}
        {showEditor && (
          <div
            className={`flex flex-col ${
              viewMode === "split"
                ? "w-1/2 border-r border-[var(--border-muted)]"
                : "flex-1"
            }`}
          >
            <Textarea
              ref={editorRef}
              value={content}
              onChange={(e) => onContentChange(e.target.value)}
              placeholder={placeholder}
              className={`flex-1 resize-none border-0 rounded-none font-mono text-xs leading-relaxed p-6 focus-visible:ring-0 focus-visible:ring-offset-0 custom-scrollbar ${editorClassName}`}
              style={{
                minHeight: "100%",
                backgroundColor: "var(--bg-deepest)",
                color: "var(--text-primary)",
              }}
            />
          </div>
        )}

        {/* Preview Pane */}
        {showPreview && (
          <div
            className={`flex flex-col overflow-hidden ${
              viewMode === "split" ? "w-1/2" : "flex-1"
            }`}
          >
            <div className="flex-1 overflow-y-auto custom-scrollbar p-8 bg-[var(--bg-base)]">
              {parsedHtml ? (
                <div
                  className={`max-w-4xl mx-auto markdown-preview ${previewClassName}`}
                  dangerouslySetInnerHTML={{ __html: parsedHtml }}
                />
              ) : (
                <div className="flex flex-col items-center justify-center h-full text-[var(--text-muted)] gap-4">
                  <svg
                    className="w-12 h-12 opacity-10"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    />
                  </svg>
                  <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                    No content
                  </span>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default MarkdownEditor;

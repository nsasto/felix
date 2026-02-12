import React, { useState, useEffect } from "react";
import { felixApi } from "../services/felixApi";
import { FileText as IconFileText } from "lucide-react";
import { ChevronLeft } from "lucide-react";
import { Button } from "./ui/button";
import MarkdownEditor from "./MarkdownEditor";
import { PageLoading } from "./ui/page-loading";

interface PlanViewerProps {
  projectId: string;
  onPlanUpdate?: () => void;
  onBack?: () => void;
}

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
    setPlanContent(originalContent);
  };

  // Render loading state
  if (loading) {
    return (
      <PageLoading
        message="Loading implementation plan..."
        layout="horizontal"
        size="sm"
      />
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
    <MarkdownEditor
      content={planContent}
      onContentChange={setPlanContent}
      viewModes={["view", "edit"]}
      initialViewMode="view"
      onSave={handleSave}
      onDiscard={handleDiscard}
      hasChanges={hasChanges}
      saving={saving}
      saveMessage={saveMessage}
      fileName="README.md"
      showFormatting={true}
      showCopy={true}
      showSave={true}
      placeholder="# Implementation Plan..."
      additionalActions={
        onBack && (
          <Button variant="ghost" size="icon" onClick={onBack}>
            <ChevronLeft className="w-4 h-4" />
          </Button>
        )
      }
    />
  );
};

export default PlanViewer;

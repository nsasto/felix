import React, { useState, useEffect, useMemo, useCallback } from "react";
import {
  felixApi,
  SpecFile,
  Requirement,
  RequirementStatusResponse,
} from "../services/felixApi";
import SpecsTableView from "./SpecsTableView";
import SpecEditorPage from "./SpecEditorPage";
import SpecCreateDialog, {
  SPEC_TEMPLATES,
  TemplateType,
} from "./SpecCreateDialog";

/**
 * Extract acceptance criteria and validation criteria sections from markdown content.
 * Returns the combined criteria sections for change detection.
 */
function extractCriteriaSections(content: string): string {
  if (!content) return "";

  const sections: string[] = [];
  const lines = content.split("\n");

  let inCriteriaSection = false;
  let currentSection: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmedLine = line.trim();

    const isCriteriaHeading = /^##\s+(acceptance|validation)\s+criteria/i.test(
      trimmedLine,
    );
    const isHeading = /^##\s+/.test(trimmedLine);

    if (isCriteriaHeading) {
      if (inCriteriaSection && currentSection.length > 0) {
        sections.push(currentSection.join("\n"));
      }
      inCriteriaSection = true;
      currentSection = [line];
    } else if (inCriteriaSection) {
      if (isHeading) {
        sections.push(currentSection.join("\n"));
        currentSection = [];
        inCriteriaSection = false;
      } else {
        currentSection.push(line);
      }
    }
  }

  if (inCriteriaSection && currentSection.length > 0) {
    sections.push(currentSection.join("\n"));
  }

  return sections.map((s) => s.trim()).join("\n---SECTION---\n");
}

interface SpecsEditorProps {
  projectId: string;
  initialSpecFilename?: string;
  onSelectSpec?: (filename: string) => void;
}

export default function SpecsEditor({
  projectId,
  initialSpecFilename,
  onSelectSpec,
}: SpecsEditorProps) {
  // View state
  const [viewMode, setViewMode] = useState<"table" | "editor">(
    initialSpecFilename ? "editor" : "table",
  );

  // Specs list state
  const [specs, setSpecs] = useState<SpecFile[]>([]);
  const [specsLoading, setSpecsLoading] = useState(true);
  const [specsError, setSpecsError] = useState<string | null>(null);

  // Requirements state (for table display)
  const [requirements, setRequirements] = useState<Requirement[]>([]);

  // Selected spec state
  const [selectedFilename, setSelectedFilename] = useState<string | null>(
    initialSpecFilename || null,
  );
  const [specContent, setSpecContent] = useState<string>("");
  const [originalContent, setOriginalContent] = useState<string>("");
  const [originalCriteria, setOriginalCriteria] = useState<string>("");
  const [contentLoading, setContentLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState<string>("");

  // New spec dialog state
  const [isNewSpecOpen, setIsNewSpecOpen] = useState(false);

  // Check if content has been modified
  const hasChanges = specContent !== originalContent;

  // Check if acceptance/validation criteria have changed
  const currentCriteria = useMemo(
    () => extractCriteriaSections(specContent),
    [specContent],
  );
  const hasCriteriaChanged = originalCriteria !== currentCriteria;

  // Get selected requirement details
  const selectedRequirement = useMemo(() => {
    if (!selectedFilename) return null;
    return (
      requirements.find((req) => req.spec_path.includes(selectedFilename)) ||
      null
    );
  }, [requirements, selectedFilename]);

  // Fetch specs list
  useEffect(() => {
    const fetchSpecs = async () => {
      setSpecsLoading(true);
      setSpecsError(null);
      try {
        const specList = await felixApi.listSpecs(projectId);
        setSpecs(specList);
      } catch (err) {
        console.error("Failed to fetch specs:", err);
        setSpecsError(
          err instanceof Error ? err.message : "Failed to load specs",
        );
      } finally {
        setSpecsLoading(false);
      }
    };

    fetchSpecs();
  }, [projectId]);

  // Fetch requirements
  useEffect(() => {
    const fetchRequirements = async () => {
      try {
        const reqData = await felixApi.getRequirements(projectId);
        setRequirements(reqData.requirements);
      } catch (err) {
        console.error("Failed to fetch requirements:", err);
        setRequirements([]);
      }
    };

    fetchRequirements();
  }, [projectId]);

  // Fetch spec content when selection changes
  useEffect(() => {
    if (!selectedFilename || viewMode !== "editor") {
      return;
    }

    const fetchContent = async () => {
      setContentLoading(true);
      try {
        const result = await felixApi.getSpec(projectId, selectedFilename);
        setSpecContent(result.content);
        setOriginalContent(result.content);
        setOriginalCriteria(extractCriteriaSections(result.content));
      } catch (err) {
        console.error("Failed to fetch spec content:", err);
        setSpecContent("");
        setOriginalContent("");
        setOriginalCriteria("");
      } finally {
        setContentLoading(false);
      }
    };

    fetchContent();
  }, [projectId, selectedFilename, viewMode]);

  // Handle spec selection from table
  const handleSpecClick = useCallback((specPath: string) => {
    // Extract filename from path
    const filename = specPath.split("/").pop() || specPath;
    setSelectedFilename(filename);
    setViewMode("editor");
  }, []);

  // Handle back to table
  const handleBack = useCallback(() => {
    if (hasChanges) {
      const confirm = window.confirm("You have unsaved changes. Discard them?");
      if (!confirm) return;
    }
    setViewMode("table");
    setSelectedFilename(null);
    setSpecContent("");
    setOriginalContent("");
    setOriginalCriteria("");
  }, [hasChanges]);

  // Handle save
  const handleSave = async () => {
    if (!selectedFilename || !hasChanges) return;

    setSaving(true);
    setSaveMessage("");

    const criteriaChanged = hasCriteriaChanged;

    try {
      await felixApi.updateSpec(projectId, selectedFilename, specContent);
      setOriginalContent(specContent);

      // If criteria changed, invalidate the plan
      if (criteriaChanged) {
        const match = selectedFilename.match(/^(S-\d+)/);
        const reqId = match ? match[1] : null;

        if (reqId) {
          try {
            const planInfo = await felixApi.getPlanInfo(projectId, reqId);
            if (planInfo.exists) {
              await felixApi.deletePlan(projectId, reqId);
              setSaveMessage(
                "Saved. Plan invalidated due to criteria changes.",
              );
              setOriginalCriteria(extractCriteriaSections(specContent));
              setTimeout(() => setSaveMessage(""), 5000);
              // Refresh requirements to update status
              const reqData = await felixApi.getRequirements(projectId);
              setRequirements(reqData.requirements);
              return;
            }
          } catch (planErr) {
            console.log("Plan invalidation skipped:", planErr);
          }
        }
        setOriginalCriteria(extractCriteriaSections(specContent));
      }

      setSaveMessage("Saved successfully");
      setTimeout(() => setSaveMessage(""), 3000);
    } catch (err) {
      console.error("Failed to save spec:", err);
      setSaveMessage(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  };

  // Handle discard changes
  const handleDiscard = () => {
    setSpecContent(originalContent);
  };

  // Handle reset plan
  const handleResetPlan = async () => {
    if (!selectedFilename) return;

    const match = selectedFilename.match(/^(S-\d+)/);
    const reqId = match ? match[1] : null;

    if (!reqId) {
      console.error("Could not extract requirement ID from filename");
      return;
    }

    try {
      await felixApi.deletePlan(projectId, reqId);
      setSaveMessage("Plan reset successfully");
      setTimeout(() => setSaveMessage(""), 3000);

      // Refresh requirements to update status
      const reqData = await felixApi.getRequirements(projectId);
      setRequirements(reqData.requirements);
    } catch (err) {
      console.error("Failed to reset plan:", err);
      setSaveMessage(
        err instanceof Error ? err.message : "Failed to reset plan",
      );
    }
  };

  // Handle open new spec dialog
  const handleOpenNewSpec = () => {
    setIsNewSpecOpen(true);
  };

  // Handle create new spec
  const handleCreateSpec = async (
    id: string,
    title: string,
    template: TemplateType,
  ) => {
    // Validate spec ID format
    if (!id.match(/^S-\d{4}$/)) {
      throw new Error("Spec ID must be in format S-XXXX (e.g., S-0006)");
    }

    // Generate filename from ID and title
    const slugTitle = title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
    const filename = `${id}-${slugTitle}.md`;

    // Generate content from template
    const templateObj = SPEC_TEMPLATES[template];
    const content = templateObj.content(id, title);

    // Create the spec
    await felixApi.createSpec(projectId, filename, content);

    // Refresh spec list
    const specList = await felixApi.listSpecs(projectId);
    setSpecs(specList);

    // Select the new spec and switch to editor view
    setSelectedFilename(filename);
    setViewMode("editor");
    onSelectSpec?.(filename);
  };

  // Handle inserting generated spec content from copilot
  const handleInsertGeneratedSpec = (content: string) => {
    setSpecContent(content);
  };

  const handleRequirementUpdate = useCallback(
    (id: string, field: string, value: any) => {
      setRequirements((prev) =>
        prev.map((req) => (req.id === id ? { ...req, [field]: value } : req)),
      );
    },
    [],
  );

  if (viewMode === "table") {
    return (
      <>
        <SpecsTableView
          requirements={requirements}
          loading={specsLoading}
          error={specsError}
          onSpecClick={handleSpecClick}
          onNewSpec={handleOpenNewSpec}
        />
        <SpecCreateDialog
          isOpen={isNewSpecOpen}
          onOpenChange={setIsNewSpecOpen}
          onCreate={handleCreateSpec}
        />
      </>
    );
  }

  if (viewMode === "editor" && selectedFilename) {
    return (
      <SpecEditorPage
        projectId={projectId}
        specFilename={selectedFilename}
        specContent={specContent}
        originalContent={originalContent}
        requirement={selectedRequirement}
        allRequirements={requirements}
        hasChanges={hasChanges}
        saving={saving}
        saveMessage={saveMessage}
        onBack={handleBack}
        onSave={handleSave}
        onDiscard={handleDiscard}
        onContentChange={setSpecContent}
        onResetPlan={handleResetPlan}
        onInsertGeneratedSpec={handleInsertGeneratedSpec}
        onRequirementUpdate={handleRequirementUpdate}
      />
    );
  }

  return null;
}

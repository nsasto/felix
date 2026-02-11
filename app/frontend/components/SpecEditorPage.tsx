import React, { useState, useEffect } from "react";
import { felixApi, Requirement, CopilotConfig } from "../services/felixApi";
import { Button } from "./ui/button";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";
import {
  ArrowLeft as IconArrowLeft,
  MessageSquare as IconMessageSquare,
  ChevronRight as IconChevronRight,
  Trash2 as IconTrash2,
  Settings as IconSettings,
  PanelRight as IconPanelRight,
} from "lucide-react";
import MarkdownEditor from "./MarkdownEditor";
import SpecEditWarningModal, { WarningAction } from "./SpecEditWarningModal";
import { SpecSidebarTabs } from "./SpecSidebarTabs";
import {
  validateSpecMetadata,
  parseSpecDependencies,
  replaceDependenciesSection,
  replaceOverviewSection,
  ValidationIssue,
  SyncableField,
  parseTitle,
  parsePriority,
  parseLabels,
  replaceTitle,
  replacePriority,
  replaceLabels,
} from "../utils/specParser";

interface SpecEditorPageProps {
  projectId: string;
  specFilename: string;
  specContent: string;
  originalContent: string;
  requirement: Requirement | null;
  allRequirements: Requirement[];
  hasChanges: boolean;
  saving: boolean;
  saveMessage: string;
  onBack: () => void;
  onSave: () => void;
  onDiscard: () => void;
  onContentChange: (content: string) => void;
  onResetPlan: () => void;
  onInsertGeneratedSpec: (content: string) => void;
}

export default function SpecEditorPage({
  projectId,
  specFilename,
  specContent,
  originalContent,
  requirement,
  allRequirements,
  hasChanges,
  saving,
  saveMessage,
  onBack,
  onSave,
  onDiscard,
  onContentChange,
  onResetPlan,
  onInsertGeneratedSpec,
}: SpecEditorPageProps) {
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [activeTab, setActiveTab] = useState<"copilot" | "metadata">(
    "metadata",
  );
  const [isWarningModalOpen, setIsWarningModalOpen] = useState(false);
  const [isResetPlanModalOpen, setIsResetPlanModalOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<"save" | "discard" | null>(
    null,
  );
  const [isCopilotEnabled, setIsCopilotEnabled] = useState(false);
  const [validationIssues, setValidationIssues] = useState<ValidationIssue[]>(
    [],
  );
  const [dismissedWarnings, setDismissedWarnings] = useState(false);
  const [lastSyncSource, setLastSyncSource] = useState<
    "metadata" | "markdown" | null
  >(null);
  const [lastSyncTimestamp, setLastSyncTimestamp] = useState<number>(0);
  const [dismissedFields, setDismissedFields] = useState<Set<string>>(
    new Set(),
  );

  // Check if copilot is enabled in settings
  useEffect(() => {
    const checkCopilotEnabled = async () => {
      try {
        const result = await felixApi.getGlobalConfig();
        const copilotConfig = result.config.copilot as
          | CopilotConfig
          | undefined;
        const enabled = copilotConfig?.enabled ?? false;
        setIsCopilotEnabled(enabled);
        // Metadata tab is default, no need to change
      } catch (error) {
        console.error("Failed to check copilot status:", error);
        setIsCopilotEnabled(false);
      }
    };

    checkCopilotEnabled();
  }, []);

  // Debounced validation of spec content
  useEffect(() => {
    if (!requirement || dismissedWarnings) return;

    // Skip validation if user just made an edit (within last 5 seconds)
    const isRecentEdit =
      lastSyncSource && Date.now() - lastSyncTimestamp < 5000;
    if (isRecentEdit) {
      setValidationIssues([]);
      return;
    }

    const timer = setTimeout(() => {
      const issues = validateSpecMetadata(requirement, specContent);
      // Filter out dismissed fields
      const filteredIssues = issues.filter(
        (issue) => !dismissedFields.has(issue.field),
      );
      setValidationIssues(filteredIssues);
    }, 500);

    return () => clearTimeout(timer);
  }, [
    specContent,
    requirement,
    dismissedWarnings,
    lastSyncSource,
    lastSyncTimestamp,
    dismissedFields,
  ]);

  // Auto-sync markdown changes to metadata
  useEffect(() => {
    if (!requirement || dismissedWarnings) return;

    // Skip if we just synced FROM metadata (within last 2 seconds)
    if (
      lastSyncSource === "metadata" &&
      Date.now() - lastSyncTimestamp < 2000
    ) {
      return;
    }

    const timer = setTimeout(async () => {
      const changes: Array<{ field: SyncableField; value: any }> = [];

      const markdownTitle = parseTitle(specContent);
      if (markdownTitle && markdownTitle !== requirement.title) {
        changes.push({ field: "title", value: markdownTitle });
      }

      const markdownPriority = parsePriority(specContent);
      if (markdownPriority !== requirement.priority) {
        changes.push({ field: "priority", value: markdownPriority });
      }

      const markdownLabels = parseLabels(specContent);
      const labelsMatch =
        JSON.stringify(markdownLabels.sort()) ===
        JSON.stringify((requirement.labels || []).sort());
      if (!labelsMatch) {
        changes.push({ field: "labels", value: markdownLabels });
      }

      const markdownDeps = parseSpecDependencies(specContent);
      const depsMatch =
        JSON.stringify(markdownDeps.sort()) ===
        JSON.stringify((requirement.depends_on || []).sort());
      if (!depsMatch) {
        changes.push({ field: "depends_on", value: markdownDeps });
      }

      if (changes.length > 0) {
        setLastSyncSource("markdown");
        setLastSyncTimestamp(Date.now());

        for (const change of changes) {
          try {
            await felixApi.updateRequirementMetadata(
              projectId,
              requirement.id,
              change.field,
              change.value,
            );
          } catch (error) {
            console.error(`Failed to sync ${change.field} to metadata:`, error);
          }
        }
      }
    }, 500);

    return () => clearTimeout(timer);
  }, [
    specContent,
    requirement,
    projectId,
    dismissedWarnings,
    lastSyncSource,
    lastSyncTimestamp,
  ]);

  // Check if requirement is in_progress
  const isInProgress = requirement?.status === "in_progress";
  const selectedSpecHasPlan = requirement?.has_plan || false;

  // Handle save with warning check
  const handleSaveClick = () => {
    if (isInProgress) {
      setPendingAction("save");
      setIsWarningModalOpen(true);
    } else {
      onSave();
    }
  };

  // Handle discard with warning check
  const handleDiscardClick = () => {
    if (isInProgress && hasChanges) {
      setPendingAction("discard");
      setIsWarningModalOpen(true);
    } else {
      onDiscard();
    }
  };

  // Handle warning modal action
  const handleWarningAction = (action: WarningAction) => {
    setIsWarningModalOpen(false);

    if (action === "continue") {
      if (pendingAction === "save") {
        onSave();
      } else if (pendingAction === "discard") {
        onDiscard();
      }
    }

    setPendingAction(null);
  };

  // Handle reset plan
  const handleResetPlanClick = () => {
    setIsResetPlanModalOpen(true);
  };

  const handleResetPlanConfirm = () => {
    setIsResetPlanModalOpen(false);
    onResetPlan();
  };

  const showResetPlanButton =
    selectedSpecHasPlan &&
    requirement &&
    (requirement.status === "planned" || requirement.status === "in_progress");

  // Handle metadata field updates
  const handleMetadataUpdate = async (field: string, value: any) => {
    if (!requirement) return;

    try {
      setLastSyncSource("metadata");
      setLastSyncTimestamp(Date.now());

      await felixApi.updateRequirementMetadata(
        projectId,
        requirement.id,
        field,
        value,
      );

      // Immediately sync to markdown
      let updatedMarkdown = specContent;
      switch (field) {
        case "title":
          updatedMarkdown = replaceTitle(specContent, value);
          break;
        case "priority":
          updatedMarkdown = replacePriority(specContent, value);
          break;
        case "labels":
          updatedMarkdown = replaceLabels(specContent, value);
          break;
        case "depends_on":
          updatedMarkdown = replaceDependenciesSection(specContent, value);
          break;
      }

      if (updatedMarkdown !== specContent) {
        onContentChange(updatedMarkdown);
      }

      console.log(`Updated and synced ${field} successfully`);
      // Note: The requirement will be updated via Supabase realtime subscription
    } catch (error) {
      console.error("Failed to update metadata:", error);
      alert("Failed to update metadata. Please try again.");
    }
  };

  // Sync a specific field in the specified direction
  const syncField = async (
    direction: "markdown-to-metadata" | "metadata-to-markdown",
    field: SyncableField,
  ) => {
    if (!requirement) return;

    setLastSyncSource(
      direction === "markdown-to-metadata" ? "markdown" : "metadata",
    );
    setLastSyncTimestamp(Date.now());

    // Remove from dismissed
    setDismissedFields((prev) => {
      const next = new Set(prev);
      next.delete(field);
      return next;
    });

    if (direction === "markdown-to-metadata") {
      let value: any;
      switch (field) {
        case "title":
          value = parseTitle(specContent);
          break;
        case "priority":
          value = parsePriority(specContent);
          break;
        case "labels":
          value = parseLabels(specContent);
          break;
        case "depends_on":
          value = parseSpecDependencies(specContent);
          break;
      }
      await handleMetadataUpdate(field, value);
    } else {
      // metadata-to-markdown
      let updatedMarkdown = specContent;
      const value = (requirement as any)[field];

      switch (field) {
        case "title":
          updatedMarkdown = replaceTitle(specContent, value as string);
          break;
        case "priority":
          updatedMarkdown = replacePriority(specContent, value as string);
          break;
        case "labels":
          updatedMarkdown = replaceLabels(specContent, value as string[]);
          break;
        case "depends_on":
          updatedMarkdown = replaceDependenciesSection(
            specContent,
            value as string[],
          );
          break;
      }

      onContentChange(updatedMarkdown);
    }
  };

  // Sync overview content to markdown
  const handleOverviewChange = (content: string) => {
    const updatedMarkdown = replaceOverviewSection(specContent, content);
    onContentChange(updatedMarkdown);
  };

  // Dismiss validation warning for this session
  const handleDismissWarning = (field?: string) => {
    if (field) {
      setDismissedFields((prev) => new Set(prev).add(field));
      setValidationIssues((prev) =>
        prev.filter((issue) => issue.field !== field),
      );
    } else {
      setDismissedWarnings(true);
      setValidationIssues([]);
    }
  };

  // Toggle sidebar and switch to appropriate tab
  const handleToggleSidebar = () => {
    if (!sidebarOpen) {
      // Opening sidebar - default to metadata tab
      setActiveTab("metadata");
    }
    setSidebarOpen(!sidebarOpen);
  };

  return (
    <div className="flex-1 flex flex-col bg-[var(--bg)] overflow-hidden">
      {/* Header */}
      <div className="flex-shrink-0 border-b border-[var(--border)] bg-[var(--bg-surface-100)] px-4 py-3 flex items-center gap-3">
        <Button
          variant="ghost"
          onClick={onBack}
          className="flex items-center gap-2"
        >
          <IconArrowLeft className="w-4 h-4" />
          Back to Specs
        </Button>
        <div className="flex-1 flex items-center gap-2">
          <span className="text-[var(--text)] font-medium">{specFilename}</span>
          {requirement && (
            <>
              <span className="text-[var(--text-muted)]">•</span>
              <span className="text-[var(--text-muted)] text-sm">
                {requirement.id}: {requirement.title}
              </span>
            </>
          )}
        </div>
        <Button
          variant="ghost"
          onClick={handleToggleSidebar}
          className="flex items-center gap-2"
        >
          {sidebarOpen ? (
            <>
              <IconChevronRight className="w-4 h-4" />
              Hide Panel
            </>
          ) : (
            <>
              <IconPanelRight className="w-4 h-4" />
              Show Panel
              {validationIssues.length > 0 && (
                <span className="inline-flex items-center justify-center w-5 h-5 text-xs font-bold text-white bg-yellow-500 rounded-full">
                  {validationIssues.length}
                </span>
              )}
            </>
          )}
        </Button>
      </div>

      {/* Main content area */}
      <div className="flex-1 flex overflow-hidden">
        {/* Editor area */}
        <div
          className={`flex-1 flex flex-col overflow-hidden transition-all duration-300 ${sidebarOpen ? "mr-0" : ""}`}
        >
          <MarkdownEditor
            content={specContent}
            onContentChange={onContentChange}
            viewModes={["edit", "split", "preview"]}
            initialViewMode="edit"
            onSave={handleSaveClick}
            onDiscard={handleDiscardClick}
            hasChanges={hasChanges}
            saving={saving}
            saveMessage={saveMessage}
            showFormatting={true}
            showCopy={true}
            showSave={true}
            fileName={specFilename}
            additionalActions={
              showResetPlanButton ? (
                <Button
                  onClick={handleResetPlanClick}
                  variant="ghost"
                  className="flex items-center gap-2 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/10"
                >
                  <IconTrash2 className="w-4 h-4" />
                  Reset Plan
                </Button>
              ) : undefined
            }
          />
        </div>

        {/* Collapsible tabbed sidebar */}
        <div
          className={`flex-shrink-0 transition-all duration-300 overflow-hidden ${
            sidebarOpen ? "w-[480px]" : "w-0"
          }`}
        >
          {sidebarOpen && (
            <SpecSidebarTabs
              activeTab={activeTab}
              onTabChange={setActiveTab}
              projectId={projectId}
              requirement={requirement}
              allRequirements={allRequirements}
              specContent={specContent}
              validationIssues={dismissedWarnings ? [] : validationIssues}
              onInsertSpec={onInsertGeneratedSpec}
              onMetadataUpdate={handleMetadataUpdate}
              onSyncField={syncField}
              onOverviewChange={handleOverviewChange}
              onDismissWarning={handleDismissWarning}
              isCopilotEnabled={isCopilotEnabled}
            />
          )}
        </div>
      </div>

      {/* Warning Modal for in_progress edits */}
      <SpecEditWarningModal
        isOpen={isWarningModalOpen}
        fileName={specFilename}
        action={pendingAction === "save" ? "save" : "discard"}
        onAction={handleWarningAction}
      />

      {/* Reset Plan Modal */}
      <AlertDialog
        open={isResetPlanModalOpen}
        onOpenChange={setIsResetPlanModalOpen}
      >
        <AlertDialogContent className="bg-[var(--bg-surface-200)]">
          <AlertDialogHeader>
            <AlertDialogTitle className="text-[var(--text)]">
              Reset Implementation Plan?
            </AlertDialogTitle>
            <AlertDialogDescription className="text-[var(--text-muted)]">
              This will delete the existing implementation plan for{" "}
              <span className="font-mono text-[var(--brand-400)]">
                {requirement?.id}
              </span>
              . The requirement status will be set back to "draft". This action
              cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel
              onClick={() => setIsResetPlanModalOpen(false)}
              className="bg-[var(--bg-surface-100)] hover:bg-[var(--bg-surface-200)]"
            >
              Cancel
            </AlertDialogCancel>
            <Button
              onClick={handleResetPlanConfirm}
              className="bg-[var(--destructive-500)] hover:bg-[var(--destructive-600)] text-white"
            >
              <IconTrash2 className="w-4 h-4 mr-2" />
              Reset Plan
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

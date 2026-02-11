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
} from "lucide-react";
import MarkdownEditor from "./MarkdownEditor";
import SpecEditWarningModal, { WarningAction } from "./SpecEditWarningModal";
import { CopilotSidebar } from "./copilot";

interface SpecEditorPageProps {
  projectId: string;
  specFilename: string;
  specContent: string;
  originalContent: string;
  requirement: Requirement | null;
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
  const [chatOpen, setChatOpen] = useState(true);
  const [isWarningModalOpen, setIsWarningModalOpen] = useState(false);
  const [isResetPlanModalOpen, setIsResetPlanModalOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<"save" | "discard" | null>(
    null,
  );
  const [isCopilotEnabled, setIsCopilotEnabled] = useState(false);

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
      } catch (error) {
        console.error("Failed to check copilot status:", error);
        setIsCopilotEnabled(false);
      }
    };

    checkCopilotEnabled();
  }, []);

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

    if (action === "proceed") {
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
        {isCopilotEnabled && (
          <Button
            variant="ghost"
            onClick={() => setChatOpen(!chatOpen)}
            className="flex items-center gap-2"
          >
            {chatOpen ? (
              <>
                <IconChevronRight className="w-4 h-4" />
                Hide Chat
              </>
            ) : (
              <>
                <IconMessageSquare className="w-4 h-4" />
                Show Chat
              </>
            )}
          </Button>
        )}
      </div>

      {/* Main content area */}
      <div className="flex-1 flex overflow-hidden">
        {/* Editor area */}
        <div
          className={`flex-1 flex flex-col overflow-hidden transition-all duration-300 ${chatOpen ? "mr-0" : ""}`}
        >
          <MarkdownEditor
            content={specContent}
            onContentChange={onContentChange}
            viewModes={["edit", "split", "preview"]}
            initialViewMode="split"
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

        {/* Collapsible chat sidebar */}
        {isCopilotEnabled && (
          <div
            className={`flex-shrink-0 transition-all duration-300 overflow-hidden ${
              chatOpen ? "w-[400px]" : "w-0"
            }`}
          >
            {chatOpen && (
              <CopilotSidebar
                projectId={projectId}
                onInsertSpec={onInsertGeneratedSpec}
              />
            )}
          </div>
        )}
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

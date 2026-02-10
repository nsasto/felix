import React from "react";
import { Alert, AlertDescription } from "./ui/alert";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";
import { Button } from "./ui/button";

export type WarningAction = "continue" | "reset_plan" | "cancel";

interface SpecEditWarningModalProps {
  /** The requirement ID being edited */
  requirementId: string;
  /** The requirement title */
  requirementTitle: string;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Whether an action is in progress (e.g., blocking) */
  isLoading?: boolean;
  /** Callback when user selects an action */
  onAction: (action: WarningAction) => void;
}

// Warning icon
const IconAlertTriangle = ({
  className = "w-5 h-5",
}: {
  className?: string;
}) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
  >
    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
    <line x1="12" y1="9" x2="12" y2="13" />
    <line x1="12" y1="17" x2="12.01" y2="17" />
  </svg>
);

// Close icon
const IconX = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
  >
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
  </svg>
);

// Pause/Stop icon
const IconPause = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
  >
    <rect x="6" y="4" width="4" height="16" rx="1" />
    <rect x="14" y="4" width="4" height="16" rx="1" />
  </svg>
);

// Edit icon
const IconEdit = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
  >
    <path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z" />
  </svg>
);

const SpecEditWarningModal: React.FC<SpecEditWarningModalProps> = ({
  requirementId,
  requirementTitle,
  isOpen,
  isLoading = false,
  onAction,
}) => {
  return (
    <AlertDialog
      open={isOpen}
      onOpenChange={(open) => {
        if (!open) onAction("cancel");
      }}
    >
      <AlertDialogContent className="max-w-[480px]">
        <AlertDialogHeader className="flex items-center justify-between border-b border-[var(--border-default)] px-4 py-3 bg-[var(--warning-500)]/5">
          <div className="flex items-center gap-2">
            <IconAlertTriangle className="w-4 h-4 text-[var(--warning-500)]" />
            <AlertDialogTitle className="text-xs font-bold text-[var(--warning-500)]">
              Active Work in Progress
            </AlertDialogTitle>
          </div>
          <AlertDialogCancel asChild>
            <Button
              onClick={() => onAction("cancel")}
              disabled={isLoading}
              variant="ghost"
              size="icon"
              className="h-8 w-8"
            >
              <IconX className="w-4 h-4" />
            </Button>
          </AlertDialogCancel>
        </AlertDialogHeader>

        <div className="p-5 space-y-4">
          <div className="space-y-3">
            <p className="text-sm theme-text-secondary">
              You are about to edit{" "}
              <span className="font-mono text-[var(--brand-500)]">
                {requirementId}
              </span>
              :
            </p>
            <p className="text-sm font-medium theme-text-secondary bg-[var(--bg-surface-100)] px-3 py-2 rounded-lg">
              "{requirementTitle}"
            </p>
          </div>

          <Alert className="border-[var(--warning-500)]/30 bg-[var(--warning-500)]/10 text-[var(--warning-500)]">
            <AlertDescription className="text-[var(--warning-500)]/90 leading-relaxed">
              <strong>This requirement is currently in progress.</strong> The
              Felix agent may be actively working on it. Editing the spec while
              work is in progress could cause:
            </AlertDescription>
            <ul className="mt-2 text-xs text-[var(--warning-500)]/70 list-disc pl-5 space-y-1">
              <li>
                Drift between the spec and the current implementation plan
              </li>
              <li>Wasted agent iterations on outdated acceptance criteria</li>
              <li>
                Confusion about which version of the spec is authoritative
              </li>
            </ul>
          </Alert>

          <div className="text-xs theme-text-muted space-y-2">
            <p>
              <strong className="theme-text-secondary">
                Choose an option:
              </strong>
            </p>
            <ul className="space-y-1.5">
              <li className="flex items-start gap-2">
                <span className="text-[var(--brand-500)] mt-0.5">•</span>
                <span>
                  <strong className="theme-text-secondary">
                    Continue Editing
                  </strong>{" "}
                  – Proceed knowing work is in progress (use caution)
                </span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-[var(--warning-500)] mt-0.5">•</span>
                <span>
                  <strong className="theme-text-secondary">Reset Plan</strong> –
                  Mark as "planned", clear the plan file, then edit
                </span>
              </li>
              <li className="flex items-start gap-2">
                <span className="theme-text-muted mt-0.5">•</span>
                <span>
                  <strong className="theme-text-secondary">Cancel</strong> –
                  Don't edit right now
                </span>
              </li>
            </ul>
          </div>
        </div>

        <AlertDialogFooter className="flex items-center justify-end gap-3 border-t border-[var(--border-default)] px-4 py-3 bg-[var(--bg-surface-75)]">
          <AlertDialogCancel asChild>
            <Button
              onClick={() => onAction("cancel")}
              disabled={isLoading}
              variant="ghost"
              size="sm"
            >
              Cancel
            </Button>
          </AlertDialogCancel>
          <Button
            onClick={() => onAction("reset_plan")}
            disabled={isLoading}
            variant="secondary"
            size="sm"
            className="uppercase text-[var(--warning-500)] border-[var(--warning-500)]/30 hover:bg-[var(--warning-500)]/10"
          >
            {isLoading ? (
              <>
                <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                Resetting...
              </>
            ) : (
              <>
                <IconPause className="w-3 h-3" />
                Reset Plan
              </>
            )}
          </Button>
          <Button
            onClick={() => onAction("continue")}
            disabled={isLoading}
            size="sm"
            className="uppercase"
          >
            <IconEdit className="w-3 h-3" />
            Continue Editing
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
};

export default SpecEditWarningModal;

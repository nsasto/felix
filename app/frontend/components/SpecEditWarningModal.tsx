import React from 'react';

export type WarningAction = 'continue' | 'reset_plan' | 'cancel';

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
const IconAlertTriangle = ({ className = "w-5 h-5" }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
    <line x1="12" y1="9" x2="12" y2="13" />
    <line x1="12" y1="17" x2="12.01" y2="17" />
  </svg>
);

// Close icon
const IconX = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
  </svg>
);

// Pause/Stop icon
const IconPause = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <rect x="6" y="4" width="4" height="16" rx="1" />
    <rect x="14" y="4" width="4" height="16" rx="1" />
  </svg>
);

// Edit icon
const IconEdit = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
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
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
      <div className="theme-bg-base border theme-border rounded-2xl shadow-2xl w-[480px] overflow-hidden">
        {/* Modal header */}
        <div className="h-12 border-b border-slate-800/60 flex items-center justify-between px-4 bg-amber-500/5">
          <div className="flex items-center gap-2">
            <IconAlertTriangle className="w-4 h-4 text-amber-400" />
            <span className="text-xs font-bold text-amber-300">
              Active Work in Progress
            </span>
          </div>
          <button
            onClick={() => onAction('cancel')}
            disabled={isLoading}
            className="p-1.5 hover:bg-slate-800 rounded-lg transition-all text-slate-500 hover:text-slate-300 disabled:opacity-50"
          >
            <IconX className="w-4 h-4" />
          </button>
        </div>

        {/* Modal body */}
        <div className="p-5 space-y-4">
          {/* Warning message */}
          <div className="space-y-3">
            <p className="text-sm text-slate-300">
              You are about to edit <span className="font-mono text-felix-400">{requirementId}</span>:
            </p>
            <p className="text-sm font-medium text-slate-200 bg-slate-800/50 px-3 py-2 rounded-lg">
              "{requirementTitle}"
            </p>
          </div>

          {/* Impact explanation */}
          <div className="bg-amber-500/10 border border-amber-500/20 rounded-xl p-4 space-y-2">
            <p className="text-xs text-amber-300/90 leading-relaxed">
              <strong>This requirement is currently in progress.</strong> The Felix agent may be 
              actively working on it. Editing the spec while work is in progress could cause:
            </p>
            <ul className="text-xs text-amber-300/70 list-disc pl-5 space-y-1">
              <li>Drift between the spec and the current implementation plan</li>
              <li>Wasted agent iterations on outdated acceptance criteria</li>
              <li>Confusion about which version of the spec is authoritative</li>
            </ul>
          </div>

          {/* Options explanation */}
          <div className="text-xs text-slate-500 space-y-2">
            <p><strong className="text-slate-400">Choose an option:</strong></p>
            <ul className="space-y-1.5">
              <li className="flex items-start gap-2">
                <span className="text-felix-400 mt-0.5">•</span>
                <span><strong className="text-slate-300">Continue Editing</strong> – Proceed knowing work is in progress (use caution)</span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-amber-400 mt-0.5">•</span>
                <span><strong className="text-slate-300">Reset Plan</strong> – Mark as "planned", clear the plan file, then edit</span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-slate-500 mt-0.5">•</span>
                <span><strong className="text-slate-300">Cancel</strong> – Don't edit right now</span>
              </li>
            </ul>
          </div>
        </div>

        {/* Modal footer */}
        <div className="h-16 border-t theme-border flex items-center justify-end gap-3 px-4 theme-bg-deep/50">
          <button
            onClick={() => onAction('cancel')}
            disabled={isLoading}
            className="px-4 py-2 text-xs font-medium text-slate-500 hover:text-slate-300 transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={() => onAction('reset_plan')}
            disabled={isLoading}
            className="px-4 py-2 bg-amber-600/80 text-white text-xs font-bold rounded-xl hover:bg-amber-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
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
          </button>
          <button
            onClick={() => onAction('continue')}
            disabled={isLoading}
            className="px-4 py-2 bg-felix-600 text-white text-xs font-bold rounded-xl hover:bg-felix-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            <IconEdit className="w-3 h-3" />
            Continue Editing
          </button>
        </div>
      </div>
    </div>
  );
};

export default SpecEditWarningModal;

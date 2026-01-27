import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { felixApi, SpecFile } from '../services/felixApi';
import { marked } from 'marked';
import { IconFileText, IconPlus } from './Icons';
import SpecEditWarningModal, { WarningAction } from './SpecEditWarningModal';
import { useRequirementStatus } from '../hooks/useRequirementStatus';

/**
 * Extract acceptance criteria and validation criteria sections from markdown content.
 * Returns the combined criteria sections for change detection.
 * 
 * Looks for sections starting with "## Acceptance Criteria" or "## Validation Criteria"
 * and captures content until the next heading of same or higher level.
 */
function extractCriteriaSections(content: string): string {
  if (!content) return '';
  
  const sections: string[] = [];
  const lines = content.split('\n');
  
  let inCriteriaSection = false;
  let currentSection: string[] = [];
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmedLine = line.trim();
    
    // Check if this is a criteria heading (## Acceptance Criteria or ## Validation Criteria)
    const isCriteriaHeading = /^##\s+(acceptance|validation)\s+criteria/i.test(trimmedLine);
    
    // Check if this is a new section (any ## heading)
    const isHeading = /^##\s+/.test(trimmedLine);
    
    if (isCriteriaHeading) {
      // Start capturing this criteria section
      if (inCriteriaSection && currentSection.length > 0) {
        // Save previous section before starting new one
        sections.push(currentSection.join('\n'));
      }
      inCriteriaSection = true;
      currentSection = [line];
    } else if (inCriteriaSection) {
      if (isHeading) {
        // End of criteria section - reached a new ## heading
        sections.push(currentSection.join('\n'));
        currentSection = [];
        inCriteriaSection = false;
      } else {
        // Continue capturing current criteria section
        currentSection.push(line);
      }
    }
  }
  
  // Don't forget the last section if we ended while in one
  if (inCriteriaSection && currentSection.length > 0) {
    sections.push(currentSection.join('\n'));
  }
  
  // Return combined sections, normalized for comparison
  // Trim each section and join with a delimiter for comparison
  return sections.map(s => s.trim()).join('\n---SECTION---\n');
}

interface SpecsEditorProps {
  projectId: string;
  initialSpecFilename?: string;
  onSelectSpec?: (filename: string) => void;
}

type ViewMode = 'edit' | 'preview' | 'split';

// Spec templates
const SPEC_TEMPLATES = {
  basic: {
    name: 'Basic Spec',
    description: 'A minimal spec template with essential sections',
    content: (id: string, title: string) => `# ${id}: ${title}

## Summary

Brief description of this specification.

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Technical Notes

Implementation details and considerations.

## Dependencies

- List any dependencies on other specs or requirements

## Validation Criteria

- [ ] Validation check 1
- [ ] Validation check 2
`,
  },
  feature: {
    name: 'Feature Spec',
    description: 'Detailed feature specification with narrative',
    content: (id: string, title: string) => `# ${id}: ${title}

## Narrative

As a [user type], I need [goal] so that [benefit].

## Acceptance Criteria

### Core Functionality

- [ ] Core feature requirement 1
- [ ] Core feature requirement 2

### Edge Cases

- [ ] Edge case handling 1
- [ ] Edge case handling 2

## Technical Notes

### Architecture

Describe the technical architecture.

### API Changes

List any API changes needed.

### Data Model

Describe any data model changes.

## Dependencies

- Dependency 1
- Dependency 2

## Validation Criteria

- [ ] Feature works as specified
- [ ] Tests pass
- [ ] Documentation updated
`,
  },
  bugfix: {
    name: 'Bug Fix Spec',
    description: 'Template for documenting a bug fix',
    content: (id: string, title: string) => `# ${id}: ${title}

## Problem Statement

Describe the bug or issue being addressed.

## Root Cause

Analysis of what caused the issue.

## Solution

### Proposed Fix

Describe the fix to be implemented.

### Files Affected

- file1.ts
- file2.ts

## Acceptance Criteria

- [ ] Bug is fixed
- [ ] No regression introduced
- [ ] Tests added to prevent recurrence

## Testing

### Steps to Reproduce (Before Fix)

1. Step 1
2. Step 2
3. Bug occurs

### Expected Behavior (After Fix)

Describe expected behavior.

## Validation Criteria

- [ ] Bug no longer reproducible
- [ ] Tests pass
`,
  },
};

type TemplateType = keyof typeof SPEC_TEMPLATES;

// Close icon component
const IconX = ({ className = "w-4 h-4" }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
  </svg>
);

const SpecsEditor: React.FC<SpecsEditorProps> = ({
  projectId,
  initialSpecFilename,
  onSelectSpec,
}) => {
  // Spec list state
  const [specs, setSpecs] = useState<SpecFile[]>([]);
  const [specsLoading, setSpecsLoading] = useState(true);
  const [specsError, setSpecsError] = useState<string | null>(null);

  // Selected spec state
  const [selectedFilename, setSelectedFilename] = useState<string | null>(initialSpecFilename || null);
  const [specContent, setSpecContent] = useState<string>('');
  const [originalContent, setOriginalContent] = useState<string>('');
  const [originalCriteria, setOriginalCriteria] = useState<string>(''); // For S-0006: Track original acceptance/validation criteria
  const [contentLoading, setContentLoading] = useState(false);
  const [contentError, setContentError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  // View mode and parsed markdown
  const [viewMode, setViewMode] = useState<ViewMode>('split');
  const [parsedHtml, setParsedHtml] = useState<string>('');

  // New spec modal state
  const [isNewSpecOpen, setIsNewSpecOpen] = useState(false);
  const [newSpecId, setNewSpecId] = useState('');
  const [newSpecTitle, setNewSpecTitle] = useState('');
  const [newSpecTemplate, setNewSpecTemplate] = useState<TemplateType>('basic');
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  // Warning modal state (for S-0006: Spec Edit Safety)
  const [pendingSpecFilename, setPendingSpecFilename] = useState<string | null>(null);
  const [isWarningModalOpen, setIsWarningModalOpen] = useState(false);
  const [isBlockingRequirement, setIsBlockingRequirement] = useState(false);

  // Reset Plan modal state (for S-0006: Manual Reset Plan Controls)
  const [isResetPlanModalOpen, setIsResetPlanModalOpen] = useState(false);
  const [isResettingPlan, setIsResettingPlan] = useState(false);
  const [resetPlanMessage, setResetPlanMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  const editorRef = useRef<HTMLTextAreaElement>(null);

  // Hook to check requirement status for warning modal (S-0006)
  const { 
    status: pendingSpecStatus, 
    isInProgress: pendingSpecIsInProgress,
    requirementId: pendingRequirementId,
  } = useRequirementStatus(projectId, pendingSpecFilename);

  // Hook to check requirement status for currently selected spec (S-0006: Manual Reset Plan Controls)
  const {
    status: selectedSpecStatus,
    hasPlan: selectedSpecHasPlan,
    requirementId: selectedRequirementId,
    refreshStatus: refreshSelectedSpecStatus,
  } = useRequirementStatus(projectId, selectedFilename);

  // Check if content has been modified
  const hasChanges = specContent !== originalContent;
  
  // S-0006: Check if acceptance/validation criteria have changed
  // This is used for plan invalidation detection on save
  const currentCriteria = useMemo(() => extractCriteriaSections(specContent), [specContent]);
  const hasCriteriaChanged = originalCriteria !== currentCriteria;

  // Fetch specs list on mount or when projectId changes
  useEffect(() => {
    const fetchSpecs = async () => {
      setSpecsLoading(true);
      setSpecsError(null);
      try {
        const specList = await felixApi.listSpecs(projectId);
        setSpecs(specList);
        
        // If no spec selected but we have specs, select the first one
        if (!selectedFilename && specList.length > 0) {
          setSelectedFilename(specList[0].filename);
        }
      } catch (err) {
        console.error('Failed to fetch specs:', err);
        setSpecsError(err instanceof Error ? err.message : 'Failed to load specs');
      } finally {
        setSpecsLoading(false);
      }
    };

    fetchSpecs();
  }, [projectId]);

  // Fetch spec content when selection changes
  useEffect(() => {
    if (!selectedFilename) {
      setSpecContent('');
      setOriginalContent('');
      setOriginalCriteria('');
      return;
    }

    const fetchContent = async () => {
      setContentLoading(true);
      setContentError(null);
      try {
        const result = await felixApi.getSpec(projectId, selectedFilename);
        setSpecContent(result.content);
        setOriginalContent(result.content);
        // S-0006: Extract and store original acceptance/validation criteria for change detection
        setOriginalCriteria(extractCriteriaSections(result.content));
      } catch (err) {
        console.error('Failed to fetch spec content:', err);
        setContentError(err instanceof Error ? err.message : 'Failed to load spec');
        setSpecContent('');
        setOriginalContent('');
        setOriginalCriteria('');
      } finally {
        setContentLoading(false);
      }
    };

    fetchContent();
  }, [projectId, selectedFilename]);

  // Parse markdown for preview
  useEffect(() => {
    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        const result = await marked.parse(specContent || '');
        if (isMounted) setParsedHtml(result);
      } catch (err) {
        console.error('Markdown rendering error:', err);
        if (isMounted) setParsedHtml(`<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`);
      }
    };

    const timeout = setTimeout(parseMarkdown, 50);
    return () => {
      isMounted = false;
      clearTimeout(timeout);
    };
  }, [specContent]);

  // Handle spec selection - initiates the selection process
  // If requirement is in_progress, shows warning modal first
  const handleSelectSpec = async (filename: string) => {
    // Warn if unsaved changes
    if (hasChanges) {
      const confirm = window.confirm('You have unsaved changes. Discard them?');
      if (!confirm) return;
    }

    // Extract requirement ID from filename to check status
    const match = filename.match(/^(S-\d+)/);
    const reqId = match ? match[1] : null;

    if (reqId) {
      try {
        // Check requirement status before opening
        const status = await felixApi.getRequirementStatus(projectId, reqId);
        if (status.status === 'in_progress') {
          // Show warning modal - store pending spec for later
          setPendingSpecFilename(filename);
          setIsWarningModalOpen(true);
          return;
        }
      } catch (err) {
        // If status check fails, proceed anyway (graceful degradation)
        console.error('Failed to check requirement status:', err);
      }
    }

    // No warning needed - proceed with selection
    setSelectedFilename(filename);
    onSelectSpec?.(filename);
  };

  // Handle warning modal actions (S-0006: Spec Edit Safety)
  const handleWarningAction = async (action: WarningAction) => {
    if (action === 'cancel') {
      // User cancelled - close modal and clear pending spec
      setIsWarningModalOpen(false);
      setPendingSpecFilename(null);
      return;
    }

    if (action === 'continue') {
      // User chose to continue editing despite warning
      if (pendingSpecFilename) {
        setSelectedFilename(pendingSpecFilename);
        onSelectSpec?.(pendingSpecFilename);
      }
      setIsWarningModalOpen(false);
      setPendingSpecFilename(null);
      return;
    }

    if (action === 'block') {
      // User wants to block the requirement before editing
      if (!pendingRequirementId) {
        setIsWarningModalOpen(false);
        setPendingSpecFilename(null);
        return;
      }

      setIsBlockingRequirement(true);
      try {
        // Update requirement status to "blocked"
        await felixApi.updateRequirementStatus(projectId, pendingRequirementId, 'blocked');
        
        // Try to stop the agent if running
        try {
          await felixApi.stopRun(projectId);
        } catch (stopErr) {
          // Agent might not be running - that's okay
          console.log('Agent stop attempted (may not have been running):', stopErr);
        }

        // Now proceed with editing
        if (pendingSpecFilename) {
          setSelectedFilename(pendingSpecFilename);
          onSelectSpec?.(pendingSpecFilename);
        }
      } catch (err) {
        console.error('Failed to block requirement:', err);
        // Still allow editing even if blocking failed
        if (pendingSpecFilename) {
          setSelectedFilename(pendingSpecFilename);
          onSelectSpec?.(pendingSpecFilename);
        }
      } finally {
        setIsBlockingRequirement(false);
        setIsWarningModalOpen(false);
        setPendingSpecFilename(null);
      }
    }
  };

  // Handle Reset Plan button click (S-0006: Manual Reset Plan Controls)
  const handleResetPlanClick = () => {
    if (!selectedRequirementId || !selectedSpecHasPlan) return;
    setIsResetPlanModalOpen(true);
    setResetPlanMessage(null);
  };

  // Handle Reset Plan confirmation (S-0006: Manual Reset Plan Controls)
  const handleResetPlanConfirm = async () => {
    if (!selectedRequirementId) return;

    setIsResettingPlan(true);
    setResetPlanMessage(null);
    try {
      await felixApi.deletePlan(projectId, selectedRequirementId);
      // Refresh the requirement status to update the hasPlan flag
      await refreshSelectedSpecStatus();
      setResetPlanMessage({ type: 'success', text: 'Plan reset successfully' });
      // Close modal after short delay to show success message
      setTimeout(() => {
        setIsResetPlanModalOpen(false);
        setResetPlanMessage(null);
      }, 1500);
    } catch (err) {
      console.error('Failed to reset plan:', err);
      setResetPlanMessage({ 
        type: 'error', 
        text: err instanceof Error ? err.message : 'Failed to reset plan' 
      });
    } finally {
      setIsResettingPlan(false);
    }
  };

  // Handle Reset Plan cancel
  const handleResetPlanCancel = () => {
    setIsResetPlanModalOpen(false);
    setResetPlanMessage(null);
  };

  // Handle save
  const handleSave = async () => {
    if (!selectedFilename || !hasChanges) return;

    setSaving(true);
    setSaveMessage(null);
    
    // S-0006: Check if acceptance/validation criteria changed before saving
    // This is used to detect plan invalidation
    const criteriaChanged = hasCriteriaChanged;
    
    try {
      await felixApi.updateSpec(projectId, selectedFilename, specContent);
      setOriginalContent(specContent);
      
      // S-0006: If criteria changed, invalidate (delete) the plan
      if (criteriaChanged) {
        // Extract requirement ID from filename
        const match = selectedFilename.match(/^(S-\d+)/);
        const reqId = match ? match[1] : null;
        
        if (reqId) {
          try {
            // Check if a plan exists before attempting to delete
            const planInfo = await felixApi.getPlanInfo(projectId, reqId);
            if (planInfo.exists) {
              await felixApi.deletePlan(projectId, reqId);
              setSaveMessage({ type: 'success', text: 'Saved. Plan invalidated due to criteria changes.' });
              // Update original criteria to match the new saved content
              setOriginalCriteria(extractCriteriaSections(specContent));
              // Clear success message after 5 seconds (longer for the important message)
              setTimeout(() => setSaveMessage(null), 5000);
              return;
            }
          } catch (planErr) {
            // Plan deletion failed or plan doesn't exist - log but don't fail the save
            console.log('Plan invalidation skipped:', planErr);
          }
        }
        // Update original criteria even if no plan was deleted
        setOriginalCriteria(extractCriteriaSections(specContent));
      }
      
      setSaveMessage({ type: 'success', text: 'Saved successfully' });
      // Clear success message after 3 seconds
      setTimeout(() => setSaveMessage(null), 3000);
    } catch (err) {
      console.error('Failed to save spec:', err);
      setSaveMessage({ type: 'error', text: err instanceof Error ? err.message : 'Failed to save' });
    } finally {
      setSaving(false);
    }
  };

  // Handle opening the new spec modal
  const handleOpenNewSpec = () => {
    // Find the next available spec ID
    const existingIds = specs
      .map(s => parseSpecFilename(s.filename).id)
      .filter(id => id.match(/^S-\d+$/))
      .map(id => parseInt(id.replace('S-', ''), 10))
      .filter(n => !isNaN(n));
    
    const maxId = existingIds.length > 0 ? Math.max(...existingIds) : 0;
    const nextId = `S-${String(maxId + 1).padStart(4, '0')}`;
    
    setNewSpecId(nextId);
    setNewSpecTitle('');
    setNewSpecTemplate('basic');
    setCreateError(null);
    setIsNewSpecOpen(true);
  };

  // Handle creating a new spec
  const handleCreateSpec = async () => {
    if (!newSpecId.trim() || !newSpecTitle.trim()) {
      setCreateError('Spec ID and title are required');
      return;
    }

    // Validate spec ID format
    if (!newSpecId.match(/^S-\d{4}$/)) {
      setCreateError('Spec ID must be in format S-XXXX (e.g., S-0006)');
      return;
    }

    // Generate filename from ID and title
    const slugTitle = newSpecTitle
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '');
    const filename = `${newSpecId}-${slugTitle}.md`;

    // Generate content from template
    const template = SPEC_TEMPLATES[newSpecTemplate];
    const content = template.content(newSpecId, newSpecTitle);

    setIsCreating(true);
    setCreateError(null);
    try {
      await felixApi.createSpec(projectId, filename, content);
      
      // Refresh spec list
      const specList = await felixApi.listSpecs(projectId);
      setSpecs(specList);
      
      // Select the new spec
      setSelectedFilename(filename);
      onSelectSpec?.(filename);
      
      // Close the modal
      setIsNewSpecOpen(false);
    } catch (err) {
      console.error('Failed to create spec:', err);
      setCreateError(err instanceof Error ? err.message : 'Failed to create spec');
    } finally {
      setIsCreating(false);
    }
  };

  // Insert formatting at cursor position
  const insertFormatting = (prefix: string, suffix: string = '') => {
    if (!editorRef.current) return;
    const textarea = editorRef.current;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const text = textarea.value;
    const selectedText = text.substring(start, end);
    const newContent = text.substring(0, start) + prefix + selectedText + suffix + text.substring(end);

    setSpecContent(newContent);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + prefix.length, end + prefix.length);
    }, 0);
  };

  // Copy raw content to clipboard
  const copyToClipboard = () => {
    navigator.clipboard.writeText(specContent);
  };

  // Get selected spec's display info
  const selectedSpec = useMemo(() => {
    return specs.find(s => s.filename === selectedFilename);
  }, [specs, selectedFilename]);

  // Extract spec ID and title from filename (e.g., "S-0001-felix-agent.md")
  const parseSpecFilename = (filename: string): { id: string; title: string } => {
    const match = filename.match(/^(S-\d+)-(.+)\.md$/);
    if (match) {
      const title = match[2].split('-').map(word => 
        word.charAt(0).toUpperCase() + word.slice(1)
      ).join(' ');
      return { id: match[1], title };
    }
    return { id: '', title: filename };
  };

  return (
    <div className="flex-1 flex theme-bg-base overflow-hidden">
      {/* Specs List Sidebar */}
      <div className="w-64 border-r theme-border flex flex-col theme-bg-deep/40 flex-shrink-0">
        <div className="h-12 border-b border-slate-800/60 flex items-center px-4 justify-between">
          <span className="text-[10px] font-bold uppercase tracking-widest text-slate-500">
            Specifications
          </span>
          <span className="text-[10px] font-mono text-slate-600 bg-slate-900 px-1.5 py-0.5 rounded">
            {specs.length}
          </span>
        </div>

        {/* Scrollable Spec List */}
        <div className="p-3 space-y-1 overflow-y-auto custom-scrollbar flex-1">
          {specsLoading ? (
            <div className="flex items-center justify-center py-8">
              <div className="text-xs text-slate-500 animate-pulse">Loading specs...</div>
            </div>
          ) : specsError ? (
            <div className="text-xs text-red-400 p-3 bg-red-900/20 rounded-lg">
              {specsError}
            </div>
          ) : specs.length === 0 ? (
            <div className="text-xs text-slate-600 text-center py-8">
              No specs found
            </div>
          ) : (
            specs.map(spec => {
              const { id, title } = parseSpecFilename(spec.filename);
              return (
                <button
                  key={spec.filename}
                  onClick={() => handleSelectSpec(spec.filename)}
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs transition-all border ${
                    selectedFilename === spec.filename
                      ? 'bg-felix-600/10 text-felix-400 border-felix-500/20 shadow-lg shadow-felix-900/10'
                      : 'text-slate-500 border-transparent hover:text-slate-300 hover:bg-slate-800/50'
                  }`}
                >
                  <IconFileText className="w-4 h-4 flex-shrink-0" />
                  <div className="flex flex-col items-start min-w-0 flex-1">
                    <span className="truncate font-medium w-full text-left">{title}</span>
                    <span className="text-[9px] opacity-40 font-mono">{id}</span>
                  </div>
                </button>
              );
            })
          )}
        </div>

        {/* Fixed New Spec Button - Always visible at bottom */}
        <div className="p-3 border-t" style={{ borderColor: 'var(--border-default)' }}>
          <button
            onClick={handleOpenNewSpec}
            className="w-full flex items-center justify-center gap-2 px-4 py-2 bg-felix-500 hover:bg-felix-600 text-white rounded-lg text-xs font-semibold transition-colors"
            title="Create a new spec"
          >
            <IconPlus className="w-4 h-4" />
            <span>New Spec</span>
          </button>
        </div>
      </div>

      {/* Editor Pane */}
      <div className="flex-1 flex flex-col min-w-0 theme-bg-deep/20">
        {/* Toolbar */}
        <div className="h-12 border-b theme-border flex items-center px-4 justify-between theme-bg-base/95 backdrop-blur z-20 flex-shrink-0">
          <div className="flex items-center gap-4">
            {/* View mode toggle */}
            <div className="flex bg-slate-900 border border-slate-800 rounded-lg p-0.5 shadow-inner">
              <button
                onClick={() => setViewMode('edit')}
                className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${
                  viewMode === 'edit'
                    ? 'bg-slate-800 text-felix-400 shadow-sm'
                    : 'text-slate-500 hover:text-slate-400'
                }`}
              >
                SOURCE
              </button>
              <button
                onClick={() => setViewMode('split')}
                className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${
                  viewMode === 'split'
                    ? 'bg-slate-800 text-felix-400 shadow-sm'
                    : 'text-slate-500 hover:text-slate-400'
                }`}
              >
                SPLIT
              </button>
              <button
                onClick={() => setViewMode('preview')}
                className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${
                  viewMode === 'preview'
                    ? 'bg-slate-800 text-felix-400 shadow-sm'
                    : 'text-slate-500 hover:text-slate-400'
                }`}
              >
                PREVIEW
              </button>
            </div>

            {/* Formatting buttons (only in edit/split mode) */}
            {(viewMode === 'edit' || viewMode === 'split') && (
              <div className="flex items-center gap-0.5 border-l border-slate-800 pl-4">
                <button
                  onClick={() => insertFormatting('# ')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
                  title="H1"
                >
                  <span className="font-bold text-xs">H1</span>
                </button>
                <button
                  onClick={() => insertFormatting('## ')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
                  title="H2"
                >
                  <span className="font-bold text-xs">H2</span>
                </button>
                <button
                  onClick={() => insertFormatting('**', '**')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
                  title="Bold"
                >
                  <span className="font-bold text-xs uppercase">B</span>
                </button>
                <button
                  onClick={() => insertFormatting('*', '*')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
                  title="Italic"
                >
                  <span className="italic text-xs font-serif font-bold uppercase">I</span>
                </button>
                <button
                  onClick={() => insertFormatting('- ')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
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
                </button>
                <button
                  onClick={() => insertFormatting('`', '`')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
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
                </button>
                <button
                  onClick={() => insertFormatting('- [ ] ')}
                  className="p-1.5 text-slate-500 hover:text-felix-400 hover:bg-slate-800 rounded-md transition-all"
                  title="Checkbox"
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
                </button>
              </div>
            )}
          </div>

          <div className="flex items-center gap-4">
            {/* Save button */}
            <button
              onClick={handleSave}
              disabled={!hasChanges || saving}
              className={`px-3 py-1.5 text-[10px] font-bold uppercase rounded-lg transition-all flex items-center gap-2 ${
                hasChanges
                  ? 'bg-felix-600 text-white hover:bg-felix-500'
                  : 'bg-slate-800 text-slate-500 cursor-not-allowed'
              }`}
            >
              {saving ? (
                <>
                  <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Saving...
                </>
              ) : (
                <>
                  <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
            </button>

            {/* Save message */}
            {saveMessage && (
              <span
                className={`text-[10px] font-medium ${
                  saveMessage.type === 'success' ? 'text-emerald-400' : 'text-red-400'
                }`}
              >
                {saveMessage.text}
              </span>
            )}

            {/* Reset Plan button - S-0006: Manual Reset Plan Controls */}
            {selectedSpecHasPlan && (selectedSpecStatus?.status === 'planned' || selectedSpecStatus?.status === 'in_progress') && (
              <>
                <div className="h-4 w-px bg-slate-800"></div>
                <button
                  onClick={handleResetPlanClick}
                  className="px-3 py-1.5 text-[10px] font-bold uppercase rounded-lg transition-all flex items-center gap-2 bg-amber-600/20 text-amber-400 border border-amber-500/30 hover:bg-amber-600/30 hover:border-amber-500/50"
                  title="Delete the current plan for this requirement"
                >
                  <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      d="M4 4l16 16M4 20L20 4"
                      strokeWidth="2.5"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                  Reset Plan
                </button>
              </>
            )}

            {/* Copy button */}
            <button
              onClick={copyToClipboard}
              className="text-[10px] font-bold text-slate-500 hover:text-felix-400 transition-colors uppercase tracking-widest flex items-center gap-2"
            >
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
            </button>

            <div className="h-4 w-px bg-slate-800"></div>

            {/* Filename display */}
            <div className="flex items-center gap-2">
              {hasChanges && (
                <div className="w-1.5 h-1.5 rounded-full bg-amber-500" title="Unsaved changes" />
              )}
              <span className="text-[10px] font-mono text-slate-500 uppercase">
                {selectedFilename || 'No spec selected'}
              </span>
            </div>
          </div>
        </div>

        {/* Content Area */}
        {!selectedFilename ? (
          // No spec selected
          <div className="flex-1 flex flex-col items-center justify-center text-center p-8 theme-bg-deepest/20">
            <div className="w-16 h-16 theme-bg-surface rounded-2xl flex items-center justify-center mb-4">
              <IconFileText className="w-8 h-8 theme-text-faint" />
            </div>
            <h3 className="text-sm font-bold theme-text-tertiary mb-2">No Spec Selected</h3>
            <p className="text-xs theme-text-muted max-w-sm">
              Select a specification from the list to view and edit its content.
            </p>
          </div>
        ) : contentLoading ? (
          // Loading content
          <div className="flex-1 flex items-center justify-center theme-bg-deepest/20">
            <div className="flex items-center gap-3 theme-text-muted">
              <div className="w-5 h-5 border-2 theme-border border-t-felix-500 rounded-full animate-spin" />
              <span className="text-xs font-mono">Loading spec...</span>
            </div>
          </div>
        ) : contentError ? (
          // Error loading content
          <div className="flex-1 flex flex-col items-center justify-center p-8 theme-bg-deepest/20">
            <div className="bg-red-900/20 border border-red-500/20 rounded-xl px-6 py-4 max-w-md">
              <h3 className="text-sm font-bold text-red-400 mb-2">Failed to Load Spec</h3>
              <p className="text-xs text-red-300/70">{contentError}</p>
            </div>
          </div>
        ) : (
          // Editor and preview
          <div
            className={`flex-1 flex overflow-hidden ${
              viewMode === 'split' ? 'divide-x divide-slate-800/40' : ''
            }`}
          >
            {/* Editor pane */}
            {(viewMode === 'edit' || viewMode === 'split') && (
              <div className="flex-1 flex flex-col min-w-0 relative h-full">
                <textarea
                  ref={editorRef}
                  value={specContent}
                  onChange={(e) => setSpecContent(e.target.value)}
                  className="w-full h-full p-12 theme-bg-deepest theme-text-secondary font-mono text-sm leading-relaxed outline-none resize-none custom-scrollbar selection:bg-felix-500/30"
                  style={{ backgroundColor: 'var(--bg-deepest)' }}
                  placeholder="# Spec content..."
                />
                {viewMode === 'edit' && (
                  <div className="absolute top-4 right-4 text-[9px] font-mono text-slate-700 uppercase tracking-[0.2em] bg-slate-900/30 px-3 py-1 rounded-full border border-slate-800/50 backdrop-blur">
                    Source Editor
                  </div>
                )}
              </div>
            )}

            {/* Preview pane */}
            {(viewMode === 'preview' || viewMode === 'split') && (
              <div className="flex-1 flex flex-col min-w-0 h-full theme-bg-base/10 relative">
                <div className="flex-1 p-12 overflow-y-auto custom-scrollbar markdown-preview font-sans max-w-4xl mx-auto w-full">
                  <div dangerouslySetInnerHTML={{ __html: parsedHtml }} />
                  {!parsedHtml && (
                    <div className="flex flex-col items-center justify-center h-full text-slate-700 gap-4">
                      <IconFileText className="w-12 h-12 opacity-10" />
                      <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                        No content to preview
                      </span>
                    </div>
                  )}
                </div>
                {viewMode === 'preview' && (
                  <div className="absolute top-4 right-4 text-[9px] font-mono text-slate-700 uppercase tracking-[0.2em] bg-slate-900/30 px-3 py-1 rounded-full border border-slate-800/50 backdrop-blur">
                    Live Preview
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* New Spec Modal */}
      {isNewSpecOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="theme-bg-base border theme-border rounded-2xl shadow-2xl w-[480px] overflow-hidden">
            {/* Modal header */}
            <div className="h-12 border-b theme-border flex items-center justify-between px-4">
              <div className="flex items-center gap-2">
                <IconPlus className="w-4 h-4 text-felix-400" />
                <span className="text-xs font-bold theme-text-secondary">
                  Create New Spec
                </span>
              </div>
              <button
                onClick={() => setIsNewSpecOpen(false)}
                className="p-1.5 rounded-lg transition-all theme-text-muted hover:theme-text-secondary"
                style={{ backgroundColor: 'transparent' }}
                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = 'var(--hover-bg)'}
                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
              >
                <IconX className="w-4 h-4" />
              </button>
            </div>

            {/* Modal body */}
            <div className="p-4 space-y-4">
              {/* Spec ID */}
              <div>
                <label className="block text-[10px] font-bold theme-text-muted uppercase tracking-wider mb-2">
                  Spec ID *
                </label>
                <input
                  type="text"
                  value={newSpecId}
                  onChange={(e) => setNewSpecId(e.target.value.toUpperCase())}
                  placeholder="S-0006"
                  className="w-full theme-bg-elevated border theme-border-muted rounded-xl px-4 py-2.5 text-sm theme-text-secondary focus:ring-1 focus:ring-felix-500 focus:border-felix-500 transition-all outline-none font-mono"
                />
                <p className="mt-1.5 text-[9px] text-slate-600">
                  Format: S-XXXX (auto-incremented from existing specs)
                </p>
              </div>

              {/* Spec Title */}
              <div>
                <label className="block text-[10px] font-bold theme-text-muted uppercase tracking-wider mb-2">
                  Title *
                </label>
                <input
                  type="text"
                  value={newSpecTitle}
                  onChange={(e) => setNewSpecTitle(e.target.value)}
                  placeholder="My New Feature"
                  className="w-full theme-bg-elevated border theme-border-muted rounded-xl px-4 py-2.5 text-sm theme-text-secondary focus:ring-1 focus:ring-felix-500 focus:border-felix-500 transition-all outline-none"
                />
                <p className="mt-1.5 text-[9px] text-slate-600">
                  Filename will be: {newSpecId && newSpecTitle ? `${newSpecId}-${newSpecTitle.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}.md` : 'S-XXXX-your-title.md'}
                </p>
              </div>

              {/* Template Selection */}
              <div>
                <label className="block text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-2">
                  Template
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {(Object.keys(SPEC_TEMPLATES) as TemplateType[]).map((templateKey) => {
                    const template = SPEC_TEMPLATES[templateKey];
                    return (
                      <button
                        key={templateKey}
                        onClick={() => setNewSpecTemplate(templateKey)}
                        className={`p-3 rounded-xl border text-left transition-all ${
                          newSpecTemplate === templateKey
                            ? 'bg-felix-600/10 border-felix-500/30 text-felix-400'
                            : 'theme-bg-elevated theme-border-muted theme-text-tertiary hover:theme-border'
                        }`}
                      >
                        <div className="text-xs font-medium mb-1">{template.name}</div>
                        <div className="text-[9px] opacity-60">{template.description}</div>
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Error display */}
              {createError && (
                <div className="p-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs text-red-400">
                  {createError}
                </div>
              )}
            </div>

            {/* Modal footer */}
            <div className="h-14 border-t border-slate-800/60 flex items-center justify-end gap-3 px-4">
              <button
                onClick={() => setIsNewSpecOpen(false)}
                className="px-4 py-2 text-xs font-medium text-slate-500 hover:text-slate-300 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleCreateSpec}
                disabled={!newSpecId.trim() || !newSpecTitle.trim() || isCreating}
                className="px-4 py-2 bg-felix-600 text-white text-xs font-bold rounded-xl hover:bg-felix-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
              >
                {isCreating ? (
                  <>
                    <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Creating...
                  </>
                ) : (
                  <>
                    <IconPlus className="w-3 h-3" />
                    Create Spec
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reset Plan Confirmation Modal (S-0006: Manual Reset Plan Controls) */}
      {isResetPlanModalOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="theme-bg-base border theme-border rounded-2xl shadow-2xl w-[400px] overflow-hidden">
            {/* Modal header */}
            <div className="h-12 border-b border-slate-800/60 flex items-center justify-between px-4">
              <div className="flex items-center gap-2">
                <svg className="w-4 h-4 text-amber-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <span className="text-xs font-bold text-slate-300">
                  Reset Plan
                </span>
              </div>
              <button
                onClick={handleResetPlanCancel}
                disabled={isResettingPlan}
                className="p-1.5 hover:bg-slate-800 rounded-lg transition-all text-slate-500 hover:text-slate-300 disabled:opacity-50"
              >
                <IconX className="w-4 h-4" />
              </button>
            </div>

            {/* Modal body */}
            <div className="p-5">
              <div className="flex items-start gap-4 mb-4">
                <div className="w-10 h-10 bg-amber-500/10 rounded-xl flex items-center justify-center flex-shrink-0">
                  <svg className="w-5 h-5 text-amber-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </div>
                <div>
                  <h3 className="text-sm font-bold text-slate-200 mb-1">
                    Delete plan for {selectedRequirementId}?
                  </h3>
                  <p className="text-xs text-slate-500 leading-relaxed">
                    This will permanently delete the implementation plan for this requirement. 
                    The agent will need to regenerate the plan on the next run.
                  </p>
                </div>
              </div>

              {/* Show current plan info if available */}
              {selectedSpecStatus?.plan_modified_at && (
                <div className="bg-slate-800/40 rounded-lg p-3 mb-4">
                  <div className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">Current Plan</div>
                  <div className="text-xs text-slate-400">
                    Generated: {new Date(selectedSpecStatus.plan_modified_at).toLocaleString()}
                  </div>
                </div>
              )}

              {/* Feedback message */}
              {resetPlanMessage && (
                <div className={`p-2 rounded-lg text-xs mb-4 ${
                  resetPlanMessage.type === 'success' 
                    ? 'bg-emerald-500/10 border border-emerald-500/20 text-emerald-400' 
                    : 'bg-red-500/10 border border-red-500/20 text-red-400'
                }`}>
                  {resetPlanMessage.text}
                </div>
              )}
            </div>

            {/* Modal footer */}
            <div className="h-14 border-t border-slate-800/60 flex items-center justify-end gap-3 px-4">
              <button
                onClick={handleResetPlanCancel}
                disabled={isResettingPlan}
                className="px-4 py-2 text-xs font-medium text-slate-500 hover:text-slate-300 transition-colors disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                onClick={handleResetPlanConfirm}
                disabled={isResettingPlan || resetPlanMessage?.type === 'success'}
                className="px-4 py-2 bg-amber-600 text-white text-xs font-bold rounded-xl hover:bg-amber-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
              >
                {isResettingPlan ? (
                  <>
                    <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Deleting...
                  </>
                ) : resetPlanMessage?.type === 'success' ? (
                  <>
                    <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="3" d="M5 13l4 4L19 7" />
                    </svg>
                    Done
                  </>
                ) : (
                  <>
                    <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                    Delete Plan
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Warning modal for editing in_progress requirements (S-0006) */}
      <SpecEditWarningModal
        requirementId={pendingRequirementId || ''}
        requirementTitle={pendingSpecStatus?.title || parseSpecFilename(pendingSpecFilename || '').title}
        isOpen={isWarningModalOpen}
        isLoading={isBlockingRequirement}
        onAction={handleWarningAction}
      />
    </div>
  );
};

export default SpecsEditor;

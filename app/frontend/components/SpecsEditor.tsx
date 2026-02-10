import React, {
  useState,
  useEffect,
  useRef,
  useMemo,
  useCallback,
} from "react";
import {
  felixApi,
  SpecFile,
  Requirement,
  RequirementStatusResponse,
} from "../services/felixApi";
import { marked } from "marked";
import { IconChevronDown, IconFileText, IconPlus } from "./Icons";
import { Alert, AlertDescription } from "./ui/alert";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { Input } from "./ui/input";
import { Textarea } from "./ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";
import SpecEditWarningModal, { WarningAction } from "./SpecEditWarningModal";
import { useRequirementStatus } from "../hooks/useRequirementStatus";
import CopilotChat from "./CopilotChat";

/**
 * Extract acceptance criteria and validation criteria sections from markdown content.
 * Returns the combined criteria sections for change detection.
 *
 * Looks for sections starting with "## Acceptance Criteria" or "## Validation Criteria"
 * and captures content until the next heading of same or higher level.
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

    // Check if this is a criteria heading (## Acceptance Criteria or ## Validation Criteria)
    const isCriteriaHeading = /^##\s+(acceptance|validation)\s+criteria/i.test(
      trimmedLine,
    );

    // Check if this is a new section (any ## heading)
    const isHeading = /^##\s+/.test(trimmedLine);

    if (isCriteriaHeading) {
      // Start capturing this criteria section
      if (inCriteriaSection && currentSection.length > 0) {
        // Save previous section before starting new one
        sections.push(currentSection.join("\n"));
      }
      inCriteriaSection = true;
      currentSection = [line];
    } else if (inCriteriaSection) {
      if (isHeading) {
        // End of criteria section - reached a new ## heading
        sections.push(currentSection.join("\n"));
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
    sections.push(currentSection.join("\n"));
  }

  // Return combined sections, normalized for comparison
  // Trim each section and join with a delimiter for comparison
  return sections.map((s) => s.trim()).join("\n---SECTION---\n");
}

interface SpecsEditorProps {
  projectId: string;
  initialSpecFilename?: string;
  onSelectSpec?: (filename: string) => void;
}

type ViewMode = "edit" | "preview" | "split";

// Spec templates
const SPEC_TEMPLATES = {
  basic: {
    name: "Basic Spec",
    description: "A minimal spec template with essential sections",
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
    name: "Feature Spec",
    description: "Detailed feature specification with narrative",
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
    name: "Bug Fix Spec",
    description: "Template for documenting a bug fix",
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

const SpecsEditor: React.FC<SpecsEditorProps> = ({
  projectId,
  initialSpecFilename,
  onSelectSpec,
}) => {
  // Spec list state
  const [specs, setSpecs] = useState<SpecFile[]>([]);
  const [specsLoading, setSpecsLoading] = useState(true);
  const [specsError, setSpecsError] = useState<string | null>(null);
  const [specSectionOpen, setSpecSectionOpen] = useState({
    draft: true,
    planned: false,
    in_progress: false,
    blocked: false,
    done: false,
  });

  // Requirements state (for S-0015: Spec Screen Enhancements - search filtering)
  const [requirements, setRequirements] = useState<Requirement[]>([]);

  // Selected spec state
  const [selectedFilename, setSelectedFilename] = useState<string | null>(
    initialSpecFilename || null,
  );
  const [specContent, setSpecContent] = useState<string>("");
  const [originalContent, setOriginalContent] = useState<string>("");
  const [originalCriteria, setOriginalCriteria] = useState<string>(""); // For S-0006: Track original acceptance/validation criteria
  const [contentLoading, setContentLoading] = useState(false);
  const [contentError, setContentError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);

  // View mode and parsed markdown
  const [viewMode, setViewMode] = useState<ViewMode>("split");
  const [parsedHtml, setParsedHtml] = useState<string>("");

  // New spec modal state
  const [isNewSpecOpen, setIsNewSpecOpen] = useState(false);
  const [newSpecId, setNewSpecId] = useState("");
  const [newSpecTitle, setNewSpecTitle] = useState("");
  const [newSpecTemplate, setNewSpecTemplate] = useState<TemplateType>("basic");
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  // Warning modal state (for S-0006: Spec Edit Safety)
  const [pendingSpecFilename, setPendingSpecFilename] = useState<string | null>(
    null,
  );
  const [isWarningModalOpen, setIsWarningModalOpen] = useState(false);
  const [isBlockingRequirement, setIsBlockingRequirement] = useState(false);

  // Reset Plan modal state (for S-0006: Manual Reset Plan Controls)
  const [isResetPlanModalOpen, setIsResetPlanModalOpen] = useState(false);
  const [isResettingPlan, setIsResettingPlan] = useState(false);
  const [resetPlanMessage, setResetPlanMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);

  // Search state (for S-0015: Spec Screen Enhancements)
  const [searchQuery, setSearchQuery] = useState<string>("");

  // Requirement status cache for safety indicators (S-0015: Drift detection)
  const [requirementStatuses, setRequirementStatuses] = useState<
    Map<string, RequirementStatusResponse>
  >(new Map());

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
  const currentCriteria = useMemo(
    () => extractCriteriaSections(specContent),
    [specContent],
  );
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

  // Fetch requirements on mount or when projectId changes (for S-0015: search filtering)
  useEffect(() => {
    const fetchRequirements = async () => {
      try {
        const reqData = await felixApi.getRequirements(projectId);
        setRequirements(reqData.requirements);
      } catch (err) {
        // Don't fail the UI if requirements can't be fetched - search just won't work as well
        console.error("Failed to fetch requirements for search:", err);
        setRequirements([]);
      }
    };

    fetchRequirements();
  }, [projectId]);

  // Fetch requirement statuses for drift detection (S-0015: Safety Indicators)
  useEffect(() => {
    const fetchStatuses = async () => {
      if (requirements.length === 0) return;

      const statusMap = new Map<string, RequirementStatusResponse>();

      // Fetch status for each requirement (limit to first 20 to avoid too many API calls)
      const reqsToFetch = requirements.slice(0, 20);
      await Promise.all(
        reqsToFetch.map(async (req) => {
          try {
            const status = await felixApi.getRequirementStatus(
              projectId,
              req.id,
            );
            statusMap.set(req.id, status);
          } catch (err) {
            // Silently fail for individual status fetches
            console.debug(`Failed to fetch status for ${req.id}:`, err);
          }
        }),
      );

      setRequirementStatuses(statusMap);
    };

    fetchStatuses();
  }, [projectId, requirements]);

  // Filter specs based on search query (S-0015: Spec Screen Enhancements)
  const filteredSpecs = useMemo(() => {
    if (!searchQuery.trim()) return specs;

    const query = searchQuery.toLowerCase().trim();
    return specs.filter((spec) => {
      // Parse spec filename to get ID and title
      const { id: specId, title: specTitle } = parseSpecFilename(spec.filename);

      // Find matching requirement for this spec
      const req = requirements.find(
        (r) => r.spec_path.includes(spec.filename) || r.id === specId,
      );

      // Match on spec ID
      if (specId.toLowerCase().includes(query)) return true;

      // Match on spec title (derived from filename)
      if (specTitle.toLowerCase().includes(query)) return true;

      // Match on requirement data if available
      if (req) {
        // Match on requirement ID
        if (req.id.toLowerCase().includes(query)) return true;

        // Match on requirement title
        if (req.title.toLowerCase().includes(query)) return true;

        // Match on status
        if (req.status.toLowerCase().includes(query)) return true;

        // Match on labels
        if (req.labels.some((label) => label.toLowerCase().includes(query)))
          return true;
      }

      return false;
    });
  }, [specs, searchQuery, requirements]);

  // Fetch spec content when selection changes
  useEffect(() => {
    if (!selectedFilename) {
      setSpecContent("");
      setOriginalContent("");
      setOriginalCriteria("");
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
        console.error("Failed to fetch spec content:", err);
        setContentError(
          err instanceof Error ? err.message : "Failed to load spec",
        );
        setSpecContent("");
        setOriginalContent("");
        setOriginalCriteria("");
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
        const result = await marked.parse(specContent || "");
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
  }, [specContent]);

  // Handle spec selection - initiates the selection process
  // If requirement is in_progress, shows warning modal first
  const handleSelectSpec = async (filename: string) => {
    // Warn if unsaved changes
    if (hasChanges) {
      const confirm = window.confirm("You have unsaved changes. Discard them?");
      if (!confirm) return;
    }

    // Extract requirement ID from filename to check status
    const match = filename.match(/^(S-\d+)/);
    const reqId = match ? match[1] : null;

    if (reqId) {
      try {
        // Check requirement status before opening
        const status = await felixApi.getRequirementStatus(projectId, reqId);
        if (status.status === "in_progress") {
          // Show warning modal - store pending spec for later
          setPendingSpecFilename(filename);
          setIsWarningModalOpen(true);
          return;
        }
      } catch (err) {
        // If status check fails, proceed anyway (graceful degradation)
        console.error("Failed to check requirement status:", err);
      }
    }

    // No warning needed - proceed with selection
    setSelectedFilename(filename);
    onSelectSpec?.(filename);
  };

  // Handle warning modal actions (S-0006: Spec Edit Safety)
  const handleWarningAction = async (action: WarningAction) => {
    if (action === "cancel") {
      // User cancelled - close modal and clear pending spec
      setIsWarningModalOpen(false);
      setPendingSpecFilename(null);
      return;
    }

    if (action === "continue") {
      // User chose to continue editing despite warning
      if (pendingSpecFilename) {
        setSelectedFilename(pendingSpecFilename);
        onSelectSpec?.(pendingSpecFilename);
      }
      setIsWarningModalOpen(false);
      setPendingSpecFilename(null);
      return;
    }

    if (action === "reset_plan") {
      // User wants to reset the plan before editing (S-0015: Pre-Edit Warning Modal)
      if (!pendingRequirementId) {
        setIsWarningModalOpen(false);
        setPendingSpecFilename(null);
        return;
      }

      setIsBlockingRequirement(true);
      try {
        // Delete the plan file
        try {
          await felixApi.deletePlan(projectId, pendingRequirementId);
        } catch (delErr) {
          // Plan might not exist - that's okay
          console.log("Plan deletion attempted (may not exist):", delErr);
        }

        // Update requirement status to "planned"
        await felixApi.updateRequirementStatus(
          projectId,
          pendingRequirementId,
          "planned",
        );

        // Try to stop the agent if running
        try {
          await felixApi.stopRun(projectId);
        } catch (stopErr) {
          // Agent might not be running - that's okay
          console.log(
            "Agent stop attempted (may not have been running):",
            stopErr,
          );
        }

        // Now proceed with editing
        if (pendingSpecFilename) {
          setSelectedFilename(pendingSpecFilename);
          onSelectSpec?.(pendingSpecFilename);
        }

        // Refresh requirements to update the list
        const reqData = await felixApi.getRequirements(projectId);
        setRequirements(reqData.requirements);
      } catch (err) {
        console.error("Failed to reset plan:", err);
        // Still allow editing even if reset failed
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
      setResetPlanMessage({ type: "success", text: "Plan reset successfully" });
      // Close modal after short delay to show success message
      setTimeout(() => {
        setIsResetPlanModalOpen(false);
        setResetPlanMessage(null);
      }, 1500);
    } catch (err) {
      console.error("Failed to reset plan:", err);
      setResetPlanMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Failed to reset plan",
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
              setSaveMessage({
                type: "success",
                text: "Saved. Plan invalidated due to criteria changes.",
              });
              // Update original criteria to match the new saved content
              setOriginalCriteria(extractCriteriaSections(specContent));
              // Clear success message after 5 seconds (longer for the important message)
              setTimeout(() => setSaveMessage(null), 5000);
              return;
            }
          } catch (planErr) {
            // Plan deletion failed or plan doesn't exist - log but don't fail the save
            console.log("Plan invalidation skipped:", planErr);
          }
        }
        // Update original criteria even if no plan was deleted
        setOriginalCriteria(extractCriteriaSections(specContent));
      }

      setSaveMessage({ type: "success", text: "Saved successfully" });
      // Clear success message after 3 seconds
      setTimeout(() => setSaveMessage(null), 3000);
    } catch (err) {
      console.error("Failed to save spec:", err);
      setSaveMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Failed to save",
      });
    } finally {
      setSaving(false);
    }
  };

  // Handle opening the new spec modal
  const handleOpenNewSpec = () => {
    // Find the next available spec ID
    const existingIds = specs
      .map((s) => parseSpecFilename(s.filename).id)
      .filter((id) => id.match(/^S-\d+$/))
      .map((id) => parseInt(id.replace("S-", ""), 10))
      .filter((n) => !isNaN(n));

    const maxId = existingIds.length > 0 ? Math.max(...existingIds) : 0;
    const nextId = `S-${String(maxId + 1).padStart(4, "0")}`;

    setNewSpecId(nextId);
    setNewSpecTitle("");
    setNewSpecTemplate("basic");
    setCreateError(null);
    setIsNewSpecOpen(true);
  };

  // Handle creating a new spec
  const handleCreateSpec = async () => {
    if (!newSpecId.trim() || !newSpecTitle.trim()) {
      setCreateError("Spec ID and title are required");
      return;
    }

    // Validate spec ID format
    if (!newSpecId.match(/^S-\d{4}$/)) {
      setCreateError("Spec ID must be in format S-XXXX (e.g., S-0006)");
      return;
    }

    // Generate filename from ID and title
    const slugTitle = newSpecTitle
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
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
      console.error("Failed to create spec:", err);
      setCreateError(
        err instanceof Error ? err.message : "Failed to create spec",
      );
    } finally {
      setIsCreating(false);
    }
  };

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
    return specs.find((s) => s.filename === selectedFilename);
  }, [specs, selectedFilename]);

  // Extract spec ID and title from filename (e.g., "S-0001-felix-agent.md")
  const parseSpecFilename = (
    filename: string,
  ): { id: string; title: string } => {
    const match = filename.match(/^(S-\d+)-(.+)\.md$/);
    if (match) {
      const title = match[2]
        .split("-")
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(" ");
      return { id: match[1], title };
    }
    return { id: "", title: filename };
  };

  type SpecStatusKey = "draft" | "planned" | "in_progress" | "blocked" | "done";

  const statusSections: { key: SpecStatusKey; label: string }[] = [
    { key: "draft", label: "Draft" },
    { key: "planned", label: "Planned" },
    { key: "in_progress", label: "In Progress" },
    { key: "blocked", label: "Blocked" },
    { key: "done", label: "Done" },
  ];

  const getSpecStatusKey = (status?: string): SpecStatusKey => {
    switch (status?.toLowerCase()) {
      case "planned":
        return "planned";
      case "in_progress":
        return "in_progress";
      case "blocked":
        return "blocked";
      case "complete":
      case "done":
        return "done";
      default:
        return "draft";
    }
  };

  const getStatusBadgeClass = (status?: string) => {
    switch (status?.toLowerCase()) {
      case "in_progress":
        return "border-[var(--warning-500)]/30 bg-[var(--warning-500)]/10 text-[var(--warning-500)]";
      case "complete":
      case "done":
        return "border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]";
      case "blocked":
        return "border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]";
      case "planned":
        return "border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]";
      default:
        return "border-[var(--border-muted)] bg-[var(--bg-surface-100)] text-[var(--text-muted)]";
    }
  };

  const groupedSpecs = useMemo(() => {
    const groups: Record<SpecStatusKey, SpecFile[]> = {
      draft: [],
      planned: [],
      in_progress: [],
      blocked: [],
      done: [],
    };

    filteredSpecs.forEach((spec) => {
      const { id } = parseSpecFilename(spec.filename);
      const req = requirements.find(
        (r) => r.spec_path.includes(spec.filename) || r.id === id,
      );
      const statusKey = getSpecStatusKey(req?.status);
      groups[statusKey].push(spec);
    });

    return groups;
  }, [filteredSpecs, requirements]);

  const toggleSpecSection = (key: SpecStatusKey) => {
    setSpecSectionOpen((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const renderSpecRow = (spec: SpecFile) => {
    const { id, title } = parseSpecFilename(spec.filename);
    const req = requirements.find(
      (r) => r.spec_path.includes(spec.filename) || r.id === id,
    );

    const reqStatus = req ? requirementStatuses.get(req.id) : null;
    const hasDrift =
      reqStatus &&
      reqStatus.has_plan &&
      reqStatus.spec_modified_at &&
      reqStatus.plan_modified_at
        ? new Date(reqStatus.spec_modified_at) >
          new Date(reqStatus.plan_modified_at)
        : false;

    const isAgentActive = req?.status === "in_progress";

    return (
      <Button
        key={spec.filename}
        onClick={() => handleSelectSpec(spec.filename)}
        variant="ghost"
        size="sm"
        className={`w-full h-auto justify-start gap-3 px-3 py-2.5 rounded-xl text-xs border transition-colors ${
          selectedFilename === spec.filename
            ? "bg-[var(--brand-500)]/10 text-[var(--brand-500)] border-[var(--brand-500)]/20"
            : "border-transparent text-[var(--text-muted)] hover:bg-[var(--bg-surface-100)] hover:text-[var(--text-secondary)]"
        }`}
      >
        <div className="relative flex-shrink-0">
          <IconFileText className="w-4 h-4" />
          {hasDrift && !isAgentActive && (
            <span
              className="absolute -top-1 -right-1 text-[8px]"
              title="Spec modified after plan generated"
            >
              ⚠️
            </span>
          )}
          {isAgentActive && (
            <span
              className="absolute -top-1 -right-1 text-[8px] animate-pulse"
              title="Agent is currently running on this requirement"
            >
              🤖
            </span>
          )}
        </div>
        <div className="flex flex-col items-start min-w-0 flex-1">
          <div className="flex items-center gap-2 w-full">
            <span className="truncate font-medium text-left flex-1">
              {title}
            </span>
            {req && (
              <span
                className={`px-1.5 py-0.5 rounded text-[8px] font-bold uppercase tracking-wider flex-shrink-0 border ${getStatusBadgeClass(
                  req.status,
                )}`}
                title={`Status: ${req.status}`}
              >
                {req.status === "in_progress"
                  ? "IN PROG"
                  : req.status.slice(0, 4).toUpperCase()}
              </span>
            )}
          </div>
          <span className="text-[9px] opacity-40 font-mono">{id}</span>
        </div>
      </Button>
    );
  };

  return (
    <div className="flex-1 flex bg-[var(--bg-base)] overflow-hidden">
      {/* Specs List Sidebar */}
      <div className="w-80 border-r border-[var(--border-default)] flex flex-col bg-[var(--bg-deep)]/40 flex-shrink-0">
        <div className="h-12 border-b border-[var(--border-default)] flex items-center px-4 justify-between">
          <span className="text-[10px] font-bold uppercase tracking-widest text-[var(--text-muted)]">
            Specifications
          </span>
          <Badge className="text-[10px] font-mono px-1.5 py-0.5">
            {specs.length}
          </Badge>
        </div>

        {/* Search Bar - S-0015: Spec Screen Enhancements */}
        <div className="px-3 pt-3 pb-2 space-y-1.5">
          <div className="relative">
            <Input
              type="text"
              placeholder="Search specs..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="h-8 text-xs pr-8"
            />
            {searchQuery && (
              <Button
                onClick={() => setSearchQuery("")}
                variant="ghost"
                size="icon"
                className="absolute right-1 top-1/2 -translate-y-1/2 h-6 w-6"
                title="Clear search"
              >
                <IconX className="w-3.5 h-3.5" />
              </Button>
            )}
          </div>
        </div>

        {/* Search Results Count - S-0015 */}
        {!specsLoading && !specsError && searchQuery && (
          <div className="px-3 pb-1">
            <span className="text-[9px] font-mono text-[var(--text-muted)]">
              {filteredSpecs.length} / {specs.length} specs
            </span>
          </div>
        )}

        {/* Scrollable Spec List */}
        <div className="px-3 pb-3 space-y-1 overflow-y-auto custom-scrollbar flex-1">
          {specsLoading ? (
            <div className="flex items-center justify-center py-8">
              <div className="text-xs animate-pulse text-[var(--text-muted)]">
                Loading specs...
              </div>
            </div>
          ) : specsError ? (
            <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="text-[var(--destructive-500)]">
                {specsError}
              </AlertDescription>
            </Alert>
          ) : specs.length === 0 ? (
            <div className="text-xs text-[var(--text-muted)] text-center py-8">
              No specs found
            </div>
          ) : filteredSpecs.length === 0 ? (
            // No specs match search - S-0015
            <div className="text-center py-8">
              <div className="text-xs text-[var(--text-muted)]">
                No specs match your search
              </div>
              <Button
                onClick={() => setSearchQuery("")}
                variant="ghost"
                size="sm"
                className="mt-2 text-[10px] font-medium text-[var(--accent-primary)]"
              >
                Clear search
              </Button>
            </div>
          ) : (
            <div className="space-y-2">
              {statusSections.map((section) => {
                const sectionSpecs = groupedSpecs[section.key];
                if (sectionSpecs.length === 0 && section.key !== "draft") {
                  return null;
                }

                const isOpen = specSectionOpen[section.key];

                return (
                  <div key={section.key} className="space-y-1">
                    <Button
                      type="button"
                      onClick={() => toggleSpecSection(section.key)}
                      variant="ghost"
                      size="sm"
                      className={`w-full justify-between px-2 py-2 text-[10px] font-bold uppercase tracking-wider ${
                        isOpen
                          ? "bg-[var(--bg-surface-100)] text-[var(--text-secondary)]"
                          : "text-[var(--text-muted)] hover:bg-[var(--bg-surface-100)] hover:text-[var(--text-secondary)]"
                      }`}
                    >
                      <div className="flex items-center gap-2">
                        <span>{section.label}</span>
                        <Badge className="text-[9px] font-mono px-1.5 py-0.5">
                          {sectionSpecs.length}
                        </Badge>
                      </div>
                      <IconChevronDown
                        className={`w-3 h-3 transition-transform text-[var(--text-muted)] ${
                          isOpen ? "rotate-180" : ""
                        }`}
                      />
                    </Button>
                    {isOpen && (
                      <div className="space-y-1">
                        {sectionSpecs.map(renderSpecRow)}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Fixed New Spec Button - Always visible at bottom */}
        <div className="p-3 border-t border-[var(--border-default)]">
          <Button
            onClick={handleOpenNewSpec}
            size="sm"
            className="w-full"
            title="Create a new spec"
          >
            <IconPlus className="w-4 h-4" />
            <span>New Spec</span>
          </Button>
        </div>
      </div>

      {/* Editor Pane */}
      <div className="flex-1 flex flex-col min-w-0 bg-[var(--bg-base)]">
        {/* Toolbar */}
        <div className="h-12 border-b border-[var(--border-default)] flex items-center px-4 justify-between bg-[var(--bg-base)]/95 backdrop-blur z-20 flex-shrink-0">
          <div className="flex items-center gap-4">
            {/* View mode toggle */}
            <ToggleGroup
              type="single"
              value={viewMode}
              onValueChange={(value) => {
                if (value) setViewMode(value as ViewMode);
              }}
            >
              <ToggleGroupItem value="edit">SOURCE</ToggleGroupItem>
              <ToggleGroupItem value="split">SPLIT</ToggleGroupItem>
              <ToggleGroupItem value="preview">PREVIEW</ToggleGroupItem>
            </ToggleGroup>

            {/* Formatting buttons (only in edit/split mode) */}
            {(viewMode === "edit" || viewMode === "split") && (
              <div className="flex items-center gap-0.5 border-l border-[var(--border-default)] pl-4">
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
                  onClick={() => insertFormatting("**", "**")}
                  title="Bold"
                >
                  <span className="font-bold text-xs uppercase">B</span>
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => insertFormatting("*", "*")}
                  title="Italic"
                >
                  <span className="italic text-xs font-serif font-bold uppercase">
                    I
                  </span>
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
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => insertFormatting("- [ ] ")}
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
                </Button>
              </div>
            )}
          </div>

          <div className="flex items-center gap-4">
            {/* Save button */}
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

            {/* Reset Plan button - S-0006: Manual Reset Plan Controls */}
            {selectedSpecHasPlan &&
              (selectedSpecStatus?.status === "planned" ||
                selectedSpecStatus?.status === "in_progress") && (
                <>
                  <div className="h-4 w-px bg-[var(--border-default)]"></div>
                  <Button
                    onClick={handleResetPlanClick}
                    variant="secondary"
                    size="sm"
                    className="uppercase text-[var(--warning-500)] border-[var(--warning-500)]/30 hover:bg-[var(--warning-500)]/10"
                    title="Delete the current plan for this requirement"
                  >
                    <svg
                      className="w-3 h-3"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        d="M4 4l16 16M4 20L20 4"
                        strokeWidth="2.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                    Reset Plan
                  </Button>
                </>
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

            <div className="h-4 w-px bg-[var(--border-default)]"></div>

            {/* Filename display */}
            <div className="flex items-center gap-2">
              {hasChanges && (
                <div
                  className="w-1.5 h-1.5 rounded-full bg-[var(--warning-500)]"
                  title="Unsaved changes"
                />
              )}
              <span className="text-[10px] font-mono text-[var(--text-muted)] uppercase">
                {selectedFilename || "No spec selected"}
              </span>
            </div>
          </div>
        </div>

        {/* Content Area */}
        {!selectedFilename ? (
          // No spec selected
          <div className="flex-1 flex flex-col items-center justify-center text-center p-8 bg-[var(--bg-base)]">
            <div className="w-16 h-16 bg-[var(--bg-surface-200)] rounded-2xl flex items-center justify-center mb-4">
              <IconFileText className="w-8 h-8 text-[var(--text-lighter)]" />
            </div>
            <h3 className="text-sm font-bold text-[var(--text-lighter)] mb-2">
              No Spec Selected
            </h3>
            <p className="text-xs text-[var(--text-muted)] max-w-sm">
              Select a specification from the list to view and edit its content.
            </p>
          </div>
        ) : contentLoading ? (
          // Loading content
          <div className="flex-1 flex items-center justify-center bg-[var(--bg-base)]">
            <div className="flex items-center gap-3 text-[var(--text-muted)]">
              <div className="w-5 h-5 border-2 border-[var(--border-default)] border-t-brand-500 rounded-full animate-spin" />
              <span className="text-xs font-mono">Loading spec...</span>
            </div>
          </div>
        ) : contentError ? (
          // Error loading content
          <div className="flex-1 flex flex-col items-center justify-center p-8 bg-[var(--bg-base)]">
            <Alert className="max-w-md border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="text-[var(--destructive-500)]">
                <strong className="block text-sm">Failed to Load Spec</strong>
                <span className="text-xs opacity-80">{contentError}</span>
              </AlertDescription>
            </Alert>
          </div>
        ) : (
          // Editor and preview
          <div
            className={`flex-1 flex overflow-hidden ${
              viewMode === "split"
                ? "divide-x divide-[var(--border-muted)]"
                : ""
            }`}
          >
            {/* Editor pane */}
            {(viewMode === "edit" || viewMode === "split") && (
              <div className="flex-1 flex flex-col min-w-0 relative h-full">
                <Textarea
                  ref={editorRef}
                  value={specContent}
                  onChange={(e) => setSpecContent(e.target.value)}
                  className="w-full h-full p-12 font-mono text-sm leading-relaxed resize-none custom-scrollbar selection:bg-brand-500/30 border-0 rounded-none bg-[var(--bg-surface-100)] text-[var(--text-light)] focus-visible:ring-0 focus-visible:ring-offset-0"
                  placeholder="# Spec content..."
                />
                {viewMode === "edit" && (
                  <div className="absolute top-4 right-4 text-[9px] font-mono text-[var(--text-lighter)] uppercase tracking-[0.2em] bg-[var(--bg-alternative)]/30 px-3 py-1 rounded-full border border-[var(--border-secondary)] backdrop-blur">
                    Source Editor
                  </div>
                )}
              </div>
            )}

            {/* Preview pane */}
            {(viewMode === "preview" || viewMode === "split") && (
              <div className="flex-1 flex flex-col min-w-0 h-full bg-[var(--bg-base)]/10 relative">
                <div className="flex-1 p-12 overflow-y-auto custom-scrollbar markdown-preview font-sans max-w-4xl mx-auto w-full">
                  <div dangerouslySetInnerHTML={{ __html: parsedHtml }} />
                  {!parsedHtml && (
                    <div className="flex flex-col items-center justify-center h-full text-[var(--text-lighter)] gap-4">
                      <IconFileText className="w-12 h-12 opacity-10" />
                      <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                        No content to preview
                      </span>
                    </div>
                  )}
                </div>
                {viewMode === "preview" && (
                  <div className="absolute top-4 right-4 text-[9px] font-mono text-[var(--text-lighter)] uppercase tracking-[0.2em] bg-[var(--bg-alternative)]/30 px-3 py-1 rounded-full border border-[var(--border-secondary)] backdrop-blur">
                    Live Preview
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* New Spec Modal */}
      <Dialog open={isNewSpecOpen} onOpenChange={setIsNewSpecOpen}>
        <DialogContent className="max-w-[480px]">
          <DialogHeader>
            <div className="flex items-center gap-2">
              <IconPlus className="w-4 h-4 text-[var(--accent-primary)]" />
              <DialogTitle>Create New Spec</DialogTitle>
            </div>
            <DialogClose asChild>
              <Button variant="ghost" size="icon" className="h-8 w-8">
                <IconX className="w-4 h-4" />
              </Button>
            </DialogClose>
          </DialogHeader>

          <div className="p-4 space-y-4">
            <div>
              <label className="block text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-2">
                Spec ID *
              </label>
              <Input
                type="text"
                value={newSpecId}
                onChange={(e) => setNewSpecId(e.target.value.toUpperCase())}
                placeholder="S-0006"
                className="font-mono"
              />
              <p className="mt-1.5 text-[9px] text-[var(--text-muted)]">
                Format: S-XXXX (auto-incremented from existing specs)
              </p>
            </div>

            <div>
              <label className="block text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-2">
                Title *
              </label>
              <Input
                type="text"
                value={newSpecTitle}
                onChange={(e) => setNewSpecTitle(e.target.value)}
                placeholder="My New Feature"
              />
              <p className="mt-1.5 text-[9px] text-[var(--text-muted)]">
                Filename will be:{" "}
                {newSpecId && newSpecTitle
                  ? `${newSpecId}-${newSpecTitle
                      .toLowerCase()
                      .replace(/[^a-z0-9]+/g, "-")
                      .replace(/^-|-$/g, "")}.md`
                  : "S-XXXX-your-title.md"}
              </p>
            </div>

            <div>
              <label className="block text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-2">
                Template
              </label>
              <div className="grid grid-cols-3 gap-2">
                {(Object.keys(SPEC_TEMPLATES) as TemplateType[]).map(
                  (templateKey) => {
                    const template = SPEC_TEMPLATES[templateKey];
                    const isSelected = newSpecTemplate === templateKey;
                    return (
                      <Button
                        key={templateKey}
                        type="button"
                        variant="secondary"
                        size="sm"
                        onClick={() => setNewSpecTemplate(templateKey)}
                        className={`h-auto items-start text-left px-3 py-3 ${
                          isSelected
                            ? "border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]"
                            : "text-[var(--text-secondary)]"
                        }`}
                      >
                        <div>
                          <div className="text-xs font-medium mb-1">
                            {template.name}
                          </div>
                          <div className="text-[9px] opacity-60">
                            {template.description}
                          </div>
                        </div>
                      </Button>
                    );
                  },
                )}
              </div>
            </div>

            {createError && (
              <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                <AlertDescription className="text-[var(--destructive-500)]">
                  {createError}
                </AlertDescription>
              </Alert>
            )}
          </div>

          <DialogFooter>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setIsNewSpecOpen(false)}
            >
              Cancel
            </Button>
            <Button
              onClick={handleCreateSpec}
              disabled={!newSpecId.trim() || !newSpecTitle.trim() || isCreating}
              size="sm"
              className="uppercase"
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
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reset Plan Confirmation Modal (S-0006: Manual Reset Plan Controls) */}
      <AlertDialog
        open={isResetPlanModalOpen}
        onOpenChange={(open) => {
          if (!open) handleResetPlanCancel();
        }}
      >
        <AlertDialogContent className="max-w-[400px]">
          <AlertDialogHeader className="flex items-center justify-between border-b border-[var(--border-default)] px-4 py-3">
            <div className="flex items-center gap-2">
              <svg
                className="w-4 h-4 text-[var(--warning-500)]"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
              <AlertDialogTitle className="text-xs font-bold">
                Reset Plan
              </AlertDialogTitle>
            </div>
            <AlertDialogCancel asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8"
                disabled={isResettingPlan}
              >
                <IconX className="w-4 h-4" />
              </Button>
            </AlertDialogCancel>
          </AlertDialogHeader>

          <div className="p-5">
            <div className="flex items-start gap-4 mb-4">
              <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 bg-[var(--warning-500)]/10 text-[var(--warning-500)]">
                <svg
                  className="w-5 h-5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                  />
                </svg>
              </div>
              <div>
                <h3 className="text-sm font-bold text-[var(--text-light)] mb-1">
                  Delete plan for {selectedRequirementId}?
                </h3>
                <AlertDialogDescription className="text-xs leading-relaxed">
                  This will permanently delete the implementation plan for this
                  requirement. The agent will need to regenerate the plan on the
                  next run.
                </AlertDialogDescription>
              </div>
            </div>

            {selectedSpecStatus?.plan_modified_at && (
              <div className="rounded-lg border border-[var(--border-muted)] bg-[var(--bg-surface-100)] p-3 mb-4">
                <div className="text-[10px] text-[var(--text-muted)] uppercase tracking-wider mb-1">
                  Current Plan
                </div>
                <div className="text-xs text-[var(--text-muted)]">
                  Generated:{" "}
                  {new Date(
                    selectedSpecStatus.plan_modified_at,
                  ).toLocaleString()}
                </div>
              </div>
            )}

            {resetPlanMessage && (
              <Alert
                className={`mb-4 ${
                  resetPlanMessage.type === "success"
                    ? "border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]"
                    : "border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]"
                }`}
              >
                <AlertDescription
                  className={
                    resetPlanMessage.type === "success"
                      ? "text-[var(--brand-500)]"
                      : "text-[var(--destructive-500)]"
                  }
                >
                  {resetPlanMessage.text}
                </AlertDescription>
              </Alert>
            )}
          </div>

          <AlertDialogFooter className="flex items-center justify-end gap-3 border-t border-[var(--border-default)] px-4 py-3">
            <AlertDialogCancel asChild>
              <Button variant="ghost" size="sm" disabled={isResettingPlan}>
                Cancel
              </Button>
            </AlertDialogCancel>
            <Button
              onClick={handleResetPlanConfirm}
              disabled={isResettingPlan || resetPlanMessage?.type === "success"}
              size="sm"
              variant={
                resetPlanMessage?.type === "success"
                  ? "secondary"
                  : "destructive"
              }
              className="uppercase"
            >
              {isResettingPlan ? (
                <>
                  <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Deleting...
                </>
              ) : resetPlanMessage?.type === "success" ? (
                <>
                  <svg
                    className="w-3 h-3"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="3"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  Done
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
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                  Delete Plan
                </>
              )}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Warning modal for editing in_progress requirements (S-0006) */}
      <SpecEditWarningModal
        requirementId={pendingRequirementId || ""}
        requirementTitle={
          pendingSpecStatus?.title ||
          parseSpecFilename(pendingSpecFilename || "").title
        }
        isOpen={isWarningModalOpen}
        isLoading={isBlockingRequirement}
        onAction={handleWarningAction}
      />

      {/* S-0017: Felix Copilot Chat Assistant */}
      {/* CopilotChat renders its own floating button and panel */}
      <CopilotChat
        projectId={projectId}
        onInsertSpec={(content: string) => {
          // Insert the generated spec content into the editor
          // If no spec is currently selected, user needs to select or create one first
          if (!selectedFilename) {
            // Show alert if no spec is selected
            alert("Please select or create a spec first to insert content.");
            return;
          }
          // Replace or append to current content based on whether editor is empty
          if (!specContent.trim()) {
            // Editor is empty - replace with generated content
            setSpecContent(content);
          } else {
            // Editor has content - append at cursor or end
            // For simplicity, we'll append at the end with a separator
            setSpecContent((prev) => `${prev}\n\n---\n\n${content}`);
          }
        }}
      />
    </div>
  );
};

export default SpecsEditor;

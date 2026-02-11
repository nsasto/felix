import React, { useState } from "react";
import { Alert, AlertDescription } from "./ui/alert";
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
import { Plus as IconPlus, X as IconX } from "lucide-react";

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

interface SpecCreateDialogProps {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  onCreate: (
    id: string,
    title: string,
    template: TemplateType,
  ) => Promise<void>;
}

export default function SpecCreateDialog({
  isOpen,
  onOpenChange,
  onCreate,
}: SpecCreateDialogProps) {
  const [newSpecId, setNewSpecId] = useState("");
  const [newSpecTitle, setNewSpecTitle] = useState("");
  const [newSpecTemplate, setNewSpecTemplate] = useState<TemplateType>("basic");
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  const handleCreate = async () => {
    if (!newSpecId.trim() || !newSpecTitle.trim()) {
      setCreateError("Spec ID and Title are required");
      return;
    }

    setIsCreating(true);
    setCreateError(null);

    try {
      await onCreate(newSpecId, newSpecTitle, newSpecTemplate);
      // Reset form
      setNewSpecId("");
      setNewSpecTitle("");
      setNewSpecTemplate("basic");
      onOpenChange(false);
    } catch (error: any) {
      setCreateError(error.message || "Failed to create spec");
    } finally {
      setIsCreating(false);
    }
  };

  const generateFilename = () => {
    if (!newSpecId || !newSpecTitle) {
      return "S-XXXX-your-title.md";
    }
    const slug = newSpecTitle
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
    return `${newSpecId}-${slug}.md`;
  };

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[480px]">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <IconPlus className="w-4 h-4 text-[var(--brand-500)]" />
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
              Filename will be: {generateFilename()}
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
          <Button variant="ghost" size="sm" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={handleCreate}
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
  );
}

// Export templates for use by parent components
export { SPEC_TEMPLATES, type TemplateType };

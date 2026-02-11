import React, { useState, useEffect } from "react";
import { Requirement } from "../services/felixApi";
import { ValidationIssue } from "../utils/specParser";
import { Select } from "./ui/select";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { MultiSelect } from "./multi-select";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "./ui/tooltip";
import {
  AlertTriangle as IconAlertTriangle,
  X as IconX,
  Plus as IconPlus,
  Check as IconCheck,
  Tag as IconTag,
  SquareArrowRight,
  SquareArrowLeft,
  RefreshCwOff,
} from "lucide-react";

interface SpecMetadataPanelProps {
  requirement: Requirement | null;
  allRequirements: Requirement[];
  specContent: string;
  validationIssues: ValidationIssue[];
  onMetadataUpdate: (field: string, value: any) => Promise<void>;
  onSyncField: (
    direction: "markdown-to-metadata" | "metadata-to-markdown",
    field: string,
  ) => void;
  onOverviewChange: (content: string) => void;
  onDismissWarning: (field?: string) => void;
}

const PRIORITY_OPTIONS = [
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "critical", label: "Critical" },
];

const getStatusColor = (status: string): string => {
  switch (status) {
    case "draft":
      return "var(--status-draft)";
    case "planned":
      return "var(--status-planned)";
    case "in_progress":
      return "var(--status-in-progress)";
    case "complete":
      return "var(--status-complete)";
    case "done":
      return "var(--status-done)";
    case "blocked":
      return "var(--status-blocked)";
    default:
      return "var(--text-muted)";
  }
};

export function SpecMetadataPanel({
  requirement,
  allRequirements,
  specContent,
  validationIssues,
  onMetadataUpdate,
  onSyncField,
  onOverviewChange,
  onDismissWarning,
}: SpecMetadataPanelProps) {
  const [newTag, setNewTag] = useState("");
  const [isAddingTag, setIsAddingTag] = useState(false);
  const [updating, setUpdating] = useState<string | null>(null);
  const [editedTitle, setEditedTitle] = useState(requirement?.title || "");

  // Update local title when requirement changes
  useEffect(() => {
    if (requirement) {
      setEditedTitle(requirement.title);
    }
  }, [requirement]);

  if (!requirement) {
    return (
      <div className="flex-1 flex items-center justify-center p-8 text-[var(--text-muted)]">
        <p>No spec selected</p>
      </div>
    );
  }

  const handlePriorityChange = async (value: string) => {
    setUpdating("priority");
    try {
      await onMetadataUpdate("priority", value);
    } finally {
      setUpdating(null);
    }
  };

  const handleAddTag = async () => {
    if (!newTag.trim()) return;

    setUpdating("tags");
    try {
      const updatedTags = [...(requirement.tags || []), newTag.trim()];
      await onMetadataUpdate("tags", updatedTags);
      setNewTag("");
      setIsAddingTag(false);
    } finally {
      setUpdating(null);
    }
  };

  const handleRemoveTag = async (tagToRemove: string) => {
    setUpdating("tags");
    try {
      const updatedTags = (requirement.tags || []).filter(
        (tag) => tag !== tagToRemove,
      );
      await onMetadataUpdate("tags", updatedTags);
    } finally {
      setUpdating(null);
    }
  };

  const handleTitleChange = async (newTitle: string) => {
    setUpdating("title");
    try {
      await onMetadataUpdate("title", newTitle);
    } finally {
      setUpdating(null);
    }
  };

  return (
    <div className="h-full flex flex-col bg-[var(--bg-surface-100)]">
      <div className="flex-1 overflow-y-auto overflow-x-hidden p-4 space-y-6">
        {/* Validation Warnings - Per Field */}
        {validationIssues.map((issue) => (
          <div key={issue.field} className="mb-4">
            <div className="border border-yellow-500 rounded-md bg-yellow-50 dark:bg-yellow-900/20 p-4">
              <div className="flex items-start gap-3">
                <IconAlertTriangle className="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-yellow-800 dark:text-yellow-200 mb-2">
                    {issue.message}: {issue.field}
                  </div>
                  <div className="text-sm text-yellow-700 dark:text-yellow-300 space-y-1 mb-3">
                    <div className="break-words">
                      <span className="font-medium">Markdown:</span>{" "}
                      {Array.isArray(issue.markdownValue)
                        ? issue.markdownValue.length > 0
                          ? issue.markdownValue.join(", ")
                          : "None"
                        : issue.markdownValue || "None"}
                    </div>
                    <div className="break-words">
                      <span className="font-medium">Metadata:</span>{" "}
                      {Array.isArray(issue.metadataValue)
                        ? issue.metadataValue.length > 0
                          ? issue.metadataValue.join(", ")
                          : "None"
                        : issue.metadataValue || "None"}
                    </div>
                  </div>
                  <TooltipProvider>
                    <div className="flex gap-2">
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() =>
                              onSyncField("markdown-to-metadata", issue.field)
                            }
                            className="h-8 w-8 p-0"
                          >
                            <SquareArrowRight className="h-4 w-4" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>Use Markdown Value</p>
                        </TooltipContent>
                      </Tooltip>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() =>
                              onSyncField("metadata-to-markdown", issue.field)
                            }
                            className="h-8 w-8 p-0"
                          >
                            <SquareArrowLeft className="h-4 w-4" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>Use Metadata Value</p>
                        </TooltipContent>
                      </Tooltip>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => onDismissWarning(issue.field)}
                            className="h-8 w-8 p-0"
                          >
                            <RefreshCwOff className="h-4 w-4" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>Ignore</p>
                        </TooltipContent>
                      </Tooltip>
                    </div>
                  </TooltipProvider>
                </div>
              </div>
            </div>
          </div>
        ))}

        {/* Basic Info */}
        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className="text-xs text-[var(--text-muted)] block mb-1">
                Spec ID
              </label>
              <Badge variant="secondary" className="font-mono">
                {requirement.id}
              </Badge>
            </div>
            <div>
              <label className="text-xs text-[var(--text-muted)] block mb-1">
                Status
              </label>
              <Badge
                style={{
                  backgroundColor: `${getStatusColor(requirement.status)}33`,
                  color: getStatusColor(requirement.status),
                  borderColor: getStatusColor(requirement.status),
                }}
                className="border capitalize"
              >
                {requirement.status.replace("_", " ")}
              </Badge>
            </div>
            <div>
              <label className="text-xs text-[var(--text-muted)] block mb-1">
                Updated
              </label>
              <span className="text-sm text-[var(--text)]">
                {requirement.updated_at}
              </span>
            </div>
          </div>
          <div>
            <label className="text-xs text-[var(--text-muted)] block mb-1">
              Title
            </label>
            <Input
              value={editedTitle}
              onChange={(e) => setEditedTitle(e.target.value)}
              onBlur={() => {
                if (editedTitle !== requirement.title) {
                  handleTitleChange(editedTitle);
                }
              }}
              disabled={updating === "title"}
              className="w-full"
              placeholder="Spec title"
            />
          </div>
        </div>

        {/* Priority */}
        <div className="space-y-2">
          <label className="text-xs text-[var(--text-muted)] block mb-1">
            Priority
          </label>
          <ToggleGroup
            type="single"
            size="sm"
            value={requirement.priority}
            onValueChange={(value) => {
              if (value) handlePriorityChange(value);
            }}
            disabled={updating === "priority"}
            className="justify-start flex-wrap"
          >
            {PRIORITY_OPTIONS.map((option) => (
              <ToggleGroupItem key={option.value} value={option.value}>
                {option.label}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>

        {/* Dependencies */}
        <div className="space-y-2">
          <label className="text-xs text-[var(--text-muted)] block mb-1">
            Dependencies
          </label>
          <MultiSelect
            options={allRequirements
              .filter((req) => req.id !== requirement?.id)
              .map((req) => ({
                label: `${req.id} - ${req.title}`,
                value: req.id,
              }))}
            value={requirement.depends_on || []}
            onValueChange={(selected) =>
              onMetadataUpdate("depends_on", selected)
            }
            placeholder="Select dependencies..."
          />
        </div>

        {/* Tags */}
        <div className="space-y-2">
          <label className="text-xs text-[var(--text-muted)] block mb-1">
            Tags
          </label>
          <div className="flex flex-wrap gap-2">
            {(requirement.tags || []).map((tag) => (
              <Badge
                key={tag}
                variant="secondary"
                className="flex items-center gap-1"
              >
                <IconTag className="w-3 h-3" />
                {tag}
                <button
                  onClick={() => handleRemoveTag(tag)}
                  disabled={updating === "tags"}
                  className="ml-1 hover:text-[var(--destructive-500)]"
                >
                  <IconX className="w-3 h-3" />
                </button>
              </Badge>
            ))}
            {isAddingTag ? (
              <div className="flex gap-1 items-center">
                <Input
                  type="text"
                  placeholder="Tag name"
                  value={newTag}
                  onChange={(e) => setNewTag(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleAddTag();
                    if (e.key === "Escape") {
                      setIsAddingTag(false);
                      setNewTag("");
                    }
                  }}
                  className="w-32 h-7 text-xs"
                  autoFocus
                />
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={handleAddTag}
                  disabled={!newTag.trim() || updating === "tags"}
                  className="h-7 w-7 p-0"
                >
                  <IconCheck className="w-4 h-4" />
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setIsAddingTag(false);
                    setNewTag("");
                  }}
                  className="h-7 w-7 p-0"
                >
                  <IconX className="w-4 h-4" />
                </Button>
              </div>
            ) : (
              <Button
                size="sm"
                variant="outline"
                onClick={() => setIsAddingTag(true)}
                disabled={updating === "tags"}
                className="h-7"
              >
                <IconPlus className="w-3 h-3 mr-1" />
                Add Tag
              </Button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

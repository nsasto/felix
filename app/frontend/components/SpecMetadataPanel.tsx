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
  onSyncFromMarkdown: () => void;
  onSyncToMarkdown: () => void;
  onOverviewChange: (content: string) => void;
  onDismissWarning: () => void;
}

const STATUS_OPTIONS = [
  { value: "planned", label: "Planned" },
  { value: "in_progress", label: "In Progress" },
  { value: "blocked", label: "Blocked" },
  { value: "complete", label: "Complete" },
  { value: "done", label: "Done" },
];

const PRIORITY_OPTIONS = [
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "critical", label: "Critical" },
];

export function SpecMetadataPanel({
  requirement,
  allRequirements,
  specContent,
  validationIssues,
  onMetadataUpdate,
  onSyncFromMarkdown,
  onSyncToMarkdown,
  onOverviewChange,
  onDismissWarning,
}: SpecMetadataPanelProps) {
  const [newLabel, setNewLabel] = useState("");
  const [isAddingLabel, setIsAddingLabel] = useState(false);
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

  const handleStatusChange = async (value: string) => {
    setUpdating("status");
    try {
      await onMetadataUpdate("status", value);
    } finally {
      setUpdating(null);
    }
  };

  const handlePriorityChange = async (value: string) => {
    setUpdating("priority");
    try {
      await onMetadataUpdate("priority", value);
    } finally {
      setUpdating(null);
    }
  };

  const handleAddLabel = async () => {
    if (!newLabel.trim()) return;

    setUpdating("labels");
    try {
      const updatedLabels = [...(requirement.labels || []), newLabel.trim()];
      await onMetadataUpdate("labels", updatedLabels);
      setNewLabel("");
      setIsAddingLabel(false);
    } finally {
      setUpdating(null);
    }
  };

  const handleRemoveLabel = async (labelToRemove: string) => {
    setUpdating("labels");
    try {
      const updatedLabels = (requirement.labels || []).filter(
        (l) => l !== labelToRemove,
      );
      await onMetadataUpdate("labels", updatedLabels);
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

  const dependencyIssue = validationIssues.find(
    (issue) => issue.type === "dependency_mismatch",
  );

  return (
    <div className="h-full flex flex-col bg-[var(--bg-surface-100)]">
      <div className="flex-1 overflow-y-auto overflow-x-hidden p-4 space-y-6">
        {/* Validation Warnings */}
        {dependencyIssue && (
          <div className="bg-yellow-500/10 border border-yellow-500/30 rounded-md p-3 space-y-3">
            <div className="flex items-start gap-2">
              <IconAlertTriangle className="w-5 h-5 text-yellow-500 flex-shrink-0 mt-0.5" />
              <div className="flex-1 space-y-2">
                <p className="text-sm font-medium text-[var(--text)]">
                  {dependencyIssue.message}
                </p>
                <div className="text-xs text-[var(--text-muted)] space-y-1">
                  <div className="break-words">
                    <span className="font-medium">Markdown:</span>{" "}
                    {dependencyIssue.markdownValue.length > 0
                      ? dependencyIssue.markdownValue.join(", ")
                      : "None"}
                  </div>
                  <div className="break-words">
                    <span className="font-medium">Metadata:</span>{" "}
                    {dependencyIssue.metadataValue.length > 0
                      ? dependencyIssue.metadataValue.join(", ")
                      : "None"}
                  </div>
                </div>
                <TooltipProvider>
                  <div className="flex gap-2">
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={onSyncFromMarkdown}
                          className="h-8 w-8 p-0"
                        >
                          <SquareArrowRight className="h-4 w-4" />
                        </Button>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Use Markdown Values</p>
                      </TooltipContent>
                    </Tooltip>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={onSyncToMarkdown}
                          className="h-8 w-8 p-0"
                        >
                          <SquareArrowLeft className="h-4 w-4" />
                        </Button>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Update Markdown Section</p>
                      </TooltipContent>
                    </Tooltip>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={onDismissWarning}
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
        )}

        {/* Basic Info */}
        <div className="space-y-3">
          <h3 className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider">
            Basic Info
          </h3>
          <div className="space-y-2">
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
            <div>
              <label className="text-xs text-[var(--text-muted)] block mb-1">
                Updated
              </label>
              <span className="text-sm text-[var(--text)]">
                {requirement.updated_at}
              </span>
            </div>
          </div>
        </div>

        {/* Status */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider block">
            Status
          </label>
          <ToggleGroup
            type="single"
            size="sm"
            value={requirement.status}
            onValueChange={(value) => {
              if (value) handleStatusChange(value);
            }}
            disabled={updating === "status"}
            className="justify-start flex-wrap"
          >
            {STATUS_OPTIONS.map((option) => (
              <ToggleGroupItem key={option.value} value={option.value}>
                {option.label}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>

        {/* Priority */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider block">
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

        {/* Labels */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider block">
            Labels
          </label>
          <div className="flex flex-wrap gap-2">
            {(requirement.labels || []).map((label) => (
              <Badge
                key={label}
                variant="secondary"
                className="flex items-center gap-1"
              >
                <IconTag className="w-3 h-3" />
                {label}
                <button
                  onClick={() => handleRemoveLabel(label)}
                  disabled={updating === "labels"}
                  className="ml-1 hover:text-[var(--destructive-500)]"
                >
                  <IconX className="w-3 h-3" />
                </button>
              </Badge>
            ))}
            {isAddingLabel ? (
              <div className="flex gap-1 items-center">
                <Input
                  type="text"
                  placeholder="Label name"
                  value={newLabel}
                  onChange={(e) => setNewLabel(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleAddLabel();
                    if (e.key === "Escape") {
                      setIsAddingLabel(false);
                      setNewLabel("");
                    }
                  }}
                  className="w-32 h-7 text-xs"
                  autoFocus
                />
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={handleAddLabel}
                  disabled={!newLabel.trim() || updating === "labels"}
                  className="h-7 w-7 p-0"
                >
                  <IconCheck className="w-4 h-4" />
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setIsAddingLabel(false);
                    setNewLabel("");
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
                onClick={() => setIsAddingLabel(true)}
                disabled={updating === "labels"}
                className="h-7"
              >
                <IconPlus className="w-3 h-3 mr-1" />
                Add Label
              </Button>
            )}
          </div>
        </div>

        {/* Dependencies */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider block">
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
      </div>
    </div>
  );
}

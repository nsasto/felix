import React, { useState, useEffect } from "react";
import { Requirement } from "../services/felixApi";
import { ValidationIssue, parseSpecOverview } from "../utils/specParser";
import { Select } from "./ui/select";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import {
  AlertTriangle as IconAlertTriangle,
  X as IconX,
  Plus as IconPlus,
  Check as IconCheck,
  Tag as IconTag,
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
  const [overviewContent, setOverviewContent] = useState("");
  const [selectedDependency, setSelectedDependency] = useState("");
  const [editedTitle, setEditedTitle] = useState(requirement?.title || "");

  // Parse overview content from markdown when it changes
  useEffect(() => {
    if (specContent) {
      const parsed = parseSpecOverview(specContent);
      setOverviewContent(parsed);
    }
  }, [specContent]);

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

  const handleRemoveDependency = async (depToRemove: string) => {
    setUpdating("depends_on");
    try {
      const updatedDeps = (requirement.depends_on || []).filter(
        (d) => d !== depToRemove,
      );
      await onMetadataUpdate("depends_on", updatedDeps);
    } finally {
      setUpdating(null);
    }
  };

  const handleAddDependency = async () => {
    if (
      !selectedDependency ||
      requirement.depends_on?.includes(selectedDependency)
    ) {
      return;
    }

    setUpdating("depends_on");
    try {
      const updatedDeps = [
        ...(requirement.depends_on || []),
        selectedDependency,
      ];
      await onMetadataUpdate("depends_on", updatedDeps);
      setSelectedDependency("");
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

  const handleOverviewChange = (content: string) => {
    setOverviewContent(content);
    onOverviewChange(content);
  };

  const dependencyIssue = validationIssues.find(
    (issue) => issue.type === "dependency_mismatch",
  );

  // Filter available dependencies (exclude self and already selected)
  const availableDependencies = allRequirements.filter(
    (req) =>
      req.id !== requirement.id && !requirement.depends_on?.includes(req.id),
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
                <div className="flex gap-2 flex-wrap">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={onSyncFromMarkdown}
                    className="text-xs"
                  >
                    Use Markdown Values
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={onSyncToMarkdown}
                    className="text-xs"
                  >
                    Update Markdown Section
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={onDismissWarning}
                    className="text-xs"
                  >
                    Ignore
                  </Button>
                </div>
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
          <select
            value={requirement.status}
            onChange={(e) => handleStatusChange(e.target.value)}
            disabled={updating === "status"}
            className="w-full px-3 py-2 bg-[var(--bg)] border border-[var(--border)] rounded-md text-sm text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--primary-500)]"
          >
            {STATUS_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>

        {/* Priority */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider block">
            Priority
          </label>
          <select
            value={requirement.priority}
            onChange={(e) => handlePriorityChange(e.target.value)}
            disabled={updating === "priority"}
            className="w-full px-3 py-2 bg-[var(--bg)] border border-[var(--border)] rounded-md text-sm text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--primary-500)]"
          >
            {PRIORITY_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
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
          <div className="flex flex-wrap gap-2 w-full">
            {(requirement.depends_on || []).map((dep) => (
              <Badge
                key={dep}
                variant="secondary"
                className="flex items-center gap-1 font-mono break-all"
              >
                {dep}
                <button
                  onClick={() => handleRemoveDependency(dep)}
                  disabled={updating === "depends_on"}
                  className="ml-1 hover:text-[var(--destructive-500)]"
                >
                  <IconX className="w-3 h-3" />
                </button>
              </Badge>
            ))}
            {(requirement.depends_on || []).length === 0 && (
              <span className="text-sm text-[var(--text-muted)]">
                No dependencies
              </span>
            )}
          </div>
          {availableDependencies.length > 0 && (
            <div className="flex gap-2 items-center mt-2">
              <select
                value={selectedDependency}
                onChange={(e) => setSelectedDependency(e.target.value)}
                disabled={updating === "depends_on"}
                className="flex-1 px-3 py-2 text-sm bg-[var(--bg-surface-200)] text-[var(--text)] border border-[var(--border)] rounded-md focus:outline-none focus:ring-2 focus:ring-[var(--brand-400)]"
              >
                <option value="">Select dependency...</option>
                {availableDependencies.map((req) => (
                  <option key={req.id} value={req.id}>
                    {req.id} - {req.title}
                  </option>
                ))}
              </select>
              <Button
                size="sm"
                variant="outline"
                onClick={handleAddDependency}
                disabled={!selectedDependency || updating === "depends_on"}
                className="h-9"
              >
                <IconPlus className="w-4 h-4" />
              </Button>
            </div>
          )}
        </div>

        {/* Overview/Narrative */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-[var(--text)] uppercase tracking-wider block">
            Overview
          </label>
          <textarea
            value={overviewContent}
            onChange={(e) => handleOverviewChange(e.target.value)}
            disabled={updating === "overview"}
            className="w-full px-3 py-2 text-sm bg-[var(--bg-surface-200)] text-[var(--text)] border border-[var(--border)] rounded-md focus:outline-none focus:ring-2 focus:ring-[var(--brand-400)] min-h-[120px] resize-y"
            placeholder="Overview content from ## Overview section..."
          />
          <p className="text-xs text-[var(--text-muted)]">
            Changes to overview are reflected in the markdown editor. Save the
            spec to persist.
          </p>
        </div>
      </div>
    </div>
  );
}

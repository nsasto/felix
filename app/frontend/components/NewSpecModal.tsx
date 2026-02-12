import React, { useState, useEffect } from "react";
import { Requirement } from "../services/felixApi";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Badge } from "./ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import {
  Plus as IconPlus,
  X as IconX,
  FileText as IconFileText,
} from "lucide-react";

interface NewSpecModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreateSpec: (specData: NewSpecData) => Promise<void>;
  existingRequirements: Requirement[];
}

export interface NewSpecData {
  id: string;
  title: string;
  priority: string;
  tags: string[];
}

export function NewSpecModal({
  isOpen,
  onClose,
  onCreateSpec,
  existingRequirements,
}: NewSpecModalProps) {
  const [specId, setSpecId] = useState("");
  const [title, setTitle] = useState("");
  const [priority, setPriority] = useState("medium");
  const [tags, setTags] = useState<string[]>([]);
  const [newTag, setNewTag] = useState("");
  const [isAddingTag, setIsAddingTag] = useState(false);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Auto-suggest next spec ID
  useEffect(() => {
    if (isOpen && !specId) {
      const maxId = existingRequirements.reduce((max, req) => {
        const match = req.id.match(/S-(\d{4})/);
        if (match) {
          const num = parseInt(match[1], 10);
          return Math.max(max, num);
        }
        return max;
      }, 0);
      const nextId = `S-${String(maxId + 1).padStart(4, "0")}`;
      setSpecId(nextId);
    }
  }, [isOpen, existingRequirements, specId]);

  // Reset form when modal closes
  useEffect(() => {
    if (!isOpen) {
      setSpecId("");
      setTitle("");
      setPriority("medium");
      setTags([]);
      setNewTag("");
      setIsAddingTag(false);
      setError(null);
    }
  }, [isOpen]);

  const validateSpecId = (id: string): boolean => {
    // Must match pattern S-XXXX where XXXX is 4 digits
    const pattern = /^S-\d{4}$/;
    if (!pattern.test(id)) {
      setError("Spec ID must match pattern S-XXXX (e.g., S-0001)");
      return false;
    }

    // Must be unique
    if (existingRequirements.some((req) => req.id === id)) {
      setError(`Spec ID ${id} already exists`);
      return false;
    }

    setError(null);
    return true;
  };

  const handleAddTag = () => {
    if (!newTag.trim()) return;
    if (tags.includes(newTag.trim())) {
      setNewTag("");
      return;
    }
    setTags([...tags, newTag.trim()]);
    setNewTag("");
    setIsAddingTag(false);
  };

  const handleRemoveTag = (tagToRemove: string) => {
    setTags(tags.filter((tag) => tag !== tagToRemove));
  };

  const handleCreate = async () => {
    // Validate
    if (!validateSpecId(specId)) return;
    if (!title.trim()) {
      setError("Title is required");
      return;
    }

    setCreating(true);
    setError(null);

    try {
      await onCreateSpec({
        id: specId,
        title: `${specId}: ${title.trim()}`,
        priority,
        tags,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create spec");
    } finally {
      setCreating(false);
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="bg-[var(--bg-surface-200)] max-w-2xl">
        <DialogHeader>
          <DialogTitle className="text-[var(--text)] flex items-center gap-2">
            <IconFileText className="w-5 h-5" />
            Create New Spec
          </DialogTitle>
          <DialogDescription className="text-[var(--text-muted)]">
            Create a new requirement specification with structured metadata. The
            markdown file will be generated automatically.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* Error Message */}
          {error && (
            <div className="bg-red-500/10 border border-red-500/30 rounded-md p-3 text-sm text-red-500">
              {error}
            </div>
          )}

          {/* Spec ID */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-[var(--text)]">
              Spec ID <span className="text-red-500">*</span>
            </label>
            <Input
              value={specId}
              onChange={(e) => {
                setSpecId(e.target.value);
                setError(null);
              }}
              placeholder="S-0001"
              className="font-mono"
              autoFocus
            />
            <p className="text-xs text-[var(--text-muted)]">
              Format: S-XXXX (e.g., S-0057). Auto-suggested next available ID.
            </p>
          </div>

          {/* Title */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-[var(--text)]">
              Title <span className="text-red-500">*</span>
            </label>
            <Input
              value={title}
              onChange={(e) => {
                setTitle(e.target.value);
                setError(null);
              }}
              placeholder="Brief description of the spec"
            />
            <p className="text-xs text-[var(--text-muted)]">
              The spec ID will be automatically prepended to the title.
            </p>
          </div>

          {/* Priority */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-[var(--text)]">
              Priority
            </label>
            <Select value={priority} onValueChange={setPriority}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Select priority" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="low">Low</SelectItem>
                <SelectItem value="medium">Medium</SelectItem>
                <SelectItem value="high">High</SelectItem>
                <SelectItem value="critical">Critical</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Tags */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-[var(--text)]">
              Tags (optional)
            </label>
            <div className="flex flex-wrap gap-2">
              {tags.map((tag) => (
                <Badge
                  key={tag}
                  variant="secondary"
                  className="flex items-center gap-1"
                >
                  {tag}
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={() => handleRemoveTag(tag)}
                    className="ml-1 h-5 w-5 hover:text-[var(--destructive-500)]"
                  >
                    <IconX className="w-3 h-3" />
                  </Button>
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
                    disabled={!newTag.trim()}
                    className="h-7 w-7 p-0"
                  >
                    <IconPlus className="w-4 h-4" />
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
                  className="h-7"
                >
                  <IconPlus className="w-3 h-3 mr-1" />
                  Add Tag
                </Button>
              )}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={creating}>
            Cancel
          </Button>
          <Button
            onClick={handleCreate}
            disabled={creating || !specId || !title.trim()}
          >
            {creating ? "Creating..." : "Create Spec"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

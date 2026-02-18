import React, { useState, useMemo } from "react";
import { Requirement } from "../services/felixApi";
import { Badge } from "./ui/badge";
import { Card } from "./ui/card";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import {
  Search as IconSearch,
  ArrowUpDown as IconSort,
  Plus as IconPlus,
  LayoutGrid as IconLayoutGrid,
  List as IconList,
} from "lucide-react";
import { PageLoading } from "./ui/page-loading";
import DataSurface from "./DataSurface";
import FilterPopover from "./FilterPopover";
import DataTable from "./DataTable";

interface SpecsTableViewProps {
  requirements: Requirement[];
  loading: boolean;
  error: string | null;
  onSpecClick: (requirementCodeOrId: string) => void;
  onNewSpec: () => void;
}

type SortField = "id" | "title" | "status" | "priority" | "modified";
type SortOrder = "asc" | "desc";
type ViewMode = "table" | "cards";

const STATUS_COLORS = {
  draft:
    "bg-[var(--text-muted)]/10 text-[var(--text-muted)] border-[var(--text-muted)]/20",
  planned:
    "bg-[var(--brand-500)]/10 text-[var(--brand-500)] border-[var(--brand-500)]/20",
  in_progress:
    "bg-[var(--status-in-progress)]/10 text-[var(--status-in-progress)] border-[var(--status-in-progress)]/20",
  blocked:
    "bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] border-[var(--destructive-500)]/20",
  done: "bg-[var(--success-500)]/10 text-[var(--success-500)] border-[var(--success-500)]/20",
};

const PRIORITY_COLORS = {
  low: "bg-[var(--text-muted)]/10 text-[var(--text-muted)] border-[var(--text-muted)]/20",
  medium:
    "bg-[var(--brand-500)]/10 text-[var(--brand-500)] border-[var(--brand-500)]/20",
  high: "bg-[var(--warning-500)]/10 text-[var(--warning-500)] border-[var(--warning-500)]/20",
  critical:
    "bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] border-[var(--destructive-500)]/20",
};

export default function SpecsTableView({
  requirements,
  loading,
  error,
  onSpecClick,
  onNewSpec,
}: SpecsTableViewProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [filters, setFilters] = useState<Record<string, Set<string>>>({
    status: new Set(),
    priority: new Set(),
  });
  const [viewMode, setViewMode] = useState<ViewMode>("table");
  const [sortField, setSortField] = useState<SortField>("modified");
  const [sortOrder, setSortOrder] = useState<SortOrder>("desc");

  // Filter and sort requirements
  const filteredAndSortedRequirements = useMemo(() => {
    let filtered = requirements;

    // Apply search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(
        (req) =>
          req.id.toLowerCase().includes(query) ||
          req.title.toLowerCase().includes(query) ||
          req.tags.some((tag) => tag.toLowerCase().includes(query)),
      );
    }

    // Apply status filter
    if (filters.status.size > 0) {
      filtered = filtered.filter((req) => filters.status.has(req.status));
    }

    // Apply priority filter
    if (filters.priority.size > 0) {
      filtered = filtered.filter((req) => filters.priority.has(req.priority));
    }

    // Sort
    const sorted = [...filtered].sort((a, b) => {
      let comparison = 0;

      switch (sortField) {
        case "id":
          comparison = a.id.localeCompare(b.id);
          break;
        case "title":
          comparison = a.title.localeCompare(b.title);
          break;
        case "status":
          comparison = a.status.localeCompare(b.status);
          break;
        case "priority": {
          const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
          comparison =
            priorityOrder[a.priority as keyof typeof priorityOrder] -
            priorityOrder[b.priority as keyof typeof priorityOrder];
          break;
        }
        case "modified": {
          const aTime = a.spec_modified_at
            ? new Date(a.spec_modified_at).getTime()
            : 0;
          const bTime = b.spec_modified_at
            ? new Date(b.spec_modified_at).getTime()
            : 0;
          comparison = aTime - bTime;
          break;
        }
      }

      return sortOrder === "asc" ? comparison : -comparison;
    });

    return sorted;
  }, [requirements, searchQuery, filters, sortField, sortOrder]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortOrder(sortOrder === "asc" ? "desc" : "asc");
    } else {
      setSortField(field);
      setSortOrder("asc");
    }
  };

  const formatDate = (dateString: string | null | undefined) => {
    if (!dateString) return "-";
    const date = new Date(dateString);
    // Check if date is valid
    if (isNaN(date.getTime())) return "-";
    return new Intl.DateTimeFormat("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    }).format(date);
  };

  const getDriftIndicator = (req: Requirement) => {
    if (!req.has_plan || !req.spec_modified_at || !req.plan_modified_at) {
      return null;
    }
    const specTime = new Date(req.spec_modified_at).getTime();
    const planTime = new Date(req.plan_modified_at).getTime();
    return specTime > planTime ? "!" : null;
  };

  if (loading) {
    return <PageLoading message="Loading specifications..." />;
  }

  if (error) {
    return (
      <div className="flex flex-col h-full bg-[var(--bg)]">
        <div className="px-6 py-6">
          <div className="bg-[var(--destructive-500)]/10 border border-[var(--destructive-500)]/20 rounded-lg p-4">
            <p className="text-[var(--destructive-500)] font-medium">
              Error loading specifications
            </p>
            <p className="text-[var(--text-muted)] text-sm mt-1">{error}</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <DataSurface
      className="pt-6"
      surfaceVariant={viewMode === "table" ? "card" : "plain"}
      contentClassName={viewMode === "table" ? undefined : "rounded-lg"}
      search={
        <div className="relative w-full max-w-sm">
          <IconSearch className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-muted)]" />
          <Input
            type="text"
            placeholder="Search specs by ID, title, or tags..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9 h-9 text-sm"
          />
        </div>
      }
      filters={
        <FilterPopover
          groups={[
            {
              key: "status",
              label: "Status",
              options: [
                { label: "Draft", value: "draft" },
                { label: "Planned", value: "planned" },
                { label: "In Progress", value: "in_progress" },
                { label: "Blocked", value: "blocked" },
                { label: "Done", value: "done" },
              ],
            },
            {
              key: "priority",
              label: "Priority",
              options: [
                { label: "Low", value: "low" },
                { label: "Medium", value: "medium" },
                { label: "High", value: "high" },
                { label: "Critical", value: "critical" },
              ],
            },
          ]}
          value={filters}
          onChange={setFilters}
          label="Filter specs"
        />
      }
      actions={
        <Button onClick={onNewSpec} className="flex items-center gap-2 h-9">
          <IconPlus className="w-4 h-4" />
          New Spec
        </Button>
      }
      viewToggle={
        <ToggleGroup
          type="single"
          value={viewMode}
          onValueChange={(value) => {
            if (value) {
              setViewMode(value as ViewMode);
            }
          }}
          className="border border-[var(--border)] rounded-md"
        >
          <ToggleGroupItem value="cards" className="h-9 w-9">
            <IconLayoutGrid className="h-4 w-4" />
          </ToggleGroupItem>
          <ToggleGroupItem value="table" className="h-9 w-9">
            <IconList className="h-4 w-4" />
          </ToggleGroupItem>
        </ToggleGroup>
      }
      footer={
        <div className="text-[var(--text-muted)] text-sm">
          {filteredAndSortedRequirements.length} of {requirements.length} specs
        </div>
      }
    >
      {filteredAndSortedRequirements.length === 0 ? (
        <div className="flex items-center justify-center py-16">
          <div className="text-center">
            <p className="text-[var(--text-muted)] mb-4">
              {searchQuery ||
              filters.status.size > 0 ||
              filters.priority.size > 0
                ? "No specs match your filters"
                : "No specifications yet"}
            </p>
            {!searchQuery &&
              filters.status.size === 0 &&
              filters.priority.size === 0 && (
                <Button onClick={onNewSpec}>
                  <IconPlus className="w-4 h-4 mr-2" />
                  Create First Spec
                </Button>
              )}
          </div>
        </div>
      ) : viewMode === "table" ? (
        <DataTable
          data={filteredAndSortedRequirements}
          rowKey={(req) => req.id}
          onRowClick={(req) => onSpecClick(req.code || req.id)}
          columns={[
            {
              key: "id",
              header: (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-auto px-0 py-0 flex items-center gap-2 cursor-pointer select-none"
                  onClick={() => handleSort("id")}
                >
                  ID
                  <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                </Button>
              ),
              cell: (req) => req.id,
              className: "font-mono text-sm text-[var(--brand-400)]",
            },
            {
              key: "title",
              header: (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-auto px-0 py-0 flex items-center gap-2 cursor-pointer select-none"
                  onClick={() => handleSort("title")}
                >
                  Title
                  <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                </Button>
              ),
              className: "min-w-0",
              cell: (req) => {
                const driftIndicator = getDriftIndicator(req);
                return (
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="text-[var(--text)] truncate whitespace-nowrap">
                      {req.title}
                    </span>
                    {driftIndicator && (
                      <span
                        className="text-xs"
                        title="Spec modified after plan was created"
                      >
                        {driftIndicator}
                      </span>
                    )}
                  </div>
                );
              },
            },
            {
              key: "tags",
              header: "Tags",
              cell: (req) => (
                <div className="flex gap-1 items-center whitespace-nowrap overflow-hidden">
                  {req.tags.length > 0 ? (
                    <>
                      {req.tags.slice(0, 3).map((tag) => (
                        <span
                          key={tag}
                          className="text-[10px] px-1.5 py-0.5 rounded bg-[var(--bg-surface-200)] text-[var(--text-muted)]"
                        >
                          {tag}
                        </span>
                      ))}
                      {req.tags.length > 3 && (
                        <span className="text-[10px] px-1.5 py-0.5 text-[var(--text-muted)]">
                          +{req.tags.length - 3}
                        </span>
                      )}
                    </>
                  ) : (
                    <span className="table-secondary text-xs">-</span>
                  )}
                </div>
              ),
            },
            {
              key: "status",
              header: (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-auto px-0 py-0 flex items-center gap-2 cursor-pointer select-none"
                  onClick={() => handleSort("status")}
                >
                  Status
                  <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                </Button>
              ),
              cell: (req) => (
                <Badge
                  className={
                    STATUS_COLORS[req.status as keyof typeof STATUS_COLORS]
                  }
                >
                  {req.status.replace("_", " ")}
                </Badge>
              ),
            },
            {
              key: "priority",
              header: (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-auto px-0 py-0 flex items-center gap-2 cursor-pointer select-none"
                  onClick={() => handleSort("priority")}
                >
                  Priority
                  <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                </Button>
              ),
              cell: (req) => (
                <Badge
                  className={
                    PRIORITY_COLORS[
                      req.priority as keyof typeof PRIORITY_COLORS
                    ]
                  }
                >
                  {req.priority}
                </Badge>
              ),
            },
            {
              key: "modified",
              header: (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-auto px-0 py-0 flex items-center gap-2 cursor-pointer select-none"
                  onClick={() => handleSort("modified")}
                >
                  Last Modified
                  <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                </Button>
              ),
              cell: (req) => (
                <span className="table-secondary text-sm">
                  {formatDate(req.spec_modified_at)}
                </span>
              ),
            },
          ]}
          rowClassName={() => "h-14"}
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 py-2">
          {filteredAndSortedRequirements.map((req) => {
            const driftIndicator = getDriftIndicator(req);
            return (
              <Card
                key={req.id}
                selectable
                onClick={() => onSpecClick(req.code || req.id)}
              >
                <div className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-sm text-[var(--brand-400)]">
                          {req.id}
                        </span>
                        {driftIndicator && (
                          <span
                            className="text-xs"
                            title="Spec modified after plan was created"
                          >
                            {driftIndicator}
                          </span>
                        )}
                      </div>
                      <div className="text-[var(--text)]">{req.title}</div>
                    </div>
                    <div className="flex flex-col items-end gap-2">
                      <Badge
                        className={
                          STATUS_COLORS[
                            req.status as keyof typeof STATUS_COLORS
                          ]
                        }
                      >
                        {req.status.replace("_", " ")}
                      </Badge>
                      <Badge
                        className={
                          PRIORITY_COLORS[
                            req.priority as keyof typeof PRIORITY_COLORS
                          ]
                        }
                      >
                        {req.priority}
                      </Badge>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center justify-between text-sm text-[var(--text-muted)]">
                    <div>
                      {req.tags.length > 0 ? (
                        <div className="flex gap-1">
                          {req.tags.slice(0, 3).map((tag) => (
                            <span
                              key={tag}
                              className="text-[10px] px-1.5 py-0.5 rounded bg-[var(--bg-surface-200)] text-[var(--text-muted)]"
                            >
                              {tag}
                            </span>
                          ))}
                          {req.tags.length > 3 && (
                            <span className="text-[10px] px-1.5 py-0.5 text-[var(--text-muted)]">
                              +{req.tags.length - 3}
                            </span>
                          )}
                        </div>
                      ) : (
                        <span>No tags</span>
                      )}
                    </div>
                    <div>{formatDate(req.spec_modified_at)}</div>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </DataSurface>
  );
}

import React, { useState, useMemo } from "react";
import { Requirement } from "../services/felixApi";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Card } from "./ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "./ui/table";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import {
  Search as IconSearch,
  ArrowUpDown as IconSort,
  Plus as IconPlus,
} from "lucide-react";
import { PageLoading } from "./ui/page-loading";

interface SpecsTableViewProps {
  requirements: Requirement[];
  loading: boolean;
  error: string | null;
  onSpecClick: (specPath: string) => void;
  onNewSpec: () => void;
}

type SortField = "id" | "title" | "status" | "priority" | "modified";
type SortOrder = "asc" | "desc";

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
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [priorityFilter, setPriorityFilter] = useState<string>("all");
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
    if (statusFilter !== "all") {
      filtered = filtered.filter((req) => req.status === statusFilter);
    }

    // Apply priority filter
    if (priorityFilter !== "all") {
      filtered = filtered.filter((req) => req.priority === priorityFilter);
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
  }, [
    requirements,
    searchQuery,
    statusFilter,
    priorityFilter,
    sortField,
    sortOrder,
  ]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortOrder(sortOrder === "asc" ? "desc" : "asc");
    } else {
      setSortField(field);
      setSortOrder("asc");
    }
  };

  const formatDate = (dateString: string | null | undefined) => {
    if (!dateString) return "—";
    const date = new Date(dateString);
    // Check if date is valid
    if (isNaN(date.getTime())) return "—";
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
    return specTime > planTime ? "⚠️" : null;
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
    <div className="flex flex-col h-full bg-[var(--bg)]">
      <div>
        {/* New Spec Button */}
        <div className="h-14 flex items-center px-6 justify-end">
          <Button onClick={onNewSpec} className="flex items-center gap-2">
            <IconPlus className="w-4 h-4" />
            New Spec
          </Button>
        </div>

        {/* Search and filters */}
        <div className="px-6 py-3 flex flex-col gap-3">
          <div className="flex items-center gap-3">
            <div className="flex-1 relative">
              <IconSearch className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-muted)]" />
              <Input
                type="text"
                placeholder="Search specs by ID, title, or tags..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
              />
            </div>
          </div>

          <div className="flex items-center gap-3">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-40">
                <SelectValue placeholder="Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Statuses</SelectItem>
                <SelectItem value="draft">Draft</SelectItem>
                <SelectItem value="planned">Planned</SelectItem>
                <SelectItem value="in_progress">In Progress</SelectItem>
                <SelectItem value="blocked">Blocked</SelectItem>
                <SelectItem value="done">Done</SelectItem>
              </SelectContent>
            </Select>

            <Select value={priorityFilter} onValueChange={setPriorityFilter}>
              <SelectTrigger className="w-40">
                <SelectValue placeholder="Priority" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Priorities</SelectItem>
                <SelectItem value="low">Low</SelectItem>
                <SelectItem value="medium">Medium</SelectItem>
                <SelectItem value="high">High</SelectItem>
                <SelectItem value="critical">Critical</SelectItem>
              </SelectContent>
            </Select>

            <div className="text-[var(--text-muted)] text-sm ml-auto">
              {filteredAndSortedRequirements.length} of {requirements.length}{" "}
              specs
            </div>
          </div>
        </div>
      </div>

      {/* Table Content */}
      <div className="flex-1 overflow-y-auto custom-scrollbar px-6 py-4">
        {filteredAndSortedRequirements.length === 0 ? (
          <div className="flex items-center justify-center py-16">
            <div className="text-center">
              <p className="text-[var(--text-muted)] mb-4">
                {searchQuery ||
                statusFilter !== "all" ||
                priorityFilter !== "all"
                  ? "No specs match your filters"
                  : "No specifications yet"}
              </p>
              {!searchQuery &&
                statusFilter === "all" &&
                priorityFilter === "all" && (
                  <Button onClick={onNewSpec}>
                    <IconPlus className="w-4 h-4 mr-2" />
                    Create First Spec
                  </Button>
                )}
            </div>
          </div>
        ) : (
          <Card className="overflow-hidden">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent border-[var(--border)]">
                  <TableHead
                    className="cursor-pointer select-none"
                    onClick={() => handleSort("id")}
                  >
                    <div className="flex items-center gap-2">
                      ID
                      <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                    </div>
                  </TableHead>
                  <TableHead
                    className="cursor-pointer select-none"
                    onClick={() => handleSort("title")}
                  >
                    <div className="flex items-center gap-2">
                      Title
                      <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                    </div>
                  </TableHead>
                  <TableHead
                    className="cursor-pointer select-none"
                    onClick={() => handleSort("status")}
                  >
                    <div className="flex items-center gap-2">
                      Status
                      <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                    </div>
                  </TableHead>
                  <TableHead
                    className="cursor-pointer select-none"
                    onClick={() => handleSort("priority")}
                  >
                    <div className="flex items-center gap-2">
                      Priority
                      <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                    </div>
                  </TableHead>
                  <TableHead
                    className="cursor-pointer select-none"
                    onClick={() => handleSort("modified")}
                  >
                    <div className="flex items-center gap-2">
                      Last Modified
                      <IconSort className="w-3 h-3 text-[var(--text-muted)]" />
                    </div>
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredAndSortedRequirements.map((req) => {
                  const driftIndicator = getDriftIndicator(req);
                  return (
                    <TableRow
                      key={req.id}
                      className="cursor-pointer hover:bg-[var(--bg-surface-100)] transition-colors border-[var(--border)]"
                      onClick={() => onSpecClick(req.spec_path)}
                    >
                      <TableCell className="font-mono text-sm text-[var(--brand-400)]">
                        {req.id}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <span className="text-[var(--text)]">
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
                        {req.tags.length > 0 && (
                          <div className="flex gap-1 mt-1">
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
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge
                          className={
                            STATUS_COLORS[
                              req.status as keyof typeof STATUS_COLORS
                            ]
                          }
                        >
                          {req.status.replace("_", " ")}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Badge
                          className={
                            PRIORITY_COLORS[
                              req.priority as keyof typeof PRIORITY_COLORS
                            ]
                          }
                        >
                          {req.priority}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-[var(--text-muted)] text-sm">
                        {formatDate(req.spec_modified_at)}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>
    </div>
  );
}

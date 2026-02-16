import React, { useEffect, useMemo, useState } from "react";
import {
  felixApi,
  ProjectDetails,
  Requirement,
  RunHistoryEntry,
} from "../services/felixApi";
import { listAgents } from "../src/api/client";
import type { Agent } from "../src/api/types";
import {
  Kanban as IconKanban,
  FileText as IconFileText,
  Terminal as IconTerminal,
  Activity as IconPulse,
} from "lucide-react";
import { Alert, AlertDescription } from "./ui/alert";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import { Card } from "./ui/card";
import { EmptyState } from "./ui/empty-state";
import { Input } from "./ui/input";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import { getRequirementStatusBadgeClass } from "../lib/status";

interface ProjectDashboardProps {
  projectId: string;
  project: ProjectDetails;
  onNavigate: (view: string) => void;
}

type DashboardAgent = {
  id: number;
  name: string;
  status: AgentEntry["status"];
  hostname?: string | null;
  executable?: string | null;
  currentRunId?: string | null;
  workflowStage?: string | null;
  source: "registry" | "config";
};

const formatDateTime = (value: string | null) => {
  if (!value) return "--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "--";
  return date.toLocaleString(undefined, {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
};

const ProjectDashboard: React.FC<ProjectDashboardProps> = ({
  projectId,
  project,
  onNavigate,
}) => {
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [runs, setRuns] = useState<RunHistoryEntry[]>([]);
  const [registryAgents, setRegistryAgents] = useState<Agent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [agentQuery, setAgentQuery] = useState("");
  const [agentDensity, setAgentDensity] = useState<"grid" | "compact">(
    "compact",
  );

  useEffect(() => {
    let isMounted = true;
    const loadDashboardData = async () => {
      setLoading(true);
      setError(null);
      const results = await Promise.allSettled([
        felixApi.getRequirements(projectId),
        felixApi.listRuns(projectId),
        listAgents({ scope: "project", projectId }),
      ]);

      if (!isMounted) return;

      const [requirementsResult, runsResult, agentsResult] = results;
      if (requirementsResult.status === "fulfilled") {
        setRequirements(requirementsResult.value.requirements || []);
      }
      if (runsResult.status === "fulfilled") {
        setRuns(runsResult.value.runs || []);
      }
      if (agentsResult.status === "fulfilled") {
        setRegistryAgents(agentsResult.value.agents || []);
      }

      if (
        requirementsResult.status === "rejected" &&
        runsResult.status === "rejected" &&
        agentsResult.status === "rejected"
      ) {
        setError("Unable to load dashboard telemetry.");
      }

      setLoading(false);
    };

    loadDashboardData();

    return () => {
      isMounted = false;
    };
  }, [projectId]);

  const statusCounts = useMemo(() => {
    const counts = {
      draft: 0,
      planned: 0,
      in_progress: 0,
      blocked: 0,
      done: 0,
      other: 0,
    };

    requirements.forEach((req) => {
      switch (req.status) {
        case "draft":
          counts.draft += 1;
          break;
        case "planned":
          counts.planned += 1;
          break;
        case "in_progress":
          counts.in_progress += 1;
          break;
        case "blocked":
          counts.blocked += 1;
          break;
        case "complete":
        case "done":
          counts.done += 1;
          break;
        default:
          counts.other += 1;
      }
    });

    return counts;
  }, [requirements]);

  const totalRequirements = requirements.length;
  const completionRate = totalRequirements
    ? Math.round((statusCounts.done / totalRequirements) * 100)
    : 0;

  const coverageScore = useMemo(() => {
    const signals = [
      project.has_specs,
      project.has_plan,
      project.has_requirements,
    ];
    const filled = signals.filter(Boolean).length;
    return Math.round((filled / signals.length) * 100);
  }, [project.has_specs, project.has_plan, project.has_requirements]);

  const recentRuns = useMemo(() => {
    return [...runs]
      .sort(
        (a, b) =>
          new Date(b.started_at).getTime() - new Date(a.started_at).getTime(),
      )
      .slice(0, 5);
  }, [runs]);

  const requirementsPreview = useMemo(() => {
    return [...requirements]
      .sort(
        (a, b) =>
          new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime(),
      )
      .slice(0, 5);
  }, [requirements]);

  const statusSegments = [
    { key: "draft", label: "Draft", color: "bg-[var(--status-draft)]" },
    { key: "planned", label: "Planned", color: "bg-[var(--status-planned)]" },
    {
      key: "in_progress",
      label: "In Progress",
      color: "bg-[var(--status-in-progress)]",
    },
    { key: "blocked", label: "Blocked", color: "bg-[var(--status-blocked)]" },
    { key: "done", label: "Done", color: "bg-[var(--status-done)]" },
    { key: "other", label: "Other", color: "bg-[var(--destructive-500)]/40" },
  ];

  const agentStatusColor = (status: DashboardAgent["status"]) => {
    switch (status) {
      case "active":
        return "bg-[var(--brand-500)]";
      case "stale":
        return "bg-[var(--warning-500)]";
      case "stopped":
        return "bg-[var(--destructive-500)]";
      case "inactive":
        return "bg-[var(--text-muted)]";
      case "not-started":
        return "bg-[var(--border-muted)]";
      default:
        return "bg-[var(--text-muted)]";
    }
  };

  const formatStage = (agent: DashboardAgent) => {
    if (agent.workflowStage) {
      return agent.workflowStage.replace(/_/g, " ");
    }
    if (agent.currentRunId) {
      return `Run ${agent.currentRunId}`;
    }
    return agent.status === "active" ? "Active" : "Idle";
  };

  const combinedAgents = useMemo<DashboardAgent[]>(() => {
    return registryAgents
      .filter((agent) => agent.id) // Filter out agents without IDs
      .map((agent) => ({
        id: agent.id,
        name: agent.name,
        status: agent.status,
        hostname: agent.hostname || null,
        executable: null,
        currentRunId: (agent.metadata?.current_run_id as string | null) || null,
        workflowStage:
          (agent.metadata?.current_workflow_stage as string | null) || null,
        source: "registry" as const,
      }))
      .sort((a, b) => (a.name || "").localeCompare(b.name || ""));
  }, [registryAgents]);

  const agentMetrics = useMemo(() => {
    const metrics = {
      total: combinedAgents.length,
      active: 0,
      stale: 0,
      stopped: 0,
      inactive: 0,
      notStarted: 0,
    };

    combinedAgents.forEach((agent) => {
      switch (agent.status) {
        case "active":
          metrics.active += 1;
          break;
        case "stale":
          metrics.stale += 1;
          break;
        case "stopped":
          metrics.stopped += 1;
          break;
        case "inactive":
          metrics.inactive += 1;
          break;
        case "not-started":
          metrics.notStarted += 1;
          break;
        default:
          break;
      }
    });

    return metrics;
  }, [combinedAgents]);

  const filteredAgents = useMemo(() => {
    const query = agentQuery.trim().toLowerCase();
    if (!query) return combinedAgents;
    return combinedAgents.filter((agent) =>
      [agent.name, agent.hostname ?? "", agent.executable ?? ""]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(query)),
    );
  }, [combinedAgents, agentQuery]);

  const formatAvailability = (status: DashboardAgent["status"]) => {
    return status === "active" ? "Running" : "Unavailable";
  };

  return (
    <div className="flex-1 overflow-y-auto custom-scrollbar theme-bg-base">
      <div className="w-full px-6 py-6 space-y-8">
        <div className="flex flex-wrap items-start justify-between gap-6">
          <div>
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-2xl font-semibold theme-text-secondary">
                {project.name || project.path.split(/[\\/]/).pop()}
              </h1>
              <Badge className="text-[10px] uppercase tracking-[0.2em]">
                {project.status || "active"}
              </Badge>
            </div>
            <p className="text-xs font-mono mt-1 theme-text-muted">
              {project.path}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              onClick={() => onNavigate("kanban")}
              variant="secondary"
              size="sm"
              className="uppercase tracking-[0.2em] text-[10px]"
            >
              <IconKanban className="w-3.5 h-3.5" />
              Requirements
            </Button>
            <Button
              onClick={() => onNavigate("assets")}
              variant="secondary"
              size="sm"
              className="uppercase tracking-[0.2em] text-[10px]"
            >
              <IconFileText className="w-3.5 h-3.5" />
              Specs
            </Button>
            <Button
              onClick={() => onNavigate("orchestration")}
              variant="secondary"
              size="sm"
              className="uppercase tracking-[0.2em] text-[10px]"
            >
              <IconTerminal className="w-3.5 h-3.5" />
              Orchestration
            </Button>
          </div>
        </div>

        {error && (
          <Alert className="border-[var(--border-default)] bg-[var(--bg-surface-100)]">
            <AlertDescription className="text-xs theme-text-secondary">
              {error}
            </AlertDescription>
          </Alert>
        )}

        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          <Card className="xl:col-span-2 rounded-2xl p-6">
            <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
              <div>
                <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
                  Workflow Saturation
                </span>
                <p className="text-xl font-semibold mt-2 theme-text-secondary">
                  {totalRequirements || "No"} active requirements
                </p>
              </div>
              <div className="text-right">
                <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
                  Completion
                </span>
                <div className="text-xl font-semibold theme-text-secondary">
                  {completionRate}%
                </div>
              </div>
            </div>
            <progress
              className="w-full h-3 overflow-hidden rounded-full bg-[var(--bg-base)] [&::-webkit-progress-bar]:bg-[var(--bg-base)] [&::-webkit-progress-value]:bg-[var(--brand-500)] [&::-moz-progress-bar]:bg-[var(--brand-500)]"
              value={completionRate}
              max={100}
            >
              {completionRate}%
            </progress>
            <div className="flex flex-wrap justify-between gap-2 mt-4 text-[10px] font-mono">
              {statusSegments.map((segment) => (
                <div
                  key={segment.key}
                  className="flex items-center gap-2 theme-text-muted"
                >
                  <span className={`w-2 h-2 rounded-full ${segment.color}`} />
                  {segment.label} (
                  {statusCounts[segment.key as keyof typeof statusCounts]})
                </div>
              ))}
            </div>
          </Card>

          <Card className="rounded-2xl p-6 flex flex-col justify-between">
            <div>
              <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
                Context Coverage
              </span>
              <div className="mt-6 space-y-3">
                <div className="flex items-center justify-between text-xs">
                  <span className="theme-text-secondary">
                    Specs, Plan, Requirements
                  </span>
                  <span className="font-mono theme-text-secondary">
                    {coverageScore}%
                  </span>
                </div>
                <progress
                  className="w-full h-2 overflow-hidden rounded-full bg-[var(--bg-base)] [&::-webkit-progress-bar]:bg-[var(--bg-base)] [&::-webkit-progress-value]:bg-[var(--brand-500)] [&::-moz-progress-bar]:bg-[var(--brand-500)]"
                  value={coverageScore}
                  max={100}
                >
                  {coverageScore}%
                </progress>
              </div>
            </div>
            <div className="mt-6">
              <div className="flex items-center justify-between text-xs">
                <span className="theme-text-muted">Specs</span>
                <span className="theme-text-secondary">
                  {project.spec_count} files
                </span>
              </div>
              <div className="flex items-center justify-between text-xs mt-2">
                <span className="theme-text-muted">Plan</span>
                <span className="theme-text-secondary">
                  {project.has_plan ? "Available" : "Missing"}
                </span>
              </div>
              <div className="flex items-center justify-between text-xs mt-2">
                <span className="theme-text-muted">Requirements</span>
                <span className="theme-text-secondary">
                  {project.has_requirements ? "Mapped" : "Empty"}
                </span>
              </div>
            </div>
          </Card>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <Card className="rounded-2xl p-6">
            <div className="flex items-center justify-between mb-4">
              <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
                Project Pulse
              </span>
              <IconPulse className="w-4 h-4 theme-text-muted" />
            </div>
            <div className="space-y-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="theme-text-muted">Last run</span>
                <span className="theme-text-secondary">
                  {recentRuns[0]
                    ? formatDateTime(recentRuns[0].started_at)
                    : "--"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="theme-text-muted">Runs tracked</span>
                <span className="theme-text-secondary">{runs.length}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="theme-text-muted">Active agents</span>
                <span className="theme-text-secondary">
                  {agentMetrics.active}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="theme-text-muted">Stale agents</span>
                <span className="theme-text-secondary">
                  {agentMetrics.stale}
                </span>
              </div>
            </div>
          </Card>

          <Card className="rounded-2xl p-6">
            <div className="flex items-center justify-between mb-4">
              <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
                Recent Runs
              </span>
              <span className="text-[10px] font-bold theme-text-secondary">
                {loading ? "Syncing" : `${runs.length} total`}
              </span>
            </div>
            {recentRuns.length === 0 && !loading && (
              <div className="text-xs theme-text-muted">
                No run history yet.
              </div>
            )}
            <div className="space-y-3">
              {recentRuns.map((run) => (
                <div
                  key={run.run_id}
                  className="flex items-center justify-between text-xs"
                >
                  <div className="flex flex-col">
                    <span className="theme-text-secondary">
                      {run.requirement_id || "General"}
                    </span>
                    <span className="text-[10px] font-mono theme-text-muted">
                      {formatDateTime(run.started_at)}
                    </span>
                  </div>
                  <span
                    className={`text-[10px] font-bold uppercase ${
                      run.status === "completed"
                        ? "text-[var(--brand-500)]"
                        : run.status === "failed"
                          ? "text-[var(--destructive-500)]"
                          : "theme-text-muted"
                    }`}
                  >
                    {run.status}
                  </span>
                </div>
              ))}
            </div>
          </Card>

          <Card className="rounded-2xl p-6">
            <div className="flex items-center justify-between mb-4">
              <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
                Requirements Queue
              </span>
              <span className="text-[10px] font-bold theme-text-secondary">
                {loading ? "--" : `${totalRequirements} total`}
              </span>
            </div>
            {requirementsPreview.length === 0 && !loading && (
              <EmptyState
                title="No requirements found"
                className="p-0 items-start text-left"
              />
            )}
            <div className="space-y-3">
              {requirementsPreview.map((req) => (
                <div key={req.id} className="flex items-center justify-between">
                  <div>
                    <div className="text-xs theme-text-secondary">
                      {req.title}
                    </div>
                    <div className="text-[10px] font-mono theme-text-muted">
                      {req.id}
                    </div>
                  </div>
                  <Badge
                    className={`text-[9px] uppercase px-2 py-1 ${getRequirementStatusBadgeClass(
                      req.status,
                    )}`}
                  >
                    {req.status.replace(/_/g, " ")}
                  </Badge>
                </div>
              ))}
            </div>
          </Card>
        </div>

        <div className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <span className="text-[10px] font-bold uppercase tracking-[0.2em] theme-text-muted">
              Agents
            </span>
            <div className="flex items-center gap-3 text-[10px] font-bold">
              <span className="theme-text-secondary">
                {agentMetrics.total} nodes
              </span>
              <span className="text-[9px] font-mono uppercase theme-text-muted">
                saved + running
              </span>
              <div className="flex items-center gap-1">
                {combinedAgents.map((agent) => (
                  <span
                    key={`${agent.source}-${agent.id}`}
                    className={`w-2 h-2 rounded-sm ${agentStatusColor(agent.status)}`}
                    title={agent.name}
                  />
                ))}
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-4 border-y border-[var(--border-muted)] py-3">
            <div className="relative flex-1 min-w-[220px] max-w-sm">
              <Input
                value={agentQuery}
                onChange={(event) => setAgentQuery(event.target.value)}
                className="h-8 text-xs"
                placeholder="Filter swarm nodes..."
              />
            </div>
            <ToggleGroup
              type="single"
              value={agentDensity}
              onValueChange={(value) => {
                if (value) setAgentDensity(value as "grid" | "compact");
              }}
            >
              <ToggleGroupItem value="grid">grid</ToggleGroupItem>
              <ToggleGroupItem value="compact">compact</ToggleGroupItem>
            </ToggleGroup>
          </div>

          {filteredAgents.length === 0 && !loading && (
            <EmptyState
              title="No agents match this filter"
              className="p-0 items-start text-left"
            />
          )}

          <div
            className={`grid gap-3 ${
              agentDensity === "compact"
                ? "grid-cols-2 md:grid-cols-4 lg:grid-cols-6"
                : "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
            }`}
          >
            {filteredAgents.map((agent) => (
              <Card
                key={`${agent.source}-${agent.id}`}
                className={`${agentDensity === "compact" ? "p-3" : "p-4"}`}
              >
                <div className="flex flex-col gap-0.5">
                  <div className="flex items-center gap-2 min-w-0">
                    <span
                      className={`w-2 h-2 rounded-full ${agentStatusColor(agent.status)}`}
                    />
                    <span
                      className={`font-semibold truncate theme-text-secondary ${
                        agentDensity === "compact" ? "text-[11px]" : "text-sm"
                      }`}
                    >
                      {agent.name}
                    </span>
                  </div>
                  <span className="text-[9px] font-mono theme-text-muted ml-4">
                    #{agent.id}
                  </span>
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <span
                    className={`theme-text-muted ${
                      agentDensity === "compact" ? "text-[9px]" : "text-xs"
                    }`}
                  >
                    {formatStage(agent)}
                  </span>
                  <Badge
                    className="text-[9px] uppercase px-2 py-0.5"
                    variant={agent.status === "active" ? "success" : "default"}
                  >
                    {formatAvailability(agent.status)}
                  </Badge>
                </div>
                <div className="mt-2 flex items-center justify-between text-[9px] font-mono theme-text-muted">
                  <span className="truncate">
                    {agent.hostname || agent.executable || "--"}
                  </span>
                  <span>{agent.currentRunId || "--"}</span>
                </div>
              </Card>
            ))}
          </div>
        </div>

        {loading && (
          <div className="text-xs font-mono uppercase tracking-[0.2em] theme-text-muted">
            Loading project telemetry...
          </div>
        )}
      </div>
    </div>
  );
};

export default ProjectDashboard;

import React, { useEffect, useMemo, useState } from "react";
import {
  felixApi,
  ProjectDetails,
  Requirement,
  RunHistoryEntry,
  AgentEntry,
  AgentConfiguration,
} from "../services/felixApi";
import { IconKanban, IconFileText, IconTerminal, IconPulse } from "./Icons";

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
  const [registryAgents, setRegistryAgents] = useState<AgentEntry[]>([]);
  const [configAgents, setConfigAgents] = useState<AgentConfiguration[]>([]);
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
        felixApi.getAgents(),
        felixApi.getAgentConfigurations(),
      ]);

      if (!isMounted) return;

      const [requirementsResult, runsResult, agentsResult, configsResult] =
        results;
      if (requirementsResult.status === "fulfilled") {
        setRequirements(requirementsResult.value.requirements || []);
      }
      if (runsResult.status === "fulfilled") {
        setRuns(runsResult.value.runs || []);
      }
      if (agentsResult.status === "fulfilled") {
        const list = Object.values(agentsResult.value.agents || {});
        setRegistryAgents(list);
      }
      if (configsResult.status === "fulfilled") {
        setConfigAgents(configsResult.value.agents || []);
      }

      if (
        requirementsResult.status === "rejected" &&
        runsResult.status === "rejected" &&
        agentsResult.status === "rejected" &&
        configsResult.status === "rejected"
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
    return requirements
      .slice(0, 6)
      .sort((a, b) => a.title.localeCompare(b.title));
  }, [requirements]);

  const statusSegments = [
    { key: "draft", label: "Draft", color: "bg-slate-600/60" },
    { key: "planned", label: "Planned", color: "bg-slate-500/80" },
    { key: "in_progress", label: "In Progress", color: "bg-brand-500" },
    { key: "blocked", label: "Blocked", color: "bg-amber-500" },
    { key: "done", label: "Done", color: "bg-emerald-500" },
    { key: "other", label: "Other", color: "bg-fuchsia-500/60" },
  ];

  const getSegmentWidth = (value: number) => {
    if (!totalRequirements) return "0%";
    return `${Math.max(2, Math.round((value / totalRequirements) * 100))}%`;
  };

  const agentStatusColor = (status: DashboardAgent["status"]) => {
    switch (status) {
      case "active":
        return "bg-emerald-500";
      case "stale":
        return "bg-amber-500";
      case "stopped":
        return "bg-red-500";
      case "inactive":
        return "bg-slate-500";
      case "not-started":
        return "bg-slate-700";
      default:
        return "bg-slate-600";
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
    const registry = registryAgents.map((agent) => ({
      id: agent.agent_id,
      name: agent.agent_name,
      status: agent.status,
      hostname: agent.hostname,
      executable: null,
      currentRunId: agent.current_run_id,
      workflowStage: agent.current_workflow_stage ?? null,
      source: "registry" as const,
    }));

    const registryIds = new Set(registryAgents.map((agent) => agent.agent_id));
    const configs = configAgents
      .filter((agent) => !registryIds.has(agent.id))
      .map((agent) => ({
        id: agent.id,
        name: agent.name,
        status: "not-started" as const,
        hostname: null,
        executable: agent.executable,
        currentRunId: null,
        workflowStage: null,
        source: "config" as const,
      }));

    return [...registry, ...configs].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
  }, [registryAgents, configAgents]);

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
    <div
      className="flex-1 overflow-y-auto custom-scrollbar"
      style={{
        backgroundColor: "var(--bg-base)",
      }}
    >
      <div className="w-full px-6 py-6 space-y-8">
        <div className="flex flex-wrap items-start justify-between gap-6">
          <div>
            <div className="flex flex-wrap items-center gap-3">
              <h1
                className="text-2xl font-semibold"
                style={{ color: "var(--text-primary)" }}
              >
                {project.name || project.path.split(/[\\/]/).pop()}
              </h1>
              <span
                className="text-[10px] font-bold uppercase tracking-[0.2em] px-2 py-1 rounded-full border"
                style={{
                  borderColor: "var(--border-muted)",
                  color: "var(--text-muted)",
                }}
              >
                {project.status || "active"}
              </span>
            </div>
            <p
              className="text-xs font-mono mt-1"
              style={{ color: "var(--text-muted)" }}
            >
              {project.path}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={() => onNavigate("kanban")}
              className="px-3 py-2 rounded-lg text-[10px] font-bold uppercase tracking-[0.2em] border flex items-center gap-2 transition-colors"
              style={{
                borderColor: "var(--border-default)",
                backgroundColor: "var(--bg-surface)",
                color: "var(--text-secondary)",
              }}
            >
              <IconKanban className="w-3.5 h-3.5" />
              Requirements
            </button>
            <button
              onClick={() => onNavigate("assets")}
              className="px-3 py-2 rounded-lg text-[10px] font-bold uppercase tracking-[0.2em] border flex items-center gap-2 transition-colors"
              style={{
                borderColor: "var(--border-default)",
                backgroundColor: "var(--bg-surface)",
                color: "var(--text-secondary)",
              }}
            >
              <IconFileText className="w-3.5 h-3.5" />
              Specs
            </button>
            <button
              onClick={() => onNavigate("orchestration")}
              className="px-3 py-2 rounded-lg text-[10px] font-bold uppercase tracking-[0.2em] border flex items-center gap-2 transition-colors"
              style={{
                borderColor: "var(--border-default)",
                backgroundColor: "var(--bg-surface)",
                color: "var(--text-secondary)",
              }}
            >
              <IconTerminal className="w-3.5 h-3.5" />
              Orchestration
            </button>
          </div>
        </div>

        {error && (
          <div
            className="px-4 py-3 rounded-xl border text-xs"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-surface)",
              color: "var(--text-secondary)",
            }}
          >
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          <div
            className="xl:col-span-2 rounded-2xl border p-6"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-surface)",
            }}
          >
            <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
              <div>
                <span
                  className="text-[10px] font-bold uppercase tracking-[0.2em]"
                  style={{ color: "var(--text-muted)" }}
                >
                  Workflow Saturation
                </span>
                <p
                  className="text-xl font-semibold mt-2"
                  style={{ color: "var(--text-primary)" }}
                >
                  {totalRequirements || "No"} active requirements
                </p>
              </div>
              <div className="text-right">
                <span
                  className="text-[10px] font-bold uppercase tracking-[0.2em]"
                  style={{ color: "var(--text-muted)" }}
                >
                  Completion
                </span>
                <div
                  className="text-xl font-semibold"
                  style={{ color: "var(--text-primary)" }}
                >
                  {completionRate}%
                </div>
              </div>
            </div>
            <div
              className="flex w-full h-3 rounded-full overflow-hidden"
              style={{ backgroundColor: "var(--bg-base)" }}
            >
              {statusSegments.map((segment) => (
                <div
                  key={segment.key}
                  className={`${segment.color} h-full`}
                  style={{
                    width: getSegmentWidth(
                      statusCounts[segment.key as keyof typeof statusCounts],
                    ),
                  }}
                />
              ))}
            </div>
            <div className="flex flex-wrap justify-between gap-2 mt-4 text-[10px] font-mono">
              {statusSegments.map((segment) => (
                <div
                  key={segment.key}
                  className="flex items-center gap-2"
                  style={{ color: "var(--text-muted)" }}
                >
                  <span className={`w-2 h-2 rounded-full ${segment.color}`} />
                  {segment.label} (
                  {statusCounts[segment.key as keyof typeof statusCounts]})
                </div>
              ))}
            </div>
          </div>

          <div
            className="rounded-2xl border p-6 flex flex-col justify-between"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-surface)",
            }}
          >
            <div>
              <span
                className="text-[10px] font-bold uppercase tracking-[0.2em]"
                style={{ color: "var(--text-muted)" }}
              >
                Context Coverage
              </span>
              <div className="mt-6 space-y-3">
                <div className="flex items-center justify-between text-xs">
                  <span style={{ color: "var(--text-secondary)" }}>
                    Specs, Plan, Requirements
                  </span>
                  <span
                    className="font-mono"
                    style={{ color: "var(--text-primary)" }}
                  >
                    {coverageScore}%
                  </span>
                </div>
                <div
                  className="h-2 rounded-full overflow-hidden"
                  style={{ backgroundColor: "var(--bg-base)" }}
                >
                  <div
                    className="h-full"
                    style={{
                      width: `${coverageScore}%`,
                      backgroundColor: "var(--accent-primary)",
                    }}
                  />
                </div>
              </div>
            </div>
            <div
              className="pt-6 border-t"
              style={{ borderColor: "var(--border-muted)" }}
            >
              <div className="flex items-center justify-between text-xs">
                <span style={{ color: "var(--text-muted)" }}>Specs</span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {project.spec_count} files
                </span>
              </div>
              <div className="flex items-center justify-between text-xs mt-2">
                <span style={{ color: "var(--text-muted)" }}>Plan</span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {project.has_plan ? "Available" : "Missing"}
                </span>
              </div>
              <div className="flex items-center justify-between text-xs mt-2">
                <span style={{ color: "var(--text-muted)" }}>Requirements</span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {project.has_requirements ? "Mapped" : "Empty"}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div
            className="rounded-2xl border p-6"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-surface)",
            }}
          >
            <div className="flex items-center justify-between mb-4">
              <span
                className="text-[10px] font-bold uppercase tracking-[0.2em]"
                style={{ color: "var(--text-muted)" }}
              >
                Project Pulse
              </span>
              <IconPulse
                className="w-4 h-4"
                style={{ color: "var(--text-muted)" }}
              />
            </div>
            <div className="space-y-3 text-sm">
              <div className="flex items-center justify-between">
                <span style={{ color: "var(--text-muted)" }}>Last run</span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {recentRuns[0]
                    ? formatDateTime(recentRuns[0].started_at)
                    : "--"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span style={{ color: "var(--text-muted)" }}>Runs tracked</span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {runs.length}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span style={{ color: "var(--text-muted)" }}>
                  Active agents
                </span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {agentMetrics.active}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span style={{ color: "var(--text-muted)" }}>Stale agents</span>
                <span style={{ color: "var(--text-secondary)" }}>
                  {agentMetrics.stale}
                </span>
              </div>
            </div>
          </div>

          <div
            className="rounded-2xl border p-6"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-surface)",
            }}
          >
            <div className="flex items-center justify-between mb-4">
              <span
                className="text-[10px] font-bold uppercase tracking-[0.2em]"
                style={{ color: "var(--text-muted)" }}
              >
                Recent Runs
              </span>
              <span
                className="text-[10px] font-bold"
                style={{ color: "var(--text-secondary)" }}
              >
                {loading ? "Syncing" : `${runs.length} total`}
              </span>
            </div>
            {recentRuns.length === 0 && !loading && (
              <div className="text-xs" style={{ color: "var(--text-muted)" }}>
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
                    <span style={{ color: "var(--text-secondary)" }}>
                      {run.requirement_id || "General"}
                    </span>
                    <span
                      className="text-[10px] font-mono"
                      style={{ color: "var(--text-muted)" }}
                    >
                      {formatDateTime(run.started_at)}
                    </span>
                  </div>
                  <span
                    className="text-[10px] font-bold uppercase"
                    style={{
                      color:
                        run.status === "completed"
                          ? "var(--accent-primary)"
                          : run.status === "failed"
                            ? "#f97316"
                            : "var(--text-muted)",
                    }}
                  >
                    {run.status}
                  </span>
                </div>
              ))}
            </div>
          </div>

          <div
            className="rounded-2xl border p-6"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-surface)",
            }}
          >
            <div className="flex items-center justify-between mb-4">
              <span
                className="text-[10px] font-bold uppercase tracking-[0.2em]"
                style={{ color: "var(--text-muted)" }}
              >
                Requirements Queue
              </span>
              <span
                className="text-[10px] font-bold"
                style={{ color: "var(--text-secondary)" }}
              >
                {loading ? "--" : `${totalRequirements} total`}
              </span>
            </div>
            {requirementsPreview.length === 0 && !loading && (
              <div className="text-xs" style={{ color: "var(--text-muted)" }}>
                No requirements found.
              </div>
            )}
            <div className="space-y-3">
              {requirementsPreview.map((req) => (
                <div key={req.id} className="flex items-center justify-between">
                  <div>
                    <div
                      className="text-xs"
                      style={{ color: "var(--text-secondary)" }}
                    >
                      {req.title}
                    </div>
                    <div
                      className="text-[10px] font-mono"
                      style={{ color: "var(--text-muted)" }}
                    >
                      {req.id}
                    </div>
                  </div>
                  <span
                    className="text-[9px] font-bold uppercase px-2 py-1 rounded-full"
                    style={{
                      backgroundColor: "var(--bg-base)",
                      color: "var(--text-muted)",
                      border: "1px solid var(--border-muted)",
                    }}
                  >
                    {req.status.replace(/_/g, " ")}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <span
              className="text-[10px] font-bold uppercase tracking-[0.2em]"
              style={{ color: "var(--text-muted)" }}
            >
              Agents
            </span>
            <div className="flex items-center gap-3 text-[10px] font-bold">
              <span style={{ color: "var(--text-secondary)" }}>
                {agentMetrics.total} nodes
              </span>
              <span
                className="text-[9px] font-mono uppercase"
                style={{ color: "var(--text-muted)" }}
              >
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

          <div
            className="flex flex-wrap items-center justify-between gap-4 border-y py-3"
            style={{ borderColor: "var(--border-muted)" }}
          >
            <div className="relative flex-1 min-w-[220px] max-w-sm">
              <input
                value={agentQuery}
                onChange={(event) => setAgentQuery(event.target.value)}
                className="w-full rounded-lg py-2 pl-3 pr-3 text-xs outline-none"
                style={{
                  backgroundColor: "var(--bg-base)",
                  border: "1px solid var(--border-muted)",
                  color: "var(--text-secondary)",
                }}
                placeholder="Filter swarm nodes..."
              />
            </div>
            <div
              className="flex border rounded-lg p-0.5"
              style={{
                backgroundColor: "var(--bg-elevated)",
                borderColor: "var(--border-default)",
              }}
            >
              {(["grid", "compact"] as const).map((mode) => (
                <button
                  key={mode}
                  onClick={() => setAgentDensity(mode)}
                  className="px-3 py-1 text-[10px] font-bold uppercase tracking-[0.2em] rounded-md transition-all"
                  style={{
                    backgroundColor:
                      agentDensity === mode
                        ? "var(--bg-surface)"
                        : "transparent",
                    color:
                      agentDensity === mode
                        ? "var(--accent-primary)"
                        : "var(--text-muted)",
                  }}
                  onMouseEnter={(event) => {
                    if (agentDensity !== mode) {
                      event.currentTarget.style.color = "var(--text-secondary)";
                    }
                  }}
                  onMouseLeave={(event) => {
                    if (agentDensity !== mode) {
                      event.currentTarget.style.color = "var(--text-muted)";
                    }
                  }}
                >
                  {mode}
                </button>
              ))}
            </div>
          </div>

          {filteredAgents.length === 0 && !loading && (
            <div className="text-xs" style={{ color: "var(--text-muted)" }}>
              No agents match this filter.
            </div>
          )}

          <div
            className={`grid gap-3 ${
              agentDensity === "compact"
                ? "grid-cols-2 md:grid-cols-4 lg:grid-cols-6"
                : "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
            }`}
          >
            {filteredAgents.map((agent) => (
              <div
                key={`${agent.source}-${agent.id}`}
                className={`rounded-xl border ${
                  agentDensity === "compact" ? "p-3" : "p-4"
                }`}
                style={{
                  borderColor: "var(--border-muted)",
                  backgroundColor: "var(--bg-surface)",
                }}
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <span
                      className={`w-2 h-2 rounded-full ${agentStatusColor(agent.status)}`}
                    />
                    <span
                      className={`font-semibold truncate ${
                        agentDensity === "compact" ? "text-[11px]" : "text-sm"
                      }`}
                      style={{ color: "var(--text-secondary)" }}
                    >
                      {agent.name}
                    </span>
                  </div>
                  <span
                    className="text-[9px] font-mono uppercase"
                    style={{ color: "var(--text-muted)" }}
                  >
                    #{agent.id}
                  </span>
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <span
                    className={
                      agentDensity === "compact" ? "text-[9px]" : "text-xs"
                    }
                    style={{ color: "var(--text-muted)" }}
                  >
                    {formatStage(agent)}
                  </span>
                  <span
                    className="text-[9px] font-bold uppercase px-2 py-0.5 rounded-full"
                    style={{
                      backgroundColor: "var(--bg-base)",
                      color:
                        agent.status === "active"
                          ? "var(--accent-primary)"
                          : "var(--text-muted)",
                      border: "1px solid var(--border-muted)",
                    }}
                  >
                    {formatAvailability(agent.status)}
                  </span>
                </div>
                <div
                  className="mt-2 flex items-center justify-between text-[9px] font-mono"
                  style={{ color: "var(--text-faint)" }}
                >
                  <span className="truncate">
                    {agent.hostname || agent.executable || "--"}
                  </span>
                  <span>{agent.currentRunId || "--"}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {loading && (
          <div
            className="text-xs font-mono uppercase tracking-[0.2em]"
            style={{ color: "var(--text-muted)" }}
          >
            Loading project telemetry...
          </div>
        )}
      </div>
    </div>
  );
};

export default ProjectDashboard;

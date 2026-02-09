import React, { useState, useEffect, useRef, useMemo } from "react";
import { Task, UIState, MarkdownAsset } from "./types";
import { felixApi, ProjectDetails } from "./services/felixApi";
import {
  IconFelix,
  IconSearch,
  IconTerminal,
  IconFileCode,
  IconFileText,
  IconCpu,
  IconKanban,
  IconPlus,
  IconPulse,
} from "./components/Icons";
import ProjectSelector from "./components/ProjectSelector";
import RequirementsKanban from "./components/RequirementsKanban";
import AgentControls from "./components/AgentControls";
import RunArtifactViewer from "./components/RunArtifactViewer";
import SpecsEditor from "./components/SpecsEditor";

import ConfigPanel from "./components/ConfigPanel";
import PlanViewer from "./components/PlanViewer";
import SettingsScreen from "./components/SettingsScreen";
import AgentDashboard from "./components/AgentDashboard";
import CopilotChat from "./components/CopilotChat";
import { marked } from "marked";
import { ThemeValue, useTheme } from "./hooks/ThemeProvider";
import Sidebar, { SidebarView } from "./components/Sidebar";

// localStorage key for remembering the last selected project
const LAST_PROJECT_KEY = "felix-last-project-id";

// Helper functions for safe localStorage operations
const saveLastProjectId = (projectId: string): void => {
  try {
    localStorage.setItem(LAST_PROJECT_KEY, projectId);
  } catch {
    // Silently fail if localStorage is unavailable (e.g., private browsing)
  }
};

/**
 * Validate that a project ID has the expected format.
 * Project IDs are 12-character hexadecimal strings (MD5 hash prefix).
 * @param projectId - The project ID to validate
 * @returns true if valid, false otherwise
 */
const isValidProjectId = (projectId: string): boolean => {
  // Project IDs must be exactly 12 hex characters (a-f, 0-9)
  return /^[a-f0-9]{12}$/i.test(projectId);
};

const getLastProjectId = (): string | null => {
  try {
    const stored = localStorage.getItem(LAST_PROJECT_KEY);
    // Validate that the stored value is a non-empty string
    if (stored && typeof stored === "string" && stored.trim().length > 0) {
      const trimmed = stored.trim();
      // Validate project ID format (12-char hex string)
      if (isValidProjectId(trimmed)) {
        return trimmed;
      }
      // Invalid format - clear corrupted data
      clearLastProjectId();
      return null;
    }
    return null;
  } catch {
    // Silently fail if localStorage is unavailable
    return null;
  }
};

const clearLastProjectId = (): void => {
  try {
    localStorage.removeItem(LAST_PROJECT_KEY);
  } catch {
    // Silently fail if localStorage is unavailable
  }
};

const INITIAL_TASKS: Task[] = [
  {
    id: "t1",
    title: "Implement Auth Layer",
    description: "Create JWT based authentication service.",
    status: "todo",
    priority: "high",
    tags: ["security", "backend"],
  },
  {
    id: "t2",
    title: "Felix UI Redesign",
    description: "Switch to Kanban-first workflow.",
    status: "in-progress",
    priority: "medium",
    tags: ["frontend", "ux"],
  },
  {
    id: "t3",
    title: "Setup Gemini 2.5 API",
    description: "Integrate native audio and multi-modal support.",
    status: "completed",
    priority: "high",
    tags: ["ai", "infra"],
  },
  {
    id: "t4",
    title: "Database Migration",
    description: "Migrate legacy SQL to optimized schema.",
    status: "backlog",
    priority: "low",
    tags: ["data"],
  },
];

// Extended UI state to include projects, config, plan, settings, and orchestration views
type ExtendedUIState =
  | UIState
  | "projects"
  | "config"
  | "plan"
  | "settings"
  | "orchestration";

const App: React.FC = () => {
  const [tasks, setTasks] = useState<Task[]>(INITIAL_TASKS);
  const [uiState, setUiState] = useState<ExtendedUIState>("projects"); // Start with projects view

  // Project management state
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(
    null,
  );
  const [selectedProject, setSelectedProject] = useState<ProjectDetails | null>(
    null,
  );
  const [backendStatus, setBackendStatus] = useState<
    "unknown" | "connected" | "disconnected"
  >("unknown");

  // Run artifact viewer state
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [isUserMenuOpen, setUserMenuOpen] = useState(false);
  const userMenuRef = useRef<HTMLDivElement | null>(null);

  const recognizedSidebarStates: SidebarView[] = [
    "projects",
    "kanban",
    "assets",
    "orchestration",
    "config",
    "plan",
    "settings",
  ];
  const activeSidebarView: SidebarView = recognizedSidebarStates.includes(
    uiState as SidebarView,
  )
    ? (uiState as SidebarView)
    : "projects";

  const viewMetadata: Record<
    SidebarView,
    { label: string; tag: string; color: string }
  > = {
    projects: {
      label: "Projects",
      tag: "Workspace List",
      color: "var(--brand-500)",
    },
    kanban: {
      label: "System Board",
      tag: "Requirement Flow",
      color: "#fb923c",
    },
    assets: { label: "Specifications", tag: "Resource Docs", color: "#34d399" },
    orchestration: {
      label: "Agent Dashboard",
      tag: "Runtime Control",
      color: "#22d3ee",
    },
    config: {
      label: "Configuration",
      tag: "Project Settings",
      color: "var(--text-muted)",
    },
    plan: { label: "Project README", tag: "Planning", color: "#38bdf8" },
    settings: { label: "Settings", tag: "Preferences", color: "#c084fc" },
  };
  const activeViewMeta = viewMetadata[activeSidebarView];
  const projectHeaderLabel = selectedProject
    ? selectedProject.name || selectedProject.path.split(/[\\/]/).pop()
    : "No project selected";
  const { theme, setTheme } = useTheme();
  const themeOptions: Array<{ label: string; value: ThemeValue; isVariant?: boolean }> = [
    { label: "Dark", value: "dark" },
    { label: "Light", value: "light" },
    { label: "Classic Dark", value: "dark", isVariant: true },
    { label: "System", value: "system" },
  ];

  // Ref to ensure auto-load only happens once on initial app load
  const hasAttemptedAutoLoad = useRef<boolean>(false);
  // Ref to track if user has manually interacted (selected project, navigated)
  // Used to prevent auto-load from overriding user actions
  const hasUserInteracted = useRef<boolean>(false);

  // Check backend status once on mount (polling removed in S-0033)
  useEffect(() => {
    const checkBackend = async () => {
      try {
        await felixApi.healthCheck();
        setBackendStatus("connected");
      } catch (e) {
        setBackendStatus("disconnected");
        console.warn("Backend not available:", e);
      }
    };
    checkBackend();
  }, []);

  // Auto-load last selected project on app startup
  useEffect(() => {
    // Only attempt auto-load once on initial mount
    if (hasAttemptedAutoLoad.current) {
      return;
    }
    hasAttemptedAutoLoad.current = true;

    const autoLoadLastProject = async () => {
      const savedProjectId = getLastProjectId();
      if (!savedProjectId) {
        return;
      }

      try {
        const projectDetails = await felixApi.getProject(savedProjectId);
        // Only apply auto-load if user hasn't manually interacted
        if (projectDetails && !hasUserInteracted.current) {
          setSelectedProjectId(savedProjectId);
          setSelectedProject(projectDetails);
          // Switch to kanban view after auto-loading
          setUiState("kanban");
        }
      } catch (error) {
        // Project no longer exists or API error - clear the saved ID
        clearLastProjectId();
        console.warn("Auto-load failed, clearing saved project ID:", error);
      }
    };

    autoLoadLastProject();
  }, []);

  const handleSelectProject = (projectId: string, details: ProjectDetails) => {
    // Mark that user has manually interacted (prevents auto-load from overriding)
    hasUserInteracted.current = true;
    setSelectedProjectId(projectId);
    setSelectedProject(details);
    // Save the selected project ID to localStorage for auto-load on next visit
    saveLastProjectId(projectId);
    // Switch to kanban view after selecting a project
    if (uiState === "projects") {
      setUiState("kanban");
    }
  };

  // Assets state for markdown editor
  const [assets, setAssets] = useState<MarkdownAsset[]>([
    {
      id: "asset1",
      name: "Project Overview",
      content:
        "# Project Overview\n\nThis is a sample markdown document for the assets view.",
      lastEdited: Date.now(),
    },
    {
      id: "asset2",
      name: "Architecture",
      content: "# Architecture\n\nDescribe your system architecture here.",
      lastEdited: Date.now(),
    },
  ]);
  const [selectedAssetId, setSelectedAssetId] = useState<string>("asset1");
  const [assetViewMode, setAssetViewMode] = useState<
    "edit" | "split" | "preview"
  >("split");
  const [parsedHtml, setParsedHtml] = useState<string>("");

  const editorRef = useRef<HTMLTextAreaElement>(null);
  const activeAsset = useMemo(
    () => assets.find((a) => a.id === selectedAssetId) || assets[0],
    [assets, selectedAssetId],
  );

  // Reliable Markdown parsing effect
  useEffect(() => {
    let isMounted = true;
    const parseMarkdown = async () => {
      try {
        // marked.parse can be sync or async depending on options; await handles both
        const result = await marked.parse(activeAsset?.content || "");
        if (isMounted) setParsedHtml(result);
      } catch (err) {
        console.error("Markdown rendering error:", err);
        if (isMounted)
          setParsedHtml(
            `<div class="text-red-500 font-mono text-xs">Parsing Error: ${err}</div>`,
          );
      }
    };

    const timeout = setTimeout(parseMarkdown, 50); // Small debounce for smoother typing
    return () => {
      isMounted = false;
      clearTimeout(timeout);
    };
  }, [activeAsset?.content]);

  const updateAssetContent = (id: string, newContent: string) => {
    setAssets((prev) =>
      prev.map((a) =>
        a.id === id ? { ...a, content: newContent, lastEdited: Date.now() } : a,
      ),
    );
  };

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

    updateAssetContent(activeAsset.id, newContent);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + prefix.length, end + prefix.length);
    }, 0);
  };

  const copyToClipboard = () => {
    navigator.clipboard.writeText(activeAsset.content);
    // Simple visual feedback could go here
  };

  const renderKanban = () => {
    const columns: { status: Task["status"]; label: string }[] = [
      { status: "backlog", label: "Backlog" },
      { status: "todo", label: "Todo" },
      { status: "in-progress", label: "In Progress" },
      { status: "completed", label: "Completed" },
    ];

    return (
      <div
        className="flex-1 flex gap-6 p-8 overflow-x-auto custom-scrollbar"
        style={{ backgroundColor: "var(--bg-deepest)" }}
      >
        {columns.map((col) => (
          <div
            key={col.status}
            className="flex-shrink-0 w-80 flex flex-col gap-4"
          >
            <div className="flex items-center justify-between px-2">
              <div className="flex items-center gap-2">
                <div
                  className={`w-2 h-2 rounded-full ${
                    col.status === "todo"
                      ? "bg-amber-500"
                      : col.status === "in-progress"
                        ? "bg-brand-500 animate-pulse"
                        : col.status === "completed"
                          ? "bg-emerald-500"
                          : ""
                  }`}
                  style={{
                    backgroundColor:
                      col.status === "backlog"
                        ? "var(--text-muted)"
                        : undefined,
                  }}
                />
                <h3
                  className="text-xs font-bold uppercase tracking-widest"
                  style={{ color: "var(--text-tertiary)" }}
                >
                  {col.label}
                </h3>
              </div>
              <span
                className="text-[10px] font-mono px-1.5 py-0.5 rounded"
                style={{
                  color: "var(--text-muted)",
                  backgroundColor: "var(--bg-deep)",
                }}
              >
                {tasks.filter((t) => t.status === col.status).length}
              </span>
            </div>

            <div className="flex-1 space-y-3">
              {tasks
                .filter((t) => t.status === col.status)
                .map((task) => (
                  <div
                    key={task.id}
                    className="border p-4 rounded-xl hover:border-brand-600/40 transition-all cursor-pointer group shadow-lg"
                    style={{
                      backgroundColor: "var(--bg-base)",
                      borderColor: "var(--border-default)",
                    }}
                  >
                    <div className="flex justify-between items-start mb-2">
                      <span
                        className={`text-[9px] font-bold px-1.5 py-0.5 rounded uppercase ${
                          task.priority === "high"
                            ? "bg-red-500/10 text-red-400 border border-red-500/20"
                            : task.priority === "medium"
                              ? "bg-amber-500/10 text-amber-400 border border-amber-500/20"
                              : ""
                        }`}
                        style={{
                          backgroundColor:
                            task.priority === "low"
                              ? "var(--bg-surface)"
                              : undefined,
                          color:
                            task.priority === "low"
                              ? "var(--text-tertiary)"
                              : undefined,
                        }}
                      >
                        {task.priority}
                      </span>
                      <button
                        className="opacity-0 group-hover:opacity-100 p-1 rounded transition-opacity"
                        style={{ backgroundColor: "transparent" }}
                      >
                        <IconPlus
                          className="w-3 h-3"
                          style={{ color: "var(--text-muted)" }}
                        />
                      </button>
                    </div>
                    <h4
                      className="text-sm font-semibold mb-1 group-hover:text-brand-400 transition-colors"
                      style={{ color: "var(--text-secondary)" }}
                    >
                      {task.title}
                    </h4>
                    <p
                      className="text-[11px] leading-relaxed mb-3 line-clamp-2"
                      style={{ color: "var(--text-muted)" }}
                    >
                      {task.description}
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {task.tags.map((tag) => (
                        <span
                          key={tag}
                          className="text-[9px] font-mono border px-1 rounded transition-colors"
                          style={{
                            color: "var(--text-muted)",
                            borderColor: "var(--border-default)",
                          }}
                        >
                          #{tag}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              <button
                className="w-full py-2 border border-dashed rounded-xl text-[10px] transition-all flex items-center justify-center gap-2 group"
                style={{
                  borderColor: "var(--border-default)",
                  color: "var(--text-muted)",
                }}
              >
                <IconPlus className="w-3 h-3 group-hover:scale-125 transition-transform" />
                Add Task
              </button>
            </div>
          </div>
        ))}
      </div>
    );
  };

  const renderCanvas = () => {
    return (
      <div
        className="flex-1 flex overflow-hidden"
        style={{ backgroundColor: "var(--bg-base)" }}
      >
        <div
          className="flex-1 flex flex-col border-r"
          style={{ borderColor: "var(--border-default)" }}
        >
          <div
            className="h-12 border-b flex items-center px-6 justify-between backdrop-blur"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-base)",
            }}
          >
            <div className="flex items-center gap-3">
              <IconFileCode
                className="w-4 h-4"
                style={{ color: "var(--accent-primary)" }}
              />
              <span
                className="text-xs font-mono font-bold"
                style={{ color: "var(--text-tertiary)" }}
              >
                workspace/felix-core/orchestrator.ts
              </span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-emerald-500"></div>
              <span className="text-[10px] font-bold text-emerald-500 uppercase">
                Live Context Active
              </span>
            </div>
          </div>
          <div className="flex-1 p-8 font-mono text-sm leading-relaxed overflow-y-auto custom-scrollbar selection:bg-brand-500/30">
            <pre className="!bg-transparent !border-none !p-0">
              {`// Felix Orchestrator Logic
import { Gemini } from '@google/genai';

export const analyzeWorkspace = async () => {
  const context = await loadFiles();
  const feedback = await Gemini.generate({
    prompt: 'Review architecture for bottlenecks',
    context
  });
  
  return feedback;
};

// @todo: Implement task-to-code mapping
export const executeTask = (taskId: string) => {
  console.log(\`Executing $\{taskId\}...\`);
};`}
            </pre>
          </div>
        </div>
      </div>
    );
  };

  const renderAssets = () => {
    return (
      <div
        className="flex-1 flex overflow-hidden"
        style={{ backgroundColor: "var(--bg-base)" }}
      >
        {/* Sub-nav Panel */}
        <div
          className="w-64 border-r flex flex-col flex-shrink-0"
          style={{
            borderColor: "var(--border-default)",
            backgroundColor: "var(--bg-deep)",
          }}
        >
          <div
            className="h-12 border-b flex items-center px-4"
            style={{ borderColor: "var(--border-default)" }}
          >
            <span
              className="text-[10px] font-bold uppercase tracking-widest"
              style={{ color: "var(--text-muted)" }}
            >
              Project Workspace
            </span>
          </div>
          <div className="p-3 space-y-1 overflow-y-auto custom-scrollbar">
            {assets.map((asset) => (
              <button
                key={asset.id}
                onClick={() => {
                  setSelectedAssetId(asset.id);
                }}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs transition-all border ${selectedAssetId === asset.id ? "bg-brand-600/10 text-brand-400 border-brand-500/20 shadow-lg shadow-brand-900/10" : "border-transparent"}`}
                style={{
                  color:
                    selectedAssetId !== asset.id
                      ? "var(--text-muted)"
                      : undefined,
                }}
              >
                <IconFileText className="w-4 h-4" />
                <div className="flex flex-col items-start min-w-0">
                  <span className="truncate font-medium">{asset.name}</span>
                  <span className="text-[9px] opacity-40 font-mono">
                    markdown
                  </span>
                </div>
              </button>
            ))}
            <button
              className="w-full flex items-center gap-2 px-3 py-2 rounded-xl text-xs border border-dashed mt-4 transition-all"
              style={{
                color: "var(--text-muted)",
                borderColor: "var(--border-default)",
              }}
            >
              <IconPlus className="w-3.5 h-3.5" />
              <span>New Resource</span>
            </button>
          </div>
        </div>

        {/* Integrated Orchestration Canvas */}
        <div
          className="flex-1 flex flex-col min-w-0"
          style={{ backgroundColor: "var(--bg-deep)" }}
        >
          <div
            className="h-12 border-b flex items-center px-4 justify-between backdrop-blur z-20 flex-shrink-0"
            style={{
              borderColor: "var(--border-default)",
              backgroundColor: "var(--bg-base)",
            }}
          >
            <div className="flex items-center gap-4">
              <div
                className="flex border rounded-lg p-0.5 shadow-inner"
                style={{
                  backgroundColor: "var(--bg-deep)",
                  borderColor: "var(--border-default)",
                }}
              >
                <button
                  onClick={() => setAssetViewMode("edit")}
                  className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all`}
                  style={{
                    backgroundColor:
                      assetViewMode === "edit"
                        ? "var(--bg-surface)"
                        : "transparent",
                    color:
                      assetViewMode === "edit"
                        ? "var(--accent-primary)"
                        : "var(--text-muted)",
                  }}
                >
                  SOURCE
                </button>
                <button
                  onClick={() => setAssetViewMode("split")}
                  className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all`}
                  style={{
                    backgroundColor:
                      assetViewMode === "split"
                        ? "var(--bg-surface)"
                        : "transparent",
                    color:
                      assetViewMode === "split"
                        ? "var(--accent-primary)"
                        : "var(--text-muted)",
                  }}
                >
                  ORCHESTRATE
                </button>
                <button
                  onClick={() => setAssetViewMode("preview")}
                  className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all`}
                  style={{
                    backgroundColor:
                      assetViewMode === "preview"
                        ? "var(--bg-surface)"
                        : "transparent",
                    color:
                      assetViewMode === "preview"
                        ? "var(--accent-primary)"
                        : "var(--text-muted)",
                  }}
                >
                  PREVIEW
                </button>
              </div>

              {(assetViewMode === "edit" || assetViewMode === "split") && (
                <div
                  className="flex items-center gap-0.5 border-l pl-4"
                  style={{ borderColor: "var(--border-default)" }}
                >
                  <button
                    onClick={() => insertFormatting("# ")}
                    className="p-1.5 rounded-md transition-all"
                    style={{ color: "var(--text-muted)" }}
                    title="H1"
                  >
                    <span className="font-bold text-xs">H1</span>
                  </button>
                  <button
                    onClick={() => insertFormatting("## ")}
                    className="p-1.5 rounded-md transition-all"
                    style={{ color: "var(--text-muted)" }}
                    title="H2"
                  >
                    <span className="font-bold text-xs">H2</span>
                  </button>
                  <button
                    onClick={() => insertFormatting("**", "**")}
                    className="p-1.5 rounded-md transition-all"
                    style={{ color: "var(--text-muted)" }}
                    title="Bold"
                  >
                    <span className="font-bold text-xs uppercase">B</span>
                  </button>
                  <button
                    onClick={() => insertFormatting("*", "*")}
                    className="p-1.5 rounded-md transition-all"
                    style={{ color: "var(--text-muted)" }}
                    title="Italic"
                  >
                    <span className="italic text-xs font-serif font-bold uppercase">
                      I
                    </span>
                  </button>
                  <button
                    onClick={() => insertFormatting("- ")}
                    className="p-1.5 rounded-md transition-all"
                    style={{ color: "var(--text-muted)" }}
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
                  </button>
                  <button
                    onClick={() => insertFormatting("`", "`")}
                    className="p-1.5 rounded-md transition-all"
                    style={{ color: "var(--text-muted)" }}
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
                  </button>
                </div>
              )}
            </div>

            <div className="flex items-center gap-4">
              <button
                onClick={copyToClipboard}
                className="text-[10px] font-bold transition-colors uppercase tracking-widest flex items-center gap-2"
                style={{ color: "var(--text-muted)" }}
              >
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
                Copy Raw
              </button>
              <div
                className="h-4 w-px"
                style={{ backgroundColor: "var(--border-default)" }}
              ></div>
              <div className="flex items-center gap-2">
                <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></div>
                <span
                  className="text-[10px] font-mono uppercase"
                  style={{ color: "var(--text-muted)" }}
                >
                  {activeAsset.name}
                </span>
              </div>
            </div>
          </div>

          {/* Flexible Content Panels */}
          <div
            className={`flex-1 flex overflow-hidden ${assetViewMode === "split" ? "divide-x" : ""}`}
            style={{ borderColor: "var(--border-muted)" }}
          >
            {(assetViewMode === "edit" || assetViewMode === "split") && (
              <div className="flex-1 flex flex-col min-w-0 relative h-full">
                <textarea
                  ref={editorRef}
                  value={activeAsset.content}
                  onChange={(e) =>
                    updateAssetContent(activeAsset.id, e.target.value)
                  }
                  className="w-full h-full p-12 font-mono text-sm leading-relaxed outline-none resize-none custom-scrollbar selection:bg-brand-500/30"
                  style={{
                    backgroundColor: "var(--bg-deepest)",
                    color: "var(--text-secondary)",
                  }}
                  placeholder="# Orchestrate your document content here..."
                />
                {assetViewMode === "edit" && (
                  <div
                    className="absolute top-4 right-4 text-[9px] font-mono uppercase tracking-[0.2em] px-3 py-1 rounded-full border backdrop-blur"
                    style={{
                      color: "var(--text-faint)",
                      backgroundColor: "var(--bg-deep)",
                      borderColor: "var(--border-muted)",
                    }}
                  >
                    Resource Source Editor
                  </div>
                )}
              </div>
            )}

            {(assetViewMode === "preview" || assetViewMode === "split") && (
              <div
                className="flex-1 flex flex-col min-w-0 h-full relative"
                style={{ backgroundColor: "var(--bg-base)" }}
              >
                <div className="flex-1 p-12 overflow-y-auto custom-scrollbar markdown-preview font-sans max-w-4xl mx-auto w-full">
                  <div dangerouslySetInnerHTML={{ __html: parsedHtml }} />
                  {!parsedHtml && (
                    <div
                      className="flex flex-col items-center justify-center h-full gap-4"
                      style={{ color: "var(--text-faint)" }}
                    >
                      <IconFelix className="w-12 h-12 opacity-10" />
                      <span className="text-xs font-mono uppercase tracking-widest opacity-20">
                        Awaiting content for rendering...
                      </span>
                    </div>
                  )}
                </div>
                {assetViewMode === "preview" && (
                  <div
                    className="absolute top-4 right-4 text-[9px] font-mono uppercase tracking-[0.2em] px-3 py-1 rounded-full border backdrop-blur"
                    style={{
                      color: "var(--text-faint)",
                      backgroundColor: "var(--bg-deep)",
                      borderColor: "var(--border-muted)",
                    }}
                  >
                    Live Visualization
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    );
  };

  // Render the projects view
  const renderProjects = () => {
    return (
      <div
        className="flex-1 flex overflow-hidden"
        style={{ backgroundColor: "var(--bg-base)" }}
      >
        {/* Project Selector Panel */}
        <div
          className="w-80 border-r flex flex-col flex-shrink-0"
          style={{
            borderColor: "var(--border-default)",
            backgroundColor: "var(--bg-deep)",
          }}
        >
          <ProjectSelector
            selectedProjectId={selectedProjectId}
            onSelectProject={handleSelectProject}
          />
        </div>

        {/* Project Details Panel */}
        <div
          className="flex-1 flex flex-col min-w-0"
          style={{ backgroundColor: "var(--bg-deep)" }}
        >
          {/* Show Run Artifact Viewer when a run is selected */}
          {selectedRunId && selectedProjectId ? (
            <RunArtifactViewer
              projectId={selectedProjectId}
              runId={selectedRunId}
              onClose={() => setSelectedRunId(null)}
            />
          ) : selectedProject ? (
            <>
              {/* Project header */}
              <div
                className="h-16 border-b flex items-center px-8 backdrop-blur"
                style={{
                  borderColor: "var(--border-default)",
                  backgroundColor: "var(--bg-base)",
                }}
              >
                <div className="flex-1">
                  <h2
                    className="text-lg font-bold"
                    style={{ color: "var(--text-secondary)" }}
                  >
                    {selectedProject.name ||
                      selectedProject.path.split(/[\\/]/).pop()}
                  </h2>
                  <p
                    className="text-[10px] font-mono truncate max-w-lg"
                    style={{ color: "var(--text-muted)" }}
                  >
                    {selectedProject.path}
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  {selectedProject.status && (
                    <span
                      className={`text-[10px] font-bold px-2 py-1 rounded-lg uppercase ${
                        selectedProject.status === "running"
                          ? "bg-brand-500/20 text-brand-400"
                          : selectedProject.status === "complete"
                            ? "bg-emerald-500/20 text-emerald-400"
                            : selectedProject.status === "blocked"
                              ? "bg-red-500/20 text-red-400"
                              : ""
                      }`}
                      style={{
                        backgroundColor: ![
                          "running",
                          "complete",
                          "blocked",
                        ].includes(selectedProject.status || "")
                          ? "var(--bg-surface)"
                          : undefined,
                        color: !["running", "complete", "blocked"].includes(
                          selectedProject.status || "",
                        )
                          ? "var(--text-tertiary)"
                          : undefined,
                      }}
                    >
                      {selectedProject.status}
                    </span>
                  )}
                </div>
              </div>

              {/* Project overview */}
              <div className="flex-1 p-8 overflow-y-auto custom-scrollbar">
                <div className="grid grid-cols-3 gap-6 mb-8">
                  {/* Specs card */}
                  <div
                    className="border rounded-2xl p-6 hover:border-brand-600/40 transition-all"
                    style={{
                      backgroundColor: "var(--bg-elevated)",
                      borderColor: "var(--border-default)",
                    }}
                  >
                    <div className="flex items-center gap-3 mb-4">
                      <div className="w-10 h-10 bg-brand-500/10 rounded-xl flex items-center justify-center">
                        <IconFileText className="w-5 h-5 text-brand-400" />
                      </div>
                      <div>
                        <h3
                          className="text-2xl font-bold"
                          style={{ color: "var(--text-secondary)" }}
                        >
                          {selectedProject.spec_count}
                        </h3>
                        <p
                          className="text-[10px] font-mono uppercase"
                          style={{ color: "var(--text-muted)" }}
                        >
                          Specifications
                        </p>
                      </div>
                    </div>
                    <button
                      onClick={() => setUiState("assets")}
                      className="w-full py-2 text-xs text-brand-400 hover:text-brand-300 transition-colors"
                    >
                      View Specs →
                    </button>
                  </div>

                  {/* Plan card */}
                  <div
                    className="border rounded-2xl p-6 hover:border-brand-600/40 transition-all"
                    style={{
                      backgroundColor: "var(--bg-elevated)",
                      borderColor: "var(--border-default)",
                    }}
                  >
                    <div className="flex items-center gap-3 mb-4">
                      <div
                        className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                          selectedProject.has_plan ? "bg-emerald-500/10" : ""
                        }`}
                        style={{
                          backgroundColor: !selectedProject.has_plan
                            ? "var(--bg-surface)"
                            : undefined,
                        }}
                      >
                        <IconKanban
                          className={`w-5 h-5 ${
                            selectedProject.has_plan ? "text-emerald-400" : ""
                          }`}
                          style={{
                            color: !selectedProject.has_plan
                              ? "var(--text-muted)"
                              : undefined,
                          }}
                        />
                      </div>
                      <div>
                        <h3
                          className="text-sm font-bold"
                          style={{ color: "var(--text-secondary)" }}
                        >
                          Project README
                        </h3>
                        <p
                          className="text-[10px] font-mono uppercase"
                          style={{ color: "var(--text-muted)" }}
                        >
                          Documentation
                        </p>
                      </div>
                    </div>
                    <button
                      onClick={() => setUiState("plan")}
                      className="w-full py-2 text-xs text-brand-400 hover:text-brand-300 transition-colors"
                    >
                      View README →
                    </button>
                  </div>

                  {/* Requirements card */}
                  <div
                    className="border rounded-2xl p-6 hover:border-brand-600/40 transition-all"
                    style={{
                      backgroundColor: "var(--bg-elevated)",
                      borderColor: "var(--border-default)",
                    }}
                  >
                    <div className="flex items-center gap-3 mb-4">
                      <div
                        className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                          selectedProject.has_requirements
                            ? "bg-amber-500/10"
                            : ""
                        }`}
                        style={{
                          backgroundColor: !selectedProject.has_requirements
                            ? "var(--bg-surface)"
                            : undefined,
                        }}
                      >
                        <IconCpu
                          className={`w-5 h-5 ${
                            selectedProject.has_requirements
                              ? "text-amber-400"
                              : ""
                          }`}
                          style={{
                            color: !selectedProject.has_requirements
                              ? "var(--text-muted)"
                              : undefined,
                          }}
                        />
                      </div>
                      <div>
                        <h3
                          className="text-sm font-bold"
                          style={{ color: "var(--text-secondary)" }}
                        >
                          {selectedProject.has_requirements
                            ? "Configured"
                            : "None"}
                        </h3>
                        <p
                          className="text-[10px] font-mono uppercase"
                          style={{ color: "var(--text-muted)" }}
                        >
                          Requirements
                        </p>
                      </div>
                    </div>
                    <button
                      onClick={() => setUiState("kanban")}
                      className="w-full py-2 text-xs text-brand-400 hover:text-brand-300 transition-colors"
                    >
                      View Board →
                    </button>
                  </div>
                </div>

                {/* Quick actions */}
                <div
                  className="border rounded-2xl p-6 mb-6"
                  style={{
                    backgroundColor: "var(--bg-elevated)",
                    borderColor: "var(--border-default)",
                  }}
                >
                  <h3
                    className="text-xs font-bold uppercase tracking-wider mb-4"
                    style={{ color: "var(--text-tertiary)" }}
                  >
                    Quick Actions
                  </h3>
                  <div className="grid grid-cols-2 gap-3 mb-3">
                    <button
                      onClick={() => setUiState("assets")}
                      className="py-3 px-4 rounded-xl text-sm transition-all flex items-center justify-center gap-2"
                      style={{
                        backgroundColor: "var(--bg-surface)",
                        color: "var(--text-secondary)",
                      }}
                    >
                      <IconFileText className="w-4 h-4" />
                      Edit Specs
                    </button>
                    <button
                      onClick={() => setUiState("kanban")}
                      className="py-3 px-4 rounded-xl text-sm transition-all flex items-center justify-center gap-2"
                      style={{
                        backgroundColor: "var(--bg-surface)",
                        color: "var(--text-secondary)",
                      }}
                    >
                      <IconKanban className="w-4 h-4" />
                      View Board
                    </button>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      onClick={() => setUiState("plan")}
                      className="py-3 px-4 rounded-xl text-sm transition-all flex items-center justify-center gap-2"
                      style={{
                        backgroundColor: "var(--bg-surface)",
                        color: "var(--text-secondary)",
                      }}
                    >
                      <IconFileCode className="w-4 h-4" />
                      View README
                    </button>
                    <button
                      onClick={() => setUiState("config")}
                      className="py-3 px-4 rounded-xl text-sm transition-all flex items-center justify-center gap-2"
                      style={{
                        backgroundColor: "var(--bg-surface)",
                        color: "var(--text-secondary)",
                      }}
                    >
                      <svg
                        className="w-4 h-4"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth="2"
                          d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                        />
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth="2"
                          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                        />
                      </svg>
                      Config
                    </button>
                  </div>
                </div>

                {/* Agent Controls */}
                <AgentControls
                  projectId={selectedProjectId!}
                  onSelectRun={(runId) => setSelectedRunId(runId)}
                />
              </div>
            </>
          ) : (
            // No project selected
            <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
              <div
                className="w-20 h-20 rounded-3xl flex items-center justify-center mb-6"
                style={{ backgroundColor: "var(--bg-surface)" }}
              >
                <IconFelix
                  className="w-10 h-10"
                  style={{ color: "var(--text-faint)" }}
                />
              </div>
              <h2
                className="text-lg font-bold mb-2"
                style={{ color: "var(--text-tertiary)" }}
              >
                No Project Selected
              </h2>
              <p
                className="text-sm max-w-md mb-6"
                style={{ color: "var(--text-muted)" }}
              >
                Select a project from the list to view its details, or register
                a new project to get started.
              </p>
              {backendStatus === "disconnected" && (
                <div className="bg-amber-500/10 border border-amber-500/20 rounded-xl px-4 py-3 text-xs text-amber-400">
                  <span className="font-bold">Backend Offline:</span> Start the
                  Felix backend server to manage projects.
                  <code
                    className="block mt-2 px-2 py-1 rounded text-amber-300"
                    style={{ backgroundColor: "var(--bg-deepest)" }}
                  >
                    cd app/backend && python main.py
                  </code>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    );
  };

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        isUserMenuOpen &&
        userMenuRef.current &&
        !userMenuRef.current.contains(event.target as Node)
      ) {
        setUserMenuOpen(false);
      }
    };

    const handleEsc = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setUserMenuOpen(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("keydown", handleEsc);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleEsc);
    };
  }, [isUserMenuOpen]);

  return (
    <div
      className="flex h-screen w-screen flex-col overflow-hidden font-sans selection:bg-brand-500/30"
      style={{
        backgroundColor: "var(--bg-deepest)",
        color: "var(--text-secondary)",
      }}
    >
      <header
        className="h-16 border-b flex items-center px-4 justify-between backdrop-blur-2xl z-10"
        style={{
          borderColor: "var(--border-default)",
          backgroundColor: "var(--bg-deep)",
        }}
      >
        <div className="flex items-center gap-8 flex-1 min-w-0">
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-2xl flex items-center justify-center shadow-sm"
              style={{
                background:
                  "linear-gradient(135deg, rgba(62, 207, 142, 0.15), rgba(62, 207, 142, 0.05))",
              }}
            >
              <IconFelix className="w-5 h-5 text-brand-500" />
            </div>
            <div className="min-w-0 leading-tight">
              <div className="flex items-center gap-2">
                <span
                  className="text-sm font-semibold"
                  style={{ color: "var(--text-secondary)" }}
                >
                  UntrueAxioms
                </span>
                <span
                  className="text-[10px] font-semibold uppercase tracking-[0.3em] px-2 py-0.5 rounded-full border"
                  style={{
                    borderColor: "var(--border-muted)",
                    color: "var(--text-muted)",
                  }}
                >
                  FREE
                </span>
              </div>
            </div>
          </div>

          <div className="flex flex-col min-w-0">
            <div className="flex items-center gap-3">
              <span
                className="w-2 h-2 rounded-full shadow"
                style={{ backgroundColor: activeViewMeta.color }}
              ></span>
              <span
                className="text-sm font-bold uppercase tracking-[0.2em]"
                style={{ color: "var(--text-secondary)" }}
              >
                {activeViewMeta.label}
              </span>
            </div>
          </div>
        </div>

        <div className="flex-1 flex justify-center">
          <div className="max-w-2xl w-full">
            <div
              className="flex items-center gap-3 px-4 py-2 rounded-full border"
              style={{
                borderColor: "var(--border-muted)",
                backgroundColor: "var(--bg-base)",
              }}
            >
              <IconSearch
                className="w-4 h-4"
                style={{ color: "var(--text-muted)" }}
              />
              <input
                type="text"
                placeholder="Search for a project or command"
                className="flex-1 bg-transparent outline-none text-sm"
                style={{ color: "var(--text-secondary)" }}
              />
              <span
                className="text-[10px] uppercase tracking-[0.3em]"
                style={{ color: "var(--text-muted)" }}
              >
                ⌘K
              </span>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-5 flex-0">
          <button
            className="text-[11px] font-bold uppercase tracking-[0.3em] border border-transparent rounded-full px-4 py-1 transition-all"
            style={{
              color: "var(--text-secondary)",
              borderColor: "transparent",
            }}
          >
            Feedback
          </button>
          <button
            className="w-8 h-8 rounded-full border flex items-center justify-center"
            style={{
              borderColor: "var(--border-muted)",
              color: "var(--text-muted)",
            }}
            title="Help"
          >
            ?
          </button>
          <div className="relative" ref={userMenuRef}>
            <button
              className="w-11 h-11 rounded-full border shadow-inner flex items-center justify-center text-[10px] font-bold"
              style={{
                borderColor: "var(--border-muted)",
                color: "var(--text-muted)",
                backgroundColor: "var(--bg-surface)",
              }}
              onClick={() => setUserMenuOpen((prev) => !prev)}
              aria-haspopup="true"
              aria-expanded={isUserMenuOpen}
              title="User menu"
            >
              NS
            </button>
            {isUserMenuOpen && (
              <div className="user-menu-panel">
                <div className="user-menu-header">
                  <p className="text-sm font-bold">nsasto</p>
                  <p className="text-[10px] opacity-60">nsasto@gmail.com</p>
                </div>
                <hr />
                <button
                  className="user-menu-item"
                  onClick={() => setUserMenuOpen(false)}
                >
                  Account preferences
                </button>
                <button
                  className="user-menu-item"
                  onClick={() => setUserMenuOpen(false)}
                >
                  Feature previews
                </button>
                <div className="user-menu-divider" />
                <p className="user-menu-divider-label">Theme</p>
                {themeOptions.map((option) => {
                  const showDot = option.value === theme && !option.isVariant;
                  return (
                    <button
                      key={option.label}
                      className={`user-menu-item ${
                        showDot ? "selected" : ""
                      }`}
                      onClick={() => {
                        setTheme(option.value);
                        setUserMenuOpen(false);
                      }}
                    >
                      {showDot && (
                        <span className="user-menu-item-dot" />
                      )}
                      {option.label}
                    </button>
                  );
                })}
                <div className="user-menu-divider" />
                <button
                  className="user-menu-item"
                  onClick={() => setUserMenuOpen(false)}
                >
                  Log out
                </button>
              </div>
            )}
          </div>
        </div>
      </header>
      <div className="flex flex-1 overflow-hidden">
        <Sidebar
          activeView={activeSidebarView}
          onChangeView={(view) => setUiState(view)}
          backendStatus={backendStatus}
          projectName={
            selectedProject
              ? selectedProject.name ||
                selectedProject.path.split(/[\\/]/).pop()
              : null
          }
        />
        {/* Main View Container */}
        <div className="flex-1 flex flex-col relative min-w-0 mb-8">
          {uiState === "projects" ? (
            renderProjects()
          ) : uiState === "kanban" ? (
            selectedProjectId ? (
              <RequirementsKanban
                projectId={selectedProjectId}
                onSelectRequirement={(req) => {
                  // Open run artifact viewer if this requirement has a last run
                  if (req.last_run_id) {
                    setSelectedRunId(req.last_run_id);
                  }
                }}
              />
            ) : (
              <div
                className="flex-1 flex flex-col items-center justify-center text-center"
                style={{ backgroundColor: "var(--bg-deepest)" }}
              >
                <span
                  className="text-sm"
                  style={{ color: "var(--text-muted)" }}
                >
                  Select a project to view requirements
                </span>
                <button
                  onClick={() => setUiState("projects")}
                  className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors"
                >
                  Go to Projects
                </button>
              </div>
            )
          ) : uiState === "orchestration" ? (
            selectedProjectId ? (
              <AgentDashboard projectId={selectedProjectId} />
            ) : (
              <div
                className="flex-1 flex flex-col items-center justify-center text-center"
                style={{ backgroundColor: "var(--bg-deepest)" }}
              >
                <span
                  className="text-sm"
                  style={{ color: "var(--text-muted)" }}
                >
                  Select a project to view agent dashboard
                </span>
                <button
                  onClick={() => setUiState("projects")}
                  className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors"
                >
                  Go to Projects
                </button>
              </div>
            )
          ) : uiState === "assets" ? (
            selectedProjectId ? (
              <SpecsEditor
                projectId={selectedProjectId}
                onSelectSpec={(filename) => {
                  console.log("Selected spec:", filename);
                }}
              />
            ) : (
              <div
                className="flex-1 flex flex-col items-center justify-center text-center"
                style={{ backgroundColor: "var(--bg-deepest)" }}
              >
                <span
                  className="text-sm"
                  style={{ color: "var(--text-muted)" }}
                >
                  Select a project to view specs
                </span>
                <button
                  onClick={() => setUiState("projects")}
                  className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors"
                >
                  Go to Projects
                </button>
              </div>
            )
          ) : uiState === "config" ? (
            selectedProjectId ? (
              <ConfigPanel
                projectId={selectedProjectId}
                onClose={() => setUiState("projects")}
              />
            ) : (
              <div
                className="flex-1 flex flex-col items-center justify-center text-center"
                style={{ backgroundColor: "var(--bg-deepest)" }}
              >
                <span
                  className="text-sm"
                  style={{ color: "var(--text-muted)" }}
                >
                  Select a project to view configuration
                </span>
                <button
                  onClick={() => setUiState("projects")}
                  className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors"
                >
                  Go to Projects
                </button>
              </div>
            )
          ) : uiState === "plan" ? (
            selectedProjectId ? (
              <PlanViewer
                projectId={selectedProjectId}
                onBack={() => setUiState("projects")}
              />
            ) : (
              <div
                className="flex-1 flex flex-col items-center justify-center text-center"
                style={{ backgroundColor: "var(--bg-deepest)" }}
              >
                <span
                  className="text-sm"
                  style={{ color: "var(--text-muted)" }}
                >
                  Select a project to view README
                </span>
                <button
                  onClick={() => setUiState("projects")}
                  className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors"
                >
                  Go to Projects
                </button>
              </div>
            )
          ) : uiState === "settings" ? (
            <SettingsScreen
              projectId={selectedProjectId ?? undefined}
              onBack={() => setUiState("projects")}
            />
          ) : (
            <div
              className="flex-1 flex flex-col items-center justify-center text-center"
              style={{ backgroundColor: "var(--bg-deepest)" }}
            >
              <span className="text-sm" style={{ color: "var(--text-muted)" }}>
                Unknown view state
              </span>
              <button
                onClick={() => setUiState("projects")}
                className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors"
              >
                Go to Projects
              </button>
            </div>
          )}
        </div>

        {/* Copilot Chat - Always rendered when in specs view */}
        {uiState === "assets" && selectedProjectId && (
          <CopilotChat projectId={selectedProjectId} />
        )}
      </div>

      {/* Persistent OS Status Bar */}
      <footer
        className="h-8 border-t flex items-center px-6 justify-between text-[10px] font-mono z-40 fixed bottom-0 left-0 right-0 select-none flex-shrink-0 backdrop-blur-xl"
        style={{
          borderColor: "var(--border-default)",
          backgroundColor: "var(--bg-base)",
          color: "var(--text-muted)",
        }}
      >
        <div className="flex items-center gap-6">
          <div
            className="flex items-center gap-2 group cursor-default"
            style={{ color: "var(--accent-primary)" }}
          >
            <IconTerminal className="w-3.5 h-3.5 group-hover:animate-pulse" />
            <span className="font-bold uppercase tracking-[0.2em] text-[9px]">
              Felix Kernel: 3.1-STABLE
            </span>
          </div>
          <div
            className="h-4 w-[1px] opacity-50"
            style={{ backgroundColor: "var(--border-default)" }}
          ></div>
          <span
            className="opacity-60 uppercase tracking-tighter"
            style={{ color: "var(--text-faint)" }}
          >
            ID: FLX-ORCH-8821
          </span>
          <span
            className="opacity-60 uppercase"
            style={{ color: "var(--text-faint)" }}
          >
            Load: 0.42 / 1.00
          </span>
        </div>
        <div className="flex items-center gap-6">
          <div className="flex items-center gap-2 transition-colors cursor-pointer">
            <span className="uppercase text-[9px]">Latency</span>
            <span className="text-emerald-500 font-bold">18ms</span>
          </div>
          <div
            className="h-4 w-[1px] opacity-50"
            style={{ backgroundColor: "var(--border-default)" }}
          ></div>
          <div className="flex items-center gap-2 group cursor-pointer">
            <div className="w-2 h-2 rounded-full bg-emerald-500 shadow-sm shadow-emerald-500/20 group-hover:scale-125 transition-transform"></div>
            <span className="uppercase tracking-[0.1em] transition-colors">
              Workspace Encrypted
            </span>
          </div>
          <div
            className="h-4 w-[1px] opacity-50"
            style={{ backgroundColor: "var(--border-default)" }}
          ></div>
          <span className="cursor-pointer transition-colors uppercase tracking-widest font-bold">
            UTF-8
          </span>
        </div>
      </footer>
    </div>
  );
};

export default App;

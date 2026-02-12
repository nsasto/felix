import React, { useState, useEffect, useRef, useMemo } from "react";
import { Task, UIState, MarkdownAsset } from "./types";
import { felixApi, ProjectDetails } from "./services/felixApi";
import {
  Bot as IconFelix,
  Search as IconSearch,
  Terminal as IconTerminal,
  Code,
  Copy,
  FileCode as IconFileCode,
  FileText as IconFileText,
  List,
  Cpu as IconCpu,
  Kanban as IconKanban,
  Plus as IconPlus,
  Activity as IconPulse,
  LayoutGrid as IconOrganization,
  ChevronDown as IconChevronDown,
  CircleHelp as IconHelpCircle,
  CheckCircle as IconCheckCircle,
} from "lucide-react";
import FelixLogo from "../../img/felix_logo_small.png";
import FelixLogoHover from "../../img/felix_logo_hammer_small.png";
import AgentControls from "./components/AgentControls";
import RunArtifactViewer from "./components/RunArtifactViewer";
import ProjectsView from "./components/views/ProjectsView";
import KanbanView from "./components/views/KanbanView";
import OrchestrationView from "./components/views/OrchestrationView";
import SpecsView from "./components/views/SpecsView";
import ConfigView from "./components/views/ConfigView";
import PlanView from "./components/views/PlanView";
import SettingsView from "./components/views/SettingsView";
import { marked } from "marked";
import { ThemeValue, useTheme } from "./hooks/ThemeProvider";
import Sidebar, { SidebarView, SidebarMode } from "./components/Sidebar";
import { Toaster } from "./components/ui/sonner";
import { Button } from "./components/ui/button";
import { Input } from "./components/ui/input";
import { Textarea } from "./components/ui/textarea";

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
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("expanded");
  const [isUserMenuOpen, setUserMenuOpen] = useState(false);
  const userMenuRef = useRef<HTMLDivElement | null>(null);
  const [isLogoHovered, setLogoHovered] = useState(false);
  const [isOrgMenuOpen, setOrgMenuOpen] = useState(false);
  const orgMenuRef = useRef<HTMLDivElement | null>(null);
  const [orgSearch, setOrgSearch] = useState("");
  const [selectedOrg, setSelectedOrg] = useState("UntrueAxioms");
  const [userProfile, setUserProfile] = useState<{
    user_id: string;
    email: string | null;
    organization: string | null;
    org_slug: string | null;
    role: string;
  } | null>(null);

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
  const themeOptions: Array<{
    label: string;
    value: ThemeValue;
    isVariant?: boolean;
  }> = [
    { label: "Dark", value: "dark" },
    { label: "Light", value: "light" },
    { label: "Classic Dark", value: "dark", isVariant: true },
    { label: "System", value: "system" },
  ];
  const orgOptions = [
    { id: "untrueaxioms", label: "UntrueAxioms", type: "org" },
    { id: "all", label: "All Organizations", type: "org" },
    { id: "new", label: "New organization", type: "action" },
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

  // Fetch user profile from backend
  useEffect(() => {
    const fetchUserProfile = async () => {
      try {
        const profile = await felixApi.getUserProfile();
        setUserProfile(profile);
        // Update organization name if available
        if (profile.organization) {
          setSelectedOrg(profile.organization);
        }
      } catch (e) {
        console.warn("Failed to fetch user profile:", e);
      }
    };
    fetchUserProfile();
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
          // Keep projects view and show the dashboard
          setUiState("projects");
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
    // Stay on projects page to show dashboard
  };

  const clearSelectedProject = () => {
    setSelectedProjectId(null);
    setSelectedProject(null);
  };

  const handleReturnToProjects = () => {
    clearSelectedProject();
    setUiState("projects");
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
      <div className="flex-1 flex gap-6 p-8 overflow-x-auto custom-scrollbar bg-[var(--bg-base)]">
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
                          : "bg-[var(--text-muted)]"
                  }`}
                />
                <h3
                  className="text-xs font-bold uppercase tracking-widest text-[var(--text-tertiary)]"
                >
                  {col.label}
                </h3>
              </div>
              <span
                className="text-[10px] font-mono px-1.5 py-0.5 rounded text-[var(--text-muted)] bg-[var(--bg-deep)]"
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
                    className="border border-[var(--border-default)] bg-[var(--bg-base)] p-4 rounded-xl hover:border-brand-600/40 transition-all cursor-pointer group shadow-lg"
                  >
                    <div className="flex justify-between items-start mb-2">
                      <span
                        className={`text-[9px] font-bold px-1.5 py-0.5 rounded uppercase ${
                          task.priority === "high"
                            ? "bg-red-500/10 text-red-400 border border-red-500/20"
                            : task.priority === "medium"
                              ? "bg-amber-500/10 text-amber-400 border border-amber-500/20"
                              : "bg-[var(--bg-surface)] text-[var(--text-tertiary)]"
                        }`}
                      >
                        {task.priority}
                      </span>
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        className="opacity-0 group-hover:opacity-100 p-1 h-7 w-7 rounded transition-opacity bg-transparent"
                      >
                        <IconPlus className="w-3 h-3 text-[var(--text-muted)]" />
                      </Button>
                    </div>
                    <h4
                      className="text-sm font-semibold mb-1 group-hover:text-brand-400 transition-colors text-[var(--text-secondary)]"
                    >
                      {task.title}
                    </h4>
                    <p
                      className="text-[11px] leading-relaxed mb-3 line-clamp-2 text-[var(--text-muted)]"
                    >
                      {task.description}
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {task.tags.map((tag) => (
                        <span
                          key={tag}
                          className="text-[9px] font-mono border border-[var(--border-default)] px-1 rounded transition-colors text-[var(--text-muted)]"
                        >
                          #{tag}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="w-full py-2 border border-[var(--border-default)] border-dashed rounded-xl text-[10px] transition-all flex items-center justify-center gap-2 group h-auto text-[var(--text-muted)]"
              >
                <IconPlus className="w-3 h-3 group-hover:scale-125 transition-transform" />
                Add Task
              </Button>
            </div>
          </div>
        ))}
      </div>
    );
  };

  const renderCanvas = () => {
    return (
      <div className="flex-1 flex overflow-hidden bg-[var(--bg-base)]">
        <div
          className="flex-1 flex flex-col border-r border-[var(--border-default)]"
        >
          <div
            className="h-12 border-b border-[var(--border-default)] bg-[var(--bg-base)] flex items-center px-6 justify-between backdrop-blur"
          >
            <div className="flex items-center gap-3">
              <IconFileCode className="w-4 h-4 text-[var(--accent-primary)]" />
              <span
                className="text-xs font-mono font-bold text-[var(--text-tertiary)]"
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
      <div className="flex-1 flex overflow-hidden bg-[var(--bg-base)]">
        {/* Sub-nav Panel */}
        <div
          className="w-64 border-r border-[var(--border-default)] flex flex-col flex-shrink-0 bg-[var(--bg-deep)]"
        >
          <div
            className="h-12 border-b border-[var(--border-default)] flex items-center px-4"
          >
            <span
              className="text-[10px] font-bold uppercase tracking-widest text-[var(--text-muted)]"
            >
              Project Workspace
            </span>
          </div>
          <div className="p-3 space-y-1 overflow-y-auto custom-scrollbar">
            {assets.map((asset) => (
              <Button
                key={asset.id}
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  setSelectedAssetId(asset.id);
                }}
                className={`w-full h-auto flex items-center gap-3 px-3 py-2.5 rounded-xl text-xs transition-all border ${
                  selectedAssetId === asset.id
                    ? "bg-brand-600/10 text-brand-400 border-brand-500/20 shadow-lg shadow-brand-900/10"
                    : "border-transparent text-[var(--text-muted)]"
                }`}
              >
                <IconFileText className="w-4 h-4" />
                <div className="flex flex-col items-start min-w-0">
                  <span className="truncate font-medium">{asset.name}</span>
                  <span className="text-[9px] opacity-40 font-mono">
                    markdown
                  </span>
                </div>
              </Button>
            ))}
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="w-full h-auto flex items-center gap-2 px-3 py-2 rounded-xl text-xs border border-[var(--border-default)] border-dashed mt-4 transition-all text-[var(--text-muted)]"
            >
              <IconPlus className="w-3.5 h-3.5" />
              <span>New Resource</span>
            </Button>
          </div>
        </div>

        {/* Integrated Orchestration Canvas */}
        <div
          className="flex-1 flex flex-col min-w-0 bg-[var(--bg-deep)]"
        >
          <div
            className="h-12 border-b border-[var(--border-default)] bg-[var(--bg-base)] flex items-center px-4 justify-between backdrop-blur z-20 flex-shrink-0"
          >
            <div className="flex items-center gap-4">
              <div
                className="flex border border-[var(--border-default)] rounded-lg p-0.5 shadow-inner bg-[var(--bg-deep)]"
              >
                <Button
                  onClick={() => setAssetViewMode("edit")}
                  variant="ghost"
                  size="sm"
                  className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${
                    assetViewMode === "edit"
                      ? "bg-[var(--bg-surface)] text-[var(--accent-primary)]"
                      : "bg-transparent text-[var(--text-muted)]"
                  }`}
                >
                  SOURCE
                </Button>
                <Button
                  onClick={() => setAssetViewMode("split")}
                  variant="ghost"
                  size="sm"
                  className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${
                    assetViewMode === "split"
                      ? "bg-[var(--bg-surface)] text-[var(--accent-primary)]"
                      : "bg-transparent text-[var(--text-muted)]"
                  }`}
                >
                  ORCHESTRATE
                </Button>
                <Button
                  onClick={() => setAssetViewMode("preview")}
                  variant="ghost"
                  size="sm"
                  className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all ${
                    assetViewMode === "preview"
                      ? "bg-[var(--bg-surface)] text-[var(--accent-primary)]"
                      : "bg-transparent text-[var(--text-muted)]"
                  }`}
                >
                  PREVIEW
                </Button>
              </div>

              {(assetViewMode === "edit" || assetViewMode === "split") && (
                <div
                  className="flex items-center gap-0.5 border-l border-[var(--border-default)] pl-4"
                >
                  <Button
                    onClick={() => insertFormatting("# ")}
                    variant="ghost"
                    size="icon"
                    className="p-1.5 rounded-md transition-all text-[var(--text-muted)]"
                    title="H1"
                  >
                    <span className="font-bold text-xs">H1</span>
                  </Button>
                  <Button
                    onClick={() => insertFormatting("## ")}
                    variant="ghost"
                    size="icon"
                    className="p-1.5 rounded-md transition-all text-[var(--text-muted)]"
                    title="H2"
                  >
                    <span className="font-bold text-xs">H2</span>
                  </Button>
                  <Button
                    onClick={() => insertFormatting("**", "**")}
                    variant="ghost"
                    size="icon"
                    className="p-1.5 rounded-md transition-all text-[var(--text-muted)]"
                    title="Bold"
                  >
                    <span className="font-bold text-xs uppercase">B</span>
                  </Button>
                  <Button
                    onClick={() => insertFormatting("*", "*")}
                    variant="ghost"
                    size="icon"
                    className="p-1.5 rounded-md transition-all text-[var(--text-muted)]"
                    title="Italic"
                  >
                    <span className="italic text-xs font-serif font-bold uppercase">
                      I
                    </span>
                  </Button>
                  <Button
                    onClick={() => insertFormatting("- ")}
                    variant="ghost"
                    size="icon"
                    className="p-1.5 rounded-md transition-all text-[var(--text-muted)]"
                    title="List"
                  >
                    <List className="w-3.5 h-3.5" />
                  </Button>
                  <Button
                    onClick={() => insertFormatting("`", "`")}
                    variant="ghost"
                    size="icon"
                    className="p-1.5 rounded-md transition-all text-[var(--text-muted)]"
                    title="Code"
                  >
                    <Code className="w-3.5 h-3.5" />
                  </Button>
                </div>
              )}
            </div>

            <div className="flex items-center gap-4">
              <Button
                onClick={copyToClipboard}
                variant="ghost"
                size="sm"
                className="text-[10px] font-bold transition-colors uppercase tracking-widest flex items-center gap-2 text-[var(--text-muted)]"
              >
                <Copy className="w-3 h-3" />
                Copy Raw
              </Button>
              <div className="h-4 w-px bg-[var(--border-default)]"></div>
              <div className="flex items-center gap-2">
                <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></div>
                <span
                  className="text-[10px] font-mono uppercase text-[var(--text-muted)]"
                >
                  {activeAsset.name}
                </span>
              </div>
            </div>
          </div>

          {/* Flexible Content Panels */}
          <div
            className={`flex-1 flex overflow-hidden ${assetViewMode === "split" ? "divide-x divide-[var(--border-muted)]" : ""}`}
          >
            {(assetViewMode === "edit" || assetViewMode === "split") && (
              <div className="flex-1 flex flex-col min-w-0 relative h-full">
                <Textarea
                  ref={editorRef}
                  value={activeAsset.content}
                  onChange={(e) =>
                    updateAssetContent(activeAsset.id, e.target.value)
                  }
                  className="w-full h-full p-12 font-mono text-sm leading-relaxed outline-none resize-none custom-scrollbar selection:bg-brand-500/30 bg-[var(--bg-base)] text-[var(--text-secondary)]"
                  placeholder="# Orchestrate your document content here..."
                />
                {assetViewMode === "edit" && (
                  <div
                    className="absolute top-4 right-4 text-[9px] font-mono uppercase tracking-[0.2em] px-3 py-1 rounded-full border border-[var(--border-muted)] backdrop-blur text-[var(--text-faint)] bg-[var(--bg-deep)]"
                  >
                    Resource Source Editor
                  </div>
                )}
              </div>
            )}

            {(assetViewMode === "preview" || assetViewMode === "split") && (
              <div
                className="flex-1 flex flex-col min-w-0 h-full relative bg-[var(--bg-base)]"
              >
                <div className="flex-1 p-12 overflow-y-auto custom-scrollbar markdown-preview font-sans max-w-4xl mx-auto w-full">
                  <div dangerouslySetInnerHTML={{ __html: parsedHtml }} />
                  {!parsedHtml && (
                    <div
                      className="flex flex-col items-center justify-center h-full gap-4 text-[var(--text-faint)]"
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
                    className="absolute top-4 right-4 text-[9px] font-mono uppercase tracking-[0.2em] px-3 py-1 rounded-full border border-[var(--border-muted)] backdrop-blur text-[var(--text-faint)] bg-[var(--bg-deep)]"
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

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      const target = event.target as Node;
      if (
        isUserMenuOpen &&
        userMenuRef.current &&
        !userMenuRef.current.contains(target)
      ) {
        setUserMenuOpen(false);
      }
      if (
        isOrgMenuOpen &&
        orgMenuRef.current &&
        !orgMenuRef.current.contains(target)
      ) {
        setOrgMenuOpen(false);
      }
    };

    const handleEsc = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setUserMenuOpen(false);
        setOrgMenuOpen(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("keydown", handleEsc);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleEsc);
    };
  }, [isUserMenuOpen, isOrgMenuOpen]);

  return (
    <div className="flex h-screen w-screen flex-col overflow-hidden font-sans selection:bg-brand-500/30 bg-[var(--bg-base)] text-[var(--text-secondary)]">
      <header
        className="h-16 flex items-center px-6 justify-between gap-6 shrink-0 border-b border-[var(--border-default)] bg-[var(--bg-base)] backdrop-blur relative z-[var(--z-fixed)]"
      >
        <div className="flex items-center gap-3">
          <div
            className="w-10 h-10 rounded-2xl overflow-hidden shadow-sm transition-transform duration-150"
            onMouseEnter={() => setLogoHovered(true)}
            onMouseLeave={() => setLogoHovered(false)}
          >
            <img
              src={isLogoHovered ? FelixLogoHover : FelixLogo}
              alt="Felix logo"
              className="w-full h-full object-cover"
            />
          </div>
          <span
            className="text-sm font-semibold text-[var(--text-secondary)]"
          >
            /
          </span>
          <div className="org-menu-group" ref={orgMenuRef}>
            <div className="flex items-center gap-2">
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="flex items-center gap-2 px-3 py-1.5 rounded-full text-sm font-semibold transition-colors text-[var(--text-secondary)] bg-transparent border-0"
                onClick={() => setOrgMenuOpen((prev) => !prev)}
                aria-haspopup="true"
                aria-expanded={isOrgMenuOpen}
              >
                <IconOrganization className="w-4 h-4 text-[var(--text-muted)]" />
                <span>{selectedOrg}</span>
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="org-menu-trigger"
                onClick={() => setOrgMenuOpen((prev) => !prev)}
                aria-label="Organization menu"
              >
                <IconChevronDown className="w-4 h-4" />
              </Button>
              <span
                className="text-[9px] font-semibold uppercase tracking-[0.2em] rounded-full border border-[var(--border-muted)] px-2 py-0.5 text-[var(--text-muted)]"
              >
                FREE
              </span>
            </div>
            {isOrgMenuOpen && (
              <div className="org-menu-panel">
                <div className="org-menu-search">
                  <IconSearch className="w-4 h-4" />
                  <Input
                    type="text"
                    placeholder="Search organizations"
                    autoComplete="off"
                    autoCorrect="off"
                    autoCapitalize="off"
                    spellCheck={false}
                    value={orgSearch}
                    onChange={(event) => setOrgSearch(event.target.value)}
                    className="border-0 bg-transparent p-0 h-auto focus-visible:ring-0 focus-visible:ring-offset-0"
                  />
                </div>
                <div className="org-menu-list">
                  {orgOptions
                    .filter((option) =>
                      option.label
                        .toLowerCase()
                        .includes(orgSearch.toLowerCase()),
                    )
                    .map((option) => {
                      const isSelected = option.label === selectedOrg;
                      return (
                        <Button
                          key={option.id}
                          type="button"
                          variant="ghost"
                          size="sm"
                          className={`org-menu-item ${isSelected ? "selected" : ""} justify-start text-left`}
                          onClick={() => {
                            if (option.type === "org") {
                              setSelectedOrg(option.label);
                            }
                            setOrgMenuOpen(false);
                          }}
                        >
                          <span>{option.label}</span>
                          {isSelected && (
                            <IconCheckCircle className="w-4 h-4" />
                          )}
                          {option.type === "action" && !isSelected && (
                            <IconPlus className="w-4 h-4" />
                          )}
                        </Button>
                      );
                    })}
                </div>
              </div>
            )}
          </div>
          <div
            className="flex items-center gap-3 text-xs font-semibold uppercase tracking-[0.15em] text-[var(--text-muted)]"
          >
            <span>/</span>
            {selectedProject && (
              <>
                <Button
                  onClick={handleReturnToProjects}
                  variant="ghost"
                  size="sm"
                  className="text-sm font-semibold transition-colors hover:text-[var(--accent-primary)] cursor-pointer px-1 text-[var(--text-secondary)]"
                >
                  {selectedProject.name ||
                    selectedProject.path.split(/[\\/]/).pop()}
                </Button>
                <span>/</span>
              </>
            )}
            <div className="flex items-center gap-2">
              <span
                className="w-2 h-2 rounded-full shadow"
                style={{ backgroundColor: activeViewMeta.color }}
              />
              <span
                className="text-sm font-semibold text-[var(--text-secondary)]"
              >
                {activeViewMeta.label}
              </span>
            </div>
            <span
              className="text-[9px] font-bold px-2 py-0.5 rounded-full border border-[var(--border-muted)] text-[var(--text-muted)]"
            >
              {activeViewMeta.tag}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-3 justify-end flex-1" />

        <div className="flex items-center gap-3">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="text-xs font-semibold uppercase tracking-[0.3em] text-[var(--text-secondary)]"
          >
            Feedback
          </Button>
          <div
            className="flex items-center gap-3 px-3 py-2 border rounded-full border-[var(--border-muted)] bg-[var(--bg-surface)]"
          >
            <IconSearch className="w-4 h-4 text-[var(--text-muted)]" />
            <Input
              type="text"
              placeholder="Search... Ctrl+K"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
              className="flex-1 bg-transparent outline-none text-sm border-0 p-0 h-auto focus-visible:ring-0 focus-visible:ring-offset-0 text-[var(--text-secondary)]"
            />
          </div>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="w-9 h-9 rounded-full border border-[var(--border-muted)] text-[var(--text-muted)] bg-transparent"
            aria-label="Help"
          >
            <IconHelpCircle className="w-5 h-5" />
          </Button>
          <div className="relative" ref={userMenuRef}>
            <Button
              type="button"
              variant="ghost"
              className="w-11 h-11 rounded-full border border-[var(--border-muted)] shadow-inner flex items-center justify-center text-[10px] font-bold text-[var(--text-muted)] bg-[var(--bg-surface)]"
              onClick={() => setUserMenuOpen((prev) => !prev)}
              aria-haspopup="true"
              aria-expanded={isUserMenuOpen}
              title="User menu"
            >
              {userProfile?.user_id
                ? userProfile.user_id
                    .split(/[^a-zA-Z0-9]/)
                    .filter((part) => part.length > 0)
                    .map((part) => part[0].toUpperCase())
                    .slice(0, 2)
                    .join("")
                : "?"}
            </Button>
            {isUserMenuOpen && (
              <div className="user-menu-panel">
                <div className="user-menu-header">
                  <p className="text-sm font-bold">
                    {userProfile?.user_id || "Loading..."}
                  </p>
                  <p className="text-[10px] opacity-60">
                    {userProfile?.email || ""}
                  </p>
                </div>
                <hr />
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="user-menu-item justify-start text-left"
                  onClick={() => setUserMenuOpen(false)}
                >
                  Account preferences
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="user-menu-item justify-start text-left"
                  onClick={() => setUserMenuOpen(false)}
                >
                  Feature previews
                </Button>
                <div className="user-menu-divider" />
                <p className="user-menu-divider-label">Theme</p>
                {themeOptions.map((option) => {
                  const showDot = option.value === theme && !option.isVariant;
                  return (
                    <Button
                      key={option.label}
                      type="button"
                      variant="ghost"
                      size="sm"
                      className={`user-menu-item ${showDot ? "selected" : ""} justify-start text-left`}
                      onClick={() => {
                        setTheme(option.value);
                        setUserMenuOpen(false);
                      }}
                    >
                      {showDot && <span className="user-menu-item-dot" />}
                      {option.label}
                    </Button>
                  );
                })}
                <div className="user-menu-divider" />
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="user-menu-item justify-start text-left"
                  onClick={() => setUserMenuOpen(false)}
                >
                  Log out
                </Button>
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
          onModeChange={setSidebarMode}
        />
        {/* Main View Container */}
        <div className="main-view flex-1 flex flex-col relative min-w-0 mb-8">
          {uiState === "projects" ? (
            <ProjectsView
              selectedProjectId={selectedProjectId}
              selectedProject={selectedProject}
              onSelectProject={handleSelectProject}
              onNavigate={(view) => setUiState(view as ExtendedUIState)}
            />
          ) : uiState === "kanban" ? (
            <KanbanView
              projectId={selectedProjectId}
              onGoToProjects={() => setUiState("projects")}
              onSelectRequirement={(req) => {
                if (req.last_run_id) {
                  setSelectedRunId(req.last_run_id);
                }
              }}
            />
          ) : uiState === "orchestration" ? (
            <OrchestrationView
              projectId={selectedProjectId}
              onGoToProjects={() => setUiState("projects")}
            />
          ) : uiState === "assets" ? (
            <SpecsView
              projectId={selectedProjectId}
              onGoToProjects={() => setUiState("projects")}
              onSelectSpec={(filename) => {
                console.log("Selected spec:", filename);
              }}
            />
          ) : uiState === "config" ? (
            <ConfigView
              projectId={selectedProjectId}
              onGoToProjects={() => setUiState("projects")}
            />
          ) : uiState === "plan" ? (
            <PlanView
              projectId={selectedProjectId}
              onGoToProjects={() => setUiState("projects")}
            />
          ) : uiState === "settings" ? (
            <SettingsView
              projectId={selectedProjectId ?? undefined}
              onBack={() => setUiState("projects")}
            />
          ) : (
            <div
              className="flex-1 flex flex-col items-center justify-center text-center bg-[var(--bg-base)]"
            >
              <span className="text-sm text-[var(--text-muted)]">
                Unknown view state
              </span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setUiState("projects")}
                className="mt-4 px-4 py-2 text-xs font-bold text-brand-400 border border-brand-500/20 rounded-lg hover:bg-brand-500/10 transition-colors h-auto"
              >
                Go to Projects
              </Button>
            </div>
          )}
        </div>
      </div>

      {/* Persistent OS Status Bar */}
      <footer
        className="footer-bar h-8 border-t border-[var(--border-default)] bg-[var(--bg-base)] text-[var(--text-muted)] z-[var(--z-fixed)] flex items-center px-6 justify-between text-[10px] font-mono fixed bottom-0 select-none flex-shrink-0 backdrop-blur-xl"
        style={{
          left: "var(--sidebar-offset, 240px)",
          width: "calc(100% - var(--sidebar-offset, 240px))",
        }}
      >
        <div className="flex items-center gap-6">
          <div
            className="flex items-center gap-2 group cursor-default text-[var(--accent-primary)]"
          >
            <IconTerminal className="w-3.5 h-3.5 group-hover:animate-pulse" />
            <span className="font-bold uppercase tracking-[0.2em] text-[9px]">
              Felix Kernel: 3.1-STABLE
            </span>
          </div>
          <div className="h-4 w-[1px] opacity-50 bg-[var(--border-default)]"></div>
          <span
            className="opacity-60 uppercase tracking-tighter text-[var(--text-faint)]"
          >
            ID: FLX-ORCH-8821
          </span>
          <span
            className="opacity-60 uppercase text-[var(--text-faint)]"
          >
            Load: 0.42 / 1.00
          </span>
        </div>
        <div className="flex items-center gap-6">
          <div className="flex items-center gap-2 transition-colors cursor-pointer">
            <span className="uppercase text-[9px]">Latency</span>
            <span className="text-emerald-500 font-bold">18ms</span>
          </div>
          <div className="h-4 w-[1px] opacity-50 bg-[var(--border-default)]"></div>
          <div className="flex items-center gap-2 group cursor-pointer">
            <div className="w-2 h-2 rounded-full bg-emerald-500 shadow-sm shadow-emerald-500/20 group-hover:scale-125 transition-transform"></div>
            <span className="uppercase tracking-[0.1em] transition-colors">
              Workspace Encrypted
            </span>
          </div>
          <div className="h-4 w-[1px] opacity-50 bg-[var(--border-default)]"></div>
          <span className="cursor-pointer transition-colors uppercase tracking-widest font-bold">
            UTF-8
          </span>
        </div>
      </footer>
      <Toaster position="top-center" />
    </div>
  );
};
export default App;


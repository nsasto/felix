import React, { useMemo, useState } from "react";
import {
  IconFileText,
  IconFileCode,
  IconKanban,
  IconPanelLeftDashed,
  IconPulse,
  IconSettings,
} from "./Icons";

export type SidebarView =
  | "projects"
  | "kanban"
  | "assets"
  | "orchestration"
  | "config"
  | "plan"
  | "settings";

type SidebarMode = "expanded" | "collapsed" | "hover";

interface SidebarProps {
  activeView: SidebarView;
  onChangeView: (view: SidebarView) => void;
  backendStatus: "unknown" | "connected" | "disconnected";
  projectName: string | null;
}

const NAV_ITEMS: Array<{
  id: SidebarView;
  label: string;
  icon: React.ReactNode;
  subtitle?: string;
}> = [
  {
    id: "projects",
    label: "Projects",
    icon: <IconFileText />,
    subtitle: "Workspace list",
  },
  {
    id: "kanban",
    label: "Board",
    icon: <IconKanban />,
    subtitle: "Requirements",
  },
  {
    id: "assets",
    label: "Specs",
    icon: <IconFileCode />,
    subtitle: "Documentation",
  },
  {
    id: "orchestration",
    label: "Orchestration",
    icon: <IconPulse />,
    subtitle: "Agent views",
  },
  {
    id: "config",
    label: "Config",
    icon: <IconSettings />,
    subtitle: "Settings",
  },
  {
    id: "plan",
    label: "README",
    icon: <IconFileCode />,
    subtitle: "Project plan",
  },
  {
    id: "settings",
    label: "Settings",
    icon: <IconSettings />,
    subtitle: "Preferences",
  },
];

const Sidebar: React.FC<SidebarProps> = ({
  activeView,
  onChangeView,
  backendStatus,
  projectName,
}) => {
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("expanded");
  const [hovered, setHovered] = useState(false);
  const [modeMenuOpen, setModeMenuOpen] = useState(false);

  const isExpanded = useMemo(() => {
    if (sidebarMode === "expanded") return true;
    if (sidebarMode === "collapsed") return false;
    return hovered;
  }, [sidebarMode, hovered]);

  const handleModeChange = (mode: SidebarMode) => {
    setSidebarMode(mode);
    setModeMenuOpen(false);
  };

  const MODE_OPTIONS: Array<{ key: SidebarMode; label: string }> = [
    { key: "expanded", label: "Expanded" },
    { key: "collapsed", label: "Collapsed" },
    { key: "hover", label: "Expand on hover" },
  ];

  return (
    <aside
      className={`sidebar ${isExpanded ? "sidebar-expanded" : "sidebar-collapsed"} sidebar-mode-${sidebarMode}`}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <div className="sidebar-nav">
        {NAV_ITEMS.map((item) => {
          const isActive = activeView === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onChangeView(item.id)}
              className={`sidebar-nav-item ${isActive ? "active" : ""}`}
            >
              <span className="sidebar-icon">{item.icon}</span>
              <div className="sidebar-labels">
                <span className="sidebar-label">{item.label}</span>
                {isExpanded && item.subtitle && (
                  <span className="sidebar-subtitle">{item.subtitle}</span>
                )}
              </div>
            </button>
          );
        })}
      </div>

      <div className="sidebar-footer">
        <div className="sidebar-project-status">
          <span className="sidebar-status-dot" />
          <div>
            <p className="text-[10px] uppercase tracking-[0.25em]">
              STATUS
            </p>
            <p className="text-xs font-semibold">
              {backendStatus === "connected"
                ? "Backend Online"
                : backendStatus === "disconnected"
                  ? "Backend Offline"
                  : "Connecting..."}
            </p>
            {isExpanded && projectName && (
              <p className="text-[10px] opacity-60 truncate">{projectName}</p>
            )}
          </div>
        </div>
        <div className="sidebar-mode-menu-container">
          <button
            onClick={() => setModeMenuOpen((prev) => !prev)}
            className="sidebar-mode-menu-btn"
            aria-haspopup="true"
            aria-expanded={modeMenuOpen}
          >
            <IconPanelLeftDashed className="w-4 h-4" />
          </button>
          {modeMenuOpen && (
            <div className="sidebar-mode-menu">
              <p className="sidebar-mode-menu-heading">Sidebar control</p>
              {MODE_OPTIONS.map((modeOption) => (
                <button
                  key={modeOption.key}
                  onClick={() => handleModeChange(modeOption.key)}
                  className={`sidebar-mode-menu-item ${
                    sidebarMode === modeOption.key ? "selected" : ""
                  }`}
                >
                  <span className="sidebar-mode-menu-dot" />
                  {modeOption.label}
                </button>
              ))}
            </div>
          )}
        </div>
        {isExpanded && (
          <div className="sidebar-user">
            <div className="sidebar-avatar">NS</div>
            <div>
              <p className="font-semibold">nsasto</p>
              <p className="text-[9px] opacity-60">nsasto@gmail.com</p>
            </div>
          </div>
        )}
      </div>
    </aside>
  );
};

export default Sidebar;

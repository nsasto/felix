import React, { useEffect, useMemo, useState } from "react";
import {
  FileText as IconFileText,
  FileCode as IconFileCode,
  Kanban as IconKanban,
  PanelLeftDashed as IconPanelLeftDashed,
  Activity as IconPulse,
  Settings as IconSettings,
} from "lucide-react";

export type SidebarView =
  | "projects"
  | "kanban"
  | "assets"
  | "orchestration"
  | "config"
  | "plan"
  | "settings";

export type SidebarMode = "expanded" | "collapsed" | "hover";

interface SidebarProps {
  activeView: SidebarView;
  onChangeView: (view: SidebarView) => void;
  backendStatus: "unknown" | "connected" | "disconnected";
  projectName: string | null;
  onModeChange?: (mode: SidebarMode) => void;
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
  onModeChange,
}) => {
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("expanded");
  const [hovered, setHovered] = useState(false);
  const [modeMenuOpen, setModeMenuOpen] = useState(false);

  const isExpanded = useMemo(() => {
    if (sidebarMode === "expanded") return true;
    if (sidebarMode === "collapsed") return false;
    return hovered;
  }, [sidebarMode, hovered]);

  useEffect(() => {
    const width = isExpanded ? "240px" : "72px";
    document.documentElement.style.setProperty("--sidebar-offset", width);
  }, [isExpanded]);

  const handleModeChange = (mode: SidebarMode) => {
    setSidebarMode(mode);
    setModeMenuOpen(false);
    onModeChange?.(mode);
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
              </div>
            </button>
          );
        })}
      </div>

      <div className="sidebar-footer">
        <div className="sidebar-project-status">
          <span className="sidebar-status-dot" />
          <div className="sidebar-status-content">
            <p className="sidebar-status-label">STATUS</p>
            <p className="sidebar-status-value">
              {backendStatus === "connected"
                ? "Backend Online"
                : backendStatus === "disconnected"
                  ? "Backend Offline"
                  : "Connecting..."}
            </p>
            {isExpanded && projectName && (
              <p className="sidebar-status-project">{projectName}</p>
            )}
          </div>
        </div>
      </div>
      <div className="sidebar-collapse-wrapper">
        <div className="sidebar-collapse-control">
          <button
            onClick={() => setModeMenuOpen((prev) => !prev)}
            className="sidebar-mode-menu-btn"
            aria-haspopup="true"
            aria-expanded={modeMenuOpen}
          >
            <IconPanelLeftDashed className="w-4 h-4" />
          </button>
          {modeMenuOpen && (
            <div
              className="sidebar-mode-menu sidebar-mode-menu-top"
              onMouseEnter={() => setModeMenuOpen(true)}
              onMouseLeave={() => setModeMenuOpen(false)}
            >
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
      </div>
    </aside>
  );
};

export default Sidebar;

import React from "react";
import {
  IconFileText,
  IconFileCode,
  IconKanban,
  IconPulse,
  IconSettings,
} from "./Icons";
import {
  Sidebar as ShadcnSidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
  useSidebar,
} from "./ui/sidebar";
import { cn } from "../lib/utils";

export type SidebarView =
  | "projects"
  | "kanban"
  | "assets"
  | "orchestration"
  | "config"
  | "plan"
  | "settings";

export type SidebarMode = "expanded" | "collapsed" | "hover";

interface SidebarProps extends React.ComponentProps<typeof ShadcnSidebar> {
  activeView: SidebarView;
  onChangeView: (view: SidebarView) => void;
  backendStatus: "unknown" | "connected" | "disconnected";
  projectName: string | null;
  // Deprecated props that we might still receive but don't strictly need with new Sidebar
  onModeChange?: (mode: SidebarMode) => void;
}

const NAV_ITEMS: Array<{
  id: SidebarView;
  label: string;
  icon: React.ElementType;
  subtitle?: string;
}> = [
  {
    id: "projects",
    label: "Projects",
    icon: IconFileText,
    subtitle: "Workspace list",
  },
  {
    id: "kanban",
    label: "Board",
    icon: IconKanban,
    subtitle: "Requirements",
  },
  {
    id: "assets",
    label: "Specs",
    icon: IconFileCode,
    subtitle: "Documentation",
  },
  {
    id: "orchestration",
    label: "Orchestration",
    icon: IconPulse,
    subtitle: "Agent views",
  },
  {
    id: "config",
    label: "Config",
    icon: IconSettings,
    subtitle: "Settings",
  },
  {
    id: "plan",
    label: "README",
    icon: IconFileCode,
    subtitle: "Project plan",
  },
  {
    id: "settings",
    label: "Settings",
    icon: IconSettings,
    subtitle: "Preferences",
  },
];

const Sidebar: React.FC<SidebarProps> = ({
  activeView,
  onChangeView,
  backendStatus,
  projectName,
  onModeChange,
  className,
  ...props
}) => {
  // We can access state from useSidebar if we need to sync it up,
  // but usually the Provider handles it.
  const { state } = useSidebar();

  // Sync mode change if parent needs it (polyfil-ish)
  React.useEffect(() => {
    if (onModeChange) {
      onModeChange(state === "collapsed" ? "collapsed" : "expanded");
    }
  }, [state, onModeChange]);

  return (
    <ShadcnSidebar collapsible="icon" className={className} {...props}>
      <SidebarHeader className="h-14 flex items-center px-4 border-b border-[var(--sidebar-border)]">
        <div className="flex items-center gap-2 overflow-hidden w-full">
          {/* We could put a logo here */}
          <div className="font-bold text-lg truncate text-[var(--brand-500)]">
            Felix
          </div>
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarMenu className="gap-2 p-2">
          {NAV_ITEMS.map((item) => {
            const isActive = activeView === item.id;
            const Icon = item.icon;

            return (
              <SidebarMenuItem key={item.id}>
                <SidebarMenuButton
                  isActive={isActive}
                  onClick={() => onChangeView(item.id)}
                  tooltip={item.label}
                  className={cn(
                    "transition-all duration-200 data-[active=true]:bg-[var(--brand-500)]/10 data-[active=true]:text-[var(--brand-600)]",
                  )}
                >
                  <Icon className="size-4" />
                  <span>{item.label}</span>
                </SidebarMenuButton>
              </SidebarMenuItem>
            );
          })}
        </SidebarMenu>
      </SidebarContent>

      <SidebarFooter className="p-4 border-t border-[var(--sidebar-border)]">
        <div className="flex items-center gap-3 overflow-hidden">
          <div className="relative flex h-2 w-2 shrink-0">
            <span
              className={cn(
                "animate-ping absolute inline-flex h-full w-full rounded-full opacity-75",
                backendStatus === "connected"
                  ? "bg-[var(--brand-500)]"
                  : "bg-[var(--destructive-500)]",
              )}
            ></span>
            <span
              className={cn(
                "relative inline-flex rounded-full h-2 w-2",
                backendStatus === "connected"
                  ? "bg-[var(--brand-500)]"
                  : "bg-[var(--destructive-500)]",
              )}
            ></span>
          </div>

          <div className="flex flex-col min-w-0 transition-all duration-200 group-data-[collapsible=icon]:opacity-0">
            <span className="text-[10px] uppercase tracking-wider font-bold text-[var(--text-muted)] leading-none mb-0.5">
              {backendStatus === "connected" ? "Online" : "Offline"}
            </span>
            {projectName && (
              <span className="text-xs truncate font-medium text-[var(--text-secondary)] leading-none">
                {projectName}
              </span>
            )}
          </div>
        </div>
      </SidebarFooter>
      <SidebarRail />
    </ShadcnSidebar>
  );
};

export default Sidebar;

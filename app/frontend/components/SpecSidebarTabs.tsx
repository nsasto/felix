import React from "react";
import { Requirement } from "../services/felixApi";
import { ValidationIssue, SyncableField } from "../utils/specParser";
import { CopilotSidebar } from "./copilot";
import { SpecMetadataPanel } from "./SpecMetadataPanel";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "./ui/tabs";
import {
  MessageSquare as IconMessageSquare,
  Settings as IconSettings,
  AlertCircle as IconAlertCircle,
} from "lucide-react";

interface SpecSidebarTabsProps {
  activeTab: "copilot" | "metadata";
  onTabChange: (tab: "copilot" | "metadata") => void;
  projectId: string;
  requirement: Requirement | null;
  allRequirements: Requirement[];
  specContent: string;
  validationIssues: ValidationIssue[];
  onInsertSpec: (spec: string) => void;
  onMetadataUpdate: (field: string, value: any) => Promise<void>;
  onSyncField: (
    direction: "markdown-to-metadata" | "metadata-to-markdown",
    field: string,
  ) => void;
  onOverviewChange: (content: string) => void;
  onDismissWarning: (field?: string) => void;
  isCopilotEnabled: boolean;
}

export function SpecSidebarTabs({
  activeTab,
  onTabChange,
  projectId,
  requirement,
  allRequirements,
  specContent,
  validationIssues,
  onInsertSpec,
  onMetadataUpdate,
  onSyncField,
  onOverviewChange,
  onDismissWarning,
  isCopilotEnabled,
}: SpecSidebarTabsProps) {
  const hasValidationIssues = validationIssues.length > 0;

  return (
    <Tabs
      value={activeTab}
      onValueChange={(value) => onTabChange(value as "copilot" | "metadata")}
      className="flex flex-col h-full bg-[var(--bg-surface-100)] border-l border-[var(--border)]"
    >
      <div className="flex-shrink-0 bg-[var(--bg-surface-100)] px-4">
        <TabsList variant="line">
          <TabsTrigger value="metadata" variant="line">
            <IconSettings className="w-4 h-4 mr-2" />
            Metadata
            {hasValidationIssues && activeTab !== "metadata" && (
              <span className="inline-flex items-center justify-center w-5 h-5 text-xs font-bold text-white bg-yellow-500 rounded-full ml-2">
                {validationIssues.length}
              </span>
            )}
          </TabsTrigger>
          {isCopilotEnabled && (
            <TabsTrigger value="copilot" variant="line">
              <IconMessageSquare className="w-4 h-4 mr-2" />
              Copilot
            </TabsTrigger>
          )}
        </TabsList>
      </div>

      <TabsContent value="metadata" className="flex-1 overflow-hidden m-0">
        <SpecMetadataPanel
          requirement={requirement}
          allRequirements={allRequirements}
          specContent={specContent}
          validationIssues={validationIssues}
          onMetadataUpdate={onMetadataUpdate}
          onSyncField={onSyncField}
          onOverviewChange={onOverviewChange}
          onDismissWarning={onDismissWarning}
        />
      </TabsContent>

      {isCopilotEnabled && (
        <TabsContent value="copilot" className="flex-1 overflow-hidden m-0">
          <CopilotSidebar projectId={projectId} onInsertSpec={onInsertSpec} />
        </TabsContent>
      )}
    </Tabs>
  );
}

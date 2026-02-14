import React, { useState } from "react";
import { Tabs, TabsList, TabsTrigger } from "./ui/tabs";
import { Button } from "./ui/button";

type PersonalTab =
  | "profile"
  | "preferences"
  | "notifications"
  | "api-keys"
  | "agent-defaults";

const PERSONAL_TABS: Array<{ id: PersonalTab; label: string }> = [
  { id: "profile", label: "Profile" },
  { id: "preferences", label: "Preferences" },
  { id: "notifications", label: "Notifications" },
  { id: "api-keys", label: "API Keys" },
  { id: "agent-defaults", label: "Personal Agent Defaults" },
];

interface PersonalSettingsScreenProps {
  onBack: () => void;
}

const PersonalSettingsScreen: React.FC<PersonalSettingsScreenProps> = ({
  onBack,
}) => {
  const [activeTab, setActiveTab] = useState<PersonalTab>("profile");

  return (
    <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
      <div className="bg-[var(--bg-base)] px-6 pt-8 pb-2">
        <div className="max-w-3xl mx-auto">
          <div className="flex items-start justify-between gap-6">
            <div>
              <h1 className="text-2xl font-semibold theme-text-primary">
                Personal Settings
              </h1>
              <p className="mt-2 text-xs theme-text-muted">
                Manage your profile and personal preferences
              </p>
            </div>
            <Button onClick={onBack} variant="ghost" size="sm">
              Back to Projects
            </Button>
          </div>
          <div className="mt-6 border-b border-[var(--border-default)]">
            <Tabs
              value={activeTab}
              onValueChange={(value) => setActiveTab(value as PersonalTab)}
            >
              <TabsList
                variant="line"
                className="w-full justify-start overflow-x-auto gap-6"
              >
                {PERSONAL_TABS.map((tab) => (
                  <TabsTrigger
                    key={tab.id}
                    value={tab.id}
                    variant="line"
                    className="text-sm font-medium"
                  >
                    {tab.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar p-8 theme-bg-base">
        <div className="max-w-3xl mx-auto">
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
            <h3 className="text-lg font-semibold">{PERSONAL_TABS.find((tab) => tab.id === activeTab)?.label}</h3>
            <p className="mt-2 text-xs theme-text-muted">
              This section is ready for personal settings content.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PersonalSettingsScreen;

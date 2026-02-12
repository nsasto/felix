import React from "react";
import SettingsScreen from "../SettingsScreen";

interface SettingsViewProps {
  projectId?: string;
  onBack: () => void;
}

export default function SettingsView({
  projectId,
  onBack,
}: SettingsViewProps) {
  return <SettingsScreen projectId={projectId} onBack={onBack} />;
}

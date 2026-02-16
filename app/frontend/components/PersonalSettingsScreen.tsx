import React, { useEffect, useState } from "react";
import {
  felixApi,
  FelixConfig,
  getCopilotApiKey,
  setCopilotApiKey,
  clearCopilotApiKey,
  UserProfileDetails,
  API_BASE_URL,
} from "../services/felixApi";
import { AlertTriangle, Check } from "lucide-react";
import { Alert, AlertDescription } from "./ui/alert";
import { Tabs, TabsList, TabsTrigger } from "./ui/tabs";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Textarea } from "./ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { Switch } from "./ui/switch";

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
  { id: "api-keys", label: "Felix Copilot" },
  { id: "agent-defaults", label: "Personal Agent Defaults" },
];

interface PersonalSettingsScreenProps {
  onBack: () => void;
}

const PersonalSettingsScreen: React.FC<PersonalSettingsScreenProps> = ({
  onBack,
}) => {
  const [activeTab, setActiveTab] = useState<PersonalTab>("profile");
  const [copilotApiKeyInput, setCopilotApiKeyInput] = useState<string>("");
  const [copilotApiKeyHasValue, setCopilotApiKeyHasValue] =
    useState<boolean>(false);
  const [copilotApiKeySaving, setCopilotApiKeySaving] = useState(false);
  const [copilotApiKeySaved, setCopilotApiKeySaved] = useState(false);
  const [copilotTestLoading, setCopilotTestLoading] = useState(false);
  const [copilotTestResult, setCopilotTestResult] = useState<{
    success: boolean;
    error?: string;
  } | null>(null);
  const [globalConfig, setGlobalConfig] = useState<FelixConfig | null>(null);
  const [copilotConfigSaving, setCopilotConfigSaving] = useState(false);
  const [copilotConfigError, setCopilotConfigError] = useState<string | null>(
    null,
  );
  const [profileDetails, setProfileDetails] =
    useState<UserProfileDetails | null>(null);
  const [profileForm, setProfileForm] = useState({
    display_name: "",
    full_name: "",
    title: "",
    bio: "",
    phone: "",
    location: "",
    website: "",
  });
  const [profileLoading, setProfileLoading] = useState(false);
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileSaved, setProfileSaved] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [avatarPreviewUrl, setAvatarPreviewUrl] = useState<string | null>(null);
  const apiHost = API_BASE_URL.replace(/\/api$/, "");

  useEffect(() => {
    const savedKey = getCopilotApiKey();
    setCopilotApiKeyHasValue(!!savedKey);
  }, []);

  const defaultCopilotConfig = {
    enabled: false,
    provider: "openai" as const,
    model: "gpt-4o",
    context_sources: {
      agents_md: true,
      learnings_md: true,
      prompt_md: true,
      requirements: true,
      other_specs: true,
    },
    features: {
      streaming: true,
      auto_suggest: true,
      context_aware: true,
    },
  };

  const modelOptions: Record<string, { value: string; label: string }[]> = {
    openai: [
      { value: "gpt-4o", label: "GPT-4o" },
      { value: "gpt-4-turbo", label: "GPT-4 Turbo" },
      { value: "gpt-3.5-turbo", label: "GPT-3.5 Turbo" },
    ],
    anthropic: [
      { value: "claude-3-5-sonnet-20241022", label: "Claude 3.5 Sonnet" },
      { value: "claude-3-opus-20240229", label: "Claude 3 Opus" },
      { value: "claude-3-haiku-20240307", label: "Claude 3 Haiku" },
    ],
  };

  useEffect(() => {
    if (activeTab !== "api-keys") {
      return;
    }
    const fetchConfig = async () => {
      try {
        const result = await felixApi.getUserConfig();
        setGlobalConfig(result.config);
      } catch (err) {
        setCopilotConfigError(
          err instanceof Error ? err.message : "Failed to load copilot settings",
        );
      }
    };
    fetchConfig();
  }, [activeTab]);

  useEffect(() => {
    if (activeTab !== "profile") {
      return;
    }
    const fetchProfile = async () => {
      setProfileLoading(true);
      setProfileError(null);
      try {
        const result = await felixApi.getUserProfileDetails();
        setProfileDetails(result);
        setProfileForm({
          display_name: result.display_name || "",
          full_name: result.full_name || "",
          title: result.title || "",
          bio: result.bio || "",
          phone: result.phone || "",
          location: result.location || "",
          website: result.website || "",
        });
        setAvatarPreviewUrl(
          result.avatar_url ? `${apiHost}${result.avatar_url}` : null,
        );
      } catch (err) {
        setProfileError(
          err instanceof Error ? err.message : "Failed to load profile",
        );
      } finally {
        setProfileLoading(false);
      }
    };
    fetchProfile();
  }, [activeTab]);

  useEffect(() => {
    if (copilotApiKeySaved) {
      const timeout = setTimeout(() => setCopilotApiKeySaved(false), 3000);
      return () => clearTimeout(timeout);
    }
  }, [copilotApiKeySaved]);

  useEffect(() => {
    if (profileSaved) {
      const timeout = setTimeout(() => setProfileSaved(false), 3000);
      return () => clearTimeout(timeout);
    }
  }, [profileSaved]);

  const handleProfileFieldChange = (field: string, value: string) => {
    setProfileForm((prev) => ({
      ...prev,
      [field]: value,
    }));
  };

  const handleSaveProfile = async () => {
    setProfileSaving(true);
    setProfileError(null);
    try {
      const result = await felixApi.updateUserProfileDetails(profileForm);
      setProfileDetails(result);
      setProfileSaved(true);
    } catch (err) {
      setProfileError(
        err instanceof Error ? err.message : "Failed to save profile",
      );
    } finally {
      setProfileSaving(false);
    }
  };

  const handleAvatarUpload = async (
    event: React.ChangeEvent<HTMLInputElement>,
  ) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setAvatarUploading(true);
    setAvatarError(null);
    try {
      const processedFile = await cropAvatarToSquare(file);
      const result = await felixApi.uploadUserAvatar(processedFile);
      setProfileDetails(result);
      setAvatarPreviewUrl(
        result.avatar_url
          ? `${apiHost}${result.avatar_url}?t=${Date.now()}`
          : null,
      );
    } catch (err) {
      setAvatarError(
        err instanceof Error ? err.message : "Failed to upload avatar",
      );
    } finally {
      setAvatarUploading(false);
      event.target.value = "";
    }
  };

  const handleRemoveAvatar = async () => {
    setAvatarUploading(true);
    setAvatarError(null);
    try {
      const result = await felixApi.deleteUserAvatar();
      setProfileDetails(result);
      setAvatarPreviewUrl(null);
    } catch (err) {
      setAvatarError(
        err instanceof Error ? err.message : "Failed to remove avatar",
      );
    } finally {
      setAvatarUploading(false);
    }
  };

  const cropAvatarToSquare = async (file: File): Promise<File> => {
    const imageUrl = URL.createObjectURL(file);
    try {
      const img = await new Promise<HTMLImageElement>((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error("Failed to load image"));
        image.src = imageUrl;
      });
      const size = Math.min(img.width, img.height);
      const sx = Math.floor((img.width - size) / 2);
      const sy = Math.floor((img.height - size) / 2);
      const canvas = document.createElement("canvas");
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext("2d");
      if (!ctx) {
        return file;
      }
      ctx.drawImage(img, sx, sy, size, size, 0, 0, size, size);
      const blob = await new Promise<Blob | null>((resolve) => {
        canvas.toBlob(
          (result) => resolve(result),
          file.type || "image/png",
          0.92,
        );
      });
      if (!blob) {
        return file;
      }
      return new File([blob], file.name, { type: file.type || "image/png" });
    } finally {
      URL.revokeObjectURL(imageUrl);
    }
  };

  const handleSaveCopilotApiKey = () => {
    if (!copilotApiKeyInput.trim()) return;
    setCopilotApiKeySaving(true);
    try {
      setCopilotApiKey(copilotApiKeyInput.trim());
      setCopilotApiKeyHasValue(true);
      setCopilotApiKeyInput("");
      setCopilotApiKeySaved(true);
      setCopilotTestResult(null);
    } finally {
      setCopilotApiKeySaving(false);
    }
  };

  const handleClearCopilotApiKey = () => {
    clearCopilotApiKey();
    setCopilotApiKeyHasValue(false);
    setCopilotApiKeyInput("");
    setCopilotTestResult(null);
  };

  const handleTestCopilotConnection = async () => {
    setCopilotTestLoading(true);
    setCopilotTestResult(null);

    try {
      const result = await felixApi.testCopilotConnection();
      setCopilotTestResult({
        success: result.success,
        error: result.error,
      });
    } catch (err) {
      setCopilotTestResult({
        success: false,
        error: err instanceof Error ? err.message : "Failed to test connection",
      });
    } finally {
      setCopilotTestLoading(false);
    }
  };

  const handleCopilotConfigChange = (field: string, value: any) => {
    if (!globalConfig) return;
    const currentCopilot = globalConfig.copilot || defaultCopilotConfig;
    const updated = {
      ...globalConfig,
      copilot: {
        ...currentCopilot,
        [field]: value,
      },
    };
    if (field === "provider") {
      const defaultModel =
        value === "openai"
          ? "gpt-4o"
          : value === "anthropic"
            ? "claude-3-5-sonnet-20241022"
            : "";
      updated.copilot = {
        ...updated.copilot,
        model: defaultModel,
      };
    }
    setGlobalConfig(updated);
  };

  const handleCopilotContextChange = (field: string, value: boolean) => {
    if (!globalConfig) return;
    const currentCopilot = globalConfig.copilot || defaultCopilotConfig;
    setGlobalConfig({
      ...globalConfig,
      copilot: {
        ...currentCopilot,
        context_sources: {
          ...currentCopilot.context_sources,
          [field]: value,
        },
      },
    });
  };

  const handleCopilotFeatureChange = (field: string, value: boolean) => {
    if (!globalConfig) return;
    const currentCopilot = globalConfig.copilot || defaultCopilotConfig;
    setGlobalConfig({
      ...globalConfig,
      copilot: {
        ...currentCopilot,
        features: {
          ...currentCopilot.features,
          [field]: value,
        },
      },
    });
  };

  const handleSaveCopilotConfig = async () => {
    if (!globalConfig) return;
    setCopilotConfigSaving(true);
    setCopilotConfigError(null);
    try {
      const result = await felixApi.updateUserConfig(globalConfig);
      setGlobalConfig(result.config);
    } catch (err) {
      setCopilotConfigError(
        err instanceof Error ? err.message : "Failed to save copilot settings",
      );
    } finally {
      setCopilotConfigSaving(false);
    }
  };

  const renderActiveTab = () => {
    if (activeTab === "api-keys") {
      const copilotConfig = globalConfig?.copilot || defaultCopilotConfig;
      const provider = copilotConfig.provider || "openai";
      const isEnabled = copilotConfig.enabled;
      return (
        <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6 space-y-5">
          <div>
            <h3 className="text-lg font-semibold">Copilot Settings</h3>
            <p className="mt-2 text-xs theme-text-muted">
              Personal copilot preferences and API key.
            </p>
          </div>

          <div className="border-t border-[var(--border-default)] pt-5 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h4 className="text-sm font-semibold">Copilot Preferences</h4>
                <p className="text-[11px] theme-text-muted">
                  Personal defaults for provider and model.
                </p>
                <span className="inline-flex mt-2 text-[9px] font-bold px-2 py-1 rounded-full border border-[var(--border-muted)] text-[var(--text-muted)] uppercase tracking-[0.18em]">
                  User Scope
                </span>
              </div>
              <Button
                onClick={handleSaveCopilotConfig}
                disabled={!globalConfig || copilotConfigSaving}
                size="sm"
                className="text-[10px] font-bold uppercase"
              >
                {copilotConfigSaving ? "Saving..." : "Save Preferences"}
              </Button>
            </div>

            {copilotConfigError && (
              <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                <AlertDescription className="text-xs text-[var(--destructive-500)]">
                  {copilotConfigError}
                </AlertDescription>
              </Alert>
            )}

            <div className="theme-bg-base border border-[var(--border-default)] rounded-xl p-4 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <label className="block text-sm font-bold theme-text-secondary">
                    Enable Copilot
                  </label>
                  <p className="text-[11px] theme-text-muted mt-1">
                    Toggle copilot features across your workspace.
                  </p>
                </div>
                <Switch
                  checked={isEnabled}
                  onCheckedChange={(checked) =>
                    handleCopilotConfigChange("enabled", checked)
                  }
                  aria-label="Enable Copilot"
                />
              </div>

              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Provider
                </label>
                <Select
                  value={provider}
                  onValueChange={(value) =>
                    handleCopilotConfigChange("provider", value)
                  }
                  disabled={!isEnabled}
                >
                  <SelectTrigger aria-label="Provider">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="openai">OpenAI</SelectItem>
                    <SelectItem value="anthropic">Anthropic</SelectItem>
                    <SelectItem value="custom">Custom</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Model
                </label>
                {provider === "custom" ? (
                  <Input
                    type="text"
                    value={copilotConfig.model}
                    onChange={(e) =>
                      handleCopilotConfigChange("model", e.target.value)
                    }
                    disabled={!isEnabled}
                    placeholder="Enter model name"
                    className="font-mono"
                  />
                ) : (
                  <Select
                    value={copilotConfig.model}
                    onValueChange={(value) =>
                      handleCopilotConfigChange("model", value)
                    }
                    disabled={!isEnabled}
                  >
                    <SelectTrigger aria-label="Model">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {modelOptions[provider]?.map((option) => (
                        <SelectItem key={option.value} value={option.value}>
                          {option.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </div>
            </div>
          </div>

          <div className="border-t border-[var(--border-default)] pt-5 space-y-4">
            <div>
              <h4 className="text-sm font-semibold">Copilot Defaults</h4>
              <p className="text-[11px] theme-text-muted">
                Context sources and feature toggles used by Copilot.
              </p>
            </div>

            <div className="theme-bg-base border border-[var(--border-default)] rounded-xl p-4">
              <label className="block text-xs font-bold theme-text-tertiary mb-3">
                Context Sources
              </label>
              <div className="space-y-3">
                {[
                  {
                    key: "agents_md",
                    label: "AGENTS.md",
                    description: "Operational instructions and validation",
                  },
                  {
                    key: "learnings_md",
                    label: "LEARNINGS.md",
                    description: "Technical knowledge and common pitfalls",
                  },
                  {
                    key: "prompt_md",
                    label: "prompt.md",
                    description: "Spec writing conventions",
                  },
                  {
                    key: "requirements",
                    label: "requirements",
                    description: "Project dependencies and status",
                  },
                  {
                    key: "other_specs",
                    label: "Other specs",
                    description: "Pattern consistency from existing specs",
                  },
                ].map((source) => (
                  <div
                    key={source.key}
                    className="flex items-center justify-between py-1"
                  >
                    <div>
                      <span className="text-sm theme-text-secondary">
                        {source.label}
                      </span>
                      <p className="text-[10px] theme-text-muted">
                        {source.description}
                      </p>
                    </div>
                    <Switch
                      checked={(copilotConfig.context_sources as any)[source.key]}
                      onCheckedChange={(checked) =>
                        handleCopilotContextChange(source.key, checked)
                      }
                      disabled={!isEnabled}
                    />
                  </div>
                ))}
              </div>
            </div>

            <div className="theme-bg-base border border-[var(--border-default)] rounded-xl p-4">
              <label className="block text-xs font-bold theme-text-tertiary mb-3">
                Features
              </label>
              <div className="space-y-3">
                {[
                  {
                    key: "streaming",
                    label: "Streaming Responses",
                    description:
                      "Enables token-by-token streaming for faster feedback",
                  },
                  {
                    key: "auto_suggest",
                    label: "Auto-suggest Spec Titles",
                    description: "Suggests titles based on your input",
                  },
                  {
                    key: "context_aware",
                    label: "Context-aware Completions",
                    description: "Uses project context in responses",
                  },
                ].map((feature) => (
                  <div
                    key={feature.key}
                    className="flex items-center justify-between py-1"
                  >
                    <div>
                      <span className="text-sm theme-text-secondary">
                        {feature.label}
                      </span>
                      <p className="text-[10px] theme-text-muted">
                        {feature.description}
                      </p>
                    </div>
                    <Switch
                      checked={(copilotConfig.features as any)[feature.key]}
                      onCheckedChange={(checked) =>
                        handleCopilotFeatureChange(feature.key, checked)
                      }
                      disabled={!isEnabled}
                    />
                  </div>
                ))}
              </div>
            </div>
          </div>

          <div className="border-t border-[var(--border-default)] pt-5 space-y-4">
            <div>
              <h4 className="text-sm font-semibold">Felix Copilot</h4>
              <p className="mt-1 text-[11px] theme-text-muted">
                Stored locally in your browser. This key is never sent to Felix.
              </p>
              <p className="mt-2 text-[10px] theme-text-muted">
                These defaults only affect Copilot behavior on this device.
              </p>
            </div>

            {copilotApiKeyHasValue && (
              <Alert className="border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]">
                <AlertDescription className="flex items-center gap-2 text-[var(--brand-500)]">
                  <Check className="w-4 h-4" />
                  <span className="text-xs">API key configured</span>
                  <Button
                    onClick={handleClearCopilotApiKey}
                    variant="ghost"
                    size="sm"
                    className="ml-auto text-[10px] text-[var(--destructive-500)]"
                  >
                    Clear
                  </Button>
                </AlertDescription>
              </Alert>
            )}

            <div className="space-y-3">
              <label className="block text-xs font-bold theme-text-tertiary mb-2">
                {copilotApiKeyHasValue ? "Update API Key" : "Enter API Key"}
              </label>
              <div className="flex gap-2">
                <Input
                  type="password"
                  value={copilotApiKeyInput}
                  onChange={(e) => setCopilotApiKeyInput(e.target.value)}
                  placeholder={
                    copilotApiKeyHasValue ? "****************" : "sk-proj-..."
                  }
                  className="flex-1 font-mono"
                />
                <Button
                  onClick={handleSaveCopilotApiKey}
                  disabled={!copilotApiKeyInput.trim() || copilotApiKeySaving}
                  size="sm"
                  className="uppercase"
                >
                  {copilotApiKeySaving ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Saving...
                    </>
                  ) : (
                    "Save"
                  )}
                </Button>
              </div>
              <p className="text-[10px] theme-text-muted">
                Your API key is stored in localStorage and used for direct calls.
              </p>
              {copilotApiKeySaved && (
                <div className="flex items-center gap-2 text-xs text-[var(--brand-500)]">
                  <Check className="w-4 h-4" />
                  <span>API key saved successfully</span>
                </div>
              )}
            </div>

            <div className="flex items-center gap-3">
              <Button
                onClick={handleTestCopilotConnection}
                disabled={copilotTestLoading || !copilotApiKeyHasValue}
                size="sm"
                className="uppercase"
              >
                {copilotTestLoading ? (
                  <>
                    <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Testing...
                  </>
                ) : (
                  "Test Connection"
                )}
              </Button>

              {copilotTestResult && (
                <div
                  className={`flex items-center gap-2 text-xs ${copilotTestResult.success ? "text-[var(--status-success)]" : "text-[var(--status-error)]"}`}
                >
                  {copilotTestResult.success ? (
                    <>
                      <span>OK</span>
                      <span>Connected successfully</span>
                    </>
                  ) : (
                    <>
                      <span>Error</span>
                      <span>
                        {copilotTestResult.error || "Connection failed"}
                      </span>
                    </>
                  )}
                </div>
              )}
            </div>

            {!copilotApiKeyHasValue && (
              <Alert className="border-[var(--warning-500)]/30 bg-[var(--warning-500)]/10 text-[var(--warning-500)]">
                <AlertDescription className="flex items-start gap-3 text-[var(--warning-500)]/80">
                  <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
                  <p className="text-xs">
                    Add a key to enable Copilot. You can rotate it anytime.
                  </p>
                </AlertDescription>
              </Alert>
            )}
          </div>
        </div>
      );
    }

    if (activeTab === "profile") {
      return (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-semibold">Profile Details</h3>
              <p className="mt-2 text-xs theme-text-muted">
                Update your personal information and profile image.
              </p>
            </div>
            <Button
              onClick={handleSaveProfile}
              disabled={profileSaving}
              size="sm"
              className="text-[10px] font-bold uppercase"
            >
              {profileSaving ? "Saving..." : "Save Profile"}
            </Button>
          </div>

          {profileError && (
            <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="text-xs text-[var(--destructive-500)]">
                {profileError}
              </AlertDescription>
            </Alert>
          )}

          {profileSaved && (
            <div className="flex items-center gap-2 text-xs text-[var(--status-success)]">
              <Check className="w-4 h-4" />
              Profile updated
            </div>
          )}

          <div className="grid gap-6 lg:grid-cols-[240px_minmax(0,1fr)]">
            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5 space-y-4">
              <div className="flex items-center justify-center">
                <div className="w-28 h-28 rounded-full overflow-hidden border border-[var(--border-muted)] bg-[var(--bg-surface)]">
                  {avatarPreviewUrl ? (
                    <img
                      src={avatarPreviewUrl}
                      alt="Profile"
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-xs theme-text-muted">
                      No Image
                    </div>
                  )}
                </div>
              </div>
              <div className="space-y-2 text-center">
                <label className="inline-flex items-center justify-center">
                  <input
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={handleAvatarUpload}
                    disabled={avatarUploading}
                  />
                  <span className="px-3 py-2 text-[10px] font-bold uppercase rounded-md border border-[var(--border-muted)] cursor-pointer">
                    {avatarUploading ? "Uploading..." : "Upload Photo"}
                  </span>
                </label>
                {avatarPreviewUrl && (
                  <Button
                    onClick={handleRemoveAvatar}
                    variant="ghost"
                    size="sm"
                    className="text-[10px] text-[var(--destructive-500)]"
                    disabled={avatarUploading}
                  >
                    Remove
                  </Button>
                )}
                {avatarError && (
                  <p className="text-[10px] text-[var(--destructive-500)]">
                    {avatarError}
                  </p>
                )}
                <p className="text-[9px] theme-text-muted">
                  JPG or PNG, up to 2MB. Auto-cropped to square.
                </p>
              </div>
            </div>

            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6 space-y-4">
              <div className="grid md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Display Name
                  </label>
                  <Input
                    value={profileForm.display_name}
                    onChange={(e) =>
                      handleProfileFieldChange("display_name", e.target.value)
                    }
                    placeholder="How you appear in Felix"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Full Name
                  </label>
                  <Input
                    value={profileForm.full_name}
                    onChange={(e) =>
                      handleProfileFieldChange("full_name", e.target.value)
                    }
                    placeholder="Your full name"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Title
                  </label>
                  <Input
                    value={profileForm.title}
                    onChange={(e) =>
                      handleProfileFieldChange("title", e.target.value)
                    }
                    placeholder="Role or title"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Email
                  </label>
                  <Input
                    value={profileDetails?.email || ""}
                    disabled
                    placeholder="Email"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Phone
                  </label>
                  <Input
                    value={profileForm.phone}
                    onChange={(e) =>
                      handleProfileFieldChange("phone", e.target.value)
                    }
                    placeholder="+1 555 123 4567"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Location
                  </label>
                  <Input
                    value={profileForm.location}
                    onChange={(e) =>
                      handleProfileFieldChange("location", e.target.value)
                    }
                    placeholder="City, Country"
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Website
                  </label>
                  <Input
                    value={profileForm.website}
                    onChange={(e) =>
                      handleProfileFieldChange("website", e.target.value)
                    }
                    placeholder="https://"
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Bio
                  </label>
                  <Textarea
                    value={profileForm.bio}
                    onChange={(e) =>
                      handleProfileFieldChange("bio", e.target.value)
                    }
                    placeholder="A short introduction"
                    rows={4}
                  />
                </div>
              </div>

              {profileLoading && (
                <p className="text-xs theme-text-muted">Loading profile...</p>
              )}
            </div>
          </div>

          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6 space-y-4">
            <div>
              <h4 className="text-sm font-semibold">Password Management</h4>
              <p className="text-[11px] theme-text-muted mt-1">
                Managed by your identity provider. Updates are not available in
                this environment.
              </p>
            </div>
            <div className="grid md:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Current Password
                </label>
                <Input type="password" disabled placeholder="********" />
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  New Password
                </label>
                <Input type="password" disabled placeholder="********" />
              </div>
              <div className="md:col-span-2">
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Confirm Password
                </label>
                <Input type="password" disabled placeholder="********" />
              </div>
            </div>
            <Button disabled size="sm" className="text-[10px] font-bold uppercase">
              Update Password
            </Button>
          </div>
        </div>
      );
    }

    const label = PERSONAL_TABS.find((tab) => tab.id === activeTab)?.label;
    return (
      <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
        <h3 className="text-lg font-semibold">{label}</h3>
        <p className="mt-2 text-xs theme-text-muted">
          This section is ready for personal settings content.
        </p>
      </div>
    );
  };

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
                className="w-full justify-start flex-wrap gap-6"
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
        <div className="max-w-3xl mx-auto">{renderActiveTab()}</div>
      </div>
    </div>
  );
};

export default PersonalSettingsScreen;

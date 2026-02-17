/**
 * Felix Backend API Service
 * Handles communication with the Felix backend server.
 */

export const API_BASE_URL = "http://localhost:8080/api";
const ACTIVE_ORG_STORAGE_KEY = "felix_active_org_id";

// --- Types matching backend models ---

export interface Project {
  id: string;
  path: string;
  name: string | null;
  git_repo: string | null;
  registered_at: string;
}

export interface ProjectDetails extends Project {
  has_specs: boolean;
  has_plan: boolean;
  has_requirements: boolean;
  spec_count: number;
  status: string | null;
}

export interface ProjectRegisterRequest {
  path: string;
  name?: string;
}

export interface ProjectUpdateRequest {
  name?: string;
  path?: string;
  git_repo?: string | null;
}

export interface SpecFile {
  filename: string;
  path: string;
}

export interface Requirement {
  id: string;
  code?: string | null;
  uuid?: string | null;
  title: string;
  spec_path: string;
  status: string;
  priority: string;
  tags: string[];
  depends_on: string[];
  updated_at: string;
  last_run_id?: string;
  // Plan status fields (enriched by backend)
  has_plan?: boolean;
  plan_path?: string | null;
  plan_modified_at?: string | null;
  spec_modified_at?: string | null;
}

export interface RequirementsData {
  requirements: Requirement[];
}

export interface RunInfo {
  run_id: string;
  requirement_id: string | null;
  started_at: string;
  artifacts: string[];
}

export type RunStatus = "running" | "completed" | "failed" | "stopped";

export interface RunHistoryEntry {
  run_id: string;
  project_id: string;
  pid: number;
  status: RunStatus;
  started_at: string;
  ended_at: string | null;
  exit_code: number | null;
  project_path: string;
  error_message: string | null;
  requirement_id: string | null;
  agent_name: string | null;
}

export interface RunHistoryResponse {
  project_id: string;
  runs: RunHistoryEntry[];
  total: number;
}

export interface RunArtifactContent {
  run_id: string;
  filename: string;
  content: string;
  size: number;
}

export interface ApiKeyInfo {
  id: string;
  project_id: string;
  name: string | null;
  created_at: string;
  last_used_at: string | null;
  expires_at: string | null;
}

export interface ApiKeyCreated {
  id: string;
  project_id: string;
  name: string | null;
  key: string; // Plain-text key (shown only once)
  created_at: string;
  expires_at: string | null;
}

export interface ApiKeyListResponse {
  keys: ApiKeyInfo[];
  count: number;
}

export interface ApiKeyCreateRequest {
  name?: string;
  expires_days?: number;
}

export interface AgentStatus {
  running: boolean;
  pid: number | null;
  started_at: string | null;
  current_run_id: string | null;
}

export interface UserProfile {
  user_id: string;
  email: string | null;
  organization: string | null;
  org_slug: string | null;
  org_id: string | null;
  role: string;
  avatar_url: string | null;
}

export interface UserProfileDetails {
  user_id: string;
  email: string | null;
  display_name: string | null;
  full_name: string | null;
  title: string | null;
  bio: string | null;
  phone: string | null;
  location: string | null;
  website: string | null;
  avatar_url: string | null;
  updated_at: string | null;
}

export interface OrganizationSummary {
  id: string;
  name: string;
  slug: string;
  role: string;
}

// --- Agent Registry Types (for S-0013: Agent Settings Registry) ---

export interface AgentEntry {
  agent_id: string;
  agent_name: string;
  pid: number;
  hostname: string;
  status: "active" | "inactive" | "stopped" | "stale" | "not-started";
  current_run_id: string | null;
  started_at: string | null;
  last_heartbeat: string | null;
  stopped_at: string | null;
  // Workflow stage fields (S-0030: Agent Workflow Visualization)
  current_workflow_stage?: string | null;
  workflow_stage_timestamp?: string | null;
}

export interface AgentRegistryResponse {
  agents: Record<string, AgentEntry>;
}

export interface AgentRegistration {
  agent_id: string;
  agent_name: string;
  pid: number;
  hostname: string;
  started_at?: string;
}

export interface AgentStatusResponse {
  agent_id: string;
  agent_name: string;
  status: string;
  pid: number;
  hostname: string;
  current_run_id: string | null;
  started_at: string | null;
  last_heartbeat: string | null;
  stopped_at: string | null;
}

// --- Requirement Status Types (for S-0006: Spec Edit Safety) ---

export interface RequirementStatusResponse {
  id: string;
  status: string;
  title: string;
  has_plan: boolean;
  plan_path: string | null;
  plan_modified_at: string | null;
  spec_modified_at: string | null;
}

export interface RequirementContentResponse {
  content: string;
}

export interface FileContentResponse {
  content: string;
  path: string;
}

export interface PlanInfo {
  requirement_id: string;
  exists: boolean;
  plan_path: string | null;
  run_id: string | null;
  modified_at: string | null;
  content_preview: string | null;
}

export interface PlanDeleteResponse {
  message: string;
  requirement_id: string;
  deleted_path: string | null;
}

// --- Config Types ---

export interface ExecutorConfig {
  mode: string;
  max_iterations: number;
  default_mode: string;
  auto_transition: boolean;
}

export interface AgentConfig {
  name?: string; // Agent name identifier (added in S-0013)
  executable: string;
  args: string[];
  working_directory: string;
  environment: Record<string, string>;
}

export interface PathsConfig {
  specs: string;
  plan: string;
  agents: string;
  runs: string;
}

export interface BackpressureConfig {
  enabled: boolean;
  commands: string[];
  max_retries?: number;
}

export interface UIConfig {
  // Currently empty - theme is now a local-only setting
}

// --- Copilot Config Types (for S-0016: Felix Copilot Settings) ---

export interface CopilotContextSources {
  agents_md: boolean;
  learnings_md: boolean;
  prompt_md: boolean;
  requirements: boolean;
  other_specs: boolean;
}

export interface CopilotFeatures {
  streaming: boolean;
  auto_suggest: boolean;
  context_aware: boolean;
}

export interface CopilotConfig {
  enabled: boolean;
  provider: "openai" | "anthropic" | "custom";
  model: string;
  context_sources: CopilotContextSources;
  features: CopilotFeatures;
}

export interface CopilotTestResult {
  success: boolean;
  error?: string;
  provider?: string;
  model?: string;
}

export interface CopilotStatus {
  enabled: boolean;
  configured: boolean;
  api_key_present: boolean;
  provider: string | null;
  model: string | null;
}

// --- Agent Configuration Types (for S-0020: Consolidate Agent Settings) ---

/**
 * Agent configuration entry representing a saved agent preset.
 * Different from AgentEntry which represents a running/registered agent instance.
 */
export interface AgentConfiguration {
  id: string;
  name: string;
  executable: string;
  args: string[];
  working_directory: string;
  environment: Record<string, string>;
  adapter?: string;
  model?: string | null;
  description?: string | null;
}

export interface AgentConfigurationCreate {
  name: string;
  executable?: string;
  args?: string[];
  working_directory?: string;
  environment?: Record<string, string>;
}

export interface AgentConfigurationUpdate {
  name?: string;
  executable?: string;
  args?: string[];
  working_directory?: string;
  environment?: Record<string, string>;
}

export interface AgentConfigurationsResponse {
  agents: AgentConfiguration[];
  active_agent_id: string | null;
}

export interface AgentConfigurationResponse {
  agent: AgentConfiguration;
  message: string;
}

export interface SetActiveAgentRequest {
  agent_id: string;
}

export interface SetActiveAgentResponse {
  agent_id: string;
  message: string;
}

// --- Agent Config List Types (for S-0021: Agent Orchestration Enhancement) ---

/**
 * Agent configuration entry from the database as returned by /api/agents/config.
 * Used by the Agent Orchestration Dashboard to display all available agents.
 */
export interface AgentConfigEntry {
  id: string;
  name: string;
  executable: string;
  args: string[];
  working_directory: string;
  environment: Record<string, string>;
  adapter?: string;
  model?: string | null;
  description?: string | null;
}

export interface AgentConfigsListResponse {
  agents: AgentConfigEntry[];
}

// --- Workflow Configuration Types (for S-0030: Agent Workflow Visualization) ---

/**
 * A single workflow stage definition from workflow.json
 */
export interface WorkflowStage {
  id: string;
  name: string;
  icon: string;
  description: string;
  order: number;
  conditional?: string;
}

/**
 * Response containing workflow configuration for the visualization panel
 */
export interface WorkflowConfigResponse {
  version: string;
  layout: "horizontal" | "vertical";
  stages: WorkflowStage[];
}

/**
 * Merged agent combining configuration from the database with runtime status from the registry.
 * Used by the Agent Orchestration Dashboard to display complete agent information.
 */
export interface MergedAgent {
  // From agent profiles (configuration)
  id: string;
  name: string;
  executable: string;
  args: string[];
  working_directory: string;
  environment: Record<string, string>;
  adapter?: string;
  model?: string | null;
  description?: string | null;
  // From runtime registry (or derived status)
  status: "not-started" | "active" | "stale" | "inactive" | "stopped";
  // Runtime data (optional - only present if agent has been started)
  pid?: number;
  hostname?: string;
  current_run_id?: string | null;
  last_heartbeat?: string | null;
  started_at?: string | null;
  stopped_at?: string | null;
  // Workflow stage fields (S-0030: Agent Workflow Visualization)
  current_workflow_stage?: string | null;
  workflow_stage_timestamp?: string | null;
}

// --- Copilot Chat Types (for S-0017: Felix Copilot Chat Assistant) ---

export type AvatarState =
  | "idle"
  | "listening"
  | "thinking"
  | "speaking"
  | "error";

export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  timestamp: Date;
}

export interface CopilotChatRequest {
  message: string;
  history: Array<{ role: string; content: string }>;
  project_path?: string;
}

export interface CopilotStreamEvent {
  token?: string;
  avatar_state?: AvatarState;
  done?: boolean;
  error?: string;
}

/**
 * Interface for controlling the copilot chat stream
 */
export interface CopilotStreamController {
  /** Subscribe to stream events */
  onEvent: (callback: (event: CopilotStreamEvent) => void) => void;
  /** Subscribe to errors */
  onError: (callback: (error: Error) => void) => void;
  /** Subscribe to completion */
  onComplete: (callback: () => void) => void;
  /** Cancel the stream */
  cancel: () => void;
}

export interface FelixConfig {
  version: string;
  executor: ExecutorConfig;
  agent: AgentConfig;
  paths: PathsConfig;
  backpressure: BackpressureConfig;
  ui: UIConfig;
  copilot?: CopilotConfig;
}

export interface ConfigContent {
  config: FelixConfig;
  path: string;
}

export interface ScopedConfigContent {
  scope_type: "org" | "user" | "project";
  scope_id: string;
  config: FelixConfig;
}

// --- API Functions ---

// Copilot API Key localStorage key (for S-0022: Copilot API Key Storage)
const COPILOT_API_KEY_STORAGE_KEY = "felix_copilot_api_key";

class FelixApiService {
  private baseUrl: string;
  private orgId: string | null;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
    try {
      this.orgId = localStorage.getItem(ACTIVE_ORG_STORAGE_KEY);
    } catch {
      this.orgId = null;
    }
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`;
    const baseHeaders: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (this.orgId) {
      baseHeaders["X-Felix-Org-Id"] = this.orgId;
    }
    const response = await fetch(url, {
      ...options,
      headers: {
        ...baseHeaders,
        ...options.headers,
      },
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(
        errorData.detail || `HTTP ${response.status}: ${response.statusText}`,
      );
    }

    return response.json();
  }

  // --- Project Endpoints ---

  async listProjects(): Promise<Project[]> {
    return this.request<Project[]>("/projects");
  }

  async getProject(projectId: string): Promise<ProjectDetails> {
    return this.request<ProjectDetails>(`/projects/${projectId}`);
  }

  async registerProject(request: ProjectRegisterRequest): Promise<Project> {
    return this.request<Project>("/projects/register", {
      method: "POST",
      body: JSON.stringify(request),
    });
  }

  async unregisterProject(projectId: string): Promise<void> {
    await this.request<{ message: string }>(`/projects/${projectId}`, {
      method: "DELETE",
    });
  }

  async updateProject(
    projectId: string,
    request: ProjectUpdateRequest,
  ): Promise<Project> {
    return this.request<Project>(`/projects/${projectId}`, {
      method: "PUT",
      body: JSON.stringify(request),
    });
  }

  // --- Spec Endpoints ---

  async listSpecs(projectId: string): Promise<SpecFile[]> {
    return this.request<SpecFile[]>(`/projects/${projectId}/specs`);
  }

  async getSpec(
    projectId: string,
    filename: string,
  ): Promise<{ content: string }> {
    return this.request<{ content: string }>(
      `/projects/${projectId}/specs/${filename}`,
    );
  }

  async updateSpec(
    projectId: string,
    filename: string,
    content: string,
  ): Promise<void> {
    await this.request<{ message: string }>(
      `/projects/${projectId}/specs/${filename}`,
      {
        method: "PUT",
        body: JSON.stringify({ content }),
      },
    );
  }

  async createSpec(
    projectId: string,
    filename: string,
    content: string,
  ): Promise<{ filename: string; content: string }> {
    return this.request<{ filename: string; content: string }>(
      `/projects/${projectId}/specs`,
      {
        method: "POST",
        body: JSON.stringify({ filename, content }),
      },
    );
  }

  // --- Plan Endpoints ---

  async getPlan(projectId: string): Promise<{ content: string }> {
    return this.request<{ content: string }>(`/projects/${projectId}/plan`);
  }

  async updatePlan(projectId: string, content: string): Promise<void> {
    await this.request<{ message: string }>(`/projects/${projectId}/plan`, {
      method: "PUT",
      body: JSON.stringify({ content }),
    });
  }

  // --- Requirements Endpoints ---

  async getRequirements(projectId: string): Promise<RequirementsData> {
    return this.request<RequirementsData>(
      `/projects/${projectId}/requirements`,
    );
  }

  async updateRequirementMetadata(
    projectId: string,
    requirementId: string,
    field: string,
    value: any,
  ): Promise<Requirement> {
    return this.request<Requirement>(
      `/projects/${projectId}/requirements/${requirementId}`,
      {
        method: "PATCH",
        body: JSON.stringify({ field, value }),
      },
    );
  }

  // --- Run Endpoints ---

  async listRuns(
    projectId: string,
    filters?: {
      requirementId?: string;
      agentName?: string;
      status?: string[];
      startDate?: string;
      endDate?: string;
    },
  ): Promise<RunHistoryResponse> {
    const params = new URLSearchParams();
    if (filters?.requirementId) {
      params.append("requirement_id", filters.requirementId);
    }
    if (filters?.agentName) {
      params.append("agent_name", filters.agentName);
    }
    if (filters?.status && filters.status.length > 0) {
      params.append("status", filters.status.join(","));
    }
    if (filters?.startDate) {
      params.append("start_date", filters.startDate);
    }
    if (filters?.endDate) {
      params.append("end_date", filters.endDate);
    }
    const queryString = params.toString();
    return this.request<RunHistoryResponse>(
      `/projects/${projectId}/runs${queryString ? `?${queryString}` : ""}`,
    );
  }

  async startRun(projectId: string): Promise<{ run_id: string; pid: number }> {
    return this.request<{ run_id: string; pid: number }>(
      `/projects/${projectId}/runs/start`,
      {
        method: "POST",
      },
    );
  }

  async stopRun(projectId: string): Promise<void> {
    await this.request<{ message: string }>(
      `/projects/${projectId}/runs/stop`,
      {
        method: "POST",
      },
    );
  }

  async getAgentStatus(projectId: string): Promise<AgentStatus> {
    return this.request<AgentStatus>(`/projects/${projectId}/runs/status`);
  }

  async getRunArtifact(
    projectId: string,
    runId: string,
    filename: string,
  ): Promise<RunArtifactContent> {
    return this.request<RunArtifactContent>(
      `/projects/${projectId}/runs/${runId}/artifacts/${filename}`,
    );
  }

  // --- Config Endpoints ---

  async getConfig(projectId: string): Promise<ConfigContent> {
    return this.request<ConfigContent>(`/projects/${projectId}/config`);
  }

  async updateConfig(
    projectId: string,
    config: FelixConfig,
  ): Promise<ConfigContent> {
    return this.request<ConfigContent>(`/projects/${projectId}/config`, {
      method: "PUT",
      body: JSON.stringify({ config }),
    });
  }

  // --- Requirement Status Endpoints (for S-0006: Spec Edit Safety) ---

  async getRequirementStatus(
    projectId: string,
    requirementId: string,
  ): Promise<RequirementStatusResponse> {
    return this.request<RequirementStatusResponse>(
      `/projects/${projectId}/requirements/${requirementId}/status`,
    );
  }

  async updateRequirementStatus(
    projectId: string,
    requirementId: string,
    status: string,
  ): Promise<RequirementStatusResponse> {
    return this.request<RequirementStatusResponse>(
      `/projects/${projectId}/requirements/${requirementId}/status`,
      {
        method: "PUT",
        body: JSON.stringify({ status }),
      },
    );
  }

  async getRequirementContent(
    projectId: string,
    requirementId: string,
  ): Promise<RequirementContentResponse> {
    return this.request<RequirementContentResponse>(
      `/projects/${projectId}/requirements/${requirementId}/content`,
    );
  }

  async getPlanInfo(
    projectId: string,
    requirementId: string,
  ): Promise<PlanInfo> {
    return this.request<PlanInfo>(
      `/projects/${projectId}/plans/${requirementId}`,
    );
  }

  async deletePlan(
    projectId: string,
    requirementId: string,
  ): Promise<PlanDeleteResponse> {
    return this.request<PlanDeleteResponse>(
      `/projects/${projectId}/plans/${requirementId}`,
      {
        method: "DELETE",
      },
    );
  }

  // --- File Endpoints ---

  async getProjectFile(
    projectId: string,
    filename: "README.md" | "CONTEXT.md" | "AGENTS.md",
  ): Promise<FileContentResponse> {
    return this.request<FileContentResponse>(
      `/projects/${projectId}/files/${filename}`,
    );
  }

  async updateProjectFile(
    projectId: string,
    filename: "README.md" | "CONTEXT.md" | "AGENTS.md",
    content: string,
  ): Promise<{ message: string; path: string }> {
    return this.request<{ message: string; path: string }>(
      `/projects/${projectId}/files/${filename}`,
      {
        method: "PUT",
        body: JSON.stringify({ content }),
      },
    );
  }

  // --- Agent Registry Endpoints (for S-0013: Agent Settings Registry) ---

  async getAgents(): Promise<AgentRegistryResponse> {
    return this.request<AgentRegistryResponse>("/agents");
  }

  async registerAgent(
    registration: AgentRegistration,
  ): Promise<AgentStatusResponse> {
    return this.request<AgentStatusResponse>("/agents/register", {
      method: "POST",
      body: JSON.stringify(registration),
    });
  }

  async agentHeartbeat(
    agentId: string,
    currentRunId?: string,
  ): Promise<AgentStatusResponse> {
    return this.request<AgentStatusResponse>(`/agents/${agentId}/heartbeat`, {
      method: "POST",
      body: JSON.stringify({ current_run_id: currentRunId || null }),
    });
  }

  async stopAgent(
    agentId: string,
    mode: "graceful" | "force" = "graceful",
  ): Promise<{
    message: string;
    agent_id: string;
    agent_name: string;
    status: string;
  }> {
    return this.request<{
      message: string;
      agent_id: string;
      agent_name: string;
      status: string;
    }>(`/agents/${agentId}/stop?mode=${mode}`, {
      method: "POST",
    });
  }

  async startAgentWithRequirement(
    agentId: string,
    requirementId: string,
  ): Promise<{
    message: string;
    agent_id: string;
    agent_name: string;
    requirement_id: string;
    status: string;
  }> {
    return this.request<{
      message: string;
      agent_id: string;
      agent_name: string;
      requirement_id: string;
      status: string;
    }>(`/agents/${agentId}/start`, {
      method: "POST",
      body: JSON.stringify({ requirement_id: requirementId }),
    });
  }

  // --- Agent Config Endpoints (for S-0021: Agent Orchestration Enhancement) ---

  /**
   * Get all configured agents from the database.
   * Returns the list of agent configurations for display in the Agent Orchestration Dashboard.
   * This is different from getAgents() which returns runtime registry (running/stopped agents).
   */
  async getAgentsConfig(): Promise<AgentConfigsListResponse> {
    return this.request<AgentConfigsListResponse>("/agents/config");
  }

  // --- Workflow Configuration Endpoint (for S-0030: Agent Workflow Visualization) ---

  /**
   * Get workflow configuration for the agent workflow visualization panel.
   * Loads felix/workflow.json from the project directory.
   * Falls back to default workflow stages if file is missing or invalid.
   */
  async getWorkflowConfig(projectId?: string): Promise<WorkflowConfigResponse> {
    const params = projectId
      ? `?project_id=${encodeURIComponent(projectId)}`
      : "";
    return this.request<WorkflowConfigResponse>(
      `/agents/workflow-config${params}`,
    );
  }

  // --- Global Settings Endpoints (project-independent) ---

  async getGlobalConfig(): Promise<ConfigContent> {
    return this.request<ConfigContent>("/settings");
  }

  async updateGlobalConfig(config: FelixConfig): Promise<ConfigContent> {
    return this.request<ConfigContent>("/settings", {
      method: "PUT",
      body: JSON.stringify({ config }),
    });
  }

  async getOrgConfig(): Promise<ScopedConfigContent> {
    return this.request<ScopedConfigContent>("/settings/org");
  }

  async updateOrgConfig(config: FelixConfig): Promise<ScopedConfigContent> {
    return this.request<ScopedConfigContent>("/settings/org", {
      method: "PUT",
      body: JSON.stringify({ config }),
    });
  }

  async getUserConfig(): Promise<ScopedConfigContent> {
    return this.request<ScopedConfigContent>("/settings/user");
  }

  async updateUserConfig(config: FelixConfig): Promise<ScopedConfigContent> {
    return this.request<ScopedConfigContent>("/settings/user", {
      method: "PUT",
      body: JSON.stringify({ config }),
    });
  }

  // --- Copilot Endpoints (for S-0016: Felix Copilot Settings) ---

  async testCopilotConnection(): Promise<CopilotTestResult> {
    // Build headers with optional API key from localStorage
    const headers: Record<string, string> = {};
    const apiKey = localStorage.getItem(COPILOT_API_KEY_STORAGE_KEY);
    if (apiKey) {
      headers["X-Copilot-API-Key"] = apiKey;
    }

    return this.request<CopilotTestResult>("/copilot/test", {
      method: "POST",
      headers,
    });
  }

  async getCopilotStatus(): Promise<CopilotStatus> {
    return this.request<CopilotStatus>("/copilot/status");
  }

  // --- Copilot Chat Endpoints (for S-0017: Felix Copilot Chat Assistant) ---

  /**
   * Stream copilot chat response via Server-Sent Events (SSE).
   * Returns a controller object to manage the stream.
   *
   * @param request - The chat request containing message, history, and optional project path
   * @returns CopilotStreamController for managing the SSE stream
   */
  streamCopilotChat(request: CopilotChatRequest): CopilotStreamController {
    let abortController: AbortController | null = new AbortController();
    let eventCallback: ((event: CopilotStreamEvent) => void) | null = null;
    let errorCallback: ((error: Error) => void) | null = null;
    let completeCallback: (() => void) | null = null;
    let processedEventIds = new Set<string>(); // Prevent duplicate events

    // Start the fetch request
    const startStream = async () => {
      try {
        // Build headers with optional API key from localStorage
        const headers: Record<string, string> = {
          "Content-Type": "application/json",
        };

        // Get API key from localStorage and add to headers if present
        const apiKey = localStorage.getItem(COPILOT_API_KEY_STORAGE_KEY);
        if (apiKey) {
          headers["X-Copilot-API-Key"] = apiKey;
        }

        const response = await fetch(`${this.baseUrl}/copilot/chat/stream`, {
          method: "POST",
          headers,
          body: JSON.stringify(request),
          signal: abortController?.signal,
        });

        if (!response.ok) {
          const errorData = await response.json().catch(() => ({}));
          // Provide clear error message for 401 Unauthorized (missing API key)
          if (response.status === 401) {
            throw new Error(
              errorData.detail ||
                "API key required. Please add your OpenAI API key in Settings → Copilot.",
            );
          }
          throw new Error(
            errorData.detail ||
              `HTTP ${response.status}: ${response.statusText}`,
          );
        }

        const reader = response.body?.getReader();
        if (!reader) {
          throw new Error("Response body is not readable");
        }

        const decoder = new TextDecoder();
        let buffer = "";
        let lineNumber = 0; // Track line numbers for deduplication

        while (true) {
          if (abortController?.signal.aborted) {
            break;
          }

          const { done, value } = await reader.read();

          if (done) {
            completeCallback?.();
            break;
          }

          // Robust buffer management
          const chunk = decoder.decode(value, { stream: true });
          buffer += chunk;

          // Handle different line endings consistently
          const lines = buffer.split(/\r?\n/);

          // Keep incomplete line in buffer
          buffer = lines.pop() || "";

          for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            lineNumber++;

            if (!line || !line.startsWith("data: ")) {
              continue;
            }

            try {
              const dataStr = line.slice(6).trim();
              if (!dataStr || dataStr === "[DONE]") {
                if (dataStr === "[DONE]") {
                  completeCallback?.();
                  return;
                }
                continue;
              }

              // Create unique event ID for deduplication
              const eventId = `${lineNumber}_${dataStr.slice(0, 50)}`;
              if (processedEventIds.has(eventId)) {
                console.warn(
                  "Duplicate SSE event detected, skipping:",
                  eventId,
                );
                continue;
              }
              processedEventIds.add(eventId);

              // Clean up old event IDs to prevent memory leak
              if (processedEventIds.size > 1000) {
                const oldestEvents = Array.from(processedEventIds).slice(
                  0,
                  500,
                );
                oldestEvents.forEach((id) => processedEventIds.delete(id));
              }

              const data = JSON.parse(dataStr) as CopilotStreamEvent;

              // Only emit if stream hasn't been cancelled
              if (!abortController?.signal.aborted && eventCallback) {
                eventCallback(data);
              }

              // Handle completion
              if (data.done) {
                completeCallback?.();
                return;
              }

              // Handle errors
              if (data.error) {
                errorCallback?.(new Error(data.error));
                return;
              }
            } catch (parseError) {
              console.warn("Failed to parse SSE data:", line, parseError);
              // Continue processing other lines
            }
          }
        }
      } catch (error) {
        if (error instanceof Error && error.name === "AbortError") {
          // Stream was cancelled, don't call error callback
          return;
        }
        errorCallback?.(
          error instanceof Error ? error : new Error(String(error)),
        );
      }
    };

    // Start streaming immediately
    startStream();

    return {
      onEvent: (callback) => {
        eventCallback = callback;
      },
      onError: (callback) => {
        errorCallback = callback;
      },
      onComplete: (callback) => {
        completeCallback = callback;
      },
      cancel: () => {
        abortController?.abort();
        abortController = null;
        // Clear callbacks to prevent stale handler execution
        eventCallback = null;
        errorCallback = null;
        completeCallback = null;
        processedEventIds.clear();
      },
    };
  }

  // --- Agent Configuration Endpoints (for S-0020: Consolidate Agent Settings) ---

  /**
   * Get all agent configurations from the database.
   * Returns the list of agent configurations along with the currently active agent ID.
   */
  async getAgentConfigurations(): Promise<AgentConfigurationsResponse> {
    return this.request<AgentConfigurationsResponse>("/agent-configs");
  }

  /**
   * Get a specific agent configuration by ID.
   */
  async getAgentConfiguration(
    agentId: string,
  ): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>(
      `/agent-configs/${agentId}`,
    );
  }

  /**
   * Create a new agent configuration.
   * Automatically assigns the next available ID.
   */
  async createAgentConfiguration(
    config: AgentConfigurationCreate,
  ): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>("/agent-configs", {
      method: "POST",
      body: JSON.stringify(config),
    });
  }

  /**
   * Update an existing agent configuration.
   * All fields are optional - only provided fields are updated.
   */
  async updateAgentConfiguration(
    agentId: string,
    config: AgentConfigurationUpdate,
  ): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>(
      `/agent-configs/${agentId}`,
      {
        method: "PUT",
        body: JSON.stringify(config),
      },
    );
  }

  /**
   * Delete an agent configuration.
   * Agent ID 0 (system default) cannot be deleted.
   * If deleting the currently active agent, switches to agent ID 0.
   */
  async deleteAgentConfiguration(
    agentId: string,
  ): Promise<{ status: string; agent_id: string; message: string }> {
    return this.request<{ status: string; agent_id: string; message: string }>(
      `/agent-configs/${agentId}`,
      {
        method: "DELETE",
      },
    );
  }

  /**
   * Set the active agent by ID.
   * Updates config.json to use the specified agent_id.
   */
  async setActiveAgent(agentId: string): Promise<SetActiveAgentResponse> {
    return this.request<SetActiveAgentResponse>("/agent-configs/active", {
      method: "POST",
      body: JSON.stringify({ agent_id: agentId }),
    });
  }

  /**
   * Get the currently active agent configuration.
   * Returns the full agent config for the active agent ID.
   * Falls back to ID 0 if the active ID is invalid.
   */
  async getActiveAgentConfiguration(): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>(
      "/agent-configs/active/current",
    );
  }

  // --- Health Check ---

  async getUserProfile(): Promise<UserProfile> {
    return this.request<UserProfile>("/user/me");
  }

  async getUserProfileDetails(): Promise<UserProfileDetails> {
    return this.request<UserProfileDetails>("/user/profile");
  }

  async updateUserProfileDetails(
    payload: Partial<UserProfileDetails>,
  ): Promise<UserProfileDetails> {
    return this.request<UserProfileDetails>("/user/profile", {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }

  async uploadUserAvatar(file: File): Promise<UserProfileDetails> {
    const url = `${this.baseUrl}/user/avatar`;
    const headers: Record<string, string> = {};
    if (this.orgId) {
      headers["X-Felix-Org-Id"] = this.orgId;
    }
    const formData = new FormData();
    formData.append("file", file);

    const response = await fetch(url, {
      method: "POST",
      headers,
      body: formData,
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(
        errorData.detail || `HTTP ${response.status}: ${response.statusText}`,
      );
    }

    return response.json();
  }

  async deleteUserAvatar(): Promise<UserProfileDetails> {
    return this.request<UserProfileDetails>("/user/avatar", {
      method: "DELETE",
    });
  }

  async listOrganizations(): Promise<OrganizationSummary[]> {
    return this.request<OrganizationSummary[]>("/user/orgs");
  }

  setActiveOrgId(orgId: string | null): void {
    this.orgId = orgId;
    try {
      if (orgId) {
        localStorage.setItem(ACTIVE_ORG_STORAGE_KEY, orgId);
      } else {
        localStorage.removeItem(ACTIVE_ORG_STORAGE_KEY);
      }
    } catch {
      // Ignore storage issues (e.g. private browsing)
    }
  }

  getActiveOrgId(): string | null {
    return this.orgId;
  }

  // --- API Key Endpoints ---

  async listApiKeys(projectId: string): Promise<ApiKeyListResponse> {
    return this.request<ApiKeyListResponse>(`/projects/${projectId}/keys`);
  }

  async createApiKey(
    projectId: string,
    request: ApiKeyCreateRequest,
  ): Promise<ApiKeyCreated> {
    return this.request<ApiKeyCreated>(`/projects/${projectId}/keys`, {
      method: "POST",
      body: JSON.stringify(request),
    });
  }

  async revokeApiKey(
    projectId: string,
    keyId: string,
  ): Promise<{ id: string; status: string }> {
    return this.request<{ id: string; status: string }>(
      `/projects/${projectId}/keys/${keyId}`,
      {
        method: "DELETE",
      },
    );
  }

  async healthCheck(): Promise<{
    status: string;
    service: string;
    version: string;
  }> {
    const url = this.baseUrl.replace("/api", "/health");
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error("Backend not available");
    }
    return response.json();
  }
}

export const felixApi = new FelixApiService();

// --- Copilot API Key localStorage Functions (for S-0022: Copilot API Key Storage) ---

/**
 * Store the Copilot API key in localStorage.
 * @param key - The OpenAI/Anthropic API key to store
 */
export function setCopilotApiKey(key: string): void {
  localStorage.setItem(COPILOT_API_KEY_STORAGE_KEY, key);
}

/**
 * Retrieve the Copilot API key from localStorage.
 * @returns The stored API key, or null if not set
 */
export function getCopilotApiKey(): string | null {
  return localStorage.getItem(COPILOT_API_KEY_STORAGE_KEY);
}

/**
 * Remove the Copilot API key from localStorage.
 */
export function clearCopilotApiKey(): void {
  localStorage.removeItem(COPILOT_API_KEY_STORAGE_KEY);
}

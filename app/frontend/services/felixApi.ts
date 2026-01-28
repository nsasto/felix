/**
 * Felix Backend API Service
 * Handles communication with the Felix backend server.
 */

const API_BASE_URL = 'http://localhost:8080/api';

// --- Types matching backend models ---

export interface Project {
  id: string;
  path: string;
  name: string | null;
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
}

export interface SpecFile {
  filename: string;
  path: string;
}

export interface Requirement {
  id: string;
  title: string;
  spec_path: string;
  status: string;
  priority: string;
  labels: string[];
  depends_on: string[];
  updated_at: string;
  last_run_id?: string;
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

export type RunStatus = 'running' | 'completed' | 'failed' | 'stopped';

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

export interface AgentStatus {
  running: boolean;
  pid: number | null;
  started_at: string | null;
  current_run_id: string | null;
}

// --- Agent Registry Types (for S-0013: Agent Settings Registry) ---

export interface AgentEntry {
  pid: number;
  hostname: string;
  status: 'active' | 'inactive' | 'stopped';
  current_run_id: string | null;
  started_at: string | null;
  last_heartbeat: string | null;
  stopped_at: string | null;
}

export interface AgentRegistryResponse {
  agents: Record<string, AgentEntry>;
}

export interface AgentRegistration {
  agent_name: string;
  pid: number;
  hostname: string;
  started_at?: string;
}

export interface AgentStatusResponse {
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
  name?: string;  // Agent name identifier (added in S-0013)
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
  theme: 'dark' | 'light' | 'system';
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
  provider: 'openai' | 'anthropic' | 'custom';
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
  id: number;
  name: string;
  executable: string;
  args: string[];
  working_directory: string;
  environment: Record<string, string>;
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
  active_agent_id: number;
}

export interface AgentConfigurationResponse {
  agent: AgentConfiguration;
  message: string;
}

export interface SetActiveAgentRequest {
  agent_id: number;
}

export interface SetActiveAgentResponse {
  agent_id: number;
  message: string;
}

// --- Copilot Chat Types (for S-0017: Felix Copilot Chat Assistant) ---

export type AvatarState = 'idle' | 'listening' | 'thinking' | 'speaking' | 'error';

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
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

// --- API Functions ---

class FelixApiService {
  private baseUrl: string;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`;
    const response = await fetch(url, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`);
    }

    return response.json();
  }

  // --- Project Endpoints ---

  async listProjects(): Promise<Project[]> {
    return this.request<Project[]>('/projects');
  }

  async getProject(projectId: string): Promise<ProjectDetails> {
    return this.request<ProjectDetails>(`/projects/${projectId}`);
  }

  async registerProject(request: ProjectRegisterRequest): Promise<Project> {
    return this.request<Project>('/projects/register', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  async unregisterProject(projectId: string): Promise<void> {
    await this.request<{ message: string }>(`/projects/${projectId}`, {
      method: 'DELETE',
    });
  }

  async updateProject(projectId: string, request: ProjectUpdateRequest): Promise<Project> {
    return this.request<Project>(`/projects/${projectId}`, {
      method: 'PUT',
      body: JSON.stringify(request),
    });
  }

  // --- Spec Endpoints ---

  async listSpecs(projectId: string): Promise<SpecFile[]> {
    return this.request<SpecFile[]>(`/projects/${projectId}/specs`);
  }

  async getSpec(projectId: string, filename: string): Promise<{ content: string }> {
    return this.request<{ content: string }>(`/projects/${projectId}/specs/${filename}`);
  }

  async updateSpec(projectId: string, filename: string, content: string): Promise<void> {
    await this.request<{ message: string }>(`/projects/${projectId}/specs/${filename}`, {
      method: 'PUT',
      body: JSON.stringify({ content }),
    });
  }

  async createSpec(projectId: string, filename: string, content: string): Promise<{ filename: string; content: string }> {
    return this.request<{ filename: string; content: string }>(`/projects/${projectId}/specs`, {
      method: 'POST',
      body: JSON.stringify({ filename, content }),
    });
  }

  // --- Plan Endpoints ---

  async getPlan(projectId: string): Promise<{ content: string }> {
    return this.request<{ content: string }>(`/projects/${projectId}/plan`);
  }

  async updatePlan(projectId: string, content: string): Promise<void> {
    await this.request<{ message: string }>(`/projects/${projectId}/plan`, {
      method: 'PUT',
      body: JSON.stringify({ content }),
    });
  }

  // --- Requirements Endpoints ---

  async getRequirements(projectId: string): Promise<RequirementsData> {
    return this.request<RequirementsData>(`/projects/${projectId}/requirements`);
  }

  async updateRequirements(projectId: string, requirements: Requirement[]): Promise<RequirementsData> {
    return this.request<RequirementsData>(`/projects/${projectId}/requirements`, {
      method: 'PUT',
      body: JSON.stringify({ requirements }),
    });
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
    }
  ): Promise<RunHistoryResponse> {
    const params = new URLSearchParams();
    if (filters?.requirementId) {
      params.append('requirement_id', filters.requirementId);
    }
    if (filters?.agentName) {
      params.append('agent_name', filters.agentName);
    }
    if (filters?.status && filters.status.length > 0) {
      params.append('status', filters.status.join(','));
    }
    if (filters?.startDate) {
      params.append('start_date', filters.startDate);
    }
    if (filters?.endDate) {
      params.append('end_date', filters.endDate);
    }
    const queryString = params.toString();
    return this.request<RunHistoryResponse>(`/projects/${projectId}/runs${queryString ? `?${queryString}` : ''}`);
  }

  async startRun(projectId: string): Promise<{ run_id: string; pid: number }> {
    return this.request<{ run_id: string; pid: number }>(`/projects/${projectId}/runs/start`, {
      method: 'POST',
    });
  }

  async stopRun(projectId: string): Promise<void> {
    await this.request<{ message: string }>(`/projects/${projectId}/runs/stop`, {
      method: 'POST',
    });
  }

  async getAgentStatus(projectId: string): Promise<AgentStatus> {
    return this.request<AgentStatus>(`/projects/${projectId}/runs/status`);
  }

  async getRunArtifact(projectId: string, runId: string, filename: string): Promise<RunArtifactContent> {
    return this.request<RunArtifactContent>(`/projects/${projectId}/runs/${runId}/artifacts/${filename}`);
  }

  // --- Config Endpoints ---

  async getConfig(projectId: string): Promise<ConfigContent> {
    return this.request<ConfigContent>(`/projects/${projectId}/config`);
  }

  async updateConfig(projectId: string, config: FelixConfig): Promise<ConfigContent> {
    return this.request<ConfigContent>(`/projects/${projectId}/config`, {
      method: 'PUT',
      body: JSON.stringify({ config }),
    });
  }

  // --- Requirement Status Endpoints (for S-0006: Spec Edit Safety) ---

  async getRequirementStatus(projectId: string, requirementId: string): Promise<RequirementStatusResponse> {
    return this.request<RequirementStatusResponse>(`/projects/${projectId}/requirements/${requirementId}/status`);
  }

  async updateRequirementStatus(projectId: string, requirementId: string, status: string): Promise<RequirementStatusResponse> {
    return this.request<RequirementStatusResponse>(`/projects/${projectId}/requirements/${requirementId}/status`, {
      method: 'PUT',
      body: JSON.stringify({ status }),
    });
  }

  async getPlanInfo(projectId: string, requirementId: string): Promise<PlanInfo> {
    return this.request<PlanInfo>(`/projects/${projectId}/plans/${requirementId}`);
  }

  async deletePlan(projectId: string, requirementId: string): Promise<PlanDeleteResponse> {
    return this.request<PlanDeleteResponse>(`/projects/${projectId}/plans/${requirementId}`, {
      method: 'DELETE',
    });
  }

  // --- Agent Registry Endpoints (for S-0013: Agent Settings Registry) ---

  async getAgents(): Promise<AgentRegistryResponse> {
    return this.request<AgentRegistryResponse>('/agents');
  }

  async registerAgent(registration: AgentRegistration): Promise<AgentStatusResponse> {
    return this.request<AgentStatusResponse>('/agents/register', {
      method: 'POST',
      body: JSON.stringify(registration),
    });
  }

  async agentHeartbeat(agentName: string, currentRunId?: string): Promise<AgentStatusResponse> {
    return this.request<AgentStatusResponse>(`/agents/${agentName}/heartbeat`, {
      method: 'POST',
      body: JSON.stringify({ current_run_id: currentRunId || null }),
    });
  }

  async stopAgent(agentName: string, mode: 'graceful' | 'force' = 'graceful'): Promise<{ message: string; agent_name: string; status: string }> {
    return this.request<{ message: string; agent_name: string; status: string }>(`/agents/${agentName}/stop?mode=${mode}`, {
      method: 'POST',
    });
  }

  async startAgentWithRequirement(agentName: string, requirementId: string): Promise<{ message: string; agent_name: string; requirement_id: string; status: string }> {
    return this.request<{ message: string; agent_name: string; requirement_id: string; status: string }>(`/agents/${agentName}/start`, {
      method: 'POST',
      body: JSON.stringify({ requirement_id: requirementId }),
    });
  }

  // --- Global Settings Endpoints (project-independent) ---

  async getGlobalConfig(): Promise<ConfigContent> {
    return this.request<ConfigContent>('/settings');
  }

  async updateGlobalConfig(config: FelixConfig): Promise<ConfigContent> {
    return this.request<ConfigContent>('/settings', {
      method: 'PUT',
      body: JSON.stringify({ config }),
    });
  }

  // --- Copilot Endpoints (for S-0016: Felix Copilot Settings) ---

  async testCopilotConnection(): Promise<CopilotTestResult> {
    return this.request<CopilotTestResult>('/copilot/test', {
      method: 'POST',
    });
  }

  async getCopilotStatus(): Promise<CopilotStatus> {
    return this.request<CopilotStatus>('/copilot/status');
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

    // Start the fetch request
    const startStream = async () => {
      try {
        const response = await fetch(`${this.baseUrl}/copilot/chat/stream`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(request),
          signal: abortController?.signal,
        });

        if (!response.ok) {
          const errorData = await response.json().catch(() => ({}));
          throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`);
        }

        const reader = response.body?.getReader();
        if (!reader) {
          throw new Error('Response body is not readable');
        }

        const decoder = new TextDecoder();
        let buffer = '';

        while (true) {
          const { done, value } = await reader.read();
          
          if (done) {
            completeCallback?.();
            break;
          }

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          
          // Keep the last incomplete line in the buffer
          buffer = lines.pop() || '';

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              try {
                const data = JSON.parse(line.slice(6)) as CopilotStreamEvent;
                eventCallback?.(data);
                
                // Check if stream is done
                if (data.done) {
                  completeCallback?.();
                  return;
                }
                
                // Check for errors
                if (data.error) {
                  errorCallback?.(new Error(data.error));
                }
              } catch (parseError) {
                // Ignore JSON parse errors for malformed lines
                console.warn('Failed to parse SSE data:', line);
              }
            }
          }
        }
      } catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
          // Stream was cancelled, don't call error callback
          return;
        }
        errorCallback?.(error instanceof Error ? error : new Error(String(error)));
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
      },
    };
  }

  // --- Agent Configuration Endpoints (for S-0020: Consolidate Agent Settings) ---

  /**
   * Get all agent configurations from agents.json.
   * Returns the list of agent configurations along with the currently active agent ID.
   */
  async getAgentConfigurations(): Promise<AgentConfigurationsResponse> {
    return this.request<AgentConfigurationsResponse>('/agent-configs');
  }

  /**
   * Get a specific agent configuration by ID.
   */
  async getAgentConfiguration(agentId: number): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>(`/agent-configs/${agentId}`);
  }

  /**
   * Create a new agent configuration.
   * Automatically assigns the next available ID.
   */
  async createAgentConfiguration(config: AgentConfigurationCreate): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>('/agent-configs', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  /**
   * Update an existing agent configuration.
   * All fields are optional - only provided fields are updated.
   */
  async updateAgentConfiguration(agentId: number, config: AgentConfigurationUpdate): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>(`/agent-configs/${agentId}`, {
      method: 'PUT',
      body: JSON.stringify(config),
    });
  }

  /**
   * Delete an agent configuration.
   * Agent ID 0 (system default) cannot be deleted.
   * If deleting the currently active agent, switches to agent ID 0.
   */
  async deleteAgentConfiguration(agentId: number): Promise<{ status: string; agent_id: number; message: string }> {
    return this.request<{ status: string; agent_id: number; message: string }>(`/agent-configs/${agentId}`, {
      method: 'DELETE',
    });
  }

  /**
   * Set the active agent by ID.
   * Updates config.json to use the specified agent_id.
   */
  async setActiveAgent(agentId: number): Promise<SetActiveAgentResponse> {
    return this.request<SetActiveAgentResponse>('/agent-configs/active', {
      method: 'POST',
      body: JSON.stringify({ agent_id: agentId }),
    });
  }

  /**
   * Get the currently active agent configuration.
   * Returns the full agent config for the active agent ID.
   * Falls back to ID 0 if the active ID is invalid.
   */
  async getActiveAgentConfiguration(): Promise<AgentConfigurationResponse> {
    return this.request<AgentConfigurationResponse>('/agent-configs/active/current');
  }

  // --- Health Check ---

  async healthCheck(): Promise<{ status: string; service: string; version: string }> {
    const url = this.baseUrl.replace('/api', '/health');
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error('Backend not available');
    }
    return response.json();
  }
}

export const felixApi = new FelixApiService();

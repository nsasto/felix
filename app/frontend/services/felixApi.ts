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
}

export interface FelixConfig {
  version: string;
  executor: ExecutorConfig;
  agent: AgentConfig;
  paths: PathsConfig;
  backpressure: BackpressureConfig;
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

  async listRuns(projectId: string): Promise<RunHistoryResponse> {
    return this.request<RunHistoryResponse>(`/projects/${projectId}/runs`);
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

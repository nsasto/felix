/**
 * API client for database-backed agent and run control endpoints.
 * Introduced in S-0040 (Run Control API) and used by S-0042 (Frontend Dashboard).
 *
 * This is a clean separation from the legacy felixApi.ts which uses
 * file-based agent registry with numeric agent IDs.
 */

import type {
  Agent,
  AgentListResponse,
  Run,
  RunListResponse,
} from './types';

const API_BASE_URL = 'http://localhost:8080/api';

/**
 * Generic request helper with error handling.
 */
async function request<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const url = `${API_BASE_URL}${endpoint}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(
      errorData.detail || `HTTP ${response.status}: ${response.statusText}`
    );
  }

  return response.json();
}

/**
 * Register a new agent in the database.
 *
 * @param agent_id - Unique agent identifier (UUID string)
 * @param name - Display name for the agent
 * @param type - Agent type (e.g., 'ralph', 'builder', 'planner')
 * @param metadata - Optional JSON metadata for the agent
 * @returns The registered agent
 */
export async function registerAgent(
  agent_id: string,
  name: string,
  type: string = 'ralph',
  metadata?: Record<string, unknown>
): Promise<Agent> {
  return request<Agent>('/agents/register', {
    method: 'POST',
    body: JSON.stringify({
      agent_id,
      name,
      type,
      metadata: metadata || {},
    }),
  });
}

/**
 * List all agents for the current project.
 *
 * @returns List of agents and count
 */
export async function listAgents(options?: {
  scope?: 'project' | 'org';
  projectId?: string;
}): Promise<AgentListResponse> {
  const params = new URLSearchParams();
  if (options?.scope) {
    params.append('scope', options.scope);
  }
  if (options?.projectId) {
    params.append('project_id', options.projectId);
  }
  const query = params.toString();
  return request<AgentListResponse>(`/agents${query ? `?${query}` : ''}`);
}

/**
 * Get a specific agent by ID.
 *
 * @param agent_id - The agent's UUID string
 * @returns The agent details
 */
export async function getAgent(agent_id: string): Promise<Agent> {
  return request<Agent>(`/agents/${encodeURIComponent(agent_id)}`);
}

/**
 * Create a new run for an agent.
 *
 * @param agent_id - The agent's UUID string
 * @param requirement_id - Optional requirement being worked on
 * @param metadata - Optional JSON metadata for the run
 * @returns The created run
 */
export async function createRun(
  agent_id: string,
  requirement_id?: string,
  metadata?: Record<string, unknown>
): Promise<Run> {
  return request<Run>('/agents/runs', {
    method: 'POST',
    body: JSON.stringify({
      agent_id,
      requirement_id: requirement_id || null,
      metadata: metadata || {},
    }),
  });
}

/**
 * Stop a running run.
 *
 * @param run_id - The run's UUID string
 * @returns The stopped run
 */
export async function stopRun(run_id: string): Promise<Run> {
  return request<Run>(`/agents/runs/${encodeURIComponent(run_id)}/stop`, {
    method: 'POST',
  });
}

/**
 * List runs with optional limit.
 *
 * @param limit - Maximum number of runs to return (default: no limit)
 * @returns List of runs and count
 */
export async function listRuns(limit?: number): Promise<RunListResponse> {
  const params = limit ? `?limit=${limit}` : '';
  return request<RunListResponse>(`/agents/runs${params}`);
}

/**
 * Get a specific run by ID.
 *
 * @param run_id - The run's UUID string
 * @returns The run details
 */
export async function getRun(run_id: string): Promise<Run> {
  return request<Run>(`/agents/runs/${encodeURIComponent(run_id)}`);
}

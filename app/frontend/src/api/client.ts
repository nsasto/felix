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
  OrgInvite,
  OrgMember,
  OrgMembersResponse,
  Run,
  RunListResponse,
  RunFilesResponse,
  RunEventsResponse,
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
  type?: string,
  metadata?: Record<string, unknown>,
  profile_id?: string
): Promise<Agent> {
  return request<Agent>('/agents/register', {
    method: 'POST',
    body: JSON.stringify({
      agent_id,
      name,
      type: type || undefined,
      metadata: metadata || {},
      profile_id: profile_id || null,
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
export async function listRuns(options?: {
  limit?: number;
  projectId?: string;
  requirementId?: string;
  status?: string[];
}): Promise<RunListResponse> {
  const params = new URLSearchParams();
  if (options?.limit) {
    params.append('limit', options.limit.toString());
  }
  if (options?.projectId) {
    params.append('project_id', options.projectId);
  }
  if (options?.requirementId) {
    params.append('requirement_id', options.requirementId);
  }
  if (options?.status && options.status.length > 0) {
    params.append('status', options.status.join(','));
  }
  const query = params.toString();
  return request<RunListResponse>(`/agents/runs${query ? `?${query}` : ''}`);
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

/**
 * List organization members and invites.
 */
export async function listOrgMembers(orgId: string): Promise<OrgMembersResponse> {
  return request<OrgMembersResponse>(
    `/orgs/${encodeURIComponent(orgId)}/members`
  );
}

/**
 * Invite a new organization member.
 */
export async function inviteOrgMember(
  orgId: string,
  payload: {
    email: string;
    role: string;
  }
): Promise<OrgInvite> {
  return request<OrgInvite>(
    `/orgs/${encodeURIComponent(orgId)}/invites`,
    {
      method: 'POST',
      body: JSON.stringify(payload),
    }
  );
}

/**
 * Update an organization member role.
 */
export async function updateOrgMemberRole(
  orgId: string,
  userId: string,
  role: string
): Promise<OrgMember> {
  return request<OrgMember>(
    `/orgs/${encodeURIComponent(orgId)}/members/${encodeURIComponent(userId)}`,
    {
      method: 'PATCH',
      body: JSON.stringify({ role }),
    }
  );
}

/**
 * Remove an organization member.
 */
export async function removeOrgMember(
  orgId: string,
  userId: string
): Promise<{ status: string }> {
  return request<{ status: string }>(
    `/orgs/${encodeURIComponent(orgId)}/members/${encodeURIComponent(userId)}`,
    { method: 'DELETE' }
  );
}

/**
 * Update an organization invite role.
 */
export async function updateOrgInviteRole(
  orgId: string,
  inviteId: string,
  role: string
): Promise<OrgInvite> {
  return request<OrgInvite>(
    `/orgs/${encodeURIComponent(orgId)}/invites/${encodeURIComponent(inviteId)}`,
    {
      method: 'PATCH',
      body: JSON.stringify({ role }),
    }
  );
}

/**
 * Resend an organization invite.
 */
export async function resendOrgInvite(
  orgId: string,
  inviteId: string
): Promise<OrgInvite> {
  return request<OrgInvite>(
    `/orgs/${encodeURIComponent(orgId)}/invites/${encodeURIComponent(inviteId)}/resend`,
    { method: 'POST' }
  );
}

/**
 * Revoke an organization invite.
 */
export async function revokeOrgInvite(
  orgId: string,
  inviteId: string
): Promise<OrgInvite> {
  return request<OrgInvite>(
    `/orgs/${encodeURIComponent(orgId)}/invites/${encodeURIComponent(inviteId)}`,
    { method: 'DELETE' }
  );
}

// ============================================================================
// RUN SYNC ENDPOINTS (S-0063 - Artifact Sync Viewer)
// ============================================================================

/**
 * List all files for a run from the sync API.
 *
 * Note: The sync endpoints use full /api path in the router definition,
 * so we need to call them without the API_BASE_URL prefix.
 *
 * @param runId - The run's UUID string
 * @returns List of files in the run with metadata
 */
export async function getRunFiles(runId: string): Promise<RunFilesResponse> {
  // Sync endpoints use full /api/runs path in router, not /agents/runs
  const url = `http://localhost:8080/api/runs/${encodeURIComponent(runId)}/files`;
  const response = await fetch(url, {
    headers: {
      'Content-Type': 'application/json',
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
 * Get the content of a specific file from a run.
 *
 * @param runId - The run's UUID string
 * @param filePath - Path of the file within the run (e.g., 'report.md', 'output.log')
 * @returns The file content as text
 */
export async function getRunFile(
  runId: string,
  filePath: string
): Promise<string> {
  // Sync endpoints use full /api/runs path in router
  const url = `http://localhost:8080/api/runs/${encodeURIComponent(runId)}/files/${encodeURIComponent(filePath)}`;
  const response = await fetch(url);

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(
      errorData.detail || `HTTP ${response.status}: ${response.statusText}`
    );
  }

  return response.text();
}

/**
 * List events for a run from the sync API with pagination support.
 *
 * @param runId - The run's UUID string
 * @param after - Cursor for pagination - return events after this ID (optional)
 * @param limit - Maximum number of events to return (default: 100, max: 1000)
 * @returns List of events and pagination info
 */
export async function getRunEvents(
  runId: string,
  after?: number,
  limit?: number
): Promise<RunEventsResponse> {
  const params = new URLSearchParams();
  if (after !== undefined) {
    params.append('after', after.toString());
  }
  if (limit !== undefined) {
    params.append('limit', limit.toString());
  }
  const query = params.toString();
  // Sync endpoints use full /api/runs path in router, not /agents/runs
  const url = `http://localhost:8080/api/runs/${encodeURIComponent(runId)}/events${query ? `?${query}` : ''}`;
  const response = await fetch(url, {
    headers: {
      'Content-Type': 'application/json',
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

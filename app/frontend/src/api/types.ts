/**
 * TypeScript interfaces for database-backed agent and run API.
 * These interfaces match the backend Pydantic models in app/backend/models.py.
 *
 * Introduced in S-0040 (Run Control API) and S-0042 (Frontend Dashboard).
 */

/**
 * Agent response from the database.
 * Matches AgentResponse in backend models.py.
 */
export interface Agent {
  /** Unique agent identifier (UUID string) */
  id: string;
  /** Project ID the agent belongs to */
  project_id: string;
  /** Display name for the agent */
  name: string;
  /** Agent type (e.g., 'ralph', 'builder', 'planner') */
  type: string;
  /** Current status (idle, running, stopped, error) */
  status: string;
  /** Last heartbeat timestamp (ISO string or null) */
  heartbeat_at: string | null;
  /** Agent metadata as JSON object */
  metadata: Record<string, unknown>;
  /** Agent profile ID (UUID string or null) */
  profile_id: string | null;
  /** Agent profile name (human-readable, joined from agent_profiles table) */
  profile_name?: string | null;
  /** Hostname where the agent is running (joined from machines table) */
  hostname?: string | null;
  /** When the agent was created (ISO string) */
  created_at: string;
  /** When the agent was last updated (ISO string) */
  updated_at: string;
}

/**
 * Response model for listing agents.
 * Matches AgentListResponse in backend models.py.
 */
export interface AgentListResponse {
  /** List of agents */
  agents: Agent[];
  /** Total number of agents returned */
  count: number;
}

/**
 * Run response from the database.
 * Matches RunResponse in backend models.py.
 */
export interface Run {
  /** Unique run identifier (UUID string) */
  id: string;
  /** Project ID the run belongs to */
  project_id: string;
  /** Agent ID executing the run */
  agent_id: string;
  /** Requirement being worked on (optional) */
  requirement_id: string | null;
  /** Current status (pending, running, completed, failed, cancelled) */
  status: string;
  /** When the run started (ISO string or null) */
  started_at: string | null;
  /** When the run completed (ISO string or null) */
  completed_at: string | null;
  /** Error message if run failed (optional) */
  error: string | null;
  /** Run metadata as JSON object */
  metadata: Record<string, unknown>;
  /** Agent display name (joined from agents table, optional) */
  agent_name: string | null;
}

/**
 * Response model for listing runs.
 * Matches RunListResponse in backend models.py.
 */
export interface RunListResponse {
  /** List of runs */
  runs: Run[];
  /** Total number of runs returned */
  count: number;
}

/**
 * Organization member response.
 * Matches OrganizationMember in backend models.py.
 */
export interface OrgMember {
  id: string;
  org_id: string;
  user_id: string;
  role: string;
  email: string | null;
  display_name: string | null;
  full_name: string | null;
  created_at: string;
  updated_at: string | null;
}

/**
 * Organization invite response.
 * Matches OrganizationInvite in backend models.py.
 */
export interface OrgInvite {
  id: string;
  org_id: string;
  email: string;
  role: string;
  status: string;
  invited_by_user_id: string | null;
  created_at: string;
  updated_at: string;
}

/**
 * Response model for listing members and invites.
 */
export interface OrgMembersResponse {
  members: OrgMember[];
  invites: OrgInvite[];
}

// ============================================================================
// RUN FILE AND EVENT INTERFACES (S-0063 - Artifact Sync Viewer)
// ============================================================================

/**
 * Information about a run file from the sync API.
 * Matches FileInfo in backend routers/sync.py.
 */
export interface RunFile {
  /** File path within the run (e.g., 'report.md', 'output.log') */
  path: string;
  /** File kind ('artifact' or 'log') */
  kind: string;
  /** File size in bytes */
  size_bytes: number;
  /** SHA256 hash of file content (optional) */
  sha256: string | null;
  /** MIME content type (e.g., 'text/markdown', 'text/plain') */
  content_type: string;
  /** When file was last updated (ISO string) */
  updated_at: string;
}

/**
 * Information about a run event from the sync API.
 * Matches EventInfo in backend routers/sync.py.
 */
export interface RunEvent {
  /** Event ID (auto-incremented integer) */
  id: number;
  /** Event timestamp (ISO string) */
  ts: string;
  /** Event type (e.g., 'started', 'task_completed', 'error') */
  type: string;
  /** Event level ('info', 'warn', 'error', 'debug') */
  level: string;
  /** Event message (optional) */
  message: string | null;
  /** Event payload as JSON object (optional) */
  payload: Record<string, unknown> | null;
}

/**
 * Response for listing run files from the sync API.
 * Matches FileListResponse in backend routers/sync.py.
 */
export interface RunFilesResponse {
  /** Run ID */
  run_id: string;
  /** List of files in the run */
  files: RunFile[];
}

/**
 * Response for listing run events from the sync API.
 * Matches EventListResponse in backend routers/sync.py.
 */
export interface RunEventsResponse {
  /** Run ID */
  run_id: string;
  /** List of events in the run */
  events: RunEvent[];
  /** Whether more events exist after this page (for pagination) */
  has_more: boolean;
}

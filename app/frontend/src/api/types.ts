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

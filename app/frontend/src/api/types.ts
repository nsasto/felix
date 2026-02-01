/**
 * TypeScript interfaces for the database-backed agent and run control API.
 * These types match the backend Pydantic models from app/backend/models.py.
 */

/**
 * Agent response model matching AgentResponse from backend.
 */
export interface Agent {
  id: string;
  project_id: string;
  name: string;
  type: string;
  status: string;
  heartbeat_at: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

/**
 * Response model for listing agents.
 */
export interface AgentListResponse {
  agents: Agent[];
  count: number;
}

/**
 * Run response model matching RunResponse from backend.
 */
export interface Run {
  id: string;
  project_id: string;
  agent_id: string;
  requirement_id: string | null;
  status: string;
  started_at: string | null;
  completed_at: string | null;
  error: string | null;
  metadata: Record<string, unknown>;
  agent_name: string | null;
}

/**
 * Response model for listing runs.
 */
export interface RunListResponse {
  runs: Run[];
  count: number;
}

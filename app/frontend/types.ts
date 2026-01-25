
// ============================================================================
// Legacy Chat Types (retained for potential Gemini integration)
// ============================================================================

export enum MessageRole {
  USER = 'user',
  MODEL = 'model',
  SYSTEM = 'system'
}

export interface ContextFile {
  id: string;
  name: string;
  path: string;
  content: string;
  language: string;
}

export interface Attachment {
  type: 'image' | 'file' | 'code';
  data: string;
  mimeType: string;
  name: string;
}

export interface Source {
  title: string;
  uri: string;
}

export interface Message {
  id: string;
  role: MessageRole;
  text: string;
  attachments?: Attachment[];
  timestamp: number;
  isThinking?: boolean;
  command?: string;
  type?: 'chat' | 'terminal' | 'action';
  sources?: Source[];
}

export interface Conversation {
  id: string;
  title: string;
  messages: Message[];
  contextFiles: ContextFile[];
  updatedAt: number;
}

export enum ModelType {
  FLASH = 'gemini-3-flash-preview',
  PRO = 'gemini-3-pro-preview'
}

// ============================================================================
// UI State Types
// ============================================================================

/** Task status for mock Kanban (legacy, used in App.tsx for demo) */
export type TaskStatus = 'todo' | 'in-progress' | 'completed' | 'backlog';

/** Mock task interface (legacy, used in App.tsx for demo) */
export interface Task {
  id: string;
  title: string;
  description: string;
  status: TaskStatus;
  priority: 'low' | 'medium' | 'high';
  tags: string[];
}

/** Markdown asset for the assets view (legacy, used in App.tsx for demo) */
export interface MarkdownAsset {
  id: string;
  name: string;
  content: string;
  lastEdited: number;
}

/** Base UI state options */
export type UIState = 'kanban' | 'canvas' | 'assets';

// ============================================================================
// Felix Backend Types (re-exported from felixApi.ts for convenience)
// ============================================================================

// These types are defined in services/felixApi.ts and should be imported
// from there for consistency. This section documents the backend models
// for reference.

/** Requirement status values matching backend RequirementStatus */
export type RequirementStatus = 'draft' | 'planned' | 'in_progress' | 'complete' | 'blocked';

/** Requirement priority values */
export type RequirementPriority = 'low' | 'medium' | 'high' | 'critical';

/** Run status values matching backend RunStatus enum */
export type RunStatus = 'running' | 'completed' | 'failed' | 'stopped';

/** WebSocket event types sent by backend */
export type WebSocketEventType = 
  | 'connected'
  | 'state_update'
  | 'file_changed'
  | 'iteration_complete'
  | 'run_complete'
  | 'error';

/** WebSocket message structure from backend */
export interface WebSocketMessage {
  type: WebSocketEventType;
  timestamp: string;
  data?: Record<string, unknown>;
}

/** State update data from WebSocket */
export interface StateUpdateData {
  iteration: number;
  mode: string;
  status: string;
  current_task: string | null;
  max_iterations: number;
}

/** Iteration complete event data */
export interface IterationCompleteData {
  iteration: number;
  mode: string;
  status: string;
  outcome: string | null;
}

/** Run complete event data */
export interface RunCompleteData {
  run_id: string | null;
  status: string;
  iterations_completed: number;
}

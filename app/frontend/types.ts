
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

export type TaskStatus = 'todo' | 'in-progress' | 'completed' | 'backlog';

export interface Task {
  id: string;
  title: string;
  description: string;
  status: TaskStatus;
  priority: 'low' | 'medium' | 'high';
  tags: string[];
}

export interface MarkdownAsset {
  id: string;
  name: string;
  content: string;
  lastEdited: number;
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

export type UIState = 'kanban' | 'canvas' | 'assets';

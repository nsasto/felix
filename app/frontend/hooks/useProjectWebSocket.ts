/**
 * useProjectWebSocket - Custom hook for real-time project updates via WebSocket
 * 
 * Connects to the Felix backend WebSocket to receive live updates when:
 * - felix/state.json changes (mode_change, status_update, iteration_start, iteration_complete, run_complete, state_update)
 * - felix/requirements.json changes (requirements_update)
 * - runs/ directory changes (run_started, run_updated, run_artifact_created, run_artifact_updated)
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { Requirement } from '../services/felixApi';

// WebSocket event types from backend
export type WebSocketEventType = 
  | 'initial_state'
  | 'initial_requirements'
  | 'initial_runs'
  | 'mode_change'
  | 'status_update'
  | 'iteration_start'
  | 'iteration_complete'
  | 'run_complete'
  | 'state_update'
  | 'requirements_update'
  | 'run_started'
  | 'run_updated'
  | 'run_artifact_created'
  | 'run_artifact_updated';

// State from felix/state.json
export interface FelixState {
  current_requirement_id: string | null;
  current_iteration: number;
  last_mode: 'planning' | 'building' | null;
  last_iteration_outcome: string | null;
  status: 'idle' | 'running' | 'complete' | 'stopped' | 'error';
  last_run_id: string | null;
  updated_at: string | null;
}

// WebSocket event data types
export interface ModeChangeData {
  previous_mode: string | null;
  current_mode: string | null;
  requirement_id: string | null;
}

export interface StatusUpdateData {
  previous_status: string | null;
  current_status: string | null;
  requirement_id: string | null;
}

export interface IterationStartData {
  iteration: number;
  mode: string | null;
  requirement_id: string | null;
}

export interface IterationCompleteData {
  iteration: number;
  outcome: string | null;
  mode: string | null;
  requirement_id: string | null;
}

export interface RunCompleteData {
  final_status: string;
  last_outcome: string | null;
  requirement_id: string | null;
  run_id: string | null;
}

export interface RunArtifactData {
  run_id: string;
  artifact?: string;
  preview?: string;
}

export interface RequirementsUpdateData {
  requirements: Requirement[];
}

export interface InitialRunsData {
  runs: Array<{
    run_id: string;
    artifacts: string[];
  }>;
}

// Generic WebSocket event
export interface WebSocketEvent {
  type: WebSocketEventType;
  timestamp: string;
  data: FelixState | ModeChangeData | StatusUpdateData | IterationStartData | 
        IterationCompleteData | RunCompleteData | RunArtifactData | 
        RequirementsUpdateData | InitialRunsData;
}

// Hook options
export interface UseProjectWebSocketOptions {
  reconnectInterval?: number;  // Time between reconnection attempts (ms)
  maxReconnectAttempts?: number;  // Max reconnection attempts before giving up
  onEvent?: (event: WebSocketEvent) => void;  // Callback for all events
  onConnect?: () => void;  // Callback when connection established
  onDisconnect?: () => void;  // Callback when disconnected
  onError?: (error: Event) => void;  // Callback for errors
}

// Hook return type
export interface UseProjectWebSocketReturn {
  isConnected: boolean;
  lastEvent: WebSocketEvent | null;
  state: FelixState | null;
  requirements: Requirement[] | null;
  reconnect: () => void;
  disconnect: () => void;
}

const WS_BASE_URL = 'ws://localhost:8080';

const DEFAULT_OPTIONS: Required<Omit<UseProjectWebSocketOptions, 'onEvent' | 'onConnect' | 'onDisconnect' | 'onError'>> = {
  reconnectInterval: 3000,
  maxReconnectAttempts: 10,
};

export function useProjectWebSocket(
  projectId: string | null,
  options: UseProjectWebSocketOptions = {}
): UseProjectWebSocketReturn {
  const {
    reconnectInterval = DEFAULT_OPTIONS.reconnectInterval,
    maxReconnectAttempts = DEFAULT_OPTIONS.maxReconnectAttempts,
    onEvent,
    onConnect,
    onDisconnect,
    onError,
  } = options;

  const [isConnected, setIsConnected] = useState(false);
  const [lastEvent, setLastEvent] = useState<WebSocketEvent | null>(null);
  const [state, setState] = useState<FelixState | null>(null);
  const [requirements, setRequirements] = useState<Requirement[] | null>(null);

  // Refs for stable references
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttemptsRef = useRef(0);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isManualDisconnectRef = useRef(false);

  // Cleanup function
  const cleanup = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
  }, []);

  // Handle incoming WebSocket messages
  const handleMessage = useCallback((event: MessageEvent) => {
    try {
      const wsEvent: WebSocketEvent = JSON.parse(event.data);
      setLastEvent(wsEvent);

      // Update state based on event type
      switch (wsEvent.type) {
        case 'initial_state':
        case 'state_update':
          setState(wsEvent.data as FelixState);
          break;
        case 'initial_requirements':
        case 'requirements_update':
          const reqData = wsEvent.data as RequirementsUpdateData;
          setRequirements(reqData.requirements);
          break;
        // Other events don't update state directly but are exposed via lastEvent
      }

      // Call user callback if provided
      if (onEvent) {
        onEvent(wsEvent);
      }
    } catch (err) {
      console.error('[useProjectWebSocket] Failed to parse message:', err);
    }
  }, [onEvent]);

  // Connect to WebSocket
  const connect = useCallback(() => {
    if (!projectId) {
      return;
    }

    // Clean up any existing connection
    cleanup();
    isManualDisconnectRef.current = false;

    const wsUrl = `${WS_BASE_URL}/ws/projects/${projectId}`;
    
    try {
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log(`[useProjectWebSocket] Connected to ${wsUrl}`);
        setIsConnected(true);
        reconnectAttemptsRef.current = 0;
        if (onConnect) {
          onConnect();
        }
      };

      ws.onmessage = handleMessage;

      ws.onclose = () => {
        console.log('[useProjectWebSocket] Connection closed');
        setIsConnected(false);
        wsRef.current = null;

        if (onDisconnect) {
          onDisconnect();
        }

        // Attempt reconnection if not a manual disconnect
        if (!isManualDisconnectRef.current && reconnectAttemptsRef.current < maxReconnectAttempts) {
          reconnectAttemptsRef.current += 1;
          console.log(`[useProjectWebSocket] Reconnecting in ${reconnectInterval}ms (attempt ${reconnectAttemptsRef.current}/${maxReconnectAttempts})`);
          reconnectTimeoutRef.current = setTimeout(connect, reconnectInterval);
        }
      };

      ws.onerror = (error) => {
        console.error('[useProjectWebSocket] WebSocket error:', error);
        if (onError) {
          onError(error);
        }
      };
    } catch (err) {
      console.error('[useProjectWebSocket] Failed to create WebSocket:', err);
    }
  }, [projectId, cleanup, handleMessage, maxReconnectAttempts, reconnectInterval, onConnect, onDisconnect, onError]);

  // Manual reconnect function
  const reconnect = useCallback(() => {
    reconnectAttemptsRef.current = 0;
    connect();
  }, [connect]);

  // Manual disconnect function
  const disconnect = useCallback(() => {
    isManualDisconnectRef.current = true;
    cleanup();
    setIsConnected(false);
    setState(null);
    setRequirements(null);
    setLastEvent(null);
  }, [cleanup]);

  // Connect when projectId changes
  useEffect(() => {
    if (projectId) {
      connect();
    } else {
      disconnect();
    }

    // Cleanup on unmount or projectId change
    return () => {
      isManualDisconnectRef.current = true;
      cleanup();
    };
  }, [projectId]); // eslint-disable-line react-hooks/exhaustive-deps

  return {
    isConnected,
    lastEvent,
    state,
    requirements,
    reconnect,
    disconnect,
  };
}

export default useProjectWebSocket;

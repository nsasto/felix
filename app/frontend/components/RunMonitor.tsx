import React, { useState, useEffect, useCallback } from 'react';
import { useProjectWebSocket, FelixState, WebSocketEvent, RunCompleteData, IterationCompleteData } from '../hooks/useProjectWebSocket';
import { IconFelix, IconCpu } from './Icons';

interface RunMonitorProps {
  projectId: string;
  /** Compact mode for embedding in smaller spaces */
  compact?: boolean;
  /** Called when run completes */
  onRunComplete?: (data: RunCompleteData) => void;
}

interface Notification {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
  timestamp: number;
}

const RunMonitor: React.FC<RunMonitorProps> = ({ 
  projectId, 
  compact = false,
  onRunComplete 
}) => {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  
  // Handle WebSocket events
  const handleEvent = useCallback((event: WebSocketEvent) => {
    if (event.type === 'run_complete') {
      const data = event.data as RunCompleteData;
      
      // Add notification
      const notification: Notification = {
        id: `${Date.now()}`,
        type: data.final_status === 'complete' ? 'success' : 
              data.final_status === 'error' ? 'error' : 
              data.final_status === 'stopped' ? 'warning' : 'info',
        message: `Run ${data.final_status}${data.requirement_id ? ` for ${data.requirement_id}` : ''}`,
        timestamp: Date.now(),
      };
      setNotifications(prev => [...prev, notification]);
      
      // Callback
      onRunComplete?.(data);
      
      // Auto-remove notification after 5 seconds
      setTimeout(() => {
        setNotifications(prev => prev.filter(n => n.id !== notification.id));
      }, 5000);
    }
    
    if (event.type === 'iteration_complete') {
      const data = event.data as IterationCompleteData;
      if (data.outcome === 'blocked' || data.outcome === 'error') {
        const notification: Notification = {
          id: `${Date.now()}`,
          type: data.outcome === 'blocked' ? 'warning' : 'error',
          message: `Iteration ${data.iteration} ${data.outcome}${data.mode ? ` in ${data.mode} mode` : ''}`,
          timestamp: Date.now(),
        };
        setNotifications(prev => [...prev, notification]);
        
        // Auto-remove after 5 seconds
        setTimeout(() => {
          setNotifications(prev => prev.filter(n => n.id !== notification.id));
        }, 5000);
      }
    }
  }, [onRunComplete]);

  const { 
    isConnected, 
    state, 
    reconnect 
  } = useProjectWebSocket(projectId, {
    onEvent: handleEvent,
  });

  // Dismiss notification
  const dismissNotification = (id: string) => {
    setNotifications(prev => prev.filter(n => n.id !== id));
  };

  // Get status display info
  const getStatusInfo = (status: FelixState['status'] | undefined) => {
    switch (status) {
      case 'running':
        return { 
          label: 'Running', 
          color: 'text-felix-400', 
          bg: 'bg-felix-500/10 border-felix-500/20',
          dot: 'bg-felix-500 animate-pulse shadow-lg shadow-felix-500/50'
        };
      case 'complete':
        return { 
          label: 'Complete', 
          color: 'text-emerald-400', 
          bg: 'bg-emerald-500/10 border-emerald-500/20',
          dot: 'bg-emerald-500'
        };
      case 'stopped':
        return { 
          label: 'Stopped', 
          color: 'text-amber-400', 
          bg: 'bg-amber-500/10 border-amber-500/20',
          dot: 'bg-amber-500'
        };
      case 'error':
        return { 
          label: 'Error', 
          color: 'text-red-400', 
          bg: 'bg-red-500/10 border-red-500/20',
          dot: 'bg-red-500'
        };
      default:
        return { 
          label: 'Idle', 
          color: 'text-slate-400', 
          bg: 'bg-slate-800/50 border-slate-700/50',
          dot: 'bg-slate-500'
        };
    }
  };

  // Get mode display info
  const getModeInfo = (mode: FelixState['last_mode'] | undefined) => {
    switch (mode) {
      case 'planning':
        return { 
          label: 'Planning', 
          color: 'text-cyan-400', 
          bg: 'bg-cyan-500/10 border-cyan-500/20',
          icon: '📋'
        };
      case 'building':
        return { 
          label: 'Building', 
          color: 'text-amber-400', 
          bg: 'bg-amber-500/10 border-amber-500/20',
          icon: '🔨'
        };
      default:
        return { 
          label: 'None', 
          color: 'text-slate-400', 
          bg: 'bg-slate-800/50 border-slate-700/50',
          icon: '—'
        };
    }
  };

  // Get notification styles
  const getNotificationStyles = (type: Notification['type']) => {
    switch (type) {
      case 'success':
        return 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400';
      case 'error':
        return 'bg-red-500/10 border-red-500/30 text-red-400';
      case 'warning':
        return 'bg-amber-500/10 border-amber-500/30 text-amber-400';
      default:
        return 'bg-slate-800/50 border-slate-700/50 text-slate-400';
    }
  };

  const statusInfo = getStatusInfo(state?.status);
  const modeInfo = getModeInfo(state?.last_mode);

  // Compact mode - inline display
  if (compact) {
    return (
      <div className="flex items-center gap-4">
        {/* Connection indicator */}
        <div className="flex items-center gap-1.5">
          <div className={`w-1.5 h-1.5 rounded-full ${isConnected ? 'bg-emerald-500' : 'bg-red-500'}`} />
          <span className="text-[9px] font-mono text-slate-600 uppercase">
            {isConnected ? 'Live' : 'Offline'}
          </span>
        </div>

        {/* Status */}
        <div className={`flex items-center gap-1.5 px-2 py-1 rounded-lg border ${statusInfo.bg}`}>
          <div className={`w-1.5 h-1.5 rounded-full ${statusInfo.dot}`} />
          <span className={`text-[10px] font-bold uppercase ${statusInfo.color}`}>
            {statusInfo.label}
          </span>
        </div>

        {/* Mode badge */}
        {state?.status === 'running' && (
          <div className={`flex items-center gap-1.5 px-2 py-1 rounded-lg border ${modeInfo.bg}`}>
            <span className="text-xs">{modeInfo.icon}</span>
            <span className={`text-[10px] font-bold uppercase ${modeInfo.color}`}>
              {modeInfo.label}
            </span>
          </div>
        )}

        {/* Iteration counter */}
        {state?.status === 'running' && state.current_iteration > 0 && (
          <span className="text-[10px] font-mono text-slate-500">
            Iter {state.current_iteration}
          </span>
        )}
      </div>
    );
  }

  // Full mode - card display
  return (
    <div className="bg-[#161b22] border border-slate-800/60 rounded-2xl overflow-hidden relative">
      {/* Notifications overlay */}
      {notifications.length > 0 && (
        <div className="absolute top-4 right-4 z-10 flex flex-col gap-2 max-w-xs">
          {notifications.map(notification => (
            <div 
              key={notification.id}
              className={`flex items-center gap-2 px-3 py-2 rounded-xl border ${getNotificationStyles(notification.type)} shadow-lg animate-in slide-in-from-right`}
            >
              <span className="text-xs font-medium flex-1">{notification.message}</span>
              <button 
                onClick={() => dismissNotification(notification.id)}
                className="p-0.5 hover:opacity-70 transition-opacity"
              >
                <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Header */}
      <div className="px-6 py-4 border-b border-slate-800/60 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
            state?.status === 'running' ? 'bg-felix-500/20' : 'bg-slate-800'
          }`}>
            <IconCpu className={`w-5 h-5 ${
              state?.status === 'running' ? 'text-felix-400 animate-pulse' : 'text-slate-500'
            }`} />
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-200">Run Monitor</h3>
            <p className="text-[10px] font-mono text-slate-600 uppercase">
              Real-time Status
            </p>
          </div>
        </div>

        {/* Connection status */}
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-emerald-500' : 'bg-red-500'}`} />
          <span className="text-[10px] font-mono text-slate-500 uppercase">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
          {!isConnected && (
            <button 
              onClick={reconnect}
              className="ml-2 text-[10px] font-bold text-felix-400 hover:text-felix-300 transition-colors"
            >
              Reconnect
            </button>
          )}
        </div>
      </div>

      {/* Body - Status display */}
      <div className="px-6 py-6">
        <div className="grid grid-cols-2 gap-6">
          {/* Status */}
          <div className="bg-[#0d1117]/50 rounded-xl p-4 border border-slate-800/40">
            <span className="text-[9px] font-mono text-slate-600 uppercase block mb-2">
              Status
            </span>
            <div className={`flex items-center gap-2 px-3 py-2 rounded-lg border ${statusInfo.bg} w-fit`}>
              <div className={`w-2 h-2 rounded-full ${statusInfo.dot}`} />
              <span className={`text-sm font-bold uppercase ${statusInfo.color}`}>
                {statusInfo.label}
              </span>
            </div>
          </div>

          {/* Mode */}
          <div className="bg-[#0d1117]/50 rounded-xl p-4 border border-slate-800/40">
            <span className="text-[9px] font-mono text-slate-600 uppercase block mb-2">
              Mode
            </span>
            <div className={`flex items-center gap-2 px-3 py-2 rounded-lg border ${modeInfo.bg} w-fit`}>
              <span className="text-base">{modeInfo.icon}</span>
              <span className={`text-sm font-bold uppercase ${modeInfo.color}`}>
                {modeInfo.label}
              </span>
            </div>
          </div>

          {/* Iteration */}
          <div className="bg-[#0d1117]/50 rounded-xl p-4 border border-slate-800/40">
            <span className="text-[9px] font-mono text-slate-600 uppercase block mb-2">
              Current Iteration
            </span>
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-bold text-slate-200">
                {state?.current_iteration ?? 0}
              </span>
              {state?.status === 'running' && (
                <span className="text-[10px] font-mono text-slate-500 animate-pulse">
                  active
                </span>
              )}
            </div>
          </div>

          {/* Requirement */}
          <div className="bg-[#0d1117]/50 rounded-xl p-4 border border-slate-800/40">
            <span className="text-[9px] font-mono text-slate-600 uppercase block mb-2">
              Current Requirement
            </span>
            <span className="text-sm font-mono text-slate-300">
              {state?.current_requirement_id || '—'}
            </span>
          </div>
        </div>

        {/* Last outcome */}
        {state?.last_iteration_outcome && (
          <div className="mt-4 bg-[#0d1117]/50 rounded-xl p-4 border border-slate-800/40">
            <span className="text-[9px] font-mono text-slate-600 uppercase block mb-2">
              Last Iteration Outcome
            </span>
            <span className={`text-xs font-mono px-2 py-1 rounded ${
              state.last_iteration_outcome === 'success' 
                ? 'bg-emerald-500/10 text-emerald-400' 
                : state.last_iteration_outcome === 'blocked' 
                ? 'bg-amber-500/10 text-amber-400'
                : state.last_iteration_outcome === 'error'
                ? 'bg-red-500/10 text-red-400'
                : 'bg-slate-800 text-slate-400'
            }`}>
              {state.last_iteration_outcome}
            </span>
          </div>
        )}

        {/* Last run ID */}
        {state?.last_run_id && (
          <div className="mt-4 bg-[#0d1117]/50 rounded-xl p-4 border border-slate-800/40">
            <span className="text-[9px] font-mono text-slate-600 uppercase block mb-2">
              Last Run ID
            </span>
            <span className="text-xs font-mono text-slate-400 truncate block">
              {state.last_run_id}
            </span>
          </div>
        )}

        {/* Updated at */}
        {state?.updated_at && (
          <div className="mt-4 text-[10px] font-mono text-slate-600 text-right">
            Last updated: {new Date(state.updated_at).toLocaleTimeString()}
          </div>
        )}
      </div>
    </div>
  );
};

export default RunMonitor;

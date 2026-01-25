import React, { useState, useEffect, useCallback } from 'react';
import { felixApi, AgentStatus, RunHistoryEntry } from '../services/felixApi';
import { IconFelix, IconCpu } from './Icons';

interface AgentControlsProps {
  projectId: string;
  /** Called when agent status changes */
  onStatusChange?: (status: AgentStatus) => void;
  /** Compact mode for embedding in smaller spaces */
  compact?: boolean;
  /** Called when a run is selected from history */
  onSelectRun?: (runId: string) => void;
}

const AgentControls: React.FC<AgentControlsProps> = ({ 
  projectId, 
  onStatusChange,
  compact = false,
  onSelectRun 
}) => {
  const [status, setStatus] = useState<AgentStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionInProgress, setActionInProgress] = useState<'start' | 'stop' | null>(null);
  const [runs, setRuns] = useState<RunHistoryEntry[]>([]);
  const [runsLoading, setRunsLoading] = useState(false);
  const [showHistory, setShowHistory] = useState(false);

  // Fetch run history
  const fetchRunHistory = useCallback(async () => {
    if (!projectId) return;
    
    setRunsLoading(true);
    try {
      const response = await felixApi.listRuns(projectId);
      setRuns(response.runs);
    } catch (err) {
      console.error('Failed to fetch run history:', err);
    } finally {
      setRunsLoading(false);
    }
  }, [projectId]);

  // Fetch status on mount and set up polling
  const fetchStatus = useCallback(async () => {
    if (!projectId) return;
    
    try {
      const agentStatus = await felixApi.getAgentStatus(projectId);
      setStatus(agentStatus);
      setError(null);
      onStatusChange?.(agentStatus);
    } catch (err) {
      console.error('Failed to fetch agent status:', err);
      // Only set error if this is the initial load
      if (loading) {
        setError(err instanceof Error ? err.message : 'Failed to fetch agent status');
      }
    } finally {
      setLoading(false);
    }
  }, [projectId, loading, onStatusChange]);

  useEffect(() => {
    fetchStatus();
    fetchRunHistory();

    // Poll status every 5 seconds when agent is running
    const interval = setInterval(() => {
      if (status?.running) {
        fetchStatus();
        fetchRunHistory(); // Also refresh history when agent is running
      }
    }, 5000);

    return () => clearInterval(interval);
  }, [projectId]); // Only depend on projectId for initial fetch

  // Separate effect for polling when running
  useEffect(() => {
    if (!status?.running) return;
    
    const interval = setInterval(fetchStatus, 5000);
    return () => clearInterval(interval);
  }, [status?.running, fetchStatus]);

  const handleStartAgent = async () => {
    setActionInProgress('start');
    setError(null);

    try {
      const result = await felixApi.startRun(projectId);
      console.log('Agent started:', result);
      
      // Fetch updated status and run history
      await fetchStatus();
      await fetchRunHistory();
    } catch (err) {
      console.error('Failed to start agent:', err);
      setError(err instanceof Error ? err.message : 'Failed to start agent');
    } finally {
      setActionInProgress(null);
    }
  };

  const handleStopAgent = async () => {
    setActionInProgress('stop');
    setError(null);

    try {
      await felixApi.stopRun(projectId);
      console.log('Agent stopped');
      
      // Fetch updated status and run history
      await fetchStatus();
      await fetchRunHistory();
    } catch (err) {
      console.error('Failed to stop agent:', err);
      setError(err instanceof Error ? err.message : 'Failed to stop agent');
    } finally {
      setActionInProgress(null);
    }
  };

  // Format timestamp for display
  const formatTimestamp = (isoString: string | null | undefined): string => {
    if (!isoString) return '';
    try {
      const date = new Date(isoString);
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch {
      return '';
    }
  };

  // Format datetime for run history display
  const formatRunDateTime = (isoString: string): string => {
    try {
      const date = new Date(isoString);
      return date.toLocaleString([], { 
        month: 'short', 
        day: 'numeric',
        hour: '2-digit', 
        minute: '2-digit' 
      });
    } catch {
      return isoString;
    }
  };

  // Get status badge styles
  const getStatusStyles = (status: string): { bg: string; text: string; dot: string } => {
    switch (status) {
      case 'running':
        return { bg: 'bg-felix-500/10 border-felix-500/20', text: 'text-felix-400', dot: 'bg-felix-500 animate-pulse' };
      case 'completed':
        return { bg: 'bg-emerald-500/10 border-emerald-500/20', text: 'text-emerald-400', dot: 'bg-emerald-500' };
      case 'failed':
        return { bg: 'bg-red-500/10 border-red-500/20', text: 'text-red-400', dot: 'bg-red-500' };
      case 'stopped':
        return { bg: 'bg-amber-500/10 border-amber-500/20', text: 'text-amber-400', dot: 'bg-amber-500' };
      default:
        return { bg: 'bg-slate-800/50 border-slate-700/50', text: 'text-slate-400', dot: 'bg-slate-500' };
    }
  };

  if (loading) {
    return (
      <div className={`flex items-center gap-3 ${compact ? '' : 'p-4 bg-[#161b22] border border-slate-800/60 rounded-2xl'}`}>
        <div className="w-4 h-4 border-2 border-slate-600/30 border-t-slate-500 rounded-full animate-spin" />
        <span className="text-[10px] font-mono text-slate-500 uppercase">Checking agent...</span>
      </div>
    );
  }

  if (error && !status) {
    return (
      <div className={`${compact ? '' : 'p-4 bg-[#161b22] border border-slate-800/60 rounded-2xl'}`}>
        <div className="flex items-center gap-2 text-red-400">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span className="text-xs">{error}</span>
        </div>
        <button
          onClick={fetchStatus}
          className="mt-2 text-[10px] font-bold text-slate-500 hover:text-slate-300 transition-colors"
        >
          Retry
        </button>
      </div>
    );
  }

  const isRunning = status?.running ?? false;

  // Compact mode - just a small status badge with action button
  if (compact) {
    return (
      <div className="flex items-center gap-3">
        {/* Status indicator */}
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${isRunning ? 'bg-felix-500 animate-pulse' : 'bg-slate-600'}`} />
          <span className={`text-[10px] font-bold uppercase ${isRunning ? 'text-felix-400' : 'text-slate-500'}`}>
            {isRunning ? 'Running' : 'Idle'}
          </span>
        </div>

        {/* Action button */}
        {isRunning ? (
          <button
            onClick={handleStopAgent}
            disabled={actionInProgress === 'stop'}
            className="px-3 py-1.5 text-[10px] font-bold text-red-400 border border-red-500/20 rounded-lg hover:bg-red-500/10 transition-colors disabled:opacity-50"
          >
            {actionInProgress === 'stop' ? 'Stopping...' : 'Stop'}
          </button>
        ) : (
          <button
            onClick={handleStartAgent}
            disabled={actionInProgress === 'start'}
            className="px-3 py-1.5 text-[10px] font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors disabled:opacity-50"
          >
            {actionInProgress === 'start' ? 'Starting...' : 'Start'}
          </button>
        )}
      </div>
    );
  }

  // Full mode - detailed card with status and controls
  return (
    <div className="bg-[#161b22] border border-slate-800/60 rounded-2xl overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 border-b border-slate-800/60 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
            isRunning ? 'bg-felix-500/20' : 'bg-slate-800'
          }`}>
            <IconFelix className={`w-5 h-5 ${isRunning ? 'text-felix-400 animate-pulse' : 'text-slate-500'}`} />
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-200">Felix Agent</h3>
            <p className="text-[10px] font-mono text-slate-600 uppercase">
              {isRunning ? 'Agent Active' : 'Agent Idle'}
            </p>
          </div>
        </div>

        {/* Status badge */}
        <div className={`flex items-center gap-2 px-3 py-1.5 rounded-lg ${
          isRunning 
            ? 'bg-felix-500/10 border border-felix-500/20' 
            : 'bg-slate-800/50 border border-slate-700/50'
        }`}>
          <div className={`w-2 h-2 rounded-full ${
            isRunning ? 'bg-felix-500 animate-pulse shadow-lg shadow-felix-500/50' : 'bg-slate-600'
          }`} />
          <span className={`text-[10px] font-bold uppercase ${
            isRunning ? 'text-felix-400' : 'text-slate-500'
          }`}>
            {isRunning ? 'Running' : 'Stopped'}
          </span>
        </div>
      </div>

      {/* Body - Status details when running */}
      {isRunning && status && (
        <div className="px-6 py-4 border-b border-slate-800/60 bg-[#0d1117]/50">
          <div className="grid grid-cols-2 gap-4">
            {status.pid && (
              <div>
                <span className="text-[9px] font-mono text-slate-600 uppercase">Process ID</span>
                <p className="text-sm font-mono text-slate-300">{status.pid}</p>
              </div>
            )}
            {status.started_at && (
              <div>
                <span className="text-[9px] font-mono text-slate-600 uppercase">Started</span>
                <p className="text-sm font-mono text-slate-300">{formatTimestamp(status.started_at)}</p>
              </div>
            )}
            {status.current_run_id && (
              <div className="col-span-2">
                <span className="text-[9px] font-mono text-slate-600 uppercase">Run ID</span>
                <p className="text-xs font-mono text-slate-400 truncate">{status.current_run_id}</p>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Error display */}
      {error && (
        <div className="px-6 py-3 bg-red-500/10 border-b border-red-500/20">
          <div className="flex items-center gap-2 text-red-400">
            <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span className="text-xs">{error}</span>
          </div>
        </div>
      )}

      {/* Footer - Actions */}
      <div className="px-6 py-4 flex items-center justify-between border-b border-slate-800/60">
        <button
          onClick={fetchStatus}
          className="text-[10px] font-bold text-slate-500 hover:text-slate-300 transition-colors flex items-center gap-1.5"
        >
          <IconCpu className="w-3 h-3" />
          Refresh Status
        </button>

        {isRunning ? (
          <button
            onClick={handleStopAgent}
            disabled={actionInProgress === 'stop'}
            className="px-4 py-2 text-xs font-bold text-red-400 border border-red-500/20 rounded-xl hover:bg-red-500/10 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            {actionInProgress === 'stop' ? (
              <>
                <div className="w-3 h-3 border-2 border-red-400/30 border-t-red-400 rounded-full animate-spin" />
                Stopping...
              </>
            ) : (
              <>
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
                </svg>
                Stop Agent
              </>
            )}
          </button>
        ) : (
          <button
            onClick={handleStartAgent}
            disabled={actionInProgress === 'start'}
            className="px-4 py-2 text-xs font-bold text-white bg-felix-600 hover:bg-felix-500 rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2 shadow-lg shadow-felix-900/30"
          >
            {actionInProgress === 'start' ? (
              <>
                <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                Starting...
              </>
            ) : (
              <>
                <IconFelix className="w-4 h-4" />
                Start Agent
              </>
            )}
          </button>
        )}
      </div>

      {/* Run History Section */}
      <div className="px-6 py-4">
        <button
          onClick={() => {
            setShowHistory(!showHistory);
            if (!showHistory && runs.length === 0) {
              fetchRunHistory();
            }
          }}
          className="w-full flex items-center justify-between text-left group"
        >
          <div className="flex items-center gap-2">
            <svg 
              className={`w-4 h-4 text-slate-500 transition-transform duration-200 ${showHistory ? 'rotate-90' : ''}`}
              fill="none" 
              stroke="currentColor" 
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5l7 7-7 7" />
            </svg>
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wider group-hover:text-slate-300 transition-colors">
              Run History
            </span>
            {runs.length > 0 && (
              <span className="text-[9px] font-mono text-slate-600 bg-slate-800 px-1.5 py-0.5 rounded">
                {runs.length}
              </span>
            )}
          </div>
          {runsLoading && (
            <div className="w-3 h-3 border-2 border-slate-600/30 border-t-slate-500 rounded-full animate-spin" />
          )}
        </button>

        {/* Expandable run history list */}
        {showHistory && (
          <div className="mt-4 space-y-2 max-h-64 overflow-y-auto custom-scrollbar">
            {runs.length === 0 ? (
              <div className="text-center py-6 text-slate-600">
                <svg className="w-8 h-8 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <p className="text-[10px] font-mono uppercase">No runs yet</p>
              </div>
            ) : (
              runs.map((run) => {
                const styles = getStatusStyles(run.status);
                return (
                  <button
                    key={run.run_id}
                    onClick={() => onSelectRun?.(run.run_id)}
                    className={`w-full flex items-center justify-between p-3 bg-[#0d1117]/50 border border-slate-800/60 rounded-xl hover:border-felix-600/40 transition-all text-left group ${
                      onSelectRun ? 'cursor-pointer' : 'cursor-default'
                    }`}
                  >
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xs font-mono text-slate-300 truncate">
                          {run.run_id}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 text-[10px] text-slate-600">
                        <span>{formatRunDateTime(run.started_at)}</span>
                        {run.ended_at && (
                          <>
                            <span>→</span>
                            <span>{formatTimestamp(run.ended_at)}</span>
                          </>
                        )}
                      </div>
                    </div>
                    <div className={`flex items-center gap-1.5 px-2 py-1 rounded-lg border ${styles.bg}`}>
                      <div className={`w-1.5 h-1.5 rounded-full ${styles.dot}`} />
                      <span className={`text-[9px] font-bold uppercase ${styles.text}`}>
                        {run.status}
                      </span>
                    </div>
                  </button>
                );
              })
            )}
          </div>
        )}
      </div>
    </div>
  );
};

export default AgentControls;

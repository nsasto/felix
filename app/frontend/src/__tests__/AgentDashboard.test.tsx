import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';
import AgentDashboard from '../../components/AgentDashboard';
import { ThemeProvider } from '../../hooks/ThemeProvider';
import { felixApi } from '../../services/felixApi';

// Mock the felixApi module (legacy API)
vi.mock('../../services/felixApi', () => ({
  felixApi: {
    getAgentsConfig: vi.fn(),
    getAgents: vi.fn(),
    getRequirements: vi.fn(),
    listRuns: vi.fn(),
    startAgentWithRequirement: vi.fn(),
    stopAgent: vi.fn(),
    // S-0030: WorkflowVisualization uses this when rendered inside LiveConsolePanel
    getWorkflowConfig: vi.fn(),
  },
}));

// Mock the new API client module (S-0042: database-backed API)
vi.mock('../api/client', () => ({
  listAgents: vi.fn(),
  listRuns: vi.fn(),
  createRun: vi.fn(),
  stopRun: vi.fn(),
}));

// Import the mocked new API client
import * as apiClient from '../api/client';

// Helper to render with ThemeProvider
const renderWithTheme = (ui: React.ReactElement) => {
  return render(
    <ThemeProvider defaultTheme="dark">
      {ui}
    </ThemeProvider>
  );
};

describe('AgentDashboard (S-0021: Agent Orchestration Enhancement)', () => {
  const mockProjectId = 'test-project';

  // Mock configured agents from agents.json
  const mockConfiguredAgents = {
    agents: [
      {
        id: 0,
        name: 'felix-primary',
        executable: 'droid',
        args: ['exec', '--skip-permissions-unsafe'],
        working_directory: '.',
        environment: {},
      },
      {
        id: 1,
        name: 'test-agent',
        executable: 'claude',
        args: ['--model', 'opus'],
        working_directory: '.',
        environment: {},
      },
    ],
  };

  // Mock runtime agents registry - keyed by agent ID (number), not name
  const mockRuntimeAgents = {
    agents: {
      0: {
        agent_id: 0,
        agent_name: 'felix-primary',
        pid: 12345,
        hostname: 'localhost',
        status: 'active' as const,
        current_run_id: 'S-0001',
        started_at: new Date().toISOString(),
        last_heartbeat: new Date().toISOString(),
        stopped_at: null,
      },
    },
  };

  // Mock requirements
  const mockRequirements = {
    requirements: [
      { id: 'S-0001', title: 'Test Requirement', status: 'planned', priority: 'high', tags: [], depends_on: [], spec_path: '', updated_at: '' },
    ],
  };

  // Mock runs
  const mockRuns = {
    runs: [],
    total: 0,
    project_id: mockProjectId,
  };

  // Mock workflow config for WorkflowVisualization component (S-0030)
  const mockWorkflowConfig = {
    version: '1.0',
    layout: 'horizontal' as const,
    stages: [
      { id: 'select_requirement', name: 'Select', icon: 'target', description: 'Select requirement', order: 1 },
      { id: 'execute_llm', name: 'LLM', icon: 'cpu', description: 'Execute LLM', order: 6 },
    ],
  };

  // Mock data for new database-backed API (S-0042)
  const mockDbAgents = {
    agents: [],
    count: 0,
  };

  const mockDbRuns = {
    runs: [],
    count: 0,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(felixApi.getAgentsConfig).mockResolvedValue(mockConfiguredAgents);
    vi.mocked(felixApi.getAgents).mockResolvedValue(mockRuntimeAgents);
    vi.mocked(felixApi.getRequirements).mockResolvedValue(mockRequirements);
    vi.mocked(felixApi.listRuns).mockResolvedValue(mockRuns);
    vi.mocked(felixApi.getWorkflowConfig).mockResolvedValue(mockWorkflowConfig);
    // S-0042: Mock new API client functions
    vi.mocked(apiClient.listAgents).mockResolvedValue(mockDbAgents);
    vi.mocked(apiClient.listRuns).mockResolvedValue(mockDbRuns);
  });

  describe('Agent List Data Source Merge', () => {
    it('loads configured agents from /api/agents/config', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        expect(felixApi.getAgentsConfig).toHaveBeenCalled();
      });
    });

    it('loads runtime agents from /api/agents', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalled();
      });
    });

    it('merges configured agents with runtime status', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for the agents list to load - use getAllByText since the agent name appears in multiple places
      await waitFor(() => {
        const felixPrimaryElements = screen.getAllByText('felix-primary');
        expect(felixPrimaryElements.length).toBeGreaterThan(0);
      }, { timeout: 2000 });

      // Also verify test-agent is displayed
      await waitFor(() => {
        expect(screen.getByText('test-agent')).toBeInTheDocument();
      }, { timeout: 2000 });
    });

    it('shows not-started status for agents without runtime entry', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // test-agent (id: 1) has no runtime entry, should show "Ready to start" text
        // Only one agent (test-agent) should show this since felix-primary has runtime entry
        const readyElements = screen.getAllByText('Ready to start');
        expect(readyElements.length).toBe(1);
      });
    });
  });

  describe('Agent List Grouping', () => {
    it('displays Available Agents section for not-started agents', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // test-agent should be in Available section
        expect(screen.getByText(/Available/)).toBeInTheDocument();
      });
    });

    it('displays Active Agents section for active/stale agents', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // felix-primary should be in Active section
        expect(screen.getByText(/Active/)).toBeInTheDocument();
      });
    });
  });

  describe('Status Icon Display', () => {
    it('shows gray dot for not-started agents', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show the gray dot (⚫) for not-started status
        // Only test-agent (id: 1) should show this, so expect exactly one
        const notStartedIcons = screen.getAllByTitle('Not Started');
        expect(notStartedIcons.length).toBe(1);
      });
    });

    it('shows green dot for active agents', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show the green dot (🟢) for active status
        // Only felix-primary (id: 0) should show this, so expect exactly one
        const activeIcons = screen.getAllByTitle('Active');
        expect(activeIcons.length).toBe(1);
      });
    });
  });

  describe('Empty State', () => {
    it('shows "No agents configured" when agents list is empty', async () => {
      vi.mocked(felixApi.getAgentsConfig).mockResolvedValue({ agents: [] });
      vi.mocked(felixApi.getAgents).mockResolvedValue({ agents: {} });

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('No agents configured')).toBeInTheDocument();
      });
    });
  });

  describe('Graceful Fallback', () => {
    it('falls back to empty list when /api/agents/config fails', async () => {
      vi.mocked(felixApi.getAgentsConfig).mockRejectedValue(new Error('Config not found'));
      vi.mocked(felixApi.getAgents).mockResolvedValue(mockRuntimeAgents);

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show "No agents configured" when config fetch fails
        expect(screen.getByText('No agents configured')).toBeInTheDocument();
      });
    });
  });

  // S-0042: Tests for live polling (restored from S-0033 which removed polling)
  describe('Live Polling Indicator (S-0042: Polling Restored)', () => {
    it('shows "Live" indicator in toolbar', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show the live polling indicator
        expect(screen.getByText('Live')).toBeInTheDocument();
      });
    });

    it('live indicator has correct tooltip', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Find the wrapper div that has the title attribute
        const indicator = screen.getByText('Live').closest('div[title]');
        expect(indicator).toHaveAttribute(
          'title',
          'Auto-refresh every 3 seconds'
        );
      });
    });

    it('refresh button triggers data fetch', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Live')).toBeInTheDocument();
      });

      // Clear mocks after initial fetch
      vi.mocked(felixApi.getAgents).mockClear();
      vi.mocked(felixApi.getAgentsConfig).mockClear();

      // Click refresh button
      const refreshButton = screen.getByTitle('Refresh');
      await act(async () => {
        fireEvent.click(refreshButton);
      });

      // Should have triggered a fetch
      await waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalledTimes(1);
      });
    });

    it('component handles fetch errors gracefully', async () => {
      // Make API fail
      vi.mocked(felixApi.getAgents).mockRejectedValue(new Error('Network error'));

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Component should still render even with fetch error
      // The Live indicator should still be visible
      await waitFor(() => {
        expect(screen.getByText('Live')).toBeInTheDocument();
      });
    });

    it('refresh button works and retries after error', async () => {
      // First call fails, subsequent calls succeed
      vi.mocked(felixApi.getAgents)
        .mockRejectedValueOnce(new Error('Network error'))
        .mockResolvedValue(mockRuntimeAgents);

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for component to render (initial fetch failed)
      await waitFor(() => {
        expect(screen.getByText('Live')).toBeInTheDocument();
      });

      // Click refresh to retry
      const refreshButton = screen.getByTitle('Refresh');
      await act(async () => {
        fireEvent.click(refreshButton);
      });

      // Second call should have been made (retry after error)
      await waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalledTimes(2);
      });
    });
  });

  // S-0042: Tests for polling mechanism
  describe('Polling Mechanism (S-0042)', () => {
    beforeEach(() => {
      vi.useFakeTimers({ shouldAdvanceTime: true });
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('polls agents every 3 seconds', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial fetch to complete
      await vi.waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalled();
      });

      // Clear mocks after initial fetch
      vi.mocked(felixApi.getAgents).mockClear();
      vi.mocked(apiClient.listAgents).mockClear();

      // Advance timer by 3 seconds (polling interval)
      await act(async () => {
        vi.advanceTimersByTime(3000);
      });

      // Should have triggered polling fetches
      await vi.waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalled();
      });
      await vi.waitFor(() => {
        expect(apiClient.listAgents).toHaveBeenCalled();
      });
    });

    it('polls runs every 3 seconds', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial fetch
      await vi.waitFor(() => {
        expect(apiClient.listRuns).toHaveBeenCalled();
      });

      // Clear mocks after initial fetch
      vi.mocked(apiClient.listRuns).mockClear();

      // Advance timer by 3 seconds (polling interval)
      await act(async () => {
        vi.advanceTimersByTime(3000);
      });

      // Should have triggered runs polling
      await vi.waitFor(() => {
        expect(apiClient.listRuns).toHaveBeenCalled();
      });
    });

    it('calls listRuns with limit of 20', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial fetch
      await vi.waitFor(() => {
        expect(apiClient.listRuns).toHaveBeenCalledWith(20);
      });
    });
  });
});


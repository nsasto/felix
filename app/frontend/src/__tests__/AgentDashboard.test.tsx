import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import AgentDashboard from '../../components/AgentDashboard';
import { ThemeProvider } from '../../hooks/ThemeProvider';
import { felixApi } from '../../services/felixApi';

// Mock the felixApi module
vi.mock('../../services/felixApi', () => ({
  felixApi: {
    getAgentsConfig: vi.fn(),
    getAgents: vi.fn(),
    getRequirements: vi.fn(),
    listRuns: vi.fn(),
    startAgentWithRequirement: vi.fn(),
    stopAgent: vi.fn(),
  },
}));

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

  // Mock runtime agents registry
  const mockRuntimeAgents = {
    agents: {
      'felix-primary': {
        pid: 12345,
        hostname: 'localhost',
        status: 'active',
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
      { id: 'S-0001', title: 'Test Requirement', status: 'planned', priority: 'high', labels: [], depends_on: [], spec_path: '', updated_at: '' },
    ],
  };

  // Mock runs
  const mockRuns = {
    runs: [],
    total: 0,
    project_id: mockProjectId,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(felixApi.getAgentsConfig).mockResolvedValue(mockConfiguredAgents);
    vi.mocked(felixApi.getAgents).mockResolvedValue(mockRuntimeAgents);
    vi.mocked(felixApi.getRequirements).mockResolvedValue(mockRequirements);
    vi.mocked(felixApi.listRuns).mockResolvedValue(mockRuns);
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
        // test-agent has no runtime entry, should show "Ready to start" text
        expect(screen.getByText('Ready to start')).toBeInTheDocument();
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
        expect(screen.getByTitle('Not Started')).toBeInTheDocument();
      });
    });

    it('shows green dot for active agents', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show the green dot (🟢) for active status
        expect(screen.getByTitle('Active')).toBeInTheDocument();
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
});

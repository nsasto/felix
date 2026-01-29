import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';
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

// Storage key constant - must match the one in AgentDashboard.tsx
const POLLING_MODE_STORAGE_KEY = 'felix_agent_polling_mode';

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
        agent_name: 'felix-primary',
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
});

// S-0023: Polling Mode Toggle Tests
describe('AgentDashboard (S-0023: Polling Mode Toggle)', () => {
  const mockProjectId = 'test-project';

  // Mock data (reused from S-0021 tests)
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
    ],
  };

  const mockRuntimeAgents = {
    agents: {
      0: {
        agent_name: 'felix-primary',
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

  const mockRequirements = {
    requirements: [
      { id: 'S-0001', title: 'Test Requirement', status: 'planned', priority: 'high', labels: [], depends_on: [], spec_path: '', updated_at: '' },
    ],
  };

  const mockRuns = {
    runs: [],
    total: 0,
    project_id: mockProjectId,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    // Clear localStorage before each test
    localStorage.removeItem(POLLING_MODE_STORAGE_KEY);
    vi.mocked(felixApi.getAgentsConfig).mockResolvedValue(mockConfiguredAgents);
    vi.mocked(felixApi.getAgents).mockResolvedValue(mockRuntimeAgents);
    vi.mocked(felixApi.getRequirements).mockResolvedValue(mockRequirements);
    vi.mocked(felixApi.listRuns).mockResolvedValue(mockRuns);
  });

  afterEach(() => {
    localStorage.removeItem(POLLING_MODE_STORAGE_KEY);
  });

  describe('Initial State and localStorage', () => {
    it('defaults to live mode when localStorage is empty', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show "Live Polling Active" badge
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });
    });

    it('loads manual mode from localStorage on mount', async () => {
      // Set manual mode in localStorage before rendering
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show "Manual Polling Mode" badge
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });
    });

    it('loads live mode from localStorage on mount', async () => {
      // Set live mode explicitly in localStorage
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'live');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should show "Live Polling Active" badge
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });
    });

    it('defaults to live mode when localStorage has invalid value', async () => {
      // Set an invalid value in localStorage
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'invalid-value');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        // Should default to "Live Polling Active" badge
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });
    });
  });

  describe('Badge Toggle Functionality', () => {
    it('toggles from live to manual mode when badge is clicked', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render with live mode
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Click the badge to toggle
      const badge = screen.getByText('Live Polling Active').closest('button');
      expect(badge).toBeInTheDocument();
      
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Should now show "Manual Polling Mode"
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });
    });

    it('toggles from manual to live mode when badge is clicked', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render with manual mode
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Click the badge to toggle
      const badge = screen.getByText('Manual Polling Mode').closest('button');
      expect(badge).toBeInTheDocument();
      
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Should now show "Live Polling Active"
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });
    });

    it('persists mode change to localStorage', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Click to toggle to manual
      const badge = screen.getByText('Live Polling Active').closest('button');
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Verify localStorage was updated
      await waitFor(() => {
        expect(localStorage.getItem(POLLING_MODE_STORAGE_KEY)).toBe('manual');
      });

      // Toggle back to live
      const manualBadge = screen.getByText('Manual Polling Mode').closest('button');
      await act(async () => {
        fireEvent.click(manualBadge!);
      });

      // Verify localStorage was updated again
      await waitFor(() => {
        expect(localStorage.getItem(POLLING_MODE_STORAGE_KEY)).toBe('live');
      });
    });
  });

  describe('Badge Accessibility', () => {
    it('has correct aria-label for live mode', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        const badge = screen.getByRole('button', { name: /Polling mode: Live Polling Active/i });
        expect(badge).toBeInTheDocument();
      });
    });

    it('has correct aria-label for manual mode', async () => {
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        const badge = screen.getByRole('button', { name: /Polling mode: Manual Polling Mode/i });
        expect(badge).toBeInTheDocument();
      });
    });

    it('has tooltip indicating click to toggle', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      await waitFor(() => {
        const badge = screen.getByText('Live Polling Active').closest('button');
        expect(badge).toHaveAttribute('title', 'Click to toggle polling mode');
      });
    });
  });

  describe('Refresh Button Behavior', () => {
    it('refresh button triggers data fetch in manual mode', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Clear mock calls
      vi.mocked(felixApi.getAgents).mockClear();
      vi.mocked(felixApi.getAgentsConfig).mockClear();

      // Find and click refresh button (title is "Refresh", not "Refresh data")
      const refreshButton = screen.getByTitle('Refresh');
      await act(async () => {
        fireEvent.click(refreshButton);
      });

      // Should have fetched agents after refresh
      await waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalled();
      });
    });

    it('refresh button triggers data fetch in live mode', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Clear mock calls
      vi.mocked(felixApi.getAgents).mockClear();
      vi.mocked(felixApi.getAgentsConfig).mockClear();

      // Find and click refresh button (title is "Refresh", not "Refresh data")
      const refreshButton = screen.getByTitle('Refresh');
      await act(async () => {
        fireEvent.click(refreshButton);
      });

      // Should have fetched agents after refresh
      await waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalled();
      });
    });
  });
});

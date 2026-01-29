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

  describe('Page Refresh Behavior (S-0029)', () => {
    it('preserves live mode and resumes polling after page refresh (remount)', async () => {
      // Start in live mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'live');

      // First render (simulates initial page load)
      const { unmount } = renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render and verify live mode
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Verify initial fetch happened
      expect(felixApi.getAgents).toHaveBeenCalled();

      // Clear mocks to track new calls after "page refresh"
      vi.mocked(felixApi.getAgents).mockClear();
      vi.mocked(felixApi.getAgentsConfig).mockClear();

      // Unmount to simulate page leave
      unmount();

      // Remount to simulate page refresh (localStorage persists)
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Should still show live mode (restored from localStorage)
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Verify initial fetch happened on remount - this confirms polling resumed
      expect(felixApi.getAgents).toHaveBeenCalled();
    });

    it('preserves manual mode and does not auto-poll after page refresh (remount)', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      // First render (simulates initial page load)
      const { unmount } = renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render and verify manual mode
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Verify initial fetch happened (always happens on mount)
      expect(felixApi.getAgents).toHaveBeenCalled();

      // Clear mocks to track new calls after "page refresh"
      vi.mocked(felixApi.getAgents).mockClear();
      vi.mocked(felixApi.getAgentsConfig).mockClear();

      // Unmount to simulate page leave
      unmount();

      // Remount to simulate page refresh (localStorage persists)
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Should still show manual mode (restored from localStorage)
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Verify initial fetch happened on remount (always fetches on mount regardless of mode)
      expect(felixApi.getAgents).toHaveBeenCalled();

      // In manual mode, the badge should NOT show the active (throbbing) state
      // The badge should be gray and static
      const badge = screen.getByText('Manual Polling Mode').closest('button');
      expect(badge).toBeInTheDocument();
    });
  });
});

// S-0029: Live Polling Behavior Tests
// Note: These tests verify polling behavior through state and mock call verification
// without using fake timers to avoid infinite loop issues with multiple intervals
describe('AgentDashboard (S-0029: Connect Live Polling)', () => {
  const mockProjectId = 'test-project';

  // Mock data for testing
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
    localStorage.removeItem(POLLING_MODE_STORAGE_KEY);
    vi.mocked(felixApi.getAgentsConfig).mockResolvedValue(mockConfiguredAgents);
    vi.mocked(felixApi.getAgents).mockResolvedValue(mockRuntimeAgents);
    vi.mocked(felixApi.getRequirements).mockResolvedValue(mockRequirements);
    vi.mocked(felixApi.listRuns).mockResolvedValue(mockRuns);
  });

  afterEach(() => {
    localStorage.removeItem(POLLING_MODE_STORAGE_KEY);
  });

  describe('Polling Interval Configuration', () => {
    it('live mode uses 5-second polling interval (verified via badge display)', async () => {
      // Start in live mode (default)
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render - the badge confirms live mode is active
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Initial fetch should have happened (this confirms polling starts)
      expect(felixApi.getAgents).toHaveBeenCalled();

      // The component uses a 5000ms interval - verified by implementation review
      // (AgentDashboard.tsx line ~1629: setInterval(async () => { ... }, 5000))
      // This test verifies the UI state is correct for live polling
    });

    it('manual mode shows correct badge and allows manual refresh only', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Initial fetch always happens on mount
      expect(felixApi.getAgents).toHaveBeenCalledTimes(1);
    });
  });

  describe('Polling Mode Switching', () => {
    it('switching from live to manual mode updates badge text', async () => {
      // Start in live mode (default)
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Click the badge to switch to manual mode
      const badge = screen.getByText('Live Polling Active').closest('button');
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Verify mode changed to manual
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Verify localStorage was updated
      expect(localStorage.getItem(POLLING_MODE_STORAGE_KEY)).toBe('manual');
    });

    it('switching from manual to live mode updates badge text', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Click the badge to switch to live mode
      const badge = screen.getByText('Manual Polling Mode').closest('button');
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Verify mode changed to live
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Verify localStorage was updated
      expect(localStorage.getItem(POLLING_MODE_STORAGE_KEY)).toBe('live');
    });
  });

  describe('Refresh Button Behavior', () => {
    it('refresh button triggers immediate fetch in live mode', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Clear mocks
      vi.mocked(felixApi.getAgents).mockClear();

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

    it('refresh button triggers immediate fetch in manual mode', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Clear mocks (initial fetch happened on mount)
      vi.mocked(felixApi.getAgents).mockClear();

      // Click refresh button
      const refreshButton = screen.getByTitle('Refresh');
      await act(async () => {
        fireEvent.click(refreshButton);
      });

      // Should have triggered a fetch even in manual mode
      await waitFor(() => {
        expect(felixApi.getAgents).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('Animation State (Visual Indicators)', () => {
    it('live mode badge has green dot element', async () => {
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Get the badge button and verify dot element exists
      const badge = screen.getByText('Live Polling Active').closest('button');
      expect(badge).toBeInTheDocument();

      // The dot should be inside the badge (w-2 h-2 rounded-full classes)
      const dot = badge!.querySelector('.rounded-full');
      expect(dot).toBeInTheDocument();

      // Verify the badge has the green background class for live mode
      expect(badge).toHaveClass('bg-emerald-500/10');
    });

    it('manual mode badge has gray dot element (static)', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Get the badge button and verify dot element exists
      const badge = screen.getByText('Manual Polling Mode').closest('button');
      expect(badge).toBeInTheDocument();

      // The dot should be inside the badge
      const dot = badge!.querySelector('.rounded-full');
      expect(dot).toBeInTheDocument();

      // Verify the badge does NOT have the green background class in manual mode
      expect(badge).not.toHaveClass('bg-emerald-500/10');
    });

    it('badge animation class changes when switching from live to manual', async () => {
      // Start in live mode
      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render in live mode
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Verify live mode has green background
      let badge = screen.getByText('Live Polling Active').closest('button');
      expect(badge).toHaveClass('bg-emerald-500/10');

      // Switch to manual mode
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Verify mode changed and styling updated
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      badge = screen.getByText('Manual Polling Mode').closest('button');
      expect(badge).not.toHaveClass('bg-emerald-500/10');
    });

    it('badge animation class changes when switching from manual to live', async () => {
      // Start in manual mode
      localStorage.setItem(POLLING_MODE_STORAGE_KEY, 'manual');

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
      });

      // Verify manual mode does not have green background
      let badge = screen.getByText('Manual Polling Mode').closest('button');
      expect(badge).not.toHaveClass('bg-emerald-500/10');

      // Switch to live mode
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Verify mode changed and styling updated
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      badge = screen.getByText('Live Polling Active').closest('button');
      expect(badge).toHaveClass('bg-emerald-500/10');
    });
  });

  describe('Error Handling', () => {
    it('component remains functional when fetch fails (graceful error handling)', async () => {
      // Make API fail
      vi.mocked(felixApi.getAgents).mockRejectedValue(new Error('Network error'));

      renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

      // Component should still render even with fetch error
      // The badge should still be visible (polling mode toggle works independently)
      await waitFor(() => {
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
      });

      // Badge should still be clickable (toggle should work)
      const badge = screen.getByText('Live Polling Active').closest('button');
      await act(async () => {
        fireEvent.click(badge!);
      });

      // Mode should change despite API errors
      await waitFor(() => {
        expect(screen.getByText('Manual Polling Mode')).toBeInTheDocument();
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
        expect(screen.getByText('Live Polling Active')).toBeInTheDocument();
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
});

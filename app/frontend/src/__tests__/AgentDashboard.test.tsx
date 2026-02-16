import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, fireEvent, act } from "@testing-library/react";
import AgentDashboard from "../../components/AgentDashboard";
import { ThemeProvider } from "../../hooks/ThemeProvider";
import { felixApi } from "../../services/felixApi";

vi.mock("../../services/felixApi", () => ({
  felixApi: {
    getRequirements: vi.fn(),
    startAgentWithRequirement: vi.fn(),
    stopAgent: vi.fn(),
    getWorkflowConfig: vi.fn(),
  },
}));

vi.mock("../api/client", () => ({
  listAgents: vi.fn(),
  listRuns: vi.fn(),
  createRun: vi.fn(),
  stopRun: vi.fn(),
}));

import * as apiClient from "../api/client";

const renderWithTheme = (ui: React.ReactElement) => {
  return render(<ThemeProvider defaultTheme="dark">{ui}</ThemeProvider>);
};

describe("AgentDashboard (database-backed agents)", () => {
  const mockProjectId = "test-project";
  const nowIso = new Date().toISOString();

  const mockRequirements = {
    requirements: [
      {
        id: "S-0001",
        title: "Test Requirement",
        status: "planned",
        priority: "high",
        tags: [],
        depends_on: [],
        spec_path: "",
        updated_at: "",
      },
    ],
  };

  const mockDbAgents = {
    agents: [
      {
        id: "agent-0",
        project_id: mockProjectId,
        name: "felix-primary",
        type: "ralph",
        status: "running",
        heartbeat_at: nowIso,
        metadata: { hostname: "localhost" },
        created_at: nowIso,
        updated_at: nowIso,
      },
      {
        id: "agent-1",
        project_id: "org-project-2",
        name: "test-agent",
        type: "builder",
        status: "idle",
        heartbeat_at: null,
        metadata: {},
        created_at: nowIso,
        updated_at: nowIso,
      },
    ],
    count: 2,
  };

  const mockDbRuns = {
    runs: [],
    count: 0,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(felixApi.getRequirements).mockResolvedValue(mockRequirements);
    vi.mocked(apiClient.listAgents).mockResolvedValue(mockDbAgents);
    vi.mocked(apiClient.listRuns).mockResolvedValue(mockDbRuns);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("loads agents with project scope by default", async () => {
    renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

    await waitFor(() => {
      expect(apiClient.listAgents).toHaveBeenCalledWith({
        scope: "project",
        projectId: mockProjectId,
      });
    });
  });

  it("renders agents in the table", async () => {
    renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

    await waitFor(() => {
      expect(screen.getByText("felix-primary")).toBeInTheDocument();
    });

    expect(screen.getByText("test-agent")).toBeInTheDocument();
  });

  it("shows empty state when no agents are returned", async () => {
    vi.mocked(apiClient.listAgents).mockResolvedValueOnce({ agents: [], count: 0 });

    renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

    await waitFor(() => {
      expect(screen.getByText("No agents found")).toBeInTheDocument();
    });
  });

  it("refresh button triggers agent reload", async () => {
    renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

    await waitFor(() => {
      expect(screen.getByText("Agent Fleet")).toBeInTheDocument();
    });

    vi.mocked(apiClient.listAgents).mockClear();
    fireEvent.click(screen.getByText("Refresh"));

    await waitFor(() => {
      expect(apiClient.listAgents).toHaveBeenCalled();
    });
  });

  it("polls agents and runs every 3 seconds", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    renderWithTheme(<AgentDashboard projectId={mockProjectId} />);

    await waitFor(() => {
      expect(apiClient.listAgents).toHaveBeenCalled();
    });
    await waitFor(() => {
      expect(apiClient.listRuns).toHaveBeenCalledWith(20);
    });

    vi.mocked(apiClient.listAgents).mockClear();
    vi.mocked(apiClient.listRuns).mockClear();

    await act(async () => {
      vi.advanceTimersByTime(3000);
    });

    await waitFor(() => {
      expect(apiClient.listAgents).toHaveBeenCalled();
    });
    await waitFor(() => {
      expect(apiClient.listRuns).toHaveBeenCalled();
    });
  });
});

import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor, fireEvent } from "@testing-library/react";
import App from "../../App";
import { ThemeProvider } from "../../hooks/ThemeProvider";
import { felixApi } from "../../services/felixApi";

vi.mock("../../services/felixApi", () => ({
  felixApi: {
    healthCheck: vi.fn(),
    getUserProfile: vi.fn(),
    getProject: vi.fn(),
    listOrganizations: vi.fn(),
    getActiveOrgId: vi.fn(),
    setActiveOrgId: vi.fn(),
  },
}));

vi.mock("../../components/ProjectSelector", () => ({
  default: () => <div>ProjectSelector</div>,
}));

vi.mock("../../components/ProjectDashboard", () => ({
  default: ({ projectId }: { projectId: string }) => (
    <div>ProjectDashboard {projectId}</div>
  ),
}));

vi.mock("../../components/views/KanbanView", () => ({
  default: () => <div>KanbanView</div>,
}));

vi.mock("../../components/views/SpecsView", () => ({
  default: () => <div>SpecsView</div>,
}));

vi.mock("../../components/views/OrchestrationView", () => ({
  default: () => <div>OrchestrationView</div>,
}));

vi.mock("../../components/views/SettingsView", () => ({
  default: () => <div>SettingsView</div>,
}));

const renderWithTheme = () =>
  render(
    <ThemeProvider defaultTheme="dark">
      <App />
    </ThemeProvider>,
  );

const mockProjectDetails = {
  id: "proj123",
  path: "C:\\dev\\felix",
  name: "AuthBase",
  registered_at: new Date().toISOString(),
  has_specs: false,
  has_plan: false,
  has_requirements: false,
  spec_count: 0,
  status: "planned",
};

describe("App URL routing", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(felixApi.healthCheck).mockResolvedValue({
      status: "ok",
      service: "felix",
      version: "test",
    });
    vi.mocked(felixApi.getUserProfile).mockResolvedValue({
      user_id: "user-1",
      email: "user@example.com",
      organization: "UntrueAxioms",
      org_slug: "untrueaxioms",
      org_id: "org-1",
      role: "admin",
    });
    vi.mocked(felixApi.listOrganizations).mockResolvedValue([
      {
        id: "org-1",
        name: "UntrueAxioms",
        slug: "untrueaxioms",
        role: "admin",
      },
    ]);
    vi.mocked(felixApi.getActiveOrgId).mockReturnValue(null);
    vi.mocked(felixApi.getProject).mockResolvedValue(mockProjectDetails);
  });

  it("shows only the org breadcrumb on the project list route", async () => {
    window.history.pushState({}, "", "/org/untrueaxioms");
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getByText("UntrueAxioms")).toBeInTheDocument();
    });

    expect(screen.queryByText("Project Overview")).not.toBeInTheDocument();
  });

  it("loads project details from the URL and shows the project crumb", async () => {
    window.history.pushState(
      {},
      "",
      "/org/untrueaxioms/projects/proj123/overview",
    );
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getAllByText("AuthBase").length).toBeGreaterThan(0);
    });

    await waitFor(() => {
      expect(window.location.pathname).toBe(
        "/org/untrueaxioms/projects/proj123/overview",
      );
    });
  });

  it("navigates to overview when the project crumb is clicked", async () => {
    window.history.pushState(
      {},
      "",
      "/org/untrueaxioms/projects/proj123/kanban",
    );
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getAllByText("AuthBase").length).toBeGreaterThan(0);
    });

    expect(window.location.pathname).toBe(
      "/org/untrueaxioms/projects/proj123/kanban",
    );

    fireEvent.click(
      screen.getByRole("button", { name: /AuthBase/i }),
    );

    await waitFor(() => {
      expect(window.location.pathname).toBe(
        "/org/untrueaxioms/projects/proj123/overview",
      );
    });
  });

  it("renders the kanban view for the kanban route", async () => {
    window.history.pushState(
      {},
      "",
      "/org/untrueaxioms/projects/proj123/kanban",
    );
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getByText("KanbanView")).toBeInTheDocument();
    });
  });

  it("renders the specs view for the specifications route", async () => {
    window.history.pushState(
      {},
      "",
      "/org/untrueaxioms/projects/proj123/specifications",
    );
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getByText("SpecsView")).toBeInTheDocument();
    });
  });

  it("renders the orchestration view for the orchestration route", async () => {
    window.history.pushState(
      {},
      "",
      "/org/untrueaxioms/projects/proj123/orchestration",
    );
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getByText("OrchestrationView")).toBeInTheDocument();
    });
  });

  it("switches views when sidebar items are clicked", async () => {
    window.history.pushState(
      {},
      "",
      "/org/untrueaxioms/projects/proj123/overview",
    );
    renderWithTheme();

    await waitFor(() => {
      expect(screen.getAllByText("AuthBase").length).toBeGreaterThan(0);
    });

    fireEvent.click(
      screen.getByRole("button", { name: "Specifications" }),
    );
    await waitFor(() => {
      expect(screen.getByText("SpecsView")).toBeInTheDocument();
      expect(window.location.pathname).toBe(
        "/org/untrueaxioms/projects/proj123/specifications",
      );
    });

    fireEvent.click(
      screen.getByRole("button", { name: "Orchestration" }),
    );
    await waitFor(() => {
      expect(screen.getByText("OrchestrationView")).toBeInTheDocument();
      expect(window.location.pathname).toBe(
        "/org/untrueaxioms/projects/proj123/orchestration",
      );
    });

    fireEvent.click(
      screen.getByRole("button", { name: "Settings" }),
    );
    await waitFor(() => {
      expect(screen.getByText("SettingsView")).toBeInTheDocument();
      expect(window.location.pathname).toBe(
        "/org/untrueaxioms/projects/proj123/settings",
      );
    });
  });
});

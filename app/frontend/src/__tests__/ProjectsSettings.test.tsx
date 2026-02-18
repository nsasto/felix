import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  within,
} from "@testing-library/react";
import OrganizationSettingsScreen from "../../components/OrganizationSettingsScreen";
import { ThemeProvider } from "../../hooks/ThemeProvider";
import { felixApi, Project } from "../../services/felixApi";

vi.mock("../../services/felixApi", () => ({
  felixApi: {
    listProjects: vi.fn(),
    registerProject: vi.fn(),
    unregisterProject: vi.fn(),
    updateProject: vi.fn(),
    getOrgConfig: vi.fn(),
    updateOrgConfig: vi.fn(),
  },
  getCopilotApiKey: vi.fn(() => null),
  setCopilotApiKey: vi.fn(),
  clearCopilotApiKey: vi.fn(),
}));

const renderWithTheme = (ui: React.ReactElement) => {
  return render(<ThemeProvider defaultTheme="dark">{ui}</ThemeProvider>);
};

const mockProjects = (): Project[] => [
  {
    id: "project-1",
    path: "C:\\dev\\Project1",
    name: "Project One",
    registered_at: "2026-01-20T10:00:00Z",
  },
  {
    id: "project-2",
    path: "C:\\dev\\Project2",
    name: "Project Two",
    registered_at: "2026-01-22T14:30:00Z",
  },
];

describe("OrganizationSettingsScreen - Projects Tab", () => {
  const mockOnBack = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(felixApi.listProjects).mockResolvedValue(mockProjects());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("loads projects on mount and shows the list", async () => {
    renderWithTheme(
      <OrganizationSettingsScreen
        orgId="00000000-0000-0000-0000-000000000001"
        organizationName="Acme"
        roleLabel="Owner"
        onBack={mockOnBack}
      />,
    );

    await waitFor(() => {
      expect(felixApi.listProjects).toHaveBeenCalled();
    });

    expect(
      screen.getByRole("heading", { name: "Projects" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Project One")).toBeInTheDocument();
    expect(screen.getByText("Project Two")).toBeInTheDocument();
    expect(screen.getByText("C:\\dev\\Project1")).toBeInTheDocument();
  });

  it("shows empty state when no projects are registered", async () => {
    vi.mocked(felixApi.listProjects).mockResolvedValue([]);

    renderWithTheme(
      <OrganizationSettingsScreen
        orgId="00000000-0000-0000-0000-000000000001"
        organizationName="Acme"
        roleLabel="Owner"
        onBack={mockOnBack}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("No Projects Registered")).toBeInTheDocument();
    });
  });

  it("shows loading state while fetching projects", async () => {
    let resolveProjects: (value: Project[]) => void;
    const projectsPromise = new Promise<Project[]>((resolve) => {
      resolveProjects = resolve;
    });
    vi.mocked(felixApi.listProjects).mockReturnValue(projectsPromise);

    renderWithTheme(
      <OrganizationSettingsScreen
        orgId="00000000-0000-0000-0000-000000000001"
        organizationName="Acme"
        roleLabel="Owner"
        onBack={mockOnBack}
      />,
    );

    expect(screen.getByText(/loading projects/i)).toBeInTheDocument();

    resolveProjects!(mockProjects());
  });

  it("shows error state when fetching projects fails", async () => {
    vi.mocked(felixApi.listProjects).mockRejectedValue(
      new Error("Failed to load projects"),
    );

    renderWithTheme(
      <OrganizationSettingsScreen
        orgId="00000000-0000-0000-0000-000000000001"
        organizationName="Acme"
        roleLabel="Owner"
        onBack={mockOnBack}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText(/failed to load projects/i)).toBeInTheDocument();
      expect(screen.getByText(/try again/i)).toBeInTheDocument();
    });
  });

  it("registers a new project", async () => {
    vi.mocked(felixApi.registerProject).mockResolvedValue({
      id: "project-3",
      path: "C:\\dev\\Project3",
      name: "Project Three",
      registered_at: "2026-01-25T08:00:00Z",
    });

    renderWithTheme(
      <OrganizationSettingsScreen
        orgId="00000000-0000-0000-0000-000000000001"
        organizationName="Acme"
        roleLabel="Owner"
        onBack={mockOnBack}
      />,
    );

    await waitFor(() => {
      expect(felixApi.listProjects).toHaveBeenCalled();
    });
    await waitFor(() => {
      expect(
        screen.getByRole("heading", { name: "Projects" }),
      ).toBeInTheDocument();
    });

    fireEvent.click(
      await screen.findByRole("button", { name: "Register New Project" }),
    );

    const gitUrlLabel = await screen.findByText("Git Repository URL *");
    const gitUrlContainer = gitUrlLabel.closest("div");
    if (!gitUrlContainer) {
      throw new Error("Git URL input container not found");
    }
    const gitUrlInput = within(gitUrlContainer).getByRole("textbox");
    fireEvent.change(gitUrlInput, {
      target: { value: "https://github.com/user/project3.git" },
    });

    const nameLabel = screen.getByText("Project Name (optional)");
    const nameContainer = nameLabel.closest("div");
    if (!nameContainer) {
      throw new Error("Project name input container not found");
    }
    const projectNameInput = within(nameContainer).getByRole("textbox");
    fireEvent.change(projectNameInput, {
      target: { value: "Project Three" },
    });

    fireEvent.click(screen.getByRole("button", { name: "Register Project" }));

    await waitFor(() => {
      expect(felixApi.registerProject).toHaveBeenCalledWith({
        git_url: "https://github.com/user/project3.git",
        name: "Project Three",
      });
    });
  });

  it("filters projects by search query", async () => {
    renderWithTheme(
      <OrganizationSettingsScreen
        orgId="00000000-0000-0000-0000-000000000001"
        organizationName="Acme"
        roleLabel="Owner"
        onBack={mockOnBack}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Project One")).toBeInTheDocument();
    });

    fireEvent.change(
      screen.getByPlaceholderText("Search projects by name or path..."),
      { target: { value: "Project Two" } },
    );

    expect(screen.queryByText("Project One")).not.toBeInTheDocument();
    expect(screen.getByText("Project Two")).toBeInTheDocument();
  });
});

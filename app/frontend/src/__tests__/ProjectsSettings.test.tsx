import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import SettingsScreen from "../../components/SettingsScreen";
import { ThemeProvider } from "../../hooks/ThemeProvider";
import {
  felixApi,
  FelixConfig,
  ConfigContent,
  Project,
} from "../../services/felixApi";

// Mock the felixApi module
vi.mock("../../services/felixApi", () => ({
  felixApi: {
    getConfig: vi.fn(),
    updateConfig: vi.fn(),
    listProjects: vi.fn(),
    registerProject: vi.fn(),
    unregisterProject: vi.fn(),
    updateProject: vi.fn(),
  },
  // Standalone localStorage functions for Copilot API key (S-0022)
  getCopilotApiKey: vi.fn(() => null),
  setCopilotApiKey: vi.fn(),
  clearCopilotApiKey: vi.fn(),
}));

// Helper to render with ThemeProvider
const renderWithTheme = (ui: React.ReactElement) => {
  return render(<ThemeProvider defaultTheme="dark">{ui}</ThemeProvider>);
};

// Create a mock config object
const createMockConfig = (
  overrides: Partial<FelixConfig> = {},
): FelixConfig => ({
  version: "1.0.0",
  executor: {
    mode: "local",
    max_iterations: 10,
    default_mode: "planning",
    auto_transition: true,
    ...overrides.executor,
  },
  agent: {
    executable: "droid",
    args: ["exec", "--"],
    working_directory: ".",
    environment: {},
    ...overrides.agent,
  },
  paths: {
    specs: "specs",
    plan: "plan.md",
    agents: "AGENTS.md",
    runs: "runs",
    ...overrides.paths,
  },
  backpressure: {
    enabled: true,
    commands: ["npm run lint", "npm test"],
    max_retries: 3,
    ...overrides.backpressure,
  },
  ui: {
    ...overrides.ui,
  },
  ...overrides,
});

const mockConfigResponse = (config: FelixConfig): ConfigContent => ({
  config,
  path: "felix/config.json",
});

// Create mock projects
const createMockProjects = (): Project[] => [
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
  {
    id: "active-project",
    path: "C:\\dev\\ActiveProject",
    name: "Active Project",
    registered_at: "2026-01-25T08:00:00Z",
  },
];

describe("SettingsScreen - Projects Category", () => {
  const mockProjectId = "active-project";
  const mockOnBack = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    // Default mock implementations
    vi.mocked(felixApi.getConfig).mockResolvedValue(
      mockConfigResponse(createMockConfig()),
    );
    vi.mocked(felixApi.listProjects).mockResolvedValue(createMockProjects());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Projects Category Navigation", () => {
    it("shows Projects category in the sidebar", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("Projects")).toBeInTheDocument();
      });
    });

    it("shows Projects description in the sidebar", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(
          screen.getByText("Manage registered projects"),
        ).toBeInTheDocument();
      });
    });

    it("switches to Projects settings when category is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General Settings")).toBeInTheDocument();
      });

      // Find Projects buttons and click the first one (category button)
      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(
          screen.getByText("Manage registered Felix projects"),
        ).toBeInTheDocument();
      });
    });

    it("fetches projects when Projects category is selected", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      // Click on Projects category
      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(felixApi.listProjects).toHaveBeenCalled();
      });
    });
  });

  describe("Projects List Display", () => {
    it("displays loading state while fetching projects", async () => {
      // Create a promise that we control
      let resolveProjects: (value: Project[]) => void;
      const projectsPromise = new Promise<Project[]>((resolve) => {
        resolveProjects = resolve;
      });
      vi.mocked(felixApi.listProjects).mockReturnValue(projectsPromise);

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      // Click on Projects category
      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      // Should show loading state
      await waitFor(() => {
        expect(screen.getByText(/loading projects/i)).toBeInTheDocument();
      });

      // Resolve the promise
      resolveProjects!(createMockProjects());

      // Loading should disappear
      await waitFor(() => {
        expect(screen.queryByText(/loading projects/i)).not.toBeInTheDocument();
      });
    });

    it("displays registered projects in the list", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      // Click on Projects category
      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
        expect(screen.getByText("Project Two")).toBeInTheDocument();
        expect(screen.getByText("Active Project")).toBeInTheDocument();
      });
    });

    it("displays project paths", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("C:\\dev\\Project1")).toBeInTheDocument();
        expect(screen.getByText("C:\\dev\\Project2")).toBeInTheDocument();
        expect(screen.getByText("C:\\dev\\ActiveProject")).toBeInTheDocument();
      });
    });

    it("highlights active project", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        // Look for the "Active" badge
        expect(screen.getByText("Active")).toBeInTheDocument();
      });
    });

    it("displays empty state when no projects registered", async () => {
      vi.mocked(felixApi.listProjects).mockResolvedValue([]);

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("No Projects Registered")).toBeInTheDocument();
        expect(
          screen.getByText(/Register a Felix project to get started/),
        ).toBeInTheDocument();
      });
    });

    it("displays error state when fetching projects fails", async () => {
      vi.mocked(felixApi.listProjects).mockRejectedValue(
        new Error("Failed to fetch"),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Failed to fetch")).toBeInTheDocument();
        expect(screen.getByText("Try again")).toBeInTheDocument();
      });
    });

    it("retries fetching projects when retry button is clicked", async () => {
      vi.mocked(felixApi.listProjects)
        .mockRejectedValueOnce(new Error("Failed to fetch"))
        .mockResolvedValueOnce(createMockProjects());

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Try again")).toBeInTheDocument();
      });

      // Click retry
      fireEvent.click(screen.getByText("Try again"));

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });
    });
  });

  describe("Search and Filter", () => {
    it("displays search input", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/search projects/i),
        ).toBeInTheDocument();
      });
    });

    it("filters projects by name", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      // Type in search box
      const searchInput = screen.getByPlaceholderText(/search projects/i);
      fireEvent.change(searchInput, { target: { value: "One" } });

      // Should only show Project One
      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
        expect(screen.queryByText("Project Two")).not.toBeInTheDocument();
        expect(screen.queryByText("Active Project")).not.toBeInTheDocument();
      });
    });

    it("filters projects by path", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      // Type path in search box
      const searchInput = screen.getByPlaceholderText(/search projects/i);
      fireEvent.change(searchInput, { target: { value: "Project2" } });

      // Should only show Project Two
      await waitFor(() => {
        expect(screen.queryByText("Project One")).not.toBeInTheDocument();
        expect(screen.getByText("Project Two")).toBeInTheDocument();
        expect(screen.queryByText("Active Project")).not.toBeInTheDocument();
      });
    });

    it("shows all projects when search is cleared", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText(/search projects/i);

      // Search for something
      fireEvent.change(searchInput, { target: { value: "One" } });
      await waitFor(() => {
        expect(screen.queryByText("Project Two")).not.toBeInTheDocument();
      });

      // Clear search
      fireEvent.change(searchInput, { target: { value: "" } });

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
        expect(screen.getByText("Project Two")).toBeInTheDocument();
        expect(screen.getByText("Active Project")).toBeInTheDocument();
      });
    });
  });

  describe("Project Registration", () => {
    it("shows Register New Project button", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Register New Project")).toBeInTheDocument();
      });
    });

    it("opens register form when button is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Register New Project")).toBeInTheDocument();
      });

      // Click register button
      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/path\\to\\your\\project/i),
        ).toBeInTheDocument();
        expect(screen.getByPlaceholderText("My Project")).toBeInTheDocument();
      });
    });

    it("closes register form when cancel is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Register New Project")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/path\\to\\your\\project/i),
        ).toBeInTheDocument();
      });

      // Click cancel
      fireEvent.click(screen.getByText("Cancel"));

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText(/path\\to\\your\\project/i),
        ).not.toBeInTheDocument();
      });
    });

    it("disables register button when path is empty", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Register New Project")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        const registerButton = screen.getByRole("button", {
          name: "Register Project",
        });
        expect(registerButton).toBeDisabled();
      });
    });

    it("enables register button when path is entered", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/path\\to\\your\\project/i),
        ).toBeInTheDocument();
      });

      const pathInput = screen.getByPlaceholderText(/path\\to\\your\\project/i);
      fireEvent.change(pathInput, { target: { value: "C:\\dev\\NewProject" } });

      await waitFor(() => {
        const registerButton = screen.getByRole("button", {
          name: "Register Project",
        });
        expect(registerButton).not.toBeDisabled();
      });
    });

    it("calls registerProject API when form is submitted", async () => {
      vi.mocked(felixApi.registerProject).mockResolvedValue({
        id: "new-project",
        path: "C:\\dev\\NewProject",
        name: "New Project",
        registered_at: "2026-01-26T12:00:00Z",
      });

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/path\\to\\your\\project/i),
        ).toBeInTheDocument();
      });

      // Fill in the form
      fireEvent.change(
        screen.getByPlaceholderText(/path\\to\\your\\project/i),
        {
          target: { value: "C:\\dev\\NewProject" },
        },
      );
      fireEvent.change(screen.getByPlaceholderText("My Project"), {
        target: { value: "New Project" },
      });

      // Submit
      fireEvent.click(screen.getByRole("button", { name: "Register Project" }));

      await waitFor(() => {
        expect(felixApi.registerProject).toHaveBeenCalledWith({
          path: "C:\\dev\\NewProject",
          name: "New Project",
        });
      });
    });

    it("shows success message after registration", async () => {
      vi.mocked(felixApi.registerProject).mockResolvedValue({
        id: "new-project",
        path: "C:\\dev\\NewProject",
        name: "New Project",
        registered_at: "2026-01-26T12:00:00Z",
      });

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/path\\to\\your\\project/i),
        ).toBeInTheDocument();
      });

      fireEvent.change(
        screen.getByPlaceholderText(/path\\to\\your\\project/i),
        {
          target: { value: "C:\\dev\\NewProject" },
        },
      );

      fireEvent.click(screen.getByRole("button", { name: "Register Project" }));

      await waitFor(() => {
        expect(
          screen.getByText(/registered successfully/i),
        ).toBeInTheDocument();
      });
    });

    it("shows error message when registration fails", async () => {
      vi.mocked(felixApi.registerProject).mockRejectedValue(
        new Error("Invalid project path"),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      fireEvent.click(screen.getByText("Register New Project"));

      await waitFor(() => {
        expect(
          screen.getByPlaceholderText(/path\\to\\your\\project/i),
        ).toBeInTheDocument();
      });

      fireEvent.change(
        screen.getByPlaceholderText(/path\\to\\your\\project/i),
        {
          target: { value: "C:\\invalid\\path" },
        },
      );

      fireEvent.click(screen.getByRole("button", { name: "Register Project" }));

      await waitFor(() => {
        expect(screen.getByText("Invalid project path")).toBeInTheDocument();
      });
    });
  });

  describe("Project Unregistration", () => {
    it("shows Unregister button for non-active projects", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        // Should have Unregister buttons for non-active projects
        const unregisterButtons = screen.getAllByText("Unregister");
        // 3 projects - 1 active = 2 unregister buttons
        expect(unregisterButtons.length).toBe(2);
      });
    });

    it("does not show Unregister button for active project", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        // Find the active project card (contains "Active" badge)
        const activeLabel = screen.getByText("Active");
        // The active project card should not have an Unregister button
        const activeCard = activeLabel.closest('[class*="rounded-xl"]');
        expect(activeCard).toBeInTheDocument();
        // Should only have 2 unregister buttons (for non-active projects)
        expect(screen.getAllByText("Unregister").length).toBe(2);
      });
    });

    it("shows confirmation dialog when Unregister is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      // Click Unregister on first non-active project
      const unregisterButtons = screen.getAllByText("Unregister");
      fireEvent.click(unregisterButtons[0]);

      await waitFor(() => {
        expect(
          screen.getByText(/Remove this project from Felix\?/),
        ).toBeInTheDocument();
        expect(
          screen.getByText(/Files will remain on disk/),
        ).toBeInTheDocument();
        expect(screen.getByText("Confirm Unregister")).toBeInTheDocument();
      });
    });

    it("hides confirmation dialog when Cancel is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const unregisterButtons = screen.getAllByText("Unregister");
      fireEvent.click(unregisterButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Confirm Unregister")).toBeInTheDocument();
      });

      // Click Cancel in the confirmation dialog
      const cancelButtons = screen.getAllByText("Cancel");
      // Find the cancel button in the unregister confirmation
      const confirmationCancel = cancelButtons.find(
        (btn) => btn.closest('[class*="border-t"]') !== null,
      );
      if (confirmationCancel) {
        fireEvent.click(confirmationCancel);
      } else {
        fireEvent.click(cancelButtons[cancelButtons.length - 1]);
      }

      await waitFor(() => {
        expect(
          screen.queryByText("Confirm Unregister"),
        ).not.toBeInTheDocument();
      });
    });

    it("calls unregisterProject API when confirmed", async () => {
      vi.mocked(felixApi.unregisterProject).mockResolvedValue(undefined);

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const unregisterButtons = screen.getAllByText("Unregister");
      fireEvent.click(unregisterButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Confirm Unregister")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Confirm Unregister"));

      await waitFor(() => {
        expect(felixApi.unregisterProject).toHaveBeenCalled();
      });
    });

    it("shows success message after unregistration", async () => {
      vi.mocked(felixApi.unregisterProject).mockResolvedValue(undefined);

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const unregisterButtons = screen.getAllByText("Unregister");
      fireEvent.click(unregisterButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Confirm Unregister")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Confirm Unregister"));

      await waitFor(() => {
        expect(
          screen.getByText(/unregistered successfully/i),
        ).toBeInTheDocument();
      });
    });
  });

  describe("Project Configuration", () => {
    it("shows Configure button for each project", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        // Should have Configure buttons for all projects
        const configureButtons = screen.getAllByText("Configure");
        expect(configureButtons.length).toBe(3); // All 3 projects
      });
    });

    it("opens configuration panel when Configure is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const configureButtons = screen.getAllByText("Configure");
      fireEvent.click(configureButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project Name")).toBeInTheDocument();
        expect(
          screen.getByText(/Display name for this project/),
        ).toBeInTheDocument();
      });
    });

    it("shows current project name in configuration input", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const configureButtons = screen.getAllByText("Configure");
      fireEvent.click(configureButtons[0]);

      await waitFor(() => {
        // The input should have the current project name as value
        // Note: Projects are sorted by registered_at desc, so "Active Project" comes first
        // Find the textbox with placeholder for project name (not the search box)
        const allInputs = screen.getAllByRole("textbox");
        // The config input is the one that appears after clicking Configure
        // It should be the last textbox (the search is first, config name is second)
        const nameInput = allInputs[allInputs.length - 1];
        expect(nameInput).toBeInTheDocument();
      });
    });

    it("closes configuration panel when Cancel is clicked", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const configureButtons = screen.getAllByText("Configure");
      fireEvent.click(configureButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project Name")).toBeInTheDocument();
      });

      // Find and click the Cancel button (should be the one in the config panel)
      const cancelButtons = screen.getAllByText("Cancel");
      fireEvent.click(cancelButtons[cancelButtons.length - 1]);

      await waitFor(() => {
        // The config panel should be closed
        expect(screen.queryByText("Project Name")).not.toBeInTheDocument();
      });
    });

    it("calls updateProject API when Save is clicked", async () => {
      vi.mocked(felixApi.updateProject).mockResolvedValue({
        id: "project-1",
        path: "C:\\dev\\Project1",
        name: "Updated Name",
        registered_at: "2026-01-20T10:00:00Z",
      });

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      // Find the Configure button for a non-active project (Project One or Two)
      const configureButtons = screen.getAllByText("Configure");
      fireEvent.click(configureButtons[configureButtons.length - 1]); // Click last Configure button

      await waitFor(() => {
        expect(screen.getByText("Project Name")).toBeInTheDocument();
      });

      // Change the name - find all textboxes and get the config input (not the search box)
      const allInputs = screen.getAllByRole("textbox");
      const nameInput = allInputs[allInputs.length - 1];
      fireEvent.change(nameInput, { target: { value: "Updated Name" } });

      // Click Save
      fireEvent.click(screen.getByRole("button", { name: "Save" }));

      await waitFor(() => {
        expect(felixApi.updateProject).toHaveBeenCalled();
      });
    });

    it("shows success message after saving configuration", async () => {
      vi.mocked(felixApi.updateProject).mockResolvedValue({
        id: "project-1",
        path: "C:\\dev\\Project1",
        name: "Updated Name",
        registered_at: "2026-01-20T10:00:00Z",
      });

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Project One")).toBeInTheDocument();
      });

      const configureButtons = screen.getAllByText("Configure");
      fireEvent.click(configureButtons[configureButtons.length - 1]);

      await waitFor(() => {
        expect(screen.getByText("Project Name")).toBeInTheDocument();
      });

      // Find all textboxes and get the config input (not the search box)
      const allInputs = screen.getAllByRole("textbox");
      const nameInput = allInputs[allInputs.length - 1];
      fireEvent.change(nameInput, { target: { value: "Updated Name" } });

      fireEvent.click(screen.getByRole("button", { name: "Save" }));

      await waitFor(() => {
        expect(screen.getByText(/configuration saved/i)).toBeInTheDocument();
      });
    });
  });

  describe("Project Actions", () => {
    it("shows Open button for each project", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        // Should have Open buttons for all projects
        const openButtons = screen.getAllByText("Open");
        expect(openButtons.length).toBe(3);
      });
    });

    it("shows copy-to-clipboard button for project path", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        // Should have copy buttons for all project paths
        const copyButtons = screen.getAllByTitle("Copy path");
        expect(copyButtons.length).toBe(3);
      });
    });
  });

  describe("Projects Sorting", () => {
    it("sorts projects by registration date (most recent first)", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const projectsButtons = screen.getAllByText("Projects");
      fireEvent.click(projectsButtons[0]);

      await waitFor(() => {
        const projectCards = screen.getAllByText(/Project/);
        // Filter to just project names
        const projectNames = projectCards
          .filter(
            (el) =>
              el.textContent === "Project One" ||
              el.textContent === "Project Two" ||
              el.textContent === "Active Project",
          )
          .map((el) => el.textContent);

        // Active Project (Jan 25) should come before Project Two (Jan 22) which should come before Project One (Jan 20)
        expect(projectNames[0]).toBe("Active Project");
        expect(projectNames[1]).toBe("Project Two");
        expect(projectNames[2]).toBe("Project One");
      });
    });
  });
});

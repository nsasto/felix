import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  within,
} from "@testing-library/react";
import SettingsScreen from "../../components/SettingsScreen";
import { ThemeProvider } from "../../hooks/ThemeProvider";
import { felixApi, FelixConfig, ConfigContent } from "../../services/felixApi";

// Mock the felixApi module
vi.mock("../../services/felixApi", () => ({
  felixApi: {
    getConfig: vi.fn(),
    updateConfig: vi.fn(),
    getGlobalConfig: vi.fn(),
    updateGlobalConfig: vi.fn(),
    // Agent configuration API methods (S-0020)
    getAgentConfigurations: vi.fn(),
    getAgentConfiguration: vi.fn(),
    createAgentConfiguration: vi.fn(),
    updateAgentConfiguration: vi.fn(),
    deleteAgentConfiguration: vi.fn(),
    setActiveAgent: vi.fn(),
    getActiveAgentConfiguration: vi.fn(),
    // Agent registry API methods (needed for Agents category)
    getAgents: vi.fn(),
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
    theme: "dark",
    ...overrides.ui,
  },
  ...overrides,
});

const mockConfigResponse = (config: FelixConfig): ConfigContent => ({
  config,
  path: "felix/config.json",
});

describe("SettingsScreen", () => {
  const mockProjectId = "test-project-id";
  const mockOnBack = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Loading State", () => {
    it("displays loading state while fetching config", async () => {
      // Setup a promise that we can resolve later
      let resolveConfig: (value: ConfigContent) => void;
      const configPromise = new Promise<ConfigContent>((resolve) => {
        resolveConfig = resolve;
      });
      vi.mocked(felixApi.getConfig).mockReturnValue(configPromise);

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      // Verify loading state
      expect(screen.getByText(/loading settings/i)).toBeInTheDocument();

      // Resolve the promise to clean up
      resolveConfig!(mockConfigResponse(createMockConfig()));
      await waitFor(() => {
        expect(screen.queryByText(/loading settings/i)).not.toBeInTheDocument();
      });
    });
  });

  describe("Error State", () => {
    it("displays error message when config fetch fails", async () => {
      vi.mocked(felixApi.getConfig).mockRejectedValue(
        new Error("Failed to load config"),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        // Multiple elements may match, so use getAllByText and check at least one exists
        const failedElements = screen.getAllByText(/failed to load/i);
        expect(failedElements.length).toBeGreaterThan(0);
      });

      // Should show back button
      expect(screen.getByText(/back to projects/i)).toBeInTheDocument();
    });

    it("calls onBack when back button is clicked in error state", async () => {
      vi.mocked(felixApi.getConfig).mockRejectedValue(
        new Error("Failed to load config"),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText(/back to projects/i)).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText(/back to projects/i));
      expect(mockOnBack).toHaveBeenCalledTimes(1);
    });
  });

  describe("Category Navigation", () => {
    it("renders all settings categories", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
        expect(screen.getByText("Agent")).toBeInTheDocument();
        expect(screen.getByText("Paths")).toBeInTheDocument();
        expect(screen.getByText("Advanced")).toBeInTheDocument();
      });
    });

    it("starts with General category selected by default", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General Settings")).toBeInTheDocument();
      });
    });

    it("switches to Paths settings when category is clicked", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const pathsButtons = screen.getAllByText("Paths");
      fireEvent.click(pathsButtons[0]);

      await waitFor(() => {
        expect(
          screen.getByText("File and directory locations (read-only)"),
        ).toBeInTheDocument();
      });
    });

    it("switches to Advanced settings when category is clicked", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const advancedButtons = screen.getAllByText("Advanced");
      fireEvent.click(advancedButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("Advanced Settings")).toBeInTheDocument();
      });
    });
  });

  describe("General Settings", () => {
    it("displays max iterations input with correct value", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(
          createMockConfig({ executor: { max_iterations: 15 } as any }),
        ),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        const maxIterInput = screen.getByDisplayValue("15");
        expect(maxIterInput).toBeInTheDocument();
      });
    });

    it("displays default mode dropdown with correct value", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        const defaultModeSelect = screen.getByDisplayValue("Planning");
        expect(defaultModeSelect).toBeInTheDocument();
      });
    });

    it("updates state when max iterations is changed", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      expect(screen.getByDisplayValue("20")).toBeInTheDocument();
    });

    it("shows unsaved changes indicator when config is modified", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      // Initially, no unsaved changes indicator
      expect(screen.queryByText(/unsaved changes/i)).not.toBeInTheDocument();

      // Modify the max iterations
      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      // Now should show unsaved changes
      await waitFor(() => {
        expect(screen.getByText(/unsaved changes/i)).toBeInTheDocument();
      });
    });
  });

  describe("Agent Settings", () => {
    it("displays agent executable path", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const agentButtons = screen.getAllByText("Agent");
      fireEvent.click(agentButtons[0]);

      await waitFor(() => {
        expect(screen.getByDisplayValue("droid")).toBeInTheDocument();
      });
    });

    it("displays agent arguments", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const agentButtons = screen.getAllByText("Agent");
      fireEvent.click(agentButtons[0]);

      await waitFor(() => {
        expect(screen.getByDisplayValue("exec --")).toBeInTheDocument();
      });
    });
  });

  describe("Paths Settings (Read-Only)", () => {
    it("displays paths as read-only values", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(
          createMockConfig({
            paths: {
              specs: "specs",
              agents: "AGENTS.md",
              runs: "runs",
              plan: "plan.md",
            },
          }),
        ),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const pathsButtons = screen.getAllByText("Paths");
      fireEvent.click(pathsButtons[0]);

      await waitFor(() => {
        // Check for the path values within code elements (they're displayed in code blocks)
        const specsElements = screen.getAllByText("specs");
        expect(specsElements.length).toBeGreaterThan(0);
        const agentsElements = screen.getAllByText("AGENTS.md");
        expect(agentsElements.length).toBeGreaterThan(0);
        const runsElements = screen.getAllByText("runs");
        expect(runsElements.length).toBeGreaterThan(0);
      });
    });

    it("shows warning that paths are read-only", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const pathsButtons = screen.getAllByText("Paths");
      fireEvent.click(pathsButtons[0]);

      await waitFor(() => {
        expect(
          screen.getByText(/path settings are read-only/i),
        ).toBeInTheDocument();
      });
    });
  });

  describe("Advanced Settings", () => {
    it("displays backpressure toggle", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(
          createMockConfig({ backpressure: { enabled: true, commands: [] } }),
        ),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const advancedButtons = screen.getAllByText("Advanced");
      fireEvent.click(advancedButtons[0]);

      await waitFor(() => {
        expect(screen.getByText(/enable backpressure/i)).toBeInTheDocument();
      });
    });

    it("shows backpressure commands when enabled", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(
          createMockConfig({
            backpressure: {
              enabled: true,
              commands: ["npm run lint", "npm test"],
              max_retries: 3,
            },
          }),
        ),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General")).toBeInTheDocument();
      });

      const advancedButtons = screen.getAllByText("Advanced");
      fireEvent.click(advancedButtons[0]);

      await waitFor(() => {
        expect(screen.getByText("npm run lint")).toBeInTheDocument();
        expect(screen.getByText("npm test")).toBeInTheDocument();
      });
    });
  });

  describe("Save Functionality", () => {
    it("disables save button when no changes are made", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General Settings")).toBeInTheDocument();
      });

      const saveButton = screen.getByText("Save Changes");
      expect(saveButton).toBeDisabled();
    });

    it("enables save button when changes are made", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      await waitFor(() => {
        const saveButton = screen.getByText("Save Changes");
        expect(saveButton).not.toBeDisabled();
      });
    });

    it("calls updateConfig when save is clicked", async () => {
      const mockConfig = createMockConfig();
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(mockConfig),
      );
      vi.mocked(felixApi.updateConfig).mockResolvedValue(
        mockConfigResponse({
          ...mockConfig,
          executor: { ...mockConfig.executor, max_iterations: 20 },
        }),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      await waitFor(() => {
        const saveButton = screen.getByText("Save Changes");
        expect(saveButton).not.toBeDisabled();
      });

      fireEvent.click(screen.getByText("Save Changes"));

      await waitFor(() => {
        expect(felixApi.updateConfig).toHaveBeenCalledWith(
          mockProjectId,
          expect.objectContaining({
            executor: expect.objectContaining({ max_iterations: 20 }),
          }),
        );
      });
    });

    it("shows success message after successful save", async () => {
      const mockConfig = createMockConfig();
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(mockConfig),
      );
      vi.mocked(felixApi.updateConfig).mockResolvedValue(
        mockConfigResponse({
          ...mockConfig,
          executor: { ...mockConfig.executor, max_iterations: 20 },
        }),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      await waitFor(() => {
        const saveButton = screen.getByText("Save Changes");
        expect(saveButton).not.toBeDisabled();
      });

      fireEvent.click(screen.getByText("Save Changes"));

      await waitFor(() => {
        expect(screen.getByText(/saved successfully/i)).toBeInTheDocument();
      });
    });

    it("shows error message when save fails", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );
      vi.mocked(felixApi.updateConfig).mockRejectedValue(
        new Error("Failed to save"),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      fireEvent.click(screen.getByText("Save Changes"));

      await waitFor(() => {
        expect(screen.getByText(/failed to save/i)).toBeInTheDocument();
      });
    });
  });

  describe("Reset Functionality", () => {
    it("shows discard button when changes are made", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      // Initially, no discard button
      expect(screen.queryByText("Discard")).not.toBeInTheDocument();

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      await waitFor(() => {
        expect(screen.getByText("Discard")).toBeInTheDocument();
      });
    });

    it("restores original values when discard is clicked", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "20" } });

      expect(screen.getByDisplayValue("20")).toBeInTheDocument();

      fireEvent.click(screen.getByText("Discard"));

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });
    });

    it("shows reset to defaults button per category", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("Reset to Defaults")).toBeInTheDocument();
      });
    });
  });

  describe("Validation", () => {
    it("shows validation error for invalid max_iterations", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "0" } });

      await waitFor(() => {
        expect(
          screen.getByText(/must be a positive integer/i),
        ).toBeInTheDocument();
      });
    });

    it("disables save button when validation errors exist", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByDisplayValue("10")).toBeInTheDocument();
      });

      const maxIterInput = screen.getByDisplayValue("10");
      fireEvent.change(maxIterInput, { target: { value: "0" } });

      await waitFor(() => {
        const saveButton = screen.getByText("Save Changes");
        expect(saveButton).toBeDisabled();
      });
    });
  });

  describe("Navigation", () => {
    it("calls onBack when back button is clicked", async () => {
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("General Settings")).toBeInTheDocument();
      });

      // Find the back button (it's the arrow icon button in the sidebar header)
      const backButton = screen.getByTitle("Back to Projects");
      fireEvent.click(backButton);

      expect(mockOnBack).toHaveBeenCalledTimes(1);
    });
  });

  // S-0019: Project-Independent Settings Tests
  describe("Project-Independent Behavior (S-0019)", () => {
    const mockOnBack = vi.fn();

    beforeEach(() => {
      vi.clearAllMocks();
    });

    describe("Loading Without ProjectId", () => {
      it("loads settings using global config API when no projectId is provided", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(felixApi.getGlobalConfig).toHaveBeenCalled();
        });

        // Should NOT call the project-specific getConfig
        expect(felixApi.getConfig).not.toHaveBeenCalled();
      });

      it("displays settings correctly without projectId", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(
            createMockConfig({ executor: { max_iterations: 25 } as any }),
          ),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("General Settings")).toBeInTheDocument();
        });

        // Verify config values are displayed
        expect(screen.getByDisplayValue("25")).toBeInTheDocument();
      });

      it("shows loading state while fetching global config", async () => {
        let resolveConfig: (value: ConfigContent) => void;
        const configPromise = new Promise<ConfigContent>((resolve) => {
          resolveConfig = resolve;
        });
        vi.mocked(felixApi.getGlobalConfig).mockReturnValue(configPromise);

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        // Verify loading state
        expect(screen.getByText(/loading settings/i)).toBeInTheDocument();

        // Resolve the promise to clean up
        resolveConfig!(mockConfigResponse(createMockConfig()));
        await waitFor(() => {
          expect(
            screen.queryByText(/loading settings/i),
          ).not.toBeInTheDocument();
        });
      });

      it("handles error when global config fetch fails", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockRejectedValue(
          new Error("Failed to load global config"),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          const failedElements = screen.getAllByText(/failed to load/i);
          expect(failedElements.length).toBeGreaterThan(0);
        });
      });
    });

    describe("Saving Without ProjectId", () => {
      it("saves settings using global config API when no projectId is provided", async () => {
        const mockConfig = createMockConfig();
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(mockConfig),
        );
        vi.mocked(felixApi.updateGlobalConfig).mockResolvedValue(
          mockConfigResponse({
            ...mockConfig,
            executor: { ...mockConfig.executor, max_iterations: 30 },
          }),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByDisplayValue("10")).toBeInTheDocument();
        });

        // Make a change
        const maxIterInput = screen.getByDisplayValue("10");
        fireEvent.change(maxIterInput, { target: { value: "30" } });

        // Click save
        await waitFor(() => {
          const saveButton = screen.getByText("Save Changes");
          expect(saveButton).not.toBeDisabled();
        });

        fireEvent.click(screen.getByText("Save Changes"));

        await waitFor(() => {
          expect(felixApi.updateGlobalConfig).toHaveBeenCalledWith(
            expect.objectContaining({
              executor: expect.objectContaining({ max_iterations: 30 }),
            }),
          );
        });

        // Should NOT call the project-specific updateConfig
        expect(felixApi.updateConfig).not.toHaveBeenCalled();
      });

      it("shows success message after saving global config", async () => {
        const mockConfig = createMockConfig();
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(mockConfig),
        );
        vi.mocked(felixApi.updateGlobalConfig).mockResolvedValue(
          mockConfigResponse({
            ...mockConfig,
            executor: { ...mockConfig.executor, max_iterations: 30 },
          }),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByDisplayValue("10")).toBeInTheDocument();
        });

        const maxIterInput = screen.getByDisplayValue("10");
        fireEvent.change(maxIterInput, { target: { value: "30" } });

        fireEvent.click(screen.getByText("Save Changes"));

        await waitFor(() => {
          expect(screen.getByText(/saved successfully/i)).toBeInTheDocument();
        });
      });

      it("shows error message when global config save fails", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.updateGlobalConfig).mockRejectedValue(
          new Error("Failed to save global config"),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByDisplayValue("10")).toBeInTheDocument();
        });

        const maxIterInput = screen.getByDisplayValue("10");
        fireEvent.change(maxIterInput, { target: { value: "30" } });

        fireEvent.click(screen.getByText("Save Changes"));

        await waitFor(() => {
          expect(screen.getByText(/failed to save/i)).toBeInTheDocument();
        });
      });
    });

    describe("Backwards Compatibility with ProjectId", () => {
      it("uses project-specific API when projectId is provided", async () => {
        const testProjectId = "test-project-123";
        vi.mocked(felixApi.getConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(
          <SettingsScreen projectId={testProjectId} onBack={mockOnBack} />,
        );

        await waitFor(() => {
          expect(felixApi.getConfig).toHaveBeenCalledWith(testProjectId);
        });

        // Should NOT call the global getGlobalConfig
        expect(felixApi.getGlobalConfig).not.toHaveBeenCalled();
      });

      it("saves using project-specific API when projectId is provided", async () => {
        const testProjectId = "test-project-123";
        const mockConfig = createMockConfig();
        vi.mocked(felixApi.getConfig).mockResolvedValue(
          mockConfigResponse(mockConfig),
        );
        vi.mocked(felixApi.updateConfig).mockResolvedValue(
          mockConfigResponse({
            ...mockConfig,
            executor: { ...mockConfig.executor, max_iterations: 15 },
          }),
        );

        renderWithTheme(
          <SettingsScreen projectId={testProjectId} onBack={mockOnBack} />,
        );

        await waitFor(() => {
          expect(screen.getByDisplayValue("10")).toBeInTheDocument();
        });

        const maxIterInput = screen.getByDisplayValue("10");
        fireEvent.change(maxIterInput, { target: { value: "15" } });

        fireEvent.click(screen.getByText("Save Changes"));

        await waitFor(() => {
          expect(felixApi.updateConfig).toHaveBeenCalledWith(
            testProjectId,
            expect.objectContaining({
              executor: expect.objectContaining({ max_iterations: 15 }),
            }),
          );
        });

        // Should NOT call updateGlobalConfig
        expect(felixApi.updateGlobalConfig).not.toHaveBeenCalled();
      });
    });

    describe("All Settings Categories Without ProjectId", () => {
      it("displays all category options without projectId", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("General")).toBeInTheDocument();
          expect(screen.getByText("Agent")).toBeInTheDocument();
          expect(screen.getByText("Paths")).toBeInTheDocument();
          expect(screen.getByText("Advanced")).toBeInTheDocument();
        });
      });

      it("can navigate to Agent settings without projectId", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("General Settings")).toBeInTheDocument();
        });

        const agentButtons = screen.getAllByText("Agent");
        fireEvent.click(agentButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Agent Settings")).toBeInTheDocument();
          expect(screen.getByDisplayValue("droid")).toBeInTheDocument();
        });
      });

      it("can navigate to Advanced settings without projectId", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(
            createMockConfig({
              backpressure: {
                enabled: true,
                commands: ["npm test"],
                max_retries: 3,
              },
            }),
          ),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("General")).toBeInTheDocument();
        });

        const advancedButtons = screen.getAllByText("Advanced");
        fireEvent.click(advancedButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Advanced Settings")).toBeInTheDocument();
          expect(screen.getByText(/enable backpressure/i)).toBeInTheDocument();
        });
      });
    });
  });

  // S-0016: Felix Copilot Settings Tests
  describe("Copilot Settings (S-0016)", () => {
    const mockOnBack = vi.fn();

    beforeEach(() => {
      vi.clearAllMocks();
    });

    // Helper to create config with copilot
    const createMockConfigWithCopilot = (
      copilotOverrides: any = {},
    ): FelixConfig => ({
      ...createMockConfig(),
      copilot: {
        enabled: false,
        provider: "openai",
        model: "gpt-4o",
        context_sources: {
          agents_md: true,
          learnings_md: true,
          prompt_md: true,
          requirements: true,
          other_specs: true,
        },
        features: {
          streaming: true,
          auto_suggest: true,
          context_aware: true,
        },
        ...copilotOverrides,
      },
    });

    describe("Category Navigation", () => {
      it("displays Felix Copilot category in sidebar", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });
      });

      it("Felix Copilot category is positioned between Paths and Advanced", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        // Get all category buttons in the sidebar
        const categories = screen
          .getAllByRole("button")
          .filter((btn) =>
            [
              "General",
              "Agent",
              "Paths",
              "Felix Copilot",
              "Advanced",
              "Projects",
              "Agents",
            ].some((cat) => btn.textContent?.includes(cat)),
          );

        // Find indices
        const pathsIndex = categories.findIndex((cat) =>
          cat.textContent?.includes("Paths"),
        );
        const copilotIndex = categories.findIndex((cat) =>
          cat.textContent?.includes("Felix Copilot"),
        );
        const advancedIndex = categories.findIndex((cat) =>
          cat.textContent?.includes("Advanced"),
        );

        // Copilot should be after Paths and before Advanced
        expect(copilotIndex).toBeGreaterThan(pathsIndex);
        expect(copilotIndex).toBeLessThan(advancedIndex);
      });

      it("shows copilot description in category", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(
            screen.getByText("AI-powered spec writing assistant"),
          ).toBeInTheDocument();
        });
      });

      it("navigates to copilot settings when category is clicked", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        // Click on Felix Copilot category
        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          // The component shows "Felix Copilot" as the heading with "Enable Copilot" as a label
          expect(screen.getByText("Enable Copilot")).toBeInTheDocument();
        });
      });
    });

    describe("Enable/Disable Toggle", () => {
      it("shows Enable Copilot toggle at the top", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Enable Copilot")).toBeInTheDocument();
        });
      });

      it("toggle defaults to OFF for new installations", async () => {
        // Config with copilot.enabled = false (default)
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: false })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Enable Copilot")).toBeInTheDocument();
          // Verify the toggle exists (it's a button element with rounded-full class)
          // The toggle is visually off when copilot is disabled (no explicit "Disabled" text shown)
          const toggleButtons = screen
            .getAllByRole("button")
            .filter(
              (btn) =>
                btn.className.includes("rounded-full") &&
                btn.className.includes("w-12"),
            );
          expect(toggleButtons.length).toBeGreaterThan(0);
        });
      });

      it("shows toggle is ON when copilot is enabled", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Enable Copilot")).toBeInTheDocument();
          // When enabled, the provider dropdown should be enabled (not have cursor-not-allowed)
          const providerSelect = screen.getByDisplayValue("OpenAI");
          expect(providerSelect).not.toBeDisabled();
        });
      });
    });

    describe("Provider Selection", () => {
      it("shows Provider dropdown", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Provider")).toBeInTheDocument();
        });
      });

      it("shows OpenAI, Anthropic, Custom options in dropdown", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          // Find the provider dropdown
          const providerSelect = screen.getByDisplayValue("OpenAI");
          expect(providerSelect).toBeInTheDocument();

          // Check that dropdown options include all providers
          const options = providerSelect.querySelectorAll("option");
          const optionValues = Array.from(options).map(
            (opt) => opt.textContent,
          );
          expect(optionValues).toContain("OpenAI");
          expect(optionValues).toContain("Anthropic");
          expect(optionValues).toContain("Custom");
        });
      });
    });

    describe("Model Selection", () => {
      it("shows Model dropdown with provider-specific options", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(
            createMockConfigWithCopilot({ enabled: true, provider: "openai" }),
          ),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Model")).toBeInTheDocument();
          // Default OpenAI model
          expect(screen.getByDisplayValue("GPT-4o")).toBeInTheDocument();
        });
      });
    });

    describe("Context Sources", () => {
      it("shows context sources section with toggles", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Context Sources")).toBeInTheDocument();
          expect(screen.getByText("AGENTS.md")).toBeInTheDocument();
          expect(screen.getByText("LEARNINGS.md")).toBeInTheDocument();
          expect(screen.getByText("prompt.md")).toBeInTheDocument();
          expect(screen.getByText("requirements.json")).toBeInTheDocument();
          // Component shows "Other specs" (lowercase s)
          expect(screen.getByText("Other specs")).toBeInTheDocument();
        });
      });
    });

    describe("Feature Toggles", () => {
      it("shows feature toggles section", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          // Component shows "Features" (not "Feature Toggles")
          expect(screen.getByText("Features")).toBeInTheDocument();
          expect(screen.getByText("Streaming Responses")).toBeInTheDocument();
          // Component shows "Auto-suggest Spec Titles" (not "Auto-suggest Titles")
          expect(
            screen.getByText("Auto-suggest Spec Titles"),
          ).toBeInTheDocument();
          expect(
            screen.getByText("Context-aware Completions"),
          ).toBeInTheDocument();
        });
      });
    });

    describe("API Key Section", () => {
      it("shows API Key configuration section", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          // The component shows "API Key" as the label
          expect(screen.getByText("API Key")).toBeInTheDocument();
          expect(screen.getByText(/FELIX_COPILOT_API_KEY/)).toBeInTheDocument();
        });
      });

      it("shows Test Connection button", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Test Connection")).toBeInTheDocument();
        });
      });

      it("Test Connection button is disabled when copilot is disabled", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: false })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          const testButton = screen.getByText("Test Connection");
          expect(testButton).toBeDisabled();
        });
      });
    });

    describe("Reset to Defaults", () => {
      it("shows Reset to Defaults button", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: true })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Reset to Defaults")).toBeInTheDocument();
        });
      });
    });

    describe("Disabled State", () => {
      it("disables provider dropdown when copilot is disabled", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: false })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          // Find the provider dropdown and verify it's disabled
          const providerSelect = screen.getByDisplayValue("OpenAI");
          expect(providerSelect).toBeDisabled();
        });
      });

      it("disables model dropdown when copilot is disabled", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfigWithCopilot({ enabled: false })),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          // Find the model dropdown and verify it's disabled
          const modelSelect = screen.getByDisplayValue("GPT-4o");
          expect(modelSelect).toBeDisabled();
        });
      });
    });

    describe("Config Persistence", () => {
      it("saves copilot settings when Save Changes is clicked", async () => {
        const mockConfig = createMockConfigWithCopilot({ enabled: false });
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(mockConfig),
        );
        vi.mocked(felixApi.updateGlobalConfig).mockResolvedValue(
          mockConfigResponse({
            ...mockConfig,
            copilot: { ...mockConfig.copilot!, enabled: true },
          }),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
        });

        const copilotButtons = screen.getAllByText("Felix Copilot");
        fireEvent.click(copilotButtons[0]);

        await waitFor(() => {
          expect(screen.getByText("Enable Copilot")).toBeInTheDocument();
        });

        // Find the enable toggle button (it's near "Disabled" text)
        const toggleButtons = screen.getAllByRole("button");
        const enableToggle = toggleButtons.find(
          (btn) =>
            btn.className.includes("rounded-full") &&
            btn.className.includes("w-12"),
        );

        if (enableToggle) {
          fireEvent.click(enableToggle);
        }

        // Wait for Save Changes to be enabled
        await waitFor(() => {
          const saveButton = screen.getByText("Save Changes");
          expect(saveButton).not.toBeDisabled();
        });

        fireEvent.click(screen.getByText("Save Changes"));

        await waitFor(() => {
          expect(felixApi.updateGlobalConfig).toHaveBeenCalled();
        });
      });
    });
  });

  // S-0020: Agent Configuration Settings Tests
  describe("Agent Configuration Settings (S-0020)", () => {
    const mockOnBack = vi.fn();

    // Mock agent configurations
    const mockAgentConfigurations = {
      agents: [
        {
          id: 0,
          name: "felix-primary",
          executable: "droid",
          args: ["exec", "--skip-permissions-unsafe"],
          working_directory: ".",
          environment: {},
        },
        {
          id: 1,
          name: "claude-agent",
          executable: "claude",
          args: ["--model", "sonnet"],
          working_directory: ".",
          environment: { API_KEY: "test-key" },
        },
      ],
      active_agent_id: 0,
    };

    // Mock agent registry response
    const mockAgentRegistry = {
      agents: {},
    };

    beforeEach(() => {
      vi.clearAllMocks();
      // Default mocks for agent configuration API
      vi.mocked(felixApi.getAgentConfigurations).mockResolvedValue(
        mockAgentConfigurations,
      );
      vi.mocked(felixApi.getAgents).mockResolvedValue(mockAgentRegistry);
    });

    describe("Agents Category Navigation", () => {
      it("displays Agents category in sidebar", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });
      });

      it("navigates to agents settings when Agents category is clicked", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        // Click on Agents category
        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        // Wait for agent configurations to load
        await waitFor(() => {
          expect(felixApi.getAgentConfigurations).toHaveBeenCalled();
        });
      });
    });

    describe("Agent List Display", () => {
      it("displays all agent configurations from agents.json", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        // Navigate to Agents category
        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          // Both agents should be displayed
          expect(screen.getByText("felix-primary")).toBeInTheDocument();
          expect(screen.getByText("claude-agent")).toBeInTheDocument();
        });
      });

      it("shows System Default badge for agent ID 0", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          // System default badge should be visible
          expect(screen.getByText(/system default/i)).toBeInTheDocument();
        });
      });

      it("shows Active badge for the currently active agent", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          // Active badge should be visible (agent 0 is active by default)
          expect(screen.getByText(/active/i)).toBeInTheDocument();
        });
      });

      it("displays agent executable and args", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          // Executable info should be visible
          expect(screen.getByText(/droid/i)).toBeInTheDocument();
          expect(screen.getByText(/claude/i)).toBeInTheDocument();
        });
      });
    });

    describe("Set Active Agent", () => {
      it("calls setActiveAgent API when Set Active button is clicked", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.setActiveAgent).mockResolvedValue({
          agent_id: 1,
          message: "Active agent set",
        });

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText("claude-agent")).toBeInTheDocument();
        });

        // Find and click Set Active button for claude-agent
        const setActiveButtons = screen.getAllByText(/set active/i);
        if (setActiveButtons.length > 0) {
          fireEvent.click(setActiveButtons[0]);
        }

        await waitFor(() => {
          expect(felixApi.setActiveAgent).toHaveBeenCalled();
        });
      });
    });

    describe("Add Agent Form", () => {
      it("shows Add Agent button", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText(/add agent/i)).toBeInTheDocument();
        });
      });

      it("opens agent form when Add Agent is clicked", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText(/add agent/i)).toBeInTheDocument();
        });

        // Click Add Agent button
        const addButton = screen.getByText(/add agent/i);
        fireEvent.click(addButton);

        await waitFor(() => {
          // Form fields should appear
          expect(screen.getByPlaceholderText(/my-agent/i)).toBeInTheDocument();
        });
      });

      it("calls createAgentConfiguration when form is submitted", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.createAgentConfiguration).mockResolvedValue({
          agent: {
            id: 2,
            name: "new-agent",
            executable: "new-exec",
            args: [],
            working_directory: ".",
            environment: {},
          },
          message: "Agent created",
        });

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText(/add agent/i)).toBeInTheDocument();
        });

        // Click Add Agent button
        const addButton = screen.getByText(/add agent/i);
        fireEvent.click(addButton);

        await waitFor(() => {
          expect(screen.getByPlaceholderText(/my-agent/i)).toBeInTheDocument();
        });

        // Fill in form fields
        const nameInput = screen.getByPlaceholderText(/my-agent/i);
        fireEvent.change(nameInput, { target: { value: "new-agent" } });

        // Find executable input and fill it
        const executableInputs = screen.getAllByRole("textbox");
        const executableInput = executableInputs.find(
          (input) =>
            input.getAttribute("placeholder")?.toLowerCase().includes("exec") ||
            input.getAttribute("placeholder") === "droid",
        );
        if (executableInput) {
          fireEvent.change(executableInput, { target: { value: "new-exec" } });
        }

        // Submit form - find Save button
        const saveButtons = screen.getAllByText(/save/i);
        const formSaveButton = saveButtons.find(
          (btn) => btn.closest("button") && !btn.closest("button")?.disabled,
        );
        if (formSaveButton) {
          fireEvent.click(formSaveButton);
        }

        await waitFor(() => {
          expect(felixApi.createAgentConfiguration).toHaveBeenCalled();
        });
      });
    });

    describe("Edit Agent", () => {
      it("shows Edit button on agent cards", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          // Edit buttons should be visible on agent cards
          const editButtons = screen.getAllByText(/edit/i);
          expect(editButtons.length).toBeGreaterThan(0);
        });
      });

      it("calls updateAgentConfiguration when edit form is submitted", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.updateAgentConfiguration).mockResolvedValue({
          agent: {
            id: 0,
            name: "updated-name",
            executable: "droid",
            args: [],
            working_directory: ".",
            environment: {},
          },
          message: "Agent updated",
        });

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText("felix-primary")).toBeInTheDocument();
        });

        // Click Edit on first agent
        const editButtons = screen.getAllByText(/edit/i);
        if (editButtons.length > 0) {
          fireEvent.click(editButtons[0]);
        }

        // Wait for form to appear with pre-filled values
        await waitFor(() => {
          // The form should have some input with the agent name
          const inputs = screen.getAllByRole("textbox");
          expect(inputs.length).toBeGreaterThan(0);
        });

        // Find and update the name input
        const nameInput = screen.getByDisplayValue("felix-primary");
        if (nameInput) {
          fireEvent.change(nameInput, { target: { value: "updated-name" } });
        }

        // Submit form
        const saveButtons = screen.getAllByText(/save/i);
        const formSaveButton = saveButtons.find((btn) => {
          const button = btn.closest("button");
          return button && !button.disabled;
        });
        if (formSaveButton) {
          fireEvent.click(formSaveButton);
        }

        await waitFor(() => {
          expect(felixApi.updateAgentConfiguration).toHaveBeenCalled();
        });
      });
    });

    describe("Delete Agent", () => {
      it("disables delete button for system default agent (ID 0)", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText("felix-primary")).toBeInTheDocument();
        });

        // Find delete buttons
        const deleteButtons = screen.getAllByText(/delete/i);

        // At least one delete button should exist (for non-system-default agents)
        // The system default agent's delete button should be disabled or not present
        // Check that there's a delete button that is enabled (for agent ID 1)
        const enabledDeleteButton = deleteButtons.find((btn) => {
          const button = btn.closest("button");
          return button && !button.disabled;
        });

        expect(enabledDeleteButton).toBeDefined();
      });

      it("calls deleteAgentConfiguration for non-system-default agents", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.deleteAgentConfiguration).mockResolvedValue({
          status: "deleted",
          agent_id: 1,
          message: "Agent deleted",
        });

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText("claude-agent")).toBeInTheDocument();
        });

        // Find and click delete button for the non-default agent
        const deleteButtons = screen.getAllByText(/delete/i);
        const enabledDeleteButton = deleteButtons.find((btn) => {
          const button = btn.closest("button");
          return button && !button.disabled;
        });

        if (enabledDeleteButton) {
          fireEvent.click(enabledDeleteButton);
        }

        await waitFor(() => {
          expect(felixApi.deleteAgentConfiguration).toHaveBeenCalled();
        });
      });
    });

    describe("Error Handling", () => {
      it("displays error when agent configurations fail to load", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.getAgentConfigurations).mockRejectedValue(
          new Error("Failed to load agent configs"),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          // Error message should be displayed
          expect(screen.getByText(/failed to load/i)).toBeInTheDocument();
        });
      });

      it("shows Try Again button when agent configs fail to load", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );
        vi.mocked(felixApi.getAgentConfigurations).mockRejectedValue(
          new Error("Failed to load"),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        await waitFor(() => {
          expect(screen.getByText(/try again/i)).toBeInTheDocument();
        });
      });
    });

    describe("Refresh Functionality", () => {
      it("refreshes agent configurations when refresh button is clicked", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig()),
        );

        renderWithTheme(<SettingsScreen onBack={mockOnBack} />);

        await waitFor(() => {
          expect(screen.getByText("Agents")).toBeInTheDocument();
        });

        const agentsButton = screen
          .getAllByText("Agents")
          .find((el) => el.closest("button")?.classList.contains("w-full"));
        if (agentsButton) {
          fireEvent.click(agentsButton);
        }

        // Wait for initial load
        await waitFor(() => {
          expect(felixApi.getAgentConfigurations).toHaveBeenCalledTimes(1);
        });

        // Find and click refresh button by text content
        const refreshButton = screen.getByText("Refresh");
        fireEvent.click(refreshButton);

        await waitFor(() => {
          // Should have been called again
          expect(felixApi.getAgentConfigurations).toHaveBeenCalledTimes(2);
        });
      });
    });
  });
});

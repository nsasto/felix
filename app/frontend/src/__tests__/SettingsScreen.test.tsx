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
import * as apiClient from "../../src/api/client";

// Mock the felixApi module
vi.mock("../../services/felixApi", () => ({
  felixApi: {
    getConfig: vi.fn(),
    updateConfig: vi.fn(),
    getGlobalConfig: vi.fn(),
    updateGlobalConfig: vi.fn(),
    getAgentConfigurations: vi.fn(),
  },
  // Standalone localStorage functions for Copilot API key (S-0022)
  getCopilotApiKey: vi.fn(() => null),
  setCopilotApiKey: vi.fn(),
  clearCopilotApiKey: vi.fn(),
}));

vi.mock("../../src/api/client", () => ({
  listAgents: vi.fn(),
  registerAgent: vi.fn(),
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
  path: "\.felix/config.json",
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
        expect(screen.getByText("Paths")).toBeInTheDocument();
        expect(screen.getByText("Advanced")).toBeInTheDocument();
        expect(screen.getByText("Projects")).toBeInTheDocument();
        expect(screen.getByText("Agents")).toBeInTheDocument();
        expect(screen.getByText("Docs")).toBeInTheDocument();
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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Paths" }), {
        button: 0,
      });

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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Advanced" }), {
        button: 0,
      });

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
        const defaultModeSection = screen.getByText("Default Mode")
          .parentElement as HTMLElement;
        const defaultModeSelect = within(defaultModeSection).getByRole(
          "combobox",
        );
        expect(defaultModeSelect).toHaveTextContent("Planning");
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

  // Note: Agent configuration lives under organization settings. The project settings
  // "Agents" category manages registered agents for the current project.

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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Paths" }), {
        button: 0,
      });

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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Paths" }), {
        button: 0,
      });

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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Advanced" }), {
        button: 0,
      });

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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Advanced" }), {
        button: 0,
      });

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
    it("calls onBack when back button is clicked in error state", async () => {
      vi.mocked(felixApi.getConfig).mockRejectedValue(
        new Error("Failed to load"),
      );

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("Failed to Load Settings")).toBeInTheDocument();
      });

      const backButton = screen.getByText("Back to Projects");
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
        expect(screen.getByText("Paths")).toBeInTheDocument();
        expect(screen.getByText("Advanced")).toBeInTheDocument();
        expect(screen.getByText("Projects")).toBeInTheDocument();
        expect(screen.getByText("Agents")).toBeInTheDocument();
      });
    });

        // Note: Agent configuration lives under organization settings. The project settings
        // "Agents" category manages registered agents for the current project.

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

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Advanced" }), {
        button: 0,
      });

        await waitFor(() => {
          expect(screen.getByText("Advanced Settings")).toBeInTheDocument();
          expect(screen.getByText(/enable backpressure/i)).toBeInTheDocument();
        });
      });
    });
  });

    describe("Project Agents", () => {
    const mockAgentProfiles = {
      agents: [
        {
          id: "profile-1",
          name: "droid-default",
          executable: "droid",
          args: ["exec", "--skip-permissions-unsafe"],
          working_directory: ".",
          environment: {},
        },
      ],
      active_agent_id: "profile-1",
    };

    const mockAgentList = {
      agents: [
        {
          id: "agent-1",
          project_id: mockProjectId,
          name: "Nova",
          type: "",
          status: "idle",
          heartbeat_at: null,
          metadata: {},
          profile_id: "profile-1",
          created_at: "2024-01-01T00:00:00Z",
          updated_at: "2024-01-01T00:00:00Z",
        },
      ],
      count: 1,
    };

    beforeEach(() => {
      vi.clearAllMocks();
      vi.mocked(felixApi.getConfig).mockResolvedValue(
        mockConfigResponse(createMockConfig()),
      );
      vi.mocked(felixApi.getAgentConfigurations).mockResolvedValue(
        mockAgentProfiles,
      );
      vi.mocked(apiClient.listAgents).mockResolvedValue({
        agents: [],
        count: 0,
      });
    });

    it("fetches agents when the Agents tab is selected", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("Agents")).toBeInTheDocument();
      });

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Agents" }), {
        button: 0,
      });

      await waitFor(() => {
        expect(apiClient.listAgents).toHaveBeenCalledWith({
          scope: "project",
          projectId: mockProjectId,
        });
      });
    });

    it("requires an agent profile before enabling Create Agent", async () => {
      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("Agents")).toBeInTheDocument();
      });

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Agents" }), {
        button: 0,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /add agent/i }),
        ).toBeInTheDocument();
      });

      fireEvent.click(screen.getByRole("button", { name: /add agent/i }));

      await waitFor(() => {
        expect(screen.getByPlaceholderText(/my-agent/i)).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText(/my-agent/i), {
        target: { value: "Nova" },
      });

      const createButton = screen.getByText("Create Agent");
      expect(createButton).toBeDisabled();

      fireEvent.click(screen.getByText("Select an agent profile"));
      fireEvent.click(screen.getByText("droid-default"));

      await waitFor(() => {
        expect(screen.getByText("Create Agent")).not.toBeDisabled();
      });
    });

    it("calls registerAgent when the form is submitted", async () => {
      vi.mocked(apiClient.listAgents).mockResolvedValue(mockAgentList);
      vi.mocked(apiClient.registerAgent).mockResolvedValue(mockAgentList.agents[0]);

      renderWithTheme(
        <SettingsScreen projectId={mockProjectId} onBack={mockOnBack} />,
      );

      await waitFor(() => {
        expect(screen.getByText("Agents")).toBeInTheDocument();
      });

      fireEvent.mouseDown(screen.getByRole("tab", { name: "Agents" }), {
        button: 0,
      });

      await waitFor(() => {
        expect(
          screen.getByRole("button", { name: /add agent/i }),
        ).toBeInTheDocument();
      });

      fireEvent.click(screen.getByRole("button", { name: /add agent/i }));

      await waitFor(() => {
        expect(screen.getByPlaceholderText(/my-agent/i)).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText(/my-agent/i), {
        target: { value: "Nova" },
      });

      fireEvent.click(screen.getByText("Select an agent profile"));
      fireEvent.click(screen.getByText("droid-default"));

      fireEvent.change(screen.getByPlaceholderText(/ralph/i), {
        target: { value: "pilot" },
      });

      fireEvent.click(screen.getByText("Create Agent"));

      await waitFor(() => {
        expect(apiClient.registerAgent).toHaveBeenCalledWith(
          expect.any(String),
          "Nova",
          "pilot",
          { source: "ui" },
          "profile-1",
        );
      });
    });
  });
});



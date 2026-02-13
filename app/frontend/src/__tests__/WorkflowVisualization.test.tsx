import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import WorkflowVisualization from '../../components/WorkflowVisualization';
import { ThemeProvider } from '../../hooks/ThemeProvider';
import { felixApi } from '../../services/felixApi';

// Mock the felixApi module
vi.mock('../../services/felixApi', () => ({
  felixApi: {
    getWorkflowConfig: vi.fn(),
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

// Mock workflow configuration matching \.felix/workflow.json structure
const mockWorkflowConfig = {
  version: '1.0',
  layout: 'horizontal' as const,
  stages: [
    { id: 'select_requirement', name: 'Select', icon: 'target', description: 'Select next requirement', order: 1 },
    { id: 'start_iteration', name: 'Start', icon: 'play', description: 'Start iteration', order: 2 },
    { id: 'determine_mode', name: 'Mode', icon: 'git-branch', description: 'Determine mode', order: 3 },
    { id: 'gather_context', name: 'Context', icon: 'folder', description: 'Gather context', order: 4 },
    { id: 'build_prompt', name: 'Prompt', icon: 'file-text', description: 'Build prompt', order: 5 },
    { id: 'execute_llm', name: 'LLM', icon: 'cpu', description: 'Execute LLM', order: 6 },
    { id: 'process_output', name: 'Output', icon: 'file-code', description: 'Process output', order: 7 },
    { id: 'check_guardrails', name: 'Guard', icon: 'shield', description: 'Check guardrails', order: 8, conditional: 'planning' },
    { id: 'detect_task', name: 'Task', icon: 'check-square', description: 'Detect task completion', order: 9 },
    { id: 'run_backpressure', name: 'Tests', icon: 'flask', description: 'Run tests', order: 10 },
    { id: 'commit_changes', name: 'Commit', icon: 'git-commit', description: 'Commit changes', order: 11 },
    { id: 'validate_requirement', name: 'Validate', icon: 'check-circle', description: 'Validate requirement', order: 12 },
    { id: 'update_status', name: 'Status', icon: 'bar-chart', description: 'Update status', order: 13 },
    { id: 'iteration_complete', name: 'Done', icon: 'flag', description: 'Iteration complete', order: 14 },
  ],
};

describe('WorkflowVisualization (S-0030: Agent Workflow Visualization)', () => {
  const mockProjectId = 'test-project';

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(felixApi.getWorkflowConfig).mockResolvedValue(mockWorkflowConfig);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Component Rendering', () => {
    it('fetches workflow configuration on mount', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage={null}
          isAgentActive={false}
        />
      );

      await waitFor(() => {
        expect(felixApi.getWorkflowConfig).toHaveBeenCalledWith(mockProjectId);
      });
    });

    it('renders all workflow stages', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      // Wait for stages to render
      await waitFor(() => {
        expect(screen.getByText('Select')).toBeInTheDocument();
        expect(screen.getByText('Start')).toBeInTheDocument();
        expect(screen.getByText('Mode')).toBeInTheDocument();
        expect(screen.getByText('LLM')).toBeInTheDocument();
        expect(screen.getByText('Done')).toBeInTheDocument();
      });
    });

    it('renders stages in correct order', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Get all stage name elements
        const stages = screen.getAllByText(/^(Select|Start|Mode|Context|Prompt|LLM|Output|Guard|Task|Tests|Commit|Validate|Status|Done)$/);
        const stageNames = stages.map(el => el.textContent);
        
        // Verify order matches workflow config
        expect(stageNames[0]).toBe('Select');
        expect(stageNames[5]).toBe('LLM');
        expect(stageNames[13]).toBe('Done');
      });
    });

    it('shows loading state initially', async () => {
      // Delay the mock response to see loading state
      let resolveConfig: (value: typeof mockWorkflowConfig) => void;
      vi.mocked(felixApi.getWorkflowConfig).mockImplementation(() => 
        new Promise(resolve => { resolveConfig = resolve; })
      );

      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage={null}
          isAgentActive={false}
        />
      );

      // Should show loading spinner
      expect(screen.getByText('Loading workflow...')).toBeInTheDocument();

      // Resolve the promise
      resolveConfig!(mockWorkflowConfig);

      // Wait for loading to complete
      await waitFor(() => {
        expect(screen.queryByText('Loading workflow...')).not.toBeInTheDocument();
      });
    });

    it('shows error state when fetch fails', async () => {
      const errorMessage = 'Failed to load workflow configuration';
      vi.mocked(felixApi.getWorkflowConfig).mockRejectedValue(new Error(errorMessage));

      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage={null}
          isAgentActive={false}
        />
      );

      await waitFor(() => {
        expect(screen.getByText(errorMessage)).toBeInTheDocument();
      });
    });

    it('shows "No workflow data" when config has empty stages', async () => {
      vi.mocked(felixApi.getWorkflowConfig).mockResolvedValue({
        version: '1.0',
        layout: 'horizontal',
        stages: [],
      });

      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage={null}
          isAgentActive={false}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('No workflow data')).toBeInTheDocument();
      });
    });
  });

  describe('Active Stage Highlighting', () => {
    it('highlights the current active stage', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        const llmStage = screen.getByText('LLM');
        // The parent node container should have active styling
        const nodeContainer = llmStage.closest('[class*="transition-all"]');
        expect(nodeContainer).toBeInTheDocument();
        // Active stage should have felix-500 border and animation class
        expect(nodeContainer).toHaveClass('animate-workflow-pulse');
      });
    });

    it('shows completed stages before current stage', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"  // order 6
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Stages before execute_llm should be completed
        const selectStage = screen.getByText('Select');
        const selectNode = selectStage.closest('[class*="transition-all"]');
        // Completed stages have emerald border
        expect(selectNode).toHaveClass('border-emerald-500/50');
      });
    });

    it('shows pending stages after current stage', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"  // order 6
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Stages after execute_llm should be pending (muted styling)
        const doneStage = screen.getByText('Done');
        const doneNode = doneStage.closest('[class*="transition-all"]');
        // Pending stages should not have completed or active styling
        expect(doneNode).not.toHaveClass('border-emerald-500/50');
        expect(doneNode).not.toHaveClass('animate-workflow-pulse');
      });
    });
  });

  describe('Agent Idle State', () => {
    it('shows "Agent idle" message when agent is not active', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage={null}
          isAgentActive={false}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('Agent idle - workflow inactive')).toBeInTheDocument();
      });
    });

    it('shows all stages as pending when agent is not active', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"  // Even with currentStage set
          isAgentActive={false}       // Agent is not active
        />
      );

      await waitFor(() => {
        // All stages should be pending (muted styling) when agent is inactive
        const selectStage = screen.getByText('Select');
        const selectNode = selectStage.closest('[class*="transition-all"]');
        // Should not have active or completed styling
        expect(selectNode).not.toHaveClass('animate-workflow-pulse');
        expect(selectNode).not.toHaveClass('border-emerald-500/50');
      });
    });
  });

  describe('Unknown Stage Handling', () => {
    it('shows warning when current stage is not in config', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="unknown_stage_id"  // Not in config
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('Unknown Stage: unknown_stage_id')).toBeInTheDocument();
      });
    });

    it('warning has amber/warning styling', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="unknown_stage_id"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        const warningText = screen.getByText('Unknown Stage: unknown_stage_id');
        const warningContainer = warningText.closest('div');
        expect(warningContainer).toHaveClass('bg-amber-500/10');
        expect(warningContainer).toHaveClass('border-amber-500/20');
      });
    });
  });

  describe('Stage Tooltips', () => {
    it('renders stage descriptions in tooltips', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Check that descriptions are rendered (in tooltip divs)
        expect(screen.getByText('Select next requirement')).toBeInTheDocument();
        expect(screen.getByText('Execute LLM')).toBeInTheDocument();
        expect(screen.getByText('Iteration complete')).toBeInTheDocument();
      });
    });

    it('shows conditional indicator for conditional stages', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // check_guardrails has conditional: 'planning'
        const conditionalIndicator = screen.getByText('(planning)');
        expect(conditionalIndicator).toBeInTheDocument();
      });
    });
  });

  describe('Visual Connectors', () => {
    it('renders connector arrows between stages', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Check that connector elements exist
        // The last stage should not have a connector
        const container = screen.getByText('Select').closest('[class*="overflow-x-auto"]')?.parentElement;
        if (container) {
          // There should be connector arrows (ChevronRight icons)
          const arrows = container.querySelectorAll('svg.lucide-chevron-right');
          // 13 arrows for 14 stages (no arrow after last)
          expect(arrows.length).toBe(13);
        }
      });
    });
  });

  describe('Completed and Failed Stages (via props)', () => {
    it('marks stages in completedStages array as completed', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          completedStages={['select_requirement', 'start_iteration']}
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Both explicitly completed stages should have green styling
        const selectStage = screen.getByText('Select');
        const selectNode = selectStage.closest('[class*="transition-all"]');
        expect(selectNode).toHaveClass('border-emerald-500/50');
      });
    });

    it('marks stages in failedStages array as failed', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="process_output"
          failedStages={['run_backpressure']}
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Failed stage should have red styling
        const testsStage = screen.getByText('Tests');
        const testsNode = testsStage.closest('[class*="transition-all"]');
        expect(testsNode).toHaveClass('border-red-500/50');
      });
    });

    it('renders checkmark overlay on completed stages', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          completedStages={['select_requirement']}
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Find the completed stage's checkmark overlay
        const selectStage = screen.getByText('Select');
        const nodeContainer = selectStage.closest('[class*="transition-all"]');
        const checkmark = nodeContainer?.querySelector('.bg-emerald-500');
        expect(checkmark).toBeInTheDocument();
      });
    });

    it('renders X overlay on failed stages', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="process_output"
          failedStages={['run_backpressure']}
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Find the failed stage's X overlay
        const testsStage = screen.getByText('Tests');
        const nodeContainer = testsStage.closest('[class*="transition-all"]');
        const xMark = nodeContainer?.querySelector('.bg-red-500');
        expect(xMark).toBeInTheDocument();
      });
    });
  });

  describe('CSS Transitions for Stage Changes', () => {
    it('stage nodes have transition-all class for smooth animations', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        const llmStage = screen.getByText('LLM');
        const nodeContainer = llmStage.closest('[class*="transition-all"]');
        expect(nodeContainer).toHaveClass('transition-all');
        expect(nodeContainer).toHaveClass('duration-300');
      });
    });

    it('icon elements have transition-colors class', async () => {
      renderWithTheme(
        <WorkflowVisualization
          projectId={mockProjectId}
          currentStage="execute_llm"
          isAgentActive={true}
        />
      );

      await waitFor(() => {
        // Icons should have transition-colors for smooth color changes
        const icons = document.querySelectorAll('[class*="transition-colors"]');
        expect(icons.length).toBeGreaterThan(0);
      });
    });
  });

  describe('Project ID Handling', () => {
    it('passes project ID to getWorkflowConfig API call', async () => {
      const customProjectId = 'custom-project-123';
      
      renderWithTheme(
        <WorkflowVisualization
          projectId={customProjectId}
          currentStage={null}
          isAgentActive={false}
        />
      );

      await waitFor(() => {
        expect(felixApi.getWorkflowConfig).toHaveBeenCalledWith(customProjectId);
      });
    });

    it('refetches config when project ID changes', async () => {
      const { rerender } = renderWithTheme(
        <WorkflowVisualization
          projectId="project-1"
          currentStage={null}
          isAgentActive={false}
        />
      );

      await waitFor(() => {
        expect(felixApi.getWorkflowConfig).toHaveBeenCalledWith('project-1');
      });

      vi.mocked(felixApi.getWorkflowConfig).mockClear();

      rerender(
        <ThemeProvider defaultTheme="dark">
          <WorkflowVisualization
            projectId="project-2"
            currentStage={null}
            isAgentActive={false}
          />
        </ThemeProvider>
      );

      await waitFor(() => {
        expect(felixApi.getWorkflowConfig).toHaveBeenCalledWith('project-2');
      });
    });
  });
});

describe('LiveConsolePanel Split Layout (S-0030)', () => {
  // Note: Full split layout tests would require mocking AgentDashboard
  // These tests verify WorkflowVisualization integrates correctly
  
  it('WorkflowVisualization component can be rendered standalone', async () => {
    renderWithTheme(
      <WorkflowVisualization
        projectId="test-project"
        currentStage="execute_llm"
        isAgentActive={true}
      />
    );

    await waitFor(() => {
      expect(screen.getByText('LLM')).toBeInTheDocument();
    });
  });

  it('WorkflowVisualization has horizontal overflow scroll for many stages', async () => {
    renderWithTheme(
      <WorkflowVisualization
        projectId="test-project"
        currentStage="execute_llm"
        isAgentActive={true}
      />
    );

    await waitFor(() => {
      const scrollContainer = screen.getByText('LLM').closest('[class*="overflow-x-auto"]');
      expect(scrollContainer).toHaveClass('overflow-x-auto');
    });
  });
});


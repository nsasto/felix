import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import RequirementsKanban from '../../components/RequirementsKanban';
import { ThemeProvider } from '../../hooks/ThemeProvider';
import { felixApi, Requirement } from '../../services/felixApi';

// Mock the felixApi module
vi.mock('../../services/felixApi', () => ({
  felixApi: {
    getRequirements: vi.fn(),
    updateRequirementStatus: vi.fn(),
    getRequirementStatus: vi.fn(),
    getSpec: vi.fn(),
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

// Storage key constant - must match the one in RequirementsKanban.tsx
const COMPACT_VIEW_STORAGE_KEY = 'felix-kanban-compact-view';

// Mock requirements data
const mockRequirements: Requirement[] = [
  {
    id: 'S-0001',
    title: 'Test Requirement 1',
    spec_path: 'specs/S-0001.md',
    status: 'planned',
    priority: 'high',
    tags: ['frontend', 'ui'],
    depends_on: [],
    updated_at: '2026-01-15',
  },
  {
    id: 'S-0002',
    title: 'Test Requirement 2 with a longer title that should be truncated in compact mode',
    spec_path: 'specs/S-0002.md',
    status: 'in_progress',
    priority: 'medium',
    tags: ['backend'],
    depends_on: ['S-0001'],
    updated_at: '2026-01-20',
  },
  {
    id: 'S-0003',
    title: 'Test Requirement 3',
    spec_path: 'specs/S-0003.md',
    status: 'complete',
    priority: 'low',
    tags: [],
    depends_on: [],
    updated_at: '2026-01-25',
  },
];

describe('RequirementsKanban (S-0025: Compact View Toggle)', () => {
  const mockProjectId = 'test-project';

  beforeEach(() => {
    vi.clearAllMocks();
    // Clear localStorage before each test
    localStorage.removeItem(COMPACT_VIEW_STORAGE_KEY);
    
    // Default mocks
    vi.mocked(felixApi.getRequirements).mockResolvedValue({
      requirements: mockRequirements,
    });
    vi.mocked(felixApi.updateRequirementStatus).mockResolvedValue({
      id: 'S-0001',
      status: 'planned',
      title: 'Test Requirement 1',
      has_plan: false,
      plan_path: null,
      plan_modified_at: null,
      spec_modified_at: null,
    });
    vi.mocked(felixApi.getRequirementStatus).mockResolvedValue({
      id: 'S-0001',
      status: 'planned',
      title: 'Test Requirement 1',
      has_plan: false,
      plan_path: null,
      plan_modified_at: null,
      spec_modified_at: null,
    });
    vi.mocked(felixApi.getSpec).mockResolvedValue({
      content: '',
    });
  });

  afterEach(() => {
    localStorage.removeItem(COMPACT_VIEW_STORAGE_KEY);
  });

  describe('Initial State and localStorage', () => {
    it('defaults to normal (non-compact) view when localStorage is empty', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      // Wait for requirements to load
      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Find the compact view checkbox
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      expect(compactCheckbox).not.toBeChecked();
    });

    it('loads compact view state from localStorage on mount', async () => {
      // Set compact mode in localStorage before rendering
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      // Wait for requirements to load
      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Checkbox should be checked
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      expect(compactCheckbox).toBeChecked();
    });

    it('defaults to normal view when localStorage has false value', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'false');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      expect(compactCheckbox).not.toBeChecked();
    });
  });

  describe('Toggle Functionality', () => {
    it('toggles to compact view when checkbox is clicked', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Click the compact view checkbox
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      fireEvent.click(compactCheckbox);

      // Checkbox should now be checked
      expect(compactCheckbox).toBeChecked();
    });

    it('toggles back to normal view when checkbox is clicked twice', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      
      // Toggle to compact
      fireEvent.click(compactCheckbox);
      expect(compactCheckbox).toBeChecked();
      
      // Toggle back to normal
      fireEvent.click(compactCheckbox);
      expect(compactCheckbox).not.toBeChecked();
    });

    it('persists compact view state to localStorage', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Verify initial localStorage state
      expect(localStorage.getItem(COMPACT_VIEW_STORAGE_KEY)).toBe('false');

      // Toggle to compact
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      fireEvent.click(compactCheckbox);

      // Verify localStorage was updated
      await waitFor(() => {
        expect(localStorage.getItem(COMPACT_VIEW_STORAGE_KEY)).toBe('true');
      });

      // Toggle back to normal
      fireEvent.click(compactCheckbox);

      await waitFor(() => {
        expect(localStorage.getItem(COMPACT_VIEW_STORAGE_KEY)).toBe('false');
      });
    });
  });

  describe('Compact Card Styling', () => {
    it('applies compact card CSS class when compact mode is enabled', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Get all kanban cards
      const cards = document.querySelectorAll('.kanban-card');
      expect(cards.length).toBeGreaterThan(0);
      
      // Initially, cards should not have compact class
      cards.forEach(card => {
        expect(card).not.toHaveClass('kanban-card-compact');
      });

      // Toggle to compact
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      fireEvent.click(compactCheckbox);

      // Cards should now have compact class
      const compactCards = document.querySelectorAll('.kanban-card-compact');
      expect(compactCards.length).toBeGreaterThan(0);
    });

    it('removes compact card CSS class when compact mode is disabled', async () => {
      // Start with compact mode enabled
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Cards should have compact class initially
      let compactCards = document.querySelectorAll('.kanban-card-compact');
      expect(compactCards.length).toBeGreaterThan(0);

      // Toggle off compact mode
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });
      fireEvent.click(compactCheckbox);

      // Cards should no longer have compact class
      compactCards = document.querySelectorAll('.kanban-card-compact');
      expect(compactCards.length).toBe(0);
    });
  });

  describe('Content Visibility in Compact Mode', () => {
    it('always shows requirement ID in compact mode', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
        expect(screen.getByText('S-0002')).toBeInTheDocument();
        expect(screen.getByText('S-0003')).toBeInTheDocument();
      });
    });

    it('always shows priority badge in compact mode', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('high')).toBeInTheDocument();
        expect(screen.getByText('medium')).toBeInTheDocument();
        expect(screen.getByText('low')).toBeInTheDocument();
      });
    });

    it('shows active indicator for in-progress requirements in compact mode', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0002')).toBeInTheDocument();
      });

      // Should show "Active" indicator for in_progress requirement
      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    it('hides tags section in compact mode (via CSS)', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // tags are still in DOM but hidden via CSS (opacity: 0, max-height: 0)
      // The hideable sections have class kanban-card-section-hideable
      const hideableSections = document.querySelectorAll('.kanban-card-section-hideable');
      expect(hideableSections.length).toBeGreaterThan(0);
    });

    it('hides View Spec button in compact mode (via CSS)', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // View Spec buttons are not rendered in compact mode
      expect(screen.queryByText('View Spec')).not.toBeInTheDocument();
    });
  });

  describe('Dependency Warnings in Compact Mode', () => {
    it('shows icon and count only for dependency warnings in compact mode', async () => {
      // Create requirements with dependency
      const reqsWithDeps: Requirement[] = [
        {
          id: 'S-0001',
          title: 'Test Requirement 1',
          spec_path: 'specs/S-0001.md',
          status: 'planned',  // Not complete, so S-0002 has incomplete dependency
          priority: 'high',
          tags: [],
          depends_on: [],
          updated_at: '2026-01-15',
        },
        {
          id: 'S-0002',
          title: 'Test Requirement 2',
          spec_path: 'specs/S-0002.md',
          status: 'planned',
          priority: 'medium',
          tags: [],
          depends_on: ['S-0001'],  // Depends on incomplete S-0001
          updated_at: '2026-01-20',
        },
      ];

      vi.mocked(felixApi.getRequirements).mockResolvedValue({
        requirements: reqsWithDeps,
      });

      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0002')).toBeInTheDocument();
      });

      // In compact mode, should show "⚠️ 1" for the dependency warning count
      expect(screen.getByText(/⚠️ 1/)).toBeInTheDocument();
      // Should NOT show the full "incomplete dependency" text
      expect(screen.queryByText(/incomplete dependency/i)).not.toBeInTheDocument();
    });

    it('shows full dependency text in normal mode', async () => {
      const reqsWithDeps: Requirement[] = [
        {
          id: 'S-0001',
          title: 'Test Requirement 1',
          spec_path: 'specs/S-0001.md',
          status: 'planned',
          priority: 'high',
          tags: [],
          depends_on: [],
          updated_at: '2026-01-15',
        },
        {
          id: 'S-0002',
          title: 'Test Requirement 2',
          spec_path: 'specs/S-0002.md',
          status: 'planned',
          priority: 'medium',
          tags: [],
          depends_on: ['S-0001'],
          updated_at: '2026-01-20',
        },
      ];

      vi.mocked(felixApi.getRequirements).mockResolvedValue({
        requirements: reqsWithDeps,
      });

      // Normal mode (not compact)
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'false');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0002')).toBeInTheDocument();
      });

      // In normal mode, should show full dependency text
      expect(screen.getByText(/1 incomplete dependency/i)).toBeInTheDocument();
    });
  });

  describe('Card Interactions', () => {
    it('cards remain clickable in compact mode', async () => {
      const mockOnSelectRequirement = vi.fn();
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(
        <RequirementsKanban 
          projectId={mockProjectId} 
          onSelectRequirement={mockOnSelectRequirement}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Click on a card - find the card by its ID and click
      const cardId = screen.getByText('S-0001');
      const card = cardId.closest('.kanban-card');
      expect(card).toBeInTheDocument();
      
      fireEvent.click(card!);

      // Should have called the select handler
      expect(mockOnSelectRequirement).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'S-0001' })
      );
    });

    it('cards remain draggable in compact mode', async () => {
      localStorage.setItem(COMPACT_VIEW_STORAGE_KEY, 'true');

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Find a card and check it has draggable attribute
      const cardId = screen.getByText('S-0001');
      const card = cardId.closest('.kanban-card');
      expect(card).toHaveAttribute('draggable', 'true');
    });
  });

  describe('Filter Bar Toggle Position', () => {
    it('shows Compact toggle next to Show Done toggle in filter bar', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Both toggles should exist in the filter bar
      const showDoneCheckbox = screen.getByRole('switch', { name: /show done/i });
      const compactCheckbox = screen.getByRole('switch', { name: /compact/i });

      expect(showDoneCheckbox).toBeInTheDocument();
      expect(compactCheckbox).toBeInTheDocument();
    });
  });

  describe('Loading and Error States', () => {
    it('shows loading state while fetching requirements', async () => {
      // Create a pending promise
      let resolveRequirements: (value: any) => void;
      const pendingPromise = new Promise((resolve) => {
        resolveRequirements = resolve;
      });
      vi.mocked(felixApi.getRequirements).mockReturnValue(pendingPromise as any);

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      // Should show loading state
      expect(screen.getByText(/loading requirements/i)).toBeInTheDocument();

      // Resolve the promise
      resolveRequirements!({ requirements: mockRequirements });

      // Should now show requirements
      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });
    });

    it('shows error state when fetch fails', async () => {
      vi.mocked(felixApi.getRequirements).mockRejectedValue(new Error('Network error'));

      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText(/error loading requirements/i)).toBeInTheDocument();
      });
    });
  });
});

describe('RequirementsKanban (S-0028: Show Done In Dropzone)', () => {
  const mockProjectId = 'test-project';

  // Mock requirements with one in Done status to verify column visibility
  const mockRequirementsWithDone: Requirement[] = [
    {
      id: 'S-0001',
      title: 'Test Requirement 1',
      spec_path: 'specs/S-0001.md',
      status: 'planned',
      priority: 'high',
      tags: ['frontend'],
      depends_on: [],
      updated_at: '2026-01-15',
    },
    {
      id: 'S-0002',
      title: 'Test Requirement 2',
      spec_path: 'specs/S-0002.md',
      status: 'done',
      priority: 'medium',
      tags: [],
      depends_on: [],
      updated_at: '2026-01-20',
    },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.removeItem(COMPACT_VIEW_STORAGE_KEY);
    
    vi.mocked(felixApi.getRequirements).mockResolvedValue({
      requirements: mockRequirementsWithDone,
    });
    vi.mocked(felixApi.updateRequirementStatus).mockResolvedValue({
      id: 'S-0001',
      status: 'planned',
      title: 'Test Requirement 1',
      has_plan: false,
      plan_path: null,
      plan_modified_at: null,
      spec_modified_at: null,
    });
    vi.mocked(felixApi.getRequirementStatus).mockResolvedValue({
      id: 'S-0001',
      status: 'planned',
      title: 'Test Requirement 1',
      has_plan: false,
      plan_path: null,
      plan_modified_at: null,
      spec_modified_at: null,
    });
  });

  afterEach(() => {
    localStorage.removeItem(COMPACT_VIEW_STORAGE_KEY);
  });

  describe('Done Dropzone Visibility', () => {
    it('shows Done dropzone in StickyDropZones when showDone is false and dragging', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      // Wait for requirements to load
      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Verify showDone checkbox is unchecked (default)
      const showDoneCheckbox = screen.getByRole('switch', { name: /show done/i });
      expect(showDoneCheckbox).not.toBeChecked();

      // Start dragging the planned requirement card
      const cardId = screen.getByText('S-0001');
      const card = cardId.closest('.kanban-card');
      expect(card).toBeInTheDocument();

      // Start drag
      fireEvent.dragStart(card!, {
        dataTransfer: {
          effectAllowed: 'move',
          setData: vi.fn(),
        },
      });

      // The StickyDropZones should appear and contain a Done dropzone
      // Look for the sticky container with all column tags including Done
      await waitFor(() => {
        // The sticky zones should show Done column label regardless of showDone state
        const stickyDoneLabels = screen.getAllByText('Done');
        // Should have at least one Done label in the sticky dropzones
        expect(stickyDoneLabels.length).toBeGreaterThan(0);
      });
    });

    it('main kanban Done column is hidden when showDone is false', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Verify showDone is unchecked
      const showDoneCheckbox = screen.getByRole('switch', { name: /show done/i });
      expect(showDoneCheckbox).not.toBeChecked();

      // Main kanban should NOT have Done column header (there are column headers with text matching tags)
      // The kanban columns have headers with uppercase text like "DRAFT", "PLANNED", "DONE"
      const kanbanContainer = document.querySelector('.overflow-x-auto');
      expect(kanbanContainer).toBeInTheDocument();

      // Check that Done column header does NOT exist in main kanban area
      // Column headers are h3 elements with uppercase text
      const columnHeaders = kanbanContainer!.querySelectorAll('h3');
      const doneHeaders = Array.from(columnHeaders).filter(h => h.textContent?.toUpperCase() === 'DONE');
      
      // Should NOT have Done column in main kanban when showDone is false
      expect(doneHeaders.length).toBe(0);
    });

    it('main kanban Done column is visible when showDone is true', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Check the showDone checkbox
      const showDoneCheckbox = screen.getByRole('switch', { name: /show done/i });
      fireEvent.click(showDoneCheckbox);
      expect(showDoneCheckbox).toBeChecked();

      // Main kanban should now have Done column header
      const kanbanContainer = document.querySelector('.overflow-x-auto');
      expect(kanbanContainer).toBeInTheDocument();

      // Check that Done column header EXISTS in main kanban area
      expect(within(kanbanContainer!).getByText('Done')).toBeInTheDocument();
    });

    it('StickyDropZones shows all columns including Done regardless of showDone filter', async () => {
      renderWithTheme(<RequirementsKanban projectId={mockProjectId} />);

      await waitFor(() => {
        expect(screen.getByText('S-0001')).toBeInTheDocument();
      });

      // Verify showDone is unchecked (Done column hidden in main kanban)
      const showDoneCheckbox = screen.getByRole('switch', { name: /show done/i });
      expect(showDoneCheckbox).not.toBeChecked();

      // Start dragging a card
      const cardId = screen.getByText('S-0001');
      const card = cardId.closest('.kanban-card');
      
      fireEvent.dragStart(card!, {
        dataTransfer: {
          effectAllowed: 'move',
          setData: vi.fn(),
        },
      });

      // StickyDropZones should appear with all 6 columns: Draft, Planned, In Progress, Complete, Blocked, Done
      await waitFor(() => {
        // Check for presence of all column tags in sticky zones
        // The fixed sticky container should show all columns
        const fixedContainer = document.querySelector('.fixed');
        expect(fixedContainer).toBeInTheDocument();

        const fixedScope = within(fixedContainer as HTMLElement);
        // All expected column tags should be present
        expect(fixedScope.getByText('Draft')).toBeInTheDocument();
        expect(fixedScope.getByText('Planned')).toBeInTheDocument();
        expect(fixedScope.getByText('In Progress')).toBeInTheDocument();
        expect(fixedScope.getByText('Complete')).toBeInTheDocument();
        expect(fixedScope.getByText('Blocked')).toBeInTheDocument();
        expect(fixedScope.getByText('Done')).toBeInTheDocument();
      });
    });
  });
});



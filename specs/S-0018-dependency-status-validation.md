# S-0018: Dependency Status Validation

## Narrative

As a Felix user viewing requirements in the kanban board or specs list, I need accurate dependency status indicators that only flag truly incomplete dependencies, so that I don't see false warnings for requirements whose dependencies are already complete.

Currently, the system may flag dependencies as incomplete even when they are marked as "done" or "complete". This creates confusion and makes it difficult to understand which requirements are truly blocked versus which are ready to work on. Users waste time investigating dependency status manually instead of trusting the visual indicators.

This requirement ensures dependency validation logic correctly recognizes completed dependencies. A dependency should only be flagged as incomplete if its status is `draft`, `planned`, `in_progress`, or `blocked` - NOT if it's `done` or `complete`.

## Acceptance Criteria

### Dependency Status Logic

- [ ] Requirement with all dependencies marked `done` or `complete` shows no incomplete dependency warning
- [ ] Requirement with at least one dependency in `draft` status shows incomplete dependency warning
- [ ] Requirement with at least one dependency in `planned` status shows incomplete dependency warning
- [ ] Requirement with at least one dependency in `in_progress` status shows incomplete dependency warning
- [ ] Requirement with at least one dependency in `blocked` status shows incomplete dependency warning
- [ ] Requirement with no dependencies never shows dependency warning
- [ ] Requirement with mix of `done` and incomplete dependencies shows warning (only incomplete ones flagged)

### Visual Indicators

- [ ] Kanban card shows dependency indicator only when dependencies are incomplete
- [ ] Dependency indicator icon: ⚠️ or 🔗 with warning color (amber/yellow)
- [ ] Hover tooltip lists incomplete dependencies by ID and title
- [ ] Tooltip shows status of each incomplete dependency (e.g., "S-0015: planned")
- [ ] Completed dependencies (done/complete) not listed in warning tooltip
- [ ] Spec list view shows same dependency indicators as kanban
- [ ] Requirement detail slide-out shows dependency section with color-coded status badges

### Dependency Section Display

- [ ] Dependencies section shows all dependencies (complete and incomplete)
- [ ] Completed dependencies: Green badge with ✓ icon
- [ ] Incomplete dependencies: Yellow/red badge with status label
- [ ] Dependencies clickable to navigate to that requirement
- [ ] Dependencies ordered: incomplete first, then completed
- [ ] Empty dependencies section hidden if no dependencies exist

### Status Change Updates

- [ ] Marking a dependency as `done` immediately updates all dependents (removes warning if last incomplete)
- [ ] Marking a dependency back to `planned` re-adds warning to all dependents
- [ ] Real-time update without page refresh (if feasible with current architecture)
- [ ] Changing status via kanban drag-drop triggers dependency validation
- [ ] Changing status via spec editor or settings updates dependency indicators

### Backend Validation

- [ ] API endpoint validates dependencies before allowing status change to `in_progress` or `done`
- [ ] Validation rule: Cannot move to `in_progress` if any dependency is not `complete` or `done` (optional, can warn instead of block)
- [ ] Validation returns list of incomplete dependencies if check fails
- [ ] Frontend shows dialog: "This requirement has incomplete dependencies: [list]. Continue anyway?"
- [ ] User can override validation and proceed (soft validation, not hard block)

## Technical Notes

### Architecture

**Dependency Status Check Function:**

```typescript
// app/frontend/utils/dependencies.ts

export type RequirementStatus = 'draft' | 'planned' | 'in_progress' | 'complete' | 'blocked' | 'done';

export interface Requirement {
  id: string;
  title: string;
  status: RequirementStatus;
  depends_on: string[];
}

/**
 * Check if a dependency status is considered complete
 */
export function isDependencyComplete(status: RequirementStatus): boolean {
  return status === 'done' || status === 'complete';
}

/**
 * Get incomplete dependencies for a requirement
 */
export function getIncompleteDependencies(
  requirement: Requirement,
  allRequirements: Requirement[]
): Requirement[] {
  if (!requirement.depends_on || requirement.depends_on.length === 0) {
    return [];
  }
  
  const incompleteDeps: Requirement[] = [];
  
  for (const depId of requirement.depends_on) {
    const dep = allRequirements.find(r => r.id === depId);
    
    if (!dep) {
      // Dependency not found - treat as incomplete
      console.warn(`Dependency ${depId} not found for ${requirement.id}`);
      continue;
    }
    
    if (!isDependencyComplete(dep.status)) {
      incompleteDeps.push(dep);
    }
  }
  
  return incompleteDeps;
}

/**
 * Check if requirement has any incomplete dependencies
 */
export function hasIncompleteDependencies(
  requirement: Requirement,
  allRequirements: Requirement[]
): boolean {
  return getIncompleteDependencies(requirement, allRequirements).length > 0;
}

/**
 * Get all dependencies (complete and incomplete) with status info
 */
export function getAllDependenciesWithStatus(
  requirement: Requirement,
  allRequirements: Requirement[]
): Array<{ requirement: Requirement; isComplete: boolean }> {
  if (!requirement.depends_on || requirement.depends_on.length === 0) {
    return [];
  }
  
  return requirement.depends_on
    .map(depId => {
      const dep = allRequirements.find(r => r.id === depId);
      if (!dep) return null;
      
      return {
        requirement: dep,
        isComplete: isDependencyComplete(dep.status)
      };
    })
    .filter(Boolean) as Array<{ requirement: Requirement; isComplete: boolean }>;
}
```

**Kanban Card Dependency Indicator:**

```tsx
// app/frontend/components/RequirementsKanban.tsx

import { hasIncompleteDependencies, getIncompleteDependencies } from '../utils/dependencies';

const RequirementCard: React.FC<{ requirement: Requirement; allRequirements: Requirement[] }> = ({
  requirement,
  allRequirements
}) => {
  const incompleteDeps = getIncompleteDependencies(requirement, allRequirements);
  const hasIncomplete = incompleteDeps.length > 0;
  
  return (
    <div className="requirement-card">
      {/* Card header with ID and status */}
      <div className="flex items-center justify-between">
        <span className="requirement-id">{requirement.id}</span>
        
        {/* Dependency warning indicator */}
        {hasIncomplete && (
          <div
            className="dependency-indicator"
            title={`Incomplete dependencies:\n${incompleteDeps.map(d => `${d.id}: ${d.status}`).join('\n')}`}
          >
            <span className="text-amber-500">⚠️</span>
          </div>
        )}
      </div>
      
      <div className="requirement-title">{requirement.title}</div>
      
      {/* Dependency badges */}
      {requirement.depends_on && requirement.depends_on.length > 0 && (
        <div className="dependency-badges mt-2 flex flex-wrap gap-1">
          {incompleteDeps.map(dep => (
            <span
              key={dep.id}
              className="text-[9px] px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-400 border border-amber-500/30"
              title={`Dependency ${dep.id} is ${dep.status}`}
            >
              🔗 {dep.id}
            </span>
          ))}
        </div>
      )}
    </div>
  );
};
```

**Requirement Detail Slide-Out Dependencies Section:**

```tsx
// app/frontend/components/RequirementDetailSlideOut.tsx

import { getAllDependenciesWithStatus } from '../utils/dependencies';

const DependenciesSection: React.FC<{ requirement: Requirement; allRequirements: Requirement[] }> = ({
  requirement,
  allRequirements
}) => {
  const dependencies = getAllDependenciesWithStatus(requirement, allRequirements);
  
  if (dependencies.length === 0) {
    return null; // Don't show section if no dependencies
  }
  
  // Sort: incomplete first, then complete
  const sorted = [...dependencies].sort((a, b) => {
    if (a.isComplete === b.isComplete) return 0;
    return a.isComplete ? 1 : -1;
  });
  
  return (
    <div className="dependencies-section">
      <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-3">
        Dependencies
      </h3>
      
      <div className="space-y-2">
        {sorted.map(({ requirement: dep, isComplete }) => (
          <div
            key={dep.id}
            className="flex items-center gap-2 p-2 rounded-lg theme-bg-elevated hover:bg-slate-800/60 cursor-pointer"
            onClick={() => navigateToRequirement(dep.id)}
          >
            {/* Status icon */}
            <span className="text-lg">
              {isComplete ? '✓' : '⚠️'}
            </span>
            
            {/* Requirement info */}
            <div className="flex-1">
              <div className="text-xs font-mono theme-text-primary">{dep.id}</div>
              <div className="text-[10px] theme-text-muted">{dep.title}</div>
            </div>
            
            {/* Status badge */}
            <span
              className={`text-[9px] font-bold px-2 py-1 rounded uppercase ${
                isComplete
                  ? 'bg-green-500/20 text-green-400 border border-green-500/30'
                  : 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
              }`}
            >
              {dep.status}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};
```

**Backend Dependency Validation (Optional):**

```python
# app/backend/routers/requirements.py

from typing import List, Dict
from fastapi import APIRouter, HTTPException

@router.put("/{project_id}/requirements/{requirement_id}/status")
async def update_requirement_status(
    project_id: str,
    requirement_id: str,
    new_status: str
):
    """Update requirement status with dependency validation"""
    
    # Load requirements
    requirements = load_requirements(project_id)
    requirement = next((r for r in requirements if r['id'] == requirement_id), None)
    
    if not requirement:
        raise HTTPException(status_code=404, detail="Requirement not found")
    
    # Validate dependencies if moving to in_progress or done
    if new_status in ['in_progress', 'done']:
        incomplete_deps = get_incomplete_dependencies(requirement, requirements)
        
        if incomplete_deps:
            return {
                "success": False,
                "warning": True,
                "message": "This requirement has incomplete dependencies",
                "incomplete_dependencies": [
                    {"id": dep['id'], "title": dep['title'], "status": dep['status']}
                    for dep in incomplete_deps
                ]
            }
    
    # Update status
    requirement['status'] = new_status
    save_requirements(project_id, requirements)
    
    return {"success": True, "requirement": requirement}

def get_incomplete_dependencies(requirement: Dict, all_requirements: List[Dict]) -> List[Dict]:
    """Get list of incomplete dependencies"""
    depends_on = requirement.get('depends_on', [])
    if not depends_on:
        return []
    
    incomplete = []
    for dep_id in depends_on:
        dep = next((r for r in all_requirements if r['id'] == dep_id), None)
        if dep and dep['status'] not in ['done', 'complete']:
            incomplete.append(dep)
    
    return incomplete
```

**Status Change Dialog (Frontend):**

```tsx
// app/frontend/components/DependencyWarningDialog.tsx

interface DependencyWarningDialogProps {
  requirement: Requirement;
  incompleteDependencies: Requirement[];
  onContinue: () => void;
  onCancel: () => void;
}

const DependencyWarningDialog: React.FC<DependencyWarningDialogProps> = ({
  requirement,
  incompleteDependencies,
  onContinue,
  onCancel
}) => {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-slate-900 border border-slate-700 rounded-2xl p-6 max-w-md">
        <h2 className="text-lg font-bold text-white mb-2">
          ⚠️ Incomplete Dependencies
        </h2>
        
        <p className="text-sm text-slate-400 mb-4">
          {requirement.id} has the following incomplete dependencies:
        </p>
        
        <div className="space-y-2 mb-6">
          {incompleteDependencies.map(dep => (
            <div key={dep.id} className="flex items-center gap-3 p-2 bg-slate-800 rounded-lg">
              <span className="text-xs font-mono text-amber-400">{dep.id}</span>
              <span className="text-xs text-slate-400 flex-1">{dep.title}</span>
              <span className="text-[9px] px-2 py-1 rounded bg-amber-500/20 text-amber-400 uppercase">
                {dep.status}
              </span>
            </div>
          ))}
        </div>
        
        <p className="text-xs text-slate-500 mb-4">
          It's recommended to complete dependencies before starting this requirement.
          Continue anyway?
        </p>
        
        <div className="flex gap-3 justify-end">
          <button
            onClick={onCancel}
            className="px-4 py-2 text-sm rounded-lg bg-slate-800 text-slate-300 hover:bg-slate-700"
          >
            Cancel
          </button>
          <button
            onClick={onContinue}
            className="px-4 py-2 text-sm rounded-lg bg-felix-500 text-white hover:bg-felix-600"
          >
            Continue Anyway
          </button>
        </div>
      </div>
    </div>
  );
};
```

### Real-Time Updates

When a requirement status changes (e.g., marked as `done`), the system should:

1. Update the requirement in `requirements.json`
2. Re-fetch requirements in frontend (or update local state)
3. Recalculate dependency indicators for all requirements
4. Update UI to reflect new dependency statuses

For real-time updates across components:
- Use React Context or state management library (Zustand/Redux)
- Or re-fetch requirements after any status change
- Or emit event that triggers re-render of affected components

### Performance Considerations

- Dependency checks run on every render - memoize results with `useMemo`
- Cache incomplete dependencies calculation per requirement
- Only recalculate when `requirements` array changes (reference equality)

```typescript
// Memoized dependency check
const incompleteDeps = useMemo(
  () => getIncompleteDependencies(requirement, allRequirements),
  [requirement.id, requirement.depends_on, allRequirements]
);
```

## Dependencies

- S-0003 (Frontend Observer UI) - requires kanban board and requirement components
- S-0002 (Backend API) - may need status update validation endpoint

## Non-Goals

- Hard blocking of status changes (only soft warnings)
- Circular dependency detection (future enhancement)
- Dependency graph visualization (future enhancement)
- Automatic status propagation (marking parent done when all children done)
- Dependency version tracking or history
- Cross-project dependencies

## Validation Criteria

- [ ] Create requirement with dependency on draft spec, verify warning shows
- [ ] Mark dependency as done, verify warning disappears immediately
- [ ] Create requirement with multiple dependencies (some done, some planned), verify only incomplete shown in warning
- [ ] Hover dependency indicator, verify tooltip lists incomplete dependencies with status
- [ ] Click dependency in slide-out, verify navigates to that requirement
- [ ] Attempt to move requirement to in_progress with incomplete dependencies, verify warning dialog appears
- [ ] Click "Continue Anyway" in dialog, verify status updates despite incomplete dependencies
- [ ] Create requirement with all dependencies done, verify no warning indicator appears
- [ ] Mark complete dependency back to planned, verify warning reappears on dependent
- [ ] Requirement with no dependencies never shows warning indicator

/**
 * Dependency Status Validation Utilities
 * 
 * Provides functions to check and validate dependency statuses for requirements.
 * A dependency is considered complete if its status is 'done' or 'complete'.
 * 
 * S-0018: Dependency Status Validation
 */

import { Requirement } from '../services/felixApi';

export type RequirementStatus = 'draft' | 'planned' | 'in_progress' | 'complete' | 'blocked' | 'done';

/**
 * Status values that indicate a dependency is complete.
 * Both 'done' and 'complete' are valid completion states.
 */
const COMPLETE_STATUSES: RequirementStatus[] = ['done', 'complete'];

/**
 * Check if a dependency status is considered complete.
 * A dependency is complete if its status is 'done' or 'complete'.
 * 
 * @param status - The status to check
 * @returns true if the status indicates completion
 */
export function isDependencyComplete(status: string): boolean {
  return COMPLETE_STATUSES.includes(status as RequirementStatus);
}

/**
 * Dependency information with completion status
 */
export interface DependencyInfo {
  requirement: Requirement;
  isComplete: boolean;
}

/**
 * Get incomplete dependencies for a requirement.
 * Returns only dependencies that are NOT in 'done' or 'complete' status.
 * 
 * @param requirement - The requirement to check dependencies for
 * @param allRequirements - All requirements to look up dependencies
 * @returns Array of incomplete dependency requirements
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
      // Dependency not found - skip (could log warning in dev)
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
 * Check if a requirement has any incomplete dependencies.
 * 
 * @param requirement - The requirement to check
 * @param allRequirements - All requirements to look up dependencies
 * @returns true if any dependency is not 'done' or 'complete'
 */
export function hasIncompleteDependencies(
  requirement: Requirement,
  allRequirements: Requirement[]
): boolean {
  return getIncompleteDependencies(requirement, allRequirements).length > 0;
}

/**
 * Get all dependencies (complete and incomplete) with status information.
 * Useful for displaying a full dependency list with visual indicators.
 * 
 * @param requirement - The requirement to get dependencies for
 * @param allRequirements - All requirements to look up dependencies
 * @returns Array of dependencies with completion status, sorted (incomplete first)
 */
export function getAllDependenciesWithStatus(
  requirement: Requirement,
  allRequirements: Requirement[]
): DependencyInfo[] {
  if (!requirement.depends_on || requirement.depends_on.length === 0) {
    return [];
  }
  
  const dependencies = requirement.depends_on
    .map(depId => {
      const dep = allRequirements.find(r => r.id === depId);
      if (!dep) return null;
      
      return {
        requirement: dep,
        isComplete: isDependencyComplete(dep.status)
      };
    })
    .filter((item): item is DependencyInfo => item !== null);
  
  // Sort: incomplete first, then completed
  return dependencies.sort((a, b) => {
    if (a.isComplete === b.isComplete) return 0;
    return a.isComplete ? 1 : -1;
  });
}

/**
 * Format incomplete dependencies for display in a tooltip.
 * Returns a string like "S-0001: planned, S-0003: in_progress"
 * 
 * @param incompleteDeps - Array of incomplete dependency requirements
 * @returns Formatted string for tooltip display
 */
export function formatIncompleteDependenciesTooltip(incompleteDeps: Requirement[]): string {
  if (incompleteDeps.length === 0) return '';
  
  return incompleteDeps
    .map(dep => `${dep.id}: ${dep.status}`)
    .join('\n');
}

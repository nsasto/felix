import { useState, useEffect, useCallback } from 'react';
import { felixApi, RequirementStatusResponse } from '../services/felixApi';

/**
 * Hook to check requirement status when opening spec editor.
 * Used for S-0006: Spec Edit Safety and Plan Invalidation.
 * 
 * @param projectId - The project ID
 * @param specFilename - The spec filename (e.g., "S-0001-felix-agent.md")
 * @returns Status information including loading state, error, and requirement data
 */
export function useRequirementStatus(projectId: string, specFilename: string | null) {
  const [status, setStatus] = useState<RequirementStatusResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Extract requirement ID from filename (e.g., "S-0001-felix-agent.md" -> "S-0001")
  const extractRequirementId = useCallback((filename: string): string | null => {
    const match = filename.match(/^(S-\d+)/);
    return match ? match[1] : null;
  }, []);

  // Fetch status when spec filename changes
  useEffect(() => {
    if (!projectId || !specFilename) {
      setStatus(null);
      setError(null);
      return;
    }

    const requirementId = extractRequirementId(specFilename);
    if (!requirementId) {
      setStatus(null);
      setError(null);
      return;
    }

    const fetchStatus = async () => {
      setLoading(true);
      setError(null);
      try {
        const result = await felixApi.getRequirementStatus(projectId, requirementId);
        setStatus(result);
      } catch (err) {
        console.error('Failed to fetch requirement status:', err);
        // Don't set error state - gracefully degrade if status check fails
        // This prevents blocking spec editing if the API endpoint isn't available
        setStatus(null);
      } finally {
        setLoading(false);
      }
    };

    fetchStatus();
  }, [projectId, specFilename, extractRequirementId]);

  // Refresh status (useful after blocking a requirement)
  const refreshStatus = useCallback(async () => {
    if (!projectId || !specFilename) return;
    
    const requirementId = extractRequirementId(specFilename);
    if (!requirementId) return;

    setLoading(true);
    try {
      const result = await felixApi.getRequirementStatus(projectId, requirementId);
      setStatus(result);
    } catch (err) {
      console.error('Failed to refresh requirement status:', err);
    } finally {
      setLoading(false);
    }
  }, [projectId, specFilename, extractRequirementId]);

  // Check if requirement is in progress
  const isInProgress = status?.status === 'in_progress';

  // Check if requirement has an active plan
  const hasPlan = status?.has_plan ?? false;

  // Get the requirement ID from current spec
  const requirementId = specFilename ? extractRequirementId(specFilename) : null;

  return {
    status,
    loading,
    error,
    isInProgress,
    hasPlan,
    requirementId,
    refreshStatus,
  };
}

export default useRequirementStatus;

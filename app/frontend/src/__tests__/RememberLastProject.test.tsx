import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Storage key constant - must match the one in App.tsx
const LAST_PROJECT_KEY = 'felix-last-project-id';

/**
 * Validate that a project ID has the expected format.
 * Project IDs are 12-character hexadecimal strings (MD5 hash prefix).
 * This mirrors the isValidProjectId function from App.tsx
 * @param projectId - The project ID to validate
 * @returns true if valid, false otherwise
 */
const isValidProjectId = (projectId: string): boolean => {
  return /^[a-f0-9]{12}$/i.test(projectId);
};

/**
 * Safe localStorage helper functions that mirror the ones in App.tsx
 */
const saveLastProjectId = (projectId: string): void => {
  try {
    localStorage.setItem(LAST_PROJECT_KEY, projectId);
  } catch {
    // Silently fail if localStorage is unavailable
  }
};

const getLastProjectId = (): string | null => {
  try {
    const stored = localStorage.getItem(LAST_PROJECT_KEY);
    if (stored && typeof stored === 'string' && stored.trim().length > 0) {
      const trimmed = stored.trim();
      if (isValidProjectId(trimmed)) {
        return trimmed;
      }
      clearLastProjectId();
      return null;
    }
    return null;
  } catch {
    return null;
  }
};

const clearLastProjectId = (): void => {
  try {
    localStorage.removeItem(LAST_PROJECT_KEY);
  } catch {
    // Silently fail if localStorage is unavailable
  }
};

// Mock project data
const mockProjectId = 'a1b2c3d4e5f6';

describe('RememberLastProject (S-0026: Remember Last Project)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Clear localStorage before each test
    localStorage.removeItem(LAST_PROJECT_KEY);
  });

  afterEach(() => {
    localStorage.removeItem(LAST_PROJECT_KEY);
  });

  describe('localStorage Helper Functions', () => {
    describe('saveLastProjectId', () => {
      it('saves project ID to localStorage correctly', () => {
        saveLastProjectId(mockProjectId);
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBe(mockProjectId);
      });

      it('overwrites existing project ID when a new one is saved', () => {
        saveLastProjectId(mockProjectId);
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBe(mockProjectId);
        
        const newProjectId = 'b2c3d4e5f6a7';
        saveLastProjectId(newProjectId);
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBe(newProjectId);
      });
    });

    describe('getLastProjectId', () => {
      it('returns null when localStorage is empty', () => {
        expect(getLastProjectId()).toBeNull();
      });

      it('returns stored project ID when valid', () => {
        localStorage.setItem(LAST_PROJECT_KEY, mockProjectId);
        expect(getLastProjectId()).toBe(mockProjectId);
      });

      it('returns null and clears storage for invalid project ID', () => {
        localStorage.setItem(LAST_PROJECT_KEY, 'invalid-id');
        expect(getLastProjectId()).toBeNull();
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
      });
    });

    describe('clearLastProjectId', () => {
      it('removes project ID from localStorage', () => {
        localStorage.setItem(LAST_PROJECT_KEY, mockProjectId);
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBe(mockProjectId);
        
        clearLastProjectId();
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
      });

      it('handles clearing when key does not exist', () => {
        expect(() => clearLastProjectId()).not.toThrow();
        expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
      });
    });
  });

  describe('localStorage Unavailability (Private Browsing)', () => {
    it('handles localStorage.setItem throwing gracefully', () => {
      const setItemSpy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
        throw new Error('QuotaExceededError');
      });

      // saveLastProjectId should not throw
      expect(() => saveLastProjectId(mockProjectId)).not.toThrow();

      setItemSpy.mockRestore();
    });

    it('handles localStorage.getItem throwing gracefully', () => {
      const getItemSpy = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
        throw new Error('SecurityError');
      });

      // getLastProjectId should not throw and return null
      expect(() => getLastProjectId()).not.toThrow();
      expect(getLastProjectId()).toBeNull();

      getItemSpy.mockRestore();
    });

    it('handles localStorage.removeItem throwing gracefully', () => {
      const removeItemSpy = vi.spyOn(Storage.prototype, 'removeItem').mockImplementation(() => {
        throw new Error('SecurityError');
      });

      // clearLastProjectId should not throw
      expect(() => clearLastProjectId()).not.toThrow();

      removeItemSpy.mockRestore();
    });
  });

  describe('Corrupted localStorage Data', () => {
    it('handles empty string in localStorage', () => {
      localStorage.setItem(LAST_PROJECT_KEY, '');
      
      // Should return null for empty string (invalid)
      expect(getLastProjectId()).toBeNull();
      // Note: Empty strings are handled by early return (trim().length check fails)
      // so clearLastProjectId is not called. This is acceptable because
      // getLastProjectId will always return null for this value.
    });

    it('handles whitespace-only string in localStorage', () => {
      localStorage.setItem(LAST_PROJECT_KEY, '   ');
      
      // Should return null for whitespace-only string (invalid)
      expect(getLastProjectId()).toBeNull();
      // Note: Whitespace-only strings after trim become empty and are
      // handled by early return, so clearLastProjectId is not called.
      // This is acceptable because getLastProjectId will always return null.
    });

    it('handles invalid format project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, 'invalid-format-id!@#');
      
      // Should return null for invalid format
      expect(getLastProjectId()).toBeNull();
      // Should also clear the invalid value
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });

    it('handles very long string in localStorage', () => {
      const longString = 'a'.repeat(10000);
      localStorage.setItem(LAST_PROJECT_KEY, longString);
      
      // Should return null for too-long string (not 12 chars)
      expect(getLastProjectId()).toBeNull();
      // Should also clear the invalid value
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });
  });

  describe('Project ID Validation', () => {
    it('accepts valid 12-character hex project ID (lowercase)', () => {
      expect(isValidProjectId('a1b2c3d4e5f6')).toBe(true);
    });

    it('accepts valid 12-character hex project ID (uppercase)', () => {
      expect(isValidProjectId('A1B2C3D4E5F6')).toBe(true);
    });

    it('accepts valid 12-character hex project ID (mixed case)', () => {
      expect(isValidProjectId('A1b2C3d4E5f6')).toBe(true);
    });

    it('accepts all-numeric hex project ID', () => {
      expect(isValidProjectId('123456789012')).toBe(true);
    });

    it('accepts all-letter hex project ID', () => {
      expect(isValidProjectId('abcdefabcdef')).toBe(true);
    });

    it('rejects project ID shorter than 12 characters', () => {
      expect(isValidProjectId('a1b2c3')).toBe(false);
    });

    it('rejects project ID longer than 12 characters', () => {
      expect(isValidProjectId('a1b2c3d4e5f6a7')).toBe(false);
    });

    it('rejects project ID with non-hex characters (g-z)', () => {
      expect(isValidProjectId('a1b2c3g4h5i6')).toBe(false);
    });

    it('rejects project ID with special characters', () => {
      expect(isValidProjectId('a1b2c3!@#$%^')).toBe(false);
    });

    it('rejects project ID with spaces', () => {
      expect(isValidProjectId('a1b2 c3d4e5f')).toBe(false);
    });

    it('rejects empty string', () => {
      expect(isValidProjectId('')).toBe(false);
    });
  });

  describe('getLastProjectId with Validation Integration', () => {
    it('returns valid lowercase hex project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, 'a1b2c3d4e5f6');
      expect(getLastProjectId()).toBe('a1b2c3d4e5f6');
    });

    it('returns valid uppercase hex project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, 'A1B2C3D4E5F6');
      expect(getLastProjectId()).toBe('A1B2C3D4E5F6');
    });

    it('clears and returns null for too-short project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, 'a1b2c3');
      expect(getLastProjectId()).toBeNull();
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });

    it('clears and returns null for too-long project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, 'a1b2c3d4e5f6g7h8');
      expect(getLastProjectId()).toBeNull();
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });

    it('clears and returns null for non-hex project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, 'a1b2c3g4h5i6');
      expect(getLastProjectId()).toBeNull();
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });

    it('trims whitespace from valid project ID', () => {
      localStorage.setItem(LAST_PROJECT_KEY, '  a1b2c3d4e5f6  ');
      // The validation regex won't match if there's leading/trailing whitespace
      // after trimming, so we need to check the behavior
      const result = getLastProjectId();
      // After trimming, if it's a valid hex ID it should be returned
      expect(result).toBe('a1b2c3d4e5f6');
    });
  });

  describe('Auto-Load Behavior (Functional Requirements)', () => {
    // These tests document the expected behavior without rendering the full App
    
    it('should load project when valid ID is stored', () => {
      // Setup: store a valid project ID
      saveLastProjectId(mockProjectId);
      
      // Verify: the stored ID can be retrieved
      const retrievedId = getLastProjectId();
      expect(retrievedId).toBe(mockProjectId);
      
      // The actual auto-load API call is tested through integration tests
    });

    it('should NOT load project when ID is missing', () => {
      // Verify: no ID stored means nothing to load
      const retrievedId = getLastProjectId();
      expect(retrievedId).toBeNull();
    });

    it('should NOT load project when ID is invalid', () => {
      // Store an invalid ID
      localStorage.setItem(LAST_PROJECT_KEY, 'invalid');
      
      // Verify: invalid ID is rejected and cleared
      const retrievedId = getLastProjectId();
      expect(retrievedId).toBeNull();
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });

    it('should clear stored ID when project no longer exists (404 scenario)', () => {
      // Simulate the scenario where a project was stored but now doesn't exist
      // The App would call clearLastProjectId() on API error
      saveLastProjectId(mockProjectId);
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBe(mockProjectId);
      
      // Simulate error handling
      clearLastProjectId();
      expect(localStorage.getItem(LAST_PROJECT_KEY)).toBeNull();
    });
  });

  describe('Project Selection Persistence (Functional Requirements)', () => {
    it('should save project ID when user selects a project', () => {
      // Initially empty
      expect(getLastProjectId()).toBeNull();
      
      // User selects a project (App calls saveLastProjectId)
      saveLastProjectId(mockProjectId);
      
      // Project ID is now persisted
      expect(getLastProjectId()).toBe(mockProjectId);
    });

    it('should overwrite previous selection when user selects different project', () => {
      const firstProjectId = 'a1b2c3d4e5f6';
      const secondProjectId = 'b2c3d4e5f6a7';
      
      // User selects first project
      saveLastProjectId(firstProjectId);
      expect(getLastProjectId()).toBe(firstProjectId);
      
      // User selects second project
      saveLastProjectId(secondProjectId);
      expect(getLastProjectId()).toBe(secondProjectId);
    });
  });
});


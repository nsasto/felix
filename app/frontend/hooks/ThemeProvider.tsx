import React, { createContext, useContext, useState, useEffect, useCallback, useMemo } from 'react';

/**
 * Theme options: 'dark' (default), 'light', or 'system' (follows OS preference)
 */
export type ThemeValue = 'dark' | 'light' | 'system';

/**
 * The actual applied theme (resolved from 'system' to 'dark' or 'light')
 */
export type ResolvedTheme = 'dark' | 'light';

interface ThemeContextType {
  /** Current theme setting (may be 'system') */
  theme: ThemeValue;
  /** The actual theme being applied ('dark' or 'light') */
  resolvedTheme: ResolvedTheme;
  /** Update the theme setting */
  setTheme: (theme: ThemeValue) => void;
  /** Whether the system prefers dark mode */
  systemPrefersDark: boolean;
}

/** LocalStorage key for persisting theme preference */
const THEME_STORAGE_KEY = 'felix-theme';

/**
 * Get the stored theme from localStorage, or return the default
 */
export function getStoredTheme(): ThemeValue {
  if (typeof window === 'undefined') return 'dark';
  try {
    const stored = localStorage.getItem(THEME_STORAGE_KEY);
    if (stored === 'dark' || stored === 'light' || stored === 'system') {
      return stored;
    }
  } catch (e) {
    // localStorage not available (e.g., private browsing)
    console.warn('Could not read theme from localStorage:', e);
  }
  return 'dark';
}

/**
 * Save theme to localStorage for instant loading on next visit
 */
function storeTheme(theme: ThemeValue): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch (e) {
    console.warn('Could not save theme to localStorage:', e);
  }
}

const ThemeContext = createContext<ThemeContextType | null>(null);

/**
 * Get the system's preferred color scheme
 */
function getSystemPreference(): ResolvedTheme {
  if (typeof window === 'undefined') return 'dark';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

/**
 * Resolve a theme value to an actual theme
 */
function resolveTheme(theme: ThemeValue, systemPreference: ResolvedTheme): ResolvedTheme {
  if (theme === 'system') {
    return systemPreference;
  }
  return theme;
}

/**
 * Apply theme class to the document element with smooth transition
 */
function applyTheme(resolvedTheme: ResolvedTheme, enableTransition: boolean = true): void {
  if (typeof document === 'undefined') return;
  
  const root = document.documentElement;
  const body = document.body;
  
  // Add transition class for smooth theme switching
  if (enableTransition) {
    root.classList.add('theme-transition');
  }
  
  // Remove existing theme classes
  root.classList.remove('dark', 'light');
  body.classList.remove('dark', 'light');
  
  // Apply new theme class
  root.classList.add(resolvedTheme);
  body.classList.add(resolvedTheme);
  
  // Remove transition class after animation completes
  if (enableTransition) {
    setTimeout(() => {
      root.classList.remove('theme-transition');
    }, 250); // Match the CSS transition duration
  }
}

interface ThemeProviderProps {
  children: React.ReactNode;
  /** Initial theme value (defaults to 'dark' if not provided) */
  defaultTheme?: ThemeValue;
  /** Callback when theme changes (useful for persisting to backend) */
  onThemeChange?: (theme: ThemeValue) => void;
}

export const ThemeProvider: React.FC<ThemeProviderProps> = ({
  children,
  defaultTheme = 'dark',
  onThemeChange,
}) => {
  const [theme, setThemeState] = useState<ThemeValue>(defaultTheme);
  const [systemPrefersDark, setSystemPrefersDark] = useState<boolean>(() => 
    getSystemPreference() === 'dark'
  );

  // Calculate the resolved theme
  const systemPreference: ResolvedTheme = systemPrefersDark ? 'dark' : 'light';
  const resolvedTheme = useMemo(
    () => resolveTheme(theme, systemPreference),
    [theme, systemPreference]
  );

  // Listen for system theme changes
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    
    const handleChange = (e: MediaQueryListEvent) => {
      setSystemPrefersDark(e.matches);
    };

    // Modern browsers
    if (mediaQuery.addEventListener) {
      mediaQuery.addEventListener('change', handleChange);
      return () => mediaQuery.removeEventListener('change', handleChange);
    }
    // Legacy browsers
    // @ts-ignore - addListener is deprecated but needed for older browsers
    mediaQuery.addListener(handleChange);
    // @ts-ignore
    return () => mediaQuery.removeListener(handleChange);
  }, []);

  // Apply theme to document when resolved theme changes
  useEffect(() => {
    applyTheme(resolvedTheme, true);
  }, [resolvedTheme]);

  // Apply initial theme without transition to prevent flash
  useEffect(() => {
    applyTheme(resolvedTheme, false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Theme setter with optional callback and localStorage persistence
  const setTheme = useCallback((newTheme: ThemeValue) => {
    setThemeState(newTheme);
    storeTheme(newTheme);
    onThemeChange?.(newTheme);
  }, [onThemeChange]);

  const contextValue = useMemo<ThemeContextType>(() => ({
    theme,
    resolvedTheme,
    setTheme,
    systemPrefersDark,
  }), [theme, resolvedTheme, setTheme, systemPrefersDark]);

  return (
    <ThemeContext.Provider value={contextValue}>
      {children}
    </ThemeContext.Provider>
  );
};

/**
 * Hook to access theme context
 * @throws Error if used outside ThemeProvider
 */
export function useTheme(): ThemeContextType {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
}

/**
 * Hook to get just the resolved theme (convenience hook)
 */
export function useResolvedTheme(): ResolvedTheme {
  const { resolvedTheme } = useTheme();
  return resolvedTheme;
}

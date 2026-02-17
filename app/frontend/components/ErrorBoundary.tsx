import React, { Component, ErrorInfo, ReactNode } from "react";
import { AlertTriangle, RefreshCw, Download } from "lucide-react";
import { Button } from "./ui/button";

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
  /** Optional title to show in the error message */
  title?: string;
  /** Optional retry callback - if provided, shows a retry button */
  onRetry?: () => void;
  /** Optional download URL - if provided, shows a download link as fallback */
  downloadUrl?: string;
  /** Optional download filename */
  downloadFilename?: string;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

/**
 * ErrorBoundary component that catches JavaScript errors in its child component tree,
 * logs those errors, and displays a fallback UI instead of crashing the whole app.
 *
 * Usage:
 * ```tsx
 * <ErrorBoundary
 *   title="Unable to load artifacts"
 *   onRetry={() => refetchData()}
 *   onError={(error) => logError(error)}
 * >
 *   <MyComponent />
 * </ErrorBoundary>
 * ```
 */
class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    // Update state so the next render will show the fallback UI
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    // Log error to console for debugging
    console.error("ErrorBoundary caught an error:", error, errorInfo);

    // Store error info in state for display
    this.setState({ errorInfo });

    // Call optional error callback
    if (this.props.onError) {
      this.props.onError(error, errorInfo);
    }
  }

  handleRetry = (): void => {
    // Reset the error state
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
    });

    // Call the retry callback if provided
    if (this.props.onRetry) {
      this.props.onRetry();
    }
  };

  render(): ReactNode {
    const { hasError, error } = this.state;
    const {
      children,
      fallback,
      title,
      onRetry,
      downloadUrl,
      downloadFilename,
    } = this.props;

    if (hasError) {
      // If a custom fallback is provided, use it
      if (fallback) {
        return fallback;
      }

      // Default error UI
      return (
        <div className="flex flex-col items-center justify-center h-full min-h-[200px] text-center p-8">
          <div className="w-16 h-16 bg-amber-500/10 rounded-2xl flex items-center justify-center mb-4">
            <AlertTriangle className="w-8 h-8 text-amber-500" />
          </div>

          <h3 className="text-sm font-bold text-slate-300 mb-2">
            {title || "Something went wrong"}
          </h3>

          {error && (
            <p className="text-xs text-slate-500 max-w-md mb-4 font-mono">
              {error.message || "An unexpected error occurred"}
            </p>
          )}

          <div className="flex items-center gap-3">
            {onRetry && (
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={this.handleRetry}
                className="flex items-center gap-2"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                Retry
              </Button>
            )}

            {downloadUrl && (
              <a
                href={downloadUrl}
                download={downloadFilename || "download"}
                className="inline-flex items-center gap-2 h-8 px-3 text-xs font-semibold rounded-md border border-[var(--border-default)] bg-[var(--bg-surface-100)] text-[var(--text-secondary)] hover:bg-[var(--hover-bg)] transition-colors"
              >
                <Download className="w-3.5 h-3.5" />
                Download File
              </a>
            )}
          </div>
        </div>
      );
    }

    return children;
  }
}

export default ErrorBoundary;

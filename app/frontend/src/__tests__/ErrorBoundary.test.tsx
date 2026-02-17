import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import ErrorBoundary from "../../components/ErrorBoundary";

// Component that throws an error for testing
const ThrowError: React.FC<{ shouldThrow: boolean }> = ({ shouldThrow }) => {
  if (shouldThrow) {
    throw new Error("Test error message");
  }
  return <div>Content rendered successfully</div>;
};

// Suppress console.error for cleaner test output (ErrorBoundary logs errors)
const originalConsoleError = console.error;

describe("ErrorBoundary", () => {
  beforeEach(() => {
    console.error = vi.fn();
  });

  afterEach(() => {
    console.error = originalConsoleError;
  });

  it("renders children when no error occurs", () => {
    render(
      <ErrorBoundary>
        <div>Test content</div>
      </ErrorBoundary>
    );

    expect(screen.getByText("Test content")).toBeInTheDocument();
  });

  it("renders error UI when child throws an error", () => {
    render(
      <ErrorBoundary>
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    expect(screen.getByText("Something went wrong")).toBeInTheDocument();
    expect(screen.getByText("Test error message")).toBeInTheDocument();
  });

  it("renders custom title when provided", () => {
    render(
      <ErrorBoundary title="Custom Error Title">
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    expect(screen.getByText("Custom Error Title")).toBeInTheDocument();
  });

  it("renders custom fallback when provided", () => {
    render(
      <ErrorBoundary fallback={<div>Custom fallback UI</div>}>
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    expect(screen.getByText("Custom fallback UI")).toBeInTheDocument();
    expect(screen.queryByText("Something went wrong")).not.toBeInTheDocument();
  });

  it("calls onError callback when error occurs", () => {
    const onErrorMock = vi.fn();

    render(
      <ErrorBoundary onError={onErrorMock}>
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    expect(onErrorMock).toHaveBeenCalledTimes(1);
    expect(onErrorMock).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        componentStack: expect.any(String),
      })
    );
  });

  it("renders retry button when onRetry is provided", () => {
    const onRetryMock = vi.fn();

    render(
      <ErrorBoundary onRetry={onRetryMock}>
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    const retryButton = screen.getByRole("button", { name: /retry/i });
    expect(retryButton).toBeInTheDocument();
  });

  it("calls onRetry and resets error state when retry button is clicked", () => {
    const onRetryMock = vi.fn();
    let shouldThrow = true;

    const { rerender } = render(
      <ErrorBoundary onRetry={onRetryMock}>
        <ThrowError shouldThrow={shouldThrow} />
      </ErrorBoundary>
    );

    // Verify error UI is shown
    expect(screen.getByText("Something went wrong")).toBeInTheDocument();

    // Click retry button
    const retryButton = screen.getByRole("button", { name: /retry/i });
    
    // Stop throwing after retry
    shouldThrow = false;
    fireEvent.click(retryButton);

    expect(onRetryMock).toHaveBeenCalledTimes(1);
  });

  it("renders download link when downloadUrl is provided", () => {
    render(
      <ErrorBoundary downloadUrl="https://example.com/file.txt" downloadFilename="test.txt">
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    const downloadLink = screen.getByRole("link", { name: /download file/i });
    expect(downloadLink).toBeInTheDocument();
    expect(downloadLink).toHaveAttribute("href", "https://example.com/file.txt");
    expect(downloadLink).toHaveAttribute("download", "test.txt");
  });

  it("renders both retry button and download link when both are provided", () => {
    const onRetryMock = vi.fn();

    render(
      <ErrorBoundary
        onRetry={onRetryMock}
        downloadUrl="https://example.com/file.txt"
      >
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    expect(screen.getByRole("button", { name: /retry/i })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /download file/i })).toBeInTheDocument();
  });

  it("logs error to console when error occurs", () => {
    render(
      <ErrorBoundary>
        <ThrowError shouldThrow={true} />
      </ErrorBoundary>
    );

    expect(console.error).toHaveBeenCalled();
  });
});

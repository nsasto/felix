import React from "react";
import { cn } from "../../lib/utils";

export interface PageLoadingProps {
  /** Loading message text */
  message?: string;
  /** Spinner size variant */
  size?: "xs" | "sm" | "md" | "lg";
  /** Layout direction */
  layout?: "vertical" | "horizontal";
  /** Whether to use full-page centered layout */
  fullPage?: boolean;
  /** Color variant */
  variant?: "brand" | "muted";
  /** Whether to show text message */
  showText?: boolean;
  /** Additional CSS classes */
  className?: string;
}

const sizeClasses = {
  xs: "w-3 h-3 border-2",
  sm: "w-5 h-5 border-2",
  md: "w-6 h-6 border-2",
  lg: "w-8 h-8 border-2",
};

const variantClasses = {
  brand: "border-[var(--brand-500)]/30 border-t-[var(--brand-500)]",
  muted: "border-[var(--border-muted)] border-t-[var(--text-muted)]",
};

const gapClasses = {
  vertical: "gap-4",
  horizontal: "gap-3",
};

export function PageLoading({
  message = "Loading...",
  size = "lg",
  layout = "vertical",
  fullPage = true,
  variant = "brand",
  showText = true,
  className,
}: PageLoadingProps) {
  const spinnerClasses = cn(
    "rounded-full animate-spin",
    sizeClasses[size],
    variantClasses[variant],
  );

  const contentClasses = cn(
    "flex",
    layout === "vertical" ? "flex-col items-center" : "items-center",
    gapClasses[layout],
  );

  const wrapperClasses = cn(
    fullPage && "flex-1 flex items-center justify-center bg-[var(--bg-base)]",
    className,
  );

  const content = (
    <div className={contentClasses}>
      <div className={spinnerClasses} />
      {showText && (
        <span className="text-xs font-mono text-[var(--text-muted)] uppercase tracking-widest">
          {message}
        </span>
      )}
    </div>
  );

  if (fullPage) {
    return <div className={wrapperClasses}>{content}</div>;
  }

  return content;
}

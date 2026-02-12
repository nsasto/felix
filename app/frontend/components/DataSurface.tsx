import React from "react";
import { Card } from "./ui/card";
import { cn } from "../lib/utils";

interface DataSurfaceProps {
  title?: string;
  search?: React.ReactNode;
  filters?: React.ReactNode;
  actions?: React.ReactNode;
  viewToggle?: React.ReactNode;
  footer?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

export default function DataSurface({
  title,
  search,
  filters,
  actions,
  viewToggle,
  footer,
  children,
  className,
}: DataSurfaceProps) {
  return (
    <div className={cn("flex flex-col h-full bg-[var(--bg)]", className)}>
      {title && (
        <div className="px-6 pt-6 pb-2">
          <h1 className="text-xl font-semibold text-[var(--text)]">{title}</h1>
        </div>
      )}

      <div className="px-6 pb-4">
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex flex-1 items-center gap-3 min-w-[240px]">
            {search}
            {filters}
          </div>
          <div className="flex items-center gap-2">
            {viewToggle}
            {actions}
          </div>
        </div>
      </div>

      <div className="flex-1 min-h-0 px-6 pb-6">
        <Card className="h-full flex flex-col overflow-hidden">
          <div className="flex-1 min-h-0 overflow-y-auto custom-scrollbar">
            {children}
          </div>
          {footer && (
            <div className="border-t border-[var(--border)] px-4 py-3">
              {footer}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}

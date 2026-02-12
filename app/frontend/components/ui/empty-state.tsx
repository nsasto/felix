import * as React from "react";
import { cn } from "../../lib/utils";

interface EmptyStateProps {
  title: string;
  description?: string;
  icon?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}

const EmptyState: React.FC<EmptyStateProps> = ({
  title,
  description,
  icon,
  action,
  className,
}) => {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center p-4 text-center gap-3",
        className,
      )}
    >
      {icon && (
        <div className="w-12 h-12 rounded-xl flex items-center justify-center bg-[var(--bg-surface)]">
          {icon}
        </div>
      )}
      <div className="space-y-1">
        <p className="text-xs font-bold text-[var(--text-tertiary)]">{title}</p>
        {description && (
          <p className="text-[10px] text-[var(--text-muted)]">{description}</p>
        )}
      </div>
      {action && <div className="pt-1">{action}</div>}
    </div>
  );
};

export { EmptyState };

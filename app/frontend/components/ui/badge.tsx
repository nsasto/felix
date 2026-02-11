import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "../../lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider",
  {
    variants: {
      variant: {
        default:
          "border-[var(--border-muted)] bg-[var(--bg-base)] text-[var(--text-muted)]",
        success:
          "border-[var(--brand-500)]/30 bg-[var(--brand-500)]/10 text-[var(--brand-500)]",
        warning:
          "border-[var(--warning-500)]/30 bg-[var(--warning-500)]/10 text-[var(--warning-500)]",
        destructive:
          "border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

export interface BadgeProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: "default" | "success" | "warning" | "destructive";
}

function Badge({ className, variant, ...props }: BadgeProps) {
  return (
    <div className={cn(badgeVariants({ variant }), className)} {...props} />
  );
}

export { Badge, badgeVariants };

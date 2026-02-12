import React from "react";
import { Toaster as Sonner } from "sonner";
import { useTheme } from "../../hooks/ThemeProvider";

type ToasterProps = React.ComponentProps<typeof Sonner>;

export function Toaster(props: ToasterProps) {
  const { theme } = useTheme();

  return (
    <Sonner
      theme={theme}
      className="toaster group"
      toastOptions={{
        classNames: {
          toast:
            "group toast bg-[var(--bg-surface-100)] text-[var(--text)] border border-[var(--border)] shadow-md",
          description: "text-[var(--text-muted)]",
          actionButton:
            "bg-[var(--brand-500)] text-white hover:bg-[var(--brand-600)]",
          cancelButton:
            "bg-[var(--bg-surface-200)] text-[var(--text)] hover:bg-[var(--bg-surface-300)]",
        },
      }}
      {...props}
    />
  );
}

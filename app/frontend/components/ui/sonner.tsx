import React from "react";
import { Toaster as Sonner } from "sonner";
import { useTheme } from "../../hooks/ThemeProvider";

type ToasterProps = React.ComponentProps<typeof Sonner>;

export function Toaster(props: ToasterProps) {
  const { theme } = useTheme();
  const isTopCenter = (props.position ?? "bottom-right") === "top-center";
  const baseStyle: React.CSSProperties = {
    position: "fixed",
    zIndex: "var(--z-toast, 9999)",
    pointerEvents: "none",
  };
  const placementStyle: React.CSSProperties = isTopCenter
    ? {
        top: "24px",
        left: "50%",
        transform: "translateX(-50%)",
        width: "356px",
        maxWidth: "calc(100vw - 32px)",
      }
    : {};

  return (
    <Sonner
      theme={theme}
      className="toaster group"
      style={{
        ...baseStyle,
        ...placementStyle,
        ...props.style,
      }}
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

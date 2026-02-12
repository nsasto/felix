import React from "react";
import {
  EllipsisVertical as IconEllipsisVertical,
  Trash2 as IconTrash2,
} from "lucide-react";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { cn } from "../lib/utils";

export type RowActionItem = {
  label: string;
  onSelect: () => void;
  variant?: "default" | "destructive";
  icon?: "trash";
};

interface RowActionsMenuProps {
  items: RowActionItem[];
  className?: string;
  align?: "start" | "center" | "end";
  label?: string;
  onOpenChange?: (open: boolean) => void;
}

export default function RowActionsMenu({
  items,
  className,
  align = "end",
  label = "Row actions",
  onOpenChange,
}: RowActionsMenuProps) {
  if (items.length === 0) {
    return null;
  }

  return (
    <DropdownMenu onOpenChange={onOpenChange}>
      <DropdownMenuTrigger asChild>
        <Button
          onClick={(event) => event.stopPropagation()}
          variant="ghost"
          size="icon"
          className={cn(
            "opacity-0 group-hover:opacity-100 data-[state=open]:opacity-100 text-[var(--text-muted)] hover:text-[var(--text)]",
            className,
          )}
          title={label}
        >
          <IconEllipsisVertical className="w-4 h-4" />
          <span className="sr-only">{label}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align={align}>
        {items.map((item) => (
          <DropdownMenuItem
            key={item.label}
            onSelect={(event) => {
              event.preventDefault();
              event.stopPropagation();
              item.onSelect();
            }}
            className={cn(
              item.variant === "destructive" &&
                "text-[var(--destructive-500)] focus:bg-[var(--destructive-500)]/10 focus:text-[var(--destructive-500)]",
            )}
          >
            {item.icon === "trash" && (
              <IconTrash2 className="mr-2 h-4 w-4" />
            )}
            {item.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

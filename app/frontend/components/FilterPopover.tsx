import React from "react";
import { Filter as IconFilter } from "lucide-react";
import { Button } from "./ui/button";
import { Checkbox } from "./ui/checkbox";
import { Popover, PopoverContent, PopoverTrigger } from "./ui/popover";

type FilterOption = {
  label: string;
  value: string;
};

type FilterGroup = {
  key: string;
  label: string;
  options: FilterOption[];
};

interface FilterPopoverProps {
  groups: FilterGroup[];
  value: Record<string, Set<string>>;
  onChange: (next: Record<string, Set<string>>) => void;
  label?: string;
}

export default function FilterPopover({
  groups,
  value,
  onChange,
  label = "Filters",
}: FilterPopoverProps) {
  const handleToggle = (groupKey: string, optionValue: string) => {
    const next = { ...value };
    const current = new Set(next[groupKey] ?? []);
    if (current.has(optionValue)) {
      current.delete(optionValue);
    } else {
      current.add(optionValue);
    }
    next[groupKey] = current;
    onChange(next);
  };

  const selectedCount = Object.values(value).reduce(
    (acc, set) => acc + set.size,
    0,
  );
  const handleClear = () => {
    const next = groups.reduce<Record<string, Set<string>>>((acc, group) => {
      acc[group.key] = new Set();
      return acc;
    }, {});
    onChange(next);
  };

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          size="icon"
          className="h-9 w-9 border-dashed"
          aria-label={label}
        >
          <IconFilter className="h-4 w-4" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-3" align="start">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <span className="text-sm font-medium text-[var(--text)]">
              {label}
            </span>
            {selectedCount > 0 && (
              <span className="text-xs text-[var(--text-muted)]">
                {selectedCount} selected
              </span>
            )}
          </div>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-7 px-2 text-xs"
            onClick={handleClear}
            disabled={selectedCount === 0}
          >
            Clear
          </Button>
        </div>
        <div className="space-y-3">
          {groups.map((group) => (
            <div key={group.key} className="space-y-2">
              <div className="text-xs uppercase tracking-wide text-[var(--text-muted)]">
                {group.label}
              </div>
              <div className="space-y-2">
                {group.options.map((option) => {
                  const checked = value[group.key]?.has(option.value) ?? false;
                  return (
                    <label
                      key={option.value}
                      className="flex items-center gap-2 text-sm text-[var(--text)] cursor-pointer"
                    >
                      <Checkbox
                        checked={checked}
                        onCheckedChange={() =>
                          handleToggle(group.key, option.value)
                        }
                      />
                      <span>{option.label}</span>
                    </label>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </PopoverContent>
    </Popover>
  );
}

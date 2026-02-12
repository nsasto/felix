import React from "react";
import { cn } from "../lib/utils";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "./ui/table";

export type DataTableColumn<T> = {
  key: string;
  header: React.ReactNode;
  cell: (row: T) => React.ReactNode;
  className?: string;
  headerClassName?: string;
};

interface DataTableProps<T> {
  data: T[];
  columns: Array<DataTableColumn<T>>;
  rowKey: (row: T) => string;
  onRowClick?: (row: T) => void;
  rowClassName?: (row: T) => string;
  actions?: (row: T) => React.ReactNode;
  actionsHeader?: React.ReactNode;
  actionsClassName?: string;
}

export default function DataTable<T>({
  data,
  columns,
  rowKey,
  onRowClick,
  rowClassName,
  actions,
  actionsHeader,
  actionsClassName,
}: DataTableProps<T>) {
  return (
    <Table>
      <TableHeader>
        <TableRow className="border-[var(--border)]">
          {columns.map((column) => (
            <TableHead key={column.key} className={column.headerClassName}>
              {column.header}
            </TableHead>
          ))}
          {actions && (
            <TableHead className={cn("w-10 text-right", actionsClassName)}>
              {actionsHeader}
            </TableHead>
          )}
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.map((row) => (
          <TableRow
            key={rowKey(row)}
            className={cn(
              onRowClick && "cursor-pointer",
              rowClassName?.(row),
            )}
            onClick={onRowClick ? () => onRowClick(row) : undefined}
          >
            {columns.map((column) => (
              <TableCell key={column.key} className={column.className}>
                {column.cell(row)}
              </TableCell>
            ))}
            {actions && (
              <TableCell className={cn("text-right", actionsClassName)}>
                {actions(row)}
              </TableCell>
            )}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

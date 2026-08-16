---
name: tanstack-table
description: Set up and use TanStack Table for headless data tables in React, Vue, Svelte, or Solid. Covers column definitions, row models (core, pagination, sorting, filtering, expansion, grouping), controlled state, virtualization, and React Query. Use when building data tables, implementing sorting/filtering/pagination, or when the user mentions TanStack Table, @tanstack/react-table, or headless tables.
---

# TanStack Table

## Quick reference

**Install (pick one):**

```bash
npm install @tanstack/react-table   # React 16.8+
npm install @tanstack/vue-table     # Vue 3
npm install @tanstack/svelte-table # Svelte 3/4
npm install @tanstack/solid-table  # Solid 1
npm install @tanstack/table-core   # Framework-agnostic / custom adapter
```

**Dev + run:** `npm install && npm run dev`

**Create table (React):**

```tsx
import { useReactTable, getCoreRowModel, flexRender } from '@tanstack/react-table'

const table = useReactTable({
  data,
  columns,
  getCoreRowModel: getCoreRowModel(),
})

// Render: thead → table.getHeaderGroups(), tbody → table.getRowModel().rows, flexRender(header/cell/footer, context)
```

**Create table (other frameworks):** Use `useVueTable` / `createSvelteTable` / `createSolidTable` with same options pattern; pass reactive data/getters where needed.

## Table options (concepts)

| Option | Purpose |
|--------|---------|
| `data` | Array of row objects (stable reference). |
| `columns` | Column defs: accessorKey/accessorFn, header, cell, footer, columns (nested groups). |
| `getCoreRowModel()` | Required — turns data into rows. |
| `state` + `onXxxChange` | Controlled state (e.g. pagination, sorting, columnFilters). |
| `initialState` | Uncontrolled default state (e.g. pagination.pageSize, columnVisibility). |

## Row models (add as needed)

| Feature | Row model | Typical state |
|--------|-----------|----------------|
| Pagination | `getPaginationRowModel()` | `pagination`, `onPaginationChange` |
| Sorting | `getSortedRowModel()` | `sorting`, `onSortingChange` |
| Filtering | `getFilteredRowModel()` | `columnFilters` / `globalFilter`, `onColumnFiltersChange` / `onGlobalFilterChange` |
| Expansion | `getExpandedRowModel()` | `expanded`, `onExpandedChange`; set `getSubRows` for nested data |
| Grouping | `getGroupedRowModel()` | `grouping`, `onGroupingChange` |
| Faceting | `getFacetedRowModel()`, `getFacetedUniqueValues()`, `getFacetedMinMaxValues()` | Used with filtering for min/max and unique values |

## Column definitions

- **createColumnHelper&lt;TData&gt;** — type-safe accessors and groups.
- **accessorKey** or **accessorFn** + **id** — data access.
- **header**, **cell**, **footer** — render (string, JSX, or function receiving context).
- Nested **columns** — grouped headers/footers.

Use **flexRender(columnDef.header | cell | footer, context)** to render.

## Rendering pattern

- **Headers:** `table.getHeaderGroups()` → each `headerGroup.headers` → `flexRender(header.column.columnDef.header, header.getContext())`; use `header.colSpan`, `header.isPlaceholder`.
- **Rows:** `table.getRowModel().rows` → each `row.getVisibleCells()` → `flexRender(cell.column.columnDef.cell, cell.getContext())`.
- **Footers:** `table.getFooterGroups()` — same as headers with `.footer`.

Use **getVisibleLeafColumns()** / **getVisibleCells()** when column visibility is toggled.

## Frequent APIs

- **table.getState()** — full state; e.g. `getState().pagination`, `getState().sorting`.
- **table.getColumn(id)** — column by id.
- **Pagination:** `setPageIndex`, `setPageSize`, `getCanPreviousPage`, `getCanNextPage`, `getPageCount`, `firstPage`, `previousPage`, `nextPage`, `lastPage`.
- **Sorting:** `header.column.getToggleSortingHandler()`, `getIsSorted()`.
- **Column visibility:** `getIsAllColumnsVisible()`, `getToggleAllColumnsVisibilityHandler()`, `column.getToggleVisibilityHandler()`.
- **Row selection:** `getSelectedRowModel().rows`, `row.getToggleSelectedHandler()`, `enableRowSelection`.

## Virtualization & infinite scroll

- **Row virtualization:** Use `@tanstack/react-virtual` (or vue-virtual, etc.) with `table.getRowModel().rows`; ref the scroll container, estimate row height, render only virtual items; use `measureElement` for dynamic height.
- **Column virtualization:** Horizontal virtualizer over `table.getVisibleLeafColumns()`; render virtual padding columns for scroll correctness.
- **Infinite scroll:** Combine with `useInfiniteQuery`; flatten pages for table data; when last virtual row is in view, call `fetchNextPage`.

## Server-side

- **manualPagination: true** — pass `rowCount`, drive `pagination` from server.
- **manualSorting: true** — drive `sorting` from server and sort in API.
- **manualFiltering: true** — filter on server; omit `getFilteredRowModel` or use for client-side only.

## Additional resources

- Full API and framework examples: [reference.md](reference.md)

---
name: tanstack-virtual
description: Set up and use TanStack Virtual in React for virtualized lists, grids, and tables. Covers useVirtualizer, useWindowVirtualizer, fixed/variable/dynamic sizes, sticky headers, smooth scroll, infinite scroll, and React Query. Use when optimizing large lists or grids, implementing virtualization in React, or when the user mentions TanStack Virtual, @tanstack/react-virtual, or virtualized lists.
---

# TanStack Virtual (React)

## Quick reference

**Install:** `npm install @tanstack/react-virtual`

**Basic row virtualizer:**

```tsx
import { useVirtualizer } from '@tanstack/react-virtual';

function VirtualList({ count = 10000 }) {
  const parentRef = React.useRef(null);
  const rowVirtualizer = useVirtualizer({
    count,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 35,
    overscan: 5,
  });

  return (
    <div ref={parentRef} style={{ height: '400px', overflow: 'auto' }}>
      <div style={{ height: `${rowVirtualizer.getTotalSize()}px`, position: 'relative' }}>
        {rowVirtualizer.getVirtualItems().map((virtualRow) => (
          <div
            key={virtualRow.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: `${virtualRow.size}px`,
              transform: `translateY(${virtualRow.start}px)`,
            }}
          >
            Row {virtualRow.index}
          </div>
        ))}
      </div>
    </div>
  );
}
```

**Required options:** `count`, `getScrollElement`, `estimateSize`.

**Key API:** `getVirtualItems()`, `getTotalSize()`, `scrollToIndex(index, { align?, behavior? })`, `scrollToOffset(toOffset, options?)`, `measureElement` (ref callback for dynamic sizes), `measure()`.

## Patterns

| Pattern | Hook / option | Notes |
|--------|----------------|--------|
| Fixed row/column size | `estimateSize: () => 35` | Same size for all items. |
| Variable size | `estimateSize: (i) => rows[i]` | Known size per index (e.g. from data). |
| Dynamic size | `ref={virtualizer.measureElement}`, `data-index={virtualRow.index}` | Measure after render; use with `measureElement` option if custom. |
| Horizontal list | `horizontal: true` | Use `translateX(…start)` and width for items. |
| Grid | Two virtualizers (rows + columns) | Nested loops over row virtual items and column virtual items. |
| Window scroll | `useWindowVirtualizer` | Use `scrollMargin: listRef.current?.offsetTop ?? 0` and `transform: translateY(${item.start - virtualizer.options.scrollMargin}px)`. |
| Infinite scroll | `useInfiniteQuery` + virtualizer | Count = `allRows.length + (hasNextPage ? 1 : 0)`; when last visible index ≥ length−1, call `fetchNextPage()`. |
| Smooth scroll | `scrollToFn: (offset, opts, instance) => { … }` | e.g. animate with `requestAnimationFrame` or `elementScroll(offset, opts.behavior, instance)`. |

## VirtualItem

- `key`, `index`, `start`, `end`, `size`, `lane` (for masonry).

## Additional resources

- Full API and examples: [reference.md](reference.md)

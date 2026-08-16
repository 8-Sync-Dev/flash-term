# TanStack Virtual — Reference

## Installation

```bash
npm install @tanstack/react-virtual
```

## React setup

**Entry (createRoot):**

```jsx
const container = document.getElementById('root');
const root = createRoot(container);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

**With React Query:**

```jsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const queryClient = new QueryClient();

ReactDOM.render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </React.StrictMode>,
  document.getElementById('root'),
);
```

---

## Hooks

### useVirtualizer

For a **scrollable DOM element** as the scroll container.

```tsx
function useVirtualizer<TScrollElement, TItemElement = unknown>(
  options: PartialKeys<
    ReactVirtualizerOptions<TScrollElement, TItemElement>,
    'observeElementRect' | 'observeElementOffset' | 'scrollToFn'
  >,
): Virtualizer<TScrollElement, TItemElement>
```

Required: `count`, `getScrollElement`, `estimateSize`.

### useWindowVirtualizer

For **window** as the scroll container. Omit `getScrollElement`; use `scrollMargin` (e.g. offset from top of page to list).

```tsx
const virtualizer = useWindowVirtualizer({
  count: 10000,
  estimateSize: () => 35,
  overscan: 5,
  scrollMargin: listRef.current?.offsetTop ?? 0,
});

// Item positioning:
transform: `translateY(${item.start - virtualizer.options.scrollMargin}px)`
```

---

## Required options

| Option | Type | Description |
|--------|------|--------------|
| `count` | `number` | Total number of items. |
| `getScrollElement` | `() => TScrollElement \| null` | Returns the scrollable element. |
| `estimateSize` | `(index: number) => number` | Estimated size (height for rows, width for columns) for the given index. |

---

## Row virtualization

### Fixed row size

```tsx
const rowVirtualizer = useVirtualizer({
  count: 10000,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 35,
  overscan: 5,
});

// Render:
height: `${rowVirtualizer.getTotalSize()}px`
// Each item:
height: `${virtualRow.size}px`,
transform: `translateY(${virtualRow.start}px)`,
```

### Variable row size

Heights known per index (e.g. from a `rows` array):

```tsx
const rowVirtualizer = useVirtualizer({
  count: rows.length,
  getScrollElement: () => parentRef.current,
  estimateSize: (i) => rows[i],
  overscan: 5,
});

// Item height:
height: `${rows[virtualRow.index]}px`,
transform: `translateY(${virtualRow.start}px)`,
```

### Dynamic row size

Sizes unknown until render; use `measureElement` and often `data-index`:

```tsx
const rowVirtualizer = useVirtualizer({
  count: sentences.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 45,
});

// On each row div:
data-index={virtualRow.index}
ref={rowVirtualizer.measureElement}
// Omit fixed height or use estimate; virtualizer updates size after measure.
```

---

## Column (horizontal) virtualization

Set `horizontal: true` and use width + `translateX`:

```tsx
const columnVirtualizer = useVirtualizer({
  horizontal: true,
  count: columns.length,
  getScrollElement: () => parentRef.current,
  estimateSize: (i) => columns[i] ?? 100,
  overscan: 5,
});

// Container inner width:
width: `${columnVirtualizer.getTotalSize()}px`

// Each column:
width: `${columns[virtualColumn.index]}px`,
transform: `translateX(${virtualColumn.start}px)`,
```

Padding: `paddingStart`, `paddingEnd` add space before/after the virtualized range.

---

## Grid virtualization

Use one virtualizer for rows and one for columns; nest their `getVirtualItems()`.

```tsx
const rowVirtualizer = useVirtualizer({
  count: rows.length,
  getScrollElement: () => parentRef.current,
  estimateSize: (i) => rows[i],
  overscan: 5,
});
const columnVirtualizer = useVirtualizer({
  horizontal: true,
  count: columns.length,
  getScrollElement: () => parentRef.current,
  estimateSize: (i) => columns[i],
  overscan: 5,
});

// Inner container:
height: `${rowVirtualizer.getTotalSize()}px`,
width: `${columnVirtualizer.getTotalSize()}px`,

// Each cell:
rowVirtualizer.getVirtualItems().map((virtualRow) =>
  columnVirtualizer.getVirtualItems().map((virtualColumn) => (
    <div
      key={`${virtualRow.key}-${virtualColumn.key}`}
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width: `${columns[virtualColumn.index]}px`,
        height: `${rows[virtualRow.index]}px`,
        transform: `translateX(${virtualColumn.start}px) translateY(${virtualRow.start}px)`,
      }}
    >
      Cell {virtualRow.index}, {virtualColumn.index}
    </div>
  )),
);
```

For dynamic grid cells, pass `ref={(el) => { rowVirtualizer.measureElement(el); columnVirtualizer.measureElement(el); }}` and set `data-row-index` / `data-column-index` when using `indexAttribute`.

---

## Window virtualizer

Use when the **window** is the scroll container:

```tsx
const listRef = React.useRef<HTMLDivElement>(null);

const virtualizer = useWindowVirtualizer({
  count: 10000,
  estimateSize: () => 35,
  overscan: 5,
  scrollMargin: listRef.current?.offsetTop ?? 0,
});

return (
  <div ref={listRef}>
    <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
      {virtualizer.getVirtualItems().map((item) => (
        <div
          key={item.key}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: '100%',
            height: `${item.size}px`,
            transform: `translateY(${item.start - virtualizer.options.scrollMargin}px)`,
          }}
        >
          Row {item.index}
        </div>
      ))}
    </div>
  </div>
);
```

Measure `scrollMargin` in `useLayoutEffect` if the list position depends on layout.

---

## Sticky headers

Use a custom `rangeExtractor` so sticky indices are always included, and style those items with `position: sticky`:

```tsx
const stickyIndexes = [0, 10, 20]; // header indices
const activeStickyIndexRef = React.useRef(0);

const rowVirtualizer = useVirtualizer({
  count: rows.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 50,
  rangeExtractor: React.useCallback((range) => {
    activeStickyIndexRef.current =
      [...stickyIndexes].reverse().find((i) => range.startIndex >= i) ?? 0;
    const next = new Set([activeStickyIndexRef.current, ...defaultRangeExtractor(range)]);
    return [...next].sort((a, b) => a - b);
  }, [stickyIndexes]),
});

// Per row:
const isSticky = stickyIndexes.includes(virtualRow.index);
const isActiveSticky = activeStickyIndexRef.current === virtualRow.index;
style={{
  ...(isSticky ? { background: '#fff', borderBottom: '1px solid #ddd', zIndex: 1 } : {}),
  ...(isActiveSticky ? { position: 'sticky' } : { position: 'absolute', transform: `translateY(${virtualRow.start}px)` }),
  top: 0,
  left: 0,
  width: '100%',
  height: `${virtualRow.size}px`,
}}
```

---

## Smooth scroll (custom scrollToFn)

Use `scrollToFn` to implement smooth scrolling for `scrollToIndex` / `scrollToOffset`:

```tsx
const rowVirtualizer = useVirtualizer({
  count: 10000,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 35,
  overscan: 5,
  scrollToFn: (offset, { behavior }, instance) => {
    parentRef.current?.scrollTo({ top: offset, behavior: 'smooth' });
  },
});

rowVirtualizer.scrollToIndex(randomIndex, { behavior: 'smooth' });
```

Or animate manually with `requestAnimationFrame` and an easing function, then call `elementScroll(interpolated, canSmooth, instance)` from `@tanstack/react-virtual`.

---

## Infinite scroll (React Query)

Combine `useInfiniteQuery` with a virtualizer; add an extra “loader” row when there is a next page:

```tsx
const {
  data,
  fetchNextPage,
  hasNextPage,
  isFetchingNextPage,
} = useInfiniteQuery({
  queryKey: ['projects'],
  queryFn: (ctx) => fetchServerPage(10, ctx.pageParam),
  getNextPageParam: (last) => last.nextOffset,
  initialPageParam: 0,
});

const allRows = data?.pages.flatMap((d) => d.rows) ?? [];
const parentRef = React.useRef(null);

const rowVirtualizer = useVirtualizer({
  count: hasNextPage ? allRows.length + 1 : allRows.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 100,
  overscan: 5,
});

React.useEffect(() => {
  const items = rowVirtualizer.getVirtualItems();
  const last = items[items.length - 1];
  if (!last) return;
  if (last.index >= allRows.length - 1 && hasNextPage && !isFetchingNextPage) {
    fetchNextPage();
  }
}, [hasNextPage, fetchNextPage, allRows.length, isFetchingNextPage, rowVirtualizer.getVirtualItems()]);
```

Render: if `virtualRow.index > allRows.length - 1`, show “Loading more…” or “Nothing more to load”; otherwise show `allRows[virtualRow.index]`.

---

## Virtualized table (React Table)

Use table rows as virtual items; keep thead fixed and virtualize tbody:

```tsx
const { rows } = table.getRowModel();
const parentRef = React.useRef(null);

const virtualizer = useVirtualizer({
  count: rows.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 34,
  overscan: 20,
});

// tbody: only render virtual rows
{virtualizer.getVirtualItems().map((virtualRow, index) => {
  const row = rows[virtualRow.index];
  return (
    <tr
      key={row.id}
      style={{
        height: `${virtualRow.size}px`,
        transform: `translateY(${virtualRow.start - index * virtualRow.size}px)`,
      }}
    >
      {row.getVisibleCells().map((cell) => (
        <td key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</td>
      ))}
    </tr>
  );
})}
```

For tables, the transform offset is often expressed relative to the row’s logical index (`virtualRow.start - index * virtualRow.size`) because the transform origin is the row’s initial position.

---

## VirtualItem

| Property | Type | Description |
|----------|------|--------------|
| `key` | `string \| number \| bigint` | Stable key (default index; override with `getItemKey`). |
| `index` | `number` | Item index. |
| `start` | `number` | Start offset in px (map to `top`/`left` or `translateY`/`translateX`). |
| `end` | `number` | End offset in px. |
| `size` | `number` | Height or width; may be estimated until measured. |
| `lane` | `number` | Lane index for masonry (default 0). |

---

## Virtualizer API

| Method / property | Description |
|-------------------|-------------|
| `getVirtualItems()` | Returns `VirtualItem[]` for currently visible (and overscan) items. |
| `getVirtualIndexes()` | Returns indexes of virtualized items. |
| `getTotalSize()` | Total size in px of all items. |
| `scrollToIndex(index, { align?, behavior? })` | Scroll so the item at `index` is in view. `align`: 'start' \| 'center' \| 'end' \| 'auto'. `behavior`: 'auto' \| 'smooth'. |
| `scrollToOffset(toOffset, { align?, behavior? })` | Scroll to a pixel offset. |
| `measure()` | Reset stored measurements so elements are re-measured. |
| `measureElement(el)` | Measure one element (use as ref callback; typically with `data-index`). |
| `options` | Read-only current options (e.g. `options.scrollMargin`). |
| `scrollElement` | Current scroll element. |
| `scrollOffset` | Current scroll offset in px. |
| `scrollDirection` | 'forward' \| 'backward' \| null. |
| `isScrolling` | Whether a scroll is in progress. |
| `resizeItem(index, size)` | Manually set item size (avoid using with `measureElement` on same index). |

---

## Optional configuration

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `true` | Set `false` to disable observers and reset state. |
| `overscan` | `1` | Number of items to render outside visible area. |
| `horizontal` | `false` | Horizontal list. |
| `paddingStart` / `paddingEnd` | - | Padding in px at start/end of list. |
| `scrollPaddingStart` / `scrollPaddingEnd` | - | Padding when scrolling to an item. |
| `scrollMargin` | - | Origin for scroll offset (e.g. for window or header). |
| `initialOffset` | - | Initial scroll position (number or function). |
| `getItemKey` | `(i) => i` | Stable key per index. |
| `rangeExtractor` | default | Custom range of indexes to render (e.g. sticky headers). |
| `measureElement` | measures via getBoundingClientRect | Custom measure function. |
| `scrollToFn` | default element scroll | Custom scroll implementation. |
| `gap` | - | Pixel gap between items. |
| `lanes` | - | Number of lanes (masonry). |
| `useFlushSync` | `true` | Use React `flushSync` for scroll updates; set `false` for React 19 or to reduce overhead. |
| `isRtl` | `false` | Invert horizontal scrolling for RTL. |
| `useScrollendEvent` | `false` | Use native scrollend; else debounced fallback. |
| `isScrollingResetDelay` | `150` | Ms after last scroll before `isScrolling` resets. |
| `useAnimationFrameWithResizeObserver` | `false` | Defer ResizeObserver to rAF (can add delay). |
| `shouldAdjustScrollPositionOnItemSizeChange` | - | Callback to control scroll adjustment when item size changes. |
| `observeElementRect` / `observeElementOffset` | - | Custom observers (usually not needed). |

---

## Masonry (lanes)

Use `lanes` so items are placed in columns (vertical) or rows (horizontal). Each `VirtualItem` has a `lane` index; position items with e.g. `left: ${virtualRow.lane * 25}%`, `width: '25%'`, and `transform: translateY(${virtualRow.start}px)`.

---

## React 19 and useFlushSync

If you see warnings about `flushSync` in lifecycle, set `useFlushSync: false`:

```tsx
const virtualizer = useVirtualizer({
  count: 10000,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 50,
  useFlushSync: false,
});
```

Slight delay during scroll is possible; acceptable for many UIs.

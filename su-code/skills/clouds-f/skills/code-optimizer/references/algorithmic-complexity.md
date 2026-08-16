# Algorithmic Complexity

## Grep/Glob Patterns to Detect

### O(n^2) and Worse Patterns
```
# Nested loops over same/related collections
for.*in.*\n.*for.*in         (nested for loops)
\.forEach\(.*\.forEach\(      (nested forEach)
\.map\(.*\.map\(              (nested map)
\.filter\(.*\.includes\(      (filter+includes = O(n*m))
\.find\(.*inside.*\.map\(     (find inside map)
\.indexOf\(.*inside.*for      (indexOf in loop)
\.includes\(.*inside.*for     (includes in loop)
# Array as lookup table
array\.find\(.*===            (use Map/Set instead)
array\.some\(.*===            (use Set.has instead)
list\.index\(                 (Python: use dict instead)
if.*in\s+list                 (Python: O(n) lookup in list)
```

### Unnecessary Iterations
```
\.filter\(.*\.length          (filter just to count)
\.filter\(.*\[0\]             (filter just to get first - use find)
\.map\(.*\.filter\(           (map then filter - combine or reverse order)
\.filter\(.*\.map\(.*\.filter (multiple passes when one suffices)
\.sort\(\).*\[0\]             (sort to get min/max - use Math.min/max or reduce)
\.sort\(\).*\.slice\(0        (sort to get top-k - use partial sort/heap)
sorted\(.*\)\[0\]             (Python: use min() instead)
sorted\(.*\)\[-1\]            (Python: use max() instead)
\.reverse\(\).*\.forEach      (reverse just to iterate backwards)
Object\.keys\(.*\.map\(.*Object\.values  (iterating keys then accessing values)
```

### Redundant Computation
```
# Same computation in loop
for.*\n.*Math\.              (math operations that could be hoisted)
for.*\n.*\.length            (accessing .length repeatedly - may be fine, check)
for.*\n.*document\.querySelector  (DOM queries in loops)
for.*\n.*JSON\.parse         (parsing same JSON repeatedly)
for.*\n.*new RegExp\(        (creating regex in loop)
for.*\n.*new Date\(          (creating Date objects in loop for same date)
```

### Inefficient Data Structure Choice
```
# Using arrays where Set/Map would be better
\.push\(.*\.includes\(       (array as unique set)
\.filter\(.*\.indexOf\(       (dedup with filter+indexOf)
\[\].*\.find\(               (array for lookups)
# Using objects where Map would be better
\{\}.*\[.*\]\s*=             (frequent dynamic key insertion)
delete.*\[                   (frequent key deletion from object)
```

## Improvement Strategies

1. **Nested loops**: Pre-build lookup Map/Set, use hash-based approaches
2. **Filter+includes**: Convert one collection to Set for O(1) lookups
3. **Sort for min/max**: Use Math.min/max, reduce, or heap for top-k
4. **Multiple passes**: Combine into single reduce/loop
5. **Redundant computation**: Hoist invariants out of loops, memoize
6. **Array as lookup**: Use Map for key-value, Set for existence checks
7. **String matching in loops**: Pre-compile regex, use Map for exact matches

## Frontend-Native Patterns

### Memoization without break-even (useMemo/useCallback/React.memo on O(1) derivations)
```
\.useMemo\(\(\).*=>.*(a\s*\+|return\s+\w+\s*\))  (memoizing a single op = slower than recompute)
useCallback\(\(\).*=>.*\(.*\)                      (callback wrapping a cheap call)
React\.memo\(                                     (check: does the child actually avoid work?)
```

### Deep operations in render or effect deps (O(n) per render, often costlier than the guarded work)
```
_\.isEqual\(|lodash.*isEqual                       (deep equality compare in deps)
structuredClone\(                                  (O(n) deep clone in hot path)
JSON\.parse\(JSON\.stringify                       (poor-man deep clone)
cloneDeep|deepmerge                                (deep copy libs in render/effect)
```

### Inline derivation chain in JSX over large arrays
```
return.*\.filter\(.*\.map\(.*\.sort\(              (3-pass derivation in render body)
\.map\(.*\.filter\(.*\.map\(                       (multi-pass when one reduce suffices)
\{.*\.sort\(                                       (.sort() directly in JSX)
```

### Context value identity churn (forces O(consumers) re-render)
```
Context\.Provider.*value=\{\{                      (object literal value = new identity each render)
Context\.Provider.*value=\[                        (array literal value)
useContext.*useState                               (context over frequently-changing state)
```

### Per-item heavy work in list render
```
\.map\(.*=>.*moment\(                              (date lib formatting per row)
\.map\(.*=>.*new Intl                              (intl formatting per row)
\.map\(.*=>.*\.toLocaleString                      (per-row locale formatting)
```

## Frontend Improvement Strategies

1. **Memoize only when derivation > compare cost**: `useMemo`/`React.memo` for `> O(1)` AND changing deps. Memoizing `a + b` is slower than recompute.
2. **Replace deep ops in deps**: drop `_.isEqual` from `useEffect` deps; derive a primitive key instead (id, hash, version counter).
3. **Hoist render derivation**: `.filter().map().sort()` inline in JSX → move to `useMemo` (deps-stable) or selector (reselect/`useSyncExternalStore`).
4. **Stabilize context value**: hoist object/array value out of render, or split context by update frequency.
5. **Virtualize lists**: `> 200` visible rows or `> 1k` total → `tanstack-virtual`. Below: plain map wins.
6. **Off-main-thread for `n > 5k`**: move heavy derivation/sort/filter to Web Worker.

# Algorithm & Data-Structure Implementation Style

How to write algorithms and data structures in Rust so they read as idiomatic to a senior reviewer: generic bounds that say exactly what they need, slice-first APIs, allocation discipline, and ownership models that fit Rust's borrow checker instead of fighting it. Distilled from [TheAlgorithms/Rust](https://github.com/TheAlgorithms/Rust) — conventions, not copied code — cross-checked against the [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/), std docs, and the [Rust Performance Book](https://nnethercote.github.io/perf-book/). Baseline: Rust 1.96, edition 2024. This file is judgment; for basic idioms/TDD see the `rust-patterns` and `rust-testing` skills.

The through-line: **correctness and idiom over cleverness**, and — the part most teaching repos get wrong — **std usually already did it better**. Learn the shape from a hand-rolled implementation; ship the standard library.

## Generic bounds: ask for the least you need

The single most common signature in an algorithm crate is a comparison-driven function. The bound you pick is a contract, and picking it too loose or too tight are both real defects.

`Ord` vs `PartialOrd`. `Ord` is a *total* order: every pair of values compares to exactly one of `Less`/`Equal`/`Greater`. `PartialOrd` allows incomparable pairs (`partial_cmp` returns `None`) — the canonical case is floats, where `NaN` is unordered against everything, so `f64: PartialOrd` but `f64: !Ord`. A correct sort or binary search needs a total order to be *meaningful*: if you bound on `PartialOrd` and call `a < b`, comparisons against `NaN` silently return `false`, and your "sorted" array is quietly wrong with no panic. TheAlgorithms repo's quick-sort partition is bounded `T: PartialOrd` and its driver `T: Ord` — a real inconsistency that lets you *call* partition on `Vec<f64>` and get garbage. **Bound sorting/searching on `Ord`.** The mechanism: `Ord` guarantees the trichotomy your loop invariants assume; giving up float support is the price, and it is the right price because sorting floats *requires* a decision about `NaN` that the caller must make explicitly (`total_cmp`, or a `NotNan` newtype). Deviate only when the algorithm genuinely tolerates a partial order (e.g. topological layering), and then document it.

```rust
/// In-place insertion sort. O(n^2) time, O(1) extra space, stable.
/// `Ord` (not `PartialOrd`) so the total-order invariant actually holds —
/// this is what makes the result well-defined for every element type.
pub fn insertion_sort<T: Ord>(arr: &mut [T]) {
    for i in 1..arr.len() {
        let mut j = i;
        while j > 0 && arr[j - 1] > arr[j] {
            arr.swap(j - 1, j);
            j -= 1;
        }
    }
}
```

Prefer `cmp` + `match Ordering` over chained `<`/`==`. The repo's binary search does `match item.cmp(&arr[mid]) { Less => ..., Greater => ..., Equal => ... }`. This is not stylistic: it computes the comparison *once* (relevant when `T: Ord` is expensive, e.g. `String`), and `match` on the three-variant `Ordering` is exhaustively checked, so you cannot forget the `Equal` branch. Two `<` comparisons is two calls and an implicit fourth "impossible" state.

`Copy` vs `Clone` vs by-value. Reach for `T: Copy` *only* when the algorithm needs to duplicate elements cheaply and you want to forbid expensive types — it is a performance assertion baked into the API. Most in-place algorithms need neither: `arr.swap(i, j)` and `std::mem::swap` move without copying and work for any `T`. Bounding a sort on `T: Ord + Copy` (a frequent beginner tell) needlessly excludes `String`, `Vec`, and every owning type. Add `Copy` when you genuinely read the same element twice by value; otherwise leave it off and let callers sort whatever they own.

Bound at the function, not the struct, when you can. Putting `T: Ord` on `impl<T: Ord> BinarySearchTree<T>` forces the bound on construction. Putting it on individual methods lets you build a `Vec<T>`-backed container of non-`Ord` types and only require `Ord` for the operations that compare. The repo puts `Ord` on the whole BST `impl` block, which is defensible for a type whose *entire purpose* is ordering — but for a general container, bound the methods. The API Guideline C-STRUCT-BOUNDS ("data structures do not duplicate derived trait bounds") says the same thing: declare a bound where it is used, not on the type definition.

## Slice-first APIs: `&[T]` / `&mut [T]`, never `&Vec<T>`

Every algorithm in the repo takes `&mut [T]` or `&[T]`, and this is the strongest single convention to copy. A `&[T]` is a fat pointer (ptr + len); it accepts a `Vec<T>`, a `[T; N]` array, a sub-range `&v[2..8]`, a boxed slice, or the backing store of a `VecDeque` after `make_contiguous`. `&Vec<T>` accepts only a `Vec` and forces a heap type on the caller for no gain — you cannot even call it on a stack array. The mechanism is deref coercion: `&Vec<T>` coerces to `&[T]` automatically, so accepting the slice costs the caller nothing and buys you every contiguous source. **Accept the widest input, return the most specific output** (API Guideline C-GENERIC): take `&[T]`, and if you must allocate a result, return `Vec<T>`.

Never take `&mut Vec<T>` unless you actually change the *length* (push/pop/truncate). Mutating elements or reordering is `&mut [T]` work. Taking `&mut Vec<T>` to sort is an API leak: it advertises "I might resize this" when you won't, and blocks callers holding an array or slice.

The one real exception: algorithms that grow the collection — a DP table you build up, a graph you add nodes to — legitimately own or borrow a `Vec`. There the length change is the point.

## In-place vs allocating: make it the caller's decision

The repo sorts in place (`&mut [T]`, `arr.swap`) and that is correct: an in-place API can always be wrapped to allocate (`let mut v = src.to_vec(); sort(&mut v);`), but an allocating API can never be made in-place. Give the caller the choice by taking `&mut [T]`; if you additionally want an owned-return convenience, layer it *on top* rather than baking `.clone()` into the core.

Watch the hidden allocation. `arr.iter().cloned().collect::<Vec<_>>()` inside a hot function, `format!` in a loop, `s.chars().collect::<Vec<char>>()` per call — each is a heap allocation the type system won't flag. The LCS implementation collects both inputs to `Vec<char>` *once* up front (necessary — `str` isn't randomly indexable by `char`, only by byte, so you cannot index UTF-8 in O(1) without this), then indexes the vecs. That is the right shape: pay the unavoidable allocation once, outside the double loop, not per comparison. When you see repeated allocation in an inner loop, hoist it or switch to indices/iterators.

## Iterators vs index loops: correctness first, then let LLVM decide

Iterators (`for x in &arr`, `arr.iter().enumerate()`, `windows`, `chunks`, `zip`) eliminate the class of off-by-one and out-of-bounds bugs that raw index arithmetic invites, and they carry length information the optimizer uses to *elide bounds checks* — an indexed `for i in 0..n { arr[i] }` may keep a check per access that `for x in arr` does not. So the default is iterators, for safety and often for speed simultaneously.

Index loops earn their place when the access pattern is not a clean forward walk: binary search jumps to `mid`; a DP table reads `table[i-1][j-1]`; an in-place partition walks two cursors toward each other. Forcing those into iterator adapters produces worse code than the honest `while`. The repo gets this balance right — iterators for population passes, indices for the genuinely random-access core. Judgment rule: if you are computing indices to feed *back* into the same slice at non-sequential positions, index directly; otherwise iterate.

One subtlety worth internalizing: `mid = lo + (hi - lo) / 2`, not `(lo + hi) / 2`. In Rust the `(lo + hi) / 2` form is actually safe for slice indices — a single allocation can't exceed `isize::MAX` bytes, so for any non-ZST element `len()` is at most `isize::MAX` and `lo + hi <= usize::MAX - 1` can't overflow. The subtraction form is still the right habit: it matches std, and it survives porting to languages or index types without that bound (the classic Java/C `int`-index overflow bug) or when `lo`/`hi` aren't derived from a slice length. Simpler still, reach for `usize::midpoint(lo, hi)` (stable since 1.85), which encodes the intent directly. The repo uses the safe form.

```rust
use std::cmp::Ordering;

/// Binary search over an ascending-sorted slice. O(log n).
/// Returns the index of `needle`, or `None`. Overflow-safe midpoint.
pub fn binary_search<T: Ord>(needle: &T, haystack: &[T]) -> Option<usize> {
    let (mut lo, mut hi) = (0, haystack.len());
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        match needle.cmp(&haystack[mid]) {
            Ordering::Less => hi = mid,
            Ordering::Greater => lo = mid + 1,
            Ordering::Equal => return Some(mid),
        }
    }
    None
}
```

## Data structures: the ownership question comes first

Rust makes you answer "who owns this node, and for how long" *before* you can compile a data structure. That question is the whole difficulty, and the answer determines which of four models you use. This is where teaching repos and production code diverge most.

### BST: `Option<Box<Node>>` (default) vs arena `Vec<Node>`

The repo's BST is the textbook Rust shape: each node owns its children through `Option<Box<Node>>`, `None` is the empty subtree, and every operation recurses. It is clean, it drops correctly for free, and for a *tree* (single owner per node, no back-edges) it is genuinely idiomatic. Use it when: nodes have exactly one parent, you don't need to point *upward* or hold external references into the tree, and depth stays bounded (recursion means a pathologically unbalanced tree can stack-overflow — a real limit the repo doesn't guard).

```rust
use std::cmp::Ordering;

/// BST via single-owner `Option<Box<Node>>`. Drops for free; no cycles possible.
pub struct Bst<T: Ord> { root: Link<T> }
type Link<T> = Option<Box<Node<T>>>;
struct Node<T: Ord> { value: T, left: Link<T>, right: Link<T> }

impl<T: Ord> Bst<T> {
    pub fn new() -> Self { Bst { root: None } }

    pub fn insert(&mut self, value: T) {
        // Iterative descent over &mut Link avoids recursion depth limits.
        let mut link = &mut self.root;
        while let Some(node) = link {
            match value.cmp(&node.value) {
                Ordering::Less => link = &mut node.left,
                Ordering::Greater => link = &mut node.right,
                Ordering::Equal => return,
            }
        }
        *link = Some(Box::new(Node { value, left: None, right: None }));
    }

    pub fn contains(&self, value: &T) -> bool {
        let mut cur = &self.root;
        while let Some(node) = cur {
            match value.cmp(&node.value) {
                Ordering::Less => cur = &node.left,
                Ordering::Greater => cur = &node.right,
                Ordering::Equal => return true,
            }
        }
        false
    }
}
```

Note the iterative `insert` walking `&mut Link` — this is the senior refinement over the repo's recursion: same logic, no stack-depth ceiling, and the borrow checker is satisfied because at each step exactly one mutable path exists. (Recursive `Drop` on `Option<Box>` can *also* overflow on a degenerate tree; a production tree keeps itself balanced — AVL/red-black — precisely to bound depth.)

Switch to an **arena** — nodes in a `Vec<Node>`, children stored as `Option<usize>` indices instead of `Box` — when the pointer model stops fitting: you need parent pointers, sibling links, or any structure where a node is referenced from more than one place. In safe Rust you *cannot* have two `&mut` owners of a node, and `Option<Box>` gives each node exactly one owner. The arena sidesteps this entirely: ownership lives in the `Vec`, "references" are `usize` indices, and multiple indices pointing at the same node are just plain `Copy` integers with no borrow implications.

```rust
use std::cmp::Ordering;

/// Arena BST: all nodes owned by `nodes`, links are indices.
/// Enables parent/cross pointers, is cache-friendly, and needs no Box/unsafe.
pub struct ArenaBst<T: Ord> {
    nodes: Vec<ArenaNode<T>>,
    root: Option<usize>,
}
struct ArenaNode<T: Ord> { value: T, left: Option<usize>, right: Option<usize> }

impl<T: Ord> ArenaBst<T> {
    pub fn new() -> Self { ArenaBst { nodes: Vec::new(), root: None } }

    pub fn insert(&mut self, value: T) {
        let mut cur = self.root;
        let mut parent: Option<(usize, bool)> = None; // (index, went_left)
        while let Some(i) = cur {
            match value.cmp(&self.nodes[i].value) {
                Ordering::Less => { parent = Some((i, true)); cur = self.nodes[i].left; }
                Ordering::Greater => { parent = Some((i, false)); cur = self.nodes[i].right; }
                Ordering::Equal => return,
            }
        }
        let idx = self.nodes.len();
        self.nodes.push(ArenaNode { value, left: None, right: None });
        match parent {
            None => self.root = Some(idx),
            Some((p, true)) => self.nodes[p].left = Some(idx),
            Some((p, false)) => self.nodes[p].right = Some(idx),
        }
    }
}
```

Why the arena is *more* idiomatic than a pointer graph in Rust, not a workaround: it makes ownership trivially single (the `Vec`), it is cache-friendly (nodes are contiguous), it serializes and clones trivially (no pointer fixup), and it avoids `unsafe` and reference-counting overhead. The trade-offs are real and you must state them: indices are not type-checked against *which* arena they came from (a stale index after you support deletion is a logic bug, not a memory-safety bug — the `Vec` bounds-check still saves you from UB), and freeing a single node means either tombstoning the slot or a free-list, because `Vec` can't leave holes. For anything cyclic or multiply-referenced, the arena is the default professional choice; this is the model `petgraph` and most Rust ECS/compiler code use.

### The last resort: `Rc<RefCell<T>>` and `unsafe`

`Rc<RefCell<Node>>` gives shared ownership with interior mutability and *runtime*-checked borrows. It is the tool when you truly need multiple owners with mutation and cannot restructure to an arena — but it costs an atomic-free refcount per clone, a borrow-flag check on every access (which *panics* at runtime if you double-borrow, converting a compile error into a crash), and it leaks memory on cycles unless you break them with `Weak`. Treat it as a smell in algorithmic code: reach for an arena first. `Arc<Mutex<T>>` is the same story across threads with real locking cost — almost never what a single-threaded algorithm wants.

The repo's doubly-linked list goes all the way to `unsafe` with `NonNull<Node<T>>`, `Box::into_raw`/`from_raw`, `PhantomData<Box<Node<T>>>`, and a hand-written `Drop`. This is honest about a real fact: **a correct, efficient doubly-linked list cannot be written in safe Rust** — every node needs a mutable back-pointer, which is aliasing safe Rust forbids. But the lesson for a senior engineer is the *opposite* of "learn to write this": a doubly-linked list is almost never the right structure. You want `Vec` (random access, cache locality), `VecDeque` (ends), or `BTreeMap` (ordered) 99% of the time. If you think you need a linked list, you usually need an arena with `next`/`prev` indices, which is safe. Writing the `unsafe` version means owning `PhantomData` for drop-check correctness, a `Drop` impl that doesn't leak, and Stacked-Borrows-clean pointer usage — a large correctness surface for a structure you shouldn't be using. (See the `unsafe-rust` reference for the actual rules if you must.)

### Graphs: index arenas, and know when to stop hand-rolling

The repo models a graph as `HashMap<String, Vec<(String, i32)>>` behind a `Graph` trait. It is readable and works, but a senior review flags it: `String` node keys mean every traversal hashes and every edge stores a heap-allocated owned string twice; a hot algorithm re-hashes the same names millions of times. The idiomatic performant model is an **index-based adjacency list** — nodes are `0..n`, adjacency is `Vec<Vec<(usize, Weight)>>` — which is what makes graph algorithms fast: neighbor lookup is a pointer offset, not a hash, and node identity is a `Copy` `usize`.

```rust
/// Index-based directed weighted graph: the idiomatic performant model.
/// Node ids are indices into `adjacency`; edges are (neighbor, weight).
pub struct Graph {
    adjacency: Vec<Vec<(usize, i64)>>,
}

impl Graph {
    pub fn with_nodes(n: usize) -> Self {
        Graph { adjacency: vec![Vec::new(); n] }
    }
    pub fn add_node(&mut self) -> usize {
        self.adjacency.push(Vec::new());
        self.adjacency.len() - 1
    }
    pub fn add_edge(&mut self, from: usize, to: usize, weight: i64) {
        self.adjacency[from].push((to, weight));
    }
    pub fn neighbors(&self, u: usize) -> &[(usize, i64)] {
        &self.adjacency[u]
    }
}
```

Keep a `HashMap<Name, usize>` on the *side* only for the input-parsing boundary, mapping external labels to indices once; the algorithm itself never touches strings. When the graph is more than a teaching exercise, reach for [`petgraph`](https://docs.rs/petgraph) — it gives you `Graph`/`StableGraph`, generic node/edge weights, and correct, tested Dijkstra/BFS/DFS/SCC/topo-sort. Hand-rolling those in production is re-implementing a mature crate; do it to *learn*, depend on petgraph to *ship*.

## Priority queues and ordering: use `BinaryHeap`, mind the contract

Don't hand-roll a heap. `std::collections::BinaryHeap` is a tested binary max-heap. For a min-heap (Dijkstra, Prim), wrap entries in `std::cmp::Reverse` rather than negating keys — negation breaks on unsigned types and on `T::MIN`, `Reverse` never does.

```rust
use std::collections::BinaryHeap;
use std::cmp::Reverse;

/// Dijkstra on an index-based graph. O((V + E) log V) with a binary heap.
/// `Reverse` turns the max-heap into a min-heap correctly for all integer keys.
pub fn dijkstra(adjacency: &[Vec<(usize, u64)>], source: usize) -> Vec<u64> {
    let mut dist = vec![u64::MAX; adjacency.len()];
    let mut heap: BinaryHeap<Reverse<(u64, usize)>> = BinaryHeap::new();
    dist[source] = 0;
    heap.push(Reverse((0, source)));
    while let Some(Reverse((d, u))) = heap.pop() {
        if d > dist[u] {
            continue; // stale entry: std BinaryHeap has no decrease-key, so we
                      // push duplicates and skip outdated pops. Idiomatic and correct.
        }
        for &(v, w) in &adjacency[u] {
            let nd = d + w;
            if nd < dist[v] {
                dist[v] = nd;
                heap.push(Reverse((nd, v)));
            }
        }
    }
    dist
}
```

That "push duplicate, skip stale" pattern is the idiomatic Rust workaround for `BinaryHeap` lacking decrease-key: it costs O(E) extra heap entries but keeps the code simple and correct, and matches how the standard-library docs demonstrate Dijkstra. If you profile and the extra entries hurt, a `BTreeSet<(dist, node)>` with explicit removal gives true decrease-key.

Custom ordering has a contract that is easy to violate: **`Ord` must be consistent with `Eq`** — `a == b` if and only if `a.cmp(&b) == Ordering::Equal`. If you hand-write `Ord` to compare only one field, you must make `Eq` ignore the other fields too, or `BinaryHeap`/`BTreeMap` invariants silently corrupt. Deriving `PartialEq` (all fields) alongside a manual `Ord` (one field) is a common, compiling, *wrong* combination.

```rust
use std::cmp::Ordering;

/// A total order that intentionally ignores `payload`. Because Ord must agree
/// with Eq, `Eq` ignores payload too — otherwise BTreeMap/BinaryHeap break.
pub struct Task { priority: u32, payload: String }

impl PartialEq for Task {
    fn eq(&self, other: &Self) -> bool { self.priority == other.priority }
}
impl Eq for Task {}
impl Ord for Task {
    fn cmp(&self, other: &Self) -> Ordering { self.priority.cmp(&other.priority) }
}
impl PartialOrd for Task {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) }
}
```

When you only need an ephemeral ordering, skip the trait impls entirely: `v.sort_unstable_by_key(|t| t.priority)` or `heap` of tuples `(priority, payload)` expresses the same thing without a contract to maintain.

## std-first: what to reach for before writing anything

The most senior deviation from any algorithms repo is to *not write the algorithm*. Sorting, searching, and heaps are solved in std at a quality you will not match:

| You want | Write this, not a hand-rolled version | Why |
| --- | --- | --- |
| Sort | `sort_unstable` / `sort_unstable_by_key` | pattern-defeating quicksort, no alloc; `sort` (stable) allocs O(n) |
| Sort by cheap key | `sort_by_key`; if key is costly, `sort_by_cached_key` | avoids recomputing the key per comparison |
| Find in sorted slice | `binary_search` / `binary_search_by` / `partition_point` | correct, overflow-safe, returns `Result<usize, usize>` (insertion point on miss) |
| Min/max | `Iterator::min`/`max`/`min_by_key` | one pass, no alloc |
| Priority queue | `BinaryHeap` (+ `Reverse` for min) | tested, cache-aware |
| Ordered map/set | `BTreeMap` / `BTreeSet` | balanced tree, range queries |
| Graph algorithms | the `petgraph` crate | correct Dijkstra/SCC/topo/BFS/DFS |
| Dedup adjacent | `Vec::dedup` / `dedup_by_key` | in place |

`partition_point` deserves a call-out: it is the general "find the boundary in a sorted-by-predicate slice" primitive and is often cleaner than `binary_search` when you want a lower/upper bound rather than an exact hit.

```rust
/// Lower bound: first index whose element is >= needle. std, no hand-rolling.
pub fn lower_bound<T: Ord>(needle: &T, haystack: &[T]) -> usize {
    haystack.partition_point(|x| x < needle)
}
```

Implement an algorithm by hand only to *learn* it, to satisfy a constraint std can't (a custom allocator, `no_std` without `alloc`, an exotic invariant), or when profiling proves the std path is the bottleneck and a specialized version wins. Absent one of those, importing std is the professional answer, and a reviewer will ask why you didn't.

## Documentation and complexity: state the contract, prove the shape

The repo's best files lead with a `//!` module comment explaining what the algorithm does and its non-obvious properties (the LCS file documents that the result is *not symmetric* in its inputs — the kind of caveat that saves a debugging session), and put `///` on public functions describing parameters, return, and the meaning of `None`/`Err`. Copy this. Beyond restating the signature, a good doc comment records:

- **Complexity** — time and *space* (extra allocation), e.g. `/// O(n log n) time, O(1) extra space`. Space matters as much as time in Rust because it maps to allocation. State it in the doc line; it is a contract callers plan around.
- **Invariants and preconditions** — "slice must be sorted ascending", "panics if the graph has a negative-weight cycle". If a precondition isn't checked, say so; an unchecked "must be sorted" that silently returns wrong results is worse than a panic.
- **Non-obvious behavior** — tie-breaking, stability, asymmetry, what an empty input returns.

Use `# Panics` / `# Errors` sections (API Guideline C-FAILURE) so the failure mode is discoverable. If it returns `Result`, the error type should be a named struct (the repo's `NodeNotInGraph` implementing `Display`), not a bare `String` — callers can match on it.

## Test co-location and conventions

Rust's convention, which the repo follows uniformly, is unit tests in the same file under `#[cfg(test)] mod tests { use super::*; ... }`. `#[cfg(test)]` means the module compiles only under `cargo test`, so it adds nothing to release binaries; `use super::*` gives tests access to *private* items, which is the point of co-location — you test internals here and reserve `tests/` (integration) for the public API only. Keep this default.

Patterns worth adopting from the repo:

- **Property-style assertions over hand-picked outputs.** The sort tests assert `is_sorted(&res) && have_same_elements(&res, &cloned)` — output is ordered *and* a permutation of the input — rather than comparing to one expected vector. This catches a sort that drops or duplicates elements, which an equality check against a fixed answer can miss. Prefer invariant checks (sorted, same multiset, length preserved) for algorithms.
- **Exhaustive edge cases as first-class tests**: empty, single element, already-sorted, reverse-sorted, all-equal, duplicates. These are where algorithms break; name them explicitly.
- **Table-driven tests via a small `macro_rules!`** when you have many `(input, expected)` triples (the binary-search and LCS files do this). It keeps dozens of cases readable. Don't reach for the macro until repetition justifies it.
- **`#[should_panic(expected = "...")]`** to pin the *message* of an intended panic, so a different panic doesn't pass silently.
- For anything with a large input space, property testing with `proptest` or `quickcheck` (generate random inputs, assert the invariant) finds cases you won't enumerate — the natural next step beyond the repo's fixed cases. See the `rust-testing` skill.

Avoid the repo's habit of timing/benchmark logic inside `#[test]` functions (`log_timed`, 300k-element runs): tests should be fast and deterministic assertions of correctness. Performance belongs in `#[bench]` (nightly) or, stably, in a `criterion` benchmark under `benches/`.

## Decision summary

| Situation | Idiomatic choice | When to deviate |
| --- | --- | --- |
| Comparison-based algorithm bound | `T: Ord` | `PartialOrd` only if a partial order is genuinely correct |
| Comparing values | `match a.cmp(b)` on `Ordering` | direct `<` only for a single throwaway comparison |
| Function input over a sequence | `&[T]` / `&mut [T]` | `&mut Vec<T>` only when you change its length |
| Transform | in-place `&mut [T]` | allocate-and-return only as a convenience wrapper |
| Access pattern | iterators | index loops for random/2D/two-cursor access |
| Tree (single owner, no back-edge) | `Option<Box<Node>>`, iterative descent | — |
| Parent pointers / cycles / graph | arena `Vec<Node>` + `usize` indices | `Rc<RefCell>` only if you can't restructure |
| Doubly-linked list | don't — use `Vec`/`VecDeque`, or arena indices | hand-rolled `unsafe` almost never justified |
| Shared mutable ownership | arena first | `Rc<RefCell>`/`Arc<Mutex>` as a last resort, mind cycles → `Weak` |
| Sort / search / heap / graph in production | std (`sort_unstable`, `binary_search`, `BinaryHeap`) / `petgraph` | hand-roll only to learn or when profiled |
| Min-heap from `BinaryHeap` | wrap in `Reverse` | negate keys never (breaks on unsigned/MIN) |
| Custom `Ord` | keep consistent with `Eq` | prefer `sort_by_key` / tuple keys to avoid the contract |

The repo is an excellent map of *how the algorithms are shaped* in Rust; a senior engineer reads it for the shape and then, in production, deletes most of it in favor of std and mature crates — keeping only the hand-rolled version when there is a concrete reason the standard answer doesn't fit.

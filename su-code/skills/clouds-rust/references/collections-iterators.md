# Collections, Iterators, Closures & Smart Pointers

Judgment for choosing containers, structuring iterator pipelines, capturing with closures, and reaching for heap/shared/interior-mutable indirection — the decisions, not the API surface. Baseline: Rust 1.96, edition 2024. Cross-references `concurrency.md` for lock semantics under contention and `performance.md` for allocation profiling.

## Standard collections: choosing the container

The container is a data-structure decision, not a style one. Pick it from your *dominant access pattern* and *size trajectory*, and be ready to defend it in review with an asymptotic and a cache argument.

| Need | Reach for | Why |
| --- | --- | --- |
| Grow-at-end sequence, index/scan | `Vec<T>` | Contiguous, cache-friendly, amortized O(1) push |
| Push/pop at *both* ends (queue, ring) | `VecDeque<T>` | Growable ring buffer; O(1) both ends |
| Key→value, no ordering needed | `HashMap<K,V>` | O(1) average lookup |
| Key→value, need sorted iteration/range | `BTreeMap<K,V>` | O(log n), ordered, supports `.range()` |
| Membership test | `HashSet` / `BTreeSet` | Same trade-off as the maps |
| Repeatedly extract min/max | `BinaryHeap<T>` | O(log n) push/pop of the extremum |
| A "list" | almost always `Vec` | see below |

### Vec is the default, and usually the right one

`Vec<T>` stores elements contiguously on the heap. That contiguity is the whole point: linear scans, `iter()`, and index access hit cache lines predictably, which on modern hardware dominates the Big-O for realistic `n`. **Why it's the default:** most "collection" code is build-then-iterate, and `Vec` is optimal for exactly that. **Trade-off:** insertion/removal in the middle is O(n) (elements shift), and a growth reallocation moves every element. **When to deviate:** you provably need front operations (→ `VecDeque`), ordered keys (→ `BTreeMap`), or membership semantics (→ a set). "I might insert in the middle" is not a reason; measure first — a `Vec` with `swap_remove` (O(1), unordered) or a sorted `Vec` + binary search often beats a fancier structure because of cache behaviour.

### VecDeque: a queue or ring buffer, nothing more

`VecDeque<T>` is a growable ring buffer: `push_back`/`pop_front` (and their mirrors) are O(1). Use it when the access pattern is genuinely double-ended — a work queue, a sliding window, BFS frontier.

```rust
/// Sliding window sums — VecDeque keeps the window O(1) at both ends.
fn sliding_window(data: &[i32], k: usize) -> Vec<i32> {
    let mut window: VecDeque<i32> = VecDeque::with_capacity(k);
    let mut out = Vec::new();
    for &x in data {
        window.push_back(x);
        if window.len() > k { window.pop_front(); }
        if window.len() == k { out.push(window.iter().sum()); }
    }
    out
}
```

**Trade-off vs `Vec`:** elements are not guaranteed contiguous (the ring wraps), so there's no single `&[T]` view without `make_contiguous`, and indexing math is slightly heavier. **When to deviate:** if you only ever push/pop one end, a `Vec` used as a stack is simpler and faster.

### LinkedList: essentially never

`std::collections::LinkedList` exists, but reaching for it is almost always wrong. **Mechanism:** a doubly-linked list of separately-allocated nodes. **Why it loses:** every node is a pointer-chase to a random heap address — catastrophic for cache — and it offers no O(1) *indexed* access, so it beats `Vec`/`VecDeque` at essentially nothing you'd hit in practice. The std docs themselves recommend `Vec`/`VecDeque` instead. **When to deviate (the only real cases):** you need O(1) splice/splitting of large lists at a held cursor, or you're storing intrusive nodes for an allocator/scheduler — and even then most teams use an arena + indices instead. If you're typing `LinkedList` from a data-structures reflex, stop and pick `VecDeque`.

### HashMap vs BTreeMap: ordering is the axis

Both map keys to values; the choice is whether you need **order**.

- `HashMap<K,V>`: O(1) average lookup/insert via hashing. Iteration order is unspecified and randomized per-execution (the default `RandomState` hasher defends against HashDoS). **When to deviate:** you need sorted iteration, `.range(a..b)` queries, or "nearest key" semantics — none of which a hash map can give.
- `BTreeMap<K,V>`: a cache-conscious B-tree (wide nodes, not a binary tree). O(log n) operations, but keys are always sorted, enabling range scans:

```rust
/// Keys in [lo, hi] in sorted order — only a BTreeMap can do this.
fn between(map: &BTreeMap<i32, &str>, lo: i32, hi: i32) -> Vec<i32> {
    map.range(lo..=hi).map(|(&k, _)| k).collect()
}
```

**Performance nuance:** for small maps or cheap-to-hash keys, `BTreeMap`'s constant factors and cache locality can *beat* `HashMap` despite the worse asymptotic — measure rather than assume. **Hasher deviation:** in a trusted, hot path where DoS is not a threat, swapping in `ahash`/`fxhash` (via `HashMap<K,V,S>`) is a legitimate, large win; never do it on attacker-controlled keys.

### HashSet / BTreeSet and BinaryHeap

Sets are the maps with `()` values and carry the same ordering trade-off. `BinaryHeap<T>` is a max-heap giving O(1) peek and O(log n) push/pop of the maximum — use it for priority queues, streaming top-k, Dijkstra. It is **not** sorted storage; iterating it yields arbitrary order. For a min-heap, wrap in `std::cmp::Reverse`:

```rust
/// Reverse turns the max-heap into a min-heap without a custom Ord.
fn drain_ascending(data: &[i32]) -> Vec<i32> {
    let mut heap: BinaryHeap<Reverse<i32>> = data.iter().map(|&x| Reverse(x)).collect();
    let mut out = Vec::with_capacity(heap.len());
    while let Some(Reverse(x)) = heap.pop() { out.push(x); }
    out
}
```

**When to deviate:** if you need *all* elements sorted once, `Vec` + `sort_unstable` is O(n log n) in one pass and more cache-friendly than n heap pops.

### The `entry` API: never look up twice

`map.entry(k)` is the idiomatic read-or-insert. **Why:** it hashes/traverses to the slot *once*, whereas `if map.contains_key() { ... } else { ... }` traverses twice and fights the borrow checker.

```rust
/// One hash+probe per word, not two.
fn word_count(text: &str) -> HashMap<&str, u32> {
    let mut counts = HashMap::new();
    for w in text.split_whitespace() {
        *counts.entry(w).or_insert(0) += 1;
    }
    counts
}
```

Use `or_insert_with(f)` when the default is expensive (closure runs only on a miss) and `or_default()` for `Default` types.

### Capacity, `with_capacity`, and amortization

`Vec`/`HashMap`/etc. grow by *reallocating and moving* to a larger buffer (roughly doubling), which makes `push` **amortized** O(1) — most pushes are free, occasional ones copy everything. **Mechanism to exploit:** if you know the final size, `with_capacity(n)` (or `reserve(n)` on an existing collection) allocates once, eliminating every intermediate realloc + move.

```rust
/// One allocation instead of ~log2(n) reallocations.
fn build(n: usize) -> Vec<u32> {
    let mut v = Vec::with_capacity(n);
    for i in 0..n as u32 { v.push(i); }
    v
}
```

**Why it matters:** reallocation is the hidden cost in tight build loops and it invalidates any raw pointers into the buffer. **Trade-off:** over-reserving wastes memory; a wrong guess is worse than none. **When to deviate:** if the size is unknown or the collection is tiny, don't bother — the default growth is fine and `with_capacity(0)` is noise. Note `collect()` from an iterator with a good `size_hint` already reserves for you, so manual capacity there is redundant.

## Iterators

Iterators are Rust's primary abstraction for sequence processing, and idiomatic Rust prefers them over index loops — not for terseness but because they're **lazy, composable, and compile to the same code as a hand-written loop.**

### Laziness: adapters vs consumers

An iterator does nothing until consumed. **Adapters** (`map`, `filter`, `take`, `enumerate`, `zip`, `flat_map`, …) are lazy: they wrap the iterator and return a new one, running no work. **Consumers** (`collect`, `sum`, `for_each`, `count`, `fold`, `find`, `any`) drive it to completion. **Why this matters in review:** a chain of adapters with no consumer is a no-op — a real bug the compiler warns about (`unused_must_use`), and a sign someone expected eager side effects. Laziness is also what makes infinite iterators (`(0..)`, `repeat`) and short-circuiting (`find`, `take_while`) work: only the demanded elements are produced.

### `collect` and type inference

`collect()` is generic over its return type via `FromIterator`, so the target type must be inferable. Provide it by annotating the binding or with turbofish:

```rust
let squares: Vec<i32> = (1..=5).map(|x| x * x).collect();
let set = (1..=5).collect::<HashSet<i32>>();       // turbofish when no binding type
let map: BTreeMap<i32, i32> = (1..=3).map(|x| (x, x * x)).collect();
```

**Why turbofish exists:** when the result feeds directly into another call, there's no binding to annotate. **Trade-off:** it's noisier; prefer a typed binding when one is natural. A pair-yielding iterator collecting into a map is a genuinely useful, non-obvious capability — reach for it instead of a manual insert loop.

### `collect::<Result<_, _>>()`: fail the whole pipeline cleanly

Collecting an iterator of `Result<T, E>` into `Result<Vec<T>, E>` short-circuits on the first `Err`, returning it; on all-`Ok` you get the `Vec`. This is the idiomatic "parse-all-or-fail" and replaces a manual loop with early return.

```rust
/// Returns the first parse error, or all values.
fn parse_all(items: &[&str]) -> Result<Vec<i32>, std::num::ParseIntError> {
    items.iter().map(|s| s.parse::<i32>()).collect()
}
```

The same transposition works for `Option`. **Trade-off:** you lose the other errors (only the first surfaces); if you need *all* failures, `partition` the results or use `itertools`. **When to deviate:** for independent items where one failure shouldn't abort the batch, collect into `Vec<Result<_,_>>` and handle them individually.

### Avoiding intermediate allocations

The most common iterator anti-pattern is `collect`ing to a `Vec` mid-pipeline only to iterate it again. Each `collect` heap-allocates. Keep the chain lazy end-to-end and consume once:

```rust
/// No intermediate Vec: filter+map+sum fuse into one pass.
fn sum_of_squares_even(data: &[i32]) -> i32 {
    data.iter().filter(|&&x| x % 2 == 0).map(|&x| x * x).sum()
}
```

**Why:** the fused chain touches each element once with no allocation; the `collect`-then-loop version allocates and traverses twice. **When to deviate:** you genuinely need the intermediate materialized (e.g. to iterate it multiple times, sort it, or because a borrow must end). Also prefer `iter()`/`iter_mut()`/`into_iter()` deliberately — borrow vs consume is a real decision, and needless `.clone()` to dodge a borrow error is the allocation you're trying to avoid, reintroduced.

### Zero-cost: why chains rival manual loops

Iterator adapters are monomorphized generic structs whose `next()` bodies inline into each other; LLVM then optimizes the fused result identically to a hand-rolled loop — the "zero-cost abstraction" claim, and it holds in practice for `slice`/`Vec` iteration (bounds checks elide, the loop vectorizes). **Why prefer them anyway:** they express intent (`filter`+`map`+`sum` vs a mutable accumulator and manual index) and remove off-by-one and bounds-check bugs. **When to deviate:** rarely for performance — if a profiler shows a specific chain not optimizing (often across a dynamic-dispatch or `dyn` boundary where inlining stops), a manual loop may win, but that's a measured exception, not a default. See `performance.md`.

### Custom `Iterator` impls

Implement `Iterator` when you have a lazy sequence with no natural backing collection — a generator, a parser producing tokens, a paginated API cursor. You implement one required method, `next`; the ~70 adapters come free via default methods.

```rust
/// Lazy, allocation-free Fibonacci. `take(n)` bounds it.
struct Fib { a: u64, b: u64 }
impl Iterator for Fib {
    type Item = u64;
    fn next(&mut self) -> Option<u64> {
        let cur = self.a;
        self.a = self.b;
        self.b = cur + self.b;
        Some(cur)
    }
}
fn fib() -> Fib { Fib { a: 0, b: 1 } }
```

**Judgment:** override `size_hint` when you know the length — `collect` uses it to pre-reserve. Implement `ExactSizeIterator`/`DoubleEndedIterator` only when the semantics are truly exact/reversible; a wrong `size_hint` is a soundness-adjacent footgun (it must never *over*-promise). **When to deviate:** if the data already lives in a `Vec`, don't write an iterator — return `impl Iterator<Item = _> + '_` from a method by delegating to the slice's iterator.

### When std falls short: `itertools`

Reach for the `itertools` crate when the standard adapters force an awkward manual step: `chunks`/`tuple_windows` (or `array_windows`) on arbitrary iterators, `chunk_by`, `unique`, `sorted`, `itertools::izip!` for 3+ way zips, `partition_map`, `join`. **Why not always:** it's a dependency and its lazy semantics occasionally differ from intuition (e.g. `chunk_by` — formerly `group_by`, mirroring `slice::chunk_by` — groups *consecutive* equal keys, like Unix `uniq`, not a global grouping). **When to deviate — stay in std:** if `flat_map`, `scan`, `fold`, or `chunks` on a slice already express it, don't add the dep. Rule of thumb: if you're writing an explicit `while let Some(x) = it.next()` loop to regroup elements, check `itertools` first.

## Closures

Closures are anonymous functions that capture their environment. The entire design turns on *how* they capture, which determines *which trait* they implement — and that trait is your API's contract.

### `Fn` / `FnMut` / `FnOnce`: the capture-and-call ladder

The compiler auto-picks how each variable is captured (by `&`, `&mut`, or by value — edition 2021+ captures *disjoint fields*, not whole structs), then implements the most permissive trait that fits:

- **`FnOnce`** — callable at least once; may *consume* captured values (move them out). Every closure is `FnOnce`. Take this bound when you'll call it exactly once (e.g. `thread::spawn`, `Option::map`).
- **`FnMut`** — callable repeatedly, may *mutate* captured state (captures by `&mut`). Take this for callbacks that accumulate.
- **`Fn`** — callable repeatedly without mutating (captures by `&` or nothing). The *strictest* bound (fewest closures satisfy it) but the most capable value: require it only when you genuinely need repeated non-mutating calls.

The subtyping is `Fn : FnMut : FnOnce` — a `Fn` satisfies an `FnMut` bound, which satisfies `FnOnce`. **API design rule:** require the *weakest* trait that lets you do your job (`FnOnce` if you call once), because it *accepts the most* closures; but *return*/store the strongest you can promise. Getting this wrong needlessly rejects a caller's valid closure.

```rust
fn call_twice<F: Fn() -> i32>(f: F) -> i32 { f() + f() }        // needs Fn: called 2x, no mutation
fn accumulate<F: FnMut(i32)>(mut sink: F, data: &[i32]) {        // FnMut: mutates captured state
    for &x in data { sink(x); }
}
fn consume<F: FnOnce() -> String>(f: F) -> String { f() }        // FnOnce: may move captures out
```

### `move`: transferring ownership into the closure

`move` forces every capture to be *by value* regardless of how the body uses it; the load-bearing mental model is *snapshot the captured values now* (at closure creation), not 'give away ownership' — which is why `(0..3).map(|i| move || i)` cleanly yields closures returning 0, 1, 2 with none of the live-variable late-binding trap that bites languages closing over a shared loop binding. **Why:** the closure must outlive the current scope — spawned onto a thread, returned from the function, or stored — so it can't hold references into a stack frame that's about to vanish. **Trade-off:** captured values are moved in (or copied if `Copy`), so the enclosing scope loses them; if you need shared access, `move` a `clone` or an `Arc` in. **When to deviate:** if the closure is consumed synchronously within the scope (passed to `map`, `sort_by`), omit `move` and let inference borrow — moving needlessly gives up the originals for no reason.

### Passing closures: `impl Fn` vs `Box<dyn Fn>`

- **`impl Fn(..) -> ..` (static dispatch)** — the default. Each closure is a distinct zero-sized-ish type; a generic/`impl Trait` parameter monomorphizes and inlines the call. **Why default:** no allocation, no vtable, full inlining. **Trade-off:** code bloat from monomorphization, and you can't mix different closure types in one collection.
- **`Box<dyn Fn(..) -> ..>` (dynamic dispatch)** — type-erases the closure behind a vtable on the heap. **Why:** required when you must store *heterogeneous* closures together, break monomorphization to shrink binary size, or name the type in a struct field without a generic parameter.

```rust
/// Heterogeneous ops must be boxed — different closures, one Vec, one type.
fn make_ops() -> Vec<Box<dyn Fn(i32) -> i32>> {
    vec![Box::new(|x| x + 1), Box::new(|x| x * 2)]
}
```

**When to deviate:** don't box a single closure passed to one function — that's a pointless allocation and lost inlining; use `impl Fn`. Reach for `Box<dyn>` (or `&dyn`) only at the point you genuinely need type erasure.

### Returning closures

Return `impl Fn(..) -> ..` — the closure's type is unnameable, so `impl Trait` is how you hand one back with static dispatch. Add `move` because the returned closure outlives the function.

```rust
/// `move` captures `n` by value so the returned closure owns it.
fn adder(n: i32) -> impl Fn(i32) -> i32 {
    move |x| x + n
}
```

**When to deviate:** if you need to return *different* closures from different branches (their types differ, so `impl Trait` can't unify them), fall back to `Box<dyn Fn(..)>`. A function returning `impl Fn` from an `if`/`else` with two different closure bodies will *not* compile — that's the signal to box.

## Smart pointers

Smart pointers add ownership semantics (and sometimes runtime bookkeeping) over a pointer. Choose the *weakest* one that models your ownership graph; every step up the ladder costs allocation, indirection, or runtime checks.

### `Box<T>`: heap allocation with unique ownership

`Box<T>` owns a single heap allocation. **When it's actually needed** (not "to put it on the heap" reflexively):
1. **Recursive types** — a type containing itself has infinite size; `Box` gives the recursive field a fixed pointer size.
2. **Trait objects** — `Box<dyn Trait>` owns a type-erased value.
3. **Large values you move often** — moving a `Box` copies one pointer, not the whole payload (measure before assuming this helps; moves of plain data are often already cheap).

```rust
/// Without Box, Expr would be infinitely sized.
enum Expr { Num(i64), Add(Box<Expr>, Box<Expr>) }
fn eval(e: &Expr) -> i64 {
    match e {
        Expr::Num(n) => *n,
        Expr::Add(l, r) => eval(l) + eval(r),
    }
}
```

**Trade-off:** an allocation + a pointer indirection (cache miss). **When to deviate:** if the value is small and lives on the stack fine, `Box` is pure overhead.

### `Rc` / `Arc`: shared ownership, and `Weak` for cycles

`Rc<T>` (single-thread) and `Arc<T>` (atomic, thread-safe) enable *multiple owners*; the value drops when the last owner does, tracked by a reference count. `Arc` uses atomic increments/decrements — correct across threads but more expensive than `Rc`'s plain integer ops.

**Judgment:** shared ownership is a real design signal, not a convenience. Prefer a single owner with borrows (`&T`) or indices into a central `Vec` (arena pattern) — they're cheaper and make the ownership graph legible. Reach for `Rc`/`Arc` when ownership genuinely is shared and lifetimes can't express it: a graph with multiple parents, a cache handed to many consumers, an immutable config shared across tasks.

- **`Rc` vs `Arc`:** use `Rc` in single-threaded code; the atomics in `Arc` are wasted cost there. Use `Arc` the moment the value crosses a thread boundary (the compiler forces this — `Rc` isn't `Send`). Don't default to `Arc` "to be safe."
- **Mutation:** `Rc`/`Arc` give *shared, immutable* access. To mutate, combine with interior mutability: `Rc<RefCell<T>>` (single-thread) or `Arc<Mutex<T>>` (multi-thread). See `concurrency.md`.
- **Cycles leak:** `Rc`/`Arc` are reference-counted, not garbage-collected. A cycle (A owns B owns A) keeps both counts ≥ 1 forever — a memory leak, not a crash. Break it with `Weak<T>`, a non-owning reference that doesn't bump the strong count; upgrade it to `Option<Rc<T>>` at use.

```rust
/// Parent<->child: children own via Rc, parent link is Weak — no cycle, no leak.
struct Node {
    parent: RefCell<Weak<Node>>,
    children: RefCell<Vec<Rc<Node>>>,
    value: i32,
}
fn tree() -> Rc<Node> {
    let leaf = Rc::new(Node {
        parent: RefCell::new(Weak::new()),
        children: RefCell::new(vec![]),
        value: 3,
    });
    let branch = Rc::new(Node {
        parent: RefCell::new(Weak::new()),
        children: RefCell::new(vec![Rc::clone(&leaf)]),
        value: 5,
    });
    *leaf.parent.borrow_mut() = Rc::downgrade(&branch);
    branch
}
```

The rule: **ownership edges are strong (`Rc`); back-references are `Weak`.** Note `Rc::clone(&x)` (explicit) over `x.clone()` — it signals "cheap refcount bump, not a deep copy" to the reader. In review, treat any `Rc<RefCell<T>>` graph that can close a cycle without a `Weak` edge as a leak: `Rc`/`Arc` are the same reference-counting scheme as Python's refcount, but with no cycle-detecting GC behind it, so a cycle is reclaimed by nothing and leaks silently rather than crashing.

### `Cow<'a, B>`: borrow until you must own

`Cow` (clone-on-write) is an enum: `Borrowed(&B)` or `Owned(B::Owned)`. **Why:** functions that *usually* return their input unchanged but *sometimes* must produce a modified copy — return `Cow` and only allocate on the rare mutation path.

```rust
/// Allocates only when a space actually needs replacing.
fn normalize(input: &str) -> Cow<'_, str> {
    if input.contains(' ') {
        Cow::Owned(input.replace(' ', "_"))
    } else {
        Cow::Borrowed(input)
    }
}
```

**Trade-off:** callers now match/deref a `Cow` instead of a `&str`; the API is slightly heavier. **When to deviate:** if you *always* allocate (every input is modified) `Cow` adds nothing over returning `String`; if you *never* allocate, return `&str`. `Cow` earns its keep only when the split is real and the hot path is the borrow — parsing/normalization where input is usually already valid is the sweet spot. Don't stash a `Cow` in a long-lived struct field either: the `Borrowed` variant chains the struct to the input's lifetime, so store `String` when the value must outlive its source.

### `Deref` / `DerefMut` coercion and its pitfalls

`Deref` lets `&SmartPtr<T>` be used where `&T` is expected: the compiler inserts `.deref()` calls automatically, and chains them. This is why `&Box<String>` works where `&str` is wanted (`Box<String>` → `String` → `str`) and why method calls "see through" `Rc`, `Box`, `String`→`str`, `Vec`→`[T]`.

```rust
fn takes_str(s: &str) -> usize { s.len() }
fn deref_demo() -> usize {
    let boxed: Box<String> = Box::new(String::from("hi"));
    takes_str(&boxed)   // &Box<String> -> &String -> &str, inserted for you
}
```

**Pitfalls that bite in review:**
- **`Deref` is for smart pointers, not inheritance.** Implementing `Deref` on a domain type to "inherit" an inner type's methods is an anti-pattern the API Guidelines warn against — it pollutes autocomplete, makes the method set surprising, and confuses readers about ownership. Use explicit delegation or `AsRef`.
- **Method resolution favors the receiver, then derefs.** Autoref tries the receiver type *before* dereferencing, so `x.clone()` on `x: Rc<T>` always resolves to `<Rc<T>>::clone` (a refcount bump) — it can never silently deep-copy the pointee. The community-convention `Rc::clone(&x)` is a *readability* choice, not a resolution fix: at a glance a reader can't tell whether `.clone()`'s receiver is an `Rc` or the owned value, so the explicit form makes the cheap operation obvious. The one genuine surprise is on a *reference*: `x.clone()` where `x: &Rc<T>` resolves to `<&Rc<T>>::clone` and yields `&Rc<T>`, not `Rc<T>`.
- **`DerefMut` and interior mutability don't compose freely** — you can't get `&mut` through a shared `Rc`; that's what `RefCell`/`Mutex` are for.

## Interior mutability

Interior mutability lets you mutate through a shared (`&`) reference by moving the borrow check from *compile time* to *runtime* (or to a `Copy` swap). It's the escape hatch for "I have `&self` but must mutate," used inside `Rc`, caches, and observers — never reach for it to dodge a borrow error you could fix by restructuring.

### `Cell<T>` vs `RefCell<T>`

- **`Cell<T>`** — no borrowing at all: you `get()` (requires `T: Copy`) or `set()`/`replace()`/`take()` the *whole* value. **Why:** zero runtime overhead, *cannot panic*, no references handed out. **When:** small `Copy` state — counters, flags, cached hashes.

```rust
struct Counter { hits: Cell<u32> }
impl Counter {
    fn bump(&self) { self.hits.set(self.hits.get() + 1); }  // mutate through &self, no panic risk
}
```

- **`RefCell<T>`** — hands out `Ref`/`RefMut` guards via `borrow()`/`borrow_mut()`, enforcing the aliasing rules (many readers XOR one writer) **at runtime**. Violating them **panics** (or `try_borrow` returns `Err`). **When:** non-`Copy` data you must borrow (a `Vec`, a `String`), typically inside `Rc<RefCell<T>>`.

```rust
fn shared_log() -> Rc<RefCell<Vec<String>>> {
    let log = Rc::new(RefCell::new(Vec::new()));
    log.borrow_mut().push("start".into());  // runtime-checked mutable borrow
    log
}
```

**The decision:** `Cell` if the type is `Copy` and you swap wholesale; `RefCell` if you must borrow a reference into it. **Trade-off:** `RefCell` moves borrow errors to *runtime panics* — a correctness risk the compiler can't catch, so keep borrow scopes tiny (don't hold a `RefMut` across a call that might re-borrow). **When to deviate:** if you can restructure to satisfy the static borrow checker, do — interior mutability is a last resort, not a convenience. For concurrency, `Cell`/`RefCell` are `!Sync`; use `Mutex`/`RwLock`/atomics instead.

### `OnceCell` / `OnceLock` / `LazyLock`: write-once & lazy init (all stable)

- **`OnceCell<T>`** (single-thread) / **`OnceLock<T>`** (thread-safe) — a cell settable *at most once*, via `set()` or `get_or_init(f)`. **When:** the value needs *runtime input* not available at declaration (a config URL, a parsed arg), so you can't bake the initializer into the static.
- **`LazyLock<T>`** (thread-safe; `LazyCell` single-thread) — the preferred stable form when the initializer is *known at declaration*: it stores the cell *and* its init closure together, running it on first access. **Why prefer it:** there's no separate `init()` step, no repeated `get_or_init`, and no code path where initialization was forgotten. This replaces the old `lazy_static!`/`once_cell::sync::Lazy` patterns — do not add `once_cell` for new code.

```rust
use std::sync::{LazyLock, OnceLock};

/// Initializer known now -> LazyLock. No accessor boilerplate.
static CONFIG: LazyLock<String> = LazyLock::new(|| "default".to_string());

/// Value depends on runtime input -> OnceLock, set once at startup.
static DB_URL: OnceLock<String> = OnceLock::new();
fn set_db_url(url: &str) { let _ = DB_URL.set(url.to_string()); }
```

**Stability note:** `OnceCell`, `OnceLock`, `LazyLock`, and `LazyCell` are all stable as of Rust 1.80. The external `once_cell` crate and `lazy_static!` macro are now historical — reach for std. **When to deviate to `OnceLock` over `LazyLock`:** only when you can't name the initializer at declaration (runtime input, or you must handle init failure fallibly with `set`).

### `Mutex` / `RwLock`: the concurrent counterparts (overview)

`Mutex<T>` and `RwLock<T>` are the thread-safe interior-mutability primitives: they own the data and hand out a guard only while the lock is held, so `Arc<Mutex<T>>` is the multi-threaded analog of `Rc<RefCell<T>>`. `Mutex` = exclusive access; `RwLock` = many readers XOR one writer (worth it only when reads vastly dominate and the critical section is non-trivial). Unlike `RefCell`, contention *blocks* rather than panics — but Rust's `Mutex` can be *poisoned* if a holder panics, surfacing as an `Err` on `lock()`. Full treatment — poisoning, deadlock avoidance, `parking_lot`, lock granularity, and choosing locks vs channels vs atomics — is in `concurrency.md`.

## Sources

- Microsoft RustTraining, C/C++ Book — *`Cow<'a, T>`: Clone-on-Write* and *`Weak<T>`: Breaking Reference Cycles* (arena `Vec`+indices over `Rc`/`Weak` in new code): <https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch17-1-avoiding-excessive-clone.md>
- Microsoft RustTraining, C# Book — *Smart Pointers: When Single Ownership Isn't Enough* (decision tree; "start with `Rc`, the compiler tells you when you need `Arc`"): <https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch07-3-smart-pointers-beyond-single-ownership.md>
- Microsoft RustTraining, Rust for Python Developers — *Ownership and Borrowing: Smart Pointers* (`Rc`/`Arc` refcount vs Python's cycle-collecting GC): <https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch07-ownership-and-borrowing.md>
- Microsoft RustTraining, Rust for Python Developers — *Closures and Iterators: Closure Capture, How Rust Differs* (`move` as snapshot; no late-binding capture bug): <https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch12-closures-and-iterators.md>

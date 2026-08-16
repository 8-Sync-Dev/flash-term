# Anti-Patterns, Pitfalls & Traps

A symptom-first catalog of what NOT to write in Rust, why it's wrong, and the idiomatic fix. Scan by symptom, match to your diff, apply the fix. Complements `rust-patterns` (idioms) and `rust-testing` — this file is the failure mode, not the recipe. Baseline: Rust 1.96, edition 2024.

## How to read this

Each entry is **symptom → cause → fix**. The symptom is what you'll actually see in a diff or a `clippy` run; the cause is the wrong mental model behind it; the fix names the mechanism, the trade-off, and when the "anti-pattern" is actually correct. Most of these are not syntax errors — they compile fine. That is exactly why they need a checklist: the compiler won't catch a design smell.

The meta-rule: **most anti-patterns are Rust fighting a habit imported from another language.** `.clone()` everywhere is GC nostalgia. `Rc<RefCell<T>>` graphs are Java object soup. Stringly-typed APIs are Python duck-typing. `Box<dyn Error>` in a library is exception-throwing. Name the imported habit and the fix usually follows.

---

## Type & API anti-patterns

### Stringly-typed everything
**Symptom:** functions take `&str`/`String` for things that are not free text — `status: &str`, `role: String`, `parse_kind(s: &str)` with a `match` on string literals scattered across the codebase. Invalid values are caught at runtime, or never.

**Cause:** modeling a closed set of states as an open type. A `String` can hold `"admni"`; the type system can't help you.

**Fix:** make illegal states unrepresentable. Parse strings **once at the boundary** into an `enum` or a newtype, then pass the typed value everywhere inside. The compiler enforces exhaustiveness on `match`, so adding a variant flags every site that must change — treat that missing-arm error as free impact analysis and never silence it with a catch-all `_ =>` on a domain enum you own (C#'s `switch` only warns, then throws `SwitchExpressionException` at runtime, so the discipline is unique to Rust).

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UserId(pub u64);

pub enum Role { Admin, Member, Guest }

pub fn can_delete(role: &Role) -> bool {
    matches!(role, Role::Admin)
}

/// Parse at the boundary; the interior never sees a raw string.
pub fn parse_role(s: &str) -> Option<Role> {
    match s {
        "admin"  => Some(Role::Admin),
        "member" => Some(Role::Member),
        "guest"  => Some(Role::Guest),
        _ => None,
    }
}
```

**Trade-off:** more types, and a conversion at every boundary (I/O, FFI, serde). **When to deviate:** the value genuinely *is* free-form text (a username, a log line), or the set is open and defined by an external system you don't control. Newtypes still earn their keep there — `UserId(u64)` prevents passing an `OrderId` where a `UserId` is expected, a bug `u64`-everywhere can't catch.

### Over-generic APIs / `impl Trait` overuse
**Symptom:** `fn process<T: Into<String>, U: AsRef<[u8]>, F: Fn(T) -> U>(...)` on a function with one caller. Every parameter is a type parameter "for flexibility." Compile times balloon; error messages become unreadable; the `.rs` doc page is a wall of `where`.

**Cause:** treating generics as free. They are not — each instantiation is monomorphized into separate machine code (binary bloat), and each bound is a promise you must keep in the signature forever.

**Fix:** generics earn their place when there are (or will plausibly be) *multiple* concrete types AND the abstraction is on a hot path where dynamic dispatch would cost. Otherwise take the concrete type, or one `impl Trait` argument for genuine ergonomics (`impl AsRef<Path>` on a file API is idiomatic and justified — callers pass `&str`, `String`, `PathBuf` freely). Prefer `&str` over `impl Into<String>` unless you actually store the `String`.

**Trade-off:** concrete types are less reusable. **When to deviate:** library crates whose whole job is abstraction (`serde`, iterators) — there generality *is* the product. The test: does a second concrete caller exist or is imminent? If not, YAGNI.

`impl Trait` in return position (`fn iter(&self) -> impl Iterator<Item = u32>`) is idiomatic and stable — it hides an unnameable type without a `Box`. But it's an opaque leak: the caller can't name the type to store it in a struct field, and changing the body can change the auto-traits (`Send`/`Sync`) you expose. Return a named type (or `Box<dyn>`) when the return type is part of a stable public contract.

### Trait object where an enum fits — and the reverse
**Symptom (object):** `Vec<Box<dyn Shape>>` for a fixed, known set of shapes you defined yourself. Every call is a vtable indirection + heap allocation; you can't `match`; you can't easily add a method that returns `Self`.

**Cause:** reaching for OOP polymorphism when the set of types is *closed and known at compile time*.

**Fix:** a closed set → `enum` + `match`. No allocation, no vtable, exhaustiveness-checked, and methods can return `Self` or take it by value.

```rust
pub enum Shape {
    Circle { r: f64 },
    Rect { w: f64, h: f64 },
}

impl Shape {
    pub fn area(&self) -> f64 {
        match self {
            Shape::Circle { r }    => std::f64::consts::PI * r * r,
            Shape::Rect { w, h }   => w * h,
        }
    }
}

pub fn total_area(shapes: &[Shape]) -> f64 {
    shapes.iter().map(Shape::area).sum()
}
```

**Symptom (reverse):** a 30-variant `enum` where callers outside the crate need to add their own variant, or every `match` is `40` arms of near-identical delegation. This is an enum straining to be a trait.

**Fix:** open set / extensible by downstream crates / heterogeneous plugin types → `Box<dyn Trait>` (or `&dyn Trait`). The vtable cost buys you extensibility the enum can't offer.

**Decision:** closed set you own → enum. Open set / third-party extensible / very large variant count with uniform behavior → trait object. Trade-off is dispatch cost + allocation (object) vs. lost extensibility + match churn (enum).

### Needless lifetimes, `'static` cargo-culting, `?Sized` noise
**Symptom:** `fn first<'a>(v: &'a [i32]) -> &'a i32` where lifetime elision already handles it; `T: 'static` bounds sprinkled on functions that don't need them; `T: ?Sized` on generics that are always sized.

**Cause:** copying bounds from an error message or an unrelated example without understanding them. Pre-NLL (before Rust 2018's non-lexical lifetimes) some manual lifetimes were needed; that era is over.

**Fix:** delete the annotation and let the compiler tell you if it's actually required. Elision covers the overwhelming majority of `&self`-returning-a-reference cases. Add `'static` only when you truly store the value beyond the current scope (spawning a thread/task that outlives the caller, `Box<dyn Any + 'static>`). Add `?Sized` only when you deliberately want to accept `str`/`[T]`/`dyn Trait` by reference.

**Trade-off:** none — removing cargo-culted bounds is strictly a win in readability and caller flexibility. **When it's real:** self-referential-ish APIs, thread spawning, and trait objects genuinely need explicit bounds. Keep those; delete the rest.

### `Box<dyn Error>` in a library's public API
**Symptom:** a library function returns `Result<T, Box<dyn std::error::Error>>` (or `anyhow::Result`). Callers can only `.to_string()` the error — they cannot `match` on failure kinds to retry, fall back, or map to HTTP codes.

**Cause:** treating errors as strings-to-log rather than values-to-handle. Convenient for the author, useless for the consumer.

**Fix:** a **library** exposes a concrete error type — an `enum` implementing `std::error::Error` (via `Display` + the trait), ideally with `#[from]` conversions (hand-rolled or via `thiserror`). Callers pattern-match on the failure. Applications, at the top level, may collapse everything into `anyhow`/`Box<dyn Error>` because they only log-and-exit.

```rust
use std::fmt;

#[derive(Debug)]
pub enum ConfigError {
    Missing { key: String },
    Parse { key: String, reason: String },
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConfigError::Missing { key } => write!(f, "missing config key `{key}`"),
            ConfigError::Parse { key, reason } => write!(f, "bad value for `{key}`: {reason}"),
        }
    }
}
impl std::error::Error for ConfigError {}

pub fn load_port(raw: Option<&str>) -> Result<u16, ConfigError> {
    let raw = raw.ok_or_else(|| ConfigError::Missing { key: "port".into() })?;
    raw.parse().map_err(|e: std::num::ParseIntError| ConfigError::Parse {
        key: "port".into(),
        reason: e.to_string(),
    })
}
```

**Trade-off:** more upfront error-type design; a growing enum. **When to deviate:** internal binaries, prototypes, and the `main`/handler layer of an app — there `anyhow` is the right tool. The rule is *libraries expose typed errors, applications consume opaque ones.* (Rust API Guidelines: C-GOOD-ERR.)

### Reimplementing std
**Symptom:** a hand-rolled `Option`-like `enum MyMaybe`, a bespoke singly-linked list, a custom `Result` clone, a manual `HashMap` over `Vec<(K,V)>` with linear scan.

**Cause:** unfamiliarity with the standard library surface, or a C/C++ reflex that a linked list is a natural default.

**Fix:** learn the std toolbox. `Option`/`Result` and their combinators (`map`, `and_then`, `ok_or`, `?`) cover control flow. For collections: `Vec` is the default sequence; `VecDeque` for a ring/queue; `HashMap`/`BTreeMap` for maps; `HashSet`/`BTreeSet` for sets. **`std::collections::LinkedList` exists but is almost never the right answer** — its cache behavior is terrible and it lacks O(1) arbitrary splice in safe code; `Vec`/`VecDeque` win in practice. Reach for a crate (`indexmap`, `smallvec`, `hashbrown`) before hand-rolling.

**Trade-off:** none, generally — std is battle-tested and optimized. **When to deviate:** a genuinely specialized data structure std doesn't provide (a lock-free queue, an arena, a specialized trie), and only after profiling proves the generic option is the bottleneck.

### Silent narrowing with `as`; `[]` where `.get()` fits
**Symptom:** `x as u8` to shrink an integer; `vec[i]`/`map[key]` for lookups that can miss.

**Cause:** treating `as` as a universal cast. Narrowing `as` is *silent data loss* — `300u16 as u8` wraps to `44` with no warning; indexing with `[]` **panics** on an out-of-range `Vec` index (a defined crash, not C++ UB) and `map[key]` does **not** auto-insert a default like C++'s `operator[]`.

**Fix:** use `From`/`Into` for infallible widening (`let n: u32 = 42u8.into();`) and `TryFrom`/`TryInto` for narrowing (`300u16.try_into()` is `Err`, so the loss is visible and handleable). Index with `.get()` returning `Option` and chain fallible lookups with `.and_then()`/`.unwrap_or()`. Reserve `as` for *deliberate* lossy conversions, and prefer `to_ne_bytes`/`from_ne_bytes` over `transmute` for byte reinterpretation.

**Trade-off:** `try_into` forces a `Result`/`Option` at the call site. **When `as` is fine:** provably-in-range narrowing you can justify, intentional float↔int truncation, and enum-to-int on a field-less enum.

### Magic sentinel values instead of `Option`; `Drop` on a generic typestate
**Symptom:** carrying a protocol sentinel (IPMI `0xFF`, PCI `0xFFFF`, "empty" = `-1`) as an ordinary field; or trying to `impl Drop for Ctx<Locked>` to attach state-specific cleanup to one typestate variant.

**Cause:** a sentinel means every consumer must remember to special-case it — one forgotten comparison yields a phantom reading or a spurious match. And Rust requires a `Drop` impl to cover *all* instantiations of a generic type (E0366: `Drop` impls can't be specialized), so cleanup can't be pinned to a single `PhantomData` typestate.

**Fix:** convert the sentinel to `Option` at the *first* parse boundary (`(raw != 0xFF).then_some(raw)`), so the "absent" case is unrepresentable downstream. For per-state cleanup, give the state that owns the resource its own concrete wrapper type (`LockedGpu`) carrying the `Drop`, rather than a type parameter on a shared struct.

**Trade-off:** an extra wrapper type per resource-owning state. **When a sentinel is unavoidable:** a wire format you must round-trip byte-for-byte — keep it at the edge, never in domain types.

---

## Ownership & borrow anti-patterns

### `.clone()` to silence the borrow checker
**Symptom:** a `.clone()` (or `.to_owned()`, `.to_vec()`) appears the moment a borrow error does, with no thought to whether ownership is actually needed. A hot loop clones a `String`/`Vec` every iteration.

**Cause:** treating the borrow checker as an obstacle to appease rather than a design signal. The error is telling you the *ownership model is unclear*, and cloning papers over it.

**Fix:** first ask *who owns this and for how long*. Usually the fix is to (a) borrow (`&T`) instead of move, (b) restructure so the borrow ends before the conflicting use (NLL makes this easy — split the code so the last use of the borrow precedes the mutation), (c) take an index/handle instead of a reference, (d) when the conflict is *mutate-while-iterating*, `collect()` the changes into a separate `Vec` and `extend`/`retain` afterward instead of borrowing mutably mid-iteration, or (e) use `Cow<'_, str>` to borrow in the common case and own only when you must mutate:

```rust
use std::borrow::Cow;

pub fn normalize(input: &str) -> Cow<'_, str> {
    if input.contains(' ') {
        Cow::Owned(input.replace(' ', "_")) // allocate only when needed
    } else {
        Cow::Borrowed(input)                // zero-copy common path
    }
}
```

**Trade-off:** a deliberate `.clone()` is sometimes the *right, cheapest, clearest* answer — cloning a small `Copy`-ish struct or an `Arc` (which just bumps a refcount) is fine. **When to deviate:** clone freely when the type is cheap (`Arc`, `Rc`, small POD), when it's outside a hot path, and when the alternative is a lifetime-annotation maze that hurts readability more than the clone hurts performance. The legitimately-narrow cases are few: an `Arc::clone` (a ~1 ns refcount bump, not a data copy), moving data into a spawned thread or closure, and extracting an owned value out of a `&self` borrow — and even there, return a borrowed view (`self.serial.as_deref().unwrap_or(UNKNOWN)`) when you can, owning only when you must. The anti-pattern is the *reflexive, unexamined* clone, especially in a loop — not cloning per se.

### `Rc<RefCell<T>>` graph soup
**Symptom:** a tree/graph/DOM built from `Rc<RefCell<Node>>` with `Weak` back-pointers everywhere; `.borrow_mut()` scattered through the code; the occasional `already borrowed: BorrowMutError` panic at runtime.

**Cause:** porting a pointer-graph design from a GC or C++ language directly. `Rc<RefCell<T>>` re-creates shared mutability by moving the borrow check to *runtime*, which is exactly what Rust's static model exists to avoid.

**Fix:** for tree/graph structures, prefer an **index-based arena**: store nodes in a `Vec` and reference them by `usize` index (or a generational index via a crate like `slotmap`). No refcounting, no runtime borrow panics, trivially `Send`, cache-friendly, and cycles are harmless (indices don't leak).

```rust
pub struct Tree { nodes: Vec<Node> }
pub struct Node { pub value: i32, pub children: Vec<usize> }

impl Tree {
    pub fn new() -> Self { Tree { nodes: Vec::new() } }
    pub fn add(&mut self, value: i32) -> usize {
        let id = self.nodes.len();
        self.nodes.push(Node { value, children: Vec::new() });
        id
    }
    pub fn link(&mut self, parent: usize, child: usize) {
        self.nodes[parent].children.push(child);
    }
    pub fn sum(&self, root: usize) -> i32 {
        let n = &self.nodes[root];
        n.value + n.children.iter().map(|&c| self.sum(c)).sum::<i32>()
    }
}
```

**Trade-off:** indices are weaker than references — you can hold a stale index after removal (generational indices via `slotmap` fix this). **When `Rc<RefCell<T>>` is right:** genuinely shared ownership with unpredictable lifetimes and *low* mutation (observer patterns, shared config), single-threaded, where an arena would be awkward. Use it deliberately, not as the default graph tool.

### Self-referential struct attempts
**Symptom:** a struct trying to hold both a buffer and a slice/reference into that same buffer (`struct S { data: String, view: &'? str }`), fighting the borrow checker with increasingly exotic lifetime annotations that never compile.

**Cause:** Rust moves values, which would invalidate an internal pointer; the language forbids this in safe code by design. This is not a skill issue — it's a fundamental constraint.

**Fix:** don't store the reference; store an **index or range** into the owned data and compute the slice on access (`&self.data[self.start..self.end]`). If you need true self-reference (e.g. wrapping a C API), use the `Pin` machinery via an established crate (`ouroboros`, `self_cell`, `yoke`) rather than hand-rolling `unsafe`. For async, `async`/`await` handles the common self-referential-future case for you.

**Trade-off:** index-based indirection is slightly less ergonomic. **When to deviate:** essentially never hand-roll this — reach for a vetted crate. The correctness surface of self-referential `unsafe` is a Rustonomicon-level trap.

### `mem::transmute` where `From`/`as` works
**Symptom:** `unsafe { std::mem::transmute(x) }` for a numeric cast, an enum-to-int, or a struct conversion.

**Cause:** `transmute` looks like "just reinterpret the bits," a C cast. It is the single most dangerous function in Rust — it bypasses type checking and produces instant UB if the bit pattern is invalid for the target type, if the layouts aren't guaranteed compatible (`repr(Rust)` layout is unspecified), or if it launders a lifetime. Size mismatches are the *one* thing it does catch — `E0512` at compile time.

**Fix:** for value conversions, implement `From`/`Into` (safe, checked, discoverable). For numeric conversions, use `as` (lossy but defined) or `TryFrom` (checked). For enum-to-integer, `as` on a field-less enum works; for the reverse use a `match` or `num_enum`.

```rust
pub struct Celsius(pub f64);
pub struct Fahrenheit(pub f64);

impl From<Celsius> for Fahrenheit {
    fn from(c: Celsius) -> Self { Fahrenheit(c.0 * 9.0 / 5.0 + 32.0) }
}
pub fn to_f(c: Celsius) -> Fahrenheit { c.into() }
```

**Trade-off:** `From` is a few lines of boilerplate. **When `transmute` is genuinely needed:** extremely rare — reinterpreting between two `#[repr(C)]`/`#[repr(transparent)]` types of provably identical layout, or slice-of-bytes reinterpretation (prefer `bytemuck`/`zerocopy` which encode the safety invariants in the type system). If you write `transmute`, you owe a `// SAFETY:` comment proving layout equality.

---

## Error & panic anti-patterns

### `.unwrap()` / `.expect()` in production paths
**Symptom:** `.unwrap()` on I/O, network, parse, or lock results in library/service code. A malformed input or a poisoned lock takes down the process.

**Cause:** using `unwrap` as "I'll handle errors later," or conflating *impossible* with *unlikely*.

**Fix:** propagate with `?` and a typed error, or handle explicitly. Reserve `.expect("reason")` for invariants that are *truly impossible* if the program is correct — and then the message must state the invariant, so a panic is a bug report ("BUG: config validated at startup, key must exist"). `.unwrap()` with no message is acceptable only in tests, examples, and `main` prototypes.

**Trade-off:** `?` requires an error type in scope and a `Result` return. **When `unwrap`/`expect` is right:** tests (a panic *is* the failure signal), examples/docs, prototypes, and provable invariants. Also `unwrap()` on a `RwLock`/`Mutex` lock is a common deliberate choice — a poisoned lock means another thread already panicked, and propagating is often pointless. Note: `.unwrap()` is *not* an anti-pattern by itself; the anti-pattern is `.unwrap()` on a recoverable, externally-triggered failure.

### Leaking `panic!` across an FFI boundary
**Symptom:** an `extern "C"` function (called from C, or exposing a Rust callback to C) that can panic — a `.unwrap()`, an array index, an allocation.

**Cause:** forgetting that unwinding a panic across a non-Rust frame is **undefined behavior**. Rust 1.81+ (all editions) aborts by default at an `extern "C"` boundary rather than unwinding into C, but you should not rely on abort as your error strategy — you lose the ability to report the error to the caller.

**Fix:** wrap the fallible body in `std::panic::catch_unwind` and convert a caught panic into an error return code (or a null pointer / out-param). Keep the actual work in a normal Rust function that returns `Result`; the `extern "C"` shim is a thin translation layer that catches, logs, and returns a C-friendly status.

```rust
// illustrative
#[unsafe(no_mangle)]
pub extern "C" fn do_work(input: i32) -> i32 {
    let result = std::panic::catch_unwind(|| {
        // real fallible Rust work here
        checked_work(input) // -> Result<i32, _>
    });
    match result {
        Ok(Ok(v))  => v,
        Ok(Err(_)) => -1, // domain error
        Err(_)     => -2, // panic caught; never let it cross the boundary
    }
}
# fn checked_work(x: i32) -> Result<i32, ()> { Ok(x) }
```

**Trade-off:** `catch_unwind` adds a landing pad and only catches unwinding panics (not `panic = "abort"` builds, and not aborts). **When to deviate:** if your whole binary is `panic = "abort"`, unwinding can't happen — but you still must ensure no partial state escapes. The rule stands: a panic must never unwind into non-Rust code.

---

## Performance pitfalls

Measure before fixing any of these — the Rust Performance Book's first rule is that intuition about hot spots is usually wrong. That said, these are the recurring offenders.

### Allocation storms / `#[derive(Clone)]` then clone in a loop
**Symptom:** a profiler shows `malloc`/`memcpy` dominating; a `.clone()` of a `Vec`/`String`/`HashMap` inside a loop body; building a large collection element-by-element without `with_capacity`.

**Cause:** each clone of a heap type is a fresh allocation + copy; each `push` past capacity is a realloc + move. In a loop these compound.

**Fix:** hoist the clone out of the loop (clone once, reuse); borrow instead of clone; reuse a single buffer across iterations (`buf.clear(); ... ` instead of a new `String` each time); pre-size with `Vec::with_capacity(n)` / `String::with_capacity(n)` when the size is known or estimable. For accumulation, `collect()` from an iterator lets std size the allocation once from the size hint.

**Trade-off:** buffer reuse can make code slightly less obviously-correct (must remember to `clear`). **When it doesn't matter:** cold paths, small N — don't contort readable code for allocations that don't show up in a profile.

### `String` `+` concatenation in a loop
**Symptom:** `s = format!("{s}{part}")` reassigned in a loop, or `s = s + &part;` in a loop.

**Cause:** `s = format!("{s}{part}")` allocates a fresh buffer and copies the whole accumulator every iteration — O(n²) total. `s = s + &part` is *not* quadratic (`Add<&str> for String` consumes `self` and `push_str`s into the existing buffer with amortized-doubling growth, amortized O(1) per append), but it's still noisy and forces the accumulator to be moved through each iteration — prefer `push_str`/`write!` or `join`.

**Fix:** build into one buffer with `push_str`/`write!`, or `collect`/`join` an iterator:

```rust
use std::fmt::Write;

pub fn join_csv(items: &[&str]) -> String {
    let mut out = String::with_capacity(items.len() * 8);
    for (i, item) in items.iter().enumerate() {
        if i > 0 { out.push(','); }
        let _ = write!(out, "{item}"); // write! into String never fails
    }
    out
}
```

For the common "join with separator" case, prefer `items.join(",")` outright — it's clearer and pre-sizes internally. **Trade-off:** none meaningful. **When `+` is fine:** joining two or three strings once, outside any loop.

### `Vec::insert(0, ..)` / `remove(0)` in a loop
**Symptom:** repeatedly inserting or removing at the front of a `Vec`.

**Cause:** `Vec` is contiguous; front operations shift every element — O(n) each, O(n²) in a loop.

**Fix:** use `VecDeque`, a ring buffer with O(1) `push_front`/`pop_front`:

```rust
use std::collections::VecDeque;

pub fn build_queue(xs: &[i32]) -> VecDeque<i32> {
    let mut q = VecDeque::with_capacity(xs.len());
    for &x in xs { q.push_front(x); }
    q
}
```

**Trade-off:** `VecDeque`'s ring layout means its elements aren't a single contiguous slice (`make_contiguous` costs a shuffle), and it's marginally slower for pure back-push + index than `Vec`. **When `Vec` is right:** you only push/pop at the back, or you need `&[T]` slice semantics.

### `collect()` then re-iterate
**Symptom:** `let v: Vec<_> = it.map(..).collect(); for x in &v { .. }` where `v` is used once; or `.collect::<Vec<_>>().iter().filter(..)` — collecting only to iterate again.

**Cause:** breaking iterator laziness for no reason, materializing an intermediate allocation.

**Fix:** keep the chain lazy and consume once. Iterators fuse map/filter/etc. into a single pass with no intermediate `Vec`:

```rust
pub fn sum_of_squares_of_evens(xs: &[i32]) -> i32 {
    xs.iter()
        .filter(|&&x| x % 2 == 0)
        .map(|&x| x * x)
        .sum()
}
```

**Trade-off:** none when you consume once. **When to collect:** you iterate the result *multiple* times, you need random access / a length, you must break a borrow (collect to end an immutable borrow before mutating), or the lazy chain would re-run expensive work per pass. Collecting to satisfy those is correct, not an anti-pattern.

### HashMap default hasher for adversarial keys — and blindly swapping it out
**Symptom (DoS):** using the default `HashMap` with attacker-controlled string keys in a public-facing service — an attacker crafts colliding keys to degrade lookups to O(n) (HashDoS). **Symptom (reverse):** replacing the default hasher with a fast non-cryptographic one (`FxHashMap`, `ahash` with a fixed seed) for keys that *are* adversarial, "because benchmarks."

**Cause:** the default hasher is SipHash — DoS-resistant but not the fastest. It's the right default *precisely because* it's safe against adversarial input. Blindly swapping it for speed removes that protection.

**Fix:** keep the default (SipHash) when keys are untrusted/external. Switch to `FxHashMap`/`ahash`/`fnv` only when keys are trusted and internal (compiler symbol tables, integer keys you generate, hot inner loops on known data) — and document why. The decision is a threat-model question, not a benchmark question.

**Trade-off:** SipHash is ~2-4× slower to hash than Fx; Fx/ahash are non-DoS-resistant. **Rule:** trusted keys + hot path → fast hasher; untrusted input → keep SipHash. Never swap "for performance" without asking who controls the keys.

### Bounds-check paranoia
**Symptom:** rewriting clean indexed code with `unsafe { *v.get_unchecked(i) }` to "avoid bounds checks," or contorting logic to eliminate checks the optimizer already removes.

**Cause:** overestimating bounds-check cost. LLVM elides most of them (iterators, `chunks`, ranges the compiler can prove in-bounds), and a mispredicted branch elsewhere dwarfs a predictable bounds check.

**Fix:** write idiomatic iterator code — `for x in &v`, `.iter()`, `.windows()`, `.chunks()` — which is bounds-check-free *and* safe because the iterator drives the bounds. If you index in a hot loop, hoist the length check or slice once (`let s = &v[..n];`) so the compiler proves subsequent indexing safe. Reach for `get_unchecked` only with a profiler showing the check is a proven, measured bottleneck, plus a `// SAFETY:` proof.

**Trade-off:** `get_unchecked` is UB if you're wrong. **When it's justified:** measured hot loops in numeric/codec code where you can prove the invariant — rare, and iterators usually get you there safely first.

---

## Concurrency pitfalls

### `Arc<Mutex<Vec<_>>>` where a channel or rayon fits
**Symptom:** worker threads all locking a shared `Arc<Mutex<Vec<Result>>>` to push results; heavy lock contention; a bottleneck that scales *negatively* with thread count.

**Cause:** modeling parallel work as shared mutable state (a "global accumulator") instead of message passing or data parallelism. All threads serialize on one lock.

**Fix:** for fan-out/fan-in, have each worker *own* its work and **send results on a channel** (`std::sync::mpsc`, or `crossbeam`/`flume` for MPMC); the collector owns the `rx`. This also means errors flow as values instead of being silently dropped:

```rust
use std::sync::mpsc;
use std::thread;

pub fn parallel_squares(inputs: Vec<u64>) -> Vec<u64> {
    let (tx, rx) = mpsc::channel();
    for x in inputs {
        let tx = tx.clone();
        thread::spawn(move || { let _ = tx.send(x * x); });
    }
    drop(tx);            // close last sender so rx terminates
    rx.iter().collect()
}
```

For CPU-bound data parallelism over a collection, `rayon`'s `par_iter().map(..).collect()` is simpler and faster than manual threads + mutex — it handles work-stealing and result collection for you. **Trade-off:** channels add a queue; rayon adds a dependency and a thread pool. **When `Arc<Mutex<>>` is right:** genuinely shared state with low contention and no natural producer/consumer shape (a shared cache, a config read by many) — and even then prefer `RwLock` for read-heavy access.

### Deadlock via inconsistent lock order
**Symptom:** the program hangs intermittently under load; two code paths lock `a` then `b`, and `b` then `a`.

**Cause:** classic lock-ordering deadlock — thread 1 holds `a` waiting for `b`, thread 2 holds `b` waiting for `a`.

**Fix:** establish and document a **global lock ordering** — always acquire in the same order (e.g. by address, by a defined hierarchy). Better, avoid holding two locks at once: copy what you need out of lock 1, release it, then take lock 2. Best, restructure so there's one lock or none (channels, ownership transfer). Never call unknown/user code (a callback, a trait method you don't control) while holding a lock — it might re-enter and lock again.

**Trade-off:** a strict lock order constrains code structure. **When simpler:** if you find yourself designing a lock hierarchy, that's a strong signal to switch to message passing instead.

### Holding a `MutexGuard`/`RefCell` borrow across an `.await`
**Symptom:** in async code, `let g = mutex.lock().unwrap(); some_async_fn().await; use(g);` — a `std::sync::Mutex` guard held across a suspension point. This compiles — nothing forbids holding the guard across a suspension point. The breakage shows up later: `std::sync::MutexGuard` is `!Send`, so the whole future becomes non-`Send` and `tokio::spawn` (multithreaded runtime) rejects it. And even on a single-threaded runtime where `Send` is not required, it's a bug: it can deadlock.

**Cause:** the future may be suspended and *another task resumed on the same thread* while the lock is held — that task tries to lock, and since it's the same thread, blocks forever (or another worker stalls). A synchronous lock has no idea a task yielded.

**Fix:** either (a) drop the guard before the `.await` — do the locked work, extract the value, release, then await; or (b) if you must hold state across an await, use an **async-aware lock** (`tokio::sync::Mutex`), whose `.lock().await` yields instead of blocking. Prefer (a): async mutexes are slower and usually a sign the critical section is too big.

```rust
// illustrative
// BAD: guard lives across await
// let g = m.lock().unwrap(); fetch().await; g.push(...);

// GOOD: shrink the critical section, drop before await
async fn ok(m: &std::sync::Mutex<Vec<u8>>) {
    let data = { let g = m.lock().unwrap(); g.clone() }; // guard dropped here
    let _ = data;
    tokio::task::yield_now().await; // no lock held across the await
}
```

**Trade-off:** `tokio::sync::Mutex` allows cross-await holding but costs more and can't be locked from sync code. **Rule:** default to `std::sync::Mutex` + short critical sections; use `tokio::sync::Mutex` only when the lock genuinely must span an await.

### False sharing
**Symptom:** a parallel counter/histogram scales poorly despite no logical contention; per-thread data lives in one array (`counters: [AtomicU64; N]`) and threads hammer adjacent entries.

**Cause:** adjacent atomics share a 64-byte cache line; each write invalidates the line in every other core's cache (cache-line ping-pong), serializing what should be independent.

**Fix:** pad each hot per-thread datum to its own cache line — `crossbeam_utils::CachePadded<T>` (or a manual `#[repr(align(64))]` newtype). Or, better, keep per-thread local accumulators and merge once at the end (no sharing at all during the hot loop).

**Trade-off:** padding wastes memory (56 bytes per counter). **When to ignore:** cold data, or data that isn't concurrently written. False sharing only bites *concurrently mutated adjacent* data — diagnose it with a profiler (high cache-miss / coherence traffic) before padding everything.

### Spawning unbounded tasks / threads
**Symptom:** `for req in stream { tokio::spawn(handle(req)); }` with no limit; or spawning an OS thread per unit of work. Under load, memory and scheduler overhead explode; the system falls over.

**Cause:** treating task/thread spawning as free. Each task has memory + scheduling cost; unbounded spawning is an unbounded resource.

**Fix:** bound concurrency. Use a `Semaphore` (`tokio::sync::Semaphore`) to cap in-flight tasks, a bounded channel as backpressure, or a fixed worker pool (`rayon` for CPU, a sized `tokio` task set / `JoinSet` with a cap for async). For sync CPU work, a thread pool (rayon) not thread-per-item.

**Trade-off:** bounded concurrency adds a limit to tune and can create backpressure that must propagate to producers. **When unbounded is ok:** a known-small, fixed number of tasks (spawning one per CPU core, a handful of background services). The anti-pattern is *unbounded growth driven by external input*.

### `spawn` + detach that silently drops errors/panics
**Symptom:** `thread::spawn(move || work())` or `tokio::spawn(async { work().await })` where the `JoinHandle` is discarded. If `work` returns an `Err` or panics, it vanishes — no log, no propagation, a silent partial failure.

**Cause:** fire-and-forget without capturing the outcome. The handle *is* the error channel; dropping it drops the error.

**Fix:** keep the `JoinHandle`/`AbortHandle` and `.join()`/`.await` it, propagating the `Result` (and detecting panics via the `Err(JoinError)`). For many tasks, collect handles in a `JoinSet` (tokio) or a `Vec<JoinHandle<_>>` and drain them, surfacing the first error. If the task truly is best-effort, at minimum log the outcome in the task body so failures are observable.

**Trade-off:** joining couples the spawner's lifetime to the task. **When detach is fine:** genuinely fire-and-forget background work whose failure is logged internally and doesn't affect correctness (a metrics flush) — but even then, *log*, never silently swallow.

### Premature lock-free / premature `unsafe` for performance
**Symptom:** hand-rolled lock-free structures with `AtomicPtr` and manual `Ordering::Relaxed`/`Acquire`/`Release` reasoning, or `unsafe` "for speed," before any measurement shows locks are the bottleneck.

**Cause:** assuming locks are slow and lock-free is fast. Uncontended `Mutex` lock/unlock is a handful of nanoseconds; correct lock-free code is extraordinarily hard (memory ordering, ABA, the Rustonomicon's hardest chapters) and often *slower* under real contention.

**Fix:** start with a `Mutex`/`RwLock` or a channel. Profile. If the lock is genuinely the bottleneck, reach for a *vetted* concurrent structure (`dashmap`, `crossbeam` queues, `arc-swap`) written and audited by experts — do not hand-roll atomics. Reserve custom `unsafe`/lock-free for measured, isolated, heavily-tested hot spots.

**Trade-off:** locks can contend. **When lock-free is justified:** a proven, measured hot path where a vetted crate doesn't fit — a tiny fraction of code, and even then prefer the crate. "Premature optimization is the root of all evil" applies with extra force to concurrency correctness.

---

## Module & architecture anti-patterns

### Fighting the module system with deep nesting
**Symptom:** `crate::services::internal::helpers::util::v2::do_thing`; `mod.rs` files re-exporting through five layers; `pub use` chains that obscure where a type is actually defined; a hierarchy deeper than the domain warrants.

**Cause:** importing a Java/C# package-per-concept habit, or nesting modules to "organize" before there's enough code to organize.

**Fix:** keep the module tree **flat and domain-shaped**. Modules should map to bounded concepts, not to arbitrary layers. Use `pub(crate)` to share within the crate without leaking to the public API, and a small, curated set of `pub use` re-exports at the crate root to present a clean facade (the "flatten the public API" guideline — C-REEXPORT). If a path is painful to write, that's a signal the structure is wrong, not that you need another `use` alias. Prefer one file per module until it's large enough to split (edition 2018+ needs no `mod.rs`; `foo.rs` + `foo/` works).

**Trade-off:** a flat structure needs discipline to avoid a single giant module. **When depth is warranted:** genuinely large crates with real sub-domains (a compiler's `parser`/`typeck`/`codegen`) — nest by *domain*, not by *layer* (`util`, `helpers`, `common` are smells; name modules after what they do). The public API depth (what users type) matters more than internal file layout — flatten the former aggressively with re-exports.

### Silent `#[cfg]` mismatch
**Symptom:** platform- or feature-gated code silently vanishes from the build — a whole `#[cfg(feature = "windws")]` block (typo) or a `#[cfg(feature = "x")]` for a feature nothing enables compiles to *nothing*, with no error.

**Cause:** `cfg` is compiler-evaluated conditional compilation, not a C preprocessor — an unmet or misspelled predicate is not a warning, it's simply absent code.

**Fix:** exercise every feature combination in CI with `cargo hack check --each-feature` (add `--feature-powerset` for interactions). For a must-support invariant, make the mistake a hard failure with a guard like `#[cfg(all(target_os = "windows", not(feature = "windows")))] compile_error!("windows target requires the windows feature")`.

**Trade-off:** `cargo hack` adds CI time proportional to feature count. **When it's overkill:** a crate with no optional features and one target — there's nothing to mismatch.

---

## Quick symptom index

| You see… | Likely anti-pattern | Jump to |
|---|---|---|
| `.clone()` next to a borrow error | appeasing the borrow checker | Ownership |
| `Rc<RefCell<Node>>` in a tree | graph soup | Ownership |
| `Box<dyn Error>` returned from a lib | opaque library errors | Type & API |
| `&str` for a closed set of values | stringly-typed | Type & API |
| `Vec<Box<dyn T>>` for types you own | trait object over enum | Type & API |
| `.unwrap()` on I/O in a service | panic in production | Error & panic |
| `transmute` for a conversion | should be `From`/`as` | Ownership |
| `s = s + &x` in a loop | quadratic string concat | Performance |
| `Vec::insert(0, ..)` in a loop | wrong collection (use `VecDeque`) | Performance |
| `.collect()` then one `for` loop | broken laziness | Performance |
| `Arc<Mutex<Vec<_>>>` accumulator | should be a channel / rayon | Concurrency |
| guard held across `.await` | async deadlock risk | Concurrency |
| `tokio::spawn(...)` handle dropped | silent error loss | Concurrency |
| `get_unchecked` with no profile | bounds-check paranoia | Performance |
| hand-rolled `AtomicPtr` structure | premature lock-free | Concurrency |
| `crate::a::b::c::d::e::f` paths | module over-nesting | Architecture |
| `300u16 as u8` silent wrap | narrowing `as` data loss | Type & API |
| `0xFF`/`-1` sentinel field | should be `Option` | Type & API |
| `#[cfg(feature = "windws")]` typo | silent cfg mismatch | Architecture |

---

## Sources

- The Rust Programming Language ("The Book") — error handling, ownership, enums vs traits: https://doc.rust-lang.org/book/
- Rust API Guidelines — C-GOOD-ERR (typed errors), C-REEXPORT (flatten API), C-NEWTYPE: https://rust-lang.github.io/api-guidelines/
- The Rustonomicon — `transmute`, unsafe, self-referential types, FFI unwinding: https://doc.rust-lang.org/nomicon/
- Rust Performance Book — allocations, collections, hashing, profiling-first discipline: https://nnethercote.github.io/perf-book/
- Tokio docs — async mutexes, `spawn`, bounded concurrency, blocking-in-async: https://tokio.rs/
- `rust-clippy` lint rationale (`needless_lifetimes`, `redundant_clone`, `large_enum_variant`, `mutex_atomic`): https://rust-lang.github.io/rust-clippy/
- Comprehensive Rust (Google) — structured fundamentals for the idiomatic fixes: https://google.github.io/comprehensive-rust/
- std docs — `VecDeque`, `Cow`, `LinkedList` caveats, `catch_unwind`, `mpsc`: https://doc.rust-lang.org/std/
- Microsoft RustTraining, c-cpp-book — excessive `clone()` / when clone is appropriate, and the C++→Rust cast hierarchy (`as`/`TryFrom`, indexing): https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch17-1-avoiding-excessive-clone.md , https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch18-cpp-rust-semantic-deep-dives.md
- Microsoft RustTraining, csharp-book — exhaustive matching vs C# `switch` runtime errors: https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch06-1-exhaustive-matching-and-null-safety.md
- Microsoft RustTraining, python-book — borrow-checker pitfalls (collect-then-mutate to mutate while iterating): https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch16-best-practices.md
- Microsoft RustTraining, type-driven-correctness-book — sentinel→`Option`, `Drop` on a typestate (E0366): https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch11-fourteen-tricks-from-the-trenches.md
- Microsoft RustTraining, engineering-book — Windows/conditional compilation, `cargo hack`, `compile_error!` guards: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch10-windows-and-conditional-compilation.md

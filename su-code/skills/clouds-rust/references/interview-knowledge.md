# Senior Rust Interview Knowledge

Model answers to the conceptual questions a senior Rust engineer must answer crisply — each is a compressed *argument*, not a flashcard. Doubles as a rapid concept-refresher for the agent. Baseline: **Rust 1.96, edition 2024**; nightly-only items are tagged. For idiom/TDD basics see the `rust-patterns` / `rust-testing` skills — this file assumes them and goes deeper.

## Ownership, borrowing, lifetimes

### Explain ownership to a C++ engineer
The one-sentence bridge: **ownership is `unique_ptr` move semantics promoted to a language-wide, compiler-enforced invariant, plus a borrow checker that makes dangling references a compile error instead of UB.** In C++ a move leaves a "valid but unspecified" source you can still touch; in Rust a move *statically invalidates* the source — using it afterward doesn't compile. `&T` is roughly `const T&` and `&mut T` is `T&`, but with a global rule C++ lacks: at any instant a value has **either** many `&T` **or** exactly one `&mut T`, never both (shared-XOR-mutable, aka aliasing XOR mutation). That single rule is what buys memory safety *and* data-race freedom without a GC. The cost you pay versus C++: some correct programs are rejected because the checker's model is conservative, and you sometimes restructure code to satisfy it (or reach for `Rc`/`RefCell`).

### What did NLL (non-lexical lifetimes) change?
Pre-2018, a borrow lasted until the end of its lexical scope (the enclosing `{}`), so `let r = &v; use(r); v.push(x);` failed even though `r` was dead by the `push`. **NLL redefined a borrow's lifetime as the region up to its last actual use**, computed from the control-flow graph, not lexical nesting. Why it matters: it eliminated a whole genre of "clone to shut the borrow checker up" workarounds and made the checker match programmer intuition. Trade-off: essentially none for users — it strictly accepts more. If you see old code with an artificial inner scope `{ let r = &v; }` purely to end a borrow early, that's a **historical pre-NLL pattern**; delete the braces. The current frontier is Polonius (a more precise, still-nightly borrow-check engine) which accepts a few more conditional-return patterns; don't design around it yet.

### Variance — and why you rarely think about it
Variance is how the subtype relation on lifetimes lifts through types. `&'a T` is **covariant** in `'a`: a `&'long` is usable where `&'short` is expected (longer-lived is a subtype). `&'a mut T` is covariant in `'a` but **invariant** in `T` — you cannot substitute a different-lifetime `T` under a mutable reference, because that would let you *write* a short-lived value into a long-lived slot and then read a dangle. `fn(T) -> U` is contravariant in `T`, covariant in `U`. `Cell<T>`/`RefCell<T>` are invariant in `T` for the same read-and-write reason. You mostly don't hand-reason this; it surfaces when a lifetime error says "one type is more general than the other" or when a `PhantomData` marker changes what compiles. `PhantomData<T>` inherits `T`'s variance; `PhantomData<fn() -> T>` gives covariance without owning a `T`, `PhantomData<fn(T)>` gives contravariance — the standard trick for getting variance right in unsafe abstractions.

### Why `'static` does *not* mean "lives forever"
`T: 'static` means **"`T` contains no references that outlive `'static`"** — i.e. it *could* be held indefinitely, not that it *will* be. An owned `String` is `'static` because it borrows nothing, yet it's dropped at end of scope. `&'static str` is the stricter case: a reference actually valid for the whole program (string literals, leaked allocations). The distinction that trips people: `T: 'static` as a *bound* (no borrowed data) versus `&'static` as a *reference lifetime* (points at forever-live memory). `thread::spawn` requires `'static` on the closure not because the thread runs forever, but because the runtime can't prove it ends before any borrowed data does. When you hit a `'static` bound you can't satisfy, the fix is usually to *own* the data (clone/`Arc`) or use a scoped API (`std::thread::scope`) that reintroduces a shorter provable lifetime.

## Move vs Copy vs Clone

`Copy` is an implicit, bit-for-bit duplicate with **no destructor and no logic** — the source stays valid (it's `memcpy`). `Clone` is an explicit, possibly-expensive, possibly-deep duplicate you call by name (`.clone()`), and it can run arbitrary code. A **move** is the default for non-`Copy` types: bits are copied *and the source is invalidated* — mechanically identical to a `Copy` at runtime, the difference is purely which the compiler lets you touch afterward. `Copy: Clone` is a supertrait, so every `Copy` type is also `Clone`.

The senior judgment: **make a type `Copy` only when copying it is always cheap and always semantically correct** — small, plain-data, no ownership of a resource. A type holding a `Box`, `Vec`, file handle, or lock *cannot* be `Copy` (would double-free / double-close). Deriving `Copy` is a **public API commitment**: it becomes a breaking change to add a non-`Copy` field later, and it silently changes call-site semantics (assignments stop being moves). So prefer *not* deriving `Copy` on domain types unless you specifically want value semantics; leaving a type move-only keeps you free to add resources later. `#[derive(Clone)]` is far cheaper to commit to.

## `String` vs `&str`, `Vec<T>` vs `[T]` vs `&[T]`

`String`/`Vec<T>` are **owned, growable, heap-backed** (ptr, len, capacity). `str`/`[T]` are **unsized** (`!Sized`) contiguous views with no ownership — you never hold one bare, only behind a reference or pointer. `&str`/`&[T]` are **fat pointers**: (ptr, len), a borrowed window that may point into a `String`/`Vec`, a literal, or the stack.

The API rule that separates seniors from juniors: **take the borrowed slice, return the owned type.** Accept `&str` not `&String`, `&[T]` not `&Vec<T>` — deref coercion means a `&String` argument works for a `&str` parameter for free, and now your function also accepts literals, `Box<str>`, substrings, and array slices. Accepting `&String` gratuitously narrows callers for zero benefit. Return `String`/`Vec` when you produce new data (the caller needs ownership); return `&str`/`&[T]` only when lending out data you already store. For "maybe borrowed, maybe owned" (e.g. normalize-only-if-needed), reach for `Cow<'a, str>` to avoid allocating in the common case. When you deviate: you legitimately take `&mut String`/`&mut Vec<T>` when the function must *grow* the buffer in place.

## Choosing among `Box` / `Rc` / `Arc` / `RefCell` / `Cell`

These decompose along two orthogonal axes — **ownership cardinality** and **mutability discipline** — so choose one from each axis:

| Need | Single owner | Shared, single-thread | Shared, multi-thread |
|---|---|---|---|
| just heap / indirection | `Box<T>` | `Rc<T>` | `Arc<T>` |
| + interior mutation (`Copy`/replace-whole) | — | `Rc<Cell<T>>` | `Arc<Mutex<T>>` |
| + interior mutation (borrow region) | — | `Rc<RefCell<T>>` | `Arc<RwLock<T>>` |

- **`Box<T>`**: single ownership + heap. Use for recursion (`enum List { Cons(i32, Box<List>) }` — needs a known size), large values you want off the stack, or to store a trait object (`Box<dyn Trait>`). Zero overhead beyond the allocation and one pointer indirection.
- **`Rc<T>`**: shared ownership, non-atomic refcount, `!Send`. Cheapest shared ownership when everything stays on one thread (graphs, trees with shared subtrees). Gives `&T` only — combine with a cell for mutation.
- **`Arc<T>`**: same, but atomic refcount → `Send + Sync` (if `T: Send + Sync`). Pay for the atomics *only* when you actually cross threads. Reaching for `Arc` "to be safe" in single-threaded code is a real, if small, perf and cognitive cost.
- **`Cell<T>`**: interior mutability with **no borrows out** — you `get()` (needs `Copy`) / `set()` / `replace()` the whole value. Zero runtime cost, can never panic. Ideal for a `Copy` flag/counter behind `&self`.
- **`RefCell<T>`**: interior mutability via **runtime-checked borrows** (`borrow()`/`borrow_mut()`), moving the shared-XOR-mutable check from compile time to run time — **panics on violation**. Use when you genuinely need `&mut` into shared single-thread state and can't thread `&mut` through statically. The cost: you traded a compile error for a potential runtime panic, so keep borrow scopes short.

**Anti-pattern to name in review:** `Rc<RefCell<T>>` sprayed everywhere is usually a design that's fighting ownership — often a sign you want an arena / index-based graph (`Vec<Node>` + `usize` handles) instead. `Rc<RefCell<_>>` cycles also leak (refcounts never hit zero); break them with `Weak<T>`.

## `Send` and `Sync` — define precisely

- **`Send`**: it is safe to **move ownership** of a `T` to another thread. Almost everything is `Send`.
- **`Sync`**: it is safe to share `&T` across threads — equivalently, `T: Sync` iff `&T: Send`.

Both are **auto traits**: the compiler derives them structurally (a struct is `Send`/`Sync` iff all fields are), and they are **unsafe to implement by hand** because you're asserting a thread-safety property the compiler can't check.

- **`!Send` example: `Rc<T>`.** Its refcount is a plain non-atomic integer; two threads dropping clones would race on `count -= 1` and double-free or leak. So `Rc` is `!Send` (you can't move it to another thread) *and* `!Sync`.
- **`!Sync` example: `Cell<T>` / `RefCell<T>`.** They hand out mutation through `&self`; sharing `&Cell` across threads would allow unsynchronized concurrent writes → a data race. `Cell`/`RefCell` are `Send` (fine to *move* to one other thread) but `!Sync` (not fine to *share*). Contrast `Mutex<T>`: it *is* `Sync` because it synchronizes.

Why this matters architecturally: these two traits are the entire compile-time foundation of Rust's "fearless concurrency". A `!Send` in a struct silently makes the whole struct `!Send`, and the error only surfaces at the `thread::spawn`/`tokio::spawn` boundary — so when a spawn fails with "cannot be sent between threads", walk the field graph for the offending `Rc`/raw pointer/`MutexGuard`.

## Static vs dynamic dispatch

**Static dispatch** (generics / `impl Trait`) is **monomorphization**: the compiler stamps out a specialized copy of the function per concrete type, so calls are direct and **inlinable** — this is what makes iterator chains compile to the same code as a hand-written loop. Cost: code-size blow-up (each instantiation is real machine code) and longer compile times. **Dynamic dispatch** (`dyn Trait` behind `&`/`Box`/`Arc`) stores a **vtable pointer** alongside the data (fat pointer) and calls through it — one copy of the code, a pointer indirection per call, and **no inlining across the call**.

Decision: default to **generics** for hot paths and small trait sets. Reach for **`dyn Trait`** when you need **heterogeneous collections** (`Vec<Box<dyn Draw>>` — you can't have a `Vec` of mixed concrete types), when monomorphization bloat is real (many instantiations of a large function), when you want to shrink compile times, or when the type must be chosen at runtime (plugin, config). The per-call vtable cost is usually negligible; the *lost inlining* is what occasionally matters in tight loops. `enum` dispatch is a third option when the set of types is closed and known — no vtable, no allocation, exhaustive matching.

```rust
pub trait Encoder { fn encode(&self, b: &[u8]) -> Vec<u8>; }
// static: monomorphized, inlinable, one code copy per concrete E
pub fn encode_static<E: Encoder>(e: &E, b: &[u8]) -> Vec<u8> { e.encode(b) }
// dynamic: one code copy, vtable indirection, no inlining
pub fn encode_dyn(e: &dyn Encoder, b: &[u8]) -> Vec<u8> { e.encode(b) }
```

## What "zero-cost abstraction" really means (and its limits)

The claim is Stroustrup's, adopted by Rust: **"what you don't use, you don't pay for; and what you do use, you couldn't hand-code better."** Concretely: generics monomorphize to direct calls, iterators/closures/`Option`/`Result` compile away, `async` desugars to a state-machine struct with no runtime unless you spawn one. It's about **runtime cost**, and it's a claim about the *optimized* build.

The limits a senior states plainly:
1. **Compile time is not free** — monomorphization and heavy generics/macros cost real build time and binary size. That's the trade you make for runtime zero-cost.
2. **Only in release.** Debug builds (`opt-level=0`) do *not* inline the abstraction away; a debug iterator chain is genuinely slower than a debug loop. Never benchmark in debug.
3. **Optimizer-dependent.** "Couldn't hand-code better" assumes LLVM actually eliminates the abstraction — usually true, occasionally not (deep closure nests, `dyn` boundaries, missing `#[inline]` across crates). Verify with a profiler/`cargo asm`, don't assume.
4. **Not every abstraction is zero-cost** — `Rc`/`Arc`/`RefCell`/`dyn`/`Box` have real, deliberate runtime cost. "Zero-cost" describes generics, iterators, and `async` desugaring, not the whole language.

## How async works under the hood

`async fn`/`async {}` are **not** threads and don't run anything on their own — they desugar to a **state machine** implementing `Future`, whose `poll(self: Pin<&mut Self>, cx: &mut Context) -> Poll<Output>` is called by an **executor**. Each `.await` is a potential suspension point: `poll` runs until it hits an unready operation (socket not readable, timer not elapsed), returns `Poll::Pending`, and — crucially — first arranges for the resource to **call the `Waker`** (obtained from `cx`) when progress is possible. The executor parks that task and does other work; when the waker fires, the executor re-polls from where the state machine left off. So the model is **cooperative, poll-based, and lazy**: nothing progresses without an executor (`tokio`, `async-std`, `smol`) driving `poll`, which is why a future dropped before completion simply never runs, and why blocking (`std::thread::sleep`, sync I/O, a CPU-bound loop) inside an async task **starves the whole executor thread** — you must use async equivalents or `spawn_blocking`.

```rust
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
// A leaf future: shows the poll/Ready/Pending shape a real reactor fills in.
pub struct Ready<T>(Option<T>);
impl<T: Unpin> Future for Ready<T> {
    type Output = T;
    fn poll(mut self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<T> {
        Poll::Ready(self.0.take().expect("polled after completion"))
    }
}
```

**Why `Pin`?** An `async` block that holds a reference across an `.await` (e.g. `let x = ...; foo(&x).await;`) compiles to a **self-referential** state machine — a field pointing at another field of the same struct. If that struct moved in memory, the internal pointer would dangle. `Pin<P>` is the type-level promise **"this value will never move again"**, so the self-references stay valid. `poll` takes `Pin<&mut Self>` precisely to uphold this. Types that are safe to move even while pinned implement `Unpin` (an auto trait; most types are `Unpin`) — `Pin` only actually constrains `!Unpin` types, which is why hand-written futures over `Unpin` data barely notice it. This is also why you sometimes must `Box::pin`/`pin!` a future before polling it manually. `async fn` in traits is **stable since 1.75**; returning `impl Future` from trait methods and the `Pin<Box<dyn Future>>` pattern remain common for object-safe async.

## Trait objects and object safety

A **trait object** (`dyn Trait`) erases the concrete type behind a fat pointer (data ptr + vtable ptr). A trait can be made into an object only if it is **dyn-compatible** (the modern term for "object-safe"): roughly, every method must be callable through a vtable. The disqualifiers to recall: a method that returns **`Self`**, is **generic over a type parameter**, or the trait having **associated constants** or a `Self: Sized` requirement it can't satisfy. A by-value **`self`** receiver, by contrast, does *not* break dyn-compatibility — the trait stays object-safe — but such a method isn't *dispatchable* on `dyn Trait`: calling it fails with **E0161** ("cannot move a value of type `dyn Trait`") because the object is unsized. Mark it `self: Box<Self>` if it must be callable through the object, or `where Self: Sized` to drop it from the vtable entirely. Reason: the vtable is one fixed table of function pointers; a generic method would need infinitely many entries, and `-> Self` needs a size the caller doesn't know. Fix patterns: split the object-unsafe methods into a separate trait, add `where Self: Sized` to *exclude* a method from the vtable (keeping the rest object-safe), or return `Box<dyn Trait>` instead of `Self`. Since 1.75, `async fn`/`-> impl Trait` in traits are *not* dyn-compatible without the `Box`-future workaround, because the return type is an unnameable per-impl type.

```rust
pub trait Draw { fn draw(&self); }          // dyn-compatible: &self, no generics, no -> Self
pub fn render(items: &[Box<dyn Draw>]) {     // heterogeneous set -> needs dyn
    for it in items { it.draw(); }
}
```

## Orphan rule and coherence

**Coherence** is the guarantee that for any (type, trait) pair there is **at most one** `impl` in the entire program — so method resolution is unambiguous and can't change based on which crates are linked. The **orphan rule** enforces it: you may `impl Trait for Type` only if **the trait or the type is local to your crate** (with `#[fundamental]`/covered-type refinements for generics). Why: if crate A could `impl Display for Vec<u8>` and crate B also could, linking both would be an irreconcilable conflict — and neither `std` nor the other crate could ever add that impl without breaking someone. The rule pushes the cost onto you: to implement an external trait on an external type, wrap it in a local **newtype** (`struct MyVec(Vec<u8>);`) and impl on that. Deviation valve: the crate that *defines* the trait can provide blanket impls, and you can always impl your own trait on foreign types. This is a deliberate ecosystem-stability trade — less local flexibility, but adding an impl in a dependency is never a breaking change for coherence reasons.

## `?Sized`

Every generic type parameter has an **implicit `Sized` bound** — `fn f<T>(t: T)` really means `T: Sized`, because the compiler must know a size to pass by value and lay out stack frames. `T: ?Sized` **opts out** of that default, admitting **dynamically-sized types** (`str`, `[T]`, `dyn Trait`) — but then you can only handle `T` behind a pointer (`&T`, `Box<T>`, `Rc<T>`), since you still can't hold a DST by value. Use `?Sized` when a function/type only ever touches `T` through a reference and you want it to also accept slices/`str`/trait objects — the canonical case is `impl<T: ?Sized> AsRef<T>` and generic wrappers like `Box<T: ?Sized>`. **Don't cargo-cult it**: adding `?Sized` to a parameter you pass by value is a contradiction, and sprinkling it "just in case" widens your API surface (every caller's `T` must now work unsized) for no gain. Add it only when you have a concrete unsized caller in mind.

```rust
// Accepts &str, &[u8], &String, &Vec<u8> ... all for free.
pub fn debug_len<T: ?Sized + AsRef<[u8]>>(t: &T) -> usize { t.as_ref().len() }
```

## Interior mutability and shared-XOR-mutable

The core invariant is **shared XOR mutable**: through a shared `&T` you normally cannot mutate. **Interior mutability** is the *controlled* exception — types that expose `&self`-based mutation while upholding the invariant by a different mechanism. The unsafe primitive under all of them is `UnsafeCell<T>`, the *only* legal way to get `&mut T` from `&UnsafeCell<T>`; everything else (`Cell`, `RefCell`, `Mutex`, `RwLock`, `atomic::*`) is a safe wrapper that enforces the discipline at a different point:

- `Cell`/`atomics`: never hand out an interior `&`/`&mut`, so no aliasing is possible — enforced *by construction*, zero cost, can't panic.
- `RefCell`: hands out borrows but **counts them at runtime** and panics on shared-XOR-mutable violation — moves the check from compile time to run time.
- `Mutex`/`RwLock`: enforce the invariant across threads via blocking/locking.

Why the exception exists: sometimes the *logical* mutation (a cache, a refcount, a memoized field, an observer registration) is invisible to callers and shouldn't require `&mut` to ripple through every API. The trade you accept: `Cell` restricts you to whole-value get/set, `RefCell` reintroduces the possibility of a panic (a correctness risk you must localize), and locks add contention. When to deviate toward plain `&mut`: if you *can* thread mutability statically, do — it's checked at compile time and never panics.

```rust
use std::cell::{Cell, RefCell};
pub struct Counter { hits: Cell<u64>, log: RefCell<Vec<u64>> }
impl Counter {
    pub fn hit(&self) {                     // &self yet mutates -> interior mutability
        let n = self.hits.get() + 1;
        self.hits.set(n);                   // Cell: whole-value, cannot panic
        self.log.borrow_mut().push(n);      // RefCell: runtime-checked borrow
    }
}
```

## Memory layout and niche optimization

Rust structs/enums have **no guaranteed layout** by default (`repr(Rust)`): the compiler reorders and pads fields freely to minimize size/alignment. Use `#[repr(C)]` for a stable, C-compatible layout (FFI, memory-mapped structs), `#[repr(transparent)]` for a single-field newtype that must have the inner type's exact ABI, and `#[repr(u8)]` etc. to fix an enum's discriminant. Never assume field order otherwise.

**Niche optimization**: a "niche" is an invalid bit-pattern of a type — e.g. a reference/`Box` is never null, `bool` uses only 2 of 256 byte values, a `NonZeroU32` excludes 0. The compiler reuses a niche to encode an enum's discriminant *for free*, so `Option<&T>`, `Option<Box<T>>`, `Option<NonZeroU32>` are the **same size** as the inner type — `None` is stored as the otherwise-impossible value (null / 0). This is why `Option<&T>` is the idiomatic nullable pointer with zero overhead, and why wrapping FFI ints in `NonZero*` lets `Option` stay pointer-sized. Practical lever: order struct fields to help packing, and prefer types with niches (`NonZero*`, references) when you'll wrap them in `Option`/enums in hot data structures.

```rust
use std::mem::size_of;
pub fn layout_facts() {
    assert_eq!(size_of::<Option<&u8>>(), size_of::<&u8>());     // niche: null encodes None
    assert_eq!(size_of::<Option<Box<u8>>>(), size_of::<Box<u8>>());
    assert_eq!(size_of::<Option<bool>>(), 1);                    // bool has spare bit-patterns
    assert_eq!(size_of::<Option<u8>>(), 2);                      // u8 is full -> needs a tag byte
}
```

## How the borrow checker gives data-race freedom

A data race requires four things simultaneously: **two+ threads, concurrent access, at least one write, no synchronization.** Rust makes it a *type error* by combining shared-XOR-mutable with `Send`/`Sync`. Within a thread, aliasing XOR mutation already forbids a live `&mut` coexisting with any other access. Across threads, you can only get concurrent access to a `T` if `&T` is shareable — which requires `T: Sync`. Types that permit unsynchronized interior mutation (`Cell`, `RefCell`) are deliberately `!Sync`, so they simply **can't be shared across threads**; the only ways to share mutable state across threads are `Sync` types that synchronize (`Mutex`, `RwLock`, atomics). Therefore the "one writer, no sync" precondition is unconstructable in safe Rust — that's the whole proof. The honest caveat: this covers **data races** (a memory-safety property), not **race conditions / deadlocks** (logic properties) — you can still deadlock two `Mutex`es or write a logically-wrong concurrent algorithm; the compiler doesn't save you there.

## `unsafe` — what it does and doesn't guarantee

`unsafe` does exactly **one** thing: it lets you use five extra powers the checker can't verify — dereference a raw pointer, call an `unsafe` fn, access or modify a mutable `static`, implement an `unsafe` trait (`Send`/`Sync`), and access `union` fields. (`UnsafeCell` isn't a sixth power: it's the only type whose interior may be legally mutated through a shared reference — done by dereferencing the `*mut T` its safe `get()` returns, i.e. power #1.) It does **not** turn off the borrow checker, the type system, or lifetimes for ordinary code, and it does **not** mean "the code is dangerous" — it means **"the compiler trusts *you* to uphold the invariants it can't check."** The burden is on the author to guarantee no UB (no dangling/unaligned/aliasing-violating access, no data races, valid values for their type, upheld library invariants). The senior discipline: keep `unsafe` blocks **minimal and encapsulated behind a safe API whose invariants you document** (a `// SAFETY:` comment on every `unsafe` block stating why it's sound), so that *safe* callers cannot cause UB no matter what they do — that's the definition of a **sound** abstraction. An `unsafe` API that safe code can misuse into UB is **unsound**, a bug regardless of intent. Read the Rustonomicon before writing any. `miri` (nightly interpreter) catches many UB classes in tests — run it.

## "Why won't this compile?" — with the reasoning

**1. Returning a reference to a local.**
```rust
fn dangle() -> &'static str {
    let s = String::from("temp");
    &s                        // ERROR: `s` dropped at end of fn, reference would dangle
}
```
The lifetime of `&s` can't outlive `s`, which dies here. Fix: return the owned `String`, or take/return a borrow tied to an input lifetime.

**2. Mutate while a shared borrow is live.**
```rust
fn puzzle(v: &mut Vec<i32>) {
    let first = &v[0];        // shared borrow of v
    v.push(1);                // ERROR: cannot borrow `*v` as mutable while borrowed as immutable
    println!("{first}");      // `first` used here -> the borrow is still live (NLL)
}
```
Shared-XOR-mutable, and `push` may reallocate, invalidating `first`. This is the borrow checker preventing C++'s classic iterator-invalidation bug at compile time. Fix: copy the value (`let first = v[0];`) or reorder so the borrow ends first.

**3. The subtle closure-capture / `Send` trap.**
```rust
use std::rc::Rc; use std::thread;
let r = Rc::new(5);
thread::spawn(move || { let _keep = r; });   // ERROR: `Rc<i32>` cannot be sent between threads
```
The `move` closure captures `r`; `Rc` is `!Send`, so the closure is `!Send`, so `spawn` rejects it. The genuinely surprising sibling: change `let _keep = r;` to **`let _ = r;`** and it **compiles** — since edition 2021's disjoint closure captures (RFC 2229), `let _ = r` is not a *use* of `r`, so the closure captures nothing and is trivially `Send`. Naming this distinction is a strong senior signal. Fix for the real case: `Arc` instead of `Rc`.

**4. Move out of a borrow.** `fn take(v: &Vec<i32>) { let x = *v; }` fails: you only have a shared borrow, moving out would leave the borrowed source invalid. Fix: `.clone()`, or take `Vec<i32>` by value, or borrow the element.

## "Design a type / API" prompts

**Make illegal states unrepresentable.** Given "a percentage 0–100", don't take a `u8` and validate everywhere — build a newtype with a **smart constructor** so the invariant holds by construction and the type system carries the proof:
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Percent(u8);              // invariant: 0..=100, enforced in one place
impl Percent {
    pub fn new(v: u8) -> Option<Self> { (v <= 100).then_some(Percent(v)) }
    pub fn get(self) -> u8 { self.0 }
}
```
The trade: a little boilerplate and a wrapper at boundaries, in exchange for never re-validating downstream. Deviate only when the value truly has no invariant.

**Typestate: push state machines into the type system** so illegal transitions don't compile. Each state is a distinct type; transition methods **consume `self`** and return the next state, statically preventing "use after close" bugs:
```rust
use std::marker::PhantomData;
pub struct Door<S> { _s: PhantomData<S> }
pub struct Open; pub struct Closed;
impl Door<Closed> {
    pub fn new() -> Self { Door { _s: PhantomData } }
    pub fn open(self) -> Door<Open> { Door { _s: PhantomData } }   // Closed -> Open only
}
impl Door<Open> { pub fn close(self) -> Door<Closed> { Door { _s: PhantomData } } }
// door.close() on a Door<Closed> is a *compile* error, not a runtime check.
```
Cost: more types and turbofish noise; worth it for protocols where a misuse is expensive (network handshakes, builders that must be finalized, resource lifecycles). Related everyday API guidance (per the Rust API Guidelines): the **builder pattern** for many-optional-arg construction, accept `impl AsRef<Path>`/`impl IntoIterator` at boundaries for ergonomic inputs, return concrete types (not `impl Trait`) from public APIs when callers may need to name them, and derive the standard traits (`Debug`, `Clone`, `PartialEq`) eagerly since omitting them is a silent ergonomics tax on every user.

## Sources
- The Rust Programming Language (The Book) — https://doc.rust-lang.org/book/
- The Rustonomicon (unsafe, variance, layout) — https://doc.rust-lang.org/nomicon/
- Rust Reference (dyn compatibility, `repr`, coherence) — https://doc.rust-lang.org/reference/
- Rust API Guidelines — https://rust-lang.github.io/api-guidelines/
- Rust std docs (`std::cell`, `std::rc`, `std::sync`, `std::marker`, `std::future`, `std::pin`)
- Comprehensive Rust (Google) — https://google.github.io/comprehensive-rust/
- Microsoft Rust Training — https://microsoft.github.io/RustTraining/ ; *Why C/C++ Developers Need Rust* (use-after-move, iterator invalidation as compile errors) — https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch01-1-why-c-cpp-developers-need-rust.md
- Rust Performance Book (Nethercote) — https://nnethercote.github.io/perf-book/
- Tokio docs (async runtime model) — https://tokio.rs/tokio/tutorial
- RFC 2229 (disjoint closure captures), RFC 2094 (NLL)

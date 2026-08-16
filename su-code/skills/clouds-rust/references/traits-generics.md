# Traits & Generics

Judgment for designing trait-based APIs and choosing between static and dynamic dispatch in Rust (baseline: Rust 1.96, edition 2024). Complements the `rust-patterns` skill — that covers basic idioms; this covers the architectural decisions.

## The one decision that dominates: static vs dynamic dispatch

Almost every trait design question reduces to *how the call is resolved*. Get this right first; the rest follows.

**Static dispatch** (`fn f<T: Trait>(x: T)` or `impl Trait`): the compiler *monomorphizes* — it stamps out a separate copy of the function for each concrete `T`, resolves every method call at compile time, and can inline across the boundary. This is the mechanism behind "zero-cost abstraction": a generic `Iterator` chain compiles to the same code you'd write by hand with a `for` loop, because after monomorphization there is no trait, no indirection, nothing left to pay for at runtime.

**Dynamic dispatch** (`&dyn Trait`, `Box<dyn Trait>`): one copy of the function. The value is a *fat pointer* — two words: a data pointer and a pointer to the type's *vtable* (a static table of function pointers plus size/align/drop). Each call is an indirect jump through the vtable; the compiler cannot inline through it.

| Axis | Static (`<T: Trait>` / `impl Trait`) | Dynamic (`dyn Trait`) |
|---|---|---|
| Resolution | Compile time, inlinable | Runtime vtable indirection |
| Runtime cost | Zero (as if hand-written) | One indirect call, no inlining |
| Code size | One copy **per concrete type** — can bloat | One copy total |
| Compile time | Grows with instantiations | Cheaper |
| Heterogeneous collection | Impossible (`Vec<T>` is one `T`) | `Vec<Box<dyn Trait>>` — the point of `dyn` |
| Requires `dyn` compatibility | No | Yes (see below) |

**Default to static dispatch.** It is faster and keeps type information; the ecosystem is built around it. Reach for `dyn` when you have a concrete reason:

- **Heterogeneous collections.** You genuinely need `Vec<Box<dyn Widget>>` holding different concrete types. This is the flagship case — generics fundamentally cannot express it.
- **Binary size / compile time.** A generic function instantiated over dozens of types (or a large function body) duplicates that body every time. Converting an outer layer to `dyn` collapses it to one copy. This is real: it is why `std` erases some closures to `dyn`, and why proc-macro-heavy codebases sometimes `dyn`-ify to cut compile time.
- **Dynamic plugin boundaries.** Trait objects behind a stable ABI, runtime-loaded implementations.

The trade-off you accept with `dyn`: no inlining (usually negligible unless the call is in a hot inner loop), loss of the concrete type, and the trait must be *dyn compatible*.

**Dependency injection, Rust-style:** a generic parameter *is* the DI mechanism — `struct UserService<R: UserRepository> { repo: R }` injects the collaborator by constructor, monomorphizes to static dispatch (no container, no reflection, no registry), and is tested by substituting a mock `R`. Use `#[async_trait]` when the repository trait needs `async fn`s, and fall back to `Box<dyn Trait>` only when the concrete impl must be chosen at runtime.

## `dyn` compatibility (formerly "object safety")

> Terminology note: as of Rust 1.96 the compiler and docs say **"dyn compatible"**; older material and error text said **"object safe"**. Same concept. Error `E0038`.

A trait can back a `dyn` object only if the compiler can build a vtable that works without knowing the concrete type. The rules that bite in practice:

- **No generic methods.** `fn f<T>(&self, t: T)` would need infinitely many vtable slots — one per `T`. Not dyn compatible.
- **No `Self` by value or in return position** for the parts placed in the vtable (`fn clone(&self) -> Self` — the caller can't know the size of the returned `Self`). Hence `Clone` is not dyn compatible.
- **No associated constants**, and methods returning `impl Trait` (RPITIT) are not dispatchable via `dyn`.
- Methods that violate these can be *excluded* from the object with `where Self: Sized`, keeping the rest of the trait usable as `dyn`. `Iterator` does exactly this so `dyn Iterator` works while `map`/`collect` stay static.

The **why**: a vtable is a fixed-size, fixed-layout table decided once at compile time. Anything that would require per-call-site or per-`T` specialization can't live in it. When you hit `E0038`, the fix is usually to split the offending method behind `where Self: Sized`, or to redesign so the generic part happens before erasure.

```rust
trait Handler {
    fn handle(&self, req: &str) -> String; // dispatchable

    // Excluded from the vtable; only callable on concrete types.
    fn boxed(self) -> Box<dyn Handler>
    where
        Self: Sized + 'static,
    {
        Box::new(self)
    }
}
```

### Trait upcasting to a supertrait (stable 1.86)

When `trait Sub: Super`, a `&dyn Sub` coerces to `&dyn Super` — and likewise for any pointer: `Arc<dyn Sub>` → `Arc<dyn Super>`, `Box<dyn Sub>` → `Box<dyn Super>`. Stable since **1.86**.

```rust
trait Super { fn id(&self) -> u32; }
trait Sub: Super { fn extra(&self); }

pub fn widen(x: &dyn Sub) -> &dyn Super { x }   // upcast — a plain coercion since 1.86
```

**Mechanism:** the `Sub` vtable now carries a pointer to the `Super` vtable, so the coercion is a cheap pointer adjust, not a copy. **Why it matters:** before 1.86 you hand-wrote `fn as_super(&self) -> &dyn Super { self }` on the trait — boilerplate, and one method per pointer kind you cared to support. The highest-value use is `Any`: upcast `&dyn MyTrait` (where `MyTrait: Any`) to `&dyn Any` and call `downcast_ref`, with no `as_any()` method polluting your trait. **Caveat:** a *raw* pointer to a trait object now carries a non-trivial invariant — its vtable must be valid, and leaking a `*const dyn Trait` with an invalid vtable into safe code is UB (Miri enforces it); safe references are unaffected. **When to deviate:** nothing — it strictly replaces the old workaround; when your MSRV reaches 1.86, delete the manual `as_super` methods.

### Better trait-bound errors for library authors: `#[diagnostic::…]` (stable 1.85)

Two attributes let a library shape the compiler's error when a bound is unmet — pure diagnostics, zero runtime or semantic effect, ignored by compilers that don't know them. `#[diagnostic::on_unimplemented(message = "…", label = "…")]` on a trait customizes the "trait not implemented" text (point users at the real fix). `#[diagnostic::do_not_recommend]` on a blanket `impl<T: Foo> Bar for T {}` stops the compiler suggesting "implement `Foo`" when a user should implement `Bar` directly — the blanket impl becomes an implementation detail instead of a misleading red herring in every error. Reach for these on a *public* trait whose default message sends users down the wrong path; skip them on internal traits where the default is already clear.

## Associated types vs generic type parameters

The single most common trait-design mistake is reaching for a generic parameter when an associated type is correct (or vice versa). The rule is about *how many implementations per type* you want:

- **Associated type** (`type Item;`): **one implementation per implementing type**. The type is an *output* of the impl — chosen by the implementer, not the caller. `Iterator::Item`, `Deref::Target`, `Add::Output`. Callers write `T::Item`; there is exactly one.
- **Generic parameter** (`trait Convert<T>`): **many implementations per type**. The type is an *input* the caller picks. `From<T>` / `Into<T>` — a type can be `From<u8>` *and* `From<u16>`. `AsRef<T>` similarly.

```rust
// Associated type: a repository yields exactly ONE entity type.
trait Repository {
    type Entity;
    fn find(&self, id: u64) -> Option<Self::Entity>;
}

// Generic param: a type may be convertible to MANY targets.
trait Convert<T> {
    fn convert(&self) -> T;
}
```

**Why it matters:** associated types make callers' signatures cleaner (`fn sum<I: Iterator>(it: I) -> I::Item` — no second type param leaking everywhere) and let type inference nail down the output. Generic params buy flexibility at the cost of that inference — with `Convert<T>`, `x.convert()` is ambiguous and forces a type annotation or fully-qualified call syntax (`Convert::<u32>::convert(&x)`) — the turbofish cannot go on the method, since `T` belongs to the trait, not to `convert`. Choosing an associated type when you meant "many" paints you into a corner (you literally cannot write the second impl); choosing a generic param when you meant "one" pollutes every downstream signature with a redundant type parameter.

**When to deviate:** if even one type must have multiple impls, you *must* use a generic param — no judgment call. If it's genuinely one-per-type, prefer the associated type.

## `impl Trait`: argument vs return position

Two syntactically-similar features with opposite meanings.

**APIT — argument position** (`fn f(x: impl Trait)`): pure sugar for an anonymous generic parameter. `fn total(n: impl IntoIterator<Item = u32>)` ≡ `fn total<I: IntoIterator<Item = u32>>(n: I)`. The *caller* chooses the concrete type; static dispatch. Downside vs the explicit form: you lose the ability to name the type param with turbofish. Prefer APIT for readability when the param isn't referenced elsewhere in the signature.

**RPIT — return position** (`fn f() -> impl Trait`): "I return *some* concrete type implementing `Trait`, and I'm not telling you which." The *callee* picks; the caller gets an opaque type. This is how you return an unnameable closure or a complex iterator chain without boxing:

```rust
// Returns a concrete iterator; no Box, no dyn, fully static and inlinable.
fn evens(limit: u32) -> impl Iterator<Item = u32> {
    (0..limit).filter(|n| n % 2 == 0)
}
```

The **why**: before RPIT you either wrote out a monstrous nested iterator type or paid for `Box<dyn Iterator>`. RPIT gives the zero-cost static version with a readable signature. The **trade-off**: the return type is a single hidden concrete type — you cannot return `impl Iterator` from two branches with *different* iterator types (that needs `Box<dyn>` or an enum). RPIT also auto-captures all in-scope generic params and lifetimes in edition 2024 (the older "leaked lifetime" foot-guns are gone; use `+ use<>` to opt out of capturing).

**RPITIT — RPIT in trait methods** (stable since **1.75**): `fn names(&self) -> impl Iterator<Item = String>` *inside a trait*. Before 1.75 this required the `async-trait` crate or an associated type + named type. Now it's native.

```rust
trait Directory {
    fn names(&self) -> impl Iterator<Item = String>; // stable 1.75+
}
```

The catch: a trait method returning `impl Trait` is **not dyn compatible** — you can't call it through `dyn Directory`, because the return type varies per implementer and can't sit in a vtable. If you need both trait-object support and an iterator return, fall back to `Box<dyn Iterator>` in the signature. Note `async fn` in traits is RPITIT under the hood (`async fn` desugars to `-> impl Future`), so the same dyn-compatibility limitation applies to native async traits.

Two further teeth on *native* async traits: RPITIT `async fn` adds no `Send` bound, so a future holding an `Rc` silently becomes `!Send` and fails only at `tokio::spawn` — never at the trait definition. Reach for the `trait_variant` crate's `make` macro to generate a `Send`-bounded variant (still static dispatch only), or drop to a manual `Pin<Box<dyn Future + Send>>` / the `async-trait` crate when you genuinely need `dyn`.

## Coherence and the orphan rule

Rust enforces **coherence**: for any (trait, type) pair there is *at most one* impl in the entire program. The **orphan rule** is how it guarantees this across separately-compiled crates: `impl Trait for Type` is allowed only if *your crate owns the trait or owns the type* (more precisely, a local type appears before any type parameter in the impl).

**Why it exists — this is the part to internalize:** without it, crate A could `impl Display for Vec<T>` one way, crate B another way, and a binary depending on both would have two conflicting impls with no principled way to pick. Method resolution would depend on link order. Coherence makes trait dispatch a global, deterministic property, which is what lets `x.method()` resolve unambiguously and lets the compiler reason about it. You give up the freedom to bolt any trait onto any type; you get a language where trait resolution is never ambiguous.

**The escape hatch — the newtype pattern.** When you must implement a foreign trait for a foreign type, wrap the foreign type in a local single-field struct. Now *you* own the wrapper, so the orphan rule is satisfied:

```rust
use std::fmt;

// We own Wrapper, so we may impl the foreign Display for it,
// even though Vec<String> is foreign.
struct Wrapper(Vec<String>);

impl fmt::Display for Wrapper {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}]", self.0.join(", "))
    }
}
```

The newtype cost is ergonomic: you must forward the methods you still want (or impl `Deref` — but `Deref`-for-abstraction is discouraged by the API guidelines; use it only for genuine smart pointers). The benefit beyond coherence: newtypes also add *type safety* (a `UserId(u64)` won't be confused with an `OrderId(u64)`) and let you attach invariants. A single-field newtype imposes no runtime cost — the wrapper is optimized away. Note that layout/ABI identity with the inner type is only *guaranteed* under `#[repr(transparent)]`; the default `repr(Rust)` makes no layout promises, which matters if the newtype crosses an FFI boundary.

## Blanket impls, default methods, supertraits, marker traits

**Blanket impls** — `impl<T: A> B for T` — implement a trait for *every* type satisfying a bound. This is how `Into` comes free from `From` (`impl<T, U: From<T>> Into<U> for T`), and how extension traits work. Power tool with a sharp edge: a blanket impl interacts with coherence globally, so adding one to a published crate can be a **breaking change** (it may collide with downstream impls). Design blanket impls deliberately, not casually.
Worse, a blanket impl is effectively irreversible: once it covers a type you can *never* add a more specific impl for that type (coherence forbids the overlap and there is no specialization on stable), so treat every blanket impl as a permanent API commitment and design its bound conservatively — widening it or carving out exceptions later is a breaking change you cannot make.

```rust
// Every Debug type gains a log line for free.
trait Loggable {
    fn log_line(&self) -> String;
}
impl<T: std::fmt::Debug> Loggable for T {
    fn log_line(&self) -> String {
        format!("{self:?}")
    }
}
```

**Default methods** let a trait ship behavior implementers can override, keeping the *required* surface minimal. `Iterator` requires only `next`; the 70+ adapters are defaults. The judgment: put the *irreducible* operations in required methods, everything derivable in defaults — implementers write the minimum, callers get the maximum.

**Supertraits** — `trait Summary: Display` — require that any `Summary` implementer also implement `Display`, so default methods can rely on it. It's a *requires* relationship, not inheritance; there's no subtyping. Use it when your trait's methods genuinely need another trait's capabilities.

```rust
trait Summary: std::fmt::Display {
    fn summary(&self) -> String {
        format!("summary: {self}") // relies on the Display supertrait
    }
}
```

**Capability mixins** compose these three tools: model each dependency as a small "ingredient" trait (`HasSpi`, `HasI2c`), give a behavior trait those as supertrait bounds (`trait FanDiag: HasSpi + HasI2c`), then a blanket `impl<T: HasSpi + HasI2c> FanDiag for T {}` grants the behavior to any type declaring the ingredients. Capabilities compose at compile time with no inheritance hierarchy — the diagnostic methods vanish the moment an ingredient impl is removed, and swapping a real bus for a mock makes all mixin logic testable for free.

**Marker traits** carry no methods; they encode a *property* the compiler or generic bounds can check: `Send`, `Sync`, `Copy`, `Sized`. Their whole value is being a bound (`T: Send`). `Send`/`Sync` are additionally *auto traits* — implemented automatically when all fields qualify — which is why thread-safety composes without boilerplate.

## `Sized` and `?Sized`

Every generic type parameter has an *implicit* `T: Sized` bound — the compiler needs a compile-time size to pass by value and lay out stack frames. Dynamically-sized types (DSTs) — `str`, `[T]`, `dyn Trait` — have no statically-known size and exist only behind a pointer (`&str`, `Box<dyn Trait>`).

`T: ?Sized` *relaxes* that implicit bound to accept DSTs. The idiom: use it when your function only touches `T` **behind a reference**, so the size never needs to be known:

```rust
// Accepts &str, &String, &dyn Display — the ref means size is irrelevant.
fn print_ref<T: std::fmt::Display + ?Sized>(x: &T) {
    let _ = format!("{x}");
}
```

**When to deviate / anti-pattern:** don't cargo-cult `?Sized` onto every generic. Add it only when you have a concrete reason to accept unsized types (usually to accept both `&str` and `&String`, or to be generic over `dyn`). If your function ever needs `T` by value, `?Sized` is wrong and won't compile anyway. The brief flags gratuitous `?Sized` as a smell — earn it.

## Generic bounds and `where` clauses

Inline bounds (`fn f<T: Clone + Debug>()`) and `where` clauses are equivalent for simple cases; `where` wins when bounds get complex, involve associated types (`where T::Item: Ord`), or apply to types other than the generic params (`where Vec<T>: Clone`). Prefer `where` past ~two bounds — it keeps the signature line readable and puts the constraints in one scannable block. This is style, but consistent style is a real maintainability win in trait-heavy code.

**The deeper judgment: bound placement.** Put bounds where the capability is *used*, not reflexively on the type definition. Bounding a `struct` (`struct Cache<T: Hash>`) forces the bound onto every impl and every user even those that don't hash — the API guidelines advise against it. Bound the *methods/impls* that need it instead. This keeps the type usable in more contexts and is easier to relax later.

## Generic Associated Types (GATs)

Stable since **1.65**. A GAT is an associated type that is itself generic — typically over a lifetime. The flagship use is the "lending iterator": an iterator whose items borrow from the iterator itself, which `Iterator` cannot express because `Item` can't mention a per-call lifetime.

```rust
trait Lending {
    type Item<'a>
    where
        Self: 'a;
    fn first(&self) -> Option<Self::Item<'_>>;
}

struct Buffer(Vec<u8>);
impl Lending for Buffer {
    type Item<'a> = &'a u8;
    fn first(&self) -> Option<Self::Item<'_>> {
        self.0.first()
    }
}
```

**When they earn their keep:** GATs are advanced and add real cognitive cost to an API. Use them only for genuine lending/streaming abstractions, or when a `type Assoc<T>` truly parameterizes over a caller-chosen type. **When to deviate:** if you can express the design with a plain associated type or a generic parameter, do that instead — GATs are the last resort, not the default. Most application code never needs them; they show up in library infrastructure (async runtimes, parser combinators, zero-copy deserializers).

## Sealed traits

A **sealed trait** can be *called* by downstream crates but never *implemented* by them. You seal by making the trait require a private supertrait that only your crate can satisfy:

```rust
mod sealed {
    pub trait Sealed {}
}

pub trait Codec: sealed::Sealed {
    fn encode(&self) -> Vec<u8>;
}

pub struct Json;
impl sealed::Sealed for Json {}
impl Codec for Json {
    fn encode(&self) -> Vec<u8> {
        br#"{}"#.to_vec()
    }
}
```

**Why:** it turns "add a method to this trait" from a *breaking change* into a *non-breaking* one, because you control every impl. Without sealing, adding a required method breaks all downstream implementers. It also lets a trait act as a closed, exhaustive set of types you enumerate. **Trade-off:** you deny users extensibility — a real cost if the trait is meant to be an extension point. Seal traits that are implementation details or closed enums-of-behavior; leave genuine extension points open. The standard library seals many traits (e.g. `std::slice::SliceIndex` conceptually) for exactly this reason.
Sealing is also a *soundness* tool: when correctness rests on every impl behaving (e.g. a command trait whose `parse_response` must return the right associated type), sealing closes the loophole of a broken or malicious external impl — outsiders can call the trait but never implement it. Reserve it for cases where you own the canonical impl set and invariants matter; do not seal capability-marker traits or anything third-party plugins are meant to extend.

## Extension traits

Add methods to a type you don't own by declaring a local trait and impl'ing it (often via a blanket impl). Convention: name it `SomethingExt`. This is the sanctioned, coherence-respecting alternative to "monkey-patching."

```rust
pub trait IterExt: Iterator {
    fn second(mut self) -> Option<Self::Item>
    where
        Self: Sized,
    {
        self.nth(1)
    }
}
impl<I: Iterator> IterExt for I {} // blanket: every iterator gets `.second()`
```

**Why:** callers get fluent `.second()` syntax on foreign types after a single `use`. **Trade-off:** the method is invisible until the trait is imported (a discoverability cost, and occasionally a surprising one in error messages), and — like all blanket impls — publishing one constrains what you can add later. Use it for genuinely reusable convenience; don't scatter one-off ext traits that a free function would serve better.

## Zero-cost abstraction: the WHY behind monomorphization

"Zero-cost abstraction" means: *the abstraction compiles away — you don't pay at runtime for expressiveness you used at compile time, and you couldn't hand-write it faster.* Monomorphization is the mechanism: because each generic instantiation is specialized to concrete types with everything inlinable, a `.iter().map(f).filter(g).sum()` chain optimizes to the same machine code as the equivalent hand-rolled loop. There is no boxing, no vtable, no dynamic type at runtime.

**The bill you do pay is at compile time and in binary size.** Every distinct instantiation duplicates the function body. A large generic function used with 20 types produces 20 copies; this inflates the binary and lengthens compile times (a top contributor per the Rust Performance Book). Mitigations when it bites: (1) keep the generic *shell* thin and delegate the bulk to a single non-generic inner function (the "outlining" trick — the monomorphized wrapper just coerces types and calls the shared body); (2) convert an appropriate layer to `dyn` to collapse copies; (3) reduce the number of distinct instantiations. This is precisely the static-vs-dynamic trade-off from the top of this file, now seen from the code-size side: static dispatch trades binary size and compile time for runtime speed, and that trade is usually correct — but not always.

## Sources

- The Rust Programming Language — Generic Types, Traits, Advanced Traits, Trait Objects: https://doc.rust-lang.org/book/
- The Rust Reference — trait/impl coherence, dyn compatibility, `Sized`: https://doc.rust-lang.org/reference/
- Rust API Guidelines — bounds on impls not types, newtypes, sealed traits: https://rust-lang.github.io/api-guidelines/
- The Rust Performance Book — monomorphization / compile-time & binary-size costs: https://nnethercote.github.io/perf-book/
- Comprehensive Rust (Google) — generics, trait objects, GATs: https://google.github.io/comprehensive-rust/
- Rust 1.65 (GATs) and 1.75 (RPITIT / async fn in traits) release notes: https://blog.rust-lang.org/
- Rust 1.86 release notes — trait upcasting to supertraits; Rust 1.85 — `#[diagnostic::do_not_recommend]`/`on_unimplemented` (RFC 2397): https://blog.rust-lang.org/2025/04/03/Rust-1.86.0/ , https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/
- Microsoft RustTraining — *Common C# Patterns in Rust* (DI via generic parameters): https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch15-migration-patterns-and-case-studies.md
- Microsoft RustTraining — *Async Book* Ch 10, Async Traits (RPITIT `Send`/`dyn` limits, `trait_variant`): https://github.com/microsoft/RustTraining/blob/main/async-book/src/ch10-async-traits.md
- Microsoft RustTraining — *Rust Patterns Book* Ch 2, Traits In Depth (associated type vs generic param, blanket-impl irreversibility): https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch02-traits-in-depth.md
- Microsoft RustTraining — *Type-Driven Correctness Book* Ch 11, Fourteen Tricks (Trick 2 — Sealed Traits for soundness): https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch11-fourteen-tricks-from-the-trenches.md
- Microsoft RustTraining — *Type-Driven Correctness Book* Ch 8, Capability Mixins — Compile-Time Hardware Contracts: https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch08-capability-mixins-compile-time-hardware-.md

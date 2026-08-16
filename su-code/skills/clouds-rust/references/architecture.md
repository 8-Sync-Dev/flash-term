# Project Architecture & Cargo Workspaces

How to structure a Rust codebase so the compiler keeps it correct as it grows — module layout, crate/workspace boundaries, dependency inversion without a DI framework, and type-driven design that encodes architecture in the type system. Baseline: **Rust 1.96, edition 2024**. Judgment over syntax; the Rust Book covers the how.

## Module organization

Rust's module tree is decoupled from the file system except by convention. `mod foo;` loads `foo.rs` **or** `foo/mod.rs` — the compiler accepts either. The 2018+ convention is **file-per-module without `mod.rs`**: a module `net` with submodules lives as `net.rs` (declaring `mod http;`) plus `net/http.rs`. The older `net/mod.rs` style still compiles and is not deprecated, but avoid mixing the two in one crate — a directory with both `net.rs` and `net/mod.rs` is a hard error, and a codebase that mixes conventions makes "where is this module defined?" a guessing game. Deviate toward `mod.rs` only when a module is a large self-contained subsystem whose directory you want to be openable as a unit; even then, prefer `net.rs` next to `net/` for discoverability.

**`extern crate` is historical.** Edition 2018+ resolves external crates by name automatically; `extern crate foo;` is only needed for `#[macro_use]` on a few legacy macro crates and for linking non-Cargo `no_std` sysroot crates. In application code, never write it.

### Visibility discipline — the real architectural lever

Visibility is how you make illegal architecture *unrepresentable* rather than merely discouraged. The default (private to the defining module) is correct far more often than people write it. Reach for the narrowest that compiles:

| Modifier | Reachable from | Use when |
|---|---|---|
| (none) | this module + descendants | default; the item is an implementation detail |
| `pub(super)` | parent module | a sibling-facing helper, not a crate-wide one |
| `pub(crate)` | anywhere in this crate | shared internally, must NOT be in the public API |
| `pub(in path)` | a named ancestor subtree | rare; a helper scoped to one subsystem |
| `pub` | downstream crates | genuine public API — a stability commitment |

The distinction that matters most is **`pub(crate)` vs `pub`**. `pub` is a semver promise: once published, removing or changing it breaks downstream crates. `pub(crate)` costs nothing to change. A field or function that is `pub` only because "the test in another module needs it" should be `pub(crate)`, or the test should move. Over-exposing internals is the single most common way Rust APIs ossify — every `pub` you didn't need is a future breaking change you can't make.

A subtle trap: a `pub` item that names a non-`pub` type in its signature is a "private-in-public" leak. Modern rustc warns (`private_interfaces`); the fix is to make the referenced type at least as visible as the item, or to stop exposing it.

### Re-exports and the facade

`pub use` decouples your *public path* from your *internal layout*. Organize modules for the author (cohesion, short files), then present a flat, curated surface to callers:

```rust
// Facade via pub use: internal layout free to change, public path stable.
mod parser {
    pub struct Ast;
    pub fn parse(_s: &str) -> Ast { Ast }
}
mod eval {
    use crate::parser::Ast;
    pub fn run(_a: &Ast) -> i64 { 0 }
}

// Public surface: callers see `crate::parse`/`crate::run`, not the module tree.
pub use parser::{parse, Ast};
pub use eval::run;

// `pub(crate)` keeps a helper reachable across modules but out of the public API.
pub(crate) fn intern(s: &str) -> String { s.to_owned() }
```

*Why:* callers write `use mycrate::Ast`, not `use mycrate::parser::ast::Ast`; you can later split `parser` into three modules without breaking anyone. *Trade-off:* a re-export is itself public API — `pub use` a foreign type and you've committed to that dependency's type in your semver contract (`C-STABLE`: your public API's stability is only as strong as the crates it re-exports). *When to deviate:* don't build a facade for a crate with three functions; the indirection buys nothing until the module tree is deep enough to leak.

## Crate splitting: when it pays and what it costs

A crate is Rust's unit of **compilation**, **privacy**, and **versioning** — not merely of organization. Splitting a crate is a heavier decision than splitting a module, and the reasons are specific:

- **Compile-time parallelism.** Cargo compiles crates in parallel and caches them per-crate; a change confined to crate A recompiles A and everything downstream of A, but leaves crates that don't depend on A untouched and lets independent crates build in parallel. (Cargo has no interface-level freshness — B rebuilds whenever A is recompiled at all, even for a private-body or comment-only edit.) Splitting a monolith along a stable interface line is the most effective way to cut incremental rebuild time on a large codebase. This is often the strongest practical reason.
- **A real API boundary.** A crate boundary is the only place `pub(crate)` stops things. If you want a genuinely enforced "these internals are unreachable," it must be a separate crate.
- **Reuse / publication.** Anything you'll publish to crates.io or share across repos is a crate.
- **Dependency isolation.** A crate that pulls a heavy or risky dependency (say, a C-FFI codec) can quarantine it so the rest of the workspace and its consumers don't inherit it, and so a feature can gate the whole crate out.

**The cost is real.** Each crate boundary blocks cross-crate inlining of non-generic functions unless the callee is `#[inline]` or LTO is on — generic functions are monomorphized in the caller's crate and inline across the boundary regardless. Hot paths across a boundary can regress. Coordinated changes now span multiple `Cargo.toml`s and version bumps. Orphan rules bite: you cannot `impl ForeignTrait for ForeignType`, so splitting types and the traits over them into different crates can strand you (newtype-wrap to escape). And too-fine splitting produces a swamp of one-file crates whose coordination overhead dwarfs the compile-time win.

**Heuristic:** split when (a) rebuilds hurt and there's a stable interface to split along, (b) you need a hard privacy boundary, or (c) you're isolating a dependency or enabling reuse. Do *not* split just to "keep files small" — that's what modules are for.

## Cargo workspaces

A workspace is multiple crates sharing one `Cargo.lock` and one `target/` directory. That shared lockfile is the point: every member resolves a given dependency requirement to the **same version**, so members never drift against each other — though semver-incompatible copies pulled in transitively can still coexist in one binary (see `cargo tree -d`). And `cargo build`/`test` at the root builds/tests the whole graph coherently.

### Version unification with `[workspace.dependencies]`

Declare shared versions once at the workspace root and inherit them:

```toml
# workspace root Cargo.toml  (illustrative)
[workspace]
members = ["crates/*"]
resolver = "3"                       # edition-2024 default resolver

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
domain = { path = "crates/domain" }  # internal path dep

# a member Cargo.toml
[dependencies]
serde = { workspace = true }
domain = { workspace = true }
```

*Why:* one edit bumps a dependency everywhere; drift between members (crate A on `serde 1.0.150`, crate B on `1.0.200`) becomes impossible to express. Package fields inherit too — `version.workspace = true`, `edition.workspace = true`, `license.workspace = true` under `[workspace.package]` — so a release bumps one number. *Trade-off:* inheritance centralizes control; a member that genuinely needs a *different* version of a dep must opt out by specifying it directly, which is a smell worth a second look. *When to deviate:* a single-crate project doesn't need a workspace; add one the moment you have a second crate or want the shared lockfile/target cache.

`resolver = "3"` (the edition-2024 default) is the MSRV-aware resolver: it prefers dependency versions compatible with your declared `rust-version`. Set it at the workspace level — a workspace ignores a member's `resolver` field.

### Feature unification — the workspace hazard

Cargo unifies features **per dependency across everything built in one invocation**. If crate A enables `tokio/full` and crate B depends on `tokio` with no features, a workspace-wide `cargo build` compiles `tokio` **once, with `full`** — so B silently gets features it never asked for. This hides accidental coupling: B compiles in the workspace but fails when built standalone.

Consequences a senior dev plans for:
- **Features are additive and must stay so.** If enabling a feature *removes* or changes behavior, unification will break a sibling. Never make features mutually exclusive; model exclusivity as separate crates or a runtime enum.
- **Verify crates build in isolation**, not only from the workspace root, if they're published independently — `cargo build -p mycrate` from a clean checkout, or CI that builds each package alone.
- **`resolver = "2"`/`"3"` narrows** the old unification: it stops unifying build-deps/proc-macros and target-specific/`dev` features into normal builds. This is why edition 2024 defaults to `"3"` — but cross-member unification of *normal* deps still happens by design.

## Layered / hexagonal architecture without a DI framework

Rust does dependency inversion with **traits as ports** and **generics or trait objects as the injection mechanism** — there is no Spring, no container, no reflection. The domain crate defines the trait it needs; outer layers implement it; the wiring is ordinary constructor parameters.

```rust
// Hexagonal: the domain defines the port (trait); adapters implement it.
// Dependency inversion with zero DI framework — just generics + trait bounds.

// --- domain crate: depends on nothing external ---
pub struct Order { pub id: u64, pub total: u64 }

pub trait OrderRepo {
    type Error;
    fn save(&mut self, order: &Order) -> Result<(), Self::Error>;
}

// Domain logic is generic over the port, not over a concrete DB.
pub fn place_order<R: OrderRepo>(repo: &mut R, id: u64, total: u64) -> Result<(), R::Error> {
    repo.save(&Order { id, total })
}

// --- adapter (would live in an outer crate) ---
#[derive(Default)]
pub struct InMemory { pub saved: Vec<u64> }
impl OrderRepo for InMemory {
    type Error = std::convert::Infallible;
    fn save(&mut self, order: &Order) -> Result<(), Self::Error> {
        self.saved.push(order.id);
        Ok(())
    }
}
```

The load-bearing rule: **the domain crate's `Cargo.toml` has no infrastructure dependencies** — no `sqlx`, no `reqwest`, no `tokio`. It defines traits; the `postgres-adapter` crate implements them and depends on both `domain` and `sqlx`. The dependency arrow points inward (adapters → domain), which is exactly the inversion. The compiler enforces it: if `domain` doesn't depend on `sqlx`, a domain type physically cannot mention a `sqlx` type.

**Static (`<R: OrderRepo>`) vs dynamic (`&mut dyn OrderRepo`) dispatch** is the key trade-off. Generics monomorphize — zero-cost calls, full inlining, but code bloat and each concrete type is a distinct instantiation. `dyn` gives one shared code path and lets you store heterogeneous implementations behind one type (a `Vec<Box<dyn Port>>`), at the cost of a vtable indirection and the object-safety restrictions (no generic methods, no `Self`-returning methods, associated types must be pinned via `dyn Trait<Item = T>`). Note the example uses an **associated type** `Error`, which is *not* object-safe unless bound — a real port aimed at `dyn` usage should use a fixed error type. Default to generics for a small fixed set of adapters; switch to `dyn` when you need runtime-swappable or plugin-style implementations, or when monomorphization bloat measurably hurts compile time.

*When to deviate:* full hexagonal layering is overhead a CLI tool or a 2000-line service doesn't need. Introduce the port trait when you have a *second* implementation (or a test double you can't otherwise build) — inventing the abstraction before the second implementor is speculative generality. The trait exists to serve the test and the swap, not for its own sake.

**Wire context in, don't store back-pointers.** Porting a framework, the C++ reflex is to store a `Framework*` in every component; the Rust equivalent — a back-pointer with no lifetime guarantee — fights the borrow checker. Pass the shared state as a lifetime-bounded parameter instead (`fn execute(&mut self, ctx: &mut DiagContext<'a>)`): a `&'a mut EventLogManager` inside a borrowed context makes the compiler *prove* the framework outlives every call. Its corollary attacks the god object — a struct with 30+ flat fields is "three or four structs wearing a trenchcoat." Decompose into focused state structs (`HealthMonitorState`, `GpuDiagState`) so each function borrows only the sub-state it touches and becomes unit-testable in isolation.

### Async at the edges, sync at the core

Treat async as an optimization applied at the outermost I/O boundary, not an architecture that pervades every layer. Structure a service as a **sync core, async shell**: a pure sync core (validate, price, decide) that takes I/O *results* as arguments, wrapped by a thin async shell that sequences fetch → decide → fetch → decide. The test for whether a function earns its `async`: if deleting the keyword would force you to replace it with threads/channels/manual polling, it earns its keep; if deletion requires no other change, it was never async. *Payoff:* business rules unit-test without a runtime or mocks, logic errors stay separate from I/O errors, and the core is reusable from CLI/WASM/batch.

Libraries follow the same rule outward: **default to sync APIs and depend on `futures`, never on `tokio` directly.** A sync library is callable from both sync and async callers (the async caller owns the `spawn_blocking` boundary decision); an async library forces *every* caller into a runtime and pushes sync callers into `Runtime::block_on`, which is fragile and panics if already inside a runtime. If the library must do I/O, ship a sync core with an optional async layer behind a feature flag — let the caller own the coloring decision, which keeps the ecosystem composable.

## Binary + library split

Put **all logic in `lib.rs`** and keep `main.rs` a thin shell that parses args, builds config, and calls one library entry point. A `src/main.rs` + `src/lib.rs` in the same package gives you both a binary and a library named after the package.

```rust
// src/main.rs — thin, untested, hard to unit-test anyway.
fn main() -> std::process::ExitCode {
    match mycrate::run(std::env::args().skip(1).collect()) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => { eprintln!("error: {e}"); std::process::ExitCode::FAILURE }
    }
}
```

*Why:* `main` cannot be called from an integration test in `tests/`, and `#[test]` fns can't easily exercise a binary. Everything reachable only through `main` is untestable and undocumentable. A binary that is a five-line delegation to `lib::run` moves 100% of the logic into the testable, documentable library. *Trade-off:* essentially none for anything past a toy — the one real cost is you now think about your CLI's public API surface, which is a feature. *When to deviate:* a genuinely trivial script (a build helper) can stay in `main.rs`; the moment you want a test for its behavior, split.

## Managing the dependency graph

`cargo tree` is the primary tool. `cargo tree -d` (duplicates) is the one to run habitually — it lists every crate compiled at **two or more semver-incompatible versions** (e.g. `rand 0.7` and `rand 0.8`). Duplicates are not always wrong (two majors *are* different crates), but each one inflates compile time and binary size, and duplicated *types* cause the maddening "expected `X`, found `X`" error where the two `X`s come from different versions.

Tactics, in order of preference:
1. **`cargo update -p dup@old --precise new`** to pull a straggler onto a version the rest already uses, when semver allows.
2. **File/patch upstream** so a transitive dep widens its version requirement.
3. **`[patch]`** a git or path override as a temporary bridge.
4. Accept the duplicate when it's a real major-version split you can't unify — but document why.

`cargo tree -i <crate>` (inverse) answers "who pulled this in?", the fastest way to hunt down an unexpected or heavyweight transitive dependency before deciding whether to cut the direct dep that dragged it in. Combine with `--edges features` to see *which feature* activated a subtree — often the way you discover an accidental `default-features = true` bloating the build. Prefer `default-features = false` plus an explicit feature list for heavy deps; it's the difference between pulling in `tokio`'s full runtime and just what you use.

## Type-driven design: make the compiler enforce architecture

The highest-leverage architectural move in Rust is pushing invariants into types so violations don't compile. Gate the investment on one question — *if this bug ships, how bad is it?* Reserve typestate and capability-token machinery for catastrophic-if-missed boundaries (power sequencing, crypto, cross-module public APIs, state machines with 3+ states); for an invariant local to one 50-line function a plain `assert!` is correct and the type-level encoding is net-negative. Types eliminate whole bug *categories*, tests cover specific *values* — they are complements, not substitutes, and knowing when to stop is part of the skill. Three tools:

**Newtypes** wrap a primitive to give it identity and a validated constructor:

```rust
// Newtype makes the compiler enforce a domain invariant at boundaries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserId(u64);

impl UserId {
    // The only constructor: validation lives here, so an invalid UserId cannot exist.
    pub fn new(raw: u64) -> Option<Self> {
        (raw != 0).then_some(UserId(raw))
    }
    pub fn get(&self) -> u64 { self.0 }
}

// Distinct type => cannot pass an OrderId where a UserId is required.
pub fn load(_id: UserId) {}
```

*Why:* "parse, don't validate" — once you hold a `UserId`, its invariant is proven by construction and never re-checked downstream. A function taking `UserId` cannot receive a raw `u64` or a `ProductId` by mistake. *Trade-off:* boilerplate (`.get()`/`.0`, `From` impls, trait forwarding); a private field plus deliberate accessors is the point, but it's friction. *When to deviate:* don't newtype a value that's genuinely just a number with no invariant and no confusability — a loop counter is a `u64`.

**Typestate** encodes a state machine in generic parameters so invalid transitions are compile errors:

```rust
use std::marker::PhantomData;
// Typestate: illegal transitions are compile errors, not runtime checks.
pub struct Open;
pub struct Closed;

pub struct Door<S> { _s: PhantomData<S> }

impl Door<Closed> {
    pub fn new() -> Self { Door { _s: PhantomData } }
    pub fn open(self) -> Door<Open> { Door { _s: PhantomData } }
}
impl Door<Open> {
    pub fn close(self) -> Door<Closed> { Door { _s: PhantomData } }
}
// There is no `close` on Door<Closed>: double-close won't compile.
```

*Why:* the classic use is a builder or protocol where "you called `.send()` before `.connect()`" should be impossible, not a runtime panic. Transitions consume `self`, so the stale state can't be reused. *Trade-off:* the type signatures leak into callers and error messages get denser; it's overkill for a two-state flag better served by an enum. *When to deviate:* use a runtime enum + `match` when states are data-carrying and dynamic, or when you must store a collection of objects in mixed states.

**Sealed traits** let you expose a trait for use but forbid downstream implementation:

```rust
// Sealed trait: implementable inside this crate, closed to downstream crates.
// Lets you add methods later without a breaking change.
mod sealed { pub trait Sealed {} }

pub trait Storage: sealed::Sealed {
    fn get(&self, k: &str) -> Option<String>;
}

pub struct Memory;
impl sealed::Sealed for Memory {}
impl Storage for Memory {
    fn get(&self, _k: &str) -> Option<String> { None }
}
```

*Why:* because no outside crate can name `sealed::Sealed`, none can implement `Storage`. You can then add a method to `Storage` later without breaking anyone — normally a breaking change, because it would invalidate downstream impls that don't exist. Use it for traits meant to be *called*, not *implemented*, by users. *Trade-off:* you remove an extension point; users who legitimately want to implement your trait are blocked. *When to deviate:* leave a trait open when downstream implementation is the intended usage (a `Serialize`-like extension trait).

## API design principles (Rust API Guidelines)

The [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) encode the conventions that make a crate feel native. The ones with the most leverage:

- **`C-COMMON-TRAITS`:** eagerly derive `Debug`, `Clone`, `PartialEq`, `Eq`, `Hash`, and where sensible `Default`, `PartialOrd`/`Ord`. *Why:* omitting `Debug` on a public type means a caller can't put it in an `assert_eq!` or `dbg!`, and adding a derive later is fine but the absence bites immediately. `Copy` is the exception — it's a semver-meaningful promise the type is cheap and address-independent; derive it deliberately, not reflexively.
- **`C-SEND-SYNC`:** public types should be `Send + Sync` unless there's a reason not to; these are auto-traits, so you get them for free until an `Rc` or a raw pointer silently removes them. A type that's accidentally `!Send` can't cross a thread boundary and will surface as a baffling error deep in a caller's async code. If a type is intentionally not `Send`, say so in the docs.
- **Naming (`C-CONV`, `C-GETTER`):** `as_` = cheap borrowed reference conversion, `to_` = expensive/owned conversion, `into_` = owning consuming conversion. Getters are `fn field(&self)`, not `fn get_field()`. These prefixes are load-bearing: a reviewer reads cost and ownership straight off the name.
- **Conversions via `From`/`TryFrom`:** implement `From` for infallible conversions (you get `Into` free) and `TryFrom` for fallible ones — never a bespoke `fn to_x() -> Result<...>` where the trait fits, because generic code and `?` rely on the traits.
- **Builders (`C-BUILDER`)** for types with many optional fields or where construction is non-trivial:

```rust
// Builder for optional/config-heavy construction; consumes self, returns owned.
#[derive(Debug)]
pub struct Client { url: String, timeout: u64, retries: u32 }

pub struct ClientBuilder { url: String, timeout: u64, retries: u32 }

impl Client {
    pub fn builder(url: impl Into<String>) -> ClientBuilder {
        ClientBuilder { url: url.into(), timeout: 30, retries: 0 }
    }
}
impl ClientBuilder {
    pub fn timeout(mut self, s: u64) -> Self { self.timeout = s; self }
    pub fn retries(mut self, n: u32) -> Self { self.retries = n; self }
    pub fn build(self) -> Client {
        Client { url: self.url, timeout: self.timeout, retries: self.retries }
    }
}

// Fallible conversion via TryFrom instead of a panicking parse.
pub struct Port(u16);
impl TryFrom<i64> for Port {
    type Error = &'static str;
    fn try_from(v: i64) -> Result<Self, Self::Error> {
        u16::try_from(v).map(Port).map_err(|_| "port out of range")
    }
}
```

*Why the owning `mut self` builder:* it chains fluently and produces an owned `Client` with no lifetime entanglement; `impl Into<String>` lets callers pass `&str` or `String`. *Trade-off:* a builder is more code than a struct literal and defers "did I set the required fields?" — pure-owning builders can't statically require a field (typestate can, at more cost). *When to deviate:* a struct with two obvious fields wants a plain constructor or `Default` + struct-update syntax, not a builder.

**Argument types (`C-GENERIC`):** be liberal in what you accept, precise in what you return. Match the bound to intent: `impl Into<String>` when the fn will *own/store* the value (convert once inside), `impl AsRef<str>`/`AsRef<Path>` when it only *reads*, and `Cow<'_, T>` when it usually reads but occasionally must mutate (borrow on the fast path, allocate only on transform). One trap: lookup keys bound on `Borrow<Q>`, *not* `AsRef` — `HashMap::get` needs `Borrow` because it additionally guarantees `Eq`/`Ord`/`Hash` agree between the owned and borrowed forms, a consistency `AsRef` does not promise. Return concrete, owned types so callers can predict what they get.

## Cross-references

- **`api-design` / `api-and-interface-design` skills** — general (language-agnostic) API and interface-boundary principles: resource modeling, versioning strategy, contract stability. This file is the Rust-specific realization (traits-as-ports, `pub(crate)`, sealed traits, semver-via-visibility); consult those for the cross-cutting design reasoning.
- **`rust-patterns` / `rust-testing` ECC skills** — basic idioms and TDD. This file goes deeper on the *architectural* decisions; those cover day-to-day pattern and test mechanics.

## Sources

- Microsoft RustTraining — c-cpp-book, "Case Study 4: God object → Composable state": https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch16-cases-3-5-lifetime-borrowing.md
- Microsoft RustTraining — async-book, Ch 14 "Async Is an Optimization, Not an Architecture": https://github.com/microsoft/RustTraining/blob/main/async-book/src/ch14-async-is-an-optimization-not-an-architecture.md
- Microsoft RustTraining — rust-patterns-book, "15. Crate Architecture and API Design": https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch15-crate-architecture-and-api-design.md
- Microsoft RustTraining — type-driven-correctness-book, "The Philosophy — Why Types Beat Tests": https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch01-the-philosophy-why-types-beat-tests.md
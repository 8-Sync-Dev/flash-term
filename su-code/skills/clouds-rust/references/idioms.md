# Idiomatic Rust

The idioms that separate senior from junior Rust — each with the mechanism, the reason it is idiomatic, the cost, and when to break it. Baseline: **Rust 1.96, edition 2024**. Cross-references the `rust-patterns` ECC skill; this file goes deeper on judgment and trade-offs rather than restating catalog patterns.

The through-line: **push errors to compile time, push invariants into types, and make the compiler enforce what a comment would otherwise ask a reviewer to enforce.** Most idioms below are one instance of that principle.

## Constructors and conversions

Rust has no language-level constructor. `new` is a *convention*, not a keyword, and that freedom is the point: you name construction by intent.

**`new` is the inherent, infallible, obvious constructor.** Return `Self`. If construction can fail, `new` is the wrong name — a `new` that returns `Result` surprises readers who expect it to always succeed. Fallible construction wants either a named `try_*`/`parse`/`open` method or `TryFrom`.

**`with_*` names an alternative construction axis** (`Vec::with_capacity`, `HashMap::with_hasher`) — same output type, different input dimension. Reach for it when `new` already means the default and you need a second, equally-primary entry point. Do not invent `with_*` for every field; that is the builder's job (below).

**`Default` is for "there is one obvious zero-config value."** Derive it when every field's default composes into a meaningful whole. The payoff is ecosystem reach: `#[derive(Default)]`, `..Default::default()` struct-update syntax, and generic code bounded on `T: Default` all light up for free.

```rust
#[derive(Default)]
pub struct Server {
    host: String,
    port: u16,
    tls: bool,
}

impl Server {
    pub fn new(host: impl Into<String>) -> Self {
        Self { host: host.into(), port: 8080, tls: false }
    }
    pub fn with_port(mut self, port: u16) -> Self {
        self.port = port;
        self
    }
}
```

**Trade-off:** `Default` silently produces a value even when "empty" is a bug (a `Config` whose default is a valid-but-wrong state). Prefer no `Default` and force callers through `new` when there is *no* sensible zero value — an un-constructable-by-default type is a feature.

**`From`/`TryFrom` over ad-hoc `to_foo`/`from_foo` converters.** Implementing `From<A> for B` gives you `B::from(a)`, `a.into()`, the `?` operator's error coercion, and blanket `Into` for free. An ad-hoc `fn from_a(a: A) -> B` gives you none of that and forces every caller to learn a bespoke name.

```rust
pub struct Port(u16);

impl TryFrom<u32> for Port {
    type Error = &'static str;
    fn try_from(v: u32) -> Result<Self, Self::Error> {
        if v <= u16::MAX as u32 { Ok(Port(v as u16)) } else { Err("port out of range") }
    }
}

impl From<Port> for u16 {
    fn from(p: Port) -> u16 { p.0 }
}
```

Rule of thumb (per the API Guidelines, C-CONV): implement `From` when the conversion is **infallible and lossless**; `TryFrom` when it can fail. Never `impl From` for a lossy/fallible conversion — panicking inside `From` violates every caller's assumption. Implement `From`, not `Into`: `impl From<A> for B` auto-generates the `Into<B> for A` blanket for free, and std encodes lossless-vs-lossy at the API level by deliberately omitting `From` for narrowing casts (there is no `From<i64> for i32`, only `TryFrom`), so `.into()` fails to compile on a lossy path and forces you through a fallible `try_into()?`. **When to deviate:** if the conversion needs a parameter or context (a locale, an allocator, a config), it is not a `From` — use a named method. `From` is a pure `A → B`.

## The builder pattern — when it earns its keep

A builder is a mutable staging type whose terminal `build()` yields the real value. It costs a second type, a fistful of `with_*` methods, and indirection. It earns that cost only under specific conditions:

| Condition | Builder? | Why |
|---|---|---|
| 3–4 fields, all with sensible defaults | No | Struct literal + `..Default::default()` is shorter and needs no new type |
| Many optional fields, several combos invalid | Yes | Builder concentrates validation in `build()` and reads as prose at the call site |
| Construction is fallible / needs staged validation | Yes | `build(self) -> Result<T, E>` is the natural home for the check |
| Field set will grow over time (public API) | Yes | Adding a `with_*` is non-breaking; adding a struct field with no `Default` is breaking |
| You need compile-time "required field X was set" | Typestate builder | Encode required-field presence in type params (below) |

**Owned (`self`) vs mutable-borrow (`&mut self`) builder.** Owned/consuming builders (`fn with_x(mut self) -> Self`) chain cleanly for one-shot construction and are the common default. `&mut self` builders return `&mut Self` and suit conditional building (`if debug { b.verbose(true); }`) without re-binding, but then need a `build(&self)` that clones. Pick owned unless callers genuinely need to build across branches.

**Trade-off:** builders defer *all* validation to runtime `build()`. If you want the type system to reject a missing required field, that is the **typestate builder** — parameterize the builder over marker types (`Builder<HostSet, PortMissing>`) so `build()` only exists once required markers flip. It is powerful and verbose; reserve it for APIs where a forgotten field is catastrophic and you cannot tolerate a runtime error. For most code, a `build() -> Result<_, _>` is the right amount of safety.

**When to deviate:** if `Default` + struct-update already expresses everything and no combination is invalid, a builder is pure ceremony. Do not add one preemptively "for the future" on an internal type — refactoring a struct literal to a builder later is mechanical.

## API boundaries: accept borrowed, return owned; generics for ergonomics

**Accept `&str` not `&String`, `&[T]` not `&Vec<T>`, `&Path` not `&PathBuf`.** `&String` can only receive a `String` reference; `&str` accepts string literals, slices, and `&String` (via deref coercion) — strictly more callers for zero cost. The narrow type is *less* capable and buys nothing. This is the single most common junior tell in a Rust review.

```rust
pub fn greet(name: &str) -> String {   // not name: &String
    format!("hello, {name}")
}
```

**`impl Into<String>` / `impl AsRef<Path>` at ergonomic boundaries.** `impl Into<String>` lets a caller pass `&str` *or* `String` and defers the allocation decision to the function — you allocate exactly once, only if you keep the value. `impl AsRef<Path>` unifies `&str`, `String`, `&Path`, `PathBuf` behind one signature.

```rust
use std::path::Path;
pub fn load(path: impl AsRef<Path>) -> usize {
    path.as_ref().as_os_str().len()
}
```

**Trade-off:** generics balloon monomorphized code size and can worsen compile times; each distinct instantiation is a separate compiled function. And `impl Trait` in argument position is *strictly less* flexible than a named generic in one way — the caller cannot turbofish it. For a hot, widely-called internal function, a concrete `&str` may compile faster and read plainer. **When to deviate:** on a private helper called from three places, skip the generic and take `&str`/`&Path` directly. Save `impl Into`/`AsRef` for public API surface where caller ergonomics justify the code bloat.

**Accept-borrowed-return-owned** is the ownership contract that makes functions composable: borrow your inputs (caller keeps them), return owned outputs (caller decides their fate). Returning a borrow ties the output's lifetime to an input and virally constrains callers — do it only when you are genuinely returning a *view* into an argument (`fn first_word(s: &str) -> &str`), not producing a new value.

## Make illegal states unrepresentable

This is the highest-leverage idiom in the language. Every invalid combination you can make un-typeable is a class of bug that cannot occur and a test you never have to write.

**Enums over bool-soup.** Three `bool` fields encode eight states; if only three are legal, five are latent bugs guarded by comments and asserts. An enum encodes exactly the legal states:

```rust
pub enum Connection {
    Disconnected,
    Connecting { attempt: u32 },
    Connected { session: String },
}
```

`session` *cannot* exist while `Disconnected`, and `attempt` *cannot* leak into `Connected` — the type geometry forbids it. Compare a struct with `is_connected: bool, session: Option<String>, attempt: Option<u32>`, where every consumer must re-check that the right fields are populated together.

**Exhaustive `match` is a refactoring tool, not just a safety net.** Adding an enum variant breaks the build at every `match` that must now handle it — the compiler hands you the exact edit list. A catch-all `_` arm on a *closed* enum throws that away (the new variant silently falls through), so avoid `_` on enums you own; spell out the arms and let the next variant find them.

**Enum + `match` dispatch over `Box<dyn Trait>` for closed variant sets.** The decision test is one question: *is this set of variants closed at compile time?* If yes, an enum with exhaustive `match` beats a trait object — no vtable, no allocation, and the compiler enforces every case. Field data from porting a ~100K-line C++ diagnostics codebase: of ~900 virtual methods only ~25 genuinely needed `dyn Trait` (plugin extension points and test mocks); the rest became enums, collapsing ~400 `dynamic_cast` calls to zero runtime type errors. The dual idiom for *behaviour*: model orthogonal capabilities as small traits (`HasArea`, `HasVolume`) with default methods and combine them at the use site with `impl HasArea + HasVolume` bounds — monomorphized static dispatch is zero-cost and there is no diamond problem. Reserve `dyn Trait` for genuinely open extension points and heterogeneous runtime collections.

**Eliminate `Option` fields that co-vary.** Two `Option`s that are always both `Some` or both `None` are one `Option<(A, B)>` or one enum arm. Co-varying `Option`s are the struct-field form of bool-soup.

**Newtypes for units, IDs, and validated values.** `struct UserId(u64)` and `struct OrderId(u64)` are incompatible at compile time, so you can never pass an order id where a user id belongs — a bug that a bare `u64` invites and a test rarely catches. Newtypes also give a *validation choke point*: make the field private and the only constructor a validating `TryFrom`/`parse`, and every value of that type is provably valid everywhere downstream ("parse, don't validate").

```rust
pub struct UserId(u64);
pub fn make(id: u64) -> UserId { UserId(id) }
```

**Trade-off:** newtypes cost boilerplate — you re-expose the operations you want (`Display`, arithmetic) rather than getting them free. Do not newtype where a value is genuinely a plain number with no invariant and no unit confusion. And do not reach for `Deref` on an invariant-enforcing newtype to dodge the boilerplate — it punches a hole through the abstraction by making *every* inner method callable (an `Email: Deref<str>` leaks `.split_at()`; a `Password` leaks `.as_bytes()`), and `DerefMut` is worse still because `*value = x` bypasses your validating constructor outright. The API Guidelines (C-DEREF) reserve `Deref` for smart pointers whose whole job is to *be* the target (`Box`, `Arc`, `MutexGuard`); for a restriction newtype expose `AsRef`/`Borrow` plus explicit delegating methods instead. **When to deviate:** private, short-lived, single-use values inside one function don't need a newtype; the idiom pays off at API and module boundaries.

**Typestate pattern — invalid *operations* unrepresentable.** Encode an object's protocol state in a type parameter so methods only exist in the states where they are legal. A closed connection has no `send`; an open one has no `open`:

```rust
use std::marker::PhantomData;

pub struct Open;
pub struct Closed;

pub struct Conn<State> {
    fd: i32,
    _state: PhantomData<State>,
}

impl Conn<Closed> {
    pub fn new(fd: i32) -> Self { Conn { fd, _state: PhantomData } }
    pub fn open(self) -> Conn<Open> { Conn { fd: self.fd, _state: PhantomData } }
}

impl Conn<Open> {
    pub fn send(&self, _bytes: &[u8]) {}
    pub fn close(self) -> Conn<Closed> { Conn { fd: self.fd, _state: PhantomData } }
}
```

The state transitions *consume* `self` and return the next state, so a stale handle to the old state is moved out of scope. `PhantomData<State>` carries the marker with zero runtime cost. **Trade-off:** typestate explodes into many `impl` blocks and confuses error messages; it does not work when state must be chosen at runtime (e.g. a state machine driven by network input — there you need a runtime enum). **When to deviate:** use typestate for *compile-time-known* protocol ordering (builder required-fields, a hardware peripheral's configure→enable→use sequence); use a runtime enum when the environment decides the transitions.

**Zero-sized capability tokens encode proof-of-authority.** A `struct AdminToken { _private: () }` is unconstructable outside its issuing module and costs zero bytes, so a signature like `fn reset_link(&mut self, _admin: &AdminToken, ...)` turns a repeated runtime `if !is_admin` check into a compile-checked proof obligation the caller must already hold. Chain state tokens (`StandbyOn → AuxiliaryOn → MainOn`) to enforce ordered sequences and a trait hierarchy (`Authenticated: Operator: Admin`) to model privilege levels — all erased at compile time.

**Lifetime branding** hands each arena/session handle an invariant, unforgeable lifetime (`PhantomData<*mut &'arena ()>`) via a `for<'arena> FnOnce` closure, so each call gets a fresh opaque `'arena` that cannot unify with another's: a handle minted against arena A is a *compile* error when used with arena B — index-into-the-wrong-collection bugs become unrepresentable with no generation counters and zero runtime cost.

## Iterator-first thinking

Prefer iterator chains to manual index loops. Not for terseness — for correctness and optimizability. An index loop invites off-by-one and out-of-bounds bugs; `for x in &v` and `v.iter().map(...)` cannot index out of bounds because there is no index. The compiler also elides bounds checks more reliably across adapter chains than across hand-rolled `v[i]` accesses.

```rust
pub fn even_squares(v: &[i32]) -> Vec<i32> {
    v.iter().filter(|&&x| x % 2 == 0).map(|&x| x * x).collect()
}
```

**`collect` into `Result` short-circuits.** `Iterator<Item = Result<T, E>>` collects to `Result<Vec<T>, E>`, stopping at the first `Err` — the idiomatic "parse all or fail fast" with no manual loop-and-break:

```rust
pub fn parse_all(items: &[&str]) -> Result<Vec<i64>, std::num::ParseIntError> {
    items.iter().map(|s| s.parse::<i64>()).collect()
}
```

Iterators are lazy: nothing runs until a consuming adapter (`collect`, `sum`, `for`, `find`). This lets you compose transformations without intermediate allocations — `filter().map().take(3)` never builds the full intermediate vector.

**Trade-off:** deeply nested closures with captured mutable state read worse than a plain `for` loop, and a `for` loop with early `break`/`continue`/`?` on complex control flow is clearer than forcing it through `try_fold`. Idiomatic ≠ "always a chain." **When to deviate:** when the loop body has genuine imperative control flow (multiple exits, side effects, `?` on several fallible steps), write the `for` loop — it is idiomatic too. Reserve chains for the map/filter/reduce shape they model.

## Error handling: `?`, conversion, and the panic boundary

**`?` is early-return-on-error with automatic conversion.** `expr?` on a `Result` returns the `Ok` value or returns the `Err` from the enclosing function — after passing it through `From::from`. That last part is the leverage: implement `From<LibError> for MyError` and a bare `?` promotes library errors into your domain error type with no `.map_err`:

```rust
#[derive(Debug)]
pub struct AppError(String);

impl From<std::num::ParseIntError> for AppError {
    fn from(e: std::num::ParseIntError) -> Self { AppError(e.to_string()) }
}

pub fn parse_sum(a: &str, b: &str) -> Result<i64, AppError> {
    let x: i64 = a.parse()?;   // ParseIntError -> AppError via From
    let y: i64 = b.parse()?;
    Ok(x + y)
}
```

`try!` is the pre-2018 macro that `?` replaced — never write it. For libraries, prefer a concrete error enum (hand-rolled or `thiserror`); for applications, a type-erased `anyhow::Error` is idiomatic because callers only ever log or bubble it. The dividing line: *does anyone match on the error variant?* Libraries must let them (enum); applications usually don't (erased). See `rust-patterns` for the error-type catalog; the judgment call is the enum-vs-erased boundary.

**`matches!` for boolean predicates on shape.** When you only need a `bool` from a pattern test, `matches!` beats a `match ... { X => true, _ => false }` — one line, no ceremony:

```rust
pub fn is_active(c: &Connection) -> bool {
    matches!(c, Connection::Connected { .. })
}
```

## Control flow: combinators and `let else`

**Combinators over nested `match` for `Option`/`Result` plumbing.** `map`, `and_then`, `unwrap_or`, `ok_or`, `filter` express the common shapes without pyramid indentation:

```rust
pub fn config_port(raw: Option<&str>) -> u16 {
    raw.and_then(|s| s.parse().ok()).unwrap_or(8080)
}
```

The nested-`match` equivalent is four lines of boilerplate that obscures the one decision. **When to deviate:** when arms have real bodies (logging, side effects, divergent logic per variant), a `match` is clearer than a chain of closures — combinators shine for *transformation*, `match` for *branching logic*.

**`let else` for the "extract or bail" shape.** Stabilized in 1.65, it binds a pattern in the *enclosing* scope and runs a diverging `else` on failure — no rightward drift, no dummy binding:

```rust
pub fn first_word(s: &str) -> &str {
    let Some(idx) = s.find(' ') else { return s; };
    &s[..idx]
}
```

This replaces the old `let idx = match s.find(' ') { Some(i) => i, None => return s };`. The `else` block must diverge (`return`, `break`, `continue`, `panic!`). Use it for guard clauses at the top of a function; use `if let` when you want the bound value only inside the taken branch.

## RAII and `Drop` guards

Rust has no `finally`. Cleanup rides on ownership: when a value's owner goes out of scope, `Drop::drop` runs deterministically. Encode "resource acquired → must be released" as a guard type whose `Drop` releases:

```rust
pub struct SpanGuard { name: &'static str }

impl SpanGuard {
    pub fn enter(name: &'static str) -> Self { SpanGuard { name } }
}

impl Drop for SpanGuard {
    fn drop(&mut self) {
        let _ = self.name;  // pop span / release here
    }
}

pub fn work() {
    let _guard = SpanGuard::enter("work");
    // guard is live until the end of scope, then drop() runs — even on early return or panic
}
```

This is how `MutexGuard`, `File`, and `tracing::span` entered-guards work: the lock is released, the fd closed, the span exited when the guard drops, *including on panic unwind*. Bind the guard to a named variable — `let _guard = ...`, **not** `let _ = ...`. `let _ =` drops *immediately* (it is a wildcard, not a binding), releasing the resource on the same line and defeating the whole point; a subtle, real bug.

**Trade-off:** `Drop` cannot be async and cannot return an error — a `Drop` that needs to `.await` (async DB rollback) or report a flush failure has no clean home. For those, expose an explicit `async fn close(self) -> Result<...>` and treat `Drop` as best-effort backstop. **When to deviate:** if release genuinely must be fallible-and-observable, don't hide it in `Drop`; make callers call `close()`. Use `Drop` for infallible, fire-and-forget cleanup.

## `#[must_use]` — make ignoring the result a warning

`#[must_use]` makes the compiler warn when a value is discarded. `Result` carries it (ignoring an error warns); put it on your own types and functions where dropping the return is almost always a bug — a `Receipt`, a `Guard` you forgot to bind, a builder's `build()` output, a lazy iterator, a function whose *only* purpose is its return value.

Ownership prevents *re*-use, never *omission* — a caller can `drop()` a single-use token (a nonce, a receipt) without ever consuming it, so move semantics alone is a partial guarantee. `#[must_use]` turns that silent drop into a warning; a typestate transition that only exists on the correct state promotes it to a hard compile error.

```rust
#[must_use = "this Receipt must be checked"]
pub struct Receipt(bool);

pub fn commit() -> Receipt { Receipt(true) }
```

The optional message tells the caller *what to do instead*. **Trade-off:** over-applying it turns intentional discards into noise and trains people to `let _ =` reflexively (which then also silences real mistakes). **When to deviate:** don't annotate functions with meaningful side effects whose return is genuinely optional info (a `HashMap::insert` returning the old value) — there, ignoring the result is normal.

## `unwrap` / `expect` discipline

`unwrap()` on `None`/`Err` panics with a generic message; `expect("reason")` panics with *your* message. Neither is banned — the rule is **a panic must be provably unreachable or a genuine unrecoverable invariant**, and the code must say which.

- **`unwrap()` in library or production paths on external/fallible input is a defect.** It converts a recoverable condition into a crash and gives operators no context. Return the error with `?`.
- **`expect("reason")` is correct when the failure is a *bug in the program*, not a runtime condition** — and the string documents the invariant you are asserting. `expect` a `Mutex::lock` (a poisoned lock means another thread already panicked — unrecoverable), `expect` a regex you wrote as a literal (`Regex::new(LITERAL).expect("literal regex is valid")`), `expect` after you just `push`ed so `last()` is `Some`. The message is a proof obligation for the reader: it states *why* this cannot fail. The community convention (the "expect-as-documentation" style) is that the string reads as the assumption, not the failure ("env var CONFIG_PATH set by launcher", not "failed to get env var").
- **Tests and prototypes:** `unwrap`/`expect` are fine — a panic *is* the test failure.

**When to deviate:** at the very top of `main`, unwrapping a startup error to abort is acceptable (though returning `Result` from `main` and letting it print is cleaner). The distinction is always "is this a runtime possibility (→ `?`) or a violated program invariant (→ `expect` with the invariant stated)."

## Naming conventions (API Guidelines C-CONV, C-GETTER)

Names are an interface. Rust's conventions encode ownership cost into the name so callers know what a call *does* without reading the body.

| Prefix | Ownership / cost | Example |
|---|---|---|
| `as_` | cheap, borrowed→borrowed, no alloc | `str::as_bytes(&self) -> &[u8]` |
| `to_` | expensive, borrowed→owned, allocates/clones | `str::to_owned(&self) -> String` |
| `into_` | consumes `self`, may reuse the allocation | `String::into_bytes(self) -> Vec<u8>` |

Getters have **no `get_` prefix** — the field-shaped name *is* the getter (`config.port()`, not `config.get_port()`). The `get_` form is reserved for the rare case with a different meaning (`[T]::get(i) -> Option<&T>`, the bounds-checked accessor). A `get_`-prefixed plain getter is a C#/Java transplant and reads as noise to a Rust reviewer.

```rust
pub struct Buffer { data: Vec<u8> }
impl Buffer {
    pub fn data(&self) -> &[u8] { &self.data }          // getter, no get_
    pub fn as_slice(&self) -> &[u8] { &self.data }       // cheap borrow
    pub fn to_vec(&self) -> Vec<u8> { self.data.clone() } // expensive, allocates
    pub fn into_inner(self) -> Vec<u8> { self.data }      // consumes, reuses alloc
}
```

Beyond prefixes: types/traits/enum variants are `UpperCamelCase`, functions/methods/fields/locals are `snake_case`, constants/statics are `SCREAMING_SNAKE_CASE`, and `rustc` warns on deviations by default (`non_camel_case_types`, `non_snake_case`, `non_upper_case_globals`) — no clippy needed. The payoff is that the whole ecosystem reads the same way — a reviewer infers cost and ownership from the name alone, which is exactly what a name is for.

## See also

- `rust-patterns` skill — the pattern *catalog* (error types, smart-pointer choices, trait-object vs generics). This file is the *judgment layer* on top of it.
- Rust API Guidelines — https://rust-lang.github.io/api-guidelines/ (C-CONV, C-GETTER, C-CTOR, naming).
- The Book, ch. 6 (enums), ch. 9 (error handling), ch. 13 (iterators/closures) — https://doc.rust-lang.org/book/.
- Comprehensive Rust — https://google.github.io/comprehensive-rust/ (structured fundamentals).
- `rust-clippy` lint rationale — the "why" behind each idiomatic-lint the compiler nudges you toward.

## Sources

Microsoft RustTraining (https://github.com/microsoft/RustTraining):
- C/C++ → Rust, ch. 16 — trait-object-vs-enum dispatch and C++-port metrics — https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch16-cases-3-5-lifetime-borrowing.md
- C# → Rust, inheritance vs composition (capability traits) — https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch10-2-inheritance-vs-composition.md
- C# → Rust, migration patterns (consuming builder) — https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch15-migration-patterns-and-case-studies.md
- Python → Rust, ch. 11 — `From`/`Into` and the lossless-vs-lossy distinction — https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch11-from-and-into-traits.md
- Python → Rust, ch. 6 — exhaustive pattern matching as a change-safety mechanism — https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch06-enums-and-pattern-matching.md
- Rust Patterns, ch. 3 — newtype/type-state and the `Deref` (C-DEREF) rule — https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch03-the-newtype-and-type-state-patterns.md
- Rust Patterns, ch. 4 — `PhantomData` and lifetime branding — https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch04-phantomdata-types-that-carry-no-data.md
- Type-Driven Correctness, ch. 3 — single-use types and the move-vs-omission gap — https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch03-single-use-types-cryptographic-guarantee.md
- Type-Driven Correctness, ch. 4 — zero-cost capability tokens — https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch04-capability-tokens-zero-cost-proof-of-aut.md
- Type-Driven Correctness, ch. 5 — protocol state machines via type-state — https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch05-protocol-state-machines-type-state-for-r.md

# Engineering Best Practices & Error Design

Senior judgment for production Rust: how to design errors, decide panic-vs-Result, keep a public API semver-stable, and harden boundaries. Assumes rustc 1.96 / edition 2024. Cross-references `rust-patterns` (idioms), `rust-testing` (TDD), and `tooling.md` (clippy/tracing setup); this file is the *decisions*, not the setup.

## The error-handling boundary: libraries vs binaries

The single most consequential error decision is *where* the code sits. A **library** returns errors it does not know how to handle to a caller it does not control — so its errors are part of its public API contract and must be *inspectable*: the caller needs to match on "was this a timeout or a 404?" A **binary/application** is the end of the line — nobody matches on its errors programmatically, they get logged or shown, so what matters is a rich *context chain* for a human, not a typed enum.

This maps to two crates that are the community default (not std, but universal):

| Crate | Use in | Gives you | Costs |
|-------|--------|-----------|-------|
| `thiserror` | libraries | derive for typed error *enums*, `Display`, `From`, `source()` | you enumerate every failure mode |
| `anyhow` (or `eyre`) | binaries, tests, prototypes | one opaque `anyhow::Error`, `.context()`, captured backtrace | callers can't match variants |

**Why not one tool for both?** If a library returns `anyhow::Error`, downstream code can only `Display` it — it can never react differently to a retryable vs fatal error, which defeats the point of a library. If a binary defines a hand-rolled enum for every failure, you pay enumeration cost for errors nobody will ever match on. Match the tool to who consumes the error.

**When to deviate:** a large internal application with a stable service boundary may want typed errors at that boundary (so HTTP handlers map variants → status codes) even though it's a "binary". And a tiny library with exactly one failure mode can expose a single unit struct instead of pulling in `thiserror`. The rule is about *consumers*, not about the `[[bin]]`/`[lib]` line in `Cargo.toml`.

## Library errors with `thiserror`

`thiserror` is a *derive-only* dependency — it generates trait impls at compile time and adds nothing to your runtime or public API surface (it does not appear in your signatures). You still own a plain `enum`; the macro writes `Display`, `Error::source`, and `From` for you.

```rust
// illustrative (needs the `thiserror` crate)
use thiserror::Error;

#[derive(Debug, Error)]
#[non_exhaustive]
pub enum StoreError {
    #[error("failed to read config")]
    Io(#[from] std::io::Error),          // #[from] generates From<io::Error> + wires source()

    #[error("parse error at line {line}: {msg}")]
    Parse { line: usize, msg: String },

    #[error("missing required key `{0}`")]
    Missing(&'static str),
}
```

The hand-written equivalent (verified to compile under edition 2024, no deps) shows exactly what the derive expands to and is worth understanding so you know what you're signing up for:

```rust
use std::fmt;

#[derive(Debug)]
#[non_exhaustive]
pub enum ConfigError {
    Io(std::io::Error),
    Parse { line: usize, msg: String },
    Missing(&'static str),
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConfigError::Io(_) => write!(f, "failed to read config"),
            ConfigError::Parse { line, msg } => write!(f, "parse error at line {line}: {msg}"),
            ConfigError::Missing(key) => write!(f, "missing required key `{key}`"),
        }
    }
}

impl std::error::Error for ConfigError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            ConfigError::Io(e) => Some(e), // preserve the underlying cause
            _ => None,
        }
    }
}

impl From<std::io::Error> for ConfigError {
    fn from(e: std::io::Error) -> Self { ConfigError::Io(e) }
}
```

Three design rules for library error enums:

1. **Wire `source()` for every wrapped error.** The `source()` chain is how tooling, `{:?}` reporters, and callers walk from your high-level error down to the OS-level cause. Dropping the source (e.g. converting `io::Error` to a `String`) throws away the diagnostic trail permanently. `#[from]` and `#[source]` do this for you; hand impls must return `Some(e)`.

2. **`Display` describes *this* layer only — never chain manually.** Write `"failed to read config"`, not `"failed to read config: {io_err}"`. The formatting layer (anyhow's reporter, `eyre`, or a manual `while let Some(src) = e.source()` loop) concatenates the chain. If each `Display` also prints its source you get the cause repeated N times ("failed to read config: file not found: file not found: ...").

3. **`#[non_exhaustive]` on public error enums, almost always.** See semver section — adding a variant is otherwise a breaking change.

Two more conventions make typed errors ergonomic end-to-end: add a crate-wide alias `pub type Result<T> = std::result::Result<T, StoreError>;` so every signature reads `-> Result<T>`, and compose sub-module error enums into the crate error with an `#[error(transparent)]` `#[from]` variant — `transparent` delegates `Display` and `source()` to the inner error instead of adding an empty wrapper layer, so nested enums flatten and stay matchable rather than stringly-collapsed. Large crates routinely run both tools at once: `thiserror` on the library's public API surface, `anyhow` inside `main()`.

**Avoid stringly-typed errors** (`Err("thing went wrong".to_string())` or a single `Error { message: String }`). A string cannot be matched on, cannot carry structured fields (the line number, the offending key), and forces every caller into fragile substring checks. The whole value of a library error is that the caller can *branch* on it. Structured fields (`Parse { line, msg }`) also make errors testable without asserting on prose.

**When to deviate:** for a *parser* or similar where the error genuinely is "unexpected token, here's the span", a struct with a span + message is structured enough; you don't need one variant per token. And an error that is purely informational at a boundary you fully control can be a string. But treat that as a smell to justify, not a default.

## Application errors with `anyhow` / `eyre`

In a binary, `Result<T, anyhow::Error>` (aliased `anyhow::Result<T>`) lets any error type flow up via `?` (anyhow blanket-`From`s anything `Error + Send + Sync + 'static`), and `.context()` attaches a human-readable frame at each layer:

```rust
// illustrative (needs the `anyhow` crate)
use anyhow::{Context, Result};

fn load_user(id: u64) -> Result<User> {
    let raw = std::fs::read_to_string(path_for(id))
        .with_context(|| format!("reading profile for user {id}"))?;
    let user: User = serde_json::from_str(&raw)
        .context("profile JSON was malformed")?;
    Ok(user)
}
```

The payoff is the report: `Error: reading profile for user 42` / `Caused by: No such file or directory (os error 2)`. `context` is a static string (cheap, no allocation until printed); `with_context` takes a closure so the format cost is only paid on the error path — use `with_context` whenever the message interpolates a value.

`eyre` (with `color-eyre`) is a drop-in alternative with customizable reporters and colored, backtrace-rich output — prefer it for CLI tools where operator experience matters; `anyhow` for services where the report goes to a log aggregator. They are mutually redundant; pick one per crate.

**Backtraces:** anyhow/eyre capture a `std::backtrace::Backtrace` at error-creation when `RUST_BACKTRACE=1` (or `RUST_LIB_BACKTRACE=1`). This is *runtime opt-in* and near-free when off. In libraries you generally don't capture backtraces (the caller decides); the context chain plus `source()` is usually enough to locate a fault without the binary size / runtime cost of always-on backtraces.

## `Box<dyn Error>` — the middle ground, and its limits

`Box<dyn std::error::Error + Send + Sync + 'static>` is std-only, needs no crate, and accepts any error via `?`. It's the right choice when you want type erasure without a dependency: internal binaries, examples, `fn main() -> Result<(), Box<dyn Error>>`. What it lacks vs anyhow: no `.context()` ergonomics, no captured backtrace, and the bare `Box<dyn Error>` (without `+ Send + Sync`) can't cross threads or be stored in most async/error frameworks — always add `+ Send + Sync + 'static` unless you have a reason not to. For a *library* public API, `Box<dyn Error>` is usually wrong: it erases the type, so callers are back to string-matching. Prefer a typed enum there.

## When to panic vs return `Result`

The dividing line is **whose bug is it.** Return `Result` for anything the caller could plausibly cause or recover from (bad input, missing file, network failure) — these are *expected* and part of normal operation. Panic for **broken invariants** — states that are only reachable if *your* code has a bug, where continuing would compute on corrupt data.

Concretely, panic (via `panic!`, `unreachable!`, `unwrap`/`expect`, `assert!`, `debug_assert!`) is correct for:

- **Provably-unreachable branches:** `unreachable!("validated by parse() above")`. Documents an invariant the type system can't express.
- **Programming-error preconditions:** indexing `v[i]` past the end, `slice[a..b]` with `a > b`. std itself panics here because a wrong index is a logic bug, not runtime data.
- **`expect` with a *reason*, not a restatement:** `expect("BUG: registry populated at init")` — the message should say *why the author believed it couldn't fail*, so the panic explains the violated assumption. `.unwrap()` bare is acceptable only in tests and throwaway code.
- **Tests:** `unwrap`/`expect`/`assert!` are idiomatic — a failed assertion *is* a failed test.

Return `Result` (never panic) for anything reachable from untrusted or external input: parsing, I/O, arithmetic that can overflow on real data, capacity limits. A library that panics on bad input is a denial-of-service vector — the caller cannot `catch` it ergonomically (`catch_unwind` is not error handling), and a panic that reaches an `extern "C"` boundary aborts the process (it is not UB, but it is unrecoverable, and whether destructors up to the boundary run is unspecified) — use `extern "C-unwind"` if unwinding must legitimately cross, or catch the panic at the boundary and convert it to an error code.

`debug_assert!` is the sweet spot for expensive invariant checks: it runs in tests/debug and compiles to nothing in release, so you can assert "this list is sorted" without paying for it in production. Use it for checks that *should* be redundant if the code is correct.

**When to deviate:** an application's `main` may `expect` on startup config because there's no meaningful recovery and a crash-with-message is the correct behavior. And in `no_std` or panic=abort embedded contexts, the panic-vs-Result calculus shifts toward Result because unwinding isn't available.

## Public API stability & semver hazards

Every public item is a promise. The [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) and the Cargo SemVer reference define what breaks. The non-obvious hazards:

- **Adding an enum variant is a breaking change** — downstream `match` without a wildcard arm stops compiling. Defense: `#[non_exhaustive]` on the enum forces external matches to include a `_ =>` arm *from day one*, so you can add variants in a minor release. Apply it to any public enum you expect to grow, and to essentially all public *error* enums. Cost: your own crate can still match exhaustively, but downstream can never, which is occasionally annoying for closed sum types (e.g. a `Direction { N, S, E, W }` that will never grow — leave those exhaustive). Crucially the attribute only constrains *downstream* crates — inside the defining crate you still match exhaustively (and want to, so a new variant breaks your own build deliberately), so an enum whose whole point is to evolve behind `#[non_exhaustive]` must live in a *separate* library crate from its consumers or the attribute buys them nothing.

- **Adding a public struct field is breaking** if the struct is constructed with a literal downstream. `#[non_exhaustive]` on the struct blocks *all* external struct-literal construction — including functional update syntax `..Default::default()` — so you must supply a constructor or builder (and, if you want incremental configuration, `Default` plus public setters or `pub` fields for mutation). Alternatively keep fields private and expose a builder.

- **Adding a required trait method is breaking** (all impls must add it) *unless* you give it a default body. Even a defaulted addition can break if it collides with an inherent method name at a call site. **Sealed traits** solve the "I want to add methods freely" problem by making the trait unimplementable downstream:

```rust
mod sealed { pub trait Sealed {} }

pub trait Connector: sealed::Sealed {
    fn scheme(&self) -> &str;
}

pub struct Tcp;
impl sealed::Sealed for Tcp {}
impl Connector for Tcp { fn scheme(&self) -> &str { "tcp" } }
```

Because only your crate can `impl sealed::Sealed`, only your crate has impls to update — so you can add methods to `Connector` without a major bump. The trade-off is exactly that: you've taken away downstream's ability to implement the trait. Seal a trait when it models *your* closed set of types (drivers, backends you ship); leave it open when extension is the point (like `Iterator`).

- **Widening is safe, narrowing is breaking:** loosening a bound (`T: Ord` → `T: PartialOrd`), taking `impl AsRef<str>` instead of `&str`, returning a more concrete type. Tightening any of these breaks callers. Returning `impl Trait` hides the concrete type so you can change it later — but it also *pins* the auto-traits (Send/Sync) it happens to have, so changing the hidden type to a `!Send` one is still breaking.

- **`#[must_use]` on RAII guards and on `Result`-returning validators** turns a silently-dropped guard or an ignored validation result into a compile warning rather than a latent bug — cheap insurance for any type whose entire purpose is to be held (a lock guard, a transaction) or checked, and it costs downstream nothing.

Run `cargo semver-checks` in CI — and gate any published-library release on it — to catch these mechanically and report the exact version bump they demand, instead of trusting a human to remember; human review misses variant/field additions constantly.

## Derive hygiene: `Default`, `Clone`, `Debug`

Derive is the default; hand-impl only when the derived behavior is *wrong*, and know the difference:

- **`Debug`** should be on nearly every public type (API Guidelines C-DEBUG) — its absence makes the type unprintable in others' error messages and tests. **Hand-impl to redact secrets:** the derive prints every field, so a derived `Debug` on a struct holding an API key or password will leak it into logs. Redact explicitly:

```rust
use std::fmt;
pub struct ApiKey(String);
impl fmt::Debug for ApiKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("ApiKey").field(&"<redacted>").finish()
    }
}
```

- **`Default`** is right only when the all-fields-default value is *meaningful*. A `RetryPolicy` whose derived default is `max_attempts: 0` is a bug — zero retries is not a sensible default. Hand-impl when the useful default isn't the zero value:

```rust
#[derive(Debug)]
pub struct RetryPolicy { pub max_attempts: u32, pub base_delay_ms: u64 }
impl Default for RetryPolicy {
    fn default() -> Self { Self { max_attempts: 3, base_delay_ms: 100 } }
}
```

- **`Clone`** — derive is fine, but *think before deriving* on types holding large buffers or handles: a derived `Clone` makes deep copies silently, and an accidental `.clone()` in a hot loop is a classic performance trap (see `performance.md`). If a type shouldn't be cheaply copied, *not* deriving `Clone` is a useful forcing function. **`Copy`** is a stronger promise still: deriving it makes moves into copies, which changes move semantics for every user and is a semver-relevant commitment — only derive `Copy` for small, truly value-like types (POD structs, newtypes over integers).

Never derive `Ord`/`Hash` casually on a type with a hand-written `PartialEq` — the derived and manual impls can disagree, violating the `a == b ⇒ hash(a) == hash(b)` contract and corrupting `HashMap`s. If you hand-write one of an equivalence family, audit them all.

## `const` vs `static`

```rust
pub const MAX_CONNS: usize = 1024;      // compile-time value, inlined at each use, no address
pub static BANNER: &str = "service v1"; // single 'static instance with one address
const TABLE: [u32; 4] = [1, 2, 4, 8];   // whole table folded at compile time
```

`const` is a *value* substituted at each use site — there is no single object, so you can't take a stable address and each use may be independently inlined. `static` is a single object with a fixed address living for the whole program. Prefer `const` for configuration constants and lookup tables (the compiler folds them, often to nothing); reach for `static` only when you genuinely need one shared address — e.g. a large table you don't want duplicated, or interop that needs a real symbol. **`static mut` is effectively forbidden** in modern Rust (edition 2024 makes references to it a hard error in many cases); use `std::sync::OnceLock`/`LazyLock` for lazily-initialized globals or an `AtomicUsize` for a mutable counter — both are safe and thread-correct.

## Feature flags done right

The one iron rule: **features must be purely additive.** Enabling a feature may only *add* items, impls, or behavior — never remove or change them. This is because Cargo *unifies* features across the whole dependency graph: if crate A depends on you with feature `x` and crate B depends on you without it, Cargo builds you *once* with `x` on. B gets `x` whether it wanted it or not.

The corollary bug this creates: **mutually-exclusive features are broken by design.** If `runtime-tokio` and `runtime-async-std` are meant to be exclusive, feature unification can enable both, and either you fail to compile (breaking an innocent third party) or silently pick one. Don't model backend choice as competing features; use separate crates, a runtime parameter, or a `compile_error!` guard as a last resort — but understand that guard *will* fire on innocent users when unification bites.

Practical discipline: keep a `default = [...]` that's the common case, make heavy/optional deps `optional = true` and gate them behind a feature, and test the powerset that matters (at least `--no-default-features` and `--all-features`) in CI — a feature that only compiles when another happens to be on is the most common feature bug. Cross-reference `tooling.md` for the CI matrix.

## Documentation as a deliverable

Docs are code you ship, not an afterthought. The mechanism that makes this real: **doctests are compiled and run by `cargo test`.** A `///` example in a fenced ```` ```rust ```` block is a test — it rots loudly instead of silently, so examples in docs stay correct across refactors.

```rust
/// Adds two counts, returning `None` on overflow.
///
/// ```
/// # use mycrate::add;
/// assert_eq!(add(2, 3), Some(5));
/// assert_eq!(add(u32::MAX, 1), None);
/// ```
pub fn add(a: u32, b: u32) -> Option<u32> { a.checked_add(b) }
```

Conventions that carry judgment: `///` documents the *following* item, `//!` documents the *enclosing* module/crate (put the crate overview in `//!` at the top of `lib.rs`). Lead every public doc with a one-line summary (it becomes the search/index blurb), then detail. Document what the API Guidelines call C-FAILURE and C-PANIC: every public `fn` that returns `Result` gets an `# Errors` section, every one that can panic gets a `# Panics` section, every `unsafe fn` gets a `# Safety` section stating the caller's obligations. Hide test-scaffolding lines with a leading `#` (as above) so the rendered example stays minimal while still compiling. `#[doc(hidden)]` removes an item from docs without making it private — use it for macro-internal items that must be `pub` but aren't API.

Enable `#![deny(missing_docs)]` on a public crate to make undocumented public items a build failure — the cheapest possible enforcement.

## Defensive validation at boundaries; newtypes

Validate *once, at the boundary*, then make the type system carry the guarantee inward. The pattern is the **validated newtype**: a wrapper whose only constructor enforces the invariant, so every downstream function taking that type gets validation *for free* and cannot be handed a bad value.

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Username(String);

#[derive(Debug)]
pub struct InvalidUsername;

impl Username {
    pub fn new(raw: &str) -> Result<Self, InvalidUsername> {
        let ok = (3..=32).contains(&raw.len())
            && raw.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
        if ok { Ok(Username(raw.to_owned())) } else { Err(InvalidUsername) }
    }
    pub fn as_str(&self) -> &str { &self.0 }
}
```

**Why this beats validating in every function:** "parse, don't validate" — once you hold a `Username`, its validity is a *type-level fact*, checked at compile time, not a runtime convention every caller must remember. The field stays private so the invariant can't be bypassed with a struct literal. Contrast with passing `&str` everywhere and calling `is_valid()` defensively at each use: that is *shotgun validation* — the same length/charset/checksum checks scattered across dozens of functions, where forgetting one is a silent bug. Spell the boundary constructor as `TryFrom<&str>` so it plugs into `?`, and for layered or polymorphic input (a tag byte selecting a payload shape) give each dispatch level its own parsed type, turning a nested `switch`-on-bytes into exhaustive typed matches. The trade-off is boilerplate (a type + constructor per invariant) and some conversion friction at the edges — worth it for security- or correctness-critical inputs (IDs, emails, paths, SQL fragments), overkill for a throwaway internal helper.

## Logging vs tracing (brief)

Use the `log` facade for simple, synchronous applications and libraries that just need leveled messages — it's the lowest common denominator and any subscriber can consume it. Use `tracing` when you have **async or concurrent** work: `tracing`'s spans capture causal/temporal context across `.await` points and task boundaries, which flat log lines cannot. As a rule, libraries should emit through `tracing` (or `log`) and never install a subscriber — that's the binary's job. Detailed setup, subscriber config, and structured-field conventions live in `tooling.md`.

## Security baseline

- **Treat all external input as hostile** and validate at the boundary (newtypes above). Rust removes memory-safety bugs in safe code but not *logic* vulns: path traversal, SSRF, injection, resource exhaustion. `serde` deserialization of untrusted data still needs limits (max sizes, `#[serde(deny_unknown_fields)]` where strictness matters).

- **Integer overflow has two runtime behaviors and you must choose intentionally.** In debug builds arithmetic *panics* on overflow; in release builds it *wraps* (two's complement) by default. Relying on the debug panic to catch bugs is a trap — the release binary silently wraps, which for a length/index/price computation is a security bug. Be explicit:

```rust
pub fn total(unit_price: u32, qty: u32) -> Option<u32> {
    unit_price.checked_mul(qty)      // None on overflow — handle it
}
pub fn saturating_add_scores(a: u8, b: u8) -> u8 {
    a.saturating_add(b)              // clamp at MAX — for bounded metrics
}
pub fn wrapping_counter(x: u32) -> u32 {
    x.wrapping_add(1)                // wrap on purpose — hashes, ring buffers
}
```

Use `checked_*` when overflow is an error to report, `saturating_*` when clamping is the correct domain behavior, `wrapping_*` only when wraparound is *intended*. `overflow-checks = true` in a release profile turns on the panic in production if you'd rather crash than wrap — a defensible choice for a security-sensitive service. Never leave a size/index/money calculation to the default.

- **`unsafe` audit posture:** every `unsafe` block is a place where *you*, not the compiler, guarantee soundness, so treat each as a reviewed exception. Require a `// SAFETY:` comment on every `unsafe` block stating the invariant that makes it sound (clippy's `undocumented_unsafe_blocks` lint enforces this); minimize the block to the fewest operations; and prefer `#![forbid(unsafe_code)]` on any crate that doesn't need it so new `unsafe` can't sneak in. The bar for adding `unsafe` is "safe Rust genuinely cannot express this or is measurably too slow, and I can write the SAFETY proof" — not convenience. Deep treatment (aliasing, `Send`/`Sync`, FFI, `MaybeUninit`) is in `unsafe-rust.md`; this is the posture, that file is the mechanics.

- **Supply-chain policy needs two tools that answer different questions.** `cargo-deny` is machine-checkable policy — known advisories, disallowed licenses, banned or duplicate versions, untrusted sources; run it everywhere. `cargo-vet` records that a *trusted human* reviewed this exact crate version (and lets you import audits from Mozilla/Google/Bytecode Alliance); add it on top of `deny` for high-assurance (gov/finance/infra) contexts, not as a fallback from it.

- **Lock-file discipline:** commit `Cargo.lock` for binaries/applications (reproducible builds) and gitignore it for libraries (let downstream resolve versions), and add `cargo update --locked` to CI so a stale lock fails the build rather than drifting silently.

## Sources

- The Rust Programming Language — https://doc.rust-lang.org/book/ (Ch. 9 error handling, Ch. 14 publishing)
- Rust API Guidelines — https://rust-lang.github.io/api-guidelines/ (C-DEBUG, C-FAILURE, C-PANIC, sealed traits, future-proofing)
- The Cargo Book, SemVer compatibility — https://doc.rust-lang.org/cargo/reference/semver.html
- `thiserror` / `anyhow` docs — https://docs.rs/thiserror, https://docs.rs/anyhow
- std docs: `std::error::Error`, `std::backtrace`, `OnceLock`/`LazyLock`, integer `checked_/wrapping_/saturating_*`
- The Rustonomicon — https://doc.rust-lang.org/nomicon/ (unsafe posture)
- Rust Performance Book — https://nnethercote.github.io/perf-book/ (clone/Copy cost)
- Comprehensive Rust (Google) — https://google.github.io/comprehensive-rust/ (error-handling fundamentals)

Microsoft RustTraining:
- Crate-Level Error Types and Result Aliases — https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch09-1-error-handling-best-practices.md, https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch09-1-crate-level-error-types-and-result-alias.md
- Error Handling — Custom Error Types with thiserror — https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch09-error-handling.md
- Crate Architecture and API Design (`#[non_exhaustive]`, sealed traits, `#[must_use]`) — https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch15-crate-architecture-and-api-design.md
- Error Handling Patterns — https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch10-error-handling-patterns.md
- Validated Boundaries — Parse, Don't Validate — https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch07-validated-boundaries-parse-dont-validate.md
- Fourteen Tricks from the Trenches (Trick 3 — `#[non_exhaustive]`) — https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch11-fourteen-tricks-from-the-trenches.md
- Dependency Management and Supply Chain Security (`cargo-deny`/`cargo-vet`/`cargo-semver-checks`, lock-file policy) — https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch06-dependency-management-and-supply-chain-s.md

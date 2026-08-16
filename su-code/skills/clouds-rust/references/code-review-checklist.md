# Rust Code Review Checklist & Heuristics

The file a senior reviewer opens during a PR: each item names the **smell** and the **question** to ask, so you catch the class of bug — not one instance. Ordered by severity: correctness first, then things that rot the codebase, then style. Baseline: Rust 1.96, edition 2024. Cross-references `rust-patterns` / `rust-testing` for the idioms themselves; this file is judgment about a *diff*.

How to use: skim by section, but weight by blast radius. A `pub` API mistake or a lock-across-`await` is worth ten style nits — those you leave to `clippy`, which should be green before you spend a human minute (see [Style](#style--let-the-tools-do-it)). Reviewers have a finite attention budget; spend it on the reversibility of the decision, not the syntax.

---

## Correctness — is it actually right?

The highest-value review category. A wrong-but-compiling Rust program is the expensive kind of bug because the type system already caught the cheap ones.

- **`unwrap()`/`expect()`/`panic!` in library code.** *Smell:* a `.unwrap()` on a path that untrusted input can reach. *Question:* "Can a caller trigger this panic with data they control?" A panic in a *binary*'s `main` is often fine — it's a top-level abort with a message. The same call in a `pub fn` of a library turns the caller's error-handling contract into a landmine: they cannot catch it without `catch_unwind` (which is not a general error mechanism and does nothing for `panic = "abort"` builds). The fix is to return `Result`/`Option`, not to litter `expect`. Deviation: `unwrap` is *correct* when the invariant is locally proven — `re.captures(s).unwrap()` right after you matched, or `expect` on a `Mutex` lock where a poisoned lock genuinely is unrecoverable. Demand the `expect` message state the *invariant*, not the symptom: `expect("BUG: capacity computed above guarantees room")`, not `expect("push failed")`.

- **Unhandled `Result` / `#[must_use]` gaps.** *Smell:* a fallible call whose result is dropped (`let _ = ...` written reflexively, or a `Result`-returning method called for effect). *Question:* "Does ignoring this error silently lose data or corrupt state?" A dropped `write`/`flush` `Result` is the classic data-loss bug. Conversely, when *you* author a function whose result must not be ignored, tag it:

  ```rust
  #[must_use = "a failed flush loses buffered data"]
  pub fn flush() -> Result<(), std::io::Error> { Ok(()) }
  ```

  The message is the review artifact — it tells the next reader *why* the result matters. `#[must_use]` also belongs on any type that is pure-by-construction (a builder, a `Future`, a lazy iterator). Trade-off: `let _ =` is a legitimate, *explicit* discard — accept it when the author clearly meant "I know this can fail and I don't care here" and the loss is truly harmless.

- **Integer overflow.** *Smell:* `a + b`, `len - 1`, `x * scale` on values derived from input or accumulation. *Question:* "In release mode, what happens when this wraps?" Debug builds panic on overflow; **release builds wrap silently by default** — the arithmetic that was caught in CI ships as a silent wrap in production. This is the single most under-reviewed correctness issue in Rust. The choice is explicit intent:

  ```rust
  pub fn slot_index(base: usize, offset: usize, len: usize) -> Option<usize> {
      let idx = base.checked_add(offset)?;   // None on overflow
      (idx < len).then_some(idx)
  }
  ```

  Use `checked_*` at trust boundaries (return `None`/error), `saturating_*` when clamping is the correct domain behavior, `wrapping_*` only when wrap is *intended* (hashing, counters), and `overflow-checks = true` in the release profile for security-sensitive crates. `a as u8` truncation is the silent cousin — flag every `as` cast that narrows; prefer `u8::try_from(x)?`.

- **Off-by-one and panicking slice indexing.** *Smell:* `&v[i..j]`, `&s[..n]`, `v[i]` where an index is computed. *Question:* "Is `j > len` or `i > j` reachable, and does this slice a `str` on a non-char boundary?" Indexing panics; `.get(i)` / `.get(i..j)` return `Option` and let you handle the edge. String slicing has a second trap: `&s[..n]` panics if `n` is not a UTF-8 char boundary — always suspect it when `n` comes from a byte count. Reviewer's reflex: any raw index into a slice/str deserves the question "prove the bound," and the ergonomic answer is usually `get`, `first`, `last`, `split_at_checked`, or an iterator.

- **Non-exhaustive / lazy matches.** *Smell:* a `match` ending in `_ => {}` on a type the author controls, or `if let` where the `else` case is silently dropped. *Question:* "When someone adds an enum variant, will the compiler force this site to be revisited — or will it fall through the wildcard?" A wildcard arm on your *own* enum defeats exhaustiveness checking, Rust's best refactoring safety net. Prefer naming variants explicitly, so adding a variant is a compile error rather than a silent behavior change. `_ => unreachable!("…")` documents intent but still defeats exhaustiveness — it converts a would-be compile error into a runtime panic; if you need a catch-all for a genuinely impossible state, prefer matching the remaining variants by name and calling `unreachable!` in those arms. Wildcards are appropriate for `#[non_exhaustive]` upstream enums you don't own — there you're *forced* to have one.

- **Error swallowing.** *Smell:* `.ok()` discarding a `Result`, `unwrap_or_default()` on something that shouldn't fail, `if let Ok(x) = ...` with no `else`, or a `match` arm that logs-and-continues. *Question:* "Is this recovering from the error, or hiding it?" `.ok()` is the quietest data-loss operator in the language. Recovery is fine and explicit; *hiding* is the smell. A logged-and-swallowed error in a loop that should have aborted the batch is a corruption vector.

---

## Ownership & borrows — is it fighting the borrow checker?

Code that compiles can still be *clone-happy* — passing the borrow checker by copying instead of by design. This is where you distinguish a Rust author from a Rust *tourist*.

- **Needless clones.** *Smell:* `.clone()` sprinkled to "make the error go away," `x.clone()` immediately before `x` is dropped, cloning to pass to a function that only reads. *Question:* "Would a borrow work here, and if not, *why* not?" Most `.clone()` in a first draft is a borrow-checker surrender. The reviewer's job is to ask whether restructuring (borrow instead of move, split the borrow, reorder statements so NLL lets the borrow end) removes it. Trade-off: **a clone is not always wrong** — cloning an `Arc` (a refcount bump) is cheap and idiomatic; cloning to break a self-referential borrow is often the *right* simplification versus a lifetime-parameter explosion. The smell is the *unexamined* clone, not the clone.

- **`&String` / `&Vec<T>` / `&Box<T>` parameters.** *Smell:* a function signature taking `&String` or `&Vec<T>`. *Question:* "Does this function need the owned type's capabilities, or just to read?" Almost always the latter — so take `&str` / `&[T]`. The narrower type accepts strictly more callers (a `&str` argument works from `String`, `&str`, `Box<str>`, string literals) and communicates "I only read." This is a Rust API Guidelines rule (`C-GENERIC` / deref coercion). Same logic downward: return `String` not `&String`, and prefer `impl AsRef<Path>` over `&Path` for filesystem-ish APIs when it eases callers.

  ```rust
  pub fn count_hits(haystack: &str, needle: char) -> usize {  // not &String
      haystack.chars().filter(|&c| c == needle).count()
  }
  ```

- **Returning borrows with the wrong lifetime.** *Smell:* a function returning `&T` where the lifetime is tied to a local, or elaborate lifetime parameters added to force a borrow to compile. *Question:* "Is this borrow's lifetime a real relationship, or a workaround?" Returning a reference into `self` is fine and idiomatic (`fn name(&self) -> &str`). Returning a reference that forces the caller into contortions, or a `'static` bound bolted on to silence an error, is a design smell — the caller may actually want an owned value, or the data wants `Arc`/`Cow`. `Cow<'a, str>` is the honest answer when a function *sometimes* borrows and *sometimes* allocates.

- **`.to_owned()` / `.to_string()` spam.** *Smell:* converting to owned at the *start* of a function then only reading. *Question:* "Is the ownership taken because it's stored, or just to avoid a lifetime?" Store-owned is legitimate (a struct field). Owned-then-read is the same surrender as clone. Watch for `format!("{x}")` used where the value is already a `String`, and `.to_string()` on something already `Display`-formatted into a buffer.

---

## API design — will this survive contact with users?

Public API is the one thing you can't cheaply change later. Every `pub` is a promise; a reviewer's job is to shrink the promise to exactly what's intended. This category dominates the review of *library* crates.

- **Leaking internal / third-party types.** *Smell:* a `pub fn` returning `hashbrown::HashMap`, `reqwest::Error`, or your private `Inner` struct. *Question:* "Have I just made a dependency's version part of my public API?" Every third-party type in a public signature makes that crate a semver-coupled dependency: their major bump becomes yours. Wrap it (`pub struct MyError(#[from] reqwest::Error)`), return a trait (`impl Iterator<Item = ...>`), or expose your own type. Deviation: re-exporting a foundational type (`serde::Serialize`, `bytes::Bytes`) on purpose is fine — but that's a deliberate coupling, and the reviewer should confirm it's deliberate.

- **Missing `#[non_exhaustive]`.** *Smell:* a `pub enum` (especially an error enum) or a `pub struct` with all-public fields, no `#[non_exhaustive]`. *Question:* "Can I add a variant/field later without a major version bump?" Without it, adding an enum variant or struct field is a breaking change, because downstream code can exhaustively match or struct-literal-construct it.

  ```rust
  #[non_exhaustive]
  pub enum ConfigError {
      Missing(String),
      Invalid { key: String, reason: String },
  }
  ```

  Trade-off: `#[non_exhaustive]` costs *your own crate* nothing but forces *downstream* matches to carry a `_` arm and blocks struct literals (they must use a constructor). For a type that is genuinely closed and stable (an RGB color, a 2D point), omitting it is the right call — don't cargo-cult it onto everything.

- **Missing common trait derives.** *Smell:* a public value type with only `#[derive(Debug)]`, or none. *Question:* "What will a user reasonably want to do with this, and have I made it impossible?" The eager-derive rule (API Guidelines `C-COMMON-TRAITS`): derive `Debug` always; `Clone`, `PartialEq`, `Eq`, `Hash`, `PartialOrd`, `Ord` when they're semantically meaningful; `Default` for anything with a natural zero; `Copy` *only* for small, truly-value types (adding it later is fine, removing it is breaking). These can't all be added backward-compatibly by the user — they need the derive at the source.

  ```rust
  #[derive(Debug, Clone, PartialEq, Eq, Hash)]
  pub struct UserId(pub u64);
  ```

  Watch the trap: a hand-written `Hash` that disagrees with a hand-written (or derived) `Eq`, or a manual `Ord` that contradicts `PartialEq`, is a latent `HashMap`/`BTreeMap` corruption bug — deriving all of them together keeps them consistent by construction, which is another reason to prefer the derive.

- **`pub` over-exposure.** *Smell:* `pub` on a field, module, or fn that only the crate uses; `pub` structs with all fields `pub`. *Question:* "Does anything *outside* this crate actually need this, or would `pub(crate)` do?" Default to private, widen deliberately. All-public fields freeze your struct layout into the API and prevent you from ever adding an invariant. Prefer private fields + accessors, or a builder, when the type has any invariant to protect. `pub(crate)` / `pub(super)` express the real scope.

- **Missing sealed-trait pattern.** *Smell:* a `pub trait` used as a closed set of your own types (an internal enum-of-behaviors), with no seal. *Question:* "Do I intend downstream crates to implement this?" If not, seal it — otherwise you can never add a method without a breaking change, and users can create instances you didn't anticipate.

  ```rust
  mod sealed { pub trait Sealed {} }
  pub trait Encoding: sealed::Sealed {   // downstream can *use* but not *impl*
      fn tag(&self) -> u8;
  }
  pub struct Utf8;
  impl sealed::Sealed for Utf8 {}
  impl Encoding for Utf8 { fn tag(&self) -> u8 { 1 } }
  ```

  Trade-off: sealing removes an extension point; only seal traits that are yours to own. A trait *meant* for downstream implementation (like `std::io::Read`) must not be sealed.

---

## Error handling — does a failure carry its story?

Errors are data with a chain of causes. The review question is always: when this fires in production at 3am, does the message say *what* failed, *where*, and *why*?

- **Stringly-typed errors.** *Smell:* `Result<T, String>`, `Err(format!("..."))`, or `Box<dyn Error>` in a *library*. *Question:* "Can the caller match on this to recover, or can they only log it?" A `String` error is unmatchable — the caller can't distinguish "not found" from "permission denied" to react differently. Libraries return typed enums (hand-rolled or `thiserror`); applications, where the caller is a human reading logs, legitimately use `anyhow`/`Box<dyn Error>` because they only propagate and report. The `thiserror`-for-libs / `anyhow`-for-apps split is the standard heuristic.

- **Lost context (no source chain).** *Smell:* an error converted with `.map_err(|_| MyError::Failed)` that throws away the underlying cause. *Question:* "If this fails, will I know which file / which line / which upstream error?" Preserve the source so `Error::source()` chains it:

  ```rust
  #[derive(Debug)]
  pub enum LoadError { Io(std::io::Error), Parse { line: usize } }
  impl std::fmt::Display for LoadError {
      fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
          match self {
              LoadError::Io(_) => write!(f, "read failed"),
              LoadError::Parse { line } => write!(f, "parse error at line {line}"),
          }
      }
  }
  impl std::error::Error for LoadError {  // Error requires Debug + Display
      fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
          match self { LoadError::Io(e) => Some(e), LoadError::Parse { .. } => None }
      }
  }
  impl From<std::io::Error> for LoadError {
      fn from(e: std::io::Error) -> Self { LoadError::Io(e) }  // `?` now preserves the cause
  }
  ```

  With `anyhow`, the equivalent smell is a bare `?` where `.with_context(|| format!("loading {path}"))` would have added the one fact that makes the log actionable.

- **Panic-vs-`Result` boundary confusion.** *Smell:* `Result` returned for a programmer bug (a violated internal invariant), or `panic!`/`assert!` used for a runtime condition the caller could handle. *Question:* "Is this a *bug* (someone called it wrong) or an *expected failure* (the world said no)?" Programmer errors → panic/`debug_assert!` (fail loud, fail early). Environmental failures (I/O, parse, network) → `Result`. Mixing them means callers either can't recover from recoverable things or get panics for things they'd have handled. `assert!` for invariant checks in a hot path may need to be `debug_assert!` — but only if the invariant is truly internal.

- **`?` discarding type information.** *Smell:* `?` across a function boundary where the `From` conversion collapses distinct error types into one opaque variant. *Question:* "After this `?`, can the caller still tell *which* subsystem failed?" A single `AppError::Other(Box<dyn Error>)` catch-all reached by many `?` sites erases the taxonomy you built. Fine for leaf/application code; a smell in a library whose whole value is a precise error type.

---

## Concurrency — the bugs that don't reproduce

Rust prevents data races, not *deadlocks*, *logic races*, or *async footguns*. `Send`/`Sync` give a false sense of safety here. These are the hardest bugs to catch after merge, so they deserve disproportionate review time.

- **Guard held across `.await`.** *Smell:* `let g = mutex.lock().unwrap(); something(&g).await;` — a `std::sync::MutexGuard` (or `RwLockReadGuard` / `RwLockWriteGuard`) alive across an await point. *Question:* "Is a lock held while this task is suspended?" The task can be parked with the lock held, and if the same task needs the lock again (or the executor is single-threaded) you deadlock; even without deadlock you serialize the whole system on one lock across I/O latency. `clippy::await_holding_lock` catches the common case — confirm it's enabled. Fix: scope the guard to end before the `await` (drop it explicitly or use a block), extract the owned data first, or switch to `tokio::sync::Mutex` when the lock genuinely must span awaits (accepting its higher cost).

- **Lock ordering / deadlock.** *Smell:* two locks acquired in one code path, or a function that locks then calls a callback/method that also locks. *Question:* "If two threads take these locks in opposite orders, do they deadlock?" Establish and document a global lock order; a reviewer should be able to see that every acquisition path respects it. Re-entrant locking (locking a `Mutex` you already hold) has unspecified behavior in Rust — it will not return; it may deadlock or panic depending on the platform. `std::sync::Mutex` is not reentrant. The best fix is usually *fewer* locks: narrow the critical section, or restructure so only one lock is ever needed at a time.

- **`Arc<Mutex<T>>` where a channel fits.** *Smell:* shared mutable state behind `Arc<Mutex<_>>` used as a work queue or one-way hand-off. *Question:* "Is this shared *state*, or is it *communication*?" "Share memory by communicating" — if data flows one direction (producer → consumer), an `mpsc`/`watch`/`oneshot` channel is clearer, lock-free at the API level, and eliminates the lock-ordering question entirely. `Arc<Mutex>` is right for genuinely shared, read-write-by-many state (a cache, a registry). The smell is using it as a mailbox.

- **Atomic memory ordering.** *Smell:* `Ordering::Relaxed` on an atomic that guards other data, or `SeqCst` cargo-culted everywhere "to be safe." *Question:* "Does this ordering actually establish the happens-before this code relies on?" `Relaxed` guarantees atomicity but *no* ordering with respect to other memory — correct for a standalone counter, a bug for a flag that publishes data written before it (needs `Release`/`Acquire`). `SeqCst` is correct-but-pessimistic; it hides the author's intent about *what* synchronizes with what. Atomics are the deepest water in the review — when in doubt, the honest reviewer comment is "justify this ordering or use a `Mutex`."

- **Blocking in async.** *Smell:* `std::fs`, `std::thread::sleep`, a CPU-heavy loop, or a blocking DB driver called inside an `async fn`. *Question:* "Does this block the executor thread?" One blocking call stalls every other task sharing that worker thread — a throughput cliff that looks like a mysterious latency spike, not an error. Use the async equivalent (`tokio::fs`, `tokio::time::sleep`) or push the blocking work to `tokio::task::spawn_blocking`. CPU-bound work (parsing a huge blob, crypto) belongs on `spawn_blocking` or a `rayon` pool, never inline in a task.

---

## Performance — is it allocating in the hot path?

Only after a profiler points here — but some patterns are cheap to fix *in review* and expensive to fix later. Don't invent hot paths; do flag obvious waste in code that's already labeled hot. See the Rust Performance Book for the measured version of all of this.

- **Allocation in a hot loop.** *Smell:* `String::new()` / `Vec::new()` / `.collect()` *inside* a loop that runs per-item. *Question:* "Can this allocation be hoisted out and reused?" Allocate the buffer once before the loop and `.clear()` it each iteration; the capacity is retained, so steady-state allocations drop to zero. Trade-off: hoisting hurts readability and is pointless outside hot code — this is a *profiled-hot-path* rule, not a blanket one.

- **Collect-then-iterate-once.** *Smell:* `let v: Vec<_> = xs.iter().map(...).collect(); for x in &v { ... }` where `v` is used exactly once. *Question:* "Does this intermediate collection earn its allocation?" If you iterate it once and drop it, fuse the chain and skip the `Vec` entirely — iterators are lazy and this is free. Deviation: you *need* the `Vec` if you iterate twice, need `len()` up front, need to sort, or want to end a borrow before more work.

- **`format!` where `write!` fits.** *Smell:* `s.push_str(&format!("{x}"))` in a loop, or building a string by repeated `format!` + concatenation. *Question:* "Am I allocating a throwaway `String` per iteration?" `format!` allocates a fresh `String` every call; `write!(&mut buf, ...)` appends into an existing buffer with no intermediate allocation:

  ```rust
  use std::fmt::Write;
  pub fn join_ids(ids: &[u64]) -> String {
      let mut out = String::with_capacity(ids.len() * 8);
      for (i, id) in ids.iter().enumerate() {
          if i > 0 { out.push(','); }
          let _ = write!(out, "{id}");   // no per-item String allocation
      }
      out
  }
  ```

- **Unbounded growth.** *Smell:* a `Vec`/`HashMap`/cache/channel that only ever grows — a memoization map with no eviction, an unbounded `mpsc` channel. *Question:* "What bounds this in the worst case?" Unbounded channels turn backpressure into an OOM; caches without eviction are memory leaks with extra steps. The reviewer's question is simply "what stops this from growing forever," and "nothing" is a bug.

- **Missing `with_capacity`.** *Smell:* building a collection to a size you already know via repeated push. *Question:* "Do I know the final size here?" If yes, `Vec::with_capacity(n)` avoids the log-n reallocations of growth. Minor, but free when the size is in hand.

---

## Unsafe — is every `unsafe` block sound and necessary?

`unsafe` shifts a proof obligation from the compiler to the human. The review bar is the highest in the codebase: an unsound `unsafe` is a memory-safety CVE. See the Rustonomicon for the invariants each operation demands.

- **Missing `// SAFETY:` comment.** *Smell:* any `unsafe { ... }` block or `unsafe fn` without an adjacent comment. *Question:* "Does this comment state the invariant the caller/author must uphold, and argue that it *holds here*?" `clippy::undocumented_unsafe_blocks` enforces the presence, but it is allow-by-default (`restriction` group) — it must be turned on explicitly via `#![warn(clippy::undocumented_unsafe_blocks)]` or `[lints.clippy] undocumented_unsafe_blocks = "warn"` in `Cargo.toml`; `cargo clippy -- -D warnings` alone will not catch it. The reviewer enforces the *quality*. A `// SAFETY: it's fine` is worse than nothing. It must name the precondition (e.g. "`ptr` is non-null and points to `len` initialized `T`, guaranteed by the `Vec` we own above") so a future editor can re-check it.

- **Unsound public API over safe-looking signature.** *Smell:* a `pub fn` with no `unsafe` keyword that can nonetheless cause UB if called with certain safe inputs. *Question:* "Can a caller using only safe code trigger undefined behavior?" This is the cardinal sin — safe Rust must be *unable* to cause UB. If a function has preconditions the type system doesn't enforce, it must be `unsafe fn` (pushing the obligation to callers) or validate its inputs internally. A safe wrapper around `unsafe` must uphold every invariant for *all* inputs it accepts.

- **Avoidable `unsafe`.** *Smell:* `unsafe` used for a micro-optimization, or to bypass the borrow checker out of impatience. *Question:* "Is there a safe API that does this, and have we *measured* that it's too slow?" `get_unchecked` where `get` would do, `transmute` where `from_ne_bytes`/`bytemuck` exists, raw pointers where `Cell`/`RefCell`/split-borrow works. Unsafe for performance is legitimate *with a benchmark*; unsafe for convenience is a smell. Also flag `transmute` specifically — it's the most abused unsafe op and usually has a safe, typed alternative.

---

## Testing — do the tests defend behavior?

A test suite that passes tells you nothing unless the tests would *fail on a real bug*. Review tests as critically as code — a bad test is worse than none because it manufactures false confidence. Depth on TDD lives in `rust-testing`; here we review the *diff's* tests.

- **Missing edge and error cases.** *Smell:* tests that only exercise the happy path — one valid input, asserting success. *Question:* "Where are the tests for empty input, the boundary (0, 1, max, off-by-one), and the `Err` arm?" The happy path is the one that was *already* going to work. The value is in the empty slice, the overflow boundary, the malformed input that should return `Err` — and asserting on the *specific* error, not just `is_err()`.

- **Flaky / time- or order-dependent tests.** *Smell:* `sleep` to "wait for" something, assertions on wall-clock time, tests that depend on execution order or shared mutable global state, `HashMap` iteration order assumed stable. *Question:* "Will this pass deterministically on a loaded CI box, in parallel, in any order?" `cargo test` runs tests in parallel by default — a test touching shared state or the real clock is a future intermittent failure. Inject the clock, use channels/sync primitives instead of `sleep`, and isolate state per test.

- **Testing implementation instead of behavior.** *Smell:* a test asserting a private helper was called, a specific internal data structure's layout, or exact log strings. *Question:* "Would a legitimate refactor that preserves behavior break this test?" If yes, it tests plumbing, not contract — it will cry wolf on every refactor and train the team to ignore failures. Test the observable contract (inputs → outputs, state transitions, errors). Deviation: a genuinely load-bearing invariant (a security check *must* run) is worth a targeted test even if it touches internals.

- **No `#[should_panic]` / property coverage where warranted.** *Smell:* a documented panic condition or a parser/serializer with only example-based tests. *Question:* "Is the panic contract tested, and would `proptest`/round-trip testing find inputs I didn't think of?" Round-trip (`decode(encode(x)) == x`) and property tests catch the input space a human enumerates poorly.

---

## Style — let the tools do it

Style should be *automated*, so a human never spends review capital here. If you're leaving style comments by hand, the CI is misconfigured.

- **`clippy` not clean.** *Smell:* a PR with `clippy` warnings, or `#[allow(clippy::...)]` sprinkled without justification. *Question:* "Is CI running `cargo clippy -- -D warnings`, and does every `#[allow]` carry a comment saying *why*?" Clippy encodes a large fraction of this entire checklist — `await_holding_lock`, `redundant_clone` (its clone-elision lint; allow-by-default `nursery` group, so opt in explicitly), the warn-by-default `clone_on_copy` and `unnecessary_to_owned` that cover the `.to_owned()`/`.to_string()` spam case, `undocumented_unsafe_blocks`, and the `as` truncation lints. An un-justified `#[allow]` is the reviewable event — the allow itself may be hiding a real bug.

- **Naming conventions.** *Smell:* `getX()` getters, `SCREAMING` non-consts, `to_`/`as_`/`into_` prefixes used against convention. *Question:* "Do names follow the Rust API Guidelines?" `snake_case` fns/vars, `CamelCase` types/traits, `SCREAMING_SNAKE_CASE` consts; getters are `fn x()` not `fn get_x()`; `as_` = cheap borrow-to-borrow, `to_` = expensive/owning, `into_` = consuming conversion. These prefixes are a *contract* about cost — misusing them misleads callers about allocation.

- **Module boundaries.** *Smell:* a 2000-line `lib.rs`, a `utils` grab-bag module, or circular `use` between modules. *Question:* "Does the module structure reflect the domain, or is it a dumping ground?" Modules are the unit of privacy and the reader's map. A `utils` / `helpers` / `common` module is usually a smell that a concept wants a name. `rustfmt` handles layout; module *design* is a human judgment the reviewer owns.

- **Missing docs on public items.** *Smell:* a `pub fn`/`pub struct`/`pub trait` with no `///`, especially one that can panic or has preconditions. *Question:* "Would a user know how to call this correctly, and does the doc state the panic/error conditions?" Enable `#![warn(missing_docs)]` on libraries. A public function that can panic *must* document the panic in a `# Panics` section — that's part of its contract, not decoration. `# Errors` and `# Safety` sections likewise. Doctests double as compile-checked examples, so they earn their keep twice.

---

## Reviewer's severity triage

When time is short, ask in this order — stop when you find enough to send back:

| Ask first | Why it outranks the rest |
|---|---|
| Can safe code cause UB? (unsafe soundness) | Memory-safety CVE; irreversible once shipped |
| Can input reach a panic / overflow / bad slice? | Production crash or silent corruption from untrusted data |
| Is a lock held across `.await` / is there a lock-order cycle? | Deadlock that won't reproduce in review or often in CI |
| Does the `pub` API leak types / lack `#[non_exhaustive]` / derives? | Cheap now, a breaking-change migration later |
| Do errors carry a source chain and a matchable type? | Determines whether prod incidents are debuggable |
| Do tests fail on a plausible bug? | A green suite that proves nothing is negative value |
| Everything under Style | Automate it; don't spend human attention |

The meta-question behind the whole checklist: **is this decision reversible?** A `pub` signature, an unsafe invariant, and an on-disk/wire format are expensive to change — review them hard. A private function body is cheap to change later — don't gold-plate it. Spend review capital in proportion to the cost of being wrong.

---

## Sources

- The Rust Programming Language ("The Book") — https://doc.rust-lang.org/book/ (error handling, `panic!` vs `Result`, ownership)
- Rust API Guidelines — https://rust-lang.github.io/api-guidelines/ (`C-COMMON-TRAITS`, `C-GENERIC`, non-exhaustive, naming, sealed traits)
- The Rustonomicon — https://doc.rust-lang.org/nomicon/ (unsafe soundness, invariants)
- Rust Performance Book — https://nnethercote.github.io/perf-book/ (allocation, iterators, capacity)
- Tokio docs — https://docs.rs/tokio/ (async locks, `spawn_blocking`, blocking-in-async)
- `rust-clippy` lint rationale — https://rust-lang.github.io/rust-clippy/ (`await_holding_lock`, `undocumented_unsafe_blocks`, `redundant_clone`, `clone_on_copy`, `unnecessary_to_owned`, `as` casts)
- Rust Reference — https://doc.rust-lang.org/reference/ (overflow behavior, atomics/memory ordering, `#[non_exhaustive]`)
- Comprehensive Rust (Google) — https://google.github.io/comprehensive-rust/ (concurrency, `Send`/`Sync`, structured fundamentals)
- Cross-references: `rust-patterns` (idioms), `rust-testing` (TDD depth)

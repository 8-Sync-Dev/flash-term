# Testing & Benchmarking Strategy

Senior judgment for deciding *what* to test, *which* tool proves it, and *when* a
test is lying to you. Mechanics (RED-GREEN, `#[test]` syntax, `assert_eq!`, mockall
setup, CI YAML) live in the `rust-testing` ECC skill — this file assumes them and
goes to the decisions. Baseline: **Rust 1.96, edition 2024**; nightly-only tooling
is tagged inline.

## The one question: what is this test defending?

Every test costs maintenance forever. The bar for keeping one is: *it fails when a
plausible bug is introduced, and it does not fail for any other reason.* A test that
can only break when you deliberately break it — and cannot catch a real regression —
is negative-value: it slows edits, gives false confidence, and trains people to
`--force` past red.

Test **behavior, contracts, and invariants**, never the compiler's job:

| Don't test | Why | Test instead |
|---|---|---|
| Trivial getters / `Default` / derived `Clone` | The compiler already proves them; the test just mirrors the field list | The behavior that *reads* the field |
| A type's *shape* (that a struct has field `x`) | Refactor-hostile; passes for wrong code that keeps the shape | The observable output the field drives |
| That `serde` serializes a `#[derive(Serialize)]` type | You're testing serde, not your code | Your custom `impl`, `#[serde(...)]` attrs, and *round-trip* stability |
| Private helper internals directly | Couples tests to implementation; blocks refactors | The public method that calls them |
| That a function was *called* (over-mocking) | Tests the wiring you wrote, not the outcome | The state/output that the call produces |

The reason this matters: a test suite's value is *regression coverage per unit of
change-resistance*. Shape/getter/mock-call tests maximize change-resistance and
minimize regression coverage — exactly backwards. **When to deviate:** a getter with
real logic (unit conversion, lazy init, validation) *is* behavior — test it. And a
`Serialize` impl feeding a stable wire format or on-disk file deserves a snapshot
test precisely because an innocent field rename is a breaking change (see Snapshot).

## Unit vs integration: the boundary is the API surface, not the file size

Two distinct testing modes, chosen by *what surface you are exercising*, not by
convenience:

- **`#[cfg(test)] mod tests` inside the source file** — the only place you can reach
  private items. Use it when the thing worth testing is genuinely internal: a tricky
  parser state machine, an arithmetic invariant, a private normalization step. The
  `#[cfg(test)]` gate means the module (and its test-only deps) compile *only* under
  `cargo test`, so it costs nothing in release builds.
- **`tests/` directory** — each file is a *separate crate* that links your library as
  an external dependency. It can see *only* your public API, exactly as a downstream
  user does. This is the mode that actually verifies your public contract: if a
  `tests/` file needs `pub(crate)` internals to work, that's a design signal, not a
  reason to widen visibility.

The trade-off is compile cost and isolation: each `tests/*.rs` is its own binary, so
N integration files means N link steps — real time on large crates. The payoff is
that integration tests survive internal refactors (they only know the public surface)
while unit tests break, which is why **behavior that has a public entry point belongs
in `tests/`** and only the genuinely-internal logic belongs in `#[cfg(test)]`.
**When to deviate:** a single `tests/lib.rs` with `mod` submodules compiles as one
binary — collapse many integration files into it when link time dominates.

Shared integration helpers go in `tests/common/mod.rs` (the `/mod.rs` form), *not*
`tests/common.rs` — the latter is itself compiled as a test binary and will warn
about unused code and run zero tests.

## Doctests: executable documentation, not a coverage crutch

`///` examples are compiled and run by `cargo test --doc`. Their job is to prove the
*example a reader would copy actually works* — they are the one test guaranteed to
rot-check your public docs. That is their entire value proposition; they are a poor
tool for exhaustive branch coverage (awkward to assert error paths; note that in
edition 2024 rustdoc merges doctests into one binary, so the old per-doctest compile
cost is largely gone — except for `compile_fail`, explicit-edition, global-attribute,
or `standalone_crate` tests, which still compile standalone).

Default to the **`?`-returning doctest**: hide `main` scaffolding with `#` lines and
let the example read like real call-site code instead of an `.unwrap()` chain. A
failed `?` fails the doctest loudly.

```rust
/// Parses a `k=v` pair.
///
/// ```
/// # use mycrate::parse_kv;
/// # fn main() -> Result<(), std::num::ParseIntError> {
/// let (k, v) = parse_kv("port=8080")?;
/// assert_eq!((k, v), ("port", 8080));
/// # Ok(())
/// # }
/// ```
pub fn parse_kv(s: &str) -> Result<(&str, u32), std::num::ParseIntError> {
    let (k, v) = s.split_once('=').unwrap_or((s, ""));
    Ok((k, v.parse()?))
}
```

Fence annotations encode intent, and choosing wrong is a real bug:
- `no_run` — compiles (so the API is checked) but does not execute. For examples that
  hit the network, spawn threads, or need a running server. Overusing it is a smell:
  you've stopped *proving* the example.
- `ignore` — not even compiled. Almost always wrong; it silently rots. Prefer
  `no_run`, or `text` for non-Rust snippets.
- `compile_fail` — asserts the code *fails* to compile. Genuinely useful to document a
  type-level guarantee (e.g. "you cannot call `.build()` twice"), but brittle across
  compiler versions since the error is version-sensitive. Pin intent to the *fact* of
  failure, not the message.
- `should_panic` — documents a precondition violation.

**When to deviate:** for a heavily-tested internal algorithm, doctests add cost
without adding coverage — keep docs illustrative there and put the assertions in unit
tests. Doctests earn their keep on the *public surface*.

## Property-based testing: assert the law, let the tool hunt the counterexample

`proptest` and `quickcheck` generate hundreds of randomized inputs against a property
you state, then — the part that matters — **shrink** any failure to a minimal
counterexample (`proptest` shrinks structurally and persists the seed to
`proptest-regressions/` so the bug becomes a permanent regression test; `quickcheck`
shrinks via the `Arbitrary` trait but doesn't persist by default). Reach for it when
you can name a *law* that must hold for all inputs, not a specific input/output pair.

The three law-shapes where property testing repeatedly finds real bugs:

1. **Round-trip** — `decode(encode(x)) == x`. Catches boundary cases hand-written
   tests miss: empty input, max values, multi-byte UTF-8, `NaN`. This is the highest
   ROI property in practice.
2. **Invariant** — a property preserved by an operation: `sort` preserves length and
   multiset; a balanced tree stays balanced after insert; `a.merge(b).len() <= a.len()
   + b.len()`.
3. **Oracle** — a slow-but-obviously-correct reference agrees with your fast impl:
   your SIMD sum vs a naive fold; your custom hash map vs `std::collections::HashMap`.

```rust
// illustrative — needs the `proptest` dev-dependency
use proptest::prelude::*;
proptest! {
    #[test]
    fn decode_encode_roundtrip(v in prop::collection::vec(any::<u8>(), 0..64)) {
        prop_assert_eq!(decode(&encode(&v)).unwrap(), v);
    }
}
```

Trade-offs and failure modes: property tests are **non-deterministic in coverage** —
a green run does not mean the space is covered, only that N random draws passed. They
run slower and, done badly, encode a *tautology*: if your property re-implements the
function under test, it proves nothing. The discipline is to assert a law that is
*independent* of the implementation. **When to deviate:** if you cannot state a law
without restating the code, the function wants example-based tests instead.
`proptest` over `quickcheck` for new code — structural shrinking and regression
persistence are strictly better; `quickcheck`'s edge is a lighter, `Arbitrary`-driven
API.

## Snapshot testing (`insta`): for output too large to assert by hand

`insta` serializes a value (Debug, JSON, YAML, Ron) and, on first run, the assertion
fails and insta writes the proposed snapshot to a pending `.snap.new` file (default
`INSTA_UPDATE=auto` → `new` locally, `no` in CI). `cargo insta review` gives an
interactive accept/reject TUI that accepts it into the committed `.snap`; later runs
diff against that and fail on any change. The right target is **complex, structured,
human-reviewable output** where writing `assert_eq!` by hand is infeasible and the
*diff* is the assertion: pretty-printed ASTs, rendered templates, error-message
formatting, large API response bodies, CLI `--help` text.

Why it works: the review step turns "did the output change?" into a human decision,
so an *intended* change is a one-key accept and an *unintended* one is a visible diff
in the PR. The cost is exactly that human-in-the-loop: an unreviewed `cargo insta
accept` blesses garbage, and snapshots can hide semantic bugs behind
syntactically-plausible output. **When to deviate:** for a single scalar or a
three-field struct, a plain `assert_eq!` is clearer and reviewer-proof — snapshots
earn their keep only past the point where a human can't eyeball the literal. Use
redactions (`insta`'s `assert_json_snapshot!` with `{".timestamp" => "[ts]"}`) to
strip nondeterministic fields, or the snapshot becomes flaky.

## Fuzzing: for parsers and any untrusted-input boundary

`cargo-fuzz` drives libFuzzer (**nightly toolchain required** — libFuzzer needs
nightly codegen flags) with a coverage-guided loop: it mutates inputs and keeps those
that reach new code paths, running millions of iterations to find inputs that panic,
hang, or trip a sanitizer (ASan by default). `arbitrary` maps the raw `&[u8]` into
your structured types so you can fuzz typed APIs, not just byte slices.

```rust
// illustrative — fuzz_targets/parse.rs, built via `cargo +nightly fuzz run parse`
#![no_main]
use libfuzzer_sys::fuzz_target;
fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        let _ = mycrate::parse(s); // must never panic / loop / UB
    }
});
```

The mental model that decides *whether to fuzz*: fuzzing is for code that will meet
**adversarial or malformed input** — deserializers, protocol/media parsers, decoders,
anything downstream of a network socket or a file a user supplies. There the property
is trivial ("never panic, never UB, terminate") and the input space is too hostile for
examples or even proptest to cover. For pure business logic on trusted inputs, fuzzing
burns CPU for little; property tests are the better spend. **When to deviate up:**
`cargo fuzz` shines on `unsafe`/FFI parsing where a missed bound is memory-unsafety, not
just a wrong answer — pair it with ASan/MSan. Seed the corpus with real-world samples
and commit the crashing inputs as regression tests.

## Mocking vs designing for testability — prefer the design

`mockall` (`#[automock]` on a trait, then `expect_*().returning(...)`) generates a mock
that records and stubs calls. It is a legitimate tool, but reaching for it first is a
design smell. The senior default is **design so you don't need heavy mocks**: depend on
a small trait and inject a *real, simple fake* in tests. A hand-written fake is often
shorter than the mock setup, and — crucially — it tests *outcomes* (state after the
call) rather than *interactions* (that a method was called with args X), which is what
couples tests to implementation and makes every refactor a test rewrite.

Inject the *effect* behind a trait — clock, filesystem, network, randomness — so the
unit under test is deterministic:

```rust
pub trait Clock { fn now_millis(&self) -> u64; }

pub struct RateLimiter<C: Clock> { clock: C, last: u64, min_gap_ms: u64 }

impl<C: Clock> RateLimiter<C> {
    pub fn allow(&mut self) -> bool {
        let now = self.clock.now_millis();
        if now.saturating_sub(self.last) >= self.min_gap_ms {
            self.last = now; true
        } else { false }
    }
}

// Test injects a hand-written fake — no mock framework, tests behavior not calls:
#[cfg(test)]
mod tests {
    use super::*;
    struct FakeClock(std::cell::Cell<u64>);
    impl Clock for FakeClock { fn now_millis(&self) -> u64 { self.0.get() } }

    #[test]
    fn rejects_second_call_within_gap() {
        let mut rl = RateLimiter { clock: FakeClock(std::cell::Cell::new(1000)), last: 0, min_gap_ms: 100 };
        assert!(rl.allow());
        assert!(!rl.allow()); // no time elapsed
    }
}
```

Static dispatch (`<C: Clock>`) means the abstraction is *free* in release — the
production `SystemClock` monomorphizes away; don't assume that — prove it with
`cargo-show-asm`/`cargo asm`, where a truly zero-cost newtype, `PhantomData`, or ZST
token emits assembly identical to the raw primitive it wraps. Trade-off: a generic parameter leaks into
every signature that holds the limiter; if that spreads painfully, switch to `Box<dyn
Clock>` (one vtable indirection, erased type). **When `mockall` genuinely wins:** a
trait with many methods where each test cares about *one*, or when you must assert an
*interaction* that has no observable state (e.g. "we called `audit_log` exactly once")
— that is a call-count contract, and mocks express it directly.

## Async tests: control time and concurrency, never sleep

`#[tokio::test]` wraps a test in a runtime (defaults to a current-thread runtime;
`#[tokio::test(flavor = "multi_thread", worker_threads = 2)]` for genuine parallelism).
The senior discipline is **making async tests deterministic**:

- **Never `sleep` to wait for something.** A real sleep makes tests slow *and* flaky
  (it races the machine's load). For time-dependent logic, use `tokio::time::pause()`
  and `advance(Duration)` to move a *virtual* clock instantly and deterministically —
  a 30-second timeout test runs in microseconds. Requires the runtime's `test-util`.
- **Test timeouts as a contract:** wrap the operation in `tokio::time::timeout(dur,
  fut)` and assert it errors — but with paused time, so it is instant.
- **Synchronize with the actual signal** — a `oneshot`/`Notify`/`Barrier` — not a
  hoped-for delay, when coordinating spawned tasks.

```rust
// illustrative — needs tokio with `test-util`, `time` features
#[tokio::test(start_paused = true)]
async fn fires_after_delay() {
    let handle = tokio::spawn(async { tokio::time::sleep(std::time::Duration::from_secs(30)).await; 42 });
    tokio::time::advance(std::time::Duration::from_secs(30)).await; // instant
    assert_eq!(handle.await.unwrap(), 42);
}
```

Trade-off: paused time only advances when *you* advance it, so a test that forgets to
`advance` past a real `.await` on a timer will hang — the price of determinism is
explicit control. **When to deviate:** true end-to-end tests against a real server or
DB need `multi_thread` and real time; keep those few, mark them slow, and put the bulk
of coverage in time-controlled unit tests.

## Determinism & isolation: the anti-flakiness contract

A flaky test is worse than no test — it trains the team to ignore red. The root causes
and their fixes:

- **Shared global state** (a `static`, an env var, a process-wide singleton, the
  current directory): parallel `cargo test` runs tests on multiple threads, so two
  tests mutating the same global collide nondeterministically. Fix the design first
  (pass state in); if the state is irreducibly global, annotate the colliding tests
  with `#[serial_test::serial]` so they run one-at-a-time. Reserve `serial` for that —
  serializing everything throws away Rust's free test parallelism.
- **Wall-clock / randomness / ordering**: inject them (see testability, above). Assert
  on `HashMap` contents as a *set*, never iteration order (it's randomized by design).
- **Ports / temp files**: bind port `0` and read back the assigned port; use `tempfile`
  for unique dirs. Never hardcode `/tmp/mytest` — two runs collide.
- **`#[ignore]`** for tests too slow/environmental for the default run; opt in with
  `cargo test -- --ignored`. This is quarantine, not a fix — track it down.
- **Profile-dependent asserts**: a `#[should_panic(expected = "overflow")]` test on
  arithmetic overflow passes only in debug — release wraps silently unless
  `overflow-checks = true` — so gate it on `cfg(debug_assertions)` or assert with
  `checked_mul` returning `None`, rather than trusting the panic to fire.

## Fixtures & builders: defaults with per-test overrides

The maintainability win is the **builder that sets sensible defaults and lets each test
override only the one axis it cares about**. Without it, every test restates the full
constructor, and adding a field means editing every test — so tests stop being written.

```rust
pub struct OrderBuilder { order: Order }
impl OrderBuilder {
    pub fn new() -> Self { Self { order: Order { id: 1, qty: 1, paid: true } } }
    pub fn qty(mut self, qty: u32) -> Self { self.order.qty = qty; self }
    pub fn unpaid(mut self) -> Self { self.order.paid = false; self }
    pub fn build(self) -> Order { self.order }
}
// A test names only what matters; irrelevant axes stay at defaults:
// let o = OrderBuilder::new().unpaid().build();
```

The payoff is that a new field with a sensible default touches *one* line (the builder)
and no test at all. `rstest`'s `#[fixture]` gives the same leverage for
dependency-injected fixtures with `#[case]` parameterization. Trade-off: a builder is
code to maintain — for a two-field struct it's overkill; introduce it at the point where
constructor churn starts hurting, not before.

## Coverage is a signal, not a target

`cargo llvm-cov` (LLVM source-based coverage; more accurate than the old gcov path)
reports line and region coverage on stable; branch coverage requires
`cargo llvm-cov --branch` on **nightly** (unstable `-Z coverage-options=branch`).
Read it as a **flashlight for untested behavior**,
not a KPI. Goodhart's law applies hard here: the instant a number becomes a gate,
people write assertion-free tests that *execute* code to bump the percentage, and
coverage stops correlating with correctness. 100% line coverage with weak assertions is
worse than 70% with sharp ones — it *looks* safe.

Chase *branch* coverage over line: a function can show 100% line coverage while half
its `if`/`match` arms — the error and negative paths — never execute, so region/branch
coverage is the honest number. Triage the gaps by risk (low-coverage × high-risk is the
only quadrant that demands a test now) and pair coverage with Miri, which finds UB in
the code that *is* covered — coverage surfaces blind spots but never proves the covered
code correct.

Use it to *find the gap and ask why*: an untouched `match` arm is either dead code
(delete it) or an untested path (test it) — both are actions coverage surfaced. Chasing
the last 15% usually means testing error paths that need fault injection; often the
honest answer is "this branch is defensive and unreachable — mark it and move on," not a
contrived test. **When a threshold helps:** as a *ratchet* in CI (fail if coverage
*drops*) it prevents silent erosion without inviting gaming as hard as an absolute
floor.

## Benchmarking: measure the work, not the optimizer

`criterion` (stable; the built-in `#[bench]` harness is **nightly-only** and effectively
frozen — do not use it for new work) runs a function many times, discards warm-up, and
does statistical analysis with outlier detection and regression-vs-previous-run
reporting. The hard part of benchmarking is not the harness — it's **not measuring the
wrong thing**:

- **`std::hint::black_box`** is mandatory around inputs and results. Without it, LLVM
  sees the computed value is unused and *deletes the entire computation* (dead-code
  elimination) or const-folds a literal input at compile time — you then "benchmark" an
  empty loop and celebrate a 0.1ns fibonacci. `black_box` is an opaque barrier that
  forces the compiler to assume the value is used and not known. Wrap the input so it
  isn't const-folded, and the output so it isn't DCE'd.
- **Statistical noise**: a laptop on battery with thermal throttling and a browser open
  produces swings larger than the change you're measuring. Criterion reports confidence
  intervals for exactly this reason — trust the *interval overlap*, not a single median.
  Pin CPU frequency / run on a quiet machine for anything you'll act on.
- **Micro vs macro**: a microbenchmark of one function can improve while the whole
  program regresses (cache effects, inlining decisions change at scale). Micro-optimize
  only what a *profiler* (see the performance reference) flagged as hot.

```rust
// illustrative — benches/bench.rs, `harness = false` in Cargo.toml
use criterion::{criterion_group, criterion_main, Criterion};
use std::hint::black_box;
fn bench(c: &mut Criterion) {
    c.bench_function("parse", |b| b.iter(|| parse(black_box("port=8080"))));
}
criterion_group!(benches, bench);
criterion_main!(benches);
```

Trade-off: criterion runs are *slow* (it wants many samples for statistical power) — too
slow for every-commit CI. Run benchmarks on demand or nightly, save the baseline
(`--save-baseline`), and compare against it. **When to deviate:** for a quick one-off "is
A faster than B" you don't need criterion's statistics — `divan` is a lighter harness
for such dev-loop checks (still `black_box` inputs/outputs) — but never trust a single `Instant::now()`
delta as evidence for a real decision; it's dominated by noise.

## Compile-fail tests (`trybuild`): proving what must *not* compile

For proc-macros and type-level API guarantees, half the contract is **what the compiler
should reject**. `trybuild` compiles `tests/ui/*.rs` files and diffs the *actual*
compiler output against a committed `.stderr` — so you assert "this misuse produces this
error." This is the only way to test that a `#[derive]` rejects an invalid attribute, or
that a typestate builder makes `.build()`-before-`.required()` a *compile* error rather
than a runtime panic.

```rust
// illustrative — tests/compile_fail.rs
#[test]
fn ui() {
    let t = trybuild::TestCases::new();
    t.compile_fail("tests/ui/*.rs"); // each .rs has a matching .stderr
}
```

The unavoidable trade-off: `.stderr` snapshots are **compiler-version-sensitive** —
diagnostic wording changes between releases and the test breaks on a toolchain bump even
though your code is fine. Manage it by pinning the MSRV those tests run under (run them
in one dedicated CI job, not the matrix) and regenerating with `TRYBUILD=overwrite` on
intended changes. **When to use it:** macro crates and typestate APIs, where "rejects
bad input at compile time" *is* the feature. For ordinary libraries it's overkill —
`compile_fail` doctests cover the occasional "this shouldn't compile" note more cheaply.

## Feature combinations break silently — verify them

A `#[cfg(feature = "...")]` guarding a mistyped feature name compiles to *nothing*, and
default-feature-only `cargo test` never exercises `--no-default-features` — so a crate
can ship a feature that has never once compiled. For any crate with 2+ features, run
`cargo hack check --each-feature --no-dev-deps` in CI to compile each feature in
isolation. Reserve `--feature-powerset` (every combination) for small core libraries
under ~8 features — it is `2^n` and impractical above that.

## Cross-references

- **RED-GREEN-REFACTOR mechanics, `#[test]`/`assert_eq!`/`rstest` syntax, mockall setup,
  CI YAML** → `rust-testing` ECC skill (don't restate it; this file is the judgment layer).
- **Profiling before you benchmark, allocation/`black_box` at scale** → `performance` reference.
- **Designing traits for injection, static vs dynamic dispatch trade-offs** → `traits-generics` reference.
- **`unsafe`/FFI correctness that fuzzing + Miri/sanitizers must guard** → `unsafe-rust` reference.

Sources: The Rust Programming Language (Ch. 11 Testing, Ch. 14 doctests); Rust API
Guidelines (docs/examples, `#[non_exhaustive]`); Rust Reference (`#[cfg(test)]`, test
harness); rustc book (`--test`, doctest fences); Rust Performance Book (benchmarking,
`black_box`); Tokio docs (`tokio::test`, `time::pause`/`advance`, `test-util`); crate
docs for `proptest`, `insta`, `cargo-fuzz`/`arbitrary`, `mockall`, `serial_test`,
`rstest`, `criterion`, `cargo-llvm-cov`, `trybuild`.

Microsoft RustTraining: rust-patterns-book Ch. 14 (overflow-check gating, trait fakes
for DI) — https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch14-testing-and-benchmarking-patterns.md;
type-driven-correctness-book Ch. 14 (testing type-level guarantees, zero-cost proof via
cargo-show-asm) — https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch14-testing-type-level-guarantees.md;
engineering-book Ch. 3 (benchmarking, Divan) — https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch03-benchmarking-measuring-what-matters.md,
Ch. 4 (branch coverage vs line) — https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch04-code-coverage-seeing-what-tests-miss.md,
Ch. 9 (feature verification with cargo hack) — https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch09-no-std-and-feature-verification.md.

---
name: clouds-rust
description: Senior Rust engineering skill — a judgment-first knowledge base for designing, implementing, reviewing, optimizing, and hardening production Rust. Covers ownership/borrowing/lifetimes, traits & generics, collections/iterators/closures/smart pointers, async/await, idiomatic Rust, error design, project & workspace architecture, concurrency & lock-free patterns, performance & memory layout, unsafe/Pin/FFI/no_std, testing & benchmarking, tooling/CI/observability/release, a code-review checklist, an anti-pattern catalog, algorithm-implementation style, and senior interview knowledge. Enforces a memory-model gate (shared XOR mutable), a stability gate (stable vs nightly, MSRV, edition 2024), a measure-first performance discipline, and an unsafe-soundness gate. Composes with `rust-patterns`, `rust-testing`, `clouds-tauri`, and `impeccable`. Use whenever the task is Rust: writing, reviewing, refactoring, architecting, debugging, optimizing, or learning it. Prefer official docs on conflict; explain WHY a pattern is idiomatic, not only how.
---

# clouds-rust

## Role

`clouds-rust` is a senior Rust engineer skill. It exists so an agent can make the
**architectural and implementation decisions** a Rust engineer who ships production code
makes — not merely emit syntax.

Primary capabilities:

- Read Rust code and identify the ownership model, error strategy, concurrency model, and
  `unsafe` surface before changing anything.
- Choose between the real alternatives Rust forces on you — static vs dynamic dispatch, `Rc`
  vs `Arc` vs borrow-restructure, threads vs async, generics vs `dyn`, enum vs trait object —
  and justify the choice by its trade-off.
- Diagnose the failure classes specific to Rust: borrow-checker fights, lifetime errors,
  `Send`/`Sync` errors, held-guard-across-`.await`, deadlocks, allocation storms, and unsound
  `unsafe`.
- Apply the smallest correct change, idiomatically, and verify it compiles and behaves.

**Baseline: Rust 1.96 (2026-06), edition 2024.** Every claim is written against this. When a
feature is nightly, edition-specific, or MSRV-sensitive, the reference file says so. Re-verify
stability before assuming a nightly pattern is available.

---

## The mental model (read before anything else)

Six ideas. Almost every Rust mistake is a violation of one of them.

**1. Memory safety is a compile-time proof resting on "shared XOR mutable".** At any instant a
value has either any number of `&T` or exactly one `&mut T` — never both. Moves make double-free
unrepresentable; the outlives rule makes use-after-free unrepresentable; shared-XOR-mutable makes
data races and iterator invalidation unrepresentable. When a design fights the borrow checker,
the fix is to restructure so the rule is *locally obvious* — not to reach for `.clone()` or
`Rc<RefCell<_>>`. NLL is the model in effect; pre-NLL workarounds are historical noise.

**2. Zero-cost abstractions are a promise with an asterisk.** Generics and iterators monomorphize
to code as fast as hand-written loops — that is real. But `dyn` costs a vtable indirection, `Box`
costs an allocation, and bounds checks cost a compare-and-branch until the compiler proves them
redundant. "Zero-cost" means *no cost you could have avoided by hand*, not *free*. Know which
abstraction is actually free and which you are paying for.

**3. `Send`/`Sync` are the type system's concurrency proof, and they are inferred.** A type is
`Send` if it is safe to move to another thread, `Sync` if `&T` is safe to share. `Rc`, `RefCell`,
and `MutexGuard` are deliberately not both. Fearless concurrency is exactly this: the compiler
refuses to compile the data race. You extend the proof by choosing `Arc`/`Mutex`/atomics, not by
suppressing it.

**4. Errors are part of your API.** A library's error *type* is a compatibility contract:
`thiserror` enums (typed, `#[non_exhaustive]`) for libraries, `anyhow`/`eyre` (context chains)
for binaries. `panic!` is for broken invariants and unreachable states, not for expected failure.
Stringly-typed errors and `.unwrap()` in library code are defects, not shortcuts.

**5. Measure before optimizing, and know which layer you are paying.** Allocation, indirection,
cache misses, and lock contention have different fixes and different tools (criterion, `perf`,
`samply`, flamegraphs). Optimizing the wrong one is the standard wasted week. Intuition about
Rust performance is frequently wrong; a benchmark is not.

**6. `unsafe` narrows, it does not disable.** `unsafe` grants five specific superpowers; the
borrow checker still runs. Every `unsafe` block carries a `// SAFETY:` note stating the invariant
that makes it sound, and wraps into a safe public API. *Unsound* (a safe API that can trigger UB)
is a bug of a different, worse kind than *unsafe*. Most `unsafe` in application code is premature
and removable.

---

## Content contract — how knowledge is written here

This skill is **not a documentation mirror**. The Book, the Reference, std docs, and the
Rustonomicon already exist and are better at being documentation. What an agent cannot get there
is engineering judgment — so that is the only thing stored here.

Every substantive guidance block in `references/` carries, in prose:

1. **Mechanism** — how it actually works, with exact type/API names.
2. **Why** — the problem it solves; why it is *idiomatic*, not only how it works.
3. **Trade-off** — what you give up (every choice costs something).
4. **When to deviate** — the conditions under which the recommendation is wrong.

Stability is explicit: stable vs nightly/experimental, edition- and MSRV-sensitivity, and
deprecated patterns flagged with their modern replacement. Self-contained examples are
compile-checked against the baseline toolchain; fragments needing external crates are marked
`// illustrative`.

PROHIBITED: API dumps without reasoning, syntax-only examples, restating the Book, undated
nightly claims. Self-check before extending: *could a competent engineer defend a decision in
review from this section alone?* If it only says what to type, add the reasoning or cut it.

---

## Mandatory rules

**1. Inspect before changing.** Read `Cargo.toml` (edition, MSRV/`rust-version`, features,
deps), the module tree and `pub` surface, the error type(s) in use, and the concurrency model
before proposing anything. Guessing any of these produces confidently wrong advice.

**2. Memory-model gate.** Resolve borrow/lifetime problems by restructuring ownership so
"shared XOR mutable" is locally obvious. Reach for `.clone()`, `Rc<RefCell<_>>`, or an extra
lifetime only after the restructure is shown not to fit — and say why. See `references/fundamentals.md`.

**3. Stability gate.** Use stable features by default. Any nightly/experimental feature is
called out explicitly with its tracking status and the stable alternative. Respect the project's
declared MSRV and edition; do not silently raise them.

**4. Error-as-API discipline.** Library errors are typed (`thiserror`, `#[non_exhaustive]`),
application errors carry context (`anyhow`/`eyre`). No `unwrap`/`expect` in library paths without
a proven invariant and a reason string. `panic!` only for broken invariants. See `references/best-practices.md`.

**5. Concurrency gate.** Any change touching threads or async answers `Send`/`Sync`, lock
ordering, and "is a guard/`Rc`/non-`Send` value held across `.await`". Prefer a channel or `rayon`
over `Arc<Mutex<_>>` when the shape fits. See `references/concurrency.md` and `references/async.md`.

**6. Measure before optimizing.** No performance change lands on intuition. Benchmark
(`criterion`/`divan`) or profile (`perf`/`samply`/flamegraph) first, change one thing, re-measure.
Attribute the cost to allocation / indirection / cache / contention before touching it. See
`references/performance.md`.

**7. Unsafe-soundness gate.** Every `unsafe` block gets a `// SAFETY:` comment stating the upheld
invariant, minimal scope, and a sound safe wrapper. Prefer removing `unsafe` over commenting it.
Validate with Miri where feasible. See `references/unsafe-rust.md`.

**8. Minimal, reversible diffs; keep conventions.** Do not restructure a working module layout,
swap an error crate, or introduce an abstraction the task did not ask for. Match the project's
existing naming, error type, and module style.

**9. Verification is required and real.** `cargo check`/`clippy -D warnings`/`test` for the
change; `cargo bench` for a perf claim; Miri for an `unsafe` change. Exercise the path that
changed. If something could not be verified, say so and name it.

**10. UI changes go through `impeccable`.** For a Rust GUI/TUI (egui, iced, ratatui, Tauri
frontend, Dioxus/Leptos), load `~/.agents/skills/impeccable/SKILL.md` for visual craft; a Tauri
app additionally loads `clouds-tauri`.

---

## Priority order (conflict resolution)

1. Direct requirements of the current task.
2. Project rules (`AGENTS.md`, repo conventions) and existing implementation patterns.
3. This skill's mandatory rules and mental model.
4. Official Rust docs for the pinned toolchain (Book, Reference, std, Nomicon, API Guidelines).
5. Community practice, explicitly labelled as such.
6. General engineering best practice.

Official docs beat blog posts. Observed behaviour in the real codebase beats docs — record the
discrepancy. On residual uncertainty, choose the lower-blast-radius option and state the assumption.

---

## Standard workflow

1. Read the task; name the target outcome, scope, and explicit non-goals.
2. Inspect per Rule 1 (edition, MSRV, deps, module surface, error type, concurrency model).
3. Route to the reference(s) for the domain (tables below); read only what the decision needs.
4. Identify the smallest correct change and name its trade-off.
5. Check it against the gates that apply: memory-model (2), stability (3), error (4),
   concurrency (5), performance (6), unsafe (7), UI (10).
6. Implement, matching existing conventions.
7. Verify for real (Rule 9); exercise the changed path.
8. Report: what changed, why, the trade-off accepted, how it was verified, what was not.

---

## Routing

### By task type

| Task | Primary | Secondary |
| --- | --- | --- |
| Ownership / borrow / lifetime problem | `references/fundamentals.md` | `references/anti-patterns.md` |
| Trait / generic / dispatch design | `references/traits-generics.md` | `references/architecture.md`, `references/idioms.md` |
| Choosing a collection / iterator / smart pointer | `references/collections-iterators.md` | `references/performance.md` |
| Async / await, futures, runtime choice | `references/async.md` | `references/concurrency.md`, `references/anti-patterns.md` |
| "Make this idiomatic" | `references/idioms.md` | `references/anti-patterns.md`, `rust-patterns` |
| Macro authoring / metaprogramming | `references/macros.md` | `references/traits-generics.md`, `references/anti-patterns.md` |
| Error handling / error type design | `references/best-practices.md` | `references/fundamentals.md` |
| Project structure / crate split / workspace | `references/architecture.md` | `references/tooling.md` |
| Public API design | `references/architecture.md` | `references/idioms.md`, `api-and-interface-design` |
| Concurrency / threads / channels / locks | `references/concurrency.md` | `references/async.md`, `references/anti-patterns.md` |
| Lock-free / atomics / memory ordering | `references/concurrency.md` | `references/performance.md`, `references/unsafe-rust.md` |
| Performance / optimization / memory layout | `references/performance.md` | `references/collections-iterators.md`, `references/tooling.md` |
| `unsafe` / raw pointers / `MaybeUninit` | `references/unsafe-rust.md` | `references/performance.md` |
| Pin / self-referential types | `references/unsafe-rust.md` | `references/async.md` |
| FFI / `extern "C"` / bindings | `references/unsafe-rust.md` | `references/architecture.md` |
| `no_std` / embedded / wasm / cross-platform | `references/unsafe-rust.md` | `references/tooling.md` |
| Testing strategy / property / fuzz / bench | `references/testing.md` | `rust-testing`, `references/tooling.md` |
| Tooling / clippy / CI / release / observability | `references/tooling.md` | `references/best-practices.md` |
| Code / PR review | `references/code-review-checklist.md` | the reference for the domain touched |
| Algorithm / data-structure implementation | `references/algorithms.md` | `references/collections-iterators.md`, `references/performance.md` |
| Interview prep / concept refresher | `references/interview-knowledge.md` | the relevant deep-dive reference |

### By symptom / compiler error

Symptoms route faster than topics when someone is reporting an error.

| Symptom / message | Cause class | Go to |
| --- | --- | --- |
| `cannot borrow ... as mutable ... also borrowed as immutable` | Shared-XOR-mutable violation | `references/fundamentals.md` §Borrowing |
| `borrowed value does not live long enough` / lifetime errors | Reference outlives referent, or missing annotation | `references/fundamentals.md` §Lifetimes |
| `` `T` cannot be sent between threads safely `` / `Sync` errors | `Send`/`Sync` boundary | `references/concurrency.md` §Send/Sync |
| Future is not `Send` / "held across await" | Non-`Send` value or guard across `.await` | `references/async.md`, `references/anti-patterns.md` |
| `already borrowed: BorrowMutError` (runtime panic) | `RefCell` aliasing at runtime | `references/collections-iterators.md` §interior mutability |
| Deadlock / program hangs under load | Lock ordering / guard held too long | `references/concurrency.md`, `references/anti-patterns.md` |
| `the trait ... is not object-safe` | `dyn` on a non-object-safe trait | `references/traits-generics.md` §object safety |
| `conflicting implementations` / orphan-rule error | Coherence | `references/traits-generics.md` §coherence, newtype |
| Slow / high-allocation hot path | Allocation / clone storm | `references/performance.md`, `references/anti-patterns.md` |
| Undefined behaviour / Miri failure | Unsound `unsafe` | `references/unsafe-rust.md` |

### Keyword triggers

`rules/*.mdc` hold the fast guardrails. Load the matching one before acting.

| Keyword | Rule file | Behaviour |
| --- | --- | --- |
| `unsafe`, `raw pointer`, `transmute`, `FFI`, `Pin`, `UB`, `Miri` | `rules/unsafe-keyword.mdc` | Soundness first; `// SAFETY:` on every block; prefer removing unsafe; Miri-verify |
| `performance`, `slow`, `optimize`, `allocation`, `bench`, `profile` | `rules/performance-keyword.mdc` | Measure → attribute the layer → change one thing → re-measure |
| `concurrency`, `async`, `thread`, `deadlock`, `Send`, `Sync`, `lock`, `race` | `rules/concurrency-keyword.mdc` | Prove Send/Sync + lock order; never hold a guard across `.await` |
| `review`, `PR`, `audit` | `rules/review-keyword.mdc` | Walk the checklist; report every real finding with severity; do not pre-filter |
| `unwrap`, `panic`, `error`, `Result`, `thiserror`, `anyhow` | `rules/error-keyword.mdc` | Error-as-API; typed for libs, context for bins; no unwrap in lib paths |

---

## Composition with other skills

- **`rust-patterns`** / **`rust-testing`** (ECC) — baseline idioms and TDD mechanics. This skill
  goes deeper: senior judgment, trade-offs, architecture, pitfalls. Cross-reference, don't restate.
- **`clouds-tauri`** — Tauri desktop apps. That skill owns the Tauri-specific Rust layer (IPC,
  capabilities, the WebView boundary); this one owns general Rust craft below it.
- **`clouds-f`** — if a Rust web backend serves a JS/React frontend, clouds-f owns the frontend.
- **`impeccable`** — mandatory for any visible Rust GUI/TUI change (egui, iced, ratatui, Dioxus,
  Leptos, Tauri frontend). It owns visual craft; this skill owns correctness and idiom.
- **`ponytail`** — write-less/reuse/delete. In Rust: don't add a crate for three lines std already
  does, don't reach for `unsafe`/lock-free/generics you can't justify, don't reimplement std.
- **`api-and-interface-design`** / **`api-design`** — general API design; `references/architecture.md`
  holds the Rust-specific API-guideline judgment.

---

## File map

```
clouds-rust/
├── SKILL.md                          # you are here — router, rules, mental model, content contract
├── references/
│   ├── fundamentals.md               # ownership, borrowing, lifetimes, matching, error mechanics, modules
│   ├── traits-generics.md            # traits, generics, dispatch, coherence, object safety, GATs, RPITIT
│   ├── collections-iterators.md      # collections, iterators, closures, smart pointers, interior mutability
│   ├── async.md                      # Future/poll model, executors, cancellation, structured concurrency
│   ├── idioms.md                     # the idioms that make code idiomatic, each with its why
│   ├── macros.md                     # macro_rules! + proc/derive/attribute macros: when, hygiene, syn/quote
│   ├── best-practices.md             # error design, panic boundary, semver, docs, security baseline
│   ├── architecture.md               # module org, crate splitting, workspaces, API design, type-driven design
│   ├── concurrency.md                # Send/Sync, threads, channels, atomics/ordering, rayon, lock-free
│   ├── performance.md                # measure-first, zero-cost limits, memory layout, allocation, build tuning
│   ├── unsafe-rust.md                # unsafe soundness, UB catalog, raw ptrs, Pin, FFI, no_std, cross-platform
│   ├── testing.md                    # what to test, property/snapshot/fuzz, mocking-vs-traits, bench correctness
│   ├── tooling.md                    # cargo, clippy, MSRV, cargo-deny/audit, tracing, CI/CD, release
│   ├── code-review-checklist.md      # the checklist a reviewer opens during a PR, grouped by concern
│   ├── anti-patterns.md              # symptom → cause → fix catalog of what not to do
│   ├── interview-knowledge.md        # senior concept questions with model answers (doubles as refresher)
│   └── algorithms.md                 # idiomatic algorithm/data-structure implementation style
└── rules/
    ├── unsafe-keyword.mdc
    ├── performance-keyword.mdc
    ├── concurrency-keyword.mdc
    ├── review-keyword.mdc
    └── error-keyword.mdc
```

---

## Extending this skill

Add knowledge only if it passes the content contract: mechanism + why + trade-off + when-to-deviate,
stability-stamped, with a compile-checked or `// illustrative`-marked example. A fact lives in exactly
one reference file; other files link to it and never re-explain it. If official Rust changes (new
stable feature, edition, deprecation), update the affected file and re-stamp the baseline.

# Performance Optimization

Measure-first performance engineering for Rust: what actually costs, how to prove it, and when to stop. Baseline: Rust 1.96, edition 2024. Cross-references the [Rust Performance Book](https://nnethercote.github.io/perf-book/); this file is the judgment layer, not a mirror.

## The only rule that matters: measure first

Intuition about Rust performance is wrong often enough that acting on it is a bug generator. The compiler (LLVM backend) does aggressive inlining, loop unrolling, autovectorization, and dead-code elimination; the "obvious" hot spot in the source is frequently free after optimization, and the real cost is somewhere you didn't look (an allocator call, a `Drop` glue chain, a cache miss, a mispredicted branch). So the discipline is fixed:

1. **Profile** a release build under a representative workload to find where time actually goes.
2. **Benchmark** the specific function you intend to change, so you have a number to beat.
3. Change one thing.
4. **Re-benchmark.** Keep the change only if the number moved and the win survives noise.

Everything below is a menu of techniques. None of them is worth applying without a measurement bracketing the change. "This should be faster" is not a reason to merge; "this is 1.8× faster on the benchmark, verified" is.

### Always profile a release build

`cargo build`/`cargo test` are `opt-level = 0` — up to an order of magnitude slower and with none of the optimizations that change *which* code is hot. Profiling a debug build tells you about debug builds and nothing about production. Profile `--release` (or a dedicated profile, below). To keep symbols in release for the profiler:

```toml
# illustrative — Cargo.toml
[profile.release]
debug = 1          # line tables; keeps symbol names for perf/samply without full -g cost
```

### Benchmarking: prove the delta

`#[bench]` is nightly-only and effectively frozen — do not use it on stable. Use a harness that controls for noise and defeats the optimizer's tendency to delete work whose result is unused:

| Tool | When |
|---|---|
| **criterion** | Default choice. Statistical analysis, outlier detection, regression tracking across runs, plots. Heavier compile/run time. |
| **divan** | Lighter, faster to write, good for many small micro-benchmarks; less statistical machinery. |

The load-bearing detail is `black_box`: without it the optimizer can constant-fold your benchmark input or eliminate a pure computation whose result is discarded, and you measure nothing. Feed inputs through `std::hint::black_box` (stable) and return/`black_box` the result.

```rust
// illustrative — benches/bench.rs (needs criterion dev-dependency)
use criterion::{criterion_group, criterion_main, Criterion};
use std::hint::black_box;

fn bench_parse(c: &mut Criterion) {
    let input = std::fs::read_to_string("fixtures/big.json").unwrap();
    c.bench_function("parse", |b| {
        b.iter(|| parse(black_box(&input)))  // black_box stops const-folding the input
    });
}
criterion_group!(benches, bench_parse);
criterion_main!(benches);
```

**Trade-off:** microbenchmarks measure a function in isolation with hot caches and a warm branch predictor — they systematically overstate real-world wins and hide cache/allocator effects that only appear in the full program. Treat a microbenchmark win as necessary, not sufficient; confirm against an end-to-end measurement before claiming a system-level speedup.

### Profilers

Pick by the question you're asking:

| Tool | Platform | Answers |
|---|---|---|
| **samply** | cross-platform | "Where is wall-clock time going?" Sampling profiler, Firefox Profiler UI. Lowest-friction default. |
| **cargo-flamegraph** | Linux/macOS | Same data as a flamegraph SVG; good for a quick shape-of-the-problem read. |
| **perf** | Linux | Ground truth. Hardware counters: cache misses, branch mispredicts, IPC. Use when a flamegraph says "this loop is hot" but not *why*. |
| **Instruments** (Time Profiler / Allocations) | macOS | Native macOS profiling; Allocations instrument for allocation churn. |
| **DHAT** (via `dhat` crate or valgrind) | cross-platform | Heap profiling: allocation count, sizes, lifetimes. Use when the flamegraph shows time in `malloc`/`free`. |

Sequence: sampling profiler to localize → if it's compute, `perf stat` for the microarchitectural reason (a cache-miss-bound loop and a branch-mispredict-bound loop need opposite fixes) → if it's allocation, a heap profiler.

## Zero-cost abstractions — and where the abstraction leaks

"Zero-cost" (Stroustrup's phrase, adopted by Rust) means: *you don't pay for what you don't use, and what you do use you couldn't hand-code better.* It is a claim about specific abstractions, not a blanket guarantee. Knowing which side of the line a construct is on is core senior judgment.

**Genuinely zero-cost (compiles to the same machine code as the manual version):**
- **Iterator chains.** `xs.iter().filter(..).map(..).sum()` monomorphizes and inlines into a single loop; there is no per-adaptor allocation or virtual call. Prefer them over index loops — they are both clearer *and* eliminate bounds checks (below).
- **Generics / static dispatch.** Each instantiation is monomorphized to a concrete type and inlined like hand-written code.
- **Newtypes / `struct` wrappers.** `struct Meters(f64)` has identical layout to `f64`.
- **`Result`/`Option` control flow and `?`.** Lowers to branches, not exceptions/unwinding.

**Costs you *do* pay (the abstraction is not free):**
- **`dyn Trait` dynamic dispatch.** Each call is an indirect jump through a vtable and is *not inlined*, which also blocks the optimizations inlining would have unlocked (constant propagation, vectorization). Fine for cold paths and heterogeneous collections; measurable in a tight loop.
- **`Box`/`Rc`/`Arc`.** Heap allocation + pointer indirection (cache miss potential); `Arc` clone/drop are atomic RMW operations (a real cost under contention).
- **Bounds checks** on indexing (see below).
- **`Mutex`/`RwLock`** uncontended is cheap but not free; contended is expensive.

```rust
trait Shape { fn area(&self) -> f64; }
struct Sq(f64);
impl Shape for Sq { fn area(&self) -> f64 { self.0 * self.0 } }

// Static dispatch (generic): monomorphized, inlinable — the zero-cost path.
fn total_static<S: Shape>(shapes: &[S]) -> f64 {
    shapes.iter().map(Shape::area).sum()
}
// Dynamic dispatch: heterogeneous, but each call is an indirect vtable jump.
fn total_dyn(shapes: &[Box<dyn Shape>]) -> f64 {
    shapes.iter().map(|s| s.area()).sum()
}
```

**When to deviate:** reach for `dyn` deliberately when monomorphization bloat hurts more than dispatch — many instantiations of a large generic function blow up code size and instruction-cache pressure and slow compile times. A cold, rarely-called generic instantiated over dozens of types is a candidate for `dyn` to shrink the binary. Before that, apply the *outline* pattern: keep only the genuinely generic sliver generic (e.g. `serialize<T>` turns `T` into a `Value`) and delegate the bulk to one non-generic inner function (`serialize_value`), so 50 instantiations share a single copy of the heavy code (Microsoft RustTraining, *Rust Patterns* ch1). Decide with a binary-size and icache measurement, not a rule.

## Memory layout

Layout drives cache behavior, and cache behavior drives real-world performance more than instruction count on modern hardware. This is where measurement-guided restructuring pays the largest dividends.

### Field ordering and `repr`

Under the default `#[repr(Rust)]` the compiler **reorders struct fields freely** to minimize padding. Do not hand-order fields for size — you cannot beat the compiler and you'll write misleading code. `#[repr(C)]` freezes declaration order (required for FFI and for any layout you rely on across the ABI boundary) and can therefore be *larger* than `repr(Rust)` because it must pad to keep your order. Choose `repr(C)` for correctness (FFI, mmap'd/wire structs), never for speed.

```rust
use std::mem::{size_of, align_of};
use std::num::NonZeroU32;

// repr(Rust): compiler reorders a,b,c to pack tightly. Don't hand-tune.
struct Reordered { a: u8, b: u64, c: u8 }

pub fn info() -> (usize, usize) {
    (size_of::<Reordered>(), align_of::<Reordered>())
}
```

### Niche optimization

Rust folds "impossible" bit patterns (niches) into enum discriminants. The load-bearing consequences:
- `Option<NonZeroU32>` is **4 bytes**, not 8 — the `None` is encoded as the zero the inner type promises never to hold.
- `Option<&T>`, `Option<Box<T>>`, `Option<NonNull<T>>` are **pointer-width** — `None` is the null pointer. `Option<&T>` genuinely costs nothing over `&T`.

```rust
use std::mem::size_of;
use std::num::NonZeroU32;
const _: () = assert!(size_of::<Option<NonZeroU32>>() == size_of::<NonZeroU32>());
const _: () = assert!(size_of::<Option<&u8>>() == size_of::<&u8>());
```

**Why it matters:** modeling "maybe absent, but the present value has a forbidden state" with `Option<NonZero…>` / `Option<&T>` costs nothing versus a manual sentinel, and it's safer. Prefer these over `-1`/`0` sentinels or a separate `bool` flag.

### Enum size = largest variant + discriminant

An enum is sized for its *largest* variant plus a tag (minus any niche it can reuse), rounded to alignment. A rarely-used 256-byte variant makes *every* value of that enum 256+ bytes, which wrecks cache density when you store many of them or move them around.

```rust
enum Msg { Ping, Payload(Box<[u8; 256]>) }  // Box the fat variant → enum stays ~pointer-sized
```

**Fix:** `Box` the large/rare variant. **Trade-off:** the common path is unaffected, but touching the boxed variant costs an allocation + indirection. Right call when the large variant is rare relative to how often the enum is stored/moved; wrong when it's on the hot path. Clippy's `large_enum_variant` flags this — treat it as a prompt to measure, not an auto-fix.

### `async fn` future size = largest live-across-await state

An `async fn` compiles to an enum with one variant per `.await` point, so the future is sized to the *largest* set of locals live across any await — the same largest-variant rule as above. A big stack value held across an await (e.g. `let buf = [0u8; 1_000_000]`) bloats the whole future to ~1 MB, and moving or storing that future can overflow the stack. Heap-allocate the payload (`Vec<u8>`/`Box<[u8]>`) or `Box::pin` sub-futures; when async code overflows the stack, audit for large arrays and deep future nesting, not recursion (Microsoft RustTraining, *Async* ch5).

### `size_of` / `align_of` are the ground truth

When layout matters, assert it in a `const` block (compile-time, zero runtime cost) so a future refactor that bloats a hot type fails the build instead of silently regressing cache behavior. This is cheaper and more honest than a comment claiming "this is 8 bytes."

### Cache-friendliness and data-oriented design (SoA vs AoS)

The dominant cost in data-heavy code is memory latency, not arithmetic. If you iterate a collection touching only one field, **Array-of-Structs (AoS)** drags every other field through cache with it; **Struct-of-Arrays (SoA)** stores each field contiguously so a single-field pass reads packed memory and autovectorizes.

```rust
// AoS: a mass-only pass strides over pos+vel too — wasted cache lines.
struct ParticleAoS { pos: [f32; 3], vel: [f32; 3], mass: f32 }
fn total_mass_aos(ps: &[ParticleAoS]) -> f32 { ps.iter().map(|p| p.mass).sum() }

// SoA: mass column is contiguous — full cache-line utilization, vectorizable.
struct ParticlesSoA { pos: Vec<[f32; 3]>, vel: Vec<[f32; 3]>, mass: Vec<f32> }
fn total_mass_soa(ps: &ParticlesSoA) -> f32 { ps.mass.iter().copied().sum() }
```

**Trade-off:** SoA is faster for column-wise passes and bulk processing but worse for "operate on one whole entity at a time" access (which now touches N distant arrays) and is more awkward to write and keep consistent. Default to AoS for clarity; switch to SoA only when a profiler shows a hot loop is memory-bound on a wide struct. This is the core of data-oriented design — shape data for the access pattern the hot loop actually has.

### `Vec<T>` vs `Box<[T]>`

`Vec<T>` carries `(ptr, len, capacity)` and can grow. `Box<[T]>` carries `(ptr, len)` — one word smaller and it states "fixed length" in the type. Once a collection is built and won't resize, `vec.into_boxed_slice()` shrinks it to exact capacity (releasing slack) and shrinks the handle. Marginal for one value; meaningful when you store millions of them or embed the handle in a hot struct. **When to deviate:** if you'll ever push again, keeping the `Vec` avoids a realloc — don't convert prematurely.

## Allocation discipline

Heap allocation is one of the most common avoidable costs in Rust code, and it rarely shows up as a single hot line — it's death by a thousand `malloc`s spread across a call tree, visible only in a heap profiler or as time in the allocator on a flamegraph.

- **Avoid needless clones.** `.clone()` to satisfy the borrow checker is a code smell — usually a borrow or a restructure works. Audit each one in order: pass `&T`/`&str`, else move if the callee needs ownership, and reserve `.clone()` for a genuinely independent copy — a GC background trains the eye to scatter copies whose cost the runtime used to hide (Microsoft RustTraining, *C#* ch16). `Arc::clone` is *not* in this category: it only bumps a refcount, so sharing across threads is cheap (still not free in a tight loop). The authoring discipline is *clone-first, optimize-later* — get the ownership structure right with liberal clones, then delete only the ones a profiler shows are hot; contorting code to dodge the borrow checker before any evidence the copy is hot is itself an anti-pattern (Microsoft RustTraining, *Python* ch16).
- **`with_capacity`.** A `Vec`/`String`/`HashMap` built by repeated `push`/`insert` reallocates and copies as it grows (amortized O(1), but the copies are real). If you know or can estimate the final size, `with_capacity(n)` allocates once. Verify with a heap profiler that the reallocations were actually costing you.
- **Reuse buffers across iterations.** Allocating a fresh `String`/`Vec` inside a loop is a per-iteration allocation. Hoist it out and `.clear()` (which retains capacity) each pass.

```rust
// Reuse one buffer instead of allocating per line. `clear()` keeps capacity.
fn process_lines(lines: &[&str]) -> usize {
    let mut buf = String::with_capacity(64);
    let mut total = 0;
    for line in lines {
        buf.clear();
        buf.push_str(line);
        buf.make_ascii_uppercase();
        total += buf.len();
    }
    total
}
```

- **`SmallVec` / `arrayvec`.** `smallvec::SmallVec<[T; N]>` stores up to N elements inline (no heap) and spills to the heap only past N; `arrayvec::ArrayVec<T, N>` is inline-only and refuses to grow. When collections are usually tiny (say ≤ 8) but occasionally larger, `SmallVec` eliminates the common-case allocation. **Trade-off:** larger stack footprint per value, an extra branch on every access (inline vs spilled), and a non-std dependency. Worth it only when a profiler shows those small allocations are hot — otherwise it's complexity for nothing.
- **`&str` / slices over owned.** Accept `&str`/`&[T]` in function signatures rather than `String`/`Vec<T>` unless you need ownership. The caller then passes a borrow with no allocation, and the function works for both owned and borrowed callers. Returning owned data is fine; *demanding* it as input forces callers to allocate.
- **`Cow<'_, T>`.** "Borrow on the common path, allocate only when you must mutate." Ideal for a function that usually returns its input unchanged but occasionally must produce a modified copy.

```rust
use std::borrow::Cow;
// No allocation when the input is already clean — only the rare tab case allocates.
fn sanitize(input: &str) -> Cow<'_, str> {
    if input.contains('\t') { Cow::Owned(input.replace('\t', "    ")) }
    else { Cow::Borrowed(input) }
}
```

**When to deviate on all of the above:** if allocation isn't on your hot path, none of this matters and the plain `Vec`/`String`/`clone` version is clearer. Prove allocation is a bottleneck (heap profiler / allocator on the flamegraph) before contorting APIs around `Cow` and `SmallVec`.

## Bounds-check elision

Every slice index `xs[i]` compiles to a check `i < len` + panic branch. In a hot loop this branch can block vectorization and cost real cycles. The idiomatic elision is **not** `unsafe` — it's iterators. When you iterate (`for x in xs`, `.iter()`, `.windows()`, `.chunks()`), the length is known to the optimizer and no per-element check is emitted.

```rust
pub fn sum_idiomatic(xs: &[u32]) -> u32 { xs.iter().copied().sum() } // no bounds checks

// Manual index loop MAY keep a per-access check unless LLVM proves i < len.
pub fn sum_indexed(xs: &[u32]) -> u32 {
    let mut acc = 0;
    for i in 0..xs.len() { acc += xs[i]; }
    acc
}
```

If you must index (e.g. touching multiple slices at the same `i`), reslice the *secondary* slices to the driving length up front — `let n = xs.len(); let ys = &ys[..n]; for i in 0..n { acc += xs[i] * ys[i]; }`. The `&ys[..n]` panics once outside the loop if `ys` is too short, and LLVM can then prove `i < ys.len()` from `i < n` and drop the per-iteration check on `ys`. Reslicing `xs` by its own length (`&xs[..n]` with `n == xs.len()`) does nothing — same pointer, same length, zero new facts. `get_unchecked` is the genuine last resort — it removes the check with `unsafe`, and a wrong index is undefined behavior, not a panic:

```rust
pub fn sum_unchecked(xs: &[u32]) -> u32 {
    let mut acc = 0;
    for i in 0..xs.len() {
        // SAFETY: i < xs.len() by loop construction.
        acc += unsafe { *xs.get_unchecked(i) };
    }
    acc
}
```

**When to deviate:** only after (1) a profiler pins the bounds check as the cost, (2) you confirmed the iterator rewrite doesn't already fix it, and (3) the win justifies an `unsafe` block you must prove sound and comment with `// SAFETY:`. In the vast majority of code, the answer is "use an iterator," and the unsafe version buys nothing while adding a UB surface. See the unsafe reference for the soundness obligations.

## Inlining

`#[inline]` is a *hint* that also makes the function's body available for cross-crate inlining (functions are only inlinable across a crate boundary if their MIR is exported, which `#[inline]` — and generics/`const fn` — do). Within a crate, LLVM already inlines aggressively based on its own cost model; adding `#[inline]` there usually changes nothing.

- **`#[inline]`** — annotate small, hot, cross-crate functions (accessors, trivial wrappers in a library). Lets callers in other crates inline them.
- **`#[inline(always)]`** — a stronger demand. Use rarely and only with a benchmark: forcing inlining of a non-trivial function bloats code size, worsens icache pressure, and can be *slower*. It is not "more optimized."
- **`#[inline(never)]`** — legitimately useful to keep a cold path (error formatting, panic helpers) out of the hot function so the hot function stays small and icache-friendly, and to get cleaner profiles/flamegraphs.

**Trade-off:** inlining trades code size for call-overhead elimination and cross-boundary optimization. More is not better — past a point it degrades icache behavior. **When to deviate:** default to no annotation and trust LLVM; add `#[inline]` on small public library functions; reach for `always`/`never` only when a benchmark says the default was wrong.

## Build-profile tuning

The single highest-leverage, lowest-effort performance change is often the release profile — it's a one-time config edit, not a code change, and it applies globally. Confirm each knob with an end-to-end benchmark; they trade compile time (and sometimes debuggability) for runtime.

```toml
# illustrative — Cargo.toml
[profile.release]
opt-level = 3        # default for release; "s"/"z" optimize for size instead of speed
lto = "thin"         # cross-crate inlining/DCE; "fat" = max but slow to link; "thin" ~ most of the win, cheaper
codegen-units = 1    # one unit = best optimization, slowest compile (default 16 trades opt for parallelism)
strip = true         # drop symbols: −50–70% binary size, zero runtime cost — the highest-leverage size knob
panic = "abort"      # drop unwinding tables/landing pads: smaller, sometimes faster; NO catch_unwind, tests differ

# optimize dependencies in dev/test while leaving your own crate cheap to rebuild — big dev-loop win for serde/parser-heavy deps
[profile.dev.package."*"]
opt-level = 2        # small one-time build cost; your crate stays opt-level 0
```

| Knob | Payoff | Cost |
|---|---|---|
| `strip = true` | −50–70% binary size at zero runtime cost — highest-leverage size knob | Loses symbol names for release-time debugging/profiling |
| `lto = "thin"`/`"fat"` | Cross-crate inlining + dead-code elimination; commonly a few-to-30% win | Much slower link; `fat` can dominate build time |
| `codegen-units = 1` | More optimization within a crate | Serializes codegen → slower compile |
| `panic = "abort"` | Smaller binary, no unwind overhead | No stack unwinding / `catch_unwind` — wrong for any code that must recover from a panic at a boundary |
| `opt-level = "s"/"z"` | Smaller code → better icache (can be *faster* on icache-bound code) | Less speed-oriented optimization |
| `target-cpu` | Uses your CPU's full ISA (AVX2/AVX-512, etc.) — big win for numeric/SIMD code | Binary won't run on older CPUs; set only when you control the target |

`target-cpu` is set via `RUSTFLAGS="-C target-cpu=native"` (or a `.cargo/config.toml` `rustflags`), not the profile. `native` = "this exact machine" — perfect for a server you own, wrong for a redistributable binary (illegal-instruction crashes on older hardware). For distribution, pick a concrete baseline (e.g. `x86-64-v2`).

**PGO (Profile-Guided Optimization)** and **BOLT** are the advanced tier. PGO: build instrumented → run representative workloads to collect a profile → rebuild using it, so LLVM lays out branches/inlining for *your* actual execution paths (via `cargo-pgo` or `-C profile-generate`/`profile-use`). BOLT re-optimizes the linked binary's code layout from a `perf` profile. Both deliver single-digit-to-low-double-digit percent on large real workloads. **Trade-off:** a genuinely more complex, workload-dependent build pipeline whose win evaporates if the profiling workload is unrepresentative. Reach for them only on mature, profiled, allocation- and algorithm-optimized code where you've exhausted cheaper wins — they are a finishing move, not an opening.

## Const evaluation

`const fn` runs at compile time when invoked in a const context (`const`/`static` initializers, array lengths, const generics), moving work out of runtime entirely. Use it to precompute lookup tables, validate invariants at build time (a failing `const { assert!(..) }` is a compile error), and encode layout expectations. What is `const`-evaluable has expanded a lot and continues to (loops, `if`, most arithmetic, much of `match` are stable in `const fn`; floating-point arithmetic, comparison, casts and `to_bits` are const-stable since 1.82). Some std methods are still non-`const` — transcendental float methods such as `sqrt` among them — so check the specific API's stability rather than assuming.

The proof engine generalizes past scalar asserts: a `const` constructor can verify structural invariants — e.g. containment and pairwise overlap-freedom of a memory map's regions — so a section resized past its bound fails the build (E0080) instead of crashing in the field months later, and the binary carries only the verified constants. Pair it with phantom access-permission markers to separate hardware capability from software permission (a typed `ReadOnly` region rejects writes even though the SRAM is physically writable) (Microsoft RustTraining, *Type-Driven Correctness* ch15).

```rust
const fn table() -> [u32; 8] {
    let mut t = [0u32; 8];
    let mut i = 0;
    while i < 8 { t[i] = (i * i) as u32; i += 1; }
    t
}
static SQUARES: [u32; 8] = table();  // computed at compile time, zero runtime cost
```

**Trade-off:** `const fn` is restricted (no heap allocation, no trait methods that aren't const, no arbitrary std calls), so making a function `const` can force awkward code. Do it when compile-time evaluation is genuinely useful (tables, static asserts), not reflexively. **When to deviate:** if the value is computed once at startup and never on a hot path, a plain `once_cell`/`LazyLock` runtime init is simpler and just as fast in practice.

## Decision summary

| Symptom (from a profiler) | First move |
|---|---|
| Time in `malloc`/`free`, high allocation count | `with_capacity`, reuse buffers, `SmallVec`, `Cow`, cut clones |
| Memory-bound hot loop over wide structs | SoA / data-oriented restructure; shrink hot enums via `Box` |
| Indirect calls dominate a tight loop | Replace `dyn` with generics on that path (watch binary size) |
| Bounds checks blocking vectorization | Rewrite as iterators; `get_unchecked` only as proven last resort |
| Compute-bound, SIMD-amenable, controlled target | `target-cpu`, then PGO |
| Binary too big / icache pressure | `opt-level = "s"`, prune monomorphization, `#[inline(never)]` cold paths |

Never apply a row without a before/after benchmark. The measurement is the deliverable, not the change.

## Sources

- [The Rust Performance Book](https://nnethercote.github.io/perf-book/) — Nethercote (primary reference for this file)
- [The Rust Programming Language](https://doc.rust-lang.org/book/) — enums, layout, ownership fundamentals
- [The Rust Reference](https://doc.rust-lang.org/reference/type-layout.html) — type layout, `repr`, niches
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) — accepting `&str`/slices in signatures
- [Comprehensive Rust (Google)](https://google.github.io/comprehensive-rust/) — zero-cost abstractions, monomorphization
- Microsoft RustTraining — [*Best Practices for C# Developers*, ch16](https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch16-best-practices.md) — clone-audit checklist (borrow → move → clone); `Arc::clone` is a refcount bump
- Microsoft RustTraining — [*Rust for Python Developers*, ch16 Best Practices](https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch16-best-practices.md) — "clone-first, optimize-later"; premature borrow-optimization as an anti-pattern
- Microsoft RustTraining — [*Async*, ch5 The State Machine Reveal](https://github.com/microsoft/RustTraining/blob/main/async-book/src/ch05-the-state-machine-reveal.md) — `async fn` future size = largest live-across-await state
- Microsoft RustTraining — [*Rust Patterns*, ch1 Generics: The Full Picture](https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch01-generics-the-full-picture.md) — monomorphization bloat and the outline pattern
- Microsoft RustTraining — [*Type-Driven Correctness*, ch15 Const Fn: Compile-Time Correctness Proofs](https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch15-const-fn-compile-time-correctness-proofs.md) — `const fn` + `assert!` as a build-time proof engine
- Microsoft RustTraining — [*Engineering*, ch7 Release Profiles and Binary Size](https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch07-release-profiles-and-binary-size.md) — `strip`, thin vs fat LTO, `panic = "abort"`, dev-profile dependency optimization
- `rust-clippy` lint rationale — `large_enum_variant`, needless-collect/clone lints
- Cross-refs within this skill: `unsafe.md` (soundness of `get_unchecked`), `rust-patterns`/`rust-testing` ECC skills (idioms/TDD — not restated here)

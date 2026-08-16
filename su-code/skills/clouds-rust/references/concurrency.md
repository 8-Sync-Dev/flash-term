# Concurrency & Parallelism

Senior-level judgment for concurrent Rust: why "fearless concurrency" is a real property and not a slogan, how to pick a coordination primitive, and when the clever lock-free thing is a mistake. Baseline: Rust 1.96, edition 2024, all `std` unless marked. Async concurrency lives in `async.md`; the full pitfall catalog is in `anti-patterns.md` — the top traps are summarized at the end here.

## Why Rust concurrency is "fearless" — the actual mechanism

The guarantee is not "no bugs." It is: **data races are a compile error, not a runtime surprise.** A data race requires two threads accessing the same memory, at least one writing, with no synchronization. Rust makes that unrepresentable by fusing two things it already had for single-threaded safety — ownership/borrowing (one `&mut` xor many `&`) — with two marker traits, `Send` and `Sync`, that extend those rules *across threads*. The borrow checker enforces exclusivity; `Send`/`Sync` decide what may cross a thread boundary at all. Everything else in this file is a consequence of those two mechanisms.

What you still own: **deadlocks, livelocks, and logic races** (correct-but-wrong interleavings, e.g. check-then-act on a value another thread mutates between). Rust prevents the memory-unsafe race, not the "I locked in the wrong order" bug. Budget your caution accordingly.

## `Send` and `Sync` — the foundation

- `Send`: a type is safe to **move/transfer ownership to another thread**.
- `Sync`: a type is safe to **share by reference across threads** — formally, `T: Sync` iff `&T: Send`.

Both are **auto traits**: the compiler derives them structurally, field by field. A struct is `Send` if all fields are `Send`; `Sync` if all fields are `Sync` — so one non-`Sync` field (a stray `Cell`, `Rc`, or raw pointer) silently makes the whole struct `!Sync`, with no annotation and no error until you try to share it. You almost never implement them by hand — you do so only inside an `unsafe` abstraction that upholds the invariant manually (see `unsafe-rust.md`). Opting *out* is safe and zero-cost via a `PhantomData<*const ()>` field: it confines a type that has no unsafe field of its own — a bare `i32` fd or opaque C handle whose underlying library isn't thread-safe — to one thread, turning a "see the docs, not thread-safe" comment into a compiler-enforced invariant. (A negative impl is also available on nightly.)

```rust
// illustrative — the mental model
fn assert_shareable<T: Send + Sync>(_: &T) {}
```

Know these by heart, because they explain 90% of "why won't this compile across a thread":

| Type | Send | Sync | Why |
|---|---|---|---|
| `Rc<T>` | no | no | non-atomic refcount — cloning on two threads races the count |
| `Arc<T>` | yes* | yes* | atomic refcount (*if `T: Send + Sync`) |
| `RefCell<T>` | yes* | **no** | runtime borrow flag is non-atomic; shared `&` could double-borrow-mut across threads (*Send if `T: Send`) |
| `Mutex<T>` | yes* | yes* | the point of a mutex is to be `Sync` (*needs `T: Send`) |
| `MutexGuard<'_, T>` | **no** | yes* | many OS mutexes require unlock on the *same* thread that locked; moving the guard would unlock elsewhere |
| `Cell<T>` | yes* | no | interior mutation through `&` is a plain non-atomic write — two threads sharing `&Cell<T>` would race on the value itself (*Send if `T: Send`) |
| raw `*const/*mut T` | no | no | no ownership story — forces you into `unsafe` to assert one |

`Rc` being `!Send` is the compiler stopping a genuine memory-safety bug: two threads each thinking they hold the last reference and both freeing. `MutexGuard: !Send` is the subtle one — it is why you cannot `.await` while holding a `std::sync::MutexGuard` in code that may move tasks between threads, and why lock-across-await belongs to `tokio::sync::Mutex` (see `async.md`).

**When to hand-implement `unsafe impl Send/Sync`:** only when wrapping raw pointers or FFI handles where *you* guarantee the synchronization the compiler can't see. Document the invariant in a `// SAFETY:` comment. Getting it wrong reintroduces exactly the UB the type system was preventing.

## Threads and scoped threads

`std::thread::spawn` takes a `'static + Send` closure — `'static` because the OS thread may outlive the spawner, so it cannot borrow the parent stack. Historically this forced the "clone an `Arc` for every capture" dance even for threads you immediately join.

**Prefer scoped threads (`std::thread::scope`, stable since 1.63)** whenever threads join within the current function. The scope guarantees all spawned threads finish before it returns, which makes borrowing parent-stack data *sound* — no `'static`, no `Arc`, no clone:

```rust
use std::thread;

fn sum_parallel(data: &[i64]) -> i64 {
    let mid = data.len() / 2;
    let (left, right) = data.split_at(mid);
    thread::scope(|s| {
        let h = s.spawn(|| left.iter().sum::<i64>()); // borrows `left` directly
        let r: i64 = right.iter().sum();
        h.join().unwrap() + r
    })
}
```

- **Mechanism:** `scope` blocks at its closing brace and joins every un-joined handle, so the borrows can't dangle.
- **Trade-off:** scoped threads are for *structured* fan-out/fan-in. They cannot outlive the call, so they're wrong for background workers, thread pools, or anything with an open-ended lifetime — use `spawn` + `Arc` there, or better, don't hand-roll a pool (reach for `rayon`).
- **When to deviate:** long-lived daemon threads, actor loops, or handing a thread to another owner all need `spawn`'s `'static`.

`join()` returns `thread::Result` — an `Err` means that thread **panicked**. Ignoring it silently swallows a crashed worker; propagate or at least log it.

## Shared mutable state: `Arc<Mutex<T>>` and lock discipline

`Arc<Mutex<T>>` is the workhorse: `Arc` gives shared *ownership* (atomic refcount), `Mutex` gives shared *mutability* (exclusive access at runtime). Reach for it when threads must mutate the same state and message-passing would be awkward.

The hard part is not the types, it's **discipline**:

**1. Keep the critical section minimal.** A lock serializes every thread that wants it; time spent holding it is time your parallelism is gone. Compute *outside* the lock, mutate *inside*.

```rust
use std::sync::{Arc, Mutex};

fn increment_shared(counter: &Arc<Mutex<u64>>, work: u64) {
    let result = expensive(work);        // outside the lock
    let mut guard = counter.lock().unwrap();
    *guard += result;                    // tiny critical section
}                                        // guard dropped here

fn expensive(n: u64) -> u64 { (0..n).sum() }
```

**2. Never hold a lock across a blocking call or I/O** — that turns your mutex into a global serialization point. Across `.await` the rule is subtler than a flat "never": a `std::sync::MutexGuard` held across `.await` compiles fine until the future is *required* to be `Send` (e.g. at `tokio::spawn`), and blindly scoping the critical section so the guard drops *before* the await opens a TOCTOU race when the code after the await depends on state read before it. For a transactional read-modify-write that spans an await, use `tokio::sync::Mutex` — its guard is `Send` and holds across `.await` without blocking the OS thread; scope-and-split only when the two halves are genuinely independent (see `async.md`).

**3. Lock ordering prevents deadlock.** If two locks A and B are ever held simultaneously, *every* site must acquire them in the same order. Thread 1 taking A→B while thread 2 takes B→A is the classic deadlock. Enforce a global order (e.g. by address, or by a documented hierarchy). Better: restructure so you never hold two locks at once.

**4. Poisoning (std only).** If a thread panics while holding a `std::sync::Mutex`, the lock becomes *poisoned*; subsequent `lock()` returns `Err(PoisonError)`. This is a safety feature: it flags that the protected data may be in a broken half-updated state. `.unwrap()` on the lock result propagates the panic — usually correct (a poisoned invariant *should* be loud). Recover with `into_inner()` / `err.get_mut()` only when you can prove the data is still consistent.

### `RwLock` — when it actually pays

`RwLock<T>` allows many concurrent readers *or* one writer.

```rust
use std::sync::{Arc, RwLock};

fn read_heavy(cfg: &Arc<RwLock<Vec<usize>>>) -> usize {
    let g = cfg.read().unwrap();   // shared read; concurrent with other readers
    g.iter().sum()
}
```

- **Why/when:** it pays only when reads *vastly* outnumber writes **and** the critical section is long enough to amortize the extra bookkeeping. For a short read (a few fields, a counter), a plain `Mutex` is typically faster because `RwLock` does more work per acquisition and the std/OS implementation can be writer-starving or reader-starving depending on platform.
- **Trade-off:** more complexity, platform-dependent fairness, and a real risk of writer starvation under sustained read load. Upgradable-read is not in std (`parking_lot` has it).
- **Default:** start with `Mutex`. Switch to `RwLock` only after measuring contention that is provably read-dominated. For "read almost always, write almost never, small value," prefer `arc-swap` (below) over `RwLock`.

### `parking_lot` trade-offs

`parking_lot::{Mutex, RwLock}` are common drop-in replacements. What you gain: `lock()`/`read()`/`write()` return the guard **directly** (no `Result`, no poisoning), guards are smaller, and uncontended/lightly-contended locking is often faster with a more compact representation. What you give up: **no poisoning**, so a panic mid-critical-section leaves the data readable in a possibly-inconsistent state with no signal — you must reason about panic-safety yourself. Also a third-party dependency and its MSRV.

Decision: use `parking_lot` for the ergonomics and speed in code where you either can't panic in the critical section or don't need the poison signal; keep `std` when you *want* poisoning to surface a broken invariant, or to stay dependency-free. In async code, neither of these is the answer for locks held across `.await` — use `tokio::sync::*` (see `async.md`).

## Channels — message passing over shared state

"Do not communicate by sharing memory; share memory by communicating." Channels move ownership between threads, sidestepping locks entirely. Prefer them when work has a clear producer→consumer flow.

**`std::sync::mpsc`:** multi-producer, single-consumer. `channel()` is **unbounded**; `sync_channel(n)` is **bounded** with capacity `n`.

```rust
use std::sync::mpsc;
use std::thread;

fn pipeline() -> i64 {
    let (tx, rx) = mpsc::sync_channel::<i64>(8);   // bounded => backpressure
    thread::scope(|s| {
        s.spawn(move || {
            for i in 0..100 {
                tx.send(i).unwrap();               // blocks when 8 unconsumed
            }
        });                                        // tx dropped => rx ends
        rx.iter().sum()
    })
}
```

**Bounded vs unbounded is a backpressure decision, not a perf tweak.** An unbounded channel with a producer faster than its consumer is an unbounded memory leak — the queue grows without limit until OOM. A **bounded** channel makes `send` block (or `try_send` fail) when full, propagating slowness *backward* to the producer. Default to bounded; choose the capacity as the buffering you can afford. Reach for unbounded only when you can prove the producer is rate-limited by something else, or the total volume is small and known.

**`crossbeam-channel`** (illustrative — external crate) is the upgrade when std's `mpsc` isn't enough: it is **mpmc** (multiple consumers too), supports `select!` over multiple channels, and is generally faster. Use it for work-stealing queues, fan-out to a worker pool, or any time you need `select!`.

```rust
// illustrative — crossbeam-channel
let (tx, rx) = crossbeam_channel::bounded(64);
// clone rx to give N workers a shared consuming end (mpmc):
for _ in 0..num_workers { let rx = rx.clone(); /* spawn worker pulling from rx */ }
```

Signal: `send` returning `Err` means all receivers dropped; `recv` returning `Err` means all senders dropped. That's how you detect shutdown — treat it as a control signal, not an error to swallow.

**Actor pattern over `Arc<Mutex<T>>`.** When state has complex invariants, its operations are long-running, or lock-ordering would be error-prone, own the state in one thread and drive it with an enum of messages over a channel (queries carry their own reply `Sender`) — message passing serializes access with no lock to deadlock. Keep `Mutex` for short, simple critical sections where an actor's channel round-trip is overkill.

## Atomics and memory ordering

Atomics (`AtomicUsize`, `AtomicBool`, `AtomicPtr`, …) give lock-free single-variable operations. The subtlety is the `Ordering` argument, which constrains how *other* memory operations may be reordered around the atomic one. Get the intuition right and you rarely need more than two of them.

- **`Relaxed`** — atomicity only, **no ordering** relative to other memory. The operation itself won't tear, but reads/writes around it may be reordered freely. Correct for a **standalone counter** where you only care that the final total is right, never that it orders other data.
- **`Release`** (on a store) — everything that happened-before this store in program order becomes visible to any thread that later does an **`Acquire`** load and observes this store's value. This is the *publish* half.
- **`Acquire`** (on a load) — the *consume* half: once you observe a `Release`-stored value, you also see all the writes that preceded it. Release/Acquire is the standard way to hand off data: write the payload, then `Release`-store a flag; the reader `Acquire`-loads the flag and is then guaranteed to see the payload.
- **`SeqCst`** — Acquire+Release *plus* a single global total order across all `SeqCst` operations. The easiest to reason about and the slowest. Use it when a thread's store must not be reordered past its own later load of a *different* atomic (the two-thread Dekker/store-buffer pattern, which Release/Acquire permits to observe `0`/`0` on both sides), or when three-plus threads must agree on one total order of independent variables (IRIW) — neither of which Release/Acquire can provide regardless of thread count.

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

fn counter(c: &AtomicUsize) {
    c.fetch_add(1, Ordering::Relaxed);   // pure count: Relaxed is correct + cheapest
}

fn publish(flag: &AtomicBool, data: &mut i32) {
    *data = 42;                          // (1) payload
    flag.store(true, Ordering::Release); // (2) any Acquire seeing `true` also sees (1)
}
```

**Decision rule:** counter with no cross-data meaning → `Relaxed`. Publishing data behind a flag / building a primitive → `Release`/`Acquire`. Multi-party consensus or "I can't prove the weaker one" → `SeqCst`, then measure. Never reach for `Relaxed` on the *synchronizing* operation of a handoff — that's the classic correctness bug.

**The ABA problem:** a compare-and-swap checks *value equality*, not "unchanged." Thread reads A, another thread changes A→B→A, the CAS still succeeds — but the world moved underneath. It bites lock-free stacks/queues built on raw pointers (a freed-and-reallocated node reuses the address). Mitigations — tagged pointers/generation counters, or hazard pointers / epoch reclamation (`crossbeam-epoch`) — are exactly why you should not hand-roll lock-free containers (next section).

## Data parallelism with `rayon`

For **CPU-bound work over a collection**, `rayon` (illustrative — external crate) is almost always the right first tool. Converting `iter()` to `par_iter()` parallelizes across a work-stealing thread pool with near-zero ceremony:

```rust
// illustrative — rayon
use rayon::prelude::*;
fn sum_squares(v: &[f64]) -> f64 {
    v.par_iter().map(|x| x * x).sum()
}
```

- **Mechanism:** rayon splits the work recursively and a global work-stealing pool balances load; idle threads steal tasks from busy ones, so uneven work distributes well without you tuning chunk sizes.
- **When it pays:** the per-item work × item count must dominate the fixed cost of splitting and cross-thread coordination. For a few thousand cheap operations, the serial iterator wins — parallelism has overhead and cache/false-sharing costs. Measure; don't assume.
- **Field data:** a 50k-image pipeline swapping Python's `multiprocessing.Pool` (16 forked workers) for `.par_iter()` fell from ~4.5 h and ~800 MB of fork+pickle overhead to ~35 min and ~50 MB — threads share memory instead of copying it, and each step returns a real `Result` instead of an opaque pickle failure.
- **When NOT to:** I/O-bound work (threads block, not compute — use async, see `async.md`), tiny datasets, or work with heavy shared-mutable state (you'll serialize on the lock and lose the win). Rayon closures must be `Send`; capturing `Rc` or a non-`Sync` cell won't compile.
- **Trade-off:** a global pool means one runaway parallel job can starve others; nested `par_iter` is usually fine (rayon handles it) but mixing rayon with a blocking async runtime needs care.

## Lock-free patterns — and when NOT to

**Start here: lock-free is almost always premature. Say no by default.** A well-scoped `Mutex` with a short critical section is fast, obviously correct, and reviewable. Hand-written lock-free code is a magnet for ABA bugs, memory-reclamation UB, and ordering mistakes that only manifest under load on one CPU architecture. A protocol that is logically sound and even works on x86 — say a SeqLock reading through `UnsafeCell` concurrently with a writer — is still a data race under Rust's abstract machine: soundness on real hardware is not soundness in Rust's memory model. The bar to justify it: you have *measured* lock contention as the bottleneck, and the data structure is simple enough to get provably right (or you're using a vetted crate).

What is legitimately reachable:

- **Atomic counters / flags** (`AtomicUsize`, `AtomicBool`): genuinely simple and correct. Metrics, feature flags, "should I stop" signals. Use them freely.
- **`arc-swap`** (illustrative — external crate): the right tool for "read-mostly, replace-wholesale" config/state. Readers get a consistent snapshot with no lock and near-zero read cost; a writer atomically swaps in a whole new `Arc<T>`. This beats `RwLock<Arc<T>>` for the common "hot config, rare reload" case.

```rust
// illustrative — arc-swap
use arc_swap::ArcSwap;
use std::sync::{Arc, LazyLock};
static CONFIG: LazyLock<ArcSwap<Config>> =
    LazyLock::new(|| ArcSwap::from_pointee(Config::default())); // std LazyLock, stable 1.80
let cfg = CONFIG.load();          // cheap, lock-free snapshot
CONFIG.store(Arc::new(new_cfg));  // atomic whole-value replace
```

- **Seqlock (concept, not std):** a reader reads a sequence counter, reads the data, re-reads the counter; if it's unchanged and even, the read was consistent, else retry. Great for a small, frequently-read, occasionally-written value where readers must never block writers. It's a *concept to recognize* — reach for a crate implementation, don't hand-roll the fencing.
- **Vetted crate structures** (`crossbeam` queues/deques, `dashmap` for a concurrent map): use these instead of writing your own. They already solved ABA and reclamation.
- **Lazy global init** (`std::sync::OnceLock` / `LazyLock`, both stable): `OnceLock::get_or_init` when initialization needs runtime arguments, `LazyLock` for a definition-site closure — both replace `lazy_static!`/`once_cell` with zero dependencies.

If you're about to write a CAS loop over a raw pointer, stop and reconsider — that's the exact code where reclamation UB lives. See `unsafe-rust.md`.

## Async vs threads — the decision

| Dimension | Threads / rayon | Async (`tokio`, see `async.md`) |
|---|---|---|
| Bottleneck | CPU-bound compute | I/O-bound waiting |
| Concurrency count | tens–hundreds (each thread ~MBs of stack) | thousands–millions of tasks |
| Model | preemptive, OS-scheduled | cooperative, `.await` yield points |
| Cost | thread creation + context switch | task is a state machine, cheap to hold |
| Complexity | lower; blocking is fine | higher; `Send` bounds, no blocking on the runtime |

The one-line rule: **wait on many things → async; compute on many cores → threads/rayon.** A server handling 50k idle-mostly connections wants async. A batch job crunching numbers wants rayon. Mixing: run CPU-heavy work off the async runtime (`spawn_blocking` / a rayon pool) so you don't stall the reactor — details in `async.md`. Do not adopt async "for performance" on a CPU-bound workload; you'll add complexity and lose.

## Deadlock, livelock, and race prevention

These are the bugs Rust does **not** catch for you — spend your vigilance here.

- **Deadlock** (threads each blocked forever waiting on a lock the other holds): enforce a **global lock order**, hold **one lock at a time** whenever possible, and never hold a lock across `.await`/I/O. Prefer channels over multi-lock protocols. `try_lock` with a backoff can break a cycle but hides the design smell.
- **Livelock** (threads active but making no progress, e.g. two `try_lock` loops each backing off in lockstep): add randomized/exponential backoff, or replace the spin with a blocking primitive so the scheduler arbitrates.
- **Logic race** (memory-safe but wrong interleaving — the check-then-act): the fix is to make the check-and-act **atomic** — do it inside one lock acquisition, or use a single atomic RMW (`fetch_add`, `compare_exchange`) instead of load-then-store.
- **Detection:** run the whole suite under **ThreadSanitizer** (`RUSTFLAGS="-Zsanitizer=thread"`, nightly) and **Miri** for the `unsafe`/atomic bits; add **`loom`** (illustrative crate) tests for lock-free structures and hand-rolled atomics. `loom` is a model checker, not a stress test: `loom::model(|| ...)` exhaustively enumerates every legal interleaving and memory-ordering outcome, deterministically surfacing bugs a probabilistic stress loop would hit only 1-in-a-million runs — so reserve it for the lock-free/atomic layer and let TSan/Miri cover ordinary `Mutex`/`RwLock` code.

## Top concurrency traps (summary — full list in `anti-patterns.md`)

1. **Holding a lock across `.await` or blocking I/O** — turns a mutex into a global serialization point or a deadlock; often a compile error via `MutexGuard: !Send`.
2. **Unbounded channel with a fast producer** — silent unbounded memory growth. Default to bounded.
3. **`Relaxed` on a synchronizing operation** — a counter is fine, a data-handoff flag is a correctness bug. Use `Release`/`Acquire`.
4. **Reaching for lock-free too early** — unmeasured, unjustified, and a breeding ground for ABA/reclamation UB. Prove contention first.
5. **Inconsistent lock ordering** — the textbook deadlock. Pick one order globally or hold one lock at a time.
6. **`RwLock` by reflex** — often slower than `Mutex` for short critical sections and risks writer starvation. Measure; consider `arc-swap` for read-mostly.
7. **Ignoring `join()`/channel `Err`** — swallows a panicked worker or a shutdown signal.
8. **Async for CPU-bound work** — added complexity, no gain, and it stalls the reactor.

## Sources

- The Rust Programming Language — Ch. 16 "Fearless Concurrency" and Ch. 20: https://doc.rust-lang.org/book/ch16-00-concurrency.html
- Comprehensive Rust (Google) — Concurrency chapters: https://google.github.io/comprehensive-rust/concurrency.html
- `std::thread` (scoped threads, `scope`, stable 1.63), `std::sync` (`Mutex`, `RwLock`, `mpsc`), `std::sync::atomic` (`Ordering`) — std docs: https://doc.rust-lang.org/std/
- The Rustonomicon — `Send`/`Sync`, atomics & memory ordering: https://doc.rust-lang.org/nomicon/send-and-sync.html, https://doc.rust-lang.org/nomicon/atomics.html
- Rust Performance Book — parallelism guidance: https://nnethercote.github.io/perf-book/
- Rust API Guidelines — trait & type conventions: https://rust-lang.github.io/api-guidelines/
- Crate docs (external, marked illustrative): `rayon`, `crossbeam-channel`, `parking_lot`, `arc-swap`, `dashmap`, `loom` on docs.rs
- Microsoft RustTraining — cross-language concurrency framing (thread-safety by type not convention), `Mutex` poisoning, `Send`/`Sync` as compile-time proofs, atomic-ordering defaults, actor pattern, `loom` as model checker:
  - c-cpp-book Ch. 13 Concurrency: https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch13-concurrency.md
  - csharp-book Ch. 13 Concurrency: https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch13-concurrency.md
  - python-book Ch. 13 Concurrency (poisoning, atomic ordering, rayon case study): https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch13-concurrency.md
  - async-book Ch. 12 Common Pitfalls (`MutexGuard` across `.await`): https://github.com/microsoft/RustTraining/blob/main/async-book/src/ch12-common-pitfalls.md
  - rust-patterns-book Ch. 5 Channels & Message Passing, Ch. 6 Concurrency vs Parallelism vs Threads: https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch05-channels-and-message-passing.md , https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch06-concurrency-vs-parallelism-vs-threads.md
  - type-driven-correctness-book Ch. 16 Send & Sync — Compile-Time Concurrency Proofs: https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch16-send-sync-compile-time-concurrency-proofs.md
  - engineering-book Ch. 5 Miri, Valgrind & Sanitizers: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch05-miri-valgrind-and-sanitizers-verifying-u.md

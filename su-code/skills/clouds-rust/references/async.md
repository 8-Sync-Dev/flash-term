# Async / Await

Judgment for writing correct, non-blocking Rust async: the poll-based model, cooperative scheduling, cancellation-as-drop, structured concurrency, and the trait/pinning constraints that trip up seniors. `tokio`, `futures`, `async-std`, `smol` are **ecosystem crates, not std** — std provides only the `Future` trait, `async`/`.await` syntax, `Pin`, and the `Waker`/`Context` task machinery. `Stream` is not in std: it comes from the `futures` crate (std's `AsyncIterator` is still unstable/nightly-only). Everything that *runs* a future is a third-party executor.

Composition: this is the async-specific companion to `rust-patterns`/`rust-testing`. Pin's `unsafe` internals live in `unsafe-rust.md`; here we explain *why* `Pin` exists, not how to project it soundly.

## The mental model: a future is inert until polled

`async fn foo() -> T` desugars to `fn foo() -> impl Future<Output = T>`. Calling it does **zero work** — it constructs a state machine and returns it. Nothing happens until something calls `Future::poll`. This is the single most important fact about Rust async and the root of the "forgot to `.await`" bug class.

```rust
use std::future::Future;

// `async fn double(x: u32) -> u32` desugars to exactly this.
// Calling double(x) allocates/returns a state machine; the `* 2`
// runs only when the returned future is polled to completion.
fn double(x: u32) -> impl Future<Output = u32> {
    async move { x * 2 }
}
```

The compiler lowers each `async` block into an anonymous enum-like state machine. Each `.await` is a **suspension point**: a variant boundary where local variables live across the yield are captured into the machine's state. `poll` is called with a `Context` carrying a `Waker`; the future runs synchronously until it hits an `.await` on something not yet ready, returns `Poll::Pending`, and stashes the `Waker` so the resource can wake it later. When woken, the executor polls again and the machine resumes from where it left off.

```rust
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};

/// A hand-written Future — a two-state machine, exactly what the compiler
/// generates for an `async` block that yields once.
struct YieldOnce { yielded: bool }

impl Future for YieldOnce {
    type Output = ();
    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<()> {
        if self.yielded {
            Poll::Ready(())
        } else {
            self.yielded = true;
            cx.waker().wake_by_ref(); // "poll me again", then suspend
            Poll::Pending
        }
    }
}
```

A production `poll` must tolerate **spurious wakes** — the executor may poll before the awaited condition is truly ready — so re-check the real condition on every poll instead of trusting that being woken means readiness. The race-free registration pattern is a double-check: test the condition, store `cx.waker().clone()`, then test the condition *again*, closing the window where it could flip between the first check and registering the waker. Every real I/O future does exactly this internally.

**Why poll-based (pull) and not callback-based (push)?** Pull lets the whole future tree compose into one flat state machine with no per-task heap allocation and no intrusive `Box<dyn Callback>` chains. The cost you pay: the model is harder to reason about (wakers, pinning) and demands an external executor. This is the "zero-cost, no-runtime-in-std" bargain — you get C-like overhead but must bring your own scheduler.

## Async is an optimization, not a default

Reach for async because you have many *mostly-idle* concurrent connections, not because "threads are expensive" — that reflex is mostly wrong at the scale most teams operate. An idle OS thread reserves ~8MB of virtual address space but commits only ~20-80KB of physical memory, a context switch is ~1-5µs, and a thread pool amortizes creation to zero; a thread pool is simpler to write and debug and stays fast until roughly 1K-10K concurrent *mostly-idle* connections (the epoll/`io_uring` sweet spot). Below ~10 concurrent I/O ops, profile before committing to async at all.

The cost you take on is *function coloring*, and in Rust it infects types, not just signatures: shared state becomes `Arc<Mutex<T>>` (spawned tasks need `Send + 'static`), `std::sync::Mutex` becomes `tokio::sync::Mutex`, `#[test]` becomes `#[tokio::test]`, and a 5-frame stack trace becomes 25 frames half of which are runtime internals. Each is a non-business-logic decision someone must make and maintain — pay it consciously for the concurrency win, not by default.

## Why you need an executor, and choosing one

std deliberately ships no executor: embedding a scheduler + reactor + thread pool in the standard library would force one policy on everyone (single vs multi-thread, work-stealing, IO backend). So you pick:

| Runtime | When |
|---|---|
| `tokio` | Default for anything networked/server-side. Largest ecosystem (hyper, tonic, sqlx, aws-sdk all target it). Multi-thread work-stealing scheduler + epoll/kqueue/IOCP reactor. |
| `smol` / `async-std` | Small, simpler; good for CLI tools or when you want a lean dependency. `async-std` is largely in maintenance mode — prefer `tokio` or `smol` for new work. |
| `embassy` | `no_std` / embedded, no allocator required. |
| hand-rolled / `futures::executor::block_on` | Tests, examples, blocking a single future on a sync thread. Not a production scheduler. |

**Judgment:** commit to one runtime early and stay on it. Mixing runtimes (e.g. calling `tokio` IO from an `async-std` task) generally panics or deadlocks because IO types are bound to their reactor. Libraries should avoid depending on a runtime at all — express APIs in std `Future`/`Stream` and let the binary choose; if you must, gate the runtime behind a feature flag. When to deviate: an app that *is* the binary can and should just pick `tokio` and move on.

**Two I/O models decide how exotic your runtime can be.** Readiness-based (epoll/kqueue/IOCP via `mio`, what standard tokio uses) asks "is it ready?" and then *your* code does the read, borrowing `&mut buf`. Completion-based (`io_uring`) submits "read into this buffer for me" and the kernel owns the buffer until completion — fundamentally incompatible with the borrowing `AsyncRead` trait, which is why `tokio-uring` exposes different ownership-transfer I/O (`let (result, buf) = file.read_at(buf, 0).await`). Only reach for `io_uring` at very high throughput (100k+ connections, storage engines); standard epoll-based tokio is the right default.

## Cooperative scheduling: blocking starves the executor

An async task only yields control at `.await`. Between await points it runs to completion on its executor thread. So a CPU-bound loop or a **synchronous blocking call** (`std::thread::sleep`, blocking `std::fs`, blocking DNS, a sync DB driver, `Mutex` contention held long) does not yield — it monopolizes that worker thread. On a multi-thread runtime you stall one of N workers; on a current-thread runtime you stall *everything*, including timers and the reactor, so unrelated tasks miss deadlines and connections drop.

Rules, with mechanism:

- **Never call blocking APIs in an async context.** Use the async equivalent (`tokio::fs`, `tokio::time::sleep`, an async DB driver). These register with the reactor and yield.
- **CPU-bound or unavoidable blocking → `tokio::task::spawn_blocking`.** It moves the closure to a dedicated blocking thread pool (default up to 512 threads) so the async workers stay free. Trade-off: the closure gets a plain thread, not an async context — you can't `.await` inside it, and there's a channel hop to get the result back. Use for: image resize, `bcrypt`, a sync C library, blocking file IO you can't avoid. It's the tool for a *one-off* blocking call, but a **smell** when it wraps large sections of ordinary business logic — wrapping a whole validate→enrich→process→format pipeline in it means the logic was never async, so call a plain sync module directly instead of parking microsecond logic on the blocking pool.
- **`tokio::task::block_in_place`** runs blocking code *inline on the current worker* but tells the scheduler to hand off its other tasks to a sibling worker first. Cheaper than `spawn_blocking` (no thread spawn, keeps task-locals), but only works on the multi-thread runtime and still burns the current thread for the duration. Use when the blocking work is short and you'd rather not pay the `spawn_blocking` hop.

```rust
// illustrative — needs tokio
async fn hash_password(pw: String) -> String {
    // bcrypt is CPU-bound and blocking: offload it.
    tokio::task::spawn_blocking(move || bcrypt::hash(pw, 12).unwrap())
        .await
        .unwrap()
}
```

**When to deviate:** a genuinely CPU-heavy pipeline (video encode, large batch compute) doesn't belong on the async runtime's blocking pool at all — use a `rayon` pool or a dedicated worker thread and communicate over a channel.

## `Send` futures and the "held across `.await`" rule

`tokio::spawn` requires `Future + Send + 'static`, because the work-stealing scheduler may move the task between threads at any await point. A future is `Send` only if **every value alive across an `.await` is `Send`**. The compiler computes this structurally from the generated state machine.

The classic trap: holding a non-`Send` guard across a yield.

```rust
// illustrative — does NOT compile if spawned: MutexGuard is !Send
async fn broken(m: &std::sync::Mutex<i32>) {
    let mut g = m.lock().unwrap();
    do_async_thing().await; // guard held across await -> future is !Send
    *g += 1;
}
```

Two things are wrong here and they're distinct: (1) `std::sync::MutexGuard` is `!Send`, so the future can't be spawned; (2) even if it compiled, you'd hold a *blocking* mutex across a suspension — the lock stays taken while the task is parked, inviting deadlock and priority inversion. The same applies to `Rc`, `RefCell` refs, and any raw pointer.

Fixes, in preference order:

1. **Shrink the critical section** so the guard drops before the await. Idiomatic and cheapest — a lock held across an await is almost always a design smell.
   ```rust
   // illustrative
   async fn ok(m: &std::sync::Mutex<i32>) {
       { let mut g = m.lock().unwrap(); *g += 1; } // guard dropped here
       do_async_thing().await;
   }
   ```
2. **If you genuinely must hold state across the await**, use `tokio::sync::Mutex`, whose guard *is* `Send` and whose `.lock().await` yields instead of blocking. Trade-off: it's slower than `std::sync::Mutex`, and its `.lock()` is async, so from sync code you must use `try_lock()` or `blocking_lock()` — and `blocking_lock()` panics if called on a runtime thread. **When to deviate — the default is still `std::sync::Mutex`**: async mutexes are only for the hold-across-await case; for short in-memory updates the std mutex is correct and faster.

Structural consequence: making a future `Send` is not a knob you flip — you fix it by not keeping `!Send` data alive across yields. `spawn_local` (on a `LocalSet`) opts out of `Send` for genuinely thread-affine work.

When you model a session as an async type-state machine, take `self` **by value** in transition methods (not `&mut self`) so ownership moves cleanly into the future across `.await`, and keep one future owning one session rather than splitting state across futures. Because a failed `.await` would otherwise drop the session permanently, have fallible transitions return `Result<Next, (Error, Prev)>` to hand the previous state back for retry; add `Send + 'static` bounds only when the session crosses threads via `tokio::spawn`.

## Cancellation is `drop` — and it's a footgun

There is no cancellation *signal* in Rust async. You cancel a future by **dropping it**. When a future is dropped mid-flight, execution stops at the last suspension point; its captured locals are dropped in place; nothing after the current `.await` runs. This falls out of the poll model for free, but it means:

- **No async destructors.** `Drop::drop` is synchronous. If a task needs async cleanup (flush a buffer, send a close frame, `COMMIT`/`ROLLBACK`), a drop cannot run it — relying on `Drop` here silently does nothing, forces a fire-and-forget `tokio::spawn` that may not run before exit, or blocks. The correct pattern is an explicit `async fn close(self)` documented as the primary cleanup path, with `Drop` kept only as a best-effort sync safety net; alternatively restructure so the durable step happens before the last await.
- **Cancellation safety.** A future is *cancellation-safe* if dropping it between polls loses no data. `tokio::select!` drops all the non-winning branches on every iteration, so any future you put in a `select!` loop must be cancellation-safe or you silently drop bytes. The subtler hazard is *multi-step mutation*: `from.debit(x).await; to.credit(x).await;` loses money if the future is dropped between the two awaits — make such sequences all-or-nothing (a DB transaction that commits last) or structure `select!` so the in-flight critical step is allowed to finish rather than abandoned.

The canonical `select!` trap:

```rust
// illustrative — needs tokio
loop {
    tokio::select! {
        // read() IS documented cancellation-safe; a lost poll reads nothing.
        n = socket.read(&mut buf) => handle(&buf[..n?]),
        // ticker is cancellation-safe.
        _ = interval.tick() => flush().await,
    }
}
```

The danger is buffering combinators: `read_line`, `read_exact`, `lines().next_line()` accumulate into an internal buffer across polls. If a `select!` branch cancels one mid-read, that partial buffer is **lost**. Fix: hoist the not-cancellation-safe future out of the loop and hold it across iterations (poll the same future object each time), or use a framed codec (`tokio_util::codec`) whose partial state lives in the decoder, not in a transient future. **Always check a method's docs for a "Cancel safety" section before putting it in `select!`.**

`select!` also introduces subtle bugs: branch expressions are evaluated eagerly each loop; a `biased;` prefix disables the default random branch order (useful for prioritizing shutdown). Prefer `tokio_util::sync::CancellationToken` (from the separate `tokio-util` dependency) or a `oneshot` shutdown channel for cooperative, *explicit* cancellation over drop-based cancellation when cleanup matters.

## Structured concurrency: run things at once, correctly

`.await` in sequence is sequential. The #1 async performance bug is awaiting independent operations one after another when they could overlap:

```rust
// illustrative — anti-pattern: two round-trips in series
let a = fetch_a().await?;
let b = fetch_b().await?; // waited for a to finish for no reason
```

Tools for concurrency *within one task* (no spawning, so no `Send`/`'static` needed — the futures run concurrently on the current task, interleaved at their await points):

- **`futures::join!` / `tokio::join!`** — drive N futures to completion concurrently, return all results. Use when you need every result and want them overlapped.
- **`tokio::try_join!`** — like `join!` but short-circuits on the first `Err`, dropping (cancelling) the rest. Use for fallible fan-out where any failure aborts the batch.
- **`select!`** — race: return when the *first* completes, drop the losers. Use for timeouts, first-of-N, shutdown.

```rust
// illustrative — needs tokio; overlaps both round-trips
let (a, b) = tokio::try_join!(fetch_a(), fetch_b())?;
```

For a *dynamic* number of tasks that should run on the executor (real parallelism across worker threads, each needing `Send + 'static`):

- **`tokio::task::JoinSet`** — spawn a growing set of tasks, `join_next().await` to collect as they finish, and **dropping the set aborts all remaining tasks**. This is the structured-concurrency primitive: it bounds task lifetime to a scope so you don't leak detached tasks. Prefer it over a `Vec<JoinHandle>` you manually await — a bare `JoinHandle` that's dropped keeps running detached, and a panicked task's error is silently lost unless you check the `JoinError`.

```rust
// illustrative — needs tokio
let mut set = tokio::task::JoinSet::new();
for url in urls {
    set.spawn(fetch(url)); // each runs on the runtime, may be parallel
}
let mut out = Vec::new();
while let Some(res) = set.join_next().await {
    out.push(res??); // JoinError (panic/abort) then the task's own Result
}
// If we return early here, `set` drops and aborts the stragglers.
```

**join vs spawn — the decision:** `join!`/`try_join!` interleave on the *current* thread (concurrency, not parallelism; no `Send` bound; cheapest). `spawn`/`JoinSet` hand tasks to the scheduler (real parallelism; requires `Send + 'static`; has a per-task cost). Reach for `join!` for a fixed handful of IO-bound calls; reach for `JoinSet` when the count is dynamic or you want work spread across cores.

**Borrow-friendly fan-out:** when the concurrent futures must *borrow* local data, `FuturesUnordered` (and `stream.buffer_unordered(n)`) avoid both the `'static` and `Send` bounds `spawn` demands by driving every future on the current task with no thread migration. The tradeoff is a shared task — one future that blocks the executor thread stalls all the others — so keep `JoinSet`/`spawn` for CPU-heavy work needing real parallelism and use `FuturesUnordered` for borrow-heavy, I/O-bound fan-out.

## Why `Pin` exists

A future that borrows its own locals across an `.await` is **self-referential**: the state machine holds both a value and a pointer into that value. If such a machine were moved in memory after being polled once, the internal pointer would dangle. `Pin<P>` is the type-level promise "the pointee will not move again", which is what makes it sound to poll a self-referential future repeatedly. That's the entire reason `Future::poll` takes `self: Pin<&mut Self>`.

Practical consequences for someone who never writes `unsafe`:
- Most futures you `.await` are pinned for you by the `.await` machinery or by `Box::pin`. You rarely touch `Pin` directly.
- To store a future and poll it yourself (e.g. in a manual `Stream` or `select!` over held futures), you must pin it: `let fut = std::pin::pin!(some_future);` (stack-pins, no allocation) or `Box::pin(some_future)` (heap, needed when you must move the pinned future around, e.g. into a `Vec<Pin<Box<dyn Future>>>`).
- `Unpin` types (almost everything that isn't a compiler-generated future/async-block) can move freely even behind `Pin`; that's why you can `Box::pin` and still pass things around.

The unsafe details of pin projection and the `Unpin` auto-trait live in `unsafe-rust.md`. What you need here: `Pin` is not ceremony — it's the mechanism that makes borrow-across-await memory-safe with zero runtime cost.

## `async fn` in traits (stable) and its `Send` gap

Since **Rust 1.75**, `async fn` in traits is stable, implemented via **RPITIT** (return-position `impl Trait` in traits): `async fn get(&self)` desugars to a method returning `impl Future`.

```rust
trait Fetch {
    async fn get(&self, key: u32) -> u32; // stable since 1.75
}

struct Doubler;
impl Fetch for Doubler {
    async fn get(&self, key: u32) -> u32 { key * 2 }
}
```

**The catch:** the returned future's `Send`-ness is *not expressible* in the bare trait. You cannot write `where T::get(..): Send`, so a generic function taking `impl Fetch` and calling `tokio::spawn(x.get(k))` won't compile — the future isn't known to be `Send`. This is the reason `async fn` in traits is still discouraged for *public library* traits that consumers will spawn.

Workarounds, with the decision:

- **`trait_variant::make`** (the modern, recommended path) — generates a `Send`-bounded variant of your trait from one definition. Zero extra allocation; it's still RPITIT under the hood. Use this for public async traits.
  ```rust
  // illustrative — needs the `trait-variant` crate
  #[trait_variant::make(Fetch: Send)]
  trait LocalFetch {
      async fn get(&self, key: u32) -> u32;
  }
  ```
- **`#[async_trait]`** (the historical workaround) — rewrites every async method to return `Pin<Box<dyn Future + Send>>`. It works everywhere and predates RPITIT, but it **heap-allocates and dynamically dispatches every call**. Use it only for `dyn`-compatible (object-safe) async traits, which native RPITIT still can't do. When to deviate from native: you need `dyn MyTrait` (trait objects) — then `async-trait` (or manual `Box::pin`) is still required.
- For an **internal** app trait where you control both sides and don't spawn the futures across threads, plain native `async fn` in traits is fine and cleanest.

## Async closures (stable 1.85)

`async || {}` is a closure that returns a future when called; the three prelude traits `AsyncFn` / `AsyncFnMut` / `AsyncFnOnce` mirror `Fn`/`FnMut`/`FnOnce`. Stable since **1.85**, in the prelude in every edition.

They exist for a reason that is **not** sugar. The pre-1.85 approximation `|| async { … }` returns an inner async block whose future **cannot borrow the closure's captures**: the `Fn` trait's return type is one fixed type with no lifetime tie to the call, so a captured `&mut Vec` cannot be touched across an `.await` inside that future. `AsyncFn` is a *lending* trait — the returned future borrows from the invocation (`&self`/`&mut self`), so it *can* use captured state across await:

```rust
// illustrative — AsyncFnMut whose returned future borrows a capture across .await
let mut acc: Vec<String> = vec![];
let mut push = async |s: String| { acc.push(load(s).await); };
push("k".into()).await;   // future borrows `acc` — impossible with `|| async {}`
```

The second win is higher-ranked async bounds: `impl for<'a> AsyncFn(&'a T)` expresses "callable with any borrow", which `for<'a> Fn(&'a T) -> Fut` cannot — the single `Fut` type has no way to name the per-call lifetime.

**Trade-off / when to deviate:** a callback that neither borrows captures across await nor needs higher-ranked lifetimes is still cleanest as `F: Fn() -> Fut, Fut: Future` — that bound is what most existing APIs already accept, so prefer it for compatibility. There is no `dyn AsyncFn` sugar yet: to store an async closure behind a trait object you still box its future (`Box<dyn Fn() -> Pin<Box<dyn Future<Output = T>>>>`) or take an `async fn`. Reach for `AsyncFn` when a higher-order async API must accept closures that *borrow their environment across the await* — scoped callbacks, retry/backoff wrappers, async combinators.

## Streams — async iterators

`Stream` is the async analog of `Iterator`: `poll_next` yields `Poll<Option<T>>`. It's **not in std** (it lives in `futures::Stream`; a std `AsyncIterator` is still nightly/unstable as of 1.96). Use it for a sequence of async-produced values: incoming connections, DB result rows, Kafka messages, SSE events.

```rust
// illustrative — needs futures/tokio-stream
use futures::StreamExt;
let mut stream = tokio_stream::iter(vec![1, 2, 3]).map(|x| x * 2);
while let Some(v) = stream.next().await {
    process(v).await;
}
```

Judgment: `while let Some(x) = s.next().await` processes items **sequentially**. For concurrent processing use `stream.buffered(n)` / `buffer_unordered(n)` to run up to `n` item-futures at once with **bounded** concurrency — this is the idiomatic backpressure knob, far better than spawning one task per item and blowing up memory. `for_each_concurrent(n, ..)` is the terminal form. Avoid `collect().await` on an unbounded stream — it buffers everything.

## Common pitfalls (each is a real bug)

- **Forgetting `.await`.** `let x = foo();` where `foo` is async binds an unpolled future and does nothing. The compiler's built-in `unused_must_use` lint fires because `async fn` futures are `#[must_use]`, catching this at warning level. (The `must_not_suspend` lint is nightly-only/unstable and unavailable on stable.) If code "silently does nothing", look here first.
- **Accidental sequential awaits** (covered above) — the top async perf bug. Overlap independent IO with `join!`.
- **Unbounded channels.** `tokio::sync::mpsc::unbounded_channel` (and `futures` unbounded) removes backpressure: a fast producer + slow consumer grows the queue until OOM. Default to the **bounded** `channel(capacity)` so `send().await` yields when full and propagates backpressure. Deviate only when you can *prove* the producer is rate-limited elsewhere.
- **Blocking DNS / file IO / `std::thread::sleep`** inside async — starves the worker (covered under cooperative scheduling). `std::net::ToSocketAddrs` resolution is blocking; use the runtime's resolver.
- **Holding `std::sync::MutexGuard`/`Rc`/`RefCell` ref across `.await`** — breaks `Send` and risks deadlock (covered above).
- **Detached tasks & the drop asymmetry.** Dropping a *future* cancels it, but dropping a `tokio::spawn` `JoinHandle` only *detaches* the task — it keeps running with its panic swallowed. To actually cancel a spawned task call `handle.abort()`; awaiting an aborted handle yields a `JoinError` with `is_cancelled() == true`. For structured lifetime use `JoinSet` (drop-aborts) or keep and `.await` the handle.
- **`block_on` inside async.** Calling `Runtime::block_on` (or `futures::executor::block_on`) from within an async task panics on tokio or deadlocks — you're asking a worker to block on itself. Use `.await`.
- **Assuming `.await` is a thread boundary.** It isn't; it's a yield point. Task-local reasoning holds between awaits, but a spawned task may resume on a different thread — hence the `Send` bound.
- **`Poll::Pending` without an arranged wake hangs silently.** A future (or the I/O layer it wraps) that returns `Pending` but never ensures `waker.wake()` will fire is never polled again — the program hangs with no error and no CPU use. Unlike a C# `TaskScheduler` that wakes continuations for you, here you own the wake obligation, so a silent hang almost always means a missing or never-triggered waker registration.

## Sources

- The Rust Programming Language — Ch. 17 "Async and Await" (https://doc.rust-lang.org/book/ch17-00-async-await.html)
- Comprehensive Rust — Async chapter (https://google.github.io/comprehensive-rust/), Microsoft Rust Training — Async book (https://microsoft.github.io/RustTraining/async-book/)
- Rust 1.85 release notes — `async` closures + `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce`; RFC 3668 (https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/, https://rust-lang.github.io/rfcs/3668-async-closures.html, https://doc.rust-lang.org/std/ops/trait.AsyncFn.html)
- Tokio docs & tutorial — scheduling, `spawn_blocking`/`block_in_place`, `select!` cancellation safety, `JoinSet`, `sync::Mutex` (https://tokio.rs, https://docs.rs/tokio)
- `std::future`, `std::pin`, `std::task` reference (https://doc.rust-lang.org/std/)
- Rust 1.75 release notes — `async fn` in traits / RPITIT; `trait-variant` and `async-trait` crate docs
- `futures` crate — `Stream`, `StreamExt`, `join!`/`try_join!` (https://docs.rs/futures)
- Rust API Guidelines & Rust Performance Book (https://rust-lang.github.io/api-guidelines/, https://nnethercote.github.io/perf-book/)
- Microsoft Rust Training, Async book — Ch. 2 "The Future Trait" (silent-hang/waker), Ch. 3 "How Poll Works" (spurious wakes, double-check), Ch. 7 "Executors and Runtimes" (epoll vs io_uring), Ch. 8 "Tokio Deep Dive" (`JoinHandle` detach vs `.abort()`), Ch. 9 "When Tokio Isn't the Right Fit" (`FuturesUnordered`), Ch. 12 "Common Pitfalls" (multi-step cancellation, async `Drop`, `biased;`), Ch. 14 "Async Is an Optimization, Not an Architecture" (thread cost, function coloring) — https://github.com/microsoft/RustTraining/tree/main/async-book
- Microsoft Rust Training, Rust for C# Developers — Ch. 13-1 "async/await Deep Dive" (lazy Future vs eager Task, why Pin); Rust for Python Developers — Ch. 13 "Concurrency" (drop-is-cancel) — https://github.com/microsoft/RustTraining/tree/main/csharp-book , https://github.com/microsoft/RustTraining/tree/main/python-book
- Microsoft Rust Training, Rust Patterns — Ch. 16 "Async/Await Essentials" (`!Send` across await), Ch. 9 "Smart Pointers" (pinning model); Type-Driven Correctness — Ch. 11 "Fourteen Tricks" (async type-state ownership) — https://github.com/microsoft/RustTraining/tree/main/rust-patterns-book , https://github.com/microsoft/RustTraining/tree/main/type-driven-correctness-book

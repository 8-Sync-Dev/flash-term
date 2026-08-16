# IPC and commands — the boundary, and what it costs to cross it

> **Baseline: `tauri 2.11.5`**, verified against docs.rs, `v2.tauri.app`, and
> `tauri-apps/tauri@dev` source on 2026-07-27. Facts read out of source name the file.
> `tauri-build` claims verified against **`tauri-build 2.6.3`** (the version resolved in
> `C:/Users/ADMIN/Documents/GitHub/zus`). Re-verify before assuming a 2.8-era pattern holds.

**Scope.** This file owns the command boundary: the macro, argument injection, threading,
state, errors, transports, events, and channels. It does **not** own:

- capability/permission syntax, ACL precedence, scope objects → `references/security.md`
- IPC benchmark numbers, payload budgets, when a round trip is too expensive →
  `references/performance.md` §IPC
- process model, boot order, `RunEvent`, the full v1→v2 delta → `references/architecture.md`

---

## Threading

**Conclusion first: default every command to `async fn`.** A `#[tauri::command]` that is a
plain `fn` runs on the **tao event loop thread**, which is the main thread, which is the UI
thread for every window in the process. Official wording: *"Commands without the `async`
keyword are executed on the main thread unless defined with `#[tauri::command(async)]`."*
This is the most common "Tauri is slow" report, and it is never Tauri.

**Symptom.** The whole app freezes — all windows, including ones uninvolved in the operation.
The titlebar stops responding, animations stall, the tray menu won't open. It lasts exactly as
long as one command call. Users describe it as "the app hangs when I click save"; a profiler
shows the main thread pegged or blocked in a syscall.

**Cause.** You wrote this:

```rust
// WRONG — tauri 2.11.5. Runs on the tao event loop thread.
#[tauri::command]
fn load_config(path: String) -> Result<Config, Error> {
    let bytes = std::fs::read(&path)?;      // blocking syscall on the UI thread
    Ok(serde_json::from_slice(&bytes)?)
}
```

A 4 ms file read is invisible. The same read on a cold network mount is 400 ms. A `reqwest`
call is unbounded. There is no duration threshold below which this is safe, because you do not
control the environment your users run in — you control only whether the work sits on the event
loop at all.

**Fix.** Three shapes, in order of preference:

```rust
// tauri 2.11.5

// A) Async I/O — the default. Body runs on tauri::async_runtime (a singleton tokio runtime).
#[tauri::command]
async fn load_config(path: String) -> Result<Config, Error> {
    Ok(serde_json::from_slice(&tokio::fs::read(&path).await?)?)
}

// B) Blocking or CPU-bound work you cannot make async — offload explicitly.
#[tauri::command]
async fn hash_archive(path: String) -> Result<String, Error> {
    tauri::async_runtime::spawn_blocking(move || {
        Ok(blake3::hash(&std::fs::read(&path)?).to_hex().to_string())
    })
    .await
    .map_err(|_| Error::Join)?
}

// C) A sync body you do not want to rewrite: the `async` attribute moves it off the loop.
//    Internally tagged "sync_threadpool" (crates/tauri-macros/src/command/wrapper.rs).
#[tauri::command(async)]
fn parse_large_csv(text: String) -> Result<Vec<Row>, Error> { /* … */ }
```

**When a sync command is correct.** Only when the body is (a) pure computation over
already-owned small data with no unbounded loop, **or** (b) the work genuinely *requires* the
main thread. The second is the real one: window creation, menu mutation, and some macOS AppKit
calls must run on the main thread. There, a sync command is not a shortcut but the mechanism —
and it needs a comment saying so, because the next reader will otherwise "fix" it into `async`
and get a panic or a silent no-op. The inverse escape hatch, when you are on a worker thread and
need the main one, is `AppHandle::run_on_main_thread(f)`.

**Trade-off of defaulting to `async`.** A task spawn and a thread hop per call — tens of
microseconds, invisible next to the serde and transport cost of the round trip itself
(`references/performance.md` §IPC). You also inherit the borrow restriction below. Both are cheap
against a frozen UI.

**Not a one-way door, and that is the point.** Flipping a command from sync to async is a
source-level change with no protocol impact; the frontend cannot tell. There is therefore no
excuse for leaving a blocking one in place. What *is* expensive is discovering the problem after
shipping, because by then the freeze is in your users' muscle memory and the bug report says
"the app is slow," which routes the investigation to the wrong layer entirely.

### The async borrow restriction

An `async` command taking a borrowed argument (`&str`, `State<'_, T>`) **must return a
`Result`**. This is not a style rule; the macro enforces it with
`#[diagnostic::on_unimplemented(message = "async commands that contain references as inputs must
return a `Result`")]` or a hard `compile_error!`. The underlying limitation is tracked at
[tauri#2533](https://github.com/tauri-apps/tauri/issues/2533).

```rust
// tauri 2.11.5
async fn increase_counter(state: tauri::State<'_, AppState>) -> Result<u32, Error>  // preferred
async fn read_counter(state: tauri::State<'_, AppState>) -> Result<u32, ()>          // if infallible
async fn greet(name: String) -> String            // owned args -> restriction disappears
```

`Result<T, ()>` rejects the JS promise with `null` if you ever return `Err`, which is a debugging
dead end. Use it where `Err` is unreachable and switch to a real error type the moment it isn't.

---

## Command mechanics

**Mechanism.** `#[tauri::command]` leaves your function alone and additionally emits a hidden
macro named `__cmd__<name>`. `tauri::generate_handler![a, b, c]` expands those into a single
`Fn(Invoke<R>) -> bool` dispatcher, which `Builder::invoke_handler` installs. The `bool` means
"did I handle this command name" — that is how plugins compose (`Plugin::extend_api` has the
same shape) and why an unregistered name produces a *runtime* "command not found", never a
compile error.

```rust
// tauri 2.11.5 — src-tauri/src/lib.rs
#[tauri::command]
fn my_custom_command(invoke_message: String) {
    println!("got: {invoke_message}");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![my_custom_command])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

```ts
import { invoke } from '@tauri-apps/api/core';   // v2 path; v1 was '@tauri-apps/api/tauri'
await invoke('my_custom_command', { invokeMessage: 'Hello!' });
```

**Argument deserialization.** The invoke payload is a JSON object (or a raw byte body — see
`## Binary`), and each non-injected parameter is deserialized **by name** with serde:

- Parameters match by key, not position. Renaming a Rust parameter is a breaking frontend
  change with no compiler help on either side. **Treat parameter names as public API.**
- A missing key deserializes as `null`: `None` for `Option<T>`, a rejected promise carrying a
  deserialization error for anything else. Never a panic.
- Default argument casing is **camelCase**: Rust `invoke_message` ⇄ JS `invokeMessage`.

**Symptom → cause → fix: arguments arrive as `undefined`, or "invalid args".** The frontend
sent `{ invoke_message }` while the command expects default camelCase — or someone added
`rename_all` and half the callers didn't move. Fix: pick one convention per project and
enforce it in review, not per command. `#[tauri::command(rename_all = "snake_case")]` switches
the whole command to `{ invoke_message }`.

**The full attribute surface** (verified in `crates/tauri-macros/src/command/wrapper.rs`; the
compiler itself says *"unexpected input, expected one of `rename_all`, `rename`, `root`,
`async`"*):

| Attribute | Accepts | Effect, and why it exists |
| --- | --- | --- |
| `rename_all` | **only** `"camelCase"` or `"snake_case"` | Argument-key casing. Anything else fails with `expected "camelCase" or "snake_case"` — there is no `kebab-case`. |
| `rename` | string | Overrides the name `invoke` uses. The only namespacing tool the macro gives you (see `## Scale`). |
| `root` | path | The `::tauri` root path. Needed only when re-exporting from a crate that renames or re-exports `tauri` — i.e. plugin authoring, `references/plugins.md`. |
| `async` | flag | Forces a sync `fn` body onto the async runtime's blocking pool. |

**Argument injection — resolved from context, not from the payload.** Any type implementing
`tauri::ipc::CommandArg` can be a parameter and is filled in by the dispatcher. These never
appear in the invoke payload, so adding one is not a breaking change.

```rust
// tauri 2.11.5 — every parameter below is injected; none come from JS
#[tauri::command]
async fn do_work(
    app: tauri::AppHandle,                      // clone-cheap handle to everything
    webview_window: tauri::WebviewWindow,       // the invoking WebviewWindow
    window: tauri::Window,                      // the invoking OS window
    webview: tauri::Webview,                    // the invoking webview
    state: tauri::State<'_, AppState>,          // managed state, keyed by type
    on_event: tauri::ipc::Channel<MyEvent>,     // streaming handle
    request: tauri::ipc::Request<'_>,           // raw body + headers
    scope: tauri::ipc::CommandScope<MyScope>,   // ACL command scope -> references/security.md
    global: tauri::ipc::GlobalScope<MyScope>,   // ACL plugin global scope
) -> Result<(), Error> {
    Ok(())
}
```

**Which window type to inject.** `WebviewWindow` for the 99% case — it wraps a `Window` plus
its `Webview` and carries both APIs. Take `Window` only when you mean the OS window and want
to be explicit that the webview is irrelevant; take `Webview` only in multi-webview builds
(behind the `unstable` feature; `references/architecture.md` §multi-window vs multi-webview).
Injecting `WebviewWindow` is also how a command learns **who called it** — `window.label()` is
your authorization input whenever different windows render content at different trust levels,
and that check belongs in Rust, not in a capability glob (`references/security.md`).

**Generic-over-runtime form** — `async fn cmd<R: Runtime>(app: AppHandle<R>, win:
WebviewWindow<R>)` — is required to exercise a command under `tauri::test::MockRuntime`
(`references/debugging-and-testing.md`). With the default `wry` feature the generic defaults to
`Wry`, which is why the non-generic form compiles at all. It is noisier everywhere and buys
unit-testability: adopt it per-module, for modules you actually intend to test, not repo-wide
as a reflex.

### Errors: why `E: Serialize`

**Mechanism.** The invoke promise **rejects with the serialized error value**. There is no side
channel — the error crosses the same serde boundary as the success value, so `Result<T, E>`
requires both `T: Serialize` and `E: Serialize`.

Almost no `std` or third-party error type implements `Serialize` (that would force a wire
format on every consumer), which is why every real Tauri codebase ends up with a local error
enum: `thiserror` for the `Display`/`From` plumbing, plus a hand-written `Serialize` that
projects it into a shape the frontend can discriminate on.

```rust
// tauri 2.11.5
#[derive(Debug, thiserror::Error)]
enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("failed to parse as string: {0}")]
    Utf8(#[from] std::str::Utf8Error),
}

#[derive(serde::Serialize)]
#[serde(tag = "kind", content = "message", rename_all = "camelCase")]
enum ErrorKind { Io(String), Utf8(String) }

impl serde::Serialize for Error {
    fn serialize<S: serde::ser::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let msg = self.to_string();
        match self {
            Self::Io(_) => ErrorKind::Io(msg),
            Self::Utf8(_) => ErrorKind::Utf8(msg),
        }
        .serialize(serializer)
    }
}
```

```ts
type ErrorKind = { kind: 'io' | 'utf8'; message: string };
invoke('read').catch((e: ErrorKind) => {
  if (e.kind === 'io') { /* offer retry */ } else { /* show parse detail */ }
});
```

**Why the indirection instead of `#[derive(Serialize)]` on `Error` directly.** Deriving on the
`thiserror` enum leaks the *source* errors' structure — `std::io::Error` is not `Serialize`, and
even where a variant's payload is serializable you have coupled the wire format to your internal
error tree. The projection enum is the wire contract; the `thiserror` enum is the internal one.
They are allowed to diverge, and they will.

**The prototype shortcut and its cost.** `.map_err(|e| e.to_string())` returning
`Result<T, String>` is fine for an afternoon and bad the moment the frontend must *react*
differently to different failures, because the only way to discriminate is substring-matching an
English message — which breaks under i18n, under a dependency bump that reworded its `Display`,
and under any error you did not anticipate. Converting later is mechanical but repo-wide, so
decide early.

**Where errors are *not* the right channel.** A command that fails as part of normal operation
(a lookup miss, a user cancelling a dialog) should return `Ok(Option<T>)` or an explicit enum,
not `Err`. Rejecting the promise forces every caller into a `try/catch` for a non-exceptional
outcome and pollutes whatever frontend error reporting you have wired up.

---

## State

**Mechanism.** Managed state is a **type-keyed container**, not a named one.
`Manager::manage<T: Send + Sync + 'static>(state) -> bool` registers exactly **one value per
type**; retrieval is `Manager::state::<T>()` or `try_state::<T>() -> Option<..>`; removal is
`unmanage::<T>() -> Option<T>`. `State<T>` is `Deref<Target = T> + Clone + CommandArg`.

"Keyed by type" is the whole design and the whole trap. It is why injection needs no wiring —
the dispatcher resolves the parameter's type against the container — and it is why a
mismatched type is a **runtime panic instead of a compile error**.

Register with `Builder::manage` (pre-boot) or `Manager::manage` (any time, typically inside
`setup`, where plugins are already initialized — `references/architecture.md` §the `setup`
hook). **`manage` returns `bool` and everyone ignores it.** `false` means a value of that type
was already managed and **yours was discarded**. In one `lib.rs` that never happens; in a
workspace where a module and a plugin both manage a `Mutex<Config>` it happens silently and
half the app reads a struct nobody writes. Assert on it in debug builds.

### Mutability: `Mutex`, `RwLock`, or `tokio::sync::Mutex`

`State` hands out shared references, so mutation needs interior mutability.

```rust
// tauri 2.11.5
use std::sync::Mutex;

#[derive(Default)]
struct AppState { counter: u32 }

tauri::Builder::default()
    .setup(|app| { app.manage(Mutex::new(AppState::default())); Ok(()) });

#[tauri::command]
fn increase_counter(state: tauri::State<'_, Mutex<AppState>>) -> u32 {
    let mut s = state.lock().unwrap();
    s.counter += 1;
    s.counter
}
```

**`std::sync::Mutex` is the default and usually correct**, including in async code. The Tauri
docs quote tokio directly: *"Contrary to popular belief, it is ok and often preferred to use
the ordinary Mutex from the standard library in asynchronous code … The primary use case for
the async mutex is to provide shared mutable access to IO resources such as a database
connection."*

- **`tokio::sync::Mutex`** only when you must hold the guard **across an `.await`**. It costs
  an allocation and a scheduler interaction per lock — that is the price of yielding correctly.
- **`std::sync::RwLock`** when reads vastly outnumber writes *and* the critical section is
  non-trivial. Not a free win: writer starvation and a higher uncontended cost are real.
  `[COMMUNITY]` For a small struct read on every IPC call, a plain `Mutex` usually wins.

**You do not need `Arc`.** Official: *"you don't need to use `Arc` for things stored in `State`
because Tauri will do this for you."* Managing `Arc<Mutex<T>>` forces every consumer to ask for
`State<'_, Arc<Mutex<T>>>` — one more way to trip the type-mismatch panic below.

### Symptom → cause → fix: holding a `MutexGuard` across `.await`

**Symptom, form one — it doesn't compile:** `future cannot be sent between threads safely` on
an async command or an `async_runtime::spawn`.

**Symptom, form two — it compiles and the app hangs** under concurrent commands. This is the
dangerous one: no error, no panic, just a UI that stops responding to anything touching that
state.

**Cause.** `std::sync::MutexGuard` is `!Send`. Awaiting while holding it forces the guard into
the generated future's state machine, so the future becomes `!Send` and the spawn rejects it
(form one). Where it *does* compile, the guard survives a yield point: the task parks holding
the lock, and any other task needing it deadlocks, because a std mutex has no concept of
yielding to the runtime (form two).

**Fix.** Reach for A first — it is usually the honest description of what the code needs.

```rust
// tauri 2.11.5

// A) Narrow the critical section so the guard drops before the await.
#[tauri::command]
async fn refresh(state: tauri::State<'_, Mutex<AppState>>) -> Result<(), Error> {
    let url = { state.lock().unwrap().endpoint.clone() };  // guard dropped at `}`
    let body = fetch(&url).await?;
    state.lock().unwrap().cache = body;
    Ok(())
}

// B) You genuinely need the lock held across the await -> tokio Mutex.
#[tauri::command]
async fn migrate(state: tauri::State<'_, tokio::sync::Mutex<Db>>) -> Result<(), Error> {
    let mut db = state.lock().await;
    db.run_migrations().await?;     // guard is Send and yields properly
    Ok(())
}
```

The clone in shape A is the trade-off, and it is the right one: copying a `String` to avoid
serialising every concurrent caller behind a network round trip. If the cloned value is
genuinely large, the lock is protecting too much — split the state rather than reaching for a
tokio mutex to dodge a memcpy.

### Symptom → cause → fix: `no state managed for field of type …`

**Symptom.** A runtime panic on first invocation of a command, naming a type.

**Cause.** Two possibilities the message does not distinguish: the `State<'_, T>` type
parameter does not exactly match what was managed, or `manage` was never called (or ran *after*
the first command). Official Caution: *"If you use the wrong type for the `State` parameter, you
will get a runtime panic instead of compile time error. For example, if you use
`State<'_, AppState>` instead of `State<'_, Mutex<AppState>>`, there won't be any state managed
with that type."*

**Fix.** Make the type unspellable-wrong with an alias used **verbatim** at both ends:

```rust
// tauri 2.11.5
#[derive(Default)]
struct AppStateInner { counter: u32 }
type AppState = Mutex<AppStateInner>;   // the only name either side ever writes
// app.manage(AppState::default())      and      state: tauri::State<'_, AppState>
```

…and do **not** wrap the alias in another `Mutex` — same bug, new disguise. In library code
prefer `try_state::<T>()` so a missing registration is a handled `None`, not a panic that takes
the window down.

### `AppHandle` — the escape hatch from `State`'s lifetime

`State<'_, T>` borrows from the invocation, so it cannot cross into a spawned thread or a
`'static` closure. `AppHandle` can: it is `Clone + Send + Sync`, implements `Manager`,
`Listener`, `Emitter` and `CommandArg`, and the docs state that *"`AppHandle`s are deliberately
cheap to clone for use-cases like this"* — refcounted handles to the manager and runtime, not a
deep copy.

```rust
// tauri 2.11.5
let handle = app.handle().clone();       // App::handle() returns &AppHandle
std::thread::spawn(move || {
    handle.state::<AppState>().lock().unwrap().counter += 1;
});
```

Full `AppHandle` semantics live in `references/architecture.md` §`AppHandle` semantics.

### Per-window state

**There is no per-window state container in v2.** `manage` is app-global and type-keyed;
`Window`, `Webview` and `WebviewWindow` all reach state through `Manager`, which resolves to the
one app-wide `StateManager`. That is a design decision, not an omission: windows come and go,
and a container keyed by a transient label would need a lifecycle Tauri cannot infer.

The idiomatic pattern is an explicit `Mutex<HashMap<String, PerWindow>>` in managed state, keyed
by `window.label()` — plus the cleanup, which is the part people forget:

```rust
// tauri 2.11.5 — the arm whose absence is the leak
.on_window_event(|window, event| {
    if matches!(event, tauri::WindowEvent::Destroyed) {
        window.app_handle().state::<WindowStates>()
            .0.lock().unwrap().remove(window.label());
    }
})
```

*Symptom: memory grows as users open and close windows.* That arm is missing.

For per-command **resource** lifetimes — open files, sockets, handles the frontend holds an id
to — v2 gives you `Manager::resources_table() -> MutexGuard<'_, ResourceTable>`, an id-keyed
table with explicit close semantics. That is what the official plugins use, and it is right when
the frontend owns the lifetime; a `HashMap` in your own state is right when Rust does.

---

## Transport

**Mechanism.** The v2 bridge has **two transports with automatic, one-way fallback**
(`crates/tauri/scripts/ipc-protocol.js`).

1. **Custom protocol — the fast path.** The frontend issues a real `fetch()` POST to a custom
   `ipc` scheme URL. The **command name is the URL path**; everything else rides in headers.
2. **`postMessage` — the fallback.** `window.ipc.postMessage(data)`, i.e. wry's
   `with_ipc_handler`. Used **always on Android** (Android cannot read request bodies over the
   custom protocol) and permanently after any custom-protocol failure.

```js
// crates/tauri/scripts/ipc-protocol.js — abridged, structure verbatim
const canUseCustomProtocol = osName !== 'android'

const headers = new Headers((options && options.headers) || {})
headers.set('Content-Type', contentType)
headers.set('Tauri-Callback', callback)
headers.set('Tauri-Error', error)
headers.set('Tauri-Invoke-Key', __TAURI_INVOKE_KEY__)

fetch(window.__TAURI_INTERNALS__.convertFileSrc(cmd, 'ipc'), {
  method: 'POST', body: data, headers
})
  .then(res => { /* res.headers.get('Tauri-Response') === 'ok' ? callback : error */ })
  .catch(e => {
    console.warn('IPC custom protocol failed, Tauri will now use the postMessage interface instead', e)
    customProtocolIpcFailed = true          // sticky for the rest of the session
    sendIpcMessage(message)                 // retry over postMessage
  })
```

### Symptom → cause → fix: the IPC silently downgrades

**Symptom.** One `IPC custom protocol failed, Tauri will now use the postMessage interface
instead` warning early in the console — often during startup, often ignored — and then the
entire session's IPC is inexplicably slower. Large payloads are worst. Reloading the window
fixes it "sometimes" (whenever the triggering condition doesn't recur), which makes it look
intermittent and unreproducible.

**Cause.** `customProtocolIpcFailed = true` is set on **any** `fetch` rejection and is
**never reset for the lifetime of the page**. One CSP directive that omits the `ipc:` scheme,
one webview policy blocking a custom scheme, one transient failure during startup — and every
subsequent invoke for that session takes the slow path. There is no API to retry the fast
path and no runtime signal other than that single warning.

**Why the fallback is slower, concretely.** Under the custom protocol the response is a real
HTTP response: `application/json` for `InvokeResponseBody::Json`, `application/octet-stream`
for `::Raw`, with `Tauri-Response: ok|error`. Under `postMessage` the Core replies by
**evaluating JavaScript in the webview** — `webview.eval(format_callback…)` — so the payload
is embedded in a JS source string, parsed by the JS engine, and escaped along the way. Binary
data cannot ride that path at all without an encoding hop. (On non-Apple platforms a JSON
payload starting with `{` or `[` is instead routed through a `Channel`; macOS and iOS always
take the `eval` path. Source: `protocol.rs`, `can_use_channel_for_response`.)

**Fix.** Treat that warning as an error, not a warning.

1. Reproduce it in a dev build and read the rejection reason the `catch` logs — it names the
   real cause (usually CSP).
2. Fix the CSP so the `ipc:` scheme is permitted, rather than living with the downgrade.
   CSP construction is `references/security.md`.
3. In CI or a smoke test, fail the run if that string appears in the console. It is a
   one-line check that catches a whole class of "the app got slow this release" regressions
   before users do.

**When the downgrade is expected and fine.** Android — always, by design. Do not chase it
there; design raw-body commands to degrade instead (`## Binary`).

### The header contract and the invoke key

Rust side (`crates/tauri/src/ipc/protocol.rs`):

```rust
const TAURI_CALLBACK_HEADER_NAME:   &str = "Tauri-Callback";
const TAURI_ERROR_HEADER_NAME:      &str = "Tauri-Error";
const TAURI_INVOKE_KEY_HEADER_NAME: &str = "Tauri-Invoke-Key";
const TAURI_RESPONSE_HEADER_NAME:   &str = "Tauri-Response";   // "ok" | "error"
```

`parse_invoke_request` **hard-requires** `Origin`, `Tauri-Invoke-Key`, `Tauri-Callback` and
`Tauri-Error`. Only `POST` and `OPTIONS` are accepted (`405` otherwise); `OPTIONS` answers
preflight with `Access-Control-Allow-Headers: *`. `Content-Type` must be `application/json` or
`application/octet-stream` — anything else returns `content type {x} is not implemented`.

The **invoke key** is a runtime-generated secret (`generate_invoke_key()`) injected into
initialized frames. It is deliberately declared *outside* `window.__TAURI_INVOKE__` — the
source comment says "to prevent the key from being leaked by `.toString()`" — and its job is
to stop arbitrary iframes or remote content from forging IPC. It is a defence-in-depth layer
on the same trust boundary the ACL guards; neither replaces validation inside your command
(`references/security.md`).

*Symptom: `invoke` works in dev, fails in the built app on Windows.* Not the invoke key — v2
serves production assets from **`http://tauri.localhost`** where v1 used `https://`. Origin,
CSP and cookie assumptions break. `app.windows[].useHttpsScheme: true` or
`WebviewWindowBuilder::use_https_scheme` restores `https`. Details and the storage-loss
consequence: `references/cross-platform.md` §Windows.

---

## Binary

**Conclusion: never return `Vec<u8>` from a command.** Everything crossing the boundary goes
through serde, and `Vec<u8>` serializes to a **JSON array of decimal numbers** — roughly 3–4
bytes of wire per byte of payload, plus the JS engine parsing every element into a boxed
number. Official warning: *"This can slow down your application if you try to return a large
data such as a file or a download HTTP response."*

*Symptom: returning a file or an image from a command is glacially slow, and the app allocates
far more than the file's size.* That is the JSON-array encoding. Fix:

```rust
// tauri 2.11.5
use tauri::ipc::Response;

#[tauri::command]
fn read_file(path: String) -> Result<Response, Error> {
    Ok(Response::new(std::fs::read(path)?))   // InvokeResponseBody::Raw, octet-stream
}
```

`Response::new(body: impl Into<InvokeResponseBody>)`, where
`enum InvokeResponseBody { Json(String), Raw(Vec<u8>) }` has `From<String>`, `From<Vec<u8>>`,
`From<InvokeBody>`, and `.deserialize::<T>()`. The mirror enum for input is
`enum InvokeBody { Json(serde_json::Value), Raw(Vec<u8>) }`.

**Trade-off.** You lose typed deserialization on the JS side — the frontend receives an
`ArrayBuffer` and must know the format. That is the correct trade for images, archives, model
weights, or anything you were about to base64. It is the wrong trade for a 200-byte struct,
where JSON costs nothing and buys you a typed object.

**Raw request bodies and headers — the inbound direction:**

```rust
// tauri 2.11.5
#[tauri::command]
fn upload(request: tauri::ipc::Request) -> Result<(), Error> {
    let tauri::ipc::InvokeBody::Raw(upload_data) = request.body() else {
        return Err(Error::RequestBodyMustBeRaw);
    };
    let Some(auth) = request.headers().get("Authorization") else {
        return Err(Error::MissingHeader("Authorization"));
    };
    Ok(())
}
```

```ts
const data = new Uint8Array([1, 2, 3]);
await invoke('upload', data, { headers: { Authorization: 'apikey' } });
```

Passing an `ArrayBuffer`/`Uint8Array` as the payload makes the request
`application/octet-stream`; the **third** `invoke` argument carries headers.

**Platform caveats you must design around.**

- *Symptom: a raw-body command works on desktop and receives an empty body on Android.*
  Android cannot read request bodies over the custom protocol; the runtime falls back to
  `postMessage` and `has_payload` is false. If you target Android, a raw-body command needs a
  JSON path too — this is a real API-shape constraint, not a polyfill.
- Linux raw bodies require the **`linux-protocol-body`** Cargo feature and
  **webkit2gtk ≥ 2.40**. Both are new in v2. On an older distro the feature compiles and the
  body does not arrive. `references/cross-platform.md` §Linux.

Payload-size thresholds and measured costs: `references/performance.md` §IPC.

---

## Events

**Mechanism.** v2 redesigned events around **targets**, not sources. `App`, `AppHandle`,
`Window`, `Webview` and `WebviewWindow` all implement `tauri::Emitter` and `tauri::Listener`.
`Emitter` gives you `emit` / `emit_to` / `emit_filter` (plus `emit_str*` variants taking a
pre-serialized payload); `Listener` gives you `listen` / `once` / `unlisten` and the
`listen_any` / `once_any` pair. Targets are `tauri::EventTarget`: `Any` · `AnyLabel { label }` ·
`App` · `Window { label }` · `Webview { label }` · `WebviewWindow { label }`.

**Choosing between the three emitters:**

```rust
// tauri 2.11.5
use tauri::{Emitter, EventTarget};

// Broadcast — every listener, every window. Correct only while every window should react.
app.emit("download-progress", progress)?;

// One target — only listeners registered by the webview labeled "login".
app.emit_to("login", "login-result", result)?;

// Predicate — a set you cannot name statically.
app.emit_filter("open-file", path, |target| match target {
    EventTarget::WebviewWindow { label } => label == "main" || label == "file-viewer",
    _ => false,
})?;
```

The moment one window is a settings dialog that must not react, `emit` becomes a **correctness**
bug rather than a performance one — the payload is serialized per target either way, but now the
wrong window acts on it. `emit_filter` costs one closure call per registered target, which is
nothing next to serialization. Choose on semantics, not cost.

**Symptom → cause → fix: `emit_to("main", …)` is not received by a global `listen()` in Rust.**
Cause: *"Webview-specific events are not triggered to regular global event listeners. To listen
to any event you must use `listen_any` instead of `listen`."* Fix: `listen_any`. The JS side is
inverted, which is the confusing part: bare `listen()` from `@tauri-apps/api/event` behaves like
`listen_any` unless you pass `{ target }`, while `WebviewWindow.listen` is target-scoped.

**Symptom → cause → fix: a handler fires five times after navigating around your SPA.** Cause:
*"The `listen` function keeps the event listener registered for the entire lifetime of the
application."* A page reload or real navigation unregisters listeners automatically — an SPA
router performs neither, so every route change stacks another listener. Fix: unlisten on unmount,
and note that `listen` returns a **Promise** of the unlisten function, which is where most of
these leaks actually come from:

```ts
// WRONG — `unlisten` is a Promise, not a function. Nothing is ever removed.
const unlisten = listen('sync-complete', () => {});
unlisten();

// RIGHT — and in a framework cleanup: () => { p.then((fn) => fn()) }
const unlisten = await listen('sync-complete', () => {});
unlisten();
```

Rust side: `listen`/`once` return an `EventId`; `unlisten(id)` removes it, and a handler can
deregister itself via `event.id()` plus a cloned `AppHandle`. `once` auto-unregisters after the
first fire — prefer it for one-shot handshakes so there is no cleanup to forget.

Built-in `tauri://*` event names (`resize`, `move`, `close-requested`, `destroyed`, `focus`,
`blur`, `scale-change`, `theme-changed`, `window-created`, `suspended`, `resumed`,
`webview-created`, `drag-enter`, `drag-over`, `drag-drop`, `drag-leave`) are documented with their
window semantics in `references/desktop-ux.md`. Custom names may contain only alphanumerics, `-`,
`/`, `:`, `_`.

**When events are the wrong tool — more often than people assume.** From the docs: *"The event
system is not designed for low latency or high throughput situations."* Concretely: no strong
typing, payloads are always JSON strings, **no ACL support** so you cannot fine-grain who may emit
or receive, and under the hood it *"directly evaluates JavaScript code."* Ordering is honest but
weak — listeners are called in registration order, but *"if a listener is async and the event
emitter sends multiple events in rapid succession, the listeners may process events out of
order."*

*Symptom: a progress bar jumps backwards under load.* That is exactly the out-of-order case. The
fix is not a sequence number you add yourself; it is a Channel.

---

## Channels

**Conclusion: any stream of more than a handful of messages should be a `Channel`, not
events.** Channels are *"designed to be fast and deliver ordered data"*, they are typed by
their `TSend`, and they are scoped to the one caller that created them instead of broadcast.

Surface: `Channel::new(on_message)` · `Channel::id() -> u32` · `Channel::send(data) -> Result<()>`,
with `impl Clone + Serialize + CommandArg`.

```rust
// tauri 2.11.5 — a Channel parameter is just another CommandArg
use tauri::ipc::Channel;

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase",
        tag = "event", content = "data")]
enum DownloadEvent { Started { content_length: usize }, Progress { chunk: usize }, Finished }

#[tauri::command]
async fn download(url: String, on_event: Channel<DownloadEvent>) -> Result<(), Error> {
    on_event.send(DownloadEvent::Started { content_length: 1000 })?;
    // … on_event.send(DownloadEvent::Progress { chunk })? per chunk …
    on_event.send(DownloadEvent::Finished)?;
    Ok(())
}
```

```ts
import { invoke, Channel } from '@tauri-apps/api/core';

const onEvent = new Channel<DownloadEvent>();
onEvent.onmessage = (message) => console.log(`got download event ${message.event}`);
await invoke('download', { url, onEvent });
```

**Why passing a `Channel` as a command argument "just works".** A `Channel` serializes to the
**string** `"__CHANNEL__:<id>"` (`IPC_PAYLOAD_PREFIX = "__CHANNEL__:"`) and deserializes back by
parsing that prefix (`crates/tauri/src/ipc/channel.rs`). It is a handle, not a transport — which
is also why it is `Clone`, can be stashed in managed state, and can be written to long after the
originating command returned.

**How messages travel, and why it matters for tuning.** Small JSON messages are pushed with
`webview.eval(...)`. Larger or raw payloads are parked in a Rust-side `ChannelDataIpcQueue` and
the webview is told to pull them — that pull is
`FETCH_CHANNEL_DATA_COMMAND = "plugin:__TAURI_CHANNEL__|fetch"` (over
`CHANNEL_PLUGIN_NAME = "__TAURI_CHANNEL__"`), carrying
`CHANNEL_ID_HEADER_NAME = "Tauri-Channel-Id"`:

```js
invoke('plugin:__TAURI_CHANNEL__|fetch', null, { headers: { 'Tauri-Channel-Id': id } })
```

The source records the measured threshold for choosing between the two paths: *"Maximum size a
JSON we should send directly without going through the fetch process // 8192 byte JSON payload
runs roughly 2x faster through eval than through fetch on WebView2 v135."* Practical
consequence: **many small messages beat few large ones**, and crossing ~8 KB per message
silently switches transports. If you are streaming, chunk small.

**Ordering is engineered, not incidental.** The JS `Channel` class carries `#nextMessageIndex`,
`#pendingMessages` and `#messageEndIndex`; each message has an `index`, out-of-order arrivals are
buffered and replayed in sequence once the gap fills — *"the index is used as a mechanism to
preserve message order."* It exists precisely because the async fetch path would otherwise
reorder. That guarantee is the concrete reason to prefer a Channel over events for anything
sequential.

### Why a Channel is the right primitive for LLM token streams

Every property a token stream needs is one a Channel has and events lack:

- **Ordering.** Tokens reassembled out of order are corrupt text, not a stale progress bar.
  Events explicitly do not guarantee this across async listeners; Channels do.
- **Per-request scoping.** Two concurrent generations in two panes each get their own `Channel`
  id. With events you would broadcast both streams to every listener and filter by a correlation
  id you invented — reimplementing channels, badly, with a cross-window leak on the way.
- **Typed variants.** A `#[serde(tag = "event")]` enum models `Token` / `ToolCall` / `Done` /
  `Failed` as one exhaustively-matchable type on both sides.
- **Lifetime.** The Channel dies with the request. There is no listener to leak on route change
  — the entire SPA leak class above simply does not apply.

```rust
// tauri 2.11.5 — the shape to reach for
#[tauri::command]
async fn complete(prompt: String, on_event: Channel<Completion>) -> Result<(), Error> {
    let mut stream = client.stream(&prompt).await?;
    while let Some(chunk) = stream.next().await {
        match chunk {
            Ok(text) => on_event.send(Completion::Token { text })?,
            // In-stream, not Err: the frontend has already rendered partial output and needs
            // the failure on the same path as the tokens, not as a rejected promise.
            Err(e) => { on_event.send(Completion::Failed { message: e.to_string() })?; break }
        }
    }
    on_event.send(Completion::Done { finish_reason: "stop".into() })?;
    Ok(())
}
```

That comment is the design decision worth keeping: once a stream has emitted its first token,
errors belong **inside** the stream. A rejected promise arrives on a different code path from the
tokens, and the UI ends up with rendered text and no terminal state.

**Cancellation is yours to build.** `Channel` has no close or cancel. The idiomatic shape is a
second command that flips a `CancellationToken` (or `AtomicBool`) held in state keyed by the
channel's `id()`, checked by the streaming loop between sends. Do not skip it: without it a user
navigating away leaves a generation running and billing.

**Binary streaming works too** — `Channel<&[u8]>`, e.g.
`async fn load_image(path: PathBuf, reader: Channel<&[u8]>)` sending chunks with
`reader.send(&chunk)`. Same ordering guarantees, no JSON-array encoding.

**The other direction.** Frontend→Rust streaming is not a Channel; it is repeated `invoke` calls,
ideally with raw bodies (`## Binary`). A Channel is created by the frontend and written by Rust.
For a genuinely bidirectional session, pass a `Channel` *and* keep a command for the inbound half
— that pairing is the pattern, and it is why `Channel` is `Clone` and storable in state.

---

## Registration

**Mechanism.** `generate_handler!` takes **an array, and may be called only once.** The docs
are explicit: *"you cannot call `invoke_handler` multiple times. Only the last call will be
used."*

*Symptom: half your commands return "command not found", and the half that works is the last
group you added.* Two `.invoke_handler()` calls; all but the final one were silently
discarded. There is no warning. This is the single most expensive five minutes in a growing
Tauri codebase, because the natural instinct when a module grows is to add a second call.
The supported way to compose command sets across crate boundaries is a **plugin**
(`Plugin::extend_api`) — `references/plugins.md`.

**Module and visibility rules, which are not symmetric:**

- Commands in `lib.rs` **cannot be `pub`** — the generated `__cmd__<name>` macro collides:
  `error[E0255]: the name '__cmd__command_name' is defined multiple times`.
- Commands in a **separate module must be `pub`**.

**Names are global, not module-scoped.** *"The command name is not scoped to the module so
they must be unique even between modules."* You register `commands::db::query` and the
frontend calls `invoke("query")` — the path is stripped. Two `query` commands in two modules
is a compile error at the handler, and worse, a *near*-collision (`get` in three modules) is a
design smell you only notice from the frontend. Namespace deliberately with
`#[tauri::command(rename = "db_query")]`.

**`AppManifest::commands` in `build.rs` — what it actually does.** By default `tauri-build`
generates the app's ACL manifest by parsing a `permissions` directory. `AppManifest::commands`
instead **autogenerates a permission pair per command**, in the format `allow-$command` and
`deny-$command`, with `$command` in snake_case (verified in `tauri-build 2.6.3`,
`src/acl.rs:98-103`):

```rust
// src-tauri/build.rs — tauri-build 2.6.3
fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new()
            .app_manifest(tauri_build::AppManifest::new().commands(&["read_file", "write_file"])),
    )
    .expect("failed to run tauri-build");
}
```

**The ACL consequence in one line:** your own commands become referenceable ACL identifiers,
so they can be allowed or denied per capability instead of being implicitly reachable by any
window that can reach the IPC — and once you opt in, a command with no matching permission in
any capability is **denied**. That is a deliberate posture change; make it consciously and
read `references/security.md` before flipping it.

ZUS does **not** use it: `src-tauri/build.rs:66` is a bare `tauri_build::build()`, so all ~250
of its commands are reachable from any window that can reach the IPC, and the trust boundary
is entirely the validation inside each command body. That is a defensible choice for a
single-window app with no untrusted content, and an indefensible one the moment a second
window renders anything remote.

**`build.removeUnusedCommands`** (default `false`) makes `tauri build` read the ACL and strip
plugin commands no capability permits — a binary-size and attack-surface win with real
caveats (it does not account for dynamically added ACLs from the `dynamic-acl` feature, which
is on by default; requires tauri-plugin ≥ 2.1 and tauri ≥ 2.4; and `tauri-build 2.6.3` warns
it *"does not work with a custom capabilities path"*). Decide it in
`references/security.md`, not here.

---

## Scale

**What ~250 commands actually looks like.** ZUS registers roughly 250 commands in a single
`generate_handler!`, grouped by comment banner — agent, env studio, migration, automations,
filesystem, path, text, compression, crypto, and the rest — across 24 workspace crates
(`references/case-studies.md` §11). It works. It is not free.

**What breaks, in the order you will hit it:**

1. **Compile time, and specifically incremental compile time.** `generate_handler!` expands
   into one function whose body references every command. Touching *any* command in the list
   invalidates that function, so the dispatcher recompiles on every command edit. The list
   itself is cheap to expand; the problem is that it is a single translation-unit-wide
   dependency edge from every command to the crate root. Mitigation: keep command *bodies* in
   separate crates (ZUS's 24-crate workspace is exactly this) so the recompile is the thin
   wrapper, not the logic.
2. **The ACL surface.** Without `AppManifest::commands`, all 250 are reachable from any
   window that can reach the IPC. With it, you have 250 identifiers to place in capability
   files. Neither is free, and the second only pays off if you actually have windows at
   different trust levels — which is the real question, not the count.
3. **Discoverability.** At 250, nobody knows whether the command they need exists. The
   observable symptom is duplication: `read_config`, `get_config` and `load_settings`
   written by three people in three months. This is the failure mode that actually costs
   money, and comment banners do not fix it — they organise the registration list, not the
   namespace.
4. **Name collisions.** Global flat namespace (see `## Registration`). At 250 commands across
   24 crates, a collision is a matter of time, and it surfaces as a compile error at the
   handler far from the code that caused it.

**How to organise it.** The ordering here is by payoff, not effort:

- **Prefix by domain in the command name, not just in the module path.**
  `#[tauri::command(rename = "agent_run")]` costs nothing, eliminates the collision class, and
  makes the frontend's call sites self-documenting. Retrofitting later is a breaking change
  for every call site, so this is close to a **one-way door** — decide it before command 30.
- **One `mod` per domain, each exporting a `pub` command list**, so the `generate_handler!`
  body reads as a table of contents rather than 250 flat paths. Comment banners are the
  degenerate version of this and are strictly worse: the compiler does not check them.
- **Bodies in workspace crates, wrappers in `src-tauri`.** The `#[tauri::command]` wrapper
  does argument extraction and error mapping; the logic lives in a plain function in a crate
  that knows nothing about Tauri. This is also what makes the logic testable without a
  `MockRuntime`.
- **Promote a domain to a plugin when it has its own state, its own permissions, or its own
  lifecycle** — not merely when it has many commands. A plugin is the only supported way to
  register commands from another crate, and it brings its own ACL namespace.
  `references/plugins.md`.

**When not to split.** Do not shard a 40-command app into plugins for tidiness. Plugins add a
manifest, a permission namespace, and an initialization-order dependency
(`references/architecture.md` §the app lifecycle). Below roughly one domain's worth of
commands, the flat list with domain-prefixed names is genuinely the better engineering.

---

## v1→v2

IPC-specific changes only. The complete migration map — config keys, Cargo features,
environment variables, structural changes — is `references/architecture.md` §v1→v2 delta.

| Area | v1 | v2 |
| --- | --- | --- |
| Rust module | `tauri::api::ipc` | **`tauri::ipc`**, rewritten. New: `Channel`, `Request`, `Response`, `InvokeBody`, `InvokeResponseBody`. |
| JS import | `@tauri-apps/api/tauri` | **`@tauri-apps/api/core`** |
| Window type | `Window` | **`WebviewWindow`**; `Manager::get_window` → **`get_webview_window`** (`get_window` still exists but returns the window-only type) |
| `emit` | source-scoped | hits **all** listeners |
| Targeted emit | — | **`emit_to`** |
| `emit_filter` | filtered on window | filters on **`EventTarget`** |
| Global listen | `listen_global` | **`listen_any`** |
| Window events | `GlobalWindowEvent` | `on_window_event` is `Fn(&Window<R>, &WindowEvent)` |
| JS listen scope | window-scoped | `listen()` behaves like `listen_any` unless `Options.target` is set; `WebviewWindow.listen` is target-scoped |
| Authorization | `tauri.allowlist` | capabilities + permissions, all plugin commands denied by default → `references/security.md` |
| IPC scope type | `scope::IpcScope` | `scope::ipc::Scope` |

The two that silently change behaviour rather than failing to compile are **`emit` widening to
all listeners** (a v1 app that relied on source scoping now leaks events to every window) and
**`listen` → `listen_any`** on the Rust side (a straight port compiles and receives nothing).
`cargo tauri migrate` does not catch either, because both are semantic.

---

**Evidence.**

- <https://v2.tauri.app/develop/calling-rust/> — commands, async, error handling, WASM externs
- <https://v2.tauri.app/develop/calling-frontend/> — events, channels, `eval`
- <https://v2.tauri.app/develop/state-management/> — `manage`, `State`, mutex guidance
- <https://v2.tauri.app/concept/inter-process-communication/> — transports, isolation pattern
- <https://docs.rs/tauri/latest/tauri/ipc/index.html> · `struct.Channel` · `struct.Response` ·
  `enum.InvokeResponseBody` · `struct.State` · `trait.Emitter` · `trait.Listener` ·
  `enum.EventTarget` · `trait.Manager` (all read at **2.11.5**)
- `tauri-apps/tauri@dev` source: `crates/tauri/scripts/ipc-protocol.js` (fallback and the
  sticky `customProtocolIpcFailed` flag), `crates/tauri/src/ipc/protocol.rs` (header contract,
  invoke key, `can_use_channel_for_response`), `crates/tauri/src/ipc/channel.rs`
  (`IPC_PAYLOAD_PREFIX`, `FETCH_CHANNEL_DATA_COMMAND`, `CHANNEL_ID_HEADER_NAME`, the 8192-byte
  eval/fetch threshold), `crates/tauri-macros/src/command/wrapper.rs` (attribute surface,
  `sync_threadpool`), `packages/api/src/core.ts` and `packages/api/src/event.ts`
- `tauri-build 2.6.3` source: `src/acl.rs:87-113` (`AppManifest`, `commands`,
  `allow-$command` / `deny-$command`), `src/lib.rs:377-414` (`Attributes::app_manifest`,
  the `removeUnusedCommands` custom-capabilities-path warning)
- [tauri#2533](https://github.com/tauri-apps/tauri/issues/2533) — async command borrow
  restriction
- Real code: `C:/Users/ADMIN/Documents/GitHub/zus/src-tauri/build.rs:66` (bare
  `tauri_build::build()`); command surface and workspace layout in
  `references/case-studies.md` §11

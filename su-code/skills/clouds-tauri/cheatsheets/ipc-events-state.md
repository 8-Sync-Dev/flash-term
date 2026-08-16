# Cheatsheet — commands, events, state

> Rust APIs verified against **`tauri 2.11.5`** (`src/lib.rs`, `src/ipc/mod.rs`,
> `src/event/mod.rs`); TypeScript against **`@tauri-apps/api 2.11.1`** (`core.d.ts`,
> `event.d.ts`), 2026-07-28. Mechanism, cost and failure analysis live in
> `references/ipc-and-commands.md` — this file is lookup only.

---

## ⚠️ Read this before you write a command

**A `#[tauri::command]` that is a plain `fn` runs on the tao event loop thread — the main
thread, the UI thread. Any blocking work in it freezes every window, including windows that
had nothing to do with the call.** Default every command to `async fn`; offload CPU-bound work
with `tauri::async_runtime::spawn_blocking`. Full reasoning, the `#[tauri::command(async)]`
escape hatch and the async-borrow rule: `references/ipc-and-commands.md` §Threading.

---

## Command signatures, side by side

| # | Rust | TypeScript | Runs on |
| --- | --- | --- | --- |
| 1 | `#[tauri::command] fn ping() -> String` | `await invoke<string>('ping')` | **event loop — blocks the UI** |
| 2 | `#[tauri::command] async fn ping() -> String` | `await invoke<string>('ping')` | async runtime thread pool |
| 3 | `#[tauri::command(async)] fn ping() -> String` | `await invoke<string>('ping')` | blocking pool (sync body, offloaded) |
| 4 | `async fn get(state: State<'_, Db>) -> Result<Row, Error>` | `await invoke<Row>('get')` | pool; **`Result` is mandatory** (borrowed arg) |
| 5 | `async fn get(app: AppHandle) -> Result<(), Error>` | `await invoke('get')` | pool; `AppHandle` is owned, no `'_` |
| 6 | `async fn who(window: WebviewWindow) -> String` | `await invoke<string>('who')` | pool; `window.label()` = the caller |
| 7 | `async fn save(path: String, body: String) -> Result<(), Error>` | `await invoke('save', { path, body })` | pool |
| 8 | `fn read_file() -> tauri::ipc::Response` | `await invoke<ArrayBuffer>('read_file')` | event loop unless `async` |

```rust
// tauri 2.11.5 — the shape to copy
use tauri::{AppHandle, State, WebviewWindow};

#[tauri::command]
async fn save_note(
    id: u64,                       // from JS: { id }
    body: String,                  // from JS: { body }
    state: State<'_, Notes>,       // injected
    app: AppHandle,                // injected
    window: WebviewWindow,         // injected — window.label() is your authz input
) -> Result<u64, String> {
    Ok(id)
}
```

```ts
import { invoke } from '@tauri-apps/api/core';
const rev = await invoke<number>('save_note', { id: 7, body: 'hello' });
```

Registration — **one call, one array**; `generate_handler!` may be used only once and the last
`invoke_handler` wins silently:

```rust
tauri::Builder::default()
  .invoke_handler(tauri::generate_handler![save_note, commands::open_project])
  .run(tauri::generate_context!())
```

| Rule | Consequence if broken |
| --- | --- |
| Command names are **global**, not module-scoped | Two `get` in two modules = compile error on `__cmd__get` |
| A command in `lib.rs` must **not** be `pub` | `error[E0255]: the name __cmd__x is defined multiple times` |
| A command in another module **must** be `pub` | Not visible to `generate_handler!` |
| `commands::` path prefix in the handler list is stripped | `invoke('open_project')`, not `invoke('commands::open_project')` |
| An unregistered name fails at **runtime** | `Command <name> not found` — never a compile error |

---

## ⚠️ Argument names: camelCase, silently

Rust parameters are deserialized **by name**, and the default JS casing is **camelCase**.

| Rust parameter | JS key (default) | JS key with `rename_all = "snake_case"` |
| --- | --- | --- |
| `invoke_message` | `invokeMessage` | `invoke_message` |
| `file_path` | `filePath` | `file_path` |
| `id` | `id` | `id` |

```rust
#[tauri::command(rename_all = "snake_case")]
fn my_custom_command(invoke_message: String) {}
// -> invoke('my_custom_command', { invoke_message: 'Hello!' })
```

| Symptom | Cause |
| --- | --- |
| Argument is `undefined` / `invalid args` in the rejection | Sent `{ invoke_message }` to a default-camelCase command, or vice versa |
| `Option<T>` silently `None` | Missing key deserializes as `null`. Never panics — so it looks like a logic bug |
| Frontend broke with no compiler error | Someone renamed a Rust parameter. **Parameter names are public API** |

Full attribute surface (`#[tauri::command(...)]`):

| Attribute | Accepts | Use |
| --- | --- | --- |
| `rename_all` | **only** `"camelCase"` \| `"snake_case"` | Argument-key casing. There is no `kebab-case` |
| `rename` | string | Change the name `invoke` uses — the only namespacing tool the macro offers |
| `root` | path | `::tauri` root; plugin authoring only → `references/plugins.md` |
| `async` | flag | Force a sync body onto the blocking pool |

---

## Injected arguments — never appear in the invoke payload

Adding one of these is **not** a breaking frontend change.

| Parameter type | Gives you |
| --- | --- |
| `tauri::AppHandle` | `Clone + Send + Sync + 'static`; state, windows, emit, paths |
| `tauri::WebviewWindow` | The invoking window + its webview. **Default choice** |
| `tauri::Window` | The OS window only |
| `tauri::Webview` | Multi-webview builds (`unstable` feature) |
| `tauri::State<'_, T>` | Managed state, keyed **by type** |
| `tauri::ipc::Channel<T>` | Typed, ordered stream back to this caller |
| `tauri::ipc::Request<'_>` | Raw body + headers |
| `tauri::ipc::CommandScope<T>` / `GlobalScope<T>` | ACL scope payload → `cheatsheets/capabilities-permissions.md` |

Testable form (needed for `tauri::test::MockRuntime`):

```rust
#[tauri::command]
async fn my_command<R: tauri::Runtime>(app: tauri::AppHandle<R>) {}
```

---

## Returning data and errors

```rust
// Error: must be Serialize, because the promise rejects WITH the serialized value.
#[derive(Debug, thiserror::Error)]
enum Error { #[error("io: {0}")] Io(String) }
impl serde::Serialize for Error {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// Binary: NEVER return Vec<u8> — serde turns it into a JSON array of decimal numbers.
#[tauri::command]
async fn read_blob() -> tauri::ipc::Response {
    tauri::ipc::Response::new(std::fs::read("/path").unwrap())
}
```

```ts
try { await invoke('save_note', { id, body }); }
catch (e) { /* e IS the serialized Err value */ }

const buf = await invoke<ArrayBuffer>('read_blob');
```

`invoke` signature: `invoke<T>(cmd: string, args?: InvokeArgs, options?: InvokeOptions): Promise<T>`
where `InvokeArgs = Record<string, unknown> | number[] | ArrayBuffer | Uint8Array` — a raw
buffer as `args` is sent as the request **body**, readable via `Request<'_>`.
Cost analysis: `references/ipc-and-commands.md` §Binary, `references/performance.md` §IPC.

---

## State

```rust
// register once — type-keyed, exactly one value per type
tauri::Builder::default()
  .manage(Notes(Mutex::new(HashMap::new())))
  .setup(|app| { app.manage(Config::load()?); Ok(()) })
```

| Need | Type | Rule |
| --- | --- | --- |
| Read-only after setup | `State<'_, Config>` | No lock needed |
| Short, non-async critical section | `State<'_, Mutex<T>>` (`std::sync`) | Cheapest. **Never hold the guard across `.await`** |
| Many readers | `State<'_, RwLock<T>>` | — |
| Guard must live across `.await` | `State<'_, tokio::sync::Mutex<T>>` | Only reason to reach for it |
| Escape the invocation lifetime | `AppHandle` + `app.state::<T>()` | `State<'_, T>` cannot cross into a spawned task |

| Symptom | Cause |
| --- | --- |
| `future cannot be sent between threads safely` | `std::sync::MutexGuard` held across `.await` |
| Panic: `no state managed for field of type …` | `.manage::<T>()` never called, or a different `T` than the command asks for |
| Async command won't compile with `State<'_, T>` | A borrowed arg forces `-> Result<_, _>` |

Two `manage` calls with the same type: the second returns `false` and is ignored. There is
**no per-window state container** in v2. Details: `references/ipc-and-commands.md` §State.

---

## Events

### Rust — `tauri::Emitter` / `tauri::Listener`

| Call | Reaches |
| --- | --- |
| `app.emit("evt", payload)?` | Every listener, every window |
| `app.emit_to("login", "evt", payload)?` | Listeners registered by the target label |
| `app.emit_filter("evt", payload, \|t\| …)?` | Targets your closure accepts |
| `emit_str` / `emit_str_to` / `emit_str_filter` | Same, with a pre-serialized payload |
| `app.listen("evt", \|e\| …) -> EventId` | Target-scoped listener |
| `app.listen_any("evt", \|e\| …) -> EventId` | **Also receives `emit_to` traffic** |
| `app.once(...)` / `once_any(...)` | Auto-unregisters after the first fire |
| `app.unlisten(id)` | Remove; a handler can self-remove via `e.id()` |

`tauri::EventTarget`: `Any` · `AnyLabel { label }` · `App` · `Window { label }` ·
`Webview { label }` · `WebviewWindow { label }`; constructors `EventTarget::any()`, `app()`,
`labeled(l)`, `window(l)`, `webview(l)`, `webview_window(l)`.

```rust
use tauri::{Emitter, EventTarget};
app.emit_filter("open-file", path, |t| match t {
    EventTarget::WebviewWindow { label } => label == "main" || label == "file-viewer",
    _ => false,
})?;
```

### TypeScript — `@tauri-apps/api/event`

```ts
import { listen, once, emit, emitTo, TauriEvent } from '@tauri-apps/api/event';

const unlisten = await listen<number>('progress', (e) => e.payload);  // any target
await listen('progress', cb, { target: 'main' });                     // AnyLabel
await listen('progress', cb, { target: { kind: 'WebviewWindow', label: 'main' } });
await emit('refresh', { reason: 'user' });
await emitTo('settings', 'refresh', { reason: 'user' });
unlisten();
```

Signatures: `listen<T>(event, handler, options?): Promise<UnlistenFn>` ·
`once<T>(...): Promise<UnlistenFn>` · `emit<T>(event, payload?): Promise<void>` ·
`emitTo<T>(target, event, payload?): Promise<void>`. `Event<T>` = `{ event, id, payload }`.
`options.target` is a label string or `{ kind: 'Any' | 'AnyLabel' | 'App' | 'Window' | 'Webview' | 'WebviewWindow', label? }`.

### ⚠️ Unlisten is a Promise

```ts
// WRONG — nothing is ever removed
const unlisten = listen('sync', () => {}); unlisten();

// RIGHT
const unlisten = await listen('sync', () => {}); unlisten();

// React — an SPA route change unregisters nothing on its own
useEffect(() => {
  const p = listen<number>('progress', (e) => setProgress(e.payload));
  return () => { p.then((fn) => fn()); };
}, []);
```

| Symptom | Cause |
| --- | --- |
| Handler fires N times after navigating around the SPA | Listeners stacked; no reload happened to clear them |
| Rust `listen()` never sees an `emit_to` | Use `listen_any` |
| Progress bar jumps backwards under load | Events give no cross-listener ordering — use a `Channel` |

Built-in names via the `TauriEvent` enum: `tauri://resize` `move` `close-requested`
`destroyed` `focus` `blur` `scale-change` `theme-changed` `window-created` `suspended`
`resumed` `webview-created` `drag-enter` `drag-over` `drag-drop` `drag-leave`. Window
semantics: `references/desktop-ux.md`. Custom names may contain only alphanumerics, `-`, `/`,
`:`, `_`. Events have **no ACL support** — you cannot restrict who emits or receives.

---

## `Channel<T>` — the ordered, per-caller stream

Rust surface: `Channel::new(on_message)` · `id() -> u32` · `send(data) -> Result<()>` ·
`Clone + Serialize + CommandArg`.

```rust
// Rust -> JS
use tauri::ipc::Channel;

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase",
        tag = "event", content = "data")]
enum DownloadEvent { Started { total: usize }, Progress { chunk: usize }, Finished }

#[tauri::command]
async fn download(url: String, on_event: Channel<DownloadEvent>) -> Result<(), String> {
    on_event.send(DownloadEvent::Started { total: 1000 }).map_err(|e| e.to_string())?;
    on_event.send(DownloadEvent::Finished).map_err(|e| e.to_string())
}
```

```ts
// JS -> Rust: the Channel is created on the frontend and passed as a normal argument
import { invoke, Channel } from '@tauri-apps/api/core';

const onEvent = new Channel<DownloadEvent>();
onEvent.onmessage = (m) => console.log(m.event, m.data);
await invoke('download', { url, onEvent });   // camelCase key, like any other argument
```

| Property | Channel | Events |
| --- | --- | --- |
| Ordering | Guaranteed (indexed, buffered, replayed) | Registration order only; async listeners may reorder |
| Typing | `TSend` | `unknown` JSON |
| Scope | The one caller that created it | Broadcast |
| ACL | n/a — it rides the command's permission | None |

**Tuning rule:** messages under ~8 KB take the fast `eval` path; larger ones switch to a
fetch-based queue. Chunk small when streaming. Why, and why a Channel is correct for LLM token
streams: `references/ipc-and-commands.md` §Channels.

A `Channel` serializes to the string `"__CHANNEL__:<id>"` — it is a handle, so it is `Clone`,
can be stored in state, and can be written to long after the originating command returned.

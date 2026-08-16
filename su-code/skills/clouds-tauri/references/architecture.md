# Architecture — the runtime, the lifecycle, and the shape of an app that grows

> **Baseline: `tauri 2.11.5`**, verified against docs.rs and `tauri-apps/tauri@dev` on
> 2026-07-27. Claims read out of source are stamped with the file. Re-verify anything marked
> `dev` against your pinned version — `dev` is ahead of stable by definition.
>
> This file owns: the process/runtime model, what runs on the main thread, the window/webview
> split, the boot sequence and `RunEvent` lifecycle, `AppHandle` semantics, configuration
> architecture, project/workspace structure, and the **master v1→v2 delta**.
> It does not cover the IPC boundary (`references/ipc-and-commands.md`), capabilities and CSP
> (`references/security.md`), plugin authoring (`references/plugins.md`), or measured cost
> (`references/performance.md`).

---

## The process and runtime architecture

**Mechanism.** A Tauri app is **one Core process** — your compiled Rust binary, the only
component with full OS access — that creates and orchestrates **N WebView processes supplied
by the operating system**. The Core owns windows, tray, menus, global state, and routes *all*
IPC. It does not render a single pixel itself.

The Rust side is a layer cake, and knowing which layer a symbol lives in tells you whether a
problem is yours, the abstraction's, or the platform's:

| Crate | Role | What breaking here looks like |
| --- | --- | --- |
| `tauri` | Public API. Ties runtime + macros + config together. Reads `tauri.conf.json` at **compile time**. | Your code |
| `tauri-runtime` | Abstract glue between `tauri` and the low-level webview libs. This is the seam that makes `tauri::test::MockRuntime` possible. | Rare; usually a feature-flag mismatch |
| `tauri-runtime-wry` | The concrete wry/tao implementation: printing, monitor detection, windowing. | Platform-specific window/monitor bugs |
| `tauri-macros` / `tauri-codegen` | `#[tauri::command]`, `generate_handler!`, `generate_context!`. Embeds and compresses assets and icons; parses config into a `Config` struct at compile time. | Compile errors that mention `__cmd__*`, or stale assets |
| `tauri-utils` | Config parsing, platform triples, CSP injection, asset management. | Config keys silently ignored |
| `tauri-build` | Build-script side: applies codegen, sets cargo cfgs. | `cfg(mobile)`/`cfg(desktop)` not defined; config feature mismatch |

Upstream, maintained by the same org: **tao** (window creation + event loop; a fork of
`winit` extended with menu bar and system tray) and **wry** (the webview abstraction — it
decides *which* webview you get and how you talk to it).

The platform webviews — **WebView2** on Windows, **WKWebView** on macOS, **webkitgtk** on
Linux — are **dynamically linked at runtime, not bundled**. That single sentence is the
source of both of Tauri's headline properties: tiny binaries, and rendering that differs per
user machine. The divergence map lives in `references/cross-platform.md`.

**Why it is designed this way.** Multi-process here is a **blast-radius argument, not a
performance one**. A crashed or compromised webview cannot take down or read the Core, and
each process can be granted least privilege. The Core is Rust specifically so that the
privileged half gets memory safety without shipping a GC. This is also why the trust boundary
sits at the IPC line and not inside the webview — see `references/security.md`.

**The consequence nobody plans for: the Core is a single process, therefore a single point of
contention.** Every window, every tray interaction, every IPC message funnels through one
event loop in one process. Horizontal scaling of the renderer (more windows) does not buy you
horizontal scaling of the privileged half. An architecture that puts real work *in* the Core
scales worse than one that pushes it onto worker threads, a thread pool, or an out-of-process
sidecar. Decide early which of your subsystems are allowed to live in the Core at all.

**Trade-offs.**

- Small binaries and no shipped runtime, paid for with **three rendering engines versioned by
  the user's OS**. There is no guaranteed feature floor; your realistic baseline is the oldest
  WebKitGTK you support.
- One privileged process means one crash takes everything. Anything that can segfault, leak
  unboundedly, or hang on a syscall (an inference runtime, a video encoder, a third-party
  dylib) is a candidate for a sidecar process rather than a Rust module — you trade IPC
  overhead and packaging complexity for the ability to kill and restart it. Sidecar bundling
  is `references/build-and-distribution.md`.
- The webview being an OS component means an OS update can change your app's behaviour without
  you shipping anything.

**Failure modes, symptom-first.**

- *"The whole UI freezes while a fast operation runs."* A non-`async` command executed on the
  event loop thread. The rule and the fix are in
  `references/ipc-and-commands.md` §Threading.
- *"Works on macOS, blank or broken on Linux."* WebKitGTK lags Safari and Chromium
  substantially. Check the actual engine version on the target distro, not your dev box →
  `references/cross-platform.md`.
- *"`WebviewWindow` methods missing after a v1→v2 port."* `Window` became `WebviewWindow` and
  `Manager::get_window` became `get_webview_window`. `get_window` still exists in v2 but
  returns the *window-only* type with no webview methods on it. See §v1→v2 below.
- *"A crash in one subsystem kills the app including unrelated windows."* You are in one
  process. Isolate it or accept it.

**When to deviate.** If your app's dominant cost is a native workload rather than UI (a media
transcoder, a local model runner), the interesting architecture question is not Tauri's — it
is whether that workload belongs in the Core at all. Prefer a supervised child process with a
narrow protocol. You lose zero-copy access to shared Rust state and gain the ability to
survive its failure.

**Evidence.** <https://v2.tauri.app/concept/architecture/> ·
<https://v2.tauri.app/concept/process-model/> ·
`crates/tauri/Cargo.toml` (`tauri-apps/tauri@dev`, read 2026-07-27).

---

## What runs on the main thread

**Mechanism.** The tao event loop **must** run on the main thread. `Builder::any_thread()`
exists to bypass that — *"Builds a new Tauri application running on any thread, bypassing the
main thread requirement"* — and is platform-restricted; it is not a general escape hatch
(tauri 2.11.5).

Three execution contexts exist in a Tauri app, and confusing them is the most common source
of self-inflicted defects:

1. **The event loop / main thread.** Window creation and manipulation, menus, tray, and the
   dispatch of every `RunEvent`. **Sync commands run here.** Anything blocking here freezes
   every window, including windows uninvolved in the operation.
2. **The singleton async runtime.** `tauri::async_runtime` is a single **tokio** runtime.
   `async` commands are driven by `tauri::async_runtime::spawn`, and the same runtime drives
   `Plugin::initialize` and `Builder::setup` (source-read, `crates/tauri`, `dev` @
   2026-07-27). This is why `tauri::async_runtime::spawn` works from inside `setup`.
3. **Your own threads.** `std::thread::spawn` with a cloned `AppHandle`, or
   `tokio::task::spawn_blocking`. Anything here that needs the main thread must route through
   `AppHandle::run_on_main_thread(f)`.

**Why.** Cocoa on macOS and the Win32 message pump both require window and menu operations on
the thread that created the window. tao does not paper over that; it exposes it. The
`run_on_main_thread` hop is the honest version of the constraint rather than a lock that would
deadlock in interesting ways.

**Trade-offs.** A single event loop thread makes window lifetime and menu state trivially
race-free — there is exactly one writer. You pay for that with an absolute prohibition on
blocking it, enforced by nothing at compile time. `any_thread()` buys you the ability to
embed Tauri inside a host that already owns `main()`, at the cost of platform support and of
every assumption the rest of the ecosystem makes.

**Failure modes, symptom-first.**

- *"Window is unresponsive, spinner keeps spinning, but the Rust log shows work progressing."*
  Event loop blocked. → `references/ipc-and-commands.md` §Threading.
- *"`set_title` / `show` / `set_focus` called from a background thread does nothing or
  panics."* Wrap it in `AppHandle::run_on_main_thread`.
- *"`MainEventsCleared` handler pegs a CPU core."* It fires every loop iteration. It is not a
  timer and must never contain work.
- *"Works on Windows, crashes at startup on macOS."* `any_thread()` on a platform that will
  not tolerate it.

**When to deviate.** Reach for `any_thread()` only when Tauri is a guest inside another
application's process and you have verified the target platforms. In every other case, if you
want work off the main thread, move the *work*, not the event loop.

**Evidence.** <https://docs.rs/tauri/latest/tauri/struct.Builder.html#method.any_thread> ·
<https://docs.rs/tauri/latest/tauri/struct.AppHandle.html#method.run_on_main_thread> ·
<https://v2.tauri.app/develop/calling-rust/> (sync-command wording).

---

## Multi-window versus multi-webview

**Mechanism.** v2 split the v1 `Window` concept into three types:

- `tauri::window::Window` — an OS window (tao).
- `tauri::webview::Webview` — a webview instance (wry).
- `tauri::webview::WebviewWindow` — *"a type that wraps a `Window` together with a
  `Webview`"*, i.e. the 1:1 case. Built with `WebviewWindowBuilder`. **This is what you want
  99% of the time.**

Several webviews inside **one** window is real but gated behind the **`unstable` Cargo
feature** (`unstable = ["tauri-runtime-wry?/unstable"]` in `crates/tauri/Cargo.toml`; the
`multiwebview` example declares `required-features = ["unstable"]`, read 2026-07-27):

```rust
// requires: tauri = { version = "2", features = ["unstable"] }
use tauri::{LogicalPosition, LogicalSize, WebviewUrl};

tauri::Builder::default().setup(|app| {
  let (w, h) = (800., 600.);
  let window = tauri::window::WindowBuilder::new(app, "main")
    .inner_size(w, h)
    .build()?;

  let _left = window.add_child(
    tauri::webview::WebviewBuilder::new("main1", WebviewUrl::App(Default::default()))
      .auto_resize(),
    LogicalPosition::new(0., 0.),
    LogicalSize::new(w / 2., h / 2.),
  )?;

  let _right = window.add_child(
    tauri::webview::WebviewBuilder::new(
      "main2",
      WebviewUrl::External("https://tauri.app".parse().unwrap()),
    ).auto_resize(),
    LogicalPosition::new(w / 2., 0.),
    LogicalSize::new(w / 2., h / 2.),
  )?;
  Ok(())
});
```

**Why the split exists.** v1's single `Window` type could not express mobile (where there is
no user-resizable OS window in the desktop sense) or multiple webviews per window. Separating
the OS surface from the rendering surface is what made both possible with one API.

**The decision that actually matters.** Do not choose multi-webview for *layout* — an
`<iframe>` or plain DOM is cheaper and portable. Choose it when you need a **separate
capability and origin boundary composited inside one window frame**: a child webview has its
own label, and a label is what capability files target. An iframe shares your origin and
therefore your IPC capability; a child webview does not. That is the one thing DOM cannot
give you. Per-window capability design is `references/security.md`.

**Trade-offs.**

- Every webview is an OS process with its own memory floor. Two panes as two webviews costs
  materially more than two `<div>`s — quantified in `references/performance.md`.
- `unstable` carries no semver promise. Shipping on it means a `tauri` patch bump can break
  your build; pin exactly and read the changelog before upgrading.
- Separate windows (the `WebviewWindow` 1:1 case) get free OS-level window management —
  minimise, snap, Mission Control, taskbar grouping — that you must hand-build inside a
  multi-webview layout. Window appearance and native behaviour is
  `references/desktop-ux.md`.

**Failure modes, symptom-first.**

- *"`window.add_child` does not exist."* Missing the `unstable` feature.
- *"`get_window("main")` returns something without `eval`/`emit`."* You got the window-only
  type. Use `get_webview_window`.
- *"A second window can call privileged commands the first one can."* Capabilities target
  labels; a new label with no capability file may still be covered by a wildcard or by an
  existing capability's `windows` list. → `references/security.md`.

**When to deviate.** Multi-webview is correct for an embedded-browser product (a real browser
tab strip, an untrusted preview pane, a plugin host rendering third-party HTML). It is wrong
for a sidebar.

**Evidence.** <https://docs.rs/tauri/latest/tauri/webview/index.html> ·
`examples/multiwebview/main.rs` and `crates/tauri/Cargo.toml` (`@dev`, read 2026-07-27).

---

## The app lifecycle, end to end

**Mechanism.** `tauri::Builder<R>` → `build(context) -> Result<App<R>>` → `App::run(callback)`
or `App::run_return(callback) -> i32`. `Builder::run(context)` is exactly
`build()?.run(|_, _| {})` — nothing more. If you want an exit code or shutdown logic, you want
`build()` + `run_return()`.

The `Builder` surface *is* your app's architecture. Read it grouped by the decision each
method represents rather than alphabetically (surface verified on docs.rs, tauri 2.11.5):

| Decision | Methods | Owned by |
| --- | --- | --- |
| The IPC boundary | `invoke_handler`, `invoke_system`, `channel_interceptor`, `append_invoke_initialization_script` | `references/ipc-and-commands.md` |
| Shared state | `manage` | `references/ipc-and-commands.md` §State |
| Extension | `plugin`, `plugin_boxed` | `references/plugins.md` |
| Lifecycle observation | `setup`, `on_page_load`, `on_window_event`, `on_webview_event` | this file |
| Native UI | `menu`, `on_menu_event`, `on_tray_icon_event`, `enable_macos_default_menu` | `references/desktop-ux.md` |
| Serving bytes without IPC | `register_uri_scheme_protocol`, `register_asynchronous_uri_scheme_protocol` | this file + `references/ipc-and-commands.md` §Binary |
| Host/runtime | `any_thread`, `device_event_filter`, `build`, `run` | this file |

**Boot order — read out of source, not inferred.** Inside `Builder::build()`
(`crates/tauri/src/app.rs`, `@dev`, read 2026-07-27):

1. `App` is constructed.
2. `app.register_core_plugins()` — **core plugins first, always.**
3. Desktop menu built from the `menu` closure (macOS additionally runs `init_app_menu`).
4. `app.manage(Env::default())`.
5. `app.manage(Scopes { asset_protocol })`.
6. `app.manage(ChannelDataIpcQueue::default())` plus
   `app.handle.plugin(ipc::channel::plugin())`.
7. Tray icon from `app.trayIcon` config (desktop + `tray-icon` feature).
8. `app.manager.initialize_plugins(handle)?` — **your `.plugin(...)` registrations initialize
   here, in registration order.**

Then inside `App::run` / `run_return`, a private `setup(app)` function:

1. `app.ran_setup = true`.
2. **Config-declared windows are created** — for each entry in `app.config().app.windows` with
   `create != false`: `WebviewWindowBuilder::from_config(...)?.build()?`.
3. `app.manager.assets.setup(app)`.
4. **Your `setup` closure runs.**

Then `RunEvent::Ready` is dispatched and the event loop takes over.

**Why the order is worth memorising.** It defines exactly what you may assume where:

- In a `Plugin::initialize`, plugins registered *after* yours do not exist yet, and neither do
  config windows. **Order your `.plugin()` calls by dependency** — there is no dependency
  resolution.
- In `setup`, plugins are initialised and config windows already exist, so
  `app.get_webview_window("main")` works. This is the earliest point at which the whole app
  surface is real.
- State registered inside `setup` is invisible to any `Plugin::initialize`, because those
  already ran. If a plugin needs your state, register the state with `Builder::manage` (step 4
  ordering, pre-boot) rather than in `setup`.
- Plugins can be added after boot with `AppHandle::plugin(p)` and removed with
  `AppHandle::remove_plugin(name) -> bool`. That is the supported way to make a plugin
  conditional on a runtime decision.

**`RunEvent` — exact variants** (`crates/tauri/src/app.rs`, `#[non_exhaustive]`, tauri 2.11.5):

```rust
pub enum RunEvent {
  Exit,
  ExitRequested { code: Option<i32>, api: ExitRequestApi },   // #[non_exhaustive]
  WindowEvent  { label: String, event: WindowEvent },          // #[non_exhaustive]
  WebviewEvent { label: String, event: WebviewEvent },         // #[non_exhaustive]
  Ready,
  Resumed,
  MainEventsCleared,
  Opened { urls: Vec<url::Url> },        // macOS / iOS / Android only
  MenuEvent(crate::menu::MenuEvent),     // desktop
  TrayIconEvent(crate::tray::TrayIconEvent), // desktop + tray-icon feature
  Reopen { has_visible_windows: bool },  // macOS only
}
```

Two details with teeth:

- `ExitRequested { code }`: `None` means **user-initiated** exit; `Some(_)` means
  **programmatic** (`AppHandle::exit(code)`, `restart()`, `request_restart()`). Gate your veto
  on `code.is_none()` or you will veto your own updater.
- `pub const tauri::RESTART_EXIT_CODE: i32 = i32::MAX;` and
  `ExitRequestApi::prevent_exit()` is a **no-op when `code == Some(RESTART_EXIT_CODE)`** —
  source: `if self.code != Some(RESTART_EXIT_CODE) { self.tx.send(Prevent) }`. **You cannot
  veto a restart.** This is deliberate: an update that installed itself must be able to
  relaunch regardless of your close handler.

`WindowEvent` (`#[non_exhaustive]`): `Resized`, `Moved`, `CloseRequested { api }`,
`Destroyed`, `Focused(bool)`, `ScaleFactorChanged { .. }`, `DragDrop(..)`,
`ThemeChanged(..)` — the last is **only delivered if `WindowBuilder::theme` is `None`**, since
a pinned theme means the OS theme is not your input. `WebviewEvent` has exactly one variant
today: `DragDrop(DragDropEvent)`. Drag-drop semantics and the native-handler conflict are
`references/desktop-ux.md`.

**Graceful shutdown with a real exit code:**

```rust
use tauri::{Manager, RunEvent, WindowEvent};

fn main() {
  let app = tauri::Builder::default()
    .on_window_event(|window, event| {
      if let WindowEvent::CloseRequested { api, .. } = event {
        // Only veto when we mean to hide rather than quit; see the loop gotcha below.
        api.prevent_close();
        let _ = window.hide();
      }
    })
    .build(tauri::generate_context!())
    .expect("error while building tauri application");

  let code = app.run_return(|app_handle, event| match event {
    RunEvent::Ready => { /* windows exist, plugins live, first paint imminent */ }
    RunEvent::ExitRequested { code, api, .. } => {
      if code.is_none() {
        api.prevent_exit();          // ignored when code == Some(RESTART_EXIT_CODE)
      }
    }
    RunEvent::Exit => {
      app_handle.cleanup_before_exit(); // last chance, on the main thread
    }
    _ => {}
  });
  std::process::exit(code);
}
```

**Why `run_return` over `run`.** `run` never returns, so the only way to propagate an exit
code is `std::process::exit` from inside a handler — which skips destructors and can truncate
a flush that was still in flight. `run_return` gives you a normal control-flow exit point.

**Trade-offs.** `prevent_exit`/`prevent_close` transfer ownership of quitting from the OS to
you. That is what enables minimise-to-tray and "save before closing" — and it means a bug in
that handler produces an **unquittable app**. Users respond by force-killing, which is exactly
the path where unflushed data is lost. If you veto, you must own a reachable, tested quit
path.

**Failure modes, symptom-first.**

- *"Cleanup in `RunEvent::Exit` never runs."* Something called `std::process::exit()`, or the
  process was killed. Note that `AppHandle::restart()` documents that **when called on the
  main thread the events may be skipped** and the process is restarted directly — do not put
  your only flush there.
- *"`prevent_close` loops forever when quitting from the tray."* `CloseRequested` fires for
  programmatic closes too. Gate the veto on an `is_quitting` flag in managed state.
- *"`RunEvent::Reopen` / `Opened` do not compile."* They are `cfg`-gated (macOS; macOS/iOS/
  Android). `RunEvent` is `#[non_exhaustive]` — always keep a `_ => {}` arm or your app breaks
  on a minor upgrade.
- *"`MainEventsCleared` burns CPU."* See §main thread.
- *"App exits with code 0 even though a subsystem failed."* You used `run`, not `run_return`.

**When to deviate.** `App::run_iteration(callback)` runs a single event-loop tick and returns
immediately — the right tool only when Tauri is embedded in a host loop you do not control.
Driving your own loop with it in a normal app reintroduces every scheduling bug tao already
solved.

**Evidence.** <https://docs.rs/tauri/latest/tauri/struct.Builder.html> ·
<https://docs.rs/tauri/latest/tauri/struct.App.html> ·
<https://docs.rs/tauri/latest/tauri/enum.RunEvent.html> ·
<https://docs.rs/tauri/latest/tauri/enum.WindowEvent.html> ·
`crates/tauri/src/app.rs` (`@dev`, read 2026-07-27).

---

## The `setup` hook — what belongs in it, and what must never

**Mechanism.**

```rust
pub fn setup<F>(mut self, setup: F) -> Self
where F: FnOnce(&mut App<R>) -> Result<(), Box<dyn std::error::Error>> + Send + 'static;
```

Four properties of that signature drive everything below:

- **`FnOnce`** — it runs exactly once, so it can consume owned values you moved in.
- **`&mut App<R>`** — you get the full app, not a handle: `app.handle()`, `app.manage(..)`,
  `app.get_webview_window(..)`, `app.path()`, `app.set_menu(..)` all work.
- **`Result<(), Box<dyn Error>>`** — and **a returned `Err` becomes `crate::Error::Setup` and
  aborts application startup.** There is no partial-boot state; the app dies.
- **`Send + 'static`** — the closure is stored, so anything captured must be `Send`.

It runs after plugins are initialised and after config windows are created, and it is
**synchronous with respect to boot**: every millisecond spent inside `setup` is a millisecond
before your first window paints. The singleton `tauri::async_runtime` is what drives it, so
`tauri::async_runtime::spawn` is available for work you want to *start* here and not wait for.

**Why it exists at all.** It is the only place where the app is fully constructed but the
event loop has not started. That combination is what you need for "resolve paths → open the
database → restore saved geometry → *then* show the window" — a sequence that must complete
before the user sees anything, and that cannot run in `Builder` chain order because it needs a
live `App`.

**What belongs in `setup`:**

- Anything that needs resolved paths (`app.path().app_data_dir()`) — those are not known at
  `Builder`-chain construction time.
- State whose construction can fail and whose failure is fatal (the primary database).
- Restoring window geometry and *then* showing a window declared `"visible": false`, which is
  the standard cure for the white-flash-then-jump.
- Platform-conditional wiring: `#[cfg(target_os = "macos")] app.set_menu(..)`.
- Conditionally registering plugins via `app.handle().plugin(..)` — e.g. a logger only under
  `debug_assertions`.
- **Kicking off** background work with `spawn` — starting a watcher, warming a cache.

**What must not be in `setup`:**

- **Anything whose failure is survivable, `?`-propagated.** `?` in `setup` is a decision that
  the app cannot exist without this subsystem. Optional subsystems must log and continue.
  `references/case-studies.md` §10 is a real `setup()` that gets this asymmetry right: the
  storage DB uses `expect` because the app genuinely cannot run without it, while the updater
  and secret-store initialisers `log::warn!` and carry on.
- **Long blocking work.** A network call, a migration, an index rebuild in `setup` is
  time-to-first-paint. Spawn it and let the UI render a loading state.
- **Environment variables the webview reads at initialisation.** By the time `setup` runs, the
  config windows in step 2 already created their webviews. Anything like
  `WEBKIT_DISABLE_DMABUF_RENDERER` must be set at the top of `main()` — see
  `references/case-studies.md` §8 for the production line and
  `references/cross-platform.md` for why.
- **`unwrap()` on anything environmental.** A user with a read-only or redirected app-data
  directory turns `unwrap()` into "the app does not start, no message, no log".

**Trade-offs.**

- Declaring windows in config makes them appear as early as possible — good perceived boot —
  but at whatever geometry the config says, before your frontend or saved layout loads.
  `"create": false` or `"visible": false` plus an explicit build/show in `setup` trades a
  slightly later first window for no flash and correct geometry. Pick per window; a splash
  window wants the former, a main editor window the latter. Startup measurement is
  `references/performance.md`.
- Everything you move into `setup` for correctness is boot latency you now own. The mitigation
  is `spawn`, and the cost of `spawn` is that your frontend must handle "not ready yet"
  states — which is real UI work, not free.

**Failure modes, symptom-first.**

- *"The app exits immediately with a cryptic error and no window."* Something in `setup`
  returned `Err`. Wrap optional subsystems; log the error before propagating anything.
- *"Works on my machine, does not start for one user."* An `unwrap()`/`expect()` in `setup` on
  a path, permission, or migration. Every fallible line in `setup` needs a decided answer to
  "is this fatal?".
- *"Window flashes white at default size, then jumps."* Window created by config before your
  frontend and geometry loaded.
- *"A plugin cannot find my managed state."* You managed it in `setup`; the plugin initialised
  earlier. Move it to `Builder::manage`.
- *"Boot takes three seconds and the profiler shows nothing after `Ready`."* The work is in
  `setup`, before `Ready` is dispatched.

**When to deviate.** If your app has no fallible initialisation at all — no database, no
resolved paths, no restored geometry — `setup` is dead weight and `Builder::manage` plus
config windows is the simpler app. Do not add a `setup` closure to hold one line.

**Evidence.** `crates/tauri/src/app.rs` (signature and `Error::Setup`, `@dev`, read
2026-07-27) · <https://docs.rs/tauri/latest/tauri/struct.Builder.html#method.setup> ·
`references/case-studies.md` §10 (a real 60-line `setup` with the fatal/optional split made
explicitly).

---

## `AppHandle` semantics

**Mechanism.** `AppHandle<R>: Clone + Send + Sync + Debug`, and it implements `Manager`,
`Listener`, `Emitter`, and `CommandArg`. That combination means one value gives you: state
access, window lookup, event emit and listen, path resolution, config, plugin add/remove, and
`run_on_main_thread`. Obtain one with `App::handle() -> &AppHandle<R>` — note the reference,
so `.clone()` it to move into a thread — or inject `app: tauri::AppHandle` as a command
parameter.

The official state-management guide is explicit: *"`AppHandle`s are deliberately cheap to
clone for use-cases like this."* Internally it is refcounted handles to the manager and the
runtime; cloning is not a deep copy of app state.

The canonical escape hatch when `State<'_, T>`'s lifetime blocks you:

```rust
let handle = app.handle().clone();
std::thread::spawn(move || {
  let state = handle.state::<Mutex<AppState>>();
  let mut guard = state.lock().unwrap();
  guard.counter += 1;
});
```

**Why it is a handle and not a global.** Tauri could have exposed a process-wide static. A
handle instead makes the dependency explicit in every signature that needs it, and makes two
`App`s in one process (integration tests, `MockRuntime`) possible. Testing strategy is
`references/debugging-and-testing.md`.

**The architectural rule that follows: `AppHandle` stops at the boundary layer.** It is an
ambient-authority object — a function taking `AppHandle` can do *anything*, so its signature
tells a reader nothing and a test must construct a whole app to call it. Pass what the
function actually needs: a `&Path`, a `&Db`, an `mpsc::Sender<Event>`. Keep `AppHandle` in
`commands/`, in `setup`, and in long-lived task supervisors that genuinely need to emit and to
read state; keep it out of your domain crates entirely. This is the same argument as
§Project structure below, and it is the difference between a core you can unit test in
milliseconds and one you cannot test at all.

**Trade-offs.** Cheap cloning plus `Send + Sync` makes it tempting to stash an `AppHandle` in
every struct. Doing so couples your whole codebase to the Tauri runtime, inflates compile
times (everything now depends on `tauri`), and destroys unit-testability. The cost of the
discipline is more explicit parameters and a few more `From` impls.

**Failure modes, symptom-first.**

- *"Cannot move `&AppHandle` into a thread / lifetime error."* `handle()` returns a reference.
  `.clone()` first.
- *"Background task emits events into the void after the window closed."* `emit` to a
  destroyed target is not an error you will notice. Tie task lifetime to something —
  a cancellation token, or check `get_webview_window(..).is_some()`.
- *"Panic on `state::<T>()` in a spawned thread."* The type was never managed, or was managed
  in `setup` after the thread started. Prefer `try_state::<T>()` off the main path. Details in
  `references/ipc-and-commands.md` §State.
- *"Everything recompiles when I touch one domain module."* `AppHandle` leaked into that
  module and dragged `tauri` in with it.

**When to deviate.** Long-lived subsystems that are inherently app-scoped — a tray controller,
a deep-link router, an update manager — legitimately hold an `AppHandle`. Put them in one
module that owns that dependency openly rather than sprinkling it.

**Evidence.** <https://docs.rs/tauri/latest/tauri/struct.AppHandle.html> ·
<https://v2.tauri.app/develop/state-management/> (the "cheap to clone" wording).

---

## Configuration architecture

**Mechanism.** `tauri.conf.json` is parsed **at compile time** by `tauri-codegen` (via
`generate_context!`) into a `Config` struct embedded in the binary, and separately by
`tauri-cli` for build and bundle decisions. It is not a runtime-editable file. At runtime you
get read-only access: `App::config()` / `AppHandle::config() -> &Config`, `Manager::config()`,
and `package_info() -> &PackageInfo`. **There is no runtime mutation API.**

**Top-level keys** (exhaustive for the v2 schema, tauri 2.11.5). Read the third column first —
that is the part you cannot change your mind about later:

| Key | What it decides | Cost of getting it wrong |
| --- | --- | --- |
| `identifier` | **Required.** Reverse-DNS, charset `A–Z a–z 0–9 - .`. Drives the bundle ID **and the webview data directory path**. | Changing it later **orphans every user's local storage, IndexedDB and cookies**. It is a one-way door on your first release. |
| `productName` | Display name; pattern `^[^/\:*?"<>|]+$`. | Cosmetic, but see `mainBinaryName`. |
| `version` | Semver, or a path to a `package.json` with a `version`; falls back to `Cargo.toml`. | The updater compares versions. A non-monotonic version strands clients → `references/build-and-distribution.md`. |
| `mainBinaryName` | Renames the cargo output binary. **No extension** — Tauri appends `.exe`. | v2 no longer auto-renames the binary to `productName` (v1 did). Omit it and your app ships as `my-crate-name`. |
| `app` | Runtime surface: `windows`, `security`, `trayIcon`, `withGlobalTauri`, `macOSPrivateApi`, `enableGTKAppId`. | `security` is the whole CSP/capability/pattern posture → `references/security.md`. |
| `build` | `devUrl`, `frontendDist`, the three `before*Command` hooks, `features`, `runner`, `additionalWatchFolders`, `removeUnusedCommands`. | Dev/build only, and therefore the cheapest column to change. |
| `bundle` | Packaging, targets, signing, resources, per-OS bundler config. | Signing identity and target list are release-engineering one-way doors → `references/build-and-distribution.md`. |
| `plugins` | Per-plugin config, keyed by `Plugin::name()`. | Ships compiled-in, including updater endpoints and pubkey → see below. |

Defaults worth knowing because they surprise people (tauri 2.11.5):
`app` defaults to `{ enableGTKAppId: false, macOSPrivateApi: false, security: { assetProtocol: { enable: false, scope: [] }, capabilities: [], dangerousDisableAssetCspModification: false, freezePrototype: false, pattern: { use: "brownfield" } }, windows: [], withGlobalTauri: false }`;
`build` defaults to `{ additionalWatchFolders: [], removeUnusedCommands: false, windows: { staticVCRuntime: true } }`.

`app.windows[]`: the label defaults to `"main"`, labels must be unique, and **`"create": false`**
declares a window in config without instantiating it — so you can build it yourself later from
the same declaration and keep one source of truth for its geometry:

```rust
tauri::Builder::default().setup(|app| {
  tauri::WebviewWindowBuilder::from_config(app.handle(), &app.config().app.windows[0])?
    .build()?;
  Ok(())
});
```

### Compiled-in versus runtime — the table to check before every release

| Compiled in (wrong = wrong on every installed machine) | Runtime (fixable without a release) |
| --- | --- |
| Every `tauri.conf.json` value, including `plugins.updater.endpoints` and `pubkey` | Managed state (`references/ipc-and-commands.md` §State) |
| Capabilities and permissions, CSP | A plugin store / your own settings file |
| Frontend assets and icons (embedded and compressed by `tauri-codegen`) | Window geometry you persist and restore |
| The registered command list | Environment variables and CLI arguments |
| `identifier` → the webview data directory | Anything you fetch from your own server |

**The rule this table exists to enforce:** anything a support engineer might need to change on
a user's machine must not be in the left column. The starkest instance is updater endpoints —
`references/case-studies.md` §6 shows a shipping app whose single compiled-in endpoint means a
dead endpoint permanently strands its install base.

### Platform overlays and RFC 7396 — the array trap

`tauri.linux.conf.json`, `tauri.windows.conf.json`, `tauri.macos.conf.json`,
`tauri.android.conf.json`, `tauri.ios.conf.json` (or `Tauri.<platform>.toml`) merge into the
base using **JSON Merge Patch, RFC 7396**.

RFC 7396 has exactly two rules you must internalise: **objects merge key by key**, and
**arrays are replaced wholesale — never concatenated. `null` deletes a key.**

```jsonc
// tauri.conf.json
{ "bundle": { "resources": ["./resources", "./licenses"] } }

// tauri.linux.conf.json
{ "bundle": { "resources": ["./linux-assets"] } }

// resolved on Linux:
{ "bundle": { "resources": ["./linux-assets"] } }   // ./resources and ./licenses are GONE
```

Every array-valued key is exposed to this: `bundle.resources`, `bundle.targets`,
`app.security.capabilities`, `app.security.assetProtocol.scope`, `app.windows`. Overriding one
window property on macOS means restating the **entire** `app.windows` array, and the day
someone adds a window to the base config and forgets the overlay, macOS silently loses it.

**Why JSON Merge Patch and not something smarter.** It is a published standard with one
obvious implementation and no ambiguity. An array-merging scheme would have to guess identity
(is this the same window? the same resource?) and would be wrong in a way nobody could
predict. Predictable-and-blunt beats clever-and-surprising for a file that ships compiled in.

**Mitigation.** Keep overlays as small as possible, and prefer restructuring so the divergent
value is not inside an array. For `app.windows`, an alternative that avoids the trap entirely
is one config-declared window with `"create": false` plus `WebviewWindowBuilder` code with
`#[cfg(target_os = ...)]` branches — the divergence becomes Rust that the compiler checks
rather than JSON that nobody diffs. `references/case-studies.md` §4 shows a real four-file
platform split for custom titlebars and what it costs in reviewability.

### Flavours: `--config`, and what `TAURI_CONFIG` actually is

`--config` is accepted by `dev`, `build`, `bundle`, and the `android`/`ios` variants. It takes
a raw JSON string or a path and is merged with the same RFC 7396 rules. This is the supported
way to ship beta/nightly flavours without a second full config:

```jsonc
// src-tauri/tauri.beta.conf.json
{ "productName": "My App Beta", "identifier": "com.myorg.myappbeta" }
```

```
npm run tauri build -- --config src-tauri/tauri.beta.conf.json
```

`TAURI_CONFIG` is **the CLI's own transport for exactly that merge patch**, not a separate
feature. `tauri-cli` serialises the resolved patch and exports it
(`crates/tauri-cli/src/helpers/config.rs`), and the build side consumes it
(`crates/tauri-build/src/lib.rs`, `@dev`, read 2026-07-27):

```rust
println!("cargo:rerun-if-env-changed=TAURI_CONFIG");
// ...
if let Ok(env) = env::var("TAURI_CONFIG") {
  let merge_config: serde_json::Value = serde_json::from_str(&env)?;
  json_patch::merge(&mut config, &merge_config);
}
```

So it is a genuine override channel, and the `rerun-if-env-changed` line means changing it
correctly invalidates the build. `[COMMUNITY]` Prefer `--config` anyway: `TAURI_CONFIG` is
trivial to leave stale in a shell or a CI step and it does not appear in any committed file,
so a wrong build is invisible in review.

Other build-time variables the CLI sets for `beforeDevCommand`/`beforeBuildCommand`/
`beforeBundleCommand`: `TAURI_ENV_PLATFORM`, `TAURI_ENV_ARCH`, `TAURI_ENV_FAMILY`,
`TAURI_ENV_PLATFORM_VERSION`, `TAURI_ENV_PLATFORM_TYPE`, `TAURI_ENV_DEBUG`. Also
`TAURI_BUNDLER_WIX_FIPS_COMPLIANT` mirrors `bundle.windows.wix.fipsCompliant`.

### File formats

JSON is the default. JSON5 and TOML are **opt-in Cargo features on both `tauri` and
`tauri-build`** — enabling it on one only is a silent no-op:

```toml
[build-dependencies]
tauri-build = { version = "2", features = ["config-json5"] }
[dependencies]
tauri       = { version = "2", features = ["config-json5"] }
```

JSON5 files must be named `tauri.conf.json` or `tauri.conf.json5`; TOML must be `Tauri.toml`.
TOML may use kebab-case (`dev-url`, `before-dev-command`) because the Rust structs carry
`#[serde(alias = ...)]`. **Field names are case-sensitive in all three formats.**

**Trade-offs of compile-time config, stated plainly.** You get: no config parsing at startup,
no runtime config drift between machines, and a config a user cannot edit to grant themselves
capabilities. You pay: every mistake ships, `tauri dev` needs a rebuild to pick up changes,
and there is no way to A/B a setting in the field. The correct response is not to fight the
design but to move genuinely variable things — feature flags, server URLs you might rotate,
log level — out of the config and into managed state or a store you fetch/read at runtime.

**Failure modes, symptom-first.**

- *"A platform overlay dropped entries from a base array."* RFC 7396. Restate the full array.
- *"`productName` changed but the binary name did not."* v2 does not auto-rename. Set
  `mainBinaryName`.
- *"Users lost all their data after we fixed an `identifier` typo."* The webview data
  directory is derived from `identifier`.
- *"Editing `tauri.conf.json` has no effect."* Compile-time parse — rebuild. `tauri dev` only
  watches known paths; `build.additionalWatchFolders` extends that set.
- *"TOML/JSON5 config silently ignored."* Feature enabled on `tauri` but not `tauri-build`, or
  vice versa.
- *"`window.__TAURI__` is undefined."* `app.withGlobalTauri` defaults to `false`. Either set
  it or import from `@tauri-apps/api/*` — the latter is preferred, because a global object is
  reachable by any injected script.

**When to deviate.** A single-platform internal tool does not need platform overlay files, and
adding them "for later" just creates four places to forget. Add the overlay the day the
divergence is real.

**Evidence.** <https://v2.tauri.app/reference/config/> ·
<https://v2.tauri.app/develop/configuration-files/> · RFC 7396:
<https://datatracker.ietf.org/doc/html/rfc7396> · `crates/tauri-cli/src/helpers/config.rs`,
`crates/tauri-build/src/lib.rs`, `crates/tauri-utils/src/config.rs` (`@dev`, read
2026-07-27).

---

## Project and workspace structure for an app that will grow

**Mechanism.** v2 requires a **library target** for mobile, and that requirement happens to
be the right structure for desktop-only apps too:

```toml
# src-tauri/Cargo.toml
[lib]
name = "app_lib"
crate-type = ["staticlib", "cdylib", "rlib"]
```

```rust
// src-tauri/src/main.rs — deliberately almost empty
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
  // Anything that must happen BEFORE any webview initialises goes here, not in setup().
  app_lib::run();
}
```

```rust
// src-tauri/src/lib.rs — the Builder chain and nothing else
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .manage(state::Settings::default())
    .setup(|app| { /* ... */ Ok(()) })
    .invoke_handler(tauri::generate_handler![commands::fs::read_text, commands::db::query])
    .build(tauri::generate_context!())
    .expect("failed to build app")
    .run(|_app, _event| {});
}
```

The `windows_subsystem` attribute and pre-webview environment setup in `main()` are load
bearing, not decoration — `references/case-studies.md` §8 has the production two-liner and
the exact symptoms each line prevents.

**The layout that survives growth:**

```
src-tauri/
├── Cargo.toml              # [lib] crate-type, workspace member
├── build.rs                # tauri_build::build()
├── tauri.conf.json         # + tauri.<platform>.conf.json when divergence is real
├── capabilities/*.json     # security posture — references/security.md
└── src/
    ├── main.rs             # windows_subsystem, pre-webview env, app_lib::run()
    ├── lib.rs              # the Builder chain; no business logic
    ├── error.rs            # the one Serialize-able boundary error type
    ├── state.rs            # managed newtypes, nothing else
    └── commands/
        ├── mod.rs
        ├── fs.rs           # thin: deserialize, validate, call core, map error
        └── db.rs
crates/                     # domain crates — NO `tauri` dependency
├── app-index/
└── app-db/
```

**The one rule that makes this work: `commands/` is an adapter layer, not a place where logic
lives.** A command function should deserialize its arguments, validate them (this is where the
security boundary is — `references/security.md`), call into a plain-Rust function, and map the
error into your boundary error type. If a command body is more than ~20 lines, the logic
inside it is untestable and unreusable, because reaching it requires a Tauri runtime.

**Why. Three concrete payoffs, in order of how soon you feel them:**

1. **Testability.** A domain crate with no `tauri` dependency is testable with plain
   `cargo test` in milliseconds, with no window, no event loop, no `MockRuntime`. The
   Tauri-level tests you still need are then few and targeted →
   `references/debugging-and-testing.md`.
2. **Compile time.** Rust's unit of recompilation is the crate. A 20k-line `src-tauri` crate
   rebuilds *entirely* every time you touch one file, and it depends on `tauri`, which is a
   large dependency graph. Splitting the leaves out means editing your indexer recompiles the
   indexer, not the app.
3. **Optionality.** A core with no `tauri` dependency can be driven by a CLI, a test harness,
   a benchmark, or a future server. A core that takes `AppHandle` cannot.

**When to split a crate.** Split when at least one of these is true:

- A subsystem has a **clean dependency direction** (it does not need to call back into the
  app) and enough substance to be worth a boundary — as a rough judgement call, low thousands
  of lines. `[COMMUNITY]`
- Incremental rebuild of `src-tauri` has become the bottleneck in your edit-run loop.
- The subsystem pulls heavy or platform-specific dependencies you want feature-gated away
  from the main crate.

**When not to split.** A crate per module is pure overhead: more `Cargo.toml` files to keep in
sync, a `pub` surface designed before you know the shape, and premature interface freezing. If
you cannot name the dependency direction the boundary enforces, there is no boundary — just
ceremony. Both real apps in `references/case-studies.md` sit at opposite ends of this
spectrum (24 workspace crates versus `src/core/*` modules plus in-tree plugins) and both ship;
the number is not the point, the direction of dependencies is.

**Crates versus plugins — a different axis.** A workspace crate gives you compile isolation
and testability. A **plugin** additionally gives you its own ACL, its own generated permission
files, and its own command namespace, which is what you want once a command group has a
security story of its own. The signals that a module has outgrown being a module are in
`references/ipc-and-commands.md` §Scale; the mechanics of authoring one are
`references/plugins.md`.

**Trade-offs.** The thin-adapter discipline costs you indirection: two functions where one
would do, plus `From` impls to map domain errors into your boundary error. In a genuinely
small app (a handful of commands, no domain logic worth the name) that indirection is pure
tax, and a flat `src/` with logic in the command bodies is the honest answer. The failure mode
to watch for is the app that quietly grows past that point and never restructures.

**Failure modes, symptom-first.**

- *"`cargo tauri android build` fails: no library target."* Missing `[lib] crate-type`.
- *"`cargo test` cannot see my functions."* They are in `main.rs`. Only `lib.rs` and its
  modules are reachable from integration tests.
- *"Edit-to-run latency keeps growing."* One monolithic crate. Split the leaves.
- *"Every change recompiles everything even after splitting."* A leaf crate depends on
  `tauri` (usually because `AppHandle` leaked into it) so it is downstream of the big graph.
- *"We cannot unit test the interesting logic."* It is inside command bodies.
- *"A release build opens a console window behind the app on Windows."* Missing
  `windows_subsystem` → `references/case-studies.md` §8.

**When to deviate.** A single-file `lib.rs` is correct for an app with under ~500 lines of
Rust. Bootstrap flat, and treat "I want to test this without a window" as the trigger to
extract — not a line count decided up front.

**Evidence.** <https://v2.tauri.app/start/migrate/from-tauri-1/> (the mobile lib-target
requirement) · `references/case-studies.md` §10 and §11 (a real `Builder` chain and a real
250-command surface) · <https://v2.tauri.app/develop/>.

---

## v1→v2 delta (master map)

You will meet v1-era blog posts, Stack Overflow answers, and LLM training data constantly.
This section exists so you can recognise v1 in three seconds and not copy it.

**The three tells.** Any one of these means you are looking at v1 and must translate before
using anything else on the page:

1. `tauri.allowlist` anywhere in the config.
2. `import { invoke } from '@tauri-apps/api/tauri'` (v2 is `@tauri-apps/api/core`).
3. `tauri::Window` as a command parameter, or `listen_global` in Rust.

**Why v2 restructured rather than patched.** v1's allowlist was one monolithic switchboard
compiled into `tauri` itself: the core carried dialog, http, shell, clipboard, global
shortcut, and updater code whether you used them or not, and the security model was a flat
list of booleans with no notion of *which window* or *which path*. v2 moved that functionality
out to plugins (so the core shrank and each plugin owns its own ACL, generated per command)
and replaced the boolean list with capabilities scoped to window labels. The config
flattening — `package` and `tauri` disappearing — follows from the same move: `tauri.allowlist`
had no successor, and `tauri.bundle`/`tauri.updater` belonged to the bundler and to a plugin,
not to the runtime.

### Config keys — every one of these moved

| v1 | v2 |
| --- | --- |
| `package.productName`, `package.version` | **top level** `productName`, `version` |
| `package` | **removed** |
| `tauri` | `app` |
| `tauri.allowlist` | **removed** → capabilities/permissions (`references/security.md`) |
| `tauri.allowlist.protocol.assetScope` | `app.security.assetProtocol.scope` |
| `tauri.cli` | `plugins.cli` |
| `tauri.updater` | `plugins.updater` (+ `bundle.createUpdaterArtifacts`, now required) |
| `tauri.updater.active` / `.dialog` | **removed** |
| `tauri.systemTray` | `app.trayIcon` |
| `tauri.pattern` | `app.security.pattern` |
| `tauri.bundle` | **top level** `bundle` |
| `tauri.bundle.identifier` | **top level** `identifier` |
| `tauri.bundle.dmg` / `deb` / `appimage` | `bundle.macOS.dmg` / `bundle.linux.deb` / `bundle.linux.appimage` |
| `tauri.windows[].fileDropEnabled` | `app.windows[].dragDropEnabled` |
| `build.withGlobalTauri` | `app.withGlobalTauri` |
| `build.distDir` | `build.frontendDist` |
| `build.devPath` | `build.devUrl` |
| `…macOS.license`, `…wix.license`, `…nsis.license` | `bundle.licenseFile` |
| `…windows.webviewFixedRuntimePath` | `bundle.windows.webviewInstallMode` |
| — | **new:** `mainBinaryName` — the binary is no longer auto-renamed to `productName` |

### Rust structural changes

- **The whole `tauri::api` module is gone.** `api::dialog` / `http` / `shell` /
  `process::Command` / `clipboard` / `global_shortcut` / `updater` all became plugins
  (`references/plugins.md`). `api::file` → use `std::fs`. `api::version` → the `semver` crate.
  `api::path` and `tauri::PathResolved` → **`tauri::Manager::path`**.
  `api::process::current_binary`/`restart` → `tauri::process`.
- `Window` → **`WebviewWindow`**; `Manager::get_window` → **`get_webview_window`**. Multi-
  webview is behind `unstable` (see §Multi-window above).
- Removed outright: `App::get_cli_matches`, `App`/`AppHandle::clipboard_manager`,
  `App`/`AppHandle::global_shortcut_manager`, `Manager::fs_scope`.
- Menu and tray were **fully rewritten**: `Menu`, `CustomMenuItem`, `Submenu`, `MenuItem`,
  `WindowMenuEvent`, `Builder::on_menu_event`, and every `SystemTray*` type are gone. New API
  in `references/desktop-ux.md`.
- Scopes renamed: `scope::IpcScope` → `scope::ipc::Scope`; `scope::FsScope` / `GlobPattern` /
  `FsScopeEvent` → `scope::fs::Scope` / `Pattern` / `Event`;
  `RemoteDomainAccessScope::enable_tauri_api` removed (use per-plugin `add_plugin`).
- `Plugin::PluginApi` now receives that plugin's config slice as its second argument;
  `Plugin::setup_with_config` removed.
- `Env.args` removed in favour of `Env.args_os`.
- **IPC, commands, events and state have their own delta** —
  `references/ipc-and-commands.md` §v1→v2.

### Cargo features

- **Added:** `linux-protocol-body` (lets the IPC read custom-protocol request bodies; needs
  **webkit2gtk 2.40**), `unstable` (multiwebview).
- **Removed:** `reqwest-client`, `reqwest-native-tls-vendored` (→ `native-tls-vendored`),
  `process-command-api`, `shell-open-api`, `windows7-compat` (→ notification plugin),
  `updater` (→ plugin), `linux-protocol-headers` (now default).
- **Renamed:** `system-tray` → **`tray-icon`**.

### Environment variables — all renamed

`TAURI_PRIVATE_KEY`→`TAURI_SIGNING_PRIVATE_KEY` ·
`TAURI_KEY_PASSWORD`→`TAURI_SIGNING_PRIVATE_KEY_PASSWORD` ·
`TAURI_SKIP_DEVSERVER_CHECK`→`TAURI_CLI_NO_DEV_SERVER_WAIT` ·
`TAURI_DEV_SERVER_PORT`→`TAURI_CLI_PORT` · `TAURI_PATH_DEPTH`→`TAURI_CLI_CONFIG_DEPTH` ·
`TAURI_FIPS_COMPLIANT`→`TAURI_BUNDLER_WIX_FIPS_COMPLIANT` ·
`TAURI_DEV_WATCHER_IGNORE_FILE`→`TAURI_CLI_WATCHER_IGNORE_FILENAME` ·
`TAURI_TRAY`→`TAURI_LINUX_AYATANA_APPINDICATOR` ·
`TAURI_APPLE_DEVELOPMENT_TEAM`→`APPLE_DEVELOPMENT_TEAM` ·
`TAURI_PLATFORM`→`TAURI_ENV_PLATFORM` · `TAURI_ARCH`→`TAURI_ENV_ARCH` ·
`TAURI_FAMILY`→`TAURI_ENV_FAMILY` · `TAURI_PLATFORM_VERSION`→`TAURI_ENV_PLATFORM_VERSION` ·
`TAURI_PLATFORM_TYPE`→`TAURI_ENV_PLATFORM_TYPE` · `TAURI_DEBUG`→`TAURI_ENV_DEBUG`.
(`TAURI_CONFIG` kept its name.)

If your CI is green but signing silently stopped, this table is the first place to look — the
old names are not errors, they are simply unread.

### Structural and behavioural

- **Mobile requires a lib target** (`crate-type = ["staticlib", "cdylib", "rlib"]`), logic in
  `lib.rs` behind `#[cfg_attr(mobile, tauri::mobile_entry_point)] pub fn run()`, and a
  near-empty `main.rs`. See §Project structure.
- **The allowlist was replaced by capabilities + permissions** in
  `src-tauri/capabilities/*.json`, with identifiers like `core:window:allow-close`. All plugin
  commands are **denied by default** → `references/security.md`.
- **The Windows production origin changed to `http://tauri.localhost`** (v1 used `https://`),
  which resets IndexedDB / LocalStorage / cookies on upgrade unless you opt back in. The fix
  and its consequences are in `references/cross-platform.md` §Windows — do not plan a v1→v2
  upgrade without reading it, because the data loss is silent and irreversible.

### `cargo tauri migrate` — what it does and does not do

It automates most of the mechanical work: config key moves, JS import rewrites, Cargo
dependency changes. The docs flag it explicitly as **not a substitute for reading the migration
guide**, and the reason is worth stating: **it cannot infer your security model.** It can see
which v1 allowlist entries were `true` and it will produce capabilities and permissions that
preserve that behaviour — which means a v1 app with a broad allowlist becomes a v2 app with a
broad capability set, and you have migrated your vulnerabilities faithfully. Treat the
generated `capabilities/` as a starting point to cut down, not as output to accept. Do that
work with `references/security.md` open.

**Trade-off of migrating at all.** v2 is where the ecosystem is; staying on v1 means no
security fixes and no plugin updates. The cost is real: capability files to author, a
mandatory pass over every removed API, mobile-shaped project restructuring you may not want,
and the Windows origin change to handle for existing users. Budget the security review, not
just the codemod.

**Failure modes, symptom-first.**

- *"Config key silently ignored after migration."* It moved. Check the table above; unknown
  keys are not always errors.
- *"`use tauri::api::...` does not resolve."* The module is gone; find the plugin.
- *"Users' settings and history vanished after the v2 upgrade on Windows."* Origin scheme
  change → `references/cross-platform.md` §Windows.
- *"Every plugin command returns a permission error after migration."* Denied by default; you
  need capability entries → `references/security.md`.
- *"Signing stopped working in CI, no error."* Renamed environment variables.

**Evidence.** <https://v2.tauri.app/start/migrate/from-tauri-1/> (the authoritative delta;
every row above was read from it or from the v2 config schema, 2026-07-27).

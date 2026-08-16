# Performance — attribute the cost to a layer before you spend a week on it

**Baseline: `tauri 2.11.5`** (`tauri-runtime` 2.11.3, `tauri-runtime-wry` 2.11.4, `tauri-build`
2.6.3, `tauri-utils` 2.9.3, `wry` 0.55.1 / `tao` 0.35.3), read from the `tauri-apps/tauri` `dev`
branch, docs.rs and `v2.tauri.app` on **2026-07-27**. Every non-obvious claim below is stamped;
re-verify before assuming a 2.11 behaviour still holds on a later 2.x.

This file is the *why* for performance. The ordered procedures live in
`playbooks/startup-performance.md`, `playbooks/memory-and-leaks.md` and
`playbooks/rendering-performance.md`; they link here rather than restating anything.

The organising idea is mental-model point 4: **binary size and memory come from different
places.** Binary size is a Rust/link-time property. Runtime memory is overwhelmingly the
WebView process group. Startup is a serial Rust critical path *followed by* a web page load.
IPC is a JSON serializer with a transport floor. These four have four different tools and four
different fixes, and picking the wrong one is the standard wasted week. So the first section is
not an optimization — it is how you find out which one you have.

---

## Sections

- Evidence labels used in this file
- 1. Measurement discipline — attribute the layer first
- 2. Startup latency
- 3. Binary size
- 4. Memory
- 5. IPC performance
- 6. Rendering
- 7. Async & concurrency — the cost model
- 8. Profiling — commands that produce a number
- 9. v1 → v2 performance deltas

---

## Evidence labels used in this file

Carried from the research pass, because the difference between them is the difference between a
defensible decision and a cargo cult:

- **[SRC]** — read directly out of Tauri/wry source or official docs. Treat as fact.
- **[COMMUNITY]** — measured by someone outside the core team. The numbers are real, the
  environment is one machine. Quote *with attribution and caveat*.
- **[INFERENCE]** — derived from a documented mechanism, not asserted by any source.
- **[FOLKLORE]** — circulating claim with no traceable reproducible measurement. **Never repeat
  as fact**, and correct it when a user brings it in.
- **[UNVERIFIED]** — used once, in §9, for a docs example that looks stale but which I could not
  positively disprove.

---

## 1. Measurement discipline — attribute the layer first

### 1.1 The two-layer split, and why it decides everything

**Mechanism** [SRC]. A Tauri app is a **Core process** — your Rust binary, the only process with
full OS access — plus one or more **WebView processes** it spawns. On Windows the webview side is
a *WebView2 process group*: one browser process + N renderer processes + a GPU process + an audio
service process, all keyed to a single user data folder. On macOS it is
`com.apple.WebKit.WebContent` plus `com.apple.WebKit.GPU`. On Linux it is `WebKitWebProcess` /
`WebKitNetworkProcess`. The process-model mechanics are `references/architecture.md`'s territory;
what matters here is the consequence.

**Why this is the first question.** The two layers have disjoint fixes. Nothing you do to
`[profile.release]` moves RSS, because RSS is Chromium's. Nothing you do to your React bundle
moves cold-start on Windows, because cold-start on Windows is dominated by spawning a Chromium
browser process group. An agent that starts editing `Cargo.toml` because "the app uses 400 MB" has
already lost, and will produce a smaller binary that uses 400 MB.

**Trade-off of measuring first.** It costs a build with `tracing` on and one profiling run, maybe
twenty minutes. That is the entire cost, and it is always cheaper than the alternative.

**When to deviate.** Only when the attribution is already unambiguous — e.g. the user reports "the
whole UI freezes for eight seconds when I click Export", which is the sync-command-on-the-event-loop
signature (§7) and needs no measurement to name. Even then, measure the fix.

**Evidence.** <https://v2.tauri.app/concept/process-model/> ·
<https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model>

### 1.2 The 60-second attribution triage

Run these in order. Stop at the first one that answers the question.

1. **Look at the process list, not at your binary.** `Get-Process my-app,msedgewebview2` /
   `ps -o rss,comm -p $(pgrep -f 'my-app|WebKitWebProcess')` / Activity Monitor filtered on both
   your binary *and* `com.apple.WebKit.*`. If your binary is 40 MB and the webview group is
   350 MB, the Rust layer is not your problem. Exact per-OS commands: §4.2.
2. **Split startup at first paint.** *Blank window for N seconds, then everything appears at
   once* = the cost is in the serial pre-paint Rust path (§2.1) — the window already exists and is
   visible, it just has nothing in it. *Window paints a shell quickly and then the UI is
   unresponsive* = the cost is after `index.html` starts loading, i.e. frontend or IPC.
3. **Get the Rust startup budget in one run.** Build with `tauri/tracing` and
   `FmtSpan::CLOSE` (§8.1). `app::build`, `app::setup` and per-plugin
   `app::plugin::register{name=…}` print their elapsed times. If those sum to 90 ms of a 2.4 s
   cold start, you have proven the Rust layer is innocent — which is a result, not a failure.
4. **Anything after the first byte of `index.html` belongs to the webview devtools Performance
   panel.** That is ordinary web profiling; `clouds-f` owns it. Devtools access itself is
   `references/debugging-and-testing.md`.
5. **Never conflate binary size with memory.** A 12 MB binary and a 300 MB RSS are not related
   quantities. §3 and §4 do not interact.

### 1.3 Measured vs Folklore ledger

This is the index of what you are allowed to state as fact. Each line points at the section that
reasons about it; the reasoning is not repeated here.

**Measured, first-party, quotable as fact** [SRC]:

| Fact | § |
| --- | --- |
| `MAX_JSON_DIRECT_EXECUTE_THRESHOLD = 8192` — *"8192 byte JSON payload runs roughly 2x faster through eval than through fetch on WebView2 v135"* | §5.2 |
| `MAX_RAW_DIRECT_EXECUTE_THRESHOLD = 1024` — *"1024 byte payload runs roughly 30% faster through eval than through fetch on macOS"* | §5.2 |
| `transparent: true` on macOS: ~620 mW vs ~75 mW GPU power, ~36 % vs ~10 % HW active residency (≈8×) on a *fully static* page; Intel: `com.apple.WebKit.GPU` at 1380 % CPU | §6.3 |
| WebView2: one browser process per user data folder; the first webview for a UDF starts it; extra origins → extra renderers | §4.1 |
| Background throttling: timers throttled and the view potentially unloaded after **~5 minutes** hidden; policy configurable only on macOS 14+ / iOS 17+ | §4.5 |
| Default WebView2 args wry passes: `--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection` | §2.2 |
| Release `codegen-units` default is **16**; debug binaries are *"30% or more larger"* than release; LTO worth *"10-20% or more"* runtime | §3.1 |
| Tokio `max_blocking_threads` default is **512** | §7.2 |

**Measured, community, quotable only with attribution** [COMMUNITY]:

| Measurement | Caveat that must travel with it | § |
| --- | --- | --- |
| Binary IPC, 10 MB payload: ~5 ms macOS / ~200 ms Windows | Tauri maintainer FabianLars, discussion #11915, explicitly *"non-scientific"*, one Discord report | §5.5 |
| Rust-side dispatch: 25 B 721.70 ns · 1 KB 8.077 µs · 64 KB 2.272 ms (Linux i7-10700KF, Criterion 0.5) | From `tauri-conduit`'s own BENCHMARKS.md — a **competing IPC library**. Methodology disclosed, bias present | §5.5 |
| End-to-end macOS aarch64 medians: 25 B 300 µs · 1 KB 400 µs · 64 KB 6.700 ms | Same source; small/medium timings are **clamped by WebKit's 1 ms `performance.now()` resolution** — only the 64 KB figure is representative | §5.5 |

**Folklore — do not repeat, and correct it when a user brings it** [FOLKLORE]:

- **"Tauri cold-starts in 380 ms vs Electron's 1420 ms" / "96 % smaller apps."** These two numbers
  circulate widely and are the ones a user is most likely to quote at you. They trace **only** to
  SEO aggregator pages (e.g. `tech-insider.org`) which cite *"indie developer benchmarks across
  r/rust and the Tauri Discord"* and claim to *"match official measurements published with the
  v2.9.6 release notes"*. **No such figures appear in any Tauri release notes, docs or blog post.**
  There is no first-party Tauri-vs-Electron size or startup table at all. See §3.5 for what you
  *can* honestly say.
- **"Always set `opt-level = "z"` for the smallest binary."** Cargo's own docs say `"s"` and `"z"`
  are *"not necessarily smaller"* than each other. §3.1.
- **"`lto = false` disables LTO."** It selects thin *local* LTO, which is the default for any
  optimized build. `lto = "off"` is off. §3.1.
- **"`Channel<&[u8]>` streams binary."** It streams a JSON number array. §5.4 — this one is in the
  **official docs**, which is why it is so widely copied.
- **"Use `ioreg` / `Device Utilization %` to check macOS GPU load."** It reports ~30 % for *any*
  foreground WKWebView including a blank Safari tab. §6.3.
- **"Ship `WEBKIT_DISABLE_COMPOSITING_MODE=1` to fix Linux."** Official guidance is the opposite:
  last resort, disables accelerated compositing for every user. §6.2 and `references/cross-platform.md`.

### 1.4 Symptom index

Match the user's words to a layer before opening a file.

| Symptom, as reported | Layer | Cause | § |
| --- | --- | --- | --- |
| "Blank window for N seconds, then everything appears at once" | Rust, pre-paint | blocking `setup` or plugin `initialize()` | §2.1 |
| "No window appears at all on launch" | frontend | `visible: false` and the frontend threw before `show()` | §2.4 |
| "My size tuning did nothing" | build | `[profile.release]` in a workspace member | §3.2 |
| "The app hard-crashes instead of showing an error" | build | `panic = "abort"` turning a rejected invoke into an abort | §3.3 |
| "Memory roughly doubled when I added a second window" | webview | separate `data_directory` → a second WebView2 process group | §4.1 |
| "Streamed a large file, reloaded the page, RSS never came back" | Rust | orphaned `ChannelDataIpcQueue` entry | §4.3 |
| "Core process RSS climbs linearly with session length" | Rust | growing managed `State`, or listeners never unlistened | §4.3 |
| "This handler fires 7× and makes 7 duplicate requests" | frontend | SPA route re-`listen`s without cleanup | §4.4 |
| "Tray app's UI state is gone when I reopen it" | webview | background throttling unloaded the view after ~5 min | §4.5 |
| "Timers die when hidden on Windows, fine on my Mac" | config | `backgroundThrottling` is macOS 14+/iOS 17+ only | §4.5 |
| "1000-row grid takes ~0.3 s before anything renders" | IPC | per-row `invoke`, paying the transport floor N times | §5.5 |
| "Streaming through a Channel is slower than one big invoke" | IPC | `Channel<&[u8]>` number-array inflation | §5.4 |
| "`emit_to` appears to vanish" | IPC | webview-specific events don't reach global listeners | §5.3 |
| "Fan spins / battery drains at idle on macOS" | rendering | `transparent: true` window compositing | §6.3 |
| "Charts/maps/terminal fast in Chrome, slow in the Linux build" | rendering | WebKitGTK silently fell back to a software rasterizer | §6.2 |
| "The whole UI freezes during one operation" | Rust threading | sync command on the event loop | §7.1 |
| "Everything gets slow once N uploads are in flight" | Rust threading | blocking calls inside async tasks starving workers | §7.2 |
| "SmartScreen prompts / an Edge mini-menu appeared after a perf flag" | config | `additionalBrowserArgs` dropped wry's defaults | §2.2 |

---

## 2. Startup latency

### 2.1 The verified critical path, and which parts are serial

**Mechanism** [SRC], from `crates/tauri/src/app.rs`. `Builder::run(ctx)` → `Builder::build(ctx)` →
`App::run(cb)`, in this order:

1. **`generate_context!()`** — a proc macro. Assets are embedded **at compile time** and, with the
   default `compression` feature on (`tauri/compression → tauri-utils/compression → brotli`),
   brotli-compressed. Cold start therefore includes brotli *decompression* of every asset the
   first page touches.
2. **`Builder::build()`** —
   `AppManager::new(...)`; the runtime is constructed (tao event loop + wry: NSApplication / GTK /
   the Win32 message loop); `app.register_core_plugins()` initializes **9 core plugins
   synchronously, in order** (`core::path`, `core::event`, `core::window`, `core::webview`,
   `core::app`, `core::resources`, `core::image`, `core::menu` on desktop, `core::tray` behind the
   `tray-icon` feature); the default macOS menu is built if you supplied none;
   `app.manage(ChannelDataIpcQueue::default())` plus the internal `__TAURI_CHANNEL__` plugin; then
   `app.manager.initialize_plugins(handle)?` runs **your** plugins' `initialize()` — synchronously,
   on the main thread, in registration order, **before any window exists**.
3. **`App::run()` → `fn setup(app)`** — for each `window_config` in
   `app.config().app.windows` where `create == true`,
   `WebviewWindowBuilder::from_config(...)?.build()?`. This is **sequential and blocking: one OS
   window plus one platform webview per iteration.** Then `app.manager.assets.setup(app)`, then
   **your `.setup()` closure — still blocking the main thread, event loop not yet pumping.**
4. **The event loop starts.** Only now does the webview begin fetching `index.html` through the
   custom protocol and parsing your bundle.

**Why it is ordered this way.** Plugins must be able to register commands, URI-scheme protocols and
initialization scripts *before* a webview exists, because `Plugin::initialization_script()` output
is injected into the document ahead of any page script. Windows must exist before `setup` so that
`setup` can legally call `app.get_webview_window("main")`. The ordering buys determinism.

**Trade-off.** Determinism is paid for by putting every plugin `initialize()` and every window
construction on one serial, pre-paint critical path with no concurrency available to you.

**Symptoms.**
- *"Blank white window for N seconds, then the whole UI appears at once."* The window exists and is
  visible (config default) while `setup` blocks. Time N and compare it to the `app::setup` span
  (§8.1) — if they match, the fix is in `setup`, not in your frontend.
- *"The app freezes during startup and never recovers."* A `std::thread::sleep` or blocking IO
  inside an async task spawned from `setup`. The official splashscreen lab is explicit: *"Don't use
  `std::thread::sleep` in async functions… you'll be locking all tasks scheduled to run on that
  thread from being executed, causing your app to freeze."*
- *"Startup got 150 ms slower and I only added a plugin."* Every plugin costs twice — once in
  serial `initialize()`, and again as an injected `initialization_script` the webview must parse and
  execute **on every page load**.

**When to deviate from "keep `setup` empty".** Anything the very first frame genuinely depends on —
restoring window geometry before showing, or opening the database the initial route reads — belongs
in `setup`, because deferring it just moves the blank screen behind a spinner. Everything else does
not. `case-studies.md` §10 is a real `setup()` that makes this split deliberately.

**Evidence.** <https://raw.githubusercontent.com/tauri-apps/tauri/dev/crates/tauri/src/app.rs> ·
<https://raw.githubusercontent.com/tauri-apps/tauri/dev/crates/tauri/src/plugin.rs> ·
<https://v2.tauri.app/learn/splashscreen/>

### 2.2 What dominates cold start, per OS

**Mechanism — Windows / WebView2** [SRC]. `wry::webview2::InnerWebView::new` calls
`CreateCoreWebView2EnvironmentWithOptions(...)` then
`ICoreWebView2Environment10::CreateCoreWebView2ControllerWithOptions` (falling back to
`ICoreWebView2Environment::CreateCoreWebView2Controller`). Microsoft: *"When the first `WebView2`
instance is created for a given user data folder, the browser process for the WebView2 Runtime
processes collection that is associated with that user data folder will be started."* So the
dominant Windows cold-start term is **spawning and initializing a Chromium browser process group**,
and it happens inside your first `WebviewWindowBuilder::build()` — i.e. inside step 3 above, before
your `setup` even runs.

**Mechanism — macOS / WKWebView** [SRC]. WKWebView is a preinstalled OS component (since 10.10),
updated only with the OS. Construction spins up the shared `com.apple.WebKit.WebContent` /
`com.apple.WebKit.GPU` service processes, which are frequently already warm from other apps.

**Mechanism — Linux / WebKitGTK** [SRC]. `webkit2gtk` 2.40+ on GTK 3.24, pinned by distro package —
so both startup cost and web-platform support vary per distro and you cannot generalise from your
dev machine. Engine divergence itself is `references/cross-platform.md`.

**Why the Windows number is the one to optimise.** It is the only platform where the engine is
*not* a warm shared OS service, so it is the platform where "reduce the number of webviews you
create at startup" (§2.3) actually pays.

**Trade-offs / symptoms.**
- *"SmartScreen prompts or a stray Edge 'mini menu' reappeared after I added one perf flag."*
  Setting `additionalBrowserArgs` **silently replaces** wry's defaults —
  `--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection` (wry#535, tauri#1345). Re-add
  them by hand.
- The same config doc warns: *"Webview instances with different browser arguments must also have
  different data directories."* Which means adding a browser arg to one window can silently buy you
  a second process group — see §4.1 for what that costs in RSS.

**When to deviate.** Do not touch `additionalBrowserArgs` for performance at all unless you have a
measurement naming a specific Chromium feature as the cost. It is a high-blast-radius knob with a
security-relevant default.

**Evidence.** <https://raw.githubusercontent.com/tauri-apps/wry/dev/src/webview2/mod.rs> ·
<https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model> ·
<https://v2.tauri.app/reference/webview-versions/>

### 2.3 Lazy vs eager windows — the largest single lever

**Mechanism** [SRC]. `WindowConfig::create: bool`, `#[serde(default = "default_true")]`. `fn setup`
only builds windows where `create == true`. The doc comment: *"Whether Tauri should create this
window at app startup or not. When this is set to `false` you must manually grab the config object
via `app.config().app.windows` and create it with `WebviewWindowBuilder::from_config`."*

```json
// src-tauri/tauri.conf.json — register the window, don't pay for it at startup
{
  "app": {
    "windows": [
      { "label": "main",     "backgroundColor": "#1b1b1f", "visible": false },
      { "label": "settings", "create": false, "url": "/settings" }
    ]
  }
}
```

```rust
// build it on demand — keeps its cost off the cold-start path entirely
#[tauri::command]
fn open_settings(app: tauri::AppHandle) -> tauri::Result<()> {
    if app.get_webview_window("settings").is_some() {
        return Ok(());
    }
    let cfg = app
        .config()
        .app
        .windows
        .iter()
        .find(|w| w.label == "settings")
        .expect("settings window must be declared in tauri.conf.json")
        .clone();
    tauri::WebviewWindowBuilder::from_config(&app, &cfg)?.build()?;
    Ok(())
}
```

**Why it is the largest lever.** Window+webview construction is the most expensive step in the
startup path *and* it is serial (§2.1). A three-window app pays three full webview constructions
before `setup` runs. Deferring two of them removes their entire cost from time-to-first-paint, and
on Windows may avoid a second process group entirely.

**Trade-off.** The first open of a lazily-created window is visibly slower than switching to a warm
one — you pay the full construction cost interactively, with the user watching. That is correct for
a settings dialog and wrong for a window the user opens on every launch.

**Symptoms of getting it wrong.** *"`.unwrap()` panicked on `get_webview_window`"* —
`Manager::get_webview_window` returns `None` for a `create: false` window until you build it, so
code written against an always-present window panics. `create: false` windows still exist in the
config and are still ACL-relevant; they are simply not instantiated.

**When to deviate.** If the second window is on the critical user path (a two-pane app where both
panes are the product), eager creation is right and you optimise elsewhere.

**Evidence.** `tauri-utils/src/config.rs` L1939-1955 ·
<https://docs.rs/tauri/latest/tauri/webview/struct.WebviewWindowBuilder.html>

### 2.4 The white flash: `backgroundColor` and `visible: false`

**Mechanism** [SRC]. Two independent levers, and they compose:

1. `WindowConfig::background_color: Option<Color>` — *"Set the window **and webview** background
   color."* This is the real fix: the OS window surface and the webview surface both start in your
   colour, so there is nothing white to flash. Platform notes from source: on Windows the alpha
   channel is ignored for the window layer, and on Windows 8+ a non-zero alpha is ignored for the
   webview layer too.
2. `WindowConfig::visible: bool` (default `true`) + `WebviewWindow::show()` — keep the window
   unmapped until the frontend reports it has painted.

```json
{ "label": "main", "visible": false, "backgroundColor": "#1b1b1f" }
```

```ts
// frontend — after the first real paint, NOT on DOMContentLoaded
import { getCurrentWindow } from '@tauri-apps/api/window';

const w = getCurrentWindow();
const failsafe = setTimeout(() => void w.show(), 3000); // always show eventually

requestAnimationFrame(() => {
  requestAnimationFrame(async () => {
    clearTimeout(failsafe);
    await w.show();
  });
});
```

**Why the failsafe is not optional.** `visible: false` trades "empty window immediately" for "no
window, then a complete window". If the frontend throws before reaching `show()`, the user gets
**no window at all and no feedback** — a strictly worse failure than a white flash, and one that
looks to the user like the app didn't launch. The timeout converts an invisible failure into a
visible broken UI, which is diagnosable.

**Trade-offs.** `backgroundColor` alone is cheap, additive, and has no failure mode — always set
it. `visible: false` costs you the "something is happening" signal during startup, so it is only a
win if your time-to-paint is short enough that the user does not think the click missed.

**Symptoms.**
- *"It still flashes white even with `visible: false`."* You are showing on `DOMContentLoaded`. The
  DOM exists but nothing has been painted yet. Double `requestAnimationFrame`, or your framework's
  post-commit hook, is the correct signal. [INFERENCE — standard web rendering semantics; Tauri
  documents no "painted" event.]
- *"The window jumps to centre after appearing."* That is a **v1** symptom, and v1-era blog posts
  tell you to call `center()` after `show()`. v2 changelog: *"Enhance centering a newly created
  window, it will no longer jump to center after being visible."* Delete the workaround.

**When to deviate.** If your startup is genuinely slow and cannot be made fast (a big local model
load, a migration), showing nothing for four seconds is worse than showing a splash — see §2.5.

**A real one.** ZUS ships `visible: false` in config and shows the window explicitly from `setup`
after restoring saved geometry, which also fixes the appear-at-default-size-then-resize jump. See
`case-studies.md` §10.

**Evidence.** `tauri-utils/src/config.rs` L2057-2061, L2213-2222 ·
<https://v2.tauri.app/blog/tauri-20/>

### 2.5 Splashscreen — a second webview, priced accordingly

**Mechanism** [SRC]. The official lab uses two configured windows — `main` with `visible: false`
and a `splashscreen` visible immediately — plus a shared `SetupState` in managed state tracking
**both** a frontend task and a backend task. When both report done, the splash closes and `main`
shows.

```rust
use std::sync::Mutex;
use tauri::{async_runtime::spawn, AppHandle, Manager, State};

struct SetupState { frontend_task: bool, backend_task: bool }

#[tauri::command]
async fn set_complete(
    app: AppHandle,
    state: State<'_, Mutex<SetupState>>,
    task: String,
) -> Result<(), ()> {
    {
        let mut s = state.lock().unwrap();
        match task.as_str() {
            "frontend" => s.frontend_task = true,
            "backend"  => s.backend_task  = true,
            _ => return Err(()),
        }
        if !(s.frontend_task && s.backend_task) { return Ok(()); }
    } // drop the guard before touching windows

    app.get_webview_window("splashscreen").unwrap().close().unwrap();
    app.get_webview_window("main").unwrap().show().unwrap();
    Ok(())
}
```

**Why two-sided completion.** Only the frontend knows when it has hydrated; only Rust knows when
migrations finished. Gating on one produces a splash that closes onto an unusable UI — which is
worse than no splash, because the user now clicks on a dead interface.

**Trade-off, and it is the deciding one.** A splash window **is a second full webview** — on
Windows, another renderer in the process group, constructed serially before `setup` (§2.1). You are
adding startup cost in order to make startup cost *feel* shorter. For anything under roughly
300 ms of setup work, `visible: false` + `backgroundColor` is strictly cheaper and looks the same.

**Symptoms.** *"Deadlock when the splash closes."* Holding the `MutexGuard` across
`close()`/`show()` while a window event handler touches the same state. Scope the lock, as above.

**When to deviate.** Use a splash when setup is genuinely long *and* you have progress to report.
A splash with an indeterminate spinner and 200 ms of work is pure cost.

**Evidence.** <https://v2.tauri.app/learn/splashscreen/>

### 2.6 Deferring service init out of `setup`

**Mechanism** [SRC]. Two registration APIs with materially different timing:

- `Builder::plugin(p)` → `self.plugins.register(plugin)`. **Deferred** to `build()`, then
  initialized synchronously by `manager.initialize_plugins(handle)` — on the pre-paint path.
- `AppHandle::plugin(p)` → `store.initialize(&mut plugin, self, &self.config().plugins)?` **then**
  `store.register(plugin)`. Initializes **immediately, wherever you call it**. Its doc comment says
  precisely this: *"This function can be used to register a plugin that is loaded dynamically e.g.
  after login. For plugins that are created when the app is started, prefer `Builder::plugin`."*

```rust
.setup(|app| {
    let handle = app.handle().clone();
    tauri::async_runtime::spawn(async move {
        let pool = connect_db().await;              // slow IO, now post-paint
        handle.manage(pool);
        if let Err(e) = handle.plugin(tauri_plugin_sql::Builder::default().build()) {
            log::warn!("sql plugin unavailable: {e}");   // never unwrap on a detached task
        }
        let _ = handle.emit("services-ready", ());
    });
    Ok(())                                          // setup returns immediately
})
```

**Why.** This converts a serial pre-paint cost into a post-paint background cost. The UI renders a
skeleton and reacts to `services-ready`.

**Trade-offs.** You have now introduced a **readiness protocol** into your frontend, and commands
belonging to a deferred plugin do not exist until it registers — calls before that point reject.
`AppHandle::plugin` returns `crate::Result<()>` on a detached task, so a deferred init failure
surfaces at an awkward moment and must be handled, not `.unwrap()`ed.

**Symptoms.**
- *"A command works in one build and 404s in another."* `removeUnusedCommands` (§3.4) reads
  capability files **at build time** and *"won't be accounting for dynamically added ACLs at
  runtime"*. Dynamic plugin registration plus `removeUnusedCommands: true` strips commands you
  intended to add later.
- *"Calling a deferred plugin's command right after launch rejects."* Expected. Gate the UI on
  `services-ready` rather than retrying.

**When to deviate.** If a subsystem is required for the first frame to be meaningful, deferring it
buys you a skeleton the user cannot use. Also see `case-studies.md` §10 for the related decision of
which subsystems may `log::warn!` and continue versus which must abort startup.

**Evidence.** `crates/tauri/src/app.rs` L508-548, L1851-1864, L2439 ·
<https://v2.tauri.app/concept/size/>

---

## 3. Binary size

Binary size is a Rust and link-time property. It has **no effect on runtime memory** (§4) and only
a second-order effect on startup (less to page in, more to decompress). Optimize it because
download size and install footprint matter to your users, not because you expect the app to get
faster.

### 3.1 The cargo profile, and what each knob actually costs

**Mechanism** [SRC]. The officially recommended profile, verbatim from the App Size page:

```toml
[profile.dev]
incremental = true    # Compile your binary in smaller steps.

[profile.release]
codegen-units = 1     # Allows LLVM to perform better optimization.
lto = true            # Enables link-time-optimizations.
opt-level = "s"       # Prioritizes small binary size. Use `3` if you prefer speed.
panic = "abort"       # Higher performance by disabling panic handlers.
strip = true          # Ensures debug symbols are removed.
```

Nightly adds `trim-paths = "all"` and `rustflags = ["-Cdebuginfo=0", "-Zthreads=8"]`.

What each one buys and what it costs:

- **`codegen-units = 1`** — the release default is **16**. Dropping to 1 removes cross-unit
  optimization barriers, so the binary is usually both smaller *and* faster. **Cost: real
  compile-time.** Whole-crate codegen is single-threaded per crate; on a large workspace this is
  the knob that turns a 90-second release build into a five-minute one. Set it in the release
  profile only, never in a profile CI uses for fast feedback.
- **`lto = true`** (= `"fat"`) — whole-program optimization. The Rust Performance Book: LTO *"can
  improve runtime speed by 10-20% or more, and also reduce binary size."* **Cost: link time and
  peak linker memory**, which is the usual cause of an OOM-killed release build in a
  memory-constrained CI runner. Escalation order is `off` < `false` (thin *local*) < `"thin"` <
  `"fat"`/`true`; `lto = false` is **not** off (§1.3).
- **`opt-level`** — `3` for speed, `"s"` for size, `"z"` most aggressive for size. Cargo's own docs
  warn the result is non-monotonic: *"the `"s"` and `"z"` levels not being necessarily smaller."*
  **Cost of `"s"`/`"z"`: runtime speed in your own hot Rust paths.** If the Rust layer does real
  work (parsing, hashing, image decode), measure both; do not cargo-cult `"z"`.
- **`strip = true`** — **Cost: unreadable production backtraces and unsymbolicated crash reports.**
  Note the win is smaller than it used to be: debug info is not generated for local release builds,
  and std's debug info has been stripped in release **since Rust 1.77**, so `strip` now mostly
  removes symbol tables. If you ship crash reporting, keep unstripped artifacts.
- **`panic = "abort"`** — this one **changes runtime behaviour**, not just size. §3.3.

**When to deviate.** For an app whose Rust layer is mostly IPC plumbing, `opt-level = "s"` costs
nothing you can measure and the size win is real. For an app doing heavy native work — a local
inference runtime, a search index, a compiler — `opt-level = 3` with `lto = "fat"` is the correct
choice and you accept the larger binary.

**Evidence.** <https://v2.tauri.app/concept/size/> ·
<https://nnethercote.github.io/perf-book/build-configuration.html>

### 3.2 The gotcha that makes all of §3.1 do nothing

**Mechanism** [SRC]. **Cargo only reads profile settings from the workspace-root `Cargo.toml`.**
If `src-tauri` is a member of a workspace, a `[profile.release]` block inside
`src-tauri/Cargo.toml` is **silently ignored** — no warning, no error, no output at all.

**Symptom, and it is the reason this has its own subsection.** *"I applied the official size
profile and the binary is exactly the same size."* Before debugging anything else, ask where the
workspace root is. A multi-crate Tauri app — which is the shape any non-trivial one converges on
(ZUS runs 24 workspace crates, `case-studies.md`) — hits this by default.

**How to confirm in ten seconds.** Rebuild and compare `cargo build --release -v` output for
`-C codegen-units=` and `-C opt-level=`, or simply move the block to the root `Cargo.toml` and diff
the artifact size. If it changes, that was the bug.

**Why Cargo does this.** Profiles are a whole-build property: two workspace members cannot be
compiled with conflicting profiles in one build graph, so only the root gets to declare them. The
silence is the design flaw, not the rule.

**When to deviate.** Never. Move the block to the root. If you need `src-tauri` to differ from other
members, use `[profile.release.package.<name>]` overrides — still declared at the root.

**Evidence.** <https://v2.tauri.app/concept/size/> (which states the workspace rule) ·
<https://doc.rust-lang.org/cargo/reference/profiles.html>

### 3.3 `panic = "abort"` converts a rejected promise into a process crash

**Mechanism.** Async commands run as Tokio tasks. With unwinding (the default), a panic inside a
command unwinds that task, Tauri turns it into an error response, and the JS `invoke` promise
**rejects** — your frontend catches it and shows a toast. With `panic = "abort"` there is no
unwinding: the panic aborts **the whole process**. A `.unwrap()` on a malformed path from the
webview stops being a caught error and becomes a hard crash with no dialog and no log line.
[INFERENCE from documented Rust and Tokio panic semantics — Tauri does not document this
interaction, and neither does the App Size page that recommends the setting.]

**Why the official profile recommends it anyway.** It removes landing pads and unwind tables, which
is a genuine size and a small speed win, and it is the right default for a binary whose failure
modes are all fatal anyway. Tauri's page is optimizing for size, and does not weigh the desktop-app
consequence.

**Symptom.** *"The app disappears instantly when I do X, no error, no dialog, nothing in the log."*
X reaches a `panic!`, `unwrap`, `expect`, slice index, or integer overflow (in debug) inside a
command. On a build with unwinding the same input produces a rejected promise and a visible error.
If a bug is reproducible in `tauri dev` as a rejected invoke and reproducible in the release bundle
as a vanishing window, `panic = "abort"` is the difference.

**The trap that makes this survive code review.** `panic = "abort"` lives in `[profile.release]`,
and **`cargo test` uses the `dev`/`test` profiles**. A fully green test suite tells you *nothing*
about the abort behaviour of your shipped binary. There is no test you can write in the normal way
that exercises it. The only real verification is exercising the failure path against an actual
release bundle.

**When to deviate — i.e. when to drop `panic = "abort"`.** Keep unwinding if any command
deserializes or acts on webview-controlled input and you are not prepared to prove every one of
them is panic-free. Keep it if you have crash-free-session metrics you care about. Keep
`panic = "abort"` if your commands are audited, you have an out-of-process crash reporter that
handles `SIGABRT`, and the size win matters (a shipping-size-constrained utility). Halfway house:
audit the command layer for `unwrap`/`expect` on webview-supplied values, return
`Result<_, YourError>` everywhere, and only then enable it.

**Evidence.** <https://v2.tauri.app/concept/size/> ·
<https://doc.rust-lang.org/cargo/reference/profiles.html#panic> · command error/threading semantics:
`references/ipc-and-commands.md`.

### 3.4 `removeUnusedCommands`

**Mechanism** [SRC]. `{ "build": { "removeUnusedCommands": true } }`. `tauri-cli` passes an env var
(`REMOVE_UNUSED_COMMANDS`, documented as an unstable implementation detail, set to the project dir)
to the build scripts of `tauri`, `tauri-build` and `tauri-plugin`; each derives the allowed-command
list from your **capability files**, and `generate_handler!` drops everything outside it. Requires
`tauri@2.4`, `tauri-build@2.1`, `tauri-plugin@2.1`, `tauri-cli@2.4`.

**Why it exists.** Plugin crates ship dozens of commands and most apps permit a handful; before
this, you linked all of them.

**Trade-off.** Official tip: *"To maximize the benefit of this, only include commands that you use
in the ACL instead of using `default`s."* If your capability file is a list of `…:default`
permission sets, you have already forfeited most of the win. So the size benefit is coupled to
capability minimalism — the same discipline `references/security.md` argues for on security
grounds, which is a rare case of the two pulling the same direction.

**Symptom.** *"A command exists in the source and 404s at runtime, only in release."* Either it is
not in any capability, or it was registered dynamically at runtime (§2.6) where the build-time
scan cannot see it.

**When to deviate.** Turn it off while you are actively adding dynamically-registered plugins, and
turn it back on with an explicit capability list before release.

### 3.5 Features, and what they cost

**Mechanism** [SRC]. `tauri`'s default features are exactly:

```
default = ["wry", "compression", "common-controls-v6", "dynamic-acl", "x11", "dbus"]
```

Everything else is opt-in: `tracing`, `devtools`, `isolation`, `protocol-asset`, `tray-icon`,
`image-png`, `image-ico`, `specta`, `macos-private-api`, `macos-proxy`, `native-tls`,
`native-tls-vendored`, `rustls-tls`, `config-json5`, `config-toml`, `webview-data-url`,
`linux-libxdo`, `unstable`, `test`.

The ones with a real cost story:

- **`wry`** = `["webview2-com", "webkit2gtk", "tauri-runtime-wry"]` — the entire renderer binding.
  Not optional in practice.
- **`compression`** = `["brotli"]` — trades binary size **down** for cold-start decompression
  **up** (§2.1). It is on by default and correct by default; turn it off only if you have measured
  asset decompression on the startup path and your installer size is not a constraint.
- **`isolation`** pulls `aes-gcm` + `getrandom` + `serialize-to-javascript`, adds a second iframe,
  and adds a per-message AES-GCM encrypt/decrypt on the IPC hot path — there is a dedicated
  `ipc::request::decrypt_isolation_payload` span (§8.1) precisely because it is measurable. Real
  security value, real per-call cost; the security argument is `references/security.md`'s.
- **`image-png` / `image-ico`** gate `image` crate codecs; `image` is `default-features = false`, so
  you pay only for the formats you name.
- **`tracing`** — zero cost when off (every span is `#[cfg(feature = "tracing")]`), meaningful when
  on. §8.1.
- **`devtools`** — *"a private API on macOS. Using private APIs on macOS prevents your application
  from being accepted to the App Store."* The same warning applies to `macos-private-api`, which
  `transparent` requires on macOS (§6.3).

**Symptom.** *"`devtools` / an `image` codec is in my release build and I never enabled it."*
**Feature unification is global**: one dependency anywhere in the graph enabling `tauri/devtools`
turns it on for your release binary too. `cargo tree -e features` is the only reliable check —
reading your own `Cargo.toml` is not.

**When to deviate.** Enable `devtools` in release deliberately if you support users by asking them
to open the inspector, and accept that you have given up the Mac App Store channel
(`references/build-and-distribution.md` owns that decision).

### 3.6 What you may honestly claim versus Electron

**Mechanism** [SRC]. Tauri does not ship a runtime: *"the WebView libraries are **not** included in
your final executable but dynamically linked at runtime… This makes your application significantly
smaller."* Electron ships Chromium plus Node.

**What is structurally guaranteed:** order-of-magnitude smaller installers and lower baseline RSS
than Electron, because you are not shipping or starting a browser. That follows from the
architecture and needs no benchmark.

**What is not:** any specific multiplier. There is **no first-party Tauri page publishing a
Tauri-vs-Electron size or startup table.** The widely-quoted "380 ms vs 1420 ms" and "96 % smaller"
figures are folklore — see §1.3 for the trace. If a user cites them, correct them and offer to
measure their app instead.

**Calibration points that are real, but are about *Rust*, not about Tauri** [SRC], from
`min-sized-rust`: a debug binary is *"30% or more larger"* than release; a fully stripped no-std
hello-world reaches ~8 KB; `build-std` + `optimize_for_size` reaches 51 KB on macOS;
`panic=immediate-abort` reaches 30 KB. **These are the Rust floor and a Tauri app is nowhere near
it** — you link wry, tao, serde_json, tokio, GTK/COM bindings and your embedded frontend. Quoting
them as Tauri numbers is a category error.

**Evidence.** <https://v2.tauri.app/concept/size/> · <https://github.com/johnthagen/min-sized-rust> ·
`crates/tauri/Cargo.toml` · `crates/tauri-utils/Cargo.toml`

---

## 4. Memory

### 4.1 Where RSS actually goes

**Mechanism** [SRC]. See §1.1 for the process split. The consequence for measurement: **measuring
only your own binary's RSS measures the smallest part of your app.** The Chromium/WebKit renderer
and GPU processes dominate, typically by an order of magnitude.

**Why this matters for the fix.** If the webview group holds the memory, the levers are all
web-side — fewer retained DOM nodes, virtualized lists, dropped image caches, fewer origins — and
`clouds-f` owns them. The two Tauri-level levers are the number of webviews you create (§2.3) and
whether they share a user data folder.

**Symptoms.**
- *"Memory roughly doubled when I added a second window."* On Windows, two webviews with
  **different `data_directory` values are two complete WebView2 process groups**. Microsoft: *"If
  an application makes use of multiple user data folders, a collection of WebView2 Runtime processes
  will be created for each."* Sharing the user data folder is the fast, cheap path — and note from
  §2.2 that differing `additionalBrowserArgs` *forces* you to differ the data directory, so a perf
  flag can silently double your RSS.
- *"RSS is higher than expected for one window."* Distinct origins inside one user data folder spawn
  additional renderers via Site Isolation. A webview loading `https://…` content alongside
  `tauri://localhost` pays for two renderers.

**When to deviate.** A window that renders genuinely untrusted content *should* get its own data
directory and its own capability (`references/security.md`); pay the memory, gain the isolation.
That is a security decision that costs memory, not a memory decision.

### 4.2 Measuring per-process, per OS

Copy-pasteable, and each measures the right thing.

**Linux.** `smaps_rollup` is documented in the kernel as *"Accumulated smaps stats for all mappings
of the process. This can be derived from smaps, but is faster and more convenient"*:

```bash
# core process + every webkit helper, PSS-accurate
for p in $(pgrep -f 'my-app|WebKitWebProcess|WebKitNetworkProcess'); do
  printf '%-8s %-28s ' "$p" "$(tr -d '\0' </proc/$p/comm)"
  awk '/^Pss:/{p+=$2} /^Private_Dirty:/{d+=$2} END{printf "Pss=%dMiB PrivDirty=%dMiB\n", p/1024, d/1024}' /proc/$p/smaps_rollup
done

# quick single-process breakdown (VmRSS = RssAnon + RssFile + RssShmem)
grep -E '^(VmRSS|RssAnon|RssFile|RssShmem|VmSwap):' /proc/<pid>/status
```

Use **Pss**, not RSS, when summing across processes — shared Chromium/WebKit pages are otherwise
counted once per process and your total is fiction.

**macOS.** `footprint(1)` reports the kernel's `phys_footprint` ledger, which is *"the value
reported by… the 'MEM' column in top(1) and the 'Memory' column in Activity Monitor.app"* — so it
is the number your users will quote at you:

```bash
sudo footprint -proc my-app -proc 'com.apple.WebKit.WebContent' -categories
sudo footprint --sample 5 -pid <pid>          # sampling mode
vmmap <pid> | tail -40                        # single process, raw kernel metrics
```

`footprint` needs root and accepts repeated `-proc`/`-pid`. **`vmmap`'s `DIRTY` column excludes
compressed/swapped memory** (which `footprint -swapped` shows) and `vmmap` handles only one process
— that mismatch is the usual reason "my numbers don't match Activity Monitor".

**Windows.**

```powershell
Get-Process -Name my-app,msedgewebview2 |
  Select-Object Id,ProcessName,
    @{n='WorkingSetMB';  e={[int]($_.WorkingSet64/1MB)}},
    @{n='PrivateMB';     e={[int]($_.PrivateMemorySize64/1MB)}} |
  Format-Table -Auto
```

For a per-renderer breakdown, WebView2 exposes a **Browser Task Manager** via
`ICoreWebView2_6::OpenTaskManagerWindow`, which *"displays all processes that are associated with
the browser process of your WebView2 … including their associated purposes."* Reaching it from
Tauri means `WebviewWindow::with_webview` and a COM cast. [INFERENCE — Tauri exposes no wrapper for
`OpenTaskManagerWindow`; `with_webview` is the documented escape hatch to the platform handle.]

**Trade-off of all of the above.** These are point-in-time snapshots. A leak is a *slope*, not a
value — take the same measurement at t=0, t=30 min and t=2 h of realistic use, and compare. A
single reading cannot distinguish "this app needs 300 MB" from "this app leaks".

**Evidence.** <https://docs.kernel.org/filesystems/proc.html> ·
<https://keith.github.io/xcode-man-pages/footprint.1.html> ·
<https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model>

### 4.3 Leak sources in the Rust layer

**Mechanism** [SRC]. `Manager::manage` puts a value into a `StateManager` that lives for the whole
app; `AppHandle`s are *"deliberately cheap to clone"* and `Arc`-backed. Cheap-to-clone plus
lives-forever is exactly the combination that leaks quietly.

1. **Growing managed `State` collections.** Anything you `manage(Mutex<HashMap<…>>)` and only ever
   insert into. No eviction, no `Drop` before exit. **Symptom: core-process RSS climbing linearly
   with session length**, flat across restarts.
2. **Unbounded channels.** A `tokio::sync::mpsc::unbounded_channel` whose consumer is slower than
   its producer grows without limit. Prefer `channel(N)` and treat `try_send` failure as
   backpressure — the point of a bound is that it makes the overload *visible* instead of turning
   it into RSS. [INFERENCE — standard Tokio semantics; Tauri does not document this.]
3. **Retained `AppHandle`s in long-lived closures.** Each clone keeps the whole `AppManager` graph
   (state, plugins, listeners) alive. Storing a handle *inside* managed state creates a reference
   cycle that never drops.
4. **Rust-side event listeners.** `Listener::listen` *"keeps the event listener registered for the
   entire lifetime of the application."* Registering one per window or per navigation without
   `unlisten(event_id)` accumulates closures forever.
5. **`ChannelDataIpcQueue`** — see §4.3.1, it is the one people cannot guess.
6. **Rust-side `Resource`s.** The JS `Resource` docs are explicit: *"The resource lives in the main
   process… and thus will not be cleaned up automatically except on application exit. If you want to
   clean it up early, call `Resource.close`."*

**Trade-off of fixing (1).** Bounding or evicting a cache costs you cache hits and adds a policy
decision (LRU? TTL? per-window?). Unbounded is genuinely correct for small, closed sets — a
per-window handle map in a three-window app is not a leak. It becomes a leak when the key space is
driven by user activity.

**When to deviate.** A deliberately unbounded structure is fine if you can state its maximum size
from first principles. Write that reasoning in a comment; the next reader cannot distinguish
"unbounded on purpose" from "unbounded by accident".

#### 4.3.1 `ChannelDataIpcQueue` — a real, verifiable, permanent leak

**Mechanism** [SRC], `crates/tauri/src/ipc/channel.rs`. When `Channel::send` gets a payload above
the direct-execute threshold (§5.2), it does not push the bytes to JS. It **stashes them in
Rust-side state and asks the webview to come and fetch them**:

```rust
webview.state::<ChannelDataIpcQueue>().0.lock().unwrap().insert(data_id, body);
webview.eval(/* JS that invokes plugin:__TAURI_CHANNEL__|fetch with header Tauri-Channel-Id */)
```

The internal `fetch` command is the **only** code path that `remove(&id)`s that entry. So if the
webview navigates, reloads, or the page closes between the `insert` and the JS-side reverse fetch,
the buffered payload stays in the `HashMap<u32, InvokeResponseBody>` **for the lifetime of the
process**. There is no timeout, no eviction, no drop-on-navigate.

**Symptom, stated the way a user reports it.** *"I streamed a 200 MB file, hit reload / navigated
away mid-download, and the app's memory never came back down — and it never comes back down, even
after the transfer is retried and completes."* Core-process RSS, not webview RSS (§4.2 tells you
which). Reproduces exactly once per interrupted stream and is additive.

**Why the design is like this.** The reverse fetch exists because a large payload inlined into a JS
source string is pathologically slow to parse (§5.2). Handing the webview an ID and letting it pull
the bytes over the custom protocol is the right transport. The queue is the buffer between the two
halves, and nothing else in the system knows whether the webview still intends to fetch.

**Mitigations, with their costs.**
- Chunk large transfers so that no single stashed payload is huge (64 KiB chunks — §5.4). An
  orphaned 64 KiB entry is a rounding error; an orphaned 200 MB one is a bug report. **Cost: more
  round trips**, which for a raw channel above 1024 bytes is the same transport per chunk anyway,
  so this is close to free.
- Cancel Rust-side work on navigation. Dropping the Rust `Channel` sends `{ end: true }` and stops
  producing new payloads. **Cost: you need a cancellation token threaded through the producer.**
- Do not stream files through IPC at all when the frontend only needs to *display* them — the
  official recommendation is `convertFileSrc` and the asset protocol (§5.3), which never touches
  this queue.

**When to deviate.** Long-lived streaming of a large payload to a page that never navigates (a
single-window kiosk app) does not hit this. An app with an SPA router and downloads does, routinely.

**Evidence.** `crates/tauri/src/ipc/channel.rs` · <https://v2.tauri.app/develop/calling-frontend/>

### 4.4 JS listeners that are never unlistened

**Mechanism** [SRC]. `listen()` returns a **Promise** of the unlisten function. The official
pitfalls section says two things that are each a bug in the wild:

- *"Don't call `unlisten()` before the listener resolves"* — calling it synchronously calls a
  Promise, not a function, and the listener is never removed.
- *"When the page is reloaded or you navigate to another URL the listeners are unregistered
  automatically. **This does not apply to a Single Page Application (SPA) router though.**"*

```ts
// React — the shape that actually cleans up
useEffect(() => {
  const p = listen<number>('download-progress', (e) => setProgress(e.payload));
  return () => { p.then((un) => un()); };
}, []);
```

**Symptom.** *"The handler fires 7 times and makes 7 duplicate network calls, and there is no error
anywhere."* Seven is how many times the user visited that route. This presents as a *correctness*
bug (duplicate requests, duplicated state updates) long before it presents as a memory bug, which is
why it is worth pattern-matching on the multiplier.

**Trade-off.** None — this is not an optimization, it is a correctness fix. The only cost is
remembering that `listen` is async.

**When to deviate.** A listener registered once at app scope, in a module that is never unmounted,
legitimately never unlistens. Register those outside component lifecycles so the distinction is
visible in the code.

### 4.5 WebView background throttling

**Mechanism** [SRC]. `WindowConfig::background_throttling: Option<BackgroundThrottlingPolicy>` with
variants `Disabled`, `Suspend`, `Throttle`. From the source doc comment: *"By default, browsers use
a suspend policy that will throttle timers and even unload the whole tab (view) to free resources
after roughly 5 minutes when a view became minimized or hidden. This will pause all tasks until the
document's visibility state changes back from hidden to visible."*

Platform support, verbatim: **Linux / Windows / Android: Unsupported** (*"Workarounds like a pending
WebLock transaction might suffice"*); **iOS 17.0+**; **macOS 14.0+**.

```json
{ "label": "main", "backgroundThrottling": "disabled" }
```

**Why the default exists.** Unloading a hidden view is the platform reclaiming a renderer's memory
— on the memory axis it is a *feature*, and it is why a minimized Tauri window can cost near zero.

**Trade-off of `disabled`.** You keep timers and long-lived state alive when hidden — necessary for
a tray app holding a websocket — and in exchange you forfeit the OS's memory reclamation and burn
battery in the background. It is a straight memory/battery-for-liveness trade, and for a
background-first app it is the wrong default in both directions depending on the app.

**Symptoms.**
- *"My tray app's UI state is gone when I reopen it, and no code changed."* The ~5-minute unload.
  Either set `disabled` or — better — persist the state in Rust so the view can be rebuilt cheaply.
  Persisting is strictly better because it also survives a crash and a restart.
- *"Works on my Mac; on the Windows build the timers still die when hidden."* `backgroundThrottling`
  is a no-op on Windows and Linux. There is no cross-platform config answer; the portable fix is to
  move the timer into Rust.
- wry exposes a `MemoryUsageLevel` type on the WebView2 backend (Chromium's memory-target/suspend
  API) which Tauri does not re-export; reaching it means `with_webview`. [INFERENCE —
  `MemoryUsageLevel` is imported in `wry/src/webview2/mod.rs`; I did not verify a Tauri-level
  wrapper exists.]

**Evidence.** `tauri-utils/src/config.rs` L1856-1864, L2224-2239 ·
<https://v2.tauri.app/develop/state-management/>

---

## 5. IPC performance

The IPC *mechanism* — command signatures, `State`, events, channels, the ACL path — is
`references/ipc-and-commands.md`. This section is only the **cost model**: what a byte crossing the
bridge costs and which transport to pick.

### 5.1 The wire protocol, and where the cost actually is

**Mechanism** [SRC], `crates/tauri/src/ipc/protocol.rs`. The primary transport is a
**custom-protocol `POST`** (v1 used `postMessage` — §9). Request headers `Tauri-Callback`,
`Tauri-Error`, `Tauri-Invoke-Key`; `OPTIONS` handled for preflight; anything other than
`POST`/`OPTIONS` → `405`. Response carries `Tauri-Response: ok | error` and
`Access-Control-Expose-Headers: Tauri-Response`. Content type is **`application/json`** for
`InvokeResponseBody::Json` and **`application/octet-stream`** for `InvokeResponseBody::Raw`. A
`postMessage` fallback survives (`kind = "post-message"`, gated on a `customProtocolIpcBlocked`
request option).

The cost centre is one blanket impl:

```rust
// crates/tauri/src/ipc/mod.rs
impl<T: Serialize> IpcResponse for T {
  fn body(self) -> crate::Result<InvokeResponseBody> {
    serde_json::to_string(&self).map(Into::into).map_err(Into::into)
  }
}
```

**Every** serializable return value is rendered into a full `String` in memory, handed to the
webview as UTF-8 bytes, and `JSON.parse`d by the JS engine. **There is no streaming and no borrow**
— for a 64 MB result you allocate a 64 MB string in Rust, copy it across, and allocate the parsed
graph in JS.

**Why.** Official rationale: *"Because this mechanism uses a JSON-RPC like protocol under the hood
to serialize requests and responses, all arguments and return data must be serializable to JSON."*
Maintainer framing in discussion #5690: *"parameters and return values are serialized around
strings. This is the restriction from webview libraries on different platforms."* It is a
portability constraint across three engines, not an oversight.

**Trade-off.** You get one uniform, debuggable, three-platform transport where every payload is
inspectable. You pay full serialization on every call and you cannot opt into zero-copy — and per a
maintainer, *"Only the windows webview supports shared memory but webview2 users reported that it's
weirdly slow"* [COMMUNITY], so a zero-copy path is not coming soon.

### 5.2 The two thresholds, and the rule they imply

**Mechanism** [SRC], `crates/tauri/src/ipc/channel.rs`. A `Channel` serializes to JS as the string
`__CHANNEL__:<id>`. On `send`, it selects one of two transports using **hardcoded, measured**
constants — the comments beside them are the most authoritative payload-size guidance that exists
anywhere in the project:

```rust
/// Maximum size a JSON we should send directly without going through the fetch process
// 8192 byte JSON payload runs roughly 2x faster through eval than through fetch on WebView2 v135
const MAX_JSON_DIRECT_EXECUTE_THRESHOLD: usize = 8192;
// 1024 byte payload runs  roughly 30% faster through eval than through fetch on macOS
const MAX_RAW_DIRECT_EXECUTE_THRESHOLD: usize = 1024;
```

- JSON payload **< 8192 bytes** → inlined into a JS source string, delivered via `webview.eval`.
- Raw payload **< 1024 bytes** → `new Uint8Array([…]).buffer` inlined via `eval`. Note the bytes
  still cross as a **JSON number array** on this path.
- Otherwise → stashed in `ChannelDataIpcQueue` (§4.3.1) and pulled back by a **reverse fetch**:
  `invoke('plugin:__TAURI_CHANNEL__|fetch', null, { headers: { 'Tauri-Channel-Id': id } })`.

Ordering is explicit: Rust attaches a monotonic `index` to every message; the JS `Channel` buffers
out-of-order arrivals in `#pendingMessages` and replays them in order. Dropping the Rust `Channel`
sends `{ end: true, index }`.

**Why two different constants.** `eval` has low fixed overhead but forces the JS engine to *parse
source*, so its cost scales badly with size. `fetch` has higher fixed overhead but a binary body
that needs no parsing. The crossover is engine- and encoding-dependent, so WebView2-with-JSON and
WebKit-with-raw land in different places. That is also why the two numbers differ by 8×.

**The rule these imply, and it is the practical takeaway of this whole section.** Combine the
thresholds with the community cost attribution (§5.5 — *"At small payloads (25B), WebView transport
overhead is 54% of total cost… At 1 KB, JSON serialization is 82% of cost and transport is only
6%"*):

> **Below ~1 KB you are paying for the bridge — so reduce the number of calls.
> Above ~1 KB you are paying for JSON — so go binary.**

Two different regimes, two different fixes, and applying the wrong one produces no improvement. A
batching refactor on 64 KB payloads buys you nothing because you were paying for serialization. A
switch to binary on 200-byte messages buys you nothing because you were paying for the round trip.

**Trade-off of chasing the thresholds.** Tuning chunk size to sit under 8192/1024 is real, free
performance — but it is a constant in Tauri's source, not a public API. It can move. Do not build an
architecture that only works at exactly 8 KiB; pick chunk sizes with margin (4 KiB JSON, 64 KiB
raw) and re-measure on a version bump.

### 5.3 Escaping JSON: raw responses, raw requests, and not using IPC at all

**Mechanism** [SRC]. Rust → JS with `tauri::ipc::Response`:

```rust
use tauri::ipc::Response;

#[tauri::command]
fn read_file(path: std::path::PathBuf) -> Result<Response, String> {
    let data = std::fs::read(path).map_err(|e| e.to_string())?;   // validate `path` first — security.md
    Ok(Response::new(data))     // -> InvokeResponseBody::Raw, application/octet-stream
}
```

```ts
const buf = await invoke<ArrayBuffer>('read_file', { path });
```

Official note: *"This can slow down your application if you try to return a large data such as a
file or a download HTTP response. To return array buffers in an optimized way, use
`tauri::ipc::Response`."*

JS → Rust: `InvokeArgs` is `Record<string, unknown> | number[] | ArrayBuffer | Uint8Array`, and

```rust
use tauri::ipc::{InvokeBody, Request};

#[tauri::command]
fn upload(request: Request<'_>) -> Result<usize, String> {
    match request.body() {
        InvokeBody::Raw(bytes) => Ok(bytes.len()),      // zero JSON
        InvokeBody::Json(_)    => Err("expected raw body".into()),
    }
}
```

**Trade-off, and it is the real one.** You lose typed arguments and serde's deserialization. You now
hand-frame anything structured — the official suggestion is *"use your own (de)serialization process
(eg. bson, protobuf, avro and others)"*, which means you have adopted a schema format and its
tooling. For one hot path carrying megabytes that is obviously worth it. For a command returning a
3 KB struct it is a maintenance cost with no measurable return.

**Symptoms / gotchas.**
- *"Raw bodies work on desktop and my Android build gets JSON."* **`InvokeBody::Raw` does not exist
  on Android.** Source doc: *"On Android, `InvokeBody::Raw` is not supported. The enum will always
  contain `InvokeBody::Json`. When targeting Android Devices, consider passing raw bytes as a base64
  `String`, which is still more efficient than passing them as a number array in
  `InvokeBody::Json`."* A number array is ~4× the bytes; base64 is ~1.37×.
- *"I optimized the file-read command and it is still slow."* For "read a file and show it", the
  official recommendation is **not IPC at all**: *"For directly reading files from the filesystem
  into the WebView we still recommend the `convertFileSrc` functionality, as it is most likely still
  faster if you do not need to process the data on the Rust backend."* The fastest IPC call is the
  one you deleted.

**Events, priced.** [SRC] `crates/tauri/src/event/mod.rs` builds
`format!("(function () {{ const fn = window['{}']; fn && fn({{event: '{}', payload: {}}}, {ids}) }})()", …)`
and `webview.eval`s it. An event with an N-byte payload becomes an ~N-byte **JavaScript source
string the engine must parse**. Official: *"Under the hood it directly evaluates JavaScript code so
it might not be suitable to sending a large amount of data"*, and *"event payloads are always JSON
strings making them not suitable for bigger messages, and there is no support of the capabilities
system to fine grain control event data."* Also: global `emit` reaches **every** listener in every
webview, so in a multi-window app you re-parse the payload once per webview — use `emit_to(label, …)`
or `emit_filter(…)`. *Symptom: "my `emit_to` vanished"* — webview-specific events *"are **not**
triggered to regular global event listeners"*; you need `listen_any`. And async listeners can
process rapid-fire events **out of order**; the docs' own advice is *"For ordered, high-throughput
data delivery, consider using Channels instead."*

### 5.4 The `Channel<&[u8]>` trap — the official example does not stream binary

This has its own subsection because it is in the **official documentation**, it looks exactly right,
and it is wrong.

**Mechanism** [SRC]. `Channel::send(data: TSend) where TSend: IpcResponse`. `&[u8]` is `Serialize`,
so it hits the blanket `impl<T: Serialize> IpcResponse` from §5.1 → `serde_json::to_string` → **a
JSON number array**. `[104,101,108,108,111,…]`. That is roughly **4× inflation** (1–3 digits plus a
comma per byte), so a 4096-byte chunk becomes ~12–16 KB of JSON text — which **instantly exceeds
`MAX_JSON_DIRECT_EXECUTE_THRESHOLD` (8192)**, falls off the fast `eval` path onto the reverse-fetch
path, and then makes the JS engine parse a 16 KB numeric array literal to reconstruct bytes it could
have received directly.

**Wrong — this is the shape people copy:**

```rust
// DOES NOT STREAM BINARY. Serializes to a JSON number array, ~4x inflation.
#[tauri::command]
async fn load_image(path: PathBuf, on_chunk: Channel<&[u8]>) -> Result<(), String> { /* … */ }
```

**Right:**

```rust
use tauri::ipc::{Channel, Response};
use tokio::io::AsyncReadExt;

#[tauri::command]
async fn load_image(path: std::path::PathBuf, on_chunk: Channel<Response>) -> Result<(), String> {
    let mut file = tokio::fs::File::open(path).await.map_err(|e| e.to_string())?;
    let mut chunk = vec![0u8; 64 * 1024];          // > 1024 -> deliberately the binary fetch path
    loop {
        let len = file.read(&mut chunk).await.map_err(|e| e.to_string())?;
        if len == 0 { break; }
        on_chunk.send(Response::new(chunk[..len].to_vec())).map_err(|e| e.to_string())?;
    }
    Ok(())
}
```

```ts
import { Channel, invoke } from '@tauri-apps/api/core';

const ch = new Channel<ArrayBuffer>();
ch.onmessage = (buf) => sink.write(new Uint8Array(buf));
await invoke('load_image', { path, onChunk: ch });
```

**Why the type system does not catch this.** `IpcResponse` has a blanket impl over all `Serialize`,
so `Channel<&[u8]>` compiles, runs, and produces correct output. The only observable difference is
throughput. There is no warning, no deprecation, no lint.

**Symptom.** *"I moved a large transfer from one big `invoke` to a `Channel` for progress reporting
and it got **slower**."* That is the signature. Check the channel's type parameter first.

**Trade-off of the correct form.** `Channel<Response>` gives up structured messages — you can no
longer send `{ chunk, progress, eta }` in one message, because the payload is bytes. Either send
progress on a second, JSON channel (small payloads, stays on `eval`), or frame it into the byte
stream yourself. That is the actual cost of binary streaming and it is why the wrong version is
attractive.

**Chunk sizing, both directions.** A 4096-byte *JSON* chunk stays on the fast `eval` path (< 8192).
A 512-byte *raw* chunk also stays on `eval` but pays the number-array inflation on the way. Pick
chunk sizes deliberately around **1 KiB (raw)** and **8 KiB (JSON)**, and remember §4.3.1: large
stashed chunks are exactly what leaks when the page navigates mid-stream.

**When to deviate.** If your chunks are genuinely small structured records (log lines, progress
ticks), `Channel<T: Serialize>` under 8 KiB is the right choice and going binary is over-engineering.

### 5.5 Chatty `invoke` is the number one mistake

**Mechanism.** Each `invoke` is a full round trip: JS `JSON.stringify` → custom-protocol POST → Rust
deserialize (`serde_json` into `Value`, then into `T`) → handler → `serde_json::to_string` →
response → JS `JSON.parse`. There is a **per-call floor independent of payload size**. On the
community end-to-end measurement below that floor is ~300 µs on Apple Silicon — and it is *clamped
by WebKit's 1 ms `performance.now()` resolution*, so the true floor may be lower while the
observable floor is not.

**The arithmetic that settles the argument.** N per-item invokes cost `N × floor + Σ payload`. One
batched invoke costs `1 × floor + Σ payload`. At a ~300 µs floor, 1000 per-row invokes is ~0.3 s of
pure overhead before any work happens, and the payload sum is identical. **Batch. Return one array,
take one array.**

**Transport decision table.** This is a genuine matrix, which is why it is a table:

| Payload / pattern | Do this | What it costs you |
| --- | --- | --- |
| Any N > ~10 similar calls | Batch into one command | Coarser error granularity — one failure fails the batch unless you return per-item results |
| < ~1 KB, structured | Plain `#[tauri::command]` + serde | Nothing. JSON overhead is noise against the transport floor |
| 1 KB – 8 KB, streaming | `Channel<T: Serialize>` — stays on the `eval` fast path | Nothing beyond channel plumbing |
| > 8 KB JSON / > 1 KB raw, streaming | `Channel<Response>` — binary reverse-fetch (§5.4) | Structured metadata must move to a second channel |
| Large one-shot blob | `tauri::ipc::Response::new(bytes)` | Typed return; you hand-frame structure |
| Large blob Rust never touches | Don't use IPC — `convertFileSrc` + asset protocol | An asset-protocol scope you must get right (`security.md`) |
| Progress / lifecycle notifications | Events, small payloads only | No ordering guarantee; no ACL over payloads |
| Android + binary | base64 `String` | ~1.37× inflation — still 3× better than a number array |

**Community measurements** [COMMUNITY] — both must travel with their caveats:

1. Tauri maintainer **FabianLars**, discussion #11915, binary IPC for **10 MB**: *"~5ms on macOS but
   ~200ms on Windows (that 100% used to be better so idk what's going on there)"* — explicitly
   *"non-scientific"*. Useful as a warning that the platforms differ by ~40×, not as a number to
   plan against.
2. `tauri-conduit` BENCHMARKS.md (v2.1.0, 2026-03-17). **Authored by a competing IPC library, so
   the framing is self-interested — but methodology and environment are disclosed and
   reproducible.** Rust-side dispatch only (Linux, i7-10700KF, release, Criterion 0.5): 25 B
   **721.70 ns**, ~1 KB **8.077 µs**, 64 KB **2.272 ms**. End-to-end through the webview (macOS
   aarch64, `cargo tauri build`, 1000 iterations), Tauri median: 25 B **300 µs**, ~1 KB **400 µs**,
   64 KB **6.700 ms** — their own note: *"Small and medium payload timings are clamped by WebKit's
   1ms `performance.now()` resolution… The 64KB results are stable and representative."* Their cost
   attribution is the part worth keeping: *"At small payloads (25B), WebView transport overhead is
   54% of total cost… At 1 KB, JSON serialization is 82% of cost and transport is only 6%."*

**When to deviate from batching.** Interactive, latency-sensitive, genuinely singular calls — a
keystroke-driven autocomplete — should stay one call each; batching them adds latency. The rule is
about *loops*, not about call count in the abstract.

**Evidence.** `crates/tauri/src/ipc/protocol.rs` · `crates/tauri/src/ipc/mod.rs` ·
`crates/tauri/src/ipc/channel.rs` · `crates/tauri/src/event/mod.rs` · `packages/api/src/core.ts` ·
<https://v2.tauri.app/concept/inter-process-communication/> · <https://v2.tauri.app/develop/calling-rust/> ·
<https://v2.tauri.app/develop/calling-frontend/> · <https://github.com/tauri-apps/tauri/discussions/11915> ·
<https://github.com/tauri-apps/tauri/discussions/5690> ·
<https://github.com/userFRM/tauri-conduit/blob/master/BENCHMARKS.md>

---

## 6. Rendering

### 6.1 The webview is the renderer

**Mechanism** [SRC]. *"The Core process doesn't render the actual user interface itself; it spins up
WebView processes that leverage WebView libraries provided by the operating system… This means that
most of your techniques and tools used in traditional web development can be used."*

**The only thing this section needs to say about web performance:** every ordinary web-perf rule
applies unchanged and is the *first* thing to check — layout thrash, unbatched style reads/writes,
oversized images, non-virtualized long lists, `filter`/`backdrop-filter` over large repainting
areas, layers that cannot be promoted. There is no Tauri-specific rendering pipeline to tune. **If a
Tauri UI is janky it is a web perf problem approximately always, and the Rust side is innocent.**
`clouds-f` is the authority for the renderer-side work; this file does not restate it.

What *is* Tauri-specific is below: three engines at three version floors, and one window-level
setting with a measured GPU cost.

### 6.2 GPU acceleration differs per platform, and Linux lies about it

**Mechanism** [SRC]. Windows/WebView2 — Chromium's GPU process, part of the process group,
self-updating, so a recent Chromium is guaranteed and preinstalled on Windows 11. macOS/WKWebView —
`com.apple.WebKit.GPU`, version pinned to the OS; unsupported macOS versions *"do **not** receive
WebKit updates."* Linux/WebKitGTK — a DMABUF-based accelerated path plus accelerated compositing,
both pinned to the distro package, and both of which can and do fail.

**The Linux problem is that the failure is silent.** Two facts from the official Linux Graphics page:

- *"WebGL2 context creation succeeds even when the result is backed by a software rasterizer or a
  slow presentation path. There is no error to catch."*
- *"WebKitGTK masks the WebGL renderer string for fingerprinting protection. `WEBGL_debug_renderer_info`
  reports `Apple GPU` on every Linux machine, so you cannot check what is actually behind the
  context."*

**Consequence: you cannot feature-detect GPU acceleration on Linux.** Official guidance: *"If your
app has a WebGL rendering path, give it a non WebGL fallback on Linux and consider exposing a setting
so users can switch, instead of trusting the context to tell you."*

**Symptom.** *"High input latency and low FPS in the terminal / editor / map / chart on Linux, with
the same code fast in a browser on the same machine."* The context was created, nothing errored, and
it is running on llvmpipe.

**Trade-off.** Shipping a non-WebGL fallback means maintaining two render paths for one platform.
The alternative is a subset of Linux users on a product that appears broken and gives you no
telemetry to find them. Exposing it as a user setting is the cheap middle.

**Correctness failures on Linux — blank window, flicker on resize, `AcceleratedSurfaceDMABuf was
unable to construct a complete framebuffer`, `Gdk-Message: Error 71 (Protocol error)` — and the
ordered workaround ladder (`nvidia_drm.modeset=1` → `__NV_DISABLE_EXPLICIT_SYNC=1` →
`WEBKIT_DISABLE_DMABUF_RENDERER=1` → `WEBKIT_DISABLE_COMPOSITING_MODE=1`) are
`references/cross-platform.md`'s §Linux, with a shipped example in `case-studies.md` §8.** The one
performance point to carry here: each rung down that ladder **disables a faster path for every
user**, so an unconditional override to fix a minority NVIDIA bug is a global regression. Gate it or
expose it.

**Evidence.** <https://v2.tauri.app/develop/debug/linux-graphics/> ·
<https://v2.tauri.app/reference/webview-versions/> · <https://v2.tauri.app/concept/process-model/>

### 6.3 `transparent: true` costs ~8× GPU power on macOS

**Mechanism** [SRC]. `WindowConfig::transparent: bool`, default `false`. On macOS it *"requires the
`macos-private-api` feature flag, enabled under `tauri > macOSPrivateApi`"* — and *"Using private
APIs on macOS prevents your application from being accepted to the App Store."*

**Measured cost** [SRC — tauri#15471, still open, labelled `status: upstream`]. A controlled A/B on
the same app with a **fully static** page (no `requestAnimationFrame`, no CSS animation, no DOM
mutation), measured with `sudo powermetrics --samplers gpu_power` on an M5 Pro / 120 Hz ProMotion,
Tauri 2.11.2 / wry 0.55.1 / tao 0.35.3:

| Window background | GPU power | GPU HW active residency |
| --- | --- | --- |
| `transparent: true` | **~620 mW** | **~36 %** |
| `transparent: false`, same page | ~75 mW | ~10 % |
| Safari blank `data:` page (control) | ~75 mW | ~10 % |

**≈8× GPU power for a page that is doing nothing.** Occluding the window drops the load to ~0,
which is what proves the cost is per-frame **window** compositing rather than page work. On an Intel
MacBook Pro the same mechanism pinned `com.apple.WebKit.GPU` at **1380 % CPU** while the app's main
process sat at ~8 % — note *which* process, or you will conclude your Rust code is fine and stop
looking.

**Diagnostic warning from the same report, and it matters more than the number.** *"`ioreg -r -d 1
-c IOAccelerator` → `Device Utilization %` is **misleading** here: it reports ~30 % for *any*
foreground WKWebView, including a blank Safari tab. Only `powermetrics` GPU Power (mW) + HW active
residency… reflect real load."* So the tool most people reach for will show ~30 % in both arms of the
A/B and tell you there is no difference. **Use `sudo powermetrics --samplers gpu_power`** (§8.4).

**Symptom.** *"The fan spins and the battery drains while the app just sits there idle on macOS."*
Static page, no animation, nothing in the JS profile. Check `transparent`.

**Trade-off.** If nothing actually shows through the window, `transparent: true` is pure cost —
you are paying for per-frame compositing of a fully opaque surface. On a 120 Hz ProMotion display
that is 120 wasted composites per second. Reach for `backgroundColor` (§2.4) plus
`decorations: false` instead; enable transparency only when you genuinely composite against the
desktop (a translucent sidebar, vibrancy, a non-rectangular window).

**When to deviate.** A visually translucent design *is* a legitimate product decision — both apps in
`case-studies.md` §4 ship transparency, and its per-platform config matrix (including why Jan turns
it off on Linux) lives there. If you make that call, make it knowing it costs ~8× idle GPU on macOS,
and consider disabling it on battery or when the window is not the active one.

**Related, and cheaper than people think.** `decorations: false` (default `true`) with
`shadow: bool` (default `true`): on Windows *"`false` has no effect on decorated window, shadow are
always ON. `true` will make undecorated window have a 1px white border, and on Windows 11, it will
have a rounded corners."* Shadow is unsupported on Linux. The v2 changelog records a real win here:
*"On Windows, handle resizing undecorated windows natively which improves performance and fixes a
couple of annoyances with previous JS implementation: No more cursor flickering when moving the
cursor across an edge."* Titlebar/UX design is `references/desktop-ux.md`.

**Evidence.** <https://github.com/tauri-apps/tauri/issues/15471> · `tauri-utils/src/config.rs`
L2040-2061, L2123-2135 · <https://v2.tauri.app/blog/tauri-20/>

### 6.4 Vsync and frame pacing: there is no knob

**Mechanism.** Frame pacing is entirely the platform compositor's and the webview's job. There is
**no** vsync, frame-limiter or presentation-interval setting anywhere in `WindowConfig` or on the
`WebviewWindow` / `Webview` API surface. [Verified absence across `tauri-utils::config::WindowConfig`
and the docs.rs method lists for `WebviewWindow` and `Webview`, tauri 2.11.5.]

**Consequence.** Your only frame-rate levers are web-platform ones: `requestAnimationFrame`
scheduling, avoiding always-animating layers, `content-visibility`, throttling your own render loop.
**The optimization is not "render fewer frames", it is "stop needing recomposites at all"** — which
is why §6.3 is a rendering-performance issue and not a styling one.

**When to deviate.** If you truly need frame-rate control (a game, a visualizer), you need it inside
the page, and you accept that the compositor above you is not under your control on any of the three
platforms.

---

## 7. Async & concurrency — the cost model

The threading *mechanism* — which command forms run where, `State` lifetimes, the borrowed-argument
limitation, `std::sync::Mutex` vs `tokio::sync::Mutex` — is `references/ipc-and-commands.md`. This
section is only what those choices cost at runtime.

### 7.1 Blocking the main thread is a whole-app outage

**Mechanism** [SRC]. Docs, verbatim: *"Async commands are executed on a separate async task using
`async_runtime::spawn`. **Commands without the `async` keyword are executed on the main thread unless
defined with `#[tauri::command(async)]`.**"* The main thread runs the tao event loop — window
messages, input, and the dispatch of `run_on_main_thread` closures. `App::run` records the main
thread id precisely because some operations must be marshalled back to it.

**Why the failure is disproportionate.** Blocking a worker thread slows one operation. Blocking the
main thread stops the OS delivering events to **every window**, including windows that have nothing
to do with the work, and after a few seconds the OS marks the app "not responding" and offers to kill
it. A 900 ms sync command is not "a 900 ms command", it is a 900 ms freeze of the entire product.
[INFERENCE — the event-loop-on-main-thread model is standard for tao/winit and is implied by
`run_on_main_thread` existing; Tauri does not spell out the freeze mechanism.]

**Symptom.** *"The whole UI freezes for N seconds during one operation, including other windows and
the tray menu."* Sync command doing IO or CPU work. This is the single most common "Tauri is slow"
report and it is never Tauri.

**Cost of the fix.** Making a command async is not free: you pay a task spawn and you lose the
ability to take borrowed arguments (`&str`, `State<'_, T>` without a `Result` return). For a command
that reads an in-memory counter and returns an integer, the spawn costs more than the work — leave
those sync. The rule is about *unbounded* work, not about all work.

### 7.2 Sizing the pools, and how to starve the runtime

**Mechanism** [SRC]. `tauri::async_runtime` is *"The singleton async runtime used by Tauri and
exposed to users"*, backed by tokio with features `["rt", "rt-multi-thread", "sync", "fs",
"io-util"]`. Its surface is `set(TokioHandle)`, `handle()`, `block_on`, `spawn`, `spawn_blocking`
(verified on docs.rs for 2.11.5).

Two pools with very different sizes and purposes:

- The **worker pool** runs async tasks. Multi-threaded scheduler, worker count defaults to the
  core count. Every `async fn` command lands here.
- The **blocking pool** runs `spawn_blocking` closures. Tokio's `max_blocking_threads` default is
  **512** [SRC, `tokio/src/runtime/builder.rs`], threads are spawned on demand and reaped after an
  idle timeout.

**The starvation failure, symptom-first.** *"Everything gets slow — unrelated commands, event
delivery, the lot — as soon as a few uploads/hashes are in flight, and it clears when they finish."*
You put blocking work (a synchronous `std::fs::read`, a CPU-bound hash, a blocking DB driver) inside
an `async fn`. Each such call occupies a worker thread for its whole duration; N concurrent ones
where N ≥ worker count leaves zero threads to poll anything else. The official splashscreen lab
states the same trap for the sleep case: *"they run cooperatively in a concurrent environment not in
parallel, meaning that if you sleep the thread instead of the Tokio task you'll be locking all tasks
scheduled to run on that thread from being executed, causing your app to freeze."*

```rust
// CPU-bound and blocking IO: off the main thread AND off the async workers
#[tauri::command]
async fn hash_file(path: std::path::PathBuf) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
        Ok::<_, String>(blake3_hex(&bytes))
    })
    .await
    .map_err(|e| e.to_string())?          // JoinError
}
```

**Cost of `spawn_blocking`, which people forget it has.** It is not free parallelism. Each call may
spawn an OS thread (up to 512), and 512 concurrent 200 MB file reads is 100 GB of resident memory
and a machine that swaps to death. **The blocking pool is a concurrency limit, not a concurrency
plan** — it is sized to be effectively unbounded. If a command can be invoked in a loop from the
frontend, put your own semaphore in front of the work (`tokio::sync::Semaphore` with a bound you
chose) rather than trusting the pool cap. That bound is also what makes the system's behaviour under
overload *predictable* instead of merely survivable.

**Command concurrency semantics** [SRC + INFERENCE]. Sync commands run inline on the main thread, so
they serialize against each other and against the event loop. Async commands are each `spawn`ed onto
the multi-threaded runtime, so **they run concurrently and complete out of order** — nothing
preserves `invoke` ordering across separate calls. [INFERENCE from `async_runtime::spawn` +
`rt-multi-thread`.] Ordering exists only *within* a `Channel`, which carries an explicit index and a
JS-side reorder buffer (§5.2). *Symptom: "two rapid invokes applied in the wrong order and corrupted
my state."* Sequence them in the frontend, or give the operation an ordering key in Rust; the runtime
will not do it for you.

**When to deviate on pool sizing.** If you need a specific worker count, a named thread pool, or
runtime metrics, build your own tokio runtime and hand its handle to `async_runtime::set` **before**
`Builder::run`. [INFERENCE — `set(TokioHandle)` is the documented injection point; Tauri does not
document pool tuning as a use case.] Cost: you now own runtime configuration for Tauri's internals
too, including plugin `initialize` and `setup` hooks.

**Evidence.** <https://docs.rs/tauri/2.11.5/tauri/async_runtime/index.html> ·
<https://v2.tauri.app/develop/calling-rust/> · <https://v2.tauri.app/learn/splashscreen/> ·
<https://raw.githubusercontent.com/tokio-rs/tokio/master/tokio/src/runtime/builder.rs> ·
`crates/tauri/src/app.rs` L1372-1373 · `crates/tauri/Cargo.toml`

---

## 8. Profiling — commands that produce a number

### 8.1 `tracing`: Tauri already instruments itself

**Mechanism** [SRC]. The `tracing` feature is **off by default**:
`tracing = ["dep:tracing", "tauri-macros/tracing", "tauri-runtime-wry?/tracing"]`. Turn it on and
the framework's own spans start emitting. Verified span names and what each one isolates:

| Span | File | What it isolates |
| --- | --- | --- |
| `app::build` | `app.rs` | Whole `Builder::build` |
| `app::setup` | `app.rs` | Window creation + your `setup` hook |
| `app::core_plugins::register` | `app.rs` | The 9 built-in plugins |
| `app::plugin::register` (field `name`) | `app.rs` | **Per-plugin init cost** |
| `ipc::request` (fields `kind`, `request`) | `ipc/protocol.rs` | `kind = "custom-protocol"` vs `"post-message"` |
| `ipc::request::deserialize` | `ipc/protocol.rs` | Argument parsing |
| `ipc::request::decrypt_isolation_payload` | `ipc/protocol.rs` | Isolation-pattern crypto cost (§3.5) |
| `ipc::request::handle` (field `cmd`) | `ipc/protocol.rs` | **Per-command handler time** |
| `ipc::request::respond` / `::response` (fields `response`, `mime_type`) | `ipc/protocol.rs` | Serialization + the JSON-vs-octet-stream decision (§5.1) |
| `window::emit::serialize` / `window::emit::json` | `event/mod.rs` | Event payload serialization |

```toml
# src-tauri/Cargo.toml
[dependencies]
tauri = { version = "2", features = ["tracing"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "fmt"] }
```

```rust
fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tauri=trace".into()),
        )
        .with_span_events(tracing_subscriber::fmt::format::FmtSpan::CLOSE) // prints span durations
        .init();
    app_lib::run();
}
```

```bash
# macOS / Linux
RUST_LOG=tauri=trace npm run tauri dev
# Windows PowerShell
$env:RUST_LOG='tauri=trace'; npm run tauri dev
```

**Why `FmtSpan::CLOSE` is the whole trick.** It prints each span's *elapsed time*, which turns a
logger into a profiler. `app::plugin::register{name="…"}` directly answers "which plugin is costing
me 200 ms of startup" — the question §2.1 says you must answer before touching anything.

**Trade-offs.** The `ipc::request` spans record the **full request and response bodies** as span
fields. Excellent for debugging, terrible for both overhead and secrecy. Keep `tracing` a dev-only
feature; never ship it enabled on a build that handles credentials, and remember from §3.5 that
feature unification can enable it behind your back.

**When to deviate.** Ship `tracing` in release only with a filter that excludes `ipc::request`, and
only if you have a real need for production spans.

### 8.2 CrabNebula DevTools — the same spans with a UI

**Mechanism** [SRC]. `cargo add tauri-plugin-devtools@2.0.0`, then initialize it **as early in
execution as possible**:

```rust
fn main() {
    #[cfg(debug_assertions)]
    let devtools = tauri_plugin_devtools::init();

    let mut builder = tauri::Builder::default();
    #[cfg(debug_assertions)]
    { builder = builder.plugin(devtools); }

    builder.run(tauri::generate_context!()).expect("error while running tauri application");
}
```

It *"allows you to instrument your Tauri app by capturing its embedded assets, Tauri configuration
file, logs and spans… track down the performance of your command calls and overall Tauri API usage,
with a special interface for Tauri events and commands, including payload, responses and inner logs
and execution spans."*

**Symptom of the one mistake.** *"The profiler shows nothing for startup."* It was initialized after
the thing you wanted to measure. It must be first. Same body-capture privacy caveat as §8.1; the
official recommendation is `#[cfg(debug_assertions)]` only.

**When to deviate.** For a one-off "which plugin is slow" question, §8.1 with `FmtSpan::CLOSE` is
faster to set up and has no extra dependency. Reach for the UI when you are exploring rather than
confirming.

### 8.3 Sampling profilers

**`samply` — the better default for a Tauri app.** Cross-platform, Firefox Profiler UI, and on
**macOS and Windows it collects off-CPU samples**, so you can see where the main thread was *blocked
on a lock* — which is exactly the §7.1 question. On Linux it is on-CPU only (*"On Linux, only
on-cpu samples are collected at the moment"*), which is the one platform where the freeze question is
hardest to answer with it.

```bash
cargo install --locked samply
```

```toml
# Cargo.toml (workspace root — see §3.2) — release codegen with symbols
[profile.profiling]
inherits = "release"
debug = true
```

```bash
cargo tauri build --debug          # or: cargo build --profile profiling
samply record ./src-tauri/target/debug/my-app

# Linux prerequisite:
echo '1' | sudo tee /proc/sys/kernel/perf_event_paranoid
```

Default rate is 1000 Hz. On macOS, system binaries cannot be profiled (`DYLD_INSERT_LIBRARIES` is
blocked); run `samply setup` once to self-sign before attaching to running processes.

**`cargo flamegraph`** — Linux via `perf`, macOS via `xctrace`, Windows natively via `blondie` (or
`dtrace` if installed, which it prefers):

```bash
cargo install flamegraph
cargo flamegraph --bin my-app -o flamegraph.svg
flamegraph --pid <pid> -o live.svg          # attach to a running app
cargo flamegraph --no-inline                # addr2line inlining can take minutes
cargo flamegraph -c "record -e branch-misses -c 100 --call-graph lbr -g"
```

Two footguns straight from its README, both of which produce a *useless output rather than an
error*:
- Release symbols: set `[profile.release] debug = true` or `CARGO_PROFILE_RELEASE_DEBUG=true`, else
  the flamegraph is an unreadable wall of addresses.
- **`lld` is the default linker since Rust 1.90.0**, and *"you must use the `--no-rosegment` flag.
  Otherwise perf will not be able to generate accurate stack traces"*:
  ```toml
  # .cargo/config.toml
  [target.x86_64-unknown-linux-gnu]
  rustflags = ["-Clink-arg=-Wl,--no-rosegment"]
  ```

**Raw `perf` (Linux)** — the way to profile the whole process tree including WebKit helpers, which
neither of the above does well:

```bash
perf record -F 999 -g --call-graph dwarf -- ./src-tauri/target/release/my-app
perf report --sort=dso,symbol
perf stat -e task-clock,cycles,instructions,cache-misses ./my-app
```

**Trade-off across all three.** Sampling profilers need symbols, and symbols contradict
`strip = true` (§3.1) — so you are profiling a build that is not byte-identical to the one you ship.
Use a dedicated `profiling` profile inheriting release, and accept that binary size measurements
must come from the real release artifact.

### 8.4 macOS: Instruments and `powermetrics`

```bash
xcrun xctrace record --template 'Time Profiler' --launch -- ./target/release/my-app
xcrun xctrace record --template 'Allocations' --attach <pid>

sudo powermetrics --samplers gpu_power                 # the §6.3 measurement
sudo powermetrics --samplers cpu_power,gpu_power -i 1000
```

For GPU questions use `powermetrics` **GPU Power (mW) + HW active residency**, never
`ioreg … IOAccelerator` — it reports ~30 % for any foreground WKWebView including a blank Safari tab,
so it cannot distinguish the two arms of the §6.3 A/B.

### 8.5 Choosing the dev gate

`#[cfg(dev)]` / `cfg!(dev)` / `tauri::is_dev()` are true for `tauri dev` **only**.
`#[cfg(debug_assertions)]` is true for `tauri dev` **and** `tauri build --debug`. Profiling code
gated on `dev` will not run in a `--debug` bundle — which is usually the build you actually want to
profile, because it is closest to release. Pick deliberately.

```bash
RUST_BACKTRACE=1 npm run tauri dev            # macOS / Linux
$env:RUST_BACKTRACE=1; npm run tauri dev      # Windows PowerShell
npm run tauri build -- --debug                # devtools + symbols, bundles to src-tauri/target/debug/bundle
```

Webview-side profiling (the inspector, its Performance panel, per-platform devtools differences) is
`references/debugging-and-testing.md`.

**Evidence.** <https://v2.tauri.app/develop/debug/> ·
<https://v2.tauri.app/develop/debug/crabnebula-devtools/> · <https://github.com/mstange/samply> ·
<https://github.com/flamegraph-rs/flamegraph> · `crates/tauri/src/app.rs` ·
`crates/tauri/src/ipc/protocol.rs` · `crates/tauri/src/event/mod.rs` · `crates/tauri/Cargo.toml`

---

## 9. v1 → v2 performance deltas

Agents hit v1-era content constantly, and most of it is confidently wrong now. These are the
perf-relevant breaks, all [SRC] against 2.11.x. Non-performance migration is
`references/architecture.md` §v1→v2 and `references/security.md` (allowlist → capabilities).

| Area | v1 | v2 (2.11.x) |
| --- | --- | --- |
| **IPC transport** | `postMessage`-based | *"Use custom protocols on the IPC implementation to enhance performance."* `POST` + `Tauri-Callback`/`Tauri-Error`/`Tauri-Invoke-Key`, `Tauri-Response` back. `postMessage` survives only as a fallback (§5.1) |
| **Binary payloads** | *"all IPC payloads were json serialized and deserialized which caused an overhead. This was noticeable once more than a few kilobytes were transferred"* | Raw both ways: `tauri::ipc::Response` and `InvokeBody::Raw`/`tauri::ipc::Request`; `InvokeArgs` accepts `ArrayBuffer`/`Uint8Array` (§5.3) |
| **Streaming** | Events only | `tauri::ipc::Channel` + JS `Channel`, ordered, with the measured eval-vs-fetch thresholds (§5.2) |
| **`custom-protocol` Cargo feature** | Required; used as the "is production" signal | *"no longer required on your application and is now ignored. To check if running on production, use `#[cfg(not(dev))]` instead of `#[cfg(feature = "custom-protocol")]`."* |
| **Undecorated window resize (Windows)** | JS implementation | Native: *"improves performance"*, no cursor flicker. **Delete the JS resize handlers you copied from a v1 blog post** (§6.3) |
| **Window centering** | Jumped to centre after becoming visible | *"it will no longer jump to center after being visible."* Delete the `center()`-after-`show()` dance (§2.4) |
| **Windows decorated + transparent** | *"decorated window not transparent initially until resized"* | Fixed — another v1-era workaround to delete |
| **Event API surface** | `window.emit` / `app.emit_all` | `Emitter`: `emit`, `emit_to`, `emit_filter`; `Listener`: `listen`, `listen_any`, `once`, `unlisten`. Webview-specific events no longer reach plain global listeners (§5.3) |
| **Payload shape** | `payload` unpacked/flattened over IPC | *"No longer unpacking and flattening the `payload` over the IPC so that commands with arguments called `cmd`, `callback`, `error`, `options` or `payload` aren't breaking the IPC."* |
| **Unused command stripping** | none | `"build": { "removeUnusedCommands": true }` (§3.4) |
| **Background throttling** | none | `backgroundThrottling: "disabled" \| "suspend" \| "throttle"`, macOS 14+/iOS 17+ only (§4.5) |
| **Global JS API** | `window.__TAURI__` commonly assumed present | `withGlobalTauri` defaults to **false**; `window.__TAURI__.core.invoke` exists only if you opt in |
| **JS import paths** | `@tauri-apps/api/tauri`, `@tauri-apps/api/window` for everything | `invoke`/`Channel`/`convertFileSrc`/`isTauri` from `@tauri-apps/api/core`; `listen`/`once` from `@tauri-apps/api/event`; `getCurrentWebviewWindow` from `@tauri-apps/api/webviewWindow` |

**One stale example in the official docs.** `AppHandle::global_shortcut_manager()` appears in a
`develop/calling-rust` example, but global shortcuts in v2 live in the
`tauri-plugin-global-shortcut` plugin. **[UNVERIFIED — this looks like a v1 carry-over; I did not
find `global_shortcut_manager` on the 2.11.5 `AppHandle` method list on docs.rs. Treat the example as
suspect and reach for the plugin.]** The general lesson is worth more than the specific method: the
v2 docs contain v1 residue, so *"the official docs say so"* is not sufficient evidence for an API
that does not appear on docs.rs for your pinned version.

**Evidence.** <https://v2.tauri.app/blog/tauri-20/> · <https://v2.tauri.app/concept/size/> ·
`crates/tauri/src/ipc/protocol.rs` · `packages/api/src/core.ts` · `tauri-utils/src/config.rs` ·
<https://docs.rs/tauri/2.11.5/tauri/struct.AppHandle.html>

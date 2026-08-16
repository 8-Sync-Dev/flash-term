# Desktop UX — making it an application, not a website in a frame

Baseline: **`tauri 2.11.5`**, verified 2026-07-27, mostly by reading the crate source locally.
Community-sourced claims are marked `[community-sourced]`.

**This file owns desktop *interaction*:** window lifecycle, custom titlebars and drag regions,
menus, tray, native dialogs, notifications, keyboard ownership, DPI, shell-opening, ergonomics.
Platform divergence is stated inline where it bites.

**It does not own, and does not repeat:** WebView engine divergence, distro bring-up and build
toolchains → `references/cross-platform.md`; icons, packaging, installers, signing →
`references/build-and-distribution.md`; the capability model behind the permissions named here →
`references/security.md`; startup/rendering/memory cost → `references/performance.md`; visual
craft → `impeccable` (SKILL.md Rule 12).

---

## The through-line

"Feels like a web app" is almost always one of four things: **the window remembers nothing**;
**the chrome you drew behaves worse than the chrome you removed**; **the webview's own bindings
are still in charge** (browser context menu, find bar, zoom); **everything is HTML**, including
things that must not be, like the file picker.

Fix in that order. 1 and 3 are cheap and high-signal. 2 is expensive and the one most often
shipped half-finished.

---

## Window creation — config windows vs. runtime builder

Static windows in `app.windows[]` are created before `setup()` runs, are schema-validated, and
participate in platform config merging (`references/cross-platform.md` §11). That is the right
home for the main window: no window-creation code to get wrong. `WebviewWindowBuilder` is for
windows whose existence, label, URL or geometry depends on runtime state — ZUS creates secondary
editor windows that way (`src-tauri/src/commands/window.rs:30`):

```rust
// tauri 2.11.5
WebviewWindowBuilder::new(&app, &label, webview_url).title(&title).inner_size(1200.0, 800.0)
```

**The label is the identity.** `get_webview_window(label)`, `emit_to(label, ..)` and — critically
— the `windows` array of every capability file key off it. A capability listing
`"windows": ["main"]` grants nothing to a runtime window labelled `editor-3`; that is the standard
cause of "works in the main window, denied in the new one". Decide the label scheme before you
ship (`main`, `editor-{n}`, `settings`) and write capability globs that match. A naming decision
is a security decision — model in `references/security.md`.

**Trade-off.** Runtime creation costs a webview instantiation: a fresh process on Windows, a fresh
`WKWebView` on macOS, the most expensive single operation in the app. Reusing a hidden window and
re-navigating is far cheaper; whether that beats the state-leakage risk is a
`references/performance.md` question. Single-window app? Do not build a window manager.

**`minWidth`/`minHeight` are a data-integrity control**, not styling. ZUS clamps at `800 × 600`
against a `1280 × 800` default (`tauri.conf.json:16-19`). Without a minimum a user drags the
window to 120 px, the layout collapses, and — if you also persist size — *that* is what gets
restored next launch; on Windows it can end up narrower than its own caption buttons. The failure
is not "it looks bad", it is "the app is permanently broken and cannot be fixed from inside the
UI". Take the minimum from the narrowest layout you actually verified, not a CSS breakpoint.

**`visible: false`, then show on your own terms.** ZUS ships `"visible": false`
(`tauri.conf.json:25`) and calls `window.show()` from Rust after restoring geometry
(`commands/window.rs:154`). A visible-at-creation window is shown by the OS *before* the webview
paints — white, or with `transparent: true` transparent-black, until the frontend renders.

The failure mode you now own: if the frontend throws before signalling ready, the app runs with
**no window and no way to reach it**. Two mandatory guards — show from **Rust on a timeout**, not
only on a frontend event (Rust always runs), and show on error paths too, because a visible window
with a broken page is debuggable and an invisible one is a ticket saying "nothing happens". ZUS
applies the mirror guard to its boot screen: a 20 s `setTimeout` that force-dismisses it
(`src/main.ts:285-286`). Generalise — **any UI gated on an event needs a timeout that fails open.**

Windows-only: with `transparent: true`, `noRedirectionBitmap` "can help avoid a white flash when
creating a transparent window" (`tauri-utils`, `config.rs` L2044).

---

## Window state persistence

**Persist position, size and maximized state — and validate the restore against current monitors
before applying it.** The validation is what people skip, and it is what produces an invisible
window.

`tauri-plugin-window-state` is the official option; take it unless you have a reason not to:

```rust
// tauri 2.11.5
.plugin(tauri_plugin_window_state::Builder::default()
    .with_state_flags(StateFlags::SIZE | StateFlags::POSITION | StateFlags::MAXIMIZED)
    .build())
```

ZUS owns it instead, because geometry lives in the same SQLite store as the rest of its persisted
workbench state and splitting one restore across two backends means two failure modes and two
migrations (`src-tauri/src/commands/window.rs:119-155`):

```rust
// tauri 2.11.5 — abridged
let on_screen = app.available_monitors().ok().is_some_and(|monitors| {
    monitors.iter().any(|m| /* ≥100×50 px overlap with m.position()/m.size() */ true)
});
if on_screen {
    let _ = window.set_position(tauri::PhysicalPosition::new(state.x, state.y));
    if state.maximized { let _ = window.maximize(); }
    else { let _ = window.set_size(tauri::PhysicalSize::new(state.width, state.height)); }
}
let _ = window.show();
```

**The trap.** Saved coordinates are desktop-space, and the desktop changes shape: undock the
laptop, unplug the second monitor, rearrange displays. Restore `x: 2400` after the monitor
spanning `1920..3840` is gone and the window lands **off-screen** — running, focused, receiving
input, invisible. Windows has a recovery path (Alt+Space → Move); macOS normally clamps
title-bearing windows back on screen, but **a `decorations: false` window has no titlebar to
clamp**, so removing decorations removes the OS's own safety net. Custom titlebars are what make
this section mandatory.

For tests: `primary_monitor()`, `available_monitors()` and `monitor_from_point()` are
`unimplemented!()` under `MockRuntime` — they panic rather than degrade. Put the geometry decision
in a pure function taking the monitor list as an argument and test *that*.

**When to save.** Not per resize event — that is a write per frame during a drag. ZUS debounces at
500 ms plus a write on `beforeunload` (`src/main.ts:325-344`). Trade-off: a hard kill inside the
debounce loses the last move, which is the correct trade against thousands of writes per drag. If
you cannot accept it, debounce on the Rust `WindowEvent::Moved`/`Resized` instead — that at least
survives a frontend crash.

State is per **label**. One blob restored into three windows stacks them exactly, which looks like
two failed to open; key by label and cascade new windows ~24 px.

---

## Multi-window ownership

**One owner of the window set, in Rust; the frontend asks it.** Any webview with
`core:window:allow-create` can make a window, which is why it should not: windows are expensive,
they outlive the code that created them, and the frontend cannot see the whole set.

- **Duplicates.** Two paths both "open settings". Fix: a `focus_or_create(label)` command —
  `get_webview_window`, then `unminimize()` → `show()` → `set_focus()`. All three: each handles a
  different state, and skipping `unminimize` leaves a minimised window unrestored on Windows (the
  sequence Jan uses, `refs/jan/src-tauri/src/core/setup.rs:396-398`).
- **Orphans.** Main window closes, a child survives, the app is a ghost with no way back. Decide
  per window whether it is dependent or independent and enforce it in `on_window_event`.
- **Label collision.** `WebviewWindowBuilder::new` fails on an existing label. Generate labels from
  Rust-held state, never a frontend string, or the webview controls a key into your window map.

**Focus differs per platform.** `set_focus()` raises and focuses on Windows and Linux. On **macOS**
the window manager resists a background app stealing focus and may only bounce the Dock icon — a
"bring to front" button that works on Windows and looks dead on macOS is this. Do not fight it
with repeated calls; that behaviour is what Mac users expect.

---

## Custom titlebars — ZUS's config, decoded

**The most expensive item in this file, and the one most often shipped half-finished.** You are
not turning a titlebar off; you are taking responsibility for drag, double-click, snap, shadow,
corner rounding and the window-control inset — three platforms, three window states each. Budget
for it, or ship `decorations: true` and spend the time on the app.

ZUS ships the full version (`src-tauri/tauri.conf.json:14-30`, `tauri 2.11.5`):

```jsonc
{
  "title": "ZUS",
  "width": 1280, "height": 800,
  "minWidth": 800, "minHeight": 600,
  "decorations": false,       // Windows/Linux/macOS: remove the OS frame
  "shadow": true,             // put the drop shadow back
  "transparent": true,        // required for rounded corners
  "visible": false,           // show from Rust after geometry restore
  "dragDropEnabled": false,   // let HTML5 DnD reach the webview
  "titleBarStyle": "Overlay", // macOS only
  "hiddenTitle": true         // macOS only
}
```

**`decorations: false`** is the only key that removes chrome on **Windows and Linux**. It also
removes the resize border, the caption buttons, and — on Windows 11 — the shell behaviours bound
to the real Maximize button. On macOS alone it would delete the traffic lights, hence the next key.

**`titleBarStyle: "Overlay"` is macOS only** — the builder method is literally
`#[cfg(target_os = "macos")]` (`src/webview/webview_window.rs:723-729`), and `set_title_bar_style`
is documented "**macOS only**". It keeps the traffic lights floating over your content. The enum
doc names the caveats you are accepting (`tauri-utils 2.9.3`, `src/lib.rs:173-177`), all real:

- *"The height of the title bar is different on different OS versions, which can lead to window
  the controls and title not being where you don't expect."* → never hardcode the traffic-light
  inset; make it a CSS variable (ZUS: `--zus-window-controls-inset`) driven from state.
- *"You need to define a custom drag region to make your window draggable."*
- *"due to a limitation you can't drag the window when it's not in focus"* (tauri-apps/tauri#4316).
  Symptom: "I have to click the window first, then drag." No config fix exists.

`TitleBarStyle::Transparent` is the cheaper option — same doc: *"Useful if you don't need to have
actual HTML under the title bar. This lets you avoid the caveats of using
`TitleBarStyle::Overlay`."* **If your design does not put content in the titlebar strip, take
`Transparent` and skip the whole trap list below.** `hiddenTitle: true` (macOS only) hides the
title text so the strip is yours.

**`transparent: true` is the expensive key, for non-aesthetic reasons.** Required for rounded
corners; three platform costs, each documented elsewhere. macOS needs `macOSPrivateApi` — an **App
Store rejection risk** — and measures roughly **8× the idle GPU power** of an opaque window
(`references/cross-platform.md` §6, `references/performance.md`). On **Linux + NVIDIA** it is the
*specific trigger* for the `Error 71 (Protocol error)` / GBM buffer launch failure
(`references/cross-platform.md` §7). On Windows it can flash white without `noRedirectionBitmap`.
**If you only want rounded corners or vibrancy, use `WindowEffectsConfig` or a background colour**
— transparency is an always-on cost paid by every user on every frame. **`shadow: true`** restores
the drop shadow `decorations: false` removes; without it a borderless window has no separation
from what is behind it, the cheapest tell that an app is a rectangle drawn by a webview.

**The state machine you now own.** A rounded window must stop being rounded when maximized or
fullscreen or the desktop shows through the corners; macOS hides the traffic lights in fullscreen,
so the inset must collapse at the same moment (`src/main.ts:296-313`):

```ts
// tauri 2.11.5 / @tauri-apps/api 2.x
const apply = async () => {
    const fullscreen = await win.isFullscreen();
    const flat = (await win.isMaximized()) || fullscreen;
    document.documentElement.classList.toggle('zus-window-round', !flat);
    document.documentElement.classList.toggle('zus-window-fullscreen', fullscreen);
};
void apply();
void win.onResized(() => { void apply(); });
```

The rounding class is applied in `index.html` **from first paint** (gated on `__ZUS_TAURI__`) and
this code only ever *removes* it — corners are round before any JS runs, and the browser build of
the same frontend is a no-op. The listener is `onResized`, not a maximize event, because maximize,
unmaximize, fullscreen and a plain drag all need the same recomputation.

**When to deviate.** Keep `decorations: true` if the app has no titlebar content, if Linux is a
first-class target (tiling WMs and non-GNOME shells treat client-side decorations inconsistently),
or if accessibility outweighs aesthetics — screen readers and window managers understand a real
titlebar and understand nothing about your `<div>`.

---

## Drag regions — five traps, in discovery order

Two mechanisms: the `data-tauri-drag-region` attribute (Tauri's injected script starts a native
drag on mousedown, zero JS from you), or `getCurrentWindow().startDragging()` (Rust:
`WebviewWindow::start_dragging()`), which needs `core:window:allow-start-dragging`.

**1 — the attribute does not apply to children.** The handler tests the event target, so a `<span>`
inside your bar is a dead zone. Symptom: "the titlebar drags, except where the title is."

**2 — interactive children get swallowed.** The inverse: put it on the whole bar and buttons inside
stop responding, because mousedown starts a drag before the click lands.

1 and 2 are one problem — **inheritance is wrong in both directions** — so any non-trivial titlebar
delegates. ZUS does (`src/main.ts:346-374`):

```ts
// tauri 2.11.5
const TITLEBAR_NO_DRAG_SELECTOR =
    'a, button, input, select, textarea, [contenteditable="true"], [draggable="true"], ' +
    '.action-item, .command-center, .window-controls-container, .menubar, .monaco-menu, ' +
    '.monaco-action-bar, .window-title, .tabs-container, .tab, /* .. */';

document.addEventListener('mousedown', (e: MouseEvent) => {
    if (e.button !== 0 || e.defaultPrevented || !appWindow) return;
    const target = e.target as HTMLElement | null;
    if (!target?.closest('.part.titlebar')) return;         // scope
    if (target.closest(TITLEBAR_NO_DRAG_SELECTOR)) return;  // deny-list
    appWindow.startDragging().catch(() => {});
});
```

*Why a deny-list:* ZUS's titlebar is rendered by the VS Code workbench, not ZUS's markup — there is
nowhere to put `data-tauri-drag-region`. One delegated listener works against DOM you do not author.
*Trade-off:* a deny-list is a standing liability — every new interactive widget in the titlebar
becomes a drag handle until someone adds it, and the failure is silent. **If you own your markup,
prefer the attribute on opted-in children; an allow-list fails closed.** The three guards are
load-bearing: `e.button !== 0` stops right-click dragging, `e.defaultPrevented` respects handlers
that already claimed the event, `.catch(() => {})` absorbs the rejection when the mouse is already
up.

**3 — double-click to maximize disappears.** Every platform maximizes on titlebar double-click
(macOS performs the user's configured "double-click a window's title bar to" action). Roll your own
drag and you get none of it: add a `dblclick` handler calling `toggleMaximize()`. On macOS you
cannot read that preference from the webview, so maximize approximates a setting that may be
*Minimize* or *Do Nothing* — record it as a known divergence.

**4 — Windows 11 loses snap layouts.** The snap flyout comes from the shell when a hit-test returns
the maximize-button region; a styled `<div>` never returns it. Fixing it needs native
window-procedure hit-testing, for which no Tauri API exists in `2.11.5`. Treat it as a **cost of
`decorations: false` on Windows** and weigh it — Win 11 power users use snap layouts constantly.

**5 — macOS `Overlay` will not drag an unfocused window** (#4316). Distinguish from trap 1 by
testing on an already-focused window.

---

## Menus

**Use `PredefinedMenuItem` for everything the platform already names, and accept that the menu bar
is a macOS structure Windows and Linux merely tolerate.**

**The structural divergence decides whether you write this code at all.** On **macOS** there is
exactly one menu bar; it belongs to the *application*, sits at the top of the screen, its first
submenu is named after the app, and it exists whether or not a window is open — users look there
for Preferences and Quit. On **Windows and Linux** the menu lives *inside the window frame*, so
with `decorations: false` there is nowhere to put it and you must render it in HTML.

ZUS makes the native menu macOS-only: `build_menu` is `#[cfg(target_os = "macos")]`
(`src-tauri/src/lib.rs:24-26`), as is `app.set_menu(build_menu(app.handle())?)?`
(`lib.rs:491-495`); Windows and Linux get the workbench's HTML menubar. **That is the right default
for any app with a custom titlebar** — one native menu where the platform demands it, one HTML menu
where the platform has nowhere to put a native one. Keeping native menus on all three means either
restoring decorations on Windows/Linux or maintaining two implementations that must stay in sync.

```rust
// tauri 2.11.5 — src-tauri/src/lib.rs:27-95
use tauri::menu::{MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};

let file_menu = SubmenuBuilder::with_id(app, "file_menu", "File")
    .item(&MenuItemBuilder::with_id("save", "Save").accelerator("CmdOrCtrl+S").build(app)?)
    .separator()
    .build()?;

let edit_menu = SubmenuBuilder::with_id(app, "edit_menu", "Edit")
    .item(&PredefinedMenuItem::undo(app, None)?)
    .item(&PredefinedMenuItem::redo(app, None)?)
    .separator()
    .item(&PredefinedMenuItem::cut(app, None)?)
    .item(&PredefinedMenuItem::copy(app, None)?)
    .item(&PredefinedMenuItem::paste(app, None)?)
    .build()?;
```

**`PredefinedMenuItem` is not a convenience.** It is the difference between an item that works and
one that only looks right. You get the platform's **own label, already localized** — a hand-written
`"Copy"` stays English in a French menu bar; the **standard accelerator**, including ones with no
cross-platform equivalent (`Cmd+,` for Preferences); and on macOS, **wiring into the responder
chain**, so `PredefinedMenuItem::copy` actually copies from the focused field. A custom item with
the same accelerator does not — it fires `on_menu_event` and hands you an id, and now *you*
implement clipboard semantics for a selection inside a webview you do not control.

Rule: if the platform names it — undo, redo, cut, copy, paste, select-all, minimize, maximize,
fullscreen, hide, hide-others, show-all, close-window, quit, about, services, separator — use the
predefined item. `MenuItemBuilder` is for application-specific commands only.

**Dispatch.** `on_menu_event` is registered on the `Builder` and receives every event. ZUS forwards
into the webview as a DOM event (`src-tauri/src/lib.rs:515-523`):

```rust
// tauri 2.11.5
.on_menu_event(|app, event| {
    let id = event.id().0.as_str();
    if let Some(window) = app.get_webview_window("main") {
        let escaped = id.replace('\\', "\\\\").replace('\'', "\\'");
        let _ = window.eval(format!(
            "window.dispatchEvent(new CustomEvent('zus-native-menu', {{ detail: '{escaped}' }}))"
        ));
    }
})
```

Note the escaping. Ids are yours, so the injection risk is theoretical — but `eval` with a
formatted string is a code-generation boundary and treating it as one costs two `replace` calls.
`references/security.md` in reverse: data crossing *into* the webview via `eval` needs escaping
just as data crossing out needs validation.

**The trap: one keystroke, two owners.** On macOS, AppKit consumes a menu accelerator *before* the
webview sees the key. If the frontend also binds that chord, one press fires both — a zoom that
jumps two steps, a save that runs twice. ZUS records the resolution in place (`lib.rs:217-229`):
zoom in/out are declared **without accelerators** so the workbench keybindings stay sole owner,
while Reset Zoom keeps `CmdOrCtrl+0` because AppKit dispatches the same action and the outcome is
identical — and the menu still *displays* the shortcut, the user-visible half of what an
accelerator is for. Generalise: **declaring an accelerator in a native menu claims exclusive
ownership of that chord on macOS.** Check whether the frontend binds it; if so, delete one — never
keep both.

**Context menus.** `ContextMenu::popup(window)` / `popup_at(window, position)`
(`src/menu/menu.rs:29-42`). Native is right when the menu is predefined items (copy/paste in a
field) and wrong when it needs your design system's icons, rich content, or keyboard navigation
matching the rest of the UI. Apps that own their titlebar usually render context menus in HTML —
but first suppress the webview's own (see *Desktop ergonomics*).

---

## System tray and the run-in-background lifecycle

**The menu is the only tray affordance that works on all three platforms. Click handling is a
Windows/macOS enhancement, not the mechanism.**

Jan's tray (`refs/jan/src-tauri/src/core/setup.rs:378-419`; Jan pins `tauri 2.8.5`, every API
re-verified against `2.11.5`):

```rust
TrayIconBuilder::with_id("tray")
    .icon(app.default_window_icon().unwrap().clone())
    .menu(&menu)                        // Open / separator / Quit
    .show_menu_on_left_click(false)
    .on_tray_icon_event(|tray, event| match event {
        TrayIconEvent::Click {
            button: MouseButton::Left, button_state: MouseButtonState::Up, ..
        } => {
            if let Some(w) = tray.app_handle().get_webview_window("main") {
                let _ = w.unminimize(); let _ = w.show(); let _ = w.set_focus();
            }
        }
        _ => {}
    })
    .on_menu_event(|app, event| match event.id.as_ref() {
        "open" => { /* same three calls */ }
        "quit" => { app.exit(0); }
        _ => {}
    })
    .build(app)
```

**Platform divergence, verbatim from `tauri 2.11.5` source:**

- `TrayIconEvent` — *"**Linux**: Unsupported. The event is not emitted even though the icon is
  shown and will still show a context menu on right click."* (`src/tray/mod.rs:64-67`).
  `on_tray_icon_event` **never fires on Linux**, so a tray whose only way back in is a left-click
  handler is a dead icon for every Linux user. Hence: always ship a menu.
- `show_menu_on_left_click` — default `true`, *"**Linux:** Unsupported."* (`src/tray/mod.rs:314-318`).
  Jan sets `false` to match Windows/macOS convention: left-click activates, right-click menus.
- `icon_as_template(true)` — **macOS only**; marks the icon an NSImage template so it inverts with
  the menu-bar appearance. Skip it and a coloured icon looks wrong in dark mode.
- Linux needs `libayatana-appindicator3-1` at runtime, in the `.deb` `depends` —
  `references/cross-platform.md` §10, `references/build-and-distribution.md`.

Do not copy the `.unwrap()` on `default_window_icon()`: it turns a missing bundle icon into a
startup panic with no message.

**The lifecycle question a tray forces you to answer: what does closing the last window mean?**
Pick one and apply it consistently. (1) **Close = quit** — correct for editors and document apps.
(2) **Close = hide to tray, quit only from the tray menu** — correct for agents, monitors, sync
clients, anything whose job continues without a window. (3) **macOS-shaped: close hides the window,
the app stays in the Dock, Quit is in the app menu** — the platform default on macOS, and quitting
on last-window-close is one of the most common ways a Tauri app announces it was not written for
the Mac.

**Two hooks, and missing the second is the bug.** Jan intercepts both to drain a running inference
server (`refs/jan/src-tauri/src/lib.rs:360-403`):

```rust
// tauri 2.8.5; RunEvent shape unchanged in 2.11.5
app.run(|app, event| {
    if let RunEvent::WindowEvent {
        event: tauri::WindowEvent::CloseRequested { api, .. }, label, ..
    } = &event {
        if label == "main" && !SHUTTING_DOWN.load(Ordering::SeqCst) && is_router_running(app) {
            api.prevent_close();
            if GRACEFUL_IN_PROGRESS.swap(true, Ordering::SeqCst) { return; } // idempotent
            /* spawn graceful shutdown, then close for real */
            return;
        }
    }
    if let RunEvent::ExitRequested { api, code, .. } = &event { /* api.prevent_exit() */ }
});
```

`CloseRequested` fires per window (the X button); `ExitRequested` fires for the application (Cmd+Q,
the app menu, your tray Quit). **Handling only `CloseRequested` means Quit bypasses your cleanup** —
exactly the shape of "it saves on close but loses data on quit".

**A prevent with no way out is an app the user cannot quit.** Note Jan's two atomics,
`SHUTTING_DOWN` and `GRACEFUL_IN_PROGRESS.swap(true, ..)`, so a second Quit during shutdown is
absorbed rather than starting a second shutdown. Any prevent needs an idempotency flag **and** a
timeout that exits anyway.

For hide-to-tray (`api.prevent_close(); window.hide();`): **tell the user the first time.** A window
that vanishes silently is indistinguishable from a crash, and the user's next move is to launch the
app again — which does nothing, because it is already running.

---

## Dialogs — never build a file picker in HTML

Not "prefer native". Never. Three reasons, none aesthetic: **`<input type="file">` gives a `File`,
not a path**, and your file logic is in Rust — `tauri-plugin-dialog` returns a `FilePath`; **it
cannot show the filesystem the way the user navigates it** (no sidebar favourites, recent places,
network volumes, cloud providers, "New Folder", type-ahead); and **on macOS the native panel is
what grants access** — a picker you drew grants nothing, and under sandboxing the chosen path is
not readable.

```rust
// tauri-plugin-dialog 2.7.0
use tauri_plugin_dialog::DialogExt;

app.dialog().file()
    .add_filter("Rust", &["rs", "toml"])
    .set_parent(&window)
    .pick_file(|path| { /* Option<FilePath>, on a callback thread */ });
```

Also `pick_files`, `pick_folder`, `pick_folders`, `save_file`, and `blocking_pick_file` /
`blocking_show` / `blocking_show_with_result`.

**Sync vs async is the trap.** The `blocking_*` family blocks the calling thread until dismissed.
Call one from a non-`async` `#[tauri::command]` and you have blocked the event loop: every window
freezes, and on some platforms the dialog cannot paint either — a deadlock, not a stall.
**`blocking_*` only from a thread you spawned**; from a command, use the callback form. SKILL.md
Rule 4.

`set_parent(&window)` makes it a real sheet on macOS and a window-owned modal on Windows. Without
it the dialog can open behind the app or on another monitor — a hang report that is really an
invisible dialog.

Permissions: `dialog:allow-open`, `dialog:allow-save`, `dialog:allow-message`; model in
`references/security.md`. A picked path is user-chosen, which is not the same as safe — it still
arrives in your command as a webview string, so canonicalise and check containment in Rust.

---

## Notifications

Permission model mirrors the web: `isPermissionGranted()` → `requestPermission()` →
`sendNotification()` (`@tauri-apps/plugin-notification`), or the Rust `NotificationExt` builder.
Request when the user opts into something notification-worthy, never at startup — a prompt in the
first second gets denied, and on macOS that denial is sticky in System Settings where the user
will never find it.

Caveats, all of which present as "notifications don't work":

- **macOS** attributes notifications to the bundle; unsigned or ad-hoc-signed apps are commonly
  dropped silently. Symptom: works under `tauri dev`, nothing from the installed `.app`. That is a
  signing problem → `references/build-and-distribution.md`.
- **Windows** needs a registered AppUserModelID, which the installer provides. Symptom: works
  installed, silent from a portable `.exe`.
- **Windows 7** needs the `windows7-compat` feature, which moved from the `tauri` crate onto
  `tauri-plugin-notification` in v2 — a v1-era snippet enabling it on `tauri` will not compile.
- **Linux** delivery needs a running notification daemon; on a minimal WM there may be none, and
  nothing errors.

Consequence: **notifications are best-effort everywhere.** Never put information the user must see
only in a notification.

---

## Keyboard ownership — three layers, one keystroke

Consumption order, outermost first: **OS global shortcuts**
(`tauri-plugin-global-shortcut`, fire even unfocused) → **native menu accelerators** (consumed by
the platform menu before the webview; see §Menus for the macOS double-owner bug) → **webview
keybindings**, which see only what the first two did not eat.

- *Global means global.* Registering `CmdOrCtrl+Shift+P` takes it from every other app on the
  machine. Register the minimum, make them user-configurable, unregister on exit — a leaked
  registration on Windows can outlive the process.
- *Registration fails silently if another app holds the chord.* Check the result and surface it,
  or the feature is mysteriously dead on one machine.
- *The WebView has bindings you did not ask for:* `Ctrl/Cmd+Shift+I` (devtools —
  `references/debugging-and-testing.md`), `Ctrl+F` (WebKitGTK's own find bar, which appears over
  your find UI on Linux), `Ctrl+P` (print), `Ctrl+±` (browser zoom, which scales the page and not
  your chrome).
- *Reload is the dangerous one.* `Ctrl+R`/`F5` reloads the frontend while Rust state survives — a
  half-reset app with inconsistent state on both sides. Suppress it in release builds unless you
  have deliberately made reload safe.

Suppress per chord in a capture-phase listener, never with a blanket handler, or you break IME and
accessibility keys you never tested.

---

## DPI

**Sizes you *set* are logical; everything you *read back* is physical. A hardcoded pixel number is
wrong in one of those two spaces.** This is how a window 1280 px wide on your machine opens 853 px
wide on a user's.

- **Setting is logical.** `WebviewWindowBuilder::inner_size(f64, f64)`, `min_inner_size`,
  `max_inner_size` (`src/webview/webview_window.rs:805-823`), and the config keys
  `app.windows[].width/height/minWidth/minHeight`. Logical = CSS pixels at scale 1.0, so the same
  numbers give the same *apparent* size on a 1× and a 2× display. That is the point: you say how
  big it should look, the OS decides how many device pixels that is.
- **Reading is physical.** `WebviewWindow::inner_size() -> PhysicalSize<u32>`,
  `outer_position() -> PhysicalPosition<i32>` (`src/window/mod.rs:1483-1492`); likewise
  `Monitor::size()` / `position()` / `scale_factor() -> f64`.
- **`set_size`/`set_position` take `impl Into<Size>`** — you choose `LogicalSize` or
  `PhysicalSize`. **This is where the bug enters:** read physical, write logical, and the window
  shrinks by the scale factor every round trip. On a 200% display it halves each launch.

ZUS keeps the spaces consistent — reads `outer_position()`/`outer_size()`, restores with
`tauri::PhysicalPosition::new` / `tauri::PhysicalSize::new`
(`src-tauri/src/commands/window.rs:142-148, 168-176`). Physical-in/physical-out is correct for
persisted geometry, because the saved rect is validated against monitor rects, which are also
physical.

**The residual hazard even when you are consistent.** A physical size only means something
alongside the scale factor it was captured at. Save on a 4K display at 200% (2560×1600 physical),
restore on 1920×1080 at 100%, and that rect is larger than the screen. ZUS's ≥100×50 px overlap
check prevents the *invisible* window but not the *oversized* one. Either store `scale_factor()`
beside the rect and convert, or clamp the restored rect to the target monitor's work area —
clamping is simpler and fails safe.

**Per-platform.** **Windows** is the only platform with arbitrary fractional per-monitor scaling
(100/125/150/175/200%…), and it changes while the window exists.
`WindowEvent::ScaleFactorChanged { scale_factor, new_inner_size }` is delivered for exactly the
three causes its doc names (`src/app.rs:129-141`): the display's resolution changed, its scale
factor changed, or **the window moved to a display with a different scale factor**. Dragging
across the boundary between a 100% and a 150% monitor is the everyday case, and this event is the
invalidation signal for any pixel geometry you cached. **macOS** scale factor is effectively 1.0 or
2.0 — mixed-DPI moves happen, the arithmetic is just clean. **Linux/WebKitGTK** is the weak one:
GTK integer scaling plus fractional compositor scaling, with a documented class of "renders at a
lower scale than expected, blurry on zoom" bugs fixed by the same `WEBKIT_DISABLE_*` vars as the
graphics failures (`references/cross-platform.md` §7). Assume nothing about fractional Wayland
scaling.

**`window.devicePixelRatio` is not the OS scale factor.** It reflects the combined OS scale *and*
any webview zoom you applied, so after a `set_zoom` it no longer converts CSS pixels to device
pixels correctly. Ask Rust for `scale_factor()` when you need the real one.

**Rules:** express native window sizes logically; never persist a size without a scale factor or a
clamp; treat `ScaleFactorChanged` as cache invalidation; test on a mixed-DPI multi-monitor setup
before release, because a single-monitor dev machine cannot reproduce any of this.

---

## shell

**Opening a URL or a file *is* a shell execution, and the string decides what executes. Never pass
user-, remote- or model-supplied text to a shell open without an allow-list check in Rust.**

`shell.open(path)` reaches `OpenScope::open`, which validates against a configured regex before
calling the `open` crate (`tauri-plugin-shell 2.3.5`, `src/scope.rs:203-205`):

> *"The path is validated against the `plugins > shell > open` validation regex, which defaults to
> `^((mailto:\w+)|(tel:\w+)|(https?://\w+)).+`"*

If `plugins > shell > open` is unset the call is refused outright, logging that the configuration
*"denies calls from JavaScript"* (`src/scope.rs:216-221`). So the out-of-the-box posture is what
`shell:default` (granting `shell:allow-open`) documents: **http(s), `mailto:` and `tel:` only.**

**Why that anchored regex is load-bearing.** Underneath, `open::that_detached` hands the string to
the platform opener — `ShellExecute` on Windows, `open` on macOS, `xdg-open` on Linux. Those will
happily launch an executable, a `.lnk`, an SMB path, or any registered protocol handler. Remove the
scheme anchor and `shell.open()` becomes an arbitrary-program launcher reachable from the webview
— which, per SKILL.md mental model 1, you must assume is attacker-controlled. The plugin also notes
that argument escaping comes from `std::process::Command::arg` inside the `open` dependency, with
the maintainer caveat that *"this behavior should be re-confirmed during upgrades of `open`"* — the
guarantee is inherited from a third-party crate, not enforced by Tauri.

**The rule.** Any URL originating outside your own code — a link in rendered markdown, an LLM tool
call, a field from a remote API, a path in a downloaded config — is untrusted. Widening the regex
to accept `file://` so "reveal in file manager" works also accepts
`file:///C:/Windows/System32/...`.

- **Keep the default scope.** Widening it is the fix that looks like it worked.
- **Own the command in Rust for everything else.** Take a *typed* input — an id, an enum variant, a
  workspace-relative key — never a raw path or URL. Resolve to a path yourself, canonicalise,
  assert containment in an allowed root, then open. SKILL.md Rule 8.
- **Never interpolate webview text into `Command`/`spawn`** — a larger hole with the same root
  cause; `references/security.md`.

Permission: grant `shell:default` (= `shell:allow-open`) and nothing else. `shell:allow-execute`,
`allow-spawn`, `allow-kill` and `allow-stdin-write` are separate and none is needed to open a link.
How permission sets compose and why deny wins: `references/security.md`.

ZUS routes the whole frontend through one opener call site (`src/main.ts:315-323`):

```ts
// tauri 2.11.5
import('@tauri-apps/plugin-shell').then(shell => {
    (window as any).__zus_shellOpen = (url: string) => { shell.open(url).catch(() => {}); };
});
```

The indirection is the point: one auditable call site instead of twenty scattered `shell.open`
calls, nineteen of which nobody re-checks when the threat model changes.

`tauri-plugin-opener` is the newer alternative with an identical threat model — every argument
above transfers. Read its scope config before adopting; do not assume the default is as tight.

---

## Desktop ergonomics — the short list

**Suppress the webview context menu.** A shipped app should not offer "Reload / Back / Inspect
Element". `document.addEventListener('contextmenu', e => e.preventDefault())`, then render your own
(or `ContextMenu::popup_at`, §Menus). **Exception:** leave the default inside text inputs unless
you have reimplemented cut/copy/paste/select-all — otherwise you have removed the user's clipboard.

**Disable text selection on chrome.** `user-select: none` on titlebar, toolbars, tab strips,
sidebars, status bars; keep it on content. Drag-selecting a toolbar label is an instant tell, and a
selection started on the titlebar competes with the window drag — a correctness fix, not only a
cosmetic one.

**Real file drag-and-drop — you must choose a mode.** `app.windows[].dragDropEnabled` selects
between two mutually exclusive behaviours. `true` (default): Tauri's native handler intercepts the
drop and delivers `WindowEvent::DragDrop(DragDropEvent::{Enter, Over, Drop, Leave})` to Rust with
`paths: Vec<PathBuf>` and a cursor position (`tauri-runtime 2.11.3`, `src/window.rs:97-120`) — real
filesystem paths, what you want for "drop a folder to open it". `false` (ZUS,
`src-tauri/tauri.conf.json:26`): the native handler stands aside and HTML5 drag-and-drop works
inside the webview — required if your UI drags internally (tab reordering, list reordering, panel
docking). **You cannot have both in one window.** Symptom of choosing wrong: *"HTML5
drag-and-drop does nothing"* → `dragDropEnabled` is still `true`. The Windows builder equivalent is
`disable_drag_drop_handler()`, documented *"required to use HTML5 drag and drop APIs on the
frontend on Windows"*. Need both? Split across two windows.

**Zoom hotkeys.** `Ctrl/Cmd` with `+`, `-`, `0`. Browser zoom scales the page; the desktop
expectation is the whole UI. ZUS drives the native webview zoom factor from a Rust command and
records why inline (`src-tauri/src/commands/window.rs:190-210`): keeping it in Rust leaves the
frontend's IPC surface unchanged, whereas the JS `getCurrentWebview().setZoom()` path would require
granting `core:webview:allow-set-webview-zoom`. It clamps to `0.2..=4.5`, which matters — an
unclamped zoom reaches a factor at which no control for zooming back out is reachable, and the
setting persists.

**Follow the system theme, with a Linux fallback.** `WindowEvent::ThemeChanged(Theme)` is
documented *"**Linux**: Not supported"* (`src/app.rs:165-172`). Jan adds a D-Bus listener on XDG
Desktop Portal colour-scheme changes because *"KDE Plasma and some other desktop environments don't
always update GTK settings when the system theme changes, which means the GTK
`WindowEvent::ThemeChanged` may never fire"* (`refs/jan/src-tauri/src/core/setup.rs:427-433`). One
event source is not enough on Linux.

**Do not expose browser navigation.** No back/forward swipe gestures, no history the user can break
with a trackpad flick. If your router uses the History API, disable the gesture.

**Restore the window** — the first section of this file, and the one users notice most.

---

**Evidence.**

Read directly rather than quoted from documentation:

- `tauri 2.11.5` crate source — `app.rs:110-172` (`WindowEvent`, `ScaleFactorChanged`,
  `ThemeChanged` platform notes); `window/mod.rs:100-104, 1472-1493, 1620-1630, 1826-1857` (scale
  factor, physical geometry, monitors, sizing); `webview/webview_window.rs:722-729, 805-823,
  2182-2185` (`title_bar_style` macOS gate, logical builder sizes); `tray/mod.rs:62-80, 288-337`
  (`TrayIconEvent` and `show_menu_on_left_click` Linux notes, `icon_as_template`);
  `menu/menu.rs:29-42` (`ContextMenu::popup` / `popup_at`).
- `tauri-utils 2.9.3` `src/lib.rs:165-180` — `TitleBarStyle` variants and the verbatim `Overlay`
  caveats, including tauri-apps/tauri#4316.
- `tauri-runtime 2.11.3` `src/window.rs:97-120` — `DragDropEvent` variants and payloads.
- `tauri-plugin-dialog 2.7.0` `src/lib.rs:83, 323-367, 439-704`, `src/desktop.rs:142-210`,
  `permissions/autogenerated/commands/{open,save,message}.toml`.
- `tauri-plugin-shell 2.3.5` `src/scope.rs:201-232`, `permissions/default.toml`.
- **ZUS** (`tauri 2.11.5`) — `src-tauri/tauri.conf.json:12-39`; `src-tauri/src/lib.rs:20-95,
  217-229, 491-495, 515-523`; `src-tauri/src/commands/window.rs:19-47, 75-95, 97-210`;
  `src/main.ts:289-374`. Case narrative: `references/case-studies.md` §4.
- **Jan** (`tauri 2.8.5`) — `src-tauri/src/core/setup.rs:377-419, 421-443`;
  `src-tauri/src/lib.rs:360-403`.
- <https://v2.tauri.app/start/migrate/from-tauri-1/> — the v1→v2 plugin split, and
  `windows7-compat` moving onto `tauri-plugin-notification`.

**Unverified, stated as such:** the macOS "double-click a window's title bar to" preference cannot
be read from the webview, so a custom titlebar's double-click behaviour is an approximation; and
Windows 11 snap-layout support for a synthetic caption button needs native hit-testing, for which
no Tauri API was found in `2.11.5`.

# Windows, tray, menus — lookup

Verified against **`tauri 2.11.5`**, `muda 0.19.3`, `tauri-plugin-window-state 2.4.1`, 2026-07-28.
Reasoning, trade-offs and failure analysis: `references/desktop-ux.md` §menus, §DPI, §shell.
Platform divergence: `references/cross-platform.md`. Visual craft is `impeccable`'s call.

---

## 1. Window options — `app.windows[]` ↔ `WebviewWindowBuilder`

| Config key | Rust builder | Platform | Gotcha |
| --- | --- | --- | --- |
| `width` / `height` | `.inner_size(w, h)` | all | Logical px, not physical. `references/desktop-ux.md` §DPI |
| `minWidth` / `minHeight` | `.min_inner_size(w, h)` | all | Omitting them lets users crush the layout to 0 |
| `maxWidth` / `maxHeight` | `.max_inner_size(w, h)` | all | — |
| `x` / `y` | `.position(x, y)` | all | Restoring a stale position puts the window on a monitor that no longer exists — validate first |
| `center` | `.center()` | all | — |
| `preventOverflow` | `.prevent_overflow()` / `.prevent_overflow_with_margin(m)` | all | Clamps to the *working area* (monitor minus taskbar), not the monitor |
| `resizable` | `.resizable(bool)` | all | — |
| `maximizable` / `minimizable` / `closable` | same names | all | Native buttons only — irrelevant under `decorations: false` |
| `decorations` | `.decorations(bool)` | all | `false` = you own titlebar, drag, snap. §2 |
| `transparent` | `.transparent(bool)` | all | macOS needs `app.macOSPrivateApi: true`; idle GPU cost → `references/performance.md` §rendering |
| `shadow` | `.shadow(bool)` | all | With `decorations: false` on Windows 11 the rounded-corner shadow is not restored |
| `titleBarStyle` | `.title_bar_style(TitleBarStyle::…)` | **macOS only** | `"Visible"` \| `"Transparent"` \| `"Overlay"`. No-op on Windows/Linux |
| `hiddenTitle` | `.hidden_title(bool)` | **macOS only** | — |
| `trafficLightPosition` | `.traffic_light_position(pos)` | **macOS only** | Schema: *requires `titleBarStyle: Overlay` **and** `decorations: true`* — dead under `decorations: false` |
| `visible` | `.visible(bool)` | all | `false` + `window.show()` from Rust after restore = no white-flash reposition |
| `focus` / `focused` | `.focus()` / `.focused(bool)` | all | — |
| `alwaysOnTop` / `alwaysOnBottom` | `.always_on_top(b)` / `.always_on_bottom(b)` | all | — |
| `skipTaskbar` | `.skip_taskbar(bool)` | all | Pair with a tray icon or the app becomes unreachable |
| `dragDropEnabled` | `.disable_drag_drop_handler()` (builder inverts) | all | `true` (default) makes the **native** handler swallow HTML5 drag-and-drop. Set `false` to use web DnD |
| `useHttpsScheme` | `.use_https_scheme(bool)` | Windows, Android | Changing it after release **changes the webview origin** and orphans `localStorage`/IndexedDB → `references/cross-platform.md` §Windows |
| `windowEffects` | `.effects(WindowEffectsConfig)` | Win/macOS | Acrylic/mica/vibrancy; costs compositing |
| `backgroundColor` | `.background_color(Color)` | all | Cheapest fix for the white flash before first paint |
| `backgroundThrottling` | `.background_throttling(policy)` | all | — |
| `contentProtected` | `.content_protected(bool)` | Win/macOS | Excludes the window from screen capture |
| `zoomHotkeysEnabled` | `.zoom_hotkeys_enabled(bool)` | all | Off by default; users expect Ctrl+± in a desktop app |
| `theme` | `.theme(Option<Theme>)` | all | `None` = follow the OS |
| `parent` | `.parent(&win)?` | all | Linux equivalent is `.transient_for(&win)?` |
| `windowClassname` | `.window_classname(s)` | **Windows only** | Needed when an installer or automation tool matches on class name |
| `label` | `WebviewWindowBuilder::new(app, "label", url)` | all | Immutable; it is the key every event and capability matches on |

Builder-only, no config equivalent: `.on_navigation()`, `.on_page_load()`, `.on_download()`,
`.on_web_resource_request()`, `.initialization_script()`. Runtime creation vs. config windows:
`references/desktop-ux.md`.

---

## 2. Custom titlebar — the ZUS recipe, and the three things it costs

Shipped config (`zus/src-tauri/tauri.conf.json`):

```json
{ "app": { "windows": [{
  "decorations": false,
  "transparent": true,
  "titleBarStyle": "Overlay",
  "hiddenTitle": true,
  "shadow": true,
  "dragDropEnabled": false,
  "visible": false
}]}}
```

Drag region — the official markup:

```html
<div class="titlebar">
  <div data-tauri-drag-region></div>
  <div class="controls">
    <button id="titlebar-minimize">…</button>
    <button id="titlebar-maximize">…</button>
    <button id="titlebar-close">…</button>
  </div>
</div>
```

```ts
import { getCurrentWindow } from '@tauri-apps/api/window';
const appWindow = getCurrentWindow();
document.getElementById('titlebar-minimize')?.addEventListener('click', () => appWindow.minimize());
document.getElementById('titlebar-maximize')?.addEventListener('click', () => appWindow.toggleMaximize());
document.getElementById('titlebar-close')?.addEventListener('click', () => appWindow.close());
```

Capability (`core:window:default` does **not** include these):

```json
"permissions": [
  "core:window:default",
  "core:window:allow-close",
  "core:window:allow-minimize",
  "core:window:allow-toggle-maximize",
  "core:window:allow-start-dragging"
]
```

### What `decorations: false` breaks, and the fix for each

| Breaks | Why | Fix |
| --- | --- | --- |
| **Child elements do not drag** | `data-tauri-drag-region` applies *only* to the element carrying it — deliberate, so buttons and inputs keep working | Put the attribute on **every** draggable child, or drop the attribute and call `appWindow.startDragging()` from a `mousedown` handler |
| **Double-click no longer maximizes** | Nothing native is listening | In the same `mousedown` handler: `e.detail === 2 ? appWindow.toggleMaximize() : appWindow.startDragging()` |
| **Windows 11 snap layouts disappear** | The flyout only appears for a window that answers `WM_NCHITTEST` with `HTMAXBUTTON` (value 9); a frameless window has no such region. Tracking issue `tauri-apps/tauri#4531`, still open | No first-party API. Either keep `decorations: true`, or overlay a native child `HWND` over your maximize button that returns `HTMAXBUTTON`. `[community-sourced]` crates doing exactly this: `tauri-plugin-window-controls`, `tauri-plugin-decoration`, `tauri-plugin-frame` — audit before adopting |

Manual drag handler (replaces `data-tauri-drag-region`, fixes both of the first two rows):

```ts
document.getElementById('titlebar')?.addEventListener('mousedown', (e) => {
  if (e.buttons === 1) {
    e.detail === 2 ? appWindow.toggleMaximize() : appWindow.startDragging();
  }
});
```

Touch and pen input on Windows needs the CSS form as well:

```css
*[data-tauri-drag-region] { app-region: drag; }
```

**macOS alternative that keeps the native features** (window tiling, alignment, traffic lights):
`decorations: true` + `TitleBarStyle::Transparent` + set `NSWindow` background from Rust. Costs
a `objc2-app-kit` dependency and a `#[cfg(target_os = "macos")]` branch. Docs:
<https://v2.tauri.app/learn/window-customization/>.

---

## 3. Menus — Rust

```rust
use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};

let open = MenuItemBuilder::with_id("open", "&Open…").accelerator("CmdOrCtrl+O").build(app)?;
let file = SubmenuBuilder::new(app, "File")
    .item(&open)
    .separator()
    .item(&PredefinedMenuItem::close_window(app, None)?)
    .build()?;
let menu = MenuBuilder::new(app).item(&file).build()?;
app.set_menu(menu)?;
```

| Type | Use | Gotcha |
| --- | --- | --- |
| `MenuBuilder::new(mgr)` / `::with_id(mgr, id)` | Menubar or context menu | **macOS: a global menubar may contain only `Submenu`s** — a top-level `MenuItem` silently misbehaves |
| `SubmenuBuilder::new(mgr, "File")` | One menubar column | `.submenu_icon()` and `.submenu_native_icon()` reset each other |
| `MenuItemBuilder::new(text)` / `::with_id(id, text)` | Plain item | Chain `.accelerator(s)`, `.enabled(b)`, then `.build(mgr)?` |
| `CheckMenuItem`, `IconMenuItem` | Toggles, icon items | Shortcuts on the builders: `.check(id, text)`, `.icon(id, text, image)` |
| `.native_icon(id, text, NativeIcon::…)` | macOS system icon | **Windows / Linux: unsupported** |
| `PredefinedMenuItem::*` | Native behaviour, free | Table below |
| `&` in item text | Mnemonic (`"&Open"` → Alt+O) | Literal ampersand is `&&` |
| `HELP_SUBMENU_ID`, `WINDOW_SUBMENU_ID` | macOS Help/Window submenu ids | Use these ids or macOS will not populate them |

`PredefinedMenuItem` (all take `(manager, text: Option<&str>)`; `about` also takes
`Option<AboutMetadata>`): `separator`, `copy`, `cut`, `paste`, `select_all`, `undo`, `redo`,
`minimize`, `maximize`, `fullscreen`, `hide`, `hide_others`, `show_all`, `close_window`, `quit`,
`about`, `services`, `bring_all_to_front`. **`hide_others`, `show_all`, `services`,
`bring_all_to_front` are macOS concepts** — put them behind `#[cfg(target_os = "macos")]` rather
than shipping inert items on Windows.

Events: `app.on_menu_event(|app, event| match event.id().as_ref() { "open" => …, _ => {} })`, or
`WebviewWindowBuilder::on_menu_event` per window. Handlers run on the main thread — anything
slow must be `tauri::async_runtime::spawn`ed (`references/ipc-and-commands.md` §Threading).

### Accelerator syntax (`muda` parser)

Format: `Modifier+Modifier+Key`. **All modifiers first**; `Shift+Alt+KeyQ` parses,
`Shift+KeyQ+Alt` is `InvalidFormat`. Case-insensitive, `+`-separated, exactly one non-modifier key.

| Token | Resolves to |
| --- | --- |
| `CmdOrCtrl` / `CmdOrControl` / `CommandOrCtrl` / `CommandOrControl` | `SUPER` on macOS, `CONTROL` elsewhere — **use this one** |
| `Command` / `Cmd` / `Super` | `META` |
| `Control` / `Ctrl` | `CONTROL` |
| `Option` / `Alt` | `ALT` |
| `Shift` | `SHIFT` |

Key names are `KeyboardEvent.code` values, with shorthand: `KeyA`…`KeyZ` (or bare `A`…`Z`),
`Digit0`…`Digit9` (or `0`…`9`), `F1`…, `Enter`, `Space`, `Tab`, `Backspace`, `Delete`, `Home`,
`End`, `PageUp`, `PageDown`, `Comma`/`,`, `Period`/`.`, `Minus`/`-`, `Equal`/`=`, `Slash`/`/`,
`Backslash`/`\`, `Quote`/`'`, `Semicolon`/`;`, `Backquote`/`` ` ``, `BracketLeft`/`[`,
`BracketRight`/`]`. An unknown key is `UnsupportedKey`, not a silent no-op.

---

## 4. Tray icon

Requires the Cargo feature — omit it and `tauri::tray` does not exist:

```toml
tauri = { version = "2", features = ["tray-icon"] }
```

```rust
use tauri::{menu::{Menu, MenuItem}, tray::TrayIconBuilder};

let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
let menu = Menu::with_items(app, &[&quit])?;
TrayIconBuilder::with_id("main-tray")
    .icon(app.default_window_icon().unwrap().clone())
    .menu(&menu)
    .show_menu_on_left_click(false)
    .on_menu_event(|app, event| if event.id().as_ref() == "quit" { app.exit(0) })
    .on_tray_icon_event(|tray, event| { /* … */ })
    .build(app)?;
```

| Builder method | Notes |
| --- | --- |
| `new()` / `with_id(id)` | Use `with_id` — you need it to look the tray up later |
| `.icon(Image)` | `app.default_window_icon().unwrap().clone()` for the app icon |
| `.menu(&menu)` | Also `.menu_on_left_click` (older alias of `.show_menu_on_left_click`) |
| `.show_menu_on_left_click(bool)` | **Default `true`** — leave it on for Windows convention, turn it off if left-click should toggle the window |
| `.tooltip(s)` / `.title(s)` | `title` is the text next to the icon (macOS menubar) |
| `.icon_as_template(bool)` | **macOS only** — without it a coloured icon looks wrong in dark menubar |
| `.temp_dir_path(p)` | **Linux only** — the icon is written to disk to be shown at all |
| `.on_menu_event(f)` / `.on_tray_icon_event(f)` | — |
| `.build(manager)` | Returns `TrayIcon<R>`; **drop it and the icon disappears** — keep it in state |

Config equivalent, `app.trayIcon`: `iconPath` (required), `id`, `iconAsTemplate`, `tooltip`,
`title`, `showMenuOnLeftClick`, `menuOnLeftClick` (deprecated alias).

### Click behaviour per platform — this is where tray UIs go wrong

| | Windows | macOS | Linux |
| --- | --- | --- | --- |
| `TrayIconEvent` emitted | yes | yes | **never** — the icon shows and the right-click menu works, but no event fires |
| `Click` (left/right/middle, with `button_state`) | yes | yes | no |
| `DoubleClick` | **Windows only** | no | no |
| `Enter` / `Move` / `Leave` | yes | yes | no |
| Left-click with a menu attached | opens the menu (default) | opens the menu (default) | opens the menu |
| Practical rule | double-click = open window | left-click = menu, no double-click | **menu-only**; every tray action must exist as a menu item |

Consequence: **never make a tray behaviour reachable only through a click event.** On Linux that
path does not exist. Put it in the menu and let clicks be a shortcut.

Permissions: `core:tray:default` for the JS `TrayIcon` API. Pure-Rust trays need none.

---

## 5. Window state persistence

```toml
tauri-plugin-window-state = "2"
```

```rust
use tauri_plugin_window_state::{Builder as WindowStateBuilder, StateFlags};

tauri::Builder::default()
    .plugin(
        WindowStateBuilder::default()
            .with_state_flags(StateFlags::SIZE | StateFlags::POSITION | StateFlags::MAXIMIZED)
            .with_denylist(&["splashscreen"])
            .build(),
    )
```

| API | Effect |
| --- | --- |
| `StateFlags::{SIZE, POSITION, MAXIMIZED, VISIBLE, DECORATIONS, FULLSCREEN}` | Bitflags; **`Default`/`all()` is every flag** |
| `.with_state_flags(flags)` | Narrow it — restoring `VISIBLE` or `DECORATIONS` fights your own startup logic |
| `.with_filename(s)` | Default is `DEFAULT_FILENAME` = `.window-state.json` in app config dir |
| `.with_denylist(&["splashscreen"])` | Windows that must never persist |
| `.skip_initial_state("label")` | Persist, but do not auto-restore — you call `restore_state` yourself |
| `.map_label(f)` | Collapse several labels onto one saved state |
| `WindowExt::restore_state(flags)` on `Window`/`WebviewWindow` | Manual restore, **after** the window exists |
| `AppHandleExt::save_window_state(flags)` / `.filename()` | Manual save |
| Permissions | `window-state:default` = `allow-filename`, `allow-restore-state`, `allow-save-window-state` |

Gotchas: restore happens *after* window creation, so pair it with `"visible": false` +
`window.show()` or the user watches the window jump. Saved geometry is **not** validated against
the current monitor set — a laptop undocked since last run gets a window off-screen; check
against `available_monitors()` before applying. Reasoning: `references/desktop-ux.md`.

---

## 6. Permission quick-map

| Doing this from JS | Needs |
| --- | --- |
| Custom titlebar buttons | `core:window:allow-close`, `-minimize`, `-toggle-maximize`, `-start-dragging` |
| Creating windows at runtime | `core:webview:allow-create-webview-window` |
| Building menus | `core:menu:default` |
| Building trays | `core:tray:default` |
| Window state save/restore | `window-state:default` |

`core:window`, `core:menu`, `core:tray`, `core:webview` are **core namespaces, not plugins** —
the `core:` prefix is required, so a bare `window:allow-close` matches nothing. There is no
`core:*` wildcard: a `permissions` array takes only concrete identifiers or a permission-set
name such as `core:default`.
Precedence, scopes and why deny wins: `references/security.md`.

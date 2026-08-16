# Plugins — lookup

Verified against **`tauri 2.11.5`**, `tauri-plugin 2.6.3`, `plugins-workspace` branch `v2`,
2026-07-28. Naming is mechanical: crate `tauri-plugin-<prefix>`, npm `@tauri-apps/plugin-<prefix>`,
permission prefix = `Builder::new("<prefix>")` name.

Authoring depth, the `Builder` hook surface, scope types, `PluginHandle` vs. extension traits,
and what each `<prefix>:default` actually grants: **`references/plugins.md`**.

---

## 1. Two names agents get wrong — check these first

| You wrote | Reality | Symptom |
| --- | --- | --- |
| `path` / `tauri-plugin-path` | **`path` is core, not a plugin.** `@tauri-apps/api/path`, `tauri::Manager::path()`, permissions `core:path:*` (inside `core:default`) | `error: unknown plugin path`, or a Cargo failure on `tauri-plugin-path`, or `path:allow-join` silently matching nothing |
| `clipboard` / `clipboard:allow-read-text` | **`clipboard-manager`** is the crate, npm package *and* permission prefix — the docs URL `/plugin/clipboard/` is the trap | Clipboard commands rejected while the capability visibly "has" clipboard permissions |

Same rule for `event`, `app`, `image`, `menu`, `tray`, `webview`, `window`, `resources`: all
**core namespaces** with a `core:` prefix, none of them plugins. Details: `references/plugins.md` §8.

---

## 2. Official inventory

Install: `npm run tauri add <prefix>` (adds crate + npm + registers it), or by hand
`cargo add tauri-plugin-<prefix>` + `npm i @tauri-apps/plugin-<prefix>`.
The **permission you almost always need** column is the *starting* grant, not a safe default —
read `references/plugins.md` §7 for what `<prefix>:default` really contains and §9 for the six
plugins whose default grants less than you assume.

| Prefix | npm | For | Usually need |
| --- | --- | --- | --- |
| `fs` | `@tauri-apps/plugin-fs` | Read/write/watch files, `BaseDirectory`-relative | `fs:default` **+ a scoped `fs:allow-read-*`/`allow-write-*`**; `deny-default` is baked in and unoverridable |
| `dialog` | `@tauri-apps/plugin-dialog` | Native open/save/message dialogs | `dialog:default` |
| `opener` | `@tauri-apps/plugin-opener` | Open URL/path in the default app, reveal in file manager | `opener:default`; add `opener:allow-open-path` **only** if you accept arbitrary-file handoff |
| `shell` | `@tauri-apps/plugin-shell` | Spawn child processes and sidecars | `shell:default` (open only). `shell:allow-execute`/`allow-spawn` need a scoped `args` validator |
| `process` | `@tauri-apps/plugin-process` | Exit / relaunch | `process:default` |
| `os` | `@tauri-apps/plugin-os` | OS, arch, family, locale, version | `os:default`; `os:allow-hostname` is **not** in it |
| `http` | `@tauri-apps/plugin-http` | Rust-side `fetch` via reqwest | `http:default` **+ an explicit origin scope** — the default allows zero origins |
| `store` | `@tauri-apps/plugin-store` | Persistent key/value store | `store:default` |
| `sql` | `@tauri-apps/plugin-sql` | SQLite / MySQL / Postgres via sqlx | `sql:default` is read-only; writes need `sql:allow-execute` |
| `notification` | `@tauri-apps/plugin-notification` | OS notifications, actions, channels | `notification:default` (grants all 16) |
| `updater` | `@tauri-apps/plugin-updater` | Signed app updates | `updater:allow-check` if Rust installs; `updater:default` if the frontend drives it |
| `window-state` | `@tauri-apps/plugin-window-state` | Persist/restore window geometry | `window-state:default` |
| `single-instance` | *(Rust-only)* | Enforce one running instance | none — no commands |
| `persisted-scope` | *(Rust-only)* | Persist `fs` + asset scopes across restarts | none — no commands |
| `autostart` | `@tauri-apps/plugin-autostart` | Launch at login | `autostart:default` |
| `global-shortcut` | `@tauri-apps/plugin-global-shortcut` | System-wide hotkeys, **desktop only** | default grants **nothing** — enumerate `global-shortcut:allow-register`, `allow-unregister`, `allow-is-registered`, `allow-register-all`, `allow-unregister-all` |
| `clipboard-manager` | `@tauri-apps/plugin-clipboard-manager` | Clipboard text/HTML/image | default grants **nothing** — `clipboard-manager:allow-read-text`, `…:allow-write-text` |
| `log` | `@tauri-apps/plugin-log` | Unified Rust + JS logging | `log:default` |
| `deep-link` | `@tauri-apps/plugin-deep-link` | Register the app as a URL-scheme handler | `deep-link:default` |
| `upload` | `@tauri-apps/plugin-upload` | Streamed upload/download with progress | `upload:default` |
| `websocket` | `@tauri-apps/plugin-websocket` | Rust-side WebSocket client | `websocket:default` |
| `stronghold` | `@tauri-apps/plugin-stronghold` | IOTA Stronghold encrypted vault | `stronghold:default` (8 of 11 commands) |
| `positioner` | `@tauri-apps/plugin-positioner` | Move windows to named positions (tray-relative etc.) | `positioner:default` |
| `cli` | `@tauri-apps/plugin-cli` | Parse argv/subcommands; config under `plugins.cli` | `cli:default` |
| `localhost` | *(Rust-only)* | Serve the frontend over localhost HTTP in production | n/a |

Mobile-only, dead code on desktop: `barcode-scanner`, `biometric`, `geolocation`, `haptics`, `nfc`.

**Target-gate the desktop-only ones** or a mobile build compiles code it cannot use:

```toml
[target."cfg(not(any(target_os = \"android\", target_os = \"ios\")))".dependencies]
tauri-plugin-global-shortcut = "2"
```

```sh
cargo add tauri-plugin-updater --target 'cfg(any(target_os = "macos", windows, target_os = "linux"))'
```

### Registration order — two that break silently

```rust
let mut builder = tauri::Builder::default();

#[cfg(desktop)]
{
    // single-instance FIRST, before deep-link / updater / anything else
    builder = builder.plugin(tauri_plugin_single_instance::init(|app, argv, cwd| { /* … */ }));
}
```

`window-state` restores **after** the window exists — pair it with `"visible": false` +
`window.show()`. Both mechanisms: `references/plugins.md` §10.

---

## 3. In-tree plugin — the minimum that compiles and generates its own permissions

Scaffold: `npx @tauri-apps/cli plugin new <name>` (`--no-api` for Rust-only, `--android` / `--ios`
for mobile). In-tree plugins are a normal workspace member consumed by path — Jan ships five this
way (`references/case-studies.md`).

```
crates/tauri-plugin-example/
├── build.rs                          # declares COMMANDS → generates permissions/autogenerated/
├── Cargo.toml                        # links = "tauri-plugin-example"; tauri-plugin as BUILD dep
├── src/{lib.rs,commands.rs,error.rs,scope.rs}
└── permissions/
    ├── default.toml                  # HAND-WRITTEN — what :default grants
    └── autogenerated/                # GENERATED — commit it
        ├── commands/<name>.toml      #   allow-<name> + deny-<name>, one file per command
        └── reference.md
```

`Cargo.toml`:

```toml
[package]
name = "tauri-plugin-example"
links = "tauri-plugin-example"        # convention; try_build() validates it

[dependencies]
tauri = "2"
serde = { version = "1", features = ["derive"] }
thiserror = "2"

[build-dependencies]
tauri-plugin = { version = "2", features = ["build"] }
```

`build.rs` — **this one line is what generates the permissions**:

```rust
const COMMANDS: &[&str] = &["do_thing"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).build();
}
```

Emits `permissions/autogenerated/commands/do_thing.toml` (`allow-do-thing`, `deny-do-thing`) plus
`permissions/autogenerated/reference.md`. **snake_case Rust fn → kebab-case identifier.**

`src/lib.rs`:

```rust
use tauri::{
    plugin::{Builder, TauriPlugin},
    Manager, Runtime,
};

mod commands;

pub struct Example<R: Runtime> {
    _app: tauri::AppHandle<R>,
}

pub trait ExampleExt<R: Runtime> {
    fn example(&self) -> &Example<R>;
}

impl<R: Runtime, T: Manager<R>> ExampleExt<R> for T {
    fn example(&self) -> &Example<R> { self.state::<Example<R>>().inner() }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("example")
        .invoke_handler(tauri::generate_handler![commands::do_thing])
        .setup(|app, _api| {
            app.manage(Example { _app: app.clone() });
            Ok(())
        })
        .build()
}
```

`permissions/default.toml` — hand-written, because *which* generated permissions are on by default
is a design decision:

```toml
"$schema" = "schemas/schema.json"

[default]
description = "Allows doing the thing"
permissions = ["allow-do-thing"]
```

Register it and grant it:

```rust
tauri::Builder::default().plugin(tauri_plugin_example::init())
```

```json
{ "permissions": ["example:default"] }
```

| Fact | Consequence |
| --- | --- |
| Commands are listed in **`build.rs`**, not derived from `src/commands.rs` | Adding `#[command] fn foo` without touching `COMMANDS` produces no permission — every call is rejected |
| `permissions/autogenerated/` is generated but **committed** | A consumer resolving the crate from a registry has no build step of yours to run |
| Errors crossing IPC must be `Serialize` | `thiserror` alone is not enough — impl `serde::Serialize` manually |
| Declaring a scope does nothing by itself | Scope checking is **opt-in inside the command** via `CommandScope<'_, T>` / `GlobalScope<'_, T>` |
| `PluginHandle::app()` is its only method | Expose plugin APIs through an extension trait on `Manager`, not through the handle |
| JS route is `plugin:<name>|<command>` | `invoke('plugin:example|do_thing')` |

Scope schema, typed plugin config (`Builder<R, C>`), `global_api_script_path`, mobile bridges and
the full hook list: `references/plugins.md` §2–§5, §12.

---

## 4. Plugin or plain command?

| Reach for a plugin when | Reach for `#[tauri::command]` when |
| --- | --- |
| The capability is reused across apps, or published | It is one app's business logic |
| You need mobile (Kotlin/Swift) implementations | Desktop only |
| You need lifecycle hooks (`on_navigation`, `on_event`, `on_page_load`) | A function is enough |
| An official plugin already does it well | Three lines of `std::fs` do it, and you want to own the validation |

Default to the command. Owning the command means owning the validation and keeping the capability
file short — this is Rule 8, and `references/plugins.md` §6 has the honest version of the trade.

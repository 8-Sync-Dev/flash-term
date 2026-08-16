# Plugins — the extension model, the official inventory, and when not to reach for it

Baseline for everything below: **`tauri 2.11.5`**, **`tauri-plugin 2.6.3`** (the build-script
crate), official plugins from `github.com/tauri-apps/plugins-workspace` branch `v2`, all
verified 2026-07-27. Plugin crates version *independently* of `tauri` — `tauri-plugin-dialog`
at 2.7.2 next to `tauri` 2.11.5 is normal, not a mismatch. MSRV for the official v2 plugins is
**1.77.2**.

**Scope of this file.** It covers the plugin *as an engineering unit*: how one is assembled,
what its lifecycle hooks can do that nothing else can, how it declares and ships its own
permissions, which official plugins exist and what their defaults really grant, and the
decision of plugin-versus-plain-command.

It does **not** cover the capability/permission model itself — how capabilities are written,
how scopes are enforced, how `deny` beats `allow` across a whole app — that is
`references/security.md`. Here you get only the plugin author's half: the `build.rs` that
generates permission files and the default sets each official plugin publishes. Updater
behaviour (endpoints, signatures, install modes) is `references/build-and-distribution.md`.
Window, tray, menu, dialog and notification *usage* is `references/desktop-ux.md`; this file
covers those plugins only as inventory rows and default-permission traps.

---

## 1. What a plugin actually is

**Mechanism.** A Tauri v2 plugin is up to four artifacts shipped together:

1. a **Cargo crate** (`tauri-plugin-{name}`) that builds a `TauriPlugin<R, C>`;
2. an optional **npm package** (`@tauri-apps/plugin-{name}` for official ones) holding the
   TypeScript bindings that `invoke` the crate's commands;
3. an optional **Android library project** and **Swift package** for mobile;
4. a `permissions/` directory that is part of the crate's published files.

The crate exports a free function `init()` by convention:

```rust
use tauri::{plugin::{Builder, TauriPlugin}, Runtime};

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("example").build()
}
```

The string passed to `Builder::new` is the single most load-bearing identifier in the whole
system. It is simultaneously:

- the **ACL namespace** — permissions are `example:allow-upload`, never `tauri-plugin-example:…`;
- the **IPC route prefix** — the webview calls `invoke('plugin:example|upload', { … })`, with a
  **pipe**, not a slash or a dot;
- the **config key** — `tauri.conf.json` → `plugins.example`.

It is *not* the crate name. `tauri-plugin-window-state` registers as `"window-state"`.

**Why the crate/npm split.** The Rust side is the trust boundary and the npm side is
convenience: a thin typed wrapper over `invoke` so consumers do not hand-write command strings.
The two are separable on purpose — a plugin that exposes no commands and only offers a Rust
extension trait needs no npm package at all, and no capability entry either. `single-instance`
and `persisted-scope` are exactly that shape.

**Trade-offs.** Two artifacts, two version numbers, two publish steps, and one failure mode
that exists only because of the split: a Rust command added without rebuilding and
republishing `dist-js` is invisible to consumers. `guest-js` → `dist-js` is **not** automatic.

**Failure modes.**

- *"`window.__TAURI__.myPlugin` is undefined, but the ESM import works."* → The plugin does not
  ship a global-API IIFE, or `global_api_script_path` is not wired in `build.rs`. Consumers with
  `app.withGlobalTauri: true` get nothing from your plugin unless you provide both. See §6.
- *"I added the TS function, the app says the binding does not exist."* → Stale `dist-js`. Build
  the TypeScript before testing; the official guide says so explicitly and it is the single most
  common plugin-authoring waste of an hour.
- *"`plugin example not found` / command not found at runtime."* → Command string mismatch. The
  route is `plugin:<Builder::new name>|<snake_case_fn_name>`.

**When to deviate.** Skip the npm package entirely (`plugin new --no-api`) whenever the plugin's
consumers are Rust-only. It removes a whole publish channel and a whole class of drift.

**Evidence** — https://v2.tauri.app/develop/plugins/ ·
https://docs.rs/tauri/latest/tauri/plugin/struct.Builder.html · in-tree real example dissected
in `references/case-studies.md` §9.

---

## 2. `tauri::plugin::Builder` — the assembly surface and what each hook is *for*

**Mechanism.** `Builder<R, C>` is the sanctioned way to produce a `TauriPlugin`; the `Plugin`
trait underneath is the escape hatch you should not need. Verified surface at 2.11.5:

| Method | The job it exists to do |
| --- | --- |
| `new(name: &'static str)` | Fixes the ACL/IPC/config namespace (§1). |
| `invoke_handler(f)` | Attaches `tauri::generate_handler![…]` — the webview-callable set. |
| `setup(f)` | Runs once at registration; `f: (&AppHandle<R>, PluginApi<R, C>)`. Manage state, read typed config, start background work, initialise the mobile bridge. |
| `js_init_script(s)` | Inject JS after global-object creation, main frame only. |
| `js_init_script_on_all_frames(s)` | Same, every frame including iframes. |
| `on_navigation(f)` | Returning `false` **cancels** the navigation. The only veto point. |
| `on_page_load(f)` | After the fact. Cannot block. |
| `on_window_ready(f)` | A window was created. |
| `on_webview_ready(f)` | A webview was created. Distinct from the above. |
| `on_event(f)` | Every event-loop `RunEvent`. Where exit handling lives. |
| `on_drop(f)` | Plugin deconstructed — teardown. |
| `register_uri_scheme_protocol(scheme, h)` | Custom protocol, synchronous, all webviews. |
| `register_asynchronous_uri_scheme_protocol(scheme, h)` | Same with a responder you can hand to a worker thread. |
| `try_build()` / `build()` | `Result<_, BuilderError>` / panicking. |

Four of these have no equivalent outside a plugin, and that is the real reason plugins exist:

```rust
use tauri::{plugin::Builder, Manager, RunEvent};
use std::{collections::HashMap, sync::Mutex, time::Duration};

struct Store(Mutex<HashMap<String, String>>);

Builder::new("example")
    .setup(|app, _api| {
        app.manage(Store(Default::default()));
        let app_ = app.clone();                 // must be owned: 'static
        std::thread::spawn(move || loop {
            let _ = app_.emit("tick", ());
            std::thread::sleep(Duration::from_secs(1));
        });
        Ok(())
    })
    .on_navigation(|window, url| {
        // the ONLY place a navigation can be refused
        url.scheme() != "forbidden" && !is_blocklisted(window.label(), url)
    })
    .on_event(|app, event| match event {
        RunEvent::ExitRequested { api, .. } => {
            // last window closed — keep a tray-resident app alive
            api.prevent_exit();
        }
        RunEvent::Exit => {
            let store = app.state::<Store>();
            let dir = app.path().app_local_data_dir().unwrap();
            let _ = std::fs::write(
                dir.join("store.json"),
                serde_json::to_string(&*store.0.lock().unwrap()).unwrap(),
            );
        }
        _ => {}
    })
    .on_drop(|_app| { /* plugin destroyed */ })
```

**Why.** `on_event` + `RunEvent::ExitRequested`/`RunEvent::Exit` is the *only* correct place to
(a) keep a tray-only app alive after its last window closes and (b) flush state on shutdown.
There is no "app will terminate" callback anywhere else. `on_navigation` is the only veto —
`on_page_load` fires after the page is already loading. `register_uri_scheme_protocol` and
`js_init_script` have no non-plugin equivalent at all. If you need any of these four, the
question "plugin or command?" is already answered.

The run-loop model these events come from — what a `RunEvent` is, when the event loop is
running, how `run()` differs from `build()` + `run(closure)` — is `references/architecture.md`.

**Trade-offs.** `on_event` fires for *every* event-loop event, so it sits on the hot path. Per
event allocation, locking, or logging there is a measurable regression in windows with heavy
pointer traffic — this is one of the few places in a Tauri app where a closure body's cost is
proportional to mouse movement. Keep it a match with cheap arms and push work elsewhere.

**Failure modes.**

- *"My tray icon disappears when I close the window."* → `RunEvent::ExitRequested` without
  `api.prevent_exit()`. The app exits with the last window by design.
- *"The app cannot be quit from the window manager / Dock any more."* → `prevent_exit()` called
  unconditionally. Once you veto exit you own the quit path: a tray or menu item calling
  `app.exit(0)` is mandatory, not optional.
- *"`closure may outlive the current function` on the thread I spawned in `setup`."* → You
  captured `&AppHandle`. Clone it; `AppHandle` is cheap to clone and `'static`.
- *"I hooked `on_webview_ready` expecting to see new windows and it fires at odd times."* → The
  guide-level prose and the rustdoc disagree. Rustdoc is authoritative: `on_window_ready` =
  window created, `on_webview_ready` = webview created. Two different events.

**When to deviate.** Implement the `Plugin` trait by hand only when you need behaviour the
builder cannot express (rare, and usually a sign the design wants two plugins). Note that v1's
`Plugin::setup_with_config` no longer exists — config now arrives through `PluginApi` in
`setup`, which is why v1-era plugin code does not compile.

**Evidence** — https://docs.rs/tauri/latest/tauri/plugin/struct.Builder.html ·
https://docs.rs/tauri/latest/tauri/enum.RunEvent.html · https://v2.tauri.app/develop/plugins/

---

## 3. Typed plugin configuration

**Mechanism.** The second generic parameter of `Builder<R, C>` is the deserialized value of
`tauri.conf.json` → `plugins.<name>`:

```rust
use serde::Deserialize;
use tauri::{plugin::{Builder, TauriPlugin}, Runtime};

#[derive(Deserialize)]
pub struct Config { pub timeout: usize }

pub fn init<R: Runtime>() -> TauriPlugin<R, Config> {
    Builder::<R, Config>::new("example")
        .setup(|_app, api| {
            let _timeout = api.config().timeout;
            Ok(())
        })
        .build()
}
```

```json
{ "plugins": { "example": { "timeout": 30 } } }
```

**Why.** Plugin knobs belong in the app's single config file, not duplicated into Rust call
sites, because the same file is read by the CLI and the bundler. It also means a consumer can
retune your plugin without touching Rust.

**Trade-offs.** Config is parsed **at runtime**, not compile time. A typo under
`plugins.<name>` surfaces as a plugin init failure at app start, not a build error — and
because `tauri.conf.json` is compiled into the binary (mental-model idea 5), you find out on a
user's machine. Weigh that against the convenience before making a field required.

**Failure modes.**

- *"Plugin fails to initialise on a clean install but works in my tree."* → A required config
  field with no `#[serde(default)]` and no `plugins.<name>` block. Use
  `Builder::<R, Option<Config>>` to make the whole block optional, and `#[serde(default)]` on
  every field you can defend a default for.
- *"My config block is ignored."* → Wrong key. It is the `Builder::new` name, not the crate
  name — `plugins.window-state`, not `plugins.tauri-plugin-window-state`.

**When to deviate.** For a plugin with many knobs, the documented convention is a **second,
plugin-owned `Builder` struct** with `Default` + fluent setters whose `build()` delegates to
`tauri::plugin::Builder`. `tauri-plugin-global-shortcut` does exactly this
(`Builder::new().with_shortcuts([…])?.with_handler(…).build()`). Prefer that when the knobs are
Rust values (closures, handlers) that cannot live in JSON.

**Evidence** — https://v2.tauri.app/develop/plugins/ ·
https://docs.rs/tauri/latest/tauri/plugin/struct.Builder.html

---

## 4. `PluginHandle` is not the handle you want — state and extension traits

**Mechanism.** `PluginHandle<R>` is deliberately tiny: its only method is `app() -> &AppHandle<R>`.
Plugin APIs are **not** exposed through it. The documented shape is a struct named after the
plugin in PascalCase, `manage`d as app state in `setup`, and reached through an **extension
trait** implemented for every `Manager<R>` — so `App`, `AppHandle`, `Window` and `WebviewWindow`
all get the method:

```rust
pub struct Example<R: Runtime> { app: AppHandle<R>, store: Mutex<HashMap<String, String>> }

impl<R: Runtime> Example<R> {
    pub fn ping(&self) -> String { "pong".into() }
}

pub trait ExampleExt<R: Runtime> { fn example(&self) -> &Example<R>; }

impl<R: Runtime, T: Manager<R>> ExampleExt<R> for T {
    fn example(&self) -> &Example<R> { self.state::<Example<R>>().inner() }
}
```

Every official plugin follows it: `ShellExt::shell()`, `DialogExt::dialog()`,
`NotificationExt::notification()`, `OpenerExt::opener()`, `FsExt::fs_scope()`,
`GlobalShortcutExt::global_shortcut()`, `AppHandleExt::save_window_state()`,
`WindowExt::restore_state()`.

**Why.** Extension traits give discoverable, namespaced access with no global registry, and they
compose: the same plugin can be consumed purely from Rust. That last property has a security
consequence worth internalising — **permissions gate the IPC boundary only**. Calling
`app.shell().sidecar("worker")` from Rust needs no capability entry at all. A plugin used only
from Rust contributes **zero** attack surface to the webview. This is the mechanical reason
Rule 8 ("prefer owning the command over widening a plugin scope") works.

**Trade-offs.** The trait must be imported explicitly, and that produces the single most common
compile error in Tauri v2.

**Failure modes.**

- *"`no method named 'shell' found for struct AppHandle`"* (or `notification`, `dialog`,
  `opener`, `fs_scope`) → missing `use tauri_plugin_shell::ShellExt;`. The method exists; the
  trait is not in scope.
- The same class hits *core* traits in v2 — `emit` needs `tauri::Emitter`, `listen` needs
  `tauri::Listener`, `get_webview_window` needs `tauri::Manager`. In v1 these were inherent
  methods, which is why v1-era snippets appear to be missing imports. Full delta:
  `references/architecture.md` §v1→v2.
- *"State not managed" panic on first call to the extension method.* → `manage` happens in
  `setup`; anything that runs before plugin registration cannot see it. Order your
  `.plugin(…)` calls accordingly.

**When to deviate.** If the plugin's API is a single function with no state, skip the struct and
export a plain `pub fn` from the crate. An extension trait over nothing is ceremony.

**Evidence** — https://docs.rs/tauri/latest/tauri/plugin/struct.PluginHandle.html ·
https://v2.tauri.app/develop/plugins/

---

## 5. How a plugin declares and ships its permissions

This is the plugin author's half of the ACL. The model itself — capabilities, windows, remote
URLs, precedence — is `references/security.md`.

**Mechanism.** Every plugin command is denied by default. A plugin makes access *possible* by
publishing permission files in `permissions/`, which consumers then reference from a capability.
Two of those files you write; the rest are generated.

Generated, from `build.rs`:

```rust
// build.rs  — NOT src/commands.rs, see the failure modes below
const COMMANDS: &[&str] = &["upload", "start_server"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).build();
}
```

`tauri_plugin::Builder::new(&[commands])` emits, per listed command, an `allow-<name>` and a
`deny-<name>` permission into **`permissions/autogenerated/commands/<name>.toml`**, plus a
human-readable **`permissions/autogenerated/reference.md`**. Command names are the snake_case
Rust function names; the generated identifiers are kebab-cased (`read_text_file` →
`allow-read-text-file`). The on-disk layout this produces in a real in-tree plugin is shown in
`references/case-studies.md` §9.

Hand-written, because it is a design decision and not derivable: which of those the plugin's
`default` set grants.

```toml
# permissions/default.toml
"$schema" = "schemas/schema.json"

[default]
description = "Allows uploading files"
permissions = ["allow-upload"]
```

Also hand-written: **scope-only permissions**, which declare no commands and exist purely to
carry scope data —

```toml
# permissions/spawn-node.toml
"$schema" = "schemas/schema.json"

[[permission]]
identifier = "allow-spawn-node"
description = "This scope permits spawning the `node` binary."

[[permission.scope.allow]]
binary = "node"
```

— and permission **sets**, which bundle identifiers under one name (`[[set]]` with
`permissions = ["allow-connect", "allow-send"]`).

If your plugin has a scope type, publish its JSON schema so consumers get autocomplete in their
capability files. The scope struct lives in `src/scope.rs` and is `#[path]`-included by the
build script, which is why `schemars` must appear in **both** `[dependencies]` and
`[build-dependencies]`:

```rust
// build.rs
#[path = "src/scope.rs"]
mod scope;

const COMMANDS: &[&str] = &["upload", "start_server"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .global_scope_schema(schemars::schema_for!(scope::Entry))
        .global_api_script_path("./dist-js/init.js")
        .build();
}
```

Full `tauri_plugin::Builder` surface (crate 2.6.3, feature `build`): `new`,
`global_scope_schema`, `global_api_script_path`, `android_path`, `ios_path`, `build()` (exits on
error), `try_build() -> anyhow::Result<()>`.

Declaring scope does nothing by itself: **scope checking is opt-in inside your command.** The
scopes arrive by dependency injection and the docs recommend checking both levels:

```rust
use tauri::ipc::{CommandScope, GlobalScope};

#[tauri::command]
pub async fn start_server<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    command_scope: CommandScope<'_, Entry>,   // scope attached to this permission entry
    scope: GlobalScope<'_, Entry>,            // plugin-wide scope
) -> Result<(), crate::Error> {
    let _allowed = command_scope.allows();
    let _denied  = command_scope.denies();
    let _global  = scope.allows();
    Ok(())
}
```

**Why it is built this way.** v1's `allowlist` was global and coarse: enabling `fs` enabled it
for every window at every URL. Generating `allow-*`/`deny-*` per command makes the granularity
match the actual unit of risk (one command), and generating it from a list in `build.rs` means
the permission set cannot silently drift from the code — as long as the list is maintained.
`global_api_script_path` exists so `withGlobalTauri` consumers get an IIFE that populates
`window.__TAURI__.<plugin>`; the ESM path does not need it.

**Trade-offs.** Verbosity, and a failure mode that is a runtime rejection with a generic message
rather than a compile error. Every new command costs a `build.rs` line, a `default.toml`
decision, and a capability edit in every consuming app. `try_build()` returns `anyhow::Result`,
so plugin-convention violations arrive as build-script strings, not typed errors — less precise
diagnostics than rustc's.

**Failure modes.**

- ***"My new plugin command returns a permission error."*** This is the classic. A command
  registered in `invoke_handler!` but **not listed in `COMMANDS` in `build.rs`** has no
  `allow-<name>` permission in existence, so no capability can grant it and the ACL rejects it
  at runtime. **The fix is in `build.rs`, not in the capability file** — adding identifiers to a
  capability cannot help, because the identifier does not exist. Symptom variant: the error
  names your command and lists no associated permissions. Add the name to `COMMANDS`, rebuild
  (the build script runs on `cargo build`), commit the regenerated
  `permissions/autogenerated/commands/<name>.toml`. Observed in a real in-tree plugin:
  `references/case-studies.md` §9.
- *"I pasted the autogeneration snippet and got a duplicate `main` / dead code."* → The official
  guide labels that snippet `src/commands.rs` while the code is a `build.rs` `fn main()`. It
  belongs in **`build.rs`**.
- *"Red squiggles in my capability JSON but the build is green."* → Stale `gen/schemas/*.json`.
  They regenerate during `cargo build`; the editor is reading the previous run.
- *"`unresolved crate schemars` — but only in the build script."* → `schemars` missing from
  `[build-dependencies]` while `scope.rs` is `#[path]`-included.
- *"I declared `permission.scope.allow` and it is not enforced."* → No command reads
  `CommandScope`/`GlobalScope`. Scope is data you must act on.
- *"Build script fails with a conventions error."* → `links = "tauri-plugin-<name>"` missing
  from `[package]`; `try_build()` validates it.

**When to deviate.** A plugin with no webview-facing commands (`single-instance`,
`persisted-scope`) needs no `permissions/` directory and no `build.rs` permission list at all.
Do not manufacture one for symmetry.

**Evidence** — https://v2.tauri.app/develop/plugins/ · https://v2.tauri.app/reference/acl/scope/ ·
https://docs.rs/tauri-plugin/latest/tauri_plugin/struct.Builder.html ·
`references/case-studies.md` §9.

---

## 6. Plugin or plain command? — the decision, honestly

**Mechanism of the choice.** A `#[tauri::command]` in your app is a function in
`generate_handler!` governed by your app's capability files. A plugin is a separate crate with
its own namespace, its own permission identifiers, its own scope type and schema, its own
lifecycle hooks, and its own release cadence.

**Reach for a plugin when at least one of these is true:**

1. **You need a lifecycle hook.** `setup`, `on_navigation`, `on_event`, `on_window_ready`,
   `on_drop` are unreachable from a plain command. A command cannot veto navigation or flush
   state at exit. This is the hardest, least arguable criterion.
2. **You need a custom URI scheme or injected JS.** `register_uri_scheme_protocol`,
   `js_init_script` — plugin-only.
3. **You need mobile native code.** The Kotlin/Swift bridge is plugin-shaped: `android_path` /
   `ios_path` in the build script, `desktop.rs`/`mobile.rs` split in `src/`. There is no way to
   bridge to platform native code from a plain command.
4. **You want your own ACL namespace and scope type.** Plain commands are governed by whatever
   your app's capability grants; a plugin gets `<name>:allow-*` identifiers, `CommandScope`/
   `GlobalScope` typed scope, and a published JSON schema consumers can autocomplete against.
   This matters when the surface is large enough that "the app capability" stops being a
   meaningful unit.
5. **It will be reused across apps.** Independent versioning, crates.io + npm distribution, and
   a permission contract other teams can read (`permissions/autogenerated/reference.md`).

**The honest default: most app-specific logic should stay a plain command.** A single command
that reads a file and returns JSON gains nothing from being a plugin and costs a crate, a build
script, a permission file, an npm package, and a version to keep in lockstep. Wrapping app logic
in a plugin because "plugins are the extension mechanism" is the standard over-engineering
failure in this stack. Two thirds of the criteria above are about *distribution* and *mobile*,
not about code organisation — if you are not distributing and not on mobile, you probably need a
module, not a plugin.

**The signal that you have crossed the line** is observable, and it is not "we have a lot of
commands". It is that command names have grown prefixes (`term_*`, `env_*`, `update_*`) that
encode a module system in strings, and merge conflicts concentrate in the `generate_handler!`
block. A real app at ~250 flat commands showing exactly this is analysed in
`references/case-studies.md` §11. Those prefix groups are the plugins you actually want, each
with its own ACL and defaults.

**Trade-offs of choosing plugin.** You add a compile unit and a publish step; refactoring across
the boundary now needs a version bump; and — subtly — you have created a namespace that
consumers can grant *wholesale* via `<name>:default`, which is a wider blast radius than a
hand-picked list of app commands. A plugin makes coarse grants easy for the same reason it makes
fine grants possible.

**Trade-offs of choosing plain command.** No hooks, no scope type, no reuse, and your capability
file grows one entry per command. In exchange your security boundary is a Rust function you
control, which is Rule 8 and the strongest pattern in either case study
(`references/case-studies.md` §3, §11).

**When to deviate from "keep it a command".** If the same command needs to exist in two apps you
own, extract it the *first* time you copy it, not the third. If it needs a lifecycle hook, there
is no deviation to consider — it is a plugin.

**Evidence** — https://v2.tauri.app/develop/plugins/ · `references/case-studies.md` §3, §9, §11.

---

## 7. The official inventory

Repo `github.com/tauri-apps/plugins-workspace`, branch `v2`, directory `plugins/` — 30 plugins
verified 2026-07-27. Naming is mechanical: crate `tauri-plugin-{name}`, npm
`@tauri-apps/plugin-{name}`, permission prefix = directory name = `Builder::new` name.

The `default` column is the exact content of each plugin's `permissions/default.toml`. Read it
before adding `<plugin>:default` to a capability — §8 and §9 exist because these are not what
people assume.

| Prefix | Crate | npm | What it is for | `<prefix>:default` grants |
| --- | --- | --- | --- | --- |
| `fs` | `tauri-plugin-fs` | `@tauri-apps/plugin-fs` | File read/write/watch, `BaseDirectory`-relative | `create-app-specific-dirs`, `read-app-specific-dirs-recursive`, **`deny-default`** |
| `dialog` | `tauri-plugin-dialog` | `@tauri-apps/plugin-dialog` | Native open/save/message dialogs | `allow-message`, `allow-save`, `allow-open` |
| `shell` | `tauri-plugin-shell` | `@tauri-apps/plugin-shell` | Spawn child processes and sidecars | **`allow-open` only** |
| `opener` | `tauri-plugin-opener` | `@tauri-apps/plugin-opener` | Open URL/path in default app, reveal in file manager | `allow-open-url`, `allow-reveal-item-in-dir`, `allow-default-urls` (**not** `allow-open-path`) |
| `process` | `tauri-plugin-process` | `@tauri-apps/plugin-process` | Exit / relaunch the app | `allow-exit`, `allow-restart` |
| `os` | `tauri-plugin-os` | `@tauri-apps/plugin-os` | OS, arch, family, locale, version | `allow-arch`, `allow-exe-extension`, `allow-family`, `allow-locale`, `allow-os-type`, `allow-platform`, `allow-version` (**not** `allow-hostname`) |
| `http` | `tauri-plugin-http` | `@tauri-apps/plugin-http` | Rust-side `fetch` via reqwest | `allow-fetch`, `allow-fetch-cancel`, `allow-fetch-send`, `allow-fetch-read-body`, `allow-fetch-cancel-body` — **no origins** |
| `store` | `tauri-plugin-store` | `@tauri-apps/plugin-store` | Persistent key/value store | all 14 store commands (`allow-load`, `allow-get`, `allow-set`, `allow-save`, …) |
| `sql` | `tauri-plugin-sql` | `@tauri-apps/plugin-sql` | SQLite/MySQL/Postgres via sqlx | `allow-close`, `allow-load`, `allow-select` — **not** `allow-execute` |
| `notification` | `tauri-plugin-notification` | `@tauri-apps/plugin-notification` | OS notifications, actions, channels | **all 16** commands |
| `updater` | `tauri-plugin-updater` | `@tauri-apps/plugin-updater` | Signed app updates → `build-and-distribution.md` | `allow-check`, `allow-download`, `allow-install`, `allow-download-and-install` |
| `window-state` | `tauri-plugin-window-state` | `@tauri-apps/plugin-window-state` | Persist/restore window geometry | `allow-filename`, `allow-restore-state`, `allow-save-window-state` |
| `single-instance` | `tauri-plugin-single-instance` | *(Rust-only)* | Enforce one running instance | *(no commands, no permissions)* |
| `persisted-scope` | `tauri-plugin-persisted-scope` | *(Rust-only)* | Save/restore `fs` + asset scopes across restarts | *(no commands, no permissions)* |
| `autostart` | `tauri-plugin-autostart` | `@tauri-apps/plugin-autostart` | Launch at login | `allow-enable`, `allow-disable`, `allow-is-enabled` |
| `global-shortcut` | `tauri-plugin-global-shortcut` | `@tauri-apps/plugin-global-shortcut` | System-wide hotkeys, desktop only | **empty — nothing** |
| `clipboard-manager` | `tauri-plugin-clipboard-manager` | `@tauri-apps/plugin-clipboard-manager` | Clipboard text/HTML/image | **empty — nothing** |
| `log` | `tauri-plugin-log` | `@tauri-apps/plugin-log` | Unified Rust+JS logging → `debugging-and-testing.md` | `allow-log` |
| `deep-link` | `tauri-plugin-deep-link` | `@tauri-apps/plugin-deep-link` | Register app as URL-scheme handler | `allow-get-current` |
| `upload` | `tauri-plugin-upload` | `@tauri-apps/plugin-upload` | Streamed upload/download with progress | `allow-upload`, `allow-download` |
| `websocket` | `tauri-plugin-websocket` | `@tauri-apps/plugin-websocket` | Rust-side WebSocket client | `allow-connect`, `allow-send` |
| `stronghold` | `tauri-plugin-stronghold` | `@tauri-apps/plugin-stronghold` | IOTA Stronghold encrypted vault | 8 of 11 (**not** `allow-destroy`, `allow-remove-secret`, `allow-remove-store-record`) |
| `positioner` | `tauri-plugin-positioner` | `@tauri-apps/plugin-positioner` | Move windows to named positions (tray-relative etc.) | `allow-move-window`, `allow-move-window-constrained`, `allow-set-tray-icon-state` |
| `cli` | `tauri-plugin-cli` | `@tauri-apps/plugin-cli` | Parse argv/subcommands; config under `plugins.cli` | `allow-cli-matches` |
| `localhost` | `tauri-plugin-localhost` | *(Rust-only)* `[UNVERIFIED: npm package existence not checked]` | Serve the frontend from a localhost HTTP server in production | `[UNVERIFIED]` |

Mobile-only, listed for completeness — wiring any of these on desktop is dead code:
`barcode-scanner`, `biometric`, `geolocation`, `haptics`, `nfc` (crate/npm follow the same
naming; default sets `[UNVERIFIED]`).

**Why this table is worth reading rather than skimming.** The `default` column is a *security
posture*, chosen per plugin by the maintainers, and the choices are not uniform. Three plugins
grant everything (`notification`, `store`), two grant nothing (§8), and several deliberately
withhold exactly the one command you will reach for (§9). Treating `<plugin>:default` as "the
sensible starting set" is wrong in both directions: sometimes it is far more than you need,
sometimes it is useless.

**Trade-offs.** Adding an official plugin is cheap in effort and not free in surface: a crate, a
version to track, and — if you also grant its permissions — an IPC-reachable command set. The
cheapest plugin is one used only from Rust (§4).

**When to deviate from using an official plugin at all.** When three lines of Rust do the job.
`api::file` became `std::fs` in v2 precisely because a plugin was never the right shape for
"read a file"; if you own the command you own the validation (Rule 8). Reach for `fs` when you
genuinely need `BaseDirectory` resolution and watching across platforms, not because you need to
read one config file.

**Evidence** — https://github.com/tauri-apps/plugins-workspace/tree/v2/plugins · each plugin's
`permissions/default.toml` and `permissions/autogenerated/reference.md` on
`raw.githubusercontent.com/tauri-apps/plugins-workspace/v2/plugins/<name>/…` ·
https://v2.tauri.app/reference/acl/core-permissions/

---

## 8. Two names that do not exist, and why agents keep writing them

**`path` is not a plugin.** There is no `plugins/path` directory, no `tauri-plugin-path` crate,
and `npm run tauri add path` fails. Path resolution is **core**: `@tauri-apps/api/path` in JS,
`tauri::Manager::path()` in Rust, permissions `core:path:allow-resolve`,
`core:path:allow-join`, … , aggregated as `core:path:default` inside `core:default`. The same is
true of `event`, `app`, `image`, `menu`, `tray`, `webview`, `window` and `resources` — all core
namespaces with `core:` prefixes, none of them plugins.

*Why the confusion exists:* in v1 these lived under the monolithic `@tauri-apps/api` and the
`allowlist`; v2 moved *most* of that surface into plugins but kept the parts with no external
dependency in core. So the v1→v2 rule "everything moved to a plugin" is false, and it is exactly
the kind of half-true simplification a blog post transmits.

*Symptom:* `error: unknown plugin path` from the CLI, or a Cargo resolution failure on
`tauri-plugin-path = "2"`, or a capability containing `path:allow-join` that silently matches
nothing. Fix: `core:path:*`. The core namespace inventory is in `references/security.md`.

**`clipboard` is `clipboard-manager`.** The documentation feature card says "Clipboard" and the
docs URL is `/plugin/clipboard/`, but the crate, the npm package, and the permission prefix are
all `clipboard-manager`. `clipboard:allow-read-text` matches nothing — and because unmatched
identifiers in a capability are not necessarily loud, you can ship it.

*Symptom:* clipboard commands rejected while the capability visibly "has" clipboard
permissions. Fix: `clipboard-manager:allow-read-text` and friends. And see §9 — the default set
for this plugin grants nothing either, so both mistakes usually appear together.

**Trade-off of the naming.** `clipboard-manager` is more precise (it manages several clipboard
formats, not just text) at the cost of a discoverability gap that the docs' own URL widens.
Nothing you can do but know it.

**Evidence** — https://v2.tauri.app/reference/acl/core-permissions/ ·
https://github.com/tauri-apps/plugins-workspace/tree/v2/plugins

---

## 9. Default permission sets that grant less than you think

Six specific cases. Each is a deliberate maintainer decision, and knowing the *reason* lets you
predict the next one instead of memorising a list.

**`global-shortcut:default` grants zero.** The README states the rationale verbatim: *"No
features are enabled by default, as we believe the shortcuts can be inherently dangerous and it
is application specific if specific shortcuts should be registered or unregistered."* A frontend
that can register a global hotkey can shadow an OS shortcut, or silently claim a key combination
other applications need — from a webview, which is the untrusted side of the boundary. There is
no defensible "safe subset" to enable, so the maintainers enable nothing. You must enumerate
`global-shortcut:allow-register`, `allow-unregister`, `allow-is-registered`, `allow-register-all`,
`allow-unregister-all` as needed. *Symptom:* `global-shortcut:default` present in the capability,
every shortcut call rejected.

**`clipboard-manager:default` grants zero,** same stated reasoning. Clipboard read is an
exfiltration primitive (the user's clipboard routinely holds passwords and tokens) and clipboard
write is a phishing primitive. Both are per-app decisions, so nothing is on by default.

**`sql:default` cannot mutate.** It grants `allow-close`, `allow-load` and `allow-select`, and
omits **`allow-execute`**. The split is between "read the database" and "change the database":
`select` is bounded by what a query can return, while `execute` from a compromised renderer is
arbitrary DDL/DML against your app's own store. *Symptom: reads work, every INSERT/UPDATE/DELETE
is rejected.* Fix if you truly need frontend writes: add `sql:allow-execute` — but the better
answer is usually a `#[tauri::command]` that performs the specific mutation with typed
arguments, which is Rule 8 applied to your database.

**`http:default` allows no origins.** It grants the whole fetch machinery (`allow-fetch`,
`allow-fetch-send`, `allow-fetch-read-body`, the two cancels) and an empty URL scope, so every
request is rejected. This is the right split, because the dangerous parameter of a
Rust-side fetch is not *whether* you can fetch but *what you can reach*: the Rust process is
outside the webview's CORS and same-origin rules, so an unscoped `http` permission is an SSRF
primitive that reaches `localhost` services and cloud metadata endpoints. *Symptom: every
request rejected despite `http:default` being present.* Fix: add a scoped entry naming exact
origins. What that looks like — and what happens when an app allows `https://*:*` and
`http://*:*` — is `references/case-studies.md` §3.

**`shell:default` is `allow-open` only,** with a pre-configured scope permitting `http(s)://`,
`tel:` and `mailto:`. It does not let you spawn anything. The reasoning is that "open this link"
is the overwhelmingly common need and process spawning is a different risk class entirely — see
`references/desktop-ux.md` §shell for why `shell:allow-execute` is the most dangerous permission
in the official set. *Symptom: `shell:default` in the capability, `Command.create(...)` rejected.*
In v2 you should not be using `shell` for links at all; use `opener`.

**`opener:default` omits `allow-open-path`.** It grants `allow-open-url`,
`allow-reveal-item-in-dir` and the `allow-default-urls` scope. Opening a *URL* is bounded by the
scheme scope; opening a *path* hands an arbitrary local file to the OS's default handler, which
for a `.desktop`, `.lnk`, `.bat`, `.command` or registered document type is code execution by
another name. *Symptom: `openUrl` works, `openPath` is rejected.* Fix: add
`opener:allow-open-path`, scoped, and know what you have accepted.

**Bonus, same family: `fs:default` contains `deny-default`,** which blocks app internals (on
Windows, the webview data folder) and cannot be overridden by any `allow-*` — deny always wins.
It grants read on app-specific directories plus `mkdir`, the latter because *"these directories
need to be manually created by the application at runtime"*. *Symptom: `fs:default` present,
reads outside the app dirs denied, and adding `fs:allow-read-text-file` does not help.*

**The generalisable rule.** A maintainer withholds from `default` exactly the commands whose
worst case is unbounded: write where the set otherwise reads (`sql`), reach where the set
otherwise only has machinery (`http`), spawn where the set otherwise only opens (`shell`), and
arbitrary-target where the set otherwise has a scheme allowlist (`opener`). When you meet a
plugin not on this list, predict its `default` by asking which of its commands has an unbounded
worst case — you will usually be right, and you can then verify against its
`permissions/default.toml` in one fetch.

**Trade-off of the design.** Safe defaults mean the first-run experience of every plugin is a
rejection, and the error is a runtime message rather than a compile failure. That cost is paid
by developers once per plugin; the alternative cost is paid by users permanently.

**When to deviate.** Granting a wide default is defensible for a window that renders only
first-party local content *and* when the alternative is a hand-maintained list that will rot.
It is never defensible for a window with `remote` URLs — see `references/security.md` and the
`"remote": { "urls": ["http://*"] }` finding in `references/case-studies.md` §3.

**Evidence** — https://raw.githubusercontent.com/tauri-apps/plugins-workspace/v2/plugins/global-shortcut/README.md ·
per-plugin `permissions/default.toml` · https://v2.tauri.app/plugin/file-system/ ·
`references/case-studies.md` §3.

---

## 10. Registration order and timing: two plugins that break if you get it wrong

### `single-instance` must be registered first

**Mechanism.** The plugin publishes a rendezvous point at init; a later process finds it, hands
over its `argv` and `cwd`, and exits. The first instance receives them in the closure:

```rust
pub fn run() {
    let mut builder = tauri::Builder::default();

    #[cfg(desktop)]
    {
        // FIRST — before deep-link, updater, anything else
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, args, cwd| {
            let _ = app.get_webview_window("main").map(|w| w.set_focus());
            handle_second_instance_argv(app, &args, &cwd);
        }));
    }

    builder
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

**Why order matters.** Registration order is init order. If another plugin is registered first,
the *second* process runs that plugin's `setup` before `single-instance` discovers the first
instance and exits. The official note is explicit: *"The Single Instance plugin must be the
first one to be registered to work well."*

**Trade-offs.** The Linux implementation uses **DBus**, so it inherits DBus sandboxing. On
Windows and macOS there is no equivalent packaging caveat; on Linux there is (below).

**Failure modes.**

- *"A second instance flashes on screen, then exits, and something is duplicated / a deep link
  went to the wrong process."* → Registered after another plugin. The doomed second instance ran
  that plugin's init side effects on its way out.
- *"Works as `.deb` and AppImage; Snap/Flatpak still opens multiple windows."* → Missing DBus
  manifest entry. The service name is `org.{id}.SingleInstance` where `{id}` is your
  `tauri.conf.json` `identifier` with dots **and dashes** replaced by underscores:
  `net.mydomain.MyApp` → `net_mydomain_MyApp` → **`org.net_mydomain_MyApp.SingleInstance`**.
  Declare a matching `slots`/`plugs` pair in `snapcraft.yaml` (`interface: dbus`, `bus: session`)
  or the Flatpak equivalent. Packaging mechanics: `references/build-and-distribution.md`.
- *"Nothing to add to my capability and no permission identifier exists."* → Correct. It has no
  commands. Do not invent `single-instance:default`.

**When to deviate.** Do not use it at all for an app that is legitimately multi-document and
where each window is an independent session; enforcing single-instance there costs you the
ability to open two projects side by side.

### `window-state` restores *after* the window exists

**Mechanism.** `tauri_plugin_window_state::Builder::default().build()` saves geometry on close
and restores it on next launch; `StateFlags` selects which properties. Manual control is via the
extension traits — `AppHandleExt::save_window_state(StateFlags::all())` writes every open
window, `WindowExt::restore_state(StateFlags::all())` reads one.

**Why it is a plugin and not app code.** Restoring geometry needs to hook window creation *and*
app exit, keep per-label bookkeeping, and write to a platform-appropriate location. That is the
exact shape a plugin exists for; doing it in app code means reimplementing the exit flush.

**Trade-offs and the failure mode they cause.** Restoration happens **after** window creation.
The window is created at its configured size and position, then moved and resized.

- *Symptom: the window appears at 800×600, centred, then visibly snaps to the saved position and
  size.* Official fix, and the only one: create the window with **`visible: false`** — the plugin
  shows it once the state is applied. A real app doing this, with the window shown explicitly
  from `setup()`, is `references/case-studies.md` §10.
- *Symptom: the window restores offscreen.* The saved monitor is no longer attached. Pair with
  `WebviewWindowBuilder::prevent_overflow()` or validate against `available_monitors()` before
  restoring — see `references/desktop-ux.md` §DPI.

**When to deviate.** If your app has exactly one window whose size never matters, skip the
plugin; if it has many transient windows, restrict `StateFlags` rather than persisting geometry
for windows the user never positions deliberately.

**Evidence** — https://v2.tauri.app/plugin/single-instance/ ·
https://v2.tauri.app/plugin/window-state/ ·
https://raw.githubusercontent.com/tauri-apps/plugins-workspace/v2/plugins/window-state/permissions/default.toml ·
`references/case-studies.md` §10.

---

## 11. Global shortcuts — the plugin whose API shape is a warning

**Mechanism.** Desktop only (Android/iOS unsupported), so target-gate the dependency and the
registration:

```toml
# src-tauri/Cargo.toml
[target."cfg(not(any(target_os = \"android\", target_os = \"ios\")))".dependencies]
tauri-plugin-global-shortcut = "2"
```

```rust
tauri::Builder::default()
    .setup(|app| {
        #[cfg(desktop)]
        {
            use tauri::Emitter;
            use tauri_plugin_global_shortcut::{Code, Modifiers, ShortcutState};

            app.handle().plugin(
                tauri_plugin_global_shortcut::Builder::new()
                    .with_shortcuts(["ctrl+d", "alt+space"])?
                    .with_handler(|app, shortcut, event| {
                        if event.state != ShortcutState::Pressed { return; }   // see below
                        if shortcut.matches(Modifiers::CONTROL, Code::KeyD) {
                            let _ = app.emit("shortcut-event", "Ctrl+D");
                        }
                    })
                    .build(),
            )?;
        }
        Ok(())
    })
```

**Why registration happens inside `setup` via `app.handle().plugin(…)`** rather than `.plugin(…)`
on the outer builder: that form can be `#[cfg(desktop)]`-gated and can use `?`, which the
builder-chain form cannot. This is the documented pattern, and it generalises to any plugin whose
construction is fallible or platform-conditional.

**Trade-offs.** Registering a system-wide hotkey takes it away from every other application,
including the OS. There is no arbitration and no "already taken" negotiation beyond a
registration failure. Global shortcuts are the least polite thing a desktop app can do; prefer
menu accelerators, which are scoped to your app — see `references/desktop-ux.md` §menus and
§ergonomics.

**Failure modes.**

- *"My shortcut action runs twice per keypress."* → The handler fires for both
  `ShortcutState::Pressed` and `Released`. Check the state.
- *"`global-shortcut:default` is in my capability and nothing works."* → §9. The default set is
  empty by design.
- *"The accelerator string my menu uses does not work here."* → Two grammars. The JS API takes
  Electron-style `CommandOrControl+Shift+C`; Rust `with_shortcuts` takes `"ctrl+d"`. Do not
  assume the menu accelerator syntax transfers.

**When to deviate.** A launcher-style app (`alt+space` to summon) has no alternative — that *is*
the product. A document app registering `Ctrl+S` globally is a bug.

**Evidence** — https://raw.githubusercontent.com/tauri-apps/plugins-workspace/v2/plugins/global-shortcut/README.md ·
https://raw.githubusercontent.com/tauri-apps/plugins-workspace/v2/plugins/global-shortcut/permissions/autogenerated/reference.md

---

## 12. A complete custom plugin — the skeleton that generates its own permissions

Scaffold with `npx @tauri-apps/cli plugin new [name]` (`--no-api` for Rust-only, `--android` /
`--ios` for mobile). The generated layout, and what each file is *for*:

```
tauri-plugin-example/
├── build.rs             # declares COMMANDS → generates permissions/autogenerated/
├── Cargo.toml           # tauri + links key; tauri-plugin as a BUILD dependency
├── package.json         # npm side; recommended name: @scope/plugin-example
├── src/
│   ├── lib.rs           # init(), state, extension trait, error type
│   ├── commands.rs      # thin IPC layer only
│   ├── desktop.rs       # desktop implementation
│   ├── mobile.rs        # mobile implementation (Kotlin/Swift bridge)
│   ├── models.rs        # shared serde structs
│   ├── scope.rs         # scope entry type, #[path]-shared with build.rs
│   └── error.rs         # error type + manual Serialize
├── permissions/
│   ├── default.toml                  # HAND-WRITTEN: what :default grants
│   ├── spawn-node.toml               # HAND-WRITTEN: scope-only permission
│   └── autogenerated/                # GENERATED: commands/*.toml + reference.md — commit it
├── guest-js/index.ts    # TS source
├── dist-js/             # built output — must be rebuilt before testing
├── android/  ios/       # native library projects
└── package.json
```

`Cargo.toml`:

```toml
[package]
name = "tauri-plugin-example"
version = "0.1.0"
edition = "2021"
rust-version = "1.77.2"
links = "tauri-plugin-example"      # plugin convention; try_build() validates it

[dependencies]
tauri = "2"
serde = { version = "1", features = ["derive"] }
thiserror = "2"
schemars = "0.8"

[build-dependencies]
tauri-plugin = { version = "2", features = ["build"] }
schemars = "0.8"                    # needed because build.rs #[path]-includes src/scope.rs
```

`build.rs` and `src/scope.rs` are in §5. `permissions/default.toml` and
`permissions/spawn-node.toml` are in §5. `src/commands.rs`:

```rust
use tauri::{
    command,
    ipc::{Channel, CommandScope, GlobalScope},
    AppHandle, Runtime, Window,
};
use crate::scope::Entry;

#[command]
pub async fn upload<R: Runtime>(
    _app: AppHandle<R>,
    _window: Window<R>,
    on_progress: Channel<u32>,
    url: String,
) -> Result<(), crate::Error> {
    let _ = url;
    on_progress.send(100)?;
    Ok(())
}

#[command]
pub async fn start_server<R: Runtime>(
    _app: AppHandle<R>,
    command_scope: CommandScope<'_, Entry>,
    scope: GlobalScope<'_, Entry>,
) -> Result<(), crate::Error> {
    // check BOTH levels — the docs' explicit recommendation
    let _cmd_allowed = command_scope.allows();
    let _cmd_denied  = command_scope.denies();
    let _global      = scope.allows();
    Ok(())
}
```

`src/lib.rs` — state, extension trait, error, hooks, `init()`:

```rust
use serde::Deserialize;
use std::{collections::HashMap, sync::Mutex};
use tauri::{
    plugin::{Builder, TauriPlugin},
    Manager, RunEvent, Runtime,
};

mod commands;
mod scope;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Tauri(#[from] tauri::Error),
}

// Errors crossing IPC must be Serialize. thiserror alone is not enough.
impl serde::Serialize for Error {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(self.to_string().as_ref())
    }
}

#[derive(Deserialize)]
pub struct Config {
    #[serde(default = "default_timeout")]
    pub timeout: usize,
}
fn default_timeout() -> usize { 30 }

pub struct Example<R: Runtime> {
    app: tauri::AppHandle<R>,
    store: Mutex<HashMap<String, String>>,
}

impl<R: Runtime> Example<R> {
    pub fn ping(&self) -> String { "pong".into() }
}

pub trait ExampleExt<R: Runtime> {
    fn example(&self) -> &Example<R>;
}

impl<R: Runtime, T: Manager<R>> ExampleExt<R> for T {
    fn example(&self) -> &Example<R> { self.state::<Example<R>>().inner() }
}

pub fn init<R: Runtime>() -> TauriPlugin<R, Config> {
    Builder::<R, Config>::new("example")
        .invoke_handler(tauri::generate_handler![
            commands::upload,
            commands::start_server
        ])
        .setup(|app, api| {
            let _timeout = api.config().timeout;
            app.manage(Example {
                app: app.clone(),
                store: Default::default(),
            });
            Ok(())
        })
        .on_navigation(|_window, url| url.scheme() != "forbidden")
        .on_event(|_app, event| {
            if let RunEvent::Exit = event { /* flush */ }
        })
        .build()
}
```

`guest-js/index.ts` — note the `plugin:example|` route and that `Channel` is the streaming
primitive (payload design and channel semantics: `references/ipc-and-commands.md`):

```ts
import { invoke, Channel } from '@tauri-apps/api/core';

export async function upload(
  url: string,
  onProgressHandler: (progress: number) => void,
): Promise<void> {
  const onProgress = new Channel<number>();
  onProgress.onmessage = onProgressHandler;
  await invoke('plugin:example|upload', { url, onProgress });
}

export async function startServer(): Promise<void> {
  await invoke('plugin:example|start_server');
}
```

Consumer wiring — three files, all three required:

```rust
use tauri_plugin_example::ExampleExt;

tauri::Builder::default()
    .plugin(tauri_plugin_example::init())
    .setup(|app| { println!("{}", app.example().ping()); Ok(()) })
```

```jsonc
// tauri.conf.json
{ "plugins": { "example": { "timeout": 30 } } }

// src-tauri/capabilities/default.json
{ "permissions": ["core:default", "example:default", "example:allow-spawn-node"] }
```

**Why this shape.** `commands.rs` stays a thin IPC-facing layer and the logic lives in plain Rust
modules underneath, which is what lets unit tests reach it without a Tauri runtime — the
`commands` / `db` / `state` / `error` / `utils` split in a real in-tree plugin, and its
`build.rs`, are dissected in `references/case-studies.md` §9. Read that instead of treating this
skeleton as the only example: it shows the same structure under production pressure, at a
different Tauri version, with the permission-generation consequence spelled out.

**Trade-offs.** This is roughly ten files and two publish channels for what may be three
commands. Re-read §6 before committing to it.

**Failure modes** (beyond §5's permission trap): errors that do not implement `Serialize` fail to
compile at the `#[command]` expansion with a confusing message; a `Channel` sent after the
webview navigated away errors rather than panicking, so propagate it (`on_progress.send(…)?`)
instead of `unwrap()` as the guide does.

**When to deviate.** Rust-only plugin → drop `guest-js`, `dist-js`, `package.json`,
`global_api_script_path`, and the whole npm publish path. No scope type → drop `scope.rs`,
`schemars` from both dependency sections, and `global_scope_schema`.

**Evidence** — https://v2.tauri.app/develop/plugins/ ·
https://docs.rs/tauri-plugin/latest/tauri_plugin/struct.Builder.html ·
`references/case-studies.md` §9.

---

## 13. Versioning, distribution, and the v1 legacy you will meet in blog posts

**Mechanism.** Official plugins version independently of `tauri` and of each other, tracking the
`2.x` line; pin `tauri-plugin-foo = "2"` and let Cargo resolve. The official READMEs name three
install channels in ascending trust: crates.io + npm; git tags or revision hashes ("most
secure"); git submodule + file protocol ("most secure, but inconvenient").

**Why the version independence.** A plugin that needs a fix should not wait for a `tauri` release,
and a `tauri` release should not force 30 plugin releases. The cost is that "which version am I
on" has no single answer.

**Trade-offs / failure modes.**

- *"I pinned `tauri = "2.0.0"` so I am on 2.0.0."* You are not. Cargo resolves `^2.0.0`; you will
  build against 2.11.x. The official doc snippets say `"2.0.0"`. The practical consequence is
  benign but confusing in the opposite direction from usual: methods you "know" do not exist yet
  (`show_menu_on_left_click`) do compile.
- *"`tauri-plugin-dialog` is 2.7.2 but `tauri` is 2.11.5 — is that a mismatch?"* No. Expected.
- *"A consumer's `dist-js` does not have my new function."* Publish the crate and the npm package
  in lockstep. A Rust command without a rebuilt/republished `dist-js` is invisible.
- Commit `permissions/autogenerated/reference.md`. It is generated, and it is also the
  human-readable permission contract your consumers read when writing capabilities. A repo
  without it forces every consumer to read your `build.rs`.

**v1 → v2, plugin-relevant only.** The full delta table is `references/architecture.md` §v1→v2;
these four items are what makes v1-era plugin content actively misleading:

- The whole `tauri::api` module is gone. `api::dialog` → `tauri-plugin-dialog`, `api::http` →
  `tauri-plugin-http`, `api::shell` / `api::process::Command` → `tauri-plugin-shell`, `api::file`
  → **`std::fs`** (no plugin), `api::path` → `tauri::Manager::path` (**core**, not a plugin).
  `clipboard_manager`, `get_cli_matches`, `global_shortcut_manager` became plugins.
  `Manager::fs_scope` → `tauri_plugin_fs::FsExt`.
- npm package names changed shape: v1 plugins were `tauri-plugin-<name>-api` installed from git;
  v2 official plugins are `@tauri-apps/plugin-<name>` from npm.
- `tauri.allowlist` no longer exists; a v1 post's "enable the fs allowlist" has no v2 translation
  beyond "write a capability" — `references/security.md`.
- `Plugin::setup_with_config` was removed; config reaches `setup` through `PluginApi` (§3).

**When to deviate from pinning `"2"`.** Pin an exact version, or a git revision, when a plugin is
load-bearing and you cannot absorb a surprise minor bump between your last test and your next
release build. One case study ships a `2.0.0-rc` plugin in production
(`references/case-studies.md` header) — the lesson there is not "never pin an rc" but "know that
you did".

**Evidence** — plugins-workspace READMEs · https://docs.rs/tauri/latest/tauri/ (version banner) ·
https://v2.tauri.app/start/migrate/from-tauri-1/ · `references/case-studies.md`.

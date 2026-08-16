# Debugging and Testing — seeing what is actually happening

Baseline: **`tauri 2.11.5`**, verified 2026-07-28. Error strings are quoted from the crate
source on disk (`tauri-2.11.5/src/…`), not paraphrased.

**§triage** — the bug is in front of you; symptom → cause → fix, no instrumentation yet.
**§diagnostics** — triage did not converge; make the system tell you the truth.
**§testing** — what is worth automating, and what is not.

Each fact lives in exactly one file: ACL and CSP semantics → `references/security.md`; per-engine
divergence → `references/cross-platform.md`; profiling → `references/performance.md`; CI and
signing → `references/build-and-distribution.md`; IPC mechanics → `references/ipc-and-commands.md`.

---

## triage

**Two questions route everything.**

1. **Webview or Rust process?** Open the inspector (§devtools). Populated DOM and clean console
   means the fault is below the IPC line; empty DOM means nothing below it matters yet.
2. **Does it reproduce under `tauri dev`?** If not, go straight to §"works in dev, broken in
   prod" — a different failure class with a shorter list of causes.

Getting these backwards is the standard wasted afternoon: an hour debugging commands on a bug
that was a 404 on `index.html`.

### Blank white window

Window opens, correctly sized and titled, renders nothing. Four causes by frequency. **Read the
Network panel, then the Console** — one of these is visible in ten seconds.

**1. The frontend was never built.** `tauri build` runs `beforeBuildCommand`, then embeds
whatever sits at `frontendDist`. A failed build, or no `beforeBuildCommand` where you assumed
one, embeds a stale or empty directory silently.
*Symptom:* 404 on `index.html` or the hashed bundle; dev is fine because dev loads `devUrl`.
*Fix:* build it; make `beforeBuildCommand` non-optional.

**2. `frontendDist` is misconfigured.** It resolves **relative to `src-tauri/`**, not the
project root — a Vite project emitting to `<root>/dist` needs `"../dist"`, while `"dist"`
silently means `src-tauri/dist`, which does not exist.
*Symptom:* identical to cause 1 — check config before rebuilding.
*Fix:* correct the path; confirm the file exists at the resolved location.

**3. Absolute asset paths.** Embedded assets are served from `tauri://localhost` (macOS, Linux)
or `http://tauri.localhost` (Windows, Android). A bundler emitting `/assets/index.js` assumes a
server rooted at `/`; frameworks expecting a prefix (Vite `base`, Next.js `basePath`) resolve to
nothing.
*Symptom:* HTML loads 200, JS/CSS 404. *Fix:* set a relative base (`base: './'`). Also why a
Tauri app is not "your website in a window" — `references/architecture.md`.

**4. A CSP violation blocked the entry script.** The document parsed, the script was refused,
nothing mounted.
*Symptom:* `Refused to execute inline script…` naming a directive — distinctive because the DOM
contains your `<div id="root">` and nothing else.
*Fix:* fix the **source**, not the policy. Inline scripts and `eval` are what a strict CSP
exists to stop; widening it to clear a blank window trades a visible bug for an invisible one.
Policy model: `references/security.md`.

**When to deviate.** On Linux a blank window with a *populated* DOM is the DMA-BUF renderer
instead, fixed by an environment variable set before the event loop starts
(`references/cross-platform.md` §Linux, `references/case-studies.md` §8). Check the DOM first so
you can tell these apart.

### "works in dev, broken in prod"

Highest-value section here: the loop is minutes per iteration, so guessing is expensive. Every
cause below is a **structural difference between the two modes**, which is why they enumerate.

Root difference: **in `tauri dev` the frontend is served by your dev server over `http://` from
`devUrl`; in `tauri build` it is served by Tauri from memory over the custom protocol.**
Different origin, scheme, headers, path resolution — the rest are corollaries.

**1. `devUrl` vs `frontendDist` — different origin, different everything.**
*Symptom:* `localStorage`/`IndexedDB` look empty, cookies vanish, CORS starts failing,
`fetch('/api/…')` stops resolving.
*Cause:* `http://localhost:1420` and `tauri://localhost` are different origins — different
storage partitions, different base for root-relative URLs.
*Fix:* never depend on the dev origin. Absolute URLs routed through a Rust command or
`tauri-plugin-http` so webview CORS does not apply; durable state is Rust-side or a store
plugin, not `localStorage`. Windows v1→v2 variant: `references/cross-platform.md` §Windows.

**2. CSP ships as a response header on assets *Tauri* serves — so a dev server bypasses it.**
*Symptom:* zero CSP errors for weeks, an avalanche on first `tauri build`.
*Cause:* the header is attached by Tauri's own asset protocol handler
(`src/protocol/tauri.rs:182-183`, `asset.csp_header`); when the webview loads your Vite server
directly, Tauri never touches that response, so you have never exercised the policy you ship.
*Fix:* set `app.security.devCsp` equal to `app.security.csp`. The config semantics invert the
folklore — `csp` *"will be injected on all HTML files on the built application. If `devCsp` is
not specified, this value is also injected on dev"* (`tauri-utils-2.9.3/src/config.rs:2896`).
People are bitten by the header mechanism, not the default, so set `devCsp` explicitly.

**3. Assets on disk are not assets that got embedded.**
*Symptom:* 404 in the built app for a path demonstrably on disk.
*Cause:* anything referenced dynamically — a string-built image path, a lazily `import()`ed
chunk the bundler could not see statically, a file you expected next to the binary — exists in
dev because the dev server has a filesystem, and not in prod because the bundle is a static map.
*Fix:* frontend files go through the bundler; Rust-owned files go in `bundle.resources` and
resolve via `app.path().resource_dir()` — never relative to the working directory, which is your
shell in dev and unpredictable in prod.

**4. `withGlobalTauri` differences.** Defaults to **`false`** (`config.rs:3074-3075, 4470`); when
true the API is injected on `window.__TAURI__`.
*Symptom:* `window.__TAURI__ is undefined` in the built app — or the mirror image, code that
works in prod and breaks under a browser-based test run.
*Cause:* the flag is per-config, so a `tauri.<platform>.conf.json` or CI-overridden config can
differ from your machine's. Separately, `window.__TAURI_INTERNALS__` is an internal the mock
layer and the real runtime shape differently.
*Fix:* import from `@tauri-apps/api/core`, leave the default, and reserve the global for a
plain-HTML frontend with no bundler.

**5. Debug output is stripped, so prod cannot tell you anything.**
*Symptom:* "it fails on the user's machine and there is nothing in any log."
*Cause:* `#[cfg(debug_assertions)]` blocks, `debug_assert!` and `println!` to a console that does
not exist under `windows_subsystem = "windows"` all vanish, and `strip = true` removes the
symbols a backtrace needs.
*Fix:* **`tauri build --debug`** produces a bundled app with `debug_assertions` on and the
inspector enabled, at `src-tauri/target/debug/bundle` — prod's packaging, dev's tooling. Then
ship a real log file so you never need it again (§diagnostics).

**Trade-off.** Closing this gap costs dev-loop convenience: with `devCsp` set and relative bases,
dev is less forgiving. That is the point — a dev environment more permissive than production is
a bug generator.

### Command not found / invoke rejects

The rejection is a string, and the string is precise. Read it literally.

**`Command {name} not found`** (`src/webview/mod.rs:1905,1911`) — the invoke handler ran and
nothing matched. *Causes by frequency:* missing from `generate_handler![]`; JS name does not
match the Rust `fn` identifier (Tauri matches the identifier, not a string you pick); a
**plugin** command invoked without its `plugin:` prefix; or registered on a second `Builder`
that is not the one being run. *Fix:* grep the handler list for the exact identifier — at ~250
commands (`references/case-studies.md` §11) that is the only reliable method. Keeping
registration from drifting is `references/ipc-and-commands.md`.

**`{cmd} not allowed. Command not found`** — different failure, similar words. This is the ACL
layer (`src/ipc/authority.rs:432` with the detail at `:404`): the command exists in the
namespace but **no permission anywhere references it**.

**Resolves, but the value is wrong.** Not an error path. Argument names convert to `camelCase`
by default — Rust `file_path` is `filePath` in the payload — and a mismatch deserializes to a
default or fails quietly depending on your types. `references/ipc-and-commands.md`.

### Permission denied at runtime

The command exists and is registered; the ACL refused it. The wording names which of four
things to fix (all `src/ipc/authority.rs`):

| Message shape | Meaning |
| --- | --- |
| `{cmd} not allowed. Permissions associated with this command: {list}` (`:432`+`:405`) | The permission exists; you have not granted it. The list names what to add. |
| `{cmd} not allowed. Command not found` (`:432`+`:404`) | No permission anywhere references it — usually a plugin whose permissions were never generated. |
| `{cmd} not allowed on window "{label}"` (`:356`) | Granted, but not to *this* window: a capability's `windows` list omits the label. |
| `{cmd} not allowed on origin [{origin}]. Please create a capability that has this origin on the context field.` (`:414`) | Granted for local context, called from a remote one. |

**Fix — and the trap.** The message names the missing permission, so the mechanical fix is
obvious and frequently wrong. Adding it is correct only if it is the narrowest thing that
works; the message will happily point at `fs:default` when what you needed was your own
three-line command with a validated path. Rule 8 of `SKILL.md` exists for this moment. The
model is `references/security.md`; the message→capability lookup is
`cheatsheets/capabilities-permissions.md`.

The `not allowed on origin` variant deserves separate suspicion: a remote context in a capability
that also carries filesystem, shell or process permissions is the shape of the worst class of
Tauri vulnerability (`references/case-studies.md` §3).

### App exits immediately with no window

The most information-poor failure in the stack; the causes are unrelated to each other.

**1. A panic in `setup()` or during `Builder::build`** — by a wide margin the most common. Every
`?` in the setup closure is an exit path, and `.expect()` on a missing boot resource crashes
before any window shows.
*Symptom:* under `windows_subsystem = "windows"` there is no console, so the message goes
nowhere and the process disappears.
*Fix:* run the binary from a terminal — `src-tauri/target/release/<app>` — for stderr, plus
`RUST_BACKTRACE=1` under `panic = "abort"` (§the panic-visibility trap). A boot sequence to
model yours on: `references/case-studies.md` §10.

**2. A second instance exiting by design.** With `tauri-plugin-single-instance`, launching over
a running instance is *supposed* to exit after handing over argv.
*Symptom:* "only fails when it is already open" — or an invisible existing instance
(tray-minimised, or a zombie from an earlier crash). *Fix:* check the process list first.

**3. Missing runtime dependency** — WebView2 absent on an old Windows install, a WebKitGTK `.so`
missing on Linux. Exits before the first frame, machine-specific. *Fix:* runtime matrix in
`references/cross-platform.md`; WebView2-bootstrapper installer configs in
`references/build-and-distribution.md`.

**4. The window is created but never shown.** Not a crash — the process is alive, which is the
tell that separates this from 1–3 instantly.
*Cause:* `"visible": false` plus a `show()` gated behind an event that never fires — the common
splash-screen / "wait for frontend ready" pattern, which deadlocks when the frontend fails to
boot. Window lifecycle: `references/desktop-ux.md`.

---

## diagnostics

Triage handles failures with a recognisable shape; everything else needs the system to report
on itself. Principle: **make the process talk before you attach anything to it.** A debugger on
the core process is legitimate, but it is the fourth thing to try.

### devtools

**Two distinct mechanisms.** Conflating them produces the perennial "I enabled devtools and
nothing happened."

**1. The `devtools` Cargo feature — whether the inspector is *compiled into* the binary.** From
the crate's feature list: *"Enables the developer tools (Web inspector) and
`window::Window#method.open_devtools`. Enabled by default on debug builds. On macOS it uses
private APIs, so you can't enable it if your app will be published to the App Store."* Present
automatically under `tauri dev` and `tauri build --debug`; **absent from a release build**
unless you opt in with `tauri = { version = "2.11.5", features = ["devtools"] }`.

**2. `WebviewWindow::open_devtools()` / `close_devtools()` — whether it is *currently open*.**
Runtime calls, verified on `WebviewWindow` in 2.11.5 alongside `is_devtools_open() -> bool`.
They are no-ops if mechanism 1 did not compile the inspector in.

**Which applies to "how do I get devtools in a production build"?** Mechanism 1 — a build
configuration change, not a code change. Mechanism 2 only decides *when* the window appears;
without the feature there is nothing to open. In dev you need neither: right-click → Inspect
Element, or `Ctrl+Shift+I` (Linux/Windows) / `Cmd+Option+I` (macOS).

ZUS wires both correctly (`src-tauri/src/lib.rs:505-511`): the runtime call sits behind the same
switch as the compile-time capability, so they cannot drift apart.

```rust
// tauri 2.11.5 — the runtime half, gated on the compile-time half
#[cfg(feature = "devtools")]
if let Some(window) = app.get_webview_window("main") {
    window.open_devtools();
}
```

**Why shipping it enabled has a cost.**

- **macOS App Store eligibility is forfeited.** The devtools API is private on macOS; the feature
  links private APIs and review rejects it. Same class of decision as `macOSPrivateApi` for
  transparency — `references/cross-platform.md` §macOS links here for this reason.
- **You hand an attacker a console inside your trust boundary.** The inspector executes arbitrary
  JS in your webview's origin, so it can call `invoke` with your invoke key and capabilities:
  every registered command becomes reachable by anyone at the machine. On a kiosk or shared
  workstation that is a real escalation.
- **It is a support-cost trade, sometimes worth taking** for an internal tool — but ship it as a
  separate internal build channel, not a flag flipped for everyone.

**When to deviate.** For a one-off production diagnosis, `tauri build --debug` is almost always
better than shipping the feature (§"works in dev, broken in prod", cause 5).

### `tauri-plugin-log`

One `log` facade for both sides; Rust `log::info!` and the JS API feed the same dispatcher,
which fans out to **targets**. `TargetKind` variants (verified, `tauri-plugin-log 2.9.0`):
`Stdout`, `Stderr`, `Folder`, `LogDir`, `Webview`, `Dispatch`. `Webview` forwards to the
frontend over the `log://log` event.

| Target | Buys | Costs |
| --- | --- | --- |
| `Stdout` | Visible in the `tauri dev` terminal, free | Nothing at all in a bundled Windows GUI app — there is no console |
| `Webview` | Rust and frontend logs interleaved on one timeline | Only as available as the inspector; adds IPC per line, so never leave at `Trace` |
| `LogDir` | The only target that survives the user closing the app — what a bug report contains | Disk, rotation, and a privacy obligation |

**Where the file lands.** `LogDir` resolves to the OS log directory for your `identifier` — the
same path `app.path().app_log_dir()` returns (verified on `PathResolver`, 2.11.5):
`%APPDATA%\<identifier>\logs` on Windows, `~/Library/Logs/<identifier>` on macOS,
`$XDG_DATA_HOME/<identifier>/logs` on Linux. **Resolve it at runtime and print it**; never
hardcode it, because `identifier` is part of the path and moves when the bundle identifier does.

`Builder` (2.9.0): `.target(…)` adds and `.targets(…)` replaces wholesale, `.level(…)` sets the
global filter and `.level_for(module, level)` a per-module one, `.max_file_size(bytes)` with
`.rotation_strategy(…)` bounds disk cost.

**A real gap worth naming.** ZUS registers the log plugin **only** under
`if cfg!(debug_assertions)` (`src-tauri/src/lib.rs:497-503`), so the shipped release build has no
logging and a user-reported crash produces nothing to read. Combined with `panic = "abort"`
(below), production failure in ZUS is invisible by construction. The fix is not "log everything
in prod" — register unconditionally with `LogDir` at `Warn`/`Info`, keeping the noisy `Stdout`
and `Webview` targets behind `debug_assertions`.

**Obligation.** A log file that outlives the process is one you now own. Never log arguments
wholesale — `format!("{:?}", req)` on a struct that later gains a token field is how credentials
reach disk. Bound the size; treat the directory as user data for deletion.

### `RUST_LOG`, `RUST_BACKTRACE`, and the Linux rendering variables

**`RUST_BACKTRACE=1`** turns a panic message into a located panic, and under `panic = "abort"`
it is the only thing that turns one into anything usable. But `strip = true` — which both ZUS
and Jan set (`references/case-studies.md` §12) — removes the symbols, so a release backtrace is
bare addresses. **Keep an unstripped copy of every binary you ship**, or the backtrace a user
sends is undecodable. Documented as `RUST_BACKTRACE=1 tauri dev`; it applies equally to running
the built binary from a terminal.

**`RUST_LOG`** filters the `log`/`tracing` facades. With the `tracing` Cargo feature you get
Tauri's own window-startup, plugin-registration, IPC and updater spans — the fastest way to
answer "did the plugin even register" without writing code. Their measurement use is
`references/performance.md`; here it is an existence check.

**Linux rendering.** `WEBKIT_DISABLE_DMABUF_RENDERER=1` is the workaround for blank or garbled
WebKitGTK windows, most often on NVIDIA proprietary drivers;
`WEBKIT_DISABLE_COMPOSITING_MODE=1` is the older, blunter sibling. Two things matter: they must
be set *before* the event loop starts, which means `std::env::set_var` at the top of `main()`
rather than a launcher script you do not control at install time; and if one fixes the symptom
you have *identified the layer*, not fixed the bug — you have taken the compositing path, with
the cost that implies. Per-distro detail: `references/cross-platform.md` §Linux; real
placement: `references/case-studies.md` §8.

**Build a `copy_diagnostics` command** returning app version, `tauri::VERSION`, OS, WebView
version, `XDG_SESSION_TYPE` and GPU driver on Linux, packaging format, and the resolved
`app_log_dir()`. `references/cross-platform.md` §7 explains why the Linux fields cannot be
inferred from `tauri info`.

### Inspecting the IPC boundary

**Frontend.** `invoke()` rejects with the **error value**, not an `Error` object — if the
command returns `Result<T, E>`, the rejection is `E` serialized. Three consequences:
`catch (e) { e.message }` prints `undefined` when `E` is a `String`, so log the whole value; an
unhandled rejection on a `void`-called `invoke` is silent in some frameworks, so a command that
"does nothing" may be rejecting into the void; and **a framework failure is indistinguishable
from your domain error** — `Command X not found` and an ACL denial arrive through the same
channel with the same shape.

**Rust.** With `tracing` enabled, IPC is a span: you see the command name and whether it was
reached. Span absent → the request never arrived; look at the ACL and handler registration, not
the command body. Span present but the frontend still fails → serialization on the way back.

**What you cannot see.** There is no network-panel equivalent for IPC — it is not HTTP, and the
inspector will not show payloads. Substitute a thin wrapper logging command name and a
*redacted* argument summary at `Debug`, under `debug_assertions` only; the shape that scales to
hundreds of commands is `references/ipc-and-commands.md`.

### The panic-visibility trap

**Symptom.** A command hitting a panicking path — `unwrap()` on `None`, index out of range, a
`RefCell` double-borrow — makes the **whole application vanish**. No dialog, no error, no
rejected promise. `await invoke(…)` never settles and never throws, so no `try/catch` or
`.catch()` ever runs. Users report "it just closes."

**Cause.** Two independent facts compose.

1. **`panic = "abort"` removes the unwind path.** Under the default `unwind`, a panic unwinds
   the thread, Tauri catches it at the command boundary, and the promise rejects. Under `abort`
   the panic calls `abort()` immediately — the process is gone before any handler, any `Drop`,
   or any IPC response exists. There is nothing to catch because unwinding was compiled out.
   **ZUS ships `panic = "abort"`** in its effective root profile; Jan ships `panic = "unwind"`
   with the explicit comment *"allows catching library panics."* Two real apps, opposite calls
   — the full comparison, including which of ZUS's two profile blocks is dead configuration, is
   `references/case-studies.md` §12.
2. **There is nowhere for the message to go.** Release builds set
   `windows_subsystem = "windows"`, so on Windows no console is attached and the message goes to
   a stderr nobody reads — and with logging gated on `debug_assertions` (§`tauri-plugin-log`)
   the event leaves no trace on any medium.

**Fix**, cheapest first:

- **Install a panic hook that reaches durable storage**, before the builder runs.
  `std::panic::set_hook` fires under `abort` as well as `unwind` — the hook runs, *then* the
  process dies. Six lines: log the `PanicHookInfo` payload and location through
  `tauri-plugin-log` to `LogDir`. The one intervention that works regardless of profile.
- **Do not panic in command bodies — return `Result`.** Under `unwind` a panic is an ugly
  rejection; under `abort` it is data loss. Enforcement is §the profile trap, fix 1.
- **Choose the profile deliberately.** `abort` buys a smaller binary and no landing-pad code;
  `unwind` buys surviving a panic in a dependency you do not control. Size/speed trade:
  `references/performance.md` §binary size.

**When to deviate.** `abort` is right for an app with no untrusted plugin surface where a panic
genuinely means unrecoverable corruption — crashing loudly beats continuing wrongly. The trap
is not the setting; it is shipping the setting without the hook.

---

## testing

**The honest summary.** The best-return tests in a Tauri app are ordinary Rust unit tests, and
ordinary frontend tests, on code that has nothing to do with Tauri. The Tauri-specific machinery
— mock runtime, mock IPC, WebDriver — is real and occasionally correct to reach for, but its
cost/benefit is far worse than its prominence in the docs suggests. A suite mirroring the
documentation's structure rather than your risk will be slow, brittle, and will not catch the
bugs in §triage.

**Not worth testing:** *that a command is registered* (a missing `generate_handler!` entry is
caught the first time anyone runs the app); *that a permission is granted* (capability JSON is
data — asserting it says what it says is a tautology; review it,
`playbooks/security-review.md`); *window and tray behaviour under the mock runtime*
(`MockRuntime` creates no real window, so the assertion is about the mock); *exhaustive
serialization round-trips* (one test per non-obvious `serde` attribute, not one per struct).

### Primary strategy: keep the logic out of the `#[tauri::command]` function

Treat `#[tauri::command]` as a *transport adapter*: deserialize, call one plain function, map
the error. Behaviour lives in the plain function, whose signature holds no Tauri types.

```rust
// tauri 2.11.5 — thin boundary, logic testable with no runtime.
pub fn resolve_note_path(root: &Path, requested: &str) -> Result<PathBuf, NoteError> {
    let candidate = root.join(requested).canonicalize()?;
    if !candidate.starts_with(root) { return Err(NoteError::OutsideRoot); }
    Ok(candidate)
}

#[tauri::command]
pub async fn read_note(state: State<'_, Vault>, requested: String) -> Result<String, NoteError> {
    let path = resolve_note_path(&state.root, &requested)?;
    tokio::fs::read_to_string(path).await.map_err(Into::into)
}
// #[test] rejects_traversal_outside_the_vault_root — no `test` feature, no mock, no app boot.
```

**Why this is primary, not merely nice.** (1) **No runtime** — microseconds instead of an `App`
boot per test; across ~250 commands (`references/case-studies.md` §11) that decides whether the
suite runs on save or on PR. (2) **No mock surface, so no divergence** — a test that never
touches `tauri::test` cannot be wrong about Tauri, because it makes no claim about it. (3) **It
tests the risky part**: validation, path handling, state transitions, error mapping. (4) **It is
the refactor security wants anyway** — Rule 2 requires validating in Rust, and a named,
unit-tested `resolve_note_path` *is* that validation (`references/security.md`).

**Trade-off.** You give up adapter coverage — argument-name mapping, `State` injection, error
serialization, all real failure modes (`references/ipc-and-commands.md`). Buy it back with a
*small fixed number* of mock-runtime tests over representative shapes, not one per command.

### `tauri::test` — what the mock runtime can and cannot do

Gated behind the **`test` Cargo feature** (*"Enables the `test` module exposing unit test
helpers"*) and documented as **unstable**. Verified surface on 2.11.5: `mock_builder() ->
Builder<MockRuntime>`, `mock_context(assets)`, `mock_app()`, `noop_assets() -> NoopAsset`,
`get_ipc_response(webview, InvokeRequest) -> Result<InvokeResponseBody, serde_json::Value>`,
`assert_ipc_response(…)`, the `INVOKE_KEY` constant, and `MockRuntime` itself.

**It buys** adapter coverage: that `generate_handler!` dispatches the name you think, that
arguments deserialize from a real `InvokeBody`, that your error type serializes into something
the frontend can read, that managed state resolves. **It cannot** run a native webview — no DOM,
no rendering, no real window, no devtools, no platform behaviour — so it tells you nothing in
`references/cross-platform.md`. Building an `InvokeRequest` by hand is verbose (`cmd`,
`callback`, `error`, `url`, `body`, `headers`, `invoke_key`); write one helper. *Unstable* is a
real warning: this module churns across 2.x minors.

On the frontend, `@tauri-apps/api/mocks` mirrors it with no Rust: `mockIPC(handler)`,
`mockWindows(…)` (existence only), `clearMocks()` after **every** test, and since **2.7.0**
`{ shouldMockEvents: true }` for partial event support (`emitTo`/`emit_filter` excluded). Mock
the *shape*, assert on the *call*; when the mock grows branches you are testing the mock.

**The dependency smell, with a real example.** The feature must be on for the module to exist,
and the tempting place is the main `[dependencies]` block. **Jan does exactly this** —
`src-tauri/Cargo.toml:151-154` declares `[dependencies.tauri]` with
`features = ["protocol-asset", "macos-private-api", "test"]`, and its `default` and `test-tauri`
feature lists re-add `tauri/test` too. It compiles the mock runtime and its dispatcher types
into the shipped binary for no runtime benefit, and makes an explicitly-unstable module part of
the release compile surface. The fix is a dev-only entry, which Cargo unifies for tests and
omits from release:

```toml
[dev-dependencies]
tauri = { version = "2.11.5", features = ["test"] }
```

**When to deviate.** A crate genuinely needing the mock runtime for a non-test consumer — a
fixture generator, an internal harness binary — has a reason. Jan has no such consumer.

### The profile trap

**Symptom.** A test asserts a command returns `Err` for bad input. It passes, green, every run.
The shipped app given that same input **hard-crashes with no error** — §the panic-visibility
trap, exactly.

**Cause.** `cargo test` builds under the **dev** profile (or `test`, which inherits it), so
`[profile.release]` — including `panic = "abort"` — does not apply:

| | `cargo test` (dev/test) | Shipped (`release`, ZUS's values) |
| --- | --- | --- |
| Panic strategy | `unwind` — caught, becomes a rejection | `abort` — process dies instantly |
| `debug_assertions` | on | off |
| Integer overflow | panics | wraps, where `overflow-checks = false` |
| Optimisation | `opt-level = 0` | `opt-level = 3`, `lto = "thin"` |

The suite is **structurally incapable** of observing the app's worst failure mode: the
panicking path your test happily catches is the path that aborts in production, and the green
tick actively argues against investigating it.

**Fix** — three parts, none of which is "run the tests in release":

1. **Do not let the test profile be the only place panics are survivable.** Treat `unwrap`,
   `expect`, `panic!` and slice indexing in command modules as defects; `clippy::unwrap_used`
   and `clippy::indexing_slicing` enforce that with no test run at all.
2. **Assert the error path returns `Err`, and separately assert it cannot panic.** For input
   parsing and path handling, a `proptest`/`quickcheck` fuzz over the plain function finds the
   panicking input the example-based test missed — the highest-value property test in a Tauri
   app, precisely because a panic there is fatal rather than noisy.
3. **Install the panic hook (§the panic-visibility trap).**

**When to deviate.** `cargo test --release` occasionally earns its keep — `overflow-checks =
false` behaviour, or an optimisation-dependent bug. Do not default to it: it is slow, and it
*still* does not exercise `panic = "abort"`, because the test harness needs unwinding to report
failures at all. That gap cannot be closed by configuration.

### WebDriver E2E

**Platform support, stated accurately, because this changed.** Two routes, two answers (both
verified on the official docs, 2026-07-28):

- **Driving [`tauri-driver`](https://crates.io/crates/tauri-driver) directly** — Selenium,
  non-Node harnesses, custom rigs — is **Windows and Linux only**: macOS has no WKWebView
  driver tool, so there is nothing to drive.
- **`@wdio/tauri-service`** (WebdriverIO, now the recommended route) covers **Windows, Linux
  and macOS**, with macOS working via an *embedded* WebDriver server inside your app
  (`tauri-plugin-wdio-webdriver`) rather than a platform driver. It can also drive
  `tauri-driver` externally on Windows/Linux, or CrabNebula's fork (paid key for macOS).

"No macOS E2E for Tauri" was true of the direct route and is no longer the whole picture.

**Is it worth the maintenance?** It **costs** a release build per run, plugins for the embedded
provider, a driver kept in sync with the platform WebView, a headless display on Linux CI, and
UI-automation flakiness. It **buys** the only automated check covering the real webview, real
IPC, real ACL and real window — the only thing here that could have caught most of §triage.

**Recommendation: a smoke suite of three to five tests, not a coverage suite** — the app
launches and renders, one command round-trips through the real ACL, one platform-critical
interaction (titlebar drag, tray menu, file dialog) behaves. That catches "the built app is
broken", highest consequence and lowest detectability, at bounded cost; past five tests the
flake rate costs more than it returns. For renderer-only assertions, WebdriverIO's **browser
mode** runs the frontend in plain Chrome against Vite with `invoke()` intercepted.

### CI shape

The pipeline itself — matrix, caching, signing, artifact upload, updater manifest — is
`references/build-and-distribution.md` §CI. What belongs here is only what must repeat per
platform and what must not.

**Run once, on the cheapest runner** (no platform-dependent behaviour, so three runs buy
nothing but minutes): `cargo fmt --check` and `cargo clippy -- -D warnings`; the pure-function
unit tests above; frontend unit and `mockIPC` tests; capability and config review
(`playbooks/security-review.md`), which is data, not behaviour.

**Run per platform** — where a green Linux run tells you nothing about Windows:
`cargo build`/`cargo check`, because `#[cfg(target_os)]` code does not compile on the others
and this is the cheapest bug in the class; anything touching paths, the log directory or
`app_log_dir()`, whose resolved locations differ (§`tauri-plugin-log`); the bundle step when
packaging config changed; and the WebDriver smoke suite where you support it.

**Run on release only.** Signing, notarization and updater-artifact generation — one-way doors
covered by Rule 7 and `playbooks/release-preparation.md`.

**The trap.** A matrix running `cargo test` on three platforms and calling it "cross-platform
testing" measures compilation three times and behaviour zero times, at three times the minutes.
The per-platform value is in the *build* and the *smoke run*.

---

**Evidence.** Verified **2026-07-28** against `tauri 2.11.5` (published 2026-07-01) and
`tauri-plugin-log 2.9.0`.

- Official docs: </develop/debug/> (dev-only code, consoles, `RUST_BACKTRACE`, inspector
  shortcuts, `tauri build --debug`, the `devtools` feature, macOS private-API warning);
  </develop/tests/>, </develop/tests/mocking/> (`mockIPC`, `mockWindows`, `clearMocks`,
  `shouldMockEvents` since 2.7.0, `emitTo`/`emit_filter` limits) and </develop/tests/webdriver/>
  (`@wdio/tauri-service` on Windows/Linux/macOS via `tauri-plugin-wdio-webdriver`; direct
  `tauri-driver` Windows and Linux only; browser mode) — all under <https://v2.tauri.app>.
- docs.rs `tauri/2.11.5`: `test` module (`mock_builder`, `mock_context`, `mock_app`,
  `noop_assets`, `get_ipc_response`, `assert_ipc_response`, `INVOKE_KEY`, `NoopAsset`,
  `MockRuntime` — *crate feature `test` only*); crate feature list; `WebviewWindow`
  (`open_devtools`, `close_devtools`, `is_devtools_open`); `PathResolver` (`app_log_dir`,
  `resource_dir`). `tauri-plugin-log/2.9.0`: `TargetKind` variants and `Builder` methods.
- Crate source on disk, `tauri-2.11.5`: `src/webview/mod.rs:1905,1911`
  (`Command {command} not found`); `src/ipc/authority.rs:356,404,405,414,432` (the four ACL
  denial shapes); `src/protocol/tauri.rs:182-183` (CSP as a response header on Tauri-served
  assets). `tauri-utils-2.9.3/src/config.rs:2896-2907` (`csp`/`devCsp`), `:3074-3075,4470`
  (`withGlobalTauri`, default `false`).
- Real codebases: ZUS `src-tauri/src/lib.rs:497-511`, root `Cargo.toml:132-137`
  (`panic = "abort"`); Jan `src-tauri/Cargo.toml:151-154` (`tauri/test` in production deps),
  `:192-202` (`panic = "unwind"`). Analysis: `references/case-studies.md` §12.

# Production Case Studies — two real Tauri v2 apps, read side by side

Everything here was read out of a shipping codebase on 2026-07-27, not from documentation.
Both apps solve the same problem class (a desktop AI tool with a heavy native layer) and
disagree on almost every security decision. That disagreement is the lesson.

| | **ZUS** | **Jan** |
| --- | --- | --- |
| What | AI IDE, VS Code workbench ported to Tauri | Local-AI desktop app (Menlo Research) |
| Version read | v1.1.0 | v0.8.3 |
| **`tauri` runtime pinned** | **`2.11.5`** (current stable) | **`2.8.5`** — `[dependencies.tauri]`, with `tauri-build 2.0.2`, plugins `2.2.x`, `tauri-plugin-log 2.0.0-rc`, and the `test` feature enabled in *production* deps |
| Frontend | vanilla TS + DOM (no framework) | React (`web-app/dist`) |
| Native | 24 workspace crates | `src/core/*` modules + 5 in-tree plugins |
| Targets | desktop only, `targets: "all"` | desktop + Android + iOS |

> **Version discipline.** ZUS is on current stable; Jan's runtime is three minor versions
> behind, one plugin is a **release candidate in production**, and the `test` feature (which
> exists to expose the mock runtime to unit tests) is enabled in the release dependency set.
> When you copy a Jan pattern, re-verify it against the version you are on — capability
> schema fields and the updater API both moved between 2.8 and 2.11. Every snippet below is
> stamped.
>
> **This is not academic. Jan's runtime pin is below a security floor.** `CVE-2026-42184` /
> `GHSA-7gmj-67g7-phm9` (fixed in **`tauri` 2.11.1**) — `is_local_url()` compared only the
> first domain label, so on Windows and Android a page at `http://app.evil.com` was
> classified `Origin::Local` and could invoke commands meant to be local-only. Jan runs
> `tauri 2.8.5` and additionally grants its main capability to `remote.urls: ["http://*"]`
> (§3) — the exact shape that bug turns into remote command execution.
>
> Attribute this correctly when you act on it: `is_local_url()` is a **runtime** function, so
> exposure tracks the **`tauri`** crate version, not `tauri-build`. Bumping `tauri-build`
> fixes nothing. **Pin `tauri >= 2.11.1`.** See `references/security.md` §advisories.

---

## 1. CSP — the same framework, two very different postures

**ZUS** (`src-tauri/tauri.conf.json`, tauri 2.11.5) — one string, explicit, closed by default:

```
default-src 'self' asset: http://asset.localhost https://asset.localhost;
script-src  'self' 'wasm-unsafe-eval';
style-src   'self' 'unsafe-inline';
object-src  'none';
base-uri    'self';
form-action 'self';
worker-src  'self' blob:;
```

**Jan** (`src-tauri/tauri.conf.json`, tauri 2.8.5) — object form, and materially looser:

```jsonc
"script-src": "'self' 'unsafe-eval' asset: $APPDATA/**.* http://asset.localhost https://eu-assets.i.posthog.com https://posthog.com",
"style-src":  "'unsafe-inline' 'self' https://fonts.googleapis.com",
"dangerousDisableAssetCspModification": ["style-src"]
```

**Read this critically.** Three things in the Jan column are the exact patterns this skill
tells you to avoid:

1. **`'unsafe-eval'` in `script-src`.** This re-enables `eval()` and `new Function()`. Any
   injected string now becomes executable code, which is the single largest step backwards
   you can take in a webview that holds IPC capability. ZUS needs only `'wasm-unsafe-eval'`
   — that permits WebAssembly compilation **without** permitting JS `eval`. If your reason
   for `'unsafe-eval'` is "we load WASM", `'wasm-unsafe-eval'` is the correct, narrower
   answer.
2. **`dangerousDisableAssetCspModification: ["style-src"]`.** Tauri normally rewrites the
   CSP at load time to inject nonces/hashes for the assets it serves. Disabling that for a
   directive means Tauri stops hardening it — the config key is named `dangerous*` because
   the framework authors want you to feel it. Reach for it only when a third-party
   stylesheet loader genuinely cannot work with nonces, and record why.
3. **A CSP with no `object-src`, `base-uri`, or `form-action`.** These three are cheap and
   close real holes (plugin embedding, `<base>` hijacking, form exfiltration). `default-src`
   does **not** cover `base-uri` or `form-action`. ZUS sets all three; Jan sets none.

**Verdict:** use ZUS's CSP shape as the starting point. Use Jan's only as a worked example
of what accumulates when CSP is edited reactively, feature by feature, under deadline.

---

## 2. Asset protocol scope — the difference between a scope and a decoration

```jsonc
// ZUS — tauri 2.11.5
"assetProtocol": { "enable": true, "scope": ["$HOME/**", "/tmp/**"] }

// Jan — tauri 2.8.5
"assetProtocol": {
  "enable": true,
  "scope": { "requireLiteralLeadingDot": false, "allow": ["**/*"] }
}
```

`"**/*"` means *every path the process can read*: `/etc/shadow` on Linux if permissions
allow, the user's SSH keys, other apps' data directories. At that point the scope is
documentation, not a control. Combined with Jan's `'unsafe-eval'`, a single XSS in the
renderer reads any file the user can read.

ZUS's `["$HOME/**", "/tmp/**"]` is still broad — it covers the whole home directory — but it
is a boundary, and it uses the `$HOME` variable rather than a hard-coded path, so it
resolves correctly per-OS.

**Rule:** the asset scope should name the directories your app actually serves from. If you
cannot enumerate them, you do not yet know what your app does.

`requireLiteralLeadingDot: false` is a separate decision: it lets glob patterns match
dotfiles. Defaulting it to `false` means `**/*` also matches `~/.aws/credentials`.

---

## 3. Capabilities — scope of blast radius

**ZUS** `src-tauri/capabilities/default.json` (tauri 2.11.5) — one capability, one window,
no remote:

```jsonc
{
  "identifier": "default",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:webview:allow-internal-toggle-devtools",
    "core:window:allow-start-dragging",
    "core:window:allow-minimize",
    "core:window:allow-toggle-maximize",
    "core:window:allow-is-maximized",
    "core:window:allow-close",
    "dialog:default", "dialog:allow-open", "dialog:allow-save",
    "dialog:allow-message", "dialog:allow-ask", "dialog:allow-confirm",
    "shell:default", "shell:allow-open",
    "log:default"
  ]
}
```

Note what is **absent**: no `fs:*`, no `shell:allow-execute`, no `http:*`. ZUS does all
filesystem and process work through its own `#[tauri::command]` functions, which jail paths
to the workspace root in Rust. The plugin ACL is not carrying that weight, so it does not
need those permissions at all. **This is the strongest pattern in either codebase**: if you
own the command, you own the validation, and you do not have to widen a plugin scope.

**Jan** `capabilities/default.json` (tauri 2.8.5) — five capabilities, and the default
one is wide:

```jsonc
{
  "identifier": "default",
  "windows": ["main"],
  "remote": { "urls": ["http://*"] },        // ← see below
  "permissions": [
    "core:default", "shell:allow-spawn", "shell:allow-open",
    { "identifier": "http:default",
      "allow": [{ "url": "https://*:*" }, { "url": "http://*:*" }], "deny": [] },
    { "identifier": "shell:allow-execute", "allow": [] },
    "vector-db:default", "rag:default", "hardware:default", "llamacpp:default",
    "updater:default", "updater:allow-check", "store:default", "deep-link:default"
  ]
}
```

Three observations, in descending severity:

- **`"remote": { "urls": ["http://*"] }` is the serious one.** This grants the capability —
  including `shell:allow-spawn` — to **any page loaded over plain HTTP** in that webview.
  Any network attacker who can MITM one `http://` navigation gets process spawn. And note
  what `remote` does *not* do: the sibling `local` field **defaults to `true`**, so adding
  `remote` widens the capability without removing local access — it is purely additive. If
  you need remote content at all, scope it to exact `https://` origins and give those
  origins their **own minimal capability**, rather than extending the one your local app
  already uses. Combined with the CVE above, this is the highest-severity line in either
  codebase.
- **`http:default` allowing `https://*:*` and `http://*:*`** turns the app into an open HTTP
  proxy from the renderer's point of view — an SSRF primitive that reaches localhost
  services and cloud metadata endpoints.
- **`shell:allow-execute` with `"allow": []` is actually good defensive practice** and worth
  copying: it declares the permission so the ACL is explicit, while the empty scope means no
  command matches. Better than leaving it undeclared and adding it wide later under
  pressure.

**Jan's per-window split is the right structure**, and worth copying even though its default
capability is loose. `logs-window.json` (tauri 2.8.5):

```jsonc
{
  "identifier": "logs-window",
  "windows": ["logs-window-local-api-server"],
  "platforms": ["linux", "macOS", "windows"],
  "permissions": [
    "core:default", "core:window:allow-start-dragging", "core:window:allow-set-theme",
    "core:window:allow-get-all-windows", "core:event:allow-listen",
    "log:default", "core:webview:allow-create-webview-window",
    "core:webview:allow-get-all-webviews", "core:window:allow-set-focus"
  ]
}
```

A log viewer gets window controls and event listening — and nothing else. A secondary window
that renders less-trusted content should never inherit the main window's capability.

---

## 4. Custom titlebars — three platforms, three answers

Both apps ship a custom titlebar, and both hit the same platform matrix. The per-platform
config split is not stylistic; the same values do not work everywhere.

| Setting | ZUS (single conf) | Jan macOS | Jan Windows | Jan Linux |
| --- | --- | --- | --- | --- |
| `decorations` | `false` | `true` | `false` | `false` |
| `transparent` | `true` | `true` | `true` | **`false`** |
| `titleBarStyle` | `Overlay` | `Overlay` | `Overlay` | — |
| `hiddenTitle` | `true` | `true` | `true` | — |
| `dragDropEnabled` | `false` | `false` | `false` | `false` |

Read the Linux column: **`transparent: false`**. Transparency on WebKitGTK is the least
reliable of the three engines — compositor-dependent, and broken outright on some setups.
Jan disables it there rather than shipping a window that renders wrong on a subset of
distros. ZUS keeps `transparent: true` everywhere in one config file, which is a latent
Linux risk it has not had to pay for yet.

macOS keeps `decorations: true` **with** `titleBarStyle: "Overlay"` + `hiddenTitle: true`
— that is how you keep the native traffic lights while drawing your own bar behind them.
Setting `decorations: false` on macOS removes the traffic lights and you must reimplement
window controls, rounded corners and the resize border yourself. Jan additionally pins
`trafficLightPosition: { x: 20, y: 32 }` to align them to its bar.

`macOSPrivateApi: true` (Jan, top-level `app`) is required for real window transparency on
macOS — and it uses private APIs, so **it disqualifies the build from the Mac App Store**.
Same flag enables the `devtools` feature's private-API path. Know which distribution channel
you are choosing before enabling it.

**`dragDropEnabled: false` in all four columns is the most-copied line here and the least
understood.** Tauri's native OS drag-drop handler swallows drag events before the webview
sees them, which breaks every HTML5 drag-and-drop implementation. Both apps disable the
native handler to get HTML5 DnD back. The cost is that you no longer receive OS file-drop
events; if you need files dropped from Finder/Explorer, you must keep it enabled and use
Tauri's drag-drop event instead.

---

## 5. Entitlements — hardened runtime versus a JIT

Both apps run untrusted-ish code (JS/WASM extension hosts, MCP servers under Bun) and both
had to punch holes in macOS hardened runtime. They punched different sizes.

```xml
<!-- Jan — Entitlements.plist -->
<key>com.apple.security.cs.allow-jit</key><true/>
```
```xml
<!-- ZUS — entitlements.plist -->
<key>com.apple.security.cs.allow-jit</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
```

Jan's comment records the exact symptom that forced it: *"Required for Bun runtime to
allocate executable memory for JIT compilation — without this, MCP servers fail with 'Ran
out of executable memory'."* That is the right way to document an entitlement: name the
failure it fixes.

ZUS grants two more, and they are not equivalent in risk:

- `allow-jit` — permits `MAP_JIT` pages. Narrowest; what a JS/WASM engine actually needs.
- `allow-unsigned-executable-memory` — permits *any* unsigned executable memory. Broader,
  and a common cargo-culted addition when `allow-jit` alone appeared not to work.
- `disable-library-validation` — permits loading **libraries not signed by you or Apple**.
  This is the widest of the three and the one to justify hardest; it exists for plugin hosts
  that `dlopen` third-party dylibs.

**Rule:** add entitlements one at a time, each with the error it resolves written next to
it, and re-test after each. A three-entitlement file where only one was needed is a
permanent weakening of the hardened runtime for no benefit. Every entitlement here is also
something notarization will note and App Review will ask about.

---

## 6. Updater — the failure mode that cannot fix itself

**ZUS** reads its updater feed out of the bundled config at runtime
(`src-tauri/src/commands/updater.rs:485-509`, tauri 2.11.5):

```rust
let raw_pubkey = app.config().plugins.0
    .get("updater").and_then(|v| v.get("pubkey"))
    .and_then(|v| v.as_str()).map(str::to_string);

let endpoints = app.config().plugins.0
    .get("updater").and_then(|v| v.get("endpoints"))
    .and_then(|v| v.as_array())
    .map(|arr| arr.iter().filter_map(|v| v.as_str().map(str::to_string)).collect::<Vec<_>>())
    .unwrap_or_default();
```

`app.config()` is the **compiled-in** configuration. The endpoint list ships inside the
binary. That gives you exactly one shot: if the endpoint later moves, dies, or was wrong at
release time, the only way to tell an installed client about the new endpoint is to ship an
update — through the endpoint that no longer works. **Installed clients are stranded and
there is no recovery path that does not involve the user manually reinstalling.**

ZUS configures a single endpoint:

```jsonc
"endpoints": ["https://github.com/8syncdev/zus-releases/releases/latest/download/latest.json"]
```

**Jan** configures two, deliberately ordered (`tauri.conf.json`, tauri 2.8.5):

```jsonc
"endpoints": [
  "https://apps.jan.ai/update-check",                                        // primary, signed
  "https://github.com/janhq/jan/releases/latest/download/latest.json"        // fallback
],
"windows": { "installMode": "passive" }
```

and its `custom_updater.rs` documents the convention: *"First endpoint is treated as PRIMARY
— uses HMAC request signing. Remaining endpoints are FALLBACK — no signing needed."* The
first is infrastructure Jan controls (so it can serve staged rollouts and telemetry-free
version checks); the second is GitHub Releases, which survives Jan's own infrastructure
going down.

**Rule — non-negotiable for any app that ships to users:** configure **at least two update
endpoints on different infrastructure**, from your very first release. The cost is one line
of JSON. The cost of getting it wrong is an install base you can never reach again.

**But be precise about what that buys you.** Fallback covers *outage*, not *hostility*.
`check()` returns `Ok(None)` immediately on an HTTP `204` and never consults the remaining
endpoints — so a primary endpoint that is compromised, or merely misconfigured to answer
`204`, silently freezes the entire install base while every fallback sits unused. Two
endpoints protect you from GitHub being down. They do not protect you from your own primary
answering "no update" forever. The mitigations are operational, not architectural: monitor
what your primary actually returns, and treat "update check success rate" as a production
metric rather than assuming it. See `references/build-and-distribution.md` §update security
for the two other failure modes in this family (rollback, baked-in endpoints).

### 6b. Jan's HMAC signing, and the fallback key smell

```rust
// refs/jan/src-tauri/src/core/updater/hmac_client.rs — tauri 2.8.5
const SECRET_KEY: &str = match option_env!("JAN_SIGNING_KEY") {
    Some(key) => key,
    None => "local-dev-test-key-not-for-production",
};
```

The design is sound: HMAC-SHA256 over `"{nonce_seed}:{timestamp}:{nonce}"`, with the
timestamp and a 32-byte nonce giving replay protection, carried in `X-Request-Token` /
`X-Request-Time` / `X-Request-Id`.

The **fallback is the bug shape**. `option_env!` resolves at compile time; if CI ever builds
without `JAN_SIGNING_KEY` set, the release binary ships with a hard-coded key that is public
in the repository — and nothing fails, nothing warns, the build is green. A missing signing
key must **fail the build**, not silently degrade:

```rust
const SECRET_KEY: &str = match option_env!("JAN_SIGNING_KEY") {
    Some(key) => key,
    #[cfg(debug_assertions)]
    None => "local-dev-test-key-not-for-production",
    #[cfg(not(debug_assertions))]
    None => panic!("JAN_SIGNING_KEY must be set for release builds"),
};
```

Note also that this HMAC layer protects the *update check request*; it is **not** a
substitute for minisign verification of the downloaded artifact. Both apps correctly keep
`pubkey` configured — that is the signature that actually stops a malicious binary.

---

## 7. Windows signing — what actually clears SmartScreen

Jan ships `src-tauri/sign.ps1`:

```powershell
param ([string]$Target)
AzureSignTool.exe sign `
  -tr http://timestamp.digicert.com `
  -kvu $env:AZURE_KEY_VAULT_URI  -kvi $env:AZURE_CLIENT_ID `
  -kvt $env:AZURE_TENANT_ID      -kvs $env:AZURE_CLIENT_SECRET `
  -kvc $env:AZURE_CERT_NAME -v $Target
```

Wired in via `bundle.windows.signCommand`. Two details that matter:

- **`-tr` (RFC 3161 timestamp) is not optional.** Without a timestamp the signature stops
  validating the day the certificate expires, and every already-installed copy starts
  warning. With it, signatures remain valid past expiry.
- The private key never exists on the build machine — it stays in Azure Key Vault and the
  runner authenticates with a service principal. This is the pattern to copy; a `.pfx` in CI
  secrets is a key you cannot revoke cleanly.

ZUS by contrast sets `"signingIdentity": "-"` under `bundle.macOS`, which is **ad-hoc
signing**: it satisfies the local loader but is not a Developer ID, so it does not notarize
and Gatekeeper will still block it on another Mac. Fine for internal builds; not shippable.

---

## 8. Linux rendering — the workaround that belongs in `main.rs`

```rust
// ZUS src-tauri/src/main.rs — tauri 2.11.5
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    #[cfg(target_os = "linux")]
    { std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1"); }
    zus_lib::run();
}
```

Two production lines worth memorising:

- **`windows_subsystem = "windows"`** — without it, every release launch on Windows opens a
  console window behind the app. `cfg_attr(not(debug_assertions), ...)` keeps stdout in
  debug builds where you want it.
- **`WEBKIT_DISABLE_DMABUF_RENDERER=1`** — WebKitGTK's DMA-BUF renderer produces a blank or
  garbled window on a range of Linux GPU setups, Nvidia proprietary drivers most notoriously.
  It must be set **before** the webview initialises, which is why it lives at the top of
  `main()` and not in `setup()`. Cost: it disables an accelerated path, so on healthy systems
  you give up some rendering performance to make the broken ones work at all.

---

## 9. Custom plugin skeleton — the shape that generates its own permissions

Jan's `tauri-plugin-vector-db` is a complete, minimal, real in-tree plugin (tauri 2.8.5 —
re-verify against current before copying):

```
plugins/tauri-plugin-vector-db/
├── build.rs              # declares commands → generates permissions
├── Cargo.toml            # tauri + tauri-plugin (build-dep)
├── package.json          # @janhq/tauri-plugin-vector-db-api
├── rollup.config.js      # bundles guest-js → dist-js
├── guest-js/index.ts     # the TS surface the app imports
├── src/{lib,commands,db,state,error,utils}.rs
└── permissions/
    ├── default.toml                 # hand-written: the default permission set
    ├── autogenerated/commands/*.toml   # ← generated, one per command
    └── schemas/
```

```rust
// build.rs — this is the whole thing
fn main() {
    tauri_plugin::Builder::new(&[
        "create_collection", "create_file", "insert_chunks", "search_collection",
        "delete_chunks", "delete_file", "delete_collection", "chunk_text",
        "get_status", "list_attachments", "get_chunks",
    ]).build();
}
```

Listing command names in `build.rs` is what makes `tauri_plugin::Builder` emit
`permissions/autogenerated/commands/<cmd>.toml` — an `allow-<cmd>` and `deny-<cmd>` pair
per command. You then hand-write `permissions/default.toml` to choose which of those the
`<plugin>:default` set grants. **A command you forget to list in `build.rs` has no
permission and will be rejected at runtime by the ACL** — that is the classic "my new plugin
command returns a permission error" bug, and the fix is in `build.rs`, not in the capability.

The `src/` split (`commands` / `db` / `state` / `error` / `utils`) is the right default:
`commands.rs` stays a thin IPC-facing layer, the logic underneath is plain Rust that unit
tests can reach without a Tauri runtime.

---

## 10. Boot sequence — a real `setup()` and what it gets right

ZUS `src-tauri/src/lib.rs:375-514` (tauri 2.11.5), abridged:

```rust
tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_shell::init())
    .manage(UpdateManagerState::new())
    .manage(Arc::new(TerminalStore::new()))
    // …~18 more .manage() calls
    .register_asynchronous_uri_scheme_protocol("zus-asset", |_ctx, request, responder| {
        std::thread::spawn(move || { /* read file, respond with mime */ });
    })
    .setup(|app| {
        let app_data = app.path().app_data_dir().expect("failed to resolve app data dir");
        std::fs::create_dir_all(&app_data).ok();
        let db = StorageDb::new(app_data.join("zus_storage.db").to_str().unwrap())?;

        restore_and_show(app, &db);          // ← window shown here, not by config
        app.manage(Arc::new(db));

        if let Err(err) = commands::updater::initialize(app.handle()) {
            log::warn!("update manager disabled: {err}");   // ← degrade, don't abort
        }
        if let Err(err) = commands::secrets::initialize(app.handle()) {
            log::warn!("secret storage disabled: {err}");
        }

        #[cfg(target_os = "macos")]
        { app.set_menu(build_menu(app.handle())?)?; }

        if cfg!(debug_assertions) {
            app.handle().plugin(tauri_plugin_log::Builder::default()
                .level(log::LevelFilter::Info).build())?;
        }
        Ok(())
    })
    .invoke_handler(tauri::generate_handler![ /* ~250 commands */ ])
    .build(tauri::generate_context!())?
    .run(move |_app, event| { /* RunEvent handling */ });
```

What to copy:

- **`"visible": false` in config + explicit show in `setup()`.** ZUS's window config sets
  `visible: false`; `restore_and_show` restores the saved geometry and *then* shows. This is
  the standard fix for the white-flash-then-jump that you get when a window appears at the
  default size before your frontend and saved layout load.
- **Optional subsystems log and continue.** `updater`, `secrets` and `profiles` each
  `log::warn!` on failure instead of `?`-ing out of `setup`. An error returned from `setup`
  aborts app startup — so anything that is not required for the app to function must not
  propagate. Note the asymmetry with the lines above them: the storage DB *does* use
  `expect`, because ZUS genuinely cannot run without it. Decide per subsystem, deliberately.
- **Registering the log plugin only under `debug_assertions`** keeps release builds from
  writing logs the user never asked for — but see the trade-off: you then have no logs when
  a user reports a production bug. Prefer shipping a log plugin in release too, at `warn`
  level, writing to the OS log directory.
- **`register_asynchronous_uri_scheme_protocol` + `std::thread::spawn`.** The responder is
  handed to a worker thread so file reads never block the event loop. **But note the
  security hole in this specific implementation**: it takes `request.uri().path()`,
  URL-decodes it, and passes it straight to `std::fs::read` with no scope check and no
  `..` collapsing, then answers with `Access-Control-Allow-Origin: *`. Any code running in
  the webview can read any file the process can. If you copy this shape — and the threading
  shape is worth copying — canonicalise the path and assert it is inside an allowed root
  before reading.

---

## 11. Command surface at scale — what ~250 commands looks like

ZUS registers roughly 250 commands in one `generate_handler!`, grouped by comment banner:
agent, env studio, migration, automations, filesystem, path, text, compression, crypto,
terminal, process, search, window, updater, profiles, secrets, textmate, os.

This works, and the grouping-by-comment is doing real navigational work, but it is at the
limit. Past a couple of hundred commands the signals that you have outgrown a flat handler
are: merge conflicts concentrating in the `generate_handler!` block, and command-name
prefixes (`term_*`, `env_*`, `update_*`) effectively encoding a module system in strings.
That prefix convention **is** the tell — those groups want to be plugins, each with its own
ACL, its own permission defaults, and its own `build.rs`. Jan's in-tree plugin layout is the
answer to the problem ZUS's flat list is starting to have.

Also visible in that list: ZUS exposes `read_file`, `write_file`, `remove`, `rename`, `exec`
and `term_spawn` as its own commands rather than enabling `fs:*` and `shell:allow-execute`.
That is why its capability file can stay short. **Owning the command means owning the
validation** — and it moves the security boundary into Rust, where you can canonicalise a
path and compare it against the workspace root, instead of into a glob in a JSON scope.

---

## 12. Cargo release profiles — one is dead code, and they optimise for opposite things

Both apps tune `[profile.release]`. One of the two blocks below has no effect at all.

```toml
# ZUS — root Cargo.toml:132-137  (EFFECTIVE)
[profile.release]
opt-level     = 3
lto           = "thin"
codegen-units = 1
strip         = true
panic         = "abort"
```
```toml
# ZUS — src-tauri/Cargo.toml:157-162  (SILENTLY IGNORED)
[profile.release]
opt-level     = 3
lto           = "thin"
codegen-units = 1
strip         = true
panic         = "abort"
```

**Cargo reads profile settings only from the workspace root.** ZUS's root `Cargo.toml`
declares a workspace and lists `"src-tauri"` as a member (line 28), which makes the
`[profile.release]` inside `src-tauri/Cargo.toml` dead configuration — Cargo does not merge
it, does not warn about it, and does not apply it.

ZUS survives this only because the two blocks happen to be identical. That is luck, and it
is the dangerous kind: the next engineer who tunes `src-tauri/Cargo.toml` will change a
value, rebuild, measure no difference, and conclude the setting does not matter. **The fix
is to delete the member-level block, not to keep them in sync.** Duplicated configuration
where one copy is inert is worse than either having it once or not at all.

**Symptom to recognise:** "I set `opt-level`/`lto`/`strip` and the binary size did not
change." First question: is that `[profile.*]` block in the workspace root, or in a member?

Jan has no parent workspace — its `src-tauri/Cargo.toml` is its own package root (there is
no `refs/jan/Cargo.toml`), so its profile applies:

```toml
# Jan — src-tauri/Cargo.toml:192-202  (EFFECTIVE)
[profile.release]
opt-level        = "z"       # Optimize for size
lto              = "fat"     # Aggressive Link Time Optimization
strip            = "symbols"
codegen-units    = 1
panic            = "unwind"  # Unwind on panic, allows catching library panics
overflow-checks  = false
incremental      = false
```

### The two real decisions in here

**`opt-level = "z"` vs `3` is a product decision, not a default.** Jan optimises for size;
ZUS optimises for speed. Jan ships model runtimes and sidecars where the Rust binary is a
small fraction of the download, so shaving it matters less than it seems — yet `"z"` also
costs runtime speed in the native layer. ZUS runs a language server, a search engine and a
terminal multiplexer in-process, where `opt-level = 3` is defensible. Pick the one your
workload justifies and write down why; inheriting someone's `"z"` because it appeared in a
blog post about small Tauri binaries is how a fast native layer gets slow.

Also note `lto = "fat"` vs `"thin"`: fat LTO gives a smaller, marginally faster binary for
substantially longer link times. On a 24-crate workspace that lands on every release build
and every CI run. And `lto = false` does **not** mean "no LTO" — it means thin *local* LTO,
which is a common misreading.

**`panic = "abort"` vs `"unwind"` has a Tauri-specific consequence that the general Rust
advice does not cover.** With `panic = "abort"`, a panic inside a command does not surface
as a rejected `invoke` promise the frontend can handle — it **terminates the process**. The
user sees the app vanish, with no error dialog and no chance to save.

Jan chose `"unwind"` and wrote the reason in the file: *"allows catching library panics."*
That is the right call for an app that loads third-party model runtimes it does not control.
ZUS chose `"abort"` — smaller binary, no unwind tables — and therefore **any panic reachable
from any of its ~250 commands is a hard crash**, including panics inside dependencies it
does not own.

The trap that makes this bite in production: **`cargo test` runs under the dev profile**, so
a test that asserts a command returns `Err` will pass happily while the same input crashes
the shipped app. If you keep `panic = "abort"`, the discipline that goes with it is that
commands must not panic — audit `unwrap()`, `expect()`, slice indexing and integer division
on any path reachable from `generate_handler!`, and prefer `Result` all the way out.

See `references/performance.md` §binary size for the full cost model of each setting.

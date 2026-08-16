# Cheatsheet — capabilities, permissions, scopes

> Fields and defaults read from the generated `src-tauri/gen/schemas/desktop-schema.json`
> (`CapabilityFile`); resolution behaviour read from `tauri 2.11.5`
> `src/ipc/authority.rs` and `tauri-utils 2.9.3` `src/acl/resolved.rs`; scope shape from
> <https://v2.tauri.app/reference/acl/scope/>. Verified 2026-07-28. The security model, the
> threat reasoning and when a capability is the *wrong* tool: `references/security.md`.

**The one rule this file cannot replace:** a capability is defence in depth. The boundary that
holds is validation inside your Rust command. `references/security.md`.

---

## Capability file skeleton — every field

Location: `src-tauri/capabilities/*.json` (also `.json5`, `.toml`). One file per trust level.

```jsonc
{
  "$schema": "../gen/schemas/desktop-schema.json",

  // REQUIRED. Unique. Also the name you pass to `app.security.capabilities`
  // and the string that appears in "referenced by:" in a denial message.
  "identifier": "main-user-files-write",

  // Optional, default "". Write what the grouped permissions let the window DO.
  "description": "Lets the main window read and write inside the user's project directory.",

  // Optional, default TRUE. Applies to tauri://localhost / the local app origin.
  "local": true,

  // Optional, default unset. URLPattern strings. ADDITIVE ONLY — see the note below.
  "remote": { "urls": ["https://*.mydomain.dev", "https://mydomain.dev/api/*"] },

  // Optional. Glob patterns matched against WINDOW labels.
  // Omitting BOTH windows and webviews means the capability binds to nothing useful.
  "windows": ["main", "editor-*"],

  // Optional. Glob patterns matched against WEBVIEW labels (multiwebview builds).
  "webviews": [],

  // Optional, default = all platforms. Exactly: "macOS" | "windows" | "linux" | "android" | "iOS".
  "platforms": ["macOS", "windows", "linux"],

  // REQUIRED. Identifier strings, or objects that extend a permission's scope.
  "permissions": [
    "core:default",
    "opener:default",
    { "identifier": "fs:allow-read-text-file", "allow": [{ "path": "$APPDATA/projects/**" }] }
  ]
}
```

| Field | Required | Default | Gotcha |
| --- | --- | --- | --- |
| `identifier` | ✅ | — | Shown in denial messages as `referenced by: capability: <id>` |
| `description` | — | `""` | Free text; the only place a reviewer learns intent |
| `local` | — | **`true`** | Leave it alone unless you genuinely want a remote-only capability |
| `remote.urls` | — | unset | URLPattern strings. `remote` **widens**, never narrows — see below |
| `windows` | — | unset | Glob against the **window label**, not the URL or title |
| `webviews` | — | unset | Only meaningful with the `unstable` multiwebview feature |
| `platforms` | — | all | Case-sensitive: `macOS`, `iOS` — not `macos`, `ios` |
| `permissions` | ✅ | — | Strings, or `{ identifier, allow?, deny? }` scope-extension objects |

Discovery: with `app.security.capabilities` unset or `[]`, **every file in `capabilities/` is
compiled in**. Putting identifiers in that array turns it into an allowlist — a file you forget
to list silently stops applying. That array is also RFC 7396 array-replaced by any platform
overlay (`cheatsheets/cli-and-config.md`).

---

## ⚠️ `remote.urls` only ever widens

`local` defaults to `true`. Adding `remote` does **not** restrict the capability to those
origins — it adds them to the local origin already granted.

| You wrote | Origins that get these permissions |
| --- | --- |
| *(no `remote`)* | local only |
| `"remote": { "urls": [...] }` | local **and** the listed remotes |
| `"local": false, "remote": { "urls": [...] }` | the listed remotes only |

Never attach `remote` to a capability that carries filesystem, shell, or process permissions.

---

## Permission identifier grammar

| Form | Example | Means |
| --- | --- | --- |
| `<name>` (no prefix) | `allow-open-project` | A permission **your app** defines in `src-tauri/permissions/*.toml` |
| `<plugin>:<permission>` | `fs:allow-read-text-file` | One plugin permission |
| `<plugin>:default` | `opener:default` | The plugin author's default **set** |
| `core:<module>:<permission>` | `core:window:allow-set-title` | One core permission |
| `core:<module>:default` | `core:event:default` | One core module's default set |
| `core:default` | `core:default` | All nine core module defaults |
| `<plugin>:deny-<permission>` | `fs:deny-webview-data-linux` | Explicit denial — read the precedence table before using |

**`*` is not a wildcard here.** `permission_name` must resolve to `default`, a permission-set
name, or a permission name, otherwise the build fails with `UnknownPermission`. The only place
`<plugin>:*` is accepted is the CLI: `tauri permission rm <plugin>:*`.

Permission **files** are TOML only (`src-tauri/permissions/*.toml`); capability files may be
JSON, JSON5 or TOML.

### What `core:default` expands to

Exactly nine module default sets — nothing else:

```
core:app:default  core:event:default  core:image:default  core:menu:default
core:path:default core:resources:default core:tray:default core:webview:default
core:window:default
```

Mostly read-only and mostly fine. The two entries to actually think about are
`core:event:allow-emit-to` (a cross-window control channel) and
`core:webview:allow-internal-toggle-devtools`. Not in any default, therefore genuinely opt-in:
`core:window:allow-create`, `allow-set-title`, `allow-close`, `allow-destroy`;
`core:webview:allow-create-webview-window`, `allow-print`;
`core:app:allow-remove-data-store`. Per-module contents and why the two matter:
`references/security.md`.

---

## Precedence — and the global deny footgun

| Layer | Rule | Verified in |
| --- | --- | --- |
| 1. Command deny | If a command name appears in **any** capability's deny list, it is denied. Checked first, before anything else | `authority.rs::resolve_access` |
| 2. Command allow | Must match origin **and** (`windows` glob **or** `webviews` glob) | same |
| 3. Absence | No matching allow = denied. There is no implicit grant | same |
| 4. Scope deny | Evaluated by the command implementation, ahead of scope allow | `references/security.md` §scopes |
| 5. Scope allow | Only what is listed | same |

### ⚠️ `deny-*` is app-global, not capability-local

`denied_commands` is a `BTreeMap` keyed by **command name only** — no window, no webview, and
in practice no origin filter either (`resolve_access` tests `.is_some()` on the map entry, so
the origin predicate cannot rescue it).

| You expected | What actually happens |
| --- | --- |
| `fs:deny-write-text-file` in `untrusted-panel.json` blocks writes for *that* window | It blocks `fs:write_text_file` for **every window in the app**, including `main` |
| Adding a `deny-*` "just to be safe" alongside the allow | The allow is dead; the command is denied everywhere |

**Consequence:** to restrict one window, give it a **narrower capability** — do not add a deny
to it. Reserve `deny-*` for things that must be off app-wide (the fs plugin's own
`deny-webview-data-*` is the model).

Scopes aggregate the same way: a scope attached to a permission with no command allow/deny
lands in the **plugin's global scope**, merged across every capability that contributes one.

---

## Scope syntax

A scope is `{ "allow": [...], "deny": [...] }` attached to a permission entry. Values are
arbitrary serde data — the **command** enforces them, the framework only delivers them.

### `fs` — entries are objects with a `path`

```jsonc
// ✅ CORRECT
{
  "identifier": "fs:allow-read-text-file",
  "allow": [{ "path": "$APPDATA/projects/**" }],
  "deny":  [{ "path": "$APPDATA/projects/.env" }]
}
```

```jsonc
// ❌ WRONG — three separate mistakes
{
  "identifier": "fs:allow-read-text-file",
  "allow": ["$APPDATA/projects/**"],          // bare string, not { "path": ... }
  "scope": [{ "path": "$APPDATA/**" }]        // no "scope" key on a permission entry
}
// and "$APPDATA/*" would not match a nested file at all — `*` stops at the separator
```

Variables usable in a path: `$AUDIO $CACHE $CONFIG $DATA $LOCALDATA $DESKTOP $DOCUMENT
$DOWNLOAD $EXE $FONT $HOME $PICTURE $PUBLIC $RUNTIME $TEMPLATE $VIDEO $RESOURCE $LOG $TEMP
$APPCONFIG $APPDATA $APPLOCALDATA $APPCACHE $APPLOG`.
`$DIR/*` is direct children only (`require_literal_separator` is hardcoded `true`);
`$DIR/**` is recursive but does **not** match `$DIR` itself, so a directory grant needs both
entries. `*` vs `**`, the leading-dot split between Windows and unix, and `../` handling:
`references/security.md` §scopes.

### `shell` — entries are named command configurations

```jsonc
// ✅ CORRECT — named config, fixed cmd, validated variable arg
{
  "identifier": "shell:allow-execute",
  "allow": [{
    "name": "git-status",
    "cmd": "git",
    "args": ["status", "--porcelain", { "validator": "[\\w./-]+" }]
  }]
}
```

```jsonc
// ❌ WRONG — this is a remote shell, not a scope
{
  "identifier": "shell:allow-execute",
  "allow": [{ "name": "run", "cmd": "sh", "args": true }]
}
```

| Key | Meaning | Gotcha |
| --- | --- | --- |
| `name` | Required. The string the frontend calls | Not the binary name |
| `cmd` | Required (non-sidecar). May start with a `$VAR` base dir | Fixed at build time; never interpolate webview input |
| `sidecar` | Required instead of `cmd` for sidecars | `{ name, sidecar: true, args }` |
| `args` | `true` (any args), `false` (none), or a list | `true` makes the scope meaningless |
| `args[]` string | Fixed positional argument | Must appear in order |
| `args[]` `{ "validator": "…" }` | Regex-validated variable | Wrapped in `^…$` unless `"raw": true`. `raw` without a full-string anchor is the standard exploit |

---

## "Permission denied at runtime" — symptom → field

The exact message text comes from `authority.rs`. Match the prefix, then check the field.

| Message | Check |
| --- | --- |
| `<cmd> not allowed. Permissions associated with this command: <list>` | No capability grants it. Add one identifier from `<list>` to a capability's `permissions` |
| `<cmd> not allowed. Command not found` | The plugin exists but nothing declares this command — wrong command name, or a plugin version skew |
| `<cmd> not allowed. Plugin not found` | The plugin is not registered in the `Builder` chain, or the `tauri-plugin-*` crate is missing |
| `<cmd> not allowed on window "<w>", webview "<wv>", URL: <origin>` | The capability's `windows` / `webviews` globs. The label is the **window label**, not the title |
| `<cmd> not allowed on origin [<origin>]. Please create a capability that has this origin on the context field.` | `local` / `remote.urls`. The message also prints every capability that matched a different context |
| `<cmd> explicitly denied on origin <origin>` | A `deny-*` permission **anywhere** in `capabilities/`. Grep the whole directory, not just the window's own file |
| Command works in dev, denied in the packaged app | `platforms` excludes the target OS, or `app.security.capabilities` lists identifiers and the file is not in the list, or a platform overlay replaced that array |
| No denial, but the command rejects with an empty/blocked result | You passed the ACL and failed the **scope**. Denial happens in the command body, not in `resolve_access` |
| Every `fetch()` fails while `http:default` is present | `http:default` enables the commands and allows **zero** origins. Add a URL scope |

Prefix note: the message names the command as `<plugin>.<command>` for plugin commands and the
bare name for your own; the resolver key is `plugin:<plugin>|<command>`.

---

## CLI helpers

```bash
tauri permission ls                       # every identifier available to this app
tauri permission ls fs -f read            # filter within one plugin
tauri permission add fs:allow-read-text-file main   # append to capabilities/main.json
tauri permission new my-perm --allow open_project --format toml -o src-tauri/permissions
tauri capability new untrusted-panel --windows preview --permission core:default
tauri permission rm fs:*                  # remove a plugin's permission files and references
```

Flags: `cheatsheets/cli-and-config.md`.

---

## Review checklist

1. One capability per trust level. A window rendering less-trusted content gets **its own
   file**, never a widening of `default`.
2. No `deny-*` used as a per-window restriction (see the footgun above).
3. No `remote` on a capability carrying fs, shell, or process permissions.
4. Every `<plugin>:default` in the list — do you know what it expands to?
   `tauri permission ls <plugin>` prints it.
5. Every scope glob: does `*` vs `**` do what you meant, and is there a `deny` for the secrets
   inside the allowed root?
6. Could you delete the plugin permission entirely by owning the command in Rust? That is the
   highest-leverage move available — `references/security.md`.

# Cheatsheet — CLI and `tauri.conf.json`

> Flags verified by running `tauri <cmd> --help` against **`tauri-cli 2.11.4`** on Windows,
> 2026-07-28. Config keys and defaults read from **`https://schema.tauri.app/config/2`**
> (`Config`, draft-07) the same day. Mechanism and reasoning live in
> `references/architecture.md` §Configuration architecture — this file is lookup only.

**Before you paste a config change:** check the compiled-in table below. A compiled-in key you
get wrong is wrong on every installed machine until they successfully update.

---

## CLI — the commands worth knowing

Invoke as `npm run tauri <cmd> --`, `pnpm tauri <cmd>`, `cargo tauri <cmd>`. `-v/--verbose` is
on every command; repeat (`-vv`) for more.

### `tauri dev`

| Flag | Effect | Gotcha |
| --- | --- | --- |
| `-c, --config <CONFIG>` | JSON string **or path** to `.json` / `.json5` / `.toml`, merged RFC 7396 | Repeatable; later wins. Platform overlay is applied **as well**, not instead |
| `-f, --features [<F>...]` | Cargo features to activate | Must be repeated on `tauri bundle` if you bundle separately |
| `-t, --target <TRIPLE>` | Target triple | — |
| `-r, --runner <BIN>` | Replace `cargo` | For `cross`, `cargo-zigbuild` etc. |
| `--release` | Run dev-mode app built in release profile | Still uses `devUrl`; not a substitute for `tauri build` |
| `-e, --exit-on-panic` | Kill the CLI on a Rust panic | Under `panic = "abort"` a command panic is silent process death — `references/case-studies.md` §12 |
| `--no-watch` | Disable the file watcher | Use when the watcher rebuild loop fights your frontend HMR |
| `--additional-watch-folders <P>` | Extra watch paths | Equivalent to `build.additionalWatchFolders` |
| `--no-dev-server` | Disable the built-in static dev server | Only relevant when `frontendDist` is a directory and `devUrl` is unset |
| `--port <PORT>` | Built-in static dev server port, default **1430** | env `TAURI_CLI_PORT` |
| `--no-dev-server-wait` | Don't wait for `devUrl` to answer before building | env `TAURI_CLI_NO_DEV_SERVER_WAIT` |

Argument passthrough: `tauri dev -- <runnerArgs> -- <appArgs>` — **two** `--` separators.

### `tauri build`

| Flag | Effect | Gotcha |
| --- | --- | --- |
| `-d, --debug` | Build with the debug profile, still bundles | Output lands in `target/debug/`, not `target/release/` |
| `-t, --target <TRIPLE>` | Target triple, or `universal-apple-darwin` | Universal needs **both** `aarch64-apple-darwin` and `x86_64-apple-darwin` installed |
| `-b, --bundles [<B>...]` | Space/comma separated bundle list | Accepted values are **host-dependent**; the full `BundleType` set is `deb` `rpm` `appimage` `msi` `nsis` `app` `dmg`. On Windows `--help` only offers `msi`, `nsis` |
| `--no-bundle` | Compile only, skip bundling | Pairs with a later `tauri bundle` |
| `-c, --config <CONFIG>` | Same merge semantics as `dev` | The supported way to ship a beta flavour |
| `-f, --features [<F>...]` | Cargo features | — |
| `--no-sign` | Skip code signing | CI without certs; **never** for a release artifact |
| `--skip-stapling` | Don't wait for notarization / don't staple | First notarization can take hours; re-enable stapling on later runs |
| `--ci` | Never prompt | env `CI=1` sets this |
| `--ignore-version-mismatches` | Suppress the Tauri package version-skew error | Only when you have proven the detection is wrong |

### `tauri bundle`

Bundles an **already-built** binary. Flags: `-d/--debug`, `-b/--bundles`, `-c/--config`,
`-f/--features`, `-t/--target`, `--ci`, `--no-sign`, `--skip-stapling`.

> Gotcha: `--features` and `--target` must **match the `tauri build --no-bundle` invocation
> exactly**, or the bundler picks up a binary you did not intend.

### `tauri icon`

```
tauri icon ./app-icon.png -o src-tauri/icons
```

| Flag | Effect | Gotcha |
| --- | --- | --- |
| `[INPUT]` | Squared PNG/SVG with transparency, **or** a manifest JSON. Default `./app-icon.png` | Manifest keys: `default` (required), `bg_color`, `android_bg`, `android_fg`, `android_fg_scale`, `android_monochrome`; paths relative to the manifest |
| `-o, --output <DIR>` | Default: `icons/` next to `tauri.conf.json` | — |
| `-p, --png <SIZES>` | Custom PNG sizes | **Suppresses the default icon set entirely** |
| `--ios-color <CSS>` | iOS icon background, default `#fff` | Overridden by manifest `bg_color` |

### `tauri signer`

```
tauri signer generate -w ~/.tauri/myapp.key
tauri signer sign -f ~/.tauri/myapp.key path/to/app.tar.gz
```

| Flag | Command | Notes |
| --- | --- | --- |
| `-w, --write-keys <PATH>` | `generate` | Without it the keypair only prints to stdout |
| `-f, --force` | `generate` | Overwrite an existing key file — ⚠️ one-way door, see below |
| `-p, --password <PW>` | both | env `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` |
| `-k, --private-key <STR>` | `sign` | env `TAURI_SIGNING_PRIVATE_KEY` (the key **content**) |
| `-f, --private-key-path <P>` | `sign` | env `TAURI_SIGNING_PRIVATE_KEY_PATH` |

> ⚠️ Regenerating the minisign keypair strands every installed client — the compiled-in
> `pubkey` no longer validates. `references/build-and-distribution.md` §signing, §updater.

### `tauri migrate`, `tauri info`

| Command | Flags | Notes |
| --- | --- | --- |
| `tauri migrate` | `-v` only | v1 → v2 codemod. Rewrites config, `Cargo.toml`, and JS imports; **does not** produce capability files that match your old allowlist — audit by hand against `references/security.md` |
| `tauri info` | `--interactive` (apply automatic fixes) | First command to run on any unfamiliar project |

### Also present

| Command | One-liner |
| --- | --- |
| `tauri add <PLUGIN>` | Adds Cargo + npm dep and registers the plugin. `-t/--tag`, `-b/--branch`, `-r/--rev`, `--no-fmt` |
| `tauri remove <PLUGIN>` | Inverse of `add` |
| `tauri permission ls [PLUGIN] [-f FILTER]` | List every permission identifier available — see `cheatsheets/capabilities-permissions.md` |
| `tauri permission add <IDENT> [CAPABILITY]` | Append a permission to a capability file |
| `tauri permission new [IDENT]` | `--allow`, `--deny`, `--format json\|toml`, `-o` |
| `tauri capability new [IDENT]` | `--windows`, `--permission`, `--format json\|toml`, `-o` |
| `tauri inspect wix-upgrade-code` | Prints the MSI Upgrade Code derived from `productName` — record it before renaming the product |
| `tauri completions -s <bash\|elvish\|fish\|powershell\|zsh> [-o FILE]` | Shell completions |

### `--config` and `TAURI_CONFIG`

```bash
# flavour build — preferred, because it is visible in the command and in review
pnpm tauri build --config src-tauri/tauri.beta.conf.json
```

| | `--config` | `TAURI_CONFIG` |
| --- | --- | --- |
| Accepts | JSON string or path, repeatable | JSON **string** only (the CLI's own transport for the same patch) |
| Merge | RFC 7396, in argument order | RFC 7396, applied in `tauri-build` |
| Rebuild trigger | yes | yes (`cargo:rerun-if-env-changed=TAURI_CONFIG`) |
| Failure mode | visible in the command | stale value in a shell or CI step, invisible in review |

Other build-time env vars set for the `before*Command` hooks: `TAURI_ENV_PLATFORM`,
`TAURI_ENV_ARCH`, `TAURI_ENV_FAMILY`, `TAURI_ENV_PLATFORM_VERSION`, `TAURI_ENV_PLATFORM_TYPE`,
`TAURI_ENV_DEBUG`.

---

## Platform overlays and the array trap

Files merged automatically into `tauri.conf.json`: `tauri.windows.conf.json`,
`tauri.macos.conf.json`, `tauri.linux.conf.json`, `tauri.android.conf.json`,
`tauri.ios.conf.json` (TOML: `Tauri.<platform>.toml`).

**RFC 7396 JSON Merge Patch: objects merge key-by-key, arrays are REPLACED wholesale, `null`
deletes a key.**

```jsonc
// tauri.conf.json          → { "bundle": { "resources": ["./res", "./licenses"] } }
// tauri.linux.conf.json    → { "bundle": { "resources": ["./linux-assets"] } }
// resolved on Linux        → { "bundle": { "resources": ["./linux-assets"] } }   // both originals GONE
```

Array-valued keys exposed to this: `bundle.resources`, `bundle.targets`, `bundle.icon`,
`bundle.externalBin`, `app.windows`, `app.security.capabilities`,
`app.security.assetProtocol.scope`. Overriding one window property means restating the whole
`app.windows` array. Why the standard is blunt on purpose, and the `"create": false` mitigation:
`references/architecture.md` §Configuration architecture.

**File formats.** JSON default. JSON5 (`tauri.conf.json` / `tauri.conf.json5`) and TOML
(`Tauri.toml`) need the `config-json5` / `config-toml` Cargo feature on **both `tauri` and
`tauri-build`** — one alone is a silent no-op. Field names are case-sensitive in all three.

---

## Config keys — compiled in vs runtime

| Compiled in — wrong ships to every machine | Runtime — fixable without a release |
| --- | --- |
| Everything in `tauri.conf.json`, incl. `plugins.updater.endpoints` and `pubkey` | Managed state (`references/ipc-and-commands.md` §State) |
| `app.security.capabilities`, CSP, every `capabilities/*.json` | A store / settings file you read at startup |
| Frontend assets and icons (embedded by `tauri-codegen`) | Window geometry you persist and restore |
| The registered command list | Env vars and CLI arguments |
| `identifier` → the WebView data directory | Anything you fetch from your own server |

Read access at runtime: `AppHandle::config()` / `Manager::config() -> &Config`. **There is no
runtime mutation API.** Reasoning and the trade-off: `references/architecture.md`
§Configuration architecture.

---

## Top level

| Key | Default | Note |
| --- | --- | --- |
| `identifier` | **required** | Reverse-DNS, charset `A–Z a–z 0–9 - .`. Drives bundle ID **and the WebView data dir** — ⚠️ changing it orphans all local storage/IndexedDB/cookies |
| `productName` | — | Pattern `^[^/\:*?"<>\|]+$` |
| `version` | falls back to `Cargo.toml` | Semver, or a path to a `package.json` |
| `mainBinaryName` | crate name | **No extension** — Tauri appends `.exe`. v2 does *not* auto-rename to `productName` |
| `app` / `build` / `bundle` / `plugins` | see below | — |
| `$schema` | — | Point at `../node_modules/@tauri-apps/cli/config.schema.json` or `https://schema.tauri.app/config/2` for editor completion |

## `app` / windows

`app` defaults: `{ enableGTKAppId: false, macOSPrivateApi: false, withGlobalTauri: false,
windows: [], security: {...} }`.

| Key | Default | Gotcha |
| --- | --- | --- |
| `app.withGlobalTauri` | `false` | Set only if you truly need `window.__TAURI__`; a global is reachable by any injected script |
| `app.macOSPrivateApi` | `false` | Required for `transparent: true` on macOS |
| `app.enableGTKAppId` | `false` | Linux only |
| `app.trayIcon` | — | `references/desktop-ux.md` §menus |
| `app.windows[].label` | `"main"` | Must be unique; this is the string every capability `windows` glob matches against |
| `app.windows[].create` | `true` | `false` = declare geometry in config, build it yourself with `WebviewWindowBuilder::from_config` |
| `app.windows[].url` | `"index.html"` | — |
| `app.windows[].dragDropEnabled` | `true` | **Set `false` to make HTML5 drag-and-drop work** — `references/desktop-ux.md` |
| `app.windows[].decorations` | `true` | `false` + custom titlebar → `references/case-studies.md` §4 |
| `app.windows[].transparent` | `false` | macOS needs `macOSPrivateApi`; idle GPU cost → `references/performance.md` §rendering |
| `app.windows[].titleBarStyle` | `"Visible"` | macOS only |
| `app.windows[].shadow` | `true` | `false` has no effect on a decorated Windows window |
| `app.windows[].useHttpsScheme` | `false` | Windows/Android. ⚠️ Flipping it **changes the origin** and orphans web storage — `references/cross-platform.md` §Windows |
| `app.windows[].devtools` | unset (on in debug) | Enabling in release needs the `devtools` Cargo feature — `references/debugging-and-testing.md` §devtools |
| `app.windows[].backgroundThrottling` | unset | Fixes timers/WS dying in a hidden window |
| `app.windows[].incognito` / `browserExtensionsEnabled` / `zoomHotkeysEnabled` | `false` | — |
| `app.windows[].contentProtected` | `false` | Blocks screen capture |
| `app.windows[].additionalBrowserArgs` | — | WebView2 only; **replaces** Tauri's defaults when set |

## `app.security`

| Key | Default | Gotcha |
| --- | --- | --- |
| `csp` | `null` | `null` means **no CSP header at all**. Tauri rewrites your asset hashes/nonces into it at compile time |
| `devCsp` | `null` | If unset, `csp` is used in dev too |
| `capabilities` | `[]` | **Empty = every file in `capabilities/` is included.** Listing identifiers switches to an allowlist |
| `assetProtocol.enable` | `false` | — |
| `assetProtocol.scope` | `[]` | Glob list; the fastest way to expose a whole filesystem → `references/security.md` |
| `pattern.use` | `"brownfield"` | `"isolation"` + `options.dir` for the isolation pattern |
| `freezePrototype` | `false` | — |
| `dangerousDisableAssetCspModification` | `false` | Name is the documentation |
| `headers` | `null` | Fixed key set: `Access-Control-*`, `Cross-Origin-{Embedder,Opener,Resource}-Policy`, `Permissions-Policy`, `Service-Worker-Allowed`, `Timing-Allow-Origin`, `X-Content-Type-Options`, `Tauri-Custom-Header`. Not applied to IPC or error responses |

## `build`

| Key | Default | Gotcha |
| --- | --- | --- |
| `devUrl` | `null` | Dev only |
| `frontendDist` | `null` | Directory **or** a URL. A directory is embedded and compressed at compile time |
| `beforeDevCommand` / `beforeBuildCommand` / `beforeBundleCommand` | `null` | Receive the `TAURI_ENV_*` vars |
| `features` | `null` | Cargo features always on |
| `additionalWatchFolders` | `[]` | `tauri dev` only watches known paths — extend it here or edits look ignored |
| `removeUnusedCommands` | `false` | Strips commands no capability grants. Turning it on can break a command you invoke from Rust-side plugin code |
| `runner` | `null` | — |

## `bundle`

| Key | Default | Gotcha |
| --- | --- | --- |
| `active` | `false` | `tauri build` bundles nothing until this is `true` |
| `targets` | `"all"` | `"all"`, one `BundleType`, or an array of them |
| `createUpdaterArtifacts` | `false` | **The updater ships nothing without this** — `references/build-and-distribution.md` §updater |
| `icon` | `[]` | Array → RFC 7396 replacement trap |
| `resources` | `null` | Array or object map; resolve at runtime via `PathResolver::resolve` |
| `externalBin` | `null` | Sidecars; the target triple suffix is mandatory on disk |
| `windows.webviewInstallMode` | `{ type: "downloadBootstrapper", silent: true }` | Offline installs need `embedBootstrapper` or `fixedRuntime` — `references/cross-platform.md` §Windows |
| `windows.allowDowngrades` | `true` | — |
| `windows.certificateThumbprint` / `timestampUrl` / `signCommand` | `null` | `references/build-and-distribution.md` §signing |
| `macOS.minimumSystemVersion` | `"10.13"` | Bounds your WKWebView feature baseline |
| `macOS.hardenedRuntime` | `true` | Required for notarization |
| `linux.appimage.bundleMediaFramework` | `false` | Needed for `<video>`/`<audio>` on many distros |
| `android.minSdkVersion` | `24` | — |
| `useLocalToolsDir` | `false` | Cache bundler tooling in-project instead of `$HOME` — useful in locked-down CI |

## `plugins`

Free-form map keyed by `Plugin::name()`; not covered by the core schema, so the CLI cannot
validate a typo here — a misspelled plugin key is silently ignored. The two that must be right
on the **first** release, because they are compiled in:

```jsonc
"plugins": {
  "updater": {
    "endpoints": ["https://a.example.com/{{target}}/{{arch}}/{{current_version}}",
                  "https://b.example.com/{{target}}/{{arch}}/{{current_version}}"],
    "pubkey": "dW50cnVzdGVkIGNvbW1lbnQ6..."
  }
}
```

One endpoint is one permanent point of failure, and `check()` returns `Ok(None)` on HTTP `204`
**without trying the next endpoint**. Design and failure modes:
`references/build-and-distribution.md` §updater, §update security; a shipping app with exactly
this exposure: `references/case-studies.md` §6.

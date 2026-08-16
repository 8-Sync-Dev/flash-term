# Build and distribution — bundling, signing, updating, shipping

## Sections

- How to read this file: one-way doors versus reversible choices
- Build pipeline: `dev`, `build`, `bundle`
- Build-time environment variables
- Cross-compilation: what actually works, bluntly
- Bundle targets, and the two defaults that produce no installer
- Resources, sidecars, and icons
- Windows packaging: NSIS vs WiX, and the `upgradeCode` one-way door
- Windows code signing, and what SmartScreen actually requires
- macOS: sign, notarize, staple
- Linux signing: the honest picture
- Updater: keys, artifacts, configuration
- Updater manifest, URL variables, and the undocumented per-bundle-type keys
- Updater runtime API and per-OS install semantics
- Update security: three distinct failure modes
- CI/CD with `tauri-apps/tauri-action`
- Distribution channels: what each one actually demands
- Versioning
- Release one-way-door checklist
- v1 → v2 delta for distribution

---

## How to read this file: one-way doors versus reversible choices

Two ideas from the mental model govern everything below.

**Configuration is compiled in** (SKILL.md §5). `tauri.conf.json` is baked into the binary by
`tauri::generate_context!()` at build time. Updater endpoints, the public key, the bundle
identifier, the CSP and the capability set all ship as constants. A wrong value is wrong on
every installed machine, forever, unless you can push an update.

**The updater is the only mechanism that can repair a shipped mistake** (SKILL.md §6). Which
means the updater is the one subsystem whose failure is not recoverable by fixing the
subsystem. If the endpoint list, the keypair, or the signature pipeline was wrong at release
time, you cannot ship the fix through the thing that is broken.

Together they produce a hard split in the release surface. Some decisions you can change next
Tuesday. Some you can never change for the users who already installed.

| Decision | Reversible? | What it costs to get wrong |
| --- | --- | --- |
| `identifier` | **NO** — one-way door | Install path, Windows webview data origin, macOS bundle ID, App Store registration. Changing it produces a *different app* beside the old one. See §Release one-way-door checklist. |
| `bundle.windows.wix.upgradeCode` | **NO** for MSI users already installed | Duplicate entries in Add/Remove Programs; updates install alongside instead of over. §Windows packaging. |
| Minisign keypair (`pubkey` + private key) | **NO** — loss is terminal | No further updates to the installed base, ever. §Updater keys. |
| `plugins.updater.endpoints` (the whole list) | **NO** — compiled in | Stranded clients with no in-band recovery path. §Update security. |
| Signing certificate subject / publisher name | **NO** in practice | Windows SmartScreen reputation is per-certificate and restarts. §Windows signing. |
| `productName` | **Effectively NO** on Windows | Derives `upgradeCode`, install dir, ARP `DisplayName`. §Windows packaging. |
| `bundle.rpm.epoch` | **NO** | Permanently alters how the package manager orders your versions. §Versioning. |
| Version scheme (semver pre-release usage) | Painful | MSI cannot express `1.0.0-beta.3`; the updater requires valid semver. §Versioning. |
| `createUpdaterArtifacts: "v1Compatible"` | Yes, but gated on adoption | You can only move to `true` when no v1 clients remain. Removed in v3. §Updater artifacts. |
| NSIS `installMode` (`currentUser` ↔ `perMachine`) | **Practically NO** | Different install root and registry hive; the old install is orphaned. `[INFERENCE]` §Windows packaging. |
| Shipping via Flatpak/Snap | Yes, per-channel | Those stores own updates; the Tauri updater does not apply, so it is a separate build flavour. §Distribution channels. |
| `bundle.targets`, `webviewInstallMode`, NSIS images/languages/compression, `resources`, `externalBin` layout, CI wiring, `timestampUrl`, updater `installMode`/`installerArgs` | **Yes** | Rebuild and re-release. Cheap. Do not agonise over these. |

Everything marked **one-way door** below gets reviewed before release #1, not after.

**Version baseline for this file.** `tauri 2.11.5` (config schema `$id`
`https://schema.tauri.app/config/2.11.5`), `@tauri-apps/cli 2.11.4` (npm `latest`),
`tauri-plugin-updater 2.10.1` (deps: `minisign-verify 0.2`, `reqwest 0.13`, `semver 1`;
requires Rust ≥ 1.77.2), `tauri-apps/tauri-action@v1`. Verified 2026-07-27. Plugin versions are
released independently of core `tauri` in v2 — never assume `tauri` and `tauri-plugin-*` share
a version number. The CLI's `check_mismatched_packages` warns on inconsistent Tauri package
versions during `build`; `--ignore-version-mismatches` suppresses it, and the symptom of
suppressing it is unexplained runtime IPC/ACL failures rather than a build error.

Updater support matrix in 2.10.1: `windows` / `linux` / `macos` full, `android` / `ios`
**none**. If your app is desktop+mobile, the mobile stores are your update mechanism and
§Update security applies only to the desktop half.

---

## Build pipeline: `dev`, `build`, `bundle`

**Mechanism.** Three commands with three distinct config inputs.

- `tauri dev` reads `build.devUrl`, runs `build.beforeDevCommand`, and watches Rust for
  hot-reload.
- `tauri build` reads `build.frontendDist`, runs `build.beforeBuildCommand`, compiles in
  release, then runs `build.beforeBundleCommand` before producing bundles and installers.
- `tauri bundle` produces bundles from an *already built* binary.

`build` flags that change the artifact, not just the log: `-d/--debug` (debug profile, sets
`TAURI_ENV_DEBUG=true` for hooks), `-t/--target <TRIPLE>` (any `rustc --print target-list`
value **plus** the synthetic `universal-apple-darwin`), `-f/--features`, `-b/--bundles`
(overrides `bundle.targets` **and forces bundling even when `bundle.active=false`**),
`--no-bundle`, `-c/--config` (repeatable; JSON string, or JSON/JSON5/TOML file; merged in
order), `--skip-stapling` (macOS, §macOS signing), `--no-sign`, `--no-binary-patching`
(§Updater manifest), `--ignore-version-mismatches`.

`build` config keys: `runner`, `devUrl`, `frontendDist` (directory path, URI, or array of
files), `beforeDevCommand`, `beforeBuildCommand`, `beforeBundleCommand`, `features`,
`removeUnusedCommands` (default `false`), `additionalWatchFolders` (default `[]`),
`windows.staticVCRuntime` (default `true`). `beforeDevCommand` accepts a string **or**
`{ script, cwd?, wait? }` (`wait` default `false`); the two build hooks accept a string or
`{ script, cwd? }` and have **no `wait` field**. Hooks run through `cmd /S /C` on Windows and
`sh -c` elsewhere, with cwd defaulting to the *frontend* directory, not `src-tauri`.

**Why the build/bundle split exists.** One Rust compile can feed several bundle
configurations. The App Store build and the direct-download build differ only in config, not
in code, so recompiling for both is waste. The canonical shape is:

```sh
tauri build --no-bundle
tauri bundle --bundles app,dmg
tauri bundle --bundles app --config src-tauri/tauri.appstore.conf.json
```

`beforeBundleCommand` exists for the narrow case of mutating the compiled binary or its
resources before packaging — extra signing passes, stripping, injecting a build stamp.

**Trade-offs.** `--config` merging is powerful and silent. A typo'd key in an overlay file is
**not rejected at the overlay level**; the wrong value surfaces as a bundler failure much
later, in a different subsystem, with an unrelated error message. Prefer the auto-merged
platform files — `tauri.windows.conf.json`, `tauri.macos.conf.json`, `tauri.linux.conf.json`
(also `Tauri.<platform>.toml`) — because they are schema-validated in place, and reserve
`--config` for genuine build *flavours* (store vs direct, staging vs production endpoints).

`removeUnusedCommands: true` shrinks the command surface by dropping commands no capability
references. That is a real security and size win and it is also a foot-gun if you invoke
commands dynamically; leave it off unless your `generate_handler!` list is fully covered by
static capability references.

**Failure modes, symptom-first.**

| Symptom | Cause | Fix |
| --- | --- | --- |
| `The default value com.tauri.dev is not allowed as it must be unique across applications.` | `identifier` never changed from the scaffold | Set a real reverse-DNS identifier — and read §Release one-way-door checklist first, this is permanent |
| Hard error on identifier characters | Identifier contains anything outside `A-Za-z0-9`, `-`, `.` | Rename; underscores are not allowed |
| Warning about `.app` suffix | Identifier ends in `.app` | Rename; it collides with the macOS bundle extension |
| `Unable to find your web assets, did you forget to build your web app?` | `frontendDist` directory does not exist | In CI this is almost always a missing `npm run build` because `beforeBuildCommand` is unset |
| Hard error naming `node_modules` / `src-tauri` / the target dir | `frontendDist` points at a parent directory — people write `"../"` | Point it at the actual dist output |
| `tauri build` completes but there is no installer | `bundle.active` is `false` (**the schema default**) | Set `bundle.active: true`, or pass `--bundles`. §Bundle targets |
| `tauri dev` hangs ~3 minutes then fails | Frontend bound a different host/port than `devUrl`; the CLI retries 90× at 2 s with a 1 s connect timeout | Fix the host, or `--no-dev-server-wait` |
| HMR silently not working in `dev` | `devUrl` unset **and** `frontendDist` is an existing directory, so the CLI started its own static dev server and injected `devUrl` | `--no-dev-server`, or configure `devUrl` properly |
| Config rejected with `additionalProperties: false` | You copied a v1-era snippet | §v1 → v2 delta |

**When to deviate.** `--no-bundle` in PR CI is correct: you want compile errors fast and you
do not want to pay for NSIS/WiX/AppImage tooling on every push. Reserve full bundling for
release tags and for a nightly job that proves the bundler still works.

**Evidence.** `crates/tauri-cli/src/build.rs`, `crates/tauri-cli/src/dev.rs` (bail/warn paths
quoted above), `config.schema.json` (`BuildConfig`, `BeforeDevCommand`, `HookCommand`,
`FrontendDist`), <https://v2.tauri.app/reference/cli/>. Verified against schema 2.11.5.

---

## Build-time environment variables

**Mechanism.** Two families, and confusing them wastes real time.

*Family 1 — CLI inputs.* Read by the CLI/bundler itself. The CLI flag wins if both are set.
`CI`, `TAURI_CLI_CONFIG_DEPTH`, `TAURI_CLI_PORT`, `TAURI_CLI_WATCHER_IGNORE_FILENAME`,
`TAURI_CLI_NO_DEV_SERVER_WAIT`, `TAURI_LINUX_AYATANA_APPINDICATOR`,
`TAURI_BUNDLER_WIX_FIPS_COMPLIANT`, `TAURI_BUNDLER_TOOLS_GITHUB_MIRROR` (+
`..._MIRROR_TEMPLATE`, e.g.
`https://mirror.example.com/<owner>/<repo>/releases/download/<version>/<asset>`),
`TAURI_SKIP_SIDECAR_SIGNATURE_CHECK`, `TAURI_SIGNING_PRIVATE_KEY`,
`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`, `TAURI_SIGNING_RPM_KEY`,
`TAURI_SIGNING_RPM_KEY_PASSPHRASE`, `TAURI_WINDOWS_SIGNTOOL_PATH`, `TAURI_WEBVIEW_AUTOMATION`,
and the `APPLE_*` set (§macOS signing).

*Family 2 — set by the CLI **for** your hook commands.* Available inside
`beforeDevCommand` / `beforeBuildCommand` / `beforeBundleCommand`: `TAURI_ENV_DEBUG`
(`true` for `dev` and `build --debug`), `TAURI_ENV_TARGET_TRIPLE`, `TAURI_ENV_ARCH`,
`TAURI_ENV_PLATFORM` (`windows` | `darwin` | `linux` | …), `TAURI_ENV_PLATFORM_VERSION`,
`TAURI_ENV_FAMILY` (`unix` | `windows`). `tauri build` additionally exports
`MACOSX_DEPLOYMENT_TARGET` from `bundle.macOS.minimumSystemVersion`.

**Why family 2 exists.** So one frontend build script can emit platform-conditional output —
different asset base, different feature flags, a different sidecar name — without duplicating
npm scripts per platform. `TAURI_ENV_TARGET_TRIPLE` is the correct key for anything that
depends on the *target* rather than the *host*, which matters the moment your CI matrix
cross-compiles.

**Trade-offs.** Driving behaviour from hook env vars keeps the config small but moves logic
out of the schema-validated file into a shell script nobody validates. Prefer a
platform-suffixed config file when the difference is declarative; use hook env vars only when
the difference is *computed*.

**Failure modes, symptom-first.**

- **Symptom: build succeeds, no `.sig` files anywhere, updater silently never finds an
  update.** `TAURI_SIGNING_PRIVATE_KEY` was not in the process environment. The official
  updater docs are explicit: **`.env` files do *not* work.** Tauri does not load a `.env` for
  signing; the value must be exported into the real environment of the `tauri build` process.
  This is the single most common cause of a "the updater doesn't work" report that turns out
  to be a build problem, not a runtime one. (Second most common is
  `createUpdaterArtifacts: false` — §Updater artifacts.)
- **Symptom: you set `TAURI_SIGNING_PRIVATE_KEY_PATH` in CI and builds still produce no
  signatures.** `TAURI_SIGNING_PRIVATE_KEY_PATH` is real — it is the clap `env` binding on
  `tauri signer sign --private-key-path` — but it is **not listed on the environment-variable
  reference page and is consumed only by `tauri signer sign`, never by `build` or `bundle`**.
  For builds, only `TAURI_SIGNING_PRIVATE_KEY` is read, and it accepts either the key
  *content* or a path. Use the content form in CI; there is no file to leave behind.
- **Symptom: deprecation warnings about `TAURI_PRIVATE_KEY*`.** You copied a v1 blog post.
  `TAURI_PRIVATE_KEY`, `TAURI_PRIVATE_KEY_PATH`, `TAURI_PRIVATE_KEY_PASSWORD` are still
  accepted by `signer sign` with a warning and are scheduled for removal in v3.
- `TAURI_ENV_PLATFORM_TYPE` appears in the config schema's doc-comments for the three hook
  keys but is **absent from the environment-variable reference**. `[UNVERIFIED]` — do not
  build logic on it.

**When to deviate.** `TAURI_BUNDLER_TOOLS_GITHUB_MIRROR` is not optional in air-gapped or
China-based CI: the bundler downloads NSIS/WiX toolchains from GitHub releases on first use and
will simply fail without egress. Mirror it once and cache it.

**Evidence.** <https://v2.tauri.app/reference/environment-variables/>,
`crates/tauri-cli/src/signer/sign.rs`, `crates/tauri-cli/src/build.rs`,
<https://v2.tauri.app/plugin/updater/>. CLI 2.11.4.

---

## Cross-compilation: what actually works, bluntly

**Mechanism.** Tauri officially supports only the **MSVC** Windows target, so
"cross-compiling to Windows" means importing the MSVC SDK via `cargo-xwin`, not switching to
a GNU toolchain.

| Host → target | Reality | How |
| --- | --- | --- |
| → `.msi` | **Windows only.** No exceptions | WiX runs only on Windows. Also requires the **VBSCRIPT** optional Windows feature; without it you get `failed to run light.exe` |
| Linux/macOS → `nsis` | Works, with real friction | Install NSIS (`apt install nsis`; on Fedora copy Stubs/Plugins manually from `tauri-apps/binary-releases` `nsis-3.zip`; `brew install nsis`), `lld` + `llvm` (for `llvm-rc`), `rustup target add x86_64-pc-windows-msvc`, `cargo install --locked cargo-xwin`, then `tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc`. `XWIN_CACHE_DIR` shares the downloaded Windows SDK between projects. Docs call it "a last resort if local VMs or CI solutions like GitHub Actions don't work for you" |
| → macOS `.app` / `.dmg` | **Impossible** | "Running on a macOS machine is a requirement." Signing additionally requires an Apple device per Apple's T&Cs |
| x86_64 Linux → ARM AppImage | **Impossible** | `linuxdeploy` does not support cross-compiling ARM AppImages (linuxdeploy#258). Native ARM runner or emulation only |
| x86_64 Linux → ARM `.deb`/`.rpm` | Works | `rustup target add aarch64-unknown-linux-gnu`, `apt install gcc-aarch64-linux-gnu`, linker in `.cargo/config.toml`, `dpkg --add-architecture arm64`, add `ports.ubuntu.com` sources **and pin the existing lines to `[arch=amd64]`**, `apt install libwebkit2gtk-4.1-dev:arm64`, `export PKG_CONFIG_SYSROOT_DIR=/usr/aarch64-linux-gnu/` |
| Windows x64 → Windows arm64 | Works | VS Installer → `MSVC v143 - VS 2022 C++ ARM64 build tools`, `rustup target add aarch64-pc-windows-msvc`. Note: **the NSIS installer itself stays x86** and runs under emulation; only the app binary is native ARM64 |
| Windows x64 → Windows 32-bit | Works | `rustup target add i686-pc-windows-msvc` |
| macOS → universal | Works | `--target universal-apple-darwin`, with **both** `aarch64-apple-darwin` and `x86_64-apple-darwin` installed |

**Trade-offs.** Every cross-compilation path above trades a native runner (which you can
debug interactively) for a toolchain you have to reproduce exactly. On GitHub Actions a
`macos-latest` + `windows-latest` + `ubuntu-22.04` matrix costs you nothing but wall-clock and
removes the entire class of "works on my cross build, broken on the user's machine". The one
case where cross-compilation genuinely wins is ARM Linux `.deb`/`.rpm`, because native ARM
runners were public-repo-only until recently and QEMU is ~6× slower (§CI/CD).

**Failure modes, symptom-first.**

- **Symptom: user reports `/usr/lib/libc.so.6: version 'GLIBC_2.33' not found`.** You built on
  a newer distro than you support. glibc symbol versioning is forward-only: a binary linked
  against 2.35 will not run on 2.31. Build on the **oldest** base system you intend to support
  that still ships WebKitGTK 4.1 — Ubuntu 22.04 / Debian 12 provide `libwebkit2gtk-4.1-dev`.
  This is a build-host decision with the blast radius of a distribution decision (tauri#1355,
  rust#57497).
- **Symptom: cross-compiled Windows installer is unsigned even though signing is
  configured.** The default signing path shells out to `signtool.exe`, which does not exist on
  Linux/macOS. Cross-compiled Windows builds **must** use `bundle.windows.signCommand`
  (`osslsigncode`, `relic`, or a cloud signer). §Windows signing.
- **Symptom: v1-era CI snippet fails to link on Linux.** v2 moved from `webkit2gtk-4.0` to
  **`webkit2gtk-4.1`** (`libwebkit2gtk-4.1-dev`). Engine-level consequences of that move are
  `references/cross-platform.md`'s territory; here it is only a package name.

**When to deviate.** Cross-compiling to Windows from Linux is defensible for a fast local
smoke build when you have no Windows machine — but never as the release path, because the
installer you ship then has a different signing story than the one you tested.

**Evidence.** <https://v2.tauri.app/distribute/windows-installer/>,
`/distribute/debian/`, `/distribute/appimage/`, `/distribute/app-store/`,
`/distribute/sign/windows/`, `build.rs` `--target` doc comment. Verified 2026-07-27.

---

## Bundle targets, and the two defaults that produce no installer

**Mechanism.** `bundle.targets` accepts `"all"` (the default), a single `BundleType`, or an
array. The enum is exactly `"deb"`, `"rpm"`, `"appimage"`, `"msi"`, `"nsis"`, `"app"`, `"dmg"`
(case-insensitive). Bundling is gated by `bundle.active`.

**Two schema defaults account for the majority of "tauri build produced nothing" reports:**

1. **`bundle.active` defaults to `false`.** `tauri build` bundles only if `bundle.active ==
   true` **or** `--bundles` was passed. `create-tauri-app` scaffolds set it `true`, so the
   people who hit this are the ones who wrote or trimmed the config by hand — and the build
   exits 0 with no error, because not bundling is a legitimate mode.
2. **`bundle.createUpdaterArtifacts` defaults to `false`.** You get installers but no `.sig`
   files, so there is nothing to put in the updater manifest, so the updater never fires.
   §Updater artifacts.

Both are `false` because they are opt-in capabilities, not because they are unusual. Assert on
artifact *presence* in CI rather than on exit code; the exit code cannot distinguish "did not
bundle" from "bundled nothing".

**Choosing targets — with the actual reason and the actual cost.**

| Target | Pick it when | What it costs |
| --- | --- | --- |
| `nsis` (`-setup.exe`) | **Default Windows choice.** One multi-language installer, per-user install without admin, installer hooks, cross-compilable, silent `/S` | Not accepted by enterprise MSI-only deployment (GPO/SCCM) |
| `msi` | Enterprise/GPO deployment, or you need WiX fragments (registry keys, services, custom UI) | Windows-only build host; needs VBSCRIPT; **one `.msi` per language**; stricter downgrade UX |
| `app` | Required intermediate for everything on macOS; the App Store submission input | Not directly downloadable by users — no installer UX |
| `dmg` | Direct-download macOS | Mac build host + notarization. Note: **the `.dmg` is not an updater artifact** — the macOS updater payload is `.app.tar.gz` |
| `deb` | Ubuntu/Debian; also the **build input for Snap and Flatpak** recipes | 2–6 MB, but couples you to distro-provided `libwebkit2gtk-4.1-0`, `libgtk-3-0` (+ `libappindicator3-1` if you use a tray) |
| `rpm` | Fedora/RHEL/openSUSE | Same dependency coupling; `epoch` misuse breaks version comparison permanently |
| `appimage` | One file, no install, widest distro reach; the **only** Linux target the updater replaces in place | "the file size grows from the 2-6 MB range to **70+ MB**"; `bundleMediaFramework` adds a further 15–35 MB; ARM cannot be cross-compiled |

Auto-generated `deb` dependencies: `libwebkit2gtk-4.1-0`, `libgtk-3-0`, plus
`libappindicator3-1` when the app uses a system tray.

**Trade-off worth naming explicitly.** `targets: "all"` is the default and it is the wrong
default for most projects, because it makes every release build do the most expensive possible
work and produces artifacts you then have to explain to users ("which of these five files do I
download?"). Pick the two or three you will actually support and list them.

**Failure modes, symptom-first.**

- **Symptom: AppImage build fails on a `files` entry.** AppImage `files` destination paths
  "must currently begin with `/usr/`".
- **Symptom: audio/video does not play inside the AppImage but works from `tauri dev`.**
  Missing `appimage.bundleMediaFramework`. It is "currently only fully supported on Ubuntu
  build systems", and the GStreamer `ugly` plugin set carries licensing that "may make it hard
  to distribute them as part of your app" — that is a legal cost, not a size cost.
- **Symptom: a sidecar or `Command` invocation works in `tauri dev` and fails in the bundled
  app on macOS/Linux.** GUI apps launched from Finder/a desktop entry **do not inherit `$PATH`
  from shell dotfiles**. Use `tauri-apps/fix-path-env-rs`. This is not a bundling bug and no
  amount of `externalBin` configuration fixes it.

**When to deviate.** Ship `msi` alongside `nsis` only if you have an actual enterprise
customer asking for it, because it doubles your Windows signing surface, doubles your updater
manifest entries, and drags in the `updaterJsonPreferNsis` trap (§CI/CD).

**Evidence.** `config.schema.json` (`BundleTarget`, `BundleType`, `AppImageConfig`,
`DebConfig`), <https://v2.tauri.app/distribute/>, `/distribute/appimage/`,
`/distribute/debian/`, `/distribute/macos-application-bundle/`. Schema 2.11.5.

---

## Resources, sidecars, and icons

**Mechanism.** `bundle.resources` takes an array of paths (globs supported), which preserves
directory structure under `$RESOURCE/`:

```json
{ "bundle": { "resources": [
  "./path/to/some-file.txt",
  "../relative/path/to/jsonfile.json",
  "some-folder/",
  "resources/**/*.md"
] } }
```

or a map for explicit destinations — `{ "infoplist/**": "./" }` is how you place macOS
`InfoPlist.strings` localisation files.

`bundle.externalBin` takes paths absolute or relative to `src-tauri/`. **The naming convention
is load-bearing:** the bundler looks for `binary-name-<TARGET_TRIPLE>` (`.exe` appended on
Windows).

```
my-binary-x86_64-pc-windows-msvc.exe
my-binary-aarch64-apple-darwin
my-binary-x86_64-unknown-linux-gnu
```

Get the triple with `rustc --print host-tuple` (Rust ≥ 1.84.0) or the older
`rustc -Vv | grep host | cut -f2 -d' '`.

**Why the suffix exists.** One config entry has to resolve to a different binary per target,
and there is no other place to encode the target. It is also what makes a cross-compiling
matrix possible at all.

**Failure modes, symptom-first.**

- **Symptom: `tauri build` fails saying it cannot find the external binary you clearly put
  there.** `externalBin` entry has **no `-<target-triple>` suffix**. This is the single most
  common sidecar failure. The bundler is not looking for `binaries/app`; it is looking for
  `binaries/app-x86_64-pc-windows-msvc.exe`.
- **Symptom: `.exe.exe`, or the bundler cannot find the Windows binary.** The extension is
  appended for you. Do not put `.exe` in `externalBin`, and do not put it in
  `mainBinaryName` either ("this config should not include the binary extension").
- **Symptom: the docs' Node rename script produces the wrong suffix in CI.** It keys off the
  *host* triple. In a cross-compiling matrix you must key off `TAURI_ENV_TARGET_TRIPLE`.
- **Symptom: a vendored third-party binary stops working after bundling on macOS.** Tauri
  re-signs sidecars, which invalidates the vendor's signature.
  `TAURI_SKIP_SIDECAR_SIGNATURE_CHECK` exists for exactly this.
- **Symptom: `Command.sidecar()` throws in JS but the Rust `sidecar()` works.** Asymmetric
  API: the **JS argument must match the `externalBin` config string** (`'binaries/my-sidecar'`),
  while the **Rust argument is the bare filename** (`"my-sidecar"`).

```rust
use tauri_plugin_shell::ShellExt;
let sidecar_command = app.shell().sidecar("my-sidecar").unwrap();   // bare filename
let (mut rx, mut child) = sidecar_command.spawn().expect("Failed to spawn sidecar");
```

```ts
import { Command } from '@tauri-apps/plugin-shell';
const command = Command.sidecar('binaries/my-sidecar');  // must equal the externalBin entry
```

The capability entry needs `shell:allow-execute` for `.execute()` or `shell:allow-spawn` for
`.spawn()`, with `sidecar: true` and an `args` validator list. The ACL reasoning — why you
should prefer owning a Rust command over widening a shell scope — is `references/security.md`;
here only the packaging half matters.

**Icons.** `tauri icon /path/to/app-icon.png` generates every platform icon including the
Microsoft Store sizes; `--ios-color '#fff'` sets the iOS background. `bundle.icon` is the
resulting array. Reversible; regenerate freely.

**When to deviate.** If your "sidecar" is a small pure-Rust helper, do not make it a sidecar.
Compile it into the app as a module and call it directly: you delete the suffix problem, the
signing problem, the `$PATH` problem, and the ACL entry in one move.

**Evidence.** <https://v2.tauri.app/develop/sidecar/>, `config.schema.json`
(`BundleConfig.resources`, `externalBin`, `mainBinaryName`),
`/distribute/macos-application-bundle/`, `/distribute/microsoft-store/`. Schema 2.11.5.

---

## Windows packaging: NSIS vs WiX, and the `upgradeCode` one-way door

**Mechanism.** `bundle.windows` keys with their schema defaults:

| Key | Default | Note |
| --- | --- | --- |
| `digestAlgorithm` | `null` | file digest for signatures; SHA-256 recommended |
| `certificateThumbprint` | `null` | **SHA1** hash of the signing certificate — see §Windows signing |
| `timestampUrl` | `null` | timestamp server; not optional in practice |
| `tsp` | `false` | RFC 3161 TSP (e.g. SSL.com) |
| `webviewInstallMode` | `{ "type": "downloadBootstrapper", "silent": true }` | table below |
| `allowDowngrades` | `true` | `false` blocks installing older over newer |
| `minimumWebview2Version` | `null` | triggers the bootstrapper if the runtime is older |
| `signCommand` | `null` | custom signer; `%1` is the file path; object form `{ cmd, args }` for whitespace-safe args |
| `bundleVCRuntime` | `false` | ship VC++ runtime DLLs next to the app |

`webviewInstallMode` is the biggest single lever on installer size, and it is fully reversible:

| Mode | Needs internet | Extra installer size |
| --- | --- | --- |
| `downloadBootstrapper` (default) | Yes | 0 MB |
| `embedBootstrapper` | Yes | ~1.8 MB |
| `offlineInstaller` | No | ~127 MB |
| `fixedRuntime` | No | ~180 MB |
| `skip` | No | 0 MB — **the app will not work** if the runtime is absent |

`nsis` keys: `template`, `headerImage` (150×57), `sidebarImage` (164×314), `installerIcon`,
`uninstallerIcon`, `uninstallerHeaderImage`, `installMode` (default `"currentUser"`),
`languages` (default `["English"]`), `customLanguageFiles`, `displayLanguageSelector`
(default `false`), `compression` (`zlib` | `bzip2` | `lzma` (default) | `none`),
`startMenuFolder`, `installerHooks`, and a **deprecated** `minimumWebview2Version` (use the
`bundle.windows` one). Hook macros for `src-tauri/windows/hooks.nsh`: `NSIS_HOOK_PREINSTALL`,
`NSIS_HOOK_POSTINSTALL`, `NSIS_HOOK_PREUNINSTALL`, `NSIS_HOOK_POSTUNINSTALL`.

`NSISInstallerMode`: `currentUser` (default — `%LOCALAPPDATA%`, no admin, metadata under
`HKCU`), `perMachine` (`Program Files`, admin, `HKLM`), `both` (user chooses, **but the
installer requires admin regardless**, which defeats most of the reason to offer the choice).

`wix` keys: `version` (`major.minor.patch[.build]`; major/minor ≤ 255, third/fourth ≤ 65535),
`upgradeCode` (UUID), `language` (default `"en-US"`), `template`, `fragmentPaths`,
`componentGroupRefs`, `componentRefs`, `featureGroupRefs`, `featureRefs`, `mergeRefs`,
`enableElevatedUpdateTask` (default `false`), `bannerPath` (493×58), `dialogImagePath`
(493×312), `fipsCompliant` (default `false`).

**The one-way door: `wix.upgradeCode`.** When unset, Tauri derives it as a **UUID v5 in the
DNS namespace from the string `"<productName>.exe.app.x64"`**. Tauri's own documentation states
the constraint: the upgrade code **"must stay the same across all of your updates, otherwise
Windows will treat your update as a different app and your users will have duplicate
versions."**

Because the default is *derived from `productName`*, renaming your product silently changes
the upgrade code. Windows Installer then has no idea the new MSI supersedes the old one.

- **Symptom:** after a rename+release, MSI users see **two entries in Add/Remove Programs**,
  both apps present, the updater "worked" but installed alongside instead of over, and user
  data appears to have vanished because the new install has a different install root.
- **There is no fix for the users who already installed.** You cannot retroactively change the
  upgrade code recorded in their installed product. The best available remediation is to ship a
  new release that pins the *old* upgrade code (so subsequent updates chain correctly) and
  hand-hold users through uninstalling the duplicate. That is a support incident, not a patch.
- **Prevention, do this before release #1:**

```sh
tauri inspect wix-upgrade-code      # prints the currently-derived UUID
```

```json
{ "bundle": { "windows": { "wix": {
  "upgradeCode": "PASTE-THE-UUID-YOU-JUST-PRINTED"
} } } }
```

Pin it, commit it, and treat it as immutable. Do this **before** you ever rename
`productName`, because after the rename the command prints the *new* derived value and the old
one is gone unless you have an old build to read it from.

`[INFERENCE]` NSIS has no documented equivalent stable GUID, and its install directory and
Start Menu entry are derived from the product name. Treat a `productName` rename as risky on
**both** installers and verify empirically: install the old version on a clean VM, then run the
renamed installer, and check whether you end up with one app or two. Do not assume NSIS is
safe just because only WiX documents the hazard.

**Trade-offs.** NSIS's `currentUser` default is the right default — no admin prompt means no
UAC friction and a much higher install completion rate — and it costs you enterprise
deployability and makes the app invisible to machine-wide inventory tooling. `perMachine` buys
those and costs you the admin prompt. `both` costs you the admin prompt *and* gives no
benefit, so it is rarely the right answer.

**Failure modes, symptom-first.**

- **`failed to run light.exe`** → the **VBSCRIPT** optional Windows feature is not installed
  (WiX needs it), or you are not on Windows at all.
- **Only one `.msi` produced but you configured several languages** → WiX emits **one `.msi`
  per language**, suffixed with the language key; your release-asset naming and updater
  manifest must account for that, and if they do not, half your users get a 404.
- **A WiX fragment you wrote has no effect** → fragment ids must be referenced through
  `componentRefs` / `componentGroupRefs` / `featureRefs` / `featureGroupRefs` / `mergeRefs`, or
  they are **silently omitted** from the installer. No error.
- **Localised MSI shows English strings** → `WixLocalization@Culture` must match the configured
  language. The locale strings Tauri references are `LaunchApp`, `DowngradeErrorMessage`,
  `PathEnvVarFeature`, `InstallAppFeature`.
- **WebView2 bootstrapper fails on Windows 7 from an MSI** → TLS 1.2 unavailability; switch to
  `embedBootstrapper`. Win7 notifications additionally need
  `tauri-plugin-notification = { version = "2.0.0", features = ["windows7-compat"] }`.
- **Bundling fails only on a CI runner that runs as the Windows *System* user** (e.g. some EC2
  workloads) → AppData is restricted, so the WiX/NSIS tool cache cannot be written. Set
  `bundle.useLocalToolsDir: true` to cache into `target/.tauri/` instead.

**When to deviate.** `enableElevatedUpdateTask` (MSI) installs a scheduled task so updates can
elevate without prompting. It is a genuine convenience for `perMachine` installs and it is also
a persistent elevated task on every user's machine — a real attack surface. Only enable it if
`perMachine` is mandatory and you have reviewed the task's ACL.

**Evidence.** <https://v2.tauri.app/distribute/windows-installer/>, `config.schema.json`
(`WindowsConfig`, `NsisConfig`, `NSISInstallerMode`, `NsisCompression`, `WixConfig`,
`WixLanguage`, `WebviewInstallMode`, `BundleConfig.useLocalToolsDir`),
<https://v2.tauri.app/reference/cli/>. Schema 2.11.5.

---

## Windows code signing, and what SmartScreen actually requires

**Mechanism.** Signing on Windows is not required to *execute* a Tauri app. It is required to
avoid SmartScreen warnings and to list in the Microsoft Store. There are three paths, and
which one is available to you is decided by your certificate, not by preference.

**Path 1 — legacy OV `.pfx` in the certificate store** (Tauri's built-in `signtool` path). The
official docs carry a Danger callout: *"This guide only applies to OV code signing certificates
acquired before June 1st 2023!"*

```json
{ "bundle": { "windows": {
  "certificateThumbprint": "A1B1A2B2A3B3A4B4A5B5A6B6A7B7A8B8A9B9A0B0",
  "digestAlgorithm": "sha256",
  "timestampUrl": "http://timestamp.comodoca.com"
} } }
```

In CI: `certutil -encode certificate.pfx base64cert.txt` into secret `WINDOWS_CERTIFICATE`,
password into `WINDOWS_CERTIFICATE_PASSWORD`, `Import-PfxCertificate` in a PowerShell step
**before** `tauri-action` runs. `TAURI_WINDOWS_SIGNTOOL_PATH` overrides where `signtool.exe` is
found.

**Path 2 / 3 — `signCommand`.** This is the path everyone issued a certificate today must
take, because **OV certificates issued after 2023-06-01 and all EV certificates require the
private key to live on hardware (HSM or token)**. A key on an HSM cannot be imported into the
Windows certificate store as a `.pfx`, so `certificateThumbprint` cannot address it. That is
precisely why the docs mark the thumbprint path as legacy-only and push you to `signCommand`.

```json
{ "bundle": { "windows": {
  "signCommand": "relic sign --file %1 --key azure --config relic.conf"
} } }
```

`%1` is the file to sign; the object form `{ "cmd": "...", "args": ["...", "%1"] }` avoids
whitespace quoting problems. Cloud options with first-party docs: **`relic`** against Azure
Key Vault (`go install github.com/sassoftware/relic/v8@latest`; the app registration needs both
**Key Vault Certificate User** and **Key Vault Crypto User** roles, authenticated with
`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_CLIENT_SECRET`), and **Azure Artifact Signing**
(previously Azure Trusted Signing / Azure Code Signing) via `cargo install
artifact-signing-cli` and
`artifact-signing-cli -e https://wus2.codesigning.azure.net -a MyAccount -c MyProfile -d MyApp %1`.
On `-d`: *"When signing a .msi installer, this description will appear as the installer's name
in the UAC prompt or will be a random string of characters if unset."*

**A real, working Key Vault signing script exists in `references/case-studies.md` §7** — a
shipping app's `sign.ps1` wired through `signCommand`, plus the reason its RFC 3161 timestamp
flag is not optional. Read that instead of writing your own.

**What SmartScreen actually requires** (verbatim from the official docs):

- **EV certificate** → *"it'll receive an immediate reputation with Microsoft SmartScreen and
  won't show any warnings to users."*
- **OV certificate** → *"Microsoft SmartScreen will still show a warning to users when they
  download the app. It might take some time until your certificate builds enough reputation."*
  You may submit a specific file at <https://www.microsoft.com/en-us/wdsi/filesubmission> for
  manual review; *"Although not guaranteed … Microsoft may grant additional reputation and
  potentially remove the warning for that specific uploaded file."*

The operationally important part is the shape of OV reputation: it is per-**certificate** for
the trust anchor, but effectively per-**file** for the warning. Every new release ships a new
file hash and **restarts the per-file clock**. This is why teams on OV certificates still get
SmartScreen warnings months after issuance, and why a high release cadence makes it worse, not
better. Budget decision: EV costs more money once; OV costs support tickets on every release
until reputation accrues.

**One-way door: the certificate subject.** SmartScreen reputation attaches to the certificate.
Changing CA, changing the legal entity name in the subject, or letting a certificate lapse and
re-issuing under a different subject **restarts reputation from zero**. Pick the publisher name
you will use for the lifetime of the product before you buy the first certificate.

**Failure modes, symptom-first.**

- **`certificate not found` with a thumbprint you copied from the certificate details.** You
  copied the SHA-256 fingerprint. `certificateThumbprint` is the **SHA1** hash of the
  certificate (schema: "Specifies the SHA1 hash of the signing certificate") **regardless of
  what `digestAlgorithm` is set to**. `digestAlgorithm` controls the *file* digest in the
  signature; the thumbprint is how `signtool` *locates the cert in the store*. Two different
  things, and they are frequently conflated.
- **Signature applies but nothing changes / cert rejected.** You bought an SSL/TLS certificate.
  It does not work — you need a **code signing** certificate. Explicit docs warning.
- **Every installed copy starts warning on the day the certificate expires.** No RFC 3161
  timestamp. See `case-studies.md` §7 for the flag.
- **CI is green and the installers are unsigned.** `--no-sign` was passed (it logs
  `--no-sign flag detected: Signing will be skipped.` and exits 0), or `signCommand` failed in
  a way the bundler tolerated. Assert on the presence of a valid signature in CI
  (`signtool verify /pa`), never on exit code 0.
- **Cross-compiled installer unsigned.** §Cross-compilation — the default path needs
  `signtool.exe`.

**When to deviate.** For an internal-only tool distributed to managed machines, skip signing
entirely and deploy the certificate trust or an AppLocker rule instead. You are paying for
SmartScreen reputation, and SmartScreen is a consumer-download control.

**Evidence.** <https://v2.tauri.app/distribute/sign/windows/>, `config.schema.json`
(`WindowsConfig`, `CustomSignCommandConfig`),
<https://v2.tauri.app/reference/environment-variables/>,
`references/case-studies.md` §7. Verified 2026-07-27.

---

## macOS: sign, notarize, staple

**Mechanism.** Three separate operations, commonly confused, with different failure modes.

*Prerequisites.* A paid Apple Developer account (**$99/yr**) **and a macOS device to sign on** —
"This is required by the signing process and due to Apple's Terms and Conditions." On the free
plan you **cannot notarize** at all. Certificate types: `Developer ID Application` for
distribution **outside** the App Store; `Apple Distribution` for the App Store. Only the Apple
Developer **Account Holder** can create `Developer ID Application` certificates (they can be
associated with another Apple ID by generating the CSR from that user's email).

*Signing.* Install the `.cer`, find the identity with
`security find-identity -v -p codesigning`, then set `bundle.macOS.signingIdentity` or
`APPLE_SIGNING_IDENTITY`. In CI, export a `.p12`, base64 it into `APPLE_CERTIFICATE` +
`APPLE_CERTIFICATE_PASSWORD`, and do the keychain dance before building:

```yaml
- name: Import Apple Developer Certificate
  env:
    APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
    APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
    KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
  run: |
    echo $APPLE_CERTIFICATE | base64 --decode > certificate.p12
    security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
    security default-keychain -s build.keychain
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
    security set-keychain-settings -t 3600 -u build.keychain
    security import certificate.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" build.keychain
    security find-identity -v -p codesigning build.keychain
```

`APPLE_SIGNING_IDENTITY` is inferred from `APPLE_CERTIFICATE` when neither it nor
`signingIdentity` is set.

*Notarization.* Required whenever you use a `Developer ID Application` certificate. Both auth
modes are consumed automatically by `tauri build` / `tauri bundle`:

- **App Store Connect API key** (use this in CI): `APPLE_API_ISSUER`, `APPLE_API_KEY` (the Key
  ID), `APPLE_API_KEY_PATH` (the `.p8`). The `.p8` is downloadable **once**, and only after a
  page reload. If `APPLE_API_KEY_PATH` is unset the bundler searches `./private_keys`,
  `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys` for
  `AuthKey_<api_key>.p8` (`API_PRIVATE_KEYS_DIR` also sets the directory). For iOS,
  `APPLE_API_KEY_PATH` is required.
- **Apple ID**: `APPLE_ID`, `APPLE_PASSWORD` (an **app-specific password**; also accepts
  `@keychain:<item>` or `@env:<VAR>`), `APPLE_TEAM_ID`.

`APPLE_PROVIDER_SHORT_NAME` (also `bundle.macOS.providerShortName`) is **required when your
Apple ID belongs to more than one team**; without it notarization fails ambiguously.

*Hardened runtime and entitlements.* `bundle.macOS.hardenedRuntime` defaults to **`true`**.
`bundle.macOS.entitlements` points at an `Entitlements.plist`, and entitlements are applied **at
signing time** — so an unsigned build silently has none of them, which is why "it works locally
without signing, fails when signed" and "it works signed, fails unsigned" are both real
reports. Two real entitlement files from shipping apps, contrasted with the risk ordering of
each key and the failure each one fixes, are in **`references/case-studies.md` §5**. Read them
there; the rule they establish — add one entitlement at a time, with the error it resolves
written next to it — is the whole discipline.

*Stapling.* `tauri build --skip-stapling`. From the CLI source: *"Gatekeeper will look for
stapled tickets to tell whether your app was notarized without reaching out to Apple's servers
which is helpful in offline environments. Enabling this option will also result in `tauri build`
not waiting for notarization to finish which is helpful for the very first time your app is
notarized as this can take multiple hours. On subsequent runs, it's recommended to disable this
setting again."*

That is the pragmatic path for release #1: **`--skip-stapling` on the first notarization**,
because a multi-hour wait inside a CI job will hit the job timeout and you will be debugging the
wrong thing. Turn it back off for release #2 onward so that offline Gatekeeper checks pass.

**Trade-offs.**

- $99/yr is unavoidable for notarization. The free plan means a Gatekeeper warning for every
  user, forever.
- Not stapling means Gatekeeper contacts Apple at first launch — which fails in air-gapped and
  restricted-network environments. If any of your users are on a locked-down corporate network,
  stapling is not optional.
- Ad-hoc signing (`"signingIdentity": "-"`) is the escape hatch without a certificate. It is
  genuinely useful — on Apple Silicon all downloaded code must be signed at all, and the
  official GitHub pipeline page recommends ad-hoc precisely to *"avoid macOS treating Apple
  Silicon builds downloaded from GitHub releases as damaged."* The cost, stated by the docs:
  *"Ad-hoc code signing does not prevent MacOS from requiring users to whitelist the
  installation in their Privacy & Security settings."* Fine for internal builds and CI
  smoke-testing. Not shippable to the public. `case-studies.md` §7 has a real app that shipped
  exactly this and what it means.

**Failure modes, symptom-first.**

- **Users report "the application is damaged and can't be opened".** The app is signed but
  **not notarized**. The message is misleading — nothing is damaged, and it does not say
  "unsigned" — and it generates a disproportionate volume of support tickets because users
  reasonably conclude the download is corrupt. If you take one thing from this section: notarize
  before you publish a DMG anywhere.
- **The certificate does not appear in `security find-identity` output or in Keychain Access →
  My Certificates.** The certificate is invalid, or it landed in the wrong keychain. It must be
  in the **login** keychain. An invalid cert is *absent*, not marked invalid — so "I can't find
  it" and "it's broken" look identical.
- **`tauri build` hangs for hours on macOS in CI.** First notarization. Use `--skip-stapling`.
- **Entitlements appear to have no effect.** The build was not signed. Entitlements are applied
  by `codesign`.
- **Version numbers behave strangely, or the app reports the wrong version.** You overrode
  default `Info.plist` values. The docs warn this "might conflict with other configuration
  values and introduce unexpected behavior" — especially version keys, which Tauri generates
  from `version` / `bundle.macOS.bundleVersion`.
- **Localised app name does not appear.** `Info.plist` supports one language; localise with
  `<lang>.lproj/InfoPlist.strings` (capital I and P) bundled through `resources`.

**One-way door: the Apple Team ID + identifier pair.** The App Store registration binds a
bundle ID to a team, and `com.apple.application-identifier` in your entitlements is
`$TEAM_ID.$IDENTIFIER`. Moving either later means a new app record. `[INFERENCE]` Changing the
signing identity also invalidates keychain ACLs that were granted to the previous signature, so
credentials your app stored under the old identity may become unreadable — verify this on a real
machine before switching identities on a shipped app.

**Other `bundle.macOS` keys worth knowing exist:** `frameworks` (system frameworks by name
without `.framework`, resolved from `$HOME/Library/Frameworks`, `/Library/Frameworks/`,
`/Network/Library/Frameworks/`; local frameworks/dylibs by path relative to `src-tauri`),
`files` (dest→source, copied into `<app>.app/Contents/`), `bundleVersion`
(→ `CFBundleVersion`), `bundleName` (→ `CFBundleName`), `minimumSystemVersion` (default
`"10.13"`; `null` removes both `LSMinimumSystemVersion` and `MACOSX_DEPLOYMENT_TARGET`; ignored
in `tauri dev`), `exceptionDomain`, `infoPlist` (merged with the generated one; Tauri also
auto-picks up `src-tauri/Info.plist`), `dmg`.

The macOS updater payload is `.app.tar.gz`. The `.dmg` is **not** an updater artifact — see
§Updater artifacts.

**Evidence.** <https://v2.tauri.app/distribute/sign/macos/>,
`/distribute/macos-application-bundle/`, `/distribute/pipelines/github/`,
<https://v2.tauri.app/reference/environment-variables/>, `config.schema.json` (`MacConfig`,
`DmgConfig`), `crates/tauri-cli/src/build.rs` (`--skip-stapling` doc comment),
`references/case-studies.md` §5 and §7. Verified 2026-07-27.

---

## Linux signing: the honest picture

**Mechanism.** Three different stories, one of which is not a security control.

*AppImage* is signed by `appimagetool` through environment variables, not config:
`SIGN=1` enables it, `SIGN_KEY` selects a specific GPG key, `APPIMAGETOOL_SIGN_PASSPHRASE`
supplies the passphrase (**"You must set this when building in CI/CD platforms"** — otherwise
gpg opens an interactive dialog and the job hangs), and `APPIMAGETOOL_FORCE_SIGN=1` makes a
signing failure fail the build. **Without `APPIMAGETOOL_FORCE_SIGN`, the AppImage is produced
anyway when signing fails** — so a green build proves nothing. Inspect with
`./target/release/bundle/appimage/$APPNAME_$VERSION_amd64.AppImage --appimage-signature`.

*RPM* uses `TAURI_SIGNING_RPM_KEY` (the ASCII-armored **private** key *content*, e.g.
`export TAURI_SIGNING_RPM_KEY=$(cat my_private.key)`) and
`TAURI_SIGNING_RPM_KEY_PASSPHRASE`. Verification on the user side needs your public key
imported (`gpg --export -a 'Tauri-App' > RPM-GPG-KEY-Tauri-App`,
`sudo rpm --import RPM-GPG-KEY-Tauri-App`) plus `~/.rpmmacros` entries.

*deb* has **no first-party Tauri signing at all.** The Linux signing page covers AppImage only,
and the environment-variable reference lists RPM keys with no deb equivalent. If you need signed
`.deb`, the correct answer is to sign the **repository** (`Release.gpg` / `InRelease`) with
`reprepro` or `aptly` — which is how apt actually establishes trust — or `dpkg-sig` the artifact
as a post-build step. Signing individual `.deb` files is not how Debian trust works, so
repository signing is the better investment anyway.

**The thing you must not get wrong.** From the official Linux signing page, verbatim:
**"The signature is not verified. AppImage does not validate the signature, so you can't rely on
it to check whether the file has been tampered with or not. The user must manually verify the
signature using the AppImage validate tool. This requires you to publish your key ID on an
authenticated channel (e.g. your website served via TLS)."**

So: **AppImage GPG signatures are provenance metadata, not a runtime integrity control.**
Nothing checks them unless a human runs `validate-<platform>.AppImage` by hand, which
approximately nobody does. Do not present AppImage signing as protecting your users from a
tampered download; it does not.

What *is* enforced on Linux is the **Tauri updater's minisign signature** — verified in-process
before install, and it "cannot be disabled" (§Update security). That is your actual integrity
mechanism on Linux, which is another reason the updater is the load-bearing subsystem.

**Why Linux signing is optional at all.** Official framing: *"While artifact signing is not
required for your application to be deployed on Linux, it can be used to increase trust."*
Linux distributions locate trust in repositories and maintainers, not in per-binary
publisher certificates, so there is no Gatekeeper/SmartScreen equivalent to satisfy.

**Trade-offs.** Setting up RPM signing costs an afternoon and buys you `rpm -K` verifiability
and eligibility for a signed repo later. AppImage signing costs the same afternoon and buys
almost nothing verifiable. Spend the effort on the updater keypair and on repository signing if
you run a repo.

**Failure modes, symptom-first.**

- **CI job hangs on the AppImage step with no output.** gpg is waiting on a passphrase dialog.
  Set `APPIMAGETOOL_SIGN_PASSPHRASE`.
- **You believe you shipped signed AppImages and `--appimage-signature` prints nothing.**
  Signing failed and the build continued. Add `APPIMAGETOOL_FORCE_SIGN=1`.
- **`rpm -K` says NOKEY on the user's machine.** Expected — they have not imported your public
  key. Publish it over TLS and document the import step, or ship through a signed repository.

**When to deviate.** Skip Linux artifact signing entirely if you distribute only AppImage +
the updater, and say so plainly in your release notes rather than shipping a signature that
implies a guarantee you are not providing.

**Evidence.** <https://v2.tauri.app/distribute/sign/linux/>, `/distribute/rpm/`,
<https://v2.tauri.app/reference/environment-variables/>. Verified 2026-07-27.

---

## Updater: keys, artifacts, configuration

**Mechanism — installation.** `tauri add updater`, or manually:

```sh
cargo add tauri-plugin-updater --target 'cfg(any(target_os = "macos", windows, target_os = "linux"))'
npm install @tauri-apps/plugin-updater
```

```rust
// src-tauri/src/lib.rs
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(desktop)]
            app.handle().plugin(tauri_plugin_updater::Builder::new().build());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

The `cfg(...)` target guard is not cosmetic: the plugin has no mobile implementation, so an
unguarded dependency compiles code you cannot use into a mobile build.

Add `"updater:default"` to your capability — that set is exactly `allow-check` +
`allow-download` + `allow-install` + `allow-download-and-install`. If your frontend only
*checks* and a Rust command does the install, grant `updater:allow-check` alone. Permission-set
reasoning generally is `references/security.md`.

**Mechanism — the keypair. This is the one-way door.**

```sh
npm run tauri signer generate -- -w ~/.tauri/myapp.key
```

Flags: `-p/--password`, `-w/--write-keys <PATH>`, `-f/--force`, `--ci` (env `CI`). It writes
`<PATH>` (secret) and `<PATH>.pub` (public); both are base64-encoded minisign key boxes. The
CLI signs with the `minisign` crate; the runtime verifies with `minisign-verify 0.2`. Without
`-w` the keys go to stdout. With `--ci` and no `-p` the CLI generates a **password-less** key
and warns: *"For security reasons, we recommend setting a password instead."*

Build-time signing reads the environment, never a config value:

```sh
export TAURI_SIGNING_PRIVATE_KEY="<key content, or a path to the key file>"
export TAURI_SIGNING_PRIVATE_KEY_PASSWORD=""
```

Manual signing of an arbitrary file: `tauri signer sign -k <KEY_STRING> | -f <KEY_FILE>
[-p <PW>] <FILE>` (`-k` and `-f` are mutually exclusive). Output is `<file>.<ext>.sig`
containing the base64 minisign signature box, with trusted comment
`timestamp:<unix>\tfile:<filename>`.

**Where the private key must live.** In a real secrets manager — GitHub Actions encrypted
secret, HashiCorp Vault, Azure Key Vault — with the **password stored separately from the key**,
plus an **offline backup** (a printed/air-gapped copy). The docs are blun: *"You should NEVER
share this key with anyone … It is important to store this key in a safe place!"* and *"if you
lose this key you will NOT be able to publish new updates to the users that have the app already
installed."* There is no recovery path short of shipping a fresh installer out-of-band and
convincing every user to run it. A password-less CI key trades convenience for "one env-var leak
from total compromise" — and compromise here means the attacker can sign payloads that every
installed client trusts.

**Mechanism — artifacts.** Driven by `bundle.createUpdaterArtifacts` (**default `false`**).

`true` (v2 mode — the real installers double as updater payloads):

```
bundle/appimage/  myapp.AppImage          myapp.AppImage.sig
bundle/macos/     myapp.app.tar.gz        myapp.app.tar.gz.sig
bundle/nsis/      myapp-setup.exe         myapp-setup.exe.sig
bundle/msi/       myapp.msi               myapp.msi.sig
```

`"v1Compatible"` (legacy wrappers): `myapp.AppImage.tar.gz(.sig)`, `myapp.app.tar.gz(.sig)`,
`myapp-setup.nsis.zip(.sig)`, `myapp.msi.zip(.sig)`. Docs: *"**This setting will be removed in
v3** so make sure to change it to `true` once all your users are migrated to v2."*

`true` halves your release asset count. `"v1Compatible"` is required **only** while v1 clients
still exist in the field, because v1 clients expect the zipped shapes — and once you set it, you
cannot move to `true` until those clients are gone, which is the one part of this decision that
is not freely reversible.

**Mechanism — configuration.**

```json
{
  "bundle": { "createUpdaterArtifacts": true },
  "plugins": {
    "updater": {
      "pubkey": "CONTENT OF myapp.key.pub",
      "endpoints": [
        "https://releases.myapp.com/{{target}}/{{arch}}/{{current_version}}",
        "https://github.com/user/repo/releases/latest/download/latest.json"
      ],
      "windows": { "installMode": "passive", "installerArgs": [] }
    }
  }
}
```

Documented keys: `pubkey` (**the key content — "It cannot be a file path!"**), `endpoints`
(*"TLS is enforced in production mode. Tauri will only continue to the next url if a non-2XX
status code is returned!"* — read §Update security before you rely on that sentence),
`dangerousInsecureTransportProtocol`, `windows.installMode`. Source-verified but **absent from
the docs page** (`plugins/updater/src/config.rs`, 2.10.1): `dangerousAcceptInvalidCerts`,
`dangerousAcceptInvalidHostnames`, `windows.installerArgs`. Kebab-case aliases are also accepted
(`install-mode`, `installer-args`, `dangerous-accept-invalid-certs`, …).

**Failure modes, symptom-first.**

- **Updater never finds an update, no error, `check()` returns null.** In order of frequency:
  (1) `createUpdaterArtifacts` is `false` so there are no `.sig` files and your manifest is
  either missing signatures or was never generated; (2) `TAURI_SIGNING_PRIVATE_KEY` was not in
  the process environment (`.env` does **not** work); (3) the primary endpoint returned
  `204` — §Update security failure mode 2.
- **`Error::EmptyEndpoints`** at `build()` time, not at `check()` time — an empty endpoints list
  fails when the updater is constructed. Good: it is a startup failure, not a silent one.
- **Signature validation fails on a manifest you hand-wrote.** `signature` must be the `.sig`
  file **contents**; "A path or URL does not work!" And the contents **change on every build**
  even for byte-identical source, so the manifest must be regenerated per release, not
  hand-maintained.
- **Updates broken on every platform after adding one new platform entry.** *"Tauri will
  validate the whole file before checking the version field, so make sure all existing platform
  configurations are valid and complete."* One malformed entry breaks all platforms.

**v1 → v2 changes here** (agents will find v1 posts): config moved from `tauri.updater.*` to
`plugins.updater.*` plus `bundle.createUpdaterArtifacts`; `tauri.updater.active` and
`tauri.updater.dialog` are **gone** — there is **no built-in update dialog in v2**, you build
the UI; env vars renamed `TAURI_PRIVATE_KEY*` → `TAURI_SIGNING_PRIVATE_KEY*`; the updater is now
an opt-in plugin gated by an ACL permission.

**Evidence.** <https://v2.tauri.app/plugin/updater/>,
`crates/tauri-cli/src/signer/{generate,sign}.rs`,
`crates/tauri-cli/src/helpers/updater_signature.rs`, `plugins/updater/src/config.rs`,
`config.schema.json` (`Updater`, `V1Compatible`). Updater plugin 2.10.1.

---

## Updater manifest, URL variables, and the undocumented per-bundle-type keys

**Mechanism — URL variable substitution.** Documented: `{{current_version}}`, `{{target}}`
(`linux` | `windows` | `darwin`), `{{arch}}` (`x86_64` | `i686` | `aarch64` | `armv7`).

**Source-verified and undocumented: `{{bundle_type}}`**, which resolves from
`tauri::utils::platform::bundle_type()` to `appimage` | `deb` | `rpm` | `app` | `msi` | `nsis`,
or the literal string `"unknown"`. Both raw and percent-encoded forms are substituted
(`%7B%7Barch%7D%7D`, `%7B%7Bbundle_type%7D%7D`, …), so the variables work inside path segments
*and* query strings. Custom variables are not supported. When you build an endpoint string with
Rust `format!()`, you need quadruple braces: `{{{{target}}}}`.

`{{bundle_type}}` is the variable that lets a dynamic update server answer correctly for a user
who installed the `.deb` versus the AppImage — without it, a single Linux endpoint has to guess.
Because it is undocumented, treat it as source-verified against **updater 2.10.1** and re-verify
before relying on it after an upgrade.

**Mechanism — static JSON manifest.** The correct v2 shape:

```json
{
  "version": "1.4.2",
  "notes": "Fixes the crash on window close and adds dark mode.",
  "pub_date": "2026-07-27T14:03:11Z",
  "platforms": {
    "windows-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkKUlVSVFkw...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/MyApp_1.4.2_x64-setup.exe"
    },
    "windows-x86_64-msi": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/MyApp_1.4.2_x64_en-US.msi"
    },
    "windows-aarch64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/MyApp_1.4.2_arm64-setup.exe"
    },
    "darwin-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/MyApp_1.4.2_x64.app.tar.gz"
    },
    "darwin-aarch64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/MyApp_1.4.2_aarch64.app.tar.gz"
    },
    "linux-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/my-app_1.4.2_amd64.AppImage"
    },
    "linux-x86_64-deb": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6...",
      "url": "https://github.com/me/app/releases/download/v1.4.2/my-app_1.4.2_amd64.deb"
    }
  }
}
```

Key semantics: `version` must be valid **SemVer**, with or without a leading `v` (both `1.0.0`
and `v1.0.0` are accepted). `notes` is free text. `pub_date` must be **RFC 3339** if present.
Platform keys are `<OS>-<ARCH>` with OS ∈ `linux` | `darwin` | `windows` and ARCH ∈ `x86_64` |
`aarch64` | `i686` | `armv7`. Required fields are `version`, `platforms.<key>.url`,
`platforms.<key>.signature`; everything else is optional.

**The undocumented per-bundle-type keys.** `Updater::get_urls` searches, in order:

```
"{os}-{arch}-{installer}"      ← tried FIRST
"{os}-{arch}"                  ← fallback
```

So `windows-x86_64-nsis`, `windows-x86_64-msi`, `linux-x86_64-deb`, `linux-x86_64-rpm`,
`linux-x86_64-appimage`, `darwin-aarch64-app` are all valid keys, and the client picks the entry
matching **how the running app was actually installed**. This is the correct fix for the class
of bug where an MSI user gets handed a `-setup.exe` (or vice versa — see the
`updaterJsonPreferNsis` trap in §CI/CD): stop choosing for them, and publish both keys.

The mechanism depends on the running binary knowing its own bundle type, which comes from the
CLI patching bundle-type information into the main executable during bundling.
**`tauri build --no-binary-patching` disables that patching** — you want it when the patch would
invalidate an existing code signature, and the cost is stated plainly: *"Skipping it preserves
an already-signed binary at the cost of per-bundle-type updater support (only relevant when
shipping multiple bundle types per platform)."* One bundle type per platform → no cost. Two →
you must choose between the signature-preserving path and correct per-type updates.

**Dynamic update server contract.** `204 No Content` means "no update". `200 OK` with
`{ "version": "", "pub_date": "", "url": "", "signature": "", "notes": "" }` means "update
available"; required fields are `url`, `version`, `signature`. Read §Update security before you
implement the 204 branch — it has a security consequence most implementers do not expect.

**Windows install mode.** `installMode` is `"passive"` (default), `"basicUi"`, or `"quiet"`,
which map to real installer arguments:

| Mode | NSIS | msiexec |
| --- | --- | --- |
| `passive` | `/P` | `/passive` |
| `quiet` | `/S` | `/quiet` |
| `basicUi` | *(none)* | `/qb+` |

On `quiet`, the docs: *"With this mode the installer cannot request admin privileges by itself so
it only works in user-wide installations or when your app itself already runs with admin
privileges. Generally not recommended."* If your NSIS `installMode` is `perMachine`, `quiet`
updates will fail silently for non-elevated users — the two settings interact and neither
warns.

Source-verified restart behaviour: the updater always appends `/UPDATE` for NSIS and
`/i <path> … /promptrestart` for MSI. `restart_after_install` defaults to **`true`**; when on,
NSIS additionally gets `/R` plus `/ARGS <escaped current exe args>` and MSI gets
`AUTOLAUNCHAPP=True` plus `LAUNCHAPPARGS="…"`. Disable with
`UpdaterBuilder::restart_after_install(false)` or `Update::restart_after_install(false)`. NSIS
argument escaping additionally escapes `/` "so that nsis won't interpret them as a beginning of
an nsis argument" — which means arguments containing paths survive, but do not hand-build these
strings yourself.

**Evidence.** <https://v2.tauri.app/plugin/updater/>, `plugins/updater/src/updater.rs`
(`check`, `get_urls`, `updater_parameters`, `installer_for_bundle_type`),
`plugins/updater/src/config.rs`, `crates/tauri-cli/src/build.rs` (`--no-binary-patching`).
Updater 2.10.1, CLI 2.11.4.

---

## Updater runtime API and per-OS install semantics

**Mechanism.**

```ts
import { check } from '@tauri-apps/plugin-updater';
import { relaunch } from '@tauri-apps/plugin-process';

const update = await check({
  timeout: 30000,                              // milliseconds
  headers: { Authorization: 'Bearer <token>' },
  proxy: '<proxy url>',
  target: 'macos-universal',                   // optional custom target key
});
if (update) {
  let downloaded = 0, contentLength = 0;
  await update.downloadAndInstall((event) => {
    switch (event.event) {
      case 'Started':  contentLength = event.data.contentLength; break;
      case 'Progress': downloaded += event.data.chunkLength;     break;
      case 'Finished': break;
    }
  });
  await relaunch();
}
```

```rust
use tauri_plugin_updater::UpdaterExt;

async fn update(app: tauri::AppHandle) -> tauri_plugin_updater::Result<()> {
  if let Some(update) = app.updater()?.check().await? {
    let mut downloaded = 0;
    update.download_and_install(
      |chunk_length, content_length| { downloaded += chunk_length; },
      || { println!("download finished"); },
    ).await?;
    app.restart();
  }
  Ok(())
}
```

`UpdaterBuilder` runtime overrides (all source-verified): `endpoints(Vec<Url>)` (re-validates
HTTPS), **`pubkey(S)` — this is what makes key rotation possible**, `target(S)`,
`version_comparator(|current, update| …)`, `header` / `headers` / `clear_headers`, `timeout`,
`proxy` / `no_proxy`, `executable_path`, `installer_arg` / `installer_args` /
`clear_installer_args`, `restart_after_install(bool)`, `on_before_exit(|| …)` (Windows only),
`configure_client(|ClientBuilder| …)`. Config values act as fallbacks when a builder value is
unset. `tauri_plugin_updater::target()` returns the default `"{os}-{arch}"` key, or `None` when
the updater is unsupported on the platform.

**Per-OS install semantics — these differ enough to change your UX.**

- **Windows.** `Update::install` *"exits the app after launching the updater installer
  successfully"* — Windows installers cannot replace a running executable. Docs: *"On Windows
  the application is automatically exited when the install step is executed due to a limitation
  of Windows installers."* You do not get to ask the user "restart later" on Windows; you only
  get to choose whether the app relaunches. Use `on_before_exit` to flush state. Payload
  detection is content-based via `infer`: a ZIP is unpacked and the first `.exe`/`.msi` inside is
  used; a raw `.exe` takes the NSIS path, a raw `.msi` the msiexec path.
- **macOS / Linux.** *"You need to relaunch the app to run the newly install version."* You
  restart explicitly (`app.restart()` / `relaunch()` from `tauri-plugin-process`), which means
  you *can* defer.
- **Linux, source-verified and broader than the docs page.** The install path branches on
  `bundle_type()`: `Deb` → `install_deb`, `Rpm` → `install_rpm` (both validated with
  `infer::archive::is_deb` / `is_rpm`, and both may escalate through `install_with_sudo`),
  anything else → `install_appimage`, which replaces the running AppImage in place.

**Trade-offs.** The official split of `fetch_update` / `install_update` — a `Channel<
DownloadEvent>` for progress plus a `PendingUpdate(Mutex<Option<Update>>)` in managed state — is
more code than calling `downloadAndInstall` from JS, and it buys you the ability to keep a
downloaded update alive across a frontend reload and to install on the user's schedule. Choose
the JS path only if "download and install now, in this page session" is acceptable. Channel
mechanics and state-management reasoning are `references/ipc-and-commands.md`. Also worth
knowing: *"restarting your app immediately after installing an update is not required"* — on
Windows you only lose the choice about the *exit*, not the *relaunch*.

**Failure modes, symptom-first.**

- **Update download 406s from a CDN or storage bucket.** `check()` sends
  `Accept: application/json` and `download()` sends `Accept: application/octet-stream`. An
  endpoint that content-negotiates on `Accept` will serve one and reject the other.
- **Memory spikes by the size of the installer during an update.** `Update::download` buffers
  the **entire payload in a `Vec<u8>`** and verifies the signature over the complete buffer
  before returning bytes. A 200 MB installer is a 200 MB allocation. This is why AppImage's
  70+ MB baseline (§Bundle targets) is a runtime memory decision too, not only a bandwidth one.
- **Update fails on Linux with a permissions error.** `install_appimage` needs the running
  AppImage's own path to be writable. Read-only mounts, `/opt` installs, and root-owned
  AppImages all fail.
- **A GUI password prompt appears mid-update on Linux.** `deb`/`rpm` installs may escalate via
  `install_with_sudo`. Do not design a silent-update UX for Linux package installs.
- **Your dynamic server wants to force a specific build and the client ignores it.** The default
  comparator is `release.version > current_version` (semver). Override `version_comparator`.

**Evidence.** <https://v2.tauri.app/plugin/updater/>, `plugins/updater/src/updater.rs`.
Updater 2.10.1.

---

## Update security: three distinct failure modes

Each of these is a separate mechanism with a separate mitigation. Fixing one does not touch
the others.

**What Tauri actually guarantees.** The public key is compiled in
(`plugins.updater.pubkey`, or supplied at runtime). Before installing, the plugin runs:

```rust
fn verify_signature(data: &[u8], release_signature: &str, pub_key: &str) -> Result<()> {
    let public_key = PublicKey::decode(&base64_to_string(pub_key)?)?;
    let signature  = Signature::decode(&base64_to_string(release_signature)?)?;
    public_key.verify(data, &signature, true)?;   // third arg: allow legacy/prehashed
    Ok(())
}
```

over the fully-downloaded payload. *"Tauri's updater needs a signature to verify that the update
is from a trusted source. **This cannot be disabled.**"* TLS is enforced for endpoints in
release builds — `validate_endpoints` returns `Error::InsecureTransportProtocol` under
`#[cfg(not(debug_assertions))]`; in debug it only prints a yellow warning, which is why "it
worked with an http endpoint in dev" is not evidence of anything.

**The guarantee is narrower than it looks: Tauri signs the artifact BYTES, not the manifest
document.** `version`, `notes`, `pub_date` and `url` are unauthenticated, attacker-controlled
data if the endpoint is compromised. Everything below follows from that one fact.

### Failure mode 1 — rollback attack (live, not theoretical)

**Mechanism.** An attacker who controls the endpoint advertises `"version": "99.0.0"` while
pointing `url` and `signature` at a **genuinely-signed older release of your app** with a known
CVE. Both checks pass: the signature *is* yours over bytes you really published, and the
comparator sees `99.0.0 > current`. The client downgrades itself into the vulnerable build and
believes it just updated.

**Why it works.** Signing artifacts proves *provenance*, not *freshness*. Nothing in the
protocol binds a version number to a set of bytes, because the signed object is the payload and
the version lives in the unsigned manifest.

**Mitigations** (pick at least one; they compose):

1. Serve the manifest from infrastructure with the **same trust level as the artifacts** — if
   the manifest host is easier to compromise than your signing key, it is the weakest link.
2. **Sign or attest the manifest yourself, out of band**, and verify that in a
   `version_comparator` or a wrapper command before accepting the release.
3. **Embed a monotonic version floor** in the app and reject any `update.version` below it via
   `version_comparator`. This is the cheapest effective control: a rollback to a version below
   the floor is refused even with a valid signature.

```rust
// Reject anything at or below the floor this build knows about.
const MIN_ACCEPTED: &str = "1.4.0";
let updater = app.updater_builder()
    .version_comparator(|current, update| {
        let floor = semver::Version::parse(MIN_ACCEPTED).unwrap();
        update.version > current && update.version >= floor
    })
    .build()?;
```

**Cost.** A floor means you can never legitimately ship a hotfix numbered below it, and each
release's floor must be maintained deliberately. That is the trade: you give up the ability to
downgrade your own users, which you almost never want anyway.

### Failure mode 2 — update suppression via the primary endpoint

**Mechanism.** `check()` iterates `endpoints` in order and, on **`204 No Content`, returns
`Ok(None)` immediately without trying any remaining endpoint.** It advances to the next URL only
on a non-2XX status or a JSON deserialization error.

**Consequence, stated precisely: multi-endpoint fallback protects against outage, not against
hostility.** A compromised — or merely misconfigured — primary endpoint that returns 204 forever
**silently freezes your entire install base**, and no error is surfaced to the app, because
"there is no update" is the protocol's success path. Your fallback endpoint is never consulted.
This refines the framing in `references/case-studies.md` §6: two endpoints on different
infrastructure are still the right minimum, and they buy availability, not integrity. A
two-endpoint app with a hostile primary is exactly as frozen as a one-endpoint app.

**Mitigations:**

1. **Monitor the check from outside the app.** Alert on the *absence* of update-check traffic
   and on 204 rates that do not match your release schedule. This is the only mitigation that
   detects the attack; the client cannot.
2. **Put the endpoint you control least under attack first.** If your primary is bespoke
   infrastructure and your fallback is GitHub Releases, consider which one an attacker reaches
   more easily — and remember that ordering decides who can silence you.
3. **Make the primary fail loudly rather than quietly.** A primary that returns a hard error
   when it has no answer (rather than 204) causes the client to fall through to the fallback.
   `[INFERENCE]` — derived from the documented iteration rule ("Tauri will only continue to the
   next url if a non-2XX status code is returned"); verify against your updater version before
   depending on it, and note that it is a deliberate protocol inversion: you are trading a clean
   "no update" signal for fall-through.
4. Add an **independent staleness check**: if the app has not successfully seen *any* manifest
   in N days, surface that to the user rather than assuming it is up to date. Silence and
   "up to date" must not look identical in your UI.

**Related semantics you will need while debugging:** a successfully parsed release clears
`last_error`; if every endpoint fails you get the *last* error; if all endpoints returned 2XX
but none parsed, you get the deserialization error. `Error::ReleaseNotFound` means every
endpoint was reachable and none yielded a release.

### Failure mode 3 — baked-in endpoints (the one-way door)

**Mechanism.** The endpoint list is part of the compiled-in configuration. There is no runtime
source of truth to correct. `references/case-studies.md` §6 shows a real app reading its feed
out of `app.config()` — that is reading the *compiled* value, so it changes nothing about the
exposure — alongside a real two-endpoint app and the convention it documents.

**Consequence.** If the endpoint moves, dies, or was wrong at release time, the only way to tell
an installed client about the new endpoint is to ship an update through the endpoint that no
longer works. Installed clients are stranded, permanently, with no recovery path that does not
involve the user manually downloading a new installer.

**Mitigations:**

1. **At least two endpoints on different infrastructure, from release #1.** One line of JSON.
2. **Own a stable hostname you will never give up**, and point it at whatever serves manifests.
   A DNS name is re-pointable; a `github.com/<org>/<repo>` URL is not, if you ever migrate org
   or rename the repo. This is the highest-leverage single decision in this section: it converts
   a compiled-in constant into an indirection you control.
3. **Treat the endpoint list as reviewed release-blocking config** — same scrutiny as the
   identifier and the upgrade code.

### Key rotation

Because `pubkey` can be overridden at runtime through `UpdaterBuilder::pubkey`, rotation is
possible but only *forward*: ship version *N* whose job is to also accept the new key (or to
fetch the new key over a channel authenticated by the old one), wait for adoption, then cut over
to signing with the new key. Clients that never received *N* can never be reached with the new
key. **Retrofitting rotation after a compromise is not possible** — so the rotation path has to
exist before you need it. Loss of the key means no more updates; compromise means the attacker
can sign payloads every installed client trusts. Those are different disasters with the same
blast radius.

### Anti-patterns that hand these attacks to anyone on the network

- `dangerousInsecureTransportProtocol: true` removes the HTTPS requirement. An on-path attacker
  can then do failure modes 1 and 2 at will without compromising any server.
- `dangerousAcceptInvalidCerts` / `dangerousAcceptInvalidHostnames` (source-only keys) disable
  TLS validation for update requests. Same exposure. They exist for corporate MITM proxies; they
  are not a debugging convenience, and a debug-time `true` that ships is a shipped
  vulnerability — and remember `pubkey` and endpoints are compiled in, so it ships silently.
- Password-less signing keys. See §Updater keys.

**When to deviate.** If your app updates through a platform store (Flatpak, Snap, Microsoft
Store, MAS) the store owns integrity and this entire section is not your threat model — disable
the updater in that build flavour rather than leaving a second, weaker update path enabled.

**Evidence.** `plugins/updater/src/updater.rs` (`check`, `verify_signature`, `download`),
`plugins/updater/src/config.rs` (`validate_endpoints`), <https://v2.tauri.app/plugin/updater/>,
`crates/tauri-cli/src/signer/generate.rs`, `references/case-studies.md` §6. Updater 2.10.1,
verified 2026-07-27.

---

## CI/CD with `tauri-apps/tauri-action`

**Mechanism.** Current major is **`tauri-apps/tauri-action@v1`** — older docs and most blog
posts still show `@v0`. The action builds, uploads release assets, and **generates
`latest.json` for you** when the updater is configured, which is why "GitHub Releases as your
update server" is the default recommendation for small teams.

```yaml
name: 'publish'
on:
  workflow_dispatch:
  push:
    branches: [release]

jobs:
  publish-tauri:
    permissions:
      contents: write
    strategy:
      fail-fast: false
      matrix:
        include:
          - platform: 'macos-latest'      # Apple Silicon
            args: '--target aarch64-apple-darwin'
          - platform: 'macos-latest'      # Intel
            args: '--target x86_64-apple-darwin'
          - platform: 'ubuntu-22.04'
            args: ''
          - platform: 'ubuntu-22.04-arm'  # public repos only
            args: ''
          - platform: 'windows-latest'
            args: ''
    runs-on: ${{ matrix.platform }}
    steps:
      - uses: actions/checkout@v7
      - name: install dependencies (ubuntu only)
        if: matrix.platform == 'ubuntu-22.04' || matrix.platform == 'ubuntu-22.04-arm'
        run: |
          sudo apt-get update
          sudo apt-get install -y libwebkit2gtk-4.1-dev libappindicator3-dev librsvg2-dev patchelf xdg-utils
      - uses: actions/setup-node@v6
        with:
          node-version: lts/*
          cache: 'npm'
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: ${{ matrix.platform == 'macos-latest' && 'aarch64-apple-darwin,x86_64-apple-darwin' || '' }}
      - name: Rust cache
        uses: swatinem/rust-cache@v2
        with:
          workspaces: './src-tauri -> target'
      - run: npm install
      - uses: tauri-apps/tauri-action@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAURI_SIGNING_PRIVATE_KEY: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}
          TAURI_SIGNING_PRIVATE_KEY_PASSWORD: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY_PASSWORD }}
          APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
          APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
          APPLE_API_ISSUER: ${{ secrets.APPLE_API_ISSUER }}
          APPLE_API_KEY: ${{ secrets.APPLE_API_KEY }}
          APPLE_API_KEY_PATH: ${{ secrets.APPLE_API_KEY_PATH }}
        with:
          tagName: app-v__VERSION__
          releaseName: 'App v__VERSION__'
          releaseBody: 'See the assets to download this version and install.'
          releaseDraft: true
          prerelease: false
          updaterJsonPreferNsis: true
          args: ${{ matrix.args }}
```

Inputs: `releaseId`, `tagName`, `releaseName`, `releaseBody`, `releaseCommitish`,
`releaseDraft` (default `false`), `prerelease` (default `false`), `generateReleaseNotes`
(default `false`), `owner`, `repo`, `githubBaseUrl`, `projectPath` (default `./`),
`retryAttempts` (default `0`), `uploadUpdaterJson` (default **`true`**),
`updaterJsonPreferNsis` (default **`false`** "for legacy reasons"), `tauriScript`, `args`,
`releaseAssetNamePattern`, `uploadPlainBinary` (default `false`), `uploadWorkflowArtifacts`
(default `false`), `workflowArtifactNamePattern` (default `[platform]-[arch]-[bundle]`),
`uploadUpdaterSignatures` (default **`true`**), `mobile`. Naming-pattern variables: `[name]`,
`[mainBinaryName]`, `[version]`, `[platform]`, `[arch]`, `[ext]`, `[mode]`, `[setup]`,
`[_setup]`, `[bundle]`. Outputs: `releaseId`, `releaseHtmlUrl`, `releaseUploadUrl`,
`artifactPaths`, `appVersion`.

Windows certificate import must be a **separate prior step** on `windows-latest` (§Windows
signing); everything else goes in the `env:` of the `tauri-action` step.

**Why the matrix shape is what it is.** macOS is two entries rather than
`universal-apple-darwin` because separate per-arch artifacts halve each user's download and
because a universal binary doubles your `.app.tar.gz` size for the updater — which matters given
the updater buffers the whole payload in memory (§Updater runtime). Use `universal-apple-darwin`
when you would rather publish one macOS asset than two, or when the Mac App Store requires it.

**Trade-offs.** `swatinem/rust-cache@v2` with `workspaces: './src-tauri -> target'` is the
single biggest CI win available and it is layout-specific — a non-default workspace layout needs
that path changed or the cache silently never hits. `uploadWorkflowArtifacts` exists only
because `actions/upload-artifact` cannot upload from multiple jobs into one artifact
(actions/upload-artifact#331) and "will likely be removed once that lands", so do not build
tooling on it.

**Failure modes, symptom-first.**

- **`Resource not accessible by integration`.** `GITHUB_TOKEN` is read-only by default. Add
  `permissions: contents: write` to the job (preferred over widening repo-level settings).
- **`latest.json` URLs point at `releases/latest/download/<bundle>` and users get 404s or the
  wrong binary.** You passed **`releaseId` without `tagName`**. Without a tag, the action cannot
  build versioned asset URLs and falls back to `latest`, which "can cause issues if your repo
  contains releases that do not include updater bundles" — i.e. any repo where a release was
  ever cut without updater artifacts. **Always pass `tagName`.**
- **The action cannot find the release you created.** If `tagName` targets an existing **draft**
  release, `releaseDraft` **must** be `true`.
- **MSI users are fine, NSIS users get handed an `.msi` (or vice versa).**
  **`updaterJsonPreferNsis` defaults to `false`**, so when both `.msi` and `-setup.exe` updater
  artifacts exist, **the MSI wins in `latest.json`**. If NSIS is your primary installer, set
  `updaterJsonPreferNsis: true`. The better fix is to publish per-bundle-type manifest keys and
  stop choosing at all (§Updater manifest).
- **Relative `--config` paths resolve unexpectedly.** They resolve relative to `projectPath`,
  which also "must NOT be gitignored".
- **ARM AppImage job takes an hour.** `pguyot/arm-runner-action` under QEMU is "**much** slower
  than GitHub's standard runners — an uncached build for a fresh `create-tauri-app` project needs
  ~1 hour". Native `ubuntu-22.04-arm` / `ubuntu-24.04-arm` runners (GA Aug 2025, **public repos
  only**) take ~10 minutes.
- **`uploadPlainBinary` seems like a nice portable option.** It is explicitly discouraged:
  "Tauri does NOT officially support a portable mode", and it breaks `bundle_type()` — hence
  per-bundle-type updater targets — unless combined with `--no-bundle`.
- **`[bundle]` in `releaseAssetNamePattern` produces odd names.** It is "likely only useful for
  `workflowArtifactNamePattern` and *not* for `releaseAssetNamePattern` because of its conflict
  with `[ext]`".

**When to deviate.** Drive `tauri build` directly instead of the action when you need to
interleave steps the action does not model — a separate notarization job, a signing service with
its own approval gate, or artifact promotion between environments. You then own `latest.json`
generation, which is more work but also removes the `updaterJsonPreferNsis` and `releaseId`
traps entirely.

**Evidence.** <https://v2.tauri.app/distribute/pipelines/github/>,
`tauri-apps/tauri-action` README (dev branch), `/distribute/sign/windows/`,
`/distribute/sign/macos/`. Action `@v1`, verified 2026-07-27.

---

## Distribution channels: what each one actually demands

Every channel below imposes constraints that reach back into your build config. Read them
before you commit to a channel, because some of them conflict with each other and a few
conflict with the updater.

### Microsoft Store

Enroll as a Windows developer, then Partner Center → Apps and Games → New Product → **"EXE or
MSI app"**. Tauri produces no MSIX, so the Store **links to** your installer rather than hosting
a packaged app — which means the Store does **not** update your app and you keep owning the
updater.

Hard requirements: (1) **offline WebView2 installer**,
`"webviewInstallMode": { "type": "offlineInstaller" }`; (2) code signed; (3) **silent install** —
the rejection text is literally `10.2.9.2 Security - Package Submissions | Win32 products must
install silently.`, and the flags are NSIS `/S` (**uppercase**) or MSI `/quiet`, entered in the
Partner Center installer parameters; (4) **`publisher` must not equal `productName`** — the
default publisher is the second segment of the identifier, so `productName: "Example"` +
`identifier: "com.example.app"` collides and you must set `bundle.publisher: "Example Inc."`.

The offline installer adds ~127 MB, so this belongs in a separate flavour — build once, bundle
twice:

```sh
tauri build --no-bundle
tauri bundle                                                          # direct download
tauri bundle --config src-tauri/tauri.microsoftstore.conf.json        # Store
```

`tauri icon` already emits the Store icon sizes.

### Mac App Store (and iOS App Store)

Register the app with a **Bundle ID exactly matching `tauri.conf.json > identifier`** — which is
why the identifier is a one-way door. Requirements: `bundle.category` set; a **"Mac App Store
Connect"** provisioning profile bundled through
`macOS.files: { "embedded.provisionprofile": "path/to/profile.provisionprofile" }`;
`src-tauri/Info.plist` with `ITSAppUsesNonExemptEncryption`; an `Entitlements.plist` with
`com.apple.security.app-sandbox`, `com.apple.application-identifier` = `$TEAM_ID.$IDENTIFIER`,
`com.apple.developer.team-identifier` = `$TEAM_ID`, referenced from `bundle.macOS.entitlements`.

```sh
tauri build --bundles app --target universal-apple-darwin
xcrun productbuild --sign "<installer signing identity>" \
  --component "target/universal-apple-darwin/release/bundle/macos/$APPNAME.app" /Applications "$APPNAME.pkg"
xcrun altool --upload-app --type macos --file "$APPNAME.pkg" --apiKey $APPLE_API_KEY_ID --apiIssuer $APPLE_API_ISSUER
```

Real blockers: the `.pkg` must be signed with a **Mac Installer Distribution** certificate,
which is a *different* certificate from the app signing one — this is the step that surprises
people. Apple-Silicon-only support requires `minimumSystemVersion: "12.0"` and dropping
`--target universal-apple-darwin`. And the app must genuinely work inside **App Sandbox**;
filesystem and network plugin usage commonly breaks there. Before planning for MAS, check
whether your window configuration has already disqualified you — the transparency/private-API
trade-off and its App Store consequence is documented in `references/case-studies.md` §4, with a
real app that took that path. The AuthKey file must be named `AuthKey_<APPLE_API_KEY_ID>.p8` and
sit in one of the four searched directories (§macOS signing).

### winget

PR a YAML manifest to `microsoft/winget-pkgs`. Testing requirements, from CONTRIBUTING: the
application must **install unattended**, the installed **version must match `PackageVersion`**,
the **publisher must match the `defaultLocale` Publisher**, and the **name must match the
`defaultLocale` PackageName** — or you must include `AppsAndFeaturesEntries`. Test locally with
`winget settings --enable LocalManifestFiles` then `winget install --manifest <path>`; the
**preferred** method is `SandboxTest.ps1` in Windows Sandbox "because it ensures the package
doesn't require any dependencies to install". One package version per PR, no non-manifest
changes.

Tauri-specific blockers: unattended install means NSIS `/S` or MSI `/quiet`. The Add/Remove
Programs `DisplayName` / `Publisher` / `DisplayVersion` that Tauri writes come from
`productName` / `publisher` (or identifier segment 2) / `version` — if those do not match the
manifest fields you must add `AppsAndFeaturesEntries`. And `perMachine` vs `currentUser` changes
the ARP hive (`HKLM` vs `HKCU`), which changes what winget can detect for upgrade and uninstall.
That makes NSIS `installMode` a winget-visible decision, not just an install-location one.

### Homebrew Cask

A cask in `Homebrew/homebrew-cask` distributing your `.dmg`/`.pkg`/`.app` from a stable URL with
a sha256. The shared **Package Acceptance Policy** applies on top of the cask rules, and the
gates are concrete:

- **Notability:** normally **≥30 forks, or ≥30 watchers, or ≥75 stars** on the canonical upstream
  repo. For a **self-submission by the repository owner: ≥90 forks, or ≥90 watchers, or ≥225
  stars**. A repository **less than 30 days old is normally not eligible**.
- **"On macOS, it must not require System Integrity Protection or Gatekeeper to be disabled or
  bypassed."** This is the decisive one for Tauri: an **unsigned or unnotarized DMG requires a
  Gatekeeper bypass, so it cannot be listed**. Notarize before you propose a cask — the
  Homebrew gate is downstream of §macOS signing, and no amount of stars fixes it.
- "An installer package that requires certificate verification to be disabled is not eligible."
- The download must be published by the developer or a publicly endorsed distribution source; no
  downloads behind account registration on an unrelated host.
- Must work on the **latest major macOS version** and on every OS/arch it declares, be actively
  maintained, and have no known unpatched vulnerabilities.

**Escape hatch:** a third-party tap (`brew tap you/yourtap`) has none of these gates but "does
not imply Homebrew endorsement or support". Most Tauri projects should start there and graduate.

### Scoop

A JSON manifest in a bucket; GUI apps go to `ScoopInstaller/Extras`
(`scoop bucket add extras`), which exists "For manifests that don't fit the Main criteria".
Required properties: `version`, `description`, `homepage`, `license` (an SPDX id, or
`Freeware`/`Proprietary`/`Public Domain`/`Shareware`/`Unknown`). Practically also `url`, `hash`
(SHA256 by default; prefix `sha512:`/`sha1:`/`md5:` to change),
`architecture.{64bit,arm64}`, `bin` and/or `shortcuts` (`[target, name, params?, icon?]`),
`checkver` + `autoupdate` (maintainers expect these so the Excavator workflow can bump versions
automatically), and `persist` for user data.

Scoop prefers *not* running installers, which gives you two options: (a) drive the
`-setup.exe` through `installer`/`uninstaller` with `file`/`args`/`keep` (`args` gets `/S`); or
(b) the URL-fragment trick that makes Scoop treat the installer as an archive —
`"url": "https://…/MyApp_x64-setup.exe#/dl.7z"` — documented as "commonly used in Scoop
manifests to bypass executable installers which might have undesirable side-effects like
registry changes, files placed outside the install directory, or an admin elevation prompt."

**The blocker:** option (b) yields a portable-ish install with **no registry entries**, which
means the Tauri **updater's NSIS/MSI install path cannot work** — there is nothing to upgrade in
place and no ARP entry. Ship Scoop as a **non-self-updating channel** and let Scoop own
versions, or use option (a) and accept the elevation/registry side effects.

### Flathub (Flatpak)

**Tauri's own Flatpak page is marked `draft: true` and `/distribute/flatpak/` returns 404 on the
live site** — the content exists only in the docs repo source. Treat that guidance as unstable
and re-verify against Flathub's own documentation.

The approach is to build the Flatpak **from your `.deb`**: `org.gnome.Platform` / `org.gnome.Sdk`
runtime 46 ("includes all dependencies of the standard Tauri app with their correct versions"),
`finish-args` for `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`, `--share=ipc`
(plus `--talk-name=org.kde.StatusNotifierWatcher` and `--filesystem=xdg-run/tray-icon:create`
only if you use a tray), then a `simple` build module that `ar -x`'s the `.deb` and installs the
binary, desktop file, icons and an AppStream MetaInfo file. Prereqs: `flatpak` +
`flatpak-builder`, `flatpak install flathub org.gnome.Platform//46 org.gnome.Sdk//46`, a MetaInfo
file (generator: freedesktop.org metainfocreator), and the `.deb`. Submission: fork
`flathub/flathub`, `git clone --branch=new-pr`, PR **against `new-pr`**.

Two real constraints. Rather than widening the sandbox with `xdg-run/tray-icon`, redirect the
tray image into a path you already own — `TrayIconBuilder::…temp_dir_path(app.path().app_cache_dir()?)`
(tray semantics themselves are `references/desktop-ux.md`). And bundling a host `.so` "is not
recommended for the final build … your local library file is not built for the flatpak runtime
environment. This can introduce various bugs that can be very hard to find" — build extra
libraries from source as a module.

`[INFERENCE]` The Tauri updater cannot work inside a Flatpak: `/app` is read-only and Flatpak
owns updates. Disable the updater in the Flatpak flavour with a separate `--config`.

### Snapcraft

Register the name on snapcraft.io, then a `snapcraft.yaml` at the repo root building on
`core22`, with `extensions: [gnome]`, `stage-packages: [libwebkit2gtk-4.1-0,
libayatana-appindicator3-1]`, and an `override-build` that runs
`npm run tauri build -- --bundles deb` and `dpkg -x`'s the result into `$SNAPCRAFT_PART_INSTALL/`.

Three things are load-bearing. The **`layout:` bind for
`/usr/lib/$SNAPCRAFT_ARCH_TRIPLET/webkit2gtk-4.1` is mandatory** — without it WebKit cannot find
its libexec at runtime and the app fails to render. `extensions: [gnome]` already grants
`desktop, desktop-legacy, gsettings, opengl, wayland, x11, mount-observe, calendar-service`, so
do **not** re-declare those plugs. And the `Icon=` line in Tauri's generated `.desktop` file uses
a bare icon name that snap confinement cannot resolve, so it must be rewritten with `sed` to an
absolute `/usr/share/icons/...` path. The `single-instance` plugin additionally needs explicit
DBus `slots`/`plugs` named after your identifier with `_` substituted for `.` and `-`.

`[INFERENCE]` As with Flatpak, `$SNAP` is read-only and the Store handles revisions — the Tauri
updater does not apply.

### AUR, and the hosted alternative

AUR has a dedicated page (`/distribute/aur/`) for PKGBUILD publishing; the packaging model is
"build from source or repack the release", and the maintainer relationship is the actual work.

**CrabNebula Cloud** is an official Tauri partner offering a hosted **dynamic update server**
plus global distribution (`/distribute/crabnebula-cloud/`,
`/distribute/pipelines/crabnebula-cloud/`). It is the documented alternative to hand-rolling a
manifest endpoint, and — read against §Update security — it is a way to buy the operational
maturity that failure modes 2 and 3 demand, at the cost of a dependency on a third party in your
integrity chain. That is a legitimate trade for a small team; make it consciously.

**Evidence.** <https://v2.tauri.app/distribute/microsoft-store/>, `/distribute/app-store/`,
`microsoft/winget-pkgs` CONTRIBUTING.md, <https://docs.brew.sh/Acceptable-Casks>,
<https://docs.brew.sh/Package-Acceptance-Policy>,
`ScoopInstaller/Scoop` wiki App-Manifests + `ScoopInstaller/Extras` README,
`tauri-apps/tauri-docs` `v2/src/content/docs/distribute/flatpak.mdx` (draft, 404 live),
<https://v2.tauri.app/distribute/snapcraft/>, <https://v2.tauri.app/distribute/>.
Verified 2026-07-27.

---

## Versioning

**Mechanism.** `tauri.conf.json > version` is the recommended source of truth. If unset, Tauri
falls back to `package.version` in `src-tauri/Cargo.toml`. It may also be a **path to a
`package.json`**, whose `version` field is then read — which is how you keep a JS monorepo and
the desktop app on one number without a sync script.

Platform mapping: macOS/iOS → `CFBundleShortVersionString`, and the default `CFBundleVersion`
(override with `bundle.macOS.bundleVersion` / `bundle.iOS.bundleVersion`); Android defaults to
`1.0` unless `bundle.android.versionCode` is set (`autoIncrementVersionCode` default `false`,
`minSdkVersion` default `24`); `tauri ios build --build-number <number>` appends a build number.
MSI needs `major.minor.patch[.build]` with major/minor ≤ 255 and third/fourth ≤ 65535, derived
from `version` unless `bundle.windows.wix.version` overrides it.

**Trade-offs and the constraint that bites.** The updater requires valid **SemVer**. MSI cannot
express SemVer pre-release or build metadata. So `1.0.0-beta.3` is a perfectly good updater
version and an impossible MSI version, and you must set `bundle.windows.wix.version` explicitly
for any pre-release you ship as an MSI. If you plan a public beta channel, decide now whether it
ships MSI — because the alternative is a parallel version scheme, and parallel version schemes
drift.

**One-way door: `bundle.rpm.epoch`** (default `0`). The RPM guide recommends against using it
unless necessary because it "alters how the package manager compares package versions". Epoch
dominates version comparison entirely, so once you bump it you can never go back — every future
version must carry the same or higher epoch or package managers will consider your new release
older than the installed one.

**Failure mode, symptom-first.** *An MSI build fails validating the version and the number looks
fine.* One of the segments exceeds the WiX limits (major/minor > 255, or third/fourth > 65535),
or the version carries a semver suffix. Set `wix.version` to a compliant numeric quadruple and
leave `version` as the semver truth.

**Evidence.** <https://v2.tauri.app/distribute/>, `config.schema.json` (`version`,
`WixConfig.version`, `MacConfig.bundleVersion`, `RpmConfig.epoch`, `AndroidConfig`),
`/distribute/rpm/`, `/distribute/app-store/`. Schema 2.11.5.

---

## Release one-way-door checklist

Run this **before the first release**, and re-run the marked lines before any release that
changes naming, signing, or update infrastructure. Treat release #1 as a design review, not a
build step (SKILL.md Rule 7). Sequenced procedure lives in
`playbooks/release-preparation.md`; this is the list of decisions that cannot be undone.

**Permanent the moment the first user installs:**

1. **`identifier`** — reverse-DNS, only `A-Za-z0-9`, `-`, `.`, not ending in `.app`, never
   `com.tauri.dev`. Determines install location, macOS bundle ID and App Store registration,
   and the Windows webview data origin. Changing it later produces a second, unrelated app.
2. **`bundle.windows.wix.upgradeCode`** — run `tauri inspect wix-upgrade-code` and **pin the
   value in config**, before you ever touch `productName`. §Windows packaging.
3. **`productName`** — derives the upgrade code, the install directory, and the ARP
   `DisplayName` that winget matches against. Effectively immutable on Windows.
4. **The minisign keypair** — generated **with a password**, private key in a real secrets
   manager, password stored separately, plus an offline backup. Loss ends your ability to update
   the installed base. §Updater keys.
5. **`plugins.updater.endpoints`** — at least two, on different infrastructure, ideally behind a
   **hostname you own and will never give up**, from release #1. Compiled in; wrong means
   stranded clients. §Update security failure mode 3.
6. **Signing identity** — Windows: the certificate subject/publisher name you will keep, because
   SmartScreen reputation is per-certificate. macOS: the Team ID + identifier pair. §Windows
   signing, §macOS signing.
7. **NSIS `installMode`** — `currentUser` vs `perMachine`. Different install root and registry
   hive; switching orphans existing installs. `[INFERENCE]`
8. **`bundle.rpm.epoch`** — leave it at `0` unless you have a specific reason. §Versioning.
9. **Version scheme** — decide whether pre-releases ship MSI before you cut the first beta.

**Verify before you publish, every release:**

- `bundle.active: true` **and** `bundle.createUpdaterArtifacts: true` — assert the presence of
  installers *and* `.sig` files as a CI step, not by reading the exit code.
- `TAURI_SIGNING_PRIVATE_KEY` present in the real process environment (not a `.env`).
- Manifest is regenerated for this release: signatures are file *contents*, they change every
  build, and **every** platform entry must be valid or updates break for all platforms.
- Per-bundle-type manifest keys published if you ship more than one bundle type per platform,
  or `updaterJsonPreferNsis` set to match your primary Windows installer. §CI/CD.
- `tagName` passed to `tauri-action` (never `releaseId` alone). §CI/CD.
- macOS: signed **and notarized**; `--skip-stapling` only for the very first notarization.
- Windows: signature present **with** an RFC 3161 timestamp (`case-studies.md` §7).
- An install-over-previous-version test on a clean VM per platform, checking that you end up
  with **one** app, not two, and that user data survived.
- An actual end-to-end update test from the previous released version to this one, against the
  real endpoints — the updater is the subsystem whose failure it cannot fix.

---

## v1 → v2 delta for distribution

Agents will find v1-era blog posts. These will silently or loudly fail on v2.

| Area | v1 | v2 |
| --- | --- | --- |
| Frontend config | `build.distDir`, `build.devPath` | `build.frontendDist`, `build.devUrl` |
| Bundle config root | `tauri.bundle.*` | top-level `bundle.*` |
| Product name / version | `package.productName`, `package.version` | top-level `productName`, `version` |
| Global Tauri | `build.withGlobalTauri` | `app.withGlobalTauri` |
| Updater | built-in `tauri.updater` with `active` + `dialog` | plugin `tauri-plugin-updater` + `plugins.updater` + `bundle.createUpdaterArtifacts`; **no built-in dialog — you build the UI** |
| Updater ACL | n/a (allowlist) | capability permission `updater:default` |
| Signing env | `TAURI_PRIVATE_KEY`, `TAURI_PRIVATE_KEY_PATH`, `TAURI_PRIVATE_KEY_PASSWORD` | `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PATH`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` (old names warn; removed in v3) |
| Windows updater artifacts | `.nsis.zip` / `.msi.zip` | raw `-setup.exe` / `.msi` (or `"v1Compatible"` for the zips) |
| Linux webview package | `webkit2gtk-4.0` | **`webkit2gtk-4.1`** |
| GitHub Action | `tauri-apps/tauri-action@v0` | `tauri-apps/tauri-action@v1` |
| Updater target keys | `{os}-{arch}` only | `{os}-{arch}-{installer}` tried **first**, then `{os}-{arch}`; new `{{bundle_type}}` URL variable |

Because v2 configs use `additionalProperties: false`, a v1 key is a schema validation error —
which is the good case. The dangerous case is a v1 *pattern* that still validates: copying a
v1 updater setup gets you a config that builds cleanly, produces no `.sig` files, and never
updates anyone.

**Evidence.** `config.schema.json`, <https://v2.tauri.app/plugin/updater/>,
`/distribute/pipelines/github/`, `plugins/updater/src/updater.rs`,
`crates/tauri-cli/src/signer/sign.rs`. Verified 2026-07-27 against tauri 2.11.5 /
updater 2.10.1 / CLI 2.11.4.

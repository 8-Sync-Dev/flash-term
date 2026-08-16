# Cross-Platform — three engines, not one browser

Baseline for every claim below: **`tauri 2.11.5`**, verified 2026-07-27. Where a claim comes
from a community thread rather than official docs it is marked `[community-sourced]`.

---

## 1. What you are actually shipping

**Mechanism.** Tauri bundles no browser engine. `wry` binds to whatever the OS already has:

| Target | Engine | Rust binding (in `tauri 2.11.5`) | Who updates it |
| --- | --- | --- | --- |
| Windows | **WebView2** (Edge / Chromium) | `webview2-com ^0.38` | Microsoft, evergreen, via a separate runtime |
| macOS / iOS | **WKWebView** (Apple WebKit) | `objc2-web-kit ^0.3` | Apple, only as part of an OS update |
| Linux | **WebKitGTK** (`webkit2gtk-4.1`) | `webkit2gtk ^2` | The distro, frozen per distro release |
| Android | System Android WebView (Chromium) | JNI | Play Store component, provider-switchable |

Evidence: <https://v2.tauri.app/reference/webview-versions/> ·
<https://github.com/tauri-apps/wry#platform-considerations> · crate dependency list on
<https://docs.rs/tauri/2.11.5/tauri/>.

**Why it is designed that way.** The whole size and memory argument for Tauri rests on this.
No 150 MB Chromium per app, no second copy of an engine the OS already has resident and
already patches. The cost is transferred to you, in full, as a three-engine compatibility
matrix — and unlike Electron you cannot pin the engine. The single exception is Windows
`fixedRuntime` (§2), and it is an exception you pay for.

**Trade-off.** You have traded ~120 MB of installer and a chunk of RSS for the obligation to
answer *every* rendering, CSS, and JS-feature question three times. Two of the three desktop
engines are WebKit, not Chromium, so "it works in Chrome" tells you about one third of your
users. Budget real time per release for this; teams that do not, discover it from users.

**When to deviate.** If you are shipping to a controlled fleet — one OS, one image, one
distro version — the matrix collapses to one engine and most of this file stops applying.
Say so explicitly in the project's README so nobody later "fixes" a Linux issue you do not
have.

---

## 2. Deriving a realistic feature baseline

**Mechanism.** Your floor is the **oldest WebKitGTK you support**, and that is set by your
oldest supported distro, not by upstream WebKit. Official mapping (abridged):

| Distro | `webkitgtk` | WebKit | Safari equivalent |
| --- | --- | --- | --- |
| Ubuntu 22.04, Debian 11 + updates, Ubuntu 20.04 + updates | 2.36 | 614.1.6 | ≈16.0 (TP 140) |
| Debian 10 + updates | 2.34 | 613.1.1 | 15.4 |
| Debian 11, Ubuntu 18.04 + updates, CentOS 8 | 2.32 | 612.1.6 | 15.0 |
| Ubuntu 20.04 (stock) | 2.28 | 610.1.1 | 14.0 |
| Ubuntu 18.04 | 2.20 | 606.1.4 | 12.0 |

Source: <https://v2.tauri.app/reference/webview-versions/>. Counter-datapoint from the field:
Ubuntu 24.04 ships `webkit2gtk-4.1: 2.50.1` (tauri-apps/tauri#14590), i.e. modern LTS is close
to current Safari. Both facts matter — the table is your floor if you publish a `.deb` for
older LTS, and irrelevant if you only support current LTS.

**The procedure.** Pick the oldest distro you will accept a bug report from → look up its
WebKitGTK → convert to the Safari equivalent → **use that Safari version as your caniuse
target** → then verify on macOS separately, because macOS has its own floor.

macOS is the half of this that people forget. WKWebView is *not* evergreen; a user on macOS
12.7 is frozen at WebKit 613.x forever. `bundle.macOS.minimumSystemVersion` is therefore your
real JS/CSS feature gate on macOS, and raising it is the only lever you have. Read the exact
WebKit version on a given Mac:

```bash
awk '/CFBundleVersion/{getline;gsub(/<[^>]*>/,"");print}' \
  /System/Library/Frameworks/WebKit.framework/Resources/Info.plist
```

Windows is effectively "recent Chromium" and is never the constraint — unless you chose
`fixedRuntime`, in which case you pinned your own floor and it is whatever build you froze.

**Failure modes, symptom-first.**

- *"Works on my Mac, a user on Big Sur reports a broken layout / a missing API."* Not a Tauri
  bug. WKWebView is pinned to their OS. Either polyfill, feature-detect, or raise
  `minimumSystemVersion` and accept dropping those users. There is no third option.
- *"CI is green, the Ubuntu 20.04 user has a blank section."* Your CI runner has a newer
  WebKitGTK than the target. CI runner version is not your baseline; your oldest supported
  distro is.

**Trade-off of raising the floor.** Every bump of `minimumSystemVersion` or "we only support
Ubuntu 22.04+" buys you modern CSS/JS and costs you users who cannot upgrade — frequently
exactly the enterprise and institutional users who pay. Make the call explicitly and record
it in the repo; do not let it drift in via a CSS feature nobody checked.

**When to deviate.** For a feature that is genuinely load-bearing (say, a WASM-heavy editor),
it is legitimate to raise the floor and ship a clear "unsupported OS" screen rather than a
subtly broken app. A broken app generates support load; a refusal does not.

---

## 3. Windows — WebView2 runtime distribution

**Mechanism.** `bundle.windows.webviewInstallMode.type`, five values:

| `type` | Needs internet at install? | Installer size delta | Notes |
| --- | --- | --- | --- |
| `downloadBootstrapper` | yes | 0 MB | **Default.** Not recommended for Win 7 via `.msi` |
| `embedBootstrapper` | yes | ~1.8 MB | Better Win 7 `.msi` behaviour |
| `offlineInstaller` | no | ~127 MB | Full WebView2 installer embedded |
| `fixedRuntime` | no | ~180 MB | Pins an exact Chromium build; also needs `path` |
| `skip` | no | 0 MB | App **will not work** without the runtime and will not install it |

```jsonc
// src-tauri/tauri.windows.conf.json
{
  "bundle": {
    "windows": {
      "webviewInstallMode": {
        "type": "fixedRuntime",
        "path": "./Microsoft.WebView2.FixedVersionRuntime.128.0.2739.42.x64/"
      },
      "minimumWebview2Version": "110.0.1531.0"
    }
  }
}
```

The `.cab` must be expanded into `src-tauri` first:

```powershell
Expand .\Microsoft.WebView2.FixedVersionRuntime.128.0.2739.42.x64.cab -F:* ./src-tauri
```

Source: <https://v2.tauri.app/distribute/windows-installer/#webview2-installation-options>

**Why the default is evergreen.** It is the security-correct choice: Microsoft ships Chromium
security fixes through Windows Update and you do nothing. `fixedRuntime` exists for two real
situations — air-gapped/offline enterprise deployment, and regulated environments that must
certify one exact engine build — and for nothing else.

**Trade-off.** Choosing `fixedRuntime` means **you now own WebView2 CVE response**. Every
Chromium security release becomes an app release for you, forever, plus 180 MB on the
installer. `offlineInstaller` is the middle ground: offline-capable install, still evergreen
afterwards, 127 MB. `skip` trades 0 MB for a support burden — it is only defensible when
something else in your deployment guarantees the runtime.

**Failure modes, symptom-first.**

- *"MSI install fails on Windows 7 with a TLS or download error."* `downloadBootstrapper`
  needs TLS 1.2, which may be disabled on Win 7. Use `embedBootstrapper`, or ship the NSIS
  `-setup.exe`, which handles `downloadBootstrapper` on Win 7.
- *"`failed to run light.exe`" during `.msi` bundling.* The Windows **VBSCRIPT optional
  feature** is disabled. Required for MSI, and Microsoft is deprecating VBSCRIPT, so expect
  this more often over time.
  Source: <https://v2.tauri.app/start/prerequisites/#vbscript-for-msi-installers>
- *"An API exists on my machine and is `undefined` for a user."* Their evergreen runtime is
  older than yours and nothing checked. `minimumWebview2Version` is the mechanism: the
  installer verifies the installed version and runs the bootstrapper when it does not match.
  Without it the mismatch surfaces at runtime as a missing API, which is unactionable for the
  user.

**v1 → v2.** `bundle.windows.webviewFixedRuntimePath` was **removed**; `webviewInstallMode`
replaced it. v1-era blog posts still reference the old key and it will simply be ignored.
Source: <https://v2.tauri.app/start/migrate/from-tauri-1/#tauri-configuration>

Bundling and installer choice more broadly belongs to `references/build-and-distribution.md`.

---

## 4. Windows — the v1→v2 origin flip that deletes user data

**Read this before any v1→v2 migration of a shipped app.** It is the only item in this file
that destroys data and cannot be undone after the fact.

**Mechanism.** In v1, production Windows builds served the frontend from
`https://tauri.localhost`. In v2 the default is **`http://tauri.localhost`**. Browser storage
is partitioned by origin, and scheme is part of the origin. Changing `https` → `http`
therefore points the webview at a **different, empty storage partition**: IndexedDB,
LocalStorage and Cookies all read as if the user had never run the app.

Official wording: *"On Windows the frontend files in production apps are now hosted on
`http://tauri.localhost` instead of `https://tauri.localhost`. Because of this IndexedDB,
LocalStorage and Cookies will be reset unless `dangerousUseHttpScheme` was used in v1."*
Source: <https://v2.tauri.app/start/migrate/from-tauri-1/#new-origin-url-on-windows>

**The fix**, for any app that already has a v1 userbase on Windows:

```jsonc
// src-tauri/tauri.windows.conf.json
{ "app": { "windows": [{ "label": "main", "useHttpsScheme": true }] } }
```

Rust equivalent: `WebviewWindowBuilder::use_https_scheme(true)`.

**Why the default changed at all.** `http://` on a localhost-style host is the scheme that
matches how the custom protocol is actually served and avoids the mixed-content and
certificate-shaped edge cases that `https://` on a non-TLS origin creates. The v1 behaviour
was itself the odd one out — which is precisely why the v1 opt-out was named
`dangerousUseHttpScheme`. The v2 default is the better long-term choice; the migration cost is
real and lands entirely on existing installs.

**Trade-offs.** Setting `useHttpsScheme: true` preserves data but permanently opts you into
the origin v2 moved away from, including whatever secure-context and mixed-content behaviour
comes with it. There is no supported migration path that moves storage between the two
origins — you either keep the old origin or you lose the data.

**Failure modes, symptom-first.**

- *"After we shipped v2, Windows users report all their settings/history/logins are gone.
  macOS and Linux users are fine."* This, exactly. Platform-asymmetry is the tell: only
  Windows changed origin.
- *"A user reinstalled v1 and their data came back."* Confirms it — the data was never
  deleted, it is sitting in the `https://tauri.localhost` partition, unreachable.

**When to deviate.** A **new** app with no v1 installs should leave the default (`http`)
alone. Only carry `useHttpsScheme: true` when you have real users to protect. If you must
move off it later, do the migration in-app: read from the old origin while you still can and
write into a Rust-side store, not into the webview's storage.

---

## 5. Windows — `additionalBrowserArgs` replaces wry's defaults

**Mechanism.** `additionalBrowserArgs` (config) / `WebviewWindowBuilder::additional_browser_args(&str)`
passes raw Chromium switches into the WebView2 environment. It is a **replacement**, not an
append. When it is unset, wry supplies its own string
(`wry src/webview2/mod.rs` L300–303, `wry 0.55.x`):

```
--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection
```

plus an autoplay flag. Setting `additionalBrowserArgs` to anything drops all of it.

**Why wry sets those defaults.** `msWebOOUI` / `msPdfOOUI` disable the Edge "mini menu" — the
Edge-branded selection popup that appears over your app's text and looks like a bug (wry#535).
`msSmartScreenProtection` disables SmartScreen inside the webview, which otherwise phones
Microsoft about URLs your app loads and can block them (tauri#1345).

**Trade-off.** The moment you need one custom switch — `--remote-debugging-port`,
`--disable-gpu`, a feature flag — you inherit responsibility for the defaults too. Re-include
the string:

```rust
WebviewWindowBuilder::new(app, "main", WebviewUrl::default())
    .additional_browser_args(
        "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection \
         --remote-debugging-port=9222",
    )
```

**Failure modes, symptom-first.**

- *"An Edge-styled popup toolbar appears when users select text, only on Windows, and only
  since <the commit that added a browser flag>."* The mini menu is back because the defaults
  were replaced.
- *"Windows users report the app blocking or warning on internal URLs."* SmartScreen is back,
  same cause.
- *"Two windows in the same app behave differently / storage is corrupted."* `config.rs` L2258:
  *"Windows: WebViews with different values for settings like `additionalBrowserArgs`,
  `browserExtensionsEnabled` or `scrollBarStyle` must have different data directories."*
  Sharing one `dataDirectory` across differing WebView2 configurations is undefined behaviour.
  Give each configuration its own directory.

**When to deviate.** If you deliberately *want* SmartScreen inside the webview — for example
a window that renders remote content — dropping the default is the point. Say so in a comment
next to the flag, because the next reader will assume it was an accident.

Two smaller Windows-only levers, same file: `window_classname(S)` sets a custom Win32 window
class name (useful when external automation or an installer needs to find your window), and
`noRedirectionBitmap` *"can help avoid a white flash when creating a transparent window"*
(`config.rs` L2044). `disable_drag_drop_handler()` is *"required to use HTML5 drag and drop
APIs on the frontend on Windows"* — the trade-off of turning off the native handler belongs to
`references/desktop-ux.md`.

ARM64 Windows needs `MSVC v143 - VS 2022 C++ ARM64 build tools (Latest)` from the VS Installer
plus `rustup target add aarch64-pc-windows-msvc`. Note that the NSIS installer stays x86 and
runs under emulation; only your app binary is native ARM64.

---

## 6. macOS — WKWebView, transparency, and the private-API gate

**Mechanism.** Three macOS specifics that change behaviour rather than appearance:

1. **Transparency requires a private API.** `tauri-utils/src/config.rs` L2041–2042: *"on
   `macOS` this requires the `macos-private-api` feature flag, enabled under
   `tauri > macOSPrivateApi`. WARNING: Using private APIs on `macOS` prevents your application
   from being accepted to the `App Store`."* The flag *"enables the transparent background API
   and sets the `fullScreenEnabled` preference to `true`."*
2. **Devtools also use private APIs on macOS** — see
   `references/debugging-and-testing.md` §devtools for the two distinct mechanisms and which
   one costs you App Store eligibility.
3. **The custom protocol scheme differs by platform**: `asset://` on macOS and Linux,
   `http://asset.localhost` on Windows and Android. `convertFileSrc()` output therefore
   differs per platform — never hardcode either form, and write CSP that admits both (the
   official example is `"img-src": "'self' asset: http://asset.localhost blob: data:"`).
4. **`dataDirectory` is unsupported on macOS/iOS** (`config.rs` L2259). Use
   `dataStoreIdentifier` (`[u8; 16]`) there instead. Copying a Windows multi-window config
   verbatim to macOS silently does nothing.

**Why transparency is gated.** AppKit exposes no public API for the layer-backed transparent
window Tauri needs, so wry reaches for a private one. Apple's rule is not about the visual
effect; it is about the API call. This makes `macOSPrivateApi: true` a **distribution
decision, not a styling decision** — it removes the Mac App Store from your options
permanently for that build.

**Trade-off — the part teams do not measure.** `transparent: true` is a continuous, always-on
GPU cost on macOS, even on a completely static page. tauri-apps/tauri#15471 measured with
`powermetrics --samplers gpu_power` (M5 Pro, macOS 26.6, tauri 2.11.2 / wry 0.55.1 / tao 0.35.3):

| | GPU power | GPU HW active residency |
| --- | --- | --- |
| `transparent: true` | ≈ **620 mW** | **36 %** |
| `transparent: false` | ≈ 75 mW | 10 % |

A blank Safari WKWebView measured identically to the transparent case, and occluding the
window dropped load to ~0 — so the cost is per-frame *window compositing*, not page work. On
an Intel MacBook Pro the WebKit GPU process sat at **1380 % CPU** while the app's own process
sat at ~8 %. A maintainer marked the issue `status: upstream`. `[community-sourced, measured
in-issue]`

The engineering consequence: if all you wanted was rounded corners or a vibrancy look, use
`effects` (`WindowEffectsConfig`) or `background_color`, not full transparency. You are
otherwise paying a permanent battery cost, plus App Store ineligibility, for a visual you
could have had for free.

**Failure modes, symptom-first.**

- *"Users report the fan spinning and battery draining while our app just sits there on
  macOS."* Check `transparent: true` before you profile anything in the frontend. Diagnostic
  note from the same report: `ioreg -r -d 1 -c IOAccelerator` "Device Utilization %" is
  **misleading** — it shows ~30 % for any foreground WKWebView app. Use `powermetrics`.
- *"Transparency works in `tauri dev` and the window is opaque after building a DMG."*
  tauri-apps/tauri#13415, open. `[community-sourced]`
- *"App Store submission rejected for private API usage."* `macOSPrivateApi: true`, or the
  `devtools` Cargo feature left on in the release build.

**When to deviate.** Ship transparency when the design genuinely requires it *and* you are
not targeting the Mac App Store — a Sparkle/updater-distributed app, notarized outside the
store, is unaffected. The measured battery cost is still real; state it in the PR.

Cross-platform titlebar and transparency *configuration* — including the per-platform matrix
two real shipping apps arrived at, and why Jan sets `transparent: false` on Linux while ZUS
does not — is in `references/case-studies.md` §4. Rendering-cost budgeting and how to measure
it is `references/performance.md`.

---

## 7. Linux — the NVIDIA / DMA-BUF escalation ladder

This is the highest-frequency platform defect in the stack and the one most often "fixed"
with the most destructive available option. Tauri has an official page for it now:
<https://v2.tauri.app/develop/debug/linux-graphics/>

**Symptoms, in the order the official page lists them.** Match against these before doing
anything else:

- window opens **blank / white**
- flicker, especially on resize
- **dies on resize** with no error output at all
- console: `AcceleratedSurfaceDMABuf was unable to construct a complete framebuffer`
- console: `Gdk-Message: Error 71 (Protocol error) dispatching to Wayland display.`

**Root cause (official).** The WebKitGTK DMA-BUF renderer requests buffer formats the NVIDIA
driver does not provide. Upstream: <https://bugs.webkit.org/show_bug.cgi?id=261874>.

**The ladder — try in this order. Earlier rungs keep more hardware acceleration.**

| # | Lever | Fixes | Cost |
| --- | --- | --- | --- |
| 1 | kernel parameter `nvidia_drm.modeset=1` | the whole class, on NVIDIA < 545 | none to your app; it is a user/system change and you cannot ship it |
| 2 | `__NV_DISABLE_EXPLICIT_SYNC=1` | Wayland `Error 71` crash | **no performance cost**; NVIDIA-scoped, no effect on other GPUs |
| 3 | `WEBKIT_DISABLE_DMABUF_RENDERER=1` | DMABUF framebuffer error and `Error 71` | drops the zero-copy rendering path for **every** user of that build |
| 4 | `WEBKIT_DISABLE_COMPOSITING_MODE=1` | last resort for the silent die-on-resize | disables accelerated compositing entirely — software compositor |

**Why the order matters, and the mistake nearly every project makes.** Rungs 3 and 4 are
process-wide environment variables. They do not apply "to affected users"; they apply to
everyone who runs your binary, including the majority whose GPU stack is fine. Skipping
straight to rung 4 — or setting 3 *and* 4 unconditionally, which is what several well-known
Tauri apps do — degrades rendering for your whole Linux userbase to fix a subset. A Tauri
maintainer pushed back on exactly that in tauri-apps/tauri#9394, pointing out that
`__NV_DISABLE_EXPLICIT_SYNC=1` has little or no performance cost and should be preferred.
`[community-sourced]`

Official guidance, in spirit: *only ship an unconditional override if you have verified your
app is affected; it disables a faster path for everyone, including users on working setups.*

**Mechanism constraint.** `WEBKIT_DISABLE_*` must be set **before the webview is created** —
top of `main()`, before `tauri::Builder`. Setting it inside `setup()` is too late and does
nothing, which is why the workaround always appears in `main.rs`. A real production `main.rs`
doing exactly this is in `references/case-studies.md` §8; do not re-derive it.

**The defensible shape** — respect a user who has already made a choice, so a working setup
can opt back out:

```rust
// src-tauri/src/main.rs — tauri 2.11.5
#[cfg(target_os = "linux")]
fn apply_webkit_workarounds() {
    // Rung 2 first: NVIDIA-scoped, no measured performance cost.
    if std::env::var_os("__NV_DISABLE_EXPLICIT_SYNC").is_none() {
        std::env::set_var("__NV_DISABLE_EXPLICIT_SYNC", "1");
    }
    // Rung 3 only if you have verified your app is affected. Never set rung 4 blindly.
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
}
```

Better still, make rung 3 a runtime opt-in the user can flip from a settings screen that
writes an env var into a relaunch, rather than a compile-time decision for everyone.

**Complications that change the answer.**

- **X11 vs Wayland asymmetry.** In tauri-apps/tauri#9394 the reporter maps symptoms to
  sessions: `AcceleratedSurfaceDMABuf … framebuffer` "seems to happen on X11"; `Error 71`
  "seems to happen on Wayland"; and for die-on-resize, "if it's happening in Wayland, your
  Webview is running on X11" (i.e. XWayland). Same thread: on newer WebKitGTK, **WebGL is
  broken on X11 but works on Wayland**, and forcing a Wayland session is the bypass.
  `GDK_BACKEND=x11` / `GDK_BACKEND=wayland` is the lever people use, and *both directions*
  appear as fixes depending on the exact combination — so always collect `XDG_SESSION_TYPE`
  in a Linux bug report. `[community-sourced]`
- **AppImage packaging changes the answer.** Same thread: an app that "runs on Wayland
  perfectly" against Arch's system libraries needed the workaround flags when built as an
  AppImage on the Ubuntu 22.04 GitHub Actions image — *"it's a problem with the AppImage
  packaging not using Wayland."* Bundling changes rendering behaviour independently of your
  code, so "works from `cargo run`" does not clear an AppImage. `[community-sourced]`
- **Transparency is a specific trigger.** tauri-apps/tauri#14924: `Error 71` /
  `Failed to create GBM buffer` at launch is *"strictly triggered by the `"transparent": true`
  window configuration"* on Fedora 43 / Arch with NVIDIA 40xx/50xx and proprietary drivers
  v590+. The workarounds then break transparency (black corners) or cause ghosting. Labelled
  `status: upstream`. This is the concrete reason a real app sets `transparent: false` on
  Linux only — see `references/case-studies.md` §4. `[community-sourced]`
- **The same vars also fix DPI scaling.** tauri-apps/tauri#14590 (Ubuntu 24.04,
  `webkit2gtk-4.1: 2.50.1`): UI renders at a lower scale, blurry/pixelated on zoom, in both
  dev and release; both `WEBKIT_DISABLE_*` vars fix it. Maintainer: *"If these env vars fix it
  this very very likely means that it's an upstream issue."* Related older report: #5600.
  `[community-sourced]`

**When to deviate.** If your Linux distribution channel is Flatpak or a distro package rather
than AppImage, and you can express a runtime dependency, prefer fixing the environment
(rung 1, driver version) over shipping rung 3. If your app has no GPU-heavy content at all,
rung 3's cost is small and shipping it unconditionally is a defensible trade — but say that in
the comment, so it reads as a decision and not as cargo cult.

---

## 8. Linux — WebKitGTK lies about the GPU

**Mechanism.** WebKitGTK masks the WebGL renderer string as an anti-fingerprinting measure:
`WEBGL_debug_renderer_info` reports **`Apple GPU` on every Linux machine**, regardless of what
is actually installed. Worse, **WebGL2 context creation succeeds even when the context is
backed by a software rasterizer.** Both together mean the standard "detect the GPU, degrade if
weak" pattern returns a confident, wrong answer.
Source: <https://v2.tauri.app/develop/debug/linux-graphics/#silent-failures-webgl-and-canvas>

**Why.** Renderer strings are a strong fingerprinting signal, and WebKit's privacy posture is
to remove them. That is a reasonable browser decision that happens to be actively hostile to
a desktop app trying to pick a rendering path.

**Trade-off / consequence.** You cannot build a runtime capability check for the fast path on
Linux. Anything that reads `WEBGL_debug_renderer_info` and branches is dead code there. The
only honest designs are: (a) give WebGL-heavy views a non-WebGL fallback on Linux, and
(b) expose it as a **user setting**, because the user can see that it is slow and you cannot.
This is the official guidance, not a workaround.

**Failure modes, symptom-first.**

- *"Our 3D view runs at 3 fps for some Linux users and we cannot reproduce it; capability
  detection says their GPU is fine."* Software rasterizer. Ask them for `XDG_SESSION_TYPE`
  and whether launching with `WEBKIT_DISABLE_DMABUF_RENDERER=1` changes anything, and give
  them the fallback toggle.
- *"Telemetry says 100 % of our Linux users have an Apple GPU."* You are reading the masked
  string. Stop reporting that field on Linux; it is noise.

**When to deviate.** If your WebGL surface is decorative (a background effect), skip the
detection entirely and just do not render it on Linux. Detection you cannot trust is worse
than no detection, because it makes the wrong branch look deliberate.

---

## 9. The asset protocol's Unix dotfile trap

Scope *design* — what to allow and why the scope is not your security boundary — is
`references/security.md`. What belongs here is the **platform-specific matching behaviour**,
because it fails differently on Unix than on Windows and produces a uniquely confusing bug.

**Mechanism.** On Unix, `assetProtocol.scope`'s **`requireLiteralLeadingDot` defaults to
`true`**. Under that rule the glob wildcards `*`, `?`, `**` and `[...]` do **not** match a path
component that begins with `.`. So:

```jsonc
{ "app": { "security": { "assetProtocol": {
  "enable": true,
  "scope": { "allow": ["$HOME/**"], "requireLiteralLeadingDot": false }
}}}}
```

`"$HOME/**"` with the default (`true`) allows `/home/alice/Documents/file.png` and **refuses**
`/home/alice/.cache/myapp/preview.png` — silently, with no hint that a dot was the reason.
Ref: tauri-apps/tauri#13788.

Two fixes, and they are not equivalent: name the segment literally
(`"$HOME/.cache/myapp/**"`), which keeps the protection; or set
`requireLiteralLeadingDot: false`, which turns it off for the whole scope and means `**/*` now
also matches `~/.aws/credentials` and `~/.ssh/`. Prefer the literal segment. Note that
`requireLiteralLeadingDot` can only be set on the **object** form of `scope` — the array
shorthand has nowhere to put it, so switching to the object form is part of the fix.

**Why the default exists.** Dotfiles on Unix are where credentials live. Making a broad glob
skip them by default converts a careless `$HOME/**` from "reads every secret on the machine"
into "reads visible documents". It is a genuinely good default that is invisible until it
bites.

**Trade-offs.** The protection costs you a silent, unlogged refusal that looks like a broken
image rather than a permission error — the worst possible ergonomics for the right behaviour.
Budget for the confusion; write the literal-dot path the first time.

**Failure modes, symptom-first.**

- *"Images load from `~/Pictures` but not from our own cache directory under `~/.cache` /
  `~/.local`, on Linux and macOS only, and there is no error."* Leading-dot rule.
- *"The scope `["*/**"]` allows nothing at all on Linux."* Resolved paths are absolute, so a
  relative-looking pattern can never match. Use `$HOME/**/*`, an absolute path, or a `$VAR`.
- *"It works in `tauri dev` and 404s in the built app."* In dev the frontend is served from
  `devUrl`, a real http origin, so `asset:` is often not exercised at all. See
  `references/debugging-and-testing.md` §"works in dev, broken in prod".

Also platform-shaped: prefer `**/*` over bare `**` for file globs, and remember that folders
the user picks at runtime through the dialog plugin are not covered by static config — persist
them with `tauri-plugin-persisted-scope = { version = "2", features = ["protocol-asset"] }`,
registering `tauri_plugin_fs` **before** `tauri_plugin_persisted_scope`.

---

## 10. Build prerequisites, exactly

Source for all of this: <https://v2.tauri.app/start/prerequisites/>

**Windows.** Microsoft C++ Build Tools with the *"Desktop development with C++"* workload;
WebView2 Evergreen Bootstrapper (already present on Win 11 and Win 10 ≥ 1803); Rust on an
**MSVC** host triple — `rustup default stable-msvc` (`x86_64-pc-windows-msvc`, `i686-`,
`aarch64-`). The GNU toolchain breaks Tauri and `trunk`; this is not a preference. Add the
VBSCRIPT optional feature only if you bundle `.msi`.

**macOS** (Catalina 10.15+). `xcode-select --install` is enough for desktop. Full Xcode is
required only for iOS targets.

**Linux**, per distro:

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install libwebkit2gtk-4.1-dev \
  build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev

# Arch
sudo pacman -S --needed webkit2gtk-4.1 base-devel curl wget file openssl \
  appmenu-gtk-module libappindicator-gtk3 librsvg xdotool

# Fedora
sudo dnf install webkit2gtk4.1-devel openssl-devel curl wget file \
  libappindicator-gtk3-devel librsvg2-devel libxdo-devel
sudo dnf group install "c-development"

# openSUSE
sudo zypper in webkit2gtk3-devel libopenssl-devel curl wget file \
  libappindicator3-1 librsvg-devel
sudo zypper in -t pattern devel_basis

# Alpine  (note the font package — see below)
apk add build-base webkit2gtk-4.1-dev curl wget file openssl \
  libayatana-appindicator-dev librsvg font-dejavu

# OSTree / Silverblue  (reboot afterwards)
rpm-ostree install webkit2gtk4.1-devel openssl-devel curl wget file \
  libappindicator-gtk3-devel librsvg2-devel libxdo-devel gcc gcc-c++ make
```

Gentoo: `net-libs/webkit-gtk:4.1 dev-libs/libayatana-appindicator net-misc/curl net-misc/wget
sys-apps/file`. NixOS: <https://wiki.nixos.org/wiki/Tauri>; `wry` suggests `pkgs.webkitgtk_4_1`
plus `pkg-config`.

**Runtime** (not build) dependencies baked into the generated `.deb`: `libwebkit2gtk-4.1-0`,
`libgtk-3-0`, and `libappindicator3-1` if the app uses a tray.
Source: <https://v2.tauri.app/distribute/debian/>

Mobile adds `JAVA_HOME` / `ANDROID_HOME` / `NDK_HOME` and
`rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android`;
iOS adds `rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim` and
`brew install cocoapods`.

### The `webkit2gtk-4.0` → `4.1` break

**Mechanism.** v2 requires WebKitGTK **4.1**, which implies **libsoup3** (4.0 is the libsoup2
ABI). Consequences, all of which look like unrelated failures:

- Every v1-era Linux install snippet (`libwebkit2gtk-4.0-dev`, `webkit2gtk4.0-devel`) fails
  `pkg-config` for v2. This is the single most common "the docs are wrong" report from someone
  following a 2023 blog post.
- The v1 Cargo feature **`linux-protocol-headers` is gone** — *"now enabled by default since we
  upgraded our minimum webkit2gtk version."* A `features = ["linux-protocol-headers"]` line
  copied from v1 will not compile.
- A new v2 feature **`linux-protocol-body`** (custom-protocol request-body parsing for IPC)
  **requires webkit2gtk ≥ 2.40** — so enabling it silently raises your Linux floor above the
  distro table in §2.

Sources: <https://v2.tauri.app/start/migrate/from-tauri-1/#new-cargo-features> and
`#removed-cargo-features`; wry feature list <https://github.com/tauri-apps/wry#feature-flags>

**Failure modes, symptom-first.**

- *"`/usr/lib/libc.so.6: version 'GLIBC_2.33' not found` on a user's machine."* glibc is
  forward-compatible only. A binary built against a newer glibc cannot run on an older one.
  **Build on the oldest base system that still provides WebKitGTK 4.1** — officially Ubuntu
  22.04 or Debian 12 — via Docker or a pinned GitHub Actions image. There is no runtime fix.
  Source: <https://v2.tauri.app/distribute/debian/#limitations> (refs tauri-apps/tauri#1355,
  rust-lang/rust#57497)
- *"The app cannot find `git` / `node` / `python` when launched from the desktop, but works
  when launched from a terminal."* GUI apps on macOS and Linux do **not** inherit `$PATH` from
  shell dotfiles. Official fix crate: <https://github.com/tauri-apps/fix-path-env-rs>. This is
  a two-platform bug that never reproduces on Windows.
- *"Text renders blank in our Alpine container."* Alpine ships no fonts. `font-dejavu` (or any
  font package) is a hard requirement, not a nicety.
- *"Cross-compiling to macOS with osxcross panics: `Class with name WKWebViewConfiguration
  could not be found`."* Add `RUSTFLAGS="-l framework=WebKit"`. Source: wry README, macOS
  section.

**Trade-off of building on the oldest base.** You get maximum reach and you compile against an
old toolchain, old WebKitGTK headers, and old everything — which is also exactly the
environment where `linux-protocol-body` and modern CSS assumptions break. Old build host and
modern feature baseline are in direct tension; pick one deliberately per release channel.

---

## 11. Express divergence in config, not in `cfg!`

**Mechanism.** The CLI automatically discovers and merges `tauri.macos.conf.json`,
`tauri.linux.conf.json`, `tauri.windows.conf.json`, `tauri.android.conf.json` and
`tauri.ios.conf.json` over the base `tauri.conf.json`. `--config <json|file>` is repeatable and
merged on top, in order, with later values winning — that layer is for build *flavors*
(staging, demo), not for platforms.

**Why this is the right place for everything in this file.** `macOSPrivateApi`,
`webviewInstallMode`, `useHttpsScheme`, and the Linux `transparent: false` decision are all
**configuration**, and configuration is compiled in and inspectable. Branching on
`cfg!(target_os = ...)` inside Rust to build different windows hides the platform matrix inside
control flow where no reviewer will find it, and it cannot express bundler-level keys at all.
The one thing that legitimately belongs in Rust is the env-var workaround in §7, because it
must run before the builder exists.

**Trade-off.** Five config files drift. Nothing validates that `main`'s window options are
coherent across them, and a key you add to the base file is silently overridden by a stale
platform file. Keep the platform files as **small as possible** — only the keys that genuinely
differ — and review them together. The real matrix two shipping apps ended up with, and where
they disagree, is `references/case-studies.md` §4.

---

## 12. v1 → v2, platform behaviour only

Agents will meet v1-era blog posts constantly. These are the entries that change **platform
behaviour** — the ones that make a copied snippet fail on one OS. The complete API and config
migration map (config root, `devPath`/`distDir`, allowlist → capabilities, `Window` →
`WebviewWindow`, the `@tauri-apps/api` split, event semantics) lives in
`references/architecture.md` §v1→v2, and is not repeated here.

| v1 | v2 | What breaks if you don't know |
| --- | --- | --- |
| `libwebkit2gtk-4.0-dev` | **`libwebkit2gtk-4.1-dev`** (libsoup3) | Every Linux install snippet; `pkg-config` failure |
| feature `linux-protocol-headers` | default-on (webkit bumped) | Won't compile if you copy it |
| — | new feature **`linux-protocol-body`** | Silently raises your Linux floor to webkit2gtk ≥ 2.40 |
| `https://tauri.localhost` (Windows) | **`http://tauri.localhost`** | ⚠️ Wipes IndexedDB / LocalStorage / Cookies — §4 |
| `tauri.bundle.windows.webviewFixedRuntimePath` | **`bundle.windows.webviewInstallMode`** | Removed key, silently ignored |
| `tauri.windows.fileDropEnabled` | **`app.windows.dragDropEnabled`** | Renamed; native drop handler stays on |
| `tauri > allowlist > protocol > assetScope` | **`app.security.assetProtocol.scope`** (+ `enable`) | Assets 404 in prod |
| feature `system-tray`, `tauri.systemTray` | **`tray-icon`**, `app.trayIcon` | Tray silently absent |
| feature `windows7-compat` | moved onto **`tauri-plugin-notification`** | Win 7 notifications |
| `TAURI_TRAY` | `TAURI_LINUX_AYATANA_APPINDICATOR` | Linux tray backend selection |
| `TAURI_PLATFORM` / `_ARCH` / `_FAMILY` / `_DEBUG` / … | `TAURI_ENV_PLATFORM` / `_ARCH` / `_FAMILY` / `_DEBUG` | **Hook scripts break silently** — the variable is just empty |
| `TAURI_SKIP_DEVSERVER_CHECK` | `TAURI_CLI_NO_DEV_SERVER_WAIT` | CI hangs or races |
| `TAURI_DEV_SERVER_PORT` | `TAURI_CLI_PORT` | CI binds the wrong port |
| `TAURI_DEV_WATCHER_IGNORE_FILE` | `TAURI_CLI_WATCHER_IGNORE_FILENAME` | Watcher thrashes |
| `TAURI_FIPS_COMPLIANT` | `TAURI_BUNDLER_WIX_FIPS_COMPLIANT` | MSI build flag ignored |

Sources: <https://v2.tauri.app/start/migrate/from-tauri-1/> ·
<https://v2.tauri.app/reference/environment-variables/>

The renamed environment variables deserve their own warning: **nothing errors**. A CI script
that reads `TAURI_PLATFORM` now reads an empty string and takes whatever branch empty implies.
Signing and bundling env renames are in `references/build-and-distribution.md`.

`tauri migrate` exists, and the docs are emphatic that *"This command is not a substitute for
this guide!"* — in particular it will not tell you about the Windows origin flip, which is the
one that costs you user data.

---

## 13. Verifying a platform claim

**Mechanism.** `tauri info` is the canonical environment dump and the only thing worth asking
a reporter for. It prints OS and session type (e.g. `ubuntu-xorg on x11`), the
`webkit2gtk-4.1` version, `rsvg2`, the Rust and Node toolchains, and — critically — the
resolved versions of `tauri`, `tauri-build`, **`wry`**, **`tao`**, the CLI, `@tauri-apps/api`
and every plugin, plus the App section (`build-type`, CSP, `frontendDist`, `devUrl`, framework,
bundler).

**Why `wry` and `tao` are the ones that matter.** Webview behaviour is decided by `wry`/`tao`,
not by the `tauri` version — two apps on `tauri 2.11.5` can resolve different `wry` patch
versions and render differently. "What Tauri version are you on?" is the wrong question; ask
for the whole `tauri info` output. A real instance of this exchange is in tauri-apps/tauri#14590.

**Trade-off / limit.** `tauri info` describes the *build* environment. It does not tell you the
user's GPU driver, session type at runtime, or whether they are running an AppImage — all of
which change the answer on Linux (§7). For a Linux report also collect `XDG_SESSION_TYPE`, the
NVIDIA driver version, and the packaging format. Build that into a "copy diagnostics" command
rather than asking; see `references/debugging-and-testing.md` §diagnostics.

**When to deviate.** Nothing in this file substitutes for running the build on the platform.
Rule 5 of the skill exists because every claim here has an exception on some distro. State
which platforms you verified and which you did not — an unverified platform is a finding, not
an omission.

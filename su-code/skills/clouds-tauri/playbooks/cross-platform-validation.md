# Cross-platform validation — prove the app works where you claim it does

**Objective** — produce an honest, evidence-backed statement of which platforms this build
works on, by testing the things that actually diverge and by naming the ones you did not test.

**The rule this playbook exists to enforce: an unverified platform is a finding, not an
omission.** Silence about Linux reads as "Linux works". Report coverage as a matrix with
explicit *not verified* cells, every time. Claiming uniform coverage you did not measure is
the failure mode; an honest gap is not.

**When to run this**
- Before any release (`playbooks/release-preparation.md` step 6 pulls this in).
- After any change touching rendering, transparency, decorations, drag regions, menus, tray,
  notifications, filesystem paths, the asset protocol, or CSS/JS features.
- When a bug is reported on one platform and you need to know whether the others share it.
- Whenever you are about to write "should work on all platforms" — that sentence is the
  trigger.

The divergence map — what differs, why, and how to handle each case — is
`references/cross-platform.md`. This file is the order you check them in and how you report
the result. Do not restate mechanism here; look it up there.

---

## Order

### 1. Establish what you actually claim to support

Before testing, write the claim down. It is narrower than "Windows, macOS, Linux":

- Architectures per OS (`x86_64`, `aarch64`).
- **Minimum OS versions** — for macOS this pins your WKWebView, which is not upgradable
  separately (`references/cross-platform.md`).
- **Minimum Linux distro versions** — this pins your oldest WebKitGTK, and therefore your
  real web-feature baseline (`references/cross-platform.md §Linux`).
- Which bundle formats you distribute per OS. An AppImage and a `.deb` do not fail the same
  way.
- Windows: whether the WebView2 runtime is bundled, downloaded, or assumed present
  (`references/cross-platform.md §Windows`).

You cannot validate an unstated claim, and most "cross-platform bugs" are a claim nobody
ever wrote down.

### 2. Walk the divergence matrix — what actually differs

These are the axes where a single implementation produces different behaviour. Test each on
each claimed platform. Look each row up in `references/cross-platform.md` when it fails;
the mechanism and the fix are there.

| Axis | What to exercise | Diverges because |
| --- | --- | --- |
| **WebView engine** | The newest CSS/JS features your frontend uses; any `Intl`, `:has()`, container query, or modern API | WebView2 (Chromium, evergreen) vs WKWebView (pinned to macOS) vs WebKitGTK (pinned to distro, oldest) — `references/cross-platform.md` |
| **Filesystem semantics** | Paths with spaces, non-ASCII, and mixed case; app data/config/cache dirs; the asset protocol against real user paths | Case sensitivity, separators, per-OS base directories, dotfile matching — `references/cross-platform.md §Linux` |
| **Window decorations** | Custom titlebar, drag regions, resize handles, transparency, rounded corners, maximize/snap | Each compositor implements this differently; `decorations: false` + `transparent: true` is the highest-divergence combination there is (`references/case-studies.md` §4) |
| **Menus** | App menu vs window menu placement, accelerators, the standard items each OS expects | macOS has one app-level menubar; Windows/Linux are per-window — `references/desktop-ux.md §menus` |
| **Tray** | Icon appearance in light/dark, left- vs right-click behaviour, menu open, quit path | Tray semantics and even availability differ; some Linux desktops need a StatusNotifier host — `references/desktop-ux.md` |
| **Notifications** | Permission prompt, delivery while focused, click-to-focus, delivery while the app is closed | Native notification centre per OS, and per Linux desktop — `references/desktop-ux.md` |
| **DPI / scaling** | 100% / 150% / 200%; moving the window between monitors of different scale mid-session | Different scale-change events and different physical/logical pixel handling — `references/desktop-ux.md §DPI` |
| **Shell / external open** | Opening URLs and files with the default handler | Different backends, and different scope semantics — `references/desktop-ux.md §shell` |
| **GPU / rendering** | Scroll, animation, video, canvas, WebGL on both integrated and discrete GPUs | The NVIDIA/DMA-BUF class on Linux is the single highest-frequency platform defect in this stack — `references/cross-platform.md §Linux`, `references/case-studies.md` §8 |

Record each cell as **pass / fail / not tested**. "Not tested" is a legitimate and required
value; leaving it blank is not.

### 3. Split the matrix into CI-coverable and hardware-only

CI is real coverage for some of this and worthless for the rest. Being clear about the line
stops you trusting a green pipeline for things it never touched.

**CI can cover** (`references/build-and-distribution.md §CI`):

- That it **builds** on each target — the largest category of platform break, and the
  cheapest to catch.
- Native prerequisites resolving on a clean runner (a missing system library shows up here
  and nowhere in local dev).
- Rust unit and integration tests per target.
- Bundling per format, and that artifacts are produced and non-empty.
- Headless WebDriver runs where you have them
  (`references/debugging-and-testing.md §testing`).

**CI cannot cover — real hardware or a real VM with a session, only:**

- Anything GPU: compositing, transparency, video, WebGL, the DMA-BUF class. CI runners have
  no GPU and will pass a build that renders a blank window on a user's machine.
- Window decorations, drag regions, snap/tile behaviour, and multi-monitor.
- DPI scaling above 100%, and cross-monitor scale changes.
- Tray icon presence and behaviour.
- Native notification delivery and click behaviour.
- Signing and Gatekeeper/SmartScreen outcomes, which are trust decisions made by a real OS
  on a machine that did not build the app (`playbooks/release-preparation.md` step 6).
- Installer UX and the in-place upgrade path.

Everything in the second list that you did not run on hardware is a *not tested* cell. That
is the entire point of the split.

### 4. Bound the Linux distro problem

"Linux" is not a platform; it is an open set, and you cannot test it. So do not try —
bound it instead:

1. **Name a support floor**: the oldest distro release you support. That fixes your
   WebKitGTK version and therefore your web-feature baseline
   (`references/cross-platform.md §Linux`). Everything older is explicitly unsupported, in
   writing.
2. **Pick a small representative set that spans the real axes**, not a long list of
   near-identical distros. The axes that produce different behaviour are: package family
   (Debian/Ubuntu vs Fedora/RHEL vs Arch), desktop and compositor (GNOME vs KDE), display
   server (**Wayland vs X11** — test both; they diverge on decorations, DPI and tray), GPU
   driver (Mesa vs proprietary NVIDIA — the NVIDIA case is not optional given its defect
   frequency), and bundle format (`.deb` / `.rpm` / AppImage).
   A four-VM set covering Ubuntu LTS on both Wayland and X11, Fedora on GNOME, and one
   NVIDIA machine covers more real risk than a dozen Ubuntu derivatives.
3. **Ask reporters for `tauri info`** rather than guessing their environment
   (`references/cross-platform.md`).
4. **Treat everything outside the set as community-reported**, and say so. That is an honest
   support statement, and it is the only one you can back.

### 5. Report the matrix, including the gaps

The deliverable of this playbook is the matrix, not a sentence. Per platform: version tested,
architecture, how (CI / VM / real hardware), and the result per axis from step 2. Explicit
*not verified* rows for anything you could not reach, each with the reason.

An unverified platform goes in the report as a finding with a severity, exactly like a bug
would (`SKILL.md` output contract, point 3). Do not soften it, do not omit it, and do not
let a build-only CI pass stand in for it.

---

## Validation

- The support claim from step 1 exists in writing and every platform in it appears in the
  matrix.
- Every cell of the step-2 matrix has a value; none are blank.
- Every axis marked *pass* names how it was exercised — CI job, VM, or physical machine —
  and no hardware-only axis (step 3) is marked pass on the strength of CI.
- `pnpm tauri build` succeeded on each claimed target, and the artifact was installed and
  launched on a machine that did not build it (`playbooks/release-preparation.md` step 6).
- Linux: both Wayland and X11 exercised, and at least one NVIDIA machine, or those cells
  are marked *not tested*.
- The report states which platforms were verified and which were not. If it does not, this
  playbook did not run.

---

## Pitfalls

- **Silence implying coverage.** Reporting only what you tested, with nothing said about the
  rest, is read as full coverage. Name the gaps.
- **Trusting a green CI matrix.** It proves the app *builds* on three OSes. It says nothing
  about anything GPU, decoration, DPI, tray, or notification related (step 3).
- **Testing Linux on one distro.** Especially testing only the maintainer's daily driver,
  which is the least representative machine available.
- **Testing only Wayland, or only X11.** They diverge on exactly the axes users notice.
- **Testing only on a GPU that works.** The NVIDIA/DMA-BUF class does not reproduce on Intel
  integrated graphics (`references/cross-platform.md §Linux`).
- **Testing only at 100% DPI.** Most Windows laptops ship at 150%.
- **Assuming a fix on one platform is a fix everywhere.** It is a fix on one platform and an
  untested change on two.
- **Testing in `tauri dev`.** Decorations, asset paths and CSP behave differently in a
  bundle (`playbooks/production-debugging.md`).
- **Testing the same OS version as the build machine.** Your macOS WKWebView and your
  minimum-supported macOS WKWebView are different engines.

---

## Escalate

Stop and ask rather than proceeding when:

- You have no access to a platform in the support claim. Do not test-by-inference — say the
  platform is unverified and let the project decide whether to acquire access or narrow the
  claim.
- The support claim itself is undefined (no minimum OS or distro versions). Get it decided;
  without it there is no pass/fail criterion and step 2 has no meaning.
- A divergence needs a per-platform behavioural difference rather than a fix — that is a
  product decision, and it belongs in config rather than `cfg!` (`references/cross-platform.md`).
- A platform failure would require dropping support for it. That is a release decision, not
  a validation outcome.
- The only fix available is one of the destructive Linux GPU workarounds. Read
  `references/cross-platform.md §Linux` and escalate rather than shipping a global disable.

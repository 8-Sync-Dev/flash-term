# Desktop UX review — native application, or website in a frame

**Objective** — decide whether the app behaves like a desktop application on each platform it
ships to, and enumerate every place it behaves like a web page instead.

**When to run this** — before the first release, before any release that adds a window, tray,
menu, or titlebar change, and whenever a user says the app "feels weird" without being able to
say why. That sentence is almost always one of the items below.

**Scope** — this review is **run against a running build, on each target platform**. It is not
a code read. Read code only to explain something you observed. Visual craft — spacing,
hierarchy, colour, motion — is `impeccable`'s call and is out of scope here; this playbook owns
*desktop-native behaviour*.

Load `~/.agents/skills/impeccable/SKILL.md` alongside this one if the review will produce
UI changes (`SKILL.md` Rule 12).

## Review rules (shared by all four review playbooks)

- Report **every** real finding with a severity — `Critical` / `High` / `Medium` / `Low`.
  Do not pre-filter; small native-behaviour breaks are exactly what accumulates into
  "feels like a website".
- Every finding carries a **`file:line`** (the config key, the CSS rule, the menu builder) and
  a **concrete fix**, not a concern.
- **Read the code before claiming behaviour** — and here, also *drive the app*. A finding you
  did not reproduce is a question.
- **State which platforms you verified.** This review is platform-shaped end to end; an
  unverified platform is a `High` finding on its own, because window chrome, menus, and DPI
  diverge more than anything else in the stack.

Report in the shape of `SKILL.md` §Output contract.

---

## Order

**1. Build and run it. Release-ish, not `dev`.**

```bash
cargo tauri build --debug
```

`dev` hides window-state and asset-path behaviour. Everything below is observed on the built
app. Record the OS version and the WebView engine version you are testing against.

**2. Window state across restarts — the first thing a user notices by its absence.**

Do this sequence exactly, three times, and record what happens:

1. Move the window to a non-default position, resize it, quit, relaunch.
   → Expected: same position, same size.
2. Maximize, quit, relaunch. → Expected: maximized, and *un-maximizing restores the previous
   size*, not the default.
3. Move the window to a secondary monitor, quit, **unplug that monitor**, relaunch.
   → Expected: the window appears on a monitor that exists. A window restored off-screen is a
   `Critical`: the app is unusable and the user cannot fix it without editing state files.

Also check the launch itself: is there a visible flash of an unsized or white window before the
real one appears? If so, the window is being shown before it is ready — `Medium`, and the fix
is the `visible: false` + show-from-Rust-after-restore pattern
(`references/desktop-ux.md`).

**3. Custom titlebar correctness — the highest-defect-density area in a Tauri app.**

Skip to step 4 if the app uses native decorations. Otherwise the app is reimplementing window
management in HTML and every one of these is broken until proven otherwise. ZUS ships this
configuration — `decorations: false`, `titleBarStyle: "Overlay"`, `transparent: true` — and the
per-platform split of those values is not stylistic (`references/case-studies.md` §4).

Test each, on each platform:

| Interaction | Expected | Severity if broken |
| --- | --- | --- |
| Drag the empty area of the titlebar | Window moves | `High` |
| Drag a *button* in the titlebar | Window does **not** move; the button activates | `High` |
| Double-click the titlebar | Maximize / restore toggles | `Medium` |
| Windows: drag to the top edge | Snap preview appears | `Medium` |
| Windows: hover the maximize button | **Snap Layouts flyout** appears | `Medium` |
| Windows: right-click the titlebar | System menu (Move/Size/Close) | `Medium` |
| macOS: traffic lights position and inset | Matches the platform, does not overlap content | `High` |
| macOS: double-click behaviour respects the system "double-click to" setting | Yes | `Low` |
| Resize from every edge and every corner | All 8 work | `High` |
| Drag a file onto the window | The app's drop handling fires, not the WebView's default | `Medium` |

Snap Layouts is the one that reveals a fake titlebar instantly on Windows 11, because a
`<div>` cannot produce it — it requires the real maximize button hit-test. Report it as a
finding with the platform named, and cite `references/cross-platform.md` §Windows for what the
platform requires.

If `transparent: true` is set, also check idle CPU/GPU on macOS — transparency has a standing
cost (`references/performance.md` §rendering). Transparency the design does not use is a
`Medium` finding.

**4. Menus — platform-correct, or a Windows menu on a Mac.**

`references/desktop-ux.md` §menus is the authority; the review questions are:

- **macOS: is there an application menu at all?** No menu bar is `High` — the app has no
  About, no Preferences at `⌘,`, no Services, no Hide, no Quit item where the platform puts it.
- **Are the standard items `PredefinedMenuItem`s** (Copy, Paste, Select All, Minimize, Zoom,
  Close, Quit, About, Services)? Hand-rolled equivalents lose the platform's accelerators,
  localisation, and enable/disable behaviour — `Medium` each, and the fix is a one-line swap.
- **Does Edit → Copy/Paste actually work inside the WebView?** On macOS, missing the
  predefined edit items breaks `⌘C`/`⌘V` in text fields with no other symptom. `High`.
- **Windows/Linux: is a macOS-style app menu being drawn where the platform expects a window
  menu or none at all?** `Medium`.
- **Do accelerators match the platform** (`⌘` vs `Ctrl`, `⌥` vs `Alt`)? A hardcoded `Ctrl` on
  macOS is `Medium`.
- **Context menus**: does right-click in content areas offer something useful and native-ish,
  and does right-click in a text field offer the edit menu?

**5. Tray and background lifecycle.**

- Close the last window. Does the process exit, or stay resident? Decide which the app *intends*
  and check it matches. A background-resident app with no tray icon is `High` — the user cannot
  see it, quit it, or reach it.
- With a tray icon: left-click, right-click, and double-click each do the platform's expected
  thing (they differ per platform — `references/desktop-ux.md` §shell).
- Does the tray menu have an unambiguous **Quit**? Missing is `High`.
- Relaunching while an instance is resident: does it focus the existing window or start a
  second process? A second process is `High`.
- On macOS, does clicking the Dock icon with no windows open restore one? No → `Medium`.

**6. Dialogs — native, or a `<div>` pretending.**

For every confirm/alert/open/save flow: is it the platform dialog, or HTML? A file picker that
is not the OS picker is `High` — it cannot reach the user's real filesystem shortcuts, recents,
iCloud/OneDrive locations, or their accessibility settings. `window.alert`/`confirm` inside a
WebView is `Medium` and looks wrong on all three platforms. Fix: the dialog plugin
(`references/plugins.md`). Destructive confirmations especially must be native.

**7. Keyboard — shortcuts, and what the WebView already owns.**

- Does `Escape` close the frontmost modal, and does `Enter` activate its default action?
- Tab order: can the primary flow be completed with the keyboard alone, and is focus visible?
  Invisible focus is `High` (accessibility).
- **Conflicts with WebView bindings** — press `Ctrl/⌘ +`, `Ctrl/⌘ -`, `Ctrl/⌘ 0`, `Ctrl/⌘ R`,
  `Ctrl/⌘ P`, `Ctrl/⌘ F`, `F5`, `F12`, `Ctrl+Shift+I`, backspace-outside-a-field. Each either
  does the app's thing or the browser's; a browser reload that discards unsaved app state is
  `High`, and a zoom that breaks a fixed-size layout is `Medium`.
- Global shortcuts registered by the app: are they conflict-checked, and can the user change
  them? An unchangeable global shortcut that collides with an OS binding is `High`.

**8. DPI and multi-monitor.**

`references/desktop-ux.md` §DPI holds the mechanism; the review drives it:

- Run on a 2× display and a 1× display. Any blurry raster asset, hairline that vanishes, or
  1px border that becomes 0.5 → `Medium`.
- **Drag the window between monitors with different scale factors** while it is open. The
  layout must reflow on the scale change, not on the next resize. A window that stays at the
  old scale until nudged is `High` and is the classic missed `ScaleFactorChanged` handling.
- Windows: check at 125% and 150%, which are the common real-world settings, not 200%.
- Very small and very large monitors: does `minWidth`/`minHeight` keep the app usable, and does
  a maximized window on a 4K display look designed or stretched?

**9. Browser affordances that should not be there — and the ones that should.**

Web apps in a frame are given away by `user-select: none` everywhere, a suppressed context
menu, and no text selection.

- Is text selection disabled on *content* the user would reasonably copy (an error message, an
  ID, a log line, a model response)? `High` — a desktop app lets you copy its text. Disabling
  selection is correct on chrome (titlebar, toolbar, tabs) and wrong on content.
- Is the browser context menu suppressed globally with no native replacement? `Medium` — the
  user lost copy/paste and spellcheck in text fields.
- Is spellcheck on in long-form text inputs?
- Is drag-and-drop of the app's own content (HTML5 DnD) working, or intercepted by the native
  drag-drop handler? This is a known collision (`references/case-studies.md` §4); `Medium`.
- Overscroll/rubber-band bounce on the whole document, link cursors on buttons, and a text
  caret over non-text: each `Low`, each contributing to the website feeling.

## Validation

Each finding is validated by the reproduction that produced it — record the exact interaction
and the observed result, per platform, in a small matrix:

| Check | Windows 11 | macOS | Linux (which DE/compositor) |
| --- | --- | --- | --- |

Empty cells are findings, not blanks. Linux specifically needs its desktop environment and
compositor named (GNOME/Wayland behaves differently from KDE/X11 for decorations, drag, and
tray); "Linux" alone is not a verified platform.

After a fix lands, re-run only the affected row and paste the new observation. Rebuild with
`cargo tauri build --debug` before re-testing — several of these behaviours differ under
`tauri dev`.

## Pitfalls

- **Reviewing in `tauri dev`.** Window state, titlebar overlay behaviour, and asset loading
  all differ from a built app.
- **Testing on one monitor.** Half of section 8 is unreachable that way.
- **Accepting "it works on my machine" for the titlebar.** The three platforms need three
  configs; a single set of values that looks fine on your OS is the default failure.
- **Filing visual taste as a native-behaviour defect.** Spacing and colour go to `impeccable`;
  keep this report about behaviour or it will be ignored.
- **Assuming the tray icon works because it appears.** Click behaviour is per-platform.
- **Confusing "the app suppresses zoom" with "the app is broken"** — suppressing zoom is a
  legitimate decision *if* the app provides its own text-size control. Check for the
  replacement before filing.

## Escalate

- A finding requires changing `decorations`, `transparent`, or `titleBarStyle` → that is a
  three-platform change with rendering and performance consequences; take it through
  `playbooks/cross-platform-validation.md`, not a spot fix.
- The app needs a menu bar it has never had → design decision, involve the owner; a wrong menu
  structure is worse than none on macOS.
- You could not test a platform at all → say so plainly, list what is unverified, and do not
  let the review be read as a pass.
- A native-behaviour fix conflicts with the visual design → `impeccable` and this skill
  disagree; surface the conflict rather than silently picking one.

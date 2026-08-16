# Rendering performance

**Objective** — separate "the renderer is slow" from "the main thread is blocked" (they look
identical to the user), then fix the right one, on the platform where it was measured.

**When to run this**

- Jank, stutter, low FPS, high input latency, "it feels laggy while scrolling / typing /
  dragging".
- A canvas, chart, map, editor or terminal that is smooth in a browser and not in the app.
- Fan spin or battery drain with the UI apparently idle.
- **Not** for slow launch — `playbooks/startup-performance.md`. **Not** for a slow single
  operation with a spinner — that is IPC (`references/performance.md` §5).

---

## Order

### 1. Measure first — record the jank before changing anything

Two numbers, both from a **release** build of the app (not `tauri dev`, not the same frontend
opened in Chrome — different engine, different compositor, different answer):

1. **A devtools Performance recording of the exact interaction**, 5–10 s, started just before
   the jank and stopped just after. Record: longest long-task duration (ms), frames dropped,
   and whether the main thread shows continuous work or a single flat gap. Getting the
   inspector open on a built app is `references/debugging-and-testing.md` §devtools.
2. **The freeze duration by wall clock**, and — critically — **whether native window chrome
   responds during it**. Try to drag the window, resize it, open the native menu, and (if you
   have one) interact with a *second* window.

Write down the platform, OS build, GPU, display refresh rate, and Tauri version with the
numbers. Every finding below is platform-scoped and does not transfer.

### 2. Is this rendering at all? Check for a sync command first

**This is the more common cause and it produces the identical user report.** A
`#[tauri::command]` that is not `async` runs on the tao event loop thread; blocking in it
freezes every window in the app (`references/performance.md` §7.1,
`references/ipc-and-commands.md` §Threading).

The discriminator is step 1's second number:

| During the jank | Layer | Go to |
| --- | --- | --- |
| Window drag/resize, native menus and **other windows** are all dead | Rust event loop | this step |
| Native chrome stays responsive, only page content stutters | WebView renderer | step 3 |
| Devtools shows a flat gap with **no** JS on the main thread | Rust event loop | this step |
| Devtools shows continuous scripting/layout/paint | WebView renderer | step 3 |

If it is the event loop:

- Search `src-tauri/src` for `#[tauri::command]` and read the **next** line of each hit: any
  declaration that is a plain `fn` (no `async`) doing IO, CPU work, or anything unbounded is a
  suspect. Pattern: `#\[tauri::command\][\s\S]{0,120}?\n\s*(pub )?fn ` matches only the
  non-async ones.
- Confirm with the `ipc::request::handle{cmd=…}` span (`references/performance.md` §8.1) — it
  gives you per-command handler time, so you get the command name rather than a guess.
- If no command is implicated, the blocker is in `setup`, a `RunEvent` handler, or a
  synchronous plugin hook. `samply` collects **off-CPU** samples on macOS and Windows, which is
  how you see a thread blocked on a lock rather than burning CPU
  (`references/performance.md` §8.3). On Linux it is on-CPU only, so this is the hardest
  platform for this question.

Fix per `references/performance.md` §7.1 / §7.2, re-measure at step 1, and stop. Do not
continue into rendering work — you have already found the cause.

### 3. WebView profiling

If the renderer is the layer, this is ordinary web performance and **`clouds-f` is the
authority**: layout thrash, unbatched style reads/writes, oversized images, non-virtualized
lists, `filter`/`backdrop-filter` over large repainting areas, layers that will not promote.
There is no Tauri-specific rendering pipeline to tune (`references/performance.md` §6.1).

What is Tauri-specific here is **which engine you profiled**. A recording taken in WebView2 on
Windows says nothing about WKWebView or WebKitGTK: three engines, three version floors
(`references/cross-platform.md` §1–§2). Label the recording with its engine, and repeat it on
any platform where the bug was reported.

Before concluding "the frontend is fine", check the IPC axis once: a 1000-row grid that takes
~0.3 s before anything renders is usually per-row `invoke` paying the transport floor N times
(`references/performance.md` §5.5), which shows up in a Performance recording as a wall of
small tasks rather than one long one.

### 4. The GPU and compositing path — per platform, and Linux is the special case

**Linux — assume nothing the page tells you.** WebGL2 context creation succeeds even when it is
backed by a software rasterizer, and WebKitGTK masks the renderer string so
`WEBGL_debug_renderer_info` reports `Apple GPU` on every Linux machine. **You cannot
feature-detect GPU acceleration on Linux.** Mechanism and the official guidance (ship a
non-WebGL fallback, expose it as a setting) are `references/performance.md` §6.2;
correctness failures — blank window, resize flicker, DMA-BUF framebuffer errors — plus the
ordered workaround ladder are `references/cross-platform.md` §Linux (§7 DMA-BUF escalation, §8
the GPU masking), with a shipped example in `references/case-studies.md` §8.

The performance rule when you reach for that ladder: **every rung disables a faster path for
every user.** An unconditional environment override to fix a minority NVIDIA bug is a global
rendering regression. Gate it by GPU/driver, or expose it as a setting.

**macOS — check `transparent: true` before anything else if the symptom is idle drain.** It
costs roughly 8× GPU power on a fully static page, measured with
`sudo powermetrics --samplers gpu_power` (`references/performance.md` §6.3, §8.4). Note *which*
process carries it: `com.apple.WebKit.GPU`, not your binary — read only your own process and
you will conclude everything is fine.

**Windows — WebView2 is Chromium with its own GPU process**, evergreen and preinstalled on
Windows 11, so a stale-engine explanation is far less likely than on the other two. Suspect the
page first.

**All three — there is no vsync or frame-pacing knob** anywhere in `WindowConfig` or the
`WebviewWindow` API (`references/performance.md` §6.4). If a proposed fix is "cap the frame
rate", the only place to implement it is inside the page.

### 5. Record which platform each finding was measured on

Write the findings as a per-platform table before proposing changes. "Jank fixed" without a
platform is not a result — a rendering result from one engine does not transfer to the other
two, and half the fixes above (transparency, DMA-BUF, compositing) are single-platform by
construction.

---

## Validation

1. Re-run **step 1 verbatim** on the platform where the problem was reported: same interaction,
   same release build, same machine, same recording length. Compare longest long task and
   dropped frames.
2. Re-run the step 2 discriminator. If native chrome was dead before and is alive now, you
   fixed a threading bug — say that, not "improved rendering".
3. For a macOS transparency change: `sudo powermetrics --samplers gpu_power` before and after,
   on the same static page, and quote GPU power (mW) plus HW active residency. Do **not** quote
   `ioreg … IOAccelerator` (see Pitfalls).
4. For a Linux graphics change: verify on the reporting GPU/driver combination *and* on at
   least one machine that did not have the bug, to show you did not regress the fast path.
5. State coverage explicitly: which of Windows / macOS / Linux you measured, and which you did
   not.

---

## Pitfalls

- **Fixing rendering when a sync command was the cause.** The single most common misdiagnosis
  in this stack. Step 2 exists because the two are indistinguishable from the user's chair.
- **Profiling in Chrome instead of the app.** Your dev browser is none of the three shipped
  engines. This is also how "works on my machine, slow on Linux" survives review
  (`references/cross-platform.md` §2).
- **Trusting `WEBGL_debug_renderer_info` on Linux.** It reports `Apple GPU` unconditionally.
  Any conclusion drawn from it is void (`references/performance.md` §6.2).
- **`ioreg -r -d 1 -c IOAccelerator` → `Device Utilization %` on macOS.** It reports ~30 % for
  *any* foreground WKWebView including a blank Safari tab, so it shows no difference between
  both arms of a transparency A/B (`references/performance.md` §6.3).
- **Shipping `WEBKIT_DISABLE_COMPOSITING_MODE=1` as a fix.** Official guidance is that it is
  the last rung of the ladder; unconditionally it disables accelerated compositing for every
  Linux user (`references/performance.md` §1.3, `references/cross-platform.md` §Linux).
- **`transparent: true` with nothing showing through.** Pure cost — per-frame compositing of an
  opaque surface, 120 wasted composites/s on a ProMotion display. `backgroundColor` plus
  `decorations: false` is the cheaper shape (`references/performance.md` §6.3, §2.4). If the
  design genuinely needs translucency, that is a legitimate product call made with the number
  in hand (`references/case-studies.md` §4).
- **A debug build.** Debug frontend bundles and unoptimized Rust distort both halves of the
  measurement.
- **Changing two things between recordings.** One change, one recording, or you have learned
  nothing about either.

---

## Escalate

Stop and ask rather than proceed when:

- The fix is a non-WebGL fallback path for Linux. That is a second render path to maintain for
  one platform — a product/staffing decision, not a perf decision
  (`references/performance.md` §6.2).
- The jank only reproduces on a specific GPU/driver on Linux and the only lever left is an
  environment override. Decide *how it is gated* with the owner before shipping it; an
  ungated override is a global regression.
- The measured cost is `transparent: true` and transparency is a deliberate part of the visual
  design. Take it to `impeccable` with the measured cost; do not silently turn off a design
  decision.
- Devtools cannot be opened on the build that shows the problem (release, customer machine).
  Get a reproducible build with the inspector enabled first
  (`references/debugging-and-testing.md` §devtools) — profiling by hypothesis is not profiling.
- The renderer is genuinely saturated by legitimate work (real-time visualization, large
  canvas). At that point the question is architectural — offscreen rendering, WebGL/WebGPU,
  or a native surface — and it needs a design discussion, not a tweak.

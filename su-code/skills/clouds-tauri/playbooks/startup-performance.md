# Startup performance

**Objective** — turn "the app takes too long to open" into four attributed numbers (process
spawn · Rust `setup()` · WebView creation · frontend first paint), fix the largest one, and
prove the fix with the same measurement on the same machine.

**When to run this**

- A user or a benchmark reports slow launch, or "blank window for N seconds then everything
  appears at once".
- Startup regressed after adding a plugin, a window, or a `setup()` step.
- Before a release, as a tracked number rather than a vibe.
- **Not** for "the UI freezes during an operation" — that is `references/performance.md` §7.1
  and `playbooks/rendering-performance.md`.

---

## Order

### 1. Measure first — cold and warm, separately, before editing anything

Nothing below this step is legitimate until you have two recorded numbers. Cold and warm are
different failures with different fixes; a single number hides which one you have.

Add a boot gate to the Rust side. This is ZUS's shipped approach (`case-studies.md` §10,
`src-tauri/src/lib.rs`, tauri 2.11.5) and it exists because a GUI app never exits, so
`Measure-Command` / `time` cannot bracket it:

```rust
// gate it behind an env var so it costs nothing in normal runs
let boot_t0 = std::time::Instant::now();
tauri::Builder::default()
    // …
    .build(tauri::generate_context!())?
    .run(move |_app, event| {
        if matches!(event, tauri::RunEvent::Ready) && std::env::var_os("APP_PERF_BOOT").is_some() {
            eprintln!("BOOT_MS={}", boot_t0.elapsed().as_millis());
            std::thread::spawn(|| {          // self-exit so a bench script can loop
                std::thread::sleep(std::time::Duration::from_secs(5));
                std::process::exit(0);
            });
        }
    });
```

`RunEvent::Ready` fires when the event loop starts — i.e. it brackets everything in
`references/performance.md` §2.1 steps 1–3 and **stops before the frontend loads**. That is a
feature: it is the native half of the number, isolated.

Run against a **release** build (`cargo tauri build`, then launch the bundled binary). Debug
timings are not proportional to release timings.

- **Warm** — launch, wait for `BOOT_MS`, let it self-exit, repeat immediately. Take the median
  of ≥ 3 runs. On Windows the WebView2 runtime process group is likely still resident, which
  is exactly what "warm" means here (`references/performance.md` §2.2).
- **Cold** — reboot, or at minimum ensure no other process is holding the engine alive
  (Windows: no `msedgewebview2.exe` in the process list; macOS: no
  `com.apple.WebKit.WebContent` from another app; Linux: no `WebKitWebProcess`). Median of
  ≥ 3, rebooting between each is the honest version.

Record: `cold_ms`, `warm_ms`, machine, OS build, Tauri version, release/debug. Anything you
cannot label with all five is not a measurement.

Also record wall-clock **time to first paint** by eye or by stopwatch — you need it in step 2
and it is the number the user is actually complaining about.

### 2. Attribute the number into four buckets — you cannot fix what you have not attributed

| Bucket | Instrument | What you read |
| --- | --- | --- |
| Process spawn + dynamic linking | `BOOT_MS` minus the tracing spans below | the remainder |
| Rust `Builder::build` + plugin init | `tauri/tracing`, span `app::build`, `app::core_plugins::register`, `app::plugin::register{name}` | per-plugin ms |
| Window + WebView creation, then your `setup()` closure | span `app::setup` (it covers **both**) | ms |
| Frontend first paint | webview devtools Performance panel / `performance.getEntriesByType('paint')` | ms after `Ready` |

Enable the spans exactly as in `references/performance.md` §8.1 — the whole trick is
`FmtSpan::CLOSE`, which prints each span's elapsed time. Run once, copy the four numbers into
a table, and check they roughly sum to your observed time to first paint.

Two attributions that end the investigation immediately:

- Spans sum to a small fraction of `BOOT_MS` (e.g. 90 ms of 2.4 s) → **the Rust layer is
  innocent.** Skip to step 6. This is a result, not a failure.
- `app::setup` alone dominates → step 3.

`app::setup` covers window construction *and* your closure, so split it by adding one
`tracing::info_span!` around your own `setup` body. Without that split you cannot tell "my
`setup` is slow" from "I create four windows at boot".

### 3. Blocking work in `setup()` — check this first, it is the usual answer

`setup()` runs on the main thread with the event loop **not yet pumping**
(`references/performance.md` §2.1). Every millisecond in it is a millisecond of blank window.

Read your `setup` closure and classify each statement into: *the first frame genuinely depends
on this* vs *everything else*. Network calls, database migrations, index builds, sidecar
spawns, model loading, and directory scans are all "everything else".

Move "everything else" out, per `references/performance.md` §2.6. The shipped shape to copy is
`case-studies.md` §10: restore geometry and show the window synchronously, then let optional
subsystems initialize and **log-and-continue on failure** rather than `?`-ing out of `setup`
(an error returned from `setup` aborts startup).

Re-run step 1 after this change alone. One change, one measurement.

### 4. Plugin `initialize()` cost

`app::plugin::register{name="…"}` gives you a per-plugin number directly. Plugins initialize
**synchronously, in registration order, before any window exists**, and each also costs a
second time as an injected initialization script the webview parses on every page load
(`references/performance.md` §2.1).

For the expensive one, in order of preference: drop it (does three lines of Rust do the job?),
replace its eager work with a lazily-initialized command, or move it behind
`app.handle().plugin(...)` at runtime (§2.6).

### 5. Eager windows

Each configured window with `create: true` costs one OS window plus one platform webview,
built **sequentially** on the pre-paint path. On Windows the first one additionally spawns the
whole WebView2 browser process group (`references/performance.md` §2.2), so window count is
the largest single lever there. Mechanism and the `create: false` migration:
`references/performance.md` §2.3.

If a splashscreen is on the table, price it as a second webview first —
`references/performance.md` §2.5.

### 6. Frontend first paint

If step 2 pointed here, this is ordinary web performance: bundle size, waterfall, blocking
imports, hydration. `clouds-f` owns it; this skill does not restate it. Two Tauri-specific
notes only: assets are brotli-decompressed at first touch (`references/performance.md` §2.1),
and devtools access in a built app is `references/debugging-and-testing.md` §devtools.

### 7. Only now, the white flash

`backgroundColor` and `visible: false` (`references/performance.md` §2.4) change *perceived*
startup, not measured startup. Doing this before steps 3–6 hides the regression from you
without fixing it for the user on a slow machine.

---

## Validation

1. Re-run **step 1 verbatim** — same build profile, same machine, same cold/warm procedure,
   same ≥ 3 runs, same median. A number from a different machine or a debug build proves
   nothing.
2. Report the before/after table with all five labels, both cold and warm. A warm-only
   improvement on a cold-start complaint is not a fix.
3. Re-run the step 2 span capture and confirm the bucket you targeted actually shrank. If total
   time dropped but your bucket did not, something else changed — find out what.
4. Confirm on the platform that reported the problem. Startup cost distribution differs per OS
   (`references/performance.md` §2.2); a Windows win does not transfer to macOS.

---

## Pitfalls

- **Optimizing an unattributed number.** The default failure of this whole exercise: a week
  spent on binary size for a startup complaint. Binary size and startup are only weakly
  related, and binary size and memory are not related at all
  (`references/performance.md` §1.2, §3).
- **Measuring `tauri dev`.** Dev serves assets over a dev server and runs a debug binary.
  Neither cold nor warm dev numbers predict the shipped app.
- **One run.** Cold start variance on a laptop is large. Median of ≥ 3, or do not quote it.
- **Deferring work into a spawned task that still blocks.** `std::thread::sleep` or blocking IO
  inside an async task starves the runtime and can freeze startup harder than the synchronous
  version did (`references/performance.md` §2.1, §7.2).
- **`visible: false` with no guaranteed `show()` path.** If the frontend throws before it calls
  `show()`, no window ever appears and the user sees nothing at all
  (`references/performance.md` §2.4).
- **Touching `additionalBrowserArgs` for startup.** It silently replaces wry's defaults,
  including a SmartScreen-related one, and can force a second data directory
  (`references/performance.md` §2.2, `references/cross-platform.md` §5). Not a startup lever.
- **Leaving the boot gate ungated.** It must be behind an env var and, ideally,
  `debug_assertions`; a self-exiting release binary is a support incident
  (`references/performance.md` §8.5 on choosing the gate).

---

## Escalate

Stop and ask rather than proceed when:

- Attribution says the cost is **process spawn / dynamic linking** — the remainder in step 2 is
  large and the spans are small. That is antivirus, code-signing verification, network-mounted
  binaries, or a slow disk on the user's machine, not something you fix in the app.
- Attribution says **WebView2 environment creation** on Windows and the app already creates
  exactly one window. There is no application-level lever left; the discussion becomes
  install-mode and runtime version (`references/cross-platform.md` §3).
- The only remaining win requires making `setup()` fallible-and-continue for a subsystem the
  product considers mandatory. That is a product decision about degraded startup, not a perf
  decision.
- Someone quotes a Tauri-vs-Electron startup figure at you. Those numbers are folklore with no
  first-party source (`references/performance.md` §1.3) — say so before agreeing to a target
  derived from them.

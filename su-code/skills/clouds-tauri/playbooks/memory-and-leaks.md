# Memory and leaks

**Objective** — decide whether the app leaks or merely costs what it costs, attribute the
growth to the Rust core process or to the WebView process group, and fix the one that is
actually growing.

**When to run this**

- "Memory grows over hours", "it's at 2 GB by the end of the day", "I have to restart it".
- RSS never comes back down after a large operation (import, stream, download, bulk render).
- Before shipping a long-running app: a tray app, an editor, anything users leave open.
- **Not** for "the app uses 300 MB at launch" — that is not a leak, it is a webview. Start at
  `references/performance.md` §4.1 and stop.

---

## Order

### 1. Measure first — a baseline and a growth curve, not a reading

**A single reading cannot distinguish "this app needs 300 MB" from "this app leaks."** A leak
is a *slope*. Before touching any code, produce the slope.

Use the per-OS command in `references/performance.md` §4.2 — it is copy-pasteable there and is
not repeated here. What this playbook adds is the protocol around it:

- **Record the right number.** Linux: `Pss` summed across the core process *and* every
  `WebKit*` helper (RSS double-counts shared pages). macOS: `footprint` phys_footprint, because
  that is the number Activity Monitor shows the user. Windows: both `PrivateMB` and
  `WorkingSetMB` for `your-app` **and** `msedgewebview2`, per process, not summed.
- **Fix the workload.** Write down a repeatable scenario — "open 3 documents, run 20 searches,
  idle" — and script it if you can. A curve from an unrepeatable session is not comparable to
  the curve you will take after the fix.
- **Sample at t = 0 (just after first paint), t = 5 min, t = 30 min, t = 2 h**, running the
  workload continuously. Four points, in a table, per process.
- **Take one restart control.** Restart the app, run the same workload for 5 minutes, sample.
  If the t=0..5min figures match the first run, growth is session-scoped (a leak). If the app
  starts high and stays flat, it is a cost, not a leak.

Release build. Debug allocations and debug-only instrumentation distort both the value and the
slope.

Record: workload, sample times, per-process numbers, machine, OS build, Tauri version.

### 2. Split native growth from WebView growth — the tooling is different

Read the curve per process, not in total:

| Growing | Layer | Continue at |
| --- | --- | --- |
| Your binary's process only | Rust core | steps 3–4 |
| `msedgewebview2` / `WebKit*` / `com.apple.WebKit.*` only | WebView | step 5 |
| Both | Two problems | do steps 3–4 first; Rust growth can pin webview-side objects, not vice versa |
| Neither, but total jumped | Process *count* | `references/performance.md` §4.1 — a second data directory or a second origin, not a leak |

This split is the whole reason step 1 measures per-process. Rust growth is answered with
`samply` / heap discipline / code reading; WebView growth is answered with devtools heap
snapshots. Applying one toolkit to the other layer is the standard wasted afternoon.

### 3. Rust-side growth: check the known Tauri leaks before profiling

In likelihood order. Mechanisms are all in `references/performance.md` §4.3 — read them there,
do not re-derive them.

1. **`ChannelDataIpcQueue`** (`references/performance.md` §4.3.1). The one nobody guesses.
   Trigger test: start a large `Channel` stream, navigate or reload the page mid-stream, watch
   core-process RSS. If it steps up and never returns — including after a successful retry —
   this is it. It is permanent for the process lifetime and additive per interrupted stream.
2. **Growing managed `State`.** Grep every `.manage(` for a collection type, then grep for
   inserts without a matching removal. Symptom: core RSS climbing linearly with session length,
   flat across restarts.
3. **Unbounded channels.** `unbounded_channel` with a consumer slower than its producer.
4. **Retained `AppHandle`s** in long-lived closures or stored *inside* managed state — a cycle
   that never drops.
5. **Rust-side `Listener::listen` without `unlisten`** — registered per window or per
   navigation.
6. **`Resource`s never `close`d** from the JS side.

Confirm the suspect before fixing it: instrument the size of the structure you suspect (log
`map.len()` on a timer, or expose it as a debug command) and check the count tracks the RSS
curve. A fix applied to an unconfirmed suspect leaves you unable to say whether it worked.

### 4. Listener and channel lifetimes

The two leak classes that are really lifetime bugs, and which present as *correctness* bugs
first:

- **JS listeners** — `listen()` returns a Promise of the unlisten function, and SPA route
  changes do **not** auto-unregister. The failure signature is a multiplier: a handler firing
  N times where N is how many times the user visited that route. Shape and the two official
  pitfalls: `references/performance.md` §4.4.
- **Channels** — a `Channel` whose Rust producer is not cancelled when the frontend goes away
  keeps producing, and (per step 3.1) can strand payloads. Ownership, cancellation, and the
  chunking rule are `references/ipc-and-commands.md` §Channels.

Audit method: grep the frontend for `listen(` and `once(` and check each has a cleanup path
tied to the component/route lifetime; grep the Rust side for `Channel<` and check each producer
observes a cancellation signal.

### 5. WebView-side growth

If step 2 pointed here, this is ordinary web memory work and `clouds-f` owns it: detached DOM
nodes, retained closures over large payloads, unbounded in-memory caches, non-virtualized
lists, image caches. Take a devtools heap snapshot at two points in the curve and compare
retainers — devtools access in a built app is `references/debugging-and-testing.md` §devtools.

Two Tauri-level levers exist and only two: the number of webviews you create
(`references/performance.md` §2.3) and whether they share a user data folder
(`references/performance.md` §4.1). Neither is a fix for a genuine web-side leak.

### 6. Re-measure before claiming anything

Go to Validation. A leak fix that has not reproduced the original curve and then flattened it
is a guess.

---

## Validation

1. Re-run **step 1 verbatim**: same workload, same four sample points, same release build, same
   machine. Put the two curves side by side.
2. The claim you are allowed to make is about the **slope**, not the peak. "Flat from t=30min
   to t=2h" is a fix. "Peak dropped 40 MB" with the same slope is not.
3. For a specific leak (step 3), add a targeted before/after: perform the triggering operation
   N times and show RSS returns to within noise of baseline each time. For
   `ChannelDataIpcQueue`, N interrupted streams must not produce N step-ups.
4. Run the restart control again. Session-scoped growth that survived the fix means you fixed a
   different leak than the one you measured.
5. State the platform. Allocator and webview reclamation behaviour differ per OS; a flat curve
   on macOS does not prove a flat curve on Windows.

---

## Pitfalls

- **"RSS went up, therefore we leak."** Wrong on every platform, for different reasons. Freed
  heap is not promptly returned to the OS by the allocator; WebKit and Chromium hold caches
  they release only under memory pressure; macOS `phys_footprint` counts compressed memory
  while `vmmap`'s `DIRTY` column does not. Growth that **plateaus** is a cost. Growth that is
  still linear at t=2h is a leak. Only the curve tells you which
  (`references/performance.md` §4.2).
- **Summing RSS across processes.** Shared Chromium/WebKit pages get counted once per process
  and your total becomes fiction. Use Pss on Linux; on Windows read per-process, not a sum.
- **Measuring a minimized or hidden window.** The webview may have been throttled or entirely
  unloaded after ~5 minutes hidden, which reclaims memory and makes a leak look fixed — and is
  macOS 14+/iOS 17+ only as a configurable policy
  (`references/performance.md` §4.5). Keep the window visible and foregrounded for the whole
  curve, or note that you did not.
- **Blaming the Rust binary because it is the one you can see.** It is typically the smallest
  process in the group (`references/performance.md` §4.1).
- **Fixing "unbounded" that was correct.** A per-window handle map in a three-window app is not
  a leak. Unbounded is fine when you can state the maximum from first principles — and the
  reasoning belongs in a comment, because the next reader cannot tell deliberate from
  accidental (`references/performance.md` §4.3).
- **Setting `backgroundThrottling: "disabled"` while investigating.** It forfeits the OS's
  memory reclamation, which changes the curve you are measuring.
- **Debug builds.** Different allocation behaviour, extra instrumentation, and `tauri/tracing`
  spans capture full IPC bodies (`references/performance.md` §8.1) — that is memory you added.

---

## Escalate

Stop and ask rather than proceed when:

- The curve is **flat** and the complaint is the absolute number. There is no leak to fix; the
  conversation is about how many windows and origins the product needs
  (`references/performance.md` §4.1), and that is a product decision.
- Growth is entirely in the WebView group and the frontend is owned by another team or skill.
  Hand off with the curve, the per-process split, and the heap snapshots — not with "Tauri uses
  a lot of memory".
- The fix for `ChannelDataIpcQueue` exposure requires threading a cancellation token through a
  producer you do not own (a plugin, a sidecar). The mitigation ladder and its costs are
  `references/performance.md` §4.3.1; picking a rung is a design call.
- A window's own data directory is the cause and that directory exists for isolation reasons.
  That is a security decision that costs memory, not a memory decision
  (`references/security.md`).
- You cannot reproduce the user's curve at all. Ask for their `tauri info` output, OS build,
  window count, and the workload — do not fix a leak you have never seen.

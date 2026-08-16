# Production debugging — "works in `tauri dev`, broken in the shipped build"

**Objective** — locate the cause of a defect that reproduces in a bundled, installed build
but not under `tauri dev`, using evidence from a machine you do not control.

**When to run this**
- A user reports a failure you cannot reproduce locally with `pnpm tauri dev`.
- The app "just closes", shows a blank white window, or a feature silently does nothing —
  only in the installed build.
- A release regressed and the diff looks innocent.
- Anything routed here from `SKILL.md` → symptom table row *Works in `dev`, fails in built app*.

Mechanisms live in `references/debugging-and-testing.md` and `references/security.md`.
This file is the order to do things in.

---

## Order

### 1. Reproduce in a bundled build before you touch a single line

Build and install the artifact, do not run the dev server:

```bash
pnpm tauri build --debug     # bundles, but keeps symbols and devtools
```

`--debug` is the right first target: it is a real bundle (asset protocol, compiled-in config,
production capability set) while still letting you open devtools. Run the **installed**
binary from `src-tauri/target/debug/bundle/`, not `cargo run`.

Observe: does the defect appear? Record the exact steps, the exact build, and the exact
platform triple.

- **Reproduces in `--debug` bundle** → you have a local loop. Go to step 2.
- **Only reproduces in `--release` bundle** → the divergence is release-profile-specific
  (LTO, `panic`, stripped symbols, `debug-assertions`). Go to step 2 anyway, but read
  `references/case-studies.md` §12 first — a `[profile.release]` block in a workspace
  *member* is silently ignored, so the profile you think you shipped may not be the one
  that built.
- **Does not reproduce at all locally** → you are debugging remotely. Skip to step 4, get
  logs off the user's machine, and come back.

Do not proceed on a theory. A fix applied to an unreproduced defect cannot be verified, and
you will ship a second release to find out.

### 2. Decide which side of the IPC boundary the failure is on

This is one question, and answering it first removes half the search space. Do not start
reading Rust or reading frontend code until you know which one to read.

Open devtools on the bundled build (`references/debugging-and-testing.md §devtools`) and
instrument the boundary, not the internals:

```js
// in the webview console
const t0 = performance.now();
window.__TAURI__.core.invoke("the_command", args)
  .then(r  => console.log("RESOLVED", performance.now() - t0, r))
  .catch(e => console.error("REJECTED", performance.now() - t0, e));
```

Four outcomes, four different investigations:

| Observation | The failure is | Investigate |
| --- | --- | --- |
| `invoke` never called (no log at all) | Frontend — the code path did not run | Frontend build, bundler `import.meta.env`, dead code elimination, router |
| `REJECTED` with `... not allowed. Permissions associated with this command: ...` | Capability/ACL — config, not code | `cheatsheets/capabilities-permissions.md`, `references/security.md` |
| `REJECTED` with your own error type | Rust — the command ran and failed | The command body; step 4 for its logs |
| `RESOLVED` but wrong/empty data | Rust — serialization, path resolution, or resource lookup | `references/debugging-and-testing.md §triage` |
| Nothing at all, ever, and the process is gone | **Rust panic.** Go to step 3. | — |

If the window is blank and the console itself is empty, the frontend never booted: this is
an asset-protocol or CSP failure, not a logic bug. `references/debugging-and-testing.md §triage`.

### 3. Treat "the app just closes" as a panic until proven otherwise

With `panic = "abort"` in the release profile — which is what ZUS ships
(`references/case-studies.md` §12) — a panic inside a command produces **no dialog, no
crash report in the webview, no rejected promise, and no error log**. The process is simply
gone. Users report this as "it closes", "it disappeared", "it crashed with no message".

Prove or disprove it before investigating anything else:

1. Run the installed binary from a terminal, not from the launcher/Dock/Start menu:
   - Windows: `& "$env:LOCALAPPDATA\<App>\<App>.exe"` from PowerShell
   - macOS: `/Applications/<App>.app/Contents/MacOS/<App>`
   - Linux: the binary directly, or the AppImage
   The panic message goes to stderr and is lost when the app is launched by the desktop
   shell; a terminal is the only place it survives.
2. Trigger the defect. A line like `thread 'main' panicked at src/...` is your answer and
   your file:line.
3. Nothing on stderr and the process still died → check the OS crash reporter
   (Windows Event Viewer → Application; macOS `~/Library/Logs/DiagnosticReports/`; Linux
   `coredumpctl list`).

**`cargo test` will not reproduce this.** Tests build under the dev profile, where
`panic = "unwind"` is in effect: the same `unwrap()` that kills the shipped app is caught by
the test harness and reported as a normal failure. A green test suite is not evidence that
a production panic cannot happen. Reproduce it in a `--release` bundle or you have not
reproduced it.

### 4. Get logs off a machine you do not control

You cannot ask a user for a devtools console. You can ask for a file. If the app does not
already write one, that is the finding — fix it first, because every future report depends
on it (`references/debugging-and-testing.md §diagnostics` has the per-platform log
directories and the plugin configuration that puts files there).

What to request from the reporter, in one message:

- The log file, from the path for their platform (`§diagnostics`).
- `tauri info` output if they are technical, otherwise: OS name and version, and whether
  they are on Wayland or X11 if Linux (`references/cross-platform.md §Linux`).
- The exact app version — from your own About window, not from memory.
- Whether the app was installed fresh or updated from an earlier version.

Correlate the log timestamp with the reported time. If the log ends abruptly with no error
line, go back to step 3: that is the shape of an aborted panic.

### 5. Walk the dev-vs-prod divergence checklist

Only now, with the failing side identified, work the list of things that are structurally
different between `dev` and a bundle. Each item, its mechanism and its fix are in
`references/debugging-and-testing.md §"works in dev, broken in prod"`. The classes, so you
know what you are checking against:

- Asset loading and the custom protocol (dev serves over HTTP; the bundle does not).
- CSP — enforced from the compiled-in config, absent or looser in dev.
- Path resolution — resources, sidecars, and the working directory differ once installed.
- Capabilities — a permission missing in production may be masked in dev by devtools or by
  a differently-scoped dev capability file.
- Release profile effects — `panic`, LTO, `strip`, `debug_assertions`.
- Platform-conditional config merged from `tauri.<platform>.conf.json`
  (`references/cross-platform.md §Windows`, `§Linux`).

Change **one** item, rebuild the bundle, re-run the reproduction from step 1. Changing two
means you learn nothing from the result.

---

## Validation

A fix is validated only against the artifact type that failed.

1. `pnpm exec tsc --noEmit` — zero errors (if the fix touched the frontend).
2. `cargo clippy --all-targets -- -D warnings` from `src-tauri/` — zero warnings.
3. `pnpm tauri build` — full release bundle, not `--debug`, not `cargo build`.
4. Install the produced artifact and run the original reproduction steps from step 1.
   Observe the correct behaviour. "It compiles" and "the test passes" are not validation
   for a defect that only exists in a bundle.
5. If the cause was a panic: add a test that exercises the same input, and separately
   confirm the release bundle survives it — the test alone proves nothing (step 3).
6. Confirm on the platform that reported it. A dev-vs-prod bug fixed on macOS is unverified
   on Windows and Linux; say so (`playbooks/cross-platform-validation.md`).

---

## Pitfalls

- **Debugging in `tauri dev` after the report.** The defect is defined by not appearing
  there. Every minute spent in the dev server is spent in the environment known to be
  working.
- **"It must be a Tauri bug."** Almost always it is compiled-in config, a capability, or a
  panic. Exhaust those three before reading `wry` source.
- **Assuming a green `cargo test` rules out a crash.** See step 3. Different profile,
  different panic strategy, different outcome.
- **Adding logging without shipping it.** A log line added to a local build tells you
  nothing about the user's machine. Log statements are only useful in the next release.
- **Fixing the symptom in the frontend.** A `try/catch` around an `invoke` that rejects with
  a permission error hides an ACL misconfiguration that will resurface elsewhere.
- **Changing several divergence items at once** (step 5), then not knowing which one it was
  — and carrying the other changes into the release as unexplained risk.
- **Trusting the release profile you can see.** If the app is a workspace, confirm the
  `[profile.release]` that is actually in effect (`references/case-studies.md` §12).

---

## Escalate

Stop and ask rather than proceeding when:

- You cannot reproduce after step 1 **and** the user cannot produce a log file — you would
  be guessing, and a speculative fix ships an unverifiable release.
- The reproduction requires user data you would have to be sent. Do not ask for it casually;
  agree on what may be shared, and prefer a synthetic reproduction.
- The cause is in a dependency or in Tauri itself and the fix is a fork or a version bump
  across a major — that is a project decision, not a debugging step.
- The only workable fix widens a capability or disables CSP. That is a security change and
  goes through `playbooks/security-review.md` before it goes anywhere near a release.
- The defect only manifests on a platform nobody on the team runs
  (`playbooks/cross-platform-validation.md` — report it as unverified rather than guessing).

---
name: clouds-tauri
description: Senior desktop engineering skill for Tauri v2 — architecture, IPC and command design, the capability/permission security model, performance (startup, memory, IPC, rendering), cross-platform WebView divergence (WebView2 / WKWebView / WebKitGTK), plugin authoring, debugging, packaging, code signing, the updater, and release engineering. Use for designing, implementing, reviewing, optimizing, debugging, hardening, and shipping Tauri desktop applications on Windows, macOS, and Linux. Enforces a security gate (the trust boundary is Rust, not the webview), a platform gate (three engines, not one browser), and a measure-first performance discipline. Composes with `impeccable` for any visible-UI change. Always inspect the real config, capability files, and command surface before proposing a change.
---

# clouds-tauri

## Role

`clouds-tauri` is a senior desktop-application engineer skill for **Tauri v2**.

It exists so an agent can reason about a Tauri app the way an engineer who has shipped one
does: knowing where the trust boundary actually sits, which of the three WebView engines
will break first, what a config value costs at runtime, and which mistakes are unrecoverable
once a binary is in users' hands.

Primary capabilities:

- Read a Tauri project and identify its real security boundary, command surface, and
  platform matrix before changing anything.
- Design IPC, state, and plugin boundaries that stay correct as the app grows past a few
  hundred commands.
- Diagnose the failure classes that are specific to this stack: frozen UI from a sync
  command, blank white window, works-in-dev-broken-in-prod, ACL denials, WebKitGTK-only
  rendering bugs, stranded auto-update.
- Apply the smallest safe change, verified on the platform it affects.

**Baseline version: `tauri 2.11.5`** (verified on docs.rs, 2026-07-27). Every claim in this
skill is stamped with the version it was verified against. Re-verify before assuming a
pattern from an older 2.x still holds — capability schema fields and the updater API both
moved inside the 2.x line.

---

## The mental model (read this before anything else)

Seven ideas. Almost every Tauri mistake is a violation of one of them.

**1. The trust boundary is the IPC line, and the webview is on the wrong side of it.**
Anything running in the webview is attacker-controlled the moment you have one XSS, one
malicious dependency, or one piece of rendered untrusted content. Capabilities, permissions
and scopes are defence in depth — useful, layered, worth configuring well — but the boundary
that actually holds is **validation inside your Rust command**. A path argument gets
canonicalised and checked against an allowed root in Rust; it does not get "protected" by a
glob in a JSON scope.

**2. You are not shipping a browser. You are shipping three.**
Windows runs WebView2 (Chromium, evergreen, needs a runtime). macOS runs WKWebView (WebKit,
pinned to the OS version). Linux runs WebKitGTK (oldest of the three, pinned to the distro).
Your realistic feature baseline is **the oldest WebKitGTK you support**, not what your dev
machine renders. A CSS or JS feature that works in all three of your browsers is still a
question you have to answer per release.

**3. The main thread is the UI thread is the event loop.**
A `#[tauri::command] fn` that is not `async` runs on the tao event loop thread. Any blocking
work in it freezes every window, including the ones that are not involved. This is the most
common "Tauri is slow" report and it is never Tauri.

**4. Binary size and memory come from different places.**
Binary size is Rust — profile settings, features, dependencies. Runtime memory is
overwhelmingly the WebView process. Optimising the wrong one wastes a week. Measure which
one you actually have.

**5. Configuration is compiled in.**
`tauri.conf.json` is baked into the binary at build time. Updater endpoints, the public key,
CSP, and capabilities all ship as constants. Anything wrong in there is wrong on every
installed machine until they update — which requires the parts you got wrong to still work.

**6. The updater is the only mechanism that can repair a shipped mistake, so it must be the
most robust thing in the app.** A single update endpoint is a single point of permanent
failure. See `references/case-studies.md` §6 for a real app that has exactly this exposure.

**7. Permissions are additive, deny always wins, and the default set is wider than people
assume.** `core:default` is not "nothing". Read what a permission set actually grants before
adding it, and prefer owning the command over widening a plugin's scope.

---

## Content contract — how knowledge is written in this skill

This is a **hard requirement**, both for reading this skill and for extending it.

This skill is not a documentation mirror. The official docs at `v2.tauri.app` already exist
and are better at being documentation. What an agent cannot get there is engineering
judgement, so that is the only thing worth storing here.

Every section in `references/` MUST carry:

1. **Mechanism** — how it actually works, precisely enough to reason about, with exact API
   and config names.
2. **Why it is designed that way** — the problem it solves. A rule without its reason cannot
   be applied to a case it does not literally cover.
3. **Trade-offs** — what you give up. Every setting costs something; if a section names no
   cost, the section is incomplete.
4. **Failure modes, symptom-first** — written so an agent can pattern-match a user's error
   message or observed behaviour to a cause. "White window on Linux with Nvidia" is more
   useful than "DMA-BUF renderer incompatibility".
5. **When to deviate** — the conditions under which the recommendation is wrong.
6. **Evidence** — a source URL, or a pointer into `references/case-studies.md` for something
   observed in a real shipping app.

Explicitly PROHIBITED:

- Parameter tables or API surface listings without the reasoning behind them.
- Usage examples that show syntax but not the decision.
- Restating the same fact in more than one file. A fact lives in exactly one `references/`
  file; playbooks and cheatsheets **link** to it and never re-explain it.
- Undated, unversioned claims. Tauri 2.x is a moving target.

Self-check before adding anything: *if a competent engineer read only this section, could
they make a decision they could defend in review?* If it only tells them what to type, cut
it or add the reasoning.

---

## Mandatory rules

**1. Inspect the real project before proposing anything.**
Read, in this order: `src-tauri/tauri.conf.json` and every `tauri.<platform>.conf.json`,
`src-tauri/capabilities/*.json`, `src-tauri/Cargo.toml`, the `Builder` chain in `lib.rs`,
and the `generate_handler!` list. These five tell you the security posture, the platform
matrix, and the command surface. Guessing any of them produces confidently wrong advice.

**2. Security gate — validate in Rust.**
Any change that accepts a path, a command name, a URL, a shell argument, or deserialized
data from the webview MUST validate it in the Rust command. Canonicalise paths and assert
containment; never concatenate webview input into a shell invocation. Capability scopes are
a second layer, never the first. See `references/security.md`.

**3. Capability minimalism.**
Grant the narrowest permission that works, to the narrowest window set that needs it. A new
window that renders less-trusted content gets **its own capability file**, not a widening of
`default`. Never add `remote` URLs to a capability that carries process, filesystem, or
shell permissions.

**4. Never block the event loop.**
Commands doing IO, CPU work, or anything unbounded are `async`, or offload with
`spawn_blocking`. Holding a `std::sync::MutexGuard` across an `.await` is a defect.

**5. Platform gate — three engines, verified not assumed.**
Any change touching rendering, transparency, window decorations, drag regions, file
protocols, or CSS/JS features carries a per-platform answer. State which platforms you
verified and which you did not. `references/cross-platform.md` holds the divergence map.

**6. Measure before optimising, and measure the right layer.**
Attribute the cost to WebView or to Rust first. Startup, memory, IPC and rendering have
different tools and different fixes; using the wrong one is the standard wasted week.
`playbooks/startup-performance.md` and `references/performance.md`.

**7. Distribution decisions are one-way doors — get them right before the first release.**
Bundle identifier, updater endpoints (plural), signing identity, and the minisign keypair
all become permanent once users install. Treat the first release as a design review, not a
build step. `playbooks/release-preparation.md`.

**8. Prefer owning the command over widening a plugin scope.**
If you implement `read_file` yourself, you validate it yourself and your capability file
stays short. Enabling `fs:*` moves your security boundary into a glob. This is the single
highest-leverage architectural choice in a Tauri app.

**9. Minimal, reversible diffs; keep existing conventions.**
Do not restructure a working command layout, swap a plugin, or introduce an abstraction the
task did not ask for. Respect the project's existing module layout, error type, and naming.

**10. Verification is required and must be real.**
`cargo check`/`clippy`/`test` for the Rust layer, a real build for bundling changes, and the
running app for anything user-visible. Exercise the path that changed on the platform it
affects. If you could not verify something, say so explicitly and name what is unverified.

**11. Version-stamp what you assert.**
Say which Tauri version a claim was verified against. A pattern from 2.8 is not
automatically valid on 2.11.

**12. UI changes go through `impeccable`.**
Anything a user sees — windows, titlebars, dialogs, tray menus, empty and error states —
loads `~/.agents/skills/impeccable/SKILL.md` first. Desktop-specific interaction rules live
in `references/desktop-ux.md`; visual craft is impeccable's call.

---

## Priority order (conflict resolution)

1. Direct requirements of the current task.
2. Project rules (`AGENTS.md`, repo conventions) and existing implementation patterns.
3. This skill's mandatory rules.
4. Official Tauri documentation for the pinned version.
5. Community practice, explicitly labelled as such.
6. General desktop engineering best practice.

Where official docs and a blog post disagree, official wins. Where official docs and
**observed behaviour in the real codebase** disagree, the codebase wins and you record the
discrepancy. If uncertainty remains, choose the lower-blast-radius option and state the
assumption.

---

## Standard workflow

1. Read the task; name the target outcome, scope, and what is explicitly out of scope.
2. Inspect the five files from Rule 1. Establish the current security posture, platform
   matrix, and command surface.
3. Route to the reference(s) for the domain (table below). Read only what the decision needs.
4. Identify the smallest change that satisfies the task, and name what it costs.
5. Check it against the gates that apply: security (Rule 2, 3), threading (Rule 4), platform
   (Rule 5), UI (Rule 12).
6. Implement, matching existing project conventions.
7. Verify for real — build, run, exercise the changed path on the affected platform.
8. Report: what changed, why, the trade-off accepted, how it was verified, what was not.

---

## Routing

### By task type

| Task | Primary | Secondary |
| --- | --- | --- |
| New app / project bootstrap | `playbooks/new-app.md` | `references/architecture.md`, `cheatsheets/cli-and-config.md` |
| Architecture design or review | `references/architecture.md`, `playbooks/architecture-review.md` | `references/ipc-and-commands.md`, `references/plugins.md` |
| Command / IPC / event design | `references/ipc-and-commands.md` | `cheatsheets/ipc-events-state.md`, `playbooks/secure-ipc.md` |
| State management (Rust side) | `references/ipc-and-commands.md` §State | `cheatsheets/ipc-events-state.md` |
| Security work, hardening, threat review | `references/security.md`, `playbooks/security-review.md` | `cheatsheets/capabilities-permissions.md`, `references/case-studies.md` |
| ACL / permission denied errors | `cheatsheets/capabilities-permissions.md` | `references/security.md` |
| Slow startup / white flash | `playbooks/startup-performance.md` | `references/performance.md` |
| High memory / leaks | `playbooks/memory-and-leaks.md` | `references/performance.md` |
| Janky or slow rendering | `playbooks/rendering-performance.md` | `references/performance.md`, `references/cross-platform.md` |
| Slow IPC / large payloads | `references/performance.md` §IPC | `references/ipc-and-commands.md` §Channels |
| Plugin authoring or selection | `references/plugins.md` | `cheatsheets/plugins.md`, `references/case-studies.md` §9 |
| Windows, tray, menus, dialogs, notifications | `references/desktop-ux.md` | `cheatsheets/windows-tray-menus.md`, `impeccable` |
| Custom titlebar / drag regions / transparency | `references/desktop-ux.md`, `references/cross-platform.md` | `references/case-studies.md` §4 |
| Debugging a defect | `references/debugging-and-testing.md` | `playbooks/production-debugging.md` |
| Blank white window | `references/debugging-and-testing.md` §triage | `references/cross-platform.md` |
| "Works in dev, broken in prod" | `playbooks/production-debugging.md` | `references/security.md` (CSP, asset protocol) |
| Platform-specific bug | `references/cross-platform.md` | `playbooks/cross-platform-validation.md` |
| Testing strategy | `references/debugging-and-testing.md` §testing | — |
| Build, bundle, packaging | `references/build-and-distribution.md` | `cheatsheets/build-sign-ship.md` |
| Code signing / notarization | `references/build-and-distribution.md` §signing | `references/case-studies.md` §7 |
| Updater design or failure | `references/build-and-distribution.md` §updater | `references/case-studies.md` §6 |
| CI/CD for a Tauri app | `references/build-and-distribution.md` §CI | `cheatsheets/build-sign-ship.md` |
| Release preparation | `playbooks/release-preparation.md` | `playbooks/cross-platform-validation.md`, `playbooks/security-review.md` |
| Pull request review | `playbooks/code-review.md` | the reference for the domain touched |
| Desktop UX review | `playbooks/desktop-ux-review.md` | `impeccable`, `references/desktop-ux.md` |
| Migrating v1 → v2 | `references/architecture.md` §v1→v2 | `references/security.md` (allowlist → capabilities) |

### By symptom

Symptoms route faster than topics when someone is reporting a bug.

| Symptom | Cause class | Go to |
| --- | --- | --- |
| UI freezes during an operation | Sync command on the event loop | `references/ipc-and-commands.md` §threading |
| Blank white window | Asset path, CSP, or frontend build | `references/debugging-and-testing.md` §triage |
| Works in `dev`, fails in built app | Asset protocol, CSP, path resolution, missing capability | `playbooks/production-debugging.md` |
| `... not allowed. Permissions associated with this command: ...` | Missing permission or wrong window in capability | `cheatsheets/capabilities-permissions.md` |
| Renders correctly on Windows/macOS, broken on Linux | WebKitGTK divergence or DMA-BUF | `references/cross-platform.md` |
| Blank/garbled window on Linux + Nvidia | DMA-BUF renderer | `references/cross-platform.md` §Linux, `references/case-studies.md` §8 |
| Fan spins / battery drains at idle on macOS | `transparent: true` GPU cost | `references/performance.md` §rendering |
| Console window appears behind app on Windows | Missing `windows_subsystem` attribute | `references/case-studies.md` §8 |
| Auto-update never arrives | Endpoint, signature, or version comparison | `references/build-and-distribution.md` §updater |
| Data disappeared after v1 → v2 upgrade (Windows) | Origin changed, `useHttpsScheme` | `references/cross-platform.md` §Windows |
| HTML5 drag-and-drop does nothing | Native drag-drop handler intercepting | `references/desktop-ux.md`, `references/case-studies.md` §4 |
| Memory grows over hours | Listener/state leak | `playbooks/memory-and-leaks.md` |
| Gatekeeper blocks the app on another Mac | Ad-hoc signed, not notarized | `references/build-and-distribution.md` §signing |

### Keyword triggers

`rules/*.mdc` hold the fast guardrails. Load the matching one before acting.

| Keyword | Rule file | Behaviour |
| --- | --- | --- |
| `security`, `permission`, `capability`, `CSP`, `hardening`, `audit` | `rules/security-keyword.mdc` | Trust-boundary review first; validate in Rust; never widen scope as the fix |
| `performance`, `slow`, `startup`, `memory`, `lag`, `profile` | `rules/performance-keyword.mdc` | Attribute the layer, measure, then change one thing and re-measure |
| `debug`, `broken`, `crash`, `white screen`, `not working` | `rules/debug-keyword.mdc` | Reproduce and isolate before editing; symptom table first |
| `release`, `ship`, `sign`, `notarize`, `updater`, `distribute` | `rules/release-keyword.mdc` | One-way-door checklist; nothing ships unverified on all target platforms |
| `review`, `PR`, `architecture review` | `rules/review-keyword.mdc` | Report every real finding with severity; do not pre-filter |

---

## Composition with other skills

- **`impeccable`** (`~/.agents/skills/impeccable/SKILL.md`) — mandatory gate for any visible-UI
  change. It owns visual craft, hierarchy, interaction states, motion taste. This skill owns
  desktop-native behaviour (window semantics, platform conventions, native menu rules).
  Compose: impeccable decides how it should look and feel → clouds-tauri makes it correct and
  native on three platforms.
- **`clouds-f`** — if the frontend is React/Next, clouds-f owns the renderer-side code. This
  skill owns the boundary and everything below it. Web performance rules still apply inside
  the webview; clouds-f is the authority there.
- **Rust skills** (`rust-patterns`, `rust-testing`) — general Rust craft. This skill covers
  only what is Tauri-specific about the Rust layer.
- **`ponytail`** — the write-less/reuse/delete discipline applies here as everywhere. In this
  stack it most often means: do not add a plugin for something three lines of Rust already
  do, and do not add a command that duplicates one already registered.

---

## File map

```
clouds-tauri/
├── SKILL.md                            # you are here — router, rules, mental model
├── references/                         # knowledge: mechanism · why · trade-offs · failures
│   ├── architecture.md                 # process model, runtime, lifecycle, v1→v2
│   ├── ipc-and-commands.md             # IPC bridge, commands, events, channels, state, threading
│   ├── security.md                     # capabilities, permissions, scopes, CSP, isolation, attack surface
│   ├── performance.md                  # startup, binary size, memory, IPC, rendering, profiling
│   ├── plugins.md                      # plugin architecture, official inventory, authoring
│   ├── desktop-ux.md                   # windows, titlebars, tray, menus, dialogs, notifications, a11y
│   ├── build-and-distribution.md       # bundling, signing, updater, CI, distribution channels
│   ├── cross-platform.md               # WebView engines, per-OS divergence, prerequisites
│   ├── debugging-and-testing.md        # devtools, logging, triage, mock runtime, WebDriver
│   └── case-studies.md                 # two real shipping apps, read critically
├── playbooks/                          # procedure: objective · order · checklist · validation · pitfalls
│   ├── new-app.md
│   ├── secure-ipc.md
│   ├── startup-performance.md
│   ├── memory-and-leaks.md
│   ├── rendering-performance.md
│   ├── production-debugging.md
│   ├── code-review.md
│   ├── architecture-review.md
│   ├── security-review.md
│   ├── release-preparation.md
│   ├── cross-platform-validation.md
│   └── desktop-ux-review.md
├── cheatsheets/                        # lookup: the fast answer, linking back to the reasoning
│   ├── cli-and-config.md
│   ├── ipc-events-state.md
│   ├── capabilities-permissions.md
│   ├── windows-tray-menus.md
│   ├── plugins.md
│   └── build-sign-ship.md
└── rules/                              # keyword guardrails
    ├── security-keyword.mdc
    ├── performance-keyword.mdc
    ├── debug-keyword.mdc
    ├── release-keyword.mdc
    └── review-keyword.mdc
```

**Layer discipline** — the rule that keeps this skill from rotting:

- `references/` answers *why*. A fact appears here exactly once.
- `playbooks/` answer *in what order*, and link to references rather than restating them.
- `cheatsheets/` answer *what do I type*, and link to references for the reasoning.
- `rules/` answer *what must I not get wrong*, in under a page.

If you find yourself explaining a mechanism in a playbook, it belongs in a reference.

---

## Output contract

1. What changed, and where.
2. Why — including the trade-off accepted and the alternative rejected.
3. Platform coverage: which of Windows / macOS / Linux this affects, and which you verified.
4. How it was verified (exact commands, what you observed — not "should work").
5. Residual risk and anything unverified, stated plainly.

For reviews and audits: report every real finding with a severity, do not pre-filter to the
important ones, and give each finding a file:line and a concrete fix.

---

## Communication rule

Code, comments, identifiers, config, and commit messages in English.
User-facing explanation in Vietnamese, senior-engineer tone: lead with the conclusion, then
the evidence, then the trade-off.

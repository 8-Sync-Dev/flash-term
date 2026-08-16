# New app — bootstrap a Tauri v2 app that will not need re-architecting

**Objective** — stand up a new Tauri v2 desktop app whose earliest decisions do not force a
rewrite, a re-signing, or an abandoned install base six months later.

**When to run this** — greenfield `create-tauri-app`; wrapping an existing web frontend in a
desktop shell; promoting a prototype to a product; auditing an app someone else scaffolded
(steps 3–9 work unchanged as a review checklist).

---

## One-way doors — settle these before step 1

Four decisions become permanent the moment a user installs. Everything else here is reversible.

| Door | Locked by | Cost of getting it wrong |
| --- | --- | --- |
| **Bundle identifier** | First install | Windows/macOS treat a changed identifier as a different app: parallel install, new appdata dir, orphaned users. Also feeds `bundle.windows.wix.upgradeCode` — `references/build-and-distribution.md` §Windows packaging |
| **Signing identity** | First signed release | SmartScreen reputation accrues **per certificate**; switching resets it to zero. `references/build-and-distribution.md` §signing |
| **Updater minisign keypair** | First shipped binary | `pubkey` is compiled in. Losing the private key strands every install permanently; rotation only works *forward*, through an update old clients can still verify — `references/build-and-distribution.md` §update security |
| **`panic` strategy** | Your crash-reporting design | `panic = "abort"` turns a command panic into silent process death — no unwind, no report. `cargo test` runs the dev profile and never surfaces it. ZUS ships `abort`, Jan `unwind` — `references/case-studies.md` §12 |

Generate the keypair now, before the first build, and put the private key in the CI secret store
the same day: `cargo tauri signer generate -w ~/.tauri/<app>.key`.

---

## Order

**1. Install prerequisites on every OS you will ship, not just yours.**
Exact package lists: `references/cross-platform.md` §10 Build prerequisites. On Linux this means
**WebKitGTK 4.1** (libsoup3); a 4.0 dev package fails as a link error that reads like a Rust bug.
Observe: `cargo tauri info` prints a version on every OS row, no `Not installed`.

**2. Choose the scaffold, and know what it decided for you.**
`pnpm create tauri-app` (or `cargo create-tauri-app`) — it wires the lib target, the CLI, and a
working `tauri.conf.json`. Prefer the **vanilla/TS** template unless the product needs a
framework: the template's framework is the hardest thing to remove later, and the frontend is the
layer most likely to be replaced. ZUS runs ~250 commands against vanilla TS, Jan runs React
(`references/case-studies.md` §11). Neither is wrong; choosing by accident is.

**3. Decide the workspace layout before the first `cargo build`, and put `[profile.release]` in
the workspace root in the same commit.**
Layout: `references/architecture.md` §Project and workspace structure. The moment a Cargo
workspace exists, this trap is live:

```toml
# <repo root>/Cargo.toml — the ONLY place Cargo reads profiles
[workspace]
members = ["src-tauri", "crates/*"]

[profile.release]
opt-level = 3          # or "z" — a product decision, case-studies §12
lto       = "thin"
panic     = "abort"    # one-way door, see table above
```

A `[profile.release]` block in `src-tauri/Cargo.toml` — a workspace **member** — is **silently
ignored**. No warning, no error, and you ship a binary built with defaults you never chose. ZUS
has both blocks and only the root one is live (`references/case-studies.md` §12). Write the root
block on day one; a member block added later looks correct and is the hardest performance defect
in this stack to catch by reading.
Observe: `cargo build --release -v 2>&1` shows your `opt-level` on the app crate's `rustc` line.

**4. Fix the `tauri.conf.json` values that are expensive to reverse.**
This file is **compiled into the binary** (`references/architecture.md` §Configuration
architecture), so "change it later" means "next release, if the updater still works".

- `identifier` — reverse-DNS, final.
- `productName` — drives binary name, install directory, macOS `.app` name.
- `app.windows[0]` — set `width`/`height`/`minWidth`/`minHeight` deliberately and decide
  `decorations` now; a custom titlebar is a three-platform config split, not a CSS choice
  (`references/desktop-ux.md` §menus, `references/case-studies.md` §4).
- `app.security.csp` — write a restrictive string **at scaffold time**. `null` disables CSP
  entirely, and a policy added later is whichever one does not break a frontend that grew without
  it. Posture comparison: `references/case-studies.md` §1; mechanism: `references/security.md`.
- Split platform-specific keys into `tauri.windows.conf.json` / `.macos.` / `.linux.` from the
  start — arrays **replace** rather than merge under RFC 7396
  (`references/architecture.md` §Configuration architecture).

**5. Start capabilities at default-deny.**
`src-tauri/capabilities/default.json` with `"windows": ["main"]` and an **empty** `permissions`
array; add identifiers one at a time as a command actually fails. Do not start from
`core:default` and subtract — it expands to nine module defaults and is wider than it reads
(`references/security.md` §permissions). Any window rendering less-trusted content gets its own
capability file, never a widening of `default`.
Observe: under `pnpm tauri dev`, each ACL error names the exact missing identifier
(`cheatsheets/capabilities-permissions.md`).

**6. Write the first command correctly — every later command is a copy of it.**

```rust
#[tauri::command]
async fn load_project(state: State<'_, AppState>, id: String) -> Result<Project, AppError> {
    project::load(&state.db, &id).await          // logic lives outside the command body
}
```

Three load-bearing properties: **`async`** (a sync command runs on the tao event loop and freezes
every window — `references/ipc-and-commands.md` §Threading); **`Result<T, E>`** with a
`Serialize` error (an async command borrowing `State<'_, _>` is *required* to return `Result` —
same section); and **no logic in the body**, so the work is unit-testable without a `tauri::App`
(`references/debugging-and-testing.md` §testing).

**7. Wire logging before you need it.**
`tauri-plugin-log` in the same commit as the first command, with a file target and a stdout
target, logging the `setup` milestones. Retrofitting logs happens during an outage, on a machine
you cannot reach. `references/debugging-and-testing.md` §diagnostics.
Observe: run the app, then find the log file at the platform app-log dir.

**8. Put CI on all three platforms in the first week.**
`tauri-apps/tauri-action@v1` across `windows-latest` / `macos-latest` / `ubuntu-22.04`, running
`cargo clippy -- -D warnings`, `cargo test`, and a real `tauri build`
(`references/build-and-distribution.md` §CI). Introducing this after three months of Windows-only
development means debugging a Linux build and a macOS signing setup simultaneously, under release
pressure. Add `TAURI_SIGNING_PRIVATE_KEY` as a secret in the same PR even if the updater is off.

**9. Pin the Tauri version and record it.**
`tauri` and `tauri-build` move within 2.x. The runtime crate is also your CVE surface:
`CVE-2026-42184` / `GHSA-7gmj-67g7-phm9` is fixed in **`tauri` 2.11.1**, and exposure tracks the
**`tauri` runtime crate**, not `tauri-build` (`references/security.md` §advisories).

---

## Validation

- `cargo tauri info` — no missing prerequisites on each target OS.
- `cargo build --release -v 2>&1` — your root-workspace `opt-level`/`lto` reach the app crate. If
  not, the profile block is in a member.
- `cargo clippy --all-targets -- -D warnings` — zero warnings.
- `pnpm tauri dev` — window opens, first command round-trips, every ACL denial in the console is
  a permission you deliberately withheld.
- `pnpm tauri build` on **each** platform via CI — three installers produced.
- Install the artifact on a clean machine or VM and launch it. Dev success is not build success
  (`references/debugging-and-testing.md` §"works in dev, broken in prod").
- Keypair exists, private key is in the CI secret store, `pubkey` is in `tauri.conf.json`, both
  backed up somewhere that survives losing your laptop.

---

## Pitfalls

- **`[profile.release]` in `src-tauri/Cargo.toml`.** Silent no-op; the whole point of step 3.
- **Scaffolding with `csp: null` "for now".** The policy that eventually ships is the one that
  breaks nothing — i.e. none.
- **Starting from `core:default` because the app needs "the basics".** You inherit nine module
  defaults you never read.
- **A sync first command because it is "fast".** It gets copied fifty times and one copy does IO.
- **Deferring the keypair to "release prep".** Pre-release builds get shared; those are installs.
- **A single updater endpoint.** One endpoint is a single point of *permanent* failure, because
  the list is compiled in — configure a fallback array on day one
  (`references/build-and-distribution.md` §update security, `references/case-studies.md` §6).
- **A plugin for something three lines of Rust already do.** Owning the command keeps the
  validation and the capability file yours (SKILL.md rule 8).
- **Developing against your own WebView only.** Your feature floor is the oldest WebKitGTK you
  support (`references/cross-platform.md` §Linux).

---

## Escalate — ask rather than guess

- **The bundle identifier**, if this app replaces or coexists with a shipped product. Wrong here
  orphans the install base and there is no migration.
- **Who holds the signing certificate and the minisign private key, and where the backup lives.**
  Organisational answer, must exist before release.
- **The supported OS floor** (oldest Windows / macOS / Linux distro) — it sets the WebView feature
  baseline and cannot be derived from the code.
- **Whether mobile is ever in scope**, and **`opt-level = 3` vs `"z"`** if binary size is a stated
  product constraint. Both are product trade-offs with no default answer.

# Architecture review — will this shape survive the next year

**Objective** — judge the *structure* of a Tauri app: where the boundaries are, whether they
are real, and which of them will break first as the app grows. Not defects — shape.

**When to run this** — before a large feature lands, when the command count crosses ~50, when
someone proposes a new crate/plugin/window, at a v1→v2 migration, or when a PR review keeps
producing the same class of finding (that is a structural cause, not a code one).

**Scope** — no line-level defects; those are `playbooks/code-review.md`. No trust-boundary
enumeration; that is `playbooks/security-review.md`. This playbook asks eight structural
questions and expects an answer with evidence for each.

## Review rules (shared by all four review playbooks)

- Report **every** real finding with a severity — `Critical` / `High` / `Medium` / `Low`.
  Do not pre-filter.
- Every finding carries a **`file:line`** and a **concrete fix** (the module to extract, the
  profile block to move, the type to introduce), not a concern.
- **Read the code before claiming behaviour.** A finding you did not verify is a question —
  list it separately as one.
- **State which platforms you verified.** An unverified platform is itself a finding, and
  structure fails per-platform more often than people expect (mobile lib target, platform
  overlays).

Report in the shape of `SKILL.md` §Output contract.

---

## Order

**1. Measure before you opine.**

```bash
rg -c '#\[tauri::command\]' src-tauri/src | sort -t: -k2 -n -r
rg -n 'generate_handler!' -A400 src-tauri/src/lib.rs | rg -c '^\s+[a-z_:]+,'
rg -n '^\[workspace\]' -A30 Cargo.toml
rg -n '\.manage\(|\.plugin\(' src-tauri/src/lib.rs
tokei src-tauri/src   # or: rg --files src-tauri/src | wc -l
```

Write down five numbers: commands registered, files declaring commands, workspace members,
`manage()` calls, plugins registered. These are the review's axes. For calibration: ZUS runs
~250 commands across 24 workspace crates in one `generate_handler!`; Jan runs a much smaller
surface with 5 in-tree plugins (`references/case-studies.md` §11). Both are defensible. A
250-command app in **one crate** is not.

**2. Where is the security boundary — Rust, or a JSON glob?**

Count the two populations:

```bash
rg -n '"permissions"' -A60 src-tauri/capabilities/*.json | rg -n '"(fs|shell|http|process):'
rg -n 'fn ' src-tauri/src/commands/ | wc -l
```

The structural question: for each privileged capability the app has (read a file, run a
process, hit a URL), is it reached through **your own command that validates in Rust**, or
through a plugin permission whose safety is a glob in JSON? An app whose filesystem access is
`fs:default` + a scope array has put its security boundary in a config file that no test
exercises and no reviewer reads carefully. `High`, and the fix is the highest-leverage change
available in a Tauri app (`SKILL.md` Rule 8; mechanism in `references/security.md`).

Evidence to cite: the capability file line granting the plugin permission, and the absence of a
corresponding owned command.

**3. Is the business logic inside `#[tauri::command]` bodies?**

Pick the three largest command functions from step 1 and read them. The test is mechanical:
**can this logic be exercised by `cargo test` with no `App`, no `AppHandle`, no `State`?**

If the answer is no, the app's core logic is only reachable through the IPC bridge, which means
it is only testable through a running WebView, which means it is not tested
(`references/debugging-and-testing.md` §testing).

Fix, stated concretely per site: extract the body into a plain function or an inherent method
on a domain type taking ordinary arguments; leave the `#[tauri::command]` as a five-line
adapter that resolves `State`/`AppHandle`, calls it, and maps the error. Severity `High` when
the extracted logic would be non-trivial, `Medium` for thin CRUD.

**4. Does the workspace layout support growth?**

Check against `references/architecture.md` §Project and workspace structure:

- Is there a **lib target** (`crate-type = ["staticlib", "cdylib", "rlib"]`) with `run()` in
  `lib.rs`, and a `main.rs` that only calls it? Missing → `High` (blocks mobile entirely, and
  makes the whole app untestable as a library).
- Are commands split into modules by domain, with one `mod` per feature area, or is there one
  4000-line `commands.rs`? One giant module → `Medium`.
- Do domain crates depend on `tauri`? A `crates/db` that imports `tauri` to return
  `tauri::Error` has fused the domain to the framework — `High`. Fix: domain crates own their
  error type; the `src-tauri` crate does the `From` conversion.
- Is the dependency direction acyclic and one-way (app → domain crates → shared)? Cycles
  through a "common" crate that imports back are `Medium`.

**5. Is `[profile.release]` alive or dead?**

```bash
rg -n '\[profile\.release\]' -A12 Cargo.toml src-tauri/Cargo.toml crates/*/Cargo.toml
```

A `[profile.release]` block in a workspace **member** is silently ignored by Cargo — only the
workspace root counts (`references/case-studies.md` §12). This produces no warning, and the
team believes they shipped LTO and `opt-level` tuning they did not. `High`, fix is a move, not
an edit. While there, confirm the `panic` setting is a deliberate decision and that the team
knows what it does to a panicking command (`playbooks/code-review.md` step 4).

**6. Is state ownership clear, or scattered?**

```bash
rg -n '\.manage\(' src-tauri/src
rg -c 'AppHandle' src-tauri/src | sort -t: -k2 -n -r | head -20
rg -n 'app_handle\(\)|\.state::<' src-tauri/src
```

Managed state is **type-keyed, one value per type** (`references/ipc-and-commands.md` §State).
Findings to look for:

- `manage()` of a bare primitive or a `Vec<T>`/`HashMap<..>` → `Medium`. A second feature
  wanting the same type silently replaces or collides. Fix: newtype per concern.
- `AppHandle` threaded into deep domain code purely to reach `state::<T>()` → `High`. That is
  a hidden global; the domain layer now cannot be constructed in a test. Fix: pass the
  dependency, resolve it once at the command adapter (`references/architecture.md`
  §AppHandle semantics).
- State mutated from both a command and a background task with no single owner → `High`.
  Fix: one owning task plus a channel, or document the lock order.

**7. Is the plugin boundary real or decorative?**

For each in-tree plugin (Jan ships 5 — `references/case-studies.md` §9), ask: does it have a
**permission surface, its own capability contribution, and a consumer other than this app**?
A plugin that exists only to namespace one team's commands, with all permissions granted by
`default`, is ceremony: it adds a build step, a permission-generation step, and an extra crate
boundary for zero isolation. `Medium`, fix is to demote it to a module —
`references/plugins.md` for the criteria that make a plugin worth its cost.

The inverse finding: a feature that *should* be a plugin (needs mobile platform code, needs
its own permissions, is reused by a second binary) implemented as inline commands. Also
`Medium`.

**8. Who orchestrates — Rust or the frontend?**

Trace one real workflow end to end (the most important one). Count the invoke round trips. A
frontend that calls six commands in sequence to complete one user action has put the workflow
in the least trustworthy, least testable layer, and pays six IPC crossings
(`references/performance.md` §IPC). `Medium`, escalating to `High` if any step is a security
decision. Fix: one command that owns the workflow and emits progress on a `Channel`
(`references/ipc-and-commands.md` §Channels).

**9. Config architecture.**

Confirm platform overlays exist where behaviour genuinely differs (`tauri.windows.conf.json`
etc.) and that nobody is branching on `cfg!(target_os)` in Rust to patch a value that belongs
in an overlay. Confirm the team can name which settings are compiled in and therefore
unfixable without a release — `references/architecture.md` §Configuration architecture. An app
with a single updater endpoint is a permanent single point of failure and belongs in this
report even though it is a distribution concern (`references/case-studies.md` §6).

## Validation

An architecture review's validation is that its findings are **checkable**, not that the build
passes. Still, produce:

```bash
cargo tree --workspace --depth 1        # confirm the dependency direction you claimed
cargo test --workspace                  # confirm step 3's claim: what is actually covered
cargo build --release                   # confirm step 5's profile is the one that applies
```

For step 5, prove it: compare `ls -l target/release/<binary>` before and after moving the
profile block to the workspace root. A size change is the evidence; no change means the block
was already effective and the finding is withdrawn.

For step 3, prove the extraction is possible on one function before recommending it for
twenty.

## Pitfalls

- **Recommending a rewrite.** Every finding must be an incremental move. If a fix cannot be
  landed in one PR, split it and say what the first PR is.
- **Counting commands as the health metric.** 250 commands in a well-split workspace is fine;
  40 in one file with logic inline is worse.
- **Calling a working layout wrong because it is unfamiliar.** Two shipping apps use two
  different shapes and both are defensible. The question is whether the structure supports the
  *next* thing, not whether it matches a template.
- **Assuming the profile block you found is the one in use** — check the workspace root.
- **Ignoring the frontend's structure.** If the frontend owns the workflows, the Rust layout
  cannot be judged in isolation.

## Escalate

- The review's conclusion is "the security boundary is in JSON" → stop and run
  `playbooks/security-review.md`; that finding needs enumeration, not a structural note.
- A proposed change would alter the bundle identifier, the updater endpoints, or the signing
  identity → one-way door, `playbooks/release-preparation.md` and a human decision.
- The app is mid-migration from v1 and the structure is half-converted → read
  `references/architecture.md` §v1→v2 and review against the *target* shape, or the review
  will file findings the migration already plans to fix.
- You cannot establish the dependency direction because the workspace does not build. Fix the
  build or stop; a structural claim about code you could not compile is a question.

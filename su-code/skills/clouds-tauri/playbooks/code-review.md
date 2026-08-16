# Code review — a Tauri diff

**Objective** — find the defects in a changed diff that a competent general Rust/TS reviewer
walks straight past because they are properties of the Tauri runtime, not of the code.

**When to run this** — any PR touching `src-tauri/`, `capabilities/`, `tauri.conf.json`, or the
frontend's `invoke`/`listen` calls. Also before merging your own work.

**Scope** — this playbook reviews a *diff*, at defect level. Whole-system shape is
`playbooks/architecture-review.md`; trust boundary is `playbooks/security-review.md`.

## Review rules (shared by all four review playbooks)

- Report **every** real finding with a severity — `Critical` / `High` / `Medium` / `Low`.
  Do not pre-filter to the important ones; the requester decides what to fix.
- Every finding carries a **`file:line`** and a **concrete fix** (the replacement, the config
  value, the function to call), not a concern.
- **Read the code before claiming behaviour.** A finding you did not verify is a *question*.
  File it as one, in a separate list, so nobody spends a day on your guess.
- **State which platforms you verified.** An unverified platform is itself a finding.

Report in the shape of `SKILL.md` §Output contract.

---

## Order

**1. Get the diff and the profile in the same breath.**

```bash
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- src-tauri/ > /tmp/rust.diff
```

Then read the **workspace root** `Cargo.toml` for `[profile.release]`. You need one value
before anything else: `panic`. A member-crate profile block is silently ignored
(`references/case-studies.md` §12) — if the `[profile.release]` you found is in
`src-tauri/Cargo.toml` and that crate is a workspace *member*, the block is dead and the real
profile is Cargo's default (`panic = "unwind"`). Note which it is; step 3's severity depends
on it. ZUS ships `panic = "abort"`, Jan ships `panic = "unwind"` — both are real, and they
make the same `unwrap()` a different bug.

**2. Rebuild the command surface delta.**

List commands added, removed, or changed in this diff:

```bash
rg -n '#\[tauri::command' src-tauri/ 
git diff origin/main...HEAD | rg -n '^\+.*(generate_handler|tauri::command)'
```

Every entry that is new in `generate_handler!` is a new hole in the IPC boundary and gets the
full treatment in steps 3–7. A command removed from the handler but still called by the
frontend is a `High` (runtime rejection, no compile error) — grep the frontend for its name.

**3. Threading pass — sync commands that should be async.**

```bash
rg -n -A2 '#\[tauri::command\]' src-tauri/src | rg -n 'fn ' | rg -v 'async fn'
```

Every hit is a candidate. Read the body. If it does file IO, network, a `std::process`
spawn, a lock that another thread can hold, a database call, or any unbounded loop, it is a
defect: it runs on the tao event loop thread and freezes **every** window, not just its own
(`references/ipc-and-commands.md` §Threading). Severity `High`; `Critical` if the operation
is user-triggerable and can take seconds.

Fix: make it `async fn`. If the work is blocking-by-nature (sync IO, CPU), keep it `async` and
wrap the body in `tauri::async_runtime::spawn_blocking`. Note the borrow restriction on async
commands (`§Threading`) — the fix may force a `Result` return; that is expected, not a reason
to leave it sync.

A sync command that only reads a config field or returns a constant is fine. Say so; do not
file it.

**4. Panic pass — the profile decides the blast radius.**

Search every path reachable from a command, including helpers it calls:

```bash
rg -n '\.unwrap\(\)|\.expect\(|\[[0-9]+\]|panic!\(|unreachable!\(|todo!\(' src-tauri/src
```

Filter to code reachable from `generate_handler!`. Also flag: slice indexing on
webview-supplied indices, `as` casts that can wrap, integer division by a webview-supplied
value, and `RefCell::borrow_mut` on a shared path.

Severity depends on step 1:
- `panic = "abort"` → **`Critical`**. A panicking command does not reject the invoke promise;
  it kills the process. No error dialog, no log line, no crash report unless you installed one.
  `cargo test` will not catch it: tests run under the **dev** profile, which is `unwind`.
- `panic = "unwind"` → `High`. The invoke rejects and the app survives, but the error the
  frontend sees is useless.

Fix in both cases: return `Result<T, E>` and propagate with `?`. `expect()` is acceptable only
on an invariant established earlier *in the same function*, and the message must state the
invariant.

**5. Lock discipline.**

```bash
rg -n -B3 -A8 '\.lock\(\)|\.read\(\)|\.write\(\)' src-tauri/src
```

Two findings to look for. (a) A `std::sync::MutexGuard` alive across an `.await` — `High`,
and see `references/ipc-and-commands.md` §State for the two symptom forms (it may compile).
Fix: scope the guard in a block that ends before the `await`, or move to
`tokio::sync::Mutex` **only** if the critical section genuinely must span the await.
(b) Two locks taken in different orders in two commands — `High`, deadlock.

**6. Channels and listeners.**

- An unbounded channel (`mpsc::unbounded_channel`, `crossbeam::unbounded`) fed from a producer
  faster than the webview drains it → `High`, unbounded memory. Fix: bounded channel plus a
  documented drop or backpressure policy.
- A `Channel<T>` or `listen` registered per invocation without a matching teardown → `High`.
  Every `listen` needs an `unlisten`/`once`, and every frontend `listen` needs its unsubscribe
  called on unmount. Check the frontend side of the diff too.
- `emit` in a hot loop with no coalescing → `Medium` (`references/performance.md` §IPC).

**7. Arguments that came from the webview.**

For each new or changed command, classify every parameter: does it originate in the webview?
If yes and it is a path, a command name, a URL, an SQL fragment, or a shell argument, the
command must validate it **in Rust** — canonicalise and assert containment for paths, allowlist
for command names and schemes. A capability scope in JSON is not the validation
(`references/security.md`). Missing validation is `Critical`.

Also flag a command that takes a *whole struct* deserialized from the webview and passes it to
a privileged API without field-level checks.

**8. Capability and config diff — was a permission added to silence an error?**

```bash
git diff origin/main...HEAD -- src-tauri/capabilities/ src-tauri/tauri.conf.json
```

Any added permission needs a stated reason in the PR. The pattern to catch: a command failed
with `... not allowed. Permissions associated with this command: ...`, and the fix was to add
the broad default set (`fs:default`, `shell:allow-execute`, a widened `assetProtocol.scope`)
rather than the one narrow permission. `High`, and the fix is usually to own the command
instead of widening the plugin (`SKILL.md` Rule 8). A `remote.urls` entry added to a
capability that also carries fs/shell/process permissions is `Critical`.

Changed `tauri.conf.json` values that are compiled in (updater endpoints, CSP, identifier,
public key) get flagged as one-way doors even when the value looks right —
`references/architecture.md` §Configuration architecture.

**9. Error surface.**

Command errors cross serde (`references/ipc-and-commands.md` §Scale for the shape at size).
Flag: `Result<_, String>` built by `format!("{e}")` that leaks absolute paths, tokens, or
internal hostnames into the webview (`Medium`, `High` if the app renders untrusted content);
and a new error variant that is not `Serialize` (it will not compile, but the fix chosen
matters — check they did not switch to `.unwrap()`).

## Validation

Run these and paste real output into the review, not "should pass":

```bash
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
pnpm exec tsc --noEmit          # or the project's typecheck script
cargo tauri build --debug       # only if the diff touched config, capabilities, or bundling
```

Then run the app and exercise the changed commands. For step 3 findings the observable proof
is specific: trigger the command and confirm the window still repaints (drag it, hover a
button) while it runs. For step 4 findings under `panic = "abort"`, feed the command the input
that panics and confirm the process survives after the fix.

## Pitfalls

- **Reviewing the Rust diff only.** A command signature change is a frontend break with no
  compile error. Grep the frontend for the command name every time.
- **Assuming `cargo test` covers panics.** It does not under `panic = "abort"`: tests build
  with the dev profile.
- **Trusting a `[profile.release]` block without checking it is in the workspace root.**
- **Filing "consider making this async" without reading the body.** Half of sync commands are
  correct. An unread finding is a question.
- **Reviewing capabilities as a config diff.** They are a security diff; if more than one
  permission moved, stop and run `playbooks/security-review.md` instead of guessing.
- **Letting a large mechanical diff hide two real changes.** Split the diff by directory and
  review the small hand-written parts first.

## Escalate

Stop and ask rather than approving when:

- The diff adds a new capability file, a `remote.urls` entry, or changes CSP — that needs
  `playbooks/security-review.md`, not a line comment.
- The command count crossed a structural threshold and `generate_handler!` is now unreadable —
  that is `playbooks/architecture-review.md`.
- You cannot determine whether an argument is webview-supplied without reading the whole
  frontend. Ask the author; do not guess the trust boundary.
- The change is user-visible and no platform was verified. Say which platforms are unverified
  and require them before merge.

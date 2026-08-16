# Secure IPC — add a command without widening the attack surface

**Objective** — expose one native capability to the frontend such that the app's blast radius
does not grow. This is the playbook to run whenever the task is "add a command that does X".

**When to run this** — any new `#[tauri::command]`; any change to an existing command's signature;
adding a plugin permission to a capability file; any code review of a diff that touches
`generate_handler!`, `src-tauri/capabilities/`, or `src-tauri/permissions/`.

---

## The framing that decides everything below

An AI app renders model output. Model output is **attacker-controlled text** — it is produced from
retrieved documents, tool results, pasted content, and user input the attacker may also control.
Rendered attacker-controlled text is executing inside the same webview as your invoke bridge.

**Therefore: any command reachable from a rendered page is reachable from prompt injection.**

You do not need an XSS. You need one poisoned document in the context window. §2 Threat model in
`references/security.md` spells out why this collapses the usual "webview is
mostly trusted" assumption. Every step below exists to make one command survive that fact.

---

## Order

**1. Decide whether it needs to be a command at all.**
Ask, in this order:

- Can the frontend do it without native access? Then do not add a command.
- Does an already-registered command do it? Adding a second, slightly-different one doubles the
  surface for one caller's convenience.
- Does the work need to *cross* the boundary, or does it need to *happen*? Work triggered by a
  timer, a file watcher, or the `setup` hook has **no** IPC surface at all — that is strictly
  safer than a command that the webview can call whenever it likes.
- If a plugin would cover it: prefer **owning the command** over enabling the plugin's permission
  set. `fs:allow-read-file` moves your security boundary into a JSON glob; your own
  `read_project_file` keeps it in Rust where you can enforce it (SKILL.md rule 8).

The best outcome of this step is not adding the command.

**2. Define the narrowest signature that does the job.**
The signature is the attack surface. Shrink it before writing a body.

- Pass an **identifier the backend can resolve**, not a path the frontend chose:
  `read_project_file(project_id: Uuid, relative: String)` beats `read_file(path: String)`.
- Pass an **enum**, not a string, wherever the set of valid values is finite. A
  `#[derive(Deserialize)] enum ExportFormat { Json, Csv }` rejects everything else at the serde
  layer, for free, before your code runs.
- Return the **minimum**. A command that returns a whole config struct leaks whatever gets added
  to that struct next year.
- Never accept a shell string, an argv array, or a URL that will be dereferenced, from the
  webview. If you think you need to: go to **Escalate**.

**3. Validate in Rust. Canonicalise, then compare against a root.**
This is the boundary that actually holds; a capability scope is the second layer, never the first
(`references/security.md` §scopes explains why a scope is a data payload, not a sandbox).

```rust
/// Resolve `relative` inside `root`, or refuse. The only path that leaves this
/// function is one proven to live under the real, symlink-resolved root.
fn resolve_in_root(root: &Path, relative: &str) -> Result<PathBuf, AppError> {
    let real_root = dunce::canonicalize(root).map_err(|_| AppError::Denied)?;
    let real = dunce::canonicalize(real_root.join(relative)).map_err(|_| AppError::NotFound)?;
    if !real.starts_with(&real_root) {
        return Err(AppError::Denied);           // `..`, absolute path, or symlink escape
    }
    Ok(real)
}
```

`dunce::canonicalize` (`dunce 1.0.5`, already in ZUS's tree) rather than `std::fs::canonicalize`:
std returns Windows `\\?\` UNC paths, so one side of a `starts_with` can carry the prefix and the
other not, and the containment check silently answers the wrong question.

Non-negotiables in this step:

- **Canonicalise before comparing.** String prefix checks on un-canonicalised input are defeated
  by `..`, by an absolute path, and by a symlink pointing out of the root.
- **Canonicalise the parent for paths that do not exist yet** (writes, creates) — `canonicalize`
  fails on a missing leaf, and falling back to the raw join re-opens the hole.
- **Refuse, do not sanitise.** Stripping `..` from a string is a game you lose; returning
  `Err(Denied)` is one you cannot.
- Apply the same shape to non-path input: an allowlist match for command names, a parsed and
  host-checked `Url` for URLs, an integer range for sizes.

**4. Choose sync vs async correctly.**
Default to `async fn`. A plain `fn` command runs on the tao event loop thread and freezes every
window while it works — `references/ipc-and-commands.md` §Threading has the mechanism and the
`spawn_blocking` escape for CPU-bound work. This matters for security, not just responsiveness: a
frozen UI is also a UI that cannot show the user what is happening or let them cancel it.
Note the coupling to step 2: an `async` command borrowing `State<'_, _>` **must** return `Result`.

**5. Declare the permission.**
One permission per command, named after the command. Permission files are **TOML only** — a JSON
permission file is silently not a permission (`references/security.md` §permissions).

```toml
# src-tauri/permissions/read-project-file.toml
[[permission]]
identifier  = "allow-read-project-file"
description = "Read one file inside the active project root."
commands.allow = ["read_project_file"]
```

Attach a scope only if the command reads `CommandScope<T>` and enforces it. A scope nobody reads
is documentation that looks like a control.

**6. Write the capability entry — narrowest window set, no remote.**

```jsonc
// src-tauri/capabilities/default.json
{
  "identifier": "default",
  "windows": ["main"],                    // not ["*"]
  "permissions": ["allow-read-project-file"]
}
```

If the caller is a window that renders less-trusted content, it gets **its own capability file**,
not an entry appended here. Never add `remote` URLs to a capability carrying filesystem, process,
or shell permissions. Precedence rules — deny wins at every layer, absence of allow is denial —
are in `references/security.md` §precedence.

**7. Test the denial path, not just the happy path.**
The happy path proves the feature works. Only the denial path proves the boundary works. Write
these as unit tests against the pure function from step 3, so they need no `tauri::App`
(`references/debugging-and-testing.md` §testing):

| Input | Required result |
| --- | --- |
| `"notes.md"` | `Ok`, resolves inside root |
| `"../../etc/passwd"` | `Err(Denied)` |
| `"/etc/passwd"` or `"C:\\Windows\\win.ini"` | `Err(Denied)` |
| a symlink inside root pointing outside | `Err(Denied)` |
| `""`, `"."`, a 4 KiB path, a NUL byte | `Err`, no panic |
| the command with its permission removed | ACL error naming the identifier |

A panic here is not a passing test. Under `panic = "abort"` a panicking command kills the process
silently, and `cargo test` runs the **dev** profile so it will not reproduce that
(`references/case-studies.md` §12).

**8. Confirm the command is not reachable from rendered model output without an explicit gate.**
Return to the framing. For this specific command, answer:

- Which windows can invoke it after step 6? Is the window that renders model output one of them?
- Can a chat message, a tool result, or a markdown link cause an invoke — directly, or via a
  frontend handler that forwards a model-chosen action name to `invoke`? An action dispatcher
  keyed on model output re-widens everything steps 2–6 narrowed.
- If the command has side effects (writes, deletes, spawns, sends network requests), what stops
  an injected instruction from triggering it silently? The gate must be **outside** the webview's
  control: a native confirmation dialog, or a capability token minted by a real user gesture in
  Rust. An HTML confirmation the injected content can also click is not a gate.
- If the answer is "nothing stops it", the command is not done. Split it: a read-only, idempotent
  half the renderer may call freely, and a gated half it may not.

---

## Validation

- `cargo clippy --all-targets -- -D warnings` — zero warnings.
- `cargo test` — the step-7 table passes, including every denial row.
- `pnpm tauri dev`, then from devtools:
  `await __TAURI__.core.invoke('read_project_file', { projectId, relative: '../../../etc/passwd' })`
  → the promise **rejects** with your `Denied` error. If it resolves, stop; step 3 is wrong.
- Temporarily remove the permission from the capability file and re-run the happy-path invoke →
  expect the ACL error naming `allow-read-project-file`, then restore it. This proves the
  capability entry is the one actually granting the command
  (`cheatsheets/capabilities-permissions.md`).
- `grep` the diff for a widened scope: no new `**` glob, no new `remote` entry, no `"windows":
  ["*"]`, no plugin default set added "to make it work".
- The UI stays responsive while the command runs — the step-4 check, observed not assumed.

---

## Pitfalls

- **Trusting the scope.** A glob in JSON is a second layer. If Rust does not check, nothing does.
- **Prefix-comparing un-canonicalised paths.** Defeated by `..`, absolutes, and symlinks.
- **Canonicalising after joining a path that does not exist**, then silently falling back to the
  raw join on error. That fallback is the vulnerability.
- **Sanitising instead of refusing.** Every strip-and-retry loop has a bypass.
- **One catch-all command** (`run_action(name, args)`) because it is fewer files. It is one
  command in `generate_handler!` and an unbounded surface in practice.
- **Adding a plugin permission as the fix for a denial.** The denial was working; widening the ACL
  to silence it inverts the control.
- **Testing only the happy path**, so the boundary is unverified by construction.
- **Assuming an XSS is required.** In an AI app, rendered model output is the injection vector,
  and it arrives through the feature working correctly.
- **Returning a raw `io::Error` string.** Error text crosses the boundary verbatim
  (`references/ipc-and-commands.md` §Errors) and leaks absolute paths and usernames.

---

## Escalate — stop and ask rather than proceed

- The requirement genuinely needs **arbitrary path, shell, or URL access from the webview**. There
  is no safe narrow signature; this needs a product decision about the gate, not an implementation.
- The command must be callable by a window that renders untrusted or model-generated content and
  has side effects. Someone must own the decision that this risk is accepted.
- The natural implementation requires enabling a plugin default set whose expansion you have read
  and consider too wide (`references/security.md` §permissions).
- The command handles credentials, keys, or tokens — those cross into the webview and live in a
  process you do not control.
- You cannot construct the symlink-escape test on the target platform. Say so explicitly rather
  than shipping the containment check unverified (SKILL.md rule 10).

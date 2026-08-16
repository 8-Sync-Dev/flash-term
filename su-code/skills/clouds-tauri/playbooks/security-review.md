# Security review — drive it from the trust boundary

**Objective** — establish what an attacker who controls the WebView can reach, and close the
gap between that and what the app intends to expose. The output is an enumerated attack
surface with a severity per entry, not a config-key checklist.

**When to run this** — before the first release, before any release that adds a command or a
capability, when the app starts rendering content it did not author (model output, remote
pages, user documents), after any dependency bump that moves the `tauri` runtime crate, and on
any PR that touches `capabilities/`, CSP, `remote.urls`, or the updater.

**Scope** — this playbook is the *order and the questions*. Every mechanism it names is
explained once in `references/security.md`; if you find yourself re-deriving how precedence
works mid-review, go read it there instead of reasoning it out.

## Review rules (shared by all four review playbooks)

- Report **every** real finding with a severity — `Critical` / `High` / `Medium` / `Low`.
  Do not pre-filter to the exploitable ones; unexploitable-today is a design constraint,
  not a non-finding.
- Every finding carries a **`file:line`** and a **concrete fix** (the permission to remove,
  the validation to add, the version to pin), not a concern.
- **Read the code before claiming behaviour.** A finding you did not verify is a question.
  Keep a separate "unverified — needs an answer" list; do not launder guesses into findings.
- **State which platforms you verified.** Scope semantics differ by platform
  (`requireLiteralLeadingDot`, path separators, shell resolution) — an unverified platform is
  itself a finding.

Report in the shape of `SKILL.md` §Output contract.

---

## Order

**0. Version floor — do this first, it is one command and it can end the review.**

```bash
cargo tree -p tauri -i          # or: rg -n '^name = "tauri"$' -A2 Cargo.lock
```

**`CVE-2026-42184` / `GHSA-7gmj-67g7-phm9` is fixed in `tauri` 2.11.1.** Exposure tracks the
**`tauri` runtime crate**, not `tauri-build` — a lockfile with `tauri-build 2.11.x` and
`tauri 2.9.x` is vulnerable, and this is the mistake teams make when they check. Below the
floor is `Critical` and blocks the release; the fix is a lockfile bump, verified by re-running
the command, not by reading `Cargo.toml`. Details and the rest of the advisory history:
`references/security.md` §advisories.

**1. Draw the boundary on paper before opening a config file.**

Write down, explicitly:

- **What renders in the WebView that the app did not author?** Model output, markdown from a
  repo, remote docs in an iframe, user-supplied filenames, extension code, an npm tree you do
  not audit. Each is an attacker foothold that does not require an XSS bug.
- **Which windows/webviews exist**, and which of them render the above.
- **What the process can reach** that the WebView must not: keychain, tokens on disk, the
  user's home directory, a shell, the network.

This list is the review. Steps 2–8 are its columns. `references/security.md` frames the model;
this step instantiates it for *this* app.

**2. Enumerate every command reachable from rendered untrusted content.**

```bash
rg -n 'generate_handler!' -A400 src-tauri/src/lib.rs
rg -n 'invoke\(|invoke<' src --glob '!node_modules'
```

For each registered command, answer one question: **if the string that reaches this command
were chosen by an attacker, what happens?** Model output is the sharp case — anything the
model can persuade the frontend to invoke is directly reachable. Flag as `Critical` any command
that, with attacker-chosen arguments, can write outside a fixed directory, spawn a process,
read a secret, or make an outbound request to an attacker-chosen host.

The fix is per command and is always Rust-side: canonicalise + assert containment for paths,
allowlist for command names and URL schemes, reject rather than sanitise. A scope entry is the
second layer, never the first.

**3. Capabilities — is the posture default-deny, and does the file say what you think?**

```bash
cat src-tauri/capabilities/*.json
rg -n '"windows"|"platforms"|"permissions"|"remote"' src-tauri/capabilities/
```

Ask in this order:

1. **Which windows does each capability bind to?** A capability with `"windows": ["*"]` grants
   its permissions to the untrusted-content window too. `High`. Fix: name the windows; give the
   less-trusted window its own capability file.
2. **What does each permission set actually expand to?** `core:default` is not "nothing", and
   plugin `:default` sets are not uniformly safe (`references/security.md` §permissions). Cite
   the expansion, not the identifier. A `:default` you cannot enumerate is an unverified
   finding, not a pass.
3. **Is anything granted that no command needs?** Cross-reference against step 2's list.
   Unused grants are `Medium` — they are the surface a future XSS lands on.
4. **Are there `deny` entries, and do they do what the author expects?** Deny beats allow at
   every layer and there are three non-equivalent deny layers
   (`references/security.md` §precedence).

**4. `remote.urls` — additive, and `local` defaults to `true`.**

```bash
rg -n '"remote"' -A6 src-tauri/capabilities/
```

Adding `remote.urls` does **not** move the capability from local to remote: `local` defaults to
`true`, so the grant now applies to your bundled pages **and** the listed origins
(`references/security.md`). Two findings:

- A capability carrying fs, shell, process, or http permissions that also lists any
  `remote.urls` → `Critical`. Any compromise of that origin, or a redirect from it, is a
  compromise of the machine. Fix: split into two capabilities and set `"local": false` on the
  remote one, with a permission list you would hand to a stranger.
- A wildcard in a remote URL pattern (`https://*.example.com`) → `High`; one subdomain
  takeover is enough.

**5. CSP posture.**

Read the `app.security.csp` value in `tauri.conf.json` and compare against
`references/case-studies.md` §1, which contrasts a closed explicit policy with a permissive
one from two real apps.

- No CSP at all → `High`, and the fix is a starting policy plus the list of what breaks.
- `'unsafe-inline'` / `'unsafe-eval'` in `script-src` → `High` unless the framework provably
  requires it; if it does, that is a finding about the framework choice, filed as `Medium`.
- `connect-src` wide open in an app that holds tokens → `High` (exfiltration path).
- CSP is compiled in (`references/architecture.md` §Configuration architecture) — a wrong value
  ships to every machine. Say so in the report; it raises priority.

Also check whether the isolation pattern is in use, and if not, whether this app is one where
it should be (`references/security.md`).

**6. Shell and filesystem exposure.**

```bash
rg -n 'shell:|Command::new|tauri_plugin_shell|open\(' src-tauri/src src-tauri/capabilities
rg -n 'assetProtocol' -A10 src-tauri/tauri.conf.json
```

- Any shell scope entry with an argument the webview supplies → `Critical`. Fix: fixed argv,
  validated enum arguments, or own the command.
- `shell:allow-open` with an unrestricted URL → `High`; a `file://` or a scheme handler is a
  code-execution path on all three platforms. Fix: validate the scheme against an allowlist in
  Rust before calling.
- `assetProtocol.scope` broad enough to serve `$HOME` → `High`
  (`references/case-studies.md` §2 shows the difference between a scope and a decoration).
- Filesystem scopes: check the traversal and symlink semantics you are relying on actually
  hold, and check `requireLiteralLeadingDot` — it defaults differently on Windows and unix, so
  the same glob gives two answers (`references/security.md` §scopes). Platform-specific:
  verify on each, or file the unverified platform.

**7. Secrets.**

```bash
rg -n 'API_KEY|SECRET|TOKEN|PASSWORD|BEGIN (RSA|OPENSSH|PRIVATE)' src-tauri/src src --glob '!node_modules'
rg -n 'localStorage|sessionStorage|indexedDB' src --glob '!node_modules'
```

- A secret compiled into the binary (`env!`, a literal, a `.env` baked at build) → `Critical`.
  A desktop binary is readable by its user; `strings` finds it. Fix: the OS keychain via
  `tauri-plugin-stronghold` or the platform store, or move the call server-side.
- A token in `localStorage` → `High`. It is reachable by any script in the WebView, which is
  the untrusted side. Fix: hold it in Rust state, expose only the operations that need it.
- A secret in a log line or an error string returned to the WebView → `High`. Cross-check with
  `playbooks/code-review.md` step 9.

**8. Updater trust — the only mechanism that can repair everything above.**

- Is the public key in `tauri.conf.json` the one whose private half is in CI, and is that
  private key backed up outside CI? Loss is unrecoverable — `Critical` if unbacked
  (`references/build-and-distribution.md` §update security).
- **Is there more than one endpoint?** A single endpoint is a permanent single point of
  failure (`references/case-studies.md` §6). `High`.
- Does the app handle the case where `check()` returns `Ok(None)`? It does that on HTTP `204`
  and **never consults fallback endpoints** — an endpoint answering `204` silently strands
  every user, and the fallback list you configured will not save you. `High`; fix is to treat
  `Ok(None)` as a distinguishable state, log it, and probe the remaining endpoints explicitly.
- Is the update fetched over TLS from a host you control, with the signature checked before
  install (default — confirm nobody disabled it)?

## Validation

```bash
cargo tree -p tauri -i                    # step 0 floor, after the fix
cargo audit                               # advisory sweep across the whole tree
cargo tauri build --debug                 # capabilities are compiled in; prove they build
```

Then verify by attempting the thing, not by reading the config:

- For each `Critical` from step 2, call the command from the devtools console with a hostile
  argument (`../../../etc/passwd`, an absolute path outside the root, a `file://` URL) and
  record the rejection. A capability change is verified when the call is refused *with the
  ACL error*, and a Rust-validation change is verified when it is refused *with your error*.
- For CSP, load the built app, open devtools, and confirm the violation report appears for an
  injected inline script.
- For the updater, point a build at a test endpoint returning `204` and confirm the app's
  logged behaviour matches what you claimed.

State the platform each of these was run on.

## Pitfalls

- **Checking `tauri-build`'s version for the CVE.** The runtime crate is what matters.
- **Reading `Cargo.toml` instead of `Cargo.lock`.** The caret range is not the resolved version.
- **Treating a scope as a sandbox.** It is a data payload handed to the command
  (`references/security.md` §scopes); the command still has to be right.
- **Adding a permission to make an error go away** and calling that the fix. Ask what the
  command needed; usually the answer is to own the command.
- **Assuming `remote.urls` replaced local access.** It added to it.
- **Auditing only the default capability file.** Extra windows have their own, and platform
  filters mean a file can be inert on your machine and live on someone else's.
- **Declaring the review clean when untrusted content is rendered but no command was traced.**
  Step 2 is the review; steps 3–8 are its supporting evidence.

## Escalate

- Below the `tauri` 2.11.1 floor and the bump breaks the build → stop the release, escalate.
  Do not ship and do not patch around it.
- The app renders model output and grants shell or unrestricted fs → stop; this needs a design
  change (an approval step, a sandboxed worker), not a scope narrowing.
- The signing key or updater private key cannot be located → one-way door, escalate to whoever
  owns the release before anything else in this list.
- You cannot determine what a `:default` permission set expands to for the pinned version →
  ask, or read the plugin's `permissions/` directory. Do not assume it is safe.

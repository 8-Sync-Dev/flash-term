# Release preparation — ship a build you can support

**Objective** — produce a release you can still repair after it is installed: correct
versions, signed artifacts, an updater that survives one endpoint failing, and a decided
rollback path.

**When to run this**
- Before the **first** release of an app. This is the highest-stakes run of this playbook;
  three of the decisions below are permanent (see *One-way doors*).
- Before every subsequent tagged release.
- Any time `version`, `identifier`, `bundle`, `signing`, or `updater` config changes.
- Routed here from `SKILL.md` rule 7 and `rules/release-keyword.mdc`.

Mechanisms are in `references/build-and-distribution.md`. This file is the order and the
gate list.

---

## One-way doors — settle these before the first release, never after

Three decisions become permanent the moment a user installs. There is no config change,
patch release, or support article that undoes them.

| Decision | Why it is permanent | Reference |
| --- | --- | --- |
| **Bundle identifier** (`identifier`) | Identifies the install to the OS, the data directory, and the WebView origin. Changing it makes the next version a *different application*: separate data, no upgrade path, two icons in the launcher. | `references/build-and-distribution.md §signing`, `references/cross-platform.md §Windows` |
| **Code signing identity** | Users' OS trust decisions, SmartScreen reputation, and macOS Gatekeeper history attach to the identity. A new certificate restarts reputation from zero. | `references/build-and-distribution.md §signing` |
| **Updater keypair (minisign)** | The **public** key is compiled into every shipped binary. Installs only accept artifacts signed by the matching private key. | `references/build-and-distribution.md §updater`, `§update security` |

**Losing the updater private key orphans every existing install permanently.** Those
machines will reject every future update you sign, forever, and the only remedy is asking
each user to manually download and reinstall — which is exactly the thing the updater
exists to avoid. Before the first release: confirm the private key and its password are in
a durable secret store (not one laptop, not one CI secret), and that at least two people or
one recovery process can reach them. Rotation is only possible *forward*, from a version
users already have — read `references/build-and-distribution.md §update security` before
assuming you can fix this later.

---

## Order

### 1. Bump the version, and make every declaration agree

The version appears in more than one place and nothing enforces agreement. A mismatch does
not fail the build — it produces artifacts whose filename, installer metadata, About window,
and updater comparison disagree.

Set, and confirm all three match:

| File | Field | Consumed by |
| --- | --- | --- |
| `src-tauri/Cargo.toml` | `[package] version` | The Rust crate; the value Tauri reports at runtime and compares against the updater manifest |
| `src-tauri/tauri.conf.json` | `version` | Bundle metadata and artifact names — **omit it and Tauri reads `Cargo.toml`**, which is the safer configuration |
| `package.json` | `version` | The JS toolchain, your tag, your changelog |

The lowest-maintenance arrangement is to remove `version` from `tauri.conf.json` entirely so
there is one fewer thing to desynchronise, leaving `Cargo.toml` as the source of truth and
`package.json` mirrored by your release script.

Verify:

```bash
grep -m1 '^version' src-tauri/Cargo.toml
grep -m1 '"version"' src-tauri/tauri.conf.json package.json
```

Version comparison is what decides whether an update is offered at all
(`references/build-and-distribution.md §updater`), so a wrong number here is an update that
silently never ships.

### 2. Write the changelog before the build, not after

Write it from the commit range, not from memory:

```bash
git log --oneline <previous-tag>..HEAD
```

Every entry that changes user-visible behaviour, every security fix with its advisory ID,
and every migration a user must perform. This is also the last cheap moment to notice that
something in the range should not ship.

If the range contains a dependency bump of the **`tauri` runtime crate**, check it against
`references/security.md §advisories` — advisory exposure tracks the `tauri` crate version,
not `tauri-build`.

### 3. Run the gates — once each, at the end

Not per-commit, not interleaved with fixes. A gate run before the final commit proves
nothing about the artifact you are shipping. Run them in this order and stop at the first
failure:

```bash
pnpm exec tsc --noEmit                              # zero errors
pnpm exec eslint .                                  # zero errors
cargo fmt --check --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml     # all pass
pnpm test                                           # if the frontend has a suite
```

Then build **per target platform** — not one platform and an assumption:

```bash
pnpm tauri build           # on each of the platforms you claim to support
```

A green test suite is not a green release. `cargo test` runs under the dev profile and will
not surface a release-profile defect — a panic that aborts the shipped process is caught and
reported as an ordinary failure under test. See `playbooks/production-debugging.md` step 3.

### 4. Sign every artifact, and verify the signature independently

Signing configuration, per-platform certificate handling, notarization and stapling are in
`references/build-and-distribution.md §signing`. The gate here is procedural:

- Every distributable artifact is signed — installers *and* the binaries inside them.
- The signature is verified with the platform's own tool on a machine that did not sign it.
  A build that "reported success" is not evidence; SmartScreen and Gatekeeper are.
- Notarization (macOS) completed and was **stapled**. Unstapled notarization fails offline.
- Signing secrets came from the secret store, not from a local keychain that only exists on
  the release engineer's machine.

### 5. Publish the updater manifest with at least two endpoints on different infrastructure

Configure `updater.endpoints` with **two or more URLs whose failure domains do not overlap**
— not two paths on the same host, not two buckets in the same account with the same
credentials, not two CDN routes to the same origin. One endpoint is one permanent single
point of failure, and the config that names it is compiled into every installed binary
(`references/build-and-distribution.md §updater`, `references/case-studies.md` §6).

Then verify the manifest is actually reachable and correct, from outside your network:

```bash
curl -i "<endpoint-1>"     # expect 200 and a valid JSON manifest
curl -i "<endpoint-2>"     # expect the same manifest
```

Check the manifest's `version`, per-platform `url`, and `signature` against the artifacts you
actually uploaded. A manifest pointing at a previous release's artifact is signed, valid, and
wrong.

### 6. Install and launch the artifact on a clean machine

The build machine has your toolchain, your dev certificates, your WebView2 runtime, your
system libraries, and your app's data directory from previous runs. It cannot tell you
whether a stranger's machine will run this.

On a clean VM or a second machine per platform:

1. Install from the distributed artifact, the way a user would.
2. Launch. Confirm no SmartScreen/Gatekeeper block, no missing-runtime prompt you did not
   intend, no console window (`references/case-studies.md` §8).
3. Exercise the primary flow, plus anything the changelog claims changed.
4. **Test the upgrade path, not only the fresh install** — install the *previous* release,
   then let the updater move it to this one. Fresh install and in-place upgrade are
   different code paths and the upgrade one is the one that can strand users.
5. Confirm user data survived the upgrade.

### 7. Decide the rollback plan before you release

Written down, before the artifact is public — deciding this during an incident is how a bad
release stays live for a day.

Answer, concretely:

- **Who can pull the release**, and how (delist the artifact, revert the manifest).
- **What the manifest reverts to** — note that publishing an older version in the manifest
  does *not* downgrade installs; version comparison will simply stop offering updates. The
  practical rollback is *forward*: a new higher version containing the revert.
- **How you will know** — the metric in *Validation* below, and who watches it.
- **The floor**: which older version is still installable if the updater path itself is what
  broke.

---

## Validation

- All three version declarations agree (step 1 command output).
- All gates green in a single final run, and a real bundle produced per target platform.
- Signature verified with a platform tool on a machine that did not produce the build.
- Both updater endpoints return the same correct manifest from an outside network (step 5).
- The artifact installed and launched on a clean machine per platform, **and** the previous
  version upgraded to it through the updater (step 6).
- **Update check success rate is a metric you collect, not an assumption.** A primary
  endpoint answering HTTP `204` makes `check()` return `Ok(None)` and it never consults the
  fallback endpoints — so a misconfigured or degraded primary silently freezes your entire
  install base while every dashboard stays green and no error is ever logged
  (`references/build-and-distribution.md §update security`). Instrument the check result and
  alert on the rate dropping, because nothing else will tell you.
- Rollback plan written and its owner named.

---

## Pitfalls

- **Versions that disagree.** No build error, but the updater compares against the crate
  version while the artifact filename came from somewhere else.
- **A `[profile.release]` in a workspace member.** Cargo silently ignores it; only the
  workspace root counts. You ship a profile you never configured
  (`references/case-studies.md` §12).
- **Running gates before the last commit.** Then landing "one small fix" and shipping
  untested bytes.
- **Two endpoints on one failure domain.** Two URLs that die together are one endpoint with
  extra configuration.
- **Testing only a fresh install.** The upgrade path is the one that breaks, and it is the
  one every existing user takes.
- **Treating "no update-failure reports" as health.** The `204` failure mode produces no
  reports at all — that is precisely what makes it dangerous.
- **Signing keys on one laptop.** See *One-way doors*.
- **Changing `identifier` to "clean things up".** It forks the application.
- **`dangerousInsecureTransportProtocol`, ever.** `references/build-and-distribution.md
  §update security`.

---

## Escalate

Stop and ask rather than proceeding when:

- Any one-way door is not yet decided, or the updater private key's location cannot be
  confirmed by someone other than you.
- You cannot build or clean-machine-test one of the platforms you claim to support. Do not
  ship it as supported — report it as unverified
  (`playbooks/cross-platform-validation.md`).
- Only one updater endpoint is available and adding a second requires infrastructure you do
  not own. That is a risk acceptance the project must make explicitly, not a step you skip.
- A gate fails for a reason you would need to suppress rather than fix.
- The release range contains a security fix and you cannot confirm the fixed version is the
  one being built (`references/security.md §advisories`).

# Build, sign, ship — lookup

Verified against **`tauri 2.11.5`**, CLI `2.11.4`, updater plugin `2.10.1`,
`tauri-apps/tauri-action@v1`, 2026-07-28.
Mechanism, trade-offs and failure analysis: `references/build-and-distribution.md`
§signing, §updater, §CI, §update security.

---

## ⚠ One-way doors — decide these before release 1

| Decision | Where | Why it cannot be undone |
| --- | --- | --- |
| **Bundle identifier** (`identifier`) | `tauri.conf.json` | It is the app's OS identity: macOS bundle ID (bound to your Apple Team ID), Windows install path and registry keys, Linux package name. Changing it makes every installed copy a **different app** — no upgrade path, no data migration |
| **`wix.upgradeCode`** and **`productName`** | `bundle.windows.wix` | Unset, the upgrade code is derived from **`productName`** — so renaming the product silently changes it. MSI users then get duplicate Add/Remove Programs entries and side-by-side installs instead of upgrades. Run `tauri inspect wix-upgrade-code` and **pin the value in config before release 1** |
| **Signing identity / certificate subject** | Apple `Developer ID`, Windows cert | SmartScreen reputation attaches to the certificate; macOS keychain ACLs attach to the signature. New CA, new legal entity name, or a lapsed-then-reissued cert **restarts reputation at zero** |
| **Updater minisign private key** | `tauri signer generate` | **Lose it and you can never publish an update to anyone who already installed the app.** No recovery. Their only path forward is downloading a fresh installer out-of-band |
| **Updater endpoint list** | `plugins.updater.endpoints` | Compiled into the binary. A single endpoint is a single permanent point of failure — ship **two**, on different infrastructure |
| **`createUpdaterArtifacts: "v1Compatible"`** | `bundle` | You cannot move to `true` until every v1 client is gone |

Back up the private key offline (printed / air-gapped), store the password **separately** from the
key, and never generate a CI key without `-p`.

---

## 1. Bundle targets

`bundle.targets`: `"all"` (default), one `BundleType`, or an array of
`"deb" | "rpm" | "appimage" | "msi" | "nsis" | "app" | "dmg"`.

| Target | OS | Pick it when | Cost / gotcha |
| --- | --- | --- | --- |
| `nsis` → `-setup.exe` | Windows | Default choice. Per-user install without admin, silent `/S`, cross-compilable | Rejected by MSI-only enterprise deployment |
| `msi` | Windows | GPO/SCCM, WiX fragments | Windows build host; **one `.msi` per language**; drags in the `updaterJsonPreferNsis` trap |
| `app` | macOS | Required intermediate for everything; App Store input | Not user-downloadable on its own |
| `dmg` | macOS | Direct download | Mac host + notarization. **Not an updater artifact** — the updater payload is `.app.tar.gz` |
| `deb` | Linux | Debian/Ubuntu; build input for Snap and Flatpak | Couples you to distro `libwebkit2gtk-4.1-0` / `libgtk-3-0` (+ `libappindicator3-1` with a tray) |
| `rpm` | Linux | Fedora/RHEL/openSUSE | Same coupling; misusing `epoch` breaks version comparison permanently |
| `appimage` | Linux | One file, widest reach; **the only Linux target the updater replaces in place** | 2–6 MB → **70+ MB**; `bundleMediaFramework` adds 15–35 MB and GStreamer `ugly` licensing |

**Two defaults that produce nothing and exit 0:**

| Key | Default | Consequence |
| --- | --- | --- |
| `bundle.active` | `false` | `tauri build` produces no installer unless this is `true` **or** `--bundles` is passed |
| `bundle.createUpdaterArtifacts` | `false` | Installers but no `.sig` files → nothing to put in the manifest → the updater never fires |

Assert on **artifact presence** in CI, never on exit code.

## 2. Icons

```sh
npm run tauri icon path/to/app-icon.png        # square source PNG
npm run tauri icon icon.png --ios-color '#fff'
```

Generates every platform size including the Microsoft Store set, and writes `bundle.icon`.
Fully reversible — regenerate freely.

---

## 3. Signing — Windows

Signing is not required to *run*. It is required to avoid SmartScreen and to list in the Store.

| Path | Config | When |
| --- | --- | --- |
| `certificateThumbprint` + `digestAlgorithm` + `timestampUrl` | `bundle.windows` | **Legacy only** — the docs restrict this to OV certificates *acquired before 2023-06-01* |
| `signCommand` | `bundle.windows` | Everything else. OV issued after 2023-06-01 and **all** EV certs keep the key on an HSM/token, which cannot live in the Windows cert store |

```json
{ "bundle": { "windows": {
  "signCommand": { "cmd": "relic", "args": ["sign", "--file", "%1", "--key", "azure", "--config", "relic.conf"] }
} } }
```

`%1` is the file to sign; use the object form to survive whitespace in paths.
Cloud options with first-party docs: **`relic`** against Azure Key Vault (app registration needs
**Key Vault Certificate User** *and* **Key Vault Crypto User**; auth via `AZURE_CLIENT_ID` /
`AZURE_TENANT_ID` / `AZURE_CLIENT_SECRET`), and **Azure Artifact Signing** (formerly Azure Trusted
Signing / Azure Code Signing) via `cargo install artifact-signing-cli`.
A real working `sign.ps1` from a shipping app: `references/case-studies.md` §7.

**SmartScreen reality**, verbatim from the docs: an **EV** certificate *"will receive an immediate
reputation … and won't show any warnings"*; an **OV** certificate *"will still show a warning …
It might take some time until your certificate builds enough reputation."* The operational sting:
the trust anchor is per-certificate but the warning is effectively **per-file**, so every release
ships a new hash and restarts the clock. High cadence makes OV worse, not better.

| Symptom | Cause |
| --- | --- |
| `certificate not found` with a thumbprint copied from cert details | `certificateThumbprint` is the **SHA1** hash regardless of `digestAlgorithm` — you copied SHA-256 |
| Signature applies, nothing changes | You bought an SSL/TLS cert, not a **code signing** cert |
| Every installed copy warns the day the cert expires | No RFC 3161 timestamp |
| CI green, installers unsigned | `--no-sign` was passed (logs and exits 0), or `signCommand` failed tolerantly. Verify with `signtool verify /pa` |

## 4. Signing — macOS

Three separate operations. Prerequisites: paid Apple Developer account (**$99/yr**) **and a macOS
machine**. The free plan cannot notarize at all.

| Step | How | Failure if skipped |
| --- | --- | --- |
| **Sign** | `Developer ID Application` cert (outside the App Store) / `Apple Distribution` (App Store). `security find-identity -v -p codesigning` → `bundle.macOS.signingIdentity` or `APPLE_SIGNING_IDENTITY` | Apple Silicon refuses downloaded unsigned code |
| **Notarize** | Automatic during `tauri build` once the env vars are set | Users see **"the application is damaged and can't be opened"** — signed but not notarized. Misleading message, disproportionate support volume |
| **Staple** | Default on; `tauri build --skip-stapling` to opt out | Gatekeeper phones Apple at first launch → fails on air-gapped / locked-down networks |

`bundle.macOS.hardenedRuntime` defaults to **`true`**. `bundle.macOS.entitlements` is applied **at
signing time**, so an unsigned build silently has none. Add one entitlement at a time with the
error it fixes written next to it — `references/case-studies.md` §5.

**Release 1: use `--skip-stapling`.** First notarization can take hours and will blow the CI job
timeout. Turn it off from release 2 onward.

`"signingIdentity": "-"` (ad-hoc) is the no-certificate escape hatch — recommended by the official
GitHub pipeline page to stop Apple Silicon calling GitHub-hosted builds "damaged". It does **not**
remove the Privacy & Security whitelist prompt. Internal builds only.

## 5. Signing — Linux (the honest picture)

| Artifact | Mechanism | Worth it? |
| --- | --- | --- |
| AppImage | Env vars, not config: `SIGN=1`, `SIGN_KEY`, `APPIMAGETOOL_SIGN_PASSPHRASE`, `APPIMAGETOOL_FORCE_SIGN=1` | **No runtime verification.** Official docs: *"AppImage does not validate the signature, so you can't rely on it to check whether the file has been tampered with."* Provenance metadata, not an integrity control |
| RPM | `TAURI_SIGNING_RPM_KEY` (ASCII-armored **private key content**) + `TAURI_SIGNING_RPM_KEY_PASSPHRASE` | Yes — buys `rpm -K` and eligibility for a signed repo |
| deb | **No first-party Tauri signing** | Sign the **repository** (`Release.gpg` / `InRelease`, via `reprepro`/`aptly`) — that is how apt trust actually works |

Without `APPIMAGETOOL_FORCE_SIGN=1` the AppImage is produced anyway when signing fails; a green
build proves nothing. Without `APPIMAGETOOL_SIGN_PASSPHRASE` in CI, gpg opens a dialog and the job
hangs. What *is* enforced on Linux is the **updater's minisign signature**, verified in-process and
not disableable — which is why the updater, not artifact signing, is your integrity mechanism here.

---

## 6. Environment variables

| Variable | For | Gotcha |
| --- | --- | --- |
| `TAURI_SIGNING_PRIVATE_KEY` | Updater minisign key — key **content or a path** | Read by `build`/`bundle`. **`.env` files do not work**; it must be in the real process environment. Missing → no `.sig` files → "the updater doesn't work" |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | That key's password | Set to `""` for a password-less key |
| `TAURI_SIGNING_PRIVATE_KEY_PATH` | `tauri signer sign --private-key-path` only | **Never read by `build` or `bundle`** — setting it in CI signs nothing |
| `TAURI_SIGNING_RPM_KEY` / `..._PASSPHRASE` | RPM GPG signing | Key *content*: `export TAURI_SIGNING_RPM_KEY=$(cat my_private.key)` |
| `TAURI_WINDOWS_SIGNTOOL_PATH` | Override `signtool.exe` discovery | — |
| `TAURI_SKIP_SIDECAR_SIGNATURE_CHECK` | Stop Tauri re-signing a vendored sidecar on macOS | Re-signing invalidates the vendor's signature |
| `TAURI_BUNDLER_TOOLS_GITHUB_MIRROR` | Mirror the NSIS/WiX toolchain download | Not optional in air-gapped or China-based CI |
| `APPLE_CERTIFICATE` / `APPLE_CERTIFICATE_PASSWORD` | base64 `.p12` + password, imported into a CI keychain | `APPLE_SIGNING_IDENTITY` is inferred from these if unset |
| `APPLE_SIGNING_IDENTITY` | Identity string | Equivalent to `bundle.macOS.signingIdentity` |
| `APPLE_API_ISSUER` / `APPLE_API_KEY` / `APPLE_API_KEY_PATH` | App Store Connect notarization — **use this in CI** | The `.p8` downloads **once**, after a page reload. Unset path → searched in `./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys` (also `API_PRIVATE_KEYS_DIR`) |
| `APPLE_ID` / `APPLE_PASSWORD` / `APPLE_TEAM_ID` | Apple-ID notarization | `APPLE_PASSWORD` is an **app-specific password** (or `@keychain:<item>` / `@env:<VAR>`) |
| `APPLE_PROVIDER_SHORT_NAME` | Disambiguate teams | **Required** when your Apple ID belongs to more than one team; otherwise notarization fails ambiguously |
| `SIGN` / `SIGN_KEY` / `APPIMAGETOOL_SIGN_PASSPHRASE` / `APPIMAGETOOL_FORCE_SIGN` | AppImage GPG | §5 |
| `TAURI_PRIVATE_KEY`, `..._PATH`, `..._PASSWORD` | **Deprecated v1 names** | Still accepted by `signer sign` with a warning; removal scheduled for v3 |

Hook-only vars available inside `beforeBuildCommand` etc. (`TAURI_ENV_TARGET_TRIPLE`,
`TAURI_ENV_PLATFORM`, `TAURI_ENV_DEBUG`, …) are a different family:
`references/build-and-distribution.md` §Build-time environment variables.

---

## 7. Updater

```sh
npm run tauri signer generate -- -w ~/.tauri/myapp.key     # writes myapp.key + myapp.key.pub
export TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/myapp.key)"
export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="…"
```

```json
{
  "bundle": { "createUpdaterArtifacts": true },
  "plugins": { "updater": {
    "pubkey": "CONTENT OF myapp.key.pub",
    "endpoints": [
      "https://releases.example.com/{{target}}/{{arch}}/{{current_version}}",
      "https://github.com/me/app/releases/latest/download/latest.json"
    ],
    "windows": { "installMode": "passive" }
  } }
}
```

`pubkey` is the key **content** — *"It cannot be a file path!"*
URL variables: `{{current_version}}`, `{{target}}` (`linux`|`windows`|`darwin`), `{{arch}}`
(`x86_64`|`i686`|`aarch64`|`armv7`), and source-verified-but-undocumented `{{bundle_type}}`.

### Manifest

```json
{
  "version": "1.4.2",
  "notes": "…",
  "pub_date": "2026-07-28T14:03:11Z",
  "platforms": {
    "windows-x86_64":      { "signature": "<contents of the .sig file>", "url": "https://…/MyApp_1.4.2_x64-setup.exe" },
    "windows-x86_64-msi":  { "signature": "…", "url": "https://…/MyApp_1.4.2_x64_en-US.msi" },
    "darwin-aarch64":      { "signature": "…", "url": "https://…/MyApp_1.4.2_aarch64.app.tar.gz" },
    "linux-x86_64":        { "signature": "…", "url": "https://…/my-app_1.4.2_amd64.AppImage" }
  }
}
```

| Field | Rule |
| --- | --- |
| `version` | Valid SemVer, leading `v` optional |
| `pub_date` | RFC 3339 if present |
| Platform key | `<os>-<arch>`, os ∈ `linux`\|`darwin`\|`windows`, arch ∈ `x86_64`\|`aarch64`\|`i686`\|`armv7` |
| `<os>-<arch>-<installer>` | Tried **first** (`windows-x86_64-nsis`, `linux-x86_64-deb`, …). Publish both keys instead of guessing which installer the user has |
| `signature` | The **contents** of the `.sig` file. *"A path or URL does not work!"* Changes every build — regenerate per release, never hand-maintain |
| Required | `version`, `url`, `signature`. One malformed platform entry **breaks every platform** — the whole file is validated before the version check |

### The `204` trap

`check()` iterates `endpoints` in order — but a **`204 No Content` returns `Ok(None)`
immediately and never tries the remaining endpoints.** It only advances on other non-2XX statuses.
Consequence: your fallback endpoint is not a fallback against a primary that answers `204`, and
anyone who can serve `204` (including an on-path attacker if
`dangerousInsecureTransportProtocol` is on) can suppress updates silently and indefinitely.
Rollback attacks and key rotation: `references/build-and-distribution.md` §update security.

| Symptom | Cause, in order of frequency |
| --- | --- |
| `check()` returns null, no error | (1) `createUpdaterArtifacts: false`; (2) `TAURI_SIGNING_PRIVATE_KEY` absent from the environment; (3) primary endpoint returned `204` |
| `Error::EmptyEndpoints` | Empty `endpoints` — fails at `build()`, not at `check()`. Loud, which is good |
| Broken on all platforms after adding one | One invalid platform entry |

There is **no built-in update dialog in v2** — `tauri.updater.dialog` and `.active` are gone; you
build the UI.

---

## 8. CI — `tauri-apps/tauri-action@v1`

```yaml
jobs:
  publish-tauri:
    permissions:
      contents: write            # GITHUB_TOKEN is read-only by default
    strategy:
      fail-fast: false
      matrix:
        include:
          - platform: 'macos-latest'
            args: '--target aarch64-apple-darwin'
          - platform: 'macos-latest'
            args: '--target x86_64-apple-darwin'
          - platform: 'ubuntu-22.04'
            args: ''
          - platform: 'windows-latest'
            args: ''
    runs-on: ${{ matrix.platform }}
    steps:
      - uses: actions/checkout@v7
      - if: startsWith(matrix.platform, 'ubuntu')
        run: |
          sudo apt-get update
          sudo apt-get install -y libwebkit2gtk-4.1-dev libappindicator3-dev librsvg2-dev patchelf xdg-utils
      - uses: actions/setup-node@v6
        with: { node-version: lts/*, cache: 'npm' }
      - uses: dtolnay/rust-toolchain@stable
      - uses: swatinem/rust-cache@v2
        with: { workspaces: './src-tauri -> target' }
      - run: npm install
      - uses: tauri-apps/tauri-action@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAURI_SIGNING_PRIVATE_KEY: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}
          TAURI_SIGNING_PRIVATE_KEY_PASSWORD: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY_PASSWORD }}
          APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
          APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
          APPLE_API_ISSUER: ${{ secrets.APPLE_API_ISSUER }}
          APPLE_API_KEY: ${{ secrets.APPLE_API_KEY }}
          APPLE_API_KEY_PATH: ${{ secrets.APPLE_API_KEY_PATH }}
        with:
          tagName: app-v__VERSION__          # ALWAYS pass this
          releaseName: 'App v__VERSION__'
          releaseDraft: true
          updaterJsonPreferNsis: true        # default is false → MSI wins in latest.json
          args: ${{ matrix.args }}
```

| Input / symptom | Note |
| --- | --- |
| `@v1` | Current major. Most blog posts still show `@v0` |
| `uploadUpdaterJson` | Default `true` — the action generates `latest.json` for you |
| `updaterJsonPreferNsis` | Default **`false`** "for legacy reasons" → when both bundles exist, the **MSI** wins and NSIS users get handed an `.msi` |
| `releaseId` without `tagName` | URLs fall back to `releases/latest/download/…` → 404s and wrong binaries. **Always pass `tagName`** |
| `tagName` targets a draft release | `releaseDraft` **must** be `true` or the action cannot find it |
| `Resource not accessible by integration` | Missing `permissions: contents: write` |
| Windows cert import | A **separate prior step** on `windows-latest`, before the action |
| `swatinem/rust-cache@v2` | Biggest single CI win; the `workspaces:` path is layout-specific or the cache silently never hits |
| `uploadPlainBinary` | Explicitly discouraged — breaks `bundle_type()` and per-bundle-type updater keys |

macOS is two per-arch entries rather than `universal-apple-darwin` because a universal binary
doubles the `.app.tar.gz` the updater buffers in memory. Full input list and the deviation case
(driving `tauri build` directly): `references/build-and-distribution.md` §CI.

# M001: M001:

## Vision
M001:

## Slice Overview
| ID | Slice | Risk | Depends | Done | After this |
|----|-------|------|---------|------|------------|
| S01 | GPU Status Surface | low | — | ✅ | # S01: GPU Status Surface — UAT

**Milestone:** M001
**Written:** 2026-03-27T07:40:35.954Z

## UAT Type

- UAT mode: artifact-driven
- Why this mode is sufficient: The slice delivers a diagnostic CLI command. All behavior is observable via command output — no UI, no network, no persistent side effects. The bootstrap can be dot-sourced in an isolated pwsh session and all subcommands exercised directly.

## Preconditions

- WezTerm is installed and `wezterm` is on PATH (for liveness tag; not required for core checks)
- Working directory is the repo root (so `wezterm-bootstrap.ps1` can be dot-sourced)
- Run in a clean `pwsh -NoLogo -NoProfile` session to avoid contamination from other profiles

## Smoke Test

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; 8sync gpu status"
```
Expected: Displays `GPU Acceleration Status` block with Front-end, Active GPU, Power preference rows. Exit code 0.

---

## Test Cases

### 1. gpu status shows all five fields

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('status')"
```

1. Run the command above.
2. **Expected:**
   - `Front-end:` row shows `WebGpu`
   - `Active GPU:` row shows a real GPU name and `(DiscreteGpu)` or `(IntegratedGpu)` — not `(unknown)`
   - `Power preference:` row shows `HighPerformance`
   - `Min GPU target:` row shows either a percentage (if `current-gpu.lua` exists) or `(not set)`
   - `State file:` row shows a full path ending in `current-gpu.lua`
   - Last line shows `[WezTerm running]` or `[WezTerm not detected]` — either is valid
   - Exit code: 0

### 2. gpu verify produces PASS/FAIL checks

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('verify')"
```

1. Run the command above.
2. **Expected:**
   - `[PASS]  front_end = WebGpu` (green)
   - `[PASS]  GPU type = DiscreteGpu  device: <name>` (green)
   - `[PASS]  power_preference = HighPerformance` (green)
   - Check 4 (state file): `[PASS]` if `current-gpu.lua` exists in cwd, `[FAIL]  current-gpu.lua exists  (file missing)` if not — both are valid depending on environment
   - Summary line: `3/4 checks passed` (worktree without state file) or `4/4 checks passed` (live config)
   - Exit code: 0

### 3. gpu help renders correctly

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('help')"
```

1. Run the command above.
2. **Expected:**
   - Section header `GPU ACCELERATION` shown in Cyan
   - Three rows: `8sync gpu status`, `8sync gpu verify`, `8sync gpu help` — each with a description
   - Exit code: 0

### 4. Alias dispatch via 8sync works

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; 8sync gpu status"
```

1. Run the command above.
2. **Expected:** Identical output to Test Case 1. Confirms `Invoke-8Sync` dispatches `gpu` to `Invoke-GpuCommand`.

### 5. Unknown subcommand falls back gracefully

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('frobnicate')"
```

1. Run the command above.
2. **Expected:**
   - Warning line: `Unknown gpu subcommand: frobnicate` in DarkYellow
   - GPU ACCELERATION help block displayed below
   - Exit code: 0

### 6. No arguments shows status + help

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @()"
```

1. Run the command above.
2. **Expected:** GPU Acceleration Status block followed by GPU ACCELERATION help block. Exit code: 0.

---

## Edge Cases

### State file absent (fresh clone or worktree)

1. Ensure `current-gpu.lua` does not exist in the working directory.
2. Run `8sync gpu status`.
3. **Expected:** `Min GPU target: (not set)`, `Last updated: (never)` — no error, no crash.

### State file present with valid min_percent

1. Create `current-gpu.lua` with content: `return { min_percent = 42, updated_utc = "2026-01-01T00:00:00Z" }`
2. Run `8sync gpu status`.
3. **Expected:** `Min GPU target: 42%`, `Last updated: 2026-01-01T00:00:00Z`.
4. Run `8sync gpu verify`.
5. **Expected:** Check 4 shows `[PASS]  current-gpu.lua exists  (min_percent=42)`.

### WezTerm not running

1. Run the status command without WezTerm running.
2. **Expected:** Liveness tag shows `[WezTerm not detected]` — no error or exception.

### Tab completion

1. In an interactive `pwsh` session with bootstrap sourced, type `8sync gpu` then press Tab.
2. **Expected:** Completions `status`, `verify`, `help` are offered.

---

## Failure Signals

- Any output line containing `Exception` or `Error:` (not `[FAIL]`) indicates an unhandled exception
- `Active GPU: (unknown)` indicates WMI failed — check `Get-WmiObject Win32_VideoController` directly
- `Front-end:` or `Power preference:` showing `(unknown)` or empty indicates `wezterm.lua` path lookup failed
- Missing `GPU ACCELERATION` section in help output indicates `Register-8SyncCompleter` was not updated

## Not Proven By This UAT

- That `current-gpu.lua` is written correctly by `8sync gpu set` (that command doesn't exist yet)
- That WezTerm actually uses WebGpu at runtime (we read config intent, not runtime state)
- Tab completion in a live WezTerm session (requires interactive terminal)
- Behavior on a machine with only integrated GPU (no discrete adapter)

## Notes for Tester

The `$PSScriptRoot` path issue means `front_end` and `power_preference` are read from hardcoded defaults in `Get-ActiveGpuInfo`, not from the actual `wezterm.lua`. This works correctly on the current system because the config uses the default values. If you've customized `config.front_end` to something other than `WebGpu`, the status and verify commands will still show `WebGpu` — this is a known limitation documented in KNOWLEDGE.md.
 |
| S02 | bg pick Image Preview in fzf | medium | — | ✅ | # S02: bg pick Image Preview in fzf — UAT

**Milestone:** M001
**Written:** 2026-03-27T07:45:28.289Z

## UAT Type

- UAT mode: artifact-driven
- Why this mode is sufficient: The slice modifies a CLI command (`8sync bg pick`) that runs fzf. The core logic — 6-field line construction, preview command string composition, placeholder correctness, and fallback selection — is fully inspectable via source analysis and unit-level mocking without requiring an interactive fzf session. End-to-end fzf preview requires a live terminal with images, which is environment-dependent; the structural checks below cover everything that can be verified non-interactively.

## Preconditions

- WezTerm config directory is the working directory (so `wezterm-bootstrap.ps1` can be dot-sourced)
- Run in a clean `pwsh -NoLogo -NoProfile` session
- `fzf` is installed (for the interactive test case; other checks do not require it)
- `wezterm` is on PATH (for the imgcat preview test; fallback test deliberately omits it)

## Smoke Test

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Read-BgCache | Select-Object -First 3"
```
Expected: Exits 0. Output is empty (no cache) or shows up to 3 cache entries. No exceptions.

---

## Test Cases

### 1. 6-field line construction is correct

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
. .\wezterm-bootstrap.ps1
\$entry = [pscustomobject]@{
    id = 'abc123'; resolution = '3840x2160'; source = 'wallhaven'
    tags = @('nature', 'landscape')
    page = 'https://wallhaven.cc/w/abc123'
    preview = 'https://th.wallhaven.cc/lg/ab/abc123.jpg'
}
\$src     = if (\$entry.source) { \$entry.source } else { 'wallhaven' }
\$preview = if (\$entry.preview) { \$entry.preview } else { '' }
\$line    = '{0}\`t{1}\`t{2}\`t{3}\`t{4}\`t{5}' -f \$entry.id, \$entry.resolution, \$src, (\$entry.tags -join ','), \$entry.page, \$preview
\$fields  = \$line -split '\`t'
Write-Host ('Field count: {0}' -f \$fields.Count)
Write-Host ('Field[4] page: {0}' -f \$fields[4])
Write-Host ('Field[5] preview: {0}' -f \$fields[5])
"
```

**Expected:**
- `Field count: 6`
- `Field[4] page: https://wallhaven.cc/w/abc123`
- `Field[5] preview: https://th.wallhaven.cc/lg/ab/abc123.jpg`
- Exit code: 0

### 2. Preview command string uses correct fzf placeholders

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
\$src = Get-Content -Raw .\modules\bg.ps1
if (\$src -match 'wezterm imgcat --width 60') { 'PASS: imgcat present' } else { 'FAIL' }
if (\$src -match 'DownloadFile.*{6}') { 'PASS: {6} placeholder' } else { 'FAIL' }
if (\$src -match 'echo {5}') { 'PASS: fallback {5}' } else { 'FAIL' }
if (\$src -match 'right:60%:wrap') { 'PASS: preview window' } else { 'FAIL' }
if (\$src -match 'finally') { 'PASS: try/finally' } else { 'FAIL' }
"
```

**Expected:** Five `PASS:` lines. No `FAIL` lines. Exit code: 0.

### 3. fzf display uses --with-nth 1,2,3 (id/resolution/source only)

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
\$src = Get-Content -Raw .\modules\bg.ps1
if (\$src -match '--with-nth 1,2,3') { 'PASS: with-nth 1,2,3' } else { 'FAIL' }
"
```

**Expected:** `PASS: with-nth 1,2,3`. Exit code: 0.

### 4. Bootstrap sources cleanly with the modified module

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Write-Host 'OK'"
```

**Expected:** `OK` printed. No errors or exceptions. Exit code: 0.

### 5. Interactive preview — live fzf with thumbnail (manual, requires populated cache)

1. Run `8sync bg search nature` to populate the cache with wallhaven results.
2. Run `8sync bg pick`.
3. Use arrow keys to navigate items in the fzf list.

**Expected:**
- fzf list shows 3 columns (id, resolution, source)
- Right pane (60% width) shows a thumbnail image that updates as you navigate
- Images are rendered inline via `wezterm imgcat`
- No error messages appear in the preview pane
- Selecting an item and pressing Enter calls `Invoke-BgSet` with the selected id

### 6. Fallback when wezterm is absent

1. Temporarily rename `wezterm.exe` to make `Test-CommandExists 'wezterm'` return false, or test in an environment without WezTerm.
2. Populate cache: `8sync bg search nature`
3. Run `8sync bg pick`

**Expected:**
- fzf list opens normally
- Preview pane (down:3:wrap) shows the page URL of the highlighted item as plain text
- No errors or exceptions
- Selecting an item still works correctly

---

## Edge Cases

### Cache entry with no preview URL

1. Manually insert a cache entry with `preview = $null` or `preview = ''`.
2. Run `8sync bg pick`.

**Expected:** Field 6 is an empty string. fzf `{6}` expands to empty. The `DownloadFile` call with an empty URL will fail; the `try/finally` block catches the exception and removes the (empty) temp file. The preview pane may show an error inside the preview subprocess, but the outer fzf session continues normally.

### Large cache (100+ entries)

1. Run multiple searches to accumulate a large cache.
2. Run `8sync bg pick`.

**Expected:** All entries appear in the fzf list. Navigation and preview work normally (each preview spawns a fresh `pwsh` subprocess; no shared state).

### User cancels fzf (Escape / Ctrl+C)

1. Run `8sync bg pick`.
2. Press Escape before selecting.

**Expected:** `Invoke-BgPick` returns silently (the `if (-not $selected) { return }` guard). No background is set. No error. Exit code: 0.

---

## Failure Signals

- Any `Exception` or `Error:` output (not inside the fzf preview pane) indicates an unhandled PowerShell error
- Preview pane shows `DownloadFile` errors on every navigation: network is unavailable or preview URLs are malformed
- Preview pane is empty/black: `wezterm imgcat` is unavailable or the temp file was not created
- fzf list shows 6 columns (raw tab-delimited): `--with-nth 1,2,3` was accidentally removed
- Selecting an entry does nothing: `Invoke-BgSet -Value $selectedId` was not called, or `$selectedId` is empty

## Not Proven By This UAT

- That the downloaded thumbnail renders with correct colors/dimensions on every OS display config
- That `wezterm imgcat` correctly interprets non-JPEG preview URLs (PNG, WebP) despite the hardcoded `.jpg` temp extension
- Preview performance on slow connections (no timeout or cancellation mechanism for the download)
- Tab completion for `8sync bg pick` in a live interactive WezTerm session
- Behavior when `fzf` version is old and does not support `--preview-window` wrapping

## Notes for Tester

The preview pane spawns a fresh `pwsh -NoProfile -NonInteractive` subprocess on every cursor movement in fzf. On a fast local network this is nearly instant; on a slow connection you may see brief blank/loading states between items. This is expected behavior — there is no debounce or caching of thumbnails between items.

The `{6}` placeholder is the sixth tab-delimited field (1-indexed). If fzf ever changes its placeholder scheme, this would silently break. The test cases above verify the placeholder at the source level.
 |
| S03 | bg set Instant Reload Confirmation | low | — | ✅ | # S03: bg set Instant Reload Confirmation — UAT

**Milestone:** M001
**Written:** 2026-03-27T07:49:36.756Z

## UAT Type

- UAT mode: artifact-driven
- Why this mode is sufficient: All behavior is observable via source analysis and a PowerShell syntax check. The three UX changes (reload confirmation, filename confirmation, download progress) are written to stdout in a deterministic, inspectable pattern. No interactive terminal or running WezTerm instance is required to verify correctness.

## Preconditions

- Working directory is the repo root (so `wezterm-bootstrap.ps1` can be dot-sourced)
- Run in a clean `pwsh -NoLogo -NoProfile` session to avoid contamination
- `wezterm` is on PATH (for the reload-probe test; other checks do not require it)

## Smoke Test

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
  \$errors = \$null
  \$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'modules/bg.ps1').Path, [ref]\$null, [ref]\$errors)
  if (\$errors.Count -eq 0) { Write-Host 'PASS: zero syntax errors' } else { Write-Host ('FAIL: ' + \$errors.Count + ' errors') }
"
```
Expected: `PASS: zero syntax errors`. Exit code 0.

---

## Test Cases

### 1. Try-ReloadWezTerm uses list-clients probe (not phantom reload)

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
  \$src = Get-Content -Raw 'modules/bg.ps1'
  if (\$src -match 'list-clients')         { 'PASS: list-clients probe present' }   else { 'FAIL: list-clients missing' }
  if (\$src -match 'reload-configuration') { 'FAIL: phantom subcommand still present' } else { 'PASS: no phantom reload-configuration' }
  if (\$src -match 'Config reloaded')      { 'PASS: Config reloaded message present' }  else { 'FAIL: Config reloaded message missing' }
  if (\$src -match 'Manual reload needed') { 'PASS: Manual reload fallback present' }   else { 'FAIL: Manual reload fallback missing' }
"
```

**Expected:** Four `PASS:` lines. No `FAIL` lines. Exit code: 0.

### 2. Invoke-BgSet prints filename confirmation

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
  \$src = Get-Content -Raw 'modules/bg.ps1'
  if (\$src -match 'Background set') { 'PASS: Background set confirmation present' } else { 'FAIL: Background set confirmation missing' }
"
```

**Expected:** `PASS: Background set confirmation present`. Exit code: 0.

### 3. Save-BgFromUrl prints download progress

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
  \$src = Get-Content -Raw 'modules/bg.ps1'
  if (\$src -match 'Downloading') { 'PASS: Downloading progress present' } else { 'FAIL: Downloading progress missing' }
  if (\$src -match 'Downloaded')  { 'PASS: Downloaded confirmation present' } else { 'FAIL: Downloaded confirmation missing' }
"
```

**Expected:** Two `PASS:` lines. Exit code: 0.

### 4. wezterm CLI has no reload subcommand (factual confirmation)

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
  \$help = (wezterm cli --help 2>&1) -join ' '
  if (\$help -match 'reload') { 'FAIL: unexpected reload subcommand found' } else { 'PASS: no reload subcommand (expected)' }
"
```

**Expected:** `PASS: no reload subcommand (expected)`. Exit code: 0.

### 5. Bootstrap sources cleanly with modified module

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Write-Host 'OK'"
```

**Expected:** `OK` printed. No errors or exceptions. Exit code: 0.

### 6. bg set confirmation and reload message appear in correct order (runtime)

1. Ensure `bg/` directory contains at least one `.jpg` file.
2. Run:
```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; 8sync bg set <existing-filename.jpg>"
```
3. **Expected output (in order):**
   - `  Background set: <filename>` (Green)
   - `  Glass adaptive hint: ...` (DarkGray)
   - Either `  Config reloaded.` (Green, if WezTerm is running) or `  Manual reload needed (Ctrl+Shift+R)` (DarkYellow)
   - Exit code: 0

### 7. Download progress appears for URL-sourced backgrounds (runtime)

1. Run:
```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; 8sync bg set https://example.com/test.jpg"
```
2. **Expected output (in order):**
   - `  Downloading test.jpg...` (DarkGray) — before the network request
   - `  Downloaded: test.jpg (N KB)` (DarkGray) — after success, or `WARNING: Failed to download image: test.jpg` on failure
   - Exit code: 0 (even on download failure — warning is non-fatal)

---

## Edge Cases

### WezTerm not running — manual reload hint

1. Ensure WezTerm is not running (or rename `wezterm.exe` temporarily).
2. Run `8sync bg set <existing-file>`.
3. **Expected:** `  Manual reload needed (Ctrl+Shift+R)` printed in DarkYellow. No exception. Exit code: 0.

### WezTerm running — live reload confirmation

1. Ensure WezTerm is running with the config loaded.
2. Run `8sync bg set <existing-file>`.
3. **Expected:** `  Config reloaded.` printed in Green. The WezTerm window updates its background immediately (file-watcher triggered by `Write-CurrentBgLua`).

### Download failure for URL-sourced background

1. Run `8sync bg set https://this-url-does-not-exist.example.com/image.jpg`.
2. **Expected:** `  Downloading ...` printed, then `WARNING: Failed to download image: image.jpg`. `Invoke-BgSet` falls through to `if (-not \$finalPath)` guard and prints `Failed to set background.` No crash. Exit code: 0.

---

## Failure Signals

- Any `Exception` or unhandled error output from the bootstrap session
- `reload-configuration` appearing in `modules/bg.ps1` (phantom subcommand that was removed)
- No `  Background set:` line after `8sync bg set <file>` completes
- `  Config reloaded.` printed even when WezTerm is not running (liveness probe bypass)
- Download progress lines missing when `8sync bg set <url>` is run

## Not Proven By This UAT

- That WezTerm's file-watcher picks up the new `current-bg.lua` within a specific time bound
- That the background image actually renders in the WezTerm window after reload (visual confirmation)
- Behavior when `wezterm cli list-clients` hangs (no timeout is applied to the probe)
- Download progress for very large images (>10 MB) — Invoke-WebRequest buffer behavior untested at scale

## Notes for Tester

The "Config reloaded." message is confirmed by WezTerm liveness only — it does not wait for or confirm WezTerm's internal reload cycle. The actual reload is triggered by the file-watcher detecting the write to `current-bg.lua`; the message is printed immediately after the liveness check returns, which happens after the file write. In practice these are effectively simultaneous on a local machine.
 |

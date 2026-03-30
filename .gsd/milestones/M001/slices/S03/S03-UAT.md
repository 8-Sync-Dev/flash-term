# S03: bg set Instant Reload Confirmation — UAT

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

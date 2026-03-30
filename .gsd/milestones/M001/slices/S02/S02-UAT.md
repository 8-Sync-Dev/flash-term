# S02: bg pick Image Preview in fzf — UAT

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

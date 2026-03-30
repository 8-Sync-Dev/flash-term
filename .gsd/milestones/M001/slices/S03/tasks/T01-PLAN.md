---
estimated_steps: 16
estimated_files: 1
skills_used: []
---

# T01: bg set confirmation message + reliable reload

1. Read Invoke-BgSet and Try-ReloadWezTerm in modules/bg.ps1.

2. In Invoke-BgSet, after a successful write:
   - Print: Write-Host ('  Background set: {0}' -f (Split-Path $finalPath -Leaf)) -ForegroundColor Green
   - Then call Try-ReloadWezTerm
   - Try-ReloadWezTerm currently does: `wezterm cli reload` if available, else prints 'Press Ctrl+Shift+R'
   - The issue: `wezterm cli reload` may not exist (it's not a real wezterm CLI subcommand). The actual reload command is `wezterm cli reload-configuration` — check which one works.

3. Fix Try-ReloadWezTerm:
   - Try `wezterm cli reload-configuration` first (correct command name)
   - Fall back to `wezterm cli list-clients` (no-op but confirms CLI is alive)
   - If both fail, print: 'Press Ctrl+Shift+R to reload config'
   - Print reload outcome clearly: 'Config reloaded' or 'Manual reload needed (Ctrl+Shift+R)'

4. In the download path (Save-BgFromUrl), add a simple progress indicator:
   Write-Host ('  Downloading {0}...' -f $FileNameHint) -ForegroundColor DarkGray
   after the Invoke-WebRequest call succeeds:
   Write-Host ('  Downloaded: {0} ({1} KB)' -f $FileNameHint, [math]::Round((Get-Item $target).Length/1024,1)) -ForegroundColor DarkGray

5. Ensure error on download failure is explicit: already warns, but add the filename to the message.

## Inputs

- `modules/bg.ps1`

## Expected Output

- `modules/bg.ps1 updated: Invoke-BgSet confirmation message, Try-ReloadWezTerm fixed reload command, Save-BgFromUrl progress`

## Verification

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& wezterm cli --help 2>&1"

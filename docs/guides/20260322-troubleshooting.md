# Troubleshooting Guide

## 1. `Couldn't find manifest for 'lazygit'`

**Cause:** `lazygit` lives in the Scoop `extras` bucket, not `main`.
On a fresh machine the extras bucket is not added by default.

**Fix (automatic):** `8sync sync` now calls `Ensure-ScoopBuckets` which adds
`extras` automatically before installing.

**Fix (manual):**
```powershell
scoop bucket add extras
scoop install lazygit
```

---

## 2. `ERROR 'fzf' isn't installed` after `8sync sync`

**Cause:** `scoop install` succeeds, but `scoop update` runs immediately after
in the same process. The newly added shims are in `~/scoop/shims/` but that path
is not yet in the current process's `$env:PATH`.

**Fix (automatic):** `8sync sync` calls `Ensure-PreferredPaths` after install,
then only updates tools where `Test-CommandExists` passes.

**Fix (manual):** Open a new terminal tab and run `8sync sync` again.

---

## 3. ANSI escape code spam on terminal (`[555;128M[222;3M...`)

**Cause:** The clean spinner uses `[System.Console]::Write` with `\r` to overwrite
the same line. On SSH sessions, tmux, or terminals where `WindowSize.Width`
returns a value outside `20..300`, the spinner writes strings hundreds of chars
wide and clobbers in-flight ANSI sequences from starship.

**Fix (automatic):** The spinner now checks `WindowSize.Width` at init time.
If width is outside `20..300` the spinner is disabled entirely for that session.

**Fix (manual):** If you still see this, run:
```powershell
$Host.UI.RawUI.WindowSize.Width   # should return 80-220
```
If it returns 0 or >300 your terminal is reporting incorrect dimensions.
Resize the window and try again, or use WezTerm directly (not over SSH).

---

## 4. `Unable to find type [System.IO.EnumerationOptions]`

**Cause:** `System.IO.EnumerationOptions` requires .NET Core 2.1+. Windows
PowerShell 5.1 uses .NET Framework 4.x which does not include this class.

**Fix (automatic):** All usages replaced with `[System.IO.SearchOption]` enum
which is available since .NET Framework 2.0.

**Fix (manual):** Upgrade to PowerShell 7+:
```powershell
scoop install powershell
```

---

## 5. WezTerm starts but keybindings do not work

**Cause:** `keys.lua` failed to load (syntax error, missing file, or wrong path).
`wezterm.lua` falls back to `config.keys = {}` silently.

**Diagnose:**
```lua
-- Add temporarily to wezterm.lua to see errors:
local ok, err = pcall(dofile, wezterm.config_dir .. "\\keys.lua")
wezterm.log_info("keys.lua: " .. tostring(ok) .. " " .. tostring(err))
```

**Fix:** Check `keys.lua` syntax manually or restore from git:
```powershell
git checkout -- keys.lua
```

---

## 6. Missing-tools cache is stale (`8sync status` shows wrong state)

**Cause:** `.state/missing-cache.json` has a 5-minute TTL. If you installed
tools outside of `8sync sync` (e.g. manually via scoop), the cache may not
reflect the new state until TTL expires.

**Fix:** Delete the cache file to force a fresh scan on next shell open:
```powershell
Remove-Item "$HOME\.config\wezterm\.state\missing-cache.json" -Force
```
Or open a new terminal tab and wait ~5 minutes.

---

## 7. `bg rotate` does not change wallpaper

**Cause:** The bg cache is empty — no wallpapers have been searched yet.

**Fix:**
```powershell
8sync bg search nature landscape   # populate cache
8sync bg rotate on 30              # enable rotation every 30 min
8sync bg rotate now                # force rotate immediately
```

---

## 8. Scoop not found on a new machine

`8sync sync` requires Scoop. Install it first:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```
Then restart the terminal and run `8sync sync`.

---

## 9. `wezterm cli reload` fails silently

This is expected when WezTerm is not running or the CLI is not in PATH.
The bootstrap falls back to a `DarkYellow` message: "Background updated.
Reopen the tab if the image did not refresh."
WezTerm's `automatically_reload_config = true` picks up file changes on its own.

---

## 10. PS version warning at shell startup

```
[8sync] PowerShell 5.0.x detected. Minimum supported: 5.1.
```

**Fix:** Update to PS 5.1 (built-in on Windows 10/11) or install pwsh 7+:
```powershell
scoop install powershell
```
The shell continues to load — only some features may behave unexpectedly.

---

## 11. `8sync opencode` exported bundle but target machine cannot run `npm i`

**Cause:** Node/npm is not installed on target machine.

**Fix:** install nvm via Scoop, then install/use Node version:

```powershell
scoop install nvm
nvm install <version>
nvm use <version>
npm i
```

**Notes:**
- `8sync opencode` intentionally excludes `node_modules/` so `npm i` must run on target machine.
- Also excludes `lib/`, `*.ps1`, `*.py` by design for portable transfer.

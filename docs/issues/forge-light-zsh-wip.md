# forge light-zsh: known issues & WIP notes

> Created: 2026-04-23  
> Branch: main  
> Related files: `modules/forge.ps1`, `modules/shell.ps1`

---

## Root problem being fixed

After Forge streams a long AI response into the terminal, **every keystroke** in the zsh prompt becomes visibly sluggish (multi-hundred-ms stall) from the **2nd message onward**.

Root cause chain:
1. `robbyrussell` (oh-my-zsh default theme) calls `git status` on every prompt render.
2. `zsh-syntax-highlighting` re-parses the **entire scrollback buffer** (not just the current line) on every keystroke.
3. `zsh-autosuggestions` rescans history against the growing buffer.
4. Combined, these three plugins turn a 3000-char AI response into O(n) per keypress.

---

## What was done in this commit

| Item | Status |
|---|---|
| `Get-ForgeManagedOmzBlock` — v2 block with `FORGE_LIGHT_ZSH=1` branch | done |
| `Ensure-ZshrcSourcesOmz` — detects v1 block, migrates to v2 automatically | done |
| `Invoke-ForgeLightMode` — standalone `8sync forge lightmode` command | done |
| `Invoke-ForgeEnterZsh` — sets `FORGE_LIGHT_ZSH=1` before spawning zsh | done |
| Tab completion: `lightmode`, `light-mode`, `light` added to `shell.ps1` | done |
| Help row for `8sync forge lightmode` in `Show-ForgeHelp` | done |
| Dispatcher entries (`Invoke-ForgeCommand`) for all 3 aliases | done |

### v2 managed block summary

When `FORGE_LIGHT_ZSH=1`:
- `ZSH_THEME=""` — disables robbyrussell (no `git status` per prompt)
- `plugins=()` — no omz `git` plugin (removes slow git aliases + completion)
- `DISABLE_UNTRACKED_FILES_DIRTY="true"` — guard in case plugins are re-added later
- `ZSH_HIGHLIGHT_MAXLENGTH=60` — syntax-highlighting only parses first 60 chars of buffer
- `ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20` — stops autosuggestions on long buffers
- `ZSH_AUTOSUGGEST_MANUAL_REBIND=1` — disables hook rebind on every precmd
- `PROMPT='%n %1~ %# '` / `RPROMPT=''` set after omz loads (bare, fast prompt)

---

## Known issues / not yet done

### 1. Forge's own plugin block is NOT patched

**File:** `modules/forge.ps1` — `Invoke-ForgeEnterZsh` area  
**Problem:** Forge installs its own `.zshrc` plugin block (Forge-managed section, separate from the oh-my-zsh block). That block may re-enable `zsh-syntax-highlighting` or `zsh-autosuggestions` by sourcing them directly, bypassing the `ZSH_HIGHLIGHT_MAXLENGTH` / `ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE` caps.  
**Why it matters:** `ZSH_HIGHLIGHT_MAXLENGTH` must be set **before** the plugin's `source` line executes. If Forge's plugin block sources `zsh-syntax-highlighting.zsh` after our v2 block and the var is not exported, the cap is silently ignored.  
**Status:** Not verified against all Forge versions. The comment in the code says "These env vars are read by Forge's own plugin block at init time" but this is an assumption, not a tested assertion.  
**Fix needed:** Read Forge's actual installed plugin block and confirm the env vars are honoured, or explicitly set `ZSH_HIGHLIGHT_MAXLENGTH` again just before Forge's plugin source line.

---

### 2. `ZSH_AUTOSUGGEST_MANUAL_REBIND` only works with zsh-autosuggestions >= 0.6.0

**File:** `modules/forge.ps1` — `Get-ForgeManagedOmzBlock`  
**Problem:** `ZSH_AUTOSUGGEST_MANUAL_REBIND` was introduced in zsh-autosuggestions v0.6.0. Older installs silently ignore it and still rebind on every precmd.  
**Status:** No version guard or warning is emitted if the installed version is older.  
**Fix needed:** Add a version check inside the zsh block (or in `Invoke-ForgeLightMode`) that warns if `$ZSH_CUSTOM/plugins/zsh-autosuggestions` is present but older than 0.6.0.

---

### 3. v1 → v2 migration regex does not handle Windows CRLF correctly in all edge cases

**File:** `modules/forge.ps1` — `Ensure-ZshrcSourcesOmz`, line ~592  
**Problem:** The strip regex is:
```
(?s)# --- Oh My Zsh \(managed by 8sync forge zsh\) ---.*?# --- end Oh My Zsh ---\r?\n?
```
This handles a single trailing CRLF but not a double-blank-line `\r\n\r\n` that some editors append. If the user's `.zshrc` was created on Windows and has CRLF throughout, the combined result after strip + prepend may have mixed `\n` / `\r\n` line endings.  
The write path normalises via `$combined -replace "\`r\`n", "\`n"` but the regex strip runs **before** normalisation, so a residual `\r\n` after the end marker is only partially consumed.  
**Impact:** Minor — causes a single blank line artefact at the migration seam. Not a correctness bug.  
**Fix needed:** Run the CRLF normalisation **before** the v1 strip regex, or extend the regex to `\r?\n(\r?\n)?`.

---

### 4. No rollback path if write fails mid-migration

**File:** `modules/forge.ps1` — `Ensure-ZshrcSourcesOmz`, lines 602–619  
**Problem:** A `.bak-8sync-<timestamp>` backup is created before writing. However, if the write fails partway (disk full, AV lock), the backup exists but there is no automatic restore. The user is left with a truncated `.zshrc` and must manually copy the backup back.  
**Status:** The error message only prints the exception; it does not print the backup path.  
**Fix needed:**
1. Print the backup path in the error message so the user can recover.
2. Optionally: attempt `Copy-Item $backup $zshrc -Force` inside the catch block.

---

### 5. `Invoke-ForgeLightMode` checks only for `.oh-my-zsh` directory — not for zsh binary

**File:** `modules/forge.ps1` — `Invoke-ForgeLightMode`  
**Problem:** The guard only verifies that `$USERPROFILE\.oh-my-zsh` exists. It does not check that a zsh binary is available (via `Test-CommandExists 'zsh'` or the msys2 path). The user could have oh-my-zsh installed but a broken or missing zsh, and the command would still proceed and report success.  
**Fix needed:** Add `if (-not (Get-ZshExePath)) { Write-Host '[error] zsh binary not found ...'; return }` before the `Ensure-ZshrcSourcesOmz` call.

---

### 6. `FORGE_LIGHT_ZSH` is not restored to its original value on zsh exit if it was already set

**File:** `modules/forge.ps1` — `Invoke-ForgeEnterZsh`  
**Problem:** The code saves `$prev.FORGE_LIGHT_ZSH` and restores it on exit. However, the save happens with `$env:FORGE_LIGHT_ZSH` which may be `$null`. After zsh exits, the restore sets `$env:FORGE_LIGHT_ZSH = $null`, which in PowerShell removes the variable from the process environment — correct behaviour. BUT if the user had `FORGE_LIGHT_ZSH=0` (explicitly opted out) before entering, `'0'` is a truthy non-empty string in zsh but the v2 block checks `[[ -n "$FORGE_LIGHT_ZSH" ]]`, so `FORGE_LIGHT_ZSH=0` would **still** activate light mode.  
**Status:** Edge case — unlikely in practice since the variable is 8sync-internal. The force-set `if (-not $env:FORGE_LIGHT_ZSH) { $env:FORGE_LIGHT_ZSH = '1' }` only sets it when absent or empty, so `FORGE_LIGHT_ZSH=0` is passed through as-is into zsh and will incorrectly trigger light mode.  
**Fix needed:** Change the zsh check from `[[ -n "$FORGE_LIGHT_ZSH" ]]` to `[[ "$FORGE_LIGHT_ZSH" == "1" ]]` so that an explicit `0` opts out.

---

## Quick reference: how to verify after a fix

```powershell
# 1. Upgrade .zshrc to v2 without full reinstall
8sync forge lightmode

# 2. Enter zsh in light mode
8sync forge enter

# 3. Inside zsh -- confirm env var is set
echo $FORGE_LIGHT_ZSH     # should print 1

# 4. Type a long string (> 60 chars) -- syntax highlight should NOT repaint
# 5. Exit and confirm env var is restored in PowerShell
exit
echo $env:FORGE_LIGHT_ZSH  # should be empty (or original value)
```

---

## Files changed in this WIP commit

| File | Lines changed | Description |
|---|---|---|
| `modules/forge.ps1` | +142 / -20 | v2 block, migration logic, lightmode command, enter zsh update |
| `modules/shell.ps1` | +1 / -1 | add lightmode/light-mode/light to forge tab completion |

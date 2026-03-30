# Project: WezTerm Configuration

A WezTerm terminal configuration for Windows 11 with an 8sync toolkit — a rich PowerShell-based
CLI for managing backgrounds, GPU acceleration, themes, Helix editor integration, and shell UX.

## Current State

**Last completed milestone:** M001 (2026-03-27)
**Branch:** `milestone/M001` — ready to merge to `main`

## Completed Milestones

### M001 — GPU Status Surface + bg pick Image Preview + bg set Instant Reload Confirmation
**Completed:** 2026-03-27
**One-liner:** Delivered three UX improvements to the 8sync toolkit: enriched GPU status/verify diagnostics, wezterm imgcat thumbnail previews in bg pick's fzf pane, and instant reload confirmation with filename feedback in bg set.

**Key deliverables:**
- `modules/gpu.ps1` — New module: `8sync gpu status` (GPU name, type, front_end, power preference), `8sync gpu verify` (4 PASS/FAIL checks), `8sync gpu help`
- `modules/bg.ps1` — Enhanced: imgcat thumbnail preview in `8sync bg pick`; filename confirmation + reload outcome in `8sync bg set`; download progress in URL-sourced backgrounds
- Integration wired through `modules/startup.ps1`, `modules/shell.ps1`, `wezterm-bootstrap.ps1`

**Known follow-ups for next milestone:**
1. Fix `$PSScriptRoot` path in `Get-ActiveGpuInfo` — currently falls back to hardcoded defaults instead of reading live `wezterm.lua` values
2. Add `8sync gpu set` command to write `current-gpu.lua` from the shell
3. Consider debounce/thumbnail caching for `bg pick` preview pane

## Architecture

```
WezTerm start
  └─ wezterm.lua: reads current-bg.lua + current-opacity.lua + current-style.lua + current-gpu.lua
       └─ launches PowerShell: ". wezterm-bootstrap.ps1"
            ├─ $script:CurrentGpuLuaPath  (→ current-gpu.lua)
            ├─ Ensure-PreferredPaths
            ├─ Set-HistoryExperience (PSReadLine + fzf Ctrl+r)
            ├─ Set-ToolAliases (ll, e, lg, y, cdi, 8sync …)
            │    └─ Register-8SyncCompleter (Tab/inline completion)
            └─ Start-AutoSync (hidden background process if stale)
```

### Module Map

| File | Purpose |
|---|---|
| `modules/gpu.ps1` | 8sync gpu — GPU status, verify, help (WMI + wezterm.lua regex) |
| `modules/bg.ps1` | 8sync bg — backgrounds: search, pick (fzf+imgcat), set, rotate, list, clear, remove |
| `modules/startup.ps1` | Invoke-8Sync dispatch, auto-sync launch |
| `modules/shell.ps1` | PSReadLine config, fzf keybindings, Register-8SyncCompleter |
| `modules/theme.ps1` | 8sync theme, hx opacity |
| `modules/sync.ps1` | 8sync sync — tool version check and update |
| `modules/clean.ps1` | 8sync clean — temp file/venv/RAM cleanup |
| `modules/helix.ps1` | 8sync hx — Helix editor theme/config management |
| `modules/opencode.ps1` | 8sync opencode — oc-bundle management |
| `modules/core.ps1` | Shared helpers (Test-CommandExists, Write-HintRow, etc.) |

## Key Technical Facts

- WezTerm CLI has no GPU introspection, reload subcommand, or renderer query. Use WMI + wezterm.lua regex.
- WezTerm reloads config via file-watcher on Lua state file writes — no explicit reload command needed.
- `$PSScriptRoot` inside `modules/*.ps1` resolves to `modules/`, not the repo root. Use `Split-Path $PSScriptRoot -Parent` to reach repo root.
- fzf `{N}` placeholders are 1-indexed for tab-delimited input; `--with-nth` controls display but not `--preview` access.
- `Net.WebClient.DownloadFile` preferred over stdout piping for binary downloads in fzf preview subprocesses.

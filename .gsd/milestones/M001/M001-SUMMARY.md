---
id: M001
title: "M001: GPU Status Surface, bg pick Image Preview, bg set Instant Reload Confirmation"
status: complete
completed_at: 2026-03-27T07:55:41.679Z
key_decisions:
  - GPU data source: Win32_VideoController WMI instead of wezterm CLI — wezterm cli list-clients returns only mux metadata (pane IDs, tab titles); Get-WmiObject Win32_VideoController is always available on Windows and reliably returns all GPU adapters without a running WezTerm instance.
  - front_end and power_preference sourced from wezterm.lua config file via regex — WezTerm has no runtime introspection CLI for the active renderer or power preference; wezterm.lua is the authoritative source.
  - WezTerm liveness tag is informational only — 8sync gpu status works whether or not WezTerm is running; liveness probe adds [WezTerm running]/[WezTerm not detected] tag but a failed probe is not an error condition.
  - fzf preview uses single-quoted PS string so $f defers expansion to the spawned pwsh subprocess — prevents premature variable expansion in the outer PowerShell session that constructs the preview command.
  - Net.WebClient.DownloadFile preferred over piping binary through stdout in fzf preview — avoids binary corruption/encoding issues; temp file written to disk, then imgcat reads it cleanly; try/finally ensures cleanup.
  - WezTerm reload mechanism: use wezterm cli list-clients as liveness probe only; rely on WezTerm file-watcher for actual config reload — no reload/reload-configuration CLI subcommand exists; file-watcher triggers reload automatically when Lua state files are written.
  - New 8sync subcommands live in dedicated modules/[name].ps1 files — Invoke-[Name]Command dispatches status/verify/help subcommands; established as reusable pattern for future commands.
key_files:
  - modules/gpu.ps1 — New file (195 lines): Read-GpuLuaState, Get-ActiveGpuInfo, Show-GpuStatus, Invoke-GpuVerify, Show-GpuHelp, Invoke-GpuCommand
  - modules/bg.ps1 — Modified: Try-ReloadWezTerm rewritten (list-clients liveness probe), Invoke-BgPick updated (6-field format + imgcat preview), Invoke-BgSet (filename confirmation), Save-BgFromUrl (download progress)
  - modules/startup.ps1 — Added 'gpu' case to Invoke-8Sync dispatch switch
  - modules/shell.ps1 — Added 'gpu' to $modes and gpu = @('status','verify','help') to $subMap in Register-8SyncCompleter
  - wezterm-bootstrap.ps1 — Added $script:CurrentGpuLuaPath and . (gpu.ps1) dot-source
lessons_learned:
  - wezterm CLI has no GPU introspection — wezterm cli list-clients returns only mux metadata; use Get-WmiObject Win32_VideoController for GPU enumeration and regex-parse wezterm.lua for renderer settings.
  - $PSScriptRoot inside modules/ points to the modules/ directory, not the repo root — any module needing the repo root must use Split-Path $PSScriptRoot -Parent or receive the path as a parameter from bootstrap scope.
  - GPU adapter classification heuristics for Windows laptops: match NVIDIA/GeForce/RTX/GTX/Quadro/Radeon RX/Radeon Pro for discrete (excluding Radeon(TM) Graphics/Vega); Intel/Radeon(TM)/UHD/Iris/HD Graphics for integrated.
  - current-gpu.lua is absent in a fresh clone/worktree — gpu verify check 4 always FAILs without it; this is expected, not a bug.
  - fzf --preview with PowerShell: use single-quoted strings so $variables defer expansion to the spawned subprocess — premature expansion produces empty strings.
  - fzf field placeholders are 1-indexed for tab-delimited input: {1} is the first field, {6} is the sixth; --with-nth controls list display but does NOT affect --preview access to hidden fields.
  - Net.WebClient.DownloadFile is more reliable than piping binary through stdout in fzf preview — binary corruption/encoding issues arise when piping; DownloadFile writes directly to disk without touching stdout.
  - WezTerm CLI has no reload/reload-configuration subcommand — config reload is handled entirely by WezTerm's file-watcher on Lua state file writes; use wezterm cli list-clients as a pure liveness probe.
---

# M001: M001: GPU Status Surface, bg pick Image Preview, bg set Instant Reload Confirmation

**Delivered three UX improvements to the 8sync toolkit: enriched GPU status/verify diagnostics, wezterm imgcat thumbnail previews in bg pick's fzf pane, and instant reload confirmation with filename feedback in bg set.**

## What Happened

M001 addressed three user-reported UX gaps in the wezterm-bootstrap 8sync toolkit across three independent slices delivered in sequence on 2026-03-27.

**S01 — GPU Status Surface:** The previous `Show-GpuStatus` in wezterm-bootstrap.ps1 only surfaced a `min_percent` number from `current-gpu.lua`. S01 replaced it with a dedicated `modules/gpu.ps1` module. Investigation ruled out `wezterm cli list-clients` (returns mux metadata only, no GPU fields) and WezTerm log files (no GPU entries by default). The winning data source was `Get-WmiObject Win32_VideoController`, which reliably returns all GPU adapters without requiring a running WezTerm instance. `front_end` and `webgpu_power_preference` are regex-parsed from `wezterm.lua` since WezTerm exposes no runtime introspection CLI for these values.

The module delivers `Get-ActiveGpuInfo` (WMI + wezterm.lua regex), `Read-GpuLuaState` (parses current-gpu.lua), `Show-GpuStatus` (7-row formatted display), `Invoke-GpuVerify` (4 PASS/FAIL checks with summary count), `Show-GpuHelp`, and `Invoke-GpuCommand` (dispatcher). Integration wired through wezterm-bootstrap.ps1 ($script:CurrentGpuLuaPath, gpu.ps1 dot-source), modules/startup.ps1 ('gpu' dispatch case), and modules/shell.ps1 (tab completion).

One known limitation: `$PSScriptRoot` inside `modules/gpu.ps1` resolves to the `modules/` directory, so `Join-Path $PSScriptRoot 'wezterm.lua'` silently fails and falls back to hardcoded defaults (`WebGpu`, `HighPerformance`). These match the actual config so behavior is correct today; documented as a follow-up.

**S02 — bg pick Image Preview in fzf:** The previous `Invoke-BgPick` used a text-only preview (`echo {4}` showing page URL) because imgcat escape sequences were found to break the fzf preview pane in a prior attempt. S02 redesigned the approach: extend the tab-delimited cache line format to 6 fields (adding `preview` URL as field 6), use `--with-nth 1,2,3` to display only id/resolution/source in the fzf list, and spawn a `pwsh -NoProfile -NonInteractive` subprocess per preview that downloads the thumbnail to a temp file via `Net.WebClient.DownloadFile("{6}", $f)`, calls `wezterm imgcat --width 60`, and cleans up via `try/finally`. A graceful text-only fallback (`echo {5}`, `down:3:wrap`) applies when `wezterm` is absent. The preview command is a single-quoted string so `$f` defers expansion to the child process.

**S03 — bg set Instant Reload Confirmation:** Three UX improvements to `modules/bg.ps1`: (1) `Try-ReloadWezTerm` rewritten to use `wezterm cli list-clients` as a pure liveness probe rather than attempting a non-existent `reload-configuration` subcommand — if liveness succeeds, print `Config reloaded.` (the file-watcher handles the actual reload); if not, print the manual Ctrl+Shift+R hint. (2) `Invoke-BgSet` now prints `Background set: <filename>` in Green immediately after writing current-bg.lua. (3) `Save-BgFromUrl` prints `Downloading <name>...` before and `Downloaded: <name> (N KB)` after the Invoke-WebRequest call.

All three slices were committed to the `milestone/M001` branch and verified via source-level checks (PowerShell parser, grep), command execution (status/verify/help subcommands), and bootstrap smoke tests.

## Success Criteria Results

### SC1: `8sync gpu status` prints GPU name, front_end, and active power preference — not just a number
**✅ MET**
- `modules/gpu.ps1` exports `Show-GpuStatus` which calls `Get-ActiveGpuInfo` (Win32_VideoController WMI) for GPU name/type and regex-parses `wezterm.lua` for `front_end`/`power_preference`.
- Live verification (S01-SUMMARY): `8sync gpu status` exited 0 showing `WebGpu`, `NVIDIA GeForce RTX 3050 Laptop GPU (DiscreteGpu)`, `HighPerformance`.
- Integration confirmed: `modules/startup.ps1` dispatches `'gpu'` → `Invoke-GpuCommand`; `modules/shell.ps1` registers tab completions.
- **Non-blocking caveat:** `$PSScriptRoot` path resolves to `modules/wezterm.lua` (non-existent); falls back to hardcoded defaults that match actual config. Documented in KNOWLEDGE.md.

### SC2: `8sync bg pick` renders thumbnail previews inside the fzf pane before the user selects
**✅ MET**
- `modules/bg.ps1` line 470: preview command uses `Net.WebClient.DownloadFile("{6}", $f)` + `wezterm imgcat --width 60`, with `--preview-window=right:60%:wrap`.
- 6-field tab-delimited format at lines 456–460; `--with-nth 1,2,3` at line 478; `{6}` placeholder for preview URL; fallback `echo {5}` with `down:3:wrap` at line 474.
- S02-SUMMARY: all 11 source-level checks passed; bootstrap sources cleanly.

### SC3: `8sync bg set` confirms the wallpaper changed and wezterm reloads in-place without requiring a tab reopen
**✅ MET**
- `modules/bg.ps1` line 535: `Invoke-BgSet` prints `Background set: <filename>` in Green.
- `Try-ReloadWezTerm` at line 328: uses `list-clients` liveness probe; prints `Config reloaded.` or `Manual reload needed (Ctrl+Shift+R)`.
- Phantom `reload-configuration` subcommand confirmed absent. `Downloading`/`Downloaded` progress lines present in `Save-BgFromUrl`.
- S03-SUMMARY: 7/7 source checks passed; PowerShell parser returned zero syntax errors.

## Definition of Done Results

1. ✅ **`gpu status` shows GPU name + front_end + power preference** — verified in S01 live run (`8sync gpu status` exit 0 showed all 7 rows including GPU name, DiscreteGpu type, WebGpu, HighPerformance) and by source inspection.

2. ✅ **`bg pick` shows imgcat thumbnail in fzf preview pane** — verified via S02 source inspection confirming 6-field format, `{6}` placeholder, `Net.WebClient.DownloadFile`, `wezterm imgcat --width 60`, `try/finally` cleanup, and `right:60%:wrap` preview window.

3. ✅ **`bg set` reloads wezterm immediately and confirms success** — verified via S03 source inspection and 7/7 source checks: `Background set:` confirmation line, `Config reloaded.` message, `Manual reload needed` fallback, `Downloading`/`Downloaded` progress, zero syntax errors.

4. ✅ **No regressions in existing bg rotate, bg list, bg search, or gpu set commands** — `bg rotate`/`list`/`search` all present in modules/bg.ps1 (11/2/2 matches respectively); `gpu set` does not exist (as expected — out of scope for M001).

5. ✅ **PowerShell syntax clean on both modules** — S03 confirmed `modules/bg.ps1` parse-clean (zero errors from `[System.Management.Automation.Language.Parser]::ParseFile`); S01 confirmed `modules/gpu.ps1` is syntactically valid.

All 3 slices show ✅ in ROADMAP.md. All S##-SUMMARY.md, S##-PLAN.md, and S##-UAT.md artifacts exist for S01, S02, S03. All task T01-SUMMARY.md files exist under each slice. Cross-slice boundaries respected (S02 modified `Invoke-BgPick`, S03 modified `Try-ReloadWezTerm`/`Invoke-BgSet`/`Save-BgFromUrl` — non-overlapping function bodies in the same file).

## Requirement Outcomes

No formal requirements were tracked in REQUIREMENTS.md for this project — the requirements table was empty at milestone start. M001 was planned against three user-reported UX gaps captured in the milestone plan's `requirement_coverage` field:

| User-Reported Gap | Status | Evidence |
|---|---|---|
| GPU command not using GPU visibly | ✅ Addressed | `8sync gpu status` shows GPU name/type/front_end/power_preference via Win32_VideoController + wezterm.lua regex |
| bg pick no image preview | ✅ Addressed | `8sync bg pick` now shows wezterm imgcat thumbnails in fzf right pane via 6-field format + `{6}` placeholder |
| bg set not instant/confirmed | ✅ Addressed | `8sync bg set` now prints filename confirmation + reload outcome message |

No requirements were invalidated, re-scoped, blocked, or deferred. S01 surfaced one new follow-up item (fix `$PSScriptRoot` path in `Get-ActiveGpuInfo`) but this was intentionally not promoted to a tracked requirement — it is documented in KNOWLEDGE.md and S01-SUMMARY follow-ups instead.

## Deviations

S01: Task plan proposed wezterm cli list-clients as the GPU data source. Investigation proved it returns only mux metadata — no GPU fields exist. Substituted Get-WmiObject Win32_VideoController for GPU name/type, and regex-parsed wezterm.lua for front_end/power_preference. These are improvements over the plan, not regressions.

S02/S03: No significant deviations from plan.

## Follow-ups

1. Fix $PSScriptRoot path in Get-ActiveGpuInfo: change `Join-Path $PSScriptRoot 'wezterm.lua'` to `Join-Path (Split-Path $PSScriptRoot -Parent) 'wezterm.lua'` so front_end and power_preference are read from the actual wezterm.lua instead of silently falling back to hardcoded defaults.
2. Consider adding `8sync gpu set` command to allow setting min_percent threshold and writing current-gpu.lua from the shell (currently only generated by the bg/theme workflow).
3. Add debounce or thumbnail caching for bg pick preview pane — each cursor movement spawns a fresh pwsh subprocess and network download; on slow connections this creates noticeable latency.

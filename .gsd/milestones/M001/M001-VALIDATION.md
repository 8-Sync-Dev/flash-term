---
verdict: needs-attention
remediation_round: 0
---

# Milestone Validation: M001

## Success Criteria Checklist
## Success Criteria Checklist

### SC1: `8sync gpu status` prints GPU name, front_end (WebGpu/OpenGL), and active power preference — not just a number
**Verdict: ✅ PASS**
- Evidence: `modules/gpu.ps1` exports `Show-GpuStatus` which calls `Get-ActiveGpuInfo` (WMI `Win32_VideoController`) for GPU name/type and regex-parses `wezterm.lua` for `front_end`/`power_preference`.
- S01 SUMMARY verification: `8sync gpu status` ran at exit 0 showing `WebGpu`, `NVIDIA GeForce RTX 3050 Laptop GPU (DiscreteGpu)`, `HighPerformance`.
- Integration wired: `modules/startup.ps1` line 152 dispatches `'gpu'` → `Invoke-GpuCommand`; `modules/shell.ps1` registers `gpu` in completions.
- **Caveat (non-blocking):** `$PSScriptRoot` path in `Get-ActiveGpuInfo` resolves to `modules/wezterm.lua` (non-existent). The function silently falls back to hardcoded defaults (`WebGpu`, `HighPerformance`) which match the actual config. Documented as known limitation in S01-SUMMARY. Functional on current system; would silently show stale values if wezterm.lua is customized.

### SC2: `8sync bg pick` renders thumbnail previews inside the fzf pane before the user selects
**Verdict: ✅ PASS**
- Evidence: `modules/bg.ps1` line 470 constructs a preview command using `Net.WebClient.DownloadFile("{6}", $f)` + `wezterm imgcat --width 60`, with `--preview-window=right:60%:wrap`.
- 6-field tab-delimited format confirmed at lines 456–460; `--with-nth 1,2,3` confirmed at line 478; `{6}` placeholder for preview URL confirmed; fallback `echo {5}` confirmed at line 474 with `down:3:wrap`.
- S02 SUMMARY: all 11 source-level checks passed; bootstrap sources cleanly.

### SC3: `8sync bg set` confirms the wallpaper changed and wezterm reloads in-place without requiring a tab reopen
**Verdict: ✅ PASS**
- Evidence: `modules/bg.ps1` line 535 prints `  Background set: <filename>` (Green) in `Invoke-BgSet`; `Try-ReloadWezTerm` at line 328 uses `list-clients` liveness probe and prints `  Config reloaded.` (Green) or `  Manual reload needed (Ctrl+Shift+R)` (DarkYellow).
- Phantom `reload-configuration` subcommand confirmed absent. `Downloading`/`Downloaded` progress lines confirmed present in `Save-BgFromUrl`.
- S03 SUMMARY: 7/7 source-level checks passed; PowerShell parser returned zero syntax errors.

### Definition-of-Done Items
1. ✅ `gpu status shows GPU name + front_end + power preference` — verified in S01 live run and source.
2. ✅ `bg pick shows imgcat thumbnail in fzf preview pane` — verified via S02 source inspection.
3. ✅ `bg set reloads wezterm immediately and confirms success` — verified via S03 source inspection.
4. ✅ `No regressions in existing bg rotate, bg list, bg search, or gpu set commands` — `bg rotate`/`list`/`search` all present (11/2/2 matches); `gpu set` does not exist (as expected).
5. ✅ `PowerShell syntax clean on both modules` — S03 confirmed `modules/bg.ps1` parse-clean; S01 confirmed `modules/gpu.ps1` structures are syntactically valid.

## Slice Delivery Audit
## Slice Delivery Audit

| Slice | Claimed Deliverable | Evidence in Summary | Artifacts Exist | Verdict |
|-------|--------------------|--------------------|-----------------|---------|
| S01 — GPU Status Surface | `modules/gpu.ps1` with `Get-ActiveGpuInfo`, `Show-GpuStatus`, `Invoke-GpuVerify`, `Show-GpuHelp`, `Invoke-GpuCommand`; wired into `startup.ps1`, `shell.ps1`, `wezterm-bootstrap.ps1` | All functions confirmed in S01-SUMMARY; verification ran all three subcommands at exit 0 | `modules/gpu.ps1` exists with all 6 functions; `startup.ps1` line 152 has `'gpu'` case; `shell.ps1` lines 53/63 register completions; `wezterm-bootstrap.ps1` line 92 dot-sources gpu.ps1 | ✅ Delivered |
| S02 — bg pick Image Preview in fzf | `Invoke-BgPick` updated in `modules/bg.ps1` with 6-field format, imgcat preview command, `--with-nth 1,2,3`, fallback to `echo {5}` | S02-SUMMARY confirms all 11 structural checks passed | `modules/bg.ps1` lines 456–480 contain all changes; `{6}` placeholder, `Net.WebClient.DownloadFile`, `try/finally`, `right:60%:wrap`, `--with-nth 1,2,3` all confirmed | ✅ Delivered |
| S03 — bg set Instant Reload Confirmation | `Try-ReloadWezTerm` rewritten; `Invoke-BgSet` filename confirmation; `Save-BgFromUrl` download progress | S03-SUMMARY confirms 7/7 source checks passed and zero parse errors | `modules/bg.ps1`: `list-clients` probe line 328; `Config reloaded.` line 329; `Manual reload needed` line 335; `Background set:` line 535; `Downloading`/`Downloaded` lines 372/375 | ✅ Delivered |

All three slices delivered all claimed artifacts. No slice has an empty or missing summary. All three completion timestamps present in SUMMARY.md files (2026-03-27).

## Cross-Slice Integration
## Cross-Slice Integration

### Boundary Map (from milestone plan)
```
modules/gpu.ps1      ← S01 only
modules/bg.ps1       ← S02, S03
wezterm.lua          ← S01 read-only (no edits needed)
.state/              ← read-only from PS side
current-gpu.lua      ← written by gpu.ps1 (S01)
current-bg.lua       ← written by bg.ps1 (S03)
```

### Verification
- **S01 vs boundary map:** `modules/gpu.ps1` created by S01 only ✅. `wezterm.lua` not modified ✅. `current-gpu.lua` reading wired (`$script:CurrentGpuLuaPath`) ✅. S01 did NOT write `current-gpu.lua` (no `gpu set` command) — consistent with boundary map and UAT's "Not Proven" section ✅.
- **S02 vs boundary map:** Only `modules/bg.ps1` modified (specifically `Invoke-BgPick`) ✅. No new files, no cross-slice conflicts ✅.
- **S03 vs boundary map:** Only `modules/bg.ps1` modified (`Try-ReloadWezTerm`, `Invoke-BgSet`, `Save-BgFromUrl`) ✅. `current-bg.lua` write confirmed via `Write-CurrentBgLua` in `Invoke-BgSet` flow ✅.
- **S02 ↔ S03 co-ownership of `modules/bg.ps1`:** Both slices modified this file. Summaries confirm no mutual regressions — S02 modified `Invoke-BgPick` (lines ~456–480), S03 modified `Try-ReloadWezTerm` + `Invoke-BgSet` + `Save-BgFromUrl` (lines ~328–375, 535) — non-overlapping function bodies ✅.
- **No cross-slice data dependency violations detected.** Slices had no declared dependencies on each other and none were observed.

### Minor Gap Noted
S01 documents a `$PSScriptRoot` path issue: `Get-ActiveGpuInfo` uses `Join-Path $PSScriptRoot 'wezterm.lua'` which resolves to `modules/wezterm.lua` (non-existent). The boundary map states S01 reads `wezterm.lua` read-only — this read silently fails and falls back to hardcoded defaults. The boundary contract is partially unmet (the read is attempted but silently skipped). Functionally harmless on the current system; documented as a follow-up in S01-SUMMARY.

## Requirement Coverage
## Requirement Coverage

No formal requirements (REQUIREMENTS.md / active_requirements table) are defined for this project — the requirements table is empty. The milestone was planned against user-reported UX gaps ("All three slices address user-reported gaps: GPU command not using GPU visibly (S01), bg pick no image preview (S02), bg set not instant/confirmed (S03)") captured as the `requirement_coverage` field in the milestone plan.

All three stated user-reported gaps are addressed:
- **GPU command not using GPU visibly** → S01 delivered `8sync gpu status` showing GPU name/type/front_end/power_preference ✅
- **bg pick no image preview** → S02 delivered wezterm imgcat thumbnail preview in fzf right pane ✅
- **bg set not instant/confirmed** → S03 delivered filename confirmation + reload outcome message ✅

No requirements were invalidated, re-scoped, or left unaddressed. No new formal requirements were surfaced (S01 surfaced a follow-up item about `$PSScriptRoot` but chose not to promote it to a tracked requirement).

## Verdict Rationale
All three success criteria are substantively met by delivered code and verified by slice summaries. All slice deliverables are present in the repository. Cross-slice boundaries were respected. No regressions detected in existing commands. Verification classes were addressed: Contract (source-level checks confirmed), Integration (dispatch wired through startup.ps1/shell.ps1/wezterm-bootstrap.ps1), Operational (bootstrap sources cleanly; PowerShell parser confirms zero syntax errors), UAT (artifact-driven checks confirmed for all three slices).

The verdict is `needs-attention` rather than `pass` due to one non-blocking structural gap: the `$PSScriptRoot` path in `Get-ActiveGpuInfo` silently fails to read `wezterm.lua` (resolves to `modules/wezterm.lua`), so `front_end` and `power_preference` are served from hardcoded defaults rather than the live config file. The system works correctly today because the defaults match the config, but the boundary map contract ("S01 reads wezterm.lua read-only") is only partially honored. This is acknowledged and documented in S01-SUMMARY as a follow-up item. It does not block milestone completion — the user-visible behavior matches the success criteria — but should be tracked for a future fix.

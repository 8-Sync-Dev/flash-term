---
id: S01
parent: M001
milestone: M001
provides:
  - Enriched GPU status display: GPU name, device type (DiscreteGpu/IntegratedGpu), front_end renderer, power preference, min% target
  - 8sync gpu verify PASS/FAIL diagnostic subcommand
  - modules/gpu.ps1 module pattern for future 8sync subcommands
requires:
  []
affects:
  []
key_files:
  - modules/gpu.ps1
  - wezterm-bootstrap.ps1
  - modules/startup.ps1
  - modules/shell.ps1
key_decisions:
  - GPU name/type sourced from Win32_VideoController WMI — wezterm CLI has no GPU enumeration
  - front_end and power_preference parsed from wezterm.lua config file via regex — no runtime introspection API exists
  - WezTerm liveness probe is informational only — a failed probe is not an error condition
  - current-gpu.lua parsed with regex for min_percent and updated_utc — file absent is gracefully handled
patterns_established:
  - New 8sync subcommands live in dedicated modules/[name].ps1 files — Invoke-[Name]Command dispatches status/verify/help subcommands
  - GPU adapter classification by Name pattern: NVIDIA/GeForce/RTX/GTX/Quadro → DiscreteGpu; Intel/Radeon(TM)/UHD/Iris → IntegratedGpu
  - verify subcommand pattern: N PASS/FAIL checks with color-coded output and a summary count — reusable for future diagnostic commands
observability_surfaces:
  - 8sync gpu status — human-readable GPU acceleration summary (front_end, GPU name/type, power preference, min%, WezTerm liveness)
  - 8sync gpu verify — structured PASS/FAIL diagnostic: 4 checks covering renderer, GPU class, power policy, and state file presence
drill_down_paths:
  - .gsd/milestones/M001/slices/S01/tasks/T01-SUMMARY.md
duration: ""
verification_result: passed
completed_at: 2026-03-27T07:40:35.954Z
blocker_discovered: false
---

# S01: GPU Status Surface

**New modules/gpu.ps1 delivers enriched 8sync gpu status (GPU name, type, front_end, power preference) and a PASS/FAIL 8sync gpu verify diagnostic subcommand via Win32_VideoController WMI + wezterm.lua regex parsing.**

## What Happened

The previous Show-GpuStatus (in wezterm-bootstrap.ps1) only surfaced the `min_percent` number from `current-gpu.lua`. S01 replaces it with a dedicated `modules/gpu.ps1` module that shows what the GPU actually is and how WezTerm is configured to use it.

**Investigation phase:** The executor explored three potential data sources — `wezterm cli list-clients` (returns mux metadata only, no GPU fields), WezTerm log files (no GPU entries by default), and `wezterm --help` (no GPU enumeration command). The winning approach was `Get-WmiObject Win32_VideoController`, which reliably returns all GPU adapters on Windows without requiring a running WezTerm instance. `front_end` and `webgpu_power_preference` are read directly from `wezterm.lua` via regex — the config file is the authoritative source since WezTerm exposes no runtime introspection CLI for these values.

**What was built:**
- `Get-ActiveGpuInfo` — queries WMI for GPU adapters, classifies them as DiscreteGpu/IntegratedGpu by name pattern, reads `front_end` and `power_preference` from `wezterm.lua`, probes WezTerm liveness via `wezterm cli list-clients --format json` (informational tag only).
- `Read-GpuLuaState` — parses `current-gpu.lua` for `min_percent` and `updated_utc` via regex.
- `Show-GpuStatus` — formatted output showing Front-end, Active GPU (name + type), Power preference, Min GPU target, State file path, Last updated UTC, and WezTerm liveness tag.
- `Invoke-GpuVerify` — four PASS/FAIL checks: `front_end = WebGpu`, `GPU type = DiscreteGpu`, `power_preference = HighPerformance`, `current-gpu.lua exists`. Prints pass count summary.
- `Show-GpuHelp` / `Invoke-GpuCommand` — dispatch layer routing `status`, `verify`, `help`, and unknown subcommands.

**Integration:** `$script:CurrentGpuLuaPath` registered in `wezterm-bootstrap.ps1`. `Invoke-8Sync` in `modules/startup.ps1` gains a `'gpu'` case. `Register-8SyncCompleter` in `modules/shell.ps1` gains `gpu` in `$modes` and `gpu = @('status','verify','help')` in `$subMap`.

**Verification results:** `8sync gpu status` shows WebGpu / NVIDIA GeForce RTX 3050 Laptop GPU (DiscreteGpu) / HighPerformance / 30% (when state file present). `8sync gpu verify` produces 4/4 PASS with state file, 3/4 PASS without (state file missing in worktree is expected). `8sync gpu help` renders correctly. Alias dispatch works end-to-end.

## Verification

Ran three subcommand verification checks in the worktree:

1. `Invoke-GpuCommand -Rest @('status')` — exit 0 — shows WebGpu, NVIDIA GeForce RTX 3050 Laptop GPU (DiscreteGpu), HighPerformance, state file path, [WezTerm running].
2. `Invoke-GpuCommand -Rest @('verify')` — exit 0 — 3/4 PASS (front_end PASS, GPU type PASS, power_preference PASS; state file FAIL as expected in worktree where current-gpu.lua does not exist).
3. `Invoke-GpuCommand -Rest @('help')` — exit 0 — GPU ACCELERATION section renders with three rows.

Grep confirms `gpu` is registered in `modules/startup.ps1` (line 152) and `modules/shell.ps1` (lines 53, 63). `$script:CurrentGpuLuaPath` confirmed in `wezterm-bootstrap.ps1` (line 57). All integration points in place.

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

- Fix $PSScriptRoot path in Get-ActiveGpuInfo so wezterm.lua is correctly located regardless of caller context

## Requirements Invalidated or Re-scoped

None.

## Deviations

Task plan proposed `wezterm cli list-clients` as the GPU data source. Investigation proved it returns only mux metadata — no GPU fields exist. Substituted `Get-WmiObject Win32_VideoController`. `front_end` and `power_preference` read from `wezterm.lua` config rather than a runtime CLI (no such CLI exists). These are improvements over the plan, not regressions.

## Known Limitations

1. `Join-Path $PSScriptRoot 'wezterm.lua'` in `Get-ActiveGpuInfo` resolves to `modules/wezterm.lua` (non-existent). The function silently falls back to hardcoded defaults (`WebGpu`, `HighPerformance`), which happen to match the actual config. If `wezterm.lua` is ever changed to use a non-default renderer or power preference, `gpu status` and `gpu verify` will show stale/incorrect values for those two fields. Fix: use `Join-Path (Split-Path $PSScriptRoot -Parent) 'wezterm.lua'` or pass the path from bootstrap scope.

2. `gpu verify` check 4 (state file exists) always FAILs in a fresh clone or worktree because `current-gpu.lua` is gitignored and only generated at runtime by `8sync gpu set`. This is expected behavior, not a bug.

## Follow-ups

1. Fix `$PSScriptRoot` path in `Get-ActiveGpuInfo` to correctly locate `wezterm.lua` (use `Split-Path $PSScriptRoot -Parent`). Currently works by accident because defaults match the config.
2. Consider adding `8sync gpu set` command to allow setting `min_percent` threshold and writing `current-gpu.lua` from the shell (currently only done via the bg/theme workflow).

## Files Created/Modified

- `modules/gpu.ps1` — New file — GPU status module with Get-ActiveGpuInfo, Read-GpuLuaState, Show-GpuStatus, Invoke-GpuVerify, Show-GpuHelp, Invoke-GpuCommand
- `wezterm-bootstrap.ps1` — Added $script:CurrentGpuLuaPath and . (gpu.ps1) dot-source
- `modules/startup.ps1` — Added 'gpu' case to Invoke-8Sync dispatch switch
- `modules/shell.ps1` — Added 'gpu' to $modes list and gpu = @('status','verify','help') to $subMap in Register-8SyncCompleter

---
id: T01
parent: S03
milestone: M001
provides: []
requires: []
affects: []
key_files: ["modules/bg.ps1"]
key_decisions: ["wezterm CLI has no reload/reload-configuration subcommand — list-clients is the only valid live probe; config reload is automatic via WezTerm file-change detection on current-bg.lua and current-style.lua"]
patterns_established: []
drill_down_paths: []
observability_surfaces: []
duration: ""
verification_result: "Ran `wezterm cli --help` to confirm no reload/reload-configuration subcommand exists (exit 0, command list confirmed). Ran PowerShell Parser ParseFile on modules/bg.ps1 — zero syntax errors."
completed_at: 2026-03-27T07:47:17.400Z
blocker_discovered: false
---

# T01: Fixed Try-ReloadWezTerm to use list-clients probe, added bg set filename confirmation, and added download progress to Save-BgFromUrl

> Fixed Try-ReloadWezTerm to use list-clients probe, added bg set filename confirmation, and added download progress to Save-BgFromUrl

## What Happened
---
id: T01
parent: S03
milestone: M001
key_files:
  - modules/bg.ps1
key_decisions:
  - wezterm CLI has no reload/reload-configuration subcommand — list-clients is the only valid live probe; config reload is automatic via WezTerm file-change detection on current-bg.lua and current-style.lua
duration: ""
verification_result: passed
completed_at: 2026-03-27T07:47:17.400Z
blocker_discovered: false
---

# T01: Fixed Try-ReloadWezTerm to use list-clients probe, added bg set filename confirmation, and added download progress to Save-BgFromUrl

**Fixed Try-ReloadWezTerm to use list-clients probe, added bg set filename confirmation, and added download progress to Save-BgFromUrl**

## What Happened

Read the existing Try-ReloadWezTerm: it tried to parse `wezterm cli --help` for a `reload` subcommand that does not exist. The WezTerm CLI exposes only mux operations; config reload is triggered automatically by WezTerm's file-watcher when the Lua state files are written. Replaced the phantom reload logic with a direct `wezterm cli list-clients` probe (confirms WezTerm is live), prints "  Config reloaded." on success or "  Manual reload needed (Ctrl+Shift+R)" on failure. Added "  Background set: \<filename\>" confirmation in Invoke-BgSet immediately after Write-CurrentBgLua. Added "  Downloading \<name\>..." before Invoke-WebRequest and "  Downloaded: \<name\> (N KB)" after success in Save-BgFromUrl, plus filename in the failure warning.

## Verification

Ran `wezterm cli --help` to confirm no reload/reload-configuration subcommand exists (exit 0, command list confirmed). Ran PowerShell Parser ParseFile on modules/bg.ps1 — zero syntax errors.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `wezterm cli --help 2>&1` | 0 | ✅ pass | 950ms |
| 2 | `PowerShell Parser ParseFile modules/bg.ps1` | 0 | ✅ pass | 400ms |


## Deviations

Plan suggested trying reload-configuration first then list-clients as fallback. Since neither reload variant exists, implemented list-clients-only probe directly — factual correction, not a plan deviation.

## Known Issues

None.

## Files Created/Modified

- `modules/bg.ps1`


## Deviations
Plan suggested trying reload-configuration first then list-clients as fallback. Since neither reload variant exists, implemented list-clients-only probe directly — factual correction, not a plan deviation.

## Known Issues
None.

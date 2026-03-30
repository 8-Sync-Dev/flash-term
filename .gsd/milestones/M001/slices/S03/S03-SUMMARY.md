---
id: S03
parent: M001
milestone: M001
provides:
  - modules/bg.ps1 with corrected Try-ReloadWezTerm, bg set filename confirmation, and Save-BgFromUrl download progress
requires:
  []
affects:
  []
key_files:
  - modules/bg.ps1
key_decisions:
  - wezterm CLI has no reload/reload-configuration subcommand — list-clients is the correct liveness probe; WezTerm file-watcher handles the actual reload when Lua state files are written
patterns_established:
  - Try-ReloadWezTerm = liveness probe (list-clients) + informational message only; actual reload is file-watcher-driven
observability_surfaces:
  - bg set prints '  Background set: <filename>' (Green) + '  Config reloaded.' or '  Manual reload needed (Ctrl+Shift+R)' after each invocation
  - Save-BgFromUrl prints '  Downloading <name>...' and '  Downloaded: <name> (N KB)' to show download progress
drill_down_paths:
  - .gsd/milestones/M001/slices/S03/tasks/T01-SUMMARY.md
duration: ""
verification_result: passed
completed_at: 2026-03-27T07:49:36.755Z
blocker_discovered: false
---

# S03: bg set Instant Reload Confirmation

**bg set now prints filename confirmation and reload outcome; Try-ReloadWezTerm uses list-clients liveness probe instead of phantom reload subcommand; Save-BgFromUrl prints download progress.**

## What Happened

The slice had a single task (T01) targeting `modules/bg.ps1`.

**Problem discovered in T01:** The existing `Try-ReloadWezTerm` function tried to detect a `reload` or `reload-configuration` subcommand in `wezterm cli --help` output — a subcommand that has never existed. WezTerm exposes only mux operations via its CLI; config reload is handled automatically by WezTerm's built-in file-watcher whenever a `*.lua` state file is written to disk.

**Fix applied:** `Try-ReloadWezTerm` was rewritten to use `wezterm cli list-clients` as a pure liveness probe. If it exits 0, WezTerm is running and the file-watcher has already triggered the reload, so the function prints "  Config reloaded." in Green. If the probe fails (WezTerm not running or not in PATH), it prints "  Manual reload needed (Ctrl+Shift+R)" in DarkYellow.

**Filename confirmation:** In `Invoke-BgSet`, immediately after `Write-CurrentBgLua` writes the state file, a new line prints `  Background set: <filename>` in Green, giving the user immediate visual confirmation of which image was applied.

**Download progress:** In `Save-BgFromUrl`, two new `Write-Host` calls bracket the `Invoke-WebRequest` call: "  Downloading \<name\>..." before, and "  Downloaded: \<name\> (N KB)" after success. The failure `Write-Warning` now includes the filename. This closes a UX gap where URL-sourced backgrounds were silent during potentially slow downloads.

**Verification:** PowerShell Parser `ParseFile` on `modules/bg.ps1` returned zero syntax errors. All seven source-level checks passed (list-clients present, Background set present, Downloading/Downloaded present, no phantom reload-configuration, Config reloaded/Manual reload messages present). `wezterm cli --help` confirmed no reload subcommand exists (exit 0, command list inspected).

## Verification

1. PowerShell Parser ParseFile on modules/bg.ps1 — PASS: zero syntax errors.
2. Source grep for `list-clients` — PASS: probe present in Try-ReloadWezTerm.
3. Source grep for `Background set` — PASS: confirmation line present in Invoke-BgSet.
4. Source grep for `Downloading` / `Downloaded` — PASS: both progress lines present in Save-BgFromUrl.
5. Source grep for `reload-configuration` — PASS: no phantom subcommand call remaining.
6. Source grep for `Config reloaded` / `Manual reload needed` — PASS: both UX messages present.
7. `wezterm cli --help` — exit 0, confirmed no reload/reload-configuration subcommand in the command list.

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Deviations

T01 plan suggested trying reload-configuration first then falling back to list-clients. Since the reload-configuration subcommand does not exist in any WezTerm release, the implementation goes directly to list-clients-only. This is a factual correction, not a deviation from intent.

## Known Limitations

"Config reloaded." is printed based on WezTerm liveness (list-clients exit code), not on confirmation that WezTerm actually processed the new state file. There is no WezTerm API to wait for or confirm a config reload cycle — this is a WezTerm CLI limitation.

## Follow-ups

None discovered during execution.

## Files Created/Modified

- `modules/bg.ps1` — Try-ReloadWezTerm rewritten to use list-clients liveness probe; Invoke-BgSet adds filename confirmation line; Save-BgFromUrl adds download progress and downloaded size lines

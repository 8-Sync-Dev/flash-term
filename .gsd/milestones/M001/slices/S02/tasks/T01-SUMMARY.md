---
id: T01
parent: S02
milestone: M001
provides: []
requires: []
affects: []
key_files: ["modules/bg.ps1"]
key_decisions: ["Use single-quoted PS string for fzf --preview so $f defers expansion to the spawned subprocess", "fzf {6} placeholder (1-indexed) is the preview URL; {5} is page URL used in the fallback", "Net.WebClient.DownloadFile avoids binary-over-stdout issues vs piping through pwsh stdout", "try/finally ensures temp file cleanup even when imgcat fails"]
patterns_established: []
drill_down_paths: []
observability_surfaces: []
duration: ""
verification_result: "Bootstrap sourced cleanly (exit 0). Read-BgCache runs without error. PowerShell parse of modules/bg.ps1 clean. Mock field construction confirmed 6 fields with correct values at each position."
completed_at: 2026-03-27T07:42:56.443Z
blocker_discovered: false
---

# T01: Add wezterm imgcat thumbnail preview to 8sync bg pick: fzf now shows a right-pane thumbnail by downloading the preview URL to a temp file via Net.WebClient and rendering with wezterm imgcat --width 60, with fallback to page URL when wezterm is absent

> Add wezterm imgcat thumbnail preview to 8sync bg pick: fzf now shows a right-pane thumbnail by downloading the preview URL to a temp file via Net.WebClient and rendering with wezterm imgcat --width 60, with fallback to page URL when wezterm is absent

## What Happened
---
id: T01
parent: S02
milestone: M001
key_files:
  - modules/bg.ps1
key_decisions:
  - Use single-quoted PS string for fzf --preview so $f defers expansion to the spawned subprocess
  - fzf {6} placeholder (1-indexed) is the preview URL; {5} is page URL used in the fallback
  - Net.WebClient.DownloadFile avoids binary-over-stdout issues vs piping through pwsh stdout
  - try/finally ensures temp file cleanup even when imgcat fails
duration: ""
verification_result: passed
completed_at: 2026-03-27T07:42:56.444Z
blocker_discovered: false
---

# T01: Add wezterm imgcat thumbnail preview to 8sync bg pick: fzf now shows a right-pane thumbnail by downloading the preview URL to a temp file via Net.WebClient and rendering with wezterm imgcat --width 60, with fallback to page URL when wezterm is absent

**Add wezterm imgcat thumbnail preview to 8sync bg pick: fzf now shows a right-pane thumbnail by downloading the preview URL to a temp file via Net.WebClient and rendering with wezterm imgcat --width 60, with fallback to page URL when wezterm is absent**

## What Happened

Read Invoke-BgPick in modules/bg.ps1. Changed the tab-delimited line format from 5 fields (id/resolution/src/tags/page) to 6 fields by appending the cache entry's preview URL as field 6. Built a wezterm-guarded fzf --preview command using a single-quoted PowerShell string so $f is not expanded at construction time. The preview subprocess downloads the thumbnail URL to a .GetTempFileName()+.jpg temp file using Net.WebClient.DownloadFile (avoids binary-over-stdout reliability issues), runs wezterm imgcat --width 60 on it, and cleans up in a finally block. fzf placeholder {6} (1-indexed) maps to the preview URL. Preview window is right:60%:wrap. When wezterm is absent the fallback shows echo {5} (page URL) in down:3:wrap. The fzf call keeps --with-nth 1,2,3 so the list shows id/resolution/source; hidden fields are still accessible to --preview.

## Verification

Bootstrap sourced cleanly (exit 0). Read-BgCache runs without error. PowerShell parse of modules/bg.ps1 clean. Mock field construction confirmed 6 fields with correct values at each position.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Read-BgCache | Select-Object -First 3"` | 0 | ✅ pass | 2100ms |
| 2 | `PS parse check on modules/bg.ps1` | 0 | ✅ pass | 400ms |
| 3 | `Mock 6-field line construction unit test` | 0 | ✅ pass | 300ms |


## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `modules/bg.ps1`


## Deviations
None.

## Known Issues
None.

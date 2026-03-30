---
id: S02
parent: M001
milestone: M001
provides:
  - Invoke-BgPick with wezterm imgcat thumbnail preview in fzf right pane (right:60%:wrap)
  - 6-field tab-delimited cache line format: id/resolution/src/tags/page/preview
  - Graceful text fallback (echo page URL) when wezterm is absent
requires:
  []
affects:
  []
key_files:
  - modules/bg.ps1
key_decisions:
  - Use single-quoted PS string for fzf --preview so $f defers expansion to the spawned subprocess
  - fzf {6} placeholder (1-indexed, tab-delimited) is the preview URL; {5} is the page URL used in the fallback
  - Net.WebClient.DownloadFile avoids binary-over-stdout issues vs piping through pwsh stdout
  - try/finally ensures temp file cleanup even when imgcat fails or fzf is cancelled
  - right:60%:wrap preview window gives adequate thumbnail space while keeping the list visible
patterns_established:
  - fzf preview with wezterm imgcat: 6-field tab-delimited line with --with-nth for display control and numeric placeholders for hidden fields accessible to --preview
  - Single-quoted PS string for fzf --preview to prevent premature variable expansion in outer shell
  - Net.WebClient.DownloadFile + try/finally cleanup for binary downloads in fzf preview subprocesses
observability_surfaces:
  - none
drill_down_paths:
  - .gsd/milestones/M001/slices/S02/tasks/T01-SUMMARY.md
duration: ""
verification_result: passed
completed_at: 2026-03-27T07:45:28.289Z
blocker_discovered: false
---

# S02: bg pick Image Preview in fzf

**fzf bg pick now shows a right-pane thumbnail via wezterm imgcat, downloading the preview URL to a temp file, with graceful text fallback when wezterm is absent**

## What Happened

S02 had a single task (T01) that modified `modules/bg.ps1` to add image preview to the `8sync bg pick` fzf selector.

**What changed in `Invoke-BgPick`:**

Previously the tab-delimited line format had 5 fields: `id TAB resolution TAB src TAB tags TAB page`. T01 added a sixth field — the cache entry's `preview` URL — making the format `id TAB resolution TAB src TAB tags TAB page TAB preview`.

The `--with-nth 1,2,3` fzf flag was preserved so the visible list still shows only id/resolution/source, keeping the UI clean. Hidden fields 4-6 remain accessible to the preview command via numeric placeholders.

**Preview command (wezterm present):**

A single-quoted PowerShell string is passed to `fzf --preview`. This is critical: `$f` must NOT expand in the outer shell — it must expand inside the child `pwsh` preview process. The preview subprocess:
1. Calls `[IO.Path]::GetTempFileName() + ".jpg"` to get a temp path
2. Uses `(New-Object Net.WebClient).DownloadFile("{6}", $f)` to download the preview URL to disk (avoids binary-over-stdout issues)
3. Runs `wezterm imgcat --width 60 $f` to render the thumbnail
4. Cleans up in a `finally` block with `Remove-Item $f -ea 0`

Preview window is `right:60%:wrap`.

**Fallback (wezterm absent):**

When `Test-CommandExists 'wezterm'` returns false, the preview command is `echo {5}` (page URL) with window `down:3:wrap` — a minimal but functional text fallback.

**Verification across all tasks:**
- Bootstrap sourced cleanly (exit 0)
- `Read-BgCache | Select-Object -First 3` runs without error
- PowerShell parse of `modules/bg.ps1` is clean
- Mock 6-field line construction confirms all fields at correct positions
- Source inspection confirms: `--with-nth 1,2,3`, `--preview-window`, `Net.WebClient`, `try/finally`, `wezterm imgcat --width 60`, `echo {5}` fallback all present

## Verification

All slice-level verification checks passed:

1. `pwsh ... ". .\wezterm-bootstrap.ps1; Read-BgCache | Select-Object -First 3"` → exit 0
2. PowerShell parser on `modules/bg.ps1` → clean (Parse OK)
3. 6-field mock line construction → all 6 fields at correct positions (PASS)
4. `{6}` preview URL placeholder present in preview command (PASS)
5. `{5}` page URL placeholder present in fallback command (PASS)
6. `right:60%:wrap` preview window set (PASS)
7. Source inspection: `--with-nth 1,2,3` present (PASS)
8. Source inspection: `Net.WebClient` present (PASS)
9. Source inspection: `try/finally` cleanup present (PASS)
10. Source inspection: `wezterm imgcat --width 60` present (PASS)
11. Source inspection: `echo {5}` fallback present (PASS)

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Deviations

None.

## Known Limitations

- The preview download happens on every fzf cursor movement — there is no caching of temp files between items. On slow connections this may cause noticeable lag.
- The temp file extension is hardcoded as `.jpg` regardless of the actual preview image format (some sources may serve `.png` or `.webp`). `wezterm imgcat` handles most formats regardless of extension, so this is unlikely to cause visible problems in practice.
- Preview works only when `wezterm` is on PATH. In environments without WezTerm (e.g. a plain Windows Terminal session) the fallback shows only the page URL text.

## Follow-ups

- Consider caching downloaded preview temp files keyed by URL to avoid re-downloading when navigating back to an already-seen item in fzf.
- The temp file extension could be inferred from the URL's path component for correctness with non-JPEG previews.

## Files Created/Modified

- `modules/bg.ps1` — Extended Invoke-BgPick: 6-field line format adds preview URL as field 6; wezterm imgcat --preview command with Net.WebClient download and try/finally cleanup; fallback to echo page URL when wezterm absent

---
estimated_steps: 14
estimated_files: 1
skills_used: []
---

# T01: fzf imgcat thumbnail preview in bg pick

Problem: fzf --preview runs a shell command per-item. On Windows with wezterm imgcat, the preview command must be a shell command string that:
  1. Extracts the preview URL from the fzf line (field 5 = preview URL in tab-delimited format)
  2. Downloads or pipes the URL to `wezterm imgcat --width 60 -`

Steps:
1. Read Invoke-BgPick in modules/bg.ps1.
2. Change the $lines format to include preview URL as field 6 (after page): id TAB resolution TAB src TAB tags TAB page TAB preview.
3. Build a --preview command string. On Windows, fzf calls cmd.exe for preview. Use a pwsh one-liner:
   `pwsh -NoProfile -Command "Invoke-WebRequest '{6}' -UseBasicParsing | Select-Object -Expand Content | wezterm imgcat --width 60 -"`
   But piping binary over pwsh stdout is unreliable. Better approach:
   Download to a temp file then imgcat the file:
   `pwsh -NoProfile -Command "$f=[System.IO.Path]::GetTempFileName()+'jpg'; (New-Object Net.WebClient).DownloadFile('{6}',$f); wezterm imgcat --width 60 $f; Remove-Item $f -ea 0"`
4. Use --preview-window=right:60%:wrap and --with-nth 1,2,3 (keep display columns as id/res/src).
5. Guard: if wezterm not in PATH, fall back to showing the page URL in preview (current behavior).
6. After selection, parse field 1 (id) and call Invoke-BgSet.

## Inputs

- `modules/bg.ps1`

## Expected Output

- `modules/bg.ps1 Invoke-BgPick updated with imgcat preview command`

## Verification

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Read-BgCache | Select-Object -First 3"

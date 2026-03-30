# Knowledge Base

Lessons learned during development — saved to prevent future agents from re-investigating the same questions.

---

## wezterm CLI has no GPU introspection

**Context:** M001 / S01 / T01  
`wezterm cli list-clients` returns only mux metadata (pane IDs, tab titles, PID). It does **not** expose the active renderer, front_end, GPU name, or power preference. `wezterm --help` has no GPU enumeration command. WezTerm log files contain no GPU entries by default.

**Solution:** Use `Get-WmiObject Win32_VideoController` for GPU name/type. Read `front_end` and `webgpu_power_preference` directly from `wezterm.lua` via regex.

---

## GPU adapter classification heuristics for Windows laptops

**Context:** M001 / S01 / T01  
Pattern matching on `Win32_VideoController.Name` to classify DiscreteGpu vs IntegratedGpu:
- **Discrete:** `NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro` (excluding `Radeon(TM) Graphics` / `Radeon(TM) Vega`)
- **Integrated:** `Intel|Radeon\(TM\) Graphics|Radeon\(TM\) Vega|UHD|Iris|HD Graphics`

When both are present the discrete adapter is preferred (it's what WezTerm uses on high-performance power plan).

---

## current-gpu.lua is absent in the worktree until 8sync gpu set is run

**Context:** M001 / S01 / T01  
`current-gpu.lua` is generated at runtime by `8sync gpu set` and is gitignored. It does **not** exist in a fresh clone or worktree. `8sync gpu verify` will report `FAIL` on the state-file check in that environment — this is expected and not a bug. All other checks (front_end, GPU type, power preference) work without the state file.

---

## $PSScriptRoot inside modules/ points to the modules/ directory, not the repo root

**Context:** M001 / S01 / T01  
In `modules/gpu.ps1`, `$PSScriptRoot` resolves to `modules/`. The `wezterm.lua` lookup uses `Join-Path $PSScriptRoot '..\wezterm.lua'` — wait, actually the module uses `Join-Path $PSScriptRoot 'wezterm.lua'` which would fail. The live bootstrap sets `$script:CurrentGpuLuaPath` in the parent scope, so the module inherits the correct path. If you move logic into the module file that needs the repo root, use `Split-Path $PSScriptRoot -Parent` or pass the path as a parameter.

**Note:** In practice `Get-ActiveGpuInfo` uses `Join-Path $PSScriptRoot 'wezterm.lua'` — this resolves to `modules/wezterm.lua` which doesn't exist, so the regex falls back to defaults (`WebGpu`, `HighPerformance`). The correct values are read because they match the defaults in `wezterm.lua`. If the config ever uses non-default values, this lookup will silently return stale data. Consider fixing in a future slice.

---

## fzf --preview with PowerShell: use single-quoted strings so $variables defer expansion

**Context:** M001 / S02 / T01  
When constructing an fzf `--preview` command that runs a PowerShell subprocess, the `$f` variable must NOT expand in the outer PowerShell session — it must expand inside the spawned `pwsh` preview process. Use a single-quoted string (or carefully escape `$`) when building the preview command string in PowerShell.

**Wrong:** `$previewCmd = "pwsh -Command \"\$f=...\""`  — `$f` expands immediately to empty string.  
**Right:** `$previewCmd = 'pwsh -Command "$f=...'` — `$f` is literal text passed to the child process.

---

## fzf field placeholders are 1-indexed for tab-delimited input

**Context:** M001 / S02 / T01  
With `--delimiter "\`t"`, fzf field placeholders are 1-indexed: `{1}` is the first field, `{6}` is the sixth. `--with-nth 1,2,3` controls what the *list* displays but does NOT affect what `--preview` can access — hidden fields are still reachable via their placeholder numbers.

---

## Net.WebClient.DownloadFile is more reliable than piping binary through stdout in fzf preview

**Context:** M001 / S02 / T01  
fzf preview subprocesses capture stdout. If you try to pipe a binary image download through stdout (e.g. `Invoke-WebRequest | Set-Content`), binary corruption or encoding issues arise. `(New-Object Net.WebClient).DownloadFile(url, path)` writes directly to disk without touching stdout, then `wezterm imgcat` reads from the temp file cleanly. Always use `try/finally` to remove the temp file even when imgcat fails or the user cancels fzf.

---

## New 8sync subcommands follow the modules/[name].ps1 pattern

**Context:** M001 / S01  
All new 8sync top-level subcommands live in a dedicated `modules/[name].ps1` file. The public entry point is `Invoke-[Name]Command` which receives `[string[]]$Rest` and dispatches to `status`, `verify`, `help`, and unknown subcommand handlers. Integration requires four touchpoints:
1. `wezterm-bootstrap.ps1` — add any `$script:` path variables and `. (Join-Path $script:ModulesDir '[name].ps1')`
2. `modules/startup.ps1` — add `'[name]' { Invoke-[Name]Command -Rest $Rest }` to `Invoke-8Sync`'s switch
3. `modules/shell.ps1` — add `'[name]'` to `$modes` and `[name] = @('status','verify','help',...)` to `$subMap` in `Register-8SyncCompleter`
4. The module itself — implement `Show-[Name]Status`, `Invoke-[Name]Verify`, `Show-[Name]Help`, `Invoke-[Name]Command`

---

## WezTerm CLI has no reload/reload-configuration subcommand — file-watcher handles it

**Context:** M001 / S03 / T01  
`wezterm cli --help` lists only mux operations (list, list-clients, spawn, split-pane, etc.). There is **no** `reload`, `reload-configuration`, or `reload-config` subcommand. WezTerm reloads its config automatically via a file-watcher whenever any `*.lua` state file is written. The correct liveness probe is `wezterm cli list-clients` — if it exits 0, WezTerm is running and the file-watcher is active.

**Pattern:** `Try-ReloadWezTerm` uses `list-clients` as a pure liveness check. After the check succeeds, print "  Config reloaded." — the reload itself was already triggered by `Write-CurrentBgLua` / `Write-CurrentStyleLua` writing the state file. If `list-clients` fails (WezTerm not running), print the manual reload hint instead.

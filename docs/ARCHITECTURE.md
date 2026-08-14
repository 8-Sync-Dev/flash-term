# Architecture

## Config loading flow

```
WezTerm start
  └─ wezterm.lua                 reads current-{bg,opacity,style,gpu}.lua, builds config
       └─ default_prog = pwsh -Command ". wezterm-bootstrap.ps1"
            └─ wezterm-bootstrap.ps1
                 ├─ dot-source modules/*.ps1   (defines all `ft` functions)
                 └─ switch ($Task)             Shell | Hint | Status | Sync | BgRotate | CleanLoop
                      └─ Start-WezTermShell (default)
                           ├─ Ensure-PreferredPaths    prepend scoop/shims to PATH
                           ├─ Set-HistoryExperience    PSReadLine + fzf Ctrl+r
                           ├─ Set-ToolAliases          ll, e, lg, y, cdi, …
                           │    └─ Register-8SyncCompleter   (Tab/inline completion for `ft`)
                           └─ Start-AutoSync           hidden bg process if tools stale (72h)
```

The dispatcher is the function **`Invoke-8Sync`**, aliased globally as **`ft`** (see
`modules/startup.ps1`, `Register-8SyncAlias`). The name `8sync` is **not** aliased here — it belongs
to the separate su-code AI binary and must not be shadowed. flash-term has no AI/session/skill
commands of its own; for AI, `ft setup` installs [su-code](https://github.com/8-Sync-Dev/su-code)
(which provides `8sync`).

## State sharing (Lua ↔ PowerShell)

PowerShell writes small `.lua` files; Lua reads them on reload. After every write, `wezterm cli reload` reapplies the change live.

| File | Writer | Shape |
|---|---|---|
| `current-bg.lua` | `ft bg set` | `return [[C:\path\to\image.jpg]]` |
| `current-opacity.lua` | `ft hx opacity` | `return 0.72` |
| `current-style.lua` | `ft theme` / `ft bg set` | `return { style=…, scene=…, bg_hint=… }` |
| `current-gpu.lua` | `ft gpu` | `return { min_percent=…, updated_utc=… }` |

All are gitignored.

## Tool management

`$script:ToolPackages` lists the 21 managed CLI tools (fzf, zoxide, ripgrep, fd, bat, eza, starship,
helix, yazi, lazygit, delta, tokei, hyperfine, dust, procs, bottom, less, jq, yq, make, chafa). All
installed/updated via Scoop (bucket `extras` ensured first), batched into one install and one update
call. State persists to `.state/tool-state.json`; `.state/sync.lock` prevents concurrent syncs and is
reaped after 30 min. A missing-tools cache (`.state/missing-cache.json`, 5-min TTL) avoids re-scanning on
every tab; `Start-AutoSync` re-syncs in a hidden process when a tool is missing or the last sync is
older than 72h.

`ft sync` installs/updates them; `ft sync --check` is a dry-run; `ft status` reports what is
installed and the last sync time.

## Dev runtimes

`ft dev` provisions development runtimes with **no Visual Studio** build tools, via Scoop (and a
couple of non-Scoop installers): `node`, `python` (uv + standalone CPython), `go`, `rust`
(GNU/MinGW triple), `chromium`, `docker` (winget), `encore`. `ft dev all` installs everything;
`ft dev` shows status; `ft dev all --check` is a dry run (`ft dev --check` with no target prints the
status table). `ft setup` runs this as a bootstrap step (`--no-dev` skips it). `~/.cargo/bin` and
`~/.encore/bin` are added to the preferred PATH.

## Update + readiness

- `ft up [self|scoop|wezterm] [--check]` updates the config repo (git ff-only), the Scoop tools, and
  reports the WezTerm version. `--check` is a dry-run.
- `ft status` reports installed tools, last sync time, current GPU target, and glass theme.
- `ft autoupdate [on|off|auto|now]` runs a background update + release notifier (notify mode by default).

## Profiles

`ft profile` gives each profile its own `.state/profiles/<name>/`, its own generated
`current-{bg,opacity,style,gpu}-<name>.lua` (read by `wezterm.lua` when `WEZTERM_PROFILE` is set), and
its own `CLAUDE_CONFIG_DIR`. `switch` changes the current tab's env/state only; `open` launches a new
`wezterm-gui` window for full visual isolation.

## Startup cost control

`Start-WezTermShell` times 8 named phases per boot and appends them to `.state/startup-profile.json`
(last 40 boots, surfaced as `startup perf:` in `ft status`; `WEZTERM_BOOT_TRACE=1` prints the total).
Background work is gated to once per 20s across tabs (`.state/startup-background-gate.json`), and the
default `light` startup mode runs only the clean-loop check — `WEZTERM_STARTUP_MODE=balanced` also runs
auto-sync, wallpaper rotation, and the update notifier.

## Local models (GGUF)

`ft gguf` runs a local **llama.cpp** server (OpenAI-compatible `/v1` endpoint) on your GPU. Point any
OpenAI-compatible client at it — including su-code's omp, configured in `~/.omp/config.yml` (see
`docs/gguf-local-gpu-provider.md`).

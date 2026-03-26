# 8sync CLI Reference

Updated: 2026-03-22

## Overview

`8sync` is the WezTerm shell toolkit. Available as `8sync` or `/8sync`.
Tab completion is registered for all commands and flags.

```
8sync <command> [flags]
```

---

## Commands

### `8sync help`
Show command overview with missing tool count.

```powershell
8sync help
8sync          # same
```

---

### `8sync status`
Show installed tool status table and last sync time.

```powershell
8sync status
```

Output: table of each managed tool (command / state / path) + last sync UTC timestamp.

---

### `8sync sync`
Install missing tools and update all managed tools via Scoop.

```powershell
8sync sync
```

- Adds `extras` bucket automatically if not present (required for `lazygit`)
- Installs any missing packages via `scoop install`
- Refreshes PATH after install
- Updates only tools that are actually installed
- Invalidates the missing-tools cache after completion

---

### `8sync clean`

Deep system cleaner. Multiple modes via flags.

#### Default — full clean

```powershell
8sync clean                    # stale > 7 days
8sync clean --days 14          # custom threshold
8sync clean --dry-run          # preview, nothing deleted
```

Cleans in order:
1. **TEMP** — `%TEMP%`, `%TMP%`, `%SystemRoot%\Temp`, `%LOCALAPPDATA%\Temp`
2. **APP CACHES** — Chrome, Edge, Firefox, Brave, VSCode, npm, pip, uv, cargo,
   gradle, maven, nuget, yarn, scoop, pnpm, bun, Teams, Discord, Slack, Spotify
3. **WINDOWS** — WU downloads, Prefetch, CrashDumps, INetCache, Recent,
   JumpLists, ErrorReports, Thumbnails, D3DShader, GPU caches, WebCache
4. **STALE ENVS** — Python venvs, conda envs, uv tools, Rust `target/`,
   Go `vendor/`, `node_modules` older than threshold
5. **MEMORY & NETWORK** — GC collect, EmptyWorkingSet, DNS/ARP/NetBIOS flush,
   clipboard clear, RAM usage report + top 5 hogs
6. **DISK** — SSD TRIM or HDD defrag via `Optimize-Volume` (needs admin;
   skips gracefully without)

#### `--projects` — stale git repo picker

```powershell
8sync clean --projects                   # default: repos not touched > 90 days
8sync clean --projects --days 30         # custom threshold
8sync clean --projects --all             # delete all (requires YES confirm)
8sync clean --projects --dry-run         # preview only
```

- Scans `~/projects`, `~/dev`, `~/code`, `~/repos`, `~/workspace`,
  `~/Documents`, `~/Desktop`, `~/Downloads`, `~/src`, `~/work`, `~/github`, `~/lab`
- Detects repos via `.git/` presence
- Uses `git log -1 --format=%ct` for last commit date (fallback: COMMIT_EDITMSG mtime)
- **fzf multi-select**: TAB to mark, Ctrl+A to select all, ENTER to confirm
- **No fzf**: numbered list with manual index input
- Always shows summary + requires typing `YES` before any deletion

#### `--deep` — dev artifact report

```powershell
8sync clean --deep                       # default: artifacts > 7 days old
8sync clean --deep --days 30
```

Scans and reports (read-only, nothing deleted):
- `npx` cache entries (`%LOCALAPPDATA%\npm-cache\_npx`) — MCP servers, CLIs
- npm global packages (`%APPDATA%\npm\node_modules`)
- pip / uv site-packages
- `~/.cargo/bin/*.exe`
- `~/go/bin/*.exe`

Output grouped by type with size + age. Remove items manually via package manager.

#### `--scan` — Windows Defender scan

```powershell
8sync clean --scan                       # quick scan + targeted dev folders
8sync clean --scan C:\path\to\project    # targeted scan on specific path
```

- Locates `MpCmdRun.exe` automatically (Program Files + Platform/*)
- Default: launches `ScanType 1` (quick scan) in background
- Also runs targeted `ScanType 3` on `scoop/apps`, `~/.cargo/bin`, npx cache
- Gracefully skips if Defender is not found

#### `help` / `--help` / `-h`

```powershell
8sync clean help
8sync clean --help
8sync clean -h
```

---

### `8sync opencode` — Portable OpenCode bundle export

```powershell
8sync opencode                    # export to ./oc-bundle
8sync opencode export a           # explicit export target
8sync opencode --dry-run          # preview exported files only
8sync opencode status             # source/bundle/node/npm/nvm readiness
8sync opencode help
```

- Source: `~/.config/opencode`
- Default bundle folder: `./oc-bundle` (relative to current working directory)
- Export exclusions: `lib/`, `node_modules/`, `*.ps1`, `*.py`
- `install` and `setup` are backward-compatible aliases to `export`

Target machine setup:

```powershell
# 1) copy bundle contents -> ~/.config/opencode
cd ~/.config/opencode
npm i

# 2) if npm is missing
scoop install nvm
nvm install <version>
nvm use <version>
npm i
```

---

### `8sync bg` — Wallpaper management

```powershell
8sync bg search <keywords>     # search Wallhaven for 4K wallpapers
8sync bg pick                  # pick from cached results with fzf
8sync bg set <id|path|url>     # set wallpaper by cache id, local path, or URL
8sync bg open <id>             # open wallpaper page in browser
8sync bg help
```

- Results cached in `.state/bg-cache.json` (up to 50 entries)
- `bg set` downloads image to `bg/`, writes `current-bg.lua`, reloads WezTerm
- Search filters: 4K (3840x2160+), relevance sort, SFW+sketchy categories

---

### `8sync hx` — Helix editor management

```powershell
8sync hx lang [name]           # install language toolchain via scoop (fzf picker)
8sync hx wrap                  # toggle soft word-wrap on/off
8sync hx opacity <val>         # adjust background transparency: + / - / 0.0-1.0
8sync hx theme [name]          # pick Helix color theme (fzf picker)
8sync hx help
```

**Supported languages for `hx lang`:**

| Key | Packages installed |
|-----|--------------------|
| `python` | python, pyright |
| `typescript` | nodejs |
| `rust` | rust, rust-analyzer |
| `go` | go, gopls |
| `lua` | lua-language-server |
| `c-cpp` | llvm |
| `zig` | zig, zls |
| `toml` | taplo |
| `markdown` | marksman |
| `java` | openjdk |
| `csharp` | dotnet-sdk |

**`hx opacity`** writes `current-opacity.lua` and reloads WezTerm live.
Values: `+` (increase 0.05), `-` (decrease 0.05), or exact `0.0`–`1.0`.

---

## Aliases set by bootstrap

| Alias | Tool | Description |
|-------|------|-------------|
| `ll` | eza | List files with icons (`-lah`) |
| `lt` | eza | Tree view 2 levels deep |
| `catn` | bat | Syntax-highlighted cat |
| `ff` | rg | Find files by name |
| `cdi` | zoxide | Smart directory jump |
| `y` | yazi | File manager with cd-on-exit |
| `e` | hx (helix) | Open in Helix editor |
| `lg` | lazygit | Git TUI |
| `pss` | procs | Process viewer |
| `top` | btm (bottom) | System monitor TUI |
| `du` | dust | Disk usage visualizer |
| `mkcd` | — | Create dir and cd into it |

**Keybindings:**

| Key | Action |
|-----|--------|
| `Ctrl+r` | Fuzzy history search (fzf) |
| `Alt+c` | Jump to directory (zoxide `cdi`) |
| `Tab` | Menu completion |
| `Up/Down` | History search backward/forward |

---

## State files

| File | Written by | Content |
|------|-----------|---------|
| `.state/tool-state.json` | `8sync sync` | Last sync UTC timestamp |
| `.state/sync.lock` | sync process | Prevents concurrent sync |
| `.state/bg-cache.json` | `8sync bg search` | Wallhaven search results |
| `.state/missing-cache.json` | shell startup | Cached missing tool list (TTL 5min) |

---

## Managed tools

| Command | Package | Installed by |
|---------|---------|--------------|
| `fzf` | fzf | scoop main |
| `zoxide` | zoxide | scoop main |
| `rg` | ripgrep | scoop main |
| `fd` | fd | scoop main |
| `bat` | bat | scoop main |
| `eza` | eza | scoop main |
| `starship` | starship | scoop main |
| `hx` | helix | scoop main |
| `yazi` | yazi | scoop main |
| `lazygit` | lazygit | scoop **extras** |
| `delta` | delta | scoop main |
| `tokei` | tokei | scoop main |
| `hyperfine` | hyperfine | scoop main |
| `dust` | dust | scoop main |
| `procs` | procs | scoop main |
| `btm` | bottom | scoop main |
| `less` | less | scoop main |

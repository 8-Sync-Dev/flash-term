# Architecture

## File Structure

```
~/.config/wezterm/
├── wezterm.lua              # WezTerm config (Lua) — appearance, keys, shell launch
├── wezterm-bootstrap.ps1    # PowerShell bootstrap — 8sync toolkit, aliases, auto-sync
├── current-bg.lua           # Generated: returns background image path (Lua)
├── current-opacity.lua      # Generated: returns overlay opacity value (Lua)
├── bg/                      # Downloaded wallpaper images
├── fonts/                   # Bundled JetBrainsMono Nerd Font
├── .state/
│   ├── tool-state.json      # Last sync timestamp
│   ├── sync.lock            # Prevents concurrent sync processes
│   └── bg-cache.json        # Cached Wallhaven search results
└── docs/                    # Documentation
```

## How It Works

### Startup Flow

```
WezTerm launches
  └─ Loads wezterm.lua
       ├─ Reads current-bg.lua → background image path
       ├─ Reads current-opacity.lua → overlay opacity value
       ├─ Sets appearance, fonts, keybindings
       └─ Launches PowerShell with bootstrap:
            └─ wezterm-bootstrap.ps1 -Task Shell
                 ├─ Ensure-PreferredPaths (scoop/shims, .local/bin)
                 ├─ Set-HistoryExperience (PSReadLine + fzf Ctrl+r)
                 ├─ Set-ToolAliases (ll, lg, e, y, cdi, ...)
                 └─ Start-AutoSync (background process if stale/missing)
```

### State File Pattern

WezTerm (Lua) and the shell (PowerShell) communicate through small Lua files:

| File | Written by | Read by | Content |
|---|---|---|---|
| `current-bg.lua` | `8sync bg set` (PS) | `wezterm.lua` | `return [[C:\path\to\image.jpg]]` |
| `current-opacity.lua` | `8sync hx opacity` (PS) | `wezterm.lua` | `return 0.72` |

After writing, the PowerShell side calls `wezterm cli reload` to apply changes live. If that fails, WezTerm's `automatically_reload_config = true` picks up file changes on its own.

### Auto-Sync Lifecycle

```
Shell starts
  └─ Start-AutoSync checks:
       ├─ Scoop available? (no → skip)
       ├─ sync.lock exists? (yes & < 30min → skip)
       ├─ Any tools missing? (yes → sync)
       └─ Last sync > 72 hours? (yes → sync)
            └─ Spawns hidden PowerShell process:
                 wezterm-bootstrap.ps1 -Task SyncQuiet
                   ├─ Creates sync.lock
                   ├─ scoop install <missing>
                   ├─ scoop update <all managed>
                   ├─ Updates tool-state.json
                   └─ Removes sync.lock
```

### Helix Config Management

`8sync hx` commands modify `%AppData%\helix\config.toml` (TOML format) using line-by-line parsing:

- **theme**: top-level `theme = "name"` key
- **wrap**: `[editor.soft-wrap]` section → `enable = true/false`
- **opacity**: writes `current-opacity.lua` (not Helix config — this is a WezTerm setting)
- **lang**: installs Scoop packages for language toolchains and LSP servers

### Background Layer Stack

WezTerm renders backgrounds as ordered layers:

```
Layer 1: Background image (brightness=0.32, saturation=0.95)
Layer 2: Dark overlay (#11111b, opacity from current-opacity.lua)
Layer 3: Text content (text_background_opacity=1.0)
```

`window_background_opacity = 0.0` makes the window itself transparent, so the Windows Acrylic effect shows through where layers don't fully cover.

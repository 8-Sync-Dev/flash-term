# Keybindings

Leader key: **`Ctrl+a`** (900ms timeout, `wezterm.lua`). The table lives in `keys.lua`; two extra
bindings are appended in `wezterm.lua` (marked below). WezTerm's default bindings stay active — nothing
sets `disable_default_key_bindings`.

## Panes

| Action | Binding |
|---|---|
| Split right (50%) | `Ctrl+Shift+\|` |
| Split down (34%) | `Ctrl+Shift+_` |
| Close pane (no confirm) | `Ctrl+Shift+w` |
| Zoom pane | `Ctrl+Shift+z` |
| Navigate panes | `Ctrl+Shift+Arrow` |
| Resize pane (5 horiz / 2 vert) | `Alt+Shift+Arrow` |

## Tabs & windows

| Action | Binding |
|---|---|
| New tab | `Ctrl+Shift+t` |
| Next / previous tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| Jump to tab N | `Alt+1`..`Alt+9` |
| Last tab | `Alt+0` |
| Fullscreen | `Alt+Enter` |
| Tab/workspace/launch-menu switcher (fuzzy) | `Leader → s` |

## Appearance (appended in `wezterm.lua`)

| Action | Binding |
|---|---|
| Toggle background: wallpaper ↔ gradient | `Ctrl+Shift+b` |
| Cycle cursor style (SteadyBlock → BlinkingBlock → BlinkingBar → BlinkingUnderline) | `Ctrl+Shift+o` |

## Font

| Action | Binding |
|---|---|
| Increase / decrease | `Ctrl+=` / `Ctrl+-` |
| Reset | `Ctrl+0` |

## Clipboard, search, selection

| Action | Binding |
|---|---|
| Copy / paste | `Ctrl+Shift+c` / `Ctrl+Shift+v` (also `Ctrl+v`) |
| Search | `Ctrl+Shift+f` |
| Command palette | `Ctrl+Shift+p` |
| Launcher | `Ctrl+Shift+l` |
| Quick select | `Ctrl+Shift+y` |

## Mouse (`wezterm.lua`)

`bypass_mouse_reporting_modifiers = "SHIFT"`, so these work even inside a TUI that grabs the mouse.

| Action | Binding |
|---|---|
| Select cell | `Shift` + left click |
| Extend selection | `Shift` + left drag |
| Complete selection / open link | `Shift` + left release |

## Leader (`Ctrl+a`) — prefix

| Action | Binding |
|---|---|
| Send literal `Ctrl+a` | `Leader → a` |
| Copy mode | `Leader → c` |
| Command palette | `Leader → x` |
| Reload config | `Leader → r` |
| Tab/workspace switcher | `Leader → s` |

## Leader — typed commands

These leader shortcuts type a command into the active pane (tmux-style prefix trigger).

| Binding | Types | Enter sent? |
|---|---|---|
| `Leader → u` | `ft up --check` | yes |
| `Leader → b` | `ft bg pick` | yes |
| `Leader → .` | `8sync .` | yes |
| `Leader → o` | `8sync ai ` | no — finish the prompt yourself |
| `Leader → h` | `8sync harness status` | yes |
| `Leader → k` | `8sync skill list` | yes |

> `8sync` is the [su-code](https://github.com/8-Sync-Dev/su-code) AI binary, installed by `ft setup`.
> flash-term only types the command; it implements no AI itself. The full `ft` surface is in `ft help`.

## Shell keys (PSReadLine, `modules/shell.ps1`)

| Action | Binding | Requires |
|---|---|---|
| Fuzzy history search (inserts, does not run) | `Ctrl+r` | `fzf` |
| Interactive directory jump | `Alt+c` → `cdi` | `zoxide` |
| Menu completion | `Tab` | — |
| Prefix history search | `Up` / `Down` | — |
| Delete char | `Ctrl+d` | — |

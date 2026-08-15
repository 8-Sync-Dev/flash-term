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
| Smart paste (image → file path) | `Ctrl+Alt+v` |
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

### Smart image paste (`Ctrl+Alt+v`)

WezTerm has no native clipboard-image paste ([wezterm#7272](https://github.com/wezterm/wezterm/issues/7272),
closed unmerged — no release, stable or nightly, supports it). This binding closes the gap:
if the clipboard holds an image (Snipping Tool, screenshot, copied picture), it is saved to
`%TEMP%\ft-paste\img_<timestamp>.png` and the **file path is typed into the pane** — the
workflow AI CLIs (Claude Code, `8sync`) expect. With no image in the clipboard it falls back
to a normal text paste.

## Leader (`Ctrl+a`) — prefix

| Action | Binding |
|---|---|
| Send literal `Ctrl+a` | `Leader → a` |
| Copy mode | `Leader → c` |
| Command palette | `Leader → x` |
| Reload config | `Leader → r` |
| Tab/workspace switcher | `Leader → s` |
| Save session now | `Leader → Shift+s` |
| Fuzzy restore a saved session | `Leader → Shift+r` |

## Session restore (resurrect.wezterm)

Windows/tabs/splits layout, pane working directories and screen text are auto-saved every
2 minutes ([YedPool/resurrect.wezterm](https://github.com/YedPool/resurrect.wezterm), loaded
via `wezterm.plugin.require` in `wezterm.lua`) and restored automatically the next time
WezTerm starts — so a reboot reopens the session as it was. Use `Leader → Shift+s` to save
on demand and `Leader → Shift+r` to pick and restore any saved workspace/window/tab.

Panes come back with their cwd and scrollback text; known-safe TUIs (`vim`, `nvim`,
`claude`, `htop`, …) are relaunched automatically. Other long-running processes cannot be
resurrected — the pane reopens a fresh shell at the saved directory.

Manage saved sessions from the shell: `ft session` (status), `ft session list [--all]`,
`ft session save` (instant save via OSC 1337 trigger), `ft session restore <name>` (stage
for next WezTerm start), `ft session delete <name>`.

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

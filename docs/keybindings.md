# Keybindings

## Leader Key

The leader key is `Ctrl+a` (tmux-style, 900ms timeout). Press leader first, then the action key.

| Binding | Action |
|---|---|
| `Leader → a` | Send literal `Ctrl+a` to terminal |
| `Leader → c` | Enter copy mode |
| `Leader → x` | Open command palette |
| `Leader → s` | Workspace/tab switcher (fuzzy) |

## Pane Management

| Binding | Action |
|---|---|
| `Ctrl+Shift+\|` | Split pane right (50%) |
| `Ctrl+Shift+_` | Split pane down (34%) |
| `Ctrl+Shift+w` | Close current pane |
| `Ctrl+Shift+z` | Toggle pane zoom |
| `Ctrl+Shift+Arrow` | Navigate between panes |
| `Alt+Shift+Arrow` | Resize pane (5 cols / 2 rows) |

## Tabs & Navigation

| Binding | Action |
|---|---|
| `Ctrl+Shift+t` | New tab |
| `Ctrl+Shift+l` | Show launcher |
| `Ctrl+Shift+p` | Command palette |
| `Ctrl+Shift+f` | Search in scrollback |
| `Ctrl+Shift+y` | Quick select (URLs, paths) |
| `Alt+Enter` | Toggle fullscreen |

## Clipboard

| Binding | Action |
|---|---|
| `Ctrl+Shift+c` | Copy to clipboard |
| `Ctrl+Shift+v` | Paste from clipboard |
| `Ctrl+v` | Paste from clipboard (alt) |

## Font Size

| Binding | Action |
|---|---|
| `Ctrl+=` | Increase font size |
| `Ctrl+-` | Decrease font size |
| `Ctrl+0` | Reset font size |

## Shell Keybindings (PSReadLine)

These are set up by the bootstrap script and work inside the PowerShell prompt:

| Binding | Action |
|---|---|
| `Ctrl+r` | Fuzzy search command history (fzf) |
| `Alt+c` | Jump to directory (zoxide interactive) |
| `Tab` | Menu-complete (cycle through completions) |
| `Ctrl+d` | Delete character under cursor |
| `Up/Down Arrow` | Search history matching current input |

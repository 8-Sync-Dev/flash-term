# Keybindings

Leader key: **`Ctrl+a`** (900ms timeout). WezTerm config in `keys.lua`.

## Panes

| Action | Binding |
|---|---|
| Split right (50%) | `Ctrl+Shift+\|` |
| Split down (34%) | `Ctrl+Shift+_` |
| Close pane | `Ctrl+Shift+w` |
| Zoom pane | `Ctrl+Shift+z` |
| Navigate panes | `Ctrl+Shift+Arrow` |
| Resize pane | `Alt+Shift+Arrow` |

## Tabs & windows

| Action | Binding |
|---|---|
| New tab | `Ctrl+Shift+t` |
| Next / previous tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| Jump to tab N | `Alt+1`..`Alt+9` |
| Fullscreen | `Alt+Enter` |
| Tab/workspace launcher | `Leader → s` |

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

## Leader (Ctrl+a) — prefix

| Action | Binding |
|---|---|
| Send literal Ctrl+a | `Leader → a` |
| Copy mode | `Leader → c` |
| Command palette | `Leader → x` |
| Reload config | `Leader → r` |
| Tab/workspace switcher | `Leader → s` |

## Leader — AI harness (omp)

| Action | Binding | Runs |
|---|---|---|
| Resume latest omp session | `Leader → .` | `8sync .` |
| omp one-shot prompt (type your prompt, then Enter) | `Leader → o` | `8sync ai ` |
| Harness readiness | `Leader → h` | `8sync harness status` |
| Skill registry list | `Leader → k` | `8sync skill list` |
| Update-all preview | `Leader → u` | `8sync up --check` |
| Background wallpaper picker | `Leader → b` | `8sync bg pick` |

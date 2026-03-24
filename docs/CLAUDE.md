# docs/ — WezTerm Config Documentation

## Structure
| Folder | Content |
|--------|---------|
| `guides/` | Usage guides: keybindings, 8sync CLI reference |
| `architecture/` | Config loading flow, system design |

## Naming
`{YYYYMMDD}-{kebab-case-name}.md`

## Rules
- English only
- Max 300 lines per file
- Code blocks for all commands/Lua/PowerShell snippets

## Quick Ref
- Config files: `wezterm.lua`, `wezterm-bootstrap.ps1`
- State: `.state/tool-state.json`
- Wallpaper: `current-bg.lua`, `bg/`

## Known Pitfalls (avoid)
- Window capture tools can fail if the native title bar is removed and the window is fully transparent (Acrylic + opacity 0.0). Keep this in mind when troubleshooting capture issues.

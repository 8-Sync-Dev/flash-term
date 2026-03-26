# docs/ — WezTerm Configuration Documentation

## Structure

| Folder | Content |
|--------|---------|
| `guides/` | Operational how-to docs (commands, keybindings, troubleshooting) |
| `architecture/` | Runtime architecture and component interaction |
| `plans/` | Versioned implementation plans and sprint tracking |

## Naming Convention

- Standard: `{YYYYMMDD}-{kebab-case-name}.md`
- Plans: `{YYYYMMDD}-v{MAJOR.MINOR.PATCH}-{kebab-slug}.md`

## Documentation Rules

- English only
- Keep files under 300 lines when possible
- Use tables for structured references
- Use fenced code blocks for PowerShell/Lua examples
- Avoid duplicated content; prefer linking to canonical docs

## Canonical Entry Points

- Guides index: `docs/guides/CLAUDE.md`
- Architecture index: `docs/architecture/CLAUDE.md`
- Plans index: `docs/plans/CLAUDE.md`

## Quick Reference

- Config files: `wezterm.lua`, `wezterm-bootstrap.ps1`
- Runtime state: `.state/tool-state.json`, `.state/sync.lock`, `.state/bg-cache.json`
- Generated Lua state: `current-bg.lua`, `current-opacity.lua`, `current-style.lua`

## Known Pitfall

- Some screen-capture tools fail when native title bar is hidden and background is fully transparent (Acrylic + very low opacity). Validate capture behavior before changing transparency defaults.

# architecture/ — Config Architecture

## Scope
How the config files work together: loading flow, subsystem design, state management.

## Naming
`{YYYYMMDD}-{kebab-case-name}.md`

## Files
- `20260320-architecture.md` — Config loading flow, 8sync internals, wallpaper system
- `20260322-roadmap.md` — Architecture-adjacent improvement roadmap and status tracking

## Writing Rules
- Keep architecture docs implementation-accurate (no aspirational behavior without labels)
- Use simple flow blocks for startup/runtime interactions
- Link operational details to `docs/guides/` instead of duplicating command docs

---
title: Project Structure
description: Canonical file and responsibility map for the WezTerm config repo
tags: [rule, structure, paths]
globs: ["*"]
---

# Project Structure

## Top-Level Map

```text
wezterm/
├── wezterm.lua                  # WezTerm runtime config
├── wezterm-bootstrap.ps1        # 8sync shell toolkit + aliases + auto-sync
├── README.md                    # User-facing setup and usage
├── AGENTS.md                    # Agent implementation constraints
├── CLAUDE.md                    # Root Claude guidance
├── docs/                        # Structured project documentation
└── .claude/                     # Claude-local policy/rules
```

## Runtime-Generated (Never Commit)

- `current-bg.lua`
- `current-opacity.lua`
- `current-style.lua`
- `current-gpu.lua`
- `.state/`
- `bg/`
- `fonts/`

## Documentation Ownership

| Area | Canonical Location |
|------|--------------------|
| CLI usage and troubleshooting | `docs/guides/` |
| Runtime architecture and flows | `docs/architecture/` |
| Version plans and task tracking | `docs/plans/` |
| Claude workspace policy | `.claude/` + root `CLAUDE.md` |

## Change Discipline

When behavior changes in `wezterm.lua` or `wezterm-bootstrap.ps1`, update related docs in the same change set.

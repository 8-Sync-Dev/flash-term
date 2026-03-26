# .claude/ — Claude Workspace Configuration

This folder stores repo-local Claude guidance, rules, and quality gates for the WezTerm configuration project.

## Structure

| Path | Purpose |
|------|---------|
| `.claude/CLAUDE.md` | Workspace index for Claude policy files |
| `.claude/rules/core/docs-standards.md` | Markdown standards and naming conventions |
| `.claude/rules/core/project-structure.md` | Canonical repository structure and ownership |
| `.claude/rules/core/reporting-standards.md` | Reporting format and validation expectations |
| `.claude/settings.local.json` | Local tool/runtime settings (machine-specific) |

## Sync Rule

When editing any of these files, also verify consistency with:

- Root `CLAUDE.md`
- `AGENTS.md`
- `docs/CLAUDE.md`

## Scope

This repository is config-first (Lua + PowerShell). Do not add product/backend assumptions from larger app templates.

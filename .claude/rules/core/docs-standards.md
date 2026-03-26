---
title: Documentation Standards
description: Markdown standards for the WezTerm config repository
tags: [rule, docs, markdown]
globs: ["docs/**", "README.md", "CLAUDE.md", "AGENTS.md", ".claude/**/*.md"]
---

# Documentation Standards

## Language
- English only for durable maintenance and agent readability.
- Keep command names, flags, and file paths exactly as implemented.

## Naming
- General docs: `{YYYYMMDD}-{kebab-case-name}.md`
- Plan docs: `{YYYYMMDD}-v{MAJOR.MINOR.PATCH}-{kebab-slug}.md`
- Index docs: `CLAUDE.md` at each folder root.

## Structure
Use this hierarchy as source of truth:

```text
docs/
├── CLAUDE.md
├── guides/
├── architecture/
└── plans/
```

## Writing Rules
- Prefer one canonical doc per topic; mark older files as legacy instead of duplicating.
- Keep files concise (target under 300 lines).
- Use tables for command/reference material.
- Use fenced code blocks for PowerShell/Lua examples.
- Do not include speculative behavior; document only shipped behavior.

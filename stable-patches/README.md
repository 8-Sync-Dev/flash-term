# Stable Patch Profiles

This folder tracks the known-good patch profiles for runtime fixes that must survive upstream updates.

## Purpose

Do **not** copy full runtime installs into this repo. Instead, keep:

- the exact patch intent
- the exact target files
- the exact 8sync commands that re-apply the stable state

That keeps the repo small and makes re-application deterministic after upstream updates.

## Profiles

- `stable-patches/opencode/STABLE.md` — OpenCode stable reinstall / fresh-install profile
- `stable-patches/gsd/STABLE.md` — GSD Anthropic OAuth prompt fix and provider label normalization

## Re-apply commands

### OpenCode

```powershell
8sync opencode reinstall --stable
```

Full clean rebuild:

```powershell
8sync opencode fresh-install --stable --claude=yes --openai=yes
```

### GSD

```powershell
8sync gsd fix --stable
```

Or regenerate routing and auto-apply the patch:

```powershell
8sync gsd setup --model claude+codex --stable
```

## Policy

When a runtime fix proves stable in real use:

1. update the relevant `STABLE.md`
2. update `CHANGELOG.md`
3. keep the 8sync command behavior aligned with the documented profile

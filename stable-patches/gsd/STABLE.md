# GSD Stable Profile

## Status

Known-good and repeatable.

## Goal

Re-apply the proven GSD runtime fix for Anthropic OAuth requests and keep the provider label readable.

## Command

Force patch only:

```powershell
8sync gsd fix --stable
```

Setup plus patch:

```powershell
8sync gsd setup --model claude+codex --stable
```

## What the stable profile does

### Runtime patch

Applies a `#145`-style Anthropic OAuth fix to the GSD runtime provider file:

- target file:
  - `~/.gsd/agent/node_modules/@gsd/pi-ai/dist/providers/anthropic-shared.js`
- behavior:
  - for Anthropic OAuth, keep only:
    - `You are Claude Code, Anthropic's official CLI for Claude.`
  - do **not** append the large GSD `context.systemPrompt`

### UI label normalization

Normalizes the interactive model selector label:

- target file:
  - `~/.gsd/agent/node_modules/@gsd/pi-coding-agent/dist/modes/interactive/components/model-selector.js`
- behavior:
  - `anthropic-api` → `anthropic`

## Stable assumptions

The repo already contains the re-apply logic in:

- `modules/gsd/00-shared.ps1`
- `modules/gsd/10-setup.ps1`
- `modules/gsd/20-interactive.ps1`
- `modules/gsd/30-status.ps1`
- `modules/gsd/50-command.ps1`
- `modules/shell.ps1`
- `modules/core.ps1`

## Verification

Use:

```powershell
8sync gsd status
```

Expected signals:

- `Anthropic OAuth prompt fix   patched`
- `Anthropic UI label           anthropic`

Then start a fresh GSD session and verify Anthropic OAuth requests no longer reproduce the prior prompt-surface failure.

# GSD Stable Profile

## Status

Stable. Runtime JS patching has been removed entirely in favor of `auth-fix`.

## Goal

Fix Anthropic OAuth authentication loops by cleaning stale OAuth entries from `auth.json` and setting Claude Code to CLI-based auth.

## Command

```powershell
8sync gsd auth-fix
```

## What auth-fix does

1. Reads `~/.gsd/agent/auth.json`
2. Removes any `anthropic` OAuth entry (stale tokens cause auth loops)
3. Sets `claude-code` to `{"type": "cli"}` (bypasses OAuth entirely)
4. Writes the cleaned auth.json back

## Setup flow

Install the latest gsd-pi, then run auth-fix:

```powershell
8sync gsd setup --model <plan>
8sync gsd auth-fix
```

No runtime JS patching is needed.

## Verification

```powershell
8sync gsd status
```

Then start a fresh GSD session and verify Anthropic requests work without OAuth loops.

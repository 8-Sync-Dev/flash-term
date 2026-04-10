# OpenCode Stable Profile

## Status

Known-good and repeatable.

## Goal

Restore a working OpenCode install with Claude OAuth and the `#145`-style system-surface reduction already baked in.

## Command

Quick repair:

```powershell
8sync opencode reinstall --stable
```

Full clean rebuild:

```powershell
8sync opencode fresh-install --stable --claude=yes --openai=yes
```

## What the stable profile does

### `reinstall --stable`

- purges OpenCode auth/plugin cache packages
- removes `~/.cache/opencode/package-lock.json`
- force-reapplies the local `oc-bundle/`
- runs `npm i` in `~/.config/opencode`
- reinstalls cache-side plugin dependencies from `cache-package.json`

### `fresh-install --stable`

- uninstalls Claude Code CLI remnants
- deep-cleans OpenCode cache/data while preserving login where possible
- runs `reinstall --stable`
- runs `oh-my-openagent install`

## Stable assumptions

The repo already carries the working OpenCode-side fixes in:

- `oc-bundle/opencode.json`
- `oc-bundle/opencode.json.tmp`
- `oc-bundle/plugins/anthropic-auth.mjs`
- `oc-bundle/plugins/plugins/anthropic-auth.mjs`
- `modules/opencode.ps1`

## Expected outcome

After `fresh-install --stable`:

- Claude OAuth login is available
- the OpenCode Anthropic auth plugin uses the reduced system surface
- the portable bundle and the reinstall flow match

## Recovery check

Use:

```powershell
8sync opencode status
```

Then open OpenCode and verify Claude auth and chat behavior in a fresh session.

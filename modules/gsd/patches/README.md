# Anthropic OAuth restore patch

## What

Upstream `gsd-pi` (commit `c2acb1fb4`, 10 Apr 2026) removed Anthropic OAuth:

> fix(pi-ai): remove Anthropic OAuth flow for TOS compliance

This breaks `/login anthropic` in any version **from 2.70.0 onwards**. You can't log in with Claude Pro/Max subscription anymore through gsd.

## Why these files exist

These are the exact files needed to **restore** Anthropic OAuth locally:

| File | Restores |
|---|---|
| `anthropic-oauth.ts` | Full OAuth module deleted by `c2acb1fb4` (extracted from parent commit `9cbda5e29`) |
| `oauth-index-with-anthropic.ts` | `index.ts` with `anthropicOAuthProvider` re-registered |

In addition, `packages/pi-ai/src/providers/anthropic.ts` must be patched to re-add the OAuth bearer-auth branch. See `8sync gsd local apply-anthropic-patch` command (TODO).

## When patches apply

- ✅ Applied automatically in `8sync gsd local setup --version latest`
- ✅ Verified against upstream main at commit `4c866b677` (gsd-pi 2.76.0)
- ❌ Will break if upstream changes `createClient` signature further — re-check on each upgrade

## TOS note

Anthropic terminated third-party Claude Pro/Max OAuth access. Restoring it locally is a personal-use workaround. For production or commercial use, either:
- Use the official Claude CLI
- Pay for Anthropic API access (`ANTHROPIC_API_KEY`)
- Use Antigravity (Claude via Google Cloud, still OAuth in upstream)

## How to re-extract after future upstream changes

```powershell
cd .gsd/vendor/gsd-pi/latest
git log --oneline --all -S "anthropicOAuthProvider" | head -10
# Find the removal commit, get its parent with ^
git show <parent>:packages/pi-ai/src/utils/oauth/anthropic.ts > ../../../../../modules/gsd/patches/anthropic-oauth.ts
git show <parent>:packages/pi-ai/src/utils/oauth/index.ts > ../../../../../modules/gsd/patches/oauth-index-with-anthropic.ts
```

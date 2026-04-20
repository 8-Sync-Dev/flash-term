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
| `anthropic-provider-with-oauth.ts` | `providers/anthropic.ts` with Bearer-auth branch for `sk-ant-oat*` OAuth tokens + `anthropic-beta: oauth-2025-04-20` header. Without this, the OAuth access token is sent via `x-api-key` and the API returns `401 invalid x-api-key`. |

All three are applied together by `8sync gsd local apply-anthropic-patch` and compiled into `dist/` by `8sync gsd local build`.

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

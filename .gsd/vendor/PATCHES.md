# Applied patches on current/

Each row documents a patch applied to current/ after seeding from baseline.
Review this list when upgrading current/ to a newer baseline, or when cherry-picking from latest/.

| Date | Patch | File | Reason | Upstream? |
|---|---|---|---|---|
| -- | OAuth system prompt #145 fix | packages/pi-ai/dist/providers/anthropic-shared.js | Remove context.systemPrompt append for OAuth tokens | not merged |
| -- | provider label normalize | packages/pi-coding-agent/dist/modes/interactive/components/model-selector.js | anthropic-api -> anthropic | not merged |
| -- | model registry opus-4-7 | packages/pi-ai/dist/models.generated.js + models.js | Add claude-opus-4-7 entry and xhigh capability | upstream in newer versions |

## Re-application procedure

1. Diff baseline vs current: git diff --no-index baseline-<ver>/ current/
2. Apply each patch above to the new baseline.
3. Verify via 8sync gsd local fix --dry-run.
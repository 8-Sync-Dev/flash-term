---
version: 1
skill_staleness_days: 0
uat_dispatch: false
unique_milestone_ids: false
notifications:
cmux:
  enabled: false
  notifications: false
  sidebar: false
  splits: false
  browser: false
remote_questions:
phases:
  skip_research: false
  skip_reassess: false
  skip_slice_research: false
  reassess_after_slice: false

dynamic_routing:
  enabled: false

token_profile: balanced

models:
  # ══════════════════════════════════════════════════════════════════════════════
  # PLAN: claude-code — Bridge qua Forge's Claude Code OAuth subscription
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   forge provider login claude_code  → OAuth token synced to ANTHROPIC_API_KEY
  #   Token auto-refresh via:  Sync-ForgeClaudeCodeToken (bootstrap function)
  #
  # HOW IT WORKS:
  #   Forge stores Claude Code OAuth tokens in ~/.forge/.credentials.json
  #   Bootstrap reads the access_token and exports as ANTHROPIC_API_KEY
  #   gsd-pi uses it for direct Anthropic API calls (no Claude CLI subprocess)
  #   Token refresh happens automatically when expired (OAuth2 refresh_token)
  #
  # COST: $0 — covered by Claude Code subscription (Pro/Max/Team)
  #   All models show zero cost because inference is subscription-based.
  #
  # STRATEGY:
  #   planning/research  → Opus 4.7 (deepest reasoning, planning king, 1M ctx)
  #   execution          → Sonnet 4.6 (agentic workhorse, 1M ctx)
  #   execution_simple   → Haiku 4.5 (fast, efficient)
  #   validation         → Sonnet 4.6 (review, same-provider consistency)
  #   completion         → Sonnet 4.6 (quality summary)
  #   subagent           → Sonnet 4.6 primary, Haiku fallback
  #
  # USE WHEN:
  #   - Forge đã login claude_code provider (forge provider login claude_code)
  #   - Muốn 100% Claude, zero API cost (subscription covers all)
  #   - Cùng auth như Forge Code đang dùng
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: claude-code/claude-opus-4-7
    fallbacks:
      - claude-code/claude-opus-4-6
      - claude-code/claude-sonnet-4-6

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: claude-code/claude-opus-4-7
    fallbacks:
      - claude-code/claude-opus-4-6
      - claude-code/claude-sonnet-4-6

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: claude-code/claude-sonnet-4-6
    fallbacks:
      - claude-code/claude-opus-4-7
      - claude-code/claude-haiku-4-5

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: claude-code/claude-haiku-4-5
    fallbacks:
      - claude-code/claude-sonnet-4-6

  # ── VALIDATION (reviewer) ───────────────────────────────────────────────────
  validation:
    model: claude-code/claude-sonnet-4-6
    fallbacks:
      - claude-code/claude-opus-4-7

  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: claude-code/claude-sonnet-4-6
    fallbacks:
      - claude-code/claude-haiku-4-5

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: claude-code/claude-sonnet-4-6
    fallbacks:
      - claude-code/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

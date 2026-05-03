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
  # PLAN: claude-max — 100% Claude via claude-code provider (Opus + Sonnet + Haiku)
  # ──────────────────────────────────────────────────────────────────────────────
  # PROVIDER: claude-code (flat-rate, $0 API cost via Claude Code subscription)
  #   Routes through Claude Code CLI bridge → subscription-based inference
  #   All models show zero cost in GSD TUI
  #
  # AUTH REQUIRED:
  #   8sync gsd forge-sync   (or: forge provider login claude_code)
  #
  # MODELS AVAILABLE:
  #   claude-opus-4-7    (1M ctx, reasoning+planning king)
  #   claude-opus-4-6    (1M ctx, fallback)
  #   claude-sonnet-4-6  (1M ctx, agentic workhorse)
  #   claude-haiku-4-5   (200K ctx, fast, low cost)
  #
  # STRATEGY:
  #   planning/research  → Opus 4-7 (deepest reasoning, 1M ctx)
  #   execution          → Sonnet 4-6 (agentic workhorse)
  #   execution_simple   → Haiku 4-5 (fast, low cost)
  #   validation         → Sonnet 4-6 (review, same-provider consistency)
  #   completion         → Sonnet 4-6 (quality summary)
  #   subagent           → Sonnet 4-6 primary, Haiku fallback
  #
  # USE WHEN:
  #   - Có Claude Code subscription (Pro $20/Max $100/Team)
  #   - Muốn 100% Claude, zero API cost (subscription covers all)
  #   - Cần deterministic behavior, chỉ một provider duy nhất
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

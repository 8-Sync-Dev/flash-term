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
  # PLAN: claude-max — 100% Claude Anthropic only (Opus + Sonnet + Haiku)
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login anthropic  → claude-opus-4-6 ($5/$25/M)
  #                       claude-sonnet-4-6 ($3/$15/M)
  #                       claude-haiku-4-5 ($0.8/$4/M)
  #
  # STRATEGY:
  #   planning/research  → Opus 4-6 (deepest reasoning, planning king)
  #   execution          → Sonnet 4-6 (agentic workhorse)
  #   execution_simple   → Haiku 4-5 (fast, low cost)
  #   validation         → Sonnet 4-6 (review, same-provider consistency)
  #   completion         → Sonnet 4-6 (quality summary)
  #   subagent           → Sonnet 4-6 primary, Haiku fallback
  #
  # USE WHEN:
  #   - Có claude.ai Max subscription ($100/mo) hoặc paid Anthropic API key
  #   - Muốn 100% Claude, zero external dependencies
  #   - Cần deterministic behavior, chỉ một provider duy nhất
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - anthropic/claude-sonnet-4-6

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - anthropic/claude-opus-4-6
      - anthropic/claude-haiku-4-5

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: anthropic/claude-haiku-4-5
    fallbacks:
      - anthropic/claude-sonnet-4-6

  # ── VALIDATION (reviewer) ───────────────────────────────────────────────────
  validation:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - anthropic/claude-opus-4-6

  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

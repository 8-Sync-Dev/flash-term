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
  # PLAN: claude-codex-review — Opus/Sonnet code + Codex validates/reviews
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login anthropic    → claude-opus-4-6 ($5/$25/M)
  #                         claude-sonnet-4-6 ($3/$15/M)
  #   /login openai-codex → gpt-5.3-codex (free via ChatGPT OAuth)
  #
  # STRATEGY:
  #   planning/research   → Opus 4-6 (deepest reasoning, planning king)
  #   execution           → Sonnet 4-6 (agentic workhorse)
  #   execution_simple    → Sonnet 4-6 (consistent quality, no downgrade)
  #   validation          → Codex (cross-model review, fresh eyes on Claude output)
  #   completion          → Codex (summary, UAT, milestone gate)
  #   subagent            → Codex (parallel cheap tasks)
  #
  # WHY CODEX AS REVIEWER:
  #   - Cross-model peer review: different model catches different blind spots
  #   - Codex is free via OAuth, so review phase costs $0
  #   - Fallback to Sonnet if Codex unavailable
  #
  # USE WHEN:
  #   - Có Claude Max + ChatGPT Plus/Pro subscription
  #   - Muốn Claude code chính, Codex review miễn phí
  #   - Cần cross-model validation để giảm blind spots
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
      - openai-codex/gpt-5.3-codex

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - openai-codex/gpt-5.3-codex

  # ── VALIDATION (reviewer — Codex reviews Claude's output) ───────────────────
  validation:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6

  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

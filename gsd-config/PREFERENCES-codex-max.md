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
  # PLAN: codex-max — 100% OpenAI Codex / GPT only
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login openai-codex  → gpt-5.4, gpt-5.3-codex, gpt-5.1-codex-max (ChatGPT OAuth, free)
  #   OR: 8sync gsd key openai <key>  → paid OpenAI API key
  #
  # STRATEGY:
  #   planning/research  → gpt-5.4 (OpenAI flagship, frontier reasoning)
  #   execution          → gpt-5.3-codex (coding specialist, SWE optimized)
  #   execution_simple   → gpt-5.1-codex-max (fast, lightweight)

  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - claude-code/claude-sonnet-4-6
  #   completion         → gpt-5.3-codex (precise summary)
  #   subagent           → gpt-5.3-codex primary, gpt-5.1-codex-max workers
  #
  # USE WHEN:
  #   - Có ChatGPT Plus/Pro ($20-$200/mo) với codex access
  #   - Muốn 100% OpenAI ecosystem, zero Anthropic/Google dependency
  #   - Cần GPT-specific tool calling / function calling behavior
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - github-copilot/gpt-5.4

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - github-copilot/gpt-5.4

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.4
      - github-copilot/gpt-5.4
      - openai-codex/gpt-5.1-codex-max

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: openai-codex/gpt-5.1-codex-max
    fallbacks:
      - openai-codex/gpt-5.3-codex


  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.1-codex-max

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.1-codex-max
      - github-copilot/gpt-5.4
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

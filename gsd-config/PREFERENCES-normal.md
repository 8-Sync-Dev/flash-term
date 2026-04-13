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
  # PLAN: normal — no Claude cost, glm-5.1 primary, free-tier fallbacks
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login google-gemini-cli → gemini-3.1-pro-preview (free, 2M ctx)
  #   /login openai-codex      → gpt-5.3-codex (free OAuth, planning only)
  #   8sync gsd key zai <key>  → glm-5.1 + glm-5-turbo ($1.2/$4/M)
  #   8sync gsd key groq <key> → kimi-k2-instruct + qwen3-32b (FREE daily reset)
  #
  # STRATEGY:
  #   planning/research  → gemini-3.1-pro (free) + codex gpt-5.3 (free, planning only)
  #   execution          → glm-5.1 primary (agentic S+), glm-5-turbo/groq fallback
  #   execution_simple   → groq free cascade

  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
  #   completion         → glm-5.1 + glm-5-turbo
  #   subagent           → glm-5.1 primary, full groq/zai cascade
  #
  # NOTE: openai-codex is intentionally NOT in execution/subagent/completion
  #   fallbacks — its "usage limit" error pauses auto-mode entirely instead of
  #   continuing the chain. Keep codex only in planning/research where it's
  #   less likely to hit daily quota during a single run.
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: google-gemini-cli/gemini-3.1-pro-preview
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - zai/glm-5.1
      - zai/glm-5-turbo

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: google-gemini-cli/gemini-3.1-pro-preview
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - zai/glm-5.1
      - zai/glm-5-turbo

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - groq/kimi-k2-instruct
      - groq/qwen/qwen3-32b

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: groq/kimi-k2-instruct
    fallbacks:
      - groq/qwen/qwen3-32b
      - zai/glm-4.5
      - zai/glm-4.5-air
      - zai/glm-4.7


  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - groq/kimi-k2-instruct
      - groq/qwen/qwen3-32b

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: zai/glm-4.5
    fallbacks:
      - zai/glm-5.1
      - zai/glm-5-turbo
      - zai/glm-5
      - groq/kimi-k2-instruct
      - groq/qwen/qwen3-32b
      - zai/glm-4.5-air
      - zai/glm-4.7
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

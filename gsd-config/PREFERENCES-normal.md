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

token_profile: balanced

models:
  # ══════════════════════════════════════════════════════════════════════════════
  # PLAN: normal — tier thấp hơn nhưng vẫn mạnh, tối đa free tier
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login anthropic        → haiku-4-5 ($1/$5/M) ← chỉ emergency fallback
  #   /login google-gemini-cli → gemini-3.1-pro-preview (free)
  #   /login openai-codex     → gpt-5.1-codex-max, gpt-5.3-codex (free OAuth)
  #   8sync gsd key zai <key>         → glm-5-turbo ($1.2/$4/M), glm-4.7 ($0.39/$1.75/M)
  #   8sync gsd key groq <key>        → kimi-k2-instruct + qwen3-32b (FREE daily)
  #   8sync gsd key google <key>      → gemini-2.5-pro / gemini-2.5-flash (free tier)
  #
  # STRATEGY:
  #   Không dùng Opus/Sonnet trả phí — thay bằng codex (OAuth free) + gemini (free)
  #   planning/research  → codex gpt-5.3 + gemini-3.1-pro (cả hai free/low cost)
  #   execution          → glm-5-turbo primary (agentic, rẻ), groq fallback free
  #   execution_simple   → groq hoàn toàn miễn phí
  #   completion         → glm-5-turbo + codex
  #   subagent           → groq free cascade hoàn toàn
  #   Claude chỉ là emergency last resort (haiku)
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview
      - zai/glm-5-turbo
      - google-gemini-cli/gemini-3.1-pro-preview
      - anthropic/claude-haiku-4-5

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - zai/glm-5-turbo
      - google-gemini-cli/gemini-3.1-pro-preview

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: zai/glm-5-turbo
    fallbacks:
      - openai-codex/gpt-5.1-codex-max
      - zai/glm-5
      - groq/kimi-k2-instruct
      - anthropic/claude-haiku-4-5

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: groq/kimi-k2-instruct
    fallbacks:
      - groq/qwen/qwen3-32b
      - zai/glm-4.7
      - zai/glm-4.7-flash
      - zai/glm-4.6

  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: zai/glm-5-turbo
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - groq/kimi-k2-instruct
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: groq/kimi-k2-instruct
    fallbacks:
      - groq/qwen/qwen3-32b
      - zai/glm-5-turbo
      - zai/glm-4.7
      - zai/glm-4.7-flash
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

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
  # PLAN: max — tập trung mạnh nhất, coding-first
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login anthropic        → claude-opus-4-6  ($5/$25/M), sonnet-4-6 ($3/$15/M)
  #   /login github-copilot   → gpt-5.4, gpt-5.3-codex, gemini-3.1-pro (subscription)
  #   /login google-gemini-cli → gemini-3.1-pro-preview (Cloud Code Assist, free)
  #   /login openai-codex     → gpt-5.3-codex, gpt-5.4 (ChatGPT OAuth, free)
  #   8sync gsd key kimi-coding <key> → k2p5 / Kimi K2.5 (SWE-bench 76.8%, free credits)
  #   8sync gsd key zai <key>         → glm-5-turbo ($1.2/$4/M), glm-5 ($0.72/$2.3/M)
  #   8sync gsd key groq <key>        → kimi-k2-instruct + qwen3-32b (FREE daily reset)
  #   8sync gsd key google <key>      → gemini-2.5-pro (5 RPM / 25 RPD free, fallback)
  #
  # TIER RANKING (coding SWE-bench):
  #   S++ : kimi-coding/k2p5                 76.8%  — coding SOTA
  #   S+  : anthropic/claude-opus-4-6        ~72%   — reasoning + planning king
  #         github-copilot/gpt-5.4           frontier codex-optimized
  #   S   : anthropic/claude-sonnet-4-6      agentic workhorse
  #         openai-codex/gpt-5.3-codex       coding specialist (OAuth free)
  #         github-copilot/gemini-3.1-pro    1M+ ctx breadth
  #   A   : zai/glm-5-turbo                  agentic-optimized, fast
  #         zai/glm-5                        open-source SOTA
  #   B   : groq/kimi-k2-instruct            ~65% SWE, FREE daily
  #         groq/qwen/qwen3-32b              reasoning, FREE 14400 RPD
  #
  # STRATEGY:
  #   planning/research  → Opus 4.6 primary (deepest reasoning)
  #   execution          → kimi K2.5 primary (best coding), codex + glm fallback
  #   execution_simple   → groq free (zero cost) cascade

  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
  #   completion         → Sonnet 4.6 (quality summary, không cần Opus)
  #   subagent           → kimi K2.5 primary, groq free workers
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - kimi-coding/k2p5
      - github-copilot/gpt-5.4
      - github-copilot/gemini-3.1-pro-preview
      - anthropic/claude-sonnet-4-6

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview
      - kimi-coding/k2p5
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: kimi-coding/k2p5
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - zai/glm-5-turbo
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: groq/kimi-k2-instruct
    fallbacks:
      - groq/qwen/qwen3-32b
      - zai/glm-5-turbo
      - zai/glm-5
      - anthropic/claude-haiku-4-5


  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - kimi-coding/k2p5
      - zai/glm-5-turbo
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: kimi-coding/k2p5
    fallbacks:
      - groq/kimi-k2-instruct
      - groq/qwen/qwen3-32b
      - zai/glm-5-turbo
      - zai/glm-5
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

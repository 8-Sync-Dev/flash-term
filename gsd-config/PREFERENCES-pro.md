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
  # PLAN: pro — cân bằng mạnh + tiết kiệm, coding-first
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login anthropic        → sonnet-4-6 ($3/$15/M)  ← Claude chỉ dùng planning/completion
  #   /login google-gemini-cli → gemini-3.1-pro-preview (free, large ctx)
  #   /login openai-codex     → gpt-5.3-codex, gpt-5.1-codex-max (free OAuth)
  #   8sync gsd key kimi-coding <key> → k2p5 (SWE 76.8%, free credits)
  #   8sync gsd key zai <key>         → glm-5-turbo ($1.2/$4/M), glm-5, glm-4.7
  #   8sync gsd key groq <key>        → kimi-k2-instruct + qwen3-32b (FREE daily)
  #
  # STRATEGY:
  #   Claude dùng Sonnet (không Opus) — đủ mạnh, tiết kiệm hơn 40%
  #   Claude chỉ ở planning/research/completion — KHÔNG dùng cho execution
  #   execution primary → kimi K2.5 + codex (zero/low cost, coding SOTA)
  #   execution_simple  → groq free hoàn toàn
  #   subagent          → groq free workers + kimi K2.5 cho task quan trọng
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - kimi-coding/k2p5
      - github-copilot/gemini-3.1-pro-preview
      - openai-codex/gpt-5.3-codex

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview
      - kimi-coding/k2p5
      - openai-codex/gpt-5.3-codex

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  # Không dùng Claude ở đây — kimi + codex đủ mạnh, rẻ hơn nhiều
  execution:
    model: kimi-coding/k2p5
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - zai/glm-5-turbo
      - zai/glm-5
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: groq/kimi-k2-instruct
    fallbacks:
      - groq/qwen/qwen3-32b
      - zai/glm-5-turbo
      - zai/glm-4.7
      - zai/glm-4.7-flash


  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - zai/glm-5-turbo
      - kimi-coding/k2p5
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: groq/kimi-k2-instruct
    fallbacks:
      - groq/qwen/qwen3-32b
      - kimi-coding/k2p5
      - zai/glm-5-turbo
      - zai/glm-4.7
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

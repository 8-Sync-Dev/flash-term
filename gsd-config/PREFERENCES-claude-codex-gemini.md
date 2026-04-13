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
  # PLAN: claude-codex-gemini — The Big Three combo (Anthropic + OpenAI + Google)
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login anthropic          → claude-opus-4-6, claude-sonnet-4-6
  #   /login openai-codex       → gpt-5.4, gpt-5.3-codex (ChatGPT OAuth, free)
  #   /login google-gemini-cli  → gemini-3.1-pro-preview (Cloud Code Assist, free)
  #   /login github-copilot     → all three via Copilot (subscription)
  #
  # TIER RANKING:
  #   Planning  : Opus 4-6 (deepest reasoning) → gpt-5.4 → gemini-3.1-pro
  #   Research  : Opus 4-6 (breadth+depth) → gemini-3.1-pro (2M ctx) → gpt-5.4
  #   Execution : gpt-5.3-codex (coding SOTA) → Sonnet 4-6 → gemini-3.1-pro
  #   Simple    : gemini-3.1-pro-preview (free, large ctx) → gpt-5.1-codex-max

  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
  #   Completion: Sonnet 4-6 (quality) → gpt-5.3-codex → gemini-3.1-pro
  #   Subagent  : gpt-5.3-codex → Sonnet 4-6 → gemini-3.1-pro
  #
  # STRATEGY:
  #   Dùng strengths của từng provider:

  #   - Claude  : planning, reasoning, nuanced completion
  #   - Codex   : execution workhorse, coding-specialist SWE tasks
  #   - Gemini  : research (2M ctx), fallback execution, long-doc tasks
  #
  # USE WHEN:
  #   - Có access cả 3 nền tảng (subscriptions hoặc OAuth free)
  #   - Muốn best-of-three cho từng phase của GSD workflow
  #   - Không muốn phụ thuộc một provider duy nhất
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - openai-codex/gpt-5.4
      - github-copilot/gpt-5.4
      - github-copilot/gemini-3.1-pro-preview
      - anthropic/claude-sonnet-4-6

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview
      - openai-codex/gpt-5.4
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
      - github-copilot/gpt-5.4
      - github-copilot/gemini-3.1-pro-preview

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - openai-codex/gpt-5.1-codex-max
      - anthropic/claude-haiku-4-5


  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - openai-codex/gpt-5.3-codex
      - github-copilot/gemini-3.1-pro-preview
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - anthropic/claude-sonnet-4-6
      - github-copilot/gemini-3.1-pro-preview
      - openai-codex/gpt-5.1-codex-max
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

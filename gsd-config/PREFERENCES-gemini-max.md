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
  # PLAN: gemini-max — 100% Google Gemini only
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   /login google-gemini-cli  → gemini-3.1-pro-preview (Cloud Code Assist, free)
  #   /login github-copilot     → github-copilot/gemini-3.1-pro (subscription)
  #   OR: 8sync gsd key google <key>  → gemini-2.5-pro API key (5 RPM/25 RPD free)
  #
  # STRATEGY:
  #   planning/research  → gemini-3.1-pro-preview (2M ctx, deep reasoning)
  #   execution          → gemini-3.1-pro-preview (massive context = whole-repo edits)
  #   execution_simple   → gemini-2.5-pro (API key, low quota fallback)

  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: claude-code/claude-sonnet-4-6
    fallbacks:
      - claude-code/claude-opus-4-6
  #   completion         → gemini-3.1-pro-preview (large-ctx summary)
  #   subagent           → gemini-3.1-pro-preview primary
  #
  # USE WHEN:
  #   - Có Google Cloud Code Assist (miễn phí qua /login google-gemini-cli)
  #   - Cần context window cực lớn (2M tokens) cho monorepo / long docs
  #   - Muốn 100% Google ecosystem, no Anthropic/OpenAI cost
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - google/gemini-2.5-pro
      - github-copilot/gemini-3.1-pro

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - google/gemini-2.5-pro
      - github-copilot/gemini-3.1-pro

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - github-copilot/gemini-3.1-pro
      - google/gemini-2.5-pro

  # ── EXECUTION (simple) ──────────────────────────────────────────────────────
  execution_simple:
    model: google/gemini-2.5-pro
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview


  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - google/gemini-2.5-pro

  # ── SUBAGENT ────────────────────────────────────────────────────────────────
  subagent:
    model: github-copilot/gemini-3.1-pro-preview
    fallbacks:
      - google/gemini-2.5-pro
      - github-copilot/gemini-3.1-pro
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

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
  # ===========================================================================
  # PLAN: claude-codex-review - Opus plans/researches, Codex codes/reviews
  # ---------------------------------------------------------------------------
  # AUTH REQUIRED:
  #   /login anthropic    -> claude-opus-4-7, claude-opus-4-6 fallback
  #   /login openai-codex -> gpt-5.4, gpt-5.3-codex fallback (ChatGPT OAuth)
  #
  # STRATEGY:
  #   planning/research   -> Opus 4-7 (deep architecture, scope, decisions)
  #   execution           -> GPT-5.4 (100% Codex coding path)
  #   execution_simple    -> gpt-5.3-codex (fast/simple Codex coding path)
  #   validation          -> GPT-5.4 (Codex review/gate)
  #   completion          -> GPT-5.4 (summary, UAT, milestone gate)
  #   subagent            -> gpt-5.3-codex (parallel Codex workers)
  #
  # WHY THIS STACK:
  #   - Opus stays in high-leverage planning/research where reasoning depth matters.
  #   - Codex owns code execution so implementation stays consistent across tasks.
  #   - GPT-5.4 reviews and completes; gpt-5.3-codex is the cheaper/faster fallback.
  #
  # USE WHEN:
  #   - Co Claude Max + ChatGPT Plus/Pro subscription
  #   - Muon Opus suy nghi sau nhung code 100% bang Codex
  #   - Can cross-model planning/execution split for large projects
  # ===========================================================================

  # -- PLANNING ---------------------------------------------------------------
  planning:
    model: claude-code/claude-opus-4-7
    fallbacks:
      - claude-code/claude-opus-4-6
      - openai-codex/gpt-5.4
      - openai-codex/gpt-5.3-codex

  # -- RESEARCH ---------------------------------------------------------------
  research:
    model: claude-code/claude-opus-4-7
    fallbacks:
      - claude-code/claude-opus-4-6
      - openai-codex/gpt-5.4
      - openai-codex/gpt-5.3-codex

  # -- EXECUTION (standard) ---------------------------------------------------
  execution:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex

  # -- EXECUTION (simple) -----------------------------------------------------
  execution_simple:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.4

  # -- VALIDATION -------------------------------------------------------------
  validation:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex

  # -- COMPLETION -------------------------------------------------------------
  completion:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex

  # -- SUBAGENT ---------------------------------------------------------------
  subagent:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.4
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

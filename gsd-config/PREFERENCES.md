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
  # PROVIDER IDs (đang active):
  #   anthropic        → claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5
  #                      (OAuth, +8h; refresh với /login)
  #   github-copilot   → claude-opus-4.6, claude-sonnet-4.6, gpt-5, gpt-5.1-codex-max
  #                      gemini-3.1-pro-preview  (OAuth, refresh thường với /login)
  #   zai              → glm-5-turbo, glm-5, glm-4.7, glm-4.6,
  #                      glm-4.7-flash, glm-4.5  (api_key, stable)
  #
  #   google-gemini-cli → EXPIRED — cần /login để dùng lại
  #   openai-codex      → không có auth
  #
  # TIER RANKING:
  #   Frontier S : anthropic/claude-opus-4-6           (depth/reasoning, planning)
  #   Frontier A : anthropic/claude-sonnet-4-6         (agentic workhorse)
  #                github-copilot/gemini-3.1-pro-preview (breadth, large-ctx)
  #                github-copilot/gpt-5.1-codex-max    (coding specialist)
  #   Frontier B : anthropic/claude-haiku-4-5          (fast/cheap)
  #
  #   GLM S : zai/glm-5-turbo  ($1.2/$4,  mạnh+nhanh nhất)
  #   GLM A : zai/glm-5        ($0.72/$2.3)
  #   GLM B : zai/glm-4.7      ($0.39/$1.75, reasoning, 202K ctx)
  #   GLM C : zai/glm-4.6      ($0.39/$1.74, concurrency 3)
  #   GLM D : zai/glm-4.7-flash ($0.06/$0.40, rẻ nhất)
  #            zai/glm-4.5     ($0.60/$2.20, concurrency 10)
  #
  # RULES:
  #   planning / research → frontier only (anthropic primary, copilot secondary)
  #   execution           → zai primary, anthropic fallback
  #   execution_simple    → zai only, cascade D
  #   completion          → anthropic-led, zai fallback
  #   subagent            → zai primary, haiku emergency fallback
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING: kiến trúc, milestone design — frontier only ───────────────────
  # Opus 4.6: depth + reasoning, tốt nhất cho complex decisions
  # Copilot Gemini 3.1 Pro: breadth + large-ctx, secondary frontier
  # Sonnet 4.6: agentic fallback khi Opus queue/fail
  # Copilot GPT-5.1 Codex Max: coding-specialist frontier
  planning:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview
      - anthropic/claude-sonnet-4-6
      - github-copilot/gpt-5.1-codex-max

  # ── RESEARCH: phân tích, nghiên cứu — frontier only ─────────────────────────
  # Opus 4.6: depth reasoning cho phân tích sâu
  # Copilot Gemini 3.1 Pro: large-ctx research
  # Sonnet 4.6: agentic research workhorse
  research:
    model: anthropic/claude-opus-4-6
    fallbacks:
      - github-copilot/gemini-3.1-pro-preview
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (standard): code khá→khó — zai primary, frontier fallback ──────
  # GLM-5 Turbo: mạnh+nhanh nhất GLM, tối ưu cho agentic coding
  # GLM-5: open-source SOTA, rẻ hơn Turbo
  # Sonnet 4.6: frontier fallback khi GLM fail/queue
  # GLM-4.7: last GLM fallback, reasoning tốt, 202K ctx
  execution:
    model: zai/glm-5-turbo
    fallbacks:
      - zai/glm-5
      - zai/glm-4.7
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (simple): task đơn giản — zai only, cascade D ──────────────────
  # GLM-4.7: reasoning + 202K ctx, đủ mạnh cho task thường
  # GLM-4.6: concurrency 3, stable
  # GLM-4.7-Flash: rẻ nhất ($0.06)
  # GLM-4.5: concurrency 10, dùng khi cần nhiều task song song
  # Haiku 4.5: frontier fallback cuối nếu tất cả GLM fail
  execution_simple:
    model: zai/glm-4.7
    fallbacks:
      - zai/glm-4.6
      - zai/glm-4.7-flash
      - zai/glm-4.5
      - anthropic/claude-haiku-4-5

  # ── COMPLETION: wrap-up, summary, validate — frontier-led ────────────────────
  # Sonnet 4.6: tốt nhất cho summary quality
  # GLM-5 Turbo: fallback rẻ khi Sonnet queue/fail
  # GLM-5: tiếp theo
  # Haiku 4.5: fast frontier last resort
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT: scout, researcher, worker — zai primary, cascade full ──────────
  # GLM-5 Turbo: mạnh + nhanh, primary cho mọi subagent task
  # GLM-5: fallback A-tier
  # GLM-4.7: B-tier, reasoning + large ctx
  # GLM-4.6: C-tier, concurrency 3
  # GLM-4.7-Flash: D-tier $0.06, rẻ nhất khi queue nhiều
  # GLM-4.5: D-tier concurrency 10
  # Haiku 4.5: frontier emergency fallback
  subagent:
    model: zai/glm-5-turbo
    fallbacks:
      - zai/glm-5
      - zai/glm-4.7
      - zai/glm-4.6
      - zai/glm-4.7-flash
      - zai/glm-4.5
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

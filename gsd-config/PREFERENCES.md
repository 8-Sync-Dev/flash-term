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
  #   zai              → TEXT: glm-5.1(S+,c?), glm-5-turbo(c1), glm-5(c2), glm-4.7(c2,202K),
  #                            glm-4.6(c3,200K), glm-4.5(c20), glm-4.7-flash(c1,$0.06),
  #                            glm-4.7-flashx(c3), glm-4.5-air(c5), glm-4.5-airx(c5),
  #                            glm-4.5-flash(c2,free), glm-4-plus(c20,legacy)
  #                      VISION: glm-4.6v(c10,$0.30/$0.90,128K,img+video+PDF+tool), 
  #                              glm-4.6v-flash(c1,9B,fast), glm-4.6v-flashx(c3),
  #                              glm-4.5v(c10,$0.60/$1.80,66K,img+video)
  #                      SPECIAL: glm-ocr(c2), glm-image(gen,c1), glm-asr-2512(audio,c5)
  #                      VIDEO GEN: vidu-q1/vidu2/cogvideox-3 (per-video billing)
  #                      NOTE: concurrency limit = max parallel in-flight requests
  #                            c1 = bottle-neck for subagent; c10/c20 = ideal for parallel tasks
  #
  #   google-gemini-cli → EXPIRED — cần /login để dùng lại
  #   openai-codex      → không có auth
  #
  # TIER RANKING (SWE-bench Verified, Mar 2026):
  #   Tier S  : anthropic/claude-opus-4-6     80.8%  ($5/$25/M, planning king)
  #             github-copilot/gemini-3.1-pro 80.6%  (free via copilot, 2M ctx)
  #             GPT-5.4                        ~80%   (terminal-bench 75.1%)
  #             Kimi K2.5                      ~77%   (exec SWE)
  #   Tier A  : anthropic/claude-sonnet-4-6   ($3/$15/M, agentic workhorse)
  #             google-gemini-cli/gemini-3.1   80.6%  (free, 2M ctx) ← NGANG Opus!
  #             zai/glm-5.1                    77.8%  (#1 open-weight SWE-bench)
  #             zai/glm-5-turbo                (~A, nhanh, agentic-optimized)
  #   Tier B  : anthropic/claude-haiku-4-5    (fast/cheap)
  #             zai/glm-5                      (A open-weight, $0.72/$2.3)
  #   Tier C  : zai/glm-4.7                   ($0.39/$1.75, 202K ctx)
  #             zai/glm-4.6                    ($0.39/$1.74)
  #   Tier D  : zai/glm-4.7-flash             ($0.06 cheapest)
  #             zai/glm-4.5                    ($0.60, concurrency 10)
  #
  # NOTE về codex (openai-codex OAuth):
  #   Free tier bị rate-limit nghiêm. "Usage limit" error → pi pause auto-mode thay vì
  #   continue fallback chain. Chỉ dùng cho planning/research role, KHÔNG đặt vào
  #   execution/subagent/completion fallback chains.
  #
  # RULES:
  #   planning / research → gemini-3.1 primary (free, 2M ctx, ngang Opus SWE), Opus fallback
  #   execution           → zai/glm-5.1 primary, fallback cascade (KHÔNG có codex)
  #   execution_simple    → zai cascade D
  #   completion          → anthropic-led, zai fallback
  #   subagent            → zai/glm-5.1 primary, cascade full (KHÔNG có codex)
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

  # ── EXECUTION (standard): code khá→khó — glm-5.1 primary, frontier fallback ──
  # GLM-5.1: S+ tier, agentic coding tốt hơn GLM-5, gần Opus 4.6
  # GLM-5 Turbo: S tier, nhanh + agentic-optimized
  # GLM-5: A tier, fallback rẻ
  # Sonnet 4.6: frontier fallback khi GLM fail/queue
  execution:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - anthropic/claude-sonnet-4-6

  # ── EXECUTION (simple): task đơn giản — c20 models first, cascade D ──────────
  # GLM-4.5: c20 concurrency — best cho parallel simple tasks
  # GLM-4.5-Air: c5, lighter variant
  # GLM-4.7: c2, reasoning + 202K ctx
  # GLM-4.6: c3, stable 200K
  # GLM-4.7-Flash: c1 $0.06 nhưng bottle-neck nếu nhiều task
  # GLM-4.7-FlashX: c3 fast flash
  # Haiku 4.5: frontier fallback cuối nếu tất cả GLM fail
  execution_simple:
    model: zai/glm-4.5
    fallbacks:
      - zai/glm-4.5-air
      - zai/glm-4.7
      - zai/glm-4.6
      - zai/glm-4.7-flashx
      - anthropic/claude-haiku-4-5

  # ── COMPLETION: wrap-up, summary, validate — frontier-led ────────────────────
  # Sonnet 4.6: tốt nhất cho summary quality
  # GLM-5.1: fallback mạnh khi Sonnet queue/fail
  # GLM-5 Turbo: fallback nhanh
  # Haiku 4.5: fast frontier last resort
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - zai/glm-5.1
      - zai/glm-5-turbo
      - anthropic/claude-haiku-4-5

  # ── SUBAGENT: scout, researcher, worker — concurrency-aware ──────────────────
  # GLM-4.5: c20 — ideal parallel worker (không bottle-neck)
  # GLM-5.1: S+ tier primary cho complex scout/research
  # GLM-5 Turbo: c1 — chỉ dùng khi cần quality, tránh parallel
  # GLM-5: c2, A-tier fallback
  # GLM-4.5-Air: c5, lightweight
  # GLM-4.7: c2, reasoning
  # GLM-4.6: c3, stable
  # GLM-4.7-FlashX: c3, fast flash
  # Haiku 4.5: frontier emergency fallback
  subagent:
    model: zai/glm-4.5
    fallbacks:
      - zai/glm-5.1
      - zai/glm-5-turbo
      - zai/glm-5
      - zai/glm-4.5-air
      - zai/glm-4.7
      - zai/glm-4.6
      - zai/glm-4.7-flashx
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

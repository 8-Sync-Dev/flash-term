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
  # PROVIDER IDs (từ auth.json):
  #   anthropic        → claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5
  #   google-gemini-cli → gemini-3.1-pro, gemini-3-flash
  #   openai-codex      → gpt-5.3-codex, gpt-5.2
  #   z-coding-plan     → glm-5-turbo, glm-5, glm-4.7, glm-4.7-flashx,
  #                        glm-4.6, glm-4.7-flash, glm-4.5
  #
  # TIER RANKING (hiệu năng thực + giá, March 2026):
  #
  #   Frontier S : gemini-3.1-pro ($2/$12, SWE 80.6%, ARC-AGI 77.1%)
  #                claude-opus-4-6 ($5/$25, SWE 80.8%, depth/reasoning #1)
  #                gpt-5.3-codex   (OAuth, Terminal-Bench 77.3%, coding specialist)
  #   Frontier A : claude-sonnet-4-6 ($3/$15, SWE 79.6%, GDPval-AA #1, agentic)
  #                gpt-5.2         ($1.75/$14, SWE 80%, balanced)
  #   Frontier B : gemini-3-flash  ($0.5/$3, fast, multimodal, SWE 78%)
  #
  #   GLM S : glm-5-turbo  ($1.2/$4,  concurrency 1, mạnh+nhanh nhất GLM)
  #   GLM A : glm-5        ($0.72/$2.3, concurrency 2, open-source SOTA)
  #   GLM B : glm-4.7      ($0.39/$1.75, concurrency 2, reasoning, 202K ctx)
  #   GLM C : glm-4.7-flashx (~$0.10/$0.50, concurrency 3, nhanh)
  #            glm-4.6     ($0.39/$1.74, concurrency 3)
  #   GLM D : glm-4.7-flash ($0.06/$0.40, concurrency 1, rẻ nhất)
  #            glm-4.5     ($0.60/$2.20, concurrency 10, nhiều nhất)
  #            claude-haiku-4-5 ($1/$5, nhanh nhẹ)
  #
  # RULES:
  #   planning / research → frontier only (cần depth phân tích, không dùng GLM)
  #   execution           → GLM primary (rẻ + đủ mạnh code), frontier fallback
  #   execution_simple    → GLM only, cascade xuống D
  #   completion          → frontier-led (quality summary)
  #   subagent            → GLM primary, cascade xuống D (chạy nhiều song song)
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING: kiến trúc, milestone design — frontier only ───────────────────
  # Gemini 3.1 Pro: breadth + benchmark #1, cost-effective frontier
  # Opus 4.6: depth, reasoning, human-preferred for complex decisions
  # Codex 5.3: coding-specialist fallback
  # Sonnet 4.6: mid-tier frontier fallback
  # GPT-5.2: thêm option trước khi hết frontier
  # Gemini 3 Flash: last resort frontier (rẻ nhất, vẫn mạnh)
  planning:
    model: google-gemini-cli/gemini-3.1-pro
    fallbacks:
      - anthropic/claude-opus-4-6
      - openai-codex/gpt-5.3-codex
      - anthropic/claude-sonnet-4-6
      - openai-codex/gpt-5.2
      - google-gemini-cli/gemini-3-flash

  # ── RESEARCH: phân tích, nghiên cứu — frontier only ─────────────────────────
  # Gemini 3.1 Pro: 1M ctx production-ready, tốt nhất cho large-context research
  # Opus 4.6: depth reasoning khi cần phân tích sâu
  # Sonnet 4.6: agentic research workhorse
  # GPT-5.2: thêm option
  # Gemini 3 Flash: fast fallback, multimodal (xử lý được image/audio/video)
  research:
    model: google-gemini-cli/gemini-3.1-pro
    fallbacks:
      - anthropic/claude-opus-4-6
      - anthropic/claude-sonnet-4-6
      - openai-codex/gpt-5.2
      - google-gemini-cli/gemini-3-flash

  # ── EXECUTION (standard): code khá→khó — GLM primary, frontier fallback ─────
  # GLM-5 Turbo: mạnh+nhanh nhất GLM, tối ưu cho agentic coding
  # GLM-5: open-source SOTA, rẻ hơn Turbo
  # Sonnet 4.6: frontier fallback khi GLM fail/queue, agentic #1
  # Gemini 3.1 Pro: frontier fallback breadth
  # GLM-4.7: last GLM fallback, reasoning tốt, 202K ctx
  execution:
    model: z-coding-plan/glm-5-turbo
    fallbacks:
      - z-coding-plan/glm-5
      - anthropic/claude-sonnet-4-6
      - google-gemini-cli/gemini-3.1-pro
      - z-coding-plan/glm-4.7

  # ── EXECUTION (simple): task đơn giản — GLM only, cascade D ─────────────────
  # GLM-4.7: reasoning + 202K ctx, đủ mạnh cho task thường
  # GLM-4.7-FlashX: nhanh hơn, concurrency 3
  # GLM-4.6: concurrency 3, stable
  # GLM-4.7-Flash: rẻ nhất ($0.06), dùng khi queue hết
  # GLM-4.5: concurrency 10, dùng khi cần nhiều task song song
  # Haiku 4.5: frontier fallback cuối nếu tất cả GLM fail
  execution_simple:
    model: z-coding-plan/glm-4.7
    fallbacks:
      - z-coding-plan/glm-4.7-flashx
      - z-coding-plan/glm-4.6
      - z-coding-plan/glm-4.7-flash
      - z-coding-plan/glm-4.5
      - anthropic/claude-haiku-4-5

  # ── COMPLETION: wrap-up, summary, validate — frontier-led ────────────────────
  # Sonnet 4.6: GDPval-AA #1 cho expert task, tốt nhất cho summary quality
  # GLM-5 Turbo: fallback rẻ khi Sonnet queue/fail
  # GLM-5: tiếp theo
  # Gemini 3 Flash: nhanh, đủ cho completion
  completion:
    model: anthropic/claude-sonnet-4-6
    fallbacks:
      - z-coding-plan/glm-5-turbo
      - z-coding-plan/glm-5
      - google-gemini-cli/gemini-3-flash

  # ── SUBAGENT: scout, researcher, worker — GLM primary, cascade full ──────────
  # GLM-5 Turbo: mạnh + nhanh, primary cho mọi subagent task
  # GLM-5: fallback A-tier GLM
  # GLM-4.7: B-tier, reasoning + large ctx
  # GLM-4.7-FlashX: C-tier, nhanh concurrency 3
  # GLM-4.7-Flash: D-tier $0.06, rẻ nhất khi queue nhiều
  # GLM-4.5: D-tier concurrency 10, nhiều subagent cùng lúc
  # Haiku 4.5: frontier emergency fallback
  subagent:
    model: z-coding-plan/glm-5-turbo
    fallbacks:
      - z-coding-plan/glm-5
      - z-coding-plan/glm-4.7
      - z-coding-plan/glm-4.7-flashx
      - z-coding-plan/glm-4.7-flash
      - z-coding-plan/glm-4.5
      - anthropic/claude-haiku-4-5
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

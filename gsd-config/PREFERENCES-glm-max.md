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
  # PLAN: glm-max — 100% ZAI/GLM, không cần login OAuth nào
  # ──────────────────────────────────────────────────────────────────────────────
  # AUTH REQUIRED:
  #   8sync gsd key zai <key>  → tất cả roles (z.ai API key duy nhất)
  #
  # ZAI MODEL CONCURRENCY (quan trọng cho auto-mode parallel tasks):
  #   glm-5.1        c?  — S+ tier exec/plan, 77.8% SWE-bench
  #   glm-5-turbo    c1  — ⚠ bottle-neck nếu nhiều subagent song song ($1.2/$4/M)
  #   glm-5          c2  — A tier fallback ($0.72/$2.3/M)
  #   glm-4.7        c2  — B tier reasoning, 202K ctx ($0.39/$1.75/M)
  #   glm-4.7-flashx c3  — fast flash variant
  #   glm-4.6        c3  — 200K ctx ($0.39/$1.74/M)
  #   glm-4.5        c20 — ✅ best cho subagent workers ($0.60/$2.20/M)
  #   glm-4.5-air    c5  — lighter air variant
  #   glm-4.7-flash  c1  — cheapest $0.06/$0.40 nhưng c1 bottle-neck
  #   glm-4.5-flash  c2  — free tier
  #   glm-4-plus     c20 — legacy nhưng stable, high concurrency
  #   glm-4.6v       c10 — vision+video+PDF, 128K, native tool call ($0.30/$0.90/M)
  #   glm-4.5v       c10 — vision+video, 66K ($0.60/$1.80/M)
  #
  # STRATEGY:
  #   planning/research  → glm-5.1 (depth), fallback glm-5-turbo/glm-5
  #   execution          → glm-5.1 primary, cascade xuống theo c-limit
  #   execution_simple   → glm-4.5 (c20, nhiều parallel) → glm-4.5-air

  # -- VALIDATION (reviewer) -----------------------------------------------
  validation:
    model: zai/glm-5.1
    fallbacks:
      - claude-code/claude-sonnet-4-6
  #   completion         → glm-5.1 → glm-5-turbo
  #   subagent           → glm-4.5 (c20) primary worker, glm-5.1 planning, full cascade
  #
  # USE WHEN:
  #   - Chỉ có ZAI key, không có OAuth login nào
  #   - Muốn 100% deterministic từ một provider duy nhất
  #   - Budget control: biết chính xác chi phí vì chỉ một provider
  # ══════════════════════════════════════════════════════════════════════════════

  # ── PLANNING ────────────────────────────────────────────────────────────────
  planning:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - zai/glm-4.7

  # ── RESEARCH ────────────────────────────────────────────────────────────────
  research:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - zai/glm-4.7

  # ── EXECUTION (standard) ────────────────────────────────────────────────────
  execution:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - zai/glm-4.7
      - zai/glm-4.5

  # ── EXECUTION (simple) — dùng c20 models để không bottle-neck ───────────────
  execution_simple:
    model: zai/glm-4.5
    fallbacks:
      - zai/glm-4.5-air
      - zai/glm-4.7
      - zai/glm-4.6
      - zai/glm-4.7-flashx


  # ── COMPLETION ──────────────────────────────────────────────────────────────
  completion:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - zai/glm-4.5

  # ── SUBAGENT — glm-4.5 (c20) cho parallel workers, glm-5.1 cho complex ──────
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
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.

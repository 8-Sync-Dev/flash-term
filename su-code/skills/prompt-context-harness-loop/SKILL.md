---
name: prompt-context-harness-loop
description: >
  Framework for designing and reviewing an AI-agent system as four NESTED layers —
  Prompt ⊂ Context ⊂ Harness ⊂ Loop. Core thesis: the LLM is only the BRAIN; the
  harness + loop + context is the BODY, and strength comes from the environment, not
  a bigger model — so invest in the outer layers to get best performance at low cost
  on heavy tasks. Use when designing/reviewing an agent, an autonomous loop, tool
  wiring, context/compaction strategy, or when deciding WHERE to invest (prompt vs
  context vs harness vs loop). Triggers: "harness", "loop engineering", "context
  engineering", "agent architecture", "why is the agent weak", "make the agent
  stronger without a bigger model". Ref: Daily Dose of DS —
  https://blog.dailydoseofds.com/p/prompt-context-harness-and-loop-engineering
license: MIT
---

# Prompt · Context · Harness · Loop Engineering

**Thesis (owner):** *"Best performance, low cost, but does heavy tasks — build the harness. The loop/harness is the body; the LLM is only the brain that controls, and it learns from the environment."* A stronger agent is usually a stronger **body**, not a bigger brain. Spend effort on the outer three layers before reaching for a larger model.

## The four nested layers

```
┌─ LOOP ── autonomy over many turns: plan → act → observe → verify → repeat ─┐
│  ┌─ HARNESS ── the software body: tools, state, error recovery, sandbox ─┐  │
│  │  ┌─ CONTEXT ── everything the model SEES this turn: retrieval, memory ┐ │  │
│  │  │  ┌─ PROMPT ── one model call: role, instructions, examples, format┐│ │  │
│  │  │  └────────────────────────────────────────────────────────────────┘│ │  │
│  │  └──────────────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Each layer wraps and expands the one inside it. A weakness at an outer layer cannot be fixed by tuning an inner one (a perfect prompt can't rescue a loop with no verification).

| Layer | What it governs | Lever when the agent is weak |
|---|---|---|
| **Prompt** | A single model call — roles, instructions, few-shot, output schema | Ambiguous/verbose instructions, no output contract |
| **Context** | What the model sees this turn — retrieval, memory, history, tool defs | Missing info, blown window, buried "main path" |
| **Harness** | The body — tools, state tracking, error recovery, sandbox, permissions | Missing tools, no recovery, unsafe exec, no observability |
| **Loop** | Multi-turn autonomy — plan/act/observe/**verify**, stopping conditions | No self-verify, no done-contract, doom-loops |

## ZUS mapping (cite when reviewing)

- **Prompt** → `backend/core/engine/agent.go` `codingKernel` (system prompt, VN-first) + graded thinking preamble (`resolve.go parseModelAlias` → `ThinkingLevel`; `factory.thinkingConfig`).
- **Context** → `backend/core/engine/summarize.go` (TextRank extractive) + `compactHistory` (MessageModifier, runs before EVERY ChatModel call) + `zus-agent::compact_history` (keep system[0] + recent suffix, trim orphan Tool results) + observation-masking principle (KNOWLEDGE#102). Auto-scale budget = f(real `context_window`) — **NOT** `context_window=1M` in DB.
- **Harness** → tool registry + consent/allowlist (`zusAllowlist.ts`) + keypool 401/429 rotation + provider fallback (`resolve.go routeFallback`) + native in-process tools (`zus-agent` `ToolExecutor`). AST/code senses: `refs/backend-encore-8sync/judge` (tree-sitter multi-lang → canonical hash + complexity), plus codegraph / codebase-memory-mcp / headroom.
- **Loop** → eino ReAct + `MaxStep` + autonomy ladder (ask → edits → autopilot). **Gap (ARCH-plch-2026):** agent-shipped work isn't self-verified (autoTest is a flag, not a gate) and there's no done-contract — the loop's weakest link.

## Rule — effective ~1M context on a ≤250k window (Context layer)

The model window is ≤250k tokens, but the effective working context reaches **~1M** by **fast compaction**, so the agent never loses the **main path**:

1. **Pin** system prompt + tool defs byte-stable (contract + KV-cache anchor; dynamic data goes in the last user message, no timestamps in system).
2. **Observation-masking first** — stale tool output → a stub with a re-fetch handle (cheaper than LLM-summarize, keeps failure signals).
3. **Verbatim tail** — keep the last N turns exact.
4. **Digest the middle** — LSA / TextRank extractive summary of the dropped span (pure-Go `summarize.go`; `summaryReserve = min(budget/3, 1500)`), not a naive drop-marker.

"~1M" is a **UI label** (`.zus-agent-ctx` badge); the DB keeps the real window so the compaction math stays correct (ADR-0005 §4).

## Rule — the body is Rust (Harness/Loop layer)

Prefer **Rust** for the harness/loop (fast, predictable, in-process tools = no WS hop) and **bind C/C++/Zig** for low-level tools when needed — the LLM only controls; speed and safety come from the body. See `crates/zus-agent` (native ReAct foundation, `Completer`/`ToolExecutor` traits).

## How to apply (design / review checklist)

1. Name the layer the problem lives in — don't fix a loop bug with prompt tweaks.
2. Prompt: is there an output contract? Are instructions minimal?
3. Context: is the main path guaranteed present after compaction? Is retrieval wired?
4. Harness: do the needed tools exist? Error recovery? Safe exec? Observability (each tool call shows a brief, expandable to detail)?
5. Loop: does it self-verify before advancing? Is there a done-contract and a stop condition?
6. Invest outward-in: cheapest durable wins are usually Context + Harness, not a bigger model.

## Loop-shape catalog (Loop layer — chọn hình dạng loop)

`references/loop-patterns-20.md` — distilled "20 AI Loop Design Patterns" (@sairahul1, owner gửi 2026-07-07)
+ đối chiếu với doctrine 4 tầng này + bảng trạng thái ZUS ✅/🟡/⬜ từng pattern. Dùng khi thiết kế/review
một loop cụ thể: doctrine này định vị TẦNG, catalog đó chọn HÌNH DẠNG loop trong tầng.

Ref: <https://blog.dailydoseofds.com/p/prompt-context-harness-and-loop-engineering>

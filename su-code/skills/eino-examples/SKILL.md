---
name: eino-examples
description: >-
  Use when enhancing or debugging the AcoLeads agent runtime (backend/core/engine) and
  you need a REAL, compilable Eino reference — agent loop (ReAct), tool-calling, agent
  transfer/handoff, multi-turn info-gathering (follow-up), session/memory, RAG,
  streaming SSE, multi-agent/supervisor, human-in-the-loop. Pairs with `lib-docs-fetch`
  + `ref/eino-docs/`: docs explain the API, this skill points at WORKING code in the
  vendored `ref/eino-examples/` submodule (cloudwego/eino-examples). Consult BEFORE
  inventing an Eino ADK/compose pattern from memory.
---

# eino-examples — vendored CloudWeGo reference for agent work

> Adapted từ `ref/agentic-cloudgo-v1/agents/skills/eino-examples` @ `8808d467`.

Real, compilable Eino code lives in the submodule **`ref/eino-examples/`**
(upstream cloudwego/eino-examples). Index: **`ref/eino-docs/2026-06-17-eino-examples-index.md`**
— open it FIRST, then read the exact example dir.

```bash
git submodule update --init ref/eino-examples          # fresh clone
git submodule update --remote --merge ref/eino-examples # pull newer patterns (commit the bump)
```

## Topic → path map

| Engine concern | Eino example (`ref/eino-examples/…`) |
|---|---|
| Agent loop / tool-calling (core runtime) | `flow/agent/react/` (+ `react/tools`, `react/memory_example`) |
| Unknown tool / no-info → graceful path | `flow/agent/react/unknown_tool_handler_example/` |
| Handoff / transfer to a specialist | `adk/intro/transfer/` (+ `…/subagents`) |
| Multi-turn info gathering without nagging | `adk/human-in-the-loop/4_follow-up/` |
| Approval / review before a sensitive write | `adk/human-in-the-loop/1_approval`, `2_review-and-edit` |
| Session / cross-turn state | `adk/intro/session/` |
| Conversation summary (returning customer) | `adk/intro/agent_with_summarization/` |
| Streaming SSE | `adk/intro/http-sse-service/` |
| RAG retriever wiring | `quickstart/chatwitheino/rag/`, `quickstart/eino_assistant/` |
| Tool authoring | `components/tool/`, `flow/agent/react/tools` |
| Supervisor / multi-agent routing | `adk/multiagent/`, `flow/agent/multiagent/{host,plan_execute}` |
| Custom agent contract | `adk/intro/custom/` |

## Grounding rule

1. "How should the Eino agent do X" → open the index, find the row, **read that example's `.go`**.
2. Cite the example path:line in reasoning (same as codegraph/ref citations).
3. Examples track upstream `main`; `backend/core` pins its own eino version — verify API shape
   via `cd backend/core && go doc github.com/cloudwego/eino/<pkg>.<Symbol>` before adopting.
4. NEVER copy an example wholesale — extract the PATTERN (loop shape, transfer wiring,
   follow-up gating) and apply it to the existing structure (data → prompt → Eino primitive).

## Boundaries
- Reference only — **do not import** `ref/eino-examples/*` from `backend/` (separate module).
- Examples inform internal engine/agent design, never public API contracts.

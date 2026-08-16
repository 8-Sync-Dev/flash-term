---
name: eino-first
description: >
  BẮT BUỘC đọc TRƯỚC mọi việc đụng backend chat/agent của AcoLeads (backend/core/engine,
  backend/core/chat, tools, guardrails, kernel/prompt, hành vi bot). Hệ thống build 100%
  trên eino framework (CloudWeGo) — KHÔNG tự chế regex/string post-process / hardcode
  thay cho eino primitive. Skill = doctrine + bản đồ eino↔code + pattern chuẩn
  (emit_reply ToolReturnDirectly, tool-side state gate, confirm-before-action) + nguồn
  tra cứu (ref/eino-docs, ref/eino-examples). Dùng khi: "fix hành vi bot", "thêm tool",
  "đổi prompt/kernel", "guardrail", "eino", "ReAct", "build backend chat".
---

# eino-first — build hệ thống chat 100% bằng eino framework

> Adapted từ `ref/agentic-cloudgo-v1/agents/skills/eino-first` @ `8808d467`. Kiến trúc
> gốc phục vụ PHP CRM cũ — **chỉ giữ doctrine + pattern**, mọi triển khai mới theo
> layout AcoLeads (`backend/core/*`), không port shape legacy.

## ⛔ MANDATE (bất biến — trùng rule "LLM-first" trong AGENTS.md)
Backend chat (`backend/core/engine`, `backend/core/chat`, `backend/core/meta` dispatch)
chạy trên **eino core** (CloudWeGo). Mọi fix hành vi / format / luồng bot đi theo
**data → prompt → eino primitive**. TUYỆT ĐỐI KHÔNG:
- regex/split/string post-process để sửa output của model;
- hardcode business value trong Go (model/provider/key = DB rows seed trong
  `backend/core/agent/migrations/`; prompt/kernel cũng thuộc data);
- đoán API eino — tra `ref/eino-docs` + `ref/eino-examples` TRƯỚC (skill `lib-docs-fetch`);
  verify shape: `cd backend/core && go doc github.com/cloudwego/eino/<pkg>.<Symbol>`.
Guardrail deterministic CHỈ numeric/state (đếm/cờ), KHÔNG sanitize prose.

## eino ↔ AcoLeads (bản đồ)
| eino primitive | AcoLeads | vai trò |
|---|---|---|
| `flow/agent/react` `react.NewAgent` | `backend/core/engine` (pipeline) | vòng ReAct 1 model ⇄ tools (`agent.Generate`) |
| `react.AgentConfig.ToolReturnDirectly` | engine pipeline | tool kết thúc lượt + trả thẳng output (pattern `emit_reply`) |
| `components/tool` + `tool/utils.InferTool` | engine tools | mỗi tool = `InvokableTool`, args = JSON-schema từ struct tag |
| `compose.ToolsNodeConfig` | engine pipeline | bộ tool theo allowlist |
| `components/model` + `eino-ext/.../{openai,gemini}` | engine model factory | ChatModel theo `llm_providers/llm_models` (DB) |
| `schema` Message/ToolInfo | engine | SystemMessage(kernel+state+context) + history |
| per-turn Memory (session JSONB) | `backend/core/chat` | checkpoint tự quản (eino interrupt/checkpoint CHƯA wire) |

## Pattern chuẩn (tham khảo go-kit làm MẪU, triển khai mới cho AcoLeads)
1. **Reply bubbles = synthetic tool `emit_reply`** (ToolReturnDirectly): LLM phát `bubbles[]`,
   engine render verbatim. KHÔNG regex split. Mẫu: `ref/agentic-cloudgo-v1/be/engine/tools/emit_reply.go`.
2. **An toàn deterministic = tool-side state gate** (numeric/state, surfaced qua ReAct loop):
   tool trả `Reason:"NEED_X"` + Message hướng dẫn → model đọc kết quả tool → hành động đúng
   lượt sau. Họ pattern (mẫu `ref/agentic-cloudgo-v1/be/engine/tools/crm_tools.go`):
   `MISSING_CONTACT` · idempotency signature + window (không tạo trùng) · `ClaimOnce`
   (tối đa 1 create/lượt) · **confirm-before-create** (`NEED_CONFIRM` echo lại thông tin,
   lượt sau khách xác nhận mới tạo) · order gate (`NEED_CALENDAR_CHECK` — buộc tool A trước B).
3. **Steer hành vi = kernel/prompt (data) + tool description**, KHÔNG Go logic.
   Đổi = migration mới (skill `encore-migrations`).

## Khi thêm/sửa (quy tắc quyết định)
- Tool mới → `utils.InferTool[In]` + struct `jsonschema` tag; đăng ký registry + allowlist
  (migration). Terminal/reply-delivery → cân nhắc `ToolReturnDirectly`.
- Cần "xác nhận trước khi hành động" / chống trùng / chặn theo điều kiện →
  **tool-side state gate**, KHÔNG prompt-only (prompt "detect-but-not-correct").
- Multi-agent thật (supervisor / plan-execute) → đọc `ref/eino-docs` adk notes + ADR trước.
  (Đã eval 2026-06-17: `supervisor.New` = NO-GO; ưu tiên ChatModelAgent+AgentTool.)

## Verify (BẮT BUỘC — build/typecheck KHÔNG đủ)
Chat thật end-to-end (webhook/webchat → engine → reply) + trace tool_calls trong chat DB.
Bằng chứng tool-fired / no-dup = trace + DB rows, KHÔNG dựa reply text/screenshot.
`encore test ./...` trong `backend/core` cho contract tests.

## Nguồn (lib-docs-fetch)
`ref/eino-docs/`: `eino-llms.txt` + `2026-06-17-eino-examples-index.md`.
`ref/eino-examples/` (runnable, xem skill `eino-examples`).
Ưu tiên: module-cache `go doc` > repo tag đã pin > cloudwego.io > pkg.go.dev. Blog = direction only.

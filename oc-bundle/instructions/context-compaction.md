# Context Compaction & Token Management

Hướng dẫn đã được xác minh từ source code thực của OpenCode (`sst/opencode`).

---

## 1. Cấu hình `compaction` trong `opencode.json` (VERIFIED từ source)

Các field sau đã được xác nhận tồn tại trong `compaction.ts`:

```json
{
  "compaction": {
    "auto": true,
    "reserved": 20000
  }
}
```

- **`auto`**: `true` = bật auto-compact khi gần đầy context. Set `false` hoặc env `OPENCODE_DISABLE_AUTOCOMPACT=1` để tắt.
- **`reserved`**: Số token "buffer" giữ lại cho response. Default = `min(COMPACTION_BUFFER, maxOutputTokens(model))`. Tăng lên 20000 giúp compact **sớm hơn và thông minh hơn** (trigger trước khi quá gần giới hạn).

**Env vars bổ sung (verified từ `config.ts`):**
- `OPENCODE_DISABLE_AUTOCOMPACT=1` — tắt hoàn toàn auto-compact
- `OPENCODE_DISABLE_PRUNE=1` — tắt pruning tool outputs cũ

---

## 2. Cơ chế Pruning (tự động, không cần config)

OpenCode **tự động prune** tool call outputs cũ trước khi compact toàn bộ. Constants từ source:

```
PRUNE_MINIMUM   = 20,000 tokens  (ngưỡng tối thiểu để prune có ý nghĩa)
PRUNE_PROTECT   = 40,000 tokens  (bảo vệ 40k token cuối cùng)
PRUNE_PROTECTED_TOOLS = ["skill"] (không bao giờ prune skill outputs)
```

Pruning giữ lại tool call structure, chỉ xóa output text lớn → nhẹ hơn compact toàn bộ.

---

## 3. Plugin `smart-compact.mjs` — Hook thực sự (VERIFIED)

OpenCode cung cấp hook **`experimental.session.compacting`** (verified từ `packages/plugin/src/index.ts`):

```typescript
"experimental.session.compacting"?: (
  input: { sessionID: string },
  output: { context: string[]; prompt?: string },
) => Promise<void>
```

- `output.context.push(...)` → thêm context strings vào compaction prompt
- `output.prompt = "..."` → override toàn bộ compaction prompt

File `~/.config/opencode/plugins/smart-compact.mjs` đã được tạo để:
1. Inject structured preservation rules vào mọi lần compact
2. Yêu cầu format summary chuẩn (Goal → Status → Files → Next Actions)
3. Extract modified files và recent errors từ session messages

---

## 4. Plugins thực sự đang dùng

| Plugin | npm/GitHub | Tác dụng |
|--------|-----------|----------|
| `oh-my-openagent@latest` | npm: oh-my-openagent | Multi-agent orchestration |
| `opencode-supermemory@latest` | npm: opencode-supermemory v2.0.4 | Persistent memory qua mọi session |
| `@tarquinen/opencode-dcp@latest` | npm: @tarquinen/opencode-dcp | Dynamic context pruning tự động |
| `./plugins/smart-compact.mjs` | local | Compaction hook thông minh (custom) |

---

## 5. Context-Mode Plugin (Built-in tools)

OpenCode đã có sẵn **context-mode** plugin với các tools:

- **`execute`**: Run code in sandbox, chỉ stdout vào context
- **`execute_file`**: Đọc file trong sandbox, chỉ summary vào context
- **`index`**: Index docs vào BM25 searchable database
- **`search`**: Query indexed content on-demand
- **`batch_execute`**: Multiple commands + auto-index + search
- **`fetch_and_index`**: Fetch URL → markdown → index

### Khi nào dùng Context-Mode

```
IF output > 20 dòng → dùng context-mode thay vì bash/cat
```

---

## 6. Best Practices

### DO:
- Dùng `context-mode` cho large outputs (logs, test results, diffs)
- Để `compaction.reserved: 20000` — compact sớm, context sạch hơn
- Để `compaction.auto: true` — không cần manual `/compact`
- `opencode-supermemory` tự lưu memory quan trọng qua mọi session

### DON'T:
- ~~`opencode-morph-plugin`~~ — **KHÔNG TỒN TẠI** (fabricated)
- ~~`AmbianceMCP`~~ — **KHÔNG TỒN TẠI** (fabricated)
- ~~`opencode-dynamic-context-pruning`~~ — **SAI TÊN**, đúng là `@tarquinen/opencode-dcp`
- Đọc toàn bộ file dài vào context
- Giữ history cũ không cần thiết

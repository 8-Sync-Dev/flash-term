# lib-docs-fetch — Auto-fetch docs từ nguồn trust cao (Eino & deps go-kit)

> **Triggers:** "cập nhật doc eino", "eino doc", "fetch docs", API Eino/eino-ext không chắc shape, lib mới vào `be/go.mod`, build lỗi sau khi bump version lib.
>
> **MANDATE:** KHÔNG BAO GIỜ đoán API shape của Eino hay lib ngoài. Khi không chắc → fetch từ nguồn trust ≥90% bên dưới (theo thứ tự), cache snapshot, rồi mới code. Blog/medium/stackoverflow = trust thấp, chỉ tham khảo hướng, không lấy làm chuẩn API.

## 0. Version pin — đọc TRƯỚC khi fetch

Nguồn chuẩn version: `be/go.mod` (hiện tại: `eino v0.9.5`, `eino-ext/.../gemini v0.1.32`, `eino-ext/.../openai v0.1.13`). Mọi doc fetch phải khớp tag/version này — doc của main branch có thể lệch API so với version đang pin.

## 1. Nguồn trust ≥90% (thứ tự ưu tiên)

| # | Nguồn | Cách lấy | Dùng khi |
|---|---|---|---|
| 1 | **Source thật trong module cache** (trust 100%) | `librarian` subagent (oh-my-pi) — đọc thẳng source lib đã resolve theo go.mod; hoặc `go doc github.com/cloudwego/eino/<pkg>.<Symbol>` từ `be/` | Câu hỏi API chính xác (signature, behavior, edge case) — **mặc định dùng cái này** |
| 2 | **Repo chính chủ** github.com/cloudwego/eino (+ `eino-ext`, `eino-examples`) | `read` URL `https://github.com/cloudwego/eino/tree/v0.9.5` (đúng tag!), release notes `https://github.com/cloudwego/eino/releases` | Đọc README/design doc/examples, diff khi bump version |
| 3 | **Docs chính chủ CloudWeGo** | `read` `https://www.cloudwego.io/docs/eino/` (overview, core_modules, ecosystem) | Khái niệm/kiến trúc (Chain/Graph/ReAct/Callbacks/Schema) |
| 4 | **context7** (LLM-formatted dump) | `read` `https://context7.com/cloudwego/eino/llms.txt` (+ `?topic=<chủ đề>`; tương tự cho `cloudwego/eino-ext`) | Cần dump cô đọng nhiều API một lúc cho 1 chủ đề |
| 5 | **pkg.go.dev** | `read` `https://pkg.go.dev/github.com/cloudwego/eino@v0.9.5/<pkg>` | API reference versioned, godoc render sẵn |

Áp dụng y hệt cho lib khác trong go.mod (encore.dev → `https://encore.dev/docs/go`, pgvector-go, jsonschema…): luôn ưu tiên #1 source thật.

## 2. Cache snapshot — `ref/eino-docs/`

- Fetch xong, lưu phần ĐÃ DÙNG (không dump cả site) vào `ref/eino-docs/<YYYY-MM-DD>-<chủ-đề>.md`, header ghi: nguồn URL + version/tag + ngày fetch.
- Trước khi fetch mới: check cache đã có chưa (`find ref/eino-docs/`) — cache hit + version khớp go.mod = dùng luôn, khỏi fetch.
- Bump version lib trong go.mod → cache cũ coi như STALE cho symbol bị đổi: fetch release notes diff giữa 2 tag trước, chỉ refresh chủ đề bị ảnh hưởng.

## 3. Recipe nhanh

```bash
# 1. Hỏi sâu hành vi/internals (trust 100%, source-verified):
#    → spawn librarian: "Đọc github.com/cloudwego/eino v0.9.5: <câu hỏi>. Trả lời kèm path:line."

# 2. API signature nhanh (source local):
cd be && go doc github.com/cloudwego/eino/compose.NewGraph

# 3. Dump chủ đề từ context7 (read tool, KHÔNG curl):
#    read https://context7.com/cloudwego/eino/llms.txt?topic=react+agent

# 4. Diff khi bump version:
#    read https://github.com/cloudwego/eino/compare/v0.9.5...v0.9.6
```

## 4. Anti-patterns

- Code theo trí nhớ model về Eino API (API đổi nhanh giữa minor versions) → build fail/behavior lệch.
- Fetch doc main branch trong khi go.mod pin tag cũ.
- Dump cả website vào cache (chỉ lưu phần dùng, có header nguồn).
- Lấy blog bên thứ ba làm chuẩn API thay vì source/godoc.

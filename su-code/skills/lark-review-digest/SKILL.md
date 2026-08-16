---
name: lark-review-digest
description: Quét toàn bộ record + comment của các bảng team trên Lark Base (8 SYNC DEV Workspace) qua browser, lọc @mention tới mình, xuất digest Markdown để review nhanh "ai giao gì · comment nào tag mình · cần trả lời". Dùng khi founder muốn review/check comment & mention của team (DEV/MKT/EDU) mà không mở từng record. Lark CLI/OAuth Base Forbidden (tenant JP) → browser-control là đường duy nhất. Build trên lark-base-ops. Trigger: "review comment team", "mention tôi", "đọc task + comment", "digest Lark", "ai tag tôi".
---

# lark-review-digest — digest comment & @mention team (Lark Base)

Đọc **record + comment** mọi bảng team → lọc **@mention tới founder** → xuất 1 file
Markdown review gọn. Không API (tenant JP → OAuth Base Forbidden) nên đi qua
**profile browser đã login** + omp `browser` tool (giống `lark-base-ops`).

## 🚫 CHỈ ĐỌC — không sửa
Skill này KHÔNG thêm/sửa/xoá record. Chỉ mở record, đọc field + comment, đóng lại
(Escape). Golden rule org vẫn áp: KHÔNG xoá gì.

## 1. Chạy (1 cell `browser` run)
```bash
# đảm bảo profile browser mở base (nếu chưa)
bash 8syncdev-org-skills/skills/browser-profile-control/scripts/profile-browser.sh \
  open linkedin "https://djphb7zech62.jp.larksuite.com/base/N4jWbAd77aflNksHyd6jIIXUpmg"
```
Attach omp `browser` (`open`, `app.cdp_url: http://127.0.0.1:9222`) rồi:
```js
const R = require('<repo>/8syncdev-org-skills/skills/lark-review-digest/scripts/review-digest.js');
const page = await R.H.attachBase(browser, 'https://djphb7zech62.jp.larksuite.com/base/N4jWbAd77aflNksHyd6jIIXUpmg');
const results = await R.scanAll(page, R.allTables());          // all teams (DEV+MKT+EDU+OPS)
// scope hẹp:  R.allTables(['DEV'])  ·  R.allTables(['DEV','MKT'])
const md = R.toMarkdown(results, { me: 'Anh Tú' });
require('fs').writeFileSync('/tmp/lark-review.md', md);
return { tables: results.length, records: results.reduce((s,r)=>s+r.withComments.length,0) };
```
→ copy `/tmp/lark-review.md` sang `briefs/lark-review-<date>.md` để lưu.

## 2. Digest gồm
- **🔔 Tag @me** — record có comment @mention founder (`@Anh Tú|Tú|Kevin|Alex`) — ưu tiên trả lời.
- **💬 Comment khác** — mọi comment còn lại (title · bảng · người nhận · trạng thái · nội dung comment).
- **📋 Coverage** — mỗi bảng quét bao nhiêu record / bao nhiêu có comment (⚠️ = bảng lỗi, scan tay lại).

## 3. Cách hoạt động (read helpers ở `lark-base-ops/scripts/lark-helpers.js`)
- `ensureGridView` → `openRecordRow(1)` (nút **"Open"** hiện khi hover row, canvas grid) → mở panel record.
- `readRecord` — đọc `[class*=card-field-editor]` (field) + `[class*=discussion-card-reply-container]` (comment). Select-field innerText kèm cả list option → lấy **dòng đầu**.
- `navRecord('next')` — click mũi tên ▼ đầu panel (prev ▲) đi record kế; trả `false` khi không đổi = hết record → dừng.
- `scanTableComments` — walk hết record 1 bảng, giữ record **có comment**, gắn cờ `mentionsMe`.

## 4. Bẫy độ bền (validated 2026-07-23)
- **Mở record = multi-x sweep** `[490,560,599,645]` (icon "Open" ở **mép phải cột primary**, x đổi theo độ rộng cột/độ dài text) + Escape giữa mỗi lần. `openTable` **scrollIntoView + verify URL `table=` đổi** (sidebar dài render item ngoài viewport → click trượt); `scanAll` retry 1 lần, skip nếu không switch (KHÔNG scan nhầm bảng).
- **Bảng Kanban** (vd ZUS IDE có "Scrum board"): `ensureGridView` click tab Grid + Escape (đóng view-menu nếu Grid đã active) trước khi walk.
- **Bảng rỗng / mis-click**: một click có thể **tạo draft record**. Chặn 2 lớp: (a) `openRecordRow` undo draft qua **edit-count delta** (Ctrl+Z, chỉ đụng draft mình vừa tạo); (b) `scanTableComments` mở record 1, nếu **title rỗng + no comment** = draft → close + Ctrl+Z + báo empty. ⚠ KHÔNG hardcode click nút "+" inline.
- ⚠️ **LIMITATION (validated 2026-07-23):** opener toạ-độ chỉ chắc trên **Grid KHÔNG group + schema task chuẩn (bảng DEV clone từ DEV_01)**. Thất bại trên: **grouped view** (vd `MKT_01` group Năm→Tháng→Tuần, 27 record → toạ độ row lệch) và **schema cột primary khác** (vd `OPS_01`). Với các bảng đó: **bỏ group + về Grid phẳng** trước, hoặc mở record thủ công. Mọi @mention hiện tại của org đều ở DEV (Hưng→Anh Tú) nên digest DEV = đủ; MKT/EDU/OPS là scaffolding chưa dùng comment.
- **Comment nhiều dòng** gộp bằng ` — `; nhiều comment/record tách bằng bullet riêng.
- Chỉ đọc **comment hiển thị trong panel record**; reply lồng sâu vẫn nằm trong `discussion-card-reply-container` nên vẫn bắt.

## 5. Mention regex
Mặc định `/@\s*(Anh\s*Tú|Tú|Kevin|Alex)/i`. Người khác → truyền `scanTableComments(page,{mentionRe:/@.../})` hoặc sửa `toMarkdown({me})`.

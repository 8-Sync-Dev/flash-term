---
name: lark-base-ops
description: Điều khiển Lark Base (Bitable) qua browser — mở base, liệt kê/mở bảng, THÊM/UPDATE record qua form panel (text/date/select/link/member/checkbox), sửa cell. Dùng khi cần đọc/điền/cập nhật Lark Base của 8 Sync Dev (lịch nội dung, CRM, nhân sự, giáo dục…). Lark CLI KHÔNG dùng được (tài khoản ở tenant JP khác → Forbidden) nên browser-control là đường duy nhất. Build trên browser-profile-control. Trigger: "điền Lark", "thêm record Lark", "cập nhật base", "mở Lark base".
---

# lark-base-ops — thao tác Lark Base qua browser

Lark CLI không xài được (tenant JP khác → OAuth Forbidden). Mọi thao tác Base đi qua
**profile browser đã login** (skill `browser-profile-control`) + omp `browser` tool trên CDP.

## 🚫 LUẬT BẤT BIẾN (org)
**KHÔNG xoá** base / bảng / record / field khi chưa được cho phép. Chỉ **THÊM** hoặc **UPDATE**.
Helper này cố ý không có hàm delete.

## ⛔ CONTRACT GIAO TASK (bất biến — chống "giao thiếu")
Record gán người PHẢI đủ **3**: `Brief nội dung` (làm gì/góc/cho ai) + `Nội dung/Bài làm` (detail: dàn ý/lời thoại/bước — KHÔNG chung chung kiểu "chọn 1 bài") + **link CỤ THỂ** ở `Link nguồn` (`coding.8syncdev.com/problem/<slug>` hoặc `news.8syncdev.com/articles/<slug>`, **KHÔNG homepage**). Thiếu 1 → `Trạng thái=Backlog`, KHÔNG gán `Người phụ trách`. Lấy slug: API `coding…/api/exercises` · news `/rankings`. Canonical: `briefs/mkt-content-ops-plan §6.0`.

## 1. Mở base (login sẵn)
```bash
bash 8syncdev-org-skills/skills/browser-profile-control/scripts/profile-browser.sh open linkedin "<BASE_URL>"
```
Rồi attach omp `browser` (action `open`, `app.cdp_url: http://127.0.0.1:9222`).

**Bẫy URL:** base ID **phân biệt hoa/thường** — `…afIN…` (I hoa) ≠ `…aflN…` (l thường). Sai 1 ký tự → 404.
Base "8 SYNC DEV Workspace" đúng: `https://djphb7zech62.jp.larksuite.com/base/N4jWbAd77aflNksHyd6jIIXUpmg`.
Nếu 404 → helper `attachBase` tự recover: về `/drive/home/` → Recent → double-click theo tên.

## 2. Helper (scripts/lark-helpers.js)
Chạy trong `browser` tool `run` (Node, có `browser`/`page`/`tab`):
```js
const H = require('<repo>/8syncdev-org-skills/skills/lark-base-ops/scripts/lark-helpers.js');
const page = await H.attachBase(browser, '<BASE_URL>');   // recover 404 qua Recent
await H.listTables(page);                                  // tên các bảng
await H.openTable(page, 'MKT_01 Lịch nội dung');
await H.openAddForm(page, { addMore: true });              // tick "Add more records after submission"
const rep = await H.addRecord(page, {
  text:   { Content: 'Tiêu đề', 'Brief nội dung': 'Làm gì · góc/định dạng · cho ai · CTA', 'Nội dung/Bài làm': 'Dàn ý/lời thoại/bước làm cụ thể', 'Link nguồn': 'https://coding.8syncdev.com/problem/<slug>' },  // Link nguồn = bài CỤ THỂ, KHÔNG homepage
  date:   { Deadline: '20/07/2026' },        // định dạng DD/MM/YYYY
  select: { 'Loại content': 'Bài học', 'Trạng thái': 'Chưa làm' },  // tự tạo option nếu chưa có
  link:   { 'Kênh đăng': 'TikTok' },         // LINK record → bảng DIM_Kênh (record phải tồn tại)
  member: { 'Người phụ trách': ['Hoàng Quyên'] },
});
// rep = { ok:[...], fail:[...] } — soi fail để retry field lỗi
```
`openAddForm` một lần (tick addMore) → gọi `addRecord` nhiều lần, form ở lại trống sau mỗi Submit.

## 3. Loại field (Lark Base) & cách điền
| Loại | Placeholder/biểu hiện | Helper |
|---|---|---|
| Text | "Type here" (INPUT) | `fillText` |
| Date | "DD/MM/YYYY" | `fillDate` (gõ + Enter + Esc) |
| Single/Multi-select | "Select or add an option" | `fillSelect` (gõ lọc → click option; tự tạo nếu chưa có) |
| **Link** (quan hệ) | "Please select a record" | `fillLink` (mở dialog → search → click record; **record đích phải có sẵn**) |
| Member | "Search for members" | `fillMember` |
| Checkbox | ô tick (vd `Duyệt`) | `setCheckbox` |
| Formula | "Autofill after submit" | tự tính, KHÔNG điền |

## 4. Bản đồ field sống — `MKT_01 Lịch nội dung` (cập nhật 2026-07-21)
`Content`(text tiêu đề) · `Brief nội dung`(text: làm gì/góc/cho ai) · `Nội dung/Bài làm`(text: dàn ý/lời thoại/bước) · `Người phụ trách`(member) · `Video/Ảnh`(attach) ·
`Link nguồn`(URL — bài GỐC cụ thể `/problem/<slug>` hoặc `/articles/<slug>`, **KHÔNG homepage**) · `Link FB`·`Link TikTok`·`Link Threads`·`Link YouTube`(URL — permalink đã đăng) · `Nền tảng`(multi-select FB·TikTok·Threads·YouTube) ·
`Deadline`(date) · `Trạng thái`(select Backlog·Chưa làm·Đang làm·Done) · `Loại content`(select Share·Bài học·Product) ·
`Kênh đăng`(link→DIM_Kênh) · `Chiến dịch`(link→DIM_Chiến dịch) · `Từ khóa SEO`(link→MKT_07) · `Persona mục tiêu`(link→DIM_Persona) · `Cấp`(select Epic·Task·Subtask) · `Task cha`(link self) · `Duyệt`(checkbox) · `Năm`/`Tuần`/`Tháng`/`Còn lại`(formula, KHÔNG điền).
**`GV_Task giáo viên cần làm`:** `Việc cần làm`(text) · `Loại việc`(select Quay video·Soạn giáo án·Viết bài) · `Link bài coding`(URL `/problem/<slug>`) · `Lời thoại / Ghi chú`(text) · `Người phụ trách`(member) · `Deadline`(date) · `Trạng thái`(select) · **[quy trình nộp/duyệt — 2026-07-22]** `Link nộp GV`(text) · `Trạng thái duyệt`(select 6 bước: GV nộp→Sale/MKT check→Sửa→Recheck→Up YT riêng tư→Done) · `Link duyệt (riêng tư)`(text: YT private đã duyệt). **`MKT_08 Lead/CRM`:** `Người chăm sóc`(member, default=Hoàng Quyên).
**`DEV_01 Task`** (trong folder **TEAM DEV**, tạo 2026-07-22): `Task`(text tiêu đề) · `Người nhận`(Person) · `Brief`(text) · `Nội dung / Chi tiết`(text) · `Acceptance`(text) · `Deadline`(date) · `Link cụ thể`(text — Lark KHÔNG có field type 'URL', dùng Text) · `Ưu tiên`(select Gấp·Thường·Thấp) · `Trạng thái`(select To-do·Đang làm·Xong) · `Team`(select Dev·MKT·GV — role dropdown phân team).
View: `Task tổng`, `Task cá nhân`. Group `Năm→Tháng→Tuần` (đã Save cho team).

## 5. Lưu ý độ bền
- Canvas Lark động — sau mỗi thao tác chờ (helper đã `sleep`). Selector đổi theo phiên bản → nếu `fail`, screenshot + chỉnh selector trong helper.
- Điền **link/member** cần record/người có sẵn ở bảng/tenant. Thiếu → điền text field mô tả thay, ghi lại để bổ sung.
- Luôn để thông tin cốt lõi (kênh, giờ, CTA) trong `Nội dung` (text) để không mất khi link/select lỗi.
- Verify sau khi điền: đếm record tăng đúng + spot-check 1–2 record.

## 6. Tạo cấu trúc (table/field/folder) qua browser — validated 2026-07-22
**Bẫy #1:** flyout con (type-list, submenu) ĐÓNG giữa các `run` cell (attach+bringToFront dismiss) → mỗi thao tác mở-flyout PHẢI atomic trong **1 cell**. Popover `New field` thì SỐNG giữa cell; chỉ flyout con đóng. Luôn re-query toạ độ (popover reposition), đừng hard-code.
- **Tạo table:** click `+ New` (sidebar, class `bitable-sidebar-add-new-block-button`) → menu → `Table` → grid mới + ô rename focus → Ctrl+A + type tên + Enter.
- **Thêm field:** toolbar `Customize Field` → nút `New field` (class `bitable-field-panel-add-field`) → click input `placeholder="Enter a field title"` + type tên → (đổi type) click type-row (class `b-field-type`, bỏ 'Explore Field Shortcuts') → click `.field-option-list__item` khớp text CHÍNH XÁC. Text = type mặc định (bỏ qua đổi type). Map: **Person**=member, **Single Option**=dropdown, **Date**; **KHÔNG có 'URL'** → link để Text. → `Confirm`.
- **Option (Single Option):** sau chọn type → `Add Option` (mỗi lần 1) → Ctrl+A + type tên → lặp → `Confirm`.
- **Rename primary field:** panel → hover row → `...` (phải row) → `Edit` → sửa title → `Confirm`.
- **Folder (nhóm team sidebar):** `+ New` → `Folder` → rename. Move table: right-click table sidebar → `Move To` → click tên folder. ⚠ Folder = tổ chức TRỰC QUAN, KHÔNG cô lập quyền; cô lập cứng ("team khác không thấy") cần **Advanced Permissions** (tính năng riêng — ĐÃ bật; xem §7).
- **Bug search type-flyout:** ô Search GIỮ text giữa lần gõ (→ 'PersonPerson' lọc rỗng). An toàn: click thẳng `.field-option-list__item` theo text (flyout mở mới = search rỗng = list đầy đủ), KHÔNG dùng search.
```
```

## 7. Phân quyền theo team — Advanced Permissions (2026-07-22)
Base ĐÃ bật **Advanced Permissions** + **"Only Custom Roles Can Access"**; custom roles: **Chung/Marketing/Teacher/FE Team**. Owner/Administrator = Anh Tú + Quốc Hưng (full, KHÔNG đổi). **Ma trận role×bảng đầy đủ** ở `org-core/operations.md §7`.
- **Nguyên tắc:** mỗi role `Can edit` bảng team mình · `View only` `DIM_*` · `Can edit` `OPS_01 Yêu cầu chéo` · còn lại `No access`. Bảng mới mặc định `No access` → chỉ set ngoại lệ. Scale = thêm 1 role.
- **Mở modal role:** Share (top-right) → **"Permission settings"** = dialog sharing CHUNG (External sharing / Who can view·copy·comment), **KHÔNG** phải modal role. Modal role-based table access (toggle + danh sách role + radio `No access/View only/Can edit` per bảng) vào qua entry riêng (base **···** More). ⚠ **[failure 2026-07-22]** automation chưa tìm được selector ổn định cho modal role → set tay / probe thêm.
- ⚠ Base LIVE: đổi quyền có rủi ro khoá người → **founder xác nhận**; agent KHÔNG tự đổi Owner/Administrator/gán người. **GRANT-only** (tăng quyền role đang `No access`) an toàn hơn REVOKE.

## 8. Rename/Clone table + View (validated 2026-07-22)
- **Rename table:** hover table ở sidebar → nút **⋮ (More)** → **Rename Table** → Ctrl+A + tên + Enter. (Right-click contextmenu KHÔNG ổn định — menu item ở rect `0,0` không click được; dùng ⋮.)
- **Clone schema (bảng rỗng cùng field):** ⋮ → **Duplicate Table** → dialog: đặt tên + chọn **"Configurations only"** (KHÔNG "Configurations and records") → Duplicate → bảng mới rỗng full-field. Dùng tạo bảng per-project nhanh (khỏi dựng lại 15 field).
- **Nhiều view + grouping (RELIABLE):** `+` cạnh tab view → **Kanban View** → mặc định group field đầu; đổi qua control **"Group by <field>"** (top) → chọn field (`Trạng thái`=Scrum board · `Cấp`=task/subtask · `Người nhận`=cá nhân) → **Save**. Filter `Loại=Bug` = bug board.
- ⚠ **[failure] `Group By` trên Grid view = fragile** qua automation (chọn field xong panel reset "Choose field", group KHÔNG áp — thử ~10 lần) → dùng **Kanban View** để có grouping.
- **Viewport:** thật `innerWidth≈1595` (screenshot downscale ~1.25×) → click theo `getBoundingClientRect` (DOM), KHÔNG theo pixel ảnh; element x>1595 = ngoài viewport, click không tới.

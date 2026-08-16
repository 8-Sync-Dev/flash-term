---
name: performance-report
description: Báo cáo hiệu quả content 8 Sync Dev từ dữ liệu THẬT — đọc sổ bài đã đăng data/social-ledger.ndjson (platform/account/kind/permalink/verified/posted_at) qua post-ledger.js, cộng số liệu kênh soi live, rồi ra bảng "đăng gì · ở đâu · đã kiểm chứng chưa · cái gì chạy" kèm danh sách bài cần đi xác minh lại và bài vi phạm doctrine. Dùng khi user hỏi "tuần rồi đăng được bao nhiêu bài", "bài nào chạy", "báo cáo MKT", "đã đăng những gì", "có bài nào chưa verify không", "review hiệu quả content".
---

# performance-report — báo cáo hiệu quả từ sổ bài, không từ trí nhớ

Quy tắc số một: **cái gì không có trong sổ hoặc không verify được thì báo là "chưa biết"**, không suy đoán.
Org chưa bật Vercel Web Analytics (`org-core/products.md §KPI`) ⇒ **không có số traffic**. Đừng bịa ra.

## 0. Nguồn dữ liệu

| Nguồn | Là gì | Ghi chú |
|---|---|---|
| `data/social-ledger.ndjson` | **Nguồn sự thật**, append-only, được commit | 1 dòng = 1 lần ghi; **cùng `uid` ghi nhiều dòng = cập nhật, last-write-wins** ⇒ **đếm dòng KHÔNG bằng đếm bài** |
| `data/.cache/social.sqlite` | index suy ra, gitignored | mất thì replay từ NDJSON, đừng coi là nguồn |
| `8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js` | CLI đọc/ghi sổ | dùng cái này, đừng tự parse NDJSON bằng tay |
| `8syncdev-org-skills/briefs/social-posts-*.md` | brief gốc của từng đợt (`brief_path` trong sổ) | truy ngược nội dung bài |
| Soi live qua `browser-profile-control` | follower/ER thật từng kênh | ghi kèm **ngày soi** |

Cột trong sổ: `uid · platform · account · target · kind · source_url · content_hash · body_chars · lang · hashtags · image_path · permalink · brief_path · verified · posted_at`.

## 1. Input

1. **Khoảng thời gian** báo cáo (mặc định: 7 ngày gần nhất).
2. **Kênh** cần soi (mặc định: tất cả trong sổ).
3. Có cần **số liệu live** (follower, ER) không — nếu có thì phải mở browser profile, và mọi số ghi kèm ngày soi.

## 2. Quy trình

**2.1 Dựng lại sổ + lấy tổng quan:**
```bash
node 8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js init
node 8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js stats
```
`stats` trả `total` · `verified` · `unverified` · `byPlatform` · `duplicateGroups`.

**2.2 Lấy bảng bài đã đăng:**
```bash
node .../post-ledger.js export --md          # bảng markdown: Ngày | ✓ | Nền tảng | Tài khoản | Chỗ đăng | Loại | Ký tự | Link
node .../post-ledger.js list --platform threads --limit 20
```

**2.3 Đối chiếu số bài thật (bẫy đã gặp):**
```bash
wc -l < data/social-ledger.ndjson    # số DÒNG
node .../post-ledger.js stats | grep '"total"'   # số BÀI (unique uid)
```
Hai số này lệch nhau là **bình thường** — sổ là log append-only. Báo cáo phải dùng số của `stats`.

**2.4 Bắt bài chưa kiểm chứng.** `verified = 0` nghĩa là **chưa ai reload permalink và tìm thấy text trên trang**. Không đếm bài đó là "đã đăng thành công". Verify xong thì:
```bash
node .../post-ledger.js verify --uid <uid> --permalink <permalink>
```

**2.5 Soi chất lượng permalink** — permalink phải là **link BÀI**, không phải link trang chủ kênh:
```bash
node -e 'const r=require("fs").readFileSync("data/social-ledger.ndjson","utf8").trim().split("\n").map(JSON.parse);
const u=[...new Map(r.map(x=>[x.uid,x])).values()];
for(const x of u) if(x.permalink && !/\/(posts|post|activity|p)\//.test(x.permalink)) console.log("NGỜ:",x.platform,x.permalink);'
```

**2.6 Soi vi phạm doctrine trong chính sổ:**
- `lang = "en+vi"` ⇒ bài song ngữ, trái doctrine "100% tiếng Việt" (founder chốt 01/08/2026). Bài cũ **sửa tại chỗ sang tiếng Việt**, không xoá đăng lại.
- `image_path = null` ⇒ đăng thiếu ảnh native (doctrine: body = chữ + ảnh native).
- `hashtags = null` ⇒ không ghi lại hashtag, không kiểm được trần từng kênh.
- `duplicateGroups` khác rỗng ⇒ cùng nội dung nằm ở nhiều chỗ, nguy cơ FB phạt duplicate.

**2.7 Số liệu kênh (nếu có yêu cầu):** soi live follower/ER, ghi kèm ngày. Mốc đã có: **fanpage 180 followers (24/07/2026)**; **nhóm FB + nhóm Zalo mỗi nhóm ~1.000 thành viên** (`products.md §KPI`) — ⛔ **không được gọi 1.000 member là 1.000 học viên**.

**2.8 Kết luận "cái gì chạy":** chỉ được kết luận khi có số so sánh được (ER, save/share, hoặc số bài verify theo kênh). Không có số ⇒ ghi *"chưa đủ dữ liệu để kết luận"* và nêu **cần đo gì để lần sau kết luận được**.

**2.9** Xuất `8syncdev-org-skills/briefs/performance-report-<YYYY-MM-DD>.md` theo §3 → tự chấm §4.

## 3. Khung output

```markdown
# Performance Report — <dd/mm–dd/mm> · <YYYY-MM-DD>
Nguồn: data/social-ledger.ndjson qua post-ledger.js (stats/export). Số live kèm ngày soi.
Traffic site: CHƯA ĐO ĐƯỢC (products.md §KPI — chưa bật analytics).

## 1. Đăng gì, ở đâu
| Ngày | Nền tảng | Chỗ đăng | Loại (news/exercise) | Ký tự | Permalink | ✓ verify |
|---|---|---|---|---|---|---|

## 2. Tổng quan
- Số BÀI (unique uid): N  ·  số DÒNG log: M (lệch là bình thường)
- Đã kiểm chứng: X/N  ·  Chưa kiểm chứng: Y/N
- Theo nền tảng: facebook … · instagram … · linkedin … · threads …

## 3. Cần xử lý ngay
| Vấn đề | Bài nào | Việc phải làm |
|---|---|---|
| verified=0 | … | reload permalink, tìm text, rồi `verify --uid` |
| permalink là trang chủ | … | lấy permalink bài thật |
| lang=en+vi | … | sửa tại chỗ sang tiếng Việt |
| duplicate group | … | gỡ bản thừa / đổi hook |

## 4. Cái gì chạy
- <kết luận CÓ số> hoặc <"chưa đủ dữ liệu — cần đo: …">

## 5. Đề xuất tuần tới (chuyển sang campaign-plan)
- …
```

## 4. Checklist tự chấm

- [ ] Số bài lấy từ `stats` (unique uid), KHÔNG phải `wc -l` NDJSON?
- [ ] Đã tách rõ **đã verify** với **chưa verify**, và không gọi bài `verified=0` là "đã đăng"?
- [ ] Mỗi bài có permalink là **link bài**, đã soi bằng lệnh §2.5?
- [ ] Đã liệt kê `duplicateGroups` nếu có?
- [ ] Đã soi `lang` / `image_path` / `hashtags` để bắt vi phạm doctrine?
- [ ] Mọi số live có **ngày soi** đi kèm?
- [ ] Chỗ không có dữ liệu ghi thẳng "chưa đo được", không suy đoán?
- [ ] Không gọi ~1.000 member nhóm là 1.000 học viên?
- [ ] Phần "cái gì chạy" hoặc có số, hoặc nói rõ cần đo gì?

## 5. Trạng thái sổ tại 02/08/2026 (mốc so sánh, đọc bằng lệnh §2)

- **33 dòng NDJSON → 16 bài thật** (unique uid). Đây chính là lý do §2.3 tồn tại.
- **9/16 đã verify**, 7 chưa. **6/16 permalink = null.**
- **6 permalink không trỏ tới bài:** 2 × `https://www.facebook.com/8syncdev` (trang chủ page), 1 × `https://www.instagram.com/8syncdev/`, 3 × LinkedIn `feed/update/urn:li:activity:…` (dạng feed-update, cần đối chiếu xem có mở đúng bài không).
- **1 permalink Threads trỏ sang account NGƯỜI KHÁC:** `threads.com/@lizon_ahamed/post/DbdInHummTg` — không phải `@8syncdev`. Bài này coi như **chưa có bằng chứng đăng**, phải soi lại.
- **8/16 bài `lang = "en+vi"`** ⇒ tồn đọng song ngữ từ trước doctrine 01/08/2026, phải sửa tại chỗ sang tiếng Việt.
- **16/16 bài `hashtags = null` và `image_path = null`** ⇒ đường ghi sổ đang không truyền 2 trường này. Báo lại để lần đăng sau ghi đủ, nếu không thì không bao giờ kiểm được trần hashtag từng kênh bằng dữ liệu.
- Phân loại: `exercise` 12 · `news` 4 ⇒ **lệch tỉ lệ 4 share : 2 bài học : 1 product** (`mkt-playbook §2`) — nêu trong báo cáo, chuyển sang `campaign-plan` để cân lại.

## 6. Đừng làm gì

- **Đừng tin "ô soạn rỗng = đã đăng".** Đã mất 1 reply Threads vì tin dấu hiệu này. Bằng chứng duy nhất: reload permalink và tìm thấy chính đoạn đó trong text của trang.
- **Đừng nhận toast `{ok}` của LinkedIn hay `{shared}` của Instagram làm bằng chứng.** `verified=1` chỉ bật khi đã reload permalink.
- **Đừng đếm dòng NDJSON làm số bài.**
- **Đừng coi `data/.cache/social.sqlite` là nguồn sự thật** — nó là index suy ra, xoá được.
- **Đừng bịa số traffic / conversion / CAC.** Chưa có cổng thanh toán course chốt xong và chưa có trang analytics (`products.md §KPI`); `MKT_06`/`MKT_08` trên Lark vẫn trống.
- **Đừng sửa NDJSON bằng tay.** Muốn cập nhật thì ghi thêm dòng cùng `uid` qua `post-ledger.js` (`verify` / `add`) — last-write-wins.
- **Đừng dừng ở mô tả.** Báo cáo phải kết thúc bằng danh sách việc phải làm, có tên người theo `operations.md §1`.

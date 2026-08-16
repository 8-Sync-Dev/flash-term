---
name: draft-content
description: Soạn MỘT bài đăng hoàn chỉnh cho MỘT kênh cụ thể của 8 Sync Dev (Facebook nick/fanpage/nhóm · Threads · Instagram · LinkedIn) đúng doctrine 01/08/2026 — 100% tiếng Việt, dòng đầu là tiêu đề Unicode-bold đánh nỗi đau, body chỉ chữ + ảnh native, KHÔNG link trong body, link đặt ở comment #1 rồi ghim. Áp đúng luật riêng từng nền tảng (Threads 1 tag/đoạn ≤500 ký tự · Instagram 5 tag + ảnh 1080×1080 · Facebook không trần tag · LinkedIn 3–5 tag). Dùng khi user nói "viết bài này cho Threads", "soạn caption FB", "draft bài IG", "viết post LinkedIn" — dùng campaign-plan nếu cần lịch cả tuần thay vì một bài.
---

# draft-content — soạn 1 bài, 1 kênh, đúng format

Skill này ra **đúng một bài, sẵn sàng đăng**. Lịch cả tuần → `campaign-plan`. Đo kết quả → `performance-report`.

## 0. Cổng copy — KHÔNG chép luật vào đây

Mọi bài PHẢI đi qua cổng canonical DUY NHẤT:
**`../org-social-ops/references/prompt-library-mkt02.md`** — PHẦN 1 (system prompt chống giọng AI + danh sách cụm cấm), PHẦN 2 (ô nhập), TEMPLATE A/B/C theo loại, PHẦN 4 (checklist duyệt 20s).
Đọc luật ở đó. File này **cố ý không nhân bản** danh sách cụm cấm — một luật, một chỗ.

Ground số liệu: `org-core/products.md` (không bịa sản phẩm/số) · `org-core/brand.md` (giọng) · `org-core/mkt-playbook.md §4b` (kho nỗi đau có nguồn) · `§4c` (keyword SEO VN).

## 1. Input phải có

| Trường | Ví dụ | Bắt buộc |
|---|---|---|
| Kênh + identity | `facebook / nick fb.com/8sync / nhóm <tên>` hoặc `threads` | ✅ |
| Loại | `share` \| `bài học` \| `product` (`mkt-playbook §2`) | ✅ |
| Link nguồn CỤ THỂ | `news.8syncdev.com/articles/<slug>` hoặc `coding.8syncdev.com/problem/<slug>` — ⛔ KHÔNG homepage | ✅ |
| Nỗi đau nhắm vào | 1 dòng, lấy từ `mkt-playbook §4b` | ✅ |
| Số liệu được phép nói | trích từ `org-core/products.md` | ✅ |
| Ảnh | đường dẫn ảnh native (card 1080×1080 hoặc ảnh chụp từ site) | ✅ |

## 2. Doctrine format — áp cho MỌI kênh (founder chốt 01/08/2026)

1. **100% tiếng Việt.** Không song ngữ, không đoạn tiếng Anh mở đầu. Tên riêng kỹ thuật (`Rust`, `Tauri`, `Hamming distance`) giữ nguyên — đó là tiếng nghề.
2. **Dòng đầu = TIÊU ĐỀ Unicode-bold** đánh thẳng nỗi đau. Sinh bằng `fmt.h1()` / `fmt.bold()` trong `../fb-group-growth/scripts/fb-groups.js`:
   ```js
   const { fmt } = require('<repo>/8syncdev-org-skills/skills/fb-group-growth/scripts/fb-groups.js');
   fmt.h1('Học 2 năm vẫn tạch phỏng vấn vì mất gốc thuật toán');
   ```
   ⛔ **TUYỆT ĐỐI không `**markdown**` hay `#` trong body** — FB/IG/Threads không render, dấu sao hiện nguyên ra mặt (đã dính thật, `fb-group-growth §1`).
3. **Body = chữ + ẢNH NATIVE. KHÔNG dán link vào body.** Link off-platform trong body bị bóp reach và bị Admin Assist auto-decline.
4. **Link đặt 100% ở COMMENT #1**, tác giả tự đăng trong 1 phút sau khi bài lên, **rồi GHIM comment đó** (`…` trên comment → *Ghim bình luận*).
5. **KHÔNG câu comment.** Không "comment để nhận link", không "inbox mình", không đổi link lấy tương tác.
6. Bio kênh phải có `0768 691 901` + `8syncdev.com/vi/bio` (kiểm 1 lần, không nhét vào body bài).

## 3. Luật RIÊNG từng kênh (verify live 2026-07-29)

| Kênh | Trần hashtag | Ảnh | Ràng buộc riêng |
|---|---|---|---|
| **Threads** | **ĐÚNG 1 topic tag / đoạn** (luật Meta — dấu `#` không hiện, chữ chỉ đổi màu) | tuỳ chọn | **≤500 ký tự / đoạn.** Bài dài → chuỗi reply: đoạn 1 `postThreads`, các đoạn sau reply vào chính permalink (`postThreadsReplyChain`). Chuỗi 6 đoạn = 6 tag khác nhau, vẫn hợp luật. Giọng đồng nghiệp, không "thầy giáo" (`mkt-playbook §4e`) |
| **Instagram** | **5 hashtag / bài** | **BẮT BUỘC ảnh vuông 1080×1080** — IG không render OG card | Caption viết như đang nói với người xem ảnh; ảnh phải tự kể được nội dung |
| **Facebook** (nick · fanpage · nhóm) | **không có trần cứng** — vẫn giữ ít, 2–4 tag Việt hoá theo SEO VN (`mkt-playbook §4c`) | ảnh native trong body | Nhóm ngoài = **share 100% FREE, KHÔNG CTA/quảng cáo**; fanpage + group mình = được full CTA + ads (`fb-group-growth §0`) |
| **LinkedIn** | **3–5 hashtag** | ảnh native | Composer TipTap/ProseMirror hydrate ~13s; link giữa body **không sinh OG card**, chỉ rewrite `lnkd.in` → càng phải theo luật link-ở-comment |

**Hashtag ĐÃ SOI có người dùng thật:** `#laptrinh` `#congnghe` `#itvietnam` `#coder` `#thuattoan` `#hoclaptrinh` `#8syncdev` (brand — LUÔN có).
**Tag CHẾT, CẤM dùng (0 kết quả khi soi):** `#vibecoding` `#devvietnam` `#lomcode` `#AIIDE`.

## 4. Quy trình

1. Đọc cổng copy `../org-social-ops/references/prompt-library-mkt02.md` PHẦN 1 + template khớp loại (A=share · B=bài học · C=product).
2. Mở link nguồn, rút **giá trị thật** — người đọc xong body là dùng được ngay, không cần bấm đi đâu.
3. Viết tiêu đề bold: nỗi đau cụ thể (`mkt-playbook §4b`), có **keyword SEO VN** (`§4c`) vì FB/Google đều index bài public.
4. Viết body theo cấu trúc 5 phần (`fb-group-growth §2b`): tiêu đề bold → hook kể chuyện thật 1–2 dòng → giá trị đầy đủ → ảnh native → hashtag.
5. Gắn CTA phễu bằng ma trận `mkt-playbook §1` — **chỉ khi đăng sân nhà**. Nhóm ngoài: bỏ hết.
6. Cắt đúng trần kênh (§3). Threads: đếm ký tự từng đoạn trước khi soạn.
7. **Chống trùng:** `node ../org-social-ops/scripts/post-ledger.js check --platform <p> --account 8syncdev --url <link> --file <file body>` → exit 3 là bị chặn, viết lại hook khác hoặc đổi bài.
8. **Lưu body ra FILE** rồi mới đăng — không bao giờ gõ lại / escape `\uXXXX` tiếng Việt vào call (đã mất bài: `rất đọi` thay vì `rất đời`, `lỗ hỏng` thay vì `lỗ hổng`; đổi 1 dấu không đổi độ dài nên assert length vô dụng).
9. Tự chấm §6. Đạt thì xuất; không đạt thì viết lại, đừng vá.

## 5. Khung output

```
KÊNH: <facebook nick | fanpage | nhóm X | threads | instagram | linkedin>
LOẠI: <share | bài học | product>

--- BODY (dán nguyên văn) ---
<tiêu đề Unicode-bold>

<hook 1–2 dòng>

<giá trị đầy đủ, mỗi ý 1 dòng>

<hashtag đúng trần kênh>
--- HẾT BODY ---

ẢNH: <đường dẫn file, IG phải 1080×1080>
COMMENT #1 (đăng ngay + GHIM): <link cụ thể /articles/<slug> hoặc /problem/<slug>>
GHI CHÚ SEO: keyword chính · 2–3 keyword phụ (mkt-playbook §4c)
GIỜ ĐĂNG ĐỀ XUẤT: <theo mkt-playbook §4>
```

## 6. Checklist tự chấm

- [ ] 100% tiếng Việt, không đoạn tiếng Anh nào (trừ tên riêng kỹ thuật)?
- [ ] Dòng đầu là tiêu đề **Unicode-bold** sinh bằng `fmt.h1`/`fmt.bold`, KHÔNG có `**` hay `#` nào trong body?
- [ ] Body **không chứa link nào**; link nằm ở comment #1 và có ghi chú "GHIM"?
- [ ] Không câu comment, không "inbox mình"?
- [ ] Hashtag đúng trần kênh (Threads 1/đoạn · IG 5 · LinkedIn 3–5 · FB tiết chế), có `#8syncdev`, không dùng tag chết?
- [ ] Threads: mọi đoạn ≤500 ký tự?  IG: có ảnh 1080×1080?
- [ ] Mở bài bằng nỗi đau thật từ `mkt-playbook §4b`, KHÔNG bằng câu hỏi tu từ?
- [ ] Mọi số liệu tra được trong `org-core/products.md`?
- [ ] Nhóm ngoài → 0 CTA bán, 0 giá, 0 "học thử"?
- [ ] Đã qua cổng copy `prompt-library-mkt02.md` PHẦN 4 (checklist 20s)?
- [ ] Body đã lưu ra file, không gõ tay tiếng Việt vào call?
- [ ] `post-ledger.js check` không chặn?

## 7. Đừng làm gì (đã dính thật)

- **Đừng để `**markdown**` / `#` trong body** — bài cũ đã dính, FB hiện nguyên dấu.
- **Đừng đăng trùng nguyên văn sang nhiều nhóm** (Niri, Astro 7.0, Airflow… mỗi bài xuất hiện 2 lần) → FB phạt duplicate, admin nhận ra spam. Mỗi nơi một bản viết lại.
- **Đừng mở bài bằng câu hỏi tu từ** ("Bạn có đang…?") — nằm trong danh sách cấm của cổng copy.
- **Đừng dùng tag chết** `#AIIDE`, tag rác `#8s`.
- **Đừng tin "ô soạn rỗng = đã đăng".** Bằng chứng duy nhất là reload permalink và tìm thấy chính đoạn đó trên trang.
- **Đừng sửa bài đã đăng bằng cách edit** — xoá rồi đăng lại (thay body trong Lexical fail 2/2, Ctrl+A chọn cả document làm body nhân đôi). Ngoại lệ duy nhất: bài cũ còn tiếng Anh thì **sửa tại chỗ sang tiếng Việt**, không xoá đăng lại.
- **Đừng chép danh sách cụm cấm vào bất kỳ file nào khác** — chỉ trỏ về `prompt-library-mkt02.md`.

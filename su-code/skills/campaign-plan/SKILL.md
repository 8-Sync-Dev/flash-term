---
name: campaign-plan
description: Lập kế hoạch chiến dịch content đa kênh cho 8 Sync Dev theo TUẦN hoặc THÁNG — chia đúng tỉ lệ 4 share : 2 bài học : 1 product, xếp từng bài vào giờ vàng theo nền tảng, gán cho người thật trong team MKT (Hoàng Quyên · Đăng Khoa · Trường Thịnh), và xuất ra file brief trong 8syncdev-org-skills/briefs/ để founder duyệt rồi đổ vào Lark MKT_01. Dùng khi user nói "lên kế hoạch content tuần này", "lịch đăng tháng 8", "plan chiến dịch", "chia bài cho team", "tuần này đăng gì" — KHÔNG dùng để viết nội dung một bài (đó là skill draft-content).
---

# campaign-plan — lịch chiến dịch đa kênh 8 Sync Dev

Skill này chỉ làm **LỊCH + PHÂN CÔNG**. Nó không viết caption (→ `draft-content`), không đo kết quả (→ `performance-report`).
Đầu ra là 1 file brief đủ chi tiết để Hoàng Quyên copy thẳng vào Lark `MKT_01 Lịch nội dung` mà không phải hỏi lại gì.

## 0. Ground trước khi lập lịch (bắt buộc, không bịa)

| Cần gì | Đọc ở đâu |
|---|---|
| Phễu + ma trận CTA chéo | `org-core/mkt-playbook.md §1` |
| Tỉ lệ 4 share : 2 bài học : 1 product + định nghĩa 3 loại | `org-core/mkt-playbook.md §2` |
| **Giờ vàng từng nền tảng + bản đồ theo NGÀY** | `org-core/mkt-playbook.md §4` |
| Kho nỗi đau có nguồn (mở bài) | `org-core/mkt-playbook.md §4b` |
| Ưu tiên nền tảng + luật chi tiền | `org-core/mkt-playbook.md §4d` |
| Team thật + ai làm được gì | `org-core/operations.md §1` |
| Số liệu sản phẩm được phép nói | `org-core/products.md` |
| Vai trò kênh FB (nick vs fanpage) | `8syncdev-org-skills/skills/fb-group-growth/SKILL.md §0` |

## 1. Input phải có trước khi chạy

1. **Phạm vi:** tuần (7 ngày, ngày bắt đầu) hay tháng (số tuần).
2. **Mục tiêu chiến dịch:** 1 câu, đo được. Ví dụ "kéo 300 lượt vào coding.8syncdev.com" — KHÔNG nhận mục tiêu kiểu "tăng nhận diện".
3. **Rổ nguyên liệu:** chạy `node 8syncdev-org-skills/skills/org-social-ops/scripts/news-ideas.js --all --n 3` để lấy ý tưởng `share` từ news; ý tưởng `bài học`/`product` lấy từ `org-core/products.md §3` (mentor, gói giá) và §6 (ZUS).
4. **Ràng buộc tuần này:** ai nghỉ, có sự kiện/ra mắt gì không.

Thiếu (1) hoặc (2) → hỏi founder, đừng tự đoán.

## 2. Quy trình

1. **Đếm slot.** Tuần = 7 bài lõi theo tỉ lệ **4 share · 2 bài học · 1 product** (`mkt-playbook §2`). Tháng = nhân 4, giữ nguyên tỉ lệ mỗi tuần — KHÔNG dồn hết product vào 1 tuần.
2. **Rải theo bản đồ ngày** (`mkt-playbook §4`): T2–T4 = `share` (top-funnel) · T5–T6 = `bài học` / bài bán / flagship · T7–CN = `product` demo / storytelling.
3. **Gán giờ vàng** cho từng bài, theo nền tảng của bài đó, nhớ **đăng TRƯỚC đỉnh**: Facebook trước 30–45', YouTube trước 2–3h, TikTok trước ~1h. Khung mạnh nhất: tối 19:00–22:00 (FB), 19:00–21:00 (TikTok/YT Shorts), 20:30–22:00 (Threads bài kỹ thuật sâu), T5 18:30 (YouTube video dài flagship).
4. **Chọn kênh theo ưu tiên `§4d`:** TikTok (awareness) → Facebook (chốt) → YouTube (SEO dài hạn) → Instagram (chỉ cross-post). Trên Facebook phải nói rõ **nick cá nhân `fb.com/8sync`** (kênh chính, traffic free, đi được vào nhóm) hay **fanpage `fb.com/8syncdev`** (nội bộ + ads).
5. **Gán cửa vào + CTA phụ** cho từng bài bằng ma trận `mkt-playbook §1`. Bài đi **nhóm ngoài** thì bỏ CTA — luật `fb-group-growth §0`.
6. **Gán người thật** (`operations.md §1`):
   - **Hoàng Quyên** — content lead, viết bài, đăng nick cá nhân + fanpage, **chốt sale 100%** (mọi lead đổ về Quyên).
   - **Đăng Khoa** — viết content + SEO keyword + brief cho Thịnh, đăng fanpage. **KHÔNG chốt sale.**
   - **Trường Thịnh** — người DUY NHẤT dựng video/Shorts. Mọi slot có video PHẢI có dòng "brief → Thịnh" kèm deadline sớm hơn giờ đăng ≥1 ngày.
7. **Gắn link CỤ THỂ cho từng slot.** `news.8syncdev.com/articles/<slug>` hoặc `coding.8syncdev.com/problem/<slug>`. ⛔ KHÔNG bao giờ để homepage — giao task thiếu link cụ thể là giao thiếu (`org-social-ops §7`, `briefs/mkt-content-ops-plan.md §6.0`).
8. **Chống trùng trước khi chốt lịch:** với mỗi link định dùng, chạy
   `node 8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js check --platform facebook --account 8syncdev --url <link> --body "<hook dự kiến>"` — exit 3 nghĩa là đã đăng/còn cooldown, đổi bài khác.
9. **Ghi brief** ra `8syncdev-org-skills/briefs/campaign-plan-<YYYY-MM-DD>.md` theo khung §3.
10. **Tự chấm** bằng §4. Dưới chuẩn thì sửa lịch, không xuất.

> **Bàn giao viết bài:** brief chỉ ghi *góc viết*, không ghi caption. Người viết dùng skill `draft-content`, và mọi câu chữ đi qua cổng copy canonical DUY NHẤT `../org-social-ops/references/prompt-library-mkt02.md` (luật chống giọng AI + danh sách cụm cấm nằm ở đó, không nhân bản sang đây).

## 3. Khung output (file brief)

```markdown
# Campaign Plan — <tuần dd/mm–dd/mm> · <mục tiêu 1 câu, đo được>
Nguồn lịch: org-core/mkt-playbook.md §2 (tỉ lệ) + §4 (giờ vàng). Team: operations.md §1.

## Tỉ lệ tuần này
share 4 / bài học 2 / product 1  → [đạt|lệch vì …]

## Lịch
| # | Ngày | Giờ đăng (VN) | Kênh + identity | Loại | Góc viết (nỗi đau §4b) | Link cụ thể | Cửa vào → CTA phụ | Người làm | Deadline |
|---|---|---|---|---|---|---|---|---|---|

## Video cần dựng (brief → Trường Thịnh)
| Slot | Nội dung | Độ dài | Sting MKT 10s (45–55s)? | Deadline giao Thịnh |

## Rủi ro / phụ thuộc
- <ví dụ: chưa có ảnh 1080×1080 cho slot IG ngày T7>

## Ô cần điền vào Lark MKT_01
<liệt kê đúng cột: Content · Nội dung · Người phụ trách · Video/Ảnh · Tài liệu tham khảo · Deadline · Trạng thái · Loại content · Kênh đăng · Chiến dịch>
```

## 4. Checklist tự chấm (thiếu 1 dòng = chưa xuất được)

- [ ] Đúng **4 share : 2 bài học : 1 product** mỗi tuần (`mkt-playbook §2`)?
- [ ] Mỗi bài có **giờ cụ thể** nằm trong khung §4, và đã trừ lùi trước đỉnh (FB 30–45' · YT 2–3h · TikTok 1h)?
- [ ] Rải đúng bản đồ ngày (T2–T4 share · T5–T6 bán · T7–CN demo/giải trí)?
- [ ] Mỗi slot có **link cụ thể** `/articles/<slug>` hoặc `/problem/<slug>`, KHÔNG homepage?
- [ ] Mỗi slot ghi rõ **identity Facebook** (nick `fb.com/8sync` hay fanpage `fb.com/8syncdev`)?
- [ ] Bài đi nhóm ngoài đã **bỏ hết CTA bán** (`fb-group-growth §0`)?
- [ ] Mỗi slot video có dòng brief → **Trường Thịnh** + deadline sớm hơn giờ đăng?
- [ ] Mọi lead/inbox trong plan đều trỏ về **Hoàng Quyên** (sale 100%)?
- [ ] Đã chạy `post-ledger.js check` cho từng link, không slot nào bị chặn?
- [ ] Mọi số liệu trong plan lấy từ `org-core/products.md`, không có số tự chế?

## 5. Đừng làm gì (đã dính thật)

- **Đừng lên lịch toàn `share`.** `operations.md §4` ghi GAP thật: `MKT_01` tháng 07/2026 chỉ có loại "Share kiến thức", chưa tách `bài học`/`product` → không có vế chốt bán.
- **Đừng để slot không có nỗi đau.** Cùng GAP đó: bài FB trung tính, thiếu hook nỗi đau và thiếu CTA phễu.
- **Đừng plan link ra repo/nguồn ngoài** (github, docs của người khác) — đã xảy ra, mất traffic OG-image của mình (`operations.md §4`).
- **Đừng dồn nhiều nhóm cùng một khung giờ** với cùng một bài: FB phạt duplicate. Rải ≥20–30', mỗi nhóm 1 bản viết lại (`fb-group-growth §2b`).
- **Đừng plan boost tiền cho bài chưa có số organic.** Luật bất biến `mkt-playbook §4d`: chỉ boost winner (FB ER≥2% · IG≥3% · TikTok ER≥4–5% + completion≥40–50%).
- **Đừng ghi thông tin đăng nhập** vào brief hay Lark (`org-social-ops §7`).
- **Đừng tự đăng.** Plan là đề xuất; founder duyệt rồi mới chạy.

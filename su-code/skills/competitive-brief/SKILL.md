---
name: competitive-brief
description: Soi đối thủ dạy lập trình ở Việt Nam (CodeLearn, F8/fullstack.edu.vn, CodeGym, FUNiX, 28Tech, VietStem, MindX, Teky, ICANTECH) và xuất brief so sánh CÓ DẪN NGUỒN — giá công khai, segment, kênh mạnh, điểm yếu, khoảng trống 8 Sync Dev đứng vào. Bao gồm cả rủi ro vận hành đã dính thật: nhóm Facebook do đối thủ sở hữu GỠ bài của mình, nên phải sàng nhóm theo CHỦ SỞ HỮU. Dùng khi user hỏi "đối thủ đang làm gì", "so sánh giá với F8/28Tech", "mình khác gì họ", "nhóm này có phải của đối thủ không", "chuẩn bị bài positioning/ads".
---

# competitive-brief — soi đối thủ VN + rủi ro sân đối thủ

Hai việc, một skill, vì chúng là cùng một tấm bản đồ:
① **Định vị** — họ bán gì, giá bao nhiêu, mình đứng vào khoảng trống nào.
② **An toàn phân phối** — nhóm/kênh nào là sân của họ, vào đó là mất bài.

## 0. Ground trước (đọc, đừng research lại từ đầu)

- **`8syncdev-org-skills/briefs/competitor-scan-vn-coding-edu.md`** — bảng đối thủ đã scan 19/07/2026, giá công khai kèm tên nguồn, phân khúc HSG Tin, khoảng trống giá. **Đây là baseline: brief mới là bản CẬP NHẬT của file này, không phải làm lại.**
- `org-core/products.md §"Đối thủ & định vị"` — 5 khác biệt đã chốt: AI IDE riêng (ZUS) · DSA playground tiếng Việt in-browser · news AI tiếng Việt + TTS · mentor thật 1-1 · triết lý chống copy, tất cả liên thông 1 tài khoản.
- `org-core/mkt-playbook.md §4d` — ưu tiên kênh + luật chi tiền, để brief kết luận được "nên đánh ở đâu".
- **`8syncdev-org-skills/skills/fb-group-growth/SKILL.md §3` + `§6`** — luật sàng nhóm theo chủ sở hữu.
- `8syncdev-org-skills/skills/fb-group-growth/references/groups-vn.md` — DB nhóm VN đang theo dõi; brief phải cập nhật lại file này khi phát hiện nhóm mới của đối thủ.

## 1. Input

1. **Câu hỏi cần trả lời.** Ví dụ "28Tech đang bán DSA giá bao nhiêu và mình chào giá thế nào" — không nhận đề bài kiểu "soi đối thủ đi".
2. **Segment nhắm:** (a) HS lớp 5–10 luyện HSG Tin · (b) SV năm 1–2 qua môn C/C++/CTDL · (c) người đi làm nhảy ngành Web/FE · (d) phụ huynh.
3. **Loại brief:** *định vị/giá* hay *an toàn nhóm* hay cả hai.

## 2. Quy trình

1. **Đọc baseline** `briefs/competitor-scan-vn-coding-edu.md`. Liệt kê ra những gì đã có, chỉ đi tìm phần THIẾU hoặc nghi đã cũ (giá thường đổi theo khuyến mãi).
2. **Xác minh lại giá từ trang gốc.** Mỗi con số phải kèm **tên miền nguồn + ngày lấy**:
   ```bash
   curl -s -L --max-time 20 "https://28tech.com.vn/khoa-hoc" | grep -oE '[0-9]{1,3}(\.[0-9]{3})+ ?đ|[0-9]+(,[0-9]+)? ?tr' | sort -u | head -20
   ```
   Trang render bằng JS thì dùng `browser-profile-control` rồi `tab.extract()`, đừng đoán.
   Giá không công khai (Teky, ICANTECH) ⇒ ghi thẳng **"không công khai"** — đó cũng là một phát hiện (phụ huynh nghi ngại), không phải chỗ để điền số ước lượng.
3. **Soi kênh mạnh của họ:** fanpage/YouTube/TikTok — đếm follower thật, xem tần suất, xem dạng content ăn khách. Ghi số kèm ngày soi.
4. **Đối chiếu với 5 khác biệt của mình** (`products.md`). Mỗi đối thủ trả lời đúng 1 câu: *"Họ mạnh chỗ nào mình không có, và mình có gì họ không thể copy trong 6 tháng?"*
5. **Sàng nhóm Facebook theo CHỦ SỞ HỮU** (phần an toàn phân phối):
   - Mở nhóm ở chế độ thời gian: `<group_url>?sorting_setting=CHRONOLOGICAL`.
   - Đọc phần Giới thiệu / admin list: nhóm gắn tên trung tâm nào?
   - **Ngưỡng loại (đã dùng thật):** 1 brand đối thủ chiếm **>50% bài** trong feed ⇒ **BỎ nhóm**.
   - Ghi kết quả vào `../fb-group-growth/references/groups-vn.md` cột trạng thái.
6. **Tìm khoảng trống** — vẽ trục giá × trục "có công cụ riêng hay không". Baseline đã chỉ ra vùng trống **~2–8 triệu/khóa** giữa "thầy cá nhân 500k–1,6tr thủ công" và "trung tâm 20–30tr". Kiểm xem vùng đó còn trống không.
7. **Xuất** `8syncdev-org-skills/briefs/competitive-brief-<YYYY-MM-DD>.md` theo §3 → tự chấm §4.

## 3. Khung output

```markdown
# Competitive Brief — <segment> · <YYYY-MM-DD>
Baseline: briefs/competitor-scan-vn-coding-edu.md (19/07/2026). Bản này cập nhật: <liệt kê thay đổi>.
Mọi giá là giá công khai tại ngày lấy, kèm nguồn ở §5.

## 1. Bảng so sánh
| Đối thủ | Segment | Offer / giá công khai (nguồn · ngày) | Kênh mạnh (số đo · ngày soi) | Điểm yếu nhìn từ 8SD |
|---|---|---|---|---|

## 2. Mình khác gì (đối chiếu products.md)
| Khác biệt 8SD | Đối thủ nào có? | Copy được trong 6 tháng? |
|---|---|---|

## 3. Khoảng trống + đề xuất định vị
- Vùng giá trống: …
- Câu định vị đề xuất (1 câu, dùng được trong ads): …

## 4. AN TOÀN PHÂN PHỐI — nhóm Facebook theo chủ sở hữu
| Nhóm | Quy mô | Chủ sở hữu | % bài của brand đó | Kết luận | Bằng chứng |
|---|---|---|---|---|---|

## 5. Nguồn
| # | Claim | URL | Ngày lấy |
```

## 4. Checklist tự chấm

- [ ] Mỗi con số giá có **URL nguồn + ngày lấy**, không có số trần trụi?
- [ ] Đã đọc baseline `competitor-scan-vn-coding-edu.md` và ghi rõ **cái gì mới so với nó**?
- [ ] Giá không công khai được ghi là "không công khai", KHÔNG ước lượng?
- [ ] Mỗi đối thủ có đúng 1 câu "mình khác gì" đối chiếu `products.md`?
- [ ] Phần an toàn phân phối có **% bài của brand đối thủ** trong feed, không chỉ nói "nhóm này của họ"?
- [ ] Đã cập nhật `../fb-group-growth/references/groups-vn.md` với nhóm mới phát hiện?
- [ ] Kết luận có **đề xuất hành động** (đăng đâu / chào giá bao nhiêu), không dừng ở mô tả?
- [ ] Không có claim nào về đối thủ mà mình không dẫn được nguồn?

## 5. Rủi ro đã dính thật (verified 2026-07-20) — phần quan trọng nhất của skill này

Nhóm "học code" lớn ở VN **phần lớn do trung tâm đối thủ sở hữu**:
- **VietStem** nắm nhóm trẻ **8.4K + 2.5K thành viên**.
- **28Tech** nắm nhóm **25.5K** — feed toàn ad của họ + câu hỏi thành viên, và họ **duyệt bài**.

Hậu quả đã xảy ra: họ **GỠ / từ chối bài cạnh tranh**. Bài viết công, ảnh làm xong, đăng vào rồi mất trắng.

**Luật rút ra (đã thành doctrine `fb-group-growth §3`, §6):**
- Thứ **DUY NHẤT** loại một nhóm là **rủi ro vận hành**, KHÔNG phải content-fit. Content-fit luôn giải được bằng filter tag/category của `news.8syncdev.com` (9 category, 4.688 bài) — nhóm nào cũng có bài khớp.
- Thứ tự đổ lực: **nick cá nhân `fb.com/8sync` (timeline + nhóm) → group của mình → nhóm ngoài neutral**. Sân mình không ai gỡ.
- Muốn với xa hơn sân nhà thì **trả tiền chạy ads trên fanpage**, đừng nhồi CTA vào nhóm người khác.

## 6. Đừng làm gì

- **Đừng đổ lực vào sân đối thủ.** Nhóm do họ nắm = công cốc, đã chứng minh bằng bài bị gỡ.
- **Đừng loại nhóm vì "không có bài phù hợp"** — đó là lý do sai; filter tag của news giải được (`fb-group-growth §3`).
- **Đừng nói xấu đối thủ trong content.** Brief này để định vị nội bộ và chọn sân, không phải để viết bài công kích — giọng brand là "số đo, không khẩu hiệu" (`brand.md`).
- **Đừng chép giá cũ.** Giá đối thủ đổi theo khuyến mãi; quá 30 ngày là phải verify lại từ trang gốc.
- **Đừng trộn segment.** `mind0` (B2B) và Ezen/IELTS đang ⏸️ ngoài scope MKT lập trình (`products.md §SCOPE`) — đừng lôi đối thủ của hai mảng đó vào brief này.
- **Đừng gộp "1.000 member nhóm FB/Zalo" thành "1.000 học viên"** khi so quy mô với đối thủ (`products.md §KPI` cấm rõ).

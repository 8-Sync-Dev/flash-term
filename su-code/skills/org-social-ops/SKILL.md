---
name: org-social-ops
description: Điều hành + tự vận hành content/MKT của 8 Sync Dev (Facebook · Lark · LinkedIn; YouTube/TikTok sau) qua profile browser đã login. Agent TỰ đọc org-core + auto-đọc news.8syncdev.com → phân tích/đánh giá → sinh ý tưởng → viết bài/video theo 2 vế (share-kiến-thức + mkt-sale) → đề xuất đăng, và audit "việc đang sai". Đích cuối: bán tutorial để giáo viên có học viên. Dùng khi user muốn lên content, điều khiển fan page, hoặc audit vận hành MKT.
---

# org-social-ops — tự vận hành content + audit social/MKT 8 Sync Dev

**Đích cuối (north-star):** BÁN được khóa `course` 1-kèm-1 (course.8syncdev.com) → **giáo viên có học viên** (doanh thu chính, products.md §3). Mọi content, dù share hay bán, cuối cùng phải đẩy người xem vào phễu tới course.

Agent tự: (1) đọc `org-core/` làm sự thật, (2) auto-đọc `news.8syncdev.com` + research thị trường, (3) sinh + **tự chấm** ý tưởng theo template, (4) soi kênh thật (FB/Lark/LinkedIn), (5) xuất PLAN/bài + BÁO CÁO việc đang sai. Người duyệt cuối = founder (`Quin19FD`/`8syncdev`).

## 0. Ground trước (bắt buộc — KHÔNG bịa)
- `org-core/products.md` — 7 sản phẩm (scope = **dạy lập trình**: news·coding·course·zus; Ezen/mind0/B2B ⏸️). Số liệu để lên bài lấy từ đây.
- `org-core/brand.md` — founder, kênh, domain, giọng.
- `org-core/mkt-playbook.md` — **TEMPLATE chuẩn**: phễu xoay vòng + ma trận CTA chéo (§1), 3 loại content (§2), 3 mắt xích sản xuất (§3), **giờ vàng đăng nghiên cứu sâu 2026 — bảng đủ TikTok/Facebook/YouTube Shorts/YouTube dài/YouTube Community + bản đồ theo ngày (§4)**, kho nỗi đau có nguồn (§4b), SEO VN (§4c), phân phối + chi tiền (§4d).
- `org-core/operations.md` — team thật + **vai trò: Hoàng Quyên & Đăng Khoa = MKT·Sale·Content (ALL TRỪ EDIT); Trường Thịnh = EDIT (video/V.O, người duy nhất edit); Khoa làm brief → Thịnh dựng**. Lark Base, §5b cấp admin news. Cộng đồng: nhóm FB + Zalo ~1.000 member/nhóm (tệp warm).
- **News API (public, KHÔNG auth — ĐỌC TRƯỚC khi lên content, đây là kho gốc):** base `https://news.8syncdev.com/api/backend/news/news`. Backend cron bài mới **mỗi ngày**, đã **tóm tắt tiếng Việt** (`viSummary`) + ảnh OG (`imageUrl`) + `whyRead` + `score`/`upvotes`.
  - `/feed?rank=latest|hot&limit=N` — mới nhất / hot nhất. `/feed?category=<slug>&rank=hot&limit=N` — theo danh mục.
  - `/rankings?period=7d|30d|all` — top kỳ · `/categories` — 9 danh mục + số bài · `/search?q=` · `/tags`, `/hot-tags?window=7d`, `/tags/<tag>`.
  - **9 categories** (dùng categories HỌC THUẬT là dễ làm nhất): `ai-ml`·`frontend`·`backend`·`devops`·`security`·`mobile`·`opensource`·`career`·`other`. Trang: `/danh-muc/<slug>`.
  - **LINK NGƯỢC = `https://news.8syncdev.com/articles/<slug>`** (đăng cái này → OG image tự hiện trên FB; KHÔNG đăng link nguồn gốc ra ngoài).

## 1. Chiến lược: 2 VẾ content, 1 ĐÍCH
Cùng đổ về bán tutorial, nhưng 2 vế khác vai trò phễu:

| Vế | Nguồn | Vai trò phễu | Loại content | Format |
|---|---|---|---|---|
| **A. Share-kiến-thức** | **news site** (auto-đọc) + kiến thức chung | **TOP** — phủ + kéo traffic + xây uy tín; quảng cáo ẩn | `share` | bài viết FB (repost news, OG image), video ngắn tin tức |
| **B. MKT-Sale** | khóa/mentor thật (tutorial) + sản phẩm | **MID/BOTTOM** — chứng minh chất lượng + chốt | `bài học`, `product` | bài viết bán, **video** lát cắt bài giảng, demo, testimonial/kết quả học viên, mentor spotlight |

- **Share-kiến-thức vẫn tái dùng cho MKT-Sale:** một tin AI/tech (vế A) có thể cắt thành "bài học" (vế B) khi trích 1 kỹ thuật ra dạy → gắn CTA tutorial.
- **Tỉ lệ/tuần (mkt-playbook §2):** ~**4 share : 2 bài học : 1 product** — share dẫn dắt, sale là điểm chốt.
- **Luôn:** 1 "cửa vào" (hook giá trị free) + CTA phụ trỏ sản phẩm kế trong phễu (ma trận §1 playbook) + "một tài khoản dùng tất cả".

## 2. Auto-đọc news → ý tưởng (engine)
```bash
node 8syncdev-org-skills/skills/org-social-ops/scripts/news-ideas.js --n 8            # hot nhất (mặc định), idea card markdown
node .../news-ideas.js --rank latest --n 8         # mới nhất (bài cron hôm nay)
node .../news-ideas.js --all --n 3                 # DUYỆT HẾT categories học thuật, nhóm theo danh mục (dễ lên lịch tháng)
node .../news-ideas.js --category ai-ml --n 6      # 1 danh mục · --period 7d|30d|all dùng bảng xếp hạng
node .../news-ideas.js --json                      # JSON để pipe tiếp (đổ vào Lark, sinh bài…)
```
Engine: fetch **API** (rank/category/rankings) → dùng `viSummary` (VN sẵn) + `category` + `upvotes` → chấm nỗi đau/nghề/học phụ → phân loại `share`/`bài học`/`product` → map pillar + cửa-vào + CTA + **link ngược `/articles/<slug>`**. `--all` nhóm theo **danh mục học thuật** (dễ nhất để lên bài + chia lịch tháng). Output là **gợi ý** — người viết bám nỗi đau & số THẬT.

## 2b. Sinh BÀI hoàn chỉnh từ ý tưởng — bộ prompt chuẩn (MKT_02, team R&D)
Ý tưởng (§2) → caption/hashtag/CTA/kịch bản hoàn chỉnh bằng **`references/prompt-library-mkt02.md`**:
- **PHẦN 1** = system prompt CHỐNG giọng AI (danh sách cụm sáo rỗng CẤM: "trong thời đại 4.0", "hãy cùng tìm hiểu", "không thể phủ nhận"… + luật SEO VN + CTA phễu theo loại).
- **PHẦN 2** = ô nhập (Tiêu đề · Loại · Kênh · Slug · Brief · Số liệu được phép) — biến duy nhất phải gõ.
- **TEMPLATE A/B/C** theo `share`/`bài học`/`product`; **PHẦN 3** = 3 bài mẫu chuẩn (neo giọng); **PHẦN 4** = checklist duyệt 20s; **PHẦN 5** = đấu nối automation Lark→AI→cột `Nội dung`.
- Đầu ra đúng **KHUNG OUTPUT** (Caption · Comment#1 link · Hashtag · [Kịch bản 60s nếu TikTok] · Ghi chú SEO). Nguyên tắc: **AI ra nháp 80%, người chốt 20%** (giọng + số THẬT + CTA). Bổ trợ rubric tự chấm §5.

## 3. Kênh & control (profile browser đã login)
```bash
bash 8syncdev-org-skills/skills/browser-profile-control/scripts/profile-browser.sh open linkedin "<url>"
```
Rồi attach omp `browser` vào `http://127.0.0.1:9222` (action open, app.cdp_url) → thao tác bằng `tab.evaluate` (đọc DOM = text).

| Kênh | URL | Login | Profile |
|---|---|---|---|
| **Facebook** fan page | facebook.com/8syncdev | ✅ (179 followers, 19/07) | `linkedin` |
| **Lark** workspace | tenant "8 SYNC DEV Workspace" (JP) | ✅ | `linkedin` |
| **LinkedIn** | linkedin.com/in/8syncdev | ✅ | `linkedin` |
| **YouTube** @Dev8Sync (Shorts + video dài + Community post) · **TikTok** @8syncdev | studio.youtube.com · tiktok.com | ⏳ founder đang login thêm | `linkedin` |
| **Facebook nick cá nhân** (Hoàng Quyên phụ trách) | facebook.com/8sync ("Nguyễn Kevin", 1K) | ✅ | `linkedin` |
| **Threads** 🧵 (mỏ vàng dev VN, viral 0đ — giờ vàng tối 20:30–22h) | threads.net | ⏳ login qua Instagram | `linkedin` |

> 1 profile `linkedin` giữ session cả 3 kênh. Lark CLI KHÔNG sang tenant khác (Forbidden 91403) → Lark qua browser. Edit LinkedIn: ProseMirror expose `el.editor` → `editor.commands.setContent(PM_JSON, true)` (HTML nuốt `&`, keyboard/paste không ăn selection).

## 4. Quy trình end-to-end (tự chạy 1 mạch)
1. **Research** — `web_search`/`last30days`: nỗi đau học lập trình VN, trend, đối thủ (CodeLearn/F8/CodeGym/FUNiX/28Tech), giờ vàng. Số mới → cập nhật `mkt-playbook §4b/§4c`.
2. **Auto-đọc news** — chạy `news-ideas.js` → rổ ý tưởng share (vế A).
3. **Bổ sung sale** — từ `products.md §3` (tutorial): mentor, giá gói, kết quả → ý tưởng vế B (bài học/product).
4. **Tự chấm** mỗi ý tưởng bằng rubric §5 → loại bài yếu, giữ bài mạnh, cân tỉ lệ 4:2:1.
5. **Soi kênh thật** — FB (`scripts/audit-fanpage.js`), Lark `MKT_01`/`OPS_01`, LinkedIn → đối chiếu template.
6. **Xuất** `briefs/content-plan-<tuần>.md` (lịch + phân công + giờ vàng) + `briefs/audit-social-<date>.md` (việc đang sai). Đăng = đề xuất, founder duyệt.

## 5. Rubric agent TỰ chấm mỗi bài (0–2 mỗi tiêu chí; <8/12 → viết lại)
1. **Nỗi đau thật** mở đầu (§4b, có nguồn) — không phải tin trung tính.
2. **Cửa vào rõ** = 1 sản phẩm free (coding/news/zus) — *chỉ sân nhà*; **nhóm ngoài: chỉ giá trị free, KHÔNG cửa-vào-bán**.
3. **CTA phễu** trỏ sản phẩm kế + hướng tutorial — **CHỈ sân nhà (fanpage/group mình); nhóm ngoài BỎ mọi CTA + KHÔNG câu comment**.
4. **Link TRONG body** về `news.8syncdev.com`/`coding.8syncdev.com` (mn tự xem, KHÔNG giấu comment) — KHÔNG link ra repo/đối thủ ngoài.
5. **SEO VN** (§4c): keyword long-tail, hashtag Việt — không generic EN.
6. **Đúng vế + format**: share→bài viết/repost; bài học→video lát cắt dạy; product→demo. Đúng giờ vàng (§4).

## 6. Checklist "việc đang sai" (audit kênh)
- [ ] Bài share mở bằng nỗi đau thật? Có kéo từ news + link về news?
- [ ] **Sân nhà:** có CTA phễu (coding→tutorial→zus, "một tài khoản"), hướng bán tutorial? **Nhóm ngoài:** share 100% FREE, KHÔNG CTA/câu comment, link+ảnh site trong body?
- [ ] Hashtag/keyword bám SEO VN?
- [ ] Đúng giờ vàng theo bảng §4 (đăng TRƯỚC đỉnh: FB 30–45', YT 2–3h, TikTok ~1h; tối 19–21h; flagship YT dài T5 18:30) + đủ nhịp bài/ngày?
- [ ] Tỉ lệ 4 share : 2 bài học : 1 product/tuần?
- [ ] Có đủ **vế sale** (bài học/product bán tutorial) chứ không chỉ share suông?
- [ ] TikTok 60s có sting MKT 10s (45–55s)?
- [ ] Lark `MKT_01` có lịch + phân công; mắt xích GV→Hoàng Quyên→MKT chạy?

## 7. Nguyên tắc
- **KHÔNG hỏi/ghi thông tin tài khoản (login/username/mật khẩu) vào Lark hay content** — account do founder tự lo. Plan/record luôn tập trung **VIỆC LÀM GÌ** (task cụ thể: ai đăng bài gì, giờ nào, kênh nào), tuyệt đối không nhét thông tin đăng nhập.
- Data thật hoặc verify — không bịa số/sản phẩm/kết quả học viên.
- **SALE = HOÀNG QUYÊN 100%** (rule founder 2026-07-21): mọi tư vấn/chốt lead đổ về Quyên — Khoa/Thịnh chỉ rep comment kỹ thuật; `MKT_08` cột `Người chăm sóc` default = Quyên. Content sinh ra CTA inbox → hiểu là inbox Quyên.
- **⛔ 2 LOẠI KÊNH (founder 2026-07-21):** Nhóm NGOÀI (nick) = **share 100% FREE, KHÔNG quảng cáo/CTA, KHÔNG câu comment, link+ảnh site TRONG body** (không giấu comment). Fanpage + group MÌNH = được full phễu quảng cáo. KHÔNG share quảng cáo đi nhóm ngoài. Hashtag luôn có #8syncdev + tag nhóm nếu bắt buộc. Chi tiết: `fb-group-growth §0`.
- **Kho content xoay tua (số verify 21/07):** news **4.688 bài** (`/api/backend/news/news/feed`) + coding **1.000 bài** (`/api/exercises`, title meme VN). Cadence chuẩn: ≥2 bài news/ngày + 1 ảnh meme đề coding/ngày (ops-plan §2).
- **⛔ HỢP ĐỒNG GIAO TASK (bất biến):** mọi record gán người PHẢI đủ **Brief + Detail + Link CỤ THỂ** — coding = `coding.8syncdev.com/problem/<slug>`, news = `news.8syncdev.com/articles/<slug>` (KHÔNG BAO GIỜ homepage). Detail chung chung ("chọn 1 bài") = giao thiếu. Thiếu 1/3 → `Backlog`, chưa gán người. Canonical: `mkt-content-ops-plan §6.0`.
- Không tự đăng/xoá/đổi (impactful) khi chưa duyệt — **report + đề xuất**, founder duyệt.
- Sau mỗi lần: cập nhật `CHANGELOG.md` + học vào `su-code/KNOWLEDGE.md`.
- Mở rộng YouTube/TikTok: thêm dòng bảng §3 + tiêu chí video vào rubric §5.

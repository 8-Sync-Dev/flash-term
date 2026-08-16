---
name: discord-ops
description: Vận hành Discord cho 8 Sync Dev — audit các server đang join (giữ server "8 Sync" + server lớn để lấy kết nối/traffic/việc làm, rời server nhỏ-chết-không liên quan), dọn spam và bật AutoMod cho 8 Sync Forum, đăng đều news/exercise vào đúng kênh với YouTube là đích cuối, và chạy bot trả lời tự động bằng Node thuần (scripts/discord-bot.mjs, không discord.js) chỉ nói bằng kho câu đã duyệt trong references/brand-answers.md. Dùng khi user muốn dọn/dựng server Discord, đăng bài vào Discord, hoặc bật bot trả lời câu hỏi lặp.
---

# discord-ops — vận hành Discord 8 Sync Dev

Discord là **kênh chat**, không phải feed. Ba hệ quả kéo theo toàn bộ skill này: reach không bị
thuật toán bóp nên **link đặt thẳng trong body** (khác Facebook), người ta hỏi rồi chờ trả lời
ngay nên **im lặng lâu = server chết**, và spam sống được nhiều ngày nếu không ai kiểm duyệt —
đúng thứ đang xảy ra ở `sửa-lỗi-lập-trình` (`references/server-structure.md` §1).

**Đích của phễu là YouTube** (founder chốt 02/08/2026). Kênh `@Dev8Sync` — 2.490 người đăng ký ·
313 video (verify 02/08/2026) — là tài sản own lớn nhất tính theo lượng nội dung. Mọi bài đăng
vào Discord phải có **ít nhất một đường về YouTube, và YouTube đứng đầu danh sách link**, rồi mới
tới news/coding. Handle `@8syncdev` trên YouTube **không tồn tại** (404) — dùng nhầm là mất traffic.

## 0. Ground trước (bắt buộc, không bịa)

- `org-core/products.md`, `org-core/brand.md`, `org-core/operations.md` — sản phẩm, số, giọng, người.
- `org-core/mkt-playbook.md` — phễu, giờ vàng, nỗi đau có nguồn.
- **Cổng copy canonical:** `../org-social-ops/references/prompt-library-mkt02.md` **PHẦN 1** —
  luật chống giọng AI + danh sách cụm cấm. Mọi chữ đăng lên Discord phải đi qua đó.
  **KHÔNG chép danh sách cụm cấm sang bất kỳ file nào của skill này.**
- `../org-social-ops/SKILL.md` — doctrine kênh (VI 100%, không câu comment, tỉ lệ nội dung).
- `../fb-group-growth/SKILL.md` — doctrine nhóm; hàm `fmt.h1()` sinh tiêu đề Unicode-bold nằm ở
  `../fb-group-growth/scripts/fb-groups.js`. **Cấm markdown `**...**` cho tiêu đề trên mạng xã
  hội** — nhưng xem §3 để biết Discord là ngoại lệ ở điểm nào.
- `references/server-structure.md` — hiện trạng 8 Sync Forum (`[QUAN SÁT]`) và sơ đồ đích (`[ĐỀ XUẤT]`).
- `references/brand-answers.md` — kho câu bot được phép nói.

**Việc skill này KHÔNG làm** (đã có chủ, gọi sang đó): lịch tuần/tháng và tỉ lệ 4 share : 2 bài
học : 1 product → `../campaign-plan`. Soạn nội dung một bài cho một kênh → `../draft-content`.
Đăng đa kênh Facebook/Threads/IG/LinkedIn → `../org-social-ops` (`scripts/social-multi.js`).
Đọc sổ cái, báo cáo → `../performance-report`.

## 1. Audit server đang join — luật giữ/rời

Founder đăng nhập bằng tài khoản `8 Sync Dev`. Trước khi làm gì khác, liệt kê **mọi server đang
join** rồi phân loại. Luật dứt khoát, không cần cân nhắc từng ca:

| Loại server | Quyết định | Vì sao |
|---|---|---|
| Tên có chữ **"8 Sync"** (8 Sync Forum…) | **GIỮ** — đây là sân nhà, không bao giờ rời | Server của chính founder |
| Server **lớn** (dev/AI/việc làm, đông và còn hoạt động) | **GIỮ** — nguồn kết nối, traffic và cơ hội việc làm cho team | Ở lại để lấy quan hệ và tin tuyển, không phải để rải quảng cáo |
| Server **nhỏ, chết, hoặc không liên quan** | **RỜI** | Sidebar sạch thì mới nhìn ra server nào đáng chăm; server chết chỉ tạo tiếng ồn thông báo |

Cách phân loại nhanh, không đoán: mở server → nhìn **tin nhắn gần nhất** ở kênh chính (im quá
30 ngày = chết) và **số người online** ở sidebar. Không liên quan = không phải lập trình, AI,
công nghệ, việc làm IT.

Ba việc luôn làm cùng lúc với audit, vì chúng rẻ và chặn đúng thứ đang gây hại:
tắt **DM từ thành viên chung server** (Privacy Settings), tắt thông báo mặc định ở server chỉ để
quan sát, và ghi lại danh sách server GIỮ vào brief — lần audit sau so được với lần này.

⚠ **Rời server là hành động không hoàn tác** (mất lịch sử, mất link mời với server private).
Agent **đề xuất danh sách rời, founder bấm** — giống luật ở `org-social-ops §7`.

## 2. Dọn spam + bật AutoMod (làm trước mọi việc content)

Đăng bài hay vào một server đang có ảnh scam là đổ nước vào xô thủng. Thứ tự:

1. Xoá bài spam Telegram + ảnh scam USDT ở `sửa-lỗi-lập-trình`, ban tài khoản đăng, xoá mọi tin
   nhắn khác của nó.
2. Bật **AutoMod** 4 luật + **Verification Level = Medium** — bảng đầy đủ ở
   `references/server-structure.md` §3.
3. Viết lại `#quy-tắc` kèm 3 dòng về scam DM.

Chi tiết từng bước, thứ tự 7 việc và sơ đồ kênh đích: `references/server-structure.md` §3–§4.

## 3. Nhịp đăng news/exercise — và ngoại lệ link của Discord

**Kênh đích cố định** (đăng sai kênh thì bài chìm, không ai đọc):

| Loại nội dung | Kênh | Nhịp |
|---|---|---|
| Tin công nghệ từ `news.8syncdev.com` | `lập-trình-công-nghệ-mới` (sau khi gộp: `#tin-công-nghệ`) | ≥2 bài/ngày |
| Đề luyện từ `coding.8syncdev.com` | `bài-tập-lập-trình` | 1 đề/ngày |
| Video mới của `@Dev8Sync` | `#video-mới` (kênh đề xuất, §3 server-structure) | mỗi khi có video |

**Doctrine giữ nguyên trên Discord:**
- **Tiếng Việt 100%.** Tiếng Anh chỉ được là đoạn phụ ngắn đặt SAU. Tên riêng kỹ thuật (`Rust`,
  `Hamming distance`, `WebSocket`) giữ nguyên.
- **KHÔNG câu comment.** Không "thả tim để nhận link", không "inbox mình".
- Giọng người thật, đi qua cổng copy ở §0. Không giọng PR.
- **Mỗi bài có ít nhất 1 link YouTube, đặt trước các link khác**, kèm một câu cầu nối tự nhiên
  sang video liên quan (kiểu "chỗ này mình có giải thích kỹ hơn trong video…"), tuyệt đối không
  "nhớ đăng ký kênh nhé".

**Ba chỗ Discord KHÁC Facebook — làm theo Discord, đừng bê nguyên luật Facebook sang:**

| Điểm | Facebook/Threads/IG | Discord |
|---|---|---|
| Link | Cấm trong body, đặt ở **comment #1** rồi ghim | **Đặt thẳng trong body.** Discord không bóp reach link, còn tự render preview YouTube — bắt người ta lội xuống reply là tự làm khó |
| Tiêu đề đậm | Unicode-bold `fmt.h1()`, cấm markdown | Discord **render markdown thật**, nên `**tiêu đề**` hiện đúng chữ đậm. Vẫn dùng `fmt.h1()` được nếu muốn thống nhất một bản copy cho mọi kênh; điều cấm là để dấu sao thô lọt ra chỗ không render |
| Ảnh | Bắt buộc ảnh native | Tuỳ. OG image của coding (`/problem/<slug>/opengraph-image`) và preview YouTube tự hiện từ link, không cần upload |

Ghim bài quan trọng bằng chính chức năng Pin của Discord (không có khái niệm "comment #1").

**Đăng bằng script** — soạn nội dung ra file text (giữ nguyên chữ tiếng Việt, không gõ lại,
không escape `\uXXXX` — luật số 1 của `org-social-ops §3b`), rồi:

```bash
export DISCORD_BOT_TOKEN='...'   # lấy token: xem §4
cd 8syncdev-org-skills/skills/discord-ops/scripts
node discord-bot.mjs post --channel <channel_id> --file ../../../briefs/discord-news-2026-08-02.txt --dry-run
node discord-bot.mjs post --channel <channel_id> --file ../../../briefs/discord-news-2026-08-02.txt
```

`--dry-run` in ra đúng thứ sẽ gửi (kèm số phần nếu bài dài hơn trần 2.000 ký tự của Discord).
Luôn chạy `--dry-run` trước — đăng nhầm kênh thì phải xoá tay.

⚠ **Sổ cái chưa nhận Discord:** `post-ledger.js` chốt cứng 7 nền tảng và không có `discord`, nên
`add --platform discord` bị từ chối. Chống trùng tạm bằng search trong kênh đích trước khi đăng
(`references/server-structure.md` §5). Đừng ghi bừa sang nền tảng khác cho có.

## 4. Chạy bot trả lời tự động

Bot ở `scripts/discord-bot.mjs`: Node thuần, dùng `WebSocket` + `fetch` toàn cục của Node 26,
**không discord.js, không thêm dependency**. Nó **không sinh chữ và không gọi LLM** — chỉ khớp
câu hỏi với `references/brand-answers.md` rồi trả nguyên văn mục khớp nhất. Không đủ khớp thì
**im lặng**: trả lời sai brand đắt hơn nhiều so với không trả lời.

**Lấy token** (một lần): Developer Portal → New Application → tab Bot → Reset Token → bật
**MESSAGE CONTENT INTENT** → tab OAuth2 → URL Generator → scope `bot` + quyền View Channels,
Send Messages, Read Message History → mở link, mời bot vào 8 Sync Forum. Chạy
`node discord-bot.mjs` không có token thì nó in đúng 5 bước này ra màn hình.

**Token chỉ sống trong biến môi trường `DISCORD_BOT_TOKEN`.** Không hardcode, không cho vào file
trong repo, không dán vào Lark hay chat (`org-social-ops §7`). Mọi log của bot đi qua bộ che —
token lọt vào chuỗi lỗi của Discord thì bị thay bằng `••••<4 ký tự cuối>`.

```bash
cd 8syncdev-org-skills/skills/discord-ops/scripts
node discord-bot.mjs --help                     # usage đầy đủ
node discord-bot.mjs --once                     # smoke test: in READY + số server rồi thoát 0
node discord-bot.mjs --dry-run --channel <id>   # nghe 1 kênh, in câu định trả lời, KHÔNG gửi
node discord-bot.mjs --channel <id>             # chạy thật, giới hạn 1 kênh
node discord-bot.mjs                            # chạy thật, mọi kênh bot thấy
```

**Cách lên sóng đúng:** `--once` (thông đường) → `--dry-run --channel <#câu-hỏi>` chạy một ngày →
đọc log xem nó định nói gì → sửa `brand-answers.md` → mới bỏ `--dry-run`. Bật thẳng chế độ gửi
thật ở toàn server là cách nhanh nhất để bot nói sai vào đúng chỗ đông người.

**Hàng rào đã dựng sẵn trong bot** (đừng nới nếu chưa đo):
- Ngưỡng khớp 2 điểm; một từ đơn lẻ không bao giờ đủ để bot mở miệng (`--min-score` chỉnh được).
- Cùng một user chỉ được trả lời 1 lần / 60 giây.
- Không bao giờ trả lời chính nó, bot khác, hay webhook.
- `allowed_mentions: {parse: []}` — bot không thể @everyone dù kho câu trả lời có lỡ chứa.
- Mất 2 nhịp heartbeat ACK → tự đóng và kết nối lại có backoff; RECONNECT/INVALID_SESSION xử lý
  đúng vòng đời Gateway v10. Đóng với mã 4004/4013/4014 (token sai, intent chưa bật) thì **dừng
  hẳn** thay vì quay vòng vô ích.

**Sửa mồm bot = sửa `references/brand-answers.md`**, không đụng code. Luật viết một mục (tối đa
4 câu, cụm khoá nhiều từ, link ở dòng cuối và YouTube đứng đầu) nằm ngay đầu file đó.

Kiểm bộ khớp không cần mạng, chạy được mọi lúc:

```bash
cd 8syncdev-org-skills/skills/discord-ops/scripts
node --input-type=module -e '
const m = await import("./discord-bot.mjs");
const e = m.loadAnswers();
for (const q of ["zus là gì","cài zus lỗi","học phí bao nhiêu","abcxyz không liên quan"]) {
  const r = m.matchAnswer(q, e);
  console.log(q, "→", r ? r.topic : "IM LẶNG");
}'
```

## 5. Đo bằng gì

Năm chỉ số + cách đếm: `references/server-structure.md` §5. Tóm tắt: người tự giới thiệu ở
`#chào-hỏi`/tuần · số ngày liên tiếp `#câu-hỏi` có người ngoài team nói · bài ở `#khoe-thành-quả`
/tháng · số lần AutoMod chặn/tuần · click sang YouTube/coding (chờ trang analytics riêng của
founder — `products.md §KPI` ghi rõ chưa có nguồn số, **không bịa**).

Riêng bot, đọc từ log của chính nó: số lần `[khớp]` so với số lần `[im lặng]`. Im lặng nhiều mà
toàn câu hỏi chính đáng ⇒ thiếu mục trong kho, thêm mục chứ đừng hạ `--min-score`.

## 6. Nguyên tắc

- **Không tự rời server, không tự xoá kênh, không tự ban người** khi chưa có founder duyệt. Xoá
  spam rõ rành (link Telegram bán tài khoản, ảnh scam USDT) là ngoại lệ duy nhất — cứ xoá.
- **Không bao giờ hỏi hay ghi lại thông tin đăng nhập** của founder. Bot dùng token riêng của
  application, không dùng tài khoản người.
- Số nào không có trong `org-core/` thì không được viết ra Discord.
- Sau mỗi đợt: thêm bullet vào `CHANGELOG.md`, học rút ra ghi vào `su-code/KNOWLEDGE.md`.
- Sửa skill này thì **mirror** sang `su-code/skills/discord-ops/` cho khớp byte rồi chạy
  `node su-code/build-skills-index.mjs`.

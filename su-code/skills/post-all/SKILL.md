---
name: post-all
description: Cỗ máy "một câu là chạy hết" cho content 8 Sync Dev — kiểm plan đang có trước, thu hoạch + xếp hạng nguyên liệu thật từ news.8syncdev.com và coding.8syncdev.com, lên lịch ĐÚNG 1 THÁNG rồi soạn và đăng hết các kênh, chốt bằng sổ cái. Dùng khi founder nói "lên bài đi", "lên plan tháng", "đăng hết các kênh", "tháng này đăng gì", "chạy content đi" — KHÔNG dùng để viết một bài lẻ (đó là draft-content) hay chỉ lên lịch (campaign-plan).
---

# post-all — lên plan 1 tháng rồi đăng hết, gọi bằng một câu

Skill này **ĐIỀU PHỐI**, không làm lại việc của ai:

| Việc | Chủ sở hữu | Đường dẫn |
|---|---|---|
| Xếp hạng nguyên liệu thật (news · exercise · đích YouTube) | **post-all** (chỉ mình nó) | `scripts/harvest.mjs` |
| Lịch + phân công + giờ vàng | `campaign-plan` | `8syncdev-org-skills/skills/campaign-plan/SKILL.md` |
| Soạn 1 bài cho 1 kênh | `draft-content` | `8syncdev-org-skills/skills/draft-content/SKILL.md` |
| Đăng + chống trùng + ghi sổ | `org-social-ops` | `8syncdev-org-skills/skills/org-social-ops/scripts/social-multi.js` |
| Đọc sổ, báo cáo | `performance-report` | `8syncdev-org-skills/skills/performance-report/SKILL.md` |
| Luật copy / chống giọng AI / **danh sách cụm cấm** | `org-social-ops` (cổng canonical DUY NHẤT) | `8syncdev-org-skills/skills/org-social-ops/references/prompt-library-mkt02.md` PHẦN 1 |

> Luật copy đọc **tại cổng đó**. File này cố ý **không nhân bản** danh sách cụm cấm — một luật, một chỗ; nhân bản là cách chắc chắn nhất để hai bản lệch nhau.

**Ground số liệu, không bịa:** `org-core/products.md` (sản phẩm + số) · `org-core/brand.md` (giọng) · `org-core/operations.md` (ai làm gì) · `org-core/mkt-playbook.md` (§1 phễu · §2 tỉ lệ 4 share : 2 bài học : 1 product · §4 giờ vàng · §4b nỗi đau có nguồn).

**Doctrine đang có hiệu lực** (đọc `org-social-ops/SKILL.md §7` + `draft-content/SKILL.md §2` cho bản đầy đủ): 100% tiếng Việt mọi kênh · dòng đầu là tiêu đề Unicode-bold sinh bằng `fmt.h1()` (⛔ không `**markdown**`) · body chỉ chữ + ảnh native, **không link trong body** · link 100% ở **comment #1 rồi ghim** · **không câu comment** · **YouTube `@Dev8Sync` là ĐÍCH của phễu** (founder chốt 2026-08-02) nên comment #1 xếp **YouTube → news → coding**, và **không bài nào được thiếu 1 đường về YouTube**.

---

## Bước 0 — KIỂM PLAN TRƯỚC KHI LÊN PLAN MỚI (bắt buộc, chạy đầu tiên)

Sai hay gặp nhất là nghe "lên bài đi" rồi sinh plan mới trong khi plan tháng đang chạy → hai lịch chồng nhau, bài đăng lệch, sổ cái chặn trùng ầm ầm. Chạy đúng lệnh này trước, không đoán:

```bash
node -e "
const fs=require('fs'), d='8syncdev-org-skills/briefs';
const f=fs.readdirSync(d).filter(x=>/^campaign-plan-.*\.md\$/.test(x)).sort().pop();
if(!f){ console.log('KHÔNG có campaign-plan nào → sinh plan mới, đi Bước 1'); process.exit(0); }
const t=fs.readFileSync(d+'/'+f,'utf8');
const m=t.match(/^Hiệu lực:\s*(\d{4}-\d{2}-\d{2})\s*→\s*(\d{4}-\d{2}-\d{2})/m);
const today=new Date().toISOString().slice(0,10);
if(!m){ console.log('CÓ '+f+' nhưng THIẾU dòng \"Hiệu lực:\" → coi như hết hiệu lực, sinh plan mới'); process.exit(0); }
console.log(m[1]<=today && today<=m[2]
  ? 'CÒN HIỆU LỰC ('+m[1]+' → '+m[2]+') → ĐỌC '+d+'/'+f+' rồi CHẠY TIẾP từ Bước 3. TUYỆT ĐỐI không sinh plan mới.'
  : 'HẾT HIỆU LỰC ('+m[1]+' → '+m[2]+') → sinh plan mới, đi Bước 1');
"
```

- **CÒN HIỆU LỰC** → đọc plan đó, tìm ngày hôm nay trong bảng lịch, **chạy tiếp Bước 3** cho các ngày chưa làm. Việc duy nhất được báo cáo thêm là **LỆCH**: ngày nào trong plan đã qua mà sổ cái không có bài. Đo bằng lệnh ở Bước 5.
- **KHÔNG có / HẾT HIỆU LỰC** → sinh plan mới từ Bước 1.

**Trần phạm vi: ĐÚNG 1 THÁNG (`--days` ≤ 31), không dài hơn.** Lý do đo được, không phải sở thích: feed `news.8syncdev.com/feed.xml` chỉ giữ **30 item** và cron đẩy bài mới **mỗi ngày** — nguyên liệu cho ngày thứ 32 hôm nay còn chưa tồn tại. Lên lịch 2–3 tháng là điền vào ô trống bằng bài tự nghĩ ra, tức là bịa. `harvest.mjs plan --days 40` chặn cứng ngay tại script.

---

## Bước 1 — Thu hoạch + xếp hạng nguyên liệu thật

```bash
node 8syncdev-org-skills/skills/post-all/scripts/harvest.mjs news --limit 30       # bảng xếp hạng điểm nóng
node 8syncdev-org-skills/skills/post-all/scripts/harvest.mjs ex   --limit 30       # bài tập coding
node 8syncdev-org-skills/skills/post-all/scripts/harvest.mjs yt   --limit 15       # video thật của @Dev8Sync = ĐÍCH
node 8syncdev-org-skills/skills/post-all/scripts/harvest.mjs news --limit 30 --json > /tmp/news.json
```

Nguồn (verify live 2026-08-02): RSS `news.8syncdev.com/feed.xml` **30 item** · sitemap `news.8syncdev.com/sitemap.xml` **148 loc / 60 permalink `/vi/articles/`** · API `coding.8syncdev.com/api/exercises` **1.000 bài** (477 easy · 325 medium · 174 hard · 24 expert) · RSS kênh `youtube.com/feeds/videos.xml?channel_id=UCMWzM6NOoVvr9484XBSJEjg` **15 video mới nhất** của `@Dev8Sync` (2.490 người đăng ký · 313 video).

### Điểm nóng của news = 3 thành phần, tất cả ĐO ĐƯỢC

| Thành phần | Thang | Nguồn của con số | Đo thật hay suy luận |
|---|---|---|---|
| **Độ mới** | 0–50, tuyến tính; bài > 30 ngày = **0** | `<pubDate>` trong feed | **ĐO THẬT** — trừ trực tiếp `Date.parse(pubDate)` |
| **Khớp chủ đề lõi** | 0–40 (trần), cộng theo **nhóm** từ khoá khớp trong `title + description` | 8 nhóm trong hằng số `BRAND_TOPICS` đầu `harvest.mjs`, mỗi nhóm ghi rõ lấy từ mục nào của `org-core/products.md` | **ĐO THẬT** phần đếm khớp; **SUY LUẬN** phần trọng số mỗi nhóm (12/10/8) — đó là thứ tự ưu tiên do người đặt theo phễu, không phải số liệu thị trường |
| **Đã đăng chưa** | **−60** nếu permalink đã có trong sổ cái | spawn `node post-ledger.js list --limit 1000000 --json`, gom `source_url` | **ĐO THẬT** — đọc `data/social-ledger.ndjson` |

Trọng số nhóm: `agent_ide` 12 · `career` 12 · `dsa` 10 · `learn` 10 · `perf` 8 · `security` 8 · `lang` 8 · `ai_ml` 8. Trần 40 để một bài "trúng đủ 8 nhóm" không nuốt hết bảng.

**−60 là cố ý nặng hơn mọi điểm cộng của một nhóm:** bài đã đăng phải rơi xuống đáy bảng, không phải "hơi tụt hạng". Đo thật hôm 02/08/2026: bài `the-kv-cache-survival-guide-…` **hạng 1 · 87.8 điểm**; sau khi ghi link đó vào sổ cái, cùng feed → **hạng 30 · 27.8 điểm** (`mới 49.8 · chủ đề 38 · sổ −60`).

### Hai thứ khác cũng do harvest lo, đừng làm tay
- **Permalink phải là link của MÌNH.** `<link>` trong feed là URL **nguồn gốc** (together.ai, medium.com…) — đăng cái đó là đẩy traffic cho người khác. `harvest.mjs` ghép feed × sitemap theo slug để ra `news.8syncdev.com/vi/articles/<slug>` (khớp 30/30 ngày 02/08/2026). Bài nào không ghép được thì in `⚠ CHƯA CÓ PERMALINK — không đăng` và **bị loại khỏi plan**.
- **YouTube là ĐÍCH, không phải nguồn.** `harvest.mjs` không lấy nội dung từ YouTube; nó lấy **link video thật** để mỗi ngày có một đường về `@Dev8Sync`, ghép theo số token trùng giữa tiêu đề video và (tiêu đề news + tên bài tập). Không ghép được thì xoay vòng — nên **không ngày nào rỗng**.

---

## Bước 2 — Plan 30 ngày (bàn giao `campaign-plan`)

```bash
node 8syncdev-org-skills/skills/post-all/scripts/harvest.mjs plan --days 30 --start $(date +%F) \
  > /tmp/plan-nguyen-lieu.txt
node 8syncdev-org-skills/skills/post-all/scripts/harvest.mjs plan --days 30 --start $(date +%F) --json \
  > /tmp/plan-nguyen-lieu.json
node -e "const p=require('/tmp/plan-nguyen-lieu.json');console.log(p.length+' ngày · thiếu YouTube: '+p.filter(d=>!d.youtube.url).length)"
```

`harvest.mjs plan` trả **bảng nguyên liệu**, không phải lịch: mỗi ngày 1 news (đã xếp hạng, chưa đăng, có permalink) + 1 bài tập coding + 1 video `@Dev8Sync` + `kind` theo tỉ lệ **4 share : 2 bài học : 1 product** (`mkt-playbook §2`, rải theo bản đồ ngày §4: T2–T5 `share` · T6–T7 `bài học` · CN `product`; §4 chia thô 3:2:2 nên T5 kéo về `share` để đúng 4:2:1 — tỉ lệ §2 là luật). Bậc bài tập theo vai trò phễu: `share`→easy · `bài học`→medium/hard · `product`→hard/expert. Không ngày nào trùng news, không ngày nào trùng bài tập.

Rồi **bàn giao sang `campaign-plan`** — đọc `8syncdev-org-skills/skills/campaign-plan/SKILL.md`, đưa nó `/tmp/plan-nguyen-lieu.json` làm "rổ nguyên liệu" (§1 mục 3, thay cho `news-ideas.js`) và yêu cầu nó làm đúng việc của nó: giờ vàng §4, phân công Hoàng Quyên / Đăng Khoa / Trường Thịnh (`operations.md §1`), cửa vào + CTA phụ (§1 ma trận), `post-ledger.js check` từng link.

Kết quả ghi ra **`8syncdev-org-skills/briefs/campaign-plan-<YYYY-MM-DD>.md`** (ngày bắt đầu). Hai thứ **post-all bắt buộc thêm** vào brief của campaign-plan:

1. Dòng thứ hai của file, đúng định dạng này (Bước 0 grep chính dòng này — sai định dạng là plan coi như hết hiệu lực):
   ```
   Hiệu lực: 2026-08-03 → 2026-09-01
   ```
2. Cột **`Đích YouTube`** trong bảng lịch, mỗi ngày một `watch?v=…` thật lấy từ `plan --json`. Không ngày nào để trống.

---

## Bước 3 — Soạn bài từng ngày (bàn giao `draft-content`)

Mỗi ngày, mỗi kênh **một bài riêng** — không rải nguyên văn sang nhiều nơi (FB phạt duplicate, đã dính thật). Đọc `8syncdev-org-skills/skills/draft-content/SKILL.md` rồi nạp đủ input §1 của nó từ dòng plan hôm đó:

```bash
# lấy nguyên liệu đúng của hôm nay từ plan đã sinh
node -e "
const p=require('/tmp/plan-nguyen-lieu.json'), t=new Date().toISOString().slice(0,10);
const d=p.find(x=>x.date===t) || p[0];
console.log(JSON.stringify(d,null,2));
"
# tiêu đề Unicode-bold (⛔ KHÔNG **markdown** — FB/IG/Threads hiện nguyên dấu sao)
node -e "
const { fmt } = require('./8syncdev-org-skills/skills/fb-group-growth/scripts/fb-groups.js');
console.log(fmt.h1('Học 2 năm vẫn tạch phỏng vấn vì mất gốc thuật toán'));
"
# ảnh card 1080 cho bài tập (Instagram bắt buộc ảnh vuông)
node -e "console.log(require('/tmp/plan-nguyen-lieu.json')[0].exercise.ogImage)"
# chống trùng TRƯỚC khi soạn xong (exit 3 = bị chặn, đổi bài)
node 8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js check \
  --platform facebook --account 8syncdev --url "<link news hôm nay>" --file /tmp/body.txt
```

Ràng buộc bắt buộc cho mọi bài (chi tiết ở `draft-content §2`/`§3`, không chép lại luật ở đây):
- **100% tiếng Việt.** Tiếng Anh chỉ được là đoạn phụ NGẮN đặt SAU. Tên riêng kỹ thuật (`Rust`, `Hamming distance`) giữ nguyên.
- Dòng đầu = tiêu đề **Unicode-bold** bằng `fmt.h1()`. Body **không có link nào**.
- **COMMENT #1 (đăng ngay + GHIM), thứ tự bắt buộc:** ① `youtube.com/watch?v=…` của `@Dev8Sync` → ② `news.8syncdev.com/vi/articles/<slug>` → ③ `coding.8syncdev.com/problem/<slug>`.
- Trong body có **1 câu cầu nối tự nhiên sang video** đó (giọng đồng nghiệp, không PR, ⛔ không "đăng ký kênh nhé").
- **Không câu comment** — không "comment để nhận link", không "inbox mình".
- Trần hashtag: Threads **1 tag/đoạn**, đoạn ≤500 ký tự · Instagram **5** · Facebook không trần (giữ 3–7) · LinkedIn **3–5**. Tag chết cấm dùng: `#vibecoding` `#devvietnam` `#lomcode` `#AIIDE`.
- Font chữ Việt trên ảnh: **`Bricolage`** / **`BigShoulders`** (đủ 42/42 nguyên âm 2 dấu). ⛔ `Outfit`, `GeistMono` cho chữ Việt (thiếu 34–35/42, dấu thanh nhảy lên dòng trên).
- Body **lưu ra FILE** rồi mới đăng — không gõ lại / escape `\uXXXX` tiếng Việt vào call (đã mất bài: `rất đọi` thay vì `rất đời`).

---

## Bước 4 — Đăng (bàn giao `org-social-ops`)

Dùng **`publish()`** của `social-multi.js`, không gọi trực tiếp `post*`: `publish()` chạy cổng chống trùng TRƯỚC và ghi sổ SAU, nên không cần nhớ hai bước.

```bash
bash 8syncdev-org-skills/skills/browser-profile-control/scripts/profile-browser.sh open linkedin "https://www.facebook.com/"
```
Rồi attach omp `browser` vào `http://127.0.0.1:9222` (`action: open`, `app.cdp_url`) và trong `{"action":"run"}`:
```js
const MOD = '<repo>/8syncdev-org-skills/skills/org-social-ops/scripts/social-multi.js';
delete require.cache[require.resolve(MOD)];          // sửa module giữa phiên thì phải xoá cache
const S = require(MOD);
const p = await S.page(browser);
const f = S.bodyFromBrief('<repo>/8syncdev-org-skills/briefs/social-posts-<date>.md');
return await S.publish(p, S.postThreads, { body: S.bodyFile(f.threads) },
  { platform: 'threads', account: '8syncdev', kind: 'share',
    sourceUrl: 'https://news.8syncdev.com/vi/articles/<slug>' });
```
Đăng xong: comment #1 (thứ tự YouTube → news → coding) rồi **ghim** comment đó. `verified=1` **chỉ** khi đã reload permalink và tìm thấy đúng đoạn text trên trang — "ô soạn rỗng" không phải bằng chứng.

---

## Bước 5 — Chốt sổ (kế hoạch vs thực tế)

```bash
node 8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js stats
```
Đối chiếu **số bài kế hoạch đã tới hạn** với **số bài `verified=1`**:
```bash
node -e "
const { execFileSync } = require('child_process');
const plan = require('/tmp/plan-nguyen-lieu.json');
const today = new Date().toISOString().slice(0,10);
const due = plan.filter(d => d.date <= today);
const s = JSON.parse(execFileSync(process.execPath,
  ['8syncdev-org-skills/skills/org-social-ops/scripts/post-ledger.js','stats'], {encoding:'utf8'}));
console.log('tới hạn: '+due.length+' ngày | đã ghi sổ: '+s.total+' | verified=1: '+s.verified+' | chưa verify: '+s.unverified);
console.log(s.verified >= due.length ? 'ĐỦ' : 'LỆCH '+(due.length - s.verified)+' bài — liệt kê ngày thiếu rồi báo founder, đừng đăng dồn bù');
"
```
Lệch thì **báo cáo**, không tự đăng bù dồn một lúc (dồn nhiều bài cùng khung giờ = FB coi là spam). Báo cáo sâu hơn: skill `performance-report`.

---

## Bảng "CẤM LÀM"

| Cấm | Vì sao (đã trả giá / đo được) |
|---|---|
| **Đăng lại bài đã có trong `data/social-ledger.ndjson`** | Loạt bài nhóm cũ đăng trùng nguyên văn (Niri/Astro/Airflow mỗi bài 2 lần) → Facebook phạt duplicate. Harvest trừ **−60**; `publish()` chặn cứng. Không `--force` để "cho nhanh". |
| **Plan dài hơn 1 tháng** | Feed chỉ giữ 30 item và đổi mỗi ngày → ngày thứ 32 không có nguyên liệu thật. `--days > 31` bị script chặn. |
| **Bịa số liệu traffic / lượt xem / conversion** | Analytics **CHƯA BẬT** (`products.md §KPI`: founder tự build trang analytics riêng, chờ xong mới có nguồn số). Số được phép nói: FB page 180 followers · nhóm FB + Zalo ~1.000 member **mỗi nhóm** (⛔ không gọi là "1.000 học viên") · YouTube 2.490 người đăng ký · 313 video · coding 1.000 bài · news 4.688 bài. |
| **Đăng khi chưa có ảnh card** | Doctrine "ảnh thay link": body không có link nên **ảnh là toàn bộ phần nhìn**. Instagram còn không render OG card → bắt buộc ảnh vuông 1080×1080. Không ảnh = không đăng. |
| **Để link trong body / câu comment** | Link trong body bị bóp reach và Admin Assist auto-decline; "comment để nhận link" là câu bị cấm thẳng. |
| **Bài không có đường về YouTube** | Doctrine founder 2026-08-02: `@Dev8Sync` là ĐÍCH của phễu (tài sản own lớn nhất: 313 video). Comment #1 phải mở đầu bằng link YouTube. |
| **Dùng handle `youtube.com/@8syncdev`** | Không tồn tại — trả **404** (đo live 02/08/2026). Kênh đúng duy nhất: `youtube.com/@Dev8Sync` (`UCMWzM6NOoVvr9484XBSJEjg`). |
| **Chép danh sách cụm cấm / luật copy vào file này hay brief** | Một luật một chỗ: `org-social-ops/references/prompt-library-mkt02.md` PHẦN 1. Bản sao là bản sẽ lệch. |
| **Sinh plan mới khi plan cũ còn hiệu lực** | Hai lịch chồng nhau → sổ cái chặn trùng liên tục, lịch mất tin cậy. Bước 0 là cổng, chạy trước mọi thứ. |
| **Tự đăng thứ founder chưa duyệt** | Plan + bài là **đề xuất**; founder (`Quin19FD`/`8syncdev`) duyệt rồi mới chạy Bước 4. |

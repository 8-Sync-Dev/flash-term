---
name: seo-audit
description: Audit SEO cho các site 8 Sync Dev đang chạy production — news.8syncdev.com, coding.8syncdev.com, course.8syncdev.com và landing 8syncdev.com. Kiểm bằng curl thật (không đoán) — thẻ OG/twitter card, robots meta, robots.txt, sitemap.xml, tiêu đề keyword-rich tiếng Việt, tình trạng index Google của bài public — rồi xuất báo cáo có lệnh reproduce + task sửa giao cho DEV. Dùng khi user nói "audit SEO", "sao link không hiện ảnh", "bài không lên Google", "kiểm og tag", "site có index không", "check sitemap".
---

# seo-audit — soi SEO site 8 Sync Dev bằng curl thật

Nguyên tắc: **mọi kết luận phải kèm lệnh chạy lại được**. Không có lệnh = không phải phát hiện, chỉ là cảm giác.
Đích SEO của org: kéo traffic free về `news` → `coding` → `course` (`org-core/mkt-playbook.md §1`), nên mỗi lỗi phải quy được ra "mất traffic ở đâu trong phễu".

## 0. Ground trước

- `org-core/mkt-playbook.md §4c` — bộ keyword long-tail VN ưu tiên + luật on-page (URL không dấu, H1 chứa keyword, 1 keyword chính + 2–3 phụ, ảnh có alt).
- `org-core/products.md` — site nào là gì, site nào cố ý chưa mở.
- `8syncdev-org-skills/briefs/dev-team-tasks.md` — mẫu task SEO đã giao DEV lần trước (OG cho coding); viết task mới theo đúng dạng đó.

## 1. Input

1. Danh sách URL cần soi. Mặc định 4 mặt trận: `https://news.8syncdev.com/` · `https://coding.8syncdev.com/` · `https://course.8syncdev.com/` · `https://8syncdev.com/vi`.
2. Ít nhất **1 URL trang chi tiết** mỗi site (`/articles/<slug>`, `/problem/<slug>`) — lỗi OG hầu như luôn nằm ở trang chi tiết, không phải trang chủ.
3. Keyword mục tiêu (lấy từ `mkt-playbook §4c`) nếu user không đưa.

## 2. Quy trình — chạy đúng các lệnh này

**2.1 Trạng thái + thẻ OG (mỗi URL):**
```bash
curl -s -o /tmp/p.html -w 'http=%{http_code} time=%{time_total}s bytes=%{size_download}\n' -L --max-time 20 "<url>"
grep -oE '<meta property="og:(title|description|image|url)" content="[^"]{0,90}' /tmp/p.html
grep -oE '<meta name="(robots|description|twitter:card)" content="[^"]*"' /tmp/p.html
grep -oE '<title>[^<]{0,90}' /tmp/p.html
```

**2.2 Kiểm bằng đúng user-agent của Facebook** (crawler thấy khác trình duyệt):
```bash
curl -s -A 'facebookexternalhit/1.1' -L --max-time 20 "<url>" | grep -oE '<meta property="og:image" content="[^"]*"'
```
Không ra dòng nào ⇒ share lên FB sẽ ra card trắng. Đây chính là bug đã dính ở `coding` (xem §5).

**2.3 robots.txt + sitemap:**
```bash
for p in robots.txt sitemap.xml; do printf '%s -> ' "$p"; curl -s -o /dev/null -w '%{http_code}\n' -L --max-time 15 "<origin>/$p"; done
curl -s -L --max-time 20 "<origin>/sitemap.xml" | grep -c '<loc>'
```

**2.4 Index Google cho bài public:**
```bash
curl -s -L "<origin>/sitemap.xml" | grep -oE '<loc>[^<]+</loc>' | sed 's/<[^>]*>//g' | head -20
```
Với từng URL nghi vấn, tra thủ công `site:<url>` trên Google rồi ghi kết quả (có/không) vào báo cáo — **ghi rõ là kiểm thủ công, ngày nào**, không tự nhận là số đo tự động.

**2.5 Tiêu đề keyword-rich tiếng Việt:** với mỗi `<title>` và `og:title` thu được, đối chiếu `mkt-playbook §4c`:
- tiêu đề có **tiếng Việt** không? (bài news giữ title gốc tiếng Anh = mất toàn bộ long-tail VN)
- có chứa ≥1 keyword ưu tiên ("học lập trình từ con số 0", "luyện thuật toán DSA tiếng Việt", "DSA cho phỏng vấn", "lộ trình học lập trình 2026", "học code cho người mất gốc"…)?
- URL không dấu, gạch ngang, chứa keyword?

**2.6 og:image có thuộc domain mình không:**
```bash
curl -s -L "<url>" | grep -oE '<meta property="og:image" content="[^"]*"'
```
Ảnh trỏ sang CDN bên thứ ba = share bài của mình nhưng quảng cáo hình của người khác, và mất kiểm soát khi họ đổi ảnh.

**2.7** Xuất báo cáo `8syncdev-org-skills/briefs/seo-audit-<YYYY-MM-DD>.md` theo khung §3, rồi tự chấm §4.

## 3. Khung output

```markdown
# SEO Audit — <site(s)> · <YYYY-MM-DD>
Cách kiểm: curl trực tiếp, mọi dòng dưới đây có lệnh reproduce. Keyword đối chiếu: mkt-playbook §4c.

## Bảng trạng thái
| URL | HTTP | og:title | og:image | robots meta | title tiếng Việt? | keyword §4c |
|---|---|---|---|---|---|---|

## Phát hiện (xếp theo thiệt hại traffic)
### [P0] <tên lỗi>
- **Triệu chứng:** …
- **Lệnh chứng minh:** `curl …`
- **Kết quả thật:** <dán nguyên dòng output>
- **Mất gì trong phễu:** <ví dụ: link news share lên FB không kéo được click vì title tiếng Anh>
- **Sửa ở đâu:** <file/route cụ thể trong products/8syncdev-pro-v2>

## Task giao DEV
| # | Việc | File/route | Acceptance (lệnh verify) |

## Đã kiểm và ĐẠT (đừng sửa)
- …
```

## 4. Checklist tự chấm

- [ ] Mỗi phát hiện có **lệnh curl** + **output nguyên văn** kèm theo?
- [ ] Đã soi cả trang chủ **và** trang chi tiết (`/articles/<slug>`, `/problem/<slug>`)?
- [ ] Đã thử user-agent `facebookexternalhit/1.1`, không chỉ curl mặc định?
- [ ] Đã kiểm `robots.txt` + `sitemap.xml` trả 200 và đếm `<loc>`?
- [ ] Đã đối chiếu title với keyword `mkt-playbook §4c`, không chỉ nói "title chưa tối ưu"?
- [ ] Đã tách rõ **kiểm tự động (curl)** với **kiểm thủ công (`site:` trên Google)**?
- [ ] Mỗi task giao DEV có acceptance là **một lệnh chạy được**, không phải mô tả cảm tính?
- [ ] Có mục "đã kiểm và ĐẠT" để lần sau không audit lại chỗ đã tốt?

## 5. Trạng thái đã verify 02/08/2026 (mốc để so lần sau)

- ✅ `news.8syncdev.com` — 200 · `og:image = /images/og-default.png` · `robots: index, follow` · `robots.txt` + `sitemap.xml` đều 200, sitemap có `hreflang` vi/en.
- ✅ `coding.8syncdev.com` — 200 · có `og:image` (`/opengraph-image`), **trang chi tiết cũng có** (`/problem/<slug>/opengraph-image`) ⇒ bug card trắng ghi trong `briefs/dev-team-tasks.md` **đã được sửa**, đừng báo lại.
- ⚠ **`news.8syncdev.com/articles/<slug>` — `og:title` vẫn là TIÊU ĐỀ TIẾNG ANH gốc**, `og:image` trỏ `media.daily.dev` (CDN bên thứ ba). Site đã có `viSummary` tiếng Việt nhưng không dùng cho thẻ OG ⇒ share lên FB hiện tiêu đề tiếng Anh, trái doctrine "100% tiếng Việt" và mất toàn bộ long-tail VN §4c. **Đây là P0 hiện tại.**
- ⚠ `course.8syncdev.com` — 200, **không còn thẻ `robots` noindex** trong HTML; ghi chú "hiện `noindex,nofollow`" ở `products.md §3` đã CŨ. Xác nhận với founder rồi cập nhật `products.md`.
- ⚠ `8syncdev.com/vi` — `<title>` và `og:title` đang là **"8SyncX · Hệ sinh thái Đào tạo Kỹ sư Thực chiến"**, trong khi `org-core/brand.md` chốt tên brand là **"8 Sync Dev"**. Lệch tên brand trên chính landing = loãng thương hiệu + loãng keyword. Hỏi founder xem đây là đổi tên có chủ đích hay drift.

## 6. Đừng làm gì

- **Đừng kết luận bằng mắt trên trình duyệt.** Trình duyệt và crawler thấy khác nhau — luôn curl với UA của FB.
- **Đừng báo lại bug đã sửa.** OG của `coding` đã xong (verify 02/08/2026); kiểm trước khi mở task.
- **Đừng tự nhận đã kiểm Google index** khi mới chỉ curl. `site:` là thao tác thủ công, ghi rõ như vậy.
- **Đừng đề xuất nhồi hashtag/keyword.** `mkt-playbook §4c`: 1 keyword chính + 2–3 phụ mỗi bài; nhồi tag phản tác dụng trên cả FB lẫn Google.
- **Đừng tự sửa code sản phẩm.** Site nằm trong submodule `products/8syncdev-pro-v2` — skill này **xuất task cho DEV**, founder review (`org-social-ops §7`).
- **Đừng bịa số traffic.** Org chưa bật Vercel Web Analytics, founder đang tự build trang analytics (`products.md §KPI`) — chưa có nguồn số thì ghi "chưa đo được".

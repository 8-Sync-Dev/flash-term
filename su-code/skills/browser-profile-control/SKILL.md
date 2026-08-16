---
name: browser-profile-control
description: BASE skill for all real-browser control — open a persistent, logged-in Chromium profile saved in this repo (data/.cache/<name>-profile) as a VISIBLE window with CDP, attach the omp browser tool to it, and drive it with validated control patterns (lazy-list scroll-scrape, login check, writing bulk data to disk from browser code). Use whenever a task needs an authenticated site (LinkedIn, GitHub, any SaaS), needs the USER to log in for the agent, or needs reliable scraping of JS-heavy pages. Other skills (remote-job-scan, linkedin-cv-sync) build on this.
---

# browser-profile-control

Điều khiển browser THẬT trên profile đăng-nhập-sẵn lưu trong repo. User login 1 lần,
mọi phiên agent sau dùng lại session. Validated 2026-07-17 (LinkedIn scrape 11 truy vấn,
275 jobs; GitHub settings).

## Kiến trúc

```
scripts/profile-browser.sh open <name> [url]     # cửa sổ Chromium HIỆN HÌNH + CDP port riêng
        └─ profile bền: data/.cache/<name>-profile   (gitignored — KHÔNG theo git sang máy khác)
omp browser tool: {"action":"open","name":"x","app":{"cdp_url":"http://127.0.0.1:<port>"}}
        └─ từ đây control bằng {"action":"run","code":"..."} — page/tab/browser đầy đủ
```

Port: `linkedin`/`default` → 9222 (tương thích linkedin-cv-sync); tên khác → 9223+hash%100
(in ra khi `open`). Nhiều profile chạy song song được.

## Quy trình chuẩn

1. `bash writter-ai/skills/browser-profile-control/scripts/profile-browser.sh open <name> <url>`
   — cửa sổ hiện lên máy user. Cần login? Bảo user login TRÊN CỬA SỔ ĐÓ rồi báo lại
   (đây là điểm mấu chốt: browser tool spawn mặc định là HEADLESS ẨN, user không gõ được).
2. Attach: browser tool `open` với `app.cdp_url` như trên. KHÔNG spawn app.path khi launcher
   đang chạy — profile lock làm CDP không lên.
3. Control qua `run`. Xong việc KHÔNG cần đóng — cửa sổ để user dùng tiếp; session tự lưu.

## Control patterns đã validated (nhúng vào `code` của action:"run")

- **Check đăng nhập** (LinkedIn): `!!document.querySelector('img.global-nav__me-photo, .global-nav__me')`.
- **Lazy-list scroll-scrape** — chuẩn cho MỌI danh sách ảo (LinkedIn/FB/Twitter):
  tìm ancestor cuộn được của item đầu (`while (el.scrollHeight <= el.clientHeight+10) el=el.parentElement`),
  `scrollBy(0,800)` lặp, dừng khi item-count đứng yên qua ~5 vòng. Bản đầy đủ:
  `../remote-job-scan/scripts/linkedin-scrape.snippet.js`.
- **Đưa data lớn ra ngoài KHÔNG qua context**: code của `run` có full Node —
  `require('fs').writeFileSync('/tmp/x.json', JSON.stringify(data))` rồi đọc file bằng tool khác.
  ĐỪNG return mảng lớn (biến scope KHÔNG persist giữa các lần `run` — return xong là mất).
- **Điều hướng**: `tab.goto(url,{waitUntil:'domcontentloaded'})` + sleep 3–4s cho SPA render;
  selector LinkedIn hiện hành: card `li[data-occludable-job-id]`, title `.artdeco-entity-lockup__title`,
  company `.artdeco-entity-lockup__subtitle`, link `a[href*="/jobs/view/"]` (strip query).

## Gotchas (đã đốt tay)

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `Timed out waiting for CDP endpoint` | Chromium ≥136 chặn CDP trên profile mặc định, HOẶC instance cũ giữ profile lock | Launcher đã dùng user-data-dir riêng + tự `pkill` instance cũ trước khi mở |
| `Attempted to use detached Frame` | Tab cũ chết sau idle dài / browser bị kill | `open` lại tab mới qua cdp_url (đừng cố `run` tiếp) |
| Spawn ra `chrome://new-tab-page` thay vì URL | app.path spawn không nhận URL | `run` → `tab.goto(...)` ngay sau khi mở |
| User không login được | browser tool spawn headless ẩn | LUÔN mở cửa sổ bằng launcher, tool chỉ ATTACH |
| Session mất trên máy mới | profile gitignored, không theo repo | User login lại 1 lần trên máy mới |

## An toàn

- Session của USER: không thao tác phá hủy (đăng bài, xóa, đổi mật khẩu) khi chưa được yêu cầu rõ.
- Scrape có nhịp (sleep giữa truy vấn, ≤~25 kết quả/trang, vài chục trang/phiên) — tránh rate-limit/khóa.
- `clear <name>` khi user muốn logout sạch.

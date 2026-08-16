---
name: linkedin-cv-sync
description: Sync the rendered CV (cv_data.yaml + data/research.json) onto the user's LinkedIn profile by driving a real Chromium over CDP with the omp browser tool. Use when the user asks to update/push/sync CV or profile details to LinkedIn, fix LinkedIn experience/publications/skills, or reopen the saved LinkedIn browser session. Covers persistent cookie profile, validated form URLs, and every field quirk.
---

# linkedin-cv-sync

Push CV content onto LinkedIn *defensibly*: every number comes from `data/research.json`,
every section is verified live after saving. Validated end-to-end on 2026-07-07
(profile `linkedin.com/in/8syncdev`, Chromium 150, LinkedIn UI in Vietnamese).

## 0. STOP gates

- Content source is **`cv_data.yaml`** (+ numbers in `data/research.json`). Missing/stale →
  run the defensible-cv pipeline first. NEVER invent numbers on LinkedIn.
- The browser profile holds **live LinkedIn auth cookies**. It lives at
  `data/.cache/linkedin-profile/` (gitignored via `data/.cache/`). NEVER commit it,
  never copy it out of the repo.

## 1. Browser lifecycle (one script)

```bash
su-code/skills/linkedin-cv-sync/scripts/linkedin-browser.sh open    # launch + CDP :9222
su-code/skills/linkedin-cv-sync/scripts/linkedin-browser.sh status  # CDP up? profile size?
su-code/skills/linkedin-cv-sync/scripts/linkedin-browser.sh clear   # kill + wipe session
```

- `open` uses `setsid -f` → survives tool timeouts; never launch chromium via a
  time-limited async job (a 3600s timeout WILL kill the window).
- Chromium ≥136 blocks CDP on the default profile → dedicated `--user-data-dir` is required.
- First run ever (or after `clear`): the user logs in manually (incl. 2FA), then work starts.
  Session persists across reopens after that.
- Attach from the agent: `browser` tool, `action: open`, `app: {"cdp_url": "http://127.0.0.1:9222"}`.
  If a previous omp tab exists, `close` it first, then re-`open`.

## 2. Direct form URLs (validated map)

| Section | URL |
|---|---|
| Intro (headline/industry/position) | `/in/<id>/edit/intro/` |
| New position | `/in/<id>/edit/forms/position/new/` |
| Edit position | `/in/<id>/details/experience/` → link `aria-label` contains `Chỉnh sửa` + company → `/details/experience/edit/forms/<urn>/` |
| New education | `/in/<id>/edit/forms/education/new/` |
| New publication | `/in/<id>/edit/forms/publication/new/` |
| New project | `/in/<id>/edit/forms/project/new/` |
| New skill | `/in/<id>/skills/edit/forms/new/` (NOT `/edit/forms/skill/`) |
| About (summary) | profile → "Thêm phần" → "Thêm tóm tắt", or `/in/<id>/edit/forms/summary/new/?profileFormEntryPoint=GUIDANCE_CARD` |
| Contact info | `/in/<id>/overlay/contact-info` → button "Chỉnh sửa thông tin liên hệ" → "Thêm trang web" |

`404 "Trang này không tồn tại"` → the guessed URL is wrong; go through the profile page buttons.

## 3. Field quirks (each cost real debugging — read before typing)

- **UI language**: button/label matching is text-based and this account renders vi_VN
  (`Lưu` = Save, `Thêm` = Add, `Tôi hiện đang làm việc ở vai trò này` = currently working).
  Re-derive strings from the DOM if the UI is English.
- **Rich-text fields (About, position description)** are TipTap/**ProseMirror**
  `div[contenteditable=true]` (About: `div.ProseMirror`, often OUTSIDE any `[role=dialog]`;
  position form: `div[aria-label^="Mô tả"]`). Type with **`elementHandle.type()`** —
  `page.keyboard.type()` gets swallowed (only non-ASCII like `—•` lands). `textarea` may
  not exist at all; probe `textarea, [contenteditable=true]` first.
- **Native `<select>`** (months/years/employment type): set `el.value` + dispatch
  `change` with `bubbles: true`. Option text is localized (`Tháng 8`, `Thực tập`).
- **Typeahead** (company/school/location/skill): `elementHandle.type()` the query, wait
  ~2s, `ArrowDown` + `Enter` to take the top canonical suggestion (gives the real company
  page + logo). Verify what got bound by reading the input's `value` after.
- **"Currently working" checkbox** hides the end-date selects; unchecking re-renders the
  form and **shifts all select indices** → re-run `page.$$('select')` after ANY toggle.
  Checkboxes are styled: labels sit in ancestor text, not `<label for>` — find them by
  walking `parentElement` innerText. Beware sibling checkboxes "Kết thúc vị trí hiện tại
  kể từ bây giờ - <role>" (they END other current roles — leave alone).
- **Publication date** is a text input demanding `dd/mm/yyyy`; bare `2024` is rejected.
  Fetch the true date from the OJS article page `meta[name=DC.Date.issued]` (`read` the URL).
- **Notify network switch** (first checkbox, context `Tắt/Bật`) — keep OFF while
  backfilling to avoid spamming the feed; optionally ON for the final flagship role.
- **Save**: click button with exact text `Lưu`; success = URL leaves the form (often to
  `/edit/forms/next-action/...` or the profile) and no `.artdeco-inline-feedback--error`.
- **`ariaSnapshot` depth >40 times out (30s)** on profile pages → use `tab.evaluate` +
  direct DOM queries instead.
- Skills: type the skill, take LinkedIn's canonical suggestion (e.g. `React` →
  `React.js`, `Docker` → `Docker Products`).
- **Feed posts (composer)** — validated 2026-07-15: open via `Bắt đầu bài đăng`; editor is
  `div.ProseMirror` in `/sharing/compose`. For long text use
  `document.execCommand('insertText')` after `focus()` — `elementHandle.type()` stalls/times
  out on 1k+ chars. **Add media FIRST, text second**: opening the media editor
  ("Trình chỉnh sửa" → "Ảnh") can silently reset the draft text. The media editor's
  `input[type=file]` renders lazily (poll up to ~15s); after `Tiếp theo`, re-check
  `img[src^="blob:"]` > 0 AND editor text length BEFORE clicking `Đăng bài` — a post
  published without images CANNOT gain them by editing (delete `Xóa bài đăng` + repost).
  Post edit uses a **Quill** `.ql-editor` (not ProseMirror); same execCommand trick works.
- **URL auto-shortening**: on save LinkedIn rewrites full URLs in post bodies to
  `lnkd.in/<hash>` — to swap a link later, match `https://lnkd.in/\S+` (near its anchor
  text), not the original URL. Verify link targets by context line, never by URL equality.
- **Post-menu items** (`Sửa bài đăng`/`Xóa bài đăng`) mount only after a REAL mouse click
  (`page.mouse.click` at button coords) — JS `el.click()` opens an empty dropdown. Find the
  item by `textContent === 'Sửa bài đăng'` on ALL elements (pick smallest rect), then mouse-click
  its coords. `Escape` closes the whole composer, not just an overlay — never use it to
  dismiss sub-dialogs. Feed's standalone `Ảnh` button opens the media editor directly; its
  "Chọn tập tin" spinner can exceed 15s before `input[type=file]` mounts (poll ~25s).
- **Intro form** (`/edit/intro/`): name fields are React inputs — set via native value
  setter + `input` event; `Tên khác` = nickname (renders as `Tú (Kevin) …`). The headline
  is a `contenteditable` div (NOT a textarea) — find it by current text, edit via execCommand.
  The **`Vị trí*` select** picks which current position shows in the TOP CARD (company +
  logo next to the name) — brand-first means selecting the founder position, not the
  employer. Set via `s.selectedIndex = i` + `dispatchEvent(new Event('change', {bubbles:true}))`.
- **Edit modal has NO add-media** — adding an image to a published post requires
  delete + repost (reactions are lost). Text-only edits (hashtags, typos) are safe in place.
- **Old posts unreachable via activity page** (pagination sticks at ~5 even with real
  clicks on "Hiển thị thêm kết quả"): open `/feed/?highlightedUpdateUrn=urn%3Ali%3Aactivity%3A<id>`
  — the post renders at the top of the FEED page where the control-menu dropdown actually
  renders its items. On `/feed/update/<urn>/` pages the dropdown opens but stays EMPTY.
- **The edit modal's Lưu button sits OUTSIDE `[role=dialog]`** on the feed page — query
  buttons globally.
- **Company page creation is gated** by Persona identity verification (QR → LinkedIn
  mobile app → ID document). Human-only; script up to the QR screen, then hand off.

## 4. Verify (mandatory before claiming done)

Main profile **virtualizes sections** — innerText checks on `/in/<id>/` miss content below
the fold. Verify on the detail pages instead:

```
/in/<id>/details/experience|education|publications|projects|skills/
```

`document.body.innerText.includes(...)` per expected string, then one screenshot of the
top card + key sections for the user. Cross-check dates/numbers against `cv_data.yaml`.

## 5. Consistency rule

LinkedIn is a **mirror** of the CV. Any factual correction (dates, roles) goes into
`cv_data.yaml` too, then re-render (`uv run --with "rendercv[full]>=2.8" rendercv render
cv_data.yaml`) and confirm the PDF stays 2 pages. Update `CHANGELOG.md` (Unreleased).

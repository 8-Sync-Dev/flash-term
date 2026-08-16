---
name: feature-ship
description: "Use when a feature just passed its smoke test and must be shipped: update changelog, roadmap, web pages, release notes, and the 8sync spine mechanically. Also use at release time to move Unreleased into a versioned block and sync zus-web copy."
---

# Feature Ship

Checklist cơ khí để ship 1 feature — chạy TUẦN TỰ, không skip bước. Mục tiêu: mọi feature
đã ship đều để lại dấu vết nhất quán ở CHANGELOG, roadmap, web và spine 8sync.

## Gate (bắt buộc trước mọi bước)

- [ ] **Smoke-test proof có thật**: feature đã chạy được end-to-end (command output, screenshot,
  hoặc E2E log). Chưa có proof → DỪNG, quay lại làm feature. Không ship theo cảm giác.

## Checklist ship (mỗi feature)

1. **`CHANGELOG.md` — mục `## [Unreleased]`**: thêm entry dạng
   `### <area> — <tóm tắt> (YYYY-MM-DD)` + bullet chi tiết (tiếng Việt, ghi rõ root cause/fix
   nếu là bug). Area = tên vùng code (vd `hub`, `env-studio`).
2. **`docs/roadmap.md`**: flip dòng tương ứng `building` → `shipped` + điền `Phiên bản`
   (chỉ khi release, xem dưới — trước release giữ `building`), hoặc thêm dòng mới nếu feature
   chưa có trong bảng. `id` kebab-case, khớp key i18n `roadmap.items.<id>` trong zus-web.
   Thêm dòng mới ⇒ thêm `roadmap.items.<id>.title|note` vào CẢ `zus-web/src/i18n/messages/vi.json`
   và `en.json`.
3. **Sync web**: `node scripts/sync-web-content.mjs` — PHẢI exit 0. Exit 1 = thiếu key i18n
   roadmap → bổ sung rồi chạy lại. Script ghi đè `zus-web/src/features/roadmap/content.ts`
   (file generated — không sửa tay).
4. **Smoke lại sau sync**: `cd zus-web && pnpm build` xanh (route `/vi/roadmap` xuất hiện
   trong build output).

## Release-only (khi cắt bản `vX.Y.Z`)

5. Move toàn bộ `## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD` trong `CHANGELOG.md`.
6. Flip các dòng roadmap của bản này sang `shipped` + `vX.Y.Z`, chạy lại bước 3–4.
7. **zus-web changelog copy (hand-curated)**: thêm entry vào
   `zus-web/src/features/changelog/content.ts` (`CHANGELOG_ENTRIES`) + copy vi/en đầy đủ
   `changelog.entries.<id>.*` trong `vi.json`/`en.json`. Sync script chỉ WARN khi thiếu —
   warning phải về 0 trước khi tag.
8. **Tag checklist**: commit trong submodule `zus-web` TRƯỚC (nó deploy Vercel riêng),
   rồi mới bump pointer submodule ở repo cha; sau đó tag/release theo
   `su-code/skills/git-workflow-and-versioning/SKILL.md`.

## Spine 8sync

9. Cập nhật `su-code/STATE.md` (phase boundary) + ghi bài học vào `su-code/KNOWLEDGE.md`
   theo quy tắc 8sync có sẵn trong `AGENTS.md` — tham chiếu, không lặp lại nội dung ở đây.

## Lưu ý

- Dòng skill này trong root `AGENTS.md` nằm trong block `8sync:skills` do 8sync quản lý —
  nếu harness regenerate block làm mất dòng `feature-ship`, thêm lại (thư mục skill này là
  source of truth).
- KHÔNG sửa `zus-web/src/features/roadmap/content.ts` bằng tay; sửa `docs/roadmap.md` rồi sync.

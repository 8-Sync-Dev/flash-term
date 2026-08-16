---
name: review-status
description: "Mandatory pre-flight gate BEFORE review-mr. Checks MR hygiene AS-IS (never fix member code). If any blocker fails → REJECT + PDF, member must fix and resubmit. Only pass to review-mr if hygiene is clean."
---

# review-status — Pre-flight Gate BEFORE review-mr

> **INVARIABLE RULE:** Bạn KHÔNG ĐƯỢC fix code của member. Review MR **ĐÚNG NHƯ member nộp**. Sai → REJECT + PDF. Member tự sửa + resubmit.

## Khi nào dùng

TRƯỚC KHI mở `review-mr/SKILL.md`. Mọi MR từ member (không phải Lead push trực tiếp) phải pass `review-status` trước. Nếu fail → không tiến hành review sâu, không deploy, không fix.

## Pipeline

```
MR tạo/push ──► review-status (pre-flight, ~30s)
                   │
                   ├── BLOCKER FAIL ──► REJECT + PDF feedback ──► STOP (member fixes)
                   │
                   └── ALL HYGIENE PASS ──► review-mr (full deep review)
                                              │
                                              ├── FAIL ──► REJECT + PDF ──► STOP
                                              └── PASS ──► recommend ACCEPT to Lead
```

## Gate 1: Hygiene AS-IS (KHÔNG fix)

Kiểm tra từng mục. **Nếu BẤT KỲ mục nào fail → REJECT ngay.** Không proceed sang review-mr.

### H1 — `be/encore.app` id non-empty
```bash
ID=$(python3 -c "import json; print(json.load(open('be/encore.app')).get('id',''))")
[ -z "$ID" ] && REJECT "encore.app id is empty — git checkout origin/master -- be/encore.app"
```

### H2 — Không lẫn personal config
```bash
git diff --name-only origin/master...HEAD | grep -iE 'CLAUDE\.md|^AGENTS\.md$|KNOWLEDGE\.md|\.omp/|\.env\.local|STATE\.md'
# Match = REJECT
```

### H3 — Không chứa secret
```bash
git diff origin/master...HEAD | grep -iE 'sk-|ak_live_|ghp_|ena_|password.*[:=].*["'\'']'
# Match = REJECT
```

### H4 — Migration prefix unique
```bash
for dir in be/*/migrations be/*/migrations_*; do
  ls "$dir"/*.up.sql | xargs -I{} basename {} | grep -oE '^[0-9]+' | sort -n | uniq -d
  # Duplicate = REJECT
done
```

### H5 — MR scope reasonable
```bash
LINES=$(git diff --shortstat origin/master...HEAD -- '*.go' | grep -oE '[0-9]+ insertion')
# > 500 = WARN (suggest split MR, don't auto-reject but flag)
```

## Gate 2: Build AS-IS

### B1 — go build
```bash
cd be && go build ./...
# Fail = REJECT
```

## Quy tắc bất biến (DÁN VÀO TƯỞNG)

1. **KHÔNG fix code member.** Nếu `encore.app` id rỗng, KHÔNG `git checkout` sửa. REJECT + hướng dẫn member tự sửa.
2. **KHÔNG deploy MR fail lên kufi.** Chỉ deploy khi build + test pass.
3. **Review đúng như member nộp.** Không thêm/bớt file, không sửa typo, không format.
4. **Mọi REJECT kèm PDF.** PDF = actionable feedback (file:dòng + lệnh fix + lý do).
5. **Member tự sửa + resubmit.** Reviewer chỉ review lại bản mới.
6. **KHÔNG BAO GIỜ xóa source branch của MR.** Đóng MR = merge branch VÀO master qua GitLab merge button (chính thức), KHÔNG phải `git push :branch`. Xóa branch = mất lịch sử member, vi phạm quy trình audit.
7. **Chỉ merge MR khi ĐỦ 4 điều kiện:** (a) MR đã fix xong hết blocker, (b) merge êm — không lỗi build/compile, (c) đã test RẤT KỸ trên kufi DEV, (d) Sếp approved deploy. Thiếu 1 = STOP.
8. **PROD VPS = nguy hiểm.** Chỉ trace/check (đọc log, chat_trace, curl endpoint), KHÔNG code/sửa trực tiếp trên VPS. Mọi fix phải đi qua: code → kufi test → Sếp approve → mới SCP VPS.

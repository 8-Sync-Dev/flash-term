# 🚀 gsd-pi v2.76 — Hướng dẫn bản đang xài (tiếng Việt)

> **Bản ưu tiên:** `gsd-pi` v2.76.x (dòng GSD-2 mới nhất trên npm, series 2.7x).
> Tài liệu này viết cho bản **bạn đang chạy ngay bây giờ** — gõ lệnh copy-paste là chạy được.

Kiểm tra bản đang dùng:
```powershell
gsd --version          # phải là 2.76.x
npm view gsd-pi version # bản npm mới nhất
8sync gsd status        # provider + routing hiện tại
```

---

## ⭐ Công dụng nổi bật CỦA BẢN 2.7x (mới so với 2.0)

Không phải lý thuyết GSD chung — đây là **những thứ chỉ bản 2.7x mới có**:

### 1. 🧠 Persistent Agent Memory (5 phase đã ship)
Agent có **bộ não lâu dài** xuyên session.
```powershell
# Trong session GSD, agent tự gọi các tool này:
#   capture_thought   — lưu quyết định/pattern/gotcha
#   memory_query      — tìm lại trước khi plan
#   gsd_graph         — duyệt đồ thị liên kết
```
- **Scope/tag:** nhớ theo project / milestone / slice.
- **Hybrid retrieval:** keyword + semantic search.
- **Knowledge graph:** planner tự lấy context từ memory cũ.
- **Maintenance:** cap cascade, decay metrics, export/import.

👉 Dự án lớn = đừng mất memory. Commit `.gsd/` đều đặn.

### 2. 🪜 Sketch-then-Refine Planning (Phase 1)
GSD giờ **phác sketch nhẹ trước**, rồi mới lock plan chi tiết. Bớt phí token khi plan sai ngay từ đầu.

### 3. 🚨 Mid-Execution Escalation (Phase 2)
Task đang chạy phát hiện độ phức tạp vượt dự kiến → **tự escalate**, rollback write nếu fail. Không cần bạn canh.

### 4. 🗣 `/gsd language` — Ngôn ngữ cố định
```
/gsd language vi
```
Set 1 lần, mọi output (plan, summary, commit message) giữ nguyên ngôn ngữ cho cả project.

### 5. 📰 `/gsd changelog` — Release notes tóm tắt bằng LLM
```
/gsd changelog
```
Xem đổi gì giữa các bản gsd-pi **ngay trong TUI**, không cần mở GitHub.

### 6. 🎯 DB-Authoritative Milestone Completeness
Trạng thái milestone giờ **đọc từ SQLite** (không còn từ file markers). Không còn false "merge" khi `complete-milestone` fail.

### 7. 🧯 Crash Recovery siêu cứng
- Lock file track unit đang chạy.
- Session chết → `/gsd auto` lần sau tự **synthesize recovery briefing** từ mọi tool call đã ghi disk → resume nguyên trạng.
- Headless crash → auto restart exponential backoff (mặc định 3 lần).
- Parallel orchestrator persist PID + liveness → multi-worker sống sót crash.

### 8. 📡 Provider Error Recovery thông minh
- Lỗi transient (rate limit, 500/503, overloaded) → auto-resume sau delay.
- Lỗi vĩnh viễn (auth, billing) → pause chờ bạn.
- Fallback chain retry network trước khi đổi model.

### 9. 🔁 Stuck Detection bằng sliding window
Phát hiện lặp dispatch (cả multi-unit cycle) → retry 1 lần với **deep diagnostic** trước khi escalate.

### 10. 💰 Flat-rate Provider Detection (mở rộng)
Detect **custom + externalCli provider** (ví dụ Claude Code subscription) → auto route qua CLI khỏi tính token tiền.

### 11. 🪟 Claude Code native Windows lookup
Không còn phải symlink `claude.cmd` thủ công — bản 2.7x tự tìm đúng binary Windows.

### 12. 🧰 RTK Output Compression
Binary quản lý sẵn, nén stdout của `bash`, `async_bash`, `bg_shell`, verification. Giảm token 40-70% cho log dài.
```powershell
# Tắt nếu cần debug:
$env:GSD_RTK_DISABLED = "1"
```

### 13. 🔄 Milestone merge an toàn
- Clean up `MERGE_HEAD` trên mọi error path.
- Auto-mode không false merge khi phase bị block + thiếu reassessment.

### 14. 🧪 `/gsd doctor` tự heal
Doctor giờ **tự chữa** dispatch fixable warnings, heal legacy task arrays / evidence rows, restore STATE.md.

---

## ⚡ Commands NÊN THUỘC (bản 2.7x)

### Cài + setup lần đầu
```powershell
npm install -g gsd-pi                 # hoặc: npm i -g gsd-pi@2.76
8sync gsd setup --auto                # auto-detect provider tốt nhất + apply PREFERENCES.md
8sync gsd fix                         # repair nhanh ~/.gsd/agent nếu có gì trục trặc
```

### Tạo + chạy milestone
```powershell
gsd                                   # mở TUI (step mode mặc định)
# Trong TUI:
/gsd language vi                      # (1 lần) khóa ngôn ngữ tiếng Việt
/gsd new-milestone                    # tạo M00x — paste spec.md vào
/gsd auto                             # chạy toàn bộ milestone, đi uống cafe
/gsd next                             # hoặc chạy từng unit một (an toàn hơn)
```

### Quan sát + debug
```powershell
/gsd query                            # snapshot JSON trạng thái (~50ms, không tốn LLM)
/gsd changelog                        # xem bản mới có gì
/gsd doctor                           # tự chẩn + tự heal
/gsd migrate                          # chuyển .planning/ (GSD v1) → .gsd/ (v2)
```

### Headless cho CI/cron
```powershell
# Chạy auto trong GitHub Actions / cron:
gsd headless --timeout 600000

# Tạo + chạy milestone end-to-end không TUI:
gsd headless new-milestone --context spec.md --auto

# Cron-friendly: 1 unit rồi thoát
gsd headless next

# Dashboard: đọc trạng thái kiểu JSON
gsd headless query                    # exit 0 done / 1 error / 2 blocked
```

### Wrapper 8sync (repo này)
```powershell
8sync gsd guide                       # mở file hướng dẫn này
8sync gsd setup --model codex         # preset stack theo brand
8sync gsd setup --pick                # fzf picker có status
8sync gsd status                      # auth/key/routing
8sync gsd keys                        # list provider
8sync gsd model add claude-opus-4-7   # thêm model không cần upgrade gsd-pi
8sync gsd fix --refresh               # refresh runtime local (không đụng global)
8sync gsd local                       # inspect .gsd/vendor/gsd-pi
```

---

## 🏗 Workflow cho dự án lớn (bản 2.7x)

```
1. npm i -g gsd-pi && 8sync gsd setup --auto
2. cd project && gsd
3. /gsd language vi              ← 1 lần duy nhất
4. /gsd new-milestone            ← paste spec
5. /gsd auto                     ← đi cafe
6. Escape để pause bất cứ lúc nào → /gsd auto resume
7. Khi xong milestone: /gsd changelog để xem gsd-pi có gì mới
```

**Terminal 2** mở song song: chỉnh ROADMAP.md, REQUIREMENTS.md — agent pick up ở phase boundary kế tiếp **không cần stop**.

**Git isolation:** set trong preferences
```yaml
git:
  isolation: worktree   # hoặc branch
```
→ mỗi milestone một branch `milestone/<MID>`, main luôn xanh.

**Verification bắt buộc:**
```yaml
verification_commands:
  - npm run lint
  - npm run typecheck
  - npm test
verification_auto_fix: true
verification_max_retries: 3
```
→ fail tự retry, pre-existing error chỉ warn (không block).

---

## 🧭 Pro tips để thành "chuyên dùng GSD" cho dự án lớn

1. **Model 2 tier:** planning = Opus/GPT-5 (mạnh), exec = Sonnet/Haiku (rẻ) → giảm 60-80% cost.
2. **Slice mỏng, vertical:** mỗi slice demo được độc lập → dễ rollback, dễ review.
3. **`/gsd query` trong dashboard** thay vì parse markdown — nhanh, không tốn LLM.
4. **Commit `.gsd/` sau mỗi session:** đó là memory dài hạn — mất nó = agent amnesia.
5. **Bật `capture_thought` liberal:** pattern, gotcha, decision đều nên lưu — memory retrieval của 2.7x rất tốt.
6. **`STATE.md` là single source of truth** — rối thì đọc file này, đừng hỏi agent.
7. **Headless trong CI:** exit code 0/1/2 cực rõ ràng, dễ wrap alert Slack.
8. **Đừng tắt RTK** trừ khi debug — log compression quý hơn bạn tưởng.
9. **`/gsd doctor` định kỳ** — tự heal nhanh hơn fix tay.
10. **Migrate từ v1?** `gsd migrate <path>` — giữ nguyên completion state.

---

## 🆘 Troubleshooting nhanh

| Lỗi | Fix |
|---|---|
| `experimental-strip-types` | Nâng Node lên ≥ 22 |
| `gsd` bị alias (oh-my-zsh) | `unalias gsd` trong `~/.zshrc` |
| `Version mismatch detected` | `gsd update` hoặc `npm i -g gsd-pi@latest` |
| Anthropic 401/bearer | `8sync gsd fix` (patch OAuth bearer-auth) |
| Hang trên piped stdin | Dùng `gsd headless` thay vì `gsd auto` |
| CLI không tìm thấy sau install | `echo 'export PATH="$(npm prefix -g)/bin:$PATH"'` |

---

## 🔗 Link chính thức

- npm: <https://www.npmjs.com/package/gsd-pi>
- GitHub: <https://github.com/gsd-build/gsd-2>
- Changelog: <https://github.com/gsd-build/gsd-2/blob/main/CHANGELOG.md>
- User guide: <https://github.com/gsd-build/gsd-2/tree/main/docs/user-docs>

Hoặc gõ ngay:
```powershell
8sync gsd guide      # mở file này
/gsd changelog       # trong TUI, xem diff release
```

> **Nhắc cuối:** GSD-2 là CLI TypeScript trên Pi SDK — không phải prompt framework. Nó tự clear context, inject đúng file lúc dispatch, quản git, track cost, detect stuck loop, recover crash. **Một lệnh. Đi chơi. Về có dự án chạy + git history sạch.**

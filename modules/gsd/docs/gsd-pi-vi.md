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

## 📚 Cookbook 2.76 — dùng từng feature mới ra sao

> **Nguyên tắc chung:** phần lớn tự chạy ngầm. Bạn chỉ cần nhớ vài command để **xem / bật / export**.

### 1. 🧠 Memory System (5 Phase đã ship — AUTO)

**Cái gì tự động:**
- Agent trong session **tự gọi** `capture_thought` khi gặp decision/pattern/gotcha.
- Planner **tự gọi** `memory_query` trước khi lập kế hoạch để lấy context cũ.
- Dispatch **tự chèn** memory liên quan vào prompt task mới.
- Knowledge graph **tự link** memories theo scope (project / milestone / slice) + tags.

**Bạn làm gì:**
```powershell
# Không phải gõ gì trong lúc chạy — agent lo.
# Nhưng BẠN nên:
# 1. Commit .gsd/ sau mỗi session → memory không mất
git add .gsd/ && git commit -m "sync gsd memory"

# 2. Gợi ý agent "hãy lưu lại" khi nó tìm ra pattern hay:
#    trong chat: "capture this as a memory with tag=routing"

# 3. Query memory thủ công trong chat (agent sẽ gọi memory_query):
#    "search memory for previous decisions about auth flow"

# 4. Xem health của memory store:
/gsd doctor                         # sẽ report memory cap + decay
```

**Export / Import (Phase 5):**
```powershell
# Backup memory sang project khác
gsd memory export > my-memories.json    # (nếu không có subcommand, agent gọi tool)
gsd memory import my-memories.json

# Hoặc đơn giản: copy thẳng file DB
cp .gsd/gsd.db ../project-B/.gsd/gsd.db
```

**Khi nào cần can thiệp:**
- Memory quá nhiều → `/gsd doctor` báo cap → cascade tự trim theo decay.
- Muốn **share pattern cross-project** → export rồi import.
- Agent không nhớ gì sau crash → check `git log .gsd/` xem có commit memory không.

---

### 2. 🪜 Progressive Planning — ADR-011 (AUTO)

**Phase 1 — Sketch-then-refine:** khi bạn gõ `/gsd new-milestone`, GSD giờ **phác sketch nhẹ trước** (2-3 slice outline), xin confirm, rồi mới lock plan chi tiết.

**Phase 2 — Mid-execution escalation:** task đang chạy phát hiện scope to hơn dự kiến → **tự escalate**, rollback file đã write nếu fail.

**Bạn không gõ gì — chỉ cần:**
```powershell
/gsd new-milestone      # flow mới tự chạy sketch → refine
# Khi TUI hỏi "accept sketch?" → Y để refine, N để chỉnh trước
```

**Chỉnh behavior (preferences):**
```yaml
# ~/.gsd/PREFERENCES.md hoặc .gsd/PREFERENCES.md
planning:
  sketch_first: true           # default true
  escalation_rollback: true    # default true
```

---

### 3. 🔌 Unified Workflow Plugin System

**Giờ có plugin architecture + modes + remote install.**

```powershell
/gsd workflow list              # xem plugin đã cài
/gsd workflow info <name>       # chi tiết 1 plugin
/gsd workflow install <url>     # cài từ remote (git URL / npm)
/gsd workflow run <name>        # chạy workflow
/gsd workflow validate <name>   # check plugin hợp lệ
```

**Use case thực tế:**
- Team có workflow riêng (ví dụ: "release-checklist") → publish repo → `workflow install`.
- Chọn "mode" (strict / loose / custom) cho từng project.

---

### 4. 🚪 /gsd onboarding Re-Entry

**Setup lại provider / key / preferences mà không cần restart TUI.**

```powershell
/gsd onboarding         # mở setup hub từ giữa session
# - Thêm provider mới
# - Đổi token_profile
# - Set git isolation
# - Tất cả không mất session hiện tại
```

**Hết double-banner bug** khi re-entry.

---

### 5. 🔍 /gsd scan — Lightweight Codebase Assessment

**Quét nhanh codebase để build context, không cần full milestone flow.**

```powershell
/gsd scan                       # scan repo → ghi .gsd/codebase/
/gsd scan --focus src/auth      # scan 1 thư mục
```

**Output:** `.gsd/codebase/SCAN-YYYYMMDD.md` gồm:
- File inventory + language breakdown.
- Symbols chính (export, class, function).
- Patterns phát hiện được.
- Dependencies.

**Khi nào dùng:**
- Trước khi `/gsd new-milestone` trên codebase lạ → agent có context tốt.
- Khi resume project sau vài tháng → refresh intel.
- Trước refactor lớn → quét pattern hiện tại.

---

### 6. 📱 Telegram Command Interface (Remote Control)

**Chạy auto-mode từ xa qua Telegram** (bên cạnh Slack/Discord đã có).

**Setup:**
```yaml
# ~/.gsd/PREFERENCES.md
remote:
  telegram:
    bot_token: "123456:ABC..."    # tạo bot qua @BotFather
    chat_id: "YOUR_CHAT_ID"
```

Hoặc trong TUI:
```powershell
/gsd prefs             # chọn Remote → Telegram → paste token
```

**Dùng:**
- Trong Telegram, chat với bot: `/status`, `/pause`, `/resume`, `/next`.
- Khi GSD gặp `ask_user_questions` trong auto-mode → câu hỏi bắn qua Telegram → bạn trả lời trên điện thoại → auto-mode tiếp tục.

**Use case:** chạy milestone dài ở máy server, ra ngoài, vẫn trả lời được quyết định khi agent hỏi.

---

### 7. 🎨 TUI Refresh + Themes mới

```powershell
/gsd prefs             # → Theme → chọn:
#   - tui-classic       (phong cách cổ điển 80-col)
#   - web-classic       (light mode sáng sủa)
#   - web-vivid         (màu rực, dễ scan)
#   - default           (bản gốc)
```

**Welcome screen / footer / chat pane** đều đã refresh. Re-entry onboarding không còn hang.

---

### 8. 💬 Ask User Questions với Markdown Preview

Khi agent dùng `ask_user_questions` trong auto-mode, **mỗi option giờ có thể kèm markdown preview** — hiện side-by-side panel để bạn đọc chi tiết trước khi chọn.

→ Bạn không làm gì — agent tự render. Chỉ cần biết: khi thấy câu hỏi có "preview" bên phải, mũi tên lên/xuống để highlight, ENTER để pick.

---

### 9. 🌲 Branch Isolation cứng hơn

**Với `isolation: branch` mode (không phải worktree):** milestone branch giờ được **tạo ngay khi vào milestone** (không phải lúc commit đầu tiên), và **validate main_branch** trước khi tạo → tránh tạo nhầm branch khi main chưa ready.

```yaml
# ~/.gsd/PREFERENCES.md
git:
  isolation: branch      # hoặc worktree
  main_branch: main      # validate
```

---

## 🎯 Tổng kết: Auto vs Manual

| Feature | Tự chạy? | Lệnh cần nhớ |
|---|---|---|
| Memory System (Phase 1-5) | ✅ Agent tự | `/gsd doctor` (health), commit `.gsd/` |
| Sketch-then-Refine Planning | ✅ Auto trong new-milestone | — |
| Mid-execution Escalation | ✅ Auto | — |
| Workflow Plugins | 🎛 Opt-in | `/gsd workflow list\|install\|run` |
| Onboarding Re-entry | 🎛 On-demand | `/gsd onboarding` |
| Codebase Scan | 🎛 On-demand | `/gsd scan` |
| Telegram Remote | 🎛 Opt-in | Set bot_token trong `/gsd prefs` |
| TUI Themes | 🎛 Opt-in | `/gsd prefs` → Theme |
| Ask User + Preview | ✅ Auto | — |
| Branch Isolation + main validation | 🎛 Opt-in | `isolation:` trong preferences |

**Tóm lại:** 5/10 feature mới **tự chạy**. 5/10 còn lại **gõ 1 lệnh** là xong.

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

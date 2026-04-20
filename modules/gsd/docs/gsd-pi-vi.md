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

## 🏆 Pro Combos — workflow chuyên nghiệp cho dự án lớn (2.76)

> Dưới đây là các **combo thực chiến** kết hợp feature mới 2.76 + command cũ. Copy-paste là chạy được, mỗi combo giải quyết 1 bài toán cụ thể của dự án lớn.

---

### 🥇 Combo 1: Day-0 Setup chuẩn "enterprise-ready"

Khi bắt đầu 1 project lớn mới hoặc convert project hiện có sang GSD:

```powershell
# Bước 1: cài + detect provider tốt nhất
npm install -g gsd-pi
8sync gsd setup --auto
8sync gsd fix

# Bước 2: vào project, chạy wizard
cd my-large-project
gsd

# Bước 3: cấu hình một lần cho cả project (trong TUI)
/gsd language vi                # khóa tiếng Việt
/gsd onboarding                 # set provider + token_profile
/gsd scan                       # tạo .gsd/codebase/SCAN-*.md — agent hiểu code sẵn
```

**Bước 4: viết `.gsd/PREFERENCES.md`** (project-level, override global):

```yaml
---
version: 1
mode: team                      # solo | team → team bật unique milestone IDs + stricter git
token_profile: balanced         # budget (giảm 60-80% cost) | balanced | quality

models:
  research: claude-sonnet-4-6
  planning:
    model: claude-opus-4-6      # planning dùng model mạnh
    fallbacks:
      - openrouter/z-ai/glm-5
      - openrouter/minimax/minimax-m2.5
  execution: claude-sonnet-4-6  # exec dùng model rẻ hơn
  completion: claude-sonnet-4-6

git:
  isolation: worktree           # worktree | branch | none
  main_branch: main             # validate trước khi tạo milestone branch

unique_milestone_ids: true      # M001-abc123 thay vì M001 — tránh collision khi team nhiều người

auto_supervisor:
  soft_timeout_minutes: 20      # warn
  idle_timeout_minutes: 10      # pause nếu idle
  hard_timeout_minutes: 30      # kill
  budget_ceiling: 50.00         # $USD/session

verification_commands:
  - npm run lint
  - npm run typecheck
  - npm test
verification_auto_fix: true
verification_max_retries: 3

auto_report: true               # tự gen HTML report .gsd/reports/ sau milestone

planning:
  sketch_first: true            # ADR-011 Phase 1
  escalation_rollback: true     # ADR-011 Phase 2

skill_discovery: suggest        # GSD gợi ý skill pack (React, Rust, ...)
---
```

**Bước 5: tạo `agent-instructions.md`** ở root project — LLM đọc mỗi session:

```markdown
# Agent Instructions — MyLargeProject

## Coding Standards
- TypeScript strict mode, no `any`.
- ESM only, không CommonJS.
- Prefer named exports.

## Architecture
- Clean Architecture: domain → usecase → infra.
- Không import ngược hướng.

## Domain Terms
- "Contract" = smart contract trong blockchain layer, không phải business contract.

## Workflow Preferences
- Commit theo Conventional Commits.
- PR mỗi slice, review xong mới merge.
```

✅ **Kết quả:** mọi milestone/slice/task sau đó agent **đã biết** standard + domain + stack — không phải giải thích lại.

---

### 🥈 Combo 2: 2-Terminal Power Workflow (the REAL workflow)

Đây là cách dùng auto-mode chuyên nghiệp — **1 terminal chạy, 1 terminal steer**:

**Terminal 1 — Executor:**
```powershell
gsd
/gsd new-milestone              # sketch-then-refine → accept
/gsd auto                       # chạy, đi cafe
```

**Terminal 2 — Steering (cùng project, file-based IPC):**
```powershell
cd my-large-project
gsd

# Discuss architecture khi đang chạy — không cần stop
/gsd discuss                    # talk về kiến trúc, agent pick up ở phase boundary

# Check progress bất cứ lúc nào (không tốn LLM)
/gsd status                     # text summary
/gsd query                      # JSON snapshot ~50ms
/gsd viz                        # workflow visualizer: progress, DAG, metrics, timeline

# Queue milestone kế tiếp
/gsd queue M002 --context spec-m2.md

# Fire-and-forget capture ý tưởng giữa chừng
/gsd capture "remember to add rate limiting to /api/auth"
# → agent tự triage giữa các task: note / defer / inject / replan / quick-task

# Steer plan documents không stop pipeline
/gsd steer                      # hard-edit plan, pickup phase boundary kế
```

✅ **Kết quả:** auto chạy không gián đoạn, bạn vẫn control được architecture + bắt ý tưởng mới mà không làm hỏng flow.

---

### 🥉 Combo 3: Memory-Driven Development (cross-project knowledge)

Dự án lớn thường có multiple repos. Combo này để **share knowledge giữa các project**:

```powershell
# Trong project A — agent tự capture memories khi làm việc
# Bạn hint để capture mạnh hơn:
#   trong chat: "capture pattern: luôn dùng zod cho runtime validation, tag=validation,api"
#   trong chat: "capture gotcha: Next.js 15 params phải await, tag=nextjs,breaking"

# Commit memory về git:
git add .gsd/gsd.db .gsd/KNOWLEDGE.md
git commit -m "chore(memory): sync Q1 learnings"

# Export sang project B:
cp .gsd/gsd.db ../project-B/.gsd/gsd.db
# hoặc dùng tool export (trong TUI project B):
#   chat với agent: "import memories from ../project-A/.gsd/gsd.db, scope=global"

# Trong project B, trước khi plan milestone mới:
/gsd scan                       # build codebase intel
# → planner tự query memory + scan → plan có context từ project A
```

**Maintenance định kỳ (Phase 5):**
```powershell
/gsd doctor                     # báo cap / decay / health
# Trong chat: "memory export with tag=validation" → lưu JSON riêng cho team
# Trong chat: "memory graph for MEM001 depth=3" → xem liên kết
```

✅ **Kết quả:** kiến thức team tích lũy xuyên project. Agent mới vào "biết" pattern cũ ngay, giảm 40-60% thời gian onboarding.

---

### 🏅 Combo 4: Remote Control (làm việc từ xa qua điện thoại)

Chạy milestone dài trên máy server / home PC, out-of-office vẫn kiểm soát:

**Setup 1 lần:**
```powershell
# Trong TUI:
/gsd prefs
# → Remote Channels → Telegram → paste bot token + chat ID
```

`PREFERENCES.md` sẽ có:
```yaml
remote:
  telegram:
    bot_token: "123456:ABC..."
    chat_id: "YOUR_CHAT_ID"
    poll_interval_seconds: 5    # default
  slack:                        # có thể bật song song
    webhook_url: "https://hooks.slack.com/..."
  discord:
    webhook_url: "https://discord.com/api/webhooks/..."
```

**Workflow thực tế:**
```powershell
# Máy server / home PC:
gsd headless --timeout 86400000   # chạy 24h không TUI, auto-restart crash

# Điện thoại — chat với Telegram bot:
/status                         # xem phase hiện tại
/pause                          # dừng an toàn
/resume                         # chạy tiếp
/next                           # force advance 1 unit
/query                          # JSON snapshot

# Khi agent dùng ask_user_questions → câu hỏi bắn qua Telegram
# Bạn trả lời trên điện thoại (có markdown preview option nếu câu hỏi complex)
# → auto-mode tiếp tục
```

✅ **Kết quả:** milestone 8-10 tiếng chạy đêm, sáng mở điện thoại đã thấy xong + HTML report ở `.gsd/reports/`.

---

### 🎯 Combo 5: Cost Optimization cực đoan (-60-80% cost)

Cho project lớn cost > $500/month, combo này ép về < $150:

```yaml
# .gsd/PREFERENCES.md
token_profile: budget                # khởi điểm

models:
  research: claude-haiku-4-5         # research chỉ cần skim
  planning:
    model: claude-opus-4-6           # planning PHẢI mạnh — đừng tiếc
    fallbacks:
      - openrouter/z-ai/glm-5        # fallback rẻ khi Anthropic rate-limit
  execution: claude-sonnet-4-6       # bulk work
  completion: claude-haiku-4-5       # summary/commit msg — haiku quá đủ

# Complexity-based routing tự phân loại simple/standard/complex
# → docs task dùng Haiku, architectural dùng Opus (tự động)

auto_supervisor:
  budget_ceiling: 25.00              # per-session hard cap, auto pause khi chạm

# Budget pressure graduated:
# - 50% budget → warn
# - 75% → downgrade non-critical phases sang model rẻ
# - 90% → chỉ giữ planning ở tier cao, còn lại haiku hết
```

**Monitor:**
```powershell
/gsd status                     # token + cost summary
/gsd viz                        # metrics tab có chart chi tiết
/gsd headless --json status     # cron ghi log cost theo giờ
```

✅ **Kết quả:** dự án lớn ~50 slices/tháng giảm từ $600 → $180, quality planning vẫn giữ.

---

### 🔥 Combo 6: Parallel Orchestration (nhiều milestone cùng lúc)

Dự án lớn có milestone **độc lập** (không depend nhau): chạy song song.

```powershell
# Set parallel trong preferences:
```
```yaml
parallel:
  enabled: true
  max_workers: 3
  budget_cap_per_worker: 20.00
```

```powershell
# Spawn worker cho từng milestone:
gsd headless dispatch M002 --worker-id w1 &
gsd headless dispatch M003 --worker-id w2 &
gsd headless dispatch M004 --worker-id w3 &

# Monitor chung:
gsd headless --json status --all-workers

# File IPC ở .gsd/parallel/ — workers share knowledge qua memory store
# PID liveness detection: worker chết → auto-orchestrator respawn
```

✅ **Kết quả:** 3 milestone xong trong thời gian 1. Worker crash → bạn bè vẫn chạy.

---

### 🛡 Combo 7: Crash-Proof Long-Running Milestone

Milestone 20+ slices chạy 2 ngày — chuẩn bị cho worst case:

```powershell
# 1. Bật tất cả safety net
```
```yaml
# PREFERENCES.md
git:
  isolation: worktree              # milestone branch riêng, main luôn xanh
  smart_commit: true               # commit per slice + squash merge

auto_supervisor:
  hard_timeout_minutes: 60         # phòng stuck
  
crash_recovery: true               # default true — synthesize briefing từ tool calls
```

```powershell
# 2. Chạy trong tmux/screen/wezterm persist
wezterm start -- gsd
# Trong GSD:
/gsd auto

# 3. Nếu session chết (SSH disconnect, máy reboot, ...):
ssh server
cd project
gsd
/gsd auto           # ← AUTO recover: đọc lock file, synthesize briefing, resume exact
# KHÔNG mất progress, KHÔNG mất memory.

# 4. Check integrity sau recovery:
/gsd doctor         # tự heal dispatch warnings, STATE.md, evidence rows
/gsd forensics      # full debugger nếu doctor không đủ (v2.40+)
```

✅ **Kết quả:** milestone 2-day survive SSH disconnect, OS update, Anthropic rate-limit, laptop sleep.

---

### 📊 Combo 8: Team Collaboration pro pattern

Team 3-5 dev dùng GSD chung repo:

```yaml
# .gsd/PREFERENCES.md (commit vào git, share cả team)
mode: team
unique_milestone_ids: true        # M001-abc123 — nhiều dev không collide
git:
  isolation: worktree             # mỗi dev worktree riêng, không đạp nhau
  main_branch: main

# Shared memory = commit .gsd/gsd.db (dùng git-lfs nếu to)
```

**Per-dev workflow:**
```powershell
# Dev A pick M002:
git pull
cd .gsd/worktrees/M002-xyz789 2>/dev/null || gsd auto   # GSD tự tạo

# Dev B pick M003:
git pull
gsd auto            # GSD detect M002 đang worktree → skip, pick M003

# Queue cho người kế:
/gsd queue M004 --assignee dev-c --context specs/m4.md
```

**Sync knowledge định kỳ:**
```powershell
# Mỗi tối, dev lead:
git pull
# trong GSD: "consolidate memories tagged=sprint-14, scope=global"
git add .gsd/ && git commit -m "chore(memory): sprint-14 consolidation"
git push
```

✅ **Kết quả:** team 5 người chạy 10 milestone song song, không merge conflict, shared knowledge graph.

---

### 🎨 Combo 9: Rapid Prototyping → Production (Quick to Full)

Bắt đầu fast, nâng dần lên enterprise:

```powershell
# Phase 1 — Quick mode (spike idea, < 1h)
/gsd-quick "add dark mode toggle"                    # nhanh, 1 file plan
/gsd-quick "prototype rate limiter" --research       # + research trước

# Phase 2 — Confirm idea → promote lên milestone
/gsd new-milestone --from-quick 001                  # convert quick → full milestone

# Phase 3 — Full pipeline
/gsd auto                                            # đầy đủ discuss/plan/exec/verify/validate
```

**Kết hợp với spike/sketch:**
```powershell
/gsd-spike "2 options: redis vs in-memory rate limit"   # 2-5 experiments, Given/When/Then verdicts
/gsd-sketch "dark mode UI variants"                      # 2-3 HTML mockups
# → kết quả lưu .gsd/ artifacts, dùng làm input cho new-milestone
```

✅ **Kết quả:** ý tưởng → POC → production không mất context, không duplicate work.

---

### 🧬 Combo 10: CI/CD Integration (GSD-native pipeline)

Biến GSD thành CI runner, không chỉ là local tool:

```yaml
# .github/workflows/gsd-nightly.yml
name: GSD Nightly Milestone
on:
  schedule:
    - cron: '0 2 * * *'       # 2am UTC

jobs:
  gsd-auto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      
      - name: Install GSD
        run: npm install -g gsd-pi
      
      - name: Run milestone headless
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GSD_TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT }}
        run: |
          gsd headless --timeout 7200000 \
            --answers "answers-ci.json"       # inject answer cho ask_user_questions
          
          # Exit codes:
          # 0 = complete, 1 = error, 2 = blocked (need human)
      
      - name: Upload HTML report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gsd-report
          path: .gsd/reports/
      
      - name: Notify Telegram on block
        if: failure()
        run: |
          # dùng gsd headless query check phase status
          gsd headless --json status | jq -r '.blocked_reason'
```

✅ **Kết quả:** milestone nightly chạy tự động, blocked → ping Telegram/Slack, report artifact.

---

### 📋 Bảng tổng hợp 10 combo

| # | Combo | Feature dùng | Target |
|---|---|---|---|
| 1 | Day-0 Setup | `/gsd onboarding` + `/gsd scan` + PREFERENCES + agent-instructions.md | New large project |
| 2 | 2-Terminal Power | `/gsd auto` + `/gsd discuss/status/capture/steer/viz` | Daily work, active steering |
| 3 | Memory-Driven Dev | Memory Phase 1-5 + `/gsd scan` | Multi-repo, cross-team knowledge |
| 4 | Remote Control | Telegram + `gsd headless` + ask_user preview | Off-hours, long-running |
| 5 | Cost Optimization | token_profile + complexity routing + budget_ceiling | Scale to $ efficiency |
| 6 | Parallel Orchestration | `parallel: enabled` + multi-worker + PID liveness | Independent milestones |
| 7 | Crash-Proof Long-Run | worktree isolation + crash recovery + `/gsd doctor/forensics` | 2+ day milestones |
| 8 | Team Collab | `mode: team` + unique_milestone_ids + worktree | 3-5 dev team |
| 9 | Quick → Full Promote | `/gsd-quick` + `/gsd-spike` + `/gsd-sketch` → `new-milestone --from-quick` | Rapid prototype → prod |
| 10 | CI/CD Pipeline | `gsd headless --answers` + exit codes + HTML report | Nightly/cron milestones |

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

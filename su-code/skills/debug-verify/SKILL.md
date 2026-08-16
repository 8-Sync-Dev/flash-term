# Debug → Fix → Push → Verify Auto-Loop

> **Triggers:** "fix xong tự test", "auto verify", "debug session", "check log", "reproduce bug", "deep chat", "loop đến khi done", "verify sau 3 phút"
>
> **Standing order 2026-05-20:** Agent tự chạy TOÀN BỘ loop. KHÔNG hỏi user "deploy xong chưa?". Chỉ hỏi khi QA fail ≥3 iter hoặc cần quyết định scope mới.
>
> **HARD RULE: dùng PRE-BUILT TOOLS, KHÔNG inline `node -e "..."` scripts.** Mỗi inline script = đốt token vô ích. Tool còn thiếu → thêm subcommand vào `tools/`, KHÔNG inline.
>
> **DUAL-LOG RULE (2026-05-25 update):** Bất kỳ kết luận về flow CRM webhook / Encore service / PubSub topic PHẢI có evidence từ CẢ 2 nguồn — CRM log (`tools/crm-log.mjs`) cho webhook outbound đã nhận + Encore server log (`tools/encore-log.mjs`) cho trạng thái internal. Chỉ 1 nguồn = đoán mò. Conclude code bug + sửa file stable mà chưa có encore log evidence = anti-pattern (xem §10).
>
> **READ-FULL-REPLY RULE (2026-06-05 — HARD, user-mandated):** Mỗi turn PHẢI đọc TRỌN VẸN reply bot (mọi bubble, mọi ký tự) qua `qa replies --decode` — KHÔNG skim câu đầu, KHÔNG kết luận "sạch" từ `grep -c`. Soi từng reply tìm: viết-hoa-sai (Capital giữa bubble sau `ạ`/`Dạ`/xuống dòng, name over-cap kiểu "khách Hàng"), split/merge sai (1 bubble khổng lồ, hoặc "Dạ"+bubble-2-cap), leak/fab, câu defer lặp. Bug nằm SẴN trong reply mà agent bỏ sót vì đọc lướt = turn FAIL, làm lại. (Lý do: user phải chụp ảnh nhắc CÙNG 1 lớp lỗi nhiều lần vì agent không đọc full reply.)
>
> **CODEGRAPH-FIRST RULE (HARD):** 100% mọi lookup symbol/function/path → `codegraph query|context|sync` TRƯỚC (`agents/skills/codegraph/SKILL.md`), KHÔNG grep/read theo trí nhớ. Symbol mới thêm mà codegraph "no results" → `codegraph sync` rồi query lại (đừng kết luận "không có"). Edit path đoán = lý do REVERT #1.
>
> **USER-TEST ASK RULE (2026-05-25):** Khi CRM FE/widget lỗi mà bug chỉ repro được qua DOM render (markdown link bị dính `)`, image bubble không hiện, click button không fire) → ngừng QA tự động, yêu cầu user `mở web lên test giúp tôi case <X>, gửi screenshot + session id`. KHÔNG đoán DOM behavior từ chuỗi text log.

---

## THE LOOP

```
┌──────────────────────────────────────────────────────────┐
│ 1. CHECK CODEBASE (read *.sql.up, *.ts liên quan trước)  │
│ 2. REPRODUCE (deep chat, mỗi turn inspect log NGAY)      │
│ 3. READ LOG (CRM webhook + Encore server, có breakpoint) │
│ 4. SEARCH literal values trong codebase                  │
│ 5. FIX (data → prompt → code guard, theo thứ tự đó)      │
│ 6. COMMIT + PUSH                                         │
│ 7. WAIT 180s (Encore Cloud deploy)                       │
│ 8. VERIFY (deep chat lại, mỗi turn inspect log)          │
│ 9. PASS? → comment GH issue (KHÔNG đóng)                 │
│    FAIL? → goto 1                                        │
└──────────────────────────────────────────────────────────┘
```

## 0. VERIFIED LIVE-LOOP RECIPE (2026-05-29 — copy-paste, đã chạy thật: session 95a3e25a iGO)

**Setup 1 lần / máy mới:**
- `pnpm install --no-frozen-lockfile` (root) → cài playwright; `npx playwright install chromium` (~175MB, có thể cần 2 lần nếu timeout).
- `export PATH="/home/alexdev/.encore/bin:$PATH"; encore auth whoami` → nếu "not logged in" thì `encore auth login` (cần cho encore-log; CRM-log chạy được KHÔNG cần auth).

**Loop MANUAL — 1 tin/lần, KHÔNG script batch (anti-pattern #15):**
```bash
# 1. Fresh session — WIDGET mode (mặc định, KHÔNG --api)
node tools/qa/qa.mjs start --agent=igo --fixture --label-prefix=eval-manual
KEY=<key_customer từ output>                       # vd 95a3e25a-6a2e-...

# 2. Gửi 1 tin (widget drive Chromium + poll CRM webhook, ~40-50s/turn)
node tools/qa/qa.mjs send --id=$KEY --message="<tin KH>"
#   → field "reply" ĐÃ là reply thật (widget tự poll); customer_social_id learn tự động.

# 3. DỪNG LẠI — đọc CRM log canonical (bubbles thật, đã tách [[SPLIT]])
node tools/qa/qa.mjs replies  --id=$KEY --since=5m   # bot bubbles
node tools/qa/qa.mjs outbound --session=$KEY --since=5m   # tool/webhook fired

# 4. (chỉ khi có encore auth) internal state — pronoun resolved, sanitizer fire
node tools/encore-log.mjs --session=$KEY --duration=60 --tail=30

# 5. CHẤM rubric §8b (R1-R9) + check kỹ thuật → ghi bảng per-turn → quyết tin kế
```

**Gotcha đã verify (đừng quên):**
- `--api`/buffer-message = ASYNC → trả `{status:"queued", reply:""}`. Reply thật chỉ ở CRM webhook. Widget mode tự poll nên field `reply` mới có giá trị → dùng widget, đọc qua `replies`.
- CRM log key theo `customer_social_id` (hex) — widget tự mint + learn. Pure api KHÔNG mint hex id → KHÔNG correlate được reply (đừng dùng api để verify hành vi).
- ~40-50s/turn là bình thường (Chromium + poll). KHÔNG sốt ruột nhảy sang `--api` → bỏ lỡ DOM/split/greeting bug (anti-pattern #13).

---


## 0a. ENV-REACHABILITY PREFLIGHT + BROWSER-VISIBLE VERIFY (2026-06-05)

> **Why:** widget mode (`qa.mjs` default) drives `crm5in1.cloudgo.vn/livechat.html`, which loads its SDK + socket from **`livechat.cloudgo.vn`** (GCP 35.240.x). A sandbox can reach `crm5in1` (VN IP) yet be firewall-blocked to `livechat.cloudgo.vn` (GCP) → `qa start` hangs at `page.goto … networkidle`. That is an **INFRA block, not a tool bug** — and the oh-my-pi `browser` tool fails on the same host too.

**PREFLIGHT before any widget run (1 line, do FIRST):**
```bash
curl -sS -o /dev/null -w "livechat %{http_code} conn=%{time_connect}s\n" --max-time 12 \
  "https://livechat.cloudgo.vn/api/v1/channels/91c46cd8-9cef-4ad4-9431-e945a7759db4/sdk.js"
```
- **HTTP 200** → widget OK, proceed `qa start`.
- **HTTP 000 / timeout** → widget UNREACHABLE from this env. **Do NOT silently fall back to `--api` and call it "verified"** — `--api` is dev-fast but the user does NOT watch it, and it skips DOM/[[SPLIT]]/render + may lack social-mapping for writes. Instead: print egress IP (`curl -sS https://api.ipify.org`), tell ops to whitelist it on the `livechat.cloudgo.vn` GCP firewall, OR ask the user to run the widget test on their network. STATE the block explicitly; treat as a DECISION GATE.

**oh-my-pi `browser` tool — VISIBLE CRM-dashboard verification (the user wants to SEE it, not read API JSON):**
- The harness has a real Chromium `browser` tool. Use it to log into the CRM dashboard and SHOW the bot conversation the user actually sees.
- Login: open `https://crm5in1.cloudgo.vn/`, `tab.fill('#username', …)` + `tab.fill('#password', …)` (dev acct `tu.nguyen`/`tu.nguyen`), click "Đăng nhập" (do NOT double-fill — it concatenates and fails login). Then open **Chat đa kênh** (omnichannel inbox) → screenshot bot bubbles as proof.
- Reachability: dashboard side = `crm5in1` (reachable); customer widget = `livechat.cloudgo.vn` (blocked when preflight fails).

**When knowledge is shallow — RESEARCH, never guess (self-learning harness):**
- Codebase symbol/path → `codegraph query|callers|callees|impact` FIRST (§1), never grep-by-memory.
- External lib / framework / API uncertain → `web_search` + the `librarian` subagent (reads lib source) BEFORE coding against it; unsure Mastra API → `tools/mastra-lookup.mjs`. Guessing an API shape = anti-pattern (causes REVERTs).

## 1. CHECK CODEBASE TRƯỚC

Mọi bug Encore liên quan đến CRM payload / DB / tool flow → đọc **codebase TRƯỚC**:

**⚠️ CODEGRAPH FIRST (2026-05-28 user directive: "force mạnh vào"):** bất kỳ symbol/function lookup nào — BẮT BUỘC codegraph TRƯỚC tiên. Đừng grep -r theo trí nhớ path, đừng read file đoán. Path có thể đã refactor:

```bash
codegraph query <symbolName>           # ⭐ FIRST — confirm shape + current path
codegraph_callers <funcName>           # who depends on it
codegraph_callees <funcName>           # what it depends on
codegraph_impact <symbol>              # blast radius before editing
codegraph_node <symbol> --code         # one symbol's full source
```

Full skill: `agents/skills/codegraph/SKILL.md`. Codegraph CLI / MCP tools cheap (~70% fewer file reads per benchmark). Nếu không dùng → high risk: edit wrong file, miss refactored callsite, re-ship reverted fix (top reason for ↩ REVERT in fix-history).

Sau codegraph confirm symbol still exists at expected path, lookup file/symbol bổ sung qua codebase-lookup khi cần fuzzy match:

```bash
# Fuzzy fallback ONLY when codegraph_query miss (rare)
node tools/codebase-lookup.mjs <keyword>                  # AND-match symbols
node tools/codebase-lookup.mjs --symbols saveActivityTool
node tools/codebase-lookup.mjs --files igo
```

Đọc bắt buộc:
- `*.up.sql` trong `encore-agent-module/src/dev/*/db/migrations/` (xem schema + seed)
- `*.ts` tool/service liên quan keyword bug
- `*.controller.ts` + `*.service.ts` của service liên quan
- Git history: `git log --oneline -20 -- <file>` + `git show <commit>` xem prior fix

---

## 2. REPRODUCE — Deep chat turn-by-turn

**WIDGET MODE = PRIORITY (2026-05-28 user directive):** Default `qa.mjs send` is browser/widget mode (Chromium loads CRM widget on prod-dev) — that's CLOSEST to real KH UX (DOM render, image bubbles, markdown click, multi-bubble timing). Verify here FIRST.

- **Default**: `qa.mjs send --id=$KEY --message="..."` (NO `--api` flag) → headless browser fires widget on `prod-dev-agentic-cloudgo-v1-kufi.encr.app`.
- **Fallback**: ONLY when widget mode fails (network unstable, page load 404, screenshot timeout) → add `--api` to fall back to direct HTTP endpoint.
- Reason: API mode bypasses widget DOM/JS pipeline → misses URL render bugs, image bubble visibility, markdown click target, [[SPLIT]] timing. Widget mode catches them.
- After widget `send`, still inspect via `tools/crm-log.mjs` + `qa.mjs replies` (CRM webhook is canonical regardless of trigger mode).

```bash
# Fresh session (unique fixture)
node tools/qa/qa.mjs start --agent=<igo|sale|care|lead> --fixture --label-prefix=debug-<issue>
KEY=<key_from_output>
```

**Mỗi turn là 1 cycle:**

```
send 1 message
  ↓
đọc reply (output của send) → có suspicions? đúng flow drawio?
  ↓
check CRM log NGAY (pre-built tool, không inline)
  ↓
quyết định turn kế
```

**🚫 ONE SEND PER TOOL CALL — HARD GATE (2026-05-29 user directive: "chat 1 tin phải dừng lại xem CRM+encore, đánh giá, nếu cần mới nhắn tiếp; 100% manual"):**
- Mỗi `qa.mjs send` PHẢI là tool call / bash block RIÊNG. TUYỆT ĐỐI KHÔNG đặt 2 lệnh `send` trong cùng 1 bash invocation, KHÔNG viết shell helper `send(){...}` rồi gọi liên tiếp, KHÔNG `&&`/`;` nối nhiều send. Một lần chạy = đúng 1 tin KH.
- Sau MỖI send, BẮT BUỘC DỪNG (kết thúc lượt tool) và inspect ĐỦ 2 nguồn TRƯỚC khi quyết định tin kế:
  1. `qa.mjs replies --id=$KEY --since=5m` (hoặc `crm-log.mjs --session=$KEY`) → đọc bubbles thật KH nhận.
  2. `qa.mjs outbound --session=$KEY --since=5m` + `encore-log.mjs --session=$KEY --duration=60 --tail=30` → tool/webhook nào fire, args, validator, internal state.
  3. CHẤM rubric §8b (R1–R9) + check kỹ thuật (leak/fab/tool) → ghi 1 dòng bảng per-turn.
  4. CHỈ khi đã hiểu turn này → mới soạn tin KH kế (dựa trên điều bot vừa nói thật, KHÔNG theo list soạn sẵn).
- Lý do: gom nhiều send = (a) bỏ lỡ bug per-turn (vỡ câu, fab, hỏi trùng) vì không đọc giữa các turn; (b) race tool-fire chồng nhau làm log khó quy trách; (c) đúng định nghĩa anti-pattern #14/#15. Gom send = test SAI, phải làm lại từ đầu.
- ≥10 turn manual (anti-pattern #14). Mỗi turn ~40-50s widget là bình thường — KHÔNG sốt ruột gom.

```bash
# ✅ ĐÚNG — 1 send / 1 lần chạy, rồi DỪNG đọc log, rồi mới turn kế ở lần chạy SAU
node tools/qa/qa.mjs send --id=$KEY --message="mình muốn tư vấn"
#   → DỪNG. Chạy riêng: qa replies + qa outbound + encore-log. Đánh giá. Xong mới send tiếp.

# ❌ SAI — gom 2 send / shell helper / && nối — CẤM (anti-pattern #14/#15)
#   send "T1" "..."; send "T2" "..."        ← test SAI
#   node ...send... && node ...send...        ← test SAI
```

**MANUAL TURN-BY-TURN MANDATE (2026-05-28 user directive, corrected):** Multi-turn behavior bugs (pronoun adapt, working-memory carry, sanitize chain ordering, F4 escalation) MUST be verified MANUALLY turn-by-turn, NOT via auto-script. Each turn the agent itself:

1. `qa.mjs send --id=$KEY --message="<turn N>"` (widget mode default).
2. `crm-log.mjs --session=$KEY --since=2 --max=10` → READ bot reply bubbles.
3. `encore-log.mjs --duration=15 --filter=$KEY|raw-reply|pronoun resolved|stripped|collapsed|WRN|ERR` → READ internal state (pronoun resolved value, sanitizer fires, post-process trace).
4. UNDERSTAND what happened: did bot reply match expected? did the right sanitizer fire? any unexpected WRN/ERR?
5. Decide turn N+1 based on what the bot actually said (not a pre-scripted message list).

**Loop 10-20 turns** to cover Stage A discovery → Stage B/C → confirm → CTA → schedule, watching pronoun consistency + sanitizer behavior turn-after-turn.

TUYỆT ĐỐI KHÔNG: viết auto-script chạy 10 turn batch rồi đọc log cuối — đó là **anti-pattern #14**. Mỗi turn phải tự agent đọc + hiểu + decide. Auto-script tạo `deep-chat.mjs` (commit `84f9513`) đã bị revert vì sai approach.

Mục tiêu: đi hết flow drawio (`ref/agent-flows/ALL-4-AGENTS.drawio.xml`) 20-30 turns, hoặc dừng khi trigger bug.

---

## 3. READ LOG — Pre-built tools

### 3.1 CRM webhook log (canonical)

```bash
# Pre-built — KHÔNG inline node -e
node tools/crm-log.mjs --session=<key> --since=30 --max=50               # all directions
node tools/crm-log.mjs --session=<key> --direction=ingress --since=30    # CRM→bot (customer_info CRM gửi)
node tools/crm-log.mjs --session=<key> --event=bot_update_customer       # bot→CRM payload
node tools/crm-log.mjs --event=bot_reply_message --session=<key>         # bot replies
node tools/crm-log.mjs --phone=0901234567 --since=60                     # hunt fake phone
node tools/crm-log.mjs --field=customer.phone --event=bot_update_customer --since=30
node tools/crm-log.mjs --session=<key> --json --max=100                  # full JSON dump
```

> **⚠️ SCHEDULE-CREATED DETECTION (2026-05-29 — verified FALSE-NEGATIVE trap):** `saveActivityTool` tạo activity bằng cách POST `saveCalendar` lên CRM CloudBot API → việc này log ở **CRM "Nhật ký đồng bộ" (inbound sync log)**, KHÔNG phải outbound webhook. CRM **KHÔNG** emit event `bot_create_activity`. → `crm-log.mjs --grep=bot_create_activity` LUÔN trả 0 dù lịch ĐÃ tạo = FALSE NEGATIVE (đừng kết luận "silent-skip" từ đó). Tín hiệu ĐÚNG để confirm lịch đã tạo:
>   1. `bot_update_customer` description chứa **"Đã đặt lịch / Mã lịch: ..."** (crm-log thấy được — KHÔNG filter event, đọc full).
>   2. CRM Nhật ký đồng bộ có dòng `saveCalendar` INBOUND (authoritative — nhờ user check UI nếu cần).
>   3. encore-log `tool:save-activity CALL/RESULT` — NHƯNG capture hay chết/rotate; nếu trống thì KHÔNG kết luận, dùng (1)+(2).
> Bài học 2026-05-29: agent grep `bot_create_activity` + encore capture chết → kết luận sai "call-path silent-skip" → ship fix `fee9d74` cho non-bug → user bắt lỗi "có time mà" → REVERT. ALWAYS confirm activity-created qua (1) bot_update_customer 'Đã đặt lịch' TRƯỚC khi kết luận schedule fail.

### 3.2 Encore server log (bot-side)

> **PREREQUISITE (2026-05-29 — verified gap): `encore logs` cần auth.** Chạy `encore auth whoami` TRƯỚC. Nếu "not logged in" → `encore auth login` (cần token/browser của user). Không auth được → encore-log BỎ TRỐNG, chỉ còn CRM log = **single source**. Khi đó ghi rõ "Encore-side chưa verify (no auth)" và KHÔNG kết luận code bug chỉ từ CRM log (xem DUAL-LOG RULE + anti-pattern #10). Bug hành vi quan sát trên reply (vỡ câu, hỏi trùng, sai xưng hô) VẪN kết luận được từ CRM log một mình — đó là output, không phải internal state.
>
> **API REPLY RỖNG (verified):** `--api` / `/customers/buffer-message` trả `{status:"queued", reply:""}` — reply thật về sau qua CRM webhook. KHÔNG tin field `reply` của `send --api`; luôn đọc qua `qa replies` / `crm-log`. Widget `send` (mặc định) tự poll nên field `reply` mới có giá trị.
```bash
# Pre-built — bounded duration + filter + breakpoint, KHÔNG bao giờ hang
node tools/encore-log.mjs --filter=dirty_crm_profile --duration=30 --max=20
node tools/encore-log.mjs --session=<key> --duration=60 --tail=30
node tools/encore-log.mjs --level=warn --duration=30 --out=tmp/encore-log/warn.log
node tools/encore-log.mjs --filter=bot_update_customer --break=fake_phone --duration=120
```

Tool tự kill `encore logs` sau `--duration` giây, tự stop khi đạt `--max` matches hoặc `--break` regex match. **Không bao giờ hang terminal.**

### 3.2b Encore CLI direct (2026-05-25)

Khi cần trace cụ thể 1 session + correlate với CRM webhook, kết hợp BOTH:

```bash
# Bắt buộc set PATH 1 lần per session — encore CLI ở /home/alexdev/.encore/bin/
export PATH="/home/alexdev/.encore/bin:$PATH"
which encore && encore version   # confirm v1.55+ available

# Fire QA send TRƯỚC, capture log NGAY sau (background → race-free)
node tools/qa/qa.mjs send --id=$KEY --message="..." --api
node tools/encore-log.mjs --duration=80 --max=300 --filter="$KEY|post-process|update_customer" --out=tmp/trace-<bug>.log

# Đọc song song log CRM + log Encore:
grep -E "post-process|update_customer|queueReason" tmp/trace-<bug>.log   # internal state
node tools/crm-log.mjs --session=$KEY --event=bot_update_customer --raw   # outbound payload
```

**Nguyên tắc đối chiếu:**
- Encore log nói `(echo) queued fields=[phone,email]` → CRM webhook PHẢI nhận đúng `{phone, email}`.
- Encore log nói `(json_output) queued mode=igo-contact-confirm` → CRM webhook PHẢI nhận `customer.description` string.
- Khi 2 nguồn LỆCH → bug ở layer giữa (PubSub serialize, interface strip, sanitize, dispatch retry).

**TEMP DEBUG LOG pattern** — khi muốn biết runtime state của 1 gate / variable, INSERT `log.info("[FB-X.Y] DEBUG", {...vars})` NGAY TRƯỚC gate, push, deploy, run 1 turn, đọc log, REVERT ngay trong same commit cycle (xem commit `01dbba2` → `733541d`). Để debug log lâu sẽ spam Encore log tier.

**ROOT CAUSE PATTERN tìm được nhờ dual-log (case study FB-1.6 2026-05-25):**
- Bug: `bot_update_customer.customer.description` không xuất hiện dù processor có log `post-merge company=Acme address=...` → ngỡ là post-process strip.
- Diagnose: thêm DEBUG log ở post-process gate → encore log show `collectedKeys=["name"]` (mất phone/company/mailingstreet) → root cause: Encore PubSub `Topic<PostProcessEvent>` strip fields ngoài interface lúc serialize → fix bằng extend interface, KHÔNG đụng helper code.
- Lesson: KHÔNG sửa `buildIgoFormattedDescription` (stable since 2026-05-23) — chỗ thật sự cần fix là interface declaration ở publisher boundary.

### 3.3 QA toolkit subcommands (riêng cho QA reply chain)

```bash
node tools/qa/qa.mjs replies --id=<key> --since=10m --decode    # bot reply text canonical
node tools/qa/qa.mjs outbound --session=<key> --since=20m       # tool calls fired
node tools/qa/qa.mjs events --session=<key> --since=20m         # aggregate
node tools/qa/qa.mjs timeline --id=<key>                        # full timeline
node tools/qa/qa.mjs info --id=<key>                            # chatbot-info snapshot
```

---

## 4. SEARCH literal values

Bug đến từ data leak / fab → grep TOÀN BỘ codebase cho giá trị nghi vấn:

```bash
# Pre-built lookup
node tools/codebase-lookup.mjs "0901234567"

# Hoặc rg (fallback)
rg -n "0901234567" --type=ts --type=sql -g '!node_modules' -g '!dist'
```

Mọi chỗ chứa literal value = potential source LLM copy hoặc DB seed pollution.

---

## 5. FIX — thứ tự ưu tiên (LIBRARY-FIRST, 2026-06-05)

1. **Xoá data source** (seed migration, fixture, prompt literal) — triệt để
2. **Sửa prompt** (supervisor instructions, rule, tone)
3. **Library primitive** — Mastra workflow step, scorer, `Memory.workingMemory` field, `suspend()/resume()`, zod tool input schema, retry. Per `docs/proposals/mastra-native-rewrite.md`. NEVER add a new hand-rolled regex / sanitizer / validator-CHECK after 2026-06-05 — that surface is in deletion, not extension.
4. **DECISION GATE** — if 1+2+3 cannot cover the bug, STOP and ask user with candidate primitives considered. Do NOT silently fall back to regex.
5. **KHÔNG sửa code đang stable** nếu root cause là data/prompt/library-config.

Tool dùng:
- Edit/Write theo project conventions (Biome, TS strict, kebab-case files)
- Pre-built: `tools/mastra-lookup.mjs` cho Mastra API uncertain
- Reference: `ref/mastra/llms.txt` (in-repo Mastra snapshot, current as of 2026-05-12)

---

## 6. COMMIT + PUSH

```bash
git add -A
git commit -m "<type>(<scope>): <summary>

<root cause from log evidence>
<files + reason>
Refs #<issue>"
git push origin <branch>
```

Conventional commit: `fix|feat|chore|docs|refactor(scope)`.

---

## 7. WAIT

```bash
sleep 180  # Encore Cloud build+deploy ~3 phút
```

---

## 8. VERIFY — deep chat lại, mỗi turn inspect

```bash
# Session MỚI (tránh CRM cache record cũ)
node tools/qa/qa.mjs start --agent=<role> --fixture --label-prefix=verify-<commit-short>
KEY=<new_key>

# Loop turn-by-turn (giống §2):
node tools/qa/qa.mjs send --id=$KEY --message="<turn 1>" --api
node tools/qa/qa.mjs send --id=$KEY --message="<turn 1>"           # WIDGET mode (default — KH UX parity)
# fallback only when widget fails: node tools/qa/qa.mjs send --id=$KEY --message="<turn 1>" --api
# ... tiếp tục đến khi cover flow bug
```

### Verify checklist

- [ ] Bot reply không leak/fab data
- [ ] `bot_update_customer` payload đúng (no fake phone/email)
- [ ] CRM panel không re-link record bẩn
- [ ] Flow đúng theo drawio
- [ ] Tone không vi phạm rule mới
- [ ] Encore log không có WARN/ERROR mới

---

## 8b. SALES-EMPLOYEE BEHAVIOR RUBRIC (2026-05-29) — "như nhân viên sale thật"

> Vì sao có: agent doanh nghiệp phải hành xử như 1 nhân viên sale GIỎI thật, không robot. Mỗi turn,
> ngoài check kỹ thuật (leak/fab/tool), BẮT BUỘC chấm reply theo rubric dưới. Mỗi R-FAIL = bug hành vi
> → ghi vào bảng per-turn, fix theo thứ tự data→prompt→code. Rubric cũng là nguồn `judge.criteria`
> cho eval harness (`tools/qa/eval`).

| # | Tiêu chí | PASS | FAIL (bug hành vi) |
|---|---|---|---|
| R1 | Xưng hô khoá | đúng anh/chị đã chốt, nhất quán mọi bubble | lẫn "anh/chị", đổi giữa chừng, gọi trống tên |
| R2 | 1 câu hỏi / turn | hỏi DUY NHẤT 1 thứ, rõ ràng | hỏi trùng cùng ý ở 2 bubble (vd xin tên công ty 2 lần), nhồi ≥3 câu hỏi |
| R3 | Câu chữ tự nhiên | đúng ngữ pháp, ngắt câu chuẩn | text vỡ ("anh ạvề"), cụt, ghép 2 mệnh đề sai, lặp mở đầu |
| R4 | Nhớ context | dùng lại info KH vừa nói (lĩnh vực/quy mô/pain) | hỏi lại thứ KH vừa trả lời |
| R5 | Discovery trước pitch | hiểu nhu cầu rồi mới đề xuất SP đúng | pitch SP/giá khi chưa rõ nhu cầu |
| R6 | Đề xuất có lý do | gắn SP với pain cụ thể của KH | liệt kê SP chung chung / dump cả bộ |
| R7 | Trung thực hành động | chỉ claim khi tool đã chạy thành công | "đã đặt lịch / đã ghi nhận" khi chưa fire tool |
| R8 | Chủ động, không ép | mời bước kế tự nhiên đúng lúc | spam upsell sau khi KH từ chối, hối thúc |
| R9 | Tone đồng cảm | có nhịp, acknowledge, như người thật | máy móc, lặp "Dạ em hiểu ạ" ×3, filler rỗng |

Bảng per-turn (§2 / issue-master-flow Step 5) PHẢI thêm cột `Rubric` liệt kê R-nào FAIL. Ví dụ thật
(session 95a3e25a, 2026-05-29 turn 1): R2 FAIL (hỏi tên công ty 2 lần B3≈B4) + R3 FAIL (B1 "Dạ em
chào anh ạvề ... rồi!" vỡ câu) — bug hành vi tận gốc cần fix, không phải lỗi kỹ thuật leak/fab.

---

## 9. REPORT — comment GH issue

```bash
node tools/qa/qa.mjs report --id=$KEY --title="Verify <issue> — <commit>"
gh issue comment <N> --body "..."  # evidence + log proof + session ID
```

**KHÔNG tự đóng issue** — user confirm rồi mới đóng (HARD RULE).

FAIL → quay lại §1, loop tiếp.

---

## Quick reference — pre-built tools

| Tool | Use case |
|---|---|
| `tools/codebase-lookup.mjs` | Find file/symbol trong codebase |
| `tools/mastra-lookup.mjs` | Search Mastra framework docs |
| `tools/crm-log.mjs` | CRM webhook log (3 directions, filter, field extract) |
| `tools/encore-log.mjs` | Encore Cloud server log (bounded duration + breakpoint) |
| `tools/qa/qa.mjs` | Manual QA toolkit (start/send/replies/outbound/events/info/report) |

**Thêm tool/subcommand mới:** viết file `.mjs` trong `tools/` hoặc subcommand vào `tools/qa/cmd/`. **CẤM inline `node -e "..."`** trong agent command.

---

## Anti-patterns

1. **Hỏi user giữa loop** — vi phạm standing order
2. **Verify bằng `tsc --noEmit` / `vitest`** — không catch runtime behavior (vitest đã remove khỏi repo)
3. **Spam 5-10 turn rồi mới check log** — phải mỗi turn inspect
4. **Inline `node -e "fetch(...)..."`** — đốt token, dùng `tools/crm-log.mjs` thay
5. **`encore logs` không bounded** — hang terminal, dùng `tools/encore-log.mjs` thay
6. **Không search literal value khi nghi fab** — #36 root cause tìm thấy nhờ `codebase-lookup 0901234567`
7. **Fix code khi root cause là data/prompt** — sửa source trước
8. **Reuse session key cũ khi verify** — CRM cache record cũ, luôn `--fixture`
9. **Tự đóng GH issue** — agent chỉ comment evidence, user đóng
10. **Conclude code bug khi chưa có encore log evidence** — sửa file stable (`buildIgoFormattedDescription`, supervisor prompt rule lớn, validator CHECK) mà KHÔNG có dual-log proof (xem §3.2b). Khi nghi: ADD temp DEBUG log → deploy → trace → confirm root cause → REVERT log + ship narrow fix. KHÔNG bao giờ refactor stable code "thử xem có đỡ không".
11. **Bỏ qua user clarification** — khi user nói rõ "ý X là Y" và previous code làm theo nghĩa khác → MUST revert thừa, KHÔNG cố giữ "phòng trường hợp" hay "có lợi cho future". Per Karpathy: delete more than add.
12. **Đoán DOM render từ log text** — nếu nghi widget render lỗi (markdown link dính `)`, ảnh không hiển thị, button click không fire) → phải ASK user mở web test thật, không phán đoán từ payload string.
13. **Verify bằng `--api` mode khi widget mode work** — bypass DOM/widget render → miss URL render bugs, image bubble visibility, markdown click target, [[SPLIT]] timing. Widget mode catches end-user UX bugs that API mode silently swallows. (2026-05-28 user directive — Bug 2 URL `/>` leak case study.)
14. **Verify ít hơn 10 turn cho BẤT KỲ issue** — CẤM tuyệt đối kết luận PASS sau <10 turn. Mỗi issue (pronoun adapt, F4 hallucination, KB leak, demo format, returning customer, EN per-turn, sanitize chain, working-memory carry, ...) PHẢI manual chat ≥10 tin nhắn để: (a) catch multi-turn regression (Bug B "chị anh/chị" chỉ xuất hiện sau khi multi-turn context build); (b) đào sâu context để hiểu LLM behavior; (c) đọc đủ dual-log (CRM + Encore) qua các stage discovery → advise → confirm → CTA → schedule; (d) cover edge cases user chưa nghĩ tới. Single-turn verify = false confidence + root cause vẫn còn sống. (2026-05-28 user directive: 'cấm chat ít hơn phải manual đào sâu context, log đầy đủ để nắm các risk, bug cần được xem xét fix tận gốc'.)
15. **Auto-script chat / batch-verify tool / GOM NHIỀU SEND** — TUYỆT ĐỐI KHÔNG viết script chạy 10 turn rồi đọc log tổng. Manual turn-by-turn = agent itself reads + decides per turn. Tool `deep-chat.mjs` (commit `84f9513`) đã revert hôm 2026-05-28 vì sai approach. **(2026-05-29 mở rộng) Cũng CẤM gom nhiều `send` trong 1 tool call / 1 bash block, shell helper `send(){...}` gọi liên tiếp, hay `&&`/`;` nối nhiều send — mỗi send PHẢI 1 lần chạy riêng rồi DỪNG đọc CRM+Encore (xem §2 ONE SEND PER TOOL CALL). Vi phạm 2026-05-29: agent dùng `send(){}` bắn T1–T2 liền → user bắt lỗi "chat 1 tin phải dừng xem log".** Tương tự: KHÔNG thêm standalone regex validator (`check-sanitize-*.mjs`) cho fix mới — real verification = manual E2E chat (pre-existing validators được giữ làm reference, nhưng KHÔNG tạo mới). (2026-05-28 + 2026-05-29 user directive.)
16. **Adding a new regex sanitizer / validator CHECK after 2026-06-05** — violates the LIBRARY-FIRST mandate. The 14 sanitizers in `processor.ts` + 22 CHECKs in `tool-call-validator.ts` are flagged for DELETION per `docs/proposals/mastra-native-rewrite.md`. Extend a Mastra workflow step, add a scorer, or surface a DECISION GATE — never extend the dying surface.
17. **Concluding "fab" without KB cross-reference (2026-06-05)** — before flagging a bot claim as fabricated, MUST grep `tools/qa/fixtures/{FAQ_Tong_Hop.md, Import-Product-AI-iGO.md, igo-faq.json}`. Three outcomes: verbatim in KB → grounded; adjacent but specific entity NOT in KB → F3 over-claim (prompt + grounding scorer); fully absent → genuine fab (defer per F4). Reverted commit `aefeb7b5` stripped a correct app-store claim because this step was skipped.

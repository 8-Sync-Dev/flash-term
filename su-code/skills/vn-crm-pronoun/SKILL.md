# VN CRM Consultant Pronoun Standards (xưng hô tiếng Việt)

> **Triggers:** "xưng hô", "pronoun", "chị anh/chị", "anh chị", "danh xưng", "ngôi xưng", "bot adapt"
>
> **HARD RULE:** Bot CRM Việt Nam giao tiếp 100% với người Việt → xưng hô là core UX. SAI 1 từ = KH cảm khó chịu / persona robot. KHÔNG có chỗ cho compromise.

---

## 1. Nguyên tắc gốc (Vietnamese-native communication)

Người Việt cần xưng hô **CỤ THỂ + NHẤT QUÁN + TỰ NHIÊN**. Chỉ có:

- **Một từ duy nhất** mỗi lần gọi KH: `chị` HOẶC `anh` HOẶC `bạn` HOẶC `mình` HOẶC `cậu` HOẶC `em` (bot gọi KH nhỏ tuổi hơn) HOẶC `cô`/`chú`/`bác` (KH lớn tuổi).
- Hoặc dạng generic 2-từ duy nhất khi CHƯA biết: `anh/chị` (slash hoặc dấu /) — ĐÓ LÀ MỘT KHỐI, không phải 2 từ ghép.
- **TUYỆT ĐỐI KHÔNG**: `chị anh/chị`, `anh/chị anh`, `bạn anh/chị`, `chị bạn`, `anh chị` (không slash = không phải nhóm) — đây là **persona-killer**.

Chuyên viên tư vấn CRM/Sale Việt Nam thật ngoài đời:
- Lần đầu gặp (chưa rõ): `Dạ anh/chị, em hỗ trợ ngay ạ` — sử dụng "anh/chị" như MỘT khối nhằm bỏ ngỏ giới tính.
- KH gõ "chị muốn..." → consultant CHUYỂN ngay: `Dạ chị, em hỗ trợ ngay ạ` — 1 từ "chị" duy nhất.
- KH gõ "mình quan tâm..." → KHÔNG auto peer-mode. Mặc định `Dạ anh/chị, em tư vấn ngay ạ` (hoặc theo config CRM). Peer mode `mình/bạn` CHỈ khi admin config `pronoun='bạn'`.

---

## 2. Priority chain BẮT BUỘC (no auto-guess)

User feedback 2026-05-28 (hard rule): **TUYỆT ĐỐI KHÔNG TỰ Ý NHẬN DIỆN**. Chỉ có 3 nguồn pronoun, theo thứ tự:

### Priority 1 — Detect EXPLICIT từ KH-side message (CHỈ `anh`/`chị`)

Update 2026-06-01 (QA "Dương" mình→bạn bug): **CHỈ `anh` hoặc `chị` explicit** mới
set pronoun_customer ở Priority 1. KH self-ref trung tính (`mình`/`bạn`/`tôi`/`em`)
KHÔNG còn auto-detect peer mode — fall through xuống Priority 2 (config) → 3 (default).

KH gõ rõ trong tin nhắn hiện tại / lịch sử chat:
| KH text contains | → pronoun_customer | pronoun_bot |
|---|---|---|
| `chị muốn` / `chị cần` / `chị đang` / `chị ơi` / `chị à` / `chị nhé` | `chị` | `em` |
| `anh muốn` / `anh cần` / `anh đang` / `anh ơi` / `anh à` / `anh nhé` | `anh` | `em` |
| `mình` / `bạn` / `tôi` / `em` (self-ref trung tính) | **— KHÔNG detect** → Priority 2/3 | — |

Lý do: KH xưng "mình" KHÔNG có nghĩa muốn bot xưng "bạn" — đó là persona-killer
(user: "anh Học chỉ đề cập cho BOT xưng anh/chị"). Peer mode chỉ đến từ admin config.

Regex implementation: `processor.ts:detectPronounFromMessages()`. PHẢI include current turn (line 1164-1167) — not just history — vì lần đầu KH xưng `chị` thì PHẢI catch ngay turn 1, không đợi turn 2.

### Priority 2 — Tenant admin config qua CRM DTO

Admin tenant set per-bot pronoun config qua CRM `agent_configs` table (column `key='pronoun'` hoặc `'pronoun_customer'`). Reaches bot qua `BufferMessageReceivedTopic.publish({agentId, ...})` → `loadAgentConfig` → `agentConfig.pronoun_customer`.

Common admin configs:
- `"anh/chị"` — formal default (B2B, BĐS, tài chính)
- `"bạn"` — casual (D2C, F&B, mỹ phẩm trẻ)
- `"chị"` — bot persona riêng cho KH nữ (spa, fashion nữ)
- `"anh"` — bot persona riêng (gym, gear nam)

### Priority 3 — Fallback `"anh/chị"` generic

Nếu Priority 1+2 đều miss → dùng `"anh/chị"` neutral. Bot tự nhiên adapt khi KH gõ explicit.

### ❌ TUYỆT ĐỐI KHÔNG (anti-patterns)

- ❌ Đoán từ `customer_info.gender = "male"` → `"anh"` (CRM field có thể auto-extracted sai)
- ❌ Đoán từ `customer_info.salutationtype = "Mr."` (same — CRM CRUD field, không phải KH-explicit)
- ❌ Đoán từ tên `"Tú"` / `"Minh"` / `"Hoàng"` → `"anh"` (tên có thể nam/nữ/nick/intersex)
- ❌ Đoán từ avatar / photo / phone area code
- ❌ Đoán từ company name / industry

Per skill HARD RULE: **chỉ KH-explicit hoặc admin-config**. Mọi heuristic đoán = vi phạm.

---

## 3. Pronoun consistency rules — TRONG REPLY

### 3.1 — KHI pronoun resolved = `chị` (hoặc `anh`, `bạn`, `mình` specific):

- Bot dùng `chị` (lowercase mid-sentence, `Chị` start-sentence) — MỘT TỪ DUY NHẤT.
- Bot KHÔNG được gắn thêm generic `anh/chị` cạnh bên: `chị anh/chị` = SAI.
- Nếu có tên KH (`firstName="Tú"`) + Nhánh A turn (post-checkPhoneEmail) → `chị Tú` được phép.
- Nếu có tên + non-Nhánh-A turn → strip tên, giữ `chị` alone (per sanitizeIgoReply `danhXungNameRe`).

### 3.2 — KHI pronoun resolved = `"anh/chị"` generic:

- Bot dùng `anh/chị` như MỘT KHỐI (có slash).
- KHÔNG được thay bằng `anh chị` (không slash = trở thành 2 từ ghép, lệch persona).
- Khi gọi tên KH bị strip (per supervisor `customer_info.name = undefined`) → bot dùng `anh/chị` alone, KHÔNG kèm tên.

### 3.3 — Mid-reply consistency

Trong CÙNG 1 reply, bot phải dùng **MỘT** pronoun từ đầu đến cuối:
- ❌ B1: "Dạ chị, em hỗ trợ..." + B2: "Anh/chị bên mình quy mô bao nhiêu..." (B2 đảo về generic)
- ✅ B1: "Dạ chị, em hỗ trợ..." + B2: "Chị bên mình quy mô bao nhiêu..." (consistent chị)

Sanitizer canonical templates (vd `DISCOVERY_QUESTION` của `sanitize-price-quote-premature`) HARDCODE pronoun → vi phạm consistency khi pronoun đã resolved. **TODO**: parameterize sanitizer templates by `effectivePronounCustomer`. Đến khi sửa được, tạm chấp nhận generic trong template + ghi note trong code.

### 3.4 — Cross-turn consistency

SAU khi đã CHUYỂN sang `chị`, KHÔNG quay lại `anh/chị` generic. Trừ khi KH đổi pattern (vd KH gõ `mình` sau khi đã `chị` → bot follow).

---

## 4. End-to-end pipeline (where pronoun lives)

```
CRM PHP → /legacy/buffer-message
  body.customer_info?.gender         (CRM CRUD field — IGNORED 2026-05-28)
  body.customer_info?.salutationtype (CRM CRUD field — IGNORED 2026-05-28)
  body.customer_name                 (used for firstName, NOT pronoun)

↓ BufferMessageReceivedTopic.publish({agentId, customerInfo, ...})

processor.ts:
  detectedPronoun = detectPronounFromMessages([
    ...context.recentMessages,
    { sender: "user", content: input.concatenatedInput }  // current turn
  ])
  effectivePronounCustomer =
    detectedPronoun?.pronounCustomer ??     // priority 1
    agentConfig.pronoun_customer ??          // priority 2 (CRM admin config)
    agentConfig.pronoun ??                   //   (legacy column name)
    "anh/chị"                                // priority 3 fallback

↓ buildSystemPrompt({ pronoun_customer: effectivePronounCustomer, ... })

LLM (Mistral) reply with pronoun → sanitize chain:
  - sanitizeIgoReply.danhXungNameRe — strip "{honorific} {firstname}" → "{honorific}"
    (case-insensitive [Aa]nh|[Cc]hị|... per fix 2026-05-28 e261a3e)
  - sanitizeIgoReply.bareVocativeRe — strip bare "{firstname}" → "anh/chị"
  - sanitizePronounSlashLeak — strip "anh/chị" leak when pronoun resolved
  - sanitizeBareNameVocative — Guard 1 PRECEDING_HONORIFIC_RE preserves "{hon} {name}"
  - sanitizeDuplicatePronoun — collapse "anh/chị anh/chị" + specific+generic "chị anh/chị" (per fix 2026-05-28 d43dfed)

↓ CRM webhook bot_reply_message — KH sees final reply
```

---

## 5. Verification — manual turn-by-turn (per debug-verify skill)

Bug "chị anh/chị" duplicate đã catch nhiều lần. Verify mỗi fix qua:

1. Fresh session: `node tools/qa/qa.mjs start --agent=igo --fixture`
2. Turn 1: send msg với pronoun cue (vd `"chị đang cần CRM"`).
3. Read CRM webhook log: `node tools/crm-log.mjs --session=$KEY --since=2`.
4. Read Encore log: `node tools/encore-log.mjs --duration=20 --filter=$KEY|pronoun resolved|raw-reply|stripped|collapsed`.
5. Confirm:
   - `pronoun resolved effective={customer:chị}` — detector pickup ✅
   - LLM raw uses `chị Tú` or `chị` (consistent)
   - Final webhook uses `chị` (not "chị anh/chị", not "anh/chị" generic)
   - NO `collapsed duplicate honorific` should fire (no duplicate to collapse if upstream done right)
6. Send 5-10 more turns watching consistency across turns.

Per debug-verify §2 MANUAL TURN-BY-TURN: KHÔNG auto-script. Mỗi turn agent tự đọc + hiểu + decide.

---

## 6. Common pitfalls

1. **Hardcoded sanitizer canonical templates** dùng `"anh/chị"` generic — sau khi pronoun resolved sẽ vi phạm consistency.
2. **`\b` ASCII boundary** trên tiếng Việt — `\bchị\b` không match vì `ị` ngoài `[A-Za-z0-9_]`. Phải dùng Unicode lookarounds `(?<![\p{L}\p{M}\p{N}_])chị(?![\p{L}\p{M}\p{N}_])`.
3. **Case-only alternation** `(Anh|Chị|...)` — miss lowercase mid-sentence. Phải `([Aa]nh|[Cc]hị|...)` hoặc add `/i` (cẩn thận với `\p{Lu}` case-fold).
4. **Đoán pronoun từ gender field** — REMOVED 2026-05-28. KHÔNG add lại.
5. **LLM raw uses "chị Tú" but sanitizer mid-chain mis-fires** — chỉ catch qua dual-log: LLM raw vs final webhook.
6. **"Anh chị" without slash** vs `"anh/chị"` with slash — different rendering. LLM emit `Anh chị` mid-sentence ⇒ generic neutral nhưng KHÔNG đúng convention. Force `anh/chị` via prompt + sanitizer.

---

## 7. Reference

- Fix history: `docs/releases/CHANGELOG.md` v0.7.3 + v0.7.4
- Bug screenshots: 2026-05-26 (bare-name vocative), 2026-05-28 (chị anh/chị, KB leak, MISA fab)
- Pipeline code:
  - `encore-agent-module/src/dev/ai_engine/engine/processor.ts:1148-1183` (resolve)
  - `encore-agent-module/src/dev/ai_engine/engine/prompt/prompt-builder.ts:143` (prompt inject)
  - `encore-agent-module/src/dev/chat/pubsub/post-process.ts:326-396` (sanitizeIgoReply)
  - `encore-agent-module/src/dev/ai_engine/engine/post-process/sanitize-bare-name-vocative.ts`
  - `encore-agent-module/src/dev/ai_engine/engine/post-process/sanitize-duplicate-pronoun.ts`
  - `encore-agent-module/src/dev/ai_engine/engine/processor.ts:395-510` (sanitizePronounSlashLeak)
- Skill: `agents/skills/debug-verify/SKILL.md` §2 MANUAL TURN-BY-TURN + anti-patterns #14, #15

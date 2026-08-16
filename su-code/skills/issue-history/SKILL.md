# issue-history — Self-reference catalog of prior fixes

> **Triggers:** "đã fix chưa?", "fix lại bug cũ", "regression", "lặp lại lỗi", "bug này đã gặp", "issue cũ", "tránh fix sai chỗ", "kiểm tra commit fix"
>
> **HARD RULE:** Before designing a fix for ANY reported symptom, grep
> `docs/feedback-qa/fix-history.md` for the symptom keyword. If a prior
> entry exists, READ its commit chain + Lessons BEFORE writing new code.

---

## Why this exists

The codebase has 800+ commits, 40+ `Refs #N` issues, and prompt rules
across hundreds of lines. The same symptom (e.g. "bot fab 'đã đặt lịch'
without firing tool") has been hit multiple times under different root
causes. Without a catalog, agents re-discover the same root cause + ship
reverts of reverts.

`tools/fix-history.mjs` scans `git log` for conventional commits with
`Refs #N` bodies, extracts root-cause / verify / lesson cues, and renders
a single markdown index. Grep that index BEFORE coding.

---

## Workflow (always)

### 1. Identify symptom keywords from user / log

From the user report or CRM log:
- Vocabulary: `"em đã ghi nhận lịch"`, `"em đã đặt"`, `"đã lưu"`, `"đã cập nhật"`
- Tool name: `saveActivityTool`, `checkPhoneEmailTool`, `saveTicketTool`
- Error code: `MISSING_CONTACT`, `HTTP 401`, `schedule_done_no_tool`
- Validator reason: `too_many_followup_questions`, `faq_assert_no_tool`
- File hint: `tool-call-validator`, `post-process`, `igo.supervisor`

### 2. Grep the catalog

```bash
grep -inB2 -A8 "em đã ghi nhận" docs/feedback-qa/fix-history.md
grep -inB2 -A8 "MISSING_CONTACT" docs/feedback-qa/fix-history.md
grep -inB2 -A8 "saveActivityTool" docs/feedback-qa/fix-history.md
```

If hits:
- Read the **Commit chain** — any `↩ REVERT` line means a prior approach
  failed user review. DO NOT re-ship that approach.
- Read **Root cause / evidence** — confirms the diagnostic angle.
- Read **Lessons** — gates around what NOT to change next time.

### 3. Cross-check with codegraph (see `agents/skills/codegraph/SKILL.md`)

After narrowing via fix-history, confirm the exact symbol still has the
expected shape:

```bash
codegraph query inspectSaveActivityCalls
codegraph query SCHEDULE_DONE_CLAIM_RE
```

**HARD WIRE 2026-05-28**: codegraph chạy TRƯỚC bất kỳ `read <file>` / `grep -r` nào. Nếu bạn định mở file thẳng theo trí nhớ path → STOP, gõ `codegraph query <symbol>` trước. Path có thể đã refactor.

If the function/regex matches what fix-history says, the prior fix is
still in place — the new symptom is a DIFFERENT path. If it changed,
trace via codegraph_callers/callees to see who else depends on it.

### 4. Combine with debug-verify (see `agents/skills/debug-verify/SKILL.md`)

The catalog tells you WHAT was fixed and HOW. To CONFIRM the report is
the same bug (vs. a regression of the prior fix), follow debug-verify:

- CHECK CODEBASE first (per §1).
- REPRODUCE manually ≥10 turns (per anti-pattern #14) — NOT auto-script.
- READ dual-log (CRM + Encore) before concluding code change is needed
  (per anti-pattern #10).
- FIX in order data → prompt → code (per §5).

### 5. Karpathy guard rails (see `.forge/skills/karpathy-guidelines/SKILL.md`)

Before shipping the new fix:

- **§1 Think before coding**: did the prior commit's Lesson cover this?
  If yes — apply that pattern. If you're about to do something the
  Lesson forbids, STOP and surface to user.
- **§3 Surgical**: every line you change must trace to the user request.
  If a prior commit reverted a change, that change is OFF-LIMITS.
- **§4 Goal-driven**: write the verify scenario BEFORE the fix. The
  fix-history "Verify cues" are good seeds.

---

## After landing a new fix

Re-run the scanner so the next agent sees your work:

```bash
node tools/fix-history.mjs
git add docs/feedback-qa/fix-history.md
git commit -m "chore(history): refresh fix-history catalog"
```

The catalog is a SNAPSHOT — it goes stale if you don't regenerate. The
trigger heuristic: any commit body that contains `Refs #N` should be
followed by a `chore(history): refresh` in the same push.

---

## Catalog format reference

Each entry in `docs/feedback-qa/fix-history.md`:

```
## #42 — <latest-summary> (<date-range>)

**Latest:** <hash> <summary>
**Commit chain:**
- <hash> <date> <type>(<scope>) — <summary>     ← oldest first
- <hash> <date> <type>(<scope>) — <summary> ↩ REVERT   ← failed approach
**Files touched:**          ← union of files changed across the chain
**Root cause / evidence:**  ← extracted from commit bodies
**Verify cues:**            ← session IDs, log excerpts to repro
**Lessons:**                ← what NOT to do, anti-patterns
[GH issue]                  ← deep link
```

Each section pulls from commit body lines containing keywords:
- Root cause: `root cause`, `evidence:`, `bug:`, `regression:`
- Verify: `verify:`, `session `, `dual-log`, `ref:`
- Lessons: `lesson:`, `anti-pattern`, `never:`, `always:`, `rule:`

So when writing new commit messages, USE THESE KEYWORDS in the body for
the next agent's catalog to pick up your reasoning:

```
fix(igo): example fix summary

Root cause: <observed effect + diagnosed source>
Evidence: session <key>, dual-log captured at tmp/trace-<bug>.log
Verify: KH msg '<example>' → bot reply '<expected>' → CRM event <name>
Lesson: NEVER <pattern that caused this regression>. ALWAYS <correct approach>.

Refs #42
```

---

## Anti-patterns this skill prevents

1. **Re-shipping a reverted fix** — catalog flags `↩ REVERT` so you see
   the prior attempt was rejected by user review.
2. **Modifying stable code** — fix-history shows file ages + commit
   counts. A file with 20 commits across 6 months is LOAD-BEARING; touch
   it only with dual-log evidence (debug-verify §3.2b).
3. **Re-investigating a known root cause** — if the catalog already has
   a `Root cause / evidence` line for your symptom, START THERE.
4. **Adding a 4th sanitizer for the same bug pattern** — catalog shows
   prior `sanitize-*.ts` files + their scope. New sanitizer must NOT
   duplicate. Prefer extending or replacing per user directive.
5. **Missing the cross-cutting fix** — if 3 commits touch the same file
   for the same `Refs #N`, the issue is structural, not surgical. The
   catalog surfaces this via the commit chain length.

---

## Maintenance

- `tools/fix-history.mjs --since=2026-05-01` — limit to recent commits
  for faster regeneration when chain is long.
- `tools/fix-history.mjs --issue=42 --stdout` — print one issue without
  rewriting the file. Useful for quick lookups in a chat.
- The `UNREFERENCED` bucket holds commits without `Refs #N` — review
  occasionally to backfill issue numbers in commit messages.

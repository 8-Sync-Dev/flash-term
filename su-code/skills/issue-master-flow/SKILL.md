# issue-master-flow — Master playbook for any bug/issue

> **Triggers:** "fix issue", "debug bug", "QA fail case", "có bug", "fix sai chỗ", "tránh fix lại đúng chỗ", "issue cũ", "test case fail"
>
> **HARD MANDATE:** Khi nhận bất kỳ bug report nào, RUN through this playbook step-by-step BEFORE touching code. Each step references a sub-skill — DO NOT skip steps. Skipping any step has caused production regressions in past sessions (see `docs/feedback-qa/fix-history.md`).
>
> **STANDING ORDER 2026-05-28:** Agent tự chạy TOÀN BỘ playbook end-to-end. Chỉ stop để ask user khi gặp DECISION GATE đánh dấu rõ trong step (vd Step 6 fix-strategy choice).
>
> **⚠️ CODEGRAPH HARD-WIRE (2026-05-28 user directive: "skill codegraph rất hay bị quên — force mạnh vào nhé"):**
> Trước MỌI lookup file/symbol/caller/callee, BẮT BUỘC `codegraph query <name>` HOẶC `codegraph search ...` TRƯỚC. KHÔNG được `grep -r` / `find -name` / `read <guess-path>` mà chưa qua codegraph. Vi phạm = fix sai file vì path đã refactor (top reason cho ↩ REVERT trong `docs/feedback-qa/fix-history.md`).
>
> Codegraph commands (lightweight — main session OK):
> ```bash
> codegraph query <symbolName>          # find by name, returns shape + file:line
> codegraph_callers <funcName>          # who depends on it
> codegraph_callees <funcName>          # what it depends on
> codegraph_impact <symbol>             # blast radius
> codegraph_node <symbol> --code        # one symbol's source
> ```
> Full skill: `agents/skills/codegraph/SKILL.md`. Use BEFORE Step 4 codebase read — codegraph tells you WHICH file to read.

## The 9-step master loop

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1 — Surface assumptions (karpathy §1)                      │
│ Step 2 — Grep fix-history catalog (issue-history skill)         │
│ Step 3 — Codegraph map symbol shape (codegraph skill)           │
│ Step 4 — Read codebase TRƯỚC (debug-verify §1)                  │
│ Step 5 — Reproduce + dual-log (debug-verify §2-§3, ≥10 turn)    │
│ Step 6 — DECISION GATE — pick fix strategy (data→prompt→code)   │
│ Step 7 — Apply surgical fix (karpathy §3)                       │
│ Step 8 — Commit + push + wait 180s + verify (debug-verify §6-§8)│
│ Step 9 — Update catalog + report (issue-history maintenance)    │
└─────────────────────────────────────────────────────────────────┘
```

If any step yields conflicting evidence → loop to Step 1 to re-state assumptions. Do not skip ahead.

---

## Step 1 — Surface assumptions (karpathy §1)

Reference: `.forge/skills/karpathy-guidelines/SKILL.md` §1 Think Before Coding.

State out loud (in your reply):
1. **Symptom**: what KH/QA reported, verbatim if possible.
2. **My current theory of root cause** (1 sentence) + confidence (high/med/low).
3. **Alternative theories** if any — surface ALL plausible, don't silently pick.
4. **Required evidence** to confirm theory (specific log lines / endpoint responses / commit shape).

Bad: "I'll fix the X bug." → skips to coding.  
Good: "Symptom is bot replies 'em đã đặt lịch' but no CRM activity. Theory A (high): validator counts fired-but-failed tool calls as success. Theory B (low): tool fires correctly but webhook listener filters out create event. Need encore log of saveActivityTool RESULT + crm-log filter for bot_create_activity."

---

## Step 2 — Grep fix-history catalog (issue-history skill)

Reference: `agents/skills/issue-history/SKILL.md`.

```bash
# Extract 3-5 keywords from Step 1 symptom + theory
grep -inB1 -A5 "<keyword>" docs/feedback-qa/fix-history.md
```

Critical reads:
- Any `↩ REVERT` line — that approach FAILED, do not re-ship.
- "Files touched" — note files that have appeared in 5+ prior fixes (they're LOAD-BEARING, treat as stable).
- "Lessons" — anti-patterns to avoid.

**Output to your reply**: 3-line summary of what catalog says about this symptom (or "no prior entry").

**Decision gate**:
- If catalog shows ≥3 commits on same issue chain → user-confirm before another attempt (loop history).
- If catalog shows ↩ REVERT for similar approach → DO NOT try same approach; redesign.

---

## Step 3 — Codegraph map symbol shape (codegraph skill)

Reference: `agents/skills/codegraph/SKILL.md` (lightweight tools only in main session).

```bash
codegraph query <symbolFromTheory>       # finds definitions + brief context
codegraph_callers <function>             # who depends on it
codegraph_callees <function>             # what it depends on
codegraph_impact <symbol>                # blast radius if changed
```

Confirm the symbol still has the shape your theory assumes. If diff between catalog's "Files touched" and current code → recent refactor; reload understanding before fix.

**Output to your reply**: 1-line shape confirmation. E.g. "inspectSaveActivityCalls at tool-call-validator.ts:497 — current returns {fired, firedWithCrmId} via for-loop on toolCalls. Catalog last-touched 2026-05-28 60c0c92."

---

## Step 4 — Read codebase TRƯỚC (debug-verify §1)

Reference: `agents/skills/debug-verify/SKILL.md` §1.

Mandatory reads (NOT optional):
- `*.up.sql` in `encore-agent-module/src/dev/*/db/migrations/` if data/schema involved.
- Tool `.ts` file containing the function from Step 3.
- The supervisor prompt section relevant to lane (igo.supervisor.ts).
- `git log --oneline -10 -- <file>` for recent activity.

**Output**: 5–10 line summary of code state + recent commit cluster.

---

## Step 5 — Reproduce + dual-log (debug-verify §2 + §3)

Reference: `agents/skills/debug-verify/SKILL.md` §2 + §3.

```bash
# Fresh session, anti-pattern #8 (no cache reuse)
node tools/qa/qa.mjs start --agent=<role> --fixture --label-prefix=debug-<issue-keyword>
KEY=<from output>

# Widget mode default (anti-pattern #13), NO --api unless widget fails
node tools/qa/qa.mjs send --id=$KEY --message="<turn 1>"
# Per turn:
#   1. read reply
#   2. crm-log.mjs --session=$KEY --since=2 --max=10
#   3. encore-log.mjs --duration=15 --filter=$KEY|<tool>|validator
#   4. understand, decide next turn
```

**Mandatory**: ≥10 turns (anti-pattern #14). Single-turn verify is PROHIBITED.

**🚫 ONE SEND PER TOOL CALL (2026-05-29 hard gate — debug-verify §2):** mỗi `send` = 1 tool call / bash block RIÊNG → DỪNG → inspect CRM (`qa replies`) + Encore (`qa outbound` / `encore-log`) → chấm rubric → MỚI send tin kế. CẤM gom 2 send, shell helper `send(){}`, hay `&&` nối nhiều send (= anti-pattern #14/#15, test SAI phải làm lại).

**Output to your reply**: per-turn table with KH msg / bot reply / tool fire / log evidence /
sales-behavior rubric (R1–R9, see debug-verify §8b). Each turn flag which R-rule FAILS — behaviour
bugs (vỡ câu, hỏi trùng, sai xưng hô) are first-class, fix tận gốc theo data→prompt→code. Like:

| Turn | KH | Bot | Tool fire | Rubric (R# FAIL) | Status |
|---|---|---|---|---|---|

---

## Step 6 — DECISION GATE — fix strategy

Reference: `agents/skills/debug-verify/SKILL.md` §5 fix priority.

Order is HARD: data → prompt → code.

1. **Data-layer fix** (`*.up.sql` seed, env config, DB row): can the issue be resolved by changing data without code?
2. **Prompt-layer fix** (supervisor instructions): can a new APPENDIX rule prevent this?
3. **Code-layer fix** (validator / sanitizer / tool): only if 1+2 cannot.

**Karpathy §3 surgical**: every changed line must trace to the symptom. NEVER refactor "while you're at it".

**Karpathy §1 surface tradeoff**: if 2 strategies viable, SURFACE BOTH to user with tradeoffs before picking.

**Per user 2026-05-28 directive**: PROMPT changes are ADDITIVE ONLY — never modify existing rules, only ADD new APPENDIX sections.

**Output**: chosen strategy + 1-sentence justification + ONE alternative considered.

---

## Step 7 — Apply surgical fix (karpathy §3)

- For DATA: write migration `0NNN_<scope>.up.sql` or update env file.
- For PROMPT: APPEND to existing APPENDIX section in `igo.supervisor.ts`; never edit prior rules unless user gives explicit "rewrite" approval.
- For CODE: smallest possible diff. Add inline comment with `// <date>: <reason>` referencing this session's evidence.

**Verify before commit**:
- TS typecheck: `pnpm -C encore-agent-module exec tsc --noEmit -p tsconfig.json 2>&1 | grep <file>` (empty = OK).
- Biome lint (only if file touched needs it): `pnpm -C encore-agent-module exec biome check --write <file>`.

---

## Step 8 — Commit + push + wait + verify (debug-verify §6-§8)

Commit body MUST follow the catalog-friendly format (see `agents/skills/issue-history/SKILL.md`):

```
<type>(<scope>): <50-char summary>

Root cause: <observed effect + diagnosed source from Step 5 dual-log>
Evidence: session <KEY>, dual-log at tmp/trace-<bug>.log
Verify: KH msg '<example>' → bot reply '<expected>' → CRM event '<name>'
Lesson: NEVER <anti-pattern>. ALWAYS <correct approach>.

Refs #<N>
```

Then:

```bash
git push origin <branch>
sleep 180      # Encore Cloud deploy
```

Verify with FRESH session (anti-pattern #8), ≥10 turn manual (anti-pattern #14).

**Output**: per-turn table again, comparing before/after for the fixed symptom.

---

## Step 9 — Update catalog + report

```bash
node tools/fix-history.mjs
git add docs/feedback-qa/fix-history.md
git commit -m "chore(history): refresh catalog after #<N>"
git push
```

If issue has GH number, comment evidence per `agents/skills/debug-verify/SKILL.md` §9 — DO NOT close issue (user closes).

---

## Quick reference — sub-skills

| Skill | Use during step | Path |
|---|---|---|
| karpathy-guidelines | 1, 6, 7 | `.forge/skills/karpathy-guidelines/SKILL.md` |
| issue-history | 2, 9 | `agents/skills/issue-history/SKILL.md` |
| codegraph | 3 | `agents/skills/codegraph/SKILL.md` |
| debug-verify | 4, 5, 6, 8 | `agents/skills/debug-verify/SKILL.md` |

---

## Verifying which LLM model is in use (often skipped → assumed Mistral)

Project supports Gemini / Mistral / OpenAI / Anthropic per `agent-builder.ts:191`. Default per env varies. Before assuming a model in your fix reasoning:

```bash
curl -sS $CLOUDGO_BASE/domain/llm-status \
  | jq '.data.supervisors[] | {name, modelName, providerName}'
```

Live config as of 2026-05-28: IGO/Care/Sale/Lead bots all on `gemini-3.1-flash-lite` (Google). Mistral is FALLBACK only (`resolveAgentAsync` line 222 in `processor.ts`). Past commit messages that said "Mistral may ignore toolChoice" were INACCURATE — actual LLM is Gemini which honors toolChoice well.

---

## Critical anti-patterns this playbook prevents

1. **Skipping Step 2 catalog grep** → re-shipping reverted approach.
2. **Skipping Step 3 codegraph** → fixing wrong file because symbol moved.
3. **Skipping Step 5 dual-log** → guessing root cause from prompt alone (top reason for revert in catalog).
4. **Skipping Step 6 decision gate** → coding without considering prompt/data alternative.
5. **Mistral/Gemini confusion** → reasoning about model behavior without `llm-status` check.
6. **Single-turn verify (Step 8)** → false PASS, KH hits it again in QA next day.

---

## Example walkthrough — Case [4] schedule fab (2026-05-28)

Step 1: Symptom = bot "đã ghi nhận lịch" + no CRM activity. Theory (high) = validator counts fired-failed as success. Alt (low) = LLM didn't fire tool at all.

Step 2: `grep "đã ghi nhận lịch" docs/feedback-qa/fix-history.md` → #42 chain has `4fdc9e8 ↩ REVERT` (F4 vocabulary rewrite, reverted per user "stable prompt only add"). Lesson: do NOT modify F4 prose; add new section instead.

Step 3: `codegraph query inspectSaveActivityCalls` → `tool-call-validator.ts:497`, returns `{fired, firedWithCrmId}`. No success check.

Step 4: Read tool-call-validator.ts:494-513 → confirms `fired = true` regardless of `tc.result.success`.

Step 5: 13-turn widget session `1cb891da-...` — turn 11 LLM fab text, `toolsFired=[]`, validator caught with `reason=schedule_done_no_tool`, forced retry, tool fired success=true activityId=1514495.

Step 6: Code-layer fix (data/prompt cannot — this is validator logic bug). Surgical: flip `fired` to require `result.success===true`.

Step 7: 8-line change in `inspectSaveActivityCalls`, inline comment dated `2026-05-28` referencing session.

Step 8: Commit `60c0c92`, push, sleep 180s, fresh session, verified: validator NOW catches fired-but-failed → forces retry → tool succeeds → CRM activity 1514495.

Step 9: `node tools/fix-history.mjs` → catalog updated; #42 chain now includes `60c0c92`.

---

## When to STOP + ask user

Per `agents/skills/debug-verify/SKILL.md` "Standing order 2026-05-20" — agent runs full loop autonomously. Stop only when:

- Step 6 DECISION GATE has 2+ equally-viable strategies with materially different tradeoffs.
- Step 8 verify FAIL ≥3 iterations on same symptom.
- User clarification needed for ambiguous spec (vd "do you want additive or rewrite?").
- Destructive operation (DROP table, force-push to main, delete files user owns).

In all other cases — execute, ship, report.

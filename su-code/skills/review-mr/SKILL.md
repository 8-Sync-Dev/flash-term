---
name: review-mr
description: Rigorously review a GitLab/GitHub merge request or branch before it merges — convention/doctrine, deployability, benchmark, performance, and unit tests — then produce a boardroom-grade PDF verdict via the business-brief engine. Use whenever asked to "review MR / review branch / duyệt MR / review kĩ / đánh giá nhánh trước khi merge". Read-first, measure-real, never merge/deploy without explicit approval.
---

# review-mr

Turn a merge request into a **cited, reproducible verdict PDF**. The review is worthless if it trusts the MR's own claims — every number is re-measured on the running system, every "it builds" is re-run, every pure function without a test gets one. First validated 2026-08-07 on `fix/fix_performace_copilot` (copilot latency MR): three deploy-blockers and a wrong-mechanism perf claim were caught only by reproducing, not reading.

## 0. STOP gates (before writing a single verdict line)

- **Never trust the MR's numbers — reproduce them.** The canonical failure: an MR "fixes latency" by citing prompt bloat; on the live env the KB was empty so the bloat never existed — the real cost was a 95–918ms retrieve round-trip. The win was real, the *stated mechanism* was wrong. You only learn that by measuring.
- **Deployability is a hard gate, not a nicety.** Run the project's real build/deploy command, not just `go build`/`tsc`. Encore, for one, passes `go build` with a blank `encore.app` id but fails every `encore` command. See §2.
- **Never merge, push to master, or deploy to PROD as part of a review.** A review ends at a verdict + a review branch. The human approves; only then does anything move. State this in the report.
- **KHÔNG BAO GIỜ xóa source branch của MR.** Đóng MR = merge branch VÀO master qua GitLab merge button. Xóa branch = mất lịch sử audit. Quy tắc tuyệt đối.
- **Chỉ merge MR khi 4 điều kiện ĐỦ:** (a) MR fix xong hết blocker, (b) merge êm không lỗi, (c) test RẤT KỸ trên kufi DEV, (d) Sếp approved. Thiếu 1 = STOP.
- **PROD VPS = nguy hiểm — chỉ TRACE, KHÔNG CODE.** Khi Sếp báo lỗi PROD: đọc log/chat_trace/curl endpoint, tìm root cause, đưa plan fix. KHÔNG SCP/sửa file trực tiếp trên VPS cho đến khi fix đã test trên kufi + Sếp approve.
- **Numbers trace to a command.** Every latency/throughput figure in the PDF comes from a command you ran and can paste. No hand-waving.

## 1. Pipeline

```
MR branch ─► clone + read diff (metadata, --stat, full patch)     # what actually changed
          ─► DEPLOYABILITY gate (real build/deploy cmd, migrations) # §2 — blockers first
          ─► CONVENTION gate (repo AGENTS.md doctrine)              # §3
          ─► reproduce on running env (benchmark, behavior)         # §4 — measure, don't trust
          ─► UNIT TEST gate (existing pass? pure fns tested?)       # §5
          ─► write HTML from references/report-template.html        # business-brief design system
          ─► scripts/build-report.sh <file.html>                    # WeasyPrint → PDF + page count
          ─► pdftoppm -png -r 96 → read cover/table pages           # VISUAL verify
          ─► cp *.pdf ~/Downloads/ ; WAIT for approval              # deliver, do not merge
```

Fixes you make while reviewing (blocker patches, missing tests) land on a dedicated
**`review/<mr-name>`** branch off the personal integration branch — never on the MR or master.

## 2. Deployability gate (blockers — check every one)

- **Build with the REAL command.** `encore build` / `encore test` / `npm run build` / `docker build` — whatever the project deploys with. A plain compiler is not enough.
- **Encore app id:** `be/encore.app` must carry a non-empty `"id"`. Blank → all codegen (`rlog`, `auth.Data`, secrets) goes undefined; the VPS also derives the DB container name from it. `scripts/check-deployability.sh` flags this.
- **Migration number collisions:** two files with the same numeric prefix (across the MR *and* the target branch) = deploy death. Git merges them silently (different filenames); the migration runner rejects a "duplicate migration identifier" and `schema_migrations` holds one version. Diff the whole migrations dir of MR-vs-target, not just new files. `scripts/check-deployability.sh` lists duplicate prefixes.
- **Lineage drift when porting to a mirror:** if the target repo numbers migrations differently from the deployed tree, the same change carries two numbers → double-apply on the next merge. `diff -rq` both migration trees before trusting file names.

## 3. Convention gate (read the repo's `AGENTS.md` first)

Score each against the project's own doctrine. For this repo (`agentic-cloudgo`): DB-driven knobs default-OFF (no env flags); no regex/string post-processing (eino primitives only); frozen CRM wire contract untouched; behavior→prompt not code. Mark each ✓/⚠/✗ with the file:line evidence. A second convention beside an existing one is a finding.

## 4. Reproduce on the running env (the heart of the review)

- **Measure what the user feels.** For a streaming endpoint that's time-to-first-token, reported apart from total — everything after ttft arrives while they read. `references/stream-bench.py` is a template SSE timer (handles the Cloudflare `1010` bare-agent block, reads the server's own `usage.timings` from the `done` frame).
- **Find the entrypoint honestly.** Trace the route → handler → the function the MR changed. Confirm the changed path is the one your test hits.
- **Check the premise, not just the delta.** Is the thing the MR optimizes even present in this env? (Empty KB → no pre-ground bloat → the optimization targets a cost that isn't there — or a *different* cost that is.)
- **Regression check on the real lane.** Exercise the changed lane end-to-end; confirm the tools/behavior that should survive do.

## 5. Unit test gate

- **Existing tests must actually run.** Beware harness traps: on Encore, `-tags localtest` makes the parser generate against a different package set than the compiler sees, so any runtime-touching package fails to build under the tag — the tests look present but never ran. Verify by running; if a whole test dir is dead, that's a finding.
- **Every pure function the MR adds gets a test.** `dropTools`, predicates, parsers — no runtime needed, no excuse. Test the invariant (the escape hatch that must survive, the identity case that preserves order), not just the happy path.

## 6. The PDF (business-brief design system)

Copy `references/report-template.html` — it IS the design system (navy/orange tokens, severity `.pill` p-red/amber/green, `table.cmp`, `.stat` boxes, `.callout`). Swap content, keep CSS. Skeleton: **Cover** (MR id, author, branch, env tested, scope) → **§0 Verdict** (one-sentence call + bullets) → **§1 What it changes** → **§2 Blockers** (pill table) → **§3 Benchmark** (`.stat` row + `table.cmp`, cite the harness) → **§4 Convention** → **§5 Tests** → **§6 Recommendation** (ordered, ending in "wait for approval"). Build:

```bash
su-code/skills/review-mr/scripts/build-report.sh my-review.html   # → my-review.pdf + page count
```

Then rasterize (`pdftoppm -png -r 96`) and actually *look* at the cover and one table page before delivering. See `su-code/skills/business-brief/SKILL.md` §4 for WeasyPrint gotchas.

## 7. Verify & deliver

Deliver the PDF to `~/Downloads/`, hand the path + one-line verdict to the user, and **stop**. The review branch is pushed to the personal repo only. NEVER advance to master/PROD/merge until the human says so — restate the current state (what's on the review branch, what is NOT on master/PROD) in the closing callout.

## 8. Housekeeping

After a validated new review pattern, fold the learning back into this `SKILL.md` and tick `CHANGELOG.md` (Unreleased) + a `validated:`/`failure:` line in `su-code/KNOWLEDGE.md`.

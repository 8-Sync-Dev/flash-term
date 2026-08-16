---
name: encore-migrations
description: >-
  Use for ANY database schema, seed, or config change in this Encore Go backend
  (backend/core/*/migrations/*.up.sql) — tables, columns, indexes, seeded rows
  (canned_responses, llm_providers/models/keys), runtime config. Encore AUTO-APPLIES
  only NEW sequential .up.sql files on deploy and NEVER re-runs an already-applied one,
  so an in-place edit silently drifts staging/prod from git. Two sanctioned paths:
  (1) add a new migration file, (2) consolidate/squash then reset+reinit. Read before
  touching migrations or running `encore db shell --write`.
---

# encore-migrations — change DB state without drifting prod (Encore Go)

> Adapted từ `ref/agentic-cloudgo-v1/agents/skills/encore-migrations` @ `8808d467`
> (doctrine generic Encore; project-specifics đổi về AcoLeads).

Encore tracks applied migrations in `schema_migrations(version, dirty)` and runs `up`
migrations **sequentially, once each**, on `encore run` (local) and every cloud deploy
(`git push encore-core main`). It NEVER re-runs an applied version. Docs:
https://encore.dev/docs/go/primitives/databases.

**The trap:** editing an applied `*.up.sql` only changes a *fresh* DB — staging/prod keep
the OLD content → git says one thing, the env does another. A later migration can also
overwrite an earlier one — **"latest applied migration wins", not "the file you edited".**

## Choose ONE of two options

### ▶ Option 1 — add a NEW migration file (DEFAULT; the only prod-safe path)
1. New file = `<N+1>_<short_name>.up.sql` in the service's `migrations/`
   (AcoLeads style: 4 số 0-pad, vd `backend/core/crm/migrations/0007_webchat.up.sql`).
2. Forward SQL only: schema → `CREATE/ALTER/DROP`; seed/config →
   `INSERT … ON CONFLICT (…) DO UPDATE` (idempotent) or targeted `UPDATE … WHERE …`.
   Nội dung dài (prompt/kernel) → dollar-quote `$TAG$…$TAG$` với tag không xuất hiện trong body.
3. Verify (below) → commit → `git push encore-core main` applies on deploy.
   **No `encore db shell --write`.**

### ▶ Option 2 — consolidate / squash (only when you CAN reset+reinit)
Local/dev or a coordinated wipe ONLY (deleting an applied file without reset →
"no migration found for version N").
1. **Backup migrations first** (`cp -r … migrations.bak-<date>`), audit overlaps,
   rewrite canonical files, then `encore db reset --all` locally → verify final state.
2. **☁️ Cloud reality:** CLI `db reset` has NO `--env` — cloud envs can't be reset by CLI.
   Reconcile instead: `schema_migrations` is a **single-row pointer** (`version,dirty`).
   To align: `DELETE FROM schema_migrations; INSERT INTO schema_migrations(version,dirty)
   VALUES (N,false);`. **NEVER `DELETE WHERE version IN (…)`** — emptying/partial rows
   makes the next deploy re-run `0001_init` → CREATE TABLE fails → deploy aborts.

Decision: live shared env + must keep data → **Option 1**. Disposable data → Option 2.

## Self-verify (mandatory gate, both options)
From `backend/core`:
- `encore check` — compiles + applies pending migrations locally; 0 errors.
- `encore db reset --all` — re-runs 1→N from scratch; proof the sequence lands the final state.
- `SELECT version, dirty FROM schema_migrations;` → version = max, `dirty=f`; spot-check rows.
- Contract behavior → `encore test ./...`.

## Debug
- Migration fails → Encore rolls back THAT migration and aborts the deploy. Fix SQL, push again.
- `dirty=t` → half-applied; fix SQL, it re-runs. Force re-run last (last resort):
  `UPDATE schema_migrations SET version = version - 1;`
- "no migration found for version N" locally → restart `encore daemon`, `encore db reset --all`.

## Project specifics (AcoLeads)
- DBs: `crm` (contacts/conversations/messages/leads/tickets/tasks/canned/inbound_events),
  `agent` (llm_providers/llm_models/llm_api_keys/agents), `chat` (sessions), `kb`.
- crm migrations hiện tại: `0001_init` … `0006_inbound_events` — số tiếp theo `0007_…`.
- Business values (models/providers/keys/seeds) live in seeds, never Go constants (AGENTS.md).
- Deploy = `git push encore-core main` (app `acoleads-core-2pfi`, staging). Migration lỗi = deploy abort (an toàn).
- bash heredocs bị chặn trong harness — build SQL bằng `write` tool rồi redirect `< file.sql`.

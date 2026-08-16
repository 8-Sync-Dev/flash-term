---
name: live-verify
description: >-
  Use this skill whenever a change must be PROVEN to work on the running
  farm-crm / Croptrace stack — i.e. any "sài thử", "test trên browser",
  "verify live", "browser test FE", "check encore log", FE/BE smoke or e2e
  verification. It drives the Next.js frontend through the oh-my-pi `browser`
  tool AND confirms the backend through Encore's structured logs + dev-dashboard
  traces. A claim is "verified" ONLY when BOTH the browser (what the user sees)
  AND the Encore log (what the server did) agree. Composes with `codegraph`
  (navigate first), never replaces it.
---

# live-verify — browser-test the FE + Encore-log the BE (farm-crm / Croptrace)

> **HARD MANDATE:** For ANY fix/dev/enhance on this stack, "done" = the running
> app proves it. Browser-drive the FE as a real user **and** read the Encore log
> for the same action. One source alone (only a screenshot, or only a curl) =
> guessing. NEVER declare "works" from a typecheck/build alone.
>
> **★ READ THE WHOLE EVIDENCE EVERY TURN:** after a browser action, `tab.observe()`
> (not just a screenshot) AND read the matching `[encore]` log lines (match by
> `trace_id`). Scan for non-`ok` codes, `unauthenticated`, 4xx/5xx, error toasts.
> Concluding "clean" from the first line/the happy bubble = a failed turn.
>
> **★ CODEGRAPH FIRST:** any symbol/path/endpoint lookup → `codegraph` (see
> `agents/skills/codegraph/SKILL.md`) BEFORE `search`/`read`/guess. State the
> `path:line` hit before opening a file.

---

## 0. Stack shape (read FIRST)
- **FE** — `frontend/web` (Next.js 16 + Turbopack, React 19). Dev on **:3000**.
  Server actions/route-handlers call the BE via `src/lib/actions/common/api-client.ts`
  (`ENCORE_API_URL` / `NEXT_PUBLIC_ENCORE_API_URL`, default `http://127.0.0.1:4000`).
  Auth is **cookie-based** (httpOnly `farm_at`/`farm_rt` set by server actions) — NOT
  a client Bearer header.
- **BE** — `backend/encore-module` (git submodule, Encore.ts + Drizzle + Postgres).
  `encore run` → API **:4000**, dev dashboard **:9400** (traces), MCP SSE :9900.
  5 SQL DBs (users/role/farming/inventory/crm) auto-provisioned via Docker.
- **One command:** `pnpm dev:all` (root) → `concurrently` runs `encore run` + `next dev`.
  (`dev:encore`, `dev:web` are the halves.)

## 1. Preflight (once per machine — all verified working)
- `encore` CLI on PATH: `export PATH="$HOME/.encore/bin:$PATH"` (already in `~/.bashrc`).
- **Docker running** (Encore provisions Postgres). `docker info` must succeed.
- **Local secret:** `backend/encore-module/.secrets.local.cue` with `JWT_SECRET: "<≥32 chars>"`
  (gitignored). Without it `encore run` can't start the auth service.
- **Local app-unlink:** `backend/encore-module/encore.app` must have `"id": ""` so `encore run`
  does NOT try to fetch cloud secrets for the linked app `farm-crm-01-h6r2-d392`
  (the logged-in account lacks access → `access denied`). ⚠️ This is a LOCAL-ONLY edit —
  NEVER commit it inside the submodule. Re-apply after any submodule update.
- **FE env:** `frontend/web/.env.local` (gitignored) — `ENCORE_API_URL=http://127.0.0.1:4000`
  plus R2 keys (`R2_ACCOUNT_ID/R2_BUCKET/R2_PUBLIC_BASE_URL/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY`)
  if testing image upload. **R2 needs S3 creds** (Access Key ID + Secret from Cloudflare R2 →
  Manage R2 API Tokens) — a `cfat_` *account* token does NOT work with the S3 API used by
  `src/lib/storage/r2.ts`.
- **Login (seeded by migration `2_create_admin` / `6_seed_uat_admin_user`):**
  `admin` / `admin123@`  ·  `uat_admin` / `admin123@`.
- **Fresh local DB has NO farming data** (only users + seeded locations). To exercise a
  data-dependent screen (timeline, PDF export, reports), CREATE the data via the UI first,
  or seed it — don't expect existing fields/seasons.

## 2. THE LOOP (self-driving)
```
1. GROUND   codegraph the symbol/route; read the FE component + BE controller
2. RUN      ensure pnpm dev:all is up (launch detached → logfile, §3)
3. DRIVE    oh-my-pi browser: login → navigate → act (§4)
4. OBSERVE  tab.observe()/screenshot  ⨉  read [encore] log by trace_id (§5)
5. ASSERT   BOTH agree: UI shows the change AND BE log shows code=ok / right call
6. CLEANUP  changelog/tests/docs LAST, gated on the smoke being green
            loop until DONE
```

## 3. Run & capture logs (so the agent can read them)
`pnpm dev:all` streams to the terminal; for a self-driving agent, launch **detached to a
logfile** so you can read BE + FE output later:
```bash
cd <repo-root>
setsid bash -c 'export PATH="$HOME/.encore/bin:$PATH" && exec pnpm dev:all' \
  >/tmp/dev-all.log 2>&1 </dev/null &
# health-check with curl (NOT /dev/tcp — that probe is unreliable here):
curl -s -m3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000   # 404 on / = up
curl -s -m3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000   # 307→/login = up
```
First `encore run` after a submodule bump re-runs migrations (fast; Postgres container persists).
Restart the stack after changing `.env.local` (Next reads it at boot).

## 4. Drive the FE (oh-my-pi `browser` tool)
- Open + log in (verified selectors):
  ```js
  // browser open name=app url=http://localhost:3000/login
  await tab.fill('aria/Số điện thoại, tên đăng nhập hoặc email', 'admin');
  await tab.fill('aria/Mật khẩu', 'admin123@');
  await tab.click('aria/Đăng nhập arrow_forward');     // fallback: tab.press('Enter',{selector:'aria/Mật khẩu'})
  await tab.waitForUrl(u => !u.includes('/login'), { timeout: 15000 }); // → /dashboard
  ```
- Prefer `tab.observe()` (structured roles/names/ids) over screenshots for state &
  selectors; `tab.screenshot()` only when visual appearance matters (and to show the user).
- Sidebar routes: Vùng trồng, Quy trình, Nhật ký (timeline), Xét nghiệm, Báo cáo, Sản phẩm…
- **Popups** (PDF export uses `window.open` + `print()`): handle the new target/page; in
  headless `print()` is a no-op — assert the generated HTML/markup, not a print dialog.
  For pure HTML-report logic prefer the exported pure builder (e.g. `buildFieldReportHTML`
  in `src/lib/utils/export.ts`) in a throwaway Bun script — faster than DOM-driving.
- **Role-play a real user** — vague/partial/out-of-order input, not a perfect script.

## 5. Confirm the BE (Encore log — the other half)
Encore logs every request as structured lines (prefixed `[encore]` in the dev-all log):
```
INF starting request  endpoint=listFields service=farming trace_id=… uid=01K9…ADMIN1
INF request completed  code=ok duration=2.38 endpoint=listFields service=farming trace_id=…
DBG auth handler returned unauthenticated endpoint=myAuthHandler service=auth trace_id=…
```
- **Read the log** with the `read` tool on `/tmp/dev-all.log` (NOT `grep`/`tail` pipelines for
  inspection). One FE action fans out to several BE calls sharing a `trace_id` — correlate by it.
- **Assert:** the expected `endpoint=`/`service=` fired, `code=ok` (not `unauthenticated`/
  `code=` error), sane `duration`, correct `uid`.
- **Visual traces:** open `http://127.0.0.1:9400` in the browser tool (payloads, timing, SQL).
- **Direct API probe** (BE in isolation): `curl :4000`. Login works headerless:
  `curl -s -X POST :4000/auth/login -d '{"username":"admin","password":"admin123@"}'` →
  `{success:true,result:{accessToken,refreshToken}}`. NOTE: authed endpoints expect the FE's
  cookie/session scheme — a raw `Authorization: Bearer <accessToken>` is rejected
  (`Token không được hỗ trợ`); verify authed flows through the browser (cookies), not raw curl.

## 6. DECISION GATES — stop & ask
- Screen needs farming data the fresh DB lacks → ask to seed/create, don't fake a pass.
- R2 image upload but no valid S3 Access Key ID + Secret in `.env.local` → ask for them
  (the route throws `Chưa cấu hình R2`). A `cfat_` account token is NOT S3 creds.
- Widget/route unreachable, or login fails for both seeded users.
- A change would require committing the local `encore.app` unlink / `.secrets.local.cue`.

## 7. Anti-patterns (cause false "done")
- Declaring success from a screenshot alone (BE may have 500'd) or a curl alone (UI may not render).
- Concluding "clean" from the first log line / happy bubble without reading the whole reply + trace.
- Probing authed endpoints with raw Bearer curl and calling a 401 a "bug" (use the cookie/browser path).
- Editing a guessed path without `codegraph` first.
- Committing the local-only `encore.app` id-unlink or `.secrets.local.cue` / `.env.local` (all local).
- Using the `/dev/tcp` port probe to gate readiness (unreliable here) — use `curl`.

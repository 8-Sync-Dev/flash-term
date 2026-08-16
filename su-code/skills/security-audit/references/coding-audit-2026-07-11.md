# Coding product — security audit findings (2026-07-11)

Scope: `coding.8syncdev.com` = `apps/coding` (Next.js, client-only playground + BFF)
+ `backend/8sync-core/coding` (Encore Go product API) + `backend/gate` (auth/billing BFF)
+ `backend/judge` (sandboxed grader) + `backend/shared/crypto` (JWT + password).

Reviewer question (owner): can problems be **copied/scraped**, can traffic be
**MITM'd/decrypted to steal problems**, is there **DoS/DDoS** exposure, and does it
pass **OWASP Top 10**. This is a defensive audit of our own product.

---

## Verdict

**Overall posture: strong.** The valuable IP (hidden grader tests + reference
solutions) is server-gated and never leaks; SQL is fully parameterized; auth is a
correctly-implemented HS256 JWT with no alg-confusion; CORS is origin-restricted;
code execution is sandboxed. The real gaps are **operational hardening**, not broken
crypto or access control: no app-level rate limiting on the *public/auth* endpoints,
committed dev-secret fallbacks, and missing FE security headers.

Published problem **statements are public by design** (SEO-indexed, `robots: index:true`
in `apps/coding/src/app/layout.tsx:41`). You cannot cryptographically prevent copying
content you serve to every browser — accept it as marketing surface and focus the
defense on the *unpublished* value (hidden tests + solutions), which is already protected.

---

## What's already correct (keep it)

| Area | Evidence |
|---|---|
| Hidden grader tests never sent to public | `coding/coding.go:117 stripHidden`, called in `listProblemsFor:165` / `getProblemFor:192` |
| Reference solution triple-gated (auth + Pro + private-access) | `coding/coding.go:215-235 getSolutionFor` |
| Private problems degrade to 280-rune teaser | `coding/access.go:95 teaserStatementRunes`, `112 teaserProblem` |
| Client `passed` never trusted — server re-grades | `coding/submit.go:16-17`, `submitGraded:379-396` |
| Hidden-case stdout/error stripped from results | `coding/submit.go:24-26 CaseResultDTO` |
| JWT verify is HS256-only, immune to alg-confusion (`none`/RS256 fail the HMAC compare; header alg never trusted) | `shared/crypto/jwt.go:63-84 Verify` |
| Password = scrypt (N=16384,r=8,p=1,64B) + constant-time compare | `shared/crypto/password.go:20-26,49-59` |
| Login has no account enumeration (same msg for no-user vs bad-pass) | `gate/auth/auth.go:88-98` |
| SQL fully parameterized ($1,$2…), no string-built queries | `coding/*.go`, `gate/auth/auth.go:79-86,140-145` |
| CORS restricted to 8syncdev.com + localhost, not wildcard | `backend/*/encore.app global_cors.allow_origins_with_credentials` |
| Code execution sandboxed (wall-clock kill + 64 MiB linear-memory cap) | `coding/submit.go:382`, `run.go:20-21` |
| Server-authoritative game state (localStorage tamper doesn't grant XP) | `apps/coding/src/lib/game/store.ts:47-49` server-wins reconcile |
| BFF keeps API base + token server-side (not in client bundle) | `apps/coding/next.config.ts:8-10`, `@8sync/bff` |
| Admin actions audit-logged | `coding/coding.go:634 writeAudit`, `gate/auth/auth.go:89,96,156` |
| TLS in transit (Encore Cloud managed certs) → packet capture can't decrypt | platform; `docs/01-ARCHITECTURE.md:236` |

---

## Findings (ranked)

### F1 — LOW (verified latent) · committed dev-secret fallback (A02/A05)
`jwtSecret()` and `judgeSecret()` fall back to committed defaults
`"dev-insecure-change-me"` / `"dev-judge-secret"` when the Encore secret + env are
both empty (`coding/config.go:16-19,31-33,48-50`; same in `gate/`, `news/`,
`judge/grade/config.go`). If a cloud env were ever deployed with the secret unset, all
JWTs would become forgeable (→ admin impersonation → read every solution/hidden test)
and the judge would accept any caller.

**Verified 2026-07-11 (`encore secret list`):** `AuthJWTSecret` (gate+core),
`JudgeSecret` (core+judge), `JudgeURLCompiled` (core) are **all set in Production,
Development, and Preview** — unset only for Local (correct; local uses the dev fallback
by design). So the dev default is **unreachable in any cloud env today**. This is a
latent misconfig risk, not a live exposure.

### F2 — HIGH · no rate limiting / brute-force protection on auth (A07 + DoS)
`Login` and `Register` are `//encore:api public` with **no throttle**
(`gate/auth/auth.go:75-105,117-158`). Two consequences:
1. **Credential brute-force**: unlimited password guesses per account.
2. **CPU-exhaustion DoS**: every login/register triggers scrypt (N=16384 ≈ 16 MB,
   tens of ms of CPU). An unauthenticated flood of `/auth/login` forces expensive
   server work with no cap → cheap DoS.

Authenticated endpoints ARE capped (`submit` daily-10 free `submit.go:58,374`; `run`
30/min/user `run.go:26,56-73`) — the gap is specifically the *pre-auth* surface.

**Fix:** per-IP sliding-window limiter on `/auth/login` + `/auth/register` (mirror
`run.go allowRun`, keyed on client IP), e.g. 10 login attempts / 5 min / IP, plus a
short lockout after N failures per account. Consider a CAPTCHA on register.

### F3 — MEDIUM · unbounded public catalog read enables one-shot scrape (A04)
`GET /coding/problems` returns **every published problem** in one unauthenticated,
unpaginated response (`coding/coding.go:143-168`). The full catalog (600+) is
harvestable in a single request. Statements are public by design, but the lack of
pagination + rate limit makes bulk mirroring trivial and cheap.

**Fix:** paginate the public list (limit/offset or cursor) and add a per-IP rate limit
at the edge. Does not stop a determined scraper (public content), but removes the
one-request full-dump and raises cost.

### F4 — MEDIUM · no FE security headers (A05)
No `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, or
`Referrer-Policy` set in any `apps/*/next.config.*` or shared config
(`apps/coding/next.config.ts` has none). Vercel sets HSTS by default, but the missing
CSP + `X-Frame-Options` widen the blast radius of any XSS and allow clickjacking. The
JWT lives in `localStorage` (ADR-020), so an XSS = token theft.

**Fix:** add a shared `async headers()` to the Next config returning
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
`Referrer-Policy: strict-origin-when-cross-origin`, and a CSP. React auto-escaping
already covers reflected XSS; CSP is the second layer.

### F5 — LOW · password policy is length-only (A07)
`Register` enforces min-8 length only (`gate/auth/auth.go:123-124`) — no breach-list
check (HIBP k-anonymity) and no complexity. Acceptable baseline; note for later.

---

## Concern-by-concern answer (owner's exact questions)

- **"Không copy được đề"** — hidden tests + solutions: **protected** (F-none, server-gated).
  Public statements: **inherently copyable** (SEO-public by design). F3 slows bulk scrape.
- **"Tấn công request lấy gói tin giải mã lấy đề"** — TLS 1.2/1.3 (Encore managed) makes
  packet-capture decryption infeasible; nothing sensitive travels unencrypted. **Safe.**
- **"DDoS / DoS"** — authed endpoints capped; **pre-auth surface uncapped** (F2 High, F3).
  No WAF/edge rate-limit in front. Add per-IP limits (F2/F3) and consider Cloudflare.
- **"OWASP Top 10"** — A01 strong, A02 F1, A03 clean, A04 F3, A05 F1+F4, A06 (run
  `go/npm audit`), A07 F2+F5, A08 audit-logged, A09 present, A10 no user-URL fetch (clean).

---

## Non-issues / by-design (do not "fix")
- Public problem statements are served to browsers — cannot be DRM'd. Marketing surface.
- localStorage game save — server is authoritative; tampering grants nothing.
- Client-side "run" for js/ts/py in-browser (ADR-013) — no server cost, no secret exposed.

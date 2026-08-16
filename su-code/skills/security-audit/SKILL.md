---
name: security-audit
description: Repeatable defensive security audit for the 8syncdev product (Encore Go backend + Next.js FE + sandboxed judge). Use to check whether problems/content can be scraped or copied, whether traffic can be MITM'd/decrypted, whether DoS/DDoS is possible, and to run an OWASP Top 10 pass. Produces a severity-ranked findings report with file:line evidence and concrete fixes. Complements the generic senior-security and security-and-hardening skills with this repo's exact trust boundaries and known-good baseline.
---

# Security Audit (8syncdev product)

A **defensive** audit of our own stack — never framed as offensive pentesting.
Generic theory lives in `../senior-security/` (STRIDE, DREAD) and
`../security-and-hardening/` (OWASP prevention patterns). This skill is the
**repo-specific playbook**: what to check, where, and what "good" looks like here.

> Do the audit yourself by reading code. Do **not** delegate the read to a subagent
> — cyber-safeguards refuse audit-framed subagent tasks. Reading your own source to
> harden it is legitimate; keep the framing defensive ("verify X is enforced").

## Trust boundaries (this stack)

```
Browser ──TLS──> FE (apps/*, Vercel) ──BFF (@8sync/bff, server-side)──> Encore Cloud
                                                                          ├─ gate/   (auth, billing) — signs HS256 JWT
                                                                          ├─ 8sync-core/coding (product API) — verifies JWT
                                                                          ├─ news/   (feed) — verifies JWT
                                                                          └─ judge/  (sandboxed grader) — X-Judge-Secret
```

- **Assets worth protecting:** hidden grader tests, reference solutions, private
  problems, admin actions, user credentials, plan/entitlement, the judge (arbitrary
  code execution sandbox). **Not** an asset: published problem statements — they are
  SEO-public by design and served to every browser.
- **Untrusted inputs:** every HTTP body/param, the JWT, submitted source code + stdin,
  billing webhooks, SAML assertions, LLM output in the forge pipeline.

## Audit lanes (map to the owner's recurring questions)

### Lane 1 — Anti-scrape / "copy được đề?"
Verify the *valuable* content is server-gated, and accept public statements are copyable.
- Hidden tests stripped from every public response → `coding/coding.go stripHidden`,
  used in `listProblemsFor` + `getProblemFor`.
- Solution behind auth **and** Pro **and** private-access → `coding/coding.go getSolutionFor`.
- Private → teaser only → `coding/access.go teaserProblem`.
- Public list should paginate + be rate-limited (else one-shot full dump).
- Grep: `grep -n "stripHidden\|teaserProblem\|isPro\|requireAdmin\|canView" backend/8sync-core/coding/*.go`

### Lane 2 — Transport / "MITM lấy gói tin giải mã?"
- All external traffic over TLS (Encore Cloud + Vercel managed certs) → packet capture
  can't decrypt. Confirm no plaintext HTTP endpoint and no secret in query strings.
- Token at rest: JWT in `localStorage` (ADR-020) → XSS = token theft; check CSP (Lane 5).
- Inter-service secret (`X-Judge-Secret`) travels service-to-service inside Encore.

### Lane 3 — DoS / DDoS
- Authed cost-gates present? `submit` daily cap (`submit.go freeDailySubmitLimit`),
  `run` per-minute (`run.go allowRun`, `runRatePerMin`).
- **Pre-auth surface** (`/auth/login`, `/auth/register`, `GET /coding/problems`,
  `/coding/public/stats`) — is there ANY per-IP throttle? scrypt on login makes an
  unthrottled login flood a CPU-exhaustion vector.
- Input size caps on bodies (`run.go runMaxSourceBytes/runMaxStdinBytes`).
- Grep: `grep -rn "allowRun\|freeDailySubmitLimit\|RatePerMin\|limiter\|throttle" backend`

### Lane 4 — AuthN/AuthZ
- JWT verify must be alg-pinned: recompute HS256, never trust header `alg`
  (`shared/crypto/jwt.go Verify`). No RS256/`none` path.
- Password: scrypt/bcrypt/argon2 + constant-time compare (`shared/crypto/password.go`).
- Login must not enumerate accounts (identical error for no-user vs bad-pass).
- Every authed endpoint scopes by `d.UserID` from the token, never a client-supplied id
  (IDOR check). Admin endpoints call `requireAdmin`.

### Lane 5 — Config / secrets / headers
- Secrets via `encore secret set --type prod,dev,pr` — NEVER `--type local` for shared
  secrets. Flag committed dev-default fallbacks (`dev-insecure-change-me`,
  `dev-judge-secret`, `dev-ops-token`): safe only if the cloud secret is provably set.
- CORS restricted (not `*`) → `backend/*/encore.app global_cors`.
- FE security headers (CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy)
  in `apps/*/next.config.*`.
- Secret scan: `grep -rnE "(secret|password|api[_-]?key|token)\s*[:=]\s*[\"'][^\"']{8,}" --include=*.go --include=*.ts backend apps | grep -vi "dev-\|example\|process.env\|os.Getenv\|json:"`

### OWASP Top 10 checklist (2021)
| ID | Focus here | Verify |
|---|---|---|
| A01 Broken Access Control | IDOR, admin gates, Pro gate | `requireAdmin`, `isPro`, `canView`, UID from JWT |
| A02 Crypto Failures | JWT alg, password KDF, TLS, dev-secret fallback | jwt.go/password.go, `encore secret list` |
| A03 Injection | SQL params, code-exec sandbox, no eval/innerHTML | `$1` placeholders, judge memory/wall caps |
| A04 Insecure Design | teaser/gate model, pagination, abuse cases | access.go, list pagination |
| A05 Misconfig | CORS, dev-secret fallback, security headers | encore.app, next.config |
| A06 Vulnerable Components | dep CVEs | `go list -m all` + `npm audit` / `pnpm audit` |
| A07 Auth Failures | brute-force, enumeration, password policy | rate-limit on login, identical errors |
| A08 Integrity | audit log, judge secret, migration seeds | writeAudit, X-Judge-Secret |
| A09 Logging | security events logged, no secrets in logs | login.failed audit, no password logging |
| A10 SSRF | any user-controlled outbound URL | judge URL is server-config, not user input |

## Severity rubric
`Impact × Exploitability` (see `../senior-security/` matrix). Rank Critical→Low; every
finding cites `path:line` and carries a concrete, copy-pasteable fix. Separate
**by-design non-issues** (public statements, localStorage game save) so they aren't
re-flagged each run.

## Run it
1. `bash agents/skills/security-audit/scripts/audit.sh` — automatable checks (CORS,
   dev-secret fallback usage, rate-limit presence, secret scan, FE headers, deps).
2. Read the flagged files and apply the five lanes + OWASP table by hand.
3. Write findings to `agents/skills/security-audit/references/coding-audit-<date>.md`
   (severity, evidence, fix). Latest baseline: `references/coding-audit-2026-07-11.md`.

## Output contract
Markdown report: **Verdict** → **Already correct (keep)** → **Findings (ranked, with
fix)** → **Concern-by-concern answer** → **By-design non-issues**. Cite `path:line` on
every claim. State what is ABSENT explicitly.

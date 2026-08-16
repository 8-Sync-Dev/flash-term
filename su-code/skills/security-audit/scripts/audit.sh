#!/usr/bin/env bash
# Defensive security audit — automatable checks for the 8syncdev product.
# Reads only; prints PASS/WARN/FAIL per check. Manual review still required
# (see ../SKILL.md lanes + OWASP table). Run from repo root.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
BE=backend
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$1"; }
fail(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
hdr(){ printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

hdr "Lane 5 — CORS not wildcard"
if grep -rn '"\*"' $BE/*/encore.app 2>/dev/null | grep -q origin; then
  fail "wildcard origin in an encore.app"
else
  n=$(grep -rl "allow_origins_with_credentials" $BE/*/encore.app 2>/dev/null | wc -l)
  pass "origin-restricted CORS in $n encore.app files"
fi

hdr "Lane 5 — committed dev-secret fallback (F1)"
hits=$(grep -rnE 'dev-insecure-change-me|dev-judge-secret|dev-ops-token' $BE --include=*.go 2>/dev/null | grep -c 'devJWTSecret\|devJudgeSecret\|devOpsToken\|= "dev-')
if [ "$hits" -gt 0 ]; then
  warn "dev-secret defaults present ($hits) — OK only if cloud secret is provably set:"
  echo "       verify: (cd $BE/gate && encore secret list --env=production | grep -i jwt)"
  echo "       harden: boot-guard that panics when cloud env + resolved secret == dev default"
else
  pass "no dev-secret fallback"
fi

hdr "Lane 4 — JWT alg pinning (no alg-confusion)"
if grep -q 'signHS256(secret, parts\[0\]' $BE/shared/crypto/jwt.go 2>/dev/null \
   && ! grep -qE 'header\.Alg|claims?\.alg|"RS256"|"none"' $BE/shared/crypto/jwt.go 2>/dev/null; then
  pass "Verify recomputes HS256, never trusts header alg"
else
  warn "review shared/crypto/jwt.go Verify for alg handling"
fi

hdr "Lane 4 — password KDF + constant-time compare"
if grep -q 'scrypt.Key' $BE/shared/crypto/password.go 2>/dev/null \
   && grep -q 'ConstantTimeCompare' $BE/shared/crypto/password.go 2>/dev/null; then
  pass "scrypt + constant-time compare"
else
  fail "password hashing not scrypt/bcrypt/argon2 or non-constant-time compare"
fi

hdr "Lane 4 — login account-enumeration"
if grep -q 'no_user' $BE/gate/auth/auth.go 2>/dev/null; then
  same=$(grep -c 'Sai tên đăng nhập hoặc mật khẩu' $BE/gate/auth/auth.go 2>/dev/null)
  [ "$same" -ge 2 ] && pass "identical error for no-user and bad-pass ($same)" \
                     || warn "login errors may differ — check enumeration"
fi

hdr "Lane 3 — rate limiting"
grep -q 'allowRun' $BE/8sync-core/coding/run.go 2>/dev/null && pass "run: per-user rate limit" || warn "run rate limit missing"
grep -q 'freeDailySubmitLimit' $BE/8sync-core/coding/submit.go 2>/dev/null && pass "submit: daily quota" || warn "submit quota missing"
if grep -qiE 'limiter|throttle|rate' $BE/gate/auth/auth.go 2>/dev/null; then
  pass "auth endpoints reference a limiter"
else
  fail "F2: no rate limit on /auth/login|register (brute-force + scrypt-DoS)"
fi

hdr "Lane 1/3 — public catalog pagination"
if grep -qiE 'limit|offset|cursor' $BE/8sync-core/coding/coding.go 2>/dev/null | grep -qi 'listProblems'; then
  pass "public list paginated"
else
  warn "F3: GET /coding/problems appears unpaginated — one-shot full-catalog dump"
fi

hdr "Lane 5 — FE security headers"
if grep -rlqE 'async headers|Content-Security-Policy|X-Frame-Options' apps/*/next.config.* 2>/dev/null; then
  pass "a next.config sets security headers"
else
  warn "F4: no CSP/X-Frame-Options/X-Content-Type-Options in any apps/*/next.config.*"
fi

hdr "Lane 5 — secret scan (hardcoded creds)"
s=$(grep -rnE '(secret|password|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}' \
      --include=*.go --include=*.ts $BE apps 2>/dev/null \
    | grep -viE 'dev-|example|process\.env|os\.Getenv|json:|NEXT_PUBLIC|header:|// ' | head -20)
[ -z "$s" ] && pass "no obvious hardcoded long secrets" || { warn "review candidates:"; echo "$s"; }

hdr "A06 — dependency CVE scan (run manually)"
echo "  go:   (cd $BE/8sync-core && go list -m all)  # cross-check govulncheck"
echo "  node: pnpm audit --prod"

printf '\n\033[1mManual review still required — see ../SKILL.md lanes + OWASP table.\033[0m\n'

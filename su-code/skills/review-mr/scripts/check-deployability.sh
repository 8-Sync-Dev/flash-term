#!/usr/bin/env bash
# review-mr deployability gate — the cheap checks that catch the expensive
# blockers. Run from the repo root of the MR checkout. Exit non-zero on any hard
# blocker so it can gate a pipeline; warnings do not fail.
#
# Usage: check-deployability.sh [be_dir]
#   be_dir defaults to "be" (the Encore app root). Pass "." for non-Encore repos.
set -uo pipefail
BE="${1:-be}"
fail=0

echo "=== 1. encore.app app id ==="
if [ -f "$BE/encore.app" ]; then
  id=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$BE/encore.app" | sed -E 's/.*"id"[^"]*"([^"]*)".*/\1/')
  if [ -z "$id" ]; then
    echo "  BLOCKER: be/encore.app has an empty id — every encore command will fail codegen."
    fail=1
  else
    echo "  ok: id=$id"
  fi
else
  echo "  (no encore.app — skipping; not an Encore app root)"
fi

echo "=== 2. duplicate migration numeric prefixes ==="
dupes=0
while IFS= read -r d; do
  [ -d "$d" ] || continue
  dup=$(ls "$d"/*.up.sql 2>/dev/null | sed 's|.*/||' | cut -d_ -f1 | sort -n | uniq -d)
  if [ -n "$dup" ]; then
    echo "  BLOCKER in $d — duplicate prefixes: $(echo "$dup" | tr '\n' ' ')"
    dupes=1; fail=1
  fi
done < <(find "$BE" -type d -name migrations 2>/dev/null)
[ "$dupes" = 0 ] && echo "  ok: no duplicate migration prefixes"

echo "=== 3. accidental secrets in the diff ==="
sec=$(grep -rnoE "ak_live_[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH) PRIVATE KEY" "$BE" 2>/dev/null \
      | grep -viE "test|fixture|example|contract-test" | head -5)
if [ -n "$sec" ]; then
  echo "  WARN: possible real secret(s) — verify by hand:"; echo "$sec" | sed 's/^/    /'
else
  echo "  ok: no obvious live secrets outside test fixtures"
fi

echo
if [ "$fail" = 0 ]; then
  echo "DEPLOYABILITY: no hard blockers found (still run the REAL build/deploy command)."
else
  echo "DEPLOYABILITY: HARD BLOCKER(S) present — must fix before merge."
fi
exit "$fail"

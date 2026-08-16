#!/usr/bin/env bash
# render_paper.sh — render a Markdown paper to PDF via report-github-md2pf's academic theme,
# then report the page count and gate it against a target (used by the write-paper skill).
#
# Usage: render_paper.sh <input.md> <output-dir> [theme] [target-pages]
#   theme         default: academic  (business|report|contract|academic)
#   target-pages  optional; flags PAGE-GATE if the PDF is outside target ±1
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <input.md> <output-dir> [theme=academic] [target-pages]" >&2
  exit 2
fi

IN=$1
OUTDIR=$2
THEME=${3:-academic}
TARGET=${4:-}

# Repo root resolved from this script's location (.../agents/skills/write-paper/scripts).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../../.." && pwd)

[ -f "$IN" ] || { echo "error: input not found: $IN" >&2; exit 1; }
IN_ABS="$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")"
mkdir -p "$OUTDIR"
OUT_ABS="$(cd "$OUTDIR" && pwd)"
PDF="$OUT_ABS/$(basename "${IN%.md}").pdf"

echo "[write-paper] rendering $IN_ABS --theme $THEME -> $OUT_ABS"
( cd "$REPO_ROOT" && uv run git-report "$IN_ABS" --theme "$THEME" -o "$OUT_ABS" ) \
  2>&1 | grep -vE '^warning:|dev-dependencies' || true

[ -f "$PDF" ] || { echo "error: expected PDF not produced: $PDF" >&2; exit 1; }

PAGES=""
if command -v pdfinfo >/dev/null 2>&1; then
  PAGES=$(pdfinfo "$PDF" 2>/dev/null | awk '/^Pages:/ {print $2}')
fi
SIZE=$(wc -c < "$PDF")
echo "[write-paper] PDF created: $PDF (${SIZE} bytes, Pages: ${PAGES:-?})"
[ "${SIZE:-0}" -gt 0 ] || { echo "error: empty PDF" >&2; exit 1; }

if [ -n "$TARGET" ] && [ -n "$PAGES" ]; then
  lo=$((TARGET - 1)); hi=$((TARGET + 1))
  if [ "$PAGES" -ge "$lo" ] && [ "$PAGES" -le "$hi" ]; then
    echo "[write-paper] PAGE-GATE OK: $PAGES within target $TARGET ±1"
  else
    echo "[write-paper] PAGE-GATE ADJUST: $PAGES vs target $TARGET (±1). Expand/trim per ieee-format.md §3." >&2
  fi
fi

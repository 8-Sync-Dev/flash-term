#!/usr/bin/env bash
# build_latex.sh — compile a LaTeX paper (e.g. IEEEtran) to PDF for the write-paper skill's
# standardized/camera-ready backend. Prefers a self-contained XeTeX engine (tectonic →
# Unicode/Vietnamese via fontspec, no system TeX install) and auto-provisions tectonic to
# ~/.local/bin if no LaTeX engine is found. tectonic fetches its package bundle on first run
# (network) and caches it thereafter.
#
# Usage: build_latex.sh <input.tex> <output-dir> [target-pages]
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <input.tex> <output-dir> [target-pages]" >&2
  exit 2
fi

IN=$1
OUTDIR=$2
TARGET=${3:-}

[ -f "$IN" ] || { echo "error: input not found: $IN" >&2; exit 1; }
IN_ABS="$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")"
mkdir -p "$OUTDIR"
OUT_ABS="$(cd "$OUTDIR" && pwd)"
PDF="$OUT_ABS/$(basename "${IN%.tex}").pdf"

export PATH="$HOME/.local/bin:$PATH"

# Pick an engine (all XeTeX-capable for Unicode/Vietnamese).
ENGINE=""
if command -v latexmk >/dev/null 2>&1; then ENGINE=latexmk
elif command -v tectonic >/dev/null 2>&1; then ENGINE=tectonic
elif command -v xelatex >/dev/null 2>&1; then ENGINE=xelatex
fi
if [ -z "$ENGINE" ]; then
  echo "[write-paper] no LaTeX engine found; installing tectonic to ~/.local/bin ..." >&2
  mkdir -p "$HOME/.local/bin"
  ( cd "$HOME/.local/bin" && curl --proto '=https' --tlsv1.2 -fsSL https://drop-sh.fullyjustified.net | sh ) >&2
  ENGINE=tectonic
fi

echo "[write-paper] compiling $IN_ABS with $ENGINE -> $OUT_ABS"
case "$ENGINE" in
  tectonic) tectonic -o "$OUT_ABS" "$IN_ABS" ;;
  latexmk)  ( cd "$(dirname "$IN_ABS")" && latexmk -xelatex -interaction=nonstopmode -outdir="$OUT_ABS" "$IN_ABS" ) ;;
  xelatex)  ( cd "$(dirname "$IN_ABS")" \
              && xelatex -interaction=nonstopmode -output-directory="$OUT_ABS" "$IN_ABS" \
              && xelatex -interaction=nonstopmode -output-directory="$OUT_ABS" "$IN_ABS" ) ;;
esac

[ -f "$PDF" ] || { echo "error: expected PDF not produced: $PDF" >&2; exit 1; }
PAGES=""
command -v pdfinfo >/dev/null 2>&1 && PAGES=$(pdfinfo "$PDF" 2>/dev/null | awk '/^Pages:/ {print $2}')
SIZE=$(wc -c < "$PDF")
echo "[write-paper] PDF created: $PDF (${SIZE} bytes, Pages: ${PAGES:-?})"
[ "${SIZE:-0}" -gt 0 ] || { echo "error: empty PDF" >&2; exit 1; }

if [ -n "$TARGET" ] && [ -n "$PAGES" ]; then
  lo=$((TARGET - 1)); hi=$((TARGET + 1))
  if [ "$PAGES" -ge "$lo" ] && [ "$PAGES" -le "$hi" ]; then
    echo "[write-paper] PAGE-GATE OK: $PAGES within target $TARGET ±1"
  else
    echo "[write-paper] PAGE-GATE ADJUST: $PAGES vs target $TARGET (±1). Tighten/expand per ieee-format.md." >&2
  fi
fi

#!/usr/bin/env bash
# Compile a LaTeX paper -> PDF using tectonic (self-contained; fetches classes,
# .bst and packages from CTAN on demand, runs BibTeX automatically).
# Usage: build.sh <paper.tex> [outdir]
#   default outdir = ./build   ·   refs.bib must sit next to <paper.tex>
set -euo pipefail

in="${1:?usage: build.sh <paper.tex> [outdir]}"
[ -f "$in" ] || { echo "no such file: $in" >&2; exit 1; }
srcdir="$(cd "$(dirname "$in")" && pwd)"
base="$(basename "${in%.tex}")"
outdir="${2:-build}"

command -v tectonic >/dev/null 2>&1 || {
  echo "tectonic not found. Install: cargo install tectonic  (or download a release binary)." >&2
  echo "Fallback if you have TeXLive: latexmk -pdf -bibtex \"$in\"" >&2
  exit 127
}

mkdir -p "$outdir"
# tectonic needs the outdir to exist; -Z shell-escape not required for these templates.
# 2>/dev/null on fontconfig noise would also hide real errors, so keep stderr but tag it.
tectonic -X compile "$in" \
  --outdir "$outdir" \
  --keep-logs \
  2> >(grep -vE '^Fontconfig warning' >&2)

pdf="$outdir/$base.pdf"
[ -f "$pdf" ] || { echo "build failed: no $pdf" >&2; exit 1; }
echo "rendered -> $pdf"

# Page count (a conference paper has a hard page limit — never ship over it blindly).
if command -v pdfinfo >/dev/null 2>&1; then
  pdfinfo "$pdf" | awk '/^Pages:/{print "pages: "$2}'
fi

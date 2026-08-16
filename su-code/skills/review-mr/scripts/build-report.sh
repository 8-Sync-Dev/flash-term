#!/usr/bin/env bash
# Render a review-mr report HTML -> PDF (WeasyPrint) + page count.
# Usage: build-report.sh <input.html> [output.pdf]
set -euo pipefail
in="${1:?usage: build-report.sh <input.html> [output.pdf]}"
[ -f "$in" ] || { echo "no such file: $in" >&2; exit 1; }
out="${2:-${in%.html}.pdf}"
uv run --with weasyprint python -m weasyprint "$in" "$out"
echo "rendered -> $out"
uv run --with pypdf python -c "from pypdf import PdfReader as R;print('pages:', len(R('$out').pages))"

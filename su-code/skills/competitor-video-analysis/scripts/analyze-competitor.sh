#!/usr/bin/env bash
# Phân tích 1 video đối thủ → báo cáo "học theo" (hook/cấu trúc/CTA/điểm ăn cắp được).
# Dùng engine watch-skill (references/watch-skill) — transcript + OCR + retrieval local.
# Usage: analyze-competitor.sh <video_url|file> [start] [end]
#   start/end: cắt đoạn (vd 0:30 2:00) để phân tích sâu 1 khúc.
# Output: outputs/competitor-<video_id>.md (+ để hỏi thêm: watch-skill ask <id> "...")
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
WS="$REPO_ROOT/references/watch-skill"
[ -d "$WS" ] || { echo "❌ Chưa có references/watch-skill — chạy: git submodule update --init references/watch-skill && cd $WS && uv sync --extra perceive --extra ocr --extra whisper --extra index --extra mcp" >&2; exit 1; }

URL="${1:?usage: analyze-competitor.sh <video_url|file> [start] [end]}"
START="${2:-}"; END="${3:-}"
OUTDIR="$REPO_ROOT/outputs"; mkdir -p "$OUTDIR"

run() { ( cd "$WS" && uv run watch-skill "$@" ); }

# 1. WATCH (index video). Cắt đoạn nếu có start/end.
WARGS=(watch "$URL")
[ -n "$START" ] && WARGS+=(--start "$START")
[ -n "$END" ]   && WARGS+=(--end "$END")
echo "▶ watch: $URL ${START:+[$START-$END]}" >&2
WLOG="$(run "${WARGS[@]}" 2>/dev/null | grep -viE 'WARNING|impersonat|av1 @|pixel format|frame error')" || true
VID="$(printf '%s' "$WLOG" | grep -oE '[a-f0-9]{16}' | head -1)"
[ -n "$VID" ] || VID="$(run list 2>/dev/null | awk 'NR==1{print $1}')"
[ -n "$VID" ] || { echo "❌ Không index được video." >&2; exit 1; }
echo "  indexed: $VID" >&2

TITLE="$(run list 2>/dev/null | grep "$VID" | sed -E 's/^[a-f0-9]+ +[0-9.]+s +//' | head -1)"
OUT="$OUTDIR/competitor-$VID.md"

# 2. BATTERY câu hỏi — rút giá trị học theo (transcript + on-screen text).
declare -a Q=(
  "Hook 5 giây đầu là gì? Trích nguyên văn câu mở đầu."
  "Dàn ý/cấu trúc video: liệt kê các phần chính kèm timestamp."
  "Chiêu giữ chân (pattern interrupt, câu dẫn, tạo tò mò) nào được dùng?"
  "Call-to-action là gì và xuất hiện lúc nào? Trích nguyên văn."
  "Phong cách chữ on-screen / caption / thuật ngữ nổi bật?"
  "1 điều giá trị nhất mà mình có thể học theo / tái dụng ngay?"
  "Điểm yếu / lỗi cần TRÁNH khi mình làm lại?"
)
declare -a LBL=("HOOK" "CẤU TRÚC" "GIỮ CHÂN" "CTA" "STYLE/CHỮ" "HỌC THEO" "TRÁNH")

{
  echo "# Phân tích video đối thủ — học theo"
  echo
  echo "- **Video:** ${TITLE:-$VID} ($VID)"
  echo "- **Nguồn:** $URL ${START:+· đoạn $START–$END}"
  echo "- **Phân tích:** $(date +%Y-%m-%d) · engine watch-skill (transcript+OCR local)"
  echo "- **Hỏi thêm:** \`cd references/watch-skill && uv run watch-skill ask $VID \"...\"\`"
  echo
} > "$OUT"

for i in "${!Q[@]}"; do
  echo "  ask: ${LBL[$i]}" >&2
  ANS="$(run ask "$VID" "${Q[$i]}" 2>/dev/null | grep -viE 'WARNING|impersonat|av1 @|pixel format|frame error|verify pass unavailable' | sed '/^[[:space:]]*$/d')" || ANS="(không trích được)"
  {
    echo "## ${LBL[$i]}"
    echo "> ${Q[$i]}"
    echo
    printf '%s\n\n' "$ANS"
  } >> "$OUT"
done

echo "✅ Báo cáo: $OUT" >&2
echo "$OUT"

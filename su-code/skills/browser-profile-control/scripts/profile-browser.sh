#!/usr/bin/env bash
# profile-browser.sh — quản lý browser Chromium HIỆN HÌNH trên profile bền (persistent)
# mà omp browser tool attach vào để control. Tổng quát hóa từ linkedin-browser.sh (validated).
#
#   profile-browser.sh open   [profile] [url]   # mở cửa sổ + CDP; default profile=default
#   profile-browser.sh status [profile]
#   profile-browser.sh clear  [profile]         # kill + xóa profile (logout sạch)
#
# Profile sống ở $REPO/data/.cache/<profile>-profile (gitignored) — user login 1 lần,
# session giữ vĩnh viễn cho các phiên agent sau. Mỗi profile 1 CDP port riêng (ổn định
# theo tên) nên nhiều profile chạy song song được.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PROFILE_NAME="${2:-default}"
PROFILE_DIR="$REPO_ROOT/data/.cache/${PROFILE_NAME}-profile"
# port ổn định theo tên profile: 9222 + (hash % 100). linkedin giữ 9222 (tương thích cũ).
if [ "$PROFILE_NAME" = "linkedin" ] || [ "$PROFILE_NAME" = "default" ]; then
  CDP_PORT="${CDP_PORT:-9222}"
else
  HASH=$(printf '%s' "$PROFILE_NAME" | cksum | cut -d' ' -f1)
  CDP_PORT="${CDP_PORT:-$((9223 + HASH % 100))}"
fi
BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable || true)"

case "${1:-status}" in
  open)
    [ -n "$BIN" ] || { echo "ERROR: no Chromium-family browser found" >&2; exit 1; }
    mkdir -p "$PROFILE_DIR"
    # Chromium >=136 CHẶN CDP trên profile mặc định -> BẮT BUỘC user-data-dir riêng.
    # Profile đang bị instance cũ giữ lock -> CDP không lên; dọn trước.
    pkill -f "user-data-dir=$PROFILE_DIR" 2>/dev/null && sleep 1 || true
    # setsid -f: sống sót qua timeout/kill của caller.
    setsid -f "$BIN" \
      --remote-debugging-port="$CDP_PORT" \
      --user-data-dir="$PROFILE_DIR" \
      --no-first-run --no-default-browser-check \
      --new-window "${3:-about:blank}" >/dev/null 2>&1
    for _ in $(seq 1 20); do
      sleep 0.5
      curl -sf --max-time 2 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null \
        && { echo "CDP up on :$CDP_PORT  profile=$PROFILE_DIR"; exit 0; }
    done
    echo "ERROR: CDP did not come up on :$CDP_PORT" >&2; exit 1
    ;;
  status)
    if curl -sf --max-time 2 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null; then
      echo "CDP: up on :$CDP_PORT"
    else
      echo "CDP: down (expected port :$CDP_PORT)"
    fi
    if [ -d "$PROFILE_DIR" ]; then
      echo "profile: $PROFILE_DIR ($(du -sh "$PROFILE_DIR" 2>/dev/null | cut -f1))"
    else
      echo "profile: absent (next open = fresh login)"
    fi
    ;;
  clear)
    pkill -f "user-data-dir=$PROFILE_DIR" 2>/dev/null || true
    sleep 1
    rm -rf "$PROFILE_DIR"
    echo "cleared: $PROFILE_DIR (session removed)"
    ;;
  *)
    echo "usage: $0 {open [profile] [url]|status [profile]|clear [profile]}" >&2; exit 2
    ;;
esac

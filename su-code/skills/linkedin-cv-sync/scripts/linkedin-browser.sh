#!/usr/bin/env bash
# linkedin-browser.sh — manage the project-local LinkedIn browser profile.
# Profile lives INSIDE this repo (gitignored) so the user can wipe it in one command.
#
#   open    launch Chromium (detached) with CDP :9222 on the project profile
#   status  is CDP alive? is the profile present? how big?
#   clear   kill Chromium + wipe the profile (logs you out; next `open` = fresh login)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PROFILE_DIR="$REPO_ROOT/data/.cache/linkedin-profile"
CDP_PORT="${CDP_PORT:-9222}"
BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable || true)"

case "${1:-status}" in
  open)
    [ -n "$BIN" ] || { echo "ERROR: no Chromium-family browser found" >&2; exit 1; }
    mkdir -p "$PROFILE_DIR"
    # setsid -f: survive the caller's timeout/kill. CDP on default profile is
    # blocked since Chromium 136 -> dedicated user-data-dir is REQUIRED.
    setsid -f "$BIN" \
      --remote-debugging-port="$CDP_PORT" \
      --user-data-dir="$PROFILE_DIR" \
      --no-first-run \
      --new-window "${2:-https://www.linkedin.com/in/me/}" >/dev/null 2>&1
    for _ in $(seq 1 20); do
      sleep 0.5
      curl -sf --max-time 2 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null && { echo "CDP up on :$CDP_PORT  profile=$PROFILE_DIR"; exit 0; }
    done
    echo "ERROR: CDP did not come up on :$CDP_PORT" >&2; exit 1
    ;;
  status)
    if curl -sf --max-time 2 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null; then
      echo "CDP: up on :$CDP_PORT"
    else
      echo "CDP: down"
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
    echo "cleared: $PROFILE_DIR (LinkedIn session removed)"
    ;;
  *)
    echo "usage: $0 {open [url]|status|clear}" >&2; exit 2
    ;;
esac

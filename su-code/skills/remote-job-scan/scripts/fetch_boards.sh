#!/usr/bin/env bash
# fetch_boards.sh — tải job từ các board remote công khai vào thư mục làm việc.
# Usage: fetch_boards.sh [outdir]   (default /tmp/jobscan)
# Nguồn: RemoteOK API · Remotive API · WeWorkRemotely RSS · 电鸭社区 eleduck API.
# LinkedIn KHÔNG nằm ở đây — cần browser đăng nhập (xem linkedin-scrape.snippet.js).
set -euo pipefail
OUT="${1:-/tmp/jobscan}"
mkdir -p "$OUT" && cd "$OUT"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36'

# RemoteOK — JSON API (phần tử đầu là legal notice, parser phải bỏ qua non-dict)
curl -s -A "$UA" 'https://remoteok.com/api' -o remoteok.json

# Remotive — API chính thức, mỗi query 1 file remotive_<q>.json
for q in ai machine-learning typescript design mobile game react-native flutter; do
  curl -s "https://remotive.com/api/remote-jobs?search=${q}&limit=50" -o "remotive_${q}.json"
done

# WeWorkRemotely — RSS per category (fetch trực tiếp bị 403 với một số path, RSS thì mở)
curl -s 'https://weworkremotely.com/categories/remote-programming-jobs.rss'            -o wwr_prog.rss
curl -s 'https://weworkremotely.com/categories/remote-full-stack-programming-jobs.rss' -o wwr_fullstack.rss
curl -s 'https://weworkremotely.com/categories/remote-design-jobs.rss'                 -o wwr_design.rss

# 电鸭社区 (eleduck) — board remote nổi tiếng nhất TQ; category 5 = 招聘 (jobs)
for p in 1 2 3; do
  curl -s -A "$UA" "https://svc.eleduck.com/api/v1/posts?category=5&page=${p}" -o "eleduck${p}.json"
done

echo "--- fetched into $OUT:"
ls -la "$OUT"

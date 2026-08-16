---
name: remote-job-scan
description: Scan remote jobs across LinkedIn (authenticated browser) + famous public boards (电鸭社区 eleduck, WeWorkRemotely, Remotive, RemoteOK) for mobile/web/app/AI/game/design roles, hard-filter gambling & crypto (EN + Chinese keywords), prioritize Chinese companies/boards over international, and compile every link into one A4 PDF digest. Use when the user asks to find remote jobs, "tìm job remote", refresh the job digest, or scan design/art/game job markets.
---

# remote-job-scan

Quét job remote đa nguồn → lọc sạch (no-gambling, no-crypto) → PDF digest 1 file có đủ link.
Validated 2026-07-17: 277 jobs / 13 trang (có LinkedIn), 123 jobs (chỉ board công khai).

## Pipeline

```
[1] LinkedIn (cần login)        [2] Board công khai
    browser-profile-control          scripts/fetch_boards.sh /tmp/jobscan
    + linkedin-scrape.snippet.js         (RemoteOK API · Remotive API ·
    -> /tmp/jobscan/linkedin.json         WWR RSS · eleduck API TQ)
                └──────────┬──────────────────┘
[3] scripts/build_digest.py --dir /tmp/jobscan
    -> ~/Downloads/RemoteJobs_Digest_<date>.pdf  (A4, Phần A 中国 ưu tiên > Phần B quốc tế,
       5 nhóm: AI/ML · Web · Mobile/App · Game · Design/Art, mỗi dòng kèm URL đầy đủ)
```

## Cách chạy

1. **LinkedIn** (bỏ qua nếu chỉ cần board công khai — builder tự chịu thiếu file):
   - Mở profile authed theo skill `browser-profile-control` (profile `linkedin`, port 9222).
   - Attach browser tool qua `cdp_url` rồi `run` toàn bộ `scripts/linkedin-scrape.snippet.js`
     (sửa object `searches` theo nhu cầu; key = hint phân loại của build_digest.py).
2. `bash scripts/fetch_boards.sh /tmp/jobscan`
3. `uv run --with weasyprint --with pypdf python scripts/build_digest.py --dir /tmp/jobscan`
   - Script TỰ verify: sweep từ khóa cấm trên text PDF đã render — exit 1 nếu còn sót.

## Luật lọc (không thương lượng)

- **Cấm gambling/casino/betting + crypto/web3/NFT** — 2 lớp regex trong build_digest.py:
  `BAD` (EN: binance, tether, evolution gaming…) + `BAD_CJK` (中文: 博彩/菠菜/棋牌/赌/区块链/
  链上/交易所/挖矿/usdt/solana/链游…). Job TQ hay lọt lớp EN — lớp CJK bắt được
  (case thật: "链上工具开发（Solana AMM）").
- **Whitelist role theo TITLE** (`ROLE`) + blacklist rác (`NOISE`: sales/HR/admin/caretaker…) —
  API board trả nhiều job ngoài ngành, lọc theo tag là KHÔNG đủ.
- **Ưu tiên Trung > quốc tế**: eleduck + truy vấn 远程 + công ty TQ (`CN_CO`: ByteDance, Tencent,
  Shopee, miHoYo…) vào Phần A đầu PDF.
- Số liệu/nguồn phải kiểm chứng: curl-verify HTTP 200 link mẫu mỗi nguồn trước khi giao.

## Gotchas

- RemoteOK: phần tử đầu API là legal notice (non-dict) — parser đã bỏ qua; board crypto-heavy,
  đừng nới lỏng filter. WWR: fetch HTML bị 403, RSS thì mở. Himalayas/Dribbble/ArtStation: chặn
  bot 403 — đừng tốn effort, đã có đủ nguồn. Scout/subagent hay trả list KHÔNG verify (bịa hoặc
  dính Tether) — tự fetch, đừng tin bảng của scout khi chưa check URL.
- PDF cần font CJK: "Noto Sans CJK HK" (fc-list check) — DejaVu không có glyph Hán.
- /tmp bị dọn định kỳ — digest xuất vào ~/Downloads, dữ liệu thô coi như ephemeral.

## Tùy biến cho user khác

`--candidate "Tên — headline"` + sửa `searches` trong snippet + (nếu cần) thêm từ khóa
ROLE/NOISE. Cấu trúc PDF giữ nguyên.

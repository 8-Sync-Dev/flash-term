---
name: exercise-forge
description: >
  Create NEW coding exercises for the 8sync platform via the tools/forge AUTO
  PIPELINE (uv + argparse). The coding agent does NOT hand-author problems
  anymore (owner decision 2026-07): the PROGRAM calls AI (ZAI GLM coding-plan
  key, glm-5.2 + 1M context) to research (scrapling + feynman notes), author
  every field (statement, 7-lang starters/references, tests, public/private
  visibility), dedup FIRST against live DB + catalog + seed, validate each
  language's reference on the REAL judge (/grade), persist every accepted
  problem to the durable catalog (tools/forge/catalog/*.json), regenerate THE
  single seed (9999_seed_catalog.up.sql), and `push` upserts straight into the
  LIVE database — no new migration, no reset, no redeploy. Trigger: "tạo bài
  tập", "create exercise/problem", "new coding problem", "generate exercise",
  /exercise-forge, "seed a coding problem", "forge problems", "đào bài".
---

# Exercise Forge — run the pipeline, don't write problems

Tư tưởng: bài tập KHÔNG được viết tay bởi agent nữa. `tools/forge` là dây chuyền
tự động; vai trò của agent là CHẠY nó, đọc summary, và review kết quả.

## Prereqs (one-time per machine)

- `tools/forge/.env` chứa `ZAI_API_KEY=<zai coding-plan key do chủ dự án cấp>`
  (file untracked — không bao giờ commit; xem `.env.example` ở repo root).
- **Judge = service GHCR đã deploy (owner mandate 2026-07-05): chấm 100% REAL
  API call, KHÔNG mock/fake/smoke.** Trỏ forge vào judge Encore build từ base
  image `ghcr.io/8syncdev/encore-judge-base` (parity với prod):
  `export JUDGE_URL="https://staging-8syncdev-judge-5qwi.encr.app"` +
  `JUDGE_SECRET` lấy từ Vercel project 8sync-coding (`vercel link --project
  8sync-coding && vercel env pull` — KHÔNG in/commit giá trị). Probe trước khi
  batch: POST /grade 1 bài py → phải `Passed`. Judge local (`cd backend/judge
  && encore run --port 4002`, env `JUDGE_GO_BIN/WASI_SDK_PATH/JUDGE_RUSTC`)
  chỉ là fallback khi offline — vẫn là real grading, nhưng ưu tiên GHCR service.
- `uv` có sẵn (`uv --version`).

## Runbook CHUẨN — `mine.sh` (treo máy tự đào, agent nên dùng cái này)

```bash
cd tools/forge
./mine.sh                    # mặc định: AI planner TỰ QUYẾT đề tài (đọc inventory
                             # catalog+live: tên/topic/tag/độ khó -> đề xuất bài lấp
                             # lỗ hổng, tỉ lệ 4 bậc khó ĐỀU NHAU), đào tới TARGET=60
TARGET=100 BATCH=10 ./mine.sh          # chỉ đổi cái cần đổi
TOPICS=topics-vi.txt ./mine.sh         # ép chủ đề bằng file (tắt AI planner)
nohup ./mine.sh >/dev/null 2>&1 &      # treo máy qua đêm
```

- **UI tiến độ**: tự bật ở `http://127.0.0.1:8799` (bar catalog/target, phân bậc
  khó, sự kiện NHẬN/LOẠI/TRÙNG, log live). Chạy tay: `uv run main.py ui`.
- **Crash-safe/resume**: bài accept ghi NGAY catalog + seed; tắt máy → chạy lại
  y lệnh là tiếp tục, dedup skip bài đã có (DB live + catalog + seed).
- **GitHub track**: mỗi batch tự commit+push origin (seed ở backend submodule +
  catalog ở superproject). `GIT_PUSH=0` để tắt.
- **Benchmark model**: `uv run bench_models.py` (real calls, kết quả
  `bench-results.json`). Concurrency ZAI: glm-5.2/5.1/4.5=10 luồng (ít blocking),
  glm-4.7/glm-5=2, glm-5-turbo=1 → mặc định giữ glm-5.2.

## Commands lẻ (from `tools/forge/`)

```bash
uv run main.py doctor                       # env + ZAI key + judge + migrations scan
uv run main.py auto --count 5 --repair 2    # 1 batch; KHÔNG --topic/--topics-file = AI planner tự quyết
#   FULL pipeline: plan (AI đọc inventory) -> research (scrapling+GLM) -> author ->
#   dedup -> judge GHCR -> catalog + seed. KHÔNG --no-research; KHÔNG --out;
#   KHÔNG --seed-only-check (dedup DB live BẬT). Thêm --url <link> để scrape nguồn.
uv run main.py ui [--port 8799]             # dashboard tiến độ (đọc logs/status.json)
uv run main.py push --env staging           # nạp catalog THẲNG vào DB live (idempotent)
uv run main.py push --env staging --replace # khớp chính xác: xoá slug không còn trong catalog
uv run main.py push --dry-run               # xem SQL, không nạp
uv run main.py dedup --slug tong-mang       # check trùng: migrations + catalog + live API
uv run main.py research --topic ... --url https://...   # scrapling + GLM-5.2 notes
uv run main.py validate specs/*.json        # chấm lại spec trên judge thật
uv run main.py emit [specs/*.json]          # regenerate THE seed từ catalog (+import specs cũ nếu đưa)
```

Luật test case (owner 2026-07-05): mỗi track TỐI ĐA 15 test, ít mà CHẤT — mỗi
hidden test phải có lý do (biên/hiếm/lớn/off-by-one); validator reject >15.

## Data model (2026-07-05 — nguồn sự thật)

- `tools/forge/catalog/<slug>.json` — durable, crash-safe: mỗi bài accept ghi
  NGAY vào đây (máy tắt giữa run vẫn còn đủ bài để push lại).
- `9999_seed_catalog.up.sql` — MỘT file duy nhất, regenerate TẠI CHỖ từ catalog
  (không bao giờ sinh file NNNN mới). Chỉ để bootstrap env MỚI.
- DB live update qua `push` (encore db conn-uri + docker psql): chỉ động bảng
  `problems`, giữ submissions/progress. KHÔNG migration, KHÔNG reset, KHÔNG redeploy.

## Model policy (owner decision)

- Author + research: `glm-5.2` (1M context — scrape 40k/nguồn, notes 120k vào
  author). Chấp nhận chậm, đổi lấy bài chất; retry tôn trọng Retry-After (429),
  6 lần, backoff tới 60s, timeout 600s. Thinking TẮT khi xuất JSON (tránh cắt cụt).
- Override: `FORGE_MODEL`/`FORGE_FAST_MODEL`. Endpoint:
  `https://api.z.ai/api/coding/paas/v4` (coding plan — KHÔNG dùng paas thường).

## Invariants the pipeline enforces (never bypass)

1. **Dedup TRƯỚC khi viết**: slug-exact + title-similarity (Jaccard ≥ 0.55) trên
   live API (`FORGE_PROBLEMS_API`, mặc định BẬT) + catalog/*.json + seed
   *.up.sql + batch đang chạy; mỗi bài accept append vào `known` (in-run dedup).
2. **Judge là chân lý**: cả 7 ngôn ngữ (js/ts/py/go/c/cpp/rust) reference phải
   100% Passed trên `/grade` thật; bài không đạt bị REJECT (có repair rounds).
3. **Bài sống trong `tools/forge/catalog/`**: seed + push đều regenerate từ đó;
   upsert idempotent `ON CONFLICT (slug) DO UPDATE`, status `published`.
4. Starter = khung TODO (không lộ lời giải); reference chỉ dùng để chấm, không emit.
5. Visibility do AI phân loại (`public` đại trà / `private` chất phỏng vấn ~30-45%).
6. **Chỉ Việt/Latin**: `foreign_chars()` chặn ký tự Hán/Nhật/Hàn/lạ trong MỌI
   trường văn bản — spec dính là bị loại + regenerate (guard vụ 挽回/队列/微型 rò ra prod).
7. **Đa dạng độ khó**: `--spread` xoay easy→expert, `--topics-file` xoay chủ đề.
   Crash giữa run? catalog đã có bài accept → chạy `push` là bài lên; re-run
   `auto` tự dedup catalog, không re-author.

## After a batch (chuẩn done)

- `uv run main.py push --env staging` → bài lên coding.8syncdev.com trong ~60s
  (ISR revalidate). KHÔNG cần deploy backend.
- Chain proof (chỉ khi đổi seed/migrations): `bash tools/exgen/corpus/verify-migrations.sh`.
- Browser-verify vài bài mới (render + editor + Chạy/Nộp bài) trước khi báo done.
- Commit: `tools/forge/catalog/` + seed (backend submodule: commit TRONG backend/
  trước, rồi bump pointer ở superproject). Review nhanh đề private trước khi bán.

## Legacy

`tools/exgen` (TS) vẫn là chuẩn cho catalog TS + corpus families cũ; forge tái
dùng đúng contract SQL/judge của nó. Đừng thêm đường ống authoring thứ ba.

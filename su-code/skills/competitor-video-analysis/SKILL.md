---
name: competitor-video-analysis
description: Phân tích video đối thủ/tham chiếu (YouTube, TikTok, FB, file local) rồi rút ra "output value học theo" — hook, cấu trúc, chiêu giữ chân, CTA, điểm ăn cắp được, lỗi cần tránh. Dùng engine watch-skill (transcript + OCR + retrieval, chạy local). Trigger khi user muốn "xem/phân tích video đối thủ", "học theo video", "bóc tách content video", "xây content từ video tham chiếu". KHÁC skill `watch` (giám sát research field, không phải video).
---

# competitor-video-analysis

Biến video đối thủ thành **bài học hành động** cho content 8 Sync Dev (coding/tech trên FB·TikTok·YouTube). Engine: [`references/watch-skill`](../../../references/watch-skill) (oxbshw/watch-skill, MIT) — scene frames + OCR + Whisper transcript + index tìm kiếm có timestamp, **chạy local** (không cần API key cho transcript/OCR/search).

Validated 2026-07-22: watch "Me at the zoo" → index `4b0f48e4f4ae6e02` → `ask` trả transcript có timestamp + confidence; báo cáo assemble OK.

## 0. Setup (per-machine, 1 lần)
```bash
git submodule update --init references/watch-skill
cd references/watch-skill
uv sync --extra perceive --extra ocr --extra whisper --extra index --extra mcp
uv run watch-skill doctor          # tự cài/kiểm ffmpeg, yt-dlp, deno; GPU whisper nếu có
```
Deps đã cần: `ffmpeg`, `yt-dlp`, `uv` (doctor tự vá phần thiếu). **Không cần API key** cho luồng chuẩn.

## 1. Chạy nhanh (1 video → báo cáo học theo)
```bash
bash 8syncdev-org-skills/skills/competitor-video-analysis/scripts/analyze-competitor.sh \
  "https://www.youtube.com/watch?v=..."        # + [start] [end] để soi 1 đoạn, vd 0:30 2:00
```
→ xuất `outputs/competitor-<video_id>.md` với 7 mục: **HOOK · CẤU TRÚC · GIỮ CHÂN · CTA · STYLE/CHỮ · HỌC THEO · TRÁNH** (mỗi câu trả lời kèm timestamp trích từ transcript/on-screen text).

Hỏi sâu thêm bất kỳ lúc nào (không tải lại video — hỏi trên index đã lưu):
```bash
cd references/watch-skill
uv run watch-skill ask <video_id> "Đoạn nào giải thích thuật toán? Tóm tắt cách họ dạy."
uv run watch-skill ask <video_id> "Nhịp cắt cảnh mỗi bao nhiêu giây? Có b-roll không?"
```

## 2. Nhiều video đối thủ (thư viện + tổng hợp chéo)
```bash
cd references/watch-skill
uv run watch-skill batch ./competitor-urls.txt --limit 50   # hoặc watch từng URL
uv run watch-skill library ask "Các kênh coding VN mở bài kiểu gì? Mẫu hook lặp lại?"
uv run watch-skill search "call to action"                  # tìm khoảnh khắc xuyên mọi video
```
`library ask` tổng hợp bằng chứng qua nhiều clip, giữ timestamp từng nguồn → tìm **mẫu chung của đối thủ** để 8Sync học theo.

## 3. Biến bài học → content 8Sync (đầu ra có giá trị)
Sau khi có `outputs/competitor-*.md`, chốt thành action (bám `org-social-ops` + luật `fb-group-growth`):
- **Hook** → viết lại theo giọng 8Sync (VN, thẳng, không clickbait rỗng), gắn bài thật `coding.8syncdev.com/problem/<slug>` hoặc `news.8syncdev.com/articles/<slug>`.
- **Cấu trúc** → template kịch bản video/bài cho GV (`GV_Task`) hoặc MKT (`MKT_01`).
- **CTA/Style** → chỉ áp cho kênh OWNED (fanpage/group mình); nhóm ngoài giữ luật share FREE (fb-group-growth §0).
- **TRÁNH** → ghi vào `su-code/KNOWLEDGE.md` nếu là bài học lặp lại.

## 4. Nâng cấp tùy chọn — visual Q&A (khi cần "nhìn" khung hình)
Luồng chuẩn dựa transcript + on-screen text (đủ cho hook/kịch bản/CTA). Muốn hỏi về **hình ảnh** (bố cục, màu, thao tác tay) → cấu hình 1 vision provider:
```bash
cd references/watch-skill
uv run watch-skill setup-vision --provider ollama          # local, không tốn tiền
# hoặc export GEMINI_API_KEY / OPENAI_API_KEY / OPENROUTER_API_KEY rồi setup-vision
```
Không có provider → `ask` vẫn trả bằng chứng transcript/OCR và **nói thẳng "không thấy rõ"** thay vì đoán (tính năng, không phải lỗi).

## Gotchas (đã gặp 2026-07-22)
- Video **AV1** (nhiều YouTube mới) → CPU giải mã phần mềm, chậm (1 clip 19s ~ vài phút lần đầu vì tải model Whisper). Lần sau nhanh. Muốn ép codec: thêm cờ yt-dlp trong engine, hoặc chấp nhận chậm 1 lần.
- YouTube phụ đề đôi khi **HTTP 429** → engine tự fallback Whisper local (vẫn ra transcript). GPU (RTX 5080 ở máy này) làm Whisper nhanh.
- `ask` chạy trên **index đã lưu** (`~/.watch-skill/index.db`) — hỏi lại miễn phí, không tải lại. `watch-skill list` xem đã index gì.
- **KHÁC skill `watch`** (research-field monitoring) — đừng nhầm. Skill này = video.

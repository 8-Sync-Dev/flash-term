# Chạy GGUF model trên GPU làm AI provider cho GSD / pi

## Cơ chế

`~/.gsd/agent/models.json` của pi dùng `api: "openai-completions"` + `baseUrl` tùy ý.
Bất kỳ server GGUF nào expose OpenAI-compatible REST API đều gắn vào được như một
provider thông thường — không cần code gì thêm trong pi.

---

## Bước 1 — Chạy GGUF server trên máy GPU

### Option A: llama.cpp server (khuyên dùng)

Nhẹ nhất, hỗ trợ `reasoning_content` field mà pi đọc được, chạy tốt trên GPU local.

```bash
llama-server \
  --model /path/to/model.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --n-gpu-layers 99 \
  --ctx-size 32768 \
  --parallel 4
```

- `--n-gpu-layers 99` : đẩy tất cả layers lên GPU (giảm xuống nếu OOM)
- `--ctx-size`        : context window, phải <= giá trị trong models.json
- `--parallel`        : số request đồng thời

Endpoint: `http://localhost:8080/v1`

### Option B: Ollama (dễ nhất, tự quản lý GPU)

```bash
ollama serve   # port 11434 mac/linux
ollama run qwen2.5-coder:32b
```

Endpoint: `http://localhost:11434/v1`

Model ID dùng trong models.json: chính xác tên bạn đã `ollama pull/run`,
ví dụ `qwen2.5-coder:32b`.

### Option C: LM Studio (Windows, có GUI)

Vào Local Server tab -> Start Server. Port mặc định 1234.
Endpoint: `http://localhost:1234/v1`

---

## Bước 2 — Thêm provider vào models.json

File: `C:/Users/Admin/.gsd/agent/models.json`

Thêm provider mới vào object `providers` (giữ nguyên các provider cũ):

```json
{
  "providers": {
    "z-coding-plan": { "...": "giữ nguyên" },

    "local-gpu": {
      "baseUrl": "http://localhost:8080/v1",
      "api": "openai-completions",
      "apiKey": "LOCAL_GPU_API_KEY",
      "authHeader": false,
      "models": [
        {
          "id": "qwen2.5-coder-32b",
          "name": "Qwen2.5-Coder 32B (local GPU)",
          "reasoning": false,
          "input": ["text"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 32768,
          "maxTokens": 8192
        }
      ]
    }
  }
}
```

**Quan trọng:**
- `"authHeader": false` — llama.cpp/Ollama/LM Studio không cần Authorization header
- `"id"` — phải khớp chính xác với tên model server nhận
  - llama.cpp: kiểm tra bằng `curl http://localhost:8080/v1/models`
  - Ollama: tên bạn đã `ollama pull`, ví dụ `qwen2.5-coder:32b`
- `"cost": 0` — chạy local, không tốn tiền
- `"contextWindow"` — phải <= `--ctx-size` bạn set trên server

---

## Bước 3 — Kiểm tra model ID thực tế của server

```bash
# llama.cpp / LM Studio / bất kỳ server nào
curl http://localhost:8080/v1/models

# Ollama
curl http://localhost:11434/v1/models
```

Dùng đúng tên trong field `"id"` của response để điền vào models.json.

---

## Bước 4 — Dùng trong PREFERENCES.md

```yaml
models:
  execution:
    model: local-gpu/qwen2.5-coder-32b
    fallbacks:
      - anthropic/claude-sonnet-4-6

  execution_simple:
    model: local-gpu/qwen2.5-coder-32b
    fallbacks:
      - anthropic/claude-haiku-4-5
```

Hoặc apply qua lệnh sau sau khi tạo file `~/.config/wezterm/gsd-config/PREFERENCES-local.md`:

```powershell
8sync gsd setup --plan local
```

---

## Bước 5 (tùy chọn) — GPU ở máy khác / remote

### LAN

```json
"baseUrl": "http://192.168.1.100:8080/v1"
```

### Internet (ngrok)

```bash
ngrok http 8080
# copy URL dạng https://abc123.ngrok.io
```

```json
"baseUrl": "https://abc123.ngrok.io/v1"
```

### Cloudflare Tunnel (ổn định hơn ngrok, free)

```bash
cloudflared tunnel --url http://localhost:8080
```

---

## Model GGUF nào chạy tốt cho coding (GSD)

| Model | VRAM cần | Ghi chu |
|---|---|---|
| Qwen2.5-Coder 32B Q4_K_M | ~20 GB | coding SOTA trong GGUF |
| Qwen3 30B-A3B Q4 (MoE) | ~6 GB active | MoE, rất mạnh, ít VRAM |
| DeepSeek-R1 14B Q4_K_M | ~9 GB | reasoning, tốt cho planning |
| Qwen2.5-Coder 7B Q8 | ~8 GB | nhỏ nhưng coding ổn |
| DeepSeek-Coder-V2 16B Q4 | ~10 GB | tool calling tốt |

Download GGUF: https://huggingface.co/bartowski (quantized builds chất lượng cao)

---

## Troubleshooting

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `401 Unauthorized` | Server nhận Authorization header lạ | `"authHeader": false` trong models.json |
| Model not found | ID không khớp | Chạy `curl .../v1/models` để lấy ID đúng |
| OOM / crash | Context quá lớn | Giảm `--ctx-size` và `contextWindow` |
| Tool calling không hoạt động | Model không support | Dùng model có `-instruct` hoặc `-tool` suffix |
| Reasoning không hiện | Field tên khác | llama.cpp dùng `reasoning_content`, pi handle sẵn |
| Chậm dù có GPU | Layers chạy trên CPU | Kiểm tra log llama-server, tăng `--n-gpu-layers` |

---

## Verify hoạt động

Sau khi setup xong:

```powershell
# Trong pi
/model                    # xem model đang active
/gsd prefs                # xem PREFERENCES.md đang dùng
```

Test nhanh bằng curl trực tiếp vào server trước khi gắn vào pi:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-32b",
    "messages": [{"role": "user", "content": "say hello"}],
    "stream": false
  }'
```

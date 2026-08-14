# Local GGUF provider (llama.cpp on GPU) + su-code

`ft gguf` runs a local **llama.cpp** server (OpenAI-compatible `/v1` endpoint) on your GPU and lets
you point the **su-code** AI harness (`8sync`, via omp) at it for fully local AI coding — no API key,
no network.

> This doc covers serving the model with **flash-term** (`ft gguf`) and wiring the **su-code** AI
> harness (`8sync`) at it. su-code is a separate project, installed by `ft setup`.

## 1. Prerequisites

- An NVIDIA GPU + current CUDA toolkit (or a ROCm/Vulkan build of llama.cpp).
- A built `llama-server` (from [llama.cpp](https://github.com/ggerganov/llama.cpp)), or let
  `ft gguf hint` walk you through it.
- One or more `.gguf` model files.

```powershell
ft gguf hint      # prerequisites checklist (driver, CUDA, llama.cpp)
```

## 2. Serve a model

```powershell
ft gguf serve `
  --engine-path "C:\tools\llamacpp\run" `
  --model-path  "D:\models\qwen2.5-coder-14b.gguf" `
  --balance            # solver: fits GPU layers + ctx to live free VRAM (not a preset)
```

`--balance` reads the model size, infers a quant multiplier from the filename, queries `nvidia-smi`
for free VRAM and GPU temperature, reserves headroom, cuts GPU layers by 20% above 75 °C, and scales
context 8K → 64K by what is left. It needs `nvidia-smi`; without it the launch silently falls back to
CPU-only. Fixed presets instead: `--preset max|high|medium|low`. Save a launch for reuse:

```powershell
ft gguf save --profile coder --engine-path <dir> --model-path <file>
ft gguf serve --profile coder
ft gguf status     # running PID + port
ft gguf stop       # kill all running llama-server
```

The server exposes **`http://localhost:<port>/v1`** (OpenAI-compatible).

## 3. Point su-code (omp) at it

su-code's `8sync` reads its provider config from `~/.omp/config.yml`. Add a provider whose `baseUrl`
is the local server endpoint, then use it as a model:

```yaml
# ~/.omp/config.yml  (fragment — merge into your existing providers)
providers:
  local:
    baseURL: http://localhost:8080/v1
    apiKey:  no-key-needed
models:
  local-coder:
    provider: local
    model:    qwen2.5-coder-14b      # must match what the server loaded
```

Then run `8sync` against it (these are su-code commands — `8sync .` for a session, `8sync ai` for a
one-shot):

```powershell
8sync . --model local-coder                 # interactive session on the local model
8sync ai "refactor this function" --model local-coder -p
```

## 4. Chat without a server

```powershell
ft gguf chat --engine-path <dir> --model-path <file>     # one-shot interactive (llama-cli)
```

## Notes

- `--balance`/presets are tuned per-machine in `gguf-config/presets.json`; edit them for your VRAM.
- VRAM exhausted → drop `--gpu-layers` (preset `low`/`medium`) or pick a smaller quant.
- Verify the endpoint before wiring `8sync`: `curl http://localhost:8080/v1/models`.

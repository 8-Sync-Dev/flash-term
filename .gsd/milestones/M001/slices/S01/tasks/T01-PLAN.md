---
estimated_steps: 16
estimated_files: 2
skills_used: []
---

# T01: Enrich Show-GpuStatus with real GPU name and front_end

1. In modules/gpu.ps1, add a helper Get-ActiveGpuInfo that calls `wezterm cli list-clients` (or parses `wezterm --version` / enumerate_gpus equivalent via wezterm CLI) to determine which GPU and front_end wezterm is using.

2. Since enumerate_gpus is a Lua API not callable from PS, use the wezterm CLI: `wezterm cli get-text` or parse `wezterm --config-file ... list-clients` output. Actually the best approach: call `wezterm cli list-clients` which returns tab-separated lines including the GPU. Parse that.

3. If the wezterm CLI returns GPU info, extract device name + front_end. If unavailable, show '(CLI not available — check inside WezTerm)'.

4. Rewrite Show-GpuStatus to show a table:
   - Min GPU target: 30% (high-performance bias)
   - Active front_end: WebGpu
   - Active GPU: NVIDIA GeForce RTX 4060 (DiscreteGpu)
   - Power preference: HighPerformance
   - State file: <path>

5. Also add `8sync gpu verify` subcommand that:
   - Reads current-gpu.lua
   - Calls wezterm cli list-clients
   - Prints a PASS/FAIL for each: front_end is WebGpu, GPU is Discrete, power is HighPerformance

6. Update Invoke-GpuCommand switch to handle 'verify'.
7. Update Show-GpuHelp with verify entry.
8. Update Register-8SyncCompleter gpu subMap in shell.ps1.

## Inputs

- `modules/gpu.ps1`
- `modules/shell.ps1`

## Expected Output

- `modules/gpu.ps1 updated with enriched Show-GpuStatus and Invoke-GpuCommand 'verify'`
- `modules/shell.ps1 updated with 'verify' in gpu subMap`

## Verification

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('status')"

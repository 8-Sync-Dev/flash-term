# =============================================================================
# 8sync gguf -- Local GGUF server launcher (llama.cpp)
# =============================================================================
#
# Usage:
#   8sync gguf serve  --engine-path <dir> --model-path <file> [options]
#   8sync gguf serve  --profile <name>    [--preset <name>] [--port N]
#   8sync gguf detect                     Scan GPU/CPU/RAM -> recommended preset + flags
#   8sync gguf presets                    List built-in + custom presets
#   8sync gguf profiles                   List saved profiles
#   8sync gguf save   --profile <name> --engine-path <d> --model-path <f> [opts]
#   8sync gguf status                     Show running llama-server processes
#   8sync gguf stop                       Kill all running llama-server processes
#   8sync gguf help                       This help screen
# =============================================================================

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
function Resolve-GgufConfigDir {
    $localDir = Join-Path $PSScriptRoot '..\gguf-config'
    if (Test-Path $localDir) { return [System.IO.Path]::GetFullPath($localDir) }
    # fallback: beside this module file
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'gguf-config'))
}

function Get-GgufPresetsPath  { Join-Path (Resolve-GgufConfigDir) 'presets.json'  }
function Get-GgufProfilesPath { Join-Path (Resolve-GgufConfigDir) 'profiles.json' }

# ---------------------------------------------------------------------------
# Hardware detection
# ---------------------------------------------------------------------------

function Get-GgufHardware {
    # Returns: [pscustomobject]@{ GpuName; VramGB; CpuCores; CpuThreads; RamGB; GpuSource }
    # VRAM: nvidia-smi first (accurate), fallback Win32_VideoController (DWORD-overflows >4GB)

    $vramGB     = 0
    $gpuName    = 'Unknown'
    $gpuSource  = 'none'

    # -- nvidia-smi (most accurate for NVIDIA) --------------------------------
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        try {
            $raw = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null |
                   Select-Object -First 1
            if ($raw -match '^(.+),\s*(\d+)') {
                $gpuName   = $Matches[1].Trim()
                $vramGB    = [math]::Round([int]$Matches[2] / 1024, 1)
                $gpuSource = 'nvidia-smi'
            }
        } catch {}
    }

    # -- WMI fallback (works for AMD / Intel, DWORD wraps at 4GB so we clamp) -
    if ($gpuSource -eq 'none') {
        try {
            $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                    Where-Object { $_.AdapterRAM -and $_.AdapterRAM -gt 0 } |
                    Sort-Object AdapterRAM -Descending
            if ($gpus) {
                $best      = $gpus | Select-Object -First 1
                $gpuName   = $best.Name
                # AdapterRAM is DWORD — max it can hold is ~4GB; anything at ~4GB may be overflow
                $raw_gb    = [math]::Round($best.AdapterRAM / 1GB, 1)
                $vramGB    = $raw_gb
                $gpuSource = 'wmi'
                if ($raw_gb -ge 3.9) {
                    # Flag as potentially truncated — can't know the real size
                    $gpuSource = 'wmi-truncated'
                }
            }
        } catch {}
    }

    # -- CPU / RAM ------------------------------------------------------------
    $cpuCores   = 4
    $cpuThreads = 8
    $ramGB      = 8
    try {
        $cpu        = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $cpuCores   = [int]$cpu.NumberOfCores
        $cpuThreads = [int]$cpu.NumberOfLogicalProcessors
        $ramGB      = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    } catch {}

    return [pscustomobject]@{
        GpuName    = $gpuName
        VramGB     = $vramGB
        CpuCores   = $cpuCores
        CpuThreads = $cpuThreads
        RamGB      = $ramGB
        GpuSource  = $gpuSource
    }
}

function Get-GgufAutoPreset {
    # Returns recommended preset name + derived n_gpu_layers for the detected hardware.
    # Logic:
    #   >= 12 GB VRAM -> max    (99 layers — let llama.cpp decide)
    #    8-12 GB VRAM -> high   (cap at 40 layers — fits most 7-13B Q8 models)
    #    4-8  GB VRAM -> medium (20 layers — partial offload)
    #    < 4  GB VRAM -> low    (CPU only)
    #
    # ctx_size scales with RAM so large-RAM machines get bigger windows.
    # CPU threads = min(physical_cores, 8) — leave headroom for OS.

    param([pscustomobject]$Hw)

    $vram    = $Hw.VramGB
    $threads = [math]::Min($Hw.CpuCores, 8)

    if ($vram -ge 12) {
        return [pscustomobject]@{
            Preset     = 'max'
            n_gpu_layers = 99
            cpu_threads  = [math]::Max(2, $threads - 6)
            ctx_size     = if ($Hw.RamGB -ge 32) { 65536 } else { 32768 }
            parallel     = if ($vram -ge 20) { 8 } elseif ($vram -ge 16) { 4 } else { 2 }
            batch_size   = 512
            flash_attn   = $true
            Reason       = ("${vram}GB VRAM >= 12GB -> full GPU offload, large context")
        }
    } elseif ($vram -ge 8) {
        return [pscustomobject]@{
            Preset     = 'high'
            n_gpu_layers = 40
            cpu_threads  = [math]::Max(2, $threads - 4)
            ctx_size     = 16384
            parallel     = 2
            batch_size   = 256
            flash_attn   = $true
            Reason       = ("${vram}GB VRAM 8-12GB -> most layers on GPU, 40 offloaded")
        }
    } elseif ($vram -ge 4) {
        return [pscustomobject]@{
            Preset     = 'medium'
            n_gpu_layers = 20
            cpu_threads  = $threads
            ctx_size     = 8192
            parallel     = 1
            batch_size   = 128
            flash_attn   = $false
            Reason       = ("${vram}GB VRAM 4-8GB -> partial GPU offload, 20 layers")
        }
    } else {
        return [pscustomobject]@{
            Preset     = 'low'
            n_gpu_layers = 0
            cpu_threads  = $Hw.CpuThreads   # CPU-only: use all logical threads
            ctx_size     = 4096
            parallel     = 1
            batch_size   = 64
            flash_attn   = $false
            Reason       = ("${vram}GB VRAM < 4GB -> CPU-only mode")
        }
    }
}

# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------
function Read-GgufJson {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Warning "gguf: cannot parse $Path -- $_"; return $null }
}

function Write-GgufJson {
    param([string]$Path, [object]$Data)
    $Data | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Preset resolution
# ---------------------------------------------------------------------------
function Get-GgufPreset {
    param([string]$Name)
    $data = Read-GgufJson (Get-GgufPresetsPath)
    if (-not $data) { return $null }
    # built-in first, then custom
    if ($data.presets.PSObject.Properties[$Name])        { return $data.presets.$Name }
    if ($data.custom_presets.PSObject.Properties[$Name]) { return $data.custom_presets.$Name }
    return $null
}

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------
function Show-GgufPresets {
    $data = Read-GgufJson (Get-GgufPresetsPath)
    if (-not $data) { Write-Warning 'gguf: presets.json not found'; return }

    Write-Host ''
    Write-HintSection 'GGUF Presets -- resource profiles for llama-server'
    Write-Host ''
    Write-Host ('  {0,-14} {1,-10} {2,-10} {3,-8} {4,-8} {5}' -f `
        'Name','GPU-Layers','CPU-Threads','Ctx-K','Parallel','Description') -ForegroundColor DarkGray
    Write-Host ('  {0}' -f ('-' * 90)) -ForegroundColor DarkGray

    foreach ($prop in $data.presets.PSObject.Properties) {
        $p = $prop.Value
        $ctx = [math]::Round($p.ctx_size / 1024)
        Write-Host ('  {0,-14} {1,-10} {2,-10} {3,-8} {4,-8} {5}' -f `
            $prop.Name,
            $p.n_gpu_layers,
            $p.cpu_threads,
            "${ctx}K",
            $p.parallel,
            $p.description) -ForegroundColor White
        if ($p.notes) {
            Write-Host ('  {0,-14} {1}' -f '', $p.notes) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    # custom_presets (skip _hint / _example)
    $customs = $data.custom_presets.PSObject.Properties |
        Where-Object { $_.Name -notlike '_*' }
    if ($customs) {
        Write-Host '  -- Custom presets (gguf-config/presets.json -> custom_presets) --------' -ForegroundColor DarkGray
        Write-Host ''
        foreach ($prop in $customs) {
            $p = $prop.Value
            $ctx = [math]::Round($p.ctx_size / 1024)
            Write-Host ('  {0,-14} {1,-10} {2,-10} {3,-8} {4,-8} {5}' -f `
                $prop.Name,
                $p.n_gpu_layers,
                $p.cpu_threads,
                "${ctx}K",
                $p.parallel,
                $p.description) -ForegroundColor Cyan
            if ($p.notes) {
                Write-Host ('  {0,-14} {1}' -f '', $p.notes) -ForegroundColor DarkGray
            }
            Write-Host ''
        }
    }

    Write-Host '  Use: 8sync gguf serve --preset <name> --engine-path <dir> --model-path <file>' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GgufDetect {
    # Detect hardware and show recommended preset with full reasoning
    $hw = Get-GgufHardware
    $ap = Get-GgufAutoPreset $hw

    Write-Host ''
    Write-HintSection 'GGUF Hardware Detection'
    Write-Host ''

    Write-Host '  -- Hardware found -------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ("  GPU   : {0}" -f $hw.GpuName) -ForegroundColor White
    $vramLabel = if ($hw.GpuSource -eq 'wmi-truncated') {
        '{0} GB (WMI truncated -- may be higher; install nvidia-smi for accuracy)' -f $hw.VramGB
    } else {
        '{0} GB  [source: {1}]' -f $hw.VramGB, $hw.GpuSource
    }
    Write-Host ("  VRAM  : {0}" -f $vramLabel) -ForegroundColor $(if ($hw.GpuSource -eq 'wmi-truncated') { 'DarkYellow' } else { 'White' })
    Write-Host ("  CPU   : {0} cores / {1} threads" -f $hw.CpuCores, $hw.CpuThreads) -ForegroundColor White
    Write-Host ("  RAM   : {0} GB" -f $hw.RamGB) -ForegroundColor White
    Write-Host ''

    Write-Host '  -- Recommended preset ---------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ("  Preset     : {0}" -f $ap.Preset)        -ForegroundColor Cyan
    Write-Host ("  Reason     : {0}" -f $ap.Reason)        -ForegroundColor DarkGray
    Write-Host ("  GPU layers : {0}" -f $ap.n_gpu_layers)  -ForegroundColor White
    Write-Host ("  CPU threads: {0}" -f $ap.cpu_threads)   -ForegroundColor White
    Write-Host ("  Context    : {0}K tokens" -f [math]::Round($ap.ctx_size / 1024)) -ForegroundColor White
    Write-Host ("  Parallel   : {0} slots"   -f $ap.parallel)  -ForegroundColor White
    Write-Host ("  Batch size : {0}"          -f $ap.batch_size) -ForegroundColor White
    Write-Host ("  Flash attn : {0}"          -f $(if ($ap.flash_attn) { 'on' } else { 'off' })) -ForegroundColor White
    Write-Host ''
    Write-Host '  To use this preset:' -ForegroundColor DarkGray
    Write-Host ("    8sync gguf serve --engine-path <dir> --model-path <file>") -ForegroundColor Yellow
    Write-Host ("    (auto-detect is the default when --preset is omitted)") -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  To override: --preset max|high|medium|low or a custom name from presets.json' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GgufProfiles {
    $data = Read-GgufJson (Get-GgufProfilesPath)
    if (-not $data -or -not $data.profiles) {
        Write-Host ''
        Write-Host '  No profiles saved yet.' -ForegroundColor DarkGray
        Write-Host '  Save one: 8sync gguf save --profile <name> --engine-path <dir> --model-path <file>' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ''
    Write-HintSection 'GGUF Profiles -- saved server configs'
    Write-Host ''

    foreach ($prop in $data.profiles.PSObject.Properties) {
        $pr = $prop.Value
        Write-Host ("  [{0}]" -f $prop.Name) -ForegroundColor Cyan
        if ($pr.description) {
            Write-Host ("    {0}" -f $pr.description) -ForegroundColor White
        }
        Write-Host ("    Engine : {0}" -f $pr.engine_path) -ForegroundColor DarkGray
        Write-Host ("    Model  : {0}" -f $pr.model_path)  -ForegroundColor DarkGray
        Write-Host ("    Preset : {0}    Port: {1}" -f $pr.preset, $pr.port) -ForegroundColor DarkGray
        if ($pr.extra_args -and $pr.extra_args.Count -gt 0) {
            Write-Host ("    Extra  : {0}" -f ($pr.extra_args -join ' ')) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    Write-Host '  Use: 8sync gguf serve --profile <name>' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GgufHint {
    # Scan every prerequisite and print status + install instructions.
    # Checks: NVIDIA driver, nvidia-smi, CUDA toolkit, nvcc, llama-server binary,
    # and whether the user's configured engine-path is reachable.

    Write-Host ''
    Write-HintSection 'GGUF -- Prerequisites checklist'
    Write-Host ''

    $allOk  = $true
    $nvidia = $false

    # ── Helper: print one row ─────────────────────────────────────────────────
    function Write-CheckRow {
        param([bool]$Ok, [string]$Label, [string]$Detail)
        $icon  = if ($Ok) { '[OK]' } else { '[!!]' }
        $color = if ($Ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-5} {1,-32} {2}" -f $icon, $Label, $Detail) -ForegroundColor $color
    }

    # ── 1. NVIDIA driver / nvidia-smi ────────────────────────────────────────
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        $verLine = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1
        Write-CheckRow $true 'NVIDIA driver' ("nvidia-smi found   driver: {0}" -f $verLine.Trim())
        $nvidia = $true
    } else {
        Write-CheckRow $false 'NVIDIA driver' 'nvidia-smi not found in PATH'
        Write-Host '         -> nvidia-smi ships with the NVIDIA display driver.' -ForegroundColor DarkGray
        Write-Host '            Install: https://www.nvidia.com/en-us/drivers/' -ForegroundColor DarkGray
        Write-Host '            Or via winget: winget install NVIDIA.NVIDIAAPP' -ForegroundColor DarkGray
        $allOk = $false
    }
    Write-Host ''

    # ── 2. CUDA Toolkit ───────────────────────────────────────────────────────
    $nvcc      = Get-Command nvcc -ErrorAction SilentlyContinue
    $cudaEnv   = $env:CUDA_PATH
    $cudaFound = $nvcc -or ($cudaEnv -and (Test-Path $cudaEnv))

    if ($cudaFound) {
        $cudaVer = ''
        if ($nvcc) {
            try { $cudaVer = (& nvcc --version 2>$null | Select-String 'release' | Select-Object -First 1).ToString().Trim() } catch {}
        } elseif ($cudaEnv) {
            $cudaVer = "CUDA_PATH=$cudaEnv"
        }
        Write-CheckRow $true 'CUDA Toolkit' $cudaVer
    } else {
        Write-CheckRow $false 'CUDA Toolkit' 'nvcc not found, CUDA_PATH not set'
        Write-Host '         -> Required to run llama-server with GPU support (CUDA backend).' -ForegroundColor DarkGray
        Write-Host '            Download: https://developer.nvidia.com/cuda-downloads' -ForegroundColor DarkGray
        Write-Host '            Choose:   Windows > x86_64 > exe (local)' -ForegroundColor DarkGray
        Write-Host '            After install: restart shell, confirm with: nvcc --version' -ForegroundColor DarkGray
        Write-Host '            Minimum version: CUDA 11.8   Recommended: 12.x / 13.x' -ForegroundColor DarkGray
        $allOk = $false
    }
    Write-Host ''

    # ── 3. llama-server binary ────────────────────────────────────────────────
    # Check PATH first, then the saved profile engine paths
    $llamaInPath = Get-Command llama-server -ErrorAction SilentlyContinue
    if (-not $llamaInPath) {
        $llamaInPath = Get-Command 'llama-server.exe' -ErrorAction SilentlyContinue
    }
    if ($llamaInPath) {
        Write-CheckRow $true 'llama-server (PATH)' $llamaInPath.Source
    } else {
        Write-CheckRow $false 'llama-server (PATH)' 'not found in PATH'
        Write-Host '         -> llama.cpp server binary — needed to serve GGUF models.' -ForegroundColor DarkGray
        Write-Host '            Option A: pre-built release (recommended):' -ForegroundColor DarkGray
        Write-Host '              https://github.com/ggml-org/llama.cpp/releases' -ForegroundColor DarkGray
        Write-Host '              Download: llama-<ver>-bin-win-cuda-cu<X.Y>-x64.zip' -ForegroundColor DarkGray
        Write-Host '              Match cu version to your CUDA Toolkit (e.g. cu12, cu13)' -ForegroundColor DarkGray
        Write-Host '            Option B: build from source (needs cmake + Visual Studio):' -ForegroundColor DarkGray
        Write-Host '              git clone https://github.com/ggml-org/llama.cpp' -ForegroundColor DarkGray
        Write-Host '              cmake -B build -DGGML_CUDA=ON && cmake --build build -j' -ForegroundColor DarkGray
        Write-Host '            After download/build, point --engine-path at the folder.' -ForegroundColor DarkGray
        $allOk = $false
    }
    Write-Host ''

    # ── 4. Engine path in saved profiles ─────────────────────────────────────
    $prData = Read-GgufJson (Get-GgufProfilesPath)
    if ($prData -and $prData.profiles) {
        $profileProps = $prData.profiles.PSObject.Properties
        if ($profileProps) {
            Write-Host '  -- Saved profile engine paths -------------------------------------------' -ForegroundColor DarkGray
            foreach ($prop in $profileProps) {
                $pr = $prop.Value
                $epOk = Test-Path $pr.engine_path
                $mpOk = Test-Path $pr.model_path
                Write-CheckRow $epOk ("Profile [{0}] engine" -f $prop.Name) $pr.engine_path
                Write-CheckRow $mpOk ("Profile [{0}] model"  -f $prop.Name) $pr.model_path
            }
            Write-Host ''
        }
    }

    # ── 5. GPU summary ────────────────────────────────────────────────────────
    if ($nvidia) {
        Write-Host '  -- GPU summary ----------------------------------------------------------' -ForegroundColor DarkGray
        try {
            $rows = & nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader,nounits 2>$null
            foreach ($row in $rows) {
                $parts = $row -split ',\s*'
                if ($parts.Count -ge 4) {
                    $vramGB = [math]::Round([int]$parts[2] / 1024, 1)
                    Write-Host ("  GPU {0}: {1}   {2} GB VRAM   driver {3}" -f `
                        $parts[0].Trim(), $parts[1].Trim(), $vramGB, $parts[3].Trim()) -ForegroundColor White
                }
            }
        } catch {}
        Write-Host ''
    }

    # ── 6. Summary ────────────────────────────────────────────────────────────
    Write-Host '  -- Quick-start ----------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  1. Install NVIDIA driver  -> nvidia-smi available automatically' -ForegroundColor DarkGray
    Write-Host '  2. Install CUDA Toolkit   -> https://developer.nvidia.com/cuda-downloads' -ForegroundColor DarkGray
    Write-Host '  3. Download llama.cpp release (CUDA build) matching your cu version' -ForegroundColor DarkGray
    Write-Host '     -> https://github.com/ggml-org/llama.cpp/releases' -ForegroundColor DarkGray
    Write-Host '  4. Download a GGUF model  -> https://huggingface.co (filter: GGUF)' -ForegroundColor DarkGray
    Write-Host '  5. Run:' -ForegroundColor DarkGray
    Write-Host '     8sync gguf serve \' -ForegroundColor Yellow
    Write-Host '       --engine-path "C:\path\to\llama-cpp\bin" \' -ForegroundColor Yellow
    Write-Host '       --model-path  "C:\path\to\model.gguf"' -ForegroundColor Yellow
    Write-Host ''

    if ($allOk) {
        Write-Host '  All prerequisites found. Ready to serve.' -ForegroundColor Green
    } else {
        Write-Host '  Fix the [!!] items above, then re-run: 8sync gguf hint' -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Show-GgufHelp {
    Write-Host ''
    Write-HintSection 'GGUF -- Local llama-server launcher'
    Write-Host ''
    Write-Host '  -- Launch ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf serve --engine-path <dir> --model-path <file>' `
                  'Start llama-server API (OpenAI-compatible, for GSD/pi/other clients)'
    Write-HintRow '8sync gguf serve --preset max'   'Override resource preset (max/high/medium/low)'
    Write-HintRow '8sync gguf serve --profile <n>'  'Load saved profile by name (engine+model+preset)'
    Write-HintRow '8sync gguf serve --port 8080'    'Override listening port (default: 8080)'
    Write-HintRow '8sync gguf serve --dry-run'      'Print the llama-server command without running it'
    Write-Host ''
    Write-Host '  -- Chat (interactive REPL, no server needed) ----------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf chat --engine-path <dir> --model-path <file>' `
                  'Start interactive multi-turn chat session (uses llama-cli)'
    Write-HintRow '8sync gguf chat --profile <n>'   'Load saved profile to start chat'
    Write-HintRow '8sync gguf chat --preset high'   'Override GPU/ctx resource preset'
    Write-HintRow '8sync gguf chat --temp 0.7'      'Sampling temperature (default: 0.7)'
    Write-HintRow '8sync gguf chat --ctx 8192'      'Context window size override'
    Write-HintRow '8sync gguf chat --system <txt>'  'Set system prompt for the session'
    Write-HintRow '8sync gguf chat --gpu-layers N'  'Manual GPU layer override'
    Write-HintRow '8sync gguf chat --dry-run'       'Print llama-cli command without launching'
    Write-Host ''
    Write-Host '  -- Detection ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf detect'               'Scan GPU/CPU/RAM and show recommended preset + flags'
    Write-HintRow '8sync gguf hint'                 'Full prerequisites checklist: driver, CUDA, llama.cpp install guide'
    Write-Host ''
    Write-Host '  -- Presets (resource profiles) -------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf presets'              'List all presets with GPU/CPU/ctx details'
    Write-Host ''
    Write-Host '  Preset      GPU layers  CPU threads  Context   Parallel  Fits' -ForegroundColor DarkGray
    Write-Host '  max         99 (all)    2            32K       4         10+ GB VRAM' -ForegroundColor White
    Write-Host '  high        32          4            16K       2         6-8 GB VRAM' -ForegroundColor White
    Write-Host '  medium      16          8            8K        1         4 GB VRAM' -ForegroundColor White
    Write-Host '  low         0 (CPU)     16           4K        1         No GPU' -ForegroundColor White
    Write-Host ''
    Write-Host '  Custom presets: edit gguf-config/presets.json -> custom_presets' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  -- Profiles (saved configs) ----------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf profiles'             'List saved profiles'
    Write-HintRow '8sync gguf save --profile <n> --engine-path <d> --model-path <f>' `
                  'Save current args as a named profile'
    Write-Host ''
    Write-Host '  -- Management -----------------------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf status'               'Show running llama-server PIDs + ports'
    Write-HintRow '8sync gguf stop'                 'Kill all running llama-server processes'
    Write-HintRow '8sync gguf help'                 'Show this help'
    Write-Host ''
    Write-Host '  -- Quick example --------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  8sync gguf serve \' -ForegroundColor Yellow
    Write-Host '    --engine-path "C:\Users\Admin\Documents\llama-cpp-cu13\src-run" \' -ForegroundColor Yellow
    Write-Host '    --model-path  "C:\Users\Admin\Downloads\Qwen3.5-4B.Q8_0.gguf" \' -ForegroundColor Yellow
    Write-Host '    --preset high --port 8080' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Endpoint after start: http://localhost:8080/v1' -ForegroundColor Cyan
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Parse args helper
# ---------------------------------------------------------------------------
function Get-ArgValue {
    param([string[]]$ArgList, [string]$Flag)
    $idx = [Array]::IndexOf($ArgList, $Flag)
    if ($idx -ge 0 -and $idx + 1 -lt $ArgList.Count -and $ArgList[$idx + 1] -notlike '--*') {
        return $ArgList[$idx + 1]
    }
    return ''
}

# ---------------------------------------------------------------------------
# Save profile
# ---------------------------------------------------------------------------
function Invoke-GgufSave {
    param([string[]]$Rest)

    $profileName = Get-ArgValue $Rest '--profile'
    $enginePath  = Get-ArgValue $Rest '--engine-path'
    $modelPath   = Get-ArgValue $Rest '--model-path'
    $preset      = Get-ArgValue $Rest '--preset'
    $port        = Get-ArgValue $Rest '--port'
    $desc        = Get-ArgValue $Rest '--desc'

    if (-not $profileName) { Write-Warning 'gguf save: --profile <name> required'; return }
    if (-not $enginePath)  { Write-Warning 'gguf save: --engine-path <dir> required'; return }
    if (-not $modelPath)   { Write-Warning 'gguf save: --model-path <file> required'; return }
    if (-not $preset)      { $preset = 'high' }
    if (-not $port)        { $port   = '8080' }

    $profilesPath = Get-GgufProfilesPath
    $data = Read-GgufJson $profilesPath
    if (-not $data) { $data = [pscustomobject]@{ profiles = [pscustomobject]@{} } }

    $entry = [pscustomobject]@{
        description = if ($desc) { $desc } else { "$profileName profile" }
        engine_path = $enginePath
        model_path  = $modelPath
        preset      = $preset
        host        = '0.0.0.0'
        port        = [int]$port
        extra_args  = @()
    }

    $data.profiles | Add-Member -NotePropertyName $profileName -NotePropertyValue $entry -Force
    Write-GgufJson $profilesPath $data

    Write-Host ''
    Write-Host ("  Profile '{0}' saved to {1}" -f $profileName, $profilesPath) -ForegroundColor Green
    Write-Host ("    Engine : {0}" -f $enginePath) -ForegroundColor DarkGray
    Write-Host ("    Model  : {0}" -f $modelPath)  -ForegroundColor DarkGray
    Write-Host ("    Preset : {0}   Port: {1}" -f $preset, $port) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Use: 8sync gguf serve --profile ' -NoNewline -ForegroundColor DarkGray
    Write-Host $profileName -ForegroundColor Cyan
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
function Show-GgufStatus {
    Write-Host ''
    Write-HintSection 'GGUF -- Running llama-server processes'
    Write-Host ''

    $procs = Get-Process -Name 'llama-server','llama-server.exe' -ErrorAction SilentlyContinue
    if (-not $procs -or $procs.Count -eq 0) {
        Write-Host '  No llama-server processes found.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    foreach ($p in $procs) {
        # Try to find the port from the command line (requires WMI)
        $cmdLine = ''
        try {
            $wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction SilentlyContinue
            $cmdLine = $wmi.CommandLine
        } catch {}

        $portMatch = [regex]::Match($cmdLine, '--port\s+(\d+)')
        $port = if ($portMatch.Success) { $portMatch.Groups[1].Value } else { '?' }

        $modelMatch = [regex]::Match($cmdLine, '--model\s+"?([^"]+\.gguf)"?')
        $model = if ($modelMatch.Success) { [System.IO.Path]::GetFileName($modelMatch.Groups[1].Value) } else { '?' }

        Write-Host ("  PID {0,-8} Port: {1,-6} Model: {2}" -f $p.Id, $port, $model) -ForegroundColor Green
        Write-Host ("    CPU: {0:N1}%  Mem: {1:N0} MB  Started: {2:HH:mm:ss}" -f `
            $p.CPU, ($p.WorkingSet64 / 1MB), $p.StartTime) -ForegroundColor DarkGray
        Write-Host ''
    }

    Write-Host '  Endpoint: http://localhost:<port>/v1' -ForegroundColor Cyan
    Write-Host '  Stop all: 8sync gguf stop' -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Stop
# ---------------------------------------------------------------------------
function Invoke-GgufStop {
    $procs = Get-Process -Name 'llama-server','llama-server.exe' -ErrorAction SilentlyContinue
    if (-not $procs -or $procs.Count -eq 0) {
        Write-Host '  No llama-server processes running.' -ForegroundColor DarkGray
        return
    }
    foreach ($p in $procs) {
        try {
            $p | Stop-Process -Force
            Write-Host ("  Stopped PID {0}" -f $p.Id) -ForegroundColor Yellow
        } catch {
            Write-Warning ("  Failed to stop PID {0}: {1}" -f $p.Id, $_)
        }
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Serve
# ---------------------------------------------------------------------------
function Invoke-GgufServe {
    param([string[]]$Rest)

    $dryRun     = $Rest -contains '--dry-run'
    $profileName = Get-ArgValue $Rest '--profile'
    $presetName  = Get-ArgValue $Rest '--preset'
    $enginePath  = Get-ArgValue $Rest '--engine-path'
    $modelPath   = Get-ArgValue $Rest '--model-path'
    $portArg     = Get-ArgValue $Rest '--port'
    $hostArg     = Get-ArgValue $Rest '--host'

    # ── Load profile if given ────────────────────────────────────────────────
    if ($profileName) {
        $data = Read-GgufJson (Get-GgufProfilesPath)
        if (-not $data -or -not $data.profiles.PSObject.Properties[$profileName]) {
            Write-Warning ("gguf: profile '{0}' not found. Run: 8sync gguf profiles" -f $profileName)
            return
        }
        $pr = $data.profiles.$profileName
        if (-not $enginePath) { $enginePath = $pr.engine_path }
        if (-not $modelPath)  { $modelPath  = $pr.model_path  }
        if (-not $presetName) { $presetName = $pr.preset       }
        if (-not $portArg)    { $portArg    = $pr.port          }
        if (-not $hostArg)    { $hostArg    = $pr.host          }
    }

    # ── Validate required args ───────────────────────────────────────────────
    if (-not $enginePath) {
        Write-Warning 'gguf serve: --engine-path <dir> is required (or use --profile <name>)'
        Write-Host '  Example: --engine-path "C:\Users\Admin\Documents\llama-cpp-cu13\src-run"' -ForegroundColor DarkGray
        return
    }
    if (-not $modelPath) {
        Write-Warning 'gguf serve: --model-path <file> is required (or use --profile <name>)'
        Write-Host '  Example: --model-path "C:\Users\Admin\Downloads\Qwen3.5-4B.Q8_0.gguf"' -ForegroundColor DarkGray
        return
    }

    # ── Defaults ─────────────────────────────────────────────────────────────
    if (-not $portArg) { $portArg = '8080'    }
    if (-not $hostArg) { $hostArg = '0.0.0.0' }

    # ── Resolve preset (auto-detect if not specified) ────────────────────────
    $autoDetected = $false
    $autoPreset   = $null
    if (-not $presetName) {
        Write-Host '  [auto-detect] Scanning hardware...' -ForegroundColor DarkGray
        $hw          = Get-GgufHardware
        $autoPreset  = Get-GgufAutoPreset $hw
        $presetName  = $autoPreset.Preset
        $autoDetected = $true
        Write-Host ("  [auto-detect] GPU: {0} ({1} GB VRAM)  CPU: {2}c/{3}t  RAM: {4} GB" -f `
            $hw.GpuName, $hw.VramGB, $hw.CpuCores, $hw.CpuThreads, $hw.RamGB) -ForegroundColor DarkGray
        Write-Host ("  [auto-detect] Chosen preset: {0}  -- {1}" -f $presetName, $autoPreset.Reason) -ForegroundColor Cyan
        Write-Host ''
    }

    # ── Resolve preset values ─────────────────────────────────────────────────
    $preset = $null
    if ($autoDetected -and $autoPreset) {
        # Build a synthetic preset object from auto-detect results
        $preset = [pscustomobject]@{
            n_gpu_layers = $autoPreset.n_gpu_layers
            cpu_threads  = $autoPreset.cpu_threads
            ctx_size     = $autoPreset.ctx_size
            parallel     = $autoPreset.parallel
            batch_size   = $autoPreset.batch_size
            flash_attn   = $autoPreset.flash_attn
            notes        = $autoPreset.Reason
        }
    } else {
        $preset = Get-GgufPreset $presetName
        if (-not $preset) {
            Write-Warning ("gguf: preset '{0}' not found. Run: 8sync gguf presets" -f $presetName)
            return
        }
    }

    # ── Locate llama-server executable ──────────────────────────────────────
    $enginePath = $enginePath.Trim('"').Trim("'")
    $modelPath  = $modelPath.Trim('"').Trim("'")

    $exeCandidates = @(
        (Join-Path $enginePath 'llama-server.exe'),
        (Join-Path $enginePath 'llama-server'),
        (Join-Path $enginePath 'server.exe'),
        (Join-Path $enginePath 'server')
    )
    $exePath = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $exePath) {
        Write-Warning ("gguf: cannot find llama-server in '{0}'" -f $enginePath)
        Write-Host '  Expected one of: llama-server.exe, llama-server, server.exe, server' -ForegroundColor DarkGray
        return
    }

    if (-not (Test-Path $modelPath)) {
        Write-Warning ("gguf: model file not found: {0}" -f $modelPath)
        return
    }

    # ── Build args ───────────────────────────────────────────────────────────
    # Flag reference (llama-server current):
    #   --threads N           generation threads
    #   --threads-batch N     prompt/batch threads  (default: same as --threads)
    #   --ctx-size N          context window
    #   --parallel N / -np    server slots
    #   -b N                  logical batch  (default: 2048)
    #   -ub N                 physical micro-batch (default: 512)
    #   --flash-attn [on|off|auto]  NOT a bare flag
    #   --cache-type-k q8_0   KV cache quantization (saves VRAM)
    #   --cache-type-v q8_0
    #   --cont-batching       continuous batching (better throughput)
    #   --jinja               enable Jinja2 chat template
    #   --metrics             expose /metrics endpoint (Prometheus)
    #   --no-mmap             don't use mmap (helps with large models)
    $serverArgs = @(
        '--model',           "`"$modelPath`"",
        '--host',            $hostArg,
        '--port',            $portArg,
        '--n-gpu-layers',    $preset.n_gpu_layers,
        '--threads',         $preset.cpu_threads,
        '--threads-batch',   $preset.cpu_threads,
        '--ctx-size',        $preset.ctx_size,
        '--parallel',        $preset.parallel,
        '-b',                $preset.batch_size,
        '-ub',               512,
        '--flash-attn',      $(if ($preset.flash_attn) { 'on' } else { 'off' }),
        '--cache-type-k',    'q8_0',
        '--cache-type-v',    'q8_0',
        '--cont-batching',
        '--jinja',
        '--metrics'
    )

    # extra_args from profile
    if ($profileName) {
        $pr = (Read-GgufJson (Get-GgufProfilesPath)).profiles.$profileName
        if ($pr.extra_args -and $pr.extra_args.Count -gt 0) {
            $serverArgs += $pr.extra_args
        }
    }

    # ── Print launch summary ─────────────────────────────────────────────────
    $ctxK = [math]::Round($preset.ctx_size / 1024)
    Write-Host ''
    Write-HintSection ('GGUF Serve -- preset: {0}{1}' -f $presetName, $(if ($profileName) { "  profile: $profileName" } else { '' }))
    Write-Host ''
    Write-Host ("  Engine  : {0}" -f $exePath)       -ForegroundColor DarkGray
    Write-Host ("  Model   : {0}" -f $modelPath)      -ForegroundColor White
    Write-Host ("  Endpoint: http://{0}:{1}/v1" -f $(if ($hostArg -eq '0.0.0.0') { 'localhost' } else { $hostArg }), $portArg) -ForegroundColor Cyan
    Write-Host ''
    Write-Host ("  Preset [{0}]" -f $presetName) -ForegroundColor DarkGray
    Write-Host ("    GPU layers : {0}" -f $preset.n_gpu_layers) -ForegroundColor White
    Write-Host ("    CPU threads: {0}" -f $preset.cpu_threads)  -ForegroundColor White
    Write-Host ("    Context    : {0}K tokens" -f $ctxK)        -ForegroundColor White
    Write-Host ("    Parallel   : {0} slots" -f $preset.parallel) -ForegroundColor White
    Write-Host ("    Batch size : {0}" -f $preset.batch_size)   -ForegroundColor White
    Write-Host ("    Flash attn : {0}" -f $(if ($preset.flash_attn) { 'on' } else { 'off' })) -ForegroundColor White
    if ($preset.notes) {
        Write-Host ("    Note       : {0}" -f $preset.notes) -ForegroundColor DarkYellow
    }
    Write-Host ''
    Write-Host ("  Command:") -ForegroundColor DarkGray
    Write-Host ("    {0} {1}" -f $exePath, ($serverArgs -join ' ')) -ForegroundColor Yellow
    Write-Host ''

    if ($dryRun) {
        Write-Host '  [dry-run] Not launching. Remove --dry-run to start.' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    Write-Host '  Starting llama-server... (Ctrl+C to stop)' -ForegroundColor Green
    Write-Host ''

    try {
        & $exePath @serverArgs
    } catch {
        Write-Warning ("gguf: server exited with error: {0}" -f $_)
    }
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------
function Invoke-GgufChat {
    param([string[]]$Rest)

    $dryRun      = $Rest -contains '--dry-run'
    $profileName = Get-ArgValue $Rest '--profile'
    $presetName  = Get-ArgValue $Rest '--preset'
    $enginePath  = Get-ArgValue $Rest '--engine-path'
    $modelPath   = Get-ArgValue $Rest '--model-path'
    $ctxArg      = Get-ArgValue $Rest '--ctx'
    $systemArg   = Get-ArgValue $Rest '--system'
    $tempArg     = Get-ArgValue $Rest '--temp'
    $gpuArg      = Get-ArgValue $Rest '--gpu-layers'

    # ── Load profile if given ────────────────────────────────────────────────
    if ($profileName) {
        $data = Read-GgufJson (Get-GgufProfilesPath)
        if (-not $data -or -not $data.profiles.PSObject.Properties[$profileName]) {
            Write-Warning ("gguf chat: profile '{0}' not found. Run: 8sync gguf profiles" -f $profileName)
            return
        }
        $pr = $data.profiles.$profileName
        if (-not $enginePath) { $enginePath = $pr.engine_path }
        if (-not $modelPath)  { $modelPath  = $pr.model_path  }
        if (-not $presetName) { $presetName = $pr.preset      }
    }

    # ── Validate required args ───────────────────────────────────────────────
    if (-not $enginePath) {
        Write-Warning 'gguf chat: --engine-path <dir> is required (or use --profile <name>)'
        Write-Host '  Example: --engine-path "C:\Users\Admin\Documents\llama-cpp-cu13\src-run"' -ForegroundColor DarkGray
        return
    }
    if (-not $modelPath) {
        Write-Warning 'gguf chat: --model-path <file> is required (or use --profile <name>)'
        Write-Host '  Example: --model-path "C:\Users\Admin\Downloads\Qwen3.5-4B.Q8_0.gguf"' -ForegroundColor DarkGray
        return
    }

    # ── Locate llama-cli ─────────────────────────────────────────────────────
    $enginePath = $enginePath.Trim('"').Trim("'")
    $modelPath  = $modelPath.Trim('"').Trim("'")

    $cliCandidates = @(
        (Join-Path $enginePath 'llama-cli.exe'),
        (Join-Path $enginePath 'llama-cli'),
        (Join-Path $enginePath 'main.exe'),
        (Join-Path $enginePath 'main')
    )
    $cliPath = $cliCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $cliPath) {
        Write-Warning ("gguf chat: cannot find llama-cli in '{0}'" -f $enginePath)
        Write-Host '  Expected: llama-cli.exe or main.exe alongside llama-server.exe' -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path $modelPath)) {
        Write-Warning ("gguf chat: model file not found: {0}" -f $modelPath)
        return
    }

    # ── Resolve preset for GPU layers + ctx ──────────────────────────────────
    $nGpuLayers = 99
    $ctxSize    = 8192

    if ($gpuArg) {
        $nGpuLayers = [int]$gpuArg
    } elseif ($presetName) {
        $p = Get-GgufPreset $presetName
        if ($p) { $nGpuLayers = $p.n_gpu_layers; $ctxSize = $p.ctx_size }
    } else {
        # Auto-detect
        $hw = Get-GgufHardware
        $ap = Get-GgufAutoPreset $hw
        $nGpuLayers = $ap.n_gpu_layers
        $ctxSize    = [math]::Min($ap.ctx_size, 16384)  # cap for interactive
        Write-Host ("  [auto-detect] {0} ({1}GB VRAM) -> preset '{2}'  {3} GPU layers  {4}K ctx" -f `
            $hw.GpuName, $hw.VramGB, $ap.Preset, $nGpuLayers, [math]::Round($ctxSize/1024)) `
            -ForegroundColor DarkGray
    }

    if ($ctxArg) { $ctxSize = [int]$ctxArg }

    # ── Temperature ──────────────────────────────────────────────────────────
    $temp = if ($tempArg) { $tempArg } else { '0.7' }

    # ── Build args ───────────────────────────────────────────────────────────
    $cliArgs = @(
        '--model',          "`"$modelPath`"",
        '--n-gpu-layers',   $nGpuLayers,
        '--ctx-size',       $ctxSize,
        '--temp',           $temp,
        '--conversation',           # multi-turn chat mode
        '--display-prompt'          # show prompt so user sees turn boundary
    )
    if ($systemArg) {
        $cliArgs += @('--system-prompt', "`"$systemArg`"")
    }

    # ── Print summary ─────────────────────────────────────────────────────────
    $ctxK = [math]::Round($ctxSize / 1024)
    $modelName = [System.IO.Path]::GetFileName($modelPath)
    Write-Host ''
    Write-HintSection ("GGUF Chat -- {0}" -f $modelName)
    Write-Host ''
    Write-Host ("  Binary : {0}" -f $cliPath)                                  -ForegroundColor DarkGray
    Write-Host ("  Model  : {0}" -f $modelPath)                                 -ForegroundColor White
    Write-Host ("  GPU    : {0} layers   Ctx: {1}K   Temp: {2}" -f $nGpuLayers, $ctxK, $temp) -ForegroundColor DarkGray
    if ($systemArg) {
        Write-Host ("  System : {0}" -f $systemArg)                             -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  Controls: type your message + Enter to send.' -ForegroundColor DarkGray
    Write-Host '            Ctrl+C to exit.' -ForegroundColor DarkGray
    Write-Host ''

    if ($dryRun) {
        Write-Host ("  Command: {0} {1}" -f $cliPath, ($cliArgs -join ' ')) -ForegroundColor Yellow
        Write-Host '  [dry-run] Remove --dry-run to start.' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    Write-Host '  Starting chat session...' -ForegroundColor Green
    Write-Host ('  ' + ('─' * 60)) -ForegroundColor DarkGray
    Write-Host ''

    try {
        & $cliPath @cliArgs
    } catch {
        Write-Warning ("gguf chat: exited with error: {0}" -f $_)
    }

    Write-Host ''
    Write-Host '  Chat session ended.' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GgufCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') {
        $Rest[0].ToLowerInvariant()
    } else { 'help' }

    switch ($sub) {
        'serve'    { Invoke-GgufServe   -Rest ($Rest | Select-Object -Skip 1) }
        'chat'     { Invoke-GgufChat    -Rest ($Rest | Select-Object -Skip 1) }
        'presets'  { Show-GgufPresets  }
        'profiles' { Show-GgufProfiles }
        'detect'   { Show-GgufDetect   }
        'hint'     { Show-GgufHint    }
        'save'     { Invoke-GgufSave    -Rest ($Rest | Select-Object -Skip 1) }
        'status'   { Show-GgufStatus   }
        'stop'     { Invoke-GgufStop   }
        'help'     { Show-GgufHelp     }
        default    { Show-GgufHelp     }
    }
}

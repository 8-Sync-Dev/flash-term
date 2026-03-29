# =============================================================================
# 8sync gguf -- Local GGUF server launcher (llama.cpp)
# =============================================================================
#
# Usage:
#   8sync gguf serve  --engine-path <dir> --model-path <file> [options]
#   8sync gguf serve  --profile <name>    [--preset <name>] [--port N]
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

function Show-GgufHelp {
    Write-Host ''
    Write-HintSection 'GGUF -- Local llama-server launcher'
    Write-Host ''
    Write-Host '  -- Launch ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync gguf serve --engine-path <dir> --model-path <file>' `
                  'Start llama-server with default preset (high)'
    Write-HintRow '8sync gguf serve --preset max'   'Override resource preset (max/high/medium/low)'
    Write-HintRow '8sync gguf serve --profile <n>'  'Load saved profile by name (engine+model+preset)'
    Write-HintRow '8sync gguf serve --port 8080'    'Override listening port (default: 8080)'
    Write-HintRow '8sync gguf serve --dry-run'      'Print the llama-server command without running it'
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
    param([string[]]$Args, [string]$Flag)
    $idx = [Array]::IndexOf($Args, $Flag)
    if ($idx -ge 0 -and $idx + 1 -lt $Args.Count -and $Args[$idx + 1] -notlike '--*') {
        return $Args[$idx + 1]
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
    if (-not $presetName) { $presetName = 'high' }
    if (-not $portArg)    { $portArg    = '8080'  }
    if (-not $hostArg)    { $hostArg    = '0.0.0.0' }

    # ── Resolve preset ───────────────────────────────────────────────────────
    $preset = Get-GgufPreset $presetName
    if (-not $preset) {
        Write-Warning ("gguf: preset '{0}' not found. Run: 8sync gguf presets" -f $presetName)
        return
    }

    # ── Locate llama-server executable ──────────────────────────────────────
    $enginePath = $enginePath.Trim('"').Trim("'")
    $modelPath  = $modelPath.Trim('"').Trim("'")

    $exeCandidates = @(
        Join-Path $enginePath 'llama-server.exe',
        Join-Path $enginePath 'llama-server',
        Join-Path $enginePath 'server.exe',
        Join-Path $enginePath 'server'
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
    $args = @(
        '--model',         "`"$modelPath`"",
        '--host',          $hostArg,
        '--port',          $portArg,
        '--n-gpu-layers',  $preset.n_gpu_layers,
        '--threads',       $preset.cpu_threads,
        '--ctx-size',      $preset.ctx_size,
        '--parallel',      $preset.parallel,
        '--batch-size',    $preset.batch_size
    )
    if ($preset.flash_attn) { $args += '--flash-attn' }

    # extra_args from profile
    if ($profileName) {
        $pr = (Read-GgufJson (Get-GgufProfilesPath)).profiles.$profileName
        if ($pr.extra_args -and $pr.extra_args.Count -gt 0) {
            $args += $pr.extra_args
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
    Write-Host ("    Flash attn : {0}" -f $(if ($preset.flash_attn) { 'yes' } else { 'no' })) -ForegroundColor White
    if ($preset.notes) {
        Write-Host ("    Note       : {0}" -f $preset.notes) -ForegroundColor DarkYellow
    }
    Write-Host ''
    Write-Host ("  Command:") -ForegroundColor DarkGray
    Write-Host ("    {0} {1}" -f $exePath, ($args -join ' ')) -ForegroundColor Yellow
    Write-Host ''

    if ($dryRun) {
        Write-Host '  [dry-run] Not launching. Remove --dry-run to start.' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    Write-Host '  Starting llama-server... (Ctrl+C to stop)' -ForegroundColor Green
    Write-Host ''

    try {
        & $exePath @args
    } catch {
        Write-Warning ("gguf: server exited with error: {0}" -f $_)
    }
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------
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
        'presets'  { Show-GgufPresets  }
        'profiles' { Show-GgufProfiles }
        'save'     { Invoke-GgufSave    -Rest ($Rest | Select-Object -Skip 1) }
        'status'   { Show-GgufStatus   }
        'stop'     { Invoke-GgufStop   }
        'help'     { Show-GgufHelp     }
        default    { Show-GgufHelp     }
    }
}

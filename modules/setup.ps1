# =============================================================================
# ft setup -- one-command bootstrap (PATH + Scoop + tools + dev runtimes + su-code)
# =============================================================================
# Usage:
#   ft setup            Ensure PATH, install Scoop, sync managed tools, dev runtimes, su-code
#   ft setup --check    Dry-run: report what's missing, change nothing
#   ft setup --no-tools     Skip tool sync
#   ft setup --no-harness   Skip su-code (AI) install
#   ft setup --no-dev       Skip dev runtimes (node/python/go/rust/chromium/docker/encore)
# =============================================================================

function Get-ScoopShimsDir { Join-Path $HOME 'scoop\shims' }

function Ensure-ScoopInstalled {
    param([switch]$DryRun)
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return $true }
    $shims = Get-ScoopShimsDir
    if (Test-Path (Join-Path $shims 'scoop.cmd')) {
        # Installed but not on this process PATH -- wire it in-process
        if ($env:PATH -notlike "*$shims*") { $env:PATH = "$shims;$env:PATH" }
        return $true
    }
    Write-Host '  [setup] installing Scoop (window may take a minute)...' -ForegroundColor Cyan
    if ($DryRun) { Write-Host '  [dry-run] would install scoop' -ForegroundColor Yellow; return $false }
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue
        $env:PATH = "$env:windir\System32;$env:windir;$env:USERPROFILE\scoop\shims;$env:PATH"
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $inst = Join-Path ([System.IO.Path]::GetTempPath()) 'scoop-inst.ps1'
        Invoke-WebRequest -Uri 'https://get.scoop.sh' -UseBasicParsing -OutFile $inst -ErrorAction Stop
        Unblock-File -Path $inst -ErrorAction SilentlyContinue
        & $inst -RunAsAdmin
        # scoop adds ~/scoop/shims to the USER path (registry); mirror it into this process
        if ($env:PATH -notlike "*$shims*") { $env:PATH = "$shims;$env:PATH" }
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host '  [ok]    Scoop installed' -ForegroundColor Green
            return $true
        }
        # Fallback: invoke the shim directly
        $scoopExe = Join-Path $shims 'scoop.cmd'
        if (Test-Path $scoopExe) { return $true }
        Write-Host '  [warn]  Scoop install may need a new shell to take effect' -ForegroundColor DarkYellow
        return $false
    } catch {
        Write-Host "  [error] Scoop install failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Ensure-PathForCore {
    # Best-effort: make git/omp/wezterm resolvable in this process if they are on disk.
    $extra = @()
    foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'bin\git\cmd'),
        (Join-Path $env:LOCALAPPDATA 'omp'),
        (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'bin\wezterm') -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'WezTerm-windows-*' } | Select-Object -First 1).FullName
    )) {
        if ($p -and (Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $extra += $p }
    }
    if ($extra.Count -gt 0) { $env:PATH = (($extra -join ';') + ";$env:PATH") }
}

function Set-DefaultWallpaper {
    # Best-effort: if the user has no wallpaper yet, fetch a tasteful dark one.
    param([string]$ConfigDir)
    $bgLua = Join-Path $ConfigDir 'current-bg.lua'
    if (Test-Path $bgLua) { return }
    if ($dryRun) { return }
    $bgDir = Join-Path $ConfigDir 'bg'
    $null = New-Item -ItemType Directory -Force -Path $bgDir
    $out = Join-Path $bgDir 'default-wallpaper.jpg'
    $url = $null
    try {
        $r = Invoke-RestMethod -Uri 'https://wallhaven.cc/api/v1/search?q=dark+minimal+abstract&categories=100&purity=100&atleast=1920x1080&sorting=toplist' -Headers @{ 'User-Agent' = 'flash-term' } -TimeoutSec 20 -ErrorAction Stop
        $url = ($r.data | Select-Object -First 1).path
    } catch {}
    if (-not $url) { return }
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $b = [System.IO.File]::ReadAllBytes($out)
        if ($b.Length -gt 20000 -and $b[0] -eq 0xFF -and $b[2] -eq 0xFF) {
            [System.IO.File]::WriteAllText($bgLua, "return [[$out]]`n", [System.Text.UTF8Encoding]::new($false))
            Write-Host '  [ok]    default wallpaper set (change: ft bg search <kw>)' -ForegroundColor Green
        }
    } catch {}
}

function Show-SetupHelp {
    Write-Host ''
    Write-Host '  FT SETUP -- one-command bootstrap' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow 'ft setup'             'PATH + Scoop + tools + dev runtimes + su-code (AI)'
    Write-HintRow 'ft setup --check'     'Dry-run: report what is missing, change nothing'
    Write-HintRow 'ft setup --no-tools'  'Skip tool sync'
    Write-HintRow 'ft setup --no-dev'    'Skip dev runtimes (node/python/go/rust/chromium/docker/encore)'
    Write-HintRow 'ft setup --no-harness''Skip su-code (AI) install'
    Write-Host ''
}

function Invoke-SetupCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    if ($Rest -contains '--help' -or $Rest -contains 'help' -or $Rest -contains '-h') { Show-SetupHelp; return }
    $dryRun    = $Rest -contains '--check' -or $Rest -contains '--dry-run'
    $noTools   = $Rest -contains '--no-tools'
    $noHarness = $Rest -contains '--no-harness'
    $noDev     = $Rest -contains '--no-dev'

    Write-Host ''
    Write-Host '  FT SETUP' -ForegroundColor Magenta
    if ($dryRun) { Write-Host '  (dry-run -- no changes)' -ForegroundColor Yellow }
    Write-Host ''

    Ensure-PathForCore
    Write-Host '  [1/5] core tools on PATH' -ForegroundColor Cyan
    foreach ($t in 'git','omp','wezterm') {
        $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
        if ($src) { Write-Host ("    [ok]    {0}: {1}" -f $t, $src) -ForegroundColor Green }
        else      { Write-Host ("    [miss]  {0} (install separately)" -f $t) -ForegroundColor DarkYellow }
    }

    Write-Host '  [2/5] Scoop' -ForegroundColor Cyan
    $scoopOk = Ensure-ScoopInstalled -DryRun:$dryRun

    # WezTerm (the terminal app) -- install via scoop if missing
    if (-not (Get-Command wezterm -ErrorAction SilentlyContinue) -and $scoopOk) {
        Write-Host '  WezTerm (terminal) -- installing via Scoop' -ForegroundColor Cyan
        if (-not $dryRun) { scoop install wezterm 2>&1 | Out-Null }
        if (Get-Command wezterm -ErrorAction SilentlyContinue) {
            Write-Host '  [ok]    WezTerm installed (Start Menu shortcut created)' -ForegroundColor Green
        }
    }

    # Nerd Font (icons/glyphs for the prompt, tabs, eza, starship) -- install if missing
    $needFont = $true
    if (Get-Command Test-NerdFontInstalled -ErrorAction SilentlyContinue) { $needFont = -not (Test-NerdFontInstalled) }
    if ($needFont -and $scoopOk -and -not $dryRun) {
        Write-Host '  Nerd Font (JetBrainsMono) -- installing via Scoop' -ForegroundColor Cyan
        scoop bucket add nerd-fonts 2>&1 | Out-Null
        scoop install JetBrainsMono-NF 2>&1 | Out-Null
        Write-Host '  [ok]    JetBrainsMono Nerd Font installed' -ForegroundColor Green
    }

    # PowerShell 7 (pwsh) -- WezTerm prefers it; enables PSReadLine typing predictions.
    if (-not (Test-Path (Join-Path $HOME 'scoop\shims\pwsh.exe')) -and $scoopOk -and -not $dryRun) {
        Write-Host '  PowerShell 7 (pwsh) -- installing via Scoop' -ForegroundColor Cyan
        scoop install pwsh 2>&1 | Out-Null
        if (Test-Path (Join-Path $HOME 'scoop\shims\pwsh.exe')) {
            Write-Host '  [ok]    PowerShell 7 installed (typing predictions enabled)' -ForegroundColor Green
        }
    }

    # CompletionPredictor -- fish-style inline path/command predictions (PSGallery)
    $pwshShim = Join-Path $HOME 'scoop\shims\pwsh.exe'
    if ((Test-Path $pwshShim) -and -not (Get-Module -ListAvailable CompletionPredictor -ErrorAction SilentlyContinue) -and -not $dryRun) {
        Write-Host '  CompletionPredictor (fish-style inline) -- installing' -ForegroundColor Cyan
        & $pwshShim -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted -EA SilentlyContinue; Install-Module CompletionPredictor -Scope CurrentUser -Force -AllowClobber -EA SilentlyContinue" 2>&1 | Out-Null
        if (Get-Module -ListAvailable CompletionPredictor -ErrorAction SilentlyContinue) {
            Write-Host '  [ok]    CompletionPredictor installed (inline path predictions)' -ForegroundColor Green
        }
    }

    if (-not $noTools) {
        Write-Host '  [3/5] managed tools (Scoop)' -ForegroundColor Cyan
        if ($scoopOk -and (Get-Command Invoke-ToolSync -ErrorAction SilentlyContinue)) {
            Invoke-ToolSync
        } else {
            Write-Host '    [skip]  Scoop unavailable -- run `ft sync` after installing Scoop' -ForegroundColor DarkYellow
        }
    }
    if (-not $noDev) {
        Write-Host '  [4/5] dev runtimes (Node/Python/Go/Rust/Chromium)' -ForegroundColor Cyan
        if ($scoopOk -and (Get-Command Invoke-DevInstall -ErrorAction SilentlyContinue)) {
            Invoke-DevInstall -DryRun:$dryRun
        } else {
            Write-Host '    [skip]  Scoop unavailable -- run `ft dev all` after installing Scoop' -ForegroundColor DarkYellow
        }
    }

    if (-not $noHarness) {
        Write-Host '  [5/5] AI harness (su-code -- provides the `8sync` command)' -ForegroundColor Cyan
        if (-not $dryRun) {
            Write-Host '  Installing su-code...' -ForegroundColor DarkGray
            try {
                iwr -useb https://8-sync-dev.github.io/su-code/install.ps1 | iex
                if (Get-Command 8sync -ErrorAction SilentlyContinue) {
                    Write-Host '  [ok]    su-code installed -- `8sync` ready' -ForegroundColor Green
                } else {
                    Write-Host '  [ok]    su-code installed -- open a NEW tab, then `8sync` works' -ForegroundColor Green
                }
                Write-Host '          Finish AI setup in a NEW tab:' -ForegroundColor Cyan
                Write-Host '            8sync setup     # once: omp + gh + MCP servers + models' -ForegroundColor Gray
                Write-Host '            8sync harness   # per-project: deploy 50 skills + /sx-* commands' -ForegroundColor Gray
                Write-Host '            8sync .         # start an AI coding session' -ForegroundColor Gray
            } catch {
                Write-Host ("  [warn]  su-code install failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
                Write-Host '          manual: irm https://8-sync-dev.github.io/su-code/install.ps1 | iex' -ForegroundColor DarkGray
            }
        } else {
            Write-Host '  [dry-run] would install su-code via irm install.ps1 | iex' -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '  Setup complete.' -ForegroundColor Green
    Write-Host '  Looks/tools: `ft help`    AI: `8sync setup` -> `8sync harness` -> `8sync .`' -ForegroundColor Green
    Write-Host ''
}

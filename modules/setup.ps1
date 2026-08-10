# =============================================================================
# 8sync setup -- one-command bootstrap (PATH + Scoop + tools + harness + doctor)
# =============================================================================
# Usage:
#   8sync setup            Ensure PATH, install Scoop, sync managed tools, deploy harness, doctor
#   8sync setup --check    Dry-run: report what's missing, change nothing
#   8sync setup --no-tools     Skip tool sync
#   8sync setup --no-harness   Skip skill/memory deploy
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
            Write-Host '  [ok]    default wallpaper set (change: 8sync bg search <kw>)' -ForegroundColor Green
        }
    } catch {}
}

function Show-SetupHelp {
    Write-Host ''
    Write-Host '  8SYNC SETUP -- one-command bootstrap' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow '8sync setup'             'PATH + Scoop + tools + harness + omp subagents + doctor'
    Write-HintRow '8sync setup --check'     'Dry-run: report what is missing, change nothing'
    Write-HintRow '8sync setup --no-tools'  'Skip tool sync'
    Write-HintRow '8sync setup --no-harness''Skip skill/memory deploy'
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

    Write-Host ''
    Write-Host '  8SYNC SETUP' -ForegroundColor Magenta
    if ($dryRun) { Write-Host '  (dry-run -- no changes)' -ForegroundColor Yellow }
    Write-Host ''

    Ensure-PathForCore
    Write-Host '  [1/4] core tools on PATH' -ForegroundColor Cyan
    foreach ($t in 'git','omp','wezterm') {
        $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
        if ($src) { Write-Host ("    [ok]    {0}: {1}" -f $t, $src) -ForegroundColor Green }
        else      { Write-Host ("    [miss]  {0} (install separately)" -f $t) -ForegroundColor DarkYellow }
    }

    Write-Host '  [2/4] Scoop' -ForegroundColor Cyan
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

    if (-not $noTools) {
        Write-Host '  [3/4] managed tools (Scoop)' -ForegroundColor Cyan
        if ($scoopOk -and (Get-Command Invoke-ToolSync -ErrorAction SilentlyContinue)) {
            Invoke-ToolSync
        } else {
            Write-Host '    [skip]  Scoop unavailable -- run `8sync sync` after installing Scoop' -ForegroundColor DarkYellow
        }
    }

    if (-not $noHarness) {
        Write-Host '  [4/4] harness deploy' -ForegroundColor Cyan
        if (Get-Command Invoke-HarnessInit -ErrorAction SilentlyContinue) {
            Invoke-HarnessInit -DryRun:$dryRun
        }
    }
    # omp-native: deploy bundled subagents (designer/librarian/reviewer/scout/...)
    $omp = Find-OmpExe
    if ($omp -and -not $dryRun) {
        Write-Host '  omp subagents (unpack)' -ForegroundColor Cyan
        & $omp agents unpack 2>&1 | Out-Null
        Write-Host '  [ok]    bundled subagents -> ~/.omp/agent/agents' -ForegroundColor Green
    }
    # Default wallpaper (best-effort, only if user has none)
    Set-DefaultWallpaper -ConfigDir (Split-Path $PSScriptRoot -Parent)

    Write-Host ''
    if (Get-Command Invoke-DoctorCommand -ErrorAction SilentlyContinue) { Invoke-DoctorCommand }
    Write-Host '  Setup complete. Run `8sync .` to start an omp session.' -ForegroundColor Green
    Write-Host ''
}

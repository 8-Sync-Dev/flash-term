# ---------------------------------------------------------------------------
#  forge.ps1 -- ForgeCode (tailcallhq/forgecode) install & management
#  Install:  curl -fsSL https://forgecode.dev/cli | sh
#  Repo:     https://github.com/tailcallhq/forgecode
# ---------------------------------------------------------------------------

# Ensure HOME env var is set (forge Rust binary requires it; Windows doesn't set it natively)
function Ensure-ForgeHomeEnv {
    # Persist to User env if missing
    $persisted = [System.Environment]::GetEnvironmentVariable('HOME', 'User')
    if (-not $persisted) {
        [System.Environment]::SetEnvironmentVariable('HOME', $env:USERPROFILE, 'User')
    }
    # Also ensure current process has it
    if (-not $env:HOME) {
        $env:HOME = $env:USERPROFILE
    }
}

# Ensure Windows console is UTF-8 (forge outputs UTF-8; legacy code pages cause
# "stdio in console mode does not support writing non-UTF-8 byte sequences")
function Ensure-ForgeConsoleUtf8 {
    try {
        # Set active code page to UTF-8 (65001) — affects child processes
        $currentCp = (chcp) 2>$null
        if ($currentCp -notmatch '65001') {
            chcp 65001 | Out-Null
        }
    } catch {}

    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)  # no BOM
        [Console]::OutputEncoding = $utf8
        [Console]::InputEncoding  = $utf8
        # PowerShell's $OutputEncoding affects pipe encoding to child processes
        $global:OutputEncoding = $utf8
    } catch {}

    # Some Rust/terminal libs check this
    if (-not $env:PYTHONIOENCODING) { $env:PYTHONIOENCODING = 'utf-8' }
    # Rust's set_var for color/terminal hints
    if (-not $env:RUST_LOG_STYLE) { $env:RUST_LOG_STYLE = 'always' }
}

function Get-ForgeInstallPath {
    # Windows: %LOCALAPPDATA%\Programs\Forge\forge.exe  (installer default)
    # Fallback: $HOME\.local\bin\forge.exe
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Forge\forge.exe'),
        (Join-Path $HOME '.local\bin\forge.exe'),
        (Join-Path $HOME '.local\bin\forge')
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    # Also try PATH
    $fromPath = Get-Command forge -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    return $null
}

function Get-ForgeVersion {
    $path = Get-ForgeInstallPath
    if (-not $path) { return $null }
    try {
        $ver = & $path --version 2>$null
        return "$ver".Trim()
    } catch {
        return $null
    }
}

function Invoke-ForgeInstall {
    param([switch]$DryRun, [switch]$Force)
    Ensure-ForgeHomeEnv

    Write-Host ''
    Write-Host '  FORGECODE -- install / update' -ForegroundColor Cyan
    Write-Host '  Repo: https://github.com/tailcallhq/forgecode' -ForegroundColor DarkGray
    Write-Host ''

    # Check existing
    $existing = Get-ForgeVersion
    if ($existing -and -not $Force) {
        Write-Host ("  [ok] forge already installed: {0}" -f $existing) -ForegroundColor Green
        Write-Host '  Use --force to reinstall/update.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if ($existing -and $Force) {
        Write-Host ("  [info] Reinstalling over existing: {0}" -f $existing) -ForegroundColor Yellow
    }

    # Determine if we have curl (Git-for-Windows / WSL-curl / system)
    $curl = Get-Command curl -ErrorAction SilentlyContinue
    if (-not $curl) {
        Write-Host '  [error] curl not found. Install Git for Windows or enable curl alias.' -ForegroundColor Red
        Write-Host '    scoop install curl' -ForegroundColor White
        Write-Host ''
        return
    }

    if ($DryRun) {
        Write-Host '  [dry-run] would run:' -ForegroundColor DarkYellow
        Write-Host '    curl -fsSL https://forgecode.dev/cli | sh' -ForegroundColor White
        Write-Host ''
        Write-Host '  Installer would:' -ForegroundColor DarkGray
        Write-Host '    1. Download forge binary for your platform' -ForegroundColor DarkGray
        Write-Host '    2. Install to %LOCALAPPDATA%\Programs\Forge\forge.exe' -ForegroundColor DarkGray
        Write-Host '    3. Install bundled deps: fzf, bat, fd' -ForegroundColor DarkGray
        Write-Host '    4. Add install dir to PATH in .bashrc / .zshrc' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host '  Running: curl -fsSL https://forgecode.dev/cli | sh' -ForegroundColor DarkGray
    Write-Host ''

    try {
        # Use sh via Git-for-Windows bash if available, otherwise PowerShell Invoke-WebRequest path
        $gitBash = @(
            'C:\Program Files\Git\bin\sh.exe',
            'C:\Program Files\Git\usr\bin\sh.exe'
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($gitBash) {
            & $gitBash -c 'curl -fsSL https://forgecode.dev/cli | sh'
        } else {
            # Fallback: download script to temp then run with sh if available
            $sh = Get-Command sh -ErrorAction SilentlyContinue
            if ($sh) {
                & $sh -c 'curl -fsSL https://forgecode.dev/cli | sh'
            } else {
                Write-Host '  [error] sh not found. Install Git for Windows to get sh.exe.' -ForegroundColor Red
                Write-Host '    scoop install git' -ForegroundColor White
                Write-Host ''
                Write-Host '  Alternatively, run manually in Git Bash:' -ForegroundColor DarkGray
                Write-Host '    curl -fsSL https://forgecode.dev/cli | sh' -ForegroundColor White
                Write-Host ''
                return
            }
        }

        Write-Host ''
        # Refresh PATH so forge is immediately available (current process + Windows User PATH)
        $forgePaths = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Forge'),
            (Join-Path $HOME '.local\bin')
        )
        foreach ($fp in $forgePaths) {
            if (-not (Test-Path $fp)) { continue }
            # Current process
            if ($env:PATH -notlike "*$fp*") {
                $env:PATH = "$fp;$env:PATH"
            }
            # Windows User PATH (persistent across sessions)
            $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            if ($userPath -notlike "*$fp*") {
                [System.Environment]::SetEnvironmentVariable('PATH', "$fp;$userPath", 'User')
                Write-Host ("  [ok] Added to Windows User PATH: {0}" -f $fp) -ForegroundColor DarkGray
            }
        }

        $ver = Get-ForgeVersion
        if ($ver) {
            Write-Host ("  [ok] forge installed successfully: {0}" -f $ver) -ForegroundColor Green
        } else {
            Write-Host '  [ok] forge installer ran. You may need to restart your shell.' -ForegroundColor Green
            Write-Host '  Tip: add to PATH:  %LOCALAPPDATA%\Programs\Forge' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ("  [error] Install failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    Write-Host ''
}

function Invoke-ForgeStatus {
    Write-Host ''
    Write-Host '  FORGECODE -- status' -ForegroundColor Cyan
    Write-Host ''

    $forgePath = Get-ForgeInstallPath
    if ($forgePath) {
        Write-Host ("  {0,-20} {1}" -f 'binary:', $forgePath) -ForegroundColor Green
        $ver = Get-ForgeVersion
        Write-Host ("  {0,-20} {1}" -f 'version:', $(if ($ver) { $ver } else { '(could not read)' })) -ForegroundColor $(if ($ver) { 'Green' } else { 'DarkYellow' })
    } else {
        Write-Host '  forge not installed.' -ForegroundColor DarkYellow
        Write-Host '  Run: 8sync forge install' -ForegroundColor DarkGray
    }

    # Check deps
    Write-Host ''
    Write-Host '  Dependencies:' -ForegroundColor DarkGray
    foreach ($dep in @('fzf', 'bat', 'fd')) {
        $found = Get-Command $dep -ErrorAction SilentlyContinue
        $color = if ($found) { 'Green' } else { 'DarkYellow' }
        $label = if ($found) { 'found' } else { 'MISSING' }
        Write-Host ("    {0,-8} {1}" -f "${dep}:", $label) -ForegroundColor $color
    }

    # Editor
    Write-Host ''
    Write-Host '  Editor:' -ForegroundColor DarkGray
    $hx = Get-Command hx -ErrorAction SilentlyContinue
    if ($hx) {
        try { $hxVer = (& hx --version 2>$null | Select-Object -First 1).Trim() } catch { $hxVer = 'helix' }
        Write-Host ("    {0,-8} {1}  ({2})" -f 'hx:', $hxVer, $hx.Source) -ForegroundColor Green
        Write-Host '    Tip: set EDITOR=hx in your profile to use Helix as forge editor' -ForegroundColor DarkGray
    } else {
        $hxFound = $false
        foreach ($candidate in @('hx', 'helix')) {
            $c = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($c) { $hxFound = $true; break }
        }
        if (-not $hxFound) {
            Write-Host '    hx:      not found  (scoop install helix)' -ForegroundColor DarkGray
        }
    }

    Write-Host ''

    # Config location hint
    $cfgDir = Join-Path $HOME '.config\forge'
    if (Test-Path $cfgDir) {
        Write-Host ("  {0,-20} {1}" -f 'config dir:', $cfgDir) -ForegroundColor DarkGray
    }

    Write-Host ''
}

function Invoke-ForgeProvider {
    param([string[]]$Rest)

    $forgePath = Get-ForgeInstallPath
    if (-not $forgePath) {
        Write-Host ''
        Write-Host '  [error] forge is not installed. Run: 8sync forge install' -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  Running: forge provider login' -ForegroundColor DarkGray
    Write-Host ''
    try {
        & $forgePath provider login
    } catch {
        Write-Host ("  [error] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Write-Host ''
}

function Invoke-ForgeUninstall {
    param([switch]$DryRun)

    Write-Host ''
    Write-Host '  FORGECODE -- uninstall' -ForegroundColor Yellow

    $forgePath = Get-ForgeInstallPath
    if (-not $forgePath) {
        Write-Host '  forge is not installed. Nothing to remove.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ("  binary: {0}" -f $forgePath) -ForegroundColor DarkGray

    $forgeDir = Split-Path $forgePath -Parent

    if ($DryRun) {
        Write-Host ("  [dry-run] would remove: {0}" -f $forgePath) -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    try {
        Remove-Item $forgePath -Force -ErrorAction Stop
        Write-Host '  [ok] forge binary removed.' -ForegroundColor Green

        # Remove dir if empty
        if ((Get-ChildItem $forgeDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $forgeDir -Force -ErrorAction SilentlyContinue
            Write-Host ("  [ok] empty dir removed: {0}" -f $forgeDir) -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ("  [error] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    # Also clean config dir
    $cfgDir = Join-Path $HOME '.config\forge'
    if (Test-Path $cfgDir) {
        Write-Host ("  Config dir kept: {0}" -f $cfgDir) -ForegroundColor DarkGray
        Write-Host '  Remove manually if desired.' -ForegroundColor DarkGray
    }

    Write-Host ''
}

function Show-ForgeHelp {
    Write-Host ''
    Write-HintSection 'FORGE -- ForgeCode AI pair programmer (tailcallhq/forgecode)'
    Write-HintRow '8sync forge install'           'Download + install forge binary via forgecode.dev/cli'
    Write-HintRow '8sync forge install --force'   'Reinstall even if already present (update)'
    Write-HintRow '8sync forge install --dry-run' 'Preview what the installer would do'
    Write-HintRow '8sync forge status'            'Show installed version, binary path, dependency check'
    Write-HintRow '8sync forge login'             'Run: forge provider login (configure AI provider)'
    Write-HintRow '8sync forge uninstall'         'Remove the forge binary'
    Write-HintRow '8sync forge uninstall --dry-run' 'Preview removal'
    Write-Host ''
    Write-Host '  After install, start forge with:' -ForegroundColor DarkGray
    Write-Host '    forge                   # interactive TUI mode' -ForegroundColor DarkGray
    Write-Host '    forge provider login    # set up API key' -ForegroundColor DarkGray
    Write-Host '    forge -p "explain ..."  # one-shot mode' -ForegroundColor DarkGray
    Write-Host ''
}

# Global wrapper: ensures HOME + UTF-8 console before every forge invocation
function global:forge {
    Ensure-ForgeHomeEnv
    Ensure-ForgeConsoleUtf8
    $forgeBin = Get-ForgeInstallPath
    if (-not $forgeBin) {
        Write-Host '[forge] forge is not installed. Run: 8sync forge install' -ForegroundColor Red
        return
    }
    & $forgeBin @args
}

function Invoke-ForgeCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun = $Rest -contains '--dry-run'
    $force  = $Rest -contains '--force'

    $sub = 'help'
    if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') {
        $sub = $Rest[0].ToLowerInvariant()
    }

    switch ($sub) {
        'install'   { Invoke-ForgeInstall -DryRun:$dryRun -Force:$force }
        'update'    { Invoke-ForgeInstall -DryRun:$dryRun -Force }
        'status'    { Invoke-ForgeStatus }
        'login'     { Invoke-ForgeProvider -Rest ($Rest | Select-Object -Skip 1) }
        'provider'  { Invoke-ForgeProvider -Rest ($Rest | Select-Object -Skip 1) }
        'uninstall' { Invoke-ForgeUninstall -DryRun:$dryRun }
        'remove'    { Invoke-ForgeUninstall -DryRun:$dryRun }
        'help'      { Show-ForgeHelp }
        default     { Show-ForgeHelp }
    }
}

# Auto-ensure HOME + UTF-8 console on module load so forge works immediately
Ensure-ForgeHomeEnv
Ensure-ForgeConsoleUtf8

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

    # GSD OAuth sync state
    Write-Host ''
    Write-Host '  GSD sync (Anthropic OAuth):' -ForegroundColor DarkGray
    $creds = Read-ForgeAnthropicCreds
    if ($creds -and $creds.AccessToken) {
        $remaining = if ($creds.ExpiresAt) { $creds.ExpiresAt - [datetime]::UtcNow } else { $null }
        $humans = if (-not $remaining) { '(no expiry)' }
                  elseif ($remaining.TotalMinutes -lt 0) { 'EXPIRED' }
                  elseif ($remaining.TotalHours -ge 1) { ('{0:F1}h left' -f $remaining.TotalHours) }
                  else { ('{0:F0}min left' -f $remaining.TotalMinutes) }
        $tokColor = if (-not $remaining -or $remaining.TotalMinutes -gt 60) { 'Green' }
                    elseif ($remaining.TotalMinutes -gt 10) { 'DarkYellow' } else { 'Red' }
        Write-Host ("    {0,-8} {1}" -f 'forge:', ('OAuth token present -- ' + $humans)) -ForegroundColor $tokColor

        $envTok = [System.Environment]::GetEnvironmentVariable('FORGE_ANTHROPIC_OAUTH_TOKEN', 'User')
        $envMatch = ($envTok -eq $creds.AccessToken)
        $envLabel = if (-not $envTok) { 'not set' } elseif ($envMatch) { 'synced' } else { 'STALE (rerun: 8sync forge sync-to-gsd)' }
        $envColor = if (-not $envTok) { 'DarkYellow' } elseif ($envMatch) { 'Green' } else { 'DarkYellow' }
        Write-Host ("    {0,-8} {1}" -f 'env:', $envLabel) -ForegroundColor $envColor

        $modelsPath = Get-GsdModelsJsonPath
        if (Test-Path $modelsPath) {
            try {
                $m = (Get-Content $modelsPath -Raw -Encoding UTF8) | ConvertFrom-Json -ErrorAction Stop
                $hasForgeProvider = $false
                if ($m.providers) {
                    foreach ($prop in $m.providers.PSObject.Properties) {
                        if ($prop.Value.apiKey -eq 'FORGE_ANTHROPIC_OAUTH_TOKEN') { $hasForgeProvider = $true; break }
                    }
                }
                if ($hasForgeProvider) {
                    Write-Host ("    {0,-8} {1}" -f 'models:', 'anthropic-forge provider present') -ForegroundColor Green
                } else {
                    Write-Host ("    {0,-8} {1}" -f 'models:', 'present but no forge provider (run: 8sync forge sync-to-gsd)') -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host ("    {0,-8} {1}" -f 'models:', 'parse error') -ForegroundColor DarkYellow
            }
        } else {
            Write-Host ("    {0,-8} {1}" -f 'models:', 'not created (run: 8sync forge sync-to-gsd)') -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '    no Forge Anthropic OAuth creds (run: forge provider login)' -ForegroundColor DarkGray
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

# ---------------------------------------------------------------------------
#  zsh on Windows -- MSYS2 + zsh + oh-my-zsh bootstrap
#  Reference: https://ohmyz.sh/#install
#  Strategy:
#    1. scoop install msys2   (only Windows-native zsh package manager we trust)
#    2. inside msys2: pacman -S --noconfirm zsh git curl
#    3. run oh-my-zsh installer non-interactively via msys2 bash
# ---------------------------------------------------------------------------

function Get-MsysBashPath {
    # Prefer scoop-installed msys2; fall back to system install
    $candidates = @(
        (Join-Path $env:USERPROFILE 'scoop\apps\msys2\current\usr\bin\bash.exe'),
        'C:\msys64\usr\bin\bash.exe',
        'C:\tools\msys64\usr\bin\bash.exe'
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    $fromPath = Get-Command bash -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -match 'msys' } |
                Select-Object -First 1
    if ($fromPath) { return $fromPath.Source }
    return $null
}

function Install-MSYS2ViaScoop {
    [OutputType([string])]
    param([switch]$DryRun)

    $existing = Get-MsysBashPath
    if ($existing) {
        Write-Host ("  [ok] msys2 already present: {0}" -f $existing) -ForegroundColor Green
        return [string]$existing
    }

    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $scoop) {
        Write-Host '  [error] scoop not found. Install scoop first:' -ForegroundColor Red
        Write-Host '    irm get.scoop.sh | iex' -ForegroundColor White
        return $null
    }

    if ($DryRun) {
        Write-Host '  [dry-run] would run: scoop install msys2' -ForegroundColor DarkYellow
        return $null
    }

    Write-Host '  Running: scoop install msys2  (~400 MB, ~2 min)' -ForegroundColor Yellow
    try {
        # Pipe scoop output directly to the host so it streams visibly to the
        # user WITHOUT polluting this function's return pipeline. Without
        # Out-Host the objects scoop emits would be collected as part of the
        # returned value, turning $bash into an array on the calling side.
        & scoop install msys2 2>&1 | Out-Host
    } catch {
        Write-Host ("  [error] scoop install msys2 failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }

    # msys2 post-install: first `bash -lc true` initializes the filesystem.
    # scoop post_install hook normally does this; invoke once to be safe.
    $bash = Get-MsysBashPath
    if ($bash) {
        try { & $bash -lc 'true' 2>&1 | Out-Null } catch {}
        Write-Host ("  [ok] msys2 installed: {0}" -f $bash) -ForegroundColor Green
        return [string]$bash
    }
    return $null
}

function Install-ZshPackage {
    param(
        [Parameter(Mandatory)][string]$BashPath,
        [switch]$DryRun
    )

    # Check if zsh already installed inside msys2
    $existing = $null
    try {
        $existing = & $BashPath -lc 'command -v zsh 2>/dev/null' 2>$null
    } catch {}
    if ($existing) {
        $existing = "$existing".Trim()
        if ($existing) {
            Write-Host ("  [ok] zsh already installed in msys2: {0}" -f $existing) -ForegroundColor Green
            return $true
        }
    }

    if ($DryRun) {
        Write-Host '  [dry-run] would run: pacman -S --noconfirm --needed zsh git curl' -ForegroundColor DarkYellow
        return $false
    }

    Write-Host '  Running: pacman -S --noconfirm --needed zsh git curl' -ForegroundColor Yellow
    try {
        # -Sy refreshes db; --needed skips if already installed; --noconfirm for unattended.
        & $BashPath -lc 'pacman -Sy --noconfirm && pacman -S --noconfirm --needed zsh git curl'
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  [error] pacman failed.' -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host ("  [error] {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
    Write-Host '  [ok] zsh + git + curl installed in msys2.' -ForegroundColor Green
    return $true
}

function ConvertTo-MsysPath {
    # Convert a Windows path "C:\Users\Admin" -> MSYS/Cygwin path "/c/Users/Admin".
    # Required when passing $env:HOME through to msys2 bash.
    param([Parameter(Mandatory)][string]$WindowsPath)
    $p = $WindowsPath -replace '\\','/'
    if ($p -match '^([A-Za-z]):(/.*)?$') {
        $drive  = $matches[1].ToLower()
        $rest   = if ($matches[2]) { $matches[2] } else { '' }
        return "/$drive$rest"
    }
    return $p
}

function Ensure-EditorEnv {
    # Make forge zsh doctor happy by setting EDITOR/FORGE_EDITOR.
    # Prefer existing value; else pick hx (helix), nvim, vim, nano in that order.
    [OutputType([string])]
    param()

    $existing = $env:EDITOR
    if (-not $existing) {
        $existing = [System.Environment]::GetEnvironmentVariable('EDITOR', 'User')
    }
    if ($existing) {
        if (-not $env:EDITOR) { $env:EDITOR = $existing }
        if (-not $env:FORGE_EDITOR) { $env:FORGE_EDITOR = $existing }
        return $existing
    }

    foreach ($cand in @('hx','nvim','vim','nano')) {
        if (Get-Command $cand -ErrorAction SilentlyContinue) {
            $env:EDITOR       = $cand
            $env:FORGE_EDITOR = $cand
            try {
                [System.Environment]::SetEnvironmentVariable('EDITOR',       $cand, 'User')
                [System.Environment]::SetEnvironmentVariable('FORGE_EDITOR', $cand, 'User')
            } catch {}
            return $cand
        }
    }
    return $null
}

function Get-ForgeManagedOmzBlock {
    # v2 managed block. Adds a FORGE_LIGHT_ZSH=1 branch that:
    #   * disables oh-my-zsh theme (robbyrussell runs `git status` every render)
    #   * disables the `git` omz plugin
    #   * caps zsh-syntax-highlighting to first 60 chars of buffer
    #     (the plugin re-parses the WHOLE buffer on every keystroke -- after
    #      Forge streams a long AI response, this turns every `:` keypress
    #      from the 2nd message onward into a multi-hundred-ms stall).
    #   * caps zsh-autosuggestions to buffers <= 20 chars + disables auto-rebind
    #   * sets a bare prompt after omz loads.
    #
    # These env vars are read by Forge's own plugin block (sourced later in
    # the same .zshrc) at init time, so our caps apply even though we do not
    # own that block.
    [OutputType([string])]
    param()

    return @(
        '# --- Oh My Zsh (managed by 8sync forge zsh v2) ---'
        '# Load before Forge plugins so the prompt + omz plugins initialize first.'
        '# FORGE_LIGHT_ZSH=1 (set by `8sync forge enter`) switches to a light'
        '# profile that keeps AI chat responsive from message 2 onward.'
        'export ZSH="$HOME/.oh-my-zsh"'
        ''
        'if [[ -n "$FORGE_LIGHT_ZSH" ]]; then'
        '    ZSH_THEME=""'
        '    plugins=()'
        '    DISABLE_UNTRACKED_FILES_DIRTY="true"'
        '    ZSH_HIGHLIGHT_MAXLENGTH=60'
        '    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20'
        '    ZSH_AUTOSUGGEST_MANUAL_REBIND=1'
        'else'
        '    ZSH_THEME="robbyrussell"'
        '    plugins=(git)'
        'fi'
        ''
        'source $ZSH/oh-my-zsh.sh'
        ''
        'if [[ -n "$FORGE_LIGHT_ZSH" ]]; then'
        "    PROMPT='%n %1~ %# '"
        "    RPROMPT=''"
        'fi'
        '# --- end Oh My Zsh ---'
        ''
    ) -join "`n"
}

function Ensure-ZshrcSourcesOmz {
    # Ensure $HOME/.zshrc contains a block that sources oh-my-zsh.
    # This is required because oh-my-zsh installer with KEEP_ZSHRC=yes does NOT
    # touch an existing .zshrc -- Forge's own installer creates .zshrc first,
    # so the omz installer sees one already and leaves it alone.
    #
    # We inject a managed block BEFORE any existing content so the omz prompt +
    # plugins load before Forge's own plugin/theme initialization.
    #
    # v2 migration: if a v1 block is present (no FORGE_LIGHT_ZSH branch), it is
    # stripped and replaced with v2 so the light-mode caps become available
    # without the user having to rerun `8sync forge zsh`.
    [OutputType([bool])]
    param()

    $zshrc = Join-Path $env:USERPROFILE '.zshrc'
    $winOmzDir = Join-Path $env:USERPROFILE '.oh-my-zsh'
    if (-not (Test-Path $winOmzDir)) { return $false }

    $existing = ''
    if (Test-Path $zshrc) {
        try { $existing = Get-Content $zshrc -Raw -Encoding UTF8 } catch {}
    }

    $hasV2 = $existing -match '# --- Oh My Zsh \(managed by 8sync forge zsh v2\) ---'
    $hasV1 = (-not $hasV2) -and ($existing -match '# --- Oh My Zsh \(managed by 8sync forge zsh\) ---')

    if ($hasV2) {
        Write-Host '  [ok] .zshrc already has v2 managed block (FORGE_LIGHT_ZSH aware)' -ForegroundColor Green
        return $true
    }

    # If user already has a custom `source $ZSH/oh-my-zsh.sh` and no managed
    # block at all, leave it alone -- user is driving.
    if (-not $hasV1 -and $existing -match 'source\s+"?\$ZSH/oh-my-zsh\.sh"?') {
        Write-Host '  [ok] .zshrc has custom omz source line (not managed by 8sync -- not touching)' -ForegroundColor Green
        return $true
    }

    # If v1 block present, strip it. The v1 block spans from its begin marker
    # through its `# --- end Oh My Zsh ---` terminator, single-line regex ok
    # because both markers are on their own lines.
    $stripped = $existing
    if ($hasV1) {
        $v1Pattern = '(?s)# --- Oh My Zsh \(managed by 8sync forge zsh\) ---.*?# --- end Oh My Zsh ---\r?\n?'
        $stripped = [regex]::Replace($existing, $v1Pattern, '')
        Write-Host '  [info] v1 managed block detected -- migrating to v2.' -ForegroundColor DarkYellow
    }

    $block    = Get-ForgeManagedOmzBlock
    $combined = $block + $stripped
    # Normalize line endings + ensure trailing newline; write UTF-8 no-BOM.
    $combined = ($combined -replace "`r`n", "`n").TrimEnd() + "`n"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try {
        # Backup first
        if (Test-Path $zshrc) {
            $backup = $zshrc + '.bak-8sync-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item $zshrc $backup -Force
            Write-Host ("  [ok] backed up .zshrc -> {0}" -f $backup) -ForegroundColor DarkGray
        }
        [System.IO.File]::WriteAllText($zshrc, $combined, $utf8)
        if ($hasV1) {
            Write-Host ("  [ok] migrated .zshrc managed block v1 -> v2: {0}" -f $zshrc) -ForegroundColor Green
        } else {
            Write-Host ("  [ok] prepended v2 oh-my-zsh source block to {0}" -f $zshrc) -ForegroundColor Green
        }
        return $true
    } catch {
        Write-Host ("  [error] could not write .zshrc: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Invoke-ForgeLightMode {
    # Upgrade an existing .zshrc to the v2 managed block without rerunning the
    # full `8sync forge zsh` install. Safe to call repeatedly (idempotent).
    Write-Host ''
    Write-Host '  FORGE -- enable light-zsh mode (fix lag from AI chat message 2+)' -ForegroundColor Cyan
    Write-Host ''

    $winOmzDir = Join-Path $env:USERPROFILE '.oh-my-zsh'
    if (-not (Test-Path $winOmzDir)) {
        Write-Host ('  [error] oh-my-zsh not found at {0}' -f $winOmzDir) -ForegroundColor Red
        Write-Host '  Run first: 8sync forge zsh' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $ok = Ensure-ZshrcSourcesOmz
    Write-Host ''
    if ($ok) {
        Write-Host '  Next step:' -ForegroundColor Cyan
        Write-Host '    8sync forge enter     # zsh auto-applies light mode (FORGE_LIGHT_ZSH=1)' -ForegroundColor White
        Write-Host ''
        Write-Host '  To opt out of light mode for a session:' -ForegroundColor DarkGray
        Write-Host '    unset FORGE_LIGHT_ZSH && exec zsh' -ForegroundColor DarkGray
    } else {
        Write-Host '  [warn] no changes made.' -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Invoke-ForgeThinking {
    # Configure Forge reasoning effort via the canonical `forge config` CLI.
    #
    # Why CLI, not regex on a TOML file:
    #   Forge resolves its global config path itself (`forge config path`).
    #   On legacy installs that path is ~/forge/.forge.toml; on migrated
    #   installs it is ~/.forge/.forge.toml. Hardcoding either path silently
    #   edits the wrong file -- the symptom is `:forge` inside the TUI still
    #   showing the old [reasoning] block. Using `forge config set` always
    #   writes to whatever file Forge will actually load.
    #
    # Effort levels supported by Forge 2.12+:
    #   none | minimal | low | medium | high | xhigh | max
    #
    # 8sync mappings:
    #   off  -> none      (thinking effectively disabled)
    #   on   -> high      (re-enable at the historical default)
    #   <other> -> passed through verbatim if Forge accepts it
    #
    # Usage:
    #   8sync forge thinking                 -- show current [reasoning] block
    #   8sync forge thinking off             -- effort = "none"
    #   8sync forge thinking low|medium|high -- set that effort level
    #   8sync forge thinking xhigh|max       -- maximum-effort levels
    #   8sync forge thinking on              -- alias for high
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    Write-Host ''
    Write-Host '  FORGE -- thinking (reasoning) setting' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Test-CommandExists 'forge')) {
        Write-Host '  [error] forge CLI not found in PATH.' -ForegroundColor Red
        Write-Host '  Install it first:  8sync forge install' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Resolve the actual config file Forge uses (informational only).
    $tomlPath = $null
    try {
        $tomlPath = (& forge config path 2>$null | Select-Object -First 1).Trim()
    } catch {
        # ignore; fall back to "?"
    }

    # Read current [reasoning] via the CLI -- guaranteed to reflect what Forge sees.
    function Script:Read-ForgeReasoning {
        $cur = [pscustomobject]@{ Effort = '?'; Enabled = '?' }
        try {
            # --porcelain emits raw TOML. Without it, Forge pretty-prints with
            # styled section headers that don't include literal "[reasoning]".
            $out = & forge config list --porcelain 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $out) { return $cur }

            $inSection = $false
            foreach ($line in $out) {
                $t = $line.Trim()
                if ($t -eq '[reasoning]')   { $inSection = $true;  continue }
                if ($t -match '^\[.*\]$')   { $inSection = $false; continue }
                if (-not $inSection) { continue }
                if ($t -match '^effort\s*=\s*"([^"]+)"')      { $cur.Effort  = $Matches[1] }
                elseif ($t -match '^enabled\s*=\s*(true|false)') { $cur.Enabled = $Matches[1] }
            }
        } catch { }
        return $cur
    }

    $cur = Read-ForgeReasoning

    $level = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'status' }

    # Show current state only.
    if ($level -in @('status', '')) {
        if ($tomlPath) {
            Write-Host ('  Config file: {0}' -f $tomlPath) -ForegroundColor DarkGray
        }
        Write-Host '  Current [reasoning] (live, via `forge config list`):' -ForegroundColor DarkGray
        Write-Host ("    effort  = `"{0}`"" -f $cur.Effort)  -ForegroundColor White
        Write-Host ("    enabled = {0}" -f $cur.Enabled) -ForegroundColor White
        Write-Host ''
        Write-Host '  Usage: 8sync forge thinking [off|low|medium|high|xhigh|max|on]' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Map friendly aliases -> Forge effort levels.
    $newEffort = switch ($level) {
        'off'     { 'none' }
        'on'      { 'high' }
        'med'     { 'medium' }
        'none'    { 'none' }
        'minimal' { 'minimal' }
        'low'     { 'low' }
        'medium'  { 'medium' }
        'high'    { 'high' }
        'xhigh'   { 'xhigh' }
        'max'     { 'max' }
        default   { $null }
    }

    if (-not $newEffort) {
        Write-Host ("  [error] unknown level '{0}'." -f $level) -ForegroundColor Red
        Write-Host '  Valid: off | none | minimal | low | medium | high | xhigh | max | on' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ("  before: effort = `"{0}`"  enabled = {1}" -f $cur.Effort, $cur.Enabled) -ForegroundColor DarkGray
    Write-Host ("  applying: forge config set reasoning-effort {0}" -f $newEffort) -ForegroundColor Yellow

    try {
        $setOut = & forge config set reasoning-effort $newEffort 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('  [error] forge config set failed: {0}' -f ($setOut -join ' ')) -ForegroundColor Red
            Write-Host ''
            return
        }
    } catch {
        Write-Host ('  [error] could not invoke forge config set: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return
    }

    $after = Read-ForgeReasoning
    Write-Host ("  after:  effort = `"{0}`"  enabled = {1}" -f $after.Effort, $after.Enabled) -ForegroundColor Green
    if ($tomlPath) {
        Write-Host ('  Written to: {0}' -f $tomlPath) -ForegroundColor DarkGray
    }
    Write-Host '  Takes effect for the next Forge session (exit and re-enter forge).' -ForegroundColor DarkGray
    Write-Host ''
}

function Read-ForgeConfigPorcelain {
    # Returns a hashtable section -> ordered hashtable of key=value (raw strings).
    # Uses `forge config list --porcelain` (canonical TOML) so we always reflect
    # the file Forge actually loads (works on both ~/forge/ and ~/.forge/ layouts).
    [OutputType([hashtable])]
    param()
    $result = @{}
    try {
        $out = & forge config list --porcelain 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return $result }
        $section = '_root'
        $result[$section] = [ordered]@{}
        foreach ($line in $out) {
            $t = "$line".Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            if ($t -match '^\[([^\]]+)\]$') {
                $section = $Matches[1]
                if (-not $result.ContainsKey($section)) { $result[$section] = [ordered]@{} }
                continue
            }
            if ($t -match '^([A-Za-z0-9_\-\.]+)\s*=\s*(.+)$') {
                $k = $Matches[1]
                $v = $Matches[2].Trim()
                # Strip surrounding quotes for display
                if ($v -match '^"(.*)"$') { $v = $Matches[1] }
                $result[$section][$k] = $v
            }
        }
    } catch {}
    return $result
}

function Get-ForgeConfigPath {
    [OutputType([string])]
    param()
    try {
        $p = (& forge config path 2>$null | Select-Object -First 1)
        if ($p) { return "$p".Trim() }
    } catch {}
    return $null
}

function Invoke-ForgeModel {
    # Show/set the active Forge model. Auto-detects provider login state so the
    # user can see at a glance which provider+model+auth Forge is actually using.
    #
    # Forge stores active model as TWO keys: [session].provider_id + [session].model_id.
    # `forge config set model` requires <PROVIDER> <MODEL> together.
    #
    # Usage:
    #   8sync forge model                          -- show current provider+model+auth+reasoning
    #   8sync forge model list                     -- run `forge provider list` (providers + logged-in)
    #   8sync forge model <model>                  -- set model on CURRENT provider (keeps provider_id)
    #   8sync forge model <provider> <model>       -- set both atomically
    #   8sync forge model set <provider> <model>   -- explicit set form
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    Write-Host ''
    Write-Host '  FORGE -- model & provider' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Test-CommandExists 'forge')) {
        Write-Host '  [error] forge CLI not found. Run: 8sync forge install' -ForegroundColor Red
        Write-Host ''
        return
    }

    if (-not $Rest) { $Rest = @() }
    $action = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'status' }

    # Subcommand: list available providers (Forge has no `model list`; providers are the unit)
    if ($action -eq 'list' -or $action -eq 'ls') {
        Write-Host '  Running: forge provider list' -ForegroundColor DarkGray
        Write-Host ''
        try { & forge provider list } catch {
            Write-Host ('  [error] {0}' -f $_.Exception.Message) -ForegroundColor Red
        }
        Write-Host ''
        Write-Host '  Tip: providers marked [logged in yes] are ready. To switch:' -ForegroundColor DarkGray
        Write-Host '    8sync forge model <provider_id> <model_id>' -ForegroundColor DarkGray
        Write-Host '    e.g. 8sync forge model claude_code claude-sonnet-4-6' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Resolve provider+model args
    $argv = @($Rest)
    if ($argv.Count -gt 0 -and $argv[0].ToLowerInvariant() -eq 'set') {
        $argv = @($argv | Select-Object -Skip 1)
    }
    $newProvider = $null
    $newModel    = $null
    if ($argv.Count -ge 2) {
        $newProvider = $argv[0]
        $newModel    = $argv[1]
    } elseif ($argv.Count -eq 1 -and $argv[0] -notlike '--*' -and $argv[0].ToLowerInvariant() -notin @('status','')) {
        # Single arg -> model only; reuse current provider_id
        $newModel = $argv[0]
    }

    $cfg = Read-ForgeConfigPorcelain
    $tomlPath = Get-ForgeConfigPath
    $curProvider = $null
    $curModel    = $null
    if ($cfg['session']) {
        if ($cfg['session'].Contains('provider_id')) { $curProvider = $cfg['session']['provider_id'] }
        if ($cfg['session'].Contains('model_id'))    { $curModel    = $cfg['session']['model_id'] }
    }
    $curEffort = '?'
    if ($cfg['reasoning'] -and $cfg['reasoning'].Contains('effort')) { $curEffort = $cfg['reasoning']['effort'] }

    if ($newModel) {
        if (-not $newProvider) {
            if (-not $curProvider) {
                Write-Host '  [error] no current provider set; specify both:' -ForegroundColor Red
                Write-Host '    8sync forge model <provider_id> <model_id>' -ForegroundColor DarkGray
                Write-Host '  See providers:  8sync forge model list' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
            $newProvider = $curProvider
            Write-Host ('  (reusing current provider: {0})' -f $newProvider) -ForegroundColor DarkGray
        }
        Write-Host ('  before: provider={0}  model={1}' -f $curProvider, $curModel) -ForegroundColor DarkGray
        Write-Host ('  applying: forge config set model {0} {1}' -f $newProvider, $newModel) -ForegroundColor Yellow
        try {
            $setOut = & forge config set model $newProvider $newModel 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host ('  [error] forge config set model failed:' ) -ForegroundColor Red
                $setOut | ForEach-Object { Write-Host ('    {0}' -f $_) -ForegroundColor Red }
                Write-Host ''
                Write-Host '  See valid providers:  8sync forge model list' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
        } catch {
            Write-Host ('  [error] {0}' -f $_.Exception.Message) -ForegroundColor Red
            Write-Host ''
            return
        }
        $after = Read-ForgeConfigPorcelain
        $aProv = if ($after['session'] -and $after['session'].Contains('provider_id')) { $after['session']['provider_id'] } else { '?' }
        $aMod  = if ($after['session'] -and $after['session'].Contains('model_id'))    { $after['session']['model_id'] }    else { '?' }
        Write-Host ('  after:  provider={0}  model={1}' -f $aProv, $aMod) -ForegroundColor Green
        if ($tomlPath) { Write-Host ('  Written to: {0}' -f $tomlPath) -ForegroundColor DarkGray }
        Write-Host '  Takes effect for the next Forge session.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Status view
    if ($tomlPath) { Write-Host ('  Config file:  {0}' -f $tomlPath) -ForegroundColor DarkGray }
    Write-Host ('  Provider:     {0}' -f $(if ($curProvider) { $curProvider } else { '(unset)' })) -ForegroundColor White
    Write-Host ('  Model:        {0}' -f $(if ($curModel)    { $curModel }    else { '(unset)' })) -ForegroundColor White
    Write-Host ('  Reasoning:    effort = "{0}"' -f $curEffort) -ForegroundColor White

    # OAuth state (only meaningful for claude_code provider)
    $creds = Read-ForgeAnthropicCreds
    if ($creds -and $creds.AccessToken) {
        $remaining = if ($creds.ExpiresAt) { $creds.ExpiresAt - [datetime]::UtcNow } else { $null }
        $humans = if (-not $remaining) { '(no expiry)' }
                  elseif ($remaining.TotalMinutes -lt 0) { 'EXPIRED' }
                  elseif ($remaining.TotalHours -ge 1) { ('{0:F1}h left' -f $remaining.TotalHours) }
                  else { ('{0:F0}min left' -f $remaining.TotalMinutes) }
        $color = if (-not $remaining -or $remaining.TotalMinutes -gt 60) { 'Green' }
                 elseif ($remaining.TotalMinutes -gt 10) { 'DarkYellow' } else { 'Red' }
        Write-Host ('  Auth:         claude_code OAuth -- {0}' -f $humans) -ForegroundColor $color
    } else {
        Write-Host '  Auth:         (no claude_code OAuth; for other providers see: 8sync forge model list)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  Usage:' -ForegroundColor DarkGray
    Write-Host '    8sync forge model list                       # providers + login state' -ForegroundColor DarkGray
    Write-Host '    8sync forge model <model>                    # change model, keep provider' -ForegroundColor DarkGray
    Write-Host '    8sync forge model <provider> <model>         # change both atomically' -ForegroundColor DarkGray
    Write-Host '    8sync forge config keys                      # list ALL valid config-set keys (schema)' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ForgeConfig {
    # Generic Forge config viewer/editor. Wraps `forge config {list|set|get|path}`.
    #
    # Usage:
    #   8sync forge config                          -- show all current values
    #   8sync forge config path                     -- print config file path
    #   8sync forge config keys                     -- list VALID set keys w/ argument schema (from forge --help)
    #   8sync forge config get <key>                -- forge config get <key>
    #   8sync forge config set <key> <args...>      -- forge config set <key> <args...>
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    Write-Host ''
    Write-Host '  FORGE -- config' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Test-CommandExists 'forge')) {
        Write-Host '  [error] forge CLI not found. Run: 8sync forge install' -ForegroundColor Red
        Write-Host ''
        return
    }

    if (-not $Rest) { $Rest = @() }
    $action = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'show' }

    switch ($action) {
        'path' {
            $p = Get-ForgeConfigPath
            if ($p) { Write-Host ('  {0}' -f $p) -ForegroundColor White }
            else    { Write-Host '  [warn] could not resolve forge config path' -ForegroundColor DarkYellow }
            Write-Host ''
            return
        }
        'keys' {
            # Live discovery of every key Forge will accept, with arg schema.
            # This is the answer to "how do I know valid key names?" -- we ask Forge itself.
            # Note: Forge emits ANSI escape codes even when piped, so strip them first.
            $ansi = [regex]'\x1b\[[0-9;]*[A-Za-z]'
            Write-Host '  Valid `forge config set` keys (live from forge --help):' -ForegroundColor DarkGray
            Write-Host ''
            $setHelp = & forge config set --help 2>&1
            $keys = @()
            $inCmds = $false
            foreach ($line in $setHelp) {
                $t = $ansi.Replace("$line", '')
                if ($t -match '^Commands:') { $inCmds = $true; continue }
                if ($inCmds) {
                    if ($t -match '^\s*$' -or $t -match '^Options:' -or $t -match '^Usage:') { break }
                    if ($t -match '^\s+(\S+)\s+(.+)$') {
                        $k = $Matches[1]
                        if ($k -eq 'help') { continue }
                        $keys += [pscustomobject]@{ Key = $k; Desc = $Matches[2].Trim() }
                    }
                }
            }
            foreach ($k in $keys) {
                # Pull argument shape from `forge config set <key> --help`
                $argShape = ''
                try {
                    $kh = & forge config set $k.Key --help 2>&1
                    foreach ($l in $kh) {
                        $cl = $ansi.Replace("$l", '')
                        if ($cl -match '^Usage:\s+(.+)$') {
                            $u = $Matches[1]
                            # Drop "forge config set <key> [OPTIONS]" prefix, keep the <ARGS>
                            $argShape = ($u -replace '^.*\[OPTIONS\]\s*','').Trim()
                            break
                        }
                    }
                } catch {}
                Write-Host ('    {0,-18} {1}' -f $k.Key, $k.Desc) -ForegroundColor White
                if ($argShape) {
                    Write-Host ('    {0,-18} args: {1}' -f '', $argShape) -ForegroundColor DarkGray
                }
            }
            if ($keys.Count -eq 0) {
                Write-Host '    (could not parse forge --help; falling back to known keys)' -ForegroundColor DarkYellow
                Write-Host '    model             <PROVIDER> <MODEL>     -- active model + provider atomically' -ForegroundColor White
                Write-Host '    commit            <PROVIDER> <MODEL>     -- model for commit message generation' -ForegroundColor White
                Write-Host '    suggest           <PROVIDER> <MODEL>     -- model for command suggestion' -ForegroundColor White
                Write-Host '    reasoning-effort  <EFFORT>               -- none|minimal|low|medium|high|xhigh|max' -ForegroundColor White
            }
            Write-Host ''
            Write-Host '  Set any key with:' -ForegroundColor DarkGray
            Write-Host '    8sync forge config set <key> <args...>' -ForegroundColor DarkGray
            Write-Host '  Examples:' -ForegroundColor DarkGray
            Write-Host '    8sync forge config set model claude_code claude-sonnet-4-6' -ForegroundColor DarkGray
            Write-Host '    8sync forge config set reasoning-effort high' -ForegroundColor DarkGray
            Write-Host '    8sync forge config set commit claude_code claude-haiku-4-5' -ForegroundColor DarkGray
            Write-Host ''
            return
        }
        'get' {
            if ($Rest.Count -lt 2) {
                Write-Host '  Usage: 8sync forge config get <key>' -ForegroundColor DarkYellow
                Write-Host '  See valid keys:  8sync forge config keys' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
            $key = $Rest[1]
            try {
                $out = & forge config get $key 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host ('  [error] forge config get {0} failed:' -f $key) -ForegroundColor Red
                    $out | ForEach-Object { Write-Host ('    {0}' -f $_) -ForegroundColor Red }
                    Write-Host '  See valid keys:  8sync forge config keys' -ForegroundColor DarkGray
                } else {
                    $out | ForEach-Object { Write-Host ('    {0}' -f $_) -ForegroundColor White }
                }
            } catch {
                Write-Host ('  [error] {0}' -f $_.Exception.Message) -ForegroundColor Red
            }
            Write-Host ''
            return
        }
        'set' {
            if ($Rest.Count -lt 3) {
                Write-Host '  Usage: 8sync forge config set <key> <args...>' -ForegroundColor DarkYellow
                Write-Host '  See valid keys + arg shape:  8sync forge config keys' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
            $key  = $Rest[1]
            $args = @($Rest | Select-Object -Skip 2)
            Write-Host ('  applying: forge config set {0} {1}' -f $key, ($args -join ' ')) -ForegroundColor Yellow
            try {
                $setOut = & forge config set $key @args 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host '  [error] forge config set failed:' -ForegroundColor Red
                    $setOut | ForEach-Object { Write-Host ('    {0}' -f $_) -ForegroundColor Red }
                    Write-Host ''
                    Write-Host '  See valid keys + arg shape:  8sync forge config keys' -ForegroundColor DarkGray
                } else {
                    Write-Host ('  [ok] {0} {1}' -f $key, ($args -join ' ')) -ForegroundColor Green
                    $p = Get-ForgeConfigPath
                    if ($p) { Write-Host ('  Written to: {0}' -f $p) -ForegroundColor DarkGray }
                }
            } catch {
                Write-Host ('  [error] {0}' -f $_.Exception.Message) -ForegroundColor Red
            }
            Write-Host ''
            return
        }
        default {
            # show / list (current values, porcelain)
            $p = Get-ForgeConfigPath
            if ($p) { Write-Host ('  Config file: {0}' -f $p) -ForegroundColor DarkGray }
            Write-Host ''
            try {
                $out = & forge config list --porcelain 2>&1
                if ($LASTEXITCODE -ne 0 -or -not $out) {
                    Write-Host '  [warn] forge config list returned no output' -ForegroundColor DarkYellow
                } else {
                    $out | ForEach-Object { Write-Host ('    {0}' -f $_) -ForegroundColor White }
                }
            } catch {
                Write-Host ('  [error] {0}' -f $_.Exception.Message) -ForegroundColor Red
            }
            Write-Host ''
            Write-Host '  More:' -ForegroundColor DarkGray
            Write-Host '    8sync forge config keys              # list VALID set keys + arg schema' -ForegroundColor DarkGray
            Write-Host '    8sync forge config get <key>         # read one key' -ForegroundColor DarkGray
            Write-Host '    8sync forge config set <key> <args>  # write any key' -ForegroundColor DarkGray
            Write-Host '    8sync forge config path              # config file path' -ForegroundColor DarkGray
            Write-Host ''
        }
    }
}

function Get-KarpathySkillContent {
    # Latest Karpathy guidelines skill content, embedded for offline use.
    # Source: https://github.com/forrestchang/andrej-karpathy-skills
    #         skills/karpathy-guidelines/SKILL.md
    # The YAML frontmatter + markdown body are exactly what Forge's SKILL.md
    # loader expects (https://forgecode.dev/docs/skills/).
    [OutputType([string])]
    param()

    return @'
---
name: karpathy-guidelines
description: MANDATORY — read before any coding task. Behavioral guidelines to reduce common LLM coding mistakes. Apply when writing, reviewing, or refactoring code to avoid overcomplication, make surgical changes, surface assumptions, and define verifiable success criteria.
license: MIT
priority: highest
load_order: 1
---

# Karpathy Guidelines (MANDATORY — READ FIRST)

Behavioral guidelines to reduce common LLM coding mistakes, derived from Andrej Karpathy's observations on LLM coding pitfalls. **This skill MUST be consulted before any non-trivial coding task.**

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks (typo fixes, obvious one-liners), use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
'@
}

function Get-ForgeProjectScanReport {
    # Scan a project root for existing agent-config artifacts so the generated
    # AGENTS.md can reference them. Returns a PSCustomObject with arrays of
    # discovered paths (relative to root).
    #
    # Priority order of source-of-truth references in the output:
    #   1. .gsd/   (GSD workspace: knowledge base, milestones, STATE/DECISIONS/...)
    #   2. .claude/ (memory, rules, skills, commands)
    #   3. .cursor/rules/*.mdc
    #   4. .agents/ (oh-my-agent SSOT: skills, workflows, rules)
    #   5. AGENTS.md / CLAUDE.md at root (existing content preserved)
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $report = [pscustomobject]@{
        Root             = $Root
        # ---- GSD ----
        GsdRootDocs      = @()   # .gsd/*.md at root (PROJECT, STATE, DECISIONS, KNOWLEDGE, CODEBASE, REQUIREMENTS)
        GsdKnowledge     = @()   # .gsd/knowledge/*.md (the real "rules/lessons" dir in GSD)
        GsdMilestones    = @()   # .gsd/milestones/M*/  (dir names only)
        GsdSkills        = @()   # .gsd/skills/<name>/SKILL.md   (rare; kept for compat)
        GsdRules         = @()   # .gsd/rules/*.md              (rare; kept for compat)
        GsdMemory        = @()   # .gsd/memory/*.md or .gsd/MEMORY.md (rare; kept for compat)
        # ---- Claude Code ----
        ClaudeSkills     = @()   # .claude/skills/<name>/ SKILL.md or *.md
        ClaudeMemory     = @()   # .claude/memory/*.md
        ClaudeRules      = @()   # .claude/rules/**/*.md (recursive -- has core/, tech-stack/, ...)
        ClaudeCommands   = @()   # .claude/commands/*.md
        ClaudeMd         = $null # .claude/CLAUDE.md or CLAUDE.md at root
        # ---- Cursor ----
        CursorRules      = @()   # .cursor/rules/*.mdc  (recursive)
        # ---- Oh-my-agent ----
        AgentsDir        = $null # .agents/ dir marker
        AgentsSkills     = @()   # .agents/skills/**/*.md
        AgentsWorkflows  = @()   # .agents/workflows/*.md
        AgentsRules      = @()   # .agents/rules/*.md
        # ---- root ----
        RootAgentsMd     = $null # AGENTS.md at root
    }

    function _RelPath($full) {
        return $full.Substring($Root.Length).TrimStart('\','/')
    }

    # ---- .gsd/ (priority 1) ----
    $gsdDir = Join-Path $Root '.gsd'
    if (Test-Path $gsdDir) {
        # Root-level .gsd/*.md (PROJECT.md, STATE.md, DECISIONS.md, KNOWLEDGE.md,
        # CODEBASE.md, REQUIREMENTS.md, and any others the user added)
        $report.GsdRootDocs = @(Get-ChildItem $gsdDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
            ForEach-Object { _RelPath $_.FullName })

        # The real "knowledge/rules" living doc dir
        $gsdKnowledgeDir = Join-Path $gsdDir 'knowledge'
        if (Test-Path $gsdKnowledgeDir) {
            $report.GsdKnowledge = @(Get-ChildItem $gsdKnowledgeDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }

        # Milestones: list dir names only (M001, M002, ...)
        $gsdMilestonesDir = Join-Path $gsdDir 'milestones'
        if (Test-Path $gsdMilestonesDir) {
            $report.GsdMilestones = @(Get-ChildItem $gsdMilestonesDir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }

        # Compat: scan legacy skills/rules/memory dirs if they exist
        $gsdSkillsDir = Join-Path $gsdDir 'skills'
        if (Test-Path $gsdSkillsDir) {
            $report.GsdSkills = @(Get-ChildItem $gsdSkillsDir -Recurse -Filter 'SKILL.md' -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
        $gsdRulesDir = Join-Path $gsdDir 'rules'
        if (Test-Path $gsdRulesDir) {
            $report.GsdRules = @(Get-ChildItem $gsdRulesDir -Filter '*.md' -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
        $gsdMemoryDir = Join-Path $gsdDir 'memory'
        if (Test-Path $gsdMemoryDir) {
            $report.GsdMemory = @(Get-ChildItem $gsdMemoryDir -Filter '*.md' -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
        $gsdMemoryFile = Join-Path $gsdDir 'MEMORY.md'
        if (Test-Path $gsdMemoryFile) {
            $report.GsdMemory += '.gsd\MEMORY.md'
        }
    }

    # ---- .claude/ (priority 2) ----
    $claudeDir = Join-Path $Root '.claude'
    if (Test-Path $claudeDir) {
        # Skills: both `skills/<name>/SKILL.md` and `skills/<name>/*.md` forms
        $claudeSkillsDir = Join-Path $claudeDir 'skills'
        if (Test-Path $claudeSkillsDir) {
            $skillMds = @(Get-ChildItem $claudeSkillsDir -Recurse -Filter 'SKILL.md' -File -ErrorAction SilentlyContinue)
            if ($skillMds.Count -gt 0) {
                $report.ClaudeSkills = @($skillMds | ForEach-Object { _RelPath $_.FullName })
            } else {
                # Fallback: each subdir is a skill, use its top-level .md
                $report.ClaudeSkills = @(Get-ChildItem $claudeSkillsDir -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { _RelPath $_.FullName })
            }
        }

        # Memory
        $claudeMemoryDir = Join-Path $claudeDir 'memory'
        if (Test-Path $claudeMemoryDir) {
            $report.ClaudeMemory = @(Get-ChildItem $claudeMemoryDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }

        # Rules (recursive -- .claude/rules/core/, tech-stack/ etc.)
        $claudeRulesDir = Join-Path $claudeDir 'rules'
        if (Test-Path $claudeRulesDir) {
            $report.ClaudeRules = @(Get-ChildItem $claudeRulesDir -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }

        # Commands (slash commands)
        $claudeCommandsDir = Join-Path $claudeDir 'commands'
        if (Test-Path $claudeCommandsDir) {
            $report.ClaudeCommands = @(Get-ChildItem $claudeCommandsDir -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
    }

    # CLAUDE.md location (check root first, then nested)
    $claudeMdRoot   = Join-Path $Root 'CLAUDE.md'
    $claudeMdNested = Join-Path $Root '.claude\CLAUDE.md'
    if (Test-Path $claudeMdRoot)        { $report.ClaudeMd = 'CLAUDE.md' }
    elseif (Test-Path $claudeMdNested)  { $report.ClaudeMd = '.claude\CLAUDE.md' }

    # ---- .cursor/rules/ (priority 3) ----
    $cursorRulesDir = Join-Path $Root '.cursor\rules'
    if (Test-Path $cursorRulesDir) {
        $report.CursorRules = @(Get-ChildItem $cursorRulesDir -Recurse -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
            ForEach-Object { _RelPath $_.FullName })
    }

    # ---- .agents/ (priority 4) ----
    $agentsDir = Join-Path $Root '.agents'
    if (Test-Path $agentsDir) {
        $report.AgentsDir = '.agents'
        $agentsSkillsDir = Join-Path $agentsDir 'skills'
        if (Test-Path $agentsSkillsDir) {
            $report.AgentsSkills = @(Get-ChildItem $agentsSkillsDir -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
        $agentsWfDir = Join-Path $agentsDir 'workflows'
        if (Test-Path $agentsWfDir) {
            $report.AgentsWorkflows = @(Get-ChildItem $agentsWfDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
        $agentsRulesDir = Join-Path $agentsDir 'rules'
        if (Test-Path $agentsRulesDir) {
            $report.AgentsRules = @(Get-ChildItem $agentsRulesDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                ForEach-Object { _RelPath $_.FullName })
        }
    }

    # ---- root AGENTS.md ----
    $rootAgents = Join-Path $Root 'AGENTS.md'
    if (Test-Path $rootAgents) { $report.RootAgentsMd = 'AGENTS.md' }

    return $report
}

function New-ForgeAgentsMdContent {
    # Build the rewritten AGENTS.md body from a scan report.
    # Contains: mandatory-skill banner, references map, scan summary.
    param(
        [Parameter(Mandatory)]$Report,
        [string]$ExistingProjectSection = ''
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# AGENTS.md')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> Project guidelines for ForgeCode / Claude Code / any AGENTS.md-compatible agent.')
    [void]$sb.AppendLine('> Generated by `8sync forge init`. This file is equivalent to CLAUDE.md.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## MANDATORY — read before any task')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('**You MUST load and apply `.forge/skills/karpathy-guidelines/SKILL.md` before starting any non-trivial coding task.**')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('The four principles are non-negotiable:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('1. **Think Before Coding** — state assumptions, surface ambiguity, ask when unclear.')
    [void]$sb.AppendLine('2. **Simplicity First** — minimum code; no speculative abstractions.')
    [void]$sb.AppendLine('3. **Surgical Changes** — every changed line traces to the user request.')
    [void]$sb.AppendLine('4. **Goal-Driven Execution** — define verifiable success criteria; loop until green.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Full text: [`.forge/skills/karpathy-guidelines/SKILL.md`](./.forge/skills/karpathy-guidelines/SKILL.md)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Skill / rule / memory references')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('The agent should auto-discover and consult these when the task matches:')
    [void]$sb.AppendLine('')

    # Forge skills
    [void]$sb.AppendLine('### ForgeCode skills (`.forge/skills/`)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- `.forge/skills/karpathy-guidelines/SKILL.md` — MANDATORY baseline (above)')
    [void]$sb.AppendLine('')

    # ---- GSD (priority 1 -- project source of truth) ----
    $hasGsd = ($Report.GsdRootDocs.Count -gt 0 -or $Report.GsdKnowledge.Count -gt 0 -or
               $Report.GsdMilestones.Count -gt 0 -or $Report.GsdSkills.Count -gt 0 -or
               $Report.GsdRules.Count -gt 0 -or $Report.GsdMemory.Count -gt 0)
    if ($hasGsd) {
        [void]$sb.AppendLine('### GSD workspace (`.gsd/`) — PRIMARY project source of truth')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('> Read these BEFORE touching code. They define the project state, decisions, and lessons.')
        [void]$sb.AppendLine('')
        if ($Report.GsdRootDocs.Count -gt 0) {
            [void]$sb.AppendLine('**Project docs (read first):**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.GsdRootDocs) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.GsdKnowledge.Count -gt 0) {
            [void]$sb.AppendLine('**Knowledge base (`.gsd/knowledge/` — lessons, patterns, gotchas):**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.GsdKnowledge) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.GsdMilestones.Count -gt 0) {
            [void]$sb.AppendLine('**Milestones (`.gsd/milestones/`):**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.GsdMilestones) { [void]$sb.AppendLine(('- `{0}/`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.GsdSkills.Count -gt 0) {
            [void]$sb.AppendLine('**Legacy GSD skills:**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.GsdSkills) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.GsdRules.Count -gt 0) {
            [void]$sb.AppendLine('**Legacy GSD rules:**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.GsdRules) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.GsdMemory.Count -gt 0) {
            [void]$sb.AppendLine('**Legacy GSD memory:**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.GsdMemory) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
    }

    # ---- Claude Code (priority 2) ----
    $hasClaude = ($Report.ClaudeSkills.Count -gt 0 -or $Report.ClaudeMemory.Count -gt 0 -or
                  $Report.ClaudeRules.Count -gt 0 -or $Report.ClaudeCommands.Count -gt 0)
    if ($hasClaude) {
        [void]$sb.AppendLine('### Claude Code workspace (`.claude/`) — compatible, auto-loaded')
        [void]$sb.AppendLine('')
        if ($Report.ClaudeSkills.Count -gt 0) {
            [void]$sb.AppendLine('**Skills:**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.ClaudeSkills) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.ClaudeMemory.Count -gt 0) {
            [void]$sb.AppendLine('**Memory (long-lived context):**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.ClaudeMemory) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.ClaudeRules.Count -gt 0) {
            [void]$sb.AppendLine('**Rules:**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.ClaudeRules) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
        if ($Report.ClaudeCommands.Count -gt 0) {
            [void]$sb.AppendLine('**Slash commands:**')
            [void]$sb.AppendLine('')
            foreach ($p in $Report.ClaudeCommands) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
            [void]$sb.AppendLine('')
        }
    }

    # Cursor
    if ($Report.CursorRules.Count -gt 0) {
        [void]$sb.AppendLine('### Cursor rules (`.cursor/rules/`)')
        [void]$sb.AppendLine('')
        foreach ($p in $Report.CursorRules) { [void]$sb.AppendLine(('- `{0}`' -f $p)) }
        [void]$sb.AppendLine('')
    }

    # .agents/
    if ($Report.AgentsDir) {
        [void]$sb.AppendLine('### Oh-my-agent SSOT (`.agents/`) — do not edit directly')
        [void]$sb.AppendLine('')
        foreach ($p in $Report.AgentsSkills)    { [void]$sb.AppendLine(('- skill:    `{0}`' -f $p)) }
        foreach ($p in $Report.AgentsWorkflows) { [void]$sb.AppendLine(('- workflow: `{0}`' -f $p)) }
        foreach ($p in $Report.AgentsRules)     { [void]$sb.AppendLine(('- rule:     `{0}`' -f $p)) }
        [void]$sb.AppendLine('')
    }

    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Project-specific guidelines')
    [void]$sb.AppendLine('')
    if ($ExistingProjectSection) {
        [void]$sb.AppendLine('> Preserved from previous AGENTS.md / CLAUDE.md:')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($ExistingProjectSection.TrimEnd())
        [void]$sb.AppendLine('')
    } else {
        [void]$sb.AppendLine('<!-- Add project-specific rules here. Anything below survives future `8sync forge init` runs -->')
        [void]$sb.AppendLine('')
    }

    return $sb.ToString()
}

function Invoke-ForgeInit {
    # Scan project root (.gsd/, .cursor/, .claude/, .agents/) and generate a
    # clean `.forge/` tree + AGENTS.md (+ CLAUDE.md alias) that references them.
    # Always writes the latest Karpathy guidelines skill as a mandatory load.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    # Guard: ValueFromRemainingArguments yields $null (not @()) when zero args
    # are passed, which breaks [Array]::IndexOf($Rest, ...) with ArgumentNullException.
    if ($null -eq $Rest) { $Rest = @() }

    $dryRun = $Rest -contains '--dry-run'
    $force  = $Rest -contains '--force'

    $pathIdx = [Array]::IndexOf($Rest, '--path')
    $root = if ($pathIdx -ge 0 -and $pathIdx + 1 -lt $Rest.Count) {
        (Resolve-Path $Rest[$pathIdx + 1] -ErrorAction SilentlyContinue).Path
    } else {
        (Get-Location).Path
    }

    if (-not $root -or -not (Test-Path $root)) {
        Write-Host ''
        Write-Host ('  [error] root not found: {0}' -f $root) -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  FORGE -- init project config (AGENTS.md + .forge/ skills)' -ForegroundColor Cyan
    Write-Host ('  root: {0}' -f $root) -ForegroundColor DarkGray
    if ($dryRun) { Write-Host '  mode: DRY-RUN (no files written)' -ForegroundColor Yellow }
    if ($force)  { Write-Host '  mode: --force (skip backups)' -ForegroundColor Yellow }
    Write-Host ''

    # ---- scan ----
    Write-Host '  [1/5] Scanning project...' -ForegroundColor Cyan
    $report = Get-ForgeProjectScanReport -Root $root

    function _RowCount($label, $count, $color = 'White') {
        $mark = if ($count -gt 0) { '[found]' } else { '[    ]' }
        Write-Host ('    {0} {1,-24} {2}' -f $mark, $label, $count) -ForegroundColor $color
    }
    _RowCount '.forge/skills (Karpathy)' 1 'Green'
    # GSD -- priority 1, show full breakdown
    _RowCount '.gsd/*.md (root docs)'    $report.GsdRootDocs.Count
    _RowCount '.gsd/knowledge/*.md'      $report.GsdKnowledge.Count
    _RowCount '.gsd/milestones/M*/'      $report.GsdMilestones.Count
    _RowCount '.gsd/skills'              $report.GsdSkills.Count
    _RowCount '.gsd/rules'               $report.GsdRules.Count
    _RowCount '.gsd/memory'              $report.GsdMemory.Count
    # Claude -- priority 2
    _RowCount '.claude/skills'           $report.ClaudeSkills.Count
    _RowCount '.claude/memory/*.md'      $report.ClaudeMemory.Count
    _RowCount '.claude/rules/**/*.md'    $report.ClaudeRules.Count
    _RowCount '.claude/commands/*.md'    $report.ClaudeCommands.Count
    # Cursor / agents
    _RowCount '.cursor/rules/*.mdc'      $report.CursorRules.Count
    _RowCount '.agents/skills'           $report.AgentsSkills.Count
    _RowCount '.agents/workflows'        $report.AgentsWorkflows.Count
    _RowCount '.agents/rules'            $report.AgentsRules.Count
    $hasRootAgents = if ($report.RootAgentsMd) { 1 } else { 0 }
    $hasClaudeMd   = if ($report.ClaudeMd)     { 1 } else { 0 }
    _RowCount 'AGENTS.md (root)'         $hasRootAgents
    _RowCount 'CLAUDE.md (root/nested)'  $hasClaudeMd
    Write-Host ''

    # ---- preserve existing project section ----
    $existingSection = ''
    $existingPaths = @()
    if ($report.RootAgentsMd) { $existingPaths += (Join-Path $root $report.RootAgentsMd) }
    if ($report.ClaudeMd -and $report.ClaudeMd -ne $report.RootAgentsMd) {
        $existingPaths += (Join-Path $root $report.ClaudeMd)
    }
    foreach ($p in $existingPaths) {
        if (Test-Path $p) {
            try {
                $txt = Get-Content $p -Raw -Encoding UTF8
                # Keep whole body so user doesn't lose anything — just append.
                if ($existingSection) { $existingSection += "`n`n---`n`n" }
                $existingSection += ("_from `{0}`_`n`n" -f (Split-Path $p -Leaf)) + $txt.TrimEnd()
            } catch {}
        }
    }

    # ---- plan paths ----
    $forgeDir   = Join-Path $root '.forge'
    $skillsDir  = Join-Path $forgeDir 'skills\karpathy-guidelines'
    $skillFile  = Join-Path $skillsDir 'SKILL.md'
    $agentsFile = Join-Path $root 'AGENTS.md'
    $claudeFile = Join-Path $root 'CLAUDE.md'
    $ts         = (Get-Date -Format 'yyyyMMdd-HHmmss')

    $agentsBody = New-ForgeAgentsMdContent -Report $report -ExistingProjectSection $existingSection
    $skillBody  = Get-KarpathySkillContent

    # ---- write (or preview) ----
    Write-Host '  [2/5] Writing .forge/skills/karpathy-guidelines/SKILL.md' -ForegroundColor Cyan
    if ($dryRun) {
        Write-Host ('    [dry-run] would write {0} bytes to {1}' -f $skillBody.Length, $skillFile) -ForegroundColor DarkGray
    } else {
        if (-not (Test-Path $skillsDir)) { New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null }
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($skillFile, $skillBody, $utf8)
        Write-Host '    [ok]' -ForegroundColor Green
    }

    Write-Host '  [3/5] Writing AGENTS.md' -ForegroundColor Cyan
    if ($dryRun) {
        Write-Host ('    [dry-run] would write {0} bytes to {1}' -f $agentsBody.Length, $agentsFile) -ForegroundColor DarkGray
    } else {
        if ((Test-Path $agentsFile) -and -not $force) {
            $bak = "$agentsFile.bak-8sync-$ts"
            Copy-Item $agentsFile $bak -Force
            Write-Host ('    [ok] backup: {0}' -f (Split-Path $bak -Leaf)) -ForegroundColor DarkGray
        }
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($agentsFile, $agentsBody, $utf8)
        Write-Host '    [ok]' -ForegroundColor Green
    }

    Write-Host '  [4/5] Writing CLAUDE.md (alias -> AGENTS.md)' -ForegroundColor Cyan
    $claudeBody = @"
# CLAUDE.md

> This project uses **AGENTS.md** as the single source of truth.
> Claude Code, ForgeCode, and any AGENTS.md-compatible agent load the same file.
>
> **Read: [AGENTS.md](./AGENTS.md)**

"@
    if ($dryRun) {
        Write-Host ('    [dry-run] would write {0} bytes to {1}' -f $claudeBody.Length, $claudeFile) -ForegroundColor DarkGray
    } else {
        if ((Test-Path $claudeFile) -and -not $force) {
            $bak = "$claudeFile.bak-8sync-$ts"
            Copy-Item $claudeFile $bak -Force
            Write-Host ('    [ok] backup: {0}' -f (Split-Path $bak -Leaf)) -ForegroundColor DarkGray
        }
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($claudeFile, $claudeBody, $utf8)
        Write-Host '    [ok]' -ForegroundColor Green
    }

    Write-Host '  [5/5] Done' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Files:' -ForegroundColor DarkGray
    Write-Host ('    {0}' -f $skillFile)  -ForegroundColor White
    Write-Host ('    {0}' -f $agentsFile) -ForegroundColor White
    Write-Host ('    {0}' -f $claudeFile) -ForegroundColor White
    Write-Host ''
    Write-Host '  Next:' -ForegroundColor Cyan
    Write-Host '    forge              # start a session; AGENTS.md + karpathy-guidelines auto-load' -ForegroundColor DarkGray
    Write-Host '    :skill             # list skills forge picked up' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-ForgeBuiltInSkills {
    # Registry of built-in skills that `8sync forge add-skill <name>` can install.
    # To add a new skill: add an entry here and a content-getter function
    # (Get-*SkillContent) that returns the full SKILL.md body.
    [OutputType([hashtable])]
    param()

    return @{
        'karpathy' = [ordered]@{
            dir         = 'karpathy-guidelines'
            description = 'Karpathy 4 principles: Think, Simplify, Surgical, Goal-Driven. Loaded first (priority: highest).'
            getter      = 'Get-KarpathySkillContent'
        }
        # Future built-ins go here.
    }
}

function Invoke-ForgeAddSkill {
    # Install a built-in skill into one of the three Forge skill scopes:
    #   --project  (default) -> <cwd>/.forge/skills/<dir>/SKILL.md
    #   --agents             -> $HOME/.agents/skills/<dir>/SKILL.md
    #   --global             -> $HOME/forge/skills/<dir>/SKILL.md
    # Usage:
    #   8sync forge add-skill                      # list built-ins
    #   8sync forge add-skill karpathy             # project scope
    #   8sync forge add-skill karpathy --global    # user-wide (all projects)
    #   8sync forge add-skill karpathy --agents    # shared across agent tools
    #   8sync forge add-skill karpathy --dry-run   # preview
    #   8sync forge add-skill karpathy --force     # overwrite, no .bak
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    # Guard against $null (zero-arg case) -- see Invoke-ForgeInit.
    if ($null -eq $Rest) { $Rest = @() }

    $dryRun   = $Rest -contains '--dry-run'
    $force    = $Rest -contains '--force'
    $isGlobal = $Rest -contains '--global'
    $isAgents = $Rest -contains '--agents'
    $isProj   = $Rest -contains '--project'

    # First non-flag arg is the skill name
    $skillName = $null
    foreach ($r in $Rest) {
        if ($r -notlike '--*') { $skillName = $r.ToLowerInvariant(); break }
    }

    $skills = Get-ForgeBuiltInSkills

    Write-Host ''
    Write-Host '  FORGE -- add built-in skill' -ForegroundColor Cyan
    Write-Host ''

    # No skill name -> list available
    if (-not $skillName) {
        Write-Host '  Available built-in skills:' -ForegroundColor DarkGray
        Write-Host ''
        foreach ($k in ($skills.Keys | Sort-Object)) {
            $desc = $skills[$k].description
            Write-Host ('    {0,-12} {1}' -f $k, $desc) -ForegroundColor White
        }
        Write-Host ''
        Write-Host '  Usage:' -ForegroundColor Cyan
        Write-Host '    8sync forge add-skill <name>              # project scope (.forge/skills/)' -ForegroundColor DarkGray
        Write-Host '    8sync forge add-skill <name> --global     # user-wide (~/forge/skills/)' -ForegroundColor DarkGray
        Write-Host '    8sync forge add-skill <name> --agents     # shared (~/.agents/skills/)' -ForegroundColor DarkGray
        Write-Host '    8sync forge add-skill <name> --dry-run    # preview only' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if (-not $skills.ContainsKey($skillName)) {
        Write-Host ("  [error] unknown skill '{0}'. Run without args to list." -f $skillName) -ForegroundColor Red
        Write-Host ''
        return
    }

    # Resolve scope -> base dir
    # Precedence if multiple flags set: --global > --agents > --project (default)
    $scope = 'project'
    $baseDir = $null
    if ($isGlobal) {
        $scope = 'global'
        $baseDir = Join-Path $HOME 'forge\skills'
    } elseif ($isAgents) {
        $scope = 'agents'
        $baseDir = Join-Path $HOME '.agents\skills'
    } else {
        $scope = 'project'
        $baseDir = Join-Path (Get-Location).Path '.forge\skills'
    }

    $skillMeta  = $skills[$skillName]
    $skillDir   = Join-Path $baseDir $skillMeta.dir
    $skillFile  = Join-Path $skillDir 'SKILL.md'
    $getterName = $skillMeta.getter

    # Call the content getter
    $content = & (Get-Command $getterName -CommandType Function)

    Write-Host ('  skill:  {0}' -f $skillName)   -ForegroundColor White
    Write-Host ('  scope:  {0}' -f $scope)       -ForegroundColor White
    Write-Host ('  target: {0}' -f $skillFile)   -ForegroundColor DarkGray
    if ($dryRun) { Write-Host '  mode:   DRY-RUN (no files written)' -ForegroundColor Yellow }
    if ($force)  { Write-Host '  mode:   --force (skip backups)'    -ForegroundColor Yellow }
    Write-Host ''

    if ($dryRun) {
        Write-Host ('  [dry-run] would write {0} bytes to target' -f $content.Length) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Ensure dir exists
    if (-not (Test-Path $skillDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
        } catch {
            Write-Host ('  [error] could not create {0}: {1}' -f $skillDir, $_.Exception.Message) -ForegroundColor Red
            Write-Host ''
            return
        }
    }

    # Backup existing
    if ((Test-Path $skillFile) -and -not $force) {
        $ts = (Get-Date -Format 'yyyyMMdd-HHmmss')
        $bak = "$skillFile.bak-8sync-$ts"
        try {
            Copy-Item $skillFile $bak -Force
            Write-Host ('  [ok] backup: {0}' -f (Split-Path $bak -Leaf)) -ForegroundColor DarkGray
        } catch {}
    }

    # Write
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($skillFile, $content, $utf8)
        Write-Host '  [ok] written' -ForegroundColor Green
    } catch {
        Write-Host ('  [error] could not write {0}: {1}' -f $skillFile, $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  Forge auto-loads this skill on the next session start.' -ForegroundColor DarkGray
    if ($scope -eq 'global') {
        Write-Host '  Scope: global -- applies to every project on this machine.' -ForegroundColor DarkGray
    } elseif ($scope -eq 'agents') {
        Write-Host '  Scope: agents -- shared with any AGENTS.md-compatible tool.' -ForegroundColor DarkGray
    } else {
        Write-Host '  Scope: project -- checked into version control with your repo.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Install-OhMyZsh {
    param(
        [Parameter(Mandatory)][string]$BashPath,
        [switch]$DryRun,
        [switch]$Force
    )

    # Install oh-my-zsh at WINDOWS $HOME (C:\Users\<user>\.oh-my-zsh) so that both
    # msys2 zsh sessions AND Windows binaries (like forge.exe) can find it.
    # Forge runs as a native Windows process and inspects Windows-side $HOME.
    $winHome      = $env:USERPROFILE
    $winOmzDir    = Join-Path $winHome '.oh-my-zsh'
    $msysHome     = ConvertTo-MsysPath $winHome               # e.g. /c/Users/Admin
    $msysOmzDir   = "$msysHome/.oh-my-zsh"

    if ((Test-Path $winOmzDir) -and -not $Force) {
        Write-Host ("  [ok] oh-my-zsh already installed at {0}" -f $winOmzDir) -ForegroundColor Green
        Write-Host '       Use --force to reinstall.' -ForegroundColor DarkGray
        return $true
    }

    if ($DryRun) {
        Write-Host '  [dry-run] would run (inside msys2 bash, with HOME=Windows profile):' -ForegroundColor DarkYellow
        Write-Host ('    HOME="{0}" RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://install.ohmyz.sh/)"' -f $msysHome) -ForegroundColor White
        Write-Host ("    -> installs to: {0}" -f $winOmzDir) -ForegroundColor DarkGray
        return $false
    }

    if ((Test-Path $winOmzDir) -and $Force) {
        Write-Host ("  [info] Removing existing {0} (--force)" -f $winOmzDir) -ForegroundColor DarkYellow
        try { Remove-Item $winOmzDir -Recurse -Force -ErrorAction Stop } catch {
            Write-Host ("  [warn] could not remove: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    Write-Host '  Running: oh-my-zsh installer' -ForegroundColor Yellow
    Write-Host ("    HOME={0}  (so forge.exe finds it at {1})" -f $msysHome, $winOmzDir) -ForegroundColor DarkGray
    try {
        # RUNZSH=no       -> do not exec into zsh after install (we're in pwsh)
        # KEEP_ZSHRC=yes  -> do not overwrite a user-managed ~/.zshrc
        # CHSH=no         -> do not try chsh (not meaningful on Windows)
        # HOME=<winpath>  -> place the install where Forge native binary looks
        $cmd = 'HOME="' + $msysHome + '" RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://install.ohmyz.sh/)"'
        & $BashPath -lc $cmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  [error] oh-my-zsh installer exited non-zero.' -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host ("  [error] {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }

    if (Test-Path $winOmzDir) {
        Write-Host ("  [ok] oh-my-zsh installed at {0}" -f $winOmzDir) -ForegroundColor Green
    } else {
        Write-Host '  [warn] installer finished but install dir not detected.' -ForegroundColor DarkYellow
    }

    # Also mirror via junction into msys2 /home/<user>/.oh-my-zsh so bare
    # `zsh` sessions launched from msys2 shell (with HOME=/home/Admin) see it too.
    try {
        $msysRoot     = Split-Path $BashPath -Parent | Split-Path -Parent | Split-Path -Parent  # ...\msys2\current
        $msysUserHome = Join-Path $msysRoot ('home\' + $env:USERNAME)
        $msysUserOmz  = Join-Path $msysUserHome '.oh-my-zsh'
        if ((Test-Path $msysUserHome) -and -not (Test-Path $msysUserOmz) -and (Test-Path $winOmzDir)) {
            & cmd.exe /c ('mklink /J "' + $msysUserOmz + '" "' + $winOmzDir + '"') 2>&1 | Out-Null
            if (Test-Path $msysUserOmz) {
                Write-Host ("  [ok] junction: {0} -> {1}" -f $msysUserOmz, $winOmzDir) -ForegroundColor DarkGray
            }
        }
    } catch {}

    return $true
}

function Add-MsysBinToPath {
    # Expose msys2's usr\bin to PATH so `zsh.exe` is discoverable by Forge etc.
    # APPEND (not prepend) so Windows-native tools (find/sort/etc.) keep
    # precedence -- msys2 only fills gaps for tools that don't exist on Windows.
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$BashPath)

    $binDir = Split-Path $BashPath -Parent   # ...\msys2\current\usr\bin
    if (-not (Test-Path $binDir)) { return $false }

    $changed = $false

    # Current process PATH (so `forge zsh setup` finds zsh in THIS shell)
    $processPath = $env:PATH
    if ($processPath -notmatch [regex]::Escape($binDir)) {
        $env:PATH = $processPath.TrimEnd(';') + ';' + $binDir
        $changed = $true
    }

    # User PATH (so future shells + freshly-launched `forge` processes find zsh)
    try {
        $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($userPath -notmatch [regex]::Escape($binDir)) {
            $newUserPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $binDir } else { $binDir }
            [System.Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
            Write-Host ("  [ok] Appended to Windows User PATH: {0}" -f $binDir) -ForegroundColor DarkGray
            $changed = $true
        }
    } catch {
        Write-Host ("  [warn] could not persist User PATH: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }

    if (-not $changed) {
        Write-Host ("  [ok] msys2 bin already in PATH: {0}" -f $binDir) -ForegroundColor Green
    }
    return $true
}

function Get-MsysZshPath {
    # Returns path to msys2 zsh.exe, or $null if not installed.
    $bash = Get-MsysBashPath
    if (-not $bash) { return $null }
    $zshExe = $bash -replace 'bash\.exe$','zsh.exe'
    if (Test-Path $zshExe) { return [string]$zshExe }
    return $null
}

function Invoke-ForgeEnterZsh {
    # Launch msys2 zsh as an interactive login shell from PowerShell.
    # Windows has no `exec` -- this function is the "enter zsh" equivalent.
    # When the user types `exit` inside zsh they return to the calling pwsh.
    param([switch]$NoLogin)

    $zshExe = Get-MsysZshPath
    if (-not $zshExe) {
        Write-Host ''
        Write-Host '  [error] zsh not installed. Run: 8sync forge zsh' -ForegroundColor Red
        Write-Host ''
        return
    }

    # Make sure Windows HOME is visible to zsh (so ~/.zshrc resolves to the
    # Windows profile where oh-my-zsh + forge-initialize block live).
    Ensure-ForgeHomeEnv
    Ensure-ForgeConsoleUtf8
    Ensure-EditorEnv | Out-Null
    Ensure-ZshInPath

    # Clear a few env vars that can confuse msys2's tty detection
    # (only affects the zsh subprocess we spawn, not the parent pwsh).
    #
    # FORGE_LIGHT_ZSH=1 tells the v2 managed block in ~/.zshrc to use a
    # lightweight profile (no robbyrussell git calls, capped syntax highlight,
    # capped autosuggestions). This keeps Forge AI chat responsive from the
    # 2nd message onward when the scrollback buffer contains long AI output.
    $prev = @{
        MSYSTEM         = $env:MSYSTEM
        CHERE_INVOKING  = $env:CHERE_INVOKING
        FORGE_LIGHT_ZSH = $env:FORGE_LIGHT_ZSH
    }
    $env:MSYSTEM = 'MSYS'              # correct subsystem for generic usr/bin
    $env:CHERE_INVOKING = '1'          # preserve current working directory
    if (-not $env:FORGE_LIGHT_ZSH) {
        $env:FORGE_LIGHT_ZSH = '1'
    }

    Write-Host ''
    Write-Host ('  Entering zsh -- {0}' -f $zshExe) -ForegroundColor Cyan
    Write-Host '  Type `exit` to return to PowerShell.' -ForegroundColor DarkGray
    Write-Host ''

    try {
        if ($NoLogin) {
            & $zshExe --interactive
        } else {
            # --login: source /etc/zprofile + ~/.zprofile (mirrors `exec zsh -l`)
            # --interactive: enable prompt, history, keybindings
            & $zshExe --login --interactive
        }
    } finally {
        # Restore parent env
        $env:MSYSTEM = $prev.MSYSTEM
        $env:CHERE_INVOKING = $prev.CHERE_INVOKING
        $env:FORGE_LIGHT_ZSH = $prev.FORGE_LIGHT_ZSH
    }
}

function Show-ForgeZshUsage {
    Write-Host ''
    Write-HintSection 'FORGE ZSH -- how to use zsh on Windows after `forge zsh setup`'
    Write-Host ''
    Write-Host '  There is no `exec zsh` on Windows -- you SPAWN a zsh subprocess.' -ForegroundColor DarkGray
    Write-Host '  When you `exit` the zsh session, you return to pwsh.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Three ways to enter zsh:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  1) Via 8sync (recommended -- ensures HOME/PATH/UTF-8 set up right):' -ForegroundColor White
    Write-Host '       8sync forge enter' -ForegroundColor Green
    Write-Host ''
    Write-Host '  2) Direct (zsh is in PATH -- just type it):' -ForegroundColor White
    Write-Host '       zsh -l -i        # -l = login, -i = interactive' -ForegroundColor Green
    Write-Host ''
    Write-Host '  3) One-shot command from pwsh (no interactive session):' -ForegroundColor White
    Write-Host '       zsh -c "<command>"' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Inside zsh you get:' -ForegroundColor Cyan
    Write-Host '    - Forge prompt + right-side AI context theme' -ForegroundColor DarkGray
    Write-Host '    - Forge `:` keybinding to invoke the AI' -ForegroundColor DarkGray
    Write-Host '    - zsh-autosuggestions (grey inline hint)' -ForegroundColor DarkGray
    Write-Host '    - zsh-syntax-highlighting' -ForegroundColor DarkGray
    Write-Host '    - Oh My Zsh: git plugin, robbyrussell theme (customize in ~/.zshrc)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  To make zsh your *default* shell in WezTerm tabs (optional):' -ForegroundColor Cyan
    Write-Host '    Edit wezterm.lua and set:' -ForegroundColor DarkGray
    $zshExePath = Get-MsysZshPath
    if (-not $zshExePath) { $zshExePath = 'C:\Users\Admin\scoop\apps\msys2\current\usr\bin\zsh.exe' }
    $zshLuaPath = $zshExePath -replace '\\','\\'
    Write-Host ("      config.default_prog = {{ '{0}', '--login', '-i' }}" -f $zshLuaPath) -ForegroundColor White
    Write-Host '    (You will lose the pwsh 8sync bootstrap -- only do this if you want zsh as your primary shell.)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Tip: keep pwsh as default shell and use `8sync forge enter` on-demand.' -ForegroundColor DarkYellow
    Write-Host '       This way you keep 8sync commands AND can pop into zsh whenever needed.' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ForgeZshInstall {
    param(
        [switch]$DryRun,
        [switch]$Force,
        [switch]$SkipOmz
    )

    Write-Host ''
    Write-Host '  FORGE -- install zsh on Windows (via MSYS2)' -ForegroundColor Cyan
    Write-Host '  Reference: https://ohmyz.sh/#install' -ForegroundColor DarkGray
    Write-Host ''

    # Step 1: MSYS2
    Write-Host '  [1/4] MSYS2 (Windows-native POSIX env)' -ForegroundColor Cyan
    $bashRaw = Install-MSYS2ViaScoop -DryRun:$DryRun
    # Defensive: if a future edit accidentally pollutes the pipeline, pick the .exe entry.
    $bash = if ($bashRaw -is [array]) {
        @($bashRaw | Where-Object { $_ -is [string] -and $_ -match '\.exe$' } | Select-Object -First 1)[0]
    } else {
        [string]$bashRaw
    }
    if (-not $bash -and -not $DryRun) {
        Write-Host ''
        Write-Host '  [fatal] cannot proceed without msys2.' -ForegroundColor Red
        Write-Host ''
        return
    }

    # Step 2: zsh package
    Write-Host ''
    Write-Host '  [2/4] zsh package (pacman)' -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host '  [dry-run] would run: pacman -S --noconfirm --needed zsh git curl' -ForegroundColor DarkYellow
    } else {
        $zshOk = Install-ZshPackage -BashPath $bash
        if (-not $zshOk) {
            Write-Host ''
            Write-Host '  [fatal] zsh install failed.' -ForegroundColor Red
            Write-Host ''
            return
        }
    }

    # Step 3: PATH wiring -- make `zsh.exe` findable by forge/other callers
    Write-Host ''
    Write-Host '  [3/4] PATH wiring (expose zsh.exe to forge + Windows)' -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host '  [dry-run] would append msys2\usr\bin to User PATH + current process PATH' -ForegroundColor DarkYellow
    } elseif ($bash) {
        Add-MsysBinToPath -BashPath $bash | Out-Null
    }

    # Step 4: oh-my-zsh
    Write-Host ''
    Write-Host '  [4/4] oh-my-zsh framework' -ForegroundColor Cyan
    if ($SkipOmz) {
        Write-Host '  [skip] --skip-omz specified; oh-my-zsh not installed.' -ForegroundColor DarkGray
    } elseif ($DryRun) {
        Write-Host '  [dry-run] would run oh-my-zsh installer via msys2 bash' -ForegroundColor DarkYellow
        Write-Host '  [dry-run] would ensure .zshrc sources oh-my-zsh (prepend managed block)' -ForegroundColor DarkYellow
    } else {
        Install-OhMyZsh -BashPath $bash -Force:$Force | Out-Null
        # Critical: ensure .zshrc actually sources oh-my-zsh. Without this, omz is
        # installed on disk but zsh sessions never load it, and `forge zsh doctor`
        # reports "Oh My Zsh not found" despite the directory existing.
        Ensure-ZshrcSourcesOmz | Out-Null
        # Also resolve forge doctor's "No editor configured" warning if possible.
        $ed = Ensure-EditorEnv
        if ($ed) {
            Write-Host ("  [ok] EDITOR/FORGE_EDITOR -> {0}" -f $ed) -ForegroundColor Green
        }
    }

    Write-Host ''
    Write-Host '  Done.' -ForegroundColor Green
    Write-Host '  Next steps (on Windows there is no `exec zsh` -- you spawn a subshell):' -ForegroundColor Cyan
    Write-Host '    forge zsh setup       # interactive -- answer Y when asked about icons' -ForegroundColor White
    Write-Host '    8sync forge enter     # jump into zsh now  (exit to return to pwsh)' -ForegroundColor White
    Write-Host '    8sync forge zsh-usage # full guide for daily use' -ForegroundColor White
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Forge -> GSD OAuth sync
#  Forge's ~/.forge/.credentials.json holds a working Anthropic OAuth token.
#  We expose it to GSD via:
#    1. $env:FORGE_ANTHROPIC_OAUTH_TOKEN (refreshed every shell startup)
#    2. ~/.gsd/agent/models.json custom provider "anthropic-forge" with
#         api:           anthropic-messages
#         authHeader:    true   -> Authorization: Bearer <token>
#         apiKey:        FORGE_ANTHROPIC_OAUTH_TOKEN  (env var reference)
#         headers:       anthropic-beta + anthropic-version (match Forge/CC)
#  Ref: https://github.com/gsd-build/gsd-2/blob/main/docs/user-docs/custom-models.md
# ---------------------------------------------------------------------------

function Get-ForgeCredentialsPath {
    $p = Join-Path $HOME '.forge\.credentials.json'
    if (Test-Path $p) { return $p }
    return $null
}

function Read-ForgeAnthropicCreds {
    $path = Get-ForgeCredentialsPath
    if (-not $path) { return $null }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host ("  [warn] could not parse {0}: {1}" -f $path, $_.Exception.Message) -ForegroundColor DarkYellow
        return $null
    }

    # Forge stores credentials as an array keyed by id. "claude_code" = Anthropic OAuth.
    $entry = $parsed | Where-Object { $_.id -eq 'claude_code' } | Select-Object -First 1
    if (-not $entry) { return $null }

    $oauth = $entry.auth_details.o_auth
    if (-not $oauth -or -not $oauth.tokens) { return $null }

    $expiresAt = $null
    if ($oauth.tokens.expires_at) {
        try { $expiresAt = [datetime]::Parse($oauth.tokens.expires_at).ToUniversalTime() } catch {}
    }

    return [pscustomobject]@{
        AccessToken  = $oauth.tokens.access_token
        RefreshToken = $oauth.tokens.refresh_token
        ExpiresAt    = $expiresAt
        ClientId     = $oauth.config.client_id
        Scopes       = @($oauth.config.scopes)
        SourcePath   = $path
    }
}

function Sync-ForgeAnthropicEnv {
    # Silently propagate Forge's current Anthropic OAuth token to $env for GSD.
    # Safe to call on every shell startup.
    param([switch]$Quiet)

    $creds = Read-ForgeAnthropicCreds
    if (-not $creds -or -not $creds.AccessToken) {
        if (-not $Quiet) {
            Write-Host '  [info] no Forge Anthropic OAuth token found; run: forge provider login' -ForegroundColor DarkGray
        }
        return $null
    }

    # Current process
    $env:FORGE_ANTHROPIC_OAUTH_TOKEN = $creds.AccessToken
    # Persist to User scope so fresh `gsd` processes pick it up without needing the bootstrap
    try {
        $existing = [System.Environment]::GetEnvironmentVariable('FORGE_ANTHROPIC_OAUTH_TOKEN', 'User')
        if ($existing -ne $creds.AccessToken) {
            [System.Environment]::SetEnvironmentVariable('FORGE_ANTHROPIC_OAUTH_TOKEN', $creds.AccessToken, 'User')
        }
    } catch {}

    return $creds
}

function Get-GsdModelsJsonPath {
    # Respect GSD_CONFIG_DIR if set; default is ~/.gsd/agent
    $root = $env:GSD_CONFIG_DIR
    if (-not $root) { $root = Join-Path $HOME '.gsd\agent' }
    if (-not (Test-Path $root)) {
        try { New-Item -ItemType Directory -Path $root -Force | Out-Null } catch {}
    }
    return (Join-Path $root 'models.json')
}

function Write-JsonUtf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )
    $json = $Object | ConvertTo-Json -Depth 12
    # Normalize line endings + ensure trailing newline
    $json = ($json -replace "`r`n", "`n").TrimEnd() + "`n"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

function New-ForgeAnthropicProviderObject {
    # Returns a PSCustomObject that serializes to the provider shape GSD expects.
    # Headers match what Forge/Claude Code send to Anthropic Messages API.
    # Model IDs + capabilities per docs.anthropic.com/en/docs/about-claude/models/overview
    # as of 2026-04 (Opus 4.7 / Sonnet 4.6 / Haiku 4.5 are current).
    $models = @(
        [ordered]@{
            id            = 'claude-opus-4-7'
            name          = 'Claude Opus 4.7 (Forge OAuth)'
            reasoning     = $true                  # adaptive + extended thinking
            input         = @('text','image')
            contextWindow = 1000000                # 1M tokens
            maxTokens     = 128000                 # 128k output
            cost          = [ordered]@{ input = 5.0; output = 25.0; cacheRead = 0.5; cacheWrite = 6.25 }
        },
        [ordered]@{
            id            = 'claude-sonnet-4-6'
            name          = 'Claude Sonnet 4.6 (Forge OAuth)'
            reasoning     = $true
            input         = @('text','image')
            contextWindow = 1000000                # 1M tokens
            maxTokens     = 64000
            cost          = [ordered]@{ input = 3.0; output = 15.0; cacheRead = 0.3; cacheWrite = 3.75 }
        },
        [ordered]@{
            id            = 'claude-haiku-4-5'
            name          = 'Claude Haiku 4.5 (Forge OAuth)'
            reasoning     = $true
            input         = @('text','image')
            contextWindow = 200000
            maxTokens     = 64000
            cost          = [ordered]@{ input = 1.0; output = 5.0; cacheRead = 0.1; cacheWrite = 1.25 }
        },
        # Older snapshots kept for compatibility with existing sessions/scripts.
        [ordered]@{
            id            = 'claude-opus-4-6'
            name          = 'Claude Opus 4.6 (Forge OAuth)'
            reasoning     = $true
            input         = @('text','image')
            contextWindow = 200000
            maxTokens     = 32000
            cost          = [ordered]@{ input = 5.0; output = 25.0; cacheRead = 0.5; cacheWrite = 6.25 }
        },
        [ordered]@{
            id            = 'claude-sonnet-4-5'
            name          = 'Claude Sonnet 4.5 (Forge OAuth)'
            reasoning     = $true
            input         = @('text','image')
            contextWindow = 200000
            maxTokens     = 64000
            cost          = [ordered]@{ input = 3.0; output = 15.0; cacheRead = 0.3; cacheWrite = 3.75 }
        }
    )

    return [ordered]@{
        baseUrl    = 'https://api.anthropic.com/v1'
        api        = 'anthropic-messages'
        apiKey     = 'FORGE_ANTHROPIC_OAUTH_TOKEN'   # env var reference -- GSD resolves at runtime
        authHeader = $true                            # -> Authorization: Bearer <token>
        headers    = [ordered]@{
            'anthropic-beta'    = 'oauth-2025-04-20,claude-code-20250219'
            'anthropic-version' = '2023-06-01'
        }
        models     = $models
    }
}

function Invoke-ForgeSyncToGsd {
    param(
        [switch]$DryRun,
        [string]$Name = 'anthropic-forge'
    )

    Write-Host ''
    Write-Host '  FORGE -> GSD -- sync Anthropic OAuth as custom provider' -ForegroundColor Cyan
    Write-Host '  Ref: gsd-build/gsd-2/docs/user-docs/custom-models.md' -ForegroundColor DarkGray
    Write-Host ''

    # 1. Read Forge credentials
    $creds = Read-ForgeAnthropicCreds
    if (-not $creds -or -not $creds.AccessToken) {
        Write-Host '  [error] no Forge Anthropic OAuth token found.' -ForegroundColor Red
        Write-Host '  Run: forge provider login   (select Claude)' -ForegroundColor White
        Write-Host ''
        return
    }

    $token = $creds.AccessToken
    $preview = if ($token.Length -gt 24) { $token.Substring(0,12) + '...' + $token.Substring($token.Length-8) } else { '***' }
    Write-Host ("  [ok] Forge token:   {0}" -f $preview) -ForegroundColor Green
    Write-Host ("       client_id:    {0}" -f $creds.ClientId) -ForegroundColor DarkGray
    Write-Host ("       scopes:       {0}" -f ($creds.Scopes -join ' ')) -ForegroundColor DarkGray
    if ($creds.ExpiresAt) {
        $now = [datetime]::UtcNow
        $remaining = $creds.ExpiresAt - $now
        $color = if ($remaining.TotalMinutes -lt 10) { 'Red' } elseif ($remaining.TotalMinutes -lt 60) { 'DarkYellow' } else { 'Green' }
        $humans = if ($remaining.TotalMinutes -lt 0) { 'EXPIRED' }
                  elseif ($remaining.TotalHours -ge 1) { ('{0:F1}h left' -f $remaining.TotalHours) }
                  else { ('{0:F0}min left' -f $remaining.TotalMinutes) }
        Write-Host ("       expires:      {0} UTC ({1})" -f $creds.ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss'), $humans) -ForegroundColor $color
    }

    # 2. Propagate to env
    Write-Host ''
    Write-Host '  [1/2] Environment variable' -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host '  [dry-run] would set $env:FORGE_ANTHROPIC_OAUTH_TOKEN (Process + User scope)' -ForegroundColor DarkYellow
    } else {
        $env:FORGE_ANTHROPIC_OAUTH_TOKEN = $token
        try {
            [System.Environment]::SetEnvironmentVariable('FORGE_ANTHROPIC_OAUTH_TOKEN', $token, 'User')
            Write-Host '  [ok] FORGE_ANTHROPIC_OAUTH_TOKEN set (Process + User)' -ForegroundColor Green
        } catch {
            Write-Host ("  [warn] could not persist to User scope: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            Write-Host '        (Process scope still set; ok for this session)' -ForegroundColor DarkGray
        }
    }

    # 3. Merge into models.json
    Write-Host ''
    Write-Host '  [2/2] ~/.gsd/agent/models.json' -ForegroundColor Cyan
    $path = Get-GsdModelsJsonPath

    $root = $null
    if (Test-Path $path) {
        try {
            $raw = Get-Content $path -Raw -Encoding UTF8
            if ($raw.Trim()) {
                $root = $raw | ConvertFrom-Json -ErrorAction Stop
            }
        } catch {
            Write-Host ("  [warn] existing models.json failed to parse: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            Write-Host '        A backup will be created before overwrite.' -ForegroundColor DarkGray
            if (-not $DryRun) {
                $backup = $path + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
                try { Copy-Item $path $backup -Force } catch {}
                Write-Host ("       backup: {0}" -f $backup) -ForegroundColor DarkGray
            }
            $root = $null
        }
    }

    # Convert parsed JSON to an ordered hashtable tree so we can merge cleanly
    # PSCustomObject -> hashtable so we can add/replace keys
    $providersHash = [ordered]@{}
    if ($root -and $root.providers) {
        foreach ($prop in $root.providers.PSObject.Properties) {
            $providersHash[$prop.Name] = $prop.Value
        }
    }

    $providerObj = New-ForgeAnthropicProviderObject
    $providersHash[$Name] = $providerObj

    # Preserve any other top-level keys (future-proof)
    $out = [ordered]@{}
    if ($root) {
        foreach ($prop in $root.PSObject.Properties) {
            if ($prop.Name -ne 'providers') { $out[$prop.Name] = $prop.Value }
        }
    }
    $out['providers'] = $providersHash

    if ($DryRun) {
        Write-Host ("  [dry-run] would write: {0}" -f $path) -ForegroundColor DarkYellow
        Write-Host '  [dry-run] provider block preview:' -ForegroundColor DarkYellow
        $preview = [ordered]@{ providers = [ordered]@{ $Name = $providerObj } } | ConvertTo-Json -Depth 10
        $preview -split "`n" | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor DarkGray }
    } else {
        try {
            Write-JsonUtf8NoBom -Path $path -Object $out
            Write-Host ("  [ok] wrote {0}" -f $path) -ForegroundColor Green
            Write-Host ("       provider key: {0}" -f $Name) -ForegroundColor DarkGray
        } catch {
            Write-Host ("  [error] write failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
            return
        }
    }

    Write-Host ''
    Write-Host '  Use in GSD:' -ForegroundColor DarkGray
    Write-Host ('    /model {0}/claude-opus-4-7'   -f $Name) -ForegroundColor White
    Write-Host ('    /model {0}/claude-sonnet-4-6' -f $Name) -ForegroundColor White
    Write-Host ('    /model {0}/claude-haiku-4-5'  -f $Name) -ForegroundColor White
    Write-Host '  Token auto-refreshes every new shell (bootstrap re-reads Forge creds).' -ForegroundColor DarkGray
    Write-Host '  Re-run `8sync forge sync-to-gsd` after `forge provider login` to refresh now.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-ForgeHelp {
    Write-Host ''
    Write-HintSection 'FORGE -- ForgeCode AI pair programmer (tailcallhq/forgecode)'
    Write-HintRow '8sync forge init'              'Scan .gsd/ .cursor/ .claude/ .agents/; generate AGENTS.md + .forge/skills (karpathy)'
    Write-HintRow '8sync forge init --dry-run'    'Preview what init would write (no files changed)'
    Write-HintRow '8sync forge init --force'      'Overwrite without creating .bak backup'
    Write-HintRow '8sync forge init --path DIR'   'Init a specific project dir instead of cwd'
    Write-HintRow '8sync forge add-skill'         'List built-in skills available for add-skill'
    Write-HintRow '8sync forge add-skill karpathy'          'Install karpathy skill into .forge/skills/ (project)'
    Write-HintRow '8sync forge add-skill karpathy --global' 'Install into ~/forge/skills/ (all projects)'
    Write-HintRow '8sync forge add-skill karpathy --agents' 'Install into ~/.agents/skills/ (shared)'
    Write-HintRow '8sync forge install'           'Download + install forge binary via forgecode.dev/cli'
    Write-HintRow '8sync forge install --with-zsh' 'Install forge + auto-install MSYS2 zsh + oh-my-zsh'
    Write-HintRow '8sync forge install --force'   'Reinstall even if already present (update)'
    Write-HintRow '8sync forge install --dry-run' 'Preview what the installer would do'
    Write-HintRow '8sync forge zsh'               'Install MSYS2 + zsh + oh-my-zsh (Windows zsh prerequisite)'
    Write-HintRow '8sync forge zsh --skip-omz'    'Install zsh only, skip oh-my-zsh'
    Write-HintRow '8sync forge zsh --dry-run'     'Preview zsh install steps'
    Write-HintRow '8sync forge enter'             'Spawn an interactive zsh login subshell (exit to return)'
    Write-HintRow '8sync forge lightmode'         'Upgrade ~/.zshrc to v2 block (fix AI chat lag from msg 2+)'
    Write-HintRow '8sync forge thinking'          'Show live [reasoning] from `forge config list`'
    Write-HintRow '8sync forge thinking off'      'effort=none (disable thinking; via forge config set)'
    Write-HintRow '8sync forge thinking low'      'Set reasoning effort=low (faster, cheaper)'
    Write-HintRow '8sync forge thinking medium'   'Set reasoning effort=medium'
    Write-HintRow '8sync forge thinking high'     'Set reasoning effort=high'
    Write-HintRow '8sync forge thinking xhigh'    'Set reasoning effort=xhigh'
    Write-HintRow '8sync forge thinking max'      'Set reasoning effort=max'
    Write-HintRow '8sync forge thinking on'       'Alias for high'
    Write-HintRow '8sync forge model'             'Show active provider+model+auth+reasoning'
    Write-HintRow '8sync forge model list'        'List providers (forge provider list) + login state'
    Write-HintRow '8sync forge model <model>'     'Set model on CURRENT provider (keeps provider_id)'
    Write-HintRow '8sync forge model <prov> <m>'  'Set provider+model atomically (e.g. claude_code claude-sonnet-4-6)'
    Write-HintRow '8sync forge config'            'Dump ALL forge config (porcelain TOML)'
    Write-HintRow '8sync forge config keys'       'List VALID config-set keys + arg schema (live from forge --help)'
    Write-HintRow '8sync forge config path'       'Print resolved forge config file path'
    Write-HintRow '8sync forge config get <k>'    'Read one config key (delegates to forge config get)'
    Write-HintRow '8sync forge config set <k> ...' 'Set ANY forge config key (forwards all args to forge config set)'
    Write-HintRow '8sync forge zsh-usage'         'How to use zsh on Windows (no exec zsh -- spawn subshell)'
    Write-HintRow '8sync forge status'            'Show installed version, binary path, dependency check'
    Write-HintRow '8sync forge login'             'Run: forge provider login (configure AI provider)'
    Write-HintRow '8sync forge sync-to-gsd'      'Sync Forge Anthropic OAuth -> GSD custom provider (models.json)'
    Write-HintRow '8sync forge sync-to-gsd --dry-run' 'Preview models.json changes without writing'
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

    # Guard: ValueFromRemainingArguments yields $null (not @()) when zero args
    # are passed -- downstream -contains / [Array]::IndexOf must see an array.
    if ($null -eq $Rest) { $Rest = @() }

    $dryRun   = $Rest -contains '--dry-run'
    $force    = $Rest -contains '--force'
    $withZsh  = $Rest -contains '--with-zsh'
    $skipOmz  = $Rest -contains '--skip-omz'

    $sub = 'help'
    if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') {
        $sub = $Rest[0].ToLowerInvariant()
    }

    switch ($sub) {
        'install'   {
            Invoke-ForgeInstall -DryRun:$dryRun -Force:$force
            if ($withZsh) {
                Write-Host '  --with-zsh: chaining zsh bootstrap...' -ForegroundColor Cyan
                Invoke-ForgeZshInstall -DryRun:$dryRun -Force:$force -SkipOmz:$skipOmz
            }
        }
        'update'    { Invoke-ForgeInstall -DryRun:$dryRun -Force }
        'zsh'       { Invoke-ForgeZshInstall -DryRun:$dryRun -Force:$force -SkipOmz:$skipOmz }
        'enter'       { Invoke-ForgeEnterZsh }
        'zsh-enter'   { Invoke-ForgeEnterZsh }
        'zsh-usage'   { Show-ForgeZshUsage }
        'usage'       { Show-ForgeZshUsage }
        'lightmode'   { Invoke-ForgeLightMode }
        'light-mode'  { Invoke-ForgeLightMode }
        'light'       { Invoke-ForgeLightMode }
        'thinking'    { Invoke-ForgeThinking -Rest ($Rest | Select-Object -Skip 1) }
        'think'       { Invoke-ForgeThinking -Rest ($Rest | Select-Object -Skip 1) }
        'model'       { Invoke-ForgeModel  -Rest ($Rest | Select-Object -Skip 1) }
        'models'      { Invoke-ForgeModel  -Rest ($Rest | Select-Object -Skip 1) }
        'config'      { Invoke-ForgeConfig -Rest ($Rest | Select-Object -Skip 1) }
        'cfg'         { Invoke-ForgeConfig -Rest ($Rest | Select-Object -Skip 1) }
        'init'        { Invoke-ForgeInit -Rest ($Rest | Select-Object -Skip 1) }
        'add-skill'   { Invoke-ForgeAddSkill -Rest ($Rest | Select-Object -Skip 1) }
        'skill'       { Invoke-ForgeAddSkill -Rest ($Rest | Select-Object -Skip 1) }
        'sync-to-gsd' {
            $nameIdx = [Array]::IndexOf($Rest, '--name')
            $customName = if ($nameIdx -ge 0 -and $nameIdx + 1 -lt $Rest.Count) { $Rest[$nameIdx + 1] } else { 'anthropic-forge' }
            Invoke-ForgeSyncToGsd -DryRun:$dryRun -Name $customName
        }
        'sync'        {
            $nameIdx = [Array]::IndexOf($Rest, '--name')
            $customName = if ($nameIdx -ge 0 -and $nameIdx + 1 -lt $Rest.Count) { $Rest[$nameIdx + 1] } else { 'anthropic-forge' }
            Invoke-ForgeSyncToGsd -DryRun:$dryRun -Name $customName
        }
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
# Auto-wire msys2\usr\bin into process PATH if zsh is installed but not findable.
# This handles the case where User PATH was updated in a previous session but
# the current shell inherited a stale PATH from its parent.
function Ensure-ZshInPath {
    # Fast path: zsh already on PATH
    if (Get-Command zsh -ErrorAction SilentlyContinue) { return }
    # Check if msys2 has a zsh we can reach
    $bash = Get-MsysBashPath
    if (-not $bash) { return }
    $binDir = Split-Path $bash -Parent
    $zshExe = Join-Path $binDir 'zsh.exe'
    if (-not (Test-Path $zshExe)) { return }
    # Append to process PATH so `forge zsh setup`, `where zsh`, etc. find it.
    if ($env:PATH -notmatch [regex]::Escape($binDir)) {
        $env:PATH = $env:PATH.TrimEnd(';') + ';' + $binDir
    }
}
Ensure-ZshInPath
# Auto-set EDITOR/FORGE_EDITOR for forge zsh doctor (quiet; picks hx > nvim > vim > nano)
try { Ensure-EditorEnv | Out-Null } catch {}
# Auto-refresh Forge Anthropic OAuth token into $env for GSD custom provider
# Quiet mode: silent if no Forge creds present (nothing to sync).
try { Sync-ForgeAnthropicEnv -Quiet | Out-Null } catch {}

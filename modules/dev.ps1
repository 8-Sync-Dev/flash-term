# =============================================================================
# ft dev -- install development runtimes (NO Visual Studio required)
# =============================================================================
# Usage:
#   ft dev                    Show status of all dev runtimes
#   ft dev node               Node.js + npm + pnpm (corepack)
#   ft dev python             uv + standalone CPython (no VS build tools)
#   ft dev go                 Go toolchain (self-contained)
#   ft dev rust               Rust GNU toolchain (no Visual Studio)
#   ft dev chromium           Chromium browser (automation / debugging)
#   ft dev all                Install every runtime above
#   ft dev --check            Dry-run: report what is missing, change nothing
#   ft dev help
# =============================================================================
#
# All runtimes install via Scoop. Two of them dodge the Visual Studio C++
# Build Tools requirement entirely:
#   - Rust uses the GNU (MinGW) host triple -- the scoop `gcc` package supplies
#     the linker + C runtime. No link.exe, no MSVC.
#   - Python is managed by `uv`, which ships prebuilt standalone CPython builds.
#
# `Invoke-DevInstall` (all runtimes) is also called by `ft setup`, so the
# `irm | iex` one-liner pulls everything down in a single bootstrap.

$script:DevToolchains = [ordered]@{
    node = @{
        Label    = 'Node.js + npm + pnpm'
        Packages = @('nodejs')
        Bucket   = $null
        Test     = { Test-CommandExists 'node' }
        Version  = { try { (& node --version) 2>$null } catch {} }
        PostInstall = {
            # scoop nodejs adds its dirs to the registry PATH (new tabs) but NOT to
            # this running process -- mirror them so node/npm/pnpm resolve now.
            # Exact element matching: a plain -notlike would treat nodejs\current as
            # already present once nodejs\current\bin is added (prefix match), hiding node.exe.
            $nodeRoot = Join-Path $HOME 'scoop\apps\nodejs\current'
            $parts = $env:PATH -split ';'
            foreach ($d in @($nodeRoot, (Join-Path $nodeRoot 'bin'))) {
                if ((Test-Path $d) -and ($parts -notcontains $d)) {
                    $env:PATH = "$d;$env:PATH"
                    $parts = @($d) + $parts
                }
            }
            if (Test-CommandExists 'corepack') {
                Write-Host '  [dev]   enabling pnpm + yarn via corepack...' -ForegroundColor DarkGray
                $null = corepack enable 2>&1
            }
            Clear-CommandCache
            if (-not (Test-CommandExists 'pnpm')) {
                Write-Host '  [dev]   fallback: npm install -g pnpm...' -ForegroundColor DarkGray
                $null = npm install -g pnpm 2>&1
            }
        }
    }
    python = @{
        Label    = 'Python (uv + standalone CPython)'
        Packages = @('uv')
        Bucket   = $null
        Test     = { Test-CommandExists 'uv' }
        Version  = { try { (& uv --version) 2>$null } catch {} }
        PostInstall = {
            Write-Host '  [dev]   installing a managed CPython via uv...' -ForegroundColor DarkGray
            $null = uv python install 2>&1
        }
    }
    go = @{
        Label    = 'Go'
        Packages = @('go')
        Bucket   = $null
        Test     = { Test-CommandExists 'go' }
        Version  = { try { (& go version) 2>$null } catch {} }
    }
    rust = @{
        Label    = 'Rust (GNU toolchain -- no Visual Studio)'
        Packages = @('gcc','rustup')
        Bucket   = $null
        Test     = { (Test-CommandExists 'rustc') -and (Test-CommandExists 'gcc') }
        Version  = { try { (& rustc --version) 2>$null } catch {} }
        PostInstall = {
            # rustup places rustc/cargo in a cargo bin dir -- wire it into this
            # process so the post-install Test sees them immediately. scoop rustup
            # uses ~/scoop/apps/rustup/current/.cargo/bin; standard rustup uses ~/.cargo/bin.
            $parts = $env:PATH -split ';'
            foreach ($cargoBin in @(
                (Join-Path $HOME 'scoop\apps\rustup\current\.cargo\bin'),
                (Join-Path $HOME '.cargo\bin')
            )) {
                if ((Test-Path $cargoBin) -and ($parts -notcontains $cargoBin)) {
                    $env:PATH = "$cargoBin;$env:PATH"
                    $parts = @($cargoBin) + $parts
                }
            }
            Write-Host '  [dev]   selecting GNU host triple (no VS link.exe needed)...' -ForegroundColor DarkGray
            $null = rustup default stable-x86_64-pc-windows-gnu 2>&1
        }
    }
    chromium = @{
        Label    = 'Chromium (browser / automation)'
        Packages = @('chromium')
        Bucket   = 'extras'
        Test     = { Test-CommandExists 'chromium' }
        Version  = {
            try {
                $exe = Join-Path $HOME 'scoop\apps\chromium\current\chrome.exe'
                if (Test-Path $exe) { (Get-Item $exe).VersionInfo.ProductVersion }
            } catch {}
        }
    }
    encore = @{
        Label    = 'Encore.dev CLI (Go backend framework)'
        Packages = $null
        Bucket   = $null
        Custom   = {
            Write-Host '  [dev]   running encore.dev install script...' -ForegroundColor DarkGray
            iwr -useb https://encore.dev/install.ps1 | iex
        }
        Test     = { Test-CommandExists 'encore' }
        Version  = { try { (& encore version 2>$null) } catch {} }
    }
    docker = @{
        Label    = 'Docker Desktop (admin + WSL2 + first GUI launch required)'
        Packages = $null
        Bucket   = $null
        Custom   = {
            Write-Host '  [dev]   installing Docker Desktop via winget (UAC prompt expected)...' -ForegroundColor DarkGray
            winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements --disable-interactivity
        }
        Test     = { Test-CommandExists 'docker' }
        Version  = { try { (& docker --version 2>$null) } catch {} }
        PostInstall = {
            Write-Host '  [note]  Launch Docker Desktop once (GUI) + enable WSL2 integration to start the engine' -ForegroundColor DarkYellow
        }
    }
}

function Clear-CommandCache {
    # Test-CommandExists memoizes results; invalidate after installs so newly
    # created shims are visible within the same run.
    $script:CommandExistsCache = @{}
}

function Install-DevChain {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [switch]$DryRun
    )

    $chain = $script:DevToolchains[$Name]
    if (-not $chain) { return }

    if (& $chain.Test) {
        Write-Host ("  [ok]    {0,-9} {1}" -f $Name, (& $chain.Version)) -ForegroundColor Green
        return
    }

    if ($DryRun) {
        $plan = if ($chain.Custom) { 'custom installer' } else { ($chain.Packages -join ', ') }
        Write-Host ("  [miss]  {0,-9} would install: {1}" -f $Name, $plan) -ForegroundColor Yellow
        return
    }

    # Two install paths: a `Custom` scriptblock (non-scoop -- encore iwr, docker
    # winget) or the default Scoop package path.
    if ($chain.Custom) {
        Write-Host ("  [dev]   installing {0}" -f $Name) -ForegroundColor Cyan
        try {
            & $chain.Custom
            Ensure-PreferredPaths
            Clear-CommandCache
        } catch {
            Write-Host ("  [error] {0} install failed: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
            return
        }
    } else {
        $scoop = Get-ScoopCommand
        if (-not $scoop) {
            Write-Host ("  [error] {0} -- Scoop not found (run: ft setup)" -f $Name) -ForegroundColor Red
            return
        }
        # Ensure the required bucket exists (chromium lives in extras).
        if ($chain.Bucket) {
            try { Ensure-ScoopBuckets -Scoop $scoop -Buckets @($chain.Bucket) } catch {}
        }
        Write-Host ("  [dev]   installing {0}: {1}" -f $Name, ($chain.Packages -join ', ')) -ForegroundColor Cyan
        try {
            & $scoop.Source install @($chain.Packages) | Out-Host
            Ensure-PreferredPaths
            Clear-CommandCache
        } catch {
            Write-Host ("  [error] {0} install failed: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
            return
        }
    }

    if ($chain.PostInstall) {
        try { & $chain.PostInstall } catch {
            Write-Host ("  [warn]  {0} post-install skipped: {1}" -f $Name, $_.Exception.Message) -ForegroundColor DarkYellow
        }
        Ensure-PreferredPaths
        Clear-CommandCache
    }

    if (& $chain.Test) {
        Write-Host ("  [ok]    {0,-9} {1}" -f $Name, (& $chain.Version)) -ForegroundColor Green
    } else {
        Write-Host ("  [warn]  {0} installed -- open a new tab to activate" -f $Name) -ForegroundColor DarkYellow
    }
}

function Invoke-DevInstall {
    # Install ALL dev runtimes. Called by `ft setup` (the one-liner bootstrap)
    # and `ft dev all`. Resilient: a per-chain failure never aborts the rest.
    param([switch]$DryRun)
    foreach ($name in $script:DevToolchains.Keys) {
        Install-DevChain -Name $name -DryRun:$DryRun
    }
}

function Show-DevStatus {
    Write-Host ''
    Write-Host '  FT DEV -- development runtimes (no Visual Studio required)' -ForegroundColor Magenta
    Write-Host ''
    $anyMissing = $false
    foreach ($name in $script:DevToolchains.Keys) {
        $chain = $script:DevToolchains[$name]
        if (& $chain.Test) {
            Write-Host ("  {0,-9} [installed] {1}" -f $name, (& $chain.Version)) -ForegroundColor Green
        } else {
            $anyMissing = $true
            Write-Host ("  {0,-9} [missing]   {1}" -f $name, $chain.Label) -ForegroundColor Yellow
            Write-Host ("            install: ft dev {0}" -f $name) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    if ($anyMissing) {
        Write-Host '  Install all: ft dev all' -ForegroundColor Cyan
    } else {
        Write-Host '  All dev runtimes installed.' -ForegroundColor Green
    }
    Write-Host ''
}

function Show-DevHelp {
    Write-Host ''
    Write-Host '  FT DEV -- development runtimes (no Visual Studio required)' -ForegroundColor Cyan
    Write-Host '  Runtimes install via Scoop (Rust uses GNU/MinGW, no VS); encore & Docker' -ForegroundColor DarkGray
    Write-Host '  use their own installers. Python ships standalone CPython via uv.' -ForegroundColor DarkGray
    Write-Host ''
    Write-HintRow 'ft dev'              'Show status of all dev runtimes'
    Write-HintRow 'ft dev node'         'Node.js + npm + pnpm (corepack)'
    Write-HintRow 'ft dev python'       'uv + standalone CPython (no VS tools)'
    Write-HintRow 'ft dev go'           'Go toolchain (self-contained)'
    Write-HintRow 'ft dev rust'         'Rust GNU toolchain (no Visual Studio)'
    Write-HintRow 'ft dev chromium'     'Chromium browser (automation / debugging)'
    Write-HintRow 'ft dev docker'        'Docker Desktop via winget (needs admin + WSL2 + first GUI launch)'
    Write-HintRow 'ft dev encore'        'Encore.dev CLI backend framework (iwr install.ps1)'
    Write-HintRow 'ft dev all'          'Install every runtime above'
    Write-HintRow 'ft dev --check'      'Dry-run: report missing runtimes, change nothing'
    Write-Host ''
    Write-Host '  Editor LSP servers: ft hx lang <language>' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-DevCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    if ($Rest -contains '--help' -or $Rest -contains 'help' -or $Rest -contains '-h') { Show-DevHelp; return }
    $dryRun  = $Rest -contains '--check' -or $Rest -contains '--dry-run'
    $targets = @($Rest | Where-Object { $_ -and $_ -notlike '--*' -and $_ -notin @('help','-h') })

    if ($targets.Count -eq 0) { Show-DevStatus; return }

    if ($targets -contains 'all') { $targets = @($script:DevToolchains.Keys) }

    Write-Host ''
    Write-Host '  FT DEV' -ForegroundColor Magenta
    if ($dryRun) { Write-Host '  (dry-run -- no changes)' -ForegroundColor Yellow }
    Write-Host ''

    foreach ($t in $targets) {
        $key = $t.ToLowerInvariant()
        if ($script:DevToolchains.Contains($key)) {
            Install-DevChain -Name $key -DryRun:$dryRun
        } else {
            Write-Host ("  [skip]  unknown runtime: {0}" -f $t) -ForegroundColor DarkYellow
            Write-Host ("          available: {0}" -f ($script:DevToolchains.Keys -join ', ')) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

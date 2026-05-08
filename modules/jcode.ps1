# ---------------------------------------------------------------------------
#  jcode.ps1 -- jcode (1jehuang/jcode) install / update / auth helper
#  Repo:    https://github.com/1jehuang/jcode
#  Install: irm https://raw.githubusercontent.com/1jehuang/jcode/master/scripts/install.ps1 | iex
# ---------------------------------------------------------------------------

function Get-JcodeInstallPath {
    # PATH first, then common install locations
    $fromPath = Get-Command jcode -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\jcode\jcode.exe'),
        (Join-Path $env:LOCALAPPDATA 'jcode\jcode.exe'),
        (Join-Path $HOME '.jcode\bin\jcode.exe'),
        (Join-Path $HOME '.local\bin\jcode.exe'),
        (Join-Path $HOME '.cargo\bin\jcode.exe')
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-JcodeVersion {
    $path = Get-JcodeInstallPath
    if (-not $path) { return $null }
    try {
        $ver = & $path --version 2>$null
        return "$ver".Trim()
    } catch {
        return $null
    }
}

function Add-JcodeToProcessPath {
    # After install, refresh process PATH so jcode is reachable in current shell.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\jcode'),
        (Join-Path $env:LOCALAPPDATA 'jcode'),
        (Join-Path $HOME '.jcode\bin'),
        (Join-Path $HOME '.local\bin'),
        (Join-Path $HOME '.cargo\bin')
    )
    foreach ($dir in $candidates) {
        if (-not (Test-Path $dir)) { continue }
        if ($env:PATH -notlike "*$dir*") {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}

function Invoke-JcodeInstall {
    param([switch]$DryRun, [switch]$Force)

    Write-Host ''
    Write-Host '  JCODE -- install / update' -ForegroundColor Cyan
    Write-Host '  Repo: https://github.com/1jehuang/jcode' -ForegroundColor DarkGray
    Write-Host ''

    $existing = Get-JcodeVersion
    if ($existing -and -not $Force) {
        Write-Host ("  [ok] jcode already installed: {0}" -f $existing) -ForegroundColor Green
        Write-Host '  Use --force to reinstall / update.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if ($existing -and $Force) {
        Write-Host ("  [info] Reinstalling over existing: {0}" -f $existing) -ForegroundColor Yellow
    }

    $script = 'https://raw.githubusercontent.com/1jehuang/jcode/master/scripts/install.ps1'

    if ($DryRun) {
        Write-Host '  [dry-run] would run:' -ForegroundColor DarkYellow
        Write-Host ("    irm {0} | iex" -f $script) -ForegroundColor White
        Write-Host ''
        return
    }

    Write-Host ("  Running: irm {0} | iex" -f $script) -ForegroundColor DarkGray
    Write-Host ''

    try {
        $code = Invoke-RestMethod -Uri $script -ErrorAction Stop
        Invoke-Expression $code
    } catch {
        Write-Host ("  [error] Install failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host '  Manual fallback: irm https://raw.githubusercontent.com/1jehuang/jcode/master/scripts/install.ps1 | iex' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Add-JcodeToProcessPath
    Write-Host ''

    $ver = Get-JcodeVersion
    if ($ver) {
        Write-Host ("  [ok] jcode installed: {0}" -f $ver) -ForegroundColor Green
        $bin = Get-JcodeInstallPath
        if ($bin) { Write-Host ("        binary: {0}" -f $bin) -ForegroundColor DarkGray }
    } else {
        Write-Host '  [warn] Installer ran but jcode not yet on PATH.' -ForegroundColor DarkYellow
        Write-Host '  Open a new terminal or restart this shell, then run: jcode --version' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Get-JcodeProviderStatus {
    # Non-interactively probe for already-configured providers (creds files / env vars).
    # Returns ordered list of [pscustomobject]@{ Provider; Source; Configured }.
    $home = $HOME
    $checks = @(
        @{ P = 'claude';      S = (Join-Path $home '.jcode\auth.json') },
        @{ P = 'claude';      S = (Join-Path $home '.claude\.credentials.json') },
        @{ P = 'claude';      S = (Join-Path $home '.local\share\opencode\auth.json') },
        @{ P = 'claude';      S = 'env:ANTHROPIC_API_KEY' },
        @{ P = 'openai';      S = (Join-Path $home '.jcode\openai-auth.json') },
        @{ P = 'openai';      S = (Join-Path $home '.codex\auth.json') },
        @{ P = 'openai';      S = 'env:OPENAI_API_KEY' },
        @{ P = 'gemini';      S = (Join-Path $home '.jcode\gemini_oauth.json') },
        @{ P = 'gemini';      S = (Join-Path $home '.gemini\oauth_creds.json') },
        @{ P = 'copilot';     S = (Join-Path $home '.config\github-copilot') },
        @{ P = 'azure';       S = (Join-Path $home '.config\jcode\azure-openai.env') },
        @{ P = 'azure';       S = 'env:AZURE_OPENAI_API_KEY' },
        @{ P = 'azure';       S = 'env:AZURE_OPENAI_ENDPOINT' },
        @{ P = 'openrouter';  S = 'env:OPENROUTER_API_KEY' },
        @{ P = 'fireworks';   S = (Join-Path $home '.config\jcode\fireworks.env') },
        @{ P = 'fireworks';   S = 'env:FIREWORKS_API_KEY' },
        @{ P = 'minimax';     S = (Join-Path $home '.config\jcode\minimax.env') },
        @{ P = 'minimax';     S = 'env:MINIMAX_API_KEY' }
    )

    $rows = foreach ($c in $checks) {
        $configured = $false
        if ($c.S -like 'env:*') {
            $name = $c.S.Substring(4)
            $val  = [System.Environment]::GetEnvironmentVariable($name, 'Process')
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($name, 'User') }
            if ($val) { $configured = $true }
        } else {
            if (Test-Path $c.S) { $configured = $true }
        }
        [pscustomobject]@{ Provider = $c.P; Source = $c.S; Configured = $configured }
    }

    return $rows
}

function Invoke-JcodeStatus {
    Write-Host ''
    Write-Host '  JCODE -- status' -ForegroundColor Cyan
    Write-Host ''

    $bin = Get-JcodeInstallPath
    if ($bin) {
        Write-Host ("  {0,-12} {1}" -f 'binary:', $bin) -ForegroundColor Green
        $ver = Get-JcodeVersion
        Write-Host ("  {0,-12} {1}" -f 'version:', $(if ($ver) { $ver } else { '(could not read)' })) `
            -ForegroundColor $(if ($ver) { 'Green' } else { 'DarkYellow' })
    } else {
        Write-Host '  jcode not installed.' -ForegroundColor DarkYellow
        Write-Host '  Run: 8sync jcode install' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  Providers (non-interactive probe):' -ForegroundColor DarkGray
    $rows = Get-JcodeProviderStatus
    $any = $false
    foreach ($g in $rows | Group-Object Provider) {
        $hits = $g.Group | Where-Object { $_.Configured }
        if ($hits) {
            $any = $true
            Write-Host ("    [x] {0,-10} via {1}" -f $g.Name, ($hits[0].Source)) -ForegroundColor Green
        } else {
            Write-Host ("    [ ] {0,-10} (no creds / env)" -f $g.Name) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    if ($any) {
        Write-Host '  Verify:  jcode auth-test --all-configured' -ForegroundColor DarkGray
    } else {
        Write-Host '  No providers configured. Run: 8sync jcode login [provider]' -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Invoke-JcodeLaunch {
    $bin = Get-JcodeInstallPath
    if (-not $bin) {
        Write-Host '  jcode not installed. Run: 8sync jcode install' -ForegroundColor DarkYellow
        return
    }
    Write-Host ("  Launching jcode in a new WezTerm tab: {0}" -f $bin) -ForegroundColor Cyan
    $wt = Get-Command wezterm -ErrorAction SilentlyContinue
    if ($wt) {
        try {
            & $wt.Source cli spawn -- $bin | Out-Null
            Write-Host '  [ok] Spawned new WezTerm tab running jcode.' -ForegroundColor Green
            return
        } catch {
            Write-Host ("  [warn] wezterm cli spawn failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
    # Fallback: run inline
    Write-Host '  Running jcode in current shell...' -ForegroundColor DarkGray
    & $bin
}

function Invoke-JcodeSmokeTest {
    $bin = Get-JcodeInstallPath
    if (-not $bin) {
        Write-Host '  jcode not installed. Run: 8sync jcode install' -ForegroundColor DarkYellow
        return
    }
    Write-Host ''
    Write-Host '  JCODE -- smoke test (jcode run "say hello")' -ForegroundColor Cyan
    Write-Host ''
    try {
        & $bin run 'say hello'
    } catch {
        Write-Host ("  [error] Smoke test failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Write-Host ''
}

function Invoke-JcodeAuthTest {
    $bin = Get-JcodeInstallPath
    if (-not $bin) {
        Write-Host '  jcode not installed. Run: 8sync jcode install' -ForegroundColor DarkYellow
        return
    }
    Write-Host ''
    Write-Host '  JCODE -- auth-test --all-configured' -ForegroundColor Cyan
    Write-Host ''
    try {
        & $bin auth-test --all-configured
    } catch {
        Write-Host ("  [error] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Write-Host ''
}

function Invoke-JcodeLogin {
    param([string[]]$Rest)
    $bin = Get-JcodeInstallPath
    if (-not $bin) {
        Write-Host '  jcode not installed. Run: 8sync jcode install' -ForegroundColor DarkYellow
        return
    }

    $known = @('claude','copilot','openai','gemini','azure','fireworks','minimax','alibaba-coding-plan')
    $provider = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { '' }

    if (-not $provider) {
        Write-Host ''
        Write-Host '  Usage: 8sync jcode login <provider>' -ForegroundColor Cyan
        Write-Host ('  Providers: ' + ($known -join ', ')) -ForegroundColor DarkGray
        Write-Host '  Env-only:' -ForegroundColor DarkGray
        Write-Host '    openrouter  -> set OPENROUTER_API_KEY' -ForegroundColor DarkGray
        Write-Host '    anthropic   -> set ANTHROPIC_API_KEY' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if ($provider -eq 'openrouter' -or $provider -eq 'anthropic') {
        $varName = if ($provider -eq 'openrouter') { 'OPENROUTER_API_KEY' } else { 'ANTHROPIC_API_KEY' }
        Write-Host ''
        Write-Host ("  {0} uses an env var, not 'jcode login'." -f $provider) -ForegroundColor Cyan
        Write-Host ("  Set it (User scope, persists):") -ForegroundColor DarkGray
        Write-Host ("    [Environment]::SetEnvironmentVariable('{0}', '<your-key>', 'User')" -f $varName) -ForegroundColor White
        Write-Host '  Then open a new shell and run: 8sync jcode status' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if ($known -notcontains $provider) {
        Write-Host ("  Unknown provider: {0}" -f $provider) -ForegroundColor Red
        Write-Host ('  Known: ' + ($known -join ', ')) -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host ("  Running: jcode login --provider {0}" -f $provider) -ForegroundColor Cyan
    Write-Host '  Follow any prompts (browser OAuth / device code / API key).' -ForegroundColor DarkGray
    Write-Host ''
    & $bin login --provider $provider
}

function Invoke-JcodeBrowser {
    param([string[]]$Rest)
    $bin = Get-JcodeInstallPath
    if (-not $bin) {
        Write-Host '  jcode not installed. Run: 8sync jcode install' -ForegroundColor DarkYellow
        return
    }
    $sub = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'status' }
    if ($sub -ne 'status' -and $sub -ne 'setup') {
        Write-Host '  Usage: 8sync jcode browser [status|setup]' -ForegroundColor DarkGray
        return
    }
    Write-Host ''
    Write-Host ("  Running: jcode browser {0}" -f $sub) -ForegroundColor Cyan
    Write-Host ''
    & $bin browser $sub
    if ($sub -eq 'setup') {
        Write-Host ''
        Write-Host '  After setup completes, approve any browser-extension prompt,' -ForegroundColor DarkGray
        Write-Host "  then verify with: 8sync jcode browser status" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-JcodeSetup {
    # End-to-end: install -> verify PATH -> launch -> probe providers -> smoke test -> browser status
    Write-Host ''
    Write-Host '  JCODE -- setup (auto)' -ForegroundColor Cyan
    Write-Host ''

    # 1. Install / update
    Invoke-JcodeInstall

    # 2. Verify PATH
    $bin = Get-JcodeInstallPath
    if (-not $bin) {
        Write-Host '  [stop] jcode still not on PATH. Open a new terminal and re-run: 8sync jcode setup' -ForegroundColor Red
        return
    }
    Write-Host ("  [ok] PATH: {0}" -f $bin) -ForegroundColor Green

    # 3. Launch in a new tab once
    Write-Host ''
    Invoke-JcodeLaunch

    # 4 + 5. Probe providers; auth-test if any configured
    Write-Host ''
    Invoke-JcodeStatus
    $rows = Get-JcodeProviderStatus
    $hasAny = ($rows | Where-Object { $_.Configured }).Count -gt 0
    if ($hasAny) {
        Invoke-JcodeAuthTest
    } else {
        Write-Host '  [next] No provider configured. Pick one:' -ForegroundColor Yellow
        Write-Host '    8sync jcode login claude     # browser OAuth' -ForegroundColor DarkGray
        Write-Host '    8sync jcode login copilot    # device code' -ForegroundColor DarkGray
        Write-Host '    8sync jcode login openai     # browser OAuth or API key' -ForegroundColor DarkGray
        Write-Host '    8sync jcode login gemini     # browser OAuth' -ForegroundColor DarkGray
        Write-Host '    8sync jcode login openrouter # set OPENROUTER_API_KEY env var' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # 7. Smoke test
    Invoke-JcodeSmokeTest

    # 8. Browser status (informational only -- do not auto-run setup)
    Write-Host '  Browser automation:' -ForegroundColor DarkGray
    try { & $bin browser status } catch {
        Write-Host '    (jcode browser status unavailable)' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  Done. Run: 8sync jcode browser setup   # if browser tool not ready' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-JcodeHelp {
    Write-Host ''
    Write-HintSection 'JCODE -- 1jehuang/jcode CLI'
    Write-HintRow '8sync jcode setup'              'Auto: install, verify PATH, launch, probe providers, smoke test'
    Write-HintRow '8sync jcode install'            'Install jcode via official PowerShell installer'
    Write-HintRow '8sync jcode install --force'    'Reinstall / update over existing binary'
    Write-HintRow '8sync jcode install --dry-run'  'Show what would run, no changes'
    Write-HintRow '8sync jcode update'             'Force-reinstall to latest'
    Write-HintRow '8sync jcode status'             'Show binary, version, configured providers'
    Write-HintRow '8sync jcode launch'             'Spawn jcode in a new WezTerm tab'
    Write-HintRow '8sync jcode smoke'              'Run: jcode run "say hello"'
    Write-HintRow '8sync jcode auth-test'          'Run: jcode auth-test --all-configured'
    Write-HintRow '8sync jcode login <provider>'   'claude | copilot | openai | gemini | azure | fireworks | minimax | alibaba-coding-plan'
    Write-HintRow '8sync jcode login openrouter'   'Guide to set OPENROUTER_API_KEY (env-only provider)'
    Write-HintRow '8sync jcode login anthropic'    'Guide to set ANTHROPIC_API_KEY (direct API)'
    Write-HintRow '8sync jcode browser status'     'Check built-in browser automation tool'
    Write-HintRow '8sync jcode browser setup'      'Run jcode browser setup (may need extension approval)'
    Write-Host ''
}

function Invoke-JcodeCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    if ($null -eq $Rest) { $Rest = @() }

    $dryRun = $Rest -contains '--dry-run'
    $force  = $Rest -contains '--force'

    $sub = 'help'
    if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') {
        $sub = $Rest[0].ToLowerInvariant()
    }

    switch ($sub) {
        'setup'      { Invoke-JcodeSetup }
        'auto'       { Invoke-JcodeSetup }
        'install'    { Invoke-JcodeInstall -DryRun:$dryRun -Force:$force }
        'update'     { Invoke-JcodeInstall -DryRun:$dryRun -Force }
        'reinstall'  { Invoke-JcodeInstall -DryRun:$dryRun -Force }
        'status'     { Invoke-JcodeStatus }
        'launch'     { Invoke-JcodeLaunch }
        'open'       { Invoke-JcodeLaunch }
        'smoke'      { Invoke-JcodeSmokeTest }
        'test'       { Invoke-JcodeSmokeTest }
        'auth-test'  { Invoke-JcodeAuthTest }
        'auth'       { Invoke-JcodeAuthTest }
        'login'      { Invoke-JcodeLogin -Rest ($Rest | Select-Object -Skip 1) }
        'browser'    { Invoke-JcodeBrowser -Rest ($Rest | Select-Object -Skip 1) }
        'help'       { Show-JcodeHelp }
        '--help'     { Show-JcodeHelp }
        '-h'         { Show-JcodeHelp }
        default      { Show-JcodeHelp }
    }
}

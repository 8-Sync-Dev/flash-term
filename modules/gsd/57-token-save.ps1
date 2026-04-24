# =============================================================================
# 8sync gsd token-save -- minimize Claude Code CLI token burn via rtk
# =============================================================================
# Context: after `8sync gsd auth-fix`, GSD routes through Claude Code CLI
# (claude-code: {type: "cli"}). Every Bash tool call in Claude Code sends
# full raw command output back into LLM context -- `git status` = 2-3k tokens,
# `cargo test` = 25k tokens, `cat file.rs` = 40k tokens.
#
# rtk (github.com/rtk-ai/rtk) is a Rust CLI proxy that sits between Claude's
# Bash tool and the actual shell, filtering/compressing output. Reported
# savings: 60-90% on common dev commands (git, ls, cat, grep, cargo test,
# npm test, docker, ruff, pytest, etc.).
#
# Install flow:
#   1. Check rtk in PATH -- if missing, offer install (scoop > cargo > binary)
#   2. Run `rtk init -g` -- writes PreToolUse Bash hook to ~/.claude/settings.json
#   3. Ensure auth.json has claude-code: {type: "cli"} (reuses Invoke-GsdAuthFix)
#   4. Print verify steps
#
# Usage:
#   8sync gsd token-save [--dry-run] [--skip-auth-fix] [--method scoop|cargo|binary]
# =============================================================================

function Get-RtkLatestBinaryUrl {
    # Returns the direct download URL for the Windows x86_64 zip from the
    # latest rtk release, or $null on failure.
    try {
        $api = 'https://api.github.com/repos/rtk-ai/rtk/releases/latest'
        $rel = Invoke-RestMethod -Uri $api -UseBasicParsing -Headers @{ 'User-Agent' = '8sync-gsd' } -ErrorAction Stop
        $asset = $rel.assets | Where-Object { $_.name -match 'rtk-x86_64-pc-windows-msvc\.zip$' } | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
    } catch {}
    return $null
}

function Install-RtkBinary {
    # Download the prebuilt Windows zip, extract rtk.exe into ~/.local/bin,
    # ensure it is on PATH (warn user if not). Returns $true on success.
    param([switch]$DryRun)

    $url = Get-RtkLatestBinaryUrl
    if (-not $url) {
        Write-Host '  [error]  Could not resolve latest rtk release URL' -ForegroundColor Red
        return $false
    }

    $targetDir = Join-Path $HOME '.local\bin'
    $targetExe = Join-Path $targetDir 'rtk.exe'

    if ($DryRun) {
        Write-Host ('  [dry-run] Would download: {0}' -f $url) -ForegroundColor Yellow
        Write-Host ('  [dry-run] Would extract to: {0}' -f $targetExe) -ForegroundColor Yellow
        return $true
    }

    if (-not (Test-Path $targetDir)) {
        $null = New-Item -Path $targetDir -ItemType Directory -Force
    }

    $tmpZip = Join-Path $env:TEMP ('rtk-' + [guid]::NewGuid().ToString() + '.zip')
    $tmpExtract = Join-Path $env:TEMP ('rtk-' + [guid]::NewGuid().ToString())

    try {
        Write-Host ('  [info]   Downloading: {0}' -f $url) -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

        $exe = Get-ChildItem -Path $tmpExtract -Filter 'rtk.exe' -Recurse -File | Select-Object -First 1
        if (-not $exe) {
            Write-Host '  [error]  rtk.exe not found inside zip' -ForegroundColor Red
            return $false
        }
        Copy-Item $exe.FullName $targetExe -Force
        Write-Host ('  [ok]     Installed rtk -> {0}' -f $targetExe) -ForegroundColor Green

        # Check PATH
        $pathDirs = $env:PATH -split ';'
        $onPath = $pathDirs | Where-Object { [System.IO.Path]::GetFullPath($_.TrimEnd('\')) -ieq [System.IO.Path]::GetFullPath($targetDir) }
        if (-not $onPath) {
            Write-Host ('  [warn]   {0} is NOT on PATH. Add it with:' -f $targetDir) -ForegroundColor DarkYellow
            Write-Host ('           setx PATH "%PATH%;{0}"' -f $targetDir) -ForegroundColor DarkGray
            Write-Host '           (then restart your shell)' -ForegroundColor DarkGray
        }
        return $true
    } catch {
        Write-Host ('  [error]  Download/extract failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        return $false
    } finally {
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-RtkViaScoop {
    param([switch]$DryRun)
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host '  [skip]   scoop not found' -ForegroundColor DarkGray
        return $false
    }
    # RTK is not in the main scoop bucket as of now; fall back to binary
    # install path silently. (Left here for forward-compat if a bucket lands.)
    Write-Host '  [info]   scoop detected but no official rtk bucket -- using binary install' -ForegroundColor DarkGray
    return $false
}

function Install-RtkViaCargo {
    param([switch]$DryRun)
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Host '  [skip]   cargo not found' -ForegroundColor DarkGray
        return $false
    }
    if ($DryRun) {
        Write-Host '  [dry-run] Would run: cargo install --git https://github.com/rtk-ai/rtk' -ForegroundColor Yellow
        return $true
    }
    Write-Host '  [info]   Installing via cargo (this can take 2-5 min)...' -ForegroundColor DarkGray
    try {
        & cargo install --git https://github.com/rtk-ai/rtk 2>&1 | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor DarkGray }
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [ok]     cargo install rtk succeeded' -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host ('  [error]  cargo install failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
    return $false
}

function Invoke-RtkInitGlobal {
    # Run `rtk init -g` -- writes the PreToolUse Bash hook to
    # ~/.claude/settings.json so Claude Code rewrites `git status` -> `rtk git status`
    # transparently before execution.
    param([switch]$DryRun)

    if ($DryRun) {
        Write-Host '  [dry-run] Would run: rtk init -g' -ForegroundColor Yellow
        return $true
    }

    try {
        $output = & rtk init -g 2>&1 | Out-String
        Write-Host ($output.TrimEnd()) -ForegroundColor DarkGray
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [ok]     rtk global hook registered in ~/.claude/settings.json' -ForegroundColor Green
            return $true
        }
        Write-Host ('  [error]  rtk init -g exited with code {0}' -f $LASTEXITCODE) -ForegroundColor Red
        return $false
    } catch {
        Write-Host ('  [error]  rtk init -g failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Set-ClaudeCodeTokenSaveEnv {
    # Writes opinionated token-saving env vars into ~/.claude/settings.json
    # under the "env" block (honored by Claude Code CLI at launch).
    #
    # Enabled (safe savings):
    #   CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1 -- fixed thinking budget, no ballooning
    #   CLAUDE_CODE_SKIP_PROMPT_HISTORY=1       -- don't persist transcript
    #   CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1  -- drop built-in git prompt boilerplate
    #
    # NOT enabled: DISABLE_PROMPT_CACHING (would HURT token usage -- caching
    # is what gives the discount on repeated system prompts).
    param([switch]$DryRun, [switch]$IncludeDisableCaching)

    $settingsPath = Join-Path $HOME '.claude\settings.json'
    $settingsDir  = Split-Path $settingsPath -Parent

    $desired = [ordered]@{
        CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = '1'
        CLAUDE_CODE_SKIP_PROMPT_HISTORY       = '1'
        CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS  = '1'
    }
    if ($IncludeDisableCaching) {
        $desired['DISABLE_PROMPT_CACHING'] = '1'
    }

    # Read existing settings.json if present
    $settings = [ordered]@{}
    if (Test-Path $settingsPath) {
        try {
            $raw    = [System.IO.File]::ReadAllText($settingsPath)
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $parsed.PSObject.Properties) {
                $settings[$prop.Name] = $prop.Value
            }
        } catch {
            Write-Host ('  [warn]   settings.json unreadable ({0}) -- will rewrite.' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    # Merge env block
    $envBlock = [ordered]@{}
    if ($settings.Contains('env') -and $settings['env']) {
        foreach ($prop in $settings['env'].PSObject.Properties) {
            $envBlock[$prop.Name] = $prop.Value
        }
    }

    $added = @()
    foreach ($key in $desired.Keys) {
        if (-not $envBlock.Contains($key) -or [string]$envBlock[$key] -ne [string]$desired[$key]) {
            $envBlock[$key] = $desired[$key]
            $added += $key
        }
    }

    if ($added.Count -eq 0) {
        Write-Host '  [ok]     All token-save env vars already set.' -ForegroundColor Green
        return
    }

    if ($DryRun) {
        Write-Host '  [dry-run] Would write/update settings.json env:' -ForegroundColor Yellow
        foreach ($k in $added) { Write-Host ('    + {0}={1}' -f $k, $desired[$k]) -ForegroundColor Yellow }
        return
    }

    if (-not (Test-Path $settingsDir)) {
        $null = New-Item -Path $settingsDir -ItemType Directory -Force
    }

    # Backup before write
    if (Test-Path $settingsPath) {
        $backup = $settingsPath + '.bak-tokensave-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        try {
            Copy-Item $settingsPath $backup -Force
            Write-Host ('  [ok]     Backed up settings.json -> {0}' -f (Split-Path $backup -Leaf)) -ForegroundColor DarkGray
        } catch {
            Write-Host ('  [warn]   Could not backup settings.json: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    $settings['env'] = $envBlock
    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $json = ($settings | ConvertTo-Json -Depth 20)
        [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
        foreach ($k in $added) {
            Write-Host ('  [ok]     Set env.{0}={1}' -f $k, $desired[$k]) -ForegroundColor Green
        }
    } catch {
        Write-Host ('  [error]  Could not write settings.json: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Invoke-GsdTokenSave {
    param(
        [switch]$DryRun,
        [switch]$SkipAuthFix,
        [switch]$SkipEnv,
        [switch]$IncludeDisableCaching,
        [ValidateSet('auto', 'scoop', 'cargo', 'binary')]
        [string]$Method = 'auto'
    )

    Write-Host ''
    Write-Host '  GSD TOKEN OPTIMIZER' -ForegroundColor Cyan
    Write-Host '  Route: Claude Code CLI + rtk proxy (60-90% token reduction on Bash calls)' -ForegroundColor DarkGray
    Write-Host '  Ref:   github.com/rtk-ai/rtk' -ForegroundColor DarkGray
    Write-Host ''

    # ---- Step 1: ensure rtk present ------------------------------------

    Write-Host '  [1/4] Ensuring rtk is installed...' -ForegroundColor Cyan
    $rtkCmd = Get-Command rtk -ErrorAction SilentlyContinue
    if ($rtkCmd) {
        $verOut = & rtk --version 2>&1 | Out-String
        Write-Host ('  [ok]     rtk present -- {0}' -f $verOut.Trim()) -ForegroundColor Green
    } else {
        Write-Host '  [info]   rtk not found in PATH -- installing...' -ForegroundColor DarkYellow

        $installed = $false
        switch ($Method) {
            'scoop'  { $installed = Install-RtkViaScoop -DryRun:$DryRun }
            'cargo'  { $installed = Install-RtkViaCargo -DryRun:$DryRun }
            'binary' { $installed = Install-RtkBinary -DryRun:$DryRun }
            'auto' {
                # Prefer binary (fast, no toolchain required), fall back to cargo.
                $installed = Install-RtkBinary -DryRun:$DryRun
                if (-not $installed) {
                    Write-Host '  [info]   Binary install failed -- trying cargo...' -ForegroundColor DarkYellow
                    $installed = Install-RtkViaCargo -DryRun:$DryRun
                }
            }
        }

        if (-not $installed) {
            Write-Host ''
            Write-Host '  [error]  Could not install rtk. Manual install:' -ForegroundColor Red
            Write-Host '           https://github.com/rtk-ai/rtk/releases' -ForegroundColor DarkGray
            Write-Host ''
            return
        }

        # Re-check PATH after install (new binary may not be picked up in current session)
        if (-not (Get-Command rtk -ErrorAction SilentlyContinue)) {
            $localBin = Join-Path $HOME '.local\bin'
            if (Test-Path (Join-Path $localBin 'rtk.exe')) {
                $env:PATH = $localBin + ';' + $env:PATH
                Write-Host ('  [info]   Added {0} to current-session PATH' -f $localBin) -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ''

    # ---- Step 2: register rtk hook -------------------------------------

    Write-Host '  [2/4] Registering rtk PreToolUse hook for Claude Code...' -ForegroundColor Cyan
    if (-not (Get-Command rtk -ErrorAction SilentlyContinue)) {
        Write-Host '  [warn]   rtk still not on PATH -- skipping hook registration.' -ForegroundColor DarkYellow
        Write-Host '           Restart your shell and rerun: 8sync gsd token-save' -ForegroundColor DarkGray
    } else {
        $null = Invoke-RtkInitGlobal -DryRun:$DryRun
    }
    Write-Host ''

    # ---- Step 3: reaffirm auth.json ------------------------------------

    Write-Host '  [3/4] Verifying auth.json routing -> claude-code CLI...' -ForegroundColor Cyan
    if ($SkipAuthFix) {
        Write-Host '  [skip]   --skip-auth-fix passed; not touching auth.json' -ForegroundColor DarkGray
    } else {
        # Reuse the existing fixer -- idempotent, no-ops if already correct.
        Invoke-GsdAuthFix -DryRun:$DryRun
    }
    Write-Host ''

    # ---- Step 4: write token-save env vars to settings.json -----------

    Write-Host '  [4/4] Writing token-save env vars to ~/.claude/settings.json...' -ForegroundColor Cyan
    if ($SkipEnv) {
        Write-Host '  [skip]   --skip-env passed; not touching settings.json' -ForegroundColor DarkGray
    } else {
        Set-ClaudeCodeTokenSaveEnv -DryRun:$DryRun -IncludeDisableCaching:$IncludeDisableCaching
    }
    Write-Host ''

    # ---- done ----------------------------------------------------------

    Write-Host '  Next steps:' -ForegroundColor Cyan
    Write-Host '    1. Restart your Claude Code / GSD session so the hook loads.' -ForegroundColor White
    Write-Host '    2. In GSD, run a command like `git status` -- it should be' -ForegroundColor White
    Write-Host '       transparently rewritten to `rtk git status` and return compressed output.' -ForegroundColor White
    Write-Host '    3. Run `rtk gain` to see cumulative token savings.' -ForegroundColor White
    Write-Host ''
    Write-Host '  Caveat: the hook only fires on Claude Code Bash tool calls.' -ForegroundColor DarkGray
    Write-Host '  Built-in Read/Grep/Glob tools bypass it. Prefer shell commands' -ForegroundColor DarkGray
    Write-Host '  (cat, rg, find) or call `rtk read|grep|find` explicitly.' -ForegroundColor DarkGray
    Write-Host ''
}

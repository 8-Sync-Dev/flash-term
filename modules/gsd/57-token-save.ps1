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

function Get-RtkForgeShimsDir {
    # Returns the dedicated shims directory for Forge rtk wrappers.
    return Join-Path $HOME '.local\bin\rtk-forge-shims'
}

function Install-RtkForgeShims {
    # Creates .bat shim files in ~/.local/bin/rtk-forge-shims/ that wrap
    # common dev commands through rtk. When this dir is prepended to PATH,
    # any subprocess Forge spawns (cmd.exe, pwsh, etc.) will transparently
    # call `rtk git`, `rtk ls`, etc. instead of the real binaries.
    #
    # Uses the %~n0 trick so one shim template covers all commands -- each
    # .bat file is identical; the filename is passed as the subcommand to rtk.
    #
    # Special case: `cat` -> `rtk read` (rtk's read subcommand compresses files).
    param([switch]$DryRun, [switch]$Remove)

    $shimsDir = Get-RtkForgeShimsDir

    # Commands to shim: (bat-name, rtk-subcommand)
    $shims = @(
        @('git',    'git'),
        @('ls',     'ls'),
        @('cat',    'read'),
        @('grep',   'grep'),
        @('find',   'find'),
        @('cargo',  'cargo'),
        @('npm',    'npm'),
        @('pytest', 'pytest'),
        @('docker', 'docker')
    )

    if ($Remove) {
        if (-not (Test-Path $shimsDir)) {
            Write-Host '  [skip]   Forge rtk shims dir not found (nothing to remove)' -ForegroundColor DarkGray
            return
        }
        if ($DryRun) {
            Write-Host ('  [dry-run] Would remove shims dir: {0}' -f $shimsDir) -ForegroundColor Yellow
            return
        }
        Remove-Item $shimsDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ('  [ok]     Removed rtk shims dir: {0}' -f $shimsDir) -ForegroundColor Green
        return
    }

    if ($DryRun) {
        Write-Host ('  [dry-run] Would create shims in: {0}' -f $shimsDir) -ForegroundColor Yellow
        foreach ($s in $shims) {
            Write-Host ('    + {0}.bat -> rtk {1} %*' -f $s[0], $s[1]) -ForegroundColor Yellow
        }
        return
    }

    if (-not (Test-Path $shimsDir)) {
        $null = New-Item -Path $shimsDir -ItemType Directory -Force
    }

    foreach ($s in $shims) {
        $name = $s[0]; $sub = $s[1]
        $batPath = Join-Path $shimsDir ($name + '.bat')
        $content = "@echo off`r`nrtk $sub %*`r`n"
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($batPath, $content, $utf8NoBom)
    }
    Write-Host ('  [ok]     Created {0} shims in {1}' -f $shims.Count, $shimsDir) -ForegroundColor Green
    Write-Host ('           git ls cat grep find cargo npm pytest docker -> rtk ...') -ForegroundColor DarkGray

    # Prepend to current session PATH
    $pathDirs = $env:PATH -split ';'
    $alreadyFirst = $pathDirs.Count -gt 0 -and ($pathDirs[0] -ieq $shimsDir)
    if (-not $alreadyFirst) {
        $env:PATH = $shimsDir + ';' + (($pathDirs | Where-Object { $_ -ine $shimsDir } | Where-Object { $_ -ne '' }) -join ';')
        Write-Host ('  [ok]     Prepended shims dir to current-session PATH') -ForegroundColor Green
    }

    # Persist to user PATH via setx
    try {
        $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        $userParts = $userPath -split ';' | Where-Object { $_ -ine $shimsDir -and $_ -ne '' }
        $newUserPath = $shimsDir + ';' + ($userParts -join ';')
        [System.Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
        Write-Host ('  [ok]     Persisted shims dir to user PATH (new shells will inherit)') -ForegroundColor Green
    } catch {
        Write-Host ('  [warn]   Could not persist to user PATH: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        Write-Host ('           Manually run: setx PATH "%PATH%;{0}"' -f $shimsDir) -ForegroundColor DarkGray
    }

    Write-Host '' 
    Write-Host '  [!] IMPORTANT: shims intercept git/ls/cat/grep for ALL processes using' -ForegroundColor DarkYellow
    Write-Host '      this PATH, not just Forge. rtk is transparent for most uses but:' -ForegroundColor DarkYellow
    Write-Host '      - `cat` is remapped to `rtk read` (may differ for binary files)' -ForegroundColor DarkYellow
    Write-Host ('      - Remove shims: 8sync gsd token-save --forge-shims --remove') -ForegroundColor DarkYellow
}

function Set-ForgeTomlTokenSave {
    # Tune ~/.forge/.forge.toml output-limit keys to reduce tokens consumed by
    # Forge's native Read / Search / Stdout tools (no hook required -- these are
    # hard caps Forge enforces before sending to the LLM).
    #
    # Only the token-impacting keys are changed; all other keys are preserved.
    param([switch]$DryRun, [switch]$Remove)

    $tomlPath = Join-Path $HOME '.forge\.forge.toml'

    if (-not (Test-Path $tomlPath)) {
        Write-Host '  [skip]   ~/.forge/.forge.toml not found' -ForegroundColor DarkGray
        return
    }

    # Optimized values (conservative -- still usable, just smaller)
    # Original defaults in comments.
    $targets = [ordered]@{
        max_read_lines            = 500    # was 2000 -- native Read tool: 500 lines max
        max_search_lines          = 200    # was 1000 -- search result lines
        max_search_result_bytes   = 3072   # was 10240 -- search result bytes (~3KB)
        max_stdout_prefix_lines   = 50     # was 100
        max_stdout_suffix_lines   = 50     # was 100
        max_stdout_line_chars     = 300    # was 500
        max_line_chars            = 1000   # was 2000
        max_fetch_chars           = 20000  # was 50000 -- web fetch
    }

    $originals = [ordered]@{
        max_read_lines            = 2000
        max_search_lines          = 1000
        max_search_result_bytes   = 10240
        max_stdout_prefix_lines   = 100
        max_stdout_suffix_lines   = 100
        max_stdout_line_chars     = 500
        max_line_chars            = 2000
        max_fetch_chars           = 50000
    }

    $applyValues = if ($Remove) { $originals } else { $targets }
    $action      = if ($Remove) { 'Restoring' } else { 'Tuning' }

    $content = [System.IO.File]::ReadAllText($tomlPath)

    if ($DryRun) {
        Write-Host ("  [dry-run] Would update ~/.forge/.forge.toml ({0} keys):" -f $applyValues.Count) -ForegroundColor Yellow
        foreach ($k in $applyValues.Keys) {
            $match = [regex]::Match($content, "(?m)^$k\s*=\s*(.+)$")
            $cur = if ($match.Success) { $match.Groups[1].Value.Trim() } else { '(not set)' }
            Write-Host ("    {0,-32} {1} -> {2}" -f $k, $cur, $applyValues[$k]) -ForegroundColor Yellow
        }
        return
    }

    # Backup
    $backup = $tomlPath + '.bak-tokensave-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    try { Copy-Item $tomlPath $backup -Force; Write-Host ('  [ok]     Backed up .forge.toml -> {0}' -f (Split-Path $backup -Leaf)) -ForegroundColor DarkGray } catch {}

    $updated = $content
    $changed = @()
    foreach ($k in $applyValues.Keys) {
        $val = $applyValues[$k]
        $pattern = "(?m)^($k\s*=\s*)(.+)$"
        if ([regex]::IsMatch($updated, $pattern)) {
            $updated = [regex]::Replace($updated, $pattern, "`${1}$val")
            $changed += $k
        }
        # If key not present, we skip (safer than injecting into unknown TOML structure)
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tomlPath, $updated, $utf8NoBom)

    Write-Host ("  [ok]     {0} {1} keys in .forge.toml" -f $action, $changed.Count) -ForegroundColor Green
    foreach ($k in $changed) {
        Write-Host ("    {0,-32} = {1}" -f $k, $applyValues[$k]) -ForegroundColor DarkGray
    }
}

function Install-ForgeRtkSkill {
    # Write a global Forge skill file that instructs Forge's AI to prefer rtk
    # commands over native tools. Forge reads .md files from ~/.forge/skills/
    # (global) and .forge/skills/ (project) at session start, injecting them
    # into the system context.
    param([switch]$DryRun, [switch]$Remove)

    $skillsDir = Join-Path $HOME '.forge\skills'
    $skillFile = Join-Path $skillsDir 'rtk-token-save.md'

    if ($Remove) {
        if (Test-Path $skillFile) {
            if ($DryRun) { Write-Host ('  [dry-run] Would remove {0}' -f $skillFile) -ForegroundColor Yellow; return }
            Remove-Item $skillFile -Force
            Write-Host ('  [ok]     Removed Forge rtk skill file') -ForegroundColor Green
        } else {
            Write-Host '  [skip]   Forge rtk skill file not found' -ForegroundColor DarkGray
        }
        return
    }

    $skillContent = @'
# RTK Token Optimizer (managed by 8sync gsd token-save --forge-full)

You have rtk (Token Killer) available. Use it to compress tool output and save tokens.

## Command preferences

When running shell commands, ALWAYS prefer the rtk variant:

| Instead of | Use |
|---|---|
| `git status` / `git log` / `git diff` | `rtk git status` / `rtk git log` / `rtk diff` |
| `cat file` | `rtk read file` |
| `ls` / `ls -la` | `rtk ls` / `rtk ls -la` |
| `grep pattern dir` | `rtk grep pattern dir` |
| `find . -name ...` | `rtk find . -name ...` |
| `cargo test` / `cargo build` | `rtk cargo test` / `rtk cargo build` |
| `npm test` / `npm run build` | `rtk npm test` / `rtk npm run build` |
| `pytest` | `rtk pytest` |
| `docker ps` / `docker logs` | `rtk docker ps` / `rtk docker logs` |
| `tsc --noEmit` | `rtk tsc --noEmit` |
| `npx eslint` | `rtk lint` |

## When reading files via shell

Use `rtk read <file>` instead of `cat <file>`. rtk read applies intelligent
line-range extraction and deduplication before returning content.

## Checking savings

Run `rtk gain` at any time to see cumulative token savings.
'@

    if ($DryRun) {
        Write-Host ('  [dry-run] Would write Forge rtk skill: {0}' -f $skillFile) -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $skillsDir)) {
        $null = New-Item -Path $skillsDir -ItemType Directory -Force
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($skillFile, $skillContent, $utf8NoBom)
    Write-Host ('  [ok]     Wrote Forge rtk skill -> ~/.forge/skills/rtk-token-save.md') -ForegroundColor Green
    Write-Host '  [info]   Forge loads skills from ~/.forge/skills/ at session start.' -ForegroundColor DarkGray
}

function Invoke-GsdTokenSave {
    param(
        [switch]$DryRun,
        [switch]$SkipAuthFix,
        [switch]$SkipEnv,
        [switch]$IncludeDisableCaching,
        [switch]$ForgeShims,
        [switch]$ForgeShimsRemove,
        [switch]$ForgeFull,
        [ValidateSet('auto', 'scoop', 'cargo', 'binary')]
        [string]$Method = 'auto',
        [int]$CompactPct = 70
    )

    # --forge-full implies --forge-shims + toml tuning + skill file
    if ($ForgeFull) { $ForgeShims = $true }

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

    Write-Host "  [compact] autoCompact: smart + threshold: ${CompactPct}% + removing DISABLE_1M_CONTEXT..." -ForegroundColor Cyan
    $compactResult = Ensure-GsdClaudeGlobalSettings -DryRun:$DryRun -CompactPct $CompactPct
    if ($compactResult.Changed) {
        Write-Host "  [ok]     Applied: smart compact @ ${CompactPct}%, 1M context unlocked" -ForegroundColor Green
    } else {
        Write-Host "  [ok]     Already correct (smart @ ${CompactPct}%, 1M unlocked)" -ForegroundColor Green
    }
    Write-Host '  [warn]   CLAUDE_AUTOCOMPACT_PCT_OVERRIDE has known upstream bugs - may not be honored' -ForegroundColor DarkYellow
    Write-Host ''

    # ---- Step 5: forge coverage (shims + toml + skill) ----------------

    Write-Host '  [5/5] Forge rtk coverage...' -ForegroundColor Cyan
    if ($ForgeFull) {
        Write-Host '  [info]   --forge-full: applying all 3 layers for maximum Forge coverage.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  [5a] .bat PATH shims (shell subprocess calls)' -ForegroundColor Cyan
        Install-RtkForgeShims -DryRun:$DryRun
        Write-Host ''
        Write-Host '  [5b] .forge.toml output limits (native Read/Search tools)' -ForegroundColor Cyan
        Set-ForgeTomlTokenSave -DryRun:$DryRun
        Write-Host ''
        Write-Host '  [5c] Forge global skill file (AI instruction layer)' -ForegroundColor Cyan
        Install-ForgeRtkSkill -DryRun:$DryRun
    } elseif ($ForgeShims -or $ForgeShimsRemove) {
        if ($ForgeShimsRemove) {
            Write-Host '  [info]   Removing shims...' -ForegroundColor DarkGray
            Install-RtkForgeShims -DryRun:$DryRun -Remove
        } else {
            Write-Host '  [info]   Creating .bat shims in PATH for Forge (and any Windows shell).' -ForegroundColor DarkGray
            Install-RtkForgeShims -DryRun:$DryRun
        }
    } else {
        Write-Host '  [skip]   Pass --forge-full for maximum Forge coverage (shims + toml + skill).' -ForegroundColor DarkGray
        Write-Host '           Or --forge-shims for shell-only shims.' -ForegroundColor DarkGray
        Write-Host '           (Forge does not read ~/.claude/settings.json -- hook has no effect.)' -ForegroundColor DarkGray
    }
    Write-Host ''

    # ---- done ----------------------------------------------------------

    Write-Host '  Next steps:' -ForegroundColor Cyan
    Write-Host '    1. Restart your Claude Code / GSD session so the hook loads.' -ForegroundColor White
    Write-Host '    2. In GSD, run a command like `git status` -- rtk compresses output.' -ForegroundColor White
    Write-Host '    3. Run `rtk gain` to see cumulative token savings.' -ForegroundColor White
    if ($ForgeFull) {
        Write-Host '    4. Restart Forge -- new PATH + tuned limits + skill file all active.' -ForegroundColor White
        Write-Host '       Forge will now: (a) use rtk shims for shell calls, (b) cap native' -ForegroundColor White
        Write-Host '       Read/Search output at smaller limits, (c) have AI prefer rtk commands.' -ForegroundColor White
    } elseif ($ForgeShims) {
        Write-Host '    4. Restart Forge -- it will inherit the new PATH and use rtk shims.' -ForegroundColor White
    }
    Write-Host ''
    Write-Host '  Caveat: Claude Code hook fires on Bash tool calls only.' -ForegroundColor DarkGray
    Write-Host '  Forge native Read/Glob tools bypass the hook (covered by --forge-full toml tuning).' -ForegroundColor DarkGray
    Write-Host ''
}

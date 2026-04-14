# =============================================================================
# 8sync gsd -- auto setup and command dispatch
# =============================================================================

function Invoke-GsdAutoSetup {
    param([switch]$DryRun)

    $agentDir = Resolve-GsdAgentDir
    $authPath = Join-Path $agentDir 'auth.json'
    $envFile = Join-Path $agentDir '.env'

    Write-Host ''
    Write-Host '  [gsd] Auto-detecting valid providers...' -ForegroundColor Cyan
    Write-Host ''

    $validOAuth = @{}
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $auth.PSObject.Properties | ForEach-Object {
                if ($_.Value.type -ne 'oauth') { return }
                $exp = $_.Value.expires
                $valid = (-not $exp) -or (([long]$exp - $now) -gt 0)
                if ($valid) { $validOAuth[$_.Name] = $true }
                $status = if ($valid) { 'VALID' } else { 'expired' }
                $mins = if ($exp) { "~{0}m" -f [math]::Round(([long]$exp - $now) / 60000) } else { '∞' }
                $color = if ($valid) { 'Green' } else { 'DarkGray' }
                Write-Host ("    oauth  {0,-26} {1} {2}" -f $_.Name, $status, $mins) -ForegroundColor $color
            }
        } catch {
            Write-Host '  [warn] auth.json parse failed' -ForegroundColor DarkYellow
        }
    }

    $envFileLines = @()
    if (Test-Path $envFile) {
        $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    $validKeys = @{}
    foreach ($provider in $script:GsdProviderKeys.Keys) {
        $varName = $script:GsdProviderKeys[$provider]
        $value = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) { $value = [System.Environment]::GetEnvironmentVariable($varName, 'User') }
        if ([string]::IsNullOrWhiteSpace($value)) {
            $line = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=\s*(.+)') } | Select-Object -First 1
            if ($line -match '=\s*(.+)$') { $value = $matches[1].Trim() }
        }
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $validKeys[$provider] = $true
        Write-Host ("    key    {0,-26} SET" -f "$provider ($varName)") -ForegroundColor Green
    }

    $selected = [System.Collections.Generic.List[string]]::new()
    if ($validOAuth['anthropic']) { $selected.Add('anthropic') }
    if ($validOAuth['github-copilot']) { $selected.Add('github-copilot') }
    if ($validOAuth['google-gemini-cli']) { $selected.Add('google-gemini-cli') }
    if ($validOAuth['openai-codex']) { $selected.Add('openai-codex') }
    if ($validKeys['zai']) { $selected.Add('zai') }
    if ($validKeys['groq']) { $selected.Add('groq') }
    if ($validKeys['kimi-coding']) { $selected.Add('kimi-coding') }

    Write-Host ''
    if ($selected.Count -eq 0) {
        Write-Host '  [error] No valid providers detected. Login with /login or set keys with 8sync gsd key.' -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host '  Active providers:' -ForegroundColor DarkGray
    foreach ($provider in $selected) {
        Write-Host ("    + {0}" -f $provider) -ForegroundColor White
    }
    Write-Host ''

    $yaml = Build-GsdModelsYaml -Selected $selected.ToArray()
    if (-not $yaml) {
        Write-Host '  [error] Could not generate model routing from detected providers.' -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host '  Generated routing (top lines):' -ForegroundColor Cyan
    $yaml -split "`n" | Select-Object -First 12 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
    Write-Host '    ...' -ForegroundColor DarkGray
    Write-Host ''

    $destPath = Join-Path (Resolve-GsdHome) 'PREFERENCES.md'
    $ok = Write-GsdPreferencesModels -ModelsYaml $yaml -DestPath $destPath -DryRun:$DryRun
    if ($ok -and -not $DryRun) {
        Invoke-GsdRuntimePatch
        Write-Host ("  [ok] Written to {0}" -f $destPath) -ForegroundColor Green
        Write-Host ''
        Write-Host '  Verify: /gsd prefs   /model' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Invoke-GsdVersionCheck {
    param([switch]$DryRun)

    $pinned = $script:GsdPinnedVersion
    Write-Host ("  [gsd] Checking gsd-pi version (pinned: {0})..." -f $pinned) -ForegroundColor Cyan

    $currentVersion = ''
    if (Get-Command 'gsd' -ErrorAction SilentlyContinue) {
        try {
            $currentVersion = (& gsd --version 2>$null).Trim()
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($currentVersion)) {
        Write-Host '  [warn]    gsd command not found or --version failed' -ForegroundColor DarkYellow
        return $false
    }

    if ($currentVersion -eq $pinned) {
        Write-Host ("  [ok]      gsd-pi version {0} matches pinned" -f $currentVersion) -ForegroundColor Green
        return $true
    }

    try {
        $cur = [System.Version]::new($currentVersion)
        $pin = [System.Version]::new($pinned)

        if ($cur -gt $pin) {
            Write-Host ("  [warn]    gsd-pi {0} is NEWER than pinned {1} -- downgrading for compatibility" -f $currentVersion, $pinned) -ForegroundColor DarkYellow
            Invoke-GsdPackageRefresh -DryRun:$DryRun
            return $true
        } elseif ($cur -lt $pin) {
            Write-Host ("  [warn]    gsd-pi {0} is OLDER than pinned {1} -- upgrading" -f $currentVersion, $pinned) -ForegroundColor DarkYellow
            Invoke-GsdPackageRefresh -DryRun:$DryRun
            return $true
        }
    } catch {
        Write-Host ("  [warn]    Cannot parse version '{0}' -- skipping version check" -f $currentVersion) -ForegroundColor DarkYellow
    }

    return $true
}

function Invoke-GsdFix {
    param(
        [switch]$DryRun,
        [switch]$Stable,
        [switch]$Force,
        [switch]$Refresh
    )

    Write-Host ''
    Write-Host '  [gsd] Running unified repair...' -ForegroundColor Cyan
    if ($Stable) {
        Write-Host '  [stable] Applying stable GSD patch profile' -ForegroundColor Cyan
    }

    # 1) Version check -- auto sync to pinned version
    $null = Invoke-GsdVersionCheck -DryRun:$DryRun

    if ($Refresh) {
        Invoke-GsdPackageRefresh -DryRun:$DryRun
    }

    # 2) Bridge repairs
    Invoke-GsdNodeModulesBridgeFix -DryRun:$DryRun
    Invoke-GsdResourceLoaderFix -DryRun:$DryRun
    Invoke-GsdAutoExtensionLoaderPatch -DryRun:$DryRun
    Invoke-GsdRuntimePatch -DryRun:$DryRun -Stable:$Stable

    # 3) DB repair for current project
    Invoke-GsdDbRepair -DryRun:$DryRun -Force:$Force -ProjectPath $PWD.Path

    # 4) Scan ALL projects with .gsd/ on all drives -- works on any machine
    Write-Host '  [gsd] Scanning all drives for projects with .gsd/ folders...' -ForegroundColor Cyan

    $projectPaths = [System.Collections.Generic.List[string]]::new()
    $currentPath = $PWD.Path
    if (Test-Path (Join-Path $currentPath '.gsd')) { $projectPaths.Add($currentPath) }

    # Gather scan roots: every fixed-drive root + user home
    $scanRoots = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($env:GSD_WORKSPACE_ROOT)) {
        # Explicit override -- respect it
        $env:GSD_WORKSPACE_ROOT -split ';' | Where-Object { Test-Path $_ } | ForEach-Object { $scanRoots.Add($_) }
    } else {
        # Auto: scan every fixed drive root
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.Free -and (Test-Path $_.Root) } |
            ForEach-Object { $scanRoots.Add($_.Root) }

        # Also home dir in case drives missed it
        if ($scanRoots -notcontains $HOME -and (Test-Path $HOME)) { $scanRoots.Add($HOME) }
    }

    foreach ($root in $scanRoots) {
        try {
            Get-ChildItem -Path $root -Directory -Recurse -Depth 5 -Filter '.gsd' -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $fp = $_.FullName
                    $fp -notmatch '[\\/]node_modules[\\/]' -and
                    $fp -notmatch '[\\/]\.npm[\\/]' -and
                    $fp -notmatch '[\\/]scoop[\\/]' -and
                    $fp -notmatch '[\\/]AppData[\\/]' -and
                    $fp -notmatch '[\\/]\.cache[\\/]' -and
                    $fp -ne (Join-Path $HOME '.gsd')           # skip global ~/.gsd (not a project)
                } | ForEach-Object {
                    $projPath = $_.Parent.FullName
                    if (-not $projectPaths.Contains($projPath)) { $projectPaths.Add($projPath) }
                }
        } catch {}
    }

    if ($projectPaths.Count -le 1) {
        Write-Host '  [ok]      No other projects with .gsd/ found' -ForegroundColor Green
    } else {
        Write-Host ("  [gsd] Found {0} project(s) -- cleaning stale sidecars:" -f $projectPaths.Count) -ForegroundColor Cyan
        foreach ($p in $projectPaths) {
            if ($p -eq $currentPath) { continue }   # already handled above

            $dbPath   = Join-Path $p '.gsd\gsd.db'
            $walPath  = "$dbPath-wal"
            $shmPath  = "$dbPath-shm"
            $lockPath = Join-Path $p '.gsd\auto.lock'

            $issues = @()
            if (Test-Path $walPath)  { $issues += 'wal' }
            if (Test-Path $shmPath)  { $issues += 'shm' }
            if (Test-Path $lockPath) { $issues += 'lock' }

            $projName = Split-Path $p -Leaf
            if ($issues.Count -eq 0) {
                Write-Host ("    {0,-40} [clean]" -f $projName) -ForegroundColor Green
            } else {
                $tag = '[stale: {0}]' -f ($issues -join ',')
                if ($DryRun) {
                    Write-Host ("    {0,-40} {1} -> [dry-run] would clean" -f $projName, $tag) -ForegroundColor DarkYellow
                } else {
                    if (Test-Path $walPath)  { Remove-Item -LiteralPath $walPath  -Force -ErrorAction SilentlyContinue }
                    if (Test-Path $shmPath)  { Remove-Item -LiteralPath $shmPath  -Force -ErrorAction SilentlyContinue }
                    if (Test-Path $lockPath) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
                    Write-Host ("    {0,-40} {1} -> cleaned" -f $projName, $tag) -ForegroundColor Green
                }
            }
        }
    }

    Write-Host '  [ok]      Unified fix finished' -ForegroundColor Green
    Write-Host ''
}

function Invoke-GsdCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun   = $Rest -contains '--dry-run'
    $pickMode = $Rest -contains '--pick'
    $autoMode = $Rest -contains '--auto'
    $stable   = $Rest -contains '--stable'
    $force    = $Rest -contains '--force'
    $balance  = $Rest -contains '--balance'   # alias for --tier=balanced (backward compat)

    $planArg = ''
    $planIdx = [Array]::IndexOf($Rest, '--plan')
    if ($planIdx -ge 0) {
        if ($planIdx + 1 -lt $Rest.Count -and $Rest[$planIdx + 1] -notlike '--*') {
            $planArg = $Rest[$planIdx + 1]
        } else {
            Show-GsdPlans; return
        }
    }

    # --model accepts both "--model=claude+codex" and "--model claude+codex"
    $modelArg = ''
    $modelEq  = $Rest | Where-Object { $_ -like '--model=*' } | Select-Object -First 1
    if ($modelEq) {
        $modelArg = $modelEq -replace '^--model=', ''
    } else {
        $modelIdx = [Array]::IndexOf($Rest, '--model')
        if ($modelIdx -ge 0) {
            if ($modelIdx + 1 -lt $Rest.Count -and $Rest[$modelIdx + 1] -notlike '--*') {
                $modelArg = $Rest[$modelIdx + 1]
            } else {
                Show-GsdPlans; return
            }
        }
    }

    # --only accepts both "--only=claude" and "--only claude"
    $onlyArg = ''
    $onlyEq  = $Rest | Where-Object { $_ -like '--only=*' } | Select-Object -First 1
    if ($onlyEq) {
        $onlyArg = $onlyEq -replace '^--only=', ''
    } else {
        $onlyIdx = [Array]::IndexOf($Rest, '--only')
        if ($onlyIdx -ge 0 -and $onlyIdx + 1 -lt $Rest.Count -and $Rest[$onlyIdx + 1] -notlike '--*') {
            $onlyArg = $Rest[$onlyIdx + 1]
        }
    }

    # --tier=light|balanced|heavy  (--balance is alias for balanced)
    $tierArg = 'balanced'
    $tierEq  = $Rest | Where-Object { $_ -like '--tier=*' } | Select-Object -First 1
    if ($tierEq) {
        $tierArg = ($tierEq -replace '^--tier=', '').ToLowerInvariant()
        if ($tierArg -notin @('light','balanced','heavy')) {
            Write-Host ("  [error] Unknown tier '{0}'. Accepted: light balanced heavy" -f $tierArg) -ForegroundColor Red
            return
        }
    } elseif ($balance) {
        $tierArg = 'balanced'
    } else {
        $tierIdx = [Array]::IndexOf($Rest, '--tier')
        if ($tierIdx -ge 0 -and $tierIdx + 1 -lt $Rest.Count -and $Rest[$tierIdx + 1] -notlike '--*') {
            $tierArg = $Rest[$tierIdx + 1].ToLowerInvariant()
        }
    }

    # --planning=<provider/model>  pin primary for planning/research
    $planningPin = ''
    $planningEq  = $Rest | Where-Object { $_ -like '--planning=*' } | Select-Object -First 1
    if ($planningEq) { $planningPin = $planningEq -replace '^--planning=', '' }

    # --exec=<provider/model>  pin primary for execution
    $execPin = ''
    $execEq  = $Rest | Where-Object { $_ -like '--exec=*' } | Select-Object -First 1
    if ($execEq) { $execPin = $execEq -replace '^--exec=', '' }

    # --use-model=opus+sonnet+haiku  pick which Claude models for claude-max
    $useModelArg = ''
    $useModelEq  = $Rest | Where-Object { $_ -like '--use-model=*' } | Select-Object -First 1
    if ($useModelEq) {
        $useModelArg = ($useModelEq -replace '^--use-model=', '').ToLowerInvariant()
    } else {
        $useModelIdx = [Array]::IndexOf($Rest, '--use-model')
        if ($useModelIdx -ge 0 -and $useModelIdx + 1 -lt $Rest.Count -and $Rest[$useModelIdx + 1] -notlike '--*') {
            $useModelArg = $Rest[$useModelIdx + 1].ToLowerInvariant()
        }
    }

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { 'setup' }
    switch ($sub) {
        'setup' {
            if ($autoMode) {
                Invoke-GsdAutoSetup -DryRun:$dryRun
            } elseif ($pickMode) {
                Invoke-GsdPlanPicker -DryRun:$dryRun
            } elseif (-not [string]::IsNullOrWhiteSpace($modelArg)) {
                Invoke-GsdSetupFromModel -DryRun:$dryRun -Model $modelArg -Tier $tierArg -Only $onlyArg -PlanningPin $planningPin -ExecPin $execPin
            } elseif (-not [string]::IsNullOrWhiteSpace($planArg)) {
                if ($planArg -eq 'claude-max' -and -not [string]::IsNullOrWhiteSpace($useModelArg)) {
                    Invoke-GsdClaudeMaxSetup -DryRun:$dryRun -UseModel $useModelArg -Tier $tierArg
                } else {
                    Invoke-GsdSetup -DryRun:$dryRun -Plan $planArg
                }
            } else {
                # No flags -- launch interactive wizard
                Invoke-GsdSetupWizard -DryRun:$dryRun
            }
        }
        'status' { Invoke-GsdStatus }
        'fix'    { Invoke-GsdFix -DryRun:$dryRun -Stable:$stable -Force:$force }
        'fix-db' { Invoke-GsdFix -DryRun:$dryRun -Force:$force | Out-Null }
        'key'    { Invoke-GsdKey -Provider ($Rest | Select-Object -Skip 1 -First 1) -Key ($Rest | Select-Object -Skip 2 -First 1) }
        'keys'   { Show-GsdKeys }
        'add' {
            $addSub = if ($Rest.Count -gt 1) { $Rest[1].ToLowerInvariant() } else { '' }
            switch ($addSub) {
                'gguf'  { Invoke-GsdAddGguf -Rest ($Rest | Select-Object -Skip 2) }
                default { Write-Host '  Usage: 8sync gsd add gguf [--port N] [--name <id>] [--dry-run]' -ForegroundColor DarkGray }
            }
        }
        'connect' {
            $conSub = if ($Rest.Count -gt 1) { $Rest[1].ToLowerInvariant() } else { '' }
            switch ($conSub) {
                'gguf'  { Invoke-GsdAddGguf -Rest ($Rest | Select-Object -Skip 2) }
                default { Write-Host '  Usage: 8sync gsd connect gguf [--port N] [--name <id>] [--dry-run]' -ForegroundColor DarkGray }
            }
        }
        'remove' {
            $remSub = if ($Rest.Count -gt 1) { $Rest[1].ToLowerInvariant() } else { '' }
            switch ($remSub) {
                'gguf'  { Invoke-GsdRemoveGguf -Rest ($Rest | Select-Object -Skip 2) }
                default { Write-Host '  Usage: 8sync gsd remove gguf [--name <id>]' -ForegroundColor DarkGray }
            }
        }
        'help'   { Show-GsdHelp }
        default  { Show-GsdHelp }
    }
}

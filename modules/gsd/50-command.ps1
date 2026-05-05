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
        Write-Host ("  [ok] Written to {0}" -f $destPath) -ForegroundColor Green
        Write-Host ''
        Write-Host '  Verify: /gsd prefs   /model' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Invoke-GsdVersionCheck {
    param(
        [switch]$DryRun,
        [switch]$AllowGlobal
    )

    $pinned = $script:GsdPinnedVersion
    Write-Host ("  [gsd] Checking gsd-pi version (pinned: {0})..." -f $pinned) -ForegroundColor Cyan

    $currentVersion = ''
    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot -and (Test-Path (Join-Path $localRoot 'package.json'))) {
        try {
            $pkg = Get-Content (Join-Path $localRoot 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $currentVersion = [string]$pkg.version
            Write-Host ("  [local]   using project runtime: {0}" -f $localRoot) -ForegroundColor DarkGray
        } catch {}
    } elseif (Get-Command 'gsd' -ErrorAction SilentlyContinue) {
        try {
            $currentVersion = (& gsd --version 2>$null).Trim()
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($currentVersion)) {
        Write-Host '  [warn]    local runtime and gsd --version are both unavailable' -ForegroundColor DarkYellow
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
            Write-Host ("  [warn]    gsd-pi {0} is NEWER than pinned {1} -- refreshing preferred runtime for compatibility" -f $currentVersion, $pinned) -ForegroundColor DarkYellow
            Invoke-GsdPackageRefresh -DryRun:$DryRun -AllowGlobal:$AllowGlobal
            return $true
        } elseif ($cur -lt $pin) {
            Write-Host ("  [warn]    gsd-pi {0} is OLDER than pinned {1} -- refreshing preferred runtime" -f $currentVersion, $pinned) -ForegroundColor DarkYellow
            Invoke-GsdPackageRefresh -DryRun:$DryRun -AllowGlobal:$AllowGlobal
            return $true
        }
    } catch {
        Write-Host ("  [warn]    Cannot parse version '{0}' -- skipping version check" -f $currentVersion) -ForegroundColor DarkYellow
    }

    return $true
}

function Invoke-GsdCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun   = $Rest -contains '--dry-run'
    $pickMode = $Rest -contains '--pick'
    $autoMode = $Rest -contains '--auto'
    $fullMode = $Rest -contains '--full'
    $force    = $Rest -contains '--force'
    $balance  = $Rest -contains '--balance'   # alias for --tier=balanced (backward compat)
    $allowGlobal = $Rest -contains '--allow-global'

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
        { $_ -eq 'bootstrap' -or ($_ -eq 'setup' -and $fullMode) } {
            Write-Host ''
            Write-Host '  [gsd] Full bootstrap: token-save + auth-fix + max-skill (karpathy global)' -ForegroundColor Cyan
            Write-Host ''
            Invoke-GsdTokenSave -DryRun:$dryRun
            Write-Host ''
            Invoke-AgentMaxSkill -DryRun:$dryRun -SkipTokenSave
            Write-Host ''
            Write-Host '  [done] GSD bootstrap complete.' -ForegroundColor Green
            Write-Host ''
        }
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
        'local'  { Invoke-GsdLocalCommand -Rest ($Rest | Select-Object -Skip 1) }
        'global' { Invoke-GsdGlobalCommand -Rest ($Rest | Select-Object -Skip 1) }
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
        'nuke' {
            $dryRun    = $Rest -contains '--dry-run'
            $yes       = $Rest -contains '--yes'
            $keepHome  = $Rest -contains '--keep-home'
            $projOnly  = $Rest -contains '--project-only'
            Invoke-GsdNuke -DryRun:$dryRun -Yes:$yes -KeepHome:$keepHome -ProjectOnly:$projOnly
        }
        'combo'  { Invoke-GsdCombo -Rest ($Rest | Select-Object -Skip 1) }
        'auth-fix' {
            Invoke-GsdAuthFix -DryRun:$dryRun
        }
        'fix-tools-cap' {
            Invoke-GsdFixToolsCap -DryRun:$dryRun
        }
        'reset-auth' {
            Invoke-GsdResetAuth -DryRun:$dryRun
        }
        'token-save' {
            $skipAuth    = $Rest -contains '--skip-auth-fix'
            $skipEnv     = $Rest -contains '--skip-env'
            $incCache    = $Rest -contains '--disable-caching'
            $forgeShims  = $Rest -contains '--forge-shims'
            $forgeFull   = $Rest -contains '--forge-full'
            $forgeRemove = $Rest -contains '--remove'
            $methodIdx = [Array]::IndexOf($Rest, '--method')
            $method = if ($methodIdx -ge 0 -and $methodIdx + 1 -lt $Rest.Count) { $Rest[$methodIdx + 1] } else { 'auto' }
            $cpIdx = [Array]::IndexOf($Rest, '--compact-pct')
            $compactPct = if ($cpIdx -ge 0 -and $cpIdx + 1 -lt $Rest.Count) { [int]$Rest[$cpIdx + 1] } else { 70 }
            Invoke-GsdTokenSave -DryRun:$dryRun -SkipAuthFix:$skipAuth -SkipEnv:$skipEnv -IncludeDisableCaching:$incCache -ForgeShims:$forgeShims -ForgeShimsRemove:$forgeRemove -ForgeFull:$forgeFull -Method $method -CompactPct $compactPct
        }
        'forge-sync' {
            Write-Host ''
            Write-Host '  [gsd] Syncing Forge Claude Code OAuth token...' -ForegroundColor Cyan
            $syncResult = Sync-ForgeClaudeCodeToken
            if ($syncResult.Synced) {
                # Verify claude CLI sees the token
                try {
                    $authOutput = & claude auth status 2>&1 | Out-String
                    if ($authOutput -match '"loggedIn":\s*true') {
                        Write-Host '  [ok]      claude auth status: loggedIn=true' -ForegroundColor Green
                    } else {
                        Write-Host '  [warn]    claude auth status did not confirm login' -ForegroundColor DarkYellow
                    }
                } catch {
                    Write-Host '  [warn]    could not verify claude auth status' -ForegroundColor DarkYellow
                }
            }
            Write-Host ''
        }
        'guide'  { Show-GsdGuide }
        'help'   { Show-GsdHelp }
        default  { Show-GsdHelp }
    }
}

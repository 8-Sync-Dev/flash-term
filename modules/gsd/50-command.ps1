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

function Invoke-GsdCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun   = $Rest -contains '--dry-run'
    $pickMode = $Rest -contains '--pick'
    $autoMode = $Rest -contains '--auto'
    $balance  = $Rest -contains '--balance'

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

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { 'setup' }
    switch ($sub) {
        'setup' {
            if ($autoMode) {
                Invoke-GsdAutoSetup -DryRun:$dryRun
            } elseif ($pickMode) {
                Invoke-GsdPlanPicker -DryRun:$dryRun
            } elseif (-not [string]::IsNullOrWhiteSpace($modelArg)) {
                Invoke-GsdSetupFromModel -DryRun:$dryRun -Model $modelArg -Balance:$balance
            } elseif (-not [string]::IsNullOrWhiteSpace($planArg)) {
                Invoke-GsdSetup -DryRun:$dryRun -Plan $planArg
            } else {
                # No flags — launch interactive wizard
                Invoke-GsdSetupWizard -DryRun:$dryRun
            }
        }
        'status' { Invoke-GsdStatus }
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

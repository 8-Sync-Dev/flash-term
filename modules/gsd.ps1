# =============================================================================
# 8sync gsd -- GSD model routing setup
# =============================================================================

function Resolve-GsdHome {
    if (-not [string]::IsNullOrWhiteSpace($env:GSD_HOME) -and (Test-Path $env:GSD_HOME)) {
        return $env:GSD_HOME
    }
    return Join-Path $HOME '.gsd'
}

function Resolve-GsdAgentDir {
    if (-not [string]::IsNullOrWhiteSpace($env:GSD_CODING_AGENT_DIR) -and (Test-Path $env:GSD_CODING_AGENT_DIR)) {
        return $env:GSD_CODING_AGENT_DIR
    }
    return Join-Path (Resolve-GsdHome) 'agent'
}

function Show-GsdPlans {
    Write-Host ''
    Write-HintSection 'GSD Plans -- 8sync gsd setup --plan <name>'
    Write-Host ''
    Write-Host '  -- Multi-provider (mixing best models) ---------------------------------' -ForegroundColor DarkGray
    Write-HintRow 'max'                  'Opus plan + kimi K2.5 exec (SWE 76.8%) + groq free workers'
    Write-HintRow 'pro'                  'Sonnet plan/completion + kimi+codex exec + groq free'
    Write-HintRow 'normal'               'No Claude cost: codex+gemini plan + glm-5-turbo exec + groq'
    Write-Host ''
    Write-Host '  -- Single-provider (one ecosystem only) --------------------------------' -ForegroundColor DarkGray
    Write-HintRow 'claude-max'           '100% Claude: Opus plan + Sonnet exec + Haiku workers'
    Write-HintRow 'codex-max'            '100% OpenAI: gpt-5.4 plan + gpt-5.3-codex exec'
    Write-HintRow 'gemini-max'           '100% Google: gemini-3.1-pro plan+exec (2M ctx, free)'
    Write-Host ''
    Write-Host '  -- The Big Three combo (best of all worlds) ----------------------------' -ForegroundColor DarkGray
    Write-HintRow 'claude-codex-gemini'  'Opus plan + codex exec + gemini research -- best of all three'
    Write-Host ''
    Write-Host '  -- Required logins per plan --------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  max                : /login anthropic  github-copilot  google-gemini-cli  openai-codex' -ForegroundColor White
    Write-Host '                       + 8sync gsd key kimi-coding  zai  groq' -ForegroundColor DarkGray
    Write-Host '  pro                : /login anthropic  google-gemini-cli  openai-codex' -ForegroundColor White
    Write-Host '                       + 8sync gsd key kimi-coding  zai  groq' -ForegroundColor DarkGray
    Write-Host '  normal             : /login google-gemini-cli  openai-codex' -ForegroundColor White
    Write-Host '                       + 8sync gsd key zai  groq' -ForegroundColor DarkGray
    Write-Host '  claude-max         : /login anthropic  (Opus+Sonnet+Haiku only)' -ForegroundColor White
    Write-Host '  codex-max          : /login openai-codex  (gpt-5.x only)' -ForegroundColor White
    Write-Host '  gemini-max         : /login google-gemini-cli  (gemini-3.1-pro free)' -ForegroundColor White
    Write-Host '  claude-codex-gemini: /login anthropic  openai-codex  google-gemini-cli' -ForegroundColor White
    Write-Host ''
    Write-Host '  Apply: 8sync gsd setup --plan <name>' -ForegroundColor DarkGray
    Write-Host '  Check: /gsd prefs   /model' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GsdHelp {
    Write-Host ''
    Write-HintSection 'GSD -- Model routing setup'
    Write-HintRow '8sync gsd setup'                      'Apply default PREFERENCES.md -> ~/.gsd'
    Write-HintRow '8sync gsd setup --plan <name>'        'Apply named plan (see below)'
    Write-HintRow '8sync gsd setup --plan'               'List all plans with descriptions'
    Write-HintRow '8sync gsd setup --dry-run'            'Preview without writing'
    Write-HintRow '8sync gsd key <provider> <key>'       'Set API key (session + persist to user env)'
    Write-HintRow '8sync gsd keys'                       'List all providers, env vars + setup guide'
    Write-HintRow '8sync gsd status'                     'Show paths, auth providers, key status'
    Write-HintRow '8sync gsd help'                       'Show this help'
    Write-Host ''
    Write-HintSection 'Plans (multi-provider)'
    Write-HintRow 'max'    'Opus plan + kimi K2.5 exec (SWE 76.8%) + groq free workers'
    Write-HintRow 'pro'    'Sonnet plan/completion + kimi+codex exec + groq free'
    Write-HintRow 'normal' 'No Claude: codex+gemini plan + glm-5-turbo exec + groq'
    Write-HintSection 'Plans (single-provider)'
    Write-HintRow 'claude-max'  '100% Claude: Opus plan + Sonnet exec + Haiku workers'
    Write-HintRow 'codex-max'   '100% OpenAI: gpt-5.4 plan + gpt-5.3-codex exec'
    Write-HintRow 'gemini-max'  '100% Google: gemini-3.1-pro plan+exec (2M ctx, free)'
    Write-HintSection 'Plans (combo)'
    Write-HintRow 'claude-codex-gemini' 'Big Three: Opus plan + codex exec + gemini research'
    Write-Host ''
    Write-Host '  Run "8sync gsd setup --plan" (no value) for full plan details' -ForegroundColor DarkGray
    Write-Host '  Verify: /gsd prefs   /model' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdSetup {
    param(
        [switch]$DryRun,
        [string]$Plan = ''
    )

    $bundleDir  = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\gsd-config'))
    $gsdHome    = Resolve-GsdHome
    $validPlans = @('max', 'pro', 'normal', 'claude-max', 'codex-max', 'gemini-max', 'claude-codex-gemini')
    $planLower  = $Plan.ToLowerInvariant().Trim()

    if ($planLower -ne '' -and $validPlans -notcontains $planLower) {
        Write-Host ''
        Write-Host ("  [error] Unknown plan '{0}'." -f $Plan) -ForegroundColor Red
        Write-Host '  Valid: max | pro | normal | claude-max | codex-max | gemini-max | claude-codex-gemini' -ForegroundColor DarkGray
        Write-Host '  Run "8sync gsd setup --plan" (no value) for full descriptions.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $srcFile  = if ($planLower -ne '') {
        Join-Path $bundleDir ("PREFERENCES-{0}.md" -f $planLower)
    } else {
        Join-Path $bundleDir 'PREFERENCES.md'
    }
    $destFile  = Join-Path $gsdHome 'PREFERENCES.md'
    $planLabel = if ($planLower -ne '') { $planLower } else { 'default' }

    Write-Host ''
    Write-Host ("  [gsd] Setup model routing  plan={0}" -f $planLabel) -ForegroundColor Cyan
    Write-Host ("  source : {0}" -f $srcFile)  -ForegroundColor DarkGray
    Write-Host ("  dest   : {0}" -f $destFile) -ForegroundColor DarkGray
    Write-Host ''

    if (-not (Test-Path $srcFile)) {
        Write-Host ("  [error] source not found: {0}" -f $srcFile) -ForegroundColor Red
        return
    }

    if ($DryRun) {
        Write-Host '  [dry-run] No files written.' -ForegroundColor Yellow
        Write-Host ("  [dry-run] would copy -> {0}" -f $destFile) -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    $dir = Split-Path $destFile -Parent
    if (-not (Test-Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }
    try {
        Copy-Item -Path $srcFile -Destination $destFile -Force -ErrorAction Stop
        Write-Host ("  [ok] {0}" -f $destFile) -ForegroundColor Green
    } catch {
        Write-Host ("  [error] {0} -- {1}" -f $destFile, $_.Exception.Message) -ForegroundColor Red
        return
    }

    Write-Host ''
    if ($planLower -ne '') {
        Write-Host ("  Plan '{0}' applied. Required setup:" -f $planLabel) -ForegroundColor Cyan
        switch ($planLower) {
            'max' {
                Write-Host '  /login -> anthropic  github-copilot  google-gemini-cli  openai-codex' -ForegroundColor Yellow
                Write-Host '  keys   -> 8sync gsd key kimi-coding <key>' -ForegroundColor Yellow
                Write-Host '            8sync gsd key zai <key>' -ForegroundColor Yellow
                Write-Host '            8sync gsd key groq <key>' -ForegroundColor Yellow
            }
            'pro' {
                Write-Host '  /login -> anthropic  google-gemini-cli  openai-codex' -ForegroundColor Yellow
                Write-Host '  keys   -> 8sync gsd key kimi-coding <key>' -ForegroundColor Yellow
                Write-Host '            8sync gsd key zai <key>' -ForegroundColor Yellow
                Write-Host '            8sync gsd key groq <key>' -ForegroundColor Yellow
            }
            'normal' {
                Write-Host '  /login -> google-gemini-cli  openai-codex' -ForegroundColor Yellow
                Write-Host '  keys   -> 8sync gsd key zai <key>' -ForegroundColor Yellow
                Write-Host '            8sync gsd key groq <key>' -ForegroundColor Yellow
                Write-Host '  optional: 8sync gsd key google <key>  (gemini-2.5-pro free tier)' -ForegroundColor DarkGray
            }
            'claude-max' {
                Write-Host '  /login -> anthropic' -ForegroundColor Yellow
                Write-Host '  Models : Opus 4-6 plan/research -> Sonnet 4-6 exec -> Haiku 4-5 simple' -ForegroundColor DarkGray
                Write-Host '  100% Claude -- no external providers needed' -ForegroundColor DarkGray
            }
            'codex-max' {
                Write-Host '  /login -> openai-codex  (ChatGPT OAuth, free)' -ForegroundColor Yellow
                Write-Host '  OR key -> 8sync gsd key openai <key>  (paid API)' -ForegroundColor Yellow
                Write-Host '  Models : gpt-5.4 plan -> gpt-5.3-codex exec -> gpt-5.1-codex-max simple' -ForegroundColor DarkGray
                Write-Host '  100% OpenAI -- no Anthropic/Google needed' -ForegroundColor DarkGray
            }
            'gemini-max' {
                Write-Host '  /login -> google-gemini-cli  (Cloud Code Assist, free)' -ForegroundColor Yellow
                Write-Host '  optional: /login github-copilot  (copilot/gemini-3.1-pro)' -ForegroundColor DarkGray
                Write-Host '  optional: 8sync gsd key google <key>  (gemini-2.5-pro API fallback)' -ForegroundColor DarkGray
                Write-Host '  Models : gemini-3.1-pro-preview all roles (2M ctx)' -ForegroundColor DarkGray
                Write-Host '  100% Google -- no Anthropic/OpenAI needed' -ForegroundColor DarkGray
            }
            'claude-codex-gemini' {
                Write-Host '  /login -> anthropic  openai-codex  google-gemini-cli' -ForegroundColor Yellow
                Write-Host '  optional: /login github-copilot  (extra model access)' -ForegroundColor DarkGray
                Write-Host '  Models : Opus plan -> codex exec -> gemini research (best of three)' -ForegroundColor DarkGray
                Write-Host '  The Big Three -- Anthropic + OpenAI + Google' -ForegroundColor Cyan
            }
        }
        Write-Host ''
        Write-Host '  Then verify: /gsd prefs   /model' -ForegroundColor DarkGray
    } else {
        Write-Host '  Done. Next: /login in pi, then /gsd prefs to verify.' -ForegroundColor Cyan
    }
    Write-Host ''
}

# Known providers and their env var names
$script:GsdProviderKeys = [ordered]@{
    'zai'          = 'ZAI_API_KEY'
    'kimi-coding'  = 'KIMI_API_KEY'
    'groq'         = 'GROQ_API_KEY'
    'google'       = 'GEMINI_API_KEY'
    'openrouter'   = 'OPENROUTER_API_KEY'
    'anthropic'    = 'ANTHROPIC_API_KEY'
    'openai'       = 'OPENAI_API_KEY'
    'xai'          = 'XAI_API_KEY'
    'mistral'      = 'MISTRAL_API_KEY'
    'context7'     = 'CONTEXT7_API_KEY'
    'jina'         = 'JINA_API_KEY'
    'brave'        = 'BRAVE_API_KEY'
    'tavily'       = 'TAVILY_API_KEY'
}

# Human-readable notes shown in 8sync gsd keys
$script:GsdProviderNotes = @{
    'zai'          = 'z.ai console - glm-5-turbo $1.2/$4/M  (stable, agentic)'
    'kimi-coding'  = 'platform.moonshot.cn - Kimi K2.5 SWE-bench 76.8%  (free credits)'
    'groq'         = 'console.groq.com - kimi-k2+qwen3-32b FREE daily reset'
    'google'       = 'aistudio.google.com - gemini-2.5-pro 5RPM/25RPD free tier'
    'openrouter'   = 'openrouter.ai - aggregator, 200+ models incl. free tier'
    'anthropic'    = 'console.anthropic.com - paid key OR use /login OAuth (free)'
    'openai'       = 'platform.openai.com - paid key OR use /login openai-codex (free)'
    'xai'          = 'console.x.ai - grok-4.20 free credits on signup'
    'mistral'      = 'console.mistral.ai - pixtral-large, free tier available'
    'context7'     = 'context7.com - documentation lookup (already set)'
    'jina'         = 'jina.ai - web reader/search'
    'brave'        = 'brave.com/search/api - web search'
    'tavily'       = 'tavily.com - web search'
}

function Show-GsdKeys {
    Write-Host ''
    Write-HintSection 'GSD API Keys -- all providers'
    Write-Host '  Usage: 8sync gsd key <provider> <api-key>' -ForegroundColor DarkGray
    Write-Host ''

    $agentDir     = Resolve-GsdAgentDir
    $envFile      = Join-Path $agentDir '.env'
    $envFileLines = @()
    if (Test-Path $envFile) {
        $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    Write-Host ("  {0,-15} {1,-22} {2,-12} {3}" -f 'PROVIDER', 'ENV VAR', 'STATUS', 'WHERE TO GET') -ForegroundColor DarkGray
    Write-Host ("  {0}" -f ('-' * 90)) -ForegroundColor DarkGray

    foreach ($provider in $script:GsdProviderKeys.Keys) {
        $varName  = $script:GsdProviderKeys[$provider]
        $note     = if ($script:GsdProviderNotes.ContainsKey($provider)) { $script:GsdProviderNotes[$provider] } else { '' }
        $fromEnv  = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
        $fromUser = [System.Environment]::GetEnvironmentVariable($varName, 'User')
        $fromFile = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1

        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            $status = '[set]'
            $color  = 'Green'
        } elseif (-not [string]::IsNullOrWhiteSpace($fromUser)) {
            $status = '[set]'
            $color  = 'Green'
        } elseif ($fromFile) {
            $status = '[.env]'
            $color  = 'DarkYellow'
        } else {
            $status = '[empty]'
            $color  = 'DarkGray'
        }

        Write-Host ("  {0,-15} {1,-22} {2,-12} {3}" -f $provider, $varName, $status, $note) -ForegroundColor $color
    }

    Write-Host ''
    Write-Host '  OAuth providers (no key needed, use /login in pi):' -ForegroundColor DarkGray
    Write-Host '    anthropic         /login anthropic' -ForegroundColor White
    Write-Host '    github-copilot    /login github-copilot   (requires Copilot subscription)' -ForegroundColor White
    Write-Host '    google-gemini-cli /login google-gemini-cli (free via Cloud Code Assist)' -ForegroundColor White
    Write-Host '    openai-codex      /login openai-codex      (free via ChatGPT OAuth)' -ForegroundColor White
    Write-Host ''
}

function Invoke-GsdKey {
    param([string]$Provider, [string]$Key)

    if ([string]::IsNullOrWhiteSpace($Provider) -or [string]::IsNullOrWhiteSpace($Key)) {
        Show-GsdKeys
        return
    }

    $providerLower = $Provider.ToLowerInvariant()
    if (-not $script:GsdProviderKeys.Contains($providerLower)) {
        Write-Host ("  [error] Unknown provider '{0}'. Run: 8sync gsd keys" -f $Provider) -ForegroundColor Red
        Write-Host ''
        return
    }

    $envVarName = $script:GsdProviderKeys[$providerLower]

    # Set for current session and persist to user env
    [System.Environment]::SetEnvironmentVariable($envVarName, $Key, 'Process')
    [System.Environment]::SetEnvironmentVariable($envVarName, $Key, 'User')

    # Also write to ~/.gsd/agent/.env so GSD daemon picks it up on restart
    $agentDir = Resolve-GsdAgentDir
    $envFile  = Join-Path $agentDir '.env'
    try {
        if (-not (Test-Path $agentDir)) { $null = New-Item -Path $agentDir -ItemType Directory -Force }
        $newLine = '{0}={1}' -f $envVarName, $Key
        if (Test-Path $envFile) {
            $lines    = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
            $replaced = $false
            $newLines = $lines | ForEach-Object {
                if ($_ -match ('^' + [regex]::Escape($envVarName) + '\s*=')) {
                    $replaced = $true
                    $newLine
                } else { $_ }
            }
            if (-not $replaced) { $newLines += $newLine }
            Set-Content -Path $envFile -Value $newLines -Encoding UTF8 -Force
        } else {
            Set-Content -Path $envFile -Value $newLine -Encoding UTF8 -Force
        }
    } catch {}

    Write-Host ''
    Write-Host ("  [gsd] {0} set" -f $envVarName) -ForegroundColor Green
    Write-Host '  Active now + persisted to user env + written to ~/.gsd/agent/.env' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdStatus {
    $gsdHome  = Resolve-GsdHome
    $agentDir = Resolve-GsdAgentDir

    $files = @(
        @{ Label = 'PREFERENCES.md'; Path = Join-Path $gsdHome  'PREFERENCES.md' }
        @{ Label = 'models.json';    Path = Join-Path $agentDir 'models.json'    }
        @{ Label = 'auth.json';      Path = Join-Path $agentDir 'auth.json'      }
    )

    Write-Host ''
    Write-Host '  [gsd] Status' -ForegroundColor Cyan
    Write-Host ("  GSD_HOME: {0}" -f $gsdHome) -ForegroundColor DarkGray
    Write-Host ''

    foreach ($f in $files) {
        $exists = Test-Path $f.Path
        $color  = if ($exists) { 'Green' } else { 'DarkYellow' }
        $status = if ($exists) { 'ok'    } else { 'MISSING'    }
        Write-Host ("  {0,-20} {1,-8} {2}" -f $f.Label, $status, $f.Path) -ForegroundColor $color
    }

    Write-Host ''

    # Current plan detection
    $prefPath = Join-Path $gsdHome 'PREFERENCES.md'
    $detectedPlan = ''
    if (Test-Path $prefPath) {
        $bundleDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\gsd-config'))
        $detectedPlan = 'unknown/custom'
        foreach ($p in @('max','pro','normal','claude-max','codex-max','gemini-max','claude-codex-gemini')) {
            $planFile = Join-Path $bundleDir ("PREFERENCES-{0}.md" -f $p)
            if (Test-Path $planFile) {
                $a = (Get-FileHash $prefPath -Algorithm MD5).Hash
                $b = (Get-FileHash $planFile -Algorithm MD5).Hash
                if ($a -eq $b) { $detectedPlan = $p; break }
            }
        }
        Write-Host ("  Active plan: {0}" -f $detectedPlan) -ForegroundColor Cyan
        Write-Host ''
    }

    # Per-plan requirements: which OAuth logins + which API keys are needed
    $planRequirements = @{
        'max'    = @{
            oauth = @('anthropic','github-copilot','google-gemini-cli','openai-codex')
            keys  = @('kimi-coding','zai','groq')
        }
        'pro'    = @{
            oauth = @('anthropic','google-gemini-cli','openai-codex')
            keys  = @('kimi-coding','zai','groq')
        }
        'normal' = @{
            oauth = @('google-gemini-cli','openai-codex')
            keys  = @('zai','groq')
        }
        'claude-max' = @{
            oauth = @('anthropic')
            keys  = @()
        }
        'codex-max' = @{
            oauth = @('openai-codex')
            keys  = @()
        }
        'gemini-max' = @{
            oauth = @('google-gemini-cli')
            keys  = @()
        }
        'claude-codex-gemini' = @{
            oauth = @('anthropic','openai-codex','google-gemini-cli')
            keys  = @()
        }
    }

    # Logged-in OAuth providers
    $authPath = Join-Path $agentDir 'auth.json'
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            Write-Host '  OAuth providers:' -ForegroundColor DarkGray
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $auth.PSObject.Properties | ForEach-Object {
                $type = if ($_.Value.type) { $_.Value.type } else { '?' }
                $exp  = $_.Value.expires
                if ($exp) {
                    $diff  = [long]$exp - $now
                    $hours = [math]::Round($diff / 3600000)
                    $tag   = if ($diff -gt 0) { "valid ~{0}h" -f $hours } else { 'EXPIRED' }
                    $color = if ($diff -gt 0) { 'Green' } else { 'Red' }
                } else {
                    $tag   = $type
                    $color = 'Green'
                }
                Write-Host ("    {0,-28} {1}" -f $_.Name, $tag) -ForegroundColor $color
            }
        } catch {
            Write-Host '  auth.json: could not parse' -ForegroundColor DarkYellow
        }
    }

    Write-Host ''

    # API key status
    Write-Host '  API keys:' -ForegroundColor DarkGray
    $envFile      = Join-Path $agentDir '.env'
    $envFileLines = @()
    if (Test-Path $envFile) {
        $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    foreach ($provider in $script:GsdProviderKeys.Keys) {
        $varName  = $script:GsdProviderKeys[$provider]
        $fromEnv  = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
        $fromUser = [System.Environment]::GetEnvironmentVariable($varName, 'User')
        $fromFile = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1

        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            $status = 'set (env)';        $color = 'Green'
        } elseif (-not [string]::IsNullOrWhiteSpace($fromUser)) {
            $status = 'set (user)';       $color = 'Green'
        } elseif ($fromFile) {
            $status = 'set (.env only)';  $color = 'DarkYellow'
        } else {
            $status = 'not set';          $color = 'DarkGray'
        }
        Write-Host ("    {0,-15} {1,-22} {2}" -f $provider, $varName, $status) -ForegroundColor $color
    }

    Write-Host ''

    # Checklist: what this plan still needs
    if ($detectedPlan -ne '' -and $planRequirements.ContainsKey($detectedPlan)) {
        $req     = $planRequirements[$detectedPlan]
        $missing = [System.Collections.Generic.List[string]]::new()

        # Check OAuth
        $loggedIn = @()
        if (Test-Path $authPath) {
            try {
                $auth2 = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                $now2  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $auth2.PSObject.Properties | ForEach-Object {
                    $exp2 = $_.Value.expires
                    if (-not $exp2 -or ([long]$exp2 - $now2) -gt 0) { $loggedIn += $_.Name }
                }
            } catch {}
        }
        foreach ($p in $req.oauth) {
            if ($loggedIn -notcontains $p) { $missing.Add("/login $p") }
        }

        # Check API keys
        $envFile2      = Join-Path $agentDir '.env'
        $envFileLines2 = @()
        if (Test-Path $envFile2) { $envFileLines2 = Get-Content $envFile2 -Encoding UTF8 -ErrorAction SilentlyContinue }
        foreach ($p in $req.keys) {
            $varName2 = $script:GsdProviderKeys[$p]
            $hasKey   = (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName2,'Process'))) -or
                        (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName2,'User'))) -or
                        ($envFileLines2 | Where-Object { $_ -match ('^' + [regex]::Escape($varName2) + '\s*=') })
            if (-not $hasKey) { $missing.Add("8sync gsd key $p <key>") }
        }

        if ($missing.Count -eq 0) {
            Write-Host '  Checklist: all requirements met' -ForegroundColor Green
        } else {
            Write-Host ("  Checklist: {0} item(s) missing for plan '{1}'" -f $missing.Count, $detectedPlan) -ForegroundColor Yellow
            foreach ($m in $missing) {
                Write-Host ("    [x] {0}" -f $m) -ForegroundColor Red
            }
        }
        Write-Host ''
    }
}

function Invoke-GsdCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun  = $Rest -contains '--dry-run'
    $planArg = ''
    $planIdx = [Array]::IndexOf($Rest, '--plan')
    if ($planIdx -ge 0) {
        if ($planIdx + 1 -lt $Rest.Count -and $Rest[$planIdx + 1] -notlike '--*') {
            $planArg = $Rest[$planIdx + 1]
        } else {
            # --plan with no value -> show plan list
            Show-GsdPlans
            return
        }
    }

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { 'setup' }

    switch ($sub) {
        'setup'  { Invoke-GsdSetup -DryRun:$dryRun -Plan $planArg }
        'status' { Invoke-GsdStatus }
        'key'    { Invoke-GsdKey -Provider ($Rest | Select-Object -Skip 1 -First 1) -Key ($Rest | Select-Object -Skip 2 -First 1) }
        'keys'   { Show-GsdKeys }
        'help'   { Show-GsdHelp }
        default  { Show-GsdHelp }
    }
}

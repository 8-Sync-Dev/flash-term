# =============================================================================
# 8sync gsd -- help, picker, and key management
# =============================================================================

function Invoke-GsdSetupWizard {
    param([switch]$DryRun)

    Write-Host ''
    Write-HintSection 'GSD Setup Wizard'
    Write-Host ''

    # ── Step 1: which brands/providers? ──────────────────────────────────────
    Write-Host '  Step 1/3  Which AI providers do you have access to?' -ForegroundColor Yellow
    Write-Host '  (brands available, pick what you have logged in or keyed)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [1] claude    Anthropic -- best planning/review (OAuth, free)' -ForegroundColor White
    Write-Host '  [2] codex     OpenAI Codex -- planning-heavy stack (OAuth, free) [planning only]' -ForegroundColor White
    Write-Host '  [3] gemini    Google Gemini CLI -- large ctx, research (OAuth, free)' -ForegroundColor White
    Write-Host '  [4] glm       ZAI/GLM -- strong exec+cost balance (API key)' -ForegroundColor White
    Write-Host '  [5] kimi      Kimi Coding -- fast cheap subagent (API key)' -ForegroundColor White
    Write-Host '  [6] groq      Groq -- free fast workers (API key)' -ForegroundColor White
    Write-Host '  [7] gguf      Local llama-server (auto-detect running server)' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Type numbers separated by space or + (e.g. "1 2" or "claude+codex+gguf")' -ForegroundColor DarkGray
    Write-Host '  Press Enter for recommended: claude+codex' -ForegroundColor DarkGray
    Write-Host ''
    $raw = Read-Host '  Providers'
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = 'claude+codex' }

    # normalise: "1 2 3" -> brand names, "claude+codex" -> passthrough
    $numMap = @{ '1'='claude'; '2'='codex'; '3'='gemini'; '4'='glm'; '5'='kimi'; '6'='groq'; '7'='gguf' }
    $tokens = $raw -replace '\+', ' ' -split '\s+' | Where-Object { $_ -ne '' }
    $brands = $tokens | ForEach-Object {
        $t = $_.ToLowerInvariant()
        if ($numMap.ContainsKey($t)) { $numMap[$t] } else { $t }
    }
    $modelArg = ($brands | Select-Object -Unique) -join '+'

    Write-Host ''
    Write-Host ("  -> Stack: {0}" -f $modelArg) -ForegroundColor Cyan
    Write-Host ''

    # ── Step 2: cost/balance mode ─────────────────────────────────────────────
    Write-Host '  Step 2  Cost tier' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  [1] balanced  Coding models lead exec; sonnet leads planning; haiku as cheap fallback  (recommended)' -ForegroundColor Cyan
    Write-Host '  [2] heavy     Sonnet leads planning + exec; strongest anthropic coverage' -ForegroundColor White
    Write-Host '  [3] light     Coding models lead everything; anthropic only as last resort' -ForegroundColor White
    Write-Host ''
    $costRaw = Read-Host '  Choice [1]'
    $tierArg = switch ($costRaw.Trim()) {
        '2' { 'heavy' }
        '3' { 'light' }
        default { 'balanced' }
    }

    Write-Host ''
    Write-Host ("  -> Tier: {0}" -f $tierArg) -ForegroundColor Cyan
    Write-Host ''

    # ── Step 3: role assignment ───────────────────────────────────────────────
    $planningPin = ''
    $execPin = ''

    if ($modelArg -match 'claude') {
        Write-Host '  Step 3/4  Role assignment (Claude detected)' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  [1] auto       Let 8sync decide based on tier (default)' -ForegroundColor Cyan
        Write-Host '  [2] opus-plan  Opus plans/research, Sonnet codes, others review' -ForegroundColor White
        Write-Host '  [3] sonnet-all Sonnet does everything (no Opus)' -ForegroundColor White
        Write-Host ''
        $roleRaw = Read-Host '  Choice [1]'
        switch ($roleRaw.Trim()) {
            '2' {
                $planningPin = 'anthropic/claude-opus-4-6'
                $execPin = 'anthropic/claude-sonnet-4-6'
                Write-Host ''
                Write-Host '  -> Opus plans + Sonnet codes' -ForegroundColor Cyan
            }
            '3' {
                $planningPin = 'anthropic/claude-sonnet-4-6'
                $execPin = 'anthropic/claude-sonnet-4-6'
                Write-Host ''
                Write-Host '  -> Sonnet everywhere' -ForegroundColor Cyan
            }
            default {
                Write-Host ''
                Write-Host '  -> Auto (tier-based)' -ForegroundColor Cyan
            }
        }
        Write-Host ''
    }

    # ── Step 4: confirm ───────────────────────────────────────────────────────
    $stepLabel = if ($modelArg -match 'claude') { '4/4' } else { '3/3' }
    Write-Host ("  Step {0}  Confirm" -f $stepLabel) -ForegroundColor Yellow
    Write-Host ''
    Write-Host ("  Stack   : {0}" -f $modelArg) -ForegroundColor White
    Write-Host ("  Tier    : {0}" -f $tierArg) -ForegroundColor White
    if ($planningPin) { Write-Host ("  Planning: {0}" -f $planningPin) -ForegroundColor White }
    if ($execPin)     { Write-Host ("  Exec    : {0}" -f $execPin) -ForegroundColor White }
    Write-Host ("  Write to: {0}" -f (Join-Path (Resolve-GsdHome) 'PREFERENCES.md')) -ForegroundColor DarkGray
    Write-Host ''
    $confirm = Read-Host '  Apply? [Y/n]'
    if ($confirm -match '^[Nn]') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Invoke-GsdSetupFromModel -Model $modelArg -DryRun:$DryRun -Tier $tierArg -PlanningPin $planningPin -ExecPin $execPin
}

function Invoke-GsdPlanPicker {
    param([switch]$DryRun)

    if (-not (Test-CommandExists 'fzf')) {
        Write-Host ''
        Write-Host '  [!] fzf not found -- install with: scoop install fzf' -ForegroundColor Red
        Write-Host '  Fallback: 8sync gsd setup --plan <name>' -ForegroundColor DarkGray
        Write-Host ''
        Show-GsdPlans
        return
    }

    $agentDir = Resolve-GsdAgentDir
    $authPath = Join-Path $agentDir 'auth.json'
    $loggedIn = @{}
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $auth.PSObject.Properties | ForEach-Object {
                $exp = $_.Value.expires
                if (-not $exp -or ([long]$exp - $now) -gt 0) { $loggedIn[$_.Name] = $true }
            }
        } catch {}
    }

    $envFile = Join-Path $agentDir '.env'
    $envFileLines = @()
    if (Test-Path $envFile) {
        $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    function Test-ProviderConfigured {
        param($Provider)

        if ($Provider.Type -eq 'oauth') { return $loggedIn[$Provider.Id] -eq $true }
        $varName = $script:GsdProviderKeys[$Provider.Id]
        return (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName, 'Process'))) -or
               (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName, 'User'))) -or
               ($null -ne ($envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1))
    }

    $preConfigured = @($script:GsdProviderMenu | Where-Object { Test-ProviderConfigured $_ } | ForEach-Object { $_.Id })
    $fzfLines = $script:GsdProviderMenu | Sort-Object {
        if ($preConfigured -contains $_.Id) { 0 } else { 1 }
    } | ForEach-Object {
        $configured = Test-ProviderConfigured $_
        if ($_.Type -eq 'oauth') {
            $status = if ($configured) { '[✓ logged in ]' } else { '[ not logged  ]' }
        } else {
            $status = if ($configured) { '[✓ key set   ]' } else { '[ no key      ]' }
        }
        "$($_.Id)`t$status  $($_.Label)`t$($_.Desc)"
    }

    $chosen = $fzfLines | fzf --multi --delimiter "`t" --with-nth '2,3' --header 'SPACE=toggle  ENTER=apply  (pre-configured shown first)' --prompt '  Provider> ' --height '~85%' --border rounded --bind 'tab:toggle+down' --bind 'shift-tab:toggle+up'
    if (-not $chosen) {
        Write-Host '  [cancelled]' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $selectedIds = @($chosen | ForEach-Object { ($_ -split "`t")[0].Trim() })
    Write-Host ''
    Write-Host '  Selected providers:' -ForegroundColor DarkGray
    foreach ($id in $selectedIds) {
        $color = if ($preConfigured -contains $id) { 'Green' } else { 'Yellow' }
        $mark = if ($preConfigured -contains $id) { '✓' } else { '+' }
        Write-Host ("    {0} {1}" -f $mark, $id) -ForegroundColor $color
    }
    Write-Host ''

    $yaml = Build-GsdModelsYaml -Selected $selectedIds
    if (-not $yaml) {
        Write-Host '  [error] Selection produced no models. Select at least one exec provider (zai, groq, kimi-coding, or anthropic).' -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host '  Generated model routing:' -ForegroundColor Cyan
    $yaml -split "`n" | Select-Object -First 20 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
    if (($yaml -split "`n").Count -gt 20) { Write-Host '    ...' -ForegroundColor DarkGray }
    Write-Host ''

    $destPath = Join-Path (Resolve-GsdHome) 'PREFERENCES.md'
    $ok = Write-GsdPreferencesModels -ModelsYaml $yaml -DestPath $destPath -DryRun:$DryRun
    if ($ok -and -not $DryRun) {
        Invoke-GsdRuntimePatch
        Write-Host ("  [ok] {0}" -f $destPath) -ForegroundColor Green
        Write-Host ''
        Write-Host '  Next: /gsd prefs to verify   /model to browse available models' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Show-GsdHelp {
    Write-Host ''
    Write-HintSection 'GSD -- model stack setup for large coding projects'
    Write-Host ''
    Write-Host '  Core commands' -ForegroundColor Cyan
    Write-Host '    8sync gsd setup --model <stack>' -ForegroundColor White
    Write-Host '        Preferred. Generate routing from brand stack, then auto-apply GSD Anthropic OAuth fix.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --model' -ForegroundColor White
    Write-Host '        Show accepted brand tokens, examples, and preset guidance.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --plan <name>' -ForegroundColor White
    Write-Host '        Legacy preset apply. Still supported for one-shot setup.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --plan' -ForegroundColor White
    Write-Host '        List presets, brand tokens, and real examples.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --auto' -ForegroundColor White
    Write-Host '        Auto-detect valid logins/keys and generate best available routing.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --pick' -ForegroundColor White
    Write-Host '        Interactive fzf picker with provider status.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --dry-run' -ForegroundColor White
    Write-Host '        Preview generated routing without writing ~/.gsd/PREFERENCES.md.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Key and status' -ForegroundColor Cyan
    Write-Host '    8sync gsd key <provider> <key>' -ForegroundColor White
    Write-Host '        LLM: zai kimi-coding groq google openai xai mistral' -ForegroundColor DarkGray
    Write-Host '        Search: tavily brave ollama   Tools: context7 jina' -ForegroundColor DarkGray
    Write-Host '    8sync gsd keys' -ForegroundColor White
    Write-Host '        List all providers grouped by type and show current status.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd status' -ForegroundColor White
    Write-Host '        Show active files, auth providers, key status, and missing setup.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd fix [--dry-run]' -ForegroundColor White
    Write-Host '        Fast repair: restore ~/.gsd/agent/node_modules and ~/.gsd/resource-loader.js, patch runtime, and clean stale .gsd DB sidecars.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd fix --refresh' -ForegroundColor White
    Write-Host '        Refresh the preferred runtime. Local project runtime is used first; global install stays blocked unless --allow-global is provided.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd fix --stable' -ForegroundColor White
    Write-Host '        Same fix path, but explicitly using the pinned stable profile contract for runtime patching.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd fix --force' -ForegroundColor White
    Write-Host '        Also back up and rebuild gsd.db, completed-units.json, and routing-history.json when the DB is genuinely corrupted.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd fix --allow-global' -ForegroundColor White
    Write-Host '        Opt in to global gsd-pi refresh only when you explicitly approve machine-wide changes.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd local' -ForegroundColor White
    Write-Host '        Inspect project-local .gsd/vendor/gsd-pi/current, baseline-2.69.0, and latest paths.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd guide' -ForegroundColor White
    Write-Host '        Show Vietnamese quick guide for gsd-pi (GSD-2): features, workflow, pro tips.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Model management' -ForegroundColor Cyan
    Write-Host '    8sync gsd model add <model-id>' -ForegroundColor White
    Write-Host '        Add a new model to GSD registry without upgrading gsd-pi.' -ForegroundColor DarkGray
    Write-Host '        e.g. 8sync gsd model add claude-opus-4-7' -ForegroundColor DarkGray
    Write-Host '    8sync gsd model add' -ForegroundColor White
    Write-Host '        Show available model templates with pricing.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd model list' -ForegroundColor White
    Write-Host '        List all Anthropic models currently in registry.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Quick start' -ForegroundColor Cyan
    Write-Host '    --model codex' -ForegroundColor White
    Write-Host '        Single-brand. Use only the selected ecosystem.' -ForegroundColor DarkGray
    Write-Host '    --model codex+glm' -ForegroundColor White
    Write-Host '        Recommended default for cost/perf on big repos.' -ForegroundColor DarkGray
    Write-Host '    --model claude+codex+gemini' -ForegroundColor White
    Write-Host '        Highest-quality mixed stack for planning and research.' -ForegroundColor DarkGray
    Write-Host '    --auto' -ForegroundColor White
    Write-Host '        Best when you already logged in / set keys and want zero thinking.' -ForegroundColor DarkGray
    Write-Host '    --pick' -ForegroundColor White
    Write-Host '        Best when you want interactive selection and visible provider status.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Accepted --model brands' -ForegroundColor Cyan
    Write-Host '    claude  -> anthropic' -ForegroundColor White
    Write-Host '    codex   -> openai-codex' -ForegroundColor White
    Write-Host '    gemini  -> google-gemini-cli' -ForegroundColor White
    Write-Host '    glm     -> zai' -ForegroundColor White
    Write-Host '    kimi    -> kimi-coding' -ForegroundColor White
    Write-Host '    groq    -> groq' -ForegroundColor White
    Write-Host '    copilot -> github-copilot' -ForegroundColor White
    Write-Host ''
    Write-Host '  Real examples' -ForegroundColor Cyan
    Write-Host '    8sync gsd setup --model codex' -ForegroundColor White
    Write-Host '        One provider only. Simple billing, simple behavior.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --model codex+glm' -ForegroundColor White
    Write-Host '        Premium planning + cheaper execution/workers.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --model glm+kimi+groq' -ForegroundColor White
    Write-Host '        No OAuth stack. Key-based and cost-controlled.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --model claude+codex+gemini --dry-run' -ForegroundColor White
    Write-Host '        Preview mixed high-end routing before apply.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --plan max' -ForegroundColor White
    Write-Host '        Apply existing curated preset directly.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --plan claude-codex-review' -ForegroundColor White
    Write-Host '        Opus plan + Sonnet code + Codex review. Cross-model peer review at $0.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --plan claude-max --use-model=opus+sonnet' -ForegroundColor White
    Write-Host '        Full Claude without Haiku. Sonnet handles simple tasks too.' -ForegroundColor DarkGray
    Write-Host '    8sync gsd setup --plan claude-max --use-model=sonnet+haiku --tier=light' -ForegroundColor White
    Write-Host '        Budget Claude: Haiku leads most tasks, Sonnet only for planning.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Rule of thumb' -ForegroundColor Cyan
    Write-Host '    no +        => single brand only' -ForegroundColor DarkGray
    Write-Host '    +           => mixed stack; 8sync auto-builds role routing from strengths/cost' -ForegroundColor DarkGray
    Write-Host '    --balance             => alias for --tier=balanced (backward compat)' -ForegroundColor DarkGray
    Write-Host '    --tier=light          => coding models lead all roles; anthropic as last resort' -ForegroundColor DarkGray
    Write-Host '    --tier=balanced       => sonnet leads planning; coding models lead exec (default)' -ForegroundColor DarkGray
    Write-Host '    --tier=heavy          => opus leads planning; sonnet leads exec (best quality)' -ForegroundColor DarkGray
    Write-Host '    --planning=opus       => pin opus as primary for planning/research' -ForegroundColor DarkGray
    Write-Host '    --planning=<model>    => pin any model as primary for planning/research' -ForegroundColor DarkGray
    Write-Host '    --exec=kimi           => pin kimi as primary for execution' -ForegroundColor DarkGray
    Write-Host '    --exec=<model>        => pin any model as primary for execution' -ForegroundColor DarkGray
    Write-Host '    +only=<brand>  => pin brand as primary in every role; others remain as fallbacks' -ForegroundColor DarkGray
    Write-Host '                      example: --model claude+codex --only=claude' -ForegroundColor DarkGray
    Write-Host '                   => claude-opus/sonnet primary, codex falls back when claude unavailable' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Detailed guide: 8sync gsd setup --model    or    8sync gsd setup --plan' -ForegroundColor DarkGray
    Write-Host '  Verify: 8sync gsd status   /gsd prefs   /model' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GsdKeys {
    Write-Host ''
    Write-HintSection 'GSD API Keys -- all providers'
    Write-Host '  Usage: 8sync gsd key <provider> <api-key>' -ForegroundColor DarkGray
    Write-Host ''

    $agentDir = Resolve-GsdAgentDir
    $envFile = Join-Path $agentDir '.env'
    $envFileLines = @()
    if (Test-Path $envFile) {
        $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    $groups = [ordered]@{
        'LLM Providers'    = @('zai','kimi-coding','groq','google','openrouter','anthropic','openai','xai','mistral')
        'Search Providers' = @('tavily','brave','ollama')
        'Tool Keys'        = @('context7','jina')
    }

    foreach ($groupName in $groups.Keys) {
        Write-Host ("  -- {0} {1}" -f $groupName, ('-' * (50 - $groupName.Length))) -ForegroundColor DarkGray
        Write-Host ("  {0,-15} {1,-24} {2,-10} {3}" -f 'PROVIDER', 'ENV VAR', 'STATUS', 'NOTES / WHERE TO GET') -ForegroundColor DarkGray
        foreach ($provider in $groups[$groupName]) {
            $varName = $script:GsdProviderKeys[$provider]
            $note = if ($script:GsdProviderNotes.ContainsKey($provider)) { $script:GsdProviderNotes[$provider] } else { '' }
            $fromEnv = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
            $fromUser = [System.Environment]::GetEnvironmentVariable($varName, 'User')
            $fromFile = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1

            if (-not [string]::IsNullOrWhiteSpace($fromEnv) -or -not [string]::IsNullOrWhiteSpace($fromUser)) {
                $status = '[set]'; $color = 'Green'
            } elseif ($fromFile) {
                $status = '[.env]'; $color = 'DarkYellow'
            } else {
                $status = '[empty]'; $color = 'DarkGray'
            }

            Write-Host ("  {0,-15} {1,-24} {2,-10} {3}" -f $provider, $varName, $status, $note) -ForegroundColor $color
        }
        Write-Host ''
    }

    Write-Host '  OAuth providers (no key needed, use /login in pi):' -ForegroundColor DarkGray
    Write-Host '    anthropic          /login anthropic' -ForegroundColor White
    Write-Host '    github-copilot     /login github-copilot   (needs Copilot subscription)' -ForegroundColor White
    Write-Host '    google-gemini-cli  /login google-gemini-cli (free via Cloud Code Assist)' -ForegroundColor White
    Write-Host '    openai-codex       /login openai-codex      (free via ChatGPT OAuth -- planning only)' -ForegroundColor White
    Write-Host ''
    Write-Host '  Search provider active in pi: /search-provider [tavily|brave|ollama|auto]' -ForegroundColor DarkGray
    Write-Host '  Set key first: 8sync gsd key tavily <key>   then /search-provider tavily' -ForegroundColor DarkGray
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
    [System.Environment]::SetEnvironmentVariable($envVarName, $Key, 'Process')
    [System.Environment]::SetEnvironmentVariable($envVarName, $Key, 'User')

    $agentDir = Resolve-GsdAgentDir
    $envFile = Join-Path $agentDir '.env'
    try {
        if (-not (Test-Path $agentDir)) { $null = New-Item -Path $agentDir -ItemType Directory -Force }
        $newLine = '{0}={1}' -f $envVarName, $Key
        if (Test-Path $envFile) {
            $lines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
            $replaced = $false
            $newLines = $lines | ForEach-Object {
                if ($_ -match ('^' + [regex]::Escape($envVarName) + '\s*=')) {
                    $replaced = $true
                    $newLine
                } else {
                    $_
                }
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

function Show-GsdGuide {
    $guidePath = Join-Path $PSScriptRoot 'docs/gsd-pi-vi.md'
    if (-not (Test-Path $guidePath)) {
        Write-Host ''
        Write-Host "  [gsd] Guide not found: $guidePath" -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host ''
    # Prefer glow > bat > mdcat > raw
    $renderer = $null
    foreach ($cmd in @('glow', 'bat', 'mdcat')) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { $renderer = $cmd; break }
    }

    switch ($renderer) {
        'glow'  { & glow -p $guidePath }
        'bat'   { & bat --style=plain --paging=always --language=markdown $guidePath }
        'mdcat' { & mdcat $guidePath }
        default {
            # Fallback: colorised pretty-print in PowerShell
            Get-Content $guidePath -Encoding UTF8 | ForEach-Object {
                $line = $_
                if ($line -match '^# ')       { Write-Host $line -ForegroundColor Magenta }
                elseif ($line -match '^## ')  { Write-Host $line -ForegroundColor Cyan }
                elseif ($line -match '^### ') { Write-Host $line -ForegroundColor Yellow }
                elseif ($line -match '^\s*\| ') { Write-Host $line -ForegroundColor Gray }
                elseif ($line -match '^\s*```') { Write-Host $line -ForegroundColor DarkGray }
                elseif ($line -match '^\s*>') { Write-Host $line -ForegroundColor DarkCyan }
                elseif ($line -match '^\s*[-*] ') { Write-Host $line -ForegroundColor White }
                elseif ($line -match '^\s*\d+\. ') { Write-Host $line -ForegroundColor White }
                else { Write-Host $line -ForegroundColor Gray }
            }
            Write-Host ''
            Write-Host '  Tip: install `glow` (scoop install glow) for prettier rendering.' -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    Write-Host "  File: $guidePath" -ForegroundColor DarkGray
    Write-Host ''
}

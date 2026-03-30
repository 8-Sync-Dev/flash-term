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
    Write-HintRow 'normal'               'No Claude cost: gemini plan + glm-5.1 exec + groq (codex planning only)'
    Write-Host ''
    Write-Host '  -- Single-provider (one ecosystem only) --------------------------------' -ForegroundColor DarkGray
    Write-HintRow 'claude-max'           '100% Claude: Opus plan + Sonnet exec + Haiku workers'
    Write-HintRow 'codex-max'            '100% OpenAI: gpt-5.4 plan + gpt-5.3-codex exec'
    Write-HintRow 'gemini-max'           '100% Google: gemini-3.1-pro plan+exec (2M ctx, free)'
    Write-HintRow 'glm-max'              '100% ZAI: glm-5.1 plan/exec + glm-4.5(c20) subagent — no OAuth needed'
    Write-Host ''
    Write-Host '  -- The Big Three combo (best of all worlds) ----------------------------' -ForegroundColor DarkGray
    Write-HintRow 'claude-codex-gemini'  'Opus plan + codex exec + gemini research -- best of all three'
    Write-Host ''
    Write-Host '  -- Interactive picker --------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  8sync gsd setup --pick    Select providers with fzf -> auto-derive plan' -ForegroundColor White
    Write-Host ''
    Write-Host '  -- Required logins per plan --------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  max                : /login anthropic  github-copilot  google-gemini-cli  openai-codex' -ForegroundColor White
    Write-Host '                       + 8sync gsd key kimi-coding  zai  groq' -ForegroundColor DarkGray
    Write-Host '  pro                : /login anthropic  google-gemini-cli  openai-codex' -ForegroundColor White
    Write-Host '                       + 8sync gsd key kimi-coding  zai  groq' -ForegroundColor DarkGray
    Write-Host '  normal             : /login google-gemini-cli  openai-codex (planning)' -ForegroundColor White
    Write-Host '                       + 8sync gsd key zai  groq' -ForegroundColor DarkGray
    Write-Host '  claude-max         : /login anthropic  (Opus+Sonnet+Haiku only)' -ForegroundColor White
    Write-Host '  codex-max          : /login openai-codex  (gpt-5.x only)' -ForegroundColor White
    Write-Host '  gemini-max         : /login google-gemini-cli  (gemini-3.1-pro free)' -ForegroundColor White
    Write-Host '  claude-codex-gemini: /login anthropic  openai-codex  google-gemini-cli' -ForegroundColor White
    Write-Host ''
    Write-Host '  Apply: 8sync gsd setup --plan <name>' -ForegroundColor DarkGray
    Write-Host '  Pick:  8sync gsd setup --pick' -ForegroundColor DarkGray
    Write-Host '  Check: /gsd prefs   /model' -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Interactive plan picker — fzf provider multi-select -> generate PREFERENCES.md
# ---------------------------------------------------------------------------

# Provider catalogue: id | label | description | type
$script:GsdProviderMenu = @(
    [pscustomobject]@{ Id='anthropic';         Label='Anthropic Claude';        Desc='claude-opus-4-6 (plan/research) + sonnet-4-6 (exec) + haiku-4-5 (simple/subagent)';  Type='oauth' }
    [pscustomobject]@{ Id='github-copilot';    Label='GitHub Copilot';          Desc='gemini-3.1-pro-preview 80.6% SWE + gpt-5-codex (needs Copilot subscription)';        Type='oauth' }
    [pscustomobject]@{ Id='google-gemini-cli'; Label='Google Gemini CLI';       Desc='gemini-3.1-pro-preview FREE 80.6% SWE, 2M ctx (Cloud Code Assist)';                  Type='oauth' }
    [pscustomobject]@{ Id='openai-codex';      Label='OpenAI Codex (OAuth)';    Desc='gpt-5.3-codex FREE via ChatGPT — PLANNING ONLY (hits rate-limit during exec)';       Type='oauth' }
    [pscustomobject]@{ Id='zai';               Label='ZAI (z.ai) API key';      Desc='glm-5.1(exec,S+) glm-4.6v(vision+video,$0.30/M,c10) glm-4.5(c20) cascade $0.06-$4/M'; Type='key'   }
    [pscustomobject]@{ Id='groq';              Label='Groq API key';            Desc='kimi-k2-instruct + qwen3-32b FREE daily reset — cheap subagent/simple tier';         Type='key'   }
    [pscustomobject]@{ Id='kimi-coding';       Label='Kimi Coding API key';     Desc='Kimi K2.5 ~77% SWE ($0.14/$2.5/M) — top exec/subagent for cost-perf';               Type='key'   }
)

# ─────────────────────────────────────────────────────────────────────────────
# Generate a PREFERENCES.md models block from selected provider IDs.
# Logic: highest-capability providers go into planning/research,
#        best agentic exec models go into execution/subagent,
#        cheapest/free models fill simple/completion fallbacks.
#        openai-codex is ONLY used in planning/research (never exec/subagent).
# ─────────────────────────────────────────────────────────────────────────────
function Build-GsdModelsYaml {
    param([string[]]$Selected)

    $has = @{}
    foreach ($s in $Selected) { $has[$s] = $true }

    $hasAnthropic = $has['anthropic']  -eq $true
    $hasCopilot   = $has['github-copilot'] -eq $true
    $hasGemini    = $has['google-gemini-cli'] -eq $true
    $hasCodex     = $has['openai-codex'] -eq $true
    $hasZai       = $has['zai'] -eq $true
    $hasGroq      = $has['groq'] -eq $true
    $hasKimi      = $has['kimi-coding'] -eq $true

    # ── Resolve per-role model lists ─────────────────────────────────────────
    # Each list is ordered: [primary, fallback1, fallback2, ...]
    # Rules:
    #   planning/research  — frontier first (Opus > gemini > copilot/gemini > codex), then zai
    #   execution          — best agentic exec: kimi > glm-5.1 > glm-5-turbo > sonnet > haiku
    #                        codex NOT here (rate-limit pause bug)
    #   execution_simple   — cheapest reliable: groq > glm-4.x > haiku
    #   completion         — quality summary: sonnet > glm-5.1 > haiku > groq
    #   subagent           — parallel workers: kimi > glm-5.x > groq > haiku
    #                        codex NOT here (same reason)
    #   validation         — falls back to planning chain (pi default: m.validation ?? m.planning)

    $planModels     = [System.Collections.Generic.List[string]]::new()
    $researchModels = [System.Collections.Generic.List[string]]::new()
    $execModels     = [System.Collections.Generic.List[string]]::new()
    $simpleModels   = [System.Collections.Generic.List[string]]::new()
    $compModels     = [System.Collections.Generic.List[string]]::new()
    $subModels      = [System.Collections.Generic.List[string]]::new()

    # planning / research — frontier depth first
    if ($hasAnthropic)  { $planModels.Add('anthropic/claude-opus-4-6');           $researchModels.Add('anthropic/claude-opus-4-6') }
    if ($hasCopilot)    { $planModels.Add('github-copilot/gemini-3.1-pro-preview'); $researchModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini)     { $planModels.Add('google-gemini-cli/gemini-3.1-pro-preview'); $researchModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasAnthropic)  { $planModels.Add('anthropic/claude-sonnet-4-6');          $researchModels.Add('anthropic/claude-sonnet-4-6') }
    if ($hasCodex)      { $planModels.Add('openai-codex/gpt-5.3-codex');           $researchModels.Add('openai-codex/gpt-5.3-codex') }  # planning only
    if ($hasZai)        { $planModels.Add('zai/glm-5.1');                          $researchModels.Add('zai/glm-5.1') }
    if ($hasZai)        { $planModels.Add('zai/glm-5-turbo') }
    if ($hasGroq)       { $planModels.Add('groq/kimi-k2-instruct') }

    # execution — best agentic exec (NO codex)
    if ($hasKimi)       { $execModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasZai)        { $execModels.Add('zai/glm-5.1'); $execModels.Add('zai/glm-5-turbo'); $execModels.Add('zai/glm-5') }
    if ($hasKimi -and -not $execModels.Contains('kimi-coding/kimi-k2.5')) { $execModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasAnthropic)  { $execModels.Add('anthropic/claude-sonnet-4-6') }
    if ($hasCopilot)    { $execModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini -and -not ($hasCopilot)) { $execModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasGroq)       { $execModels.Add('groq/kimi-k2-instruct') }
    if ($hasAnthropic)  { $execModels.Add('anthropic/claude-haiku-4-5') }

    # execution_simple — cheapest first (NO codex)
    if ($hasGroq)       { $simpleModels.Add('groq/kimi-k2-instruct'); $simpleModels.Add('groq/qwen/qwen3-32b') }
    if ($hasZai)        { $simpleModels.Add('zai/glm-4.7'); $simpleModels.Add('zai/glm-4.7-flash'); $simpleModels.Add('zai/glm-4.6') }
    if ($hasKimi)       { $simpleModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasAnthropic)  { $simpleModels.Add('anthropic/claude-haiku-4-5') }
    if ($hasGemini -and $simpleModels.Count -eq 0) { $simpleModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }

    # completion — quality summary
    if ($hasAnthropic)  { $compModels.Add('anthropic/claude-sonnet-4-6') }
    if ($hasZai)        { $compModels.Add('zai/glm-5.1'); $compModels.Add('zai/glm-5-turbo') }
    if ($hasKimi)       { $compModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasGemini)     { $compModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasCopilot)    { $compModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGroq)       { $compModels.Add('groq/kimi-k2-instruct') }
    if ($hasAnthropic)  { $compModels.Add('anthropic/claude-haiku-4-5') }

    # subagent — parallel workers (NO codex)
    if ($hasKimi)       { $subModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasZai)        { $subModels.Add('zai/glm-5.1'); $subModels.Add('zai/glm-5-turbo'); $subModels.Add('zai/glm-5') }
    if ($hasGroq)       { $subModels.Add('groq/kimi-k2-instruct'); $subModels.Add('groq/qwen/qwen3-32b') }
    if ($hasZai)        { $subModels.Add('zai/glm-4.7'); $subModels.Add('zai/glm-4.7-flash') }
    if ($hasAnthropic)  { $subModels.Add('anthropic/claude-haiku-4-5') }
    if ($hasCopilot)    { $subModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini -and -not $hasCopilot) { $subModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }

    # ── Deduplicate while preserving order ────────────────────────────────────
    function Dedupe-List { param($list)
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $list | Where-Object { $seen.Add($_) }
    }
    $planModels     = @(Dedupe-List $planModels)
    $researchModels = @(Dedupe-List $researchModels)
    $execModels     = @(Dedupe-List $execModels)
    $simpleModels   = @(Dedupe-List $simpleModels)
    $compModels     = @(Dedupe-List $compModels)
    $subModels      = @(Dedupe-List $subModels)

    # ── Sanity: must have at least one model per role ─────────────────────────
    if ($planModels.Count -eq 0 -or $execModels.Count -eq 0) {
        return $null  # caller will abort
    }

    # ── Render YAML block ─────────────────────────────────────────────────────
    function Format-ModelBlock {
        param([string]$Role, [string[]]$Models)
        if ($Models.Count -eq 0) { return }
        $lines = @("  ${Role}:")
        $lines += "    model: $($Models[0])"
        if ($Models.Count -gt 1) {
            $lines += '    fallbacks:'
            for ($i = 1; $i -lt $Models.Count; $i++) {
                $lines += "      - $($Models[$i])"
            }
        }
        $lines -join "`n"
    }

    # Build provider summary comment
    $providerList = $Selected -join ', '
    $planLabel = if ($planModels.Count -gt 0) { $planModels[0] } else { 'none' }
    $execLabel = if ($execModels.Count -gt 0) { $execModels[0] } else { 'none' }

    $codexNote = if ($hasCodex) {
        "`n  # NOTE: openai-codex is in planning/research only — NOT in exec/subagent/completion`n  #   (usage-limit error pauses auto-mode indefinitely instead of continuing fallback chain)"
    } else { '' }

    $yaml = @"
  # ══════════════════════════════════════════════════════════════════════════════
  # PLAN: custom (generated by 8sync gsd setup --pick)
  # Providers: $providerList
  # planning  → $planLabel
  # execution → $execLabel
  # Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')$codexNote
  # ══════════════════════════════════════════════════════════════════════════════

$(Format-ModelBlock 'planning'         $planModels)

$(Format-ModelBlock 'research'         $researchModels)

$(Format-ModelBlock 'execution'        $execModels)

$(Format-ModelBlock 'execution_simple' $simpleModels)

$(Format-ModelBlock 'completion'       $compModels)

$(Format-ModelBlock 'subagent'         $subModels)
"@

    return $yaml.TrimEnd()
}

# ─────────────────────────────────────────────────────────────────────────────
# Write generated models block into ~/.gsd/PREFERENCES.md
# Replaces the models: ... section while keeping the YAML front-matter header.
# ─────────────────────────────────────────────────────────────────────────────
function Write-GsdPreferencesModels {
    param(
        [Parameter(Mandatory)] [string]$ModelsYaml,
        [string]$DestPath,
        [switch]$DryRun
    )

    $gsdHome = Resolve-GsdHome
    if (-not $DestPath) { $DestPath = Join-Path $gsdHome 'PREFERENCES.md' }

    # Template header (everything before models:)
    $header = @'
---
version: 1
skill_staleness_days: 0
uat_dispatch: false
unique_milestone_ids: false
notifications:
cmux:
  enabled: false
  notifications: false
  sidebar: false
  splits: false
  browser: false
remote_questions:
phases:
  skip_research: false
  skip_reassess: false
  skip_slice_research: false
  reassess_after_slice: false

token_profile: balanced

models:
'@

    $footer = @'


---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.
'@

    # If existing file has custom header settings, preserve them
    if (Test-Path $DestPath) {
        $existing = Get-Content $DestPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        # Extract everything from --- to "models:" line, keep it
        if ($existing -match '(?s)(^---.*?token_profile:.*?\n\nmodels:\n)') {
            $header = $matches[1]
        }
    }

    $newContent = $header + "`n" + $ModelsYaml + $footer

    if ($DryRun) {
        Write-Host ''
        Write-Host '  [dry-run] Would write:' -ForegroundColor Yellow
        Write-Host ("  {0}" -f $DestPath) -ForegroundColor DarkGray
        Write-Host ''
        $newContent -split "`n" | Select-Object -First 60 | ForEach-Object {
            Write-Host ("  {0}" -f $_) -ForegroundColor DarkGray
        }
        Write-Host '  ... (truncated)' -ForegroundColor DarkGray
        Write-Host ''
        return $true
    }

    $dir = Split-Path $DestPath -Parent
    if (-not (Test-Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }

    try {
        Set-Content -Path $DestPath -Value $newContent -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Host ("  [error] write failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
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

    # ── Detect current auth/key state ────────────────────────────────────────
    $agentDir = Resolve-GsdAgentDir
    $authPath = Join-Path $agentDir 'auth.json'
    $loggedIn = @{}
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $now  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $auth.PSObject.Properties | ForEach-Object {
                $exp = $_.Value.expires
                if (-not $exp -or ([long]$exp - $now) -gt 0) { $loggedIn[$_.Name] = $true }
            }
        } catch {}
    }

    $envFileLines = @()
    $envFile = Join-Path $agentDir '.env'
    if (Test-Path $envFile) { $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue }

    function Test-ProviderConfigured {
        param($p)
        if ($p.Type -eq 'oauth') { return $loggedIn[$p.Id] -eq $true }
        $varName = $script:GsdProviderKeys[$p.Id]
        return (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName,'Process'))) -or
               (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName,'User'))) -or
               ($null -ne ($envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1))
    }

    # ── Build fzf input ──────────────────────────────────────────────────────
    # Format: "ID\tSTATUS_LABEL  FULL_LABEL\tDESC"
    # Pre-configured providers sort to top
    $preConfigured = @($script:GsdProviderMenu | Where-Object { Test-ProviderConfigured $_ } | ForEach-Object { $_.Id })

    $fzfLines = $script:GsdProviderMenu | Sort-Object {
        if ($preConfigured -contains $_.Id) { 0 } else { 1 }
    } | ForEach-Object {
        $p = $_
        $configured = Test-ProviderConfigured $p
        if ($p.Type -eq 'oauth') {
            $status = if ($configured) { '[✓ logged in ]' } else { '[ not logged  ]' }
        } else {
            $status = if ($configured) { '[✓ key set   ]' } else { '[ no key      ]' }
        }
        "$($p.Id)`t$status  $($p.Label)`t$($p.Desc)"
    }

    $headerLine = "SPACE=toggle  ENTER=apply  (pre-configured shown first)"
    $fzfArgs = @(
        '--multi'
        '--delimiter', "`t"
        '--with-nth', '2,3'
        '--header', $headerLine
        '--prompt', '  Provider> '
        '--height', '~85%'
        '--border', 'rounded'
        '--bind', 'tab:toggle+down'
        '--bind', 'shift-tab:toggle+up'
    )

    $chosen = $fzfLines | fzf @fzfArgs
    if (-not $chosen) {
        Write-Host '  [cancelled]' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $selectedIds = @($chosen | ForEach-Object { ($_ -split "`t")[0].Trim() })

    Write-Host ''
    Write-Host '  Selected providers:' -ForegroundColor DarkGray
    foreach ($id in $selectedIds) {
        $mark = if ($preConfigured -contains $id) { '✓' } else { '+' }
        Write-Host ("    {0} {1}" -f $mark, $id) -ForegroundColor $(if ($preConfigured -contains $id) { 'Green' } else { 'Yellow' })
    }
    Write-Host ''

    # ── Generate models YAML ──────────────────────────────────────────────────
    $yaml = Build-GsdModelsYaml -Selected $selectedIds
    if (-not $yaml) {
        Write-Host '  [error] Selection produced no models. Select at least one exec provider (zai, groq, kimi-coding, or anthropic).' -ForegroundColor Red
        Write-Host ''
        return
    }

    # Preview top of generated block
    Write-Host '  Generated model routing:' -ForegroundColor Cyan
    $yaml -split "`n" | Select-Object -First 20 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
    if (($yaml -split "`n").Count -gt 20) { Write-Host '    ...' -ForegroundColor DarkGray }
    Write-Host ''

    # ── Write to ~/.gsd/PREFERENCES.md ───────────────────────────────────────
    $gsdHome = Resolve-GsdHome
    $destPath = Join-Path $gsdHome 'PREFERENCES.md'
    $ok = Write-GsdPreferencesModels -ModelsYaml $yaml -DestPath $destPath -DryRun:$DryRun

    if ($ok -and -not $DryRun) {
        Write-Host ("  [ok] {0}" -f $destPath) -ForegroundColor Green
        Write-Host ''
        Write-Host '  Next: /gsd prefs to verify   /model to browse available models' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Show-GsdHelp {
    Write-Host ''
    Write-HintSection 'GSD -- Model routing setup'
    Write-HintRow '8sync gsd setup'                      'Apply default PREFERENCES.md -> ~/.gsd'
    Write-HintRow '8sync gsd setup --plan <name>'        'Apply named plan (see below)'
    Write-HintRow '8sync gsd setup --plan'               'List all plans with descriptions'
    Write-HintRow '8sync gsd setup --auto'               'Auto-detect valid logins/keys -> generate PREFERENCES.md'
    Write-HintRow '8sync gsd setup --pick'               'Interactive fzf: pick providers -> generate PREFERENCES.md'
    Write-HintRow '8sync gsd setup --dry-run'            'Preview without writing'
    Write-HintRow '8sync gsd key <provider> <key>'       'Set API key — LLM: zai kimi-coding groq google openai xai mistral'
    Write-HintRow '                                  '    'Search: tavily brave ollama  |  Tools: context7 jina'
    Write-HintRow '8sync gsd keys'                       'List all providers grouped (LLM / Search / Tools) + status'
    Write-HintRow '8sync gsd status'                     'Show paths, auth providers, key status'
    Write-HintRow '8sync gsd add gguf'                   'Detect running llama-server and register it in models.json'
    Write-HintRow '8sync gsd add gguf --port N'          'Target a specific port (default: probe 8080/8081/8082/1234/11434)'
    Write-HintRow '8sync gsd add gguf --name <id>'       'Override provider id (default: gguf-local-<model>)'
    Write-HintRow '8sync gsd add gguf --dry-run'         'Preview without writing models.json'
    Write-HintRow '8sync gsd remove gguf'                'Remove all gguf-local-* providers from models.json'
    Write-HintRow '8sync gsd remove gguf --name <id>'    'Remove a specific provider by id'
    Write-HintRow '8sync gsd help'                       'Show this help'
    Write-Host ''
    Write-HintSection 'Plans (multi-provider)'
    Write-HintRow 'max'    'Opus plan + kimi K2.5 exec (SWE 76.8%) + groq free workers'
    Write-HintRow 'pro'    'Sonnet plan/completion + kimi+codex exec + groq free'
    Write-HintRow 'normal' 'No Claude: gemini plan + glm-5.1 exec + groq (codex planning only)'
    Write-HintRow 'glm-max'    '100% ZAI: glm-5.1 plan/exec + glm-4.5(c20) subagent workers'
    Write-HintSection 'Plans (single-provider)'
    Write-HintRow 'claude-max'  '100% Claude: Opus plan + Sonnet exec + Haiku workers'
    Write-HintRow 'codex-max'   '100% OpenAI: gpt-5.4 plan + gpt-5.3-codex exec'
    Write-HintRow 'gemini-max'  '100% Google: gemini-3.1-pro plan+exec (2M ctx, free)'
    Write-HintSection 'Plans (combo)'
    Write-HintRow 'claude-codex-gemini' 'Big Three: Opus plan + codex exec + gemini research'
    Write-Host ''
    Write-Host '  Interactive: 8sync gsd setup --auto   (auto-detect, no interaction)' -ForegroundColor DarkGray
    Write-Host '               8sync gsd setup --pick   (fzf provider picker)' -ForegroundColor DarkGray
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
    $validPlans = @('max', 'pro', 'normal', 'claude-max', 'codex-max', 'gemini-max', 'claude-codex-gemini', 'glm-max')
    $planLower  = $Plan.ToLowerInvariant().Trim()

    if ($planLower -ne '' -and $validPlans -notcontains $planLower) {
        Write-Host ''
        Write-Host ("  [error] Unknown plan '{0}'." -f $Plan) -ForegroundColor Red
        Write-Host '  Valid: max | pro | normal | claude-max | codex-max | gemini-max | claude-codex-gemini | glm-max' -ForegroundColor DarkGray
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
            'glm-max' {
                Write-Host '  8sync gsd key zai <key>  (only requirement)' -ForegroundColor Yellow
                Write-Host '  Models : glm-5.1 plan/exec + glm-4.5(c20) subagent -> full cascade' -ForegroundColor DarkGray
                Write-Host '  100% ZAI -- no OAuth, no other providers' -ForegroundColor DarkGray
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
    # LLM providers
    'zai'          = 'ZAI_API_KEY'
    'kimi-coding'  = 'KIMI_API_KEY'
    'groq'         = 'GROQ_API_KEY'
    'google'       = 'GEMINI_API_KEY'
    'openrouter'   = 'OPENROUTER_API_KEY'
    'anthropic'    = 'ANTHROPIC_API_KEY'
    'openai'       = 'OPENAI_API_KEY'
    'xai'          = 'XAI_API_KEY'
    'mistral'      = 'MISTRAL_API_KEY'
    # Search providers (pi reads these via process.env — same mechanism)
    'tavily'       = 'TAVILY_API_KEY'
    'brave'        = 'BRAVE_API_KEY'
    'ollama'       = 'OLLAMA_API_KEY'
    # Tool keys
    'context7'     = 'CONTEXT7_API_KEY'
    'jina'         = 'JINA_API_KEY'
}

# Human-readable notes shown in 8sync gsd keys
$script:GsdProviderNotes = @{
    'zai'          = 'z.ai — glm-5.1(S+) glm-5-turbo(c1) glm-5(c2) glm-4.7(c2) glm-4.5(c20) glm-4.6v(vision,c10,$0.30) glm-4.5v(vision,c10,$0.60)'
    'kimi-coding'  = 'platform.moonshot.cn — Kimi K2.5 SWE 76.8% ($0.14/$2.5/M)'
    'groq'         = 'console.groq.com — kimi-k2+qwen3-32b FREE daily reset'
    'google'       = 'aistudio.google.com — gemini-2.5-pro API key (5RPM free tier)'
    'openrouter'   = 'openrouter.ai — DeepSeek V3.2($0.28/$0.42) R1 + 200+ models, free tier có'
    'anthropic'    = 'console.anthropic.com — paid key OR /login OAuth'
    'openai'       = 'platform.openai.com — paid key OR /login openai-codex (free)'
    'xai'          = 'console.x.ai — grok-4 free credits on signup'
    'mistral'      = 'console.mistral.ai — pixtral-large, free tier'
    'tavily'       = 'tavily.com/app/api-keys — web search, 1000 free/mo | /search-provider tavily'
    'brave'        = 'brave.com/search/api — web search, 2000 free/mo | /search-provider brave'
    'ollama'       = 'local Ollama server token (optional) | /search-provider ollama'
    'context7'     = 'context7.com/dashboard — doc lookup (already bundled in pi)'
    'jina'         = 'jina.ai/api — fetch_page/web reader (optional, higher rate limit)'
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

    $groups = [ordered]@{
        'LLM Providers'    = @('zai','kimi-coding','groq','google','openrouter','anthropic','openai','xai','mistral')
        'Search Providers' = @('tavily','brave','ollama')
        'Tool Keys'        = @('context7','jina')
    }

    foreach ($groupName in $groups.Keys) {
        Write-Host ("  -- {0} {1}" -f $groupName, ('-' * (50 - $groupName.Length))) -ForegroundColor DarkGray
        Write-Host ("  {0,-15} {1,-24} {2,-10} {3}" -f 'PROVIDER','ENV VAR','STATUS','NOTES / WHERE TO GET') -ForegroundColor DarkGray

        foreach ($provider in $groups[$groupName]) {
            $varName  = $script:GsdProviderKeys[$provider]
            $note     = if ($script:GsdProviderNotes.ContainsKey($provider)) { $script:GsdProviderNotes[$provider] } else { '' }
            $fromEnv  = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
            $fromUser = [System.Environment]::GetEnvironmentVariable($varName, 'User')
            $fromFile = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1

            if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
                $status = '[set]';       $color = 'Green'
            } elseif (-not [string]::IsNullOrWhiteSpace($fromUser)) {
                $status = '[set]';       $color = 'Green'
            } elseif ($fromFile) {
                $status = '[.env]';      $color = 'DarkYellow'
            } else {
                $status = '[empty]';     $color = 'DarkGray'
            }

            Write-Host ("  {0,-15} {1,-24} {2,-10} {3}" -f $provider, $varName, $status, $note) -ForegroundColor $color
        }
        Write-Host ''
    }

    Write-Host '  OAuth providers (no key needed, use /login in pi):' -ForegroundColor DarkGray
    Write-Host '    anthropic          /login anthropic' -ForegroundColor White
    Write-Host '    github-copilot     /login github-copilot   (needs Copilot subscription)' -ForegroundColor White
    Write-Host '    google-gemini-cli  /login google-gemini-cli (free via Cloud Code Assist)' -ForegroundColor White
    Write-Host '    openai-codex       /login openai-codex      (free via ChatGPT OAuth — planning only)' -ForegroundColor White
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
        foreach ($p in @('max','pro','normal','claude-max','codex-max','gemini-max','claude-codex-gemini','glm-max')) {
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

# ---------------------------------------------------------------------------
# GSD gguf provider management
# ---------------------------------------------------------------------------

function Get-GsdModelsJsonPath {
    $agentDir = Resolve-GsdAgentDir
    return Join-Path $agentDir 'models.json'
}

function Read-GsdModelsJson {
    $path = Get-GsdModelsJsonPath
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Warning "gsd: cannot parse models.json -- $_"; return $null }
}

function Write-GsdModelsJson {
    param([object]$Data)
    $path = Get-GsdModelsJsonPath
    # Preserve as tidy JSON — Depth 10 handles nested model arrays
    $Data | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
}

function Probe-GgufServer {
    # Try common llama-server ports. Returns first live server info or $null.
    param([string]$Port = '')

    $ports = if ($Port) { @([int]$Port) } else { @(8080, 8081, 8082, 1234, 11434) }

    foreach ($p in $ports) {
        try {
            $resp = Invoke-RestMethod "http://localhost:$p/v1/models" `
                        -TimeoutSec 3 -ErrorAction Stop
            return [pscustomobject]@{
                Port    = $p
                BaseUrl = "http://localhost:$p/v1"
                Models  = @($resp.data)
            }
        } catch {}
    }
    return $null
}

function Invoke-GsdAddGguf {
    param([string[]]$Rest)

    $dryRun    = $Rest -contains '--dry-run'
    $portArg   = ''
    $nameArg   = ''           # optional provider id override
    $roleArg   = ''           # optional: plan|exec|worker (wires into PREFERENCES)

    for ($i = 0; $i -lt $Rest.Count; $i++) {
        switch ($Rest[$i]) {
            '--port'   { $portArg  = $Rest[++$i] }
            '--name'   { $nameArg  = $Rest[++$i] }
            '--role'   { $roleArg  = $Rest[++$i] }
        }
    }

    Write-Host ''
    Write-HintSection 'GSD -- Add GGUF server as provider'
    Write-Host ''

    # ── Probe server ──────────────────────────────────────────────────────────
    Write-Host '  Probing llama-server on localhost...' -ForegroundColor DarkGray
    $server = Probe-GgufServer -Port $portArg
    if (-not $server) {
        $tried = if ($portArg) { "port $portArg" } else { 'ports 8080, 8081, 8082, 1234, 11434' }
        Write-Host ''
        Write-Host ("  [!!] No llama-server found on {0}." -f $tried) -ForegroundColor Red
        Write-Host '       Start one first:  8sync gguf serve --profile <name>' -ForegroundColor DarkGray
        Write-Host '       Then retry:       8sync gsd add gguf' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ("  [OK] Server found on port {0}  ->  {1}" -f $server.Port, $server.BaseUrl) -ForegroundColor Green
    Write-Host ''

    # ── List models from server ───────────────────────────────────────────────
    $models = $server.Models
    if (-not $models -or $models.Count -eq 0) {
        Write-Host '  [!!] Server returned no models from /v1/models.' -ForegroundColor Red
        return
    }

    Write-Host ("  Models available on server ({0}):" -f $models.Count) -ForegroundColor DarkGray
    foreach ($m in $models) {
        $mid = if ($m.id) { $m.id } else { $m }
        Write-Host ("    {0}" -f $mid) -ForegroundColor White
    }
    Write-Host ''

    # ── Build provider entry ──────────────────────────────────────────────────
    # Provider id: user-supplied or derived from first model filename stem
    $firstModelId = if ($models[0].id) { $models[0].id } else { [string]$models[0] }
    $stem         = [System.IO.Path]::GetFileNameWithoutExtension($firstModelId) -replace '[^a-zA-Z0-9\-]', '-'
    $providerId   = if ($nameArg) { $nameArg } else { "gguf-local-$stem" }

    # Build models array — one entry per model reported by the server
    $modelEntries = foreach ($m in $models) {
        $mid   = if ($m.id)   { $m.id }   else { [string]$m }
        $mname = if ($m.name) { $m.name } else {
            [System.IO.Path]::GetFileNameWithoutExtension($mid)
        }
        [pscustomobject]@{
            id            = $mid
            name          = "$mname (local GGUF)"
            reasoning     = $false
            input         = @('text')
            cost          = [pscustomobject]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
            contextWindow = 32768
            maxTokens     = 8192
        }
    }

    $providerEntry = [pscustomobject]@{
        baseUrl = $server.BaseUrl
        api     = 'openai-completions'
        models  = @($modelEntries)
    }

    # ── Load and patch models.json ────────────────────────────────────────────
    $data = Read-GsdModelsJson
    if (-not $data) {
        $data = [pscustomobject]@{ providers = [pscustomobject]@{} }
    }
    if (-not $data.PSObject.Properties['providers']) {
        $data | Add-Member -NotePropertyName 'providers' -NotePropertyValue ([pscustomobject]@{})
    }

    $alreadyExists = $data.providers.PSObject.Properties[$providerId] -ne $null

    Write-Host ("  Provider id : {0}" -f $providerId)          -ForegroundColor Cyan
    Write-Host ("  Base URL    : {0}" -f $server.BaseUrl)       -ForegroundColor DarkGray
    Write-Host ("  Models      : {0}" -f ($modelEntries | ForEach-Object { $_.id }) -join ', ') -ForegroundColor DarkGray
    if ($alreadyExists) {
        Write-Host ("  (overwriting existing provider '{0}')" -f $providerId) -ForegroundColor DarkYellow
    }
    Write-Host ''

    if ($dryRun) {
        Write-Host '  [dry-run] models.json not modified. Remove --dry-run to apply.' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    $data.providers | Add-Member -NotePropertyName $providerId -NotePropertyValue $providerEntry -Force
    Write-GsdModelsJson $data

    $mjPath = Get-GsdModelsJsonPath
    Write-Host ("  [OK] Written to {0}" -f $mjPath) -ForegroundColor Green
    Write-Host ''
    Write-Host '  Next steps:' -ForegroundColor DarkGray
    Write-Host ("    /model  to browse and select the new model in pi/GSD") -ForegroundColor DarkGray
    Write-Host ("    8sync gsd status  to verify provider is visible") -ForegroundColor DarkGray
    if ($roleArg) {
        Write-Host ("    --role '{0}' noted -- wire manually in PREFERENCES.md for now" -f $roleArg) -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Invoke-GsdRemoveGguf {
    param([string[]]$Rest)

    $dryRun  = $Rest -contains '--dry-run'
    $nameArg = ''
    for ($i = 0; $i -lt $Rest.Count; $i++) {
        if ($Rest[$i] -eq '--name') { $nameArg = $Rest[++$i] }
    }

    $data = Read-GsdModelsJson
    if (-not $data) { Write-Warning 'gsd: models.json not found'; return }

    # Find gguf-local-* providers
    $ggufProviders = $data.providers.PSObject.Properties |
        Where-Object { $_.Name -like 'gguf-local-*' -or ($nameArg -and $_.Name -eq $nameArg) }

    if (-not $ggufProviders) {
        Write-Host '  No gguf-local-* providers found in models.json.' -ForegroundColor DarkGray
        Write-Host '  Add one first: 8sync gsd add gguf' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-HintSection 'GSD -- Remove GGUF provider'
    Write-Host ''

    foreach ($prop in $ggufProviders) {
        Write-Host ("  Removing: {0}  ->  {1}" -f $prop.Name, $prop.Value.baseUrl) -ForegroundColor Yellow
        if (-not $dryRun) {
            # PSObject can't remove properties directly — rebuild without the key
            $newProviders = [pscustomobject]@{}
            foreach ($p in $data.providers.PSObject.Properties) {
                if ($p.Name -ne $prop.Name) {
                    $newProviders | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
                }
            }
            $data.providers = $newProviders
        }
    }

    if ($dryRun) {
        Write-Host '  [dry-run] models.json not modified.' -ForegroundColor DarkYellow
    } else {
        Write-GsdModelsJson $data
        Write-Host ("  [OK] Updated {0}" -f (Get-GsdModelsJsonPath)) -ForegroundColor Green
    }
    Write-Host ''
}

function Invoke-GsdAutoSetup {
    param([switch]$DryRun)

    $agentDir = Resolve-GsdAgentDir
    $authPath = Join-Path $agentDir 'auth.json'
    $envFile  = Join-Path $agentDir '.env'

    Write-Host ''
    Write-Host '  [gsd] Auto-detecting valid providers...' -ForegroundColor Cyan
    Write-Host ''

    # ── Read auth.json OAuth state ───────────────────────────────────────────
    $validOAuth = @{}
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $now  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $auth.PSObject.Properties | ForEach-Object {
                $exp = $_.Value.expires
                $type = $_.Value.type
                if ($type -eq 'oauth') {
                    $valid = (-not $exp) -or (([long]$exp - $now) -gt 0)
                    if ($valid) { $validOAuth[$_.Name] = $true }
                    $status = if ($valid) { 'VALID' } else { 'expired' }
                    $mins = if ($exp) { "~{0}m" -f [math]::Round(([long]$exp - $now) / 60000) } else { '∞' }
                    $color = if ($valid) { 'Green' } else { 'DarkGray' }
                    Write-Host ("    oauth  {0,-26} {1} {2}" -f $_.Name, $status, $mins) -ForegroundColor $color
                }
            }
        } catch {
            Write-Host '  [warn] auth.json parse failed' -ForegroundColor DarkYellow
        }
    }

    # ── Read API keys from .env + user env ───────────────────────────────────
    $envFileLines = @()
    if (Test-Path $envFile) { $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue }

    $validKeys = @{}
    foreach ($provider in $script:GsdProviderKeys.Keys) {
        $varName = $script:GsdProviderKeys[$provider]
        $val = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
        if ([string]::IsNullOrWhiteSpace($val)) { $val = [System.Environment]::GetEnvironmentVariable($varName, 'User') }
        if ([string]::IsNullOrWhiteSpace($val)) {
            $line = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=\s*(.+)') } | Select-Object -First 1
            if ($line -match '=\s*(.+)$') { $val = $matches[1].Trim() }
        }
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $validKeys[$provider] = $true
            Write-Host ("    key    {0,-26} SET" -f "$provider ($varName)") -ForegroundColor Green
        }
    }

    # ── Map to provider IDs used by Build-GsdModelsYaml ─────────────────────
    # oauth providers:  anthropic, github-copilot, google-gemini-cli, openai-codex
    # key providers:    zai, kimi-coding, groq, google, ...

    $selected = [System.Collections.Generic.List[string]]::new()

    if ($validOAuth['anthropic'])          { $selected.Add('anthropic') }
    if ($validOAuth['github-copilot'])     { $selected.Add('github-copilot') }
    if ($validOAuth['google-gemini-cli'])  { $selected.Add('google-gemini-cli') }
    if ($validOAuth['openai-codex'])       { $selected.Add('openai-codex') }
    if ($validKeys['zai'])                 { $selected.Add('zai') }
    if ($validKeys['groq'])                { $selected.Add('groq') }
    if ($validKeys['kimi-coding'])         { $selected.Add('kimi-coding') }

    Write-Host ''
    if ($selected.Count -eq 0) {
        Write-Host '  [error] No valid providers detected. Login with /login or set keys with 8sync gsd key.' -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host '  Active providers:' -ForegroundColor DarkGray
    foreach ($p in $selected) {
        Write-Host ("    + {0}" -f $p) -ForegroundColor White
    }
    Write-Host ''

    # ── Generate + write ──────────────────────────────────────────────────────
    $yaml = Build-GsdModelsYaml -Selected $selected.ToArray()
    if (-not $yaml) {
        Write-Host '  [error] Could not generate model routing from detected providers.' -ForegroundColor Red
        Write-Host ''
        return
    }

    # Preview
    Write-Host '  Generated routing (top lines):' -ForegroundColor Cyan
    $yaml -split "`n" | Select-Object -First 12 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
    Write-Host '    ...' -ForegroundColor DarkGray
    Write-Host ''

    $gsdHome  = Resolve-GsdHome
    $destPath = Join-Path $gsdHome 'PREFERENCES.md'
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
    $planArg = ''
    $planIdx = [Array]::IndexOf($Rest, '--plan')
    if ($planIdx -ge 0) {
        if ($planIdx + 1 -lt $Rest.Count -and $Rest[$planIdx + 1] -notlike '--*') {
            $planArg = $Rest[$planIdx + 1]
        } else {
            Show-GsdPlans
            return
        }
    }

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { 'setup' }

    switch ($sub) {
        'setup'  {
            if ($autoMode)  { Invoke-GsdAutoSetup -DryRun:$dryRun }
            elseif ($pickMode) { Invoke-GsdPlanPicker -DryRun:$dryRun }
            else { Invoke-GsdSetup -DryRun:$dryRun -Plan $planArg }
        }
        'status' { Invoke-GsdStatus }
        'key'    { Invoke-GsdKey -Provider ($Rest | Select-Object -Skip 1 -First 1) -Key ($Rest | Select-Object -Skip 2 -First 1) }
        'keys'   { Show-GsdKeys }
        'add'    {
            $addSub = if ($Rest.Count -gt 1) { $Rest[1].ToLowerInvariant() } else { '' }
            switch ($addSub) {
                'gguf'   { Invoke-GsdAddGguf -Rest ($Rest | Select-Object -Skip 2) }
                default  { Write-Host '  Usage: 8sync gsd add gguf [--port N] [--name <id>] [--dry-run]' -ForegroundColor DarkGray }
            }
        }
        'remove' {
            $remSub = if ($Rest.Count -gt 1) { $Rest[1].ToLowerInvariant() } else { '' }
            switch ($remSub) {
                'gguf'   { Invoke-GsdRemoveGguf -Rest ($Rest | Select-Object -Skip 2) }
                default  { Write-Host '  Usage: 8sync gsd remove gguf [--name <id>]' -ForegroundColor DarkGray }
            }
        }
        'help'   { Show-GsdHelp }
        default  { Show-GsdHelp }
    }
}

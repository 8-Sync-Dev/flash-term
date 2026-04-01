# =============================================================================
# 8sync gsd -- preferences generation and setup flows
# =============================================================================


function Build-GsdModelsYaml {
    param(
        [string[]]$Selected,
        [switch]$Balance,       # sonnet first, opus last fallback (save cost)
        [string]$GgufRef = ''   # "provider/model" for running gguf server
    )

    $has = @{}
    foreach ($s in $Selected) { $has[$s] = $true }

    $hasAnthropic = $has['anthropic']         -eq $true
    $hasCopilot   = $has['github-copilot']    -eq $true
    $hasGemini    = $has['google-gemini-cli'] -eq $true
    $hasCodex     = $has['openai-codex']      -eq $true
    $hasZai       = $has['zai']               -eq $true
    $hasGroq      = $has['groq']              -eq $true
    $hasKimi      = $has['kimi-coding']       -eq $true
    $hasGguf      = $GgufRef -ne ''

    $plan  = [System.Collections.Generic.List[string]]::new()
    $rsrch = [System.Collections.Generic.List[string]]::new()
    $exec  = [System.Collections.Generic.List[string]]::new()
    $simp  = [System.Collections.Generic.List[string]]::new()
    $comp  = [System.Collections.Generic.List[string]]::new()
    $sub   = [System.Collections.Generic.List[string]]::new()

    # ── planning / research ───────────────────────────────────────────────────
    # --balance: sonnet first, opus pushed to last (10-20x cheaper per call)
    # default  : opus first (most capable)
    if ($hasAnthropic) {
        $primary = if ($Balance) { 'anthropic/claude-sonnet-4-6' } else { 'anthropic/claude-opus-4-6' }
        $plan.Add($primary); $rsrch.Add($primary)
    }
    if ($hasCopilot) { $plan.Add('github-copilot/gemini-3.1-pro-preview');   $rsrch.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini)  { $plan.Add('google-gemini-cli/gemini-3.1-pro-preview'); $rsrch.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasCodex)   { $plan.Add('openai-codex/gpt-5.3-codex');               $rsrch.Add('openai-codex/gpt-5.3-codex') }
    if ($hasZai)     { $plan.Add('zai/glm-5.1'); $rsrch.Add('zai/glm-5.1');   $plan.Add('zai/glm-5-turbo') }
    if ($hasGroq)    { $plan.Add('groq/kimi-k2-instruct') }
    # when balanced: expensive models as last fallback only
    if ($hasAnthropic -and $Balance) {
        $plan.Add('anthropic/claude-opus-4-6');    $rsrch.Add('anthropic/claude-opus-4-6')
        $plan.Add('anthropic/claude-sonnet-4-6') | Out-Null  # dedup will remove
    }
    if ($hasAnthropic -and -not $Balance) {
        $plan.Add('anthropic/claude-sonnet-4-6'); $rsrch.Add('anthropic/claude-sonnet-4-6')
    }

    # ── execution ─────────────────────────────────────────────────────────────
    if ($hasKimi)    { $exec.Add('kimi-coding/kimi-k2.5') }
    if ($hasZai)     { $exec.Add('zai/glm-5.1'); $exec.Add('zai/glm-5-turbo'); $exec.Add('zai/glm-5') }
    if ($hasAnthropic){ $exec.Add('anthropic/claude-sonnet-4-6'); $exec.Add('anthropic/claude-haiku-4-5') }
    if ($hasCopilot) { $exec.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini -and -not $hasCopilot) { $exec.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasGroq)    { $exec.Add('groq/kimi-k2-instruct') }
    if ($hasGguf)    { $exec.Add($GgufRef) }   # local server as cheap final fallback

    # ── execution_simple (cheap fan-out workers — gguf + free tiers first) ───
    if ($hasGguf)    { $simp.Add($GgufRef) }
    if ($hasGroq)    { $simp.Add('groq/kimi-k2-instruct'); $simp.Add('groq/qwen/qwen3-32b') }
    if ($hasZai)     { $simp.Add('zai/glm-4.7'); $simp.Add('zai/glm-4.7-flash'); $simp.Add('zai/glm-4.6') }
    if ($hasKimi)    { $simp.Add('kimi-coding/kimi-k2.5') }
    if ($hasAnthropic){ $simp.Add('anthropic/claude-haiku-4-5') }
    if ($hasGemini -and $simp.Count -eq 0) { $simp.Add('google-gemini-cli/gemini-3.1-pro-preview') }

    # ── completion ────────────────────────────────────────────────────────────
    if ($hasAnthropic){ $comp.Add('anthropic/claude-sonnet-4-6'); $comp.Add('anthropic/claude-haiku-4-5') }
    if ($hasZai)     { $comp.Add('zai/glm-5.1'); $comp.Add('zai/glm-5-turbo') }
    if ($hasKimi)    { $comp.Add('kimi-coding/kimi-k2.5') }
    if ($hasGemini)  { $comp.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasCopilot) { $comp.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGroq)    { $comp.Add('groq/kimi-k2-instruct') }
    if ($hasGguf)    { $comp.Add($GgufRef) }

    # ── subagent (parallel tasks — cost matters most, gguf + cheap first) ────
    if ($hasGguf)    { $sub.Add($GgufRef) }
    if ($hasKimi)    { $sub.Add('kimi-coding/kimi-k2.5') }
    if ($hasZai)     { $sub.Add('zai/glm-5.1'); $sub.Add('zai/glm-5-turbo'); $sub.Add('zai/glm-5'); $sub.Add('zai/glm-4.7'); $sub.Add('zai/glm-4.7-flash') }
    if ($hasGroq)    { $sub.Add('groq/kimi-k2-instruct'); $sub.Add('groq/qwen/qwen3-32b') }
    if ($hasAnthropic){ $sub.Add('anthropic/claude-haiku-4-5') }
    if ($hasCopilot) { $sub.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini -and -not $hasCopilot) { $sub.Add('google-gemini-cli/gemini-3.1-pro-preview') }

    function Dedupe { param($L); $seen=[System.Collections.Generic.HashSet[string]]::new(); $L|Where-Object{$seen.Add($_)} }

    $plan  = @(Dedupe $plan);  $rsrch = @(Dedupe $rsrch)
    $exec  = @(Dedupe $exec);  $simp  = @(Dedupe $simp)
    $comp  = @(Dedupe $comp);  $sub   = @(Dedupe $sub)

    if ($plan.Count -eq 0 -or $exec.Count -eq 0) { return $null }

    function Fmt { param([string]$Role,[string[]]$M)
        if ($M.Count -eq 0) { return }
        $l = @("  ${Role}:","    model: $($M[0])")
        if ($M.Count -gt 1) { $l += '    fallbacks:'; 1..($M.Count-1) | % { $l += "      - $($M[$_])" } }
        $l -join "`n"
    }

    $providers = $Selected + $(if ($hasGguf) { @('gguf') } else { @() })
    $modeNote  = if ($Balance) { ' [balance: sonnet primary, opus=last fallback]' } else { '' }
    $ggufNote  = if ($hasGguf) { "`n  # gguf: $GgufRef -> exec_simple + subagent + completion (free local)" } else { '' }
    $codexNote = if ($hasCodex){ "`n  # codex: planning/research only (exec omitted to avoid rate-limit stalls)" } else { '' }

    return @"
  # Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')  providers: $($providers -join '+')$modeNote$ggufNote$codexNote

$(Fmt 'planning'         $plan)

$(Fmt 'research'         $rsrch)

$(Fmt 'execution'        $exec)

$(Fmt 'execution_simple' $simp)

$(Fmt 'completion'       $comp)

$(Fmt 'subagent'         $sub)
"@.TrimEnd()
}


    $planModels     = [System.Collections.Generic.List[string]]::new()
    $researchModels = [System.Collections.Generic.List[string]]::new()
    $execModels     = [System.Collections.Generic.List[string]]::new()
    $simpleModels   = [System.Collections.Generic.List[string]]::new()
    $compModels     = [System.Collections.Generic.List[string]]::new()
    $subModels      = [System.Collections.Generic.List[string]]::new()

    if ($hasAnthropic) { $planModels.Add('anthropic/claude-opus-4-6'); $researchModels.Add('anthropic/claude-opus-4-6') }
    if ($hasCopilot)   { $planModels.Add('github-copilot/gemini-3.1-pro-preview'); $researchModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini)    { $planModels.Add('google-gemini-cli/gemini-3.1-pro-preview'); $researchModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasAnthropic) { $planModels.Add('anthropic/claude-sonnet-4-6'); $researchModels.Add('anthropic/claude-sonnet-4-6') }
    if ($hasCodex)     { $planModels.Add('openai-codex/gpt-5.3-codex'); $researchModels.Add('openai-codex/gpt-5.3-codex') }
    if ($hasZai)       { $planModels.Add('zai/glm-5.1'); $researchModels.Add('zai/glm-5.1'); $planModels.Add('zai/glm-5-turbo') }
    if ($hasGroq)      { $planModels.Add('groq/kimi-k2-instruct') }

    if ($hasKimi)      { $execModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasZai)       { $execModels.Add('zai/glm-5.1'); $execModels.Add('zai/glm-5-turbo'); $execModels.Add('zai/glm-5') }
    if ($hasAnthropic) { $execModels.Add('anthropic/claude-sonnet-4-6'); $execModels.Add('anthropic/claude-haiku-4-5') }
    if ($hasCopilot)   { $execModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini -and -not $hasCopilot) { $execModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasGroq)      { $execModels.Add('groq/kimi-k2-instruct') }

    if ($hasGroq)      { $simpleModels.Add('groq/kimi-k2-instruct'); $simpleModels.Add('groq/qwen/qwen3-32b') }
    if ($hasZai)       { $simpleModels.Add('zai/glm-4.7'); $simpleModels.Add('zai/glm-4.7-flash'); $simpleModels.Add('zai/glm-4.6') }
    if ($hasKimi)      { $simpleModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasAnthropic) { $simpleModels.Add('anthropic/claude-haiku-4-5') }
    if ($hasGemini -and $simpleModels.Count -eq 0) { $simpleModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }

    if ($hasAnthropic) { $compModels.Add('anthropic/claude-sonnet-4-6'); $compModels.Add('anthropic/claude-haiku-4-5') }
    if ($hasZai)       { $compModels.Add('zai/glm-5.1'); $compModels.Add('zai/glm-5-turbo') }
    if ($hasKimi)      { $compModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasGemini)    { $compModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }
    if ($hasCopilot)   { $compModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGroq)      { $compModels.Add('groq/kimi-k2-instruct') }

    if ($hasKimi)      { $subModels.Add('kimi-coding/kimi-k2.5') }
    if ($hasZai)       { $subModels.Add('zai/glm-5.1'); $subModels.Add('zai/glm-5-turbo'); $subModels.Add('zai/glm-5'); $subModels.Add('zai/glm-4.7'); $subModels.Add('zai/glm-4.7-flash') }
    if ($hasGroq)      { $subModels.Add('groq/kimi-k2-instruct'); $subModels.Add('groq/qwen/qwen3-32b') }

function Write-GsdPreferencesModels {
    param(
        [Parameter(Mandatory)] [string]$ModelsYaml,
        [string]$DestPath,
        [switch]$DryRun
    )

    $gsdHome = Resolve-GsdHome
    if (-not $DestPath) { $DestPath = Join-Path $gsdHome 'PREFERENCES.md' }

    $bundleTemplatePath = Join-Path (Resolve-GsdBundleDir) 'PREFERENCES.md'
    $baseContent = $null

    if (Test-Path $DestPath) {
        $baseContent = Get-Content $DestPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrWhiteSpace($baseContent) -and (Test-Path $bundleTemplatePath)) {
        $baseContent = Get-Content $bundleTemplatePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrWhiteSpace($baseContent)) {
        Write-Host '  [error] Could not resolve a base PREFERENCES.md template.' -ForegroundColor Red
        return $false
    }

    $normalizedBase = $baseContent -replace "`r`n", "`n"
    $replacement = "models:`n$ModelsYaml"
    $newContent = $null

    if ($normalizedBase -match '(?s)(^---\s*\n.*?\n)models:\n.*?(\n---\s*\n.*)$') {
        $newContent = $matches[1] + $replacement + $matches[2]
    } elseif ($normalizedBase -match '(?s)(^---\s*\n.*?\n---\s*\n.*)$') {
        $frontMatter = $matches[1]
        $newContent = $frontMatter -replace '(?s)\n---\s*\n', "`n$replacement`n---`n"
    } else {
        Write-Host '  [error] Base PREFERENCES.md does not have the expected front matter structure.' -ForegroundColor Red
        return $false
    }

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
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($DestPath, $newContent, $utf8NoBom)
        return $true
    } catch {
        Write-Host ("  [error] write failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Resolve-GsdModelStack {
    param([string]$ModelArg)

    if ([string]::IsNullOrWhiteSpace($ModelArg)) { return @() }

    $aliases = @{
        'claude'='anthropic'; 'anthropic'='anthropic'
        'codex'='openai-codex'; 'openai'='openai-codex'
        'gemini'='google-gemini-cli'; 'google'='google-gemini-cli'
        'glm'='zai'; 'zai'='zai'
        'kimi'='kimi-coding'; 'kimi-coding'='kimi-coding'
        'groq'='groq'; 'copilot'='github-copilot'; 'github-copilot'='github-copilot'
        'gguf'='gguf'  # special token -- resolved at call site via Probe-GgufServer
    }

    $singleDefaults = @{
        'anthropic'='anthropic,zai'; 'openai-codex'='openai-codex,zai'
        'google-gemini-cli'='google-gemini-cli'; 'zai'='zai'
        'kimi-coding'='kimi-coding'; 'groq'='groq'; 'github-copilot'='github-copilot'
        'gguf'='gguf'
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $seen   = [System.Collections.Generic.HashSet[string]]::new()
    $tokens = $ModelArg -split '\+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' }

    foreach ($token in $tokens) {
        if (-not $aliases.ContainsKey($token)) {
            Write-Host ("  [error] Unknown brand '{0}'. Accepted: claude codex gemini glm kimi groq copilot gguf" -f $token) -ForegroundColor Red
            return $null
        }
        $id = $aliases[$token]
        # single-token with defaults only when it's the only token and has defaults
        if ($tokens.Count -eq 1 -and $singleDefaults.ContainsKey($id)) {
            $singleDefaults[$id] -split ',' | ForEach-Object { if ($seen.Add($_)) { $result.Add($_) } }
        } else {
            if ($seen.Add($id)) { $result.Add($id) }
        }
    }
    return $result.ToArray()
}

function Invoke-GsdSetupFromModel {
    param(
        [Parameter(Mandatory)] [string]$Model,
        [switch]$DryRun,
        [switch]$Balance
    )

    # Detect +gguf token and resolve to running server
    $modelTokens = $Model.ToLowerInvariant() -split '\+'
    $hasGgufToken = $modelTokens -contains 'gguf'
    $modelWithoutGguf = ($modelTokens | Where-Object { $_ -ne 'gguf' }) -join '+'
    if (-not $modelWithoutGguf) { $modelWithoutGguf = $Model }

    $ggufRef = ''
    if ($hasGgufToken) {
        Write-Host '  [gguf] Probing running llama-server...' -ForegroundColor DarkGray
        $server = Probe-GgufServer
        if ($server -and $server.Models.Count -gt 0) {
            $modelId = if ($server.Models[0].id) { $server.Models[0].id } else { [string]$server.Models[0] }
            $stem    = [System.IO.Path]::GetFileNameWithoutExtension($modelId) -replace '[^a-zA-Z0-9\-]','-'
            $ggufRef = "gguf-local-$stem/$modelId"
            Write-Host ("  [gguf] Found: {0}  ->  {1}" -f $server.BaseUrl, $ggufRef) -ForegroundColor Green
        } else {
            Write-Host '  [gguf] No server found on ports 8080/8081/8082/1234/11434 -- gguf omitted.' -ForegroundColor DarkYellow
            Write-Host '         Start one first: 8sync gguf serve ... --balance' -ForegroundColor DarkGray
        }
    }

    $selectedProviders = Resolve-GsdModelStack -ModelArg $modelWithoutGguf
    if ($null -eq $selectedProviders -or $selectedProviders.Count -eq 0) { return }

    $yaml = Build-GsdModelsYaml -Selected $selectedProviders -Balance:$Balance -GgufRef $ggufRef
    if (-not $yaml) {
        Write-Host '  [error] Could not generate routing. Include at least one exec-capable brand: glm kimi claude gemini groq.' -ForegroundColor Red
        return
    }

    $destPath = Join-Path (Resolve-GsdHome) 'PREFERENCES.md'
    $modeStr  = if ($Balance) { ' --balance' } else { '' }
    $ggufStr  = if ($ggufRef) { "  gguf     : $ggufRef`n" } else { '' }

    Write-Host ''
    Write-Host ("  [gsd] Setup  model={0}{1}" -f $Model, $modeStr) -ForegroundColor Cyan
    Write-Host ("  providers: {0}" -f ($selectedProviders -join ', ')) -ForegroundColor DarkGray
    if ($ggufStr) { Write-Host ($ggufStr.TrimEnd()) -ForegroundColor DarkGray }
    Write-Host ("  dest     : {0}" -f $destPath) -ForegroundColor DarkGray
    Write-Host ''
    $yaml -split "`n" | Select-Object -First 20 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
    if (($yaml -split "`n").Count -gt 20) { Write-Host '    ...' -ForegroundColor DarkGray }
    Write-Host ''

    $ok = Write-GsdPreferencesModels -ModelsYaml $yaml -DestPath $destPath -DryRun:$DryRun
    if ($ok -and -not $DryRun) {
        Write-Host ("  [ok] {0}" -f $destPath) -ForegroundColor Green
        Write-Host '  Next: 8sync gsd status   /gsd prefs   /model' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Invoke-GsdSetup {
    param(
        [switch]$DryRun,
        [string]$Plan = ''
    )

    $bundleDir = Resolve-GsdBundleDir
    $gsdHome = Resolve-GsdHome
    $validPlans = @('max', 'pro', 'normal', 'claude-max', 'codex-max', 'gemini-max', 'claude-codex-gemini', 'glm-max')
    $planLower = $Plan.ToLowerInvariant().Trim()

    if ($planLower -ne '' -and $validPlans -notcontains $planLower) {
        Write-Host ''
        Write-Host ("  [error] Unknown plan '{0}'." -f $Plan) -ForegroundColor Red
        Write-Host '  Valid: max | pro | normal | claude-max | codex-max | gemini-max | claude-codex-gemini | glm-max' -ForegroundColor DarkGray
        Write-Host '  Run "8sync gsd setup --plan" (no value) for full descriptions.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $srcFile = if ($planLower -ne '') { Join-Path $bundleDir ("PREFERENCES-{0}.md" -f $planLower) } else { Join-Path $bundleDir 'PREFERENCES.md' }
    $destFile = Join-Path $gsdHome 'PREFERENCES.md'
    $planLabel = if ($planLower -ne '') { $planLower } else { 'default' }

    Write-Host ''
    Write-Host ("  [gsd] Setup model routing  plan={0}" -f $planLabel) -ForegroundColor Cyan
    Write-Host ("  source : {0}" -f $srcFile) -ForegroundColor DarkGray
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
    if ($planLower -eq '') {
        Write-Host '  Done. Next: /login in pi, then /gsd prefs to verify.' -ForegroundColor Cyan
        Write-Host ''
        return
    }

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
    Write-Host ''
}

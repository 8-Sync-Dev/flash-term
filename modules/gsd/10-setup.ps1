# =============================================================================
# 8sync gsd -- preferences generation and setup flows
# =============================================================================


function Build-GsdModelsYaml {
    param([string[]]$Selected)

    $has = @{}
    foreach ($s in $Selected) { $has[$s] = $true }

    $hasAnthropic = $has['anthropic'] -eq $true
    $hasCopilot   = $has['github-copilot'] -eq $true
    $hasGemini    = $has['google-gemini-cli'] -eq $true
    $hasCodex     = $has['openai-codex'] -eq $true
    $hasZai       = $has['zai'] -eq $true
    $hasGroq      = $has['groq'] -eq $true
    $hasKimi      = $has['kimi-coding'] -eq $true

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
    if ($hasAnthropic) { $subModels.Add('anthropic/claude-haiku-4-5') }
    if ($hasCopilot)   { $subModels.Add('github-copilot/gemini-3.1-pro-preview') }
    if ($hasGemini -and -not $hasCopilot) { $subModels.Add('google-gemini-cli/gemini-3.1-pro-preview') }

    function Dedupe-List {
        param($List)

        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $List | Where-Object { $seen.Add($_) }
    }

    $planModels     = @(Dedupe-List $planModels)
    $researchModels = @(Dedupe-List $researchModels)
    $execModels     = @(Dedupe-List $execModels)
    $simpleModels   = @(Dedupe-List $simpleModels)
    $compModels     = @(Dedupe-List $compModels)
    $subModels      = @(Dedupe-List $subModels)

    if ($planModels.Count -eq 0 -or $execModels.Count -eq 0) {
        return $null
    }

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

    $providerList = $Selected -join ', '
    $planLabel = if ($planModels.Count -gt 0) { $planModels[0] } else { 'none' }
    $execLabel = if ($execModels.Count -gt 0) { $execModels[0] } else { 'none' }
    $codexNote = if ($hasCodex) {
        "`n  # NOTE: openai-codex is in planning/research only — NOT in exec/subagent/completion`n  #   (usage-limit error pauses auto-mode indefinitely instead of continuing fallback chain)"
    } else { '' }

    $yaml = @"
  # ============================================================================
  # PLAN: custom (generated by 8sync gsd setup)
  # Providers: $providerList
  # planning  -> $planLabel
  # execution -> $execLabel
  # Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')$codexNote
  # ============================================================================

$(Format-ModelBlock 'planning'         $planModels)

$(Format-ModelBlock 'research'         $researchModels)

$(Format-ModelBlock 'execution'        $execModels)

$(Format-ModelBlock 'execution_simple' $simpleModels)

$(Format-ModelBlock 'completion'       $compModels)

$(Format-ModelBlock 'subagent'         $subModels)
"@

    return $yaml.TrimEnd()
}

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
        Set-Content -Path $DestPath -Value $newContent -Encoding UTF8 -Force
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
        'claude' = 'anthropic'; 'anthropic' = 'anthropic'; 'codex' = 'openai-codex'; 'openai' = 'openai-codex'
        'gemini' = 'google-gemini-cli'; 'google' = 'google-gemini-cli'; 'glm' = 'zai'; 'zai' = 'zai'
        'kimi' = 'kimi-coding'; 'kimi-coding' = 'kimi-coding'; 'groq' = 'groq'; 'copilot' = 'github-copilot'
        'github-copilot' = 'github-copilot'
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($raw in ($ModelArg -split '\+')) {
        $token = $raw.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if (-not $aliases.ContainsKey($token)) {
            Write-Host ''
            Write-Host ("  [error] Unknown model brand '{0}' in --model '{1}'." -f $token, $ModelArg) -ForegroundColor Red
            Write-Host '  Accepted: claude, codex, gemini, glm, kimi, groq, copilot' -ForegroundColor DarkGray
            Write-Host '  Example : 8sync gsd setup --model codex+glm' -ForegroundColor DarkGray
            Write-Host ''
            return $null
        }

        $providerId = $aliases[$token]
        if ($seen.Add($providerId)) { $result.Add($providerId) }
    }

    return $result.ToArray()
}

function Invoke-GsdSetupFromModel {
    param(
        [Parameter(Mandatory)] [string]$Model,
        [switch]$DryRun
    )

    $selectedProviders = Resolve-GsdModelStack -ModelArg $Model
    if ($null -eq $selectedProviders -or $selectedProviders.Count -eq 0) { return }

    $yaml = Build-GsdModelsYaml -Selected $selectedProviders
    if (-not $yaml) {
        Write-Host ''
        Write-Host '  [error] Could not generate routing from this model stack.' -ForegroundColor Red
        Write-Host '  Hint: pick at least one execution-capable brand such as glm, kimi, claude, gemini, groq.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $gsdHome = Resolve-GsdHome
    $destPath = Join-Path $gsdHome 'PREFERENCES.md'

    Write-Host ''
    Write-Host ("  [gsd] Setup model routing  model={0}" -f $Model) -ForegroundColor Cyan
    Write-Host ("  providers: {0}" -f ($selectedProviders -join ', ')) -ForegroundColor DarkGray
    Write-Host ("  dest     : {0}" -f $destPath) -ForegroundColor DarkGray
    Write-Host ''

    $yaml -split "`n" | Select-Object -First 18 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
    if (($yaml -split "`n").Count -gt 18) { Write-Host '    ...' -ForegroundColor DarkGray }
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

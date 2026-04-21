# =============================================================================
# 8sync gsd -- status reporting
# =============================================================================

function Invoke-GsdStatus {
    $gsdHome = Resolve-GsdHome
    $agentDir = Resolve-GsdAgentDir

    $files = @(
        @{ Label = 'PREFERENCES.md'; Path = Join-Path $gsdHome 'PREFERENCES.md' }
        @{ Label = 'models.json';    Path = Join-Path $agentDir 'models.json' }
        @{ Label = 'auth.json';      Path = Join-Path $agentDir 'auth.json' }
    )

    Write-Host ''
    Write-Host '  [gsd] Status' -ForegroundColor Cyan
    Write-Host ("  GSD_HOME: {0}" -f $gsdHome) -ForegroundColor DarkGray
    Write-Host ''

    foreach ($file in $files) {
        $exists = Test-Path $file.Path
        $color = if ($exists) { 'Green' } else { 'DarkYellow' }
        $status = if ($exists) { 'ok' } else { 'MISSING' }
        Write-Host ("  {0,-20} {1,-8} {2}" -f $file.Label, $status, $file.Path) -ForegroundColor $color
    }
    Write-Host ''

    $patch = Get-GsdRuntimePatchStatus
    $providerPatchColor = switch ($patch.ProviderPatch) {
        'patched'   { 'Green' }
        'unpatched' { 'Yellow' }
        'missing'   { 'DarkYellow' }
        default     { 'Red' }
    }
    $labelColor = switch ($patch.UiLabel) {
        'anthropic'     { 'Green' }
        'dynamic'       { 'Green' }
        'anthropic-api' { 'Yellow' }
        'missing'       { 'DarkYellow' }
        default         { 'Red' }
    }
    $settingsColor = if ($patch.Settings -eq 'ok') { 'Green' } elseif ($patch.Settings -eq 'missing') { 'DarkYellow' } else { 'Red' }

    Write-Host '  Runtime patch status:' -ForegroundColor Cyan
    Write-Host ("    Anthropic OAuth prompt fix   {0}" -f $patch.ProviderPatch) -ForegroundColor $providerPatchColor
    Write-Host ("    Anthropic UI label          {0}" -f $patch.UiLabel) -ForegroundColor $labelColor
    Write-Host ("    settings.json               {0}" -f $patch.Settings) -ForegroundColor $settingsColor
    if ($patch.DefaultProvider -or $patch.DefaultModel) {
        Write-Host ("    default model               {0}/{1}" -f $patch.DefaultProvider, $patch.DefaultModel) -ForegroundColor DarkGray
    }
    $claudePathColor = switch ($patch.ClaudePathStatus) {
        'native-configured' { 'Green' }
        'native-found'      { 'Yellow' }
        'shim-only'         { 'Yellow' }
        default             { 'DarkYellow' }
    }
    Write-Host ("    Claude Code path           {0}" -f $patch.ClaudePathStatus) -ForegroundColor $claudePathColor
    if ($patch.ConfiguredClaudePath) {
        Write-Host ("      configured               {0}" -f $patch.ConfiguredClaudePath) -ForegroundColor DarkGray
    }
    if ($patch.NativeClaudePath) {
        Write-Host ("      native                   {0}" -f $patch.NativeClaudePath) -ForegroundColor DarkGray
    }
    if ($patch.ShimClaudePath -and $patch.ShimClaudePath -ne $patch.NativeClaudePath) {
        Write-Host ("      shim                     {0}" -f $patch.ShimClaudePath) -ForegroundColor DarkGray
    }
    Write-Host ''

    $prefPath = Join-Path $gsdHome 'PREFERENCES.md'
    $detectedPlan = ''
    if (Test-Path $prefPath) {
        $bundleDir = Resolve-GsdBundleDir
        $detectedPlan = 'unknown/custom'
        foreach ($plan in @('max','pro','normal','claude-max','codex-max','gemini-max','claude-codex-gemini','glm-max')) {
            $planFile = Join-Path $bundleDir ("PREFERENCES-{0}.md" -f $plan)
            if (-not (Test-Path $planFile)) { continue }
            $prefHash = (Get-FileHash $prefPath -Algorithm MD5).Hash
            $planHash = (Get-FileHash $planFile -Algorithm MD5).Hash
            if ($prefHash -eq $planHash) {
                $detectedPlan = $plan
                break
            }
        }
        Write-Host ("  Active plan: {0}" -f $detectedPlan) -ForegroundColor Cyan
        Write-Host ''
    }

    $planRequirements = @{
        'max' = @{ oauth = @('anthropic','github-copilot','google-gemini-cli','openai-codex'); keys = @('kimi-coding','zai','groq') }
        'pro' = @{ oauth = @('anthropic','google-gemini-cli','openai-codex'); keys = @('kimi-coding','zai','groq') }
        'normal' = @{ oauth = @('google-gemini-cli','openai-codex'); keys = @('zai','groq') }
        'claude-max' = @{ oauth = @('anthropic'); keys = @() }
        'codex-max' = @{ oauth = @('openai-codex'); keys = @() }
        'gemini-max' = @{ oauth = @('google-gemini-cli'); keys = @() }
        'claude-codex-gemini' = @{ oauth = @('anthropic','openai-codex','google-gemini-cli'); keys = @() }
    }

    $authPath = Join-Path $agentDir 'auth.json'
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            Write-Host '  OAuth providers:' -ForegroundColor DarkGray
            $auth.PSObject.Properties | ForEach-Object {
                $exp = $_.Value.expires
                if ($exp) {
                    $diff = [long]$exp - $now
                    $hours = [math]::Round($diff / 3600000)
                    $tag = if ($diff -gt 0) { "valid ~{0}h" -f $hours } else { 'EXPIRED' }
                    $color = if ($diff -gt 0) { 'Green' } else { 'Red' }
                } else {
                    $tag = if ($_.Value.type) { $_.Value.type } else { '?' }
                    $color = 'Green'
                }
                Write-Host ("    {0,-28} {1}" -f $_.Name, $tag) -ForegroundColor $color
            }
        } catch {
            Write-Host '  auth.json: could not parse' -ForegroundColor DarkYellow
        }
    }
    Write-Host ''

    Write-Host '  API keys:' -ForegroundColor DarkGray
    $envFile = Join-Path $agentDir '.env'
    $envFileLines = @()
    if (Test-Path $envFile) {
        $envFileLines = Get-Content $envFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    foreach ($provider in $script:GsdProviderKeys.Keys) {
        $varName = $script:GsdProviderKeys[$provider]
        $fromEnv = [System.Environment]::GetEnvironmentVariable($varName, 'Process')
        $fromUser = [System.Environment]::GetEnvironmentVariable($varName, 'User')
        $fromFile = $envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1

        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            $status = 'set (env)'; $color = 'Green'
        } elseif (-not [string]::IsNullOrWhiteSpace($fromUser)) {
            $status = 'set (user)'; $color = 'Green'
        } elseif ($fromFile) {
            $status = 'set (.env only)'; $color = 'DarkYellow'
        } else {
            $status = 'not set'; $color = 'DarkGray'
        }

        Write-Host ("    {0,-15} {1,-22} {2}" -f $provider, $varName, $status) -ForegroundColor $color
    }
    Write-Host ''

    if ($detectedPlan -eq '' -or -not $planRequirements.ContainsKey($detectedPlan)) {
        return
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    $loggedIn = @()
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $auth.PSObject.Properties | ForEach-Object {
                $exp = $_.Value.expires
                if (-not $exp -or ([long]$exp - $now) -gt 0) { $loggedIn += $_.Name }
            }
        } catch {}
    }

    foreach ($provider in $planRequirements[$detectedPlan].oauth) {
        if ($loggedIn -notcontains $provider) {
            $missing.Add("/login $provider")
        }
    }

    foreach ($provider in $planRequirements[$detectedPlan].keys) {
        $varName = $script:GsdProviderKeys[$provider]
        $hasKey = (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName, 'Process'))) -or
                  (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName, 'User'))) -or
                  ($envFileLines | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') })
        if (-not $hasKey) {
            $missing.Add("8sync gsd key $provider <key>")
        }
    }

    if ($missing.Count -eq 0) {
        Write-Host '  Checklist: all requirements met' -ForegroundColor Green
    } else {
        Write-Host ("  Checklist: {0} item(s) missing for plan '{1}'" -f $missing.Count, $detectedPlan) -ForegroundColor Yellow
        foreach ($item in $missing) {
            Write-Host ("    [x] {0}" -f $item) -ForegroundColor Red
        }
    }
    Write-Host ''
}

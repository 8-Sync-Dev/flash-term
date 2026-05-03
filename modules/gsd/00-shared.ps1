# =============================================================================
# 8sync gsd -- shared paths, provider catalog, and common metadata
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

function Resolve-GsdBundleDir {
    if (-not [string]::IsNullOrWhiteSpace($script:ModulesDir)) {
        return [System.IO.Path]::GetFullPath((Join-Path $script:ModulesDir '..\gsd-config'))
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\gsd-config'))
}

function Resolve-GsdProjectRoot {
    param([string]$StartPath = (Get-Location).Path)

    if ([string]::IsNullOrWhiteSpace($StartPath)) { return $null }

    $current = [System.IO.Path]::GetFullPath($StartPath)
    while ($current) {
        if (Test-Path (Join-Path $current '.gsd')) {
            return $current
        }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }

    return $null
}

function Resolve-GsdProjectVendorDir {
    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) { return $null }
    return Join-Path $projectRoot '.gsd\vendor\gsd-pi'
}

function Resolve-GsdLocalBaselineRoot {
    $vendorDir = Resolve-GsdProjectVendorDir
    if (-not $vendorDir) { return $null }
    return Join-Path $vendorDir ("baseline-{0}" -f $script:GsdPinnedVersion)
}

function Resolve-GsdLocalLatestRoot {
    $vendorDir = Resolve-GsdProjectVendorDir
    if (-not $vendorDir) { return $null }
    return Join-Path $vendorDir 'latest'
}

function Resolve-GsdLocalCurrentRoot {
    $vendorDir = Resolve-GsdProjectVendorDir
    if (-not $vendorDir) { return $null }
    return Join-Path $vendorDir 'current'
}

function Resolve-GsdPreferredRuntimeRoot {
    $candidates = @(
        (Resolve-GsdLocalCurrentRoot),
        (Resolve-GsdLocalBaselineRoot),
        (Resolve-GsdLocalLatestRoot)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return $null
}

function Get-GsdLocalRuntimeStatus {
    $projectRoot = Resolve-GsdProjectRoot
    $vendorDir = Resolve-GsdProjectVendorDir
    $baselineRoot = Resolve-GsdLocalBaselineRoot
    $latestRoot = Resolve-GsdLocalLatestRoot
    $currentRoot = Resolve-GsdLocalCurrentRoot
    $preferredRoot = Resolve-GsdPreferredRuntimeRoot

    return [pscustomobject]@{
        ProjectRoot    = $projectRoot
        VendorDir      = $vendorDir
        BaselineRoot   = $baselineRoot
        LatestRoot     = $latestRoot
        CurrentRoot    = $currentRoot
        HasProjectRoot = -not [string]::IsNullOrWhiteSpace($projectRoot)
        HasVendorDir   = $vendorDir -and (Test-Path $vendorDir)
        HasBaseline    = $baselineRoot -and (Test-Path $baselineRoot)
        HasLatest      = $latestRoot -and (Test-Path $latestRoot)
        HasCurrent     = $currentRoot -and (Test-Path $currentRoot)
        PreferredRoot  = $preferredRoot
    }
}

function Get-GsdAnthropicSharedProviderPath {
    $agentDir = Resolve-GsdAgentDir
    return Join-Path $agentDir 'node_modules\@gsd\pi-ai\dist\providers\anthropic-shared.js'
}

function Get-GsdAnthropicUiLabelPath {
    $agentDir = Resolve-GsdAgentDir
    return Join-Path $agentDir 'node_modules\@gsd\pi-coding-agent\dist\modes\interactive\components\model-selector.js'
}

function Get-GsdSettingsPath {
    $agentDir = Resolve-GsdAgentDir
    return Join-Path $agentDir 'settings.json'
}

function Read-GsdSettingsJson {
    $path = Get-GsdSettingsPath
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
}

function Write-GsdSettingsJson {
    param([object]$Data)

    $path = Get-GsdSettingsPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }
    $Data | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
}

function Get-GsdClaudeCodeNativeCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($p in @(
        $env:CLAUDE_CODE_BIN,
        $env:CLAUDE_CODE_PATH,
        (Join-Path $HOME '.local\bin\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and -not $candidates.Contains($p)) {
            $candidates.Add($p)
        }
    }

    try {
        $cmdExe = Get-Command 'claude.exe' -ErrorAction SilentlyContinue
        if ($cmdExe -and -not $candidates.Contains($cmdExe.Source)) {
            $candidates.Add($cmdExe.Source)
        }
    } catch {}

    return @($candidates)
}

function Test-GsdClaudeCodeNativeBinary {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) { return $false }
    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -ne '.exe') { return $false }

    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            if ($fs.Length -lt 2) { return $false }
            $b1 = $fs.ReadByte()
            $b2 = $fs.ReadByte()
            return ($b1 -eq 0x4D -and $b2 -eq 0x5A) # MZ
        } finally {
            $fs.Dispose()
        }
    } catch {
        return $false
    }
}

function Get-GsdClaudeCommandPath {
    try {
        $cmd = Get-Command 'claude' -ErrorAction SilentlyContinue
        if ($cmd) { return [string]$cmd.Source }
    } catch {}
    return $null
}

function Resolve-GsdClaudeCodeNativePath {
    foreach ($candidate in (Get-GsdClaudeCodeNativeCandidates)) {
        if (Test-GsdClaudeCodeNativeBinary -Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Ensure-GsdClaudeCodeExecutableSetting {
    param([switch]$DryRun)

    $nativePath = Resolve-GsdClaudeCodeNativePath
    if ([string]::IsNullOrWhiteSpace($nativePath)) {
        return [pscustomobject]@{
            Status = 'native-missing'
            NativePath = ''
            ConfiguredPath = ''
            Changed = $false
        }
    }

    $settings = Read-GsdSettingsJson
    if ($null -eq $settings) { $settings = [pscustomobject]@{} }
    $configuredPath = [string]$settings.pathToClaudeCodeExecutable
    $envChanged = $false

    if (-not $DryRun) {
        $procEnv = [System.Environment]::GetEnvironmentVariable('CLAUDE_CODE_PATH', 'Process')
        $userEnv = [System.Environment]::GetEnvironmentVariable('CLAUDE_CODE_PATH', 'User')
        if ($procEnv -ne $nativePath) {
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CODE_PATH', $nativePath, 'Process')
            $envChanged = $true
        }
        if ($userEnv -ne $nativePath) {
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CODE_PATH', $nativePath, 'User')
            $envChanged = $true
        }
    }

    if ($configuredPath -eq $nativePath) {
        return [pscustomobject]@{
            Status = if ($envChanged) { 'already-correct+env' } else { 'already-correct' }
            NativePath = $nativePath
            ConfiguredPath = $configuredPath
            Changed = $envChanged
        }
    }

    if (-not $DryRun) {
        $data = [ordered]@{}
        foreach ($prop in $settings.PSObject.Properties) {
            $data[$prop.Name] = $prop.Value
        }
        $data['pathToClaudeCodeExecutable'] = $nativePath
        Write-GsdSettingsJson -Data $data
    }

    return [pscustomobject]@{
        Status = if ([string]::IsNullOrWhiteSpace($configuredPath)) { 'configured' } else { 'rewritten' }
        NativePath = $nativePath
        ConfiguredPath = $configuredPath
        Changed = $true
    }
}

function Test-GsdAnthropicOauthAvailable {
    $agentDir = Resolve-GsdAgentDir
    $authPath = Join-Path $agentDir 'auth.json'
    if (-not (Test-Path $authPath)) { return $false }

    try {
        $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $entry = $auth.anthropic
        if (-not $entry) { return $false }
        if (-not $entry.expires) { return $true }
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        return ([long]$entry.expires -gt $now)
    } catch {
        return $false
    }
}

function Test-GsdAnthropicApiKeyConfigured {
    $varName = 'ANTHROPIC_API_KEY'
    if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName, 'Process'))) { return $true }
    if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($varName, 'User'))) { return $true }

    $envFile = Join-Path (Resolve-GsdAgentDir) '.env'
    if (Test-Path $envFile) {
        try {
            $line = Get-Content $envFile -Encoding UTF8 | Where-Object { $_ -match ('^' + [regex]::Escape($varName) + '\s*=') } | Select-Object -First 1
            if ($line) { return $true }
        } catch {}
    }
    return $false
}

function Normalize-GsdPreferencesForClaudeCodeOAuth {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [switch]$DryRun
    )

    # claude-code/ is now the intended provider for claude-max and claude-code plans.
    # No normalization needed -- claude-code routes through subscription (flat-rate, $0).
    return [pscustomobject]@{ Status='already-clean'; Changed=$false; Path=$Path; Replacements=0 }
}

function Normalize-GsdSettingsForClaudeCodeOAuth {
    param([switch]$DryRun)

    # claude-code is now the intended provider identity for claude-max and claude-code plans.
    # No normalization needed -- keep claude-code as defaultProvider.
    return [pscustomobject]@{ Status='already-clean'; Changed=$false }
}

function Get-GsdClaudeGlobalSettingsPath {
    return Join-Path $HOME '.claude\settings.json'
}

function Read-GsdClaudeGlobalSettingsJson {
    $path = Get-GsdClaudeGlobalSettingsPath
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
}

function Write-GsdClaudeGlobalSettingsJson {
    param([object]$Data)
    $path = Get-GsdClaudeGlobalSettingsPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }
    $Data | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding UTF8
}

function Ensure-GsdClaudeGlobalSettings {
    param(
        [switch]$DryRun,
        [int]$CompactPct = 0
    )

    $settings = Read-GsdClaudeGlobalSettingsJson
    if ($null -eq $settings) { $settings = [pscustomobject]@{} }
    $data = [ordered]@{}
    foreach ($prop in $settings.PSObject.Properties) { $data[$prop.Name] = $prop.Value }

    if (-not $data.Contains('env') -or $null -eq $data['env']) {
        $data['env'] = [ordered]@{}
    }

    $envMap = [ordered]@{}
    if ($data['env'] -is [System.Collections.IDictionary]) {
        foreach ($k in $data['env'].Keys) { $envMap[$k] = $data['env'][$k] }
    } else {
        foreach ($prop in $data['env'].PSObject.Properties) { $envMap[$prop.Name] = $prop.Value }
    }

    $desiredEnv = [ordered]@{
        'DISABLE_TELEMETRY' = '1'
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' = '1'
        'CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING' = '1'
        'CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING' = '1'
    }

    $changed = $false

    # Remove env vars that hurt more than help
    $removeKeys = @(
        'CLAUDE_CODE_DISABLE_1M_CONTEXT'    # forces 200K, wastes Opus 4.7's 1M window
        'DISABLE_PROMPT_CACHING'            # caching saves tokens — never disable
    )
    foreach ($rk in $removeKeys) {
        if ($envMap.Contains($rk)) {
            $envMap.Remove($rk)
            $changed = $true
        }
    }

    foreach ($k in $desiredEnv.Keys) {
        if (-not $envMap.Contains($k) -or [string]$envMap[$k] -ne $desiredEnv[$k]) {
            $envMap[$k] = $desiredEnv[$k]
            $changed = $true
        }
    }

    if (-not $data.Contains('autoCompact') -or $data['autoCompact'] -ne 'smart') {
        $data['autoCompact'] = 'smart'
        $changed = $true
    }

    if ($CompactPct -gt 0) {
        $pctStr = [string]$CompactPct
        if (-not $envMap.Contains('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE') -or [string]$envMap['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'] -ne $pctStr) {
            $envMap['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'] = $pctStr
            $changed = $true
        }
    }

    $data['env'] = $envMap

    if (-not $changed) {
        return [pscustomobject]@{ Status='already-correct'; Changed=$false; Path=(Get-GsdClaudeGlobalSettingsPath) }
    }

    if (-not $DryRun) {
        Write-GsdClaudeGlobalSettingsJson -Data $data
    }

    return [pscustomobject]@{ Status='written'; Changed=$true; Path=(Get-GsdClaudeGlobalSettingsPath) }
}

function Invoke-GsdClaudeFix {
    param(
        [switch]$DryRun,
        [string]$PreferencesPath = ''
    )

    $claudeFix = Ensure-GsdClaudeCodeExecutableSetting -DryRun:$DryRun
    $settingsFix = Normalize-GsdSettingsForClaudeCodeOAuth -DryRun:$DryRun
    $globalClaudeFix = Ensure-GsdClaudeGlobalSettings -DryRun:$DryRun

    # Sync Forge's Claude Code OAuth token to ANTHROPIC_API_KEY if no key is set
    $forgeSync = $null
    if (-not $DryRun -and -not (Test-GsdAnthropicApiKeyConfigured)) {
        $forgeSync = Sync-ForgeClaudeCodeToken -Quiet
    }

    $routeFix = $null
    if (-not [string]::IsNullOrWhiteSpace($PreferencesPath)) {
        $routeFix = Normalize-GsdPreferencesForClaudeCodeOAuth -Path $PreferencesPath -DryRun:$DryRun
    } else {
        $defaultPrefs = Join-Path (Resolve-GsdHome) 'PREFERENCES.md'
        if (Test-Path $defaultPrefs) {
            $routeFix = Normalize-GsdPreferencesForClaudeCodeOAuth -Path $defaultPrefs -DryRun:$DryRun
        }
    }

    return [pscustomobject]@{
        ClaudePath = $claudeFix
        Settings   = $settingsFix
        GlobalClaude = $globalClaudeFix
        ForgeSync  = $forgeSync
        Preferences = $routeFix
    }
}

function Get-GsdRuntimePatchStatus {
    $providerPath = Get-GsdAnthropicSharedProviderPath
    $labelPath = Get-GsdAnthropicUiLabelPath
    $settingsPath = Get-GsdSettingsPath

    $providerStatus = 'missing'
    if (Test-Path $providerPath) {
        try {
            $raw = Get-Content $providerPath -Raw -Encoding UTF8
            if ($raw -match 'params\.system = \[' -and $raw -match 'You are Claude Code, Anthropic''s official CLI for Claude\.' -and $raw -notmatch 'params\.system\.push\(') {
                $providerStatus = 'patched'
            } else {
                $providerStatus = 'unpatched'
            }
        } catch {
            $providerStatus = 'error'
        }
    }

    $labelStatus = 'missing'
    if (Test-Path $labelPath) {
        try {
            $raw = Get-Content $labelPath -Raw -Encoding UTF8
            if ($raw -match 'anthropic:\s*"anthropic-api"') {
                $labelStatus = 'anthropic-api'
            } elseif ($raw -match 'anthropic:\s*"anthropic"') {
                $labelStatus = 'anthropic'
            } elseif ($raw -match 'row\.provider' -and $raw -notmatch 'anthropic:\s*"') {
                # New GSD version uses dynamic row.provider -- no label map to patch
                $labelStatus = 'dynamic'
            } else {
                $labelStatus = 'custom'
            }
        } catch {
            $labelStatus = 'error'
        }
    }

    $defaultProvider = ''
    $defaultModel = ''
    $configuredClaudePath = ''
    $settingsStatus = 'missing'
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $defaultProvider = [string]$settings.defaultProvider
            $defaultModel = [string]$settings.defaultModel
            $configuredClaudePath = [string]$settings.pathToClaudeCodeExecutable
            $settingsStatus = 'ok'
        } catch {
            $settingsStatus = 'error'
        }
    }

    # Check OAuth scope/endpoint patch status
    $oauthScopeStatus = 'unknown'
    $oauthPath = Join-Path (Resolve-GsdAgentDir) 'node_modules\gsd-pi\packages\pi-ai\dist\utils\oauth\anthropic.js'
    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot) {
        $localOauth = Join-Path $localRoot 'packages\pi-ai\dist\utils\oauth\anthropic.js'
        if (Test-Path $localOauth) { $oauthPath = $localOauth }
    }
    if (Test-Path $oauthPath) {
        try {
            $oauthRaw = Get-Content $oauthPath -Raw -Encoding UTF8
            $hasScope = $oauthRaw -match 'user:sessions:claude_code'
            $hasEndpoint = $oauthRaw -match 'console\.anthropic\.com/v1/oauth/token'
            if ($hasScope -and $hasEndpoint) {
                $oauthScopeStatus = 'patched'
            } elseif ($hasScope) {
                $oauthScopeStatus = 'scope-only'
            } else {
                $oauthScopeStatus = 'needs-patch'
            }
        } catch {
            $oauthScopeStatus = 'error'
        }
    } else {
        $oauthScopeStatus = 'missing'
    }

    $nativeClaudePath = Resolve-GsdClaudeCodeNativePath
    $shimClaudePath = Get-GsdClaudeCommandPath
    $claudePathStatus = if (-not [string]::IsNullOrWhiteSpace($nativeClaudePath)) {
        if ($configuredClaudePath -eq $nativeClaudePath) { 'native-configured' } else { 'native-found' }
    } elseif (-not [string]::IsNullOrWhiteSpace($shimClaudePath)) {
        'shim-only'
    } else {
        'missing'
    }

    return [pscustomobject]@{
        ProviderPatch = $providerStatus
        OAuthScope    = $oauthScopeStatus
        UiLabel       = $labelStatus
        Settings      = $settingsStatus
        DefaultProvider = $defaultProvider
        DefaultModel    = $defaultModel
        ConfiguredClaudePath = $configuredClaudePath
        NativeClaudePath = $nativeClaudePath
        ShimClaudePath = $shimClaudePath
        ClaudePathStatus = $claudePathStatus
        ProviderPath  = $providerPath
        UiLabelPath   = $labelPath
        SettingsPath  = $settingsPath
    }
}

function Invoke-GsdRuntimePatch {
    param(
        [switch]$DryRun,
        [switch]$Stable
    )

    $providerPath = Get-GsdAnthropicSharedProviderPath
    $labelPath = Get-GsdAnthropicUiLabelPath

    Write-Host ''
    Write-Host '  [gsd] Applying runtime fixes...' -ForegroundColor Cyan
    if ($Stable) {
        Write-Host '  [stable] Applying stable GSD patch profile' -ForegroundColor Cyan
    }

    if (Test-Path $providerPath) {
        try {
            $raw = (Get-Content $providerPath -Raw -Encoding UTF8) -replace "`r`n", "`n"
            $oldBlock = @"
    if (isOAuthToken) {
        params.system = [
            {
                type: "text",
                text: "You are Claude Code, Anthropic's official CLI for Claude.",
                ...(cacheControl ? { cache_control: cacheControl } : {}),
            },
        ];
        if (context.systemPrompt) {
            params.system.push({
                type: "text",
                text: sanitizeSurrogates(context.systemPrompt),
                ...(cacheControl ? { cache_control: cacheControl } : {}),
            });
        }
    }
"@
            $newBlock = @"
    if (isOAuthToken) {
        params.system = [
            {
                type: "text",
                text: "You are Claude Code, Anthropic's official CLI for Claude.",
                ...(cacheControl ? { cache_control: cacheControl } : {}),
            },
        ];
    }
"@

            $oldBlock = $oldBlock -replace "`r`n", "`n"
            $newBlock = $newBlock -replace "`r`n", "`n"

            $status = Get-GsdRuntimePatchStatus
            if ($status.ProviderPatch -eq 'patched') {
                Write-Host '  [ok]      Anthropic OAuth system prompt fix already applied' -ForegroundColor Green
            } elseif ($raw.Contains($oldBlock)) {
                if ($DryRun) {
                    Write-Host ("  [dry-run] patch {0}" -f $providerPath) -ForegroundColor DarkYellow
                } else {
                    $updated = $raw.Replace($oldBlock, $newBlock)
                    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                    [System.IO.File]::WriteAllText($providerPath, $updated, $utf8NoBom)
                    Write-Host '  [ok]      Patched Anthropic OAuth system prompt (#145-style)' -ForegroundColor Green
                }
            } else {
                Write-Host '  [warn]    Anthropic provider file has unexpected shape; skipped system patch' -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host ("  [warn]    Failed to patch Anthropic provider file: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '  [warn]    Anthropic provider file not found; skipped system patch' -ForegroundColor DarkYellow
    }

    if (Test-Path $labelPath) {
        try {
            $raw = Get-Content $labelPath -Raw -Encoding UTF8
            if ($raw -match 'row\.provider' -and $raw -notmatch 'anthropic:\s*"') {
                Write-Host '  [ok]      Model selector uses dynamic provider labels (no patch needed)' -ForegroundColor Green
            } elseif ($raw -match 'anthropic:\s*"anthropic"') {
                Write-Host '  [ok]      Anthropic provider label already normalized' -ForegroundColor Green
            } elseif ($raw -match 'anthropic:\s*"anthropic-api"') {
                if ($DryRun) {
                    Write-Host ("  [dry-run] patch {0}" -f $labelPath) -ForegroundColor DarkYellow
                } else {
                    $updated = $raw -replace 'anthropic:\s*"anthropic-api"', 'anthropic: "anthropic"'
                    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                    [System.IO.File]::WriteAllText($labelPath, $updated, $utf8NoBom)
                    Write-Host '  [ok]      Normalized provider label anthropic-api -> anthropic' -ForegroundColor Green
                }
            } else {
                Write-Host '  [warn]    Model selector label map has unexpected shape; skipped label patch' -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host ("  [warn]    Failed to patch provider label: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    # --- Claude Code provider options: pathToClaudeCodeExecutable ---
    # Rewrite the whole getProviderOptions function body so that:
    #   1. pathToClaudeCodeExecutable is ALWAYS passed when provider is
    #      claude-code (the previous shape early-returned undefined when
    #      runner.hasUI() was false, so the SDK fell back to PATH lookup
    #      which on Windows picked up the scoop bash-script shim).
    #   2. A hardcoded resolved native path is used as a final fallback
    #      after env vars — so a gsd process started before CLAUDE_CODE_PATH
    #      was populated still finds the right binary.
    # Apply to every discoverable sdk.js (agent-dir bridge, local vendor,
    # scoop/npm global install) to stay resilient against reinstalls.
    $nativeClaudePath = Resolve-GsdClaudeCodeNativePath
    $escapedNativePath = if ($nativeClaudePath) { $nativeClaudePath.Replace('\','\\').Replace('"','\"') } else { '' }
    $patchMarker = '/*__GSD_CLAUDE_PATH_PATCHED__*/'

    $sdkCandidates = [System.Collections.Generic.List[string]]::new()
    $sdkCandidates.Add((Join-Path (Resolve-GsdAgentDir) 'node_modules\@gsd\pi-coding-agent\dist\core\sdk.js'))
    $sdkLocalRoot = Resolve-GsdPreferredRuntimeRoot
    if ($sdkLocalRoot) {
        $sdkCandidates.Add((Join-Path $sdkLocalRoot 'packages\pi-coding-agent\dist\core\sdk.js'))
    }
    try {
        $gsdCmdForSdk = Get-Command gsd -ErrorAction SilentlyContinue
        if ($gsdCmdForSdk -and $gsdCmdForSdk.Source) {
            $gsdBinForSdk = Split-Path $gsdCmdForSdk.Source -Parent
            # Direct packages/ copy (the source of truth in global install)
            $sdkCandidates.Add((Join-Path $gsdBinForSdk 'node_modules\gsd-pi\packages\pi-coding-agent\dist\core\sdk.js'))
            # Nested node_modules symlink — Node.js resolves @gsd/pi-coding-agent
            # from loader.js through this path first. On scoop it happens to
            # point at a test/latest/ directory; we need to patch THAT file too,
            # since it's what actually gets imported at runtime.
            $sdkCandidates.Add((Join-Path $gsdBinForSdk 'node_modules\gsd-pi\node_modules\@gsd\pi-coding-agent\dist\core\sdk.js'))
        }
    } catch {}

    $sdkDesiredBody = @"
        getProviderOptions: async (currentModel) => { $patchMarker
            if (currentModel.provider !== "claude-code")
                return undefined;
            const runner = extensionRunnerRef.current;
            const __claudePath = process.env.CLAUDE_CODE_PATH || process.env.CLAUDE_CODE_NATIVE_PATH || "$escapedNativePath";
            const __base = __claudePath ? { pathToClaudeCodeExecutable: __claudePath } : {};
            if (!runner?.hasUI())
                return Object.keys(__base).length ? __base : undefined;
            return Object.assign({ extensionUIContext: runner.getUIContext() }, __base);
        },
"@ -replace "`r`n", "`n"
    $sdkDesiredBody = $sdkDesiredBody.TrimEnd("`n")

    $sdkSeen = @{}
    $sdkPatchedAny = $false
    $sdkOkAny = $false
    $sdkFoundAny = $false
    foreach ($sdkPath in $sdkCandidates) {
        if (-not (Test-Path $sdkPath)) { continue }
        $sdkFull = [System.IO.Path]::GetFullPath($sdkPath)
        if ($sdkSeen.ContainsKey($sdkFull)) { continue }
        $sdkSeen[$sdkFull] = $true

        try {
            $raw = (Get-Content $sdkFull -Raw -Encoding UTF8) -replace "`r`n", "`n"

            if ($raw.Contains($patchMarker)) {
                Write-Host ("  [ok]      Claude path patch already applied  {0}" -f $sdkFull) -ForegroundColor Green
                $sdkOkAny = $true
                $sdkFoundAny = $true
                continue
            }

            # Match the whole getProviderOptions function body up to the
            # method-level `        },` (8-space indent). Lazy quantifier
            # prevents greedy overrun into the next method.
            $pattern = [regex]'(?s)getProviderOptions: async \(currentModel\) => \{.*?\n        \},'
            if ($pattern.IsMatch($raw)) {
                $sdkFoundAny = $true
                if ($DryRun) {
                    Write-Host ("  [dry-run] patch Claude provider options {0}" -f $sdkFull) -ForegroundColor DarkYellow
                } else {
                    $updated = $pattern.Replace($raw, { param($m) $sdkDesiredBody }, 1)
                    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                    [System.IO.File]::WriteAllText($sdkFull, $updated, $utf8NoBom)
                    Write-Host ("  [ok]      Patched Claude provider options  {0}" -f $sdkFull) -ForegroundColor Green
                    $sdkPatchedAny = $true
                }
            } else {
                Write-Host ("  [warn]    sdk.js: getProviderOptions shape not recognized  {0}" -f $sdkFull) -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host ("  [warn]    Failed to patch {0}: {1}" -f $sdkFull, $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
    if (-not $sdkFoundAny) {
        Write-Host '  [warn]    No sdk.js with getProviderOptions found to patch' -ForegroundColor DarkYellow
    }

    # --- Anthropic OAuth scope + endpoint patch ---
    # GSD's default OAuth config is missing the user:sessions:claude_code scope
    # and uses platform.claude.com instead of console.anthropic.com.
    # Without this scope, tokens get routed to "extra usage" billing instead
    # of the Claude Max subscription quota (same client_id, different scope).
    #
    # Patch ALL discoverable copies: (1) agent-dir bridge, (2) local-project vendor,
    # (3) the globally-installed gsd-pi that `gsd` CLI actually loads from
    # (scoop/npm/nvm — resolved via `Get-Command gsd`). Earlier versions only
    # touched (1) and (2), which left the active runtime unpatched.
    $oauthCandidates = [System.Collections.Generic.List[string]]::new()
    $oauthCandidates.Add((Join-Path (Resolve-GsdAgentDir) 'node_modules\gsd-pi\packages\pi-ai\dist\utils\oauth\anthropic.js'))

    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot) {
        $oauthCandidates.Add((Join-Path $localRoot 'packages\pi-ai\dist\utils\oauth\anthropic.js'))
    }

    # Resolve global gsd-pi via the gsd launcher (scoop/npm/nvm shim)
    try {
        $gsdCmd = Get-Command gsd -ErrorAction SilentlyContinue
        if ($gsdCmd -and $gsdCmd.Source) {
            $gsdBin = Split-Path $gsdCmd.Source -Parent
            $globalOauth = Join-Path $gsdBin 'node_modules\gsd-pi\packages\pi-ai\dist\utils\oauth\anthropic.js'
            $oauthCandidates.Add($globalOauth)
        }
    } catch {}

    # Dedupe (by fully-resolved path) and patch each existing file
    $seen = @{}
    $patchedAny = $false
    $okAny = $false
    foreach ($oauthPath in $oauthCandidates) {
        if (-not (Test-Path $oauthPath)) { continue }
        $full = [System.IO.Path]::GetFullPath($oauthPath)
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true

        try {
            $oauthRaw = (Get-Content $full -Raw -Encoding UTF8) -replace "`r`n", "`n"
            $needsPatch = $false
            $updated = $oauthRaw

            # Fix TOKEN_URL
            if ($updated -match 'platform\.claude\.com/v1/oauth/token') {
                $updated = $updated -replace 'platform\.claude\.com/v1/oauth/token', 'console.anthropic.com/v1/oauth/token'
                $needsPatch = $true
            }
            # Fix REDIRECT_URI
            if ($updated -match 'platform\.claude\.com/oauth/code/callback') {
                $updated = $updated -replace 'platform\.claude\.com/oauth/code/callback', 'console.anthropic.com/oauth/code/callback'
                $needsPatch = $true
            }
            # Fix SCOPES - add user:sessions:claude_code if missing
            if ($updated -match 'user:inference"' -and $updated -notmatch 'user:sessions:claude_code') {
                $updated = $updated -replace 'user:inference"', 'user:inference user:sessions:claude_code"'
                $needsPatch = $true
            }

            if (-not $needsPatch) {
                Write-Host ("  [ok]      OAuth already patched  {0}" -f $full) -ForegroundColor Green
                $okAny = $true
            } elseif ($DryRun) {
                Write-Host ("  [dry-run] patch OAuth scope/endpoint {0}" -f $full) -ForegroundColor DarkYellow
            } else {
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($full, $updated, $utf8NoBom)
                Write-Host ("  [ok]      Patched OAuth (scope+endpoint) {0}" -f $full) -ForegroundColor Green
                $patchedAny = $true
            }
        } catch {
            Write-Host ("  [warn]    Failed to patch {0}: {1}" -f $full, $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
    if (-not $patchedAny -and -not $okAny) {
        Write-Host '  [warn]    No Anthropic OAuth file found to patch (agent/vendor/global all missing)' -ForegroundColor DarkYellow
    }

    Write-Host ''
}

function Resolve-GsdResourceLoaderTarget {
    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot) {
        $localCandidates = @(
            (Join-Path $localRoot 'dist\resource-loader.js'),
            (Join-Path $localRoot 'packages\pi-coding-agent\dist\core\resource-loader.js')
        )
        foreach ($candidate in $localCandidates) {
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $candidates = @()

    $gsdCommand = Get-Command gsd -ErrorAction SilentlyContinue
    if ($gsdCommand) {
        try {
            $cmdDir = Split-Path $gsdCommand.Source -Parent
            $candidates += [System.IO.Path]::GetFullPath((Join-Path $cmdDir 'node_modules\gsd-pi\dist\resource-loader.js'))
            $candidates += [System.IO.Path]::GetFullPath((Join-Path $cmdDir 'node_modules\gsd-pi\packages\pi-coding-agent\dist\core\resource-loader.js'))
        } catch {}
    }

    $candidates += @(
        (Join-Path $HOME 'scoop\persist\nodejs-lts\bin\node_modules\gsd-pi\dist\resource-loader.js'),
        (Join-Path $HOME 'scoop\persist\nodejs-lts\bin\node_modules\gsd-pi\packages\pi-coding-agent\dist\core\resource-loader.js')
    )

    foreach ($candidate in ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-GsdResourceLoaderShimPath {
    return Join-Path (Resolve-GsdHome) 'resource-loader.js'
}

function Resolve-GsdRuntimeLayout {
    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot) {
        $localNodeModules = Join-Path $localRoot 'node_modules'
        return [pscustomobject]@{
            Origin            = 'local-project'
            Root              = $localRoot
            NodeModulesTarget = $localNodeModules
            ScopeTargetPath   = (Join-Path $localRoot 'packages')
            ExtensionDepsTarget = $localNodeModules
        }
    }

    $globalNodeModules = Resolve-GsdNodeModulesTarget
    if (-not $globalNodeModules) { return $null }

    return [pscustomobject]@{
        Origin            = 'global'
        Root              = (Join-Path $globalNodeModules 'gsd-pi')
        NodeModulesTarget = $globalNodeModules
        ScopeTargetPath   = (Join-Path $globalNodeModules 'gsd-pi\packages')
        ExtensionDepsTarget = (Join-Path $globalNodeModules 'gsd-pi\node_modules')
    }
}

function Resolve-GsdNodeModulesTarget {
    $candidates = @()

    $gsdCommand = Get-Command gsd -ErrorAction SilentlyContinue
    if ($gsdCommand) {
        try {
            $cmdDir = Split-Path $gsdCommand.Source -Parent
            $candidates += [System.IO.Path]::GetFullPath((Join-Path $cmdDir 'node_modules'))
        } catch {}
    }

    $candidates += @(
        (Join-Path $HOME 'scoop\apps\nodejs-lts\current\bin\node_modules'),
        (Join-Path $HOME 'scoop\persist\nodejs-lts\bin\node_modules')
    )

    foreach ($candidate in ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-GsdNodeModulesBridgeFix {
    param([switch]$DryRun)

    $agentDir = Resolve-GsdAgentDir
    $bridgePath = Join-Path $agentDir 'node_modules'
    $layout = Resolve-GsdRuntimeLayout

    Write-Host '  [gsd] Repairing node_modules bridge...' -ForegroundColor Cyan

    if (-not $layout) {
        Write-Host '  [warn]    Could not locate local or installed gsd-pi runtime layout' -ForegroundColor DarkYellow
        return
    }

    $targetPath = $layout.NodeModulesTarget
    $scopeTargetPath = $layout.ScopeTargetPath

    if (-not (Test-Path $targetPath)) {
        Write-Host ("  [warn]    Missing node_modules target: {0}" -f $targetPath) -ForegroundColor DarkYellow
        return
    }

    if (-not (Test-Path $scopeTargetPath)) {
        Write-Host ("  [warn]    Missing scoped package source: {0}" -f $scopeTargetPath) -ForegroundColor DarkYellow
    }

    $bridgeReady = $false
    if (Test-Path $bridgePath) {
        try {
            $item = Get-Item -LiteralPath $bridgePath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $item.Target -contains $targetPath) {
                $bridgeReady = $true
            }
        } catch {}
    }

    if ($DryRun) {
        if (-not $bridgeReady) {
            Write-Host ("  [dry-run] [{0}] bridge {1} -> {2}" -f $layout.Origin, $bridgePath, $targetPath) -ForegroundColor DarkYellow
        }
        $scopePath = Join-Path $bridgePath '@gsd'
        if (Test-Path $scopeTargetPath) {
            Write-Host ("  [dry-run] [{0}] bridge {1} -> {2}" -f $layout.Origin, $scopePath, $scopeTargetPath) -ForegroundColor DarkYellow
        }
        return
    }

    try {
        if (-not $bridgeReady) {
            if (Test-Path $bridgePath) {
                Remove-Item -LiteralPath $bridgePath -Recurse -Force -ErrorAction Stop
            }

            if (-not (Test-Path $agentDir)) {
                $null = New-Item -Path $agentDir -ItemType Directory -Force
            }

            $null = New-Item -Path $bridgePath -ItemType Junction -Target $targetPath -Force
            Write-Host ("  [ok]      Restored ~/.gsd/agent/node_modules bridge ({0})" -f $layout.Origin) -ForegroundColor Green
        } else {
            Write-Host ("  [ok]      ~/.gsd/agent/node_modules bridge already points at {0} runtime" -f $layout.Origin) -ForegroundColor Green
        }

        if (Test-Path $scopeTargetPath) {
            $scopePath = Join-Path $bridgePath '@gsd'
            $scopeReady = $false
            if (Test-Path $scopePath) {
                try {
                    $scopeItem = Get-Item -LiteralPath $scopePath -Force
                    if (($scopeItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $scopeItem.Target -contains $scopeTargetPath) {
                        $scopeReady = $true
                    }
                } catch {}
            }

            if (-not $scopeReady) {
                if (Test-Path $scopePath) {
                    Remove-Item -LiteralPath $scopePath -Recurse -Force -ErrorAction Stop
                }
                $null = New-Item -Path $scopePath -ItemType Junction -Target $scopeTargetPath -Force
                Write-Host ("  [ok]      Restored ~/.gsd/agent/node_modules/@gsd scope bridge ({0})" -f $layout.Origin) -ForegroundColor Green
            } else {
                Write-Host ("  [ok]      ~/.gsd/agent/node_modules/@gsd scope bridge already valid ({0})" -f $layout.Origin) -ForegroundColor Green
            }
        }

        $extDir = Join-Path $agentDir 'extensions'
        $extDepsTarget = $layout.ExtensionDepsTarget
        $extBridgePath = Join-Path $extDir 'node_modules'
        if (Test-Path $extDepsTarget) {
            $extBridgeReady = $false
            if (Test-Path $extBridgePath) {
                try {
                    $extItem = Get-Item -LiteralPath $extBridgePath -Force
                    if (($extItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $extItem.Target -contains $extDepsTarget) {
                        $extBridgeReady = $true
                    }
                } catch {}
            }

            if (-not $extBridgeReady) {
                if (Test-Path $extBridgePath) {
                    Remove-Item -LiteralPath $extBridgePath -Recurse -Force -ErrorAction Stop
                }
                if (-not (Test-Path $extDir)) {
                    $null = New-Item -Path $extDir -ItemType Directory -Force
                }
                $null = New-Item -Path $extBridgePath -ItemType Junction -Target $extDepsTarget -Force
                Write-Host ("  [ok]      Restored ~/.gsd/agent/extensions/node_modules deps bridge ({0})" -f $layout.Origin) -ForegroundColor Green
            } else {
                Write-Host ("  [ok]      ~/.gsd/agent/extensions/node_modules deps bridge already valid ({0})" -f $layout.Origin) -ForegroundColor Green
            }
        }
    } catch {
        Write-Host ("  [warn]    Failed to restore node_modules bridge: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

function Invoke-GsdResourceLoaderFix {
    param([switch]$DryRun)

    $shimPath = Get-GsdResourceLoaderShimPath
    $targetPath = Resolve-GsdResourceLoaderTarget

    Write-Host '  [gsd] Repairing resource-loader bridge...' -ForegroundColor Cyan

    if (-not $targetPath) {
        Write-Host '  [warn]    Could not locate installed gsd-pi resource-loader.js' -ForegroundColor DarkYellow
        return
    }

    $targetUri = [System.Uri]::new($targetPath).AbsoluteUri
    $shimContent = @"
export * from '${targetUri}';
"@

    if ((Test-Path $shimPath)) {
        try {
            $current = Get-Content $shimPath -Raw -Encoding UTF8
            if ($current -eq $shimContent) {
                Write-Host '  [ok]      resource-loader.js shim already points at installed gsd-pi runtime' -ForegroundColor Green
                return
            }
        } catch {
            Write-Host ("  [warn]    Failed to read existing resource-loader shim: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    if ($DryRun) {
        Write-Host ("  [dry-run] write {0} -> {1}" -f $shimPath, $targetPath) -ForegroundColor DarkYellow
        return
    }

    try {
        $parent = Split-Path $shimPath -Parent
        if (-not (Test-Path $parent)) {
            $null = New-Item -Path $parent -ItemType Directory -Force
        }
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($shimPath, $shimContent, $utf8NoBom)
        Write-Host '  [ok]      Restored ~/.gsd/resource-loader.js compatibility shim' -ForegroundColor Green
    } catch {
        Write-Host ("  [warn]    Failed to write resource-loader shim: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

function Invoke-GsdAutoExtensionLoaderPatch {
    param([switch]$DryRun)

    $autoPath = Join-Path (Resolve-GsdAgentDir) 'extensions\gsd\auto.js'
    if (-not (Test-Path $autoPath)) {
        Write-Host '  [warn]    auto.js not found under ~/.gsd/agent/extensions/gsd' -ForegroundColor DarkYellow
        return
    }

    $oldBlock = @"
        const _req = createRequire(import.meta.url);
        const pkgRoot = dirname(_req.resolve("gsd-pi/package.json"));
        const { initResources } = await import(join(pkgRoot, "dist", "resource-loader.js"));
"@

    $newBlock = @"
        const { initResources } = await import("../../../resource-loader.js");
"@

    try {
        $raw = Get-Content $autoPath -Raw -Encoding UTF8
        if ($raw.Contains($newBlock)) {
            Write-Host '  [ok]      auto.js already imports ~/.gsd/resource-loader.js bridge' -ForegroundColor Green
            return
        }

        if (-not $raw.Contains($oldBlock)) {
            Write-Host '  [warn]    auto.js has unexpected loader block shape; skipped patch' -ForegroundColor DarkYellow
            return
        }

        if ($DryRun) {
            Write-Host ("  [dry-run] patch {0}" -f $autoPath) -ForegroundColor DarkYellow
            return
        }

        $updated = $raw.Replace($oldBlock, $newBlock)
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($autoPath, $updated, $utf8NoBom)
        Write-Host '  [ok]      Patched auto.js to use ~/.gsd/resource-loader.js bridge' -ForegroundColor Green
    } catch {
        Write-Host ("  [warn]    Failed to patch auto.js loader import: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

function Invoke-GsdPackageRefresh {
    param(
        [switch]$DryRun,
        [switch]$AllowGlobal
    )

    Write-Host '  [gsd] Refreshing gsd-pi runtime...' -ForegroundColor Cyan

    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot) {
        Write-Host ("  [local]   preferred runtime: {0}" -f $localRoot) -ForegroundColor Cyan
        if (-not (Test-Path (Join-Path $localRoot 'package.json'))) {
            Write-Host '  [warn]    local runtime exists but package.json is missing; skipped refresh' -ForegroundColor DarkYellow
            return
        }

        if (Test-CommandExists 'npm') {
            if ($DryRun) {
                Write-Host ("  [dry-run] npm install  (cwd={0})" -f $localRoot) -ForegroundColor DarkYellow
            } else {
                try {
                    Push-Location $localRoot
                    & npm install
                    Pop-Location
                    Write-Host '  [ok]      npm install in local project runtime' -ForegroundColor Green
                } catch {
                    try { Pop-Location } catch {}
                    Write-Host ("  [warn]    Failed local npm install: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
                }
            }
        } elseif (Test-CommandExists 'bun') {
            if ($DryRun) {
                Write-Host ("  [dry-run] bun install  (cwd={0})" -f $localRoot) -ForegroundColor DarkYellow
            } else {
                try {
                    Push-Location $localRoot
                    & bun install
                    Pop-Location
                    Write-Host '  [ok]      bun install in local project runtime' -ForegroundColor Green
                } catch {
                    try { Pop-Location } catch {}
                    Write-Host ("  [warn]    Failed local bun install: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
                }
            }
        } else {
            Write-Host '  [warn]    Neither npm nor bun was found; cannot refresh local gsd-pi runtime automatically' -ForegroundColor DarkYellow
        }
        return
    }

    if (-not $AllowGlobal) {
        Write-Host '  [warn]    No local project runtime found. Global gsd-pi install is blocked by default.' -ForegroundColor DarkYellow
        Write-Host '  [hint]    Prepare .gsd/vendor/gsd-pi/current or baseline-2.69.0 first, or rerun with --allow-global after explicit approval.' -ForegroundColor DarkGray
        return
    }

    $pinnedPkg = "gsd-pi@$script:GsdPinnedVersion"

    if (Test-CommandExists 'npm') {
        if ($DryRun) {
            Write-Host ("  [dry-run] npm install -g {0}" -f $pinnedPkg) -ForegroundColor DarkYellow
        } else {
            try {
                & npm install -g $pinnedPkg
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host ("  [ok]      npm install -g {0}" -f $pinnedPkg) -ForegroundColor Green
                } else {
                    Write-Host ("  [warn]    npm install -g {0} exited with code {1}" -f $pinnedPkg, $LASTEXITCODE) -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host ("  [warn]    Failed to refresh gsd-pi with npm: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } elseif (Test-CommandExists 'bun') {
        if ($DryRun) {
            Write-Host ("  [dry-run] bun add -g {0}" -f $pinnedPkg) -ForegroundColor DarkYellow
        } else {
            try {
                & bun add -g $pinnedPkg
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host ("  [ok]      bun add -g {0}" -f $pinnedPkg) -ForegroundColor Green
                } else {
                    Write-Host ("  [warn]    bun add -g {0} exited with code {1}" -f $pinnedPkg, $LASTEXITCODE) -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host ("  [warn]    Failed to refresh gsd-pi with bun: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } else {
        Write-Host '  [warn]    Neither npm nor bun was found; cannot refresh gsd-pi automatically' -ForegroundColor DarkYellow
    }

    if (Test-CommandExists 'gsd') {
        if ($DryRun) {
            Write-Host '  [dry-run] gsd --version' -ForegroundColor DarkYellow
        } else {
            try {
                & gsd --version
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host '  [ok]      gsd --version' -ForegroundColor Green
                } else {
                    Write-Host ("  [warn]    gsd --version exited with code {0}" -f $LASTEXITCODE) -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host ("  [warn]    Failed to run gsd --version: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } else {
        Write-Host '  [warn]    gsd command not found after refresh' -ForegroundColor DarkYellow
    }
}

function Remove-GsdPathSafe {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if ($DryRun) {
        Write-Host ("  [dry-run] remove {0}" -f $Path) -ForegroundColor DarkYellow
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Host ("  [ok]      Removed {0}" -f $Path) -ForegroundColor Green
    } catch {
        Write-Host ("  [warn]    Failed to remove {0}: {1}" -f $Path, $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

function Backup-And-Remove-GsdPath {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "{0}.bak-{1}" -f $Path, $stamp

    if ($DryRun) {
        Write-Host ("  [dry-run] backup {0} -> {1}" -f $Path, $backupPath) -ForegroundColor DarkYellow
        Write-Host ("  [dry-run] remove {0}" -f $Path) -ForegroundColor DarkYellow
        return
    }

    try {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Host ("  [ok]      Backed up and removed {0}" -f $Path) -ForegroundColor Green
    } catch {
        Write-Host ("  [warn]    Failed to rebuild {0}: {1}" -f $Path, $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

function Invoke-GsdDbRepair {
    param(
        [switch]$DryRun,
        [switch]$Force,
        [string]$ProjectPath = (Get-Location).Path
    )

    $projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
    $projectGsd = Join-Path $projectRoot '.gsd'
    $dbPath = Join-Path $projectGsd 'gsd.db'

    Write-Host '  [gsd] Cleaning stale DB sidecars...' -ForegroundColor Cyan
    Remove-GsdPathSafe -Path "$dbPath-wal" -DryRun:$DryRun
    Remove-GsdPathSafe -Path "$dbPath-shm" -DryRun:$DryRun
    Remove-GsdPathSafe -Path "$dbPath-journal" -DryRun:$DryRun
    Remove-GsdPathSafe -Path (Join-Path $projectGsd 'auto.lock') -DryRun:$DryRun

    if ($Force) {
        Backup-And-Remove-GsdPath -Path (Join-Path $projectGsd 'completed-units.json') -DryRun:$DryRun
        Backup-And-Remove-GsdPath -Path (Join-Path $projectGsd 'routing-history.json') -DryRun:$DryRun
        Backup-And-Remove-GsdPath -Path $dbPath -DryRun:$DryRun
    } else {
        Write-Host '  [ok]      Preserved gsd.db and milestone caches (use --force to rebuild them)' -ForegroundColor Green
    }
}

function Show-GsdLocalStatus {
    $status = Get-GsdLocalRuntimeStatus

    Write-Host ''
    Write-HintSection 'GSD LOCAL RUNTIME -- project-scoped baseline and latest source'
    Write-Host ''
    if (-not $status.HasProjectRoot) {
        Write-Host '  No project-local .gsd/ root found from current directory.' -ForegroundColor DarkYellow
        Write-Host '  Expected layout lives under: <project>/.gsd/vendor/gsd-pi/' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ("  project   : {0}" -f $status.ProjectRoot) -ForegroundColor White
    Write-Host ("  vendor    : {0}" -f $status.VendorDir) -ForegroundColor DarkGray
    Write-Host ("  current   : {0}  [{1}]" -f $status.CurrentRoot,  $(if ($status.HasCurrent) { 'present' } else { 'missing' })) -ForegroundColor DarkGray
    Write-Host ("  baseline  : {0}  [{1}]" -f $status.BaselineRoot, $(if ($status.HasBaseline) { 'present' } else { 'missing' })) -ForegroundColor DarkGray
    Write-Host ("  latest    : {0}  [{1}]" -f $status.LatestRoot,   $(if ($status.HasLatest) { 'present' } else { 'missing' })) -ForegroundColor DarkGray
    Write-Host ("  preferred : {0}" -f $(if ($status.PreferredRoot) { $status.PreferredRoot } else { 'none -- global fallback only' })) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Intended contract:' -ForegroundColor Yellow
    Write-Host ("    - baseline-{0} = pinned known-good source snapshot" -f $script:GsdPinnedVersion) -ForegroundColor DarkGray
    Write-Host '    - latest         = git submodule or manual checkout of newest upstream source' -ForegroundColor DarkGray
    Write-Host '    - current        = active local runtime path used by bridge fixes and local refresh' -ForegroundColor DarkGray
    Write-Host '    - global install remains blocked unless --allow-global is provided' -ForegroundColor DarkGray
    Write-Host ''
}

$script:GsdPinnedVersion = '2.69.0'

$script:GsdProviderMenu = @(
    [pscustomobject]@{ Id='anthropic';         Label='Anthropic Claude';        Desc='claude-opus-4-6 (plan/research) + sonnet-4-6 (exec) + haiku-4-5 (simple/subagent)';  Type='oauth' }
    [pscustomobject]@{ Id='github-copilot';    Label='GitHub Copilot';          Desc='gemini-3.1-pro-preview 80.6% SWE + gpt-5-codex (needs Copilot subscription)';        Type='oauth' }
    [pscustomobject]@{ Id='google-gemini-cli'; Label='Google Gemini CLI';       Desc='gemini-3.1-pro-preview FREE 80.6% SWE, 2M ctx (Cloud Code Assist)';                  Type='oauth' }
    [pscustomobject]@{ Id='openai-codex';      Label='OpenAI Codex (OAuth)';    Desc='gpt-5.3-codex FREE via ChatGPT -- PLANNING ONLY (hits rate-limit during exec)';       Type='oauth' }
    [pscustomobject]@{ Id='zai';               Label='ZAI (z.ai) API key';      Desc='glm-5.1(exec,S+) glm-4.6v(vision+video,$0.30/M,c10) glm-4.5(c20) cascade $0.06-$4/M'; Type='key'   }
    [pscustomobject]@{ Id='groq';              Label='Groq API key';            Desc='kimi-k2-instruct + qwen3-32b FREE daily reset -- cheap subagent/simple tier';         Type='key'   }
    [pscustomobject]@{ Id='kimi-coding';       Label='Kimi Coding API key';     Desc='Kimi K2.5 ~77% SWE ($0.14/$2.5/M) -- top exec/subagent for cost-perf';               Type='key'   }
)

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
    'tavily'       = 'TAVILY_API_KEY'
    'brave'        = 'BRAVE_API_KEY'
    'ollama'       = 'OLLAMA_API_KEY'
    'context7'     = 'CONTEXT7_API_KEY'
    'jina'         = 'JINA_API_KEY'
}

$script:GsdProviderNotes = @{
    'zai'          = 'z.ai -- glm-5.1(S+) glm-5-turbo(c1) glm-5(c2) glm-4.7(c2) glm-4.5(c20) glm-4.6v(vision,c10,$0.30) glm-4.5v(vision,c10,$0.60)'
    'kimi-coding'  = 'platform.moonshot.cn -- Kimi K2.5 SWE 76.8% ($0.14/$2.5/M)'
    'groq'         = 'console.groq.com -- kimi-k2+qwen3-32b FREE daily reset'
    'google'       = 'aistudio.google.com -- gemini-2.5-pro API key (5RPM free tier)'
    'openrouter'   = 'openrouter.ai -- DeepSeek V3.2($0.28/$0.42) R1 + 200+ models, free tier có'
    'anthropic'    = 'console.anthropic.com -- paid key OR /login OAuth'
    'openai'       = 'platform.openai.com -- paid key OR /login openai-codex (free)'
    'xai'          = 'console.x.ai -- grok-4 free credits on signup'
    'mistral'      = 'console.mistral.ai -- pixtral-large, free tier'
    'tavily'       = 'tavily.com/app/api-keys -- web search, 1000 free/mo | /search-provider tavily'
    'brave'        = 'brave.com/search/api -- web search, 2000 free/mo | /search-provider brave'
    'ollama'       = 'local Ollama server token (optional) | /search-provider ollama'
    'context7'     = 'context7.com/dashboard -- doc lookup (already bundled in pi)'
    'jina'         = 'jina.ai/api -- fetch_page/web reader (optional, higher rate limit)'
}

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
    $Data | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
}

# =============================================================================
# Forge Claude Code OAuth token sync
# Reads the OAuth access_token from Forge's credentials and exports it as
# ANTHROPIC_API_KEY so gsd-pi's anthropic provider (and claude-code-cli
# readiness check) can authenticate without a separate Anthropic API key.
# =============================================================================

function Get-ForgeCredentialsPath {
    return Join-Path $HOME '.forge\.credentials.json'
}

function Read-ForgeClaudeCodeCredentials {
    $path = Get-ForgeCredentialsPath
    if (-not (Test-Path $path)) { return $null }

    try {
        $creds = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $entry = $creds | Where-Object { $_.id -eq 'claude_code' } | Select-Object -First 1
        if (-not $entry -or -not $entry.auth_details -or -not $entry.auth_details.o_auth) {
            return $null
        }

        $oauth = $entry.auth_details.o_auth
        return [pscustomobject]@{
            AccessToken  = [string]$oauth.tokens.access_token
            RefreshToken = [string]$oauth.tokens.refresh_token
            ExpiresAt    = [string]$oauth.tokens.expires_at
            TokenUrl     = [string]$oauth.config.token_url
            ClientId     = [string]$oauth.config.client_id
        }
    } catch {
        return $null
    }
}

function Test-ForgeClaudeCodeTokenExpired {
    param([Parameter(Mandatory)] [string]$ExpiresAt)

    try {
        $expiry = [DateTimeOffset]::Parse($ExpiresAt)
        $now = [DateTimeOffset]::UtcNow
        # Consider expired if less than 5 minutes remaining
        return ($expiry.AddMinutes(-5) -le $now)
    } catch {
        return $true
    }
}

function Invoke-ForgeClaudeCodeTokenRefresh {
    param(
        [Parameter(Mandatory)] [string]$RefreshToken,
        [Parameter(Mandatory)] [string]$TokenUrl,
        [Parameter(Mandatory)] [string]$ClientId
    )

    try {
        $body = @{
            grant_type    = 'refresh_token'
            refresh_token = $RefreshToken
            client_id     = $ClientId
        }

        $response = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

        if (-not $response.access_token) {
            return $null
        }

        return [pscustomobject]@{
            AccessToken  = [string]$response.access_token
            RefreshToken = if ($response.refresh_token) { [string]$response.refresh_token } else { $RefreshToken }
            ExpiresIn    = [int]$response.expires_in
        }
    } catch {
        return $null
    }
}

function Save-ForgeClaudeCodeTokens {
    param(
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string]$RefreshToken,
        [Parameter(Mandatory)] [int]$ExpiresIn
    )

    $path = Get-ForgeCredentialsPath
    if (-not (Test-Path $path)) { return }

    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        $creds = $raw | ConvertFrom-Json -ErrorAction Stop

        $expiresAt = [DateTimeOffset]::UtcNow.AddSeconds($ExpiresIn).ToString('o')

        for ($i = 0; $i -lt $creds.Count; $i++) {
            if ($creds[$i].id -eq 'claude_code') {
                $creds[$i].auth_details.o_auth.tokens.access_token = $AccessToken
                $creds[$i].auth_details.o_auth.tokens.refresh_token = $RefreshToken
                $creds[$i].auth_details.o_auth.tokens.expires_at = $expiresAt
                break
            }
        }

        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($path, ($creds | ConvertTo-Json -Depth 10), $utf8NoBom)
    } catch {
        # Silently fail -- credential write is best-effort
    }
}

function Sync-ForgeTokenToGsdAuthJson {
    <#
    .SYNOPSIS
    Writes the Forge OAuth token into ~/.gsd/agent/auth.json as the 'anthropic' credential.
    GSD reads auth.json BEFORE env vars for OAuth providers, so this is critical.
    The auth.json format uses Unix epoch milliseconds for 'expires'.
    #>
    param(
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string]$RefreshToken,
        [Parameter(Mandatory)] [string]$ExpiresAtIso,
        [switch]$Quiet
    )

    $authJsonPath = Join-Path $HOME '.gsd\agent\auth.json'
    if (-not (Test-Path $authJsonPath)) {
        # auth.json doesn't exist yet -- create it with the anthropic credential
        $parentDir = Split-Path $authJsonPath -Parent
        if (-not (Test-Path $parentDir)) {
            $null = New-Item -Path $parentDir -ItemType Directory -Force
        }
    }

    try {
        # Convert ISO expires_at to Unix epoch milliseconds (GSD's format)
        $expiryMs = [DateTimeOffset]::Parse($ExpiresAtIso).ToUnixTimeMilliseconds()

        # Read existing auth.json or start fresh
        $authData = @{}
        if (Test-Path $authJsonPath) {
            try {
                $raw = [System.IO.File]::ReadAllText($authJsonPath)
                $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                # Convert PSObject to hashtable for easier manipulation
                foreach ($prop in $parsed.PSObject.Properties) {
                    $authData[$prop.Name] = $prop.Value
                }
            } catch {
                # Malformed auth.json -- start fresh but preserve non-anthropic keys
                $authData = @{}
            }
        }

        # If claude-code CLI bridge is configured, do NOT write an anthropic OAuth entry.
        # GSD picks the anthropic OAuth entry first and fails with "Invalid API key" once the
        # Forge token expires; the CLI bridge is the durable path (claude.ai subscription).
        $ccEntry = $authData['claude-code']
        if ($ccEntry -and $ccEntry.type -eq 'cli') {
            if ($authData.Contains('anthropic')) {
                $authData.Remove('anthropic')
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                $json = $authData | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($authJsonPath, $json, $utf8NoBom)
                if (-not $Quiet) {
                    Write-Host '  [forge-sync] claude-code CLI bridge active -- removed stale anthropic OAuth entry' -ForegroundColor DarkGray
                }
            } elseif (-not $Quiet) {
                Write-Host '  [forge-sync] claude-code CLI bridge active -- skipping anthropic OAuth write' -ForegroundColor DarkGray
            }
            return $true
        }

        # Update the anthropic entry with Forge's OAuth token
        $authData['anthropic'] = [pscustomobject]@{
            type    = 'oauth'
            refresh = $RefreshToken
            access  = $AccessToken
            expires = $expiryMs
        }

        # Write back with UTF-8 (no BOM) -- same format GSD uses
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $json = $authData | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($authJsonPath, $json, $utf8NoBom)

        return $true
    } catch {
        if (-not $Quiet) {
            Write-Host ("  [forge-sync] auth.json write failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
        return $false
    }
}

function Invoke-GsdAuthFix {
    <#
    .SYNOPSIS
    Fix GSD Anthropic auth by writing {"claude-code":{"type":"cli"}} to auth.json.

    Root cause (gsd-build/gsd-2#4280): after Anthropic OAuth was removed from GSD,
    stale auth.json entries with shape {type:"oauth", access, refresh, expires} under
    the "anthropic" key cause a permanent cooldown/auth-loop. The correct fix is to:
      1. Remove the stale "anthropic" OAuth entry.
      2. Set "claude-code": {"type": "cli"} so GSD routes through the Claude Code CLI
         extension instead of trying to OAuth-authenticate with Anthropic directly.

    Safe to run repeatedly (idempotent).
    #>
    param([switch]$DryRun)

    Write-Host ''
    Write-Host '  GSD auth fix (ref: gsd-build/gsd-2#4280)' -ForegroundColor Cyan
    Write-Host '  Clears stale Anthropic OAuth entry, sets claude-code CLI provider.' -ForegroundColor DarkGray
    Write-Host ''

    $authJsonPath = Join-Path $HOME '.gsd\agent\auth.json'
    $agentDir     = Split-Path $authJsonPath -Parent

    # ---- read current state -------------------------------------------

    $authData = [ordered]@{}
    $hasStaleAnthropicOauth = $false
    $hasClaudeCodeCli       = $false

    if (Test-Path $authJsonPath) {
        try {
            $raw    = [System.IO.File]::ReadAllText($authJsonPath)
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $parsed.PSObject.Properties) {
                $authData[$prop.Name] = $prop.Value
            }

            $anthropicEntry = $authData['anthropic']
            if ($anthropicEntry -and $anthropicEntry.type -eq 'oauth') {
                $hasStaleAnthropicOauth = $true
                $exp = $anthropicEntry.expires
                $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $ageMin = if ($exp) { [math]::Round(($now - [long]$exp) / 60000) } else { '?' }
                Write-Host ("  [detect] Stale Anthropic OAuth entry found (expired {0} min ago)" -f $ageMin) -ForegroundColor DarkYellow
            }

            $ccEntry = $authData['claude-code']
            if ($ccEntry -and $ccEntry.type -eq 'cli') {
                $hasClaudeCodeCli = $true
                Write-Host '  [detect] claude-code CLI entry already present' -ForegroundColor DarkGray
            }
        } catch {
            Write-Host ("  [warn]   auth.json could not be parsed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            Write-Host '  Will create a clean auth.json.' -ForegroundColor DarkGray
        }
    } else {
        Write-Host '  [detect] auth.json does not exist yet -- will create.' -ForegroundColor DarkGray
    }

    # ---- nothing to do? -----------------------------------------------

    if (-not $hasStaleAnthropicOauth -and $hasClaudeCodeCli) {
        Write-Host '  [ok] auth.json already correct (no stale OAuth, claude-code CLI set).' -ForegroundColor Green
        Write-Host ''
        return
    }

    # ---- apply fix ----------------------------------------------------

    if ($DryRun) {
        Write-Host '  [dry-run] Would apply:' -ForegroundColor Yellow
        if ($hasStaleAnthropicOauth) {
            Write-Host '    - remove auth.json["anthropic"] (stale OAuth entry)' -ForegroundColor Yellow
        }
        Write-Host '    - set    auth.json["claude-code"] = {"type": "cli"}' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    # Ensure agent dir exists
    if (-not (Test-Path $agentDir)) {
        $null = New-Item -Path $agentDir -ItemType Directory -Force
    }

    # Backup existing auth.json
    if (Test-Path $authJsonPath) {
        $backup = $authJsonPath + '.bak-authfix-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        try {
            Copy-Item $authJsonPath $backup -Force
            Write-Host ("  [ok]     Backed up auth.json -> {0}" -f (Split-Path $backup -Leaf)) -ForegroundColor DarkGray
        } catch {
            Write-Host ("  [warn]   Could not backup auth.json: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    # Remove stale anthropic OAuth entry
    if ($hasStaleAnthropicOauth) {
        $authData.Remove('anthropic')
        Write-Host '  [ok]     Removed stale anthropic OAuth entry' -ForegroundColor Green
    }

    # Set claude-code CLI entry
    $authData['claude-code'] = [pscustomobject]@{ type = 'cli' }
    Write-Host '  [ok]     Set claude-code = {"type": "cli"}' -ForegroundColor Green

    # Write back
    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $json = $authData | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($authJsonPath, $json, $utf8NoBom)
        Write-Host ("  [ok]     Written: {0}" -f $authJsonPath) -ForegroundColor Green
    } catch {
        Write-Host ("  [error]  Could not write auth.json: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  Next: restart GSD session and run /model to verify claude-code provider is active.' -ForegroundColor Cyan
    Write-Host ''
}

function Invoke-GsdFixToolsCap {
    <#
    .SYNOPSIS
    Fix Anthropic 128-tool-definition cap error in gsd-pi claude-code bridge.

    Root cause: Anthropic API enforces a hard cap of 128 tool definitions per
    request. With multiple MCPs (gsd-workflow + project plugins) plus built-in
    Claude Code tools, gsd-pi exceeds the cap and gets HTTP 400:
        "tools": maximum number of items is 128

    Fix: Patches buildSdkOptions in
        ~/.gsd/agent/extensions/claude-code-cli/stream-adapter.js
    to inject 11 known gsd-workflow alias dupes into disallowedTools, plus a
    user-extensible env var GSD_CLAUDE_DISALLOWED_TOOLS (CSV, supports `*`).

    Marker comment [GSD-FIX-TOOLS-CAP v1] makes this idempotent. Re-run after
    every gsd-pi upgrade that wipes node_modules.
    #>
    param([switch]$DryRun)

    Write-Host ''
    Write-Host '  GSD fix-tools-cap (Anthropic 128-tool cap)' -ForegroundColor Cyan
    Write-Host '  Patches stream-adapter.js to drop 11 gsd-workflow alias dupes.' -ForegroundColor DarkGray
    Write-Host ''

    $marker  = '[GSD-FIX-TOOLS-CAP v1]'
    $adapter = Join-Path $HOME '.gsd\agent\extensions\claude-code-cli\stream-adapter.js'

    if (-not (Test-Path $adapter)) {
        Write-Host ("  [error]  stream-adapter.js not found: {0}" -f $adapter) -ForegroundColor Red
        Write-Host '  Install gsd-pi first: 8sync gsd setup --plan claude-max' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $content = [System.IO.File]::ReadAllText($adapter)

    if ($content.Contains($marker)) {
        Write-Host ("  [ok]     Already patched (marker {0} present)" -f $marker) -ForegroundColor Green
        Write-Host ''
        Write-Host '  To extend the disallow list, set:' -ForegroundColor DarkGray
        Write-Host '    $env:GSD_CLAUDE_DISALLOWED_TOOLS = "mcp__foo__bar,mcp__baz__*"' -ForegroundColor White
        Write-Host ''
        return
    }

    # ---- locate patch site --------------------------------------------
    # buildSdkOptions builds an `options` object with a `disallowedTools` array.
    # We inject right before the assignment using a stable anchor.

    $anchor = 'const disallowedTools = '
    $idx    = $content.IndexOf($anchor)
    if ($idx -lt 0) {
        # Fallback: try the property form `disallowedTools:` inside the options literal
        $anchor = 'disallowedTools:'
        $idx    = $content.IndexOf($anchor)
    }
    if ($idx -lt 0) {
        Write-Host '  [error]  Could not locate disallowedTools assignment in stream-adapter.js' -ForegroundColor Red
        Write-Host '  This may be a newer gsd-pi version. Open an issue or patch manually.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if ($DryRun) {
        Write-Host ("  [dry-run] Would inject {0} block before offset {1} in:" -f $marker, $idx) -ForegroundColor Yellow
        Write-Host ("    {0}" -f $adapter) -ForegroundColor Yellow
        Write-Host ''
        return
    }

    # ---- backup + patch ----------------------------------------------

    $backup = $adapter + '.bak-toolscap-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    try {
        Copy-Item $adapter $backup -Force
        Write-Host ("  [ok]     Backed up -> {0}" -f (Split-Path $backup -Leaf)) -ForegroundColor DarkGray
    } catch {
        Write-Host ("  [warn]   Could not backup: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }

    $patch = @'
// {{MARKER}} Anthropic enforces a hard cap of 128 tool definitions per
// request. With multiple MCPs (gsd-workflow + project plugins) plus the
// built-in Claude Code tools, the request can exceed that cap and 400 out.
// Always strip the 11 known gsd-workflow alias dupes; users can extend the
// list via GSD_CLAUDE_DISALLOWED_TOOLS (CSV of tool names, supports `*`
// wildcards as accepted by the SDK).
const __gsdDefaultDupes = [
    "mcp__gsd-workflow__gsd_save_decision",
    "mcp__gsd-workflow__gsd_save_requirement",
    "mcp__gsd-workflow__gsd_update_requirement",
    "mcp__gsd-workflow__gsd_milestone_complete",
    "mcp__gsd-workflow__gsd_milestone_generate_id",
    "mcp__gsd-workflow__gsd_milestone_validate",
    "mcp__gsd-workflow__gsd_slice_complete",
    "mcp__gsd-workflow__gsd_slice_replan",
    "mcp__gsd-workflow__gsd_task_complete",
    "mcp__gsd-workflow__gsd_task_plan",
    "mcp__gsd-workflow__gsd_roadmap_reassess",
];
const __gsdExtraDisallow = (process.env.GSD_CLAUDE_DISALLOWED_TOOLS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
const __gsdDisallowed = Array.from(new Set([...__gsdDefaultDupes, ...__gsdExtraDisallow]));

'@
    $patch = $patch.Replace('{{MARKER}}', $marker)

    # Insert immediately before the anchor line (find start of that line)
    $lineStart = $content.LastIndexOf("`n", $idx)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart += 1 }

    # Detect leading indent of the anchor line so the patch matches indentation
    $indent = ''
    $j = $lineStart
    while ($j -lt $content.Length -and ($content[$j] -eq ' ' -or $content[$j] -eq "`t")) {
        $indent += $content[$j]
        $j++
    }

    # Indent every line of the patch
    $indentedPatch = ($patch -split "`n" | ForEach-Object {
        if ([string]::IsNullOrEmpty($_)) { '' } else { $indent + $_ }
    }) -join "`n"

    # Rewrite the anchor line to consume our local var instead of inline expression
    # We splice: <patch>\n<indent>const disallowedTools = __gsdDisallowed;\n<rest>
    $lineEnd = $content.IndexOf("`n", $idx)
    if ($lineEnd -lt 0) { $lineEnd = $content.Length }

    $before  = $content.Substring(0, $lineStart)
    $after   = $content.Substring($lineEnd + 1)
    $newLine = $indent + 'const disallowedTools = __gsdDisallowed;'

    # If the anchor matched the property form (`disallowedTools:`), keep original
    # and just inject the var block above it (the property can still reference
    # __gsdDisallowed). Heuristic: if anchor starts with "const disallowedTools",
    # we replace the line; otherwise we keep it.
    $anchorLine = $content.Substring($lineStart, $lineEnd - $lineStart)
    if ($anchorLine.TrimStart().StartsWith('const disallowedTools')) {
        $patched = $before + $indentedPatch + $newLine + "`n" + $after
    } else {
        # Property form -- inject var block, leave existing line intact
        $patched = $before + $indentedPatch + $anchorLine + "`n" + $after
        Write-Host '  [info]   Property-form disallowedTools detected; injected var block only.' -ForegroundColor DarkGray
        Write-Host '           Edit stream-adapter.js manually if dupes still leak through.' -ForegroundColor DarkGray
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($adapter, $patched, $utf8NoBom)

    # ---- syntax check -------------------------------------------------

    $nodeOk = $false
    try {
        $checkOut = & node --check $adapter 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { $nodeOk = $true }
        else {
            Write-Host '  [error]  node --check failed:' -ForegroundColor Red
            Write-Host $checkOut -ForegroundColor Red
        }
    } catch {
        Write-Host ("  [warn]   node not on PATH; skipping syntax check: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        $nodeOk = $true  # don't roll back if node is unavailable
    }

    if (-not $nodeOk) {
        Write-Host '  [rollback] Restoring from backup.' -ForegroundColor Yellow
        Copy-Item $backup $adapter -Force
        Write-Host ''
        return
    }

    Write-Host ("  [ok]     Patched: {0}" -f $adapter) -ForegroundColor Green
    Write-Host ("  [ok]     Marker:  {0}" -f $marker) -ForegroundColor Green
    Write-Host ''
    Write-Host '  Next: re-run gsd from your project. If 128-cap still fires, extend disallow list:' -ForegroundColor Cyan
    Write-Host '    $env:GSD_CLAUDE_DISALLOWED_TOOLS = "mcp__foo__bar,mcp__baz__*"' -ForegroundColor White
    Write-Host ''
    Write-Host '  If still broken, nuclear option: 8sync gsd reset-auth' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdResetAuth {
    <#
    .SYNOPSIS
    Nuclear-option auth reset. Wipes ~/.gsd/agent/auth.json (with backup),
    then sets claude-code: {"type": "cli"} so a fresh `claude /login` flow
    gets picked up cleanly.

    Use when fix-tools-cap + auth-fix didn't unstick the bridge.
    #>
    param([switch]$DryRun)

    Write-Host ''
    Write-Host '  GSD reset-auth (nuclear)' -ForegroundColor Cyan
    Write-Host '  Backs up auth.json, wipes everything, sets claude-code CLI.' -ForegroundColor DarkGray
    Write-Host ''

    $authJsonPath = Join-Path $HOME '.gsd\agent\auth.json'
    $agentDir     = Split-Path $authJsonPath -Parent

    if ($DryRun) {
        Write-Host '  [dry-run] Would:' -ForegroundColor Yellow
        if (Test-Path $authJsonPath) {
            Write-Host ("    - backup {0} -> auth.json.bak-resetauth-<ts>" -f $authJsonPath) -ForegroundColor Yellow
        }
        Write-Host '    - write fresh auth.json: { "claude-code": {"type":"cli"} }' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    if (-not (Test-Path $agentDir)) {
        $null = New-Item -Path $agentDir -ItemType Directory -Force
    }

    if (Test-Path $authJsonPath) {
        $backup = $authJsonPath + '.bak-resetauth-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        try {
            Copy-Item $authJsonPath $backup -Force
            Write-Host ("  [ok]     Backed up -> {0}" -f (Split-Path $backup -Leaf)) -ForegroundColor DarkGray
        } catch {
            Write-Host ("  [warn]   Could not backup: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '  [info]   auth.json does not exist yet; creating fresh.' -ForegroundColor DarkGray
    }

    $fresh = [pscustomobject]@{
        'claude-code' = [pscustomobject]@{ type = 'cli' }
    }

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $json = $fresh | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($authJsonPath, $json, $utf8NoBom)
        Write-Host ("  [ok]     Written: {0}" -f $authJsonPath) -ForegroundColor Green
    } catch {
        Write-Host ("  [error]  Could not write auth.json: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return
    }

    # ---- verify Claude Code CLI login state --------------------------

    $claudeOk = $false
    try {
        $authOutput = & claude auth status 2>&1 | Out-String
        if ($authOutput -match '"loggedIn":\s*true') {
            $claudeOk = $true
            Write-Host '  [ok]     claude auth status: loggedIn=true' -ForegroundColor Green
        } else {
            Write-Host '  [warn]   claude auth status did not confirm login' -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host ("  [warn]   could not run `claude auth status`: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }

    Write-Host ''
    Write-Host '  Next steps:' -ForegroundColor Cyan
    if (-not $claudeOk) {
        Write-Host '    1. Run: claude /login        (or `claude` then /login)' -ForegroundColor White
        Write-Host '    2. Re-verify: claude auth status' -ForegroundColor White
        Write-Host '    3. Then: 8sync gsd fix-tools-cap   (re-applies tool-cap patch)' -ForegroundColor White
    } else {
        Write-Host '    1. 8sync gsd fix-tools-cap   (re-applies tool-cap patch)' -ForegroundColor White
        Write-Host '    2. Test: gsd --print "ping" --profile claude-max' -ForegroundColor White
    }
    Write-Host ''
}

function Sync-ForgeClaudeCodeToken {
    <#
    .SYNOPSIS
    Reads Forge's Claude Code OAuth token and syncs it to:
      1. $env:ANTHROPIC_API_KEY (for env-var based auth)
      2. ~/.gsd/agent/auth.json  (for GSD's internal OAuth credential store)
    Refreshes the token automatically if expired. Returns status object.
    #>
    param([switch]$Quiet)

    $cred = Read-ForgeClaudeCodeCredentials
    if (-not $cred -or [string]::IsNullOrWhiteSpace($cred.AccessToken)) {
        if (-not $Quiet) {
            Write-Host '  [forge-sync] No Claude Code OAuth credentials found in ~/.forge/.credentials.json' -ForegroundColor DarkYellow
        }
        return [pscustomobject]@{ Status='no-credentials'; Synced=$false }
    }

    $token = $cred.AccessToken
    $refreshToken = $cred.RefreshToken
    $expiresAtIso = $cred.ExpiresAt
    $refreshed = $false

    # Check expiry and refresh if needed
    if (-not [string]::IsNullOrWhiteSpace($cred.ExpiresAt) -and (Test-ForgeClaudeCodeTokenExpired -ExpiresAt $cred.ExpiresAt)) {
        if (-not $Quiet) {
            Write-Host '  [forge-sync] Token expired, refreshing...' -ForegroundColor Yellow
        }

        $refreshResult = Invoke-ForgeClaudeCodeTokenRefresh `
            -RefreshToken $cred.RefreshToken `
            -TokenUrl $cred.TokenUrl `
            -ClientId $cred.ClientId

        if ($refreshResult) {
            $token = $refreshResult.AccessToken
            $refreshToken = $refreshResult.RefreshToken
            $expiresAtIso = [DateTimeOffset]::UtcNow.AddSeconds($refreshResult.ExpiresIn).ToString('o')
            $refreshed = $true

            # Persist refreshed tokens back to Forge's credential store
            Save-ForgeClaudeCodeTokens `
                -AccessToken $refreshResult.AccessToken `
                -RefreshToken $refreshResult.RefreshToken `
                -ExpiresIn $refreshResult.ExpiresIn

            if (-not $Quiet) {
                Write-Host '  [forge-sync] Token refreshed successfully' -ForegroundColor Green
            }
        } else {
            if (-not $Quiet) {
                Write-Host '  [forge-sync] Token refresh failed; using existing (possibly expired) token' -ForegroundColor DarkYellow
            }
        }
    }

    # 1. Export to environment for gsd-pi env-var fallback and claude CLI
    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $token, 'Process')

    # 2. Sync into ~/.gsd/agent/auth.json so GSD's internal OAuth store uses the fresh token.
    #    GSD reads auth.json BEFORE env vars for OAuth providers, so this is the primary path.
    $authJsonSynced = Sync-ForgeTokenToGsdAuthJson `
        -AccessToken $token `
        -RefreshToken $refreshToken `
        -ExpiresAtIso $expiresAtIso `
        -Quiet:$Quiet

    if (-not $Quiet) {
        $statusLabel = if ($refreshed) { 'refreshed+synced' } else { 'synced' }
        Write-Host ("  [forge-sync] ANTHROPIC_API_KEY set from Forge Claude Code OAuth ({0})" -f $statusLabel) -ForegroundColor Green
        if ($authJsonSynced) {
            Write-Host '  [forge-sync] ~/.gsd/agent/auth.json anthropic credential updated' -ForegroundColor Green
        }
    }

    return [pscustomobject]@{ Status=if ($refreshed) { 'refreshed' } else { 'synced' }; Synced=$true; AuthJsonSynced=$authJsonSynced }
}

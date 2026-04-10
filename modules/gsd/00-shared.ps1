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
            } else {
                $labelStatus = 'custom'
            }
        } catch {
            $labelStatus = 'error'
        }
    }

    $defaultProvider = ''
    $defaultModel = ''
    $settingsStatus = 'missing'
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $defaultProvider = [string]$settings.defaultProvider
            $defaultModel = [string]$settings.defaultModel
            $settingsStatus = 'ok'
        } catch {
            $settingsStatus = 'error'
        }
    }

    return [pscustomobject]@{
        ProviderPatch = $providerStatus
        UiLabel       = $labelStatus
        Settings      = $settingsStatus
        DefaultProvider = $defaultProvider
        DefaultModel    = $defaultModel
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
            $raw = Get-Content $providerPath -Raw -Encoding UTF8
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
            if ($raw -match 'anthropic:\s*"anthropic"') {
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

    Write-Host ''
}

$script:GsdProviderMenu = @(
    [pscustomobject]@{ Id='anthropic';         Label='Anthropic Claude';        Desc='claude-opus-4-6 (plan/research) + sonnet-4-6 (exec) + haiku-4-5 (simple/subagent)';  Type='oauth' }
    [pscustomobject]@{ Id='github-copilot';    Label='GitHub Copilot';          Desc='gemini-3.1-pro-preview 80.6% SWE + gpt-5-codex (needs Copilot subscription)';        Type='oauth' }
    [pscustomobject]@{ Id='google-gemini-cli'; Label='Google Gemini CLI';       Desc='gemini-3.1-pro-preview FREE 80.6% SWE, 2M ctx (Cloud Code Assist)';                  Type='oauth' }
    [pscustomobject]@{ Id='openai-codex';      Label='OpenAI Codex (OAuth)';    Desc='gpt-5.3-codex FREE via ChatGPT — PLANNING ONLY (hits rate-limit during exec)';       Type='oauth' }
    [pscustomobject]@{ Id='zai';               Label='ZAI (z.ai) API key';      Desc='glm-5.1(exec,S+) glm-4.6v(vision+video,$0.30/M,c10) glm-4.5(c20) cascade $0.06-$4/M'; Type='key'   }
    [pscustomobject]@{ Id='groq';              Label='Groq API key';            Desc='kimi-k2-instruct + qwen3-32b FREE daily reset — cheap subagent/simple tier';         Type='key'   }
    [pscustomobject]@{ Id='kimi-coding';       Label='Kimi Coding API key';     Desc='Kimi K2.5 ~77% SWE ($0.14/$2.5/M) — top exec/subagent for cost-perf';               Type='key'   }
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

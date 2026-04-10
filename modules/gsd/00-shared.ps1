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
            } elseif ($raw -match 'row\.provider' -and $raw -notmatch 'anthropic:\s*"') {
                # New GSD version uses dynamic row.provider — no label map to patch
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

    Write-Host ''
}

function Resolve-GsdResourceLoaderTarget {
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
    $targetPath = Resolve-GsdNodeModulesTarget

    Write-Host '  [gsd] Repairing node_modules bridge...' -ForegroundColor Cyan

    if (-not $targetPath) {
        Write-Host '  [warn]    Could not locate installed node_modules for gsd-pi' -ForegroundColor DarkYellow
        return
    }

    $scopeTargetPath = Join-Path $targetPath 'gsd-pi\packages'
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
            Write-Host ("  [dry-run] bridge {0} -> {1}" -f $bridgePath, $targetPath) -ForegroundColor DarkYellow
        }
        $scopePath = Join-Path $bridgePath '@gsd'
        if (Test-Path $scopeTargetPath) {
            Write-Host ("  [dry-run] bridge {0} -> {1}" -f $scopePath, $scopeTargetPath) -ForegroundColor DarkYellow
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
            Write-Host '  [ok]      Restored ~/.gsd/agent/node_modules bridge' -ForegroundColor Green
        } else {
            Write-Host '  [ok]      ~/.gsd/agent/node_modules bridge already points at installed runtime' -ForegroundColor Green
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
                Write-Host '  [ok]      Restored ~/.gsd/agent/node_modules/@gsd scope bridge' -ForegroundColor Green
            } else {
                Write-Host '  [ok]      ~/.gsd/agent/node_modules/@gsd scope bridge already valid' -ForegroundColor Green
            }
        }

        $extDir = Join-Path $agentDir 'extensions'
        $extDepsTarget = Join-Path $targetPath 'gsd-pi\node_modules'
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
                Write-Host '  [ok]      Restored ~/.gsd/agent/extensions/node_modules deps bridge' -ForegroundColor Green
            } else {
                Write-Host '  [ok]      ~/.gsd/agent/extensions/node_modules deps bridge already valid' -ForegroundColor Green
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
    param([switch]$DryRun)

    Write-Host '  [gsd] Refreshing gsd-pi runtime...' -ForegroundColor Cyan

    if (Test-CommandExists 'npm') {
        if ($DryRun) {
            Write-Host '  [dry-run] npm install -g gsd-pi@latest' -ForegroundColor DarkYellow
        } else {
            try {
                & npm install -g gsd-pi@latest
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host '  [ok]      npm install -g gsd-pi@latest' -ForegroundColor Green
                } else {
                    Write-Host ("  [warn]    npm install -g gsd-pi@latest exited with code {0}" -f $LASTEXITCODE) -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host ("  [warn]    Failed to refresh gsd-pi with npm: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } elseif (Test-CommandExists 'bun') {
        if ($DryRun) {
            Write-Host '  [dry-run] bun add -g gsd-pi@latest' -ForegroundColor DarkYellow
        } else {
            try {
                & bun add -g gsd-pi@latest
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host '  [ok]      bun add -g gsd-pi@latest' -ForegroundColor Green
                } else {
                    Write-Host ("  [warn]    bun add -g gsd-pi@latest exited with code {0}" -f $LASTEXITCODE) -ForegroundColor DarkYellow
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

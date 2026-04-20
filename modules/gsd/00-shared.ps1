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

function Invoke-GsdModelRegistryPatch {
    param([switch]$DryRun)

    $piAiDir = Get-GsdPiAiModelsDir
    if (-not $piAiDir) { return }

    $genFile = Join-Path $piAiDir 'models.generated.js'
    $modelsFile = Join-Path $piAiDir 'models.js'

    if (-not (Test-Path $genFile)) {
        Write-Host '  [warn]    models.generated.js not found -- skipping model registry patch' -ForegroundColor DarkYellow
        return
    }

    # -- 1) Inject claude-opus-4-7 entry into models.generated.js (anthropic section)
    $genRaw = Get-Content $genFile -Raw -Encoding UTF8
    if ($genRaw -match 'claude-opus-4-7') {
        Write-Host '  [ok]      claude-opus-4-7 already in model registry' -ForegroundColor Green
    } else {
        $opus47Entry = @'
        "claude-opus-4-7": {
            id: "claude-opus-4-7",
            name: "Claude Opus 4.7",
            api: "anthropic-messages",
            provider: "anthropic",
            baseUrl: "https://api.anthropic.com",
            reasoning: true,
            input: ["text", "image"],
            cost: {
                input: 5,
                output: 25,
                cacheRead: 0.5,
                cacheWrite: 6.25,
            },
            contextWindow: 1000000,
            maxTokens: 128000,
        },
'@
        # Insert right after the claude-opus-4-6 entry closing
        $anchor = '"claude-opus-4-6":'
        $anchorIdx = $genRaw.IndexOf($anchor)
        if ($anchorIdx -ge 0) {
            # Find the closing "}," for this entry (next "}," after the anchor block)
            $searchFrom = $anchorIdx
            $closingPattern = "`n        },"
            $closingIdx = $genRaw.IndexOf($closingPattern, $searchFrom)
            if ($closingIdx -ge 0) {
                $insertAt = $closingIdx + $closingPattern.Length
                if ($DryRun) {
                    Write-Host '  [dry-run] would inject claude-opus-4-7 into models.generated.js' -ForegroundColor DarkYellow
                } else {
                    $genRaw = $genRaw.Insert($insertAt, "`n$opus47Entry")
                    [System.IO.File]::WriteAllText($genFile, $genRaw, [System.Text.UTF8Encoding]::new($false))
                    Write-Host '  [ok]      Injected claude-opus-4-7 into models.generated.js' -ForegroundColor Green
                }
            } else {
                Write-Host '  [warn]    Could not locate opus-4-6 entry boundary -- skipping injection' -ForegroundColor DarkYellow
            }
        } else {
            Write-Host '  [warn]    Could not find claude-opus-4-6 anchor in models.generated.js' -ForegroundColor DarkYellow
        }
    }

    # -- 2) Add capability patch for opus-4-7 in models.js (supportsXhigh)
    if (Test-Path $modelsFile) {
        $modRaw = Get-Content $modelsFile -Raw -Encoding UTF8
        if ($modRaw -match 'opus-4-7|opus-4\.7') {
            Write-Host '  [ok]      opus-4-7 capability patch already in models.js' -ForegroundColor Green
        } else {
            $oldCaps = 'match: (m) => m.api === "anthropic-messages" && (m.id.includes("opus-4-6") || m.id.includes("opus-4.6")),'
            $newCaps = 'match: (m) => m.api === "anthropic-messages" && (m.id.includes("opus-4-6") || m.id.includes("opus-4.6") || m.id.includes("opus-4-7") || m.id.includes("opus-4.7")),'
            if ($modRaw.Contains($oldCaps)) {
                if ($DryRun) {
                    Write-Host '  [dry-run] would patch opus-4-7 xhigh capability in models.js' -ForegroundColor DarkYellow
                } else {
                    $modRaw = $modRaw.Replace($oldCaps, $newCaps)
                    [System.IO.File]::WriteAllText($modelsFile, $modRaw, [System.Text.UTF8Encoding]::new($false))
                    Write-Host '  [ok]      Patched opus-4-7 xhigh capability in models.js' -ForegroundColor Green
                }
            } else {
                Write-Host '  [warn]    Could not find capability patch anchor in models.js' -ForegroundColor DarkYellow
            }
        }
    }
}

function Get-GsdPiAiModelsDir {
    $localRoot = Resolve-GsdPreferredRuntimeRoot
    if ($localRoot) {
        $localDir = Join-Path $localRoot 'packages\pi-ai\dist'
        if (Test-Path $localDir) { return $localDir }
    }

    $gsdPiBase = $null
    if (Test-CommandExists 'gsd') {
        try {
            $gsdBin = (Get-Command gsd -ErrorAction SilentlyContinue).Source
            if ($gsdBin) {
                $gsdPiBase = Split-Path (Split-Path $gsdBin)
                if (-not (Test-Path (Join-Path $gsdPiBase 'packages'))) {
                    $gsdPiBase = Join-Path (Split-Path $gsdBin) 'node_modules\gsd-pi'
                }
            }
        } catch {}
    }
    if (-not $gsdPiBase -or -not (Test-Path $gsdPiBase)) {
        $gsdPiBase = Join-Path $HOME 'scoop\persist\nodejs-lts\bin\node_modules\gsd-pi'
    }
    $dir = Join-Path $gsdPiBase 'packages\pi-ai\dist'
    if (Test-Path $dir) { return $dir }
    return $null
}

# Known model templates -- extend this table when new models launch
$script:GsdModelTemplates = @{
    'claude-opus-4-7' = @{
        name = 'Claude Opus 4.7'; api = 'anthropic-messages'; provider = 'anthropic'
        baseUrl = 'https://api.anthropic.com'; reasoning = $true; input = @('text','image')
        costIn = 5; costOut = 25; cacheRead = 0.5; cacheWrite = 6.25
        contextWindow = 1000000; maxTokens = 128000; xhigh = $true
    }
    'claude-sonnet-4-7' = @{
        name = 'Claude Sonnet 4.7'; api = 'anthropic-messages'; provider = 'anthropic'
        baseUrl = 'https://api.anthropic.com'; reasoning = $true; input = @('text','image')
        costIn = 3; costOut = 15; cacheRead = 0.3; cacheWrite = 3.75
        contextWindow = 1000000; maxTokens = 128000; xhigh = $true
    }
    'claude-opus-4-6' = @{
        name = 'Claude Opus 4.6'; api = 'anthropic-messages'; provider = 'anthropic'
        baseUrl = 'https://api.anthropic.com'; reasoning = $true; input = @('text','image')
        costIn = 5; costOut = 25; cacheRead = 0.5; cacheWrite = 6.25
        contextWindow = 1000000; maxTokens = 128000; xhigh = $true
    }
}

function Invoke-GsdModelAdd {
    param(
        [string[]]$Rest,
        [switch]$DryRun
    )

    $modelId = ($Rest | Where-Object { $_ -notlike '--*' } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        Write-Host ''
        Write-Host '  Usage: 8sync gsd model add <model-id>' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Available model templates:' -ForegroundColor Cyan
        foreach ($k in $script:GsdModelTemplates.Keys | Sort-Object) {
            $t = $script:GsdModelTemplates[$k]
            Write-Host ("    {0,-30} {1} (${2}/{3} per 1M tokens)" -f $k, $t.name, $t.costIn, $t.costOut) -ForegroundColor Gray
        }
        Write-Host ''
        Write-Host '  Or specify any model-id -- it will be added based on opus-4-6 template.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $piAiDir = Get-GsdPiAiModelsDir
    if (-not $piAiDir) {
        Write-Host '  [err]     Cannot locate gsd-pi models directory' -ForegroundColor Red
        return
    }

    $genFile = Join-Path $piAiDir 'models.generated.js'
    $modelsFile = Join-Path $piAiDir 'models.js'

    if (-not (Test-Path $genFile)) {
        Write-Host '  [err]     models.generated.js not found' -ForegroundColor Red
        return
    }

    $genRaw = Get-Content $genFile -Raw -Encoding UTF8
    if ($genRaw -match [regex]::Escape("`"$modelId`"")) {
        Write-Host ("  [ok]      {0} already exists in model registry" -f $modelId) -ForegroundColor Green
        return
    }

    # Resolve template
    $tmpl = $script:GsdModelTemplates[$modelId]
    if (-not $tmpl) {
        # Infer from model ID pattern
        if ($modelId -match 'opus') {
            $tmpl = $script:GsdModelTemplates['claude-opus-4-6'].Clone()
        } elseif ($modelId -match 'sonnet') {
            $tmpl = $script:GsdModelTemplates['claude-sonnet-4-7'].Clone()
        } else {
            $tmpl = $script:GsdModelTemplates['claude-opus-4-6'].Clone()
        }
        $tmpl.name = $modelId -replace '-', ' ' -replace '(\b\w)', { $_.Value.ToUpper() }
    }

    $inputArr = ($tmpl.input | ForEach-Object { "`"$_`"" }) -join ', '
    $entry = @"
        "$modelId": {
            id: "$modelId",
            name: "$($tmpl.name)",
            api: "$($tmpl.api)",
            provider: "$($tmpl.provider)",
            baseUrl: "$($tmpl.baseUrl)",
            reasoning: $($tmpl.reasoning.ToString().ToLower()),
            input: [$inputArr],
            cost: {
                input: $($tmpl.costIn),
                output: $($tmpl.costOut),
                cacheRead: $($tmpl.cacheRead),
                cacheWrite: $($tmpl.cacheWrite),
            },
            contextWindow: $($tmpl.contextWindow),
            maxTokens: $($tmpl.maxTokens),
        },
"@

    # Find anchor: insert after claude-opus-4-6 or last anthropic entry
    $anchor = '"claude-opus-4-6":'
    $anchorIdx = $genRaw.IndexOf($anchor)
    if ($anchorIdx -lt 0) {
        $anchor = '"claude-opus-4-5":'
        $anchorIdx = $genRaw.IndexOf($anchor)
    }

    if ($anchorIdx -ge 0) {
        $closingPattern = "`n        },"
        $closingIdx = $genRaw.IndexOf($closingPattern, $anchorIdx)
        if ($closingIdx -ge 0) {
            $insertAt = $closingIdx + $closingPattern.Length
            if ($DryRun) {
                Write-Host ("  [dry-run] would add {0} to model registry" -f $modelId) -ForegroundColor DarkYellow
            } else {
                $genRaw = $genRaw.Insert($insertAt, "`n$entry")
                [System.IO.File]::WriteAllText($genFile, $genRaw, [System.Text.UTF8Encoding]::new($false))
                Write-Host ("  [ok]      Added {0} to model registry" -f $modelId) -ForegroundColor Green
            }
        } else {
            Write-Host '  [err]     Could not find entry boundary in models.generated.js' -ForegroundColor Red
            return
        }
    } else {
        Write-Host '  [err]     Could not find anchor entry in models.generated.js' -ForegroundColor Red
        return
    }

    # Patch xhigh capability if needed
    if ($tmpl.xhigh -and (Test-Path $modelsFile)) {
        $modRaw = Get-Content $modelsFile -Raw -Encoding UTF8
        $shortId = $modelId -replace 'claude-', ''
        $dotId = $shortId -replace '-(\d)', '.$1'
        if ($modRaw -notmatch [regex]::Escape($shortId)) {
            # Find the anthropic capability patch line and extend it
            $pattern = 'm.id.includes\("opus-4-6"\) \|\| m.id.includes\("opus-4\.6"\)'
            if ($modRaw -match $pattern) {
                $oldMatch = ($modRaw | Select-String -Pattern $pattern -AllMatches).Matches[0].Value
                $newMatch = "$oldMatch || m.id.includes(`"$shortId`") || m.id.includes(`"$dotId`")"
                if (-not $DryRun) {
                    $modRaw = $modRaw.Replace($oldMatch, $newMatch)
                    [System.IO.File]::WriteAllText($modelsFile, $modRaw, [System.Text.UTF8Encoding]::new($false))
                    Write-Host ("  [ok]      Patched xhigh capability for {0}" -f $modelId) -ForegroundColor Green
                }
            }
        }
    }
}

function Invoke-GsdModelList {
    $piAiDir = Get-GsdPiAiModelsDir
    if (-not $piAiDir) {
        Write-Host '  [err]     Cannot locate gsd-pi models directory' -ForegroundColor Red
        return
    }

    $genFile = Join-Path $piAiDir 'models.generated.js'
    if (-not (Test-Path $genFile)) {
        Write-Host '  [err]     models.generated.js not found' -ForegroundColor Red
        return
    }

    $genRaw = Get-Content $genFile -Raw -Encoding UTF8
    $matches = [regex]::Matches($genRaw, '"(claude-[^"]+)":\s*\{[^}]*name:\s*"([^"]+)"')

    Write-Host ''
    Write-Host '  Anthropic models in GSD registry:' -ForegroundColor Cyan
    Write-Host ''
    $seen = @{}
    foreach ($m in $matches) {
        $id = $m.Groups[1].Value
        $name = $m.Groups[2].Value
        if (-not $seen.ContainsKey($id)) {
            $seen[$id] = $true
            $patched = if ($script:GsdModelTemplates.ContainsKey($id)) { ' [patched]' } else { '' }
            Write-Host ("    {0,-35} {1}{2}" -f $id, $name, $patched) -ForegroundColor Gray
        }
    }
    Write-Host ''
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

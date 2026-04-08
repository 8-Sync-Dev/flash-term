# ─────────────────────────────────────────────────────────────────────────────
# 8sync opencode — OpenCode config setup + portable bundle flows
# ─────────────────────────────────────────────────────────────────────────────

function Resolve-OpencodeBundlePath {
    param([string]$BundleDir = 'oc-bundle')

    if ([string]::IsNullOrWhiteSpace($BundleDir)) {
        $BundleDir = 'oc-bundle'
    }

    if ([System.IO.Path]::IsPathRooted($BundleDir)) {
        return $BundleDir
    }

    $candidates = @(
        Join-Path $PWD.Path $BundleDir,
        Join-Path $HOME '.config\wezterm\oc-bundle',
        Join-Path $HOME $BundleDir
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return Join-Path $PWD.Path $BundleDir
}

function Convert-ToRelativePath {
    param(
        [Parameter(Mandatory)] [string]$BasePath,
        [Parameter(Mandatory)] [string]$FullPath
    )

    $baseWithSlash = if ($BasePath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) { $BasePath } else { $BasePath + [System.IO.Path]::DirectorySeparatorChar }
    if ($FullPath.StartsWith($baseWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($baseWithSlash.Length)
    }

    return $FullPath
}

function Test-OpencodeExportExcluded {
    param([Parameter(Mandatory)] [string]$RelativePath)

    $normalized = $RelativePath -replace '/', '\\'

    if ($normalized -match '(^|\\)(lib|node_modules)(\\|$)') {
        return $true
    }

    $ext = [System.IO.Path]::GetExtension($normalized)
    return ($ext -ieq '.ps1' -or $ext -ieq '.py')
}

function Ensure-OpencodeObjectProperty {
    param(
        [Parameter(Mandatory)] [object]$Parent,
        [Parameter(Mandatory)] [string]$Name
    )

    if (-not $Parent.PSObject.Properties[$Name]) {
        $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{})
    }

    return $Parent.$Name
}

function Set-OpencodeProperty {
    param(
        [Parameter(Mandatory)] [object]$Parent,
        [Parameter(Mandatory)] [string]$Name,
        [AllowNull()] $Value
    )

    if ($Parent.PSObject.Properties[$Name]) {
        $Parent.PSObject.Properties.Remove($Name)
    }
    $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Resolve-OpencodeConfigPath {
    return Join-Path $HOME '.config\opencode\opencode.json'
}

function Resolve-OpencodeBaseConfigPath {
    $targetPath = Resolve-OpencodeConfigPath
    if (Test-Path $targetPath) {
        return $targetPath
    }

    $bundlePath = Join-Path (Resolve-OpencodeBundlePath -BundleDir 'oc-bundle') 'opencode.json'
    if (Test-Path $bundlePath) {
        return $bundlePath
    }

    return $null
}

function Read-OpencodeBaseConfig {
    $basePath = Resolve-OpencodeBaseConfigPath
    if (-not $basePath) {
        Write-Host '  [error] Could not find a base OpenCode config. Expected ~/.config/opencode/opencode.json or oc-bundle/opencode.json' -ForegroundColor Red
        return $null
    }

    try {
        $raw = Get-Content $basePath -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json
        return [pscustomobject]@{
            Path = $basePath
            Data = $json
        }
    } catch {
        Write-Host ("  [error] Failed to read base config: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Write-OpencodeConfig {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$DryRun
    )

    $json = $Config | ConvertTo-Json -Depth 30
    if ($DryRun) {
        Write-Host ''
        Write-Host '  [dry-run] Would write:' -ForegroundColor Yellow
        Write-Host ("  {0}" -f $Path) -ForegroundColor DarkGray
        Write-Host '  [dry-run] Preview suppressed to avoid echoing provider credentials and MCP headers.' -ForegroundColor DarkYellow
        Write-Host ''
        return $true
    }

    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) {
        $null = New-Item -Path $dir -ItemType Directory -Force
    }

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
        return $true
    } catch {
        Write-Host ("  [error] Failed to write config: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Resolve-OpencodeProjectConfigPath {
    return Join-Path $PWD.Path '.planning\config.json'
}

function Read-OpencodeProjectConfig {
    $path = Resolve-OpencodeProjectConfigPath
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{
            Path = $path
            Data = [pscustomobject]@{}
        }
    }

    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json
        return [pscustomobject]@{
            Path = $path
            Data = $json
        }
    } catch {
        Write-Host ("  [error] Failed to read project config: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Write-OpencodeProjectConfig {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$DryRun
    )

    $json = $Config | ConvertTo-Json -Depth 20
    if ($DryRun) {
        Write-Host ''
        Write-Host '  [dry-run] Would write:' -ForegroundColor Yellow
        Write-Host ("  {0}" -f $Path) -ForegroundColor DarkGray
        $json -split "`n" | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor DarkGray }
        Write-Host ''
        return $true
    }

    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) {
        $null = New-Item -Path $dir -ItemType Directory -Force
    }

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
        return $true
    } catch {
        Write-Host ("  [error] Failed to write project config: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Resolve-OpencodeVariantForModel {
    param([string]$Model)

    if ([string]::IsNullOrWhiteSpace($Model)) {
        return ''
    }

    if ($Model -like 'openai/*') {
        return 'low'
    }

    if ($Model -like 'openrouter/google/*') {
        return 'low'
    }

    return ''
}

function Get-OpencodePresetMap {
    return @{
        'claude' = [pscustomobject]@{
            Plan  = 'anthropic/claude-opus-4-6'
            Build = 'anthropic/claude-sonnet-4-6'
            Small = 'anthropic/claude-haiku-4-5'
        }
        'codex' = [pscustomobject]@{
            Plan  = 'openai/gpt-5.4'
            Build = 'openai/gpt-5.3-codex'
            Small = 'openai/gpt-5.1-codex-mini'
        }
        'gemini' = [pscustomobject]@{
            Plan  = 'openrouter/google/gemini-3.1-pro-preview'
            Build = 'openrouter/google/gemini-3.1-pro-preview'
            Small = 'openrouter/google/gemini-2.5-flash'
        }
        'glm' = [pscustomobject]@{
            Plan  = 'zai-coding-plan/glm-5.1'
            Build = 'zai-coding-plan/glm-5.1'
            Small = 'zai-coding-plan/glm-4.7-flashx'
        }
        'groq' = [pscustomobject]@{
            Plan  = 'groq/moonshotai/kimi-k2-instruct-0905'
            Build = 'groq/moonshotai/kimi-k2-instruct-0905'
            Small = 'groq/qwen/qwen3-32b'
        }
        'gguf' = [pscustomobject]@{
            Plan  = ''
            Build = ''
            Small = ''
        }
    }
}

function Resolve-OpencodeModelStack {
    param([string]$ModelArg)

    if ([string]::IsNullOrWhiteSpace($ModelArg)) {
        return $null
    }

    $aliases = @{
        'claude' = 'claude'; 'anthropic' = 'claude'
        'codex' = 'codex'; 'openai' = 'codex'
        'gemini' = 'gemini'; 'google' = 'gemini'
        'glm' = 'glm'; 'zai' = 'glm'
        'groq' = 'groq'
        'gguf' = 'gguf'
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($token in ($ModelArg -split '\+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })) {
        if (-not $aliases.ContainsKey($token)) {
            Write-Host ("  [error] Unknown OpenCode model brand '{0}'. Accepted: claude codex gemini glm groq gguf" -f $token) -ForegroundColor Red
            return $null
        }
        $id = $aliases[$token]
        if ($seen.Add($id)) {
            $result.Add($id)
        }
    }

    return $result.ToArray()
}

function Resolve-OpencodePlanPreset {
    param([string]$Plan)

    if ([string]::IsNullOrWhiteSpace($Plan)) {
        return $null
    }

    switch ($Plan.Trim().ToLowerInvariant()) {
        'claude-max' {
            return [pscustomobject]@{
                PlanName = 'claude-max'
                Source = 'plan'
                Name = 'claude-max'
                Plan  = 'anthropic/claude-opus-4-6'
                Build = 'anthropic/claude-sonnet-4-6'
                Small = 'anthropic/claude-haiku-4-5'
                PlanVariant = (Resolve-OpencodeVariantForModel -Model 'anthropic/claude-opus-4-6')
                BuildVariant = (Resolve-OpencodeVariantForModel -Model 'anthropic/claude-sonnet-4-6')
                SmallVariant = (Resolve-OpencodeVariantForModel -Model 'anthropic/claude-haiku-4-5')
                EnabledProviders = @('anthropic')
                Notes = @('/connect -> Anthropic')
            }
        }
        'codex-max' {
            return [pscustomobject]@{
                PlanName = 'codex-max'
                Source = 'plan'
                Name = 'codex-max'
                Plan  = 'openai/gpt-5.4'
                Build = 'openai/gpt-5.3-codex'
                Small = 'openai/gpt-5.1-codex-mini'
                PlanVariant = (Resolve-OpencodeVariantForModel -Model 'openai/gpt-5.4')
                BuildVariant = (Resolve-OpencodeVariantForModel -Model 'openai/gpt-5.3-codex')
                SmallVariant = (Resolve-OpencodeVariantForModel -Model 'openai/gpt-5.1-codex-mini')
                EnabledProviders = @('openai')
                Notes = @('/connect -> OpenAI')
            }
        }
        'gemini-max' {
            return [pscustomobject]@{
                PlanName = 'gemini-max'
                Source = 'plan'
                Name = 'gemini-max'
                Plan  = 'openrouter/google/gemini-3.1-pro-preview'
                Build = 'openrouter/google/gemini-3.1-pro-preview'
                Small = 'openrouter/google/gemini-2.5-flash'
                PlanVariant = (Resolve-OpencodeVariantForModel -Model 'openrouter/google/gemini-3.1-pro-preview')
                BuildVariant = (Resolve-OpencodeVariantForModel -Model 'openrouter/google/gemini-3.1-pro-preview')
                SmallVariant = (Resolve-OpencodeVariantForModel -Model 'openrouter/google/gemini-2.5-flash')
                EnabledProviders = @('openrouter')
                Notes = @('Requires OPENROUTER_API_KEY for OpenRouter Gemini models')
            }
        }
        'glm-max' {
            return [pscustomobject]@{
                PlanName = 'glm-max'
                Source = 'plan'
                Name = 'glm-max'
                Plan  = 'zai-coding-plan/glm-5.1'
                Build = 'zai-coding-plan/glm-5.1'
                Small = 'zai-coding-plan/glm-4.7-flashx'
                PlanVariant = (Resolve-OpencodeVariantForModel -Model 'zai-coding-plan/glm-5.1')
                BuildVariant = (Resolve-OpencodeVariantForModel -Model 'zai-coding-plan/glm-5.1')
                SmallVariant = (Resolve-OpencodeVariantForModel -Model 'zai-coding-plan/glm-4.7-flashx')
                EnabledProviders = @('zai-coding-plan')
                Notes = @('/connect -> Z.AI Coding Plan')
            }
        }
        'claude-codex-gemini' {
            return [pscustomobject]@{
                PlanName = 'claude-codex-gemini'
                Source = 'plan'
                Name = 'claude-codex-gemini'
                Plan  = 'anthropic/claude-opus-4-6'
                Build = 'openai/gpt-5.3-codex'
                Small = 'openrouter/google/gemini-2.5-flash'
                PlanVariant = (Resolve-OpencodeVariantForModel -Model 'anthropic/claude-opus-4-6')
                BuildVariant = (Resolve-OpencodeVariantForModel -Model 'openai/gpt-5.3-codex')
                SmallVariant = (Resolve-OpencodeVariantForModel -Model 'openrouter/google/gemini-2.5-flash')
                EnabledProviders = @('anthropic', 'openai', 'openrouter')
                Notes = @('/connect -> Anthropic', '/connect -> OpenAI', 'OPENROUTER_API_KEY for Gemini via OpenRouter')
            }
        }
        default {
            Write-Host ''
            Write-Host ("  [error] Unknown OpenCode plan '{0}'." -f $Plan) -ForegroundColor Red
            Write-Host '  Valid: claude-max | codex-max | gemini-max | glm-max | claude-codex-gemini' -ForegroundColor DarkGray
            Write-Host ''
            return $null
        }
    }
}

function Resolve-OpencodeGgufModel {
    try {
        $server = Probe-GgufServer
        if (-not $server -or -not $server.Models -or $server.Models.Count -eq 0) {
            return $null
        }

        $modelId = if ($server.Models[0].id) { $server.Models[0].id } else { [string]$server.Models[0] }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($modelId) -replace '[^a-zA-Z0-9\-]', '-'
        return [pscustomobject]@{
            ProviderId = "gguf-local-$stem"
            ModelId = $modelId
            FullModel = "gguf-local-$stem/$modelId"
            BaseUrl = $server.BaseUrl
        }
    } catch {
        return $null
    }
}

function Build-OpencodeSetupSpecFromBrands {
    param([string[]]$Brands)

    if (-not $Brands -or $Brands.Count -eq 0) {
        return $null
    }

    $presetMap = Get-OpencodePresetMap
    $brandList = @($Brands)
    $ggufInfo = $null
    if ($brandList -contains 'gguf') {
        $ggufInfo = Resolve-OpencodeGgufModel
        if (-not $ggufInfo) {
            Write-Host '  [warn] GGUF requested but no running llama-server was detected. Omitting gguf.' -ForegroundColor DarkYellow
            $brandList = @($brandList | Where-Object { $_ -ne 'gguf' })
        }
    }

    if (-not $brandList -or $brandList.Count -eq 0) {
        Write-Host '  [error] No usable OpenCode providers remained after validation.' -ForegroundColor Red
        return $null
    }

    $planPriority = @('claude', 'gemini', 'codex', 'glm', 'groq', 'gguf')
    $buildPriority = @('codex', 'glm', 'claude', 'gemini', 'groq', 'gguf')
    $smallPriority = @('gguf', 'glm', 'groq', 'codex', 'claude', 'gemini')

    function Pick-Brand {
        param([string[]]$Priority, [string[]]$Available)
        foreach ($candidate in $Priority) {
            if ($Available -contains $candidate) {
                return $candidate
            }
        }
        return $Available[0]
    }

    $planBrand = Pick-Brand -Priority $planPriority -Available $brandList
    $buildBrand = Pick-Brand -Priority $buildPriority -Available $brandList
    $smallBrand = Pick-Brand -Priority $smallPriority -Available $brandList

    $planModel = if ($planBrand -eq 'gguf') { $ggufInfo.FullModel } else { $presetMap[$planBrand].Plan }
    $buildModel = if ($buildBrand -eq 'gguf') { $ggufInfo.FullModel } else { $presetMap[$buildBrand].Build }
    $smallModel = if ($smallBrand -eq 'gguf') { $ggufInfo.FullModel } else { $presetMap[$smallBrand].Small }

    $providers = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($model in @($planModel, $buildModel, $smallModel)) {
        if ($model -and ($model -match '^([^/]+)/')) {
            $null = $providers.Add($matches[1])
        }
    }

    return [pscustomobject]@{
        Source = 'model'
        Name = ($Brands -join '+')
        Plan = $planModel
        Build = $buildModel
        Small = $smallModel
        PlanVariant = (Resolve-OpencodeVariantForModel -Model $planModel)
        BuildVariant = (Resolve-OpencodeVariantForModel -Model $buildModel)
        SmallVariant = (Resolve-OpencodeVariantForModel -Model $smallModel)
        EnabledProviders = @($providers)
        Gguf = $ggufInfo
        Notes = @('Default agent variant bias: low where the selected provider supports it.')
    }
}

function Build-OpencodeProjectOverrides {
    param([Parameter(Mandatory)] [object]$Spec)

    return [ordered]@{
        'gsd-planner' = $Spec.Plan
        'gsd-executor' = $Spec.Build
        'gsd-phase-researcher' = $Spec.Small
        'gsd-verifier' = $Spec.Plan
    }
}

function Apply-OpencodeProjectSetupSpec {
    param(
        [Parameter(Mandatory)] [object]$Spec,
        [switch]$DryRun
    )

    $project = Read-OpencodeProjectConfig
    if (-not $project) {
        return
    }

    $config = $project.Data
    $targetPath = $project.Path
    $overrides = Build-OpencodeProjectOverrides -Spec $Spec

    $modelOverrides = Ensure-OpencodeObjectProperty -Parent $config -Name 'model_overrides'
    foreach ($entry in $overrides.GetEnumerator()) {
        Set-OpencodeProperty -Parent $modelOverrides -Name $entry.Key -Value $entry.Value
    }

    Write-Host ''
    Write-Host ("  [opencode] Project setup  {0}={1}" -f $Spec.Source, $Spec.Name) -ForegroundColor Cyan
    Write-Host ("  dest      : {0}" -f $targetPath) -ForegroundColor DarkGray
    foreach ($entry in $overrides.GetEnumerator()) {
        Write-Host ("  {0,-18} {1}" -f ($entry.Key + ':'), $entry.Value) -ForegroundColor DarkGray
    }
    Write-Host ''

    $ok = Write-OpencodeProjectConfig -Config $config -Path $targetPath -DryRun:$DryRun
    if ($ok -and -not $DryRun) {
        Write-Host ("  [ok] {0}" -f $targetPath) -ForegroundColor Green
        Write-Host '  Verify: inspect .planning/config.json and restart the project session if needed.' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Apply-OpencodeSetupSpec {
    param(
        [Parameter(Mandatory)] [object]$Spec,
        [switch]$DryRun
    )

    $base = Read-OpencodeBaseConfig
    if (-not $base) {
        return
    }

    $config = $base.Data
    $targetPath = Resolve-OpencodeConfigPath

    Set-OpencodeProperty -Parent $config -Name '$schema' -Value 'https://opencode.ai/config.json'
    Set-OpencodeProperty -Parent $config -Name 'model' -Value $Spec.Build
    Set-OpencodeProperty -Parent $config -Name 'small_model' -Value $Spec.Small
    Set-OpencodeProperty -Parent $config -Name 'default_agent' -Value 'build'
    Set-OpencodeProperty -Parent $config -Name 'enabled_providers' -Value $Spec.EnabledProviders

    $agent = Ensure-OpencodeObjectProperty -Parent $config -Name 'agent'

    $buildAgent = Ensure-OpencodeObjectProperty -Parent $agent -Name 'build'
    Set-OpencodeProperty -Parent $buildAgent -Name 'model' -Value $Spec.Build
    if ($Spec.PSObject.Properties['BuildVariant'] -and -not [string]::IsNullOrWhiteSpace($Spec.BuildVariant)) {
        Set-OpencodeProperty -Parent $buildAgent -Name 'variant' -Value $Spec.BuildVariant
    } elseif ($buildAgent.PSObject.Properties['variant']) {
        $buildAgent.PSObject.Properties.Remove('variant')
    }

    $planAgent = Ensure-OpencodeObjectProperty -Parent $agent -Name 'plan'
    Set-OpencodeProperty -Parent $planAgent -Name 'model' -Value $Spec.Plan
    if ($Spec.PSObject.Properties['PlanVariant'] -and -not [string]::IsNullOrWhiteSpace($Spec.PlanVariant)) {
        Set-OpencodeProperty -Parent $planAgent -Name 'variant' -Value $Spec.PlanVariant
    } elseif ($planAgent.PSObject.Properties['variant']) {
        $planAgent.PSObject.Properties.Remove('variant')
    }

    $generalAgent = Ensure-OpencodeObjectProperty -Parent $agent -Name 'general'
    Set-OpencodeProperty -Parent $generalAgent -Name 'model' -Value $Spec.Build
    if ($Spec.PSObject.Properties['BuildVariant'] -and -not [string]::IsNullOrWhiteSpace($Spec.BuildVariant)) {
        Set-OpencodeProperty -Parent $generalAgent -Name 'variant' -Value $Spec.BuildVariant
    } elseif ($generalAgent.PSObject.Properties['variant']) {
        $generalAgent.PSObject.Properties.Remove('variant')
    }

    $exploreAgent = Ensure-OpencodeObjectProperty -Parent $agent -Name 'explore'
    Set-OpencodeProperty -Parent $exploreAgent -Name 'model' -Value $Spec.Small
    if ($Spec.PSObject.Properties['SmallVariant'] -and -not [string]::IsNullOrWhiteSpace($Spec.SmallVariant)) {
        Set-OpencodeProperty -Parent $exploreAgent -Name 'variant' -Value $Spec.SmallVariant
    } elseif ($exploreAgent.PSObject.Properties['variant']) {
        $exploreAgent.PSObject.Properties.Remove('variant')
    }

    if ($Spec.Gguf) {
        $provider = Ensure-OpencodeObjectProperty -Parent $config -Name 'provider'
        $ggufProvider = [pscustomobject]@{
            options = [pscustomobject]@{
                apiKey = 'local'
                baseURL = $Spec.Gguf.BaseUrl
            }
            models = [pscustomobject]@{
                $($Spec.Gguf.ModelId) = [pscustomobject]@{
                    name = ([System.IO.Path]::GetFileNameWithoutExtension($Spec.Gguf.ModelId) + ' (local GGUF)')
                    attachment = $false
                    reasoning = $false
                }
            }
        }
        Set-OpencodeProperty -Parent $provider -Name $Spec.Gguf.ProviderId -Value $ggufProvider
    }

    Write-Host ''
    Write-Host ("  [opencode] Setup  {0}={1}" -f $Spec.Source, $Spec.Name) -ForegroundColor Cyan
    Write-Host ("  base    : {0}" -f $base.Path) -ForegroundColor DarkGray
    Write-Host ("  dest    : {0}" -f $targetPath) -ForegroundColor DarkGray
    Write-Host ("  plan    : {0}" -f $Spec.Plan) -ForegroundColor DarkGray
    if ($Spec.PSObject.Properties['PlanVariant'] -and $Spec.PlanVariant) { Write-Host ("  plan-v  : {0}" -f $Spec.PlanVariant) -ForegroundColor DarkGray }
    Write-Host ("  build   : {0}" -f $Spec.Build) -ForegroundColor DarkGray
    if ($Spec.PSObject.Properties['BuildVariant'] -and $Spec.BuildVariant) { Write-Host ("  build-v : {0}" -f $Spec.BuildVariant) -ForegroundColor DarkGray }
    Write-Host ("  small   : {0}" -f $Spec.Small) -ForegroundColor DarkGray
    if ($Spec.PSObject.Properties['SmallVariant'] -and $Spec.SmallVariant) { Write-Host ("  small-v : {0}" -f $Spec.SmallVariant) -ForegroundColor DarkGray }
    Write-Host ("  enabled : {0}" -f ($Spec.EnabledProviders -join ', ')) -ForegroundColor DarkGray
    if ($Spec.Notes -and $Spec.Notes.Count -gt 0) {
        foreach ($note in $Spec.Notes) {
            Write-Host ("  note    : {0}" -f $note) -ForegroundColor DarkYellow
        }
    }
    Write-Host ''

    $ok = Write-OpencodeConfig -Config $config -Path $targetPath -DryRun:$DryRun
    if ($ok -and -not $DryRun) {
        Write-Host ("  [ok] {0}" -f $targetPath) -ForegroundColor Green
        Write-Host '  Verify: opencode debug config   opencode models' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Read-OpencodeWizardChoice {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string[]]$Options,
        [int]$Default = 0
    )

    Write-Host ''
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { '*' } else { ' ' }
        Write-Host ("   [{0}] {1} {2}" -f ($i + 1), $marker, $Options[$i]) -ForegroundColor DarkGray
    }

    while ($true) {
        $raw = Read-Host ("  Pick 1-{0} (Enter={1})" -f $Options.Count, ($Default + 1))
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $Default
        }
        $value = 0
        if ([int]::TryParse($raw, [ref]$value) -and $value -ge 1 -and $value -le $Options.Count) {
            return ($value - 1)
        }
        Write-Host '  Invalid choice. Try again.' -ForegroundColor DarkYellow
    }
}

function Read-OpencodeWizardMultiSelect {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string[]]$Options,
        [int[]]$DefaultIndices = @()
    )

    Write-Host ''
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $selected = if ($DefaultIndices -contains $i) { 'x' } else { ' ' }
        Write-Host ("   [{0}] [{1}] {2}" -f ($i + 1), $selected, $Options[$i]) -ForegroundColor DarkGray
    }
    Write-Host '  Enter comma-separated numbers. Empty input keeps defaults.' -ForegroundColor DarkGray

    while ($true) {
        $raw = Read-Host '  Select'
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @($DefaultIndices | Sort-Object -Unique)
        }

        $picked = [System.Collections.Generic.List[int]]::new()
        $ok = $true
        foreach ($part in ($raw -split '[, ]+' | Where-Object { $_ -ne '' })) {
            $value = 0
            if (-not [int]::TryParse($part, [ref]$value) -or $value -lt 1 -or $value -gt $Options.Count) {
                $ok = $false
                break
            }
            $picked.Add($value - 1)
        }

        if ($ok -and $picked.Count -gt 0) {
            return @($picked | Sort-Object -Unique)
        }

        Write-Host '  Invalid selection. Try again.' -ForegroundColor DarkYellow
    }
}

function Invoke-OpencodeSetupCli {
    param([switch]$DryRun)

    Write-Host ''
    Write-HintSection 'OpenCode setup wizard'
    Write-Host '  Goal: build ~/.config/opencode/opencode.json with low-bias defaults where supported.' -ForegroundColor DarkGray

    $modeIndex = Read-OpencodeWizardChoice -Title 'Setup mode' -Options @(
        'Preset plan (fast path)',
        'Custom provider mix'
    ) -Default 0

    if ($modeIndex -eq 0) {
        $plans = @('claude-max', 'codex-max', 'gemini-max', 'glm-max', 'claude-codex-gemini')
        $planIndex = Read-OpencodeWizardChoice -Title 'Preset' -Options $plans -Default 0
        $spec = Resolve-OpencodePlanPreset -Plan $plans[$planIndex]
        if ($spec) {
            Apply-OpencodeSetupSpec -Spec $spec -DryRun:$DryRun
        }
        return
    }

    $brands = @('claude', 'codex', 'gemini', 'glm', 'groq', 'gguf')
    $defaultIndices = @(0, 1)
    $selectedIndices = Read-OpencodeWizardMultiSelect -Title 'Providers to include' -Options @(
        'claude  -> Anthropic planning / writing',
        'codex   -> OpenAI coding models',
        'gemini  -> Gemini via OpenRouter',
        'glm     -> Z.AI Coding Plan',
        'groq    -> Groq fast fallback',
        'gguf    -> local llama.cpp server'
    ) -DefaultIndices $defaultIndices

    $selectedBrands = foreach ($idx in $selectedIndices) { $brands[$idx] }
    $spec = Build-OpencodeSetupSpecFromBrands -Brands $selectedBrands
    if ($spec) {
        Apply-OpencodeSetupSpec -Spec $spec -DryRun:$DryRun
    }
}

function Invoke-OpencodeSetupProject {
    param([string[]]$Rest)

    $dryRun = $Rest -contains '--dry-run'
    $modelArg = ''
    $planArg = ''

    for ($i = 0; $i -lt $Rest.Count; $i++) {
        $token = $Rest[$i]
        switch -Regex ($token) {
            '^--model=(.+)$' { $modelArg = $matches[1]; continue }
            '^--plan=(.+)$'  { $planArg = $matches[1]; continue }
            '^--dry-run$'    { continue }
            '^--model$' {
                if ($i + 1 -lt $Rest.Count) { $modelArg = $Rest[++$i] }
                continue
            }
            '^--plan$' {
                if ($i + 1 -lt $Rest.Count) { $planArg = $Rest[++$i] }
                continue
            }
        }
    }

    if ($modelArg -and $planArg) {
        Write-Host ''
        Write-Host '  [error] Use either --model or --plan for project setup, not both.' -ForegroundColor Red
        Write-Host ''
        return
    }

    if (-not $modelArg -and -not $planArg) {
        Write-Host ''
        Write-HintSection 'OpenCode project setup -- generate .planning/config.json'
        Write-HintRow '8sync opencode setup project --model=claude+codex' 'Write model_overrides for planner/executor/researcher/verifier'
        Write-HintRow '8sync opencode setup project --plan=claude-max'    'Use a named stack preset for project-level overrides'
        Write-HintRow '8sync opencode setup project --dry-run --plan=claude-codex-gemini' 'Preview .planning/config.json changes'
        Write-Host ''
        return
    }

    $spec = $null
    if ($planArg) {
        $spec = Resolve-OpencodePlanPreset -Plan $planArg
    } else {
        $brands = Resolve-OpencodeModelStack -ModelArg $modelArg
        if ($brands) {
            $spec = Build-OpencodeSetupSpecFromBrands -Brands $brands
        }
    }

    if ($spec) {
        Apply-OpencodeProjectSetupSpec -Spec $spec -DryRun:$dryRun
    }
}

function Invoke-OpencodeSetup {
    param([string[]]$Rest)

    if ($Rest.Count -gt 0 -and $Rest[0].ToLowerInvariant() -eq 'project') {
        Invoke-OpencodeSetupProject -Rest ($Rest | Select-Object -Skip 1)
        return
    }

    $dryRun = $Rest -contains '--dry-run'
    $modelArg = ''
    $planArg = ''
    $cliMode = $false

    for ($i = 0; $i -lt $Rest.Count; $i++) {
        $token = $Rest[$i]
        switch -Regex ($token) {
            '^cli$'          { $cliMode = $true; continue }
            '^--cli$'        { $cliMode = $true; continue }
            '^--model=(.+)$' { $modelArg = $matches[1]; continue }
            '^--plan=(.+)$'  { $planArg = $matches[1]; continue }
            '^--dry-run$'    { continue }
            '^--model$' {
                if ($i + 1 -lt $Rest.Count) { $modelArg = $Rest[++$i] }
                continue
            }
            '^--plan$' {
                if ($i + 1 -lt $Rest.Count) { $planArg = $Rest[++$i] }
                continue
            }
        }
    }

    if ($cliMode) {
        Invoke-OpencodeSetupCli -DryRun:$dryRun
        return
    }

    if ($modelArg -and $planArg) {
        Write-Host ''
        Write-Host '  [error] Use either --model or --plan, not both.' -ForegroundColor Red
        Write-Host ''
        return
    }

    if (-not $modelArg -and -not $planArg) {
        Write-Host ''
        Write-HintSection 'OpenCode setup -- generate ~/.config/opencode/opencode.json'
        Write-HintRow '8sync opencode setup project --plan=claude-max'    'Write .planning/config.json model_overrides for this repo'
        Write-HintRow '8sync opencode setup cli'                  'Interactive wizard: choose preset or provider mix step by step'
        Write-HintRow '8sync opencode setup --model=claude+codex' 'Use Claude for plan, Codex for build, set small_model automatically'
        Write-HintRow '8sync opencode setup --plan=claude-max'    'Claude-only preset: Opus plan, Sonnet build, Haiku small_model'
        Write-HintRow '8sync opencode setup --plan=codex-max'     'OpenAI-only preset: GPT-5.4 plan, GPT-5.3 Codex build'
        Write-HintRow '8sync opencode setup --plan=gemini-max'    'Gemini via OpenRouter: Gemini 3.1 Pro + 2.5 Flash small_model'
        Write-HintRow '8sync opencode setup --plan=glm-max'       'Z.AI Coding Plan preset'
        Write-HintRow '8sync opencode setup --dry-run --model=glm' 'Preview generated config without writing'
        Write-Host ''
        return
    }

    if ($planArg) {
        $spec = Resolve-OpencodePlanPreset -Plan $planArg
        if ($spec) {
            Apply-OpencodeSetupSpec -Spec $spec -DryRun:$dryRun
        }
        return
    }

    $brands = Resolve-OpencodeModelStack -ModelArg $modelArg
    if (-not $brands) {
        return
    }

    $spec = Build-OpencodeSetupSpecFromBrands -Brands $brands
    if ($spec) {
        Apply-OpencodeSetupSpec -Spec $spec -DryRun:$dryRun
    }
}

function Show-OpencodeHelp {
    Write-Host ''
    Write-HintSection 'OPENCODE -- OpenCode config setup + portable bundle flows'
    Write-HintRow '8sync opencode setup project --plan=claude-max'    'Write .planning/config.json model_overrides for this repo'
    Write-HintRow '8sync opencode setup cli'                   'Interactive wizard: choose preset or provider mix step by step'
    Write-HintRow '8sync opencode setup --model=claude+codex' 'Generate ~/.config/opencode/opencode.json using OpenCode model/provider schema'
    Write-HintRow '8sync opencode setup --plan=claude-max'    'Apply a named OpenCode preset (claude-max, codex-max, gemini-max, glm-max)'
    Write-HintRow '8sync opencode setup --dry-run --model=glm' 'Preview generated config without writing'
    Write-HintRow '8sync opencode export [folder]'            'Export ~/.config/opencode to bundle folder (default: oc-bundle)'
    Write-HintRow '8sync opencode apply [folder]'             'Copy bundle -> ~/.config/opencode and run npm i'
    Write-HintRow '8sync opencode reinstall [folder]'         'Force reinstall (wipe ~/.config/opencode, then apply + npm i)'
    Write-HintRow '8sync opencode status'                     'Show source/bundle/npm readiness'
    Write-Host ''
    Write-Host '  -- GGUF / local model -----------------------------------------------' -ForegroundColor DarkGray
    Write-HintRow '8sync opencode connect gguf'               'Add running llama-server as provider in opencode.json'
    Write-HintRow '8sync opencode connect gguf --port N'      'Probe specific port (default: 8080,8081,8082,1234,11434)'
    Write-HintRow '8sync opencode connect gguf --name id'     'Override provider id (default: gguf-local-<model>)'
    Write-HintRow '8sync opencode connect gguf --dry-run'     'Preview change without writing'
    Write-Host ''
    Write-Host '  Target machine setup:' -ForegroundColor DarkGray
    Write-Host '    1) Copy/extract bundle folder (default: oc-bundle) into machine' -ForegroundColor DarkGray
    Write-Host '    2) Run: 8sync opencode reinstall [folder]' -ForegroundColor DarkGray
    Write-Host '    3) Or generate local config directly: 8sync opencode setup --plan=claude-max' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Note: Do NOT push bundle to public repo with secrets in opencode.json.' -ForegroundColor DarkYellow
    Write-Host ''
}

function Invoke-OpencodeApply {
    param(
        [string]$BundleDir = 'oc-bundle',
        [switch]$DryRun,
        [switch]$Force
    )

    $bundlePath = Resolve-OpencodeBundlePath -BundleDir $BundleDir
    $autoDetected = ($BundleDir -eq 'oc-bundle') -and ($bundlePath -ne (Join-Path $PWD.Path $BundleDir))
    if (-not (Test-Path $bundlePath)) {
        Write-Host ("  [opencode] Bundle folder not found: {0}" -f $bundlePath) -ForegroundColor Red
        Write-Host '  [opencode] Searched: $PWD/oc-bundle, ~/.config/wezterm/oc-bundle, ~/oc-bundle' -ForegroundColor DarkGray
        return
    }

    $targetPath = Join-Path $HOME '.config\opencode'
    $bundleFiles = Get-ChildItem -Path $bundlePath -Recurse -Force -File -ErrorAction SilentlyContinue
    if (-not $bundleFiles -or $bundleFiles.Count -eq 0) {
        Write-Host '  [opencode] Bundle has no files to apply.' -ForegroundColor DarkYellow
        return
    }

    $actions = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($file in $bundleFiles) {
        $rel = Convert-ToRelativePath -BasePath $bundlePath -FullPath $file.FullName
        $dest = Join-Path $targetPath $rel
        $destDir = Split-Path $dest -Parent
        $actions.Add([pscustomobject]@{
            Rel     = $rel
            Src     = $file.FullName
            Dest    = $dest
            DestDir = $destDir
        })
    }

    Write-Host ''
    Write-Host '  [opencode] Apply bundle' -ForegroundColor Cyan
    $bundleLabel = if ($autoDetected) { "$bundlePath  (auto-detected)" } else { $bundlePath }
    Write-Host ("  bundle: {0}" -f $bundleLabel) -ForegroundColor DarkGray
    Write-Host ("  target: {0}" -f $targetPath) -ForegroundColor DarkGray
    Write-Host ''

    if ($DryRun) {
        Write-Host '  [opencode] DRY RUN -- no files written' -ForegroundColor Yellow
        if ($Force) {
            Write-Host '  [dry-run] would wipe target folder before copy (--force)' -ForegroundColor DarkYellow
        }
        foreach ($a in $actions) {
            Write-Host ("  [dry-run] {0}" -f $a.Rel) -ForegroundColor DarkYellow
        }
        Write-Host ("  Total files: {0}" -f $actions.Count) -ForegroundColor DarkGray
        Write-Host '  [dry-run] would run: npm i (inside ~/.config/opencode)' -ForegroundColor DarkYellow
        Write-Host '  [dry-run] then: restart OpenCode to auto-install plugins' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if ($Force -and (Test-Path $targetPath)) {
        try {
            Get-ChildItem -Path $targetPath -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host ("  [error] Failed to clear target folder contents: {0}" -f $_.Exception.Message) -ForegroundColor Red
            return
        }
    }

    if (-not (Test-Path $targetPath)) {
        $null = New-Item -Path $targetPath -ItemType Directory -Force
    }

    $copied = 0
    $errors = 0
    foreach ($a in $actions) {
        try {
            if (-not (Test-Path $a.DestDir)) {
                $null = New-Item -Path $a.DestDir -ItemType Directory -Force
            }
            Copy-Item -Path $a.Src -Destination $a.Dest -Force -ErrorAction Stop
            Write-Host ("  [ok]      {0}" -f $a.Rel) -ForegroundColor Green
            $copied++
        } catch {
            Write-Host ("  [error]   {0} -- {1}" -f $a.Rel, $_.Exception.Message) -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ''
    Write-Host ("  Apply done. copied={0} errors={1}" -f $copied, $errors) -ForegroundColor $(if ($errors -gt 0) { 'DarkYellow' } else { 'Cyan' })
    Write-Host ''

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Host '  npm not found. Install Node/npm then run: cd ~/.config/opencode; npm i' -ForegroundColor DarkYellow
        Write-Host '    scoop install nvm' -ForegroundColor White
        Write-Host '    nvm install <version>' -ForegroundColor White
        Write-Host '    nvm use <version>' -ForegroundColor White
        Write-Host '    npm i' -ForegroundColor White
        Write-Host ''
        return
    }

    try {
        Push-Location $targetPath
        Write-Host '  Running npm i ...' -ForegroundColor Yellow
        npm i
        Write-Host '  npm i completed.' -ForegroundColor Green
    } catch {
        Write-Host ("  [error] npm i failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    } finally {
        Pop-Location
    }

    Write-Host ''
    Write-Host '  [opencode] Setup complete!' -ForegroundColor Cyan
    Write-Host '  Next steps:' -ForegroundColor DarkGray
    Write-Host '    1) Restart OpenCode -- plugins auto-install on startup' -ForegroundColor DarkGray
    Write-Host '    2) Verify model routing: opencode debug config' -ForegroundColor DarkGray
    Write-Host '    3) If needed, generate a fresh runtime config: 8sync opencode setup --model=claude+codex' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-OpencodeExport {
    param(
        [string]$BundleDir = 'oc-bundle',
        [switch]$DryRun
    )

    $source = Join-Path $HOME '.config\opencode'
    if (-not (Test-Path $source)) {
        Write-Host ("  [opencode] Source config not found: {0}" -f $source) -ForegroundColor Red
        return
    }

    $bundlePath = Resolve-OpencodeBundlePath -BundleDir $BundleDir
    $sourcePath = (Resolve-Path $source).Path

    $files = Get-ChildItem -Path $sourcePath -Recurse -Force -File -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) {
        Write-Host '  [opencode] Source has no files to export.' -ForegroundColor DarkYellow
        return
    }

    $actions = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($file in $files) {
        $rel = Convert-ToRelativePath -BasePath $sourcePath -FullPath $file.FullName
        if (Test-OpencodeExportExcluded -RelativePath $rel) {
            continue
        }

        $dest = Join-Path $bundlePath $rel
        $destDir = Split-Path $dest -Parent
        $actions.Add([pscustomobject]@{
            Rel     = $rel
            Src     = $file.FullName
            Dest    = $dest
            DestDir = $destDir
        })
    }

    Write-Host ''
    Write-Host '  [opencode] Export bundle' -ForegroundColor Cyan
    Write-Host ("  source: {0}" -f $sourcePath) -ForegroundColor DarkGray
    Write-Host ("  bundle: {0}" -f $bundlePath) -ForegroundColor DarkGray
    Write-Host ''

    if ($actions.Count -eq 0) {
        Write-Host '  [opencode] Nothing to export after exclusions (lib, node_modules, *.ps1, *.py).' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if ($DryRun) {
        Write-Host '  [opencode] DRY RUN -- no files written' -ForegroundColor Yellow
        foreach ($a in $actions) {
            Write-Host ("  [dry-run] {0}" -f $a.Rel) -ForegroundColor DarkYellow
        }
        Write-Host ("  Total files: {0}" -f $actions.Count) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if (Test-Path $bundlePath) {
        try {
            Remove-Item -Path $bundlePath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host ("  [error] Failed to clear bundle folder: {0}" -f $_.Exception.Message) -ForegroundColor Red
            return
        }
    }
    $null = New-Item -Path $bundlePath -ItemType Directory -Force

    $copied = 0
    $errors = 0
    foreach ($a in $actions) {
        try {
            if (-not (Test-Path $a.DestDir)) {
                $null = New-Item -Path $a.DestDir -ItemType Directory -Force
            }
            Copy-Item -Path $a.Src -Destination $a.Dest -Force -ErrorAction Stop
            Write-Host ("  [ok]      {0}" -f $a.Rel) -ForegroundColor Green
            $copied++
        } catch {
            Write-Host ("  [error]   {0} -- {1}" -f $a.Rel, $_.Exception.Message) -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ''
    Write-Host ("  Export done. copied={0} errors={1}" -f $copied, $errors) -ForegroundColor $(if ($errors -gt 0) { 'DarkYellow' } else { 'Cyan' })
    Write-Host ''
    Write-Host '  Target machine:' -ForegroundColor Yellow
    Write-Host '    1. Copy all files from bundle folder -> ~/.config/opencode' -ForegroundColor White
    Write-Host '    2. cd ~/.config/opencode && npm i' -ForegroundColor White
    Write-Host '    3. If npm missing: scoop install nvm; nvm install <version>; nvm use <version>; npm i' -ForegroundColor White
    Write-Host ''
}

function Invoke-OpencodeStatus {
    $sourcePath = Join-Path $HOME '.config\opencode'
    $bundlePath = Resolve-OpencodeBundlePath -BundleDir 'oc-bundle'

    Write-Host ''
    Write-Host '  [opencode] Export Status' -ForegroundColor Cyan
    Write-Host ''

    $sourceOk = Test-Path $sourcePath
    Write-Host ("  {0,-40} {1}" -f '~/.config/opencode (source):', $(if ($sourceOk) { 'exists' } else { 'MISSING' })) -ForegroundColor $(if ($sourceOk) { 'Green' } else { 'Red' })

    $bundleOk = Test-Path $bundlePath
    Write-Host ("  {0,-40} {1}" -f './oc-bundle (default bundle):', $(if ($bundleOk) { 'exists' } else { 'MISSING' })) -ForegroundColor $(if ($bundleOk) { 'Green' } else { 'DarkYellow' })

    if ($bundleOk) {
        $bundleCount = (Get-ChildItem -Path $bundlePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("  {0,-40} {1}" -f 'bundle files:', $bundleCount) -ForegroundColor DarkGray
    }

    Write-Host ''
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    $node = Get-Command node -ErrorAction SilentlyContinue
    $nvm = Get-Command nvm -ErrorAction SilentlyContinue

    Write-Host ("  {0,-18} {1}" -f 'node:', $(if ($node) { 'found' } else { 'MISSING' })) -ForegroundColor $(if ($node) { 'Green' } else { 'DarkYellow' })
    Write-Host ("  {0,-18} {1}" -f 'npm:', $(if ($npm) { 'found' } else { 'MISSING' })) -ForegroundColor $(if ($npm) { 'Green' } else { 'DarkYellow' })
    Write-Host ("  {0,-18} {1}" -f 'nvm:', $(if ($nvm) { 'found' } else { 'MISSING' })) -ForegroundColor $(if ($nvm) { 'Green' } else { 'DarkYellow' })

    if (-not $npm) {
        Write-Host ''
        Write-Host '  npm missing quick fix:' -ForegroundColor Yellow
        Write-Host '    scoop install nvm' -ForegroundColor White
        Write-Host '    nvm install <version>' -ForegroundColor White
        Write-Host '    nvm use <version>' -ForegroundColor White
        Write-Host '    npm i' -ForegroundColor White
    }

    Write-Host ''
}

function Invoke-OpencodeConnectGguf {
    param([string[]]$Rest)

    $dryRun  = $Rest -contains '--dry-run'
    $portArg = ''
    $nameArg = ''
    for ($i = 0; $i -lt $Rest.Count; $i++) {
        switch ($Rest[$i]) {
            '--port' { $portArg = $Rest[++$i] }
            '--name' { $nameArg = $Rest[++$i] }
        }
    }

    Write-Host ''
    Write-HintSection 'OpenCode -- Connect GGUF server as provider'
    Write-Host ''

    $ocConfigPath = Resolve-OpencodeConfigPath
    if (-not (Test-Path $ocConfigPath)) {
        Write-Host ("  [!!] opencode.json not found: {0}" -f $ocConfigPath) -ForegroundColor Red
        Write-Host '       Run: 8sync opencode apply   or  8sync opencode setup --plan=claude-max  first.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host '  Probing llama-server on localhost...' -ForegroundColor DarkGray
    $ports = if ($portArg) { @([int]$portArg) } else { @(8080, 8081, 8082, 1234, 11434) }
    $found = $null
    foreach ($p in $ports) {
        try {
            $r = Invoke-RestMethod "http://localhost:$p/v1/models" -TimeoutSec 5 -ErrorAction Stop
            $found = [pscustomobject]@{ Port = $p; BaseUrl = "http://localhost:$p/v1"; Models = @($r.data) }
            break
        } catch {}
    }

    if (-not $found) {
        $tried = if ($portArg) { "port $portArg" } else { 'ports 8080, 8081, 8082, 1234, 11434' }
        Write-Host ("  [!!] No llama-server found on {0}." -f $tried) -ForegroundColor Red
        Write-Host '       Start one first: 8sync gguf serve ... --balance' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ("  [OK] Server found on port {0}  ->  {1}" -f $found.Port, $found.BaseUrl) -ForegroundColor Green

    $firstModelId = if ($found.Models -and $found.Models[0].id) { $found.Models[0].id } else { 'gguf-local' }
    $stem       = [System.IO.Path]::GetFileNameWithoutExtension($firstModelId) -replace '[^a-zA-Z0-9\-]', '-'
    $providerId = if ($nameArg) { $nameArg } else { "gguf-local-$stem" }
    $modelId    = $firstModelId

    Write-Host ("  Provider  : {0}" -f $providerId) -ForegroundColor DarkGray
    Write-Host ("  Model id  : {0}" -f $modelId) -ForegroundColor DarkGray
    Write-Host ("  Base URL  : {0}" -f $found.BaseUrl) -ForegroundColor DarkGray
    Write-Host ''

    if ($dryRun) {
        Write-Host '  [dry-run] opencode.json not modified. Remove --dry-run to apply.' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    try {
        $raw  = Get-Content $ocConfigPath -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json

        $provider = Ensure-OpencodeObjectProperty -Parent $data -Name 'provider'
        $providerEntry = [pscustomobject]@{
            options = [pscustomobject]@{
                apiKey  = 'local'
                baseURL = $found.BaseUrl
            }
            models  = [pscustomobject]@{
                $modelId = [pscustomobject]@{
                    name       = [System.IO.Path]::GetFileNameWithoutExtension($modelId) + ' (local GGUF)'
                    attachment = $false
                    reasoning  = $false
                }
            }
        }

        Set-OpencodeProperty -Parent $provider -Name $providerId -Value $providerEntry
        $data | ConvertTo-Json -Depth 30 | Set-Content $ocConfigPath -Encoding UTF8
        Write-Host ("  [OK] Written to {0}" -f $ocConfigPath) -ForegroundColor Green
    } catch {
        Write-Host ("  [error] Failed to patch opencode.json: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  Next steps:' -ForegroundColor DarkGray
    Write-Host ("    /model  -> select '{0}/{1}'" -f $providerId, $modelId) -ForegroundColor DarkGray
    Write-Host '    Or set in opencode.json: "model": "<providerId>/<modelId>"' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-OpencodeCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun = $Rest -contains '--dry-run'
    $force = $Rest -contains '--force'

    $sub = 'export'
    $argStart = 0
    if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') {
        $sub = $Rest[0].ToLowerInvariant()
        $argStart = 1
    }

    $bundleDir = 'oc-bundle'
    if ($Rest.Count -gt $argStart) {
        $candidate = $Rest[$argStart]
        if ($candidate -and $candidate -notlike '--*') {
            $bundleDir = $candidate
        }
    }

    switch ($sub) {
        'export'    { Invoke-OpencodeExport -BundleDir $bundleDir -DryRun:$dryRun }
        'apply'     { Invoke-OpencodeApply -BundleDir $bundleDir -DryRun:$dryRun -Force:$force }
        'reinstall' { Invoke-OpencodeApply -BundleDir $bundleDir -DryRun:$dryRun -Force }
        'install'   { Invoke-OpencodeExport -BundleDir $bundleDir -DryRun:$dryRun }
        'setup'     { Invoke-OpencodeSetup -Rest ($Rest | Select-Object -Skip 1) }
        '--dry-run' { Invoke-OpencodeExport -BundleDir 'oc-bundle' -DryRun }
        'status'    { Invoke-OpencodeStatus }
        'connect' {
            $conSub = if ($Rest.Count -gt 1) { $Rest[1].ToLowerInvariant() } else { '' }
            switch ($conSub) {
                'gguf'  { Invoke-OpencodeConnectGguf -Rest ($Rest | Select-Object -Skip 2) }
                default {
                    Write-Host '  Usage: 8sync opencode connect gguf [--port N] [--name <id>] [--dry-run]' -ForegroundColor DarkGray
                    Write-Host '  Adds running llama-server as a provider in ~/.config/opencode/opencode.json' -ForegroundColor DarkGray
                }
            }
        }
        'help'    { Show-OpencodeHelp }
        default   { Show-OpencodeHelp }
    }
}

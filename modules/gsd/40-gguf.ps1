# =============================================================================
# 8sync gsd -- local GGUF provider management
# =============================================================================

function Probe-GgufServer {
    param([string]$Port = '')

    $ports = if ($Port) { @([int]$Port) } else { @(8080, 8081, 8082, 1234, 11434) }
    foreach ($port in $ports) {
        try {
            $response = Invoke-RestMethod "http://localhost:$port/v1/models" -TimeoutSec 3 -ErrorAction Stop
            return [pscustomobject]@{
                Port    = $port
                BaseUrl = "http://localhost:$port/v1"
                Models  = @($response.data)
            }
        } catch {}
    }
    return $null
}

function Invoke-GsdAddGguf {
    param([string[]]$Rest)

    $dryRun = $Rest -contains '--dry-run'
    $portArg = ''
    $nameArg = ''
    $roleArg = ''

    for ($i = 0; $i -lt $Rest.Count; $i++) {
        switch ($Rest[$i]) {
            '--port' { $portArg = $Rest[++$i] }
            '--name' { $nameArg = $Rest[++$i] }
            '--role' { $roleArg = $Rest[++$i] }
        }
    }

    Write-Host ''
    Write-HintSection 'GSD -- Add GGUF server as provider'
    Write-Host ''
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

    $models = $server.Models
    if (-not $models -or $models.Count -eq 0) {
        Write-Host '  [!!] Server returned no models from /v1/models.' -ForegroundColor Red
        return
    }

    Write-Host ("  Models available on server ({0}):" -f $models.Count) -ForegroundColor DarkGray
    foreach ($model in $models) {
        $modelId = if ($model.id) { $model.id } else { $model }
        Write-Host ("    {0}" -f $modelId) -ForegroundColor White
    }
    Write-Host ''

    $firstModelId = if ($models[0].id) { $models[0].id } else { [string]$models[0] }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($firstModelId) -replace '[^a-zA-Z0-9\-]', '-'
    $providerId = if ($nameArg) { $nameArg } else { "gguf-local-$stem" }

    $modelEntries = foreach ($model in $models) {
        $modelId = if ($model.id) { $model.id } else { [string]$model }
        $modelName = if ($model.name) { $model.name } else { [System.IO.Path]::GetFileNameWithoutExtension($modelId) }
        [pscustomobject]@{
            id            = $modelId
            name          = "$modelName (local GGUF)"
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

    $data = Read-GsdModelsJson
    if (-not $data) {
        $data = [pscustomobject]@{ providers = [pscustomobject]@{} }
    }
    if (-not $data.PSObject.Properties['providers']) {
        $data | Add-Member -NotePropertyName 'providers' -NotePropertyValue ([pscustomobject]@{})
    }

    $alreadyExists = $data.providers.PSObject.Properties[$providerId] -ne $null
    Write-Host ("  Provider id : {0}" -f $providerId) -ForegroundColor Cyan
    Write-Host ("  Base URL    : {0}" -f $server.BaseUrl) -ForegroundColor DarkGray
    Write-Host ("  Models      : {0}" -f (($modelEntries | ForEach-Object { $_.id }) -join ', ')) -ForegroundColor DarkGray
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

    Write-Host ("  [OK] Written to {0}" -f (Get-GsdModelsJsonPath)) -ForegroundColor Green
    Write-Host ''
    Write-Host '  Next steps:' -ForegroundColor DarkGray
    Write-Host '    /model  to browse and select the new model in pi/GSD' -ForegroundColor DarkGray
    Write-Host '    8sync gsd status  to verify provider is visible' -ForegroundColor DarkGray
    if ($roleArg) {
        Write-Host ("    --role '{0}' noted -- wire manually in PREFERENCES.md for now" -f $roleArg) -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Invoke-GsdRemoveGguf {
    param([string[]]$Rest)

    $dryRun = $Rest -contains '--dry-run'
    $nameArg = ''
    for ($i = 0; $i -lt $Rest.Count; $i++) {
        if ($Rest[$i] -eq '--name') { $nameArg = $Rest[++$i] }
    }

    $data = Read-GsdModelsJson
    if (-not $data) {
        Write-Warning 'gsd: models.json not found'
        return
    }

    $ggufProviders = $data.providers.PSObject.Properties | Where-Object {
        $_.Name -like 'gguf-local-*' -or ($nameArg -and $_.Name -eq $nameArg)
    }

    if (-not $ggufProviders) {
        Write-Host '  No gguf-local-* providers found in models.json.' -ForegroundColor DarkGray
        Write-Host '  Add one first: 8sync gsd add gguf' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-HintSection 'GSD -- Remove GGUF provider'
    Write-Host ''

    foreach ($provider in $ggufProviders) {
        Write-Host ("  Removing: {0}  ->  {1}" -f $provider.Name, $provider.Value.baseUrl) -ForegroundColor Yellow
        if ($dryRun) { continue }

        $newProviders = [pscustomobject]@{}
        foreach ($existing in $data.providers.PSObject.Properties) {
            if ($existing.Name -ne $provider.Name) {
                $newProviders | Add-Member -NotePropertyName $existing.Name -NotePropertyValue $existing.Value
            }
        }
        $data.providers = $newProviders
    }

    if ($dryRun) {
        Write-Host '  [dry-run] models.json not modified.' -ForegroundColor DarkYellow
    } else {
        Write-GsdModelsJson $data
        Write-Host ("  [OK] Updated {0}" -f (Get-GsdModelsJsonPath)) -ForegroundColor Green
    }
    Write-Host ''
}

# ─────────────────────────────────────────────────────────────────────────────
# 8sync gsd -- GSD model routing setup
# ─────────────────────────────────────────────────────────────────────────────

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

function Show-GsdHelp {
    Write-Host ''
    Write-HintSection 'GSD -- Model routing setup'
    Write-HintRow '8sync gsd setup'                   'Copy PREFERENCES.md + models.json -> ~/.gsd (replace)'
    Write-HintRow '8sync gsd setup --dry-run'         'Preview paths without writing anything'
    Write-HintRow '8sync gsd key z-coding-plan <key>' 'Set Z_CODING_PLAN_API_KEY (session + persist)'
    Write-HintRow '8sync gsd status'                  'Show GSD paths, logged-in providers, key status'
    Write-HintRow '8sync gsd help'                    'Show this help'
    Write-Host ''
    Write-Host '  After setup, login providers in GSD: /login' -ForegroundColor DarkGray
    Write-Host '  Then verify: /gsd prefs   /model' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdSetup {
    param([switch]$DryRun)

    $bundleDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\gsd-config'))
    $gsdHome   = Resolve-GsdHome
    $agentDir  = Resolve-GsdAgentDir

    $copies = @(
        @{ Src = Join-Path $bundleDir 'PREFERENCES.md'; Dest = Join-Path $gsdHome  'PREFERENCES.md' }
        @{ Src = Join-Path $bundleDir 'models.json';    Dest = Join-Path $agentDir 'models.json'    }
    )

    Write-Host ''
    Write-Host '  [gsd] Setup model routing' -ForegroundColor Cyan
    Write-Host ("  source:  {0}" -f $bundleDir) -ForegroundColor DarkGray
    Write-Host ("  gsd dir: {0}" -f $gsdHome)   -ForegroundColor DarkGray
    Write-Host ''

    foreach ($c in $copies) {
        if (-not (Test-Path $c.Src)) {
            Write-Host ("  [error] source not found: {0}" -f $c.Src) -ForegroundColor Red
            return
        }
    }

    if ($DryRun) {
        Write-Host '  [dry-run] No files written.' -ForegroundColor Yellow
        foreach ($c in $copies) {
            Write-Host ("  [dry-run] {0}" -f $c.Dest) -ForegroundColor DarkYellow
        }
        Write-Host ''
        return
    }

    foreach ($c in $copies) {
        $dir = Split-Path $c.Dest -Parent
        if (-not (Test-Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }
        try {
            Copy-Item -Path $c.Src -Destination $c.Dest -Force -ErrorAction Stop
            Write-Host ("  [ok] {0}" -f $c.Dest) -ForegroundColor Green
        } catch {
            Write-Host ("  [error] {0} -- {1}" -f $c.Dest, $_.Exception.Message) -ForegroundColor Red
        }
    }

    Write-Host ''
    Write-Host '  Done. Next: /login in GSD, then /gsd prefs to verify.' -ForegroundColor Cyan
    Write-Host ''
}

# Known providers and their env var names
$script:GsdProviderKeys = [ordered]@{
    'z-coding-plan'    = 'Z_CODING_PLAN_API_KEY'
    'anthropic'        = 'ANTHROPIC_API_KEY'
    'openai'           = 'OPENAI_API_KEY'
    'google'           = 'GOOGLE_API_KEY'
    'openrouter'       = 'OPENROUTER_API_KEY'
    'groq'             = 'GROQ_API_KEY'
    'context7'         = 'CONTEXT7_API_KEY'
    'jina'             = 'JINA_API_KEY'
    'brave'            = 'BRAVE_API_KEY'
    'tavily'           = 'TAVILY_API_KEY'
}

function Invoke-GsdKey {
    param([string]$Provider, [string]$Key)

    if ([string]::IsNullOrWhiteSpace($Provider) -or [string]::IsNullOrWhiteSpace($Key)) {
        Write-Host ''
        Write-Host '  Usage: 8sync gsd key <provider> <api-key>' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Providers:' -ForegroundColor DarkGray
        foreach ($p in $script:GsdProviderKeys.Keys) {
            Write-Host ("    {0,-20} {1}" -f $p, $script:GsdProviderKeys[$p]) -ForegroundColor White
        }
        Write-Host ''
        return
    }

    $providerLower = $Provider.ToLowerInvariant()
    if (-not $script:GsdProviderKeys.Contains($providerLower)) {
        Write-Host ("  [error] Unknown provider '{0}'. Run: 8sync gsd key (no args) to list providers." -f $Provider) -ForegroundColor Red
        Write-Host ''
        return
    }

    $envVarName = $script:GsdProviderKeys[$providerLower]

    # Set for current session
    [System.Environment]::SetEnvironmentVariable($envVarName, $Key, 'Process')
    # Persist for all future sessions
    [System.Environment]::SetEnvironmentVariable($envVarName, $Key, 'User')

    # Also write to ~/.gsd/agent/.env so GSD daemon picks it up
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
    Write-Host ("  [gsd] {0} = {1}" -f $envVarName, $providerLower) -ForegroundColor Green
    Write-Host '  Active now and persisted for all future sessions.' -ForegroundColor DarkGray
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

    # Logged-in providers from auth.json
    $authPath = Join-Path $agentDir 'auth.json'
    if (Test-Path $authPath) {
        try {
            $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            Write-Host '  Logged-in providers:' -ForegroundColor DarkGray
            $auth.PSObject.Properties | ForEach-Object {
                $type = if ($_.Value.type) { $_.Value.type } else { '?' }
                Write-Host ("    {0,-28} {1}" -f $_.Name, $type) -ForegroundColor White
            }
        } catch {
            Write-Host '  auth.json: could not parse' -ForegroundColor DarkYellow
        }
    }

    Write-Host ''

    # API key status for known providers
    Write-Host '  API keys:' -ForegroundColor DarkGray
    $envFile = Join-Path $agentDir '.env'
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
            $status = 'set (env)'
            $color  = 'Green'
        } elseif (-not [string]::IsNullOrWhiteSpace($fromUser)) {
            $status = 'set (user)'
            $color  = 'Green'
        } elseif ($fromFile) {
            $status = 'set (.env only -- run: 8sync gsd key ' + $provider + ' <key>)'
            $color  = 'DarkYellow'
        } else {
            $status = 'not set'
            $color  = 'DarkGray'
        }
        Write-Host ("    {0,-20} {1,-16} {2}" -f $provider, $varName, $status) -ForegroundColor $color
    }

    Write-Host ''
}

function Invoke-GsdCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun = $Rest -contains '--dry-run'
    $sub    = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { 'setup' }

    switch ($sub) {
        'setup'  { Invoke-GsdSetup -DryRun:$dryRun }
        'status' { Invoke-GsdStatus }
        'key'    { Invoke-GsdKey -Provider ($Rest | Select-Object -Skip 1 -First 1) -Key ($Rest | Select-Object -Skip 2 -First 1) }
        'help'   { Show-GsdHelp }
        default  { Show-GsdHelp }
    }
}

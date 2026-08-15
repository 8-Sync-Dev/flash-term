# ---------------------------------------------------------------------------
#  ft gateway -- expose omp's OAuth'd providers (Claude / Gemini / GLM) as a
#  local OpenAI-compatible endpoint any client (ZCode, etc.) can call.
#  Backed by: `omp auth-broker serve` (credential vault, refreshes OAuth) +
#  `omp auth-gateway serve` (proxy that injects the live token per request).
# ---------------------------------------------------------------------------

function Get-OmpGatewayTokenPath {
    return (Join-Path $HOME '.omp' 'auth-gateway.token')
}

function Test-GatewayPortListening {
    param([Parameter(Mandatory)] [int]$Port)

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if ($task.Wait(300) -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Wait-GatewayPort {
    param([Parameter(Mandatory)] [int]$Port, [int]$Tries = 20)

    for ($i = 0; $i -lt $Tries; $i++) {
        if (Test-GatewayPortListening -Port $Port) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Get-OmpGatewayToken {
    # Materialize the token file on first use (omp creates it on demand).
    $path = Get-OmpGatewayTokenPath
    if (-not (Test-Path $path) -and (Test-CommandExists 'omp')) {
        try { $null = & omp auth-gateway token 2>$null } catch { }
    }
    if (Test-Path $path) {
        try { return (Get-Content -Raw -Path $path -ErrorAction Stop).Trim() } catch { return $null }
    }
    return $null
}

function Get-GatewayMaskedToken {
    $token = Get-OmpGatewayToken
    if (-not $token) { return '(missing -- run: ft gateway start)' }
    if ($token.Length -le 10) { return $token }
    return ('{0}...{1}' -f $token.Substring(0, 6), $token.Substring($token.Length - 4))
}

function Start-OmpGateway {
    if (-not (Test-CommandExists 'omp')) {
        Write-Host '[ft] omp not found. Install su-code first: ft setup' -ForegroundColor Red
        return
    }

    $brokerUp = Test-GatewayPortListening -Port $script:OmpBrokerPort
    if (-not $brokerUp) {
        try {
            Start-Process -FilePath 'omp' -ArgumentList @('auth-broker', 'serve', ('--bind=127.0.0.1:{0}' -f $script:OmpBrokerPort)) -WindowStyle Hidden
        } catch {
            Write-Warning ('[ft] Failed to start omp auth-broker: {0}' -f $_)
            return
        }
        if (Wait-GatewayPort -Port $script:OmpBrokerPort) {
            Write-Host ('[ft] auth-broker listening on 127.0.0.1:{0}' -f $script:OmpBrokerPort) -ForegroundColor Green
        } else {
            Write-Warning '[ft] auth-broker did not come up in time.'
            return
        }
    } else {
        Write-Host ('[ft] auth-broker already running (port {0})' -f $script:OmpBrokerPort) -ForegroundColor DarkGray
    }

    $gatewayUp = Test-GatewayPortListening -Port $script:OmpGatewayPort
    if (-not $gatewayUp) {
        $null = Get-OmpGatewayToken
        try {
            $env:OMP_AUTH_BROKER_URL = 'http://127.0.0.1:{0}' -f $script:OmpBrokerPort
            Start-Process -FilePath 'omp' -ArgumentList @('auth-gateway', 'serve', ('--bind=127.0.0.1:{0}' -f $script:OmpGatewayPort)) -WindowStyle Hidden
        } catch {
            Write-Warning ('[ft] Failed to start omp auth-gateway: {0}' -f $_)
            return
        }
        if (Wait-GatewayPort -Port $script:OmpGatewayPort) {
            Write-Host ('[ft] auth-gateway listening on 127.0.0.1:{0}' -f $script:OmpGatewayPort) -ForegroundColor Green
        } else {
            Write-Warning '[ft] auth-gateway did not come up in time.'
            return
        }
    } else {
        Write-Host ('[ft] auth-gateway already running (port {0})' -f $script:OmpGatewayPort) -ForegroundColor DarkGray
    }

    Write-Host ''
    Show-GatewayProviderCard
}

function Stop-OmpGateway {
    $ports = @($script:OmpBrokerPort, $script:OmpGatewayPort)
    $stopped = @()
    try {
        $conns = Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $ports -contains $_.LocalPort -and $_.LocalAddress -in @('127.0.0.1', '0.0.0.0', '::1', '::') }
        foreach ($procId in ($conns | Select-Object -ExpandProperty OwningProcess -Unique)) {
            if ($procId -and $procId -ne $PID) {
                try {
                    Stop-Process -Id $procId -Force -ErrorAction Stop
                    $stopped += $procId
                } catch { }
            }
        }
    } catch {
        Write-Warning ('[ft] Could not query listeners: {0}' -f $_)
        return
    }

    if ($stopped.Count -gt 0) {
        Write-Host ('[ft] Stopped gateway process(es): {0}' -f ($stopped -join ', ')) -ForegroundColor Green
    } else {
        Write-Host '[ft] Nothing to stop (gateway not running).' -ForegroundColor DarkGray
    }
}

function Show-GatewayProviderCard {
    # The exact values to paste into a custom-provider form (ZCode et al).
    $gatewayUp = Test-GatewayPortListening -Port $script:OmpGatewayPort
    Write-Host ''
    Write-HintSection 'OMP GATEWAY -- provider settings'
    Write-HintRow 'Base URL'   ('http://127.0.0.1:{0}/v1' -f $script:OmpGatewayPort)
    Write-HintRow 'API key'    ('{0}   (full value: ft gateway key)' -f (Get-GatewayMaskedToken))
    Write-HintRow 'API format' 'OpenAI-compatible (chat completions)'
    Write-HintRow 'Models'     'anthropic/claude-sonnet-5, google-antigravity/gemini-3-pro, zai/glm-5.3, ...'
    Write-HintRow 'Full list'  'ft gateway models'
    if (-not $gatewayUp) {
        Write-HintRow 'Status' 'NOT RUNNING -- start with: ft gateway start'
    }
    Write-Host ''
    Write-Host '  OAuth refresh is handled by omp -- no manual token rotation needed.' -ForegroundColor DarkGray
    Write-Host '  Requires su-code OAuth login first: omp auth-broker login anthropic|google-antigravity|zai' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GatewayStatus {
    $omp = Test-CommandExists 'omp'
    $brokerUp = Test-GatewayPortListening -Port $script:OmpBrokerPort
    $gatewayUp = Test-GatewayPortListening -Port $script:OmpGatewayPort

    Write-Host ''
    Write-HintSection 'GATEWAY STATUS'
    Write-HintRow 'omp binary'   $(if ($omp) { 'ok' } else { 'missing (install: ft setup)' })
    Write-HintRow ('auth-broker (port {0})' -f $script:OmpBrokerPort) $(if ($brokerUp) { 'listening' } else { 'stopped' })
    Write-HintRow ('auth-gateway (port {0})' -f $script:OmpGatewayPort) $(if ($gatewayUp) { 'listening' } else { 'stopped' })
    Write-Host ''
    Show-GatewayProviderCard
}

function Get-GatewayModels {
    if (-not (Test-GatewayPortListening -Port $script:OmpGatewayPort)) {
        Write-Warning '[ft] Gateway not running. Start it first: ft gateway start'
        return
    }
    $token = Get-OmpGatewayToken
    if (-not $token) {
        Write-Warning '[ft] Gateway token missing at ~/.omp/auth-gateway.token'
        return
    }

    try {
        $resp = Invoke-RestMethod -Method Get -Uri ('http://127.0.0.1:{0}/v1/models' -f $script:OmpGatewayPort) `
            -Headers @{ Authorization = ('Bearer {0}' -f $token) } -TimeoutSec 15 -ErrorAction Stop
    } catch {
        Write-Warning ('[ft] Model list request failed: {0}' -f $_.Exception.Message)
        return
    }

    $ids = @($resp.data | ForEach-Object { $_.id }) | Sort-Object
    $groups = $ids | Group-Object { ($_ -split '/')[0] }
    Write-Host ''
    Write-HintSection ('GATEWAY MODELS ({0})' -f $ids.Count)
    foreach ($g in $groups) {
        Write-Host ('  {0} ({1}):' -f $g.Name, $g.Count) -ForegroundColor Cyan
        foreach ($id in $g.Group) {
            Write-Host ('    {0}' -f $id) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    Write-Host '  Paste any ID above into the provider form model list.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GatewayHelp {
    Write-Host ''
    Write-HintSection 'GATEWAY -- reuse omp OAuth (Claude / Gemini / GLM) in any OpenAI-compatible client'
    Write-HintRow 'ft gateway'          'Show status + the provider values to paste into ZCode'
    Write-HintRow 'ft gateway start'    'Start auth-broker + auth-gateway in the background'
    Write-HintRow 'ft gateway stop'     'Stop both background processes'
    Write-HintRow 'ft gateway key'      'Print the gateway API key (for copy/paste)'
    Write-HintRow 'ft gateway models'   'List every available model ID through the gateway'
    Write-HintRow 'ft gateway help'     'This help'
    Write-Host ''
}

function Invoke-GatewayCommand {
    param([string[]]$Rest)

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-GatewayStatus
        return
    }

    if ($Rest -contains '--help' -or $Rest -contains '-h' -or $Rest -contains 'help') {
        Show-GatewayHelp
        return
    }

    switch ($Rest[0].ToLowerInvariant()) {
        'status'  { Show-GatewayStatus }
        'start'   { Start-OmpGateway }
        'stop'    { Stop-OmpGateway }
        'restart' {
            Stop-OmpGateway
            Start-Sleep -Milliseconds 500
            Start-OmpGateway
        }
        'key'     {
            $token = Get-OmpGatewayToken
            if ($token) { Write-Host $token -ForegroundColor Green }
            else { Write-Warning '[ft] No gateway token yet. Run: ft gateway start' }
        }
        'models'  { Get-GatewayModels }
        default   { Write-Warning '[ft] Unknown gateway option. Use: ft gateway help' }
    }
}

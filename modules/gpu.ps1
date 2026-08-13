function Clamp-GpuPercent {
    param([int]$Value)

    if ($Value -lt 0) { return 0 }
    if ($Value -gt 100) { return 100 }
    return $Value
}

function Get-CurrentGpuMinPercent {
    $defaultValue = Clamp-GpuPercent -Value $script:GpuMinPercentDefault
    if (-not (Test-Path $script:CurrentGpuLuaPath)) {
        return $defaultValue
    }

    try {
        $raw = Get-Content -Raw -Path $script:CurrentGpuLuaPath -ErrorAction Stop
        $match = [regex]::Match($raw, 'min_percent\s*=\s*(\d+)')
        if ($match.Success) {
            return Clamp-GpuPercent -Value ([int]$match.Groups[1].Value)
        }
    } catch {
    }

    return $defaultValue
}

function Write-CurrentGpuState {
    param([Parameter(Mandatory)] [int]$MinPercent)

    $safePercent = Clamp-GpuPercent -Value $MinPercent
    $timestamp = [datetime]::UtcNow.ToString('o')
    $lua = @(
        'return {',
        ('  min_percent = {0},' -f $safePercent),
        ('  updated_utc = "{0}",' -f $timestamp),
        '}'
    )

    Set-Content -Path $script:CurrentGpuLuaPath -Value $lua -Encoding UTF8
}

function Show-GpuStatus {
    $current = Get-CurrentGpuMinPercent
    $profile = if ($current -ge 10) { 'high-performance bias' } else { 'balanced power' }

    Write-Host ''
    Write-HintSection 'GPU STATUS'
    Write-HintRow 'Minimum GPU target' ('{0}% ({1})' -f $current, $profile)
    Write-HintRow 'State file' $script:CurrentGpuLuaPath
    Write-Host ''
}

function Show-GpuHelp {
    Write-Host ''
    Write-HintSection 'GPU -- reduce render lag with adaptive policy'
    Write-HintRow 'ft gpu status' 'Show current GPU target and active profile'
    Write-HintRow 'ft gpu 10' 'Set minimum GPU target to 10% (recommended for smoother rendering)'
    Write-HintRow 'ft gpu <0-100>' 'Set custom minimum GPU target percent'
    Write-HintRow 'ft gpu auto' ('Reset target to default ({0}%)' -f $script:GpuMinPercentDefault)
    Write-HintRow 'ft gpu off' 'Set target to 0% (balanced power mode)'
    Write-Host ''
}

function Set-GpuMinPercent {
    param([Parameter(Mandatory)] [int]$MinPercent)

    $safePercent = Clamp-GpuPercent -Value $MinPercent
    try {
        Write-CurrentGpuState -MinPercent $safePercent
    } catch {
        Write-Warning ('[ft] Failed to write GPU state: {0}' -f $_)
        return
    }

    Write-Host ('[ft] GPU minimum target set to {0}%' -f $safePercent) -ForegroundColor Green
    if ($safePercent -ge 10) {
        Write-Host '[ft] Applying high-performance GPU bias to reduce UI lag.' -ForegroundColor Yellow
    } else {
        Write-Host '[ft] Applying balanced GPU policy for lower power usage.' -ForegroundColor DarkGray
    }

    try {
        Try-ReloadWezTerm
    } catch {
        Write-Warning ('[ft] GPU state saved, but WezTerm reload failed: {0}' -f $_)
    }
}

function Invoke-GpuCommand {
    param([string[]]$Rest)

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-GpuStatus
        return
    }

    if ($Rest -contains '--help' -or $Rest -contains '-h' -or $Rest -contains 'help') {
        Show-GpuHelp
        return
    }

    $sub = $Rest[0].ToLowerInvariant()
    switch ($sub) {
        'status' {
            Show-GpuStatus
            return
        }
        'auto' {
            Set-GpuMinPercent -MinPercent $script:GpuMinPercentDefault
            return
        }
        'off' {
            Set-GpuMinPercent -MinPercent 0
            return
        }
    }

    $parsed = 0
    if ([int]::TryParse($sub, [ref]$parsed)) {
        if ($parsed -lt 0 -or $parsed -gt 100) {
            Write-Warning '[ft] gpu value must be between 0 and 100.'
            return
        }
        Set-GpuMinPercent -MinPercent $parsed
        return
    }

    Write-Warning '[ft] Unknown gpu option. Use: ft gpu help'
}

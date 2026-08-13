function Show-ThemeHelp {
    Write-Host ''
    Write-HintSection 'WEZTERM GLASS THEME'
    Write-HintRow 'ft theme status'                  'Show current style, scene, and adaptive hint'
    Write-HintRow 'ft theme list'                    'List available styles and scenes'
    Write-HintRow 'ft theme <style> [scene]'         'Set style quickly, optional scene'
    Write-HintRow 'ft theme style <name>'            'Set style only'
    Write-HintRow 'ft theme scene <name>'            'Set scene only'
    Write-HintRow 'ft theme help'                    'Show this help'
    Write-Host ''
}

function Show-ThemeStatus {
    $state = Read-CurrentStyleState
    Write-Host ''
    Write-Host ('  glass style: {0}' -f $state.style) -ForegroundColor Cyan
    Write-Host ('  glass scene: {0}' -f $state.scene) -ForegroundColor Cyan
    Write-Host ('  adaptive hint: {0}' -f $state.bgHint) -ForegroundColor DarkGray
    Write-Host ('  styles: {0}' -f ($script:KnownGlassStyles -join ', ')) -ForegroundColor DarkGray
    Write-Host ('  scenes: {0}' -f ($script:KnownGlassScenes -join ', ')) -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ThemeCommand {
    param([string[]]$Rest)

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-ThemeStatus
        Show-ThemeHelp
        return
    }

    $sub = $Rest[0].ToLowerInvariant()

    if ($sub -in @('help', '--help', '-h')) {
        Show-ThemeHelp
        return
    }

    if ($sub -eq 'status') {
        Show-ThemeStatus
        return
    }

    if ($sub -eq 'list') {
        Show-ThemeStatus
        return
    }

    $targetStyle = $null
    $targetScene = $null

    switch ($sub) {
        'style' {
            if ($Rest.Count -lt 2) {
                Write-Host ('Usage: ft theme style <{0}>' -f ($script:KnownGlassStyles -join '|')) -ForegroundColor DarkYellow
                return
            }
            $targetStyle = $Rest[1].ToLowerInvariant()
        }
        'scene' {
            if ($Rest.Count -lt 2) {
                Write-Host ('Usage: ft theme scene <{0}>' -f ($script:KnownGlassScenes -join '|')) -ForegroundColor DarkYellow
                return
            }
            $targetScene = $Rest[1].ToLowerInvariant()
        }
        default {
            if ($script:KnownGlassStyles -contains $sub) {
                $targetStyle = $sub
                if ($Rest.Count -ge 2) {
                    $targetScene = $Rest[1].ToLowerInvariant()
                }
            } elseif ($script:KnownGlassScenes -contains $sub) {
                $targetScene = $sub
            } else {
                Write-Host 'Unknown theme command.' -ForegroundColor DarkYellow
                Show-ThemeHelp
                return
            }
        }
    }

    if ($targetStyle -and -not ($script:KnownGlassStyles -contains $targetStyle)) {
        Write-Host ('Invalid style: {0}' -f $targetStyle) -ForegroundColor DarkYellow
        Write-Host ('Valid styles: {0}' -f ($script:KnownGlassStyles -join ', ')) -ForegroundColor DarkGray
        return
    }

    if ($targetScene -and -not ($script:KnownGlassScenes -contains $targetScene)) {
        Write-Host ('Invalid scene: {0}' -f $targetScene) -ForegroundColor DarkYellow
        Write-Host ('Valid scenes: {0}' -f ($script:KnownGlassScenes -join ', ')) -ForegroundColor DarkGray
        return
    }

    $result = Write-CurrentStyleLua -Style $targetStyle -Scene $targetScene
    Write-Host ('Glass theme updated: style={0} scene={1} hint={2}' -f $result.style, $result.scene, $result.bgHint) -ForegroundColor Green
    Try-ReloadWezTerm
}

function Invoke-HxCommand {
    param([string[]]$Rest)

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-HxHelp
        return
    }

    $sub = $Rest[0].ToLowerInvariant()
    switch ($sub) {
        'help'    { Show-HxHelp }
        'lang'    {
            $name = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
            Invoke-HxLang -LangName $name
        }
        'health'  { Invoke-HxHealth }
        'wrap'    { Invoke-HxWrap }
        'opacity' {
            $val = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
            Invoke-HxOpacity -Value $val
        }
        'theme'   {
            $name = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
            Invoke-HxTheme -ThemeName $name
        }
        'bg'      {
            $style = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
            Invoke-HxBg -Style $style
        }
        default   { Show-HxHelp }
    }
}

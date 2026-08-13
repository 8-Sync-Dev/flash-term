function Ensure-HelixConfigDir {
    if (-not (Test-Path $script:HelixConfigDir)) {
        $null = New-Item -Path $script:HelixConfigDir -ItemType Directory -Force
    }
}

function Read-HelixConfig {
    if (-not (Test-Path $script:HelixConfigPath)) { return @() }
    return @(Get-Content $script:HelixConfigPath)
}

function Get-HelixThemeValue {
    $lines = Read-HelixConfig
    foreach ($line in $lines) {
        if ($line -match '^\s*theme\s*=\s*"([^"]+)"') {
            return $Matches[1]
        }
    }
    return ''
}

function Set-HelixThemeValue {
    param([Parameter(Mandatory)] [string]$Theme)

    Ensure-HelixConfigDir
    $lines = Read-HelixConfig

    if ($lines.Count -eq 0) {
        Set-Content -Path $script:HelixConfigPath -Value "theme = `"$Theme`"" -Encoding UTF8
        return
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $found = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*theme\s*=') {
            $result.Add("theme = `"$Theme`"")
            $found = $true
            continue
        }
        $result.Add($line)
    }

    if (-not $found) {
        $result.Insert(0, "theme = `"$Theme`"")
    }

    $result | Set-Content -Path $script:HelixConfigPath -Encoding UTF8
}

function Get-HelixSoftWrap {
    $lines = Read-HelixConfig
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match '^\[editor\.soft-wrap\]') { $inSection = $true; continue }
        if ($line -match '^\[' -and $inSection) { break }
        if ($inSection -and $line -match '^\s*enable\s*=\s*(true|false)') {
            return $Matches[1] -eq 'true'
        }
    }
    return $false
}

function Set-HelixSoftWrap {
    param([bool]$Enable)

    Ensure-HelixConfigDir
    $val = if ($Enable) { 'true' } else { 'false' }
    $lines = Read-HelixConfig

    if ($lines.Count -eq 0) {
        @('[editor.soft-wrap]', "enable = $val") | Set-Content -Path $script:HelixConfigPath -Encoding UTF8
        return
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    $found = $false
    $sectionFound = $false

    foreach ($line in $lines) {
        if ($line -match '^\[editor\.soft-wrap\]') {
            $inSection = $true
            $sectionFound = $true
            $result.Add($line)
            continue
        }
        if ($line -match '^\[' -and $inSection) {
            if (-not $found) {
                $result.Add("enable = $val")
                $found = $true
            }
            $inSection = $false
        }
        if ($inSection -and $line -match '^\s*enable\s*=') {
            $result.Add("enable = $val")
            $found = $true
            continue
        }
        $result.Add($line)
    }

    if ($inSection -and -not $found) {
        $result.Add("enable = $val")
        $found = $true
    }

    if (-not $sectionFound) {
        $result.Add('')
        $result.Add('[editor.soft-wrap]')
        $result.Add("enable = $val")
    }

    $result | Set-Content -Path $script:HelixConfigPath -Encoding UTF8
}

function Read-CurrentOpacity {
    if (-not (Test-Path $script:CurrentOpacityPath)) {
        return $script:DefaultOpacity
    }
    $content = Get-Content -Raw $script:CurrentOpacityPath
    if ($content -match 'return\s+([\d.]+)') {
        $val = [double]$Matches[1]
        return [Math]::Max(0.0, [Math]::Min(1.0, $val))
    }
    return $script:DefaultOpacity
}

function Write-CurrentOpacity {
    param([double]$Value)
    $clamped = [Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $Value)), 2)
    Set-Content -Path $script:CurrentOpacityPath -Value "return $clamped" -Encoding UTF8
}

function Get-HelixThemeList {
    $themeDirs = @(
        (Join-Path $env:APPDATA 'helix\runtime\themes'),
        (Join-Path $HOME 'scoop\apps\helix\current\runtime\themes')
    )
    foreach ($dir in $themeDirs) {
        if (Test-Path $dir) {
            return Get-ChildItem -Path $dir -Filter '*.toml' |
                ForEach-Object { $_.BaseName } | Sort-Object
        }
    }
    return @()
}

function Invoke-HxTheme {
    param([string]$ThemeName)

    if ($ThemeName) {
        Set-HelixThemeValue -Theme $ThemeName
        Write-Host "Helix theme set to: $ThemeName" -ForegroundColor Green
        return
    }

    $themes = Get-HelixThemeList
    if (-not $themes -or $themes.Count -eq 0) {
        Write-Host 'No themes found. Is Helix installed?' -ForegroundColor DarkYellow
        return
    }

    if (-not (Test-CommandExists 'fzf')) {
        Write-Host 'fzf is missing. Run "ft sync" or use "ft hx theme <name>".' -ForegroundColor DarkYellow
        return
    }

    $current = Get-HelixThemeValue
    $selected = $themes | fzf --height=50% --layout=reverse --border --prompt='Theme> ' --query="$current"
    if ($selected) {
        Set-HelixThemeValue -Theme $selected
        Write-Host "Helix theme set to: $selected" -ForegroundColor Green
    }
}

function Set-HelixBg {
    param([string]$Style)

    $helixThemesDir = Join-Path $env:APPDATA 'helix\themes'
    $themeFile      = Join-Path $helixThemesDir 'glass_black.toml'

    if (-not (Test-Path $helixThemesDir)) {
        $null = New-Item -ItemType Directory -Path $helixThemesDir -Force
    }

    # Resolve current base theme to inherit from (default: catppuccin_mocha)
    $base = Get-HelixThemeValue
    if (-not $base -or $base -eq 'glass_black') { $base = 'catppuccin_mocha' }

    switch ($Style.ToLowerInvariant()) {
        'black' {
            @(
                "# glass_black - pure black background over $base",
                "inherits = `"$base`"",
                '',
                '"ui.background" = { bg = "#000000" }',
                '"ui.cursorline.primary" = { bg = "#0d0d0d" }'
            ) | Set-Content -Path $themeFile -Encoding UTF8
        }
        'transparent' {
            @(
                "# glass_black - transparent background (terminal bg shows through)",
                "inherits = `"$base`"",
                '',
                '"ui.background" = { }'
            ) | Set-Content -Path $themeFile -Encoding UTF8
        }
        'reset' {
            if (Test-Path $themeFile) { Remove-Item $themeFile -Force }
            Set-HelixThemeValue -Theme $base
            Write-Host "  [hx bg] Reset to base theme: $base" -ForegroundColor Green
            return
        }
        default {
            # Treat as hex color or named color
            $color = $Style
            if ($color -notmatch '^#') { $color = "#$color" }
            @(
                "# glass_black - custom background",
                "inherits = `"$base`"",
                '',
                "`"ui.background`" = { bg = `"$color`" }"
            ) | Set-Content -Path $themeFile -Encoding UTF8
        }
    }

    Set-HelixThemeValue -Theme 'glass_black'
    Write-Host ("  [hx bg] Background set to '{0}' (theme: glass_black <- {1})" -f $Style, $base) -ForegroundColor Green
}

function Invoke-HxBg {
    param([string]$Style)

    if (-not $Style -or $Style -eq 'help') {
        Write-Host ''
        Write-HintSection 'HX BG -- set Helix background color'
        Write-HintRow 'ft hx bg black'        'Pure black (#000000) background'
        Write-HintRow 'ft hx bg transparent'  'Transparent (terminal bg shows through)'
        Write-HintRow 'ft hx bg <#hex>'       'Custom hex color e.g. ft hx bg 0a0a0a'
        Write-HintRow 'ft hx bg reset'         'Remove override, restore original theme'
        Write-Host ''
        Write-Host '  Current theme:' -NoNewline -ForegroundColor DarkGray
        Write-Host (' ' + (Get-HelixThemeValue)) -ForegroundColor Cyan
        Write-Host ''
        return
    }

    Set-HelixBg -Style $Style
}

function Invoke-HxWrap {
    $current = Get-HelixSoftWrap
    $new = -not $current
    Set-HelixSoftWrap -Enable $new
    $state = if ($new) { 'ON' } else { 'OFF' }
    Write-Host "Helix soft-wrap: $state" -ForegroundColor Green
}

function Invoke-HxOpacity {
    param([string]$Value)

    $current = Read-CurrentOpacity

    if (-not $Value) {
        Write-Host ("Current overlay opacity: {0:F2}" -f $current) -ForegroundColor Cyan
        Write-Host 'Usage: ft hx opacity <+|-|0.0-1.0>' -ForegroundColor DarkGray
        return
    }

    $newVal = $current
    switch ($Value) {
        '+' { $newVal = $current + $script:OpacityStep }
        '-' { $newVal = $current - $script:OpacityStep }
        default {
            try {
                $newVal = [double]$Value
            } catch {
                Write-Host 'Invalid value. Use +, -, or a number between 0.0 and 1.0.' -ForegroundColor DarkYellow
                return
            }
        }
    }

    Write-CurrentOpacity -Value $newVal
    $actual = Read-CurrentOpacity
    Write-Host ("Overlay opacity: {0:F2}" -f $actual) -ForegroundColor Green
    Try-ReloadWezTerm
}

function Invoke-HxLang {
    param([string]$LangName)

    $scoop = Get-ScoopCommand
    if (-not $scoop) {
        Write-Warning 'Scoop not found. Install Scoop first.'
        return
    }

    if ($LangName) {
        $key = $LangName.ToLowerInvariant()
        if ($script:LangServers.Contains($key)) {
            $packages = $script:LangServers[$key]
            Write-Host ("Installing: {0}" -f ($packages -join ', ')) -ForegroundColor Yellow
            & $scoop.Source install @packages | Out-Host
            Write-Host "Language support for '$key' installed." -ForegroundColor Green
        } else {
            Write-Host "Unknown language: $LangName" -ForegroundColor DarkYellow
            Write-Host ("Available: {0}" -f ($script:LangServers.Keys -join ', ')) -ForegroundColor DarkGray
        }
        return
    }

    if (-not (Test-CommandExists 'fzf')) {
        Write-Host 'fzf is missing. Run "ft sync" or use "ft hx lang <name>".' -ForegroundColor DarkYellow
        Write-Host ("Available: {0}" -f ($script:LangServers.Keys -join ', ')) -ForegroundColor DarkGray
        return
    }

    $lines = $script:LangServers.GetEnumerator() | ForEach-Object {
        "{0}`t{1}" -f $_.Key, ($_.Value -join ', ')
    }

    $selected = $lines | fzf --delimiter "`t" --height=50% --layout=reverse --border --prompt='Language> '
    if ($selected) {
        $lang = ($selected -split "`t")[0]
        Invoke-HxLang -LangName $lang
    }
}

function Show-HxHelp {
    Write-Host ''
    Write-HintSection 'HELIX EDITOR'
    Write-HintRow 'ft hx help'           'Show this help'
    Write-HintRow 'ft hx lang [name]'    'Install language toolchain via scoop (fzf picker)'
    Write-HintRow 'ft hx health'         'Parse hx --health: show LSP status, suggest missing'
    Write-HintRow 'ft hx wrap'           'Toggle soft word-wrap on/off'
    Write-HintRow 'ft hx opacity <val>'  '+  -  or 0.0-1.0 -- adjust background transparency'
    Write-HintRow 'ft hx theme [name]'   'Pick Helix color theme (fzf picker)'
    Write-Host ''
}

function Invoke-HxHealth {
    if (-not (Test-CommandExists 'hx')) {
        Write-Host ''
        Write-Host '  Helix (hx) not found. Run: ft sync' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  ft hx health  LSP server status' -ForegroundColor Cyan
    Write-Host ''

    try {
        $raw = & hx --health 2>&1 | Out-String
    } catch {
        Write-Host '  Failed to run hx --health' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    $lines = $raw -split "`n"

    # Collect language rows — lines that start with a language name (not header/section lines)
    # hx --health output format (per language section):
    #   Configured language servers:   <name>  ✓/<path> or ✘ not found
    # Full health output has a flat table:
    #   Language  LSP  DAP  Formatter  ...
    # We want lines that have ✘ or mention "not found" / "None"

    $missing  = [System.Collections.Generic.List[string]]::new()
    $ok       = [System.Collections.Generic.List[string]]::new()
    $partial  = [System.Collections.Generic.List[string]]::new()

    $inTable  = $false
    $headers  = @()

    foreach ($line in $lines) {
        $trimmed = $line.TrimEnd()
        if (-not $trimmed) { continue }

        # Detect header row
        if ($trimmed -match '^Language\s') {
            $inTable = $true
            $headers = $trimmed -split '\s{2,}'
            continue
        }
        if (-not $inTable) { continue }
        # Skip separator lines
        if ($trimmed -match '^[-=]+') { continue }

        # Data row: first token is language name
        $cols = $trimmed -split '\s{2,}'
        if ($cols.Count -lt 2) { continue }
        $lang = $cols[0].Trim()
        if (-not $lang -or $lang -match '^[-=]') { continue }

        # Check columns for ✘ or "None" indicating missing tools
        $rowText = $trimmed
        $hasCheck = $rowText -match '✓'
        $hasCross = $rowText -match '✘'
        $hasNone  = $rowText -match '\bNone\b'

        if ($hasCross -and -not $hasCheck) {
            $null = $missing.Add($lang)
        } elseif ($hasCross -or $hasNone) {
            $null = $partial.Add($lang)
        } else {
            $null = $ok.Add($lang)
        }
    }

    # If table parse yielded nothing, fall back to raw line scan
    if ($ok.Count -eq 0 -and $missing.Count -eq 0 -and $partial.Count -eq 0) {
        foreach ($line in $lines) {
            if ($line -match '✘') {
                # Try to extract language/tool name — first word-like token before ✘
                $m = [regex]::Match($line, '^\s*(\S+)')
                if ($m.Success) { $null = $missing.Add($m.Groups[1].Value) }
            }
        }
    }

    # Print results
    if ($ok.Count -gt 0) {
        Write-Host '  OK' -ForegroundColor Green
        foreach ($l in $ok) {
            Write-Host ('    ✓  {0}' -f $l) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    if ($partial.Count -gt 0) {
        Write-Host '  PARTIAL (some tools missing)' -ForegroundColor Yellow
        foreach ($l in $partial) {
            Write-Host ('    ~  {0}' -f $l) -ForegroundColor Yellow
            Write-Host ('       Run: ft hx lang {0}' -f $l) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    if ($missing.Count -gt 0) {
        Write-Host '  MISSING' -ForegroundColor Red
        foreach ($l in $missing) {
            Write-Host ('    ✘  {0}' -f $l) -ForegroundColor Red
            Write-Host ('       Run: ft hx lang {0}' -f $l) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    if ($ok.Count -eq 0 -and $partial.Count -eq 0 -and $missing.Count -eq 0) {
        # Could not parse — just dump raw output
        Write-Host $raw -ForegroundColor DarkGray
    }

    Write-Host ''
}


function Read-BgCache {
    Ensure-StateDir
    if (-not (Test-Path $script:BgCachePath)) {
        return @()
    }

    try {
        $raw = Get-Content -Raw $script:BgCachePath
        if (-not $raw) {
            return @()
        }
        $parsed = $raw | ConvertFrom-Json
        if ($parsed -is [array]) {
            return $parsed
        }
        return @($parsed)
    } catch {
        return @()
    }
}

function Write-BgCache {
    param([Parameter(Mandatory)] [object[]]$Items)

    Ensure-StateDir
    $trimmed = $Items | Select-Object -First $script:BgCacheLimit
    $trimmed | ConvertTo-Json -Depth 6 | Set-Content -Path $script:BgCachePath -Encoding UTF8
}

function Normalize-WallhavenEntry {
    param([Parameter(Mandatory)] [object]$Item)

    $tags = @()
    if ($Item.tags) {
        $tags = $Item.tags | ForEach-Object { $_.name } | Where-Object { $_ }
    }

    return [pscustomobject]@{
        id         = $Item.id
        resolution = $Item.resolution
        ratio      = $Item.ratio
        page       = $Item.url
        short      = $Item.short_url
        preview    = $Item.thumbs.original
        file       = $Item.path
        colors     = @($Item.colors)
        tags       = $tags
        queriedUtc = [datetime]::UtcNow.ToString('o')
    }
}

function Search-Wallhaven {
    param([Parameter(Mandatory)] [string]$Keywords)

    $encoded = [Uri]::EscapeDataString($Keywords)
    $uri = "https://wallhaven.cc/api/v1/search?q=$encoded&atleast=3840x2160&sorting=relevance&order=desc&categories=111&purity=110"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 20
    } catch {
        Write-Warning 'Wallhaven request failed. Check network access and try again.'
        return @()
    }

    if (-not $response -or -not $response.data) {
        return @()
    }

    $items = @()
    foreach ($entry in $response.data) {
        $items += Normalize-WallhavenEntry -Item $entry
    }
    return $items
}

function Show-BgHelp {
    Write-Host ''
    Write-Host 'Background commands:' -ForegroundColor Yellow
    Write-Host '  8sync bg help'
    Write-Host '  8sync bg search <keywords>'
    Write-Host '  8sync bg pick'
    Write-Host '  8sync bg set <id|path|url>'
    Write-Host '  8sync bg open <id>'
    Write-Host ('  8sync bg rotate [on [N] | off | now | time <min> | status]  (default: {0} min)' -f $script:BgRotateDefaultMinutes)
    Write-Host '  8sync bg list                                 List downloaded images'
    Write-Host '  8sync bg clear cache                          Clear search cache'
    Write-Host '  8sync bg remove <filename|id|all>             Remove downloaded images'
    Write-Host ''
    Write-Host '  Rotate picks random images from bg/ folder.' -ForegroundColor DarkGray
    Write-Host ''
}

function Ensure-BackgroundDir {
    if (-not (Test-Path $script:BackgroundDir)) {
        $null = New-Item -Path $script:BackgroundDir -ItemType Directory -Force
    }
}

function Write-CurrentBgLua {
    param([Parameter(Mandatory)] [string]$Path)

    $escaped = $Path.Replace('\\', '\\\\')
    $content = "return [[{0}]]" -f $escaped
    Set-Content -Path $script:CurrentBgLuaPath -Value $content -Encoding UTF8
}

function Read-CurrentStyleState {
    $style = $script:DefaultGlassStyle
    $scene = $script:DefaultGlassScene
    $bgHint = 'neutral'

    if (Test-Path $script:CurrentStyleLuaPath) {
        try {
            $raw = Get-Content -Raw $script:CurrentStyleLuaPath
            if ($raw -match 'style\s*=\s*"([a-z_]+)"') {
                $candidate = $Matches[1].ToLowerInvariant()
                if ($script:KnownGlassStyles -contains $candidate) { $style = $candidate }
            }
            if ($raw -match 'scene\s*=\s*"([a-z_]+)"') {
                $candidate = $Matches[1].ToLowerInvariant()
                if ($script:KnownGlassScenes -contains $candidate) { $scene = $candidate }
            }
            if ($raw -match 'bg_hint\s*=\s*"([a-z_]+)"') {
                $candidate = $Matches[1].ToLowerInvariant()
                if (@('bright', 'neutral', 'dark') -contains $candidate) { $bgHint = $candidate }
            }
        } catch {
        }
    }

    return [pscustomobject]@{
        style  = $style
        scene  = $scene
        bgHint = $bgHint
    }
}

function Write-CurrentStyleLua {
    param(
        [string]$Style,
        [string]$Scene,
        [string]$BgHint
    )

    $current = Read-CurrentStyleState
    $resolvedStyle = if ($Style) { $Style.ToLowerInvariant() } else { $current.style }
    $resolvedScene = if ($Scene) { $Scene.ToLowerInvariant() } else { $current.scene }
    $resolvedHint = if ($BgHint) { $BgHint.ToLowerInvariant() } else { $current.bgHint }

    if (-not ($script:KnownGlassStyles -contains $resolvedStyle)) { $resolvedStyle = $script:DefaultGlassStyle }
    if (-not ($script:KnownGlassScenes -contains $resolvedScene)) { $resolvedScene = $script:DefaultGlassScene }
    if (-not (@('bright', 'neutral', 'dark') -contains $resolvedHint)) { $resolvedHint = 'neutral' }

    $content = @(
        'return {'
        ('  style = "{0}",' -f $resolvedStyle)
        ('  scene = "{0}",' -f $resolvedScene)
        ('  bg_hint = "{0}",' -f $resolvedHint)
        '}'
    )
    $content | Set-Content -Path $script:CurrentStyleLuaPath -Encoding UTF8

    return [pscustomobject]@{
        style  = $resolvedStyle
        scene  = $resolvedScene
        bgHint = $resolvedHint
    }
}

function Get-WallpaperBrightnessHint {
    param([object]$Entry)

    if (-not $Entry) {
        return 'neutral'
    }

    $palette = @()
    if ($Entry.colors) {
        $palette = @($Entry.colors)
    }

    if ($palette.Count -eq 0) {
        return 'neutral'
    }

    $scores = New-Object System.Collections.Generic.List[double]
    foreach ($hex in $palette) {
        if (-not $hex) { continue }
        $raw = $hex.ToString().TrimStart('#')
        if ($raw.Length -ne 6) { continue }
        try {
            $r = [Convert]::ToInt32($raw.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($raw.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($raw.Substring(4, 2), 16)
            $lum = ((0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b)) / 255.0
            $scores.Add($lum)
        } catch {
        }
    }

    if ($scores.Count -eq 0) {
        return 'neutral'
    }

    $avg = ($scores | Measure-Object -Average).Average
    if ($avg -ge 0.62) { return 'bright' }
    if ($avg -le 0.38) { return 'dark' }
    return 'neutral'
}

function Try-ReloadWezTerm {
    if (Test-CommandExists 'wezterm') {
        try {
            $cliHelp = & wezterm cli --help | Out-String
            if ($cliHelp -match '(?m)^\s+reload\s') {
                & wezterm cli reload | Out-Null
                Write-Host 'WezTerm config reloaded.' -ForegroundColor Green
            } else {
                & wezterm cli list-clients | Out-Null
                Write-Host 'Config updated. Press Ctrl+Shift+R in WezTerm to reload.' -ForegroundColor Green
            }
            return
        } catch {
        }
    }

    Write-Host 'Background updated. Reopen the tab if the image did not refresh.' -ForegroundColor DarkYellow
}

function Resolve-BgTarget {
    param([Parameter(Mandatory)] [string]$Value)

    if ($Value -match '^(https?)://') {
        return [pscustomobject]@{ Type = 'url'; Value = $Value }
    }

    if (Test-Path $Value) {
        $full = (Resolve-Path -Path $Value).Path
        return [pscustomobject]@{ Type = 'path'; Value = $full }
    }

    $cache = Read-BgCache
    $match = $cache | Where-Object { $_.id -eq $Value } | Select-Object -First 1
    if ($match) {
        return [pscustomobject]@{ Type = 'cache'; Value = $match }
    }

    return $null
}

function Save-BgFromUrl {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [string]$FileNameHint
    )

    Ensure-BackgroundDir
    $safeName = $FileNameHint
    if (-not $safeName) {
        $safeName = ([Guid]::NewGuid().ToString('n') + '.jpg')
    }

    $target = Join-Path $script:BackgroundDir $safeName
    try {
        Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing -TimeoutSec 30
        return $target
    } catch {
        Write-Warning 'Failed to download image from URL.'
        return $null
    }
}

function Invoke-BgSearch {
    param([Parameter(Mandatory)] [string]$Keywords)

    $results = Search-Wallhaven -Keywords $Keywords
    if (-not $results -or $results.Count -eq 0) {
        Write-Host 'No results found.' -ForegroundColor DarkYellow
        return
    }

    Write-BgCache -Items $results
    Write-Host ("Saved {0} results to cache." -f ($results.Count)) -ForegroundColor Green
}

function Invoke-BgPick {
    $cache = Read-BgCache
    if (-not $cache -or $cache.Count -eq 0) {
        Write-Host 'No cached results. Run "8sync bg search <keywords>" first.' -ForegroundColor DarkYellow
        return
    }

    if (-not (Test-CommandExists 'fzf')) {
        Write-Host 'fzf is missing. Run "8sync sync" or use "8sync bg set <id>".' -ForegroundColor DarkYellow
        return
    }

    $lines = $cache | ForEach-Object {
        "{0}`t{1}`t{2}`t{3}" -f $_.id, $_.resolution, ($_.tags -join ','), $_.page
    }

    $selected = $lines | fzf --delimiter "`t" --with-nth 1,2,3 --prompt='BG> ' --height=60% --layout=reverse --border
    if (-not $selected) {
        return
    }

    $selectedId = ($selected -split "`t")[0]
    if (-not $selectedId) {
        return
    }

    Invoke-BgSet -Value $selectedId
}

function Invoke-BgSet {
    param([Parameter(Mandatory)] [string]$Value)

    $target = Resolve-BgTarget -Value $Value
    if (-not $target) {
        Write-Host 'Target not found. Use an id from cache, a local path, or a URL.' -ForegroundColor DarkYellow
        return
    }

    $finalPath = $null
    $bgHint = 'neutral'
    switch ($target.Type) {
        'path' {
            $finalPath = $target.Value
        }
        'url' {
            $fileName = Split-Path -Leaf $target.Value
            $downloaded = Save-BgFromUrl -Url $target.Value -FileNameHint $fileName
            if ($downloaded) {
                $finalPath = $downloaded
            }
        }
        'cache' {
            $entry = $target.Value
            $fileName = ("wallhaven-{0}.jpg" -f $entry.id)
            $downloaded = Save-BgFromUrl -Url $entry.file -FileNameHint $fileName
            if ($downloaded) {
                $finalPath = $downloaded
            }
            $bgHint = Get-WallpaperBrightnessHint -Entry $entry
        }
    }

    if (-not $finalPath) {
        Write-Host 'Failed to set background.' -ForegroundColor DarkYellow
        return
    }

    Write-CurrentBgLua -Path $finalPath
    $styleState = Write-CurrentStyleLua -BgHint $bgHint
    Write-Host ("Glass adaptive hint: {0}" -f $styleState.bgHint) -ForegroundColor DarkGray
    Try-ReloadWezTerm
}

function Invoke-BgOpen {
    param([Parameter(Mandatory)] [string]$Id)

    $cache = Read-BgCache
    $entry = $cache | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $entry) {
        Write-Host 'ID not found in cache.' -ForegroundColor DarkYellow
        return
    }

    $page = $entry.page
    if (-not $page) {
        Write-Host 'No page URL found for this entry.' -ForegroundColor DarkYellow
        return
    }

    try {
        Start-Process $page | Out-Null
    } catch {
        Write-Host $page
    }
}

function Read-BgRotateState {
    Ensure-StateDir
    if (-not (Test-Path $script:BgRotatePath)) {
        return [pscustomobject]@{ enabled = $false; intervalMinutes = $script:BgRotateDefaultMinutes; lastRotatedUtc = $null }
    }
    try {
        return Get-Content -Raw $script:BgRotatePath | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ enabled = $false; intervalMinutes = $script:BgRotateDefaultMinutes; lastRotatedUtc = $null }
    }
}

function Write-BgRotateState {
    param([bool]$Enabled, [int]$IntervalMinutes, [string]$LastRotatedUtc = '')
    Ensure-StateDir
    $state = Read-BgRotateState
    if ($LastRotatedUtc -eq '') { $LastRotatedUtc = $state.lastRotatedUtc }
    [pscustomobject]@{
        enabled         = $Enabled
        intervalMinutes = $IntervalMinutes
        lastRotatedUtc  = $LastRotatedUtc
    } | ConvertTo-Json | Set-Content -Path $script:BgRotatePath -Encoding UTF8
}

function Invoke-BgRotateNow {
    Ensure-BackgroundDir
    $imageExts = @('*.jpg','*.jpeg','*.png','*.bmp','*.gif','*.webp')
    $allFiles = @()
    foreach ($ext in $imageExts) {
        $allFiles += @(Get-ChildItem -Path $script:BackgroundDir -Filter $ext -File -ErrorAction SilentlyContinue)
    }

    if ($allFiles.Count -eq 0) {
        Write-Host '  No images in bg/ folder. Run "8sync bg search <keywords>" + "8sync bg set <id>" first.' -ForegroundColor DarkYellow
        return
    }

    $currentPath = ''
    if (Test-Path $script:CurrentBgLuaPath) {
        try {
            $raw = Get-Content -Raw $script:CurrentBgLuaPath -ErrorAction SilentlyContinue
            if ($raw -match '\[\[(.+)\]\]') { $currentPath = $Matches[1].Trim() }
        } catch {}
    }

    $candidates = @($allFiles | Where-Object { $_.FullName -ne $currentPath })
    if ($candidates.Count -eq 0) { $candidates = $allFiles }

    $pick = $candidates[(Get-Random -Maximum $candidates.Count)]
    Write-Host ('  Rotating to: {0}' -f $pick.Name) -ForegroundColor Cyan

    # Try to get brightness hint from cache if wallhaven id matches
    $brightnessHint = $null
    if ($pick.Name -match 'wallhaven-(.+)\.\w+$') {
        $whId = $Matches[1]
        $cache = Read-BgCache
        $entry = $cache | Where-Object { $_.id -eq $whId } | Select-Object -First 1
        if ($entry) { $brightnessHint = Get-WallpaperBrightnessHint -Entry $entry }
    }

    Write-CurrentBgLua -ImagePath $pick.FullName
    Write-CurrentStyleLua -BrightnessHint $brightnessHint
    Try-ReloadWezTerm

    $state = Read-BgRotateState
    Write-BgRotateState -Enabled $state.enabled -IntervalMinutes $state.intervalMinutes `
        -LastRotatedUtc ([datetime]::UtcNow.ToString('o'))
}

function Start-BgRotateCheck {
    $state = Read-BgRotateState
    if (-not $state.enabled) { return }

    $lastUtc = if ($state.lastRotatedUtc) { [datetime]$state.lastRotatedUtc } else { [datetime]::MinValue }
    $minutesSince = ([datetime]::UtcNow - $lastUtc).TotalMinutes
    if ($minutesSince -lt $state.intervalMinutes) { return }

    $engine = Get-ShellEngine
    if (-not (Test-Path $engine)) { return }

    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                   '-File', $PSCommandPath, '-Task', 'BgRotate')
    try {
        Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {}
}

function Invoke-BgRotateCommand {
    param([string[]]$Rest)

    $sub = if ($Rest -and $Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'status' }

    switch ($sub) {
        'on' {
            $mins = $script:BgRotateDefaultMinutes
            if ($Rest.Count -ge 2) {
                $parsed = 0
                if ([int]::TryParse($Rest[1], [ref]$parsed) -and $parsed -gt 0) { $mins = $parsed }
            }
            Write-BgRotateState -Enabled $true -IntervalMinutes $mins
            Write-Host ('  bg rotate: ON  every {0} min' -f $mins) -ForegroundColor Green
        }
        'off' {
            $state = Read-BgRotateState
            Write-BgRotateState -Enabled $false -IntervalMinutes $state.intervalMinutes
            Write-Host '  bg rotate: OFF' -ForegroundColor DarkGray
        }
        'now' {
            Invoke-BgRotateNow
        }
        'time' {
            if ($Rest.Count -lt 2) {
                $state = Read-BgRotateState
                Write-Host ('  Current interval: {0} min' -f $state.intervalMinutes) -ForegroundColor Cyan
                Write-Host '  Usage: 8sync bg rotate time <minutes>' -ForegroundColor DarkGray
                return
            }
            $parsed = 0
            if ([int]::TryParse($Rest[1], [ref]$parsed) -and $parsed -gt 0) {
                $state = Read-BgRotateState
                Write-BgRotateState -Enabled $state.enabled -IntervalMinutes $parsed
                Write-Host ('  Rotate interval set to {0} min' -f $parsed) -ForegroundColor Green
            } else {
                Write-Host '  Invalid minutes. Usage: 8sync bg rotate time <minutes>' -ForegroundColor DarkYellow
            }
        }
        'status' {
            $state = Read-BgRotateState
            $lastUtc = if ($state.lastRotatedUtc) { [datetime]$state.lastRotatedUtc } else { $null }
            $statusStr = if ($state.enabled) { 'ON' } else { 'OFF' }
            $color = if ($state.enabled) { 'Green' } else { 'DarkGray' }
            Write-Host ''
            Write-Host ('  bg rotate: {0}  every {1} min' -f $statusStr, $state.intervalMinutes) -ForegroundColor $color
            Write-Host ('  source: bg/ folder ({0} images)' -f @(Get-ChildItem -Path $script:BackgroundDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|bmp|gif|webp)$' }).Count) -ForegroundColor DarkGray
            Write-Host ('  last rotated: {0}' -f $(if ($lastUtc) { $lastUtc.ToString('u') } else { 'never' })) -ForegroundColor DarkGray
            Write-Host ''
        }
        default {
            Write-Host '  Usage: 8sync bg rotate [on [N] | off | now | time <min> | status]' -ForegroundColor DarkYellow
            Write-Host ('  Default interval: {0} min' -f $script:BgRotateDefaultMinutes) -ForegroundColor DarkGray
        }
    }
}

function Invoke-BgClearCache {
    if (-not (Test-Path $script:BgCachePath)) {
        Write-Host '  Search cache is already empty.' -ForegroundColor DarkGray
        return
    }
    try {
        Remove-Item -Path $script:BgCachePath -Force -ErrorAction Stop
        Write-Host '  Search cache cleared.' -ForegroundColor Green
    } catch {
        Write-Warning "Failed to clear cache: $_"
    }
}

function Invoke-BgList {
    Ensure-BackgroundDir
    $files = Get-ChildItem -Path $script:BackgroundDir -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending
    if (-not $files -or $files.Count -eq 0) {
        Write-Host '  No downloaded images in bg/ folder.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host ("  {0} downloaded image(s) in bg/" -f $files.Count) -ForegroundColor Cyan
    Write-Host ''
    $idx = 1
    foreach ($f in $files) {
        $sizeKB = [math]::Round($f.Length / 1024, 1)
        $date = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        $marker = ''
        # Check if this is the currently active wallpaper
        if (Test-Path $script:CurrentBgLuaPath) {
            try {
                $raw = Get-Content -Raw $script:CurrentBgLuaPath -ErrorAction SilentlyContinue
                if ($raw -match '\[\[(.+)\]\]') {
                    $currentPath = $Matches[1].Trim().Replace('\\\\', '\')
                    if ($currentPath -eq $f.FullName) { $marker = ' *' }
                }
            } catch {}
        }
        $color = if ($marker) { 'Green' } else { 'White' }
        Write-Host ("  {0,3}. {1,-45} {2,8} KB  {3}{4}" -f $idx, $f.Name, $sizeKB, $date, $marker) -ForegroundColor $color
        $idx++
    }
    Write-Host ''
    if ($files | Where-Object { $_.Name -match '^wallhaven-' }) {
        Write-Host '  Preview: https://wallhaven.cc/w/<id>  (id = number after "wallhaven-")' -ForegroundColor DarkGray
    }
    Write-Host '  * = currently active wallpaper' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-BgRemove {
    param([string[]]$Rest)

    Ensure-BackgroundDir

    if (-not $Rest -or $Rest.Count -eq 0) {
        Write-Host '  Usage: 8sync bg remove <filename|id|all>' -ForegroundColor DarkYellow
        Write-Host '  Examples:' -ForegroundColor DarkGray
        Write-Host '    8sync bg remove wallhaven-abc123.jpg' -ForegroundColor DarkGray
        Write-Host '    8sync bg remove abc123' -ForegroundColor DarkGray
        Write-Host '    8sync bg remove all' -ForegroundColor DarkGray
        return
    }

    $target = $Rest[0]

    if ($target -eq 'all') {
        $files = Get-ChildItem -Path $script:BackgroundDir -File -ErrorAction SilentlyContinue
        if (-not $files -or $files.Count -eq 0) {
            Write-Host '  No images to remove.' -ForegroundColor DarkGray
            return
        }
        $count = $files.Count
        $files | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host ("  Removed {0} image(s) from bg/." -f $count) -ForegroundColor Green
        return
    }

    # Try exact filename match first
    $filePath = Join-Path $script:BackgroundDir $target
    if (Test-Path $filePath) {
        Remove-Item -Path $filePath -Force
        Write-Host ("  Removed: {0}" -f $target) -ForegroundColor Green
        return
    }

    # Try as wallhaven id (wallhaven-<id>.jpg)
    $idPath = Join-Path $script:BackgroundDir ("wallhaven-{0}.jpg" -f $target)
    if (Test-Path $idPath) {
        Remove-Item -Path $idPath -Force
        Write-Host ("  Removed: wallhaven-{0}.jpg" -f $target) -ForegroundColor Green
        return
    }

    # Try partial filename match
    $matches = Get-ChildItem -Path $script:BackgroundDir -File -Filter "*$target*" -ErrorAction SilentlyContinue
    if ($matches -and $matches.Count -eq 1) {
        Remove-Item -Path $matches[0].FullName -Force
        Write-Host ("  Removed: {0}" -f $matches[0].Name) -ForegroundColor Green
        return
    }
    if ($matches -and $matches.Count -gt 1) {
        Write-Host ("  Multiple matches for '{0}':" -f $target) -ForegroundColor DarkYellow
        $matches | ForEach-Object { Write-Host ("    {0}" -f $_.Name) -ForegroundColor White }
        Write-Host '  Please specify the exact filename.' -ForegroundColor DarkYellow
        return
    }

    Write-Host ("  Not found: {0}" -f $target) -ForegroundColor DarkYellow
}

function Invoke-BgCommand {
    param([string[]]$Rest)

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-BgHelp
        return
    }

    $sub = $Rest[0].ToLowerInvariant()
    switch ($sub) {
        'help'   { Show-BgHelp }
        'search' {
            if ($Rest.Count -lt 2) {
                Write-Host 'Usage: 8sync bg search <keywords>' -ForegroundColor DarkYellow
                return
            }
            $keywords = ($Rest | Select-Object -Skip 1) -join ' '
            Invoke-BgSearch -Keywords $keywords
        }
        'pick'   { Invoke-BgPick }
        'set'    {
            if ($Rest.Count -lt 2) {
                Write-Host 'Usage: 8sync bg set <id|path|url>' -ForegroundColor DarkYellow
                return
            }
            $value = ($Rest | Select-Object -Skip 1) -join ' '
            Invoke-BgSet -Value $value
        }
        'open'   {
            if ($Rest.Count -lt 2) {
                Write-Host 'Usage: 8sync bg open <id>' -ForegroundColor DarkYellow
                return
            }
            Invoke-BgOpen -Id $Rest[1]
        }
        'rotate' { Invoke-BgRotateCommand -Rest ($Rest | Select-Object -Skip 1) }
        'clear'  {
            if ($Rest.Count -ge 2 -and $Rest[1].ToLowerInvariant() -eq 'cache') {
                Invoke-BgClearCache
            } else {
                Write-Host 'Usage: 8sync bg clear cache' -ForegroundColor DarkYellow
            }
        }
        'list'   { Invoke-BgList }
        'remove' { Invoke-BgRemove -Rest ($Rest | Select-Object -Skip 1) }
        default  { Show-BgHelp }
    }
}

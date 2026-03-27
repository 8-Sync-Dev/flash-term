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

function Normalize-YandereEntry {
    param([Parameter(Mandatory)] [object]$Item)

    $tagList = @()
    if ($Item.tags) {
        $tagList = ($Item.tags -split '\s+') | Where-Object { $_ -and $_ -notmatch '^(rating|score|width|height):' } | Select-Object -First 8
    }

    return [pscustomobject]@{
        id         = [string]$Item.id
        resolution = "{0}x{1}" -f $Item.width, $Item.height
        ratio      = if ($Item.height -gt 0) { [math]::Round($Item.width / $Item.height, 2) } else { 0 }
        page       = "https://yande.re/post/show/{0}" -f $Item.id
        short      = "https://yande.re/post/show/{0}" -f $Item.id
        preview    = $Item.preview_url
        file       = $Item.file_url
        colors     = @()
        tags       = $tagList
        source     = 'yandere'
        queriedUtc = [datetime]::UtcNow.ToString('o')
    }
}

function Search-Yandere {
    param(
        [Parameter(Mandatory)] [string]$Keywords,
        [int]$Limit = 24
    )

    $tagParts = @($Keywords -split '\s+')
    $tagParts += 'width:3840..'
    $tagParts += 'rating:safe'
    $tagParts += 'order:score'
    $tags = ($tagParts | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '+'
    $uri = "https://yande.re/post.json?tags=$tags&limit=$Limit"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 20
    } catch {
        Write-Warning 'yande.re request failed. Check network access and try again.'
        return @()
    }

    if (-not $response -or $response.Count -eq 0) {
        return @()
    }

    $items = @()
    foreach ($entry in $response) {
        $items += Normalize-YandereEntry -Item $entry
    }
    return $items
}

function Normalize-SafebooruEntry {
    param([Parameter(Mandatory)] [object]$Item)

    $tagList = @()
    if ($Item.tags) {
        $tagList = ($Item.tags -split '\s+') | Where-Object { $_ } | Select-Object -First 8
    }

    $imgUrl = "https://safebooru.org/images/{0}/{1}" -f $Item.directory, $Item.image

    return [pscustomobject]@{
        id         = [string]$Item.id
        resolution = "{0}x{1}" -f $Item.width, $Item.height
        ratio      = if ($Item.height -gt 0) { [math]::Round($Item.width / $Item.height, 2) } else { 0 }
        page       = "https://safebooru.org/index.php?page=post&s=view&id={0}" -f $Item.id
        short      = "https://safebooru.org/index.php?page=post&s=view&id={0}" -f $Item.id
        preview    = "https://safebooru.org/thumbnails/{0}/thumbnail_{1}" -f $Item.directory, $Item.image
        file       = $imgUrl
        colors     = @()
        tags       = $tagList
        source     = 'safebooru'
        queriedUtc = [datetime]::UtcNow.ToString('o')
    }
}

function Search-Safebooru {
    param(
        [Parameter(Mandatory)] [string]$Keywords,
        [int]$Limit = 24
    )

    $tagParts = @($Keywords -split '\s+')
    $tagParts += 'wallpaper'
    $tagParts += 'highres'
    $tags = ($tagParts | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '+'
    $uri = "https://safebooru.org/index.php?page=dapi&s=post&q=index&json=1&tags=$tags&limit=$Limit"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 20
    } catch {
        Write-Warning 'Safebooru request failed. Check network access and try again.'
        return @()
    }

    if (-not $response -or $response.Count -eq 0) {
        return @()
    }

    $items = @()
    foreach ($entry in $response) {
        $items += Normalize-SafebooruEntry -Item $entry
    }
    return $items
}

function Show-BgHelp {
    Write-Host ''
    Write-Host 'Background commands:' -ForegroundColor Yellow
    Write-Host '  8sync bg help'
    Write-Host '  8sync bg search <keywords>                    Search wallhaven (default)'
    Write-Host '  8sync bg search --yandere <keywords>          Search yande.re (4K+ anime)'
    Write-Host '  8sync bg search --safebooru <keywords>        Search safebooru (SFW anime)'
    Write-Host '  8sync bg search --all <keywords>              Search all sources'
    Write-Host '  8sync bg pick                                 fzf pick from cache'
    Write-Host '  8sync bg set <id|path|url>'
    Write-Host '  8sync bg open <id>'
    Write-Host ('  8sync bg rotate [on [N] | off | now | time <min> | status]  (default: {0} min)' -f $script:BgRotateDefaultMinutes)
    Write-Host '  8sync bg list                                 List images with preview'
    Write-Host '  8sync bg clear cache                          Clear search cache'
    Write-Host '  8sync bg remove <filename|id|all>             Remove downloaded images'
    Write-Host ''
    Write-Host '  Sources: wallhaven.cc (default) | yande.re (4K+ anime) | safebooru (SFW)' -ForegroundColor DarkGray
    Write-Host '  Rotate picks random images from bg/ folder.' -ForegroundColor DarkGray
    Write-Host '  List uses wezterm imgcat for inline preview if available.' -ForegroundColor DarkGray
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

    # Parse source flags from keywords
    $source = 'wallhaven'
    $cleanKeywords = $Keywords
    if ($Keywords -match '^--yandere\s+') {
        $source = 'yandere'
        $cleanKeywords = $Keywords -replace '^--yandere\s+', ''
    } elseif ($Keywords -match '^--safebooru\s+') {
        $source = 'safebooru'
        $cleanKeywords = $Keywords -replace '^--safebooru\s+', ''
    } elseif ($Keywords -match '^--all\s+') {
        $source = 'all'
        $cleanKeywords = $Keywords -replace '^--all\s+', ''
    }

    if (-not $cleanKeywords.Trim()) {
        Write-Host 'Usage: 8sync bg search [--yandere|--safebooru|--all] <keywords>' -ForegroundColor DarkYellow
        return
    }

    $allResults = @()

    switch ($source) {
        'wallhaven' {
            Write-Host '  Searching wallhaven.cc ...' -ForegroundColor DarkGray
            $allResults = @(Search-Wallhaven -Keywords $cleanKeywords)
        }
        'yandere' {
            Write-Host '  Searching yande.re ...' -ForegroundColor DarkGray
            $allResults = @(Search-Yandere -Keywords $cleanKeywords)
        }
        'safebooru' {
            Write-Host '  Searching safebooru.org ...' -ForegroundColor DarkGray
            $allResults = @(Search-Safebooru -Keywords $cleanKeywords)
        }
        'all' {
            Write-Host '  Searching wallhaven.cc ...' -ForegroundColor DarkGray
            $wh = @(Search-Wallhaven -Keywords $cleanKeywords)
            Write-Host ("    wallhaven: {0} results" -f $wh.Count) -ForegroundColor DarkGray
            Write-Host '  Searching yande.re ...' -ForegroundColor DarkGray
            $yr = @(Search-Yandere -Keywords $cleanKeywords)
            Write-Host ("    yande.re: {0} results" -f $yr.Count) -ForegroundColor DarkGray
            Write-Host '  Searching safebooru.org ...' -ForegroundColor DarkGray
            $sb = @(Search-Safebooru -Keywords $cleanKeywords)
            Write-Host ("    safebooru: {0} results" -f $sb.Count) -ForegroundColor DarkGray
            $allResults = @($wh) + @($yr) + @($sb)
        }
    }

    if (-not $allResults -or $allResults.Count -eq 0) {
        Write-Host '  No results found.' -ForegroundColor DarkYellow
        return
    }

    Write-BgCache -Items $allResults
    $sourceLabel = if ($source -eq 'all') { 'all sources' } else { $source }
    Write-Host ("  Saved {0} results from {1} to cache." -f $allResults.Count, $sourceLabel) -ForegroundColor Green
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

    # Build lines: id, resolution, source, tags, page
    $lines = $cache | ForEach-Object {
        $src = if ($_.source) { $_.source } else { 'wallhaven' }
        "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.id, $_.resolution, $src, ($_.tags -join ','), $_.page
    }

    # fzf with text-only preview (imgcat escape sequences break fzf preview pane)
    $selected = $lines | fzf --delimiter "`t" --with-nth 1,2,3 --prompt='BG> ' --height=60% --layout=reverse --border --preview "echo {4}" --preview-window=down:3:wrap
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
            $src = if ($entry.source) { $entry.source } else { 'wallhaven' }
            $ext = '.jpg'
            if ($entry.file -match '\.(\w+)$') { $ext = '.' + $Matches[1] }
            $fileName = ("{0}-{1}{2}" -f $src, $entry.id, $ext)
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

    Write-CurrentBgLua -Path $pick.FullName
    Write-CurrentStyleLua -BgHint $brightnessHint
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
    param([string[]]$Rest)

    Ensure-BackgroundDir
    $files = Get-ChildItem -Path $script:BackgroundDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(jpg|jpeg|png|bmp|gif|webp)$' } |
        Sort-Object -Property LastWriteTime -Descending
    if (-not $files -or $files.Count -eq 0) {
        Write-Host '  No downloaded images in bg/ folder.' -ForegroundColor DarkGray
        return
    }

    $showPreview = ($Rest -and $Rest -contains '--preview')
    $hasImgcat = Test-CommandExists 'wezterm'

    # Read current wallpaper path once
    $currentPath = ''
    if (Test-Path $script:CurrentBgLuaPath) {
        try {
            $raw = Get-Content -Raw $script:CurrentBgLuaPath -ErrorAction SilentlyContinue
            if ($raw -match '\[\[(.+)\]\]') {
                $currentPath = $Matches[1].Trim().Replace('\\\\', '\')
            }
        } catch {}
    }

    Write-Host ''
    Write-Host ("  {0} downloaded image(s) in bg/" -f $files.Count) -ForegroundColor Cyan
    Write-Host ''
    $idx = 1
    foreach ($f in $files) {
        $sizeKB = [math]::Round($f.Length / 1024, 1)
        $date = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        $marker = ''
        if ($currentPath -eq $f.FullName) { $marker = ' *' }
        $color = if ($marker) { 'Green' } else { 'White' }

        # Build source-specific page link
        $pageLink = ''
        if ($f.Name -match '^wallhaven-(.+)\.\w+$') {
            $pageLink = "https://wallhaven.cc/w/{0}" -f $Matches[1]
        } elseif ($f.Name -match '^yandere-(\d+)\.\w+$') {
            $pageLink = "https://yande.re/post/show/{0}" -f $Matches[1]
        } elseif ($f.Name -match '^safebooru-(\d+)\.\w+$') {
            $pageLink = "https://safebooru.org/index.php?page=post&s=view&id={0}" -f $Matches[1]
        }

        Write-Host ("  {0,3}. {1,-45} {2,8} KB  {3}{4}" -f $idx, $f.Name, $sizeKB, $date, $marker) -ForegroundColor $color
        if ($pageLink) {
            Write-Host ("       {0}" -f $pageLink) -ForegroundColor DarkGray
        }

        # Show inline thumbnail preview if --preview flag or small enough set
        if ($showPreview -and $hasImgcat) {
            try {
                & wezterm imgcat --width 40 $f.FullName 2>$null
            } catch {}
        }
        $idx++
    }
    Write-Host ''
    if (-not $showPreview -and $hasImgcat) {
        Write-Host '  Tip: 8sync bg list --preview   to show inline image thumbnails' -ForegroundColor DarkGray
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

    # Try as source-id pattern (wallhaven-<id>.*, yandere-<id>.*, safebooru-<id>.*)
    foreach ($prefix in @('wallhaven', 'yandere', 'safebooru')) {
        $idMatches = Get-ChildItem -Path $script:BackgroundDir -Filter "$prefix-$target.*" -File -ErrorAction SilentlyContinue
        if ($idMatches -and $idMatches.Count -gt 0) {
            $idMatches | Remove-Item -Force
            Write-Host ("  Removed: {0}" -f $idMatches[0].Name) -ForegroundColor Green
            return
        }
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
        'list'   { Invoke-BgList -Rest ($Rest | Select-Object -Skip 1) }
        'remove' { Invoke-BgRemove -Rest ($Rest | Select-Object -Skip 1) }
        default  { Show-BgHelp }
    }
}

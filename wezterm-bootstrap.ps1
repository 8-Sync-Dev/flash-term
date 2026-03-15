[CmdletBinding()]
param(
    [ValidateSet('Shell', 'Hint', 'Status', 'SyncQuiet', 'Sync')]
    [string]$Task = 'Shell'
)

$ErrorActionPreference = 'Continue'

$script:ToolPackages = [ordered]@{
    fzf       = 'fzf'
    zoxide    = 'zoxide'
    rg        = 'ripgrep'
    fd        = 'fd'
    bat       = 'bat'
    eza       = 'eza'
    starship  = 'starship'
    hx        = 'helix'
    yazi      = 'yazi'
    lazygit   = 'lazygit'
    delta     = 'delta'
    tokei     = 'tokei'
    hyperfine = 'hyperfine'
    dust      = 'dust'
    procs     = 'procs'
    btm       = 'bottom'
    less      = 'less'
}

$script:StateDir = Join-Path $PSScriptRoot '.state'
$script:StatePath = Join-Path $script:StateDir 'tool-state.json'
$script:SyncLockPath = Join-Path $script:StateDir 'sync.lock'
$script:SyncIntervalHours = 72
$script:BgCacheLimit = 50
$script:BgCachePath = Join-Path $script:StateDir 'bg-cache.json'
$script:BackgroundDir = Join-Path $PSScriptRoot 'bg'
$script:CurrentBgLuaPath = Join-Path $PSScriptRoot 'current-bg.lua'

$script:HelixConfigDir = Join-Path $env:APPDATA 'helix'
$script:HelixConfigPath = Join-Path $script:HelixConfigDir 'config.toml'
$script:CurrentOpacityPath = Join-Path $PSScriptRoot 'current-opacity.lua'
$script:DefaultOpacity = 0.72
$script:OpacityStep = 0.05

$script:LangServers = [ordered]@{
    'python'     = @('python', 'pyright')
    'typescript' = @('nodejs')
    'rust'       = @('rust', 'rust-analyzer')
    'go'         = @('go', 'gopls')
    'lua'        = @('lua-language-server')
    'c-cpp'      = @('llvm')
    'zig'        = @('zig', 'zls')
    'toml'       = @('taplo')
    'markdown'   = @('marksman')
    'java'       = @('openjdk')
    'csharp'     = @('dotnet-sdk')
}

function Ensure-PreferredPaths {
    $pathsToAdd = @(
        (Join-Path $HOME 'scoop\shims'),
        (Join-Path $HOME '.local\bin')
    )

    foreach ($pathItem in $pathsToAdd) {
        if ((Test-Path $pathItem) -and ($env:PATH -notlike "*$pathItem*")) {
            $env:PATH = "$pathItem;$env:PATH"
        }
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory)] [string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ScoopCommand {
    $command = Get-Command scoop -ErrorAction SilentlyContinue
    if ($command) {
        return $command
    }

    foreach ($candidate in @(
        (Join-Path $HOME 'scoop\shims\scoop.cmd'),
        (Join-Path $HOME 'scoop\shims\scoop.ps1')
    )) {
        if (Test-Path $candidate) {
            return [pscustomobject]@{ Source = $candidate }
        }
    }

    return $null
}

function Get-CommandSummary {
    param([Parameter(Mandatory)] [string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            Command = $Name
            State   = 'missing'
            Source  = ''
        }
    }

    return [pscustomobject]@{
        Command = $Name
        State   = 'ok'
        Source  = $command.Source
    }
}

function Get-ManagedToolStatus {
    foreach ($tool in $script:ToolPackages.Keys) {
        Get-CommandSummary -Name $tool
    }
}

function Get-MissingPackages {
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($pair in $script:ToolPackages.GetEnumerator()) {
        if (-not (Test-CommandExists $pair.Key)) {
            $missing.Add($pair.Value)
        }
    }
    return $missing
}

function Ensure-StateDir {
    if (-not (Test-Path $script:StateDir)) {
        $null = New-Item -Path $script:StateDir -ItemType Directory -Force
    }
}

function Read-State {
    Ensure-StateDir
    if (-not (Test-Path $script:StatePath)) {
        return [pscustomobject]@{
            lastSyncUtc = $null
        }
    }

    try {
        return Get-Content -Raw $script:StatePath | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            lastSyncUtc = $null
        }
    }
}

function Write-State {
    param([datetime]$LastSyncUtc)

    Ensure-StateDir
    $payload = [pscustomobject]@{
        lastSyncUtc = $LastSyncUtc.ToString('o')
    }
    $payload | ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8
}

function Get-ShellEngine {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    foreach ($candidate in @(
        (Join-Path $HOME 'scoop\shims\pwsh.exe'),
        (Join-Path $HOME 'scoop\apps\powershell\current\pwsh.exe')
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($powershell) {
        return $powershell.Source
    }

    $fallbackPath = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path $fallbackPath) {
        return $fallbackPath
    }

    return 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
}

function Show-8SyncHint {
    $missing = Get-MissingPackages
    $missingText = if ($missing.Count -gt 0) { ($missing -join ', ') } else { 'none' }

    Write-Host ''
    Write-Host '  8sync - WezTerm Shell Toolkit' -ForegroundColor Cyan
    Write-Host ('  Missing tools: {0}' -f $missingText) -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  COMMANDS' -ForegroundColor Yellow
    Write-Host '  8sync help' -ForegroundColor White -NoNewline
    Write-Host '                  Show this help' -ForegroundColor DarkGray
    Write-Host '  8sync status' -ForegroundColor White -NoNewline
    Write-Host '                Show installed tools and last sync time' -ForegroundColor DarkGray
    Write-Host '  8sync sync' -ForegroundColor White -NoNewline
    Write-Host '                  Install missing tools + update all via scoop' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  BACKGROUND WALLPAPER' -ForegroundColor Yellow
    Write-Host '  8sync bg search <keywords>' -ForegroundColor White -NoNewline
    Write-Host '  Search Wallhaven for wallpapers' -ForegroundColor DarkGray
    Write-Host '  8sync bg pick' -ForegroundColor White -NoNewline
    Write-Host '               Pick from cached results with fzf' -ForegroundColor DarkGray
    Write-Host '  8sync bg set <id|path|url>' -ForegroundColor White -NoNewline
    Write-Host '   Set wallpaper by cache id, local path, or URL' -ForegroundColor DarkGray
    Write-Host '  8sync bg open <id>' -ForegroundColor White -NoNewline
    Write-Host '          Open wallpaper page in browser' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  FILE & NAVIGATION' -ForegroundColor Yellow
    Write-Host '  ll' -ForegroundColor White -NoNewline
    Write-Host '                          List files with icons (eza -lah)' -ForegroundColor DarkGray
    Write-Host '  lt' -ForegroundColor White -NoNewline
    Write-Host '                          Tree view 2 levels (eza --tree)' -ForegroundColor DarkGray
    Write-Host '  y' -ForegroundColor White -NoNewline
    Write-Host '                           File manager with preview (yazi)' -ForegroundColor DarkGray
    Write-Host '  catn <file>' -ForegroundColor White -NoNewline
    Write-Host '                 View file with syntax highlight (bat)' -ForegroundColor DarkGray
    Write-Host '  ff <pattern>' -ForegroundColor White -NoNewline
    Write-Host '                Find files by name (rg --files)' -ForegroundColor DarkGray
    Write-Host '  cdi <query>' -ForegroundColor White -NoNewline
    Write-Host '                 Jump to directory (zoxide)' -ForegroundColor DarkGray
    Write-Host '  mkcd <path>' -ForegroundColor White -NoNewline
    Write-Host '                 Create directory and cd into it' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  EDITING & GIT' -ForegroundColor Yellow
    Write-Host '  e <file>' -ForegroundColor White -NoNewline
    Write-Host '                    Edit file in terminal (helix, LSP built-in)' -ForegroundColor DarkGray
    Write-Host '  lg' -ForegroundColor White -NoNewline
    Write-Host '                          Git TUI - stage, commit, diff (lazygit)' -ForegroundColor DarkGray
    Write-Host '  git diff' -ForegroundColor White -NoNewline
    Write-Host '                    Auto syntax-highlighted diffs (delta)' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  SYSTEM & ANALYSIS' -ForegroundColor Yellow
    Write-Host '  top' -ForegroundColor White -NoNewline
    Write-Host '                         System monitor TUI (bottom)' -ForegroundColor DarkGray
    Write-Host '  pss <query>' -ForegroundColor White -NoNewline
    Write-Host '                 Process viewer with search (procs)' -ForegroundColor DarkGray
    Write-Host '  du <path>' -ForegroundColor White -NoNewline
    Write-Host '                   Disk usage visualizer (dust)' -ForegroundColor DarkGray
    Write-Host '  tokei' -ForegroundColor White -NoNewline
    Write-Host '                       Count lines of code by language' -ForegroundColor DarkGray
    Write-Host '  hyperfine <cmd>' -ForegroundColor White -NoNewline
    Write-Host '             Benchmark command execution time' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  HELIX EDITOR' -ForegroundColor Yellow
    Write-Host '  8sync hx lang [name]' -ForegroundColor White -NoNewline
    Write-Host '        Install language toolchain (fzf picker)' -ForegroundColor DarkGray
    Write-Host '  8sync hx wrap' -ForegroundColor White -NoNewline
    Write-Host '                 Toggle soft word-wrap' -ForegroundColor DarkGray
    Write-Host '  8sync hx opacity <+|-|val>' -ForegroundColor White -NoNewline
    Write-Host '    Adjust background transparency' -ForegroundColor DarkGray
    Write-Host '  8sync hx theme [name]' -ForegroundColor White -NoNewline
    Write-Host '       Pick color theme (fzf picker)' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  KEYBINDINGS' -ForegroundColor Yellow
    Write-Host '  Ctrl+r' -ForegroundColor White -NoNewline
    Write-Host '                      Fuzzy search command history (fzf)' -ForegroundColor DarkGray
    Write-Host '  Alt+c' -ForegroundColor White -NoNewline
    Write-Host '                       Jump to directory (zoxide interactive)' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  EXAMPLES' -ForegroundColor Yellow
    Write-Host '  8sync sync' -ForegroundColor DarkCyan -NoNewline
    Write-Host '                  # install/update all managed tools' -ForegroundColor DarkGray
    Write-Host '  e ~/.config/wezterm/wezterm.lua' -ForegroundColor DarkCyan -NoNewline
    Write-Host '           # edit config in helix' -ForegroundColor DarkGray
    Write-Host '  lg' -ForegroundColor DarkCyan -NoNewline
    Write-Host '                          # open lazygit in current repo' -ForegroundColor DarkGray
    Write-Host '  y ~/projects' -ForegroundColor DarkCyan -NoNewline
    Write-Host '                # browse files with preview' -ForegroundColor DarkGray
    Write-Host '  tokei src/' -ForegroundColor DarkCyan -NoNewline
    Write-Host '                  # count code lines in src/' -ForegroundColor DarkGray
    Write-Host '  hyperfine "fd .rs"' -ForegroundColor DarkCyan -NoNewline
    Write-Host '          # benchmark a command' -ForegroundColor DarkGray
    Write-Host '  8sync bg search anime' -ForegroundColor DarkCyan -NoNewline
    Write-Host '       # find wallpapers on Wallhaven' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-8SyncStatus {
    $state = Read-State
    $lastSync = if ($state.lastSyncUtc) { [datetime]$state.lastSyncUtc } else { $null }

    Write-Host ''
    Write-Host 'Managed tool status' -ForegroundColor Cyan
    Get-ManagedToolStatus | Format-Table -AutoSize
    Write-Host ''
    Write-Host ('Last sync UTC: {0}' -f ($(if ($lastSync) { $lastSync.ToString('u') } else { 'never' }))) -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ToolSync {
    param([switch]$Quiet)

    $scoop = Get-ScoopCommand
    if (-not $scoop) {
        if (-not $Quiet) {
            Write-Warning 'Scoop was not found. Install Scoop first, then run /8sync sync.'
        }
        return
    }

    Ensure-StateDir
    if (Test-Path $script:SyncLockPath) {
        if (-not $Quiet) {
            Write-Host 'A background sync is already running.' -ForegroundColor DarkYellow
        }
        return
    }

    Set-Content -Path $script:SyncLockPath -Value ([datetime]::UtcNow.ToString('o')) -Encoding ASCII
    try {
        $missingPackages = Get-MissingPackages
        if ($missingPackages.Count -gt 0) {
            if (-not $Quiet) {
                Write-Host ('Installing missing packages: {0}' -f ($missingPackages -join ', ')) -ForegroundColor Yellow
            }
            & $scoop.Source install @missingPackages | Out-Host
        }

        $allPackages = $script:ToolPackages.Values | Select-Object -Unique
        if (-not $Quiet) {
            Write-Host ('Updating managed packages: {0}' -f ($allPackages -join ', ')) -ForegroundColor Yellow
        }
        & $scoop.Source update @allPackages | Out-Host

        Write-State -LastSyncUtc ([datetime]::UtcNow)
        if (-not $Quiet) {
            Write-Host 'Tool sync completed.' -ForegroundColor Green
        }
    } finally {
        Remove-Item $script:SyncLockPath -Force -ErrorAction SilentlyContinue
    }
}

function Start-AutoSync {
    $scoop = Get-ScoopCommand
    if (-not $scoop) {
        return
    }

    if (Test-Path $script:SyncLockPath) {
        try {
            $lockAge = ([datetime]::UtcNow - (Get-Item $script:SyncLockPath).LastWriteTimeUtc).TotalMinutes
            if ($lockAge -gt 30) {
                Remove-Item $script:SyncLockPath -Force -ErrorAction SilentlyContinue
            } else {
                return
            }
        } catch {
            return
        }
    }

    $state = Read-State
    $lastSyncUtc = if ($state.lastSyncUtc) { [datetime]$state.lastSyncUtc } else { $null }
    $missingPackages = Get-MissingPackages
    $shouldSync = $missingPackages.Count -gt 0

    if (-not $shouldSync -and $lastSyncUtc) {
        $hours = ([datetime]::UtcNow - $lastSyncUtc).TotalHours
        $shouldSync = $hours -ge $script:SyncIntervalHours
    } elseif (-not $lastSyncUtc) {
        $shouldSync = $true
    }

    if (-not $shouldSync) {
        return
    }

    $engine = Get-ShellEngine
    if (-not (Test-Path $engine)) {
        return
    }

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Task', 'SyncQuiet'
    )

    try {
        Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {
        # Silently ignore auto-sync failures
    }
}

function Set-HistoryExperience {
    if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
        return
    }

    try {
        Import-Module PSReadLine -ErrorAction Stop
    } catch {
        return
    }

    try {
        Set-PSReadLineOption -EditMode Windows -ErrorAction Stop
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
        Set-PSReadLineOption -BellStyle None -ErrorAction Stop
        Set-PSReadLineOption -HistoryNoDuplicates -ErrorAction Stop
        Set-PSReadLineOption -MaximumHistoryCount 20000 -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction Stop
        Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar -ErrorAction Stop
        Set-PSReadLineKeyHandler -Chord 'Alt+c' -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert('cdi ')
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        } -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction Stop
    } catch {
        # Silently ignore PSReadLine errors - console may not support all features
    }

    if (Test-CommandExists 'fzf') {
        try {
            Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
                $historyPath = (Get-PSReadLineOption).HistorySavePath
                if (-not (Test-Path $historyPath)) {
                    return
                }

                $history = Get-Content $historyPath -ErrorAction SilentlyContinue
                if (-not $history) {
                    return
                }

                [array]::Reverse($history)
                $selected = $history | fzf --height=45% --layout=reverse --border --prompt='History> ' --no-sort
                if ($selected) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
                }
            } -ErrorAction Stop
        } catch {
            # Ignore fzf handler errors
        }
    }
}

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

function Try-ReloadWezTerm {
    if (Test-CommandExists 'wezterm') {
        try {
            & wezterm cli reload | Out-Null
            Write-Host 'WezTerm config reloaded.' -ForegroundColor Green
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
        }
    }

    if (-not $finalPath) {
        Write-Host 'Failed to set background.' -ForegroundColor DarkYellow
        return
    }

    Write-CurrentBgLua -Path $finalPath
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
        default  { Show-BgHelp }
    }
}

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
        Write-Host 'fzf is missing. Run "8sync sync" or use "8sync hx theme <name>".' -ForegroundColor DarkYellow
        return
    }

    $current = Get-HelixThemeValue
    $selected = $themes | fzf --height=50% --layout=reverse --border --prompt='Theme> ' --query="$current"
    if ($selected) {
        Set-HelixThemeValue -Theme $selected
        Write-Host "Helix theme set to: $selected" -ForegroundColor Green
    }
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
        Write-Host 'Usage: 8sync hx opacity <+|-|0.0-1.0>' -ForegroundColor DarkGray
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
        Write-Host 'fzf is missing. Run "8sync sync" or use "8sync hx lang <name>".' -ForegroundColor DarkYellow
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
    Write-Host '  Helix editor commands:' -ForegroundColor Yellow
    Write-Host '  8sync hx help' -ForegroundColor White -NoNewline
    Write-Host '                  Show this help' -ForegroundColor DarkGray
    Write-Host '  8sync hx lang [name]' -ForegroundColor White -NoNewline
    Write-Host '           Install language toolchain via scoop (fzf)' -ForegroundColor DarkGray
    Write-Host '  8sync hx wrap' -ForegroundColor White -NoNewline
    Write-Host '                  Toggle soft word-wrap on/off' -ForegroundColor DarkGray
    Write-Host '  8sync hx opacity <+|-|val>' -ForegroundColor White -NoNewline
    Write-Host '     Adjust background transparency' -ForegroundColor DarkGray
    Write-Host '  8sync hx theme [name]' -ForegroundColor White -NoNewline
    Write-Host '          Pick Helix color theme (fzf)' -ForegroundColor DarkGray
    Write-Host ''
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
        'wrap'    { Invoke-HxWrap }
        'opacity' {
            $val = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
            Invoke-HxOpacity -Value $val
        }
        'theme'   {
            $name = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
            Invoke-HxTheme -ThemeName $name
        }
        default   { Show-HxHelp }
    }
}

function Set-ToolAliases {
    if (Test-CommandExists 'zoxide') {
        try {
            Invoke-Expression (& zoxide init powershell | Out-String)
        } catch {
            # Ignore zoxide init errors
        }
    }

    if (Test-CommandExists 'starship') {
        try {
            Invoke-Expression (& starship init powershell)
        } catch {
            # Ignore starship init errors
        }
    }

    if (Test-CommandExists 'eza') {
        function global:ll { eza --icons=always --group-directories-first -lah @args }
        function global:lt { eza --icons=always --group-directories-first -lah --tree --level=2 @args }
    } else {
        function global:ll { Get-ChildItem -Force @args }
    }

    if (Test-CommandExists 'bat') {
        function global:catn { bat --paging=never --style=plain @args }
    }

    if (Test-CommandExists 'rg') {
        function global:ff { rg --files @args }
    }

    if (Test-CommandExists 'zoxide') {
        Set-Alias -Name cdi -Value z -Scope Global -Force
    }

    if (Test-CommandExists 'delta') {
        $env:GIT_PAGER = 'delta'
    }

    if (Test-CommandExists 'yazi') {
        function global:y {
            $tmp = [System.IO.Path]::GetTempFileName()
            yazi --cwd-file="$tmp" @args
            $cwd = Get-Content $tmp -ErrorAction SilentlyContinue
            if ($cwd -and $cwd -ne $PWD.Path) {
                Set-Location $cwd
            }
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }

    if (Test-CommandExists 'lazygit') {
        Set-Alias -Name lg -Value lazygit -Scope Global -Force
    }

    if (Test-CommandExists 'hx') {
        Set-Alias -Name e -Value hx -Scope Global -Force
    }

    if (Test-CommandExists 'procs') {
        Set-Alias -Name pss -Value procs -Scope Global -Force
    }

    if (Test-CommandExists 'btm') {
        Set-Alias -Name top -Value btm -Scope Global -Force
    }

    if (Test-CommandExists 'dust') {
        Set-Alias -Name du -Value dust -Scope Global -Force
    }

    function global:mkcd {
        param([Parameter(Mandatory)] [string]$Path)
        $null = New-Item -ItemType Directory -Path $Path -Force
        Set-Location $Path
    }

    function global:Invoke-8Sync {
        param(
            [string]$Mode = 'help',
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$Rest
        )

        switch ($Mode.ToLowerInvariant()) {
            'help'   { Show-8SyncHint }
            'hint'   { Show-8SyncHint }
            'status' { Show-8SyncStatus }
            'sync'   { Invoke-ToolSync }
            'bg'     { Invoke-BgCommand -Rest $Rest }
            'hx'     { Invoke-HxCommand -Rest $Rest }
            default  { Show-8SyncHint }
        }
    }

    Set-Alias -Name '/8sync' -Value Invoke-8Sync -Scope Global -Force
    Set-Alias -Name '8sync' -Value Invoke-8Sync -Scope Global -Force
}

function Start-WezTermShell {
    Ensure-PreferredPaths
    $env:TERM_PROGRAM = 'WezTerm'
    if ($Host.UI -and $Host.UI.RawUI) {
        try {
            $Host.UI.RawUI.WindowTitle = 'WezTerm PowerShell'
        } catch {
            # Ignore if console doesn't support title setting
        }
    }
    Set-HistoryExperience
    Set-ToolAliases
    Start-AutoSync

    $missingPackages = Get-MissingPackages
    if ($missingPackages.Count -gt 0) {
        Write-Host ('[8sync] Missing tools: {0}. Run "8sync sync" to install.' -f ($missingPackages -join ', ')) -ForegroundColor DarkYellow
    }
}

Ensure-PreferredPaths

try {
    switch ($Task) {
        'Hint' {
            Show-8SyncHint
            break
        }
        'Status' {
            Show-8SyncStatus
            break
        }
        'SyncQuiet' {
            Invoke-ToolSync -Quiet
            break
        }
        'Sync' {
            Invoke-ToolSync
            break
        }
        default {
            Start-WezTermShell
        }
    }
} catch {
    Write-Warning "Bootstrap error: $_"
}

$global:LASTEXITCODE = 0


#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Shell', 'Hint', 'Status', 'SyncQuiet', 'Sync', 'BgRotate')]
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
$script:MissingCachePath = Join-Path $script:StateDir 'missing-cache.json'
$script:MissingCacheTtlSeconds = 300   # 5 minutes
$script:SyncIntervalHours = 72
$script:BgCacheLimit = 50
$script:BgCachePath = Join-Path $script:StateDir 'bg-cache.json'
$script:BgRotatePath = Join-Path $script:StateDir 'bg-rotate.json'
$script:BgRotateDefaultMinutes = 30
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
    # Check cache first -- avoids 16x Get-Command on every tab open when tools are installed.
    # Cache is invalidated after MissingCacheTtlSeconds (default 5min) or when scoop runs.
    Ensure-StateDir
    if (Test-Path $script:MissingCachePath) {
        try {
            $cached = Get-Content -Raw $script:MissingCachePath | ConvertFrom-Json
            if ($cached -and $cached.generatedUtc) {
                $age = ([datetime]::UtcNow - [datetime]$cached.generatedUtc).TotalSeconds
                if ($age -lt $script:MissingCacheTtlSeconds) {
                    # Return cached list as Generic.List to match callers' .Count/.Add expectations
                    $list = New-Object System.Collections.Generic.List[string]
                    foreach ($item in $cached.missing) { $list.Add($item) }
                    return $list
                }
            }
        } catch {}
    }

    # Cache miss or expired -- do the real scan
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($pair in $script:ToolPackages.GetEnumerator()) {
        if (-not (Test-CommandExists $pair.Key)) {
            $missing.Add($pair.Value)
        }
    }

    # Persist result
    try {
        [pscustomobject]@{
            generatedUtc = [datetime]::UtcNow.ToString('o')
            missing      = @($missing)
        } | ConvertTo-Json | Set-Content -Path $script:MissingCachePath -Encoding UTF8
    } catch {}

    return $missing
}

function Clear-MissingCache {
    # Call after any install/update so next Get-MissingPackages re-scans
    Remove-Item $script:MissingCachePath -Force -ErrorAction SilentlyContinue
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

function Write-HintRow {
    param(
        [string]$Cmd,
        [string]$Desc,
        [int]$CmdWidth = 32,
        [ConsoleColor]$CmdColor = [ConsoleColor]::White,
        [ConsoleColor]$DescColor = [ConsoleColor]::DarkGray
    )
    $termWidth = try { $Host.UI.RawUI.WindowSize.Width } catch { 100 }
    if ($termWidth -lt 40) { $termWidth = 100 }
    $descMaxWidth = $termWidth - $CmdWidth - 2
    if ($descMaxWidth -lt 10) { $descMaxWidth = 40 }

    $paddedCmd = ('  ' + $Cmd).PadRight($CmdWidth)
    Write-Host $paddedCmd -ForegroundColor $CmdColor -NoNewline

    # word-wrap description if too long
    if ($Desc.Length -le $descMaxWidth) {
        Write-Host $Desc -ForegroundColor $DescColor
    } else {
        $words = $Desc -split ' '
        $line = ''
        $firstLine = $true
        foreach ($word in $words) {
            if (($line + ' ' + $word).TrimStart().Length -gt $descMaxWidth) {
                if ($firstLine) {
                    Write-Host $line.TrimStart() -ForegroundColor $DescColor
                    $firstLine = $false
                } else {
                    Write-Host ((' ' * $CmdWidth) + $line.TrimStart()) -ForegroundColor $DescColor
                }
                $line = $word
            } else {
                $line = ($line + ' ' + $word).TrimStart()
            }
        }
        if ($line) {
            if ($firstLine) {
                Write-Host $line -ForegroundColor $DescColor
            } else {
                Write-Host ((' ' * $CmdWidth) + $line) -ForegroundColor $DescColor
            }
        }
    }
}

function Write-HintSection {
    param([string]$Title)
    Write-Host ''
    Write-Host ('  ' + $Title) -ForegroundColor Yellow
}

function Show-8SyncHint {
    $missing = Get-MissingPackages
    $missingText = if ($missing.Count -gt 0) { ($missing -join ', ') } else { 'none' }

    Write-Host ''
    Write-Host '  8sync  WezTerm Shell Toolkit' -ForegroundColor Cyan -NoNewline
    Write-Host ('  [missing: {0}]' -f $missingText) -ForegroundColor DarkGray

    Write-HintSection 'COMMANDS'
    Write-HintRow '8sync help'              'Show this help'
    Write-HintRow '8sync status'            'Installed tools + last sync time'
    Write-HintRow '8sync sync'              'Install missing tools + update all via scoop'
    Write-HintRow '8sync clean [--days N]'         'Deep clean: temp/cache/venv/RAM/disk (default: stale > 7 days)'
    Write-HintRow '8sync clean --projects [--all]' 'Stale git repo picker -- fzf multi-select to delete'
    Write-HintRow '8sync clean --deep'             'Report stale MCP/npm/pip/cargo/go dev artifacts'
    Write-HintRow '8sync clean --scan'             'Windows Defender quick scan + dev folder scan'

    Write-HintSection 'BACKGROUND'
    Write-HintRow '8sync bg search <kw>'         'Search Wallhaven for 4K wallpapers'
    Write-HintRow '8sync bg pick'                'Pick from cached results with fzf'
    Write-HintRow '8sync bg set <id|path>'       'Set wallpaper by cache id, local path, or URL'
    Write-HintRow '8sync bg open <id>'           'Open wallpaper page in browser'
    Write-HintRow '8sync bg rotate [on N|off]'   'Auto-rotate wallpaper every N min (default 30)'

    Write-HintSection 'HELIX EDITOR'
    Write-HintRow '8sync hx lang [name]'    'Install language toolchain via scoop (fzf picker)'
    Write-HintRow '8sync hx wrap'           'Toggle soft word-wrap on/off'
    Write-HintRow '8sync hx opacity <val>'  'Adjust background transparency: +  -  or 0.0-1.0'
    Write-HintRow '8sync hx theme [name]'   'Pick Helix color theme (fzf picker)'

    Write-HintSection 'FILE & NAVIGATION'
    Write-HintRow 'll'                      'List files with icons (eza -lah)'
    Write-HintRow 'lt'                      'Tree view 2 levels (eza --tree)'
    Write-HintRow 'y [path]'                'File manager with cd-on-exit (yazi)'
    Write-HintRow 'catn <file>'             'Syntax-highlighted view (bat)'
    Write-HintRow 'ff <pattern>'            'Find files by name (rg --files)'
    Write-HintRow 'cdi <query>'             'Jump to directory (zoxide)'
    Write-HintRow 'mkcd <path>'             'Create directory and cd into it'

    Write-HintSection 'EDITING & GIT'
    Write-HintRow 'e <file>'                'Open in Helix editor (LSP built-in)'
    Write-HintRow 'lg'                      'Git TUI: stage, commit, diff (lazygit)'
    Write-HintRow 'git diff'                'Auto syntax-highlighted diffs (delta)'

    Write-HintSection 'SYSTEM'
    Write-HintRow 'top'                     'System monitor TUI (bottom)'
    Write-HintRow 'pss <query>'             'Process viewer with search (procs)'
    Write-HintRow 'du [path]'               'Disk usage visualizer (dust)'
    Write-HintRow 'tokei [path]'            'Count lines of code by language'
    Write-HintRow 'hyperfine <cmd>'         'Benchmark command execution time'

    Write-HintSection 'KEYBINDINGS'
    Write-HintRow 'Ctrl+r'                  'Fuzzy search command history (fzf)'
    Write-HintRow 'Alt+c'                   'Jump to directory (zoxide interactive)'
    Write-Host ''
}

function Show-8SyncStatus {
    $state = Read-State
    $lastSync = if ($state.lastSyncUtc) { [datetime]$state.lastSyncUtc } else { $null }

    Write-Host ''
    Write-Host 'Managed tool status' -ForegroundColor Cyan
    Get-ManagedToolStatus | Format-Table -AutoSize
    Write-Host ('Last sync UTC: {0}' -f ($(if ($lastSync) { $lastSync.ToString('u') } else { 'never' }))) -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'Config disk usage' -ForegroundColor Cyan

    $configDir = $PSScriptRoot
    $diskEntries = @(
        @{ Label = '.state/';  Path = $script:StateDir }
        @{ Label = 'bg/';      Path = $script:BackgroundDir }
        @{ Label = 'fonts/';   Path = (Join-Path $configDir 'fonts') }
    )

    $totalBytes = [long]0
    foreach ($entry in $diskEntries) {
        if ([System.IO.Directory]::Exists($entry.Path)) {
            $sz = [long]0
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($entry.Path, '*', [System.IO.SearchOption]::AllDirectories)) {
                    try { $sz += [System.IO.FileInfo]::new($f).Length } catch {}
                }
            } catch {}
            $totalBytes += $sz
            Write-Host ('  {0,-12} {1}' -f $entry.Label, (Format-Bytes $sz)) -ForegroundColor DarkGray
        } else {
            Write-Host ('  {0,-12} --' -f $entry.Label) -ForegroundColor DarkGray
        }
    }
    Write-Host ('  {0,-12} {1}' -f 'total', (Format-Bytes $totalBytes)) -ForegroundColor DarkGray
    Write-Host ''

    $rotateSt = Read-BgRotateState
    $rotateStr = if ($rotateSt.enabled) { 'ON  every {0}min' -f $rotateSt.intervalMinutes } else { 'OFF' }
    $rotateColor = if ($rotateSt.enabled) { 'Green' } else { 'DarkGray' }
    Write-Host ('bg rotate: {0}' -f $rotateStr) -ForegroundColor $rotateColor
    Write-Host ''
}

function Ensure-ScoopBuckets {
    param(
        [Parameter(Mandatory)] [object]$Scoop,
        [string[]]$Buckets = @('extras')
    )

    try {
        $existing = & $Scoop.Source bucket list 2>$null | ForEach-Object { "$_".Trim() }
    } catch {
        $existing = @()
    }

    foreach ($bucket in $Buckets) {
        if ($existing -notcontains $bucket) {
            Write-Host ("Adding Scoop bucket: {0}" -f $bucket) -ForegroundColor Yellow
            try {
                & $Scoop.Source bucket add $bucket 2>&1 | Out-Host
            } catch {
                Write-Warning ("Failed to add bucket '{0}': {1}" -f $bucket, $_.Exception.Message)
            }
        }
    }
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
        # Ensure required buckets exist before install (lazygit lives in extras)
        Ensure-ScoopBuckets -Scoop $scoop -Buckets @('extras')

        $missingPackages = Get-MissingPackages
        if ($missingPackages.Count -gt 0) {
            if (-not $Quiet) {
                Write-Host ('Installing missing packages: {0}' -f ($missingPackages -join ', ')) -ForegroundColor Yellow
            }
            & $scoop.Source install @missingPackages | Out-Host

            # Refresh PATH so newly installed shims are visible to scoop update
            Ensure-PreferredPaths
        }

        # Only update packages that are now actually installed
        $installedPackages = $script:ToolPackages.GetEnumerator() |
            Where-Object { Test-CommandExists $_.Key } |
            ForEach-Object { $_.Value } |
            Select-Object -Unique

        if ($installedPackages.Count -gt 0) {
            if (-not $Quiet) {
                Write-Host ('Updating managed packages: {0}' -f ($installedPackages -join ', ')) -ForegroundColor Yellow
            }
            & $scoop.Source update @installedPackages | Out-Host
        } elseif (-not $Quiet) {
            Write-Host 'No installed packages to update.' -ForegroundColor DarkGray
        }

        Write-State -LastSyncUtc ([datetime]::UtcNow)
        Clear-MissingCache   # force re-scan on next tab open
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
    # PSReadLine is already loaded in PS 5.1+ by default; skip the slow
    # Get-Module -ListAvailable scan and just try to configure it directly.
    # If it isn't present the try/catch swallows the error silently.

    try {
        # Basic readline options -- fast path, no module scan needed
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
        # PSReadLine not available or console doesn't support all features -- silent
    }

    if (Test-CommandExists 'fzf') {
        try {
            Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
                $historyPath = (Get-PSReadLineOption).HistorySavePath
                if (-not (Test-Path $historyPath)) { return }
                $history = Get-Content $historyPath -ErrorAction SilentlyContinue
                if (-not $history) { return }
                [array]::Reverse($history)
                $selected = $history | fzf --height=45% --layout=reverse --border --prompt='History> ' --no-sort
                if ($selected) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
                }
            } -ErrorAction Stop
        } catch {}
    }
}

function Register-8SyncCompleter {
    # Tab / inline completion for: 8sync <mode> <subcommand>
    $completer = {
        param($wordToComplete, $commandAst, $cursorPosition)

        $tokens = $commandAst.CommandElements | ForEach-Object { $_.ToString() }
        $count  = $tokens.Count

        # top-level modes
        $modes = @('help','status','sync','clean','bg','hx')

        # subcommands per mode
        $subMap = @{
            bg = @('search','pick','set','open','rotate','help')
            hx = @('lang','wrap','opacity','theme','help')
            clean = @('help','--days','--dry-run','--projects','--all','--deep','--scan','--help')
        }

        if ($count -le 1) {
            # still typing the command name itself -- nothing to complete yet
            return
        }

        if ($count -eq 2) {
            # completing the mode argument
            $partial = $tokens[1]
            $modes | Where-Object { $_ -like "$partial*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            return
        }

        if ($count -ge 3) {
            $mode = $tokens[1].ToLowerInvariant()
            $partial = $tokens[$count - 1]
            if ($subMap.ContainsKey($mode)) {
                $subMap[$mode] | Where-Object { $_ -like "$partial*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
        }
    }

    try {
        Register-ArgumentCompleter -CommandName '8sync'  -ScriptBlock $completer -ErrorAction SilentlyContinue
        Register-ArgumentCompleter -CommandName '/8sync' -ScriptBlock $completer -ErrorAction SilentlyContinue
    } catch {}
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
    $cache = Read-BgCache
    if (-not $cache -or $cache.Count -eq 0) {
        Write-Host '  No cached wallpapers. Run "8sync bg search <keywords>" first.' -ForegroundColor DarkYellow
        return
    }

    $currentPath = ''
    if (Test-Path $script:CurrentBgLuaPath) {
        try {
            $raw = Get-Content -Raw $script:CurrentBgLuaPath -ErrorAction SilentlyContinue
            if ($raw -match '\[\[(.+)\]\]') { $currentPath = $Matches[1].Trim() }
        } catch {}
    }

    $candidates = @($cache | Where-Object {
        $fileName = 'wallhaven-{0}.jpg' -f $_.id
        $localPath = Join-Path $script:BackgroundDir $fileName
        $localPath -ne $currentPath
    })

    if ($candidates.Count -eq 0) { $candidates = @($cache) }

    $pick = $candidates[(Get-Random -Maximum $candidates.Count)]
    Write-Host ('  Rotating to: {0}' -f $pick.id) -ForegroundColor Cyan
    Invoke-BgSet -Value $pick.id

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
        'status' {
            $state = Read-BgRotateState
            $lastUtc = if ($state.lastRotatedUtc) { [datetime]$state.lastRotatedUtc } else { $null }
            $statusStr = if ($state.enabled) { 'ON' } else { 'OFF' }
            $color = if ($state.enabled) { 'Green' } else { 'DarkGray' }
            Write-Host ''
            Write-Host ('  bg rotate: {0}  every {1} min' -f $statusStr, $state.intervalMinutes) -ForegroundColor $color
            Write-Host ('  last rotated: {0}' -f $(if ($lastUtc) { $lastUtc.ToString('u') } else { 'never' })) -ForegroundColor DarkGray
            Write-Host ''
        }
        default {
            Write-Host '  Usage: 8sync bg rotate [on [N] | off | now | status]' -ForegroundColor DarkYellow
        }
    }
}

function Show-BgHelp {
    Write-Host ''
    Write-Host 'Background commands:' -ForegroundColor Yellow
    Write-Host '  8sync bg help'
    Write-Host '  8sync bg search <keywords>'
    Write-Host '  8sync bg pick'
    Write-Host '  8sync bg set <id|path|url>'
    Write-Host '  8sync bg open <id>'
    Write-Host '  8sync bg rotate [on [N] | off | now | status]'
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
        'rotate' { Invoke-BgRotateCommand -Rest ($Rest | Select-Object -Skip 1) }
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
    Write-HintSection 'HELIX EDITOR'
    Write-HintRow '8sync hx help'           'Show this help'
    Write-HintRow '8sync hx lang [name]'    'Install language toolchain via scoop (fzf picker)'
    Write-HintRow '8sync hx wrap'           'Toggle soft word-wrap on/off'
    Write-HintRow '8sync hx opacity <val>'  '+  -  or 0.0-1.0 -- adjust background transparency'
    Write-HintRow '8sync hx theme [name]'   'Pick Helix color theme (fzf picker)'
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  8sync clean -- deep system / RAM / venv cleaner
# ---------------------------------------------------------------------------

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:F2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:F1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:F0} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

# Spinner state -- shared across the clean session
$script:CleanSpinnerFrames = @('-','\\','|','/')
$script:CleanSpinnerIdx    = 0
$script:CleanTotalFreed    = [long]0
$script:CleanTotalFiles    = 0

# Spinner guard: only use \r-overwrite trick on a real interactive console.
# Extra checks beyond ConsoleHost:
#   - Width must be readable and sane (20..300) -- rules out SSH/tmux/redir
#   - Not output-redirected (pipe, file, capture)
#   - WindowSize must not throw (non-interactive hosts do)
$script:CleanIsConsole = $false
if ($Host.Name -eq 'ConsoleHost' -and
    -not [System.Console]::IsOutputRedirected -and
    -not [System.Console]::IsInputRedirected) {
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -ge 20 -and $w -le 300) {
            $script:CleanIsConsole = $true
        }
    } catch {}
}

function Get-SafeTermWidth {
    $w = 80
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch {}
    if ($w -lt 20 -or $w -gt 300) { $w = 80 }
    return $w
}

function Write-CleanSpinner {
    param([string]$Msg, [string]$Counter = '')
    if (-not $script:CleanIsConsole) { return }
    $frame = $script:CleanSpinnerFrames[$script:CleanSpinnerIdx % $script:CleanSpinnerFrames.Count]
    $script:CleanSpinnerIdx++
    $termWidth = Get-SafeTermWidth
    # Truncate long paths so line never wraps
    $maxMsg = $termWidth - 32
    if ($Msg.Length -gt $maxMsg -and $maxMsg -gt 8) { $Msg = '...' + $Msg.Substring($Msg.Length - ($maxMsg - 3)) }
    $line = ('  {0} {1}  {2}' -f $frame, $Msg, $Counter).PadRight($termWidth - 1)
    # Overwrite same line via \r -- stays on one line, no scroll
    [System.Console]::Write("`r" + $line)
}

function Clear-SpinnerLine {
    if (-not $script:CleanIsConsole) { return }
    $termWidth = Get-SafeTermWidth
    [System.Console]::Write("`r" + (' ' * ($termWidth - 1)) + "`r")
}

function Write-CleanResult {
    param([string]$Label, [int]$FileCount, [long]$Freed, [switch]$DryRun, [switch]$Skipped)
    Clear-SpinnerLine
    if ($Skipped) { return }   # path didn't exist -- print nothing
    $tag   = if ($DryRun) { ' ~' } else { '' }
    $fStr  = if ($Freed -gt 0) { Format-Bytes $Freed } else { '--' }
    $nStr  = if ($FileCount -gt 0) { ('{0} files' -f $FileCount) } else { '0 files' }
    # colour: green when freed something, dry-run yellow, zero gray
    $color = if ($Freed -gt 0 -and -not $DryRun) { 'Green' } elseif ($DryRun -and $Freed -gt 0) { 'DarkYellow' } else { 'DarkGray' }
    Write-Host ('  {0}{1}  {2}  {3}' -f $Label, $tag, $nStr, $fStr) -ForegroundColor $color
}

# Fast recursive file scan using .NET EnumerateFiles (5-10x faster than Get-ChildItem -Recurse)
function Invoke-CleanPath {
    param(
        [string]$Path,
        [string]$Label,
        [int]$StaleDays = 0,
        [switch]$DryRun,
        [switch]$Recursive
    )

    if (-not (Test-Path $Path)) {
        Write-CleanResult -Label $Label -FileCount 0 -Freed 0 -DryRun:$DryRun -Skipped
        return [long]0
    }

    $cutoff   = if ($StaleDays -gt 0) { (Get-Date).AddDays(-$StaleDays) } else { $null }
    $freed    = [long]0
    $count    = 0
    $spinFreq = 0   # throttle spinner updates

    # Show initial spinner immediately so user knows we started
    Write-CleanSpinner -Msg $Label -Counter 'scanning...'

    try {
        $searchOpt = if ($Recursive) {
            [System.IO.SearchOption]::AllDirectories
        } else {
            [System.IO.SearchOption]::TopDirectoryOnly
        }

        $files = [System.IO.Directory]::EnumerateFiles($Path, '*', $searchOpt)

        foreach ($filePath in $files) {
            # Throttle spinner: update every 500 files -- 1 Console.Write per 500 iterations
            $spinFreq++
            if ($spinFreq -ge 500) {
                $spinFreq = 0
                Write-CleanSpinner -Msg $Label -Counter ('{0} files  {1}' -f $count, (Format-Bytes $freed))
            }

            try {
                $info = [System.IO.FileInfo]::new($filePath)
                if ($cutoff -and $info.LastWriteTime -ge $cutoff) { continue }
                $sz = $info.Length
                if (-not $DryRun) {
                    [System.IO.File]::Delete($filePath)
                }
                $freed += $sz
                $count++
            } catch {}
        }
    } catch {}

    # Remove empty leftover dirs (bottom-up, non-blocking)
    if (-not $DryRun -and $Recursive) {
        try {
            [System.IO.Directory]::EnumerateDirectories($Path, '*', [System.IO.SearchOption]::AllDirectories) |
                Sort-Object { $_.Length } -Descending |
                ForEach-Object {
                    try {
                        if ([System.IO.Directory]::GetFileSystemEntries($_).Count -eq 0) {
                            [System.IO.Directory]::Delete($_)
                        }
                    } catch {}
                }
        } catch {}
    }

    $script:CleanTotalFreed += $freed
    $script:CleanTotalFiles += $count
    Write-CleanResult -Label $Label -FileCount $count -Freed $freed -DryRun:$DryRun
    return $freed
}

function Invoke-RamFlush {
    param([switch]$DryRun)
    Write-CleanSpinner -Msg 'flushing memory + network...'

    # -- GC: flush PowerShell/.NET managed heap ---------------------------
    if (-not $DryRun) {
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        } catch {}
    }

    # -- EmptyWorkingSet: trim current process working set ----------------
    try {
        if (-not ([System.Management.Automation.PSTypeName]'MemUtil').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MemUtil {
    [DllImport("psapi.dll")]    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
}
'@ -ErrorAction SilentlyContinue
        }
        if (-not $DryRun) {
            [MemUtil]::EmptyWorkingSet([MemUtil]::GetCurrentProcess()) | Out-Null
        }
    } catch {}

    # -- Network flush (all no-admin) -------------------------------------
    if (-not $DryRun) {
        try { & ipconfig /flushdns   2>$null | Out-Null } catch {}  # DNS resolver cache
        try { & nbtstat  /R          2>$null | Out-Null } catch {}  # NetBIOS name cache
        try { & arp      -d *        2>$null | Out-Null } catch {}  # ARP table (fails silently without admin)
    }

    # -- Clipboard: clear (safe, no-admin) --------------------------------
    if (-not $DryRun) {
        try { Set-Clipboard -Value '' -ErrorAction SilentlyContinue } catch {}
    }

    # -- Report: RAM stats + top 5 memory hogs ----------------------------
    Clear-SpinnerLine
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $freeMB  = [math]::Round($os.FreePhysicalMemory / 1024)
            $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
            $usedMB  = $totalMB - $freeMB
            $pct     = [math]::Round($usedMB * 100 / $totalMB)
            $tag     = if ($DryRun) { ' ~' } else { '' }
            $color   = if ($pct -gt 85) { 'Yellow' } elseif ($pct -gt 65) { 'DarkYellow' } else { 'Green' }
            $flushNote = if ($DryRun) { '' } else { '  flushed: DNS ARP NetBIOS clipboard GC' }
            Write-Host ('  RAM{0}  {1} MB / {2} MB  ({3}% used){4}' -f $tag, $usedMB, $totalMB, $pct, $flushNote) -ForegroundColor $color
        }
    } catch {}

    # Top 5 RAM hogs -- informational only (never killed)
    try {
        $top = Get-Process -ErrorAction SilentlyContinue |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                $mb = [math]::Round($_.WorkingSet64 / 1MB)
                '{0} ({1} MB)' -f $_.ProcessName, $mb
            }
        if ($top) {
            Write-Host ('  top: ' + ($top -join '  ')) -ForegroundColor DarkGray
        }
    } catch {}
}

# ---------------------------------------------------------------------------
#  Disk optimization -- SSD TRIM / HDD defrag (requires admin for Optimize-Volume)
# ---------------------------------------------------------------------------

function Invoke-DiskOptimize {
    param([switch]$DryRun)
    Write-CleanSpinner -Msg 'checking disks...'

    # Detect disk types via Get-PhysicalDisk -- requires Storage module
    $disks = @()
    try {
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_.BusType -ne 'USB' } |    # skip USB drives
            ForEach-Object {
                [pscustomobject]@{
                    Name      = $_.FriendlyName
                    MediaType = $_.MediaType             # SSD, HDD, Unspecified
                    BusType   = $_.BusType               # NVMe, SATA, SAS
                    SizeGB    = [math]::Round($_.Size / 1GB)
                    Health    = $_.HealthStatus
                }
            }
    } catch {
        # Storage module not available -- skip disk optimization
        Clear-SpinnerLine
        Write-Host '  disk info unavailable' -ForegroundColor DarkGray
        return
    }

    if ($disks.Count -eq 0) {
        Clear-SpinnerLine
        Write-Host '  no disks found' -ForegroundColor DarkGray
        return
    }

    Clear-SpinnerLine
    foreach ($disk in $disks) {
        $type  = if ($disk.MediaType -eq 'SSD') { 'SSD' } elseif ($disk.MediaType -eq 'HDD') { 'HDD' } else { '???' }
        $bus   = if ($disk.BusType) { $disk.BusType } else { '' }
        $health = if ($disk.Health -ne 'Healthy') { "  $($disk.Health)" } else { '' }
        $color  = if ($disk.Health -ne 'Healthy') { 'Yellow' } else { 'DarkGray' }

        # Attempt Optimize-Volume (requires admin -- will fail gracefully without)
        $action = ''
        if (-not $DryRun) {
            try {
                # Get volumes on this physical disk
                $volumes = Get-Volume -ErrorAction SilentlyContinue |
                    Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
                foreach ($vol in $volumes) {
                    Write-CleanSpinner -Msg ('optimizing ' + $vol.DriveLetter + ':')
                    try {
                        if ($disk.MediaType -eq 'SSD') {
                            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop
                            $action = 'TRIM'
                        } elseif ($disk.MediaType -eq 'HDD') {
                            Optimize-Volume -DriveLetter $vol.DriveLetter -Defrag -ErrorAction Stop
                            $action = 'defrag'
                        }
                    } catch {
                        # Access denied without admin -- that's expected
                        $action = 'skipped (needs admin)'
                    }
                }
            } catch {
                $action = 'skipped (needs admin)'
            }
        } else {
            $action = if ($disk.MediaType -eq 'SSD') { 'would TRIM' } elseif ($disk.MediaType -eq 'HDD') { 'would defrag' } else { 'skip' }
        }

        Clear-SpinnerLine
        Write-Host ('  {0}  {1} {2} {3}GB  {4}{5}' -f $disk.Name, $type, $bus, $disk.SizeGB, $action, $health) -ForegroundColor $color
    }
}

function Test-IsPythonVenv {
    # Quick check: dir has Scripts\python.exe (Windows) or bin/python (Unix-style)
    # OR contains pyvenv.cfg -- any of these = it's a Python env
    param([string]$Dir)
    return (
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'pyvenv.cfg')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'Scripts', 'python.exe')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'Scripts', 'python3.exe')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'bin', 'python')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'bin', 'python3'))
    )
}

function Find-VenvDirs {
    param([string[]]$SearchRoots, [int]$StaleDays)
    $cutoff = (Get-Date).AddDays(-$StaleDays)
    $found  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Helper: add dir to found if it exists and is stale
    $tryAdd = {
        param([string]$dir)
        if ([System.IO.Directory]::Exists($dir)) {
            $lw = [System.IO.Directory]::GetLastWriteTime($dir)
            if ($lw -lt $cutoff) { $null = $found.Add($dir) }
        }
    }

    $recurseOpt = [System.IO.SearchOption]::AllDirectories

    # -- Track 1: pyvenv.cfg -- standard venv / uv / virtualenv (modern) --------
    # pyvenv.cfg lives INSIDE the env dir, so its parent IS the env.
    # Catches: python -m venv .venv, uv venv, virtualenv, hatch, pdm, pyenv-virtualenv
    # --------------------------------------------------------------------------
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        Write-CleanSpinner -Msg ('scanning ' + $root)
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($root, 'pyvenv.cfg', $recurseOpt)) {
                try {
                    $dir = [System.IO.Path]::GetDirectoryName($f)
                    Write-CleanSpinner -Msg $dir
                    & $tryAdd $dir
                } catch {}
            }
        } catch {}
    }

    # -- Track 2: directory-name patterns -- conda, old virtualenv, custom names -
    # .venv / venv / .env / env / virtualenv / .virtualenv -- verify it's Python
    # by checking for Scripts\python.exe (no pyvenv.cfg in old virtualenv / conda)
    # --------------------------------------------------------------------------
    $pyDirPatterns = @('.venv', 'venv', '.env', 'env', 'virtualenv', '.virtualenv')
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($pattern in $pyDirPatterns) {
            try {
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($root, $pattern, $recurseOpt)) {
                    try {
                        Write-CleanSpinner -Msg $d
                        if (Test-IsPythonVenv -Dir $d) {
                            & $tryAdd $d
                        }
                    } catch {}
                }
            } catch {}
        }
    }

    # -- Track 3: conda / mamba named envs --------------------------------------
    # Conda stores named envs in fixed locations, not inside project dirs.
    # Each env subdir contains Scripts\python.exe (Windows).
    # --------------------------------------------------------------------------
    $condaRoots = @(
        (Join-Path $HOME '.conda\envs'),
        (Join-Path $HOME 'miniconda3\envs'),
        (Join-Path $HOME 'miniforge3\envs'),
        (Join-Path $HOME 'mambaforge\envs'),
        (Join-Path $HOME 'anaconda3\envs'),
        (Join-Path $HOME 'anaconda\envs'),
        (Join-Path $env:LOCALAPPDATA 'conda\conda\envs'),
        (Join-Path $env:USERPROFILE 'AppData\Local\miniconda3\envs')
    ) | Select-Object -Unique
    foreach ($condaRoot in $condaRoots) {
        if (-not [System.IO.Directory]::Exists($condaRoot)) { continue }
        Write-CleanSpinner -Msg ('conda envs: ' + $condaRoot)
        try {
            foreach ($envDir in [System.IO.Directory]::EnumerateDirectories($condaRoot)) {
                if (Test-IsPythonVenv -Dir $envDir) {
                    & $tryAdd $envDir
                }
            }
        } catch {}
    }

    # -- Track 4: uv tool installs ---------------------------------------------
    # `uv tool install` creates isolated envs in %APPDATA%\uv\tools\<package>
    # These are not project venvs but are safe to remove if stale (reinstallable)
    # --------------------------------------------------------------------------
    $uvToolsRoot = Join-Path $env:APPDATA 'uv\tools'
    if ([System.IO.Directory]::Exists($uvToolsRoot)) {
        Write-CleanSpinner -Msg ('uv tools: ' + $uvToolsRoot)
        try {
            foreach ($toolDir in [System.IO.Directory]::EnumerateDirectories($uvToolsRoot)) {
                if (Test-IsPythonVenv -Dir $toolDir) {
                    & $tryAdd $toolDir
                }
            }
        } catch {}
    }

    # -- Track 5: Rust target/ dirs --------------------------------------------
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($root, 'Cargo.toml', $recurseOpt)) {
                try {
                    $targetDir = Join-Path ([System.IO.Path]::GetDirectoryName($f)) 'target'
                    & $tryAdd $targetDir
                } catch {}
            }
        } catch {}
    }

    # -- Track 6: Go vendor/ dirs ----------------------------------------------
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($root, 'go.mod', $recurseOpt)) {
                try {
                    $vendorDir = Join-Path ([System.IO.Path]::GetDirectoryName($f)) 'vendor'
                    & $tryAdd $vendorDir
                } catch {}
            }
        } catch {}
    }

    # -- Track 7: node_modules -------------------------------------------------
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        try {
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($root, 'node_modules', $recurseOpt)) {
                try {
                    $lw = [System.IO.Directory]::GetLastWriteTime($d)
                    if ($lw -lt $cutoff) { $null = $found.Add($d) }
                } catch {}
            }
        } catch {}
    }

    return @($found)
}

function Remove-VenvDir {
    param([string]$Path, [switch]$DryRun)
    Write-CleanSpinner -Msg ('sizing ' + [System.IO.Path]::GetFileName($Path) + '...')
    try {
        $size = [long]0
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $size += [System.IO.FileInfo]::new($f).Length } catch {}
        }
        Clear-SpinnerLine
        $tag   = if ($DryRun) { ' ~' } else { '' }
        $color = if ($size -gt 0 -and -not $DryRun) { 'Green' } elseif ($DryRun -and $size -gt 0) { 'DarkYellow' } else { 'DarkGray' }
        $name  = [System.IO.Path]::GetFileName($Path)
        $parent= [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($Path))
        Write-Host ('  {0}/{1}{2}  {3}' -f $parent, $name, $tag, (Format-Bytes $size)) -ForegroundColor $color
        if (-not $DryRun) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:CleanTotalFreed += $size
        return $size
    } catch {
        Clear-SpinnerLine
        return [long]0
    }
}

# ---------------------------------------------------------------------------
#  Stale project scanner
# ---------------------------------------------------------------------------

function Get-DirSizeBytes {
    param([string]$Path)
    $size = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $size += [System.IO.FileInfo]::new($f).Length } catch {}
        }
    } catch {}
    return $size
}

function Find-StaleProjects {
    param([int]$StaleDays = 90)

    $cutoff = (Get-Date).AddDays(-$StaleDays)
    $found  = [System.Collections.Generic.List[object]]::new()

    $searchRoots = @(
        $HOME,
        (Join-Path $HOME 'projects'),
        (Join-Path $HOME 'dev'),
        (Join-Path $HOME 'code'),
        (Join-Path $HOME 'repos'),
        (Join-Path $HOME 'workspace'),
        (Join-Path $HOME 'Documents'),
        (Join-Path $HOME 'Desktop'),
        (Join-Path $HOME 'Downloads'),
        (Join-Path $HOME 'src'),
        (Join-Path $HOME 'work'),
        (Join-Path $HOME 'github'),
        (Join-Path $HOME 'lab')
    ) | Where-Object { [System.IO.Directory]::Exists($_) } | Select-Object -Unique

    $topOnlyOpt = [System.IO.SearchOption]::TopDirectoryOnly

    foreach ($root in $searchRoots) {
        Write-CleanSpinner -Msg ('scanning ' + $root)
        try {
            foreach ($dir in [System.IO.Directory]::EnumerateDirectories($root, '*', $topOnlyOpt)) {
                $gitDir = Join-Path $dir '.git'
                if (-not [System.IO.Directory]::Exists($gitDir)) { continue }

                # Get last commit date via git log (fast  reads packfile header only)
                $lastCommit = $null
                try {
                    $ts = & git -C $dir log -1 --format='%ct' 2>$null
                    if ($ts -and $ts -match '^\d+$') {
                        $lastCommit = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$ts).LocalDateTime
                    }
                } catch {}

                # Fall back to filesystem mtime of .git/COMMIT_EDITMSG
                if (-not $lastCommit) {
                    $editmsg = Join-Path $gitDir 'COMMIT_EDITMSG'
                    if ([System.IO.File]::Exists($editmsg)) {
                        $lastCommit = [System.IO.File]::GetLastWriteTime($editmsg)
                    } else {
                        $lastCommit = [System.IO.Directory]::GetLastWriteTime($gitDir)
                    }
                }

                if ($lastCommit -ge $cutoff) { continue }   # active  skip

                Write-CleanSpinner -Msg ('sizing ' + [System.IO.Path]::GetFileName($dir) + '...')
                $sizeBytes = Get-DirSizeBytes -Path $dir

                $remote = ''
                try {
                    $r = & git -C $dir remote get-url origin 2>$null
                    if ($r) { $remote = $r.Trim() }
                } catch {}

                $null = $found.Add([pscustomobject]@{
                    Path        = $dir
                    Name        = [System.IO.Path]::GetFileName($dir)
                    LastCommit  = $lastCommit
                    SizeBytes   = $sizeBytes
                    SizeDisplay = Format-Bytes $sizeBytes
                    DaysOld     = [int]([datetime]::Now - $lastCommit).TotalDays
                    Remote      = $remote
                })
            }
        } catch {}
    }

    Clear-SpinnerLine
    return @($found | Sort-Object SizeBytes -Descending)
}

# ---------------------------------------------------------------------------
#  Interactive project picker (fzf multi-select)
# ---------------------------------------------------------------------------

function Invoke-ProjectPicker {
    param(
        [int]$StaleDays = 90,
        [switch]$All,
        [switch]$DryRun
    )

    Write-Host ''
    Write-Host ('  8sync clean --projects  stale > {0}d{1}' -f $StaleDays, $(if ($DryRun) { '  dry-run' } else { '' })) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Scanning for stale git repos...' -ForegroundColor Yellow

    $projects = Find-StaleProjects -StaleDays $StaleDays
    Clear-SpinnerLine

    if ($projects.Count -eq 0) {
        Write-Host ('  No stale projects found (threshold: {0} days).' -f $StaleDays) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ('  Found {0} stale project(s):' -f $projects.Count) -ForegroundColor Yellow
    Write-Host ''

    # Build display table for all paths
    # Format: "<name padded> | <size> | <days> || <path>" -- path after "||" is the safe key
    $lines = $projects | ForEach-Object {
        $remote = if ($_.Remote) {
            $r = $_.Remote -replace '^https?://(www\.)?', '' -replace '^git@([^:]+):', '$1/'
            if ($r.Length -gt 32) { $r.Substring(0, 29) + '...' } else { $r }
        } else { '' }
        '{0,-36} {1,7}  {2,3}d  {3,-34}  || {4}' -f $_.Name, $_.SizeDisplay, $_.DaysOld, $remote, $_.Path
    }

    # Build a lookup: path -> project object (avoids any name-matching ambiguity)
    $pathIndex = @{}
    foreach ($p in $projects) { $pathIndex[$p.Path] = $p }

    $toDelete = @()

    if ($All) {
        # --all: show full list, then require explicit confirmation before deleting
        Write-Host '  Projects to delete:' -ForegroundColor Yellow
        foreach ($p in $projects) {
            Write-Host ('  {0,-42} {1,8}  {2}d ago' -f $p.Name, $p.SizeDisplay, $p.DaysOld) -ForegroundColor White
        }
        Write-Host ''
        if (-not $DryRun) {
            Write-Host ('  About to delete ALL {0} listed project(s). This cannot be undone.' -f $projects.Count) -ForegroundColor Red
            Write-Host '  Type YES to confirm, or press ENTER to cancel: ' -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host
            if ($confirm.Trim() -ne 'YES') {
                Write-Host '  Cancelled.' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
        }
        $toDelete = $projects

    } elseif (Test-CommandExists 'fzf') {
        Write-Host '  [TAB=select  ENTER=confirm  ESC=cancel  Ctrl+A=select all]' -ForegroundColor DarkGray
        Write-Host ''
        $selected = $lines | fzf `
            --multi `
            --header='Select projects to DELETE (TAB to mark, ENTER to confirm)' `
            --height=70% `
            --layout=reverse `
            --border `
            --prompt='Delete> ' `
            --bind='ctrl-a:select-all' `
            --with-nth='1,2,3,4,5'

        if (-not $selected) {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            Write-Host ''
            return
        }

        # Extract path from after "|| " separator -- exact match, no name ambiguity
        $toDelete = @($selected | ForEach-Object {
            if ($_ -match '\|\|\s+(.+)$') {
                $path = $Matches[1].Trim()
                if ($pathIndex.ContainsKey($path)) { $pathIndex[$path] }
            }
        } | Where-Object { $_ })

    } else {
        # No fzf -- plain numbered list
        $i = 1
        foreach ($p in $projects) {
            Write-Host ('  [{0,2}] {1,-42} {2,8}  {3}d ago' -f $i, $p.Name, $p.SizeDisplay, $p.DaysOld) -ForegroundColor White
            $i++
        }
        Write-Host ''
        Write-Host '  Enter numbers to delete (e.g. 1,3,5  or "all"  or ENTER to cancel): ' -ForegroundColor Yellow -NoNewline
        $rawInput = Read-Host
        if (-not $rawInput -or $rawInput.Trim() -eq '') {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            Write-Host ''
            return
        }
        if ($rawInput.Trim().ToLowerInvariant() -eq 'all') {
            $toDelete = $projects
        } else {
            $indices = $rawInput -split '[,\s]+' |
                Where-Object { $_ -match '^\d+$' } |
                ForEach-Object { [int]$_ - 1 } |
                Where-Object { $_ -ge 0 -and $_ -lt $projects.Count }
            $toDelete = @($indices | ForEach-Object { $projects[$_] })
        }
    }

    if (-not $toDelete -or @($toDelete).Count -eq 0) {
        Write-Host '  Nothing selected.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Final summary + safety confirmation before actual delete
    Write-Host ''
    Write-Host ('  Selected {0} project(s) to delete:' -f @($toDelete).Count) -ForegroundColor Yellow
    $totalFreed = [long]0
    foreach ($p in @($toDelete)) {
        Write-Host ('    {0,-42} {1,8}' -f $p.Name, $p.SizeDisplay) -ForegroundColor White
        $totalFreed += $p.SizeBytes
    }
    Write-Host ('  Total: {0}' -f (Format-Bytes $totalFreed)) -ForegroundColor DarkGray
    Write-Host ''

    if ($DryRun) {
        Write-Host ('  >> would free {0} from {1} project(s)' -f (Format-Bytes $totalFreed), @($toDelete).Count) -ForegroundColor DarkYellow
        Write-Host '  run without --dry-run to apply' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host '  Type YES to confirm permanent deletion, or press ENTER to cancel: ' -ForegroundColor Red -NoNewline
    $confirm = Read-Host
    if ($confirm.Trim() -ne 'YES') {
        Write-Host '  Cancelled. Nothing deleted.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host ('  Deleting {0} project(s)...' -f @($toDelete).Count) -ForegroundColor Yellow
    foreach ($p in @($toDelete)) {
        Write-Host ('  {0}  {1}' -f $p.Name, $p.SizeDisplay) -ForegroundColor Green
        try {
            Remove-Item -Path $p.Path -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    Write-Host ''
    Write-Host ('  >> freed {0} from {1} project(s)' -f (Format-Bytes $totalFreed), @($toDelete).Count) -ForegroundColor Green
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Deep dev artifact scanner (MCP, npm globals, pip globals, cargo, go)
# ---------------------------------------------------------------------------

function Find-OrphanedDevArtifacts {
    param([int]$StaleDays = 30)

    $cutoff  = (Get-Date).AddDays(-$StaleDays)
    $results = [System.Collections.Generic.List[object]]::new()

    $addEntry = {
        param([string]$Type, [string]$Name, [string]$Path, [datetime]$LastWrite, [long]$Size)
        $null = $results.Add([pscustomobject]@{
            Type        = $Type
            Name        = $Name
            Path        = $Path
            LastWrite   = $LastWrite
            DaysOld     = [int]([datetime]::Now - $LastWrite).TotalDays
            SizeBytes   = $Size
            SizeDisplay = Format-Bytes $Size
        })
    }

    # -- MCP server caches & data ----------------------------------------
    $mcpRoots = @(
        (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'),   # Claude Desktop
        (Join-Path $HOME '.config\claude'),
        (Join-Path $env:APPDATA 'Code\User\globalStorage\saoudrizwan.claude-dev'),  # Cline/Claude VSCode ext
        (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx')                  # npx-cached MCP servers
    )
    foreach ($p in $mcpRoots) {
        if (-not (Test-Path $p)) { continue }
        Write-CleanSpinner -Msg ('MCP: ' + $p)
        try {
            # npx cache entries older than threshold
            if ($p -like '*_npx*') {
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($p)) {
                    $lw = [System.IO.Directory]::GetLastWriteTime($d)
                    if ($lw -lt $cutoff) {
                        $sz = Get-DirSizeBytes $d
                        & $addEntry 'npx-cache' ([System.IO.Path]::GetFileName($d)) $d $lw $sz
                    }
                }
            }
        } catch {}
    }

    # -- npm global packages ---------------------------------------------
    $npmGlobalDirs = @(
        (Join-Path $env:APPDATA 'npm\node_modules'),
        (Join-Path $HOME 'scoop\apps\nodejs\current\node_modules'),
        (Join-Path $env:PROGRAMFILES 'nodejs\node_modules')
    )
    foreach ($ngDir in $npmGlobalDirs) {
        if (-not [System.IO.Directory]::Exists($ngDir)) { continue }
        Write-CleanSpinner -Msg ('npm globals: ' + $ngDir)
        try {
            foreach ($pkg in [System.IO.Directory]::EnumerateDirectories($ngDir)) {
                $lw = [System.IO.Directory]::GetLastWriteTime($pkg)
                if ($lw -lt $cutoff) {
                    $name = [System.IO.Path]::GetFileName($pkg)
                    if ($name -eq 'npm') { continue }   # never remove npm itself
                    $sz = Get-DirSizeBytes $pkg
                    & $addEntry 'npm-global' $name $pkg $lw $sz
                }
            }
        } catch {}
        break   # only scan the first found npm global dir
    }

    # -- pip / uv global site-packages -----------------------------------
    $pipGlobalDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\Lib\site-packages'),
        (Join-Path $HOME 'scoop\apps\python\current\Lib\site-packages'),
        (Join-Path $env:APPDATA 'Python\Python*\site-packages')
    )
    foreach ($pattern in $pipGlobalDirs) {
        $resolved = try { (Resolve-Path $pattern -ErrorAction SilentlyContinue) } catch { $null }
        if (-not $resolved) { continue }
        foreach ($dir in @($resolved)) {
            if (-not [System.IO.Directory]::Exists($dir.Path)) { continue }
            Write-CleanSpinner -Msg ('pip site-packages: ' + $dir.Path)
            try {
                foreach ($pkg in [System.IO.Directory]::EnumerateDirectories($dir.Path)) {
                    $lw = [System.IO.Directory]::GetLastWriteTime($pkg)
                    if ($lw -lt $cutoff) {
                        $name = [System.IO.Path]::GetFileName($pkg)
                        if ($name -match '(pip|setuptools|wheel|distutils)') { continue }
                        $sz = Get-DirSizeBytes $pkg
                        & $addEntry 'pip-global' $name $pkg $lw $sz
                    }
                }
            } catch {}
            break
        }
    }

    # -- cargo installed bins --------------------------------------------
    $cargoBin = Join-Path $HOME '.cargo\bin'
    if ([System.IO.Directory]::Exists($cargoBin)) {
        Write-CleanSpinner -Msg 'cargo bin...'
        try {
            foreach ($bin in [System.IO.Directory]::EnumerateFiles($cargoBin, '*.exe')) {
                $info = [System.IO.FileInfo]::new($bin)
                if ($info.LastWriteTime -lt $cutoff) {
                    & $addEntry 'cargo-bin' $info.Name $bin $info.LastWriteTime $info.Length
                }
            }
        } catch {}
    }

    # -- go installed bins -----------------------------------------------
    $goBin = Join-Path $HOME 'go\bin'
    if ([System.IO.Directory]::Exists($goBin)) {
        Write-CleanSpinner -Msg 'go bin...'
        try {
            foreach ($bin in [System.IO.Directory]::EnumerateFiles($goBin, '*.exe')) {
                $info = [System.IO.FileInfo]::new($bin)
                if ($info.LastWriteTime -lt $cutoff) {
                    & $addEntry 'go-bin' $info.Name $bin $info.LastWriteTime $info.Length
                }
            }
        } catch {}
    }

    Clear-SpinnerLine
    return @($results | Sort-Object SizeBytes -Descending)
}

function Show-DevArtifactReport {
    param([int]$StaleDays = 30)

    Write-Host ''
    Write-Host ('  8sync clean --deep  dev artifacts > {0}d old' -f $StaleDays) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Scanning dev artifacts (MCP, npm, pip, cargo, go)...' -ForegroundColor Yellow

    $artifacts = Find-OrphanedDevArtifacts -StaleDays $StaleDays
    Clear-SpinnerLine

    if ($artifacts.Count -eq 0) {
        Write-Host ('  No stale dev artifacts found (threshold: {0} days).' -f $StaleDays) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Group by type
    $grouped = $artifacts | Group-Object Type
    foreach ($group in $grouped) {
        $totalSz = ($group.Group | Measure-Object SizeBytes -Sum).Sum
        Write-Host ('  {0}  ({1} items  {2})' -f $group.Name.ToUpper(), $group.Count, (Format-Bytes $totalSz)) -ForegroundColor Yellow
        foreach ($item in $group.Group | Select-Object -First 10) {
            Write-Host ('    {0,-45} {1,8}  {2}d ago' -f $item.Name, $item.SizeDisplay, $item.DaysOld) -ForegroundColor DarkGray
        }
        if ($group.Group.Count -gt 10) {
            Write-Host ('    ... and {0} more' -f ($group.Group.Count - 10)) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    $totalAll = ($artifacts | Measure-Object SizeBytes -Sum).Sum
    Write-Host ('  Total stale dev artifacts: {0} items  {1}' -f $artifacts.Count, (Format-Bytes $totalAll)) -ForegroundColor DarkYellow
    Write-Host '  These are reported only  remove manually or with your package manager.' -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Windows Defender quick scan
# ---------------------------------------------------------------------------

function Invoke-DefenderScan {
    param([string[]]$TargetPaths)

    Write-Host ''
    Write-Host '  8sync clean --scan  Windows Defender scan' -ForegroundColor Cyan
    Write-Host ''

    # Locate MpCmdRun.exe
    $mpCmd = $null
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Defender\MpCmdRun.exe'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform\*\MpCmdRun.exe')
    )
    foreach ($c in $candidates) {
        $resolved = try { (Resolve-Path $c -ErrorAction SilentlyContinue) } catch { $null }
        if ($resolved) {
            $mpCmd = @($resolved)[0].Path
            break
        }
    }

    if (-not $mpCmd -or -not (Test-Path $mpCmd)) {
        Write-Host '  Windows Defender MpCmdRun.exe not found. Skipping scan.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ('  Defender: {0}' -f $mpCmd) -ForegroundColor DarkGray

    if ($TargetPaths -and $TargetPaths.Count -gt 0) {
        # Custom path scan
        foreach ($path in $TargetPaths | Where-Object { Test-Path $_ }) {
            Write-Host ('  Scanning: {0}' -f $path) -ForegroundColor Yellow
            try {
                $result = & $mpCmd -Scan -ScanType 3 -File $path 2>&1
                $threat = $result | Select-String -Pattern 'threat|found|infected' -CaseSensitive:$false
                if ($threat) {
                    Write-Host ('  [!] THREATS DETECTED in {0}' -f $path) -ForegroundColor Red
                    $threat | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
                } else {
                    Write-Host ('  [OK] Clean: {0}' -f $path) -ForegroundColor Green
                }
            } catch {
                Write-Host ('  Scan failed for {0}: {1}' -f $path, $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } else {
        # Quick scan (ScanType 1)  non-blocking, Defender runs in background
        Write-Host '  Running quick scan (ScanType 1)...' -ForegroundColor Yellow
        Write-Host '  Note: scan runs in background. Check Windows Security for results.' -ForegroundColor DarkGray
        try {
            Start-Process -FilePath $mpCmd -ArgumentList @('-Scan', '-ScanType', '1') -WindowStyle Hidden -ErrorAction Stop
            Write-Host '  [OK] Quick scan started.' -ForegroundColor Green
        } catch {
            Write-Host ('  Failed to start scan: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }

        # Also scan common dev artifact roots (targeted, foreground)
        $devRoots = @(
            (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'),
            (Join-Path $HOME 'scoop\apps'),
            (Join-Path $HOME '.cargo\bin')
        ) | Where-Object { Test-Path $_ }

        if ($devRoots.Count -gt 0) {
            Write-Host '  Targeted scan on dev tool directories...' -ForegroundColor Yellow
            foreach ($root in $devRoots) {
                Write-Host ('  Scanning: {0}' -f $root) -ForegroundColor DarkGray
                try {
                    & $mpCmd -Scan -ScanType 3 -File $root 2>&1 | Out-Null
                    Write-Host ('  [OK] {0}' -f $root) -ForegroundColor Green
                } catch {}
            }
        }
    }

    Write-Host ''
}

function Invoke-SystemClean {
    param(
        [int]$StaleDays = 7,
        [switch]$DryRun
    )

    # Reset session counters
    $script:CleanTotalFreed  = [long]0
    $script:CleanTotalFiles  = 0
    $script:CleanSpinnerIdx  = 0

    $sw    = [System.Diagnostics.Stopwatch]::StartNew()
    $dTag  = if ($DryRun) { '  dry-run' } else { '' }

    Write-Host ''
    Write-Host ('  8sync clean  >{0}d stale{1}' -f $StaleDays, $dTag) -ForegroundColor Cyan
    Write-Host ''

    # -- Temp --------------------------------------------------------------
    Write-Host '  TEMP' -ForegroundColor Yellow
    $tempPaths = @($env:TEMP, $env:TMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:LOCALAPPDATA 'Temp')) |
        Select-Object -Unique
    foreach ($p in $tempPaths) {
        $shortLabel = if ($p -like "$HOME*") { '~' + $p.Substring($HOME.Length) } else { $p }
        Invoke-CleanPath -Path $p -Label $shortLabel -StaleDays $StaleDays -DryRun:$DryRun -Recursive | Out-Null
    }

    # -- App caches ------------------------------------------------------
    Write-Host ''
    Write-Host '  APP CACHES' -ForegroundColor Yellow
    $cachePaths = @(
        # -- Browsers --
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache');       Label = 'Chrome' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache');  Label = 'Chrome/code' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache');      Label = 'Edge' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache'); Label = 'Edge/code' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles');                    Label = 'Firefox' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Cache'); Label = 'Brave' }
        # -- Dev tools --
        @{ Path = (Join-Path $env:APPDATA 'Code\User\workspaceStorage');                       Label = 'VSCode/workspace' }
        @{ Path = (Join-Path $env:APPDATA 'Code\logs');                                        Label = 'VSCode/logs' }
        @{ Path = (Join-Path $env:APPDATA 'Code\CachedExtensionVSIXs');                        Label = 'VSCode/vsix' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'npm-cache');                                   Label = 'npm' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'pip\cache');                                   Label = 'pip' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'uv\cache');                                    Label = 'uv' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'go\pkg\mod\cache');                            Label = 'go/mod' }
        @{ Path = (Join-Path $HOME '.cargo\registry\cache');                                   Label = 'cargo' }
        @{ Path = (Join-Path $HOME '.gradle\caches');                                          Label = 'gradle' }
        @{ Path = (Join-Path $HOME '.m2\repository');                                          Label = 'maven' }
        @{ Path = (Join-Path $HOME '.nuget\packages');                                         Label = 'nuget' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Yarn\Cache');                                  Label = 'yarn' }
        @{ Path = (Join-Path $HOME 'scoop\cache');                                             Label = 'scoop' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'pnpm\store');                                  Label = 'pnpm' }
        @{ Path = (Join-Path $env:APPDATA 'Bun\install\cache');                                Label = 'bun' }
        # -- Communication apps --
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Teams\Cache');                            Label = 'Teams' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Teams\blob_storage');                     Label = 'Teams/blob' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Teams\databases');                        Label = 'Teams/db' }
        @{ Path = (Join-Path $env:APPDATA 'discord\Cache');                                    Label = 'Discord' }
        @{ Path = (Join-Path $env:APPDATA 'discord\Code Cache');                               Label = 'Discord/code' }
        @{ Path = (Join-Path $env:APPDATA 'Slack\Cache');                                      Label = 'Slack' }
        @{ Path = (Join-Path $env:APPDATA 'Slack\Code Cache');                                 Label = 'Slack/code' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Spotify\Storage');                             Label = 'Spotify' }
    )
    foreach ($entry in $cachePaths) {
        Invoke-CleanPath -Path $entry.Path -Label $entry.Label -StaleDays $StaleDays -DryRun:$DryRun -Recursive | Out-Null
    }

    # -- Windows caches --------------------------------------------------
    Write-Host ''
    Write-Host '  WINDOWS' -ForegroundColor Yellow
    $winCaches = @(
        # -- System caches (some need admin -- fail silently) --
        @{ Path = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download'); Label = 'WU/download' }
        @{ Path = (Join-Path $env:SystemRoot 'Prefetch');                       Label = 'Prefetch' }
        # -- User-space caches (no admin) --
        @{ Path = (Join-Path $env:LOCALAPPDATA 'CrashDumps');                   Label = 'CrashDumps' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache');  Label = 'INetCache' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Recent');          Label = 'Recent' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations');   Label = 'JumpLists' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER');        Label = 'ErrorReports' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer');   Label = 'Thumbnails' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'D3DSCache');                    Label = 'D3DShader' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache');               Label = 'NVIDIA/DXCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache');               Label = 'NVIDIA/GLCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'AMD\DxCache');                  Label = 'AMD/DxCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'AMD\GLCache');                  Label = 'AMD/GLCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Intel\ShaderCache');            Label = 'Intel/Shader' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ActionCenterCache'); Label = 'ActionCenter' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches');     Label = 'WinCaches' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WebCache');   Label = 'WebCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'IconCache.db');                 Label = 'IconCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\ConstraintIndex'); Label = 'SearchIdx' }
    )
    foreach ($entry in $winCaches) {
        Invoke-CleanPath -Path $entry.Path -Label $entry.Label -StaleDays $StaleDays -DryRun:$DryRun -Recursive | Out-Null
    }

    # -- Stale envs ------------------------------------------------------
    Write-Host ''
    Write-Host ('  STALE ENVS  (>{0}d)' -f $StaleDays) -ForegroundColor Yellow
    $searchRoots = @(
        $HOME,
        (Join-Path $HOME 'projects'), (Join-Path $HOME 'dev'),  (Join-Path $HOME 'code'),
        (Join-Path $HOME 'repos'),    (Join-Path $HOME 'workspace'), (Join-Path $HOME 'Documents')
    ) | Where-Object { Test-Path $_ }

    if ($searchRoots.Count -gt 0) {
        $venvDirs = Find-VenvDirs -SearchRoots $searchRoots -StaleDays $StaleDays
        Clear-SpinnerLine
        if ($venvDirs.Count -gt 0) {
            foreach ($venv in $venvDirs) {
                Remove-VenvDir -Path $venv -DryRun:$DryRun | Out-Null
            }
        } else {
            Write-Host '  no stale envs' -ForegroundColor DarkGray
        }
    }

    # -- RAM + network flush --------------------------------------------
    Write-Host ''
    Write-Host '  MEMORY & NETWORK' -ForegroundColor Yellow
    Invoke-RamFlush -DryRun:$DryRun

    # -- Disk optimization -----------------------------------------------
    Write-Host ''
    Write-Host '  DISK' -ForegroundColor Yellow
    Invoke-DiskOptimize -DryRun:$DryRun

    # -- Summary ----------------------------------------------------------
    $sw.Stop()
    $elapsed = if ($sw.Elapsed.TotalSeconds -ge 60) {
        ('{0}m {1}s' -f [int]$sw.Elapsed.TotalMinutes, $sw.Elapsed.Seconds)
    } else {
        ('{0:F1}s' -f $sw.Elapsed.TotalSeconds)
    }
    Write-Host ''
    $summaryColor = if ($DryRun) { 'DarkYellow' } else { 'Green' }
    $verb         = if ($DryRun) { 'would free' } else { 'freed' }
    Write-Host ('  >> {0} {1}  {2} files  {3}' -f $verb, (Format-Bytes $script:CleanTotalFreed), $script:CleanTotalFiles, $elapsed) -ForegroundColor $summaryColor
    if ($DryRun) { Write-Host '  run without --dry-run to apply' -ForegroundColor DarkGray }
    Write-Host ''
}

function Invoke-CleanCommand {
    param([string[]]$Rest)

    $dryRun      = $false
    $staleDays   = 7
    $doProjects  = $false
    $projectsAll = $false
    $doDeep      = $false
    $doScan      = $false
    $scanPaths   = @()

    foreach ($arg in $Rest) {
        switch ($arg.ToLowerInvariant()) {
            '--dry-run'  { $dryRun = $true }
            '--projects' { $doProjects = $true }
            '--all'      { $projectsAll = $true }
            '--deep'     { $doDeep = $true }
            '--scan'     { $doScan = $true }
            { $_ -in '--help', 'help', '-h' } {
                Write-Host ''
                Write-HintSection 'CLEAN -- deep system / cache / venv / RAM / disk / project optimizer'
                Write-HintRow '8sync clean'                          'Full clean: temp/cache/venv/RAM/disk (stale > 7d)'
                Write-HintRow '8sync clean --days N'                 'Custom stale threshold  e.g. --days 14'
                Write-HintRow '8sync clean --dry-run'                'Preview only -- nothing deleted'
                Write-HintRow '8sync clean --projects'               'Pick stale git repos to delete (fzf multi-select)'
                Write-HintRow '8sync clean --projects --all'         'Delete ALL stale git repos, no picker'
                Write-HintRow '8sync clean --projects --days N'      'Stale threshold for projects (default: 90d)'
                Write-HintRow '8sync clean --projects --dry-run'     'Preview project deletions only'
                Write-HintRow '8sync clean --deep'                   'Report stale MCP/npm/pip/cargo/go artifacts'
                Write-HintRow '8sync clean --deep --days N'          'Custom threshold for artifact scan'
                Write-HintRow '8sync clean --scan'                   'Windows Defender quick + dev-folder scan'
                Write-HintRow '8sync clean --scan <path>'            'Targeted Defender scan on specific path'
                Write-Host ''
                return
            }
        }
    }

    for ($i = 0; $i -lt $Rest.Count; $i++) {
        if ($Rest[$i] -in '--days', '-d') {
            $parsed = 0
            if ($i + 1 -lt $Rest.Count -and [int]::TryParse($Rest[$i + 1], [ref]$parsed) -and $parsed -gt 0) {
                $staleDays = $parsed
            }
        }
        # --scan <path1> <path2> ...  (optional path args after --scan)
        if ($Rest[$i].ToLowerInvariant() -eq '--scan') {
            for ($j = $i + 1; $j -lt $Rest.Count; $j++) {
                if ($Rest[$j] -like '--*') { break }
                $scanPaths += $Rest[$j]
            }
        }
    }

    if ($doProjects) {
        # Use explicit --days N if provided, otherwise default 90d for projects
        $projectDays = if ($Rest -contains '--days' -or $Rest -contains '-d') { $staleDays } else { 90 }
        Invoke-ProjectPicker -StaleDays $projectDays -All:$projectsAll -DryRun:$dryRun
        return
    }

    if ($doDeep) {
        Show-DevArtifactReport -StaleDays $staleDays
        return
    }

    if ($doScan) {
        Invoke-DefenderScan -TargetPaths $scanPaths
        return
    }

    Invoke-SystemClean -StaleDays $staleDays -DryRun:$dryRun
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

function Register-ShellEngineInits {
    # Run zoxide and starship init AFTER all aliases are registered.
    # Both spawn an external process and Invoke-Expression the output --
    # typically 50-150ms each. Moving them here means the prompt appears
    # with all aliases ready before the engines hook in.
    # zoxide: registers z / __zoxide_hook. cdi alias already points to z.
    # starship: overrides PROMPT_COMMAND / prompt function.
    if (Test-CommandExists 'zoxide') {
        try {
            Invoke-Expression (& zoxide init powershell | Out-String)
        } catch {}
    }

    if (Test-CommandExists 'starship') {
        try {
            Invoke-Expression (& starship init powershell)
        } catch {}
    }
}

function Set-ToolAliases {
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

    function global:Reset-TerminalState {
        # Resets all terminal modes that TUI apps (OpenCode, vim, etc.) may leave
        # behind when they crash or exit uncleanly:
        #   - Mouse tracking off (normal, button, any-event, SGR extended)
        #   - Bracketed paste off
        #   - Alternative screen off
        #   - Cursor visible, not blinking
        #   - Application keypad mode off
        [System.Console]::Write(
            "`e[?1000l" +   # mouse tracking off
            "`e[?1002l" +   # button-event mouse off
            "`e[?1003l" +   # any-event mouse off
            "`e[?1006l" +   # SGR extended mouse off
            "`e[?1015l" +   # URXVT extended mouse off
            "`e[?2004l" +   # bracketed paste off
            "`e[?1049l" +   # exit alt screen
            "`e[?25h"   +   # cursor visible
            "`e[0m"         # reset all SGR attributes
        )
        [System.Console]::WriteLine()
        Write-Host 'Terminal state reset.' -ForegroundColor Green
    }
    Set-Alias -Name fix -Value Reset-TerminalState -Scope Global -Force

    Register-8SyncAlias

    # Engine inits last -- these are the slowest external calls (50-150ms each)
    # All aliases/completers are already registered before this runs
    Register-ShellEngineInits
}

function Register-8SyncAlias {
    # 8sync command dispatcher + aliases + tab completion.
    # Extracted from Set-ToolAliases so it can be tested/reloaded independently.

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
            'clean'  { Invoke-CleanCommand -Rest $Rest }
            'bg'     { Invoke-BgCommand -Rest $Rest }
            'hx'     { Invoke-HxCommand -Rest $Rest }
            default  { Show-8SyncHint }
        }
    }

    Set-Alias -Name '/8sync' -Value Invoke-8Sync -Scope Global -Force
    Set-Alias -Name '8sync'  -Value Invoke-8Sync -Scope Global -Force

    Register-8SyncCompleter
}

function Test-NerdFontInstalled {
    # Check 1: scoop manifest present (fastest, no assembly needed)
    $scoop = Get-ScoopCommand
    if ($scoop) {
        try {
            $info = & $scoop.Source info JetBrainsMono-NF 2>$null | Out-String
            if ($info -match 'Installed') { return $true }
        } catch {}
    }

    # Check 2: font files exist in user or system font folder
    $fontDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'),
        'C:\Windows\Fonts',
        (Join-Path $HOME 'scoop\apps\JetBrainsMono-NF\current')
    )
    foreach ($dir in $fontDirs) {
        if ((Test-Path $dir) -and (Get-ChildItem $dir -Filter '*JetBrainsMono*' -ErrorAction SilentlyContinue)) {
            return $true
        }
    }

    # Check 3: registry (HKCU user fonts, no admin needed)
    foreach ($regPath in @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )) {
        try {
            $regFonts = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            if ($regFonts -and ($regFonts.PSObject.Properties.Name | Where-Object { $_ -like '*JetBrainsMono*' })) {
                return $true
            }
        } catch {}
    }

    # Check 4: System.Drawing (requires explicit assembly load in PS 5.1)
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $families = [System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }
        if (($families -contains 'JetBrainsMono Nerd Font') -or ($families -contains 'JetBrainsMono NF')) {
            return $true
        }
    } catch {}

    return $false
}

function Ensure-NerdFont {
    if (Test-NerdFontInstalled) { return }
    Write-Host '[8sync] JetBrainsMono Nerd Font not found.' -ForegroundColor DarkYellow
    Write-Host '  To install: scoop bucket add nerd-fonts && scoop install JetBrainsMono-NF' -ForegroundColor DarkGray
}

function Start-WezTermShell {
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
        Write-Warning ('[8sync] PowerShell {0}.{1} detected. Minimum supported: 5.1. Some features may not work.' -f $psVer.Major, $psVer.Minor)
        Write-Warning '[8sync] Install pwsh 7+: scoop install powershell  or  https://aka.ms/powershell'
    }

    Ensure-PreferredPaths
    Ensure-NerdFont
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
    Start-BgRotateCheck

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
        'BgRotate' {
            Invoke-BgRotateNow
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


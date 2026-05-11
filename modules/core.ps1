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

    if (-not $script:CommandExistsCache) {
        $script:CommandExistsCache = @{}
    }

    if ($script:CommandExistsCache.ContainsKey($Name)) {
        return [bool]$script:CommandExistsCache[$Name]
    }

    $exists = $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
    $script:CommandExistsCache[$Name] = $exists
    return $exists
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

function Test-StartupBackgroundGate {
    Ensure-StateDir

    $nowUtc = [datetime]::UtcNow
    if (Test-Path $script:StartupBackgroundGatePath) {
        try {
            $raw = Get-Content -Raw $script:StartupBackgroundGatePath | ConvertFrom-Json
            if ($raw -and $raw.lastRunUtc) {
                $ageSeconds = ($nowUtc - [datetime]$raw.lastRunUtc).TotalSeconds
                if ($ageSeconds -lt $script:StartupBackgroundGateSeconds) {
                    return $false
                }
            }
        } catch {
        }
    }

    try {
        [pscustomobject]@{
            lastRunUtc = $nowUtc.ToString('o')
        } | ConvertTo-Json | Set-Content -Path $script:StartupBackgroundGatePath -Encoding UTF8
    } catch {
    }

    return $true
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

function Get-StartupMode {
    $mode = $env:WEZTERM_STARTUP_MODE
    if ([string]::IsNullOrWhiteSpace($mode)) {
        return $script:StartupModeDefault
    }

    $normalized = $mode.ToLowerInvariant()
    if ($script:StartupKnownModes -contains $normalized) {
        return $normalized
    }

    return $script:StartupModeDefault
}

function Write-StartupProfile {
    param(
        [Parameter(Mandatory)] [string]$Mode,
        [Parameter(Mandatory)] [hashtable]$Phases,
        [Parameter(Mandatory)] [double]$TotalMs
    )

    Ensure-StateDir

    $entry = [pscustomobject]@{
        timestampUtc = [datetime]::UtcNow.ToString('o')
        mode         = $Mode
        totalMs      = [math]::Round($TotalMs, 1)
        phases       = $Phases
    }

    $existing = @()
    if (Test-Path $script:StartupProfilePath) {
        try {
            $raw = Get-Content -Raw $script:StartupProfilePath
            if ($raw) {
                $parsed = $raw | ConvertFrom-Json
                if ($parsed -is [array]) {
                    $existing = @($parsed)
                } elseif ($parsed) {
                    $existing = @($parsed)
                }
            }
        } catch {
        }
    }

    $merged = @($existing + $entry)
    if ($merged.Count -gt $script:StartupProfileMaxEntries) {
        $start = $merged.Count - $script:StartupProfileMaxEntries
        $merged = @($merged[$start..($merged.Count - 1)])
    }

    $merged | ConvertTo-Json -Depth 7 | Set-Content -Path $script:StartupProfilePath -Encoding UTF8
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

    Write-HintSection 'PROFILE'
    Write-HintRow '8sync profile list'              'List all profiles (* = active)'
    Write-HintRow '8sync profile create <name>'     'Create new empty profile'
    Write-HintRow '8sync profile clone <src> <dst>'  'Clone profile with all settings'
    Write-HintRow '8sync profile switch <name>'     'Switch current tab to profile (CLI/state only)'
    Write-HintRow '8sync profile open <name>'       'Open new window with full profile isolation'
    Write-HintRow '8sync profile delete <name>'     'Delete a profile'
    Write-HintRow '8sync profile help'              'Full profile help with details'

    Write-HintSection 'COMMANDS'
    Write-HintRow '8sync help'              'Show this help'
    Write-HintRow '8sync status'            'Installed tools + last sync time'
    Write-HintRow '8sync reload'            'Hot-reload all modules in current session (no new tab needed)'
    Write-HintRow '8sync sync'              'Install missing tools + update all via scoop'
    Write-HintRow '8sync sync --check'     'Dry-run: show missing + available updates, no changes'
    Write-HintRow '8sync clean [--days N]'         'Deep clean: temp/cache/global env/RAM/disk (default: stale > 7 days)'
    Write-HintRow '8sync clean --projects [--all]' 'Report stale git repos only (deletion disabled for safety)'
    Write-HintRow '8sync gpu [N|status|auto|off]'  'Adaptive GPU policy. Example: 8sync gpu 10 for smoother rendering'
    Write-HintRow '8sync clean --deep'             'Report stale MCP/npm/pip/cargo/go dev artifacts'
    Write-HintRow '8sync clean --scan'             'Windows Defender quick scan + dev folder scan'
    Write-HintRow '8sync clean --audit'            'npm/cargo/pip vulnerability scan + postinstall check'
    Write-HintRow '8sync clean --loop on [N] [profile]' 'Auto clean loop (light/balanced/deep) with safe dry-run defaults'
    Write-HintRow '8sync theme [style] [scene]'    'Set WezTerm glass style/scene and persist it'
    Write-HintRow '8sync forge install'              'Install ForgeCode AI pair programmer (forgecode.dev)'
    Write-HintRow '8sync forge status'               'Show forge version, binary path, dependency check'
    Write-HintRow '8sync opencode'                   'Export portable OpenCode bundle to ./oc-bundle (exclude lib, node_modules, *.ps1, *.py)'
    Write-HintRow '8sync opencode reinstall'         'Purge auth/plugin cache, then force reinstall from ./oc-bundle -> ~/.config/opencode + npm i'
    Write-HintRow '8sync opencode fresh-install --stable' 'Full clean + reinstall + oma install using the pinned stable profile'
    Write-HintRow '8sync opencode --dry-run'         'Preview exported/applied files only, no changes'
    Write-HintRow '8sync opencode status'            'Show source + bundle status and runtime readiness'
    Write-HintRow '8sync gsd setup'                 'Generate routing and auto-apply GSD Anthropic OAuth fix (#145-style)'
    Write-HintRow '8sync gsd fix [--dry-run]'       'Fast repair: restore node_modules/resource-loader bridges, patch runtime, clean stale DB sidecars'
    Write-HintRow '8sync gsd fix --refresh'         'Also upgrade gsd-pi runtime when you explicitly want a slower package refresh'
    Write-HintRow '8sync gsd fix --force'           'Also back up and rebuild gsd.db + milestone cache files when the project DB is corrupted'
    Write-HintRow '8sync gsd-1 help'                'OpenCode GSD (.planning/) guide bridge for the current project'
    Write-HintRow '8sync gsd-1 status'              'Check .planning/config.json, oc-config.json, ROADMAP.md, STATE.md'
    Write-HintRow '8sync gsd key <api-key>'         'Set Z_CODING_PLAN_API_KEY (current session + persist)'
    Write-HintRow '8sync gsd status'                'Show GSD paths, logged-in providers, API key status'
    Write-HintRow '8sync gsd local'                 'Show project-local gsd-pi baseline/current/latest layout and preferred runtime'
    Write-HintRow '8sync gsd add gguf'              'Register running llama-server as GSD provider in models.json'
    Write-HintRow '8sync gsd remove gguf'           'Remove gguf-local-* providers from models.json'
    Write-HintRow '8sync remove claude-code'       'Deep uninstall Claude Code CLI (native + npm + bun)'
    Write-HintRow '8sync remove gsd2 --dry-run'    'Preview deep removal of gsd-2 (gsd-pi@latest) from this machine'

    Write-HintSection 'GGUF'
    Write-HintRow '8sync gguf serve --engine-path <d> --model-path <f>' 'Start llama-server with chosen preset'
    Write-HintRow '8sync gguf hint'                                      'Prerequisites checklist (driver, CUDA, llama.cpp)'
    Write-HintRow '8sync gguf serve --preset <max|high|medium|low>'     'Resource preset (GPU layers, ctx, threads)'
    Write-HintRow '8sync gguf serve --profile <name>'                   'Launch from saved profile'
    Write-HintRow '8sync gguf presets'                                   'List all presets with GPU/CPU/context details'
    Write-HintRow '8sync gguf profiles'                                  'List saved server profiles'
    Write-HintRow '8sync gguf save --profile <n> --engine-path <d> --model-path <f>' 'Save profile for quick re-launch'
    Write-HintRow '8sync gguf status'                                    'Show running llama-server PIDs + ports'
    Write-HintRow '8sync gguf stop'                                      'Kill all running llama-server processes'

    Write-HintSection 'BACKGROUND'
    Write-HintRow '8sync bg search <kw>'         'Search wallhaven (default), --yandere, --safebooru, --all'
    Write-HintRow '8sync bg pick'                'Pick from cache with fzf + imgcat preview'
    Write-HintRow '8sync bg set <id|path>'       'Set wallpaper by cache id, local path, or URL'
    Write-HintRow '8sync bg open <id>'           'Open wallpaper page in browser'
    Write-HintRow '8sync bg rotate [on N|off|time N]' 'Auto-rotate from bg/ every N min (default 5)'
    Write-HintRow '8sync bg list [--preview]'    'List images with links (--preview: inline imgcat)'
    Write-HintRow '8sync bg clear cache'         'Clear wallpaper search cache'
    Write-HintRow '8sync bg remove <name|id|all>' 'Remove downloaded images'

    Write-HintSection 'HELIX EDITOR'
    Write-HintRow '8sync hx lang [name]'    'Install language toolchain via scoop (fzf picker)'
    Write-HintRow '8sync hx health'         'Parse hx --health: show LSP status, suggest missing'
    Write-HintRow '8sync hx wrap'           'Toggle soft word-wrap on/off'
    Write-HintRow '8sync hx opacity <val>'  'Adjust background transparency: +  -  or 0.0-1.0'
    Write-HintRow '8sync hx theme [name]'   'Pick Helix color theme (fzf picker)'
    Write-HintRow '8sync hx bg black'       'Pure black background (glass effect)'
    Write-HintRow '8sync hx bg transparent' 'Transparent bg (terminal bg shows through)'
    Write-HintRow '8sync hx bg reset'       'Restore original theme background'

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
    if (Get-Command Get-CurrentGpuMinPercent -ErrorAction SilentlyContinue) {
        $gpuMin = Get-CurrentGpuMinPercent
        Write-Host ('gpu target: {0}%  (set via: 8sync gpu N)' -f $gpuMin) -ForegroundColor DarkGray
    }
    $glass = Read-CurrentStyleState
    Write-Host ('glass theme: style={0} scene={1} hint={2}' -f $glass.style, $glass.scene, $glass.bgHint) -ForegroundColor DarkGray
    Write-Host ('startup mode: {0}  (override: WEZTERM_STARTUP_MODE=light|balanced)' -f (Get-StartupMode)) -ForegroundColor DarkGray

    if (Test-Path $script:StartupProfilePath) {
        try {
            $spRaw = Get-Content -Raw $script:StartupProfilePath
            $spData = if ($spRaw) { $spRaw | ConvertFrom-Json } else { $null }
            $spArr = if ($spData -is [array]) { @($spData) } elseif ($spData) { @($spData) } else { @() }
            if ($spArr.Count -gt 0) {
                $last = $spArr[$spArr.Count - 1]
                Write-Host ('startup perf: last={0}ms mode={1}' -f $last.totalMs, $last.mode) -ForegroundColor DarkGray
            }
        } catch {
        }
    }
    Write-Host ''
}

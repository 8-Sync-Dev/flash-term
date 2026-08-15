# ---------------------------------------------------------------------------
#  session.ps1 -- `ft session`: manage WezTerm session persistence
#  (resurrect.wezterm plugin state: saved workspaces/windows/tabs).
# ---------------------------------------------------------------------------

# Locate the resurrect plugin state dir under %APPDATA%\wezterm\plugins.
# Returns $null when the plugin has never saved anything (e.g. offline first start).
function Get-SessionStateDir {
    $pluginsDir = Join-Path $env:APPDATA 'wezterm\plugins'
    if (-not (Test-Path $pluginsDir)) { return $null }

    try {
        $dir = Get-ChildItem $pluginsDir -Directory -Filter '*resurrect*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'state' } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        return $dir
    } catch { return $null }
}

function Get-SessionCurrent {
    param([string]$StateDir)
    $file = Join-Path $StateDir 'current_state'
    if (-not (Test-Path $file)) { return $null }
    try {
        $lines = [System.IO.File]::ReadAllLines($file) |
            Where-Object { $_ -and $_.Trim() -ne '' }
        if ($lines.Count -ge 2) {
            return [pscustomobject]@{ Name = $lines[0]; Type = $lines[1] }
        }
    } catch {}
    return $null
}

# Count panes in a resurrect pane_tree. Children live under 'right'/'bottom'
# (sub-trees); left/top/width/height are geometry coordinates, not children.
function Get-SessionPaneCount {
    param($Node)
    if ($null -eq $Node) { return 0 }

    $total = 1
    foreach ($side in @('right', 'bottom')) {
        $child = if ($Node.PSObject.Properties.Name -contains $side) { $Node.$side } else { $null }
        if ($null -ne $child -and $child -isnot [ValueType]) {
            $total += Get-SessionPaneCount -Node $child
        }
    }
    return $total
}

function Show-SessionList {
    param(
        [string]$StateDir,
        [switch]$All
    )

    $current = Get-SessionCurrent -StateDir $StateDir
    if ($current) {
        Write-Host ('  current (auto-restored on WezTerm start): {0}  [{1}]' -f $current.Name, $current.Type) -ForegroundColor Cyan
        Write-Host ''
    }

    $groups = @(
        @{ Label = 'WORKSPACES'; Dir = Join-Path $StateDir 'workspace'; Type = 'workspace' },
        @{ Label = 'WINDOWS';    Dir = Join-Path $StateDir 'window';    Type = 'window' }
    )
    if ($All) {
        $groups += @{ Label = 'TABS'; Dir = Join-Path $StateDir 'tab'; Type = 'tab' }
    }

    foreach ($group in $groups) {
        $files = @()
        if (Test-Path $group.Dir) {
            try {
                $files = Get-ChildItem $group.Dir -Filter '*.json' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending
            } catch {}
        }

        Write-Host ('  {0} ({1})' -f $group.Label, $files.Count) -ForegroundColor White
        if ($files.Count -eq 0) {
            Write-Host '    (none saved yet)' -ForegroundColor DarkGray
        }

        foreach ($f in $files) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $marker = if ($current -and $current.Name -eq $name -and $current.Type -eq $group.Type) { '*' } else { ' ' }
            $meta = ''
            try {
                $json = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($group.Type -eq 'workspace' -and $json.window_states) {
                    $tabCount = 0; $paneCount = 0
                    foreach ($w in @($json.window_states)) {
                        $tabCount += @($w.tabs).Count
                        foreach ($t in @($w.tabs)) {
                            $paneCount += Get-SessionPaneCount -Node $t.pane_tree
                        }
                    }
                    $meta = '{0} window(s), {1} tab(s), {2} pane(s)' -f @($json.window_states).Count, $tabCount, $paneCount
                } elseif ($group.Type -eq 'window' -and $json.tabs) {
                    $paneCount = 0
                    foreach ($t in @($json.tabs)) { $paneCount += Get-SessionPaneCount -Node $t.pane_tree }
                    $meta = '{0} tab(s), {1} pane(s)' -f @($json.tabs).Count, $paneCount
                } elseif ($group.Type -eq 'tab' -and $json.pane_tree) {
                    $meta = '{0} pane(s)' -f (Get-SessionPaneCount -Node $json.pane_tree)
                }
            } catch {}

            Write-Host -NoNewline ('    {0}' -f $marker) -ForegroundColor Green
            Write-Host -NoNewline (' {0,-28}' -f $name) -ForegroundColor White
            Write-Host -NoNewline (' {0,10}  ' -f $f.LastWriteTime.ToString('MM-dd HH:mm')) -ForegroundColor DarkGray
            Write-Host ('{0,7:N0} KB  {1}' -f ($f.Length / 1KB), $meta) -ForegroundColor DarkGray
        }
        Write-Host ''
    }
}

function Invoke-SessionSave {
    # Trigger an instant save via OSC 1337 user var (handled by event_driven_save
    # in wezterm.lua). Only works inside a WezTerm pane.
    if (-not $env:WEZTERM_PANE) {
        Write-Host '  Not inside a WezTerm pane -- cannot trigger a save here.' -ForegroundColor Yellow
        Write-Host '  Open a WezTerm tab and run `ft session save`, or press Ctrl+a Shift+s.' -ForegroundColor DarkGray
        return
    }

    try {
        $stamp = [DateTime]::UtcNow.Ticks.ToString()
        $value = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($stamp))
        $esc = [char]27
        Write-Host -NoNewline ("$esc]1337;SetUserVar=ft_session_save=$value$([char]7)")
        Write-Host '  Save triggered -- workspace state written within a second.' -ForegroundColor Green
        Write-Host '  Run `ft session list` to verify the timestamp.' -ForegroundColor DarkGray
    } catch {
        Write-Host "  Failed to emit save trigger: $_" -ForegroundColor Red
    }
}

function Invoke-SessionRestore {
    param(
        [string]$StateDir,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Host '  Usage: ft session restore <name>' -ForegroundColor Yellow
        Write-Host '  Run `ft session list` to see saved workspace names.' -ForegroundColor DarkGray
        return
    }

    $target = Join-Path (Join-Path $StateDir 'workspace') ($Name + '.json')
    if (-not (Test-Path $target)) {
        Write-Host ('  No saved workspace named "{0}".' -f $Name) -ForegroundColor Red
        Write-Host '  Run `ft session list` to see saved names.' -ForegroundColor DarkGray
        return
    }

    try {
        # current_state = name line + type line; consumed by resurrect_on_gui_startup.
        # Write UTF-8 without BOM (Lua io.open reads it back verbatim).
        [System.IO.File]::WriteAllText((Join-Path $StateDir 'current_state'), "$Name`nworkspace`n", [System.Text.UTF8Encoding]::new($false))
        Write-Host ('  "{0}" staged -- it will be restored the next time WezTerm starts.' -f $Name) -ForegroundColor Green
        Write-Host '  To restore right now in this session: Ctrl+a Shift+r and pick it from the list.' -ForegroundColor DarkGray
    } catch {
        Write-Host "  Failed to stage restore: $_" -ForegroundColor Red
    }
}

function Invoke-SessionDelete {
    param(
        [string]$StateDir,
        [string]$Name,
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Host '  Usage: ft session delete <name> [--force]' -ForegroundColor Yellow
        return
    }

    $target = Join-Path (Join-Path $StateDir 'workspace') ($Name + '.json')
    if (-not (Test-Path $target)) {
        Write-Host ('  No saved workspace named "{0}".' -f $Name) -ForegroundColor Red
        return
    }

    if (-not $Force) {
        Write-Host ('  Delete saved workspace "{0}"? This cannot be undone. [y/N] ' -f $Name) -ForegroundColor Yellow -NoNewline
        $answer = Read-Host
        if ($answer -notmatch '^[Yy]') {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            return
        }
    }

    try {
        Remove-Item $target -Force
        Write-Host ('  Deleted saved workspace "{0}".' -f $Name) -ForegroundColor Green

        # Drop the pointer too if it referenced the deleted save.
        $current = Get-SessionCurrent -StateDir $StateDir
        if ($current -and $current.Name -eq $Name) {
            [System.IO.File]::WriteAllText((Join-Path $StateDir 'current_state'), '', [System.Text.UTF8Encoding]::new($false))
            Write-Host '  (was staged for next-startup restore -- pointer cleared)' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  Failed to delete: $_" -ForegroundColor Red
    }
}

function Show-SessionHelp {
    Write-Host ''
    Write-HintSection 'SESSION -- WezTerm session persistence (resurrect.wezterm)'
    Write-HintRow 'ft session'                 'Show session status + saved workspaces'
    Write-HintRow 'ft session list [--all]'    'List saved workspaces/windows (+tabs with --all)'
    Write-HintRow 'ft session save'            'Save the current workspace right now (also auto every 2 min)'
    Write-HintRow 'ft session restore <name>'  'Stage a saved workspace for the next WezTerm start'
    Write-HintRow 'ft session delete <name>'   'Delete a saved workspace (--force skips confirm)'
    Write-HintRow 'ft session help'            'This help'
    Write-Host ''
    Write-Host '  Keys: Ctrl+a Shift+s save now · Ctrl+a Shift+r fuzzy restore in-session.' -ForegroundColor DarkGray
    Write-Host '  Saved state: layout + pane cwds + screen text. Processes are not resurrected' -ForegroundColor DarkGray
    Write-Host '  (fresh shell per pane; safe TUIs like vim/nvim/claude relaunch automatically).' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-SessionCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    if ($null -eq $Rest) { $Rest = @() }
    $sub = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'status' }
    $subArgs = @($Rest | Select-Object -Skip 1)

    $stateDir = Get-SessionStateDir
    if (-not $stateDir) {
        Write-Host '  No resurrect session state found.' -ForegroundColor Yellow
        Write-Host '  The plugin state appears after WezTerm first saves a session (within ~2 min of startup).' -ForegroundColor DarkGray
        return
    }

    switch ($sub) {
        'help'    { Show-SessionHelp }
        'list'    { Show-SessionList -StateDir $stateDir -All:($subArgs -contains '--all') }
        'save'    { Invoke-SessionSave }
        'restore' { Invoke-SessionRestore -StateDir $stateDir -Name ($subArgs | Where-Object { $_ -notlike '-*' } | Select-Object -First 1) }
        'delete'  { Invoke-SessionDelete -StateDir $stateDir -Name ($subArgs | Where-Object { $_ -notlike '-*' } | Select-Object -First 1) -Force:($subArgs -contains '--force') }
        'status'  {
            $current = Get-SessionCurrent -StateDir $stateDir
            if ($current) {
                Write-Host ('  Session persistence: on (auto-save every 2 min, auto-restore on start)' ) -ForegroundColor Cyan
                Write-Host ('  Next startup restores: {0}  [{1}]' -f $current.Name, $current.Type) -ForegroundColor White
            } else {
                Write-Host '  Session persistence: on, but nothing staged for next-startup restore yet.' -ForegroundColor Cyan
            }
            Write-Host ''
            Show-SessionList -StateDir $stateDir
        }
        default {
            Write-Host ('  Unknown subcommand "{0}".' -f $sub) -ForegroundColor Yellow
            Show-SessionHelp
        }
    }
}

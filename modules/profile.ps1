# ---------------------------------------------------------------------------
#  Profile management — Chrome-like isolated terminal profiles
#  Each profile gets its own .state, generated Lua files, and CLI config dirs.
# ---------------------------------------------------------------------------

$script:ProfilesDir = Join-Path $script:StateDir 'profiles'
$script:ProfileRegistryPath = Join-Path $script:StateDir 'profiles.json'

function Ensure-ProfilesDir {
    if (-not (Test-Path $script:ProfilesDir)) {
        $null = New-Item -Path $script:ProfilesDir -ItemType Directory -Force
    }
}

function Read-ProfileRegistry {
    if (-not (Test-Path $script:ProfileRegistryPath)) {
        return @{ profiles = @() }
    }
    try {
        $raw = Get-Content -Raw $script:ProfileRegistryPath -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        if (-not $data.profiles) { $data | Add-Member -NotePropertyName 'profiles' -NotePropertyValue @() -Force }
        return $data
    } catch {
        return @{ profiles = @() }
    }
}

function Write-ProfileRegistry {
    param([Parameter(Mandatory)]$Data)
    Ensure-StateDir
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ProfileRegistryPath -Encoding UTF8 -Force
}

function Get-ProfileDir {
    param([Parameter(Mandatory)][string]$Name)
    return (Join-Path $script:ProfilesDir $Name)
}

function Get-ActiveProfileName {
    if ($env:WEZTERM_PROFILE -and $env:WEZTERM_PROFILE -ne '') {
        return $env:WEZTERM_PROFILE
    }
    return 'default'
}

# --- State file helpers (per-profile paths) --------------------------------

function Get-ProfileStatePath {
    param([string]$ProfileName, [string]$FileName)
    $dir = Get-ProfileDir -Name $ProfileName
    return (Join-Path $dir $FileName)
}

function Get-ProfileLuaPath {
    param([string]$ProfileName, [string]$BaseName)
    # e.g. current-bg-work.lua or current-bg.lua for default
    $configDir = $PSScriptRoot
    if ($ProfileName -eq 'default') {
        return (Join-Path $configDir "$BaseName.lua")
    }
    return (Join-Path $configDir "$BaseName-$ProfileName.lua")
}

# --- CRUD operations -------------------------------------------------------

function New-TerminalProfile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$CloneFrom
    )

    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        Write-Host "  Invalid profile name '$Name'. Use only letters, digits, hyphens, underscores." -ForegroundColor Red
        return
    }

    Ensure-ProfilesDir
    $profileDir = Get-ProfileDir -Name $Name

    if (Test-Path $profileDir) {
        Write-Host "  Profile '$Name' already exists." -ForegroundColor Red
        return
    }

    if ($CloneFrom) {
        $sourceDir = Get-ProfileDir -Name $CloneFrom
        if (-not (Test-Path $sourceDir)) {
            # If cloning from 'default', use main .state/ as source
            if ($CloneFrom -eq 'default') {
                $sourceDir = $script:StateDir
            } else {
                Write-Host "  Source profile '$CloneFrom' not found." -ForegroundColor Red
                return
            }
        }
        Copy-Item -Path $sourceDir -Destination $profileDir -Recurse -Force
        # Remove nested profiles dir if accidentally copied
        $nestedProfiles = Join-Path $profileDir 'profiles'
        if (Test-Path $nestedProfiles) { Remove-Item $nestedProfiles -Recurse -Force }
        $nestedRegistry = Join-Path $profileDir 'profiles.json'
        if (Test-Path $nestedRegistry) { Remove-Item $nestedRegistry -Force }
        Write-Host "  Profile '$Name' created (cloned from '$CloneFrom')." -ForegroundColor Green
    } else {
        $null = New-Item -Path $profileDir -ItemType Directory -Force
        Write-Host "  Profile '$Name' created (empty)." -ForegroundColor Green
    }

    # Register in profiles.json
    $registry = Read-ProfileRegistry
    $entry = [pscustomobject]@{
        name      = $Name
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        clonedFrom = if ($CloneFrom) { $CloneFrom } else { $null }
    }
    $registry.profiles = @($registry.profiles) + @($entry)
    Write-ProfileRegistry -Data $registry

    # Create per-profile CLI config dir for isolation
    $cliConfigDir = Join-Path $env:USERPROFILE ".claude-profiles\$Name"
    if (-not (Test-Path $cliConfigDir)) {
        $null = New-Item -Path $cliConfigDir -ItemType Directory -Force
    }
    Write-Host "  CLI config dir: $cliConfigDir" -ForegroundColor DarkGray
}

function Get-TerminalProfiles {
    $registry = Read-ProfileRegistry
    $active = Get-ActiveProfileName

    Write-Host ''
    Write-Host '  Terminal Profiles' -ForegroundColor Cyan
    Write-Host ''

    # Always show default
    $isActive = ($active -eq 'default')
    $marker = if ($isActive) { ' *' } else { '  ' }
    $color = if ($isActive) { 'Green' } else { 'White' }
    Write-Host ('  {0} default' -f $marker) -ForegroundColor $color -NoNewline
    Write-Host '  (built-in)' -ForegroundColor DarkGray

    foreach ($p in $registry.profiles) {
        $isActive = ($active -eq $p.name)
        $marker = if ($isActive) { ' *' } else { '  ' }
        $color = if ($isActive) { 'Green' } else { 'White' }
        $extra = ''
        if ($p.clonedFrom) { $extra = "  (cloned from: $($p.clonedFrom))" }
        Write-Host ('  {0} {1}' -f $marker, $p.name) -ForegroundColor $color -NoNewline
        Write-Host $extra -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host "  Active: $active" -ForegroundColor DarkYellow
    Write-Host ''
}

function Switch-TerminalProfile {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -ne 'default') {
        $profileDir = Get-ProfileDir -Name $Name
        if (-not (Test-Path $profileDir)) {
            Write-Host "  Profile '$Name' not found. Use '8sync profile list' to see available profiles." -ForegroundColor Red
            return
        }
    }

    $env:WEZTERM_PROFILE = $Name

    # Set isolated CLI config dir
    $cliConfigDir = Join-Path $env:USERPROFILE ".claude-profiles\$Name"
    if (Test-Path $cliConfigDir) {
        $env:CLAUDE_CONFIG_DIR = $cliConfigDir
    }

    # Point state dir to profile-specific location
    if ($Name -eq 'default') {
        $script:StateDir = Join-Path $PSScriptRoot '.state'
    } else {
        $script:StateDir = $profileDir
    }

    # Reload WezTerm config to pick up per-profile Lua state files
    Try-ReloadWezTerm

    Write-Host "  Switched to profile '$Name'." -ForegroundColor Green
    Write-Host "  WEZTERM_PROFILE=$Name" -ForegroundColor DarkGray
    if ($env:CLAUDE_CONFIG_DIR) {
        Write-Host "  CLAUDE_CONFIG_DIR=$($env:CLAUDE_CONFIG_DIR)" -ForegroundColor DarkGray
    }
}

function Remove-TerminalProfile {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -eq 'default') {
        Write-Host "  Cannot delete the default profile." -ForegroundColor Red
        return
    }

    $profileDir = Get-ProfileDir -Name $Name
    if (-not (Test-Path $profileDir)) {
        Write-Host "  Profile '$Name' not found." -ForegroundColor Red
        return
    }

    $active = Get-ActiveProfileName
    if ($active -eq $Name) {
        Write-Host "  Cannot delete the active profile. Switch to another profile first." -ForegroundColor Red
        return
    }

    Remove-Item -Path $profileDir -Recurse -Force

    # Remove from registry
    $registry = Read-ProfileRegistry
    $registry.profiles = @($registry.profiles | Where-Object { $_.name -ne $Name })
    Write-ProfileRegistry -Data $registry

    # Clean up per-profile Lua state files
    $configDir = $PSScriptRoot
    foreach ($base in @('current-bg', 'current-opacity', 'current-style', 'current-gpu')) {
        $luaFile = Join-Path $configDir "$base-$Name.lua"
        if (Test-Path $luaFile) { Remove-Item $luaFile -Force }
    }

    Write-Host "  Profile '$Name' deleted." -ForegroundColor Green
}

function Open-TerminalProfile {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -ne 'default') {
        $profileDir = Get-ProfileDir -Name $Name
        if (-not (Test-Path $profileDir)) {
            Write-Host "  Profile '$Name' not found. Use '8sync profile list' to see available profiles." -ForegroundColor Red
            return
        }
    }

    # Find wezterm-gui.exe
    $weztermExe = $null
    if (Test-CommandExists 'wezterm-gui') {
        $weztermExe = (Get-Command 'wezterm-gui' -ErrorAction SilentlyContinue).Source
    }
    if (-not $weztermExe) {
        # Try common scoop path
        $scoopPath = Join-Path $env:USERPROFILE 'scoop\apps\wezterm\current\wezterm-gui.exe'
        if (Test-Path $scoopPath) { $weztermExe = $scoopPath }
    }
    if (-not $weztermExe) {
        # Try Program Files
        $pfPath = 'C:\Program Files\WezTerm\wezterm-gui.exe'
        if (Test-Path $pfPath) { $weztermExe = $pfPath }
    }
    if (-not $weztermExe) {
        Write-Host '  Could not find wezterm-gui.exe. Ensure WezTerm is in PATH.' -ForegroundColor Red
        return
    }

    # Build bootstrap command with profile env
    $bootstrapPath = Join-Path $PSScriptRoot 'wezterm-bootstrap.ps1'
    $shell = if (Test-Path (Join-Path $env:USERPROFILE 'scoop\shims\pwsh.exe')) {
        Join-Path $env:USERPROFILE 'scoop\shims\pwsh.exe'
    } else {
        'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    # Set WEZTERM_PROFILE for the new window process
    $env:WEZTERM_PROFILE = $Name

    # Set isolated CLI config dir
    $cliConfigDir = Join-Path $env:USERPROFILE ".claude-profiles\$Name"
    if (Test-Path $cliConfigDir) {
        $env:CLAUDE_CONFIG_DIR = $cliConfigDir
    }

    Start-Process -FilePath $weztermExe -ArgumentList @(
        'start', '--',
        $shell, '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-Command',
        ". '$bootstrapPath'"
    )

    # Restore env in current process
    $env:WEZTERM_PROFILE = Get-ActiveProfileName

    Write-Host "  Opened new WezTerm window with profile '$Name'." -ForegroundColor Green
    Write-Host '  Visual settings (bg, opacity, style) are isolated per window.' -ForegroundColor DarkGray
}

function Show-ProfileHelp {
    Write-Host ''
    Write-HintSection 'PROFILE -- Chrome-like isolated terminal profiles'
    Write-HintRow '8sync profile list'              'List all profiles (* = active)'
    Write-HintRow '8sync profile create <name>'     'Create new empty profile'
    Write-HintRow '8sync profile clone <src> <dst>'  'Clone profile with all settings'
    Write-HintRow '8sync profile switch <name>'     'Switch current tab to profile (CLI/state only)'
    Write-HintRow '8sync profile open <name>'       'Open new WezTerm window with profile (full isolation)'
    Write-HintRow '8sync profile delete <name>'     'Delete a profile (cannot delete active)'
    Write-HintRow '8sync profile help'              'Show this help'
    Write-Host ''
    Write-Host '  switch vs open:' -ForegroundColor Cyan
    Write-Host '    switch  Changes CLI login + state for current tab only.' -ForegroundColor DarkGray
    Write-Host '            Visual (bg/opacity/style) stays shared in the window.' -ForegroundColor DarkGray
    Write-Host '    open    Launches a NEW window with full isolation:' -ForegroundColor DarkGray
    Write-Host '            separate bg, opacity, style, CLI login, state.' -ForegroundColor DarkGray
    Write-Host '            Like Chrome — each profile = its own window.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Each profile isolates:' -ForegroundColor DarkGray
    Write-Host '    - WezTerm visual (bg, opacity, theme, glass) via open' -ForegroundColor DarkGray
    Write-Host '    - CLI accounts (Claude Code, etc.) via CLAUDE_CONFIG_DIR' -ForegroundColor DarkGray
    Write-Host '    - Tool sync state and preferences' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Env vars per profile:' -ForegroundColor DarkGray
    Write-Host '    WEZTERM_PROFILE=<name>    Active profile name' -ForegroundColor DarkGray
    Write-Host '    CLAUDE_CONFIG_DIR=<path>  Isolated Claude Code config' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ProfileCommand {
    param([array]$Rest)

    $sub = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'help' }
    $args2 = if ($Rest.Count -gt 1) { $Rest[1..($Rest.Count - 1)] } else { @() }

    switch ($sub) {
        'list'   { Get-TerminalProfiles }
        'create' {
            if ($args2.Count -lt 1) {
                Write-Host '  Usage: 8sync profile create <name>' -ForegroundColor Yellow
                return
            }
            New-TerminalProfile -Name $args2[0]
        }
        'clone' {
            if ($args2.Count -lt 2) {
                Write-Host '  Usage: 8sync profile clone <source> <destination>' -ForegroundColor Yellow
                return
            }
            New-TerminalProfile -Name $args2[1] -CloneFrom $args2[0]
        }
        'switch' {
            if ($args2.Count -lt 1) {
                Write-Host '  Usage: 8sync profile switch <name>' -ForegroundColor Yellow
                return
            }
            Switch-TerminalProfile -Name $args2[0]
        }
        'open' {
            if ($args2.Count -lt 1) {
                Write-Host '  Usage: 8sync profile open <name>' -ForegroundColor Yellow
                return
            }
            Open-TerminalProfile -Name $args2[0]
        }
        'delete' {
            if ($args2.Count -lt 1) {
                Write-Host '  Usage: 8sync profile delete <name>' -ForegroundColor Yellow
                return
            }
            Remove-TerminalProfile -Name $args2[0]
        }
        'help'   { Show-ProfileHelp }
        default  { Show-ProfileHelp }
    }
}

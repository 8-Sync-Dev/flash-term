#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Shell', 'Hint', 'Status', 'SyncQuiet', 'Sync', 'BgRotate', 'CleanLoop')]
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
$script:BootstrapPath = $PSCommandPath   # full path to wezterm-bootstrap.ps1 — used by bg rotate daemon
$script:StatePath = Join-Path $script:StateDir 'tool-state.json'
$script:SyncLockPath = Join-Path $script:StateDir 'sync.lock'
$script:MissingCachePath = Join-Path $script:StateDir 'missing-cache.json'
$script:MissingCacheTtlSeconds = 300   # 5 minutes
$script:SyncIntervalHours = 72
$script:BgCacheLimit = 50
$script:BgCachePath = Join-Path $script:StateDir 'bg-cache.json'
$script:BgRotatePath = Join-Path $script:StateDir 'bg-rotate.json'
$script:BgRotateDefaultMinutes = 5
$script:BackgroundDir = Join-Path $PSScriptRoot 'bg'
$script:CleanLoopPath = Join-Path $script:StateDir 'clean-loop.json'
$script:CleanLoopDefaultMinutes = 5
$script:CleanLoopLockPath = Join-Path $script:StateDir 'clean-loop.lock'
$script:CleanLoopLockMaxAgeMinutes = 180
$script:CleanLoopDefaultProfile = 'light'
$script:CleanLoopKnownProfiles = @('light', 'balanced', 'deep')
$script:CurrentBgLuaPath = Join-Path $PSScriptRoot 'current-bg.lua'
$script:CurrentStyleLuaPath = Join-Path $PSScriptRoot 'current-style.lua'
$script:CurrentGpuLuaPath = Join-Path $PSScriptRoot 'current-gpu.lua'
$script:StartupProfilePath = Join-Path $script:StateDir 'startup-profile.json'
$script:StartupProfileMaxEntries = 40
$script:StartupModeDefault = 'balanced'
$script:StartupKnownModes = @('light', 'balanced')

$script:HelixConfigDir = Join-Path $env:APPDATA 'helix'
$script:HelixConfigPath = Join-Path $script:HelixConfigDir 'config.toml'
$script:CurrentOpacityPath = Join-Path $PSScriptRoot 'current-opacity.lua'
$script:GpuMinPercentDefault = 10
$script:DefaultOpacity = 0.72
$script:OpacityStep = 0.05
$script:DefaultGlassStyle = 'neon_glass'
$script:DefaultGlassScene = 'focus'
$script:KnownGlassStyles = @('neon_glass', 'ice_glass', 'mint_glass')
$script:KnownGlassScenes = @('focus', 'cinematic', 'showcase')

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

# ---------------------------------------------------------------------------
#  Module loading — each file contains related functions, dot-sourced here.
# ---------------------------------------------------------------------------
$script:ModulesDir = Join-Path $PSScriptRoot 'modules'

. (Join-Path $script:ModulesDir 'core.ps1')
. (Join-Path $script:ModulesDir 'sync.ps1')
. (Join-Path $script:ModulesDir 'shell.ps1')
. (Join-Path $script:ModulesDir 'bg.ps1')
. (Join-Path $script:ModulesDir 'helix.ps1')
. (Join-Path $script:ModulesDir 'clean.ps1')
. (Join-Path $script:ModulesDir 'theme.ps1')
. (Join-Path $script:ModulesDir 'gpu.ps1')
. (Join-Path $script:ModulesDir 'opencode.ps1')
. (Join-Path $script:ModulesDir 'startup.ps1')
. (Join-Path $script:ModulesDir 'gsd.ps1')
. (Join-Path $script:ModulesDir 'gguf.ps1')

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
        'CleanLoop' {
            Invoke-CleanLoopTick
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

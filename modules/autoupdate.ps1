# =============================================================================
# ft autoupdate -- background update + release notification
# =============================================================================
# On every shell start (throttled), checks whether the local flash-term is
# behind origin/main OR a newer GitHub release exists, and prints a one-line
# banner. Modes: notify (default) | auto | off.
#
#   ft autoupdate            Show mode + last check
#   ft autoupdate status     Same, verbose
#   ft autoupdate on|off|auto  Set mode
#   ft autoupdate now        Check immediately (foreground)
# =============================================================================

$script:AutoupdateStatePath = Join-Path $script:StateDir 'autoupdate.json'
$script:AutoupdateNoticePath = Join-Path $script:StateDir 'update-notice.txt'
$script:AutoupdateIntervalHours = 6
$script:AutoupdateDefaultMode = 'notify'

function Get-AutoupdateRoot {
    # flash-term config root = parent of modules/
    Split-Path $PSScriptRoot -Parent
}

function Read-AutoupdateState {
    Ensure-StateDir
    $def = @{ mode = $script:AutoupdateDefaultMode; lastCheckUtc = $null; lastSeenRelease = $null }
    if (Test-Path $script:AutoupdateStatePath) {
        try { foreach ($k in $def.Keys) { if (-not ($_."$k")) {} } ; return (Get-Content -Raw $script:AutoupdateStatePath | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]$def
}

function Write-AutoupdateState {
    param($State)
    Ensure-StateDir
    $obj = [ordered]@{
        mode            = $State.mode
        lastCheckUtc    = $State.lastCheckUtc
        lastSeenRelease = $State.lastSeenRelease
    }
    $obj | ConvertTo-Json | Set-Content -Path $script:AutoupdateStatePath -Encoding UTF8
}

function Get-AutoupdateMode {
    $envMode = $env:FLASH_TERM_AUTOUPDATE
    if ($envMode -in @('notify','auto','off')) { return $envMode }
    return (Read-AutoupdateState).mode
}

function Get-LocalHead {
    param([string]$Root)
    $git = Get-RealGitForUp
    if (-not $git) { return $null }
    return (& $git -C $Root rev-parse --short HEAD 2>$null)
}

function Get-RemoteHead {
    param([string]$Root)
    $git = Get-RealGitForUp
    if (-not $git) { return $null }
    & $git -C $Root ls-remote origin HEAD 2>$null | ForEach-Object { ($_ -split '\s+')[0].Substring(0,7) } | Select-Object -First 1
}

function Get-BehindCount {
    param([string]$Root)
    $git = Get-RealGitForUp
    if (-not $git) { return 0 }
    & $git -C $Root fetch -q origin 2>$null
    $b = & $git -C $Root rev-list --count 'HEAD..origin/HEAD' 2>$null
    if ($b) { return [int]$b }
    return 0
}

function Get-LatestRelease {
    # Returns latest release tag (via gh if present, else API). $null if none.
    $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
    if ($gh) {
        $tag = & $gh release view --repo 8-Sync-Dev/flash-term --json tagName -q '.tagName' 2>$null
        if ($tag) { return $tag }
    }
    try {
        $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/8-Sync-Dev/flash-term/releases/latest' -Headers @{ 'User-Agent' = 'flash-term' } -ErrorAction Stop
        if ($r.tag_name) { return $r.tag_name }
    } catch {}
    return $null
}

function Clear-UpdateNotice { Remove-Item $script:AutoupdateNoticePath -Force -ErrorAction SilentlyContinue }
function Write-UpdateNotice {
    param([string]$Message)
    Ensure-StateDir
    [System.IO.File]::WriteAllText($script:AutoupdateNoticePath, $Message, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-AutoupdateCheck {
    # Foreground check: compares local vs remote + release. Writes a notice if an update exists.
    param([switch]$Quiet)
    $root = Get-AutoupdateRoot
    if (-not (Test-Path (Join-Path $root '.git'))) { return }   # not a git checkout
    $st = Read-AutoupdateState
    if ($st.mode -eq 'off') { Clear-UpdateNotice; return }

    $behind = Get-BehindCount -Root $root
    $release = Get-LatestRelease
    $newRelease = ($release -and $release -ne $st.lastSeenRelease)
    $st.lastCheckUtc = (Get-Date).ToUniversalTime().ToString('o')
    if ($release) { $st.lastSeenRelease = $release }
    Write-AutoupdateState -State $st

    $msg = $null
    if ($behind -gt 0) {
        $msg = "flash-term: $behind commit(s) behind origin/main  ->  run: ft up self"
    }
    if ($newRelease -and $release) {
        $r = "flash-term: new release $release available  ->  run: ft up self"
        $msg = if ($msg) { "$msg`n         $r" } else { $r }
    }

    if ($msg) {
        Write-UpdateNotice -Message $msg
        if (-not $Quiet) { Write-Host '' -ForegroundColor DarkYellow; Write-Host "  >> $msg" -ForegroundColor Yellow; Write-Host '' }
        if ($st.mode -eq 'auto') {
            # Auto-pull in-process (best-effort, ff-only)
            if (Get-Command Update-FlashTermSelf -ErrorAction SilentlyContinue) {
                Update-FlashTermSelf
            }
        }
    } else {
        Clear-UpdateNotice
    }
}

function Start-AutoupdateCheck {
    # Background, throttled launcher (mirrors Start-AutoSync). Runs in a hidden pwsh.
    $st = Read-AutoupdateState
    if ($st.mode -eq 'off') { return }
    $last = $st.lastCheckUtc
    if ($last) {
        try {
            $elapsed = ((Get-Date).ToUniversalTime() - [datetime]$last).TotalHours
            if ($elapsed -lt $script:AutoupdateIntervalHours) { return }
        } catch {}
    }
    $engine = Get-ShellEngine
    if (-not (Test-Path $engine)) { return }
    $args = @('-NoProfile','-NoLogo','-ExecutionPolicy','Bypass','-File',(Join-Path (Get-AutoupdateRoot) 'wezterm-bootstrap.ps1'),'-Task','AutoupdateCheck')
    try { Start-Process -FilePath $engine -ArgumentList $args -WindowStyle Hidden -ErrorAction Stop | Out-Null } catch {}
}

function Show-AutoupdateNotice {
    # Print the pending notice once per WezTerm process (uses wezterm.GLOBAL-like flag).
    if ($script:AutoupdateNoticeShown) { return }
    $script:AutoupdateNoticeShown = $true
    if (Test-Path $script:AutoupdateNoticePath) {
        $msg = (Get-Content -Raw $script:AutoupdateNoticePath -ErrorAction SilentlyContinue).Trim()
        if ($msg) {
            Write-Host ''
            Write-Host '  >> update available:' -ForegroundColor Yellow
            foreach ($line in ($msg -split "`n")) { Write-Host "     $line" -ForegroundColor Yellow }
            Write-Host ''
        }
    }
}

function Show-AutoupdateHelp {
    Write-Host ''
    Write-Host '  FT AUTOUPDATE' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow 'ft autoupdate'           'Show mode + last check time'
    Write-HintRow 'ft autoupdate on'        'Enable notify mode (banner when update available)'
    Write-HintRow 'ft autoupdate off'       'Disable checks'
    Write-HintRow 'ft autoupdate auto'      'Auto-pull on startup when behind (ff-only)'
    Write-HintRow 'ft autoupdate now'       'Check immediately (foreground)'
    Write-Host ''
}

function Invoke-AutoupdateCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $sub = if ($Rest -and $Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { '' }
    switch ($sub) {
        'on'      { $mode = 'notify' }
        'auto'    { $mode = 'auto' }
        'off'     { $mode = 'off' }
        default   { $mode = $null }
    }
    if ($mode) {
        $st = Read-AutoupdateState; $st.mode = $mode; Write-AutoupdateState -State $st
        Write-Host "  autoupdate mode -> $mode" -ForegroundColor Green
        return
    }
    if ($sub -eq 'now') { Invoke-AutoupdateCheck; return }
    # status (default)
    $st = Read-AutoupdateState
    Write-Host ''
    Write-Host '  autoupdate' -ForegroundColor Cyan
    Write-Host ("    mode:            {0}" -f $st.mode) -ForegroundColor DarkGray
    Write-Host ("    last check UTC:  {0}" -f $(if($st.lastCheckUtc){$st.lastCheckUtc}else{'never'})) -ForegroundColor DarkGray
    Write-Host ("    last release:    {0}" -f $(if($st.lastSeenRelease){$st.lastSeenRelease}else{'none yet'})) -ForegroundColor DarkGray
    Write-Host ("    interval:        {0}h" -f $script:AutoupdateIntervalHours) -ForegroundColor DarkGray
    Write-Host ''
}
